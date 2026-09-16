-- =========================================================
-- SCRIPT DE ENTREGA — 13º Salário: apuração de avos e médias
-- (Entrega 1 do módulo 13º Salário — requisitos YE-DP-13-001)
--
-- O QUE ESTE SCRIPT FAZ:
--   * cria a tabela de parâmetros do 13º por empresa (decimo_terceiro_config);
--   * cria três funções de LEITURA que apuram os avos da Lei 4.090/1962,
--     a média das variáveis do ano e a base do 13º, com memória;
--   * acrescenta em folha_13_calculo as colunas que registram se os
--     números foram apurados ou digitados;
--   * passa a recusar avos impossíveis (o ano tem 12 meses).
--
-- O QUE ESTE SCRIPT NAO FAZ: não altera nem apaga NENHUM cálculo de 13º
-- já gravado. Só cria coisa nova e acrescenta coluna com valor padrão —
-- por isso não há tabela de backup neste script.
--
-- Idempotente: rodar duas vezes não quebra nem duplica.
-- Rodar no SQL Editor do projeto de PRODUÇÃO, de uma vez só.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.decimo_terceiro_config (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id  UUID NOT NULL,
    empresa_id UUID,

    -- Divisor da média das variáveis do ano.
    media_divisor TEXT NOT NULL DEFAULT 'avos_apurados'
        CHECK (media_divisor IN ('avos_apurados', 'meses_com_valor', 'doze_avos')),

    -- Efeito do afastamento sobre os avos.
    afastamento_regra TEXT NOT NULL DEFAULT 'previdenciario_suspende'
        CHECK (afastamento_regra IN ('previdenciario_suspende', 'tudo_conta')),

    -- Dia do afastamento previdenciário a partir do qual o empregador
    -- deixa de contar (16 = os 15 primeiros são dele, Lei 8.213 art. 60).
    afastamento_dias_empregador INT NOT NULL DEFAULT 15
        CHECK (afastamento_dias_empregador BETWEEN 0 AND 90),

    -- Base do adiantamento da 1ª parcela.
    adiantamento_base TEXT NOT NULL DEFAULT 'proporcional_apurado'
        CHECK (adiantamento_base IN ('proporcional_apurado', 'remuneracao_mes_anterior')),

    parametros_vigencia_inicio DATE NOT NULL DEFAULT '2026-01-01',

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Uma config por empresa (e uma "geral" do tenant quando empresa_id é null).
    CONSTRAINT decimo_terceiro_config_empresa_unica UNIQUE (tenant_id, empresa_id)
);

ALTER TABLE public.decimo_terceiro_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "decimo_terceiro_config por tenant" ON public.decimo_terceiro_config;
CREATE POLICY "decimo_terceiro_config por tenant"
ON public.decimo_terceiro_config FOR ALL TO authenticated
USING (tenant_id = public.get_user_tenant_id())
WITH CHECK (tenant_id = public.get_user_tenant_id());

DROP TRIGGER IF EXISTS touch_decimo_terceiro_config ON public.decimo_terceiro_config;
CREATE TRIGGER touch_decimo_terceiro_config
BEFORE UPDATE ON public.decimo_terceiro_config
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

COMMENT ON TABLE public.decimo_terceiro_config IS
    'Parametros do calculo do 13o por empresa (divisor da media, efeito do afastamento nos avos, base do adiantamento), com vigencia.';
ALTER TABLE public.decimo_terceiro_config
    ADD COLUMN IF NOT EXISTS media_inclui_protegidas BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.decimo_terceiro_config.media_inclui_protegidas IS
    'FALSE (padrao): rubrica protegida (Salario Base, INSS, IRRF) NAO entra na media das variaveis — o salario fixo ja entra como remuneracao base. TRUE: entra, e a memoria avisa.';

COMMENT ON COLUMN public.decimo_terceiro_config.media_divisor IS
    'avos_apurados: divide pelos meses que geraram avo. meses_com_valor: so pelos meses com variavel. doze_avos: sempre por 12.';
