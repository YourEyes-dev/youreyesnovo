-- =========================================================
-- Férias — média das variáveis do art. 142 apurada da folha
--
-- PROBLEMA: a média das variáveis era um campo digitado, que nascia
-- zerado (FeriasTab do Financeiro). Quem recebe hora extra habitual,
-- comissão ou adicional leva a MÉDIA para as férias; calcular só o
-- fixo paga a menos, e sem memória nada se audita.
--
-- ENTREGA:
--   1) parâmetros da média em ferias_config (com vigência), por empresa;
--   2) ferias_media_variaveis(...) — apura a média a partir dos
--      lançamentos da folha, considerando apenas as rubricas marcadas
--      com incide_ferias, e devolve a MEMÓRIA (competência a competência)
--      junto com o valor.
--
-- DECISÕES DO DONO DO PRODUTO (01/09/2026):
--   • base: os 12 meses do próprio período aquisitivo;
--   • divisor: os meses do período (mês sem variável entra como zero),
--     limitado aos meses em que o colaborador teve folha — quem foi
--     admitido no meio não é dividido por 12.
--   Ambas ficam parametrizáveis por empresa, com a decisão acima como
--   padrão, e a vigência registrada para o cálculo não mudar o passado.
--
-- Requisitos YE-DP-FERIAS-001: RF-004, RN-007, CA-006, RNF-001/002/008.
-- Caso de teste: FERIAS-033.
-- Somente leitura sobre a folha: nada é gravado por esta função.
-- =========================================================

SET lock_timeout = '10s';

-- ── 1. Parâmetros da média (por empresa, com vigência) ────────────────────
ALTER TABLE public.ferias_config
    ADD COLUMN IF NOT EXISTS media_base TEXT NOT NULL DEFAULT 'aquisitivo',
    ADD COLUMN IF NOT EXISTS media_divisor TEXT NOT NULL DEFAULT 'meses_do_periodo',
    ADD COLUMN IF NOT EXISTS media_vigencia_inicio DATE NOT NULL DEFAULT '2026-01-01';

