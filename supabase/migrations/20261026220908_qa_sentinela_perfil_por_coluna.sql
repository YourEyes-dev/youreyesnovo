-- ============================================================================
-- SENTINELA DE PERFIL POR COLUNA + REGISTRO (PERFIL-AUD-001) — garantia estrutural
--
-- RAIZ do DASH-PERFIL-01 / PERFIL-AUD-001: a sentinela antiga confere por NOME
-- (qa_caso_perfil_003 varre atestado%/%_saude%/psicossocial%/ferias%/... ;
-- qa_caso_rls_003 confere 9 tabelas numa lista fixa). Tabela de dado pessoal
-- cujo nome nao casa (avaliacao_*, feedbacks, humor_*, onboarding_*, beneficios_*,
-- pdi_*, ponto auxiliares, ...) nunca era acusada, mesmo com tenant_id +
-- coluna de titular. Foi por isso que avaliacao/metas/humor/feedback escaparam.
--
-- CORRECAO (cobertura garantida, sem whack-a-mole por nome):
--   1) qa_tabelas_perfil_excecao — registro versionado de excecoes (tabela,
--      motivo, quem, quando), no espirito de qa_tabelas_protegidas.
--   2) qa_caso_perfil_044 — sonda POR COLUNA + REGISTRO: varre TODA tabela
--      public (relkind 'r') com tenant_id E uma coluna de titular
--      (colaborador_id/colaborador_cpf/colaborador_nome/user_id/avaliador_id) e
--      ACUSA a que NAO tem perfil_restringe_leitura_* RESTRICTIVE de SELECT,
--      salvo se estiver na excecao versionada. Assim nenhuma tabela sensivel
--      passa por omissao de NOME: basta ter coluna de titular. De proposito NAO
--      tenta adivinhar "escopo por titular" pelo TEXTO da politica (o padrao
--      tenant_id IN (SELECT tenant_id FROM profiles WHERE user_id = auth.uid())
--      cita auth.uid() mas e leitura por tenant INTEIRO — heuristica de texto
--      daria falso-negativo e um vazamento passaria). O que e seguro por titular
--      (ex.: bem_estar_respostas/bem_estar_gratidao, auth.uid()=user_id) entra na
--      excecao com o motivo citando a migration — documentado, nunca silenciado.
--   3) qa_caso_perfil_045 — confere que as 8 CRITICAS da 1a onda
--      (PERFIL-AUD-007/005/002) carregam a camada RESTRICTIVE.
--
-- As tabelas de ALTA (metas extra/OKR, PDI, ponto auxiliar, beneficios
-- individuais, disciplinar/desligamento) sao a 2a onda: a sonda vai ACUSA-LAS
-- (tem PII e leitura ampla) ate serem fechadas — de proposito. NAO entram na
-- excecao (so config/baixo impacto, sem PII individual, entra).
--
-- Idempotente. Somente leitura de dado de cliente (cria registro/rotinas de QA).
-- ============================================================================

SET lock_timeout = '10s';

