-- ============================================================================
-- QA — reinstala as cercas do cercado de testes (PONTO-270)
--
-- A tabela ponto_compensacao_falta, criada depois da última instalação das
-- cercas (20260930192005_..._fatia1), nasceu com RLS e políticas de tenant,
-- mas FICOU SEM a trava do cercado (o gatilho qa_guarda_cercado). Sem ela, uma
-- rotina de teste com erro de tenant poderia escrever em dado de cliente real
-- por esse caminho. O caso PONTO-270 vigia exatamente isso e acusou a falha
-- ("1 tabela do módulo SEM a trava do cercado: ponto_compensacao_falta").
--
-- Correção (a mesma que o próprio caso indica, e idêntica à de
-- 20260924184510): qa_instalar_cercas(), que instala o gatilho qa_guarda_cercado
-- em TODA tabela de public com coluna tenant_id que ainda não o tenha.
-- Idempotente. O gatilho é NO-OP fora do modo de teste (só age quando
-- app.qa_modo = 'on'), então não afeta a operação normal nem a produção.
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
    RAISE NOTICE 'Cercas do cercado reinstaladas (alcanca ponto_compensacao_falta e qualquer outra tabela com tenant_id sem a trava).';
  END IF;
END $cerca$;
