-- =========================================================
-- QA — FERIAS-055: sonda usa um tenant REAL
--
-- A versao anterior inseria a solicitacao-sonda com um tenant aleatorio
-- (gen_random_uuid()), que viola a FK ferias_solicitacoes_tenant_id_fkey
-- no schema real -> a sonda quebrava antes de exercitar a trava e o caso
-- devolvia 'erro'. (No stub local, tenant_id nao tinha FK, entao passava.)
--
-- Correcao: a sonda pega um tenant existente. Sem nenhum tenant (banco
-- vazio recem-criado), o caso responde 'nao_implementado' em vez de 'erro'.
-- Continua tudo desfeito ao final (subtransacao com rollback).
-- =========================================================

SET lock_timeout = '10s';

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

    -- Tenant real, para nao violar a FK da solicitacao-sonda.
    SELECT id INTO v_ten FROM public.tenants LIMIT 1;
    IF v_ten IS NULL THEN
        r.situacao := 'nao_implementado';
        r.obtido := 'Sem tenants na base para montar a sonda; a trava existe (funcao + trigger) '
                 || 'mas nao foi exercitada com dados.';
        RETURN r;
    END IF;

    -- Sonda funcional, sempre desfeita.
    BEGIN
        INSERT INTO public.ferias_solicitacoes
            (tenant_id, colaborador_nome, data_inicio, data_fim, dias_solicitados, status)
        VALUES (v_ten, 'QA Sonda FERIAS-055', CURRENT_DATE, CURRENT_DATE + 20, 20, 'aprovado')
        RETURNING id INTO v_id;

        -- 1) sem ciencia: em_gozo deve ser BARRADO
        BEGIN
            UPDATE public.ferias_solicitacoes SET status='em_gozo' WHERE id=v_id;
        EXCEPTION WHEN check_violation THEN
            v_barrou := true;
        END;

        -- 2) com ciencia registrada: em_gozo deve PASSAR
        UPDATE public.ferias_solicitacoes
           SET aviso_ciencia_em = now(), aviso_ciencia_origem = 'manual'
         WHERE id = v_id;
        BEGIN
            UPDATE public.ferias_solicitacoes SET status='em_gozo' WHERE id=v_id;
            v_liberou := true;
        EXCEPTION WHEN OTHERS THEN
            v_liberou := false;
        END;

        RAISE EXCEPTION 'qa_rollback';   -- desfaz tudo o que a sonda tocou
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
