-- ============================================================================
-- QA — Ferias: sondas usam o cercado (qa_sandbox_tenant_id) em vez de um tenant
-- REAL. As rotinas 023/055/060/061/080/081/082 pegavam FROM public.tenants
-- LIMIT 1 — no dev o 1o tenant e o sandbox (passava), mas na producao o modo-QA
-- bloqueia escrever fora do cercado. Trocar por qa_sandbox_tenant_id() e
-- correto nos dois: e cercado E satisfaz a FK. Comportamento do teste inalterado.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_023()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
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
                 || 'motor do RF-009: alerta em D-90/60/30, dobro ao vencer (art. 137) e acao no '
                 || 'Plano de Acao com 5W2H.';
        RETURN r;
    END IF;

    v_ten := public.qa_sandbox_tenant_id();
    IF v_ten IS NULL THEN
        r.situacao := 'nao_implementado';
        r.obtido := 'Sem tenants para montar a sonda; o motor existe mas nao foi exercitado.';
        RETURN r;
    END IF;

    BEGIN
        -- Periodo VENCIDO (concessivo ja passou): aquisitivo_fim ha ~13 meses.
        INSERT INTO public.ferias_periodos_aquisitivos
            (tenant_id, colaborador_cpf, colaborador_nome, data_admissao,
             aquisitivo_inicio, aquisitivo_fim, dias_direito, dias_saldo, status)
        VALUES (v_ten, '00000000191', 'QA Vencido', CURRENT_DATE - 800,
                CURRENT_DATE - 760, (CURRENT_DATE - INTERVAL '13 months')::date, 30, 30, 'ativo');

        -- Periodo a vencer em ~50 dias (faixa d60): concessivo = hoje + 50.
        -- concessivo = aquisitivo_fim + 12m  =>  aquisitivo_fim = hoje + 50 - 12m.
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
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_055()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
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

    v_ten := public.qa_sandbox_tenant_id();
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
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_060()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
    r public.qa_retorno; v_tem boolean; v_ten uuid; v_id uuid;
    v_com int; v_prazo date;
BEGIN
    r.passo_ordem := 1;
    r.passo_acao := 'AUDITORIA: existe fluxo de ferias coletivas com comunicados (15 dias)?';
    r.esperado := 'Programa por setor, ate 2 periodos >= 10 dias, comunicados MTE/sindicato/empregados';

    SELECT to_regclass('public.ferias_coletivas') IS NOT NULL INTO v_tem;
    IF NOT v_tem THEN
        r.situacao := 'falhou';
        r.obtido := 'ACHADO: sem fluxo de coletivas (arts. 139-141). Sem ele, nem os limites '
                 || 'nem as comunicacoes de 15 dias nem o art. 140 tem onde viver.';
        RETURN r;
    END IF;

    v_ten := public.qa_sandbox_tenant_id();
    IF v_ten IS NULL THEN
        r.situacao := 'nao_implementado'; r.obtido := 'Sem tenants para a sonda.'; RETURN r;
    END IF;

    BEGIN
        INSERT INTO public.ferias_coletivas (tenant_id, ano, departamento, p1_inicio, p1_fim)
        VALUES (v_ten, EXTRACT(YEAR FROM CURRENT_DATE)::int, 'QA-Producao',
                CURRENT_DATE + 40, CURRENT_DATE + 51)   -- 12 dias
        RETURNING id INTO v_id;

        v_com := public.ferias_coletiva_abrir_comunicados(v_id);
        SELECT count(*), min(prazo_limite) INTO v_com, v_prazo
          FROM public.ferias_coletivas_comunicados WHERE coletiva_id = v_id;

        RAISE EXCEPTION 'qa_rollback';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM <> 'qa_rollback' THEN
            r.situacao := 'erro'; r.obtido := 'A sonda quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
        END IF;
    END;

    IF v_com = 3 AND v_prazo = (CURRENT_DATE + 40 - 15) THEN
        r.situacao := 'passou';
        r.obtido := 'Coletiva de 12 dias aceita; 3 comunicados (MTE, sindicato, empregados) '
                 || 'abertos com prazo 15 dias antes do inicio.';
    ELSE
        r.situacao := 'falhou';
        r.obtido := format('Rito incompleto: comunicados=%s (esperado 3), prazo=%s (esperado %s).',
                           v_com, v_prazo, CURRENT_DATE + 40 - 15);
    END IF;
    RETURN r;
