-- ============================================================================
-- SCRIPT DE ENTREGA UNICO — 13o Salario (Gratificacao de Natal)
-- Referencia: YE-DP-13-001
--
-- Aplicar PRIMEIRO na HOMOLOGACAO e, depois de conferido, o MESMO arquivo na
-- PRODUCAO (fluxo forward-only, decisao 09/2026). Este arquivo substitui os
-- nove scripts separados: eles continuam no repositorio para consulta, mas a
-- ordem entre eles era o unico jeito de errar — aqui ela ja vem embutida.
--
-- O QUE ENTREGA, em ordem:
--   1. Apuracao dos avos (Lei 4.090/1962: 1/12 por mes, fracao >= 15 dias),
--      medias das variaveis e as memorias que tornam o valor reproduzivel;
--   2. Fechamento: vinculo, situacao, INSS e IRRF no banco, processamento em
--      lote, prazo legal (30/11 e 20/12 recuando para o ultimo dia util),
--      aprovacao, pagamento, reabertura com dupla aprovacao e camada de perfil;
--   3. As duas politicas de adiantamento da Lei 4.749/1965 a escolha da
--      empresa, e a media FISICA de horas extras (Sumula 347 do TST);
--   4. Alertas de prazo (D-30/15/7 e D-15/7/3) com Plano de Acao 5W2H;
--   5. Provisao contabil mensal, conciliacao, 13o na rescisao e adiantamento
--      junto as ferias;
--   6. eSocial: S-1200 com apuracao ANUAL (indApuracao = 2) e S-1210 dos
--      pagamentos. MONTA e confere; NAO TRANSMITE (certificado, procuracao e
--      ambiente sao do cliente, e o leiaute vigente precisa ser conferido);
--   7. Duas correcoes de lei que os testes encontraram: o aviso previo
--      INDENIZADO passa a projetar o tempo de servico (CLT, art. 487, §1o;
--      Sumula 371 do TST) e o afastamento por ACIDENTE DE TRABALHO deixa de
--      derrubar avo (Sumula 46 do TST; Lei 8.213/1991, art. 4o, par. unico);
--   8. Culpa reciproca: o motivo que faltava, pagando METADE das verbas
--      (CLT, art. 484; Sumula 14 do TST);
--   9. Documentacao de testes: os 31 casos e as rotinas que os executam.
--
-- O QUE ELE NAO FAZ: nao altera nenhum calculo de 13o ja gravado, nao mexe em
-- rescisao ja fechada e nao apaga dado de negocio. Tudo e CREATE OR REPLACE,
-- ADD COLUMN IF NOT EXISTS, indice/gatilho recriado e INSERT ... ON CONFLICT.
-- Por isso NAO ha tabela de backup: a regra de backup vale para UPDATE/DELETE
-- de dado existente, e aqui nao ha nenhum. A unica excecao e a deduplicacao
-- da configuracao do 13o (item 3), que guarda o que remove em
-- backup_decimo_terceiro_config_<aaaammdd> antes de mexer.
--
-- O SQL Editor roda o arquivo inteiro em UMA transacao: se algo falhar, nada
-- e aplicado (nao ha estado pela metade). A conferencia final e o unico SELECT
-- e sai por ultimo. Idempotente: rodar duas vezes nao quebra nem duplica.
--
-- OBS DDL: adiciona colunas e cria gatilhos em tabelas da folha. Com
-- lock_timeout de 10s, se alguma estiver muito movimentada o comando falha
-- rapido e a transacao volta atras — nesse caso, rode de novo numa janela
-- mais tranquila (fora do fechamento de folha).
--
-- DEPOIS DESTE SCRIPT: as telas do 13o (apuracao com memoria, lote, Politica
-- do 13o, recibos em Documentos, alertas, provisoes, aba eSocial) e o motivo
-- "Culpa Reciproca" na rescisao vem do codigo — elas so aparecem depois do
-- Publicar no Lovable.
-- ============================================================================

SET lock_timeout = '10s';

-- ════════════════════════════════════════════════════════════════════
-- 1) Apuracao: avos da Lei 4.090, medias e memorias
-- ════════════════════════════════════════════════════════════════════
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


-- ════════════════════════════════════════════════════════════════════
-- 2) Fechamento: estrutura, encargos no banco, lote e reabertura
-- ════════════════════════════════════════════════════════════════════
-- ── 1. Colunas que faltavam ───────────────────────────────────────────
ALTER TABLE public.folha_13_calculo
    ADD COLUMN IF NOT EXISTS admissao_id       UUID REFERENCES public.admissoes(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS empresa_id        UUID,
    ADD COLUMN IF NOT EXISTS competencia       TEXT,
    ADD COLUMN IF NOT EXISTS data_prevista     DATE,
    ADD COLUMN IF NOT EXISTS data_pagamento    DATE,
    ADD COLUMN IF NOT EXISTS aprovado_por      UUID,
    ADD COLUMN IF NOT EXISTS aprovado_por_nome TEXT,
    ADD COLUMN IF NOT EXISTS aprovado_em       TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS pago_por          UUID,
    ADD COLUMN IF NOT EXISTS pago_em           TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS reaberto_de       UUID REFERENCES public.folha_13_calculo(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS reabertura_motivo TEXT,
    ADD COLUMN IF NOT EXISTS lote_id           UUID,
    ADD COLUMN IF NOT EXISTS observacao        TEXT;

COMMENT ON COLUMN public.folha_13_calculo.admissao_id IS
    'Vinculo real com a admissao que originou o calculo (o colaborador_id e TEXT solto, herdado).';
COMMENT ON COLUMN public.folha_13_calculo.data_prevista IS
    'Prazo legal da parcela (Lei 4.749/1965): 30/11 para a 1a, 20/12 para a 2a, antecipado por fim de semana ou feriado.';
COMMENT ON COLUMN public.folha_13_calculo.reaberto_de IS
    'Quando o calculo nasce da reabertura de um fechado, aponta para o anterior — a trilha nao se perde.';
COMMENT ON COLUMN public.folha_13_calculo.lote_id IS
    'Identifica a rodada de processamento em lote que gerou a linha.';

-- ── 2. Vocabulário de situação ────────────────────────────────────────
-- O default herdado é 'calculado'; o vocabulário passa a ser fechado.
-- NOT VALID de proposito: barra o que entra de agora em diante sem
-- varrer o historico de producao, que pode ter valor fora da lista.
DO $ck$
BEGIN
    ALTER TABLE public.folha_13_calculo
        ADD CONSTRAINT folha_13_calculo_status_ck
        CHECK (status IN ('rascunho', 'calculado', 'aprovado', 'pago', 'cancelado')) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

-- Valores não podem ser negativos.
DO $ck$
BEGIN
    ALTER TABLE public.folha_13_calculo
        ADD CONSTRAINT folha_13_calculo_valores_ck
        CHECK (valor_bruto >= 0 AND valor_inss >= 0 AND valor_irrf >= 0
               AND valor_fgts >= 0 AND total_descontos >= 0) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

-- Aprovado e pago exigem carimbo de quem e quando.
DO $ck$
BEGIN
    ALTER TABLE public.folha_13_calculo
        ADD CONSTRAINT folha_13_calculo_aprovacao_ck
        CHECK (status <> 'aprovado' OR aprovado_em IS NOT NULL) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

DO $ck$
BEGIN
    ALTER TABLE public.folha_13_calculo
        ADD CONSTRAINT folha_13_calculo_pagamento_ck
        CHECK (status <> 'pago' OR data_pagamento IS NOT NULL) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

-- ── Uma parcela viva por colaborador/ano ──────────────────────────────
-- Cancelado fica de fora: é o que permite reabrir sem apagar o
-- histórico. Linha sem CPF também, porque não identifica ninguém.
--
-- TOLERANTE DE PROPÓSITO: se a base já tiver duas parcelas vivas da
-- mesma pessoa (dado antigo), a criação do índice falharia e, num
-- script de uma transação só, derrubaria a entrega inteira. Aqui ela
-- avisa e segue; a conferência final aponta o que precisa ser
-- resolvido antes de tentar de novo.
DO $ix$
BEGIN
    CREATE UNIQUE INDEX IF NOT EXISTS folha_13_calculo_parcela_viva_uq
        ON public.folha_13_calculo (
            tenant_id, ano, parcela,
            regexp_replace(colaborador_cpf, '[^0-9]', '', 'g'),
            COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid))
        WHERE status <> 'cancelado'
          AND colaborador_cpf IS NOT NULL
          AND regexp_replace(colaborador_cpf, '[^0-9]', '', 'g') <> '';

    COMMENT ON INDEX public.folha_13_calculo_parcela_viva_uq IS
        'Uma parcela viva por colaborador/ano/empresa. Cancelado e linha sem CPF ficam de fora.';
EXCEPTION WHEN unique_violation OR others THEN
    RAISE NOTICE 'Unicidade da parcela viva NAO criada: %. Ha calculo duplicado na base — a conferencia final lista.', SQLERRM;
END $ix$;

-- ── 4. Camada de perfil: remuneração não é de todo mundo ──────────────
DO $rls$
DECLARE
    c_admin CONSTANT TEXT :=
        $a$public.perfil_permite_modulo(tenant_id, 'financeiro', 'colaboradores')$a$;
    c_proprio CONSTANT TEXT :=
        $p$regexp_replace(COALESCE(colaborador_cpf, ''), '[^0-9]', '', 'g')
             = public.cpf_do_usuario_logado()$p$;
BEGIN
    IF to_regclass('public.folha_13_calculo') IS NULL THEN
        RAISE NOTICE 'folha_13_calculo não existe nesta base; camada de perfil pulada.';
        RETURN;
    END IF;

    EXECUTE 'DROP POLICY IF EXISTS perfil_restringe_leitura_folha_13_calculo ON public.folha_13_calculo';
    EXECUTE format(
        'CREATE POLICY perfil_restringe_leitura_folha_13_calculo ON public.folha_13_calculo
           AS RESTRICTIVE FOR SELECT TO authenticated USING (%s OR %s)',
        c_admin, c_proprio);
    RAISE NOTICE 'Camada de perfil aplicada em folha_13_calculo: quem não administra a folha só vê o próprio 13º.';
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'folha_13_calculo ficou SEM a camada de perfil: %', SQLERRM;
END $rls$;

-- ── 5. Prazo legal da parcela (Lei 4.749/1965) ────────────────────────
-- 1ª até 30/11, 2ª até 20/12; se a data cair em fim de semana ou
-- feriado, ANTECIPA para o último dia útil anterior.
CREATE OR REPLACE FUNCTION public.decimo_terceiro_prazo_legal(
    p_ano     INT,
    p_parcela INT,
    p_uf      TEXT DEFAULT NULL,
    p_municipio TEXT DEFAULT NULL
)
RETURNS DATE
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    v_data DATE;
    v_i    INT := 0;
BEGIN
    IF p_ano IS NULL OR p_parcela NOT IN (1, 2) THEN
        RETURN NULL;
    END IF;

    v_data := CASE WHEN p_parcela = 1
                   THEN make_date(p_ano, 11, 30)
                   ELSE make_date(p_ano, 12, 20) END;

    -- Anda para trás até cair em dia útil. O limite de 15 tentativas é
    -- folga de sobra para qualquer emenda de feriados.
    WHILE v_i < 15 LOOP
        EXIT WHEN extract(isodow FROM v_data) < 6
              AND NOT EXISTS (
                  SELECT 1 FROM public.feriados f
                   WHERE COALESCE(f.ativo, true)
                     -- Só feriado de fato: facultativo não obriga a antecipar.
                     AND COALESCE(f.tipo, '') <> 'facultativo'
                     -- A tabela guarda data fixa OU recorrente por dia/mês.
                     AND (f.data = v_data
                          OR (COALESCE(f.recorrente, false)
                              AND f.dia = extract(day   FROM v_data)::int
                              AND f.mes = extract(month FROM v_data)::int))
                     AND (COALESCE(f.abrangencia, 'nacional') = 'nacional'
                          OR (p_uf IS NOT NULL AND f.uf = p_uf)
                          OR (p_municipio IS NOT NULL AND f.municipio = p_municipio)));
        v_data := v_data - 1;
        v_i := v_i + 1;
    END LOOP;

    RETURN v_data;
END $fn$;

COMMENT ON FUNCTION public.decimo_terceiro_prazo_legal(INT, INT, TEXT, TEXT) IS
    'Prazo legal da parcela do 13o (Lei 4.749/1965): 30/11 e 20/12, antecipando para o ultimo dia util anterior quando cai em fim de semana ou feriado.';

GRANT EXECUTE ON FUNCTION public.decimo_terceiro_prazo_legal(INT, INT, TEXT, TEXT) TO authenticated;



-- ── 1. INSS progressivo ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.decimo_terceiro_inss(
    p_base     NUMERIC,
    p_tenant   UUID DEFAULT NULL,
    p_data_ref DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    v_faixas JSONB;
    v_teto   NUMERIC(12,2);
    v_base   NUMERIC(12,2);
    v_valor  NUMERIC(12,2) := 0;
    v_det    JSONB := '[]'::jsonb;
    v_origem TEXT := 'tabela da empresa';
    r        RECORD;
    v_parc   NUMERIC(12,2);
BEGIN
    IF p_tenant IS NOT NULL THEN
        SELECT t.faixas, t.teto INTO v_faixas, v_teto
          FROM public.folha_tabelas_inss t
         WHERE t.tenant_id = p_tenant
           AND t.vigencia_inicio <= p_data_ref
           AND (t.vigencia_fim IS NULL OR t.vigencia_fim >= p_data_ref)
         ORDER BY t.vigencia_inicio DESC
         LIMIT 1;
    END IF;

    IF v_faixas IS NULL OR jsonb_array_length(v_faixas) = 0 THEN
        -- Padrão de 2025, o mesmo embutido no front. Fica registrado na
        -- memória para ninguém confundir com tabela cadastrada.
        v_faixas := '[{"de":0,"ate":1518.00,"aliquota":7.5},
                      {"de":1518.01,"ate":2793.88,"aliquota":9},
                      {"de":2793.89,"ate":4190.83,"aliquota":12},
                      {"de":4190.84,"ate":8157.41,"aliquota":14}]'::jsonb;
        v_teto   := 8157.41;
        v_origem := 'padrao 2025 (empresa sem tabela vigente cadastrada)';
    END IF;

    v_base := least(COALESCE(p_base, 0), COALESCE(v_teto, 8157.41));
    IF v_base <= 0 THEN
        RETURN jsonb_build_object('valor', 0, 'base_efetiva', 0,
                                  'origem_tabela', v_origem, 'faixas', '[]'::jsonb);
    END IF;

    FOR r IN
        SELECT (f->>'de')::NUMERIC       AS de,
               (f->>'ate')::NUMERIC      AS ate,
               (f->>'aliquota')::NUMERIC AS aliquota
          FROM jsonb_array_elements(v_faixas) f
         ORDER BY (f->>'de')::NUMERIC
    LOOP
        -- Base dentro da faixa: o "de" começa em X,01, então o teto da
        -- faixa anterior é de - 0,01. Arredonda por faixa, como o front.
        v_parc := greatest(0, least(v_base, r.ate) - greatest(0, r.de - 0.01));
        EXIT WHEN v_parc <= 0 AND v_base < r.de;
        CONTINUE WHEN v_parc <= 0;

        v_parc := round(v_parc * r.aliquota / 100, 2);
        v_valor := v_valor + v_parc;
        v_det := v_det || jsonb_build_object(
            'de', r.de, 'ate', r.ate, 'aliquota', r.aliquota, 'valor', v_parc);
    END LOOP;

    RETURN jsonb_build_object(
        'valor', round(v_valor, 2), 'base_efetiva', v_base,
        'origem_tabela', v_origem, 'faixas', v_det);
END $fn$;

COMMENT ON FUNCTION public.decimo_terceiro_inss(NUMERIC, UUID, DATE) IS
    'INSS progressivo do 13o pela tabela vigente da empresa (folha_tabelas_inss), com a memoria faixa a faixa. Somente leitura.';

-- ── 2. IRRF exclusivo na fonte ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.decimo_terceiro_irrf(
    p_base        NUMERIC,
    p_dependentes INT DEFAULT 0,
    p_tenant      UUID DEFAULT NULL,
    p_data_ref    DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    v_faixas JSONB;
    v_ded_dep NUMERIC(12,2);
    v_base   NUMERIC(12,2);
    v_origem TEXT := 'tabela da empresa';
    r        RECORD;
BEGIN
    IF p_tenant IS NOT NULL THEN
        SELECT t.faixas, t.deducao_por_dependente INTO v_faixas, v_ded_dep
          FROM public.folha_tabelas_irrf t
         WHERE t.tenant_id = p_tenant
           AND t.vigencia_inicio <= p_data_ref
           AND (t.vigencia_fim IS NULL OR t.vigencia_fim >= p_data_ref)
         ORDER BY t.vigencia_inicio DESC
         LIMIT 1;
    END IF;

    IF v_faixas IS NULL OR jsonb_array_length(v_faixas) = 0 THEN
        v_faixas := '[{"de":0,"ate":2259.20,"aliquota":0,"deducao":0},
                      {"de":2259.21,"ate":2826.65,"aliquota":7.5,"deducao":169.44},
                      {"de":2826.66,"ate":3751.05,"aliquota":15,"deducao":381.44},
                      {"de":3751.06,"ate":4664.68,"aliquota":22.5,"deducao":662.77},
                      {"de":4664.69,"ate":999999999,"aliquota":27.5,"deducao":896.00}]'::jsonb;
        v_ded_dep := 189.59;
        v_origem  := 'padrao 2025 (empresa sem tabela vigente cadastrada)';
    END IF;

    v_base := COALESCE(p_base, 0) - (COALESCE(p_dependentes, 0) * COALESCE(v_ded_dep, 0));

    IF v_base <= 0 THEN
        RETURN jsonb_build_object('valor', 0, 'base_efetiva', 0, 'aliquota', 0,
                                  'faixa', 'Isento', 'origem_tabela', v_origem);
    END IF;

    FOR r IN
        SELECT (f->>'de')::NUMERIC       AS de,
               (f->>'ate')::NUMERIC      AS ate,
               (f->>'aliquota')::NUMERIC AS aliquota,
               (f->>'deducao')::NUMERIC  AS deducao
          FROM jsonb_array_elements(v_faixas) f
         ORDER BY (f->>'de')::NUMERIC
    LOOP
        IF v_base >= r.de AND v_base <= r.ate THEN
            RETURN jsonb_build_object(
                'valor', greatest(0, round(v_base * r.aliquota / 100 - r.deducao, 2)),
                'base_efetiva', v_base,
                'aliquota', r.aliquota,
                'deducao_faixa', r.deducao,
                'deducao_dependentes', COALESCE(p_dependentes,0) * COALESCE(v_ded_dep,0),
                'faixa', format('R$ %s a R$ %s', r.de, r.ate),
                'origem_tabela', v_origem);
        END IF;
    END LOOP;

    RETURN jsonb_build_object('valor', 0, 'base_efetiva', v_base, 'aliquota', 0,
                              'faixa', 'Isento', 'origem_tabela', v_origem);
END $fn$;

COMMENT ON FUNCTION public.decimo_terceiro_irrf(NUMERIC, INT, UUID, DATE) IS
    'IRRF exclusivo na fonte do 13o pela tabela vigente da empresa (folha_tabelas_irrf), com deducao por dependente. Somente leitura.';

GRANT EXECUTE ON FUNCTION public.decimo_terceiro_inss(NUMERIC, UUID, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decimo_terceiro_irrf(NUMERIC, INT, UUID, DATE) TO authenticated;

-- ── 3. Uma parcela inteira ────────────────────────────────────────────
-- Espelha calcular13 do front: 1ª parcela é 50% sem INSS/IRRF (o FGTS
-- incide na competência do pagamento); 2ª aplica INSS e IRRF sobre o
-- 13º cheio, calculado em separado da folha do mês (RN-005/007), deduz
-- o adiantamento e recolhe FGTS sobre a diferença.
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
        v_primeira  := round(v_bruto / 2, 2);
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
            'fundamento', 'Lei 4.749/1965 (parcelas); INSS e IRRF so na 2a; FGTS nas duas'));
END $fn$;

COMMENT ON FUNCTION public.decimo_terceiro_calcular(UUID, TEXT, INT, INT, UUID, INT, NUMERIC, TEXT) IS
    'Calcula uma parcela do 13o de um vinculo (bruto, INSS, IRRF, FGTS, liquido) com a memoria completa. Somente leitura: nada e gravado.';

GRANT EXECUTE ON FUNCTION public.decimo_terceiro_calcular(UUID, TEXT, INT, INT, UUID, INT, NUMERIC, TEXT) TO authenticated;


