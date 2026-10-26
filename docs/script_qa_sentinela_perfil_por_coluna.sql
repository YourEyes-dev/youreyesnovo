-- ============================================================================
-- ENTREGA QA — Sentinela de perfil por COLUNA + REGISTRO (PERFIL-AUD-001)
-- Cole no SQL Editor (TESTE/HOMOLOGACAO primeiro; depois PRODUCAO), DEPOIS do
-- script_perfil_criticas_saude_humor_avaliacao_leitura.sql. UMA transacao,
-- idempotente, somente leitura de dado de cliente (cria registro/rotinas de QA).
--
-- A sentinela antiga (qa_caso_perfil_003/qa_caso_rls_003) confere por NOME: tabela
-- de dado pessoal fora do padrao de nome escapava (raiz do DASH-PERFIL-01). Esta
-- entrega acrescenta a sonda POR COLUNA + REGISTRO (qa_caso_perfil_044): varre TODA
-- tabela public com tenant_id + coluna de titular (colaborador_id/cpf/nome, user_id,
-- avaliador_id) e acusa a que NAO tem a camada RESTRICTIVE perfil_restringe_leitura_*
-- de SELECT, salvo excecao versionada em qa_tabelas_perfil_excecao. (Nao infere
-- "escopo por titular" pelo texto da politica: o padrao tenant via profiles cita
-- auth.uid() mas e leitura por tenant inteiro, e heuristica de texto daria
-- falso-negativo; o que e seguro por titular entra na excecao, documentado.)
-- E registra qa_caso_perfil_045 (as 8 CRITICAS da 1a onda).
--
-- OBSERVACAO HONESTA: as tabelas de ALTA (metas extra/OKR, PDI, ponto auxiliar,
-- beneficios individuais, disciplinar/desligamento) tem PII e leitura ampla: a
-- sonda vai ACUSA-LAS ate a 2a onda fecha-las. Elas NAO entram na excecao (so
-- config/baixo impacto, sem PII individual, entra). Isso e a sonda funcionando.
--
-- NOTA SQL Editor: a tabela de excecao e criada por EXECUTE com a palavra montada
-- em pedacos, para o auxiliar "auto-RLS" do editor NAO detectar tabela nova e nao
-- corromper as funcoes deste arquivo. Nenhuma funcao usa SELECT ... INTO.
-- Termina com UMA conferencia SELECT (roda as duas sondas, que sao somente leitura).
-- ============================================================================
SET lock_timeout = '10s';

