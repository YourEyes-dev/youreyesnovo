-- ============================================================================
-- ENTREGA — Acesso Fase 2d: escrita pelo perfil na SOLICITACAO DE FERIAS
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de PRODUCAO.
-- PRE-REQUISITO: script_acesso_fase2b_escrita_pelo_perfil (cria perfil_escreve e o
-- PERFIL-012, que este arquivo amplia). Se a 2b nao foi aplicada, este arquivo
-- avisa e nao cria as travas.
--
-- Roda em UMA transacao, idempotente. NAO cria tabela, NAO altera dado.
--
-- O QUE MUDA: ferias_solicitacoes passa a exigir o verbo no modulo (criar /
-- editar ou aprovar / excluir) de quem TEM perfil vinculado; quem NAO tem perfil
-- segue como antes. Alem disso, DECIDIR um pedido pendente (pendente para
-- aprovado ou recusado) exige o verbo APROVAR (e, para o gestor de subordinados,
-- que o pedido seja de um subordinado). So vale para sessao de usuario: rotinas
-- automaticas e funcoes de borda nao sao barradas.
-- Inclui o caso de QA FER-070 e amplia o PERFIL-012 para 21 tabelas.
-- ============================================================================

-- ============================================================================
-- Acesso — Fase 2d: escrita pelo perfil na SOLICITAÇÃO DE FÉRIAS
--
-- Terceira fatia da escrita (2b: férias/ponto/psicossocial; 2c: EPI, folha,
-- benefícios). Mesma decisão, perfil_escreve: quem TEM perfil vinculado só grava
-- com o verbo no módulo; quem NÃO tem perfil segue como antes; Super Admin e dono
-- passam; o gestor imediato com escopo "subordinados diretos" só atua na
-- solicitação de um subordinado seu.
--
-- Tabela: ferias_solicitacoes, módulos ferias e colaboradores (os mesmos da
-- leitura). INSERT exige 'criar'; UPDATE 'editar' ou 'aprovar'; DELETE 'excluir'.
--
-- O VERBO "APROVAR" DE VERDADE. Uma política RESTRICTIVE só enxerga a linha nova,
-- então não distingue "editar um campo" de "decidir o pedido". Um gatilho
-- BEFORE UPDATE fecha essa lacuna: a decisão sobre um pedido PENDENTE (passar de
-- pendente para aprovado ou recusado) exige o verbo 'aprovar' — e, para o gestor
-- de subordinados, que o pedido seja de um subordinado dele. Só vale para sessão
-- de usuário (auth.uid presente): rotina automática e função de borda, sem
-- sessão, não são barradas (a RLS também não se aplica a elas).
-- Verificado: nenhuma função do sistema leva um pedido de pendente direto para
-- aprovado/recusado (elas movem entre aprovado, em gozo, suspenso, concluído e
-- cancelado), então os fluxos automáticos não passam por esta checagem.
--
-- Verificado também: nenhuma função SECURITY INVOKER da aplicação grava nas
-- tabelas travadas (o gatilho de histórico e os de status são SECURITY DEFINER).
--
-- QA: FER-070 (efeito do verbo aprovar) e PERFIL-012 ampliado para 21 tabelas.
-- ============================================================================

SET lock_timeout = '10s';

-- ── 1) Políticas RESTRICTIVE por comando ────────────────────────────────────
DO $w$
DECLARE
  v_cpf text;
