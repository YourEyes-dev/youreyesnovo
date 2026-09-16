-- ============================================================================
-- ENTREGA — PONTO 421 (folga compensatoria) e 410 (intervalo: batida x declaracao)
--
-- ONDE COLAR: SQL Editor da HOMOLOGACAO (e da PRODUCAO, quando aprovado).
-- Depois do script_ponto_correcoes_402_430_431.sql.
--
-- (421) E CORRECAO DE COMPORTAMENTO
--   Nao havia como registrar uma folga compensatoria: o dia sem marcacao
--   virava FALTA e o debito entrava no extrato junto com "atrasos, faltas
--   e saidas antecipadas". A empresa dava a folga E mantinha o saldo
--   positivo (que seria pago de novo no vencimento), enquanto quem estava
--   compensando aparecia com falta — com risco de desconto e de perda do
--   DSR da semana.
--
-- (410) NAO ERA DEFEITO — ERA A SONDA OLHANDO O LUGAR ERRADO
--   A regra da Sumula 338, III (a marcacao real prevalece sobre a
--   pre-assinalacao) JA ESTAVA implementada e correta: o gatilho
--   ponto_diario_pre_assinalacao marca a origem como "marcado" sempre que
--   ha almoco batido. A sonda procurava a logica dentro do calculo do dia
--   — detalhe de implementacao — e reprovava um sistema que atende a
--   regra. Aqui ela passa a MEDIR o comportamento.
--
-- O QUE MUDA DE COMPORTAMENTO
--   - Passa a existir a rotina ponto_registrar_folga_compensatoria. Nada
--     e registrado por ela automaticamente: e a tela/DP que a chama.
--   - Dias ja fechados nao sao reescritos por este arquivo.
--   - A consolidacao passa a RESPEITAR um dia marcado como folga
--     compensatoria, em vez de recalcula-lo como falta.
--
-- GARANTIAS
--   - Idempotente: rodar duas vezes nao duplica nem quebra. Registrar a
--     MESMA folga duas vezes tambem nao debita o banco duas vezes.
--   - Nao altera dado existente: so cria a rotina e ajusta as sondas.
--   - Nenhuma escrita nova depende do formato do indice da apuracao
--     diaria (chave com ou sem empresa).
-- Roda inteiro em UMA transacao.
-- ============================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- (421) Registro da folga compensatória
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_registrar_folga_compensatoria(
  p_tenant_id uuid, p_colaborador_cpf text, p_data date, p_observacao text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_cpf     text := regexp_replace(coalesce(p_colaborador_cpf, ''), '[^0-9]', '', 'g');
  v_id      uuid; v_cid uuid; v_cnome text; v_eid uuid;
  v_min     int;
  v_comp    text := to_char(p_data, 'YYYY-MM');
  v_banco   uuid;
  v_obs     text;
BEGIN
  IF v_cpf = '' OR p_data IS NULL THEN
    RETURN jsonb_build_object('success', false, 'motivo', 'CPF e data sao obrigatorios');
  END IF;

  -- Quem é o colaborador (dia já existente, senão cadastro).
  SELECT d.id, d.colaborador_id, d.colaborador_nome, d.empresa_id
    INTO v_id, v_cid, v_cnome, v_eid
  FROM public.ponto_diario d
  WHERE d.tenant_id = p_tenant_id
    AND regexp_replace(d.colaborador_cpf, '[^0-9]', '', 'g') = v_cpf
    AND d.data = p_data
  ORDER BY d.empresa_id NULLS LAST
  LIMIT 1;

  IF v_cid IS NULL THEN
    SELECT a.id, a.nome_completo, a.empresa_id INTO v_cid, v_cnome, v_eid
    FROM public.admissoes a
    WHERE a.tenant_id = p_tenant_id
      AND regexp_replace(coalesce(a.cpf, ''), '[^0-9]', '', 'g') = v_cpf
      AND coalesce(a.inativo, false) = false
    ORDER BY a.data_admissao DESC NULLS LAST
    LIMIT 1;
  END IF;

  IF v_cid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'motivo', 'colaborador nao encontrado');
  END IF;

  -- Quantos minutos a folga consome: a jornada prevista para o dia.
  BEGIN
    SELECT j.minutos INTO v_min
    FROM public.ponto_jornada_do_dia(p_tenant_id, v_cpf, v_cid::text, p_data) j;
  EXCEPTION WHEN OTHERS THEN
    v_min := NULL;
  END;
  v_min := COALESCE(NULLIF(v_min, 0), 480);

  v_obs := COALESCE(p_observacao, 'Folga compensatoria (banco de horas)');

  -- (1) O dia: neutro, nunca falta.
  IF v_id IS NOT NULL THEN
    UPDATE public.ponto_diario
       SET tipo_dia          = 'folga_compensatoria',
           status            = 'justificado',
           horas_trabalhadas = make_interval(mins => 0),
           horas_faltantes   = make_interval(mins => 0),
           atraso_minutos    = 0,
           observacao        = v_obs,
           updated_at        = now()
     WHERE id = v_id;
  ELSE
    INSERT INTO public.ponto_diario
      (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, data,
       horas_trabalhadas, horas_faltantes, status, tipo_dia, observacao)
    VALUES
      (p_tenant_id, v_eid, v_cid, v_cnome, v_cpf, p_data,
       make_interval(mins => 0), make_interval(mins => 0), 'justificado',
       'folga_compensatoria', v_obs);
  END IF;

  -- (2) O banco: débito do tipo 'compensacao', separado das ausências.
  SELECT b.id INTO v_banco
  FROM public.ponto_banco_horas b
  WHERE b.tenant_id = p_tenant_id
    AND regexp_replace(b.colaborador_cpf, '[^0-9]', '', 'g') = v_cpf
    AND b.competencia = v_comp
  ORDER BY b.created_at DESC NULLS LAST
  LIMIT 1;

  IF v_banco IS NULL THEN
    INSERT INTO public.ponto_banco_horas
      (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, tipo,
       competencia, saldo_anterior_minutos, creditos_minutos, debitos_minutos,
       compensados_minutos, saldo_atual_minutos, convertido_extras)
    VALUES (p_tenant_id, v_eid, v_cid, v_cnome, v_cpf, 'mensal',
            v_comp, 0, 0, 0, 0, 0, false)
    RETURNING id INTO v_banco;
  END IF;

  -- Idempotente: a mesma folga nao debita duas vezes.
  IF EXISTS (
    SELECT 1 FROM public.ponto_banco_horas_movimentacoes m
    WHERE m.banco_horas_id = v_banco AND m.tipo = 'compensacao'
      AND m.data_referencia = p_data
  ) THEN
    RETURN jsonb_build_object('success', true, 'ja_registrada', true,
                              'minutos', v_min, 'competencia', v_comp);
  END IF;

  INSERT INTO public.ponto_banco_horas_movimentacoes
    (tenant_id, banco_horas_id, colaborador_cpf, data_referencia, tipo, minutos, descricao, origem)
  VALUES (p_tenant_id, v_banco, v_cpf, p_data, 'compensacao', v_min,
          v_obs || ' — ' || to_char(p_data, 'DD/MM/YYYY'), 'folga_compensatoria');

  UPDATE public.ponto_banco_horas
     SET compensados_minutos = COALESCE(compensados_minutos, 0) + v_min,
         saldo_atual_minutos = COALESCE(saldo_atual_minutos, 0) - v_min,
         updated_at = now()
   WHERE id = v_banco;

  RETURN jsonb_build_object('success', true, 'minutos', v_min,
                            'competencia', v_comp, 'banco_horas_id', v_banco);
