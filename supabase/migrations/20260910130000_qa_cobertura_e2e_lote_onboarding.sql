-- =========================================================
-- QA — Ponte de cobertura e2e: specs de tela do Onboarding (/onboarding-rh) —
-- 3 ligações.
--
-- Liga cada it() novo (cypress/e2e/onboarding.cy.ts) ao caso documentado que
-- ele executa, em qa_cobertura_e2e (codigo -> spec + título do it()). Sem esta
-- ponte, a guarda scripts/verificar-cobertura-e2e.mjs trataria os it() novos
-- como "inventados" e reprovaria a corrida.
--
-- Escopo dos it(): entrada/validação (as três abas montam, o modal de novo
-- template trava sem nome, a aba Indicadores consolida os números) — sem criar
-- template nem processo, então não dependem de dado semeado.
--
-- Títulos = texto EXATO do it() (normalizado por espaços). Só INSERE dados.
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  ('ONB-001', 'cypress/e2e/onboarding.cy.ts', 'abre com as três abas Processos, Indicadores e Templates'),
  ('ONB-011', 'cypress/e2e/onboarding.cy.ts', 'bloqueia a criação de template sem nome'),
  ('ONB-050', 'cypress/e2e/onboarding.cy.ts', 'mostra os indicadores consolidados')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;
