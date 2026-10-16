-- stub de pg_cron — ver pg_cron.control. Só registra o agendamento numa
-- tabela; nada é de fato agendado (não há scheduler no banco efêmero).
\echo Use "CREATE EXTENSION pg_cron" to load this file. \quit

CREATE SCHEMA IF NOT EXISTS cron;

CREATE TABLE IF NOT EXISTS cron.job (
  jobid    bigserial PRIMARY KEY,
  jobname  text,
  schedule text,
  command  text,
  nodename text   DEFAULT 'localhost',
  nodeport integer DEFAULT 5432,
  database text   DEFAULT current_database(),
  username text   DEFAULT current_user,
  active   boolean DEFAULT true
);

CREATE TABLE IF NOT EXISTS cron.job_run_details (
  jobid     bigint,
  runid     bigserial PRIMARY KEY,
  job_pid   integer,
  database  text,
  username  text,
  command   text,
  status    text,
  return_message text,
  start_time timestamptz,
  end_time   timestamptz
);

CREATE OR REPLACE FUNCTION cron.schedule(job_name text, schedule text, command text)
RETURNS bigint LANGUAGE sql AS
$f$ INSERT INTO cron.job(jobname, schedule, command) VALUES (job_name, schedule, command) RETURNING jobid $f$;

CREATE OR REPLACE FUNCTION cron.schedule(schedule text, command text)
RETURNS bigint LANGUAGE sql AS
$f$ INSERT INTO cron.job(jobname, schedule, command) VALUES (NULL, schedule, command) RETURNING jobid $f$;

CREATE OR REPLACE FUNCTION cron.unschedule(job_name text)
RETURNS boolean LANGUAGE sql AS
$f$ DELETE FROM cron.job WHERE jobname = job_name; SELECT true $f$;

CREATE OR REPLACE FUNCTION cron.unschedule(job_id bigint)
RETURNS boolean LANGUAGE sql AS
$f$ DELETE FROM cron.job WHERE jobid = job_id; SELECT true $f$;
