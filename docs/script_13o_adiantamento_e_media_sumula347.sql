-- =========================================================
-- SCRIPT DE ENTREGA — 13º Salário: política do adiantamento
-- configurável e média das horas extras pela Súmula 347 do TST
--
-- PRÉ-REQUISITO: rodar depois dos scripts da Entrega 1 e da Entrega 2.
--
-- O QUE ESTE SCRIPT FAZ:
--   * o parâmetro adiantamento_base passa a VALER (era documentado e
--     inerte): a empresa escolhe entre metade do 13º proporcional
--     (prática de mercado) e metade da remuneração do mês anterior
--     (letra do art. 2º da Lei 4.749/1965). O 13º total é o mesmo nas
--     duas; muda quanto entra em novembro;
--   * a média das horas extras passa a seguir a Súmula 347 do TST —
--     quantidade FÍSICA de horas do ponto x valor da hora VIGENTE —,
--     com queda automática para a média de valores quando não há ponto
--     no ano. Quem teve aumento salarial deixa de receber a menos;
--   * folha_rubricas ganha he_do_ponto, para a hora extra não ser
--     contada duas vezes (uma pelo ponto, outra pelo valor pago);
--   * CORRIGE UM DEFEITO: decimo_terceiro_config aceitava DUAS linhas
--     de configuração geral da mesma empresa, porque no PostgreSQL dois
--     NULL não são iguais e a restrição usava empresa_id. Com duas
--     linhas, o cálculo passava a usar uma qualquer — em silêncio.
--
-- ATENÇÃO — ESTE SCRIPT MUDA VALORES: a média das horas extras passa a
-- ser a física por padrão. Para quem teve aumento salarial no ano, o 13º
-- sobe (é o valor que a Súmula 347 sustenta). Confira com a contabilidade
-- e refaça os cálculos ainda não aprovados.
--
-- APAGA ALGO? Só linhas de configuração DUPLICADAS, e antes copia todas
-- para backup_decimo_terceiro_config_20260904 (a mais recente de cada
-- empresa é mantida). Nenhum cálculo de 13º é tocado.
--
-- Idempotente. Rodar no SQL Editor de PRODUÇÃO, de uma vez só.
-- =========================================================

-- Requisitos YE-DP-13-001: RF-002, RN-002, RN-003, CA-003, [VAL] das
-- Súmulas do TST e da política de adiantamento.
-- =========================================================

SET lock_timeout = '10s';

-- ── Parâmetros novos ──────────────────────────────────────────────────
ALTER TABLE public.decimo_terceiro_config
    ADD COLUMN IF NOT EXISTS media_horas_extras TEXT NOT NULL DEFAULT 'fisica'
        CHECK (media_horas_extras IN ('fisica', 'valores')),
    ADD COLUMN IF NOT EXISTS divisor_horas_mes NUMERIC(6,2) NOT NULL DEFAULT 220
        CHECK (divisor_horas_mes > 0);

COMMENT ON COLUMN public.decimo_terceiro_config.media_horas_extras IS
    'fisica (padrao): media da QUANTIDADE de horas do ponto x valor da hora vigente (Sumula 347 do TST). valores: media dos valores pagos no ano.';
COMMENT ON COLUMN public.decimo_terceiro_config.divisor_horas_mes IS
    'Divisor mensal para achar o valor da hora (salario / divisor). 220 para jornada de 44h semanais.';

-- Marca a rubrica alimentada pelo ponto, para a media fisica nao
-- somar a mesma hora extra duas vezes.
ALTER TABLE public.folha_rubricas
    ADD COLUMN IF NOT EXISTS he_do_ponto BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.folha_rubricas.he_do_ponto IS
    'TRUE quando a rubrica e hora extra apurada pelo ponto. A media do 13o a trata pela media fisica (Sumula 347) em vez da media de valores.';

-- O catálogo padrão da casa: 1003 e 1004 são as horas extras.
UPDATE public.folha_rubricas
   SET he_do_ponto = TRUE
 WHERE codigo_interno IN ('1003', '1004')
   AND NOT he_do_ponto;

