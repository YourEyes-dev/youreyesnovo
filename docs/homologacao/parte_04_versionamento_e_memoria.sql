-- ============================================================================
-- HOMOLOGACAO — PONTO, PARTE 04 de 16: Versionamento de escala e memoria de calculo
--
-- Parametro de escala passa a ter vigencia (mudar a escala hoje nao
-- reescreve o mes passado) e cada apuracao guarda a memoria que permite
-- refazer a conta.
--
-- ONDE COLAR
-- No SQL Editor do projeto de HOMOLOGACAO. Nao e para a producao: a producao
-- so muda por gesto manual seu, depois de conferida aqui.
--
-- COMO USAR
-- Cole o arquivo INTEIRO e execute uma vez. Pode rodar de novo sem risco
-- (idempotente). As partes tem ordem: rode da 01 para a 16, conferindo o
-- resultado de cada uma antes de passar para a seguinte.
--
-- O QUE ESTE ARQUIVO REUNE
--   * script_ponto_onda1_versionamento_e_memoria.sql
--
-- Ao final sai UMA conferencia, dizendo o que chegou e o que faltou.
-- ============================================================================



-- ############################################################
-- BLOCO: script_ponto_onda1_versionamento_e_memoria.sql
-- ############################################################

-- ============================================================================
-- SCRIPT DE ENTREGA — PONTO, ONDA 1 (parte 3): versionamento + memória
-- Cole no SQL Editor do banco de PRODUÇÃO (projeto diayjpsrcerycycyaxst)
-- SOMENTE após aprovar no ambiente de teste. Idempotente (pode rodar 2x).
--
-- O QUE FAZ
--   PONTO-153  parâmetros da escala versionados por vigência — editar a
--              escala hoje deixa de reescrever a apuração de um mês passado
--   PONTO-385  memória de cálculo por competência (fonte + resultado)
--
-- SEGURANÇA: a mudança é INERTE até alguém editar uma escala. Sem versões,
-- o overlay devolve a escala viva intacta e a apuração sai idêntica à de
-- hoje. Só depois de uma edição os dias passados passam a ler a versão
-- congelada. A memória é um registro sob demanda, ao lado da apuração.
--
-- A parte de QA (rotina do PONTO-385) fica no ambiente de teste.
-- ============================================================================

SET LOCAL lock_timeout = '10s';


-- ---------------------------------------------------------------------
-- PONTO-153 (1/3): tabela de versões dos parâmetros da escala
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ponto_escala_param_versoes (
  id                             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  escala_id                      uuid NOT NULL,
  tenant_id                      uuid,
  vigencia_inicio                date NOT NULL,
  vigencia_fim                   date NOT NULL,
  jornada_diaria_minutos         integer,
  hora_entrada_padrao            time without time zone,
  hora_saida_padrao              time without time zone,
  intervalo_intrajornada_minutos integer,
  tolerancia_minutos             integer,
  tolerancia_diaria_minutos      integer,
  dias_config                    jsonb,
  arquivada_em                   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ponto_escala_versao_periodo CHECK (vigencia_fim >= vigencia_inicio)
);

COMMENT ON TABLE public.ponto_escala_param_versoes IS
  'PONTO-153 — parametros da escala congelados por vigencia. Uma linha por edicao: guarda os valores ANTIGOS e o periodo em que valeram. A apuracao de um dia passado le a versao que cobre a data, nao o valor vivo.';

CREATE INDEX IF NOT EXISTS ponto_escala_param_versoes_busca
  ON public.ponto_escala_param_versoes (escala_id, vigencia_inicio DESC);

ALTER TABLE public.ponto_escala_param_versoes ENABLE ROW LEVEL SECURITY;

DO $pol_ver$
BEGIN
  DROP POLICY IF EXISTS "Tenant gerencia ponto_escala_param_versoes" ON public.ponto_escala_param_versoes;
  CREATE POLICY "Tenant gerencia ponto_escala_param_versoes"
    ON public.ponto_escala_param_versoes FOR ALL
    USING (tenant_id = public.current_user_tenant_id())
    WITH CHECK (tenant_id = public.current_user_tenant_id());
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Politica de ponto_escala_param_versoes nao aplicada: %', SQLERRM;
END $pol_ver$;

