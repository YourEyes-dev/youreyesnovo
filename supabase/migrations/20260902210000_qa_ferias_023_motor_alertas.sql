-- =========================================================
-- QA — FERIAS-023: motor de alertas de vencimento e risco de dobro (RF-009)
--
-- Confere que existe um MOTOR (nao so um painel passivo): a varredura gera
-- alerta em D-90/60/30, sinaliza o dobro ao vencer e leva o critico ao
-- Plano de Acao. Sonda funcional com rollback: nada e gravado.
-- =========================================================

SET lock_timeout = '10s';

-- Registra o caso (idempotente) na Documentacao de testes, se a tabela existir.
DO $doc$
DECLARE v_mod uuid;
BEGIN
    SELECT id INTO v_mod FROM public.qa_modulos WHERE lower(caminho) LIKE '%ferias%' LIMIT 1;
    IF v_mod IS NOT NULL THEN
        INSERT INTO public.qa_casos_teste (modulo_id, codigo, titulo, descricao, nivel)
        VALUES (v_mod, 'FERIAS-023',
                'Motor de alertas: D-90/60/30, dobro ao vencer e acao no Plano',
                'O sistema varre os periodos e gera alerta em D-90/60/30; ao vencer o concessivo sinaliza o dobro (art. 137), estima o custo e cria a acao no Plano de Acao. RF-009 do YE-DP-FERIAS-001.',
                'api')
        ON CONFLICT (codigo) DO NOTHING;
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Documentacao QA nao registrada (segue): %', SQLERRM;
END $doc$;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_023()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
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

    SELECT id INTO v_ten FROM public.tenants LIMIT 1;
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
END $fn$;
