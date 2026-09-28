-- ============================================================================
-- ENTREGA — FOLHA · PARTE 2/2 (competências) — PRODUÇÃO
--
-- Rode SÓ DEPOIS da PARTE 1 (conferida, tudo 'ok'). Esta parte toca apenas
-- folha_periodos — assim nenhuma transação pega lock exclusivo em duas tabelas
-- movimentadas ao mesmo tempo (evita o deadlock que ocorreu na homologação com
-- o script único).
--
-- Cobre desta parte: FOLHA-070 (folha complementar: tipo + competência-mãe),
--        FOLHA-071 (reabertura exige rito — gatilho em folha_periodos),
--        FOLHA-081 (conferência de variação atípica). Só ALTER ADD COLUMN,
--        FUNCTION e TRIGGER; não cria tabela nem altera dado. Idempotente,
--        uma transação.
-- ============================================================================

SET lock_timeout = '10s';

-- ── FOLHA-070: folha complementar (colunas em folha_periodos) ───────────────
ALTER TABLE public.folha_periodos
  ADD COLUMN IF NOT EXISTS tipo_folha text NOT NULL DEFAULT 'normal';
ALTER TABLE public.folha_periodos
  ADD COLUMN IF NOT EXISTS competencia_origem_id uuid;

COMMENT ON COLUMN public.folha_periodos.tipo_folha IS
  'FOLHA-070: normal | complementar (dissidio/reajuste retroativo) | adiantamento.';
COMMENT ON COLUMN public.folha_periodos.competencia_origem_id IS
  'FOLHA-070: referencia a competencia-mae quando complementar.';

-- ── FOLHA-071: reabertura com rito (colunas em folha_periodos) ──────────────
ALTER TABLE public.folha_periodos
  ADD COLUMN IF NOT EXISTS reabertura_justificativa text;
ALTER TABLE public.folha_periodos
  ADD COLUMN IF NOT EXISTS reabertura_aprovada_por uuid;

-- ── FOLHA-071: reabrir competência fechada exige rito (gatilho em folha_periodos)
CREATE OR REPLACE FUNCTION public.folha_bloqueia_reabertura_sem_rito()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  -- Reabrir uma competencia fechada exige motivo (dupla aprovacao/trilha).
  IF OLD.status = 'fechado' AND NEW.status <> 'fechado'
     AND COALESCE(NEW.reabertura_justificativa, '') = '' THEN
    RAISE EXCEPTION
      'Reabertura de competencia fechada exige motivo e aprovacao registrados (FOLHA-071).'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_folha_bloqueia_reabertura_sem_rito ON public.folha_periodos;
CREATE TRIGGER trg_folha_bloqueia_reabertura_sem_rito
  BEFORE UPDATE OF status ON public.folha_periodos
  FOR EACH ROW EXECUTE FUNCTION public.folha_bloqueia_reabertura_sem_rito();

-- ── FOLHA-081: conferência de fechamento — variação atípica ─────────────────
CREATE OR REPLACE FUNCTION public.folha_conferencia_variacao(
  p_tenant    uuid,
  p_periodo_id uuid,
  p_limiar    numeric DEFAULT 0.20   -- 20% de variação destaca-se
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_atual   numeric;
  v_ant     numeric;
  v_var     numeric;
BEGIN
  -- Confronta o custo da competencia com a competencia anterior para destacar
  -- salto atipico na conferencia do fechamento (a trilha fica em folha_historico).
  SELECT total_liquido INTO v_atual FROM public.folha_periodos WHERE id = p_periodo_id;

  SELECT p2.total_liquido INTO v_ant
    FROM public.folha_periodos p1
    JOIN public.folha_periodos p2
      ON p2.tenant_id = p1.tenant_id AND p2.competencia < p1.competencia
    WHERE p1.id = p_periodo_id AND p1.tenant_id = p_tenant
    ORDER BY p2.competencia DESC
    LIMIT 1;

  IF v_ant IS NULL OR v_ant = 0 THEN
    RETURN jsonb_build_object('comparavel', false);
  END IF;

  v_var := (COALESCE(v_atual,0) - v_ant) / v_ant;

  RETURN jsonb_build_object(
    'comparavel', true,
    'total_atual', v_atual,
    'total_anterior', v_ant,
    'variacao', ROUND(v_var, 4),
    'atipica', abs(v_var) >= p_limiar
  );
END;
$$;

COMMENT ON FUNCTION public.folha_conferencia_variacao(uuid, uuid, numeric) IS
  'FOLHA-081: variacao atipica do custo da competencia vs. historico, para a conferencia do fechamento.';


-- ════════════════════ CONFERÊNCIA PARTE 2 (esperado tudo 'ok') ════════════════
WITH alvo(item, presente) AS (
  VALUES
    ('FOLHA-070 · folha complementar (colunas)',
       (EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='folha_periodos' AND column_name='tipo_folha')
        AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='folha_periodos' AND column_name='competencia_origem_id'))),
    ('FOLHA-071 · reabertura com rito (colunas)',
       (EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='folha_periodos' AND column_name='reabertura_justificativa')
        AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='folha_periodos' AND column_name='reabertura_aprovada_por'))),
    ('FOLHA-071 · gatilho reabertura exige rito',
       EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_folha_bloqueia_reabertura_sem_rito' AND NOT tgisinternal)),
    ('FOLHA-081 · conferência de variação atípica',
       (to_regprocedure('public.folha_conferencia_variacao(uuid,uuid,numeric)') IS NOT NULL))
)
SELECT item, CASE WHEN presente THEN 'ok' ELSE 'FALTOU' END AS situacao FROM alvo ORDER BY item;