-- ── Média física das horas extras (Súmula 347) ────────────────────────
CREATE OR REPLACE FUNCTION public.decimo_terceiro_media_horas_extras(
    p_tenant   UUID,
    p_cpf      TEXT,
    p_ano      INT,
    p_avos     INT,
    p_salario  NUMERIC,
    p_empresa  UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    v_cpf       TEXT := regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
    v_divisor   NUMERIC(6,2) := 220;
    v_pct50     NUMERIC(6,2) := 50;
    v_pct100    NUMERIC(6,2) := 100;
    v_min50     INT := 0;
    v_min100    INT := 0;
    v_meses     INT := 0;
    v_hora      NUMERIC(14,4);
    v_valor     NUMERIC(14,2) := 0;
    v_divide_por INT;
BEGIN
    IF p_tenant IS NULL OR v_cpf = '' OR p_ano IS NULL THEN
        RETURN jsonb_build_object('aplicavel', false,
                                  'motivo', 'Chamada incompleta.');
    END IF;

    SELECT c.divisor_horas_mes INTO v_divisor
      FROM public.decimo_terceiro_config c
     WHERE c.tenant_id = p_tenant
       AND (c.empresa_id = p_empresa OR (p_empresa IS NULL AND c.empresa_id IS NULL))
     LIMIT 1;
    v_divisor := coalesce(v_divisor, 220);

    -- Percentuais da CCT vigente no ano-base; sem CCT, os legais.
    SELECT coalesce(k.he_percentual_dia_util, 50), coalesce(k.he_percentual_domingos, 100)
      INTO v_pct50, v_pct100
      FROM public.ponto_cct_config k
     WHERE k.tenant_id = p_tenant
       AND coalesce(k.ativo, true)
       AND k.vigencia_inicio <= make_date(p_ano, 12, 31)
       AND (k.vigencia_fim IS NULL OR k.vigencia_fim >= make_date(p_ano, 1, 1))
     ORDER BY k.vigencia_inicio DESC
     LIMIT 1;
    v_pct50  := coalesce(v_pct50, 50);
    v_pct100 := coalesce(v_pct100, 100);

    -- Quantidade FÍSICA de horas extras no ano-base.
    SELECT coalesce(sum(p.horas_extras_50_minutos), 0),
           coalesce(sum(p.horas_extras_100_minutos), 0),
           count(DISTINCT date_trunc('month', p.data))
      INTO v_min50, v_min100, v_meses
      FROM public.ponto_diario p
     WHERE p.tenant_id = p_tenant
       AND regexp_replace(coalesce(p.colaborador_cpf, ''), '\D', '', 'g') = v_cpf
       AND p.data BETWEEN make_date(p_ano, 1, 1) AND make_date(p_ano, 12, 31);

    IF v_meses = 0 OR (v_min50 = 0 AND v_min100 = 0) THEN
        RETURN jsonb_build_object(
            'aplicavel', false,
            'motivo', CASE WHEN v_meses = 0
                           THEN 'Sem registro de ponto no ano-base — média física não se aplica.'
                           ELSE 'Ponto sem horas extras no ano-base.' END,
            'meses_com_ponto', v_meses);
    END IF;

    -- Valor da hora VIGENTE (época do pagamento), não a histórica.
    v_hora := round(coalesce(p_salario, 0) / v_divisor, 4);

    -- Divide pelos avos: é a mesma régua do restante do 13º.
    v_divide_por := coalesce(nullif(p_avos, 0), v_meses);

    v_valor := round(
        ( (v_min50  / 60.0) * v_hora * (1 + v_pct50  / 100.0)
        + (v_min100 / 60.0) * v_hora * (1 + v_pct100 / 100.0)
        ) / v_divide_por, 2);

    RETURN jsonb_build_object(
        'aplicavel',       true,
        'media',           v_valor,
        'horas_50',        round(v_min50  / 60.0, 2),
        'horas_100',       round(v_min100 / 60.0, 2),
        'percentual_50',   v_pct50,
        'percentual_100',  v_pct100,
        'valor_hora',      v_hora,
        'divisor_horas_mes', v_divisor,
        'meses_com_ponto', v_meses,
        'dividido_por',    v_divide_por,
        'fundamento',      'Sumula 347 do TST: media fisica das horas x salario-hora da epoca do pagamento');
END $fn$;

COMMENT ON FUNCTION public.decimo_terceiro_media_horas_extras(UUID, TEXT, INT, INT, NUMERIC, UUID) IS
    'Media das horas extras do 13o pela Sumula 347 do TST: quantidade fisica de horas do ponto x valor da hora vigente. Somente leitura.';

GRANT EXECUTE ON FUNCTION public.decimo_terceiro_media_horas_extras(UUID, TEXT, INT, INT, NUMERIC, UUID) TO authenticated;

-- ── A média de valores aprende a deixar as horas extras de fora ──────
DROP FUNCTION IF EXISTS public.decimo_terceiro_media_variaveis(UUID, TEXT, INT, INT, UUID);

CREATE OR REPLACE FUNCTION public.decimo_terceiro_media_variaveis(
    p_tenant  UUID,
    p_cpf     TEXT,
    p_ano     INT,
    p_avos    INT DEFAULT NULL,
    p_empresa UUID DEFAULT NULL,
    p_excluir_he_do_ponto BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    v_cpf          TEXT := regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
    v_divisor_regra TEXT := 'avos_apurados';
    v_inclui_prot  BOOLEAN := false;
    v_vigencia     DATE := '2026-01-01';
    v_ini          TEXT;
    v_fim          TEXT;
    v_total        NUMERIC(14,2) := 0;
    v_meses_valor  INT := 0;
    v_divisor      INT := 0;
    v_media        NUMERIC(14,2) := 0;
    v_rubricas_mkd INT := 0;
    v_competencias JSONB := '[]'::jsonb;
    v_rubricas     JSONB := '[]'::jsonb;
    v_protegidas   TEXT;
    v_avisos       TEXT[] := ARRAY[]::TEXT[];
BEGIN
    IF p_tenant IS NULL OR v_cpf = '' OR p_ano IS NULL THEN
        IF p_tenant IS NULL THEN
            v_avisos := array_append(v_avisos, 'Empresa não informada na consulta.');
        END IF;
        IF v_cpf = '' THEN
            v_avisos := array_append(v_avisos,
                format('CPF não informado ou sem dígito algum (recebido: %L). Informe o CPF do colaborador.', coalesce(p_cpf, '')));
        END IF;
        IF p_ano IS NULL THEN
            v_avisos := array_append(v_avisos, 'Ano-base não informado na consulta.');
        END IF;
        RETURN jsonb_build_object(
            'media', 0, 'total', 0, 'meses_divisor', 0,
            'avisos', to_jsonb(v_avisos)
        );
    END IF;

    SELECT c.media_divisor, c.parametros_vigencia_inicio, c.media_inclui_protegidas
      INTO v_divisor_regra, v_vigencia, v_inclui_prot
      FROM public.decimo_terceiro_config c
     WHERE c.tenant_id = p_tenant
       AND (c.empresa_id = p_empresa OR (p_empresa IS NULL AND c.empresa_id IS NULL))
     LIMIT 1;

    IF NOT FOUND THEN
        SELECT c.media_divisor, c.parametros_vigencia_inicio, c.media_inclui_protegidas
          INTO v_divisor_regra, v_vigencia, v_inclui_prot
          FROM public.decimo_terceiro_config c
         WHERE c.tenant_id = p_tenant AND c.empresa_id IS NULL
         LIMIT 1;
    END IF;

    v_divisor_regra := coalesce(v_divisor_regra, 'avos_apurados');
    v_inclui_prot   := coalesce(v_inclui_prot, false);
    v_vigencia      := coalesce(v_vigencia, DATE '2026-01-01');

    v_ini := to_char(make_date(p_ano, 1, 1),  'YYYY-MM');
    v_fim := to_char(make_date(p_ano, 12, 1), 'YYYY-MM');

    -- A empresa marcou alguma rubrica como integrante do 13º?
    SELECT count(*)::INT INTO v_rubricas_mkd
      FROM public.folha_rubricas r
     WHERE r.tenant_id = p_tenant AND r.incide_13 AND r.ativa
       AND (v_inclui_prot OR NOT r.protegida)
       AND (NOT p_excluir_he_do_ponto OR NOT r.he_do_ponto);

    IF v_rubricas_mkd = 0 THEN
        v_avisos := array_append(v_avisos,
            'Nenhuma rubrica está marcada como integrante do 13º no cadastro de rubricas — a média sai zero até alguém marcar (hora extra, comissão, adicionais).');
    END IF;

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
           AND r.incide_13
           AND r.ativa
           AND r.tipo = 'PROVENTO'
           -- Decisao do dono do produto (03/09/2026): rubrica PROTEGIDA
           -- (Salario Base, INSS, IRRF) NAO entra na media. A media e das
           -- variaveis; o salario fixo ja entra como remuneracao base, e
           -- soma-lo aqui pagaria o 13o dobrado. Parametrizavel por empresa.
           AND (v_inclui_prot OR NOT r.protegida)
           -- Hora extra alimentada pelo ponto sai daqui quando a media
           -- fisica da Sumula 347 vai cuidar dela — senao contaria duas
           -- vezes o mesmo trabalho.
           AND (NOT p_excluir_he_do_ponto OR NOT r.he_do_ponto)
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
        coalesce((SELECT count(*)::INT FROM por_competencia WHERE valor > 0), 0),
        coalesce((SELECT jsonb_agg(jsonb_build_object('competencia', competencia, 'valor', valor)
                                   ORDER BY competencia) FROM por_competencia), '[]'::jsonb),
        coalesce((SELECT jsonb_agg(jsonb_build_object('codigo', codigo, 'descricao', descricao, 'valor', valor)
                                   ORDER BY valor DESC) FROM por_rubrica), '[]'::jsonb)
      INTO v_total, v_meses_valor, v_competencias, v_rubricas;

    -- Divisor: por padrão os meses que geraram avo — quem foi admitido no
    -- meio do ano não é dividido por 12.
    IF v_divisor_regra = 'doze_avos' THEN
        v_divisor := 12;
    ELSIF v_divisor_regra = 'meses_com_valor' THEN
        v_divisor := v_meses_valor;
    ELSE
        v_divisor := coalesce(nullif(p_avos, 0), v_meses_valor);
        IF coalesce(p_avos, 0) = 0 AND v_meses_valor > 0 THEN
            v_avisos := array_append(v_avisos,
                'Avos não informados na chamada: a média foi dividida pelos meses com variável.');
        END IF;
    END IF;

    IF v_divisor > 0 THEN
        v_media := round(v_total / v_divisor, 2);
    END IF;

    IF v_total = 0 AND v_rubricas_mkd > 0 THEN
        v_avisos := array_append(v_avisos,
            'Nenhum lançamento de rubrica variável encontrado no ano-base — confira se a folha do período foi importada.');
    END IF;

    -- A média é das VARIÁVEIS. Rubrica protegida (o Salário Base é uma
    -- delas) integra o 13º pelo lado do salário, que já entra como
    -- remuneração base — se ela também for lançada na folha, o valor
    -- entra duas vezes e o 13º sai dobrado. Não decidimos por conta
    -- própria excluir: avisamos, nomeando a rubrica, para o DP conferir.
    SELECT string_agg(DISTINCT r.descricao, ', ' ORDER BY r.descricao)
      INTO v_protegidas
      FROM public.folha_lancamentos l
      JOIN public.folha_periodos pe ON pe.id = l.periodo_id
      JOIN public.folha_rubricas  r ON r.id = l.rubrica_id
     WHERE l.tenant_id = p_tenant
       AND regexp_replace(coalesce(l.colaborador_cpf, ''), '\D', '', 'g') = v_cpf
       AND pe.competencia BETWEEN v_ini AND v_fim
       AND r.incide_13 AND r.ativa AND r.tipo = 'PROVENTO'
       AND r.protegida;

    IF v_protegidas IS NOT NULL THEN
        IF v_inclui_prot THEN
            v_avisos := array_append(v_avisos,
                format('Atenção: %s ENTROU na média porque esta empresa está configurada para incluir rubricas protegidas. O salário fixo já entra como remuneração base — confira se o valor não está sendo contado duas vezes.', v_protegidas));
        ELSE
            v_avisos := array_append(v_avisos,
                format('%s está lançada na folha e marcada como integrante do 13º, mas FOI DEIXADA DE FORA da média: a média é das variáveis e o salário fixo já entra como remuneração base.', v_protegidas));
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'media',               v_media,
        'total',               v_total,
        'meses_divisor',       v_divisor,
        'meses_com_valor',     v_meses_valor,
        'divisor_regra',       v_divisor_regra,
        'he_do_ponto_excluida', p_excluir_he_do_ponto,
        'rubricas_marcadas',   v_rubricas_mkd,
        'janela_inicio',       v_ini,
        'janela_fim',          v_fim,
        'parametros_vigencia', v_vigencia,
        'fundamento',          'Decreto 57.155/1965 (medias das variaveis)',
        'apurado_em',          now(),
        'competencias',        v_competencias,
        'rubricas',            v_rubricas,
        'avisos',              to_jsonb(v_avisos)
    );
END $fn$;
COMMENT ON FUNCTION public.decimo_terceiro_media_variaveis(UUID, TEXT, INT, INT, UUID, BOOLEAN) IS
    'Media das variaveis do 13o pelos valores pagos no ano, so rubricas com incide_13, nao protegidas e (opcionalmente) sem as horas extras do ponto. Somente leitura.';
GRANT EXECUTE ON FUNCTION public.decimo_terceiro_media_variaveis(UUID, TEXT, INT, INT, UUID, BOOLEAN) TO authenticated;

-- ── A apuração orquestra os dois métodos ─────────────────────────────
CREATE OR REPLACE FUNCTION public.decimo_terceiro_apurar(
    p_tenant     UUID,
    p_cpf        TEXT,
    p_ano        INT,
    p_salario    NUMERIC DEFAULT NULL,
    p_empresa    UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    v_avos_json  JSONB;
    v_media_json JSONB;
    v_he_json    JSONB := NULL;
    v_modo_he    TEXT  := 'fisica';
    v_usa_fisica BOOLEAN := false;
    v_media_he   NUMERIC(14,2) := 0;
    v_avos       INT;
    v_media      NUMERIC(14,2);
    v_salario    NUMERIC(14,2);
    v_base       NUMERIC(14,2);
    v_cpf        TEXT := regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
    v_avisos     TEXT[] := ARRAY[]::TEXT[];
BEGIN
    v_avos_json := public.decimo_terceiro_avos(p_tenant, p_cpf, p_ano, p_empresa);
    v_avos      := coalesce((v_avos_json->>'avos')::INT, 0);

    -- Salário primeiro: a média física da Súmula 347 precisa do valor da
    -- hora VIGENTE, e ele sai do salário.
    v_salario := p_salario;
    IF v_salario IS NULL OR v_salario = 0 THEN
        SELECT a.salario INTO v_salario
          FROM public.admissoes a
         WHERE a.tenant_id = p_tenant
           AND regexp_replace(coalesce(a.cpf, ''), '\D', '', 'g') = v_cpf
           AND a.status = 'concluido'
         ORDER BY a.data_admissao DESC NULLS LAST
         LIMIT 1;
    END IF;
    v_salario := coalesce(v_salario, 0);

    IF v_salario = 0 THEN
        v_avisos := array_append(v_avisos,
            'Salário não encontrado no cadastro — informe a remuneração base antes de fechar o cálculo.');
    END IF;

    -- Horas extras: método da empresa (padrão, Súmula 347 do TST: média
    -- FÍSICA das horas x valor da hora vigente). Se não houver ponto no
    -- ano, cai para a média de valores e a memória diz isso.
    SELECT c.media_horas_extras INTO v_modo_he
      FROM public.decimo_terceiro_config c
     WHERE c.tenant_id = p_tenant
       AND (c.empresa_id = p_empresa OR (p_empresa IS NULL AND c.empresa_id IS NULL))
     LIMIT 1;
    IF NOT FOUND THEN
        SELECT c.media_horas_extras INTO v_modo_he
          FROM public.decimo_terceiro_config c
         WHERE c.tenant_id = p_tenant AND c.empresa_id IS NULL LIMIT 1;
    END IF;
    v_modo_he := coalesce(v_modo_he, 'fisica');

    IF v_modo_he = 'fisica' THEN
        v_he_json := public.decimo_terceiro_media_horas_extras(
                         p_tenant, p_cpf, p_ano, v_avos, v_salario, p_empresa);
        v_usa_fisica := coalesce((v_he_json->>'aplicavel')::BOOLEAN, false);
        IF v_usa_fisica THEN
            v_media_he := coalesce((v_he_json->>'media')::NUMERIC, 0);
        ELSE
            v_avisos := array_append(v_avisos,
                format('Média das horas extras: %s Foi usada a média dos valores pagos no ano.',
                       coalesce(v_he_json->>'motivo', '')));
        END IF;
    END IF;

    -- Demais variáveis (comissão, adicionais) pela média de valores. Se a
    -- média física cuidou das horas extras, elas ficam de fora daqui.
    v_media_json := public.decimo_terceiro_media_variaveis(
                        p_tenant, p_cpf, p_ano, v_avos, p_empresa, v_usa_fisica);
    v_media      := coalesce((v_media_json->>'media')::NUMERIC, 0) + v_media_he;

    -- Base do 13º integral (12/12). O proporcional sai da multiplicação
    -- pelos avos, feita no cálculo da parcela.
    v_base := round(v_salario + v_media, 2);

    RETURN jsonb_build_object(
        'ano',             p_ano,
        'avos',            v_avos,
        'remuneracao_base', v_salario,
        'media_variaveis', v_media,
        'base_integral',   v_base,
        'base_proporcional', round(v_base * v_avos / 12.0, 2),
        'apurado_em',      now(),
        'memoria_avos',    v_avos_json,
        'memoria_media',   v_media_json,
        'media_horas_extras_metodo', CASE WHEN v_usa_fisica THEN 'fisica' ELSE 'valores' END,
        'media_horas_extras',        v_media_he,
        'memoria_horas_extras',      v_he_json,
        -- Sem repetir: avos e media podem reclamar da mesma coisa (o CPF,
        -- por exemplo) e o mesmo aviso duas vezes so confunde quem le.
        'avisos',          to_jsonb(ARRAY(
            SELECT DISTINCT aviso FROM unnest(
                v_avisos
                || coalesce(ARRAY(SELECT jsonb_array_elements_text(v_avos_json->'avisos')), ARRAY[]::TEXT[])
                || coalesce(ARRAY(SELECT jsonb_array_elements_text(v_media_json->'avisos')), ARRAY[]::TEXT[])
            ) AS aviso
        ))
    );
END $fn$;
GRANT EXECUTE ON FUNCTION public.decimo_terceiro_apurar(UUID, TEXT, INT, NUMERIC, UUID) TO authenticated;

-- ── A 1ª parcela passa a seguir a política escolhida ─────────────────
CREATE OR REPLACE FUNCTION public.decimo_terceiro_calcular(
    p_tenant       UUID,
    p_cpf          TEXT,
    p_ano          INT,
    p_parcela      INT,
    p_empresa      UUID    DEFAULT NULL,
    p_dependentes  INT     DEFAULT 0,
    p_primeira     NUMERIC DEFAULT NULL,
    p_tipo_vinculo TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    v_ap        JSONB;
    v_avos      INT;
    v_bruto     NUMERIC(12,2);
    v_primeira  NUMERIC(12,2);
    v_inss_j    JSONB := NULL;
    v_irrf_j    JSONB := NULL;
    v_inss      NUMERIC(12,2) := 0;
    v_irrf      NUMERIC(12,2) := 0;
    v_base_fgts NUMERIC(12,2) := 0;
    v_fgts      NUMERIC(12,2) := 0;
    v_desc      NUMERIC(12,2) := 0;
    v_liq       NUMERIC(12,2) := 0;
    v_aliq_fgts NUMERIC(5,2)  := 8.00;
    v_tem_fgts  BOOLEAN := true;
    v_tem_inss  BOOLEAN := true;
    v_data_ref  DATE;
    v_pol_adto  TEXT := 'proporcional_apurado';
    v_rem_ant   NUMERIC(12,2);
    v_comp_ant  TEXT;
    v_nota_adto TEXT := NULL;
BEGIN
    IF p_parcela NOT IN (1, 2) THEN
        RETURN jsonb_build_object('erro', 'Parcela deve ser 1 ou 2.');
    END IF;

    v_ap    := public.decimo_terceiro_apurar(p_tenant, p_cpf, p_ano, NULL, p_empresa);
    v_avos  := COALESCE((v_ap->>'avos')::INT, 0);
    v_bruto := round(COALESCE((v_ap->>'base_integral')::NUMERIC, 0) * v_avos / 12.0, 2);

    -- Regras do vínculo (avulso, estagiário e afins podem não ter FGTS).
    IF p_tipo_vinculo IS NOT NULL THEN
        SELECT c.fgts, c.aliquota_fgts, c.inss_empregado
          INTO v_tem_fgts, v_aliq_fgts, v_tem_inss
          FROM public.folha_vinculos_config c
         WHERE c.tenant_id = p_tenant AND c.tipo_vinculo = p_tipo_vinculo
         LIMIT 1;
        v_tem_fgts  := COALESCE(v_tem_fgts, true);
        v_aliq_fgts := COALESCE(v_aliq_fgts, 8.00);
        v_tem_inss  := COALESCE(v_tem_inss, true);
    END IF;

    v_data_ref := public.decimo_terceiro_prazo_legal(p_ano, p_parcela);

    IF p_parcela = 1 THEN
        -- Política do adiantamento, escolhida pela empresa. As duas
        -- leituras produzem o mesmo 13º total; muda o quanto entra em
        -- novembro (a 2ª parcela acerta a diferença).
        SELECT cfg.adiantamento_base INTO v_pol_adto
          FROM public.decimo_terceiro_config cfg
         WHERE cfg.tenant_id = p_tenant
           AND (cfg.empresa_id = p_empresa OR (p_empresa IS NULL AND cfg.empresa_id IS NULL))
         LIMIT 1;
        IF NOT FOUND THEN
            SELECT cfg.adiantamento_base INTO v_pol_adto
              FROM public.decimo_terceiro_config cfg
             WHERE cfg.tenant_id = p_tenant AND cfg.empresa_id IS NULL LIMIT 1;
        END IF;
        v_pol_adto := coalesce(v_pol_adto, 'proporcional_apurado');

        IF v_pol_adto = 'remuneracao_mes_anterior' THEN
            -- Letra do art. 2º da Lei 4.749/1965: metade do salário
            -- recebido no mês ANTERIOR ao pagamento do adiantamento.
            v_comp_ant := to_char(coalesce(v_data_ref, make_date(p_ano, 11, 30))
                                  - INTERVAL '1 month', 'YYYY-MM');

            -- "Remuneração recebida no mês anterior" = salário do
            -- cadastro + as VARIÁVEIS lançadas naquela competência.
            -- O salário vem do cadastro (não da folha) pela mesma razão
            -- do resto do módulo: nem todo cliente lança o fixo como
            -- rubrica, e somar os dois duplicaria o salário de quem lança.
            SELECT coalesce(sum(l.valor), 0) INTO v_rem_ant
              FROM public.folha_lancamentos l
              JOIN public.folha_periodos pe ON pe.id = l.periodo_id
              JOIN public.folha_rubricas  r ON r.id = l.rubrica_id
             WHERE l.tenant_id = p_tenant
               AND regexp_replace(coalesce(l.colaborador_cpf, ''), '\D', '', 'g')
                   = regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g')
               AND pe.competencia = v_comp_ant
               AND r.tipo = 'PROVENTO'
               AND r.natureza = 'REMUNERATORIA'
               AND NOT r.protegida;

            IF v_rem_ant = 0 THEN
                v_nota_adto := format(
                    'Sem variável lançada na competência %s: o adiantamento saiu só do salário do cadastro.',
                    v_comp_ant);
            END IF;

            v_rem_ant := coalesce((v_ap->>'remuneracao_base')::NUMERIC, 0) + v_rem_ant;

            v_primeira := round(v_rem_ant / 2, 2);

            -- Trava de bom senso: o adiantamento nunca supera o próprio
            -- 13º apurado — adiantar mais viraria desconto na 2ª parcela.
            IF v_primeira > v_bruto THEN
                v_nota_adto := coalesce(v_nota_adto || ' ', '') || format(
                    'Metade da remuneração de %s (R$ %s) superaria o 13º devido (R$ %s); limitado ao 13º.',
                    v_comp_ant, round(v_rem_ant / 2, 2), v_bruto);
                v_primeira := v_bruto;
            END IF;
        ELSE
            v_primeira := round(v_bruto / 2, 2);
        END IF;
        v_base_fgts := v_primeira;
        v_fgts      := CASE WHEN v_tem_fgts THEN round(v_base_fgts * v_aliq_fgts / 100, 2) ELSE 0 END;
        v_liq       := v_primeira;
    ELSE
        v_primeira := COALESCE(p_primeira, round(v_bruto / 2, 2));

        IF v_tem_inss THEN
            v_inss_j := public.decimo_terceiro_inss(v_bruto, p_tenant, v_data_ref);
            v_inss   := COALESCE((v_inss_j->>'valor')::NUMERIC, 0);
        END IF;

        v_irrf_j := public.decimo_terceiro_irrf(v_bruto - v_inss, p_dependentes, p_tenant, v_data_ref);
        v_irrf   := COALESCE((v_irrf_j->>'valor')::NUMERIC, 0);

        v_base_fgts := v_bruto - v_primeira;
        v_fgts      := CASE WHEN v_tem_fgts THEN round(v_base_fgts * v_aliq_fgts / 100, 2) ELSE 0 END;

        v_desc := round(v_inss + v_irrf + v_primeira, 2);
        v_liq  := round(v_bruto - v_desc, 2);
    END IF;

    RETURN jsonb_build_object(
        'ano', p_ano, 'parcela', p_parcela, 'avos', v_avos,
        'remuneracao_base',      (v_ap->>'remuneracao_base')::NUMERIC,
        'media_variaveis',       (v_ap->>'media_variaveis')::NUMERIC,
        'valor_bruto',           v_bruto,
        'valor_primeira_parcela', v_primeira,
        'base_inss',   CASE WHEN p_parcela = 2 THEN v_bruto ELSE 0 END,
        'valor_inss',  v_inss,
        'base_irrf',   CASE WHEN p_parcela = 2 THEN v_bruto - v_inss ELSE 0 END,
        'valor_irrf',  v_irrf,
        'base_fgts',   v_base_fgts,
        'valor_fgts',  v_fgts,
        'total_descontos', v_desc,
        'total_liquido',   v_liq,
        'data_prevista',   v_data_ref,
        'competencia',     to_char(v_data_ref, 'YYYY-MM'),
        'memoria', jsonb_build_object(
            'apuracao', v_ap, 'inss', v_inss_j, 'irrf', v_irrf_j,
            'aliquota_fgts', v_aliq_fgts, 'dependentes_irrf', COALESCE(p_dependentes, 0),
            'adiantamento_politica', v_pol_adto,
            'adiantamento_nota', v_nota_adto,
            'fundamento', 'Lei 4.749/1965 (parcelas); INSS e IRRF so na 2a; FGTS nas duas'));
END $fn$;
GRANT EXECUTE ON FUNCTION public.decimo_terceiro_calcular(UUID, TEXT, INT, INT, UUID, INT, NUMERIC, TEXT) TO authenticated;

-- ── 3. DEFEITO MEU: a config do 13º aceitava duplicata ────────────────
-- decimo_terceiro_config nasceu (Entrega 1) com
--   CONSTRAINT ... UNIQUE (tenant_id, empresa_id)
-- e empresa_id é opcional. No PostgreSQL, DOIS NULL NÃO SÃO IGUAIS: a
-- restrição não impedia duas linhas de configuração GERAL da mesma
-- empresa. Com duas linhas, o LIMIT 1 do cálculo passava a pegar uma
-- QUALQUER — a política do adiantamento e o método da média viravam
-- sorteio, em silêncio. Foi assim que o teste das duas políticas
-- devolveu o mesmo número.
--
-- Correção: unicidade à prova de NULL, como já se faz em folha_13_calculo.
-- Antes de remover duplicata, as linhas são copiadas.

CREATE TABLE IF NOT EXISTS public.backup_decimo_terceiro_config_20260904 AS
SELECT * FROM public.decimo_terceiro_config WHERE false;

DO $dedup$
DECLARE v_dups INT;
BEGIN
    WITH ranqueado AS (
        SELECT id, row_number() OVER (
                 PARTITION BY tenant_id,
                              COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid)
                 ORDER BY updated_at DESC NULLS LAST, created_at DESC) AS pos
          FROM public.decimo_terceiro_config)
    INSERT INTO public.backup_decimo_terceiro_config_20260904
    SELECT c.* FROM public.decimo_terceiro_config c
      JOIN ranqueado r ON r.id = c.id AND r.pos > 1;

    WITH ranqueado AS (
        SELECT id, row_number() OVER (
                 PARTITION BY tenant_id,
                              COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid)
                 ORDER BY updated_at DESC NULLS LAST, created_at DESC) AS pos
          FROM public.decimo_terceiro_config)
    DELETE FROM public.decimo_terceiro_config c
     USING ranqueado r
     WHERE r.id = c.id AND r.pos > 1;

    GET DIAGNOSTICS v_dups = ROW_COUNT;
    IF v_dups > 0 THEN
        RAISE NOTICE 'Configuracoes do 13o duplicadas removidas: % (copiadas em backup_decimo_terceiro_config_20260904; a mais recente de cada empresa foi mantida).', v_dups;
    END IF;
END $dedup$;

-- A restrição antiga não protege NULL; o índice abaixo protege.
ALTER TABLE public.decimo_terceiro_config
    DROP CONSTRAINT IF EXISTS decimo_terceiro_config_empresa_unica;

CREATE UNIQUE INDEX IF NOT EXISTS decimo_terceiro_config_empresa_uq
    ON public.decimo_terceiro_config (
        tenant_id, COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid));

