-- ============================================================================
-- ENTREGA — QA: caso PERFIL-038 (funcoes de leitura do cadastro), DEPOIS do script_admissoes_funcoes_leitura.sql
-- So dado de QA (rotina, caso e implementacao). Cole no SQL Editor.
-- ============================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.qa_caso_perfil_038()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_falhas text[] := ARRAY[]::text[];
  v_fn text;
  v_uid uuid;
  v_claims text;
  v_lista bigint;
  v_cpfs bigint;
  v_emails bigint;
  v_celeb_ano bigint;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA + FUNCIONAL (somente leitura): funcoes de leitura do cadastro para quem nao e do RH';
  r.esperado    := 'Funcoes presentes (security definer); restrito recebe a lista de pessoas sem CPF/e-mail/celular alheios; celebracoes sem o ano';

  FOREACH v_fn IN ARRAY ARRAY['colaboradores_diretorio', 'celebracoes_pessoas', 'meu_time_admissoes',
                              'admissoes_contagens', 'admissoes_historico_status'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.proname = v_fn AND p.pronamespace = 'public'::regnamespace AND p.prosecdef) THEN
      v_falhas := v_falhas || ('falta a funcao ' || v_fn || ' como security definer')::text;
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.proname = 'ye_modulos_dados_pessoas' AND p.pronamespace = 'public'::regnamespace) THEN
    v_falhas := v_falhas || 'falta ye_modulos_dados_pessoas'::text;
  END IF;

  IF COALESCE(array_length(v_falhas, 1), 0) > 0 THEN
    r.situacao := 'falhou';
    r.obtido   := array_to_string(v_falhas, '; ');
    r.detalhe  := jsonb_build_object('falhas', to_jsonb(v_falhas));
    RETURN r;
  END IF;

  v_uid := (SELECT ub.auth_user_id FROM public.usuarios_base ub WHERE ub.email_principal = 'restrito.e2e@youreyes.local' LIMIT 1);
  IF v_uid IS NULL OR to_regprocedure('qa_rls.conta_auth(text)') IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Funcoes conferidas. Falta a prova funcional: semear restrito.e2e@youreyes.local (seed-e2e-user) e ter os ajudantes qa_rls.';
    RETURN r;
  END IF;

  v_claims := current_setting('request.jwt.claims', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  v_lista := qa_rls.conta_auth('SELECT count(*) FROM public.colaboradores_diretorio()');
  v_cpfs := qa_rls.conta_auth('SELECT count(*) FROM public.colaboradores_diretorio() WHERE cpf <> ''''');
  v_emails := qa_rls.conta_auth('SELECT count(*) FROM public.colaboradores_diretorio() WHERE email IS NOT NULL OR celular IS NOT NULL');
  v_celeb_ano := qa_rls.conta_auth('SELECT count(*) FROM public.celebracoes_pessoas() WHERE data_nascimento IS NOT NULL AND data_nascimento NOT LIKE ''2000-%''');
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);

  IF COALESCE(v_cpfs, 0) > 1 OR COALESCE(v_emails, 0) > 1 THEN
    v_falhas := v_falhas || ('FALHA GRAVE: o usuario restrito recebe ' || v_cpfs || ' CPFs e ' || v_emails || ' contatos pelo diretorio')::text;
  END IF;
  IF COALESCE(v_celeb_ano, 0) > 0 THEN
    v_falhas := v_falhas || ('as celebracoes devolvem o ano de nascimento de ' || v_celeb_ano || ' pessoas')::text;
  END IF;

  IF COALESCE(array_length(v_falhas, 1), 0) > 0 THEN
    r.situacao := 'falhou';
    r.obtido   := array_to_string(v_falhas, '; ');
    r.detalhe  := jsonb_build_object('falhas', to_jsonb(v_falhas));
  ELSIF COALESCE(v_lista, 0) <= 1 THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Funcoes presentes, mas o cercado tem poucas pessoas ativas para provar o mascaramento.';
  ELSE
    r.situacao := 'passou';
    r.obtido   := 'Funcoes presentes; o usuario restrito recebe ' || v_lista || ' pessoas no diretorio, com no maximo o proprio CPF/contato, e as celebracoes sem ano.';
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
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; PERFIL-038 nao documentado.';
    RETURN;
  END IF;
  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PERFIL-038', 'Cadastro de colaboradores: quem nao e do RH ve o diretorio de pessoas, sem CPF, contato nem ano de nascimento alheios',
   'negativo', 'critica', 'aprovado', 'api', 'LGPD arts. 6º e 46',
   'O cadastro (admissoes) era lido direto por quase todo o sistema, trazendo CPF, e-mail e celular de todos para telas sociais (mural, @mencao, PDI, trilhas). Agora essas telas leem funcoes do banco: o diretorio entrega nome, cargo, departamento, filial, gestor e foto a todos, e CPF/e-mail/celular so a propria pessoa, a quem tem acesso de gestao a dados de pessoas e ao lider (da equipe); as celebracoes saem sem o ano de nascimento; contagens e equipe do gestor tambem saem por funcao. Primeira parte do fechamento da leitura do cadastro.',
   'Script das funcoes de leitura do cadastro aplicado; usuario restrito semeado.',
   '[{"ordem":1,"acao":"Conferir as 5 funcoes security definer","resultado_esperado":"Presentes"},{"ordem":2,"acao":"Com o usuario restrito, listar o diretorio e as celebracoes","resultado_esperado":"No maximo o proprio CPF e contato; nascimento sempre com ano 2000"}]'::jsonb,
   'Todos veem quem e quem; so quem precisa ve os dados pessoais.', 'Rotina qa_caso_perfil_038 (somente leitura). A trava da tabela admissoes (parte 2) e documentada em caso proprio.')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
    VALUES ('PERFIL-038', 'qa_caso_perfil_038', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao PERFIL-038 nao registrada: %', SQLERRM;
END $doc$;

DO $roda$
BEGIN
  PERFORM public.qa_rodar_bateria('manual', 'seguranca-acesso/perfis');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bateria nao rodou agora (%). A rotina fica registrada e entra na proxima execucao.', SQLERRM;
END $roda$;

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT (SELECT count(*) FROM public.qa_casos_teste WHERE codigo = 'PERFIL-038')       AS caso_documentado,
       (SELECT (public.qa_caso_perfil_038()).situacao)                                AS perfil_038,
       (SELECT (public.qa_caso_perfil_038()).obtido)                                  AS detalhe;
