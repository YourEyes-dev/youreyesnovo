-- =========================================================
-- 13º Salário — Entrega 3: prazos, alertas e Plano de Ação
--
-- PROBLEMA: o controle de prazos da folha não conhecia o 13º. O CHECK de
-- folha_alertas_prazo só admitia os tipos mensais, então não havia onde
-- registrar "1ª parcela até 30/11" nem "2ª até 20/12". Pior: a tabela era
-- alimentada SÓ PELA TELA — nenhuma função do banco gerava ou conferia
-- alerta algum. Quem não abrisse a aba no mês certo não era avisado de
-- nada, e um 13º calculado com competências sem variáveis lançadas saía
-- menor em silêncio. Perder o prazo da Lei 4.749/1965 é multa; pagar a
-- menos é diferença que vira passivo.
--
-- ENTREGA:
--   1) o vocabulário de prazos passa a conhecer o 13º;
--   2) folha_alertas_prazo ganha severidade, empresa e o vínculo com a
--      ação, além de unicidade — o mesmo alerta não nasce duas vezes;
--   3) decimo_terceiro_alertas_varrer() — uma VARREDURA no banco, não na
--      tela: prazo das duas parcelas (D-30/15/7 e D-15/7/3, mais o
--      vencido), base de médias incompleta e afastamento a validar;
--   4) decimo_terceiro_alerta_gerar_acao() — converte o alerta em ação no
--      Plano de Ação com 5W2H, espelhando Férias e Ponto;
--   5) agendamento diário por pg_cron, como as demais varreduras da casa.
--
-- DECISÃO, espelhando Férias: ação AUTOMÁTICA só no crítico (parcela
-- vencida e véspera do prazo). Os demais viram ação sob demanda, para o
-- Plano de Ação não virar caixa de spam que ninguém lê.
--
-- Requisitos YE-DP-13-001: RF-006, RN-003, RN-004, seções 14 e 15.
-- Casos: DEC13-021 (base incompleta), DEC13-030 (prazo das parcelas).
-- =========================================================

SET lock_timeout = '10s';

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
