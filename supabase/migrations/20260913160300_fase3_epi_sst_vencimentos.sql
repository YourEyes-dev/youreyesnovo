-- ============================================================================
-- Fase 3 (motores) — EPI/SST: relógios de vencimento e travas.
--
-- EPI-011: rotina que vigia a validade do CA (vencido/a vencer → Plano de Ação).
-- EPI-022: saldo abaixo do mínimo abre reposição no Plano de Ação (sem duplicar).
-- EPI-050: entrega calcula a data prevista de troca (entrega + periodicidade).
-- EPI-052: desligamento gera checklist de devolução dos EPIs ativos.
-- SST-001: rotina que marca documento de SST vencido e alerta a renovação.
-- SST-011: entrega de EPI com CA vencido é recusada (NR-6).
-- SST-020: próximo exame periódico derivado da periodicidade do cargo.
--
-- (Fica para depois EPI-051 — kit de admissão por função de risco.)
-- ============================================================================

-- Helper: abre uma ação no Plano de Ação sem duplicar (por origem_id + origem_modulo).
CREATE OR REPLACE FUNCTION public.plano_acao_abrir(
  p_tenant uuid, p_modulo text, p_origem_id uuid, p_titulo text, p_descricao text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_tenant IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM public.plano_acoes
              WHERE tenant_id = p_tenant AND origem_modulo = p_modulo
                AND origem_id = p_origem_id AND COALESCE(arquivada,false) = false) THEN
    RETURN;
  END IF;
  INSERT INTO public.plano_acoes (tenant_id, codigo, titulo, descricao, origem_modulo, origem_id, arquivada)
  VALUES (p_tenant,
          upper(left(p_modulo,3)) || '-' || to_char(now(),'YYYYMMDDHH24MISS') || '-' || left(replace(p_origem_id::text,'-',''),6),
          p_titulo, p_descricao, p_modulo, p_origem_id, false);
END;
$$;

-- ── EPI-011: vigia a validade do CA (rotina diária) ─────────────────────────
CREATE OR REPLACE FUNCTION public.epi_ca_vigiar()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_n integer := 0; t RECORD;
BEGIN
  -- CA vencido ou a vencer em 30 dias abre ação de renovação/recompra.
  FOR t IN
    SELECT id, tenant_id, nome, ca_numero, ca_validade
      FROM public.epi_tipos
     WHERE ca_validade IS NOT NULL
       AND ca_validade <= (CURRENT_DATE + INTERVAL '30 days')
       AND COALESCE(is_active, true) = true
  LOOP
    PERFORM public.plano_acao_abrir(
      t.tenant_id, 'epi', t.id,
      CASE WHEN t.ca_validade < CURRENT_DATE
           THEN 'CA vencido: renovar/recomprar ' || COALESCE(t.nome,'EPI') || ' (CA ' || COALESCE(t.ca_numero,'?') || ')'
           ELSE 'CA a vencer: providenciar renovação de ' || COALESCE(t.nome,'EPI') || ' (CA ' || COALESCE(t.ca_numero,'?') || ')' END,
      'ca_validade em ' || to_char(t.ca_validade,'DD/MM/YYYY'));
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;

-- ── EPI-022: saldo abaixo do mínimo abre reposição no Plano de Ação ─────────
CREATE OR REPLACE FUNCTION public.epi_verificar_estoque_minimo()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_n integer := 0; t RECORD;
BEGIN
  -- Cada item abaixo do mínimo vira uma reposição em public.plano_acoes
  -- (o helper plano_acao_abrir cuida da não-duplicidade).
  FOR t IN
    SELECT et.id, et.tenant_id, et.nome, et.estoque_minimo,
           COALESCE(SUM(e.quantidade_estoque), 0) AS saldo
      FROM public.epi_tipos et
      LEFT JOIN public.epis e ON e.tipo_id = et.id
     WHERE et.estoque_minimo IS NOT NULL AND et.estoque_minimo > 0
     GROUP BY et.id, et.tenant_id, et.nome, et.estoque_minimo
    HAVING COALESCE(SUM(e.quantidade_estoque), 0) < et.estoque_minimo
  LOOP
    PERFORM public.plano_acao_abrir(
      t.tenant_id, 'epi', t.id,
      'Reposição de EPI: ' || COALESCE(t.nome,'item') || ' abaixo do estoque mínimo',
      'Saldo ' || t.saldo || ' < mínimo ' || t.estoque_minimo);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;

-- ── EPI-050: entrega calcula a data prevista de troca ───────────────────────
CREATE OR REPLACE FUNCTION public.epi_entrega_calcula_troca()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_periodicidade_troca_dias integer;
BEGIN
  IF NEW.data_devolucao_prevista IS NULL AND NEW.data_entrega IS NOT NULL THEN
    SELECT et.periodicidade_troca_dias INTO v_periodicidade_troca_dias
      FROM public.epis e JOIN public.epi_tipos et ON et.id = e.tipo_id
     WHERE e.id = NEW.epi_id;
    IF v_periodicidade_troca_dias IS NOT NULL AND v_periodicidade_troca_dias > 0 THEN
      NEW.data_devolucao_prevista := NEW.data_entrega + v_periodicidade_troca_dias;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_epi_entrega_calcula_troca ON public.epi_entregas;
CREATE TRIGGER trg_epi_entrega_calcula_troca
  BEFORE INSERT ON public.epi_entregas
  FOR EACH ROW EXECUTE FUNCTION public.epi_entrega_calcula_troca();

