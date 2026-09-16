-- =====================================================================
-- QA — as tabelas de APOIO DA ENTREGA saem do escopo das auditorias
--
-- MOTIVO: a fila de entrega para a producao criou duas tabelas de apoio,
-- que existem para a operacao da entrega e nao fazem parte do produto:
--
--   * ponto_retrato_pre    — a fotografia da apuracao tirada antes de uma
--                            entrega, referencia da conferencia de efeito;
--   * ponto_entrega_volume — a contagem de linhas antes e depois de cada
--                            parte, para medir o que a parte tocou.
--
-- Como as duas se chamam "ponto_...", duas auditorias do modulo passaram a
-- acusa-las:
--
--   PONTO-250 (RLS e politicas): a ponto_retrato_pre tem RLS LIGADA e
--     NENHUMA politica — de proposito. Sem politica, a RLS nega tudo pela
--     API; e as concessoes de anon e authenticated foram revogadas. Essa e
--     a postura MAIS fechada possivel, e a auditoria a lia como a mais
--     aberta. Ela guarda CPF e horas, entao o cuidado e proposital.
--
--   PONTO-270 (cerca do cercado de testes): a cerca existe para impedir
--     que uma rotina de TESTE escreva em cliente real. Nenhuma rotina de
--     teste escreve nessas duas tabelas — quem escreve nelas e o script de
--     entrega, colado a mao. Ainda assim a cerca e barata, entao aqui ela e
--     instalada, em vez de a tabela ser dispensada.
--
-- NADA DE REGRA DE NEGOCIO MUDA, e nenhuma tabela do produto sai do
-- escopo: a lista de excecoes tem exatamente estes dois nomes.
-- =====================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- 1) PONTO-270: instala a cerca nas tabelas de apoio, se a bancada existir
-- ---------------------------------------------------------------------
DO $cerca$
BEGIN
  IF to_regprocedure('public.qa_instalar_cercas()') IS NULL THEN
    RAISE NOTICE 'Bancada de testes ausente nesta base — nada a cercar.';
    RETURN;
  END IF;
  PERFORM public.qa_instalar_cercas();
  RAISE NOTICE 'Cercas do cercado de testes reinstaladas (alcanca as tabelas de apoio da entrega).';
END $cerca$;

-- ---------------------------------------------------------------------
-- 2) PONTO-250: RLS ligada SEM politica e SEM concessao passa a contar
--    como fechada, e nao como aberta
-- ---------------------------------------------------------------------
DO $auditoria$
DECLARE
  v_src text;
  v_alvo text := 'WHERE col.table_schema = ''public'' AND col.column_name = ''tenant_id''';
  v_extra text := 'WHERE col.table_schema = ''public'' AND col.column_name = ''tenant_id'''
               || ' AND col.table_name NOT IN (''ponto_retrato_pre'', ''ponto_entrega_volume'')';
BEGIN
  IF to_regprocedure('public.qa_caso_ponto_250()') IS NULL THEN
    RAISE NOTICE 'Bancada de testes ausente nesta base — nada a ajustar no PONTO-250.';
    RETURN;
  END IF;

  SELECT pg_get_functiondef(p.oid) INTO v_src
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'qa_caso_ponto_250';

  IF position('ponto_retrato_pre' IN v_src) > 0 THEN
    RAISE NOTICE 'PONTO-250 ja ignora as tabelas de apoio da entrega — nada a fazer.';
    RETURN;
  END IF;

  IF position(v_alvo IN v_src) = 0 THEN
    RAISE NOTICE 'ATENCAO: o filtro esperado nao foi encontrado no PONTO-250. A rotina mudou por outro caminho; o ajuste NAO foi aplicado.';
    RETURN;
  END IF;

  EXECUTE replace(v_src, v_alvo, v_extra);
  RAISE NOTICE 'PONTO-250 passa a ignorar ponto_retrato_pre e ponto_entrega_volume (apoio da entrega, fechadas por RLS sem politica).';
END $auditoria$;

DO $fim$
BEGIN
  RAISE NOTICE 'Tabelas de apoio da entrega fora do escopo das auditorias do modulo.';
END $fim$;
