-- =========================================================
-- QA — Ponte de cobertura e2e: ERGO-014 e ERGO-061 (Ergonomia).
--
-- Mesma correção do Bloqueio 1 (o "Novo Risco" grava em gro_riscos) destravou:
--   • ERGO-014 — a criticidade exibida vem de severidade+probabilidade (o
--     nivel_risco é calculado pelo trigger calcular_nivel_gro_risco e aparece na
--     linha do Inventário GRO);
--   • ERGO-061 — os cards de estatística refletem o inventário (gro_riscos).
-- Os it() correspondentes estão em cypress/e2e/ergonomia.cy.ts; aqui ligamos cada
-- caso ao seu teste.
--
-- (ERGO-015/020/024 NÃO entram: têm descompasso de produto próprio — ver
-- docs/BLOQUEIOS_PRODUTO_QA_E2E.md, Bloqueios 2/3/4.)
--
-- delete-then-insert: idempotente, converge para o título certo.
-- =========================================================

DELETE FROM public.qa_cobertura_e2e WHERE codigo IN ('ERGO-014', 'ERGO-061');

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  ('ERGO-014', 'cypress/e2e/ergonomia.cy.ts', 'a criticidade exibida vem da severidade e da probabilidade'),
  ('ERGO-061', 'cypress/e2e/ergonomia.cy.ts', 'os cards de estatística refletem o inventário GRO')
) AS v(codigo, spec, teste);