-- ── SST-011: entrega de EPI com CA vencido é recusada (NR-6) ────────────────
CREATE OR REPLACE FUNCTION public.epi_entrega_valida_ca_vigente()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_ca_validade date; v_nome text;
BEGIN
  SELECT et.ca_validade, et.nome INTO v_ca_validade, v_nome
    FROM public.epis e JOIN public.epi_tipos et ON et.id = e.tipo_id
   WHERE e.id = NEW.epi_id;
  IF v_ca_validade IS NOT NULL
     AND v_ca_validade < COALESCE(NEW.data_entrega, CURRENT_DATE) THEN
    RAISE EXCEPTION 'Entrega vedada: o CA do EPI "%" venceu em % — entregar EPI com CA vencido equivale a nao entregar (NR-6).',
      COALESCE(v_nome,'?'), to_char(v_ca_validade,'DD/MM/YYYY')
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_epi_entrega_ca_vigente ON public.epi_entregas;
CREATE TRIGGER trg_epi_entrega_ca_vigente
  BEFORE INSERT ON public.epi_entregas
  FOR EACH ROW EXECUTE FUNCTION public.epi_entrega_valida_ca_vigente();

-- ── EPI-052: desligamento gera checklist de devolução dos EPIs ativos ───────
CREATE OR REPLACE FUNCTION public.epi_checklist_devolucao_desligamento()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_ativos integer;
BEGIN
  IF NEW.status = 'desligado' AND (OLD.status IS DISTINCT FROM NEW.status) THEN
    SELECT count(*) INTO v_ativos
      FROM public.epi_entregas ee
     WHERE ee.tenant_id = NEW.tenant_id
       AND regexp_replace(COALESCE(ee.colaborador_cpf,''), '[^0-9]', '', 'g')
         = regexp_replace(COALESCE(NEW.cpf,''), '[^0-9]', '', 'g')
       AND COALESCE(ee.status::text,'') NOT IN ('devolvido', 'descartado');
    IF v_ativos > 0 THEN
      -- Cobra a devolução SEM travar a rescisão (a rescisão segue).
      PERFORM public.plano_acao_abrir(
        NEW.tenant_id, 'epi', NEW.id,
        'Devolução de EPI no desligamento de ' || COALESCE(NEW.nome_completo,'colaborador'),
        v_ativos || ' entrega(s) ativa(s) a conferir/devolver (sem reter verbas — CLT art. 462).');
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_epi_checklist_devolucao_desligamento ON public.admissoes;
CREATE TRIGGER trg_epi_checklist_devolucao_desligamento
  AFTER UPDATE OF status ON public.admissoes
  FOR EACH ROW EXECUTE FUNCTION public.epi_checklist_devolucao_desligamento();

-- ── SST-001: rotina que marca documento de SST vencido e alerta renovação ───
CREATE OR REPLACE FUNCTION public.sst_vigiar_documentos()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_n integer := 0; d RECORD;
BEGIN
  -- Marca vencido o que passou da data_vigencia.
  UPDATE public.sst_documentos
     SET status = 'vencido'
   WHERE data_vigencia IS NOT NULL
     AND data_vigencia < CURRENT_DATE
     AND COALESCE(status,'') NOT IN ('vencido', 'substituido', 'cancelado');
  GET DIAGNOSTICS v_n = ROW_COUNT;

  -- Janela de renovação (60/30 dias) abre ação no Plano de Ação.
  FOR d IN
    SELECT id, tenant_id, tipo, data_vigencia
      FROM public.sst_documentos
     WHERE data_vigencia IS NOT NULL
       AND data_vigencia BETWEEN CURRENT_DATE AND (CURRENT_DATE + INTERVAL '60 days')
       AND COALESCE(status,'') NOT IN ('substituido', 'cancelado')
  LOOP
    PERFORM public.plano_acao_abrir(
      d.tenant_id, 'sst', d.id,
      'Renovar documento de SST (' || COALESCE(d.tipo,'documento') || ') — vigência ' || to_char(d.data_vigencia,'DD/MM/YYYY'),
      'Janela de renovação (60/30 dias) do documento de SST.');
  END LOOP;
  RETURN v_n;
END;
$$;

-- ── SST-020: próximo exame periódico pela periodicidade do cargo ────────────
CREATE OR REPLACE FUNCTION public.sst_proximo_exame_periodico(p_cargo_id uuid, p_ultimo_aso date)
RETURNS date
LANGUAGE sql
STABLE
AS $$
  -- Próximo periódico = último ASO + periodicidade_exame_meses do cargo (NR-7).
  SELECT CASE WHEN c.periodicidade_exame_meses IS NULL OR p_ultimo_aso IS NULL THEN NULL
              ELSE (p_ultimo_aso + (c.periodicidade_exame_meses || ' months')::interval)::date END
    FROM public.cargos c
   WHERE c.id = p_cargo_id;
$$;
COMMENT ON FUNCTION public.sst_proximo_exame_periodico(uuid, date) IS
  'Proxima data do exame periodico = ultimo ASO + periodicidade_exame_meses do cargo (NR-7). SST-020.';

-- ── Agendamentos diários (pg_cron) ──────────────────────────────────────────
DO $cron$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule('epi-ca-vigiar-diario',       '0 6 * * *', $$SELECT public.epi_ca_vigiar()$$);
    PERFORM cron.schedule('epi-estoque-minimo-diario',  '5 6 * * *', $$SELECT public.epi_verificar_estoque_minimo()$$);
    PERFORM cron.schedule('sst-vigiar-documentos-diario','10 6 * * *', $$SELECT public.sst_vigiar_documentos()$$);
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Agendamento pg_cron nao aplicado: %', SQLERRM;
END $cron$;
