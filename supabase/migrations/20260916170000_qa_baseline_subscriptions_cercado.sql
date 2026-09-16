-- ============================================================================
-- QA — linha de base do cercado: registrar a assinatura própria do tenant de QA.
--
-- O detector de vazamento (qa_verifica_vazamento) compara a contagem de linhas
-- do cercado, por tabela, com a linha de base gravada em qa_mobiliario_fixo. A
-- base foi medida cedo (quando o cercado só tinha pastas de documento e o
-- cadastro da empresa); a assinatura do próprio tenant de QA (plano "tester",
-- status trialing) é semeada por migration POSTERIOR. Resultado: a base espera
-- 0 em `subscriptions`, o cercado tem 1, e a bateria acusa
-- ">>> VAZAMENTO" mesmo com o cercado íntegro. Não é dado esquecido de teste —
-- é mobiliário fixo (a assinatura de billing do tenant de QA) que a base ainda
-- não conhecia.
--
-- Correção forward-only e idempotente: alinhar SÓ a linha `subscriptions` da
-- base à contagem real do cercado em repouso, sem tocar nas demais. Medir (em
-- vez de fixar "1") deixa a base exata em qualquer ambiente — se o seed não
-- rodou, fica 0; com ele, fica 1 — e nunca gera FALTA/SOBROU falso.
-- ============================================================================

DO $qa_baseline_sub$
DECLARE v_t uuid := public.qa_sandbox_tenant_id(); v_n bigint;
BEGIN
  IF v_t IS NULL THEN
    RAISE NOTICE 'Cercado ausente; linha de base de subscriptions nao ajustada.';
    RETURN;
  END IF;
  IF to_regclass('public.qa_mobiliario_fixo') IS NULL THEN
    RAISE NOTICE 'qa_mobiliario_fixo ausente; nada a ajustar.';
    RETURN;
  END IF;

  SELECT count(*) INTO v_n FROM public.subscriptions WHERE tenant_id = v_t;

  IF v_n > 0 THEN
    INSERT INTO public.qa_mobiliario_fixo (tabela, esperado, motivo)
    VALUES ('subscriptions', v_n,
            'Assinatura propria do tenant de QA (plano tester/trialing) — mobiliario fixo do cercado; a linha de base foi medida antes desse seed existir.')
    ON CONFLICT (tabela) DO UPDATE
      SET esperado = EXCLUDED.esperado, motivo = EXCLUDED.motivo, registrado_em = now();
  ELSE
    -- Sem assinatura no cercado: a base nao deve exigir nenhuma (remove entrada obsoleta, se houver).
    DELETE FROM public.qa_mobiliario_fixo WHERE tabela = 'subscriptions';
  END IF;
END $qa_baseline_sub$;
