-- =========================================================
-- QA — Ponte de cobertura e2e: specs de tela do PDI (/pdi) — 5 ligações.
--
-- Liga cada it() novo (cypress/e2e/pdi.cy.ts) ao caso documentado que ele
-- executa, em qa_cobertura_e2e (codigo -> spec + título do it()). Sem esta
-- ponte, a guarda scripts/verificar-cobertura-e2e.mjs trataria os it() novos
-- como "inventados" e reprovaria a corrida.
--
-- Escopo dos it(): entrada/validação (a tela monta com as abas, o FAQ abre/
-- fecha, as estatísticas aparecem, e o modal de novo PDI trava sem colaborador
-- ou sem datas) — sem criar PDI, então não dependem de dado semeado.
--
-- Títulos = texto EXATO do it() (normalizado por espaços). Só INSERE dados.
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  ('PDI-001', 'cypress/e2e/pdi.cy.ts', 'abre com a lista e as abas Todos, Ativos e Concluídos'),
  ('PDI-003', 'cypress/e2e/pdi.cy.ts', 'abre e fecha o FAQ em accordion'),
  ('PDI-011', 'cypress/e2e/pdi.cy.ts', 'bloqueia a criação de PDI sem colaborador'),
  ('PDI-012', 'cypress/e2e/pdi.cy.ts', 'bloqueia a criação de PDI sem as datas'),
  ('PDI-031', 'cypress/e2e/pdi.cy.ts', 'mostra as estatísticas do topo')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;
