-- SEG-0006 — schema privado "backup", fora da API.
--
-- Causa raiz do vazamento (26/10/2026): a regra da casa "faca backup antes de
-- alterar dado" criava copias em public.backup_<assunto>_<aaaammdd>. No schema
-- public o role anon (a chave publica embutida no site) tem grant por padrao,
-- entao um backup sem RLS ficava legivel por qualquer um — salario e PII de
-- producao chegaram a vazar por isso.
--
-- A partir daqui os backups nascem em backup.<assunto>_<aaaammdd>: um schema que
-- o PostgREST NAO expoe (so serve 'public') e que anon/authenticated nao
-- enxergam. Ver a regra atualizada no CLAUDE.md.

create schema if not exists backup;

revoke all on schema backup from public;
revoke all on schema backup from anon, authenticated;
grant usage, create on schema backup to postgres;
grant usage on schema backup to service_role;

-- Tabelas futuras no schema nao concedem nada a anon/authenticated (o inverso do public).
alter default privileges in schema backup revoke all on tables from public;
alter default privileges in schema backup revoke all on tables from anon, authenticated;

comment on schema backup is
  'SEG-0006: copias de seguranca de entregas (backup_<assunto>_<aaaammdd>). Fora da API; nunca expor a anon/authenticated. Regra em CLAUDE.md.';
