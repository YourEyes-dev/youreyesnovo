-- =========================================================
-- QA — perfis de acesso: leitura e escrita pelo perfil (passo 2.4)
--
--   PERFIL-040 (api, somente leitura)  as quatro tabelas de acesso (perfis_acesso, perfil_permissoes, perfil_excecoes,
--              usuario_perfil_vinculos) tem as 16 politicas RESTRICTIVE (leitura + inserir/alterar/excluir) e o usuario de
--              teste restrito (so Documentos) le no maximo o PROPRIO perfil e o proprio vinculo.
-- Idempotente: caso com ON CONFLICT (codigo) DO NOTHING; implementacao por upsert.
-- =========================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.qa_caso_perfil_040()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_n int;
  v_uid uuid;
  v_claims text;
  v_perfis bigint;
  v_vinc bigint;
  v_exc bigint;
  v_total_perfis bigint;
  v_meus_vinc bigint;
  v_meus_perfis bigint;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA + FUNCIONAL (somente leitura): quem ve e mexe em perfis e permissoes e decidido pelo perfil';
  r.esperado    := '16 politicas RESTRICTIVE nas 4 tabelas; usuario restrito le apenas o(s) proprio(s) perfil e vinculo(s)';

  v_n := (SELECT count(*) FROM pg_policies
           WHERE schemaname = 'public' AND permissive = 'RESTRICTIVE'
             AND tablename IN ('perfis_acesso','perfil_permissoes','perfil_excecoes','usuario_perfil_vinculos')
             AND policyname ~ '^perfil_restringe_(leitura|escrita)_');
  IF COALESCE(v_n, 0) < 16 THEN
    r.situacao := 'falhou';
    r.obtido   := 'FALHA GRAVE: so ' || COALESCE(v_n, 0) || ' de 16 travas por perfil nas tabelas de acesso.';
    RETURN r;
  END IF;

  v_uid := (SELECT ub.auth_user_id FROM public.usuarios_base ub WHERE ub.email_principal = 'restrito.e2e@youreyes.local' LIMIT 1);
  IF v_uid IS NULL OR to_regprocedure('qa_rls.conta_auth(text)') IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Travas conferidas (16). Falta a prova funcional: semear restrito.e2e@youreyes.local (seed-e2e-user) e ter os ajudantes qa_rls.';
    RETURN r;
  END IF;

  v_meus_vinc := (SELECT count(*) FROM public.usuario_perfil_vinculos v
                   JOIN public.usuarios_base ub ON ub.id = v.usuario_id WHERE ub.auth_user_id = v_uid);
  v_meus_perfis := (SELECT count(DISTINCT v.perfil_id) FROM public.usuario_perfil_vinculos v
                     JOIN public.usuarios_base ub ON ub.id = v.usuario_id WHERE ub.auth_user_id = v_uid);
  v_total_perfis := (xpath('/row/c/text()', query_to_xml('SELECT count(*) AS c FROM public.perfis_acesso', false, true, '')))[1]::text::bigint;
  v_claims := current_setting('request.jwt.claims', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  v_perfis := qa_rls.conta_auth('SELECT count(*) FROM public.perfis_acesso');
  v_vinc   := qa_rls.conta_auth('SELECT count(*) FROM public.usuario_perfil_vinculos');
  v_exc    := qa_rls.conta_auth('SELECT count(*) FROM public.perfil_excecoes');
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);

  IF COALESCE(v_perfis, 0) > COALESCE(v_meus_perfis, 0) OR COALESCE(v_vinc, 0) > COALESCE(v_meus_vinc, 0) THEN
    r.situacao := 'falhou';
    r.obtido   := 'FALHA GRAVE: o usuario restrito le ' || COALESCE(v_perfis, 0) || ' perfis e ' || COALESCE(v_vinc, 0) || ' vinculos (os dele sao ' || COALESCE(v_meus_perfis, 0) || ' e ' || COALESCE(v_meus_vinc, 0) || ').';
  ELSIF COALESCE(v_total_perfis, 0) <= COALESCE(v_meus_perfis, 0) THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Travas presentes, mas ha poucos perfis para provar o bloqueio.';
  ELSE
    r.situacao := 'passou';
    r.obtido   := 'Travas presentes; o usuario restrito le ' || v_perfis || ' de ' || v_total_perfis || ' perfis, ' || v_vinc || ' vinculo(s) e ' || COALESCE(v_exc, 0) || ' liberacao(oes).';
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
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; PERFIL-040 nao documentado.';
    RETURN;
  END IF;
  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PERFIL-040', 'Perfis de acesso: quem ve e quem altera perfis, permissoes, liberacoes e vinculos e decidido pelo perfil',
   'negativo', 'critica', 'aprovado', 'api', 'LGPD arts. 6º e 46',
   'As tabelas que dizem quem pode o que (perfis, permissoes, liberacoes e o perfil de cada pessoa) eram legiveis por qualquer membro da empresa e gravaveis por quem tivesse papel de administrador, sem olhar o perfil. Agora cada pessoa ve o proprio perfil, as permissoes dele e as proprias liberacoes (o app precisa para montar o menu); ve os de todos e altera quem tem, no perfil, os modulos Usuarios, Configuracoes ou Perfis & Acessos com o verbo criar/editar/excluir. Sem perfil vinculado vale o legado por papel.',
   'Script do passo 2.4 aplicado; usuario restrito semeado.',
   '[{"ordem":1,"acao":"Contar as politicas RESTRICTIVE perfil_restringe_leitura_* e perfil_restringe_escrita_* nas 4 tabelas","resultado_esperado":"16"},{"ordem":2,"acao":"Com o usuario restrito, contar perfis, vinculos e liberacoes visiveis","resultado_esperado":"No maximo o proprio"}]'::jsonb,
   'Perfil so e visto e alterado por quem o perfil autoriza.', 'Rotina qa_caso_perfil_040 (somente leitura). Limite: quem altera vinculos pode conceder a si mesmo um perfil maior; o criterio de quem pode conceder acesso segue em pode_gerir_acesso.')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
    VALUES ('PERFIL-040', 'qa_caso_perfil_040', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao PERFIL-040 nao registrada: %', SQLERRM;
END $doc$;

DO $roda$
BEGIN
  PERFORM public.qa_rodar_bateria('manual', 'seguranca-acesso/perfis');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bateria nao rodou agora (%). A rotina fica registrada e entra na proxima execucao.', SQLERRM;
END $roda$;
