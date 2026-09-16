-- =========================================================
-- QA — Ponte de cobertura e2e: specs de tela de Autenticação (/login) —
-- 5 ligações.
--
-- Liga cada it() novo (cypress/e2e/autenticacao.cy.ts) ao caso documentado que
-- ele executa, em qa_cobertura_e2e (codigo -> spec + título do it()). Sem esta
-- ponte, a guarda scripts/verificar-cobertura-e2e.mjs trataria os it() novos
-- como "inventados" e reprovaria a corrida.
--
-- Escopo dos it(): a própria tela de login — monta, barra campos vazios/
-- inválidos, mostra/oculta a senha, dá erro genérico com senha errada, e uma
-- rota protegida sem login redireciona para o /login. Nenhum faz login válido,
-- então não cria sessão nem depende de dado semeado.
--
-- Títulos = texto EXATO do it() (normalizado por espaços). Só INSERE dados.
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  ('AUTH-001', 'cypress/e2e/autenticacao.cy.ts', 'monta a tela de login com os campos e ações'),
  ('AUTH-003', 'cypress/e2e/autenticacao.cy.ts', 'mostra erro genérico com senha errada'),
  ('AUTH-004', 'cypress/e2e/autenticacao.cy.ts', 'barra o envio com campos vazios ou inválidos'),
  ('AUTH-005', 'cypress/e2e/autenticacao.cy.ts', 'mostra e oculta a senha'),
  ('AUTH-020', 'cypress/e2e/autenticacao.cy.ts', 'redireciona rota protegida sem login para o login')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;
