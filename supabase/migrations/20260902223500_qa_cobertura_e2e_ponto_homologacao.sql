-- =========================================================
-- QA — Ponte de cobertura e2e para o spec do Ponto (6 ligações)
--
-- Liga cada it() de cypress/e2e/ponto.cy.ts ao caso documentado da Bateria
-- de Homologação do Ponto que ele executa, na tabela qa_cobertura_e2e
-- (codigo -> spec + título do it()). Sem esta ponte, a guarda
-- scripts/verificar-cobertura-e2e.mjs trataria os it() novos como
-- "inventados" e REPROVARIA a corrida.
--
-- Os títulos abaixo são o texto EXATO do it() (normalizado por espaços),
-- como o Cypress reporta e como a guarda cruza. Renomear um it() sem
-- atualizar aqui quebra a ligação (a guarda avisa, sem reprovar).
--
-- Os casos PONTO-HOM-* entram na migration 20260902223000 (aplicada antes
-- desta pelo db push, por ordem de carimbo).
--
-- Só INSERE dados. Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  ('PONTO-HOM-A1', 'cypress/e2e/ponto.cy.ts', 'abre Configurações › Intervalo pré-assinalado e o formulário de nova declaração'),
  ('PONTO-HOM-E1', 'cypress/e2e/ponto.cy.ts', 'abre Configurações › Certificado digital e o formulário de novo certificado'),
  ('PONTO-HOM-B1', 'cypress/e2e/ponto.cy.ts', 'abre Apuração › Fechamento com o controle de fechar período'),
  ('PONTO-HOM-E2', 'cypress/e2e/ponto.cy.ts', 'abre Compliance › Dossiê fiscal com a ação de montar'),
  ('PONTO-HOM-I1', 'cypress/e2e/ponto.cy.ts', 'abre Compliance › Alertas CLT'),
  ('PONTO-HOM-H1', 'cypress/e2e/ponto.cy.ts', 'abre Escalas com a ação de criar escala')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;
