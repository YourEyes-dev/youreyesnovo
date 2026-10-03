-- =====================================================================
-- PREFLIGHT da Rede de Segurança — roda ANTES das migrations, num
-- Postgres puro (CI ou réplica local). Dá à base vazia a mesma mobília
-- que o Supabase oferece de fábrica e que as migrations pressupõem:
--   • papéis (anon, authenticated, service_role, authenticator, ...)
--   • schemas extensions / auth / storage
--   • auth.uid()/role()/jwt() lendo request.jwt.claims (o Motor simula
--     o usuário exatamente por esse GUC)
--   • auth.users, storage.objects/buckets, storage.foldername()
-- pg_cron e pg_net entram como EXTENSÕES-FALSAS (qa-harness/ext/) — ver
-- os .control. Nada aqui vai para staging/produção: é mobília de teste.
--
-- Regra de ouro: as MIGRATIONS não mudam. Tudo que falta para elas
-- atravessarem um banco vazio mora AQUI.
-- =====================================================================

-- ─── Papéis do Supabase ──────────────────────────────────────────────
DO $roles$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY[
    'anon','authenticated','service_role','authenticator',
    'supabase_admin','supabase_auth_admin','supabase_storage_admin',
    'dashboard_user','pgbouncer','supabase_realtime_admin'
  ] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
      EXECUTE format('CREATE ROLE %I NOLOGIN NOINHERIT', r);
    END IF;
  END LOOP;
  -- authenticator troca para os papéis de request; postgres herda todos
  -- para poder assumir qualquer um nas simulações.
  EXECUTE 'GRANT anon, authenticated, service_role TO authenticator';
  EXECUTE 'GRANT anon, authenticated, service_role TO postgres';
END $roles$;

-- ─── Schemas de base ─────────────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS storage;
GRANT USAGE ON SCHEMA extensions TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA auth       TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA storage    TO anon, authenticated, service_role;

-- Publicação de realtime criada de fábrica pelo Supabase; migrations fazem
-- ALTER PUBLICATION ... ADD TABLE. Vazia aqui é suficiente.
DO $pub$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;
END $pub$;

-- ─── auth.uid()/role()/jwt() — leem o GUC request.jwt.claims ─────────
-- O Motor faz set_config('request.jwt.claims', json_build_object('sub',..,
-- 'role','authenticated')::text, true). Estas funções o decodificam igual
-- ao Supabase real.
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')::uuid
$$;

CREATE OR REPLACE FUNCTION auth.role() RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'
$$;

CREATE OR REPLACE FUNCTION auth.email() RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email'
$$;

CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb
LANGUAGE sql STABLE AS $$
  SELECT COALESCE(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb)
$$;

-- ─── auth.users — alvo de muitas FKs e de algumas fixtures ───────────
CREATE TABLE IF NOT EXISTS auth.users (
  instance_id        uuid,
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  aud                varchar(255),
  role               varchar(255),
  email              varchar(255),
  encrypted_password varchar(255),
  email_confirmed_at timestamptz,
  invited_at         timestamptz,
  confirmation_token varchar(255),
  confirmation_sent_at timestamptz,
  recovery_token     varchar(255),
  recovery_sent_at   timestamptz,
  last_sign_in_at    timestamptz,
  raw_app_meta_data  jsonb,
  raw_user_meta_data jsonb,
  is_super_admin     boolean,
  created_at         timestamptz DEFAULT now(),
  updated_at         timestamptz DEFAULT now(),
  phone              text,
  phone_confirmed_at timestamptz,
  confirmed_at       timestamptz,
  banned_until       timestamptz,
  deleted_at         timestamptz,
  is_anonymous       boolean DEFAULT false
);
GRANT ALL ON auth.users TO service_role, supabase_auth_admin;
GRANT SELECT ON auth.users TO authenticated, anon;

-- ─── storage: buckets, objects, foldername/filename/extension ────────
CREATE TABLE IF NOT EXISTS storage.buckets (
  id         text PRIMARY KEY,
  name       text NOT NULL,
  owner      uuid,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  public     boolean DEFAULT false,
  avif_autodetection boolean DEFAULT false,
  file_size_limit    bigint,
  allowed_mime_types text[]
);

CREATE TABLE IF NOT EXISTS storage.objects (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bucket_id     text REFERENCES storage.buckets(id),
  name          text,
  owner         uuid,
  created_at    timestamptz DEFAULT now(),
  updated_at    timestamptz DEFAULT now(),
  last_accessed_at timestamptz DEFAULT now(),
  metadata      jsonb,
  path_tokens   text[],
  version       text,
  owner_id      text
);
GRANT ALL ON storage.buckets, storage.objects TO service_role, supabase_storage_admin;
GRANT SELECT ON storage.buckets, storage.objects TO authenticated, anon;

CREATE OR REPLACE FUNCTION storage.foldername(name text) RETURNS text[]
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE parts text[];
BEGIN
  parts := string_to_array(name, '/');
  RETURN parts[1 : GREATEST(array_length(parts, 1) - 1, 0)];
END $$;

CREATE OR REPLACE FUNCTION storage.filename(name text) RETURNS text
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE parts text[];
BEGIN
  parts := string_to_array(name, '/');
  RETURN parts[array_length(parts, 1)];
END $$;

CREATE OR REPLACE FUNCTION storage.extension(name text) RETURNS text
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE fn text; parts text[];
BEGIN
  fn := storage.filename(name);
  parts := string_to_array(fn, '.');
  RETURN parts[array_length(parts, 1)];
END $$;
