-- =========================================================
-- QA — Ponte de cobertura e2e: specs de tela da Central de Suporte (/suporte) —
-- 4 ligações.
--
-- Liga cada it() novo (cypress/e2e/suporte.cy.ts) ao caso documentado que ele
-- executa, em qa_cobertura_e2e (codigo -> spec + título do it()). Sem esta
-- ponte, a guarda scripts/verificar-cobertura-e2e.mjs trataria os it() novos
-- como "inventados" e reprovaria a corrida.
--
-- Escopo dos it(): entrada/validação (a central monta com stats e filtros, o
-- modal de novo ticket trava sem título/descrição e oferece tipo/prioridade/
-- módulo, a lista vazia orienta) — sem criar ticket, então não dependem de
-- dado semeado.
--
-- Títulos = texto EXATO do it() (normalizado por espaços). Só INSERE dados.
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  ('SUP-001', 'cypress/e2e/suporte.cy.ts', 'abre a central com stats e filtros'),
  ('SUP-011', 'cypress/e2e/suporte.cy.ts', 'bloqueia o envio de ticket sem título ou descrição'),
  ('SUP-012', 'cypress/e2e/suporte.cy.ts', 'permite escolher tipo, prioridade e módulo no novo ticket'),
  ('SUP-050', 'cypress/e2e/suporte.cy.ts', 'mostra a lista vazia orientando a abrir um ticket')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;
