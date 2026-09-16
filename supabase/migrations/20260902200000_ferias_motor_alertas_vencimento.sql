-- =========================================================
-- Ferias — motor de alertas de vencimento e risco de dobro (RF-009)
--
-- PROBLEMA: o painel de risco (Governanca/Inteligencia) mostra vencidos e a
-- vencer para quem ENTRA na tela — passivo. O documento YE-DP-FERIAS-001
-- (RF-009) pede um MOTOR: alerta em D-90/60/30, sinaliza o dobro (art. 137)
-- ao vencer o concessivo, estima o custo e leva ao Plano de Acao.
--
-- FONTE: ferias_periodos_aquisitivos (do item 1) — o concessivo e
-- aquisitivo_fim + 12 meses (art. 134). O salario, para estimar o dobro,
-- vem de admissoes por CPF (mesma fonte do Financeiro de Ferias).
--
-- DECISOES DO DONO DO PRODUTO (02/09/2026):
--   • acao no Plano de Acao: automatica so no CRITICO (concessivo vencido /
--     risco de dobro); D-90/60/30 geram acao sob demanda (botao na tela);
--   • disparo: varredura DIARIA (pg_cron) + sob demanda pela tela.
--
-- Caso de teste: RF-009 (familia FERIAS-020/021).
-- =========================================================

SET lock_timeout = '10s';

-- ── 1. Tabela de alertas (espelha ponto_alertas) ──────────────────────────
CREATE TABLE IF NOT EXISTS public.ferias_alertas (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     UUID NOT NULL,
    empresa_id    UUID,
    periodo_id    UUID,             -- ferias_periodos_aquisitivos
    colaborador_cpf  TEXT,
    colaborador_nome TEXT,
    colaborador_id   UUID,

    aquisitivo_fim   DATE,
    concessivo_fim   DATE,          -- data-limite para conceder (art. 134)
    dias_para_vencer INTEGER,

    -- 'concessivo_a_vencer' (D-90/60/30) | 'risco_dobro' (vencido)
    tipo   TEXT NOT NULL,
    -- marco atingido: d90 | d60 | d30 | vencido — um alerta por marco/periodo
    faixa  TEXT NOT NULL,
    severidade TEXT NOT NULL DEFAULT 'media',   -- media | alta | critica

    titulo     TEXT NOT NULL,
    descricao  TEXT,
    custo_estimado NUMERIC(14,2),   -- so no risco de dobro, quando ha salario

    plano_acao_id UUID,
    resolvido   BOOLEAN NOT NULL DEFAULT false,
    resolvido_em TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- idempotencia: um alerta por marco por periodo
    CONSTRAINT ferias_alerta_unico UNIQUE (tenant_id, periodo_id, faixa)
);

CREATE INDEX IF NOT EXISTS idx_ferias_alertas_tenant ON public.ferias_alertas (tenant_id, resolvido);
CREATE INDEX IF NOT EXISTS idx_ferias_alertas_venc   ON public.ferias_alertas (tenant_id, concessivo_fim);

ALTER TABLE public.ferias_alertas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "ferias_alertas por tenant" ON public.ferias_alertas;
CREATE POLICY "ferias_alertas por tenant"
ON public.ferias_alertas FOR ALL TO authenticated
USING (tenant_id = public.get_user_tenant_id())
WITH CHECK (tenant_id = public.get_user_tenant_id());

