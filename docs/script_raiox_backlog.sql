-- ============================================================================
-- RAIO-X do backlog restante — DIAGNOSTICO (somente leitura).
--
-- Roda os casos ainda abertos (Temas 3 e 4 + residuos de QA) com o executor
-- descartavel (simulacao em transacao, com ROLLBACK): NAO altera nada. Pode
-- rodar direto na producao — nenhuma linha e tocada.
--
-- Objetivo: saber EXATAMENTE o que ja esta verde e o que ainda esta vermelho
-- em cada ambiente, para planejar as entregas sem adivinhar. Todos esses casos
-- ja passam no desenvolvimento; o que falta e a entrega (drift).
--
-- Leitura: situacao ∈ passou (ja ok aqui) | falhou (achado presente) |
--          erro (rotina/objeto ausente) | nao_implementado | SEM_ROTINA.
-- ============================================================================

WITH casos(codigo, tema) AS (
  VALUES
    ('PONTO-252','T3 segregacao'), ('FERIAS-056','T3 segregacao'),
    ('DESL-002','T3 segregacao'),  ('DESL-106','T3 segregacao'),
    ('EMP-020','T4 duplicidade'),  ('EMP-021','T4 duplicidade'),
    ('EMP-070','T4 duplicidade'),  ('EMP-071','T4 duplicidade'),
    ('AFAST-001','residuo QA'),    ('COLAB-011','residuo QA'),
    ('COLAB-023','residuo QA'),    ('COLAB-033','residuo QA'),
    ('DESL-003','residuo QA'),     ('HIER-002','residuo QA'),
    ('DADO-010','residuo QA'),     ('HCAT-010','residuo QA'),
    ('HTPL-010','residuo QA')
)
SELECT
  c.tema,
  c.codigo,
  CASE WHEN p.oid IS NULL THEN 'SEM_ROTINA'
       ELSE (public.qa_executar_descartavel('qa_caso_'||lower(replace(c.codigo,'-','_')))).situacao::text
  END AS situacao
FROM casos c
LEFT JOIN pg_proc p
  ON p.proname = 'qa_caso_'||lower(replace(c.codigo,'-','_'))
 AND p.pronamespace = 'public'::regnamespace
ORDER BY c.tema, c.codigo;
