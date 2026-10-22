-- ============================================================================
-- ENTREGA — QA do EPI: caso EPI-047 (origem da assinatura) e sua rotina
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de TESTE depois do script
-- script_epi_origem_assinatura_pelo_servidor.sql. Só documenta o caso e cria a
-- rotina; não altera comportamento nem dado de cliente. UMA transação,
-- idempotente, sem criar tabela.
-- ============================================================================

-- =========================================================
-- QA — EPI-047: a origem da assinatura (IP e hora) vem do SERVIDOR, não do
-- navegador.
--
-- O wizard gravava ip_address como string vazia e signed_at com o relógio do
-- aparelho. Uma ficha assinada sem IP e com hora que o usuário pode alterar não
-- prova onde e quando a assinatura ocorreu. A prova precisa vir do servidor, e
-- um valor que o cliente mande não pode se sobrepor ao que o servidor viu.
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
  (v_mod, 'EPI-047',
   'A origem da assinatura (IP e hora) é registrada pelo servidor e não pode ser forjada pelo navegador',
   'negativo', 'alta', 'aprovado', 'api',
   'Lei 14.063/2020, art. 4º (assinatura avançada: identificar o signatário e detectar alteração); MP 2.200-2/2001, art. 10, §2º; LGPD art. 6º, X (prestação de contas)',
   'A trilha da assinatura responde quem, quando e de onde. Se o IP vem em branco ou do navegador, e a hora do relógio do aparelho, a empresa não consegue sustentar em juízo onde e quando a assinatura foi colhida.',
   'Sandbox QA com um EPI em estoque.',
   '[{"ordem":1,"acao":"Registrar a entrega assinada com cabeçalhos de uma requisição real, mandando no corpo um IP falso e uma hora de 2020","resultado_esperado":"ip_address é o do cabeçalho do servidor e signed_at é a hora do servidor"},
     {"ordem":2,"acao":"Conferir o selo de integridade","resultado_esperado":"assinatura_hash preenchido, calculado sobre a hora do servidor"},
     {"ordem":3,"acao":"Registrar sem cabeçalhos de requisição (chamada interna)","resultado_esperado":"mantém o IP informado, sem inventar valor"}]'::jsonb,
   'IP e hora da assinatura vêm do servidor; o que o navegador mandar não se sobrepõe.',
   'Guarda a correção C5. O IP é o do cabeçalho x-forwarded-for / cf-connecting-ip da requisição (primeiro endereço). Geolocalização não entra: exigiria consentimento específico (LGPD) e fica para decisão à parte.')
  ON CONFLICT (codigo) DO UPDATE SET
    titulo = EXCLUDED.titulo, objetivo = EXCLUDED.objetivo, passos = EXCLUDED.passos,
    resultado_esperado = EXCLUDED.resultado_esperado, observacoes = EXCLUDED.observacoes;
END $doc$;

