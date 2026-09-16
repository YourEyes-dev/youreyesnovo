-- ============================================================================
-- Fase 4 (motores) — Folha: rubricas classificadas e fechamento imutável.
--
-- FOLHA-001: rubrica sem natureza do eSocial é incompleta e não entra no cálculo.
-- FOLHA-002: vigência/versionamento da rubrica (a definição do passado se preserva).
-- FOLHA-030: desconto exige amparo do art. 462 (rubrica classificada, teto).
-- FOLHA-070: folha complementar (tipo + competência-mãe).
-- FOLHA-071: competência fechada é imutável; reabertura exige rito.
-- FOLHA-081: conferência de fechamento com variação atípica vs. histórico.
-- ============================================================================

-- ── FOLHA-002: vigência da rubrica ──────────────────────────────────────────
ALTER TABLE public.folha_rubricas
  ADD COLUMN IF NOT EXISTS vigencia_inicio date;
ALTER TABLE public.folha_rubricas
  ADD COLUMN IF NOT EXISTS vigencia_fim date;

COMMENT ON COLUMN public.folha_rubricas.vigencia_inicio IS
  'FOLHA-002: inicio da vigencia da definicao da rubrica (incidencias por competencia).';

-- ── FOLHA-070: folha complementar ───────────────────────────────────────────
ALTER TABLE public.folha_periodos
  ADD COLUMN IF NOT EXISTS tipo_folha text NOT NULL DEFAULT 'normal';
ALTER TABLE public.folha_periodos
  ADD COLUMN IF NOT EXISTS competencia_origem_id uuid;

COMMENT ON COLUMN public.folha_periodos.tipo_folha IS
  'FOLHA-070: normal | complementar (dissidio/reajuste retroativo) | adiantamento.';
COMMENT ON COLUMN public.folha_periodos.competencia_origem_id IS
  'FOLHA-070: referencia a competencia-mae quando complementar.';

-- ── FOLHA-071: reabertura com rito ──────────────────────────────────────────
ALTER TABLE public.folha_periodos
  ADD COLUMN IF NOT EXISTS reabertura_justificativa text;
ALTER TABLE public.folha_periodos
  ADD COLUMN IF NOT EXISTS reabertura_aprovada_por uuid;

-- ── FOLHA-001: rubrica incompleta (sem classificação do eSocial) ────────────
CREATE OR REPLACE FUNCTION public.folha_rubrica_incompleta(p_rubrica_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $$
  -- Rubrica sem classificacao_esocial (S-1010) é incompleta: não pode dirigir
  -- base de INSS/FGTS/IRRF. Serve de trava para o cálculo/lançamento.
  SELECT COALESCE(
    (SELECT fr.classificacao_esocial IS NULL OR btrim(fr.classificacao_esocial) = ''
       FROM public.folha_rubricas fr WHERE fr.id = p_rubrica_id),
    false);
$$;

COMMENT ON FUNCTION public.folha_rubrica_incompleta(uuid) IS
  'FOLHA-001: true quando a rubrica nao tem classificacao_esocial — bloqueia o uso no calculo.';

-- ── FOLHA-030: amparo do desconto (art. 462) ────────────────────────────────
CREATE OR REPLACE FUNCTION public.folha_valida_desconto_462(
  p_rubrica_id uuid,
  p_valor      numeric,
  p_salario_base numeric
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
DECLARE
  v_classificada boolean;
  v_categoria    text;
  v_teto         numeric;
BEGIN
  -- Regra do desconto amparado pelo art. 462 da CLT: só com amparo (lei, CCT,
  -- adiantamento) e dentro do teto. Exige rubrica classificada; VT tem teto de
  -- 6% do salario-base.
  v_classificada := p_rubrica_id IS NOT NULL AND NOT public.folha_rubrica_incompleta(p_rubrica_id);

  SELECT lower(COALESCE(fr.natureza_contabil, fr.classificacao_esocial, ''))
    INTO v_categoria
    FROM public.folha_rubricas fr WHERE fr.id = p_rubrica_id;

  v_teto := CASE WHEN v_categoria ILIKE '%transp%' THEN ROUND(COALESCE(p_salario_base,0) * 0.06, 2)
                 ELSE NULL END;

  RETURN jsonb_build_object(
    'tem_amparo', v_classificada,
    'teto', v_teto,
    'excede_teto', (v_teto IS NOT NULL AND COALESCE(p_valor,0) > v_teto)
  );
END;
$$;

COMMENT ON FUNCTION public.folha_valida_desconto_462(uuid, numeric, numeric) IS
  'FOLHA-030: valida amparo do desconto (art. 462) — rubrica classificada e teto (VT 6%).';

-- Trava no lançamento: desconto/uso de rubrica INCOMPLETA é recusado (CA-001).
-- Lançamentos sem rubrica_id (texto livre) não são afetados aqui.
CREATE OR REPLACE FUNCTION public.folha_lancamento_valida_rubrica()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.rubrica_id IS NOT NULL AND public.folha_rubrica_incompleta(NEW.rubrica_id) THEN
    RAISE EXCEPTION
      'Rubrica sem classificacao do eSocial (S-1010) nao pode ser usada no calculo da folha (CA-001).'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_folha_lancamento_valida_rubrica ON public.folha_lancamentos;
CREATE TRIGGER trg_folha_lancamento_valida_rubrica
  BEFORE INSERT OR UPDATE OF rubrica_id ON public.folha_lancamentos
  FOR EACH ROW EXECUTE FUNCTION public.folha_lancamento_valida_rubrica();

-- ── FOLHA-071: competência fechada é imutável ───────────────────────────────
CREATE OR REPLACE FUNCTION public.folha_bloqueia_lancamento_fechado()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  v_periodo uuid := COALESCE(NEW.periodo_id, OLD.periodo_id);
  v_status  text;
BEGIN
  SELECT status INTO v_status FROM public.folha_periodos WHERE id = v_periodo;
  IF v_status = 'fechado' THEN
    RAISE EXCEPTION
      'Competencia fechada é imutavel: lancamento so apos reabertura com rito (FOLHA-071).'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_folha_bloqueia_lancamento_fechado ON public.folha_lancamentos;
CREATE TRIGGER trg_folha_bloqueia_lancamento_fechado
  BEFORE INSERT OR UPDATE OR DELETE ON public.folha_lancamentos
  FOR EACH ROW EXECUTE FUNCTION public.folha_bloqueia_lancamento_fechado();

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