-- ── 4. A empresa inteira de uma vez ───────────────────────────────────
-- Idempotente: quem já tem cálculo vivo daquela parcela é pulado, não
-- duplicado (a unicidade do índice também barraria). Grava competência,
-- prazo legal e o identificador do lote.
CREATE OR REPLACE FUNCTION public.decimo_terceiro_lote(
    p_tenant  UUID,
    p_ano     INT,
    p_parcela INT,
    p_empresa UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    v_lote     UUID := gen_random_uuid();
    v_prazo    DATE;
    a          RECORD;
    v_c        JSONB;
    v_criados  INT := 0;
    v_pulados  INT := 0;
    v_semavo   INT := 0;
    v_erros    JSONB := '[]'::jsonb;
    v_total    NUMERIC(14,2) := 0;
BEGIN
    IF p_tenant IS NULL OR p_ano IS NULL OR p_parcela NOT IN (1, 2) THEN
        RETURN jsonb_build_object('erro', 'Informe empresa, ano-base e parcela (1 ou 2).');
    END IF;

    v_prazo := public.decimo_terceiro_prazo_legal(p_ano, p_parcela);

    FOR a IN
        SELECT ad.id, ad.nome_completo, ad.cpf, ad.tipo_contrato, ad.empresa_id
          FROM public.admissoes ad
         WHERE ad.tenant_id = p_tenant
           AND ad.status = 'concluido'
           AND ad.data_admissao IS NOT NULL
           AND (p_empresa IS NULL OR ad.empresa_id = p_empresa)
         ORDER BY ad.nome_completo
    LOOP
        BEGIN
            -- Já existe cálculo vivo desta parcela? Então não se mexe.
            IF EXISTS (
                SELECT 1 FROM public.folha_13_calculo c
                 WHERE c.tenant_id = p_tenant AND c.ano = p_ano AND c.parcela = p_parcela
                   AND regexp_replace(COALESCE(c.colaborador_cpf,''), '[^0-9]', '', 'g')
                       = regexp_replace(COALESCE(a.cpf,''), '[^0-9]', '', 'g')
                   AND c.status <> 'cancelado')
            THEN
                v_pulados := v_pulados + 1;
                CONTINUE;
            END IF;

            v_c := public.decimo_terceiro_calcular(
                       p_tenant, a.cpf, p_ano, p_parcela, p_empresa, 0, NULL, a.tipo_contrato);

            -- Sem avo não há 13º a pagar: não se grava linha zerada.
            IF COALESCE((v_c->>'avos')::INT, 0) = 0 THEN
                v_semavo := v_semavo + 1;
                CONTINUE;
            END IF;

            INSERT INTO public.folha_13_calculo (
                tenant_id, empresa_id, admissao_id, ano, parcela,
                colaborador_id, colaborador_nome, colaborador_cpf, tipo_vinculo,
                meses_trabalhados, remuneracao_base, media_variaveis,
                valor_bruto, valor_primeira_parcela,
                base_inss, valor_inss, base_irrf, valor_irrf,
                base_fgts, valor_fgts, total_descontos, total_liquido,
                status, competencia, data_prevista, lote_id,
                avos_origem, media_origem, memoria_calculo)
            VALUES (
                p_tenant, a.empresa_id, a.id, p_ano, p_parcela,
                a.id::text, a.nome_completo, a.cpf, a.tipo_contrato,
                (v_c->>'avos')::INT,
                (v_c->>'remuneracao_base')::NUMERIC, (v_c->>'media_variaveis')::NUMERIC,
                (v_c->>'valor_bruto')::NUMERIC, (v_c->>'valor_primeira_parcela')::NUMERIC,
                (v_c->>'base_inss')::NUMERIC, (v_c->>'valor_inss')::NUMERIC,
                (v_c->>'base_irrf')::NUMERIC, (v_c->>'valor_irrf')::NUMERIC,
                (v_c->>'base_fgts')::NUMERIC, (v_c->>'valor_fgts')::NUMERIC,
                (v_c->>'total_descontos')::NUMERIC, (v_c->>'total_liquido')::NUMERIC,
                'calculado', v_c->>'competencia', v_prazo, v_lote,
                'apurado', 'apurado', v_c->'memoria');

            v_criados := v_criados + 1;
            v_total   := v_total + COALESCE((v_c->>'total_liquido')::NUMERIC, 0);

        EXCEPTION WHEN OTHERS THEN
            -- Um colaborador problemático não derruba a folha inteira,
            -- mas volta nomeado no resultado.
            v_erros := v_erros || jsonb_build_object(
                'colaborador', a.nome_completo, 'erro', SQLERRM);
        END;
    END LOOP;

    RETURN jsonb_build_object(
        'lote_id', v_lote, 'ano', p_ano, 'parcela', p_parcela,
        'prazo_legal', v_prazo,
        'criados', v_criados, 'ja_existiam', v_pulados, 'sem_avo', v_semavo,
        'total_liquido', round(v_total, 2),
        'erros', v_erros, 'processado_em', now());
END $fn$;

COMMENT ON FUNCTION public.decimo_terceiro_lote(UUID, INT, INT, UUID) IS
    'Calcula e grava a parcela do 13o de todos os vinculos da empresa de uma vez. Idempotente: quem ja tem calculo vivo e pulado. Devolve o resumo do lote.';

GRANT EXECUTE ON FUNCTION public.decimo_terceiro_lote(UUID, INT, INT, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.decimo_terceiro_aprovar(
    p_calculo UUID,
    p_nome    TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE r public.folha_13_calculo;
BEGIN
    SELECT * INTO r FROM public.folha_13_calculo WHERE id = p_calculo;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('erro', 'Cálculo não encontrado.');
    END IF;
    IF r.status = 'cancelado' THEN
        RETURN jsonb_build_object('erro', 'Cálculo cancelado não pode ser aprovado.');
    END IF;
    IF r.status IN ('aprovado', 'pago') THEN
        RETURN jsonb_build_object('ok', true, 'ja_estava', r.status, 'id', r.id);
    END IF;

    UPDATE public.folha_13_calculo
       SET status = 'aprovado',
           aprovado_por = auth.uid(),
           aprovado_por_nome = p_nome,
           aprovado_em = now(),
           updated_at = now()
     WHERE id = p_calculo;

    RETURN jsonb_build_object('ok', true, 'id', p_calculo, 'status', 'aprovado');
END $fn$;

-- ── 2. Pagar ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.decimo_terceiro_pagar(
    p_calculo UUID,
    p_data    DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    r public.folha_13_calculo;
    v_atraso INT;
BEGIN
    SELECT * INTO r FROM public.folha_13_calculo WHERE id = p_calculo;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('erro', 'Cálculo não encontrado.');
    END IF;
    IF r.status = 'cancelado' THEN
        RETURN jsonb_build_object('erro', 'Cálculo cancelado não pode ser pago.');
    END IF;
    IF r.status <> 'aprovado' AND r.status <> 'pago' THEN
        RETURN jsonb_build_object('erro',
            'Só se paga o que foi aprovado. Situação atual: ' || r.status);
    END IF;

    UPDATE public.folha_13_calculo
       SET status = 'pago', data_pagamento = p_data,
           pago_por = auth.uid(), pago_em = now(), updated_at = now()
     WHERE id = p_calculo;

    -- O prazo é legal (Lei 4.749): pagar depois vira multa. O sistema
    -- não impede, mas devolve o atraso para quem paga ver.
    v_atraso := CASE WHEN r.data_prevista IS NOT NULL AND p_data > r.data_prevista
                     THEN p_data - r.data_prevista ELSE 0 END;

    RETURN jsonb_build_object(
        'ok', true, 'id', p_calculo, 'status', 'pago',
        'data_pagamento', p_data, 'prazo_legal', r.data_prevista,
        'dias_de_atraso', v_atraso,
        'aviso', CASE WHEN v_atraso > 0
                      THEN format('Pagamento %s dia(s) após o prazo legal (%s) — Lei 4.749/1965.',
                                  v_atraso, r.data_prevista)
                      ELSE NULL END);
END $fn$;

-- ── 3. Reabrir: cancela e recria, nunca sobrescreve ───────────────────
CREATE OR REPLACE FUNCTION public.decimo_terceiro_reabrir(
    p_calculo UUID,
    p_motivo  TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    r      public.folha_13_calculo;
    v_c    JSONB;
    v_novo UUID;
    v_dif  NUMERIC(12,2);
BEGIN
    IF p_motivo IS NULL OR length(btrim(p_motivo)) < 10 THEN
        RETURN jsonb_build_object('erro',
            'Reabertura exige motivo escrito (ao menos 10 caracteres) — é o que fica na trilha.');
    END IF;

    SELECT * INTO r FROM public.folha_13_calculo WHERE id = p_calculo;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('erro', 'Cálculo não encontrado.');
    END IF;
    IF r.status = 'cancelado' THEN
        RETURN jsonb_build_object('erro', 'Este cálculo já foi cancelado por uma reabertura anterior.');
    END IF;

    -- Dupla aprovação: quem aprovou não reabre o próprio ato.
    IF r.aprovado_por IS NOT NULL AND auth.uid() IS NOT NULL
       AND r.aprovado_por = auth.uid() THEN
        RETURN jsonb_build_object('erro',
            'Quem aprovou este cálculo não pode reabri-lo: a reabertura exige uma segunda pessoa.');
    END IF;

    v_c := public.decimo_terceiro_calcular(
               r.tenant_id, r.colaborador_cpf, r.ano, r.parcela,
               r.empresa_id, 0, r.valor_primeira_parcela, r.tipo_vinculo);

    -- Cancela primeiro: a unicidade só admite uma parcela viva.
    UPDATE public.folha_13_calculo
       SET status = 'cancelado', observacao = COALESCE(observacao || ' | ', '') ||
           format('Cancelado por reabertura em %s: %s', now()::date, p_motivo),
           updated_at = now()
     WHERE id = p_calculo;

    INSERT INTO public.folha_13_calculo (
        tenant_id, empresa_id, admissao_id, ano, parcela,
        colaborador_id, colaborador_nome, colaborador_cpf, tipo_vinculo,
        meses_trabalhados, remuneracao_base, media_variaveis,
        valor_bruto, valor_primeira_parcela,
        base_inss, valor_inss, base_irrf, valor_irrf,
        base_fgts, valor_fgts, total_descontos, total_liquido,
        status, competencia, data_prevista,
        reaberto_de, reabertura_motivo,
        avos_origem, media_origem, memoria_calculo)
    VALUES (
        r.tenant_id, r.empresa_id, r.admissao_id, r.ano, r.parcela,
        r.colaborador_id, r.colaborador_nome, r.colaborador_cpf, r.tipo_vinculo,
        (v_c->>'avos')::INT,
        (v_c->>'remuneracao_base')::NUMERIC, (v_c->>'media_variaveis')::NUMERIC,
        (v_c->>'valor_bruto')::NUMERIC, (v_c->>'valor_primeira_parcela')::NUMERIC,
        (v_c->>'base_inss')::NUMERIC, (v_c->>'valor_inss')::NUMERIC,
        (v_c->>'base_irrf')::NUMERIC, (v_c->>'valor_irrf')::NUMERIC,
        (v_c->>'base_fgts')::NUMERIC, (v_c->>'valor_fgts')::NUMERIC,
        (v_c->>'total_descontos')::NUMERIC, (v_c->>'total_liquido')::NUMERIC,
        'calculado', v_c->>'competencia', (v_c->>'data_prevista')::DATE,
        r.id, p_motivo,
        'apurado', 'apurado', v_c->'memoria')
    RETURNING id INTO v_novo;

    v_dif := round(COALESCE((v_c->>'total_liquido')::NUMERIC, 0) - COALESCE(r.total_liquido, 0), 2);

    RETURN jsonb_build_object(
        'ok', true,
        'cancelado', r.id, 'novo', v_novo,
        'liquido_anterior', r.total_liquido,
        'liquido_novo', (v_c->>'total_liquido')::NUMERIC,
        'diferenca', v_dif,
        'sentido', CASE WHEN v_dif > 0 THEN 'complemento a pagar'
                        WHEN v_dif < 0 THEN 'estorno a apurar'
                        ELSE 'sem diferença' END,
        'motivo', p_motivo);
END $fn$;

-- ── 4. Trava: dinheiro fechado não se sobrescreve ─────────────────────
CREATE OR REPLACE FUNCTION public.decimo_terceiro_trava_fechado()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $tg$
BEGIN
    -- Só protege os valores. Mudar situação, datas e carimbos é o
    -- caminho normal de aprovar, pagar e cancelar por reabertura.
    IF OLD.status IN ('aprovado', 'pago')
       AND (NEW.valor_bruto      IS DISTINCT FROM OLD.valor_bruto
         OR NEW.valor_inss       IS DISTINCT FROM OLD.valor_inss
         OR NEW.valor_irrf       IS DISTINCT FROM OLD.valor_irrf
         OR NEW.valor_fgts       IS DISTINCT FROM OLD.valor_fgts
         OR NEW.total_liquido    IS DISTINCT FROM OLD.total_liquido
         OR NEW.meses_trabalhados IS DISTINCT FROM OLD.meses_trabalhados)
    THEN
        RAISE EXCEPTION 'Cálculo de 13º já % não pode ter valores alterados. Use a reabertura, que preserva o histórico e registra o motivo.', OLD.status
            USING ERRCODE = 'raise_exception';
    END IF;
    RETURN NEW;
END $tg$;

DROP TRIGGER IF EXISTS trg_decimo_terceiro_trava_fechado ON public.folha_13_calculo;
CREATE TRIGGER trg_decimo_terceiro_trava_fechado
BEFORE UPDATE ON public.folha_13_calculo
FOR EACH ROW EXECUTE FUNCTION public.decimo_terceiro_trava_fechado();

COMMENT ON FUNCTION public.decimo_terceiro_reabrir(UUID, TEXT) IS
    'Reabre uma parcela fechada: cancela a linha antiga e cria a nova apontando para ela (reaberto_de), com motivo obrigatorio e a diferenca apurada. Exige segunda pessoa: quem aprovou nao reabre.';

GRANT EXECUTE ON FUNCTION public.decimo_terceiro_aprovar(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decimo_terceiro_pagar(UUID, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decimo_terceiro_reabrir(UUID, TEXT) TO authenticated;

-- ── 2. DEC13-070: a sonda informa a data de pagamento ─────────────────

-- ── 3. As regras dos encargos passam a viver no banco ─────────────────
-- Até aqui elas existiam só no cálculo da tela: quem gravasse por fora
-- (importação, script, integração) furava a regra sem resistência.
-- Casos DEC13-040, DEC13-041 e DEC13-042.

-- INSS e IRRF só na 2ª parcela (Lei 4.749/1965; RIR/2018 art. 700: a
-- tributação é exclusiva na fonte, apurada na 2ª sobre o valor integral).
DO $ck$
BEGIN
    ALTER TABLE public.folha_13_calculo
        ADD CONSTRAINT folha_13_calculo_encargos_2a_ck
        CHECK (parcela <> 1
               OR (COALESCE(valor_inss, 0) = 0 AND COALESCE(valor_irrf, 0) = 0
                   AND COALESCE(base_inss, 0) = 0 AND COALESCE(base_irrf, 0) = 0)) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

-- FGTS incide sobre a parcela paga, nunca sobre mais que o 13º cheio
-- (Lei 8.036 art. 15): a soma das duas bases fecha exatamente o bruto.
DO $ck$
BEGIN
    ALTER TABLE public.folha_13_calculo
        ADD CONSTRAINT folha_13_calculo_base_fgts_ck
        CHECK (COALESCE(base_fgts, 0) <= COALESCE(valor_bruto, 0)) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

-- O adiantamento deduzido não pode superar o próprio 13º.
DO $ck$
BEGIN
    ALTER TABLE public.folha_13_calculo
        ADD CONSTRAINT folha_13_calculo_primeira_ck
        CHECK (COALESCE(valor_primeira_parcela, 0) <= COALESCE(valor_bruto, 0)) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

-- ── Sonda de QA DEC13-070 acompanha a trava nova ──────────────────────
-- O CHECK de pagamento (acima) recusa status 'pago' sem data. A sonda de
-- QA foi escrita para o banco antigo, frouxo: ela gravava 'pago' sem
-- data e, com a trava, passaria a devolver 'erro' em vez de julgar o
-- sistema. A sonda se ajusta a regra nova; a regra fica.
-- ── 2. DEC13-070: a sonda informa a data de pagamento ─────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_070()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_id uuid; v_alterou boolean := false; v_trg text;
BEGIN
  -- A sonda grava e NÃO desfaz (padrão desta família). Com a unicidade
  -- da Entrega 2, rodar duas vezes colidiria com a própria linha da
  -- rodada anterior — então ela limpa o próprio rastro antes.
  DELETE FROM public.folha_13_calculo
   WHERE tenant_id = public.qa_sandbox_tenant_id()
     AND colaborador_id = 'qa-dec13-070';

  -- Pago exige data de pagamento desde a Entrega 2 (CHECK
  -- folha_13_calculo_pagamento_ck) — a sonda informa, como a tela faz.
  INSERT INTO public.folha_13_calculo
    (tenant_id, ano, colaborador_id, colaborador_nome, colaborador_cpf, parcela,
     valor_bruto, total_liquido, status, data_pagamento)
  VALUES (public.qa_sandbox_tenant_id(), extract(year from CURRENT_DATE)::int,
          'qa-dec13-070', 'QA Pago Editado', '00000000070', 2, 3000, 2500,
          'pago', CURRENT_DATE)
  RETURNING id INTO v_id;

  r.passo_ordem := 1;
  r.passo_acao := 'Editar diretamente o valor bruto de um cálculo com status PAGO';
  r.esperado := 'Bloqueado — valor pago só muda por reabertura com motivo, dupla aprovação e diferença';
  BEGIN
    UPDATE public.folha_13_calculo SET valor_bruto = 9999 WHERE id = v_id;
    SELECT (valor_bruto = 9999) INTO v_alterou FROM public.folha_13_calculo WHERE id = v_id;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_alterou := false; END;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: existe trilha de alteração na tabela do 13º?';
  r.esperado := 'Gatilho de auditoria registrando antes/depois (RNF-004: log imutável)';
  SELECT string_agg(DISTINCT t.tgname, ', ') INTO v_trg
  FROM pg_trigger t
  WHERE t.tgrelid = 'public.folha_13_calculo'::regclass AND NOT t.tgisinternal
    AND t.tgname NOT ILIKE '%updated_at%' AND t.tgname NOT ILIKE 'qa\_%';

  IF v_alterou AND v_trg IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: um cálculo PAGO foi editado em silêncio — o valor bruto mudou de 3.000 '
             || 'para 9.999 sem bloqueio, sem justificativa, sem aprovação e sem trilha. '
             || 'Correção: trava de UPDATE para status pago/fechado + fluxo de reabertura '
             || '(RF-007 do documento).';
  ELSIF NOT v_alterou THEN
    r.situacao := 'passou';
    r.obtido := format('A edição direta do cálculo pago foi recusada pela trava do banco%s.',
                       CASE WHEN v_trg IS NULL THEN '' ELSE ' (gatilhos: ' || v_trg || ')' END);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Alteração registrada em trilha (%s) — conferir se guarda antes/depois.', v_trg);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── 2. As regras dos encargos passam a viver no banco ─────────────────
-- Até aqui elas existiam só no cálculo da tela: quem gravasse por fora
-- (importação, script, integração) furava a regra sem resistência.
-- Casos DEC13-040, DEC13-041 e DEC13-042.

-- INSS e IRRF só na 2ª parcela (Lei 4.749/1965; RIR/2018 art. 700: a
-- tributação é exclusiva na fonte, apurada na 2ª sobre o valor integral).
DO $ck$
BEGIN
    ALTER TABLE public.folha_13_calculo
        ADD CONSTRAINT folha_13_calculo_encargos_2a_ck
        CHECK (parcela <> 1
               OR (COALESCE(valor_inss, 0) = 0 AND COALESCE(valor_irrf, 0) = 0
                   AND COALESCE(base_inss, 0) = 0 AND COALESCE(base_irrf, 0) = 0)) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

-- FGTS incide sobre a parcela paga, nunca sobre mais que o 13º cheio
-- (Lei 8.036 art. 15): a soma das duas bases fecha exatamente o bruto.
DO $ck$
BEGIN
    ALTER TABLE public.folha_13_calculo
        ADD CONSTRAINT folha_13_calculo_base_fgts_ck
        CHECK (COALESCE(base_fgts, 0) <= COALESCE(valor_bruto, 0)) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

-- O adiantamento deduzido não pode superar o próprio 13º.
DO $ck$
BEGIN
    ALTER TABLE public.folha_13_calculo
        ADD CONSTRAINT folha_13_calculo_primeira_ck
        CHECK (COALESCE(valor_primeira_parcela, 0) <= COALESCE(valor_bruto, 0)) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;


-- ════════════════════════════════════════════════════════════════════
-- 3) Adiantamento a escolha da empresa e media fisica (Sumula 347)
-- ════════════════════════════════════════════════════════════════════
-- Requisitos YE-DP-13-001: RF-002, RN-002, RN-003, CA-003, [VAL] das
-- Súmulas do TST e da política de adiantamento.
-- =========================================================


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


-- ════════════════════════════════════════════════════════════════════
-- 4) Prazos: alertas D-30/15/7 e D-15/7/3, com Plano de Acao
-- ════════════════════════════════════════════════════════════════════
-- =========================================================


-- ── 1. O vocabulário de prazos aprende o 13º ──────────────────────────
ALTER TABLE public.folha_alertas_prazo
    DROP CONSTRAINT IF EXISTS folha_alertas_prazo_tipo_check;

ALTER TABLE public.folha_alertas_prazo
    ADD CONSTRAINT folha_alertas_prazo_tipo_check CHECK (tipo IN (
        'fechamento_folha', 'pagamento', 'fgts', 'esocial_s1200',
        'esocial_s1210', 'dctfweb', 'inss_patronal', 'rescisao_pagamento',
        -- 13º salário (Lei 4.749/1965 e Decreto 57.155/1965)
        'decimo_terceiro_1a_parcela',
        'decimo_terceiro_2a_parcela',
        'decimo_terceiro_base_incompleta',
        'decimo_terceiro_afastamento'
    ));

ALTER TABLE public.folha_alertas_prazo
    ADD COLUMN IF NOT EXISTS empresa_id    UUID,
    ADD COLUMN IF NOT EXISTS severidade    TEXT NOT NULL DEFAULT 'media',
    ADD COLUMN IF NOT EXISTS faixa         TEXT,
    ADD COLUMN IF NOT EXISTS ano           INT,
    ADD COLUMN IF NOT EXISTS plano_acao_id UUID,
    ADD COLUMN IF NOT EXISTS updated_at    TIMESTAMPTZ NOT NULL DEFAULT now();

DO $ck$
BEGIN
    ALTER TABLE public.folha_alertas_prazo
        ADD CONSTRAINT folha_alertas_prazo_severidade_ck
        CHECK (severidade IN ('baixa', 'media', 'alta', 'critica')) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

-- Um alerta por tipo/marco/colaborador/ano: a varredura roda todo dia e
-- não pode acumular a mesma cobrança.
CREATE UNIQUE INDEX IF NOT EXISTS folha_alertas_prazo_unico
    ON public.folha_alertas_prazo (
        tenant_id, tipo,
        COALESCE(ano, 0),
        COALESCE(faixa, ''),
        COALESCE(colaborador_id, ''),
        COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid));

CREATE INDEX IF NOT EXISTS idx_folha_alertas_prazo_pendentes
    ON public.folha_alertas_prazo (tenant_id, status, data_limite);

COMMENT ON COLUMN public.folha_alertas_prazo.faixa IS
    'Marco atingido: d30 | d15 | d7 | d3 | vencida | unica. Um alerta por marco, para a varredura diaria nao duplicar.';

-- ── 2. A varredura ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.decimo_terceiro_alertas_varrer(
    p_tenant UUID DEFAULT NULL,
    p_ano    INT  DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
    v_ano      INT := COALESCE(p_ano, extract(year FROM CURRENT_DATE)::INT);
    t          RECORD;
    v_prazo    DATE;
    v_dias     INT;
    v_faixa    TEXT;
    v_sev      TEXT;
    v_pend     INT;
    v_parcela  INT;
    v_novos    INT := 0;
    v_acoes    INT := 0;
    v_id       UUID;
    r          RECORD;
BEGIN
    FOR t IN
        SELECT id FROM public.tenants
         WHERE (p_tenant IS NULL OR id = p_tenant)
           AND COALESCE(ativo, true)
    LOOP
        -- ── a) Prazo das duas parcelas (Lei 4.749/1965) ──────────────
        FOREACH v_parcela IN ARRAY ARRAY[1, 2] LOOP
            v_prazo := public.decimo_terceiro_prazo_legal(v_ano, v_parcela);
            v_dias  := v_prazo - CURRENT_DATE;

            -- Quantos vínculos ainda não têm a parcela paga?
            SELECT count(*) INTO v_pend
              FROM public.admissoes a
             WHERE a.tenant_id = t.id
               AND a.status = 'concluido'
               AND a.data_admissao IS NOT NULL
               AND a.data_admissao <= make_date(v_ano, 12, 31)
               AND NOT EXISTS (
                   SELECT 1 FROM public.folha_13_calculo c
                    WHERE c.tenant_id = t.id AND c.ano = v_ano
                      AND c.parcela = v_parcela AND c.status = 'pago'
                      AND regexp_replace(COALESCE(c.colaborador_cpf,''), '[^0-9]', '', 'g')
                          = regexp_replace(COALESCE(a.cpf,''), '[^0-9]', '', 'g'));

            CONTINUE WHEN v_pend = 0;   -- todo mundo pago: nada a cobrar

            -- Marcos: 1ª parcela D-30/15/7; 2ª D-15/7/3 (seção 14).
            v_faixa := CASE
                WHEN v_dias < 0 THEN 'vencida'
                WHEN v_parcela = 1 AND v_dias <= 7  THEN 'd7'
                WHEN v_parcela = 1 AND v_dias <= 15 THEN 'd15'
                WHEN v_parcela = 1 AND v_dias <= 30 THEN 'd30'
                WHEN v_parcela = 2 AND v_dias <= 3  THEN 'd3'
                WHEN v_parcela = 2 AND v_dias <= 7  THEN 'd7'
                WHEN v_parcela = 2 AND v_dias <= 15 THEN 'd15'
                ELSE NULL END;

            CONTINUE WHEN v_faixa IS NULL;  -- ainda longe do prazo

            v_sev := CASE WHEN v_faixa = 'vencida' THEN 'critica'
                          WHEN v_parcela = 2 THEN 'critica'
                          ELSE 'alta' END;

            INSERT INTO public.folha_alertas_prazo (
                tenant_id, ano, tipo, faixa, severidade, competencia,
                data_limite, status, descricao, valor_referencia)
            VALUES (
                t.id, v_ano,
                CASE WHEN v_parcela = 1 THEN 'decimo_terceiro_1a_parcela'
                     ELSE 'decimo_terceiro_2a_parcela' END,
                v_faixa, v_sev, to_char(v_prazo, 'YYYY-MM'),
                v_prazo,
                CASE WHEN v_faixa = 'vencida' THEN 'atrasado' ELSE 'pendente' END,
                CASE WHEN v_faixa = 'vencida'
                     THEN format('%sª parcela do 13º VENCIDA em %s: %s vínculo(s) sem pagamento registrado. Atraso gera multa (Lei 4.749/1965).',
                                 v_parcela, to_char(v_prazo, 'DD/MM/YYYY'), v_pend)
                     ELSE format('%sª parcela do 13º vence em %s dia(s), em %s: %s vínculo(s) ainda sem pagamento.',
                                 v_parcela, v_dias, to_char(v_prazo, 'DD/MM/YYYY'), v_pend) END,
                v_pend)
            ON CONFLICT DO NOTHING
            RETURNING id INTO v_id;

            IF v_id IS NOT NULL THEN
                v_novos := v_novos + 1;
                -- Ação automática só no crítico.
                IF v_sev = 'critica' THEN
                    PERFORM public.decimo_terceiro_alerta_gerar_acao(v_id);
                    v_acoes := v_acoes + 1;
                END IF;
            END IF;
        END LOOP;

        -- ── b) Base de médias incompleta ─────────────────────────────
        -- Quem tem variável em algum mês do ano, mas com competências
        -- FALTANDO: a folha não foi importada e o 13º sairia menor.
        FOR r IN
            WITH esperado AS (
                SELECT a.id, a.cpf, a.nome_completo, a.empresa_id,
                       greatest(a.data_admissao, make_date(v_ano, 1, 1)) AS ini,
                       least(CURRENT_DATE, make_date(v_ano, 12, 31))     AS fim
                  FROM public.admissoes a
                 WHERE a.tenant_id = t.id AND a.status = 'concluido'
                   AND a.data_admissao IS NOT NULL
                   AND a.data_admissao <= least(CURRENT_DATE, make_date(v_ano, 12, 31))
            ),
            contagem AS (
                SELECT e.*,
                       (SELECT count(DISTINCT pe.competencia)
                          FROM public.folha_lancamentos l
                          JOIN public.folha_periodos pe ON pe.id = l.periodo_id
                          JOIN public.folha_rubricas  ru ON ru.id = l.rubrica_id
                         WHERE l.tenant_id = t.id
                           AND regexp_replace(COALESCE(l.colaborador_cpf,''), '[^0-9]', '', 'g')
                               = regexp_replace(COALESCE(e.cpf,''), '[^0-9]', '', 'g')
                           AND ru.incide_13 AND ru.ativa AND NOT ru.protegida
                           AND pe.competencia BETWEEN to_char(e.ini,'YYYY-MM') AND to_char(e.fim,'YYYY-MM')
                       ) AS meses_com_variavel,
                       ((extract(year FROM age(date_trunc('month', e.fim), date_trunc('month', e.ini))) * 12
                         + extract(month FROM age(date_trunc('month', e.fim), date_trunc('month', e.ini))))::INT + 1
                       ) AS meses_esperados
                  FROM esperado e
            )
            SELECT * FROM contagem
             WHERE meses_com_variavel > 0
               AND meses_com_variavel < meses_esperados
        LOOP
            INSERT INTO public.folha_alertas_prazo (
                tenant_id, empresa_id, ano, tipo, faixa, severidade, competencia,
                data_limite, status, descricao,
                colaborador_id, colaborador_nome, valor_referencia)
            VALUES (
                t.id, r.empresa_id, v_ano, 'decimo_terceiro_base_incompleta', 'unica',
                'media', to_char(make_date(v_ano, 12, 1), 'YYYY-MM'),
                public.decimo_terceiro_prazo_legal(v_ano, 2), 'pendente',
                format('Base de médias incompleta: %s de %s competência(s) do ano têm variável lançada. Sem as demais, o 13º sai menor (Decreto 57.155/1965).',
                       r.meses_com_variavel, r.meses_esperados),
                r.id::text, r.nome_completo,
                r.meses_esperados - r.meses_com_variavel)
            ON CONFLICT DO NOTHING;
            IF FOUND THEN v_novos := v_novos + 1; END IF;
        END LOOP;

        -- ── c) Afastamento previdenciário a validar ──────────────────
        FOR r IN
            SELECT DISTINCT a.id, a.nome_completo, a.empresa_id
              FROM public.admissoes a
              JOIN public.afastamentos af
                ON regexp_replace(COALESCE(af.colaborador_cpf,''), '[^0-9]', '', 'g')
                 = regexp_replace(COALESCE(a.cpf,''), '[^0-9]', '', 'g')
              JOIN public.afastamentos_previdenciario ap ON ap.afastamento_id = af.id
             WHERE a.tenant_id = t.id AND a.status = 'concluido'
               AND af.tenant_id = t.id
               AND ap.especie_beneficio IN ('B31','B91','B92','B32')
               AND af.data_inicio <= make_date(v_ano, 12, 31)
               AND COALESCE(af.data_fim, make_date(v_ano, 12, 31)) >= make_date(v_ano, 1, 1)
        LOOP
            INSERT INTO public.folha_alertas_prazo (
                tenant_id, empresa_id, ano, tipo, faixa, severidade, competencia,
                data_limite, status, descricao, colaborador_id, colaborador_nome)
            VALUES (
                t.id, r.empresa_id, v_ano, 'decimo_terceiro_afastamento', 'unica',
                'media', to_char(make_date(v_ano, 12, 1), 'YYYY-MM'),
                public.decimo_terceiro_prazo_legal(v_ano, 2), 'pendente',
                'Afastamento previdenciário no ano-base: confira com a contabilidade os avos que cabem à empresa e o abono anual pago pelo INSS.',
                r.id::text, r.nome_completo)
            ON CONFLICT DO NOTHING;
            IF FOUND THEN v_novos := v_novos + 1; END IF;
        END LOOP;
    END LOOP;

    RETURN jsonb_build_object(
        'ano', v_ano, 'alertas_novos', v_novos, 'acoes_criadas', v_acoes,
        'varrido_em', now());
END $fn$;

COMMENT ON FUNCTION public.decimo_terceiro_alertas_varrer(UUID, INT) IS
    'Varredura dos alertas do 13o: prazo das duas parcelas (Lei 4.749/1965), base de medias incompleta e afastamento a validar. Idempotente: um alerta por marco.';

REVOKE EXECUTE ON FUNCTION public.decimo_terceiro_alertas_varrer(UUID, INT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.decimo_terceiro_alertas_varrer(UUID, INT) TO authenticated;

-- ── 3. Do alerta para o Plano de Ação (5W2H) ──────────────────────────
-- Espelha ferias_alerta_gerar_acao e ponto_alerta_gerar_acao.
-- Idempotente: um alerta gera uma ação, não uma por varredura.
CREATE OR REPLACE FUNCTION public.decimo_terceiro_alerta_gerar_acao(
    p_alerta_id        UUID,
    p_responsavel_id   UUID DEFAULT NULL,
    p_responsavel_nome TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
    a       RECORD;
    v_grav  INT; v_urg INT; v_tend INT := 4;
    v_prio  public.acao_gut_prioridade;
    v_prazo INT;
    v_onde  TEXT;
    v_porque TEXT;
    v_como  TEXT;
    v_id    UUID;
BEGIN
    SELECT * INTO a FROM public.folha_alertas_prazo WHERE id = p_alerta_id;
    IF NOT FOUND THEN RETURN NULL; END IF;
    IF a.plano_acao_id IS NOT NULL THEN RETURN a.plano_acao_id; END IF;

    v_grav := CASE a.severidade WHEN 'critica' THEN 5 WHEN 'alta' THEN 4 ELSE 3 END;
    v_urg  := v_grav;
    v_prio := (CASE a.severidade WHEN 'critica' THEN 'imediato'
                                 WHEN 'alta'    THEN 'urgente'
                                 ELSE 'medio' END)::public.acao_gut_prioridade;

    -- Prazo (When): até a data-limite, nunca no passado.
    v_prazo := greatest(COALESCE(a.data_limite - CURRENT_DATE, 0), 0);

    v_onde := COALESCE(
        (SELECT razao_social FROM public.empresa_cadastro WHERE id = a.empresa_id),
        '13º Salário — controle de prazos');

    -- Why e How dependem do que se está cobrando.
    v_porque := CASE a.tipo
        WHEN 'decimo_terceiro_1a_parcela' THEN
            'A 1ª parcela do 13º deve ser paga entre 1º de fevereiro e 30 de novembro (Lei 4.749/1965, art. 2º). Fora do prazo, multa e passivo.'
        WHEN 'decimo_terceiro_2a_parcela' THEN
            'A 2ª parcela do 13º deve ser paga até 20 de dezembro (Lei 4.749/1965, art. 1º), antecipando quando cai em fim de semana ou feriado.'
        WHEN 'decimo_terceiro_base_incompleta' THEN
            'A média das variáveis compõe a base do 13º (Decreto 57.155/1965). Competência sem lançamento faz o 13º sair menor — diferença que vira reclamação.'
        ELSE
            'Afastamento previdenciário muda os avos que cabem à empresa e aciona o abono anual do INSS: confirmar evita pagar a mais ou a menos.'
    END;

    v_como := CASE a.tipo
        WHEN 'decimo_terceiro_1a_parcela' THEN
            'Rodar o lote da 1ª parcela, conferir a apuração, aprovar e liberar o pagamento até a data-limite; guardar o comprovante.'
        WHEN 'decimo_terceiro_2a_parcela' THEN
            'Fechar a apuração, conferir INSS e IRRF, aprovar, pagar até a data-limite e transmitir o eSocial.'
        WHEN 'decimo_terceiro_base_incompleta' THEN
            'Importar ou lançar as competências que faltam e reapurar o 13º antes do fechamento.'
        ELSE
            'Levar o caso à contabilidade, registrar a decisão sobre os avos e reapurar se necessário.'
    END;

    INSERT INTO public.plano_acoes (
        tenant_id, empresa_id, titulo, descricao,
        porque, onde, como, prazo,
        responsavel_id, responsavel_nome,
        origem_modulo, origem_id, origem_descricao,
        gravidade, urgencia, tendencia, prioridade,
        custo_estimado, tipo, status
    ) VALUES (
        a.tenant_id, a.empresa_id,
        CASE a.tipo
            WHEN 'decimo_terceiro_1a_parcela'      THEN format('13º %s: pagar a 1ª parcela até %s', a.ano, to_char(a.data_limite, 'DD/MM'))
            WHEN 'decimo_terceiro_2a_parcela'      THEN format('13º %s: pagar a 2ª parcela até %s', a.ano, to_char(a.data_limite, 'DD/MM'))
            WHEN 'decimo_terceiro_base_incompleta' THEN format('13º %s: completar a base de médias de %s', a.ano, COALESCE(a.colaborador_nome, 'colaborador'))
            ELSE format('13º %s: validar afastamento de %s', a.ano, COALESCE(a.colaborador_nome, 'colaborador'))
        END,
        COALESCE(a.descricao, 'Alerta do 13º salário'),
        v_porque, v_onde, v_como,
        (CURRENT_DATE + v_prazo),
        p_responsavel_id, p_responsavel_nome,
        'financeiro', a.id,
        format('Alerta do 13º (%s, %s) — ano-base %s%s', a.tipo, a.severidade, a.ano,
               COALESCE(' — ' || a.colaborador_nome, '')),
        v_grav, v_urg, v_tend, v_prio,
        a.valor_referencia,
        CASE WHEN a.status = 'atrasado' THEN 'corretiva' ELSE 'preventiva' END,
        'pendente')
    RETURNING id INTO v_id;

    UPDATE public.folha_alertas_prazo
       SET plano_acao_id = v_id, updated_at = now()
     WHERE id = p_alerta_id;

    RETURN v_id;
END $fn$;

COMMENT ON FUNCTION public.decimo_terceiro_alerta_gerar_acao(UUID, UUID, TEXT) IS
    'Converte um alerta do 13o em acao no Plano de Acao com 5W2H. Idempotente: um alerta, uma acao.';

REVOKE EXECUTE ON FUNCTION public.decimo_terceiro_alerta_gerar_acao(UUID, UUID, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.decimo_terceiro_alerta_gerar_acao(UUID, UUID, TEXT) TO authenticated;

-- ── 4. Agendamento diário ─────────────────────────────────────────────
-- Como as demais varreduras da casa. Onde não há pg_cron (réplica local),
-- o bloco avisa e segue.
DO $cron$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        -- A remocao vem PROTEGIDA: pedir para remover um agendamento que
        -- ainda nao existe e erro no pg_cron, e o erro derrubaria o bloco
        -- inteiro antes de criar o agendamento novo — que e justamente o
        -- caso da primeira execucao. Padrao ja usado nas demais varreduras
        -- da casa.
        PERFORM cron.unschedule('decimo_terceiro_alertas_diario')
          WHERE EXISTS (SELECT 1 FROM cron.job
                         WHERE jobname = 'decimo_terceiro_alertas_diario');

        PERFORM cron.schedule('decimo_terceiro_alertas_diario', '25 6 * * *',
                              $c$SELECT public.decimo_terceiro_alertas_varrer();$c$);
        RAISE NOTICE 'Varredura de alertas do 13o agendada para as 06:25 diarias.';
    ELSE
        RAISE NOTICE 'pg_cron nao instalado: a varredura do 13o existe, mas nao foi agendada.';
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Agendamento da varredura do 13o nao aplicado: %', SQLERRM;
END $cron$;


-- ════════════════════════════════════════════════════════════════════
-- 5) Contabilidade e rescisao: provisao, conciliacao, ferias
-- ════════════════════════════════════════════════════════════════════
-- ── 1. Provisão mensal ────────────────────────────────────────────────
-- Um registro por colaborador/competência. O 13º provisionado do mês é
-- 1/12 da remuneração (salário + médias); os encargos acompanham.
CREATE UNIQUE INDEX IF NOT EXISTS folha_provisoes_unica
    ON public.folha_provisoes (tenant_id, competencia, tipo, colaborador_id);

CREATE OR REPLACE FUNCTION public.decimo_terceiro_provisionar(
    p_competencia TEXT,
    p_tenant      UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
    v_ano      INT;
    v_mes      INT;
    v_ref      DATE;
    t          RECORD;
    a          RECORD;
    v_ap       JSONB;
    v_base     NUMERIC(12,2);
    v_prov     NUMERIC(12,2);
    v_inss     NUMERIC(12,2);
    v_fgts     NUMERIC(12,2);
    v_criadas  INT := 0;
    v_revert   INT := 0;
    v_total    NUMERIC(14,2) := 0;
BEGIN
    IF p_competencia !~ '^\d{4}-\d{2}$' THEN
        RETURN jsonb_build_object('erro', 'Competência deve estar no formato AAAA-MM.');
    END IF;

    v_ano := split_part(p_competencia, '-', 1)::INT;
    v_mes := split_part(p_competencia, '-', 2)::INT;
    v_ref := (make_date(v_ano, v_mes, 1) + INTERVAL '1 month - 1 day')::DATE;

    FOR t IN
        SELECT id FROM public.tenants
         WHERE (p_tenant IS NULL OR id = p_tenant) AND COALESCE(ativo, true)
    LOOP
        -- Reverte a provisão de quem não está mais ativo na competência,
        -- ou de quem já teve o 13º do ano pago: o custo virou despesa.
        UPDATE public.folha_provisoes pr
           SET revertida = true, data_reversao = v_ref
         WHERE pr.tenant_id = t.id
           AND pr.tipo = '13_salario'
           AND NOT COALESCE(pr.revertida, false)
           AND left(pr.competencia, 4) = v_ano::text
           -- Casa pelo CPF, não pelo colaborador_id: este último é um
           -- TEXT livre e cada módulo grava o seu (a rescisão pode ter
           -- um id diferente do da provisão). O CPF é a chave confiável
           -- e é como o resto do módulo já casa os registros.
           AND EXISTS (
               SELECT 1
                 FROM public.folha_rescisoes r
                 JOIN public.admissoes ad
                   ON ad.tenant_id = t.id
                  AND ad.id::text = pr.colaborador_id
                WHERE r.tenant_id = t.id
                  AND regexp_replace(COALESCE(r.colaborador_cpf,''), '[^0-9]', '', 'g')
                      = regexp_replace(COALESCE(ad.cpf,''), '[^0-9]', '', 'g')
                  AND r.data_desligamento <= v_ref);
        GET DIAGNOSTICS v_revert = ROW_COUNT;

        FOR a IN
            SELECT ad.id, ad.nome_completo, ad.cpf, ad.data_admissao
              FROM public.admissoes ad
             WHERE ad.tenant_id = t.id
               AND ad.status = 'concluido'
               AND ad.data_admissao IS NOT NULL
               AND ad.data_admissao <= v_ref
               -- Desligado antes do fim do mês não provisiona.
               AND NOT EXISTS (
                   SELECT 1 FROM public.folha_rescisoes r
                    WHERE r.tenant_id = t.id
                      AND regexp_replace(COALESCE(r.colaborador_cpf,''), '[^0-9]', '', 'g')
                          = regexp_replace(COALESCE(ad.cpf,''), '[^0-9]', '', 'g')
                      AND r.data_desligamento <= v_ref)
        LOOP
            BEGIN
                v_ap   := public.decimo_terceiro_apurar(t.id, a.cpf, v_ano, NULL, NULL);
                v_base := COALESCE((v_ap->>'base_integral')::NUMERIC, 0);
                CONTINUE WHEN v_base <= 0;

                -- 1/12 por mês: o custo nasce ao longo do ano.
                v_prov := round(v_base / 12, 2);
                -- Encargos que acompanham a provisão (RN-005/006).
                v_inss := round(v_prov * 0.20, 2);   -- INSS patronal
                v_fgts := round(v_prov * 0.08, 2);

                INSERT INTO public.folha_provisoes (
                    tenant_id, competencia, colaborador_id, colaborador_nome,
                    tipo, valor_provisao, valor_terco,
                    encargos_inss, encargos_fgts, valor_total, revertida)
                VALUES (
                    t.id, p_competencia, a.id::text, a.nome_completo,
                    '13_salario', v_prov, 0, v_inss, v_fgts,
                    v_prov + v_inss + v_fgts, false)
                ON CONFLICT (tenant_id, competencia, tipo, colaborador_id)
                DO UPDATE SET
                    valor_provisao = EXCLUDED.valor_provisao,
                    encargos_inss  = EXCLUDED.encargos_inss,
                    encargos_fgts  = EXCLUDED.encargos_fgts,
                    valor_total    = EXCLUDED.valor_total,
                    colaborador_nome = EXCLUDED.colaborador_nome;

                v_criadas := v_criadas + 1;
                v_total   := v_total + v_prov + v_inss + v_fgts;
            EXCEPTION WHEN OTHERS THEN
                RAISE WARNING 'Provisão do 13º falhou para % (%): %',
                    a.nome_completo, a.cpf, SQLERRM;
            END;
        END LOOP;
    END LOOP;

    RETURN jsonb_build_object(
        'competencia', p_competencia,
        'provisionados', v_criadas,
        'revertidos', v_revert,
        'total_provisionado', round(v_total, 2),
        'fundamento', 'Regime de competencia: 1/12 do 13o por mes, com INSS patronal e FGTS',
        'processado_em', now());
END $fn$;

COMMENT ON FUNCTION public.decimo_terceiro_provisionar(TEXT, UUID) IS
    'Provisiona 1/12 do 13o de cada vinculo ativo na competencia, com encargos, e reverte a de quem foi desligado. Idempotente por competencia.';

REVOKE EXECUTE ON FUNCTION public.decimo_terceiro_provisionar(TEXT, UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.decimo_terceiro_provisionar(TEXT, UUID) TO authenticated;


-- ── 2. Conciliação: provisionado x pago ───────────────────────────────
-- O que o contador pede no fechamento (seção 20 do documento).
CREATE OR REPLACE FUNCTION public.decimo_terceiro_conciliar_provisao(
    p_tenant UUID,
    p_ano    INT
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    v_prov  NUMERIC(14,2);
    v_pago  NUMERIC(14,2);
    v_meses JSONB;
BEGIN
    SELECT COALESCE(sum(valor_total), 0) INTO v_prov
      FROM public.folha_provisoes
     WHERE tenant_id = p_tenant AND tipo = '13_salario'
       AND left(competencia, 4) = p_ano::text
       AND NOT COALESCE(revertida, false);

    SELECT COALESCE(sum(total_liquido + valor_inss + valor_irrf + valor_fgts), 0) INTO v_pago
      FROM public.folha_13_calculo
     WHERE tenant_id = p_tenant AND ano = p_ano AND status = 'pago';

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'competencia', competencia,
               'provisionado', total,
               'colaboradores', qtd) ORDER BY competencia), '[]'::jsonb)
      INTO v_meses
      FROM (SELECT competencia, sum(valor_total)::NUMERIC(14,2) AS total, count(*) AS qtd
              FROM public.folha_provisoes
             WHERE tenant_id = p_tenant AND tipo = '13_salario'
               AND left(competencia, 4) = p_ano::text
               AND NOT COALESCE(revertida, false)
             GROUP BY competencia) m;

    RETURN jsonb_build_object(
        'ano', p_ano,
        'provisionado', v_prov,
        'pago', v_pago,
        'diferenca', round(v_prov - v_pago, 2),
        'situacao', CASE
            WHEN abs(v_prov - v_pago) < 0.01 THEN 'conciliado'
            WHEN v_prov > v_pago THEN 'provisionado a maior — sobra a reverter'
            ELSE 'provisionado a menor — falta reforçar a provisão' END,
        'por_competencia', v_meses,
        'apurado_em', now());
END $fn$;

COMMENT ON FUNCTION public.decimo_terceiro_conciliar_provisao(UUID, INT) IS
    'Conciliacao do 13o: provisionado x pago no ano, com a diferenca e o detalhe por competencia.';

GRANT EXECUTE ON FUNCTION public.decimo_terceiro_conciliar_provisao(UUID, INT) TO authenticated;

-- ── 3. Rescisão: a regra do motivo passa a viver no banco ─────────────
-- Justa causa faz perder o 13º proporcional (Lei 4.090/1962 e
-- jurisprudência consolidada). A culpa recíproca, que dá metade
-- (Súmula 14 do TST), é tratada no módulo de Desligamento (DESL-035) e
-- não é motivo próprio no enum daqui.
CREATE OR REPLACE FUNCTION public.decimo_terceiro_rescisao_valida()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $tg$
BEGIN
    IF NEW.tipo_rescisao = 'DISPENSA_COM_JUSTA_CAUSA'
       AND COALESCE(NEW.decimo_terceiro_proporcional, 0) > 0 THEN
        RAISE EXCEPTION 'Dispensa por justa causa não gera 13º proporcional (Lei 4.090/1962). Valor informado: R$ %. Se o caso for culpa recíproca, use o tratamento próprio, que paga metade (Súmula 14 do TST).',
            NEW.decimo_terceiro_proporcional
            USING ERRCODE = 'raise_exception';
    END IF;
    RETURN NEW;
END $tg$;

DROP TRIGGER IF EXISTS trg_decimo_terceiro_rescisao_valida ON public.folha_rescisoes;
CREATE TRIGGER trg_decimo_terceiro_rescisao_valida
BEFORE INSERT OR UPDATE ON public.folha_rescisoes
FOR EACH ROW EXECUTE FUNCTION public.decimo_terceiro_rescisao_valida();

-- ── 4. O 13º que cabe na rescisão, conciliado com o já pago ───────────
CREATE OR REPLACE FUNCTION public.decimo_terceiro_da_rescisao(
    p_rescisao UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    r        public.folha_rescisoes;
    v_ano    INT;
    v_ap     JSONB;
    v_avos   INT;
    v_base   NUMERIC(12,2);
    v_devido NUMERIC(12,2);
    v_pago   NUMERIC(12,2) := 0;
    v_perde  BOOLEAN := false;
BEGIN
    SELECT * INTO r FROM public.folha_rescisoes WHERE id = p_rescisao;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('erro', 'Rescisão não encontrada.');
    END IF;

    v_ano   := extract(year FROM r.data_desligamento)::INT;
    v_perde := (r.tipo_rescisao = 'DISPENSA_COM_JUSTA_CAUSA');

    v_ap   := public.decimo_terceiro_apurar(r.tenant_id, r.colaborador_cpf, v_ano, NULL, NULL);
    v_avos := COALESCE((v_ap->>'avos')::INT, 0);
    v_base := COALESCE((v_ap->>'base_integral')::NUMERIC, 0);

    v_devido := CASE WHEN v_perde THEN 0 ELSE round(v_base * v_avos / 12.0, 2) END;

    -- Adiantamento já pago no ano (inclusive o das férias): abate.
    SELECT COALESCE(sum(c.total_liquido), 0) INTO v_pago
      FROM public.folha_13_calculo c
     WHERE c.tenant_id = r.tenant_id
       AND c.ano = v_ano
       AND c.status = 'pago'
       AND regexp_replace(COALESCE(c.colaborador_cpf,''), '[^0-9]', '', 'g')
           = regexp_replace(COALESCE(r.colaborador_cpf,''), '[^0-9]', '', 'g');

    RETURN jsonb_build_object(
        'rescisao_id',   r.id,
        'ano',           v_ano,
        'tipo_rescisao', r.tipo_rescisao,
        'perde_por_justa_causa', v_perde,
        'avos',          v_avos,
        'base',          v_base,
        'devido',        v_devido,
        'ja_pago_no_ano', v_pago,
        'a_pagar_na_rescisao', greatest(round(v_devido - v_pago, 2), 0),
        'a_descontar',   CASE WHEN v_pago > v_devido
                              THEN round(v_pago - v_devido, 2) ELSE 0 END,
        'fundamento', CASE WHEN v_perde
            THEN 'Justa causa: perde o 13o proporcional (Lei 4.090/1962).'
            ELSE 'Rescisao no ano-base: 13o proporcional aos avos, deduzido o adiantamento ja pago.' END,
        'memoria', v_ap,
        'apurado_em', now());
END $fn$;

COMMENT ON FUNCTION public.decimo_terceiro_da_rescisao(UUID) IS
    'Apura o 13o proporcional que cabe numa rescisao pelo motivo, deduz o adiantamento ja pago no ano e devolve a memoria.';

GRANT EXECUTE ON FUNCTION public.decimo_terceiro_da_rescisao(UUID) TO authenticated;

-- ── 5. O lote anual não paga quem já foi desligado ────────────────────
-- As verbas do desligado saem na rescisão. Sem isto, ele reaparecia na
-- folha de dezembro e receberia duas vezes.
CREATE OR REPLACE FUNCTION public.decimo_terceiro_lote(
    p_tenant  UUID,
    p_ano     INT,
    p_parcela INT,
    p_empresa UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    v_lote      UUID := gen_random_uuid();
    v_prazo     DATE;
    a           RECORD;
    v_c         JSONB;
    v_criados   INT := 0;
    v_pulados   INT := 0;
    v_semavo    INT := 0;
    v_desligado INT := 0;
    v_erros     JSONB := '[]'::jsonb;
    v_total     NUMERIC(14,2) := 0;
BEGIN
    IF p_tenant IS NULL OR p_ano IS NULL OR p_parcela NOT IN (1, 2) THEN
        RETURN jsonb_build_object('erro', 'Informe empresa, ano-base e parcela (1 ou 2).');
    END IF;

    v_prazo := public.decimo_terceiro_prazo_legal(p_ano, p_parcela);

    FOR a IN
        SELECT ad.id, ad.nome_completo, ad.cpf, ad.tipo_contrato, ad.empresa_id
          FROM public.admissoes ad
         WHERE ad.tenant_id = p_tenant
           AND ad.status = 'concluido'
           AND ad.data_admissao IS NOT NULL
           AND (p_empresa IS NULL OR ad.empresa_id = p_empresa)
         ORDER BY ad.nome_completo
    LOOP
        BEGIN
            -- Desligado até a data-limite da parcela: as verbas dele
            -- saem na rescisão, não aqui.
            IF EXISTS (
                SELECT 1 FROM public.folha_rescisoes r
                 WHERE r.tenant_id = p_tenant
                   AND regexp_replace(COALESCE(r.colaborador_cpf,''), '[^0-9]', '', 'g')
                       = regexp_replace(COALESCE(a.cpf,''), '[^0-9]', '', 'g')
                   AND r.data_desligamento <= v_prazo)
            THEN
                v_desligado := v_desligado + 1;
                CONTINUE;
            END IF;

            IF EXISTS (
                SELECT 1 FROM public.folha_13_calculo c
                 WHERE c.tenant_id = p_tenant AND c.ano = p_ano AND c.parcela = p_parcela
                   AND regexp_replace(COALESCE(c.colaborador_cpf,''), '[^0-9]', '', 'g')
                       = regexp_replace(COALESCE(a.cpf,''), '[^0-9]', '', 'g')
                   AND c.status <> 'cancelado')
            THEN
                v_pulados := v_pulados + 1;
                CONTINUE;
            END IF;

            v_c := public.decimo_terceiro_calcular(
                       p_tenant, a.cpf, p_ano, p_parcela, p_empresa, 0, NULL, a.tipo_contrato);

            IF COALESCE((v_c->>'avos')::INT, 0) = 0 THEN
                v_semavo := v_semavo + 1;
                CONTINUE;
            END IF;

            INSERT INTO public.folha_13_calculo (
                tenant_id, empresa_id, admissao_id, ano, parcela,
                colaborador_id, colaborador_nome, colaborador_cpf, tipo_vinculo,
                meses_trabalhados, remuneracao_base, media_variaveis,
                valor_bruto, valor_primeira_parcela,
                base_inss, valor_inss, base_irrf, valor_irrf,
                base_fgts, valor_fgts, total_descontos, total_liquido,
                status, competencia, data_prevista, lote_id,
                avos_origem, media_origem, memoria_calculo)
            VALUES (
                p_tenant, a.empresa_id, a.id, p_ano, p_parcela,
                a.id::text, a.nome_completo, a.cpf, a.tipo_contrato,
                (v_c->>'avos')::INT,
                (v_c->>'remuneracao_base')::NUMERIC, (v_c->>'media_variaveis')::NUMERIC,
                (v_c->>'valor_bruto')::NUMERIC, (v_c->>'valor_primeira_parcela')::NUMERIC,
                (v_c->>'base_inss')::NUMERIC, (v_c->>'valor_inss')::NUMERIC,
                (v_c->>'base_irrf')::NUMERIC, (v_c->>'valor_irrf')::NUMERIC,
                (v_c->>'base_fgts')::NUMERIC, (v_c->>'valor_fgts')::NUMERIC,
                (v_c->>'total_descontos')::NUMERIC, (v_c->>'total_liquido')::NUMERIC,
                'calculado', v_c->>'competencia', v_prazo, v_lote,
                'apurado', 'apurado', v_c->'memoria');

            v_criados := v_criados + 1;
            v_total   := v_total + COALESCE((v_c->>'total_liquido')::NUMERIC, 0);

        EXCEPTION WHEN OTHERS THEN
            v_erros := v_erros || jsonb_build_object(
                'colaborador', a.nome_completo, 'erro', SQLERRM);
        END;
    END LOOP;

    RETURN jsonb_build_object(
        'lote_id', v_lote, 'ano', p_ano, 'parcela', p_parcela,
        'prazo_legal', v_prazo,
        'criados', v_criados, 'ja_existiam', v_pulados, 'sem_avo', v_semavo,
        'desligados_na_rescisao', v_desligado,
        'total_liquido', round(v_total, 2),
        'erros', v_erros, 'processado_em', now());
END $fn$;

GRANT EXECUTE ON FUNCTION public.decimo_terceiro_lote(UUID, INT, INT, UUID) TO authenticated;

-- ── 6. O adiantamento nas férias deixa de ser um botão órfão ──────────
-- A programação de férias tem o campo adiantar_13 desde sempre, e NADA o
-- consumia: quem pedia o adiantamento junto às férias marcava a caixa e
-- não acontecia nada. É o art. 2º, § 2º da Lei 4.749/1965 — o empregado
-- que requerer no mês de JANEIRO recebe o adiantamento por ocasião das
-- férias.
--
-- A função gera a 1ª parcela desses colaboradores com a data-limite
-- amarrada ao início do gozo (o adiantamento é pago ao sair de férias,
-- não em novembro). O pedido fora de janeiro NÃO é bloqueado — conceder
-- assim mesmo é liberalidade permitida —, mas fica registrado na
-- memória, para a auditoria saber que foi por decisão da empresa.
CREATE OR REPLACE FUNCTION public.decimo_terceiro_adiantamento_nas_ferias(
    p_tenant UUID,
    p_ano    INT
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    g          RECORD;
    v_c        JSONB;
    v_criados  INT := 0;
    v_pulados  INT := 0;
    v_fora_jan INT := 0;
    v_avisos   JSONB := '[]'::jsonb;
    v_prazo    DATE;
    v_no_prazo BOOLEAN;
BEGIN
    IF p_tenant IS NULL OR p_ano IS NULL THEN
        RETURN jsonb_build_object('erro', 'Informe empresa e ano-base.');
    END IF;

    FOR g IN
        SELECT pr.colaborador_cpf, pr.colaborador_nome, pr.colaborador_id,
               pr.empresa_id, pr.p1_inicio, pr.created_at, pr.confirmado_em,
               ad.id AS admissao_id, ad.tipo_contrato
          FROM public.ferias_programacao pr
          LEFT JOIN public.admissoes ad
            ON ad.tenant_id = pr.tenant_id
           AND regexp_replace(COALESCE(ad.cpf,''), '[^0-9]', '', 'g')
               = regexp_replace(COALESCE(pr.colaborador_cpf,''), '[^0-9]', '', 'g')
           AND ad.status = 'concluido'
         WHERE pr.tenant_id = p_tenant
           AND COALESCE(pr.adiantar_13, false)
           AND pr.p1_inicio IS NOT NULL
           AND extract(year FROM pr.p1_inicio)::INT = p_ano
    LOOP
        BEGIN
            -- Já tem 1ª parcela viva? Não se mexe.
            IF EXISTS (
                SELECT 1 FROM public.folha_13_calculo c
                 WHERE c.tenant_id = p_tenant AND c.ano = p_ano AND c.parcela = 1
                   AND regexp_replace(COALESCE(c.colaborador_cpf,''), '[^0-9]', '', 'g')
                       = regexp_replace(COALESCE(g.colaborador_cpf,''), '[^0-9]', '', 'g')
                   AND c.status <> 'cancelado')
            THEN
                v_pulados := v_pulados + 1;
                CONTINUE;
            END IF;

            -- Lei 4.749/1965, art. 2º, § 2º: pedido no mês de janeiro.
            v_no_prazo := extract(month FROM COALESCE(g.confirmado_em, g.created_at))::INT = 1
                          AND extract(year  FROM COALESCE(g.confirmado_em, g.created_at))::INT = p_ano;
            IF NOT v_no_prazo THEN
                v_fora_jan := v_fora_jan + 1;
                v_avisos := v_avisos || jsonb_build_object(
                    'colaborador', g.colaborador_nome,
                    'aviso', 'Pedido fora do mês de janeiro (art. 2º, § 2º da Lei 4.749/1965). O adiantamento foi gerado assim mesmo, por liberalidade da empresa — fica registrado na memória.');
            END IF;

            v_c := public.decimo_terceiro_calcular(
                       p_tenant, g.colaborador_cpf, p_ano, 1, g.empresa_id, 0, NULL, g.tipo_contrato);

            CONTINUE WHEN COALESCE((v_c->>'avos')::INT, 0) = 0;

            -- O adiantamento sai ao entrar em férias, não em novembro:
            -- a data-limite passa a ser a véspera do gozo.
            v_prazo := g.p1_inicio - 1;

            INSERT INTO public.folha_13_calculo (
                tenant_id, empresa_id, admissao_id, ano, parcela,
                colaborador_id, colaborador_nome, colaborador_cpf, tipo_vinculo,
                meses_trabalhados, remuneracao_base, media_variaveis,
                valor_bruto, valor_primeira_parcela,
                base_inss, valor_inss, base_irrf, valor_irrf,
                base_fgts, valor_fgts, total_descontos, total_liquido,
                status, competencia, data_prevista,
                avos_origem, media_origem, observacao, memoria_calculo)
            VALUES (
                p_tenant, g.empresa_id, g.admissao_id, p_ano, 1,
                COALESCE(g.admissao_id::text, g.colaborador_id::text),
                g.colaborador_nome, g.colaborador_cpf, g.tipo_contrato,
                (v_c->>'avos')::INT,
                (v_c->>'remuneracao_base')::NUMERIC, (v_c->>'media_variaveis')::NUMERIC,
                (v_c->>'valor_bruto')::NUMERIC, (v_c->>'valor_primeira_parcela')::NUMERIC,
                0, 0, 0, 0,
                (v_c->>'base_fgts')::NUMERIC, (v_c->>'valor_fgts')::NUMERIC,
                (v_c->>'total_descontos')::NUMERIC, (v_c->>'total_liquido')::NUMERIC,
                'calculado', to_char(g.p1_inicio, 'YYYY-MM'), v_prazo,
                'apurado', 'apurado',
                format('Adiantamento do 13º pago no gozo das férias iniciado em %s (Lei 4.749/1965, art. 2º, § 2º)%s',
                       to_char(g.p1_inicio, 'DD/MM/YYYY'),
                       CASE WHEN v_no_prazo THEN '' ELSE ' — pedido fora de janeiro' END),
                (v_c->'memoria') || jsonb_build_object(
                    'origem_adiantamento', 'ferias',
                    'ferias_inicio', g.p1_inicio,
                    'pedido_em_janeiro', v_no_prazo));

            v_criados := v_criados + 1;
        EXCEPTION WHEN OTHERS THEN
            v_avisos := v_avisos || jsonb_build_object(
                'colaborador', g.colaborador_nome, 'erro', SQLERRM);
        END;
    END LOOP;

    RETURN jsonb_build_object(
        'ano', p_ano,
        'adiantamentos_gerados', v_criados,
        'ja_existiam', v_pulados,
        'pedidos_fora_de_janeiro', v_fora_jan,
        'avisos', v_avisos,
        'fundamento', 'Lei 4.749/1965, art. 2o, § 2o: adiantamento pago por ocasiao das ferias',
        'processado_em', now());
END $fn$;

COMMENT ON FUNCTION public.decimo_terceiro_adiantamento_nas_ferias(UUID, INT) IS
    'Gera a 1a parcela do 13o de quem pediu o adiantamento junto as ferias (art. 2o, § 2o da Lei 4.749/1965), com a data-limite na vespera do gozo. Idempotente.';

GRANT EXECUTE ON FUNCTION public.decimo_terceiro_adiantamento_nas_ferias(UUID, INT) TO authenticated;


-- ════════════════════════════════════════════════════════════════════
-- 6) eSocial: S-1200 anual e S-1210 (monta, NAO transmite)
-- ════════════════════════════════════════════════════════════════════
-- ── 1. Contexto da folha nas transmissões ─────────────────────────────
ALTER TABLE public.esocial_transmissoes
    ADD COLUMN IF NOT EXISTS origem_modulo   TEXT,
    ADD COLUMN IF NOT EXISTS origem_id       UUID,
    ADD COLUMN IF NOT EXISTS ano             INT,
    ADD COLUMN IF NOT EXISTS parcela         INT,
    ADD COLUMN IF NOT EXISTS periodo_apuracao TEXT,
    ADD COLUMN IF NOT EXISTS ind_apuracao    INT,
    ADD COLUMN IF NOT EXISTS leiaute_versao  TEXT,
    ADD COLUMN IF NOT EXISTS colaborador_cpf TEXT;

COMMENT ON COLUMN public.esocial_transmissoes.ind_apuracao IS
    'Indicativo de apuracao do eSocial: 1 = mensal, 2 = anual (13o salario).';
COMMENT ON COLUMN public.esocial_transmissoes.leiaute_versao IS
    'Versao do leiaute usada para montar o XML. Leiaute desatualizado e a causa mais comum de rejeicao — confira a vigente na data do envio.';

-- Anti-duplicidade: um evento vivo por origem/tipo. Erro e cancelado
-- ficam de fora, para permitir refazer depois de corrigir.
CREATE UNIQUE INDEX IF NOT EXISTS esocial_transmissoes_origem_uq
    ON public.esocial_transmissoes (tenant_id, tipo_evento, origem_id)
    WHERE origem_id IS NOT NULL
      AND COALESCE(status, '') NOT IN ('erro', 'cancelado', 'rejeitado');

-- ── 2. Validação prévia: onde se evita a rejeição ─────────────────────
CREATE OR REPLACE FUNCTION public.decimo_terceiro_esocial_validar(
    p_tenant UUID,
    p_ano    INT
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    v_problemas JSONB := '[]'::jsonb;
    v_aptos     INT := 0;
    r           RECORD;
    v_motivo    TEXT;
BEGIN
    IF p_tenant IS NULL OR p_ano IS NULL THEN
        RETURN jsonb_build_object('erro', 'Informe empresa e ano-base.');
    END IF;

    FOR r IN
        SELECT c.id, c.colaborador_nome, c.colaborador_cpf, c.parcela, c.status,
               c.valor_bruto, c.total_liquido, c.admissao_id
          FROM public.folha_13_calculo c
         WHERE c.tenant_id = p_tenant AND c.ano = p_ano
           AND c.status <> 'cancelado'
         ORDER BY c.colaborador_nome, c.parcela
    LOOP
        v_motivo := NULL;

        IF r.colaborador_cpf IS NULL
           OR length(regexp_replace(r.colaborador_cpf, '[^0-9]', '', 'g')) <> 11 THEN
            v_motivo := 'CPF ausente ou inválido — o eSocial identifica o trabalhador pelo CPF.';
        ELSIF r.admissao_id IS NULL THEN
            v_motivo := 'Cálculo sem vínculo com a admissão: o evento precisa da matrícula do trabalhador.';
        ELSIF COALESCE(r.valor_bruto, 0) <= 0 THEN
            v_motivo := 'Valor bruto zerado: evento sem remuneração é rejeitado.';
        ELSIF r.status NOT IN ('aprovado', 'pago') THEN
            v_motivo := format('Cálculo em "%s": só se declara o que foi aprovado ou pago.', r.status);
        END IF;

        IF v_motivo IS NULL THEN
            v_aptos := v_aptos + 1;
        ELSE
            v_problemas := v_problemas || jsonb_build_object(
                'calculo_id',  r.id,
                'colaborador', r.colaborador_nome,
                'parcela',     r.parcela,
                'problema',    v_motivo);
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'ano', p_ano,
        'aptos', v_aptos,
        'com_problema', jsonb_array_length(v_problemas),
        'problemas', v_problemas,
        'pode_transmitir', (v_aptos > 0 AND jsonb_array_length(v_problemas) = 0),
        'validado_em', now());
END $fn$;

COMMENT ON FUNCTION public.decimo_terceiro_esocial_validar(UUID, INT) IS
    'Validacao previa do 13o para o eSocial: CPF, vinculo, valor e situacao do calculo. E onde se evita a rejeicao, antes de transmitir.';

GRANT EXECUTE ON FUNCTION public.decimo_terceiro_esocial_validar(UUID, INT) TO authenticated;

-- ── 3. Montagem dos eventos ───────────────────────────────────────────
-- S-1200 com indApuracao = 2 (anual) leva a remuneração do 13º do ano;
-- S-1210 leva o pagamento de cada parcela. Um evento por trabalhador.
--
-- O XML sai montado e GRAVADO como 'pendente'. Não há envio aqui: a
-- transmissão depende de certificado, procuração e ambiente definidos
-- pelo cliente. O que esta função entrega é o evento pronto e conferido.
CREATE OR REPLACE FUNCTION public.decimo_terceiro_esocial_gerar(
    p_tenant  UUID,
    p_ano     INT,
    p_tipo    TEXT DEFAULT 'S-1200',
    p_leiaute TEXT DEFAULT 'S-1.3'
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    v_val     JSONB;
    r         RECORD;
    v_cnpj    TEXT;
    v_xml     TEXT;
    v_gerados INT := 0;
    v_pulados INT := 0;
    v_cpf     TEXT;
    v_periodo TEXT;
    v_ind     INT;
BEGIN
    IF p_tipo NOT IN ('S-1200', 'S-1210') THEN
        RETURN jsonb_build_object('erro', 'Tipo deve ser S-1200 (remuneração anual) ou S-1210 (pagamentos).');
    END IF;

    -- Não se monta evento sobre base torta.
    v_val := public.decimo_terceiro_esocial_validar(p_tenant, p_ano);
    IF NOT COALESCE((v_val->>'pode_transmitir')::BOOLEAN, false) THEN
        RETURN jsonb_build_object(
            'erro', 'A validação prévia apontou pendências — corrija antes de montar os eventos.',
            'validacao', v_val);
    END IF;

    SELECT regexp_replace(COALESCE(cnpj, ''), '[^0-9]', '', 'g') INTO v_cnpj
      FROM public.empresa_cadastro WHERE tenant_id = p_tenant LIMIT 1;
    v_cnpj := COALESCE(NULLIF(v_cnpj, ''), '00000000000000');

    -- S-1200 é um evento por trabalhador no ano; S-1210, um por parcela.
    FOR r IN
        SELECT c.id, c.colaborador_nome, c.colaborador_cpf, c.parcela,
               c.valor_bruto, c.valor_inss, c.valor_irrf, c.total_liquido,
               c.data_pagamento, c.empresa_id
          FROM public.folha_13_calculo c
         WHERE c.tenant_id = p_tenant AND c.ano = p_ano
           AND c.status IN ('aprovado', 'pago')
           AND (p_tipo = 'S-1200' OR c.status = 'pago')
         ORDER BY c.colaborador_nome, c.parcela
    LOOP
        -- No S-1200 basta UM evento por trabalhador (apuração anual), e
        -- ele leva o 13º INTEIRO. Cada linha de folha_13_calculo já
        -- guarda o 13º cheio em valor_bruto (a parcela paga fica em
        -- valor_primeira_parcela / total_liquido) — somar as duas
        -- parcelas declararia o DOBRO ao eSocial. Usa-se a linha da 2ª,
        -- que é a do fechamento.
        CONTINUE WHEN p_tipo = 'S-1200' AND r.parcela <> 2;

        v_cpf     := regexp_replace(r.colaborador_cpf, '[^0-9]', '', 'g');
        v_ind     := CASE WHEN p_tipo = 'S-1200' THEN 2 ELSE 1 END;
        v_periodo := CASE WHEN p_tipo = 'S-1200'
                          THEN p_ano::text
                          ELSE to_char(COALESCE(r.data_pagamento, CURRENT_DATE), 'YYYY-MM') END;

        IF EXISTS (
            SELECT 1 FROM public.esocial_transmissoes t
             WHERE t.tenant_id = p_tenant AND t.tipo_evento = p_tipo
               AND t.origem_id = r.id
               AND COALESCE(t.status, '') NOT IN ('erro', 'cancelado', 'rejeitado'))
        THEN
            v_pulados := v_pulados + 1;
            CONTINUE;
        END IF;

        IF p_tipo = 'S-1200' THEN
            v_xml := format($x$<?xml version="1.0" encoding="UTF-8"?>
<eSocial>
  <evtRemun>
    <ideEvento>
      <indRetif>1</indRetif>
      <indApuracao>2</indApuracao>
      <perApur>%s</perApur>
      <tpAmb>2</tpAmb>
    </ideEvento>
    <ideEmpregador><tpInsc>1</tpInsc><nrInsc>%s</nrInsc></ideEmpregador>
    <ideTrabalhador><cpfTrab>%s</cpfTrab></ideTrabalhador>
    <dmDev>
      <ideDmDev>13-%s</ideDmDev>
      <infoPerApur>
        <ideEstabLot>
          <tpInsc>1</tpInsc><nrInsc>%s</nrInsc>
          <remunPerApur>
            <itensRemun>
              <codRubr>13SAL</codRubr>
              <vrRubr>%s</vrRubr>
            </itensRemun>
          </remunPerApur>
        </ideEstabLot>
      </infoPerApur>
    </dmDev>
  </evtRemun>
</eSocial>$x$, p_ano, v_cnpj, v_cpf, p_ano, v_cnpj, to_char(r.valor_bruto, 'FM999999990.00'));
        ELSE
            v_xml := format($x$<?xml version="1.0" encoding="UTF-8"?>
<eSocial>
  <evtPgtos>
    <ideEvento>
      <indApuracao>1</indApuracao>
      <perApur>%s</perApur>
      <tpAmb>2</tpAmb>
    </ideEvento>
    <ideEmpregador><tpInsc>1</tpInsc><nrInsc>%s</nrInsc></ideEmpregador>
    <ideBenef><cpfBenef>%s</cpfBenef></ideBenef>
    <infoPgto>
      <dtPgto>%s</dtPgto>
      <tpPgto>1</tpPgto>
      <perRef>%s</perRef>
      <ideDmDev>13-%s-P%s</ideDmDev>
      <vrLiq>%s</vrLiq>
    </infoPgto>
  </evtPgtos>
</eSocial>$x$, v_periodo, v_cnpj, v_cpf,
        to_char(COALESCE(r.data_pagamento, CURRENT_DATE), 'YYYY-MM-DD'),
        p_ano::text, p_ano, r.parcela, to_char(r.total_liquido, 'FM999999990.00'));
        END IF;

        INSERT INTO public.esocial_transmissoes (
            tenant_id, empresa_id, tipo_evento, xml_enviado, status,
            origem_modulo, origem_id, ano, parcela, periodo_apuracao,
            ind_apuracao, leiaute_versao, colaborador_cpf, tentativas)
        VALUES (
            p_tenant, r.empresa_id, p_tipo, v_xml, 'pendente',
            'decimo_terceiro', r.id, p_ano,
            CASE WHEN p_tipo = 'S-1210' THEN r.parcela END,
            v_periodo, v_ind, p_leiaute, v_cpf, 0);

        v_gerados := v_gerados + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'ano', p_ano, 'tipo', p_tipo, 'leiaute', p_leiaute,
        'eventos_gerados', v_gerados,
        'ja_existiam', v_pulados,
        'situacao', 'pendente de transmissão',
        'aviso', 'Os eventos foram MONTADOS, não enviados. A transmissão depende de certificado digital, procuração eletrônica e ambiente definidos pelo cliente. Confira a versão do leiaute vigente antes de transmitir.',
        'gerado_em', now());
END $fn$;

COMMENT ON FUNCTION public.decimo_terceiro_esocial_gerar(UUID, INT, TEXT, TEXT) IS
    'Monta os eventos do 13o para o eSocial: S-1200 com apuracao ANUAL (indApuracao=2) e S-1210 dos pagamentos. Grava como pendente; NAO transmite.';

GRANT EXECUTE ON FUNCTION public.decimo_terceiro_esocial_gerar(UUID, INT, TEXT, TEXT) TO authenticated;

-- ── 4. QA: a sonda do eSocial passa a cobrar o que foi entregue ──
-- =========================================================
-- QA DEC13-050 — aperta a sonda do eSocial do 13º
--
-- A sonda dava "passou" cedo demais: aceitava QUALQUER função cujo texto
-- contivesse "S-1200" ou "anual", e procurava a unicidade apenas entre
-- CONSTRAINTs — sem enxergar índice único parcial. Com isso o caso ficou
-- verde antes de existir qualquer geração de evento do 13º, que é
-- exatamente o achado que ele deveria acusar.
--
-- Agora ela cobra o que a Entrega 5 entrega, pelo nome: a validação
-- prévia, a montagem dos eventos e a anti-duplicidade por origem —
-- aceitando tanto constraint quanto índice único.
-- =========================================================
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_050()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_unq       text;
  v_validar   boolean;
  v_gerar     boolean;
  v_anual     boolean;
  v_faltando  text[] := ARRAY[]::text[];
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a folha anual do 13º tem eventos, validação prévia e anti-duplicidade?';
  r.esperado := 'S-1200 (apuração anual, indApuracao=2) e S-1210 (pagamentos), validação antes do envio e unicidade por origem';

  IF to_regclass('public.esocial_transmissoes') IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A tabela de transmissões do eSocial não existe nesta base.';
    RETURN r;
  END IF;

  -- unicidade: vale constraint OU índice único (o índice parcial é o que
  -- permite refazer o evento depois de um erro ou cancelamento)
  SELECT string_agg(nome, ', ') INTO v_unq FROM (
    SELECT conname AS nome FROM pg_constraint
     WHERE conrelid = 'public.esocial_transmissoes'::regclass AND contype = 'u'
    UNION
    SELECT c.relname FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
     WHERE i.indrelid = 'public.esocial_transmissoes'::regclass
       AND i.indisunique AND NOT i.indisprimary
  ) u;

  SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'decimo_terceiro_esocial_validar')
    INTO v_validar;
  SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'decimo_terceiro_esocial_gerar')
    INTO v_gerar;
  SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'decimo_terceiro_esocial_gerar'
                    AND p.prosrc LIKE '%indApuracao>2<%')
    INTO v_anual;

  IF NOT v_validar THEN v_faltando := array_append(v_faltando, 'validação prévia do 13º (decimo_terceiro_esocial_validar)'); END IF;
  IF NOT v_gerar   THEN v_faltando := array_append(v_faltando, 'montagem dos eventos (decimo_terceiro_esocial_gerar)'); END IF;
  IF v_gerar AND NOT v_anual THEN v_faltando := array_append(v_faltando, 'apuração ANUAL no S-1200 (indApuracao = 2)'); END IF;
  IF v_unq IS NULL THEN v_faltando := array_append(v_faltando, 'anti-duplicidade em esocial_transmissoes'); END IF;

  IF array_length(v_faltando, 1) IS NOT NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO (terceiro da série ADM-093/FERIAS-081, agora pela folha ANUAL): falta '
             || array_to_string(v_faltando, '; ') || '. A competência anual tem regra própria de '
             || 'retificação e prazo; sem os eventos, o 13º pago não existe para o governo — e a '
             || 'DCTFWeb de dezembro não fecha com a folha. Correção: geração dos dois eventos no '
             || 'fechamento (apuração e pagamento), chave natural (vínculo + tipo + competência '
             || 'anual) e tradução de rejeição em instrução, nunca reenvio às cegas.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Proteções presentes: validação prévia e montagem do S-1200 anual e do S-1210, com unicidade (%s).', v_unq);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;


-- ════════════════════════════════════════════════════════════════════
-- 7) Correcoes de lei: aviso previo projetado e Sumula 46 do TST
-- ════════════════════════════════════════════════════════════════════
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
    v_cpf          TEXT;
    v_ano_ini      DATE;
    v_ano_fim      DATE;
    v_admissao     DATE;
    v_desligamento DATE;
    v_fim_contrato DATE;
    v_dias_aviso   INT := 0;
    v_aviso_tipo   TEXT;
    v_tem_ponto    BOOLEAN := false;
    v_regra        TEXT;
    v_dias_empreg  INT;
    v_vigencia     DATE;
    v_avos         INT;
    v_meses        JSONB;
    v_avisos       TEXT[] := ARRAY[]::TEXT[];
BEGIN
    v_cpf := regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
    IF v_cpf = '' OR p_ano IS NULL OR p_tenant IS NULL THEN
        RETURN jsonb_build_object('erro',
            'Apuração de avos precisa de empresa, CPF e ano-base. Recebido: CPF "'
            || coalesce(p_cpf, '(vazio)') || '".');
    END IF;

    v_ano_ini := make_date(p_ano, 1, 1);
    v_ano_fim := make_date(p_ano, 12, 31);

    SELECT c.afastamento_regra, c.afastamento_dias_empregador, c.parametros_vigencia_inicio
      INTO v_regra, v_dias_empreg, v_vigencia
      FROM public.decimo_terceiro_config c
     WHERE c.tenant_id = p_tenant AND c.empresa_id IS NOT DISTINCT FROM p_empresa
     LIMIT 1;

    IF v_regra IS NULL THEN
        SELECT c.afastamento_regra, c.afastamento_dias_empregador, c.parametros_vigencia_inicio
          INTO v_regra, v_dias_empreg, v_vigencia
          FROM public.decimo_terceiro_config c
         WHERE c.tenant_id = p_tenant AND c.empresa_id IS NULL
         LIMIT 1;
    END IF;

    v_regra       := coalesce(v_regra, 'previdenciario_suspende');
    v_dias_empreg := coalesce(v_dias_empreg, 15);
    v_vigencia    := coalesce(v_vigencia, DATE '2026-01-01');

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

    -- Desligamento no ano-base, com o aviso prévio da própria rescisão.
    SELECT r.data_desligamento, r.aviso_tipo, coalesce(r.dias_aviso, 0)
      INTO v_desligamento, v_aviso_tipo, v_dias_aviso
      FROM public.folha_rescisoes r
     WHERE r.tenant_id = p_tenant
       AND regexp_replace(coalesce(r.colaborador_cpf, ''), '\D', '', 'g') = v_cpf
       AND r.data_desligamento BETWEEN v_ano_ini AND v_ano_fim
     ORDER BY r.data_desligamento
     LIMIT 1;

    IF v_desligamento IS NULL THEN
        SELECT min(a.data_desligamento) INTO v_desligamento
          FROM public.admissoes a
         WHERE a.tenant_id = p_tenant
           AND regexp_replace(coalesce(a.cpf, ''), '\D', '', 'g') = v_cpf
           AND a.data_desligamento BETWEEN v_ano_ini AND v_ano_fim;
    END IF;

    -- PROJEÇÃO DO AVISO PRÉVIO INDENIZADO (CLT, art. 487, §1º; Súmula 371
    -- do TST): o contrato termina na data projetada, não na baixa. É o
    -- que decide o avo do último mês.
    v_fim_contrato := v_desligamento;
    IF v_desligamento IS NOT NULL
       AND lower(coalesce(v_aviso_tipo, '')) = 'indenizado'
       AND v_dias_aviso > 0 THEN
        v_fim_contrato := v_desligamento + v_dias_aviso;
        IF v_fim_contrato > v_ano_fim THEN
            v_fim_contrato := v_ano_fim;
        END IF;
        v_avisos := array_append(v_avisos, format(
            'Aviso prévio indenizado de %s dias: o contrato projeta até %s e os avos foram contados até lá (CLT, art. 487, §1º; Súmula 371 do TST).',
            v_dias_aviso, to_char(v_desligamento + v_dias_aviso, 'DD/MM/YYYY')));
    END IF;

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

    WITH meses AS MATERIALIZED (
        SELECT m AS mes,
               make_date(p_ano, m, 1) AS mes_ini,
               (make_date(p_ano, m, 1) + INTERVAL '1 month - 1 day')::DATE AS mes_fim
          FROM generate_series(1, 12) AS m
    ),
    vinculo AS MATERIALIZED (
        SELECT mes, mes_ini, mes_fim,
               greatest(mes_ini, v_admissao) AS ini,
               least(mes_fim, coalesce(v_fim_contrato, mes_fim)) AS fim
          FROM meses
    ),
    dias AS MATERIALIZED (
        SELECT mes, mes_ini, mes_fim, ini, fim,
               CASE WHEN fim >= ini THEN (fim - ini + 1) ELSE 0 END AS dias_vinculo
          FROM vinculo
    ),
    computo AS MATERIALIZED (
        SELECT d.mes, d.dias_vinculo,
               CASE WHEN NOT v_tem_ponto OR d.dias_vinculo = 0 THEN 0 ELSE (
                   SELECT count(*)::INT
                     FROM public.ponto_diario pd
                    WHERE pd.tenant_id = p_tenant
                      AND regexp_replace(coalesce(pd.colaborador_cpf, ''), '\D', '', 'g') = v_cpf
                      AND pd.data BETWEEN d.ini AND d.fim
                      AND pd.status = 'falta'
               ) END AS faltas,
               -- Dias por conta do INSS. SÓ as espécies COMUNS suspendem o
               -- avo: nas ACIDENTÁRIAS (B91 e B92) a ausência não pesa
               -- contra a gratificação natalina (Súmula 46 do TST; Lei
               -- 8.213/1991, art. 4º, parágrafo único).
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
                      AND ap.especie_beneficio IN ('B31', 'B32')
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
    SELECT count(*) FILTER (WHERE conta)::INT,
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

    -- Afastamento acidentário no ano: a memória diz por que ele não tirou
    -- avo, para ninguém "corrigir" isso depois por engano.
    IF EXISTS (
        SELECT 1 FROM public.afastamentos af
          JOIN public.afastamentos_previdenciario ap ON ap.afastamento_id = af.id
         WHERE af.tenant_id = p_tenant
           AND regexp_replace(coalesce(af.colaborador_cpf, ''), '\D', '', 'g') = v_cpf
           AND ap.especie_beneficio IN ('B91', 'B92')
           AND af.data_inicio <= v_ano_fim
           AND coalesce(af.data_fim, v_ano_fim) >= v_ano_ini
    ) THEN
        v_avisos := array_append(v_avisos,
            'Há afastamento por acidente do trabalho no ano-base: os dias contam normalmente para o 13º (Súmula 46 do TST; Lei 8.213/1991, art. 4º, parágrafo único).');
    END IF;

    IF v_avos = 0 THEN
        v_avisos := array_append(v_avisos,
            'Nenhum mês do ano-base fechou 15 dias de trabalho — não há avo a pagar. Confira admissão, faltas e afastamentos.');
    END IF;

    RETURN jsonb_build_object(
        'avos',                v_avos,
        'ano',                 p_ano,
        'admissao',            v_admissao,
        'desligamento',        v_desligamento,
        'fim_contrato',        v_fim_contrato,
        'aviso_previo_tipo',   v_aviso_tipo,
        'aviso_previo_dias',   v_dias_aviso,
        'tem_ponto',           v_tem_ponto,
        'afastamento_regra',   v_regra,
        'dias_empregador',     v_dias_empreg,
        'parametros_vigencia', v_vigencia,
        'fundamento',          'Lei 4.090/1962, art. 1º, § 2º (fração >= 15 dias); CLT, art. 487, §1º (projeção do aviso indenizado); Súmula 46 do TST (acidente do trabalho)',
        'apurado_em',          now(),
        'meses',               v_meses,
        'avisos',              to_jsonb(v_avisos)
    );
END $fn$;

COMMENT ON FUNCTION public.decimo_terceiro_avos(UUID, TEXT, INT, UUID) IS
    'Avos do 13o (Lei 4.090/1962): 1/12 por mes com fracao >= 15 dias, descontadas faltas do ponto e afastamento previdenciario COMUM. Projeta o aviso previo indenizado (CLT art. 487 §1o) e nao desconta afastamento acidentario (Sumula 46 do TST). Somente leitura.';

GRANT EXECUTE ON FUNCTION public.decimo_terceiro_avos(UUID, TEXT, INT, UUID) TO authenticated;

-- ── Documentacao de testes e rotinas ──────────────────────────────────
DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'financeiro/decimo-terceiro';
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo financeiro/decimo-terceiro nao existe nesta base — casos nao inseridos.';
    RETURN;
  END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'DEC13-004', 'Aviso prévio indenizado projeta o tempo e pode gerar mais um avo',
   'negativo', 'critica', 'aprovado', 'api',
   'CLT, art. 487, §1º; Súmula 371 do TST; OJ 82 da SDI-1 do TST',
   'O aviso prévio indenizado integra o tempo de serviço para todos os efeitos legais. Desligado em 20/11 com 30 dias de aviso indenizado, o contrato projeta até 20/12: dezembro passa a ter 20 dias e vira mais um avo. Ignorar a projeção paga 11/12 onde a lei manda 12/12 — diferença que volta como reclamatória.',
   'Vínculo desligado em 20/11 do ano-base, com aviso prévio indenizado de 30 dias.',
   '[{"ordem": 1, "acao": "Apurar o 13º sem considerar a projeção", "resultado_esperado": "11 avos"}, {"ordem": 2, "acao": "Apurar considerando a projeção do aviso indenizado", "resultado_esperado": "12 avos — dezembro fecha 20 dias com a projeção"}, {"ordem": 3, "acao": "Conferir a memória", "resultado_esperado": "A memória mostra a data projetada do fim do contrato, não só a data do desligamento"}]'::jsonb,
   'Aviso indenizado conta como tempo de serviço — inclusive para o avo de dezembro.',
   'Requisitos YE-DP-13-001: RN-001 e RN-009 (rescisão). O mesmo vale para as férias proporcionais.'),

  (v_mod, 'DEC13-005', 'Fronteira dos 15 dias: dia 16 conta o avo, dia 17 não',
   'negativo', 'alta', 'aprovado', 'api',
   'Lei 4.090/1962, art. 1º, §2º (fração igual ou superior a 15 dias)',
   'A regra da fração é de contagem exata e é onde mais se erra por um dia. Em mês de 31 dias, admissão no dia 17 deixa 15 dias trabalhados (17 a 31) e CONTA; no dia 18 deixa 14 e NÃO conta. Fevereiro, com 28 ou 29 dias, tem fronteira própria. O teste fixa as bordas para que nenhuma mudança futura as mova sem que alguém perceba.',
   'Vínculos fictícios admitidos exatamente nas datas de fronteira do ano-base.',
   '[{"ordem": 1, "acao": "Admitido em 17/03 (mês de 31 dias)", "resultado_esperado": "Março conta — 15 dias trabalhados"}, {"ordem": 2, "acao": "Admitido em 18/03", "resultado_esperado": "Março não conta — 14 dias"}, {"ordem": 3, "acao": "Admitido em 14/02 (ano comum, 28 dias)", "resultado_esperado": "Fevereiro conta — 15 dias"}, {"ordem": 4, "acao": "Admitido em 15/02 (ano comum)", "resultado_esperado": "Fevereiro não conta — 14 dias"}]'::jsonb,
   'A borda é 15 dias exatos, contados no calendário do próprio mês.',
   'Requisitos YE-DP-13-001: RN-001 / CA-001. Complementa DEC13-001, que cobre o caso geral.'),

  (v_mod, 'DEC13-006', 'Afastamento por acidente de trabalho conta como tempo de serviço',
   'alternativo', 'alta', 'aprovado', 'api',
   'Lei 8.213/1991, art. 4º, parágrafo único e art. 118; CLT, art. 4º; Súmula 46 do TST',
   'O afastamento acidentário (benefício B-91) não é igual ao auxílio-doença comum: o período é contado como tempo de serviço para todos os efeitos, inclusive 13º. Tratar acidente de trabalho como doença comum tira avos que a lei manda pagar.',
   'Vínculo com 4 meses de afastamento acidentário (B-91) no ano-base.',
   '[{"ordem": 1, "acao": "Apurar o 13º de quem se afastou por acidente de trabalho", "resultado_esperado": "Os meses de afastamento contam como avos do empregador"}, {"ordem": 2, "acao": "Comparar com afastamento por doença comum", "resultado_esperado": "Na doença comum o empregador paga só os 15 primeiros dias e o restante é abono anual do INSS"}, {"ordem": 3, "acao": "Conferir a memória", "resultado_esperado": "A memória nomeia o tipo de afastamento e o efeito aplicado"}]'::jsonb,
   'Acidente de trabalho conta tempo; doença comum divide com o INSS.',
   'Requisitos YE-DP-13-001: RN-008. Complementa DEC13-003, que trata maternidade e doença comum.'),

  (v_mod, 'DEC13-022', 'Horas extras entram pela média física × valor da hora atual (Súmula 347)',
   'alternativo', 'alta', 'aprovado', 'api',
   'Súmula 347 do TST; Decreto 57.155/1965, art. 2º',
   'A média de horas extras do 13º é FÍSICA: soma-se a quantidade de HORAS do ano, divide-se pelos meses e multiplica-se pelo valor da hora VIGENTE no pagamento. Usar a média dos valores históricos paga a menos sempre que houve aumento salarial no ano — é passivo certo.',
   'Vínculo com 10 horas extras por mês o ano todo e aumento salarial no meio do ano.',
   '[{"ordem": 1, "acao": "Apurar a média pela quantidade de horas × valor atual", "resultado_esperado": "Média calculada sobre o salário vigente"}, {"ordem": 2, "acao": "Comparar com a média dos valores pagos no ano", "resultado_esperado": "A média física é MAIOR quando houve aumento"}, {"ordem": 3, "acao": "Conferir a memória", "resultado_esperado": "A memória informa qual critério foi usado e por quê"}]'::jsonb,
   'Média física protege o cálculo do aumento salarial no meio do ano.',
   'Requisitos YE-DP-13-001: RN-003. Sem registro de ponto no ano, o sistema usa os valores pagos e avisa.'),

  (v_mod, 'DEC13-023', 'Adicionais habituais integram a base do 13º',
   'feliz', 'alta', 'aprovado', 'api',
   'Súmula 60 (adicional noturno), Súmula 132 (adicional de periculosidade) e Súmula 139 (adicional de insalubridade) do TST; Decreto 57.155/1965, art. 2º',
   'Adicional noturno, de insalubridade e de periculosidade pagos com habitualidade integram a remuneração e, portanto, a base do 13º. Se as rubricas desses adicionais não estiverem marcadas como integrantes do 13º no cadastro, o cálculo sai a menor sem ninguém perceber.',
   'Rubricas de adicional noturno, insalubridade e periculosidade cadastradas e pagas com habitualidade.',
   '[{"ordem": 1, "acao": "Conferir a marcação das rubricas de adicional", "resultado_esperado": "Marcadas como integrantes da base do 13º"}, {"ordem": 2, "acao": "Apurar a média das variáveis", "resultado_esperado": "Os adicionais habituais entram na média"}, {"ordem": 3, "acao": "Conferir a memória", "resultado_esperado": "Cada rubrica somada aparece nomeada na memória"}]'::jsonb,
   'Adicional habitual é remuneração — e remuneração entra no 13º.',
   'Requisitos YE-DP-13-001: RN-003 / CA-002. Complementa DEC13-020.'),

  (v_mod, 'DEC13-034', 'Política do adiantamento: as duas opções da lei, à escolha da empresa',
   'alternativo', 'alta', 'aprovado', 'api',
   'Lei 4.749/1965, art. 2º, caput',
   'A lei manda adiantar METADE do salário do mês anterior. A prática consolidada admite também metade do 13º apurado (com médias). As duas leituras são defensáveis, então a escolha é da empresa — e precisa ficar registrada, com efeito real no cálculo e a mesma política valendo para todos no ano.',
   'Empresa com a política do adiantamento configurada.',
   '[{"ordem": 1, "acao": "Configurar a política ''metade da remuneração do mês anterior'' e apurar a 1ª parcela", "resultado_esperado": "Valor = 50% da remuneração do mês anterior"}, {"ordem": 2, "acao": "Trocar para ''metade do 13º apurado'' e apurar de novo", "resultado_esperado": "Valor = 50% do 13º com médias — diferente do anterior"}, {"ordem": 3, "acao": "Conferir o registro", "resultado_esperado": "A política escolhida fica gravada e visível na memória do cálculo"}]'::jsonb,
   'As duas opções existem, a empresa escolhe e o sistema obedece — sem valor mágico.',
   'Requisitos YE-DP-13-001: RN-004. Ponto [VAL] do documento: a escolha deve ser conferida com a contabilidade.'),

  (v_mod, 'DEC13-035', 'Adiantamento nas férias fora de janeiro é avisado, não recusado',
   'negativo', 'media', 'aprovado', 'api',
   'Lei 4.749/1965, art. 2º, §2º',
   'O empregado que quer receber a 1ª parcela nas férias deve requerer em JANEIRO do ano correspondente. Pedido fora dessa janela não obriga o empregador. O sistema não deve recusar em silêncio nem pagar sem registro: deve avisar que o pedido saiu fora do prazo e deixar a decisão documentada.',
   'Pedido de férias com adiantamento do 13º requerido em março.',
   '[{"ordem": 1, "acao": "Gerar os adiantamentos das férias do ano", "resultado_esperado": "Os pedidos de janeiro geram a 1ª parcela normalmente"}, {"ordem": 2, "acao": "Conferir o pedido feito em março", "resultado_esperado": "Aparece na lista de avisos como fora da janela do §2º"}, {"ordem": 3, "acao": "Conferir a contagem", "resultado_esperado": "O retorno informa quantos pedidos ficaram fora de janeiro"}]'::jsonb,
   'Fora de janeiro não é proibido — é decisão da empresa, e fica registrada.',
   'Requisitos YE-DP-13-001: RN-004. Complementa DEC13-032.'),

  (v_mod, 'DEC13-043', 'INSS do 13º respeita faixas e teto, e bate com a tabela vigente',
   'feliz', 'critica', 'aprovado', 'api',
   'Lei 8.212/1991, art. 20 e art. 28, §7º; Decreto 3.048/1999, art. 214, §6º',
   'O INSS do 13º é progressivo por faixas e limitado ao teto. O cálculo do banco (usado no lote) e o da tela precisam dar o MESMO número em todas as faixas, inclusive nas bordas e acima do teto — divergência entre os dois é erro de recolhimento, com multa.',
   'Tabela de INSS vigente cadastrada.',
   '[{"ordem": 1, "acao": "Calcular o INSS em bases de cada faixa e nas bordas", "resultado_esperado": "Valor progressivo, faixa a faixa"}, {"ordem": 2, "acao": "Calcular o INSS em base acima do teto", "resultado_esperado": "Desconto limitado ao teto — não cresce mais"}, {"ordem": 3, "acao": "Comparar banco e tela", "resultado_esperado": "Mesmo valor, centavo a centavo"}]'::jsonb,
   'Faixas, bordas e teto conferidos — e os dois caminhos de cálculo concordando.',
   'Requisitos YE-DP-13-001: RN-005 / CA-004. Complementa DEC13-040.'),

  (v_mod, 'DEC13-052', 'Provisão do 13º é revertida quando o colaborador é desligado',
   'negativo', 'alta', 'aprovado', 'api',
   'Lei 6.404/1976, art. 177 (regime de competência); NBC TG 1000, seção 21 (provisões); documento YE-DP-13-001, CA-009',
   'A provisão acumula 1/12 por mês enquanto o vínculo existe. Quando o colaborador é desligado e o 13º é quitado na rescisão, a provisão daquele vínculo precisa ser REVERTIDA — senão o balanço carrega para sempre uma obrigação que já foi paga.',
   'Colaborador provisionado durante o ano e desligado antes de dezembro.',
   '[{"ordem": 1, "acao": "Provisionar competências com o vínculo ativo", "resultado_esperado": "Provisão acumulada mês a mês"}, {"ordem": 2, "acao": "Desligar o colaborador e provisionar a competência seguinte", "resultado_esperado": "A provisão do desligado é revertida, não repetida"}, {"ordem": 3, "acao": "Conciliar o ano", "resultado_esperado": "Provisionado e pago fecham, sem sobra do desligado"}]'::jsonb,
   'Provisão de quem saiu não fica pendurada no balanço.',
   'Requisitos YE-DP-13-001: RNF-007. Complementa DEC13-051.'),

  (v_mod, 'DEC13-061', 'Culpa recíproca paga metade do 13º proporcional',
   'alternativo', 'alta', 'aprovado', 'api',
   'CLT, art. 484; Súmula 14 do TST',
   'Reconhecida a culpa recíproca, as verbas rescisórias devidas pela dispensa sem justa causa são pagas pela METADE — inclusive o 13º proporcional. Tratar como justa causa (zero) ou como dispensa comum (integral) erra nos dois sentidos.',
   'Rescisão por culpa recíproca reconhecida judicialmente, no meio do ano-base.',
   '[{"ordem": 1, "acao": "Apurar o 13º da rescisão por culpa recíproca", "resultado_esperado": "Metade do 13º proporcional aos avos"}, {"ordem": 2, "acao": "Comparar com a dispensa sem justa causa", "resultado_esperado": "Metade do valor da dispensa comum"}, {"ordem": 3, "acao": "Conferir o fundamento", "resultado_esperado": "A memória cita o art. 484 da CLT e a Súmula 14 do TST"}]'::jsonb,
   'Culpa recíproca não é zero nem inteiro: é metade.',
   'Requisitos YE-DP-13-001: RN-009. DESL-035 cobre o lado do aviso prévio; aqui é o 13º.'),

  (v_mod, 'DEC13-062', 'Pedido de demissão mantém o 13º proporcional',
   'feliz', 'alta', 'aprovado', 'api',
   'Lei 4.090/1962, art. 3º; Súmula 157 do TST',
   'Quem pede demissão tem direito ao 13º proporcional aos meses trabalhados. Só a dispensa por justa causa afasta a gratificação. Confundir os dois motivos retém verba devida — e a Súmula 157 é expressa.',
   'Rescisão por pedido de demissão em agosto do ano-base.',
   '[{"ordem": 1, "acao": "Apurar o 13º da rescisão por pedido de demissão", "resultado_esperado": "8/12 do 13º, proporcional aos avos"}, {"ordem": 2, "acao": "Comparar com a dispensa por justa causa", "resultado_esperado": "Na justa causa, zero"}, {"ordem": 3, "acao": "Conferir o abatimento do adiantamento", "resultado_esperado": "Se houve 1ª parcela paga, ela é deduzida"}]'::jsonb,
   'Pedir demissão não faz perder o 13º proporcional.',
   'Requisitos YE-DP-13-001: RN-009. Complementa DEC13-060.'),

  (v_mod, 'DEC13-063', 'Falecimento: o 13º proporcional é devido e vai aos dependentes',
   'alternativo', 'media', 'aprovado', 'api',
   'Lei 6.858/1980, art. 1º; Lei 4.090/1962, art. 3º',
   'Com o falecimento do empregado, o 13º proporcional continua devido e é pago aos dependentes habilitados na Previdência, independentemente de inventário. O sistema não pode tratar o falecimento como perda da gratificação.',
   'Rescisão por falecimento em setembro do ano-base.',
   '[{"ordem": 1, "acao": "Apurar o 13º da rescisão por falecimento", "resultado_esperado": "9/12, proporcional aos avos — valor devido"}, {"ordem": 2, "acao": "Conferir o fundamento", "resultado_esperado": "A memória registra que o pagamento segue a Lei 6.858/1980"}, {"ordem": 3, "acao": "Conferir que não é tratado como justa causa", "resultado_esperado": "Valor diferente de zero"}]'::jsonb,
   'Falecimento não extingue a gratificação proporcional.',
   'Requisitos YE-DP-13-001: RN-009. O encaminhamento aos dependentes é operação do DP, fora do cálculo.'),

  (v_mod, 'DEC13-072', 'Rodar o lote duas vezes não duplica parcela',
   'negativo', 'alta', 'aprovado', 'api',
   'Documento YE-DP-13-001, RF-004 e RNF-008 (processamento em lote idempotente)',
   'O processamento em lote é feito por pessoas, sob pressão de prazo, e será clicado duas vezes. A segunda passada não pode criar uma segunda parcela viva para o mesmo colaborador: tem de pular quem já tem cálculo e dizer quantos pulou.',
   'Empresa com colaboradores aptos e a 1ª parcela já processada.',
   '[{"ordem": 1, "acao": "Processar o lote da 1ª parcela", "resultado_esperado": "Cálculos criados para os aptos"}, {"ordem": 2, "acao": "Processar o mesmo lote de novo", "resultado_esperado": "Nenhum cálculo novo; o retorno informa quantos já existiam"}, {"ordem": 3, "acao": "Conferir a base", "resultado_esperado": "Uma única parcela viva por colaborador/ano"}]'::jsonb,
   'Clicar duas vezes não duplica folha.',
   'Requisitos YE-DP-13-001: RF-004. A trava de base é a unicidade da parcela viva.'),

  (v_mod, 'DEC13-073', 'Prazo legal recua para o último dia útil, inclusive em feriado municipal',
   'negativo', 'alta', 'aprovado', 'api',
   'Lei 4.749/1965, arts. 1º e 2º; Lei 662/1949 e Lei 9.093/1995 (feriados civis e municipais)',
   'Se 30/11 ou 20/12 caem em sábado, domingo ou feriado, o pagamento tem de ser ANTECIPADO para o último dia útil anterior — nunca adiado. A conta precisa enxergar também o feriado municipal da cidade do estabelecimento, que é o mais fácil de esquecer.',
   'Feriado municipal cadastrado no dia útil imediatamente anterior à data-limite.',
   '[{"ordem": 1, "acao": "Consultar o prazo da 2ª parcela num ano em que 20/12 cai em domingo", "resultado_esperado": "Data-limite antecipada para a sexta-feira"}, {"ordem": 2, "acao": "Cadastrar feriado municipal nessa sexta e consultar de novo", "resultado_esperado": "Antecipa mais um dia útil"}, {"ordem": 3, "acao": "Conferir a 1ª parcela em 30/11", "resultado_esperado": "Mesma regra de antecipação"}]'::jsonb,
   'A data-limite anda para trás, nunca para frente.',
   'Requisitos YE-DP-13-001: RN-002 / CA-003. Complementa DEC13-031.')
  ON CONFLICT (codigo) DO UPDATE SET
      titulo = EXCLUDED.titulo, base_legal = EXCLUDED.base_legal,
      objetivo = EXCLUDED.objetivo, pre_condicoes = EXCLUDED.pre_condicoes,
      passos = EXCLUDED.passos, resultado_esperado = EXCLUDED.resultado_esperado,
      observacoes = EXCLUDED.observacoes, nivel = EXCLUDED.nivel,
      prioridade = EXCLUDED.prioridade, updated_at = now();

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Documentacao de testes do 13o: % casos antes, % depois.', v_antes, v_depois;
END $doc$;

-- ── DEC13-005: a fronteira dos 15 dias, dia a dia ─────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_005()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_ten uuid := public.qa_sandbox_tenant_id();
  v_ano int := extract(year from CURRENT_DATE)::int - 1;
  v_erros text[] := ARRAY[]::text[]; v_lidos text[] := ARRAY[]::text[];
  v_cpf text; v_avos int; c record;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Apurar os avos de vinculos admitidos exatamente nas datas de fronteira';
  r.esperado := 'Mes com 15 dias ou mais conta; com 14, nao conta (Lei 4.090, art. 1o, §2o)';

  FOR c IN
    SELECT * FROM (VALUES
      ('90000005053', make_date(v_ano,3,17), 10, 'admitido em 17/03 (15 dias)'),
      ('90000005134', make_date(v_ano,3,18),  9, 'admitido em 18/03 (14 dias)'),
      ('90000005215', make_date(v_ano,2,14), 11, 'admitido em 14/02'),
      ('90000005304', make_date(v_ano,2,15), 10, 'admitido em 15/02')
    ) AS t(cpf, adm, avos_esperados, rotulo)
  LOOP
    -- vinculo efemero: a sonda cria, le e desfaz o proprio rastro
    DELETE FROM public.admissoes WHERE tenant_id = v_ten AND cpf = c.cpf;
    INSERT INTO public.admissoes (tenant_id, nome_completo, cpf, cargo, data_admissao, status)
    VALUES (v_ten, 'QA Fronteira ' || c.cpf, c.cpf, 'QA', c.adm, 'concluido');

    v_avos := COALESCE((public.decimo_terceiro_avos(v_ten, c.cpf, v_ano, NULL)->>'avos')::int, -1);
    v_lidos := array_append(v_lidos, format('%s: %s avos', c.rotulo, v_avos));
    IF v_avos <> c.avos_esperados THEN
      v_erros := array_append(v_erros,
        format('%s deveria dar %s avos e deu %s', c.rotulo, c.avos_esperados, v_avos));
    END IF;

    DELETE FROM public.admissoes WHERE tenant_id = v_ten AND cpf = c.cpf;
  END LOOP;

  IF array_length(v_erros,1) IS NOT NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a fronteira dos 15 dias esta deslocada — ' || array_to_string(v_erros, '; ')
             || '. Um dia de diferenca na contagem vira um avo a mais ou a menos em toda a folha.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Fronteiras conferidas (' || array_to_string(v_lidos, '; ') || ').';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-043: faixas, bordas e teto do INSS ──────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_043()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_ten uuid := public.qa_sandbox_tenant_id();
  v_erros text[] := ARRAY[]::text[]; v_lidos text[] := ARRAY[]::text[];
  v_ant numeric := -1; v_val numeric; v_teto numeric; v_base numeric;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Calcular o INSS do 13o em bases crescentes, das faixas ate acima do teto';
  r.esperado := 'Valor progressivo que nunca diminui e para de crescer no teto (Lei 8.212/1991, art. 20)';

  FOREACH v_base IN ARRAY ARRAY[1000, 1412, 1500, 2666.68, 4000.03, 7786.02, 9000, 20000]::numeric[]
  LOOP
    v_val := COALESCE((public.decimo_terceiro_inss(v_base, v_ten, NULL)->>'valor')::numeric, -1);
    v_lidos := array_append(v_lidos, format('base %s -> %s', v_base, v_val));
    IF v_val < v_ant THEN
      v_erros := array_append(v_erros, format('base %s desconta MENOS que a base anterior', v_base));
    END IF;
    IF v_val > v_base THEN
      v_erros := array_append(v_erros, format('base %s desconta mais que o proprio 13o', v_base));
    END IF;
    v_ant := v_val;
  END LOOP;

  r.passo_ordem := 2;
  r.passo_acao := 'Conferir o teto: dobrar a base acima do teto nao pode aumentar o desconto';
  r.esperado := 'Mesmo valor — o desconto e limitado ao teto';
  v_teto := (public.decimo_terceiro_inss(20000, v_ten, NULL)->>'valor')::numeric;
  IF (public.decimo_terceiro_inss(40000, v_ten, NULL)->>'valor')::numeric <> v_teto THEN
    v_erros := array_append(v_erros, 'o desconto continua crescendo acima do teto');
  END IF;

  IF array_length(v_erros,1) IS NOT NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o INSS do 13o nao respeita a progressao ou o teto — '
             || array_to_string(v_erros, '; ') || '. Recolhimento errado gera multa.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Progressao e teto conferidos (%s); teto em R$ %s.',
                       array_to_string(v_lidos, '; '), v_teto);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-073: a data-limite anda para tras, nunca para frente ────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_073()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_erros text[] := ARRAY[]::text[]; v_lidos text[] := ARRAY[]::text[];
  v_d date; v_ano int; v_limite date;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Consultar o prazo legal das duas parcelas em varios anos';
  r.esperado := 'Sempre dia util, e nunca depois de 30/11 (1a) ou 20/12 (2a) — Lei 4.749/1965';

  FOR v_ano IN 2024..2030 LOOP
    -- 1a parcela: limite 30/11
    v_d := public.decimo_terceiro_prazo_legal(v_ano, 1, NULL, NULL);
    v_limite := make_date(v_ano, 11, 30);
    IF v_d > v_limite THEN
      v_erros := array_append(v_erros, format('%s: 1a parcela caiu em %s, depois de 30/11', v_ano, v_d));
    END IF;
    IF extract(isodow from v_d) > 5 THEN
      v_erros := array_append(v_erros, format('%s: 1a parcela caiu em fim de semana (%s)', v_ano, v_d));
    END IF;
    v_lidos := array_append(v_lidos, format('%s 1a=%s', v_ano, v_d));

    -- 2a parcela: limite 20/12
    v_d := public.decimo_terceiro_prazo_legal(v_ano, 2, NULL, NULL);
    v_limite := make_date(v_ano, 12, 20);
    IF v_d > v_limite THEN
      v_erros := array_append(v_erros, format('%s: 2a parcela caiu em %s, depois de 20/12', v_ano, v_d));
    END IF;
    IF extract(isodow from v_d) > 5 THEN
      v_erros := array_append(v_erros, format('%s: 2a parcela caiu em fim de semana (%s)', v_ano, v_d));
    END IF;
    v_lidos := array_append(v_lidos, format('2a=%s', v_d));
  END LOOP;

  IF array_length(v_erros,1) IS NOT NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a data-limite do 13o nao antecipa corretamente — '
             || array_to_string(v_erros, '; ')
             || '. Pagar fora da janela e infracao mesmo com o valor certo.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Prazos conferidos em 7 anos, sempre em dia util e dentro do limite ('
             || array_to_string(v_lidos, ', ') || ').';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-006: acidente de trabalho nao derruba avo (Sumula 46 TST) ───
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_006()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_ten uuid := public.qa_sandbox_tenant_id();
  v_ano int := extract(year from CURRENT_DATE)::int - 1;
  v_cpf text := '90000005487'; v_af uuid;
  v_avos_acid int; v_avos_comum int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Apurar os avos de quem ficou 4 meses afastado por ACIDENTE DE TRABALHO (B91)';
  r.esperado := 'Os meses contam: a ausencia por acidente nao pesa contra o 13o (Sumula 46 do TST)';

  DELETE FROM public.afastamentos WHERE tenant_id = v_ten AND colaborador_cpf = v_cpf;
  DELETE FROM public.admissoes   WHERE tenant_id = v_ten AND cpf = v_cpf;
  INSERT INTO public.admissoes (tenant_id, nome_completo, cpf, cargo, data_admissao, status)
  VALUES (v_ten, 'QA Acidentado', v_cpf, 'QA', make_date(v_ano - 3, 1, 10), 'concluido');

  INSERT INTO public.afastamentos (tenant_id, colaborador_cpf, colaborador_nome,
                                   data_inicio, data_fim, nexo_trabalho, observacoes)
  VALUES (v_ten, v_cpf, 'QA Acidentado',
          make_date(v_ano, 3, 1), make_date(v_ano, 6, 30), 'sim'::nexo_trabalho, 'QA DEC13-006')
  RETURNING id INTO v_af;
  INSERT INTO public.afastamentos_previdenciario (tenant_id, afastamento_id, especie_beneficio,
                                                  data_inicio_beneficio)
  VALUES (v_ten, v_af, 'B91', make_date(v_ano, 3, 16));

  v_avos_acid := COALESCE((public.decimo_terceiro_avos(v_ten, v_cpf, v_ano, NULL)->>'avos')::int, -1);

  r.passo_ordem := 2;
  r.passo_acao := 'Trocar o beneficio para DOENCA COMUM (B31) e apurar de novo';
  r.esperado := 'Ai sim os meses de beneficio saem dos avos do empregador — o INSS paga o abono anual';
  UPDATE public.afastamentos_previdenciario SET especie_beneficio = 'B31' WHERE afastamento_id = v_af;
  v_avos_comum := COALESCE((public.decimo_terceiro_avos(v_ten, v_cpf, v_ano, NULL)->>'avos')::int, -1);

  DELETE FROM public.afastamentos_previdenciario WHERE afastamento_id = v_af;
  DELETE FROM public.afastamentos WHERE id = v_af;
  DELETE FROM public.admissoes WHERE tenant_id = v_ten AND cpf = v_cpf;

  IF v_avos_acid < 12 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o afastamento por ACIDENTE DE TRABALHO derruba avos igual ao de '
             || 'doenca comum (acidentario: %s avos; doenca comum: %s avos). A Sumula 46 do TST e '
             || 'expressa: as ausencias por acidente do trabalho NAO sao consideradas contra a '
             || 'gratificacao natalina, e o art. 4o, paragrafo unico, da Lei 8.213/1991 conta o '
             || 'periodo como tempo de servico. Do jeito atual a empresa paga a menos e a '
             || 'diferenca volta como reclamatoria. Correcao: as especies acidentarias (B91, B92) '
             || 'nao entram no desconto de dias do empregador; as comuns (B31, B32) continuam '
             || 'entrando.', v_avos_acid, v_avos_comum);
  ELSIF v_avos_comum >= 12 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO ao contrario: a doenca comum tambem manteve %s avos. O empregador '
             || 'so responde pelos 15 primeiros dias; o restante e abono anual do INSS. Contar '
             || 'tudo paga a MAIS e duplica a despesa.', v_avos_comum);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Cada afastamento com seu efeito: acidente de trabalho manteve %s avos '
             || '(Sumula 46 do TST); doenca comum ficou com %s, cabendo o abono anual ao INSS.',
             v_avos_acid, v_avos_comum);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-004: projecao do aviso previo indenizado ────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_004()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_ten uuid := public.qa_sandbox_tenant_id();
  v_ano int := extract(year from CURRENT_DATE)::int - 1;
  v_cpf text := '90000005568'; v_avos int; v_adm uuid;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Apurar os avos de quem foi desligado em 20/11 com aviso previo INDENIZADO de 30 dias';
  r.esperado := '12 avos: a projecao leva o contrato ate 20/12 e dezembro fecha 20 dias (CLT, art. 487, §1o; Sumula 371 do TST)';

  DELETE FROM public.admissoes WHERE tenant_id = v_ten AND cpf = v_cpf;
  INSERT INTO public.admissoes (tenant_id, nome_completo, cpf, cargo, data_admissao,
                                data_desligamento, status)
  VALUES (v_ten, 'QA Aviso Indenizado', v_cpf, 'QA', make_date(v_ano - 2, 2, 1),
          make_date(v_ano, 11, 20), 'concluido')
  RETURNING id INTO v_adm;

  DELETE FROM public.folha_rescisoes WHERE tenant_id = v_ten AND colaborador_cpf = v_cpf;
  INSERT INTO public.folha_rescisoes (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
                                      admissao_id, tipo_rescisao, data_desligamento,
                                      aviso_tipo, dias_aviso)
  VALUES (v_ten, 'qa-dec13-004', 'QA Aviso Indenizado', v_cpf, v_adm,
          'DISPENSA_SEM_JUSTA_CAUSA', make_date(v_ano, 11, 20), 'indenizado', 30);

  v_avos := COALESCE((public.decimo_terceiro_avos(v_ten, v_cpf, v_ano, NULL)->>'avos')::int, -1);

  DELETE FROM public.folha_rescisoes WHERE tenant_id = v_ten AND colaborador_cpf = v_cpf;
  DELETE FROM public.admissoes WHERE id = v_adm;

  IF v_avos < 12 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a apuracao parou na data do desligamento e devolveu %s avos. O '
             || 'aviso previo INDENIZADO integra o tempo de servico para todos os efeitos legais '
             || '(CLT, art. 487, §1o; Sumula 371 do TST): desligado em 20/11 com 30 dias de aviso, '
             || 'o contrato projeta ate 20/12 e dezembro fecha 20 dias — o 12o avo e devido. '
             || 'Pagar 11/12 onde a lei manda 12/12 e diferenca que volta como reclamatoria, e a '
             || 'mesma projecao vale para as ferias proporcionais. Correcao: somar os dias do '
             || 'aviso indenizado a data de fim do contrato antes de contar os avos.', v_avos);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Projecao do aviso indenizado considerada: %s avos, com dezembro contado '
             || 'pela data projetada do fim do contrato.', v_avos);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-061/062/063: o motivo da rescisao e o 13o ───────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_rescisao_motivo(
  p_tipo text, p_mes int, p_fator numeric, p_cpf text, p_nome text)
RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE
  v_ten uuid := public.qa_sandbox_tenant_id();
  v_ano int := extract(year from CURRENT_DATE)::int - 1;
  v_adm uuid; v_resc uuid; v_out jsonb;
BEGIN
  DELETE FROM public.folha_rescisoes WHERE tenant_id = v_ten AND colaborador_cpf = p_cpf;
  DELETE FROM public.admissoes WHERE tenant_id = v_ten AND cpf = p_cpf;
  INSERT INTO public.admissoes (tenant_id, nome_completo, cpf, cargo, salario, data_admissao,
                                data_desligamento, status)
  VALUES (v_ten, p_nome, p_cpf, 'QA', 3000, make_date(v_ano - 2, 2, 1),
          make_date(v_ano, p_mes, 25), 'concluido')
  RETURNING id INTO v_adm;

  INSERT INTO public.folha_rescisoes (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
                                      admissao_id, tipo_rescisao, data_desligamento)
  VALUES (v_ten, 'qa-' || p_cpf, p_nome, p_cpf, v_adm, p_tipo::public.rescisao_tipo, make_date(v_ano, p_mes, 25))
  RETURNING id INTO v_resc;

  v_out := public.decimo_terceiro_da_rescisao(v_resc);

  DELETE FROM public.folha_rescisoes WHERE id = v_resc;
  DELETE FROM public.admissoes WHERE id = v_adm;
  RETURN v_out;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_dec13_062()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_ped jsonb; v_jc jsonb; v_dev numeric; v_avos int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Apurar o 13o de uma rescisao por PEDIDO DE DEMISSAO em agosto';
  r.esperado := '13o proporcional aos avos — so a justa causa afasta a gratificacao (Sumula 157 do TST)';
  v_ped := public.qa_caso_dec13_rescisao_motivo('PEDIDO_DEMISSAO', 8, 1.0, '90000005649', 'QA Pediu Demissao');
  v_jc  := public.qa_caso_dec13_rescisao_motivo('DISPENSA_COM_JUSTA_CAUSA', 8, 0.0, '90000005720', 'QA Justa Causa');
  v_dev := COALESCE((v_ped->>'devido')::numeric, -1);
  v_avos := COALESCE((v_ped->>'avos')::int, -1);

  IF v_dev <= 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o pedido de demissao ficou sem 13o proporcional (devido: R$ %s, '
             || '%s avos). A Sumula 157 do TST e o art. 3o da Lei 4.090/1962 garantem a '
             || 'gratificacao proporcional a quem pede demissao — so a justa causa a afasta. '
             || 'Reter verba devida e passivo direto.', v_dev, v_avos);
  ELSIF COALESCE((v_jc->>'devido')::numeric, -1) <> 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO ao contrario: a justa causa pagou R$ %s de 13o proporcional, '
             || 'quando a Lei 4.090/1962 a afasta.', (v_jc->>'devido'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Pedido de demissao manteve o 13o proporcional (%s avos, R$ %s) e a justa '
             || 'causa ficou em zero, como manda a lei.', v_avos, v_dev);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_dec13_063()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_out jsonb; v_dev numeric;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Apurar o 13o de uma rescisao por FALECIMENTO em setembro';
  r.esperado := '13o proporcional devido, para pagamento aos dependentes (Lei 6.858/1980)';
  v_out := public.qa_caso_dec13_rescisao_motivo('FALECIMENTO', 9, 1.0, '90000005800', 'QA Falecimento');
  v_dev := COALESCE((v_out->>'devido')::numeric, -1);

  IF v_dev <= 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o falecimento ficou sem 13o proporcional (R$ %s). A gratificacao '
             || 'continua devida e e paga aos dependentes habilitados na Previdencia, '
             || 'independentemente de inventario (Lei 6.858/1980, art. 1o; Lei 4.090/1962, art. '
             || '3o). Tratar falecimento como perda da verba e erro grave com a familia.', v_dev);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Falecimento manteve o 13o proporcional devido (%s avos, R$ %s), para '
             || 'encaminhamento aos dependentes (Lei 6.858/1980).', (v_out->>'avos'), v_dev);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_dec13_061()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_cr jsonb; v_sem jsonb; v_dev_cr numeric; v_dev_sem numeric;
  v_tipos text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Apurar o 13o de uma rescisao por CULPA RECIPROCA';
  r.esperado := 'Metade do 13o proporcional (CLT, art. 484; Sumula 14 do TST)';

  SELECT string_agg(DISTINCT e.enumlabel, ', ') INTO v_tipos
  FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
  WHERE t.typname LIKE '%rescisao%' AND e.enumlabel ILIKE '%RECIPROC%';

  BEGIN
    v_cr := public.qa_caso_dec13_rescisao_motivo('CULPA_RECIPROCA', 6, 0.5, '90000005991', 'QA Culpa Reciproca');
  EXCEPTION WHEN OTHERS THEN
    v_cr := jsonb_build_object('erro', SQLERRM);
  END;
  v_sem := public.qa_caso_dec13_rescisao_motivo('DISPENSA_SEM_JUSTA_CAUSA', 6, 1.0, '90000006025', 'QA Sem Justa Causa');

  v_dev_cr  := COALESCE((v_cr->>'devido')::numeric, -1);
  v_dev_sem := COALESCE((v_sem->>'devido')::numeric, -1);

  IF v_cr ? 'erro' THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a culpa reciproca nao existe como motivo de rescisao (%s). O art. '
             || '484 da CLT e a Sumula 14 do TST mandam pagar METADE das verbas da dispensa sem '
             || 'justa causa, o 13o proporcional incluido. Sem esse motivo, o operador acaba '
             || 'lancando como justa causa (paga zero, e devedor) ou como dispensa comum (paga '
             || 'inteiro, e perde dinheiro). Detalhe tecnico: %s',
             coalesce('motivos com "reciproca" no sistema: ' || v_tipos, 'nenhum motivo de culpa reciproca cadastrado'),
             (v_cr->>'erro'));
  ELSIF v_dev_sem <= 0 OR abs(v_dev_cr - round(v_dev_sem / 2, 2)) > 0.02 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a culpa reciproca pagou R$ %s, quando deveria pagar metade da '
             || 'dispensa sem justa causa (R$ %s / 2 = R$ %s) — CLT, art. 484 e Sumula 14 do TST.',
             v_dev_cr, v_dev_sem, round(v_dev_sem / 2, 2));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Culpa reciproca paga metade: R$ %s contra R$ %s da dispensa sem justa '
             || 'causa (Sumula 14 do TST).', v_dev_cr, v_dev_sem);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-022: Sumula 347 — media FISICA das horas extras ─────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_022()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_fn boolean; v_src text; v_param boolean; v_marca boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): existe media FISICA de horas extras no 13o?';
  r.esperado := 'Quantidade de horas do ano dividida pelos meses, multiplicada pelo valor da hora ATUAL (Sumula 347 do TST)';

  SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                  WHERE n.nspname='public' AND p.proname='decimo_terceiro_media_horas_extras')
    INTO v_fn;
  SELECT prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='decimo_terceiro_media_horas_extras';
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='decimo_terceiro_config'
                    AND column_name='media_horas_extras') INTO v_param;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='folha_rubricas'
                    AND column_name='he_do_ponto') INTO v_marca;

  IF NOT v_fn OR NOT v_param THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a media de horas extras do 13o nao e fisica (funcao: %s; escolha '
             || 'do criterio: %s). A Sumula 347 do TST manda somar a QUANTIDADE de horas extras '
             || 'do ano, dividir pelos meses e multiplicar pelo valor da hora VIGENTE. Usar a '
             || 'media dos valores pagos paga a menos sempre que houve aumento salarial no ano — '
             || 'e o aumento e a regra, nao a excecao.',
             CASE WHEN v_fn THEN 'existe' ELSE 'nao existe' END,
             CASE WHEN v_param THEN 'existe' ELSE 'nao existe' END);
  ELSIF v_src NOT ILIKE '%valor_hora%' AND v_src NOT ILIKE '%salario%' THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a funcao de media de horas extras existe, mas nao multiplica pelo valor '
             || 'da hora atual — sem isso ela nao cumpre a Sumula 347 do TST.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Media fisica implementada (decimo_terceiro_media_horas_extras), criterio '
             || 'escolhivel pela empresa e rubricas de HE do ponto marcadas: %s.',
             CASE WHEN v_marca THEN 'sim' ELSE 'marcador ausente' END);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-023: adicionais habituais integram a base ───────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_023()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_col text; v_fora text; v_total int; v_existentes int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Conferir se as rubricas de adicional habitual entram na base do 13o';
  r.esperado := 'Noturno, insalubridade e periculosidade marcados como integrantes (Sumulas 60, 132 e 139 do TST)';

  SELECT column_name INTO v_col FROM information_schema.columns
   WHERE table_schema='public' AND table_name='folha_rubricas'
     AND (column_name ILIKE '%13%' OR column_name ILIKE '%decimo%') LIMIT 1;

  IF v_col IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o cadastro de rubricas nao tem marcacao de "integra o 13o". Sem ela, '
             || 'nao ha como saber se adicional noturno, insalubridade e periculosidade entram '
             || 'na base — e eles entram, por habitualidade (Sumulas 60, 132 e 139 do TST).';
    RETURN r;
  END IF;

  EXECUTE format(
    'SELECT count(*) FROM public.folha_rubricas
      WHERE tipo = ''PROVENTO''
        AND (descricao ILIKE ''%%noturn%%'' OR descricao ILIKE ''%%insalubr%%''
             OR descricao ILIKE ''%%periculos%%'')') INTO v_existentes;

  IF COALESCE(v_existentes, 0) = 0 THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Nao ha rubrica de adicional noturno, insalubridade ou periculosidade cadastrada '
             || 'nesta base — nao ha o que conferir. O caso volta a valer assim que a empresa '
             || 'cadastrar esses adicionais, e ai eles precisam entrar na base do 13o (Sumulas '
             || '60, 132 e 139 do TST).';
    RETURN r;
  END IF;

  EXECUTE format(
    'SELECT count(*), string_agg(descricao, '', '') FROM public.folha_rubricas
      WHERE tipo = ''PROVENTO''
        AND (descricao ILIKE ''%%noturn%%'' OR descricao ILIKE ''%%insalubr%%''
             OR descricao ILIKE ''%%periculos%%'')
        AND COALESCE(%I, false) = false', v_col)
  INTO v_total, v_fora;

  IF v_total > 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: %s rubrica(s) de adicional habitual estao FORA da base do 13o '
             || '(%s). Adicional noturno (Sumula 60), de periculosidade (Sumula 132) e de '
             || 'insalubridade (Sumula 139) integram a remuneracao e, por habitualidade, a base '
             || 'do 13o. Fora da base, o 13o sai a menor sem ninguem perceber. Correcao: marcar '
             || 'essas rubricas como integrantes no cadastro.', v_total, v_fora);
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Nenhuma rubrica de adicional habitual ficou fora da base do 13o (marcador "'
             || v_col || '" no cadastro de rubricas).';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-034: as duas politicas do adiantamento ──────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_034()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_check text; v_opcoes text; v_le boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a empresa escolhe a base do adiantamento?';
  r.esperado := 'As duas leituras da Lei 4.749/1965, art. 2o, disponiveis e com efeito no calculo';

  SELECT pg_get_constraintdef(c.oid) INTO v_check
  FROM pg_constraint c
  WHERE c.conrelid = 'public.decimo_terceiro_config'::regclass AND c.contype = 'c'
    AND pg_get_constraintdef(c.oid) ILIKE '%adiantamento_base%';

  SELECT prosrc ILIKE '%adiantamento_base%' INTO v_le
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='decimo_terceiro_calcular';

  v_opcoes := coalesce(v_check, 'sem parametro');

  IF v_check IS NULL
     OR v_check NOT ILIKE '%remuneracao_mes_anterior%'
     OR v_check NOT ILIKE '%proporcional_apurado%' THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: nao ha escolha registrada da base do adiantamento (%s). A Lei '
             || '4.749/1965, art. 2o, manda adiantar metade do salario do mes anterior; a pratica '
             || 'consolidada admite metade do 13o apurado. As duas sao defensaveis, e por isso a '
             || 'escolha e da empresa — mas precisa ficar REGISTRADA e valer igual para todos no '
             || 'ano, senao cada calculo vira uma interpretacao.', v_opcoes);
  ELSIF NOT COALESCE(v_le, false) THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o parametro da politica do adiantamento existe, mas o calculo da parcela '
             || 'nao o le — escolha sem efeito e pior que escolha nenhuma, porque parece cumprida.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Politica do adiantamento registrada e lida pelo calculo (%s).', v_opcoes);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-035: pedido fora de janeiro e avisado ───────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_035()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_src text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o pedido fora de janeiro e sinalizado?';
  r.esperado := 'Aviso de pedido fora da janela do §2o do art. 2o da Lei 4.749/1965 — sem recusa silenciosa';

  SELECT prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='decimo_terceiro_adiantamento_nas_ferias';

  IF v_src IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nao existe rotina de adiantamento do 13o junto as ferias. O §2o do art. '
             || '2o da Lei 4.749/1965 da esse direito a quem requer em janeiro, e sem rotina o '
             || 'pedido se perde entre planilhas.';
  ELSIF v_src NOT ILIKE '%janeiro%' AND v_src NOT ILIKE '%fora_de_janeiro%' THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a rotina de adiantamento nas ferias nao distingue o pedido feito em '
             || 'JANEIRO dos demais. Fora da janela do §2o o empregador nao e obrigado a antecipar '
             || '— o sistema deve avisar e deixar a decisao registrada, nunca recusar em silencio '
             || 'nem pagar sem rastro.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'A rotina de adiantamento nas ferias separa os pedidos de janeiro e avisa sobre os '
             || 'que ficaram fora da janela do §2o (Lei 4.749/1965).';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-052: provisao do desligado e revertida ──────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_052()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_src text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a provisao reverte quando o vinculo termina?';
  r.esperado := 'Provisao do desligado revertida na competencia seguinte, e conciliacao fechando';

  SELECT prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='decimo_terceiro_provisionar';

  IF v_src IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nao ha provisao propria do 13o. Sem ela, a despesa aparece inteira em '
             || 'dezembro e o resultado dos outros onze meses sai distorcido (regime de '
             || 'competencia — Lei 6.404/1976, art. 177).';
  ELSIF v_src NOT ILIKE '%revert%' OR v_src NOT ILIKE '%desligad%' THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a provisao do 13o nao reverte a parcela de quem foi desligado. O 13o '
             || 'desses ja foi quitado na rescisao; manter a provisao deixa no balanco uma '
             || 'obrigacao que nao existe mais, e a conciliacao nunca fecha.';
  ELSIF v_src NOT ILIKE '%cpf%' THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a reversao da provisao nao casa o colaborador pelo CPF. O identificador '
             || 'livre de colaborador difere entre modulos, entao a reversao encontra zero linhas '
             || 'e falha em silencio — o pior tipo de erro contabil.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'A provisao do 13o reverte a parcela dos desligados, casando o vinculo pelo CPF.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-072: o lote nao duplica parcela ─────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_072()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_ten uuid := public.qa_sandbox_tenant_id();
  v_ano int := extract(year from CURRENT_DATE)::int - 1;
  v_cpf text := '90000006106'; v_adm uuid;
  v_r1 jsonb; v_r2 jsonb; v_vivas int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Processar o lote da 1a parcela e, em seguida, processar o MESMO lote de novo';
  r.esperado := 'A segunda passada nao cria parcela nova e informa quantos ja existiam';

  DELETE FROM public.folha_13_calculo WHERE tenant_id = v_ten AND ano = v_ano
     AND regexp_replace(coalesce(colaborador_cpf,''),'\D','','g') = v_cpf;
  DELETE FROM public.admissoes WHERE tenant_id = v_ten AND cpf = v_cpf;
  INSERT INTO public.admissoes (tenant_id, nome_completo, cpf, cargo, salario, data_admissao, status)
  VALUES (v_ten, 'QA Lote Duplo', v_cpf, 'QA', 2500, make_date(v_ano - 1, 3, 1), 'concluido')
  RETURNING id INTO v_adm;

  v_r1 := public.decimo_terceiro_lote(v_ten, v_ano, 1, NULL);
  v_r2 := public.decimo_terceiro_lote(v_ten, v_ano, 1, NULL);

  SELECT count(*) INTO v_vivas FROM public.folha_13_calculo
   WHERE tenant_id = v_ten AND ano = v_ano AND parcela = 1
     AND regexp_replace(coalesce(colaborador_cpf,''),'\D','','g') = v_cpf
     AND status <> 'cancelado';

  DELETE FROM public.folha_13_calculo WHERE tenant_id = v_ten AND ano = v_ano
     AND regexp_replace(coalesce(colaborador_cpf,''),'\D','','g') = v_cpf;
  DELETE FROM public.admissoes WHERE id = v_adm;

  IF v_vivas > 1 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: rodar o lote duas vezes criou %s parcelas vivas para o mesmo '
             || 'colaborador. O lote e clicado por gente sob pressao de prazo e sera clicado duas '
             || 'vezes — duplicar parcela vira pagamento em dobro. Retornos: %s / %s',
             v_vivas, v_r1, v_r2);
  ELSIF COALESCE((v_r2->>'ja_calculados')::int, (v_r2->>'ja_existiam')::int, 0) = 0
        AND COALESCE((v_r2->>'calculados')::int, 0) > 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a segunda passada nao duplicou, mas tambem nao informa que pulou '
             || 'ninguem (%s) — quem processa fica sem saber se o lote rodou. Retorno precisa '
             || 'dizer quantos foram calculados e quantos ja existiam.', v_r2);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Lote idempotente: uma unica parcela viva apos duas passadas; a segunda '
             || 'informou o que pulou (%s).', v_r2);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── Registro das rotinas no motor (código -> função) ──────────────────
INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
  ('DEC13-004','qa_caso_dec13_004',true), ('DEC13-005','qa_caso_dec13_005',true),
  ('DEC13-006','qa_caso_dec13_006',true), ('DEC13-022','qa_caso_dec13_022',true),
  ('DEC13-023','qa_caso_dec13_023',true), ('DEC13-034','qa_caso_dec13_034',true),
  ('DEC13-035','qa_caso_dec13_035',true), ('DEC13-043','qa_caso_dec13_043',true),
  ('DEC13-052','qa_caso_dec13_052',true), ('DEC13-061','qa_caso_dec13_061',true),
  ('DEC13-062','qa_caso_dec13_062',true), ('DEC13-063','qa_caso_dec13_063',true),
  ('DEC13-072','qa_caso_dec13_072',true), ('DEC13-073','qa_caso_dec13_073',true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;


-- ════════════════════════════════════════════════════════════════════
-- 8) Culpa reciproca: o motivo que faltava e a metade das verbas
-- ════════════════════════════════════════════════════════════════════
ALTER TYPE public.rescisao_tipo ADD VALUE IF NOT EXISTS 'CULPA_RECIPROCA';

-- ── 13º da rescisão: metade na culpa recíproca ────────────────────────
CREATE OR REPLACE FUNCTION public.decimo_terceiro_da_rescisao(
    p_rescisao UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    r         public.folha_rescisoes;
    v_ano     INT;
    v_ap      JSONB;
    v_avos    INT;
    v_base    NUMERIC(12,2);
    v_devido  NUMERIC(12,2);
    v_integral NUMERIC(12,2);
    v_pago    NUMERIC(12,2) := 0;
    v_perde   BOOLEAN := false;
    v_metade  BOOLEAN := false;
BEGIN
    SELECT * INTO r FROM public.folha_rescisoes WHERE id = p_rescisao;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('erro', 'Rescisão não encontrada.');
    END IF;

    v_ano    := extract(year FROM r.data_desligamento)::INT;
    v_perde  := (r.tipo_rescisao::text = 'DISPENSA_COM_JUSTA_CAUSA');
    v_metade := (r.tipo_rescisao::text = 'CULPA_RECIPROCA');

    v_ap   := public.decimo_terceiro_apurar(r.tenant_id, r.colaborador_cpf, v_ano, NULL, NULL);
    v_avos := COALESCE((v_ap->>'avos')::INT, 0);
    v_base := COALESCE((v_ap->>'base_integral')::NUMERIC, 0);

    v_integral := round(v_base * v_avos / 12.0, 2);
    v_devido := CASE WHEN v_perde  THEN 0
                     WHEN v_metade THEN round(v_integral / 2, 2)
                     ELSE v_integral END;

    -- Adiantamento já pago no ano (inclusive o das férias): abate.
    SELECT COALESCE(sum(c.total_liquido), 0) INTO v_pago
      FROM public.folha_13_calculo c
     WHERE c.tenant_id = r.tenant_id
       AND c.ano = v_ano
       AND c.status = 'pago'
       AND regexp_replace(COALESCE(c.colaborador_cpf,''), '[^0-9]', '', 'g')
           = regexp_replace(COALESCE(r.colaborador_cpf,''), '[^0-9]', '', 'g');

    RETURN jsonb_build_object(
        'rescisao_id',   r.id,
        'ano',           v_ano,
        'tipo_rescisao', r.tipo_rescisao,
        'perde_por_justa_causa', v_perde,
        'metade_por_culpa_reciproca', v_metade,
        'avos',          v_avos,
        'base',          v_base,
        'devido_integral', v_integral,
        'devido',        v_devido,
        'ja_pago_no_ano', v_pago,
        'a_pagar_na_rescisao', greatest(round(v_devido - v_pago, 2), 0),
        'a_descontar',   CASE WHEN v_pago > v_devido
                              THEN round(v_pago - v_devido, 2) ELSE 0 END,
        'fundamento', CASE
            WHEN v_perde
              THEN 'Justa causa: perde o 13o proporcional (Lei 4.090/1962).'
            WHEN v_metade
              THEN 'Culpa reciproca: metade do 13o proporcional (CLT, art. 484; Sumula 14 do TST). Integral seria R$ '
                   || to_char(v_integral, 'FM999999990.00') || '.'
            ELSE 'Rescisao no ano-base: 13o proporcional aos avos, deduzido o adiantamento ja pago.' END,
        'memoria', v_ap,
        'apurado_em', now());
END $fn$;

COMMENT ON FUNCTION public.decimo_terceiro_da_rescisao(UUID) IS
    'Apura o 13o proporcional que cabe numa rescisao pelo motivo (justa causa perde; culpa reciproca paga metade, CLT art. 484 e Sumula 14 do TST), deduz o adiantamento ja pago no ano e devolve a memoria.';

GRANT EXECUTE ON FUNCTION public.decimo_terceiro_da_rescisao(UUID) TO authenticated;

-- ── A trava passa a cobrir os dois jeitos de errar ────────────────────
CREATE OR REPLACE FUNCTION public.decimo_terceiro_rescisao_valida()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $tg$
DECLARE
    v_ap       JSONB;
    v_integral NUMERIC(12,2);
BEGIN
    -- Justa causa nao gera 13o proporcional (Lei 4.090/1962).
    IF NEW.tipo_rescisao::text = 'DISPENSA_COM_JUSTA_CAUSA'
       AND COALESCE(NEW.decimo_terceiro_proporcional, 0) > 0 THEN
        RAISE EXCEPTION 'Dispensa por justa causa não gera 13º proporcional (Lei 4.090/1962). Valor informado: R$ %. Se o caso for culpa recíproca, use o motivo "Culpa Recíproca", que paga metade (CLT, art. 484; Súmula 14 do TST).',
            to_char(NEW.decimo_terceiro_proporcional, 'FM999999990.00');
    END IF;

    -- Culpa reciproca paga METADE: o valor inteiro tambem e recusado,
    -- porque pagar a mais aqui e dinheiro que nao volta.
    IF NEW.tipo_rescisao::text = 'CULPA_RECIPROCA'
       AND COALESCE(NEW.decimo_terceiro_proporcional, 0) > 0
       AND NEW.colaborador_cpf IS NOT NULL THEN
        v_ap := public.decimo_terceiro_apurar(NEW.tenant_id, NEW.colaborador_cpf,
                    extract(year FROM NEW.data_desligamento)::INT, NULL, NULL);
        v_integral := round(COALESCE((v_ap->>'base_integral')::NUMERIC, 0)
                          * COALESCE((v_ap->>'avos')::INT, 0) / 12.0, 2);
        IF v_integral > 0
           AND NEW.decimo_terceiro_proporcional > round(v_integral / 2, 2) + 0.02 THEN
            RAISE EXCEPTION 'Culpa recíproca paga METADE do 13º proporcional (CLT, art. 484; Súmula 14 do TST): o devido é R$ % e foi informado R$ %.',
                to_char(round(v_integral / 2, 2), 'FM999999990.00'),
                to_char(NEW.decimo_terceiro_proporcional, 'FM999999990.00');
        END IF;
    END IF;

    RETURN NEW;
END $tg$;

COMMENT ON FUNCTION public.decimo_terceiro_rescisao_valida() IS
    'Recusa 13o proporcional na justa causa (Lei 4.090/1962) e valor acima da metade na culpa reciproca (CLT art. 484; Sumula 14 do TST).';


-- ════════════════════════════════════════════════════════════════════
-- 9) Documentacao de testes: 31 casos e as rotinas que os rodam
-- ════════════════════════════════════════════════════════════════════
-- ══════════ 1a leva: modulo e os 17 casos originais ══════════
-- O modulo pai precisa existir: em base que nunca recebeu a documentacao
-- de testes ele pode faltar, e ai o filho nao nasce e nada e documentado.
INSERT INTO public.qa_modulos (parent_id, label, path, prioridade_doc, status_doc)
SELECT NULL, 'Financeiro', 'financeiro', 1, 'em_andamento'
WHERE NOT EXISTS (SELECT 1 FROM public.qa_modulos WHERE path = 'financeiro');

