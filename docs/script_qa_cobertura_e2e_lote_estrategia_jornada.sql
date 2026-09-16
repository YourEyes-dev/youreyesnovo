-- =========================================================
-- ENTREGA QA — Ponte de cobertura e2e (15 ligações caso↔teste)
--
-- Cole no SQL Editor da HOMOLOGAÇÃO (e depois, quando aprovado, na produção).
-- Liga os it() de cypress/e2e/{estrategia,analise-jornada}.cy.ts aos casos já
-- documentados (PLEST/ORG/IDENT-TELA-* e AJOR-*). Sem esta ponte, a guarda
-- reprova a corrida (it() sem caso). Idempotente: ON CONFLICT DO NOTHING.
-- Termina com uma conferência.
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

-- ── Conferência (última query: é o que o SQL Editor exibe) ──
SELECT c.spec, count(*) AS ligacoes
FROM public.qa_cobertura_e2e c
WHERE c.spec IN ('cypress/e2e/estrategia.cy.ts','cypress/e2e/analise-jornada.cy.ts')
GROUP BY c.spec ORDER BY c.spec;
