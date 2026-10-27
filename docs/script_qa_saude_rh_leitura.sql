-- ============================================================================
-- ENTREGA — QA: caso PERFIL-035 (saude e RH), DEPOIS do script_saude_rh_leitura_por_perfil.sql
-- So dado de QA (rotina, caso e implementacao). Cole no SQL Editor.
-- ============================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.qa_caso_perfil_035()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_falhas text[] := ARRAY[]::text[];
  v_tab text;
  v_def text;
  v_uid uuid;
  v_claims text;
  v_visiveis bigint;
  v_total bigint := 0;
  v_n bigint;
  v_selo bigint;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA + FUNCIONAL (somente leitura): dados de saude e RH obedecem ao perfil';
  r.esperado    := 'Trava de leitura nas 13 tabelas, trava de escrita nos certificados, selo sem motivo para quem nao e da saude; usuario restrito sem linhas alheias';

  FOREACH v_tab IN ARRAY ARRAY['afastamentos','afastamentos_cat','afastamentos_ntep','afastamentos_fap','afastamentos_esocial',
      'afastamentos_retorno','afastamentos_marcadores','afastamentos_previdenciario','afastamentos_pendencias',
      'contratos_experiencia','contratos_experiencia_historico','colaborador_condicoes_especiais','esocial_transmissoes',
      'esocial_certificados'] LOOP
    IF to_regclass('public.' || v_tab) IS NULL THEN
      CONTINUE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = v_tab
                    AND policyname = 'perfil_restringe_leitura_' || v_tab AND permissive = 'RESTRICTIVE') THEN
      v_falhas := v_falhas || ('falta a trava de leitura em ' || v_tab)::text;
    END IF;
  END LOOP;

  IF to_regclass('public.esocial_certificados') IS NOT NULL THEN
    FOREACH v_tab IN ARRAY ARRAY['ins','upd','del'] LOOP
      IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'esocial_certificados'
                      AND policyname = 'perfil_restringe_escrita_esocial_certificados_' || v_tab AND permissive = 'RESTRICTIVE') THEN
        v_falhas := v_falhas || ('falta a trava de escrita (' || v_tab || ') nos certificados digitais')::text;
      END IF;
    END LOOP;
  END IF;

  v_def := (SELECT pg_get_functiondef(p.oid) FROM pg_proc p
             WHERE p.proname = 'afastamentos_ativos_resumo' AND p.pronamespace = 'public'::regnamespace LIMIT 1);
  IF v_def IS NULL THEN
    v_falhas := v_falhas || 'falta a funcao afastamentos_ativos_resumo'::text;
  ELSIF v_def !~* 'perfil_amplo_sem_subordinados' OR v_def !~* 'security definer' THEN
    v_falhas := v_falhas || 'afastamentos_ativos_resumo nao restringe o motivo ao perfil de saude'::text;
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
    r.obtido   := 'Travas conferidas. Falta a prova funcional: semear restrito.e2e@youreyes.local (seed-e2e-user) e ter os ajudantes qa_rls.';
    RETURN r;
  END IF;

  v_claims := current_setting('request.jwt.claims', true);
  FOREACH v_tab IN ARRAY ARRAY['afastamentos','afastamentos_cat','afastamentos_previdenciario','afastamentos_pendencias',
      'contratos_experiencia','colaborador_condicoes_especiais','esocial_transmissoes','esocial_certificados'] LOOP
    IF to_regclass('public.' || v_tab) IS NULL THEN
      CONTINUE;
    END IF;
    v_n := (xpath('/row/c/text()', query_to_xml(format('SELECT count(*) AS c FROM public.%I', v_tab), false, true, '')))[1]::text::bigint;
    v_total := v_total + COALESCE(v_n, 0);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
    v_visiveis := qa_rls.conta_auth(format('SELECT count(*) FROM public.%I', v_tab));
    PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
    IF COALESCE(v_visiveis, 0) > 0 THEN
      v_falhas := v_falhas || ('FALHA GRAVE: o usuario restrito le ' || v_visiveis || ' linhas de ' || v_tab)::text;
    END IF;
  END LOOP;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  v_selo := qa_rls.conta_auth('SELECT count(*) FROM public.afastamentos_ativos_resumo()');
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF COALESCE(v_selo, 0) > 0 THEN
    v_falhas := v_falhas || ('FALHA GRAVE: o usuario restrito recebe ' || v_selo || ' afastados no selo')::text;
  END IF;

  IF COALESCE(array_length(v_falhas, 1), 0) > 0 THEN
    r.situacao := 'falhou';
    r.obtido   := array_to_string(v_falhas, '; ');
    r.detalhe  := jsonb_build_object('falhas', to_jsonb(v_falhas));
  ELSIF v_total = 0 THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Travas presentes, mas nao ha linhas nessas tabelas para provar o bloqueio.';
  ELSE
    r.situacao := 'passou';
    r.obtido   := 'Travas presentes; o usuario restrito nao le nenhuma das ' || v_total || ' linhas de saude/RH e o selo vem vazio.';
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
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; PERFIL-035 nao documentado.';
    RETURN;
  END IF;
  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PERFIL-035', 'Dados de saude e RH: afastamentos, eSocial, contratos de experiencia e condicoes especiais so por perfil',
   'negativo', 'critica', 'aprovado', 'api', 'LGPD arts. 6º, 11 e 46',
   'Afastamentos (com motivo clinico, nexo, CAT e beneficio do INSS), eventos eSocial, certificados digitais, contratos de experiencia e condicoes especiais eram legiveis por qualquer membro da empresa, e o selo "Afastado" mostrava o motivo (inclusive saude mental) em PDI, feedback, EPI e outras telas. Agora: modulo da area em escopo amplo, ou a propria linha (CPF), ou a do subordinado direto; eventos eSocial com remuneracao exigem tambem "pode ver salario"; certificados digitais so gravam com Configuracoes + verbo; o selo traz o motivo so a quem tem Atestados ou SST amplo.',
   'Script de saude e RH aplicado; usuario restrito semeado.',
   '[{"ordem":1,"acao":"Conferir a politica perfil_restringe_leitura_<tabela> nas 13 tabelas, a escrita dos certificados e a funcao do selo","resultado_esperado":"Presentes"},{"ordem":2,"acao":"Com o usuario restrito (so Documentos), contar linhas visiveis dessas tabelas e do selo","resultado_esperado":"Zero"}]'::jsonb,
   'Cada um ve so o que e seu ou o que o perfil da area libera.', 'Rotina qa_caso_perfil_035 (somente leitura).')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
    VALUES ('PERFIL-035', 'qa_caso_perfil_035', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao PERFIL-035 nao registrada: %', SQLERRM;
END $doc$;

DO $roda$
BEGIN
  PERFORM public.qa_rodar_bateria('manual', 'seguranca-acesso/perfis');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bateria nao rodou agora (%). A rotina fica registrada e entra na proxima execucao.', SQLERRM;
END $roda$;

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT (SELECT count(*) FROM public.qa_casos_teste WHERE codigo = 'PERFIL-035')       AS caso_documentado,
       (SELECT (public.qa_caso_perfil_035()).situacao)                                AS perfil_035,
       (SELECT (public.qa_caso_perfil_035()).obtido)                                  AS detalhe;
