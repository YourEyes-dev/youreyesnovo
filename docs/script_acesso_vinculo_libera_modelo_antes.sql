-- ============================================================================
-- ENTREGA — Vincular perfil escolhido nao falha mais no indice unico (gatilho BEFORE)
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de HOMOLOGACAO primeiro e,
-- so depois de conferido, no de PRODUCAO. Espelha a migration
-- 20261018174413_acesso_vinculo_libera_modelo_antes.sql
--
-- Roda em UMA transacao, idempotente. SET lock_timeout evita travar a tabela movimentada.
-- Cria uma FUNCAO e UM gatilho (so na tabela usuario_perfil_vinculos) e documenta o caso
-- de QA PERFIL-017. NAO cria tabela, NAO altera nem apaga nenhum vinculo existente.
--
-- O QUE CORRIGE: ao cadastrar um usuario escolhendo um perfil (ou vincular um perfil a quem
-- ja tem o modelo do tipo), a tela falhava com "duplicate key ... usuario_perfil_vinculos_ativo_uidx"
-- e o usuario ficava com o modelo do tipo (acesso amplo, no caso de Gestor/Administrador) em
-- vez do perfil escolhido. Usuarios JA cadastrados com esse erro NAO sao corrigidos por este
-- script: use a lista de apoio e vincule o perfil certo pela tela de Perfis depois de aplica-lo.
-- ============================================================================

SET lock_timeout = '10s';

-- Vincular perfil ESCOLHIDO a quem ja tem o vinculo automatico (modelo do tipo) falhava com
-- "duplicate key value violates unique constraint usuario_perfil_vinculos_ativo_uidx".
--
-- Causa: o indice unico permite UM vinculo ativo por usuario e empresa. O cadastro de
-- usuario cria o vinculo automatico (Colaborador padrao, e desde a Fase 1b tambem Gestor
-- padrao e Administrador padrao) e, logo depois, a tela grava o perfil escolhido como
-- ativo. O gatilho que desativa o automatico (trg_substituir_perfil_padrao) roda DEPOIS do
-- insert (AFTER), mas o indice e checado DURANTE o insert: o erro vem antes. Resultado: o
-- usuario ficava com o modelo do tipo (acesso amplo, no caso do gestor) em vez do perfil
-- que o RH escolheu. O mesmo vale para vincular perfil a usuario existente pela tela de Perfis.
--
-- Correcao: um gatilho BEFORE INSERT/UPDATE desativa os vinculos ativos de sistema
-- (padrao_sistema) do mesmo usuario e da mesma empresa ANTES de o novo ser gravado, abrindo
-- espaco para ele. Nao mexe em vinculo de perfil escolhido pelo RH: dois perfis escolhidos
-- ativos para o mesmo usuario e empresa continuam barrados pelo indice, de proposito.
CREATE OR REPLACE FUNCTION public.trg_vinculo_libera_modelo_antes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  IF COALESCE(NEW.ativo, true) = true THEN
    UPDATE public.usuario_perfil_vinculos v
       SET ativo = false,
           is_perfil_principal = false,
           observacao = COALESCE(v.observacao, '')
             || ' [desativado: outro perfil vinculado em ' || to_char(now(), 'DD/MM/YYYY') || ']'
      FROM public.perfis_acesso pa
     WHERE pa.id = v.perfil_id
       AND pa.tipo::text = 'padrao_sistema'
       AND v.usuario_id = NEW.usuario_id
       AND v.id IS DISTINCT FROM NEW.id
       AND v.perfil_id IS DISTINCT FROM NEW.perfil_id
       AND COALESCE(v.ativo, true) = true
       AND COALESCE(v.empresa_id, '00000000-0000-0000-0000-000000000000'::uuid)
         = COALESCE(NEW.empresa_id, '00000000-0000-0000-0000-000000000000'::uuid);
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'vinculo: modelo anterior nao desativado para %: % (%)', NEW.usuario_id, SQLERRM, SQLSTATE;
  RETURN NEW;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.trg_vinculo_libera_modelo_antes() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_vinculo_libera_modelo_antes ON public.usuario_perfil_vinculos;
CREATE TRIGGER trigger_vinculo_libera_modelo_antes
BEFORE INSERT OR UPDATE OF ativo, perfil_id, empresa_id ON public.usuario_perfil_vinculos
FOR EACH ROW EXECUTE FUNCTION public.trg_vinculo_libera_modelo_antes();

