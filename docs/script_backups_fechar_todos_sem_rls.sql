-- ============================================================================
-- SEGURANCA — Fechar o acesso via API a TODAS as tabelas backup_* (PRODUCAO)
-- Cole INTEIRO no SQL Editor de PRODUCAO (e, se quiser, da homologacao).
-- Espelha a migration 20261015235100_backups_fechar_todos_sem_rls.sql.
--
-- Substitui o script_backups_sem_rls.sql (lista fixa de 8 tabelas): este olha o
-- catalogo e fecha qualquer public.backup_* que esteja aberta, inclusive as que a
-- lista fixa nao conhecia (ex.: backup_superadmin_20260831 na homologacao).
-- Rodar os dois, em qualquer ordem, nao tem problema.
--
-- O que faz: liga RLS e revoga acesso de anon e authenticated. NAO altera, move nem
-- apaga nenhuma linha (por isso nao ha tabela de backup deste script).
-- Com RLS ligada e sem politica, so service_role e o dono do banco enxergam as
-- linhas, o que basta para restaurar qualquer correcao antiga.
--
-- NAO cria tabela nem funcao (sem auto-RLS do editor). Idempotente.
-- Para reabrir uma tabela: ALTER TABLE public.<tabela> DISABLE ROW LEVEL SECURITY;
-- e GRANT SELECT ON public.<tabela> TO authenticated; (nao recomendado).
-- ============================================================================

DO $rls$
DECLARE
  v_tab text;
BEGIN
  SET LOCAL lock_timeout = '10s';
  FOR v_tab IN
    SELECT c.relname
      FROM pg_class c
     WHERE c.relnamespace = 'public'::regnamespace
       AND c.relkind IN ('r', 'p')
       AND c.relname LIKE 'backup\_%'
     ORDER BY c.relname
  LOOP
    BEGIN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', v_tab);
      EXECUTE format('REVOKE ALL ON TABLE public.%I FROM anon, authenticated', v_tab);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'backup %: % (%)', v_tab, SQLERRM, SQLSTATE;
    END;
  END LOOP;
END
$rls$;

-- CONFERENCIA (unico resultado): todas as linhas devem dizer ok.
-- Lista vazia = nao ha tabela de backup nesta base.
SELECT c.relname AS tabela,
       c.relrowsecurity AS rls_ligada,
       has_table_privilege('anon', c.oid, 'SELECT') AS anon_le,
       has_table_privilege('authenticated', c.oid, 'SELECT') AS authenticated_le,
       CASE WHEN c.relrowsecurity
                 AND NOT has_table_privilege('anon', c.oid, 'SELECT')
                 AND NOT has_table_privilege('authenticated', c.oid, 'SELECT') THEN 'ok'
            ELSE 'ATENCAO: ainda aberta' END AS erro_tecnico
  FROM pg_class c
 WHERE c.relnamespace = 'public'::regnamespace
   AND c.relkind IN ('r', 'p')
   AND c.relname LIKE 'backup\_%'
 ORDER BY c.relname;
