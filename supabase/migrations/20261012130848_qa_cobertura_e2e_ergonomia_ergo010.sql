-- =========================================================
-- QA — Ponte de cobertura e2e: ERGO-010 (Ergonomia) destravado.
--
-- O Bloqueio 1 (docs/BLOQUEIOS_PRODUTO_QA_E2E.md) foi resolvido: o "Novo Risco"
-- da tela de Ergonomia agora grava no inventário unificado gro_riscos (via
-- useGRORiscos.criarRisco), então o risco cadastrado APARECE no Inventário GRO —
-- exatamente o passo 3 do caso ERGO-010. Com a tela cumprindo o caso, o it()
-- correspondente passou a existir em cypress/e2e/ergonomia.cy.ts; aqui a ponte
-- liga o caso ao teste.
--
-- delete-then-insert: idempotente e converge para o título certo mesmo onde já
-- houvesse uma linha antiga do ERGO-010 (não havia, mas é a forma robusta).
-- =========================================================

DELETE FROM public.qa_cobertura_e2e WHERE codigo = 'ERGO-010';

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
VALUES ('ERGO-010', 'cypress/e2e/ergonomia.cy.ts',
        'cadastra um risco e ele aparece no Inventário GRO');
