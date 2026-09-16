-- ============================================================================
-- ENTREGA — jornada prevista desconta o intervalo PRE-ASSINALADO
--
-- O ACHADO (cartao-ponto de agosto/2026): escala com 1h de intervalo declarado
-- por pre-assinalacao. O cartao saiu assim, quase todo dia:
--
--   Marcacoes 08:00 17:00 | H.D. 8:00 | H.N. 9:00 | H.A. 1:00
--   Ocorrencia: "Atraso / saida antecipada"
--
-- H.D. (o trabalhado) estava certo: a janela menos 1h de intervalo. H.N. (a
-- jornada PREVISTA) vinha com a janela crua, sem descontar o intervalo. A
-- diferenca virava uma hora de ausencia por dia, e um dia integralmente
-- cumprido era rotulado como atraso. No fechamento do mes: 16:50 de ausencia
-- que nunca existiu.
--
-- A CAUSA: ponto_jornada_do_dia so descontava o intervalo quando O PROPRIO DIA
-- da escala trazia o trio tem_almoco + inicio_almoco + fim_almoco. Intervalo
-- declarado por PRE-ASSINALACAO nunca era lido: a tabela nasceu marcada como
-- "metadado de exibicao; o motor de saldo nao le". Ficou pela metade — o
-- cartao imprimia o "(P)" e a apuracao seguia ignorando a declaracao.
--
-- E por isso as SEXTAS saiam certas e o resto da semana nao: naquele dia a
-- escala tinha a janela de almoco preenchida, nos outros nao. A tela repara
-- configuracoes antigas ao abrir a escala, mas so grava se alguem salvar —
-- por isso a correcao pertence ao motor, nao a tela.
--
-- O QUE MUDA: a jornada prevista passa a descontar o intervalo por precedencia
--   (1) janela de almoco declarada no proprio dia;
--   (2) minutos de intervalo no proprio dia;
--   (3) pre-assinalacao vigente (colaborador prevalece sobre escala).
-- Dia sem nenhuma das tres segue exatamente como hoje.
--
-- O QUE NAO MUDA, de proposito: nao ha passo (4) caindo para o intervalo
-- generico da escala (ponto_escalas.intervalo_intrajornada_minutos). A tela
-- cria toda escala com esse campo em 60 por padrao, entao uma escala cuja
-- janela ja exclui o almoco (08:00-16:00) passaria a perder mais uma hora.
-- Descontar so o que foi DECLARADO evita trocar um erro por outro.
--
-- PRE-REQUISITOS — ESTE ARQUIVO SE RECUSA A APLICAR SEM ELES.
-- O corpo novo chama duas rotinas que vieram em pacotes anteriores da fila:
--   · ponto_pre_assinalacao_do_dia  — pacote 18 (Onda 4 parte 3), que por sua
--     vez depende dos pacotes 16 e 17;
--   · ponto_escala_com_versao       — pacote da Onda 1 (PONTO-153).
-- O PostgreSQL NAO valida o corpo de uma funcao plpgsql na criacao: sem a
-- guarda abaixo, este arquivo instalaria com sucesso uma funcao que quebraria
-- na PRIMEIRA apuracao, derrubando o ponto de todos os clientes. Faltando
-- qualquer pre-requisito, a funcao ATUAL fica intacta e sai um aviso.
--
-- NAO altera nenhum dado: substitui UMA funcao de leitura. O relatorio le a
-- apuracao ao vivo, entao nao e preciso reprocessar competencia — basta gerar
-- o cartao de novo. Idempotente. Roda inteiro em UMA transacao.
-- Sumula 338, III do TST; Portaria MTP 671/2021; CLT art. 71, par. 2.
-- ============================================================================

SET lock_timeout = '10s';

DO $guarda$
DECLARE
  v_tem_declaracao boolean;
  v_tem_versao     boolean;