COMMENT ON COLUMN public.decimo_terceiro_config.afastamento_regra IS
    'previdenciario_suspende: afastamento com beneficio do INSS deixa de contar apos os dias do empregador. tudo_conta: nenhum afastamento derruba avo.';
COMMENT ON COLUMN public.decimo_terceiro_config.adiantamento_base IS
    'proporcional_apurado: 1a parcela = 50% do 13o proporcional. remuneracao_mes_anterior: 50% da remuneracao do mes anterior ao pagamento.';


-- ── 2. Avos da Lei 4.090/1962 ─────────────────────────────────────────────
-- 1/12 por mês; o mês conta quando restam 15 dias ou mais de trabalho,
-- descontadas as faltas injustificadas e o afastamento previdenciário.
-- Devolve o número de avos E a memória mês a mês — é ela que torna o
-- valor reproduzível depois (RNF-001/007).
-- SECURITY INVOKER de propósito: quem chama só enxerga o que a RLS do seu
-- tenant já permitiria enxergar.
CREATE OR REPLACE FUNCTION public.decimo_terceiro_avos(
    p_tenant  UUID,
    p_cpf     TEXT,
    p_ano     INT,
    p_empresa UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    v_cpf         TEXT := regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
    v_regra       TEXT := 'previdenciario_suspende';
    v_dias_empreg INT  := 15;
    v_vigencia    DATE := '2026-01-01';
    v_admissao    DATE;
    v_desligamento DATE;
    v_ano_ini     DATE;
    v_ano_fim     DATE;
    v_tem_ponto   BOOLEAN := false;
    v_avos        INT := 0;
    v_meses       JSONB := '[]'::jsonb;
    v_avisos      TEXT[] := ARRAY[]::TEXT[];
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
            'avos', 0, 'meses', '[]'::jsonb,
            'avisos', to_jsonb(v_avisos)
        );
    END IF;

    v_ano_ini := make_date(p_ano, 1, 1);
    v_ano_fim := make_date(p_ano, 12, 31);

    -- Parâmetros da empresa; sem registro da empresa, cai no geral do tenant.
    SELECT c.afastamento_regra, c.afastamento_dias_empregador, c.parametros_vigencia_inicio
      INTO v_regra, v_dias_empreg, v_vigencia
      FROM public.decimo_terceiro_config c
     WHERE c.tenant_id = p_tenant
       AND (c.empresa_id = p_empresa OR (p_empresa IS NULL AND c.empresa_id IS NULL))
     LIMIT 1;

    IF NOT FOUND THEN
        SELECT c.afastamento_regra, c.afastamento_dias_empregador, c.parametros_vigencia_inicio
          INTO v_regra, v_dias_empreg, v_vigencia
          FROM public.decimo_terceiro_config c
         WHERE c.tenant_id = p_tenant AND c.empresa_id IS NULL
         LIMIT 1;
    END IF;

    v_regra       := coalesce(v_regra, 'previdenciario_suspende');
    v_dias_empreg := coalesce(v_dias_empreg, 15);
    v_vigencia    := coalesce(v_vigencia, DATE '2026-01-01');

    -- Admissão: o vínculo efetivo (admissão concluída) do CPF no tenant.
    SELECT min(a.data_admissao) INTO v_admissao
      FROM public.admissoes a
     WHERE a.tenant_id = p_tenant
       AND regexp_replace(coalesce(a.cpf, ''), '\D', '', 'g') = v_cpf
       AND a.status = 'concluido'
       AND a.data_admissao IS NOT NULL;

    IF v_admissao IS NULL THEN
        v_avisos := array_append(v_avisos,
            'Não há admissão concluída com data para este CPF — os avos foram apurados como se o vínculo cobrisse o ano inteiro. Confira o cadastro antes de fechar.');
        v_admissao := v_ano_ini;
    END IF;

    -- Desligamento no ano-base, se houver (o 13º vira proporcional).
    SELECT min(r.data_desligamento) INTO v_desligamento
      FROM public.folha_rescisoes r
     WHERE r.tenant_id = p_tenant
       AND regexp_replace(coalesce(r.colaborador_cpf, ''), '\D', '', 'g') = v_cpf
       AND r.data_desligamento BETWEEN v_ano_ini AND v_ano_fim;

    -- O ponto cobre o ano? Sem cobertura, não descontamos faltas que não
    -- temos como provar — e avisamos.
    SELECT EXISTS (
        SELECT 1 FROM public.ponto_diario pd
         WHERE pd.tenant_id = p_tenant
           AND regexp_replace(coalesce(pd.colaborador_cpf, ''), '\D', '', 'g') = v_cpf
           AND pd.data BETWEEN v_ano_ini AND v_ano_fim
           AND pd.status <> 'pendente'
    ) INTO v_tem_ponto;

    IF NOT v_tem_ponto THEN
        v_avisos := array_append(v_avisos,
            'Sem registro de ponto no ano-base: os avos foram apurados sem desconto de faltas.');
    END IF;

    -- Mês a mês: dias de vínculo, faltas injustificadas e dias de
    -- afastamento previdenciário além dos dias do empregador.
    WITH meses AS MATERIALIZED (
        SELECT m AS mes,
               make_date(p_ano, m, 1) AS mes_ini,
               (make_date(p_ano, m, 1) + INTERVAL '1 month - 1 day')::DATE AS mes_fim
          FROM generate_series(1, 12) AS m
    ),
    vinculo AS MATERIALIZED (
        SELECT mes, mes_ini, mes_fim,
               greatest(mes_ini, v_admissao) AS ini,
               least(mes_fim, coalesce(v_desligamento, mes_fim)) AS fim
          FROM meses
    ),
    dias AS MATERIALIZED (
        SELECT mes, mes_ini, mes_fim, ini, fim,
               CASE WHEN fim >= ini THEN (fim - ini + 1) ELSE 0 END AS dias_vinculo
          FROM vinculo
    ),
    computo AS MATERIALIZED (
        SELECT d.mes, d.dias_vinculo,
               -- Faltas injustificadas do ponto dentro do vínculo do mês.
               CASE WHEN d.dias_vinculo = 0 OR NOT v_tem_ponto THEN 0 ELSE (
                   SELECT count(*)::INT FROM public.ponto_diario pd
                    WHERE pd.tenant_id = p_tenant
                      AND regexp_replace(coalesce(pd.colaborador_cpf, ''), '\D', '', 'g') = v_cpf
                      AND pd.data BETWEEN d.ini AND d.fim
                      AND pd.status = 'falta'
               ) END AS faltas,
               -- Dias de afastamento previdenciário que já correm por conta
               -- do INSS (a partir do dia seguinte aos dias do empregador).
               CASE WHEN d.dias_vinculo = 0 OR v_regra <> 'previdenciario_suspende' THEN 0 ELSE (
                   SELECT coalesce(sum(
                       greatest(0,
                           least(coalesce(af.data_fim, d.fim), d.fim)
                           - greatest(af.data_inicio + v_dias_empreg, d.ini) + 1)
                   )::INT, 0)
                     FROM public.afastamentos af
                     JOIN public.afastamentos_previdenciario ap ON ap.afastamento_id = af.id
                    WHERE af.tenant_id = p_tenant
                      AND regexp_replace(coalesce(af.colaborador_cpf, ''), '\D', '', 'g') = v_cpf
                      AND ap.especie_beneficio IN ('B31', 'B91', 'B92', 'B32')
                      AND af.data_inicio <= d.fim
                      AND coalesce(af.data_fim, d.fim) >= d.ini
               ) END AS dias_inss
          FROM dias d
    ),
    fechado AS MATERIALIZED (
        SELECT mes, dias_vinculo, faltas, dias_inss,
               greatest(0, dias_vinculo - faltas - dias_inss) AS dias_computados,
               (greatest(0, dias_vinculo - faltas - dias_inss) >= 15) AS conta
          FROM computo
    )
    SELECT coalesce(sum(CASE WHEN conta THEN 1 ELSE 0 END)::INT, 0),
           coalesce(jsonb_agg(jsonb_build_object(
               'mes',             mes,
               'dias_vinculo',    dias_vinculo,
               'faltas',          faltas,
               'dias_inss',       dias_inss,
               'dias_computados', dias_computados,
               'conta',           conta
           ) ORDER BY mes), '[]'::jsonb)
      INTO v_avos, v_meses
      FROM fechado;

    IF v_avos = 0 THEN
        v_avisos := array_append(v_avisos,
            'Nenhum mês do ano-base fechou 15 dias de trabalho — não há avo a pagar. Confira admissão, faltas e afastamentos.');
    END IF;

    RETURN jsonb_build_object(
        'avos',                v_avos,
        'ano',                 p_ano,
        'admissao',            v_admissao,
        'desligamento',        v_desligamento,
        'tem_ponto',           v_tem_ponto,
        'afastamento_regra',   v_regra,
        'dias_empregador',     v_dias_empreg,
        'parametros_vigencia', v_vigencia,
        'fundamento',          'Lei 4.090/1962, art. 1º, § 2º (fração >= 15 dias)',
        'apurado_em',          now(),
        'meses',               v_meses,
        'avisos',              to_jsonb(v_avisos)
    );
