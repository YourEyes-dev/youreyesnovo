-- CRITICO #1 (Ponto): liga o ADICIONAL NOTURNO ao calculo real (art. 73).
-- calcular_he_adicional_noturno_dia era orfa; a consolidacao a chama em dias
-- com trabalho efetivo e ela grava SO o adicional noturno. HE = a do saldo.
-- Idempotente (CREATE OR REPLACE). Nao altera dado.
SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.calcular_he_adicional_noturno_dia(p_colaborador_id uuid, p_data date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_diario RECORD;
  v_cct RECORD;
  v_jornada_diaria_min INTEGER := 480; -- 8h (fallback; a escala do vínculo tem prioridade)
  v_he50_pct NUMERIC := 50;
  v_he100_pct NUMERIC := 100;
  v_adn_pct NUMERIC := 20;
  v_noturno_inicio TIME := '22:00';
  v_noturno_fim TIME := '05:00';
  v_usa_hora_ficta BOOLEAN := true;
  v_he_limite_diario_min INTEGER := 120;
  v_he50 INTEGER := 0;
  v_he100 INTEGER := 0;
  v_adn_min INTEGER := 0;
  v_trab_min INTEGER := 0;
  v_dow INTEGER;
  v_empresa UUID;
  v_j_escala INTEGER;
  v_excesso INTEGER;
  v_domingo_dobra BOOLEAN := false;
BEGIN
  SELECT * INTO v_diario FROM public.ponto_diario
   WHERE colaborador_id = p_colaborador_id AND data = p_data
   LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_diario');
  END IF;

  v_empresa := v_diario.empresa_id;

  -- CCT vigente (se houver) prioriza acordo individual, depois ACT, depois CCT
  SELECT c.* INTO v_cct
    FROM public.ponto_cct_config c
   WHERE c.tenant_id = v_diario.tenant_id
     AND (c.vigencia_inicio IS NULL OR c.vigencia_inicio <= p_data)
     AND (c.vigencia_fim IS NULL OR c.vigencia_fim >= p_data)
   ORDER BY c.created_at DESC
   LIMIT 1;
  IF FOUND THEN
    v_jornada_diaria_min := COALESCE(v_cct.jornada_diaria_horas,8) * 60;
    v_he50_pct := COALESCE(v_cct.he_percentual_dia_util,50);
    v_he100_pct := COALESCE(v_cct.he_percentual_domingos,100);
    v_adn_pct := COALESCE(v_cct.adicional_noturno_percentual,20);
    v_noturno_inicio := COALESCE(v_cct.hora_noturna_inicio,'22:00'::time);
    v_noturno_fim := COALESCE(v_cct.hora_noturna_fim,'05:00'::time);
    v_usa_hora_ficta := COALESCE(v_cct.usa_hora_ficta,true);
    v_he_limite_diario_min := COALESCE(v_cct.he_limite_diario_min,120);
  END IF;

  -- (091) Jornada do dia pela ESCALA vigente do vínculo — tem prioridade sobre
  -- a CCT/8h fixas. Respeita o versionamento de parâmetros da onda 1 (a própria
  -- ponto_jornada_do_dia aplica o overlay). Sem escala com jornada para o dia,
  -- mantém-se o que a CCT/8h definiram acima.
  BEGIN
    SELECT j.jornada_min INTO v_j_escala
      FROM public.ponto_jornada_do_dia(v_diario.tenant_id, v_diario.colaborador_cpf,
                                       v_diario.colaborador_id::text, p_data) j;
    IF COALESCE(v_j_escala, 0) > 0 THEN
      v_jornada_diaria_min := v_j_escala;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_j_escala := NULL; -- qualquer falha na leitura da escala: mantém o fallback CCT/8h
  END;

  -- Total trabalhado em minutos (a partir das marcações entrada/saida)
  IF v_diario.entrada IS NOT NULL AND v_diario.saida IS NOT NULL THEN
    v_trab_min := EXTRACT(EPOCH FROM (v_diario.saida::time - v_diario.entrada::time))/60;
    IF v_diario.saida_almoco IS NOT NULL AND v_diario.retorno_almoco IS NOT NULL THEN
      v_trab_min := v_trab_min - EXTRACT(EPOCH FROM (v_diario.retorno_almoco::time - v_diario.saida_almoco::time))/60;
    END IF;
  END IF;
  IF v_trab_min < 0 THEN v_trab_min := 0; END IF;

  v_dow := EXTRACT(DOW FROM p_data); -- 0=domingo

  -- (130) Domingo trabalhado como descanso semanal, sem folga
  -- compensatória: Lei 605/1949 art. 9º + Súmula 146 do TST -> a jornada
  -- trabalhada é paga EM DOBRO por inteiro (não só o que excede a jornada). Só
  -- vale quando o domingo NÃO é dia de trabalho previsto na escala — a escala
  -- 6x1 e afins já carregam o repouso noutro dia e caem no cálculo normal. Sem
  -- escala atribuída, o domingo é o repouso padrão da semana e a dobra vale.
  v_domingo_dobra := (v_dow = 0 AND v_trab_min > 0 AND COALESCE(v_j_escala, 0) = 0);

  -- (092) Horas extras: TODO o tempo que excede a jornada é apurado. O limite
  -- de 2h do art. 59 é norma de conduta, não de cálculo — não se trunca a
  -- apuração; apura-se tudo e sinaliza-se o excesso ao RH.
  IF v_trab_min > v_jornada_diaria_min THEN
    v_excesso := v_trab_min - v_jornada_diaria_min;
  ELSE
    v_excesso := 0;
  END IF;

  IF v_domingo_dobra THEN
    -- Jornada inteira em dobro (o eventual excedente também é do domingo).
    v_he100 := v_trab_min;
    v_he50  := 0;
  ELSIF v_excesso > 0 THEN
    IF v_dow = 0 THEN
      v_he100 := v_excesso;   -- domingo previsto na escala: excedente a 100%
    ELSE
      v_he50 := v_excesso;    -- dia útil / sábado: excedente a 50%
    END IF;
  END IF;

  -- Sinalização do excesso ao limite do art. 59 (sem deixar de apurar).
  -- Idempotente: um alerta por colaborador/dia.
  IF v_excesso > v_he_limite_diario_min THEN
    INSERT INTO public.ponto_alertas
      (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
       tipo, severidade, titulo, descricao, data_referencia)
    SELECT v_diario.tenant_id, v_empresa, v_diario.colaborador_id::text,
           v_diario.colaborador_nome, v_diario.colaborador_cpf,
           'excesso_he_art59', 'alta',
           'Excesso ao limite de 2h extras (CLT art. 59)',
           format('Apuradas %s min de hora extra no dia, acima do limite de %s min do art. 59. '
               || 'O tempo foi apurado por inteiro (continua devido); regularizar o excesso.',
               v_excesso, v_he_limite_diario_min),
           p_data
    WHERE NOT EXISTS (
      SELECT 1 FROM public.ponto_alertas a
      WHERE a.tenant_id = v_diario.tenant_id
        AND a.colaborador_cpf = v_diario.colaborador_cpf
        AND a.data_referencia = p_data
        AND a.tipo = 'excesso_he_art59'
    );
  END IF;

  -- Adicional noturno: minutos trabalhados na janela 22h-05h
  -- Aproximação: se entrada < 05:00 OU saida > 22:00, calcula sobreposição da jornada bruta
  IF v_diario.entrada IS NOT NULL AND v_diario.saida IS NOT NULL THEN
    DECLARE
      v_e TIMESTAMP := (p_data::text || ' ' || v_diario.entrada::text)::timestamp;
      v_s TIMESTAMP := (p_data::text || ' ' || v_diario.saida::text)::timestamp;
      v_n_ini TIMESTAMP := (p_data::text || ' ' || v_noturno_inicio::text)::timestamp;
      v_n_fim TIMESTAMP := ((p_data + 1)::text || ' ' || v_noturno_fim::text)::timestamp;
      v_overlap_min INTEGER := 0;
      v_prorrog_min INTEGER := 0;
    BEGIN
      IF v_s < v_e THEN v_s := v_s + INTERVAL '1 day'; END IF;
      -- Parte estritamente noturna: minutos dentro da janela legal 22h-05h,
      -- convertidos pela hora ficta (52min30s) quando aplicavel.
      v_overlap_min := GREATEST(0,
        EXTRACT(EPOCH FROM (LEAST(v_s, v_n_fim) - GREATEST(v_e, v_n_ini)))/60
      )::INTEGER;
      v_adn_min := v_overlap_min;
      IF v_usa_hora_ficta AND v_adn_min > 0 THEN
        v_adn_min := ROUND(v_adn_min * 60.0 / 52.5);
      END IF;
      -- Súmula 60, II do TST: jornada cumprida integralmente no período noturno
      -- (entrada ate as 22h, cobrindo toda a janela) e prorrogada alem das 05h ->
      -- o adicional acompanha as horas prorrogadas. Criterio conservador: essas
      -- horas entram pelo tempo REAL (sem hora ficta, cuja aplicacao a prorrogacao
      -- e controvertida). A parte noturna acima ja levou a ficta.
      IF v_e <= v_n_ini AND v_s > v_n_fim THEN
        v_prorrog_min := GREATEST(0, EXTRACT(EPOCH FROM (v_s - v_n_fim))/60)::INTEGER;
        v_adn_min := v_adn_min + v_prorrog_min;
      END IF;
    END;
  END IF;

  -- HE canonica = a derivada do saldo do banco (espelho). Aqui grava-se APENAS o
  -- adicional noturno no dia; as colunas de HE do ponto_diario ficam a cargo do
  -- saldo (nao se escreve HE "por par" aqui para nao criar numero divergente).
  UPDATE public.ponto_diario
     SET adicional_noturno_minutos = v_adn_min,
         updated_at = now()
   WHERE id = v_diario.id;

  RETURN jsonb_build_object(
    'ok', true,
    'he50_min', v_he50,
    'he100_min', v_he100,
    'adicional_noturno_min', v_adn_min,
    'percentual_he50', v_he50_pct,
    'percentual_he100', v_he100_pct,
    'percentual_adn', v_adn_pct,
    'domingo_dobra', v_domingo_dobra
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.consolidar_ponto_diario_manual(p_tenant_id uuid, p_colaborador_cpf text, p_data date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_afast public.afastamentos;
  v_ferias public.ferias_solicitacoes;
  v_atest public.atestados;
  v_cid UUID; v_cnome TEXT; v_eid UUID; v_obs TEXT;
  v_regra TEXT; v_abona BOOLEAN;
  c RECORD;
BEGIN
  SELECT colaborador_id, colaborador_nome INTO v_cid, v_cnome
  FROM public.ponto_marcacoes
  WHERE tenant_id = p_tenant_id AND colaborador_cpf = p_colaborador_cpf
  ORDER BY created_at DESC LIMIT 1;
  IF v_cid IS NULL THEN
    SELECT colaborador_id, colaborador_nome INTO v_cid, v_cnome
    FROM public.ponto_ajustes
    WHERE tenant_id = p_tenant_id AND colaborador_cpf = p_colaborador_cpf
    ORDER BY created_at DESC LIMIT 1;
  END IF;

  IF v_cid IS NULL THEN
    SELECT a.id, a.nome_completo INTO v_cid, v_cnome
    FROM public.admissoes a
    WHERE a.tenant_id = p_tenant_id
      AND regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g')
          = regexp_replace(COALESCE(p_colaborador_cpf, ''), '[^0-9]', '', 'g')
      AND COALESCE(a.inativo, false) = false
    ORDER BY a.data_admissao DESC NULLS LAST
    LIMIT 1;
  END IF;

  SELECT f.* INTO v_ferias FROM public.ferias_solicitacoes f
  WHERE f.tenant_id = p_tenant_id AND f.colaborador_cpf = p_colaborador_cpf
    AND f.status IN ('aprovado','em_gozo','concluido')
    AND f.data_inicio <= p_data AND f.data_fim >= p_data
  ORDER BY f.data_inicio DESC LIMIT 1;
  IF v_ferias.id IS NOT NULL THEN
    v_cid := COALESCE(v_cid, v_ferias.colaborador_id);
    v_cnome := COALESCE(v_cnome, v_ferias.colaborador_nome);
    v_obs := 'Férias: ' || to_char(v_ferias.data_inicio,'DD/MM/YYYY') || ' a ' || to_char(v_ferias.data_fim,'DD/MM/YYYY');
    PERFORM public._ponto_grava_abono(p_tenant_id, v_cid, v_cnome, p_colaborador_cpf, p_data, v_obs);
    RETURN;
  END IF;

  SELECT a.* INTO v_atest FROM public.atestados a
  WHERE a.tenant_id = p_tenant_id AND a.colaborador_cpf = p_colaborador_cpf
    AND a.data_inicio_afastamento IS NOT NULL
    AND a.data_inicio_afastamento <= p_data
    AND COALESCE(a.data_fim_afastamento, a.data_inicio_afastamento) >= p_data
  ORDER BY a.data_inicio_afastamento DESC LIMIT 1;
  IF v_atest.id IS NOT NULL THEN
    IF COALESCE(v_atest.subtipo_assistencial::text, '') = 'comparecimento' THEN
      -- Declaracao de comparecimento: abona conforme o catalogo da empresa.
      v_regra := COALESCE((
        SELECT tipo_abono FROM public.ponto_justificativas
        WHERE tenant_id = p_tenant_id AND codigo = 'DECLARACAO_COMPARECIMENTO'
        ORDER BY empresa_id NULLS LAST LIMIT 1), 'configuravel');
      v_abona := (v_regra = 'sim')
              OR (v_regra = 'configuravel' AND COALESCE(v_atest.abona, false));
      IF v_abona THEN
        v_cid := COALESCE(v_cid, v_atest.colaborador_id);
        v_cnome := COALESCE(v_cnome, v_atest.colaborador_nome);
        v_obs := 'Declaração: ' || to_char(v_atest.data_inicio_afastamento,'DD/MM/YYYY')
          || CASE WHEN v_atest.data_fim_afastamento IS NOT NULL THEN ' a ' || to_char(v_atest.data_fim_afastamento,'DD/MM/YYYY') ELSE '' END;
        PERFORM public._ponto_grava_abono(p_tenant_id, v_cid, v_cnome, p_colaborador_cpf, p_data, v_obs);
        RETURN;
      END IF;
      -- Nao abonada: o documento fica registrado, mas o dia NAO e justificado.
      -- Se houver um atestado COMUM cobrindo o mesmo dia, ele abona.
      SELECT a.* INTO v_atest FROM public.atestados a
      WHERE a.tenant_id = p_tenant_id AND a.colaborador_cpf = p_colaborador_cpf
        AND a.data_inicio_afastamento IS NOT NULL
        AND a.data_inicio_afastamento <= p_data
        AND COALESCE(a.data_fim_afastamento, a.data_inicio_afastamento) >= p_data
        AND COALESCE(a.subtipo_assistencial::text, '') <> 'comparecimento'
      ORDER BY a.data_inicio_afastamento DESC LIMIT 1;
      IF v_atest.id IS NOT NULL THEN
        v_cid := COALESCE(v_cid, v_atest.colaborador_id);
        v_cnome := COALESCE(v_cnome, v_atest.colaborador_nome);
        v_obs := 'Atestado: ' || to_char(v_atest.data_inicio_afastamento,'DD/MM/YYYY')
          || CASE WHEN v_atest.data_fim_afastamento IS NOT NULL THEN ' a ' || to_char(v_atest.data_fim_afastamento,'DD/MM/YYYY') ELSE '' END;
        PERFORM public._ponto_grava_abono(p_tenant_id, v_cid, v_cnome, p_colaborador_cpf, p_data, v_obs);
        RETURN;
      END IF;
      -- senao, cai para o fluxo normal (dia conta como falta/incompleto).
    ELSE
      -- Atestado comum: abona sempre (comportamento inalterado).
      v_cid := COALESCE(v_cid, v_atest.colaborador_id);
      v_cnome := COALESCE(v_cnome, v_atest.colaborador_nome);
      v_obs := 'Atestado: ' || to_char(v_atest.data_inicio_afastamento,'DD/MM/YYYY')
        || CASE WHEN v_atest.data_fim_afastamento IS NOT NULL THEN ' a ' || to_char(v_atest.data_fim_afastamento,'DD/MM/YYYY') ELSE '' END;
      PERFORM public._ponto_grava_abono(p_tenant_id, v_cid, v_cnome, p_colaborador_cpf, p_data, v_obs);
      RETURN;
    END IF;
  END IF;

  v_afast := public.afastamento_vigente(p_tenant_id, p_colaborador_cpf, p_data);
  IF v_afast.id IS NOT NULL THEN
    v_cid := COALESCE(v_cid, v_afast.colaborador_id);
    v_cnome := COALESCE(v_cnome, v_afast.colaborador_nome);
    v_obs := 'Afastamento (' || COALESCE(replace(v_afast.motivo_principal::text,'_',' '),'registrado')
      || '): de ' || to_char(v_afast.data_inicio,'DD/MM/YYYY')
      || CASE WHEN v_afast.data_fim IS NOT NULL THEN ' a ' || to_char(v_afast.data_fim,'DD/MM/YYYY') ELSE ' — em aberto' END;
    PERFORM public._ponto_grava_abono(p_tenant_id, v_cid, v_cnome, p_colaborador_cpf, p_data, v_obs);
    RETURN;
  END IF;

  IF v_cid IS NULL THEN RETURN; END IF;
  v_eid := COALESCE(public.ponto_empresa_do_colaborador(v_cid),
                    public.ponto_empresa_do_cpf(p_tenant_id, p_colaborador_cpf));

  c := public._ponto_calc_dia(p_tenant_id, p_colaborador_cpf, p_data, v_cid);

  INSERT INTO public.ponto_diario (
    tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, data,
    entrada, saida_almoco, retorno_almoco, saida, horas_trabalhadas, status, observacao
  ) VALUES (
    p_tenant_id, v_eid, v_cid, v_cnome, p_colaborador_cpf, p_data,
    c.o_pent, c.o_salm, c.o_ralm, c.o_usai, c.o_horas, c.o_status, c.o_obs
  )
  ON CONFLICT (tenant_id, colaborador_cpf, data, COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid))
  DO UPDATE SET
    empresa_id = COALESCE(EXCLUDED.empresa_id, public.ponto_diario.empresa_id),
    colaborador_nome = EXCLUDED.colaborador_nome,
    entrada = EXCLUDED.entrada, saida_almoco = EXCLUDED.saida_almoco,
    retorno_almoco = EXCLUDED.retorno_almoco, saida = EXCLUDED.saida,
    horas_trabalhadas = EXCLUDED.horas_trabalhadas,
    status = CASE WHEN public.ponto_diario.status = 'justificado' THEN 'justificado' ELSE EXCLUDED.status END,
    observacao = CASE WHEN public.ponto_diario.status = 'justificado'
                        AND public.ponto_diario.observacao LIKE 'Abonado por afastamento%'
                      THEN public.ponto_diario.observacao ELSE EXCLUDED.observacao END,
    updated_at = now();

  -- CRITICO #1: popula o adicional noturno do dia (art. 73) — SO em dias com
  -- trabalho efetivo. Feriado/abono/falta nao tem adicional, e pular evita
  -- re-disparar gatilhos de reconsolidacao em dia neutro (PONTO-402).
  IF COALESCE(c.o_horas, interval '0') > interval '0' THEN
    BEGIN
      PERFORM public.calcular_he_adicional_noturno_dia(v_cid, p_data);
    EXCEPTION WHEN OTHERS THEN NULL; -- nunca derrubar a consolidacao
    END;
  END IF;
END;
$function$;

DO $val$
DECLARE v_t uuid := public.qa_sandbox_tenant_id(); v_cpf text := public.qa_cpf(7799);
        v_d date := DATE '2026-09-15'; v_adn int; v_trab interval;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM public.qa_ponto_admissao('QA Noturno Fix', 7799);
  PERFORM public.qa_ponto_marca(v_cpf,'QA Noturno Fix', v_d, TIME '22:00','entrada');
  PERFORM public.qa_ponto_marca(v_cpf,'QA Noturno Fix', v_d, TIME '23:30','saida');
  PERFORM public.consolidar_ponto_diario_manual(v_t, v_cpf, v_d);
  SELECT adicional_noturno_minutos, horas_trabalhadas INTO v_adn, v_trab
    FROM public.ponto_diario WHERE tenant_id=v_t AND colaborador_cpf=v_cpf AND data=v_d LIMIT 1;
  RAISE NOTICE 'FIX-NOTURNO (dia trabalhado): adicional_noturno=% (esperado >0) trabalhadas=%', COALESCE(v_adn::text,'NULL'), v_trab;
  RAISE EXCEPTION 'ROLLBACK_ME';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM <> 'ROLLBACK_ME' THEN RAISE NOTICE 'FIX-NOTURNO ERRO: %', SQLERRM; END IF;
END $val$;
