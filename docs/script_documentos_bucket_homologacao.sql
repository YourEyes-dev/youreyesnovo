-- ============================================================================
-- ENTREGA (HOMOLOGACAO) — cofre de documentos: buckets de Storage + politicas
--
-- POR QUE ESTE SCRIPT EXISTE:
--   O upload de documentos na tela de Colaboradores/Admissoes grava no bucket
--   'documentos' (src/components/colaboradores/ColaboradorForm.tsx,
--   src/hooks/useAdmissoes.ts). Os buckets de Storage e suas politicas nascem
--   por seed manual (supabase/seeds/staging_buckets.sql) no TESTE e ja existem
--   na PRODUCAO. A HOMOLOGACAO e um projeto separado, forward-only, que NAO
--   recebeu essa parte de Storage — a linha do bucket 'documentos' nunca foi
--   criada em storage.buckets. Sem ela, qualquer upload devolve "Bucket not
--   found" e o arquivo nao sobe (mesmo com o registro de metadados aparecendo
--   como "Enviado" na tela). Este script traz o Storage da homologacao ao
--   mesmo estado do teste/producao. Mesmo padrao ja usado em
--   docs/script_ponto_selfie_bucket.sql para o bucket 'ponto-selfies'.
--
--   Aplique no SQL Editor da HOMOLOGACAO (fgsblefvdabgdouipigz). E idempotente:
--   em um projeto que ja tenha os buckets/politicas, ele e inocuo (roda duas
--   vezes sem quebrar nem duplicar).
--
-- SEGURANCA: so cria linhas de bucket e (re)cria funcao/politicas de Storage.
--   NAO altera, copia nem apaga nenhum dado de negocio nem arquivo existente.
--   Por isso nao ha bloco de backup (o script so CRIA coisa nova).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Buckets de Storage — espelham nome, visibilidade e limite da PRODUCAO
--    (mesma lista de supabase/seeds/staging_buckets.sql). ON CONFLICT deixa o
--    script idempotente e alinha public/file_size_limit de buckets ja criados.
-- ----------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES
  ('atestados',              'atestados',              false, NULL),
  ('avatars',                'avatars',                true,  NULL),
  ('blog-media',             'blog-media',             true,  104857600),
  ('documentos',             'documentos',             false, 52428800),
  ('empresas-logos',         'empresas-logos',         true,  NULL),
  ('epi-fotos',              'epi-fotos',              true,  NULL),
  ('epi-signatures',         'epi-signatures',         true,  NULL),
  ('ergonomia-evidencias',   'ergonomia-evidencias',   false, NULL),
  ('esocial-certificados',   'esocial-certificados',   false, 5242880),
  ('eventos-sst',            'eventos-sst',            false, NULL),
  ('feed-imagens',           'feed-imagens',           true,  NULL),
  ('hub-contabil',           'hub-contabil',           false, NULL),
  ('jornada-documentos',     'jornada-documentos',     false, NULL),
  ('marketplace-docs',       'marketplace-docs',       false, NULL),
  ('ouvidoria-anexos',       'ouvidoria-anexos',       false, 10485760),
  ('pdi-evidencias',         'pdi-evidencias',         false, NULL),
  ('plano-evidencias',       'plano-evidencias',       false, NULL),
  ('ponto-ajustes-anexos',   'ponto-ajustes-anexos',   false, NULL),
  ('ponto-selfies',          'ponto-selfies',          true,  NULL),
  ('sst-documentos',         'sst-documentos',         false, NULL),
  ('trilha-conteudo',        'trilha-conteudo',        true,  52428800),
  ('trilha-evidencias',      'trilha-evidencias',      false, NULL)
ON CONFLICT (id) DO UPDATE SET
  public          = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit;

