-- ============================================================================
-- QA — LOTE 1b (ANDAIME COMPLETO): apoios + sub-rotinas _corpo na producao.
--
-- Refaz o Lote 1 (10 apoios) de forma idempotente E acrescenta as sub-rotinas
-- qa_caso_*_corpo, que algumas rotinas de caso chamam e ficaram de fora dos
-- diagnosticos anteriores (por casarem com o padrao qa_caso_*). Read-only por
-- natureza. CREATE OR REPLACE — pode rodar quantas vezes quiser.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.qa_afast_legado(p_nome text, p_inicio date)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  -- Nasce legítimo: prazo indeterminado pode existir sem data de término.
  v_id := public.qa_afast_novo(p_nome, p_inicio, NULL, true);

  -- Retira a marcação. A guarda de UPDATE só reage quando havia uma data
  -- de término e alguém tenta apagá-la; aqui nunca houve.
  UPDATE public.afastamentos
     SET prazo_indeterminado = false,
         status_geral_new    = 'registrado'
   WHERE id = v_id;

  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_afast_novo(p_nome text, p_inicio date, p_fim date, p_prazo_indeterminado boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.afastamentos
    (tenant_id, colaborador_nome, colaborador_cpf, data_inicio, data_fim,
     status, prazo_indeterminado)
  VALUES (public.qa_sandbox_tenant_id(), p_nome, public.qa_cpf(9101),
          p_inicio, p_fim, 'ativo', p_prazo_indeterminado)
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_afast_tipado(p_nome text, p_semente integer, p_inicio date, p_fim date, p_tipo text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.afastamentos
    (tenant_id, colaborador_nome, colaborador_cpf, data_inicio, data_fim,
     status, tipo_principal_new)
  VALUES (public.qa_sandbox_tenant_id(), p_nome, public.qa_cpf(p_semente),
          p_inicio, p_fim, 'ativo', p_tipo::public.afastamento_tipo_principal)
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_cpf_formatado(p_cpf text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT format('%s.%s.%s-%s',
                substr(p_cpf,1,3), substr(p_cpf,4,3), substr(p_cpf,7,3), substr(p_cpf,10,2))
$function$

;

CREATE OR REPLACE FUNCTION public.qa_feriado_da_unidade(p_empresa_id uuid, p_data date, p_nome text DEFAULT '[QA] Feriado de Teste'::text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_t uuid := public.qa_sandbox_tenant_id(); v_tab uuid;
BEGIN
  INSERT INTO public.feriado_tabelas (tenant_id, nome, uf, municipio, ano, ativo)
  VALUES (v_t, p_nome || ' ' || p_data, 'SP', 'São Paulo', EXTRACT(YEAR FROM p_data)::int, true)
  RETURNING id INTO v_tab;
  INSERT INTO public.feriado_tabela_itens (tenant_id, tabela_id, nome, data, recorrente, tipo, ativo)
  VALUES (v_t, v_tab, p_nome, p_data, false, 'feriado', true);
  INSERT INTO public.feriado_tabela_empresas (tenant_id, tabela_id, empresa_id)
  VALUES (v_t, v_tab, p_empresa_id);
  RETURN v_tab;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_ferias_periodo(p_cpf text, p_nome text, p_faltas integer DEFAULT 0, p_aquisitivo_fim date DEFAULT (CURRENT_DATE - 30))
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid; v_direito int := public.ferias_dias_por_faltas_clt(p_faltas);
BEGIN
  INSERT INTO public.ferias_periodos_aquisitivos
    (tenant_id, colaborador_cpf, colaborador_nome, data_admissao,
     aquisitivo_inicio, aquisitivo_fim, faltas_carga, dias_gozados,
     fonte_faltas, dias_direito, dias_saldo, faltas_consideradas, status, origem)
  VALUES (public.qa_sandbox_tenant_id(), p_cpf, p_nome,
          p_aquisitivo_fim - interval '1 year',
          p_aquisitivo_fim - interval '1 year', p_aquisitivo_fim,
          p_faltas, 0, 'carga', v_direito, v_direito, p_faltas, 'ativo', 'sistema')
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_ponto_dia_horarios(p_cpf text, p_nome text, p_data date, p_entrada time without time zone, p_saida time without time zone, p_salm time without time zone DEFAULT NULL::time without time zone, p_ralm time without time zone DEFAULT NULL::time without time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_t uuid := public.qa_sandbox_tenant_id();
  v_id uuid; v_colab uuid; v_min int;
BEGIN
  v_min := floor(EXTRACT(EPOCH FROM (p_saida - p_entrada))/60)::int;
  IF v_min < 0 THEN v_min := v_min + 1440; END IF;
  IF p_salm IS NOT NULL AND p_ralm IS NOT NULL THEN
    v_min := v_min - floor(EXTRACT(EPOCH FROM (p_ralm - p_salm))/60)::int;
  END IF;

  SELECT d.id, d.colaborador_id INTO v_id, v_colab
  FROM public.ponto_diario d
  WHERE d.tenant_id = v_t AND d.colaborador_cpf = p_cpf AND d.data = p_data
  ORDER BY d.created_at NULLS LAST
  LIMIT 1;

  IF v_id IS NOT NULL THEN
    UPDATE public.ponto_diario
       SET entrada = p_entrada, saida = p_saida,
           saida_almoco = p_salm, retorno_almoco = p_ralm,
           horas_trabalhadas = make_interval(mins => v_min)
     WHERE id = v_id;
    RETURN coalesce(v_colab, gen_random_uuid());
  END IF;

  v_colab := gen_random_uuid();
  INSERT INTO public.ponto_diario
    (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf, data,
     entrada, saida_almoco, retorno_almoco, saida, horas_trabalhadas, status)
  VALUES (v_t, v_colab, p_nome, p_cpf, p_data,
          p_entrada, p_salm, p_ralm, p_saida, make_interval(mins => v_min), 'regular');
  RETURN v_colab;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_ponto_dia_min(p_cpf text, p_nome text, p_data date, p_minutos integer)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE v_t uuid := public.qa_sandbox_tenant_id(); v_id uuid;
BEGIN
  -- Atualiza a linha do dia se ela existir; senão, insere. Vale tanto na
  -- chave nova (com empresa) quanto na antiga (sem), porque não nomeia
  -- índice nenhum.
  SELECT d.id INTO v_id
  FROM public.ponto_diario d
  WHERE d.tenant_id = v_t AND d.colaborador_cpf = p_cpf AND d.data = p_data
  ORDER BY d.created_at NULLS LAST
  LIMIT 1;

  IF v_id IS NOT NULL THEN
    UPDATE public.ponto_diario
       SET horas_trabalhadas = make_interval(mins => p_minutos),
           saida = TIME '08:00' + make_interval(mins => p_minutos)
     WHERE id = v_id;
  ELSE
    INSERT INTO public.ponto_diario
      (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
       data, entrada, saida, horas_trabalhadas, status)
    VALUES (v_t, gen_random_uuid(), p_nome, p_cpf,
            p_data, TIME '08:00', TIME '08:00' + make_interval(mins => p_minutos),
            make_interval(mins => p_minutos), 'regular');
  END IF;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_ponto_escala_tol(p_cpf text, p_nome text, p_jornada_min integer, p_tol_min integer, p_data_inicio date, p_data_fim date)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.ponto_escalas
    (tenant_id, nome, tipo, modalidade, jornada_diaria_minutos,
     jornada_semanal_minutos, intervalo_intrajornada_minutos,
     tolerancia_minutos, tolerancia_diaria_minutos,
     hora_entrada_padrao, hora_saida_padrao,
     equalizacao_mensal_ativa, carga_semanal_contratada_min, ativa)
  VALUES (public.qa_sandbox_tenant_id(), 'QA escala ' || p_cpf, 'fixa', 'fixa',
          p_jornada_min, p_jornada_min * 5, 60,
          LEAST(p_tol_min, 5), p_tol_min,
          TIME '08:00', TIME '17:00',
          false, p_jornada_min * 5, true)
  RETURNING id INTO v_id;

  INSERT INTO public.ponto_escala_atribuicoes
    (tenant_id, escala_id, colaborador_id, colaborador_nome, colaborador_cpf,
     data_inicio, data_fim, ativa)
  VALUES (public.qa_sandbox_tenant_id(), v_id, p_cpf, p_nome, p_cpf,
          p_data_inicio, p_data_fim, true);
  RETURN v_id;
END;
$function$

;

CREATE OR REPLACE FUNCTION public.qa_ponto_marca(p_cpf text, p_nome text, p_data date, p_hora time without time zone, p_tipo text, p_original boolean DEFAULT true)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.ponto_marcacoes
    (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
     data_marcacao, hora_marcacao, tipo_marcacao,
     hash_marcacao, marcacao_original, origem_marcacao)
  VALUES (public.qa_sandbox_tenant_id(), gen_random_uuid(), p_nome, p_cpf,
          p_data, p_hora, p_tipo,
          'qa-seed', p_original, CASE WHEN p_original THEN 'O' ELSE 'A' END);
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_210_corpo()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
  r public.qa_retorno;
  v_cpf text; v_t uuid := public.qa_sandbox_tenant_id();
  v_n1 bigint; v_n2 bigint;
  v_mudou boolean := false;
  v_unico boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Gravar duas marcacoes e conferir se o NSR nasce sozinho e continua a serie';
  r.esperado := 'NSR atribuido na gravacao, sequencial, sem buraco';

  v_cpf := public.qa_ponto_admissao('QA NSR', 2101);
  PERFORM public.qa_ponto_marca(v_cpf, 'QA NSR', CURRENT_DATE - 2, TIME '08:00', 'entrada');
  PERFORM public.qa_ponto_marca(v_cpf, 'QA NSR', CURRENT_DATE - 2, TIME '12:00', 'saida');

  SELECT min(nsr), max(nsr) INTO v_n1, v_n2
  FROM public.ponto_marcacoes
  WHERE tenant_id = v_t AND colaborador_cpf = v_cpf;

  r.passo_ordem := 2;
  r.passo_acao := 'Tentar ALTERAR o NSR de uma marcacao ja gravada';
  r.esperado := 'Recusado — o numero amarra o registro ao arquivo-fonte';
  BEGIN
    UPDATE public.ponto_marcacoes SET nsr = nsr + 1000
    WHERE tenant_id = v_t AND colaborador_cpf = v_cpf;
    v_mudou := true;
  EXCEPTION WHEN OTHERS THEN v_mudou := false; END;

  r.passo_ordem := 3;
  r.passo_acao := 'Conferir que o NSR nao se repete dentro do estabelecimento';
  r.esperado := 'Indice unico por (tenant, empresa, nsr)';
  SELECT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public' AND tablename = 'ponto_marcacoes'
      AND indexname = 'ponto_marcacoes_nsr_unico'
  ) INTO v_unico;

  IF v_n1 IS NOT NULL AND v_n2 = v_n1 + 1 AND NOT v_mudou AND v_unico THEN
    r.situacao := 'passou';
    r.obtido := format('NSR atribuido na gravacao (%s e %s, sem buraco), imutavel depois de '
             || 'gravado e unico por estabelecimento. Marcacoes anteriores a esta '
             || 'funcionalidade ficam sem NSR ate rodar o preenchimento historico.', v_n1, v_n2);
  ELSIF v_n1 IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a marcacao foi gravada SEM NSR. Sem numeracao sequencial de registro, '
             || 'o AFD improvisa numeros na exportacao e nada demonstra que nenhum registro foi '
             || 'removido. E o requisito central do arquivo-fonte da Portaria 671.';
  ELSIF v_n2 <> v_n1 + 1 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a serie do NSR tem buraco (%s depois de %s). Buraco na sequencia '
             || 'e exatamente o que a fiscalizacao le como registro removido.', v_n2, v_n1);
  ELSIF v_mudou THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o NSR de uma marcacao ja gravada pode ser ALTERADO. Numero que muda nao '
             || 'amarra nada — o vinculo entre a marcacao e o arquivo-fonte deixa de provar.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: falta o indice que impede NSR repetido dentro do estabelecimento.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_301_corpo()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_cpf text; v_comp text := to_char(CURRENT_DATE - 7, 'YYYY-MM'); v_dif int;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_cpf := public.qa_ponto_admissao('[QA-PONTO] Intocado', 30101);
  PERFORM public.qa_ponto_dia(v_cpf, '[QA-PONTO] Intocado', public.qa_dia_util_passado());

  r.passo_ordem := 1;
  r.passo_acao := 'Comparar a apuração pública com a bruta num período sem duplicatas';
  r.esperado := 'Idênticas, linha a linha — o invólucro só age quando há duplicata';
  SELECT count(*) INTO v_dif FROM (
    SELECT * FROM public.ponto_saldo_dias_competencia(v_t, v_cpf, v_comp)
    EXCEPT
    SELECT * FROM public.ponto_saldo_dias_competencia_bruto(v_t, v_cpf, v_comp)
  ) x;

  IF v_dif = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'Sem duplicata, a saída pública é idêntica à bruta — a correção foi cirúrgica como prometido.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('%s linha(s) diferentes entre a função pública e a bruta num período SEM duplicatas — o invólucro está alterando dias que deveria deixar em paz.', v_dif);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_321_corpo()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_emp uuid; v_cpf text; v_dia date := public.qa_dia_util_passado();
        v_comp text; v_colab uuid := gen_random_uuid(); a record;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_comp := to_char(v_dia, 'YYYY-MM');
  v_emp := public.qa_nova_empresa('[QA-RN23] Unidade Compensada', '11222333032102');
  v_cpf := public.qa_ponto_admissao('[QA-RN23] Compensou a Folga', 32101, v_emp);
  PERFORM public.qa_feriado_da_unidade(v_emp, v_dia);
  PERFORM public.qa_ponto_dia(v_cpf, '[QA-RN23] Compensou a Folga', v_dia, v_emp);

  r.passo_ordem := 1;
  r.passo_acao := 'Registrar a folga compensatória do feriado trabalhado';
  r.esperado := 'Registro aceito, vinculando feriado, colaborador e dia da folga';
  INSERT INTO public.feriado_folga_compensatoria
    (tenant_id, colaborador_id, colaborador_cpf, data_feriado, data_folga)
  VALUES (v_t, v_colab, v_cpf, v_dia, v_dia + 7);

  r.passo_ordem := 2;
  r.passo_acao := 'Apurar o adicional da competência com a folga registrada';
  r.esperado := 'O feriado compensado sai do cálculo do adicional (art. 9º, parte final)';
  SELECT * INTO a FROM public.ponto_feriado_adicional_competencia(v_t, v_emp, v_comp) f
  WHERE regexp_replace(f.colaborador_cpf, '[^0-9]', '', 'g') = v_cpf;

  IF a.colaborador_cpf IS NULL OR COALESCE(a.minutos_adicional_100, 0) = 0 THEN
    r.situacao := 'passou';
    r.obtido := format('Compensou, não dobra: com a folga registrada, o adicional zerou (dias compensados: %s).', COALESCE(a.dias_compensados, 0));
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('A FOLGA REGISTRADA NÃO AFASTOU A DOBRA: adicional_100 = %s minuto(s) mesmo com compensação. Pagaria em dobro E daria a folga — duas vezes a mesma hora.', a.minutos_adicional_100);
  END IF;
  RETURN r;
EXCEPTION
  WHEN undefined_function THEN
    r.situacao := 'falhou';
    r.obtido := 'A APURAÇÃO RN23 QUEBRA NESTE BANCO: ' || SQLERRM || '. A função de apoio '
      || 'feriado_comportamento não existe em NENHUMA migration do repositório — foi criada '
      || 'por fora, direto no banco (mesmo precedente de feriados e ponto_diario.tipo_dia). '
      || 'Qualquer ambiente montado a partir das migrations fica com o adicional de feriado '
      || 'inoperante. Correção: trazer a função para o repositório com CREATE OR REPLACE.';
    r.erro_tecnico := SQLERRM;
    RETURN r;
  WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_394_corpo()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_cpf text := public.qa_cpf(3941);
  v_ea uuid; v_eb uuid;
  v_data date := CURRENT_DATE - 3;
  v_linhas_dois int;
  v_cpf_uni text := public.qa_cpf(3942);
  v_data_uni date := CURRENT_DATE - 4;
  v_linhas_uni int;
BEGIN
  v_ea := public.qa_nova_empresa('QA Vinculo A ' || v_cpf, '11.222.333/0001-81', true);
  v_eb := public.qa_nova_empresa('QA Vinculo B ' || v_cpf, '11.444.777/0001-61', true);

  r.passo_ordem := 1;
  r.passo_acao := 'Registrar o MESMO dia do MESMO CPF em dois vinculos (duas empresas)';
  r.esperado := 'Cada vinculo tem a sua linha de apuracao — contratos autonomos';
  PERFORM public.qa_ponto_dia(v_cpf, 'QA Dois Vinculos', v_data, v_ea);
  PERFORM public.qa_ponto_dia(v_cpf, 'QA Dois Vinculos', v_data, v_eb);

  SELECT count(*) INTO v_linhas_dois
  FROM public.ponto_diario
  WHERE tenant_id = v_t AND colaborador_cpf = v_cpf AND data = v_data;

  r.passo_ordem := 2;
  r.passo_acao := 'Nao-regressao: um unico vinculo, marcacoes + abono, no mesmo dia';
  r.esperado := 'Uma unica linha — a empresa na chave nao parte o dia de quem tem um vinculo';
  -- admissao com empresa unica; consolidacao deriva a empresa do cadastro
  PERFORM public.qa_ponto_admissao('QA Um Vinculo', 3942, v_ea);
  PERFORM public.qa_ponto_marca(v_cpf_uni, 'QA Um Vinculo', v_data_uni, TIME '08:00', 'entrada');
  PERFORM public.qa_ponto_marca(v_cpf_uni, 'QA Um Vinculo', v_data_uni, TIME '17:00', 'saida');
  PERFORM public.consolidar_ponto_diario_manual(v_t, v_cpf_uni, v_data_uni);
  -- uma segunda escrita no mesmo dia (abono) nao pode criar uma segunda linha
  PERFORM public.consolidar_ponto_diario_manual(v_t, v_cpf_uni, v_data_uni);

  SELECT count(*) INTO v_linhas_uni
  FROM public.ponto_diario
  WHERE tenant_id = v_t AND colaborador_cpf = v_cpf_uni AND data = v_data_uni;

  IF v_linhas_dois = 2 AND v_linhas_uni = 1 THEN
    r.situacao := 'passou';
    r.obtido := 'Dois vinculos do mesmo CPF apuraram o mesmo dia em linhas separadas (2), e o '
             || 'colaborador de um unico vinculo manteve uma linha (1) apos duas escritas no '
             || 'mesmo dia. A empresa entrou na chave sem partir o dia de quem tem um vinculo.';
  ELSIF v_linhas_dois < 2 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO ESTRUTURAL: dois vinculos do mesmo CPF no mesmo dia produziram %s '
             || 'linha(s), nao 2 — a apuracao continua chaveada de um jeito que impede o segundo '
             || 'contrato. O documento de requisitos exige apuracao e arquivos POR VINCULO.',
             v_linhas_dois);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('REGRESSAO: um colaborador de UNICO vinculo ficou com %s linhas no mesmo '
             || 'dia. A empresa na chave partiu o dia de quem tem um vinculo so — o gatilho de '
             || 'reconciliacao nao esta fundindo as escritas.', v_linhas_uni);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_431_corpo()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_comp text := to_char(CURRENT_DATE, 'YYYY-MM'); v_qtd int; v_uq text;
        v_recusou boolean := false;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Montar o dossie da competencia DUAS vezes e contar';
  r.esperado := 'Um unico dossie por competencia, com data e hash atualizados';

  INSERT INTO public.ponto_dossies_fiscalizacao
    (tenant_id, competencia, periodo_ini, periodo_fim, total_pecas, hash_pacote)
  VALUES (v_t, v_comp, date_trunc('month', CURRENT_DATE)::date, CURRENT_DATE, 5, 'qa-hash-1')
  ON CONFLICT DO NOTHING;

  BEGIN
    INSERT INTO public.ponto_dossies_fiscalizacao
      (tenant_id, competencia, periodo_ini, periodo_fim, total_pecas, hash_pacote)
    VALUES (v_t, v_comp, date_trunc('month', CURRENT_DATE)::date, CURRENT_DATE, 7, 'qa-hash-2');
  EXCEPTION WHEN unique_violation THEN
    v_recusou := true;  -- a trava existe: e exatamente o que o caso cobra
  END;

  SELECT count(*) INTO v_qtd FROM public.ponto_dossies_fiscalizacao d
  WHERE d.tenant_id = v_t AND d.competencia = v_comp;

  SELECT string_agg(indexname, ', ') INTO v_uq FROM pg_indexes
  WHERE schemaname = 'public' AND tablename = 'ponto_dossies_fiscalizacao'
    AND indexdef ILIKE '%unique%';

  IF v_qtd > 1 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a mesma competencia ficou com %s dossies — remontar empilha '
             || 'copias em vez de atualizar. Dois dossies da mesma competencia com conteudos '
             || 'e hashes diferentes e o pior cenario na fiscalizacao: a empresa apresenta um '
             || 'e o auditor encontra o outro. Correcao: unicidade por tenant+competencia com '
             || 'atualizacao no lugar.', v_qtd);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Dossie unico por competencia (registros: %s; segundo lancamento %s; '
             || 'unicidade: %s).', v_qtd,
             CASE WHEN v_recusou THEN 'recusado pela trava' ELSE 'atualizou o existente' END,
             coalesce(v_uq, 'na gravacao'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

-- ── Conferencia: os apoios existem agora? + rotinas que dependiam deles ──────
SELECT 'apoios/sub-rotinas presentes' AS item,
       count(*)::text || ' de 15' AS valor
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN
 ('qa_afast_legado','qa_afast_novo','qa_afast_tipado','qa_cpf_formatado','qa_feriado_da_unidade',
  'qa_ferias_periodo','qa_ponto_dia_horarios','qa_ponto_dia_min','qa_ponto_escala_tol','qa_ponto_marca',
  'qa_caso_ponto_210_corpo','qa_caso_ponto_301_corpo','qa_caso_ponto_321_corpo','qa_caso_ponto_394_corpo','qa_caso_ponto_431_corpo')
UNION ALL
SELECT 'familia Ponto: ' || (public.qa_executar_descartavel('qa_caso_ponto_321')).situacao::text
        || ' / ' || (public.qa_executar_descartavel('qa_caso_ponto_394')).situacao::text,
       'PONTO-321 / PONTO-394';
