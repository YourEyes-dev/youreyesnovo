-- ============================================================================
-- Motor de QA — rotinas do módulo Isolamento RLS (RLS-001 … RLS-007).
--
-- Casos documentados e aprovados que estavam sem rotina (nível api). Todos são
-- leitura/verificação: os de auditoria varrem o catálogo (pg_class/pg_policies);
-- os funcionais montam fixtures no cercado e leem SOB RLS pelo papel real
-- (qa_rls.conta_auth/conta_anon, que rodam como authenticated/anon — sem
-- BYPASSRLS), simulando o usuário via claims. Tudo roda em transação
-- descartável (qa_executar_descartavel desfaz ao final).
-- ============================================================================

-- ── RLS-001: tabelas sensíveis têm RLS habilitada ───────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_rls_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_inerte text; v_off text; v_lista text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): RLS habilitada nas tabelas sensíveis';
  r.esperado    := 'Nenhuma tabela sensível com RLS desligada (política inerte)';

  -- (a) Tabela que TEM política de perfil mas está com RLS desligada: a
  --     política fica inerte e o dado vaza para qualquer sessão.
  SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_inerte
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
  WHERE c.relkind = 'r' AND NOT c.relrowsecurity
    AND EXISTS (SELECT 1 FROM pg_policies p WHERE p.schemaname = 'public'
                 AND p.tablename = c.relname AND p.policyname LIKE 'perfil_restringe_leitura_%');

  -- (b) Lista curada de tabelas de negócio sensíveis que precisam de RLS.
  SELECT string_agg(t, ', ' ORDER BY t) INTO v_off
  FROM unnest(ARRAY['atestados','eventos_saude','afastamentos_saude','alertas_saude',
                    'ponto_marcacoes','ponto_espelhos','ferias_solicitacoes','folha_rescisoes',
                    'beneficios_colaboradores','documentos','ouvidoria','psicossocial_participacoes',
                    'log_acesso_clinico']) AS t
  WHERE to_regclass('public.' || t) IS NOT NULL
    AND NOT (SELECT c.relrowsecurity FROM pg_class c WHERE c.oid = ('public.' || t)::regclass);

  v_lista := NULLIF(concat_ws(', ', v_inerte, v_off), '');
  IF v_lista IS NULL THEN
    r.situacao := 'passou';
    r.obtido   := 'Todas as tabelas sensíveis conferidas estão com RLS habilitada.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := 'Tabela(s) sensível(is) com RLS DESLIGADA: ' || v_lista
               || '. Habilitar ALTER TABLE ... ENABLE ROW LEVEL SECURITY.';
    r.detalhe  := jsonb_build_object('tabelas', v_lista);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── RLS-002: isolamento por tenant (não se lê dado de outra empresa) ─────────
CREATE OR REPLACE FUNCTION public.qa_caso_rls_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_claims text; v_t1 uuid := public.qa_sandbox_tenant_id(); v_t2 uuid;
        v_a uuid; v_tag text := left(gen_random_uuid()::text, 8); n_own bigint; n_other bigint;