-- Módulo próprio, filho de Financeiro (a tela é uma aba de Financeiro)
INSERT INTO public.qa_modulos (parent_id, label, path, prioridade_doc, status_doc)
SELECT m.id, '13º Salário', 'financeiro/decimo-terceiro', 1, 'em_andamento'
FROM public.qa_modulos m
WHERE m.path = 'financeiro'
ON CONFLICT (path) DO NOTHING;

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos
  WHERE path = 'financeiro/decimo-terceiro';
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo financeiro/decimo-terceiro nao pode ser criado nesta base — casos da 1a leva nao inseridos.';
    RETURN;
  END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  -- ══════════ A) APURAÇÃO DE AVOS ══════════

  (v_mod, 'DEC13-001', 'Avos apurados do vínculo: 1/12 por mês, fração de 15 dias conta',
   'feliz', 'alta', 'aprovado', 'e2e',
   'Lei 4.090/1962, art. 1º, §§1º e 2º',
   'O 13º é 1/12 da remuneração por mês de serviço do ano, e a fração igual ou superior a 15 dias conta como mês inteiro. Os avos devem sair da DATA DE ADMISSÃO do vínculo — não de um número digitado à mão. Admitido em 20 de maio: maio tem menos de 15 dias, não conta; junho a dezembro contam — 7 avos. Admitido em 10 de maio: maio conta — 8 avos.',
   'Vínculos fictícios admitidos em 10/05 e 20/05 do ano-base.',
   '[{"ordem":1,"acao":"Apurar o 13º do admitido em 10/05","resultado_esperado":"8 avos (maio conta — 22 dias trabalhados ≥ 15)"},
     {"ordem":2,"acao":"Apurar o 13º do admitido em 20/05","resultado_esperado":"7 avos (maio com menos de 15 dias não conta)"},
     {"ordem":3,"acao":"Conferir a origem do número de meses","resultado_esperado":"Calculado da data de admissão, não digitado livremente pelo operador"}]'::jsonb,
   'Avos nascem do vínculo e da regra dos 15 dias — nunca de digitação.',
   'Requisitos YE-DP-13-001: RN-001 / CA-001 / cenário "Admissão no ano" (seção 25). DIVERGÊNCIA VISÍVEL: calcular13 recebe mesesTrabalhados informado na tela (DecimoTerceiroTab) — sem apuração automática. Deve falhar e encaminhar.'),

  (v_mod, 'DEC13-002', 'Faltas injustificadas derrubam o avo do mês que fica com menos de 15 dias',
   'negativo', 'alta', 'aprovado', 'e2e',
   'Lei 4.090/1962, art. 1º, §1º (mês de serviço); tratamento consolidado das faltas injustificadas',
   'Mês em que as faltas INJUSTIFICADAS reduzem o trabalho para menos de 15 dias não gera avo. Faltas justificadas e afastamentos legais não entram nessa conta. A fonte é o Ponto — as ocorrências do módulo de jornada precisam refletir na apuração, senão o 13º sai maior do que o devido.',
   'Vínculo com 16 faltas injustificadas registradas no Ponto em um mesmo mês do ano-base.',
   '[{"ordem":1,"acao":"Apurar os avos do vínculo","resultado_esperado":"O mês com 16 faltas injustificadas NÃO conta como avo"},
     {"ordem":2,"acao":"Repetir com faltas justificadas (atestado)","resultado_esperado":"O mês conta normalmente — justificada não derruba avo"}]'::jsonb,
   'Injustificada demais no mês, avo a menos; justificada não mexe.',
   'Requisitos YE-DP-13-001: RN-001 / fluxo "Faltas injustificadas" (seção 9). Integração com Ponto/Afastamentos (seção 17).'),

  (v_mod, 'DEC13-003', 'Afastamentos: maternidade integra, auxílio-doença divide com o INSS',
   'alternativo', 'alta', 'aprovado', 'e2e',
   'Lei 8.213/1991 (abono anual, art. 120 do Decreto 3.048/1999); salário-maternidade integra a apuração patronal',
   'Afastamentos não são todos iguais: na licença-maternidade o período INTEGRA a apuração do empregador; no auxílio-doença, o empregador paga os avos trabalhados e o INSS paga o abono anual proporcional ao benefício. O sistema deve tratar cada tipo pelo seu efeito e marcar o caso para validação contábil — não apagar nem contar tudo igual.',
   'Vínculos fictícios com licença-maternidade (4 meses) e auxílio-doença (5 meses) no ano-base.',
   '[{"ordem":1,"acao":"Apurar o 13º da colaboradora em licença-maternidade","resultado_esperado":"Período da licença conta na apuração patronal"},
     {"ordem":2,"acao":"Apurar o 13º do afastado por auxílio-doença","resultado_esperado":"Avos patronais só dos meses trabalhados; período do benefício sinalizado como abono anual do INSS"},
     {"ordem":3,"acao":"Conferir a marcação do caso","resultado_esperado":"Apuração marcada para validação contábil, com o tipo de afastamento visível"}]'::jsonb,
   'Cada afastamento com seu efeito — e contabilidade avisada.',
   'Requisitos YE-DP-13-001: RN-008 / CA (seção 24) / cenário "Afastamento" (seção 25). Classificação [OLC]/[VAL] — a divisão exata patronal×INSS é ponto de validação (seção 30). Integra com jornada-rotina/afastamentos.'),

  -- ══════════ B) BASE DE CÁLCULO E MÉDIAS ══════════

  (v_mod, 'DEC13-020', 'Base do 13º inclui as médias das variáveis do ano',
   'feliz', 'alta', 'aprovado', 'e2e',
   'Decreto 57.155/1965, art. 2º; Súmulas 45, 148 e 253 do TST',
   'Quem recebe horas extras habituais, adicional noturno ou comissões não tem 13º só do salário fixo: as variáveis do ano entram na base pela média, conforme a parametrização de rubricas. Base composta apenas do fixo, para quem tem variável habitual, é diferença certa em reclamação.',
   'Vínculo com salário fixo e horas extras habituais lançadas na folha ao longo do ano-base.',
   '[{"ordem":1,"acao":"Calcular o 13º do vínculo com variáveis","resultado_esperado":"Base = salário + média das variáveis, com memória de cálculo mostrando a composição"},
     {"ordem":2,"acao":"Conferir as rubricas que integraram","resultado_esperado":"Somente rubricas parametrizadas como integrantes da base do 13º"}]'::jsonb,
   'Variável habitual entra pela média — e a memória mostra o caminho.',
   'Requisitos YE-DP-13-001: RN-002 / CA-002. Composição exata da base é [VAL]/[DAE] por cliente (seção 30); o que se testa é que a média EXISTE e é parametrizável (folha_rubricas).'),

  (v_mod, 'DEC13-021', 'Base de médias incompleta trava com alerta antes do fechamento',
   'excecao', 'media', 'aprovado', 'api',
   'Documento YE-DP-13-001, RF-006 e seção 14 (alerta "Base de médias incompleta")',
   'Fechar o 13º com rubricas variáveis do ano faltando é pagar errado com hora marcada. Antes do fechamento, o sistema confere se as competências do ano têm as variáveis lançadas; faltando, alerta o DP e aponta o que completar — o fechamento com pendência exige decisão consciente, não passa em silêncio.',
   'Ano-base com competências sem lançamento de rubricas variáveis para vínculo que as recebe habitualmente.',
   '[{"ordem":1,"acao":"Preparar o fechamento do 13º","resultado_esperado":"Alerta de base incompleta com as competências/rubricas faltantes"},
     {"ordem":2,"acao":"Completar os lançamentos e reprocessar","resultado_esperado":"Alerta encerrado; médias recalculadas"}]'::jsonb,
   'Média só fecha com o ano inteiro na mesa.',
   'Requisitos YE-DP-13-001: seção 14 / cenário "Dado ausente" (seção 25) / IA "Detecção de médias incompletas" (seção 18).'),

  -- ══════════ C) PARCELAS E PRAZOS ══════════

  (v_mod, 'DEC13-030', '1ª parcela: 50%, paga entre 1º de fevereiro e 30 de novembro',
   'feliz', 'critica', 'aprovado', 'api',
   'Lei 4.749/1965, art. 2º',
   'O adiantamento é METADE da remuneração do mês anterior, pago entre 1º/02 e 30/11. O sistema agenda a data-alvo, alerta na aproximação (D-30/15/7) e acusa o atraso — 1ª parcela paga em dezembro é infração, ainda que o valor esteja certo. FGTS incide sobre o adiantamento na competência do pagamento.',
   'Ano-base com vínculos ativos e calendário carregado.',
   '[{"ordem":1,"acao":"Programar a 1ª parcela dentro do prazo","resultado_esperado":"50% da base, agendada até 30/11, com FGTS da competência"},
     {"ordem":2,"acao":"Aproximar-se de 30/11 sem pagamento","resultado_esperado":"Alertas D-30/15/7 para DP/RH/Financeiro, com ação no Plano de Ação"},
     {"ordem":3,"acao":"Simular data de pagamento em dezembro","resultado_esperado":"Acusado como fora do prazo legal — não passa como regular"}]'::jsonb,
   'Metade do valor, dentro da janela legal, com o prazo vigiado.',
   'Requisitos YE-DP-13-001: RN-003 / CA-003 / alerta "1ª parcela a vencer" (seção 14). DIVERGÊNCIA VISÍVEL: não há motor de prazos nem alertas do 13º hoje. Deve falhar e encaminhar.'),

  (v_mod, 'DEC13-031', '2ª parcela até 20 de dezembro, antecipando em fim de semana ou feriado',
   'feliz', 'critica', 'aprovado', 'api',
   'Lei 4.749/1965, art. 1º; regra de antecipação por dia não útil',
   'A 2ª parcela vence em 20/12 — e quando o dia 20 cai em sábado, domingo ou feriado, paga-se ANTES, não depois. O motor de datas precisa conhecer o calendário (tabela de feriados) e mover a data-alvo para o dia útil anterior, refletindo isso nos alertas (D-15/7/3).',
   'Ano em que 20/12 cai em fim de semana; tabela de feriados carregada.',
   '[{"ordem":1,"acao":"Consultar a data-alvo da 2ª parcela nesse ano","resultado_esperado":"Antecipada para o último dia útil antes de 20/12"},
     {"ordem":2,"acao":"Conferir os alertas","resultado_esperado":"D-15/7/3 contados sobre a data antecipada, prioridade crítica"}]'::jsonb,
   'O prazo corre para trás no calendário, nunca para frente.',
   'Requisitos YE-DP-13-001: RN-004 / CA-004 / cenário "Prazo vencido" (seção 25) / RNF-003. Usa a tabela feriados já existente no projeto.'),

  (v_mod, 'DEC13-032', 'Adiantamento nas férias: requerido em janeiro, pago no gozo, baixado na apuração',
   'alternativo', 'media', 'aprovado', 'e2e',
   'Lei 4.749/1965, art. 2º, §2º',
   'Quem requer em janeiro recebe a 1ª parcela junto das férias. O lado Férias já tem caso (FERIAS-035); aqui se testa o lado 13º: a opção registrada muda a data do adiantamento para o gozo, o valor pago nas férias aparece na apuração anual como adiantamento JÁ FEITO e a 2ª parcela deduz exatamente esse valor — sem pagar de novo em novembro.',
   'Vínculo com adiantar_13 = true requerido em janeiro e férias gozadas em julho, com a 1ª parcela paga junto.',
   '[{"ordem":1,"acao":"Consultar a apuração do 13º do vínculo","resultado_esperado":"Adiantamento marcado como pago nas férias, com valor e data"},
     {"ordem":2,"acao":"Programar a rodada geral de novembro","resultado_esperado":"Vínculo fora da rodada da 1ª parcela — já recebeu"},
     {"ordem":3,"acao":"Calcular a 2ª parcela","resultado_esperado":"Deduzido o valor pago nas férias, não os 50% teóricos"}]'::jsonb,
   'Pagou nas férias, baixou na apuração, deduziu na 2ª — uma vez só.',
   'Requisitos YE-DP-13-001: RN-003 / CA-003 / cenário "Adiantamento nas férias" (seção 9). Par do FERIAS-035 (lado Férias). Política de adiantamento é [DAE] (seção 30).'),

  (v_mod, 'DEC13-033', '2ª parcela deduz o adiantamento e diferenças posteriores geram complemento',
   'alternativo', 'alta', 'aprovado', 'e2e',
   'Lei 4.749/1965, arts. 1º e 2º; Decreto 57.155/1965 (recálculo com variáveis do ano)',
   'A 2ª parcela é o total anual MENOS o adiantamento efetivamente pago. E o ano não acaba em 20/12: variável lançada depois (comissão de dezembro, HE do fim do ano) gera DIFERENÇA a apurar como complemento, com trilha própria e reflexo no eSocial — não se reabre o valor pago fingindo que nada mudou.',
   '1ª parcela paga; variável nova lançada após o pagamento da 2ª.',
   '[{"ordem":1,"acao":"Calcular a 2ª parcela","resultado_esperado":"Total anual menos o adiantamento real, com memória de cálculo"},
     {"ordem":2,"acao":"Lançar variável retroativa do ano","resultado_esperado":"Diferença detectada e alerta a DP/Contador"},
     {"ordem":3,"acao":"Apurar o complemento","resultado_esperado":"Complemento com trilha vinculada à apuração original e reflexo no eSocial"}]'::jsonb,
   'Deduz o que foi pago; o que chegar depois vira complemento rastreado.',
   'Requisitos YE-DP-13-001: CA-005 / RF-006 / cenário "Diferença" (seção 25) / alerta "Diferença após a 2ª parcela" (seção 14).'),

  -- ══════════ D) ENCARGOS ══════════

  (v_mod, 'DEC13-040', 'INSS do 13º: só na 2ª parcela, calculado em separado da folha do mês',
   'feliz', 'critica', 'aprovado', 'e2e',
   'Lei 8.212/1991; Decreto 3.048/1999, art. 214, §6º (cálculo em separado); retenção na quitação da 2ª parcela',
   'O INSS incide sobre o 13º INTEIRO, mas só é retido na 2ª parcela — e a base do 13º é tributada SEPARADA da remuneração de dezembro, cada uma com sua progressão de faixas. Somar as duas bases numa conta só infla a alíquota e desconta INSS a mais do colaborador.',
   'Vínculo com salário que, somado ao 13º, mudaria de faixa se as bases fossem somadas.',
   '[{"ordem":1,"acao":"Calcular a 1ª parcela","resultado_esperado":"Nenhum INSS retido no adiantamento"},
     {"ordem":2,"acao":"Calcular a 2ª parcela","resultado_esperado":"INSS sobre o 13º integral, com progressão de faixas própria, separada da folha de dezembro"},
     {"ordem":3,"acao":"Conferir a tabela aplicada","resultado_esperado":"Tabela de INSS vigente na competência (tabela versionada), não fixa em código"}]'::jsonb,
   'Base do 13º anda sozinha na tabela — e só paga na 2ª.',
   'Requisitos YE-DP-13-001: RN-005 / CA-004. Usa folha_tabelas_inss (versionada — RNF-002). Tabelas vigentes são [VAL] (seção 30).'),

  (v_mod, 'DEC13-041', 'IRRF do 13º: tributação exclusiva na fonte, apurada na 2ª parcela',
   'feliz', 'critica', 'aprovado', 'e2e',
   'RIR/2018 (Decreto 9.580/2018), art. 700 — tributação exclusiva na fonte do 13º salário',
   'O IRRF do 13º é EXCLUSIVO na fonte: apurado sobre o valor integral na quitação da 2ª parcela, com as deduções legais (dependentes, INSS do próprio 13º), e NÃO se soma aos rendimentos do mês para reajustar a tabela. Misturar o 13º com o salário de dezembro no IRRF é erro clássico que muda o imposto dos dois.',
   'Vínculo com dependentes cadastrados e 13º na faixa tributável.',
   '[{"ordem":1,"acao":"Calcular a 1ª parcela","resultado_esperado":"Nenhum IRRF no adiantamento"},
     {"ordem":2,"acao":"Calcular a 2ª parcela","resultado_esperado":"IRRF sobre o 13º integral, deduzindo INSS do 13º e dependentes, separado do IRRF do salário"},
     {"ordem":3,"acao":"Conferir o caráter exclusivo","resultado_esperado":"Valor não compensável/somável com a tributação mensal; tabela vigente versionada"}]'::jsonb,
   'Imposto do 13º nasce e morre na 2ª parcela, sem contaminar o mês.',
   'Requisitos YE-DP-13-001: RN-007 / CA-004. Usa folha_tabelas_irrf (versionada). Tabela anual e deduções são [VAL] (seção 30).'),

  (v_mod, 'DEC13-042', 'FGTS de 8% nas duas parcelas, cada uma na sua competência',
   'feliz', 'alta', 'aprovado', 'e2e',
   'Lei 8.036/1990, art. 15 (a remuneração inclui a gratificação de Natal)',
   'O FGTS incide sobre AMBAS as parcelas — 8% sobre o adiantamento na competência em que foi pago e 8% sobre o restante na competência da 2ª parcela. Depositar tudo em dezembro, ou esquecer o depósito do adiantamento, deixa diferença de FGTS que o FGTS Digital denuncia.',
   '1ª parcela paga em novembro; 2ª em dezembro.',
   '[{"ordem":1,"acao":"Conferir o FGTS da 1ª parcela","resultado_esperado":"8% sobre os 50% pagos, na competência de novembro"},
     {"ordem":2,"acao":"Conferir o FGTS da 2ª parcela","resultado_esperado":"8% sobre a diferença (total menos adiantamento), na competência de dezembro"},
     {"ordem":3,"acao":"Somar as duas competências","resultado_esperado":"8% exatos sobre o 13º integral — sem falta nem duplicidade"}]'::jsonb,
   'Oito por cento no total, repartidos pela competência de cada parcela.',
   'Requisitos YE-DP-13-001: RN-006 / CA-004. calcular13 já reparte a base (1ª: metade; 2ª: diferença) — o que falta conferir é o registro por competência para a guia. Alíquota parametrizada por vínculo (aprendiz 2%).'),

  -- ══════════ E) RESCISÃO NO ANO ══════════

  (v_mod, 'DEC13-060', 'Rescisão no ano-base: 13º proporcional pago, justa causa perde, adiantamento concilia',
   'alternativo', 'alta', 'aprovado', 'e2e',
   'Lei 4.090/1962, art. 3º; CLT, art. 477; justa causa afasta a gratificação proporcional',
   'Desligado no meio do ano, o colaborador leva o 13º proporcional aos avos trabalhados (indenizado na rescisão); na dispensa POR JUSTA CAUSA, perde a proporcional. E se a 1ª parcela já tinha sido paga (inclusive nas férias), o valor adiantado é conciliado nas verbas — na justa causa, o adiantado a maior vira desconto conforme a regra.',
   'Vínculos fictícios desligados em agosto: um sem justa causa (com adiantamento pago), outro por justa causa.',
   '[{"ordem":1,"acao":"Processar a rescisão sem justa causa","resultado_esperado":"13º proporcional (8/12) nas verbas, deduzido o adiantamento pago"},
     {"ordem":2,"acao":"Processar a rescisão por justa causa","resultado_esperado":"13º proporcional zerado, com a base legal citada"},
     {"ordem":3,"acao":"Conferir a conciliação na apuração anual","resultado_esperado":"Vínculo desligado fora da rodada de novembro/dezembro — quitado na rescisão"}]'::jsonb,
   'Proporcional na rescisão, nada na justa causa, adiantamento nunca em dobro.',
   'Requisitos YE-DP-13-001: RN-009 / CA-006 / cenário "Rescisão" (seção 25). A família DESL cobre as verbas em geral (culpa recíproca 50% = DESL-035); aqui se testa a CONCILIAÇÃO com o módulo do 13º.'),

  -- ══════════ F) eSOCIAL E PROVISÃO ══════════

  (v_mod, 'DEC13-050', 'eSocial do 13º: S-1200 da folha anual e S-1210 dos pagamentos, sem duplicar',
   'excecao', 'alta', 'aprovado', 'api',
   'eSocial — S-1200 (apuração anual do 13º) e S-1210 (pagamentos); regras de retificação',
   'O 13º tem folha PRÓPRIA no eSocial: apuração anual via S-1200 e pagamentos das parcelas via S-1210, no leiaute vigente. Rejeição volta traduzida (o que houve, onde corrigir) e o reenvio retifica — nunca cria segundo evento da mesma competência anual. Sem esses eventos, o 13º pago não existe para o governo.',
   'Apuração e pagamentos do 13º concluídos no ambiente de teste.',
   '[{"ordem":1,"acao":"Fechar a apuração anual","resultado_esperado":"S-1200 anual gerado no leiaute vigente"},
     {"ordem":2,"acao":"Registrar os pagamentos das parcelas","resultado_esperado":"S-1210 correspondente, valores conciliados com as parcelas"},
     {"ordem":3,"acao":"Simular rejeição e reenviar","resultado_esperado":"Retorno traduzido, ação sugerida, reenvio como retificação — sem evento duplicado"}]'::jsonb,
   'Folha anual declarada, pagamentos casados, rejeição virando retificação.',
   'Requisitos YE-DP-13-001: RN-010 / CA-007 / cenário "Com erro" (seção 25). DIVERGÊNCIA VISÍVEL: não há geração de S-1200/S-1210 hoje. Deve falhar e encaminhar. Mesma disciplina de ADM-093 e FERIAS-081.'),

  (v_mod, 'DEC13-051', 'Provisão do 13º atualizada a cada competência e conciliável com a folha',
   'feliz', 'media', 'aprovado', 'api',
   'Documento YE-DP-13-001, CA-009 e RNF-007; regime de competência contábil',
   'O custo do 13º nasce mês a mês (1/12 + encargos por competência), não em dezembro. A provisão acompanha cada fato gerador — admissões, desligamentos e reajustes mexem nela — e o contador consegue conciliar o saldo provisionado com o efetivamente pago no fim do ano, com relatório exportável.',
   'Ano-base com admissões e um desligamento no meio do ano.',
   '[{"ordem":1,"acao":"Conferir a provisão após cada competência","resultado_esperado":"Saldo cresce 1/12 + encargos por vínculo ativo; ajusta em admissão/desligamento"},
     {"ordem":2,"acao":"Pagar as parcelas","resultado_esperado":"Provisão baixada contra os pagamentos"},
     {"ordem":3,"acao":"Exportar o relatório de provisão","resultado_esperado":"Saldo conciliável com a folha e com o pago, por estabelecimento"}]'::jsonb,
   'Provisão viva o ano inteiro — dezembro só confirma o que já estava contado.',
   'Requisitos YE-DP-13-001: CA-009 / seção 20 / alerta "Provisão desatualizada" (seção 14). Existe folha_provisoes genérica; o vínculo específico com o 13º é o que se testa. Regras de conciliação são [DAE]/[VAL] (seção 30).'),

  -- ══════════ G) FLUXO, REABERTURA E ACESSO ══════════

  (v_mod, 'DEC13-070', 'Cálculo fechado do 13º só reabre com dupla aprovação e diferença rastreada',
   'excecao', 'alta', 'aprovado', 'api',
   'Documento YE-DP-13-001, RF-007; RNF-004 (trilha imutável)',
   'Corrigir 13º já fechado e pago não é editar o registro: é REABRIR com motivo, dupla aprovação, recálculo e apuração da diferença (complemento ou estorno), preservando a versão original na trilha. Alteração silenciosa em valor pago é exatamente o que a auditoria trabalhista procura.',
   'Cálculo de 13º fechado e pago no ambiente de teste.',
   '[{"ordem":1,"acao":"Tentar editar diretamente o cálculo fechado","resultado_esperado":"Bloqueado — só via reabertura formal"},
     {"ordem":2,"acao":"Reabrir com motivo e dupla aprovação","resultado_esperado":"Recálculo executado; diferença apurada como complemento/estorno"},
     {"ordem":3,"acao":"Conferir a trilha","resultado_esperado":"Versão original preservada; quem, quando, por quê e a diferença encadeados"}]'::jsonb,
   'Fechado não se edita: reabre com rito ou não muda.',
   'Requisitos YE-DP-13-001: RF-007 / cenário "Alteração retroativa" (seção 25). Mesma disciplina de FERIAS-054 (reabertura de férias).'),

  (v_mod, 'DEC13-071', 'Remuneração do 13º restrita por perfil: colaborador só vê o próprio',
   'negativo', 'alta', 'aprovado', 'api',
   'LGPD (Lei 13.709/2018), arts. 6º, VII e 46 — segurança e acesso mínimo; matriz de perfis do documento (seção 6)',
   'Valores de 13º são dado de remuneração: o colaborador consulta SÓ o próprio cálculo e recibo; a folha da equipe/empresa fica com DP, RH, financeiro e contador conforme a matriz de perfis, sempre dentro do tenant. Vazamento horizontal de remuneração entre colegas é incidente LGPD, não bug estético.',
   'Colaborador comum autenticado no tenant de teste; cálculos de 13º de vários vínculos existentes.',
   '[{"ordem":1,"acao":"Colaborador consulta o próprio 13º","resultado_esperado":"Permitido — parcelas e recibo próprios"},
     {"ordem":2,"acao":"Colaborador tenta ler o cálculo de um colega","resultado_esperado":"Bloqueado pela política de acesso (RLS)"},
     {"ordem":3,"acao":"Usuário de outro tenant tenta ler qualquer cálculo","resultado_esperado":"Bloqueado — segregação por empresa"}]'::jsonb,
   'Cada um vê o seu; a folha inteira é assunto de quem opera a folha.',
   'Requisitos YE-DP-13-001: seção 6 / seção 22 / cenário "Permissões insuficientes" (seção 25). A tabela folha_13_calculo é sensível: conferir cobertura da camada perfil_restringe_leitura_* (rotina PERFIL-003) ou exceção documentada.')

  ON CONFLICT (codigo) DO NOTHING;

  -- ---------------------------------------------------------
  -- Referências cruzadas em casos de outras famílias
  -- (só acrescenta às observações, não reescreve)
  -- ---------------------------------------------------------
  UPDATE public.qa_casos_teste SET observacoes = observacoes ||
    ' Requisitos YE-DP-13-001: o lado 13º do adiantamento nas férias ganhou caso próprio (DEC13-032 — baixa na apuração e dedução na 2ª parcela).'
  WHERE codigo = 'FERIAS-035' AND position('YE-DP-13-001' IN observacoes) = 0;

  UPDATE public.qa_casos_teste SET observacoes = observacoes ||
    ' Requisitos YE-DP-13-001: a conciliação do 13º na rescisão (adiantamento pago, rodada anual) ganhou caso próprio (DEC13-060).'
  WHERE codigo = 'DESL-035' AND position('YE-DP-13-001' IN observacoes) = 0;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE '13º Salário: % casos antes, % depois (esperado +17 na primeira execução).', v_antes, v_depois;
