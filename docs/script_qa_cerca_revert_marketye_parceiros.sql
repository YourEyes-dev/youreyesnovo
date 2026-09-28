-- ============================================================================
-- ENTREGA — Revert de cerca em duas tabelas multi-tenant (marketye/parceiros)
--
-- Cole no SQL Editor da HOMOLOGAÇÃO primeiro; só depois de conferido, na
-- PRODUÇÃO. É o MESMO script nos dois (forward-only).
--
-- POR QUÊ: o instalador genérico de cercas do QA (qa_instalar_cercas) instala a
-- trava qa_guarda_cercado em TODA tabela de public com tenant_id. Rodá-lo para
-- alcançar duas tabelas de ponto acabou cercando também duas que NUNCA tiveram
-- cerca e que são multi-tenant por desenho:
--   · marketplace_demanda_latente  (agrega células de várias empresas)
--   · parceiro_mrr_snapshots        (snapshot de MRR por cliente do parceiro)
-- As rotinas de QA desses módulos (MKY-005, MKY-065, PGP-010/012/013) criam
-- tenants sintéticos próprios e escrevem neles — a cerca, em modo de teste,
-- passou a bloquear e reprovar os casos. Este script tira a cerca SÓ dessas
-- duas e ensina o instalador/vigia a pulá-las, para não reabrir a regressão.
-- As tabelas de ponto (ponto_expurgo_eventos, ponto_retrato_pre) continuam
-- cercadas de propósito.
--
-- SEGURANÇA: a trava do cercado é NO-OP fora do modo de teste (só age com
-- app.qa_modo = 'on'); tirá-la dessas duas não muda nada na operação normal.
-- Não cria tabela (sem risco do auto-RLS do editor). Idempotente. Roda numa
-- transação: se algo falhar, desfaz tudo sozinho.
--
-- OBS sobre a limpeza de qa_tabelas_protegidas: são 2 linhas de um REGISTRO
-- interno do QA (não é dado de cliente), triviais de refazer. Por isso não se
-- guarda tabela de backup aqui — criar tabela num script que também troca
-- funções acionaria o auto-RLS do editor e corromperia os corpos. O desfazer,
-- se um dia for preciso, é reinserir as duas linhas:
--   INSERT INTO public.qa_tabelas_protegidas (tabela, motivo) VALUES
--     ('marketplace_demanda_latente','Cerca generica: tabela tem tenant_id'),
--     ('parceiro_mrr_snapshots','Cerca generica: tabela tem tenant_id')
--   ON CONFLICT DO NOTHING;
-- ============================================================================

SET lock_timeout = '10s';

-- 1) Tira o gatilho das duas tabelas (se houver) e limpa o registro
DO $revert$
DECLARE
  c text;
  v_excecoes CONSTANT text[] := ARRAY['marketplace_demanda_latente', 'parceiro_mrr_snapshots'];
BEGIN
  FOREACH c IN ARRAY v_excecoes LOOP
    IF to_regclass('public.' || quote_ident(c)) IS NULL THEN
      RAISE NOTICE 'Tabela public.% nao existe nesta base — nada a reverter.', c;
      CONTINUE;
    END IF;
    IF EXISTS (
      SELECT 1 FROM pg_trigger tg
      WHERE tg.tgname = 'qa_guarda_cercado'
        AND tg.tgrelid = ('public.' || quote_ident(c))::regclass
        AND NOT tg.tgisinternal
    ) THEN
      EXECUTE format('DROP TRIGGER qa_guarda_cercado ON public.%I', c);
      RAISE NOTICE 'Cerca removida de public.%.', c;
    ELSE
      RAISE NOTICE 'public.% ja estava sem a cerca.', c;
    END IF;
    IF to_regclass('public.qa_tabelas_protegidas') IS NOT NULL THEN
      DELETE FROM public.qa_tabelas_protegidas WHERE tabela = c;
    END IF;
  END LOOP;
END $revert$;

