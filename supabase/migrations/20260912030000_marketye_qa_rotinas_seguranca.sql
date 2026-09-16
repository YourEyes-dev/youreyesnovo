-- =====================================================================
-- MARKETYE · QA: ROTINAS DA FAMÍLIA DE SEGURANÇA (MKY-110 a MKY-116)
--
-- Pacote de QA de 12/09: os sete casos de segurança e RLS ganham rotina.
-- Cada rotina monta um cenário completo no cercado (dois especialistas,
-- duas empresas, conversas, mensagens, cupom, contestação, ocorrência,
-- destaque, documento, denúncia, contratação, demanda latente), troca de
-- papel e de claims (SET LOCAL ROLE authenticated + request.jwt.claims)
-- e prova o LADO NEGATIVO do isolamento tabela a tabela, com controles
-- positivos para a rotina nunca passar à toa.
--
-- Duas correções de defesa em profundidade que as rotinas exigem:
--   D-05: EXECUTE das funções marketye_* deixa de ser herdado de PUBLIC
--         (visitante anônimo executava 47 funções, guardadas só por dentro).
--         Só a vitrine pública e as vagas de demanda ficam para anon; as
--         internas ficam só para service_role.
--   D-15: marketplace_reputacao expunha a qualquer usuário autenticado o
--         motivo do aviso de ajuste de nível de todos os especialistas;
--         as colunas de aviso saem da leitura direta (o portal lê por função).
--
-- Idempotente: REVOKE/GRANT repetíveis, CREATE OR REPLACE, ON CONFLICT.
-- =====================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- 1) D-05 — superfície mínima de EXECUTE nas funções do módulo
-- ---------------------------------------------------------------------
DO $seg$
DECLARE f record;
BEGIN
  FOR f IN SELECT p.oid::regprocedure AS assinatura, p.proname
           FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public' AND p.proname LIKE 'marketye_%'
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', f.assinatura);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', f.assinatura);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM authenticated', f.assinatura);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f.assinatura);
    IF f.proname NOT IN ('marketye_buscar_interno', 'marketye_cadastrar_especialista_para', 'marketye_recalcular_reputacao', 'marketye_semear_ilha_teste') THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', f.assinatura);
    END IF;
    IF f.proname IN ('marketye_vitrine_publica', 'marketye_vagas_demanda', 'marketye_meu_id') THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon', f.assinatura);
    END IF;
  END LOOP;
END $seg$;

-- ---------------------------------------------------------------------
-- 2) D-15 — aviso de ajuste de nível não é leitura pública
--    D-16 — visitante anônimo tinha SELECT de tabela inteira em avaliações
--    (inclusive tenant_id e avaliador_id). A política de leitura é só para
--    authenticated, então devolvia zero linhas — mas a concessão ficava lá.
--    Visitante não lê avaliações direto (a vitrine exige login; a página
--    pública lê por função).
-- ---------------------------------------------------------------------
REVOKE SELECT ON public.marketplace_avaliacoes FROM anon;
REVOKE SELECT ON public.marketplace_reputacao FROM authenticated, anon;
GRANT SELECT (profissional_id, saude_score, saude_cor, media_90d, avaliacoes_90d, clientes_unicos_total, clientes_unicos_90d, taxa_resposta_90d,
              tempo_resposta_mediano_min, taxa_cancelamento_90d, ocorrencias_90d, servicos_concluidos_total, nivel, nivel_desde, abaixo_piso,
              protegido_ate, calculado_em)
  ON public.marketplace_reputacao TO authenticated;

-- ---------------------------------------------------------------------
-- 2b) D-17 — políticas que liam marketplace_profissionais.user_id como o
--     próprio usuário. Desde que a coluna user_id foi fechada para usuário
--     comum (MKY-012), essas 13 políticas quebravam com "permission denied
--     for table marketplace_profissionais" em qualquer leitura direta de
--     anúncios, pacotes, contratações, comissões e documentos, e no upload
--     de foto e documento do especialista (Storage). Achado pela MKY-110.
--     Correção: comparar com marketye_meu_id() (função segura que devolve
--     o id do especialista da sessão), sem ler a coluna fechada.
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS "Professionals view own commissions" ON public.marketplace_afiliados_comissoes;
CREATE POLICY "Professionals view own commissions" ON public.marketplace_afiliados_comissoes FOR SELECT TO authenticated
  USING (profissional_id = public.marketye_meu_id());

DROP POLICY IF EXISTS "Authenticated users can insert audit" ON public.marketplace_audit_log;
CREATE POLICY "Authenticated users can insert audit" ON public.marketplace_audit_log FOR INSERT TO authenticated
  WITH CHECK (tenant_id = public.get_user_tenant_id() OR profissional_id = public.marketye_meu_id());

DROP POLICY IF EXISTS "Professionals can update their contracts" ON public.marketplace_contratacoes;
CREATE POLICY "Professionals can update their contracts" ON public.marketplace_contratacoes FOR UPDATE TO authenticated
  USING (profissional_id = public.marketye_meu_id());
DROP POLICY IF EXISTS "Professionals can view their contracts" ON public.marketplace_contratacoes;
CREATE POLICY "Professionals can view their contracts" ON public.marketplace_contratacoes FOR SELECT TO authenticated
  USING (profissional_id = public.marketye_meu_id());

DROP POLICY IF EXISTS "Profissionais manage own pacotes" ON public.marketplace_pacotes;
CREATE POLICY "Profissionais manage own pacotes" ON public.marketplace_pacotes FOR ALL TO public
  USING (profissional_id = public.marketye_meu_id()) WITH CHECK (profissional_id = public.marketye_meu_id());

