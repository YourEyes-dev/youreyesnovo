-- =========================================================
-- QA — EPI-046: a entrega assinada baixa o estoque uma vez só e, se falhar, não
-- deixa nada para trás (ficha, saldo ou movimentação).
--
-- Guarda a correção de epi_registrar_entrega. O defeito, provado numa réplica
-- com todas as migrations: o gatilho baixava o estoque global no INSERT e o
-- wizard fazia uma segunda baixa esperando o saldo de antes; ela nunca batia, o
-- wizard APAGAVA a entrega assinada e o estoque ficava descontado sem ficha.
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
  (v_mod, 'EPI-046',
   'A entrega assinada baixa o estoque uma vez só e, se falhar, não deixa nada para trás',
   'negativo', 'alta', 'aprovado', 'api',
   'NR-6 (controle do EPI fornecido); Documento YE-DP-EPI-001, RN-003/RN-005 (saldo nunca negativo; baixa condicionada à assinatura)',
   'A ficha de entrega é prova. Se a baixa de estoque falha no meio e o sistema apaga a ficha, a empresa perde a prova e fica com o estoque descontado sem entrega. A entrega, a baixa (global e do local) e a movimentação precisam acontecer juntas ou não acontecer.',
   'Sandbox QA com um EPI com 10 unidades no global e 10 no local.',
   '[{"ordem":1,"acao":"Registrar a entrega assinada de 2 unidades escolhendo o local","resultado_esperado":"Global 8, local 8, uma única movimentação (10 para 8) e a ficha com hash"},
     {"ordem":2,"acao":"Tentar entregar mais do que o saldo","resultado_esperado":"Recusa com mensagem clara; nenhuma ficha, saldo ou movimentação alterados"},
     {"ordem":3,"acao":"Tentar entregar mais do que o saldo do local (o global cobre)","resultado_esperado":"Recusa; nada gravado"}]'::jsonb,
   'Entrega, baixa e movimentação são atômicas; falha não apaga nem deixa rastro parcial.',
   'Guarda a correção C6. Não cobre a substituição (marcar a entrega anterior como devolvida): o wizard usa colunas que não existem e isso nunca funcionou; decisão de regra pendente.')
  ON CONFLICT (codigo) DO UPDATE SET
    titulo = EXCLUDED.titulo, objetivo = EXCLUDED.objetivo, passos = EXCLUDED.passos,
    resultado_esperado = EXCLUDED.resultado_esperado, observacoes = EXCLUDED.observacoes;
END $doc$;

