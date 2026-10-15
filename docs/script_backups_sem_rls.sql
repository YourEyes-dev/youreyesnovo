-- ============================================================================
-- SEGURANCA — Fechar acesso via API as 8 tabelas de backup sem RLS (PRODUCAO)
-- Cole INTEIRO no SQL Editor de PRODUCAO. Espelha a migration
-- 20261015165521_backups_sem_rls_fechar_acesso.sql.
--
-- O que faz: liga RLS e revoga acesso de anon e authenticated nas 8 tabelas
-- backup_* que a conferencia de 15/10/2026 achou sem RLS. NAO altera, move nem
-- apaga nenhuma linha (por isso nao ha tabela de backup deste script).
-- Com RLS ligada e sem politica, so service_role e o dono do banco enxergam as
-- linhas, o que basta para restaurar qualquer correcao antiga.
--
-- NAO cria tabela nem funcao (sem auto-RLS do editor). Idempotente.
-- Para desfazer uma tabela: ALTER TABLE public.<tabela> DISABLE ROW LEVEL SECURITY;
-- e GRANT SELECT ON public.<tabela> TO authenticated; (nao recomendado).
-- ============================================================================

DO $rls$
DECLARE
  v_tab text;
  v_tabs text[] := ARRAY[
    'backup_conf_deslig_foto_20260929',
    'backup_conf_deslig_movs_20260929',
    'backup_encerra_deslig_afast_20260929',
    'backup_escala_desligados_20260929',
    'backup_features_20260925',
    'backup_features_nomes_20260925',
    'backup_ouv_pontes_20260925',
    'backup_plan_entitlements_20260925'
  ];
BEGIN
  SET LOCAL lock_timeout = '10s';
  FOREACH v_tab IN ARRAY v_tabs LOOP
    BEGIN
      IF to_regclass('public.' || quote_ident(v_tab)) IS NOT NULL THEN
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', v_tab);
        EXECUTE format('REVOKE ALL ON TABLE public.%I FROM anon, authenticated', v_tab);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'backup %: % (%)', v_tab, SQLERRM, SQLSTATE;
    END;
  END LOOP;
END
$rls$;

-- CONFERENCIA (unico resultado): esperado rls_ligada = true e anon/authenticated_le = false
SELECT t.nome,
       (c.oid IS NOT NULL) AS existe,
       c.relrowsecurity AS rls_ligada,
       CASE WHEN c.oid IS NULL THEN NULL ELSE has_table_privilege('anon', c.oid, 'SELECT') END AS anon_le,
       CASE WHEN c.oid IS NULL THEN NULL ELSE has_table_privilege('authenticated', c.oid, 'SELECT') END AS authenticated_le,
       CASE WHEN c.oid IS NULL THEN 'tabela ausente'
            WHEN c.relrowsecurity AND NOT has_table_privilege('anon', c.oid, 'SELECT')
                 AND NOT has_table_privilege('authenticated', c.oid, 'SELECT') THEN 'ok'
            ELSE 'ATENCAO: ainda aberta' END AS erro_tecnico
FROM unnest(ARRAY[
  'backup_conf_deslig_foto_20260929','backup_conf_deslig_movs_20260929',
  'backup_encerra_deslig_afast_20260929','backup_escala_desligados_20260929',
  'backup_features_20260925','backup_features_nomes_20260925',
  'backup_ouv_pontes_20260925','backup_plan_entitlements_20260925']) AS t(nome)
LEFT JOIN pg_class c ON c.relname = t.nome
  AND c.relnamespace = 'public'::regnamespace
ORDER BY t.nome;
