-- =========================================================
-- QA — Ponte de cobertura e2e: specs de tela de Cultura & Celebrações
-- (/cultura-celebracoes) — 3 ligações.
--
-- Liga cada it() novo (cypress/e2e/cultura-celebracoes.cy.ts) ao caso
-- documentado que ele executa, em qa_cobertura_e2e (codigo -> spec + título do
-- it()). Sem esta ponte, a guarda scripts/verificar-cobertura-e2e.mjs trataria
-- os it() novos como "inventados" e reprovaria a corrida.
--
-- Escopo dos it(): entrada/validação (os KPIs e as abas montam, os indicadores
-- culturais consolidam os números, o modal de nova ação não cria sem título/
-- data) — sem criar ação/ritual/preferência, então não dependem de dado semeado.
--
-- Títulos = texto EXATO do it() (normalizado por espaços). Só INSERE dados.
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  ('CULT-001', 'cypress/e2e/cultura-celebracoes.cy.ts', 'abre com as abas e os KPIs'),
  ('CULT-011', 'cypress/e2e/cultura-celebracoes.cy.ts', 'não cria ação sem título ou data'),
  ('CULT-060', 'cypress/e2e/cultura-celebracoes.cy.ts', 'mostra os indicadores culturais')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;
