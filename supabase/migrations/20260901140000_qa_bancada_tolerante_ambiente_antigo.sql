-- =====================================================================
-- QA — a bancada roda em ambiente ANTIGO sem quebrar
--
-- MOTIVO: a bateria do Ponto rodada na HOMOLOGAÇÃO (31/08) voltou com 21
-- casos em ERRO. O detalhe técnico mostrou que quase todos têm uma causa
-- só, e que ela não é do sistema testado — é da própria bancada, que
-- pressupunha a estrutura MAIS NOVA do projeto:
--
--   14 casos:  "there is no unique or exclusion constraint matching the
--              ON CONFLICT specification"
--     As ferramentas de massa (qa_ponto_dia_min, qa_ponto_dia_horarios)
--     usam ON CONFLICT apontando a chave de apuração diária COM empresa
--     (tenant, cpf, data, COALESCE(empresa_id, ...)), criada pela onda 1
--     (20260818190000). Onde a onda 1 ainda não chegou, a chave é a antiga
--     (tenant, cpf, data) e o ON CONFLICT não encontra índice — a rotina
--     nem começa. Aqui elas passam a NÃO depender da forma do índice:
--     tentam atualizar a linha do dia e, se não houver, inserem.
--
--   4 casos:   estrutura ausente no destino (coluna nsr; função
--              ponto_saldo_dias_competencia_bruto; tabelas
--              feriado_folga_compensatoria e ponto_dossies_fiscalizacao).
--     Eram ERRO — que não diz nada a quem lê o relatório. Passam a ser
--     FALHA COM ACHADO, dizendo qual peça falta no ambiente e o que isso
--     significa. É a diferença entre ruído e informação: ERRO é a rotina
--     que não chegou ao fim; FALHOU é o veredito de que o ambiente não
--     atende à regra.
--
--   1 caso:    PONTO-354 (conversão global tocando outro tenant) já foi
--              tratado em 20260827100000 — não se repete aqui.
--
-- NADA DE REGRA DE NEGÓCIO MUDA. Só a bancada que a verifica.
-- =====================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- 1) FERRAMENTAS DE MASSA — independentes da forma do índice
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.qa_ponto_dia_min(
  p_cpf text, p_nome text, p_data date, p_minutos integer)
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
END $function$;

CREATE OR REPLACE FUNCTION public.qa_ponto_dia_horarios(
  p_cpf text, p_nome text, p_data date,
  p_entrada time without time zone, p_saida time without time zone,
  p_salm time without time zone DEFAULT NULL,
  p_ralm time without time zone DEFAULT NULL)
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
END $function$;

-- ---------------------------------------------------------------------
-- 2) SONDAS DE ESTRUTURA AUSENTE — achado em vez de erro
--
-- Cada uma ganha uma guarda no inicio: se a peca que ela precisa nao
-- existe no ambiente, devolve FALHOU explicando a lacuna. Quando a peca
-- existe, o corpo original roda igual (delegado a rotina real).
-- ---------------------------------------------------------------------

-- Guarda comum: renomeia a rotina original e cria um invólucro.
DO $envelopa$
DECLARE
  v record;
BEGIN
  FOR v IN
    SELECT * FROM (VALUES
      ('qa_caso_ponto_210',
       'A coluna nsr (Numero Sequencial de Registro) nao existe em ponto_marcacoes neste ambiente.',
       'ACHADO: este ambiente nao tem a coluna NSR nas marcacoes — sem ela nao ha numeracao sequencial de registro, e o AFD exigido pela Portaria MTP 671/2021 nao pode ser gerado com a serie continua que a fiscalizacao confere. A estrutura existe no projeto; falta chegar aqui.'),
      ('qa_caso_ponto_301',
       'A funcao ponto_saldo_dias_competencia_bruto nao existe neste ambiente.',
       'ACHADO: este ambiente nao tem a apuracao BRUTA (ponto_saldo_dias_competencia_bruto), que serve de referencia para provar que o agrupamento por dia nao altera um dia normal. Sem ela nao ha como comparar o resultado publico com a fonte. A funcao existe no projeto; falta chegar aqui.'),
      ('qa_caso_ponto_321',
       'A tabela feriado_folga_compensatoria nao existe neste ambiente.',
       'ACHADO: este ambiente nao tem onde registrar a folga compensatoria do feriado trabalhado — logo, nao ha como afastar o pagamento em dobro (CLT art. 9 da Lei 605/49 c/c Sumula 146 do TST) provando a compensacao. Ou a empresa paga a dobra sempre, ou deixa de pagar sem prova. A tabela existe no projeto; falta chegar aqui.'),
      ('qa_caso_ponto_431',
       'A tabela ponto_dossies_fiscalizacao nao existe neste ambiente.',
       'ACHADO: este ambiente nao tem a tabela do dossie de fiscalizacao — nao ha o que remontar nem como garantir um dossie unico por competencia. A estrutura existe no projeto; falta chegar aqui.')
    ) AS t(fn, motivo, achado)
  LOOP
    -- so envelopa se a rotina existir e ainda nao tiver sido envelopada
    CONTINUE WHEN to_regprocedure('public.' || v.fn || '()') IS NULL;
    CONTINUE WHEN to_regprocedure('public.' || v.fn || '_corpo()') IS NOT NULL;

    EXECUTE format('ALTER FUNCTION public.%I() RENAME TO %I', v.fn, v.fn || '_corpo');

    EXECUTE format($f$
      CREATE OR REPLACE FUNCTION public.%I()
      RETURNS public.qa_retorno
      LANGUAGE plpgsql
      AS $corpo$
      DECLARE r public.qa_retorno;
      BEGIN
        IF %s THEN
          r.passo_ordem := 1;
          r.passo_acao  := 'Conferir se a estrutura que este caso exercita existe no ambiente';
          r.esperado    := 'Estrutura presente para o caso poder ser exercitado';
          r.situacao    := 'falhou';
          r.obtido      := %L;
          r.erro_tecnico := %L;
          RETURN r;
        END IF;
        RETURN public.%I();
      END $corpo$;
    $f$, v.fn,
        CASE v.fn
          WHEN 'qa_caso_ponto_210' THEN 'public.qa_coluna_existe(''ponto_marcacoes'', ''nsr'') IS NOT TRUE'
          WHEN 'qa_caso_ponto_301' THEN 'to_regprocedure(''public.ponto_saldo_dias_competencia_bruto(uuid, text, text)'') IS NULL'
          WHEN 'qa_caso_ponto_321' THEN 'to_regclass(''public.feriado_folga_compensatoria'') IS NULL'
          WHEN 'qa_caso_ponto_431' THEN 'to_regclass(''public.ponto_dossies_fiscalizacao'') IS NULL'
        END,
        v.achado, v.motivo, v.fn || '_corpo');

    RAISE NOTICE 'Sonda % passou a acusar a lacuna em vez de quebrar.', v.fn;
  END LOOP;
END $envelopa$;

DO $fim$
BEGIN
  RAISE NOTICE 'Bancada tolerante a ambiente antigo: ferramentas de massa sem ON CONFLICT e 4 sondas com guarda de estrutura.';
END $fim$;
