-- ============================================================================
-- CONFERIR OS 5 CASOS-ALVO DIRETO — sem rodar a bateria inteira (sem timeout)
--
-- A bateria completa (784 casos) estoura o teto de tempo do SQL Editor. Aqui
-- chamamos SÓ as 5 rotinas que mexemos nesta rodada — cada uma roda em ms.
--
-- Roda no CERCADO (qa-sandbox): não cria/altera/lê dado de cliente. O modo QA é
-- transação-local (some ao fim da query). Cole INTEIRO no SQL Editor da
-- HOMOLOGAÇÃO. Esperado: PONTO-402 / MKY-063 / MKY-123 / ISOL-005 / ISOL-006
-- com situacao = 'passou' (ou 'falhou' com achado, mas NUNCA 'erro').
-- ============================================================================

SELECT 'PONTO-402' AS caso, (x.r).situacao::text AS situacao, left((x.r).obtido, 200) AS detalhe
  FROM (SELECT public.qa_caso_ponto_402() AS r) x
UNION ALL
SELECT 'MKY-063', (x.r).situacao::text, left((x.r).obtido, 200)
  FROM (SELECT public.qa_caso_mky_063() AS r) x
UNION ALL
SELECT 'MKY-123', (x.r).situacao::text, left((x.r).obtido, 200)
  FROM (SELECT public.qa_caso_mky_123() AS r) x
UNION ALL
SELECT 'ISOL-005', (x.r).situacao::text, left((x.r).obtido, 200)
  FROM (SELECT public.qa_caso_isol_005() AS r) x
UNION ALL
SELECT 'ISOL-006', (x.r).situacao::text, left((x.r).obtido, 200)
  FROM (SELECT public.qa_caso_isol_006() AS r) x
ORDER BY caso;