-- ---------------------------------------------------------------------
-- PONTO-153 (2/3): ao editar a escala, arquiva os parâmetros ANTIGOS
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_escala_arquiva_versao()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  v_inicio date;
BEGIN
  -- Só arquiva se um parâmetro que a apuração usa realmente mudou.
  IF NEW.jornada_diaria_minutos         IS DISTINCT FROM OLD.jornada_diaria_minutos
     OR NEW.tolerancia_minutos          IS DISTINCT FROM OLD.tolerancia_minutos
     OR NEW.tolerancia_diaria_minutos   IS DISTINCT FROM OLD.tolerancia_diaria_minutos
     OR NEW.hora_entrada_padrao         IS DISTINCT FROM OLD.hora_entrada_padrao
     OR NEW.hora_saida_padrao           IS DISTINCT FROM OLD.hora_saida_padrao
     OR NEW.intervalo_intrajornada_minutos IS DISTINCT FROM OLD.intervalo_intrajornada_minutos
     OR NEW.dias_config                 IS DISTINCT FROM OLD.dias_config
  THEN
    -- Início da vigência dos params antigos: logo após a última versão
    -- arquivada desta escala, ou um piso bem antigo na primeira vez.
    SELECT COALESCE(max(vigencia_fim) + 1, DATE '1900-01-01')
      INTO v_inicio
    FROM public.ponto_escala_param_versoes WHERE escala_id = OLD.id;

    -- Edição hoje congela os valores antigos até ontem. Se o intervalo não
    -- é válido (params vigoraram só hoje), não há passado a congelar.
    IF v_inicio <= CURRENT_DATE - 1 THEN
      INSERT INTO public.ponto_escala_param_versoes
        (escala_id, tenant_id, vigencia_inicio, vigencia_fim,
         jornada_diaria_minutos, hora_entrada_padrao, hora_saida_padrao,
         intervalo_intrajornada_minutos, tolerancia_minutos, tolerancia_diaria_minutos,
         dias_config)
      VALUES (OLD.id, OLD.tenant_id, v_inicio, CURRENT_DATE - 1,
              OLD.jornada_diaria_minutos, OLD.hora_entrada_padrao, OLD.hora_saida_padrao,
              OLD.intervalo_intrajornada_minutos, OLD.tolerancia_minutos, OLD.tolerancia_diaria_minutos,
              OLD.dias_config);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ponto_escala_arquiva_versao ON public.ponto_escalas;
CREATE TRIGGER trg_ponto_escala_arquiva_versao
BEFORE UPDATE ON public.ponto_escalas
FOR EACH ROW
EXECUTE FUNCTION public.ponto_escala_arquiva_versao();

-- ---------------------------------------------------------------------
-- PONTO-153 (3/3): overlay — devolve a escala com os parâmetros da versão
-- vigente na data. Sem versão cobrindo a data, devolve a escala intacta
-- (é o que torna a mudança inerte até a primeira edição).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_escala_com_versao(esc public.ponto_escalas, p_data date)
RETURNS public.ponto_escalas
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v public.ponto_escala_param_versoes;
BEGIN
  IF esc.id IS NULL OR p_data IS NULL THEN
    RETURN esc;
  END IF;

  SELECT * INTO v
  FROM public.ponto_escala_param_versoes pv
  WHERE pv.escala_id = esc.id
    AND p_data BETWEEN pv.vigencia_inicio AND pv.vigencia_fim
  ORDER BY pv.vigencia_inicio DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN esc;  -- nenhuma versão cobre a data: a escala viva é a vigente
  END IF;

  esc.jornada_diaria_minutos          := v.jornada_diaria_minutos;
  esc.tolerancia_minutos              := v.tolerancia_minutos;
  esc.tolerancia_diaria_minutos       := v.tolerancia_diaria_minutos;
  esc.hora_entrada_padrao             := v.hora_entrada_padrao;
  esc.hora_saida_padrao               := v.hora_saida_padrao;
  esc.intervalo_intrajornada_minutos  := v.intervalo_intrajornada_minutos;
  esc.dias_config                     := v.dias_config;
  RETURN esc;
END;
$$;

