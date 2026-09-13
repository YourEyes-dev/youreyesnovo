-- ============================================================================
-- Fase 3 (motores) — Férias, lote 2: pontes com Afastamentos e Ponto.
--
-- FERIAS-003: o recálculo do período aquisitivo passa a consultar os
--             afastamentos (art. 133, IV — benefício previdenciário > 6 meses
--             reinicia o aquisitivo).
-- FERIAS-024: afastamento sobreposto ao gozo SUSPENDE a solicitação de férias.
-- FERIAS-053: marcar ponto durante férias em gozo é recusado (a ponte
--             férias→ponto, que só existia para afastamentos).
-- ============================================================================

-- Colunas para registrar a interrupção do art. 133 no período aquisitivo.
ALTER TABLE public.ferias_periodos_aquisitivos
  ADD COLUMN IF NOT EXISTS interrompido_art133 boolean NOT NULL DEFAULT false;
ALTER TABLE public.ferias_periodos_aquisitivos
  ADD COLUMN IF NOT EXISTS interrompido_afastamento_id uuid;

-- ── FERIAS-003: recálculo consulta os afastamentos (art. 133) ───────────────
CREATE OR REPLACE FUNCTION public.ferias_recalcular_periodo(p_periodo_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r            public.ferias_periodos_aquisitivos%ROWTYPE;
    v_metodo     TEXT;
    v_faltas_pt  INTEGER;
    v_faltas     INTEGER;
    v_fonte      TEXT;
    v_direito    NUMERIC(4,1);
    v_meses      INTEGER;
    v_prev_dias  INTEGER;
    v_af_id      UUID;
BEGIN
    SELECT * INTO r FROM public.ferias_periodos_aquisitivos WHERE id = p_periodo_id;
    IF NOT FOUND THEN RETURN; END IF;

    -- Art. 133, IV (CLT): benefício previdenciário por mais de 6 meses (mesmo
    -- descontínuos) no período aquisitivo faz perder o direito; um novo período
    -- começa no retorno. Aqui zera o aquisitivo atual e registra a origem —
    -- consulta o módulo de Afastamentos (b31/b91) sobreposto à janela.
    SELECT COALESCE(SUM(
             (LEAST(COALESCE(a.data_fim, r.aquisitivo_fim), r.aquisitivo_fim)
              - GREATEST(a.data_inicio, r.aquisitivo_inicio)) + 1), 0),
           MAX(a.id)
      INTO v_prev_dias, v_af_id
      FROM public.afastamentos a
     WHERE a.tenant_id = r.tenant_id
       AND regexp_replace(COALESCE(a.colaborador_cpf, ''), '[^0-9]', '', 'g')
         = regexp_replace(COALESCE(r.colaborador_cpf, ''), '[^0-9]', '', 'g')
       AND a.tipo_principal_new IN ('beneficio_b31', 'beneficio_b91')
       AND a.data_inicio <= r.aquisitivo_fim
       AND COALESCE(a.data_fim, r.aquisitivo_fim) >= r.aquisitivo_inicio;

    IF COALESCE(v_prev_dias, 0) > 180 THEN
        UPDATE public.ferias_periodos_aquisitivos
           SET interrompido_art133         = true,
               interrompido_afastamento_id = v_af_id,
               dias_direito                = 0,
               dias_saldo                  = 0,
               calculado_em                = now(),
               validacao_motivo            = 'Art. 133, IV: beneficio previdenciario > 6 meses no periodo reinicia o aquisitivo (novo periodo a partir do retorno).'
         WHERE id = p_periodo_id;
        RETURN;
    END IF;

    -- Método da empresa (fallback: config geral do tenant → clt_faltas)
    SELECT metodo_calculo INTO v_metodo
      FROM public.ferias_config
     WHERE tenant_id = r.tenant_id
       AND empresa_id IS NOT DISTINCT FROM r.empresa_id
     LIMIT 1;
    IF v_metodo IS NULL THEN
        SELECT metodo_calculo INTO v_metodo
          FROM public.ferias_config
         WHERE tenant_id = r.tenant_id AND empresa_id IS NULL
         LIMIT 1;
    END IF;
    v_metodo := COALESCE(v_metodo, 'clt_faltas');

    -- Fonte das faltas: ponto tem precedência; senão, carga.
    v_faltas_pt := public.ferias_faltas_do_ponto(
        r.tenant_id, r.colaborador_cpf, r.aquisitivo_inicio, r.aquisitivo_fim
    );
    IF v_faltas_pt IS NOT NULL THEN
        v_faltas := v_faltas_pt;
        v_fonte  := 'ponto';
    ELSE
        v_faltas := COALESCE(r.faltas_carga, 0);
        v_fonte  := 'carga';
    END IF;

    IF v_metodo = 'proporcional_avos' THEN
        v_meses := GREATEST(0, LEAST(12,
            (EXTRACT(YEAR  FROM age(r.aquisitivo_fim + 1, r.aquisitivo_inicio)) * 12
           + EXTRACT(MONTH FROM age(r.aquisitivo_fim + 1, r.aquisitivo_inicio)))::INTEGER));
        v_direito := ROUND(v_meses * 2.5, 1);
        IF v_faltas > 32 THEN v_direito := 0; END IF;
    ELSE
        v_direito := public.ferias_dias_por_faltas_clt(v_faltas);
    END IF;

    UPDATE public.ferias_periodos_aquisitivos
       SET fonte_faltas        = v_fonte,
           faltas_consideradas = v_faltas,
           dias_direito        = v_direito,
           dias_saldo          = GREATEST(0, v_direito - COALESCE(dias_gozados, 0)),
           calculado_em        = now(),
           status = CASE
               WHEN v_direito = 0 AND v_faltas > 32
                    AND status NOT IN ('zerado_confirmado', 'encerrado')
                   THEN 'pendente_validacao'
               WHEN status = 'pendente_validacao' AND NOT (v_direito = 0 AND v_faltas > 32)
                   THEN 'ativo'
               ELSE status
           END,
           validacao_motivo = CASE
               WHEN v_direito = 0 AND v_faltas > 32
                   THEN v_faltas || ' faltas no período — art. 130 da CLT retira o direito a férias'
               ELSE validacao_motivo
           END
     WHERE id = p_periodo_id;
END;
$$;

-- ── FERIAS-024: afastamento sobreposto suspende as férias em gozo/aprovadas ─
-- Status 'suspenso' passa a existir; DP reprograma e devolve o saldo depois.
ALTER TABLE public.ferias_solicitacoes DROP CONSTRAINT IF EXISTS ferias_solicitacoes_status_check;
ALTER TABLE public.ferias_solicitacoes ADD CONSTRAINT ferias_solicitacoes_status_check
  CHECK (status = ANY (ARRAY['pendente','aprovado','recusado','cancelado','em_gozo','concluido','suspenso']));

CREATE OR REPLACE FUNCTION public.afastamento_suspende_ferias()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'ativo' AND NEW.data_inicio IS NOT NULL THEN
    UPDATE public.ferias_solicitacoes fs
       SET status = 'suspenso'
     WHERE fs.tenant_id = NEW.tenant_id
       AND regexp_replace(COALESCE(fs.colaborador_cpf, ''), '[^0-9]', '', 'g')
         = regexp_replace(COALESCE(NEW.colaborador_cpf, ''), '[^0-9]', '', 'g')
       AND fs.status IN ('em_gozo', 'aprovado')
       AND fs.data_inicio <= COALESCE(NEW.data_fim, fs.data_fim)
       AND fs.data_fim   >= NEW.data_inicio;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_afastamento_suspende_ferias ON public.afastamentos;
CREATE TRIGGER trg_afastamento_suspende_ferias
  AFTER INSERT OR UPDATE OF status, data_inicio, data_fim ON public.afastamentos
  FOR EACH ROW EXECUTE FUNCTION public.afastamento_suspende_ferias();

-- ── FERIAS-053: ponto durante férias em gozo é recusado ─────────────────────
-- Estende o validador de marcação (que só olhava afastamentos) para também
-- barrar quando há férias em gozo cobrindo a data (casamento por CPF).
CREATE OR REPLACE FUNCTION public.validar_batida_afastamento()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_af RECORD;
  v_fer RECORD;
BEGIN
  SELECT data_inicio, data_fim INTO v_af
    FROM public.afastamentos
   WHERE tenant_id = NEW.tenant_id
     AND colaborador_id = NEW.colaborador_id
     AND status::text IN ('ativo', 'beneficio_inss')
     AND NEW.data_marcacao BETWEEN data_inicio AND COALESCE(data_fim, DATE '9999-12-31')
   ORDER BY data_inicio DESC
   LIMIT 1;

  IF FOUND THEN
    RAISE EXCEPTION
      'Colaborador afastado desde % %. Não é possível registrar ponto durante o afastamento.',
      to_char(v_af.data_inicio, 'DD/MM/YYYY'),
      CASE WHEN v_af.data_fim IS NULL
           THEN '(sem data de término registrada)'
           ELSE 'até ' || to_char(v_af.data_fim, 'DD/MM/YYYY') END;
  END IF;

  -- Férias em gozo também suspendem a prestação de serviço (art. 129/130).
  SELECT data_inicio, data_fim INTO v_fer
    FROM public.ferias_solicitacoes
   WHERE tenant_id = NEW.tenant_id
     AND regexp_replace(COALESCE(colaborador_cpf, ''), '[^0-9]', '', 'g')
       = regexp_replace(COALESCE(NEW.colaborador_cpf, ''), '[^0-9]', '', 'g')
     AND status = 'em_gozo'
     AND NEW.data_marcacao BETWEEN data_inicio AND data_fim
   ORDER BY data_inicio DESC
   LIMIT 1;

  IF FOUND THEN
    RAISE EXCEPTION
      'Colaborador em férias (em gozo) de % a %. Não é possível registrar ponto durante as férias.',
      to_char(v_fer.data_inicio, 'DD/MM/YYYY'), to_char(v_fer.data_fim, 'DD/MM/YYYY');
  END IF;

  RETURN NEW;
END;
$$;