END $fn$;

COMMENT ON FUNCTION public.decimo_terceiro_avos(UUID, TEXT, INT, UUID) IS
    'Avos do 13o (Lei 4.090/1962): 1/12 por mes com fracao >= 15 dias, descontadas faltas do ponto e afastamento previdenciario, com memoria mes a mes. Somente leitura.';

GRANT EXECUTE ON FUNCTION public.decimo_terceiro_avos(UUID, TEXT, INT, UUID) TO authenticated;


-- ── 3. Média das variáveis do ano-base ────────────────────────────────────
-- Só as rubricas marcadas com incide_13 no cadastro de rubricas.
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
       AND (v_inclui_prot OR NOT r.protegida);

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
    'Media das variaveis do 13o (Decreto 57.155/1965) apurada dos lancamentos da folha do ano-base, so rubricas com incide_13, com memoria competencia a competencia. Somente leitura.';

GRANT EXECUTE ON FUNCTION public.decimo_terceiro_media_variaveis(UUID, TEXT, INT, INT, UUID) TO authenticated;


-- ── 4. Apuração completa (avos + média + base) ────────────────────────────
-- É o que a tela chama: uma ida ao banco devolve tudo com a memória junta.
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
    v_avos       INT;
    v_media      NUMERIC(14,2);
    v_salario    NUMERIC(14,2);
    v_base       NUMERIC(14,2);
    v_cpf        TEXT := regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
    v_avisos     TEXT[] := ARRAY[]::TEXT[];
