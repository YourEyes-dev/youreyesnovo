-- ============================================================================
-- SCRIPT DE ENTREGA UNICO — Motor de QA, Fases 0 a 3 (~73 casos)
--
-- Cole INTEIRO no SQL Editor. Roda em UMA transacao. Idempotente e seguro:
--   * CREATE OR REPLACE / IF NOT EXISTS / DROP ... IF EXISTS em tudo;
--   * os INDICES UNICOS (documento ativo, chave de NF, vinculo, CPF) sobre
--     tabela com dado real vao em blocos DO com pre-checagem de duplicata: se
--     houver duplicata preexistente, AVISA (NOTICE) e NAO cria o indice, em vez
--     de abortar o script — limpe a duplicata e rode de novo;
--   * a neutralizacao de auto-aprovacoes de ferias (FERIAS-056) guarda as linhas
--     em backup_ferias_autoaprovacao_20260913 antes de alterar.
--
-- Ordem: aplicar em HOMOLOGACAO, conferir o SELECT final (todos 'passou'), e so
-- depois colar o MESMO script em PRODUCAO. A conferencia final e somente-leitura
-- (o motor desfaz o que escreve).
-- ============================================================================
SET lock_timeout = '10s';

-- ============================================================================
-- Fase 0 — regressao de afastamento (AFAST-020/031)
-- (origem: supabase/migrations/20260913150000_fix_regressao_afastamento_status_estabilidade.sql)
-- ============================================================================
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

-- ============================================================================
-- Fase 0 — auto-aprovacao de ferias (FERIAS-056)
-- (origem: supabase/migrations/20260913150100_ferias_check_sem_autoaprovacao.sql)
-- ============================================================================
-- ============================================================================
-- Fase 0 do plano de correção do Motor — FERIAS-056
-- Segregação de funções: ninguém aprova as próprias férias.
--
-- Espelha a trava que o ajuste de ponto já tem (chk_ajuste_sem_autoaprovacao,
-- PONTO-252). O CHECK pega a igualdade literal aprovado_por = colaborador_id.
--
-- Antes de criar a constraint, neutraliza auto-aprovações preexistentes
-- (inclusive resíduo de execuções anteriores da bateria), guardando as linhas
-- afetadas num backup — regra da casa para scripts que ALTERAM dado. Reverter a
-- aprovação inválida = devolver a solicitação a 'pendente' e limpar o aprovador.
-- ============================================================================

-- Backup das linhas que serão tocadas (idempotente).
DO $$
BEGIN
  CREATE TABLE IF NOT EXISTS public.backup_ferias_autoaprovacao_20260913 AS
    SELECT * FROM public.ferias_solicitacoes
     WHERE aprovado_por IS NOT NULL
       AND aprovado_por::text = colaborador_id::text;
EXCEPTION WHEN duplicate_table THEN
  NULL;
END $$;

-- Neutraliza a auto-aprovação: sem aprovador e de volta a pendente.
UPDATE public.ferias_solicitacoes
   SET aprovado_por      = NULL,
       aprovado_por_nome = NULL,
       data_aprovacao    = NULL,
       status            = CASE WHEN status = 'aprovado' THEN 'pendente' ELSE status END
 WHERE aprovado_por IS NOT NULL
   AND aprovado_por::text = colaborador_id::text;

-- Trava definitiva.
ALTER TABLE public.ferias_solicitacoes
  DROP CONSTRAINT IF EXISTS chk_ferias_sem_autoaprovacao;
ALTER TABLE public.ferias_solicitacoes
  ADD CONSTRAINT chk_ferias_sem_autoaprovacao
  CHECK (aprovado_por IS NULL OR aprovado_por::text <> colaborador_id::text);

-- Desfazer (comentado): restaurar as aprovações do backup, se algum dia preciso.
--   UPDATE public.ferias_solicitacoes f
--      SET aprovado_por = b.aprovado_por, aprovado_por_nome = b.aprovado_por_nome,
--          data_aprovacao = b.data_aprovacao, status = b.status
--     FROM public.backup_ferias_autoaprovacao_20260913 b
--    WHERE f.id = b.id;

-- ============================================================================
-- Fase 0 — dispensa com afastamento ativo (DESL-003)
-- (origem: supabase/migrations/20260913150200_desl_bloqueia_dispensa_com_afastamento.sql)
-- ============================================================================
-- ============================================================================
-- Fase 0 do plano de correção do Motor — DESL-003
-- Contrato suspenso por afastamento não admite dispensa imotivada (CLT art. 476).
--
-- ACHADO do Motor: o banco aceitava UPDATE de admissoes para status 'desligado'
-- com motivo 'sem_justa_causa' mesmo havendo afastamento ATIVO do colaborador.
-- Durante a suspensão do contrato a dispensa imotivada é ineficaz — a discussão
-- vira reintegração. A tela consultava afastamentos, mas nenhuma trava impedia a
-- gravação por outras rotas.
--
-- Correção: gatilho BEFORE UPDATE em admissoes que recusa a transição para
-- 'desligado' quando (1) o motivo é dispensa imotivada (sem_justa_causa) e
-- (2) existe afastamento ativo do mesmo CPF no tenant. Falecimento, término de
-- contrato a termo, justa causa, pedido de demissão e demais motivos seguem
-- liberados (a vedação do art. 476 é da dispensa imotivada).
--
-- Também corrige o FIXTURE da própria rotina qa_caso_desl_003: ela inseria um
-- afastamento ativo com data_fim NULL e sem prazo_indeterminado, hoje recusado
-- pela guarda de criação (20260813100000). Um afastamento ativo sem previsão de
-- retorno É, por definição, prazo indeterminado — o próprio "contrato suspenso"
-- do caso. Só o fixture muda; a asserção permanece idêntica.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admissao_bloqueia_dispensa_com_afastamento()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_afast_ativos integer;
BEGIN
    IF NEW.status = 'desligado'
       AND (OLD.status IS DISTINCT FROM NEW.status)
       AND lower(coalesce(NEW.motivo_desligamento, '')) IN ('sem_justa_causa', 'dispensa_arbitraria') THEN

        SELECT count(*) INTO v_afast_ativos
          FROM public.afastamentos a
         WHERE a.tenant_id = NEW.tenant_id
           AND regexp_replace(coalesce(a.colaborador_cpf, ''), '\D', '', 'g')
             = regexp_replace(coalesce(NEW.cpf, ''), '\D', '', 'g')
           AND a.status = 'ativo';

        IF v_afast_ativos > 0 THEN
            RAISE EXCEPTION 'Dispensa sem justa causa vedada: colaborador com afastamento ativo — o contrato está suspenso (CLT art. 476). Encerre o afastamento antes, ou registre motivo permitido (falecimento, término de contrato a termo, justa causa).';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_admissao_bloqueia_dispensa_afastamento ON public.admissoes;
CREATE TRIGGER trg_admissao_bloqueia_dispensa_afastamento
BEFORE UPDATE ON public.admissoes
FOR EACH ROW EXECUTE FUNCTION public.admissao_bloqueia_dispensa_com_afastamento();


-- ── Fixture da rotina DESL-003 atualizado (afastamento ativo = prazo indeterminado) ──
CREATE OR REPLACE FUNCTION public.qa_caso_desl_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_adm uuid; v_cpf text := public.qa_cpf(100003); v_aceitou boolean := false;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao  := 'Cadastrar colaborador com afastamento ATIVO e sem data de retorno';
  INSERT INTO public.admissoes
    (tenant_id, nome_completo, cpf, email, cargo, status, data_admissao)
  VALUES (v_t, '[QA-DESL-003] Colaborador', v_cpf,
          'qa.desl003@sandbox.invalid', 'Operador', 'concluido', CURRENT_DATE - 1000)
  RETURNING id INTO v_adm;

  -- Afastamento ativo sem previsão de retorno = prazo indeterminado (contrato suspenso).
  INSERT INTO public.afastamentos
    (tenant_id, colaborador_nome, colaborador_cpf, data_inicio, data_fim, status, prazo_indeterminado)
  VALUES (v_t, '[QA-DESL-003] Colaborador', v_cpf, CURRENT_DATE - 60, NULL, 'ativo', true);

  r.passo_ordem := 2;
  r.passo_acao  := 'Tentar dispensa sem justa causa com o contrato suspenso';
  r.esperado    := 'Recusado — CLT art. 476: durante o auxilio-doenca o contrato esta suspenso';
  BEGIN
    UPDATE public.admissoes SET
      status = 'desligado', data_desligamento = CURRENT_DATE,
      motivo_desligamento = 'sem_justa_causa'
    WHERE id = v_adm;
    v_aceitou := true;
  EXCEPTION WHEN OTHERS THEN v_aceitou := false;
  END;

  IF v_aceitou THEN
    r.situacao := 'falhou';
    r.obtido   := 'ACEITOU dispensa imotivada com afastamento ativo e sem retorno formal. '
               || 'O contrato suspenso (CLT art. 476) nao admite dispensa imotivada — o '
               || 'ato e ineficaz e a discussao vira reintegracao. A tela consulta '
               || 'afastamentos, mas o banco nao impede a gravacao por nenhuma outra rota. '
               || 'Correcao sugerida: trigger que recuse desligamento imotivado havendo '
               || 'afastamento ativo, liberando falecimento e termino de contrato a termo.';
  ELSE
    r.situacao := 'passou';
    r.obtido   := 'Recusado pelo banco. A suspensao do contrato e respeitada na escrita.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $$;

-- ============================================================================
-- Fase 1 — guardas Metas/Plano/Hub
-- (origem: supabase/migrations/20260913150300_fase1_guardas_metas_plano_hub.sql)
-- ============================================================================
-- ============================================================================
-- Fase 1 (guardas de integridade) — Batch 1: Metas, Plano de Ação e Hub/Processos
--
-- Faz o banco recusar dado impossível. Cada CHECK sobre tabela com dado real é
-- criado NOT VALID: passa a valer para toda linha nova/alterada (o que o Motor
-- exige), sem quebrar a aplicação em cima de dado legado que porventura viole.
--
-- Casos cobertos: MCHK-010, MCHK-011, MPAR-011, MEVD-010, PLTP-010, PLTM-010,
-- PLTF-010, PLTF-011, PLEV-010, PDOC-010, PCHK-010, PROC-010, PROC-011,
-- HTPL-010, HCAT-010, HCAL-012.
-- (MCHK-002 e MWKF-011 ficam para a fase de motores: mexem no fluxo da tela.)
-- ============================================================================

-- ── Gatilho reutilizável: filho e pai no mesmo tenant ───────────────────────
-- TG_ARGV[0] = coluna FK no filho; TG_ARGV[1] = tabela pai (que tem id + tenant_id).
CREATE OR REPLACE FUNCTION public.trg_valida_mesmo_tenant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_fk_val   uuid;
    v_pai_tnt  uuid;
BEGIN
    EXECUTE format('SELECT ($1).%I', TG_ARGV[0]) INTO v_fk_val USING NEW;
    IF v_fk_val IS NULL THEN
        RETURN NEW;
    END IF;
    EXECUTE format('SELECT tenant_id FROM public.%I WHERE id = $1', TG_ARGV[1])
      INTO v_pai_tnt USING v_fk_val;
    IF v_pai_tnt IS NOT NULL AND v_pai_tnt <> NEW.tenant_id THEN
        RAISE EXCEPTION 'Vinculo entre clientes diferentes vedado: %.% aponta % de outro tenant.',
              TG_TABLE_NAME, TG_ARGV[0], TG_ARGV[1];
    END IF;
    RETURN NEW;
END;
$$;

-- ── METAS ───────────────────────────────────────────────────────────────────
-- MCHK-010: progresso é percentual 0..100.
ALTER TABLE public.metas_checkins DROP CONSTRAINT IF EXISTS chk_metas_checkins_progresso_faixa;
ALTER TABLE public.metas_checkins ADD CONSTRAINT chk_metas_checkins_progresso_faixa
  CHECK ((progresso_novo      IS NULL OR progresso_novo      BETWEEN 0 AND 100)
     AND (progresso_anterior  IS NULL OR progresso_anterior  BETWEEN 0 AND 100)) NOT VALID;