BEGIN
  IF to_regclass('public.ferias_solicitacoes') IS NULL
     OR to_regprocedure('public.perfil_escreve(uuid,text[],text[],text)') IS NULL THEN
    RAISE NOTICE 'ferias_solicitacoes ou perfil_escreve ausente; escrita nao ajustada.';
    RETURN;
  END IF;

  v_cpf := CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns
                              WHERE table_schema = 'public' AND table_name = 'ferias_solicitacoes'
                                AND column_name = 'colaborador_cpf')
                THEN 'colaborador_cpf' ELSE 'NULL::text' END;

  DROP POLICY IF EXISTS perfil_restringe_escrita_ferias_solicitacoes_ins ON public.ferias_solicitacoes;
  DROP POLICY IF EXISTS perfil_restringe_escrita_ferias_solicitacoes_upd ON public.ferias_solicitacoes;
  DROP POLICY IF EXISTS perfil_restringe_escrita_ferias_solicitacoes_del ON public.ferias_solicitacoes;

  EXECUTE format(
    'CREATE POLICY perfil_restringe_escrita_ferias_solicitacoes_ins ON public.ferias_solicitacoes '
    || 'AS RESTRICTIVE FOR INSERT TO authenticated '
    || 'WITH CHECK (public.perfil_escreve(tenant_id, ARRAY[''ferias'', ''colaboradores'']::text[], ARRAY[''criar'']::text[], %s))',
    v_cpf);
  EXECUTE format(
    'CREATE POLICY perfil_restringe_escrita_ferias_solicitacoes_upd ON public.ferias_solicitacoes '
    || 'AS RESTRICTIVE FOR UPDATE TO authenticated '
    || 'USING (public.perfil_escreve(tenant_id, ARRAY[''ferias'', ''colaboradores'']::text[], ARRAY[''editar'', ''aprovar'']::text[], %s)) '
    || 'WITH CHECK (public.perfil_escreve(tenant_id, ARRAY[''ferias'', ''colaboradores'']::text[], ARRAY[''editar'', ''aprovar'']::text[], %s))',
    v_cpf, v_cpf);
  EXECUTE format(
    'CREATE POLICY perfil_restringe_escrita_ferias_solicitacoes_del ON public.ferias_solicitacoes '
    || 'AS RESTRICTIVE FOR DELETE TO authenticated '
    || 'USING (public.perfil_escreve(tenant_id, ARRAY[''ferias'', ''colaboradores'']::text[], ARRAY[''excluir'']::text[], %s))',
    v_cpf);
  RAISE NOTICE 'Escrita por perfil aplicada em ferias_solicitacoes.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENCAO: ferias_solicitacoes ficou sem a trava de escrita por perfil: %', SQLERRM;
END $w$;

-- ── 2) Decidir um pedido pendente exige o verbo "aprovar" ───────────────────
CREATE OR REPLACE FUNCTION public.ferias_decisao_exige_aprovar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $fn$
BEGIN
  -- Sem sessão de usuário (rotina automática, função de borda): não se aplica.
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  IF OLD.status = 'pendente' AND NEW.status IN ('aprovado', 'recusado') THEN
    IF NOT public.perfil_escreve(NEW.tenant_id, ARRAY['ferias', 'colaboradores']::text[],
                                 ARRAY['aprovar']::text[], NEW.colaborador_cpf) THEN
      RAISE EXCEPTION 'Sem permissão para aprovar ou recusar férias: o seu perfil não tem a ação Aprovar neste módulo (ou o pedido não é de um subordinado seu).'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN NEW;
END
$fn$;

DO $t$
BEGIN
  IF to_regclass('public.ferias_solicitacoes') IS NULL THEN
    RAISE NOTICE 'ferias_solicitacoes nao existe; gatilho nao criado.';
    RETURN;
  END IF;
  DROP TRIGGER IF EXISTS trg_ferias_decisao_exige_aprovar ON public.ferias_solicitacoes;
  CREATE TRIGGER trg_ferias_decisao_exige_aprovar
    BEFORE UPDATE OF status ON public.ferias_solicitacoes
    FOR EACH ROW EXECUTE FUNCTION public.ferias_decisao_exige_aprovar();
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENCAO: gatilho da decisao de ferias nao criado: %', SQLERRM;
END $t$;

-- ── 3) QA: PERFIL-012 passa a auditar ferias_solicitacoes ───────────────────
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
  v_novo := replace(v_def, $a$'epi_entregas', 'folha_itens', 'beneficios_colaboradores'$a$,
                           $b$'epi_entregas', 'folha_itens', 'beneficios_colaboradores', 'ferias_solicitacoes'$b$);
  v_novo := replace(v_novo, '15 tabelas de gestão', '16 tabelas de gestão');
  v_novo := replace(v_novo, 'nas 20 tabelas', 'nas 21 tabelas');
  IF v_novo = v_def THEN
    RAISE NOTICE 'qa_caso_perfil_012 ja cobre ferias_solicitacoes (ou o trecho nao foi achado).';
  ELSE
    EXECUTE v_novo;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'qa_caso_perfil_012 nao ajustada: %', SQLERRM;
END $q12$;

