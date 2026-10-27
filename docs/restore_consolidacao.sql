-- RESTAURA a consolidar_ponto_diario_manual correta na homologacao
-- (base 162245 limpa + reinjecao de feriado/folga da 203045). Remove o
-- PERFORM noturno e o bug de feriado que meus testes deixaram. Idempotente.
SET lock_timeout = '10s';
-- base limpa:
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
END;
$function$;

-- reinjecao feriado+folga (203045 integral):
-- =====================================================================
-- CORRECAO (regressao): restaura na consolidacao os dois blocos perdidos
-- quando consolidar_ponto_diario_manual foi reconstruida pela Fatia 2a da
-- Declaracao de comparecimento (20261020162245), a partir de uma base
-- anterior as injecoes de 20260901180000 (feriado neutro) e 20260901200000
-- (folga compensatoria).
--
-- Efeito do bug: um feriado em dia util da escala, SEM marcacao, voltava a
-- ser consolidado como status='falta' (tipo_dia NULL) -> contava como falta,
-- descontava na folha e derrubava o DSR (Lei 605/1949). Idem a folga
-- compensatoria registrada, que podia ser recalculada como falta.
--
-- Esta correcao reinjeta os dois blocos ANTES de 'c := public._ponto_calc_dia(',
-- de forma IDEMPOTENTE (so injeta se ainda nao estiverem presentes). So mexe
-- em FUNCOES (nao cria tabela): nao aciona o auto-RLS do editor.
-- =====================================================================

SET lock_timeout = '10s';

