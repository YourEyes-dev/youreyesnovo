-- ============================================================================
-- Acesso — Fase 2e: escrita pelo perfil no 13º salário e nas rescisões
--
-- Quarta fatia da escrita (2b: férias/ponto/psicossocial; 2c: EPI, folha,
-- benefícios; 2d: solicitação de férias). Mesma decisão, perfil_escreve: quem TEM
-- perfil vinculado só grava com o verbo no módulo; quem NÃO tem perfil segue como
-- antes; Super Admin e dono passam.
--
-- Tabelas e módulos (os mesmos da política de leitura de cada uma):
--   folha_13_calculo   financeiro, colaboradores
--   folha_rescisoes    financeiro, colaboradores
-- INSERT exige 'criar'; UPDATE 'editar' ou 'aprovar'; DELETE 'excluir'.
--
-- AS ROTINAS DO 13º RODAM COMO O USUÁRIO. decimo_terceiro_lote, _adiantamento_nas_
-- ferias, _aprovar, _pagar e _reabrir são SECURITY INVOKER: passam pela política
-- nova. Verificado: elas gravam só em folha_13_calculo (nenhuma cascata para outra
-- tabela) e os gatilhos das duas tabelas só calculam/validam (não gravam em outro
-- lugar). Consequência prática: processar o 13º em lote, que faz inserir e
-- atualizar na mesma chamada (upsert), exige 'criar' E 'editar' no perfil.
--
-- O VERBO "APROVAR" NO 13º. As funções _aprovar, _pagar e _reabrir existem como API
-- (o cliente hoje só chama _lote e _adiantamento_nas_ferias) e não têm nenhuma
-- checagem de permissão dentro: qualquer membro do cliente podia aprovar e pagar um
-- 13º. A política já estreita quem tem perfil; um gatilho BEFORE UPDATE OF status
-- torna real o verbo: passar um cálculo para 'aprovado' exige 'aprovar'. Só vale
-- com sessão de usuário (auth.uid presente): rotina automática e função de borda
-- não são barradas. Pagar e reabrir seguem exigindo 'editar' (não há verbo próprio).
--
-- QA: DEC13-080 (efeito do verbo aprovar) e PERFIL-012 ampliado para 23 tabelas.
-- ============================================================================

SET lock_timeout = '10s';

-- ── 1) Políticas RESTRICTIVE por comando ────────────────────────────────────
DO $w$
DECLARE
  v_tab text;
BEGIN
  IF to_regprocedure('public.perfil_escreve(uuid,text[],text[],text)') IS NULL THEN
    RAISE NOTICE 'perfil_escreve ausente; escrita nao ajustada.';
    RETURN;
  END IF;

  FOREACH v_tab IN ARRAY ARRAY['folha_13_calculo', 'folha_rescisoes'] LOOP
    BEGIN
      IF to_regclass('public.' || v_tab) IS NULL THEN
        RAISE NOTICE 'Escrita por perfil: tabela % nao existe; pulada.', v_tab;
        CONTINUE;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema = 'public' AND table_name = v_tab
                        AND column_name = 'tenant_id') THEN
        RAISE NOTICE 'Escrita por perfil: % sem tenant_id; pulada.', v_tab;
        CONTINUE;
      END IF;

      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'perfil_restringe_escrita_' || v_tab || '_ins', v_tab);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'perfil_restringe_escrita_' || v_tab || '_upd', v_tab);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'perfil_restringe_escrita_' || v_tab || '_del', v_tab);

      EXECUTE format(
        'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR INSERT TO authenticated '
        || 'WITH CHECK (public.perfil_escreve(tenant_id, ARRAY[''financeiro'', ''colaboradores'']::text[], ARRAY[''criar'']::text[], NULL::text))',
        'perfil_restringe_escrita_' || v_tab || '_ins', v_tab);
      EXECUTE format(
        'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR UPDATE TO authenticated '
        || 'USING (public.perfil_escreve(tenant_id, ARRAY[''financeiro'', ''colaboradores'']::text[], ARRAY[''editar'', ''aprovar'']::text[], NULL::text)) '
        || 'WITH CHECK (public.perfil_escreve(tenant_id, ARRAY[''financeiro'', ''colaboradores'']::text[], ARRAY[''editar'', ''aprovar'']::text[], NULL::text))',
        'perfil_restringe_escrita_' || v_tab || '_upd', v_tab);
      EXECUTE format(
        'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR DELETE TO authenticated '
        || 'USING (public.perfil_escreve(tenant_id, ARRAY[''financeiro'', ''colaboradores'']::text[], ARRAY[''excluir'']::text[], NULL::text))',
        'perfil_restringe_escrita_' || v_tab || '_del', v_tab);

      RAISE NOTICE 'Escrita por perfil aplicada em %.', v_tab;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ATENCAO: % ficou sem a trava de escrita por perfil: %', v_tab, SQLERRM;
    END;
  END LOOP;
