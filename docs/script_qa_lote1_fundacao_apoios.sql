-- ============================================================================
-- QA — LOTE 1 (FUNDACAO): entregar os 10 apoios de QA que faltam na producao.
--
-- Sao funcoes de APOIO (mobiliario de teste) que as rotinas usam para montar
-- cenarios. Existem no dev/staging desde suas migrations; nunca chegaram a
-- producao (drift forward-only). Read-only por natureza (montam dados de teste
-- que as rotinas descartam). Idempotente (CREATE OR REPLACE).
--
-- Com elas, varias rotinas de Ponto/Afastamento/Ferias que davam "erro" por
-- falta de apoio passam a rodar. Conferencia no fim roda 4 rotinas de Ponto
-- que dependiam desses apoios.
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

-- ── Conferencia: rotinas de Ponto que dependiam dos apoios ──────────────────
WITH alvo(codigo) AS (VALUES ('PONTO-004'),('PONTO-210'),('PONTO-402'),('PONTO-410'))
SELECT a.codigo, (public.qa_executar_descartavel(i.funcao_sql)).situacao::text AS situacao
FROM alvo a JOIN public.qa_implementacoes i ON i.codigo = a.codigo
ORDER BY a.codigo;
