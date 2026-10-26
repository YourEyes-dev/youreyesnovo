-- ============================================================================
-- CONFERENCIA READ-ONLY — ISOL-006 na PRODUCAO (diayjpsrcerycycyaxst)
--
-- SO LEITURA. Nao altera nada. Cole no SQL Editor da PRODUCAO para ver, entre as
-- 9 rotinas da entrega ISOL-006, QUAIS o usuario ANONIMO (chave publica) consegue
-- executar HOJE — ou seja, quais estao expostas sem login antes da correcao.
--
-- Leitura do resultado:
--   anon_executa = SIM  -> exposta: anon roda a rotina sem login (RLS roda depois).
--   anon_executa = nao  -> ja fechada.
--   (nao aparece)       -> a rotina nao existe nesta base (ex.: demo_dev_trilha_pool,
--                          que e drift so da homologacao).
-- Depois de aplicar o script de entrega, rode de novo: tudo deve vir 'nao'.
-- ============================================================================
SELECT
  p.proname                                              AS rotina,
  pg_get_function_identity_arguments(p.oid)              AS assinatura,
  CASE WHEN has_function_privilege('anon', p.oid, 'EXECUTE')
       THEN 'SIM' ELSE 'nao' END                         AS anon_executa,
  CASE WHEN has_function_privilege('authenticated', p.oid, 'EXECUTE')
       THEN 'sim' ELSE 'nao' END                         AS logado_executa,
  p.prosecdef                                            AS security_definer,
  (p.prorettype = 'pg_catalog.trigger'::regtype)         AS e_gatilho
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prokind = 'f'
  AND p.proname IN (
    'epi_devolver_entrega',
    'ponto_registrar_compensacao_falta',
    'ponto_dar_ciencia_compensacao_falta',
    'reconsiderar_marcacao_ponto',
    'admissoes_preserva_salario_mascarado',
    'profiles_protege_tenant',
    'audit_carimba_autor',
    'ponto_vinculo_cobre_periodo',
    'demo_dev_trilha_pool'
  )
ORDER BY anon_executa DESC, p.proname;