CREATE OR REPLACE FUNCTION public.qa_caso_epi_047()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_tipo uuid; v_epi uuid; v_ent jsonb; v_ent2 jsonb;
        v_ip text; v_hora timestamptz; v_ip2 text;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Registrar a entrega assinada com cabeçalhos de requisição, mandando IP falso e hora de 2020';
  r.esperado := 'ip_address do cabeçalho do servidor; signed_at do relógio do servidor; hash preenchido';
  INSERT INTO public.epi_tipos (tenant_id, nome, ca_numero, ca_validade, is_active)
  VALUES (v_t, 'QA — Luva origem', '99047', CURRENT_DATE + 365, true) RETURNING id INTO v_tipo;
  INSERT INTO public.epis (tenant_id, tipo_id, codigo, quantidade_estoque, data_validade)
  VALUES (v_t, v_tipo, 'QA-EPI-047', 10, CURRENT_DATE + 365) RETURNING id INTO v_epi;

  PERFORM set_config('request.headers',
    '{"x-forwarded-for":"203.0.113.7, 10.0.0.1","user-agent":"qa-agent"}', true);
  v_ent := public.epi_registrar_entrega(jsonb_build_object(
    'tenant_id', v_t, 'epi_id', v_epi, 'colaborador_nome', 'QA Colaborador 047',
    'colaborador_cpf', public.qa_cpf(47), 'quantidade', 1, 'data_entrega', CURRENT_DATE,
    'status', 'ativa', 'assinatura_url', 'qa/assinatura-047.png',
    'signed_at', '2020-01-01T00:00:00Z', 'ip_address', '1.1.1.1'));
  v_ip := v_ent->>'ip_address';
  v_hora := (v_ent->>'signed_at')::timestamptz;

  r.passo_ordem := 2;
  r.passo_acao := 'Registrar sem cabeçalhos de requisição (chamada interna)';
  PERFORM set_config('request.headers', '', true);
  v_ent2 := public.epi_registrar_entrega(jsonb_build_object(
    'tenant_id', v_t, 'epi_id', v_epi, 'colaborador_nome', 'QA Colaborador 047 B',
    'colaborador_cpf', public.qa_cpf(47), 'quantidade', 1, 'data_entrega', CURRENT_DATE,
    'status', 'ativa', 'assinatura_url', 'qa/assinatura-047b.png',
    'signed_at', now(), 'ip_address', '198.51.100.9'));
  v_ip2 := v_ent2->>'ip_address';

  IF v_ip IS DISTINCT FROM '203.0.113.7' THEN
    r.situacao := 'falhou';
    r.obtido := format('O IP gravado foi %s; o esperado é o do cabeçalho do servidor (203.0.113.7). O navegador mandou 1.1.1.1 e isso não pode prevalecer.',
                       COALESCE(v_ip, 'vazio'));
  ELSIF v_hora < now() - interval '5 minutes' THEN
    r.situacao := 'falhou';
    r.obtido := format('signed_at ficou em %s, a hora que o navegador mandou, e não a do servidor.', v_hora);
  ELSIF COALESCE(v_ent->>'assinatura_hash', '') = '' THEN
    r.situacao := 'falhou';
    r.obtido := 'A ficha assinada ficou sem hash de integridade.';
  ELSIF v_ip2 IS DISTINCT FROM '198.51.100.9' THEN
    r.situacao := 'falhou';
    r.obtido := format('Sem cabeçalhos de requisição o IP informado deveria ser mantido (198.51.100.9) e ficou %s.',
                       COALESCE(v_ip2, 'vazio'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('IP %s e hora %s vieram do servidor (o IP e a hora forjados foram ignorados); hash preenchido; sem cabeçalhos mantém o valor informado.',
                       v_ip, to_char(v_hora, 'YYYY-MM-DD HH24:MI'));
  END IF;
  r.detalhe := jsonb_build_object('ip', v_ip, 'signed_at', v_hora, 'ip_sem_cabecalho', v_ip2);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES ('EPI-047', 'qa_caso_epi_047')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql;

-- Conferência final (o editor mostra só este resultado):
SELECT
  EXISTS (SELECT 1 FROM public.qa_casos_teste WHERE codigo = 'EPI-047') AS caso_documentado,
  EXISTS (SELECT 1 FROM public.qa_implementacoes WHERE codigo = 'EPI-047'
           AND funcao_sql = 'qa_caso_epi_047') AS rotina_registrada,
  (SELECT count(*) FROM pg_proc WHERE proname = 'qa_caso_epi_047') AS funcao_criada,
  NULL::text AS erro_tecnico;

-- Para desfazer:
--   DELETE FROM public.qa_implementacoes WHERE codigo = 'EPI-047';
--   DROP FUNCTION IF EXISTS public.qa_caso_epi_047();
--   DELETE FROM public.qa_casos_teste WHERE codigo = 'EPI-047';