BEGIN
    v_avos_json := public.decimo_terceiro_avos(p_tenant, p_cpf, p_ano, p_empresa);
    v_avos      := coalesce((v_avos_json->>'avos')::INT, 0);

    v_media_json := public.decimo_terceiro_media_variaveis(p_tenant, p_cpf, p_ano, v_avos, p_empresa);
    v_media      := coalesce((v_media_json->>'media')::NUMERIC, 0);

    -- Salário: o informado pela tela ou, na falta, o da admissão concluída.
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

COMMENT ON FUNCTION public.decimo_terceiro_apurar(UUID, TEXT, INT, NUMERIC, UUID) IS
    'Apuracao completa do 13o de um vinculo no ano-base: avos, media das variaveis e base, com as duas memorias. Somente leitura.';

GRANT EXECUTE ON FUNCTION public.decimo_terceiro_apurar(UUID, TEXT, INT, NUMERIC, UUID) TO authenticated;


-- ── 5. Origem do valor e integridade no cálculo gravado ───────────────────
ALTER TABLE public.folha_13_calculo
    ADD COLUMN IF NOT EXISTS avos_origem  TEXT NOT NULL DEFAULT 'manual',
    ADD COLUMN IF NOT EXISTS media_origem TEXT NOT NULL DEFAULT 'manual';