CREATE OR REPLACE FUNCTION public.qa_caso_epi_046()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_tipo uuid; v_epi uuid; v_loc uuid; v_ent jsonb;
        v_global int; v_local int; v_movs int; v_ant int; v_atu int; v_erro2 text; v_erro3 text;
        v_cpf text := public.qa_cpf(46);
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Registrar a entrega assinada de 2 unidades escolhendo o local';
  r.esperado := 'Global 8, local 8, uma movimentação (10 para 8) e ficha com hash';
  INSERT INTO public.epi_tipos (tenant_id, nome, ca_numero, ca_validade, is_active)
  VALUES (v_t, 'QA — Luva atômica', '99046', CURRENT_DATE + 365, true) RETURNING id INTO v_tipo;
  INSERT INTO public.epis (tenant_id, tipo_id, codigo, quantidade_estoque, data_validade)
  VALUES (v_t, v_tipo, 'QA-EPI-046', 10, CURRENT_DATE + 365) RETURNING id INTO v_epi;
  INSERT INTO public.epi_locais_estoque (tenant_id, nome) VALUES (v_t, 'QA — Almox 046') RETURNING id INTO v_loc;
  INSERT INTO public.epi_estoque_local (tenant_id, epi_id, local_estoque_id, quantidade, tamanho)
  VALUES (v_t, v_epi, v_loc, 10, '');

  v_ent := public.epi_registrar_entrega(jsonb_build_object(
    'tenant_id', v_t, 'epi_id', v_epi, 'colaborador_nome', 'QA Colaborador 046',
    'colaborador_cpf', v_cpf, 'quantidade', 2, 'data_entrega', CURRENT_DATE,
    'status', 'ativa', 'assinatura_url', 'qa/assinatura-046.png', 'signed_at', now()), v_loc);

  v_global := (SELECT quantidade_estoque FROM public.epis WHERE id = v_epi);
  v_local  := (SELECT quantidade FROM public.epi_estoque_local WHERE epi_id = v_epi AND local_estoque_id = v_loc);
  v_movs   := (SELECT count(*) FROM public.epi_movimentacoes WHERE epi_id = v_epi);
  v_ant    := (SELECT quantidade_anterior FROM public.epi_movimentacoes WHERE epi_id = v_epi LIMIT 1);
  v_atu    := (SELECT quantidade_atual FROM public.epi_movimentacoes WHERE epi_id = v_epi LIMIT 1);

  IF v_global <> 8 OR v_local <> 8 OR v_movs <> 1 OR v_ant <> 10 OR v_atu <> 8
     OR COALESCE(v_ent->>'assinatura_hash', '') = '' THEN
    r.situacao := 'falhou';
    r.obtido := format('Baixa/ficha incorretas: global %s (esperado 8), local %s (esperado 8), movimentações %s (esperado 1, de 10 para 8; veio %s para %s), hash %s.',
                       v_global, v_local, v_movs, v_ant, v_atu,
                       CASE WHEN COALESCE(v_ent->>'assinatura_hash', '') = '' THEN 'ausente' ELSE 'ok' END);
    RETURN r;
  END IF;

  r.passo_ordem := 2;
  r.passo_acao := 'Tentar entregar mais do que o saldo e mais do que o saldo do local';
  r.esperado := 'Recusa com nada gravado: sem ficha, sem mudança de saldo, sem movimentação';
  BEGIN
    PERFORM public.epi_registrar_entrega(jsonb_build_object(
      'tenant_id', v_t, 'epi_id', v_epi, 'colaborador_nome', 'QA Colaborador 046 B',
      'quantidade', 99, 'data_entrega', CURRENT_DATE, 'status', 'ativa',
      'assinatura_url', 'qa/b.png', 'signed_at', now()), v_loc);
  EXCEPTION WHEN OTHERS THEN v_erro2 := SQLERRM;
  END;

  UPDATE public.epi_estoque_local SET quantidade = 1 WHERE epi_id = v_epi AND local_estoque_id = v_loc;
  BEGIN
    PERFORM public.epi_registrar_entrega(jsonb_build_object(
      'tenant_id', v_t, 'epi_id', v_epi, 'colaborador_nome', 'QA Colaborador 046 C',
      'quantidade', 3, 'data_entrega', CURRENT_DATE, 'status', 'ativa',
      'assinatura_url', 'qa/c.png', 'signed_at', now()), v_loc);
  EXCEPTION WHEN OTHERS THEN v_erro3 := SQLERRM;
  END;

  v_global := (SELECT quantidade_estoque FROM public.epis WHERE id = v_epi);
  v_movs   := (SELECT count(*) FROM public.epi_movimentacoes WHERE epi_id = v_epi);

  IF v_erro2 IS NULL OR v_erro3 IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('Entrega acima do saldo não foi recusada (global: %s; local: %s).',
                       COALESCE(v_erro2, 'ACEITA'), COALESCE(v_erro3, 'ACEITA'));
  ELSIF v_global <> 8
     OR EXISTS (SELECT 1 FROM public.epi_entregas WHERE colaborador_nome IN ('QA Colaborador 046 B', 'QA Colaborador 046 C'))
     OR v_movs <> 1 THEN
    r.situacao := 'falhou';
    r.obtido := format('A recusa deixou rastro parcial: global %s (esperado 8), movimentações %s (esperado 1), entregas das tentativas recusadas: %s.',
                       v_global, v_movs,
                       (SELECT count(*) FROM public.epi_entregas WHERE colaborador_nome IN ('QA Colaborador 046 B', 'QA Colaborador 046 C')));
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Entrega assinada baixou uma vez (global 8, local 8, uma movimentação, com hash) e as duas recusas não deixaram rastro.';
  END IF;
  r.detalhe := jsonb_build_object('erro_acima_do_saldo', v_erro2, 'erro_acima_do_local', v_erro3);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES ('EPI-046', 'qa_caso_epi_046')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql;
