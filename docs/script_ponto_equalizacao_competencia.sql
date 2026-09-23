-- ============================================================================
-- ENTREGA — ponto_equalizacao_competencia: feriados via fonte unica (teste->prod)
--
-- O QUE ESTE SCRIPT FAZ (e por que):
--   A equalizacao mensal desconta os feriados dos dias uteis do mes. A versao
--   da producao usava uma regra FROUXA: sem UF/cidade na filial, deduzia TODOS
--   os feriados estaduais e municipais da base — enquanto o espelho de ponto
--   nao considerava nenhum. O mesmo dia contava como feriado num calculo e como
--   dia util no outro. O teste (fonte da verdade) passou a deduzir os feriados
--   via feriados_da_empresa (a MESMA resolucao do espelho). Mesma assinatura.
--
-- POR QUE O ENVELOPE "DO ... EXECUTE":
--   O SQL Editor do Supabase tem um recurso que tenta "ativar RLS em tabelas
--   novas". Ele varre o texto e confunde os alvos de SELECT ... INTO (v_esc,
--   v_emp, ...) com criacao de tabela, injetando ALTER TABLE no meio da funcao
--   e quebrando o corpo. Criando a funcao de DENTRO de um bloco DO/EXECUTE, o
--   nivel de cima e so um DO (sem SELECT INTO visivel), e o injetor nao dispara.
--   A funcao criada e byte a byte a mesma — a conferencia por md5 comprova.
--
-- SEGURANCA: so substitui a funcao; nao altera nem apaga dado; idempotente.
-- ============================================================================

SET lock_timeout = '10s';

DO $ptdo$
BEGIN
  EXECUTE $ptsql$
