-- ============================================================================
-- DIAGNÓSTICO ISOL-005 — qual tabela sensível está com RLS DESLIGADO
--                        (SOMENTE LEITURA)
--
-- NÃO altera nada. Lista as tabelas base de public com coluna tenant_id (não
-- qa_%) cujo isolamento (RLS) está DESLIGADO — o que o ISOL-005 acusa. A
-- varredura anterior só ligou RLS nas cópias backup_* e só criou política nas
-- tabelas que já tinham RLS ligado; uma tabela VIVA não-backup com RLS desligado
-- escapou das duas. Este diagnóstico a identifica.
--
-- IMPORTANTE antes de corrigir: ligar RLS numa tabela viva CORTA o acesso atual.
-- Por isso preciso saber, de cada tabela listada:
--   • eh_backup: se for backup_*, a correção é ligar RLS + política somente
--     superadmin (o desfazer é do dono do banco, não afeta ninguém).
--   • linhas: quantas linhas tem (dá ideia se é usada).
--   • tem_policy_definida: se já há política escrita (mesmo com RLS off).
-- Com isso decido a política certa: somente_superadmin (se ninguém acessa) ou
-- isolamento por tenant (tenant_id = get_user_tenant_id(), se os clientes usam).
-- ============================================================================

SELECT
  c.relname AS tabela,
  (c.relname LIKE 'backup\_%') AS eh_backup,
  c.relrowsecurity AS rls_ligado,
  (SELECT reltuples::bigint FROM pg_class c2 WHERE c2.oid = c.oid) AS linhas_estimadas,
  EXISTS (SELECT 1 FROM pg_policies p WHERE p.schemaname='public' AND p.tablename=c.relname) AS tem_policy_definida,
  obj_description(c.oid) AS comentario
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
  AND c.relname NOT LIKE 'qa\_%'
  AND c.relrowsecurity = false
  AND EXISTS (SELECT 1 FROM pg_attribute a
               WHERE a.attrelid = c.oid AND a.attname = 'tenant_id'
                 AND a.attnum > 0 AND NOT a.attisdropped)
ORDER BY eh_backup, c.relname;