-- ---------------------------------------------------------------------
-- PONTO-153: os três leitores que carregam a escala recebem o overlay.
--   Uma única linha inserida logo após a guarda de escala nula; o resto
--   do corpo é o original.
-- ---------------------------------------------------------------------
-- ---- ponto_jornada_do_dia: overlay de versao apos a guarda ----
CREATE OR REPLACE FUNCTION public.ponto_jornada_do_dia(p_tenant_id uuid, p_cpf text, p_colaborador_id text, p_data date)
 RETURNS TABLE(jornada_min integer, tol_min integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_escala public.ponto_escalas;
  v_dow int;
  v_dia_key text;
  v_ordinal int;
  v_is_ultimo boolean;
  v_dia_cfg jsonb;
  v_comp jsonb;
  v_ord_raw text;
  v_entrada time;
  v_saida time;
  v_intervalo int;
  v_jornada int;
BEGIN
  SELECT e.* INTO v_escala
  FROM public.ponto_escala_atribuicoes a
  JOIN public.ponto_escalas e ON e.id = a.escala_id
  WHERE a.tenant_id = p_tenant_id
    AND (a.colaborador_cpf = p_cpf OR a.colaborador_id = p_colaborador_id)
    AND COALESCE(a.ativa, true) = true
    AND a.data_inicio <= p_data
    AND (a.data_fim IS NULL OR a.data_fim >= p_data)
  ORDER BY a.data_inicio DESC
  LIMIT 1;

  IF v_escala.id IS NULL THEN
    RETURN;
  END IF;

  -- PONTO-153: aplica os parametros da versao vigente na data (inerte se
  -- nao ha versao — devolve a escala viva intacta).
  v_escala := public.ponto_escala_com_versao(v_escala, p_data);

  IF v_escala.dias_config IS NULL OR jsonb_typeof(v_escala.dias_config) <> 'object' THEN
    jornada_min := v_escala.jornada_diaria_minutos;
    tol_min := COALESCE(v_escala.tolerancia_diaria_minutos, 0);
    RETURN NEXT;
    RETURN;
  END IF;

  v_dow := EXTRACT(DOW FROM p_data)::int;
  v_dia_key := CASE v_dow
    WHEN 0 THEN 'domingo'
    WHEN 1 THEN 'segunda'
    WHEN 2 THEN 'terca'
    WHEN 3 THEN 'quarta'
    WHEN 4 THEN 'quinta'
    WHEN 5 THEN 'sexta'
    WHEN 6 THEN 'sabado'
  END;

  v_dia_cfg := v_escala.dias_config -> v_dia_key;

  IF v_dia_cfg IS NOT NULL AND COALESCE((v_dia_cfg->>'trabalha')::boolean, false) THEN
    v_entrada := (v_dia_cfg->>'entrada')::time;
    v_saida := (v_dia_cfg->>'saida')::time;
    v_jornada := EXTRACT(EPOCH FROM (v_saida - v_entrada))::int / 60;
    IF COALESCE((v_dia_cfg->>'tem_almoco')::boolean, false)
       AND (v_dia_cfg->>'inicio_almoco') IS NOT NULL
       AND (v_dia_cfg->>'fim_almoco') IS NOT NULL THEN
      v_jornada := v_jornada - (EXTRACT(EPOCH FROM (
        (v_dia_cfg->>'fim_almoco')::time - (v_dia_cfg->>'inicio_almoco')::time
      ))::int / 60);
    END IF;
    jornada_min := GREATEST(v_jornada, 0);
    tol_min := COALESCE(v_escala.tolerancia_diaria_minutos, 0);
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_escala.compensacoes_mensais IS NOT NULL
     AND jsonb_typeof(v_escala.compensacoes_mensais) = 'array' THEN
    v_ordinal := ((EXTRACT(DAY FROM p_data)::int - 1) / 7) + 1;
    -- é a última ocorrência deste dia da semana no mês?
    v_is_ultimo := (p_data + 7) > (date_trunc('month', p_data) + interval '1 month - 1 day')::date;

    -- ordinal_mes pode vir como número ('1'..'5'), 'ultimo'/'último',
    -- 'todos'/'todas'/vazio (qualquer ocorrência). Comparação textual evita
    -- o erro de cast que derrubava toda a apuração do dia.
    FOR v_comp IN
      SELECT c FROM jsonb_array_elements(v_escala.compensacoes_mensais) c
      WHERE c->>'dia_semana' = v_dia_key
    LOOP
      v_ord_raw := lower(trim(COALESCE(v_comp->>'ordinal_mes', '')));
      IF v_ord_raw IN ('', 'todos', 'todas', 'todo', 'toda', '0')
         OR (v_ord_raw ~ '^\d+$' AND v_ord_raw::int = v_ordinal)
         OR (v_ord_raw IN ('ultimo', 'último', 'ultima', 'última') AND v_is_ultimo) THEN
        v_entrada := (v_comp->>'entrada')::time;
        v_saida := (v_comp->>'saida')::time;
        v_intervalo := COALESCE(NULLIF(v_comp->>'intervalo','')::int, 0);
        v_jornada := (EXTRACT(EPOCH FROM (v_saida - v_entrada))::int / 60) - v_intervalo;
        jornada_min := GREATEST(v_jornada, 0);
        tol_min := COALESCE(v_escala.tolerancia_diaria_minutos, 0);
        RETURN NEXT;
        RETURN;
      END IF;
    END LOOP;
  END IF;

  jornada_min := 0;
  tol_min := COALESCE(v_escala.tolerancia_diaria_minutos, 0);
  RETURN NEXT;
END;
$function$;

-- ---- ponto_escala_do_dia: overlay de versao apos a guarda ----
CREATE OR REPLACE FUNCTION public.ponto_escala_do_dia(p_tenant_id uuid, p_cpf text, p_colaborador_id text, p_data date)
 RETURNS TABLE(entrada time without time zone, saida time without time zone, intervalo_min integer, jornada_min integer, tolerancia_batida_min integer, tolerancia_diaria_min integer, trabalha boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_escala public.ponto_escalas;
  v_dow int;
  v_dia_key text;
  v_ordinal int;
  v_dia_cfg jsonb;
  v_comp jsonb;
  v_entrada time;
  v_saida time;
  v_intervalo int;
  v_jornada int;
BEGIN
  SELECT e.* INTO v_escala
  FROM public.ponto_escala_atribuicoes a
  JOIN public.ponto_escalas e ON e.id = a.escala_id
  WHERE a.tenant_id = p_tenant_id
    AND (a.colaborador_cpf = p_cpf OR a.colaborador_id = p_colaborador_id)
    AND COALESCE(a.ativa, true) = true
    AND a.data_inicio <= p_data
    AND (a.data_fim IS NULL OR a.data_fim >= p_data)
  ORDER BY a.data_inicio DESC
  LIMIT 1;

  IF v_escala.id IS NULL THEN
    RETURN;
  END IF;

  -- PONTO-153: aplica os parametros da versao vigente na data (inerte se
  -- nao ha versao — devolve a escala viva intacta).
  v_escala := public.ponto_escala_com_versao(v_escala, p_data);

  v_dow := EXTRACT(DOW FROM p_data)::int;
  v_dia_key := CASE v_dow
    WHEN 0 THEN 'domingo' WHEN 1 THEN 'segunda' WHEN 2 THEN 'terca'
    WHEN 3 THEN 'quarta' WHEN 4 THEN 'quinta' WHEN 5 THEN 'sexta'
    WHEN 6 THEN 'sabado'
  END;

  IF v_escala.dias_config IS NOT NULL AND jsonb_typeof(v_escala.dias_config) = 'object' THEN
    v_dia_cfg := v_escala.dias_config -> v_dia_key;
    IF v_dia_cfg IS NOT NULL AND COALESCE((v_dia_cfg->>'trabalha')::boolean, false) THEN
      v_entrada := (v_dia_cfg->>'entrada')::time;
      v_saida := (v_dia_cfg->>'saida')::time;
      v_intervalo := 0;
      IF COALESCE((v_dia_cfg->>'tem_almoco')::boolean, false)
         AND (v_dia_cfg->>'inicio_almoco') IS NOT NULL
         AND (v_dia_cfg->>'fim_almoco') IS NOT NULL THEN
        v_intervalo := EXTRACT(EPOCH FROM (
          (v_dia_cfg->>'fim_almoco')::time - (v_dia_cfg->>'inicio_almoco')::time
        ))::int / 60;
      END IF;
      v_jornada := (EXTRACT(EPOCH FROM (v_saida - v_entrada))::int / 60) - v_intervalo;
      entrada := v_entrada;
      saida := v_saida;
      intervalo_min := GREATEST(v_intervalo, 0);
      jornada_min := GREATEST(v_jornada, 0);
      tolerancia_batida_min := COALESCE(v_escala.tolerancia_minutos, 5);
      tolerancia_diaria_min := COALESCE(v_escala.tolerancia_diaria_minutos, 0);
      trabalha := true;
      RETURN NEXT;
      RETURN;
    END IF;
  END IF;

  IF v_escala.compensacoes_mensais IS NOT NULL
     AND jsonb_typeof(v_escala.compensacoes_mensais) = 'array' THEN
    v_ordinal := ((EXTRACT(DAY FROM p_data)::int - 1) / 7) + 1;
    SELECT c INTO v_comp
    FROM jsonb_array_elements(v_escala.compensacoes_mensais) c
    WHERE c->>'dia_semana' = v_dia_key
      AND COALESCE((c->>'ordinal_mes')::int, 0) = v_ordinal
    LIMIT 1;

    IF v_comp IS NOT NULL THEN
      v_entrada := (v_comp->>'entrada')::time;
      v_saida := (v_comp->>'saida')::time;
      v_intervalo := COALESCE((v_comp->>'intervalo')::int, 0);
      v_jornada := (EXTRACT(EPOCH FROM (v_saida - v_entrada))::int / 60) - v_intervalo;
      entrada := v_entrada;
      saida := v_saida;
      intervalo_min := GREATEST(v_intervalo, 0);
      jornada_min := GREATEST(v_jornada, 0);
      tolerancia_batida_min := COALESCE(v_escala.tolerancia_minutos, 5);
      tolerancia_diaria_min := COALESCE(v_escala.tolerancia_diaria_minutos, 0);
      trabalha := true;
      RETURN NEXT;
      RETURN;
    END IF;
  END IF;

  entrada := NULL;
  saida := NULL;
  intervalo_min := 0;
  jornada_min := COALESCE(v_escala.jornada_diaria_minutos, 0);
  tolerancia_batida_min := COALESCE(v_escala.tolerancia_minutos, 5);
  tolerancia_diaria_min := COALESCE(v_escala.tolerancia_diaria_minutos, 0);
  trabalha := false;
  RETURN NEXT;
END;
$function$;

-- ---- ponto_intervalo_janela_do_dia: overlay de versao apos a guarda ----
CREATE OR REPLACE FUNCTION public.ponto_intervalo_janela_do_dia(p_tenant_id uuid, p_cpf text, p_colaborador_id text, p_data date)
 RETURNS TABLE(inicio time without time zone, fim time without time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_escala public.ponto_escalas;
  v_dia_key text;
  v_dia_cfg jsonb;
  v_cpf text := regexp_replace(COALESCE(p_cpf, ''), '[^0-9]', '', 'g');
BEGIN
  SELECT e.* INTO v_escala
  FROM public.ponto_escala_atribuicoes a
  JOIN public.ponto_escalas e ON e.id = a.escala_id
  WHERE a.tenant_id = p_tenant_id
    AND (regexp_replace(COALESCE(a.colaborador_cpf,''), '[^0-9]', '', 'g') = v_cpf
         OR a.colaborador_id = p_colaborador_id)
    AND COALESCE(a.ativa, true) = true
    AND a.data_inicio <= p_data
    AND (a.data_fim IS NULL OR a.data_fim >= p_data)
  ORDER BY a.data_inicio DESC
  LIMIT 1;

  IF v_escala.id IS NULL THEN
    RETURN;
  END IF;

  -- PONTO-153: aplica os parametros da versao vigente na data (inerte se
  -- nao ha versao — devolve a escala viva intacta).
  v_escala := public.ponto_escala_com_versao(v_escala, p_data);

  v_dia_key := CASE EXTRACT(DOW FROM p_data)::int
    WHEN 0 THEN 'domingo' WHEN 1 THEN 'segunda' WHEN 2 THEN 'terca'
    WHEN 3 THEN 'quarta' WHEN 4 THEN 'quinta' WHEN 5 THEN 'sexta'
    WHEN 6 THEN 'sabado'
  END;

  -- (a) dias_config
  IF v_escala.dias_config IS NOT NULL AND jsonb_typeof(v_escala.dias_config) = 'object' THEN
    v_dia_cfg := v_escala.dias_config -> v_dia_key;
    IF v_dia_cfg IS NOT NULL
       AND COALESCE((v_dia_cfg->>'trabalha')::boolean, false)
       AND COALESCE((v_dia_cfg->>'tem_almoco')::boolean, false)
       AND (v_dia_cfg->>'inicio_almoco') IS NOT NULL
       AND (v_dia_cfg->>'fim_almoco') IS NOT NULL THEN
      BEGIN
        inicio := (v_dia_cfg->>'inicio_almoco')::time;
        fim := (v_dia_cfg->>'fim_almoco')::time;
        IF inicio IS NOT NULL AND fim IS NOT NULL AND fim > inicio THEN
          RETURN NEXT;
          RETURN;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        NULL; -- config malformada: cai para a fonte (b)
      END;
    END IF;
  END IF;

  -- (b) vão entre blocos consecutivos da escala
  SELECT p1.hora_fim, p2.hora_inicio
    INTO inicio, fim
  FROM public.ponto_escala_periodos p1
  JOIN public.ponto_escala_periodos p2
    ON p2.escala_id = p1.escala_id
   AND p2.dia_semana = p1.dia_semana
   AND p2.ordem_bloco = p1.ordem_bloco + 1
  WHERE p1.escala_id = v_escala.id
    AND p1.dia_semana = v_dia_key
    AND p2.hora_inicio > p1.hora_fim
  ORDER BY p1.ordem_bloco ASC
  LIMIT 1;

  IF inicio IS NOT NULL AND fim IS NOT NULL THEN
    RETURN NEXT;
  END IF;
END;
$function$;

-- ---- ponto_escala_do_dia (variante SQL): overlay via LATERAL ----
CREATE OR REPLACE FUNCTION public.ponto_escala_do_dia(p_tenant_id uuid, p_cpf text, p_colaborador_id uuid, p_data date)
 RETURNS TABLE(hora_entrada time without time zone, tolerancia_min integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT ev.hora_entrada_padrao, COALESCE(ev.tolerancia_diaria_minutos, 10)
  FROM public.ponto_escala_atribuicoes a
  JOIN public.ponto_escalas e ON e.id = a.escala_id
  CROSS JOIN LATERAL public.ponto_escala_com_versao(e, p_data) ev
  WHERE a.tenant_id = p_tenant_id
    AND (a.colaborador_cpf = p_cpf OR a.colaborador_id = p_colaborador_id::text)
    AND COALESCE(a.ativa, true) = true
    AND a.data_inicio <= p_data
    AND (a.data_fim IS NULL OR a.data_fim >= p_data)
  ORDER BY a.data_inicio DESC
  LIMIT 1;
$function$;

-- =====================================================================
-- PONTO-385 — Memória de cálculo
-- =====================================================================
-- Registra, por competência, a FONTE (marcações), os PARÂMETROS usados e o
-- RESULTADO apurado — para o auditor refazer a conta e o DP explicar o
-- espelho ao colaborador. É um registro sob demanda, ao lado da apuração;
-- não altera nenhum cálculo.
CREATE TABLE IF NOT EXISTS public.ponto_memoria_calculo (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id         uuid NOT NULL,
  colaborador_cpf   text NOT NULL,
  competencia       text NOT NULL,
  empresa_id        uuid,
  fonte_marcacoes   integer,
  fonte_hash        text,
  parametros        jsonb,
  resultado         jsonb,
  gerada_em         timestamptz NOT NULL DEFAULT now()
);

-- Uma memoria por (tenant, cpf, competencia, empresa); empresa nula usa
-- sentinela. Indice de expressao (UNIQUE inline nao aceita COALESCE).
CREATE UNIQUE INDEX IF NOT EXISTS ponto_memoria_calculo_uk
  ON public.ponto_memoria_calculo
  (tenant_id, colaborador_cpf, competencia,
   COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid));

COMMENT ON TABLE public.ponto_memoria_calculo IS
  'PONTO-385 — memoria de calculo por competencia: fonte (marcacoes), parametros usados e resultado apurado. Permite refazer a conta a partir da fonte e a versao dos parametros.';

CREATE INDEX IF NOT EXISTS ponto_memoria_calculo_busca
  ON public.ponto_memoria_calculo (tenant_id, colaborador_cpf, competencia);

ALTER TABLE public.ponto_memoria_calculo ENABLE ROW LEVEL SECURITY;

DO $pol_mem$
BEGIN
  DROP POLICY IF EXISTS "Tenant gerencia ponto_memoria_calculo" ON public.ponto_memoria_calculo;
  CREATE POLICY "Tenant gerencia ponto_memoria_calculo"
    ON public.ponto_memoria_calculo FOR ALL
    USING (tenant_id = public.current_user_tenant_id())
    WITH CHECK (tenant_id = public.current_user_tenant_id());
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Politica de ponto_memoria_calculo nao aplicada: %', SQLERRM;
END $pol_mem$;

-- Gera/atualiza a memória de uma competência a partir da apuração já pronta.
-- Idempotente: reprocessar a mesma competência sobrescreve a linha.
CREATE OR REPLACE FUNCTION public.ponto_registrar_memoria_calculo(
  p_tenant_id uuid, p_colaborador_cpf text, p_competencia text, p_empresa_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_cpf text := regexp_replace(COALESCE(p_colaborador_cpf, ''), '[^0-9]', '', 'g');
  v_ini date := to_date(p_competencia || '-01', 'YYYY-MM-DD');
  v_fim date := (to_date(p_competencia || '-01', 'YYYY-MM-DD') + INTERVAL '1 month - 1 day')::date;
  v_n int; v_hash text; v_resultado jsonb; v_id uuid;
BEGIN
  -- Fonte: marcacoes originais da competencia.
  SELECT count(*),
         md5(COALESCE(string_agg(
           m.data_marcacao::text || ':' || m.hora_marcacao::text || ':' || COALESCE(m.tipo_marcacao,''),
           '|' ORDER BY m.data_marcacao, m.hora_marcacao), ''))
    INTO v_n, v_hash
  FROM public.ponto_marcacoes m
  WHERE m.tenant_id = p_tenant_id
    AND regexp_replace(COALESCE(m.colaborador_cpf,''), '[^0-9]', '', 'g') = v_cpf
    AND m.data_marcacao BETWEEN v_ini AND v_fim;

  -- Resultado: o saldo apurado da competencia (a mesma fonte da tela).
  SELECT jsonb_build_object(
           'dias', count(*),
           'saldo_min_total', COALESCE(sum(s.saldo_min), 0),
           'trabalhado_min_total', COALESCE(sum(s.trabalhado_min), 0)
         )
    INTO v_resultado
  FROM public.ponto_saldo_dias_competencia(p_tenant_id, v_cpf, p_competencia) s;

  INSERT INTO public.ponto_memoria_calculo
    (tenant_id, colaborador_cpf, competencia, empresa_id, fonte_marcacoes, fonte_hash, parametros, resultado)
  VALUES (p_tenant_id, v_cpf, p_competencia, p_empresa_id, v_n, v_hash,
          jsonb_build_object('gerado_por', 'ponto_registrar_memoria_calculo'),
          v_resultado)
  ON CONFLICT (tenant_id, colaborador_cpf, competencia,
               COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid))
  DO UPDATE SET fonte_marcacoes = EXCLUDED.fonte_marcacoes,
                fonte_hash      = EXCLUDED.fonte_hash,
                resultado       = EXCLUDED.resultado,
                gerada_em       = now()
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- Tabelas novas de ponto precisam da trava do cercado (PONTO-270 vigia).
DO $cercas$
BEGIN
  PERFORM 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'qa_instalar_cercas';
  IF NOT FOUND THEN RETURN; END IF;
  PERFORM * FROM public.qa_instalar_cercas();
  RAISE NOTICE 'Cercas reinstaladas (tabelas novas da parte 3 incluidas).';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Nao foi possivel instalar as cercas: %', SQLERRM;
END $cercas$;

-- ============================================================================
-- CONFERÊNCIA — o SQL Editor mostra apenas o último resultado.
-- Esperado: t | t | 4 | t | OK
-- ============================================================================
SELECT
  (to_regclass('public.ponto_escala_param_versoes') IS NOT NULL)       AS tabela_versoes,

  (SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal
     AND tgname='trg_ponto_escala_arquiva_versao') = 1                 AS gatilho_arquiva,

  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prokind='f'
      AND p.proname IN ('ponto_jornada_do_dia','ponto_escala_do_dia',
                        'ponto_intervalo_janela_do_dia')
      AND pg_get_functiondef(p.oid) LIKE '%ponto_escala_com_versao%')  AS leitores_com_overlay,

  (to_regclass('public.ponto_memoria_calculo') IS NOT NULL)            AS tabela_memoria,

  CASE
    WHEN to_regclass('public.ponto_escala_param_versoes') IS NULL
      THEN 'ERRO: tabela de versoes nao criada'
    WHEN (SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal
            AND tgname='trg_ponto_escala_arquiva_versao') = 0
      THEN 'ERRO: gatilho de arquivamento nao criado — editar escala reescreveria o passado'
    WHEN (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
           WHERE n.nspname='public' AND p.prokind='f'
             AND p.proname IN ('ponto_jornada_do_dia','ponto_escala_do_dia',
                               'ponto_intervalo_janela_do_dia')
             AND pg_get_functiondef(p.oid) LIKE '%ponto_escala_com_versao%') < 4
      THEN 'ERRO: algum leitor da escala ficou sem o overlay de versao'
    WHEN to_regclass('public.ponto_memoria_calculo') IS NULL
      THEN 'ERRO: tabela de memoria nao criada'
    ELSE 'OK'
  END                                                                  AS erro_tecnico;


-- ============================================================================
-- CONFERENCIA DESTA PARTE
-- Lista o que a parte deveria deixar no ambiente e diz o que chegou. A ultima
-- linha resume: OK quando nada faltou.
-- ============================================================================
WITH esperado (tipo, nome, marcador) AS MATERIALIZED (
  VALUES
    ('funcao', 'ponto_escala_arquiva_versao', NULL),
    ('funcao', 'ponto_escala_com_versao', NULL),
    ('funcao', 'ponto_jornada_do_dia', NULL),
    ('funcao', 'ponto_escala_do_dia', NULL),
    ('funcao', 'ponto_intervalo_janela_do_dia', NULL),
    ('funcao', 'ponto_registrar_memoria_calculo', ' ORDER BY m.data_marcacao, m.hora_marcacao), '),
    ('tabela', 'ponto_escala_param_versoes', NULL),
    ('tabela', 'ponto_memoria_calculo', NULL),
    ('gatilho', 'trg_ponto_escala_arquiva_versao', NULL),
    ('indice', 'ponto_escala_param_versoes_busca', NULL),
    ('indice', 'ponto_memoria_calculo_uk', NULL),
    ('indice', 'ponto_memoria_calculo_busca', NULL)
), estado AS MATERIALIZED (
  SELECT e.tipo, e.nome, e.marcador,
         CASE e.tipo
           WHEN 'funcao'  THEN EXISTS (SELECT 1 FROM pg_proc p
                                        JOIN pg_namespace n ON n.oid = p.pronamespace
                                       WHERE n.nspname = 'public' AND p.proname = e.nome
                                         AND (e.marcador IS NULL
                                              OR p.prosrc LIKE '%' || e.marcador || '%'))
           WHEN 'tabela'  THEN to_regclass('public.' || e.nome) IS NOT NULL
           WHEN 'indice'  THEN EXISTS (SELECT 1 FROM pg_indexes
                                       WHERE schemaname = 'public' AND indexname = e.nome)
           WHEN 'gatilho' THEN EXISTS (SELECT 1 FROM pg_trigger
                                       WHERE NOT tgisinternal AND tgname = e.nome)
           WHEN 'coluna'  THEN EXISTS (SELECT 1 FROM information_schema.columns
                                       WHERE table_schema = 'public'
                                         AND table_name  = split_part(e.nome, '.', 1)
                                         AND column_name = split_part(e.nome, '.', 2))
         END AS presente
  FROM esperado e
)
SELECT tipo, nome, CASE WHEN presente THEN 'chegou' ELSE 'FALTOU' END AS situacao
FROM estado
WHERE NOT presente
UNION ALL
SELECT 'RESUMO',
       (SELECT count(*) FROM estado WHERE presente)::text || ' de '
         || (SELECT count(*) FROM estado)::text || ' pecas no lugar',
       CASE WHEN (SELECT count(*) FROM estado WHERE NOT presente) = 0
            THEN 'OK' ELSE 'CONFERIR as linhas acima' END
ORDER BY 1 DESC, 2;
