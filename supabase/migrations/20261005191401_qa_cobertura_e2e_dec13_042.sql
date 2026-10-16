-- =====================================================================
-- Ponte de cobertura e2e — DEC13-042 (FGTS no detalhe do 13º)
--
-- Liga o caso DEC13-042 ao it() que o exercita em
-- cypress/e2e/decimo-terceiro.cy.ts. Esse teste depende da fixture de folha
-- (seed-folha-fixture gera um 13º calculado), por isso entrou agora, com a
-- fixture. Completa o modulo financeiro/decimo-terceiro (10/10 e2e).
-- =====================================================================
INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste, ativo, criado_em) VALUES
  ('DEC13-042', 'cypress/e2e/decimo-terceiro.cy.ts', 'o detalhe de um 13º calculado discrimina o FGTS', true, now())
ON CONFLICT (codigo) DO UPDATE SET
  spec = EXCLUDED.spec, teste = EXCLUDED.teste, ativo = true;