END $doc$;

-- ══════════ 1a leva: rotinas ══════════
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_aceitou_15m boolean := false; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Gravar cálculo de 13º com 15 meses trabalhados (impossível — o ano tem 12)';
  r.esperado := 'Recusado — avos vão de 0 a 12 e deveriam sair da data de admissão, não de digitação';
  BEGIN
    INSERT INTO public.folha_13_calculo
      (tenant_id, ano, colaborador_id, colaborador_nome, meses_trabalhados)
    VALUES (public.qa_sandbox_tenant_id(), extract(year from CURRENT_DATE)::int,
            'qa-dec13-001', 'QA Avos Quinze', 15);
    v_aceitou_15m := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_aceitou_15m := false; END;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA (somente leitura): alguém apura os avos a partir da admissão?';
  r.esperado := 'Função que calcule 1/12 por mês com a fração de 15 dias (Lei 4.090, art. 1º)';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%avos%'
         OR (p.prosrc ILIKE '%meses_trabalhados%' AND p.prosrc ILIKE '%data_admissao%'));

  IF v_aceitou_15m OR v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: os avos do 13º são um número DIGITADO — a tela (DecimoTerceiroTab) '
             || 'pede "meses trabalhados" e o banco aceitou até 15 meses (%s; folha_13_calculo não '
             || 'tem CHECK em meses_trabalhados) e nenhuma função apura os avos da data de '
             || 'admissão (%s). A Lei 4.090 manda contar 1/12 por mês com fração ≥ 15 dias: '
             || 'admitido em 10/05 são 8 avos, em 20/05 são 7 — diferença que hoje depende da '
             || 'conta de cabeça do operador. Correção: CHECK meses_trabalhados BETWEEN 0 AND 12 '
             || 'e apuração automática pela admissão (com faltas/afastamentos), digitação só como '
             || 'exceção justificada.',
             CASE WHEN v_aceitou_15m THEN '15 aceito' ELSE 'recusado' END,
             coalesce('há candidatas: ' || v_fns, 'nenhuma função'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Avos limitados e apurados por: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-002 — faltas injustificadas derrubam o avo do mês (< 15 dias)
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): as faltas do Ponto chegam à apuração do 13º?';
  r.esperado := 'Mês reduzido a menos de 15 dias por falta INJUSTIFICADA não conta avo; justificada não interfere';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  -- exige menção explícita ao 13º: "falta + avos" solto pega as férias
  -- (ferias_recalcular_periodo aplica o art. 130 e não toca o 13º)
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%falta%'
    AND (p.prosrc ILIKE '%decimo%' OR p.prosrc ILIKE '%13_calculo%');
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nenhuma função liga as faltas apuradas no Ponto ao 13º — o módulo de '
             || 'jornada materializa faltas dia a dia (ponto_diario) e o 13º nem olha. Um '
             || 'colaborador com 16 faltas injustificadas num mês deveria perder aquele avo '
             || '(mês de serviço exige ≥ 15 dias trabalhados, Lei 4.090 art. 1º §1º); hoje o '
             || '13º sai integral porque os meses são digitados (ver DEC13-001). O efeito '
             || 'perverso é o inverso também: falta JUSTIFICADA não pode derrubar avo, e sem '
             || 'regra nenhuma ninguém garante os dois lados. Correção: apuração de avos '
             || 'consumindo as ocorrências do Ponto, distinguindo justificada de injustificada.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Faltas refletem na apuração via: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-003 — afastamentos: maternidade integra, auxílio-doença divide com o INSS
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_fns text; v_tab text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): os afastamentos entram na apuração do 13º com o efeito de cada tipo?';
  r.esperado := 'Maternidade conta na apuração patronal; auxílio-doença gera abono anual pelo INSS no período do benefício';
  v_tab := public.qa_col_existe('afastamentos', 'tipo%');
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%afastamento%'
    AND (p.prosrc ILIKE '%decimo%' OR p.prosrc ILIKE '%13_calculo%' OR p.prosrc ILIKE '%avos%');
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o módulo de afastamentos existe e é tipado (%s), mas nenhuma '
             || 'função o consulta ao apurar o 13º. Os efeitos são opostos por tipo: '
             || 'licença-maternidade INTEGRA a apuração patronal; auxílio-doença divide — '
             || 'empregador paga os avos trabalhados e o INSS paga o abono anual do período de '
             || 'benefício (Decreto 3.048, art. 120). Sem o cruzamento, ou a empresa paga 13º '
             || 'de período que é do INSS (paga a mais) ou corta período de maternidade (paga '
             || 'a menos e responde por isso). Correção: apuração por tipo de afastamento, com '
             || 'marcação para validação contábil [VAL] nos casos divididos.',
             coalesce(v_tab, 'tabela afastamentos'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Afastamentos tratados na apuração via: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-020 — base com médias das variáveis (Decreto 57.155; Súmulas 45/148/253)
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_020()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_flag text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a marcação incide_13 das rubricas alimenta alguma média?';
  r.esperado := 'Rubricas com incide_13 = true compõem a média das variáveis na base do 13º';
  v_flag := public.qa_col_existe('folha_rubricas', 'incide_13');
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%incide_13%';
  IF v_flag IS NOT NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO (metade boa, metade decorativa): a parametrização EXISTE — '
             || 'folha_rubricas.incide_13 diz exatamente quais rubricas compõem a base do 13º, '
             || 'o desenho certo do Decreto 57.155 — mas NENHUMA função a consulta: a "média de '
             || 'variáveis" do cálculo é um único número digitado na tela (media_variaveis), '
             || 'sem memória de qual rubrica entrou nem de que período. Horas extras habituais, '
             || 'adicional noturno e comissões integram a base por lei (Súmulas 45/148/253) e '
             || 'hoje dependem de o operador calcular a média fora do sistema. Correção: média '
             || 'automática dos lançamentos do ano filtrados por incide_13, com a composição '
             || 'gravada na memória de cálculo.';
  ELSIF v_flag IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'O campo incide_13 não existe mais em folha_rubricas.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Médias calculadas a partir de incide_13 em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-021 — base de médias incompleta alerta antes do fechamento
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_021()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): algum motor confere a completude do ano antes do fechamento?';
  r.esperado := 'Competência sem variáveis lançadas gera alerta ANTES do cálculo, não diferença depois';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%folha_alertas_prazo%';
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a tabela de alertas da folha (folha_alertas_prazo) é alimentada só '
             || 'pela TELA — nenhuma função do banco gera ou confere alerta algum, e não '
             || 'existe verificação de base incompleta em lugar nenhum. Quem não abrir a aba '
             || 'de alertas no mês certo não é avisado de nada, e um 13º calculado com '
             || 'competências sem variáveis lançadas sai menor em silêncio — diferença que '
             || 'vira passivo (seção 14 do documento pede alerta de "base de médias '
             || 'incompleta" com prioridade média antes do fechamento). Correção: rotina '
             || 'agendada (pg_cron, como as demais do projeto) conferindo lançamentos do '
             || 'ano × vínculos com variável habitual e registrando o alerta.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Alertas gerados/conferidos no banco por: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-030 — 1ª parcela: 50% entre 1º/02 e 30/11 (Lei 4.749)
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_030()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_check text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o prazo legal do 13º tem lugar no controle de prazos da folha?';
  r.esperado := 'Tipos de alerta contemplando as parcelas do 13º (1ª até 30/11; 2ª até 20/12)';
  SELECT pg_get_constraintdef(c.oid) INTO v_check
  FROM pg_constraint c
  WHERE c.conrelid = 'public.folha_alertas_prazo'::regclass
    AND c.contype = 'c' AND pg_get_constraintdef(c.oid) ILIKE '%tipo%';
  IF v_check IS NULL OR (v_check NOT ILIKE '%13%' AND v_check NOT ILIKE '%decimo%') THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o controle de prazos da folha não conhece o 13º — o CHECK de '
             || 'folha_alertas_prazo só admite tipos mensais (%s): não há onde registrar '
             || '"1ª parcela até 30/11" nem "2ª até 20/12", e a tela que semeia os alertas '
             || 'gera datas aproximadas mês a mês, nunca as datas da Lei 4.749. Pagar a 1ª '
             || 'parcela fora da janela (1º/02 a 30/11) é infração mesmo com o valor certo, '
             || 'e é o risco nº 1 do módulo (seção 26). Correção: tipos decimo_primeira e '
             || 'decimo_segunda no CHECK + semeadura anual das duas datas com alertas '
             || 'D-30/15/7 e D-15/7/3.', coalesce(v_check, 'constraint ausente'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Prazos do 13º contemplados no controle: %s.', v_check);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-031 — 2ª parcela até 20/12 com antecipação por dia não útil
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_031()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_feriados text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): existe motor de datas que antecipe prazo em dia não útil?';
  r.esperado := '20/12 em fim de semana/feriado desloca a data-alvo para o dia útil ANTERIOR';
  v_feriados := CASE WHEN to_regclass('public.feriados') IS NOT NULL THEN 'feriados' END;
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%feriado%'
    AND (p.prosrc ILIKE '%util%' OR p.prosrc ILIKE '%antecip%')
    AND (p.prosrc ILIKE '%folha%' OR p.prosrc ILIKE '%decimo%' OR p.prosrc ILIKE '%prazo%');
  IF v_feriados IS NOT NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o calendário EXISTE (tabela feriados, nacional e por município) e '
             || 'nenhum motor de prazos da folha o consulta — não há função que desloque uma '
             || 'data-alvo para o dia útil anterior. O prazo do 13º anda sempre para TRÁS '
             || '(20/12 no sábado paga-se na sexta 19; pagar na segunda 22 é atraso com multa), '
             || 'diferente de prazos tributários que às vezes prorrogam — por isso a regra '
             || 'precisa ser do prazo, não um utilitário genérico. Correção: função de data-alvo '
             || 'com antecipação consultando feriados, usada pelos alertas do DEC13-030 '
             || '(RNF-003 do documento).';
  ELSIF v_feriados IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A tabela de feriados não existe mais nesta base.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Motor de antecipação presente: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-032 — adiantamento nas férias baixa na apuração e deduz na 2ª
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_032()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_opcao text; v_fns text; v_ponte text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a opção adiantar_13 das férias chega ao módulo do 13º?';
  r.esperado := 'Adiantamento pago no gozo aparece na apuração anual como 1ª parcela JÁ PAGA';
  v_opcao := public.qa_col_existe('ferias_programacao', 'adiantar_13');
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%adiantar_13%';
  v_ponte := coalesce(public.qa_col_existe('folha_13_calculo', '%adiant%'),
                      public.qa_col_existe('folha_13_calculo', '%ferias%'),
                      public.qa_col_existe('folha_13_calculo', '%origem%'));
  IF v_opcao IS NOT NULL AND v_fns IS NULL AND v_ponte IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a opção existe SÓ do lado das férias — ferias_programacao.adiantar_13 '
             || 'é gravada e o cálculo de férias a soma no líquido (FERIAS-035 cobre esse '
             || 'lado), mas o módulo do 13º nunca fica sabendo: nenhuma função lê adiantar_13 '
             || 'e folha_13_calculo não tem campo que registre adiantamento pago fora da '
             || 'rodada (valor_primeira_parcela é digitado). Consequência prática: quem '
             || 'recebeu a 1ª parcela nas férias de julho entra na rodada de novembro e '
             || 'RECEBE DE NOVO — e a 2ª parcela deduz os 50% teóricos, não o valor real. '
             || 'Correção: baixa automática na apuração anual (origem + valor + data do '
             || 'adiantamento) e dedução pelo valor efetivamente pago.';
  ELSIF v_opcao IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'O campo adiantar_13 não existe mais em ferias_programacao.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Ponte férias→13º presente (funções: %s; campos: %s).',
                       coalesce(v_fns, '—'), coalesce(v_ponte, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-033 — dedução do adiantamento e diferenças posteriores
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_033()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_aceitou_p3 boolean := false; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Gravar cálculo com parcela = 3 (só existem 1ª e 2ª)';
  r.esperado := 'Recusado — o 13º tem duas parcelas; "3" só faria sentido como complemento estruturado';
  BEGIN
    INSERT INTO public.folha_13_calculo
      (tenant_id, ano, colaborador_id, colaborador_nome, parcela)
    VALUES (public.qa_sandbox_tenant_id(), extract(year from CURRENT_DATE)::int,
            'qa-dec13-033', 'QA Parcela Tres', 3);
    v_aceitou_p3 := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_aceitou_p3 := false; END;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA (somente leitura): diferença apurada depois da 2ª parcela tem tratamento?';
  r.esperado := 'Complemento/estorno com vínculo à apuração original e reflexo no eSocial';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%complemento%13%' OR p.prosrc ILIKE '%13%complemento%'
         OR (p.prosrc ILIKE '%13_calculo%' AND (p.prosrc ILIKE '%estorno%' OR p.prosrc ILIKE '%diferen%')));

  IF v_aceitou_p3 OR v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: parcela é INT sem CHECK (parcela = 3 foi %s) e não existe '
             || 'estrutura de complemento — variável lançada depois da 2ª parcela (comissão de '
             || 'dezembro, HE da virada) não tem para onde ir: ou o operador edita o cálculo '
             || 'pago (sem trilha — ver DEC13-070) ou a diferença morre esquecida, e ambos '
             || 'erram. A dedução do adiantamento também é frágil: valor_primeira_parcela é '
             || 'digitado, não lido do pagamento real. Correção: CHECK parcela IN (1,2) + '
             || 'registro de complemento/estorno vinculado à apuração original (CA-005 e '
             || 'cenário "Diferença" da seção 25).',
             CASE WHEN v_aceitou_p3 THEN 'aceita' ELSE 'recusada' END);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Parcelas restritas e diferenças tratadas por: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-040 — INSS só na 2ª parcela, em cálculo separado
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_040()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_aceitou boolean := false; v_vig text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Gravar 1ª parcela com INSS retido (R$ 500) — a lei manda reter só na 2ª';
  r.esperado := 'Recusado — adiantamento não sofre INSS; a retenção acontece na quitação';
  BEGIN
    INSERT INTO public.folha_13_calculo
      (tenant_id, ano, colaborador_id, colaborador_nome, parcela, valor_inss, base_inss)
    VALUES (public.qa_sandbox_tenant_id(), extract(year from CURRENT_DATE)::int,
            'qa-dec13-040', 'QA INSS Primeira', 1, 500, 3000);
    v_aceitou := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_aceitou := false; END;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: a tabela de INSS é versionada por vigência?';
  r.esperado := 'folha_tabelas_inss com vigência (RNF-002) — o ponto bom do desenho atual';
  v_vig := public.qa_col_existe('folha_tabelas_inss', 'vigencia_inicio');

  IF v_aceitou THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o banco aceitou 1ª parcela com INSS retido — nenhum CHECK impede '
             || 'encargo no adiantamento (parcela = 1 com valor_inss = 500 entrou). O cálculo do '
             || 'React até faz certo (1ª sem descontos, 2ª com INSS em base separada da folha '
             || 'do mês, progressão própria de faixas), mas a regra vive SÓ na tela: qualquer '
             || 'escrita direta, importação ou ajuste manual grava o ilegal sem resistência. '
             || 'O versionamento das tabelas está correto (%s). Correção: CHECK '
             || '(parcela = 2 OR (valor_inss = 0 AND valor_irrf = 0)) — a regra legal morando '
             || 'no banco, não só no formulário.',
             coalesce('vigência presente: ' || v_vig, 'vigência AUSENTE'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Encargo na 1ª parcela recusado; tabelas com vigência (%s).',
                       coalesce(v_vig, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-041 — IRRF exclusivo na fonte, na 2ª parcela
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_041()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_aceitou boolean := false; v_vig text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Gravar 1ª parcela com IRRF retido (R$ 300) — tributação do 13º é exclusiva da 2ª';
  r.esperado := 'Recusado — o IRRF do 13º nasce na quitação, sobre o valor integral, apartado do mês';
  BEGIN
    INSERT INTO public.folha_13_calculo
      (tenant_id, ano, colaborador_id, colaborador_nome, parcela, valor_irrf, base_irrf)
    VALUES (public.qa_sandbox_tenant_id(), extract(year from CURRENT_DATE)::int,
            'qa-dec13-041', 'QA IRRF Primeira', 1, 300, 4000);
    v_aceitou := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_aceitou := false; END;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: a tabela de IRRF é versionada por vigência?';
  r.esperado := 'folha_tabelas_irrf com vigência e deduções parametrizadas';
  v_vig := public.qa_col_existe('folha_tabelas_irrf', 'vigencia_inicio');

  IF v_aceitou THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO (par do DEC13-040, aqui pelo imposto): 1ª parcela com IRRF entrou '
             || 'sem resistência — a exclusividade na fonte (RIR/2018, art. 700: apura na 2ª '
             || 'parcela sobre o valor integral, sem somar aos rendimentos do mês) existe só no '
             || 'cálculo do React. O detalhe que agrava: base_irrf digitável permite também '
             || 'somar o 13º ao salário de dezembro numa base só, mudando a faixa dos dois — o '
             || 'erro clássico. Tabelas versionadas: %s. Correção: mesmo CHECK do DEC13-040 '
             || 'cobrindo valor_irrf, e memória de cálculo registrando a base apartada.',
             coalesce(v_vig, 'vigência AUSENTE'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('IRRF na 1ª parcela recusado; tabelas com vigência (%s).',
                       coalesce(v_vig, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-042 — FGTS de 8% nas duas parcelas, por competência
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_042()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_aceitou boolean := false; v_comp text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Gravar cálculo com base de FGTS MAIOR que o bruto (base 10.000 para bruto 3.000)';
  r.esperado := 'Recusado — a base do FGTS de cada parcela é fração do bruto, nunca mais que ele';
  BEGIN
    INSERT INTO public.folha_13_calculo
      (tenant_id, ano, colaborador_id, colaborador_nome, parcela,
       valor_bruto, base_fgts, valor_fgts)
    VALUES (public.qa_sandbox_tenant_id(), extract(year from CURRENT_DATE)::int,
            'qa-dec13-042', 'QA FGTS Inflado', 2, 3000, 10000, 800);
    v_aceitou := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_aceitou := false; END;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: o depósito de cada parcela tem competência registrada para a guia?';
  r.esperado := 'FGTS da 1ª na competência do adiantamento; da 2ª na competência da quitação';
  v_comp := coalesce(public.qa_col_existe('folha_13_calculo', '%competencia%'),
                     public.qa_col_existe('folha_13_calculo', '%data_pagamento%'));

  IF v_aceitou OR v_comp IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o cálculo do React reparte a base certa (1ª: metade; 2ª: '
             || 'diferença — 8%% exatos no total, Lei 8.036 art. 15), mas o banco não sustenta '
             || 'a regra: base_fgts inflada além do bruto foi %s e NÃO HÁ campo de competência '
             || 'nem data de pagamento em folha_13_calculo (%s) — sem eles não se monta a guia '
             || 'de cada parcela nem se prova o depósito na competência devida, que é '
             || 'exatamente o que o FGTS Digital confere. Correção: CHECK base_fgts <= '
             || 'valor_bruto + colunas de competência/data de pagamento por parcela.',
             CASE WHEN v_aceitou THEN 'aceita' ELSE 'recusada' END,
             coalesce('há: ' || v_comp, 'nenhum campo'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Base consistente e competência registrada (%s).', v_comp);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-050 — eSocial: S-1200 anual e S-1210 sem duplicidade
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_050()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_unq text; v_anual text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a folha anual do 13º tem eventos e anti-duplicidade?';
  r.esperado := 'S-1200 (apuração anual) e S-1210 (pagamentos) gerados, com unicidade por competência';
  IF to_regclass('public.esocial_transmissoes') IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A tabela de transmissões do eSocial não existe nesta base.';
    RETURN r;
  END IF;
  SELECT string_agg(conname, ', ') INTO v_unq
  FROM pg_constraint WHERE conrelid = 'public.esocial_transmissoes'::regclass AND contype = 'u';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_anual
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%S-1200%' OR p.prosrc ILIKE '%S1200%' OR p.prosrc ILIKE '%anual%13%');

  IF v_unq IS NULL AND v_anual IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO (terceiro da série ADM-093/FERIAS-081, agora pela folha ANUAL): o 13º '
             || 'não gera evento nenhum — nenhuma função monta o S-1200 da competência anual '
             || 'nem o S-1210 dos pagamentos das parcelas, e esocial_transmissoes segue sem '
             || 'unicidade (mesmo evento gravável duas vezes). A competência anual tem regra '
             || 'própria de retificação e prazo; sem os eventos, o 13º pago não existe para o '
             || 'governo — e a DCTFWeb de dezembro não fecha com a folha. Correção: geração '
             || 'dos dois eventos no fechamento (apuração e pagamento), chave natural '
             || '(vínculo + tipo + competência anual) e tradução de rejeição em instrução, '
             || 'nunca reenvio às cegas.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Proteções presentes (unicidade: %s; eventos anuais: %s).',
                       coalesce(v_unq, '—'), coalesce(v_anual, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-051 — provisão do 13º viva, competência a competência
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_051()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_tab text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a provisão do 13º é alimentada por algum motor?';
  r.esperado := '1/12 + encargos por competência e vínculo ativo, baixada contra os pagamentos';
  v_tab := CASE WHEN to_regclass('public.folha_provisoes') IS NOT NULL THEN 'folha_provisoes' END;
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%folha_provisoes%';
  IF v_tab IS NOT NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a tabela existe (folha_provisoes, com tipo, encargos e reversão — '
             || 'desenho certo) e NENHUMA função a alimenta: a provisão do 13º é lançada à '
             || 'mão, quando alguém lembra. Provisão por regime de competência não é enfeite '
             || 'contábil — o custo nasce 1/12 por mês (CA-009), admissões e desligamentos a '
             || 'ajustam, e o contador precisa conciliar provisionado × pago no fim do ano '
             || '(seção 20). À mão, ela desalinha da folha no primeiro mês esquecido e o '
             || 'balancete de dezembro leva o susto do ano inteiro de uma vez. Correção: '
             || 'rotina mensal (pg_cron) provisionando por vínculo ativo e baixando contra '
             || 'os pagamentos das parcelas.';
  ELSIF v_tab IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A tabela folha_provisoes não existe mais nesta base.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Provisão alimentada por: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-060 — rescisão: proporcional pago, justa causa perde, adiantamento concilia
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_060()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_aceitou boolean := false; v_ponte text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Gravar rescisão POR JUSTA CAUSA pagando 13º proporcional de R$ 1.000';
  r.esperado := 'Recusado — na dispensa por justa causa o 13º proporcional é perdido';
  BEGIN
    INSERT INTO public.folha_rescisoes
      (tenant_id, colaborador_id, colaborador_nome, tipo_rescisao,
       data_desligamento, decimo_terceiro_proporcional)
    VALUES (public.qa_sandbox_tenant_id(), 'qa-dec13-060', 'QA Justa Causa Com 13',
            'DISPENSA_COM_JUSTA_CAUSA', CURRENT_DATE, 1000);
    v_aceitou := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_aceitou := false; END;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: a rescisão concilia com o módulo do 13º (adiantamento pago, rodada anual)?';
  r.esperado := 'Adiantamento deduzido nas verbas e vínculo desligado fora da rodada de novembro/dezembro';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_ponte
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%folha_rescisoes%' AND p.prosrc ILIKE '%13_calculo%';

  IF v_aceitou OR v_ponte IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a rescisão tem o campo certo (decimo_terceiro_proporcional) e '
             || 'nenhuma regra por trás — justa causa com 13º proporcional de R$ 1.000 foi '
             || '%s (o cálculo correto vive só no React, calcularRescisao), e nenhuma função '
             || 'liga folha_rescisoes a folha_13_calculo (%s): adiantamento pago nas férias '
             || 'não é conferido nas verbas, e o desligado pode reaparecer na rodada anual. '
             || 'A exceção da culpa recíproca (50%%, Súmula 14) é o DESL-035. Correção: '
             || 'validação motivo × verba no banco e conciliação rescisão ↔ apuração anual '
             || 'do 13º nos dois sentidos.',
             CASE WHEN v_aceitou THEN 'aceito' ELSE 'recusado' END,
             coalesce('há: ' || v_ponte, 'nenhuma'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Justa causa sem 13º garantida e conciliação presente (%s).', v_ponte);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-070 — cálculo fechado só reabre com rito
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_070()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_id uuid; v_alterou boolean := false; v_trg text;
BEGIN
  INSERT INTO public.folha_13_calculo
    (tenant_id, ano, colaborador_id, colaborador_nome, parcela,
     valor_bruto, total_liquido, status)
  VALUES (public.qa_sandbox_tenant_id(), extract(year from CURRENT_DATE)::int,
          'qa-dec13-070', 'QA Pago Editado', 2, 3000, 2500, 'pago')
  RETURNING id INTO v_id;

  r.passo_ordem := 1;
  r.passo_acao := 'Editar diretamente o valor bruto de um cálculo com status PAGO';
  r.esperado := 'Bloqueado — valor pago só muda por reabertura com motivo, dupla aprovação e diferença';
  BEGIN
    UPDATE public.folha_13_calculo SET valor_bruto = 9999 WHERE id = v_id;
    SELECT (valor_bruto = 9999) INTO v_alterou FROM public.folha_13_calculo WHERE id = v_id;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_alterou := false; END;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: existe trilha de alteração na tabela do 13º?';
  r.esperado := 'Gatilho de auditoria registrando antes/depois (RNF-004: log imutável)';
  SELECT string_agg(DISTINCT t.tgname, ', ') INTO v_trg
  FROM pg_trigger t
  -- a cerca do sandbox de QA (qa_guarda_cercado) não é trilha de auditoria
  WHERE t.tgrelid = 'public.folha_13_calculo'::regclass AND NOT t.tgisinternal
    AND t.tgname NOT ILIKE '%updated_at%' AND t.tgname NOT ILIKE 'qa\_%';

  IF v_alterou AND v_trg IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: um cálculo PAGO foi editado em silêncio — o valor bruto mudou de 3.000 '
             || 'para 9.999 sem bloqueio, sem justificativa, sem aprovação e sem trilha (o único '
             || 'gatilho da tabela é o de updated_at, que não guarda o valor anterior). Nem o '
             || 'status tem CHECK: qualquer texto vale. Recibo entregue dizendo um valor e banco '
             || 'dizendo outro é exatamente o cenário que a auditoria trabalhista procura, e a '
             || 'reabertura com rito (motivo + dupla aprovação + diferença como complemento/'
             || 'estorno) é o RF-007 do documento. Correção: trava de UPDATE para status pago/'
             || 'fechado + trilha append-only com antes/depois + fluxo de reabertura. Mesma '
             || 'disciplina do FERIAS-054.';
  ELSIF NOT v_alterou THEN
    r.situacao := 'passou';
    r.obtido := 'A edição direta do cálculo pago foi recusada.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Alteração registrada em trilha (%s) — conferir se guarda antes/depois.', v_trg);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-071 — remuneração do 13º restrita por perfil
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_071()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_restr int; v_proprio int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): as políticas de folha_13_calculo separam o próprio do alheio?';
  r.esperado := 'Colaborador lê só o próprio cálculo; folha da equipe restrita por perfil (camada RESTRICTIVE)';
  SELECT count(*) INTO v_restr
  FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'folha_13_calculo'
    AND permissive = 'RESTRICTIVE';
  SELECT count(*) INTO v_proprio
  FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'folha_13_calculo'
    AND (qual ILIKE '%auth.uid%' OR qual ILIKE '%usuario%' OR qual ILIKE '%colaborador%uid%');

  IF v_restr = 0 AND v_proprio = 0 THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: folha_13_calculo tem UMA política, e ela é só de tenant — qualquer '
             || 'usuário autenticado da empresa, inclusive o colaborador comum, lê a folha de '
             || '13º INTEIRA: salário-base, médias e líquido de todos os colegas. Remuneração '
             || 'é dado pessoal com acesso mínimo (LGPD art. 6º VII e seção 6 do documento: '
             || 'colaborador vê só o próprio), e a tabela está FORA da camada '
             || 'perfil_restringe_leitura_* que protege as 20 tabelas sensíveis do sistema — '
             || 'a folha de férias (folha_ferias_calculo) já tem a dela, o 13º ficou sem. '
             || 'Correção: política RESTRICTIVE via perfil_permite_modulo (padrão PERFIL-003) '
             || '+ regra de "próprio registro" para o colaborador.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Camadas presentes (restritivas: %s; separação do próprio: %s políticas).',
                       v_restr, v_proprio);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- Registro no motor
INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
  ('DEC13-001','qa_caso_dec13_001',true), ('DEC13-002','qa_caso_dec13_002',true),
  ('DEC13-003','qa_caso_dec13_003',true), ('DEC13-020','qa_caso_dec13_020',true),
  ('DEC13-021','qa_caso_dec13_021',true), ('DEC13-030','qa_caso_dec13_030',true),
  ('DEC13-031','qa_caso_dec13_031',true), ('DEC13-032','qa_caso_dec13_032',true),
  ('DEC13-033','qa_caso_dec13_033',true), ('DEC13-040','qa_caso_dec13_040',true),
  ('DEC13-041','qa_caso_dec13_041',true), ('DEC13-042','qa_caso_dec13_042',true),
  ('DEC13-050','qa_caso_dec13_050',true), ('DEC13-051','qa_caso_dec13_051',true),
  ('DEC13-060','qa_caso_dec13_060',true), ('DEC13-070','qa_caso_dec13_070',true),
  ('DEC13-071','qa_caso_dec13_071',true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- ══════════ 2a leva: 14 casos novos e suas rotinas ══════════
DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'financeiro/decimo-terceiro';
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo financeiro/decimo-terceiro nao existe nesta base — casos nao inseridos.';
    RETURN;
  END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'DEC13-004', 'Aviso prévio indenizado projeta o tempo e pode gerar mais um avo',
   'negativo', 'critica', 'aprovado', 'api',
   'CLT, art. 487, §1º; Súmula 371 do TST; OJ 82 da SDI-1 do TST',
   'O aviso prévio indenizado integra o tempo de serviço para todos os efeitos legais. Desligado em 20/11 com 30 dias de aviso indenizado, o contrato projeta até 20/12: dezembro passa a ter 20 dias e vira mais um avo. Ignorar a projeção paga 11/12 onde a lei manda 12/12 — diferença que volta como reclamatória.',
   'Vínculo desligado em 20/11 do ano-base, com aviso prévio indenizado de 30 dias.',
   '[{"ordem": 1, "acao": "Apurar o 13º sem considerar a projeção", "resultado_esperado": "11 avos"}, {"ordem": 2, "acao": "Apurar considerando a projeção do aviso indenizado", "resultado_esperado": "12 avos — dezembro fecha 20 dias com a projeção"}, {"ordem": 3, "acao": "Conferir a memória", "resultado_esperado": "A memória mostra a data projetada do fim do contrato, não só a data do desligamento"}]'::jsonb,
   'Aviso indenizado conta como tempo de serviço — inclusive para o avo de dezembro.',
   'Requisitos YE-DP-13-001: RN-001 e RN-009 (rescisão). O mesmo vale para as férias proporcionais.'),

  (v_mod, 'DEC13-005', 'Fronteira dos 15 dias: dia 16 conta o avo, dia 17 não',
   'negativo', 'alta', 'aprovado', 'api',
   'Lei 4.090/1962, art. 1º, §2º (fração igual ou superior a 15 dias)',
   'A regra da fração é de contagem exata e é onde mais se erra por um dia. Em mês de 31 dias, admissão no dia 17 deixa 15 dias trabalhados (17 a 31) e CONTA; no dia 18 deixa 14 e NÃO conta. Fevereiro, com 28 ou 29 dias, tem fronteira própria. O teste fixa as bordas para que nenhuma mudança futura as mova sem que alguém perceba.',
   'Vínculos fictícios admitidos exatamente nas datas de fronteira do ano-base.',
   '[{"ordem": 1, "acao": "Admitido em 17/03 (mês de 31 dias)", "resultado_esperado": "Março conta — 15 dias trabalhados"}, {"ordem": 2, "acao": "Admitido em 18/03", "resultado_esperado": "Março não conta — 14 dias"}, {"ordem": 3, "acao": "Admitido em 14/02 (ano comum, 28 dias)", "resultado_esperado": "Fevereiro conta — 15 dias"}, {"ordem": 4, "acao": "Admitido em 15/02 (ano comum)", "resultado_esperado": "Fevereiro não conta — 14 dias"}]'::jsonb,
   'A borda é 15 dias exatos, contados no calendário do próprio mês.',
   'Requisitos YE-DP-13-001: RN-001 / CA-001. Complementa DEC13-001, que cobre o caso geral.'),

  (v_mod, 'DEC13-006', 'Afastamento por acidente de trabalho conta como tempo de serviço',
   'alternativo', 'alta', 'aprovado', 'api',
   'Lei 8.213/1991, art. 4º, parágrafo único e art. 118; CLT, art. 4º; Súmula 46 do TST',
   'O afastamento acidentário (benefício B-91) não é igual ao auxílio-doença comum: o período é contado como tempo de serviço para todos os efeitos, inclusive 13º. Tratar acidente de trabalho como doença comum tira avos que a lei manda pagar.',
   'Vínculo com 4 meses de afastamento acidentário (B-91) no ano-base.',
   '[{"ordem": 1, "acao": "Apurar o 13º de quem se afastou por acidente de trabalho", "resultado_esperado": "Os meses de afastamento contam como avos do empregador"}, {"ordem": 2, "acao": "Comparar com afastamento por doença comum", "resultado_esperado": "Na doença comum o empregador paga só os 15 primeiros dias e o restante é abono anual do INSS"}, {"ordem": 3, "acao": "Conferir a memória", "resultado_esperado": "A memória nomeia o tipo de afastamento e o efeito aplicado"}]'::jsonb,
   'Acidente de trabalho conta tempo; doença comum divide com o INSS.',
   'Requisitos YE-DP-13-001: RN-008. Complementa DEC13-003, que trata maternidade e doença comum.'),

  (v_mod, 'DEC13-022', 'Horas extras entram pela média física × valor da hora atual (Súmula 347)',
   'alternativo', 'alta', 'aprovado', 'api',
   'Súmula 347 do TST; Decreto 57.155/1965, art. 2º',
   'A média de horas extras do 13º é FÍSICA: soma-se a quantidade de HORAS do ano, divide-se pelos meses e multiplica-se pelo valor da hora VIGENTE no pagamento. Usar a média dos valores históricos paga a menos sempre que houve aumento salarial no ano — é passivo certo.',
   'Vínculo com 10 horas extras por mês o ano todo e aumento salarial no meio do ano.',
   '[{"ordem": 1, "acao": "Apurar a média pela quantidade de horas × valor atual", "resultado_esperado": "Média calculada sobre o salário vigente"}, {"ordem": 2, "acao": "Comparar com a média dos valores pagos no ano", "resultado_esperado": "A média física é MAIOR quando houve aumento"}, {"ordem": 3, "acao": "Conferir a memória", "resultado_esperado": "A memória informa qual critério foi usado e por quê"}]'::jsonb,
   'Média física protege o cálculo do aumento salarial no meio do ano.',
   'Requisitos YE-DP-13-001: RN-003. Sem registro de ponto no ano, o sistema usa os valores pagos e avisa.'),

  (v_mod, 'DEC13-023', 'Adicionais habituais integram a base do 13º',
   'feliz', 'alta', 'aprovado', 'api',
   'Súmula 60 (adicional noturno), Súmula 132 (adicional de periculosidade) e Súmula 139 (adicional de insalubridade) do TST; Decreto 57.155/1965, art. 2º',
   'Adicional noturno, de insalubridade e de periculosidade pagos com habitualidade integram a remuneração e, portanto, a base do 13º. Se as rubricas desses adicionais não estiverem marcadas como integrantes do 13º no cadastro, o cálculo sai a menor sem ninguém perceber.',
   'Rubricas de adicional noturno, insalubridade e periculosidade cadastradas e pagas com habitualidade.',
   '[{"ordem": 1, "acao": "Conferir a marcação das rubricas de adicional", "resultado_esperado": "Marcadas como integrantes da base do 13º"}, {"ordem": 2, "acao": "Apurar a média das variáveis", "resultado_esperado": "Os adicionais habituais entram na média"}, {"ordem": 3, "acao": "Conferir a memória", "resultado_esperado": "Cada rubrica somada aparece nomeada na memória"}]'::jsonb,
   'Adicional habitual é remuneração — e remuneração entra no 13º.',
   'Requisitos YE-DP-13-001: RN-003 / CA-002. Complementa DEC13-020.'),

  (v_mod, 'DEC13-034', 'Política do adiantamento: as duas opções da lei, à escolha da empresa',
   'alternativo', 'alta', 'aprovado', 'api',
   'Lei 4.749/1965, art. 2º, caput',
   'A lei manda adiantar METADE do salário do mês anterior. A prática consolidada admite também metade do 13º apurado (com médias). As duas leituras são defensáveis, então a escolha é da empresa — e precisa ficar registrada, com efeito real no cálculo e a mesma política valendo para todos no ano.',
   'Empresa com a política do adiantamento configurada.',
   '[{"ordem": 1, "acao": "Configurar a política ''metade da remuneração do mês anterior'' e apurar a 1ª parcela", "resultado_esperado": "Valor = 50% da remuneração do mês anterior"}, {"ordem": 2, "acao": "Trocar para ''metade do 13º apurado'' e apurar de novo", "resultado_esperado": "Valor = 50% do 13º com médias — diferente do anterior"}, {"ordem": 3, "acao": "Conferir o registro", "resultado_esperado": "A política escolhida fica gravada e visível na memória do cálculo"}]'::jsonb,
   'As duas opções existem, a empresa escolhe e o sistema obedece — sem valor mágico.',
   'Requisitos YE-DP-13-001: RN-004. Ponto [VAL] do documento: a escolha deve ser conferida com a contabilidade.'),

  (v_mod, 'DEC13-035', 'Adiantamento nas férias fora de janeiro é avisado, não recusado',
   'negativo', 'media', 'aprovado', 'api',
   'Lei 4.749/1965, art. 2º, §2º',
   'O empregado que quer receber a 1ª parcela nas férias deve requerer em JANEIRO do ano correspondente. Pedido fora dessa janela não obriga o empregador. O sistema não deve recusar em silêncio nem pagar sem registro: deve avisar que o pedido saiu fora do prazo e deixar a decisão documentada.',
   'Pedido de férias com adiantamento do 13º requerido em março.',
   '[{"ordem": 1, "acao": "Gerar os adiantamentos das férias do ano", "resultado_esperado": "Os pedidos de janeiro geram a 1ª parcela normalmente"}, {"ordem": 2, "acao": "Conferir o pedido feito em março", "resultado_esperado": "Aparece na lista de avisos como fora da janela do §2º"}, {"ordem": 3, "acao": "Conferir a contagem", "resultado_esperado": "O retorno informa quantos pedidos ficaram fora de janeiro"}]'::jsonb,
   'Fora de janeiro não é proibido — é decisão da empresa, e fica registrada.',
   'Requisitos YE-DP-13-001: RN-004. Complementa DEC13-032.'),

  (v_mod, 'DEC13-043', 'INSS do 13º respeita faixas e teto, e bate com a tabela vigente',
   'feliz', 'critica', 'aprovado', 'api',
   'Lei 8.212/1991, art. 20 e art. 28, §7º; Decreto 3.048/1999, art. 214, §6º',
   'O INSS do 13º é progressivo por faixas e limitado ao teto. O cálculo do banco (usado no lote) e o da tela precisam dar o MESMO número em todas as faixas, inclusive nas bordas e acima do teto — divergência entre os dois é erro de recolhimento, com multa.',
   'Tabela de INSS vigente cadastrada.',
   '[{"ordem": 1, "acao": "Calcular o INSS em bases de cada faixa e nas bordas", "resultado_esperado": "Valor progressivo, faixa a faixa"}, {"ordem": 2, "acao": "Calcular o INSS em base acima do teto", "resultado_esperado": "Desconto limitado ao teto — não cresce mais"}, {"ordem": 3, "acao": "Comparar banco e tela", "resultado_esperado": "Mesmo valor, centavo a centavo"}]'::jsonb,
   'Faixas, bordas e teto conferidos — e os dois caminhos de cálculo concordando.',
   'Requisitos YE-DP-13-001: RN-005 / CA-004. Complementa DEC13-040.'),

  (v_mod, 'DEC13-052', 'Provisão do 13º é revertida quando o colaborador é desligado',
   'negativo', 'alta', 'aprovado', 'api',
   'Lei 6.404/1976, art. 177 (regime de competência); NBC TG 1000, seção 21 (provisões); documento YE-DP-13-001, CA-009',
   'A provisão acumula 1/12 por mês enquanto o vínculo existe. Quando o colaborador é desligado e o 13º é quitado na rescisão, a provisão daquele vínculo precisa ser REVERTIDA — senão o balanço carrega para sempre uma obrigação que já foi paga.',
   'Colaborador provisionado durante o ano e desligado antes de dezembro.',
   '[{"ordem": 1, "acao": "Provisionar competências com o vínculo ativo", "resultado_esperado": "Provisão acumulada mês a mês"}, {"ordem": 2, "acao": "Desligar o colaborador e provisionar a competência seguinte", "resultado_esperado": "A provisão do desligado é revertida, não repetida"}, {"ordem": 3, "acao": "Conciliar o ano", "resultado_esperado": "Provisionado e pago fecham, sem sobra do desligado"}]'::jsonb,
   'Provisão de quem saiu não fica pendurada no balanço.',
   'Requisitos YE-DP-13-001: RNF-007. Complementa DEC13-051.'),

  (v_mod, 'DEC13-061', 'Culpa recíproca paga metade do 13º proporcional',
   'alternativo', 'alta', 'aprovado', 'api',
   'CLT, art. 484; Súmula 14 do TST',
   'Reconhecida a culpa recíproca, as verbas rescisórias devidas pela dispensa sem justa causa são pagas pela METADE — inclusive o 13º proporcional. Tratar como justa causa (zero) ou como dispensa comum (integral) erra nos dois sentidos.',
   'Rescisão por culpa recíproca reconhecida judicialmente, no meio do ano-base.',
   '[{"ordem": 1, "acao": "Apurar o 13º da rescisão por culpa recíproca", "resultado_esperado": "Metade do 13º proporcional aos avos"}, {"ordem": 2, "acao": "Comparar com a dispensa sem justa causa", "resultado_esperado": "Metade do valor da dispensa comum"}, {"ordem": 3, "acao": "Conferir o fundamento", "resultado_esperado": "A memória cita o art. 484 da CLT e a Súmula 14 do TST"}]'::jsonb,
   'Culpa recíproca não é zero nem inteiro: é metade.',
   'Requisitos YE-DP-13-001: RN-009. DESL-035 cobre o lado do aviso prévio; aqui é o 13º.'),

  (v_mod, 'DEC13-062', 'Pedido de demissão mantém o 13º proporcional',
   'feliz', 'alta', 'aprovado', 'api',
   'Lei 4.090/1962, art. 3º; Súmula 157 do TST',
   'Quem pede demissão tem direito ao 13º proporcional aos meses trabalhados. Só a dispensa por justa causa afasta a gratificação. Confundir os dois motivos retém verba devida — e a Súmula 157 é expressa.',
   'Rescisão por pedido de demissão em agosto do ano-base.',
   '[{"ordem": 1, "acao": "Apurar o 13º da rescisão por pedido de demissão", "resultado_esperado": "8/12 do 13º, proporcional aos avos"}, {"ordem": 2, "acao": "Comparar com a dispensa por justa causa", "resultado_esperado": "Na justa causa, zero"}, {"ordem": 3, "acao": "Conferir o abatimento do adiantamento", "resultado_esperado": "Se houve 1ª parcela paga, ela é deduzida"}]'::jsonb,
   'Pedir demissão não faz perder o 13º proporcional.',
   'Requisitos YE-DP-13-001: RN-009. Complementa DEC13-060.'),

  (v_mod, 'DEC13-063', 'Falecimento: o 13º proporcional é devido e vai aos dependentes',
   'alternativo', 'media', 'aprovado', 'api',
   'Lei 6.858/1980, art. 1º; Lei 4.090/1962, art. 3º',
   'Com o falecimento do empregado, o 13º proporcional continua devido e é pago aos dependentes habilitados na Previdência, independentemente de inventário. O sistema não pode tratar o falecimento como perda da gratificação.',
   'Rescisão por falecimento em setembro do ano-base.',
   '[{"ordem": 1, "acao": "Apurar o 13º da rescisão por falecimento", "resultado_esperado": "9/12, proporcional aos avos — valor devido"}, {"ordem": 2, "acao": "Conferir o fundamento", "resultado_esperado": "A memória registra que o pagamento segue a Lei 6.858/1980"}, {"ordem": 3, "acao": "Conferir que não é tratado como justa causa", "resultado_esperado": "Valor diferente de zero"}]'::jsonb,
   'Falecimento não extingue a gratificação proporcional.',
   'Requisitos YE-DP-13-001: RN-009. O encaminhamento aos dependentes é operação do DP, fora do cálculo.'),

  (v_mod, 'DEC13-072', 'Rodar o lote duas vezes não duplica parcela',
   'negativo', 'alta', 'aprovado', 'api',
   'Documento YE-DP-13-001, RF-004 e RNF-008 (processamento em lote idempotente)',
   'O processamento em lote é feito por pessoas, sob pressão de prazo, e será clicado duas vezes. A segunda passada não pode criar uma segunda parcela viva para o mesmo colaborador: tem de pular quem já tem cálculo e dizer quantos pulou.',
   'Empresa com colaboradores aptos e a 1ª parcela já processada.',
   '[{"ordem": 1, "acao": "Processar o lote da 1ª parcela", "resultado_esperado": "Cálculos criados para os aptos"}, {"ordem": 2, "acao": "Processar o mesmo lote de novo", "resultado_esperado": "Nenhum cálculo novo; o retorno informa quantos já existiam"}, {"ordem": 3, "acao": "Conferir a base", "resultado_esperado": "Uma única parcela viva por colaborador/ano"}]'::jsonb,
   'Clicar duas vezes não duplica folha.',
   'Requisitos YE-DP-13-001: RF-004. A trava de base é a unicidade da parcela viva.'),

  (v_mod, 'DEC13-073', 'Prazo legal recua para o último dia útil, inclusive em feriado municipal',
   'negativo', 'alta', 'aprovado', 'api',
   'Lei 4.749/1965, arts. 1º e 2º; Lei 662/1949 e Lei 9.093/1995 (feriados civis e municipais)',
   'Se 30/11 ou 20/12 caem em sábado, domingo ou feriado, o pagamento tem de ser ANTECIPADO para o último dia útil anterior — nunca adiado. A conta precisa enxergar também o feriado municipal da cidade do estabelecimento, que é o mais fácil de esquecer.',
   'Feriado municipal cadastrado no dia útil imediatamente anterior à data-limite.',
   '[{"ordem": 1, "acao": "Consultar o prazo da 2ª parcela num ano em que 20/12 cai em domingo", "resultado_esperado": "Data-limite antecipada para a sexta-feira"}, {"ordem": 2, "acao": "Cadastrar feriado municipal nessa sexta e consultar de novo", "resultado_esperado": "Antecipa mais um dia útil"}, {"ordem": 3, "acao": "Conferir a 1ª parcela em 30/11", "resultado_esperado": "Mesma regra de antecipação"}]'::jsonb,
   'A data-limite anda para trás, nunca para frente.',
   'Requisitos YE-DP-13-001: RN-002 / CA-003. Complementa DEC13-031.')
  ON CONFLICT (codigo) DO UPDATE SET
      titulo = EXCLUDED.titulo, base_legal = EXCLUDED.base_legal,
      objetivo = EXCLUDED.objetivo, pre_condicoes = EXCLUDED.pre_condicoes,
      passos = EXCLUDED.passos, resultado_esperado = EXCLUDED.resultado_esperado,
      observacoes = EXCLUDED.observacoes, nivel = EXCLUDED.nivel,
      prioridade = EXCLUDED.prioridade, updated_at = now();

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Documentacao de testes do 13o: % casos antes, % depois.', v_antes, v_depois;
END $doc$;

-- ── DEC13-005: a fronteira dos 15 dias, dia a dia ─────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_005()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_ten uuid := public.qa_sandbox_tenant_id();
  v_ano int := extract(year from CURRENT_DATE)::int - 1;
  v_erros text[] := ARRAY[]::text[]; v_lidos text[] := ARRAY[]::text[];
  v_cpf text; v_avos int; c record;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Apurar os avos de vinculos admitidos exatamente nas datas de fronteira';
  r.esperado := 'Mes com 15 dias ou mais conta; com 14, nao conta (Lei 4.090, art. 1o, §2o)';

  FOR c IN
    SELECT * FROM (VALUES
      ('90000005053', make_date(v_ano,3,17), 10, 'admitido em 17/03 (15 dias)'),
      ('90000005134', make_date(v_ano,3,18),  9, 'admitido em 18/03 (14 dias)'),
      ('90000005215', make_date(v_ano,2,14), 11, 'admitido em 14/02'),
      ('90000005304', make_date(v_ano,2,15), 10, 'admitido em 15/02')
    ) AS t(cpf, adm, avos_esperados, rotulo)
  LOOP
    -- vinculo efemero: a sonda cria, le e desfaz o proprio rastro
    DELETE FROM public.admissoes WHERE tenant_id = v_ten AND cpf = c.cpf;
    INSERT INTO public.admissoes (tenant_id, nome_completo, cpf, cargo, data_admissao, status)
    VALUES (v_ten, 'QA Fronteira ' || c.cpf, c.cpf, 'QA', c.adm, 'concluido');

    v_avos := COALESCE((public.decimo_terceiro_avos(v_ten, c.cpf, v_ano, NULL)->>'avos')::int, -1);
    v_lidos := array_append(v_lidos, format('%s: %s avos', c.rotulo, v_avos));
    IF v_avos <> c.avos_esperados THEN
      v_erros := array_append(v_erros,
        format('%s deveria dar %s avos e deu %s', c.rotulo, c.avos_esperados, v_avos));
    END IF;

    DELETE FROM public.admissoes WHERE tenant_id = v_ten AND cpf = c.cpf;
  END LOOP;

  IF array_length(v_erros,1) IS NOT NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a fronteira dos 15 dias esta deslocada — ' || array_to_string(v_erros, '; ')
             || '. Um dia de diferenca na contagem vira um avo a mais ou a menos em toda a folha.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Fronteiras conferidas (' || array_to_string(v_lidos, '; ') || ').';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-043: faixas, bordas e teto do INSS ──────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_043()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_ten uuid := public.qa_sandbox_tenant_id();
  v_erros text[] := ARRAY[]::text[]; v_lidos text[] := ARRAY[]::text[];
  v_ant numeric := -1; v_val numeric; v_teto numeric; v_base numeric;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Calcular o INSS do 13o em bases crescentes, das faixas ate acima do teto';
  r.esperado := 'Valor progressivo que nunca diminui e para de crescer no teto (Lei 8.212/1991, art. 20)';

  FOREACH v_base IN ARRAY ARRAY[1000, 1412, 1500, 2666.68, 4000.03, 7786.02, 9000, 20000]::numeric[]
  LOOP
    v_val := COALESCE((public.decimo_terceiro_inss(v_base, v_ten, NULL)->>'valor')::numeric, -1);
    v_lidos := array_append(v_lidos, format('base %s -> %s', v_base, v_val));
    IF v_val < v_ant THEN
      v_erros := array_append(v_erros, format('base %s desconta MENOS que a base anterior', v_base));
    END IF;
    IF v_val > v_base THEN
      v_erros := array_append(v_erros, format('base %s desconta mais que o proprio 13o', v_base));
    END IF;
    v_ant := v_val;
  END LOOP;

  r.passo_ordem := 2;
  r.passo_acao := 'Conferir o teto: dobrar a base acima do teto nao pode aumentar o desconto';
  r.esperado := 'Mesmo valor — o desconto e limitado ao teto';
  v_teto := (public.decimo_terceiro_inss(20000, v_ten, NULL)->>'valor')::numeric;
  IF (public.decimo_terceiro_inss(40000, v_ten, NULL)->>'valor')::numeric <> v_teto THEN
    v_erros := array_append(v_erros, 'o desconto continua crescendo acima do teto');
  END IF;

  IF array_length(v_erros,1) IS NOT NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o INSS do 13o nao respeita a progressao ou o teto — '
             || array_to_string(v_erros, '; ') || '. Recolhimento errado gera multa.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Progressao e teto conferidos (%s); teto em R$ %s.',
                       array_to_string(v_lidos, '; '), v_teto);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-073: a data-limite anda para tras, nunca para frente ────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_073()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_erros text[] := ARRAY[]::text[]; v_lidos text[] := ARRAY[]::text[];
  v_d date; v_ano int; v_limite date;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Consultar o prazo legal das duas parcelas em varios anos';
  r.esperado := 'Sempre dia util, e nunca depois de 30/11 (1a) ou 20/12 (2a) — Lei 4.749/1965';

  FOR v_ano IN 2024..2030 LOOP
    -- 1a parcela: limite 30/11
    v_d := public.decimo_terceiro_prazo_legal(v_ano, 1, NULL, NULL);
    v_limite := make_date(v_ano, 11, 30);
    IF v_d > v_limite THEN
      v_erros := array_append(v_erros, format('%s: 1a parcela caiu em %s, depois de 30/11', v_ano, v_d));
    END IF;
    IF extract(isodow from v_d) > 5 THEN
      v_erros := array_append(v_erros, format('%s: 1a parcela caiu em fim de semana (%s)', v_ano, v_d));
    END IF;
    v_lidos := array_append(v_lidos, format('%s 1a=%s', v_ano, v_d));

    -- 2a parcela: limite 20/12
    v_d := public.decimo_terceiro_prazo_legal(v_ano, 2, NULL, NULL);
    v_limite := make_date(v_ano, 12, 20);
    IF v_d > v_limite THEN
      v_erros := array_append(v_erros, format('%s: 2a parcela caiu em %s, depois de 20/12', v_ano, v_d));
    END IF;
    IF extract(isodow from v_d) > 5 THEN
      v_erros := array_append(v_erros, format('%s: 2a parcela caiu em fim de semana (%s)', v_ano, v_d));
    END IF;
    v_lidos := array_append(v_lidos, format('2a=%s', v_d));
  END LOOP;

  IF array_length(v_erros,1) IS NOT NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a data-limite do 13o nao antecipa corretamente — '
             || array_to_string(v_erros, '; ')
             || '. Pagar fora da janela e infracao mesmo com o valor certo.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Prazos conferidos em 7 anos, sempre em dia util e dentro do limite ('
             || array_to_string(v_lidos, ', ') || ').';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-006: acidente de trabalho nao derruba avo (Sumula 46 TST) ───
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_006()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_ten uuid := public.qa_sandbox_tenant_id();
  v_ano int := extract(year from CURRENT_DATE)::int - 1;
  v_cpf text := '90000005487'; v_af uuid;
  v_avos_acid int; v_avos_comum int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Apurar os avos de quem ficou 4 meses afastado por ACIDENTE DE TRABALHO (B91)';
  r.esperado := 'Os meses contam: a ausencia por acidente nao pesa contra o 13o (Sumula 46 do TST)';

  DELETE FROM public.afastamentos WHERE tenant_id = v_ten AND colaborador_cpf = v_cpf;
  DELETE FROM public.admissoes   WHERE tenant_id = v_ten AND cpf = v_cpf;
  INSERT INTO public.admissoes (tenant_id, nome_completo, cpf, cargo, data_admissao, status)
  VALUES (v_ten, 'QA Acidentado', v_cpf, 'QA', make_date(v_ano - 3, 1, 10), 'concluido');

  INSERT INTO public.afastamentos (tenant_id, colaborador_cpf, colaborador_nome,
                                   data_inicio, data_fim, nexo_trabalho, observacoes)
  VALUES (v_ten, v_cpf, 'QA Acidentado',
          make_date(v_ano, 3, 1), make_date(v_ano, 6, 30), 'sim'::nexo_trabalho, 'QA DEC13-006')
  RETURNING id INTO v_af;
  INSERT INTO public.afastamentos_previdenciario (tenant_id, afastamento_id, especie_beneficio,
                                                  data_inicio_beneficio)
  VALUES (v_ten, v_af, 'B91', make_date(v_ano, 3, 16));

  v_avos_acid := COALESCE((public.decimo_terceiro_avos(v_ten, v_cpf, v_ano, NULL)->>'avos')::int, -1);

  r.passo_ordem := 2;
  r.passo_acao := 'Trocar o beneficio para DOENCA COMUM (B31) e apurar de novo';
  r.esperado := 'Ai sim os meses de beneficio saem dos avos do empregador — o INSS paga o abono anual';
  UPDATE public.afastamentos_previdenciario SET especie_beneficio = 'B31' WHERE afastamento_id = v_af;
  v_avos_comum := COALESCE((public.decimo_terceiro_avos(v_ten, v_cpf, v_ano, NULL)->>'avos')::int, -1);

  DELETE FROM public.afastamentos_previdenciario WHERE afastamento_id = v_af;
  DELETE FROM public.afastamentos WHERE id = v_af;
  DELETE FROM public.admissoes WHERE tenant_id = v_ten AND cpf = v_cpf;

  IF v_avos_acid < 12 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o afastamento por ACIDENTE DE TRABALHO derruba avos igual ao de '
             || 'doenca comum (acidentario: %s avos; doenca comum: %s avos). A Sumula 46 do TST e '
             || 'expressa: as ausencias por acidente do trabalho NAO sao consideradas contra a '
             || 'gratificacao natalina, e o art. 4o, paragrafo unico, da Lei 8.213/1991 conta o '
             || 'periodo como tempo de servico. Do jeito atual a empresa paga a menos e a '
             || 'diferenca volta como reclamatoria. Correcao: as especies acidentarias (B91, B92) '
             || 'nao entram no desconto de dias do empregador; as comuns (B31, B32) continuam '
             || 'entrando.', v_avos_acid, v_avos_comum);
  ELSIF v_avos_comum >= 12 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO ao contrario: a doenca comum tambem manteve %s avos. O empregador '
             || 'so responde pelos 15 primeiros dias; o restante e abono anual do INSS. Contar '
             || 'tudo paga a MAIS e duplica a despesa.', v_avos_comum);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Cada afastamento com seu efeito: acidente de trabalho manteve %s avos '
             || '(Sumula 46 do TST); doenca comum ficou com %s, cabendo o abono anual ao INSS.',
             v_avos_acid, v_avos_comum);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-004: projecao do aviso previo indenizado ────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_004()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_ten uuid := public.qa_sandbox_tenant_id();
  v_ano int := extract(year from CURRENT_DATE)::int - 1;
  v_cpf text := '90000005568'; v_avos int; v_adm uuid;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Apurar os avos de quem foi desligado em 20/11 com aviso previo INDENIZADO de 30 dias';
  r.esperado := '12 avos: a projecao leva o contrato ate 20/12 e dezembro fecha 20 dias (CLT, art. 487, §1o; Sumula 371 do TST)';

  DELETE FROM public.admissoes WHERE tenant_id = v_ten AND cpf = v_cpf;
  INSERT INTO public.admissoes (tenant_id, nome_completo, cpf, cargo, data_admissao,
                                data_desligamento, status)
  VALUES (v_ten, 'QA Aviso Indenizado', v_cpf, 'QA', make_date(v_ano - 2, 2, 1),
          make_date(v_ano, 11, 20), 'concluido')
  RETURNING id INTO v_adm;

  DELETE FROM public.folha_rescisoes WHERE tenant_id = v_ten AND colaborador_cpf = v_cpf;
  INSERT INTO public.folha_rescisoes (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
                                      admissao_id, tipo_rescisao, data_desligamento,
                                      aviso_tipo, dias_aviso)
  VALUES (v_ten, 'qa-dec13-004', 'QA Aviso Indenizado', v_cpf, v_adm,
          'DISPENSA_SEM_JUSTA_CAUSA', make_date(v_ano, 11, 20), 'indenizado', 30);

  v_avos := COALESCE((public.decimo_terceiro_avos(v_ten, v_cpf, v_ano, NULL)->>'avos')::int, -1);

  DELETE FROM public.folha_rescisoes WHERE tenant_id = v_ten AND colaborador_cpf = v_cpf;
  DELETE FROM public.admissoes WHERE id = v_adm;

  IF v_avos < 12 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a apuracao parou na data do desligamento e devolveu %s avos. O '
             || 'aviso previo INDENIZADO integra o tempo de servico para todos os efeitos legais '
             || '(CLT, art. 487, §1o; Sumula 371 do TST): desligado em 20/11 com 30 dias de aviso, '
             || 'o contrato projeta ate 20/12 e dezembro fecha 20 dias — o 12o avo e devido. '
             || 'Pagar 11/12 onde a lei manda 12/12 e diferenca que volta como reclamatoria, e a '
             || 'mesma projecao vale para as ferias proporcionais. Correcao: somar os dias do '
             || 'aviso indenizado a data de fim do contrato antes de contar os avos.', v_avos);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Projecao do aviso indenizado considerada: %s avos, com dezembro contado '
             || 'pela data projetada do fim do contrato.', v_avos);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-061/062/063: o motivo da rescisao e o 13o ───────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_rescisao_motivo(
  p_tipo text, p_mes int, p_fator numeric, p_cpf text, p_nome text)
RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE
  v_ten uuid := public.qa_sandbox_tenant_id();
  v_ano int := extract(year from CURRENT_DATE)::int - 1;
  v_adm uuid; v_resc uuid; v_out jsonb;
BEGIN
  DELETE FROM public.folha_rescisoes WHERE tenant_id = v_ten AND colaborador_cpf = p_cpf;
  DELETE FROM public.admissoes WHERE tenant_id = v_ten AND cpf = p_cpf;
  INSERT INTO public.admissoes (tenant_id, nome_completo, cpf, cargo, salario, data_admissao,
                                data_desligamento, status)
  VALUES (v_ten, p_nome, p_cpf, 'QA', 3000, make_date(v_ano - 2, 2, 1),
          make_date(v_ano, p_mes, 25), 'concluido')
  RETURNING id INTO v_adm;

  INSERT INTO public.folha_rescisoes (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
                                      admissao_id, tipo_rescisao, data_desligamento)
  VALUES (v_ten, 'qa-' || p_cpf, p_nome, p_cpf, v_adm, p_tipo::public.rescisao_tipo, make_date(v_ano, p_mes, 25))
  RETURNING id INTO v_resc;

  v_out := public.decimo_terceiro_da_rescisao(v_resc);

  DELETE FROM public.folha_rescisoes WHERE id = v_resc;
  DELETE FROM public.admissoes WHERE id = v_adm;
  RETURN v_out;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_dec13_062()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_ped jsonb; v_jc jsonb; v_dev numeric; v_avos int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Apurar o 13o de uma rescisao por PEDIDO DE DEMISSAO em agosto';
  r.esperado := '13o proporcional aos avos — so a justa causa afasta a gratificacao (Sumula 157 do TST)';
  v_ped := public.qa_caso_dec13_rescisao_motivo('PEDIDO_DEMISSAO', 8, 1.0, '90000005649', 'QA Pediu Demissao');
  v_jc  := public.qa_caso_dec13_rescisao_motivo('DISPENSA_COM_JUSTA_CAUSA', 8, 0.0, '90000005720', 'QA Justa Causa');
  v_dev := COALESCE((v_ped->>'devido')::numeric, -1);
  v_avos := COALESCE((v_ped->>'avos')::int, -1);

  IF v_dev <= 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o pedido de demissao ficou sem 13o proporcional (devido: R$ %s, '
             || '%s avos). A Sumula 157 do TST e o art. 3o da Lei 4.090/1962 garantem a '
             || 'gratificacao proporcional a quem pede demissao — so a justa causa a afasta. '
             || 'Reter verba devida e passivo direto.', v_dev, v_avos);
  ELSIF COALESCE((v_jc->>'devido')::numeric, -1) <> 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO ao contrario: a justa causa pagou R$ %s de 13o proporcional, '
             || 'quando a Lei 4.090/1962 a afasta.', (v_jc->>'devido'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Pedido de demissao manteve o 13o proporcional (%s avos, R$ %s) e a justa '
             || 'causa ficou em zero, como manda a lei.', v_avos, v_dev);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_dec13_063()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_out jsonb; v_dev numeric;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Apurar o 13o de uma rescisao por FALECIMENTO em setembro';
  r.esperado := '13o proporcional devido, para pagamento aos dependentes (Lei 6.858/1980)';
  v_out := public.qa_caso_dec13_rescisao_motivo('FALECIMENTO', 9, 1.0, '90000005800', 'QA Falecimento');
  v_dev := COALESCE((v_out->>'devido')::numeric, -1);

  IF v_dev <= 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o falecimento ficou sem 13o proporcional (R$ %s). A gratificacao '
             || 'continua devida e e paga aos dependentes habilitados na Previdencia, '
             || 'independentemente de inventario (Lei 6.858/1980, art. 1o; Lei 4.090/1962, art. '
             || '3o). Tratar falecimento como perda da verba e erro grave com a familia.', v_dev);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Falecimento manteve o 13o proporcional devido (%s avos, R$ %s), para '
             || 'encaminhamento aos dependentes (Lei 6.858/1980).', (v_out->>'avos'), v_dev);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_dec13_061()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_cr jsonb; v_sem jsonb; v_dev_cr numeric; v_dev_sem numeric;
  v_tipos text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Apurar o 13o de uma rescisao por CULPA RECIPROCA';
  r.esperado := 'Metade do 13o proporcional (CLT, art. 484; Sumula 14 do TST)';

  SELECT string_agg(DISTINCT e.enumlabel, ', ') INTO v_tipos
  FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
  WHERE t.typname LIKE '%rescisao%' AND e.enumlabel ILIKE '%RECIPROC%';

  BEGIN
    v_cr := public.qa_caso_dec13_rescisao_motivo('CULPA_RECIPROCA', 6, 0.5, '90000005991', 'QA Culpa Reciproca');
  EXCEPTION WHEN OTHERS THEN
    v_cr := jsonb_build_object('erro', SQLERRM);
  END;
  v_sem := public.qa_caso_dec13_rescisao_motivo('DISPENSA_SEM_JUSTA_CAUSA', 6, 1.0, '90000006025', 'QA Sem Justa Causa');

  v_dev_cr  := COALESCE((v_cr->>'devido')::numeric, -1);
  v_dev_sem := COALESCE((v_sem->>'devido')::numeric, -1);

  IF v_cr ? 'erro' THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a culpa reciproca nao existe como motivo de rescisao (%s). O art. '
             || '484 da CLT e a Sumula 14 do TST mandam pagar METADE das verbas da dispensa sem '
             || 'justa causa, o 13o proporcional incluido. Sem esse motivo, o operador acaba '
             || 'lancando como justa causa (paga zero, e devedor) ou como dispensa comum (paga '
             || 'inteiro, e perde dinheiro). Detalhe tecnico: %s',
             coalesce('motivos com "reciproca" no sistema: ' || v_tipos, 'nenhum motivo de culpa reciproca cadastrado'),
             (v_cr->>'erro'));
  ELSIF v_dev_sem <= 0 OR abs(v_dev_cr - round(v_dev_sem / 2, 2)) > 0.02 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a culpa reciproca pagou R$ %s, quando deveria pagar metade da '
             || 'dispensa sem justa causa (R$ %s / 2 = R$ %s) — CLT, art. 484 e Sumula 14 do TST.',
             v_dev_cr, v_dev_sem, round(v_dev_sem / 2, 2));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Culpa reciproca paga metade: R$ %s contra R$ %s da dispensa sem justa '
             || 'causa (Sumula 14 do TST).', v_dev_cr, v_dev_sem);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-022: Sumula 347 — media FISICA das horas extras ─────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_022()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_fn boolean; v_src text; v_param boolean; v_marca boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): existe media FISICA de horas extras no 13o?';
  r.esperado := 'Quantidade de horas do ano dividida pelos meses, multiplicada pelo valor da hora ATUAL (Sumula 347 do TST)';

  SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                  WHERE n.nspname='public' AND p.proname='decimo_terceiro_media_horas_extras')
    INTO v_fn;
  SELECT prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='decimo_terceiro_media_horas_extras';
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='decimo_terceiro_config'
                    AND column_name='media_horas_extras') INTO v_param;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='folha_rubricas'
                    AND column_name='he_do_ponto') INTO v_marca;

  IF NOT v_fn OR NOT v_param THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a media de horas extras do 13o nao e fisica (funcao: %s; escolha '
             || 'do criterio: %s). A Sumula 347 do TST manda somar a QUANTIDADE de horas extras '
             || 'do ano, dividir pelos meses e multiplicar pelo valor da hora VIGENTE. Usar a '
             || 'media dos valores pagos paga a menos sempre que houve aumento salarial no ano — '
             || 'e o aumento e a regra, nao a excecao.',
             CASE WHEN v_fn THEN 'existe' ELSE 'nao existe' END,
             CASE WHEN v_param THEN 'existe' ELSE 'nao existe' END);
  ELSIF v_src NOT ILIKE '%valor_hora%' AND v_src NOT ILIKE '%salario%' THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a funcao de media de horas extras existe, mas nao multiplica pelo valor '
             || 'da hora atual — sem isso ela nao cumpre a Sumula 347 do TST.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Media fisica implementada (decimo_terceiro_media_horas_extras), criterio '
             || 'escolhivel pela empresa e rubricas de HE do ponto marcadas: %s.',
             CASE WHEN v_marca THEN 'sim' ELSE 'marcador ausente' END);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-023: adicionais habituais integram a base ───────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_023()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_col text; v_fora text; v_total int; v_existentes int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Conferir se as rubricas de adicional habitual entram na base do 13o';
  r.esperado := 'Noturno, insalubridade e periculosidade marcados como integrantes (Sumulas 60, 132 e 139 do TST)';

  SELECT column_name INTO v_col FROM information_schema.columns
   WHERE table_schema='public' AND table_name='folha_rubricas'
     AND (column_name ILIKE '%13%' OR column_name ILIKE '%decimo%') LIMIT 1;

  IF v_col IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o cadastro de rubricas nao tem marcacao de "integra o 13o". Sem ela, '
             || 'nao ha como saber se adicional noturno, insalubridade e periculosidade entram '
             || 'na base — e eles entram, por habitualidade (Sumulas 60, 132 e 139 do TST).';
    RETURN r;
  END IF;

  EXECUTE format(
    'SELECT count(*) FROM public.folha_rubricas
      WHERE tipo = ''PROVENTO''
        AND (descricao ILIKE ''%%noturn%%'' OR descricao ILIKE ''%%insalubr%%''
             OR descricao ILIKE ''%%periculos%%'')') INTO v_existentes;

  IF COALESCE(v_existentes, 0) = 0 THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Nao ha rubrica de adicional noturno, insalubridade ou periculosidade cadastrada '
             || 'nesta base — nao ha o que conferir. O caso volta a valer assim que a empresa '
             || 'cadastrar esses adicionais, e ai eles precisam entrar na base do 13o (Sumulas '
             || '60, 132 e 139 do TST).';
    RETURN r;
  END IF;

  EXECUTE format(
    'SELECT count(*), string_agg(descricao, '', '') FROM public.folha_rubricas
      WHERE tipo = ''PROVENTO''
        AND (descricao ILIKE ''%%noturn%%'' OR descricao ILIKE ''%%insalubr%%''
             OR descricao ILIKE ''%%periculos%%'')
        AND COALESCE(%I, false) = false', v_col)
  INTO v_total, v_fora;

  IF v_total > 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: %s rubrica(s) de adicional habitual estao FORA da base do 13o '
             || '(%s). Adicional noturno (Sumula 60), de periculosidade (Sumula 132) e de '
             || 'insalubridade (Sumula 139) integram a remuneracao e, por habitualidade, a base '
             || 'do 13o. Fora da base, o 13o sai a menor sem ninguem perceber. Correcao: marcar '
             || 'essas rubricas como integrantes no cadastro.', v_total, v_fora);
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Nenhuma rubrica de adicional habitual ficou fora da base do 13o (marcador "'
             || v_col || '" no cadastro de rubricas).';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-034: as duas politicas do adiantamento ──────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_034()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_check text; v_opcoes text; v_le boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a empresa escolhe a base do adiantamento?';
  r.esperado := 'As duas leituras da Lei 4.749/1965, art. 2o, disponiveis e com efeito no calculo';

  SELECT pg_get_constraintdef(c.oid) INTO v_check
  FROM pg_constraint c
  WHERE c.conrelid = 'public.decimo_terceiro_config'::regclass AND c.contype = 'c'
    AND pg_get_constraintdef(c.oid) ILIKE '%adiantamento_base%';

  SELECT prosrc ILIKE '%adiantamento_base%' INTO v_le
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='decimo_terceiro_calcular';

  v_opcoes := coalesce(v_check, 'sem parametro');

  IF v_check IS NULL
     OR v_check NOT ILIKE '%remuneracao_mes_anterior%'
     OR v_check NOT ILIKE '%proporcional_apurado%' THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: nao ha escolha registrada da base do adiantamento (%s). A Lei '
             || '4.749/1965, art. 2o, manda adiantar metade do salario do mes anterior; a pratica '
             || 'consolidada admite metade do 13o apurado. As duas sao defensaveis, e por isso a '
             || 'escolha e da empresa — mas precisa ficar REGISTRADA e valer igual para todos no '
             || 'ano, senao cada calculo vira uma interpretacao.', v_opcoes);
  ELSIF NOT COALESCE(v_le, false) THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o parametro da politica do adiantamento existe, mas o calculo da parcela '
             || 'nao o le — escolha sem efeito e pior que escolha nenhuma, porque parece cumprida.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Politica do adiantamento registrada e lida pelo calculo (%s).', v_opcoes);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-035: pedido fora de janeiro e avisado ───────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_035()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_src text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o pedido fora de janeiro e sinalizado?';
  r.esperado := 'Aviso de pedido fora da janela do §2o do art. 2o da Lei 4.749/1965 — sem recusa silenciosa';

  SELECT prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='decimo_terceiro_adiantamento_nas_ferias';

  IF v_src IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nao existe rotina de adiantamento do 13o junto as ferias. O §2o do art. '
             || '2o da Lei 4.749/1965 da esse direito a quem requer em janeiro, e sem rotina o '
             || 'pedido se perde entre planilhas.';
  ELSIF v_src NOT ILIKE '%janeiro%' AND v_src NOT ILIKE '%fora_de_janeiro%' THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a rotina de adiantamento nas ferias nao distingue o pedido feito em '
             || 'JANEIRO dos demais. Fora da janela do §2o o empregador nao e obrigado a antecipar '
             || '— o sistema deve avisar e deixar a decisao registrada, nunca recusar em silencio '
             || 'nem pagar sem rastro.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'A rotina de adiantamento nas ferias separa os pedidos de janeiro e avisa sobre os '
             || 'que ficaram fora da janela do §2o (Lei 4.749/1965).';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-052: provisao do desligado e revertida ──────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_052()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_src text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a provisao reverte quando o vinculo termina?';
  r.esperado := 'Provisao do desligado revertida na competencia seguinte, e conciliacao fechando';

  SELECT prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='decimo_terceiro_provisionar';

  IF v_src IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nao ha provisao propria do 13o. Sem ela, a despesa aparece inteira em '
             || 'dezembro e o resultado dos outros onze meses sai distorcido (regime de '
             || 'competencia — Lei 6.404/1976, art. 177).';
  ELSIF v_src NOT ILIKE '%revert%' OR v_src NOT ILIKE '%desligad%' THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a provisao do 13o nao reverte a parcela de quem foi desligado. O 13o '
             || 'desses ja foi quitado na rescisao; manter a provisao deixa no balanco uma '
             || 'obrigacao que nao existe mais, e a conciliacao nunca fecha.';
  ELSIF v_src NOT ILIKE '%cpf%' THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a reversao da provisao nao casa o colaborador pelo CPF. O identificador '
             || 'livre de colaborador difere entre modulos, entao a reversao encontra zero linhas '
             || 'e falha em silencio — o pior tipo de erro contabil.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'A provisao do 13o reverte a parcela dos desligados, casando o vinculo pelo CPF.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-072: o lote nao duplica parcela ─────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_072()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_ten uuid := public.qa_sandbox_tenant_id();
  v_ano int := extract(year from CURRENT_DATE)::int - 1;
  v_cpf text := '90000006106'; v_adm uuid;
  v_r1 jsonb; v_r2 jsonb; v_vivas int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Processar o lote da 1a parcela e, em seguida, processar o MESMO lote de novo';
  r.esperado := 'A segunda passada nao cria parcela nova e informa quantos ja existiam';

  DELETE FROM public.folha_13_calculo WHERE tenant_id = v_ten AND ano = v_ano
     AND regexp_replace(coalesce(colaborador_cpf,''),'\D','','g') = v_cpf;
  DELETE FROM public.admissoes WHERE tenant_id = v_ten AND cpf = v_cpf;
  INSERT INTO public.admissoes (tenant_id, nome_completo, cpf, cargo, salario, data_admissao, status)
  VALUES (v_ten, 'QA Lote Duplo', v_cpf, 'QA', 2500, make_date(v_ano - 1, 3, 1), 'concluido')
  RETURNING id INTO v_adm;

  v_r1 := public.decimo_terceiro_lote(v_ten, v_ano, 1, NULL);
  v_r2 := public.decimo_terceiro_lote(v_ten, v_ano, 1, NULL);

  SELECT count(*) INTO v_vivas FROM public.folha_13_calculo
   WHERE tenant_id = v_ten AND ano = v_ano AND parcela = 1
     AND regexp_replace(coalesce(colaborador_cpf,''),'\D','','g') = v_cpf
     AND status <> 'cancelado';

  DELETE FROM public.folha_13_calculo WHERE tenant_id = v_ten AND ano = v_ano
     AND regexp_replace(coalesce(colaborador_cpf,''),'\D','','g') = v_cpf;
  DELETE FROM public.admissoes WHERE id = v_adm;

  IF v_vivas > 1 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: rodar o lote duas vezes criou %s parcelas vivas para o mesmo '
             || 'colaborador. O lote e clicado por gente sob pressao de prazo e sera clicado duas '
             || 'vezes — duplicar parcela vira pagamento em dobro. Retornos: %s / %s',
             v_vivas, v_r1, v_r2);
  ELSIF COALESCE((v_r2->>'ja_calculados')::int, (v_r2->>'ja_existiam')::int, 0) = 0
        AND COALESCE((v_r2->>'calculados')::int, 0) > 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a segunda passada nao duplicou, mas tambem nao informa que pulou '
             || 'ninguem (%s) — quem processa fica sem saber se o lote rodou. Retorno precisa '
             || 'dizer quantos foram calculados e quantos ja existiam.', v_r2);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Lote idempotente: uma unica parcela viva apos duas passadas; a segunda '
             || 'informou o que pulou (%s).', v_r2);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── Registro das rotinas no motor (código -> função) ──────────────────
INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
  ('DEC13-004','qa_caso_dec13_004',true), ('DEC13-005','qa_caso_dec13_005',true),
  ('DEC13-006','qa_caso_dec13_006',true), ('DEC13-022','qa_caso_dec13_022',true),
  ('DEC13-023','qa_caso_dec13_023',true), ('DEC13-034','qa_caso_dec13_034',true),
  ('DEC13-035','qa_caso_dec13_035',true), ('DEC13-043','qa_caso_dec13_043',true),
  ('DEC13-052','qa_caso_dec13_052',true), ('DEC13-061','qa_caso_dec13_061',true),
  ('DEC13-062','qa_caso_dec13_062',true), ('DEC13-063','qa_caso_dec13_063',true),
  ('DEC13-072','qa_caso_dec13_072',true), ('DEC13-073','qa_caso_dec13_073',true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;


-- ══════════ Ajuste que vem DEPOIS da 1a leva ══════════
-- A 1a leva traz a sonda do DEC13-070 na versao escrita para o banco
-- antigo, que gravava status 'pago' sem data de pagamento — a trava da
-- Entrega 2 recusa isso, com razao. A versao ajustada precisa vir por
-- ultimo, senao a leva anterior a sobrescreve.
-- ── 2. DEC13-070: a sonda informa a data de pagamento ─────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_070()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_id uuid; v_alterou boolean := false; v_trg text;
BEGIN
  -- A sonda grava e NÃO desfaz (padrão desta família). Com a unicidade
  -- da Entrega 2, rodar duas vezes colidiria com a própria linha da
  -- rodada anterior — então ela limpa o próprio rastro antes.
  DELETE FROM public.folha_13_calculo
   WHERE tenant_id = public.qa_sandbox_tenant_id()
     AND colaborador_id = 'qa-dec13-070';

  -- Pago exige data de pagamento desde a Entrega 2 (CHECK
  -- folha_13_calculo_pagamento_ck) — a sonda informa, como a tela faz.
  INSERT INTO public.folha_13_calculo
    (tenant_id, ano, colaborador_id, colaborador_nome, colaborador_cpf, parcela,
     valor_bruto, total_liquido, status, data_pagamento)
  VALUES (public.qa_sandbox_tenant_id(), extract(year from CURRENT_DATE)::int,
          'qa-dec13-070', 'QA Pago Editado', '00000000070', 2, 3000, 2500,
          'pago', CURRENT_DATE)
  RETURNING id INTO v_id;

  r.passo_ordem := 1;
  r.passo_acao := 'Editar diretamente o valor bruto de um cálculo com status PAGO';
  r.esperado := 'Bloqueado — valor pago só muda por reabertura com motivo, dupla aprovação e diferença';
  BEGIN
    UPDATE public.folha_13_calculo SET valor_bruto = 9999 WHERE id = v_id;
    SELECT (valor_bruto = 9999) INTO v_alterou FROM public.folha_13_calculo WHERE id = v_id;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_alterou := false; END;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: existe trilha de alteração na tabela do 13º?';
  r.esperado := 'Gatilho de auditoria registrando antes/depois (RNF-004: log imutável)';
  SELECT string_agg(DISTINCT t.tgname, ', ') INTO v_trg
  FROM pg_trigger t
  WHERE t.tgrelid = 'public.folha_13_calculo'::regclass AND NOT t.tgisinternal
    AND t.tgname NOT ILIKE '%updated_at%' AND t.tgname NOT ILIKE 'qa\_%';

  IF v_alterou AND v_trg IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: um cálculo PAGO foi editado em silêncio — o valor bruto mudou de 3.000 '
             || 'para 9.999 sem bloqueio, sem justificativa, sem aprovação e sem trilha. '
             || 'Correção: trava de UPDATE para status pago/fechado + fluxo de reabertura '
             || '(RF-007 do documento).';
  ELSIF NOT v_alterou THEN
    r.situacao := 'passou';
    r.obtido := format('A edição direta do cálculo pago foi recusada pela trava do banco%s.',
                       CASE WHEN v_trg IS NULL THEN '' ELSE ' (gatilhos: ' || v_trg || ')' END);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Alteração registrada em trilha (%s) — conferir se guarda antes/depois.', v_trg);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- A mesma historia da sonda do DEC13-050: a 1a leva a traz na versao
-- frouxa (aceitava qualquer funcao com "anual" no texto e so procurava
-- unicidade entre constraints, entao passava de graca). A versao que
-- cobra as funcoes pelo nome precisa vir DEPOIS dela.
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_050()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_unq       text;
  v_validar   boolean;
  v_gerar     boolean;
  v_anual     boolean;
  v_faltando  text[] := ARRAY[]::text[];
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a folha anual do 13º tem eventos, validação prévia e anti-duplicidade?';
  r.esperado := 'S-1200 (apuração anual, indApuracao=2) e S-1210 (pagamentos), validação antes do envio e unicidade por origem';

  IF to_regclass('public.esocial_transmissoes') IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A tabela de transmissões do eSocial não existe nesta base.';
    RETURN r;
  END IF;

  -- unicidade: vale constraint OU índice único (o índice parcial é o que
  -- permite refazer o evento depois de um erro ou cancelamento)
  SELECT string_agg(nome, ', ') INTO v_unq FROM (
    SELECT conname AS nome FROM pg_constraint
     WHERE conrelid = 'public.esocial_transmissoes'::regclass AND contype = 'u'
    UNION
    SELECT c.relname FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
     WHERE i.indrelid = 'public.esocial_transmissoes'::regclass
       AND i.indisunique AND NOT i.indisprimary
  ) u;

  SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'decimo_terceiro_esocial_validar')
    INTO v_validar;
  SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'decimo_terceiro_esocial_gerar')
    INTO v_gerar;
  SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'decimo_terceiro_esocial_gerar'
                    AND p.prosrc LIKE '%indApuracao>2<%')
    INTO v_anual;

  IF NOT v_validar THEN v_faltando := array_append(v_faltando, 'validação prévia do 13º (decimo_terceiro_esocial_validar)'); END IF;
  IF NOT v_gerar   THEN v_faltando := array_append(v_faltando, 'montagem dos eventos (decimo_terceiro_esocial_gerar)'); END IF;
  IF v_gerar AND NOT v_anual THEN v_faltando := array_append(v_faltando, 'apuração ANUAL no S-1200 (indApuracao = 2)'); END IF;
  IF v_unq IS NULL THEN v_faltando := array_append(v_faltando, 'anti-duplicidade em esocial_transmissoes'); END IF;

  IF array_length(v_faltando, 1) IS NOT NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO (terceiro da série ADM-093/FERIAS-081, agora pela folha ANUAL): falta '
             || array_to_string(v_faltando, '; ') || '. A competência anual tem regra própria de '
             || 'retificação e prazo; sem os eventos, o 13º pago não existe para o governo — e a '
             || 'DCTFWeb de dezembro não fecha com a folha. Correção: geração dos dois eventos no '
             || 'fechamento (apuração e pagamento), chave natural (vínculo + tipo + competência '
             || 'anual) e tradução de rejeição em instrução, nunca reenvio às cegas.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Proteções presentes: validação prévia e montagem do S-1200 anual e do S-1210, com unicidade (%s).', v_unq);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ════════════════════════════════════════════════════════════════════
