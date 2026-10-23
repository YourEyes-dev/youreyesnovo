-- ============================================================================
-- ENTREGA — QA: casos PERFIL-032 (tipo padrao) e PERFIL-033 (vinculos), DEPOIS dos dois scripts acima
-- So dado de QA (rotinas, casos e implementacoes). Cole no SQL Editor.
-- ============================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.qa_caso_perfil_032()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_falhas text[] := ARRAY[]::text[];
  v_def text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): o padrao de quem e criado sem tipo e o de menor acesso';
  r.esperado    := 'tipo_usuario e tipo_vinculo com padrao colaborador; modelo por tipo manda o desconhecido ao Colaborador padrao';

  v_def := (SELECT pg_get_expr(d.adbin, d.adrelid) FROM pg_attrdef d
             JOIN pg_attribute a ON a.attrelid = d.adrelid AND a.attnum = d.adnum
            WHERE d.adrelid = 'public.usuarios_base'::regclass AND a.attname = 'tipo_usuario');
  IF v_def IS NULL OR v_def !~ 'colaborador' THEN
    v_falhas := v_falhas || ('usuarios_base.tipo_usuario tem padrao ' || COALESCE(v_def, '(nenhum)'))::text;
  END IF;

  v_def := (SELECT pg_get_expr(d.adbin, d.adrelid) FROM pg_attrdef d
             JOIN pg_attribute a ON a.attrelid = d.adrelid AND a.attnum = d.adnum
            WHERE d.adrelid = 'public.usuario_vinculos'::regclass AND a.attname = 'tipo_vinculo');
  IF v_def IS NULL OR v_def !~ 'colaborador' THEN
    v_falhas := v_falhas || ('usuario_vinculos.tipo_vinculo tem padrao ' || COALESCE(v_def, '(nenhum)'))::text;
  END IF;

  v_def := (SELECT pg_get_functiondef(p.oid) FROM pg_proc p
             WHERE p.proname = 'perfil_modelo_para_tipo' AND p.pronamespace = 'public'::regnamespace LIMIT 1);
  IF v_def IS NULL OR v_def !~* 'ELSE\s+public\.perfil_padrao_colaborador' THEN
    v_falhas := v_falhas || 'perfil_modelo_para_tipo nao manda o tipo desconhecido ao Colaborador padrao'::text;
  END IF;

  IF COALESCE(array_length(v_falhas, 1), 0) > 0 THEN
    r.situacao := 'falhou';
    r.obtido   := array_to_string(v_falhas, '; ');
    r.detalhe  := jsonb_build_object('falhas', to_jsonb(v_falhas));
  ELSE
    r.situacao := 'passou';
    r.obtido   := 'Quem e criado sem tipo entra como colaborador (perfil Colaborador padrao).';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_perfil_033()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_falhas text[] := ARRAY[]::text[];
  v_nome text;
  v_uid uuid;
  v_ub uuid;
  v_claims text;
  v_visiveis bigint;
  v_proprias bigint;
  v_alheias bigint;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA + FUNCIONAL (somente leitura): vinculos de usuario pelo perfil';
  r.esperado    := 'Travas de leitura e escrita presentes; o usuario restrito ve so os proprios vinculos';

  FOREACH v_nome IN ARRAY ARRAY['perfil_restringe_leitura_usuario_vinculos','perfil_restringe_escrita_usuario_vinculos_ins','perfil_restringe_escrita_usuario_vinculos_upd'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'usuario_vinculos'
                    AND policyname = v_nome AND permissive = 'RESTRICTIVE') THEN
      v_falhas := v_falhas || ('falta a politica ' || v_nome)::text;
    END IF;
  END LOOP;

  IF COALESCE(array_length(v_falhas, 1), 0) > 0 THEN
    r.situacao := 'falhou';
    r.obtido   := array_to_string(v_falhas, '; ');
    r.detalhe  := jsonb_build_object('falhas', to_jsonb(v_falhas));
    RETURN r;
  END IF;

  v_uid := (SELECT ub.auth_user_id FROM public.usuarios_base ub WHERE ub.email_principal = 'restrito.e2e@youreyes.local' LIMIT 1);
  v_ub  := (SELECT ub.id FROM public.usuarios_base ub WHERE ub.email_principal = 'restrito.e2e@youreyes.local' LIMIT 1);
  IF v_uid IS NULL OR v_ub IS NULL OR to_regprocedure('qa_rls.conta_auth(text)') IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Travas conferidas. Falta a prova funcional: semear restrito.e2e@youreyes.local (seed-e2e-user) e ter os ajudantes qa_rls.';
    RETURN r;
  END IF;

  v_alheias := (xpath('/row/c/text()', query_to_xml(format(
      'SELECT count(*) AS c FROM public.usuario_vinculos WHERE usuario_id <> %L', v_ub), false, true, '')))[1]::text::bigint;
  v_claims := current_setting('request.jwt.claims', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  v_visiveis := qa_rls.conta_auth('SELECT count(*) FROM public.usuario_vinculos');
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  v_proprias := (xpath('/row/c/text()', query_to_xml(format(
      'SELECT count(*) AS c FROM public.usuario_vinculos WHERE usuario_id = %L', v_ub), false, true, '')))[1]::text::bigint;

  IF v_visiveis <> COALESCE(v_proprias, 0) THEN
    r.situacao := 'falhou';
    r.obtido   := 'FALHA GRAVE: o usuario restrito ve ' || v_visiveis || ' vinculos e so ' || COALESCE(v_proprias, 0) || ' sao dele';
  ELSIF COALESCE(v_alheias, 0) = 0 THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Travas presentes, mas nao ha vinculos de outras pessoas para provar o bloqueio.';
  ELSE
    r.situacao := 'passou';
    r.obtido   := 'Travas presentes; o usuario restrito ve so os proprios vinculos (' || v_alheias || ' de outras pessoas bloqueados).';
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
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; PERFIL-032/033 nao documentados.';
    RETURN;
  END IF;
  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PERFIL-032', 'Quem e criado sem tipo definido entra como colaborador (menor acesso)',
   'feliz', 'alta', 'aprovado', 'api', 'LGPD arts. 6º e 46',
   'O tipo padrao de usuario e de vinculo era gestor: quem criava um usuario sem escolher o tipo dava a ele o perfil Gestor (padrao), com acesso amplo, e o papel de gestao. Decisao do dono do produto: o padrao e colaborador (perfil Colaborador padrao, so autosservico) e o RH corrige depois. Vale para o formulario de Novo Usuario e para o padrao das colunas.',
   'Script de tipo padrao aplicado.',
   '[{"ordem":1,"acao":"Conferir o padrao das colunas usuarios_base.tipo_usuario e usuario_vinculos.tipo_vinculo","resultado_esperado":"colaborador"},{"ordem":2,"acao":"Conferir que perfil_modelo_para_tipo manda o tipo desconhecido ao Colaborador padrao","resultado_esperado":"Presente"}]'::jsonb,
   'Menos acesso por omissao.', 'Rotina qa_caso_perfil_032 (somente leitura). Linhas existentes nao mudam.'),
  (v_mod, 'PERFIL-033', 'Vinculos de usuario: so os proprios, salvo quem gere usuarios',
   'negativo', 'critica', 'aprovado', 'api', 'LGPD arts. 6º e 46',
   'usuario_vinculos define a quais empresas cada usuario tem acesso. Estava decidida so pela conta: qualquer membro lia, criava e alterava vinculos de qualquer pessoa, inclusive os proprios (um consultor externo podia ampliar sozinho as empresas que ve). Agora le o proprio vinculo, ou todos, para quem tem Usuarios/Configuracoes; cria e altera so quem tem esses modulos com o verbo criar/editar (quem pode cadastrar empresa vincula a si mesmo a empresa nova).',
   'Script de vinculos pelo perfil aplicado; usuario restrito semeado.',
   '[{"ordem":1,"acao":"Conferir as politicas RESTRICTIVE de leitura, INSERT e UPDATE em usuario_vinculos","resultado_esperado":"Presentes"},{"ordem":2,"acao":"Com o usuario restrito, contar os vinculos visiveis","resultado_esperado":"Igual aos proprios"}]'::jsonb,
   'Cada um ve so os proprios vinculos; so a gestao de usuarios os altera.', 'Rotina qa_caso_perfil_033 (somente leitura).')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
    VALUES ('PERFIL-032', 'qa_caso_perfil_032', true), ('PERFIL-033', 'qa_caso_perfil_033', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao PERFIL-032/033 nao registrada: %', SQLERRM;
END $doc$;

DO $roda$
BEGIN
  PERFORM public.qa_rodar_bateria('manual', 'seguranca-acesso/perfis');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bateria nao rodou agora (%). A rotina fica registrada e entra na proxima execucao.', SQLERRM;
END $roda$;

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT (SELECT count(*) FROM public.qa_casos_teste WHERE codigo IN ('PERFIL-032','PERFIL-033')) AS casos_documentados,
       (SELECT (public.qa_caso_perfil_032()).situacao)                                          AS perfil_032,
       (SELECT (public.qa_caso_perfil_033()).situacao)                                          AS perfil_033,
       (SELECT (public.qa_caso_perfil_033()).obtido)                                            AS detalhe_033;
