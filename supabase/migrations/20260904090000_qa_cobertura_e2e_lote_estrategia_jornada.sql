-- =========================================================
-- QA — Ponte de cobertura e2e: specs de tela da Estratégia (Planejamento,
-- Organograma, Identidade/Cultura) e da Análise de Jornada (15 ligações).
--
-- Liga cada it() novo (cypress/e2e/{estrategia,analise-jornada}.cy.ts) ao caso
-- documentado que ele executa, em qa_cobertura_e2e (codigo -> spec + título do
-- it()). Sem esta ponte, a guarda scripts/verificar-cobertura-e2e.mjs trataria
-- os it() novos como "inventados" e reprovaria a corrida.
--
-- Títulos = texto EXATO do it() (normalizado por espaços). Só INSERE dados.
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  -- Estratégia: Planejamento Estratégico
  ('PLEST-TELA-01', 'cypress/e2e/estrategia.cy.ts',      'abre Planejamento Estratégico com SWOT e Oceano Azul'),
  ('PLEST-TELA-03', 'cypress/e2e/estrategia.cy.ts',      'abre a sub-aba Oceano Azul'),
  ('PLEST-TELA-06', 'cypress/e2e/estrategia.cy.ts',      'abre o Guia Rápido da estratégia'),
  -- Estratégia: Organograma
  ('ORG-TELA-01',   'cypress/e2e/estrategia.cy.ts',      'abre o Organograma'),
  ('ORG-TELA-02',   'cypress/e2e/estrategia.cy.ts',      'abre o formulário de Nova Posição'),
  -- Estratégia: Identidade / Cultura
  ('IDENT-TELA-01', 'cypress/e2e/estrategia.cy.ts',      'abre a Cultura com Missão, Visão e Valores'),
  ('IDENT-TELA-04', 'cypress/e2e/estrategia.cy.ts',      'tem o gerador de manual com IA'),
  -- Análise de Jornada
  ('AJOR-001', 'cypress/e2e/analise-jornada.cy.ts',      'abre o módulo Análise de Jornada com as 8 abas'),
  ('AJOR-011', 'cypress/e2e/analise-jornada.cy.ts',      'abre a aba Dashboard'),
  ('AJOR-030', 'cypress/e2e/analise-jornada.cy.ts',      'abre a aba Importação'),
  ('AJOR-040', 'cypress/e2e/analise-jornada.cy.ts',      'abre a aba Individual'),
  ('AJOR-050', 'cypress/e2e/analise-jornada.cy.ts',      'abre a aba Conformidade'),
  ('AJOR-060', 'cypress/e2e/analise-jornada.cy.ts',      'abre a aba Alertas'),
  ('AJOR-070', 'cypress/e2e/analise-jornada.cy.ts',      'abre a aba Documentos'),
  ('AJOR-080', 'cypress/e2e/analise-jornada.cy.ts',      'abre a aba Relatórios')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;
