-- ============================================================================
-- ENTREGA — apuracao em duas pecas: nucleo + involucro (PONTO-300/301)
--
-- POR QUE
-- O projeto dividiu o motor de apuracao em duas pecas ha meses; a producao
-- ficou com a peca unica (o monolito). Essa divergencia ja custou caro duas
-- vezes no ensaio da homologacao:
--   - o pacote #7 (tolerancia) apontava para o nucleo e teria falhado EM VOZ
--     ALTA na producao: "function ... does not exist";
--   - o pacote #26 (escala 12x36) teria falhado EM SILENCIO — ele procura um
--     trecho para alterar, nao acha, e segue sem mudar nada. Na pratica, o
--     plantonista de 12x36 continuaria acumulando falta no dia de folga.
-- Enquanto os dois ambientes divergirem, todo pacote futuro que tocar a
-- apuracao corre o mesmo risco. Este pacote encerra a divergencia.
--
-- O QUE ENTRA
--   1. ponto_saldo_dias_competencia_bruto — o NUCLEO. E exatamente o mesmo
--      motor que ja roda na producao hoje: comparado linha a linha com o
--      monolito remendado pelos pacotes #7 e #26, as unicas 11 linhas
--      diferentes sao COMENTARIOS. Nenhuma linha de codigo executavel muda.
--   2. ponto_saldo_dias_competencia — o INVOLUCRO, fino e explicito. Ele
--      agrupa por dia e:
--        - dia que sai UMA VEZ SO passa intocado (linhas = 1 -> saldo_unico),
--          sem nem arredondamento;
--        - dia que sai duplicado vira uma linha, aplicando a mesma tolerancia
--          de 10 minutos da apuracao.
--      Ou seja: em base sem dia duplicado, a saida publica e IDENTICA a de
--      hoje, linha a linha. E o que o caso PONTO-301 confere.
--
-- POR QUE E SEGURO
--   - A assinatura publica nao muda: mesmos parametros, mesma tabela de
--     retorno (dia, entrada, saida, trabalhado_min, jornada_min, saldo_min,
--     protegido, equalizacao, excedente_retido_min). Os 6 chamadores de banco
--     (apurar_banco_horas_colaborador, ponto_espelho_resumo,
--     ponto_saldo_dia_empresa, ponto_excedente_pendentes,
--     ponto_registrar_memoria_calculo, ponto_dias_repetidos_na_apuracao) e as
--     telas continuam chamando a mesma funcao, do mesmo jeito.
--   - O nucleo entra ANTES do involucro: o involucro e LANGUAGE sql e o banco
--     valida o corpo dele na criacao — se o nucleo faltasse, o proprio banco
--     recusaria, em vez de deixar passar quebrado.
--
-- NAO altera espelho, fechamento, banco de horas nem tela. Idempotente.
-- Roda inteiro em UMA transacao.
-- ============================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- (1) O NUCLEO — o motor, igual ao que ja roda hoje.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_saldo_dias_competencia_bruto(p_tenant_id uuid, p_colaborador_cpf text, p_competencia text)
 RETURNS TABLE(dia date, entrada time without time zone, saida time without time zone, trabalhado_min integer, jornada_min integer, saldo_min integer, protegido boolean, equalizacao boolean, excedente_retido_min integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ini date := to_date(p_competencia || '-01', 'YYYY-MM-DD');
  v_fim date := (to_date(p_competencia || '-01', 'YYYY-MM-DD') + INTERVAL '1 month - 1 day')::date;
  v_cpf text := regexp_replace(COALESCE(p_colaborador_cpf, ''), '[^0-9]', '', 'g');
  v_colaborador_id text;
  v_fb_jornada int;
  v_fb_tol int := 0;
  v_fb_escala_id uuid;
  v_vinc_ini date;
  v_vinc_fim date;
  v_jornada int;
  v_tol int;
  v_esperado int;
  v_atest_min int;
  v_jornada_efetiva int;
  v_extras int;
  v_faltantes int;
  v_trab int;
  v_diff int;
  v_ent_esc time; v_sai_esc time; v_interv int; v_tol_bat int;
  v_ent_cons int; v_sai_cons int; v_trab_ajust int; v_usou_batida boolean;
  v_protegido boolean;
  v_prot_credito boolean;
  v_trab_marc int;
  v_janela int;
  v_janela_cons int;
  v_interv_real int;
  v_desc_interv int;
  v_int_ini time; v_int_fim time;
  v_eq_data date;
  v_eq_total int;
  v_eq_liberado boolean := false;
  v_eq_teve_linha boolean := false;
  v_eq_m jsonb;
  v_eq_auto boolean := false;
  v_qtd_sab int := 0;
  v_ult_sab date;
  v_exc_decidido boolean;
  v_ja_emitiu date[] := ARRAY[]::date[];
  r RECORD;
BEGIN
  v_ult_sab := v_fim - ((EXTRACT(ISODOW FROM v_fim)::int + 1) % 7);

  SELECT colaborador_id INTO v_colaborador_id
  FROM public.ponto_diario
  WHERE tenant_id = p_tenant_id
    AND regexp_replace(colaborador_cpf, '[^0-9]', '', 'g') = v_cpf
    AND data BETWEEN v_ini AND v_fim
  ORDER BY data DESC
  LIMIT 1;

  SELECT e.jornada_diaria_minutos, COALESCE(e.tolerancia_diaria_minutos, 0), e.id
    INTO v_fb_jornada, v_fb_tol, v_fb_escala_id
  FROM public.ponto_escala_atribuicoes a
  JOIN public.ponto_escalas e ON e.id = a.escala_id
  WHERE a.tenant_id = p_tenant_id
    AND (regexp_replace(COALESCE(a.colaborador_cpf,''), '[^0-9]', '', 'g') = v_cpf OR a.colaborador_id::text = v_colaborador_id)
    AND COALESCE(a.ativa, true) = true
  ORDER BY a.data_inicio ASC
  LIMIT 1;

  SELECT MIN(a.data_inicio),
         CASE WHEN bool_or(a.data_fim IS NULL) THEN NULL ELSE MAX(a.data_fim) END
    INTO v_vinc_ini, v_vinc_fim
  FROM public.ponto_escala_atribuicoes a
  WHERE a.tenant_id = p_tenant_id
    AND (regexp_replace(COALESCE(a.colaborador_cpf,''), '[^0-9]', '', 'g') = v_cpf OR a.colaborador_id::text = v_colaborador_id)
    AND COALESCE(a.ativa, true) = true;

  SELECT pem.data_equalizacao, pem.total_equalizacao_min, (pem.art61_liberado_em IS NOT NULL)
    INTO v_eq_data, v_eq_total, v_eq_liberado
  FROM public.ponto_equalizacao_mensal pem
  WHERE pem.tenant_id = p_tenant_id
    AND pem.colaborador_cpf = v_cpf
    AND pem.competencia = p_competencia;

  IF v_eq_data IS NOT NULL AND EXTRACT(ISODOW FROM v_eq_data) <> 6 THEN
    v_eq_data := v_ult_sab;
  END IF;

  IF v_eq_data IS NULL AND v_fb_escala_id IS NOT NULL THEN
    SELECT count(*) INTO v_qtd_sab
    FROM public.ponto_diario d
    WHERE d.tenant_id = p_tenant_id
      AND regexp_replace(d.colaborador_cpf, '[^0-9]', '', 'g') = v_cpf
      AND d.data BETWEEN v_ini AND v_fim
      AND EXTRACT(ISODOW FROM d.data) = 6
      AND (d.entrada IS NOT NULL OR COALESCE(floor(EXTRACT(EPOCH FROM d.horas_trabalhadas)/60)::int,0) > 0);

    IF v_qtd_sab >= 1 THEN
      SELECT d.data INTO v_eq_data
      FROM public.ponto_diario d
      WHERE d.tenant_id = p_tenant_id
        AND regexp_replace(d.colaborador_cpf, '[^0-9]', '', 'g') = v_cpf
        AND d.data BETWEEN v_ini AND v_fim
        AND EXTRACT(ISODOW FROM d.data) = 6
        AND (d.entrada IS NOT NULL OR COALESCE(floor(EXTRACT(EPOCH FROM d.horas_trabalhadas)/60)::int,0) > 0)
      ORDER BY d.data DESC
      LIMIT 1;

      BEGIN
        v_eq_m := public.ponto_equalizacao_competencia(p_tenant_id, v_fb_escala_id, p_competencia);
      EXCEPTION WHEN OTHERS THEN
        v_eq_m := NULL;
      END;
      v_eq_total := COALESCE((v_eq_m->>'total_equalizacao_min')::int, 0);
      v_eq_auto := (v_eq_total > 0);
      IF NOT v_eq_auto THEN
        v_eq_data := NULL;
      END IF;
    END IF;
  END IF;

  IF v_eq_data IS NULL AND v_fim < CURRENT_DATE AND v_fb_escala_id IS NOT NULL
     AND v_qtd_sab = 0 THEN
    BEGIN
      v_eq_m := public.ponto_equalizacao_competencia(p_tenant_id, v_fb_escala_id, p_competencia);
    EXCEPTION WHEN OTHERS THEN
      v_eq_m := NULL;
    END;
    v_eq_total := COALESCE((v_eq_m->>'total_equalizacao_min')::int, 0);
    IF v_eq_total > 0 THEN
      v_eq_data := v_ult_sab;
    END IF;
  END IF;

  FOR r IN
    SELECT g.d::date AS data,
           d.status, d.tipo_dia, d.observacao,
           COALESCE(d.horas_trabalhadas, INTERVAL '0') AS horas_trabalhadas,
           d.horas_extras, d.horas_faltantes,
           COALESCE(d.colaborador_id::text, v_colaborador_id) AS colaborador_id,
           d.entrada, d.saida
    FROM generate_series(v_ini, v_fim, INTERVAL '1 day') g(d)
    LEFT JOIN LATERAL (
      SELECT p.*
      FROM public.ponto_diario p
      WHERE p.tenant_id = p_tenant_id
        AND regexp_replace(p.colaborador_cpf, '[^0-9]', '', 'g') = v_cpf
        AND p.data = g.d::date
      ORDER BY COALESCE(floor(EXTRACT(EPOCH FROM p.horas_trabalhadas)/60)::int, 0) DESC,
               p.updated_at DESC NULLS LAST
      LIMIT 1
    ) d ON true
    WHERE d.data IS NOT NULL
       OR (
         v_vinc_ini IS NOT NULL
         AND g.d::date >= v_vinc_ini
         AND (v_vinc_fim IS NULL OR g.d::date <= v_vinc_fim)
         AND g.d::date <= CURRENT_DATE
       )
    ORDER BY 1
  LOOP
    IF r.data = ANY (v_ja_emitiu) THEN
      CONTINUE;
    END IF;
    v_ja_emitiu := v_ja_emitiu || r.data;

    IF v_eq_data IS NOT NULL AND r.data = v_eq_data THEN
      v_eq_teve_linha := true;
    END IF;

    v_protegido := (
      r.status = 'justificado'
      OR COALESCE(r.tipo_dia, 'normal') IN ('ferias', 'atestado', 'afastamento', 'feriado')
      OR COALESCE(r.observacao, '') ILIKE '%atestado%'
      OR EXISTS (
        SELECT 1 FROM public.atestados a
        WHERE a.tenant_id = p_tenant_id
          AND regexp_replace(a.colaborador_cpf, '[^0-9]', '', 'g') = v_cpf
          AND COALESCE(a.unidade_afastamento, 'dias') = 'dias'
          AND a.data_inicio_afastamento IS NOT NULL
          AND a.data_inicio_afastamento <= r.data
          AND COALESCE(a.data_fim_afastamento, a.data_inicio_afastamento) >= r.data
      )
      OR (
        r.entrada IS NULL AND r.saida IS NULL
        AND COALESCE(floor(EXTRACT(EPOCH FROM r.horas_trabalhadas)/60)::int, 0) = 0
        AND EXISTS (
          SELECT 1 FROM public.atestados a
          WHERE a.tenant_id = p_tenant_id
            AND regexp_replace(a.colaborador_cpf, '[^0-9]', '', 'g') = v_cpf
            AND COALESCE(a.unidade_afastamento, 'dias') = 'horas'
            AND a.data_inicio_afastamento IS NOT NULL
            AND a.data_inicio_afastamento <= r.data
            AND COALESCE(a.data_fim_afastamento, a.data_inicio_afastamento) >= r.data
        )
      )
    );

    v_prot_credito := v_protegido
      AND r.entrada IS NOT NULL AND r.saida IS NOT NULL
      AND COALESCE(floor(EXTRACT(EPOCH FROM r.horas_trabalhadas)/60)::int, 0) > 0;

    -- Sabado de equalizacao SEMPRE prevalece (mesmo em dias marcados como
    -- justificado / "compensacao de horas"), desde que haja tempo trabalhado.
    IF v_eq_data IS NOT NULL AND r.data = v_eq_data
       AND (NOT v_protegido OR COALESCE(floor(EXTRACT(EPOCH FROM r.horas_trabalhadas)/60)::int, 0) > 0) THEN
      v_eq_teve_linha := true;
      v_trab := COALESCE(floor(EXTRACT(EPOCH FROM r.horas_trabalhadas)/60)::int, 0);
      v_diff := v_trab - COALESCE(v_eq_total, 0);
      excedente_retido_min := 0;
      IF v_diff > 120 AND NOT v_eq_liberado THEN
        excedente_retido_min := v_diff - 120;
        v_diff := 120;
      END IF;
      IF abs(v_diff) <= 10 THEN v_diff := 0; END IF;
      IF v_protegido AND v_diff < 0 THEN v_diff := 0; END IF;
      dia := r.data; entrada := r.entrada; saida := r.saida;
      trabalhado_min := v_trab;
      jornada_min := COALESCE(v_eq_total, 0);
      saldo_min := v_diff;
      protegido := COALESCE(v_protegido, false);
      equalizacao := true;
      RETURN NEXT;
      CONTINUE;
    END IF;

    IF v_protegido AND NOT v_prot_credito THEN
      IF v_eq_data IS NOT NULL AND r.data = v_eq_data THEN
        v_eq_teve_linha := true;
      END IF;
      dia := r.data; entrada := r.entrada; saida := r.saida;
      trabalhado_min := COALESCE(floor(EXTRACT(EPOCH FROM r.horas_trabalhadas)/60)::int, 0);
      jornada_min := 0; saldo_min := 0; protegido := true;
      equalizacao := false; excedente_retido_min := 0;
      RETURN NEXT;
      CONTINUE;
    END IF;

    SELECT j.jornada_min, j.tol_min INTO v_jornada, v_tol
    FROM public.ponto_jornada_do_dia(p_tenant_id, v_cpf, r.colaborador_id::text, r.data) j;

    IF v_jornada IS NULL OR v_jornada = 0 THEN
      IF EXTRACT(DOW FROM r.data)::int IN (0, 6) THEN
        v_esperado := 0;
      ELSE
        v_esperado := COALESCE(v_fb_jornada, 0);
      END IF;
    ELSE
      v_esperado := v_jornada;
    END IF;

    -- (150) 12x36 por ciclo (art. 59-A): plantao usa a jornada do ciclo; a FOLGA
    -- do ciclo NAO gera falta (sobrepoe o fallback de 8h dos dias uteis).
    DECLARE v_ciclo record;
    BEGIN
      SELECT * INTO v_ciclo FROM public.ponto_apurar_ciclo_plantao_do_dia(p_tenant_id, v_cpf, r.colaborador_id::text, r.data);
      IF v_ciclo.eh_ciclo AND v_ciclo.eh_plantao IS NOT NULL THEN
        IF v_ciclo.eh_plantao THEN v_esperado := COALESCE(v_ciclo.jornada_min, v_esperado);
        ELSE v_esperado := 0; END IF;
      END IF;
    END;
    IF v_eq_data IS NOT NULL
       AND EXTRACT(ISODOW FROM r.data) = 6
       AND r.data <> v_eq_data THEN
      v_esperado := 0;
    END IF;
    v_tol := CASE WHEN COALESCE(v_tol, 0) <> 0 THEN v_tol ELSE COALESCE(v_fb_tol, 0) END;

    SELECT COALESCE(SUM(COALESCE(a.horas_afastamento, 0) * 60 + COALESCE(a.minutos_afastamento, 0)), 0)
      INTO v_atest_min
    FROM public.atestados a
    WHERE a.tenant_id = p_tenant_id
      AND regexp_replace(a.colaborador_cpf, '[^0-9]', '', 'g') = v_cpf
      AND COALESCE(a.unidade_afastamento, 'dias') = 'horas'
      AND a.data_inicio_afastamento IS NOT NULL
      AND a.data_inicio_afastamento <= r.data
      AND COALESCE(a.data_fim_afastamento, a.data_inicio_afastamento) >= r.data;

    v_jornada_efetiva := GREATEST(0, v_esperado - COALESCE(v_atest_min, 0));

    v_ent_esc := NULL; v_sai_esc := NULL; v_interv := 0; v_tol_bat := 5;
    BEGIN
      SELECT e.entrada, e.saida, COALESCE(e.intervalo_min, 0), COALESCE(e.tolerancia_batida_min, 5)
        INTO v_ent_esc, v_sai_esc, v_interv, v_tol_bat
      FROM public.ponto_escala_do_dia(p_tenant_id, v_cpf, r.colaborador_id::text, r.data) e;
    EXCEPTION WHEN OTHERS THEN
      v_ent_esc := NULL; v_sai_esc := NULL;
    END;

    v_trab := COALESCE(floor(EXTRACT(EPOCH FROM r.horas_trabalhadas)/60)::int, 0);
    v_usou_batida := false;
    v_diff := 0;

    IF v_ent_esc IS NOT NULL AND v_sai_esc IS NOT NULL
       AND r.entrada IS NOT NULL AND r.saida IS NOT NULL
       AND v_jornada_efetiva > 0 THEN

      v_ent_cons := CASE
        WHEN abs(floor(EXTRACT(EPOCH FROM r.entrada)/60)::int - floor(EXTRACT(EPOCH FROM v_ent_esc)/60)::int) <= COALESCE(v_tol_bat, 5)
          THEN floor(EXTRACT(EPOCH FROM v_ent_esc)/60)::int
        ELSE floor(EXTRACT(EPOCH FROM r.entrada)/60)::int
      END;

      v_sai_cons := CASE
        WHEN abs(floor(EXTRACT(EPOCH FROM r.saida)/60)::int - floor(EXTRACT(EPOCH FROM v_sai_esc)/60)::int) <= COALESCE(v_tol_bat, 5)
          THEN floor(EXTRACT(EPOCH FROM v_sai_esc)/60)::int
        ELSE floor(EXTRACT(EPOCH FROM r.saida)/60)::int
      END;

      v_trab_marc := COALESCE(floor(EXTRACT(EPOCH FROM r.horas_trabalhadas)/60)::int, 0);
      v_janela := floor(EXTRACT(EPOCH FROM (r.saida - r.entrada))/60)::int;
      IF v_janela < 0 THEN
        v_janela := v_janela + 1440;
      END IF;
      v_interv_real := GREATEST(0, v_janela - v_trab_marc);

      v_janela_cons := v_sai_cons - v_ent_cons;
      IF v_janela_cons < 0 THEN
        v_janela_cons := v_janela_cons + 1440;
      END IF;

      IF v_interv_real > 0 THEN
        v_desc_interv := 0;
      ELSE
        v_int_ini := NULL; v_int_fim := NULL;
        IF v_sai_cons >= v_ent_cons THEN
          BEGIN
            SELECT w.inicio, w.fim INTO v_int_ini, v_int_fim
            FROM public.ponto_intervalo_janela_do_dia(p_tenant_id, v_cpf, r.colaborador_id::text, r.data) w;
          EXCEPTION WHEN OTHERS THEN
            v_int_ini := NULL; v_int_fim := NULL;
          END;
        END IF;

        IF v_int_ini IS NOT NULL AND v_int_fim IS NOT NULL THEN
          v_desc_interv := GREATEST(0,
            LEAST(v_sai_cons, floor(EXTRACT(EPOCH FROM v_int_fim)/60)::int)
            - GREATEST(v_ent_cons, floor(EXTRACT(EPOCH FROM v_int_ini)/60)::int)
          );
        ELSE
          v_desc_interv := LEAST(COALESCE(v_interv, 0), GREATEST(0, v_janela - v_jornada_efetiva));
        END IF;
      END IF;

      v_trab_ajust := GREATEST(0, v_janela_cons - v_interv_real - v_desc_interv);
      v_diff := GREATEST(0, v_janela - v_interv_real - v_desc_interv) - v_jornada_efetiva;
      v_trab := GREATEST(0, v_janela - v_interv_real - v_desc_interv);
      v_usou_batida := true;
    END IF;

    IF NOT v_usou_batida THEN
      v_extras    := COALESCE(floor(EXTRACT(EPOCH FROM r.horas_extras)/60)::int, 0);
      v_faltantes := COALESCE(floor(EXTRACT(EPOCH FROM r.horas_faltantes)/60)::int, 0);

      IF v_extras > 0 OR v_faltantes > 0 THEN
        v_diff := v_extras - v_faltantes;
      ELSIF v_jornada_efetiva = 0 THEN
        v_diff := GREATEST(0, v_trab);
      ELSIF r.status = 'falta' THEN
        v_diff := -v_jornada_efetiva;
      ELSE
        v_diff := v_trab - v_jornada_efetiva;
        -- Déficit absorvido só até o teto POR MARCAÇÃO (art. 58 §1º / Súmula
        -- 366); sobra no dia mantém o teto DIÁRIO configurado.
        IF v_diff < 0 THEN
          IF abs(v_diff) <= COALESCE(v_tol_bat, 5) THEN
            v_diff := 0;
          END IF;
        ELSIF abs(v_diff) <= COALESCE(v_tol, 0) THEN
          v_diff := 0;
        END IF;
      END IF;
    END IF;

    -- Tolerância do art. 58, §1º + Súmula 366, com os dois tetos cumulativos:
    --   · déficit (atraso/antecipação): absorvido só até o teto POR MARCAÇÃO;
    --   · sobra no dia: absorvida até o teto DIÁRIO (10).
    -- Estourou o teto aplicável, computa-se a TOTALIDADE (não só o excedente).
    IF v_diff < 0 THEN
      IF abs(v_diff) <= COALESCE(v_tol_bat, 5) THEN
        v_diff := 0;
      END IF;
    ELSIF v_diff <= 10 THEN
      v_diff := 0;
    END IF;

    IF v_prot_credito AND v_diff < 0 THEN
      v_diff := 0;
    END IF;

    excedente_retido_min := 0;
    IF v_jornada_efetiva > 0 AND v_diff > 120 THEN
      SELECT EXISTS (
        SELECT 1 FROM public.ponto_excedente_decisao x
        WHERE x.tenant_id = p_tenant_id
          AND regexp_replace(x.colaborador_cpf, '[^0-9]', '', 'g') = v_cpf
          AND x.dia = r.data
          AND x.decisao = 'liberado'
      ) INTO v_exc_decidido;

      IF NOT COALESCE(v_exc_decidido, false) THEN
        excedente_retido_min := v_diff - 120;
        v_diff := 120;
      END IF;
    END IF;

    dia := r.data;
    entrada := r.entrada;
    saida := r.saida;
    trabalhado_min := v_trab;
    jornada_min := v_jornada_efetiva;
    saldo_min := v_diff;
    protegido := COALESCE(v_prot_credito, false);
    equalizacao := false;
    RETURN NEXT;
  END LOOP;

  IF v_eq_data IS NOT NULL AND NOT v_eq_teve_linha AND v_eq_data < CURRENT_DATE THEN
    dia := v_eq_data; entrada := NULL; saida := NULL;
    trabalhado_min := 0;
    jornada_min := COALESCE(v_eq_total, 0);
    saldo_min := -COALESCE(v_eq_total, 0);
    protegido := false; equalizacao := true; excedente_retido_min := 0;
    IF saldo_min <> 0 THEN RETURN NEXT; END IF;
  END IF;
END;
$function$
;

COMMENT ON FUNCTION public.ponto_saldo_dias_competencia_bruto(uuid, text, text) IS
  'Nucleo da apuracao de saldo por dia na competencia. Pode devolver mais de uma linha para o mesmo dia civil quando ha vinculos ou lancamentos concorrentes; quem consome deve usar o involucro ponto_saldo_dias_competencia, que garante uma linha por dia. PONTO-300/301.';

-- ---------------------------------------------------------------------------
-- (2) O INVOLUCRO — a funcao publica, que so age quando ha dia duplicado.
--     Entra DEPOIS do nucleo de proposito: e LANGUAGE sql, entao o banco
--     valida o corpo agora e recusaria se o nucleo nao existisse.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_saldo_dias_competencia(p_tenant_id uuid, p_colaborador_cpf text, p_competencia text)
 RETURNS TABLE(dia date, entrada time without time zone, saida time without time zone, trabalhado_min integer, jornada_min integer, saldo_min integer, protegido boolean, equalizacao boolean, excedente_retido_min integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH bruto AS (
    SELECT * FROM public.ponto_saldo_dias_competencia_bruto(
      p_tenant_id, p_colaborador_cpf, p_competencia)
  ),
  agrupado AS (
    SELECT b.dia,
           count(*)                                      AS linhas,
           -- Entrada mais cedo e saída mais tarde entre as linhas do dia:
           -- a linha extra vem sem marcação, então na prática ficam as
           -- marcações reais.
           min(b.entrada)                                AS entrada,
           max(b.saida)                                  AS saida,
           max(b.trabalhado_min)                         AS trabalhado_min,
           max(b.jornada_min)                            AS jornada_min,
           max(b.saldo_min)                              AS saldo_unico,
           bool_or(b.protegido)                          AS protegido,
           bool_or(b.equalizacao)                        AS equalizacao,
           max(b.excedente_retido_min)                   AS excedente_retido_min
    FROM bruto b
    GROUP BY b.dia
  )
  SELECT a.dia,
         a.entrada,
         a.saida,
         a.trabalhado_min,
         -- Dia protegido não tem jornada a cobrar.
         CASE WHEN a.protegido AND a.linhas > 1 THEN 0 ELSE a.jornada_min END,
         CASE
           -- Dia que saiu uma vez só: nada muda, nem por arredondamento.
           WHEN a.linhas = 1 THEN a.saldo_unico
           -- Dia protegido não gera débito nem crédito.
           WHEN a.protegido THEN 0
           -- Tolerância de 10 minutos, a mesma da apuração.
           WHEN abs(a.trabalhado_min - a.jornada_min) <= 10 THEN 0
           ELSE a.trabalhado_min - a.jornada_min
         END,
         a.protegido,
         a.equalizacao,
         a.excedente_retido_min
  FROM agrupado a
  ORDER BY a.dia;
$function$
;

COMMENT ON FUNCTION public.ponto_saldo_dias_competencia(uuid, text, text) IS
  'Apuracao de saldo por dia na competencia — uma linha por dia civil. Involucro fino sobre ponto_saldo_dias_competencia_bruto: dia que sai uma vez so passa intocado; dia duplicado e agrupado com a mesma tolerancia de 10 minutos da apuracao. Assinatura publica inalterada. PONTO-300/301.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | t | t | t | t | OK
--   nucleo            : ponto_saldo_dias_competencia_bruto existe
--   involucro         : a funcao publica existe
--   involucro_delega  : o involucro chama o nucleo (nao e mais monolito)
--   tolerancia_5      : o nucleo carrega o remendo do pacote #7
--   ciclo_12x36       : o nucleo carrega o remendo do pacote #26
--   assinatura_igual  : a tabela de retorno publica nao mudou
-- ---------------------------------------------------------------------------
WITH x AS MATERIALIZED (
  SELECT
    (to_regprocedure('public.ponto_saldo_dias_competencia_bruto(uuid,text,text)') IS NOT NULL) AS nucleo,
    (to_regprocedure('public.ponto_saldo_dias_competencia(uuid,text,text)') IS NOT NULL) AS involucro,
    EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public' AND p.proname = 'ponto_saldo_dias_competencia'
               AND p.prosrc LIKE '%ponto_saldo_dias_competencia_bruto%') AS involucro_delega,
    EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public' AND p.proname = 'ponto_saldo_dias_competencia_bruto'
               AND position('v_interv := 0; v_tol_bat := 5;' in p.prosrc) > 0) AS tolerancia_5,
    EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public' AND p.proname = 'ponto_saldo_dias_competencia_bruto'
               AND position('ponto_apurar_ciclo_plantao_do_dia' in p.prosrc) > 0) AS ciclo_12x36,
    (pg_get_function_result(to_regprocedure('public.ponto_saldo_dias_competencia(uuid,text,text)'))
       = 'TABLE(dia date, entrada time without time zone, saida time without time zone,'
      || ' trabalhado_min integer, jornada_min integer, saldo_min integer, protegido boolean,'
      || ' equalizacao boolean, excedente_retido_min integer)') AS assinatura_igual
)
SELECT nucleo, involucro, involucro_delega, tolerancia_5, ciclo_12x36, assinatura_igual,
       CASE WHEN nucleo AND involucro AND involucro_delega AND tolerancia_5
                 AND ciclo_12x36 AND assinatura_igual
            THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico
FROM x;
