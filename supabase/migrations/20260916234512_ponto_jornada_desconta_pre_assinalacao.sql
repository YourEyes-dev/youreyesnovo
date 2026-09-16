-- =====================================================================
-- Jornada prevista desconta o intervalo PRE-ASSINALADO
--
-- ACHADO (relatorio de cartao-ponto de agosto/2026, cliente real): escala
-- das 08:00 as 17:00 com intervalo de 1h declarado por pre-assinalacao.
-- O cartao saiu assim, em quase todos os dias:
--
--   Marcacoes 08:00 17:00 | H.D. 8:00 | H.N. 9:00 | H.A. 1:00
--   Ocorrencia: "Atraso / saida antecipada"
--
-- H.D. (trabalhado) estava certo: 9h de janela menos 1h de intervalo. H.N.
-- (jornada prevista) vinha 9:00 — a janela CRUA, sem descontar o intervalo.
-- A diferenca virava 1 hora de ausencia por dia, e um dia integralmente
-- cumprido era rotulado como atraso. No mes fechado: 16:50 de ausencia
-- fantasma.
--
-- CAUSA: ponto_jornada_do_dia so descontava o intervalo quando o PROPRIO DIA
-- da escala trazia o trio tem_almoco + inicio_almoco + fim_almoco. Intervalo
-- declarado por pre-assinalacao nunca era lido — a tabela nasceu marcada como
-- "metadado de exibicao; o motor de saldo nao le". Ela ficou pela metade: o
-- cartao imprimia o "(P)" e a apuracao seguia ignorando a declaracao.
--
-- Isso tambem explica por que as sextas-feiras sairam certas (8:00) e o resto
-- da semana nao: aquele dia da escala tinha a janela de almoco preenchida, os
-- outros nao. A tela repara configuracoes antigas ao abrir a escala, mas so
-- grava se alguem salvar — por isso a correcao pertence ao motor.
--
-- O QUE MUDA: a jornada prevista passa a descontar o intervalo por uma cadeia
-- de precedencia — janela de almoco do dia, depois minutos de intervalo do
-- dia, depois pre-assinalacao vigente. Dia sem nenhuma das tres segue
-- exatamente como hoje.
--
-- NAO cai para ponto_escalas.intervalo_intrajornada_minutos de proposito: a
-- tela cria toda escala com esse campo em 60 por padrao, entao escala cuja
-- janela ja exclui o almoco (08:00-16:00) passaria a perder mais uma hora.
-- Descontar so o que foi DECLARADO evita trocar um erro por outro.
--
-- Sumula 338, III do TST; Portaria MTP 671/2021; CLT art. 71, §2.
-- =====================================================================

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

    -- O intervalo intrajornada NAO integra a jornada (CLT art. 71, §2). A
    -- janela do dia (saida - entrada) e tempo de permanencia; o que a
    -- transforma em JORNADA PREVISTA e o desconto do intervalo.
    --
    -- Ate aqui o desconto so acontecia quando O PROPRIO DIA trazia a janela
    -- de almoco. Escala cujo intervalo foi declarado por PRE-ASSINALACAO
    -- ficava com a jornada prevista inflada pelo tamanho do almoco — e cada
    -- dia integralmente cumprido virava uma ausencia de 1 hora, com a
    -- ocorrencia "Atraso / saida antecipada" num dia sem atraso nenhum.
    v_intervalo := NULL;

    -- (1) Janela de almoco declarada no proprio dia: a mais especifica.
    IF COALESCE((v_dia_cfg->>'tem_almoco')::boolean, false)
       AND (v_dia_cfg->>'inicio_almoco') IS NOT NULL
       AND (v_dia_cfg->>'fim_almoco') IS NOT NULL THEN
      v_intervalo := EXTRACT(EPOCH FROM (
        (v_dia_cfg->>'fim_almoco')::time - (v_dia_cfg->>'inicio_almoco')::time
      ))::int / 60;
    END IF;

    -- (2) Minutos de intervalo no proprio dia — o mesmo campo que o ramo de
    --     compensacoes mensais, logo abaixo, sempre respeitou.
    IF v_intervalo IS NULL AND NULLIF(v_dia_cfg->>'intervalo', '') IS NOT NULL THEN
      v_intervalo := (v_dia_cfg->>'intervalo')::int;
    END IF;

    -- (3) Pre-assinalacao vigente (Sumula 338, III do TST; Portaria MTP
    --     671/2021). Declarar o intervalo formalmente significa que ele
    --     existe e nao e batido: a janela do dia o contem, e a jornada
    --     prevista e a janela menos ele. A resolucao de precedencia
    --     (colaborador vence escala) ja vive na rotina propria.
    --
    --     NAO ha passo (4) caindo para ponto_escalas.intervalo_intrajornada_minutos
    --     de proposito: a tela cria toda escala com esse campo em 60 por
    --     padrao, entao uma escala cuja janela ja exclui o almoco (08:00-16:00)
    --     passaria a ser cortada em mais uma hora. Descontar so o que foi
    --     DECLARADO evita trocar um erro por outro.
    IF v_intervalo IS NULL THEN
      SELECT pa.intervalo_minutos INTO v_intervalo
      FROM public.ponto_pre_assinalacao_do_dia(
             p_tenant_id, p_cpf, p_colaborador_id, p_data) pa
      WHERE pa.aplica;
    END IF;

    v_jornada := v_jornada - COALESCE(v_intervalo, 0);
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

COMMENT ON FUNCTION public.ponto_jornada_do_dia(uuid, text, text, date) IS
  'Jornada prevista e tolerancia do dia, a partir da escala vigente (com a versao vigente na data). O intervalo intrajornada e descontado da janela por precedencia: janela de almoco do dia, minutos de intervalo do dia, pre-assinalacao vigente (Sumula 338, III do TST). Nao usa o intervalo generico da escala, que a tela preenche com 60 por padrao.';