-- Garante o gravador do feriado neutro (idempotente; ja existe nos ambientes).
CREATE OR REPLACE FUNCTION public.ponto_grava_feriado_neutro(
  p_tenant_id uuid, p_empresa_id uuid, p_colaborador_id uuid,
  p_colaborador_nome text, p_colaborador_cpf text, p_data date, p_nome_feriado text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_id uuid;
BEGIN
  SELECT d.id INTO v_id
  FROM public.ponto_diario d
  WHERE d.tenant_id = p_tenant_id
    AND d.colaborador_cpf = p_colaborador_cpf
    AND d.data = p_data
    AND (d.empresa_id IS NOT DISTINCT FROM p_empresa_id OR d.empresa_id IS NULL)
  ORDER BY d.empresa_id NULLS LAST
  LIMIT 1;

  IF v_id IS NOT NULL THEN
    UPDATE public.ponto_diario
       SET empresa_id        = COALESCE(empresa_id, p_empresa_id),
           tipo_dia          = 'feriado',
           feriado_nome      = p_nome_feriado,
           status            = 'justificado',
           horas_trabalhadas = make_interval(mins => 0),
           horas_faltantes   = make_interval(mins => 0),
           atraso_minutos    = 0,
           observacao        = 'Feriado: ' || p_nome_feriado,
           updated_at        = now()
     WHERE id = v_id;
  ELSE
    INSERT INTO public.ponto_diario
      (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, data,
       entrada, saida_almoco, retorno_almoco, saida,
       horas_trabalhadas, horas_faltantes, status, tipo_dia, feriado_nome, observacao)
    VALUES
      (p_tenant_id, p_empresa_id, p_colaborador_id, p_colaborador_nome, p_colaborador_cpf, p_data,
       NULL, NULL, NULL, NULL,
       make_interval(mins => 0), make_interval(mins => 0), 'justificado',
       'feriado', p_nome_feriado, 'Feriado: ' || p_nome_feriado);
  END IF;
END $function$;

-- (402) Reinjeta o bloco do feriado sem marcacao = dia neutro.
DO $fixferiado$
DECLARE v_src text; v_novo text; v_marca text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'consolidar_ponto_diario_manual';

  IF v_src IS NULL THEN
    RAISE NOTICE '(402) consolidacao nao existe nesta base — pulado.';
    RETURN;
  END IF;

  IF v_src ILIKE '%ponto_grava_feriado_neutro%' THEN
    RAISE NOTICE '(402) ja aplicado — nada a fazer.';
    RETURN;
  END IF;

  v_marca := 'c := public._ponto_calc_dia(';
  IF position(v_marca IN v_src) = 0 THEN
    RAISE NOTICE '(402) NAO aplicado: a ancora do calculo do dia mudou. Revisar a mao.';
    RETURN;
  END IF;

  v_novo := replace(v_src, v_marca,
    '-- Feriado sem marcacao e dia neutro, nunca falta (Lei 605/1949, art. 1).'
 || '  -- Feriado TRABALHADO segue pelo calculo: e la que a dobra e a folga'  || chr(10)
 || '  -- compensatoria sao decididas (PONTO-320/321).'                       || chr(10)
 || '  IF NOT EXISTS (SELECT 1 FROM public.ponto_marcacoes m'                 || chr(10)
 || '                  WHERE m.tenant_id = p_tenant_id'                       || chr(10)
 || '                    AND m.colaborador_cpf = p_colaborador_cpf'           || chr(10)
 || '                    AND m.data_marcacao = p_data) THEN'                  || chr(10)
 || '    DECLARE v_feriado text;'                                             || chr(10)
 || '    BEGIN'                                                               || chr(10)
 || '      v_feriado := public.feriado_do_dia(p_tenant_id, v_cid, p_data);'   || chr(10)
 || '      IF v_feriado IS NOT NULL THEN'                                     || chr(10)
 || '        PERFORM public.ponto_grava_feriado_neutro(p_tenant_id, v_eid, v_cid,' || chr(10)
 || '                  v_cnome, p_colaborador_cpf, p_data, v_feriado);'       || chr(10)
 || '        RETURN;'                                                         || chr(10)
 || '      END IF;'                                                           || chr(10)
 || '    EXCEPTION WHEN OTHERS THEN'                                          || chr(10)
 || '      NULL;  -- cadastro de feriados indisponivel nao pode travar o dia' || chr(10)
 || '    END;'                                                                || chr(10)
 || '  END IF;'                                                               || chr(10) || chr(10)
 || '  ' || v_marca);

  EXECUTE v_novo;
  RAISE NOTICE '(402) consolidacao volta a tratar feriado sem marcacao como dia neutro.';
END $fixferiado$;

-- (421) Reinjeta o bloco que respeita a folga compensatoria registrada.
DO $fixfolga$
DECLARE v_src text; v_novo text; v_marca text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'consolidar_ponto_diario_manual';

  IF v_src IS NULL THEN
    RAISE NOTICE '(421) consolidacao nao existe nesta base — pulado.';
    RETURN;
  END IF;

  IF v_src ILIKE '%folga_compensatoria%' THEN
    RAISE NOTICE '(421) consolidacao ja respeita a folga — nada a fazer.';
    RETURN;
  END IF;

  v_marca := 'c := public._ponto_calc_dia(';
  IF position(v_marca IN v_src) = 0 THEN
    RAISE NOTICE '(421) NAO aplicado: a ancora do calculo do dia mudou. Revisar a mao.';
    RETURN;
  END IF;

  v_novo := replace(v_src, v_marca,
    '-- Folga compensatoria registrada nao volta a ser calculada como falta:'      || chr(10)
 || '  -- ela ja debitou o banco (PONTO-421).'                                     || chr(10)
 || '  IF EXISTS (SELECT 1 FROM public.ponto_diario d0'                            || chr(10)
 || '              WHERE d0.tenant_id = p_tenant_id'                               || chr(10)
 || '                AND d0.colaborador_cpf = p_colaborador_cpf'                   || chr(10)
 || '                AND d0.data = p_data'                                         || chr(10)
 || '                AND d0.tipo_dia = ''folga_compensatoria'') THEN'              || chr(10)
 || '    RETURN;'                                                                  || chr(10)
 || '  END IF;'                                                                    || chr(10) || chr(10)
 || '  ' || v_marca);

  EXECUTE v_novo;
  RAISE NOTICE '(421) consolidacao volta a respeitar a folga compensatoria.';
END $fixfolga$;

-- conferencia
DO $c$ DECLARE v text; BEGIN
  v := pg_get_functiondef('public.consolidar_ponto_diario_manual(uuid,text,date)'::regprocedure);
  RAISE NOTICE 'RESTORE-CONSOL: feriado=% folga=% perform_noturno_removido=%', (position('ponto_grava_feriado_neutro' IN v)>0), (position('folga_compensatoria' IN v)>0), (position('calcular_he_adicional_noturno_dia' IN v)=0);
END $c$;
