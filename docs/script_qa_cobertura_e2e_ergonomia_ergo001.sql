-- =========================================================
-- ENTREGA QA — Ponte de cobertura e2e: ERGO-001 (Ergonomia) retomado.
--
-- Cole no SQL Editor do ambiente de TESTE primeiro; só depois de aprovado,
-- na produção. Religa o caso ERGO-001 ao it() de tela que o executa, agora
-- que o teste semeia a base NR-17 (clica "Inicializar Itens NR-17") antes de
-- conferir as 7 abas do fluxo GRO. Sem esta ponte, a guarda da esteira
-- (verificar-cobertura-e2e) trataria o it() como "inventado" e reprovaria.
--
-- Pré-requisito: o caso ERGO-001 já documentado em qa_casos_teste (nível e2e).
-- delete-then-insert: converge para o título certo mesmo onde já existia uma
-- linha antiga do ERGO-001. Idempotente. Roda em UMA transação; termina com
-- uma conferência (o SQL Editor só mostra o último resultado).
-- =========================================================

DELETE FROM public.qa_cobertura_e2e WHERE codigo = 'ERGO-001';

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
VALUES ('ERGO-001', 'cypress/e2e/ergonomia.cy.ts',
        'inicializa a base NR-17 e abre as 7 abas do fluxo GRO');

-- ── Conferência (última query: é o que o SQL Editor exibe) ──
SELECT c.codigo, c.spec, c.teste, c.ativo
FROM public.qa_cobertura_e2e c
WHERE c.spec = 'cypress/e2e/ergonomia.cy.ts'
ORDER BY c.codigo;
