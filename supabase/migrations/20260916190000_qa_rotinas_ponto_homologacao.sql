-- ============================================================================
-- Motor de QA — rotinas do módulo Ponto (PONTO-HOM-C1, C2, F2).
--
-- Três casos de homologação que estavam sem rotina (nível api). Convertidos em
-- verificação automatizada, em transação descartável:
--   C1 — o agendamento das vigilâncias existe (cron.job) e a rotina roda as 8
--        vigilâncias sem erro.
--   C2 — rodar as vigilâncias duas vezes não duplica o alerta de certificado.
--   F2 — visualizar selfie e exportar AFD deixam rastro na trilha de acesso.
-- ============================================================================

-- ── PONTO-HOM-C1: agendamento existe e as 8 vigilâncias rodam sem erro ───────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_hom_c1()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_active boolean; v_sched text; v_total int; v_err int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir o agendamento ponto-vigilancias-diarias e rodar as 8 vigilâncias';
  r.esperado    := 'Job ativo às 03:37 UTC; 8 linhas, todas com tenants_com_erro = 0';

  SELECT active, schedule INTO v_active, v_sched FROM cron.job WHERE jobname = 'ponto-vigilancias-diarias';
  SELECT count(*)::int, count(*) FILTER (WHERE tenants_com_erro > 0)::int
    INTO v_total, v_err FROM public.ponto_vigilancias_diarias();

  IF v_active IS NOT TRUE OR v_sched IS DISTINCT FROM '37 3 * * *' THEN
    r.situacao := 'falhou';
    r.obtido := format('Agendamento das vigilâncias ausente/errado (ativo=%s, schedule=%s).', COALESCE(v_active::text,'nulo'), COALESCE(v_sched,'nulo'));
  ELSIF v_total <> 8 THEN
    r.situacao := 'falhou';
    r.obtido := format('A rotina devolveu %s vigilância(s), esperado 8.', v_total);
  ELSIF v_err > 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('%s vigilância(s) acusaram tenant com erro.', v_err);
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Job ativo às 03:37 UTC e as 8 vigilâncias rodaram sem erro.';
  END IF;
  r.detalhe := jsonb_build_object('job_ativo', v_active, 'schedule', v_sched, 'total', v_total, 'com_erro', v_err);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-HOM-C2: rodar duas vezes não duplica o alerta de certificado ──────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_hom_c2()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_t1 uuid := public.qa_sandbox_tenant_id(); v_venc date := CURRENT_DATE + 10;
        v_tag text := left(gen_random_uuid()::text, 8); n0 int; n1 int; n2 int;
BEGIN
  IF v_t1 IS NULL THEN r.situacao := 'nao_implementado'; r.obtido := 'Cercado de teste ausente.'; RETURN r; END IF;

  r.passo_ordem := 1;
  r.passo_acao  := 'Certificado vencendo em 10 dias; rodar as vigilâncias duas vezes';
  r.esperado    := '1º disparo cria o alerta; 2º não duplica';

  INSERT INTO public.ponto_certificados_digitais (tenant_id, titular_nome, numero_serie, valido_ate, alerta_antecedencia_dias, ativo)
  VALUES (v_t1, '[QA] Titular ' || v_tag, 'QA-SERIE-' || v_tag, v_venc, 30, true);

  SELECT count(*)::int INTO n0 FROM public.ponto_alertas
   WHERE tenant_id = v_t1 AND tipo = 'certificado_digital_vencimento' AND data_referencia = v_venc;

  PERFORM public.ponto_vigilancias_diarias();
  SELECT count(*)::int INTO n1 FROM public.ponto_alertas
   WHERE tenant_id = v_t1 AND tipo = 'certificado_digital_vencimento' AND data_referencia = v_venc;

  PERFORM public.ponto_vigilancias_diarias();
  SELECT count(*)::int INTO n2 FROM public.ponto_alertas
   WHERE tenant_id = v_t1 AND tipo = 'certificado_digital_vencimento' AND data_referencia = v_venc;

  IF n1 = 1 AND n2 = 1 THEN
    r.situacao := 'passou';
    r.obtido := 'O 1º disparo criou o alerta do certificado; o 2º não duplicou (segue um único aviso).';
  ELSIF n1 <> 1 THEN
    r.situacao := 'falhou';
    r.obtido := format('O 1º disparo deveria criar 1 alerta do certificado, criou %s (antes havia %s).', n1, n0);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('O 2º disparo DUPLICOU o alerta: passou de %s para %s.', n1, n2);
  END IF;
  r.detalhe := jsonb_build_object('antes', n0, 'apos_1', n1, 'apos_2', n2, 'vencimento', v_venc);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-HOM-F2: selfie e exportação de AFD deixam rastro na trilha ────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_hom_f2()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_claims text; v_t1 uuid := public.qa_sandbox_tenant_id();
        v_uid uuid := gen_random_uuid(); n_selfie int; n_afd int;
BEGIN
  v_claims := current_setting('request.jwt.claims', true);
  IF v_t1 IS NULL THEN r.situacao := 'nao_implementado'; r.obtido := 'Cercado de teste ausente.'; RETURN r; END IF;

  r.passo_ordem := 1;
  r.passo_acao  := 'Registrar visualização de selfie e exportação de AFD pelos loggers da trilha';
  r.esperado    := 'Uma linha visualizou_selfie e uma exportou_afd (com competência e empresa no escopo)';

  PERFORM public.qa_mky_claims(v_uid);
  -- Mesmos loggers que a tela da selfie e o export do AFD invocam (Portaria 671 / LGPD).
  PERFORM public.ponto_log_acesso_sensivel(v_t1, 'visualizou_selfie', 'selfie', gen_random_uuid(), NULL, 'QA: visualização de selfie', NULL);
  PERFORM public.ponto_log_exportacao(v_t1, 'exportou_afd',
            jsonb_build_object('competencia', '2026-09', 'empresa', 'QA Empresa Staging'), NULL, 'QA: exportação de AFD', NULL);
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);

  SELECT count(*)::int INTO n_selfie FROM public.ponto_acesso_sensivel_log
   WHERE usuario_id = v_uid AND acao = 'visualizou_selfie';
  SELECT count(*)::int INTO n_afd FROM public.ponto_acesso_sensivel_log
   WHERE usuario_id = v_uid AND acao = 'exportou_afd'
     AND escopo ? 'competencia' AND escopo ? 'empresa';

  IF n_selfie = 1 AND n_afd = 1 THEN
    r.situacao := 'passou';
    r.obtido := 'A visualização de selfie e a exportação de AFD ficaram registradas na trilha (com competência e empresa no escopo).';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Trilha incompleta: visualizou_selfie=%s (esperado 1), exportou_afd com escopo=%s (esperado 1).', n_selfie, n_afd);
  END IF;
  r.detalhe := jsonb_build_object('selfie', n_selfie, 'afd', n_afd);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── Ligar caso ↔ rotina ─────────────────────────────────────────────────────
INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
  ('PONTO-HOM-C1', 'qa_caso_ponto_hom_c1', true),
  ('PONTO-HOM-C2', 'qa_caso_ponto_hom_c2', true),
  ('PONTO-HOM-F2', 'qa_caso_ponto_hom_f2', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
