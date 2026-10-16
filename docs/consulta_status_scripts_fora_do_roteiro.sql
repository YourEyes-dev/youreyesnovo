-- Status dos 12 scripts de entrega fora do roteiro de Acesso (SOMENTE LEITURA).
-- Cole no SQL Editor da PRODUCAO (e do TESTE para comparar). Nao altera nada.
-- Leitura: true / numero esperado = ja aplicado; false / 0 = ainda falta.
SELECT
  -- Mudam o comportamento das telas / do banco de negocio
  COALESCE(pg_get_functiondef(to_regprocedure('public.validate_tipo_instrumento_campanha()')) LIKE '%entrevista_coletiva%', false)
    AS s1_psico_entrevista_coletiva,
  COALESCE(pg_get_functiondef(to_regprocedure('public.calcular_nivel_gro_risco()')) LIKE '%psicossocial%', false)
    AS s2_gro_nivel_psicossocial,
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prosecdef
      AND NOT EXISTS (SELECT 1 FROM unnest(COALESCE(p.proconfig,'{}')) c WHERE c LIKE 'search_path=%')
      AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e'))
    AS s3_sec001_funcoes_sem_search_path_esperado_0,
  -- Motor de QA (nao muda comportamento do sistema para os clientes)
  (to_regprocedure('public.qa_caso_sec_001()') IS NOT NULL)                 AS q1_rotina_sec_001,
  (to_regprocedure('public.qa_caso_central_001()') IS NOT NULL)             AS q2_rotinas_central_eventos,
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('ponto_falta_compensavel','ponto_registrar_compensacao_falta',
                        'ponto_autorizar_compensacao_falta','ponto_homologar_compensacao_falta',
                        'ponto_dar_ciencia_compensacao_falta','ponto_cancelar_compensacao_falta')
      AND pg_get_functiondef(p.oid) LIKE '%app.qa_modo%')                   AS q3_ponto_bypass_qa_esperado_6,
  (to_regprocedure('public.qa_instalar_cercas()') IS NOT NULL)              AS q4_bancada_qa_presente,
  (to_regprocedure('public.qa_cobertura_e2e_por_modulo()') IS NOT NULL)     AS q5_cobertura_por_modulo,
  (SELECT count(*) FROM public.qa_cobertura_e2e WHERE spec = 'cypress/e2e/decimo-terceiro.cy.ts') AS q6_pontes_13o_esperado_10,
  (SELECT count(*) FROM public.qa_cobertura_e2e WHERE spec = 'cypress/e2e/folha-pagamento.cy.ts') AS q7_pontes_folha_esperado_3,
  (SELECT count(*) FROM public.qa_cobertura_e2e WHERE codigo IN ('ERGO-001','ERGO-010'))          AS q8_pontes_ergo_esperado_2;
