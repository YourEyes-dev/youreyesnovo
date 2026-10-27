-- =========================================================
-- QA — EPI-055: a entrega marcada como ASSINADA exige a imagem da assinatura.
--
-- O defeito, achado na primeira entrega ponta a ponta no staging: na etapa da
-- assinatura o wizard fazia setSignatureData(data) e, na mesma hora,
-- saveEntrega("entregue"). O estado do React ainda estava vazio, então o
-- envio da foto e da assinatura era pulado, e a entrega era gravada com
-- signed_at preenchido, assinatura_url NULO e foto NULA: uma "ficha assinada"
-- sem assinatura, que não prova nada.
--
-- A regra precisa valer no BANCO (o front erra, o banco é a última barreira):
-- epi_registrar_entrega recusa entrega com signed_at e sem assinatura_url.
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
  (v_mod, 'EPI-055',
   'A entrega assinada exige a imagem da assinatura: não existe ficha assinada sem assinatura',
   'negativo', 'alta', 'aprovado', 'api',
   'Lei 14.063/2020, art. 4º (a assinatura avançada identifica o signatário); MP 2.200-2/2001, art. 10, §2º',
   'Uma ficha marcada como assinada, mas sem a imagem da assinatura, não prova o recebimento do EPI e dá à empresa uma falsa segurança. O banco é a última barreira: recusa a entrega assinada sem a assinatura, mesmo que a tela falhe.',
   'Sandbox QA com um EPI em estoque.',
   '[{"ordem":1,"acao":"Registrar uma entrega com signed_at e SEM assinatura_url","resultado_esperado":"Recusada, sem gravar entrega nem baixar estoque"},
     {"ordem":2,"acao":"Registrar a mesma entrega COM assinatura_url","resultado_esperado":"Gravada normalmente"},
     {"ordem":3,"acao":"Registrar uma recusa (sem assinatura e sem signed_at)","resultado_esperado":"Continua aceita"}]'::jsonb,
   'Só existe entrega assinada com a imagem da assinatura; a recusa segue possível.',
   'Guarda a correção do wizard (estado atrasado do React ao salvar) e a barreira no banco. A foto é exigida pela tela, não pelo banco, para não quebrar fluxos que a gravam depois.')
  ON CONFLICT (codigo) DO UPDATE SET
    titulo = EXCLUDED.titulo, objetivo = EXCLUDED.objetivo, passos = EXCLUDED.passos,
    resultado_esperado = EXCLUDED.resultado_esperado, observacoes = EXCLUDED.observacoes;
END $doc$;

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
    'status', 'extraviado', 'observacoes', 'RECUSADO: QA'));

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

INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES ('EPI-055', 'qa_caso_epi_055')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql;
