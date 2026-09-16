-- =========================================================
-- QA — Central de Controle de Clientes: captura de erros
--
-- Regra da casa: documentacao vem antes do teste. Este arquivo documenta os
-- casos (nivel 'api', porque tudo o que eles provam esta no banco) E ja traz
-- as rotinas do motor, para a bateria nao devolver "nao_implementado".
--
-- CENTRAL-001  dado pessoal nao chega ao disco em claro (LGPD, RN-002)
-- CENTRAL-002  escrita direta na tabela de evento e negada (RN-001)
-- CENTRAL-003  erros iguais agrupam em um incidente (RN-005)
-- CENTRAL-004  sem sessao, a ingestao recusa (secao 3.4)
-- CENTRAL-005  usuario entra pseudonimizado, nunca identificado (RN-003)
-- =========================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------
-- 1) Modulo na arvore da Documentacao de Testes
-- ---------------------------------------------------------
DO $mod$
DECLARE v_sec uuid;
BEGIN
  SELECT id INTO v_sec FROM public.qa_modulos WHERE path = 'sistema';
  IF v_sec IS NULL THEN
    RAISE EXCEPTION 'Bloco sistema nao encontrado na arvore de QA.';
  END IF;

  INSERT INTO public.qa_modulos (parent_id, label, path, ordem, prioridade_doc, status_doc)
  VALUES (v_sec, 'Central de Controle de Clientes', 'sistema/central-controle-clientes', 9, 2, 'documentado')
  ON CONFLICT (path) DO UPDATE
    SET label = EXCLUDED.label, status_doc = 'documentado', motivo_bloqueio = NULL;
END $mod$;

-- ---------------------------------------------------------
-- 2) Casos documentados
-- ---------------------------------------------------------
DO $doc$
DECLARE v_mod uuid;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'sistema/central-controle-clientes';

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'CENTRAL-001', 'Dado pessoal nao e gravado em claro no evento de erro',
   'negativo', 'critica', 'aprovado', 'api',
   'A Central e a maior superficie de dado pessoal interno da casa. Um erro na tela pode arrastar CPF, e-mail ou telefone do colaborador do cliente. Nada disso pode chegar ao disco.',
   'Usuario autenticado.',
   '[{"ordem":1,"acao":"Registrar um erro cuja mensagem contem CPF, e-mail, telefone e um token","resultado_esperado":"O evento gravado mostra [cpf], [email], [telefone] e [oculto]; nenhum dos valores originais aparece"}]'::jsonb,
   'O evento existe, e util para depurar, e nao carrega dado pessoal.',
   'LGPD art. 11 / RN-002. Mascaramento por public.mascarar_pii, aplicado na ingestao.'),

  (v_mod, 'CENTRAL-002', 'Escrita direta na tabela de evento e negada',
   'negativo', 'critica', 'aprovado', 'api',
   'Fecha a classe de vulnerabilidade ja conhecida na casa: gravacao direta em tabela exposta. A unica porta e a funcao do servidor.',
   'Sessao de usuario comum (papel authenticated).',
   '[{"ordem":1,"acao":"Tentar INSERT direto em evento_erro pelo papel authenticated","resultado_esperado":"A gravacao e recusada"}]'::jsonb,
   'Nenhum caminho de escrita alem de registrar_evento_erro.',
   'RN-001. A tabela nao tem politica de INSERT, de proposito.'),

  (v_mod, 'CENTRAL-003', 'Erros iguais agrupam em um unico incidente',
   'feliz', 'alta', 'aprovado', 'api',
   'Mil ocorrencias do mesmo defeito precisam virar UMA linha na fila de trabalho, senao a equipe se afoga e para de olhar.',
   'Usuario autenticado.',
   '[{"ordem":1,"acao":"Registrar duas vezes o mesmo erro, mudando apenas os numeros da mensagem","resultado_esperado":"Um unico incidente, com o contador de ocorrencias em 2"}]'::jsonb,
   'Um defeito = um incidente, com contagem.',
   'RN-005. A impressao digital ignora numeros, enderecos e aspas.'),

  (v_mod, 'CENTRAL-004', 'Sem sessao, a ingestao recusa o evento',
   'negativo', 'alta', 'aprovado', 'api',
   'A porta de entrada de evento so aceita origem autenticada da aplicacao, para nao virar deposito aberto de qualquer um.',
   'Nenhuma sessao ativa.',
   '[{"ordem":1,"acao":"Chamar a ingestao sem sessao","resultado_esperado":"Resposta gravado=false, motivo sem_sessao; nada e gravado"}]'::jsonb,
   'Evento anonimo nao entra.',
   'Secao 3.4 do documento de requisitos.'),

  (v_mod, 'CENTRAL-005', 'Usuario aparece pseudonimizado no evento',
   'feliz', 'alta', 'aprovado', 'api',
   'Precisamos saber que foi o mesmo usuario de novo, sem guardar quem ele e.',
   'Usuario autenticado.',
   '[{"ordem":1,"acao":"Registrar um erro e ler o evento gravado","resultado_esperado":"O campo do usuario traz um apelido estavel, diferente do id e sem e-mail ou nome"}]'::jsonb,
   'Rastreabilidade sem identificacao.',
   'RN-003. O sal do pseudonimo vive no app_config de cada ambiente.')
  ON CONFLICT (codigo) DO NOTHING;
END $doc$;

