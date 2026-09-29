-- ============================================================================
-- ENTREGA — INTEGRIDADE: Metas + Plano de Ação + Hub Contábil (16 casos)
--
-- Cole INTEIRO no SQL Editor da HOMOLOGAÇÃO; depois de conferido, o MESMO na
-- PRODUÇÃO. Traz as guardas de integridade já verdes no teste (via migrations)
-- e nunca coladas aqui. São CHECKs e triggers que fazem o banco recusar dado
-- impossível — todos os CHECK são NOT VALID (valem para linha nova/alterada,
-- não quebram em cima de dado legado).
--
-- Cobre: MCHK-002, MCHK-010, MEVD-010, MPAR-011 (Metas);
--        PLEV-010, PLTF-010, PLTF-011, PLTM-010, PLTP-010 (Plano de Ação);
--        CERT-010, CERT-011, HCAT-010, HTPL-010, PCHK-010, PDOC-010, PROC-010 (Hub).
--   (de brinde, a parte 1 também cobre MCHK-011, PROC-011, HCAL-012.)
--
-- SEGURANÇA: NÃO cria tabela (sem a pegadinha do auto-RLS do editor); só ALTER
-- ADD CONSTRAINT (CHECK NOT VALID), CREATE OR REPLACE FUNCTION e CREATE TRIGGER.
-- Idempotente, roda numa transação.
--
-- Origem (só as partes destes 3 módulos): fase1 20260913150300 (Metas/Plano/Hub,
-- inteiro), fase1 20260913150400 (só o bloco CERTIDÕES) e fase4 20260915180000
-- (só MCHK-002). Ao fim, conferência única — esperado tudo 'ok'.
-- ============================================================================

SET lock_timeout = '10s';

-- ════════════════════ 1) METAS + PLANO + HUB (guardas de integridade) ═════════
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

-- ════════════════════ 2) HUB — CERTIDÕES (CERT-010, CERT-011) ═════════════════
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

-- ════════════════════ 3) METAS — MCHK-002 (check-in reflete na meta) ══════════
-- ── MCHK-002: check-in reflete na meta ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.meta_checkin_aplica_na_meta()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  -- O check-in é a fonte: aplica valor e progresso na meta e deriva o status
  -- (100% => concluida; >0 => em_andamento). Nao mexe em metas canceladas.
  UPDATE public.metas m
     SET valor_atual = COALESCE(NEW.valor_novo, m.valor_atual),
         progresso   = COALESCE(NEW.progresso_novo, m.progresso),
         status = CASE
           WHEN m.status = 'cancelada' THEN m.status
           WHEN COALESCE(NEW.progresso_novo, m.progresso) >= 100 THEN 'concluida'::meta_status
           WHEN COALESCE(NEW.progresso_novo, m.progresso) > 0   THEN 'em_andamento'::meta_status
           ELSE m.status
         END
   WHERE m.id = NEW.meta_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_meta_checkin_aplica_na_meta ON public.metas_checkins;
CREATE TRIGGER trg_meta_checkin_aplica_na_meta
  AFTER INSERT ON public.metas_checkins
  FOR EACH ROW EXECUTE FUNCTION public.meta_checkin_aplica_na_meta();

-- ════════════════════ CONFERÊNCIA (única — esperado tudo 'ok') ════════════════
WITH alvo(item, presente) AS (
  VALUES
    ('MCHK-002 · check-in reflete na meta',   EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='meta_checkin_aplica_na_meta')),
    ('MCHK-010 · progresso 0..100',           EXISTS(SELECT 1 FROM pg_constraint WHERE conname='chk_metas_checkins_progresso_faixa')),
    ('MEVD-010 · evidência não vazia',        EXISTS(SELECT 1 FROM pg_constraint WHERE conname='chk_metas_evidencias_nao_vazia')),
    ('MPAR-011 · peso > 0',                   EXISTS(SELECT 1 FROM pg_constraint WHERE conname='chk_metas_participantes_peso_positivo')),
    ('PLEV-010 · evidência valida tarefa',    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='plano_evidencia_valida_tarefa')),
    ('PLTF-010/011 · dependência (anti-ciclo/mesma ação)', EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='plano_tarefa_valida_dependencia')),
    ('PLTM-010 · tempo fim>=inicio e duração>=0', EXISTS(SELECT 1 FROM pg_constraint WHERE conname='chk_plano_tempo_intervalo')),
    ('PLTP-010 · template exige título',      EXISTS(SELECT 1 FROM pg_constraint WHERE conname='chk_plano_templates_tem_titulo')),
    ('CERT-010 · emissão <= validade',        EXISTS(SELECT 1 FROM pg_constraint WHERE conname='chk_hub_certidoes_datas')),
    ('CERT-011 · irregular prevalece',        (SELECT pg_get_functiondef(p.oid) ILIKE '%irregular%' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='atualizar_status_certidao' LIMIT 1)),
    ('HCAT-010 · obrigatoriedade + retenção >=0', (EXISTS(SELECT 1 FROM pg_constraint WHERE conname='chk_hub_catalogo_obrigatoriedade') AND EXISTS(SELECT 1 FROM pg_constraint WHERE conname='chk_hub_catalogo_retencao_nao_negativa'))),
    ('HTPL-010 · tipo no enum',               EXISTS(SELECT 1 FROM pg_constraint WHERE conname='chk_htpl_tipo_no_enum')),
    ('PCHK-010 · conclusão confere checklist', EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='hub_processo_valida_conclusao')),
    ('PDOC-010 · versão do mesmo processo',   EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='hub_documento_valida_versao_anterior')),
    ('PROC-010 · prazo >= referência',        EXISTS(SELECT 1 FROM pg_constraint WHERE conname='chk_hub_processos_prazo_coerente'))
)
SELECT item, CASE WHEN presente THEN 'ok' ELSE 'FALTOU' END AS situacao FROM alvo ORDER BY item;
