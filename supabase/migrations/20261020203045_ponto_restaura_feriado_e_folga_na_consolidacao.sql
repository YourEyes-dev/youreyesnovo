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
