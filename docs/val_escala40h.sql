-- PROVA (homologação): escala 5x2 / 40h (480 min/dia) calcula certo?
-- Dia A = 8h exatas (saldo 0); Dia B = 9h (saldo +60). Rollback por bloco.
SET lock_timeout = '10s';
DO $$
DECLARE
  v_t uuid := public.qa_sandbox_tenant_id();
  v_cpf text := public.qa_cpf(6611);
  v_cid uuid;
  v_dA date := DATE '2026-09-14';  -- segunda
  v_dB date := DATE '2026-09-15';  -- terca
  v_trabA interval; v_trabB interval; v_jorA int; v_jorB int;
  v_stA text; v_stB text;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM public.qa_ponto_admissao('QA 40h', 6611);
  SELECT a.id INTO v_cid FROM public.admissoes a WHERE a.tenant_id=v_t AND a.cpf=v_cpf LIMIT 1;
  -- escala 5x2: 480 min/dia (8h), jornada semanal 2400 (40h), atribuída ao cpf
  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA 40h', 480, 5, v_dA - 30, v_dA + 30);

  -- Dia A: 08:00-12:00 + 13:00-17:00 = 8h exatas
  PERFORM public.qa_ponto_marca(v_cpf,'QA 40h', v_dA, TIME '08:00','entrada');
  PERFORM public.qa_ponto_marca(v_cpf,'QA 40h', v_dA, TIME '12:00','saida');
  PERFORM public.qa_ponto_marca(v_cpf,'QA 40h', v_dA, TIME '13:00','entrada');
  PERFORM public.qa_ponto_marca(v_cpf,'QA 40h', v_dA, TIME '17:00','saida');
  PERFORM public.consolidar_ponto_diario_manual(v_t, v_cpf, v_dA);

  -- Dia B: 08:00-12:00 + 13:00-18:00 = 9h (1h extra)
  PERFORM public.qa_ponto_marca(v_cpf,'QA 40h', v_dB, TIME '08:00','entrada');
  PERFORM public.qa_ponto_marca(v_cpf,'QA 40h', v_dB, TIME '12:00','saida');
  PERFORM public.qa_ponto_marca(v_cpf,'QA 40h', v_dB, TIME '13:00','entrada');
  PERFORM public.qa_ponto_marca(v_cpf,'QA 40h', v_dB, TIME '18:00','saida');
  PERFORM public.consolidar_ponto_diario_manual(v_t, v_cpf, v_dB);

  SELECT horas_trabalhadas, status INTO v_trabA, v_stA FROM public.ponto_diario WHERE tenant_id=v_t AND colaborador_cpf=v_cpf AND data=v_dA;
  SELECT horas_trabalhadas, status INTO v_trabB, v_stB FROM public.ponto_diario WHERE tenant_id=v_t AND colaborador_cpf=v_cpf AND data=v_dB;
  BEGIN v_jorA := public.ponto_jornada_do_dia(v_t, v_cpf, v_cid, v_dA); EXCEPTION WHEN OTHERS THEN v_jorA := -1; END;
  BEGIN v_jorB := public.ponto_jornada_do_dia(v_t, v_cpf, v_cid, v_dB); EXCEPTION WHEN OTHERS THEN v_jorB := -1; END;

  RAISE NOTICE 'ESCALA40h DiaA(8h): trabalhadas=% esperado_min=% status=% (saldo esperado 0)', v_trabA, v_jorA, v_stA;
  RAISE NOTICE 'ESCALA40h DiaB(9h): trabalhadas=% esperado_min=% status=% (saldo esperado +60)', v_trabB, v_jorB, v_stB;
  RAISE EXCEPTION 'ROLLBACK_ME';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM <> 'ROLLBACK_ME' THEN RAISE NOTICE 'ESCALA40h ERRO: %', SQLERRM; END IF;
END $$;
