-- ============================================================================
-- Compensacao de falta — guard de tenant ignora o cercado em modo de teste
--
-- Problema (motor de QA, PONTO-479/480/481/485 = "Acesso negado ao tenant"):
-- as RPCs de compensacao de falta tem o guard
--   IF auth.uid() IS NOT NULL AND get_user_tenant_id() IS DISTINCT FROM p_tenant_id
--     THEN RAISE 'Acesso negado ao tenant';
-- As rotinas de QA rodam no tenant do cercado (qa-sandbox), mas o motor e
-- disparado por um usuario logado real. Quando esse usuario nao e do sandbox
-- (ex.: disparado por alguem de um tenant real), auth.uid() nao e nulo e o
-- tenant dele difere do sandbox -> o guard derruba a rotina. Rodar como um
-- usuario do sandbox mascarava o problema (dependia de QUEM rodava a bateria).
--
-- Correcao: o guard passa a ser ignorado quando o modo de teste esta ligado
-- (app.qa_modo = on, que so existe DENTRO da transacao de teste, nunca em
-- operacao normal). A escrita cross-tenant continua barrada de verdade pela
-- CERCA (qa_bloqueia_fora_do_cercado), que e a protecao real. Em producao e em
-- qualquer request normal, app.qa_modo nao esta setado -> o guard segue EXATO
-- como antes (nenhuma mudanca de comportamento).
--
-- Le o GUC direto (sem chamar qa_modo_ligado()), para a funcao patchada nao
-- criar dependencia da bancada de QA — assim o patch e seguro ate onde a
-- bancada nao existe.
--
-- Patch dinamico: pega a definicao atual de cada RPC (pg_get_functiondef),
-- troca SO a linha do guard e recria. Preserva o corpo e o dono (CREATE OR
-- REPLACE mantem o owner). Idempotente: rodar de novo nao acha mais o alvo.
-- ============================================================================

DO $patch$
DECLARE
  v_names text[] := ARRAY[
    'ponto_falta_compensavel',
    'ponto_registrar_compensacao_falta',
    'ponto_autorizar_compensacao_falta',
    'ponto_homologar_compensacao_falta',
    'ponto_dar_ciencia_compensacao_falta',
    'ponto_cancelar_compensacao_falta'
  ];
  v_alvo text := 'public.get_user_tenant_id() IS DISTINCT FROM p_tenant_id THEN';
  v_subs text := 'public.get_user_tenant_id() IS DISTINCT FROM p_tenant_id AND COALESCE(current_setting(''app.qa_modo'', true), ''off'') <> ''on'' THEN';
  v_nome text;
  v_oid  oid;
  v_def  text;
BEGIN
  FOREACH v_nome IN ARRAY v_names LOOP
    FOR v_oid IN
      SELECT p.oid
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = v_nome
    LOOP
      v_def := pg_get_functiondef(v_oid);
      IF position(v_alvo IN v_def) > 0 THEN
        EXECUTE replace(v_def, v_alvo, v_subs);
        RAISE NOTICE 'Guard ajustado em %() — bypassa tenant quando app.qa_modo=on.', v_nome;
      ELSE
        RAISE NOTICE 'Guard em %() ja ajustado ou inexistente — nada a fazer.', v_nome;
      END IF;
    END LOOP;
  END LOOP;
END $patch$;
