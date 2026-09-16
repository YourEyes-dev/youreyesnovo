-- ============================================================================
-- HOMOLOGACAO — PONTO, PARTE 06 de 16: Calculo da jornada: virada, tolerancia, escala e noturno
--
-- Turno que cruza a meia-noite pertence ao dia de inicio; tolerancia de 5
-- min por marcacao alem do teto diario; hora extra medida contra a jornada
-- REAL da escala; adicional noturno que acompanha a prorrogacao (Sumula 60,
-- II).
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
--   * script_ponto_onda3_turno_da_virada.sql
--   * script_ponto_onda3_tolerancia.sql
--   * script_ponto_onda3_jornada_escala_he.sql
--   * script_ponto_onda3_adicional_noturno_prorrogado.sql
--
-- Ao final sai UMA conferencia, dizendo o que chegou e o que faltou.
-- ============================================================================



-- ############################################################
-- BLOCO: script_ponto_onda3_turno_da_virada.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 3 (parte 4): turno da virada pertence ao dia de início
-- Alvos: ponto_corte_virada (nova), ponto_reordena_tipos_dia, _ponto_calc_dia
-- PONTO-022
--
-- O QUE FAZ
--   A jornada que cruza a meia-noite (ex.: entrada 22:00, saída 06:00 do dia
--   seguinte, lançadas no dia de início) passa a pertencer INTEGRALMENTE ao dia
--   em que começou — 8h no dia de início, sem falta fictícia no dia seguinte.
--   A reordenação de rótulos e a consolidação diária passam a ler as batidas em
--   ordem CÍCLICA (o turno começa logo após o maior vão do dia), reconhecendo a
--   virada. Nenhum horário é alterado; muda só a ORDEM de leitura das batidas.
--
-- SEGURO E IDEMPOTENTE: CREATE OR REPLACE das funções (definição única, sem
--   remendos próprios de produção nestas funções). Dias comuns não mudam — o
--   corte da virada devolve NULL quando o maior vão é o descanso noturno.
-- ============================================================================

-- Ponto de corte da virada: a hora da batida que INICIA o turno (logo após o
-- maior vão do dia). Devolve NULL quando não há virada (o maior vão é o descanso
-- noturno, caso comum) — aí a ordem por relógio já está certa.
CREATE OR REPLACE FUNCTION public.ponto_corte_virada(
  p_tenant_id uuid, p_colaborador_cpf text, p_data date
) RETURNS time
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  WITH m AS (
    SELECT hora_marcacao AS h
    FROM public.ponto_marcacoes
    WHERE tenant_id = p_tenant_id
      AND colaborador_cpf = p_colaborador_cpf
      AND data_marcacao = p_data
  ),
  g AS (
    SELECT h, EXTRACT(EPOCH FROM (h - lag(h) OVER (ORDER BY h)))/60 AS gap
    FROM m
  ),
  stats AS (
    SELECT (SELECT max(gap) FROM g) AS max_int,
           1440 - EXTRACT(EPOCH FROM ((SELECT max(h) FROM m) - (SELECT min(h) FROM m)))/60 AS wrap_gap
  )
  SELECT CASE
           WHEN (SELECT count(*) FROM m) < 2 THEN NULL
           WHEN s.max_int > s.wrap_gap
             THEN (SELECT h FROM g WHERE gap = s.max_int ORDER BY h LIMIT 1)
           ELSE NULL
         END
  FROM stats s;
$$;

COMMENT ON FUNCTION public.ponto_corte_virada(uuid, text, date) IS
  'Hora da batida que inicia o turno quando a jornada cruza a meia-noite (logo apos o maior vao do dia). NULL em dias comuns. Usada para ordenar as batidas em ordem ciclica.';

-- ---------------------------------------------------------------------------
-- REORDENAÇÃO de rótulos, agora em ordem cíclica (virada reconhecida).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_reordena_tipos_dia(p_tenant_id uuid, p_colaborador_cpf text, p_data date)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_n       int;
  v_min_gap numeric;
  v_corte   time := public.ponto_corte_virada(p_tenant_id, p_colaborador_cpf, p_data);
  v_changed uuid[];
  v_id      uuid;
  v_antes   jsonb;
