-- =========================================================
-- QA — eSocial de ferias: FERIAS-080 (S-2230 motivo 15), FERIAS-081
-- (rejeicao traduzida + reenvio nao duplica), FERIAS-082 (S-1200/S-1210).
-- Sondas com rollback: nada e gravado.
-- =========================================================

SET lock_timeout = '10s';

-- Insere um calculo de ferias-sonda e devolve o id (para as sondas abaixo).
CREATE OR REPLACE FUNCTION public.qa_ferias_sonda_calculo(p_tenant UUID)
RETURNS UUID
LANGUAGE plpgsql AS $fn$
DECLARE v_id UUID;
BEGIN
    INSERT INTO public.folha_ferias_calculo
        (tenant_id, colaborador_nome, colaborador_cpf,
         periodo_aquisitivo_inicio, periodo_aquisitivo_fim,
         data_inicio_gozo, data_fim_gozo, dias_gozo,
         valor_ferias, valor_terco, total_liquido, data_pagamento, status)
    VALUES
        (p_tenant, 'QA eSocial', '90000000191',
         CURRENT_DATE - 400, CURRENT_DATE - 35,
         CURRENT_DATE + 40, CURRENT_DATE + 69, 30,
         3000, 1000, 3600, CURRENT_DATE + 37, 'calculado')
    RETURNING id INTO v_id;
    RETURN v_id;
END $fn$;

-- FERIAS-080 — concessao gera S-2230 com motivo 15 e datas exatas
CREATE OR REPLACE FUNCTION public.qa_caso_ferias_080()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
    r public.qa_retorno; v_ten uuid; v_calc uuid; v_ev RECORD;
BEGIN
    r.passo_ordem := 1;
    r.passo_acao := 'AUDITORIA: a concessao gera o S-2230 (motivo 15) com datas exatas?';
    r.esperado := 'Um S-2230 pendente, codMotAfast=15, dtIniAfast/dtTermAfast = datas do gozo';

    IF to_regproc('public.ferias_esocial_gerar') IS NULL THEN
        r.situacao := 'falhou';
        r.obtido := 'ACHADO: a concessao nao gera evento do eSocial. Sem o S-2230 (motivo 15), '
                 || 'o gozo nao existe oficialmente para o governo (RF-008).';
        RETURN r;
    END IF;
    SELECT id INTO v_ten FROM public.tenants LIMIT 1;
    IF v_ten IS NULL THEN r.situacao := 'nao_implementado'; r.obtido := 'Sem tenants.'; RETURN r; END IF;

    BEGIN
        v_calc := public.qa_ferias_sonda_calculo(v_ten);
        PERFORM public.ferias_esocial_gerar(v_calc);
        SELECT tipo_evento, status, motivo_afastamento,
               (xml_enviado::jsonb ->> 'dtIniAfast') AS ini,
               (xml_enviado::jsonb ->> 'dtTermAfast') AS fim
          INTO v_ev
          FROM public.esocial_transmissoes
         WHERE ferias_calculo_id = v_calc AND tipo_evento = 'S-2230';
        RAISE EXCEPTION 'qa_rollback';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM <> 'qa_rollback' THEN
            r.situacao := 'erro'; r.obtido := 'A sonda quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
        END IF;
    END;

    IF v_ev.status = 'pendente' AND v_ev.motivo_afastamento = '15'
       AND v_ev.ini = (CURRENT_DATE + 40)::text AND v_ev.fim = (CURRENT_DATE + 69)::text THEN
        r.situacao := 'passou';
        r.obtido := 'S-2230 gerado: motivo 15, datas exatas do gozo, status pendente para envio.';
    ELSE
        r.situacao := 'falhou';
        r.obtido := format('S-2230 incorreto: status=%s motivo=%s ini=%s fim=%s.',
                           v_ev.status, v_ev.motivo_afastamento, v_ev.ini, v_ev.fim);
    END IF;
    RETURN r;
EXCEPTION WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- FERIAS-081 — rejeicao traduzida e reenvio nao duplica
CREATE OR REPLACE FUNCTION public.qa_caso_ferias_081()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
    r public.qa_retorno; v_ten uuid; v_calc uuid; v_tid uuid;
    v_traducao text; v_status text; v_qtd_antes int; v_qtd_depois int;
