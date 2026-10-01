-- ============================================================================
-- ENTREGA — apuração respeita a escala vigente em cada período (bug da troca de
-- escala que recalcula o passado com a escala nova).
-- Colar no SQL Editor de PRODUÇÃO (projeto diayjpsrcerycycyaxst).
--
-- ACHADO: ao trocar a escala de um colaborador, a atribuição antiga é encerrada
-- (data_fim + ativa=false). Os resolvedores "do dia" da apuração filtravam
-- "ativa=true" e, com isso, IGNORAVAM a atribuição encerrada mesmo para dias
-- DENTRO do período dela — caindo na escala ATUAL. Ex.: colaborador que passou
-- de 44h para 36h tinha agosto (ainda 44h) recalculado como 36h.
--
-- CORREÇÃO: honrar a atribuição ENCERRADA (ativa=false COM data_fim) nos dias do
-- seu intervalo; manter ignoradas só as CANCELADAS (ativa=false SEM data_fim).
-- Troca, nos 6 resolvedores por dia, "COALESCE(a.ativa,true)=true" por
-- "(COALESCE(a.ativa,true)=true OR a.data_fim IS NOT NULL)".
--
-- SEGURANÇA: só substitui FUNÇÃO (não cria tabela, não altera/apaga dado).
-- Cirúrgico e idempotente: parte da definição atual, injeta só a condição; se já
-- corrigida ou sem a âncora, apenas avisa. Só mexe no alias "a" (atribuição) —
-- não toca em "pa.ativa" (pré-assinalação). Termina com conferência.
--
-- EFEITO A SABER: depois de aplicar, o CÁLCULO AO VIVO (espelho/apuração) de
-- quem trocou de escala passa a refletir a escala certa de cada período. Os
-- saldos JÁ GRAVADOS no banco só mudam quando a competência for reapurada.
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
  v_anchor text := 'AND COALESCE(a.ativa, true) = true'
                 || E'\n    AND a.data_inicio <= p_data';
  v_fixed text := 'AND (COALESCE(a.ativa, true) = true OR a.data_fim IS NOT NULL)'
                 || E'\n    AND a.data_inicio <= p_data';
BEGIN
  FOREACH v_fn IN ARRAY v_funcs LOOP
    FOR v_oid IN
      SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = v_fn AND p.prokind = 'f'
    LOOP
      v_src := pg_get_functiondef(v_oid);
      IF position(v_fixed IN v_src) > 0 THEN
        RAISE NOTICE '[%] já corrigida — nada a fazer.', v_fn;
        CONTINUE;
      END IF;
      IF position(v_anchor IN v_src) = 0 THEN
        RAISE NOTICE '[%] âncora não encontrada (confira manualmente) — pulada.', v_fn;
        CONTINUE;
      END IF;
      EXECUTE replace(v_src, v_anchor, v_fixed);
      RAISE NOTICE '[%] corrigida.', v_fn;
    END LOOP;
  END LOOP;
END $fix$;


-- ---------------------------------------------------------------------
-- CONFERÊNCIA: cada resolvedor deve conter a condição corrigida.
-- Espera-se corrigida = true para todas as linhas.
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
