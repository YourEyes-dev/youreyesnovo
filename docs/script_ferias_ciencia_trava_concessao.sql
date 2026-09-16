-- ============================================================================
-- ENTREGA — Ferias: a ciencia do aviso trava o inicio do gozo (art. 135)
--
-- Colar INTEIRO no SQL Editor do projeto de PRODUCAO e executar uma vez.
--
-- POR QUE
--   O aviso de ferias podia ser emitido sem coleta de ciencia, e nada
--   impedia o gozo comecar assim. O documento YE-DP-FERIAS-001 (CA-005,
--   cenario "Aviso sem ciencia -> nao conclui a concessao") exige que a
--   concessao so se conclua com o aviso cientificado — a prova pedida em
--   fiscalizacao (art. 135 da CLT, comunicacao MEDIANTE RECIBO).
--
-- O QUE MUDA
--   1) ferias_solicitacoes ganha a marca da ciencia (aviso_ciencia_em/
--      origem/por), com valvula para ciencia colhida em PAPEL;
--   2) ferias_aviso_tem_ciencia(solicitacao) — a regra num lugar so (vale
--      ciencia por assinatura digital, registro manual ou papel);
--   3) assinar o AVISO marca a ciencia na solicitacao (trigger de banco);
--   4) trava: a transicao para 'em_gozo' e recusada sem ciencia;
--   5) a rotina que promove aprovado->em_gozo pela data passa a promover SO
--      quem ja tem ciencia — assim o lote nunca esbarra na trava;
--   6) a rotina de QA FERIAS-055 passa a exercitar a trava.
--
-- SEGURANCA DO DADO
--   So CRIA/SUBSTITUI objetos (colunas com IF NOT EXISTS, funcoes com
--   CREATE OR REPLACE, triggers recriadas). Nao altera nem apaga nenhuma
--   LINHA existente, entao nao ha copia de seguranca a fazer. Idempotente:
--   rodar duas vezes nao quebra nem duplica.
--
-- EFEITO NA OPERACAO: apos este script, iniciar o gozo (status 'em_gozo')
--   exige ciencia do aviso. Solicitacoes ja em 'em_gozo' ou 'concluido' NAO
--   sao tocadas (a trava so age na TRANSICAO para em_gozo). Para quem colhe
--   a ciencia em papel, ha o registro manual (aviso_ciencia_origem='papel').
--
-- PROVADO em replica local com schema fiel (tenants + FK + trigger de
--   historico): sem ciencia o em_gozo e barrado; assinar o aviso marca a
--   ciencia; com ciencia o em_gozo passa; a promocao automatica so promove
--   quem tem ciencia. A rotina QA FERIAS-055 responde 'passou'.
--
-- A TELA (botoes "Iniciar Gozo", "Aviso p/ Assinar", "Registrar ciencia")
--   e o arquivamento automatico em Documentos so mudam apos Publicar no Lovable.
-- ============================================================================

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

-- ── 2. A regra da ciencia, em um lugar so ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.ferias_aviso_tem_ciencia(p_solicitacao UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
    SELECT
        EXISTS (SELECT 1 FROM public.ferias_solicitacoes s
                 WHERE s.id = p_solicitacao AND s.aviso_ciencia_em IS NOT NULL)
        OR EXISTS (SELECT 1 FROM public.ferias_assinatura_links l
                    WHERE l.ferias_solicitacao_id = p_solicitacao
                      AND coalesce(l.tipo_documento, 'aviso') = 'aviso'
                      AND l.status = 'assinado');
$fn$;

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

-- ── 6. QA — FERIAS-055 exercita a trava (sonda com rollback) ──────────────
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
                 || 'com o aviso pendente. O art. 135 exige comunicacao MEDIANTE RECIBO.';
        RETURN r;
    END IF;

    SELECT id INTO v_ten FROM public.tenants LIMIT 1;
    IF v_ten IS NULL THEN
        r.situacao := 'nao_implementado';
        r.obtido := 'Sem tenants na base para montar a sonda; a trava existe mas nao foi '
                 || 'exercitada com dados.';
        RETURN r;
    END IF;

    BEGIN
        INSERT INTO public.ferias_solicitacoes
            (tenant_id, colaborador_nome, data_inicio, data_fim, dias_solicitados, status)
        VALUES (v_ten, 'QA Sonda FERIAS-055', CURRENT_DATE, CURRENT_DATE + 20, 20, 'aprovado')
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
                 || 'registrada, passa.';
    ELSIF NOT v_barrou THEN
        r.situacao := 'falhou';
        r.obtido := 'A trava existe mas NAO barrou o em_gozo sem ciencia.';
    ELSE
        r.situacao := 'falhou';
        r.obtido := 'A trava barrou ate com a ciencia registrada — bloqueando concessao legitima.';
    END IF;
    RETURN r;
EXCEPTION WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── 7. Conferencia final (o editor mostra so o ultimo resultado) ──────────
SELECT
    (SELECT CASE WHEN to_regprocedure('public.ferias_aviso_tem_ciencia(uuid)') IS NOT NULL
        THEN 'sim' ELSE 'NAO — verificar' END)                              AS regra_ciencia,
    (SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_trigger
                               WHERE tgname='trg_ferias_trava_em_gozo' AND NOT tgisinternal)
        THEN 'sim' ELSE 'NAO — verificar' END)                             AS trava_instalada,
    (SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_trigger
                               WHERE tgname='trg_ferias_link_marca_ciencia' AND NOT tgisinternal)
        THEN 'sim' ELSE 'NAO — verificar' END)                             AS assinatura_marca_ciencia,
    (SELECT situacao FROM public.qa_caso_ferias_055())                      AS qa_ferias_055,
    (SELECT obtido   FROM public.qa_caso_ferias_055())                      AS qa_ferias_055_detalhe;
