-- ============================================================================
-- ENTREGA — Acesso Fase 2c: escrita pelo perfil em EPI, itens da folha, beneficios
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de PRODUCAO.
-- PRE-REQUISITO: script_acesso_fase2b_escrita_pelo_perfil (cria perfil_escreve e
-- os casos PERFIL-012/013, que este arquivo amplia).
--
-- Roda em UMA transacao, idempotente. NAO cria tabela, NAO altera dado: so
-- politicas RESTRICTIVE, duas funcoes de QA e ajuste do texto de dois casos.
--
-- O QUE MUDA: epi_entregas, folha_itens e beneficios_colaboradores passam a exigir
-- o verbo no modulo (criar / editar ou aprovar / excluir) de quem TEM perfil
-- vinculado. Quem NAO tem perfil: nada muda. Super Admin e dono passam.
-- epi_entregas, DELETE: aceita excluir OU criar, porque o assistente de entrega
-- desfaz pelo cliente o registro que acabou de criar (conflito de estoque).
-- ============================================================================

-- ============================================================================
-- Acesso — Fase 2c: escrita pelo perfil em EPI, itens da folha e benefícios
--
-- Segunda fatia da escrita (a primeira, 2b, cobriu férias, ponto e psicossocial).
-- Mesma decisão, perfil_escreve: quem TEM perfil vinculado só grava com o verbo
-- no módulo; quem NÃO tem perfil segue como antes; Super Admin e dono passam.
--
-- Tabelas desta fatia e módulos (espelham a política de LEITURA de cada uma):
--   epi_entregas              sst, colaboradores
--   folha_itens               financeiro, colaboradores
--   beneficios_colaboradores  beneficios, colaboradores
--
-- Verificado antes: nenhuma função SECURITY INVOKER da aplicação grava nelas
-- (só rotinas de QA, que rodam como Super Admin, e excluir_colaborador_forcado,
-- que é SECURITY DEFINER e ignora a RLS).
--
-- ATENÇÃO — epi_entregas, DELETE: o assistente de entrega apaga o registro que
-- ele mesmo acabou de criar quando o estoque entra em conflito ou falha (desfaz
-- a transação pelo cliente). Exigir só 'excluir' deixaria esse desfazer falhar
-- em silêncio para quem tem 'criar' sem 'excluir', e sobraria uma entrega sem
-- baixa de estoque. Por isso, nesta tabela, o DELETE aceita 'excluir' OU 'criar'.
-- É mais frouxo que o ideal e muito mais estreito que o "qualquer membro" de hoje.
--
-- Observação (não alterada aqui): a rota /epis usa o módulo 'epi', mas a leitura
-- de epi_entregas consulta 'sst' e 'colaboradores'. Perfil só com 'epi' abre a
-- tela e não lê as entregas. A escrita acompanha a leitura de propósito.
--
-- Também amplia PERFIL-012 (estrutura) e PERFIL-013 (efeito) para estas tabelas.
-- ============================================================================

SET lock_timeout = '10s';

DO $w$
DECLARE
  r record;
  v_mods text;
  v_del text;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('epi_entregas',             ARRAY['sst', 'colaboradores'],          ARRAY['excluir', 'criar']),
      ('folha_itens',              ARRAY['financeiro', 'colaboradores'],   ARRAY['excluir']),
      ('beneficios_colaboradores', ARRAY['beneficios', 'colaboradores'],   ARRAY['excluir'])
    ) AS t(tabela, modulos, acoes_del)
  LOOP
    BEGIN
      IF to_regclass('public.' || r.tabela) IS NULL THEN
        RAISE NOTICE 'Escrita por perfil: tabela % nao existe; pulada.', r.tabela;
        CONTINUE;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema = 'public' AND table_name = r.tabela
                        AND column_name = 'tenant_id') THEN
        RAISE NOTICE 'Escrita por perfil: % sem tenant_id; pulada.', r.tabela;
        CONTINUE;
      END IF;

      v_mods := quote_literal(r.modulos::text);
      v_del  := quote_literal(r.acoes_del::text);

      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',
                     'perfil_restringe_escrita_' || r.tabela || '_ins', r.tabela);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',
                     'perfil_restringe_escrita_' || r.tabela || '_upd', r.tabela);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',
                     'perfil_restringe_escrita_' || r.tabela || '_del', r.tabela);

      EXECUTE format(
        'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR INSERT TO authenticated '
        || 'WITH CHECK (public.perfil_escreve(tenant_id, %s::text[], ARRAY[''criar'']::text[], NULL::text))',
        'perfil_restringe_escrita_' || r.tabela || '_ins', r.tabela, v_mods);

      EXECUTE format(
        'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR UPDATE TO authenticated '
        || 'USING (public.perfil_escreve(tenant_id, %s::text[], ARRAY[''editar'', ''aprovar'']::text[], NULL::text)) '
        || 'WITH CHECK (public.perfil_escreve(tenant_id, %s::text[], ARRAY[''editar'', ''aprovar'']::text[], NULL::text))',
        'perfil_restringe_escrita_' || r.tabela || '_upd', r.tabela, v_mods, v_mods);

      EXECUTE format(
        'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR DELETE TO authenticated '
        || 'USING (public.perfil_escreve(tenant_id, %s::text[], %s::text[], NULL::text))',
        'perfil_restringe_escrita_' || r.tabela || '_del', r.tabela, v_mods, v_del);

      RAISE NOTICE 'Escrita por perfil aplicada em %.', r.tabela;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ATENCAO: % ficou sem a trava de escrita por perfil: %', r.tabela, SQLERRM;
    END;
  END LOOP;
