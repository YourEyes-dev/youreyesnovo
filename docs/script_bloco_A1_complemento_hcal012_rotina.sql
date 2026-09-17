-- ============================================================================
-- A1 — COMPLEMENTO: entregar a rotina qa_caso_hcal_012 à produção.
--
-- O gatilho do A1 (hub_calendario_status) já está em produção e protegendo.
-- Só a ROTINA de QA que confere o HCAL-012 não tinha sido entregue (existe em
-- migration desde 08/2026, chegou ao dev/staging, não à produção — drift
-- forward-only). Por isso a bateria devolvia "function qa_caso_hcal_012 does
-- not exist".
--
-- Só cria a rotina (read-only, simula por descarte) e liga em qa_implementacoes.
-- Idempotente. Termina numa conferência única.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.qa_caso_hcal_012()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_t1 uuid := public.qa_sandbox_tenant_id();
        v_t2 uuid := public.qa_sandbox2_tenant_id(); v_cal_t2 uuid;
BEGIN
  PERFORM public.qa_modo_ligar();
  IF v_t2 IS NULL THEN r.situacao := 'erro'; r.obtido := '2o cercado nao existe.'; RETURN r; END IF;
  INSERT INTO public.hub_calendario_envios (tenant_id, titulo, tipo, categoria, dia_limite)
  VALUES (v_t2, '[QA-HCAL] Calendario do Cliente B', 'envio', 'folha', 15) RETURNING id INTO v_cal_t2;

  r.passo_ordem := 1;
  r.passo_acao := 'Inserir status no tenant 1 apontando calendário do tenant 2';
  r.esperado := 'Recusado — status e calendário do mesmo tenant';
  BEGIN
    INSERT INTO public.hub_calendario_status (tenant_id, calendario_id, competencia, status)
    VALUES (v_t1, v_cal_t2, to_char(CURRENT_DATE, 'YYYY-MM'), 'pendente');
    r.situacao := 'falhou';
    r.obtido := 'STATUS CRUZANDO TENANTS ACEITO: o andamento do cliente A ficou preso a item de calendário do cliente B. Mesma família de FER-004, MCHK-011 e PROC-011 — mesmo remédio, gatilho de coerência de tenant.';
  EXCEPTION WHEN OTHERS THEN
    r.situacao := 'passou'; r.obtido := 'Vínculo cruzando tenants recusado: ' || SQLERRM;
  END;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
VALUES ('HCAL-012', 'qa_caso_hcal_012', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- Conferência
SELECT 'HCAL-012' AS item,
       (SELECT situacao::text FROM public.qa_executar_descartavel('qa_caso_hcal_012')) AS res;
