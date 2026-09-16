-- ============================================================================
-- Motor de QA — RLS-004 e RLS-005: robustez ao gatilho de perfil padrão.
--
-- As rotinas montam um usuário de teste com um perfil específico (só "metas",
-- sem saúde) e inserem o vínculo à mão. Porém o gatilho
-- trg_vincular_perfil_padrao já cria um vínculo ao perfil PADRÃO do tenant no
-- momento do INSERT em usuarios_base (quando o tenant tem um padrão definido).
-- Como o índice único usuario_perfil_vinculos_ativo_uidx permite UM vínculo
-- ativo por (usuário, empresa), o INSERT explícito colidia
-- ("duplicate key ... usuario_perfil_vinculos_ativo_uidx") sempre que o cercado
-- passou a ter um perfil padrão.
--
-- Correção: DESATIVAR qualquer vínculo já existente do usuário antes de inserir
-- o do teste — assim o perfil do teste é o único ATIVO (e o único que
-- perfil_permite_modulo enxerga). Só a montagem do caso muda; a verificação é a
-- mesma.
-- ============================================================================

-- ── RLS-004 ─────────────────────────────────────────────────────────────────
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

  INSERT INTO auth.users (id, email) VALUES (v_uid, 'qa-rls4-' || v_tag || '@sandbox.invalid');
  INSERT INTO public.profiles (user_id, tenant_id, nome_completo, onboarding_concluido) VALUES (v_uid, v_t1, 'QA RLS4', true);
  INSERT INTO public.usuarios_base (tenant_id, nome_completo, email_principal, auth_user_id, status, tipo_usuario, cpf)
  VALUES (v_t1, 'QA RLS4', 'qa-rls4-' || v_tag || '@sandbox.invalid', v_uid, 'ativo', 'colaborador', public.qa_cpf((floor(random() * 900000) + 1)::int)) RETURNING id INTO v_ub;
  INSERT INTO public.perfis_acesso (tenant_id, nome, ativo) VALUES (v_t1, '[QA-RLS4] Perfil sem saúde ' || v_tag, true) RETURNING id INTO v_perfil;
  INSERT INTO public.perfil_permissoes (perfil_id, tenant_id, modulo, acao, escopo, ativo)
  VALUES (v_perfil, v_t1, 'metas', 'visualizar', 'empresa_inteira', true);
  -- O gatilho de perfil padrão pode já ter vinculado o usuário; desativa antes
  -- para o perfil do teste (sem saúde) ser o único ativo.
  UPDATE public.usuario_perfil_vinculos SET ativo = false WHERE usuario_id = v_ub;
  INSERT INTO public.usuario_perfil_vinculos (tenant_id, usuario_id, perfil_id, ativo) VALUES (v_t1, v_ub, v_perfil, true);

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

-- ── RLS-005 ─────────────────────────────────────────────────────────────────
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
  -- Desativa o vínculo de perfil padrão criado pelo gatilho para o perfil do
  -- teste ser o único ativo.
  UPDATE public.usuario_perfil_vinculos SET ativo = false WHERE usuario_id = v_ub;
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
