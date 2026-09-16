-- =========================================================
-- 13º Salário — a média avisa quando uma rubrica protegida entra nela
--
-- PROBLEMA (visto ao semear a folha de demonstração, 03/09/2026): o
-- cadastro padrão de rubricas marca "Salário Base" como integrante do
-- 13º — e está certo, o salário compõe o 13º. Só que a MÉDIA apurada
-- aqui é a das VARIÁVEIS: o salário fixo já entra no cálculo pelo campo
-- de remuneração base. Se o cliente também lançar o salário base como
-- rubrica na folha do mês, ele soma nos dois lugares e o 13º sai
-- dobrado — em silêncio.
--
-- ENTREGA: a apuração passa a avisar, nomeando a rubrica, sempre que uma
-- rubrica PROTEGIDA (as do sistema: Salário Base, INSS, IRRF) entrar na
-- média. Não excluímos por conta própria — quem decide o que integra a
-- média é o cadastro do cliente —, mas deixa de ser silencioso.
--
-- Nenhum valor muda: só entra um aviso a mais na memória.
--
-- Requisitos YE-DP-13-001: RF-002, RN-002, seção 14 (base incompleta).
-- =========================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.decimo_terceiro_media_variaveis(
    p_tenant  UUID,
    p_cpf     TEXT,
    p_ano     INT,
    p_avos    INT DEFAULT NULL,
    p_empresa UUID DEFAULT NULL
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

    SELECT c.media_divisor, c.parametros_vigencia_inicio
      INTO v_divisor_regra, v_vigencia
      FROM public.decimo_terceiro_config c
     WHERE c.tenant_id = p_tenant
       AND (c.empresa_id = p_empresa OR (p_empresa IS NULL AND c.empresa_id IS NULL))
     LIMIT 1;

    IF NOT FOUND THEN
        SELECT c.media_divisor, c.parametros_vigencia_inicio
          INTO v_divisor_regra, v_vigencia
          FROM public.decimo_terceiro_config c
         WHERE c.tenant_id = p_tenant AND c.empresa_id IS NULL
         LIMIT 1;
    END IF;

    v_divisor_regra := coalesce(v_divisor_regra, 'avos_apurados');
    v_vigencia      := coalesce(v_vigencia, DATE '2026-01-01');

    v_ini := to_char(make_date(p_ano, 1, 1),  'YYYY-MM');
    v_fim := to_char(make_date(p_ano, 12, 1), 'YYYY-MM');

    -- A empresa marcou alguma rubrica como integrante do 13º?
    SELECT count(*)::INT INTO v_rubricas_mkd
      FROM public.folha_rubricas r
     WHERE r.tenant_id = p_tenant AND r.incide_13 AND r.ativa;

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
        v_avisos := array_append(v_avisos,
            format('Atenção: %s entrou na média por estar marcada como integrante do 13º. A média é das variáveis (hora extra, comissão, adicionais) e o salário fixo já entra como remuneração base — confira se o valor não está sendo contado duas vezes.', v_protegidas));
    END IF;

    RETURN jsonb_build_object(
        'media',               v_media,
        'total',               v_total,
        'meses_divisor',       v_divisor,
        'meses_com_valor',     v_meses_valor,
        'divisor_regra',       v_divisor_regra,
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

COMMENT ON FUNCTION public.decimo_terceiro_media_variaveis(UUID, TEXT, INT, INT, UUID) IS
    'Media das variaveis do 13o (Decreto 57.155/1965) apurada dos lancamentos da folha do ano-base, so rubricas com incide_13, com memoria competencia a competencia. Avisa quando rubrica protegida entra na media. Somente leitura.';

GRANT EXECUTE ON FUNCTION public.decimo_terceiro_media_variaveis(UUID, TEXT, INT, INT, UUID) TO authenticated;