CREATE OR REPLACE FUNCTION public.ponto_equalizacao_competencia(p_tenant_id uuid, p_escala_id uuid, p_competencia text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $fn$
DECLARE
  v_ini date := to_date(p_competencia || '-01', 'YYYY-MM-DD');
  v_fim date := (to_date(p_competencia || '-01', 'YYYY-MM-DD') + INTERVAL '1 month - 1 day')::date;
  v_esc RECORD;
  v_emp RECORD;
  v_dias text[] := ARRAY['segunda','terca','quarta','quinta','sexta'];
  v_dia text;
  v_cfg jsonb;
  v_j int;
  v_carga int := 0;
  v_contratada int;
  v_dias_uteis int := 0;
  v_feriados jsonb := '[]'::jsonb;
  v_qtd_fer int := 0;
  v_efetivos int;
  v_def_sem int;
  v_total int;
  v_obs text[] := ARRAY[]::text[];
BEGIN
  IF auth.uid() IS NOT NULL AND public.get_user_tenant_id() IS DISTINCT FROM p_tenant_id THEN
    RAISE EXCEPTION 'Acesso negado ao tenant';
  END IF;

  SELECT id, nome, dias_config, jornada_diaria_minutos, empresa_id,
         COALESCE(equalizacao_mensal_ativa, false) AS ativa,
         COALESCE(carga_semanal_contratada_min, 2640) AS contratada
    INTO v_esc
  FROM public.ponto_escalas
  WHERE id = p_escala_id AND tenant_id = p_tenant_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Escala não encontrada no tenant';
  END IF;

  v_contratada := v_esc.contratada;

  SELECT estado, cidade INTO v_emp
  FROM public.empresa_cadastro WHERE id = v_esc.empresa_id;

  -- Carga semanal REAL derivada do dias_config (seg–sex)
  IF v_esc.dias_config IS NOT NULL AND jsonb_typeof(v_esc.dias_config) = 'object' THEN
    FOREACH v_dia IN ARRAY v_dias LOOP
      v_cfg := v_esc.dias_config -> v_dia;
      IF v_cfg IS NOT NULL AND COALESCE((v_cfg->>'trabalha')::boolean, false) THEN
        v_j := (EXTRACT(EPOCH FROM ((v_cfg->>'saida')::time - (v_cfg->>'entrada')::time)) / 60)::int;
        IF COALESCE((v_cfg->>'tem_almoco')::boolean, false)
           AND (v_cfg->>'inicio_almoco') IS NOT NULL
           AND (v_cfg->>'fim_almoco') IS NOT NULL THEN
          v_j := v_j - (EXTRACT(EPOCH FROM (
            (v_cfg->>'fim_almoco')::time - (v_cfg->>'inicio_almoco')::time)) / 60)::int;
        END IF;
        v_carga := v_carga + GREATEST(v_j, 0);
      END IF;
    END LOOP;
  ELSE
    v_carga := COALESCE(v_esc.jornada_diaria_minutos, 0) * 5;
    v_obs := v_obs || ARRAY['Carga semanal estimada por jornada_diaria_minutos × 5 (escala sem dias_config).'];
  END IF;

  v_def_sem  := GREATEST(v_contratada - v_carga, 0);

  -- Opt-in desligado: não aplica (mas devolve a memória para inspeção)
  IF NOT v_esc.ativa THEN
    RETURN jsonb_build_object(
      'aplicavel', false,
      'competencia', p_competencia,
      'escala_id', v_esc.id,
      'escala_nome', v_esc.nome,
      'carga_semanal_real_min', v_carga,
      'carga_semanal_contratada_min', v_contratada,
      'total_equalizacao_min', 0,
      'observacoes', to_jsonb(v_obs || ARRAY['Equalização mensal desativada para esta escala.']),
      'gerado_em', now()
    );
  END IF;

  -- RN01: dias úteis seg–sex por contagem direta
  SELECT count(*) INTO v_dias_uteis
  FROM generate_series(v_ini, v_fim, interval '1 day') g
  WHERE EXTRACT(ISODOW FROM g) BETWEEN 1 AND 5;

  -- RN02: feriados (só tipo='feriado' e ativo=true)
  SELECT COALESCE(jsonb_agg(jsonb_build_object('data', f.data, 'nome', f.nome) ORDER BY f.data), '[]'::jsonb),
         count(*)
    INTO v_feriados, v_qtd_fer
  FROM (
    -- FONTE ÚNICA: mesma resolução do espelho (feriado_do_dia), agora ciente
    -- das tabelas nomeadas vinculadas à filial, de feriados de abrangência
    -- 'filial' e de feriados recorrentes (dia/mês).
    --
    -- A regra anterior era frouxa: sem UF/cidade na filial, TODOS os feriados
    -- estaduais e municipais da base eram deduzidos aqui, enquanto no espelho
    -- não valia nenhum — o mesmo dia contava como feriado num cálculo e como
    -- dia útil no outro.
    SELECT h.data, h.nome
    FROM public.feriados_da_empresa(p_tenant_id, v_esc.empresa_id, v_ini, v_fim) h
    WHERE EXTRACT(ISODOW FROM h.data) BETWEEN 1 AND 5
    ORDER BY h.data
  ) f;

  v_efetivos := GREATEST(v_dias_uteis - COALESCE(v_qtd_fer, 0), 0);
  v_total    := round(v_efetivos * v_def_sem / 5.0)::int;

  IF v_def_sem = 0 THEN
    v_obs := v_obs || ARRAY['Escala já cumpre a carga contratada — equalização não se aplica.'];
  END IF;
  IF v_qtd_fer = 0 THEN
    v_obs := v_obs || ARRAY['Nenhum feriado deduzido neste mês (pontos facultativos não são deduzidos).'];
  END IF;

  RETURN jsonb_build_object(
    'aplicavel', true,
    'competencia', p_competencia,
    'escala_id', v_esc.id,
    'escala_nome', v_esc.nome,
    'dias_uteis_brutos', v_dias_uteis,
    'feriados_deduzidos', v_feriados,
    'qtd_feriados_deduzidos', COALESCE(v_qtd_fer, 0),
    'dias_uteis_efetivos', v_efetivos,
    'carga_semanal_real_min', v_carga,
    'carga_semanal_contratada_min', v_contratada,
    'deficit_semanal_min', v_def_sem,
    'deficit_diario_min', round(v_def_sem / 5.0, 1),
    'total_equalizacao_min', v_total,
    'observacoes', to_jsonb(v_obs),
    'gerado_em', now()
  );
END;
$fn$;
  $ptsql$;
END
$ptdo$;

-- ── Conferencia — RODE ESTE BLOCO SEPARADO (numa consulta nova) ─────────────
-- Esperado: 1 linha, status = OK.
--   SELECT
--     md5(regexp_replace(pg_get_functiondef(p.oid), '\s+', ' ', 'g'))  AS md5_producao,
--     '15dd498adb35c461ef2eb6ae0a65678e'                               AS md5_teste,
--     CASE WHEN md5(regexp_replace(pg_get_functiondef(p.oid), '\s+', ' ', 'g'))
--               = '15dd498adb35c461ef2eb6ae0a65678e'
--          THEN 'OK' ELSE 'CONFERIR' END                               AS status
--   FROM pg_proc p
--   JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
--   WHERE p.proname = 'ponto_equalizacao_competencia';
