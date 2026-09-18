-- ============================================================================
-- DIAGNOSTICO dos residuos do motor (somente leitura) — rodar em HOMOLOGACAO
-- e em PRODUCAO. Para cada caso: a rotina de QA existe? o controle existe?
-- Nao altera nada.
-- ============================================================================
WITH chk AS (
  SELECT
    -- rotinas de QA
    (to_regprocedure('public.qa_caso_colab_011()') IS NOT NULL) AS rot_colab011,
    (to_regprocedure('public.qa_caso_colab_023()') IS NOT NULL) AS rot_colab023,
    (to_regprocedure('public.qa_caso_colab_033()') IS NOT NULL) AS rot_colab033,
    (to_regprocedure('public.qa_caso_desl_003()')  IS NOT NULL) AS rot_desl003,
    (to_regprocedure('public.qa_caso_hier_002()')  IS NOT NULL) AS rot_hier002,
    -- controles
    EXISTS (SELECT 1 FROM pg_constraint WHERE conname='usuarios_base_colaborador_exige_cpf'
              AND conrelid='public.usuarios_base'::regclass) AS ctl_colab011,
    (to_regclass('public.usuarios_base_email_tenant_uidx') IS NOT NULL) AS ctl_colab023,
    (to_regclass('public.usuarios_base_cpf_norm_tenant_uidx') IS NOT NULL) AS ctl_colab033,
    EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_admissao_bloqueia_dispensa_afastamento'
              AND tgrelid='public.admissoes'::regclass AND NOT tgisinternal) AS ctl_desl003,
    EXISTS (SELECT 1 FROM pg_constraint WHERE conname='empresa_cadastro_grupo_economico_id_fkey'
              AND conrelid='public.empresa_cadastro'::regclass) AS ctl_hier002
)
SELECT 'COLAB-011' AS caso, rot_colab011::text AS rotina, ctl_colab011::text AS controle FROM chk
UNION ALL SELECT 'COLAB-023', rot_colab023::text, ctl_colab023::text FROM chk
UNION ALL SELECT 'COLAB-033', rot_colab033::text, ctl_colab033::text FROM chk
UNION ALL SELECT 'DESL-003',  rot_desl003::text,  ctl_desl003::text  FROM chk
UNION ALL SELECT 'HIER-002',  rot_hier002::text,  ctl_hier002::text  FROM chk
ORDER BY caso;
