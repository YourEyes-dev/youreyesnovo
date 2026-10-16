-- ============================================================================
-- ENTREGA — Reinstala a trava do cercado de QA (PONTO-270)
--
-- Contexto: a tabela ponto_compensacao_falta nasceu com RLS e políticas de
-- tenant, mas sem o gatilho qa_guarda_cercado (a "trava do cercado" que isola
-- o cercado de testes). O caso PONTO-270 acusou: "1 tabela do módulo SEM a
-- trava do cercado: ponto_compensacao_falta".
--
-- Correção: qa_instalar_cercas() instala o gatilho em toda tabela de public
-- com coluna tenant_id que ainda não o tenha. Idempotente; o gatilho é NO-OP
-- fora do modo de teste (só age quando app.qa_modo = on), então não afeta a
-- operação normal. Se a bancada de QA não existir nesta base (ex.: produção),
-- o script apenas avisa e não faz nada — seguro em qualquer ambiente.
--
-- Roda o arquivo inteiro de uma vez no SQL Editor.
-- ============================================================================

DO $cerca$
BEGIN
  IF to_regprocedure('public.qa_instalar_cercas()') IS NULL THEN
    RAISE NOTICE 'Bancada de testes ausente nesta base — nada a cercar.';
  ELSE
    PERFORM public.qa_instalar_cercas();
    RAISE NOTICE 'Cercas do cercado reinstaladas.';
  END IF;
END $cerca$;

-- Conferência (o editor mostra só o último resultado):
--   bancada_qa_presente = a base tem o cercado de testes instalado?
--   trava_instalada     = a tabela ponto_compensacao_falta já tem o gatilho?
-- Em homologação/teste: trava_instalada deve vir TRUE depois de rodar.
-- Em produção (sem bancada de QA): ambos FALSE é o esperado e inofensivo.
SELECT
  to_regprocedure('public.qa_instalar_cercas()') IS NOT NULL AS bancada_qa_presente,
  EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'qa_guarda_cercado'
      AND tgrelid = to_regclass('public.ponto_compensacao_falta')
  ) AS trava_instalada;