DROP POLICY IF EXISTS "Users can insert own docs" ON public.marketplace_profissional_documentos;
CREATE POLICY "Users can insert own docs" ON public.marketplace_profissional_documentos FOR INSERT TO public
  WITH CHECK (profissional_id = public.marketye_meu_id());
DROP POLICY IF EXISTS "Users can view own docs" ON public.marketplace_profissional_documentos;
CREATE POLICY "Users can view own docs" ON public.marketplace_profissional_documentos FOR SELECT TO public
  USING (profissional_id = public.marketye_meu_id() OR public.is_superadmin(auth.uid()));

DROP POLICY IF EXISTS "Professionals manage own services" ON public.marketplace_servicos;
CREATE POLICY "Professionals manage own services" ON public.marketplace_servicos FOR ALL TO authenticated
  USING (profissional_id = public.marketye_meu_id()) WITH CHECK (profissional_id = public.marketye_meu_id());

DO $pol$
BEGIN
  DROP POLICY IF EXISTS "MarketYE: especialista apaga a propria foto" ON storage.objects;
  CREATE POLICY "MarketYE: especialista apaga a propria foto" ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'marketplace-fotos' AND split_part(name, '/', 1) = public.marketye_meu_id()::text);
  DROP POLICY IF EXISTS "MarketYE: especialista sobe a propria foto" ON storage.objects;
  CREATE POLICY "MarketYE: especialista sobe a propria foto" ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'marketplace-fotos' AND split_part(name, '/', 1) = public.marketye_meu_id()::text);
  DROP POLICY IF EXISTS "MarketYE: especialista troca a propria foto" ON storage.objects;
  CREATE POLICY "MarketYE: especialista troca a propria foto" ON storage.objects FOR UPDATE TO authenticated
    USING (bucket_id = 'marketplace-fotos' AND split_part(name, '/', 1) = public.marketye_meu_id()::text);
  DROP POLICY IF EXISTS "Profissional dono pode ler marketplace-docs" ON storage.objects;
  CREATE POLICY "Profissional dono pode ler marketplace-docs" ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'marketplace-docs' AND EXISTS (
      SELECT 1 FROM public.marketplace_profissional_documentos d
      WHERE d.arquivo_url LIKE '%' || storage.objects.name AND d.profissional_id = public.marketye_meu_id()));
  DROP POLICY IF EXISTS "Profissional pode subir marketplace-docs" ON storage.objects;
  CREATE POLICY "Profissional pode subir marketplace-docs" ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'marketplace-docs' AND split_part(name, '/', 1) = public.marketye_meu_id()::text);
EXCEPTION WHEN undefined_table OR undefined_object OR insufficient_privilege THEN
  RAISE NOTICE 'MarketYE: políticas de storage não ajustadas neste banco (%): %', SQLSTATE, SQLERRM;
END $pol$;

-- ---------------------------------------------------------------------
-- 3) Limpeza ampliada (denúncias, contratações e demanda das contas de QA)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.qa_mky_limpar()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  -- Dependentes sem ON DELETE CASCADE primeiro (auditoria, avaliações, denúncias, contratações), depois o especialista (o resto cascateia).
  DELETE FROM public.marketplace_audit_log WHERE profissional_id IN (SELECT id FROM public.marketplace_profissionais WHERE nome_completo LIKE 'QA Especialista %' OR email LIKE 'qa-mky-%@sandbox.invalid');
  DELETE FROM public.marketplace_avaliacoes WHERE profissional_id IN (SELECT id FROM public.marketplace_profissionais WHERE nome_completo LIKE 'QA Especialista %' OR email LIKE 'qa-mky-%@sandbox.invalid');
  DELETE FROM public.marketplace_denuncias WHERE profissional_id IN (SELECT id FROM public.marketplace_profissionais WHERE nome_completo LIKE 'QA Especialista %' OR email LIKE 'qa-mky-%@sandbox.invalid');
  DELETE FROM public.marketplace_contratacoes WHERE profissional_id IN (SELECT id FROM public.marketplace_profissionais WHERE nome_completo LIKE 'QA Especialista %' OR email LIKE 'qa-mky-%@sandbox.invalid');
  DELETE FROM public.marketplace_leads WHERE profissional_id IN (SELECT id FROM public.marketplace_profissionais WHERE nome_completo LIKE 'QA Especialista %' OR email LIKE 'qa-mky-%@sandbox.invalid');
  DELETE FROM public.marketplace_profissionais WHERE nome_completo LIKE 'QA Especialista %' OR email LIKE 'qa-mky-%@sandbox.invalid';
  DELETE FROM public.marketplace_demanda_latente WHERE uf = 'QA';
  DELETE FROM public.marketplace_categorias WHERE slug LIKE 'qa-mky-%';
  DELETE FROM public.superadmins WHERE email LIKE 'qa-mky-%@sandbox.invalid';
  DELETE FROM public.profiles WHERE nome_completo LIKE 'QA Empresa %' AND user_id IN (SELECT id FROM auth.users WHERE email LIKE 'qa-mky-%@sandbox.invalid');
  DELETE FROM public.tenants WHERE slug LIKE 'qa-mky-%';
  DELETE FROM auth.users WHERE email LIKE 'qa-mky-%@sandbox.invalid';
END $$;