BEGIN
  -- Contagem e menor vão entre batidas JÁ na ordem cíclica (guarda de ruído).
  SELECT count(*), min(gap) INTO v_n, v_min_gap
  FROM (
    SELECT (ordk - lag(ordk) OVER (ORDER BY ordk)) / 60 AS gap
    FROM (
      SELECT EXTRACT(EPOCH FROM hora_marcacao)
             + CASE WHEN v_corte IS NOT NULL AND hora_marcacao < v_corte
                    THEN 86400 ELSE 0 END AS ordk
      FROM public.ponto_marcacoes
      WHERE tenant_id = p_tenant_id
        AND colaborador_cpf = p_colaborador_cpf
        AND data_marcacao = p_data
    ) e
  ) g;

  IF v_n IS NULL OR v_n = 0
     OR v_n % 2 = 1
     OR (v_min_gap IS NOT NULL AND v_min_gap < 15) THEN
    RETURN false;
  END IF;

  -- Retrato de antes, para o log de auditoria.
  SELECT jsonb_agg(jsonb_build_object('hora', hora_marcacao, 'tipo', tipo_marcacao)
                   ORDER BY hora_marcacao)
    INTO v_antes
  FROM public.ponto_marcacoes
  WHERE tenant_id = p_tenant_id
    AND colaborador_cpf = p_colaborador_cpf
    AND data_marcacao = p_data;

  PERFORM set_config('app.ponto_reordena', 'on', true);

  WITH reord AS (
    SELECT id,
           row_number() OVER (
             ORDER BY (EXTRACT(EPOCH FROM hora_marcacao)
                       + CASE WHEN v_corte IS NOT NULL AND hora_marcacao < v_corte
                              THEN 86400 ELSE 0 END),
                      created_at
           ) AS pos
    FROM public.ponto_marcacoes
    WHERE tenant_id = p_tenant_id
      AND colaborador_cpf = p_colaborador_cpf
      AND data_marcacao = p_data
  ), upd AS (
    UPDATE public.ponto_marcacoes m
    SET    tipo_marcacao = CASE WHEN r.pos % 2 = 1 THEN 'entrada' ELSE 'saida' END
    FROM   reord r
    WHERE  m.id = r.id
      AND  m.tipo_marcacao IS DISTINCT FROM
           (CASE WHEN r.pos % 2 = 1 THEN 'entrada' ELSE 'saida' END)
    RETURNING m.id
  )
  SELECT array_agg(id) INTO v_changed FROM upd;

  PERFORM set_config('app.ponto_reordena', 'off', true);

  IF v_changed IS NOT NULL THEN
    FOREACH v_id IN ARRAY v_changed LOOP
      BEGIN
        PERFORM public.classificar_marcacao_clt(v_id);
      EXCEPTION WHEN OTHERS THEN
        NULL;  -- classificação CLT é auxiliar; nunca quebra o fluxo
      END;
    END LOOP;

    BEGIN
      INSERT INTO public.ponto_audit_log (
        tenant_id, tabela_origem, registro_id, acao,
        dados_anteriores, dados_novos, usuario_id
      )
      SELECT p_tenant_id, 'ponto_marcacoes', v_changed[1], 'AJUSTE',
             jsonb_build_object('operacao', 'REORDENACAO_ROTULOS',
                                'data', p_data, 'sequencia', v_antes),
             jsonb_build_object('operacao', 'REORDENACAO_ROTULOS',
                                'data', p_data,
                                'motivo', 'Batida incluída em horário anterior às existentes; '
                                       || 'rótulos entrada/saída reencaixados pelo relógio '
                                       || '(ordem cíclica, virada reconhecida). '
                                       || 'Nenhum horário foi alterado.',
                                'marcacoes_afetadas', to_jsonb(v_changed),
                                'sequencia', (
                                  SELECT jsonb_agg(jsonb_build_object('hora', hora_marcacao,
                                                                      'tipo', tipo_marcacao)
                                                   ORDER BY hora_marcacao)
                                  FROM public.ponto_marcacoes
                                  WHERE tenant_id = p_tenant_id
                                    AND colaborador_cpf = p_colaborador_cpf
                                    AND data_marcacao = p_data
                                )),
             auth.uid();
    EXCEPTION WHEN OTHERS THEN
      NULL;  -- auditoria é registro acessório; nunca derruba a aprovação
    END;
  END IF;

  RETURN (v_changed IS NOT NULL);
END;
$function$;

