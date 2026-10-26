-- SEG-0006 — remove as tabelas backup_* que migrations anteriores (serie
-- Acesso 2.x) criaram em public. Sao copias de dado sensivel sem RLS; o
-- ISOL-005 as acusa. A partir de 20261026140419 os backups vivem no schema
-- privado 'backup', fora da API. Esta migration limpa o que ficou no public
-- (staging e banco efemero do CI). Produção e homologacao ja foram limpas
-- pelos scripts de entrega. Idempotente.

DO $limpa_backups_public$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT tablename FROM pg_tables
    WHERE schemaname = 'public' AND tablename LIKE 'backup\_%'
  LOOP
    EXECUTE format('DROP TABLE IF EXISTS public.%I', r.tablename);
  END LOOP;
END
$limpa_backups_public$;
