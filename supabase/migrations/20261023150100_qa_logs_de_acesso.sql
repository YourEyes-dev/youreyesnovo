-- =========================================================
-- QA — trilhas de auditoria de usuarios e perfis
--
--   PERFIL-034 (api, somente leitura)  usuario_audit_log, perfil_audit_log e perfil_acesso_sensivel_log tem as
--              travas RESTRICTIVE de leitura e de INSERT por perfil, UPDATE/DELETE negados ao navegador e o
--              gatilho que carimba o autor; e, com o usuario de teste restrito (so Documentos), ele nao le
--              nenhuma linha das trilhas.
-- Idempotente: caso com ON CONFLICT (codigo) DO NOTHING; implementacao por upsert.
-- =========================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.qa_caso_perfil_034()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_falhas text[] := ARRAY[]::text[];
  v_tab text;
  v_pol text;
  v_uid uuid;
  v_claims text;
  v_visiveis bigint;
  v_total bigint := 0;
  v_n bigint;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA + FUNCIONAL (somente leitura): as trilhas de usuarios e perfis obedecem ao perfil';
  r.esperado    := 'Travas de leitura, INSERT, UPDATE e DELETE e gatilho do autor nas 3 trilhas; usuario restrito nao le nenhuma linha';

  FOREACH v_tab IN ARRAY ARRAY['usuario_audit_log','perfil_audit_log','perfil_acesso_sensivel_log'] LOOP
    IF to_regclass('public.' || v_tab) IS NULL THEN
      CONTINUE;
    END IF;
    FOREACH v_pol IN ARRAY ARRAY['perfil_restringe_leitura_' || v_tab, 'perfil_restringe_escrita_' || v_tab || '_ins',
                                 'log_imutavel_' || v_tab || '_upd', 'log_imutavel_' || v_tab || '_del'] LOOP
      IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = v_tab
                      AND policyname = v_pol AND permissive = 'RESTRICTIVE') THEN
        v_falhas := v_falhas || ('falta a politica ' || v_pol)::text;
      END IF;
    END LOOP;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = ('public.' || v_tab)::regclass
                    AND t.tgname = 'trg_audit_carimba_autor' AND NOT t.tgisinternal AND t.tgenabled <> 'D') THEN
      v_falhas := v_falhas || ('falta o gatilho que carimba o autor em ' || v_tab)::text;
    END IF;
  END LOOP;

  IF COALESCE(array_length(v_falhas, 1), 0) > 0 THEN
    r.situacao := 'falhou';
    r.obtido   := array_to_string(v_falhas, '; ');
    r.detalhe  := jsonb_build_object('falhas', to_jsonb(v_falhas));
    RETURN r;
  END IF;

  v_uid := (SELECT ub.auth_user_id FROM public.usuarios_base ub WHERE ub.email_principal = 'restrito.e2e@youreyes.local' LIMIT 1);
  IF v_uid IS NULL OR to_regprocedure('qa_rls.conta_auth(text)') IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Travas conferidas. Falta a prova funcional: semear restrito.e2e@youreyes.local (seed-e2e-user) e ter os ajudantes qa_rls.';
    RETURN r;
  END IF;

  v_claims := current_setting('request.jwt.claims', true);
  FOREACH v_tab IN ARRAY ARRAY['usuario_audit_log','perfil_audit_log','perfil_acesso_sensivel_log'] LOOP
    IF to_regclass('public.' || v_tab) IS NULL THEN
      CONTINUE;
    END IF;
    v_n := (xpath('/row/c/text()', query_to_xml(format('SELECT count(*) AS c FROM public.%I', v_tab), false, true, '')))[1]::text::bigint;
    v_total := v_total + COALESCE(v_n, 0);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
    v_visiveis := qa_rls.conta_auth(format('SELECT count(*) FROM public.%I', v_tab));
    PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
    IF COALESCE(v_visiveis, 0) <> 0 THEN
      v_falhas := v_falhas || ('FALHA GRAVE: o usuario restrito le ' || v_visiveis || ' linhas de ' || v_tab)::text;
    END IF;
  END LOOP;

  IF COALESCE(array_length(v_falhas, 1), 0) > 0 THEN
    r.situacao := 'falhou';
    r.obtido   := array_to_string(v_falhas, '; ');
    r.detalhe  := jsonb_build_object('falhas', to_jsonb(v_falhas));
  ELSIF v_total = 0 THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Travas presentes, mas as trilhas estao vazias; nao ha o que bloquear para provar.';
  ELSE
    r.situacao := 'passou';
    r.obtido   := 'Travas presentes; o usuario restrito nao le nenhuma das ' || v_total || ' linhas das trilhas.';
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
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; PERFIL-034 nao documentado.';
    RETURN;
  END IF;
  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PERFIL-034', 'Trilhas de auditoria de usuarios e perfis: so quem administra acessos le, e o autor vem do banco',
   'negativo', 'critica', 'aprovado', 'api', 'LGPD arts. 6º e 46',
   'As trilhas de usuarios e de perfis (usuario_audit_log, perfil_audit_log, perfil_acesso_sensivel_log) podiam ser lidas por qualquer membro da empresa (os valores trazem CPF, e-mail, tipo e perfil de cada pessoa) e qualquer membro podia gravar linhas, com o autor informado pelo navegador. Agora: leitura so para quem tem Usuarios, Perfis & Acessos ou Configuracoes em escopo amplo; gravacao so de quem tem esses modulos com verbo de escrita; autor e hora carimbados pelo banco; alterar ou apagar linha so pelas rotinas do sistema.',
   'Script das trilhas aplicado; usuario restrito semeado.',
   '[{"ordem":1,"acao":"Conferir as politicas RESTRICTIVE de leitura, INSERT, UPDATE e DELETE e o gatilho do autor nas 3 trilhas","resultado_esperado":"Presentes"},{"ordem":2,"acao":"Com o usuario restrito (so Documentos), contar as linhas visiveis das trilhas","resultado_esperado":"Zero"}]'::jsonb,
   'Trilha lida so por quem administra acessos; ninguem forja nem apaga.', 'Rotina qa_caso_perfil_034 (somente leitura).')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
    VALUES ('PERFIL-034', 'qa_caso_perfil_034', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao PERFIL-034 nao registrada: %', SQLERRM;
END $doc$;

DO $roda$
BEGIN
  PERFORM public.qa_rodar_bateria('manual', 'seguranca-acesso/perfis');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bateria nao rodou agora (%). A rotina fica registrada e entra na proxima execucao.', SQLERRM;
END $roda$;
