-- ============================================================================
-- ENTREGA — Ferias: motor de alertas de vencimento e risco de dobro (RF-009)
--
-- Colar INTEIRO no SQL Editor do projeto de PRODUCAO e executar uma vez.
--
-- POR QUE
--   O painel de risco so mostrava vencidos para quem entrava na tela —
--   passivo. O RF-009 do YE-DP-FERIAS-001 pede um MOTOR: alerta em
--   D-90/60/30, sinaliza o dobro (art. 137) ao vencer o concessivo, estima
--   o custo e leva ao Plano de Acao.
--
-- O QUE MUDA
--   1) tabela ferias_alertas (um alerta por marco/periodo, idempotente);
--   2) ferias_alertas_varrer(tenant) — varre os periodos ativos, calcula o
--      concessivo (aquisitivo_fim + 12 meses), registra o alerta do marco e
--      estima o custo do dobro pelo salario das admissoes;
--   3) ferias_alerta_gerar_acao(alerta) — converte o alerta em acao no Plano
--      de Acao com 5W2H;
--   4) agendamento DIARIO por pg_cron (idempotente);
--   5) a rotina de QA FERIAS-023.
--
--   Decisao do produto (02/09/2026): acao AUTOMATICA so no critico (risco de
--   dobro); os demais geram acao sob demanda (botao na tela).
--
-- SEGURANCA DO DADO
--   So CRIA coisa nova (tabela, funcoes, trigger de cron). Nao altera nem
--   apaga LINHA existente, entao nao ha copia de seguranca a fazer.
--   Idempotente: rodar duas vezes nao quebra nem duplica. Este script NAO
--   dispara a varredura — quem a dispara e o agendamento diario e a tela.
--
-- EFEITO NA OPERACAO — LEIA: a partir da primeira varredura (na madrugada
--   seguinte, ou ao abrir a aba Vencimentos), os periodos JA vencidos viram
--   alerta critico e cada um cria UMA acao no Plano de Acao. Se houver
--   passivo acumulado, varias acoes podem nascer de uma vez no primeiro dia
--   — e o esperado (radar de dobro), mas convem avisar o RH.
--
-- PROVADO em replica local com schema fiel: periodo vencido -> alerta de
--   dobro critico com custo estimado e acao automatica; a vencer em 25 dias
--   -> alerta d30 sem acao; a >90 dias -> nada. Idempotente (2a varredura=0).
--   QA FERIAS-023 responde 'passou'.
--
-- A TELA (aba "Vencimentos") so aparece apos Publicar no Lovable.
-- ============================================================================

SET lock_timeout = '10s';

