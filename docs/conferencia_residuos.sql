-- ============================================================================
-- CONFERENCIA dos residuos do motor — rodar DEPOIS de
-- docs/script_residuos_colab033_desl003.sql, em transacao propria.
-- Roda as 5 rotinas com o executor descartavel (rollback). So-leitura no efeito.
-- Se pegar lock transitorio numa base movimentada, rode de novo.
-- ============================================================================
SET lock_timeout = '10s';

SELECT 'COLAB-011' AS caso, (public.qa_executar_descartavel('qa_caso_colab_011')).situacao::text AS situacao
UNION ALL SELECT 'COLAB-023', (public.qa_executar_descartavel('qa_caso_colab_023')).situacao::text
UNION ALL SELECT 'COLAB-033', (public.qa_executar_descartavel('qa_caso_colab_033')).situacao::text
UNION ALL SELECT 'DESL-003',  (public.qa_executar_descartavel('qa_caso_desl_003')).situacao::text
UNION ALL SELECT 'HIER-002',  (public.qa_executar_descartavel('qa_caso_hier_002')).situacao::text
ORDER BY caso;
