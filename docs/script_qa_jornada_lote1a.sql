-- ============================================================================
-- ENTREGA — QA: caso PERFIL-028 (jornada lote 1a), DEPOIS do script_jornada_lote1a_leitura_por_perfil.sql
-- So dado de QA (rotina, caso e implementacao). Cole no SQL Editor.
-- ============================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.qa_caso_perfil_028()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_falhas text[] := ARRAY[]::text[];
  v_tab text;
  v_qual text;
  v_uid uuid;
  v_cpf text;
  v_claims text;
  v_visiveis bigint;
  v_proprias bigint;
  v_alheias_total bigint := 0;
  v_tabelas_com_dado int := 0;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA + FUNCIONAL (somente leitura): jornada so le a propria linha (ou o que o perfil amplo libera)';
  r.esperado    := 'As 13 tabelas com a trava de leitura por perfil; o usuario restrito enxerga so o proprio CPF';

  -- 1) Estrutura
  FOREACH v_tab IN ARRAY ARRAY['ponto_semanal','ponto_banco_horas','ponto_banco_horas_movimentacoes','ponto_ajustes',
      'ponto_links','ponto_acesso_sensivel_log','ponto_equalizacao_mensal','ponto_comprovantes','ponto_memoria_calculo',
      'ponto_compensacao_falta','ponto_pre_assinalacao','jornada_alertas','jornada_analises'] LOOP
    IF to_regclass('public.' || v_tab) IS NULL THEN
      CONTINUE;
    END IF;
    v_qual := (SELECT lower(COALESCE(qual, '')) FROM pg_policies
                WHERE schemaname = 'public' AND tablename = v_tab
                  AND policyname = 'perfil_restringe_leitura_' || v_tab AND permissive = 'RESTRICTIVE');
    IF v_qual IS NULL THEN
      v_falhas := v_falhas || ('falta a trava de leitura em ' || v_tab)::text;
    ELSIF v_qual !~ 'perfil_amplo_sem_subordinados' OR v_qual !~ 'cpf_do_usuario_logado' THEN
      v_falhas := v_falhas || ('a trava de ' || v_tab || ' nao consulta o perfil e o proprio CPF')::text;
    END IF;
  END LOOP;

  IF COALESCE(array_length(v_falhas, 1), 0) > 0 THEN
    r.situacao := 'falhou';
    r.obtido   := array_to_string(v_falhas, '; ');
    r.detalhe  := jsonb_build_object('falhas', to_jsonb(v_falhas));
    RETURN r;
  END IF;

  -- 2) Prova funcional com o usuario restrito
  -- Atribuicao por subconsulta escalar (o editor de SQL de producao confunde a forma curta com criacao de tabela; ver CLAUDE.md).
  v_uid := (SELECT ub.auth_user_id FROM public.usuarios_base ub
             WHERE ub.email_principal = 'restrito.e2e@youreyes.local' LIMIT 1);
  v_cpf := (SELECT regexp_replace(COALESCE(ub.cpf, ''), '[^0-9]', '', 'g') FROM public.usuarios_base ub
             WHERE ub.email_principal = 'restrito.e2e@youreyes.local' LIMIT 1);
  IF v_uid IS NULL OR COALESCE(v_cpf, '') = '' OR to_regprocedure('qa_rls.conta_auth(text)') IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Travas conferidas nas tabelas existentes. Falta a prova funcional: semear restrito.e2e@youreyes.local (seed-e2e-user) e ter os ajudantes qa_rls.';
    RETURN r;
  END IF;

  v_claims := current_setting('request.jwt.claims', true);
  FOREACH v_tab IN ARRAY ARRAY['ponto_semanal','ponto_banco_horas','ponto_banco_horas_movimentacoes','ponto_ajustes',
      'ponto_links','ponto_acesso_sensivel_log','ponto_equalizacao_mensal','ponto_comprovantes','ponto_memoria_calculo',
      'ponto_compensacao_falta','ponto_pre_assinalacao','jornada_alertas','jornada_analises'] LOOP
    IF to_regclass('public.' || v_tab) IS NULL THEN
      CONTINUE;
    END IF;
    v_visiveis := (xpath('/row/c/text()', query_to_xml(format(
        'SELECT count(*) AS c FROM public.%I WHERE regexp_replace(COALESCE(colaborador_cpf,''''),''[^0-9]'',''g'','''') <> %L',
        v_tab, v_cpf), false, true, '')))[1]::text::bigint;
    v_alheias_total := v_alheias_total + COALESCE(v_visiveis, 0);
    IF COALESCE(v_visiveis, 0) > 0 THEN v_tabelas_com_dado := v_tabelas_com_dado + 1; END IF;

    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
    v_visiveis := qa_rls.conta_auth(format('SELECT count(*) FROM public.%I', v_tab));
    PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
    v_proprias := (xpath('/row/c/text()', query_to_xml(format(
        'SELECT count(*) AS c FROM public.%I WHERE regexp_replace(COALESCE(colaborador_cpf,''''),''[^0-9]'',''g'','''') = %L',
        v_tab, v_cpf), false, true, '')))[1]::text::bigint;
    IF v_visiveis <> COALESCE(v_proprias, 0) THEN
      v_falhas := v_falhas || ('FALHA GRAVE em ' || v_tab || ': o usuario restrito ve ' || v_visiveis
                               || ' linhas e so ' || COALESCE(v_proprias, 0) || ' sao dele')::text;
    END IF;
  END LOOP;

  IF COALESCE(array_length(v_falhas, 1), 0) > 0 THEN
    r.situacao := 'falhou';
    r.obtido   := array_to_string(v_falhas, '; ');
    r.detalhe  := jsonb_build_object('falhas', to_jsonb(v_falhas));
  ELSIF v_alheias_total = 0 THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Travas presentes, mas nao ha linhas de outras pessoas nestas tabelas para provar o bloqueio. Semear dados de jornada de outro colaborador.';
  ELSE
    r.situacao := 'passou';
    r.obtido   := 'Travas presentes; o usuario restrito enxerga so o proprio CPF em ' || v_tabelas_com_dado
                  || ' tabela(s) que tem linhas de outras pessoas (' || v_alheias_total || ' linhas bloqueadas).';
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
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; PERFIL-028 nao documentado.';
    RETURN;
  END IF;
  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PERFIL-028', 'Dados de jornada por pessoa: so a propria linha ou o que o perfil de Ponto libera',
   'negativo', 'critica', 'aprovado', 'api', 'LGPD arts. 6º e 46',
   'Levantamento de 10/2026: 13 tabelas de jornada (banco de horas, ajustes, semanal, comprovantes, analises...) traziam o CPF do colaborador e podiam ser lidas por qualquer membro da empresa. Passam a seguir o mesmo portao de ponto_marcacoes e ponto_espelhos: perfil com Ponto/Colaboradores em escopo amplo ve tudo, o colaborador ve a propria linha (CPF) e o lider com escopo de subordinados ve a dele e a dos subordinados diretos.',
   'Lote 1a de jornada aplicado; usuario restrito semeado.',
   '[{"ordem":1,"acao":"Conferir a trava perfil_restringe_leitura_<tabela> (perfil amplo + proprio CPF) nas 13 tabelas","resultado_esperado":"Presente em todas as que existem"},{"ordem":2,"acao":"Com o usuario restrito (so Documentos), contar as linhas visíveis de cada tabela","resultado_esperado":"Igual ao numero de linhas do proprio CPF"}]'::jsonb,
   'Cada pessoa le so a propria jornada, salvo perfil amplo.', 'Rotina qa_caso_perfil_028 (somente leitura). Fora do lote 1a: ponto_alertas, ponto_escala_atribuicoes, ponto_troca_turno, ponto_acordos, ponto_lotacao_historico (lote 1b) e ponto_diario (leitura agregada).')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
    VALUES ('PERFIL-028', 'qa_caso_perfil_028', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao PERFIL-028 nao registrada: %', SQLERRM;
END $doc$;

DO $roda$
BEGIN
  PERFORM public.qa_rodar_bateria('manual', 'seguranca-acesso/perfis');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bateria nao rodou agora (%). A rotina fica registrada e entra na proxima execucao.', SQLERRM;
END $roda$;

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT (SELECT count(*) FROM public.qa_casos_teste WHERE codigo = 'PERFIL-028')       AS caso_documentado,
       (SELECT (public.qa_caso_perfil_028()).situacao)                                AS perfil_028,
       (SELECT (public.qa_caso_perfil_028()).obtido)                                  AS detalhe;
