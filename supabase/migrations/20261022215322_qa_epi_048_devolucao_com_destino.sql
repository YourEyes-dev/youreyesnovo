-- =========================================================
-- QA — EPI-048: a devolução respeita o destino do EPI (estoque, manutenção ou
-- descarte) e acontece numa transação só.
--
-- O defeito, provado numa réplica com todas as migrations: o gatilho de
-- epi_entregas devolve o item ao estoque global em QUALQUER devolução. Com
-- destino "descarte" o estoque subia (entrega 2: 10 para 8; devolver para
-- descarte: 8 para 10), como se o EPI descartado ainda existisse. A tela fazia
-- depois vários passos soltos, sem transação.
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
  (v_mod, 'EPI-048',
   'A devolução respeita o destino (estoque, manutenção ou descarte) e não infla o estoque',
   'negativo', 'alta', 'aprovado', 'api',
   'NR-6 (o empregador responde pela guarda, higienização, manutenção e substituição do EPI); Documento YE-DP-EPI-001, RN-003 (saldo confiável)',
   'EPI desgastado, danificado ou vencido que volta ao estoque como se estivesse bom é risco de segurança, e estoque inflado por item descartado esconde a necessidade de reposição. O destino da devolução decide o que acontece com o saldo, e tudo precisa acontecer junto ou não acontecer.',
   'Sandbox QA com um EPI com 10 unidades.',
   '[{"ordem":1,"acao":"Entregar 2 unidades assinadas e devolver para DESCARTE","resultado_esperado":"Estoque continua em 8 (o item descartado não volta ao saldo); movimentações de devolução e de descarte registradas"},
     {"ordem":2,"acao":"Entregar 2 e devolver para ESTOQUE","resultado_esperado":"Estoque volta a 8 e a entrega fica devolvida"},
     {"ordem":3,"acao":"Entregar 1 e devolver para MANUTENÇÃO","resultado_esperado":"Saldo global recompõe e o local Em Manutenção recebe a unidade"},
     {"ordem":4,"acao":"Devolver de novo a mesma entrega e usar um destino inválido","resultado_esperado":"Recusa, sem alterar nada"},
     {"ordem":5,"acao":"Substituir um EPI entregue escolhendo DESCARTE para o anterior; tentar a substituição sem destino","resultado_esperado":"Com destino: nova entrega e anterior devolvida juntos, sem inflar o saldo. Sem destino: recusa sem gravar nada"}]'::jsonb,
   'O destino define o saldo; a devolução é atômica e não pode ser repetida.',
   'Guarda a correção da devolução e a base da substituição com destino escolhido a cada vez. O estoque devolvido não volta a um local específico (a entrega não guarda o local de origem): só o global recompõe.')
  ON CONFLICT (codigo) DO UPDATE SET
    titulo = EXCLUDED.titulo, objetivo = EXCLUDED.objetivo, passos = EXCLUDED.passos,
    resultado_esperado = EXCLUDED.resultado_esperado, observacoes = EXCLUDED.observacoes;
END $doc$;

