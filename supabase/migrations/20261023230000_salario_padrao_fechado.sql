-- ============================================================================
-- SALARIO (passo 2.3, primeira fatia): fechado por padrao + contratos de experiencia mascarados
--
-- 1) PADRAO FECHADO. perfis_acesso.pode_ver_salario nascia LIGADO (default true): todo perfil novo, inclusive o
--    "Colaborador (padrao)" criado automaticamente, enxergava o salario de todos. Decisao do dono do produto (10/2026):
--    menos acesso por omissao; o RH libera depois. Agora:
--      * o padrao da coluna passa a ser DESLIGADO (perfis novos e o Colaborador (padrao) criado daqui para frente);
--      * os perfis "Colaborador (padrao)" que ja existem e estao ligados sao DESLIGADOS (copia das linhas em
--        backup_perfis_salario_20261023, com o comando de desfazer no fim). Perfis criados pelos clientes NAO sao
--        tocados: a consulta consulta_salario_perfis.sql lista quais ainda veem salario para decidirem com o cliente.
--    O proprio holerite da pessoa continua visivel (a regra da folha libera o proprio CPF).
--
-- 2) CONTRATOS DE EXPERIENCIA. contratos_experiencia.salario e uma COPIA do salario da admissao e nao tinha mascara.
--    Mesmo desenho do cadastro: visao contratos_experiencia_segura (security_invoker; salario so para quem pode ver) que
--    a tela passa a ler, e um gatilho que preserva o salario quando quem nao pode ver salva o contrato.
--
-- Limite conhecido (nao resolvido aqui): quem ja tem acesso as linhas da tabela de origem e nao tem permissao de salario
-- ainda consegue ler a COLUNA pela API direta, porque o Postgres nao mascara coluna por usuario. Fechar isso exige
-- separar o salario em tabela propria (passo proprio) ou travar quem le a linha (passo da leitura do cadastro).
-- Idempotente. Nao apaga dado.
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