-- ---------------------------------------------------------------------
-- 4) Cenário compartilhado da família de segurança
--    A e B: especialistas aprovados (B com anúncio publicado + rascunho, cupom,
--    contestação, ocorrência, destaque). X (cercado 1) conversa com B; Y
--    (cercado 2) conversa com A, avalia A, denuncia A, tem contratação legada
--    e demanda latente. Devolve todos os ids em JSON. Restaura os claims.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.qa_mky_cenario_seguranca()
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v_claims text := current_setting('request.jwt.claims', true);
  t1 uuid := public.qa_sandbox_tenant_id(); t2 uuid; sa uuid; x uuid; y uuid; a record; b record; cat uuid;
  b_pub uuid; b_rasc uuid; a_pub uuid; lead_xb uuid; lead_ya uuid; msg_xb uuid; msg_ya uuid; cupom_b uuid; contest_b uuid; ocorr_b uuid;
  dest_b uuid; doc_xb uuid; den_y uuid; contr_y uuid; dem_y uuid; aval_a uuid; v jsonb;
BEGIN
  IF t1 IS NULL THEN RAISE EXCEPTION 'Cercado qa-sandbox não existe'; END IF;
  SELECT id INTO t2 FROM public.tenants WHERE slug = 'qa-sandbox-2';
  IF t2 IS NULL THEN RAISE EXCEPTION 'Segundo cercado (qa-sandbox-2) não existe'; END IF;
  sa := public.qa_mky_superadmin();
  x := public.qa_mky_usuario_empresa(t1, '110x'); y := public.qa_mky_usuario_empresa(t2, '110y');
  SELECT * INTO a FROM public.qa_mky_especialista('110a', '900.000.032-71');
  SELECT * INTO b FROM public.qa_mky_especialista('110b', '900.000.033-52');
  SELECT id INTO cat FROM public.marketplace_categorias WHERE slug = 'seguranca-trabalho';

  PERFORM public.qa_mky_claims(sa);
  PERFORM public.marketye_moderar_especialista(a.prof_id, 'aprovado', NULL, true);
  PERFORM public.marketye_moderar_especialista(b.prof_id, 'aprovado', NULL, true);

  PERFORM public.qa_mky_claims(b.uid);
  v := public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Seguranca B publicado', 'descricao', 'Serviço fictício de teste do MarketYE, apenas para a rotina automatizada de segurança.', 'categoria_id', cat, 'modalidade', 'online', 'tipo_preco', 'hora', 'preco_referencia', 300));
  b_pub := (v->>'id')::uuid; PERFORM public.marketye_anuncio_publicar(b_pub);
  v := public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Seguranca B rascunho', 'descricao', 'Rascunho fictício de teste do MarketYE que não deve aparecer para ninguém.', 'categoria_id', cat, 'modalidade', 'online', 'tipo_preco', 'sob_orcamento'));
  b_rasc := (v->>'id')::uuid;
  v := public.marketye_cupom_salvar(jsonb_build_object('codigo', 'QASEG110', 'descricao', 'cupom de teste', 'desconto_percentual', 10));
  SELECT id INTO cupom_b FROM public.marketplace_cupons WHERE profissional_id = b.prof_id AND codigo = 'QASEG110';

  PERFORM public.qa_mky_claims(a.uid);
  v := public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Seguranca A publicado', 'descricao', 'Serviço fictício de teste do MarketYE, apenas para a rotina automatizada de segurança.', 'categoria_id', cat, 'modalidade', 'presencial', 'tipo_preco', 'hora', 'preco_referencia', 250));
  a_pub := (v->>'id')::uuid; PERFORM public.marketye_anuncio_publicar(a_pub);

  PERFORM public.qa_mky_claims(x);
  lead_xb := (public.marketye_abrir_lead(b.prof_id, b_pub, 'Preciso de um PGR para a minha empresa de teste.')->>'id')::uuid;
  SELECT id INTO msg_xb FROM public.marketplace_lead_mensagens WHERE lead_id = lead_xb ORDER BY created_at LIMIT 1;

  PERFORM public.qa_mky_claims(y);
  lead_ya := (public.marketye_abrir_lead(a.prof_id, a_pub, 'Preciso de um laudo para a minha empresa de teste.')->>'id')::uuid;
  SELECT id INTO msg_ya FROM public.marketplace_lead_mensagens WHERE lead_id = lead_ya ORDER BY created_at LIMIT 1;
  PERFORM public.qa_mky_claims(a.uid); PERFORM public.marketye_lead_mensagem(lead_ya, 'Posso atender na próxima semana.');
  PERFORM public.qa_mky_claims(y); PERFORM public.marketye_lead_status(lead_ya, 'ganho');
  v := public.marketye_avaliar('lead', lead_ya, '{"pontualidade":4,"clareza":5,"aderencia_escopo":4,"profissionalismo":5}'::jsonb, 'Avaliação fictícia de teste.');
  SELECT id INTO aval_a FROM public.marketplace_avaliacoes WHERE lead_id = lead_ya AND direcao = 'cliente_para_especialista' LIMIT 1;

  PERFORM public.qa_mky_claims(sa);
  v := public.marketye_destaque_criar(b.prof_id, NULL, 'topo', NULL, NULL, CURRENT_DATE, CURRENT_DATE + 7, NULL);
  dest_b := (v->>'id')::uuid;
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);

  -- Mobiliário inserido direto (a rotina roda como o dono do banco): contestação, ocorrência, documento, denúncia, contratação legada, demanda latente.
  INSERT INTO public.marketplace_contestacoes (profissional_id, decisao_tipo, motivo) VALUES (b.prof_id, 'outro', 'Contestação fictícia de teste da rotina de segurança.') RETURNING id INTO contest_b;
  INSERT INTO public.marketplace_ocorrencias (profissional_id, tipo, descricao, reflexo_visibilidade) VALUES (b.prof_id, 'ocorrencia', 'Ocorrência fictícia de teste.', false) RETURNING id INTO ocorr_b;
  INSERT INTO public.marketplace_lead_documentos (lead_id, documento_id, tipo) VALUES (lead_xb, gen_random_uuid(), 'proposta') RETURNING id INTO doc_xb;
  INSERT INTO public.marketplace_denuncias (tenant_id, profissional_id, denunciante_id, denunciante_nome, tipo, descricao) VALUES (t2, a.prof_id, y, 'QA Empresa 110y', 'outro', 'Denúncia fictícia de teste.') RETURNING id INTO den_y;
  INSERT INTO public.marketplace_contratacoes (tenant_id, servico_id, profissional_id, solicitante_id, solicitante_nome, modalidade) VALUES (t2, a_pub, a.prof_id, y, 'QA Empresa 110y', 'presencial') RETURNING id INTO contr_y;
  INSERT INTO public.marketplace_demanda_latente (tenant_id, categoria_id, uf, termos, resultados) VALUES (t2, cat, 'QA', 'demanda fictícia', 0) RETURNING id INTO dem_y;

  RETURN jsonb_build_object('t1', t1, 't2', t2, 'sa', sa, 'x', x, 'y', y, 'a_uid', a.uid, 'a_prof', a.prof_id, 'b_uid', b.uid, 'b_prof', b.prof_id,
                            'b_pub', b_pub, 'b_rasc', b_rasc, 'a_pub', a_pub, 'lead_xb', lead_xb, 'lead_ya', lead_ya, 'msg_xb', msg_xb, 'msg_ya', msg_ya,
                            'cupom_b', cupom_b, 'contest_b', contest_b, 'ocorr_b', ocorr_b, 'dest_b', dest_b, 'doc_xb', doc_xb, 'den_y', den_y,
                            'contr_y', contr_y, 'dem_y', dem_y, 'aval_a', aval_a);
