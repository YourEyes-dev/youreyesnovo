-- ============================================================================
-- CRITICO #1 — Parte A: liga o ADICIONAL NOTURNO (art. 73) por TRIGGER BEFORE
-- em ponto_diario (padrao do trg_ponto_diario_supressao_intervalo), SEM tocar na
-- consolidar_ponto_diario_manual (que e remendada por string) nem na funcao orfa.
-- Nucleo PURO extraido do bloco noturno vigente (nao "corrige" nada; reproduz).
-- NAO altera dado. Idempotente.
-- ============================================================================
SET lock_timeout = '10s';

-- Nucleo PURO (minutos de adicional noturno de um dia, a partir dos horarios)
CREATE OR REPLACE FUNCTION public.ponto_adicional_noturno_minutos(
  p_data date, p_entrada time, p_saida time,
  p_noturno_inicio time DEFAULT '22:00',
  p_noturno_fim    time DEFAULT '05:00',
  p_usa_hora_ficta boolean DEFAULT true
) RETURNS integer
LANGUAGE plpgsql IMMUTABLE AS $fn$
DECLARE
  v_e timestamp; v_s timestamp; v_n_ini timestamp; v_n_fim timestamp;
  v_overlap_min int := 0; v_prorrog_min int := 0; v_adn int := 0;
BEGIN
  IF p_entrada IS NULL OR p_saida IS NULL THEN RETURN 0; END IF;
  v_e     := (p_data::text || ' ' || p_entrada::text)::timestamp;
  v_s     := (p_data::text || ' ' || p_saida::text)::timestamp;
  v_n_ini := (p_data::text || ' ' || p_noturno_inicio::text)::timestamp;
  v_n_fim := ((p_data + 1)::text || ' ' || p_noturno_fim::text)::timestamp;
  IF v_s < v_e THEN v_s := v_s + INTERVAL '1 day'; END IF;
  v_overlap_min := GREATEST(0, EXTRACT(EPOCH FROM (LEAST(v_s,v_n_fim) - GREATEST(v_e,v_n_ini)))/60)::int;
  v_adn := v_overlap_min;
  IF p_usa_hora_ficta AND v_adn > 0 THEN v_adn := ROUND(v_adn * 60.0 / 52.5); END IF;
  IF v_e <= v_n_ini AND v_s > v_n_fim THEN
    v_prorrog_min := GREATEST(0, EXTRACT(EPOCH FROM (v_s - v_n_fim))/60)::int;
    v_adn := v_adn + v_prorrog_min;
  END IF;
  RETURN v_adn;
END; $fn$;

-- Trigger BEFORE: so seta NEW.adicional_noturno_minutos (sem UPDATE, sem recursao)
CREATE OR REPLACE FUNCTION public.ponto_diario_adicional_noturno()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE v_ini time := '22:00'; v_fim time := '05:00'; v_ficta boolean := true; v_cct RECORD;
BEGIN
  SELECT c.hora_noturna_inicio, c.hora_noturna_fim, c.usa_hora_ficta INTO v_cct
  FROM public.ponto_cct_config c
  WHERE c.tenant_id = NEW.tenant_id
    AND (c.vigencia_inicio IS NULL OR c.vigencia_inicio <= NEW.data)
    AND (c.vigencia_fim    IS NULL OR c.vigencia_fim    >= NEW.data)
  ORDER BY c.created_at DESC LIMIT 1;
  IF FOUND THEN
    v_ini   := COALESCE(v_cct.hora_noturna_inicio, v_ini);
    v_fim   := COALESCE(v_cct.hora_noturna_fim,    v_fim);
    v_ficta := COALESCE(v_cct.usa_hora_ficta,      v_ficta);
  END IF;
  NEW.adicional_noturno_minutos :=
    public.ponto_adicional_noturno_minutos(NEW.data, NEW.entrada, NEW.saida, v_ini, v_fim, v_ficta);
  RETURN NEW;
END; $fn$;

DROP TRIGGER IF EXISTS trg_ponto_diario_adicional_noturno ON public.ponto_diario;
CREATE TRIGGER trg_ponto_diario_adicional_noturno
  BEFORE INSERT OR UPDATE ON public.ponto_diario
  FOR EACH ROW EXECUTE FUNCTION public.ponto_diario_adicional_noturno();

-- VALIDACAO (rollback por bloco): noturno pelo pipeline + paridade com a funcao orfa + diurno=0
DO $val$
DECLARE
  v_t uuid := public.qa_sandbox_tenant_id();
  v_cpf text := public.qa_cpf(7801); v_cid uuid;
  v_dn date := DATE '2026-09-15';  -- dia noturno
  v_dd date := DATE '2026-09-16';  -- dia diurno
  v_adn_trigger int; v_adn_orfa int; v_adn_diurno int;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM public.qa_ponto_admissao('QA Not A', 7801);
  SELECT a.id INTO v_cid FROM public.admissoes a WHERE a.tenant_id=v_t AND a.cpf=v_cpf LIMIT 1;
  -- noturno 22:00-23:30 (consolidacao dispara pelo AFTER INSERT das marcacoes)
  PERFORM public.qa_ponto_marca(v_cpf,'QA Not A', v_dn, TIME '22:00','entrada');
  PERFORM public.qa_ponto_marca(v_cpf,'QA Not A', v_dn, TIME '23:30','saida');
  PERFORM public.consolidar_ponto_diario_manual(v_t, v_cpf, v_dn);
  SELECT adicional_noturno_minutos INTO v_adn_trigger
    FROM public.ponto_diario WHERE tenant_id=v_t AND colaborador_cpf=v_cpf AND data=v_dn LIMIT 1;
  -- paridade: o que a funcao orfa daria pro mesmo dia (le o jsonb)
  BEGIN v_adn_orfa := (public.calcular_he_adicional_noturno_dia(v_cid, v_dn)->>'adicional_noturno_min')::int;
  EXCEPTION WHEN OTHERS THEN v_adn_orfa := -1; END;
  -- diurno 08:00-12:00 13:00-17:00
  PERFORM public.qa_ponto_marca(v_cpf,'QA Not A', v_dd, TIME '08:00','entrada');
  PERFORM public.qa_ponto_marca(v_cpf,'QA Not A', v_dd, TIME '12:00','saida');
  PERFORM public.qa_ponto_marca(v_cpf,'QA Not A', v_dd, TIME '13:00','entrada');
  PERFORM public.qa_ponto_marca(v_cpf,'QA Not A', v_dd, TIME '17:00','saida');
  PERFORM public.consolidar_ponto_diario_manual(v_t, v_cpf, v_dd);
  SELECT adicional_noturno_minutos INTO v_adn_diurno
    FROM public.ponto_diario WHERE tenant_id=v_t AND colaborador_cpf=v_cpf AND data=v_dd LIMIT 1;

  RAISE NOTICE 'NOTURNO-A: trigger=% | funcao_orfa=% (devem bater) | diurno=% (esperado 0)',
               COALESCE(v_adn_trigger::text,'NULL'), COALESCE(v_adn_orfa::text,'NULL'), COALESCE(v_adn_diurno::text,'NULL');
  RAISE EXCEPTION 'ROLLBACK_ME';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM <> 'ROLLBACK_ME' THEN RAISE NOTICE 'NOTURNO-A ERRO: %', SQLERRM; END IF;
END $val$;