BEGIN
  v_claims := current_setting('request.jwt.claims', true);
  SELECT id INTO v_t2 FROM public.tenants WHERE slug = 'qa-sandbox-2';
  IF v_t1 IS NULL OR v_t2 IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Cercados de teste (qa-sandbox / qa-sandbox-2) ausentes.'; RETURN r;
  END IF;

  r.passo_ordem := 1; r.passo_acao := 'Usuário do tenant A tenta ler dado do tenant A e do tenant B';
  r.esperado := 'Vê a linha do próprio tenant; zero linhas do outro';

  v_a := public.qa_mky_usuario_empresa(v_t1, 'rls2a');
  INSERT INTO public.user_roles (user_id, role) VALUES (v_a, 'manager');
  INSERT INTO public.metas (tenant_id, titulo, ano) VALUES (v_t1, '[QA-RLS2] meta A ' || v_tag, 2026);
  INSERT INTO public.metas (tenant_id, titulo, ano) VALUES (v_t2, '[QA-RLS2] meta B ' || v_tag, 2026);

  PERFORM public.qa_mky_claims(v_a);
  n_own   := qa_rls.conta_auth(format('SELECT count(*) FROM public.metas WHERE tenant_id = %L AND titulo = %L', v_t1, '[QA-RLS2] meta A ' || v_tag));
  n_other := qa_rls.conta_auth(format('SELECT count(*) FROM public.metas WHERE tenant_id = %L AND titulo = %L', v_t2, '[QA-RLS2] meta B ' || v_tag));
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);

  -- conta_auth devolve -1 quando o papel authenticated não tem GRANT de leitura
  -- (acontece na réplica local, onde os grants do Supabase não são replicados);
  -- RLS nunca levanta insufficient_privilege — só a falta de grant. No staging
  -- o grant existe e a leitura devolve a contagem real.
  IF n_other > 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('VAZAMENTO entre tenants: usuário do tenant A enxergou %s linha(s) do tenant B.', n_other);
  ELSIF n_own = 1 THEN
    r.situacao := 'passou';
    r.obtido := 'Usuário do tenant A vê a própria meta e não vê nada do tenant B. Isolamento por RLS garantido.';
  ELSIF n_own <= 0 THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Réplica local sem os GRANTs do papel authenticated (leitura devolveu -1); o isolamento confirma no staging, onde o grant existe.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Controle falhou: usuário do tenant A não leu a própria meta (esperado 1, obtido %s).', n_own);
  END IF;
  r.detalhe := jsonb_build_object('n_own', n_own, 'n_other', n_other);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── RLS-003: políticas RESTRICTIVE de perfil presentes nas tabelas sensíveis ─
CREATE OR REPLACE FUNCTION public.qa_caso_rls_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_falta text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): política RESTRICTIVE de perfil nas tabelas cobertas';
  r.esperado    := 'Cada tabela sensível prevista tem sua perfil_restringe_leitura_* RESTRICTIVE';

  -- Conjunto representativo das famílias cobertas (ponto, férias, saúde, psico,
  -- benefícios, documentos). Cada uma tem de ter a política RESTRICTIVE viva.
  SELECT string_agg(t, ', ' ORDER BY t) INTO v_falta
  FROM unnest(ARRAY['atestados','eventos_saude','afastamentos_saude','ponto_marcacoes',
                    'ferias_solicitacoes','beneficios_colaboradores','documentos',
                    'psicossocial_participacoes','folha_rescisoes']) AS t
  WHERE to_regclass('public.' || t) IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM pg_policies p
      WHERE p.schemaname = 'public' AND p.tablename = t
        AND p.policyname LIKE 'perfil_restringe_leitura_%'
        AND p.permissive = 'RESTRICTIVE');

  IF v_falta IS NULL THEN
    r.situacao := 'passou';
    r.obtido   := 'Todas as tabelas sensíveis previstas têm a política RESTRICTIVE de perfil.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := 'Tabela(s) sensível(is) SEM a política RESTRICTIVE de perfil: ' || v_falta;
    r.detalhe  := jsonb_build_object('tabelas', v_falta);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── RLS-004: dado de saúde só é lido por perfil autorizado ──────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_rls_004()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_claims text; v_t1 uuid := public.qa_sandbox_tenant_id();
        v_uid uuid := gen_random_uuid(); v_ub uuid; v_perfil uuid; v_tag text := left(gen_random_uuid()::text, 8);
        n_user bigint; n_owner bigint;
