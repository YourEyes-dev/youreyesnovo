-- ============================================================================
-- ENTREGA — cadastro de usuarios (usuarios_base), PARTE 2: trava de leitura/escrita + protecao contra autopromocao
-- RODE SO DEPOIS de: (1) script_usuarios_funcoes_leitura.sql (PARTE 1) aplicado, (2) as TELAS NOVAS PUBLICADAS (Vercel) —
-- sem elas o seletor de gestor e o responsavel da Ouvidoria ficam vazios — e (3) conferida a consulta_usuarios_base_quem_muda.sql.
-- Nenhum dado e alterado; so aperta politicas e cria um gatilho. Idempotente.
-- Para desfazer: DROP POLICY perfil_restringe_leitura_usuarios_base / perfil_restringe_escrita_usuarios_base_ins / _upd e
-- DROP TRIGGER trg_usuarios_base_protege ON public.usuarios_base.
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

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename='usuarios_base'
         AND policyname IN ('perfil_restringe_leitura_usuarios_base','perfil_restringe_escrita_usuarios_base_ins','perfil_restringe_escrita_usuarios_base_upd')) AS politicas_novas_esperado_3,
       (SELECT count(*) FROM pg_trigger WHERE tgrelid='public.usuarios_base'::regclass AND tgname='trg_usuarios_base_protege' AND NOT tgisinternal) AS gatilho_esperado_1;
