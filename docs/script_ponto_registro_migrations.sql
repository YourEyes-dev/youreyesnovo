-- SOMENTE LEITURA — este banco recebe migrations do CLI?
-- Nao cria, nao altera, nao apaga. O CASE evita erro onde o registro nao existe.
SELECT
  COALESCE(substring((SELECT valor FROM public.app_config WHERE chave = 'supabase_url')
                     FROM 'https?://([a-z0-9]+)\.'), '(sem supabase_url)') AS projeto,
  (to_regclass('supabase_migrations.schema_migrations') IS NOT NULL)       AS tem_registro,
  CASE WHEN to_regclass('supabase_migrations.schema_migrations') IS NULL THEN NULL
       ELSE (xpath('/row/c/text()', query_to_xml(
              'SELECT count(*) AS c FROM supabase_migrations.schema_migrations',
              false, true, '')))[1]::text::bigint END                      AS migrations_registradas,
  CASE WHEN to_regclass('supabase_migrations.schema_migrations') IS NULL THEN NULL
       ELSE (xpath('/row/c/text()', query_to_xml(
              'SELECT max(version) AS c FROM supabase_migrations.schema_migrations',
              false, true, '')))[1]::text END                              AS carimbo_mais_recente;
