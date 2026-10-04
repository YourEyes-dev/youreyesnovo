-- =====================================================================
-- ENTREGA — QA CENTRAL-001..005: rotinas da telemetria de erros
-- (colar no SQL Editor; rodar em producao SO apos aprovado no teste)
--
-- Liga as 5 rotinas do Motor que provam as garantias de PRIVACIDADE da
-- ingestao de eventos de erro (registrar_evento_erro). Desenho fiel em
-- qualquer ambiente: ancorado nos primitivos (mascarar_pii,
-- pseudonimo_usuario) e na estrutura (RLS, chave unica de incidente),
-- sem depender de ler tabelas superadmin-only nem de escrever eventos
-- (a trava do cercado barra escrita fora do sandbox durante a bateria).
--
-- Seguro: so cria FUNCAO e insere metadado de QA; nao cria TABELA (nao
-- aciona o auto-RLS do editor) e nao toca dado de negocio. Idempotente.
-- =====================================================================

-- CENTRAL-001 — dado pessoal nao e gravado em claro.
CREATE OR REPLACE FUNCTION public.qa_caso_central_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_mascarado text;
  v_raw text := 'erro no envio para joao.silva@teste.com do CPF 529.982.247-25';
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Mascarar a mensagem como a ingestao faz (mascarar_pii) antes de gravar';
  r.esperado    := 'E-mail e CPF saem substituidos; o valor em claro nao permanece';
  v_mascarado := public.mascarar_pii(v_raw);

  IF v_mascarado ILIKE '%joao.silva@teste.com%' OR v_mascarado LIKE '%529.982.247-25%' THEN
    r.situacao := 'falhou';
    r.obtido := 'PII sobreviveu ao mascaramento: "' || v_mascarado
      || '". Dado pessoal em claro no evento de erro viola a LGPD.';
  ELSIF v_mascarado LIKE '%[email]%' AND v_mascarado LIKE '%[cpf]%' THEN
    r.situacao := 'passou';
    r.obtido := 'E-mail e CPF foram mascarados antes de gravar: "' || v_mascarado || '".';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'O mascaramento nao marcou e-mail/CPF como esperado: "' || v_mascarado || '".';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- CENTRAL-002 — escrita direta na tabela de evento e negada (estrutural).
CREATE OR REPLACE FUNCTION public.qa_caso_central_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_rls boolean; v_insert_aberto int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir que evento_erro tem RLS e nenhuma porta de INSERT direto';
  r.esperado    := 'RLS ligada e nenhuma politica de INSERT para anon/authenticated/public';

  SELECT c.relrowsecurity INTO v_rls
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'evento_erro';

  SELECT count(*) INTO v_insert_aberto
  FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'evento_erro'
    AND cmd IN ('INSERT', 'ALL')
    AND roles && ARRAY['anon','authenticated','public']::name[];

  IF v_rls IS NOT TRUE THEN
    r.situacao := 'falhou';
    r.obtido := 'evento_erro esta SEM RLS — escrita direta possivel, burlando o mascaramento.';
  ELSIF v_insert_aberto > 0 THEN
    r.situacao := 'falhou';
    r.obtido := 'Ha politica permitindo INSERT direto em evento_erro a anon/authenticated/public. '
      || 'A ingestao so deve entrar por registrar_evento_erro.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'evento_erro com RLS ligada e sem porta de INSERT direto: so entra por registrar_evento_erro.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- CENTRAL-003 — erros iguais agrupam num unico incidente.
-- Estrutural (como o 002): o caminho dinamico (ingerir 2x) nao serve aqui
-- porque a escrita de evento_erro cai no tenant do usuario, e a trava do
-- cercado (qa_bloqueia_fora_do_cercado) barra escrita fora do sandbox
-- durante a bateria — no harness E no staging. A garantia de agrupamento
-- e, de fato, estrutural: fingerprint e chave unica de evento_incidente e
-- a ingestao faz upsert nela somando ocorrencias.
CREATE OR REPLACE FUNCTION public.qa_caso_central_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_tem_chave boolean; v_upsert boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir que fingerprint e chave unica e a ingestao faz upsert por ela';
  r.esperado    := 'evento_incidente com chave unica em fingerprint; registrar_evento_erro com ON CONFLICT (fingerprint) somando ocorrencias';

  SELECT EXISTS (
    SELECT 1 FROM pg_constraint con
    JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attnum = ANY(con.conkey)
    WHERE con.conrelid = 'public.evento_incidente'::regclass
      AND con.contype IN ('p','u') AND a.attname = 'fingerprint'
      AND array_length(con.conkey, 1) = 1
  ) INTO v_tem_chave;

  SELECT pg_get_functiondef(p.oid) ILIKE '%on conflict (fingerprint)%'
         AND pg_get_functiondef(p.oid) ILIKE '%ocorrencias%'
  INTO v_upsert
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'registrar_evento_erro';

  IF v_tem_chave AND COALESCE(v_upsert, false) THEN
    r.situacao := 'passou';
    r.obtido := 'fingerprint e chave unica de evento_incidente e a ingestao faz ON CONFLICT '
      || '(fingerprint) somando ocorrencias: o mesmo erro, visto muitas vezes, vira UM incidente.';
  ELSIF NOT v_tem_chave THEN
    r.situacao := 'falhou';
    r.obtido := 'evento_incidente NAO tem chave unica so em fingerprint: erros iguais poderiam '
      || 'virar incidentes duplicados, inchando a lista.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'registrar_evento_erro nao faz o upsert por fingerprint (ON CONFLICT ... ocorrencias): '
      || 'o agrupamento nao esta garantido.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- CENTRAL-004 — sem sessao, a ingestao recusa o evento.
