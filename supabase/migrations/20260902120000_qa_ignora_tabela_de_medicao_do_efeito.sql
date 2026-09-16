-- =====================================================================
-- QA — a tabela que MEDE o efeito da entrega sai do escopo das auditorias
--
-- MOTIVO: a fila de producao da auditoria de DP criou mais uma tabela de
-- apoio, que existe para a operacao da entrega e nao faz parte do produto:
--
--   * ponto_efeito_apuracao — a fotografia do saldo CALCULADO, tirada antes
--     e depois da entrega. A diferenca entre as duas e a medida do efeito
--     das cinco correcoes.
--
-- Como ela se chama "ponto_...", as duas auditorias do modulo passaram a
-- acusa-la, pelos mesmos motivos ja documentados para ponto_retrato_pre e
-- ponto_entrega_volume em 20260901270000:
--
--   PONTO-250 (RLS e politicas): a tabela tem RLS LIGADA e NENHUMA
--     politica, de proposito, e as concessoes de anon e authenticated foram
--     revogadas. E a postura MAIS fechada possivel, e a auditoria a lia como
--     a mais aberta. Ela guarda CPF e horas, entao o cuidado e proposital.
--
--   PONTO-270 (cerca do cercado de testes): nenhuma rotina de teste escreve
--     nela — quem escreve e o script de entrega, colado a mao. Ainda assim a
--     cerca e barata, entao aqui ela e instalada, em vez de a tabela ser
--     dispensada.
--
-- NADA DE REGRA DE NEGOCIO MUDA, e nenhuma tabela do produto sai do escopo:
-- a lista de excecoes ganha exatamente este nome.
-- =====================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- 1) PONTO-270: instala a cerca, se a bancada existir
-- ---------------------------------------------------------------------
DO $cerca$
BEGIN
  IF to_regprocedure('public.qa_instalar_cercas()') IS NULL THEN
    RAISE NOTICE 'Bancada de testes ausente nesta base — nada a cercar.';
    RETURN;
  END IF;
  PERFORM public.qa_instalar_cercas();
  RAISE NOTICE 'Cercas do cercado de testes reinstaladas (alcanca a tabela de medicao do efeito).';
END $cerca$;

-- ---------------------------------------------------------------------
-- 2) PONTO-250: a nova tabela entra na mesma lista de excecoes
-- ---------------------------------------------------------------------
DO $auditoria$
DECLARE
  v_src text;
  v_alvo text := '''ponto_retrato_pre'', ''ponto_entrega_volume''';
  v_novo text := '''ponto_retrato_pre'', ''ponto_entrega_volume'', ''ponto_efeito_apuracao''';
BEGIN
  IF to_regprocedure('public.qa_caso_ponto_250()') IS NULL THEN
    RAISE NOTICE 'Bancada de testes ausente nesta base — nada a ajustar no PONTO-250.';
    RETURN;
  END IF;

  SELECT pg_get_functiondef(p.oid) INTO v_src
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'qa_caso_ponto_250';

  IF position('ponto_efeito_apuracao' IN v_src) > 0 THEN
    RAISE NOTICE 'PONTO-250 ja ignora a tabela de medicao do efeito — nada a fazer.';
    RETURN;
  END IF;

  IF position(v_alvo IN v_src) = 0 THEN
    RAISE NOTICE 'ATENCAO: a lista de excecoes esperada nao foi encontrada no PONTO-250. Rode antes a migration 20260901270000; o ajuste NAO foi aplicado.';
    RETURN;
  END IF;

  EXECUTE replace(v_src, v_alvo, v_novo);
  RAISE NOTICE 'PONTO-250 passa a ignorar tambem ponto_efeito_apuracao (apoio da entrega, fechada por RLS sem politica).';
END $auditoria$;

DO $fim$
BEGIN
  RAISE NOTICE 'Tabela de medicao do efeito fora do escopo das auditorias do modulo.';
END $fim$;
