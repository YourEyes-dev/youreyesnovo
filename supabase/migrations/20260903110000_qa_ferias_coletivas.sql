-- =========================================================
-- QA — Ferias coletivas: FERIAS-060 (rito), FERIAS-061 (limites),
-- FERIAS-062 (art. 140). Sondas com rollback: nada e gravado.
-- =========================================================

SET lock_timeout = '10s';

-- FERIAS-060 — rito completo: ate 2 periodos, comunicados com 15 dias
CREATE OR REPLACE FUNCTION public.qa_caso_ferias_060()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
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

    SELECT id INTO v_ten FROM public.tenants LIMIT 1;
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
END $fn$;

-- FERIAS-061 — limites: < 10 dias barra; 2o programa no ano/setor barra
CREATE OR REPLACE FUNCTION public.qa_caso_ferias_061()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
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
    SELECT id INTO v_ten FROM public.tenants LIMIT 1;
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
END $fn$;

-- FERIAS-062 — art. 140: novato entra proporcional
CREATE OR REPLACE FUNCTION public.qa_caso_ferias_062()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
    r public.qa_retorno; v_ten uuid; v_id uuid;
    v_novato_140 boolean; v_novato_dias int; v_veterano_140 boolean;
BEGIN
    r.passo_ordem := 1;
    r.passo_acao := 'AUDITORIA: quem tem menos de 12 meses entra proporcional (art. 140)?';
    r.esperado := 'Novato: art_140=true e dias proporcionais ao tempo de casa; veterano: art_140=false';

    IF to_regproc('public.ferias_coletiva_afetados') IS NULL THEN
        r.situacao := 'falhou'; r.obtido := 'Sem tratamento do art. 140 (encadeado ao FERIAS-060).'; RETURN r;
    END IF;
    SELECT id INTO v_ten FROM public.tenants LIMIT 1;
    IF v_ten IS NULL THEN r.situacao := 'nao_implementado'; r.obtido := 'Sem tenants.'; RETURN r; END IF;

    BEGIN
        INSERT INTO public.ferias_coletivas (tenant_id, ano, departamento, p1_inicio, p1_fim)
        VALUES (v_ten, EXTRACT(YEAR FROM CURRENT_DATE)::int, 'QA-140',
                CURRENT_DATE + 40, CURRENT_DATE + 51)
        RETURNING id INTO v_id;

        -- novato: admitido ha 6 meses -> art_140, ~15 dias proporcionais
        INSERT INTO public.admissoes (tenant_id, nome, nome_completo, cpf, departamento, status, data_admissao, salario)
        VALUES (v_ten, 'Novato', 'QA Novato', '00000000140', 'QA-140', 'concluido',
                (CURRENT_DATE + 40 - INTERVAL '6 months')::date, 2000);
        -- veterano: admitido ha 3 anos -> nao art_140
        INSERT INTO public.admissoes (tenant_id, nome, nome_completo, cpf, departamento, status, data_admissao, salario)
        VALUES (v_ten, 'Veterano', 'QA Veterano', '00000000241', 'QA-140', 'concluido',
                (CURRENT_DATE - INTERVAL '3 years')::date, 2000);

        SELECT art_140, dias_proporcionais INTO v_novato_140, v_novato_dias
          FROM public.ferias_coletiva_afetados(v_id) WHERE colaborador_nome = 'QA Novato';
        SELECT art_140 INTO v_veterano_140
          FROM public.ferias_coletiva_afetados(v_id) WHERE colaborador_nome = 'QA Veterano';

        RAISE EXCEPTION 'qa_rollback';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM <> 'qa_rollback' THEN
            r.situacao := 'erro'; r.obtido := 'A sonda quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
        END IF;
    END;

    IF v_novato_140 AND NOT coalesce(v_veterano_140, true) AND v_novato_dias BETWEEN 12 AND 18 THEN
        r.situacao := 'passou';
        r.obtido := format('Art. 140 OK: novato de 6 meses entra proporcional (%s dias) e o '
                 || 'veterano nao e afetado.', v_novato_dias);
    ELSE
        r.situacao := 'falhou';
        r.obtido := format('Art. 140 incorreto: novato_140=%s dias=%s veterano_140=%s.',
                           v_novato_140, v_novato_dias, v_veterano_140);
    END IF;
    RETURN r;
EXCEPTION WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;
