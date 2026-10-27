-- CRITICO #1 Parte B(i): expoe o adicional noturno no resumo do espelho.
-- Coluna aditiva adicional_noturno_min (soma de ponto_diario.adicional_noturno).
-- Diff zero hoje (tudo 0); passa a valer com o trigger da Parte A.
SET lock_timeout = '10s';
DROP FUNCTION IF EXISTS public.ponto_espelho_resumo_empresa(uuid, uuid, text);
DROP FUNCTION IF EXISTS public.ponto_espelho_resumo(uuid, text, text);

CREATE OR REPLACE FUNCTION public.ponto_espelho_resumo(
  p_tenant_id uuid,
  p_colaborador_cpf text,
  p_competencia text
)
RETURNS TABLE(
  dias_com_registro integer,
  dias_trabalhados integer,
  total_trabalhado_min integer,
  total_jornada_prevista_min integer,
  total_creditos_min integer,
  total_debitos_min integer,
  saldo_min integer,
  total_faltas integer,
  dias_protegidos integer,
  excedente_retido_min integer,
  dia_equalizacao date,
  saldo_anterior_min integer,
  saldo_banco_min integer,
  he_50_min integer,
  he_100_min integer,
  atrasos_min integer,
  adicional_noturno_min integer
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_cpf text := regexp_replace(COALESCE(p_colaborador_cpf, ''), '[^0-9]', '', 'g');
  v_ini date := to_date(p_competencia || '-01', 'YYYY-MM-DD');
  v_fim date := (to_date(p_competencia || '-01', 'YYYY-MM-DD') + interval '1 month - 1 day')::date;
  v_cid uuid;
  v_saldo_ant integer := 0;
  v_cred_100 integer := 0;
  v_cred_tot integer := 0;
  v_saldo integer := 0;
  v_he100 integer := 0;
  v_he50 integer := 0;
BEGIN
  SELECT max(pd.colaborador_id::text)::uuid INTO v_cid
  FROM public.ponto_diario pd
  WHERE pd.tenant_id = p_tenant_id
    AND regexp_replace(COALESCE(pd.colaborador_cpf, ''), '[^0-9]', '', 'g') = v_cpf
    AND pd.data BETWEEN v_ini AND v_fim;

  -- Saldo anterior do banco de horas (crédito trazido do ciclo anterior).
  SELECT COALESCE(bh.saldo_anterior_minutos, 0) INTO v_saldo_ant
  FROM public.ponto_banco_horas bh
  WHERE bh.tenant_id = p_tenant_id
    AND bh.competencia = p_competencia
    AND regexp_replace(COALESCE(bh.colaborador_cpf, ''), '[^0-9]', '', 'g') = v_cpf
  ORDER BY bh.updated_at DESC NULLS LAST
  LIMIT 1;
  v_saldo_ant := COALESCE(v_saldo_ant, 0);

  RETURN QUERY
  WITH d AS (
    SELECT * FROM public.ponto_saldo_dias_competencia(p_tenant_id, v_cpf, p_competencia)
  ),
  c AS (
    SELECT
      count(*)::int AS dias_com_registro,
      count(*) FILTER (WHERE d.trabalhado_min > 0)::int AS dias_trabalhados,
      COALESCE(sum(d.trabalhado_min), 0)::int AS total_trabalhado_min,
      COALESCE(sum(d.jornada_min), 0)::int AS total_jornada_prevista_min,
      COALESCE(sum(d.saldo_min) FILTER (WHERE d.saldo_min > 0), 0)::int AS total_creditos_min,
      COALESCE(-sum(d.saldo_min) FILTER (WHERE d.saldo_min < 0), 0)::int AS total_debitos_min,
      COALESCE(sum(d.saldo_min), 0)::int AS saldo_min,
      count(*) FILTER (
        WHERE NOT d.protegido AND d.jornada_min > 0 AND d.trabalhado_min = 0
      )::int AS total_faltas,
      count(*) FILTER (WHERE d.protegido)::int AS dias_protegidos,
      COALESCE(sum(d.excedente_retido_min), 0)::int AS excedente_retido_min,
      (SELECT min(x.dia) FROM d x WHERE x.equalizacao) AS dia_equalizacao,
      -- Crédito originado em domingo ou feriado trabalhado: adicional 100%
      -- (Súmula 146 TST; Lei 605/1949, art. 9º).
      COALESCE(sum(d.saldo_min) FILTER (
        WHERE d.saldo_min > 0
          AND (
            EXTRACT(ISODOW FROM d.dia) = 7
            OR (v_cid IS NOT NULL AND public.feriado_do_dia(p_tenant_id, v_cid, d.dia) IS NOT NULL)
          )
      ), 0)::int AS credito_100_min
    FROM d
  )
  SELECT
    c.dias_com_registro, c.dias_trabalhados, c.total_trabalhado_min,
    c.total_jornada_prevista_min, c.total_creditos_min, c.total_debitos_min,
    c.saldo_min, c.total_faltas, c.dias_protegidos, c.excedente_retido_min,
    c.dia_equalizacao,
    v_saldo_ant,
    (v_saldo_ant + c.saldo_min)::int AS saldo_banco_min,
    -- Débito não reduz hora extra: só o saldo positivo é distribuído.
    GREATEST(0, (v_saldo_ant + c.saldo_min) - LEAST(c.credito_100_min, GREATEST(0, v_saldo_ant + c.saldo_min)))::int AS he_50_min,
    LEAST(c.credito_100_min, GREATEST(0, v_saldo_ant + c.saldo_min))::int AS he_100_min,
    c.total_debitos_min AS atrasos_min,
    (SELECT COALESCE(SUM(COALESCE(pd.adicional_noturno_minutos,0)),0)::int
       FROM public.ponto_diario pd
      WHERE pd.tenant_id = p_tenant_id
        AND regexp_replace(COALESCE(pd.colaborador_cpf,''),'[^0-9]','','g') = v_cpf
        AND pd.data BETWEEN v_ini AND v_fim) AS adicional_noturno_min
  FROM c;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.ponto_espelho_resumo(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ponto_espelho_resumo(uuid, text, text) TO authenticated;

COMMENT ON FUNCTION public.ponto_espelho_resumo(uuid, text, text) IS
  'Totais do espelho a partir da apuração (ponto_saldo_dias_competencia). RN28: o saldo positivo do banco de horas (incluindo saldo anterior) é distribuído entre HE 50% e HE 100% conforme a origem (domingo/feriado = 100%).';

CREATE OR REPLACE FUNCTION public.ponto_espelho_resumo_empresa(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_competencia text
)
RETURNS TABLE(
  colaborador_cpf text,
  colaborador_nome text,
  colaborador_id uuid,
  dias_com_registro integer,
  dias_trabalhados integer,
  total_trabalhado_min integer,
  total_jornada_prevista_min integer,
  total_creditos_min integer,
  total_debitos_min integer,
  saldo_min integer,
  total_faltas integer,
  dias_protegidos integer,
  excedente_retido_min integer,
  dia_equalizacao date,
  saldo_anterior_min integer,
  saldo_banco_min integer,
  he_50_min integer,
  he_100_min integer,
  atrasos_min integer,
  adicional_noturno_min integer
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ini date := to_date(p_competencia || '-01', 'YYYY-MM-DD');
  v_fim date := (to_date(p_competencia || '-01', 'YYYY-MM-DD') + interval '1 month - 1 day')::date;
  r RECORD;
BEGIN
  FOR r IN
    SELECT regexp_replace(pd.colaborador_cpf, '[^0-9]', '', 'g') AS cpf,
           max(pd.colaborador_nome) AS nome,
           max(pd.colaborador_id::text)::uuid AS cid
    FROM public.ponto_diario pd
    WHERE pd.tenant_id = p_tenant_id
      AND pd.data BETWEEN v_ini AND v_fim
      AND COALESCE(pd.colaborador_cpf, '') <> ''
      AND (p_empresa_id IS NULL OR pd.empresa_id = p_empresa_id OR pd.empresa_id IS NULL)
    GROUP BY 1
    ORDER BY 2
  LOOP
    RETURN QUERY
    SELECT r.cpf, r.nome, r.cid, s.*
    FROM public.ponto_espelho_resumo(p_tenant_id, r.cpf, p_competencia) s;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.ponto_espelho_resumo_empresa(uuid, uuid, text) FROM PUBLIC, anon;
