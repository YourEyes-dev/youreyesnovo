-- Situação "recusado" (parte 2): converte as recusas já gravadas como
-- "extraviado" e ajusta as rotinas de QA que gravam recusa (EPI-055 e EPI-057).
-- Recusa antiga = sem assinatura e com a marca "RECUSADO:" nas observações
-- (o assistente sempre a grava). Extravio de verdade não é tocado.
UPDATE public.epi_entregas
   SET status = 'recusado'
 WHERE status = 'extraviado' AND signed_at IS NULL AND observacoes LIKE 'RECUSADO:%';

CREATE OR REPLACE FUNCTION public.qa_caso_epi_055()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_tipo uuid; v_epi uuid; v_erro text; v_global int; v_entregas int; v_ok jsonb; v_recusa jsonb;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Tentar entrega assinada sem a imagem da assinatura; depois com ela; depois uma recusa';
  r.esperado := 'Sem assinatura: recusada e nada gravado. Com assinatura: aceita. Recusa: aceita';
  INSERT INTO public.epi_tipos (tenant_id, nome, ca_numero, ca_validade, is_active)
  VALUES (v_t, 'QA — Luva assinatura', '99055', CURRENT_DATE + 365, true) RETURNING id INTO v_tipo;
  INSERT INTO public.epis (tenant_id, tipo_id, codigo, quantidade_estoque, data_validade)
  VALUES (v_t, v_tipo, 'QA-EPI-055', 10, CURRENT_DATE + 365) RETURNING id INTO v_epi;

  BEGIN
    PERFORM public.epi_registrar_entrega(jsonb_build_object(
      'tenant_id', v_t, 'epi_id', v_epi, 'colaborador_nome', 'QA Colaborador 055 A',
      'colaborador_cpf', public.qa_cpf(55), 'quantidade', 1, 'data_entrega', CURRENT_DATE,
      'status', 'ativa', 'signed_at', now()));
  EXCEPTION WHEN OTHERS THEN v_erro := SQLERRM;
  END;
  v_global := (SELECT quantidade_estoque FROM public.epis WHERE id = v_epi);
  v_entregas := (SELECT count(*) FROM public.epi_entregas WHERE epi_id = v_epi);

  v_ok := public.epi_registrar_entrega(jsonb_build_object(
    'tenant_id', v_t, 'epi_id', v_epi, 'colaborador_nome', 'QA Colaborador 055 B',
    'colaborador_cpf', public.qa_cpf(55), 'quantidade', 1, 'data_entrega', CURRENT_DATE,
    'status', 'ativa', 'assinatura_url', 'qa/assinatura-055.png', 'signed_at', now()));
  v_recusa := public.epi_registrar_entrega(jsonb_build_object(
    'tenant_id', v_t, 'epi_id', v_epi, 'colaborador_nome', 'QA Colaborador 055 C',
    'colaborador_cpf', public.qa_cpf(55), 'quantidade', 1, 'data_entrega', CURRENT_DATE,
    'status', 'recusado', 'observacoes', 'RECUSADO: QA'));

  IF v_erro IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: uma entrega marcada como assinada, mas SEM a imagem da assinatura, foi aceita. Isso grava uma ficha assinada que não prova nada.';
  ELSIF v_global <> 10 OR v_entregas <> 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('A recusa deixou rastro: saldo %s (esperado 10) e %s entrega(s) (esperado 0).', v_global, v_entregas);
  ELSIF v_ok->>'id' IS NULL OR v_recusa->>'id' IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A entrega com assinatura ou a recusa deixou de ser aceita.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Assinada sem a assinatura foi recusada (%s) sem gravar nada; com assinatura e a recusa seguem aceitas.', v_erro);
  END IF;
  r.detalhe := jsonb_build_object('erro_sem_assinatura', v_erro, 'saldo_apos_recusa', v_global);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_epi_057()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_tipo uuid; v_epi uuid; v_res1 int; v_est1 int; v_res2 int; v_erro2 text;
        v_ent uuid; v_res3 int; v_est3 int; v_res4 int; v_est4 int; v_recusas int;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Registrar recusas (dentro e acima do saldo) e uma entrega aguardando assinatura';
  r.esperado := 'Recusa não reserva; a reserva da entrega que aguarda assinatura continua funcionando';
  INSERT INTO public.epi_tipos (tenant_id, nome, ca_numero, ca_validade, is_active)
  VALUES (v_t, 'QA — Luva recusa', '99057', CURRENT_DATE + 365, true) RETURNING id INTO v_tipo;
  INSERT INTO public.epis (tenant_id, tipo_id, codigo, quantidade_estoque, data_validade)
  VALUES (v_t, v_tipo, 'QA-EPI-057', 10, CURRENT_DATE + 365) RETURNING id INTO v_epi;

  PERFORM public.epi_registrar_entrega(jsonb_build_object(
    'tenant_id', v_t, 'epi_id', v_epi, 'colaborador_nome', 'QA Colaborador 057 A',
    'colaborador_cpf', public.qa_cpf(57), 'quantidade', 3, 'data_entrega', CURRENT_DATE,
    'status', 'recusado', 'observacoes', 'RECUSADO: QA'));
  v_res1 := (SELECT COALESCE(quantidade_reservada, 0) FROM public.epis WHERE id = v_epi);
  v_est1 := (SELECT quantidade_estoque FROM public.epis WHERE id = v_epi);

  BEGIN
    PERFORM public.epi_registrar_entrega(jsonb_build_object(
      'tenant_id', v_t, 'epi_id', v_epi, 'colaborador_nome', 'QA Colaborador 057 B',
      'colaborador_cpf', public.qa_cpf(57), 'quantidade', 50, 'data_entrega', CURRENT_DATE,
      'status', 'recusado', 'observacoes', 'RECUSADO: QA acima do saldo'));
  EXCEPTION WHEN OTHERS THEN v_erro2 := SQLERRM;
  END;
  v_res2 := (SELECT COALESCE(quantidade_reservada, 0) FROM public.epis WHERE id = v_epi);
  v_recusas := (SELECT count(*) FROM public.epi_entregas WHERE epi_id = v_epi AND status = 'recusado');

  -- Entrega aguardando assinatura (não é recusa): continua reservando.
  v_ent := (public.epi_registrar_entrega(jsonb_build_object(
    'tenant_id', v_t, 'epi_id', v_epi, 'colaborador_nome', 'QA Colaborador 057 C',
    'colaborador_cpf', public.qa_cpf(57), 'quantidade', 2, 'data_entrega', CURRENT_DATE,
    'status', 'ativa'))->>'id')::uuid;
  v_res3 := (SELECT COALESCE(quantidade_reservada, 0) FROM public.epis WHERE id = v_epi);
  v_est3 := (SELECT quantidade_estoque FROM public.epis WHERE id = v_epi);

  UPDATE public.epi_entregas SET assinatura_url = 'qa/c.png', signed_at = now() WHERE id = v_ent;
  v_res4 := (SELECT COALESCE(quantidade_reservada, 0) FROM public.epis WHERE id = v_epi);
  v_est4 := (SELECT quantidade_estoque FROM public.epis WHERE id = v_epi);

  IF v_res1 <> 0 OR v_est1 <> 10 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: uma recusa de 3 unidades deixou %s reservada(s) e o estoque em %s; não deveria reservar nada (reservado 0, estoque 10).', v_res1, v_est1);
  ELSIF v_erro2 IS NOT NULL OR v_recusas <> 2 THEN
    r.situacao := 'falhou';
    r.obtido := format('A recusa acima do saldo foi barrada (%s) e o registro se perdeu (recusas gravadas: %s, esperado 2).', COALESCE(v_erro2, 'sem erro'), v_recusas);
  ELSIF v_res2 <> 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('Depois das recusas ficaram %s unidade(s) reservada(s); esperado 0.', v_res2);
  ELSIF v_res3 <> 2 OR v_est3 <> 10 THEN
    r.situacao := 'falhou';
    r.obtido := format('A entrega aguardando assinatura deveria reservar 2 e manter o físico em 10; ficou reservado %s e físico %s.', v_res3, v_est3);
  ELSIF v_res4 <> 0 OR v_est4 <> 8 THEN
    r.situacao := 'falhou';
    r.obtido := format('Ao assinar, esperava reservado 0 e estoque 8; ficou reservado %s e estoque %s.', v_res4, v_est4);
  ELSE
    r.situacao := 'passou';
    r.obtido := 'As recusas (inclusive acima do saldo) foram gravadas sem reservar nada; a entrega aguardando assinatura reservou 2 e, ao assinar, baixou o físico para 8 e zerou a reserva.';
  END IF;
  r.detalhe := jsonb_build_object('reservado_apos_recusa', v_res1, 'recusas_gravadas', v_recusas,
                                  'reservado_apos_aguardar', v_res3, 'estoque_final', v_est4);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;