BEGIN
    r.passo_ordem := 1;
    r.passo_acao := 'AUDITORIA: rejeicao e traduzida e o reenvio nao duplica o evento?';
    r.esperado := 'Codigo tecnico vira mensagem clara; regerar mantem UMA linha por evento';

    IF to_regproc('public.ferias_esocial_interpretar_retorno') IS NULL THEN
        r.situacao := 'falhou'; r.obtido := 'Sem interpretacao de retorno (RF-008).'; RETURN r; END IF;
    SELECT id INTO v_ten FROM public.tenants LIMIT 1;
    IF v_ten IS NULL THEN r.situacao := 'nao_implementado'; r.obtido := 'Sem tenants.'; RETURN r; END IF;

    BEGIN
        v_calc := public.qa_ferias_sonda_calculo(v_ten);
        PERFORM public.ferias_esocial_gerar(v_calc);
        SELECT count(*) INTO v_qtd_antes FROM public.esocial_transmissoes WHERE ferias_calculo_id = v_calc;

        SELECT id INTO v_tid FROM public.esocial_transmissoes
         WHERE ferias_calculo_id = v_calc AND tipo_evento = 'S-2230';
        v_traducao := public.ferias_esocial_interpretar_retorno(v_tid, '301', 'erro cru');
        SELECT status INTO v_status FROM public.esocial_transmissoes WHERE id = v_tid;

        -- reenvio: regenera; nao pode criar linha nova
        PERFORM public.ferias_esocial_gerar(v_calc);
        SELECT count(*) INTO v_qtd_depois FROM public.esocial_transmissoes WHERE ferias_calculo_id = v_calc;

        RAISE EXCEPTION 'qa_rollback';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM <> 'qa_rollback' THEN
            r.situacao := 'erro'; r.obtido := 'A sonda quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
        END IF;
    END;

    IF v_status = 'rejeitado' AND v_traducao NOT LIKE '%erro cru%'
       AND v_qtd_antes = 3 AND v_qtd_depois = 3 THEN
        r.situacao := 'passou';
        r.obtido := 'Rejeicao traduzida (schema/leiaute) e reenvio manteve 3 eventos — sem duplicar.';
    ELSE
        r.situacao := 'falhou';
        r.obtido := format('status=%s traducao=%s antes=%s depois=%s.',
                           v_status, v_traducao, v_qtd_antes, v_qtd_depois);
    END IF;
    RETURN r;
EXCEPTION WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- FERIAS-082 — S-1200 e S-1210 com as rubricas e a data de pagamento
CREATE OR REPLACE FUNCTION public.qa_caso_ferias_082()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
    r public.qa_retorno; v_ten uuid; v_calc uuid;
    v_s1200 jsonb; v_s1210 jsonb;
BEGIN
    r.passo_ordem := 1;
    r.passo_acao := 'AUDITORIA: as ferias refletem no S-1200 (rubricas) e S-1210 (detPgtoFer)?';
    r.esperado := 'S-1200 com ferias e terco na competencia; S-1210 com a data real do pagamento';

    IF to_regproc('public.ferias_esocial_gerar') IS NULL THEN
        r.situacao := 'falhou'; r.obtido := 'Sem geracao dos eventos de folha (RF-008).'; RETURN r; END IF;
    SELECT id INTO v_ten FROM public.tenants LIMIT 1;
    IF v_ten IS NULL THEN r.situacao := 'nao_implementado'; r.obtido := 'Sem tenants.'; RETURN r; END IF;

    BEGIN
        v_calc := public.qa_ferias_sonda_calculo(v_ten);
        PERFORM public.ferias_esocial_gerar(v_calc);
        SELECT xml_enviado::jsonb INTO v_s1200 FROM public.esocial_transmissoes
         WHERE ferias_calculo_id = v_calc AND tipo_evento = 'S-1200';
        SELECT xml_enviado::jsonb INTO v_s1210 FROM public.esocial_transmissoes
         WHERE ferias_calculo_id = v_calc AND tipo_evento = 'S-1210';
        RAISE EXCEPTION 'qa_rollback';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM <> 'qa_rollback' THEN
            r.situacao := 'erro'; r.obtido := 'A sonda quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
        END IF;
    END;

    IF v_s1200 IS NOT NULL AND v_s1210 IS NOT NULL
       AND jsonb_array_length(v_s1200->'itensRemun') = 2
       AND (v_s1210->'detPgtoFer'->>'dtPgto') = (CURRENT_DATE + 37)::text THEN
        r.situacao := 'passou';
        r.obtido := 'S-1200 com ferias+terco e S-1210 com a data real do pagamento (prova o D-2).';
    ELSE
        r.situacao := 'falhou';
        r.obtido := format('S-1200=%s S-1210 dtPgto=%s.',
                           v_s1200 IS NOT NULL, v_s1210->'detPgtoFer'->>'dtPgto');
    END IF;
    RETURN r;
EXCEPTION WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;
