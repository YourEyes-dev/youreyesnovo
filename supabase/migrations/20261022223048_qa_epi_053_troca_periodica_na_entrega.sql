-- =========================================================
-- QA — EPI-053: a entrega de um EPI com periodicidade de troca calcula a data
-- prevista da troca (e não quebra).
--
-- O defeito, achado na primeira entrega ponta a ponta no navegador do staging:
-- o gatilho epi_entrega_calcula_troca somava inteiro a um timestamptz
-- (NEW.data_entrega + dias), operador que não existe no PostgreSQL. Resultado:
-- TODA entrega de EPI cujo tipo tem periodicidade_troca_dias falhava com
-- "operator does not exist: timestamp with time zone + integer", pelo wizard
-- antigo e pelo novo. O EPI-050 passava porque só conferia que a FUNÇÃO
-- existia; e os testes de entrega usavam tipos sem periodicidade.
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
  (v_mod, 'EPI-053',
   'A entrega de EPI com periodicidade de troca calcula a data prevista da troca',
   'feliz', 'alta', 'aprovado', 'api',
   'NR-6 (substituição do EPI danificado ou extraviado e guarda pelo empregador); Documento YE-DP-EPI-001, RF-016 (troca periódica)',
   'A periodicidade de troca do EPI é o que permite cobrar a substituição antes do desgaste. Se o cálculo da data prevista quebra, a entrega inteira falha e a empresa fica sem registrar o fornecimento.',
   'Sandbox QA com dois tipos de EPI: um com periodicidade de troca e outro sem.',
   '[{"ordem":1,"acao":"Entregar um EPI de tipo com periodicidade de 180 dias","resultado_esperado":"A entrega é gravada e a data prevista da troca é a data da entrega mais 180 dias"},
     {"ordem":2,"acao":"Entregar um EPI de tipo sem periodicidade","resultado_esperado":"A entrega é gravada sem data prevista de troca"},
     {"ordem":3,"acao":"Entregar informando a data prevista","resultado_esperado":"A data informada é respeitada, não recalculada"}]'::jsonb,
   'A entrega com periodicidade funciona e grava a data prevista da troca.',
   'Guarda a correção do gatilho epi_entrega_calcula_troca (timestamptz + inteiro). Achado na primeira entrega ponta a ponta no staging.')
  ON CONFLICT (codigo) DO UPDATE SET
    titulo = EXCLUDED.titulo, objetivo = EXCLUDED.objetivo, passos = EXCLUDED.passos,
    resultado_esperado = EXCLUDED.resultado_esperado, observacoes = EXCLUDED.observacoes;
END $doc$;

CREATE OR REPLACE FUNCTION public.qa_caso_epi_053()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_tipo_a uuid; v_tipo_b uuid; v_epi_a uuid; v_epi_b uuid;
        v_a jsonb; v_b jsonb; v_c jsonb; v_esperada date;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Entregar EPI com periodicidade de 180 dias, outro sem periodicidade, e um com data prevista informada';
  r.esperado := 'Com periodicidade: data da entrega + 180 dias. Sem: nada. Informada: respeitada';
  INSERT INTO public.epi_tipos (tenant_id, nome, ca_numero, ca_validade, is_active, periodicidade_troca_dias)
  VALUES (v_t, 'QA — Luva com troca', '99053', CURRENT_DATE + 365, true, 180) RETURNING id INTO v_tipo_a;
  INSERT INTO public.epi_tipos (tenant_id, nome, ca_numero, ca_validade, is_active)
  VALUES (v_t, 'QA — Óculos sem troca', '99054', CURRENT_DATE + 365, true) RETURNING id INTO v_tipo_b;
  INSERT INTO public.epis (tenant_id, tipo_id, codigo, quantidade_estoque, data_validade)
  VALUES (v_t, v_tipo_a, 'QA-EPI-053A', 10, CURRENT_DATE + 365) RETURNING id INTO v_epi_a;
  INSERT INTO public.epis (tenant_id, tipo_id, codigo, quantidade_estoque, data_validade)
  VALUES (v_t, v_tipo_b, 'QA-EPI-053B', 10, CURRENT_DATE + 365) RETURNING id INTO v_epi_b;

  v_esperada := CURRENT_DATE + 180;

  v_a := public.epi_registrar_entrega(jsonb_build_object(
    'tenant_id', v_t, 'epi_id', v_epi_a, 'colaborador_nome', 'QA Colaborador 053 A',
    'colaborador_cpf', public.qa_cpf(53), 'quantidade', 1, 'data_entrega', CURRENT_DATE,
    'status', 'ativa', 'assinatura_url', 'qa/a.png', 'signed_at', now()));
  v_b := public.epi_registrar_entrega(jsonb_build_object(
    'tenant_id', v_t, 'epi_id', v_epi_b, 'colaborador_nome', 'QA Colaborador 053 B',
    'colaborador_cpf', public.qa_cpf(53), 'quantidade', 1, 'data_entrega', CURRENT_DATE,
    'status', 'ativa', 'assinatura_url', 'qa/b.png', 'signed_at', now()));
  v_c := public.epi_registrar_entrega(jsonb_build_object(
    'tenant_id', v_t, 'epi_id', v_epi_a, 'colaborador_nome', 'QA Colaborador 053 C',
    'colaborador_cpf', public.qa_cpf(53), 'quantidade', 1, 'data_entrega', CURRENT_DATE,
    'status', 'ativa', 'assinatura_url', 'qa/c.png', 'signed_at', now()));

  IF (v_a->>'data_devolucao_prevista')::date IS DISTINCT FROM v_esperada THEN
    r.situacao := 'falhou';
    r.obtido := format('Data prevista da troca: %s; o esperado é %s (entrega + 180 dias).',
                       COALESCE(v_a->>'data_devolucao_prevista', 'vazia'), v_esperada);
  ELSIF v_b->>'data_devolucao_prevista' IS NOT NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('EPI sem periodicidade ganhou data prevista (%s); deveria ficar vazia.', v_b->>'data_devolucao_prevista');
  ELSE
    -- Data informada: atualiza uma entrega com data própria e confere que o gatilho respeita.
    BEGIN
      INSERT INTO public.epi_entregas
        (tenant_id, epi_id, colaborador_nome, colaborador_cpf, quantidade, data_entrega,
         data_devolucao_prevista, assinatura_url, signed_at)
      VALUES (v_t, v_epi_a, 'QA Colaborador 053 D', public.qa_cpf(53), 1, now(),
              CURRENT_DATE + 7, 'qa/d.png', now());
      IF (SELECT e.data_devolucao_prevista FROM public.epi_entregas e
           WHERE e.colaborador_nome = 'QA Colaborador 053 D' AND e.epi_id = v_epi_a) <> CURRENT_DATE + 7 THEN
        r.situacao := 'falhou';
        r.obtido := 'A data prevista informada foi recalculada; deveria ser respeitada.';
      ELSE
        r.situacao := 'passou';
        r.obtido := format('Com periodicidade de 180 dias a troca ficou em %s; sem periodicidade ficou vazia; a data informada foi respeitada.', v_esperada);
      END IF;
    END;
  END IF;
  r.detalhe := jsonb_build_object('com_periodicidade', v_a->>'data_devolucao_prevista',
                                  'sem_periodicidade', v_b->>'data_devolucao_prevista');
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES ('EPI-053', 'qa_caso_epi_053')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql;