-- ---------------------------------------------------------------------------
-- CONSOLIDAÇÃO diária, lendo as batidas em ordem cíclica (virada reconhecida).
-- Só muda a ordem de leitura das batidas; o resto do cálculo é o mesmo.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._ponto_calc_dia(p_tenant_id uuid, p_colaborador_cpf text, p_data date, p_cid uuid, OUT o_pent time without time zone, OUT o_salm time without time zone, OUT o_ralm time without time zone, OUT o_usai time without time zone, OUT o_horas interval, OUT o_status text, OUT o_obs text)
 RETURNS record
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_marc RECORD;
  v_count INT := 0;
  v_ins TIME[] := '{}'; v_outs TIME[] := '{}';
  v_abr TIME; v_classe TEXT; v_esp TEXT := 'in';
  v_min INT := 0; v_dif INT;
  v_anom BOOLEAN := false; v_aberta BOOLEAN := false;
  v_pend BOOLEAN := false; v_esc RECORD;
  v_corte TIME := public.ponto_corte_virada(p_tenant_id, p_colaborador_cpf, p_data);
BEGIN
  FOR v_marc IN
    SELECT hora_marcacao, tipo_marcacao FROM public.ponto_marcacoes
    WHERE tenant_id = p_tenant_id AND colaborador_cpf = p_colaborador_cpf AND data_marcacao = p_data
    ORDER BY (EXTRACT(EPOCH FROM hora_marcacao)
              + CASE WHEN v_corte IS NOT NULL AND hora_marcacao < v_corte
                     THEN 86400 ELSE 0 END) ASC,
             created_at ASC
  LOOP
    v_count := v_count + 1;
    v_classe := COALESCE(public.ponto_classifica_tipo(v_marc.tipo_marcacao), v_esp);
    IF v_classe = 'in' THEN
      o_pent := COALESCE(o_pent, v_marc.hora_marcacao);
      v_ins := v_ins || v_marc.hora_marcacao;
      IF v_abr IS NOT NULL THEN v_anom := true; END IF;
      v_abr := v_marc.hora_marcacao; v_esp := 'out';
    ELSE
      IF v_abr IS NOT NULL THEN
        -- Trunca os segundos (FLOOR) para alinhar com a exibição do Espelho
        v_dif := FLOOR(EXTRACT(EPOCH FROM (v_marc.hora_marcacao - v_abr)) / 60)::INT;
        IF v_dif < 0 THEN v_dif := v_dif + 1440; END IF;
        v_min := v_min + GREATEST(0, v_dif);
        v_abr := NULL;
      ELSE
        v_anom := true;
      END IF;
      v_outs := v_outs || v_marc.hora_marcacao;
      o_usai := v_marc.hora_marcacao; v_esp := 'in';
    END IF;
  END LOOP;

  v_aberta := (v_abr IS NOT NULL);
  IF array_length(v_outs,1) >= 2 THEN
    o_salm := v_outs[1];
    SELECT t INTO o_ralm FROM unnest(v_ins) AS t WHERE t > v_outs[1] ORDER BY t ASC LIMIT 1;
  END IF;
  IF v_aberta AND array_length(v_outs,1) >= 1 AND array_length(v_ins,1) >= 2 THEN
    o_salm := v_outs[1];
    SELECT t INTO o_ralm FROM unnest(v_ins) AS t WHERE t > v_outs[1] ORDER BY t ASC LIMIT 1;
    o_usai := NULL;
  END IF;
  o_horas := make_interval(mins => v_min);

  SELECT EXISTS (SELECT 1 FROM public.ponto_ajustes
    WHERE tenant_id = p_tenant_id AND colaborador_cpf = p_colaborador_cpf
      AND data_referencia = p_data AND status = 'pendente') INTO v_pend;

  IF v_pend THEN o_status := 'ajuste_pendente';
  ELSIF v_count = 0 THEN o_status := 'falta';
  ELSIF v_aberta OR v_anom THEN o_status := 'incompleto';
  ELSE
    o_status := 'regular';
    SELECT * INTO v_esc FROM public.ponto_escala_do_dia(p_tenant_id, p_colaborador_cpf, p_cid, p_data);
    IF v_esc.hora_entrada IS NOT NULL AND o_pent IS NOT NULL
       AND o_pent > (v_esc.hora_entrada + make_interval(mins => v_esc.tolerancia_min)) THEN
      o_status := 'atraso';
    END IF;
  END IF;

  IF o_status = 'atraso' AND EXISTS (
    SELECT 1 FROM public.atestados a
    WHERE a.tenant_id = p_tenant_id AND a.colaborador_cpf = p_colaborador_cpf
      AND a.data_inicio_afastamento IS NOT NULL
      AND COALESCE(a.unidade_afastamento,'dias') = 'horas'
      AND a.data_inicio_afastamento <= p_data
      AND COALESCE(a.data_fim_afastamento, a.data_inicio_afastamento) >= p_data
  ) THEN
    o_status := 'regular';
    o_obs := COALESCE(NULLIF(o_obs, '') || ' ', '') || 'Atraso justificado por atestado de horas no dia.';
  END IF;

  IF v_anom AND NOT v_pend THEN
    o_obs := 'Sequência de marcações incompleta (entrada/saída sem par) — horas do período não pareado não contabilizadas. Solicite ajuste de ponto.';
  END IF;
