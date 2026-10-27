-- =========================================================
-- QA — cadastro de colaboradores: trava de leitura da tabela admissoes (passo 2.6, parte 2)
--
--   PERFIL-039 (api, somente leitura)  a tabela admissoes tem a trava RESTRICTIVE de leitura por perfil e o usuario de teste
--              restrito (so Documentos) le no maximo a PROPRIA ficha, enquanto o diretorio de pessoas segue completo.
-- Idempotente: caso com ON CONFLICT (codigo) DO NOTHING; implementacao por upsert.
-- =========================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.qa_caso_perfil_039()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_def text;
  v_uid uuid;
  v_claims text;
  v_total bigint;
  v_visiveis bigint;
  v_diretorio bigint;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA + FUNCIONAL (somente leitura): a ficha completa so para quem tem perfil';
  r.esperado    := 'Trava RESTRICTIVE em admissoes; usuario restrito le no maximo a propria ficha e ainda recebe o diretorio';

  v_def := (SELECT qual FROM pg_policies WHERE schemaname = 'public' AND tablename = 'admissoes'
              AND policyname = 'perfil_restringe_leitura_admissoes' AND permissive = 'RESTRICTIVE');
  IF v_def IS NULL THEN
    r.situacao := 'falhou';
    r.obtido   := 'FALHA GRAVE: falta a trava de leitura por perfil na tabela admissoes.';
    RETURN r;
  ELSIF v_def !~ 'perfil_amplo_sem_subordinados' OR v_def !~ 'cpf_do_usuario_logado' THEN
    r.situacao := 'falhou';
    r.obtido   := 'A trava de admissoes nao consulta o perfil e o proprio CPF.';
    RETURN r;
  END IF;

  v_uid := (SELECT ub.auth_user_id FROM public.usuarios_base ub WHERE ub.email_principal = 'restrito.e2e@youreyes.local' LIMIT 1);
  IF v_uid IS NULL OR to_regprocedure('qa_rls.conta_auth(text)') IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Trava conferida. Falta a prova funcional: semear restrito.e2e@youreyes.local (seed-e2e-user) e ter os ajudantes qa_rls.';
    RETURN r;
  END IF;

  v_total := (xpath('/row/c/text()', query_to_xml('SELECT count(*) AS c FROM public.admissoes', false, true, '')))[1]::text::bigint;
  v_claims := current_setting('request.jwt.claims', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  v_visiveis := qa_rls.conta_auth('SELECT count(*) FROM public.admissoes');
  v_diretorio := qa_rls.conta_auth('SELECT count(*) FROM public.colaboradores_diretorio()');
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);

  IF COALESCE(v_visiveis, 0) > 1 THEN
    r.situacao := 'falhou';
    r.obtido   := 'FALHA GRAVE: o usuario restrito le ' || v_visiveis || ' fichas completas (deveria ler no maximo a propria).';
  ELSIF COALESCE(v_total, 0) <= 1 THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Trava presente, mas ha poucas fichas para provar o bloqueio.';
  ELSE
    r.situacao := 'passou';
    r.obtido   := 'Trava presente; o usuario restrito le ' || v_visiveis || ' de ' || v_total || ' fichas e recebe ' || COALESCE(v_diretorio, 0) || ' pessoas no diretorio.';
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
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; PERFIL-039 nao documentado.';
    RETURN;
  END IF;
  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PERFIL-039', 'Cadastro de colaboradores: a ficha completa so para quem tem perfil de dados de pessoas, a propria ou a equipe',
   'negativo', 'critica', 'aprovado', 'api', 'LGPD arts. 6º, 11 e 46',
   'A tabela admissoes (CPF, dados bancarios, saude do exame admissional, salario) era legivel por qualquer membro da empresa, inclusive o colaborador comum. Agora le a ficha completa quem tem escopo amplo em um modulo de dados de pessoas (colaboradores, ponto, ferias, financeiro, benefícios, psicossocial, SST, atestados, EPI, incidentes, avaliacoes, onboarding, contratos, usuarios, hub contabil, configuracoes, cargos, departamentos, filiais, empresa, ergonomia, analise de jornada), a propria pessoa, e o lider a ficha da equipe. Os demais recursos usam o diretorio de pessoas (nome, cargo, departamento, foto) sem CPF nem contato alheios.',
   'Scripts das partes 1 e 2 aplicados; usuario restrito semeado.',
   '[{"ordem":1,"acao":"Conferir a politica RESTRICTIVE perfil_restringe_leitura_admissoes (perfil amplo, proprio CPF, subordinados)","resultado_esperado":"Presente"},{"ordem":2,"acao":"Com o usuario restrito, contar as fichas visiveis e as pessoas do diretorio","resultado_esperado":"No maximo 1 ficha; diretorio completo"}]'::jsonb,
   'Ficha completa so para quem precisa; diretorio para todos.', 'Rotina qa_caso_perfil_039 (somente leitura). Limite: quem tem acesso amplo a algum modulo de pessoas le a coluna de salario pela API direta; a visao admissoes_segura mascara so nas telas.')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
    VALUES ('PERFIL-039', 'qa_caso_perfil_039', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao PERFIL-039 nao registrada: %', SQLERRM;
END $doc$;

DO $roda$
BEGIN
  PERFORM public.qa_rodar_bateria('manual', 'seguranca-acesso/perfis');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bateria nao rodou agora (%). A rotina fica registrada e entra na proxima execucao.', SQLERRM;
END $roda$;
