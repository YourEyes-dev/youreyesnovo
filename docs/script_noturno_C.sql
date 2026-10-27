-- ============================================================================
-- CRITICO #1 — Parte C: reflexo de HE no DSR (Sumula 172) a partir da HE
-- CANONICA = credito do saldo do banco (ponto_saldo_dias_competencia), em vez
-- das colunas horas_extras_50/100 do ponto_diario (que ficam zeradas).
-- Recria ponto_dsr_competencia a partir da versao mais nova (20260930201223),
-- MUDANDO SO a fonte de he_min. Toda a logica de falta compensada (PONTO-481)
-- fica VERBATIM. Idempotente. Nao altera dado.
-- ============================================================================
SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.ponto_dsr_competencia(
  p_tenant_id       uuid,
  p_colaborador_cpf text,
  p_competencia     text
)
RETURNS TABLE(
  semana_inicio             date,
  semana_fim                date,
  dias_uteis_trabalhados    integer,
  he_semana_min             integer,
  reflexo_he_dsr_min        integer,
  teve_falta_injustificada  boolean,
  dsr_perdido               boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  -- DSR (Lei 605/1949). Semana ISO. Reflexo das HE (Súmula 172) + perda por
  -- falta injustificada (art. 6). [dsr-ignora-falta-compensada]: falta com
  -- compensação efetivada em banco não conta como falta para o DSR.
  -- [RN28] HE canônica = crédito diário do saldo do banco (mesma fonte do
  -- espelho), não as colunas horas_extras_* do ponto_diario.
  WITH saldo AS (
    SELECT s.dia, GREATEST(0, s.saldo_min) AS he_dia_min
    FROM public.ponto_saldo_dias_competencia(p_tenant_id, p_colaborador_cpf, p_competencia) s
  ),
  dias AS (
    SELECT d.data,
           date_trunc('week', d.data)::date       AS semana,
           EXTRACT(ISODOW FROM d.data)::int        AS isodow,
           COALESCE(sa.he_dia_min, 0)              AS he_min,
           COALESCE(floor(EXTRACT(EPOCH FROM d.horas_trabalhadas)/60)::int, 0) AS trab_min,
           d.status,
           d.tipo_dia,
           d.observacao,
           EXISTS (
             SELECT 1 FROM public.ponto_compensacao_falta cf
             WHERE cf.tenant_id = p_tenant_id
               AND regexp_replace(COALESCE(cf.colaborador_cpf,''),'[^0-9]','','g')
                   = regexp_replace(COALESCE(p_colaborador_cpf,''),'[^0-9]','','g')
               AND cf.data_falta = d.data
               AND cf.status = 'efetivada'
           )                                                    AS compensada
    FROM public.ponto_diario d
    LEFT JOIN saldo sa ON sa.dia = d.data
    WHERE d.tenant_id = p_tenant_id
      AND regexp_replace(d.colaborador_cpf, '[^0-9]', '', 'g')
          = regexp_replace(COALESCE(p_colaborador_cpf, ''), '[^0-9]', '', 'g')
      AND to_char(d.data, 'YYYY-MM') = p_competencia
  ),
  por_semana AS (
    SELECT semana                                             AS semana_inicio,
           (semana + 6)                                       AS semana_fim,
           COUNT(*) FILTER (WHERE isodow <= 6 AND trab_min > 0) AS dias_uteis_trab,
           COALESCE(SUM(he_min), 0)                            AS he_semana,
           bool_or(
             isodow <= 6
             AND status = 'falta'
             AND NOT compensada
             AND COALESCE(tipo_dia, '') NOT IN ('ferias','atestado','afastamento','feriado')
             AND COALESCE(observacao, '') NOT ILIKE '%atestado%'
             AND COALESCE(observacao, '') NOT ILIKE '%justific%'
           )                                                   AS teve_falta
    FROM dias
    GROUP BY semana
  )
  SELECT
    semana_inicio,
    semana_fim,
    dias_uteis_trab::int,
    he_semana::int,
    CASE WHEN dias_uteis_trab > 0
         THEN ROUND(he_semana::numeric / dias_uteis_trab)::int
         ELSE 0 END                          AS reflexo_he_dsr_min,
    COALESCE(teve_falta, false)              AS teve_falta_injustificada,
    COALESCE(teve_falta, false)              AS dsr_perdido
  FROM por_semana
  ORDER BY semana_inicio;
$function$;

-- VALIDACAO (rollback por bloco): dia com saldo positivo -> reflexo de HE no DSR > 0
DO $val$
DECLARE
  v_t uuid := public.qa_sandbox_tenant_id();
  v_cpf text := public.qa_cpf(7802);
  v_d date := DATE '2026-09-15';  -- segunda
  v_reflexo int := 0; v_he int := 0; v_falta boolean;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM public.qa_ponto_admissao('QA DSR', 7802);
  -- escala 8h/dia, atribuida
  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA DSR', 480, 5, v_d - 10, v_d + 20);
  -- dia de 9h (08-12,13-18) -> saldo +60
  PERFORM public.qa_ponto_marca(v_cpf,'QA DSR', v_d, TIME '08:00','entrada');
  PERFORM public.qa_ponto_marca(v_cpf,'QA DSR', v_d, TIME '12:00','saida');
  PERFORM public.qa_ponto_marca(v_cpf,'QA DSR', v_d, TIME '13:00','entrada');
  PERFORM public.qa_ponto_marca(v_cpf,'QA DSR', v_d, TIME '18:00','saida');
  PERFORM public.consolidar_ponto_diario_manual(v_t, v_cpf, v_d);

  SELECT COALESCE(SUM(reflexo_he_dsr_min),0), COALESCE(SUM(he_semana_min),0), bool_or(dsr_perdido)
    INTO v_reflexo, v_he, v_falta
    FROM public.ponto_dsr_competencia(v_t, v_cpf, '2026-09');

  RAISE NOTICE 'DSR-C: he_semana_total=% reflexo_total=% (esperado >0, vindo do saldo) | dsr_perdido=% (esperado false)',
               v_he, v_reflexo, v_falta;
  RAISE EXCEPTION 'ROLLBACK_ME';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM <> 'ROLLBACK_ME' THEN RAISE NOTICE 'DSR-C ERRO: %', SQLERRM; END IF;
END $val$;