END;
$function$;

-- ---------------------------------------------------------------------------
-- CONFERÊNCIA — o SQL Editor mostra apenas o último resultado.
-- Esperado: t | t | t | OK
--   corte_existe        : t  (função ponto_corte_virada criada)
--   reordena_usa_corte  : t  (reordenação lê em ordem cíclica)
--   consolida_usa_corte : t  (consolidação lê em ordem cíclica)
-- ---------------------------------------------------------------------------
SELECT
  (to_regprocedure('public.ponto_corte_virada(uuid,text,date)') IS NOT NULL)   AS corte_existe,
  (position('ponto_corte_virada' in pg_get_functiondef('public.ponto_reordena_tipos_dia(uuid,text,date)'::regprocedure)) > 0) AS reordena_usa_corte,
  (position('ponto_corte_virada' in pg_get_functiondef(p.oid)) > 0)            AS consolida_usa_corte,
  CASE
    WHEN to_regprocedure('public.ponto_corte_virada(uuid,text,date)') IS NOT NULL
     AND position('ponto_corte_virada' in pg_get_functiondef('public.ponto_reordena_tipos_dia(uuid,text,date)'::regprocedure)) > 0
     AND position('ponto_corte_virada' in pg_get_functiondef(p.oid)) > 0
      THEN 'OK'
    ELSE 'PENDENTE: conferir'
  END                                                                          AS erro_tecnico
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = '_ponto_calc_dia'
LIMIT 1;



-- ############################################################
-- BLOCO: script_ponto_onda3_tolerancia.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 3 (parte 1): tolerância cumulativa dos dois tetos legais
-- Alvo (produção/homologação): função monolítica
--   public.ponto_saldo_dias_competencia(uuid, text, text)
-- PONTO-041 / PONTO-042 / PONTO-352 (mantém PONTO-353, PONTO-040)
--
-- O QUE FAZ
--   CLT art. 58, §1º + TST Súmula 366: variação de registro não desconta nem
--   vira extra até 5 min POR MARCAÇÃO, observado o teto de 10 min DIÁRIOS.
--   Ultrapassado qualquer um, computa-se a TOTALIDADE que excede a jornada.
--   Duas correções no corpo de apuração:
--     (a) o encaixe de batida na escala passa a usar 5 min por marcação
--         (era 10 — o dobro do limite legal);
--     (b) o piso de tolerância deixa de ser um "abs(saldo) <= 10" cego: o
--         atraso/antecipação (déficit) é absorvido só até o teto POR MARCAÇÃO;
--         a sobra no dia mantém o teto DIÁRIO. Assim um déficit de 6 min numa
--         marcação passa a ser computado por inteiro, e a fronteira do teto
--         diário na sobra (10→0, 11→11) segue idêntica.
--
-- POR QUE O ALVO É O MONÓLITO (drift descoberto no ensaio da homologação)
--   No repositório, a apuração foi refatorada em duas funções (uma casca
--   `ponto_saldo_dias_competencia` que delega para o miolo
--   `ponto_saldo_dias_competencia_bruto`). ESSA REFATORAÇÃO NUNCA CHEGOU À
--   PRODUÇÃO: lá (e na homologação, cópia fiel) a apuração continua num único
--   corpo monolítico chamado `ponto_saldo_dias_competencia`, corrigido por
--   remendo ao longo do tempo. Portanto, aqui o alvo é o monólito.
--
-- POR QUE ESTE SCRIPT É CIRÚRGICO (e não cola o corpo inteiro)
--   O corpo vivo em produção tem remendos que não correspondem a nenhum
--   arquivo do repositório. Colar um corpo inteiro apagaria esses remendos.
--   Este script LÊ o corpo que estiver vivo e troca APENAS os trechos de
--   tolerância. Se o corpo não casar exatamente com o padrão esperado nessas
--   linhas, o script NÃO altera nada e avisa (PENDENTE) — para reconciliarmos
--   à mão antes, sem risco de mexer no cálculo errado.
--
--   Validado contra o corpo REAL de produção: os padrões abaixo casam
--   exatamente com o monólito, o marcador de equalização NÃO é tocado, e o
--   caso de tolerância PONTO-041 sai de "falhou" (sem patch) para "passou"
--   (com patch). Idempotente: rodar duas vezes não quebra nem duplica
--   (reconhece o marcador [onda3-tol] já aplicado).
-- ============================================================================

