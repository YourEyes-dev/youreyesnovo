-- =========================================================
-- ENTREGA QA (opcional) — Ponte de cobertura e2e do spec do Ponto (6 ligações)
--
-- Cole no SQL Editor do ambiente de HOMOLOGACAO (projeto fgsblefvdabgdouipigz)
-- SE quiser que a tela Documentação de testes mostre os 6 casos da Bateria de
-- Homologação do Ponto já ligados ao teste de tela (cypress/e2e/ponto.cy.ts).
--
-- Não é obrigatório para RODAR o Cypress — os testes rodam de qualquer jeito.
-- Isto só alimenta o painel de cobertura (qual caso já tem teste de tela).
-- A mesma ponte entra no staging pela migration 20260902223500.
--
-- Pré-requisito: os casos PONTO-HOM-* já documentados (script
-- docs/script_qa_ponto_bateria_homologacao.sql). Só INSERE. Idempotente:
-- ON CONFLICT (codigo) DO NOTHING. Termina com uma conferência SELECT.
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

-- ── Conferência (última query: é o que o SQL Editor exibe) ──
SELECT c.codigo,
       ct.titulo,
       c.spec,
       c.teste
FROM public.qa_cobertura_e2e c
LEFT JOIN public.qa_casos_teste ct ON ct.codigo = c.codigo
WHERE c.codigo LIKE 'PONTO-HOM-%'
ORDER BY c.codigo;
