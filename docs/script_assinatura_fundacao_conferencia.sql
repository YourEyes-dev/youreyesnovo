-- ============================================================================
-- ASSINATURA FORTE — CONFERÊNCIA da fundação ASS-0001 + espelho (SOMENTE LEITURA)
-- Cole no SQL Editor ANTES (diagnóstico) e DEPOIS da sequência:
--   fundação parte1 -> fundação parte2 -> espelho parte2 -> espelho parte4
-- NÃO altera nada: só consulta o catálogo e roda os casos de QA pelo funil
-- qa_executar_descartavel (o dado do teste nunca persiste).
--
-- Esperado DEPOIS: todos os objetos true; versao_funcoes = 'final_30_10' (a do
-- staging); ass_001..003 e esp_ass_001..011 = 'passou'.
-- Se versao_funcoes = 'fundacao_26_10': falta reaplicar
-- docs/script_assinatura_espelho_parte2_funcoes.sql.
-- ============================================================================

WITH m AS MATERIALIZED (
  SELECT to_regprocedure('public.qa_executar_descartavel(text)') IS NOT NULL AS tem_motor
)
SELECT
  to_regprocedure('public.selar_assinatura(text,text,timestamptz,text)') IS NOT NULL AS selar_assinatura,
  to_regprocedure('public.selar_assinatura_origem()') IS NOT NULL AS selar_assinatura_origem,
  to_regprocedure('public.registrar_consentimento_biometrico(jsonb)') IS NOT NULL AS registrar_consentimento,
  to_regprocedure('public.registrar_assinatura_trilha(jsonb)') IS NOT NULL AS registrar_trilha,
  to_regprocedure('public.arquivar_documento_servidor(jsonb)') IS NOT NULL AS arquivar_documento,
  CASE
    WHEN to_regprocedure('public.arquivar_documento_servidor(jsonb)') IS NULL THEN 'ausente'
    WHEN position('subpasta_caminho' IN pg_get_functiondef(to_regprocedure('public.arquivar_documento_servidor(jsonb)'))) > 0
     AND position('assinatura_origem_efetiva' IN pg_get_functiondef(to_regprocedure('public.registrar_consentimento_biometrico(jsonb)'))) > 0
     AND position('assinatura_origem_efetiva' IN pg_get_functiondef(to_regprocedure('public.registrar_assinatura_trilha(jsonb)'))) > 0
      THEN 'final_30_10'
    ELSE 'fundacao_26_10'
  END AS versao_funcoes,
  to_regclass('public.consentimentos_assinatura') IS NOT NULL AS tab_consentimentos,
  to_regclass('public.assinaturas_trilha') IS NOT NULL AS tab_trilha,
  to_regclass('public.documento_audit_logs') IS NOT NULL AS tab_audit_logs,
  (SELECT bool_and(c.relrowsecurity) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname IN ('consentimentos_assinatura', 'assinaturas_trilha', 'documento_audit_logs')) AS rls_ligada,
  COALESCE((SELECT NOT b.public FROM storage.buckets b WHERE b.id = 'assinatura-evidencias'), false) AS bucket_privado,
  CASE WHEN NOT m.tem_motor OR to_regprocedure('public.qa_caso_ass_001()') IS NULL THEN 'ausente'
       ELSE (public.qa_executar_descartavel('qa_caso_ass_001')).situacao::text END AS ass_001,
  CASE WHEN NOT m.tem_motor OR to_regprocedure('public.qa_caso_ass_002()') IS NULL THEN 'ausente'
       ELSE (public.qa_executar_descartavel('qa_caso_ass_002')).situacao::text END AS ass_002,
  CASE WHEN NOT m.tem_motor OR to_regprocedure('public.qa_caso_ass_003()') IS NULL THEN 'ausente'
       ELSE (public.qa_executar_descartavel('qa_caso_ass_003')).situacao::text END AS ass_003,
  CASE WHEN NOT m.tem_motor OR to_regprocedure('public.qa_caso_esp_ass_001()') IS NULL THEN 'ausente'
       ELSE (public.qa_executar_descartavel('qa_caso_esp_ass_001')).situacao::text END AS esp_ass_001,
  CASE WHEN NOT m.tem_motor OR to_regprocedure('public.qa_caso_esp_ass_002()') IS NULL THEN 'ausente'
       ELSE (public.qa_executar_descartavel('qa_caso_esp_ass_002')).situacao::text END AS esp_ass_002,
  CASE WHEN NOT m.tem_motor OR to_regprocedure('public.qa_caso_esp_ass_003()') IS NULL THEN 'ausente'
       ELSE (public.qa_executar_descartavel('qa_caso_esp_ass_003')).situacao::text END AS esp_ass_003,
  CASE WHEN NOT m.tem_motor OR to_regprocedure('public.qa_caso_esp_ass_004()') IS NULL THEN 'ausente'
       ELSE (public.qa_executar_descartavel('qa_caso_esp_ass_004')).situacao::text END AS esp_ass_004,
  CASE WHEN NOT m.tem_motor OR to_regprocedure('public.qa_caso_esp_ass_005()') IS NULL THEN 'ausente'
       ELSE (public.qa_executar_descartavel('qa_caso_esp_ass_005')).situacao::text END AS esp_ass_005,
  CASE WHEN NOT m.tem_motor OR to_regprocedure('public.qa_caso_esp_ass_006()') IS NULL THEN 'ausente'
       ELSE (public.qa_executar_descartavel('qa_caso_esp_ass_006')).situacao::text END AS esp_ass_006,
  CASE WHEN NOT m.tem_motor OR to_regprocedure('public.qa_caso_esp_ass_007()') IS NULL THEN 'ausente'
       ELSE (public.qa_executar_descartavel('qa_caso_esp_ass_007')).situacao::text END AS esp_ass_007,
  CASE WHEN NOT m.tem_motor OR to_regprocedure('public.qa_caso_esp_ass_008()') IS NULL THEN 'ausente'
       ELSE (public.qa_executar_descartavel('qa_caso_esp_ass_008')).situacao::text END AS esp_ass_008,
  CASE WHEN NOT m.tem_motor OR to_regprocedure('public.qa_caso_esp_ass_009()') IS NULL THEN 'ausente'
       ELSE (public.qa_executar_descartavel('qa_caso_esp_ass_009')).situacao::text END AS esp_ass_009,
  CASE WHEN NOT m.tem_motor OR to_regprocedure('public.qa_caso_esp_ass_010()') IS NULL THEN 'ausente'
       ELSE (public.qa_executar_descartavel('qa_caso_esp_ass_010')).situacao::text END AS esp_ass_010,
  CASE WHEN NOT m.tem_motor OR to_regprocedure('public.qa_caso_esp_ass_011()') IS NULL THEN 'ausente'
       ELSE (public.qa_executar_descartavel('qa_caso_esp_ass_011')).situacao::text END AS esp_ass_011
FROM m;