DO $ck$
BEGIN
    ALTER TABLE public.ferias_config
        ADD CONSTRAINT ferias_config_media_base_ck
        CHECK (media_base IN ('aquisitivo', 'anteriores_ao_gozo'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

DO $ck$
BEGIN
    ALTER TABLE public.ferias_config
        ADD CONSTRAINT ferias_config_media_divisor_ck
        CHECK (media_divisor IN ('meses_do_periodo', 'meses_com_valor'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

COMMENT ON COLUMN public.ferias_config.media_base IS
    'Janela de apuracao da media do art. 142: aquisitivo (12 meses do proprio periodo) ou anteriores_ao_gozo (12 competencias fechadas antes do inicio do gozo).';
COMMENT ON COLUMN public.ferias_config.media_divisor IS
    'meses_do_periodo: divide pelos meses da janela em que houve folha (mes sem variavel entra como zero). meses_com_valor: divide so pelos meses com valor.';
COMMENT ON COLUMN public.ferias_config.media_vigencia_inicio IS
    'Desde quando estes parametros valem. Fica gravado na memoria de calculo para o valor ser reproduzivel depois.';

-- ── 2. Apuração da média ──────────────────────────────────────────────────
-- Devolve a média E a memória (competência a competência, rubrica a rubrica).
-- SECURITY INVOKER de propósito: quem chama só enxerga a folha que a RLS
-- do seu tenant já permitiria enxergar.
CREATE OR REPLACE FUNCTION public.ferias_media_variaveis(
    p_tenant            UUID,
    p_cpf               TEXT,
    p_aquisitivo_inicio DATE,
    p_aquisitivo_fim    DATE,
    p_inicio_gozo       DATE DEFAULT NULL,
    p_empresa           UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    v_base          TEXT := 'aquisitivo';
    v_divisor_regra TEXT := 'meses_do_periodo';
    v_vigencia      DATE := '2026-01-01';
    v_cpf           TEXT := regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
    v_ini           TEXT;   -- competência inicial da janela (YYYY-MM)
    v_fim           TEXT;   -- competência final da janela (YYYY-MM)
    v_total         NUMERIC(14,2) := 0;
    v_meses_folha   INTEGER := 0;
    v_meses_valor   INTEGER := 0;
    v_divisor       INTEGER := 0;
    v_media         NUMERIC(14,2) := 0;
    v_rubricas_mkd  INTEGER := 0;
    v_competencias  JSONB := '[]'::jsonb;
    v_rubricas      JSONB := '[]'::jsonb;
    v_avisos        TEXT[] := ARRAY[]::TEXT[];
BEGIN
    IF p_tenant IS NULL OR v_cpf = '' OR p_aquisitivo_inicio IS NULL OR p_aquisitivo_fim IS NULL THEN
        RETURN jsonb_build_object(
            'media', 0, 'total', 0, 'meses_divisor', 0,
            'avisos', to_jsonb(ARRAY['Informe colaborador e período aquisitivo para apurar a média.'])
        );
    END IF;

    -- Parâmetros da empresa; sem registro da empresa, cai no geral do tenant.
    SELECT c.media_base, c.media_divisor, c.media_vigencia_inicio
      INTO v_base, v_divisor_regra, v_vigencia
      FROM public.ferias_config c
     WHERE c.tenant_id = p_tenant
       AND (c.empresa_id = p_empresa OR (p_empresa IS NULL AND c.empresa_id IS NULL))
     LIMIT 1;

    IF NOT FOUND THEN
        SELECT c.media_base, c.media_divisor, c.media_vigencia_inicio
          INTO v_base, v_divisor_regra, v_vigencia
          FROM public.ferias_config c
         WHERE c.tenant_id = p_tenant AND c.empresa_id IS NULL
         LIMIT 1;
    END IF;

    v_base          := coalesce(v_base, 'aquisitivo');
    v_divisor_regra := coalesce(v_divisor_regra, 'meses_do_periodo');
    v_vigencia      := coalesce(v_vigencia, DATE '2026-01-01');

    -- Janela de competências.
    IF v_base = 'anteriores_ao_gozo' AND p_inicio_gozo IS NOT NULL THEN
        v_fim := to_char((date_trunc('month', p_inicio_gozo) - INTERVAL '1 month'), 'YYYY-MM');
        v_ini := to_char((date_trunc('month', p_inicio_gozo) - INTERVAL '12 months'), 'YYYY-MM');
    ELSE
        IF v_base = 'anteriores_ao_gozo' THEN
            v_avisos := array_append(v_avisos, 'Sem data de início do gozo: a média foi apurada pelo período aquisitivo.');
            v_base := 'aquisitivo';
        END IF;
        v_ini := to_char(p_aquisitivo_inicio, 'YYYY-MM');
        v_fim := to_char(p_aquisitivo_fim,    'YYYY-MM');
    END IF;

    -- A empresa marcou alguma rubrica como integrante das férias?
    SELECT count(*) INTO v_rubricas_mkd
      FROM public.folha_rubricas r
     WHERE r.tenant_id = p_tenant AND r.incide_ferias AND r.ativa;

    IF v_rubricas_mkd = 0 THEN
        v_avisos := array_append(v_avisos, 'Nenhuma rubrica está marcada como integrante das férias no cadastro de rubricas — a média sai zero até alguém marcar (hora extra, comissão, adicionais).');
    END IF;

    -- Lançamentos das rubricas variáveis, competência a competência.
    WITH janela AS MATERIALIZED (
        SELECT l.valor, pe.competencia,
               coalesce(l.rubrica_codigo, r.codigo_interno) AS codigo,
               coalesce(r.descricao, l.rubrica_descricao)   AS descricao
          FROM public.folha_lancamentos l
          JOIN public.folha_periodos pe ON pe.id = l.periodo_id
          JOIN public.folha_rubricas  r ON r.id = l.rubrica_id
         WHERE l.tenant_id = p_tenant
           AND regexp_replace(coalesce(l.colaborador_cpf, ''), '\D', '', 'g') = v_cpf
           AND pe.competencia BETWEEN v_ini AND v_fim
           AND r.incide_ferias
           AND r.ativa
           AND r.tipo = 'PROVENTO'
    ),
    por_competencia AS MATERIALIZED (
        SELECT competencia, sum(valor)::NUMERIC(14,2) AS valor
          FROM janela GROUP BY competencia
    ),
    por_rubrica AS MATERIALIZED (
        SELECT codigo, descricao, sum(valor)::NUMERIC(14,2) AS valor
          FROM janela GROUP BY codigo, descricao
    )
    SELECT
        coalesce((SELECT sum(valor) FROM por_competencia), 0),
        coalesce((SELECT count(*) FROM por_competencia WHERE valor > 0), 0),
        coalesce((SELECT jsonb_agg(jsonb_build_object('competencia', competencia, 'valor', valor)
                                   ORDER BY competencia) FROM por_competencia), '[]'::jsonb),
        coalesce((SELECT jsonb_agg(jsonb_build_object('codigo', codigo, 'descricao', descricao, 'valor', valor)
                                   ORDER BY valor DESC) FROM por_rubrica), '[]'::jsonb)
      INTO v_total, v_meses_valor, v_competencias, v_rubricas;

    -- Meses em que o colaborador teve folha na janela — é o divisor honesto
    -- para quem foi admitido no meio do período.
    SELECT count(DISTINCT pe.competencia) INTO v_meses_folha
      FROM public.folha_itens i
      JOIN public.folha_periodos pe ON pe.id = i.periodo_id
     WHERE i.tenant_id = p_tenant
       AND regexp_replace(coalesce(i.colaborador_cpf, ''), '\D', '', 'g') = v_cpf
       AND pe.competencia BETWEEN v_ini AND v_fim;

    IF v_divisor_regra = 'meses_com_valor' THEN
        v_divisor := v_meses_valor;
    ELSE
        -- Sem folha registrada na janela, ao menos não dividimos por zero:
        -- usa os meses em que houve variável.
        v_divisor := CASE WHEN v_meses_folha > 0 THEN v_meses_folha ELSE v_meses_valor END;
        IF v_meses_folha = 0 AND v_meses_valor > 0 THEN
            v_avisos := array_append(v_avisos, 'Não há folha fechada do colaborador nesta janela; a média foi dividida pelos meses com valor.');
        END IF;
    END IF;

    IF v_divisor > 0 THEN
        v_media := round(v_total / v_divisor, 2);
    END IF;

    IF v_total = 0 AND v_rubricas_mkd > 0 THEN
        v_avisos := array_append(v_avisos, 'Nenhum lançamento de rubrica variável encontrado na janela — confira se a folha do período foi importada.');
    END IF;

    RETURN jsonb_build_object(
        'media',              v_media,
        'total',              v_total,
        'meses_divisor',      v_divisor,
        'meses_com_folha',    v_meses_folha,
        'meses_com_valor',    v_meses_valor,
        'base',               v_base,
        'divisor_regra',      v_divisor_regra,
        'janela_inicio',      v_ini,
        'janela_fim',         v_fim,
        'parametros_vigencia', v_vigencia,
        'fundamento',         'CLT art. 142',
        'apurado_em',         now(),
        'competencias',       v_competencias,
        'rubricas',           v_rubricas,
        'avisos',             to_jsonb(v_avisos)
    );
END $fn$;

COMMENT ON FUNCTION public.ferias_media_variaveis(UUID, TEXT, DATE, DATE, DATE, UUID) IS
    'Media das variaveis do art. 142 apurada dos lancamentos da folha (so rubricas com incide_ferias), com a memoria competencia a competencia. Somente leitura.';

GRANT EXECUTE ON FUNCTION public.ferias_media_variaveis(UUID, TEXT, DATE, DATE, DATE, UUID) TO authenticated;

-- ── 3. Origem da média no cálculo gravado ─────────────────────────────────
-- 'apurada' = veio desta função; 'manual' = o DP digitou/ajustou.
-- A memória completa continua dentro de memoria_calculo.
ALTER TABLE public.folha_ferias_calculo
    ADD COLUMN IF NOT EXISTS media_origem TEXT NOT NULL DEFAULT 'manual';

DO $ck$
BEGIN
    ALTER TABLE public.folha_ferias_calculo
        ADD CONSTRAINT folha_ferias_calculo_media_origem_ck
        CHECK (media_origem IN ('apurada', 'manual', 'apurada_ajustada'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

COMMENT ON COLUMN public.folha_ferias_calculo.media_origem IS
    'De onde veio a media das variaveis: apurada (ferias_media_variaveis), apurada_ajustada (apurada e depois editada) ou manual.';
