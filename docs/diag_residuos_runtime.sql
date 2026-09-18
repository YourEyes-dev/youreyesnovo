-- ============================================================================
-- DIAGNOSTICO runtime dos residuos (somente leitura, rollback) — rodar em
-- HOMOLOGACAO e em PRODUCAO. Roda as 5 rotinas e devolve situacao + o erro
-- tecnico real (quando 'erro') + o inicio do 'obtido'. Nao altera nada.
-- ============================================================================
SET lock_timeout = '10s';

SELECT caso,
       (r).situacao::text AS situacao,
       left(COALESCE((r).erro_tecnico,''), 200) AS erro_tecnico,
       left(COALESCE((r).obtido,''), 160) AS obtido
FROM (
  SELECT 'COLAB-011' AS caso, public.qa_executar_descartavel('qa_caso_colab_011') AS r
  UNION ALL SELECT 'COLAB-023', public.qa_executar_descartavel('qa_caso_colab_023')
  UNION ALL SELECT 'COLAB-033', public.qa_executar_descartavel('qa_caso_colab_033')
  UNION ALL SELECT 'DESL-003',  public.qa_executar_descartavel('qa_caso_desl_003')
  UNION ALL SELECT 'HIER-002',  public.qa_executar_descartavel('qa_caso_hier_002')
) s
ORDER BY caso;
