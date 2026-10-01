-- ============================================================================
-- ENTREGA — apuração respeita a escala vigente em cada período (bug da troca de
-- escala que recalcula o passado com a escala nova).
-- Colar no SQL Editor de PRODUÇÃO (projeto diayjpsrcerycycyaxst).
--
-- ACHADO: ao trocar a escala de um colaborador, a atribuição antiga é encerrada
-- (data_fim + ativa=false). Os resolvedores "do dia" da apuração filtravam
-- "ativa=true" e IGNORAVAM a atribuição encerrada mesmo para dias DENTRO do
-- período dela — caindo na escala ATUAL. Ex.: quem passou de 44h para 36h tinha
-- agosto (ainda 44h) recalculado como 36h.
--
-- CORREÇÃO: honrar a atribuição ENCERRADA (ativa=false COM data_fim) nos dias do
-- seu intervalo; manter ignoradas só as CANCELADAS (ativa=false SEM data_fim).
-- Troca, nos 6 resolvedores por dia, a condição "COALESCE(a.ativa,true)=true"
-- por "(COALESCE(a.ativa,true)=true OR a.data_fim IS NOT NULL)".
--
-- Esta versão é INDEPENDENTE DE ESPAÇAMENTO (troca só o pedaço da condição, não
-- depende de quebra de linha/recuo) — necessário porque em produção algumas
-- dessas funções têm recuo diferente do repositório.
--
-- SEGURANÇA: só substitui FUNÇÃO (não cria tabela, não altera/apaga dado).
-- Cirúrgico e idempotente: se já corrigida, pula; se não achar a condição,
-- avisa. Só mexe no alias "a" (atribuição) — não toca em "pa.ativa"
-- (pré-assinalação). Termina com conferência. Pode rodar quantas vezes quiser.
-- ============================================================================
DO $fix$
DECLARE
  v_fn text;
  v_funcs text[] := ARRAY[
    'ponto_jornada_do_dia',
    'ponto_escala_do_dia',
    'ponto_intervalo_janela_do_dia',
    'ponto_apurar_ciclo_plantao_do_dia',
    'ponto_debito_batida_do_dia',
    'ponto_pre_assinalacao_do_dia'
  ];
  v_oid oid;
  v_src text;
  v_alvo text  := 'COALESCE(a.ativa, true) = true';
  v_feito text := 'COALESCE(a.ativa, true) = true OR a.data_fim IS NOT NULL';
  v_novo text  := '(COALESCE(a.ativa, true) = true OR a.data_fim IS NOT NULL)';
BEGIN
  FOREACH v_fn IN ARRAY v_funcs LOOP
    FOR v_oid IN
      SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = v_fn AND p.prokind = 'f'
    LOOP
      v_src := pg_get_functiondef(v_oid);
      IF position(v_feito IN v_src) > 0 THEN
        RAISE NOTICE '[%] já corrigida — nada a fazer.', v_fn;
        CONTINUE;
      END IF;
      IF position(v_alvo IN v_src) = 0 THEN
        RAISE NOTICE '[%] condição não encontrada (confira manualmente) — pulada.', v_fn;
        CONTINUE;
      END IF;
      EXECUTE replace(v_src, v_alvo, v_novo);
      RAISE NOTICE '[%] corrigida.', v_fn;
    END LOOP;
  END LOOP;
END $fix$;


-- ---------------------------------------------------------------------
-- CONFERÊNCIA: todas as linhas devem vir corrigida = true.
-- ---------------------------------------------------------------------
SELECT
  p.proname AS funcao,
  pg_get_function_identity_arguments(p.oid) AS assinatura,
  (position('OR a.data_fim IS NOT NULL' IN pg_get_functiondef(p.oid)) > 0) AS corrigida
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prokind='f'
  AND p.proname IN (
    'ponto_jornada_do_dia','ponto_escala_do_dia','ponto_intervalo_janela_do_dia',
    'ponto_apurar_ciclo_plantao_do_dia','ponto_debito_batida_do_dia','ponto_pre_assinalacao_do_dia'
  )
ORDER BY funcao;