-- ---------------------------------------------------------
-- 3) Rotinas do motor (somente leitura do ponto de vista do usuario:
--    escrevem apenas dentro da propria transacao de teste)
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.qa_caso_central_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_texto text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Mascarar mensagem com CPF, e-mail, telefone e token';
  r.esperado := 'Nenhum valor original sobrevive ao mascaramento';

  v_texto := public.mascarar_pii(
    'colaborador 900.000.012-34 (maria.silva@empresa.com.br), fone (46) 99123-4567, token=abc123');

  IF v_texto LIKE '%[cpf]%' AND v_texto LIKE '%[email]%'
     AND v_texto LIKE '%[telefone]%' AND v_texto LIKE '%[oculto]%'
     AND v_texto NOT LIKE '%900.000.012-34%' AND v_texto NOT LIKE '%maria.silva%'
     AND v_texto NOT LIKE '%abc123%' THEN
    r.situacao := 'passou';
    r.obtido := 'Dado pessoal mascarado antes de gravar: ' || v_texto;
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'Sobrou dado pessoal no texto mascarado: ' || v_texto;
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_central_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_insert_livre boolean; v_grant boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA: procurar caminho de escrita direta em evento_erro';
  r.esperado := 'Nenhuma politica de INSERT e nenhum GRANT de INSERT para anon/authenticated';

  SELECT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'evento_erro'
      AND cmd IN ('INSERT', 'ALL')
  ) INTO v_insert_livre;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.role_table_grants
    WHERE table_schema = 'public' AND table_name = 'evento_erro'
      AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE')
      AND grantee IN ('anon', 'authenticated')
  ) INTO v_grant;

  IF NOT v_insert_livre AND NOT v_grant THEN
    r.situacao := 'passou';
    r.obtido := 'Escrita so pela funcao do servidor: sem politica de INSERT e sem GRANT de escrita.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'Existe caminho de escrita direta (politica=' || v_insert_livre::text ||
                ', grant=' || v_grant::text || ').';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_central_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_uid uuid; v_a jsonb; v_b jsonb; v_oc int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Registrar o mesmo erro duas vezes, mudando so os numeros';
  r.esperado := 'Um unico incidente, com duas ocorrencias';

  SELECT user_id INTO v_uid FROM public.superadmins WHERE ativo LIMIT 1;
  IF v_uid IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Sem superadmin ativo para simular a sessao.';
    RETURN r;
  END IF;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);

  v_a := public.registrar_evento_erro(jsonb_build_object(
    'mensagem', '[QA-CENTRAL3] falha no registro 111', 'modulo', 'QA',
    'tipo', 'QaTeste', 'stack', 'at rotinaDeTeste (qa.ts:111)'));
  v_b := public.registrar_evento_erro(jsonb_build_object(
    'mensagem', '[QA-CENTRAL3] falha no registro 999', 'modulo', 'QA',
    'tipo', 'QaTeste', 'stack', 'at rotinaDeTeste (qa.ts:999)'));

  SELECT ocorrencias INTO v_oc FROM public.evento_incidente
   WHERE fingerprint = v_b->>'fingerprint';

  IF (v_a->>'fingerprint') = (v_b->>'fingerprint') AND COALESCE(v_oc, 0) >= 2 THEN
    r.situacao := 'passou';
    r.obtido := 'Os dois erros caíram no mesmo incidente, com contador em ' || v_oc::text || '.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'Erros iguais geraram incidentes diferentes (' ||
                COALESCE(v_a->>'fingerprint','?') || ' x ' || COALESCE(v_b->>'fingerprint','?') || ').';
  END IF;
  r.detalhe := jsonb_build_object('primeiro', v_a, 'segundo', v_b, 'ocorrencias', v_oc);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_central_004()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_resposta jsonb;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Chamar a ingestao sem nenhuma sessao';
  r.esperado := 'Recusa com motivo sem_sessao, sem gravar nada';

  -- Sessao ausente: claims sem 'sub' (e como o PostgREST chega sem login).
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  v_resposta := public.registrar_evento_erro(
    jsonb_build_object('mensagem', '[QA-CENTRAL4] tentativa anonima', 'modulo', 'QA'));

  IF (v_resposta->>'gravado') = 'false' AND (v_resposta->>'motivo') = 'sem_sessao' THEN
    r.situacao := 'passou';
    r.obtido := 'Ingestao recusou evento sem sessao.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'Ingestao aceitou (ou recusou pelo motivo errado): ' || v_resposta::text;
  END IF;
  r.detalhe := v_resposta;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_central_005()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_uid uuid; v_pseudo text; v_email text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Gerar o apelido do usuario e comparar com o que identifica a pessoa';
  r.esperado := 'Apelido estavel, diferente do id e sem e-mail';

  SELECT user_id, email INTO v_uid, v_email FROM public.superadmins WHERE ativo LIMIT 1;
  IF v_uid IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Sem superadmin ativo para gerar o apelido.';
    RETURN r;
  END IF;

  v_pseudo := public.pseudonimo_usuario(v_uid);

  IF v_pseudo IS NOT NULL
     AND v_pseudo <> v_uid::text
     AND position(COALESCE(v_email, '@@') in v_pseudo) = 0
     AND v_pseudo = public.pseudonimo_usuario(v_uid) THEN
    r.situacao := 'passou';
    r.obtido := 'Usuario entra como apelido estavel, sem identificar a pessoa.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'O apelido nao protege a identidade do usuario.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;