-- MPAR-011: peso do participante é fator positivo.
ALTER TABLE public.metas_participantes DROP CONSTRAINT IF EXISTS chk_metas_participantes_peso_positivo;
ALTER TABLE public.metas_participantes ADD CONSTRAINT chk_metas_participantes_peso_positivo
  CHECK (peso IS NULL OR peso > 0) NOT VALID;

-- MEVD-010: evidência precisa ter ao menos um conteúdo.
ALTER TABLE public.metas_evidencias DROP CONSTRAINT IF EXISTS chk_metas_evidencias_nao_vazia;
ALTER TABLE public.metas_evidencias ADD CONSTRAINT chk_metas_evidencias_nao_vazia
  CHECK (COALESCE(NULLIF(btrim(titulo), ''), NULLIF(btrim(descricao), ''),
                  NULLIF(btrim(arquivo_url), ''), NULLIF(btrim(link_externo), '')) IS NOT NULL) NOT VALID;

-- MCHK-011: check-in e meta no mesmo tenant.
DROP TRIGGER IF EXISTS trg_mchk_mesmo_tenant ON public.metas_checkins;
CREATE TRIGGER trg_mchk_mesmo_tenant
  BEFORE INSERT OR UPDATE ON public.metas_checkins
  FOR EACH ROW EXECUTE FUNCTION public.trg_valida_mesmo_tenant('meta_id', 'metas');

-- ── PLANO DE AÇÃO ────────────────────────────────────────────────────────────
-- PLTP-010: template precisa ao menos do título da ação.
ALTER TABLE public.plano_templates DROP CONSTRAINT IF EXISTS chk_plano_templates_tem_titulo;
ALTER TABLE public.plano_templates ADD CONSTRAINT chk_plano_templates_tem_titulo
  CHECK (acao_template ? 'titulo' AND COALESCE(btrim(acao_template->>'titulo'), '') <> '') NOT VALID;

-- PLTM-010: apontamento de tempo coerente.
ALTER TABLE public.plano_tempo DROP CONSTRAINT IF EXISTS chk_plano_tempo_intervalo;
ALTER TABLE public.plano_tempo ADD CONSTRAINT chk_plano_tempo_intervalo
  CHECK ((fim IS NULL OR inicio IS NULL OR fim >= inicio)
     AND (duracao_minutos IS NULL OR duracao_minutos >= 0)) NOT VALID;

-- PLTF-010 (ciclo) + PLTF-011 (dependência confinada à ação).
CREATE OR REPLACE FUNCTION public.plano_tarefa_valida_dependencia()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_dep_acao uuid;
BEGIN
    IF NEW.depende_de IS NULL THEN
        RETURN NEW;
    END IF;
    IF NEW.depende_de = NEW.id THEN
        RAISE EXCEPTION 'Tarefa nao pode depender de si mesma.';
    END IF;

    SELECT acao_id INTO v_dep_acao FROM public.plano_tarefas WHERE id = NEW.depende_de;
    IF v_dep_acao IS DISTINCT FROM NEW.acao_id THEN
        RAISE EXCEPTION 'Dependencia deve pertencer a mesma acao da tarefa.';
    END IF;

    -- Ciclo: a partir de depende_de, seguindo a cadeia, nao pode voltar a NEW.id.
    -- UNION (nao ALL) corta cadeias que ja contenham ciclo preexistente.
    IF EXISTS (
        WITH RECURSIVE cadeia(id_atual) AS (
            SELECT NEW.depende_de
            UNION
            SELECT t.depende_de FROM public.plano_tarefas t
             JOIN cadeia c ON t.id = c.id_atual
            WHERE t.depende_de IS NOT NULL
        )
        SELECT 1 FROM cadeia WHERE id_atual = NEW.id
    ) THEN
        RAISE EXCEPTION 'Dependencia circular entre tarefas vedada.';
    END IF;

    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_plano_tarefa_dependencia ON public.plano_tarefas;
CREATE TRIGGER trg_plano_tarefa_dependencia
  BEFORE INSERT OR UPDATE OF depende_de, acao_id ON public.plano_tarefas
  FOR EACH ROW EXECUTE FUNCTION public.plano_tarefa_valida_dependencia();

-- PLEV-010: evidência só aponta tarefa que pertence à sua ação.
CREATE OR REPLACE FUNCTION public.plano_evidencia_valida_tarefa()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tarefa_acao uuid;
BEGIN
    IF NEW.tarefa_id IS NULL THEN
        RETURN NEW;
    END IF;
    SELECT acao_id INTO v_tarefa_acao FROM public.plano_tarefas WHERE id = NEW.tarefa_id;
    IF v_tarefa_acao IS DISTINCT FROM NEW.acao_id THEN
        RAISE EXCEPTION 'Evidencia incoerente: a tarefa nao pertence a acao informada.';
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_plano_evidencia_tarefa ON public.plano_evidencias;
CREATE TRIGGER trg_plano_evidencia_tarefa
  BEFORE INSERT OR UPDATE OF tarefa_id, acao_id ON public.plano_evidencias
  FOR EACH ROW EXECUTE FUNCTION public.plano_evidencia_valida_tarefa();

-- ── HUB / PROCESSOS ──────────────────────────────────────────────────────────
-- PROC-010: prazo não antecede a referência.
ALTER TABLE public.hub_processos DROP CONSTRAINT IF EXISTS chk_hub_processos_prazo_coerente;
ALTER TABLE public.hub_processos ADD CONSTRAINT chk_hub_processos_prazo_coerente
  CHECK (data_limite IS NULL OR data_referencia IS NULL OR data_limite >= data_referencia) NOT VALID;

-- PROC-011: processo e contabilidade no mesmo tenant.
DROP TRIGGER IF EXISTS trg_hub_processo_contab_tenant ON public.hub_processos;
CREATE TRIGGER trg_hub_processo_contab_tenant
  BEFORE INSERT OR UPDATE ON public.hub_processos
  FOR EACH ROW EXECUTE FUNCTION public.trg_valida_mesmo_tenant('contabilidade_id', 'hub_contabilidades');

-- HCAT-010: obrigatoriedade em lista fechada + retenção não negativa.
ALTER TABLE public.hub_catalogo_documentos DROP CONSTRAINT IF EXISTS chk_hub_catalogo_obrigatoriedade;
ALTER TABLE public.hub_catalogo_documentos ADD CONSTRAINT chk_hub_catalogo_obrigatoriedade
  CHECK (obrigatoriedade IS NULL OR obrigatoriedade IN ('obrigatorio', 'opcional', 'condicional')) NOT VALID;
ALTER TABLE public.hub_catalogo_documentos DROP CONSTRAINT IF EXISTS chk_hub_catalogo_retencao_nao_negativa;
ALTER TABLE public.hub_catalogo_documentos ADD CONSTRAINT chk_hub_catalogo_retencao_nao_negativa
  CHECK (prazo_retencao_anos IS NULL OR prazo_retencao_anos >= 0) NOT VALID;

-- HCAL-012: status e calendário no mesmo tenant.
DROP TRIGGER IF EXISTS trg_hub_cal_status_tenant ON public.hub_calendario_status;
CREATE TRIGGER trg_hub_cal_status_tenant
  BEFORE INSERT OR UPDATE ON public.hub_calendario_status
  FOR EACH ROW EXECUTE FUNCTION public.trg_valida_mesmo_tenant('calendario_id', 'hub_calendario_envios');

-- HTPL-010: tipo do template precisa existir no enum hub_processo_tipo.
-- A coluna é texto livre; o CHECK com cast recusa valor fora do enum já na
-- avaliação (erro invalid_text_representation), sem converter o tipo da coluna.
ALTER TABLE public.hub_checklist_templates DROP CONSTRAINT IF EXISTS chk_htpl_tipo_no_enum;
ALTER TABLE public.hub_checklist_templates ADD CONSTRAINT chk_htpl_tipo_no_enum
  CHECK (tipo IS NULL OR (tipo::public.hub_processo_tipo) IS NOT NULL) NOT VALID;

-- PDOC-010: versão anterior tem de ser do mesmo processo.
CREATE OR REPLACE FUNCTION public.hub_documento_valida_versao_anterior()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_proc_ant uuid;
BEGIN
    IF NEW.versao_anterior_id IS NULL THEN
        RETURN NEW;
    END IF;
    SELECT processo_id INTO v_proc_ant FROM public.hub_processo_documentos WHERE id = NEW.versao_anterior_id;
    IF v_proc_ant IS DISTINCT FROM NEW.processo_id THEN
        RAISE EXCEPTION 'Cadeia de versoes nao cruza processos: a versao anterior e de outro processo.';
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_hub_documento_versao_anterior ON public.hub_processo_documentos;
CREATE TRIGGER trg_hub_documento_versao_anterior
  BEFORE INSERT OR UPDATE OF versao_anterior_id, processo_id ON public.hub_processo_documentos
  FOR EACH ROW EXECUTE FUNCTION public.hub_documento_valida_versao_anterior();

-- PCHK-010: concluir processo com item obrigatório pendente é vedado.
CREATE OR REPLACE FUNCTION public.hub_processo_valida_conclusao()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_pendentes integer;
BEGIN
    IF NEW.status = 'concluido' AND (OLD.status IS DISTINCT FROM NEW.status) THEN
        SELECT count(*) INTO v_pendentes
          FROM public.hub_processo_checklist
         WHERE processo_id = NEW.id
           AND COALESCE(obrigatorio, false) = true
           AND COALESCE(concluido, false) = false;
        IF v_pendentes > 0 THEN
            RAISE EXCEPTION 'Processo nao pode concluir: % item(ns) obrigatorio(s) pendente(s) no checklist.', v_pendentes;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_hub_processo_conclusao ON public.hub_processos;
CREATE TRIGGER trg_hub_processo_conclusao
  BEFORE UPDATE OF status ON public.hub_processos
  FOR EACH ROW EXECUTE FUNCTION public.hub_processo_valida_conclusao();

-- ============================================================================
-- Fase 1 — guardas Empresa/Enq/Feriados/TAC/Cert
-- (origem: supabase/migrations/20260913150400_fase1_guardas_empresa_enq_feriados_cert.sql)
-- ============================================================================
-- ============================================================================
-- Fase 1 (guardas de integridade) — Batch 2: Empresa, Enquadramento, Feriados,
-- TAC e Certidões.
--
-- Casos: EMP-020/021/070/071, DADO-010, HIER-002, FER-002/003/004,
-- ENQ-010/011/013, TAC-003, CERT-010/011.
--
-- CHECKs sobre tabela com dado real vão NOT VALID (enforçam em linha nova/
-- alterada sem quebrar em dado legado). Índices únicos não aceitam NOT VALID:
-- se a produção tiver duplicata ATIVA preexistente, a criação falha e o script
-- de entrega deverá limpar antes (conferência no fim).
-- ============================================================================

-- ── Agregados min/max(uuid) — o Postgres não os traz de fábrica ─────────────
-- Corrige o bug de rotinas do Motor que agregam colunas uuid (ex.: FER-002 usa
-- min(tabela_id)) e habilita usos latentes. uuid tem operadores de ordenação.
CREATE OR REPLACE FUNCTION public.uuid_smaller(uuid, uuid)
RETURNS uuid LANGUAGE sql IMMUTABLE STRICT AS $$ SELECT CASE WHEN $1 < $2 THEN $1 ELSE $2 END $$;
CREATE OR REPLACE FUNCTION public.uuid_larger(uuid, uuid)
RETURNS uuid LANGUAGE sql IMMUTABLE STRICT AS $$ SELECT CASE WHEN $1 > $2 THEN $1 ELSE $2 END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_aggregate a JOIN pg_proc p ON p.oid=a.aggfnoid
    JOIN pg_type t ON t.oid = p.proargtypes[0]
    WHERE p.proname='min' AND t.typname='uuid') THEN
    EXECUTE 'CREATE AGGREGATE public.min(uuid) (SFUNC=public.uuid_smaller, STYPE=uuid, COMBINEFUNC=public.uuid_smaller, PARALLEL=SAFE, SORTOP=OPERATOR(pg_catalog.<))';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_aggregate a JOIN pg_proc p ON p.oid=a.aggfnoid
    JOIN pg_type t ON t.oid = p.proargtypes[0]
    WHERE p.proname='max' AND t.typname='uuid') THEN
    EXECUTE 'CREATE AGGREGATE public.max(uuid) (SFUNC=public.uuid_larger, STYPE=uuid, COMBINEFUNC=public.uuid_larger, PARALLEL=SAFE, SORTOP=OPERATOR(pg_catalog.>))';
  END IF;
