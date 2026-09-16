-- =====================================================================
-- SCRIPT DE ENTREGA · CENTRAL DE TESTES APOSENTADA
-- (a tela passa a ser a Central de Controle de Clientes)
--
-- Cole no SQL Editor do projeto. Roda em UMA transação e pode ser
-- executado mais de uma vez sem efeito diferente.
--
-- O QUE FAZ: desliga o disparo automático dos agentes da antiga Central
-- de Testes (job de pg_cron que rodava a cada minuto). Sem a tela, ele
-- só gastaria execução de função e escreveria histórico que ninguém lê.
--
-- O QUE NÃO FAZ: não apaga nem altera nenhum dado. As tabelas
-- youreyes_agentes, youreyes_documentos e youreyes_execucoes ficam
-- intactas, com todo o histórico; as funções continuam existindo.
-- Por isso não há cópia de segurança a fazer aqui.
--
-- PARA RELIGAR (se um dia quiser os agentes de volta):
--   SELECT cron.schedule('youreyes-dispatch-agentes', '* * * * *',
--                        'SELECT public.youreyes_dispatch_agentes()');
--
-- Conteúdo igual ao da migration 20260916185000_central_testes_aposentada.sql.
-- =====================================================================

DO $aposenta$
BEGIN
  PERFORM cron.unschedule('youreyes-dispatch-agentes');
  RAISE NOTICE 'Central de Testes: disparo automático dos agentes desligado.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Central de Testes: job youreyes-dispatch-agentes já não existia (%).', SQLERRM;
END
$aposenta$;

DO $comenta$
BEGIN
  COMMENT ON TABLE public.youreyes_agentes IS
    'Agentes da antiga Central de Testes (aposentada em 09/2026; disparo automático desligado). Mantida apenas para consulta do histórico.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Comentário da tabela youreyes_agentes não aplicado (%).', SQLERRM;
END
$comenta$;

-- ═══ CONFERÊNCIA (único resultado que o editor mostra) ═══
SELECT
  (SELECT count(*) FROM cron.job WHERE jobname = 'youreyes-dispatch-agentes')     AS jobs_ativos_deve_ser_zero,
  (SELECT count(*) FROM public.youreyes_agentes)                                   AS agentes_preservados,
  (SELECT count(*) FROM public.youreyes_documentos)                                AS documentos_preservados,
  (SELECT count(*) FROM public.youreyes_execucoes)                                 AS execucoes_preservadas,
  CASE WHEN (SELECT count(*) FROM cron.job WHERE jobname = 'youreyes-dispatch-agentes') = 0
       THEN 'OK — disparo desligado, histórico preservado'
       ELSE 'ATENÇÃO — o job continua agendado' END                                AS resultado;