END $w$;

-- ── QA: PERFIL-012 e PERFIL-013 passam a cobrir também estas tabelas ────────
CREATE OR REPLACE FUNCTION public.qa_caso_perfil_012()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_falhas text[] := ARRAY[]::text[];
  v_tab text;
  v_cmd text;
  v_oid oid;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): travas de escrita por perfil — decisão, 15 tabelas de gestão e 5 endurecidas';
  r.esperado    := 'perfil_escreve SECURITY DEFINER; política RESTRICTIVE de INSERT, UPDATE e DELETE em cada tabela';

  v_oid := to_regprocedure('public.perfil_escreve(uuid,text[],text[],text)');
  IF v_oid IS NULL THEN
    v_falhas := v_falhas || 'função perfil_escreve ausente'::text;
  ELSIF NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_oid) THEN
    v_falhas := v_falhas || 'perfil_escreve não é SECURITY DEFINER'::text;
  END IF;

  FOREACH v_tab IN ARRAY ARRAY[
    'ferias_periodos_aquisitivos', 'ferias_programacao', 'ferias_assinatura_links',
    'folha_ferias_calculo', 'ferias_vinculo_familiar', 'ferias_coletivas',
    'ferias_coletivas_comunicados', 'ponto_espelhos', 'ponto_diario',
    'psicossocial_participacoes', 'questionario_psicossocial_convites', 'psicossocial_entrevistas',
    'epi_entregas', 'folha_itens', 'beneficios_colaboradores'
  ] LOOP
    IF to_regclass('public.' || v_tab) IS NULL THEN
      CONTINUE;
    END IF;
    FOREACH v_cmd IN ARRAY ARRAY['ins', 'upd', 'del'] LOOP
      IF NOT EXISTS (SELECT 1 FROM pg_policies pl
                      WHERE pl.schemaname = 'public' AND pl.tablename = v_tab
                        AND pl.policyname = 'perfil_restringe_escrita_' || v_tab || '_' || v_cmd
                        AND pl.permissive = 'RESTRICTIVE'
                        AND position('perfil_escreve' IN COALESCE(pl.qual, '') || COALESCE(pl.with_check, '')) > 0) THEN
        v_falhas := v_falhas || ('sem a trava de escrita ' || v_cmd || ' em ' || v_tab)::text;
      END IF;
    END LOOP;
  END LOOP;

  FOREACH v_tab IN ARRAY ARRAY[
    'afastamentos_saude', 'psicossocial_entrevistas_evidencias', 'psicossocial_alertas',
    'ferias_alertas', 'ferias_historico'
  ] LOOP
    IF to_regclass('public.' || v_tab) IS NULL THEN
      CONTINUE;
    END IF;
    FOREACH v_cmd IN ARRAY ARRAY['ins', 'upd', 'del'] LOOP
      IF NOT EXISTS (SELECT 1 FROM pg_policies pl
                      WHERE pl.schemaname = 'public' AND pl.tablename = v_tab
                        AND pl.policyname = 'escrita_so_dono_' || v_tab || '_' || v_cmd
                        AND pl.permissive = 'RESTRICTIVE') THEN
        v_falhas := v_falhas || ('escrita direta aberta (' || v_cmd || ') em ' || v_tab)::text;
      END IF;
    END LOOP;
  END LOOP;

  IF COALESCE(array_length(v_falhas, 1), 0) = 0 THEN
    r.situacao := 'passou';
    r.obtido   := 'Decisão de escrita e travas por comando íntegras nas 20 tabelas.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := array_to_string(v_falhas, '; ');
    r.detalhe  := jsonb_build_object('falhas', to_jsonb(v_falhas));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_perfil_013()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  c record;
  v_uid uuid;
  v_tenant uuid;
  v_claims_antes text;
  v_conjunto text;
  v_pode boolean;
  v_liberou text[] := ARRAY[]::text[];
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'FUNCIONAL (somente leitura): usuário só com o Colaborador (padrão) tenta escrever em férias, ponto, EPI, folha e benefícios';
  r.esperado    := 'perfil_escreve = false para criar e excluir em todos os conjuntos de módulos';

  FOR c IN
    SELECT ub.auth_user_id, ub.tenant_id
      FROM public.usuarios_base ub
     WHERE ub.auth_user_id IS NOT NULL
       AND COALESCE(ub.status::text, 'ativo') = 'ativo'
       AND EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v
                     JOIN public.perfis_acesso pa ON pa.id = v.perfil_id
                    WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true) = true
                      AND pa.nome = 'Colaborador (padrão)')
       AND NOT EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v
                         JOIN public.perfis_acesso pa ON pa.id = v.perfil_id
                        WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true) = true
                          AND (v.expira_em IS NULL OR v.expira_em > now())
                          AND pa.nome <> 'Colaborador (padrão)')
       AND NOT EXISTS (SELECT 1 FROM public.perfil_excecoes pe
                        WHERE pe.usuario_id = ub.id AND COALESCE(pe.ativo, true) = true)
       AND NOT EXISTS (SELECT 1 FROM public.user_roles ur
                        WHERE ur.user_id = ub.auth_user_id AND ur.role::text = 'owner')
     LIMIT 25
  LOOP
    IF NOT public.is_superadmin(c.auth_user_id) THEN
      v_uid := c.auth_user_id;
      v_tenant := c.tenant_id;
      EXIT;
    END IF;
  END LOOP;

  IF v_uid IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Nenhum usuário só com o Colaborador (padrão). Crie um usuário de tipo colaborador, sem perfil escolhido.';
    RETURN r;
  END IF;

  v_claims_antes := current_setting('request.jwt.claims', true);
  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  BEGIN
    FOREACH v_conjunto IN ARRAY ARRAY[
      'ferias,colaboradores,ponto',
      'sst,colaboradores',
      'financeiro,colaboradores',
      'beneficios,colaboradores'
    ] LOOP
      v_pode := public.perfil_escreve(v_tenant, string_to_array(v_conjunto, ','),
                                      ARRAY['criar', 'excluir'], NULL);
      IF v_pode IS NOT FALSE THEN
        v_liberou := v_liberou || replace(v_conjunto, ',', '+')::text;
      END IF;
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claims', COALESCE(v_claims_antes, ''), true);
    RAISE;
  END;
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims_antes, ''), true);

  IF COALESCE(array_length(v_liberou, 1), 0) = 0 THEN
    r.situacao := 'passou';
    r.obtido   := 'Usuário só com o Colaborador (padrão) não pode criar nem excluir em férias, ponto, EPI, folha e benefícios.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := 'Usuário só com o Colaborador (padrão) obteve escrita em: ' || array_to_string(v_liberou, ', ') || '.';
    r.detalhe  := jsonb_build_object('conjuntos_liberados', to_jsonb(v_liberou));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $$;

