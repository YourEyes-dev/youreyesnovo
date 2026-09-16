-- =========================================================
-- SCRIPT DE ENTREGA — 13º Salário, Entrega 4
-- Provisão contábil, rescisão e adiantamento nas férias
--
-- PRÉ-REQUISITO: rodar depois dos scripts das Entregas 1, 2 e 3 e do
-- script do adiantamento/Súmula 347.
--
-- O QUE ESTE SCRIPT FAZ:
--   * provisão do 13º que se alimenta sozinha: 1/12 por mês, com INSS
--     patronal e FGTS, revertendo a de quem foi desligado. Até aqui a
--     tabela existia e NENHUMA função a alimentava — a provisão era
--     lançada à mão, quando alguém lembrava;
--   * conciliação provisionado x pago, que é o que o contador pede no
--     fechamento;
--   * a regra da rescisão passa a viver no banco: justa causa não gera
--     13º proporcional (antes, R$ 1.000 de 13º em justa causa entrava
--     sem resistência, porque a regra vivia só na tela);
--   * apuração do 13º da rescisão, deduzindo o adiantamento já pago;
--   * o lote anual passa a PULAR quem foi desligado antes do prazo da
--     parcela — as verbas dele saem na rescisão, não na folha de
--     dezembro (antes, receberia duas vezes);
--   * o "adiantar 13º" da programação de férias deixa de ser botão
--     órfão: gera a 1ª parcela com a data-limite na véspera do gozo
--     (Lei 4.749/1965, art. 2º, § 2º), registrando quando o pedido veio
--     fora de janeiro.
--
-- ATENÇÃO: a trava da rescisão passa a RECUSAR gravação de rescisão por
-- justa causa com 13º proporcional maior que zero. Se houver rotina que
-- grave assim hoje, ela passará a falhar — o que é o objetivo, mas vale
-- avisar quem opera.
--
-- O QUE NÃO FAZ: não altera nem apaga cálculo, provisão ou rescisão já
-- gravados. As funções de provisão só rodam quando alguém as chama.
--
-- Idempotente. Rodar no SQL Editor de PRODUÇÃO, de uma vez só.
-- =========================================================

SET lock_timeout = '10s';

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

-- ── Conferência final ─────────────────────────────────────────────────
WITH itens AS MATERIALIZED (
    SELECT * FROM (VALUES
        ('funcao de provisao mensal',          'funcao',  'decimo_terceiro_provisionar'),
        ('funcao de conciliacao provisao x pago','funcao', 'decimo_terceiro_conciliar_provisao'),
        ('funcao do 13o na rescisao',          'funcao',  'decimo_terceiro_da_rescisao'),
        ('funcao do adiantamento nas ferias',  'funcao',  'decimo_terceiro_adiantamento_nas_ferias'),
        ('trava da justa causa na rescisao',   'gatilho', 'trg_decimo_terceiro_rescisao_valida'),
        ('unicidade da provisao por competencia','indice','folha_provisoes_unica')
    ) AS t(item, especie, nome)
)
SELECT i.item,
       CASE WHEN CASE i.especie
              WHEN 'funcao'  THEN EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                                           WHERE n.nspname='public' AND p.proname=i.nome)
              WHEN 'gatilho' THEN EXISTS (SELECT 1 FROM pg_trigger WHERE tgname=i.nome AND NOT tgisinternal)
              WHEN 'indice'  THEN EXISTS (SELECT 1 FROM pg_class WHERE relname=i.nome AND relkind='i')
            END THEN 'OK' ELSE 'FALTOU' END AS situacao,
       NULL::text AS erro_tecnico
  FROM itens i
 UNION ALL
SELECT 'o lote pula quem foi desligado',
       CASE WHEN position('desligados_na_rescisao' in p.prosrc) > 0 THEN 'OK' ELSE 'FALTOU' END,
       CASE WHEN position('desligados_na_rescisao' in p.prosrc) > 0 THEN NULL
            ELSE 'decimo_terceiro_lote nao foi substituida' END
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='decimo_terceiro_lote'
 UNION ALL
SELECT 'rescisoes por justa causa com 13o (a corrigir)',
       CASE WHEN count(*) = 0 THEN 'OK' ELSE 'RESOLVER' END,
       CASE WHEN count(*) = 0 THEN NULL
            ELSE count(*)::text || ' rescisao(oes) ja gravada(s) com justa causa e 13o proporcional — '
                 || 'a trava vale para o que entrar de agora em diante; estas ficam para conferencia manual' END
  FROM public.folha_rescisoes
 WHERE tipo_rescisao = 'DISPENSA_COM_JUSTA_CAUSA'
   AND COALESCE(decimo_terceiro_proporcional, 0) > 0
 ORDER BY 2 DESC, 1;
