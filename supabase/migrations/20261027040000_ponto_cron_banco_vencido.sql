-- ============================================================================
-- CRÍTICO #2 — agenda a conversão de banco de horas VENCIDO em horas extras.
-- A função public.converter_banco_horas_vencido() já existe e está completa
-- (varre todos os tenants; converte saldo com prazo_compensacao vencido em HE,
-- marca convertido_extras e lança a movimentação) — mas NÃO estava agendada em
-- lugar nenhum (CLT art. 59 §5º: saldo não compensado no prazo vira HE a pagar).
-- Este script agenda um cron diário. Idempotente. Mesmo padrão dos demais crons
-- do sistema (pg_cron), guardado pela existência da extensão.
-- ============================================================================

SET lock_timeout = '10s';

DO $cron$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('ponto-banco-vencido-diario')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ponto-banco-vencido-diario');
    PERFORM cron.schedule('ponto-banco-vencido-diario', '25 4 * * *',
      'SELECT public.converter_banco_horas_vencido();');
    RAISE NOTICE 'Banco de horas vencido: conversão em HE agendada (04:25 UTC, diária).';
  ELSE
    RAISE NOTICE 'pg_cron ausente — a aplicação deve chamar public.converter_banco_horas_vencido() diariamente.';
  END IF;
END
$cron$;

-- Conferência: o job está agendado?
SELECT jobname, schedule, command
FROM cron.job
WHERE jobname = 'ponto-banco-vencido-diario';