END $function$;

COMMENT ON FUNCTION public.ponto_registrar_folga_compensatoria(uuid, text, date, text) IS
  'Registra a folga compensatoria: o dia vira neutro (sem falta) e o banco recebe movimentacao do tipo compensacao, separada dos debitos por ausencia. Idempotente. CLT art. 59, 2. PONTO-421.';

-- A consolidação respeita o dia de folga em vez de reescrevê-lo.
DO $consolida$
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
  RAISE NOTICE '(421) consolidacao passa a respeitar a folga compensatoria.';
END $consolida$;

-- ---------------------------------------------------------------------
-- SONDAS
-- ---------------------------------------------------------------------

-- (421) comportamental: registra a folga e confere dia + extrato.
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_421()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_cpf text; v_dia date; v_res jsonb;
        v_status text; v_tipo text; v_falta interval; v_mov int; v_comp int;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_dia := public.qa_dia_util_passado();
  v_cpf := public.qa_cpf(42101);

  IF NOT EXISTS (SELECT 1 FROM public.admissoes a
                  WHERE a.tenant_id = v_t AND a.cpf = v_cpf
                    AND COALESCE(a.inativo, false) = false) THEN
    PERFORM public.qa_ponto_admissao('QA Folga Compensatoria', 42101);
  END IF;

  r.passo_ordem := 1;
  r.passo_acao := 'Registrar uma folga compensatoria e conferir o dia e o extrato do banco';
  r.esperado := 'Dia sem falta + debito do tipo compensacao no banco (CLT art. 59, 2)';

  IF to_regprocedure('public.ponto_registrar_folga_compensatoria(uuid,text,date,text)') IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nao ha como registrar uma folga compensatoria. Compensar e o '
             || 'proposito do banco de horas: sem esse registro, o dia de folga vira FALTA '
             || '(com risco de desconto e de perda do DSR) e o saldo positivo permanece — '
             || 'a empresa da a folga E paga de novo no vencimento. Correcao: rotina que '
             || 'grave o dia como folga (neutro) e lance no banco a movimentacao do tipo '
             || 'compensacao, separada dos debitos por ausencia.';
    RETURN r;
  END IF;

  v_res := public.ponto_registrar_folga_compensatoria(v_t, v_cpf, v_dia);

  SELECT d.status, d.tipo_dia, coalesce(d.horas_faltantes, interval '0')
    INTO v_status, v_tipo, v_falta
  FROM public.ponto_diario d
  WHERE d.tenant_id = v_t AND d.colaborador_cpf = v_cpf AND d.data = v_dia;

  SELECT count(*), coalesce(sum(m.minutos), 0) INTO v_mov, v_comp
  FROM public.ponto_banco_horas_movimentacoes m
  WHERE m.tenant_id = v_t AND m.colaborador_cpf = v_cpf
    AND m.data_referencia = v_dia AND m.tipo = 'compensacao';

  IF coalesce(v_res ->> 'success', 'false') <> 'true' THEN
    r.situacao := 'falhou';
    r.obtido := format('A folga nao pode ser registrada: %s', coalesce(v_res ->> 'motivo', '(sem motivo)'));
  ELSIF v_status = 'falta' OR v_falta > interval '0' THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: mesmo registrada, a folga ficou como falta (status=%s, '
             || 'faltantes=%s) — desconto e perda de DSR para quem estava compensando.',
             v_status, v_falta);
  ELSIF v_mov = 0 THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o dia nao virou falta, mas o banco NAO foi debitado — a empresa da '
             || 'a folga e mantem o saldo positivo, que sera pago de novo no vencimento '
             || '(PONTO-171).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Folga registrada: dia neutro (tipo_dia=%s, status=%s) e debito de %s '
             || 'minuto(s) do tipo compensacao no extrato do banco.',
             coalesce(v_tipo, '—'), v_status, v_comp);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- (410) comportamental: a batida real prevalece sobre a declaracao.
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_410()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_cpf text; v_com date; v_sem date;
        v_o_com text; v_o_sem text; v_pre_com int;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_cpf := public.qa_cpf(41001);
  v_com := public.qa_dia_util_passado();
  v_sem := v_com - 1;

  r.passo_ordem := 1;
  r.passo_acao := 'Lancar um dia com almoco BATIDO e outro sem, e conferir a origem do intervalo';
  r.esperado := 'Com batida: intervalo marcado (Sumula 338, III). Sem batida: vale o declarado.';

  IF public.qa_col_existe('ponto_diario', 'intervalo_origem') IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nao ha registro da ORIGEM do intervalo neste ambiente — sem ele nao '
             || 'e possivel provar, dia a dia, se o intervalo foi batido ou apenas declarado. '
             || 'Pela Sumula 338, III, do TST a presuncao cede diante do fato: intervalo '
             || 'batido menor que o declarado precisa aparecer como suprimido (PONTO-060), '
             || 'nao como gozado.';
    RETURN r;
  END IF;

  PERFORM public.qa_ponto_dia_horarios(v_cpf, 'QA Intervalo Batido', v_com,
                                       TIME '08:00', TIME '17:00', TIME '12:00', TIME '13:00');
  PERFORM public.qa_ponto_dia_horarios(v_cpf, 'QA Intervalo Batido', v_sem,
                                       TIME '08:00', TIME '17:00');

  SELECT d.intervalo_origem, d.intervalo_pre_assinalado_minutos INTO v_o_com, v_pre_com
  FROM public.ponto_diario d
  WHERE d.tenant_id = v_t AND d.colaborador_cpf = v_cpf AND d.data = v_com;

  SELECT d.intervalo_origem INTO v_o_sem
  FROM public.ponto_diario d
  WHERE d.tenant_id = v_t AND d.colaborador_cpf = v_cpf AND d.data = v_sem;

  IF coalesce(v_o_com, '') <> 'marcado' THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o dia com almoco BATIDO ficou com origem de intervalo "%s" — '
             || 'o declarado esta se sobrepondo ao que foi efetivamente marcado. Pela Sumula '
             || '338, III, do TST a presuncao cede diante do fato: intervalo batido menor que '
             || 'o declarado tem de aparecer como suprimido (PONTO-060), com a indenizacao do '
             || 'art. 71, 4, e nao como gozado.', coalesce(v_o_com, 'nulo'));
  ELSIF v_pre_com IS NOT NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO PARCIAL: a origem ficou correta (marcado), mas o dia guardou '
             || '%s minuto(s) de intervalo pre-assinalado junto — dois valores para o mesmo '
             || 'intervalo confundem o espelho e a memoria de calculo.', v_pre_com);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('A batida real prevalece: dia com almoco batido tem origem "marcado" '
             || '(sem declaracao junto); dia sem batida fica com "%s".',
             coalesce(v_o_sem, 'nenhuma declaracao vigente'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

DO $fim$
BEGIN
  RAISE NOTICE 'PONTO 421 (folga compensatoria) e 410 (sonda comportamental do intervalo) aplicados.';
END $fim$;

-- ---------------------------------------------------------------------------
-- CONFERENCIA FINAL — as duas neste ambiente.
--
-- Esperado onde HA a pre-assinalacao (onda 4):   passou | passou | OK
-- Esperado onde NAO HA a pre-assinalacao:        passou | falhou | OK
--   (o 410 acusa, e deve: sem a coluna intervalo_origem nao ha como
--    provar, dia a dia, se o intervalo foi batido ou apenas declarado.
--    E achado do ambiente, nao defeito desta entrega.)
--
--   c421    : a folga compensatoria registra e debita o banco
--   c410    : a batida real prevalece sobre a declaracao
--   tem_onda4: o ambiente tem o registro da origem do intervalo
-- ---------------------------------------------------------------------------
WITH x AS MATERIALIZED (
  SELECT (public.qa_caso_ponto_421()).situacao AS c421,
         (public.qa_caso_ponto_410()).situacao AS c410,
         EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'ponto_diario'
                    AND column_name = 'intervalo_origem') AS tem_onda4
)
SELECT c421, c410, tem_onda4,
       CASE
         WHEN c421 NOT IN ('passou','nao_implementado') THEN 'CONFERIR'
         -- Sem a onda 4, o 410 acusa a lacuna do ambiente: e o esperado.
         WHEN NOT tem_onda4 THEN 'OK'
         WHEN c410 IN ('passou','nao_implementado') THEN 'OK'
         ELSE 'CONFERIR'
       END AS erro_tecnico
FROM x;
