-- ============================================================================
-- ENTREGA — QA: caso PERFIL-042 (cadastro de usuarios fechado e sem autopromocao), DEPOIS do script_usuarios_base_trava.sql
-- So dado de QA (rotina, caso e implementacao). Cole no SQL Editor.
-- ============================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.qa_caso_perfil_042()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_n int;
  v_trg int;
  v_uid uuid;
  v_claims text;
  v_visiveis bigint;
  v_diretorio bigint;
  v_total bigint;
  v_linhas int;
  v_promoveu boolean := false;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA + FUNCIONAL (somente leitura): cadastro de usuarios fechado e sem autopromocao';
  r.esperado    := '3 politicas RESTRICTIVE + gatilho; restrito le no maximo a propria linha, recebe o diretorio e nao muda o proprio tipo';

  v_n := (SELECT count(*) FROM pg_policies
           WHERE schemaname = 'public' AND tablename = 'usuarios_base' AND permissive = 'RESTRICTIVE'
             AND policyname IN ('perfil_restringe_leitura_usuarios_base', 'perfil_restringe_escrita_usuarios_base_ins',
                                'perfil_restringe_escrita_usuarios_base_upd'));
  v_trg := (SELECT count(*) FROM pg_trigger t WHERE t.tgrelid = 'public.usuarios_base'::regclass
             AND t.tgname = 'trg_usuarios_base_protege' AND NOT t.tgisinternal);
  IF COALESCE(v_n, 0) < 3 OR COALESCE(v_trg, 0) < 1 THEN
    r.situacao := 'falhou';
    r.obtido   := 'FALHA GRAVE: usuarios_base com ' || COALESCE(v_n, 0) || ' de 3 politicas por perfil e ' || COALESCE(v_trg, 0) || ' de 1 gatilho de protecao.';
    RETURN r;
  END IF;

  v_uid := (SELECT ub.auth_user_id FROM public.usuarios_base ub WHERE ub.email_principal = 'restrito.e2e@youreyes.local' LIMIT 1);
  IF v_uid IS NULL OR to_regprocedure('qa_rls.conta_auth(text)') IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Travas conferidas. Falta a prova funcional: semear restrito.e2e@youreyes.local (seed-e2e-user) e ter os ajudantes qa_rls.';
    RETURN r;
  END IF;

  v_total := (SELECT count(*) FROM public.usuarios_base ub WHERE ub.tenant_id = (SELECT tenant_id FROM public.usuarios_base WHERE auth_user_id = v_uid LIMIT 1));
  v_claims := current_setting('request.jwt.claims', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  v_visiveis  := qa_rls.conta_auth('SELECT count(*) FROM public.usuarios_base');
  v_diretorio := qa_rls.conta_auth('SELECT count(*) FROM public.usuarios_diretorio()');

  -- tentativa de autopromocao: precisa ser recusada; se passar, a alteracao e desfeita pelo proprio bloco
  BEGIN
    SET LOCAL ROLE authenticated;
    UPDATE public.usuarios_base SET tipo_usuario = 'administrador' WHERE auth_user_id = v_uid;
    GET DIAGNOSTICS v_linhas = ROW_COUNT;
    RESET ROLE;
    v_promoveu := COALESCE(v_linhas, 0) > 0;
    RAISE EXCEPTION 'desfaz';
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);

  IF COALESCE(v_visiveis, 0) > 1 THEN
    r.situacao := 'falhou';
    r.obtido   := 'FALHA GRAVE: o usuario restrito le ' || v_visiveis || ' linhas do cadastro de usuarios (deveria ler no maximo a propria).';
  ELSIF v_promoveu THEN
    r.situacao := 'falhou';
    r.obtido   := 'FALHA GRAVE: o usuario restrito conseguiu alterar o proprio tipo de usuario (autopromocao).';
  ELSIF COALESCE(v_total, 0) <= 1 THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Travas presentes, mas ha poucos usuarios para provar o bloqueio.';
  ELSE
    r.situacao := 'passou';
    r.obtido   := 'Travas presentes; o usuario restrito le ' || v_visiveis || ' de ' || v_total || ' usuarios, recebe ' || COALESCE(v_diretorio, 0) || ' no diretorio e nao muda o proprio tipo.';
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
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; PERFIL-042 nao documentado.';
    RETURN;
  END IF;
  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PERFIL-042', 'Cadastro de usuarios: a ficha de usuarios so para a propria pessoa ou quem gere usuarios, e ninguem se autopromove',
   'negativo', 'critica', 'aprovado', 'api', 'LGPD arts. 6º, 11 e 46',
   'A tabela usuarios_base era legivel por qualquer membro da empresa e alteravel em qualquer linha, inclusive o proprio tipo (colaborador para administrador), o status e a empresa. Agora le a propria linha ou quem tem Usuarios, Configuracoes ou Perfis & Acessos; insere e altera outras linhas quem tem Usuarios/Configuracoes com o verbo criar/editar; e um gatilho impede qualquer pessoa (menos o dono da empresa e o Super Admin) de trocar na propria linha o tipo, o status, o CPF, o e-mail, a conta de login ou o convite, e de trocar a empresa de uma linha. Seletores usam usuarios_diretorio().',
   'Scripts do passo 2.5 (partes 1 e 2) aplicados; usuario restrito semeado.',
   '[{"ordem":1,"acao":"Conferir as politicas RESTRICTIVE de leitura, insercao e alteracao e o gatilho de protecao em usuarios_base","resultado_esperado":"Presentes"},{"ordem":2,"acao":"Com o usuario restrito, contar as linhas de usuarios_base visiveis e tentar alterar o proprio tipo","resultado_esperado":"No maximo 1 linha; a alteracao do tipo e recusada"}]'::jsonb,
   'Cadastro de usuarios lido e alterado so por quem o perfil autoriza; sem autopromocao.', 'Rotina qa_caso_perfil_042 (somente leitura: a tentativa de alteracao e desfeita).')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
    VALUES ('PERFIL-042', 'qa_caso_perfil_042', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao PERFIL-042 nao registrada: %', SQLERRM;
END $doc$;

DO $roda$
BEGIN
  PERFORM public.qa_rodar_bateria('manual', 'seguranca-acesso/perfis');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bateria nao rodou agora (%). A rotina fica registrada e entra na proxima execucao.', SQLERRM;
END $roda$;

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT (SELECT count(*) FROM public.qa_casos_teste WHERE codigo = 'PERFIL-042') AS caso_documentado,
       (SELECT (public.qa_caso_perfil_042()).situacao)                          AS perfil_042,
       (SELECT (public.qa_caso_perfil_042()).obtido)                            AS detalhe;
