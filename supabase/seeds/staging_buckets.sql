-- Criação dos buckets de Storage no ambiente de staging.
-- Execute no SQL Editor do projeto de staging DEPOIS de aplicar as migrations.
-- Espelha exatamente os buckets existentes em produção (nome, visibilidade e limite de tamanho).

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES
  ('atestados',              'atestados',              false, NULL),
  ('avatars',                'avatars',                true,  NULL),
  ('blog-media',             'blog-media',             true,  104857600),
  ('documentos',             'documentos',             false, 52428800),
  ('empresas-logos',         'empresas-logos',         true,  NULL),
  ('epi-evidencias',         'epi-evidencias',         false, NULL),
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
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit;

-- As policies de storage.objects já vêm nas migrations de `supabase/migrations/`.
-- Confira depois com:
--   SELECT bucket_id, count(*) FROM storage.objects GROUP BY 1;
--   SELECT policyname FROM pg_policies WHERE schemaname = 'storage';