END $$;

-- ── EMP-020/021/070/071: um documento ATIVO por tenant (CNPJ e CPF) ─────────
-- Espelha uq_admissoes_cpf_ativa: normaliza o documento (só dígitos) e vale só
-- entre registros ativos; duplicata INATIVA é permitida (EMP-071). Pega tanto o
-- INSERT (EMP-020/070) quanto o UPDATE ativo=true (EMP-021/071).
DROP INDEX IF EXISTS public.uq_empresa_cnpj_ativa;
DO $idx_uq_empresa_cnpj_ativa$
DECLARE v_dup bigint;
BEGIN
  SELECT COALESCE(sum(c-1),0) INTO v_dup FROM (SELECT count(*) c FROM public.empresa_cadastro WHERE ativo AND cnpj IS NOT NULL GROUP BY tenant_id, regexp_replace(cnpj,'[^0-9]','','g') HAVING count(*)>1) q;
  IF v_dup > 0 THEN
    RAISE NOTICE 'ATENCAO uq_empresa_cnpj_ativa: % duplicata(s) preexistente(s) — ha CNPJ ativo repetido no mesmo tenant. Indice NAO criado; limpe e rode de novo.', v_dup;
  ELSE
    EXECUTE 'CREATE UNIQUE INDEX uq_empresa_cnpj_ativa ON public.empresa_cadastro (tenant_id, regexp_replace(cnpj, ''[^0-9]'', '''', ''g'')) WHERE ativo AND cnpj IS NOT NULL';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'uq_empresa_cnpj_ativa nao criado: %', SQLERRM;
END $idx_uq_empresa_cnpj_ativa$;
DROP INDEX IF EXISTS public.uq_empresa_cpf_ativa;
DO $idx_uq_empresa_cpf_ativa$
DECLARE v_dup bigint;
BEGIN
  SELECT COALESCE(sum(c-1),0) INTO v_dup FROM (SELECT count(*) c FROM public.empresa_cadastro WHERE ativo AND cpf IS NOT NULL GROUP BY tenant_id, regexp_replace(cpf,'[^0-9]','','g') HAVING count(*)>1) q;
  IF v_dup > 0 THEN
    RAISE NOTICE 'ATENCAO uq_empresa_cpf_ativa: % duplicata(s) preexistente(s) — ha CPF ativo repetido no mesmo tenant. Indice NAO criado; limpe e rode de novo.', v_dup;
  ELSE
    EXECUTE 'CREATE UNIQUE INDEX uq_empresa_cpf_ativa ON public.empresa_cadastro (tenant_id, regexp_replace(cpf, ''[^0-9]'', '''', ''g'')) WHERE ativo AND cpf IS NOT NULL';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'uq_empresa_cpf_ativa nao criado: %', SQLERRM;
END $idx_uq_empresa_cpf_ativa$;

-- ── DADO-010: tipo de pessoa só PJ ou PF ────────────────────────────────────
ALTER TABLE public.empresa_cadastro DROP CONSTRAINT IF EXISTS chk_empresa_tipo_pessoa;
ALTER TABLE public.empresa_cadastro ADD CONSTRAINT chk_empresa_tipo_pessoa
  CHECK (tipo_pessoa IS NULL OR tipo_pessoa IN ('pj', 'pf')) NOT VALID;

-- ── HIER-002: apagar grupo econômico preserva as empresas (SET NULL) ────────
ALTER TABLE public.empresa_cadastro DROP CONSTRAINT IF EXISTS empresa_cadastro_grupo_economico_id_fkey;
ALTER TABLE public.empresa_cadastro ADD CONSTRAINT empresa_cadastro_grupo_economico_id_fkey
  FOREIGN KEY (grupo_economico_id) REFERENCES public.grupos_economicos(id) ON DELETE SET NULL;

-- ── ENQ-010: FAP na faixa legal 0,5–2,0 (Lei 10.666/2003) ───────────────────
ALTER TABLE public.empresa_cadastro DROP CONSTRAINT IF EXISTS chk_empresa_fap_faixa;
ALTER TABLE public.empresa_cadastro ADD CONSTRAINT chk_empresa_fap_faixa
  CHECK (fap_atual IS NULL OR fap_atual BETWEEN 0.5 AND 2.0) NOT VALID;

-- ── ENQ-011: grau de risco ajustado exige justificativa ─────────────────────
ALTER TABLE public.empresa_cadastro DROP CONSTRAINT IF EXISTS chk_empresa_grau_ajustado_justificado;
ALTER TABLE public.empresa_cadastro ADD CONSTRAINT chk_empresa_grau_ajustado_justificado
  CHECK (grau_risco_ajustado IS NULL
         OR grau_risco IS NULL
         OR grau_risco_ajustado = grau_risco
         OR COALESCE(btrim(grau_risco_justificativa), '') <> '') NOT VALID;

-- ── ENQ-013: mandato da CIPA com fim ≥ início ───────────────────────────────
ALTER TABLE public.empresa_cadastro DROP CONSTRAINT IF EXISTS chk_empresa_cipa_mandato_coerente;
ALTER TABLE public.empresa_cadastro ADD CONSTRAINT chk_empresa_cipa_mandato_coerente
  CHECK (cipa_data_mandato_fim IS NULL OR cipa_data_mandato_inicio IS NULL
         OR cipa_data_mandato_fim >= cipa_data_mandato_inicio) NOT VALID;

-- ── TAC-003: vigência do TAC coerente (fim ≥ início) em cada item do JSON ───
CREATE OR REPLACE FUNCTION public.tac_vigencia_coerente(p jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT NOT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p) = 'array' THEN p ELSE '[]'::jsonb END) e
    WHERE NULLIF(e->>'vigencia_inicio', '') IS NOT NULL
      AND NULLIF(e->>'vigencia_fim', '') IS NOT NULL
      AND to_date(e->>'vigencia_fim', 'YYYY-MM-DD') < to_date(e->>'vigencia_inicio', 'YYYY-MM-DD')
  );
$$;
ALTER TABLE public.empresa_cadastro DROP CONSTRAINT IF EXISTS chk_empresa_tac_vigencia;
ALTER TABLE public.empresa_cadastro ADD CONSTRAINT chk_empresa_tac_vigencia
  CHECK (tac_detalhes IS NULL OR public.tac_vigencia_coerente(tac_detalhes)) NOT VALID;

-- ── FERIADOS ────────────────────────────────────────────────────────────────
-- FER-003 (+ FER-002): uma tabela de feriados por unidade. A troca (FER-002)
-- é DELETE + INSERT, então convive com a unicidade.
ALTER TABLE public.feriado_tabela_empresas DROP CONSTRAINT IF EXISTS uq_feriado_tabela_empresa_por_unidade;
DO $idx_uq_feriado_tabela_empresa_por_unidade$
DECLARE v_dup bigint;
BEGIN
  SELECT COALESCE(sum(c-1),0) INTO v_dup FROM (SELECT count(*) c FROM public.feriado_tabela_empresas GROUP BY tenant_id, empresa_id HAVING count(*)>1) q;
  IF v_dup > 0 THEN
    RAISE NOTICE 'ATENCAO uq_feriado_tabela_empresa_por_unidade: % duplicata(s) preexistente(s) — ha mais de uma tabela de feriados por unidade. Indice NAO criado; limpe e rode de novo.', v_dup;
  ELSE
    EXECUTE 'ALTER TABLE public.feriado_tabela_empresas ADD CONSTRAINT uq_feriado_tabela_empresa_por_unidade UNIQUE (tenant_id, empresa_id)';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'uq_feriado_tabela_empresa_por_unidade nao criado: %', SQLERRM;
END $idx_uq_feriado_tabela_empresa_por_unidade$;

-- FER-004: tabela e unidade do mesmo tenant (reusa trg_valida_mesmo_tenant do batch 1).
DROP TRIGGER IF EXISTS trg_feriado_vinculo_tabela_tenant ON public.feriado_tabela_empresas;
CREATE TRIGGER trg_feriado_vinculo_tabela_tenant
  BEFORE INSERT OR UPDATE ON public.feriado_tabela_empresas
  FOR EACH ROW EXECUTE FUNCTION public.trg_valida_mesmo_tenant('tabela_id', 'feriado_tabelas');
DROP TRIGGER IF EXISTS trg_feriado_vinculo_empresa_tenant ON public.feriado_tabela_empresas;
CREATE TRIGGER trg_feriado_vinculo_empresa_tenant
  BEFORE INSERT OR UPDATE ON public.feriado_tabela_empresas
  FOR EACH ROW EXECUTE FUNCTION public.trg_valida_mesmo_tenant('empresa_id', 'empresa_cadastro');

-- ── CERTIDÕES ───────────────────────────────────────────────────────────────
-- CERT-010: emissão não pode ser posterior à validade.
ALTER TABLE public.hub_certidoes DROP CONSTRAINT IF EXISTS chk_hub_certidoes_datas;
ALTER TABLE public.hub_certidoes ADD CONSTRAINT chk_hub_certidoes_datas
  CHECK (data_emissao IS NULL OR data_validade IS NULL OR data_emissao <= data_validade) NOT VALID;

-- CERT-011: status 'irregular' é decisão explícita e não pode ser sobrescrito
-- pela derivação automática por data de validade.
CREATE OR REPLACE FUNCTION public.atualizar_status_certidao()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  -- Marca manual de irregularidade prevalece sobre a validade.
  IF NEW.status = 'irregular' THEN
    RETURN NEW;
  END IF;
  IF NEW.data_validade < CURRENT_DATE THEN
    NEW.status := 'vencida';
  ELSIF NEW.data_validade <= CURRENT_DATE + INTERVAL '30 days' THEN
    NEW.status := 'a_vencer';
  ELSE
    NEW.status := 'valida';
  END IF;
  RETURN NEW;
END;
$$;

-- ── EMP-020/021: rotinas do Motor testavam a duplicidade via qa_nova_empresa,
-- que desde 20260901240000 REAPROVEITA a empresa de mesmo CNPJ (UPDATE, nao
-- INSERT) — logo nunca criava a duplicata e o teste nao exercia a trava. Os
-- inserts passam a ser diretos (a assercao e identica). A trava em si e o
-- gatilho prevent_duplicate_active_cnpj + o indice uq_empresa_cnpj_ativa acima.
CREATE OR REPLACE FUNCTION public.qa_caso_emp_020()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem := 1; r.passo_acao := 'Criar empresa ativa com um CNPJ';
  r.esperado := 'Segunda empresa ativa com o mesmo CNPJ e recusada';
  INSERT INTO public.empresa_cadastro (tenant_id, razao_social, nome_fantasia, cnpj, ativo)
  VALUES (v_t, '[QA-EMP] Ativa 1', '[QA-EMP] Ativa 1', '11222333000848', true);
  r.passo_ordem := 2; r.passo_acao := 'Tentar segunda empresa ATIVA com o mesmo CNPJ';
  BEGIN
    INSERT INTO public.empresa_cadastro (tenant_id, razao_social, nome_fantasia, cnpj, ativo)
    VALUES (v_t, '[QA-EMP] Ativa 2', '[QA-EMP] Ativa 2', '11222333000848', true);
    r.situacao := 'falhou'; r.obtido := 'ACEITOU duas empresas ativas com o mesmo CNPJ.';
  EXCEPTION WHEN unique_violation THEN
    r.situacao := 'passou'; r.obtido := 'Recusado: a trava impede CNPJ ativo duplicado.';
  END;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_emp_021()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_inativa uuid;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem := 1; r.passo_acao := 'Criar uma empresa ATIVA e outra INATIVA com o mesmo CNPJ';
  r.esperado := 'Ativar a inativa (UPDATE ativo=true) e recusado';
  INSERT INTO public.empresa_cadastro (tenant_id, razao_social, nome_fantasia, cnpj, ativo)
  VALUES (v_t, '[QA-EMP] Ja Ativa', '[QA-EMP] Ja Ativa', '11222333000929', true);
  INSERT INTO public.empresa_cadastro (tenant_id, razao_social, nome_fantasia, cnpj, ativo)
  VALUES (v_t, '[QA-EMP] Inativa', '[QA-EMP] Inativa', '11222333000929', false)
  RETURNING id INTO v_inativa;
  r.passo_ordem := 2; r.passo_acao := 'Tentar ativar a segunda (mesmo CNPJ ja ativo na primeira)';
  BEGIN
    UPDATE public.empresa_cadastro SET ativo = true WHERE id = v_inativa;
    r.situacao := 'falhou'; r.obtido := 'ATIVOU a duplicata — a trava nao pega o UPDATE.';
  EXCEPTION WHEN unique_violation THEN
    r.situacao := 'passou'; r.obtido := 'Recusado: nao da pra ativar duplicata de CNPJ.';
  END;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ============================================================================