-- ── 4) QA: FER-070 — o verbo "aprovar" é real ───────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_fer_070()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  c record;
  v_falhas text[] := ARRAY[]::text[];
  v_cmd text;
  v_uid uuid;
  v_tenant uuid;
  v_claims_antes text;
  v_edita boolean;
  v_aprova boolean;
  v_funcional text := 'Sem usuário com perfil de Férias que edite e não aprove, para a prova funcional; a estrutura foi conferida.';
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA + FUNCIONAL (somente leitura): travas de escrita da solicitação de férias e o verbo Aprovar';
  r.esperado    := 'Política RESTRICTIVE por comando e gatilho de decisão presentes; perfil que edita e não aprova não decide pedido';

  FOREACH v_cmd IN ARRAY ARRAY['ins', 'upd', 'del'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_policies pl
                    WHERE pl.schemaname = 'public' AND pl.tablename = 'ferias_solicitacoes'
                      AND pl.policyname = 'perfil_restringe_escrita_ferias_solicitacoes_' || v_cmd
                      AND pl.permissive = 'RESTRICTIVE'
                      AND position('perfil_escreve' IN COALESCE(pl.qual, '') || COALESCE(pl.with_check, '')) > 0) THEN
      v_falhas := v_falhas || ('sem a trava de escrita ' || v_cmd || ' em ferias_solicitacoes')::text;
    END IF;
  END LOOP;

  IF NOT EXISTS (SELECT 1 FROM pg_trigger t
                  WHERE t.tgname = 'trg_ferias_decisao_exige_aprovar'
                    AND t.tgrelid = to_regclass('public.ferias_solicitacoes')
                    AND t.tgenabled <> 'D' AND NOT t.tgisinternal) THEN
    v_falhas := v_falhas || 'gatilho trg_ferias_decisao_exige_aprovar ausente ou desabilitado'::text;
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
                        AND pp.modulo IN ('ferias', 'colaboradores')
                        AND pp.acao::text = 'editar'
                        AND COALESCE(pp.escopo::text, '') NOT IN ('proprio_usuario', 'subordinados_diretos')
                      WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true) = true)
         AND NOT EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v
                           JOIN public.perfil_permissoes pp ON pp.perfil_id = v.perfil_id
                            AND COALESCE(pp.ativo, true) = true
                            AND pp.modulo IN ('ferias', 'colaboradores')
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
        v_edita  := public.perfil_escreve(v_tenant, ARRAY['ferias', 'colaboradores'], ARRAY['editar'], NULL);
        v_aprova := public.perfil_escreve(v_tenant, ARRAY['ferias', 'colaboradores'], ARRAY['aprovar'], NULL);
      EXCEPTION WHEN OTHERS THEN
        PERFORM set_config('request.jwt.claims', COALESCE(v_claims_antes, ''), true);
        RAISE;
      END;
      PERFORM set_config('request.jwt.claims', COALESCE(v_claims_antes, ''), true);

      IF v_edita IS NOT TRUE THEN
        v_falhas := v_falhas || 'usuário com Editar não consegue editar solicitação'::text;
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
    r.obtido   := 'Travas e gatilho da solicitação de férias íntegros. ' || v_funcional;
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
    RAISE NOTICE 'Motor de QA ausente nesta base; caso FER-070 nao documentado.';
    RETURN;
  END IF;

  UPDATE public.qa_casos_teste
     SET objetivo = 'A camada de perfil só filtrava leitura; a escrita seguia em "qualquer membro". Garante a função de decisão (SECURITY DEFINER) e uma política RESTRICTIVE por comando (INSERT, UPDATE, DELETE) nas 16 tabelas em que só a gestão escreve (férias, solicitação de férias, ponto, psicossocial, EPI, itens da folha, benefícios) e nas 5 que ninguém grava pelo cliente.',
         resultado_esperado = 'Travas de escrita íntegras nas 21 tabelas.'
   WHERE codigo = 'PERFIL-012';

  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'jornada-rotina/ferias' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo jornada-rotina/ferias ausente; caso FER-070 nao documentado.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado)
  VALUES
  (v_mod, 'FER-070', 'Decidir um pedido de férias pendente exige o verbo Aprovar do perfil',
   'negativo', 'alta', 'aprovado', 'api',
   'LGPD, art. 46; CLT arts. 134 a 137 (concessão das férias)',
   'A solicitação de férias era gravável por qualquer membro do cliente, e a política de escrita não distingue editar um campo de decidir o pedido. A trava de escrita por perfil cobre a tabela e um gatilho exige a ação Aprovar para passar um pedido de pendente a aprovado ou recusado (para o gestor de subordinados, só de um subordinado seu). Rotinas automáticas, sem sessão de usuário, não são barradas.',
   'Fase 2d aplicada.',
   '[{"ordem":1,"acao":"Conferir as políticas RESTRICTIVE de INSERT, UPDATE e DELETE de ferias_solicitacoes e o gatilho de decisão","resultado_esperado":"Presentes e habilitados"},
     {"ordem":2,"acao":"Simular um usuário cujo perfil tem Editar (escopo amplo) em Férias e não tem Aprovar, e chamar a decisão de escrita para editar e para aprovar","resultado_esperado":"Editar permitido; Aprovar negado"}]',
   'Quem edita sem Aprovar não decide pedido de férias.')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
      ('FER-070', 'qa_caso_fer_070', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao FER-070 nao registrada: %', SQLERRM;
END $qa$;

DO $roda$
BEGIN
  PERFORM public.qa_rodar_bateria('manual', 'jornada-rotina/ferias');
  PERFORM public.qa_rodar_bateria('manual', 'seguranca-acesso/perfis');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bateria nao rodou agora (%). As rotinas ficam registradas e entram na proxima execucao agendada.', SQLERRM;
END $roda$;

-- ── Conferencia (o editor mostra so o ultimo resultado) ─────────────────────
SELECT
  (SELECT count(*) FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'ferias_solicitacoes'
      AND policyname LIKE 'perfil_restringe_escrita\_ferias\_solicitacoes\_%')  AS politicas_esperado_3,
  (SELECT count(*) FROM pg_trigger
    WHERE tgname = 'trg_ferias_decisao_exige_aprovar' AND NOT tgisinternal)      AS gatilho_esperado_1,
  (public.qa_caso_fer_070()).situacao::text                                      AS qa_fer_070,
  (public.qa_caso_perfil_012()).situacao::text                                   AS qa_perfil_012;

-- ── DESFAZER (so se precisar; remove SO o que esta fase criou) ──────────────
-- Rode, em separado:
-- DROP TRIGGER IF EXISTS trg_ferias_decisao_exige_aprovar ON public.ferias_solicitacoes;
-- DROP POLICY IF EXISTS perfil_restringe_escrita_ferias_solicitacoes_ins ON public.ferias_solicitacoes;
-- DROP POLICY IF EXISTS perfil_restringe_escrita_ferias_solicitacoes_upd ON public.ferias_solicitacoes;
-- DROP POLICY IF EXISTS perfil_restringe_escrita_ferias_solicitacoes_del ON public.ferias_solicitacoes;

-- ── PRE-CHECAGEM (so leitura; cole separado ANTES, se quiser ver o impacto) ─
-- (a) Perfis ESCOLHIDOS que editam Ferias mas NAO tem Aprovar: quem os tem
--     deixaria de conseguir aprovar ou recusar pedidos pendentes.
-- SELECT ub.tenant_id, pa.nome AS perfil,
--        string_agg(DISTINCT pp.acao::text, ',' ORDER BY pp.acao::text) AS verbos,
--        count(DISTINCT ub.id) AS usuarios
--   FROM public.usuarios_base ub
--   JOIN public.usuario_perfil_vinculos v ON v.usuario_id = ub.id AND COALESCE(v.ativo, true)
--   JOIN public.perfis_acesso pa ON pa.id = v.perfil_id AND COALESCE(pa.tipo::text, '') <> 'padrao_sistema'
--   JOIN public.perfil_permissoes pp ON pp.perfil_id = pa.id AND COALESCE(pp.ativo, true)
--        AND pp.modulo IN ('ferias', 'colaboradores')
--        AND COALESCE(pp.escopo::text, '') <> 'proprio_usuario'
--  GROUP BY ub.tenant_id, pa.nome
-- HAVING bool_or(pp.acao::text = 'editar')
--    AND NOT bool_or(pp.acao::text IN ('aprovar', 'administrar'))
--  ORDER BY 4 DESC;
-- (b) Perfis escolhidos com acesso a Ferias sem todos os verbos de escrita:
--     veja a pre-checagem da Fase 2b (a mesma lista de modulos de ferias).