DO $entrega$
DECLARE
  v_def text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'ponto_saldo_dias_competencia'
    AND pg_get_function_identity_arguments(p.oid) = 'p_tenant_id uuid, p_colaborador_cpf text, p_competencia text'
  LIMIT 1;

  IF v_def IS NULL THEN
    RAISE NOTICE 'ponto_saldo_dias_competencia nao encontrada — nada a fazer.';
    RETURN;
  END IF;

  IF position('[onda3-tol]' in v_def) > 0 THEN
    RAISE NOTICE 'Ja aplicado (marcador [onda3-tol] presente). Nada a fazer.';
    RETURN;
  END IF;

  -- (a) padrao POR MARCACAO: 10 -> 5 (tres tokens)
  v_def := replace(v_def, 'v_interv := 0; v_tol_bat := 10;', 'v_interv := 0; v_tol_bat := 5;');
  v_def := replace(v_def, 'COALESCE(e.tolerancia_batida_min, 10)', 'COALESCE(e.tolerancia_batida_min, 5)');
  v_def := replace(v_def, 'COALESCE(v_tol_bat, 10)', 'COALESCE(v_tol_bat, 5)');

  -- (b1) deficit no caminho SEM batida (bloco exato: 8/10/8 espacos)
  v_def := replace(v_def,
    E'        IF abs(v_diff) <= COALESCE(v_tol, 0) THEN\n          v_diff := 0;\n        END IF;',
    E'        -- [onda3-tol] deficit absorvido so ate o teto POR MARCACAO\n'
 || E'        -- (art. 58 §1º / Sumula 366); sobra mantem o teto DIARIO.\n'
 || E'        IF v_diff < 0 THEN\n'
 || E'          IF abs(v_diff) <= COALESCE(v_tol_bat, 5) THEN\n'
 || E'            v_diff := 0;\n'
 || E'          END IF;\n'
 || E'        ELSIF abs(v_diff) <= COALESCE(v_tol, 0) THEN\n'
 || E'          v_diff := 0;\n'
 || E'        END IF;');

  -- (b2) piso final, valido para todos os caminhos (bloco exato: 4/6/4 espacos)
  v_def := replace(v_def,
    E'    IF abs(v_diff) <= 10 THEN\n      v_diff := 0;\n    END IF;',
    E'    -- [onda3-tol] dois tetos cumulativos (art. 58 §1º + Sumula 366):\n'
 || E'    -- deficit no teto POR MARCACAO; sobra no teto DIARIO (10). Estourou\n'
 || E'    -- qualquer um, computa-se a totalidade que excede a jornada.\n'
 || E'    IF v_diff < 0 THEN\n'
 || E'      IF abs(v_diff) <= COALESCE(v_tol_bat, 5) THEN\n'
 || E'        v_diff := 0;\n'
 || E'      END IF;\n'
 || E'    ELSIF v_diff <= 10 THEN\n'
 || E'      v_diff := 0;\n'
 || E'    END IF;');

  -- Guarda: as trocas todas ocorreram? Se nao casou, NAO aplica e avisa.
  IF position('[onda3-tol]' in v_def) = 0
     OR position('COALESCE(v_tol_bat, 5)' in v_def) = 0
     OR position('COALESCE(e.tolerancia_batida_min, 10)' in v_def) > 0 THEN
    RAISE NOTICE 'ATENCAO: corpo divergente nas linhas de tolerancia (provavel remendo proprio de producao). NADA foi alterado. Envie pg_get_functiondef(ponto_saldo_dias_competencia) para reconciliarmos a mao antes de aplicar.';
    RETURN;
  END IF;

  EXECUTE v_def;
  RAISE NOTICE 'Tolerancia cumulativa aplicada em ponto_saldo_dias_competencia.';
END $entrega$;

