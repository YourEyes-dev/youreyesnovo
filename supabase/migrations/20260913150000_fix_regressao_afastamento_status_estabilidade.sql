-- ============================================================================
-- Fase 0 do plano de correção do Motor — regressão de 24/07 nos afastamentos
-- (AFAST-020 e AFAST-031)
--
-- Contexto: a reescrita 20260724130001 corrigiu um erro real (a função de
-- 23/07 abortava todo INSERT com 42703, pois gravava em NEW.dias_afastamento —
-- coluna que não existe em `afastamentos` — e escrevia em tabelas-filhas num
-- gatilho BEFORE, antes de a linha-pai existir). Ao mover a inteligência para
-- um gatilho AFTER, porém, perderam-se DUAS escritas que precisam morar na
-- própria linha (um AFTER não altera NEW):
--
--   AFAST-020  a virada de status para 'aguardando_inss' quando o afastamento
--              passa de 15 dias (Lei 8.213, art. 60). Além disso, o ramo do
--              EPISÓDIO ÚNICO > 15 dias sumiu — só a ACUMULAÇÃO por CID (que
--              exige CID em afastamentos_saude + colaborador vinculado) disparava
--              a pendência de INSS/S-2230. Um atestado longo comum passava calado.
--   AFAST-031  a gravação de afastamentos.data_fim_estabilidade (retorno + 12
--              meses, art. 118 CLT) para acidente/doença ocupacional, e os
--              próprios tipos acidentários, que saíram da Regra 9 (marcador de
--              estabilidade). A Rescisão (DESL-071) lê esse campo para bloquear
--              a dispensa; vazio, o bloqueio não acontece.
--
-- Correção (mantendo a arquitetura BEFORE/AFTER de 24/07):
--   * afastamento_campos_before (BEFORE): calcula os dias do episódio a partir
--     das próprias datas (roda ANTES de trigger_atualizar_afastamento_dias, que
--     seta dias_totais — 'trg_' < 'trigger_' na ordem alfabética), vira o status
--     para 'aguardando_inss' no episódio único > 15 dias e grava
--     data_fim_estabilidade para os tipos acidentários.
--   * processar_inteligencia_afastamento (AFTER): restaura o ramo "único OU
--     acumulado > 15 dias" para criar as pendências inss/s2230, devolve os tipos
--     acidentários à Regra 9 e dá precedência a 'aguardando_inss' sobre
--     'pendencia_critica' na escalada de status.
--
-- Idempotente: CREATE OR REPLACE das duas funções; nenhuma estrutura nova.
-- ============================================================================

-- ── BEFORE: apenas campos da própria linha ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.afastamento_campos_before()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_dias integer;
BEGIN
    -- Prazo indeterminado não tem data fim; o status reflete isso.
    IF COALESCE(NEW.prazo_indeterminado, FALSE) THEN
        IF NEW.status_geral_new IS NULL
           OR NEW.status_geral_new NOT IN ('prazo_indeterminado', 'em_beneficio') THEN
            NEW.status_geral_new := 'prazo_indeterminado';
        END IF;
    END IF;

    -- Dias do episódio a partir das próprias datas. Este gatilho roda ANTES de
    -- trigger_atualizar_afastamento_dias (que preenche dias_totais), então o
    -- valor ainda não está disponível em NEW — recalculamos aqui.
    IF NEW.data_inicio IS NOT NULL AND NEW.data_fim IS NOT NULL THEN
        v_dias := (NEW.data_fim - NEW.data_inicio) + 1;
    ELSIF NEW.data_inicio IS NOT NULL THEN
        v_dias := (CURRENT_DATE - NEW.data_inicio) + 1;
    ELSE
        v_dias := 0;
    END IF;

    -- AFAST-020: episódio único acima de 15 dias vira 'aguardando_inss'
    -- (Lei 8.213, art. 60 — a partir do 16º dia o benefício é do INSS). A
    -- ACUMULAÇÃO por CID continua tratada no gatilho AFTER (precisa do CID e do
    -- vínculo do colaborador); aqui garantimos o caso mais comum, o atestado
    -- longo, que não depende de CID. Não sobrescreve estados terminais/benefício.
    IF NOT COALESCE(NEW.prazo_indeterminado, FALSE)
       AND v_dias > 15
       AND (NEW.status_geral_new IS NULL
            OR NEW.status_geral_new NOT IN
               ('aguardando_inss', 'em_beneficio', 'encerrado', 'cancelado', 'prazo_indeterminado')) THEN
        NEW.status_geral_new := 'aguardando_inss';
    END IF;

    -- AFAST-031: estabilidade de 12 meses a partir do RETORNO (data_fim) para
    -- acidente típico/trajeto e doença ocupacional (art. 118 CLT). O B91 segue
    -- calculado em beneficios_inss (trigger calcular_estabilidade_b91).
    IF NEW.tipo_principal_new IN ('acidente_tipico', 'acidente_trajeto', 'doenca_ocupacional')
       AND NEW.data_fim IS NOT NULL THEN
        NEW.data_fim_estabilidade := (NEW.data_fim + INTERVAL '12 months')::date;
    END IF;

    RETURN NEW;
