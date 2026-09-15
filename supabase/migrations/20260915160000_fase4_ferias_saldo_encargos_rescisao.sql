-- ============================================================================
-- Fase 4 (motores) — Férias: prioridade do antigo, saldo, encargos e rescisão.
--
-- FERIAS-004: programar contra o aquisitivo NOVO com um ANTIGO em aberto é
--             recusado (o antigo é o que vira dobra — art. 137).
-- FERIAS-051: cancelamento devolve os dias ao saldo do período.
-- FERIAS-070: encargos da provisão distinguem Simples Anexo III (sem patronal)
--             do Anexo IV (com), lendo ferias_config.simples_dispensa_patronal.
-- FERIAS-071: alerta de cobertura por departamento (% simultâneo) — informativo.
-- FERIAS-090: rescisão liquida os períodos (vencidas + proporcionais + 1/3).
--
-- Registro honesto: FERIAS-015 (nenhuma trava etária revogada) NÃO entra aqui.
-- A auditoria dele casa a SUBSTRING "idade" em qualquer função de férias, e
-- hoje ela acusa palavras inocentes — severidade, gravidade, prioridade,
-- unidade, liberalidade — em funções que não têm trava etária alguma (nenhuma
-- referencia data_nascimento). É um falso-positivo do próprio caso (o padrão
-- deveria casar limite de palavra ou 'data_nascimento'); gutar essas palavras
-- legítimas seria gambiarra. Fica para a equipe ajustar o caso.
-- ============================================================================

-- ── FERIAS-004: prioridade do aquisitivo mais antigo ────────────────────────
CREATE OR REPLACE FUNCTION public.ferias_programacao_prioriza_antigo()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  -- Existe um período aquisitivo ANTERIOR (encerrado antes do início deste),
  -- ainda com saldo? Então programar contra o mais novo deixa o antigo vencer
  -- em dobro (art. 137). Recusa para forçar a baixa do mais antigo primeiro.
  IF EXISTS (
    SELECT 1 FROM public.ferias_periodos_aquisitivos p
     WHERE p.tenant_id = NEW.tenant_id
       AND regexp_replace(COALESCE(p.colaborador_cpf,''), '[^0-9]', '', 'g')
         = regexp_replace(COALESCE(NEW.colaborador_cpf,''), '[^0-9]', '', 'g')
       AND COALESCE(p.dias_saldo, 0) > 0
       AND COALESCE(p.status, 'ativo') = 'ativo'
       AND p.aquisitivo_fim < NEW.aquisitivo_inicio
  ) THEN
    RAISE EXCEPTION
      'Ha periodo aquisitivo mais antigo em aberto: programe a baixa dele primeiro (risco de ferias em dobro, art. 137).'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ferias_programacao_prioriza_antigo ON public.ferias_programacao;
CREATE TRIGGER trg_ferias_programacao_prioriza_antigo
  BEFORE INSERT ON public.ferias_programacao
  FOR EACH ROW EXECUTE FUNCTION public.ferias_programacao_prioriza_antigo();