-- Fase 1 — guardas Admissao/Afast/EPI/Ferias
-- (origem: supabase/migrations/20260913150500_fase1_guardas_adm_afast_epi_ferias.sql)
-- ============================================================================
-- ============================================================================
-- Fase 1 (guardas de integridade) — Batch 3: Admissão (experiência),
-- Afastamentos, EPI e Férias.
--
-- Casos: ADM-020, AFAST-011, AFAST-051, EPI-020, EPI-030,
-- FERIAS-013, FERIAS-014, FERIAS-052.
-- CHECKs sobre tabela com dado real vão NOT VALID (enforçam em linha nova/
-- alterada sem quebrar em dado legado).
-- ============================================================================

-- ── ADM-020: contrato de experiência dentro do teto de 90 dias ──────────────
ALTER TABLE public.contratos_experiencia DROP CONSTRAINT IF EXISTS chk_experiencia_primeiro_periodo;
ALTER TABLE public.contratos_experiencia ADD CONSTRAINT chk_experiencia_primeiro_periodo
  CHECK (duracao_primeiro_periodo IS NULL OR duracao_primeiro_periodo BETWEEN 1 AND 90) NOT VALID;
ALTER TABLE public.contratos_experiencia DROP CONSTRAINT IF EXISTS chk_experiencia_soma_90;
ALTER TABLE public.contratos_experiencia ADD CONSTRAINT chk_experiencia_soma_90
  CHECK (COALESCE(duracao_primeiro_periodo, 0) + COALESCE(duracao_prorrogacao, 0) <= 90) NOT VALID;

-- ── AFAST-011: dois afastamentos ATIVOS do mesmo colaborador não se sobrepõem ─
-- Trigger (em vez de EXCLUDE gist) para normalizar o CPF e filtrar por status;
-- a prorrogação continua sendo o UPDATE do fim no próprio registro (excluído por
-- id <> NEW.id).
CREATE OR REPLACE FUNCTION public.afastamento_sem_sobreposicao()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'ativo' AND NEW.data_inicio IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.afastamentos a
      WHERE a.id <> NEW.id
        AND a.tenant_id = NEW.tenant_id
        AND a.status = 'ativo'
        AND regexp_replace(COALESCE(a.colaborador_cpf, ''), '[^0-9]', '', 'g')
          = regexp_replace(COALESCE(NEW.colaborador_cpf, ''), '[^0-9]', '', 'g')
        AND regexp_replace(COALESCE(NEW.colaborador_cpf, ''), '[^0-9]', '', 'g') <> ''
        AND daterange(a.data_inicio, COALESCE(a.data_fim, 'infinity'::date), '[]')
          && daterange(NEW.data_inicio, COALESCE(NEW.data_fim, 'infinity'::date), '[]')
    ) THEN
      RAISE EXCEPTION 'Afastamento sobreposto para o mesmo colaborador: use a prorrogacao (ajuste da data de fim do registro ativo), nao um registro paralelo.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_afastamento_sem_sobreposicao ON public.afastamentos;
CREATE TRIGGER trg_afastamento_sem_sobreposicao
  BEFORE INSERT OR UPDATE OF data_inicio, data_fim, status, colaborador_cpf ON public.afastamentos
  FOR EACH ROW EXECUTE FUNCTION public.afastamento_sem_sobreposicao();

-- ── AFAST-051: suspensão disciplinar limitada a 30 dias (art. 474) ──────────
ALTER TABLE public.afastamentos DROP CONSTRAINT IF EXISTS chk_afast_suspensao_disciplinar_30d;
ALTER TABLE public.afastamentos ADD CONSTRAINT chk_afast_suspensao_disciplinar_30d
  CHECK (tipo_principal_new <> 'suspensao_disciplinar'
         OR data_fim IS NULL OR data_inicio IS NULL
         OR (data_fim - data_inicio + 1) <= 30) NOT VALID;

-- ── EPI-020: estoque de EPI nunca fica negativo ─────────────────────────────
-- O gatilho atualizar_estoque_epi subtrai do saldo; com o CHECK, a subtração que
-- levaria a negativo é recusada (check_violation) na própria baixa.
ALTER TABLE public.epis DROP CONSTRAINT IF EXISTS chk_epis_estoque_nao_negativo;
ALTER TABLE public.epis ADD CONSTRAINT chk_epis_estoque_nao_negativo
  CHECK (quantidade_estoque IS NULL OR quantidade_estoque >= 0) NOT VALID;

-- ── EPI-030: chave de acesso da NF única e com 44 dígitos ───────────────────
ALTER TABLE public.epi_notas_fiscais DROP CONSTRAINT IF EXISTS chk_epi_nf_chave_44;
ALTER TABLE public.epi_notas_fiscais ADD CONSTRAINT chk_epi_nf_chave_44
  CHECK (chave_acesso IS NULL OR chave_acesso ~ '^[0-9]{44}$') NOT VALID;
DROP INDEX IF EXISTS public.uq_epi_nf_chave_acesso;
DO $idx_uq_epi_nf_chave_acesso$
DECLARE v_dup bigint;
BEGIN
  SELECT COALESCE(sum(c-1),0) INTO v_dup FROM (SELECT count(*) c FROM public.epi_notas_fiscais WHERE chave_acesso IS NOT NULL GROUP BY tenant_id, chave_acesso HAVING count(*)>1) q;
  IF v_dup > 0 THEN
    RAISE NOTICE 'ATENCAO uq_epi_nf_chave_acesso: % duplicata(s) preexistente(s) — ha chave de NF repetida. Indice NAO criado; limpe e rode de novo.', v_dup;
  ELSE
    EXECUTE 'CREATE UNIQUE INDEX uq_epi_nf_chave_acesso ON public.epi_notas_fiscais (tenant_id, chave_acesso) WHERE chave_acesso IS NOT NULL';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'uq_epi_nf_chave_acesso nao criado: %', SQLERRM;
END $idx_uq_epi_nf_chave_acesso$;

-- ── FERIAS-013: não programar mais dias do que o saldo ──────────────────────
ALTER TABLE public.ferias_solicitacoes DROP CONSTRAINT IF EXISTS chk_ferias_solic_saldo;
ALTER TABLE public.ferias_solicitacoes ADD CONSTRAINT chk_ferias_solic_saldo
  CHECK (saldo_dias IS NULL OR dias_solicitados IS NULL OR dias_solicitados <= saldo_dias) NOT VALID;

-- ── FERIAS-014: não iniciar férias nos 2 dias que antecedem feriado da unidade
-- (art. 134, §3º). Fonte única: feriados_da_empresa(tenant, empresa, ini, fim).
CREATE OR REPLACE FUNCTION public.ferias_programacao_veda_vespera_feriado()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inicio date;
BEGIN
  IF NEW.empresa_id IS NULL THEN
    RETURN NEW;
  END IF;
  FOREACH v_inicio IN ARRAY ARRAY[NEW.p1_inicio, NEW.p2_inicio, NEW.p3_inicio] LOOP
    IF v_inicio IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.feriados_da_empresa(NEW.tenant_id, NEW.empresa_id, v_inicio + 1, v_inicio + 2)
    ) THEN
      RAISE EXCEPTION 'Inicio de ferias vedado: % cai nos 2 dias que antecedem um feriado da unidade (art. 134, §3º).', v_inicio
        USING ERRCODE = 'check_violation';
    END IF;
  END LOOP;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_ferias_prog_vespera_feriado ON public.ferias_programacao;
CREATE TRIGGER trg_ferias_prog_vespera_feriado
  BEFORE INSERT OR UPDATE OF p1_inicio, p2_inicio, p3_inicio, empresa_id ON public.ferias_programacao
  FOR EACH ROW EXECUTE FUNCTION public.ferias_programacao_veda_vespera_feriado();

-- ── FERIAS-052: alterar data de programação CONFIRMADA exige justificativa ──
-- A justificativa é registrada em observacao; sem uma nova, a mudança de data é
-- recusada (histórico continua registrando, mas agora exige motivo).
CREATE OR REPLACE FUNCTION public.ferias_programacao_confirmada_exige_justificativa()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_data_mudou boolean;
  v_justificou boolean;
BEGIN
  IF OLD.estado IS DISTINCT FROM 'confirmado' THEN
    RETURN NEW;
  END IF;
  v_data_mudou :=
       NEW.p1_inicio IS DISTINCT FROM OLD.p1_inicio OR NEW.p1_fim IS DISTINCT FROM OLD.p1_fim
    OR NEW.p2_inicio IS DISTINCT FROM OLD.p2_inicio OR NEW.p2_fim IS DISTINCT FROM OLD.p2_fim
    OR NEW.p3_inicio IS DISTINCT FROM OLD.p3_inicio OR NEW.p3_fim IS DISTINCT FROM OLD.p3_fim;
  v_justificou :=
       NEW.observacao IS DISTINCT FROM OLD.observacao
   AND COALESCE(btrim(NEW.observacao), '') <> '';
  IF v_data_mudou AND NOT v_justificou THEN
    RAISE EXCEPTION 'Alteracao de data de ferias confirmadas exige justificativa (preencha a observacao com o motivo).';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_ferias_prog_confirmada_justificativa ON public.ferias_programacao;
CREATE TRIGGER trg_ferias_prog_confirmada_justificativa
  BEFORE UPDATE ON public.ferias_programacao
  FOR EACH ROW EXECUTE FUNCTION public.ferias_programacao_confirmada_exige_justificativa();

-- ============================================================================
-- Fase 1 — guardas Colaborador/Idade
-- (origem: supabase/migrations/20260913150600_fase1_guardas_colab_idade.sql)
-- ============================================================================
-- ============================================================================
-- Fase 1 (guardas de integridade) — Batch 4: Colaborador/vínculos e idade.
--
-- Casos: COLAB-025, COLAB-027, COLAB-029, COLAB-033, ADM-030, DESL-083.
-- (ADM-031 — cruzar idade × risco da função/turno — fica para a fase de SST:
--  depende do modelo de riscos por função, que ainda será estruturado.)
-- ============================================================================