-- ── 1. Tabela de alertas ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ferias_alertas (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     UUID NOT NULL,
    empresa_id    UUID,
    periodo_id    UUID,
    colaborador_cpf  TEXT,
    colaborador_nome TEXT,
    colaborador_id   UUID,
    aquisitivo_fim   DATE,
    concessivo_fim   DATE,
    dias_para_vencer INTEGER,
    tipo   TEXT NOT NULL,
    faixa  TEXT NOT NULL,
    severidade TEXT NOT NULL DEFAULT 'media',
    titulo     TEXT NOT NULL,
    descricao  TEXT,
    custo_estimado NUMERIC(14,2),
    plano_acao_id UUID,
    resolvido   BOOLEAN NOT NULL DEFAULT false,
    resolvido_em TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
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

-- ── 3. A varredura ────────────────────────────────────────────────────────
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

        IF    v_dias <  0  THEN v_faixa := 'vencido'; v_sev := 'critica'; v_tipo := 'risco_dobro';
        ELSIF v_dias <= 30 THEN v_faixa := 'd30';     v_sev := 'alta';    v_tipo := 'concessivo_a_vencer';
        ELSIF v_dias <= 60 THEN v_faixa := 'd60';     v_sev := 'alta';    v_tipo := 'concessivo_a_vencer';
        ELSIF v_dias <= 90 THEN v_faixa := 'd90';     v_sev := 'media';   v_tipo := 'concessivo_a_vencer';
        ELSE  CONTINUE;
        END IF;

        v_custo := NULL;
        IF v_tipo = 'risco_dobro' THEN
            SELECT salario INTO v_sal FROM public.admissoes
             WHERE tenant_id = pr.tenant_id
               AND regexp_replace(coalesce(cpf,''),'\D','','g') = regexp_replace(coalesce(pr.colaborador_cpf,''),'\D','','g')
             LIMIT 1;
            IF coalesce(v_sal,0) > 0 THEN
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
        RETURNING id, (xmax = 0) INTO v_alerta_id, v_inserido;

        IF v_inserido THEN
            v_novos := v_novos + 1;
        END IF;
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

-- ── 5. QA — FERIAS-023 (sonda com rollback) ───────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ferias_023()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
    r        public.qa_retorno;
    v_tem    BOOLEAN;
    v_ten    UUID;
    v_gerou_venc  INTEGER := 0;
    v_gerou_d60   INTEGER := 0;
    v_crit_id     UUID;
    v_acao        UUID;
BEGIN
    r.passo_ordem := 1;
    r.passo_acao  := 'AUDITORIA: existe motor de alertas de vencimento (D-90/60/30 + dobro + acao)?';
    r.esperado    := 'Varredura gera alertas por marco; vencido sinaliza dobro e cria acao no Plano';

    SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                    WHERE n.nspname='public' AND p.proname='ferias_alertas_varrer')
      INTO v_tem;
    IF NOT v_tem THEN
        r.situacao := 'falhou';
        r.obtido := 'ACHADO: o vencimento aparece so para quem entra na tela — passivo. Falta o '
                 || 'motor do RF-009.';
        RETURN r;
    END IF;

    SELECT id INTO v_ten FROM public.tenants LIMIT 1;
    IF v_ten IS NULL THEN
        r.situacao := 'nao_implementado';
        r.obtido := 'Sem tenants para montar a sonda; o motor existe mas nao foi exercitado.';
        RETURN r;
    END IF;

    BEGIN
        INSERT INTO public.ferias_periodos_aquisitivos
            (tenant_id, colaborador_cpf, colaborador_nome, data_admissao,
             aquisitivo_inicio, aquisitivo_fim, dias_direito, dias_saldo, status)
        VALUES (v_ten, '00000000191', 'QA Vencido', CURRENT_DATE - 800,
                CURRENT_DATE - 760, (CURRENT_DATE - INTERVAL '13 months')::date, 30, 30, 'ativo');
        INSERT INTO public.ferias_periodos_aquisitivos
            (tenant_id, colaborador_cpf, colaborador_nome, data_admissao,
             aquisitivo_inicio, aquisitivo_fim, dias_direito, dias_saldo, status)
        VALUES (v_ten, '00000000272', 'QA D60', CURRENT_DATE - 400,
                CURRENT_DATE - 380, (CURRENT_DATE + 50 - INTERVAL '12 months')::date, 30, 30, 'ativo');

        PERFORM public.ferias_alertas_varrer(v_ten);

        SELECT count(*) INTO v_gerou_venc FROM public.ferias_alertas
         WHERE tenant_id = v_ten AND tipo = 'risco_dobro' AND faixa = 'vencido';
        SELECT count(*) INTO v_gerou_d60 FROM public.ferias_alertas
         WHERE tenant_id = v_ten AND faixa = 'd60';
        SELECT id, plano_acao_id INTO v_crit_id, v_acao FROM public.ferias_alertas
         WHERE tenant_id = v_ten AND faixa = 'vencido' LIMIT 1;

        RAISE EXCEPTION 'qa_rollback';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM <> 'qa_rollback' THEN
            r.situacao := 'erro'; r.obtido := 'A sonda quebrou'; r.erro_tecnico := SQLERRM;
            RETURN r;
        END IF;
    END;

    IF v_gerou_venc >= 1 AND v_gerou_d60 >= 1 AND v_acao IS NOT NULL THEN
        r.situacao := 'passou';
        r.obtido := 'Motor OK: gera alerta em D-60 e alerta de dobro ao vencer, e o critico ja '
                 || 'nasce com acao no Plano de Acao (art. 134/137).';
    ELSIF v_gerou_venc = 0 OR v_gerou_d60 = 0 THEN
        r.situacao := 'falhou';
        r.obtido := format('A varredura nao gerou os marcos esperados (vencido=%s, d60=%s).',
                           v_gerou_venc, v_gerou_d60);
    ELSE
        r.situacao := 'falhou';
        r.obtido := 'Os alertas nascem, mas o critico (dobro) nao virou acao automatica no Plano.';
    END IF;
    RETURN r;
EXCEPTION WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── 6. Conferencia final ──────────────────────────────────────────────────
SELECT
    (SELECT CASE WHEN to_regclass('public.ferias_alertas') IS NOT NULL
        THEN 'sim' ELSE 'NAO — verificar' END)                              AS tabela_alertas,
    (SELECT CASE WHEN to_regprocedure('public.ferias_alertas_varrer(uuid)') IS NOT NULL
        THEN 'sim' ELSE 'NAO — verificar' END)                             AS varredura,
    (SELECT CASE WHEN to_regprocedure('public.ferias_alerta_gerar_acao(uuid,uuid,text,integer)') IS NOT NULL
        THEN 'sim' ELSE 'NAO — verificar' END)                             AS gera_acao,
    (SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_cron')
        THEN 'sim (pg_cron presente; job diario agendado)'
        ELSE 'sem pg_cron (roda sob demanda)' END)                         AS agendado_diario,
    (SELECT situacao FROM public.qa_caso_ferias_023())                      AS qa_ferias_023;