END $$;

-- ---------------------------------------------------------------------
-- 5) Rotinas
-- ---------------------------------------------------------------------
-- MKY-110 — especialista A não lê nem escreve nas linhas de B (tabela a tabela)
CREATE OR REPLACE FUNCTION public.qa_caso_mky_110()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; n int;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  r.passo_ordem := 1; r.passo_acao := 'Como A: ler as linhas de B em cada tabela'; r.esperado := 'zero linhas nas tabelas privadas; só o anúncio publicado de B; as próprias linhas visíveis (controle)';
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.marketplace_consentimentos WHERE profissional_id = (s->>'a_prof')::uuid; IF n = 0 THEN falhas := array_append(falhas, 'controle: A não lê os próprios consentimentos'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_leads WHERE profissional_id = (s->>'b_prof')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'leads de B'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_lead_mensagens WHERE lead_id = (s->>'lead_xb')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'mensagens de B'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_lead_documentos WHERE lead_id = (s->>'lead_xb')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'documentos da conversa de B'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_cupons WHERE profissional_id = (s->>'b_prof')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'cupons de B'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_consentimentos WHERE profissional_id = (s->>'b_prof')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'consentimentos de B'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_contestacoes WHERE profissional_id = (s->>'b_prof')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'contestações de B'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_ocorrencias WHERE profissional_id = (s->>'b_prof')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'ocorrências de B'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_autonomia_eventos WHERE profissional_id = (s->>'b_prof')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'trilha de autonomia de B'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_destaques WHERE profissional_id = (s->>'b_prof')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'destaques de B'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_servicos WHERE id = (s->>'b_rasc')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'rascunho de anúncio de B'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_servicos WHERE id = (s->>'b_pub')::uuid; IF n <> 1 THEN falhas := array_append(falhas, 'controle: anúncio publicado de B deveria ser visível'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Como A: escrever nas linhas de B'; r.esperado := 'nada muda';
  UPDATE public.marketplace_servicos SET nome = 'invadido' WHERE id = (s->>'b_pub')::uuid; GET DIAGNOSTICS n = ROW_COUNT; IF n > 0 THEN falhas := array_append(falhas, 'UPDATE no anúncio de B alterou linha'); END IF;
  BEGIN
    INSERT INTO public.marketplace_cupons (profissional_id, codigo, desconto_percentual) VALUES ((s->>'b_prof')::uuid, 'INVASAO', 5);
    falhas := array_append(falhas, 'INSERT de cupom em nome de B foi aceito');
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    INSERT INTO public.marketplace_servicos (profissional_id, nome, descricao, modalidade) VALUES ((s->>'b_prof')::uuid, 'invasao', 'anúncio em nome de outro', 'online');
    falhas := array_append(falhas, 'INSERT de anúncio em nome de B foi aceito');
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    DELETE FROM public.marketplace_cupons WHERE id = (s->>'cupom_b')::uuid; GET DIAGNOSTICS n = ROW_COUNT; IF n > 0 THEN falhas := array_append(falhas, 'DELETE do cupom de B apagou linha'); END IF;
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF array_length(falhas, 1) IS NULL THEN
    r.situacao := 'passou'; r.obtido := 'A não lê nem altera leads, mensagens, documentos, cupons, consentimentos, contestações, ocorrências, trilha, destaques e rascunhos de B; só o anúncio publicado, como a vitrine exige.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; ');
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE; PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-111 — empresa X não lê nem escreve nas linhas da empresa Y
CREATE OR REPLACE FUNCTION public.qa_caso_mky_111()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; n int;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  r.passo_ordem := 1; r.passo_acao := 'Como usuário de X: ler as linhas de Y em cada tabela'; r.esperado := 'zero linhas; a própria conversa visível (controle)';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  PERFORM set_config('app.qa_modo', 'off', true);  -- a trava do cercado dispara antes do RLS e lê tenants sob RLS como authenticated (ver MKY-001)
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.marketplace_leads WHERE id = (s->>'lead_xb')::uuid; IF n <> 1 THEN falhas := array_append(falhas, 'controle: X não lê a própria conversa'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_leads WHERE id = (s->>'lead_ya')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'lead de Y'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_lead_mensagens WHERE lead_id = (s->>'lead_ya')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'mensagens de Y'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_denuncias WHERE id = (s->>'den_y')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'denúncia de Y'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_contratacoes WHERE id = (s->>'contr_y')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'contratação de Y'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_demanda_latente WHERE id = (s->>'dem_y')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'demanda latente de Y'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_avaliacoes WHERE id = (s->>'aval_a')::uuid AND direcao = 'cliente_para_especialista'; IF n <> 1 THEN falhas := array_append(falhas, 'controle: avaliação pública de especialista deveria ser legível'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Como usuário de X: escrever em nome de Y'; r.esperado := 'recusado ou nada muda';
  BEGIN
    INSERT INTO public.marketplace_denuncias (tenant_id, profissional_id, denunciante_id, denunciante_nome, tipo, descricao) VALUES ((s->>'t2')::uuid, (s->>'a_prof')::uuid, (s->>'x')::uuid, 'QA Empresa 110x', 'outro', 'denúncia em nome de outra empresa');
    falhas := array_append(falhas, 'INSERT de denúncia com tenant de Y foi aceito');
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  UPDATE public.marketplace_contratacoes SET observacoes = 'invadido' WHERE id = (s->>'contr_y')::uuid; GET DIAGNOSTICS n = ROW_COUNT; IF n > 0 THEN falhas := array_append(falhas, 'UPDATE na contratação de Y alterou linha'); END IF;
  RESET ROLE;
  PERFORM set_config('app.qa_modo', 'on', true);
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF array_length(falhas, 1) IS NULL THEN
    r.situacao := 'passou'; r.obtido := 'X não lê leads, mensagens, denúncias, contratações nem demanda latente de Y, e não escreve em nome de Y; lê a própria conversa e as avaliações públicas de especialistas.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; ');
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE; PERFORM set_config('app.qa_modo', 'on', true); PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-112 — estrutura do RLS: toda tabela com política; nada permissivo demais; colunas sensíveis fechadas
CREATE OR REPLACE FUNCTION public.qa_caso_mky_112()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; falhas text[] := '{}'; v text;
BEGIN
  r.passo_ordem := 1; r.passo_acao := 'Tabelas marketplace_* com RLS ligado e zero políticas, ou sem RLS'; r.esperado := 'nenhuma';
  SELECT string_agg(c.relname, ', ') INTO v FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relname LIKE 'marketplace_%' AND c.relrowsecurity
    AND NOT EXISTS (SELECT 1 FROM pg_policies p WHERE p.schemaname = 'public' AND p.tablename = c.relname);
  IF v IS NOT NULL THEN falhas := array_append(falhas, 'RLS ligado sem política (inacessível por engano): ' || v); END IF;
  SELECT string_agg(c.relname, ', ') INTO v FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relname LIKE 'marketplace_%' AND NOT c.relrowsecurity;
  IF v IS NOT NULL THEN falhas := array_append(falhas, 'sem RLS: ' || v); END IF;

  r.passo_ordem := 2; r.passo_acao := 'Políticas com USING true ou WITH CHECK true em tabela sensível'; r.esperado := 'só nas públicas por desenho (categorias, escopo, config, pacotes) e nas de conteúdo público com colunas fechadas (avaliações, reputação)';
  SELECT string_agg(p.tablename || '.' || p.policyname, ', ') INTO v FROM pg_policies p
  WHERE p.schemaname = 'public' AND p.tablename LIKE 'marketplace_%'
    AND (btrim(COALESCE(p.qual, '')) = 'true' OR btrim(COALESCE(p.with_check, '')) = 'true')
    AND p.tablename NOT IN ('marketplace_categorias', 'marketplace_escopo_habilitacao', 'marketplace_config', 'marketplace_pacotes', 'marketplace_avaliacoes', 'marketplace_reputacao');
  IF v IS NOT NULL THEN falhas := array_append(falhas, 'política permissiva demais: ' || v); END IF;
  SELECT string_agg(p.tablename || '.' || p.policyname, ', ') INTO v FROM pg_policies p
  WHERE p.schemaname = 'public' AND p.tablename LIKE 'marketplace_%' AND btrim(COALESCE(p.with_check, '')) = 'true';
  IF v IS NOT NULL THEN falhas := array_append(falhas, 'WITH CHECK true (escrita aberta): ' || v); END IF;

  r.passo_ordem := 3; r.passo_acao := 'Colunas sensíveis legíveis por authenticated ou anon'; r.esperado := 'nenhuma';
  SELECT string_agg(table_name || '.' || column_name || ' (' || grantee || ')', ', ') INTO v FROM information_schema.column_privileges
  WHERE table_schema = 'public' AND privilege_type = 'SELECT' AND grantee IN ('authenticated', 'anon')
    AND ((table_name = 'marketplace_profissionais' AND column_name IN ('email', 'telefone', 'cpf_cnpj', 'user_id', 'tenant_id'))
      OR (table_name = 'marketplace_avaliacoes' AND column_name IN ('tenant_id', 'avaliador_id'))
      OR (table_name = 'marketplace_reputacao' AND column_name IN ('nivel_aviso_motivo', 'nivel_aviso_em')));
  IF v IS NOT NULL THEN falhas := array_append(falhas, 'coluna sensível exposta: ' || v); END IF;
  -- Leitura de tabela inteira (sem restrição de coluna) nas três tabelas com colunas sensíveis:
  SELECT string_agg(table_name || ' (' || grantee || ')', ', ') INTO v FROM information_schema.role_table_grants
  WHERE table_schema = 'public' AND privilege_type = 'SELECT' AND grantee IN ('authenticated', 'anon')
    AND table_name IN ('marketplace_profissionais', 'marketplace_avaliacoes', 'marketplace_reputacao');
  IF v IS NOT NULL THEN falhas := array_append(falhas, 'SELECT de tabela inteira onde deveria ser por coluna: ' || v); END IF;

  IF array_length(falhas, 1) IS NULL THEN
    r.situacao := 'passou'; r.obtido := 'Toda tabela do módulo tem RLS e política; nenhuma política aberta fora das públicas por desenho; e-mail, telefone, documento, avaliador e aviso de nível não são legíveis por usuário comum.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; ');
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-113 — UPDATE/DELETE onde o papel só tem SELECT: zero linhas e valor inalterado
CREATE OR REPLACE FUNCTION public.qa_caso_mky_113()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; n int; v_nota numeric; v_texto text; v_status text; v_lib boolean; v_nivel text; v_cons int;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  SELECT count(*) INTO v_cons FROM public.marketplace_consentimentos WHERE profissional_id = (s->>'a_prof')::uuid;
  r.passo_ordem := 1; r.passo_acao := 'Como A: alterar a avaliação recebida, a mensagem da empresa, o próprio consentimento, a própria reputação e o próprio lead'; r.esperado := '0 linhas em todos';
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  PERFORM set_config('app.qa_modo', 'off', true);  -- a trava do cercado lê tenants sob RLS como authenticated (ver MKY-001)
  SET LOCAL ROLE authenticated;
  BEGIN UPDATE public.marketplace_avaliacoes SET nota_geral = 5 WHERE id = (s->>'aval_a')::uuid; GET DIAGNOSTICS n = ROW_COUNT; IF n > 0 THEN falhas := array_append(falhas, 'avaliação recebida alterada'); END IF; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN UPDATE public.marketplace_lead_mensagens SET texto = 'invadido' WHERE id = (s->>'msg_ya')::uuid; GET DIAGNOSTICS n = ROW_COUNT; IF n > 0 THEN falhas := array_append(falhas, 'mensagem da empresa alterada'); END IF; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN DELETE FROM public.marketplace_consentimentos WHERE profissional_id = (s->>'a_prof')::uuid; GET DIAGNOSTICS n = ROW_COUNT; IF n > 0 THEN falhas := array_append(falhas, 'consentimento apagado'); END IF; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN UPDATE public.marketplace_reputacao SET nivel = 'top' WHERE profissional_id = (s->>'a_prof')::uuid; GET DIAGNOSTICS n = ROW_COUNT; IF n > 0 THEN falhas := array_append(falhas, 'reputação alterada'); END IF; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN UPDATE public.marketplace_leads SET status = 'ganho' WHERE id = (s->>'lead_xb')::uuid; GET DIAGNOSTICS n = ROW_COUNT; IF n > 0 THEN falhas := array_append(falhas, 'lead alterado pelo especialista'); END IF; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  RESET ROLE;
  r.passo_ordem := 2; r.passo_acao := 'Como usuário de X: liberar o contato e mudar o status direto na tabela'; r.esperado := '0 linhas';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  SET LOCAL ROLE authenticated;
  BEGIN UPDATE public.marketplace_leads SET contato_liberado = true, status = 'ganho' WHERE id = (s->>'lead_xb')::uuid; GET DIAGNOSTICS n = ROW_COUNT; IF n > 0 THEN falhas := array_append(falhas, 'lead alterado pela empresa'); END IF; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  RESET ROLE;
  PERFORM set_config('app.qa_modo', 'on', true);
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.passo_ordem := 3; r.passo_acao := 'Reler os valores como o dono do banco'; r.esperado := 'tudo como antes';
  SELECT nota_geral INTO v_nota FROM public.marketplace_avaliacoes WHERE id = (s->>'aval_a')::uuid;
  SELECT texto INTO v_texto FROM public.marketplace_lead_mensagens WHERE id = (s->>'msg_ya')::uuid;
  SELECT status::text, contato_liberado INTO v_status, v_lib FROM public.marketplace_leads WHERE id = (s->>'lead_xb')::uuid;
  SELECT nivel INTO v_nivel FROM public.marketplace_reputacao WHERE profissional_id = (s->>'a_prof')::uuid;
  SELECT count(*) INTO n FROM public.marketplace_consentimentos WHERE profissional_id = (s->>'a_prof')::uuid;
  IF v_nota = 5 OR v_texto = 'invadido' OR v_status = 'ganho' OR v_lib OR v_nivel = 'top' OR n <> v_cons THEN
    falhas := array_append(falhas, format('valor mudou (nota %s, texto %s, status %s, liberado %s, nível %s, consentimentos %s/%s)', v_nota, v_texto, v_status, v_lib, v_nivel, n, v_cons));
  END IF;
  IF array_length(falhas, 1) IS NULL THEN
    r.situacao := 'passou'; r.obtido := 'Toda escrita direta onde o papel só lê foi negada ou afetou 0 linhas, e nada mudou: avaliação, mensagem, consentimento, reputação e lead intactos.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; ');
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE; PERFORM set_config('app.qa_modo', 'on', true); PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-114 — superfície de EXECUTE: anon só nas públicas; internas só service_role; anon barrado nas sensíveis
CREATE OR REPLACE FUNCTION public.qa_caso_mky_114()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_claims text; falhas text[] := '{}'; v text; v_msg text; f text;
BEGIN
  v_claims := current_setting('request.jwt.claims', true);
  r.passo_ordem := 1; r.passo_acao := 'Funções marketye_* executáveis por anon'; r.esperado := 'só marketye_vitrine_publica, marketye_vagas_demanda e marketye_meu_id (devolve nulo sem sessão; as políticas a chamam)';
  SELECT string_agg(p.proname, ', ' ORDER BY p.proname) INTO v FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname LIKE 'marketye_%' AND has_function_privilege('anon', p.oid, 'EXECUTE')
    AND p.proname NOT IN ('marketye_vitrine_publica', 'marketye_vagas_demanda', 'marketye_meu_id');
  IF v IS NOT NULL THEN falhas := array_append(falhas, 'anon executa: ' || v); END IF;
  SELECT string_agg(p.proname, ', ') INTO v FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname IN ('marketye_vitrine_publica', 'marketye_vagas_demanda') AND NOT has_function_privilege('anon', p.oid, 'EXECUTE');
  IF v IS NOT NULL THEN falhas := array_append(falhas, 'controle: a página pública precisa de anon em ' || v); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Funções internas executáveis por authenticated ou anon'; r.esperado := 'nenhuma (só service_role)';
  SELECT string_agg(p.proname, ', ') INTO v FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname IN ('marketye_buscar_interno', 'marketye_cadastrar_especialista_para', 'marketye_recalcular_reputacao', 'marketye_semear_ilha_teste')
    AND (has_function_privilege('anon', p.oid, 'EXECUTE') OR has_function_privilege('authenticated', p.oid, 'EXECUTE'));
  IF v IS NOT NULL THEN falhas := array_append(falhas, 'interna exposta: ' || v); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Como anon: chamar moderação, ajustes, painel e busca'; r.esperado := 'recusado antes de qualquer efeito';
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  SET LOCAL ROLE anon;
  FOREACH f IN ARRAY ARRAY['SELECT public.marketye_moderar_especialista(gen_random_uuid(), ''aprovado'', NULL, true)',
                           'SELECT public.marketye_config_salvar(''relevancia_pesos'', ''{}''::jsonb, NULL)',
                           'SELECT public.marketye_painel_liquidez()',
                           'SELECT public.marketye_buscar(''{}''::jsonb)',
                           'SELECT public.marketye_moderacao_fila()'] LOOP
    BEGIN
      EXECUTE f;
      falhas := array_append(falhas, 'anon executou sem barreira: ' || f);
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    WHEN OTHERS THEN falhas := array_append(falhas, 'anon chegou a rodar a função (erro interno, não de permissão): ' || left(f, 60) || ' -> ' || SQLERRM);
    END;
  END LOOP;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF array_length(falhas, 1) IS NULL THEN
    r.situacao := 'passou'; r.obtido := 'anon só executa a vitrine pública, as vagas de demanda e a consulta do próprio id; internas só service_role; moderação, ajustes, painel, fila e busca recusam o visitante por permissão.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; ');
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE; PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-115 — entrada hostil vira texto; busca não quebra com curingas e aspas
CREATE OR REPLACE FUNCTION public.qa_caso_mky_115()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; e record; v_claims text; falhas text[] := '{}'; v_t uuid := public.qa_sandbox_tenant_id(); v_u uuid; v_nome text; v_desc text; v_an uuid; q text; v jsonb;
        v_hostil text := 'Robert''); DROP TABLE marketplace_leads;--';
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  v_u := public.qa_mky_usuario_empresa(v_t, '115');
  SELECT * INTO e FROM public.qa_mky_especialista('115', '900.000.030-00');
  r.passo_ordem := 1; r.passo_acao := 'Salvar nome com injeção SQL e apresentação com HTML'; r.esperado := 'gravados como texto; tabela intacta';
  PERFORM public.qa_mky_claims(e.uid);
  PERFORM public.marketye_meu_perfil_salvar(jsonb_build_object('nome_completo', v_hostil, 'bio', '<script>alert(1)</script> apresentação de teste'));
  SELECT nome_completo, bio INTO v_nome, v_desc FROM public.marketplace_profissionais WHERE id = e.prof_id;
  IF v_nome <> v_hostil THEN falhas := array_append(falhas, 'nome não ficou literal: ' || COALESCE(v_nome, 'NULL')); END IF;
  IF v_desc NOT LIKE '<script>%' THEN falhas := array_append(falhas, 'apresentação não ficou literal'); END IF;
  IF to_regclass('public.marketplace_leads') IS NULL THEN falhas := array_append(falhas, 'tabela marketplace_leads sumiu'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Salvar anúncio com HTML na descrição'; r.esperado := 'texto literal';
  v := public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Anuncio 115', 'descricao', '<img src=x onerror=alert(1)> descrição fictícia de teste', 'modalidade', 'online', 'tipo_preco', 'sob_orcamento'));
  v_an := (v->>'id')::uuid;
  SELECT descricao INTO v_desc FROM public.marketplace_servicos WHERE id = v_an;
  IF v_desc NOT LIKE '<img src=x onerror=alert(1)>%' THEN falhas := array_append(falhas, 'descrição do anúncio não ficou literal'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Buscar com curingas, aspas e barra'; r.esperado := 'sem erro';
  PERFORM public.qa_mky_claims(v_u);
  FOREACH q IN ARRAY ARRAY['%', '_', '''', '\', '"; DROP TABLE marketplace_leads;--', '%%%', '\%'] LOOP
    BEGIN
      v := public.marketye_buscar(jsonb_build_object('q', q, 'ignorar_uf_padrao', true));
    EXCEPTION WHEN OTHERS THEN falhas := array_append(falhas, 'busca quebrou com ' || quote_literal(q) || ': ' || SQLERRM); END;
  END LOOP;
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF array_length(falhas, 1) IS NULL THEN
    r.situacao := 'passou'; r.obtido := 'Injeção e HTML ficaram como texto, a tabela continua, e a busca aceitou curingas, aspas e barra sem erro.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; ');
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-116 — escrita direta nas tabelas expostas por usuário autenticado é recusada
CREATE OR REPLACE FUNCTION public.qa_caso_mky_116()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; n int; v_sql text; v_msg text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  PERFORM set_config('app.qa_modo', 'off', true);
  r.passo_ordem := 1; r.passo_acao := 'Como usuário de X: INSERT direto em leads, mensagens, avaliações, demanda latente e configuração'; r.esperado := 'recusado pelo RLS (42501) em todos';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  SET LOCAL ROLE authenticated;
  FOREACH v_sql IN ARRAY ARRAY[
    format('INSERT INTO public.marketplace_leads (tenant_id, profissional_id, servico_id, criado_por) VALUES (%L, %L, %L, %L)', s->>'t1', s->>'b_prof', s->>'b_pub', s->>'x'),
    format('INSERT INTO public.marketplace_lead_mensagens (lead_id, autor_tipo, autor_id, texto) VALUES (%L, ''cliente'', %L, ''me liga no 46 99999-0000'')', s->>'lead_xb', s->>'x'),
    format('INSERT INTO public.marketplace_avaliacoes (profissional_id, tenant_id, lead_id, direcao, nota_geral, avaliador_id) VALUES (%L, %L, %L, ''cliente_para_especialista'', 5, %L)', s->>'b_prof', s->>'t1', s->>'lead_xb', s->>'x'),
    format('INSERT INTO public.marketplace_demanda_latente (tenant_id, uf, termos, resultados) VALUES (%L, ''QA'', ''x'', 0)', s->>'t1'),
    'INSERT INTO public.marketplace_config (chave, versao, valor, vigente) VALUES (''relevancia_pesos'', 999, ''{}''::jsonb, true)'
  ] LOOP
    BEGIN
      EXECUTE v_sql;
      falhas := array_append(falhas, 'aceito: ' || left(v_sql, 70));
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    WHEN OTHERS THEN falhas := array_append(falhas, 'passou pelo RLS e caiu em outra barreira (' || SQLSTATE || '): ' || left(v_sql, 60));
    END;
  END LOOP;
  BEGIN UPDATE public.marketplace_config SET valor = '{}'::jsonb WHERE vigente; GET DIAGNOSTICS n = ROW_COUNT; IF n > 0 THEN falhas := array_append(falhas, 'UPDATE em marketplace_config alterou linhas'); END IF; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  -- Controle positivo: a mesma pessoa escreve pela porta certa.
  BEGIN PERFORM public.marketye_lead_mensagem((s->>'lead_xb')::uuid, 'Mensagem pela função, permitida.'); EXCEPTION WHEN OTHERS THEN falhas := array_append(falhas, 'controle: a função de mensagem falhou: ' || SQLERRM); END;
  RESET ROLE;
  r.passo_ordem := 2; r.passo_acao := 'Como especialista A: INSERT direto em reputação, destaques, consentimentos, contestações e ocorrências'; r.esperado := 'recusado pelo RLS (42501) em todos';
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  SET LOCAL ROLE authenticated;
  FOREACH v_sql IN ARRAY ARRAY[
    format('INSERT INTO public.marketplace_reputacao (profissional_id, nivel) VALUES (%L, ''top'')', gen_random_uuid()),
    format('INSERT INTO public.marketplace_destaques (profissional_id, tipo, inicio, fim, ativo) VALUES (%L, ''topo'', CURRENT_DATE, CURRENT_DATE + 30, true)', s->>'a_prof'),
    format('INSERT INTO public.marketplace_consentimentos (profissional_id, tipo, versao) VALUES (%L, ''termos_especialista'', ''falsa'')', s->>'a_prof'),
    format('INSERT INTO public.marketplace_contestacoes (profissional_id, decisao_tipo, motivo) VALUES (%L, ''outro'', ''contestação por fora da função'')', s->>'a_prof'),
    format('INSERT INTO public.marketplace_ocorrencias (profissional_id, tipo, descricao) VALUES (%L, ''ocorrencia'', ''apagando o histórico'')', s->>'b_prof')
  ] LOOP
    BEGIN
      EXECUTE v_sql;
      falhas := array_append(falhas, 'aceito: ' || left(v_sql, 70));
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    WHEN OTHERS THEN falhas := array_append(falhas, 'passou pelo RLS e caiu em outra barreira (' || SQLSTATE || '): ' || left(v_sql, 60));
    END;
  END LOOP;
  RESET ROLE;
  PERFORM set_config('app.qa_modo', 'on', true);
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF array_length(falhas, 1) IS NULL THEN
    r.situacao := 'passou'; r.obtido := 'Nenhuma escrita direta passou: leads, mensagens, avaliações, demanda latente, configuração, reputação, destaques, consentimentos, contestações e ocorrências só aceitam a porta das funções.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; ');
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE; PERFORM set_config('app.qa_modo', 'on', true); PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ---------------------------------------------------------------------
-- 6) Registro das rotinas
-- ---------------------------------------------------------------------
INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES
  ('MKY-110', 'qa_caso_mky_110'), ('MKY-111', 'qa_caso_mky_111'), ('MKY-112', 'qa_caso_mky_112'), ('MKY-113', 'qa_caso_mky_113'),
  ('MKY-114', 'qa_caso_mky_114'), ('MKY-115', 'qa_caso_mky_115'), ('MKY-116', 'qa_caso_mky_116')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
