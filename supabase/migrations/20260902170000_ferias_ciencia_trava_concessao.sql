-- =========================================================
-- Ferias — a ciencia do aviso trava o inicio do gozo (RF-003 / CA-005)
--
-- PROBLEMA: o aviso de ferias podia ser emitido sem coleta de ciencia, e
-- nada impedia o gozo comecar mesmo assim. O documento YE-DP-FERIAS-001
-- (CA-005, cenario "Aviso sem ciencia -> nao conclui a concessao") exige
-- que a concessao so se conclua com o aviso cientificado.
--
-- ENTREGA (banco):
--   1) marca da ciencia na propria solicitacao (aviso_ciencia_em/origem/por),
--      com valvula para ciencia colhida em papel — a trava nao pode paralisar
--      quem nao usa assinatura digital;
--   2) quando um link de assinatura do AVISO e assinado, a ciencia e marcada
--      na solicitacao automaticamente (trigger no banco, independe do front);
--   3) ferias_aviso_tem_ciencia(solicitacao) — a regra em um lugar so;
--   4) trava: a transicao para 'em_gozo' exige ciencia (gesto manual);
--   5) a rotina que promove aprovado->em_gozo pela data passa a promover SO
--      quem ja tem ciencia — assim o lote nunca esbarra na trava.
--
-- Caso de teste: FERIAS-055.
-- =========================================================

SET lock_timeout = '10s';

-- ── 1. Marca da ciencia na solicitacao ────────────────────────────────────
ALTER TABLE public.ferias_solicitacoes
    ADD COLUMN IF NOT EXISTS aviso_ciencia_em     TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS aviso_ciencia_origem TEXT,
    ADD COLUMN IF NOT EXISTS aviso_ciencia_por    UUID;

DO $ck$
BEGIN
    ALTER TABLE public.ferias_solicitacoes
        ADD CONSTRAINT ferias_solic_aviso_ciencia_origem_ck
        CHECK (aviso_ciencia_origem IS NULL
               OR aviso_ciencia_origem IN ('assinatura', 'manual', 'papel'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

COMMENT ON COLUMN public.ferias_solicitacoes.aviso_ciencia_em IS
    'Quando o colaborador deu ciencia do aviso de ferias. NULL = sem ciencia ainda.';
COMMENT ON COLUMN public.ferias_solicitacoes.aviso_ciencia_origem IS
    'Como a ciencia foi colhida: assinatura (digital), manual (registrada no sistema por gestao) ou papel.';

-- ── 2. A regra da ciencia, em um lugar so ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.ferias_aviso_tem_ciencia(p_solicitacao UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
    SELECT
        -- ciencia ja marcada na solicitacao (assinatura, manual ou papel)...
        EXISTS (SELECT 1 FROM public.ferias_solicitacoes s
                 WHERE s.id = p_solicitacao AND s.aviso_ciencia_em IS NOT NULL)
        -- ...ou um link de assinatura do AVISO ja assinado (rede de seguranca
        --    caso a marca ainda nao tenha sido gravada).
        OR EXISTS (SELECT 1 FROM public.ferias_assinatura_links l
                    WHERE l.ferias_solicitacao_id = p_solicitacao
                      AND coalesce(l.tipo_documento, 'aviso') = 'aviso'
                      AND l.status = 'assinado');
$fn$;

COMMENT ON FUNCTION public.ferias_aviso_tem_ciencia(UUID) IS
    'True quando o aviso de ferias da solicitacao ja tem ciencia (assinatura digital, registro manual ou papel).';

-- ── 3. Assinar o aviso marca a ciencia na solicitacao ─────────────────────
CREATE OR REPLACE FUNCTION public.ferias_link_marca_ciencia()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
    IF NEW.status = 'assinado'
       AND OLD.status IS DISTINCT FROM 'assinado'
       AND coalesce(NEW.tipo_documento, 'aviso') = 'aviso'
       AND NEW.ferias_solicitacao_id IS NOT NULL THEN
        UPDATE public.ferias_solicitacoes s
           SET aviso_ciencia_em     = COALESCE(s.aviso_ciencia_em, NEW.assinado_em, now()),
               aviso_ciencia_origem = COALESCE(s.aviso_ciencia_origem, 'assinatura')
         WHERE s.id = NEW.ferias_solicitacao_id
           AND s.aviso_ciencia_em IS NULL;
    END IF;
    RETURN NEW;
END $fn$;

DROP TRIGGER IF EXISTS trg_ferias_link_marca_ciencia ON public.ferias_assinatura_links;
CREATE TRIGGER trg_ferias_link_marca_ciencia
    AFTER UPDATE ON public.ferias_assinatura_links
    FOR EACH ROW EXECUTE FUNCTION public.ferias_link_marca_ciencia();

-- ── 4. A trava: iniciar o gozo exige ciencia ──────────────────────────────
CREATE OR REPLACE FUNCTION public.ferias_trava_em_gozo_sem_ciencia()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
    IF NEW.status = 'em_gozo'
       AND OLD.status IS DISTINCT FROM 'em_gozo'
       AND NOT public.ferias_aviso_tem_ciencia(NEW.id) THEN
        RAISE EXCEPTION 'Nao e possivel iniciar o gozo: o aviso de ferias ainda nao tem ciencia do colaborador (CLT art. 135). Colha a assinatura do aviso ou registre a ciencia antes.'
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $fn$;

DROP TRIGGER IF EXISTS trg_ferias_trava_em_gozo ON public.ferias_solicitacoes;
CREATE TRIGGER trg_ferias_trava_em_gozo
    BEFORE UPDATE ON public.ferias_solicitacoes
    FOR EACH ROW EXECUTE FUNCTION public.ferias_trava_em_gozo_sem_ciencia();

-- ── 5. A promocao automatica pela data respeita a trava ───────────────────
-- Sem isto, a rotina em lote promoveria aprovado->em_gozo mesmo sem ciencia
-- e a trava (item 4) abortaria o lote inteiro. Agora ela so promove quem tem
-- ciencia; quem nao tem fica em 'aprovado' ate a ciencia ser colhida.
CREATE OR REPLACE FUNCTION public.atualizar_status_ferias_automatico()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
  UPDATE public.ferias_solicitacoes s
  SET status = 'em_gozo'
  WHERE s.status = 'aprovado'
    AND s.data_inicio <= CURRENT_DATE
    AND s.data_fim >= CURRENT_DATE
    AND public.ferias_aviso_tem_ciencia(s.id);

  UPDATE public.ferias_solicitacoes
  SET status = 'concluido'
  WHERE status = 'em_gozo'
    AND data_fim < CURRENT_DATE;
END;
$fn$;