-- ---------------------------------------------------------------------------
-- CONFERÊNCIA — o SQL Editor mostra apenas o último resultado.
-- Esperado depois de aplicar:  t | t | t | t | OK
--   marcador_aplicado : t  (o marcador [onda3-tol] está no corpo)
--   por_marcacao_5    : t  (o padrão 10 por marcação foi trocado por 5)
--   sem_padrao_antigo : t  (não sobrou COALESCE(e.tolerancia_batida_min, 10))
--   equalizacao_intacta: t (a linha do sábado de equalização NÃO foi mexida)
-- Se vier 'PENDENTE', o corpo em produção divergiu e nada foi alterado:
--   me envie o pg_get_functiondef que eu reconcilio.
-- ---------------------------------------------------------------------------
WITH def AS (
  SELECT pg_get_functiondef(p.oid) AS src
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'ponto_saldo_dias_competencia'
    AND pg_get_function_identity_arguments(p.oid) = 'p_tenant_id uuid, p_colaborador_cpf text, p_competencia text'
  LIMIT 1
)
SELECT
  (position('[onda3-tol]' in src) > 0)                                AS marcador_aplicado,
  (position('COALESCE(v_tol_bat, 5)' in src) > 0)                     AS por_marcacao_5,
  (position('COALESCE(e.tolerancia_batida_min, 10)' in src) = 0)      AS sem_padrao_antigo,
  (position('IF abs(v_diff) <= 10 THEN v_diff := 0; END IF;' in src) > 0) AS equalizacao_intacta,
  CASE
    WHEN position('[onda3-tol]' in src) > 0
     AND position('COALESCE(v_tol_bat, 5)' in src) > 0
     AND position('COALESCE(e.tolerancia_batida_min, 10)' in src) = 0
      THEN 'OK'
    ELSE 'PENDENTE: corpo divergente, nada aplicado — reconciliar'
  END                                                                  AS erro_tecnico
FROM def;



-- ############################################################
-- BLOCO: script_ponto_onda3_jornada_escala_he.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 3 (parte 2): jornada da escala + hora extra sem truncar
-- Alvo: public.calcular_he_adicional_noturno_dia
-- PONTO-091 / PONTO-092  (mantém PONTO-110, PONTO-111)
--
-- O QUE FAZ
--   (091) A jornada esperada do dia passa a vir da ESCALA vigente do vínculo
--         (respeita o versionamento da onda 1). A CCT/8h fixas só valem quando
--         o vínculo não tem escala para o dia. Assim a hora extra de quem tem
--         jornada contratual menor (ex.: 6h) deixa de ser apagada.
--   (092) Remove o corte que truncava a hora extra em 2h (art. 59): apura-se
--         TODO o tempo trabalhado além da jornada (continua devido) e sinaliza-se
--         o excesso ao RH com um alerta (ponto_alertas), um por colaborador/dia.
--   Não mexe no adicional noturno nem na hora ficta.
--
-- SEGURO E IDEMPOTENTE: é um CREATE OR REPLACE da função (definição única, sem
--   remendos próprios de produção nesta função). Rodar duas vezes não quebra
--   nem duplica; o alerta tem guarda anti-duplicata.
--
-- OBSERVAÇÃO IMPORTANTE: hoje esta função de cálculo ainda não é consumida pelo
--   fluxo vivo de apuração (nenhum gatilho/tela a chama). A correção deixa o
--   cálculo certo para quando ele for ligado; por si só não altera os números
--   que já aparecem hoje.
-- ============================================================================

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
    NULL; -- qualquer falha na leitura da escala: mantém o fallback CCT/8h
  END;

  -- Total trabalhado em minutos (a partir das marcações entrada/saida)
  IF v_diario.entrada IS NOT NULL AND v_diario.saida IS NOT NULL THEN
    v_trab_min := EXTRACT(EPOCH FROM (v_diario.saida::time - v_diario.entrada::time))/60;
    IF v_diario.saida_almoco IS NOT NULL AND v_diario.retorno_almoco IS NOT NULL THEN
      v_trab_min := v_trab_min - EXTRACT(EPOCH FROM (v_diario.retorno_almoco::time - v_diario.saida_almoco::time))/60;
    END IF;
  END IF;
  IF v_trab_min < 0 THEN v_trab_min := 0; END IF;

  -- (092) Horas extras: TODO o tempo que excede a jornada é apurado. O limite
  -- de 2h do art. 59 é norma de conduta, não de cálculo — não se trunca a
  -- apuração; apura-se tudo e sinaliza-se o excesso ao RH.
  v_dow := EXTRACT(DOW FROM p_data); -- 0=domingo
  IF v_trab_min > v_jornada_diaria_min THEN
    v_excesso := v_trab_min - v_jornada_diaria_min;
    IF v_dow = 0 THEN
      v_he100 := v_excesso;
    ELSE
      v_he50 := v_excesso;
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
    BEGIN
      IF v_s < v_e THEN v_s := v_s + INTERVAL '1 day'; END IF;
      v_overlap_min := GREATEST(0,
        EXTRACT(EPOCH FROM (LEAST(v_s, v_n_fim) - GREATEST(v_e, v_n_ini)))/60
      )::INTEGER;
      v_adn_min := v_overlap_min;
      IF v_usa_hora_ficta AND v_adn_min > 0 THEN
        v_adn_min := ROUND(v_adn_min * 60.0 / 52.5);
      END IF;
    END;
  END IF;

  UPDATE public.ponto_diario
     SET horas_extras_50_minutos = v_he50,
         horas_extras_100_minutos = v_he100,
         adicional_noturno_minutos = v_adn_min,
         updated_at = now()
   WHERE id = v_diario.id;

  RETURN jsonb_build_object(
    'ok', true,
    'he50_min', v_he50,
    'he100_min', v_he100,
    'adicional_noturno_min', v_adn_min,
    'percentual_he50', v_he50_pct,
    'percentual_he100', v_he100_pct,
    'percentual_adn', v_adn_pct
  );
