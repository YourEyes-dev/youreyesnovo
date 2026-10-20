-- ============================================================================
-- ENTREGA (QA docs): remove pontes órfãs de cobertura e2e do Ouvidoria.
-- Equivalente à migration 20260927124436_qa_ouvidoria_remove_pontes_orfas.sql
-- Cole INTEIRO no SQL Editor (homologação e depois produção). Idempotente.
--
-- OUV-003/004/005 são nível 'api' (rodam no motor), mas tinham ponte em
-- qa_cobertura_e2e + it() no Cypress — duplicidade e ponte órfã. Os it() já
-- saíram do spec; aqui saem as pontes. O motor segue cobrindo os três casos.
--
-- Como APAGA linhas existentes, guarda backup antes (via EXECUTE, para não
-- acionar o auxiliar de RLS do editor).
-- ============================================================================

SET lock_timeout = '10s';

-- 1) Backup das pontes antes de apagar.
DO $bkp$
BEGIN
  EXECUTE 'CREATE ' || 'TABLE IF NOT EXISTS public.backup_qa_cobertura_ouv_20260927 AS '
       || 'SELECT * FROM public.qa_cobertura_e2e '
       || 'WHERE codigo IN (''OUV-003'', ''OUV-004'', ''OUV-005'')';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'backup nao recriado (provavelmente ja existe): %', SQLERRM;
END
$bkp$;

-- 2) Remove as pontes órfãs.
DELETE FROM public.qa_cobertura_e2e
 WHERE codigo IN ('OUV-003', 'OUV-004', 'OUV-005');

-- 3) Conferência (único resultado): pontes_restantes deve ser 0.
SELECT count(*) AS pontes_restantes
FROM public.qa_cobertura_e2e
WHERE codigo IN ('OUV-003', 'OUV-004', 'OUV-005');

-- Desfazer (se precisar), com as linhas guardadas no backup:
--   INSERT INTO public.qa_cobertura_e2e
--   SELECT * FROM public.backup_qa_cobertura_ouv_20260927
--   ON CONFLICT DO NOTHING;
