-- ============================================================================
-- ENTREGA — QA: caso PERFIL-030 (jornada, escrita pelo perfil), DEPOIS do script_jornada_escrita_por_perfil.sql
-- So dado de QA (rotina, caso e implementacao). Cole no SQL Editor.
-- ============================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.qa_caso_perfil_030()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_falhas text[] := ARRAY[]::text[];
  v_tab text;
  v_cmd text;
  v_nome text;
  v_fn text;
  v_uid uuid;
  v_tenant uuid;
  v_claims text;
  v_pode_criar boolean;
  v_pode_excluir boolean;
  v_pode_modulo boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA + FUNCIONAL (somente leitura): a escrita da jornada obedece ao perfil';
  r.esperado    := 'As 18 tabelas com travas RESTRICTIVE de INSERT, UPDATE e DELETE; gatilhos de atestado por conta do sistema; usuario restrito sem escrita no Ponto';

  -- 1) Estrutura: tres travas por tabela
  FOREACH v_tab IN ARRAY ARRAY['ponto_banco_horas','ponto_banco_horas_movimentacoes','ponto_links','ponto_pre_assinalacao',
      'ponto_escala_atribuicoes','ponto_acordos','jornada_alertas','jornada_analises','ponto_troca_turno','ponto_alertas',
      'ponto_ajustes','ponto_semanal','ponto_equalizacao_mensal','ponto_comprovantes','ponto_memoria_calculo',
      'ponto_compensacao_falta','ponto_lotacao_historico','ponto_acesso_sensivel_log'] LOOP
    IF to_regclass('public.' || v_tab) IS NULL THEN
      CONTINUE;
    END IF;
    FOREACH v_cmd IN ARRAY ARRAY['INSERT','UPDATE','DELETE'] LOOP
      IF NOT EXISTS (SELECT 1 FROM pg_policies
                      WHERE schemaname = 'public' AND tablename = v_tab AND permissive = 'RESTRICTIVE'
                        AND cmd = v_cmd
                        AND (policyname LIKE 'perfil_restringe_escrita_%' OR policyname LIKE 'escrita_so_dono_%')) THEN
        v_falhas := v_falhas || ('falta a trava de ' || v_cmd || ' em ' || v_tab)::text;
      END IF;
    END LOOP;
  END LOOP;

  -- 2) Gatilhos de atestado gravam por conta do sistema
  FOREACH v_fn IN ARRAY ARRAY['public.ponto_atestado_detectar_sobreposicao()','public.ponto_atestado_encaminhar_afastamento()'] LOOP
    IF to_regprocedure(v_fn) IS NOT NULL THEN
      IF NOT (SELECT p.prosecdef FROM pg_proc p WHERE p.oid = to_regprocedure(v_fn)) THEN
        v_falhas := v_falhas || (v_fn || ' voltou a rodar com o direito de quem registra o atestado')::text;
      END IF;
    END IF;
  END LOOP;

  IF COALESCE(array_length(v_falhas, 1), 0) > 0 THEN
    r.situacao := 'falhou';
    r.obtido   := array_to_string(v_falhas, '; ');
    r.detalhe  := jsonb_build_object('falhas', to_jsonb(v_falhas));
    RETURN r;
  END IF;

  -- 3) Prova funcional com o usuario restrito (atribuicao por subconsulta escalar; ver CLAUDE.md)
  v_uid := (SELECT ub.auth_user_id FROM public.usuarios_base ub
             WHERE ub.email_principal = 'restrito.e2e@youreyes.local' LIMIT 1);
  v_tenant := (SELECT ub.tenant_id FROM public.usuarios_base ub
                WHERE ub.email_principal = 'restrito.e2e@youreyes.local' LIMIT 1);
  IF v_uid IS NULL OR v_tenant IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Travas conferidas nas tabelas existentes. Falta a prova funcional: semear restrito.e2e@youreyes.local (seed-e2e-user).';
    RETURN r;
  END IF;

  v_claims := current_setting('request.jwt.claims', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  BEGIN
    v_pode_criar   := public.perfil_escreve(v_tenant, ARRAY['ponto','colaboradores'], ARRAY['criar'], NULL);
    v_pode_excluir := public.perfil_escreve(v_tenant, ARRAY['ponto','colaboradores'], ARRAY['excluir'], NULL);
    v_pode_modulo  := public.perfil_permite_modulo(v_tenant, VARIADIC ARRAY['ponto','colaboradores']);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
    RAISE;
  END;
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);

  IF v_pode_criar IS FALSE AND v_pode_excluir IS FALSE AND v_pode_modulo IS FALSE THEN
    r.situacao := 'passou';
    r.obtido   := 'Travas presentes nas 18 tabelas; o usuario restrito nao cria, nao exclui e nao passa no porteiro do Ponto.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := 'FALHA GRAVE: o usuario restrito obteve escrita no Ponto: criar=' || COALESCE(v_pode_criar::text, 'nulo')
               || ', excluir=' || COALESCE(v_pode_excluir::text, 'nulo') || ', modulo=' || COALESCE(v_pode_modulo::text, 'nulo') || '.';
    r.detalhe  := jsonb_build_object('criar', v_pode_criar, 'excluir', v_pode_excluir, 'modulo', v_pode_modulo);
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
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; PERFIL-030 nao documentado.';
    RETURN;
  END IF;
  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PERFIL-030', 'Escrita da jornada pelo perfil: quem nao tem Ponto nao grava escala, banco de horas, acordos nem alertas',
   'negativo', 'critica', 'aprovado', 'api', 'LGPD arts. 6º e 46',
   'As 18 tabelas de ponto/jornada eram graváveis por qualquer membro da empresa (só o tenant decidia). A escrita passa a seguir o perfil: gestão grava com o verbo criar, editar ou excluir no módulo e no escopo do perfil (líder de subordinados só na equipe); o colaborador só solicita o próprio ajuste (sempre pendente); tabelas que só o sistema grava ficam para Super Admin e dono; a trilha de acessos sensíveis só o Super Admin altera. Os gatilhos de atestado passam a gravar por conta do sistema para o alerta não se perder.',
   'Escrita da jornada aplicada; usuario restrito semeado.',
   '[{"ordem":1,"acao":"Conferir as travas RESTRICTIVE de INSERT, UPDATE e DELETE nas 18 tabelas e os gatilhos de atestado como security definer","resultado_esperado":"Presentes em todas as que existem"},{"ordem":2,"acao":"Com o usuario restrito (so Documentos), consultar perfil_escreve (criar, excluir) e perfil_permite_modulo no Ponto","resultado_esperado":"Falso nas tres"}]'::jsonb,
   'Sem Ponto no perfil, nada de escrita na jornada.', 'Rotina qa_caso_perfil_030 (somente leitura).')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
    VALUES ('PERFIL-030', 'qa_caso_perfil_030', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao PERFIL-030 nao registrada: %', SQLERRM;
END $doc$;

DO $roda$
BEGIN
  PERFORM public.qa_rodar_bateria('manual', 'seguranca-acesso/perfis');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bateria nao rodou agora (%). A rotina fica registrada e entra na proxima execucao.', SQLERRM;
END $roda$;

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT (SELECT count(*) FROM public.qa_casos_teste WHERE codigo = 'PERFIL-030')       AS caso_documentado,
       (SELECT (public.qa_caso_perfil_030()).situacao)                                AS perfil_030,
       (SELECT (public.qa_caso_perfil_030()).obtido)                                  AS detalhe;
