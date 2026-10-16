-- =========================================================
-- QA — Ponte de cobertura e2e: ERGO-001 (Ergonomia) retomado.
--
-- O lote 20260909120000 ligou o ERGO-001 ("abre com as 7 abas do fluxo GRO"),
-- e o 20260909130000 o ADIOU (removeu a ponte) porque, com a ilha de QA vazia,
-- a tela mostra o EmptyState e não renderiza as abas — testar exigia semear a
-- base NR-17. O novo it() de cypress/e2e/ergonomia.cy.ts passou a FAZER esse
-- seed (clica "Inicializar Itens NR-17", backend idempotente) e então confere
-- as 7 abas. Aqui religamos a ponte ao título novo do it().
--
-- delete-then-insert (não ON CONFLICT DO NOTHING): o ERGO-001 pode ter uma
-- linha antiga com o título anterior em ambientes onde o lote foi aplicado mas
-- o "adiar" não — isto converge para o título certo em qualquer estado.
-- Idempotente: rodar de novo apaga e reinsere a mesma linha.
-- =========================================================

DELETE FROM public.qa_cobertura_e2e WHERE codigo = 'ERGO-001';

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
VALUES ('ERGO-001', 'cypress/e2e/ergonomia.cy.ts',
        'inicializa a base NR-17 e abre as 7 abas do fluxo GRO');