EXCEPTION WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_061()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
    r public.qa_retorno; v_ten uuid; v_ano int := EXTRACT(YEAR FROM CURRENT_DATE)::int;
    v_barrou_curto boolean := false; v_barrou_terceiro boolean := false;
BEGIN
    r.passo_ordem := 1;
    r.passo_acao := 'AUDITORIA: os limites das coletivas valem (min 10 dias; max 2/ano)?';
    r.esperado := 'Periodo de 8 dias barrado; segundo programa no mesmo ano/setor barrado';

    IF to_regclass('public.ferias_coletivas') IS NULL THEN
        r.situacao := 'falhou'; r.obtido := 'Sem tabela de coletivas (encadeado ao FERIAS-060).'; RETURN r;
    END IF;
    v_ten := public.qa_sandbox_tenant_id();
    IF v_ten IS NULL THEN r.situacao := 'nao_implementado'; r.obtido := 'Sem tenants.'; RETURN r; END IF;

    BEGIN
        -- 8 dias: deve barrar
        BEGIN
            INSERT INTO public.ferias_coletivas (tenant_id, ano, departamento, p1_inicio, p1_fim)
            VALUES (v_ten, v_ano, 'QA-Limites', CURRENT_DATE + 40, CURRENT_DATE + 47);
        EXCEPTION WHEN check_violation THEN v_barrou_curto := true;
        END;

        -- 1 valido + 2o programa no mesmo ano/setor: o 2o deve barrar
        INSERT INTO public.ferias_coletivas (tenant_id, ano, departamento, p1_inicio, p1_fim)
        VALUES (v_ten, v_ano, 'QA-Limites2', CURRENT_DATE + 40, CURRENT_DATE + 51);
        BEGIN
            INSERT INTO public.ferias_coletivas (tenant_id, ano, departamento, p1_inicio, p1_fim)
            VALUES (v_ten, v_ano, 'QA-Limites2', CURRENT_DATE + 100, CURRENT_DATE + 111);
        EXCEPTION WHEN check_violation THEN v_barrou_terceiro := true;
        END;

        RAISE EXCEPTION 'qa_rollback';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM <> 'qa_rollback' THEN
            r.situacao := 'erro'; r.obtido := 'A sonda quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
        END IF;
    END;

    IF v_barrou_curto AND v_barrou_terceiro THEN
        r.situacao := 'passou';
        r.obtido := 'Limites valem: periodo de 8 dias barrado (min 10) e segundo programa no '
                 || 'mesmo ano/setor barrado (max 2 periodos anuais).';
    ELSE
        r.situacao := 'falhou';
        r.obtido := format('Limites frouxos: barrou_8dias=%s, barrou_2o_programa=%s.',
                           v_barrou_curto, v_barrou_terceiro);
    END IF;
    RETURN r;
EXCEPTION WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_080()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
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
    v_ten := public.qa_sandbox_tenant_id();
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
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_081()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
    r public.qa_retorno; v_ten uuid; v_calc uuid; v_tid uuid;
    v_traducao text; v_status text; v_qtd_antes int; v_qtd_depois int;
BEGIN
    r.passo_ordem := 1;
    r.passo_acao := 'AUDITORIA: rejeicao e traduzida e o reenvio nao duplica o evento?';
    r.esperado := 'Codigo tecnico vira mensagem clara; regerar mantem UMA linha por evento';

    IF to_regproc('public.ferias_esocial_interpretar_retorno') IS NULL THEN
        r.situacao := 'falhou'; r.obtido := 'Sem interpretacao de retorno (RF-008).'; RETURN r; END IF;
    v_ten := public.qa_sandbox_tenant_id();
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
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_082()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
    r public.qa_retorno; v_ten uuid; v_calc uuid;
    v_s1200 jsonb; v_s1210 jsonb;
BEGIN
    r.passo_ordem := 1;
    r.passo_acao := 'AUDITORIA: as ferias refletem no S-1200 (rubricas) e S-1210 (detPgtoFer)?';
    r.esperado := 'S-1200 com ferias e terco na competencia; S-1210 com a data real do pagamento';

    IF to_regproc('public.ferias_esocial_gerar') IS NULL THEN
        r.situacao := 'falhou'; r.obtido := 'Sem geracao dos eventos de folha (RF-008).'; RETURN r; END IF;
    v_ten := public.qa_sandbox_tenant_id();
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
END $function$

;