-- 2) Instalador genérico passa a PULAR essas duas tabelas
DO $patch$
BEGIN
  IF to_regprocedure('public.qa_instalar_cercas()') IS NULL THEN
    RAISE NOTICE 'qa_instalar_cercas() ausente — nada a ajustar.';
    RETURN;
  END IF;

  CREATE OR REPLACE FUNCTION public.qa_instalar_cercas()
  RETURNS TABLE(nome_tabela text, acao text)
  LANGUAGE plpgsql
  AS $fn$
  DECLARE
    c        record;
    v_tinha  boolean;
    v_novas  int := 0;
    v_ja     int := 0;
    -- Tabelas multi-tenant POR DESENHO, que nunca tiveram cerca. Ficam de fora
    -- de proposito (cerca-las reprova MKY-005/065 e PGP-010/012/013).
    v_excecoes CONSTANT text[] := ARRAY['marketplace_demanda_latente', 'parceiro_mrr_snapshots'];
  BEGIN
    IF to_regprocedure('public.qa_bloqueia_fora_do_cercado()') IS NULL THEN
      RAISE EXCEPTION 'qa_bloqueia_fora_do_cercado() nao existe — rode as migrations do cercado antes.';
    END IF;

    FOR c IN
      SELECT col.table_name
      FROM information_schema.columns col
      JOIN information_schema.tables t
        ON t.table_schema = col.table_schema AND t.table_name = col.table_name
      WHERE col.table_schema = 'public'
        AND col.column_name  = 'tenant_id'
        AND t.table_type     = 'BASE TABLE'
        AND col.table_name NOT LIKE 'qa\_%'
        AND col.table_name <> ALL (v_excecoes)
      ORDER BY col.table_name
    LOOP
      SELECT EXISTS (
        SELECT 1 FROM pg_trigger tg
        WHERE tg.tgname = 'qa_guarda_cercado'
          AND tg.tgrelid = ('public.' || quote_ident(c.table_name))::regclass
          AND NOT tg.tgisinternal
      ) INTO v_tinha;

      IF NOT v_tinha THEN
        EXECUTE format(
          'CREATE TRIGGER qa_guarda_cercado
             BEFORE INSERT OR UPDATE OR DELETE ON public.%I
             FOR EACH ROW EXECUTE FUNCTION public.qa_bloqueia_fora_do_cercado()',
          c.table_name);
        v_novas := v_novas + 1;
        nome_tabela := c.table_name; acao := 'trava instalada'; RETURN NEXT;
      ELSE
        v_ja := v_ja + 1;
      END IF;

      INSERT INTO public.qa_tabelas_protegidas AS p (tabela, motivo)
      SELECT c.table_name, 'Cerca generica: tabela tem tenant_id'
      WHERE NOT EXISTS (SELECT 1 FROM public.qa_tabelas_protegidas x
                        WHERE x.tabela = c.table_name);
    END LOOP;

    nome_tabela := format('%s tabela(s) ja protegida(s), %s nova(s)', v_ja, v_novas);
    acao        := 'resumo';
    RETURN NEXT;
  END $fn$;
END $patch$;

-- 3) Vigia da cerca também passa a reconhecer as duas exceções
DO $patch2$
BEGIN
  IF to_regprocedure('public.qa_cercas_faltando()') IS NULL THEN
    RAISE NOTICE 'qa_cercas_faltando() ausente — nada a ajustar.';
    RETURN;
  END IF;

  CREATE OR REPLACE FUNCTION public.qa_cercas_faltando()
  RETURNS TABLE(tabela text)
  LANGUAGE sql STABLE
  AS $fn$
    SELECT col.table_name::text
    FROM information_schema.columns col
    JOIN information_schema.tables t
      ON t.table_schema = col.table_schema AND t.table_name = col.table_name
    WHERE col.table_schema = 'public'
      AND col.column_name  = 'tenant_id'
      AND t.table_type     = 'BASE TABLE'
      AND col.table_name NOT LIKE 'qa\_%'
      AND col.table_name NOT IN ('marketplace_demanda_latente', 'parceiro_mrr_snapshots')
      AND NOT EXISTS (
        SELECT 1 FROM pg_trigger tg
        WHERE tg.tgname = 'qa_guarda_cercado'
          AND tg.tgrelid = ('public.' || quote_ident(col.table_name))::regclass
          AND NOT tg.tgisinternal)
    ORDER BY 1;
  $fn$;
END $patch2$;

-- 4) Conferência (única, para o editor mostrar): esperado 2 linhas, ambas 'ok'
WITH alvo AS MATERIALIZED (
  SELECT 'gatilho nas 2 revertidas (esperado 0)'::text AS item,
         (SELECT count(*) FROM pg_trigger tg JOIN pg_class c ON c.oid = tg.tgrelid
           WHERE tg.tgname = 'qa_guarda_cercado' AND NOT tg.tgisinternal
             AND c.relname IN ('marketplace_demanda_latente','parceiro_mrr_snapshots')) AS valor,
         0 AS esperado
  UNION ALL
  SELECT 'gatilho nas 2 de ponto (esperado 2 se existirem)'::text,
         (SELECT count(*) FROM pg_trigger tg JOIN pg_class c ON c.oid = tg.tgrelid
           WHERE tg.tgname = 'qa_guarda_cercado' AND NOT tg.tgisinternal
             AND c.relname IN ('ponto_expurgo_eventos','ponto_retrato_pre')),
         (SELECT count(*) FROM information_schema.tables
           WHERE table_schema='public' AND table_name IN ('ponto_expurgo_eventos','ponto_retrato_pre'))
)
SELECT item, valor, esperado,
       CASE WHEN valor = esperado THEN 'ok' ELSE 'CONFERIR' END AS situacao
FROM alvo;