DO $ck$
BEGIN
    ALTER TABLE public.folha_13_calculo
        ADD CONSTRAINT folha_13_calculo_avos_origem_ck
        CHECK (avos_origem IN ('apurado', 'manual', 'apurado_ajustado'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

DO $ck$
BEGIN
    ALTER TABLE public.folha_13_calculo
        ADD CONSTRAINT folha_13_calculo_media_origem_ck
        CHECK (media_origem IN ('apurado', 'manual', 'apurado_ajustado'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

COMMENT ON COLUMN public.folha_13_calculo.avos_origem IS
    'De onde vieram os avos: apurado (decimo_terceiro_avos), apurado_ajustado (apurado e depois editado com justificativa) ou manual.';
COMMENT ON COLUMN public.folha_13_calculo.media_origem IS
    'De onde veio a media das variaveis: apurado (decimo_terceiro_media_variaveis), apurado_ajustado ou manual.';

-- O ano tem 12 meses: 15 avos era aceito (DEC13-001). NOT VALID de
-- proposito — barra o que entra de agora em diante sem varrer o historico
-- de producao, que pode ter linha antiga fora da regra.
DO $ck$
BEGIN
    ALTER TABLE public.folha_13_calculo
        ADD CONSTRAINT folha_13_calculo_meses_ck
        CHECK (meses_trabalhados BETWEEN 0 AND 12) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

DO $ck$
BEGIN
    ALTER TABLE public.folha_13_calculo
        ADD CONSTRAINT folha_13_calculo_parcela_ck
        CHECK (parcela IN (1, 2)) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

-- ── Conferência final (o editor só mostra o último resultado) ─────────────
WITH objetos AS MATERIALIZED (
    SELECT 'tabela decimo_terceiro_config' AS item,
           (to_regclass('public.decimo_terceiro_config') IS NOT NULL) AS ok
    UNION ALL SELECT 'funcao decimo_terceiro_avos',
           EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname = 'public' AND p.proname = 'decimo_terceiro_avos')
    UNION ALL SELECT 'funcao decimo_terceiro_media_variaveis',
           EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname = 'public' AND p.proname = 'decimo_terceiro_media_variaveis')
    UNION ALL SELECT 'funcao decimo_terceiro_apurar',
           EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname = 'public' AND p.proname = 'decimo_terceiro_apurar')
    UNION ALL SELECT 'coluna folha_13_calculo.avos_origem',
           EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = 'folha_13_calculo'
                      AND column_name = 'avos_origem')
    UNION ALL SELECT 'coluna folha_13_calculo.media_origem',
           EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = 'folha_13_calculo'
                      AND column_name = 'media_origem')
    UNION ALL SELECT 'parametro media_inclui_protegidas',
           EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = 'decimo_terceiro_config'
                      AND column_name = 'media_inclui_protegidas')
    UNION ALL SELECT 'trava de avos impossiveis (0 a 12)',
           EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'folha_13_calculo_meses_ck')
    UNION ALL SELECT 'trava de parcela (1 ou 2)',
           EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'folha_13_calculo_parcela_ck')
)
SELECT item,
       CASE WHEN ok THEN 'OK' ELSE 'FALTOU' END AS situacao,
       CASE WHEN ok THEN NULL ELSE 'Objeto nao encontrado apos a execucao' END AS erro_tecnico
  FROM objetos
 ORDER BY situacao DESC, item;