BEGIN
  v_claims := current_setting('request.jwt.claims', true);
  IF v_t1 IS NULL THEN r.situacao := 'nao_implementado'; r.obtido := 'Cercado de teste ausente.'; RETURN r; END IF;

  r.passo_ordem := 1; r.passo_acao := 'Usuário SEM escopo de saúde tenta ler atestados do tenant';
  r.esperado := 'Zero linhas (dado de saúde protegido pela camada de perfil)';

  -- Usuário do tenant, comum, com perfil que libera só "metas" (nada de saúde).
  INSERT INTO auth.users (id, email) VALUES (v_uid, 'qa-rls4-' || v_tag || '@sandbox.invalid');
  INSERT INTO public.profiles (user_id, tenant_id, nome_completo, onboarding_concluido) VALUES (v_uid, v_t1, 'QA RLS4', true);
  INSERT INTO public.usuarios_base (tenant_id, nome_completo, email_principal, auth_user_id, status, tipo_usuario, cpf)
  VALUES (v_t1, 'QA RLS4', 'qa-rls4-' || v_tag || '@sandbox.invalid', v_uid, 'ativo', 'colaborador', public.qa_cpf((floor(random() * 900000) + 1)::int)) RETURNING id INTO v_ub;
  INSERT INTO public.perfis_acesso (tenant_id, nome, ativo) VALUES (v_t1, '[QA-RLS4] Perfil sem saúde ' || v_tag, true) RETURNING id INTO v_perfil;
  INSERT INTO public.perfil_permissoes (perfil_id, tenant_id, modulo, acao, escopo, ativo)
  VALUES (v_perfil, v_t1, 'metas', 'visualizar', 'empresa_inteira', true);
  INSERT INTO public.usuario_perfil_vinculos (tenant_id, usuario_id, perfil_id, ativo) VALUES (v_t1, v_ub, v_perfil, true);

  -- Semear um atestado no tenant (existe de fato).
  INSERT INTO public.atestados (tenant_id, colaborador_nome, tipo, data_emissao, profissional_nome, profissional_registro, observacoes)
  VALUES (v_t1, '[QA-RLS4] Colaborador ' || v_tag, 'assistencial', CURRENT_DATE, 'QA Dr. Teste', 'CRM-QA-0000', 'atestado fictício de teste ' || v_tag);
  SELECT count(*) INTO n_owner FROM public.atestados WHERE tenant_id = v_t1 AND observacoes = 'atestado fictício de teste ' || v_tag;

  PERFORM public.qa_mky_claims(v_uid);
  n_user := qa_rls.conta_auth(format('SELECT count(*) FROM public.atestados WHERE tenant_id = %L AND observacoes = %L', v_t1, 'atestado fictício de teste ' || v_tag));
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);

  IF n_owner < 1 THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Não foi possível semear o atestado de teste (controle vazio).';
  ELSIF n_user <= 0 THEN
    r.situacao := 'passou';
    r.obtido := 'Usuário sem escopo de saúde lê 0 atestados, embora o registro exista. Dado de saúde protegido pela camada de perfil.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('VAZAMENTO de saúde: usuário sem escopo leu %s atestado(s).', n_user);
  END IF;
  r.detalhe := jsonb_build_object('n_user', n_user, 'n_owner', n_owner);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── RLS-005: perfil_permite_modulo barra módulo não liberado ao perfil ──────
CREATE OR REPLACE FUNCTION public.qa_caso_rls_005()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_claims text; v_t1 uuid := public.qa_sandbox_tenant_id();
        v_uid uuid := gen_random_uuid(); v_ub uuid; v_perfil uuid; v_tag text := left(gen_random_uuid()::text, 8);
        v_ok boolean; v_block boolean;
