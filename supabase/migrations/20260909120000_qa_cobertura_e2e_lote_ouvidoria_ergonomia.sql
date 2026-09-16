-- =========================================================
-- QA — Ponte de cobertura e2e: specs de tela da Ouvidoria (/ouvidoria) e da
-- Gestão de Risco Ergonômico (/ergonomia) — 8 ligações.
--
-- Liga cada it() novo (cypress/e2e/{ouvidoria,ergonomia}.cy.ts) ao caso
-- documentado que ele executa, em qa_cobertura_e2e (codigo -> spec + título do
-- it()). Sem esta ponte, a guarda scripts/verificar-cobertura-e2e.mjs trataria
-- os it() novos como "inventados" e reprovaria a corrida.
--
-- Escopo dos it(): entrada/validação de tela (o módulo monta, as abas montam,
-- as travas de campo obrigatório seguram o envio, o Guia Rápido abre/fecha) —
-- sem criar manifestação nem risco, então não dependem de dado semeado.
--
-- Títulos = texto EXATO do it() (normalizado por espaços). Só INSERE dados.
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  -- Ouvidoria (/ouvidoria) — aba Enviar
  ('OUV-001',  'cypress/e2e/ouvidoria.cy.ts', 'abre na aba Enviar com o formulário pronto'),
  ('OUV-003',  'cypress/e2e/ouvidoria.cy.ts', 'mostra os cinco tipos de manifestação'),
  ('OUV-004',  'cypress/e2e/ouvidoria.cy.ts', 'bloqueia o envio sem assunto'),
  ('OUV-005',  'cypress/e2e/ouvidoria.cy.ts', 'bloqueia o envio sem mensagem'),
  ('OUV-011',  'cypress/e2e/ouvidoria.cy.ts', 'avisa ao ativar o modo anônimo e retira o aviso ao desligar'),
  -- Gestão de Risco Ergonômico (/ergonomia)
  ('ERGO-001', 'cypress/e2e/ergonomia.cy.ts', 'abre com as 7 abas do fluxo GRO'),
  ('ERGO-002', 'cypress/e2e/ergonomia.cy.ts', 'abre e fecha o Guia Rápido sem afetar a tela'),
  ('ERGO-011', 'cypress/e2e/ergonomia.cy.ts', 'bloqueia o cadastro de risco sem título')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;