BEGIN
  v_tem_declaracao := to_regprocedure(
    'public.ponto_pre_assinalacao_do_dia(uuid,text,text,date)') IS NOT NULL;
  v_tem_versao := to_regprocedure(
    'public.ponto_escala_com_versao(public.ponto_escalas,date)') IS NOT NULL;

  IF NOT v_tem_declaracao OR NOT v_tem_versao THEN
    RAISE NOTICE 'PULADO — este ambiente ainda nao tem os pre-requisitos. ponto_pre_assinalacao_do_dia: %; ponto_escala_com_versao: %. Aplique antes os pacotes da fila do Ponto (16, 17 e 18 para a pre-assinalacao; Onda 1 para a versao da escala). A funcao atual NAO foi tocada.',
      v_tem_declaracao, v_tem_versao;
    RETURN;
  END IF;

  EXECUTE $def$
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

      -- O intervalo intrajornada NAO integra a jornada (CLT art. 71, par. 2).
      -- A janela do dia (saida - entrada) e tempo de permanencia; o que a
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
      --     NAO ha passo (4) caindo para o intervalo generico da escala, de
      --     proposito: a tela cria toda escala com aquele campo em 60 por
      --     padrao, entao uma escala cuja janela ja exclui o almoco
      --     (08:00-16:00) passaria a ser cortada em mais uma hora. Descontar
      --     so o que foi DECLARADO evita trocar um erro por outro.
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
      -- e a ultima ocorrencia deste dia da semana no mes?
      v_is_ultimo := (p_data + 7) > (date_trunc('month', p_data) + interval '1 month - 1 day')::date;

      -- ordinal_mes pode vir como numero ('1'..'5'), 'ultimo'/'ultimo',
      -- 'todos'/'todas'/vazio (qualquer ocorrencia). Comparacao textual evita
      -- o erro de cast que derrubava toda a apuracao do dia.
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
  $def$;

  EXECUTE $doc$
  COMMENT ON FUNCTION public.ponto_jornada_do_dia(uuid, text, text, date) IS
    'Jornada prevista e tolerancia do dia, a partir da escala vigente (com a versao vigente na data). O intervalo intrajornada e descontado da janela por precedencia: janela de almoco do dia, minutos de intervalo do dia, pre-assinalacao vigente (Sumula 338, III do TST). Nao usa o intervalo generico da escala, que a tela preenche com 60 por padrao.'
  $doc$;

  RAISE NOTICE 'OK — a jornada prevista passa a descontar o intervalo declarado.';
END $guarda$;

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | t | OK
--   pre_requisitos_ok : o ambiente tem as duas rotinas de que o corpo depende
--   funcao_ok         : ponto_jornada_do_dia existe
--   le_declaracao     : o corpo consulta a pre-assinalacao vigente
--
-- Se sair f | t | f | PRE-REQUISITO FALTANDO, o arquivo se recusou de
-- proposito e NADA foi alterado: a fila do Ponto ainda nao chegou aqui.
--
-- As duas colunas seguintes sao INFORMATIVAS, nao reprovam: dizem o alcance da
-- correcao — quantas declaracoes estao vigentes hoje e quantos vinculos de
-- escala passam a ter a jornada prevista descontada do intervalo declarado.
-- ---------------------------------------------------------------------------
WITH x AS MATERIALIZED (
  SELECT
    (to_regprocedure('public.ponto_pre_assinalacao_do_dia(uuid,text,text,date)') IS NOT NULL
     AND to_regprocedure('public.ponto_escala_com_versao(public.ponto_escalas,date)') IS NOT NULL)
       AS pre_requisitos_ok,
    (to_regprocedure('public.ponto_jornada_do_dia(uuid,text,text,date)') IS NOT NULL) AS funcao_ok,
    EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public' AND p.proname = 'ponto_jornada_do_dia'
               AND p.prosrc LIKE '%ponto_pre_assinalacao_do_dia%') AS le_declaracao,
    (SELECT count(*) FROM public.ponto_pre_assinalacao
      WHERE COALESCE(ativa, true) = true
        AND data_inicio <= CURRENT_DATE
        AND (data_fim IS NULL OR data_fim >= CURRENT_DATE)) AS declaracoes_vigentes,
    (SELECT count(DISTINCT a.id)
       FROM public.ponto_escala_atribuicoes a
       JOIN public.ponto_pre_assinalacao pa
         ON pa.tenant_id = a.tenant_id
        AND COALESCE(pa.ativa, true) = true
        AND pa.data_inicio <= CURRENT_DATE
        AND (pa.data_fim IS NULL OR pa.data_fim >= CURRENT_DATE)
        AND (
          pa.escala_id = a.escala_id
          OR (pa.colaborador_cpf IS NOT NULL
              AND regexp_replace(pa.colaborador_cpf, '[^0-9]', '', 'g')
                = regexp_replace(COALESCE(a.colaborador_cpf, ''), '[^0-9]', '', 'g'))
        )
      WHERE COALESCE(a.ativa, true) = true
        AND a.data_inicio <= CURRENT_DATE
        AND (a.data_fim IS NULL OR a.data_fim >= CURRENT_DATE)) AS vinculos_alcancados
)
SELECT pre_requisitos_ok, funcao_ok, le_declaracao,
       declaracoes_vigentes, vinculos_alcancados,
       CASE
         WHEN NOT pre_requisitos_ok THEN 'PRE-REQUISITO FALTANDO — nada foi alterado'
         WHEN funcao_ok AND le_declaracao THEN 'OK'
         ELSE 'CONFERIR'
       END AS erro_tecnico
FROM x;
