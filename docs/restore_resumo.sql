-- ============================================================================
-- RESTAURA ponto_espelho_resumo / _empresa na HOMOLOGACAO ao estado do repo.
-- Motivo: testes do adicional noturno (teste B, revertido) deixaram a base do
-- resumo poluida em homologacao (com coluna de teste e SEM o patch de
-- equalizacao). Este script reconstroi as duas funcoes a partir das fontes
-- verdadeiras do repositorio, na ordem cronologica correta:
--   1) base ponto_espelho_resumo           = 20260805012900
--   2) fix  ponto_espelho_resumo_empresa   = 20260813140000 (PONTO-311/312)
--   3) patch equalizacao (base)            = 20260930182041 [falta-nao-conta-equalizacao]
--   4) patch vinculo (_empresa)            = 20260930225818 [lista-respeita-vinculo]
-- Idempotente. Nao altera dado. Roda em transacao unica (esteira).
-- ============================================================================
SET lock_timeout = '10s';

-- Limpa o estado atual (DROP resolve a mudanca de assinatura de retorno do teste).
DROP FUNCTION IF EXISTS public.ponto_espelho_resumo_empresa(uuid, uuid, text);
DROP FUNCTION IF EXISTS public.ponto_espelho_resumo(uuid, text, text);

-- ---------------------------------------------------------------------------
-- 1) BASE: ponto_espelho_resumo  (verbatim de 20260805012900)
-- ---------------------------------------------------------------------------
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
  atrasos_min integer
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
    c.total_debitos_min AS atrasos_min
  FROM c;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.ponto_espelho_resumo(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ponto_espelho_resumo(uuid, text, text) TO authenticated;

COMMENT ON FUNCTION public.ponto_espelho_resumo(uuid, text, text) IS
  'Totais do espelho a partir da apuração (ponto_saldo_dias_competencia). RN28: o saldo positivo do banco de horas (incluindo saldo anterior) é distribuído entre HE 50% e HE 100% conforme a origem (domingo/feriado = 100%).';

-- ---------------------------------------------------------------------------
-- 2) FIX: ponto_espelho_resumo_empresa  (verbatim de 20260813140000, PONTO-311/312)
-- ---------------------------------------------------------------------------
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
  atrasos_min integer
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
      -- Linha sem empresa NÃO entra em todas: resolve-se pelo cadastro da
      -- admissão. Deixar passar era o defeito reparado em 04/08.
      AND (p_empresa_id IS NULL
           OR COALESCE(
                pd.empresa_id,
                public.ponto_empresa_do_cpf(
                  p_tenant_id,
                  regexp_replace(pd.colaborador_cpf, '[^0-9]', '', 'g'))
              ) = p_empresa_id)
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
GRANT EXECUTE ON FUNCTION public.ponto_espelho_resumo_empresa(uuid, uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3) PATCH equalizacao na BASE  (verbatim de 20260930182041)
-- ---------------------------------------------------------------------------
DO $patch$
DECLARE
  v_src text;
  v_new text;
  v_anchor text := 'WHERE NOT d.protegido AND d.jornada_min > 0 AND d.trabalhado_min = 0';
  v_repl  text := 'WHERE NOT d.protegido AND d.jornada_min > 0 AND d.trabalhado_min = 0'
                 || ' AND NOT COALESCE(d.equalizacao, false) /* [falta-nao-conta-equalizacao] */';
BEGIN
  v_src := pg_get_functiondef('public.ponto_espelho_resumo(uuid,text,text)'::regprocedure);

  IF position('[falta-nao-conta-equalizacao]' IN v_src) > 0 THEN
    RAISE NOTICE 'ponto_espelho_resumo: correcao [falta-nao-conta-equalizacao] ja aplicada; nada a fazer.';
    RETURN;
  END IF;

  IF position(v_anchor IN v_src) = 0 THEN
    RAISE NOTICE 'ponto_espelho_resumo: ancora do filtro de faltas NAO encontrada; revisar manualmente.';
    RETURN;
  END IF;

  v_new := replace(v_src, v_anchor, v_repl);
  EXECUTE v_new;
  RAISE NOTICE 'ponto_espelho_resumo: correcao [falta-nao-conta-equalizacao] aplicada.';
END;
$patch$;

-- ---------------------------------------------------------------------------
-- 4) PATCH vinculo no _empresa  (verbatim de 20260930225818, bloco C)
-- ---------------------------------------------------------------------------
DO $patchC$
DECLARE
  v_src text; v_novo text;
  v_alvo text := E'      AND COALESCE(pd.colaborador_cpf, \'\') <> \'\'';
  v_troca text := E'      AND COALESCE(pd.colaborador_cpf, \'\') <> \'\'\n'
    || E'      -- [lista-respeita-vinculo] não traz desligado após a data\n'
    || E'      AND public.ponto_vinculo_cobre_periodo(p_tenant_id, regexp_replace(pd.colaborador_cpf, \'[^0-9]\', \'\', \'g\'), v_ini, v_fim)';
BEGIN
  v_src := pg_get_functiondef('public.ponto_espelho_resumo_empresa(uuid,uuid,text)'::regprocedure);
  IF position('[lista-respeita-vinculo]' IN v_src) > 0 THEN
    RAISE NOTICE 'ponto_espelho_resumo_empresa ja filtra por vinculo — nada a fazer.'; RETURN;
  END IF;
  IF position(v_alvo IN v_src) = 0 THEN
    RAISE NOTICE 'ATENCAO: ancora do loop de cpf em ponto_espelho_resumo_empresa nao encontrada; NADA alterado.'; RETURN;
  END IF;
  v_novo := replace(v_src, v_alvo, v_troca);
  EXECUTE v_novo;
  RAISE NOTICE 'ponto_espelho_resumo_empresa: lista do mes passa a respeitar o vinculo.';
END;
$patchC$;

-- ---------------------------------------------------------------------------
-- CONFERENCIA final: markers presentes, coluna de teste ausente.
-- ---------------------------------------------------------------------------
DO $ver$
DECLARE
  v_resumo text := pg_get_functiondef('public.ponto_espelho_resumo(uuid,text,text)'::regprocedure);
  v_emp    text := pg_get_functiondef('public.ponto_espelho_resumo_empresa(uuid,uuid,text)'::regprocedure);
  v_eq  boolean := position('[falta-nao-conta-equalizacao]' IN v_resumo) > 0;
  v_vin boolean := position('[lista-respeita-vinculo]' IN v_emp) > 0;
  v_not boolean := position('adicional_noturno' IN v_resumo) > 0;  -- deve ser FALSE
BEGIN
  RAISE NOTICE 'RESTORE-RESUMO: equalizacao=% vinculo=% coluna_noturno_de_teste_presente=% (esperado t / t / f)',
    v_eq, v_vin, v_not;
END;
$ver$;
