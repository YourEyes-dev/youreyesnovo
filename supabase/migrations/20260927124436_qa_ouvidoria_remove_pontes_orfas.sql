-- ============================================================================
-- QA — Remove pontes órfãs de cobertura e2e do Ouvidoria (OUV-003/004/005).
--
-- Esses casos foram convertidos para nível 'api' (rodam no motor, rotinas
-- qa_caso_ouv_003/004/005), mas continuavam com ponte em qa_cobertura_e2e +
-- it() no Cypress — cobertura duplicada e ponte órfã (a guarda avisa). Removida
-- a duplicidade: os it() saíram de cypress/e2e/ouvidoria.cy.ts e aqui saem as
-- pontes. O motor segue cobrindo os três casos.
--
-- Idempotente: DELETE por codigo (rodar de novo não quebra).
-- ============================================================================

SET lock_timeout = '10s';

DELETE FROM public.qa_cobertura_e2e
 WHERE codigo IN ('OUV-003', 'OUV-004', 'OUV-005');