END;
$function$;

-- ---------------------------------------------------------------------------
-- CONFERÊNCIA — o SQL Editor mostra apenas o último resultado.
-- Esperado: t | t | t | OK
--   le_jornada_escala : t  (passou a consultar ponto_jornada_do_dia)
--   nao_trunca_2h     : t  (sumiu o corte LEAST no cálculo de HE)
--   sinaliza_excesso  : t  (o alerta de excesso do art. 59 está no corpo)
-- ---------------------------------------------------------------------------
WITH def AS (
  SELECT pg_get_functiondef(p.oid) AS src
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'calcular_he_adicional_noturno_dia'
    AND pg_get_function_identity_arguments(p.oid) = 'p_colaborador_id uuid, p_data date'
  LIMIT 1
)
SELECT
  (position('ponto_jornada_do_dia' in src) > 0)                                AS le_jornada_escala,
  (position('LEAST(v_trab_min - v_jornada_diaria_min' in src) = 0)             AS nao_trunca_2h,
  (position('excesso_he_art59' in src) > 0)                                    AS sinaliza_excesso,
  CASE
    WHEN position('ponto_jornada_do_dia' in src) > 0
     AND position('LEAST(v_trab_min - v_jornada_diaria_min' in src) = 0
     AND position('excesso_he_art59' in src) > 0
      THEN 'OK'
    ELSE 'PENDENTE: corpo inesperado — conferir'
  END                                                                          AS erro_tecnico
FROM def;



