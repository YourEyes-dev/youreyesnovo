-- =====================================================================
-- ENTREGA — Ponte de cobertura e2e do DEC13-042 (FGTS no 13º)
-- (colar no SQL Editor; rodar em producao SO apos aprovado no teste)
--
-- Liga DEC13-042 ao it() de cypress/e2e/decimo-terceiro.cy.ts. Esse teste
-- depende da fixture de folha (seed-folha-fixture). So insere metadado de QA.
-- Idempotente. Com ele, financeiro/decimo-terceiro fecha 10/10 e2e.
-- =====================================================================
INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste, ativo, criado_em) VALUES
  ('DEC13-042', 'cypress/e2e/decimo-terceiro.cy.ts', 'o detalhe de um 13º calculado discrimina o FGTS', true, now())
ON CONFLICT (codigo) DO UPDATE SET
  spec = EXCLUDED.spec, teste = EXCLUDED.teste, ativo = true;

-- CONFERENCIA FINAL: as 10 pontes do 13º.
SELECT codigo, teste
FROM public.qa_cobertura_e2e
WHERE spec = 'cypress/e2e/decimo-terceiro.cy.ts'
ORDER BY codigo;
