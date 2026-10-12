-- =========================================================
-- ENTREGA QA — Ponte de cobertura e2e: ERGO-014 e ERGO-061 (Ergonomia).
--
-- Cole no SQL Editor do ambiente de TESTE primeiro; só depois de aprovado, na
-- produção. Liga ao Cypress os casos destravados pela correção do Bloqueio 1:
--   • ERGO-014 — criticidade composta por severidade+probabilidade (linha do
--     Inventário GRO);
--   • ERGO-061 — cards de estatística refletem o inventário (gro_riscos).
-- Sem a ponte, a guarda da esteira trataria os it() como "inventados".
--
-- Pré-requisito: casos ERGO-014 e ERGO-061 já documentados em qa_casos_teste
-- (nível e2e). delete-then-insert: idempotente. Roda em UMA transação; termina
-- com uma conferência (o SQL Editor só mostra o último resultado).
-- =========================================================

DELETE FROM public.qa_cobertura_e2e WHERE codigo IN ('ERGO-014', 'ERGO-061');

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  ('ERGO-014', 'cypress/e2e/ergonomia.cy.ts', 'a criticidade exibida vem da severidade e da probabilidade'),
  ('ERGO-061', 'cypress/e2e/ergonomia.cy.ts', 'os cards de estatística refletem o inventário GRO')
) AS v(codigo, spec, teste);

-- ── Conferência (última query: é o que o SQL Editor exibe) ──
SELECT c.codigo, c.spec, c.teste, c.ativo
FROM public.qa_cobertura_e2e c
WHERE c.spec = 'cypress/e2e/ergonomia.cy.ts'
ORDER BY c.codigo;