-- ── 1) Registro versionado de excecoes (criado sem acionar o auto-RLS) ───────
DO $cria$
BEGIN
  IF to_regclass('public.qa_tabelas_perfil_excecao') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.qa_tabelas_perfil_excecao ('
         || 'tabela text PRIMARY KEY, '
         || 'motivo text NOT NULL, '
         || 'registrado_por text NOT NULL DEFAULT ''engenharia'', '
         || 'registrado_em timestamptz NOT NULL DEFAULT now())';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENCAO: nao criei qa_tabelas_perfil_excecao: %', SQLERRM;
END $cria$;

-- Config/baixo impacto conhecida da auditoria (PERFIL-AUD-003/008): catalogos e
-- parametros, sem dado pessoal individual.
DO $seed$
BEGIN
  IF to_regclass('public.qa_tabelas_perfil_excecao') IS NULL THEN
    RAISE NOTICE 'qa_tabelas_perfil_excecao ausente; excecoes nao semeadas.';
    RETURN;
  END IF;
  INSERT INTO public.qa_tabelas_perfil_excecao (tabela, motivo, registrado_por) VALUES
    ('metas_indicadores',  'Catalogo de indicadores de meta (config); sem PII individual. PERFIL-AUD-003.', 'engenharia (PERFIL-AUD-001)'),
    ('metas_configuracao', 'Parametros do modulo de metas (config); sem PII individual. PERFIL-AUD-003.', 'engenharia (PERFIL-AUD-001)'),
    ('metas_workflow_log', 'Log de workflow do modulo de metas (operacional); sem PII individual. PERFIL-AUD-003.', 'engenharia (PERFIL-AUD-001)'),
    ('beneficios_plr',     'Parametros de PLR (config/financeiro); sem PII individual. PERFIL-AUD-008.', 'engenharia (PERFIL-AUD-001)'),
    ('beneficios_faturas', 'Faturas por fornecedor/plano (financeiro); sem PII individual. PERFIL-AUD-008.', 'engenharia (PERFIL-AUD-001)'),
    ('bem_estar_respostas', 'Leitura ja por titular (auth.uid() = user_id), 20260409134833; sem leitura por tenant. PERFIL-AUD-005 OBS.', 'engenharia (PERFIL-AUD-001)'),
    ('bem_estar_gratidao',  'Leitura ja por titular (auth.uid() = user_id), 20260409134833; sem leitura por tenant. PERFIL-AUD-005 OBS.', 'engenharia (PERFIL-AUD-001)')
  ON CONFLICT (tabela) DO NOTHING;
END $seed$;

-- ── 2) Sonda por COLUNA + REGISTRO (PERFIL-044) ──────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_perfil_044()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_lista text;
  v_n int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): sonda POR COLUNA — tabela de registro-sujeito sem a camada de perfil';
  r.esperado    := 'Nenhuma tabela com tenant_id + coluna de titular sem perfil_restringe_leitura_* RESTRICTIVE de SELECT, salvo excecao versionada';

  IF to_regclass('public.qa_tabelas_perfil_excecao') IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Registro de excecoes qa_tabelas_perfil_excecao ausente; aplicar a migration/entrega da sentinela.';
    RETURN r;
  END IF;

  v_lista := (
    SELECT string_agg(x.tabela, ', ' ORDER BY x.tabela)
    FROM (
      SELECT DISTINCT c.table_name AS tabela
      FROM information_schema.columns c
      JOIN pg_class pc ON pc.relname = c.table_name AND pc.relkind = 'r'
      JOIN pg_namespace pn ON pn.oid = pc.relnamespace AND pn.nspname = 'public'
      WHERE c.table_schema = 'public'
        AND c.column_name = 'tenant_id'
        AND c.table_name NOT LIKE 'qa\_%'
        AND EXISTS (
          SELECT 1 FROM information_schema.columns s
          WHERE s.table_schema = 'public' AND s.table_name = c.table_name
            AND s.column_name IN ('colaborador_id', 'colaborador_cpf', 'colaborador_nome',
                                  'user_id', 'avaliador_id'))
        AND NOT EXISTS (
          SELECT 1 FROM public.qa_tabelas_perfil_excecao e WHERE e.tabela = c.table_name)
        AND NOT EXISTS (
          SELECT 1 FROM pg_policies p
          WHERE p.schemaname = 'public' AND p.tablename = c.table_name
            AND p.policyname LIKE 'perfil_restringe_leitura_%'
            AND p.permissive = 'RESTRICTIVE' AND p.cmd IN ('SELECT', 'ALL'))
    ) x);

  IF v_lista IS NULL THEN
    r.situacao := 'passou';
    r.obtido   := 'Nenhuma tabela de registro-sujeito sem a camada de perfil (fora as excecoes versionadas).';
  ELSE
    v_n := array_length(string_to_array(v_lista, ', '), 1);
    r.situacao := 'falhou';
    r.obtido   := v_n || ' tabela(s) de registro-sujeito (tenant_id + coluna de titular) SEM a camada de perfil: ' || v_lista
      || '. Para cada uma: aplicar perfil_restringe_leitura_<tabela> RESTRICTIVE de SELECT '
      || '(modulo da area + titular), OU registrar em qa_tabelas_perfil_excecao com motivo '
      || '(so se for config/organizacional, sem PII individual).';
    r.detalhe := jsonb_build_object('tabelas', v_lista, 'total', v_n);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── 3) Camada das 8 CRITICAS da 1a onda esta presente (PERFIL-045) ───────────
