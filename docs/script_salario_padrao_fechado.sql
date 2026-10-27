-- ============================================================================
-- ENTREGA — Salario (passo 2.3, 1a fatia): fechado por padrao + contratos de experiencia mascarados
-- Cole no SQL Editor (TESTE e HOMOLOGACAO primeiro; depois PRODUCAO). UMA transacao, idempotente.
-- Altera DADO: desliga "Pode ver salario" nos perfis "Colaborador (padrao)" que estavam ligados. Antes copia essas linhas
-- para backup_perfis_salario_20261023 (a tabela e criada por EXECUTE, de proposito, por causa do RLS automatico do editor).
-- Cria 1 visao, 1 funcao e 1 gatilho nos contratos de experiencia. Perfis criados pelos clientes NAO sao tocados.
-- ORDEM com as telas: aplique ESTE script ANTES de publicar as telas (a tela de contratos passa a ler a visao nova).
-- Rode ANTES a consulta_salario_perfis.sql. Termina com UMA conferencia SELECT.
-- ============================================================================
SET lock_timeout = '10s';

-- ── 1) padrao fechado ────────────────────────────────────────────────────────
DO $pad$
BEGIN
  IF to_regclass('public.perfis_acesso') IS NULL THEN
    RAISE NOTICE 'perfis_acesso ausente; nada a fazer.';
    RETURN;
  END IF;

  ALTER TABLE public.perfis_acesso ALTER COLUMN pode_ver_salario SET DEFAULT false;

  -- copia das linhas que serao alteradas (a tabela e criada por EXECUTE para o editor de SQL nao acionar o RLS automatico)
  IF to_regclass('public.backup_perfis_salario_20261023') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.backup_perfis_salario_20261023 AS '
         || 'SELECT id, tenant_id, nome, pode_ver_salario, now() AS copiado_em FROM public.perfis_acesso '
         || 'WHERE nome = ''Colaborador (padrão)'' AND pode_ver_salario = true';
  END IF;

  UPDATE public.perfis_acesso
     SET pode_ver_salario = false
   WHERE nome = 'Colaborador (padrão)' AND pode_ver_salario = true;

  RAISE NOTICE 'Salario: padrao fechado e Colaborador (padrao) desligado.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENCAO: padrao de salario nao foi fechado: %', SQLERRM;
END $pad$;

-- ── 2) contratos de experiencia ──────────────────────────────────────────────
DO $ctr$
DECLARE
  v_cols text;
BEGIN
  IF to_regclass('public.contratos_experiencia') IS NULL THEN
    RAISE NOTICE 'contratos_experiencia ausente; nada a fazer.';
    RETURN;
  END IF;

  -- atribuicao por subconsulta escalar (o editor de SQL de producao confunde a forma curta com criacao de tabela)
  v_cols := (SELECT string_agg(
               CASE WHEN column_name = 'salario'
                    THEN 'CASE WHEN public.pode_ver_salario(c.tenant_id) THEN c.salario ELSE NULL END AS salario'
                    ELSE 'c.' || quote_ident(column_name)
               END,
               ', ' ORDER BY ordinal_position)
               FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'contratos_experiencia');

  EXECUTE 'CREATE OR REPLACE VIEW public.contratos_experiencia_segura '
       || 'WITH (security_invoker = true) AS SELECT ' || v_cols
       || ' FROM public.contratos_experiencia c';
  GRANT SELECT ON public.contratos_experiencia_segura TO authenticated;
  COMMENT ON VIEW public.contratos_experiencia_segura IS
    'Leitura de contratos_experiencia com salario mascarado por pode_ver_salario(). A tela le por aqui; escritas seguem na tabela. Se a tabela ganhar colunas, rodar de novo esta criacao.';
  RAISE NOTICE 'Salario: visao contratos_experiencia_segura criada.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENCAO: visao dos contratos nao criada: %', SQLERRM;
END $ctr$;

CREATE OR REPLACE FUNCTION public.contratos_preserva_salario_mascarado()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $fn$
BEGIN
  -- quem nao pode ver o salario nao o altera (um salvamento com o campo mascarado nao pode apagar o valor real)
  IF NOT public.pode_ver_salario(NEW.tenant_id) THEN
    NEW.salario := OLD.salario;
  END IF;
  RETURN NEW;
END;
$fn$;

DO $trg$
BEGIN
  IF to_regclass('public.contratos_experiencia') IS NULL THEN
    RETURN;
  END IF;
  DROP TRIGGER IF EXISTS trg_contratos_preserva_salario ON public.contratos_experiencia;
  CREATE TRIGGER trg_contratos_preserva_salario
    BEFORE UPDATE ON public.contratos_experiencia
    FOR EACH ROW EXECUTE FUNCTION public.contratos_preserva_salario_mascarado();
  RAISE NOTICE 'Salario: gatilho de preservacao nos contratos criado.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENCAO: gatilho de preservacao dos contratos nao criado: %', SQLERRM;
END $trg$;

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT
  (SELECT pg_get_expr(d.adbin, d.adrelid) FROM pg_attrdef d JOIN pg_attribute a ON a.attrelid = d.adrelid AND a.attnum = d.adnum
    WHERE d.adrelid = 'public.perfis_acesso'::regclass AND a.attname = 'pode_ver_salario')                         AS padrao_do_perfil,
  (SELECT count(*) FROM public.perfis_acesso WHERE nome = 'Colaborador (padrão)' AND pode_ver_salario)             AS colaborador_padrao_ainda_ve,
  (SELECT count(*) FROM public.backup_perfis_salario_20261023)                                                     AS linhas_no_backup,
  (SELECT count(*) FROM pg_views WHERE schemaname = 'public' AND viewname = 'contratos_experiencia_segura')        AS visao_dos_contratos,
  (SELECT count(*) FROM pg_trigger WHERE tgname = 'trg_contratos_preserva_salario' AND NOT tgisinternal)           AS gatilho_dos_contratos;
-- Esperado: false, 0, (quantos estavam ligados), 1 e 1.
--
-- DESFAZER o desligamento dos Colaborador (padrao): 
--   UPDATE public.perfis_acesso p SET pode_ver_salario = true FROM public.backup_perfis_salario_20261023 b WHERE p.id = b.id;
-- e o padrao: ALTER TABLE public.perfis_acesso ALTER COLUMN pode_ver_salario SET DEFAULT true;