DO $qa$
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL THEN
    RAISE NOTICE 'Motor de QA ausente nesta base; documentacao de PERFIL-012/013 nao atualizada.';
    RETURN;
  END IF;

  UPDATE public.qa_casos_teste
     SET titulo = 'Travas de escrita por perfil presentes nas tabelas de gestão e endurecidas',
         objetivo = 'A camada de perfil só filtrava leitura; a escrita seguia em "qualquer membro". Garante a função de decisão (SECURITY DEFINER) e uma política RESTRICTIVE por comando (INSERT, UPDATE, DELETE) nas 15 tabelas em que só a gestão escreve (férias, ponto, psicossocial, EPI, itens da folha, benefícios) e nas 5 que ninguém grava pelo cliente.',
         resultado_esperado = 'Travas de escrita íntegras nas 20 tabelas.'
   WHERE codigo = 'PERFIL-012';

  UPDATE public.qa_casos_teste
     SET titulo = 'Usuário só com o Colaborador (padrão) não escreve em férias, ponto, EPI, folha nem benefícios',
         objetivo = 'Prova o efeito: quem só tem o perfil de autosserviço (tudo em escopo próprio) não pode criar nem excluir registros de férias, ponto, EPI, itens da folha e benefícios, mesmo sendo membro do cliente (que era o suficiente para gravar pela API).',
         passos = '[{"ordem":1,"acao":"Simular o usuário e chamar perfil_escreve para criar e excluir nos conjuntos de módulos de férias/ponto, EPI, folha e benefícios","resultado_esperado":"Falso em todos"}]'::jsonb
   WHERE codigo = 'PERFIL-013';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao de PERFIL-012/013 nao atualizada: %', SQLERRM;
