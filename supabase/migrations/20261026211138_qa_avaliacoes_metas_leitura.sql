-- ============================================================================
-- QA — Avaliacoes e metas: leitura por perfil + endurecimento da sonda PERFIL-003
--
-- POR QUE A SONDA PERFIL-003 NAO PEGOU 'afastamentos' (nem avaliacao/metas):
-- ela nao usa uma lista fixa de tabelas, mas uma lista fixa de PADROES DE NOME
-- (atestado%, %_saude%, %psicossocial%, ferias%, folha_ferias%, documentos,
-- admissao_documentos). 'afastamentos', 'afastamentos_pendencias',
-- 'avaliacao_respostas', 'avaliacao_9box' e 'metas' nao casam com nenhum desses
-- nomes, entao a tabela sensivel ficava INVISIVEL para a sonda mesmo sem a camada
-- de perfil — exatamente o ponto cego que deixou o vazamento do dashboard passar.
--
-- CORRECAO DA SONDA (sem virar whack-a-mole):
--   (B) acrescenta o dominio por nome 'afastamento%' (todos os afastamentos_*
--       clinicos ja tem a camada; so os dois CONFIGS organizacionais entram como
--       excecao documentada).
--   (C) acrescenta os dominios de avaliacoes/metas, mas SO quando a tabela carrega
--       uma coluna-SUJEITO de trabalhador (colaborador_id/nome/cpf ou
--       avaliado_id/nome/cpf). Assim a sonda pega o registro-sujeito de uma pessoa
--       (avaliacao_respostas, avaliacao_9box, metas) e IGNORA os catalogos/ciclos
--       (avaliacao_ciclos, avaliacao_templates, metas_configuracao, ...) e as
--       filhas que so tem nome de ATOR (meta_okrs, okr_checkins, meta_acoes, ...),
--       que nao sao registro-sujeito. Nome de coluna comum (colaborador_cpf existe
--       em centenas de tabelas) NAO serve de sinal sozinho — por isso o dominio +
--       coluna-sujeito, e nao a coluna sozinha.
-- Observacao honesta: avaliacao_feedbacks, meta_okrs, okr_checkins, metas_*
-- (atores), e todo o modulo pdi_* seguem legiveis por tenant inteiro (sem camada
-- de perfil). Nao sao registro-sujeito direto (descem por FK de um pai ja travado
-- ou so guardam nome de ator) e estao FORA do raio do DASH-PERFIL-01; ficam como
-- acompanhamento separado — NAO foram silenciados (a sonda simplesmente nao os
-- classifica como registro-sujeito), e nao entram na lista de excecoes.
--
-- Idempotente (CREATE OR REPLACE; upsert dos casos). Somente leitura.
-- ============================================================================

SET lock_timeout = '10s';