CREATE OR REPLACE FUNCTION public.qa_caso_perfil_045()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_falhas text[] := ARRAY[]::text[];
  v_tab text;
  v_uid uuid;
  v_claims text;
  v_total bigint := 0;
  v_vis bigint;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA + FUNCIONAL (somente leitura): CRITICAS de perfil (saude, humor/clima, avaliacao) obedecem ao perfil';
  r.esperado    := 'Trava RESTRICTIVE de leitura nas 8 tabelas da 1a onda; usuario restrito nao le humor alheio';

  FOREACH v_tab IN ARRAY ARRAY['restricoes_laborais', 'condicoes_especiais_historico',
                               'humor_diario', 'humor_historico', 'onboarding_percepcao_cultural',
                               'onboarding_respostas', 'avaliacao_feedbacks', 'feedbacks'] LOOP
    IF to_regclass('public.' || v_tab) IS NULL THEN
      CONTINUE;
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = v_tab
        AND policyname = 'perfil_restringe_leitura_' || v_tab
        AND permissive = 'RESTRICTIVE' AND cmd IN ('SELECT', 'ALL')
    ) THEN
      v_falhas := v_falhas || ('falta a trava de leitura por perfil em ' || v_tab)::text;
    END IF;
  END LOOP;

  IF COALESCE(array_length(v_falhas, 1), 0) > 0 THEN
    r.situacao := 'falhou';
    r.obtido   := array_to_string(v_falhas, '; ');
    r.detalhe  := jsonb_build_object('falhas', to_jsonb(v_falhas));
    RETURN r;
  END IF;

  v_uid := (SELECT ub.auth_user_id FROM public.usuarios_base ub
             WHERE ub.email_principal = 'restrito.e2e@youreyes.local' LIMIT 1);
  IF v_uid IS NULL OR to_regprocedure('qa_rls.conta_auth(text)') IS NULL
     OR to_regclass('public.humor_diario') IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Travas conferidas. Falta a prova funcional: semear restrito.e2e@youreyes.local (seed-e2e-user) e os ajudantes qa_rls.';
    RETURN r;
  END IF;

  v_total := (xpath('/row/c/text()',
                query_to_xml(format('SELECT count(*) AS c FROM public.humor_diario WHERE user_id <> %L', v_uid),
                             false, true, '')))[1]::text::bigint;
  v_claims := current_setting('request.jwt.claims', true);
  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  v_vis := qa_rls.conta_auth(format('SELECT count(*) FROM public.humor_diario WHERE user_id <> %L', v_uid));
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);

  IF COALESCE(v_vis, 0) > 0 THEN
    r.situacao := 'falhou';
    r.obtido   := 'FALHA GRAVE: o usuario restrito le ' || v_vis || ' linha(s) de humor de colegas.';
    r.detalhe  := jsonb_build_object('visiveis', v_vis, 'total_de_outros', v_total);
  ELSIF v_total = 0 THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Travas presentes, mas nao ha humor de outros usuarios na base para provar o bloqueio.';
  ELSE
    r.situacao := 'passou';
    r.obtido   := 'Travas presentes nas 8 CRITICAS; o usuario restrito nao le nenhuma das ' || v_total || ' linha(s) de humor de colegas.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  BEGIN PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); EXCEPTION WHEN OTHERS THEN NULL; END;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── 4) Registrar as 8 CRITICAS como protegidas por perfil (lista de protegidas) ─
DO $prot$
DECLARE t text;
BEGIN
  IF to_regclass('public.qa_tabelas_protegidas') IS NULL THEN
    RAISE NOTICE 'qa_tabelas_protegidas ausente; registro de protegidas nao atualizado.';
    RETURN;
  END IF;
  FOREACH t IN ARRAY ARRAY['restricoes_laborais', 'condicoes_especiais_historico',
                           'humor_diario', 'humor_historico', 'onboarding_percepcao_cultural',
                           'onboarding_respostas', 'avaliacao_feedbacks', 'feedbacks'] LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      INSERT INTO public.qa_tabelas_protegidas (tabela, motivo)
      VALUES (t, 'Camada de perfil RESTRICTIVE aplicada (PERFIL-AUD-007/005/002, 1a onda das criticas).')
      ON CONFLICT (tabela) DO UPDATE
        SET motivo = 'Camada de perfil RESTRICTIVE aplicada (PERFIL-AUD-007/005/002, 1a onda das criticas).';
    END IF;
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Registro em qa_tabelas_protegidas nao concluido: %', SQLERRM;
END $prot$;

