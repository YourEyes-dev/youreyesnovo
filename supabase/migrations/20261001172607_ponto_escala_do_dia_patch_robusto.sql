-- ============================================================================
-- Reforço do fix da escala por período: patch INDEPENDENTE DE ESPAÇAMENTO.
--
-- A migração 20261001170741 corrige os 6 resolvedores "do dia" por uma âncora
-- de 2 linhas (condição + indentação). Em ambientes cujo corpo da função tem
-- recuo diferente do repositório (produção/homologação divergiram), a âncora
-- não casava e a função ficava SEM o fix. Esta migração reaplica o mesmo fix
-- trocando só o PEDAÇO da condição ("COALESCE(a.ativa,true)=true"), sem depender
-- de quebra de linha/recuo — pegando qualquer variante.
--
-- Idempotente: pula o que já está corrigido. Só substitui FUNÇÃO. Só mexe no
-- alias "a" (atribuição) — não toca em "pa.ativa" (pré-assinalação).
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
        RAISE NOTICE '[%] já corrigida.', v_fn;
        CONTINUE;
      END IF;
      IF position(v_alvo IN v_src) = 0 THEN
        RAISE NOTICE '[%] condição não encontrada — pulada.', v_fn;
        CONTINUE;
      END IF;
      EXECUTE replace(v_src, v_alvo, v_novo);
      RAISE NOTICE '[%] corrigida (patch robusto).', v_fn;
    END LOOP;
  END LOOP;
END $fix$;
