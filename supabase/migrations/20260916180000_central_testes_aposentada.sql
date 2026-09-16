-- =====================================================================
-- Central de Testes aposentada → Central de Controle de Clientes
--
-- A tela "Central de Testes" (/admin/youreyes) mantinha uma segunda
-- documentação de testes, paralela à oficial (QA e testes → Documentação
-- de Testes). Decisão 09/2026: o lugar dela no menu passa a ser a
-- Central de Controle de Clientes (monitoramento dos clientes em
-- produção) e a equipe de agentes sai da navegação.
--
-- O que esta migration faz:
--   · desliga o disparo automático dos agentes (job de pg_cron que roda
--     a cada minuto) — sem tela, ele só gastaria execução de Edge
--     Function e escreveria histórico que ninguém lê.
--
-- O que esta migration NÃO faz (de propósito):
--   · não apaga youreyes_agentes, youreyes_documentos nem
--     youreyes_execucoes: o conteúdo já registrado fica guardado;
--   · não remove a função youreyes_dispatch_agentes nem a Edge Function
--     youreyes-run-agent — religar é só reagendar o job.
-- =====================================================================

DO $aposenta$
BEGIN
  PERFORM cron.unschedule('youreyes-dispatch-agentes');
  RAISE NOTICE 'Central de Testes: disparo automático dos agentes desligado.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Central de Testes: job youreyes-dispatch-agentes já não existia (%).', SQLERRM;
END
$aposenta$;

COMMENT ON TABLE public.youreyes_agentes IS
  'Agentes da antiga Central de Testes (aposentada em 09/2026; disparo automático desligado). Mantida apenas para consulta do histórico.';
