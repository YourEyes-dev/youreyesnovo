-- PROVA (homologação): o adicional noturno chega ao ponto_diario pela consolidação real?
-- Monta um dia 100% noturno (22:00->23:30), consolida pelo pipeline vigente e compara
-- a coluna gravada com o que a função calcular_he_adicional_noturno_dia (órfã) daria.
-- Rollback por bloco (não suja o sandbox).
SET lock_timeout = '10s';
DO $$
DECLARE
  v_t    uuid := public.qa_sandbox_tenant_id();
  v_cpf  text := public.qa_cpf(7788);
  v_d    date := DATE '2026-09-15';     -- segunda-feira qualquer
  v_cid  uuid;
  v_adn_gravado int; v_he50 int; v_he100 int; v_status text; v_trab interval;
  v_orfa jsonb;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM public.qa_ponto_admissao('QA Noturno', 7788);
  SELECT a.id INTO v_cid FROM public.admissoes a WHERE a.tenant_id = v_t AND a.cpf = v_cpf LIMIT 1;

  -- dia 100% noturno: 22:00 entrada, 23:30 saída (90 min dentro de 22h-05h)
  PERFORM public.qa_ponto_marca(v_cpf, 'QA Noturno', v_d, TIME '22:00', 'entrada');
  PERFORM public.qa_ponto_marca(v_cpf, 'QA Noturno', v_d, TIME '23:30', 'saida');

  -- consolidação do pipeline vigente
  PERFORM public.consolidar_ponto_diario_manual(v_t, v_cpf, v_d);

  SELECT adicional_noturno_minutos, horas_extras_50_minutos, horas_extras_100_minutos, status, horas_trabalhadas
    INTO v_adn_gravado, v_he50, v_he100, v_status, v_trab
    FROM public.ponto_diario WHERE tenant_id = v_t AND colaborador_cpf = v_cpf AND data = v_d LIMIT 1;

  -- o que a função (órfã) calcularia pro mesmo dia
  BEGIN
    v_orfa := public.calcular_he_adicional_noturno_dia(v_cid, v_d);
  EXCEPTION WHEN OTHERS THEN v_orfa := jsonb_build_object('erro', SQLERRM);
  END;

  RAISE NOTICE 'NOTURNO: ponto_diario.adicional_noturno_minutos=% | he50=% he100=% | status=% trabalhadas=% || funcao_calcularia=%',
               COALESCE(v_adn_gravado::text,'NULL'), COALESCE(v_he50::text,'NULL'),
               COALESCE(v_he100::text,'NULL'), v_status, v_trab, v_orfa;
  RAISE EXCEPTION 'ROLLBACK_ME';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM <> 'ROLLBACK_ME' THEN RAISE NOTICE 'NOTURNO teste ERRO: %', SQLERRM; END IF;
END $$;
