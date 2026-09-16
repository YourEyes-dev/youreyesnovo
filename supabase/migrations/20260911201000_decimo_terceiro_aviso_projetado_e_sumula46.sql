-- =========================================================
-- 13º Salário — duas correções de lei encontradas pelos testes novos
--
-- A leva de casos DEC13-004 e DEC13-006 (Documentação de testes) acusou
-- dois pontos em que a apuração dos avos paga MENOS do que a lei manda —
-- e diferença a menos volta como reclamatória, com juros.
--
-- 1) AVISO PRÉVIO INDENIZADO NÃO PROJETAVA (DEC13-004)
--    A apuração parava na data do desligamento. O aviso prévio indenizado
--    integra o tempo de serviço para TODOS os efeitos legais (CLT, art.
--    487, §1º; Súmula 371 do TST; OJ 82 da SDI-1). Desligado em 20/11 com
--    30 dias de aviso, o contrato projeta até 20/12 e dezembro fecha 20
--    dias: o 12º avo é devido. Antes saíam 11.
--
-- 2) ACIDENTE DE TRABALHO TRATADO COMO DOENÇA COMUM (DEC13-006)
--    Todas as espécies previdenciárias (B31, B32, B91, B92) derrubavam
--    avo igual. Mas a Súmula 46 do TST é expressa: as ausências por
--    ACIDENTE DO TRABALHO não são consideradas contra a gratificação
--    natalina, e o art. 4º, parágrafo único, da Lei 8.213/1991 conta o
--    período como tempo de serviço. Agora só as espécies COMUNS (B31
--    auxílio-doença e B32 invalidez) suspendem o avo; as ACIDENTÁRIAS
--    (B91 e B92) contam normalmente.
--
-- Nada disso muda cálculo já fechado: a apuração é somente leitura e o
-- que está aprovado ou pago segue travado. Os cálculos em aberto passam a
-- sair pelo número correto.
--
-- Requisitos YE-DP-13-001: RN-001, RN-008, RN-009. Casos: DEC13-004, DEC13-006.
-- =========================================================

SET lock_timeout = '10s';

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
