-- =====================================================================
-- SEG-0006 — Limpeza das tabelas backup_* do schema public
--
-- Contexto: a regra da casa "faca backup antes de alterar dado" criava
-- copias em public.backup_<assunto>_<aaaammdd>. Essas copias ficaram
-- permanentes; algumas de dado sensivel (salario, usuarios) chegaram a
-- ficar com RLS desligado e grant para anon — vazamento fechado em
-- 26/10/2026 (as 12 expostas ja foram removidas). Este script remove as
-- backups RESTANTES (as travadas, RLS on sem politica, que o ISOL-005
-- ainda acusa) e deixa o public limpo.
--
-- Seguro: sao COPIAS. O dado real vive nas tabelas originais, que seguem
-- intactas e protegidas. Remover um backup so apaga a copia de seguranca
-- de uma entrega ja validada e no ar. Idempotente (roda duas vezes sem erro).
-- NAO cria tabela nova (nao aciona o auto-RLS do SQL Editor).
-- =====================================================================

SET lock_timeout = '10s';

DO $limpa_backups$
DECLARE
  r RECORD;
  n INT := 0;
BEGIN
  FOR r IN
    SELECT tablename
    FROM pg_tables
    WHERE schemaname = 'public'
      AND tablename LIKE 'backup\_%'
    ORDER BY tablename
  LOOP
    BEGIN
      EXECUTE format('DROP TABLE IF EXISTS public.%I', r.tablename);
      n := n + 1;
      RAISE NOTICE 'backup removido: %', r.tablename;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'nao removeu % (%): %', r.tablename, SQLSTATE, SQLERRM;
    END;
  END LOOP;
  RAISE NOTICE 'total de backups removidos: %', n;
END
$limpa_backups$;

-- Conferencia final (deve voltar 0): nenhuma tabela backup_* no public.
SELECT count(*) AS backups_restantes_no_public
FROM pg_tables
WHERE schemaname = 'public' AND tablename LIKE 'backup\_%';