END;
$$;


-- ── AFTER: marcadores, pendências, FAP e escalada de status ─────────────────
CREATE OR REPLACE FUNCTION public.processar_inteligencia_afastamento()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_dias              INTEGER := 0;
    v_cid               TEXT;
    v_cnae              TEXT;
    v_ntep_status       TEXT;
    v_acumulado_60_dias INTEGER := 0;
    v_episodio_dias     INTEGER := 0;
    v_inss_15           BOOLEAN := FALSE;
    v_setor_id          UUID;
    v_mental_setor_count INTEGER := 0;
    v_criticas          INTEGER := 0;
BEGIN
    -- O UPDATE de status no final redispara este trigger. Corta a recursão.
    IF pg_trigger_depth() > 1 THEN
        RETURN NULL;
    END IF;

    v_dias     := COALESCE(NEW.dias_totais, 0);
    v_setor_id := NEW.setor_id;

    SELECT cid_principal INTO v_cid
      FROM public.afastamentos_saude
     WHERE afastamento_id = NEW.id;

    -- CNAE principal da empresa (não o CNPJ, como estava antes)
    SELECT cnae_principal INTO v_cnae
      FROM public.empresa_cadastro
     WHERE id = NEW.empresa_id;

    -- Reprocessa do zero os marcadores automáticos
    DELETE FROM public.afastamentos_marcadores
     WHERE afastamento_id = NEW.id AND origem = 'sistema';

    -- ── Regra 2: Saúde Mental (CID F) ──────────────────────────────────────
    IF v_cid LIKE 'F%' THEN
        INSERT INTO public.afastamentos_marcadores (afastamento_id, tenant_id, marcador)
        VALUES (NEW.id, NEW.tenant_id, 'saude_mental'),
               (NEW.id, NEW.tenant_id, 'cid_f'),
               (NEW.id, NEW.tenant_id, 'poss_risco_psicossocial');

        INSERT INTO public.afastamentos_pendencias
            (afastamento_id, tenant_id, tipo_pendencia, descricao, prioridade)
        VALUES (NEW.id, NEW.tenant_id, 'entrevista_retorno',
                'Realizar entrevista de retorno obrigatoria por CID F', 'media')
        ON CONFLICT DO NOTHING;

        IF v_setor_id IS NOT NULL THEN
            SELECT count(*) INTO v_mental_setor_count
              FROM public.afastamentos a
              JOIN public.afastamentos_saude s ON a.id = s.afastamento_id
             WHERE a.setor_id = v_setor_id
               AND s.cid_principal LIKE 'F%'
               AND a.created_at >= (now() - interval '90 days');

            IF v_mental_setor_count >= 3 THEN
                INSERT INTO public.afastamentos_marcadores (afastamento_id, tenant_id, marcador)
                VALUES (NEW.id, NEW.tenant_id, 'padrao_coletivo_setor');

                INSERT INTO public.afastamentos_pendencias
                    (afastamento_id, tenant_id, tipo_pendencia, descricao, prioridade)
                VALUES (NEW.id, NEW.tenant_id, 'revisao_sst',
                        'Alerta: 3+ afastamentos CID F no setor em 90 dias. Revisar PGR/FPR.', 'alta')
                ON CONFLICT DO NOTHING;
            END IF;
        END IF;
    END IF;

    -- ── Regra 3: Regra dos 15 dias (episódio único OU acumulado mesmo CID) ──
    -- Restaura o ramo do episódio único (basta dias_totais > 15), perdido na
    -- reescrita de 24/07. A acumulação por CID em 60 dias soma por cima quando
    -- há CID e colaborador vinculado.
    v_episodio_dias := v_dias;
    IF v_cid IS NOT NULL AND NEW.colaborador_id IS NOT NULL THEN
        SELECT COALESCE(SUM(a.dias_totais), 0) INTO v_acumulado_60_dias
          FROM public.afastamentos a
          JOIN public.afastamentos_saude s ON a.id = s.afastamento_id
         WHERE a.colaborador_id = NEW.colaborador_id
           AND a.id <> NEW.id
           AND s.cid_principal = v_cid
           AND a.data_inicio >= (NEW.data_inicio - interval '60 days');
        v_episodio_dias := v_episodio_dias + v_acumulado_60_dias;
    END IF;

    IF v_episodio_dias > 15 THEN
        v_inss_15 := TRUE;
        INSERT INTO public.afastamentos_marcadores (afastamento_id, tenant_id, marcador)
        VALUES (NEW.id, NEW.tenant_id, 'acumulacao_previdenciaria_15_dias'),
               (NEW.id, NEW.tenant_id, 'afastamento_superior_15_dias');

        INSERT INTO public.afastamentos_pendencias
            (afastamento_id, tenant_id, tipo_pendencia, descricao, prioridade)
        VALUES (NEW.id, NEW.tenant_id, 'inss',
                'Trabalhador atingiu 15+ dias (episodio unico ou acumulado no mesmo CID em 60 dias). Avaliar INSS.', 'critica')
        ON CONFLICT DO NOTHING;

        INSERT INTO public.afastamentos_pendencias
            (afastamento_id, tenant_id, tipo_pendencia, descricao, prioridade)
        VALUES (NEW.id, NEW.tenant_id, 's2230',
                'Enviar evento S-2230 por afastamento superior a 15 dias.', 'alta')
        ON CONFLICT DO NOTHING;
    END IF;

    -- ── Regras 4 e 7: NTEP e FAP ───────────────────────────────────────────
    IF v_cid IS NOT NULL AND v_cnae IS NOT NULL THEN
        v_ntep_status := public.check_ntep_relationship(v_cid, v_cnae);

        IF v_ntep_status = 'suspeito' THEN
            INSERT INTO public.afastamentos_marcadores (afastamento_id, tenant_id, marcador)
            VALUES (NEW.id, NEW.tenant_id, 'ntep_suspeito'),
                   (NEW.id, NEW.tenant_id, 'risco_impacto_fap');

            INSERT INTO public.afastamentos_pendencias
                (afastamento_id, tenant_id, tipo_pendencia, descricao, prioridade)
            VALUES (NEW.id, NEW.tenant_id, 'ntep',
                    'Possivel NTEP identificado. Avaliar nexo ocupacional.', 'alta')
            ON CONFLICT DO NOTHING;

            INSERT INTO public.afastamentos_fap
                (afastamento_id, tenant_id, impacta_fap, nivel_risco, motivo_impacto)
            VALUES (NEW.id, NEW.tenant_id, FALSE, 'risco_alto', 'NTEP Suspeito (' || v_cid || ')')
            ON CONFLICT (afastamento_id)
            DO UPDATE SET nivel_risco    = 'risco_alto',
                          motivo_impacto = EXCLUDED.motivo_impacto;
        END IF;
    END IF;

    -- ── Regra 5: CAT obrigatória ───────────────────────────────────────────
    IF NEW.tipo_principal_new IN ('acidente_tipico', 'acidente_trajeto', 'doenca_ocupacional') THEN
        INSERT INTO public.afastamentos_marcadores (afastamento_id, tenant_id, marcador)
        VALUES (NEW.id, NEW.tenant_id, 'cat_obrigatoria'),
               (NEW.id, NEW.tenant_id, 'cat_pendente');

        INSERT INTO public.afastamentos_pendencias
            (afastamento_id, tenant_id, tipo_pendencia, descricao, prioridade)
        VALUES (NEW.id, NEW.tenant_id, 'cat',
                'CAT obrigatoria para este tipo de afastamento.', 'critica')
        ON CONFLICT DO NOTHING;

        INSERT INTO public.afastamentos_pendencias
            (afastamento_id, tenant_id, tipo_pendencia, descricao, prioridade)
        VALUES (NEW.id, NEW.tenant_id, 's2210',
                'Enviar S-2210 referente a CAT obrigatoria.', 'critica')
        ON CONFLICT DO NOTHING;
    END IF;

    -- ── Regra 8: Retorno ao trabalho ───────────────────────────────────────
    IF v_dias >= 30
       OR NEW.tipo_principal_new IN ('beneficio_b31', 'beneficio_b91', 'licenca_maternidade') THEN
        INSERT INTO public.afastamentos_marcadores (afastamento_id, tenant_id, marcador)
        VALUES (NEW.id, NEW.tenant_id, 'retorno_obrigatorio');

        INSERT INTO public.afastamentos_pendencias
            (afastamento_id, tenant_id, tipo_pendencia, descricao, prioridade)
        VALUES (NEW.id, NEW.tenant_id, 'aso_retorno',
                'Exame de retorno ao trabalho obrigatorio (>30 dias ou beneficio)', 'alta')
        ON CONFLICT DO NOTHING;
    END IF;

    -- ── Regra 9: Estabilidade provisória (marcador) ────────────────────────
    -- Devolvidos os tipos acidentários (art. 118 CLT), removidos por engano na
    -- reescrita de 24/07. A DATA (data_fim_estabilidade) é gravada no BEFORE.
    IF NEW.tipo_principal_new IN ('beneficio_b91', 'licenca_maternidade', 'mandato_sindical',
                                  'acidente_tipico', 'acidente_trajeto', 'doenca_ocupacional') THEN
        INSERT INTO public.afastamentos_marcadores (afastamento_id, tenant_id, marcador)
        VALUES (NEW.id, NEW.tenant_id, 'estabilidade_provisoria');
    END IF;

    -- ── Escalada de status ─────────────────────────────────────────────────
    -- 'aguardando_inss' tem precedência sobre 'pendencia_critica'. Para o
    -- episódio único > 15 dias o BEFORE já virou o status; aqui cobrimos o caso
    -- da ACUMULAÇÃO (episódio único ≤15, acumulado >15), que o BEFORE não vê.
    SELECT count(*) INTO v_criticas
      FROM public.afastamentos_pendencias
     WHERE afastamento_id = NEW.id
       AND status = 'pendente'
       AND prioridade = 'critica';

    IF v_inss_15
       AND NEW.status_geral_new NOT IN
           ('aguardando_inss', 'em_beneficio', 'encerrado', 'cancelado', 'prazo_indeterminado') THEN
        UPDATE public.afastamentos
           SET status_geral_new = 'aguardando_inss'
         WHERE id = NEW.id;
    ELSIF v_criticas > 0
       AND NEW.status_geral_new NOT IN
           ('aguardando_inss', 'em_beneficio', 'encerrado', 'cancelado', 'prazo_indeterminado')
       AND NEW.status_geral_new IS DISTINCT FROM 'pendencia_critica' THEN
        UPDATE public.afastamentos
           SET status_geral_new = 'pendencia_critica'
         WHERE id = NEW.id;
    END IF;

    RETURN NULL;
END;
$$;
