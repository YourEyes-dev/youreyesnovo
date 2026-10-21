-- ============================================================================
-- ENTREGA — agenda diaria que desativa os links externos de ponto vencidos
--
-- Cole ESTE arquivo inteiro no SQL Editor (HOMOLOGACAO e, depois, PRODUCAO).
-- Equivale ao bloco de cron da migration 20260804155000_qa_ponto_links_autoaprovacao_retencao.sql:
-- a funcao ponto_links_desativar_vencidos() ja existe na producao; so faltava o agendamento
-- (achado do levantamento main x producao de 20/10/2026).
--
-- So AGENDA (cron.schedule); nao altera nem apaga dado. Roda em UMA transacao e e idempotente:
-- se o job ja existe, e reagendado com o mesmo horario. Sem pg_cron, so avisa.
-- ============================================================================

DO $cron$
BEGIN
  IF to_regprocedure('public.ponto_links_desativar_vencidos()') IS NULL THEN
    RAISE NOTICE 'ponto_links_desativar_vencidos() nao existe neste ambiente: nada agendado.';
  ELSIF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('ponto-links-vencidos')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ponto-links-vencidos');
    PERFORM cron.schedule('ponto-links-vencidos', '17 3 * * *',
                          'SELECT public.ponto_links_desativar_vencidos();');
  ELSE
    RAISE NOTICE 'pg_cron ausente: chame ponto_links_desativar_vencidos() pela aplicacao.';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'agendamento ponto-links-vencidos: %', SQLERRM;
END
$cron$;

-- Conferencia (o editor mostra so o ultimo resultado). Esperado: funcao_existe = true e job_agendado = true.
SELECT to_regprocedure('public.ponto_links_desativar_vencidos()') IS NOT NULL AS funcao_existe,
       EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ponto-links-vencidos') AS job_agendado,
       (SELECT schedule FROM cron.job WHERE jobname = 'ponto-links-vencidos') AS horario;

-- Para desfazer: SELECT cron.unschedule('ponto-links-vencidos');
