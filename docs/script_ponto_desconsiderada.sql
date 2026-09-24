-- ============================================================================
-- ENTREGA — "marcacao desconsiderada nao entra no calculo" (drift teste -> prod)
--
-- O QUE ESTE SCRIPT FAZ (e por que):
--   Quando o gestor DESCONSIDERA uma batida (duplicada ou incorreta), a batida
--   permanece registrada (Sumula 338 / Portaria 671 — nada de ponto se apaga),
--   mas marcada como desconsiderada. O teste (fonte da verdade) ja exclui essas
--   batidas de tres calculos; a producao ainda NAO, e por isso uma batida
--   riscada segue pesando nas horas do dia. Este script traz as tres funcoes
--   para o estado do teste, adicionando o filtro
--   "AND NOT COALESCE(desconsiderada, false)":
--
--     1. _ponto_calc_dia          — o laco das batidas do dia (horas/status);
--     2. ponto_corte_virada       — o corte da virada de dia;
--     3. ponto_reordena_tipos_dia — a reordenacao dos rotulos entrada/saida.
--
-- SEGURANCA: so cria/substitui funcoes; nao altera nem apaga dado; nao cria
--   gatilho (sem risco de deadlock). E idempotente (rodar duas vezes nao muda
--   nada nem quebra). A conferencia final compara o corpo de cada funcao, ja
--   normalizado, com o hash do teste — as tres tem de fechar em OK.
-- ============================================================================

SET lock_timeout = '10s';

-- ── 1) _ponto_calc_dia ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._ponto_calc_dia(p_tenant_id uuid, p_colaborador_cpf text, p_data date, p_cid uuid, OUT o_pent time without time zone, OUT o_salm time without time zone, OUT o_ralm time without time zone, OUT o_usai time without time zone, OUT o_horas interval, OUT o_status text, OUT o_obs text)
 RETURNS record
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fn$
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
    WHERE tenant_id = p_tenant_id AND colaborador_cpf = p_colaborador_cpf AND data_marcacao = p_data AND NOT COALESCE(desconsiderada, false)
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
        -- O registro legal e em hora e minuto (AFD da Portaria 671 nao tem
        -- segundos). Trunca-se CADA MARCACAO antes de subtrair: truncar a
        -- diferenca perdia ate 59s por par, duas vezes ao dia, sempre
        -- contra o trabalhador (PONTO-470).
        v_dif := floor(EXTRACT(EPOCH FROM v_marc.hora_marcacao) / 60)::INT - floor(EXTRACT(EPOCH FROM v_abr) / 60)::INT;
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
$fn$;

-- ── 2) ponto_corte_virada ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ponto_corte_virada(p_tenant_id uuid, p_colaborador_cpf text, p_data date)
 RETURNS time without time zone
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $fn$
  WITH m AS (
    SELECT hora_marcacao AS h
    FROM public.ponto_marcacoes
    WHERE tenant_id = p_tenant_id
      AND colaborador_cpf = p_colaborador_cpf
      AND data_marcacao = p_data AND NOT COALESCE(desconsiderada, false)
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
$fn$;

-- ── 3) ponto_reordena_tipos_dia ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ponto_reordena_tipos_dia(p_tenant_id uuid, p_colaborador_cpf text, p_data date)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fn$
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
        AND data_marcacao = p_data AND NOT COALESCE(desconsiderada, false)
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
    AND data_marcacao = p_data AND NOT COALESCE(desconsiderada, false);

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
      AND data_marcacao = p_data AND NOT COALESCE(desconsiderada, false)
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
                                    AND data_marcacao = p_data AND NOT COALESCE(desconsiderada, false)
                                )),
             auth.uid();
    EXCEPTION WHEN OTHERS THEN
      NULL;  -- auditoria é registro acessório; nunca derruba a aprovação
    END;
  END IF;

  RETURN (v_changed IS NOT NULL);
END;
$fn$;

-- ── Conferencia (o editor mostra so o ultimo resultado) ─────────────────────
-- Compara o corpo de cada funcao (com espaco em branco colapsado) com o hash
-- do TESTE. Esperado: 3 linhas, todas com status = OK.
WITH esperado(objeto, md5_teste) AS (
  VALUES
    ('_ponto_calc_dia',          '2050fdc7c00e30c890051164c48032c2'),
    ('ponto_corte_virada',       'c8440dff3b6ff77f68cbc39e2d7a52d6'),
    ('ponto_reordena_tipos_dia', '2bdc46a24ffd331302f0aa64eab0dc8b')
)
SELECT
  e.objeto,
  md5(regexp_replace(pg_get_functiondef(p.oid), '\s+', ' ', 'g')) AS md5_producao,
  e.md5_teste,
  CASE WHEN md5(regexp_replace(pg_get_functiondef(p.oid), '\s+', ' ', 'g')) = e.md5_teste
       THEN 'OK' ELSE 'CONFERIR' END AS status
FROM esperado e
JOIN pg_proc p      ON p.proname = e.objeto
JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
ORDER BY e.objeto;