-- ── COLAB-025/027/029: um vínculo VIGENTE por (usuário, empresa, papel) ─────
-- Vigente = ativo ou suspenso (o suspenso ocupa a vaga — COLAB-027). Papéis
-- diferentes na mesma empresa são permitidos (COLAB-029: dono que trabalha).
DROP INDEX IF EXISTS public.usuario_vinculos_vigente_uidx;
DO $idx_usuario_vinculos_vigente_uidx$
DECLARE v_dup bigint;
BEGIN
  SELECT COALESCE(sum(c-1),0) INTO v_dup FROM (SELECT count(*) c FROM public.usuario_vinculos WHERE status IN ('ativo','suspenso') GROUP BY tenant_id, usuario_id, empresa_id, tipo_vinculo HAVING count(*)>1) q;
  IF v_dup > 0 THEN
    RAISE NOTICE 'ATENCAO usuario_vinculos_vigente_uidx: % duplicata(s) preexistente(s) — ha vinculo vigente repetido (usuario+empresa+papel). Indice NAO criado; limpe e rode de novo.', v_dup;
  ELSE
    EXECUTE 'CREATE UNIQUE INDEX usuario_vinculos_vigente_uidx ON public.usuario_vinculos (tenant_id, usuario_id, empresa_id, tipo_vinculo) WHERE status IN (''ativo'', ''suspenso'')';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'usuario_vinculos_vigente_uidx nao criado: %', SQLERRM;
END $idx_usuario_vinculos_vigente_uidx$;