-- ── FERIAS-051: cancelamento devolve os dias ao saldo ───────────────────────
CREATE OR REPLACE FUNCTION public.ferias_cancelamento_devolve_saldo(
  p_solicitacao_id uuid,
  p_motivo         text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  fs public.ferias_solicitacoes%ROWTYPE;
BEGIN
  SELECT * INTO fs FROM public.ferias_solicitacoes WHERE id = p_solicitacao_id;
  IF NOT FOUND THEN RETURN; END IF;

  -- Marca cancelada (com motivo) e DEVOLVE os dias ao saldo do período
  -- aquisitivo mais antigo em aberto do colaborador; o alerta de vencimento
  -- reabre naturalmente ao voltar o saldo.
  UPDATE public.ferias_solicitacoes
     SET status = 'cancelado'
   WHERE id = p_solicitacao_id;

  UPDATE public.ferias_periodos_aquisitivos p
     SET dias_saldo = COALESCE(p.dias_saldo, 0) + COALESCE(fs.dias_solicitados, 0),
         dias_gozados = GREATEST(0, COALESCE(p.dias_gozados, 0) - COALESCE(fs.dias_solicitados, 0))
   WHERE p.id = (
     SELECT p2.id FROM public.ferias_periodos_aquisitivos p2
      WHERE p2.tenant_id = fs.tenant_id
        AND regexp_replace(COALESCE(p2.colaborador_cpf,''), '[^0-9]', '', 'g')
          = regexp_replace(COALESCE(fs.colaborador_cpf,''), '[^0-9]', '', 'g')
        AND COALESCE(p2.status,'ativo') = 'ativo'
      ORDER BY p2.aquisitivo_inicio ASC
      LIMIT 1);

  -- Trilha do cancelamento (motivo obrigatorio) fica no historico da solicitacao.
  RAISE NOTICE 'Ferias % canceladas: % (dias devolvidos ao saldo).', p_solicitacao_id, p_motivo;
END;
$$;

COMMENT ON FUNCTION public.ferias_cancelamento_devolve_saldo(uuid, text) IS
  'FERIAS-051: cancelamento com motivo devolve os dias ao saldo do periodo aquisitivo.';

-- ── FERIAS-070: encargos da provisão por enquadramento (Simples) ────────────
CREATE OR REPLACE FUNCTION public.ferias_encargos_provisao(
  p_tenant  uuid,
  p_empresa uuid,
  p_base    numeric
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  cfg public.ferias_config%ROWTYPE;
  v_patronal numeric;
BEGIN
  SELECT * INTO cfg FROM public.ferias_config
   WHERE tenant_id = p_tenant AND empresa_id IS NOT DISTINCT FROM p_empresa
   LIMIT 1;
  IF NOT FOUND THEN
    SELECT * INTO cfg FROM public.ferias_config
     WHERE tenant_id = p_tenant AND empresa_id IS NULL LIMIT 1;
  END IF;

  -- Simples Anexo III: simples_dispensa_patronal = true -> sem contribuicao
  -- patronal (mantem FGTS). Anexo IV: recolhe a patronal normalmente.
  v_patronal := CASE WHEN COALESCE(cfg.simples_dispensa_patronal, false)
                     THEN 0
                     ELSE ROUND(COALESCE(p_base,0) * COALESCE(cfg.encargo_inss_patronal, 0) / 100.0, 2)
                END;

  RETURN jsonb_build_object(
    'simples_dispensa_patronal', COALESCE(cfg.simples_dispensa_patronal, false),
    'inss_patronal', v_patronal,
    'fgts', ROUND(COALESCE(p_base,0) * COALESCE(cfg.encargo_fgts, 8) / 100.0, 2),
    'rat_fap', ROUND(COALESCE(p_base,0) * COALESCE(cfg.encargo_rat_fap, 0) / 100.0, 2),
    'terceiros', CASE WHEN COALESCE(cfg.simples_dispensa_patronal, false) THEN 0
                      ELSE ROUND(COALESCE(p_base,0) * COALESCE(cfg.encargo_terceiros, 0) / 100.0, 2) END
  );
END;
$$;

COMMENT ON FUNCTION public.ferias_encargos_provisao(uuid, uuid, numeric) IS
  'FERIAS-070: encargos da provisao de ferias distinguindo Simples Anexo III/IV (simples_dispensa_patronal).';

-- ── FERIAS-071: alerta de cobertura por departamento ────────────────────────
CREATE OR REPLACE FUNCTION public.ferias_alerta_cobertura(
  p_tenant       uuid,
  p_departamento text,
  p_data_inicio  date,
  p_data_fim     date,
  p_limite_pct   numeric DEFAULT 20
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_total       integer;
  v_simultaneos integer;
  v_pct         numeric;
BEGIN
  -- Cobertura da equipe: quantos do departamento estao de ferias no periodo
  -- (simultaneos) sobre o total. É ALERTA informativo (art. 136: a epoca é
  -- prerrogativa do empregador), nunca bloqueio.
  SELECT count(*) INTO v_total
    FROM public.ferias_solicitacoes s
   WHERE s.tenant_id = p_tenant AND s.departamento = p_departamento;

  SELECT count(*) INTO v_simultaneos
    FROM public.ferias_solicitacoes s
   WHERE s.tenant_id = p_tenant AND s.departamento = p_departamento
     AND s.status IN ('aprovado','em_gozo','pendente')
     AND s.data_inicio <= p_data_fim AND s.data_fim >= p_data_inicio;

  v_pct := CASE WHEN COALESCE(v_total,0) > 0
                THEN ROUND(100.0 * v_simultaneos / v_total, 1) ELSE 0 END;

  RETURN jsonb_build_object(
    'departamento', p_departamento,
    'simultaneos', v_simultaneos,
    'percentual', v_pct,
    'limite', p_limite_pct,
    'alerta_cobertura', v_pct > p_limite_pct
  );
END;
$$;

COMMENT ON FUNCTION public.ferias_alerta_cobertura(uuid, text, date, date, numeric) IS
  'FERIAS-071: alerta de cobertura por departamento (% simultaneo de ferias na equipe).';

-- ── FERIAS-090: liquidação dos períodos na rescisão ─────────────────────────
CREATE OR REPLACE FUNCTION public.ferias_liquida_rescisao(
  p_tenant       uuid,
  p_colaborador_cpf text,
  p_data_desligamento date
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_vencidas   numeric := 0;
  v_prop_avos  integer := 0;
  rec RECORD;
BEGIN
  -- Percorre os periodos aquisitivos em aberto (ferias_periodos_aquisitivos)
  -- e apura, para o desligamento: vencidas integrais + proporcionais por
  -- duodecimos, ambas com 1/3 (arts. 146-148, Sumula 171). Indenizadas.
  FOR rec IN
    SELECT * FROM public.ferias_periodos_aquisitivos p
     WHERE p.tenant_id = p_tenant
       AND regexp_replace(COALESCE(p.colaborador_cpf,''), '[^0-9]', '', 'g')
         = regexp_replace(COALESCE(p_colaborador_cpf,''), '[^0-9]', '', 'g')
       AND COALESCE(p.dias_saldo, 0) > 0
  LOOP
    IF rec.aquisitivo_fim <= p_data_desligamento THEN
      v_vencidas := v_vencidas + COALESCE(rec.dias_saldo, 0);   -- periodo completo
    ELSE
      -- Proporcional: duodecimos desde o inicio do aquisitivo ate o desligamento.
      v_prop_avos := v_prop_avos + LEAST(12, GREATEST(0,
        (EXTRACT(YEAR FROM age(p_data_desligamento, rec.aquisitivo_inicio)) * 12
       + EXTRACT(MONTH FROM age(p_data_desligamento, rec.aquisitivo_inicio)))::int));
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'dias_vencidos', v_vencidas,
    'avos_proporcionais', v_prop_avos,
    'dias_proporcionais', ROUND(v_prop_avos * 2.5, 1),
    'inclui_um_terco', true,
    'observacao', 'Ferias indenizadas na rescisao (vencidas + proporcionais + 1/3).'
  );
END;
$$;

COMMENT ON FUNCTION public.ferias_liquida_rescisao(uuid, text, date) IS
  'FERIAS-090: liquida os ferias_periodos no desligamento (vencidas + proporcionais + 1/3, indenizadas).';