-- ----------------------------------------------------------------------------
-- 2) Helper de tenants — reune TODOS os tenants acessiveis pelo usuario
--    (profile + usuarios_base + usuario_vinculos). Igual a migration
--    20260610230000_fix_upload_documentos_multitenant.sql. CREATE OR REPLACE
--    e idempotente e garante que as politicas abaixo tenham a funcao que citam.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.user_tenant_ids()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
  SELECT tenant_id FROM public.profiles WHERE user_id = auth.uid()
  UNION
  SELECT tenant_id FROM public.usuarios_base
   WHERE auth_user_id = auth.uid() AND status = 'ativo'
  UNION
  SELECT uv.tenant_id
    FROM public.usuario_vinculos uv
    JOIN public.usuarios_base ub ON ub.id = uv.usuario_id
   WHERE ub.auth_user_id = auth.uid()
     AND uv.status = 'ativo'
     AND (uv.data_fim IS NULL OR uv.data_fim >= CURRENT_DATE);
$fn$;

REVOKE EXECUTE ON FUNCTION public.user_tenant_ids() FROM anon;
GRANT  EXECUTE ON FUNCTION public.user_tenant_ids() TO authenticated;

-- ----------------------------------------------------------------------------
-- 3) Politicas do bucket 'documentos' — reconhecem qualquer tenant do usuario
--    (nao so o principal). Copia exata da migration 20260610230000. DROP/CREATE
--    e idempotente: reafirma as politicas caso a homologacao tenha nascido sem
--    elas (mesmo motivo do bucket faltante). Caminho: {tenant_id}/...
-- ----------------------------------------------------------------------------

-- INSERT (o upload que estava devolvendo "Bucket not found")
DROP POLICY IF EXISTS "documentos_multitenant_insert" ON storage.objects;
CREATE POLICY "documentos_multitenant_insert"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'documentos'
  AND (storage.foldername(name))[1] IN (SELECT public.user_tenant_ids()::text)
);

-- SELECT (para os documentos enviados aparecerem/pre-visualizarem)
DROP POLICY IF EXISTS "documentos_multitenant_select" ON storage.objects;
CREATE POLICY "documentos_multitenant_select"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'documentos'
  AND (storage.foldername(name))[1] IN (SELECT public.user_tenant_ids()::text)
);

-- UPDATE (upsert do upload)
DROP POLICY IF EXISTS "documentos_multitenant_update" ON storage.objects;
CREATE POLICY "documentos_multitenant_update"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'documentos'
  AND (storage.foldername(name))[1] IN (SELECT public.user_tenant_ids()::text)
);

-- DELETE (remover anexo)
DROP POLICY IF EXISTS "documentos_multitenant_delete" ON storage.objects;
CREATE POLICY "documentos_multitenant_delete"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'documentos'
  AND (storage.foldername(name))[1] IN (SELECT public.user_tenant_ids()::text)
);

-- ----------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor so mostra o ultimo resultado.
-- Esperado: bucket_documentos = true, limite_mb = 50, e as 4 colunas de
-- politica em true. buckets_criados = 22 (todos da lista acima presentes).
-- ----------------------------------------------------------------------------
SELECT
  EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'documentos')                       AS bucket_documentos,
  (SELECT file_size_limit / 1048576 FROM storage.buckets WHERE id = 'documentos')      AS limite_mb,
  (SELECT count(*) FROM storage.buckets
     WHERE id IN ('atestados','avatars','blog-media','documentos','empresas-logos',
                  'epi-fotos','epi-signatures','ergonomia-evidencias','esocial-certificados',
                  'eventos-sst','feed-imagens','hub-contabil','jornada-documentos',
                  'marketplace-docs','ouvidoria-anexos','pdi-evidencias','plano-evidencias',
                  'ponto-ajustes-anexos','ponto-selfies','sst-documentos','trilha-conteudo',
                  'trilha-evidencias'))                                                AS buckets_criados,
  EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects'
            AND policyname='documentos_multitenant_insert')                            AS pol_insert,
  EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects'
            AND policyname='documentos_multitenant_select')                            AS pol_select,
  EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects'
            AND policyname='documentos_multitenant_update')                            AS pol_update,
  EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects'
            AND policyname='documentos_multitenant_delete')                            AS pol_delete;