-- ── 1) Registro versionado de excecoes ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.qa_tabelas_perfil_excecao (
  tabela         text PRIMARY KEY,
  motivo         text NOT NULL,
  registrado_por text NOT NULL DEFAULT 'engenharia',
  registrado_em  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.qa_tabelas_perfil_excecao IS
  'Tabelas com tenant_id + coluna de titular que a sonda qa_caso_perfil_044 NAO acusa, por decisao documentada (config/organizacional, sem PII individual). Toda linha e uma excecao versionada com motivo e autor; tabela com PII NUNCA entra aqui (seria silenciar o vazamento).';

-- Config/baixo impacto conhecida da auditoria (PERFIL-AUD-003/008): catalogos e
-- parametros, sem dado pessoal individual. Entram como excecao documentada.
INSERT INTO public.qa_tabelas_perfil_excecao (tabela, motivo, registrado_por) VALUES
  ('metas_indicadores',  'Catalogo de indicadores de meta (config); sem PII individual. PERFIL-AUD-003.', 'engenharia (PERFIL-AUD-001)'),
  ('metas_configuracao', 'Parametros do modulo de metas (config); sem PII individual. PERFIL-AUD-003.', 'engenharia (PERFIL-AUD-001)'),
  ('metas_workflow_log', 'Log de workflow do modulo de metas (operacional); sem PII individual. PERFIL-AUD-003.', 'engenharia (PERFIL-AUD-001)'),
  ('beneficios_plr',     'Parametros de PLR (config/financeiro); sem PII individual. PERFIL-AUD-008.', 'engenharia (PERFIL-AUD-001)'),
  ('beneficios_faturas', 'Faturas por fornecedor/plano (financeiro); sem PII individual. PERFIL-AUD-008.', 'engenharia (PERFIL-AUD-001)'),
  -- Ja corretas POR TITULAR (auth.uid() = user_id), 20260409134833: nao precisam
  -- da camada RESTRICTIVE; a sonda nao infere isso do texto, entao documenta-se aqui.
  ('bem_estar_respostas', 'Leitura ja por titular (auth.uid() = user_id), 20260409134833; sem leitura por tenant. PERFIL-AUD-005 OBS.', 'engenharia (PERFIL-AUD-001)'),
  ('bem_estar_gratidao',  'Leitura ja por titular (auth.uid() = user_id), 20260409134833; sem leitura por tenant. PERFIL-AUD-005 OBS.', 'engenharia (PERFIL-AUD-001)')
ON CONFLICT (tabela) DO NOTHING;

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

  -- Atribuicao por subconsulta escalar (nao usar SELECT ... INTO: no SQL Editor
  -- isso arma o auto-RLS e corrompe funcoes do mesmo arquivo).
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
        -- (1) carrega coluna de titular (registro-sujeito de uma pessoa)
        AND EXISTS (
          SELECT 1 FROM information_schema.columns s
          WHERE s.table_schema = 'public' AND s.table_name = c.table_name
            AND s.column_name IN ('colaborador_id', 'colaborador_cpf', 'colaborador_nome',
                                  'user_id', 'avaliador_id'))
        -- (2) NAO esta na lista de excecoes versionadas
        AND NOT EXISTS (
          SELECT 1 FROM public.qa_tabelas_perfil_excecao e WHERE e.tabela = c.table_name)
        -- (3) NAO tem a camada de perfil RESTRICTIVE de SELECT
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

  -- Prova funcional (opcional): o usuario restrito (so Documentos) nao le humor
  -- de colegas (humor_diario so abre para Bem-estar/Psicossocial amplo ou o proprio).
  v_uid := (SELECT ub.auth_user_id FROM public.usuarios_base ub
             WHERE ub.email_principal = 'restrito.e2e@youreyes.local' LIMIT 1);
  IF v_uid IS NULL OR to_regprocedure('qa_rls.conta_auth(text)') IS NULL
     OR to_regclass('public.humor_diario') IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Travas conferidas. Falta a prova funcional: semear restrito.e2e@youreyes.local (seed-e2e-user) e os ajudantes qa_rls.';
    RETURN r;
  END IF;

  -- Linhas de humor que NAO sao do usuario restrito (as unicas que ele poderia vazar).
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
-- qa_tabelas_protegidas ja contem toda tabela com tenant_id (cerca generica);
-- aqui so carimbamos o motivo com a camada de perfil, para rastreio.
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

-- ── 5) Documentacao de testes (qa_casos_teste) + ligacao a rotina ────────────
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
   'A sentinela antiga (PERFIL-003/RLS-003) so via tabelas por padrao de NOME; tabela nova fora do padrao escapava (foi a raiz do DASH-PERFIL-01). A sonda nova varre TODA tabela public com tenant_id + coluna de titular (colaborador_id/cpf/nome, user_id, avaliador_id) e acusa a que nao tem a camada RESTRICTIVE perfil_restringe_leitura_* de SELECT, salvo excecao versionada em qa_tabelas_perfil_excecao. Nao infere escopo por titular do texto da politica (daria falso-negativo); o que e seguro por titular entra na excecao documentado.',
   'Migration/entrega da sentinela aplicada (qa_tabelas_perfil_excecao criada).',
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

-- ── 6) Rodar a bateria da familia (nao aborta se algo faltar) ────────────────
DO $roda$
BEGIN
  PERFORM public.qa_rodar_bateria('manual', 'seguranca-acesso/perfis');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bateria nao rodou agora (%). As rotinas ficam registradas e entram na proxima execucao.', SQLERRM;
END $roda$;
