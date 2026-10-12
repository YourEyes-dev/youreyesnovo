-- =========================================================
-- ENTREGA QA — Ponte de cobertura e2e: ERGO-010 (Ergonomia) destravado.
--
-- Cole no SQL Editor do ambiente de TESTE primeiro; só depois de aprovado, na
-- produção. Liga o caso ERGO-010 ao it() de tela que o executa, agora que o
-- Bloqueio 1 foi resolvido (o "Novo Risco" grava em gro_riscos e o risco aparece
-- no Inventário GRO). Sem esta ponte, a guarda da esteira trataria o it() como
-- "inventado" e reprovaria.
--
-- Pré-requisito: o caso ERGO-010 já documentado em qa_casos_teste (nível e2e).
-- delete-then-insert: idempotente. Roda em UMA transação; termina com uma
-- conferência (o SQL Editor só mostra o último resultado).
-- =========================================================

DELETE FROM public.qa_cobertura_e2e WHERE codigo = 'ERGO-010';

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
VALUES ('ERGO-010', 'cypress/e2e/ergonomia.cy.ts',
        'cadastra um risco e ele aparece no Inventário GRO');

-- ── Conferência (última query: é o que o SQL Editor exibe) ──
SELECT c.codigo, c.spec, c.teste, c.ativo
FROM public.qa_cobertura_e2e c
WHERE c.spec = 'cypress/e2e/ergonomia.cy.ts'
ORDER BY c.codigo;
