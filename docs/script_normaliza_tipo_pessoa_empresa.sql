-- ============================================================================
-- ENTREGA: Normaliza empresa_cadastro.tipo_pessoa ('juridica'->'pj', 'fisica'->'pf')
-- Equivalente à migration 20260927114429_normaliza_tipo_pessoa_empresa.sql
-- Cole INTEIRO no SQL Editor de PRODUÇÃO. Idempotente.
--
-- Por que: a trava chk_empresa_tipo_pessoa (NOT VALID) só aceita 'pj'/'pf'/NULL.
-- Linhas com o valor legado 'juridica' existiam, mas qualquer UPDATE delas falha
-- (erro 23514) — inclusive o UPDATE de recontagem de cotas que o trigger de
-- admissão dispara ao cadastrar um colaborador. Este script normaliza o legado.
--
-- Como ALTERA dado existente, guarda as linhas afetadas antes (backup). A tabela
-- de backup é criada via EXECUTE para NAO acionar o auxiliar de RLS do editor.
-- ============================================================================

SET lock_timeout = '10s';

-- 1) Backup das linhas que serao tocadas (some se rodar 2x: IF NOT EXISTS).
DO $bkp$
BEGIN
  EXECUTE 'CREATE ' || 'TABLE IF NOT EXISTS public.backup_empresa_tipo_pessoa_20260927 AS '
       || 'SELECT * FROM public.empresa_cadastro '
       || 'WHERE lower(btrim(tipo_pessoa)) IN '
       || '(''juridica'',''jurídica'',''pessoa juridica'',''pessoa jurídica'','
       || ' ''fisica'',''física'',''pessoa fisica'',''pessoa física'')';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'backup nao recriado (provavelmente ja existe): %', SQLERRM;
END
$bkp$;

-- 2) Normalizacao.
UPDATE public.empresa_cadastro
   SET tipo_pessoa = 'pj'
 WHERE lower(btrim(tipo_pessoa)) IN ('juridica', 'jurídica', 'pessoa juridica', 'pessoa jurídica');

UPDATE public.empresa_cadastro
   SET tipo_pessoa = 'pf'
 WHERE lower(btrim(tipo_pessoa)) IN ('fisica', 'física', 'pessoa fisica', 'pessoa física');

-- 3) Valida a constraint (se restar valor inesperado, registra e segue).
DO $valida$
BEGIN
  EXECUTE 'ALTER TABLE public.empresa_cadastro VALIDATE CONSTRAINT chk_empresa_tipo_pessoa';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'chk_empresa_tipo_pessoa nao validada: %', SQLERRM;
END
$valida$;

-- 4) Conferencia (unico resultado): ainda_invalidos deve ser 0.
SELECT
  count(*) FILTER (WHERE tipo_pessoa IS NOT NULL AND tipo_pessoa NOT IN ('pj','pf')) AS ainda_invalidos,
  count(*) FILTER (WHERE tipo_pessoa = 'pj') AS pj,
  count(*) FILTER (WHERE tipo_pessoa = 'pf') AS pf,
  count(*) FILTER (WHERE tipo_pessoa IS NULL) AS nulos
FROM public.empresa_cadastro;

-- Desfazer (se algum dia precisar), com as linhas guardadas no backup:
--   UPDATE public.empresa_cadastro ec
--      SET tipo_pessoa = b.tipo_pessoa
--     FROM public.backup_empresa_tipo_pessoa_20260927 b
--    WHERE b.id = ec.id;
