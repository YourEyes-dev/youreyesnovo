-- ============================================================================
-- ENTREGA — FOLHA · PARTE 1/2 (rubricas + lançamentos) — PRODUÇÃO
--
-- Divisão em duas partes para EVITAR DEADLOCK: o script único criava gatilhos em
-- DUAS tabelas movimentadas (folha_lancamentos e folha_periodos) na MESMA
-- transação — na homologação isso deu "deadlock detected" (regra da casa:
-- nunca gatilho em duas tabelas movimentadas numa transação só). Esta PARTE 1
-- toca apenas folha_rubricas (config) e folha_lancamentos; a PARTE 2 toca só
-- folha_periodos. Cole a PARTE 1, confira as linhas 'ok', depois a PARTE 2.
--
-- Conteúdo idêntico ao já validado na homologação — só reparticionado por tabela.
-- Cobre desta parte: FOLHA-001 (rubrica incompleta + trava no lançamento),
--        FOLHA-002 (vigência da rubrica), FOLHA-030 (amparo do desconto art.462),
--        FOLHA-071 (competência fechada trava lançamento — gatilho em
--        folha_lancamentos). Só ALTER ADD COLUMN, FUNCTION e TRIGGER; não cria
--        tabela nem altera dado. Idempotente, uma transação.
-- ============================================================================

SET lock_timeout = '10s';

-- ── FOLHA-002: vigência da rubrica (folha_rubricas) ─────────────────────────
ALTER TABLE public.folha_rubricas
  ADD COLUMN IF NOT EXISTS vigencia_inicio date;
ALTER TABLE public.folha_rubricas
  ADD COLUMN IF NOT EXISTS vigencia_fim date;

COMMENT ON COLUMN public.folha_rubricas.vigencia_inicio IS
  'FOLHA-002: inicio da vigencia da definicao da rubrica (incidencias por competencia).';

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

-- ── FOLHA-001: trava no lançamento (gatilho em folha_lancamentos) ───────────
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

-- ── FOLHA-071: competência fechada trava lançamento (gatilho em folha_lancamentos)
--    Lê folha_periodos.status em tempo de execução — a coluna já existe em produção.
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


-- ════════════════════ CONFERÊNCIA PARTE 1 (esperado tudo 'ok') ════════════════
WITH alvo(item, presente) AS (
  VALUES
    ('FOLHA-001 · rubrica incompleta (trava eSocial)',
       (to_regprocedure('public.folha_rubrica_incompleta(uuid)') IS NOT NULL)),
    ('FOLHA-001 · gatilho valida rubrica no lançamento',
       EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_folha_lancamento_valida_rubrica' AND NOT tgisinternal)),
    ('FOLHA-002 · vigência da rubrica (colunas)',
       (EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='folha_rubricas' AND column_name='vigencia_inicio')
        AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='folha_rubricas' AND column_name='vigencia_fim'))),
    ('FOLHA-030 · amparo do desconto (art. 462)',
       (to_regprocedure('public.folha_valida_desconto_462(uuid,numeric,numeric)') IS NOT NULL)),
    ('FOLHA-071 · gatilho competência fechada imutável',
       EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_folha_bloqueia_lancamento_fechado' AND NOT tgisinternal))
)
SELECT item, CASE WHEN presente THEN 'ok' ELSE 'FALTOU' END AS situacao FROM alvo ORDER BY item;