CREATE OR REPLACE FUNCTION public.qa_caso_epi_048()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_tipo uuid; v_epi uuid; v_e1 uuid; v_e2 uuid; v_e3 uuid;
        v_g1 int; v_g2 int; v_g3 int; v_loc_manut int; v_mov_desc int;
        v_erro_repete text; v_erro_destino text; v_st1 text; v_st2 text; v_st3 text;
        v_e4 uuid; v_e5 uuid; v_g4 int; v_g5 int; v_st4 text; v_erro_subst text; v_g6 int; v_novas int;
        v_cpf text := public.qa_cpf(48);
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Entregar e devolver para descarte, estoque e manutenção';
  r.esperado := 'Descarte não volta ao saldo; estoque volta; manutenção recompõe e vai ao local Em Manutenção';
  INSERT INTO public.epi_tipos (tenant_id, nome, ca_numero, ca_validade, is_active)
  VALUES (v_t, 'QA — Luva devolução', '99048', CURRENT_DATE + 365, true) RETURNING id INTO v_tipo;
  INSERT INTO public.epis (tenant_id, tipo_id, codigo, quantidade_estoque, data_validade)
  VALUES (v_t, v_tipo, 'QA-EPI-048', 10, CURRENT_DATE + 365) RETURNING id INTO v_epi;

  v_e1 := (public.epi_registrar_entrega(jsonb_build_object(
    'tenant_id', v_t, 'epi_id', v_epi, 'colaborador_nome', 'QA Colaborador 048',
    'colaborador_cpf', v_cpf, 'quantidade', 2, 'data_entrega', CURRENT_DATE, 'status', 'ativa',
    'assinatura_url', 'qa/a.png', 'signed_at', now()))->>'id')::uuid;
  PERFORM public.epi_devolver_entrega(v_e1, 'descarte', 'QA descarte');
  v_g1 := (SELECT quantidade_estoque FROM public.epis WHERE id = v_epi);
  v_st1 := (SELECT status::text FROM public.epi_entregas WHERE id = v_e1);
  v_mov_desc := (SELECT count(*) FROM public.epi_movimentacoes
                  WHERE epi_id = v_epi AND subtipo = 'descarte');

  v_e2 := (public.epi_registrar_entrega(jsonb_build_object(
    'tenant_id', v_t, 'epi_id', v_epi, 'colaborador_nome', 'QA Colaborador 048 B',
    'colaborador_cpf', v_cpf, 'quantidade', 2, 'data_entrega', CURRENT_DATE, 'status', 'ativa',
    'assinatura_url', 'qa/b.png', 'signed_at', now()))->>'id')::uuid;
  PERFORM public.epi_devolver_entrega(v_e2, 'estoque', NULL);
  v_g2 := (SELECT quantidade_estoque FROM public.epis WHERE id = v_epi);
  v_st2 := (SELECT status::text FROM public.epi_entregas WHERE id = v_e2);

  v_e3 := (public.epi_registrar_entrega(jsonb_build_object(
    'tenant_id', v_t, 'epi_id', v_epi, 'colaborador_nome', 'QA Colaborador 048 C',
    'colaborador_cpf', v_cpf, 'quantidade', 1, 'data_entrega', CURRENT_DATE, 'status', 'ativa',
    'assinatura_url', 'qa/c.png', 'signed_at', now()))->>'id')::uuid;
  PERFORM public.epi_devolver_entrega(v_e3, 'manutencao', NULL);
  v_g3 := (SELECT quantidade_estoque FROM public.epis WHERE id = v_epi);
  v_st3 := (SELECT status::text FROM public.epi_entregas WHERE id = v_e3);
  v_loc_manut := COALESCE((SELECT sum(l.quantidade) FROM public.epi_estoque_local l
                             JOIN public.epi_locais_estoque c ON c.id = l.local_estoque_id
                            WHERE l.epi_id = v_epi AND c.nome = 'Em Manutenção'), 0);

  r.passo_ordem := 2;
  r.passo_acao := 'Devolver de novo a mesma entrega e usar um destino inválido';
  BEGIN
    PERFORM public.epi_devolver_entrega(v_e1, 'estoque', NULL);
  EXCEPTION WHEN OTHERS THEN v_erro_repete := SQLERRM;
  END;
  BEGIN
    PERFORM public.epi_devolver_entrega(v_e3, 'lixeira', NULL);
  EXCEPTION WHEN OTHERS THEN v_erro_destino := SQLERRM;
  END;

  r.passo_ordem := 3;
  r.passo_acao := 'Substituir um EPI entregue, escolhendo o destino do anterior (descarte), e tentar sem destino';
  v_e4 := (public.epi_registrar_entrega(jsonb_build_object(
    'tenant_id', v_t, 'epi_id', v_epi, 'colaborador_nome', 'QA Colaborador 048 D',
    'colaborador_cpf', v_cpf, 'quantidade', 1, 'data_entrega', CURRENT_DATE, 'status', 'ativa',
    'assinatura_url', 'qa/d.png', 'signed_at', now()))->>'id')::uuid;   -- 8 para 7
  BEGIN
    PERFORM public.epi_registrar_entrega(jsonb_build_object(
      'tenant_id', v_t, 'epi_id', v_epi, 'colaborador_nome', 'QA Colaborador 048 E',
      'colaborador_cpf', v_cpf, 'quantidade', 1, 'data_entrega', CURRENT_DATE, 'status', 'ativa',
      'assinatura_url', 'qa/e0.png', 'signed_at', now()), NULL, v_e4, NULL);
  EXCEPTION WHEN OTHERS THEN v_erro_subst := SQLERRM;
  END;
  v_g6 := (SELECT quantidade_estoque FROM public.epis WHERE id = v_epi);
  v_novas := (SELECT count(*) FROM public.epi_entregas
               WHERE epi_id = v_epi AND colaborador_nome = 'QA Colaborador 048 E');
  v_e5 := (public.epi_registrar_entrega(jsonb_build_object(
    'tenant_id', v_t, 'epi_id', v_epi, 'colaborador_nome', 'QA Colaborador 048 E',
    'colaborador_cpf', v_cpf, 'quantidade', 1, 'data_entrega', CURRENT_DATE, 'status', 'ativa',
    'assinatura_url', 'qa/e.png', 'signed_at', now()), NULL, v_e4, 'descarte')->>'id')::uuid;
  v_g5 := (SELECT quantidade_estoque FROM public.epis WHERE id = v_epi);
  v_st4 := (SELECT status::text FROM public.epi_entregas WHERE id = v_e4);

  IF v_g1 <> 8 THEN
    r.situacao := 'falhou';
    r.obtido := format('Devolução para DESCARTE deixou o estoque em %s; o esperado é 8 (o item descartado não pode voltar ao saldo).', v_g1);
  ELSIF v_mov_desc < 1 THEN
    r.situacao := 'falhou';
    r.obtido := 'O descarte não deixou movimentação registrada.';
  ELSIF v_g2 <> 8 THEN
    r.situacao := 'falhou';
    r.obtido := format('Devolução para ESTOQUE deixou o saldo em %s; o esperado é 8 (6 após a entrega mais 2 devolvidas).', v_g2);
  ELSIF v_g3 <> 8 OR v_loc_manut < 1 THEN
    r.situacao := 'falhou';
    r.obtido := format('Devolução para MANUTENÇÃO: saldo global %s (esperado 8) e %s unidade(s) no local Em Manutenção (esperado ao menos 1).', v_g3, v_loc_manut);
  ELSIF v_st1 <> 'devolvido' OR v_st2 <> 'devolvido' OR v_st3 <> 'devolvido' THEN
    r.situacao := 'falhou';
    r.obtido := format('Status após devolver: %s, %s, %s (todos deveriam ser devolvido).', v_st1, v_st2, v_st3);
  ELSIF v_erro_repete IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'Devolver de novo a mesma entrega foi aceito; deveria ser recusado.';
  ELSIF v_erro_destino IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'Um destino inválido foi aceito.';
  ELSIF v_erro_subst IS NULL OR v_novas <> 0 OR v_g6 <> 7 THEN
    r.situacao := 'falhou';
    r.obtido := format('Substituição sem destino deveria ser recusada sem gravar nada: erro=%s, entregas novas=%s (esperado 0), saldo=%s (esperado 7).',
                       COALESCE(v_erro_subst, 'ACEITA'), v_novas, v_g6);
  ELSIF v_st4 <> 'devolvido' OR v_g5 <> 6 THEN
    r.situacao := 'falhou';
    r.obtido := format('Substituição com descarte: entrega anterior %s (esperado devolvido) e saldo %s (esperado 6: 7, menos 1 da nova, mais 1 devolvido, menos 1 descartado).',
                       v_st4, v_g5);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Descarte manteve o saldo em %s, estoque e manutenção recompuseram (8), o local Em Manutenção recebeu %s, e repetir ou usar destino inválido foi recusado; a substituição com descarte devolveu o anterior e fechou em %s, e sem destino foi recusada sem gravar nada.',
                       v_g1, v_loc_manut, v_g5);
  END IF;
  r.detalhe := jsonb_build_object('apos_descarte', v_g1, 'apos_estoque', v_g2, 'apos_manutencao', v_g3,
                                  'em_manutencao', v_loc_manut, 'apos_substituicao', v_g5, 'erro_repete', v_erro_repete,
                                  'erro_destino', v_erro_destino);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES ('EPI-048', 'qa_caso_epi_048')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql;
