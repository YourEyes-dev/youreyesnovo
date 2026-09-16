-- =========================================================
-- QA — Ponte de cobertura e2e: specs de tela de Contratos de Experiência
-- (/contratos-experiencia) — 3 ligações.
--
-- Liga cada it() novo (cypress/e2e/contratos-experiencia.cy.ts) ao caso
-- documentado que ele executa, em qa_cobertura_e2e (codigo -> spec + título do
-- it()). Sem esta ponte, a guarda scripts/verificar-cobertura-e2e.mjs trataria
-- os it() novos como "inventados" e reprovaria a corrida.
--
-- Escopo dos it(): entrada/validação (o painel monta com abas e KPIs, a lista
-- tem busca e filtros, a config trava períodos que excedem 90 dias) — sem
-- salvar config nem criar/alterar contrato, então não dependem de dado semeado
-- além da ilha padrão.
--
-- Títulos = texto EXATO do it() (normalizado por espaços). Só INSERE dados.
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  ('EXP-001', 'cypress/e2e/contratos-experiencia.cy.ts', 'abre o painel com as abas e os KPIs'),
  ('EXP-003', 'cypress/e2e/contratos-experiencia.cy.ts', 'tem busca e filtros na lista de contratos'),
  ('EXP-060', 'cypress/e2e/contratos-experiencia.cy.ts', 'bloqueia a configuração de períodos que excede 90 dias')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;