COMMENT ON INDEX public.decimo_terceiro_config_empresa_uq IS
    'Uma configuracao por empresa, e uma geral do tenant. A prova de NULL: a restricao anterior (UNIQUE com empresa_id nulo) deixava passar duplicata.';

-- ── Conferência final ─────────────────────────────────────────────────
WITH itens AS MATERIALIZED (
    SELECT * FROM (VALUES
        ('parametro media_horas_extras',  'coluna_cfg', 'media_horas_extras'),
        ('parametro divisor_horas_mes',   'coluna_cfg', 'divisor_horas_mes'),
        ('marca he_do_ponto nas rubricas','coluna_rub', 'he_do_ponto'),
        ('funcao media fisica (Sumula 347)', 'funcao',   'decimo_terceiro_media_horas_extras'),
        ('unicidade da config a prova de NULL', 'indice','decimo_terceiro_config_empresa_uq')
    ) AS t(item, especie, nome)
)
SELECT i.item,
       CASE WHEN CASE i.especie
              WHEN 'coluna_cfg' THEN EXISTS (SELECT 1 FROM information_schema.columns
                                              WHERE table_schema='public' AND table_name='decimo_terceiro_config'
                                                AND column_name=i.nome)
              WHEN 'coluna_rub' THEN EXISTS (SELECT 1 FROM information_schema.columns
                                              WHERE table_schema='public' AND table_name='folha_rubricas'
                                                AND column_name=i.nome)
              WHEN 'indice'     THEN EXISTS (SELECT 1 FROM pg_class WHERE relname=i.nome AND relkind='i')
              WHEN 'funcao'     THEN EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                                              WHERE n.nspname='public' AND p.proname=i.nome)
            END THEN 'OK' ELSE 'FALTOU' END AS situacao,
       NULL::text AS erro_tecnico
  FROM itens i
 UNION ALL
SELECT 'a 1a parcela le a politica escolhida',
       CASE WHEN position('remuneracao_mes_anterior' in p.prosrc) > 0 THEN 'OK' ELSE 'FALTOU' END,
       CASE WHEN position('remuneracao_mes_anterior' in p.prosrc) > 0 THEN NULL
            ELSE 'decimo_terceiro_calcular nao foi substituida' END
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname='public' AND p.proname='decimo_terceiro_calcular'
 UNION ALL
SELECT 'configuracoes duplicadas removidas',
       'INFORMATIVO',
       (SELECT count(*)::text || ' linha(s) movida(s) para backup_decimo_terceiro_config_20260904'
          FROM public.backup_decimo_terceiro_config_20260904)
 ORDER BY 2 DESC, 1;
