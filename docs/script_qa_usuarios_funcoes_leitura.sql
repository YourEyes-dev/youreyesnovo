-- ============================================================================
-- ENTREGA — QA: caso PERFIL-041 (diretorio de usuarios sem dado pessoal alheio), DEPOIS do script_usuarios_funcoes_leitura.sql
-- So dado de QA (rotina, caso e implementacao). Cole no SQL Editor.
-- ============================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.qa_caso_perfil_041()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_n int;
  v_uid uuid;
  v_claims text;
  v_lista bigint;
  v_emails bigint;
  v_cpfs bigint;
  v_tipos bigint;
  v_total bigint;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA + FUNCIONAL (somente leitura): diretorio de usuarios sem dado pessoal alheio';
  r.esperado    := 'Tres funcoes security definer; usuario restrito recebe a lista e no maximo o proprio e-mail, CPF e tipo';

  v_n := (SELECT count(*) FROM pg_proc p
           WHERE p.pronamespace = 'public'::regnamespace AND p.prosecdef
             AND p.proname IN ('usuarios_diretorio', 'usuario_por_cpf', 'usuarios_contar_por_cargo'));
  IF COALESCE(v_n, 0) < 3 THEN
    r.situacao := 'falhou';
    r.obtido   := 'FALHA GRAVE: so ' || COALESCE(v_n, 0) || ' de 3 funcoes do diretorio de usuarios (security definer).';
    RETURN r;
  END IF;

  v_uid := (SELECT ub.auth_user_id FROM public.usuarios_base ub WHERE ub.email_principal = 'restrito.e2e@youreyes.local' LIMIT 1);
  IF v_uid IS NULL OR to_regprocedure('qa_rls.conta_auth(text)') IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Funcoes conferidas (3). Falta a prova funcional: semear restrito.e2e@youreyes.local (seed-e2e-user) e ter os ajudantes qa_rls.';
    RETURN r;
  END IF;

  v_total := (SELECT count(*) FROM public.usuarios_base ub WHERE ub.tenant_id = (SELECT tenant_id FROM public.usuarios_base WHERE auth_user_id = v_uid LIMIT 1));
  v_claims := current_setting('request.jwt.claims', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  v_lista  := qa_rls.conta_auth('SELECT count(*) FROM public.usuarios_diretorio()');
  v_emails := qa_rls.conta_auth('SELECT count(email_principal) FROM public.usuarios_diretorio()');
  v_cpfs   := qa_rls.conta_auth('SELECT count(*) FROM public.usuarios_diretorio() WHERE length(COALESCE(cpf, chr(32))) > 1');
  v_tipos  := qa_rls.conta_auth('SELECT count(tipo_usuario) FROM public.usuarios_diretorio()');
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);

  IF COALESCE(v_emails, 0) > 1 OR COALESCE(v_cpfs, 0) > 1 OR COALESCE(v_tipos, 0) > 1 THEN
    r.situacao := 'falhou';
    r.obtido   := 'FALHA GRAVE: o usuario restrito recebe ' || COALESCE(v_emails, 0) || ' e-mails, ' || COALESCE(v_cpfs, 0) || ' CPFs e ' || COALESCE(v_tipos, 0) || ' tipos pelo diretorio (deveria ser no maximo o proprio).';
  ELSIF COALESCE(v_total, 0) <= 1 THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Funcoes presentes, mas ha poucos usuarios para provar o bloqueio.';
  ELSE
    r.situacao := 'passou';
    r.obtido   := 'Diretorio com ' || COALESCE(v_lista, 0) || ' usuarios; o usuario restrito recebe ' || COALESCE(v_emails, 0) || ' e-mail(s) e ' || COALESCE(v_cpfs, 0) || ' CPF(s) (os dele).';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  BEGIN PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); EXCEPTION WHEN OTHERS THEN NULL; END;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $$;

DO $doc$
DECLARE v_mod uuid;
BEGIN
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'seguranca-acesso/perfis' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; PERFIL-041 nao documentado.';
    RETURN;
  END IF;
  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PERFIL-041', 'Cadastro de usuarios: o diretorio de usuarios nao entrega e-mail, CPF, tipo nem status de colegas a quem nao tem acesso amplo',
   'negativo', 'critica', 'aprovado', 'api', 'LGPD arts. 6º, 11 e 46',
   'A tabela usuarios_base (nome, e-mail, CPF, telefone, tipo, status, convite) e lida hoje por qualquer membro da empresa. Antes de fecha-la, as telas que so escolhem uma pessoa (gestor, responsavel da Ouvidoria) passam a usar usuarios_diretorio(), que devolve nome, foto e cargo dos usuarios ativos e so entrega e-mail, CPF, tipo e status da propria pessoa e de quem tem acesso amplo a dados de pessoas. usuario_por_cpf (Admissao) e usuarios_contar_por_cargo (excluir cargo) completam o conjunto.',
   'Script do passo 2.5 parte 1 aplicado; usuario restrito semeado.',
   '[{"ordem":1,"acao":"Conferir as tres funcoes (usuarios_diretorio, usuario_por_cpf, usuarios_contar_por_cargo)","resultado_esperado":"Presentes e security definer"},{"ordem":2,"acao":"Com o usuario restrito, chamar usuarios_diretorio() e contar e-mails e CPFs preenchidos","resultado_esperado":"No maximo o proprio; a lista de nomes completa"}]'::jsonb,
   'Seletor de pessoas sem expor dado pessoal alheio.', 'Rotina qa_caso_perfil_041 (somente leitura).')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
    VALUES ('PERFIL-041', 'qa_caso_perfil_041', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao PERFIL-041 nao registrada: %', SQLERRM;
END $doc$;

DO $roda$
BEGIN
  PERFORM public.qa_rodar_bateria('manual', 'seguranca-acesso/perfis');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bateria nao rodou agora (%). A rotina fica registrada e entra na proxima execucao.', SQLERRM;
END $roda$;

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT (SELECT count(*) FROM public.qa_casos_teste WHERE codigo = 'PERFIL-041') AS caso_documentado,
       (SELECT (public.qa_caso_perfil_041()).situacao)                          AS perfil_041,
       (SELECT (public.qa_caso_perfil_041()).obtido)                            AS detalhe;