-- QA PERFIL-017: o gatilho existe, e BEFORE e desativa o vinculo de sistema (auditoria da
-- estrutura, somente leitura).
CREATE OR REPLACE FUNCTION public.qa_caso_perfil_017()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_falhas text[] := ARRAY[]::text[];
  v_def text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): gatilho BEFORE que libera o modelo do tipo ao vincular um perfil';
  r.esperado    := 'Gatilho BEFORE INSERT em usuario_perfil_vinculos que desativa o vinculo de sistema (padrao_sistema) do mesmo usuario e empresa';

  IF NOT EXISTS (SELECT 1 FROM pg_trigger t
                  WHERE t.tgrelid = 'public.usuario_perfil_vinculos'::regclass
                    AND t.tgname = 'trigger_vinculo_libera_modelo_antes'
                    AND NOT t.tgisinternal AND t.tgenabled <> 'D'
                    AND (t.tgtype & 2) = 2 AND (t.tgtype & 4) = 4) THEN
    v_falhas := v_falhas || 'gatilho BEFORE INSERT trigger_vinculo_libera_modelo_antes ausente ou desabilitado'::text;
  END IF;

  v_def := COALESCE(pg_get_functiondef(to_regprocedure('public.trg_vinculo_libera_modelo_antes()')), '');
  IF position('padrao_sistema' IN v_def) = 0 OR position('ativo = false' IN v_def) = 0 THEN
    v_falhas := v_falhas || 'função do gatilho não desativa o vínculo de sistema'::text;
  END IF;

  IF COALESCE(array_length(v_falhas, 1), 0) = 0 THEN
    r.situacao := 'passou';
    r.obtido   := 'Gatilho BEFORE presente: vincular um perfil libera o modelo do tipo antes do índice único.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := array_to_string(v_falhas, '; ');
    r.detalhe  := jsonb_build_object('falhas', to_jsonb(v_falhas));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $$;

DO $qa$
DECLARE v_mod uuid;
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL OR to_regclass('public.qa_modulos') IS NULL THEN
    RAISE NOTICE 'Motor de QA ausente nesta base; caso PERFIL-017 nao documentado.';
    RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'seguranca-acesso/perfis' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; caso PERFIL-017 nao documentado.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado)
  VALUES
  (v_mod, 'PERFIL-017', 'Vincular um perfil escolhido a quem tem o modelo do tipo não falha no índice único',
   'feliz', 'alta', 'aprovado', 'api',
   'LGPD, art. 46',
   'O índice usuario_perfil_vinculos_ativo_uidx permite um vínculo ativo por usuário e empresa. O cadastro cria o vínculo automático (modelo do tipo) e a tela grava o perfil escolhido; sem um gatilho BEFORE que libere o modelo, o insert falha e o usuário fica com o acesso amplo do modelo em vez do perfil escolhido.',
   'Gatilho trigger_vinculo_libera_modelo_antes aplicado.',
   '[{"ordem":1,"acao":"Conferir o gatilho BEFORE INSERT em usuario_perfil_vinculos e a função que desativa o vínculo de padrao_sistema do mesmo usuário e empresa","resultado_esperado":"Gatilho presente e habilitado"}]',
   'Gatilho BEFORE presente e funcional.')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
      ('PERFIL-017', 'qa_caso_perfil_017', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao PERFIL-017 nao registrada: %', SQLERRM;
END $qa$;

-- ── Conferencia (o editor mostra so o ultimo resultado) ─────────────────────
-- Esperado: gatilho_esperado_1 = 1 e qa_perfil_017 = passou.
SELECT
  (SELECT count(*) FROM pg_trigger t
    WHERE t.tgrelid = 'public.usuario_perfil_vinculos'::regclass
      AND t.tgname = 'trigger_vinculo_libera_modelo_antes' AND NOT t.tgisinternal) AS gatilho_esperado_1,
  (SELECT count(*) FROM public.qa_casos_teste WHERE codigo = 'PERFIL-017')           AS caso_qa_esperado_1,
  (public.qa_caso_perfil_017()).situacao::text                                       AS qa_perfil_017;

-- ── DESFAZER (so se precisar; rode em separado) ─────────────────────────────
--   DROP TRIGGER IF EXISTS trigger_vinculo_libera_modelo_antes ON public.usuario_perfil_vinculos;
--   DROP FUNCTION IF EXISTS public.trg_vinculo_libera_modelo_antes();
-- Vinculos que o gatilho desativou levam, na observacao, "[desativado: outro perfil vinculado em ...]".
