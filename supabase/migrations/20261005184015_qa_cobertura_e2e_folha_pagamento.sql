-- =====================================================================
-- Ponte de cobertura e2e — Folha de Pagamento (cypress/e2e/folha-pagamento.cy.ts)
--
-- Liga 3 dos 6 casos FOLHA de nivel e2e ao it() que os exercita na tela.
-- O titulo precisa bater AO CARACTERE com o do it() no spec.
--
-- Fora deste lote (precisam de folha calculada / condicoes cadastradas —
-- exige fixture): FOLHA-021 (insalubridade/periculosidade), FOLHA-022 (DSR)
-- e FOLHA-041 (holerite discriminado). Serao ligados quando houver semeadura.
-- =====================================================================
INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste, ativo, criado_em) VALUES
  ('FOLHA-010', 'cypress/e2e/folha-pagamento.cy.ts', 'aba Tabelas mostra a tabela de INSS por faixas com teto', true, now()),
  ('FOLHA-011', 'cypress/e2e/folha-pagamento.cy.ts', 'aba Tabelas mostra a tabela de IRRF com dedução por dependente', true, now()),
  ('FOLHA-020', 'cypress/e2e/folha-pagamento.cy.ts', 'aba CCT expõe o adicional noturno das convenções coletivas', true, now())
ON CONFLICT (codigo) DO UPDATE SET
  spec = EXCLUDED.spec, teste = EXCLUDED.teste, ativo = true;
