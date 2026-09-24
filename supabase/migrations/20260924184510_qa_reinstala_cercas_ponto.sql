-- ============================================================================
-- QA — reinstala as cercas do cercado de testes (PONTO-270)
--
-- Duas tabelas do módulo ponto criadas depois da última instalação ficaram sem
-- a trava do cercado (ponto_expurgo_eventos, ponto_retrato_pre). Sem ela, uma
-- rotina de teste com erro de tenant poderia escrever em dado de cliente real
-- por esse caminho. O caso PONTO-270 vigia justamente isso e acusou a falha.
--
-- Correção (a que o próprio caso indica): qa_instalar_cercas(), que instala o
-- gatilho qa_guarda_cercado em TODA tabela de public com coluna tenant_id que
-- ainda não o tenha. Idempotente. O gatilho é NO-OP fora do modo de teste
-- (só age quando app.qa_modo = 'on'), então não afeta operação normal.
--
-- Padrão da casa: se a bancada de QA não existir nesta base, apenas avisa e não
-- faz nada — por isso é seguro em qualquer ambiente.
-- ============================================================================

DO $cerca$
BEGIN
  IF to_regprocedure('public.qa_instalar_cercas()') IS NULL THEN
    RAISE NOTICE 'Bancada de testes ausente nesta base — nada a cercar.';
  ELSE
    PERFORM public.qa_instalar_cercas();
    RAISE NOTICE 'Cercas do cercado reinstaladas (alcanca ponto_expurgo_eventos e ponto_retrato_pre).';
  END IF;
END $cerca$;
