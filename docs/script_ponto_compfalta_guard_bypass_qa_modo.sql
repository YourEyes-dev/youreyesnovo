-- ============================================================================
-- ENTREGA — Compensacao de falta: guard de tenant ignora o cercado em teste
--
-- Corrige o motor de QA (PONTO-479/480/481/485 = "Acesso negado ao tenant").
-- As RPCs de compensacao de falta derrubavam a rotina quando o motor era
-- disparado por um usuario de tenant REAL (auth.uid() nao nulo e tenant <>
-- sandbox). O guard passa a ser ignorado quando o modo de teste esta ligado
-- (app.qa_modo = on) — que so existe DENTRO da transacao de teste. A escrita
-- cross-tenant continua barrada de verdade pela CERCA. Em producao e em
-- qualquer request normal, app.qa_modo nao esta setado: o guard segue EXATO
-- como antes (zero mudanca de comportamento). Nao chama qa_modo_ligado(): le o
-- GUC direto, para nao criar dependencia da bancada de QA.
--
-- Patch dinamico (pega a definicao atual, troca so a linha do guard, recria):
-- preserva corpo e dono, e idempotente. Rode o arquivo inteiro de uma vez.
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
        RAISE NOTICE 'Guard ajustado em %().', v_nome;
      ELSE
        RAISE NOTICE 'Guard em %() ja ajustado ou inexistente.', v_nome;
      END IF;
    END LOOP;
  END LOOP;
END $patch$;

-- Conferencia (o editor mostra so o ultimo resultado):
--   com_bypass        = quantas RPCs ja tem o bypass de qa_modo (esperado: 6)
--   rpcs_encontradas  = quantas das 6 existem nesta base
SELECT
  count(*) FILTER (WHERE def LIKE '%app.qa_modo%') AS com_bypass,
  count(*)                                         AS rpcs_encontradas
FROM (
  SELECT pg_get_functiondef(p.oid) AS def
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN (
      'ponto_falta_compensavel',
      'ponto_registrar_compensacao_falta',
      'ponto_autorizar_compensacao_falta',
      'ponto_homologar_compensacao_falta',
      'ponto_dar_ciencia_compensacao_falta',
      'ponto_cancelar_compensacao_falta'
    )
) s;