END $qa$;

DO $roda$
BEGIN
  PERFORM public.qa_rodar_bateria('manual', 'seguranca-acesso/perfis');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bateria nao rodou agora (%). As rotinas ficam registradas e entram na proxima execucao agendada.', SQLERRM;
END $roda$;

-- ── Conferencia (o editor mostra so o ultimo resultado) ─────────────────────
SELECT
  (SELECT count(DISTINCT tablename) FROM pg_policies
    WHERE schemaname = 'public' AND policyname LIKE 'perfil_restringe_escrita\_%')  AS tabelas_de_gestao_esperado_15,
  (SELECT count(DISTINCT tablename) FROM pg_policies
    WHERE schemaname = 'public' AND policyname LIKE 'escrita\_so\_dono\_%')         AS tabelas_endurecidas_esperado_5,
  (public.qa_caso_perfil_012()).situacao::text                                       AS qa_perfil_012,
  (public.qa_caso_perfil_013()).situacao::text                                       AS qa_perfil_013;

-- ── DESFAZER (so se precisar; remove SO as travas desta fase) ───────────────
-- Rode esta consulta: ela GERA os comandos DROP POLICY. Copie o resultado e rode.
-- SELECT format('DROP POLICY IF EXISTS %I ON %I.%I;', policyname, schemaname, tablename) AS comando
--   FROM pg_policies
--  WHERE schemaname = 'public'
--    AND tablename IN ('epi_entregas', 'folha_itens', 'beneficios_colaboradores')
--    AND policyname LIKE 'perfil_restringe_escrita\_%'
--  ORDER BY tablename, policyname;

-- ── PRE-CHECAGEM (so leitura; cole separado ANTES, se quiser ver o impacto) ─
-- Perfis ESCOLHIDOS com acesso amplo aos modulos destas tabelas, mas sem todos os
-- verbos de escrita: quem os tem perderia o verbo que falta.
-- SELECT ub.tenant_id, pa.nome AS perfil, pp.modulo,
--        string_agg(DISTINCT pp.acao::text, ',' ORDER BY pp.acao::text) AS verbos,
--        count(DISTINCT ub.id) AS usuarios
--   FROM public.usuarios_base ub
--   JOIN public.usuario_perfil_vinculos v ON v.usuario_id = ub.id AND COALESCE(v.ativo, true)
--   JOIN public.perfis_acesso pa ON pa.id = v.perfil_id AND COALESCE(pa.tipo::text, '') <> 'padrao_sistema'
--   JOIN public.perfil_permissoes pp ON pp.perfil_id = pa.id AND COALESCE(pp.ativo, true)
--        AND pp.modulo IN ('sst','financeiro','beneficios','colaboradores')
--        AND COALESCE(pp.escopo::text, '') <> 'proprio_usuario'
--  GROUP BY ub.tenant_id, pa.nome, pp.modulo
-- HAVING NOT bool_or(pp.acao::text = 'administrar')
--    AND NOT (bool_or(pp.acao::text = 'criar') AND bool_or(pp.acao::text = 'editar') AND bool_or(pp.acao::text = 'excluir'))
--  ORDER BY 5 DESC;