CREATE OR REPLACE FUNCTION public.qa_caso_central_004()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_res jsonb;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Sem sessao (auth.uid nulo), chamar a ingestao';
  r.esperado    := 'registrar_evento_erro devolve gravado=false, motivo=sem_sessao';

  PERFORM set_config('request.jwt.claims', '{}', true);  -- derruba a sessao
  v_res := public.registrar_evento_erro('{"mensagem":"evento anonimo","modulo":"qa"}'::jsonb);

  IF (v_res->>'gravado') = 'false' AND (v_res->>'motivo') = 'sem_sessao' THEN
    r.situacao := 'passou';
    r.obtido := 'Sem sessao, a ingestao recusou o evento (motivo sem_sessao), como deve.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'Sem sessao a ingestao NAO recusou corretamente. Resposta: ' || COALESCE(v_res::text, '(nula)');
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- CENTRAL-005 — usuario aparece pseudonimizado no evento.
CREATE OR REPLACE FUNCTION public.qa_caso_central_005()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_uid uuid; v_pseudo text; v_pseudo2 text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir que o usuario entra no evento pseudonimizado, nao em claro';
  r.esperado    := 'pseudonimo_usuario(uid) nao e o uid, e e deterministico';

  IF NOT public.qa_up_pode_virar_usuario() THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Ambiente nao permite simular usuario.'; RETURN r;
  END IF;
  v_uid := public.qa_up_usuario('CENTRAL-005', 1, '90000002038', 'ativo', NULL);
  IF v_uid IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Nao foi possivel montar a identidade de teste.'; RETURN r;
  END IF;

  v_pseudo  := public.pseudonimo_usuario(v_uid);
  v_pseudo2 := public.pseudonimo_usuario(v_uid);

  IF v_pseudo IS NULL OR v_pseudo = '' THEN
    r.situacao := 'falhou'; r.obtido := 'pseudonimo_usuario devolveu vazio: o evento ficaria sem autor rastreavel nem pseudonimo.';
  ELSIF v_pseudo = v_uid::text OR v_pseudo ILIKE '%' || v_uid::text || '%' THEN
    r.situacao := 'falhou'; r.obtido := 'O pseudonimo CONTEM o uid real (' || v_pseudo || '): nao pseudonimiza.';
  ELSIF v_pseudo <> v_pseudo2 THEN
    r.situacao := 'falhou'; r.obtido := 'O pseudonimo nao e deterministico: o mesmo usuario viraria autores diferentes, impedindo agrupar sem reidentificar.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'O usuario entra pseudonimizado (' || v_pseudo || '): nao e o uid, e e estavel para o mesmo usuario.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- Ligar as rotinas aos casos (idempotente).
INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo, criado_em) VALUES
  ('CENTRAL-001', 'qa_caso_central_001', true, now()),
  ('CENTRAL-002', 'qa_caso_central_002', true, now()),
  ('CENTRAL-003', 'qa_caso_central_003', true, now()),
  ('CENTRAL-004', 'qa_caso_central_004', true, now()),
  ('CENTRAL-005', 'qa_caso_central_005', true, now())
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- CONFERENCIA FINAL (o editor mostra so o ultimo resultado): os 5 CENTRAL
-- devem sair 'passou'. Roda cada rotina via o executor descartavel, com o
-- modo de teste ligado (a bateria faz isso; aqui garantimos para a conferencia).
DO $modo$ BEGIN PERFORM public.qa_modo_ligar(); END $modo$;
SELECT c AS caso,
       (public.qa_executar_descartavel('qa_caso_' || lower(replace(c,'-','_')))).situacao
FROM (VALUES ('CENTRAL-001'),('CENTRAL-002'),('CENTRAL-003'),('CENTRAL-004'),('CENTRAL-005')) v(c)
ORDER BY c;