-- ── 2. Converter um alerta em acao no Plano de Acao (5W2H) ─────────────────
-- Espelha ponto_alerta_gerar_acao. Idempotente: um alerta -> uma acao.
CREATE OR REPLACE FUNCTION public.ferias_alerta_gerar_acao(
    p_alerta_id       UUID,
    p_responsavel_id  UUID  DEFAULT NULL,
    p_responsavel_nome TEXT DEFAULT NULL,
    p_prazo_dias      INTEGER DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
    a      RECORD;
    v_grav int; v_urg int; v_tend int := 4;
    v_prio public.acao_gut_prioridade;
    v_prazo int;
    v_onde text;
    v_id   uuid;
BEGIN
    SELECT * INTO a FROM public.ferias_alertas WHERE id = p_alerta_id;
    IF NOT FOUND THEN RETURN NULL; END IF;
    IF a.plano_acao_id IS NOT NULL THEN RETURN a.plano_acao_id; END IF;

    v_grav := CASE a.severidade WHEN 'critica' THEN 5 WHEN 'alta' THEN 4 ELSE 3 END;
    v_urg  := v_grav;
    v_prio := (CASE a.severidade WHEN 'critica' THEN 'imediato'
                                 WHEN 'alta' THEN 'urgente' ELSE 'medio' END)::public.acao_gut_prioridade;
    -- prazo: ate o vencimento do concessivo (nunca no passado); vencido -> ja
    v_prazo := COALESCE(p_prazo_dias, GREATEST(a.dias_para_vencer, 0));

    v_onde := COALESCE(
        (SELECT razao_social FROM public.empresa_cadastro WHERE id = a.empresa_id),
        'Ferias — controle de vencimento');

    INSERT INTO public.plano_acoes (
        tenant_id, empresa_id, titulo, descricao,
        porque, onde, como, prazo,
        responsavel_id, responsavel_nome,
        origem_modulo, origem_id, origem_descricao,
        gravidade, urgencia, tendencia, prioridade,
        custo_estimado, tipo, status
    ) VALUES (
        a.tenant_id, a.empresa_id,
        a.titulo,
        COALESCE(a.descricao, a.titulo),
        CASE WHEN a.tipo = 'risco_dobro'
             THEN 'Periodo concessivo vencido: gozo em atraso paga em dobro os dias excedentes (CLT art. 137; Sumula 81 TST).'
             ELSE format('Periodo concessivo a vencer em %s dias (art. 134): conceder antes evita o dobro.', a.dias_para_vencer) END,
        v_onde,
        'Programar e conceder as ferias dentro do concessivo; comprovar a concessao (evidencia).',
        (CURRENT_DATE + v_prazo),
        p_responsavel_id, p_responsavel_nome,
        'ferias', a.id,
        format('Alerta de ferias %s (%s) do colaborador %s', a.tipo, a.severidade,
               COALESCE(a.colaborador_nome, a.colaborador_cpf, '-')),
        v_grav, v_urg, v_tend, v_prio,
        a.custo_estimado,
        CASE WHEN a.tipo = 'risco_dobro' THEN 'corretiva' ELSE 'preventiva' END,
        'pendente'
    )
    RETURNING id INTO v_id;

    UPDATE public.ferias_alertas SET plano_acao_id = v_id, updated_at = now() WHERE id = p_alerta_id;
    RETURN v_id;
END $fn$;

-- ── 3. A varredura: gera/atualiza alertas e a acao critica ────────────────
-- Percorre os periodos ativos com saldo, calcula o marco atingido e registra
-- o alerta da faixa (idempotente pelo UNIQUE). No vencido, cria a acao
-- automaticamente. p_tenant NULL = todos (uso do agendamento diario).
CREATE OR REPLACE FUNCTION public.ferias_alertas_varrer(p_tenant UUID DEFAULT NULL)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
    pr      RECORD;
    v_conc  DATE;
    v_dias  INTEGER;
    v_faixa TEXT;
    v_sev   TEXT;
    v_tipo  TEXT;
    v_sal   NUMERIC;
    v_custo NUMERIC;
    v_titulo TEXT;
    v_alerta_id UUID;
    v_inserido  BOOLEAN;
    v_novos INTEGER := 0;
BEGIN
    FOR pr IN
        SELECT * FROM public.ferias_periodos_aquisitivos
         WHERE status = 'ativo'
           AND dias_saldo > 0
           AND (p_tenant IS NULL OR tenant_id = p_tenant)
    LOOP
        v_conc := (pr.aquisitivo_fim + INTERVAL '12 months')::date;
        v_dias := v_conc - CURRENT_DATE;

        -- Marco atingido (a janela atual). Fora de D-90 nao gera nada.
        IF    v_dias <  0  THEN v_faixa := 'vencido'; v_sev := 'critica'; v_tipo := 'risco_dobro';
        ELSIF v_dias <= 30 THEN v_faixa := 'd30';     v_sev := 'alta';    v_tipo := 'concessivo_a_vencer';
        ELSIF v_dias <= 60 THEN v_faixa := 'd60';     v_sev := 'alta';    v_tipo := 'concessivo_a_vencer';
        ELSIF v_dias <= 90 THEN v_faixa := 'd90';     v_sev := 'media';   v_tipo := 'concessivo_a_vencer';
        ELSE  CONTINUE;
        END IF;

        -- Custo estimado do dobro (so no vencido, quando ha salario).
        v_custo := NULL;
        IF v_tipo = 'risco_dobro' THEN
            SELECT salario INTO v_sal FROM public.admissoes
             WHERE tenant_id = pr.tenant_id
               AND regexp_replace(coalesce(cpf,''),'\D','','g') = regexp_replace(coalesce(pr.colaborador_cpf,''),'\D','','g')
             LIMIT 1;
            IF coalesce(v_sal,0) > 0 THEN
                -- dobro sobre os dias em saldo + 1/3 constitucional
                v_custo := round((v_sal/30.0) * pr.dias_saldo * (1 + 1/3.0), 2);
            END IF;
        END IF;

        v_titulo := CASE v_tipo
            WHEN 'risco_dobro' THEN format('Ferias vencidas (dobro) — %s', COALESCE(pr.colaborador_nome, pr.colaborador_cpf))
            ELSE format('Ferias a vencer em %s dias — %s', v_dias, COALESCE(pr.colaborador_nome, pr.colaborador_cpf))
        END;

        INSERT INTO public.ferias_alertas (
            tenant_id, empresa_id, periodo_id, colaborador_cpf, colaborador_nome, colaborador_id,
            aquisitivo_fim, concessivo_fim, dias_para_vencer, tipo, faixa, severidade,
            titulo, descricao, custo_estimado
        ) VALUES (
            pr.tenant_id, pr.empresa_id, pr.id, pr.colaborador_cpf, pr.colaborador_nome, pr.colaborador_id,
            pr.aquisitivo_fim, v_conc, v_dias, v_tipo, v_faixa, v_sev,
            v_titulo,
            CASE v_tipo
                WHEN 'risco_dobro' THEN format('Concessivo venceu em %s. Cada dia gozado agora paga em dobro (art. 137).', v_conc)
                ELSE format('Conceder ate %s para nao pagar em dobro (art. 134/137).', v_conc)
            END,
            v_custo
        )
        ON CONFLICT (tenant_id, periodo_id, faixa) DO UPDATE
            SET dias_para_vencer = EXCLUDED.dias_para_vencer,
                custo_estimado   = EXCLUDED.custo_estimado,
                updated_at       = now()
        -- xmax = 0 distingue a linha recem-INSERIDA da apenas atualizada
        -- (now() e constante na transacao, entao datas nao servem para isso).
        RETURNING id, (xmax = 0) INTO v_alerta_id, v_inserido;

        IF v_inserido THEN
            v_novos := v_novos + 1;
        END IF;
        -- CRITICO: acao automatica no Plano de Acao (decisao do produto; idempotente)
        IF v_tipo = 'risco_dobro' THEN
            PERFORM public.ferias_alerta_gerar_acao(v_alerta_id);
        END IF;
    END LOOP;

    RETURN v_novos;
END $fn$;

GRANT EXECUTE ON FUNCTION public.ferias_alertas_varrer(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ferias_alerta_gerar_acao(UUID, UUID, TEXT, INTEGER) TO authenticated;

-- ── 4. Agendamento diario (pg_cron), idempotente ──────────────────────────
DO $cron$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.unschedule('ferias-alertas-diario')
          WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ferias-alertas-diario');
        PERFORM cron.schedule('ferias-alertas-diario', '10 6 * * *',
            $job$ SELECT public.ferias_alertas_varrer(); $job$);
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron indisponivel; a varredura segue chamavel sob demanda: %', SQLERRM;
END $cron$;
