-- =========================================================
-- QA — Adia o ERGO-001 da cobertura e2e.
--
-- O lote 20260909120000 registrou a ponte de ERGO-001 ("abre com as 7 abas do
-- fluxo GRO"), mas a corrida na homologação mostrou que a página de Ergonomia
-- só renderiza as 7 abas quando o módulo TEM inventário NR-17 — com o módulo
-- vazio (ilha de QA) ela mostra o EmptyState, sem abas. Testar as abas exigiria
-- inicializar a base NR-17 (escrever dado na ilha), o que sai do escopo de
-- entrada "sem semear dado". O it() correspondente foi retirado de
-- cypress/e2e/ergonomia.cy.ts; aqui a ponte é retirada junto para não ficar
-- "quebrada" (bridge apontando para it() inexistente). ERGO-001 segue
-- documentado em qa_casos_teste e pendente até um teste com dado.
--
-- Idempotente: DELETE de linha ausente não faz nada.
-- =========================================================

DELETE FROM public.qa_cobertura_e2e WHERE codigo = 'ERGO-001';