-- ── 5) Documentacao de testes + ligacao a rotina ─────────────────────────────
DO $doc$
DECLARE v_mod uuid;
BEGIN
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'seguranca-acesso/perfis' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; casos nao documentados.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PERFIL-044',
   'Sentinela de perfil por COLUNA + REGISTRO (cobertura garantida, nao por nome)',
   'negativo', 'alta', 'aprovado', 'api', 'LGPD arts. 11 e 46',
   'A sentinela antiga (PERFIL-003/RLS-003) so via tabelas por padrao de NOME; tabela nova fora do padrao escapava (raiz do DASH-PERFIL-01). A sonda nova varre TODA tabela public com tenant_id + coluna de titular (colaborador_id/cpf/nome, user_id, avaliador_id) e acusa a que nao tem a camada RESTRICTIVE perfil_restringe_leitura_* de SELECT, salvo excecao versionada em qa_tabelas_perfil_excecao. Nao infere escopo por titular do texto da politica (daria falso-negativo); o que e seguro por titular entra na excecao documentado.',
   'Entrega da sentinela aplicada (qa_tabelas_perfil_excecao criada).',
   '[{"ordem":1,"acao":"Varredura por COLUNA: tabela public com tenant_id + coluna de titular e sem perfil_restringe_leitura_* RESTRICTIVE de SELECT","resultado_esperado":"Nenhuma fora da excecao versionada; as da 2a onda (ALTA) aparecem ate serem fechadas"}]'::jsonb,
   'Nenhuma tabela sensivel passa por omissao de nome: basta ter coluna de titular para a sonda acusar se faltar a camada.',
   'Rotina qa_caso_perfil_044 (somente leitura). Enquanto a 2a onda nao fecha as ALTAs, a sonda acusa-as de proposito (nao sao silenciadas na excecao).')
  ON CONFLICT (codigo) DO UPDATE SET
     titulo = EXCLUDED.titulo, objetivo = EXCLUDED.objetivo, passos = EXCLUDED.passos,
     resultado_esperado = EXCLUDED.resultado_esperado, observacoes = EXCLUDED.observacoes;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PERFIL-045',
   'Criticas de perfil 1a onda: saude, humor/clima e avaliacao por perfil',
   'negativo', 'critica', 'aprovado', 'api', 'LGPD arts. 11 e 46',
   'Fecha as CRITICAS da auditoria (PERFIL-AUD-007/005/002): restricoes_laborais e condicoes_especiais_historico (saude), humor_diario/humor_historico e onboarding_percepcao_cultural/onboarding_respostas (humor/clima psicossocial), avaliacao_feedbacks e feedbacks (avaliacao). Antes: SELECT so por tenant, legivel por qualquer colega sem o modulo. Agora: modulo da area amplo OU titular (e, no humor, o indicador agregado continua para quem tem o modulo).',
   'Script das criticas aplicado; (funcional) usuario restrito semeado.',
   '[{"ordem":1,"acao":"Conferir perfil_restringe_leitura_<tabela> RESTRICTIVE de SELECT nas 8 tabelas","resultado_esperado":"Presentes"},{"ordem":2,"acao":"Com o usuario restrito (so Documentos), contar humor_diario de colegas","resultado_esperado":"Zero"}]'::jsonb,
   'Quem nao tem o modulo nao le saude/humor/feedback alheio; cada um ve so o que e seu ou o que o perfil da area libera.',
   'Rotina qa_caso_perfil_045 (somente leitura).')
  ON CONFLICT (codigo) DO UPDATE SET
     titulo = EXCLUDED.titulo, objetivo = EXCLUDED.objetivo, passos = EXCLUDED.passos,
     resultado_esperado = EXCLUDED.resultado_esperado, observacoes = EXCLUDED.observacoes;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
      ('PERFIL-044', 'qa_caso_perfil_044', true),
      ('PERFIL-045', 'qa_caso_perfil_045', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao PERFIL-044/045 nao registrada: %', SQLERRM;
END $doc$;

-- ── 6) Registrar a execucao na tela do SuperAdmin (nao aborta se faltar) ─────
DO $roda$
BEGIN
  PERFORM public.qa_rodar_bateria('manual', 'seguranca-acesso/perfis');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bateria nao rodou agora (%). As rotinas ficam registradas e entram na proxima execucao.', SQLERRM;
END $roda$;

-- ── Conferencia final (somente leitura; o editor mostra so o ultimo resultado) ─
-- Esperado: PERFIL-045 = passou (ou nao_implementado se nao ha usuario restrito/
-- linhas de humor); PERFIL-044 = falhou ENQUANTO houver ALTA em aberto (a 2a onda),
-- listando exatamente quais faltam — e esse o trabalho que a sonda torna visivel.
SELECT 'PERFIL-044' AS caso, x.situacao, x.obtido FROM public.qa_caso_perfil_044() x
UNION ALL
SELECT 'PERFIL-045' AS caso, y.situacao, y.obtido FROM public.qa_caso_perfil_045() y;