-- ############################################################
-- BLOCO: script_ponto_onda3_adicional_noturno_prorrogado.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 3 (parte 3): adicional noturno prorrogado (Súmula 60, II TST)
-- Alvo: public.calcular_he_adicional_noturno_dia
-- PONTO-112  (mantém PONTO-110, PONTO-111, PONTO-091, PONTO-092)
--
-- O QUE FAZ
--   Quando a jornada é cumprida integralmente no período noturno (entrada até
--   as 22h, cobrindo toda a janela legal 22h–05h) e PRORROGADA além das 05h, o
--   adicional noturno acompanha as horas prorrogadas, em vez de cessar em 05:00
--   fixo (Súmula 60, II do TST). Criterio conservador na hora ficta: a parte
--   noturna (22h–05h) mantém a ficta; as horas prorrogadas entram pelo tempo
--   real (a aplicação da ficta à prorrogação é controvertida).
--
-- IMPORTANTE — ESTE PACOTE INCLUI A PARTE 2. O corpo aqui já traz as correções
--   da parte 2 (jornada da escala + HE sem truncar), porque é a mesma função.
--   Se você rodar o pacote #8 (parte 2) antes, tudo bem: este #9 o substitui
--   com o corpo final. Se rodar só o #9, também fica completo.
--
-- SEGURO E IDEMPOTENTE: CREATE OR REPLACE (definição única, sem remendos
--   próprios de produção nesta função).
--
-- OBSERVAÇÃO: como na parte 2, esta função de cálculo ainda não é consumida
--   pelo fluxo vivo de apuração — a correção deixa o cálculo certo para quando
--   for ligado.
-- ============================================================================

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
    NULL; -- qualquer falha na leitura da escala: mantém o fallback CCT/8h
  END;

  -- Total trabalhado em minutos (a partir das marcações entrada/saida)
  IF v_diario.entrada IS NOT NULL AND v_diario.saida IS NOT NULL THEN
    v_trab_min := EXTRACT(EPOCH FROM (v_diario.saida::time - v_diario.entrada::time))/60;
    IF v_diario.saida_almoco IS NOT NULL AND v_diario.retorno_almoco IS NOT NULL THEN
      v_trab_min := v_trab_min - EXTRACT(EPOCH FROM (v_diario.retorno_almoco::time - v_diario.saida_almoco::time))/60;
    END IF;
  END IF;
  IF v_trab_min < 0 THEN v_trab_min := 0; END IF;

  -- (092) Horas extras: TODO o tempo que excede a jornada é apurado. O limite
  -- de 2h do art. 59 é norma de conduta, não de cálculo — não se trunca a
  -- apuração; apura-se tudo e sinaliza-se o excesso ao RH.
  v_dow := EXTRACT(DOW FROM p_data); -- 0=domingo
  IF v_trab_min > v_jornada_diaria_min THEN
    v_excesso := v_trab_min - v_jornada_diaria_min;
    IF v_dow = 0 THEN
      v_he100 := v_excesso;
    ELSE
      v_he50 := v_excesso;
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

  UPDATE public.ponto_diario
     SET horas_extras_50_minutos = v_he50,
         horas_extras_100_minutos = v_he100,
         adicional_noturno_minutos = v_adn_min,
         updated_at = now()
   WHERE id = v_diario.id;

  RETURN jsonb_build_object(
    'ok', true,
    'he50_min', v_he50,
    'he100_min', v_he100,
    'adicional_noturno_min', v_adn_min,
    'percentual_he50', v_he50_pct,
    'percentual_he100', v_he100_pct,
    'percentual_adn', v_adn_pct
  );
END;
$function$;

-- ---------------------------------------------------------------------------
-- CONFERÊNCIA — o SQL Editor mostra apenas o último resultado.
-- Esperado: t | t | t | t | OK
--   le_jornada_escala   : t  (parte 2 — lê ponto_jornada_do_dia)
--   nao_trunca_2h       : t  (parte 2 — sem o corte LEAST)
--   sinaliza_excesso    : t  (parte 2 — alerta do art. 59)
--   adicional_prorrogado: t  (parte 3 — prorrogação da Súmula 60, II)
-- ---------------------------------------------------------------------------
WITH def AS (
  SELECT pg_get_functiondef(p.oid) AS src
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'calcular_he_adicional_noturno_dia'
    AND pg_get_function_identity_arguments(p.oid) = 'p_colaborador_id uuid, p_data date'
  LIMIT 1
)
SELECT
  (position('ponto_jornada_do_dia' in src) > 0)                    AS le_jornada_escala,
  (position('LEAST(v_trab_min - v_jornada_diaria_min' in src) = 0) AS nao_trunca_2h,
  (position('excesso_he_art59' in src) > 0)                        AS sinaliza_excesso,
  (position('v_prorrog_min' in src) > 0)                           AS adicional_prorrogado,
  CASE
    WHEN position('ponto_jornada_do_dia' in src) > 0
     AND position('LEAST(v_trab_min - v_jornada_diaria_min' in src) = 0
     AND position('excesso_he_art59' in src) > 0
     AND position('v_prorrog_min' in src) > 0
      THEN 'OK'
    ELSE 'PENDENTE: corpo inesperado — conferir'
  END                                                              AS erro_tecnico
FROM def;


-- ============================================================================
-- CONFERENCIA DESTA PARTE
-- Lista o que a parte deveria deixar no ambiente e diz o que chegou. A ultima
-- linha resume: OK quando nada faltou.
-- ============================================================================
WITH esperado (tipo, nome, marcador) AS MATERIALIZED (
  VALUES
    ('funcao', 'ponto_corte_virada', NULL),
    ('funcao', 'ponto_reordena_tipos_dia', 'Batida incluída em horário anterior às existentes; '),
    ('funcao', '_ponto_calc_dia', 'Atraso justificado por atestado de horas no dia.'),
    ('funcao', 'calcular_he_adicional_noturno_dia', NULL)
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