END $w$;

-- ── 2) Aprovar um 13º exige o verbo "aprovar" ───────────────────────────────
CREATE OR REPLACE FUNCTION public.decimo_terceiro_aprovacao_exige_aprovar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $fn$
BEGIN
  -- Sem sessão de usuário (rotina automática, função de borda): não se aplica.
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'aprovado' AND OLD.status IS DISTINCT FROM 'aprovado' THEN
    IF NOT public.perfil_escreve(NEW.tenant_id, ARRAY['financeiro', 'colaboradores']::text[],
                                 ARRAY['aprovar']::text[], NULL::text) THEN
      RAISE EXCEPTION 'Sem permissão para aprovar o 13º salário: o seu perfil não tem a ação Aprovar no módulo Financeiro.'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN NEW;
END
$fn$;

DO $t$
BEGIN
  IF to_regclass('public.folha_13_calculo') IS NULL THEN
    RAISE NOTICE 'folha_13_calculo nao existe; gatilho nao criado.';
    RETURN;
  END IF;
  DROP TRIGGER IF EXISTS trg_decimo_terceiro_aprovacao_exige_aprovar ON public.folha_13_calculo;
  CREATE TRIGGER trg_decimo_terceiro_aprovacao_exige_aprovar
    BEFORE UPDATE OF status ON public.folha_13_calculo
    FOR EACH ROW EXECUTE FUNCTION public.decimo_terceiro_aprovacao_exige_aprovar();
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENCAO: gatilho da aprovacao do 13o nao criado: %', SQLERRM;
END $t$;

-- ── 3) QA: PERFIL-012 passa a auditar as duas tabelas ───────────────────────
DO $q12$
DECLARE
  v_def text;
  v_novo text;
BEGIN
  IF to_regprocedure('public.qa_caso_perfil_012()') IS NULL THEN
    RAISE NOTICE 'qa_caso_perfil_012 ausente; nao ajustada.';
    RETURN;
  END IF;
  v_def := pg_get_functiondef(to_regprocedure('public.qa_caso_perfil_012()'));
  v_novo := replace(v_def, $a$'beneficios_colaboradores', 'ferias_solicitacoes'$a$,
                           $b$'beneficios_colaboradores', 'ferias_solicitacoes', 'folha_13_calculo', 'folha_rescisoes'$b$);
  v_novo := replace(v_novo, '16 tabelas de gestão', '18 tabelas de gestão');
  v_novo := replace(v_novo, 'nas 21 tabelas', 'nas 23 tabelas');
  IF v_novo = v_def THEN
    RAISE NOTICE 'qa_caso_perfil_012 ja cobre 13o e rescisoes (ou o trecho nao foi achado).';
  ELSE
    EXECUTE v_novo;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'qa_caso_perfil_012 nao ajustada: %', SQLERRM;
END $q12$;