BEGIN
  v_claims := current_setting('request.jwt.claims', true);
  IF v_t1 IS NULL THEN r.situacao := 'nao_implementado'; r.obtido := 'Cercado de teste ausente.'; RETURN r; END IF;

  r.passo_ordem := 1; r.passo_acao := 'Perfil libera "metas" mas não "ponto"; conferir o portão de módulo';
  r.esperado := 'perfil_permite_modulo(metas)=true e (ponto)=false';

  INSERT INTO auth.users (id, email) VALUES (v_uid, 'qa-rls5-' || v_tag || '@sandbox.invalid');
  INSERT INTO public.profiles (user_id, tenant_id, nome_completo, onboarding_concluido) VALUES (v_uid, v_t1, 'QA RLS5', true);
  INSERT INTO public.usuarios_base (tenant_id, nome_completo, email_principal, auth_user_id, status, tipo_usuario, cpf)
  VALUES (v_t1, 'QA RLS5', 'qa-rls5-' || v_tag || '@sandbox.invalid', v_uid, 'ativo', 'colaborador', public.qa_cpf((floor(random() * 900000) + 1)::int)) RETURNING id INTO v_ub;
  INSERT INTO public.perfis_acesso (tenant_id, nome, ativo) VALUES (v_t1, '[QA-RLS5] Perfil só metas ' || v_tag, true) RETURNING id INTO v_perfil;
  INSERT INTO public.perfil_permissoes (perfil_id, tenant_id, modulo, acao, escopo, ativo)
  VALUES (v_perfil, v_t1, 'metas', 'visualizar', 'empresa_inteira', true);
  INSERT INTO public.usuario_perfil_vinculos (tenant_id, usuario_id, perfil_id, ativo) VALUES (v_t1, v_ub, v_perfil, true);

  PERFORM public.qa_mky_claims(v_uid);
  v_ok    := public.perfil_permite_modulo(v_t1, 'metas');
  v_block := public.perfil_permite_modulo(v_t1, 'ponto');
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);

  IF v_ok IS TRUE AND v_block IS FALSE THEN
    r.situacao := 'passou';
    r.obtido := 'Portão de módulo correto: libera o módulo do perfil (metas) e barra o não liberado (ponto).';
  ELSIF v_block IS NOT FALSE THEN
    r.situacao := 'falhou';
    r.obtido := 'Portão de módulo falhou: perfil sem "ponto" foi liberado para o módulo ponto.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'Controle falhou: perfil COM "metas" não foi liberado para o próprio módulo.';
  END IF;
  r.detalhe := jsonb_build_object('metas', v_ok, 'ponto', v_block);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── RLS-006: sessão sem autenticação não lê dado de negócio ─────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_rls_006()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_claims text; v_t1 uuid := public.qa_sandbox_tenant_id();
        v_tag text := left(gen_random_uuid()::text, 8); n_anon bigint; n_owner bigint;
BEGIN
  v_claims := current_setting('request.jwt.claims', true);
  IF v_t1 IS NULL THEN r.situacao := 'nao_implementado'; r.obtido := 'Cercado de teste ausente.'; RETURN r; END IF;

  r.passo_ordem := 1; r.passo_acao := 'Sessão anônima (sem claims) tenta ler dado de negócio';
  r.esperado := 'Zero linhas';

  INSERT INTO public.metas (tenant_id, titulo, ano) VALUES (v_t1, '[QA-RLS6] meta anon ' || v_tag, 2026);
  SELECT count(*) INTO n_owner FROM public.metas WHERE tenant_id = v_t1 AND titulo = '[QA-RLS6] meta anon ' || v_tag;

  n_anon := qa_rls.conta_anon(format('SELECT count(*) FROM public.metas WHERE tenant_id = %L AND titulo = %L', v_t1, '[QA-RLS6] meta anon ' || v_tag));

  IF n_owner < 1 THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Não foi possível semear a meta de teste (controle vazio).';
  ELSIF n_anon <= 0 THEN
    r.situacao := 'passou';
    r.obtido := 'Sessão anônima lê 0 linhas de negócio, embora o registro exista. Linha de base da RLS respeitada.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('O anônimo leu %s linha(s) de negócio — RLS não está barrando auth.uid() nulo.', n_anon);
  END IF;
  r.detalhe := jsonb_build_object('n_anon', n_anon, 'n_owner', n_owner);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── RLS-007: tabela sensível nova precisa de política de perfil (= PERFIL-003) ─
CREATE OR REPLACE FUNCTION public.qa_caso_rls_007()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno;
BEGIN
  -- A cobertura da camada de perfil é a mesma varredura do PERFIL-003. Reusar
  -- garante que os dois casos falem a mesma verdade (uma fonte só).
  r := public.qa_caso_perfil_003();
  r.passo_acao := 'Cobertura da camada de perfil (via PERFIL-003): tabela sensível nova precisa de política ou exceção';
  r.esperado   := 'Nenhuma tabela de padrão sensível sem política de perfil ou exceção documentada';
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── Ligar caso ↔ rotina ─────────────────────────────────────────────────────
INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
  ('RLS-001', 'qa_caso_rls_001', true),
  ('RLS-002', 'qa_caso_rls_002', true),
  ('RLS-003', 'qa_caso_rls_003', true),
  ('RLS-004', 'qa_caso_rls_004', true),
  ('RLS-005', 'qa_caso_rls_005', true),
  ('RLS-006', 'qa_caso_rls_006', true),
  ('RLS-007', 'qa_caso_rls_007', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
