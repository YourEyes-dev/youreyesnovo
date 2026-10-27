-- =========================================================
-- QA — EPI-057: a recusa de assinatura não prende estoque.
--
-- O defeito: atualizar_estoque_epi reserva o saldo em QUALQUER entrega inserida
-- sem assinatura. A recusa do colaborador em assinar é gravada sem assinatura
-- (status extraviado), então reservava unidades que nunca seriam entregues e
-- nada as liberava: a cada recusa o saldo disponível (estoque menos reservado)
-- encolhia para sempre. Pior: uma recusa com o saldo disponível baixo era
-- BARRADA pela checagem de reserva, e o registro da recusa se perdia.
--
-- Só documenta e liga o teste; não altera comportamento. Idempotente.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid;
BEGIN
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'saude-ocupacional/epi');
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo saude-ocupacional/epi não encontrado.'; END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'EPI-057',
   'A recusa de assinatura não reserva nem prende estoque, e continua registrada',
   'negativo', 'alta', 'aprovado', 'api',
   'NR-6 (registro do fornecimento); Documento YE-DP-EPI-001, RN-005 (reserva só enquanto a entrega aguarda assinatura)',
   'A recusa do colaborador em assinar precisa ficar registrada (com a advertência), mas o EPI não saiu do almoxarifado: não pode reservar unidades nem consumir o saldo disponível. A reserva existe só para a entrega que ainda aguarda a assinatura.',
   'Sandbox QA com um EPI com 10 unidades.',
   '[{"ordem":1,"acao":"Registrar uma recusa de 3 unidades","resultado_esperado":"Recusa gravada; reservado continua 0 e o estoque continua 10"},
     {"ordem":2,"acao":"Registrar uma recusa de 50 unidades (acima do saldo)","resultado_esperado":"A recusa é gravada mesmo assim: é só um registro, não uma saída"},
     {"ordem":3,"acao":"Registrar uma entrega SEM assinatura e SEM recusa (aguardando assinatura) de 2 unidades","resultado_esperado":"Reserva 2 unidades, estoque físico 10"},
     {"ordem":4,"acao":"Assinar essa entrega","resultado_esperado":"Baixa definitiva: estoque 8 e reservado volta a 0"}]'::jsonb,
   'Recusa registra sem reservar; a reserva da entrega que aguarda assinatura segue funcionando.',
   'Guarda a correção do gatilho atualizar_estoque_epi (reserva só com status ativa). Reservas que a recusa já tinha prendido são recompostas pelo script de reparo, com cópia prévia.')
  ON CONFLICT (codigo) DO UPDATE SET
    titulo = EXCLUDED.titulo, objetivo = EXCLUDED.objetivo, passos = EXCLUDED.passos,
    resultado_esperado = EXCLUDED.resultado_esperado, observacoes = EXCLUDED.observacoes;
END $doc$;

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
    'status', 'extraviado', 'observacoes', 'RECUSADO: QA'));
  v_res1 := (SELECT COALESCE(quantidade_reservada, 0) FROM public.epis WHERE id = v_epi);
  v_est1 := (SELECT quantidade_estoque FROM public.epis WHERE id = v_epi);

  BEGIN
    PERFORM public.epi_registrar_entrega(jsonb_build_object(
      'tenant_id', v_t, 'epi_id', v_epi, 'colaborador_nome', 'QA Colaborador 057 B',
      'colaborador_cpf', public.qa_cpf(57), 'quantidade', 50, 'data_entrega', CURRENT_DATE,
      'status', 'extraviado', 'observacoes', 'RECUSADO: QA acima do saldo'));
  EXCEPTION WHEN OTHERS THEN v_erro2 := SQLERRM;
  END;
  v_res2 := (SELECT COALESCE(quantidade_reservada, 0) FROM public.epis WHERE id = v_epi);
  v_recusas := (SELECT count(*) FROM public.epi_entregas WHERE epi_id = v_epi AND status = 'extraviado');

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

INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES ('EPI-057', 'qa_caso_epi_057')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql;