-- ── 1) PERFIL-003 endurecida ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_perfil_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_lista text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): tabelas de padrao sensivel sem a camada de perfil';
  r.esperado    := 'Nenhuma tabela sensivel descoberta sem politica perfil_restringe_leitura_*';

  SELECT string_agg(x.table_name, ', ' ORDER BY x.table_name) INTO v_lista
  FROM (
    SELECT DISTINCT c.table_name
    FROM information_schema.columns c
    JOIN pg_class pc ON pc.relname = c.table_name AND pc.relkind = 'r'
    JOIN pg_namespace pn ON pn.oid = pc.relnamespace AND pn.nspname = 'public'
    WHERE c.table_schema = 'public'
      AND c.column_name = 'tenant_id'
      AND (c.table_name LIKE 'atestado%'
        OR c.table_name LIKE '%\_saude%'
        OR c.table_name LIKE '%psicossocial%'
        OR c.table_name LIKE 'ferias%'
        OR c.table_name LIKE 'folha\_ferias%'
        -- ACRESCENTADO EM 26/10 (DASH-PERFIL-01): dominios antes cegos.
        -- (B) afastamentos (afastamento/CAT/INSS/eSocial/NTEP/ASO de uma pessoa).
        OR c.table_name LIKE 'afastamento%'
        -- (C) avaliacoes/metas, so o REGISTRO-SUJEITO (carrega coluna de sujeito).
        OR ((c.table_name LIKE 'avaliacao%'
             OR c.table_name = 'metas'
             OR c.table_name LIKE 'meta\_%'
             OR c.table_name LIKE 'metas\_%'
             OR c.table_name LIKE 'okr%')
            AND EXISTS (
              SELECT 1 FROM information_schema.columns s
              WHERE s.table_schema = 'public'
                AND s.table_name = c.table_name
                AND s.column_name IN ('colaborador_id', 'colaborador_nome', 'colaborador_cpf',
                                      'avaliado_id', 'avaliado_nome', 'avaliado_cpf')))
        OR c.table_name IN ('documentos', 'admissao_documentos'))
      AND c.table_name NOT IN (
        -- EXCECOES DOCUMENTADAS (triagem de 08/08/2026):
        'psicossocial_dimensoes',            -- catalogo de dimensoes, sem dado pessoal
        'psicossocial_ghe',                  -- grupos homogeneos, organizacional
        'psicossocial_ghe_cargos',           -- relacao GHE x cargo, organizacional
        'psicossocial_consentimentos',       -- registro anonimo por hash de sessao
        'psicossocial_evidencias',           -- evidencia de risco organizacional, sem pessoa
        'psicossocial_indice_confiabilidade',-- indice agregado (contagens), sem pessoa
        'psicossocial_inventario_riscos',    -- inventario organizacional de riscos
        'psicossocial_plano_acao',           -- plano de acao por GHE, organizacional
        'psicossocial_responsavel_tecnico',  -- dados do RT do programa (profissional que
                                             -- assina o documento, nao trabalhador avaliado)
        'psicossocial_riscos',               -- catalogo de riscos ("nome" e o nome do risco)
        'questionario_psicossocial_campanhas',-- desenho do ciclo; nao guarda pessoa
        -- ACRESCENTADA EM 14/08, com a entrada do modulo Ferias:
        'ferias_config',                      -- percentuais de encargo da EMPRESA
                                              -- (INSS patronal, RAT/FAP, FGTS); parametro
        -- ACRESCENTADAS EM 26/10 (DASH-PERFIL-01): configs organizacionais de
        -- afastamentos (casam com 'afastamento%' mas nao guardam pessoa):
        'afastamento_tipo_config',            -- matriz de efeitos legais por TIPO de afastamento
        'afastamento_hipoteses_art473'        -- catalogo das hipoteses do art. 473 da CLT
      )
      AND NOT EXISTS (
        SELECT 1 FROM pg_policies p
        WHERE p.schemaname = 'public'
          AND p.tablename = c.table_name
          AND p.policyname LIKE 'perfil_restringe_leitura_%'
      )
  ) x;

  IF v_lista IS NULL THEN
    r.situacao := 'passou';
    r.obtido   := 'Nenhuma tabela de padrao sensivel sem a camada de perfil.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := 'Tabela(s) de padrao sensivel SEM a camada de perfil: ' || v_lista
      || '. Se a tabela guarda dado pessoal identificavel, aplicar a politica '
      || 'perfil_restringe_leitura_<tabela>; se for organizacional, adicionar a lista de '
      || 'excecoes desta rotina com justificativa.';
    r.detalhe := jsonb_build_object('tabelas', v_lista);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $$;

-- ── 2) PERFIL-042: a camada de avaliacoes/metas esta presente e bloqueia ─────
CREATE OR REPLACE FUNCTION public.qa_caso_perfil_042()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
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
  r.passo_acao  := 'AUDITORIA + FUNCIONAL (somente leitura): avaliacoes e metas obedecem ao perfil';
  r.esperado    := 'Trava RESTRICTIVE de leitura em avaliacao_respostas, avaliacao_9box e metas; usuario restrito nao le 9-box alheio';

  FOREACH v_tab IN ARRAY ARRAY['avaliacao_respostas', 'avaliacao_9box', 'metas'] LOOP
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

  -- Prova funcional (opcional): o usuario restrito (so Documentos) nao pode ler
  -- 9-box de ninguem — a tabela nao tem ramo "proprio" nem "avaliador".
  v_uid := (SELECT ub.auth_user_id FROM public.usuarios_base ub
             WHERE ub.email_principal = 'restrito.e2e@youreyes.local' LIMIT 1);
  IF v_uid IS NULL OR to_regprocedure('qa_rls.conta_auth(text)') IS NULL
     OR to_regclass('public.avaliacao_9box') IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Travas conferidas. Falta a prova funcional: semear restrito.e2e@youreyes.local (seed-e2e-user) e ter os ajudantes qa_rls.';
    RETURN r;
  END IF;

  v_total := (xpath('/row/c/text()',
                query_to_xml('SELECT count(*) AS c FROM public.avaliacao_9box', false, true, '')))[1]::text::bigint;
  v_claims := current_setting('request.jwt.claims', true);
  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  v_vis := qa_rls.conta_auth('SELECT count(*) FROM public.avaliacao_9box');
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);

  IF COALESCE(v_vis, 0) > 0 THEN
    r.situacao := 'falhou';
    r.obtido   := 'FALHA GRAVE: o usuario restrito le ' || v_vis || ' linha(s) de avaliacao_9box.';
    r.detalhe  := jsonb_build_object('visiveis', v_vis, 'total', v_total);
  ELSIF v_total = 0 THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Travas presentes, mas nao ha linhas em avaliacao_9box para provar o bloqueio.';
  ELSE
    r.situacao := 'passou';
    r.obtido   := 'Travas presentes; o usuario restrito nao le nenhuma das ' || v_total || ' linha(s) de 9-box.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  BEGIN PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); EXCEPTION WHEN OTHERS THEN NULL; END;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $$;

