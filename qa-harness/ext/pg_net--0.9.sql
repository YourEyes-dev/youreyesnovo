-- stub de pg_net — ver pg_net.control. Devolve um id sequencial e não
-- dispara requisição nenhuma (não há rede no banco efêmero).
\echo Use "CREATE EXTENSION pg_net" to load this file. \quit

CREATE SCHEMA IF NOT EXISTS net;

CREATE SEQUENCE IF NOT EXISTS net._request_id_seq;

CREATE OR REPLACE FUNCTION net.http_post(
  url text,
  body jsonb DEFAULT '{}'::jsonb,
  params jsonb DEFAULT '{}'::jsonb,
  headers jsonb DEFAULT '{}'::jsonb,
  timeout_milliseconds integer DEFAULT 5000
) RETURNS bigint LANGUAGE sql AS
$f$ SELECT nextval('net._request_id_seq') $f$;

CREATE OR REPLACE FUNCTION net.http_get(
  url text,
  params jsonb DEFAULT '{}'::jsonb,
  headers jsonb DEFAULT '{}'::jsonb,
  timeout_milliseconds integer DEFAULT 5000
) RETURNS bigint LANGUAGE sql AS
$f$ SELECT nextval('net._request_id_seq') $f$;