-- ── 4) QA: DEC13-080 — o verbo "aprovar" vale para o 13º ────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_080()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  c record;
  v_falhas text[] := ARRAY[]::text[];
  v_tab text;
  v_cmd text;
  v_uid uuid;
  v_tenant uuid;
  v_claims_antes text;
  v_edita boolean;
  v_aprova boolean;
  v_funcional text := 'Sem usuário com perfil Financeiro que edite e não aprove, para a prova funcional; a estrutura foi conferida.';
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA + FUNCIONAL (somente leitura): travas de escrita do 13º e das rescisões e o verbo Aprovar';
  r.esperado    := 'Política RESTRICTIVE por comando nas duas tabelas e gatilho de aprovação presentes; perfil que edita e não aprova não aprova o 13º';

  FOREACH v_tab IN ARRAY ARRAY['folha_13_calculo', 'folha_rescisoes'] LOOP
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

  IF to_regclass('public.folha_13_calculo') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM pg_trigger t
                      WHERE t.tgname = 'trg_decimo_terceiro_aprovacao_exige_aprovar'
                        AND t.tgrelid = to_regclass('public.folha_13_calculo')
                        AND t.tgenabled <> 'D' AND NOT t.tgisinternal) THEN
    v_falhas := v_falhas || 'gatilho trg_decimo_terceiro_aprovacao_exige_aprovar ausente ou desabilitado'::text;
  END IF;

  IF COALESCE(array_length(v_falhas, 1), 0) = 0 THEN
    FOR c IN
      SELECT ub.auth_user_id, ub.tenant_id
        FROM public.usuarios_base ub
       WHERE ub.auth_user_id IS NOT NULL
         AND COALESCE(ub.status::text, 'ativo') = 'ativo'
         AND EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v
                       JOIN public.perfil_permissoes pp ON pp.perfil_id = v.perfil_id
                        AND COALESCE(pp.ativo, true) = true
                        AND pp.modulo IN ('financeiro', 'colaboradores')
                        AND pp.acao::text = 'editar'
                        AND COALESCE(pp.escopo::text, '') NOT IN ('proprio_usuario', 'subordinados_diretos')
                      WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true) = true)
         AND NOT EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v
                           JOIN public.perfil_permissoes pp ON pp.perfil_id = v.perfil_id
                            AND COALESCE(pp.ativo, true) = true
                            AND pp.modulo IN ('financeiro', 'colaboradores')
                            AND pp.acao::text IN ('aprovar', 'administrar')
                          WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true) = true)
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

    IF v_uid IS NOT NULL THEN
      v_claims_antes := current_setting('request.jwt.claims', true);
      PERFORM set_config('request.jwt.claims',
                         json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
      BEGIN
        v_edita  := public.perfil_escreve(v_tenant, ARRAY['financeiro', 'colaboradores'], ARRAY['editar'], NULL);
        v_aprova := public.perfil_escreve(v_tenant, ARRAY['financeiro', 'colaboradores'], ARRAY['aprovar'], NULL);
      EXCEPTION WHEN OTHERS THEN
        PERFORM set_config('request.jwt.claims', COALESCE(v_claims_antes, ''), true);
        RAISE;
      END;
      PERFORM set_config('request.jwt.claims', COALESCE(v_claims_antes, ''), true);

      IF v_edita IS NOT TRUE THEN
        v_falhas := v_falhas || 'usuário com Editar não consegue editar o 13º'::text;
      END IF;
      IF v_aprova IS NOT FALSE THEN
        v_falhas := v_falhas || 'usuário com Editar, sem Aprovar, obteve a ação Aprovar'::text;
      END IF;
      IF COALESCE(array_length(v_falhas, 1), 0) = 0 THEN
        v_funcional := 'Prova funcional: perfil que edita e não aprova edita, mas não obtém Aprovar.';
      END IF;
    END IF;
  END IF;

  IF COALESCE(array_length(v_falhas, 1), 0) = 0 THEN
    r.situacao := 'passou';
    r.obtido   := 'Travas e gatilho do 13º e das rescisões íntegros. ' || v_funcional;
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

DO $qa$
DECLARE v_mod uuid;
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL OR to_regclass('public.qa_modulos') IS NULL THEN
    RAISE NOTICE 'Motor de QA ausente nesta base; caso DEC13-080 nao documentado.';
    RETURN;
  END IF;

  UPDATE public.qa_casos_teste
     SET objetivo = 'A camada de perfil só filtrava leitura; a escrita seguia em "qualquer membro". Garante a função de decisão (SECURITY DEFINER) e uma política RESTRICTIVE por comando (INSERT, UPDATE, DELETE) nas 18 tabelas em que só a gestão escreve (férias, solicitação de férias, ponto, psicossocial, EPI, itens da folha, benefícios, 13º salário e rescisões) e nas 5 que ninguém grava pelo cliente.',
         resultado_esperado = 'Travas de escrita íntegras nas 23 tabelas.'
   WHERE codigo = 'PERFIL-012';

  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'financeiro/decimo-terceiro' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo financeiro/decimo-terceiro ausente; caso DEC13-080 nao documentado.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado)
  VALUES
  (v_mod, 'DEC13-080', 'Aprovar o 13º exige o verbo Aprovar do perfil; rescisão e 13º só são gravados por perfil com permissão',
   'negativo', 'alta', 'aprovado', 'api',
   'LGPD, art. 46; Lei 4.749/1965 (13º salário)',
   'O 13º e as rescisões eram graváveis por qualquer membro do cliente, e as funções de aprovar, pagar e reabrir o 13º (SECURITY INVOKER) não checavam permissão. A trava de escrita por perfil cobre as duas tabelas e um gatilho exige a ação Aprovar para passar um cálculo a aprovado. Rotinas automáticas, sem sessão de usuário, não são barradas. Processar o 13º em lote (inserir e atualizar) exige Criar e Editar.',
   'Fase 2e aplicada.',
   '[{"ordem":1,"acao":"Conferir as políticas RESTRICTIVE de INSERT, UPDATE e DELETE de folha_13_calculo e folha_rescisoes e o gatilho de aprovação","resultado_esperado":"Presentes e habilitados"},
     {"ordem":2,"acao":"Simular um usuário cujo perfil tem Editar (escopo amplo) em Financeiro e não tem Aprovar, e chamar a decisão de escrita para editar e para aprovar","resultado_esperado":"Editar permitido; Aprovar negado"}]',
   'Quem edita sem Aprovar não aprova o 13º.')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
      ('DEC13-080', 'qa_caso_dec13_080', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao DEC13-080 nao registrada: %', SQLERRM;
END $qa$;

DO $roda$
BEGIN
  PERFORM public.qa_rodar_bateria('manual', 'financeiro/decimo-terceiro');
  PERFORM public.qa_rodar_bateria('manual', 'seguranca-acesso/perfis');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bateria nao rodou agora (%). As rotinas ficam registradas e entram na proxima execucao agendada.', SQLERRM;
END $roda$;