-- ── 3) Documentacao de testes (qa_casos_teste) ───────────────────────────────
DO $doc$
DECLARE v_mod uuid;
BEGIN
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'seguranca-acesso/perfis' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; casos nao documentados.';
    RETURN;
  END IF;

  -- Conferencia 2 da casa: PERFIL-003 mudou de forma -> atualizar a descricao.
  UPDATE public.qa_casos_teste
     SET objetivo = 'Detectar tabela sensivel (saude, psicossocial, documento, afastamento, '
                 || 'avaliacao ou meta que registre um trabalhador) criada DEPOIS da camada e '
                 || 'que ficou sem a politica restritiva. A sonda varre por dominio de nome; nos '
                 || 'dominios de avaliacao/meta exige uma coluna-sujeito (colaborador_*/avaliado_*) '
                 || 'para nao confundir catalogo/ciclo com registro-sujeito.',
         passos = '[{"ordem":1,"acao":"Varredura por padrao de nome (atestad%, %saude%, psicossocial%, ferias%, afastamento%, documentos) + avaliacao/metas com coluna-sujeito, com tenant_id e RLS","resultado_esperado":"Todas com politica perfil_restringe_leitura_* ou na lista de excecoes documentadas"}]'::jsonb
   WHERE codigo = 'PERFIL-003';

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PERFIL-042',
   'Avaliacoes e metas: leitura por perfil (avaliacao_respostas, avaliacao_9box, metas)',
   'negativo', 'critica', 'aprovado', 'api', 'LGPD arts. 6º, 11 e 46',
   'A Central de Pendencias e os blocos da tela inicial mostravam nome do colaborador, avaliacoes e metas a qualquer membro da empresa (o filtro por perfil daquelas telas era cosmetico; so a RLS protege). Agora: avaliacao_respostas so para o modulo avaliacoes amplo ou para o proprio avaliador; avaliacao_9box so para o modulo avaliacoes amplo; metas so para o modulo avaliacoes/metas amplo ou para a propria meta individual (por CPF).',
   'Script de avaliacoes/metas aplicado; (funcional) usuario restrito semeado.',
   '[{"ordem":1,"acao":"Conferir a politica perfil_restringe_leitura_<tabela> RESTRICTIVE de SELECT em avaliacao_respostas, avaliacao_9box e metas","resultado_esperado":"Presentes"},{"ordem":2,"acao":"Com o usuario restrito (so Documentos), contar linhas visiveis de avaliacao_9box","resultado_esperado":"Zero"}]'::jsonb,
   'Quem nao tem o modulo nao le avaliacao/meta alheia; cada um ve so o que e seu ou o que o perfil da area libera.',
   'Rotina qa_caso_perfil_042 (somente leitura).')
  ON CONFLICT (codigo) DO UPDATE SET
     titulo = EXCLUDED.titulo, objetivo = EXCLUDED.objetivo, passos = EXCLUDED.passos,
     resultado_esperado = EXCLUDED.resultado_esperado, observacoes = EXCLUDED.observacoes;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
    VALUES ('PERFIL-042', 'qa_caso_perfil_042', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao PERFIL-003/042 nao registrada: %', SQLERRM;
END $doc$;

-- ── 4) Rodar a bateria da familia (nao aborta se algo faltar) ────────────────
DO $roda$
BEGIN
  PERFORM public.qa_rodar_bateria('manual', 'seguranca-acesso/perfis');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bateria nao rodou agora (%). As rotinas ficam registradas e entram na proxima execucao.', SQLERRM;
END $roda$;
