-- Status dos scripts de entrega POSTERIORES ao roteiro de Acesso (SOMENTE LEITURA).
-- Cole no SQL Editor da PRODUCAO (e da HOMOLOGACAO para comparar). Nao altera nada.
-- Leitura: true / numero esperado = ja aplicado; false / 0 = ainda falta.
-- Feriados fase 1 (backfill de dados) e fase 2 (corpo de funcao) nao tem marca estrutural:
-- confira-os pelos scripts de portao em docs (precheck e golden do resolver).
SELECT
  -- Psicossocial (13/10)
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'validate_tipo_instrumento_campanha') AS p1_tipo_instrumento,
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'calcular_nivel_gro_risco') AS p2_gro_severidade,
  -- Cultura & Celebracoes (18/10)
  EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public'
          AND table_name = 'cultura_config' AND column_name = 'automacao_aniversario') AS c1_automacao_colunas,
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'cultura_automacao_rodar') AS c2_automacao_rotina,
  EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cultura-automacao-diaria') AS c3_cron_diario,
  EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public'
          AND table_name = 'cultura_config' AND column_name = 'lembrar_gestor') AS c4_lembrar_gestor,
  to_regclass('public.cultura_dias_profissao') IS NOT NULL AS c5_dias_profissao,
  -- Declaracao de comparecimento / abono legal art. 473 (20/10)
  EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public'
          AND table_name = 'ponto_justificativas' AND column_name = 'base_legal') AS d1_base_legal,
  EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_justificativa_trava_legal') AS d2_trava_legal,
  EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public'
          AND table_name = 'atestados' AND column_name = 'abona') AS d3_atestados_abona,
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'seed_justificativa_declaracao') AS d4_seed_declaracao,
  -- Motor de QA dessas entregas
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND (p.proname LIKE 'qa_caso_cult_%' OR p.proname LIKE 'qa_caso_fer_%'
       OR p.proname LIKE 'qa_caso_abono_%')) AS q1_rotinas_cultura_feriados_abono,
  (SELECT count(*) FROM public.qa_casos_teste WHERE codigo LIKE 'ABONO-%') AS q2_casos_abono,
  (SELECT count(*) FROM public.qa_cobertura_e2e WHERE codigo IN ('ERGO-001','ERGO-010')) AS q3_pontes_ergo_esperado_2;