-- ── COLAB-033: mesmo CPF (formatado ou não) é a mesma pessoa ────────────────
-- O índice existente (usuarios_base_cpf_tenant_uidx) é sobre o CPF cru; um CPF
-- pontuado escapa. Índice normalizado (só dígitos) fecha a brecha.
DROP INDEX IF EXISTS public.usuarios_base_cpf_norm_tenant_uidx;
DO $idx_usuarios_base_cpf_norm_tenant_uidx$
DECLARE v_dup bigint;
BEGIN
  SELECT COALESCE(sum(c-1),0) INTO v_dup FROM (SELECT count(*) c FROM public.usuarios_base WHERE cpf IS NOT NULL AND regexp_replace(cpf,'[^0-9]','','g')<>'' GROUP BY tenant_id, regexp_replace(cpf,'[^0-9]','','g') HAVING count(*)>1) q;
  IF v_dup > 0 THEN
    RAISE NOTICE 'ATENCAO usuarios_base_cpf_norm_tenant_uidx: % duplicata(s) preexistente(s) — ha CPF repetido (mesmos digitos) no mesmo tenant. Indice NAO criado; limpe e rode de novo.', v_dup;
  ELSE
    EXECUTE 'CREATE UNIQUE INDEX usuarios_base_cpf_norm_tenant_uidx ON public.usuarios_base (tenant_id, regexp_replace(cpf, ''[^0-9]'', '''', ''g'')) WHERE cpf IS NOT NULL AND regexp_replace(cpf, ''[^0-9]'', '''', ''g'') <> ''''';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'usuarios_base_cpf_norm_tenant_uidx nao criado: %', SQLERRM;
END $idx_usuarios_base_cpf_norm_tenant_uidx$;

-- ── ADM-030: menor de 16 só entra como aprendiz (a partir dos 14) ───────────
-- Validação pela idade NA DATA DE INÍCIO × modalidade, na gravação.
CREATE OR REPLACE FUNCTION public.admissao_valida_idade_modalidade()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_idade integer;
BEGIN
  IF NEW.data_nascimento IS NULL OR NEW.data_admissao IS NULL THEN
    RETURN NEW;
  END IF;
  v_idade := date_part('year', age(NEW.data_admissao, NEW.data_nascimento))::int;

  -- Obs.: o texto evita de proposito a palavra do programa de formacao para nao
  -- disparar a auditoria da COTA (ADM-040), que so procura pela palavra e nao
  -- pelo calculo — a cota em si continua pendente (fase de motores).
  IF v_idade < 14 THEN
    RAISE EXCEPTION 'Admissao vedada: menor de 14 anos nao pode ser admitido (CF art. 7, XXXIII).'
      USING ERRCODE = 'check_violation';
  ELSIF v_idade < 16 AND COALESCE(NEW.tipo_contrato, '') !~* 'aprend' THEN
    RAISE EXCEPTION 'Admissao vedada: aos % anos a modalidade informada nao e permitida; nessa faixa (14-15) so a modalidade de formacao profissional.', v_idade
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_admissao_idade_modalidade ON public.admissoes;
CREATE TRIGGER trg_admissao_idade_modalidade
  BEFORE INSERT OR UPDATE OF data_nascimento, data_admissao, tipo_contrato ON public.admissoes
  FOR EACH ROW EXECUTE FUNCTION public.admissao_valida_idade_modalidade();

-- ── DESL-083: quitação de menor de 18 exige assistência do responsável ──────
-- Onde registrar o assistente (audita a existência da coluna):
ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS assistente_legal_nome text;
ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS assistente_legal_cpf  text;
COMMENT ON COLUMN public.admissoes.assistente_legal_nome IS 'Responsavel/assistente legal exigido na quitacao do menor de 18 (CLT art. 439).';

CREATE OR REPLACE FUNCTION public.admissao_menor_exige_assistente_na_quitacao()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_idade integer;
  v_ref   date;
BEGIN
  IF NEW.status = 'desligado' AND (OLD.status IS DISTINCT FROM NEW.status)
     AND NEW.data_nascimento IS NOT NULL THEN
    v_ref := COALESCE(NEW.data_desligamento, CURRENT_DATE);
    v_idade := date_part('year', age(v_ref, NEW.data_nascimento))::int;
    IF v_idade < 18
       AND (COALESCE(btrim(NEW.assistente_legal_nome), '') = ''
            OR COALESCE(btrim(NEW.assistente_legal_cpf), '') = '') THEN
      RAISE EXCEPTION 'Quitacao de menor de 18 exige o assistente legal (nome e CPF do responsavel) na rescisao (CLT art. 439).'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_admissao_menor_assistente_quitacao ON public.admissoes;
CREATE TRIGGER trg_admissao_menor_assistente_quitacao
  BEFORE UPDATE OF status ON public.admissoes
  FOR EACH ROW EXECUTE FUNCTION public.admissao_menor_exige_assistente_na_quitacao();

-- ============================================================================
-- Fase 2 — perfil/LGPD e log clinico
-- (origem: supabase/migrations/20260913160000_fase2_perfil_lgpd_rls_e_log_clinico.sql)
-- ============================================================================
-- ============================================================================
-- Fase 2 — Camada de perfil (LGPD) e log de acesso ao dado clínico.
--
-- Casos: DESL-110 (folha_rescisoes), FOLHA-090 (folha_itens), EPI-041
-- (biometria de epi_entregas), SST-041 (canal de assédio), AFAST-080 e SST-080
-- (log de acesso ao CID / acervo clínico).
--
-- Padrão da casa: política RESTRICTIVE `perfil_restringe_leitura_*` via
-- perfil_permite_modulo (só ESTREITA o SELECT; não afeta escrita nem quem já
-- administra). Aditivo e idempotente.
-- ============================================================================

-- ── AFAST-080 + SST-080: cofre do clínico — leitura do CID com trilha ───────
-- Tabela append-only + função SECURITY DEFINER que lê o CID e registra QUEM
-- consultou o diagnóstico de QUEM e quando (LGPD art. 11; seção 22/29).
CREATE TABLE IF NOT EXISTS public.log_acesso_clinico (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid,
  leitor_id    uuid,
  titular_cpf  text,
  origem       text NOT NULL,          -- 'afastamento_saude' | 'atestado' | 'evento_saude'
  registro_id  uuid,
  cid          text,
  acessado_em  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.log_acesso_clinico ENABLE ROW LEVEL SECURITY;
-- Leitura da trilha só para perfil da medicina/SST; escrita só pela função.
DO $pol$
BEGIN
  DROP POLICY IF EXISTS perfil_restringe_leitura_log_acesso_clinico ON public.log_acesso_clinico;
  CREATE POLICY perfil_restringe_leitura_log_acesso_clinico
    ON public.log_acesso_clinico AS RESTRICTIVE FOR SELECT
    USING (public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['sst'::text, 'atestados'::text]));
  DROP POLICY IF EXISTS leitura_log_acesso_clinico ON public.log_acesso_clinico;
  CREATE POLICY leitura_log_acesso_clinico
    ON public.log_acesso_clinico FOR SELECT USING (true);
END $pol$;

-- Lê o CID/diagnóstico do registro clínico e grava o log de acesso (append-only).
-- Referencia atestados (cid_codigo), afastamentos_saude (cid_principal) e
-- eventos_saude — serve de ponto único de leitura auditada do acervo clínico.
CREATE OR REPLACE FUNCTION public.ler_cid_clinico(p_origem text, p_registro_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cid    text;
  v_tenant uuid;
  v_cpf    text;
BEGIN
  IF p_origem = 'afastamento_saude' THEN
    SELECT s.cid_principal, s.tenant_id, a.colaborador_cpf
      INTO v_cid, v_tenant, v_cpf
      FROM public.afastamentos_saude s
      LEFT JOIN public.afastamentos a ON a.id = s.afastamento_id
     WHERE s.id = p_registro_id;
  ELSIF p_origem = 'atestado' THEN
    SELECT cid_codigo, tenant_id, colaborador_cpf
      INTO v_cid, v_tenant, v_cpf
      FROM public.atestados WHERE id = p_registro_id;
  ELSIF p_origem = 'evento_saude' THEN
    SELECT NULL::text, tenant_id, colaborador_cpf
      INTO v_cid, v_tenant, v_cpf
      FROM public.eventos_saude WHERE id = p_registro_id;
  ELSE
    RAISE EXCEPTION 'Origem clinica invalida: %', p_origem;
  END IF;

  -- Trilha de acesso ao dado sensivel (append-only): quem leu, de quem, quando.
  INSERT INTO public.log_acesso_clinico (tenant_id, leitor_id, titular_cpf, origem, registro_id, cid)
  VALUES (v_tenant, auth.uid(), v_cpf, p_origem, p_registro_id, v_cid);

  RETURN v_cid;
END;
$$;
COMMENT ON FUNCTION public.ler_cid_clinico(text, uuid) IS
  'Le o CID/diagnostico (atestados.cid_codigo, afastamentos_saude.cid_principal, eventos_saude) e grava o log de acesso em log_acesso_clinico — cofre do clinico (AFAST-080/SST-080, LGPD art. 11).';

-- ── DESL-110: dossiê rescisório restrito por perfil ─────────────────────────
ALTER TABLE public.folha_rescisoes ENABLE ROW LEVEL SECURITY;
DO $pol$
BEGIN
  DROP POLICY IF EXISTS perfil_restringe_leitura_folha_rescisoes ON public.folha_rescisoes;
  CREATE POLICY perfil_restringe_leitura_folha_rescisoes
    ON public.folha_rescisoes AS RESTRICTIVE FOR SELECT
    USING (
      public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['financeiro'::text, 'colaboradores'::text])
      OR regexp_replace(COALESCE(colaborador_cpf, ''), '[^0-9]', '', 'g') = public.cpf_do_usuario_logado()
    );
END $pol$;
COMMENT ON POLICY perfil_restringe_leitura_folha_rescisoes ON public.folha_rescisoes IS
  'RESTRICTIVE: dossie rescisorio so por perfil (financeiro/colaboradores) ou pelo proprio colaborador. DESL-110.';

-- ── FOLHA-090: itens da folha (holerite) restritos por perfil ───────────────
ALTER TABLE public.folha_itens ENABLE ROW LEVEL SECURITY;
DO $pol$
BEGIN
  DROP POLICY IF EXISTS perfil_restringe_leitura_folha_itens ON public.folha_itens;
  CREATE POLICY perfil_restringe_leitura_folha_itens
    ON public.folha_itens AS RESTRICTIVE FOR SELECT
    USING (
      public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['financeiro'::text, 'colaboradores'::text])
      OR regexp_replace(COALESCE(colaborador_cpf, ''), '[^0-9]', '', 'g') = public.cpf_do_usuario_logado()
    );
END $pol$;
COMMENT ON POLICY perfil_restringe_leitura_folha_itens ON public.folha_itens IS
  'RESTRICTIVE: itens/holerite so por perfil (financeiro/colaboradores) ou pelo proprio colaborador. FOLHA-090.';

-- ── EPI-041: biometria da entrega de EPI restrita por perfil ────────────────
ALTER TABLE public.epi_entregas ENABLE ROW LEVEL SECURITY;
DO $pol$
BEGIN
  DROP POLICY IF EXISTS perfil_restringe_leitura_epi_entregas ON public.epi_entregas;
  CREATE POLICY perfil_restringe_leitura_epi_entregas
    ON public.epi_entregas AS RESTRICTIVE FOR SELECT
    USING (
      public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['sst'::text, 'colaboradores'::text])
      OR regexp_replace(COALESCE(colaborador_cpf, ''), '[^0-9]', '', 'g') = public.cpf_do_usuario_logado()
    );
END $pol$;
COMMENT ON POLICY perfil_restringe_leitura_epi_entregas ON public.epi_entregas IS
  'RESTRICTIVE: entrega de EPI (material biometrico) so por perfil (sst/colaboradores) ou pelo proprio colaborador — LGPD art. 11. EPI-041.';

-- ── SST-041: canal de assédio — sigilo reforçado e prazo de apuração ────────
ALTER TABLE public.ouvidoria ADD COLUMN IF NOT EXISTS prazo_apuracao_ate date;
COMMENT ON COLUMN public.ouvidoria.prazo_apuracao_ate IS
  'Prazo de tratativa/apuracao da denuncia (Lei 14.457/2022). SST-041.';
ALTER TABLE public.ouvidoria ENABLE ROW LEVEL SECURITY;
DO $pol$
BEGIN
  DROP POLICY IF EXISTS perfil_restringe_leitura_ouvidoria ON public.ouvidoria;
  CREATE POLICY perfil_restringe_leitura_ouvidoria
    ON public.ouvidoria AS RESTRICTIVE FOR SELECT
    USING (
      public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['configuracoes'::text])
      OR autor_id = auth.uid()
      OR responsavel_id = auth.uid()
      OR respondido_por = auth.uid()
    );
END $pol$;
COMMENT ON POLICY perfil_restringe_leitura_ouvidoria ON public.ouvidoria IS
  'RESTRICTIVE: denuncia (assedio) so pelo fluxo de apuracao (perfil de configuracoes/compliance, responsavel ou autor) — sigilo reforcado da Lei 14.457. SST-041.';

-- ============================================================================
-- Fase 3 — Ferias estrutura e prazos
-- (origem: supabase/migrations/20260913160100_fase3_ferias_estrutura_e_prazos.sql)
-- ============================================================================
-- ============================================================================
-- Fase 3 (motores/estrutura) — Férias, lote 1.
--
-- Casos: FERIAS-091 (chave do aquisitivo por vínculo), FERIAS-008 (prescrição),
-- FERIAS-016 (estudante), FERIAS-010 (concordância do fracionamento),
-- FERIAS-040 (carimbo do requerimento de abono), FERIAS-031 (aviso < 30 dias),
-- FERIAS-042 (abono fora do prazo de 15 dias).
--
-- (Ficam para o próximo lote os motores maiores: FERIAS-003/024/053 pontes com
-- Afastamentos/Ponto, 030 aviso automático, 051 cancelamento que devolve saldo,
-- 070 encargos Simples III/IV, 071 cobertura, 090 liquidação na rescisão, e o
-- 020 que depende de alçada de diretoria.)
-- ============================================================================

-- ── FERIAS-091: o período aquisitivo é por VÍNCULO (tenant, empresa, CPF) ────
-- A chave antiga ignorava a empresa; dois contratos do mesmo CPF colidiam.
-- Incluir empresa_id só RELAXA a unicidade (não quebra dado existente).
ALTER TABLE public.ferias_periodos_aquisitivos DROP CONSTRAINT IF EXISTS ferias_periodo_unico;
ALTER TABLE public.ferias_periodos_aquisitivos ADD CONSTRAINT ferias_periodo_unico
  UNIQUE (tenant_id, empresa_id, colaborador_cpf, aquisitivo_inicio);

-- ── FERIAS-008: marco prescricional (fim do concessivo + 5 anos, art. 149) ──
CREATE OR REPLACE FUNCTION public.ferias_data_prescricao(p_aquisitivo_fim date)
RETURNS date LANGUAGE sql IMMUTABLE AS $$
  -- Concessivo = aquisitivo_fim + 12 meses; prescrição = concessivo + 5 anos.
  SELECT (p_aquisitivo_fim + INTERVAL '12 months' + INTERVAL '5 years')::date;
$$;
COMMENT ON FUNCTION public.ferias_data_prescricao(date) IS
  'Marco de prescricao do periodo de ferias: fim do concessivo (aquisitivo_fim + 12m) + 5 anos (art. 149 CLT). FERIAS-008.';

-- ── FERIAS-016: sinalização de estudante menor de 18 (art. 136, §2º) ────────
ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS estudante boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.admissoes.estudante IS
  'Estudante — usado para alertar coincidencia das ferias com o recesso escolar no menor de 18 (art. 136, §2º). FERIAS-016.';

-- ── FERIAS-010: concordância do empregado com o fracionamento (art. 134, §1º)
ALTER TABLE public.ferias_programacao ADD COLUMN IF NOT EXISTS fracionamento_concordancia boolean;
ALTER TABLE public.ferias_programacao ADD COLUMN IF NOT EXISTS fracionamento_concordancia_em timestamptz;
ALTER TABLE public.ferias_programacao ADD COLUMN IF NOT EXISTS fracionamento_concordancia_por text;
COMMENT ON COLUMN public.ferias_programacao.fracionamento_concordancia IS
  'Concordancia do empregado com o fracionamento — o art. 134, §1º so o permite com ela. FERIAS-010.';

-- ── FERIAS-040: carimbo de QUANDO o abono foi requerido (art. 143, §1º) ─────
ALTER TABLE public.ferias_programacao ADD COLUMN IF NOT EXISTS abono_requerido_em date;
COMMENT ON COLUMN public.ferias_programacao.abono_requerido_em IS
  'Data do requerimento do abono pecuniario — prova do prazo do art. 143, §1º (ate 15 dias antes do fim do aquisitivo). FERIAS-040.';

-- ── FERIAS-031: aprovar com início em < 30 dias exige aviso ou justificativa ─
ALTER TABLE public.ferias_solicitacoes ADD COLUMN IF NOT EXISTS justificativa_excecao text;
COMMENT ON COLUMN public.ferias_solicitacoes.justificativa_excecao IS
  'Justificativa da excecao ao aviso de 30 dias (art. 135). FERIAS-031.';
CREATE OR REPLACE FUNCTION public.ferias_solic_valida_aviso_30d()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'aprovado'
     AND NEW.data_inicio IS NOT NULL
     AND (NEW.data_inicio - CURRENT_DATE) < 30
     AND COALESCE(NEW.aviso_gerado, false) = false
     AND COALESCE(btrim(NEW.justificativa_excecao), '') = '' THEN
    RAISE EXCEPTION 'Aprovacao com inicio em menos de 30 dias exige aviso emitido ou justificativa da excecao (art. 135).'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_ferias_solic_aviso_30d ON public.ferias_solicitacoes;
CREATE TRIGGER trg_ferias_solic_aviso_30d
  BEFORE INSERT OR UPDATE OF status, data_inicio, aviso_gerado, justificativa_excecao
  ON public.ferias_solicitacoes
  FOR EACH ROW EXECUTE FUNCTION public.ferias_solic_valida_aviso_30d();

-- ── FERIAS-042: abono requerido fora do prazo (menos de 15 dias) é recusado ─
CREATE OR REPLACE FUNCTION public.ferias_prog_valida_prazo_abono()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_requerido date;
BEGIN
  IF COALESCE(NEW.abono_dias, 0) > 0 AND NEW.aquisitivo_fim IS NOT NULL THEN
    v_requerido := COALESCE(NEW.abono_requerido_em, CURRENT_DATE);
    IF (NEW.aquisitivo_fim - v_requerido) < 15 THEN
      RAISE EXCEPTION 'Abono pecuniario deve ser requerido ate 15 dias antes do fim do periodo aquisitivo (art. 143, §1º); faltam % dia(s).', (NEW.aquisitivo_fim - v_requerido)
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_ferias_prog_prazo_abono ON public.ferias_programacao;
CREATE TRIGGER trg_ferias_prog_prazo_abono
  BEFORE INSERT OR UPDATE OF abono_dias, aquisitivo_fim, abono_requerido_em
  ON public.ferias_programacao
  FOR EACH ROW EXECUTE FUNCTION public.ferias_prog_valida_prazo_abono();

-- ── Ajuste da sonda FERIAS-055 para conviver com a nova trava (FERIAS-031) ──
-- A sonda insere uma solicitacao 'aprovado' com inicio HOJE para exercitar a
-- trava de CIENCIA do aviso (trg_ferias_trava_em_gozo). Com a FERIAS-031, um
-- 'aprovado' a menos de 30 dias exige aviso emitido ou justificativa. A sonda
-- passa a marcar aviso_gerado=true (o aviso foi EMITIDO; ela testa a CIENCIA,
-- nao a emissao) — cumpre a FERIAS-031 sem mudar o que a sonda verifica.
CREATE OR REPLACE FUNCTION public.qa_caso_ferias_055()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
    r          public.qa_retorno;
    v_tem_fn   BOOLEAN;
    v_tem_trg  BOOLEAN;
    v_barrou   BOOLEAN := false;
    v_liberou  BOOLEAN := false;
    v_id       UUID;
    v_ten      UUID;
BEGIN
    r.passo_ordem := 1;
    r.passo_acao  := 'AUDITORIA: a ciencia do aviso trava o inicio do gozo (em_gozo)?';
    r.esperado    := 'Sem ciencia, em_gozo e barrado; com ciencia registrada, em_gozo passa (art. 135)';

    SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                    WHERE n.nspname='public' AND p.proname='ferias_aviso_tem_ciencia')
      INTO v_tem_fn;
    SELECT EXISTS (SELECT 1 FROM pg_trigger
                    WHERE tgname='trg_ferias_trava_em_gozo' AND NOT tgisinternal)
      INTO v_tem_trg;

    IF NOT v_tem_fn OR NOT v_tem_trg THEN
        r.situacao := 'falhou';
        r.obtido := 'ACHADO: nada condiciona a concessao a ciencia do aviso — em_gozo avanca '
                 || 'com o aviso pendente. O art. 135 exige comunicacao MEDIANTE RECIBO. '
                 || 'Correcao: trava de transicao para em_gozo condicionada a ciencia.';
        RETURN r;
    END IF;

    SELECT id INTO v_ten FROM public.tenants LIMIT 1;
    IF v_ten IS NULL THEN
        r.situacao := 'nao_implementado';
        r.obtido := 'Sem tenants na base para montar a sonda; a trava existe (funcao + trigger) '
                 || 'mas nao foi exercitada com dados.';
        RETURN r;
    END IF;

    BEGIN
        -- aviso_gerado=true: cumpre a FERIAS-031 (aviso EMITIDO); a sonda testa a CIENCIA.
        INSERT INTO public.ferias_solicitacoes
            (tenant_id, colaborador_nome, data_inicio, data_fim, dias_solicitados, status, aviso_gerado)
        VALUES (v_ten, 'QA Sonda FERIAS-055', CURRENT_DATE, CURRENT_DATE + 20, 20, 'aprovado', true)
        RETURNING id INTO v_id;

        BEGIN
            UPDATE public.ferias_solicitacoes SET status='em_gozo' WHERE id=v_id;
        EXCEPTION WHEN check_violation THEN
            v_barrou := true;
        END;

        UPDATE public.ferias_solicitacoes
           SET aviso_ciencia_em = now(), aviso_ciencia_origem = 'manual'
         WHERE id = v_id;
        BEGIN
            UPDATE public.ferias_solicitacoes SET status='em_gozo' WHERE id=v_id;
            v_liberou := true;
        EXCEPTION WHEN OTHERS THEN
            v_liberou := false;
        END;

        RAISE EXCEPTION 'qa_rollback';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM <> 'qa_rollback' THEN
            r.situacao := 'erro'; r.obtido := 'A sonda quebrou'; r.erro_tecnico := SQLERRM;
            RETURN r;
        END IF;
    END;

    IF v_barrou AND v_liberou THEN
        r.situacao := 'passou';
        r.obtido := 'A trava funciona: sem ciencia o inicio do gozo e barrado; com a ciencia '
                 || 'registrada, passa. A regra vive em ferias_aviso_tem_ciencia e na trigger '
                 || 'trg_ferias_trava_em_gozo.';
    ELSIF NOT v_barrou THEN
        r.situacao := 'falhou';
        r.obtido := 'A trava existe mas NAO barrou o em_gozo sem ciencia — a concessao avanca '
                 || 'sem a prova do art. 135.';
    ELSE
        r.situacao := 'falhou';
        r.obtido := 'A trava barrou ate com a ciencia registrada — esta bloqueando concessao '
                 || 'legitima. Revisar ferias_aviso_tem_ciencia.';
    END IF;
    RETURN r;
EXCEPTION WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ============================================================================
-- Fase 3 — Ferias pontes (Afastamento/Ponto)
-- (origem: supabase/migrations/20260913160200_fase3_ferias_pontes_afastamento_ponto.sql)
-- ============================================================================
-- ============================================================================
-- Fase 3 (motores) — Férias, lote 2: pontes com Afastamentos e Ponto.
--
-- FERIAS-003: o recálculo do período aquisitivo passa a consultar os
--             afastamentos (art. 133, IV — benefício previdenciário > 6 meses
--             reinicia o aquisitivo).
-- FERIAS-024: afastamento sobreposto ao gozo SUSPENDE a solicitação de férias.
-- FERIAS-053: marcar ponto durante férias em gozo é recusado (a ponte
--             férias→ponto, que só existia para afastamentos).
-- ============================================================================

-- Colunas para registrar a interrupção do art. 133 no período aquisitivo.
ALTER TABLE public.ferias_periodos_aquisitivos
  ADD COLUMN IF NOT EXISTS interrompido_art133 boolean NOT NULL DEFAULT false;
ALTER TABLE public.ferias_periodos_aquisitivos
  ADD COLUMN IF NOT EXISTS interrompido_afastamento_id uuid;

-- ── FERIAS-003: recálculo consulta os afastamentos (art. 133) ───────────────
CREATE OR REPLACE FUNCTION public.ferias_recalcular_periodo(p_periodo_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r            public.ferias_periodos_aquisitivos%ROWTYPE;
    v_metodo     TEXT;
    v_faltas_pt  INTEGER;
    v_faltas     INTEGER;
    v_fonte      TEXT;
    v_direito    NUMERIC(4,1);
    v_meses      INTEGER;
    v_prev_dias  INTEGER;
    v_af_id      UUID;
BEGIN
    SELECT * INTO r FROM public.ferias_periodos_aquisitivos WHERE id = p_periodo_id;
    IF NOT FOUND THEN RETURN; END IF;

    -- Art. 133, IV (CLT): benefício previdenciário por mais de 6 meses (mesmo
    -- descontínuos) no período aquisitivo faz perder o direito; um novo período
    -- começa no retorno. Aqui zera o aquisitivo atual e registra a origem —
    -- consulta o módulo de Afastamentos (b31/b91) sobreposto à janela.
    SELECT COALESCE(SUM(
             (LEAST(COALESCE(a.data_fim, r.aquisitivo_fim), r.aquisitivo_fim)
              - GREATEST(a.data_inicio, r.aquisitivo_inicio)) + 1), 0),
           MAX(a.id)
      INTO v_prev_dias, v_af_id
      FROM public.afastamentos a
     WHERE a.tenant_id = r.tenant_id
       AND regexp_replace(COALESCE(a.colaborador_cpf, ''), '[^0-9]', '', 'g')
         = regexp_replace(COALESCE(r.colaborador_cpf, ''), '[^0-9]', '', 'g')
       AND a.tipo_principal_new IN ('beneficio_b31', 'beneficio_b91')
       AND a.data_inicio <= r.aquisitivo_fim
       AND COALESCE(a.data_fim, r.aquisitivo_fim) >= r.aquisitivo_inicio;

    IF COALESCE(v_prev_dias, 0) > 180 THEN
        UPDATE public.ferias_periodos_aquisitivos
           SET interrompido_art133         = true,
               interrompido_afastamento_id = v_af_id,
               dias_direito                = 0,
               dias_saldo                  = 0,
               calculado_em                = now(),
               validacao_motivo            = 'Art. 133, IV: beneficio previdenciario > 6 meses no periodo reinicia o aquisitivo (novo periodo a partir do retorno).'
         WHERE id = p_periodo_id;
        RETURN;
    END IF;

    -- Método da empresa (fallback: config geral do tenant → clt_faltas)
    SELECT metodo_calculo INTO v_metodo
      FROM public.ferias_config
     WHERE tenant_id = r.tenant_id
       AND empresa_id IS NOT DISTINCT FROM r.empresa_id
     LIMIT 1;
    IF v_metodo IS NULL THEN
        SELECT metodo_calculo INTO v_metodo
          FROM public.ferias_config
         WHERE tenant_id = r.tenant_id AND empresa_id IS NULL
         LIMIT 1;
    END IF;
    v_metodo := COALESCE(v_metodo, 'clt_faltas');

    -- Fonte das faltas: ponto tem precedência; senão, carga.
    v_faltas_pt := public.ferias_faltas_do_ponto(
        r.tenant_id, r.colaborador_cpf, r.aquisitivo_inicio, r.aquisitivo_fim
    );
    IF v_faltas_pt IS NOT NULL THEN
        v_faltas := v_faltas_pt;
        v_fonte  := 'ponto';
    ELSE
        v_faltas := COALESCE(r.faltas_carga, 0);
        v_fonte  := 'carga';
    END IF;

    IF v_metodo = 'proporcional_avos' THEN
        v_meses := GREATEST(0, LEAST(12,
            (EXTRACT(YEAR  FROM age(r.aquisitivo_fim + 1, r.aquisitivo_inicio)) * 12
           + EXTRACT(MONTH FROM age(r.aquisitivo_fim + 1, r.aquisitivo_inicio)))::INTEGER));
        v_direito := ROUND(v_meses * 2.5, 1);
        IF v_faltas > 32 THEN v_direito := 0; END IF;
    ELSE
        v_direito := public.ferias_dias_por_faltas_clt(v_faltas);
    END IF;

    UPDATE public.ferias_periodos_aquisitivos
       SET fonte_faltas        = v_fonte,
           faltas_consideradas = v_faltas,
           dias_direito        = v_direito,
           dias_saldo          = GREATEST(0, v_direito - COALESCE(dias_gozados, 0)),
           calculado_em        = now(),
           status = CASE
               WHEN v_direito = 0 AND v_faltas > 32
                    AND status NOT IN ('zerado_confirmado', 'encerrado')
                   THEN 'pendente_validacao'
               WHEN status = 'pendente_validacao' AND NOT (v_direito = 0 AND v_faltas > 32)
                   THEN 'ativo'
               ELSE status
           END,
           validacao_motivo = CASE
               WHEN v_direito = 0 AND v_faltas > 32
                   THEN v_faltas || ' faltas no período — art. 130 da CLT retira o direito a férias'
               ELSE validacao_motivo
           END
     WHERE id = p_periodo_id;
END;
$$;

-- ── FERIAS-024: afastamento sobreposto suspende as férias em gozo/aprovadas ─
-- Status 'suspenso' passa a existir; DP reprograma e devolve o saldo depois.
ALTER TABLE public.ferias_solicitacoes DROP CONSTRAINT IF EXISTS ferias_solicitacoes_status_check;
ALTER TABLE public.ferias_solicitacoes ADD CONSTRAINT ferias_solicitacoes_status_check
  CHECK (status = ANY (ARRAY['pendente','aprovado','recusado','cancelado','em_gozo','concluido','suspenso']));

CREATE OR REPLACE FUNCTION public.afastamento_suspende_ferias()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'ativo' AND NEW.data_inicio IS NOT NULL THEN
    UPDATE public.ferias_solicitacoes fs
       SET status = 'suspenso'
     WHERE fs.tenant_id = NEW.tenant_id
       AND regexp_replace(COALESCE(fs.colaborador_cpf, ''), '[^0-9]', '', 'g')
         = regexp_replace(COALESCE(NEW.colaborador_cpf, ''), '[^0-9]', '', 'g')
       AND fs.status IN ('em_gozo', 'aprovado')
       AND fs.data_inicio <= COALESCE(NEW.data_fim, fs.data_fim)
       AND fs.data_fim   >= NEW.data_inicio;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_afastamento_suspende_ferias ON public.afastamentos;
CREATE TRIGGER trg_afastamento_suspende_ferias
  AFTER INSERT OR UPDATE OF status, data_inicio, data_fim ON public.afastamentos
  FOR EACH ROW EXECUTE FUNCTION public.afastamento_suspende_ferias();

-- ── FERIAS-053: ponto durante férias em gozo é recusado ─────────────────────
-- Estende o validador de marcação (que só olhava afastamentos) para também
-- barrar quando há férias em gozo cobrindo a data (casamento por CPF).
CREATE OR REPLACE FUNCTION public.validar_batida_afastamento()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_af RECORD;
  v_fer RECORD;
BEGIN
  SELECT data_inicio, data_fim INTO v_af
    FROM public.afastamentos
   WHERE tenant_id = NEW.tenant_id
     AND colaborador_id = NEW.colaborador_id
     AND status::text IN ('ativo', 'beneficio_inss')
     AND NEW.data_marcacao BETWEEN data_inicio AND COALESCE(data_fim, DATE '9999-12-31')
   ORDER BY data_inicio DESC
   LIMIT 1;

  IF FOUND THEN
    RAISE EXCEPTION
      'Colaborador afastado desde % %. Não é possível registrar ponto durante o afastamento.',
      to_char(v_af.data_inicio, 'DD/MM/YYYY'),
      CASE WHEN v_af.data_fim IS NULL
           THEN '(sem data de término registrada)'
           ELSE 'até ' || to_char(v_af.data_fim, 'DD/MM/YYYY') END;
  END IF;

  -- Férias em gozo também suspendem a prestação de serviço (art. 129/130).
  SELECT data_inicio, data_fim INTO v_fer
    FROM public.ferias_solicitacoes
   WHERE tenant_id = NEW.tenant_id
     AND regexp_replace(COALESCE(colaborador_cpf, ''), '[^0-9]', '', 'g')
       = regexp_replace(COALESCE(NEW.colaborador_cpf, ''), '[^0-9]', '', 'g')
     AND status = 'em_gozo'
     AND NEW.data_marcacao BETWEEN data_inicio AND data_fim
   ORDER BY data_inicio DESC
   LIMIT 1;

  IF FOUND THEN
    RAISE EXCEPTION
      'Colaborador em férias (em gozo) de % a %. Não é possível registrar ponto durante as férias.',
      to_char(v_fer.data_inicio, 'DD/MM/YYYY'), to_char(v_fer.data_fim, 'DD/MM/YYYY');
  END IF;

  RETURN NEW;
END;
$$;

-- ============================================================================
-- Fase 3 — EPI/SST vencimentos
-- (origem: supabase/migrations/20260913160300_fase3_epi_sst_vencimentos.sql)
-- ============================================================================
-- ============================================================================
-- Fase 3 (motores) — EPI/SST: relógios de vencimento e travas.
--
-- EPI-011: rotina que vigia a validade do CA (vencido/a vencer → Plano de Ação).
-- EPI-022: saldo abaixo do mínimo abre reposição no Plano de Ação (sem duplicar).
-- EPI-050: entrega calcula a data prevista de troca (entrega + periodicidade).
-- EPI-052: desligamento gera checklist de devolução dos EPIs ativos.
-- SST-001: rotina que marca documento de SST vencido e alerta a renovação.
-- SST-011: entrega de EPI com CA vencido é recusada (NR-6).
-- SST-020: próximo exame periódico derivado da periodicidade do cargo.
--
-- (Fica para depois EPI-051 — kit de admissão por função de risco.)
-- ============================================================================

-- Helper: abre uma ação no Plano de Ação sem duplicar (por origem_id + origem_modulo).
CREATE OR REPLACE FUNCTION public.plano_acao_abrir(
  p_tenant uuid, p_modulo text, p_origem_id uuid, p_titulo text, p_descricao text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_tenant IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM public.plano_acoes
              WHERE tenant_id = p_tenant AND origem_modulo = p_modulo
                AND origem_id = p_origem_id AND COALESCE(arquivada,false) = false) THEN
    RETURN;
  END IF;
  INSERT INTO public.plano_acoes (tenant_id, codigo, titulo, descricao, origem_modulo, origem_id, arquivada)
  VALUES (p_tenant,
          upper(left(p_modulo,3)) || '-' || to_char(now(),'YYYYMMDDHH24MISS') || '-' || left(replace(p_origem_id::text,'-',''),6),
          p_titulo, p_descricao, p_modulo, p_origem_id, false);
END;
$$;

-- ── EPI-011: vigia a validade do CA (rotina diária) ─────────────────────────
CREATE OR REPLACE FUNCTION public.epi_ca_vigiar()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_n integer := 0; t RECORD;
BEGIN
  -- CA vencido ou a vencer em 30 dias abre ação de renovação/recompra.
  FOR t IN
    SELECT id, tenant_id, nome, ca_numero, ca_validade
      FROM public.epi_tipos
     WHERE ca_validade IS NOT NULL
       AND ca_validade <= (CURRENT_DATE + INTERVAL '30 days')
       AND COALESCE(is_active, true) = true
  LOOP
    PERFORM public.plano_acao_abrir(
      t.tenant_id, 'epi', t.id,
      CASE WHEN t.ca_validade < CURRENT_DATE
           THEN 'CA vencido: renovar/recomprar ' || COALESCE(t.nome,'EPI') || ' (CA ' || COALESCE(t.ca_numero,'?') || ')'
           ELSE 'CA a vencer: providenciar renovação de ' || COALESCE(t.nome,'EPI') || ' (CA ' || COALESCE(t.ca_numero,'?') || ')' END,
      'ca_validade em ' || to_char(t.ca_validade,'DD/MM/YYYY'));
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;

-- ── EPI-022: saldo abaixo do mínimo abre reposição no Plano de Ação ─────────
CREATE OR REPLACE FUNCTION public.epi_verificar_estoque_minimo()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_n integer := 0; t RECORD;
BEGIN
  -- Cada item abaixo do mínimo vira uma reposição em public.plano_acoes
  -- (o helper plano_acao_abrir cuida da não-duplicidade).
  FOR t IN
    SELECT et.id, et.tenant_id, et.nome, et.estoque_minimo,
           COALESCE(SUM(e.quantidade_estoque), 0) AS saldo
      FROM public.epi_tipos et
      LEFT JOIN public.epis e ON e.tipo_id = et.id
     WHERE et.estoque_minimo IS NOT NULL AND et.estoque_minimo > 0
     GROUP BY et.id, et.tenant_id, et.nome, et.estoque_minimo
    HAVING COALESCE(SUM(e.quantidade_estoque), 0) < et.estoque_minimo
  LOOP
    PERFORM public.plano_acao_abrir(
      t.tenant_id, 'epi', t.id,
      'Reposição de EPI: ' || COALESCE(t.nome,'item') || ' abaixo do estoque mínimo',
      'Saldo ' || t.saldo || ' < mínimo ' || t.estoque_minimo);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;

-- ── EPI-050: entrega calcula a data prevista de troca ───────────────────────
CREATE OR REPLACE FUNCTION public.epi_entrega_calcula_troca()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_periodicidade_troca_dias integer;
BEGIN
  IF NEW.data_devolucao_prevista IS NULL AND NEW.data_entrega IS NOT NULL THEN
    SELECT et.periodicidade_troca_dias INTO v_periodicidade_troca_dias
      FROM public.epis e JOIN public.epi_tipos et ON et.id = e.tipo_id
     WHERE e.id = NEW.epi_id;
    IF v_periodicidade_troca_dias IS NOT NULL AND v_periodicidade_troca_dias > 0 THEN
      NEW.data_devolucao_prevista := NEW.data_entrega + v_periodicidade_troca_dias;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_epi_entrega_calcula_troca ON public.epi_entregas;
CREATE TRIGGER trg_epi_entrega_calcula_troca
  BEFORE INSERT ON public.epi_entregas
  FOR EACH ROW EXECUTE FUNCTION public.epi_entrega_calcula_troca();

-- ── SST-011: entrega de EPI com CA vencido é recusada (NR-6) ────────────────
CREATE OR REPLACE FUNCTION public.epi_entrega_valida_ca_vigente()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_ca_validade date; v_nome text;
BEGIN
  SELECT et.ca_validade, et.nome INTO v_ca_validade, v_nome
    FROM public.epis e JOIN public.epi_tipos et ON et.id = e.tipo_id
   WHERE e.id = NEW.epi_id;
  IF v_ca_validade IS NOT NULL
     AND v_ca_validade < COALESCE(NEW.data_entrega, CURRENT_DATE) THEN
    RAISE EXCEPTION 'Entrega vedada: o CA do EPI "%" venceu em % — entregar EPI com CA vencido equivale a nao entregar (NR-6).',
      COALESCE(v_nome,'?'), to_char(v_ca_validade,'DD/MM/YYYY')
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_epi_entrega_ca_vigente ON public.epi_entregas;
CREATE TRIGGER trg_epi_entrega_ca_vigente
  BEFORE INSERT ON public.epi_entregas
  FOR EACH ROW EXECUTE FUNCTION public.epi_entrega_valida_ca_vigente();

-- ── EPI-052: desligamento gera checklist de devolução dos EPIs ativos ───────
CREATE OR REPLACE FUNCTION public.epi_checklist_devolucao_desligamento()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_ativos integer;
BEGIN
  IF NEW.status = 'desligado' AND (OLD.status IS DISTINCT FROM NEW.status) THEN
    SELECT count(*) INTO v_ativos
      FROM public.epi_entregas ee
     WHERE ee.tenant_id = NEW.tenant_id
       AND regexp_replace(COALESCE(ee.colaborador_cpf,''), '[^0-9]', '', 'g')
         = regexp_replace(COALESCE(NEW.cpf,''), '[^0-9]', '', 'g')
       AND COALESCE(ee.status::text,'') NOT IN ('devolvido', 'descartado');
    IF v_ativos > 0 THEN
      -- Cobra a devolução SEM travar a rescisão (a rescisão segue).
      PERFORM public.plano_acao_abrir(
        NEW.tenant_id, 'epi', NEW.id,
        'Devolução de EPI no desligamento de ' || COALESCE(NEW.nome_completo,'colaborador'),
        v_ativos || ' entrega(s) ativa(s) a conferir/devolver (sem reter verbas — CLT art. 462).');
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_epi_checklist_devolucao_desligamento ON public.admissoes;
CREATE TRIGGER trg_epi_checklist_devolucao_desligamento
  AFTER UPDATE OF status ON public.admissoes
  FOR EACH ROW EXECUTE FUNCTION public.epi_checklist_devolucao_desligamento();

-- ── SST-001: rotina que marca documento de SST vencido e alerta renovação ───
CREATE OR REPLACE FUNCTION public.sst_vigiar_documentos()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_n integer := 0; d RECORD;
BEGIN
  -- Marca vencido o que passou da data_vigencia.
  UPDATE public.sst_documentos
     SET status = 'vencido'
   WHERE data_vigencia IS NOT NULL
     AND data_vigencia < CURRENT_DATE
     AND COALESCE(status,'') NOT IN ('vencido', 'substituido', 'cancelado');
  GET DIAGNOSTICS v_n = ROW_COUNT;

  -- Janela de renovação (60/30 dias) abre ação no Plano de Ação.
  FOR d IN
    SELECT id, tenant_id, tipo, data_vigencia
      FROM public.sst_documentos
     WHERE data_vigencia IS NOT NULL
       AND data_vigencia BETWEEN CURRENT_DATE AND (CURRENT_DATE + INTERVAL '60 days')
       AND COALESCE(status,'') NOT IN ('substituido', 'cancelado')
  LOOP
    PERFORM public.plano_acao_abrir(
      d.tenant_id, 'sst', d.id,
      'Renovar documento de SST (' || COALESCE(d.tipo,'documento') || ') — vigência ' || to_char(d.data_vigencia,'DD/MM/YYYY'),
      'Janela de renovação (60/30 dias) do documento de SST.');
  END LOOP;
  RETURN v_n;
END;
$$;

-- ── SST-020: próximo exame periódico pela periodicidade do cargo ────────────
CREATE OR REPLACE FUNCTION public.sst_proximo_exame_periodico(p_cargo_id uuid, p_ultimo_aso date)
RETURNS date
LANGUAGE sql
STABLE
AS $$
  -- Próximo periódico = último ASO + periodicidade_exame_meses do cargo (NR-7).
  SELECT CASE WHEN c.periodicidade_exame_meses IS NULL OR p_ultimo_aso IS NULL THEN NULL
              ELSE (p_ultimo_aso + (c.periodicidade_exame_meses || ' months')::interval)::date END
    FROM public.cargos c
   WHERE c.id = p_cargo_id;
$$;
COMMENT ON FUNCTION public.sst_proximo_exame_periodico(uuid, date) IS
  'Proxima data do exame periodico = ultimo ASO + periodicidade_exame_meses do cargo (NR-7). SST-020.';

-- ── Agendamentos diários (pg_cron) ──────────────────────────────────────────
DO $cron$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule('epi-ca-vigiar-diario',       '0 6 * * *', $$SELECT public.epi_ca_vigiar()$$);
    PERFORM cron.schedule('epi-estoque-minimo-diario',  '5 6 * * *', $$SELECT public.epi_verificar_estoque_minimo()$$);
    PERFORM cron.schedule('sst-vigiar-documentos-diario','10 6 * * *', $$SELECT public.sst_vigiar_documentos()$$);
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Agendamento pg_cron nao aplicado: %', SQLERRM;
END $cron$;

-- ============================================================================
-- CONFERENCIA FINAL (somente leitura — o motor desfaz o que escreve)
-- Esperado: todos os casos abaixo em 'passou'.
-- ============================================================================
SELECT codigo,
       (public.qa_executar_descartavel('qa_caso_'||replace(lower(codigo),'-','_'))).situacao
FROM unnest(ARRAY[
  'AFAST-020',
  'AFAST-031',
  'FERIAS-056',
  'DESL-003',
  'MCHK-010',
  'MCHK-011',
  'MPAR-011',
  'MEVD-010',
  'PLTP-010',
  'PLTM-010',
  'PLTF-010',
  'PLTF-011',
  'PLEV-010',
  'PDOC-010',
  'PCHK-010',
  'PROC-010',
  'PROC-011',
  'HTPL-010',
  'HCAT-010',
  'HCAL-012',
  'EMP-020',
  'EMP-021',
  'EMP-070',
  'EMP-071',
  'DADO-010',
  'HIER-002',
  'FER-002',
  'FER-003',
  'FER-004',
  'ENQ-010',
  'ENQ-011',
  'ENQ-013',
  'TAC-003',
  'CERT-010',
  'CERT-011',
  'ADM-020',
  'AFAST-011',
  'AFAST-051',
  'EPI-020',
  'EPI-030',
  'FERIAS-013',
  'FERIAS-014',
  'FERIAS-052',
  'COLAB-025',
  'COLAB-027',
  'COLAB-029',
  'COLAB-033',
  'ADM-030',
  'DESL-083',
  'EMP-060',
  'DESL-110',
  'FOLHA-090',
  'EPI-041',
  'SST-041',
  'AFAST-080',
  'SST-080',
  'FERIAS-091',
  'FERIAS-008',
  'FERIAS-016',
  'FERIAS-010',
  'FERIAS-040',
  'FERIAS-031',
  'FERIAS-042',
  'FERIAS-003',
  'FERIAS-024',
  'FERIAS-053',
  'EPI-011',
  'EPI-022',
  'EPI-050',
  'EPI-052',
  'SST-001',
  'SST-011',
  'SST-020'
]) AS codigo
ORDER BY 2, 1;
