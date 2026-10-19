-- ============================================================================
-- PRE-CHECK DE PARIDADE — Unificacao de feriados (SOMENTE LEITURA)
-- Rode no SQL Editor da PRODUCAO (diayjpsrcerycycyaxst) e me cole a linha.
-- Nao cria, nao altera, nao apaga nada.
--
-- Serve para garantir que os scripts das Fases 1 e 2 rodam sem surpresa de
-- drift: a Fase 1 usa ON CONFLICT (tenant_id, empresa_id) no vinculo, que
-- depende da trava FER-003; e cria o calendario a partir de empresa_cadastro
-- (estado/cidade). A Fase 2 troca a funcao feriados_da_empresa.
--
-- CRITERIO (tudo deve vir true / > 0):
--   tem_feriados, tem_tabelas, tem_itens, tem_vinculos   -> tabelas existem
--   tem_constraint_fer003                                -> ON CONFLICT da Fase 1 funciona
--   tem_resolver                                         -> Fase 2 tem o que substituir
--   emp_tem_estado_cidade                                -> Fase 1 preenche uf/municipio do calendario
-- E, de bonus, quanto trabalho a Fase 1 tera:
--   feriados_filial_ativos                               -> quantas linhas 'filial' serao migradas
-- ============================================================================

SELECT
  (to_regclass('public.feriados')                 IS NOT NULL) AS tem_feriados,
  (to_regclass('public.feriado_tabelas')          IS NOT NULL) AS tem_tabelas,
  (to_regclass('public.feriado_tabela_itens')     IS NOT NULL) AS tem_itens,
  (to_regclass('public.feriado_tabela_empresas')  IS NOT NULL) AS tem_vinculos,
  EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'uq_feriado_tabela_empresa_por_unidade'
      AND conrelid = to_regclass('public.feriado_tabela_empresas')
  )                                                            AS tem_constraint_fer003,
  (to_regprocedure('public.feriados_da_empresa(uuid,uuid,date,date)') IS NOT NULL) AS tem_resolver,
  (
    EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='empresa_cadastro' AND column_name='estado')
    AND
    EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='empresa_cadastro' AND column_name='cidade')
  )                                                            AS emp_tem_estado_cidade,
  (SELECT count(*) FROM public.feriados
     WHERE abrangencia='filial' AND tenant_id IS NOT NULL AND empresa_id IS NOT NULL
       AND COALESCE(ativo,true)=true)                          AS feriados_filial_ativos;
