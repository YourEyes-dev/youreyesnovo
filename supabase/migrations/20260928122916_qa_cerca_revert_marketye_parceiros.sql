-- ============================================================================
-- QA · Revert de cerca em duas tabelas que NUNCA foram cercadas (marketye/parceiros)
--
-- CONTEXTO: em 24/09 o conserto do PONTO-270 rodou o instalador GENÉRICO
-- qa_instalar_cercas() (migration 20260924184510_qa_reinstala_cercas_ponto),
-- que instala o gatilho qa_guarda_cercado em TODA tabela de public com coluna
-- tenant_id. O objetivo era só alcançar as duas tabelas de ponto que ficaram
-- sem trava (ponto_expurgo_eventos, ponto_retrato_pre). Mas o instalador é
-- genérico: cercou 36 tabelas, e entre elas duas que NUNCA tinham cerca —
--
--   · marketplace_demanda_latente  (MarketYE)
--   · parceiro_mrr_snapshots        (Parceiros)
--
-- Essas duas guardam, por desenho, linhas de MUITOS tenants que NÃO são o
-- cercado: a demanda latente agrega células de várias empresas sintéticas
-- (o piso mínimo por célula É o que MKY-005 testa) e o snapshot de MRR é por
-- cliente do parceiro. As rotinas de QA desses módulos criam tenants
-- sintéticos próprios (não o qa-sandbox) e escrevem neles — o que a cerca,
-- em modo de teste, passou a bloquear. Resultado: verde virou vermelho em
--
--   · MKY-005, MKY-065  → marketplace_demanda_latente
--   · PGP-010, PGP-012, PGP-013 → parceiro_mrr_snapshots
--
-- em AMBOS os ambientes (foram cercadas nos dois). Isto é regressão da
-- instalação genérica, não bug dessas rotinas. A correção é reverter a cerca
-- SÓ nessas duas tabelas — as duas de ponto (ponto_expurgo_eventos,
-- ponto_retrato_pre) continuam cercadas, que é do que o PONTO-270 depende.
--
-- DURABILIDADE: além de tirar o gatilho agora, este script ensina o instalador
-- genérico (qa_instalar_cercas) e o vigia (qa_cercas_faltando) a PULAR essas
-- duas tabelas. Sem isso, a próxima vez que alguém rodasse qa_instalar_cercas()
-- — ao criar uma tabela nova — reinstalaria a cerca e reabriria exatamente
-- esta regressão. A exceção mora no corpo das funções, à vista de quem lê,
-- com o motivo ao lado (mesma disciplina de PERFIL-003 e das rotinas ISOL).
--
-- Conserto durável alternativo (não feito aqui, anotado): ensinar as rotinas de
-- QA do marketye/parceiros a registrar os tenants sintéticos que criam como
-- cercados — aí as tabelas ficariam protegidas E os testes passariam. Exige
-- mudar a trava para consultar um registro de cercados (hoje ela só reconhece
-- qa-sandbox e qa-sandbox-2, fixos), o que é entrega própria, maior que este
-- revert.
--
-- Padrão da casa: se a bancada de QA não existir nesta base, apenas avisa.
-- Idempotente (rodar duas vezes não quebra nem duplica).
-- ============================================================================

SET lock_timeout = '10s';

-- ─────────────────────────────────────────────────────────
-- 1) Tira o gatilho das duas tabelas (se estiver instalado)
-- ─────────────────────────────────────────────────────────
DO $revert$
DECLARE
  c text;
  v_excecoes CONSTANT text[] := ARRAY['marketplace_demanda_latente', 'parceiro_mrr_snapshots'];
BEGIN
  FOREACH c IN ARRAY v_excecoes LOOP
    IF to_regclass('public.' || quote_ident(c)) IS NULL THEN
      RAISE NOTICE 'Tabela public.% não existe nesta base — nada a reverter.', c;
      CONTINUE;
    END IF;
    IF EXISTS (
      SELECT 1 FROM pg_trigger tg
      WHERE tg.tgname = 'qa_guarda_cercado'
        AND tg.tgrelid = ('public.' || quote_ident(c))::regclass
        AND NOT tg.tgisinternal
    ) THEN
      EXECUTE format('DROP TRIGGER qa_guarda_cercado ON public.%I', c);
      RAISE NOTICE 'Cerca removida de public.% (tabela multi-tenant por desenho).', c;
    ELSE
      RAISE NOTICE 'public.% já estava sem a cerca — nada a fazer.', c;
    END IF;

    -- Sai da lista de "protegidas" para o estado ficar consistente com o
    -- gatilho ausente (a linha havia sido inserida pela instalação genérica).
    IF to_regclass('public.qa_tabelas_protegidas') IS NOT NULL THEN
      DELETE FROM public.qa_tabelas_protegidas WHERE tabela = c;
    END IF;
  END LOOP;
END $revert$;

-- ─────────────────────────────────────────────────────────
-- 2) Instalador genérico passa a PULAR essas duas tabelas
--    (para uma futura reinstalação não reabrir a regressão)
-- ─────────────────────────────────────────────────────────
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
    -- Tabelas multi-tenant POR DESENHO, que nunca tiveram cerca: a demanda
    -- latente agrega células de várias empresas (piso mínimo por célula) e o
    -- snapshot de MRR é por cliente do parceiro. As rotinas de QA desses
    -- módulos criam tenants sintéticos próprios e escrevem neles; cercá-las
    -- reprova MKY-005/065 e PGP-010/012/013. Ficam de fora de propósito.
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
        AND col.table_name NOT LIKE 'qa\_%'   -- as tabelas do proprio QA ficam de fora
        AND col.table_name <> ALL (v_excecoes)  -- multi-tenant por desenho (ver acima)
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

-- ─────────────────────────────────────────────────────────
-- 3) Vigia da cerca também passa a reconhecer as duas exceções
--    (senão acusaria "falta cerca" nelas para sempre)
-- ─────────────────────────────────────────────────────────
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
      -- exceções multi-tenant por desenho (ver qa_instalar_cercas)
      AND col.table_name NOT IN ('marketplace_demanda_latente', 'parceiro_mrr_snapshots')
      AND NOT EXISTS (
        SELECT 1 FROM pg_trigger tg
        WHERE tg.tgname = 'qa_guarda_cercado'
          AND tg.tgrelid = ('public.' || quote_ident(col.table_name))::regclass
          AND NOT tg.tgisinternal)
    ORDER BY 1;
  $fn$;
END $patch2$;

-- ─────────────────────────────────────────────────────────
-- 4) Conferência: as duas alvo sem gatilho; as duas de ponto com gatilho
-- ─────────────────────────────────────────────────────────
DO $confere$
DECLARE
  v_alvo int;
  v_ponto int;
BEGIN
  SELECT count(*) INTO v_alvo
  FROM pg_trigger tg
  JOIN pg_class c ON c.oid = tg.tgrelid
  WHERE tg.tgname = 'qa_guarda_cercado' AND NOT tg.tgisinternal
    AND c.relname IN ('marketplace_demanda_latente', 'parceiro_mrr_snapshots');

  SELECT count(*) INTO v_ponto
  FROM pg_trigger tg
  JOIN pg_class c ON c.oid = tg.tgrelid
  WHERE tg.tgname = 'qa_guarda_cercado' AND NOT tg.tgisinternal
    AND c.relname IN ('ponto_expurgo_eventos', 'ponto_retrato_pre');

  RAISE NOTICE 'Conferência: % gatilho(s) nas tabelas revertidas (esperado 0); % nas de ponto (esperado 2 se existirem nesta base).',
    v_alvo, v_ponto;
END $confere$;
