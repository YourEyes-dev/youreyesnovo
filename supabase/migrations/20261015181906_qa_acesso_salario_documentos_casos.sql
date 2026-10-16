-- ============================================================================
-- QA — casos pendentes: Acesso (Fases 1a/1b), "pode ver salário" e Documentos
-- com escopo "próprio usuário"
--
-- Premissa da casa: toda alteração de recurso passa pela Documentação de Testes
-- (qa_casos_teste) e pela Execução de Testes (rotina qa_caso_<x> no motor SQL).
-- Estas entregas saíram sem isso; esta migration quita a dívida.
--
-- NÍVEL api (rotina no motor, somente leitura):
--   PERFIL-008  perfil vinculado manda: gestão com perfil próprio não é ampla
--   PERFIL-009  tipo vira modelo: funções, gatilhos e conjunto de tipos
--   PERFIL-010  "pode ver salário": flag, verificador, views, gatilhos, folha
--   PERFIL-011  "pode ver salário": usuário sem permissão não recebe salário
--   DOC-050     Documentos: camada de perfil em pastas e documentos
--   DOC-051     Documentos: usuário próprio só alcança a própria subárvore
--
-- NÍVEL e2e (só documentado): DOC-052 e DOC-053. A prova de tela exige uma
-- SEGUNDA conta de robô com o módulo no escopo próprio (a suíte hoje usa só a
-- conta de Super Admin, que enxerga tudo por desenho). Sem essa conta não se
-- escreve o it(): a guarda do Cypress apenas avisa de caso e2e sem teste.
--
-- As rotinas simulam o usuário por claims dentro da transação (padrão do
-- PERFIL-004) e restauram os claims em qualquer saída. Sem massa para o teste
-- funcional, devolvem nao_implementado com o que criar (padrão PERFIL-004).
-- ============================================================================

SET lock_timeout = '10s';