-- CONFERENCIA FINAL — peca por peca (o editor so mostra este resultado)
-- ════════════════════════════════════════════════════════════════════
WITH pecas AS MATERIALIZED (
    SELECT * FROM (VALUES
      -- (ordem, script, peca, especie, nome)
      (1,'script_13o_apuracao_avos_e_medias.sql',        'apuracao dos avos (Lei 4.090)',        'funcao','decimo_terceiro_avos'),
      (1,'script_13o_apuracao_avos_e_medias.sql',        'media das variaveis do ano',            'funcao','decimo_terceiro_media_variaveis'),
      (1,'script_13o_apuracao_avos_e_medias.sql',        'parametros do 13o por empresa',         'tabela','decimo_terceiro_config'),
      (2,'script_13o_entrega2_estrutura_encargos_lote.sql','INSS do 13o no banco',                'funcao','decimo_terceiro_inss'),
      (2,'script_13o_entrega2_estrutura_encargos_lote.sql','IRRF do 13o no banco',                'funcao','decimo_terceiro_irrf'),
      (2,'script_13o_entrega2_estrutura_encargos_lote.sql','processamento em lote',               'funcao','decimo_terceiro_lote'),
      (2,'script_13o_entrega2_estrutura_encargos_lote.sql','prazo legal (30/11 e 20/12)',         'funcao','decimo_terceiro_prazo_legal'),
      (2,'script_13o_entrega2_estrutura_encargos_lote.sql','reabertura com dupla aprovacao',      'funcao','decimo_terceiro_reabrir'),
      (2,'script_13o_entrega2_estrutura_encargos_lote.sql','uma parcela viva por colaborador',    'indice','folha_13_calculo_parcela_viva_uq'),
      (3,'script_13o_adiantamento_e_media_sumula347.sql', 'media fisica das horas extras (S. 347)','funcao','decimo_terceiro_media_horas_extras'),
      (4,'script_13o_entrega3_alertas_prazos.sql',        'varredura de alertas de prazo',        'funcao','decimo_terceiro_alertas_varrer'),
      (4,'script_13o_entrega3_alertas_prazos.sql',        'alerta vira Plano de Acao',            'funcao','decimo_terceiro_alerta_gerar_acao'),
      (5,'script_13o_entrega4_provisao_rescisao_ferias.sql','provisao contabil mensal',           'funcao','decimo_terceiro_provisionar'),
      (5,'script_13o_entrega4_provisao_rescisao_ferias.sql','conciliacao provisionado x pago',    'funcao','decimo_terceiro_conciliar_provisao'),
      (5,'script_13o_entrega4_provisao_rescisao_ferias.sql','13o da rescisao',                    'funcao','decimo_terceiro_da_rescisao'),
      (5,'script_13o_entrega4_provisao_rescisao_ferias.sql','adiantamento junto as ferias',       'funcao','decimo_terceiro_adiantamento_nas_ferias'),
      (6,'script_13o_entrega5_esocial.sql',               'validacao previa do eSocial',          'funcao','decimo_terceiro_esocial_validar'),
      (6,'script_13o_entrega5_esocial.sql',               'montagem do S-1200 e S-1210',          'funcao','decimo_terceiro_esocial_gerar'),
      (8,'script_13o_culpa_reciproca.sql',                'trava dos dois erros da rescisao',     'funcao','decimo_terceiro_rescisao_valida')
    ) AS t(ordem, script, peca, especie, nome)
)
SELECT p.ordem AS passo, p.peca AS item,
       CASE WHEN CASE p.especie
              WHEN 'funcao' THEN EXISTS (SELECT 1 FROM pg_proc pr JOIN pg_namespace n ON n.oid=pr.pronamespace
                                          WHERE n.nspname='public' AND pr.proname = p.nome)
              WHEN 'tabela' THEN to_regclass('public.' || p.nome) IS NOT NULL
              WHEN 'indice' THEN EXISTS (SELECT 1 FROM pg_class WHERE relname = p.nome AND relkind='i')
            END THEN 'OK' ELSE 'FALTA' END AS situacao,
       CASE WHEN CASE p.especie
              WHEN 'funcao' THEN EXISTS (SELECT 1 FROM pg_proc pr JOIN pg_namespace n ON n.oid=pr.pronamespace
                                          WHERE n.nspname='public' AND pr.proname = p.nome)
              WHEN 'tabela' THEN to_regclass('public.' || p.nome) IS NOT NULL
              WHEN 'indice' THEN EXISTS (SELECT 1 FROM pg_class WHERE relname = p.nome AND relkind='i')
            END THEN NULL ELSE 'cole o ' || p.script END AS erro_tecnico
  FROM pecas p
 UNION ALL
SELECT 3, 'a politica do adiantamento vale no calculo',
       CASE WHEN position('adiantamento_base' in pr.prosrc) > 0 THEN 'OK' ELSE 'FALTA' END,
       CASE WHEN position('adiantamento_base' in pr.prosrc) > 0 THEN NULL
            ELSE 'cole o script_13o_adiantamento_e_media_sumula347.sql (sempre DEPOIS do script 2)' END
  FROM pg_proc pr JOIN pg_namespace n ON n.oid=pr.pronamespace
 WHERE n.nspname='public' AND pr.proname='decimo_terceiro_calcular'
 UNION ALL
SELECT 7, 'aviso previo indenizado projeta o tempo (CLT 487 §1o)',
       CASE WHEN position('v_fim_contrato' in pr.prosrc) > 0 THEN 'OK' ELSE 'FALTA' END,
       CASE WHEN position('v_fim_contrato' in pr.prosrc) > 0 THEN NULL
            ELSE 'cole o script_13o_testes_leva2_e_correcoes.sql' END
  FROM pg_proc pr JOIN pg_namespace n ON n.oid=pr.pronamespace
 WHERE n.nspname='public' AND pr.proname='decimo_terceiro_avos'
 UNION ALL
SELECT 7, 'acidente de trabalho nao derruba avo (Sumula 46 TST)',
       CASE WHEN position('''B31'', ''B32''' in pr.prosrc) > 0 THEN 'OK' ELSE 'FALTA' END,
       CASE WHEN position('''B31'', ''B32''' in pr.prosrc) > 0 THEN NULL
            ELSE 'cole o script_13o_testes_leva2_e_correcoes.sql' END
  FROM pg_proc pr JOIN pg_namespace n ON n.oid=pr.pronamespace
 WHERE n.nspname='public' AND pr.proname='decimo_terceiro_avos'
 UNION ALL
SELECT 7, 'casos de teste documentados (esperado 31)',
       CASE WHEN count(*) >= 31 THEN 'OK' ELSE 'FALTA' END,
       CASE WHEN count(*) >= 31 THEN 'documentados: ' || count(*)::text
            ELSE 'documentados: ' || count(*)::text || ' — cole o script_13o_testes_leva2_e_correcoes.sql' END
  FROM public.qa_casos_teste c JOIN public.qa_modulos m ON m.id = c.modulo_id
 WHERE m.path = 'financeiro/decimo-terceiro'
 UNION ALL
SELECT 7, 'sonda de QA DEC13-070 ajustada a trava de pagamento',
       CASE WHEN position('data_pagamento' in pr.prosrc) > 0 THEN 'OK' ELSE 'FALTA' END,
       CASE WHEN position('data_pagamento' in pr.prosrc) > 0 THEN NULL
            ELSE 'cole o script_13o_corrige_sonda_dec13_070.sql' END
  FROM pg_proc pr JOIN pg_namespace n ON n.oid=pr.pronamespace
 WHERE n.nspname='public' AND pr.proname='qa_caso_dec13_070'
 UNION ALL
SELECT 8, 'motivo CULPA_RECIPROCA no vocabulario de rescisao',
       CASE WHEN EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid
                          WHERE t.typname='rescisao_tipo' AND e.enumlabel='CULPA_RECIPROCA')
            THEN 'OK' ELSE 'FALTA' END,
       CASE WHEN EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid
                          WHERE t.typname='rescisao_tipo' AND e.enumlabel='CULPA_RECIPROCA')
            THEN NULL ELSE 'cole o script_13o_culpa_reciproca.sql' END
 UNION ALL
SELECT 9, 'varredura diaria de alertas agendada',
       CASE WHEN NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_cron') THEN 'INFORMATIVO'
            WHEN EXISTS (SELECT 1 FROM cron.job WHERE jobname='decimo_terceiro_alertas_diario') THEN 'OK'
            ELSE 'FALTA' END,
       CASE WHEN NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_cron')
            THEN 'pg_cron nao instalado: a varredura roda pelo botao da tela'
            WHEN EXISTS (SELECT 1 FROM cron.job WHERE jobname='decimo_terceiro_alertas_diario')
            THEN NULL
            ELSE 'rode: SELECT cron.schedule(''decimo_terceiro_alertas_diario'', ''25 6 * * *'', ''SELECT public.decimo_terceiro_alertas_varrer();'');' END
 ORDER BY 3 DESC, 1, 2;
