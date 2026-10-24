-- ============================================================================
-- CADASTRO DE USUARIOS (usuarios_base) — PARTE 2: leitura e escrita pelo perfil + protecao contra autopromocao
--
-- ANTES: qualquer membro da empresa lia a ficha de todos (e-mail, CPF, telefone, tipo, status, codigo de convite) e podia
-- ALTERAR qualquer linha, inclusive o proprio tipo (colaborador -> administrador), o status e a empresa. So a tela impedia.
--
-- AGORA (RESTRICTIVE, somam-se as politicas antigas; so APERTAM):
--   LEITURA   a PROPRIA linha (menu, permissoes, sessao, Meu Perfil) ou quem tem Usuarios, Configuracoes ou Perfis & Acessos
--             em escopo alem do proprio. Os seletores de pessoas usam usuarios_diretorio() (PARTE 1).
--   INSERIR   quem tem Usuarios/Configuracoes E o verbo criar no perfil.
--   ALTERAR   a propria linha (limitada pelo gatilho abaixo) ou quem tem Usuarios/Configuracoes E o verbo editar.
--   EXCLUIR   continua sem politica: ninguem exclui por aqui.
--   GATILHO   ninguem (exceto dono da empresa e Super Admin) troca na PROPRIA linha o tipo, o status, o CPF, o e-mail, a conta de
--             login, a validacao ou o convite; ninguem troca a empresa de uma linha. So nome, foto e demais dados de perfil.
--   Sem perfil vinculado vale o legado por papel (gestao), como nas demais travas.
-- Rotinas internas (security definer) e funcoes de borda (chave de servico) nao mudam. Nenhum dado e alterado. Idempotente.
-- RODE SO DEPOIS de a PARTE 1 estar aplicada E as telas novas publicadas.
-- ============================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.usuarios_base_protege()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_novo jsonb;
  v_velho jsonb;
  v_campo text;
BEGIN
  -- Chave de servico / SQL Editor (sem usuario) e Super Admin passam.
  IF v_uid IS NULL OR public.is_superadmin(v_uid) THEN
    RETURN NEW;
  END IF;

  v_novo := to_jsonb(NEW);
  v_velho := to_jsonb(OLD);

  IF v_novo->'tenant_id' IS DISTINCT FROM v_velho->'tenant_id' THEN
    RAISE EXCEPTION 'A empresa de um cadastro de usuario nao pode ser alterada.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Na PROPRIA linha, so o dono da empresa mexe nos campos de privilegio e de identidade.
  IF OLD.auth_user_id = v_uid AND NOT public.ye_eh_dono(v_uid, OLD.tenant_id) THEN
    FOREACH v_campo IN ARRAY ARRAY['auth_user_id', 'tipo_usuario', 'status', 'cpf', 'email_principal', 'email_validado',
                                    'telefone_validado', 'convite_token', 'convite_enviado_em', 'convite_expira_em',
                                    'convite_aceito_em', 'origem_cadastro'] LOOP
      IF v_novo->v_campo IS DISTINCT FROM v_velho->v_campo THEN
        RAISE EXCEPTION 'Voce nao pode alterar o proprio campo "%". Peca a um responsavel pelos acessos.', v_campo
          USING ERRCODE = 'insufficient_privilege';
      END IF;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$fn$;

DO $ub$
BEGIN
  IF to_regclass('public.usuarios_base') IS NULL THEN
    RAISE NOTICE 'usuarios_base ausente nesta base; nada a fazer.';
    RETURN;
  END IF;

  ALTER TABLE public.usuarios_base ENABLE ROW LEVEL SECURITY;

  DROP TRIGGER IF EXISTS trg_usuarios_base_protege ON public.usuarios_base;
  CREATE TRIGGER trg_usuarios_base_protege
    BEFORE UPDATE ON public.usuarios_base
    FOR EACH ROW EXECUTE FUNCTION public.usuarios_base_protege();

  DROP POLICY IF EXISTS perfil_restringe_leitura_usuarios_base ON public.usuarios_base;
  DROP POLICY IF EXISTS perfil_restringe_escrita_usuarios_base_ins ON public.usuarios_base;
  DROP POLICY IF EXISTS perfil_restringe_escrita_usuarios_base_upd ON public.usuarios_base;

  CREATE POLICY perfil_restringe_leitura_usuarios_base ON public.usuarios_base
    AS RESTRICTIVE FOR SELECT TO authenticated
    USING (
      auth_user_id = auth.uid()
      OR public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['usuarios','configuracoes','perfis_acesso']::text[])
    );

  CREATE POLICY perfil_restringe_escrita_usuarios_base_ins ON public.usuarios_base
    AS RESTRICTIVE FOR INSERT TO authenticated
    WITH CHECK (
      public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['usuarios','configuracoes']::text[])
      AND public.perfil_escreve(tenant_id, ARRAY['usuarios','configuracoes']::text[], ARRAY['criar']::text[], NULL)
    );

  CREATE POLICY perfil_restringe_escrita_usuarios_base_upd ON public.usuarios_base
    AS RESTRICTIVE FOR UPDATE TO authenticated
    USING (
      auth_user_id = auth.uid()
      OR (public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['usuarios','configuracoes']::text[])
          AND public.perfil_escreve(tenant_id, ARRAY['usuarios','configuracoes']::text[], ARRAY['editar','aprovar']::text[], NULL))
    )
    WITH CHECK (
      auth_user_id = auth.uid()
      OR (public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['usuarios','configuracoes']::text[])
          AND public.perfil_escreve(tenant_id, ARRAY['usuarios','configuracoes']::text[], ARRAY['editar','aprovar']::text[], NULL))
    );

  RAISE NOTICE 'usuarios_base: leitura, escrita e protecao contra autopromocao aplicadas.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENCAO: usuarios_base ficou SEM a trava: %', SQLERRM;
END $ub$;