-- ── PERFIL-008 ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_perfil_008()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  c record;
  v_falhas text[] := ARRAY[]::text[];
  v_fn text;
  v_def text;
  v_uid uuid;
  v_tenant uuid;
  v_claims_antes text;
  v_amplo boolean;
  v_funcional text := 'Sem usuário de gestão com perfil próprio para a prova funcional (a estrutura foi conferida).';
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA + FUNCIONAL (somente leitura): o perfil vinculado manda sobre papel/tipo de gestão';
  r.esperado    := 'Funções centrais usam v_tem_perfil e o dono estrito; gestão com perfil só próprio NÃO obtém acesso amplo';

  -- 1) Estrutura: as duas funções centrais carregam a regra
  FOREACH v_fn IN ARRAY ARRAY['public.perfil_permite_modulo(uuid,text[])',
                              'public.perfil_amplo_sem_subordinados(uuid,text[])'] LOOP
    IF to_regprocedure(v_fn) IS NULL THEN
      v_falhas := v_falhas || (v_fn || ' ausente');
      CONTINUE;
    END IF;
    v_def := pg_get_functiondef(to_regprocedure(v_fn));
    IF position('v_tem_perfil' IN v_def) = 0 THEN
      v_falhas := v_falhas || (v_fn || ' sem a trava de perfil vinculado (v_tem_perfil)');
    END IF;
    IF position('ye_eh_dono' IN v_def) = 0 THEN
      v_falhas := v_falhas || (v_fn || ' sem o dono estrito (ye_eh_dono)');
    END IF;
    IF position('''owner''::public.app_role' IN v_def) > 0 THEN
      v_falhas := v_falhas || (v_fn || ' voltou a usar has_minimum_role(owner), que também passa para admin');
    END IF;
  END LOOP;

  IF to_regprocedure('public.ye_eh_dono(uuid,uuid)') IS NULL THEN
    v_falhas := v_falhas || 'ye_eh_dono ausente'::text;
  END IF;

  -- 2) Funcional: gestão (papel/tipo) cujo perfil só concede escopo próprio
  IF COALESCE(array_length(v_falhas, 1), 0) = 0 THEN
    FOR c IN
      SELECT ub.auth_user_id, ub.tenant_id
        FROM public.usuarios_base ub
       WHERE ub.auth_user_id IS NOT NULL
         AND COALESCE(ub.status::text, 'ativo') = 'ativo'
         AND ( ub.tipo_usuario::text IN ('administrador', 'gestor')
               OR EXISTS (SELECT 1 FROM public.user_roles ur
                           WHERE ur.user_id = ub.auth_user_id
                             AND ur.role::text IN ('manager', 'admin')) )
         AND NOT EXISTS (SELECT 1 FROM public.user_roles ur
                          WHERE ur.user_id = ub.auth_user_id AND ur.role::text = 'owner')
         AND EXISTS (
               SELECT 1 FROM public.usuario_perfil_vinculos v
                 JOIN public.perfil_permissoes pp ON pp.perfil_id = v.perfil_id
                  AND COALESCE(pp.ativo, true) = true
                  AND pp.modulo IN ('documentos', 'configuracoes', 'colaboradores')
                  AND COALESCE(pp.escopo::text, '') = 'proprio_usuario'
                WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true) = true)
         AND NOT EXISTS (
               SELECT 1 FROM public.usuario_perfil_vinculos v
                 JOIN public.perfil_permissoes pp ON pp.perfil_id = v.perfil_id
                  AND COALESCE(pp.ativo, true) = true
                  AND pp.modulo IN ('documentos', 'configuracoes', 'colaboradores')
                  AND COALESCE(pp.escopo::text, '') <> 'proprio_usuario'
                WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true) = true)
         AND NOT EXISTS (
               SELECT 1 FROM public.perfil_excecoes pe
                WHERE pe.usuario_id = ub.id AND COALESCE(pe.ativo, true) = true
                  AND COALESCE(pe.tipo, 'adicional') = 'adicional'
                  AND pe.modulo IN ('documentos', 'configuracoes', 'colaboradores'))
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
        v_amplo := public.perfil_permite_modulo(v_tenant, 'documentos', 'configuracoes', 'colaboradores');
      EXCEPTION WHEN OTHERS THEN
        PERFORM set_config('request.jwt.claims', COALESCE(v_claims_antes, ''), true);
        RAISE;
      END;
      PERFORM set_config('request.jwt.claims', COALESCE(v_claims_antes, ''), true);

      IF v_amplo IS TRUE THEN
        v_falhas := v_falhas || 'usuário de gestão com perfil só próprio obteve acesso amplo'::text;
      ELSE
        v_funcional := 'Prova funcional: gestão com perfil só próprio negada para acesso amplo.';
      END IF;
    END IF;
  END IF;

  IF COALESCE(array_length(v_falhas, 1), 0) = 0 THEN
    r.situacao := 'passou';
    r.obtido   := 'Funções centrais íntegras. ' || v_funcional;
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

-- ── PERFIL-009 ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_perfil_009()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_falhas text[] := ARRAY[]::text[];
  v_fn text;
  v_tipo text;
  v_def text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): o tipo vira modelo — funções, gatilhos e tipos de gestão';
  r.esperado    := 'Modelos por tipo existem, o gatilho de cadastro os usa e o perfil escolhido substitui o automático';

  FOREACH v_fn IN ARRAY ARRAY['public.perfil_modelo_acesso_total(uuid,text,text,text)',
                              'public.perfil_modelo_administrador(uuid)',
                              'public.perfil_modelo_gestor(uuid)',
                              'public.perfil_modelo_para_tipo(uuid,text)',
                              'public.perfil_padrao_colaborador(uuid)'] LOOP
    IF to_regprocedure(v_fn) IS NULL THEN
      v_falhas := v_falhas || (v_fn || ' ausente');
    END IF;
  END LOOP;

  -- o conjunto de tipos que o app converte em gestão (userRoleMap.ts)
  IF to_regprocedure('public.perfil_modelo_para_tipo(uuid,text)') IS NOT NULL THEN
    v_def := pg_get_functiondef(to_regprocedure('public.perfil_modelo_para_tipo(uuid,text)'));
    FOREACH v_tipo IN ARRAY ARRAY['administrador', 'gestor', 'lideranca', 'rh_dp', 'implantador',
                                  'suporte_autorizado', 'corporativo_multiempresa'] LOOP
      IF position('''' || v_tipo || '''' IN v_def) = 0 THEN
        v_falhas := v_falhas || ('perfil_modelo_para_tipo não trata o tipo ' || v_tipo);
      END IF;
    END LOOP;
  END IF;

  -- gatilho de cadastro usa o modelo por tipo
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t
                  WHERE t.tgname = 'trigger_vincular_perfil_padrao'
                    AND t.tgrelid = to_regclass('public.usuarios_base')
                    AND t.tgenabled <> 'D' AND NOT t.tgisinternal) THEN
    v_falhas := v_falhas || 'gatilho trigger_vincular_perfil_padrao ausente ou desabilitado'::text;
  END IF;
  IF to_regprocedure('public.trg_vincular_perfil_padrao()') IS NOT NULL
     AND position('perfil_modelo_para_tipo' IN pg_get_functiondef(to_regprocedure('public.trg_vincular_perfil_padrao()'))) = 0 THEN
    v_falhas := v_falhas || 'trg_vincular_perfil_padrao não usa perfil_modelo_para_tipo'::text;
  END IF;

  -- perfil escolhido substitui o modelo automático
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t
                  WHERE t.tgname = 'trigger_substituir_perfil_padrao'
                    AND t.tgrelid = to_regclass('public.usuario_perfil_vinculos')
                    AND t.tgenabled <> 'D' AND NOT t.tgisinternal) THEN
    v_falhas := v_falhas || 'gatilho trigger_substituir_perfil_padrao ausente ou desabilitado'::text;
  END IF;
  IF to_regprocedure('public.trg_substituir_perfil_padrao()') IS NOT NULL
     AND position('padrao_sistema' IN pg_get_functiondef(to_regprocedure('public.trg_substituir_perfil_padrao()'))) = 0 THEN
    v_falhas := v_falhas || 'trg_substituir_perfil_padrao não generalizado para qualquer modelo (padrao_sistema)'::text;
  END IF;

  IF COALESCE(array_length(v_falhas, 1), 0) = 0 THEN
    r.situacao := 'passou';
    r.obtido   := 'Modelos por tipo, gatilho de cadastro e substituição pelo perfil escolhido íntegros.';
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

-- ── PERFIL-010 ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_perfil_010()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_falhas text[] := ARRAY[]::text[];
  p record;
  v_oid oid;
  v_qtd int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): estrutura do "pode ver salário" — flag, verificador, views, gatilhos e folha';
  r.esperado    := 'Flag e verificador presentes; toda view mascarada security_invoker, sem coluna a menos e com gatilho de preservação; folha com política restritiva';

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'perfis_acesso'
                    AND column_name = 'pode_ver_salario' AND is_nullable = 'NO') THEN
    v_falhas := v_falhas || 'perfis_acesso.pode_ver_salario ausente ou aceita nulo'::text;
  END IF;

  v_oid := to_regprocedure('public.pode_ver_salario(uuid)');
  IF v_oid IS NULL THEN
    v_falhas := v_falhas || 'função pode_ver_salario ausente'::text;
  ELSIF NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_oid) THEN
    v_falhas := v_falhas || 'pode_ver_salario não é SECURITY DEFINER'::text;
  END IF;

  -- views mascaradas: (tabela base, view, gatilho de preservação)
  FOR p IN
    SELECT * FROM (VALUES
      ('admissoes',                'admissoes_segura',                'trg_admissoes_preserva_salario'),
      ('cargos',                   'cargos_segura',                   'trg_cargos_preserva_faixa'),
      ('ferias_solicitacoes',      'ferias_solicitacoes_segura',      'trg_ferias_sol_preserva_valores'),
      ('beneficios_colaboradores', 'beneficios_colaboradores_segura', 'trg_beneficios_preserva_valor'),
      ('ferias_alertas',           'ferias_alertas_segura',           'trg_ferias_alertas_preserva_custo')
    ) AS t(base, vista, gatilho)
  LOOP
    IF to_regclass('public.' || p.base) IS NULL THEN
      CONTINUE;  -- tabela não existe nesta base
    END IF;
    v_oid := to_regclass('public.' || p.vista);
    IF v_oid IS NULL THEN
      v_falhas := v_falhas || (p.vista || ' ausente');
      CONTINUE;
    END IF;
    IF NOT ('security_invoker=true' = ANY (COALESCE((SELECT c.reloptions FROM pg_class c WHERE c.oid = v_oid),
                                                    ARRAY[]::text[]))) THEN
      v_falhas := v_falhas || (p.vista || ' sem security_invoker (passaria por cima do RLS)');
    END IF;
    IF position('pode_ver_salario' IN pg_get_viewdef(v_oid)) = 0 THEN
      v_falhas := v_falhas || (p.vista || ' sem a máscara pode_ver_salario');
    END IF;
    v_qtd := (SELECT count(*)
                FROM information_schema.columns c
               WHERE c.table_schema = 'public' AND c.table_name = p.base
                 AND NOT EXISTS (SELECT 1 FROM information_schema.columns v
                                  WHERE v.table_schema = 'public' AND v.table_name = p.vista
                                    AND v.column_name = c.column_name));
    IF v_qtd > 0 THEN
      v_falhas := v_falhas || (p.vista || ' sem ' || v_qtd || ' coluna(s) da tabela (recriar a view)');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger t
                    WHERE t.tgname = p.gatilho AND t.tgrelid = to_regclass('public.' || p.base)
                      AND t.tgenabled <> 'D' AND NOT t.tgisinternal) THEN
      v_falhas := v_falhas || (p.gatilho || ' ausente ou desabilitado em ' || p.base);
    END IF;
  END LOOP;

  -- folha: política restritiva por tabela que existir
  FOR p IN
    SELECT unnest(ARRAY['folha_itens', 'folha_rescisoes', 'folha_13_calculo', 'folha_ferias_calculo',
                        'folha_provisoes', 'folha_memoria_calculo', 'folha_lancamentos',
                        'folha_periodos', 'folha_lotes']) AS tabela
  LOOP
    IF to_regclass('public.' || p.tabela) IS NULL THEN
      CONTINUE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies pl
                    WHERE pl.schemaname = 'public' AND pl.tablename = p.tabela
                      AND pl.policyname = 'perfil_restringe_salario_' || p.tabela
                      AND pl.permissive = 'RESTRICTIVE' AND pl.cmd = 'SELECT') THEN
      v_falhas := v_falhas || ('folha sem política perfil_restringe_salario_' || p.tabela);
    END IF;
  END LOOP;

  IF COALESCE(array_length(v_falhas, 1), 0) = 0 THEN
    r.situacao := 'passou';
    r.obtido   := 'Flag, verificador, views mascaradas, gatilhos de preservação e travas de folha íntegros.';
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

-- ── PERFIL-011 ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_perfil_011()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  c record;
  v_uid uuid;
  v_tenant uuid;
  v_claims_antes text;
  v_pode boolean;
  v_reais bigint;
  v_vistos bigint;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'FUNCIONAL (somente leitura): simular usuário cujo perfil desliga "pode ver salário" e ler o cadastro pela view';
  r.esperado    := 'pode_ver_salario = false e admissoes_segura sem nenhum salário preenchido';

  FOR c IN
    SELECT ub.auth_user_id, ub.tenant_id
      FROM public.usuarios_base ub
     WHERE ub.auth_user_id IS NOT NULL
       AND COALESCE(ub.status::text, 'ativo') = 'ativo'
       AND EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v
                     JOIN public.perfis_acesso pa ON pa.id = v.perfil_id
                    WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true) = true
                      AND COALESCE(pa.ativo, true) = true AND pa.pode_ver_salario = false)
       AND NOT EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v
                         JOIN public.perfis_acesso pa ON pa.id = v.perfil_id
                        WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true) = true
                          AND COALESCE(pa.ativo, true) = true AND pa.pode_ver_salario = true)
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
    r.obtido   := 'Nenhum usuário com perfil de "Pode ver salário" desligado. Crie um perfil com a opção '
               || 'desligada e vincule a um usuário de teste.';
    RETURN r;
  END IF;

  -- quanto salário existe de fato no cliente (como o chamador, antes de simular)
  v_reais := (SELECT count(*) FROM public.admissoes WHERE tenant_id = v_tenant AND salario IS NOT NULL);

  v_claims_antes := current_setting('request.jwt.claims', true);
  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  BEGIN
    v_pode   := public.pode_ver_salario(v_tenant);
    v_vistos := (SELECT count(*) FROM public.admissoes_segura
                  WHERE tenant_id = v_tenant AND salario IS NOT NULL);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claims', COALESCE(v_claims_antes, ''), true);
    RAISE;
  END;
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims_antes, ''), true);

  IF v_pode IS FALSE AND v_vistos = 0 THEN
    r.situacao := 'passou';
    r.obtido   := 'Usuário sem permissão: pode_ver_salario = false e nenhum salário saiu pela view'
               || CASE WHEN v_reais = 0
                       THEN ' (ressalva: o cliente não tem salário cadastrado, então o mascaramento não foi exercitado).'
                       ELSE ' (existiam ' || v_reais || ' salário(s) cadastrado(s) no cliente).' END;
  ELSE
    r.situacao := 'falhou';
    r.obtido   := 'Usuário SEM permissão de ver salário: pode_ver_salario = ' || COALESCE(v_pode::text, 'nulo')
               || ' e ' || v_vistos || ' salário(s) visível(is) pela view admissoes_segura.';
    r.detalhe  := jsonb_build_object('pode_ver_salario', v_pode, 'salarios_visiveis', v_vistos,
                                     'salarios_existentes', v_reais);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $$;

-- ── DOC-050 ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_doc_050()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_falhas text[] := ARRAY[]::text[];
  v_tab text;
  v_pol text;
  v_oid oid;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): camada de perfil em documento_pastas e documentos com a subárvore do usuário';
  r.esperado    := 'Políticas RESTRICTIVE de leitura nas duas tabelas usando ye_pastas_do_usuario; função SECURITY DEFINER';

  FOR v_tab, v_pol IN
    SELECT * FROM (VALUES
      ('documento_pastas', 'perfil_restringe_leitura_documento_pastas'),
      ('documentos',       'perfil_restringe_leitura_documentos')
    ) AS t(tab, pol)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_policies pl
                    WHERE pl.schemaname = 'public' AND pl.tablename = v_tab
                      AND pl.policyname = v_pol
                      AND pl.permissive = 'RESTRICTIVE' AND pl.cmd = 'SELECT') THEN
      v_falhas := v_falhas || (v_tab || ' sem a política restritiva de leitura ' || v_pol);
    ELSIF NOT EXISTS (SELECT 1 FROM pg_policies pl
                       WHERE pl.schemaname = 'public' AND pl.tablename = v_tab
                         AND pl.policyname = v_pol
                         AND position('ye_pastas_do_usuario' IN COALESCE(pl.qual, '')) > 0) THEN
      v_falhas := v_falhas || (v_pol || ' não usa ye_pastas_do_usuario (quem tem escopo próprio perderia a própria pasta ou veria tudo)');
    END IF;
  END LOOP;

  v_oid := to_regprocedure('public.ye_pastas_do_usuario(uuid)');
  IF v_oid IS NULL THEN
    v_falhas := v_falhas || 'função ye_pastas_do_usuario ausente'::text;
  ELSIF NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_oid) THEN
    v_falhas := v_falhas || 'ye_pastas_do_usuario não é SECURITY DEFINER (recairia na própria RLS)'::text;
  END IF;

  IF COALESCE(array_length(v_falhas, 1), 0) = 0 THEN
    r.situacao := 'passou';
    r.obtido   := 'Camada de perfil de Documentos íntegra nas duas tabelas.';
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

-- ── DOC-051 ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_doc_051()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  c record;
  v_uid uuid;
  v_tenant uuid;
  v_cpf text;
  v_claims_antes text;
  v_amplo boolean;
  v_ids uuid[];
  v_estranhas bigint;
  v_minhas bigint;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'FUNCIONAL (somente leitura): usuário sem acesso amplo a Documentos alcança só a própria subárvore';
  r.esperado    := 'ye_pastas_do_usuario devolve a própria pasta de colaborador e nada de empresa, unidade ou outro colaborador';

  FOR c IN
    SELECT ub.auth_user_id, ub.tenant_id,
           regexp_replace(COALESCE(ub.cpf, ''), '[^0-9]', '', 'g') AS cpf
      FROM public.usuarios_base ub
     WHERE ub.auth_user_id IS NOT NULL
       AND COALESCE(ub.status::text, 'ativo') = 'ativo'
       AND regexp_replace(COALESCE(ub.cpf, ''), '[^0-9]', '', 'g') <> ''
       AND EXISTS (SELECT 1 FROM public.documento_pastas p
                    WHERE p.tenant_id = ub.tenant_id AND p.tipo::text = 'colaborador'
                      AND regexp_replace(COALESCE(p.colaborador_cpf, ''), '[^0-9]', '', 'g')
                          = regexp_replace(COALESCE(ub.cpf, ''), '[^0-9]', '', 'g'))
     LIMIT 25
  LOOP
    v_claims_antes := current_setting('request.jwt.claims', true);
    PERFORM set_config('request.jwt.claims',
                       json_build_object('sub', c.auth_user_id, 'role', 'authenticated')::text, true);
    BEGIN
      v_amplo := public.perfil_permite_modulo(c.tenant_id, 'documentos', 'configuracoes', 'colaboradores');
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('request.jwt.claims', COALESCE(v_claims_antes, ''), true);
      RAISE;
    END;
    PERFORM set_config('request.jwt.claims', COALESCE(v_claims_antes, ''), true);

    IF v_amplo IS FALSE THEN
      v_uid := c.auth_user_id;
      v_tenant := c.tenant_id;
      v_cpf := c.cpf;
      EXIT;
    END IF;
  END LOOP;

  IF v_uid IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Nenhum usuário com Documentos só no escopo próprio e pasta de colaborador encontrado. '
               || 'Crie um perfil com Documentos em "Próprio usuário" e vincule a um usuário de teste que tenha pasta.';
    RETURN r;
  END IF;

  v_claims_antes := current_setting('request.jwt.claims', true);
  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  BEGIN
    v_ids := public.ye_pastas_do_usuario(v_tenant);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claims', COALESCE(v_claims_antes, ''), true);
    RAISE;
  END;
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims_antes, ''), true);

  v_minhas := (SELECT count(*) FROM public.documento_pastas p
                WHERE p.id = ANY (v_ids) AND p.tipo::text = 'colaborador'
                  AND regexp_replace(COALESCE(p.colaborador_cpf, ''), '[^0-9]', '', 'g') = v_cpf);
  v_estranhas := (SELECT count(*) FROM public.documento_pastas p
                   WHERE p.id = ANY (v_ids)
                     AND ( p.tipo::text IN ('root', 'unidade', 'ano', 'mes')
                           OR (p.tipo::text = 'colaborador'
                               AND regexp_replace(COALESCE(p.colaborador_cpf, ''), '[^0-9]', '', 'g') <> v_cpf) ));

  IF v_minhas >= 1 AND v_estranhas = 0 THEN
    r.situacao := 'passou';
    r.obtido   := 'Usuário próprio alcança ' || COALESCE(array_length(v_ids, 1), 0)
               || ' pasta(s): a própria e a subárvore, sem pasta de empresa, unidade ou de outro colaborador.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := 'Subárvore do usuário próprio incorreta: ' || v_minhas || ' pasta(s) própria(s) e '
               || v_estranhas || ' pasta(s) estranha(s) (empresa, unidade ou outro colaborador).';
    r.detalhe  := jsonb_build_object('pastas_proprias', v_minhas, 'pastas_estranhas', v_estranhas,
                                     'total', COALESCE(array_length(v_ids, 1), 0));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $$;

-- ── Documentação dos casos ─────────────────────────────────────────────────
DO $qa1$
DECLARE v_mod uuid;
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL OR to_regclass('public.qa_modulos') IS NULL THEN
    RAISE NOTICE 'Motor de QA ausente nesta base; casos PERFIL-008..011 nao documentados.';
    RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'seguranca-acesso/perfis' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; casos PERFIL-008..011 nao documentados.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado)
  VALUES
  (v_mod, 'PERFIL-008', 'Perfil vinculado manda: gestão com perfil só próprio não obtém acesso amplo',
   'negativo', 'critica', 'aprovado', 'api',
   'LGPD, art. 46 (acesso conforme a função)',
   'O perfil é a fonte da verdade. Papel manager/admin ou tipo administrador/gestor só concedem acesso amplo automático a quem NÃO tem perfil vinculado; só Super Admin e o dono (owner) do próprio cliente ficam acima. Garante que as duas funções centrais carregam essa regra e que ela vale na prática.',
   'Fases 1a e 2a aplicadas.',
   '[{"ordem":1,"acao":"Conferir nas duas funções centrais a trava de perfil vinculado e o dono estrito (e que has_minimum_role(owner) não voltou, pois também passa para admin)","resultado_esperado":"Regras presentes nas duas funções"},
     {"ordem":2,"acao":"Simular um usuário de gestão cujo perfil só concede escopo próprio em documentos/configuracoes/colaboradores e chamar perfil_permite_modulo","resultado_esperado":"Falso: sem acesso amplo"}]',
   'Funções centrais íntegras e gestão com perfil só próprio sem acesso amplo.'),

  (v_mod, 'PERFIL-009', 'O tipo de usuário vira modelo: todo cadastro novo nasce com perfil do seu tipo',
   'feliz', 'alta', 'aprovado', 'api',
   'LGPD, art. 46',
   'Administrador e tipos de gestão (gestor, lideranca, rh_dp, implantador, suporte_autorizado, corporativo_multiempresa) nascem com um modelo de acesso amplo editável; os demais com o Colaborador (padrão); um perfil escolhido pelo RH substitui o modelo automático. O conjunto de tipos acompanha o que o app converte em gestão.',
   'Fases 1b e 2a aplicadas.',
   '[{"ordem":1,"acao":"Conferir as funções de modelo, o gatilho de cadastro e o de substituição, e os tipos tratados por perfil_modelo_para_tipo","resultado_esperado":"Tudo presente e habilitado"}]',
   'Modelos por tipo íntegros.'),

  (v_mod, 'PERFIL-010', 'Permissão "pode ver salário": flag, verificador, views mascaradas, gatilhos e folha',
   'feliz', 'critica', 'aprovado', 'api',
   'LGPD, arts. 6º (necessidade) e 46',
   'Quando o perfil desliga "Pode ver salário", o valor não pode sair do banco. A estrutura precisa estar completa: flag no perfil, verificador SECURITY DEFINER, uma view security_invoker por tabela com valor, sem coluna a menos que a tabela, com gatilho que impede o save mascarado de apagar o valor, e política restritiva nas tabelas de folha.',
   'Entregas de salário aplicadas (fundação, folha, cadastro, cargos, férias, benefícios, alertas).',
   '[{"ordem":1,"acao":"Varrer o catálogo: coluna, função, views (opção security_invoker, definição com a máscara, colunas), gatilhos e políticas de folha","resultado_esperado":"Nenhuma peça ausente ou desviada"}]',
   'Estrutura do "pode ver salário" íntegra.'),

  (v_mod, 'PERFIL-011', 'Usuário sem permissão de ver salário não recebe nenhum salário pela leitura do cadastro',
   'negativo', 'critica', 'aprovado', 'api',
   'LGPD, arts. 6º e 46',
   'Prova o efeito: simulado um usuário cujos perfis ativos desligam "Pode ver salário", o verificador devolve falso e a view de leitura do cadastro não traz nenhum salário preenchido, mesmo que existam salários no cliente.',
   'Existir um perfil com a opção desligada vinculado a um usuário de teste.',
   '[{"ordem":1,"acao":"Simular o usuário e chamar pode_ver_salario","resultado_esperado":"Falso"},
     {"ordem":2,"acao":"Ler admissoes_segura e contar linhas com salário preenchido","resultado_esperado":"Zero"}]',
   'Nenhum salário sai pela view para quem não pode ver.')
  ON CONFLICT (codigo) DO NOTHING;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao PERFIL-008..011 nao registrada: %', SQLERRM;
END $qa1$;

DO $qa2$
DECLARE v_mod uuid;
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL OR to_regclass('public.qa_modulos') IS NULL THEN
    RAISE NOTICE 'Motor de QA ausente nesta base; casos DOC-050..053 nao documentados.';
    RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'documentos-governanca/documentos' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo documentos-governanca/documentos ausente; casos DOC-050..053 nao documentados.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado)
  VALUES
  (v_mod, 'DOC-050', 'Camada de perfil em pastas e documentos usa a subárvore do usuário',
   'feliz', 'critica', 'aprovado', 'api',
   'LGPD, art. 46',
   'documento_pastas não tinha camada de perfil: qualquer membro do cliente via todas as pastas. Garante a política restritiva de leitura nas duas tabelas, apoiada em ye_pastas_do_usuario (SECURITY DEFINER para montar a subárvore sem recair na própria RLS).',
   'Entrega de Documentos com escopo próprio aplicada.',
   '[{"ordem":1,"acao":"Conferir as políticas RESTRICTIVE de SELECT em documento_pastas e documentos e a função de apoio","resultado_esperado":"Presentes, usando ye_pastas_do_usuario; função SECURITY DEFINER"}]',
   'Camada de perfil de Documentos íntegra.'),

  (v_mod, 'DOC-051', 'Usuário com Documentos só no escopo próprio alcança apenas a própria subárvore',
   'negativo', 'critica', 'aprovado', 'api',
   'LGPD, arts. 6º e 46',
   'Prova o efeito no banco: para quem não tem acesso amplo, ye_pastas_do_usuario devolve a pasta de colaborador dele e as subpastas, e nenhuma pasta de empresa, unidade, ano, mês ou de outro colaborador.',
   'Usuário de teste com perfil de Documentos em "Próprio usuário" e pasta de colaborador.',
   '[{"ordem":1,"acao":"Simular o usuário e chamar ye_pastas_do_usuario","resultado_esperado":"Inclui a própria pasta de colaborador"},
     {"ordem":2,"acao":"Procurar no resultado pastas root/unidade/ano/mes ou de outro colaborador","resultado_esperado":"Nenhuma"}]',
   'Subárvore restrita à própria pasta.'),

  (v_mod, 'DOC-052', 'Usuário com Documentos no escopo próprio vê o módulo no menu e só a própria pasta',
   'feliz', 'critica', 'aprovado', 'e2e',
   'LGPD, arts. 6º e 46',
   'Jornada ponta a ponta do achado de 10/2026: /documentos era rota admin-only (o menu e a rota barravam o escopo próprio) e, depois, a árvore trazia pastas de empresa e de outros colaboradores.',
   'Conta de robô de teste (NÃO Super Admin, gestor ou owner) com perfil de Documentos em "Próprio usuário" e pasta de colaborador.',
   '[{"ordem":1,"acao":"Entrar com a conta restrita e abrir o menu Documentos & Governança","resultado_esperado":"O item Documentos aparece"},
     {"ordem":2,"acao":"Abrir Documentos e olhar a árvore de pastas","resultado_esperado":"Só a pasta do próprio usuário e as subpastas; nenhuma pasta de empresa nem de outro colaborador"}]',
   'Menu visível e árvore restrita à própria pasta.'),

  (v_mod, 'DOC-053', 'Escopo próprio em Documentos não mostra abas de empresa nem ações de gestão',
   'negativo', 'alta', 'aprovado', 'e2e',
   'LGPD, art. 46',
   'As abas Conformidade, Governança, PDCA, Notificações e Auditoria e os botões de gestão trazem visão da empresa inteira e não podem aparecer para o escopo próprio.',
   'Mesma conta de robô restrita do DOC-052.',
   '[{"ordem":1,"acao":"Abrir Documentos com a conta restrita","resultado_esperado":"Só a aba Estrutura"},
     {"ordem":2,"acao":"Procurar o botão Nova Pasta","resultado_esperado":"Não existe"}]',
   'Sem abas de empresa e sem Nova Pasta.')
  ON CONFLICT (codigo) DO NOTHING;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao DOC-050..053 nao registrada: %', SQLERRM;
END $qa2$;

-- ── Execução: liga caso <-> rotina (só os de nível api) e roda as baterias ──
DO $impl$
BEGIN
  IF to_regclass('public.qa_implementacoes') IS NULL THEN
    RAISE NOTICE 'qa_implementacoes ausente; rotinas nao ligadas.';
    RETURN;
  END IF;
  INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
    ('PERFIL-008', 'qa_caso_perfil_008', true),
    ('PERFIL-009', 'qa_caso_perfil_009', true),
    ('PERFIL-010', 'qa_caso_perfil_010', true),
    ('PERFIL-011', 'qa_caso_perfil_011', true),
    ('DOC-050',    'qa_caso_doc_050',    true),
    ('DOC-051',    'qa_caso_doc_051',    true)
  ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Rotinas nao ligadas: %', SQLERRM;
END $impl$;

DO $roda$
BEGIN
  PERFORM public.qa_rodar_bateria('manual', 'seguranca-acesso/perfis');
  PERFORM public.qa_rodar_bateria('manual', 'documentos-governanca/documentos');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bateria nao rodou agora (%). As rotinas ficam registradas e entram na proxima execucao agendada.', SQLERRM;
END $roda$;
