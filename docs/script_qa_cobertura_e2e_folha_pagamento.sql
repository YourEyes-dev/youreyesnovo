-- =====================================================================
-- ENTREGA — Ponte de cobertura e2e da Folha de Pagamento
-- (colar no SQL Editor; rodar em producao SO apos aprovado no teste)
--
-- Liga 3 casos FOLHA de nivel e2e aos it() de
-- cypress/e2e/folha-pagamento.cy.ts. So insere metadado de QA. Idempotente.
-- Fora deste lote: FOLHA-021/022/041 (exigem folha calculada / fixture).
-- =====================================================================
INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste, ativo, criado_em) VALUES
  ('FOLHA-010', 'cypress/e2e/folha-pagamento.cy.ts', 'aba Tabelas mostra a tabela de INSS por faixas com teto', true, now()),
  ('FOLHA-011', 'cypress/e2e/folha-pagamento.cy.ts', 'aba Tabelas mostra a tabela de IRRF com dedução por dependente', true, now()),
  ('FOLHA-020', 'cypress/e2e/folha-pagamento.cy.ts', 'aba CCT expõe o adicional noturno das convenções coletivas', true, now())
ON CONFLICT (codigo) DO UPDATE SET
  spec = EXCLUDED.spec, teste = EXCLUDED.teste, ativo = true;

-- CONFERENCIA FINAL: as 3 pontes da folha, cada uma apontando para o seu it().
SELECT codigo, teste
FROM public.qa_cobertura_e2e
WHERE spec = 'cypress/e2e/folha-pagamento.cy.ts'
ORDER BY codigo;
