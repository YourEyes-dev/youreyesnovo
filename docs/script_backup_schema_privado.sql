-- =====================================================================
-- SEG-0006 — Script de entrega: schema privado "backup", fora da API
--
-- Cria o schema 'backup' e garante que anon/authenticated nao o enxergam.
-- A partir daqui, todo backup de "antes de alterar dado" nasce em
-- backup.<assunto>_<aaaammdd>, nunca mais em public (onde a chave publica
-- anon tinha grant e um backup sem RLS vazava — salario/PII em 26/10/2026).
--
-- Idempotente. NAO cria tabela (nao aciona o auto-RLS do SQL Editor).
-- Termina com uma conferencia.
-- =====================================================================

create schema if not exists backup;

revoke all on schema backup from public;
revoke all on schema backup from anon, authenticated;
grant usage, create on schema backup to postgres;
grant usage on schema backup to service_role;

alter default privileges in schema backup revoke all on tables from public;
alter default privileges in schema backup revoke all on tables from anon, authenticated;

comment on schema backup is
  'SEG-0006: copias de seguranca de entregas (backup_<assunto>_<aaaammdd>). Fora da API; nunca expor a anon/authenticated. Regra em CLAUDE.md.';

-- Conferencia (esperado: existe=1, anon_usa=f, auth_usa=f):
select
  (select count(*) from information_schema.schemata where schema_name = 'backup') as schema_existe,
  has_schema_privilege('anon', 'backup', 'USAGE')          as anon_enxerga,
  has_schema_privilege('authenticated', 'backup', 'USAGE') as authenticated_enxerga;
