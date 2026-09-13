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
