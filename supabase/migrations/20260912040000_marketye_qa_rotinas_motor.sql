-- =====================================================================
-- MARKETYE · ROTINAS DO MOTOR (banco) PARA OS CASOS DOCUMENTADOS — 12/09/2026
--
-- Implementa qa_caso_mky_* para os 58 casos de nível 'api' que o motor SQL
-- consegue executar (famílias 030 cadastro, 040 moderação, 050 anúncio,
-- 060 busca, 070 conversa, 080 avaliação/reputação, 090 LGPD, 100 ajustes,
-- 120 integrações). Executam em Super Admin → QA e Testes → Executar testes →
-- Motor (banco), módulo MarketYE (path rede-parceiros), ou por
-- SELECT * FROM public.qa_rodar_bateria('manual', 'rede-parceiros').
--
-- Regras seguidas:
--   · cada rotina nasce de um caso documentado e roda dentro de
--     qa_executar_descartavel (transação descartada; cercados qa-sandbox);
--   · a rotina é honesta: quando o produto contraria o caso ela FALHA e o
--     texto de "obtido" começa com ACHADO. Os 17 casos que falham hoje ganham
--     disposição bug_confirmado (16) ou aguardando_construcao (1) com o motivo,
--     na parte 4 abaixo — a bateria mostra falhou, e a conferência do script
--     de entrega só considera inesperada a falha de caso em_triagem;
--   · simulação de papel por claims (request.jwt.claims) e, quando a
--     prova exige RLS, SET LOCAL ROLE authenticated/anon. A trava do
--     cercado lê tenants sob RLS, por isso os blocos com papel trocado
--     desligam app.qa_modo só naquele trecho (ver MKY-001/111);
--   · restauração de claims volta a um JSON vazio, nunca a string vazia
--     (no SQL Editor as claims são nulas e a string vazia quebra auth.uid()).
--
-- Ficam fora desta leva (ver docs/QA_MARKETYE.md): 039, 069, 120, 146
-- (aguardando construção), 091 (decisão de produto), 160/161 (fora de
-- escopo), 117 (Edge Function), 104 e 130..135 (IA) e todos os casos e2e.
-- =====================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- 1) Ajudantes e rotinas por família
-- ---------------------------------------------------------------------

-- ===== Ajudantes (revisão) =====
-- qa_mky_cenario_seguranca: a restauração das claims volta a um JSON vazio ('{}') em vez de string vazia; no SQL Editor (claims nulas)
-- a string vazia quebrava qualquer auth.uid() chamado depois do cenário ("invalid input syntax for type json").
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
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);

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

-- ===== Família A — cadastro e verificação (MKY-031..038) =====
-- MKY-031 — DV inválido recusado; formatação não importa
CREATE OR REPLACE FUNCTION public.qa_caso_mky_031()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; falhas text[] := '{}'; v_uid uuid; v_msg text; v_res jsonb; v_doc text;
BEGIN
  PERFORM public.qa_mky_limpar();
  r.passo_ordem := 1; r.passo_acao := 'Cadastrar com CPF 900.000.012-99 (DV errado)'; r.esperado := 'recusado';
  v_uid := gen_random_uuid(); INSERT INTO auth.users (id, email) VALUES (v_uid, 'qa-mky-031a-' || left(v_uid::text, 8) || '@sandbox.invalid');
  BEGIN
    PERFORM public.marketye_cadastrar_especialista_para(v_uid, jsonb_build_object('nome_completo', 'QA Especialista 031', 'email', 'qa-mky-031a@sandbox.invalid', 'cpf_cnpj', '900.000.012-99', 'aceite_termos', true, 'tenant_origem', public.qa_sandbox_tenant_id()));
    falhas := array_append(falhas, 'CPF com DV errado foi aceito');
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  r.passo_ordem := 2; r.passo_acao := 'Cadastrar com CNPJ 12.345.678/0001-00 (DV errado)'; r.esperado := 'recusado';
  BEGIN
    PERFORM public.marketye_cadastrar_especialista_para(v_uid, jsonb_build_object('nome_completo', 'QA Especialista 031', 'email', 'qa-mky-031a@sandbox.invalid', 'cpf_cnpj', '12.345.678/0001-00', 'tipo_pessoa', 'pj', 'aceite_termos', true, 'tenant_origem', public.qa_sandbox_tenant_id()));
    falhas := array_append(falhas, 'CNPJ com DV errado foi aceito');
  EXCEPTION WHEN OTHERS THEN NULL; END;
  r.passo_ordem := 3; r.passo_acao := 'Cadastrar com CPF formatado e DV correto'; r.esperado := 'aceito; guardado só com dígitos';
  v_res := public.marketye_cadastrar_especialista_para(v_uid, jsonb_build_object('nome_completo', 'QA Especialista 031', 'email', 'qa-mky-031a-' || left(v_uid::text, 8) || '@sandbox.invalid', 'cpf_cnpj', '900.000.031-90', 'aceite_termos', true, 'tenant_origem', public.qa_sandbox_tenant_id()));
  SELECT cpf_cnpj INTO v_doc FROM public.marketplace_profissionais WHERE id = (v_res->>'id')::uuid;
  IF public.marketye_so_digitos(v_doc) <> '90000003190' THEN falhas := array_append(falhas, 'documento gravado diferente do esperado: ' || COALESCE(v_doc, 'NULL')); END IF;
  IF array_length(falhas, 1) IS NULL THEN
    r.situacao := 'passou'; r.obtido := 'CPF e CNPJ com dígito errado recusados (' || COALESCE(left(v_msg, 60), '') || '); CPF formatado e válido aceito e guardado como ' || v_doc || '.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-032 — um CNPJ, uma conta; exclusão LGPD libera o documento
CREATE OR REPLACE FUNCTION public.qa_caso_mky_032()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; falhas text[] := '{}'; u1 uuid := gen_random_uuid(); u2 uuid := gen_random_uuid(); u3 uuid := gen_random_uuid(); v_res jsonb; v_msg text := 'ok'; v_claims text; v_t uuid := public.qa_sandbox_tenant_id();
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  INSERT INTO auth.users (id, email) VALUES (u1, 'qa-mky-032a-' || left(u1::text, 8) || '@sandbox.invalid'), (u2, 'qa-mky-032b-' || left(u2::text, 8) || '@sandbox.invalid'), (u3, 'qa-mky-032c-' || left(u3::text, 8) || '@sandbox.invalid');
  r.passo_ordem := 1; r.passo_acao := 'Cadastrar PJ com CNPJ fictício válido'; r.esperado := 'aceito';
  v_res := public.marketye_cadastrar_especialista_para(u1, jsonb_build_object('nome_completo', 'QA Especialista 032 PJ', 'email', 'qa-mky-032a-' || left(u1::text, 8) || '@sandbox.invalid', 'cpf_cnpj', '12.345.678/0001-95', 'tipo_pessoa', 'pj', 'aceite_termos', true, 'tenant_origem', v_t));
  r.passo_ordem := 2; r.passo_acao := 'Outra conta com o mesmo CNPJ só com dígitos'; r.esperado := 'recusado: já possui cadastro';
  BEGIN
    PERFORM public.marketye_cadastrar_especialista_para(u2, jsonb_build_object('nome_completo', 'QA Especialista 032 dup', 'email', 'qa-mky-032b-' || left(u2::text, 8) || '@sandbox.invalid', 'cpf_cnpj', '12345678000195', 'tipo_pessoa', 'pj', 'aceite_termos', true, 'tenant_origem', v_t));
    v_msg := 'aceitou';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_msg NOT LIKE '%já possui cadastro%' THEN falhas := array_append(falhas, 'CNPJ repetido: ' || v_msg); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Excluir (LGPD) o primeiro e cadastrar de novo o mesmo CNPJ'; r.esperado := 'aceito';
  PERFORM public.qa_mky_claims(u1); PERFORM public.marketye_excluir_meu_perfil('EXCLUIR');
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  BEGIN
    v_res := public.marketye_cadastrar_especialista_para(u3, jsonb_build_object('nome_completo', 'QA Especialista 032 novo', 'email', 'qa-mky-032c-' || left(u3::text, 8) || '@sandbox.invalid', 'cpf_cnpj', '12.345.678/0001-95', 'tipo_pessoa', 'pj', 'aceite_termos', true, 'tenant_origem', v_t));
  EXCEPTION WHEN OTHERS THEN falhas := array_append(falhas, 'recadastro após exclusão recusado: ' || SQLERRM); END;
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'CNPJ único por dígitos; depois da exclusão LGPD o mesmo CNPJ volta a poder se cadastrar.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-033 — sem aceite não entra; com aceite, três consentimentos versionados com IP e navegador
CREATE OR REPLACE FUNCTION public.qa_caso_mky_033()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; falhas text[] := '{}'; u uuid := gen_random_uuid(); v_res jsonb; v_msg text := 'ok'; n int; v_versoes jsonb; v_status text; v_cv text; v_ce timestamptz; v_t uuid := public.qa_sandbox_tenant_id();
BEGIN
  PERFORM public.qa_mky_limpar();
  INSERT INTO auth.users (id, email) VALUES (u, 'qa-mky-033-' || left(u::text, 8) || '@sandbox.invalid');
  r.passo_ordem := 1; r.passo_acao := 'Cadastrar com aceite_termos = false'; r.esperado := 'recusado';
  BEGIN
    PERFORM public.marketye_cadastrar_especialista_para(u, jsonb_build_object('nome_completo', 'QA Especialista 033', 'email', 'qa-mky-033-' || left(u::text, 8) || '@sandbox.invalid', 'cpf_cnpj', '900.000.032-71', 'aceite_termos', false, 'tenant_origem', v_t));
    v_msg := 'aceitou';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_msg = 'aceitou' THEN falhas := array_append(falhas, 'cadastro sem aceite foi aceito'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Cadastrar com aceite, ip e user_agent'; r.esperado := '3 consentimentos com as versões vigentes, ip e navegador';
  v_res := public.marketye_cadastrar_especialista_para(u, jsonb_build_object('nome_completo', 'QA Especialista 033', 'email', 'qa-mky-033-' || left(u::text, 8) || '@sandbox.invalid', 'cpf_cnpj', '900.000.032-71', 'aceite_termos', true, 'ip', '203.0.113.7', 'user_agent', 'QA/1.0', 'tenant_origem', v_t));
  v_versoes := public.marketye_config('termos_versoes');
  SELECT count(*) INTO n FROM public.marketplace_consentimentos c WHERE c.profissional_id = (v_res->>'id')::uuid
    AND c.tipo IN ('termos_especialista', 'privacidade_nao_usuario', 'codigo_etica') AND c.versao = v_versoes->>c.tipo AND c.ip IS NOT NULL AND c.user_agent IS NOT NULL;
  IF n <> 3 THEN falhas := array_append(falhas, format('consentimentos completos (versão vigente + ip + navegador): %s de 3', n)); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Ler o perfil'; r.esperado := 'consentimento_versao e consentimento_em preenchidos; status pendente';
  SELECT status::text, consentimento_versao, consentimento_em INTO v_status, v_cv, v_ce FROM public.marketplace_profissionais WHERE id = (v_res->>'id')::uuid;
  IF v_status <> 'pendente' OR v_cv IS NULL OR v_ce IS NULL THEN falhas := array_append(falhas, format('perfil: status %s, versão %s, data %s', v_status, v_cv, v_ce)); END IF;
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Sem aceite recusa (' || left(v_msg, 50) || '); com aceite grava três consentimentos com versão vigente, IP e navegador; perfil nasce pendente com a versão registrada.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-034 — usuário de empresa vira especialista com a mesma conta, sem duplicar
CREATE OR REPLACE FUNCTION public.qa_caso_mky_034()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; falhas text[] := '{}'; v_claims text; x uuid; v_res jsonb; v_res2 jsonb; v_uid uuid; v_tenant uuid; v_meu uuid; v_t uuid := public.qa_sandbox_tenant_id();
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  x := public.qa_mky_usuario_empresa(v_t, '034');
  r.passo_ordem := 1; r.passo_acao := 'Como usuário de empresa, chamar marketye_cadastrar_especialista'; r.esperado := 'cadastro ligado à conta e à empresa de origem; pendente';
  PERFORM public.qa_mky_claims(x);
  v_res := public.marketye_cadastrar_especialista(jsonb_build_object('nome_completo', 'QA Especialista 034', 'email', 'qa-mky-034x@sandbox.invalid', 'cpf_cnpj', '900.000.033-52', 'aceite_termos', true));
  SELECT user_id, tenant_id INTO v_uid, v_tenant FROM public.marketplace_profissionais WHERE id = (v_res->>'id')::uuid;
  IF v_uid IS DISTINCT FROM x THEN falhas := array_append(falhas, 'user_id não é a conta que cadastrou'); END IF;
  IF v_tenant IS DISTINCT FROM v_t THEN falhas := array_append(falhas, 'empresa de origem não registrada'); END IF;
  IF v_res->>'status' <> 'pendente' THEN falhas := array_append(falhas, 'não nasceu pendente'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Chamar de novo'; r.esperado := 'ja_existia = true, sem duplicar';
  v_res2 := public.marketye_cadastrar_especialista(jsonb_build_object('nome_completo', 'QA Especialista 034', 'email', 'qa-mky-034x@sandbox.invalid', 'cpf_cnpj', '900.000.033-52', 'aceite_termos', true));
  IF NOT COALESCE((v_res2->>'ja_existia')::boolean, false) OR (v_res2->>'id') <> (v_res->>'id') THEN falhas := array_append(falhas, 'segunda chamada não devolveu o mesmo cadastro'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Consultar o próprio id de especialista'; r.esperado := 'igual ao cadastro';
  v_meu := public.marketye_meu_id();
  IF v_meu IS DISTINCT FROM (v_res->>'id')::uuid THEN falhas := array_append(falhas, 'marketye_meu_id não aponta para o cadastro'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Conta de empresa ganhou o papel de especialista com origem registrada, sem duplicar; a sessão resolve o próprio id.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-035 — área que exige registro só publica com conselho e número
CREATE OR REPLACE FUNCTION public.qa_caso_mky_035()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; falhas text[] := '{}'; v_claims text; u uuid := gen_random_uuid(); v_prof uuid; sa uuid; v_cat uuid; v_cat_livre uuid; v_an uuid; v_an2 uuid; v_res jsonb; v_msg text := 'ok'; v_t uuid := public.qa_sandbox_tenant_id();
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  sa := public.qa_mky_superadmin();
  INSERT INTO auth.users (id, email) VALUES (u, 'qa-mky-035-' || left(u::text, 8) || '@sandbox.invalid');
  v_res := public.marketye_cadastrar_especialista_para(u, jsonb_build_object('nome_completo', 'QA Especialista 035', 'email', 'qa-mky-035-' || left(u::text, 8) || '@sandbox.invalid', 'cpf_cnpj', '900.000.030-00', 'aceite_termos', true, 'tenant_origem', v_t));
  v_prof := (v_res->>'id')::uuid;
  PERFORM public.qa_mky_claims(sa); PERFORM public.marketye_moderar_especialista(v_prof, 'aprovado', NULL, true);
  SELECT id INTO v_cat FROM public.marketplace_categorias WHERE slug = 'pgr' AND exige_registro;
  SELECT id INTO v_cat_livre FROM public.marketplace_categorias WHERE slug = 'palestras-eventos';
  IF v_cat IS NULL OR v_cat_livre IS NULL THEN r.situacao := 'erro'; r.obtido := 'Taxonomia sem pgr (exige registro) ou palestras-eventos'; PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); RETURN r; END IF;
  r.passo_ordem := 1; r.passo_acao := 'Publicar anúncio em PGR sem registro profissional'; r.esperado := 'recusado com o conselho aceito na mensagem';
  PERFORM public.qa_mky_claims(u);
  v_an := (public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA PGR 035 sem registro', 'descricao', 'Serviço fictício de teste do MarketYE em área regulada.', 'categoria_id', v_cat, 'modalidade', 'presencial', 'tipo_preco', 'sob_orcamento'))->>'id')::uuid;
  BEGIN PERFORM public.marketye_anuncio_publicar(v_an); v_msg := 'publicou'; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_msg NOT ILIKE '%registro%' THEN falhas := array_append(falhas, 'publicou sem registro ou mensagem não fala em registro: ' || v_msg); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Informar conselho e número e publicar de novo'; r.esperado := 'publicado';
  PERFORM public.marketye_meu_perfil_salvar(jsonb_build_object('conselho', 'CREA', 'registro_profissional', 'PR-000035'));
  BEGIN PERFORM public.marketye_anuncio_publicar(v_an); EXCEPTION WHEN OTHERS THEN falhas := array_append(falhas, 'com registro ainda recusou: ' || SQLERRM); END;
  r.passo_ordem := 3; r.passo_acao := 'Outro especialista sem registro publica em Palestras e eventos'; r.esperado := 'publica';
  PERFORM public.marketye_meu_perfil_salvar(jsonb_build_object('conselho', '', 'registro_profissional', ''));
  v_an2 := (public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Palestra 035 livre', 'descricao', 'Palestra fictícia de teste do MarketYE em área livre.', 'categoria_id', v_cat_livre, 'modalidade', 'presencial', 'tipo_preco', 'sob_orcamento'))->>'id')::uuid;
  BEGIN PERFORM public.marketye_anuncio_publicar(v_an2); EXCEPTION WHEN OTHERS THEN falhas := array_append(falhas, 'área livre recusou sem registro: ' || SQLERRM); END;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Área regulada recusou sem registro (' || left(v_msg, 70) || '), publicou com registro; área livre publica sem registro. Regra vem da taxonomia.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-037 — apresentação com contato é mascarada ou recusada
CREATE OR REPLACE FUNCTION public.qa_caso_mky_037()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; falhas text[] := '{}'; v_claims text; e record; v_bio text; v_msg text := 'ok';
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  SELECT * INTO e FROM public.qa_mky_especialista('037', '900.000.031-90');
  r.passo_ordem := 1; r.passo_acao := 'Salvar apresentação com telefone e e-mail'; r.esperado := 'mascarada ou recusada';
  PERFORM public.qa_mky_claims(e.uid);
  BEGIN
    PERFORM public.marketye_meu_perfil_salvar(jsonb_build_object('bio', 'Fale comigo no (46) 99999-0000 ou joao@exemplo.test para combinar.'));
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  SELECT bio INTO v_bio FROM public.marketplace_profissionais WHERE id = e.prof_id;
  IF v_msg = 'ok' AND (v_bio LIKE '%99999-0000%' OR v_bio ILIKE '%joao@exemplo.test%') THEN
    falhas := array_append(falhas, 'apresentação gravada com telefone e e-mail em texto claro (a vitrine mostra a bio)');
  END IF;
  r.passo_ordem := 2; r.passo_acao := 'Salvar apresentação sem contato'; r.esperado := 'gravada intacta';
  PERFORM public.marketye_meu_perfil_salvar(jsonb_build_object('bio', 'Apresentação limpa de teste, sem canais diretos.'));
  SELECT bio INTO v_bio FROM public.marketplace_profissionais WHERE id = e.prof_id;
  IF v_bio <> 'Apresentação limpa de teste, sem canais diretos.' THEN falhas := array_append(falhas, 'apresentação limpa foi alterada'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Apresentação com contato ' || CASE WHEN v_msg = 'ok' THEN 'foi mascarada' ELSE 'foi recusada (' || left(v_msg, 60) || ')' END || '; apresentação limpa gravada intacta.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-038 — recadastro do mesmo CPF depois da exclusão LGPD não ressuscita o perfil antigo
CREATE OR REPLACE FUNCTION public.qa_caso_mky_038()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; falhas text[] := '{}'; v_claims text; e record; u2 uuid := gen_random_uuid(); v_res jsonb; v_nome text; v_exc timestamptz; n int; v_t uuid := public.qa_sandbox_tenant_id();
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  SELECT * INTO e FROM public.qa_mky_especialista('038', '900.000.032-71');
  PERFORM public.qa_mky_claims(e.uid); PERFORM public.marketye_excluir_meu_perfil('EXCLUIR');
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  r.passo_ordem := 1; r.passo_acao := 'Cadastrar de novo o mesmo CPF com outra conta'; r.esperado := 'aceito; novo id; pendente; sem anúncios';
  INSERT INTO auth.users (id, email) VALUES (u2, 'qa-mky-038b-' || left(u2::text, 8) || '@sandbox.invalid');
  v_res := public.marketye_cadastrar_especialista_para(u2, jsonb_build_object('nome_completo', 'QA Especialista 038 volta', 'email', 'qa-mky-038b-' || left(u2::text, 8) || '@sandbox.invalid', 'cpf_cnpj', '900.000.032-71', 'aceite_termos', true, 'tenant_origem', v_t));
  IF (v_res->>'id')::uuid = e.prof_id THEN falhas := array_append(falhas, 'reaproveitou o id antigo'); END IF;
  IF v_res->>'status' <> 'pendente' THEN falhas := array_append(falhas, 'não nasceu pendente'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_servicos WHERE profissional_id = (v_res->>'id')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'novo perfil já tem anúncios'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Consultar o perfil antigo'; r.esperado := 'anonimizado e fora da vitrine';
  SELECT nome_completo, excluido_em INTO v_nome, v_exc FROM public.marketplace_profissionais WHERE id = e.prof_id;
  IF v_exc IS NULL OR v_nome <> 'Especialista removido' THEN falhas := array_append(falhas, 'perfil antigo não continua anonimizado'); END IF;
  SELECT count(*) INTO n FROM public.marketye_buscar_interno(jsonb_build_object('q', 'QA Especialista 038')) x WHERE (x->'profissional'->>'id')::uuid = e.prof_id;
  IF n > 0 THEN falhas := array_append(falhas, 'perfil antigo apareceu na busca'); END IF;
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Mesmo CPF volta como perfil novo e pendente; o antigo segue anonimizado e invisível.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ===== Família B — moderação, denúncia, situação, transparência, devido processo (MKY-041..046) =====
-- MKY-041 — funções administrativas negam empresa, especialista e visitante
CREATE OR REPLACE FUNCTION public.qa_caso_mky_041()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v_papel text; v_uid uuid; v_fn text; v_msg text;
        n_aud int; n_oc int; n_dest int; n_cfg int; n int; v jsonb; v_st text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  SELECT count(*) INTO n_aud FROM public.marketplace_audit_log; SELECT count(*) INTO n_oc FROM public.marketplace_ocorrencias;
  SELECT count(*) INTO n_dest FROM public.marketplace_destaques; SELECT count(*) INTO n_cfg FROM public.marketplace_config;
  FOR v_papel, v_uid IN SELECT * FROM (VALUES ('empresa', (s->>'x')::uuid), ('especialista', (s->>'a_uid')::uuid), ('visitante', NULL::uuid)) t(papel, uid) LOOP
    r.passo_ordem := CASE v_papel WHEN 'empresa' THEN 1 WHEN 'especialista' THEN 2 ELSE 3 END;
    r.passo_acao := 'Chamar moderar, situação, decidir denúncia, decidir contestação, destaque e config como ' || v_papel; r.esperado := 'todas recusam com "Acesso negado"';
    IF v_uid IS NULL THEN PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true); ELSE PERFORM public.qa_mky_claims(v_uid); END IF;
    FOREACH v_fn IN ARRAY ARRAY['moderar', 'situacao', 'denuncia', 'contestacao', 'destaque', 'config'] LOOP
      v_msg := 'aceitou';
      BEGIN
        CASE v_fn
          WHEN 'moderar' THEN PERFORM public.marketye_moderar_especialista((s->>'b_prof')::uuid, 'rejeitado', 'motivo indevido de teste', false);
          WHEN 'situacao' THEN PERFORM public.marketye_especialista_situacao((s->>'b_prof')::uuid, 'suspenso', 'suspensão indevida de teste');
          WHEN 'denuncia' THEN PERFORM public.marketye_denuncia_decidir((s->>'den_y')::uuid, 'procedente', 'decisão indevida de teste');
          WHEN 'contestacao' THEN PERFORM public.marketye_contestacao_decidir((s->>'contest_b')::uuid, 'indeferida', 'resposta indevida de teste');
          WHEN 'destaque' THEN PERFORM public.marketye_destaque_criar((s->>'b_prof')::uuid, NULL, 'topo', NULL, NULL, CURRENT_DATE, CURRENT_DATE + 1, NULL);
          WHEN 'config' THEN PERFORM public.marketye_config_salvar('piso_nota', '{"nota": 1, "minimo_avaliacoes": 1}'::jsonb, 'indevido', 'BR');
        END CASE;
      EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
      IF v_msg <> 'Acesso negado' THEN falhas := array_append(falhas, format('%s/%s: %s', v_papel, v_fn, left(v_msg, 60))); END IF;
    END LOOP;
  END LOOP;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  SELECT count(*) INTO n FROM public.marketplace_audit_log; IF n <> n_aud THEN falhas := array_append(falhas, 'auditoria ganhou linhas'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_ocorrencias; IF n <> n_oc THEN falhas := array_append(falhas, 'ocorrência gravada'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_destaques; IF n <> n_dest THEN falhas := array_append(falhas, 'destaque gravado'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_config; IF n <> n_cfg THEN falhas := array_append(falhas, 'config gravada'); END IF;
  SELECT status::text INTO v_st FROM public.marketplace_profissionais WHERE id = (s->>'b_prof')::uuid; IF v_st <> 'ativo' THEN falhas := array_append(falhas, 'status de B mudou para ' || v_st); END IF;
  SELECT status INTO v_st FROM public.marketplace_denuncias WHERE id = (s->>'den_y')::uuid; IF v_st <> 'aberta' THEN falhas := array_append(falhas, 'denúncia decidida: ' || v_st); END IF;
  SELECT status INTO v_st FROM public.marketplace_contestacoes WHERE id = (s->>'contest_b')::uuid; IF v_st <> 'aberta' THEN falhas := array_append(falhas, 'contestação decidida: ' || v_st); END IF;
  r.passo_ordem := 4; r.passo_acao := 'Ler as filas de moderação e contestação e o painel de liquidez como usuário de empresa'; r.esperado := 'recusam ou devolvem vazio';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  v := public.marketye_moderacao_fila('pendente'); IF v IS NOT NULL AND v <> '[]'::jsonb THEN falhas := array_append(falhas, 'fila de moderação legível por empresa'); END IF;
  v := public.marketye_contestacoes_fila(); IF v IS NOT NULL AND v <> '[]'::jsonb THEN falhas := array_append(falhas, 'fila de contestações legível por empresa'); END IF;
  v := public.marketye_painel_liquidez(); IF v IS NOT NULL THEN falhas := array_append(falhas, 'painel de liquidez legível por empresa'); END IF;
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  v := public.marketye_moderacao_fila('pendente'); IF v IS NOT NULL AND v <> '[]'::jsonb THEN falhas := array_append(falhas, 'fila de moderação legível por especialista'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'As seis funções administrativas recusam empresa, especialista e visitante com "Acesso negado" e nada é gravado; filas e painel voltam vazios para usuário comum.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-042 — denúncia: remover (takedown) ou manter, com ocorrência e motivo
CREATE OR REPLACE FUNCTION public.qa_caso_mky_042()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v_den uuid; v_den2 uuid; v_st text; v_acao text; n int; v_an_st text; v_an_antes text; v_portal jsonb;
        v_motivo text := 'Anúncio com conduta inadequada confirmada pela moderação';
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  r.passo_ordem := 1; r.passo_acao := 'Empresa X registra denúncia sobre o anúncio publicado de B'; r.esperado := 'denúncia aberta, visível na fila do superadmin';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  PERFORM set_config('app.qa_modo', 'off', true);  -- a trava do cercado lê tenants sob RLS como authenticated (ver MKY-001)
  SET LOCAL ROLE authenticated;
  INSERT INTO public.marketplace_denuncias (tenant_id, profissional_id, denunciante_id, denunciante_nome, tipo, descricao)
  VALUES ((s->>'t1')::uuid, (s->>'b_prof')::uuid, (s->>'x')::uuid, 'QA Empresa 110x', 'conduta_inadequada', 'Denúncia fictícia de teste: o anúncio promete algo que não cumpre.') RETURNING id INTO v_den;
  RESET ROLE;
  PERFORM public.qa_mky_claims((s->>'sa')::uuid);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.marketplace_denuncias WHERE id = v_den AND status = 'aberta';
  RESET ROLE;
  PERFORM set_config('app.qa_modo', 'on', true);
  IF n <> 1 THEN falhas := array_append(falhas, 'denúncia não aparece aberta para o superadmin'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Superadmin decide "procedente" com a ação "remover anúncio"'; r.esperado := 'anúncio removido e fora da busca; ocorrência com reflexo; motivo visível no portal de B';
  PERFORM public.marketye_denuncia_decidir(v_den, 'procedente', v_motivo);
  SELECT count(*) INTO n FROM public.marketplace_ocorrencias WHERE origem_tipo = 'denuncia' AND origem_id = v_den AND profissional_id = (s->>'b_prof')::uuid AND reflexo_visibilidade;
  IF n <> 1 THEN falhas := array_append(falhas, 'ocorrência com reflexo na visibilidade não registrada'); END IF;
  SELECT status INTO v_an_st FROM public.marketplace_servicos WHERE id = (s->>'b_pub')::uuid;
  IF v_an_st <> 'removido' THEN falhas := array_append(falhas, 'anúncio denunciado segue "' || v_an_st || '" depois da decisão procedente (sem takedown)'); END IF;
  SELECT count(*) INTO n FROM public.marketye_buscar_interno(jsonb_build_object('q', 'QA Seguranca B publicado')) x WHERE x->>'servico_id' = s->>'b_pub';
  IF n > 0 THEN falhas := array_append(falhas, 'anúncio denunciado continua na busca'); END IF;
  PERFORM public.qa_mky_claims((s->>'b_uid')::uuid);
  v_portal := public.marketye_meu_portal();
  IF NOT (COALESCE(v_portal->'ocorrencias', '[]'::jsonb) @> jsonb_build_array(jsonb_build_object('descricao', v_motivo))) THEN falhas := array_append(falhas, 'portal de B não mostra o motivo da ocorrência'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  r.passo_ordem := 3; r.passo_acao := 'Outra denúncia sobre B, decidida "improcedente"'; r.esperado := 'anúncio inalterado; denúncia encerrada com motivo; sem ocorrência';
  INSERT INTO public.marketplace_denuncias (tenant_id, profissional_id, denunciante_id, denunciante_nome, tipo, descricao)
  VALUES ((s->>'t1')::uuid, (s->>'b_prof')::uuid, (s->>'x')::uuid, 'QA Empresa 110x', 'outro', 'Segunda denúncia fictícia de teste.') RETURNING id INTO v_den2;
  SELECT status INTO v_an_antes FROM public.marketplace_servicos WHERE id = (s->>'b_pub')::uuid;
  PERFORM public.qa_mky_claims((s->>'sa')::uuid);
  PERFORM public.marketye_denuncia_decidir(v_den2, 'improcedente', 'Sem elementos que confirmem a denúncia');
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  SELECT status, acao_tomada INTO v_st, v_acao FROM public.marketplace_denuncias WHERE id = v_den2;
  IF v_st <> 'improcedente' OR v_acao IS NULL THEN falhas := array_append(falhas, format('segunda denúncia: status %s, motivo %s', v_st, COALESCE(v_acao, 'vazio'))); END IF;
  SELECT count(*) INTO n FROM public.marketplace_ocorrencias WHERE origem_id = v_den2; IF n > 0 THEN falhas := array_append(falhas, 'decisão improcedente gerou ocorrência'); END IF;
  SELECT status INTO v_an_st FROM public.marketplace_servicos WHERE id = (s->>'b_pub')::uuid; IF v_an_st <> v_an_antes THEN falhas := array_append(falhas, 'decisão improcedente mudou o anúncio'); END IF;
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Denúncia entra aberta na fila; "procedente" remove o anúncio, registra ocorrência com reflexo e o motivo aparece no portal; "improcedente" encerra com motivo sem tocar no anúncio.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN RESET ROLE; PERFORM set_config('app.qa_modo', 'on', true); PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-043 — suspender tira da vitrine; reativar devolve; trilha com quem, quando e motivo
CREATE OR REPLACE FUNCTION public.qa_caso_mky_043()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; n int; v_st text; v_portal jsonb; v_an_st text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  SELECT count(*) INTO n FROM public.marketye_buscar_interno(jsonb_build_object('q', 'QA Seguranca B publicado')) x WHERE x->>'servico_id' = s->>'b_pub';
  IF n <> 1 THEN falhas := array_append(falhas, 'controle: B não aparece na busca antes da suspensão'); END IF;
  r.passo_ordem := 1; r.passo_acao := 'Superadmin suspende B com motivo'; r.esperado := 'status suspenso; some da busca; portal mostra a situação e o motivo';
  PERFORM public.qa_mky_claims((s->>'sa')::uuid);
  PERFORM public.marketye_especialista_situacao((s->>'b_prof')::uuid, 'suspenso', 'Documentação em revisão pela moderação (teste)');
  SELECT status::text INTO v_st FROM public.marketplace_profissionais WHERE id = (s->>'b_prof')::uuid; IF v_st <> 'suspenso' THEN falhas := array_append(falhas, 'status após suspender: ' || v_st); END IF;
  SELECT count(*) INTO n FROM public.marketye_buscar_interno(jsonb_build_object('q', 'QA Seguranca B publicado')) x WHERE x->>'servico_id' = s->>'b_pub';
  IF n > 0 THEN falhas := array_append(falhas, 'suspenso continua na busca'); END IF;
  PERFORM public.qa_mky_claims((s->>'b_uid')::uuid);
  v_portal := public.marketye_meu_portal();
  IF v_portal->'perfil'->>'status' <> 'suspenso' OR COALESCE(v_portal->'perfil'->>'moderacao_motivo', '') NOT ILIKE '%Documentação em revisão%' THEN falhas := array_append(falhas, 'portal não mostra suspensão com motivo'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Superadmin reativa B'; r.esperado := 'volta à busca; anúncios continuam publicados';
  PERFORM public.qa_mky_claims((s->>'sa')::uuid);
  PERFORM public.marketye_especialista_situacao((s->>'b_prof')::uuid, 'ativo', 'Documentação conferida (teste)');
  SELECT count(*) INTO n FROM public.marketye_buscar_interno(jsonb_build_object('q', 'QA Seguranca B publicado')) x WHERE x->>'servico_id' = s->>'b_pub';
  IF n <> 1 THEN falhas := array_append(falhas, 'reativado não voltou à busca'); END IF;
  SELECT status INTO v_an_st FROM public.marketplace_servicos WHERE id = (s->>'b_pub')::uuid; IF v_an_st <> 'publicado' THEN falhas := array_append(falhas, 'anúncio mudou para ' || v_an_st); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Consultar marketplace_audit_log'; r.esperado := 'dois eventos com quem, quando e motivo';
  SELECT count(*) INTO n FROM public.marketplace_audit_log WHERE profissional_id = (s->>'b_prof')::uuid AND acao IN ('especialista_suspenso', 'especialista_ativo') AND usuario_id = (s->>'sa')::uuid AND created_at IS NOT NULL AND descricao ILIKE '%(teste)%';
  IF n <> 2 THEN falhas := array_append(falhas, format('auditoria: %s eventos completos de 2', n)); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Suspender tira da busca na hora e o portal mostra a situação com o motivo; reativar devolve com os anúncios intactos; dois eventos auditados com autor, data e motivo.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-045 — relatório de transparência agregado, sem dado pessoal
CREATE OR REPLACE FUNCTION public.qa_caso_mky_045()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v jsonb; v_txt text; k text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  PERFORM public.qa_mky_claims((s->>'sa')::uuid);
  PERFORM public.marketye_denuncia_decidir((s->>'den_y')::uuid, 'procedente', 'Confirmada (teste)');
  PERFORM public.marketye_contestacao_decidir((s->>'contest_b')::uuid, 'indeferida', 'Decisão mantida após análise (teste)');
  r.passo_ordem := 1; r.passo_acao := 'Chamar marketye_transparencia(ano corrente) como superadmin'; r.esperado := 'JSON com as contagens do período';
  v := public.marketye_transparencia(EXTRACT(YEAR FROM now())::int);
  IF v IS NULL THEN falhas := array_append(falhas, 'relatório vazio para o superadmin'); ELSE
    FOREACH k IN ARRAY ARRAY['denuncias_recebidas', 'denuncias_procedentes', 'cadastros_aprovados', 'cadastros_rejeitados', 'anuncios_publicados', 'impulsionamentos', 'contestacoes', 'exclusoes_lgpd'] LOOP
      IF NOT (v ? k) THEN falhas := array_append(falhas, 'falta a contagem ' || k); END IF;
    END LOOP;
    IF COALESCE((v->>'denuncias_recebidas')::int, 0) < 1 OR COALESCE((v->>'denuncias_procedentes')::int, 0) < 1 THEN falhas := array_append(falhas, 'denúncias do período não contadas'); END IF;
    IF COALESCE((v->>'cadastros_aprovados')::int, 0) < 2 THEN falhas := array_append(falhas, 'aprovações do período não contadas'); END IF;
    IF COALESCE((v->>'impulsionamentos')::int, 0) < 1 THEN falhas := array_append(falhas, 'impulsionamentos não contados'); END IF;
    IF COALESCE((v->'contestacoes'->>'indeferidas')::int, 0) < 1 OR NOT (v->'contestacoes' ? 'deferidas') OR NOT (v->'contestacoes' ? 'abertas') THEN falhas := array_append(falhas, 'contestações abertas/deferidas/indeferidas incompletas'); END IF;
  END IF;
  r.passo_ordem := 2; r.passo_acao := 'Inspecionar o JSON'; r.esperado := 'nenhum nome, e-mail, documento ou id de pessoa';
  v_txt := COALESCE(v::text, '');
  IF v_txt LIKE '%@%' THEN falhas := array_append(falhas, 'contém e-mail'); END IF;
  IF v_txt ILIKE '%QA Especialista%' OR v_txt ILIKE '%QA Empresa%' THEN falhas := array_append(falhas, 'contém nome'); END IF;
  IF v_txt LIKE '%90000003271%' OR v_txt LIKE '%90000003352%' THEN falhas := array_append(falhas, 'contém documento'); END IF;
  FOREACH k IN ARRAY ARRAY['a_prof', 'b_prof', 'x', 'y', 'a_uid', 'b_uid'] LOOP
    IF v_txt LIKE '%' || (s->>k) || '%' THEN falhas := array_append(falhas, 'contém id de pessoa (' || k || ')'); END IF;
  END LOOP;
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  IF public.marketye_transparencia(NULL) IS NOT NULL THEN falhas := array_append(falhas, 'usuário de empresa lê o relatório'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Relatório com denúncias (recebidas/procedentes), cadastros, anúncios, impulsionamentos, contestações e exclusões LGPD, só números: sem nome, e-mail, documento ou id; usuário comum não lê.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-046 — nada automático remove ou suspende: só função de superadmin e a guarda
CREATE OR REPLACE FUNCTION public.qa_caso_mky_046()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v_jobs text; v_trg text; v_fns text; v_st text; n int; n_oc int; v_texto text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  r.passo_ordem := 1; r.passo_acao := 'Listar jobs, gatilhos e funções que mudam status de anúncio ou especialista'; r.esperado := 'só funções que exigem superadmin (ou o próprio dono) e a guarda; nenhum job automático';
  BEGIN
    SELECT string_agg(j.jobname || ' (' || trim(j.command) || ')', '; ') INTO v_jobs
    FROM cron.job j WHERE EXISTS (
      SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND j.command ILIKE '%' || p.proname || '(%'
        AND (p.prosrc ILIKE '%marketplace_profissionais%' OR p.prosrc ILIKE '%marketplace_servicos%') AND p.prosrc ~* 'status\s*=');
  EXCEPTION WHEN undefined_table THEN v_jobs := NULL; END;
  IF v_jobs IS NOT NULL THEN falhas := array_append(falhas, 'job automático altera status sem decisão humana: ' || v_jobs); END IF;
  SELECT string_agg(c.relname || '.' || t.tgname || ' (' || p.proname || ')', '; ') INTO v_trg
  FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_proc p ON p.oid = t.tgfoid
  WHERE NOT t.tgisinternal AND c.relnamespace = 'public'::regnamespace AND c.relname IN ('marketplace_servicos', 'marketplace_profissionais')
    AND p.proname NOT IN ('marketye_guarda_profissional', 'marketye_guarda_anuncio', 'marketye_trilha_autonomia_perfil', 'marketye_trilha_autonomia_anuncio', 'qa_bloqueia_fora_do_cercado', 'update_updated_at_column')
    AND p.prosrc ~* 'NEW\.status\s*:?=\s*''(bloqueado|suspenso|removido|pausado)''';
  IF v_trg IS NOT NULL THEN falhas := array_append(falhas, 'gatilho muda status sozinho: ' || v_trg); END IF;
  SELECT string_agg(p.proname, ', ') INTO v_fns
  FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.prokind = 'f' AND p.prorettype <> 'trigger'::regtype
    AND p.prosrc ~* 'UPDATE\s+public\.marketplace_(profissionais|servicos)\s+SET[\s\S]*status\s*=\s*''?(bloqueado|suspenso|removido)'
    AND p.prosrc NOT ILIKE '%is_superadmin(%' AND p.prosrc NOT ILIKE '%marketye_meu_id()%' AND p.proname NOT LIKE 'qa_%';
  IF v_fns IS NOT NULL THEN falhas := array_append(falhas, 'função sem exigir superadmin nem o próprio dono põe bloqueado/suspenso/removido: ' || v_fns); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Simular a sinalização da IA: anúncio publicado passa a ter contato disfarçado no texto'; r.esperado := 'anúncio permanece publicado até decisão humana; nenhuma ocorrência automática';
  s := public.qa_mky_cenario_seguranca();
  v_texto := 'Serviço fictício de teste do MarketYE. Chama no zap 46 9 9999 0000 para orçamento rápido.';
  IF NOT public.marketye_texto_tem_contato(v_texto) THEN falhas := array_append(falhas, 'controle: o texto de teste não dispara a sinalização de contato'); END IF;
  SELECT count(*) INTO n_oc FROM public.marketplace_ocorrencias WHERE profissional_id = (s->>'b_prof')::uuid;
  PERFORM public.qa_mky_claims((s->>'b_uid')::uuid);
  PERFORM public.marketye_anuncio_salvar(jsonb_build_object('id', s->>'b_pub', 'nome', 'QA Seguranca B publicado', 'descricao', v_texto, 'modalidade', 'online', 'tipo_preco', 'sob_orcamento'));
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  SELECT status INTO v_st FROM public.marketplace_servicos WHERE id = (s->>'b_pub')::uuid;
  IF v_st <> 'publicado' THEN falhas := array_append(falhas, 'anúncio mudou sozinho para ' || v_st); END IF;
  SELECT count(*) INTO n FROM public.marketplace_ocorrencias WHERE profissional_id = (s->>'b_prof')::uuid; IF n <> n_oc THEN falhas := array_append(falhas, 'ocorrência criada sem decisão humana'); END IF;
  SELECT status::text INTO v_st FROM public.marketplace_profissionais WHERE id = (s->>'b_prof')::uuid; IF v_st <> 'ativo' THEN falhas := array_append(falhas, 'especialista mudou sozinho para ' || v_st); END IF;
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Nenhum job, gatilho ou função fora do superadmin muda status; texto sinalizado não derruba o anúncio nem gera ocorrência sem decisão humana.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ===== Família C — anúncio, preço, promoção, cupom, destaque, autonomia, mídia (MKY-051..058) =====
-- MKY-051 — texto com telefone, e-mail ou link não publica
CREATE OR REPLACE FUNCTION public.qa_caso_mky_051()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v_cat uuid; v_an uuid; v_st text; v_msg text; v_base jsonb; v_txt text;
        v_esp text := 'Remova telefones, e-mails ou links do texto — o contato acontece pelo MarketYE.';
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  SELECT id INTO v_cat FROM public.marketplace_categorias WHERE slug = 'seguranca-trabalho';
  PERFORM public.qa_mky_claims((s->>'b_uid')::uuid);
  v_base := jsonb_build_object('nome', 'QA Contato 051', 'categoria_id', v_cat, 'modalidade', 'online', 'tipo_preco', 'sob_orcamento');
  r.passo_ordem := 1; r.passo_acao := 'Salvar anúncio com telefone na descrição'; r.esperado := 'salvo como rascunho';
  v_an := (public.marketye_anuncio_salvar(v_base || jsonb_build_object('descricao', 'Ligue agora (46) 99999-0000 e agende sua visita técnica de teste.'))->>'id')::uuid;
  SELECT status INTO v_st FROM public.marketplace_servicos WHERE id = v_an; IF v_st <> 'rascunho' THEN falhas := array_append(falhas, 'nasceu ' || v_st); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Publicar'; r.esperado := 'recusado: ' || v_esp;
  BEGIN PERFORM public.marketye_anuncio_publicar(v_an); v_msg := 'publicou'; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_msg <> v_esp THEN falhas := array_append(falhas, 'telefone: ' || left(v_msg, 80)); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Repetir com link, com e-mail e com telefone no título'; r.esperado := 'recusado nos três';
  FOREACH v_txt IN ARRAY ARRAY['Veja meu portfólio completo em www.meusite.com.br antes de contratar o serviço.', 'Mande um e-mail para eu@x.com com a descrição do serviço de teste que precisa.'] LOOP
    PERFORM public.marketye_anuncio_salvar(v_base || jsonb_build_object('id', v_an, 'descricao', v_txt));
    BEGIN PERFORM public.marketye_anuncio_publicar(v_an); v_msg := 'publicou'; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    IF v_msg <> v_esp THEN falhas := array_append(falhas, left(v_txt, 25) || ': ' || left(v_msg, 60)); END IF;
  END LOOP;
  PERFORM public.marketye_anuncio_salvar(v_base || jsonb_build_object('id', v_an, 'nome', 'Consultoria 46999990000', 'descricao', 'Serviço fictício de teste do MarketYE, sem nenhum canal de contato na descrição.'));
  BEGIN PERFORM public.marketye_anuncio_publicar(v_an); v_msg := 'publicou'; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_msg <> v_esp THEN falhas := array_append(falhas, 'telefone no título: ' || left(v_msg, 60)); END IF;
  r.passo_ordem := 4; r.passo_acao := 'Remover os contatos e publicar'; r.esperado := 'publicado';
  PERFORM public.marketye_anuncio_salvar(v_base || jsonb_build_object('id', v_an, 'descricao', 'Serviço fictício de teste do MarketYE, sem nenhum canal de contato no texto.'));
  BEGIN PERFORM public.marketye_anuncio_publicar(v_an); EXCEPTION WHEN OTHERS THEN falhas := array_append(falhas, 'texto limpo recusado: ' || SQLERRM); END;
  SELECT status INTO v_st FROM public.marketplace_servicos WHERE id = v_an; IF v_st <> 'publicado' THEN falhas := array_append(falhas, 'texto limpo ficou ' || v_st); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Telefone, link e e-mail na descrição e telefone no título salvam como rascunho mas não publicam (mensagem pede para remover); sem contato, publica.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-052 — preço: zero recusado; sob orçamento dispensa; faixa invertida nunca gravada
CREATE OR REPLACE FUNCTION public.qa_caso_mky_052()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v_cat uuid; v_an uuid; v_msg text; v_base jsonb; v_min numeric; v_max numeric;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  SELECT id INTO v_cat FROM public.marketplace_categorias WHERE slug = 'seguranca-trabalho';
  PERFORM public.qa_mky_claims((s->>'b_uid')::uuid);
  v_base := jsonb_build_object('nome', 'QA Preco 052', 'descricao', 'Serviço fictício de teste do MarketYE para a regra de preço.', 'categoria_id', v_cat, 'modalidade', 'online');
  r.passo_ordem := 1; r.passo_acao := 'Salvar com tipo_preco = hora e preco_referencia = 0'; r.esperado := 'recusado: Informe um preço-base ou marque sob orçamento';
  BEGIN PERFORM public.marketye_anuncio_salvar(v_base || jsonb_build_object('tipo_preco', 'hora', 'preco_referencia', 0)); v_msg := 'aceitou'; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_msg NOT ILIKE '%preço-base%' THEN falhas := array_append(falhas, 'preço zero: ' || left(v_msg, 60)); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Salvar com sob_orcamento sem preço'; r.esperado := 'aceito';
  BEGIN v_an := (public.marketye_anuncio_salvar(v_base || jsonb_build_object('tipo_preco', 'sob_orcamento'))->>'id')::uuid; EXCEPTION WHEN OTHERS THEN falhas := array_append(falhas, 'sob orçamento recusado: ' || SQLERRM); END;
  r.passo_ordem := 3; r.passo_acao := 'Salvar faixa com mínimo 500 e máximo 100'; r.esperado := 'recusado ou normalizado; nunca gravado invertido';
  BEGIN
    v_an := (public.marketye_anuncio_salvar(v_base || jsonb_build_object('tipo_preco', 'pacote', 'preco_referencia', 300, 'preco_minimo', 500, 'preco_maximo', 100))->>'id')::uuid;
    SELECT preco_minimo, preco_maximo INTO v_min, v_max FROM public.marketplace_servicos WHERE id = v_an;
    IF v_min > v_max THEN falhas := array_append(falhas, format('faixa gravada invertida (mínimo %s > máximo %s)', v_min, v_max)); END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Preço zero recusado com a mensagem certa; sob orçamento dispensa preço; faixa invertida não chega ao banco.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-053 — pausar/retomar reversíveis; remover é definitivo
CREATE OR REPLACE FUNCTION public.qa_caso_mky_053()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; n int; v_st text; v_pub_em timestamptz; v_pub_em2 timestamptz; v_portal jsonb; v_msg text; v_an uuid;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca(); v_an := (s->>'b_pub')::uuid;
  SELECT publicado_em INTO v_pub_em FROM public.marketplace_servicos WHERE id = v_an;
  PERFORM public.qa_mky_claims((s->>'b_uid')::uuid);
  r.passo_ordem := 1; r.passo_acao := 'marketye_anuncio_status(id, pausado)'; r.esperado := 'some da busca; portal mostra pausado';
  PERFORM public.marketye_anuncio_status(v_an, 'pausado');
  SELECT count(*) INTO n FROM public.marketye_buscar_interno(jsonb_build_object('q', 'QA Seguranca B publicado')) x WHERE x->>'servico_id' = v_an::text; IF n > 0 THEN falhas := array_append(falhas, 'pausado continua na busca'); END IF;
  v_portal := public.marketye_meu_portal();
  IF NOT (v_portal->'anuncios' @> jsonb_build_array(jsonb_build_object('id', v_an, 'status', 'pausado'))) THEN falhas := array_append(falhas, 'portal não mostra pausado'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Publicar de novo'; r.esperado := 'volta à busca sem nova moderação';
  PERFORM public.marketye_anuncio_publicar(v_an);
  SELECT count(*) INTO n FROM public.marketye_buscar_interno(jsonb_build_object('q', 'QA Seguranca B publicado')) x WHERE x->>'servico_id' = v_an::text; IF n <> 1 THEN falhas := array_append(falhas, 'retomado não voltou à busca'); END IF;
  SELECT status, publicado_em INTO v_st, v_pub_em2 FROM public.marketplace_servicos WHERE id = v_an;
  IF v_st <> 'publicado' OR v_pub_em2 IS DISTINCT FROM v_pub_em THEN falhas := array_append(falhas, 'retomar exigiu nova publicação/moderação'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'marketye_anuncio_status(id, removido) e tentar publicar de novo'; r.esperado := 'não volta; precisa de anúncio novo';
  PERFORM public.marketye_anuncio_status(v_an, 'removido');
  BEGIN PERFORM public.marketye_anuncio_publicar(v_an); v_msg := 'publicou'; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  SELECT status INTO v_st FROM public.marketplace_servicos WHERE id = v_an;
  IF v_msg = 'publicou' OR v_st = 'publicado' THEN falhas := array_append(falhas, 'anúncio removido voltou a publicado pela função de publicar'); END IF;
  PERFORM public.marketye_anuncio_status(v_an, 'removido');
  BEGIN
    PERFORM public.marketye_anuncio_salvar(jsonb_build_object('id', v_an, 'nome', 'QA Seguranca B publicado', 'descricao', 'Serviço fictício de teste do MarketYE, apenas para a rotina automatizada de segurança.', 'modalidade', 'online', 'tipo_preco', 'sob_orcamento'));
    SELECT status INTO v_st FROM public.marketplace_servicos WHERE id = v_an;
    IF v_st <> 'removido' THEN falhas := array_append(falhas, 'salvar ressuscita anúncio removido (virou ' || v_st || ')'); END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Pausar tira da busca e o portal mostra; retomar devolve sem nova moderação; removido não volta por publicar nem por salvar.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-054 — promoção só dentro do período; percentual fora da faixa recusado
CREATE OR REPLACE FUNCTION public.qa_caso_mky_054()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v_an uuid; v_base jsonb; x jsonb; v_msg text; v_pct numeric;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca(); v_an := (s->>'b_pub')::uuid;
  PERFORM public.qa_mky_claims((s->>'b_uid')::uuid);
  v_base := jsonb_build_object('id', v_an, 'nome', 'QA Seguranca B publicado', 'descricao', 'Serviço fictício de teste do MarketYE, apenas para a rotina automatizada de segurança.', 'modalidade', 'online', 'tipo_preco', 'sob_orcamento');
  r.passo_ordem := 1; r.passo_acao := 'Promoção de 10% de hoje até +30 dias'; r.esperado := 'busca devolve promocao_ativa = true';
  PERFORM public.marketye_anuncio_salvar(v_base || jsonb_build_object('promocao_percentual', 10, 'promocao_inicio', CURRENT_DATE, 'promocao_fim', CURRENT_DATE + 30));
  SELECT y INTO x FROM public.marketye_buscar_interno(jsonb_build_object('q', 'QA Seguranca B publicado')) y WHERE y->>'servico_id' = v_an::text;
  IF x IS NULL OR (x->>'promocao_ativa')::boolean IS DISTINCT FROM true OR (x->>'promocao_percentual')::numeric <> 10 THEN falhas := array_append(falhas, 'promoção vigente não sinalizada'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Promoção com fim ontem'; r.esperado := 'promocao_ativa = false';
  PERFORM public.marketye_anuncio_salvar(v_base || jsonb_build_object('promocao_percentual', 10, 'promocao_inicio', CURRENT_DATE - 10, 'promocao_fim', CURRENT_DATE - 1));
  SELECT y INTO x FROM public.marketye_buscar_interno(jsonb_build_object('q', 'QA Seguranca B publicado')) y WHERE y->>'servico_id' = v_an::text;
  IF x IS NULL OR (x->>'promocao_ativa')::boolean IS DISTINCT FROM false THEN falhas := array_append(falhas, 'promoção vencida segue ativa'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Percentual 0 e percentual 95'; r.esperado := 'recusado';
  FOREACH v_pct IN ARRAY ARRAY[0, 95] LOOP
    BEGIN
      PERFORM public.marketye_anuncio_salvar(v_base || jsonb_build_object('promocao_percentual', v_pct, 'promocao_inicio', CURRENT_DATE, 'promocao_fim', CURRENT_DATE + 5));
      falhas := array_append(falhas, format('percentual %s aceito', v_pct));
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END LOOP;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Promoção aparece só dentro do período; percentual 0 e acima de 90 recusados.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-055 — cupom: código único, validade e limite aplicados na busca e na conversa
CREATE OR REPLACE FUNCTION public.qa_caso_mky_055()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; n int; v_desc numeric; v_usos int; x jsonb; l1 uuid; l2 uuid; l3 uuid; l4 uuid; v_cod text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  PERFORM public.qa_mky_claims((s->>'b_uid')::uuid);
  UPDATE public.marketplace_cupons SET ativo = false WHERE profissional_id = (s->>'b_prof')::uuid;  -- só o cupom deste caso conta
  r.passo_ordem := 1; r.passo_acao := 'Criar cupom BEMVINDO 15% válido até +10 dias, limite 2'; r.esperado := 'criado; busca devolve tem_cupom = true';
  PERFORM public.marketye_cupom_salvar(jsonb_build_object('codigo', 'BEMVINDO', 'desconto_percentual', 15, 'validade', CURRENT_DATE + 10, 'limite_uso', 2));
  SELECT y INTO x FROM public.marketye_buscar_interno(jsonb_build_object('q', 'QA Seguranca B publicado')) y WHERE y->>'servico_id' = s->>'b_pub';
  IF (x->>'tem_cupom')::boolean IS DISTINCT FROM true THEN falhas := array_append(falhas, 'busca não sinaliza cupom válido'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Criar outro cupom com o mesmo código'; r.esperado := 'atualiza o existente, não duplica';
  PERFORM public.marketye_cupom_salvar(jsonb_build_object('codigo', 'bemvindo', 'desconto_percentual', 20, 'validade', CURRENT_DATE + 10, 'limite_uso', 2));
  SELECT count(*), max(desconto_percentual) INTO n, v_desc FROM public.marketplace_cupons WHERE profissional_id = (s->>'b_prof')::uuid AND codigo = 'BEMVINDO';
  IF n <> 1 OR v_desc <> 20 THEN falhas := array_append(falhas, format('mesmo código: %s linhas, desconto %s', n, v_desc)); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Duas empresas abrem conversa (cupom aplicado sozinho); a terceira conversa nova já não recebe'; r.esperado := 'duas com cupom_codigo e usos = 2; a terceira sem cupom';
  PERFORM public.qa_mky_claims((s->>'y')::uuid);
  l1 := (public.marketye_abrir_lead((s->>'b_prof')::uuid, (s->>'b_pub')::uuid, 'Quero orçamento fictício de teste com cupom.')->>'id')::uuid;
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  PERFORM public.marketye_lead_status((s->>'lead_xb')::uuid, 'perdido', NULL);
  l2 := (public.marketye_abrir_lead((s->>'b_prof')::uuid, (s->>'b_pub')::uuid, 'Quero orçamento fictício de teste com cupom.')->>'id')::uuid;
  SELECT count(*) INTO n FROM public.marketplace_leads WHERE id IN (l1, l2) AND cupom_codigo = 'BEMVINDO';
  SELECT usos INTO v_usos FROM public.marketplace_cupons WHERE profissional_id = (s->>'b_prof')::uuid AND codigo = 'BEMVINDO';
  IF n <> 2 OR v_usos <> 2 THEN falhas := array_append(falhas, format('duas conversas: %s com cupom, usos %s', n, v_usos)); END IF;
  PERFORM public.marketye_lead_status(l2, 'perdido', NULL);
  l3 := (public.marketye_abrir_lead((s->>'b_prof')::uuid, (s->>'b_pub')::uuid, 'Terceira conversa fictícia de teste.')->>'id')::uuid;
  SELECT cupom_codigo INTO v_cod FROM public.marketplace_leads WHERE id = l3;
  SELECT usos INTO v_usos FROM public.marketplace_cupons WHERE profissional_id = (s->>'b_prof')::uuid AND codigo = 'BEMVINDO';
  IF v_cod IS NOT NULL OR v_usos <> 2 THEN falhas := array_append(falhas, format('terceira conversa recebeu cupom %s (usos %s)', v_cod, v_usos)); END IF;
  SELECT y INTO x FROM public.marketye_buscar_interno(jsonb_build_object('q', 'QA Seguranca B publicado')) y WHERE y->>'servico_id' = s->>'b_pub';
  IF (x->>'tem_cupom')::boolean IS DISTINCT FROM false THEN falhas := array_append(falhas, 'busca sinaliza cupom esgotado'); END IF;
  r.passo_ordem := 4; r.passo_acao := 'Cupom com validade ontem'; r.esperado := 'tem_cupom = false; conversa nova sem cupom';
  PERFORM public.qa_mky_claims((s->>'b_uid')::uuid);
  PERFORM public.marketye_cupom_salvar(jsonb_build_object('codigo', 'BEMVINDO', 'desconto_percentual', 20, 'validade', CURRENT_DATE - 1, 'limite_uso', 10));
  SELECT y INTO x FROM public.marketye_buscar_interno(jsonb_build_object('q', 'QA Seguranca B publicado')) y WHERE y->>'servico_id' = s->>'b_pub';
  IF (x->>'tem_cupom')::boolean IS DISTINCT FROM false THEN falhas := array_append(falhas, 'busca sinaliza cupom vencido'); END IF;
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  PERFORM public.marketye_lead_status(l3, 'perdido', NULL);
  l4 := (public.marketye_abrir_lead((s->>'b_prof')::uuid, (s->>'b_pub')::uuid, 'Quarta conversa fictícia de teste.')->>'id')::uuid;
  SELECT cupom_codigo INTO v_cod FROM public.marketplace_leads WHERE id = l4; IF v_cod IS NOT NULL THEN falhas := array_append(falhas, 'cupom vencido aplicado'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Código único por especialista (maiúsculas, atualiza em vez de duplicar); a busca só sinaliza cupom válido; as duas primeiras conversas recebem o cupom e consomem os usos; a terceira e a com cupom vencido ficam sem.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-056 — destaque: recusado abaixo do piso; teto de 2 por categoria; rótulo e ordem
CREATE OR REPLACE FUNCTION public.qa_caso_mky_056()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v_cat uuid; c record; d record; v_msg text; an_c uuid; an_d uuid; v_res jsonb; v_pos_a int; v_pos_b int; v_pos_c int; v_pos_d int; v_pat_b boolean; v_pat_c boolean; v_pat_d boolean;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  SELECT id INTO v_cat FROM public.marketplace_categorias WHERE slug = 'seguranca-trabalho';
  SELECT * INTO c FROM public.qa_mky_especialista('056c', '900.000.030-00');
  SELECT * INTO d FROM public.qa_mky_especialista('056d', '900.000.031-90');
  PERFORM public.qa_mky_claims((s->>'sa')::uuid);
  PERFORM public.marketye_moderar_especialista(c.prof_id, 'aprovado', NULL, true); PERFORM public.marketye_moderar_especialista(d.prof_id, 'aprovado', NULL, true);
  UPDATE public.marketplace_destaques SET ativo = false WHERE profissional_id = (s->>'b_prof')::uuid;  -- o destaque "topo" do cenário não entra neste caso
  PERFORM public.qa_mky_claims(c.uid);
  an_c := (public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Destaque 056 C', 'descricao', 'Serviço fictício de teste do MarketYE para destaques.', 'categoria_id', v_cat, 'modalidade', 'online', 'tipo_preco', 'sob_orcamento'))->>'id')::uuid; PERFORM public.marketye_anuncio_publicar(an_c);
  PERFORM public.qa_mky_claims(d.uid);
  an_d := (public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Destaque 056 D', 'descricao', 'Serviço fictício de teste do MarketYE para destaques.', 'categoria_id', v_cat, 'modalidade', 'online', 'tipo_preco', 'sob_orcamento'))->>'id')::uuid; PERFORM public.marketye_anuncio_publicar(an_d);
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  INSERT INTO public.marketplace_avaliacoes (profissional_id, avaliador_id, tenant_id, direcao, criterios, nota_geral, comentario)
  SELECT (s->>'a_prof')::uuid, (s->>'x')::uuid, (s->>'t1')::uuid, 'cliente_para_especialista', '{"pontualidade":2}'::jsonb, 2, 'Avaliação fictícia de teste ' || g FROM generate_series(1, 3) g;
  PERFORM public.marketye_recalcular_reputacao((s->>'a_prof')::uuid);
  PERFORM public.qa_mky_claims((s->>'sa')::uuid);
  r.passo_ordem := 1; r.passo_acao := 'Criar destaque de categoria para A (abaixo do piso)'; r.esperado := 'recusado: Melhore sua nota para ativar destaques';
  BEGIN PERFORM public.marketye_destaque_criar((s->>'a_prof')::uuid, NULL, 'categoria', v_cat, NULL, CURRENT_DATE, CURRENT_DATE + 7, 100); v_msg := 'aceitou'; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_msg NOT ILIKE '%Melhore sua nota%' THEN falhas := array_append(falhas, 'abaixo do piso: ' || left(v_msg, 60)); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Criar destaque de categoria para B e C'; r.esperado := 'criados';
  BEGIN PERFORM public.marketye_destaque_criar((s->>'b_prof')::uuid, NULL, 'categoria', v_cat, NULL, CURRENT_DATE, CURRENT_DATE + 7, 100); EXCEPTION WHEN OTHERS THEN falhas := array_append(falhas, 'B recusado: ' || SQLERRM); END;
  BEGIN PERFORM public.marketye_destaque_criar(c.prof_id, NULL, 'categoria', v_cat, NULL, CURRENT_DATE, CURRENT_DATE + 7, 100); EXCEPTION WHEN OTHERS THEN falhas := array_append(falhas, 'C recusado: ' || SQLERRM); END;
  r.passo_ordem := 3; r.passo_acao := 'Criar para D na mesma categoria e período'; r.esperado := 'recusado: teto de 2 slots';
  BEGIN PERFORM public.marketye_destaque_criar(d.prof_id, NULL, 'categoria', v_cat, NULL, CURRENT_DATE, CURRENT_DATE + 7, 100); v_msg := 'aceitou'; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_msg NOT ILIKE '%Teto de destaques%' THEN falhas := array_append(falhas, 'teto: ' || left(v_msg, 60)); END IF;
  r.passo_ordem := 4; r.passo_acao := 'Buscar na categoria'; r.esperado := 'B e C patrocinados; D não; A (abaixo do piso) por último';
  SELECT jsonb_agg(y ORDER BY (y->>'score')::numeric DESC) INTO v_res FROM public.marketye_buscar_interno(jsonb_build_object('categoria_slug', 'seguranca-trabalho', 'limite', 100)) y WHERE y->'profissional'->>'id' IN (s->>'a_prof', s->>'b_prof', c.prof_id::text, d.prof_id::text);
  SELECT min(i), bool_or((e->>'patrocinado')::boolean) INTO v_pos_b, v_pat_b FROM jsonb_array_elements(v_res) WITH ORDINALITY t(e, i) WHERE e->'profissional'->>'id' = s->>'b_prof';
  SELECT min(i), bool_or((e->>'patrocinado')::boolean) INTO v_pos_c, v_pat_c FROM jsonb_array_elements(v_res) WITH ORDINALITY t(e, i) WHERE e->'profissional'->>'id' = c.prof_id::text;
  SELECT min(i), bool_or((e->>'patrocinado')::boolean) INTO v_pos_d, v_pat_d FROM jsonb_array_elements(v_res) WITH ORDINALITY t(e, i) WHERE e->'profissional'->>'id' = d.prof_id::text;
  SELECT max(i) INTO v_pos_a FROM jsonb_array_elements(v_res) WITH ORDINALITY t(e, i) WHERE e->'profissional'->>'id' = s->>'a_prof';
  IF v_pat_b IS DISTINCT FROM true OR v_pat_c IS DISTINCT FROM true THEN falhas := array_append(falhas, 'B/C sem rótulo patrocinado'); END IF;
  IF v_pat_d IS DISTINCT FROM false THEN falhas := array_append(falhas, 'D aparece patrocinado'); END IF;
  IF v_pos_a IS NULL OR v_pos_a < GREATEST(v_pos_b, v_pos_c, v_pos_d) THEN falhas := array_append(falhas, format('A abaixo do piso não ficou por último (posições A %s, B %s, C %s, D %s)', v_pos_a, v_pos_b, v_pos_c, v_pos_d)); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Abaixo do piso não compra destaque; B e C entram; D bate no teto de 2 por categoria; a busca rotula B e C como patrocinados e mantém A por último.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-057 — trilha de autonomia: anterior/novo, legível só pelo dono
CREATE OR REPLACE FUNCTION public.qa_caso_mky_057()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; n int; e record;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  DELETE FROM public.marketplace_autonomia_eventos WHERE profissional_id = (s->>'a_prof')::uuid;
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  r.passo_ordem := 1; r.passo_acao := 'Salvar perfil com disponibilidade e políticas'; r.esperado := 'evento com anterior (nulo) e novo';
  PERFORM public.marketye_meu_perfil_salvar(jsonb_build_object('disponibilidade', '{"seg": ["08:00-12:00"]}'::jsonb, 'politicas', 'Cancelamento sem custo até 24h antes (teste).'));
  SELECT * INTO e FROM public.marketplace_autonomia_eventos WHERE profissional_id = (s->>'a_prof')::uuid AND tipo = 'perfil_horario_politica' ORDER BY created_at DESC LIMIT 1;
  IF e.id IS NULL OR e.anterior->>'politicas' IS NOT NULL OR e.novo->>'politicas' NOT ILIKE '%24h%' OR e.novo->'disponibilidade' IS NULL THEN falhas := array_append(falhas, 'primeiro evento incompleto'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Alterar as políticas'; r.esperado := 'novo evento com anterior = valor antigo';
  PERFORM public.marketye_meu_perfil_salvar(jsonb_build_object('politicas', 'Cancelamento sem custo até 48h antes (teste).'));
  SELECT * INTO e FROM public.marketplace_autonomia_eventos WHERE profissional_id = (s->>'a_prof')::uuid AND tipo = 'perfil_horario_politica' AND novo->>'politicas' ILIKE '%48h%' LIMIT 1;
  IF e.id IS NULL OR e.anterior->>'politicas' NOT ILIKE '%24h%' THEN falhas := array_append(falhas, 'segundo evento não guarda o valor anterior'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_autonomia_eventos WHERE profissional_id = (s->>'a_prof')::uuid AND tipo = 'perfil_horario_politica'; IF n <> 2 THEN falhas := array_append(falhas, format('%s eventos (esperado 2)', n)); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Outro especialista tenta ler os eventos'; r.esperado := 'zero linhas (RLS); o dono lê os seus';
  PERFORM public.qa_mky_claims((s->>'b_uid')::uuid);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.marketplace_autonomia_eventos WHERE profissional_id = (s->>'a_prof')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'B lê a trilha de A'); END IF;
  RESET ROLE;
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.marketplace_autonomia_eventos WHERE profissional_id = (s->>'a_prof')::uuid; IF n < 2 THEN falhas := array_append(falhas, 'controle: o dono não lê a própria trilha'); END IF;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Cada mudança de disponibilidade/política gera evento com valor anterior e novo; só o dono lê a própria trilha.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN RESET ROLE; PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-058 — foto pública; documento de verificação só dono e superadmin
CREATE OR REPLACE FUNCTION public.qa_caso_mky_058()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; n int; v_foto text; v_doc text; v_pub boolean;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  v_foto := (s->>'a_prof') || '/foto.jpg'; v_doc := (s->>'a_prof') || '/identidade.pdf';
  INSERT INTO storage.objects (bucket_id, name, owner, path_tokens) VALUES ('marketplace-fotos', v_foto, (s->>'a_uid')::uuid, ARRAY[s->>'a_prof', 'foto.jpg']), ('marketplace-docs', v_doc, (s->>'a_uid')::uuid, ARRAY[s->>'a_prof', 'identidade.pdf']);
  INSERT INTO public.marketplace_profissional_documentos (profissional_id, categoria, nome_arquivo, arquivo_url, tamanho_bytes, mime_type) VALUES ((s->>'a_prof')::uuid, 'identidade', 'identidade.pdf', 'marketplace-docs/' || v_doc, 1234, 'application/pdf');
  SELECT public INTO v_pub FROM storage.buckets WHERE id = 'marketplace-fotos'; IF v_pub IS DISTINCT FROM true THEN falhas := array_append(falhas, 'bucket de fotos não é público'); END IF;
  SELECT public INTO v_pub FROM storage.buckets WHERE id = 'marketplace-docs'; IF v_pub IS DISTINCT FROM false THEN falhas := array_append(falhas, 'bucket de documentos é público'); END IF;
  r.passo_ordem := 1; r.passo_acao := 'Ler a foto sem login'; r.esperado := 'acessível';
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  SET LOCAL ROLE anon;
  SELECT count(*) INTO n FROM storage.objects WHERE bucket_id = 'marketplace-fotos' AND name = v_foto; IF n <> 1 THEN falhas := array_append(falhas, 'foto não acessível sem login'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Ler o documento sem login e como outro especialista'; r.esperado := 'negado';
  SELECT count(*) INTO n FROM storage.objects WHERE bucket_id = 'marketplace-docs' AND name = v_doc; IF n > 0 THEN falhas := array_append(falhas, 'documento legível sem login'); END IF;
  RESET ROLE;
  PERFORM public.qa_mky_claims((s->>'b_uid')::uuid);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM storage.objects WHERE bucket_id = 'marketplace-docs' AND name = v_doc; IF n > 0 THEN falhas := array_append(falhas, 'outro especialista lê o documento'); END IF;
  RESET ROLE;
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM storage.objects WHERE bucket_id = 'marketplace-docs' AND name = v_doc; IF n <> 1 THEN falhas := array_append(falhas, 'controle: o dono não lê o próprio documento'); END IF;
  RESET ROLE;
  r.passo_ordem := 3; r.passo_acao := 'Ler como superadmin'; r.esperado := 'acessível';
  PERFORM public.qa_mky_claims((s->>'sa')::uuid);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM storage.objects WHERE bucket_id = 'marketplace-docs' AND name = v_doc; IF n <> 1 THEN falhas := array_append(falhas, 'superadmin não lê o documento'); END IF;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Foto no bucket público legível sem login; documento de verificação invisível para visitante e para outro especialista; dono e superadmin leem.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN RESET ROLE; PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ===== Família D — busca (MKY-060..068) =====
-- Ajudante: salva e publica um anúncio como o especialista informado (devolve o id), preservando as claims de quem chamou.
CREATE OR REPLACE FUNCTION public.qa_mky_anuncio_publicado(p_uid uuid, p_nome text, p_slug text, p_modalidade text, p_tipo_preco text, p_preco numeric, p_extra jsonb DEFAULT '{}'::jsonb)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_claims text := current_setting('request.jwt.claims', true); v_cat uuid; v_id uuid;
BEGIN
  SELECT id INTO v_cat FROM public.marketplace_categorias WHERE slug = p_slug;
  IF v_cat IS NULL THEN RAISE EXCEPTION 'Categoria % não existe na taxonomia', p_slug; END IF;
  PERFORM public.qa_mky_claims(p_uid);
  v_id := (public.marketye_anuncio_salvar(jsonb_build_object('nome', p_nome, 'descricao', 'Serviço fictício de teste do MarketYE para a rotina automatizada de busca.', 'categoria_id', v_cat,
            'modalidade', p_modalidade, 'tipo_preco', p_tipo_preco, 'preco_referencia', p_preco) || COALESCE(p_extra, '{}'::jsonb))->>'id')::uuid;
  PERFORM public.marketye_anuncio_publicar(v_id);
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  RETURN v_id;
END $$;

-- MKY-060 — cada filtro devolve só quem satisfaz
CREATE OR REPLACE FUNCTION public.qa_caso_mky_060()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_claims text; falhas text[] := '{}'; sa uuid; e1 record; e2 record; e3 record; e4 record; e5 record; e6 record; ids uuid[]; nomes text[]; v_got text[]; v_exp text[]; f jsonb; k int;
  filtros jsonb[]; esperados text[][]; rotulos text[];
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  sa := public.qa_mky_superadmin();
  SELECT * INTO e1 FROM public.qa_mky_especialista('060e1', '900.000.034-33');
  SELECT * INTO e2 FROM public.qa_mky_especialista('060e2', '900.000.035-14');
  SELECT * INTO e3 FROM public.qa_mky_especialista('060e3', '900.000.036-03');
  SELECT * INTO e4 FROM public.qa_mky_especialista('060e4', '900.000.037-86');
  SELECT * INTO e5 FROM public.qa_mky_especialista('060e5', '900.000.038-67');
  SELECT * INTO e6 FROM public.qa_mky_especialista('060e6', '900.000.039-48');
  PERFORM public.qa_mky_claims(sa);
  PERFORM public.marketye_moderar_especialista(e1.prof_id, 'aprovado', NULL, true); PERFORM public.marketye_moderar_especialista(e2.prof_id, 'aprovado', NULL, false);
  PERFORM public.marketye_moderar_especialista(e3.prof_id, 'aprovado', NULL, true); PERFORM public.marketye_moderar_especialista(e4.prof_id, 'aprovado', NULL, true);
  PERFORM public.marketye_moderar_especialista(e5.prof_id, 'aprovado', NULL, true); PERFORM public.marketye_moderar_especialista(e6.prof_id, 'aprovado', NULL, false);
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  -- Atributos controlados (o cadastro nasce em Cidade QA / UF QA, presencial+online, sem avaliações).
  UPDATE public.marketplace_profissionais SET estado = 'ZZ', cidade = 'Cidade ZZ' WHERE id IN (e4.prof_id, e6.prof_id);
  UPDATE public.marketplace_profissionais SET cidade = 'Outra Cidade' WHERE id = e5.prof_id;
  UPDATE public.marketplace_profissionais SET atende_remoto = (id = e3.prof_id) WHERE id IN (e1.prof_id, e2.prof_id, e3.prof_id, e4.prof_id, e5.prof_id, e6.prof_id);
  UPDATE public.marketplace_profissionais SET nota_media = 3.0, total_avaliacoes = 3 WHERE id = e2.prof_id;
  UPDATE public.marketplace_profissionais SET nota_media = 4.5, total_avaliacoes = 3 WHERE id = e3.prof_id;
  UPDATE public.marketplace_profissionais SET nota_media = 4.8, total_avaliacoes = 3 WHERE id = e5.prof_id;
  UPDATE public.marketplace_reputacao SET nivel = 'prata' WHERE profissional_id = e2.prof_id;
  UPDATE public.marketplace_reputacao SET nivel = 'bronze' WHERE profissional_id = e3.prof_id;
  UPDATE public.marketplace_reputacao SET nivel = 'ouro' WHERE profissional_id = e5.prof_id;
  PERFORM public.qa_mky_anuncio_publicado(e1.uid, 'QA Filtro 060 E1', 'cipa-brigada', 'presencial', 'hora', 100);
  PERFORM public.qa_mky_anuncio_publicado(e2.uid, 'QA Filtro 060 E2', 'epi-riscos', 'online', 'visita', 500);
  PERFORM public.qa_mky_anuncio_publicado(e3.uid, 'QA Filtro 060 E3', 'primeiros-socorros', 'hibrido', 'sob_orcamento', NULL);
  PERFORM public.qa_mky_anuncio_publicado(e4.uid, 'QA Filtro 060 E4', 'seguranca-trabalho', 'presencial', 'pacote', 200);
  PERFORM public.qa_mky_anuncio_publicado(e5.uid, 'QA Filtro 060 E5', 'pgr', 'presencial', 'mensal', 1000);
  PERFORM public.qa_mky_anuncio_publicado(e6.uid, 'QA Filtro 060 E6', 'treinamentos-nr', 'online', 'hora', 50);
  filtros := ARRAY[
    '{"categoria_slug": "seguranca-trabalho"}'::jsonb, '{"modalidade": "online"}'::jsonb, '{"preco_max": 150}'::jsonb, '{"selo": true}'::jsonb,
    '{"nota_min": 4}'::jsonb, '{"nivel_min": "prata"}'::jsonb, '{"somente_remoto": true}'::jsonb, '{"uf": "QA"}'::jsonb, '{"cidade": "Cidade QA"}'::jsonb, '{}'::jsonb];
  rotulos := ARRAY['categoria raiz (com subáreas)', 'modalidade online (inclui híbrido)', 'preco_max 150 (inclui sob orçamento)', 'selo', 'nota_min 4 (sem avaliações passa)', 'nivel_min prata', 'somente_remoto', 'UF QA (online/remoto passam)', 'cidade', 'sem filtro'];
  esperados := ARRAY[
    ARRAY['E1', 'E2', 'E4', 'E5', '', ''], ARRAY['E2', 'E3', 'E6', '', '', ''], ARRAY['E1', 'E3', 'E6', '', '', ''], ARRAY['E1', 'E3', 'E4', 'E5', '', ''],
    ARRAY['E1', 'E3', 'E4', 'E5', 'E6', ''], ARRAY['E2', 'E5', '', '', '', ''], ARRAY['E2', 'E3', 'E6', '', '', ''], ARRAY['E1', 'E2', 'E3', 'E5', 'E6', ''],
    ARRAY['E1', 'E2', 'E3', 'E6', '', ''], ARRAY['E1', 'E2', 'E3', 'E4', 'E5', 'E6']];
  FOR k IN 1..array_length(filtros, 1) LOOP
    v_exp := array_remove(ARRAY[esperados[k][1], esperados[k][2], esperados[k][3], esperados[k][4], esperados[k][5], esperados[k][6]], '');
    r.passo_ordem := k; r.passo_acao := 'Filtrar por ' || rotulos[k]; r.esperado := array_to_string(v_exp, ',');
    SELECT COALESCE(array_agg(right(x->>'nome', 2) ORDER BY right(x->>'nome', 2)), '{}') INTO v_got FROM public.marketye_buscar_interno(filtros[k] || '{"q": "QA Filtro 060", "limite": 100}'::jsonb) x;
    IF v_got <> v_exp THEN falhas := array_append(falhas, format('%s: veio %s, esperado %s', rotulos[k], array_to_string(v_got, ','), array_to_string(v_exp, ','))); END IF;
  END LOOP;
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Dez filtros (categoria com subáreas, modalidade, preço, selo, nota, nível, remoto, UF, cidade, nenhum) devolvem exatamente o conjunto esperado entre 6 anúncios controlados.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-061 — relevância por obrigação; pesos vêm da configuração
CREATE OR REPLACE FUNCTION public.qa_caso_mky_061()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_claims text; falhas text[] := '{}'; sa uuid; p record; q record; an_p uuid; an_q uuid; v_first text; v_fit numeric; sp numeric; sq numeric; sp2 numeric; sq2 numeric; v_pesos jsonb;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  sa := public.qa_mky_superadmin();
  SELECT * INTO p FROM public.qa_mky_especialista('061p', '900.000.034-33');
  SELECT * INTO q FROM public.qa_mky_especialista('061q', '900.000.035-14');
  PERFORM public.qa_mky_claims(sa);
  PERFORM public.marketye_moderar_especialista(p.prof_id, 'aprovado', NULL, true); PERFORM public.marketye_moderar_especialista(q.prof_id, 'aprovado', NULL, true);
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  an_p := public.qa_mky_anuncio_publicado(p.uid, 'QA Fit 061 P', 'seguranca-trabalho', 'online', 'sob_orcamento', NULL, '{"obrigacao_legal": ["NR-1"]}'::jsonb);
  an_q := public.qa_mky_anuncio_publicado(q.uid, 'QA Fit 061 Q', 'seguranca-trabalho', 'online', 'sob_orcamento', NULL, '{"obrigacao_legal": ["NR-17"]}'::jsonb);
  r.passo_ordem := 1; r.passo_acao := 'Empresa com obrigação NR-1 busca'; r.esperado := 'P antes de Q; fatores.fit de P = 1.0';
  SELECT x->>'servico_id', (x->'fatores'->>'fit')::numeric INTO v_first, v_fit FROM public.marketye_buscar_interno('{"q": "QA Fit 061", "obrigacoes": ["NR-1"]}'::jsonb) x LIMIT 1;
  IF v_first <> an_p::text OR v_fit <> 1.0 THEN falhas := array_append(falhas, format('NR-1: primeiro %s, fit %s', CASE WHEN v_first = an_p::text THEN 'P' ELSE 'Q' END, v_fit)); END IF;
  SELECT (x->>'score')::numeric INTO sp FROM public.marketye_buscar_interno('{"q": "QA Fit 061", "obrigacoes": ["NR-1"]}'::jsonb) x WHERE x->>'servico_id' = an_p::text;
  SELECT (x->>'score')::numeric INTO sq FROM public.marketye_buscar_interno('{"q": "QA Fit 061", "obrigacoes": ["NR-1"]}'::jsonb) x WHERE x->>'servico_id' = an_q::text;
  r.passo_ordem := 2; r.passo_acao := 'Empresa com obrigação NR-17 busca'; r.esperado := 'Q antes de P';
  SELECT x->>'servico_id' INTO v_first FROM public.marketye_buscar_interno('{"q": "QA Fit 061", "obrigacoes": ["NR-17"]}'::jsonb) x LIMIT 1;
  IF v_first <> an_q::text THEN falhas := array_append(falhas, 'NR-17: Q não veio primeiro'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Superadmin zera o peso fit e a busca repete'; r.esperado := 'a vantagem de P some sem deploy';
  v_pesos := public.marketye_config('relevancia_pesos') || '{"fit": 0}'::jsonb;
  PERFORM public.qa_mky_claims(sa); PERFORM public.marketye_config_salvar('relevancia_pesos', v_pesos, 'teste automatizado', 'BR');
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  SELECT (x->>'score')::numeric INTO sp2 FROM public.marketye_buscar_interno('{"q": "QA Fit 061", "obrigacoes": ["NR-1"]}'::jsonb) x WHERE x->>'servico_id' = an_p::text;
  SELECT (x->>'score')::numeric INTO sq2 FROM public.marketye_buscar_interno('{"q": "QA Fit 061", "obrigacoes": ["NR-1"]}'::jsonb) x WHERE x->>'servico_id' = an_q::text;
  IF NOT (sp > sq) THEN falhas := array_append(falhas, format('com peso: P %s não supera Q %s', sp, sq)); END IF;
  IF sp2 <> sq2 OR sp2 >= sp THEN falhas := array_append(falhas, format('peso fit zerado não mudou a ordem (P %s→%s, Q %s→%s)', sp, sp2, sq, sq2)); END IF;
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := format('Obrigação casada dá fit 1.0 e põe o anúncio na frente (P %s × Q %s); zerando o peso na configuração os dois empatam (%s) sem deploy.', sp, sq, sp2);
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-062 — proteção ao novato por dias ou avaliações, parametrizada
CREATE OR REPLACE FUNCTION public.qa_caso_mky_062()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_claims text; falhas text[] := '{}'; sa uuid; n1 record; n2 record; x1 jsonb; x2 jsonb; t1 uuid := public.qa_sandbox_tenant_id(); v_x uuid;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  sa := public.qa_mky_superadmin(); v_x := public.qa_mky_usuario_empresa(t1, '062x');
  SELECT * INTO n1 FROM public.qa_mky_especialista('062n1', '900.000.034-33');
  SELECT * INTO n2 FROM public.qa_mky_especialista('062n2', '900.000.035-14');
  PERFORM public.qa_mky_claims(sa);
  PERFORM public.marketye_moderar_especialista(n1.prof_id, 'aprovado', NULL, true); PERFORM public.marketye_moderar_especialista(n2.prof_id, 'aprovado', NULL, true);
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  UPDATE public.marketplace_profissionais SET created_at = now() - interval '60 days' WHERE id = n2.prof_id;
  PERFORM public.marketye_recalcular_reputacao(n2.prof_id);
  PERFORM public.qa_mky_anuncio_publicado(n1.uid, 'QA Novato 062 N1', 'seguranca-trabalho', 'online', 'sob_orcamento', NULL);
  PERFORM public.qa_mky_anuncio_publicado(n2.uid, 'QA Novato 062 N2', 'seguranca-trabalho', 'online', 'sob_orcamento', NULL);
  r.passo_ordem := 1; r.passo_acao := 'Buscar'; r.esperado := 'novato só para o criado hoje, com exploração 1.0';
  SELECT x INTO x1 FROM public.marketye_buscar_interno('{"q": "QA Novato 062"}'::jsonb) x WHERE x->'profissional'->>'id' = n1.prof_id::text;
  SELECT x INTO x2 FROM public.marketye_buscar_interno('{"q": "QA Novato 062"}'::jsonb) x WHERE x->'profissional'->>'id' = n2.prof_id::text;
  IF (x1->'profissional'->>'novato')::boolean IS DISTINCT FROM true OR (x1->'fatores'->>'exploracao')::numeric <> 1.0 THEN falhas := array_append(falhas, 'novo de hoje não protegido'); END IF;
  IF (x2->'profissional'->>'novato')::boolean IS DISTINCT FROM false OR (x2->'fatores'->>'exploracao')::numeric >= 1.0 THEN falhas := array_append(falhas, 'o de 60 dias segue protegido'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Três avaliações no novato e buscar'; r.esperado := 'novato = false';
  INSERT INTO public.marketplace_avaliacoes (profissional_id, avaliador_id, tenant_id, direcao, criterios, nota_geral, comentario)
  SELECT n1.prof_id, v_x, t1, 'cliente_para_especialista', '{"pontualidade":5}'::jsonb, 5, 'Avaliação fictícia de teste ' || g FROM generate_series(1, 3) g;
  PERFORM public.marketye_recalcular_reputacao(n1.prof_id);
  SELECT x INTO x1 FROM public.marketye_buscar_interno('{"q": "QA Novato 062"}'::jsonb) x WHERE x->'profissional'->>'id' = n1.prof_id::text;
  IF (x1->'profissional'->>'novato')::boolean IS DISTINCT FROM false THEN falhas := array_append(falhas, 'com 3 avaliações continua protegido'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'protecao_novato.dias = 90 na configuração'; r.esperado := 'o de 60 dias passa a protegido';
  PERFORM public.qa_mky_claims(sa); PERFORM public.marketye_config_salvar('protecao_novato', '{"dias": 90, "ate_avaliacoes": 3}'::jsonb, 'teste automatizado', 'BR');
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  PERFORM public.marketye_recalcular_reputacao(n2.prof_id);
  SELECT x INTO x2 FROM public.marketye_buscar_interno('{"q": "QA Novato 062"}'::jsonb) x WHERE x->'profissional'->>'id' = n2.prof_id::text;
  IF (x2->'profissional'->>'novato')::boolean IS DISTINCT FROM true THEN falhas := array_append(falhas, 'com janela de 90 dias o de 60 dias não ficou protegido'); END IF;
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Novato de hoje protegido (exploração 1.0), o de 60 dias não; três avaliações encerram a proteção; ampliar os dias na configuração reabre para o de 60 dias.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-063 — endereço da empresa como padrão; raio; remoto; "perto de mim"; ignorar UF
CREATE OR REPLACE FUNCTION public.qa_caso_mky_063()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_claims text; falhas text[] := '{}'; sa uuid; g1 record; g2 record; g3 record; a1 uuid; a2 uuid; a3 uuid; t1 uuid := public.qa_sandbox_tenant_id(); v_x uuid; v_res jsonb; ids text[]; v_emp uuid; d1 numeric;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  sa := public.qa_mky_superadmin(); v_x := public.qa_mky_usuario_empresa(t1, '063x');
  SELECT id INTO v_emp FROM public.empresa_cadastro WHERE tenant_id = t1 ORDER BY created_at LIMIT 1;
  IF v_emp IS NULL THEN INSERT INTO public.empresa_cadastro (tenant_id, razao_social) VALUES (t1, 'Empresa QA 063') RETURNING id INTO v_emp; END IF;
  UPDATE public.empresa_cadastro SET latitude = -25.0, longitude = -52.0, estado = 'QA' WHERE id = v_emp;
  SELECT * INTO g1 FROM public.qa_mky_especialista('063g1', '900.000.034-33');
  SELECT * INTO g2 FROM public.qa_mky_especialista('063g2', '900.000.035-14');
  SELECT * INTO g3 FROM public.qa_mky_especialista('063g3', '900.000.036-03');
  PERFORM public.qa_mky_claims(sa);
  PERFORM public.marketye_moderar_especialista(g1.prof_id, 'aprovado', NULL, true); PERFORM public.marketye_moderar_especialista(g2.prof_id, 'aprovado', NULL, true); PERFORM public.marketye_moderar_especialista(g3.prof_id, 'aprovado', NULL, true);
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  UPDATE public.marketplace_profissionais SET latitude = -25.18, longitude = -52.0, atende_remoto = false WHERE id = g1.prof_id; -- ~20 km, presencial
  UPDATE public.marketplace_profissionais SET latitude = -32.2, longitude = -52.0, atende_remoto = true WHERE id = g2.prof_id;  -- ~800 km, remoto
  UPDATE public.marketplace_profissionais SET latitude = -27.25, longitude = -52.0, atende_remoto = false WHERE id = g3.prof_id; -- ~250 km, presencial
  a1 := public.qa_mky_anuncio_publicado(g1.uid, 'QA Geo 063 G1', 'seguranca-trabalho', 'presencial', 'sob_orcamento', NULL);
  a2 := public.qa_mky_anuncio_publicado(g2.uid, 'QA Geo 063 G2', 'seguranca-trabalho', 'online', 'sob_orcamento', NULL);
  a3 := public.qa_mky_anuncio_publicado(g3.uid, 'QA Geo 063 G3', 'seguranca-trabalho', 'presencial', 'sob_orcamento', NULL);
  r.passo_ordem := 1; r.passo_acao := 'Buscar sem coordenadas como usuário da empresa'; r.esperado := 'usa o endereço da empresa: 20 km e remoto entram; 250 km só via relaxamento de raio';
  SELECT COALESCE(array_agg(x->>'servico_id'), '{}') INTO ids FROM public.marketye_buscar_interno('{"q": "QA Geo 063", "lat": -25.0, "lng": -52.0}'::jsonb) x;
  IF NOT (ids @> ARRAY[a1::text, a2::text]) OR ids @> ARRAY[a3::text] THEN falhas := array_append(falhas, 'raio 100 km puro: conjunto errado'); END IF;
  SELECT (x->>'distancia_km')::numeric INTO d1 FROM public.marketye_buscar_interno('{"q": "QA Geo 063", "lat": -25.0, "lng": -52.0}'::jsonb) x WHERE x->>'servico_id' = a1::text;
  IF d1 IS NULL OR abs(d1 - 20) > 3 THEN falhas := array_append(falhas, format('distância de G1 %s km (esperado ~20)', d1)); END IF;
  PERFORM public.qa_mky_claims(v_x);
  v_res := public.marketye_buscar('{"q": "QA Geo 063"}'::jsonb);
  IF (v_res->'filtros_aplicados'->>'lat')::numeric <> -25.0 OR v_res->'filtros_aplicados'->>'uf' <> 'QA' THEN falhas := array_append(falhas, 'não injetou lat/lng/UF da empresa'); END IF;
  SELECT COALESCE(array_agg(e->>'servico_id'), '{}') INTO ids FROM jsonb_array_elements(v_res->'resultados') e;
  IF NOT (ids @> ARRAY[a1::text, a2::text, a3::text]) OR NOT (v_res->'relaxamentos' @> '["raio"]'::jsonb) THEN falhas := array_append(falhas, 'o de 250 km não entrou pelo relaxamento de raio'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Buscar com lat/lng da tela (perto do G3)'; r.esperado := 'sobrepõe o endereço da empresa';
  v_res := public.marketye_buscar('{"q": "QA Geo 063", "lat": -27.25, "lng": -52.0}'::jsonb);
  IF (v_res->'filtros_aplicados'->>'lat')::numeric <> -27.25 THEN falhas := array_append(falhas, 'coordenada da tela ignorada'); END IF;
  SELECT (e->>'distancia_km')::numeric INTO d1 FROM jsonb_array_elements(v_res->'resultados') e WHERE e->>'servico_id' = a3::text;
  IF d1 IS NULL OR d1 > 1 THEN falhas := array_append(falhas, format('G3 a %s km da coordenada da tela (esperado ~0)', d1)); END IF;
  r.passo_ordem := 3; r.passo_acao := 'ignorar_uf_padrao = true'; r.esperado := 'não injeta a UF da empresa';
  v_res := public.marketye_buscar('{"q": "QA Geo 063", "ignorar_uf_padrao": true}'::jsonb);
  IF v_res->'filtros_aplicados' ? 'uf' OR v_res->'filtros_aplicados' ? 'uf_padrao' THEN falhas := array_append(falhas, 'UF injetada mesmo com ignorar_uf_padrao'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Sem coordenadas a busca parte do endereço da empresa (lat/lng/UF): 20 km e remoto entram no raio de 100 km, o de 250 km só pelo relaxamento; coordenada da tela sobrepõe; ignorar_uf_padrao não injeta UF.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-064 — busca vazia registra demanda latente (uma linha por empresa/categoria/UF/dia) e aceita "Avise-me"
CREATE OR REPLACE FUNCTION public.qa_caso_mky_064()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_claims text; falhas text[] := '{}'; t1 uuid := public.qa_sandbox_tenant_id(); t2 uuid; v_x uuid; v_y uuid; v_cat uuid; v_res jsonb; n int; v_av boolean;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  SELECT id INTO t2 FROM public.tenants WHERE slug = 'qa-sandbox-2';
  v_x := public.qa_mky_usuario_empresa(t1, '064x'); v_y := public.qa_mky_usuario_empresa(t2, '064y');
  SELECT id INTO v_cat FROM public.marketplace_categorias WHERE slug = 'pgr';
  r.passo_ordem := 1; r.passo_acao := 'Buscar "xyzservicoinexistente" em PGR'; r.esperado := 'total 0; categorias_adjacentes não vazio';
  PERFORM public.qa_mky_claims(v_x);
  v_res := public.marketye_buscar('{"q": "xyzservicoinexistente", "categoria_slug": "pgr"}'::jsonb);
  IF (v_res->>'total')::int <> 0 OR jsonb_array_length(COALESCE(v_res->'categorias_adjacentes', '[]'::jsonb)) = 0 OR (v_res->>'oferta_insuficiente')::boolean IS DISTINCT FROM true THEN falhas := array_append(falhas, 'busca vazia sem sugestões de áreas parecidas'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'marketye_registrar_busca com avisar = true e e-mail'; r.esperado := 'linha em marketplace_demanda_latente com avisar = true';
  PERFORM public.marketye_registrar_busca(v_cat, 'QA', NULL, 'xyzservicoinexistente', 0, true, 'qa-mky-064@sandbox.invalid');
  SELECT count(*), bool_and(avisar) INTO n, v_av FROM public.marketplace_demanda_latente WHERE tenant_id = t1 AND categoria_id = v_cat AND uf = 'QA' AND dia = CURRENT_DATE;
  IF n <> 1 OR v_av IS DISTINCT FROM true THEN falhas := array_append(falhas, format('registro: %s linhas, avisar %s', n, v_av)); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Repetir a busca no mesmo dia'; r.esperado := 'mesma linha atualizada, não duplica';
  PERFORM public.marketye_registrar_busca(v_cat, 'QA', NULL, 'outro termo', 0, false, NULL);
  SELECT count(*), bool_and(avisar) INTO n, v_av FROM public.marketplace_demanda_latente WHERE tenant_id = t1 AND categoria_id = v_cat AND uf = 'QA' AND dia = CURRENT_DATE;
  IF n <> 1 OR v_av IS DISTINCT FROM true THEN falhas := array_append(falhas, format('repetição: %s linhas, avisar %s', n, v_av)); END IF;
  r.passo_ordem := 4; r.passo_acao := 'Consultar como outra empresa'; r.esperado := 'não lê a linha da primeira (RLS)';
  PERFORM public.qa_mky_claims(v_y);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.marketplace_demanda_latente WHERE tenant_id = t1; IF n > 0 THEN falhas := array_append(falhas, 'outra empresa lê a demanda da primeira'); END IF;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Busca sem oferta devolve total 0 com áreas parecidas; o registro cria uma linha por empresa/categoria/UF/dia com "Avise-me" e não duplica; outra empresa não a lê.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN RESET ROLE; PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-065 — demanda latente pública só agregada (célula ≥ 5 empresas); tabela crua fechada
CREATE OR REPLACE FUNCTION public.qa_caso_mky_065()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_claims text; falhas text[] := '{}'; t1 uuid := public.qa_sandbox_tenant_id(); v_x uuid; v_pgr uuid; v_ltcat uuid; v_res jsonb; v_txt text; n int; ids uuid[] := '{}'; j int; v_msg text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  v_x := public.qa_mky_usuario_empresa(t1, '065x');
  SELECT id INTO v_pgr FROM public.marketplace_categorias WHERE slug = 'pgr'; SELECT id INTO v_ltcat FROM public.marketplace_categorias WHERE slug = 'ltcat-laudos';
  -- Seis empresas sintéticas na célula PGR/QA e três em LTCAT/QA. A tabela não tem chave estrangeira para tenants; a trava do cercado é
  -- desligada só para estas linhas (ids que não existem em lugar nenhum), dentro da transação descartada.
  FOR j IN 1..6 LOOP ids := array_append(ids, gen_random_uuid()); END LOOP;
  PERFORM set_config('app.qa_modo', 'off', true);
  INSERT INTO public.marketplace_demanda_latente (tenant_id, categoria_id, uf, termos, resultados, avisar, avisar_email)
  SELECT ids[i], v_pgr, 'QA', 'termo sigiloso ' || i, 0, true, 'empresa' || i || '@sandbox.invalid' FROM generate_series(1, 6) i;
  INSERT INTO public.marketplace_demanda_latente (tenant_id, categoria_id, uf, termos, resultados) SELECT ids[i], v_ltcat, 'QA', 'termo sigiloso ltcat', 0 FROM generate_series(1, 3) i;
  PERFORM set_config('app.qa_modo', 'on', true);
  r.passo_ordem := 1; r.passo_acao := 'marketye_vagas_demanda() sem login'; r.esperado := 'só a célula com ≥ 5 empresas; só categoria, UF e contagem';
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  SET LOCAL ROLE anon;
  v_res := public.marketye_vagas_demanda(NULL);
  RESET ROLE;
  SELECT count(*) INTO n FROM jsonb_array_elements(v_res) e WHERE e->>'uf' = 'QA' AND e->>'categoria_slug' = 'pgr' AND (e->>'empresas')::int = 6; IF n <> 1 THEN falhas := array_append(falhas, 'célula PGR/QA com 6 empresas não veio'); END IF;
  SELECT count(*) INTO n FROM jsonb_array_elements(v_res) e WHERE e->>'uf' = 'QA' AND e->>'categoria_slug' = 'ltcat-laudos'; IF n > 0 THEN falhas := array_append(falhas, 'célula com 3 empresas exposta (abaixo do piso)'); END IF;
  v_txt := v_res::text;
  IF v_txt LIKE '%sigiloso%' OR v_txt LIKE '%@%' OR v_txt LIKE '%' || ids[1]::text || '%' OR v_txt ILIKE '%tenant%' THEN falhas := array_append(falhas, 'agregado expõe termo, e-mail ou id de empresa'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'SELECT em marketplace_demanda_latente como anon'; r.esperado := 'zero linhas ou recusado';
  SET LOCAL ROLE anon;
  BEGIN SELECT count(*) INTO n FROM public.marketplace_demanda_latente WHERE uf = 'QA'; v_msg := n::text; EXCEPTION WHEN insufficient_privilege THEN v_msg := 'recusado'; END;
  RESET ROLE;
  IF v_msg NOT IN ('0', 'recusado') THEN falhas := array_append(falhas, 'anon lê ' || v_msg || ' linhas cruas'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'SELECT como usuário da empresa A'; r.esperado := 'nenhuma linha de outra empresa (só as de A, ou nenhuma)';
  PERFORM public.qa_mky_claims(v_x);
  PERFORM public.marketye_registrar_busca(v_pgr, 'QA', NULL, 'busca da própria empresa', 0, false, NULL);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.marketplace_demanda_latente WHERE uf = 'QA' AND tenant_id <> t1;
  RESET ROLE;
  IF n > 0 THEN falhas := array_append(falhas, format('empresa A lê %s linhas de outras empresas', n)); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'A função pública devolve só a célula com 6 empresas (categoria, UF, contagem) e esconde a de 3; a tabela crua não devolve linha alguma de terceiros para visitante nem para empresa.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN RESET ROLE; PERFORM set_config('app.qa_modo', 'on', true); PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-068 — só ativo × publicado aparece; nenhum estado intermediário vaza
CREATE OR REPLACE FUNCTION public.qa_caso_mky_068()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_claims text; falhas text[] := '{}'; sa uuid; v1 record; v2 record; v3 record; v4 record; v5 record; e record; v_an uuid; v_cat uuid; n int; n_esp int; v_vit jsonb; v_msg text; v_pub_ok uuid;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  sa := public.qa_mky_superadmin();
  SELECT id INTO v_cat FROM public.marketplace_categorias WHERE slug = 'seguranca-trabalho';
  SELECT * INTO v1 FROM public.qa_mky_especialista('068v1', '900.000.034-33');
  SELECT * INTO v2 FROM public.qa_mky_especialista('068v2', '900.000.035-14');
  SELECT * INTO v3 FROM public.qa_mky_especialista('068v3', '900.000.036-03');
  SELECT * INTO v4 FROM public.qa_mky_especialista('068v4', '900.000.037-86');
  SELECT * INTO v5 FROM public.qa_mky_especialista('068v5', '900.000.038-67');
  PERFORM public.qa_mky_claims(sa);
  FOR e IN SELECT * FROM (VALUES (v1.prof_id), (v2.prof_id), (v3.prof_id), (v4.prof_id), (v5.prof_id)) t(p) LOOP PERFORM public.marketye_moderar_especialista(e.p, 'aprovado', NULL, true); END LOOP;
  -- Cada um com um anúncio em cada status (publica enquanto está ativo).
  FOR e IN SELECT * FROM (VALUES (v1.uid, 'v1'), (v2.uid, 'v2'), (v3.uid, 'v3'), (v4.uid, 'v4'), (v5.uid, 'v5')) t(u, m) LOOP
    PERFORM public.qa_mky_claims(e.u);
    v_an := (public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Vis 068 ' || e.m || ' rascunho', 'descricao', 'Serviço fictício de teste do MarketYE para visibilidade.', 'categoria_id', v_cat, 'modalidade', 'online', 'tipo_preco', 'sob_orcamento'))->>'id')::uuid;
    v_an := (public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Vis 068 ' || e.m || ' pausado', 'descricao', 'Serviço fictício de teste do MarketYE para visibilidade.', 'categoria_id', v_cat, 'modalidade', 'online', 'tipo_preco', 'sob_orcamento'))->>'id')::uuid;
    PERFORM public.marketye_anuncio_publicar(v_an); PERFORM public.marketye_anuncio_status(v_an, 'pausado');
    v_an := (public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Vis 068 ' || e.m || ' removido', 'descricao', 'Serviço fictício de teste do MarketYE para visibilidade.', 'categoria_id', v_cat, 'modalidade', 'online', 'tipo_preco', 'sob_orcamento'))->>'id')::uuid;
    PERFORM public.marketye_anuncio_publicar(v_an); PERFORM public.marketye_anuncio_status(v_an, 'removido');
    v_an := (public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Vis 068 ' || e.m || ' publicado', 'descricao', 'Serviço fictício de teste do MarketYE para visibilidade.', 'categoria_id', v_cat, 'modalidade', 'online', 'tipo_preco', 'sob_orcamento'))->>'id')::uuid;
    PERFORM public.marketye_anuncio_publicar(v_an);
    IF e.m = 'v5' THEN v_pub_ok := v_an; END IF;
  END LOOP;
  PERFORM public.qa_mky_claims(sa);
  PERFORM public.marketye_especialista_situacao(v1.prof_id, 'pendente', 'teste'); PERFORM public.marketye_especialista_situacao(v2.prof_id, 'suspenso', 'teste');
  PERFORM public.marketye_moderar_especialista(v3.prof_id, 'rejeitado', 'motivo de teste', false);
  PERFORM public.qa_mky_claims(v4.uid); PERFORM public.marketye_excluir_meu_perfil('EXCLUIR');
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  r.passo_ordem := 1; r.passo_acao := 'Buscar sem filtro'; r.esperado := 'só ativo × publicado (1 de 20)';
  SELECT count(*) INTO n FROM public.marketye_buscar_interno('{"q": "QA Vis 068", "limite": 100}'::jsonb) x;
  SELECT count(*) INTO n_esp FROM public.marketye_buscar_interno('{"q": "QA Vis 068", "limite": 100}'::jsonb) x WHERE x->>'servico_id' = v_pub_ok::text;
  IF n <> 1 OR n_esp <> 1 THEN falhas := array_append(falhas, format('busca devolveu %s anúncios (esperado só o publicado do ativo)', n)); END IF;
  r.passo_ordem := 2; r.passo_acao := 'marketye_vitrine_publica() sem login'; r.esperado := 'contagens pela mesma regra; sem PII';
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  SET LOCAL ROLE anon; v_vit := public.marketye_vitrine_publica(); RESET ROLE;
  SELECT count(*) INTO n FROM public.marketplace_servicos s JOIN public.marketplace_profissionais p ON p.id = s.profissional_id WHERE s.status = 'publicado' AND s.ativo AND p.status = 'ativo' AND p.excluido_em IS NULL;
  IF (v_vit->>'anuncios_publicados')::int <> n THEN falhas := array_append(falhas, format('vitrine conta %s anúncios publicados; de especialistas ativos são %s', v_vit->>'anuncios_publicados', n)); END IF;
  IF v_vit::text LIKE '%@%' OR v_vit::text ILIKE '%QA Especialista%' THEN falhas := array_append(falhas, 'vitrine pública expõe dado pessoal'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Ler marketplace_servicos como anon'; r.esperado := 'só publicados de especialistas ativos';
  SET LOCAL ROLE anon;
  BEGIN SELECT count(*) INTO n FROM public.marketplace_servicos WHERE nome LIKE 'QA Vis 068%'; v_msg := n::text; EXCEPTION WHEN insufficient_privilege THEN v_msg := 'recusado'; END;
  RESET ROLE;
  IF v_msg NOT IN ('1', 'recusado') THEN falhas := array_append(falhas, format('anon lê %s anúncios na tabela (publicados de pendente/suspenso/bloqueado vazam)', v_msg)); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Entre 5 especialistas × 4 status de anúncio, a busca, a vitrine pública e a tabela lida por visitante mostram só o publicado do especialista ativo.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN RESET ROLE; PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ===== Família E — conversa (lead) (MKY-071..077) =====
-- MKY-071 — terceiro não lê, não escreve e não libera contato em conversa alheia
CREATE OR REPLACE FUNCTION public.qa_caso_mky_071()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; n int; v_msg text; l uuid;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca(); l := (s->>'lead_xb')::uuid;
  r.passo_ordem := 1; r.passo_acao := 'Empresa Y lê a conversa entre X e B'; r.esperado := 'zero linhas';
  PERFORM public.qa_mky_claims((s->>'y')::uuid);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.marketplace_leads WHERE id = l; IF n > 0 THEN falhas := array_append(falhas, 'Y lê o lead'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_lead_mensagens WHERE lead_id = l; IF n > 0 THEN falhas := array_append(falhas, 'Y lê as mensagens'); END IF;
  RESET ROLE;
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.marketplace_leads WHERE id = l; IF n <> 1 THEN falhas := array_append(falhas, 'controle: X não lê a própria conversa'); END IF;
  RESET ROLE;
  r.passo_ordem := 2; r.passo_acao := 'Y chama marketye_lead_mensagem no lead'; r.esperado := 'recusado';
  PERFORM public.qa_mky_claims((s->>'y')::uuid);
  BEGIN PERFORM public.marketye_lead_mensagem(l, 'Mensagem invasora de teste'); v_msg := 'aceitou'; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_msg = 'aceitou' THEN falhas := array_append(falhas, 'Y escreveu na conversa alheia'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Especialista A chama liberar_contato e lead_status'; r.esperado := 'recusado';
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  BEGIN PERFORM public.marketye_lead_liberar_contato(l); v_msg := 'aceitou'; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_msg = 'aceitou' THEN falhas := array_append(falhas, 'A liberou contato de conversa alheia'); END IF;
  BEGIN PERFORM public.marketye_lead_status(l, 'ganho', NULL); v_msg := 'aceitou'; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_msg = 'aceitou' THEN falhas := array_append(falhas, 'A mudou o status de conversa alheia'); END IF;
  r.passo_ordem := 4; r.passo_acao := 'Y chama marketye_lead_contato'; r.esperado := 'recusado';
  PERFORM public.qa_mky_claims((s->>'y')::uuid);
  BEGIN PERFORM public.marketye_lead_contato(l); v_msg := 'aceitou'; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_msg = 'aceitou' THEN falhas := array_append(falhas, 'Y leu o contato de conversa alheia'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_lead_mensagens WHERE lead_id = l AND texto ILIKE '%invasora%'; IF n > 0 THEN falhas := array_append(falhas, 'mensagem invasora gravada'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Outra empresa não lê lead nem mensagens e não escreve; outro especialista não libera contato nem muda status; contato negado a terceiro. X lê a própria conversa.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN RESET ROLE; PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-072 — recusa de conversa: sem ocorrência, sem reflexo na saúde, conta como resposta
CREATE OR REPLACE FUNCTION public.qa_caso_mky_072()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; n int; l uuid; rep0 jsonb; rep1 jsonb; v_st text; v_portal jsonb; v_txt text; obs text := '';
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  l := (public.marketye_abrir_lead((s->>'a_prof')::uuid, (s->>'a_pub')::uuid, 'Preciso de um serviço fictício de teste.')->>'id')::uuid;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  UPDATE public.marketplace_leads SET created_at = now() - interval '2 hours' WHERE id = l;  -- entra na janela de cálculo (leads com mais de 1 h)
  rep0 := public.marketye_recalcular_reputacao((s->>'a_prof')::uuid);
  r.passo_ordem := 1; r.passo_acao := 'Especialista chama marketye_lead_status(lead, perdido, "Não vou atender")'; r.esperado := 'lead encerrado; nenhuma ocorrência';
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  PERFORM public.marketye_lead_status(l, 'perdido', 'Não vou atender');
  SELECT status INTO v_st FROM public.marketplace_leads WHERE id = l; IF v_st NOT IN ('perdido', 'encerrado') THEN falhas := array_append(falhas, 'status ' || v_st); END IF;
  SELECT count(*) INTO n FROM public.marketplace_ocorrencias WHERE profissional_id = (s->>'a_prof')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'recusa gerou ocorrência'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Recalcular reputação'; r.esperado := 'saúde não piora; a recusa conta como resposta, não como falta';
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  rep1 := public.marketye_recalcular_reputacao((s->>'a_prof')::uuid);
  IF (rep1->>'saude_score')::numeric < (rep0->>'saude_score')::numeric THEN falhas := array_append(falhas, format('saúde caiu de %s para %s', rep0->>'saude_score', rep1->>'saude_score')); END IF;
  IF COALESCE((rep1->>'taxa_resposta_90d')::numeric, 0) < 1 THEN falhas := array_append(falhas, format('recusa não contou como resposta (taxa_resposta %s)', COALESCE(rep1->>'taxa_resposta_90d', 'nula'))); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Ler o portal'; r.esperado := 'texto de encerramento sem palavra disciplinar';
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  v_portal := public.marketye_meu_portal();
  SELECT e->>'ultima_mensagem' INTO v_txt FROM jsonb_array_elements(v_portal->'leads') e WHERE e->>'id' = l::text;
  IF v_txt IS NULL OR v_txt ~* '(penalidade|infra[çc][ãa]o|puni[çc][ãa]o|advert[êe]ncia|falta grave)' THEN falhas := array_append(falhas, 'texto disciplinar ou ausente: ' || COALESCE(v_txt, 'nulo')); END IF;
  IF v_txt ILIKE 'A empresa encerrou%' THEN obs := ' Observação: quando o especialista recusa, a mensagem de sistema diz que foi a empresa que encerrou.'; END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Recusar encerra a conversa sem ocorrência, sem derrubar a saúde e contando como resposta; o texto do portal não é disciplinar.' || obs;
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; ') || obs; END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-073 — lead parado não gera ocorrência, não muda selo/status/nível; só reflete na saúde
CREATE OR REPLACE FUNCTION public.qa_caso_mky_073()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; n int; l uuid; rep jsonb; p record; v_portal jsonb;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  l := (public.marketye_abrir_lead((s->>'a_prof')::uuid, (s->>'a_pub')::uuid, 'Preciso de um serviço fictício de teste sem resposta.')->>'id')::uuid;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  UPDATE public.marketplace_leads SET created_at = now() - interval '3 days' WHERE id = l;
  r.passo_ordem := 1; r.passo_acao := 'Recalcular reputação'; r.esperado := 'taxa de resposta reflete o atraso; cor pode cair';
  rep := public.marketye_recalcular_reputacao((s->>'a_prof')::uuid);
  IF COALESCE((rep->>'taxa_resposta_90d')::numeric, 1) <> 0 OR rep->>'tempo_resposta_mediano_min' IS NOT NULL THEN falhas := array_append(falhas, format('taxa %s / tempo %s não refletem lead sem resposta', rep->>'taxa_resposta_90d', rep->>'tempo_resposta_mediano_min')); END IF;
  IF rep->>'saude_cor' = 'verde' THEN falhas := array_append(falhas, 'saúde continua verde com lead parado'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Conferir especialista'; r.esperado := 'ativo, selo intacto, sem ocorrência, sem ajuste de nível';
  SELECT * INTO p FROM public.marketplace_profissionais WHERE id = (s->>'a_prof')::uuid;
  IF p.status::text <> 'ativo' OR NOT p.selo_verificado THEN falhas := array_append(falhas, format('status %s, selo %s', p.status, p.selo_verificado)); END IF;
  SELECT count(*) INTO n FROM public.marketplace_ocorrencias WHERE profissional_id = p.id; IF n > 0 THEN falhas := array_append(falhas, 'ocorrência gerada'); END IF;
  IF rep->>'nivel' <> 'novo' OR rep->>'nivel_aviso_em' IS NOT NULL THEN falhas := array_append(falhas, 'nível ou aviso de nível alterado'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Conferir textos do portal'; r.esperado := 'nada como penalidade ou infração';
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  v_portal := public.marketye_meu_portal();
  IF v_portal::text ~* '(penalidade|infra[çc][ãa]o|puni[çc][ãa]o|advert[êe]ncia)' THEN falhas := array_append(falhas, 'portal usa palavra disciplinar'); END IF;
  IF (v_portal->'metricas'->>'sem_resposta')::int < 1 THEN falhas := array_append(falhas, 'portal não sinaliza a conversa sem resposta'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := format('Lead parado 3 dias: taxa de resposta 0 e saúde %s (%s), sem ocorrência, selo e status intactos, nível sem aviso; portal aponta a conversa sem resposta sem linguagem disciplinar.', rep->>'saude_score', rep->>'saude_cor');
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-074 — serviço combinado abre janela de avaliação de 14 dias, parametrizada
CREATE OR REPLACE FUNCTION public.qa_caso_mky_074()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; l1 uuid; l2 uuid; v_ganho timestamptz; v_msg text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  l1 := (public.marketye_abrir_lead((s->>'a_prof')::uuid, (s->>'a_pub')::uuid, 'Preciso de um serviço fictício de teste.')->>'id')::uuid;
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid); PERFORM public.marketye_lead_mensagem(l1, 'Posso atender.');
  r.passo_ordem := 1; r.passo_acao := 'Empresa marca ganho'; r.esperado := 'ganho_em = agora';
  PERFORM public.qa_mky_claims((s->>'x')::uuid); PERFORM public.marketye_lead_status(l1, 'ganho', NULL);
  SELECT ganho_em INTO v_ganho FROM public.marketplace_leads WHERE id = l1;
  IF v_ganho IS NULL OR abs(EXTRACT(EPOCH FROM (now() - v_ganho))) > 60 THEN falhas := array_append(falhas, 'ganho_em não registrado agora'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Empresa e especialista avaliam'; r.esperado := 'ambas aceitas, em direções opostas';
  BEGIN
    IF (public.marketye_avaliar('lead', l1, '{"pontualidade":5,"clareza":5,"aderencia_escopo":5,"profissionalismo":5}'::jsonb, NULL)->>'direcao') <> 'cliente_para_especialista' THEN falhas := array_append(falhas, 'direção da empresa errada'); END IF;
  EXCEPTION WHEN OTHERS THEN falhas := array_append(falhas, 'empresa não pôde avaliar: ' || SQLERRM); END;
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  BEGIN
    IF (public.marketye_avaliar('lead', l1, '{"clareza":5}'::jsonb, NULL)->>'direcao') <> 'especialista_para_cliente' THEN falhas := array_append(falhas, 'direção do especialista errada'); END IF;
  EXCEPTION WHEN OTHERS THEN falhas := array_append(falhas, 'especialista não pôde avaliar: ' || SQLERRM); END;
  r.passo_ordem := 3; r.passo_acao := 'Segundo lead ganho há 15 dias: avaliar'; r.esperado := 'recusado: O prazo de 14 dias para avaliar já passou.';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  l2 := (public.marketye_abrir_lead((s->>'a_prof')::uuid, (s->>'a_pub')::uuid, 'Segundo serviço fictício de teste.')->>'id')::uuid;
  PERFORM public.marketye_lead_status(l2, 'ganho', NULL);
  UPDATE public.marketplace_leads SET ganho_em = now() - interval '15 days' WHERE id = l2;
  BEGIN PERFORM public.marketye_avaliar('lead', l2, '{"clareza":5}'::jsonb, NULL); v_msg := 'aceitou'; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_msg <> 'O prazo de 14 dias para avaliar já passou.' THEN falhas := array_append(falhas, 'fora da janela: ' || left(v_msg, 60)); END IF;
  r.passo_ordem := 4; r.passo_acao := 'janela_avaliacao_dias = 30 e repetir'; r.esperado := 'aceito';
  PERFORM public.qa_mky_claims((s->>'sa')::uuid); PERFORM public.marketye_config_salvar('janela_avaliacao_dias', '{"dias": 30}'::jsonb, 'teste automatizado', 'BR');
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  BEGIN PERFORM public.marketye_avaliar('lead', l2, '{"clareza":5}'::jsonb, NULL); EXCEPTION WHEN OTHERS THEN falhas := array_append(falhas, 'com janela de 30 dias recusou: ' || SQLERRM); END;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Ganho registra a data; os dois lados avaliam em direções opostas; 15 dias depois a avaliação é recusada com a mensagem do prazo; com a janela em 30 dias volta a aceitar.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-075 — documento da conversa vive no módulo Documentos, vinculado ao lead, só para a empresa dona
CREATE OR REPLACE FUNCTION public.qa_caso_mky_075()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; n int; v_doc uuid; l uuid; d record;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca(); l := (s->>'lead_xb')::uuid;
  INSERT INTO public.user_roles (user_id, role) VALUES ((s->>'x')::uuid, 'manager');  -- quem arquiva documentos na empresa tem papel de gestor
  INSERT INTO public.documentos (tenant_id, colaborador_nome, nome_arquivo, nome_original, tipo, tamanho, mime_type, storage_path, data_validade, criado_por, observacoes)
  VALUES ((s->>'t1')::uuid, 'Proposta MarketYE (teste)', 'proposta-teste.pdf', 'proposta-teste.pdf', 'proposta', 1000, 'application/pdf', (s->>'t1') || '/marketye/proposta-teste.pdf', CURRENT_DATE + 90, (s->>'x')::uuid, 'Origem: MarketYE, conversa ' || l::text)
  RETURNING id INTO v_doc;
  r.passo_ordem := 1; r.passo_acao := 'marketye_lead_vincular_documento(lead, documento, proposta)'; r.esperado := 'linha em marketplace_lead_documentos; mensagem de sistema na conversa';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  PERFORM public.marketye_lead_vincular_documento(l, v_doc, 'proposta');
  SELECT count(*) INTO n FROM public.marketplace_lead_documentos WHERE lead_id = l AND documento_id = v_doc AND tipo = 'proposta'; IF n <> 1 THEN falhas := array_append(falhas, 'vínculo não gravado'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_lead_mensagens WHERE lead_id = l AND autor_tipo = 'sistema' AND texto ILIKE '%Documentos%'; IF n < 1 THEN falhas := array_append(falhas, 'sem mensagem de sistema'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Consultar o documento no módulo Documentos como a empresa'; r.esperado := 'metadados: tipo, versão 1, vigência, vínculo com o lead';
  SET LOCAL ROLE authenticated;
  SELECT * INTO d FROM public.documentos WHERE id = v_doc;
  RESET ROLE;
  IF d.id IS NULL OR d.tipo <> 'proposta' OR d.versao_atual <> 1 OR d.data_validade IS NULL THEN falhas := array_append(falhas, 'empresa não lê o documento com metadados'); END IF;
  SELECT count(*) INTO n FROM public.documento_versoes WHERE documento_id = v_doc; IF n <> 1 THEN falhas := array_append(falhas, format('%s versões (esperado 1)', n)); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Outra empresa consulta o documento e o vínculo'; r.esperado := 'não vê (tenant)';
  PERFORM public.qa_mky_claims((s->>'y')::uuid);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.documentos WHERE id = v_doc; IF n > 0 THEN falhas := array_append(falhas, 'outra empresa lê o documento'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_lead_documentos WHERE documento_id = v_doc; IF n > 0 THEN falhas := array_append(falhas, 'outra empresa lê o vínculo'); END IF;
  RESET ROLE;
  PERFORM public.qa_mky_claims((s->>'b_uid')::uuid);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.marketplace_lead_documentos WHERE documento_id = v_doc; IF n <> 1 THEN falhas := array_append(falhas, 'o especialista da conversa não vê o vínculo'); END IF;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'O vínculo entra com tipo proposta e mensagem de sistema; a empresa lê o documento com tipo, versão 1 e vigência; outra empresa não vê documento nem vínculo; o especialista da conversa vê o vínculo.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN RESET ROLE; PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-077 — cupom na conversa: só o válido é aplicado, fica registrado e consome uso
CREATE OR REPLACE FUNCTION public.qa_caso_mky_077()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; n int; l1 uuid; l2 uuid; l3 uuid; v_cod text; v_usos int;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  UPDATE public.marketplace_cupons SET ativo = false WHERE profissional_id = (s->>'b_prof')::uuid;
  PERFORM public.qa_mky_claims((s->>'b_uid')::uuid);
  PERFORM public.marketye_cupom_salvar(jsonb_build_object('codigo', 'VENCIDO', 'desconto_percentual', 30, 'validade', CURRENT_DATE - 1));
  r.passo_ordem := 1; r.passo_acao := 'Só existe cupom vencido: empresa abre conversa'; r.esperado := 'conversa sem cupom';
  PERFORM public.qa_mky_claims((s->>'y')::uuid);
  l1 := (public.marketye_abrir_lead((s->>'b_prof')::uuid, (s->>'b_pub')::uuid, 'Conversa fictícia de teste sem cupom válido.')->>'id')::uuid;
  SELECT cupom_codigo INTO v_cod FROM public.marketplace_leads WHERE id = l1; IF v_cod IS NOT NULL THEN falhas := array_append(falhas, 'cupom vencido aplicado: ' || v_cod); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Cupom válido com limite 1: outra empresa abre conversa'; r.esperado := 'lead.cupom_codigo preenchido; usos = 1; mensagem de sistema';
  PERFORM public.qa_mky_claims((s->>'b_uid')::uuid);
  PERFORM public.marketye_cupom_salvar(jsonb_build_object('codigo', 'PROMO1', 'desconto_percentual', 15, 'validade', CURRENT_DATE + 10, 'limite_uso', 1));
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  PERFORM public.marketye_lead_status((s->>'lead_xb')::uuid, 'perdido', NULL);
  l2 := (public.marketye_abrir_lead((s->>'b_prof')::uuid, (s->>'b_pub')::uuid, 'Conversa fictícia de teste com cupom.')->>'id')::uuid;
  SELECT cupom_codigo INTO v_cod FROM public.marketplace_leads WHERE id = l2;
  SELECT usos INTO v_usos FROM public.marketplace_cupons WHERE profissional_id = (s->>'b_prof')::uuid AND codigo = 'PROMO1';
  SELECT count(*) INTO n FROM public.marketplace_lead_mensagens WHERE lead_id = l2 AND autor_tipo = 'sistema' AND texto ILIKE '%PROMO1%';
  IF v_cod IS DISTINCT FROM 'PROMO1' OR v_usos <> 1 OR n <> 1 THEN falhas := array_append(falhas, format('cupom válido: código %s, usos %s, mensagens %s', COALESCE(v_cod, 'nulo'), v_usos, n)); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Terceira conversa nova com o cupom esgotado'; r.esperado := 'sem cupom; usos continua 1';
  PERFORM public.qa_mky_claims((s->>'y')::uuid);
  PERFORM public.marketye_lead_status(l1, 'perdido', NULL);
  l3 := (public.marketye_abrir_lead((s->>'b_prof')::uuid, (s->>'b_pub')::uuid, 'Conversa fictícia de teste após o limite.')->>'id')::uuid;
  SELECT cupom_codigo INTO v_cod FROM public.marketplace_leads WHERE id = l3;
  SELECT usos INTO v_usos FROM public.marketplace_cupons WHERE profissional_id = (s->>'b_prof')::uuid AND codigo = 'PROMO1';
  IF v_cod IS NOT NULL OR v_usos <> 1 THEN falhas := array_append(falhas, format('após o limite: código %s, usos %s', v_cod, v_usos)); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Cupom vencido nunca entra na conversa; o válido fica registrado no lead, consome um uso e avisa na conversa; esgotado o limite, a conversa seguinte abre sem cupom.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ===== Família F — avaliação e reputação (MKY-080..088) =====
-- MKY-080 — fora da janela é recusada com a mensagem do prazo
CREATE OR REPLACE FUNCTION public.qa_caso_mky_080()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; l uuid; v_msg text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  l := (public.marketye_abrir_lead((s->>'a_prof')::uuid, (s->>'a_pub')::uuid, 'Serviço fictício de teste combinado há 20 dias.')->>'id')::uuid;
  PERFORM public.marketye_lead_status(l, 'ganho', NULL);
  UPDATE public.marketplace_leads SET ganho_em = now() - interval '20 days' WHERE id = l;
  r.passo_ordem := 1; r.passo_acao := 'Avaliar lead ganho há 20 dias'; r.esperado := 'recusado com "O prazo de 14 dias para avaliar já passou."';
  BEGIN PERFORM public.marketye_avaliar('lead', l, '{"clareza":5}'::jsonb, NULL); v_msg := 'aceitou'; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_msg <> 'O prazo de 14 dias para avaliar já passou.' THEN falhas := array_append(falhas, left(v_msg, 80)); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Avaliação 20 dias depois do combinado é recusada com a mensagem do prazo de 14 dias.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-081 — quarta avaliação do mesmo par em 30 dias é recusada
CREATE OR REPLACE FUNCTION public.qa_caso_mky_081()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; l uuid; v_msg text; i int;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  FOR i IN 1..3 LOOP
    l := (public.marketye_abrir_lead((s->>'a_prof')::uuid, (s->>'a_pub')::uuid, format('Serviço fictício de teste número %s.', i))->>'id')::uuid;
    PERFORM public.marketye_lead_status(l, 'ganho', NULL);
    PERFORM public.marketye_avaliar('lead', l, '{"clareza":5}'::jsonb, NULL);
  END LOOP;
  r.passo_ordem := 1; r.passo_acao := 'Quarto lead ganho e avaliação'; r.esperado := 'recusado: limite por par';
  l := (public.marketye_abrir_lead((s->>'a_prof')::uuid, (s->>'a_pub')::uuid, 'Serviço fictício de teste número 4.')->>'id')::uuid;
  PERFORM public.marketye_lead_status(l, 'ganho', NULL);
  BEGIN PERFORM public.marketye_avaliar('lead', l, '{"clareza":5}'::jsonb, NULL); v_msg := 'aceitou'; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_msg NOT ILIKE '%Limite de avaliações%' THEN falhas := array_append(falhas, 'quarta avaliação: ' || left(v_msg, 60)); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Ajustar as três para 40 dias atrás e repetir'; r.esperado := 'aceito';
  UPDATE public.marketplace_avaliacoes SET created_at = now() - interval '40 days' WHERE profissional_id = (s->>'a_prof')::uuid AND tenant_id = (s->>'t1')::uuid AND direcao = 'cliente_para_especialista';
  BEGIN PERFORM public.marketye_avaliar('lead', l, '{"clareza":5}'::jsonb, NULL); EXCEPTION WHEN OTHERS THEN falhas := array_append(falhas, 'fora da janela de 30 dias ainda recusou: ' || SQLERRM); END;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Três avaliações do par empresa × especialista passam; a quarta em 30 dias é recusada; com as três fora da janela, aceita.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-082 — autocompra: especialista que é usuário de empresa não avalia a si mesmo nem conta como cliente próprio
CREATE OR REPLACE FUNCTION public.qa_caso_mky_082()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v_prof uuid; v_an uuid; l uuid; v_msg text; rep jsonb; v_lead_ok boolean := false; v_aval_ok boolean := false;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  v_prof := (public.marketye_cadastrar_especialista(jsonb_build_object('nome_completo', 'QA Especialista 082 X', 'email', 'qa-mky-082x@sandbox.invalid', 'cpf_cnpj', '900.000.034-33', 'aceite_termos', true, 'conselho', 'CREA', 'registro_profissional', 'QA-082'))->>'id')::uuid;
  PERFORM public.qa_mky_claims((s->>'sa')::uuid); PERFORM public.marketye_moderar_especialista(v_prof, 'aprovado', NULL, true);
  v_an := public.qa_mky_anuncio_publicado((s->>'x')::uuid, 'QA Autocompra 082', 'seguranca-trabalho', 'online', 'sob_orcamento', NULL);
  r.passo_ordem := 1; r.passo_acao := 'X (empresa A) abre conversa com o próprio anúncio, marca ganho e avalia'; r.esperado := 'recusado em algum ponto';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  BEGIN l := (public.marketye_abrir_lead(v_prof, v_an, 'Abrindo conversa comigo mesmo (teste).')->>'id')::uuid; v_lead_ok := true; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_lead_ok THEN
    BEGIN PERFORM public.marketye_lead_status(l, 'ganho', NULL); EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN PERFORM public.marketye_avaliar('lead', l, '{"pontualidade":5,"clareza":5}'::jsonb, 'Autoavaliação de teste.'); v_aval_ok := true; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  END IF;
  IF v_lead_ok AND v_aval_ok THEN falhas := array_append(falhas, 'conversa consigo mesmo aberta, ganha e avaliada sem recusa'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Se o lead passou, recalcular reputação'; r.esperado := 'clientes_unicos não conta a própria empresa';
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF v_lead_ok THEN
    rep := public.marketye_recalcular_reputacao(v_prof);
    IF COALESCE((rep->>'clientes_unicos_total')::int, 0) > 0 OR COALESCE((rep->>'servicos_concluidos_total')::int, 0) > 0 THEN falhas := array_append(falhas, format('a própria empresa contou como cliente (clientes %s, serviços %s)', rep->>'clientes_unicos_total', rep->>'servicos_concluidos_total')); END IF;
  END IF;
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Autocompra bloqueada (' || COALESCE(left(v_msg, 60), 'recusa') || ') e a própria empresa não conta na reputação.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-083 — saúde recente: janela de 90 dias parametrizada; cores pelos limiares
CREATE OR REPLACE FUNCTION public.qa_caso_mky_083()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; rep jsonb; a100 uuid; a60 uuid; a10 uuid; v_nota numeric; p uuid;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca(); p := (s->>'a_prof')::uuid;
  DELETE FROM public.marketplace_avaliacoes WHERE profissional_id = p;
  INSERT INTO public.marketplace_avaliacoes (profissional_id, avaliador_id, tenant_id, direcao, criterios, nota_geral, created_at) VALUES (p, (s->>'x')::uuid, (s->>'t1')::uuid, 'cliente_para_especialista', '{}'::jsonb, 1, now() - interval '100 days') RETURNING id INTO a100;
  INSERT INTO public.marketplace_avaliacoes (profissional_id, avaliador_id, tenant_id, direcao, criterios, nota_geral, created_at) VALUES (p, (s->>'x')::uuid, (s->>'t1')::uuid, 'cliente_para_especialista', '{}'::jsonb, 5, now() - interval '60 days') RETURNING id INTO a60;
  INSERT INTO public.marketplace_avaliacoes (profissional_id, avaliador_id, tenant_id, direcao, criterios, nota_geral, created_at) VALUES (p, (s->>'x')::uuid, (s->>'t1')::uuid, 'cliente_para_especialista', '{}'::jsonb, 5, now() - interval '10 days') RETURNING id INTO a10;
  r.passo_ordem := 1; r.passo_acao := 'Recalcular'; r.esperado := 'saúde usa só as de 60 e 10 dias; nota_media usa todas';
  rep := public.marketye_recalcular_reputacao(p);
  SELECT nota_media INTO v_nota FROM public.marketplace_profissionais WHERE id = p;
  IF (rep->>'avaliacoes_90d')::int <> 2 OR (rep->>'media_90d')::numeric <> 5 THEN falhas := array_append(falhas, format('janela: %s avaliações, média %s', rep->>'avaliacoes_90d', rep->>'media_90d')); END IF;
  IF v_nota <> 3.67 THEN falhas := array_append(falhas, format('nota_media %s (esperado 3.67 com as três)', v_nota)); END IF;
  IF (rep->>'saude_score')::numeric <> 95 OR rep->>'saude_cor' <> 'verde' THEN falhas := array_append(falhas, format('saúde %s/%s (esperado 95 verde)', rep->>'saude_score', rep->>'saude_cor')); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Score 80'; r.esperado := 'verde';
  UPDATE public.marketplace_avaliacoes SET nota_geral = 2 WHERE id = a60; rep := public.marketye_recalcular_reputacao(p);
  IF (rep->>'saude_score')::numeric <> 80 OR rep->>'saude_cor' <> 'verde' THEN falhas := array_append(falhas, format('80: %s/%s', rep->>'saude_score', rep->>'saude_cor')); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Score 60'; r.esperado := 'amarelo';
  UPDATE public.marketplace_avaliacoes SET nota_geral = 1 WHERE id = a60; UPDATE public.marketplace_avaliacoes SET nota_geral = 2 WHERE id = a10; rep := public.marketye_recalcular_reputacao(p);
  IF (rep->>'saude_score')::numeric <> 60 OR rep->>'saude_cor' <> 'amarelo' THEN falhas := array_append(falhas, format('60: %s/%s', rep->>'saude_score', rep->>'saude_cor')); END IF;
  r.passo_ordem := 4; r.passo_acao := 'Score 40 (duas ocorrências com reflexo)'; r.esperado := 'vermelho';
  INSERT INTO public.marketplace_ocorrencias (profissional_id, tipo, descricao, reflexo_visibilidade) VALUES (p, 'ocorrencia', 'Ocorrência fictícia 1', true), (p, 'ocorrencia', 'Ocorrência fictícia 2', true);
  rep := public.marketye_recalcular_reputacao(p);
  IF (rep->>'saude_score')::numeric <> 40 OR rep->>'saude_cor' <> 'vermelho' THEN falhas := array_append(falhas, format('40: %s/%s', rep->>'saude_score', rep->>'saude_cor')); END IF;
  r.passo_ordem := 5; r.passo_acao := 'saude_recente.janela_dias = 120'; r.esperado := 'a de 100 dias entra';
  PERFORM public.qa_mky_claims((s->>'sa')::uuid); PERFORM public.marketye_config_salvar('saude_recente', '{"verde": 75, "amarelo": 50, "janela_dias": 120}'::jsonb, 'teste automatizado', 'BR');
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  rep := public.marketye_recalcular_reputacao(p);
  IF (rep->>'avaliacoes_90d')::int <> 3 THEN falhas := array_append(falhas, format('janela de 120 dias: %s avaliações (esperado 3)', rep->>'avaliacoes_90d')); END IF;
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Saúde usa só as avaliações da janela (2 de 3) e a nota geral usa todas; 95/80 verde, 60 amarelo, 40 vermelho com ocorrências; janela de 120 dias na configuração inclui a de 100 dias.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-084 — piso de nota só com o mínimo de avaliações; score reduzido a 25%
CREATE OR REPLACE FUNCTION public.qa_caso_mky_084()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; rep jsonb; p uuid; x jsonb; s_baixo numeric; s_normal numeric;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca(); p := (s->>'a_prof')::uuid;
  DELETE FROM public.marketplace_avaliacoes WHERE profissional_id = p;
  r.passo_ordem := 1; r.passo_acao := 'Duas avaliações nota 2 e recalcular'; r.esperado := 'abaixo_piso = false';
  INSERT INTO public.marketplace_avaliacoes (profissional_id, avaliador_id, tenant_id, direcao, criterios, nota_geral) SELECT p, (s->>'x')::uuid, (s->>'t1')::uuid, 'cliente_para_especialista', '{}'::jsonb, 2 FROM generate_series(1, 2);
  rep := public.marketye_recalcular_reputacao(p);
  IF (rep->>'abaixo_piso')::boolean THEN falhas := array_append(falhas, 'com 2 avaliações já rebaixou'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Terceira nota 2'; r.esperado := 'abaixo_piso = true; busca com score reduzido a 25%';
  INSERT INTO public.marketplace_avaliacoes (profissional_id, avaliador_id, tenant_id, direcao, criterios, nota_geral) VALUES (p, (s->>'x')::uuid, (s->>'t1')::uuid, 'cliente_para_especialista', '{}'::jsonb, 2);
  rep := public.marketye_recalcular_reputacao(p);
  IF NOT (rep->>'abaixo_piso')::boolean THEN falhas := array_append(falhas, 'com 3 avaliações nota 2 não rebaixou'); END IF;
  SELECT y INTO x FROM public.marketye_buscar_interno('{"q": "QA Seguranca A publicado"}'::jsonb) y WHERE y->>'servico_id' = s->>'a_pub';
  s_baixo := (x->>'score')::numeric;
  IF (x->>'abaixo_piso')::boolean IS DISTINCT FROM true THEN falhas := array_append(falhas, 'busca não marca abaixo do piso'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'piso_nota.minimo_avaliacoes = 5'; r.esperado := 'abaixo_piso volta a false; score volta ao cheio (o reduzido era 25% dele)';
  PERFORM public.qa_mky_claims((s->>'sa')::uuid); PERFORM public.marketye_config_salvar('piso_nota', '{"nota": 3.5, "minimo_avaliacoes": 5}'::jsonb, 'teste automatizado', 'BR');
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  rep := public.marketye_recalcular_reputacao(p);
  IF (rep->>'abaixo_piso')::boolean THEN falhas := array_append(falhas, 'com mínimo 5 continua abaixo do piso'); END IF;
  SELECT y INTO x FROM public.marketye_buscar_interno('{"q": "QA Seguranca A publicado"}'::jsonb) y WHERE y->>'servico_id' = s->>'a_pub';
  s_normal := (x->>'score')::numeric;
  IF abs(s_baixo - s_normal * 0.25) > 0.01 THEN falhas := array_append(falhas, format('score abaixo do piso %s não é 25%% do cheio %s', s_baixo, s_normal)); END IF;
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := format('Duas notas 2 não rebaixam; a terceira rebaixa e a busca reduz o score a 25%% (%s de %s); subir o mínimo para 5 na configuração desfaz.', s_baixo, s_normal);
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-085 — subir de nível exige todas as métricas ao mesmo tempo
CREATE OR REPLACE FUNCTION public.qa_caso_mky_085()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; rep jsonb; p uuid; v_oc uuid;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca(); p := (s->>'a_prof')::uuid;
  DELETE FROM public.marketplace_avaliacoes WHERE profissional_id = p; DELETE FROM public.marketplace_leads WHERE profissional_id = p;
  -- 30 conversas ganhas e avaliadas nota 5, todas da mesma empresa (mobiliário direto: o limite de 3 avaliações por par impede fazer isso pela função).
  WITH l AS (
    INSERT INTO public.marketplace_leads (tenant_id, profissional_id, servico_id, criado_por, status, ganho_em, created_at, primeira_resposta_em)
    SELECT (s->>'t1')::uuid, p, (s->>'a_pub')::uuid, (s->>'x')::uuid, 'ganho', now() - interval '1 day', now() - interval '2 days', now() - interval '2 days' + interval '1 hour' FROM generate_series(1, 30) RETURNING id)
  INSERT INTO public.marketplace_avaliacoes (lead_id, profissional_id, avaliador_id, tenant_id, direcao, criterios, nota_geral) SELECT id, p, (s->>'x')::uuid, (s->>'t1')::uuid, 'cliente_para_especialista', '{}'::jsonb, 5 FROM l;
  r.passo_ordem := 1; r.passo_acao := 'Recalcular'; r.esperado := 'nível continua novo: clientes únicos abaixo do exigido';
  rep := public.marketye_recalcular_reputacao(p);
  IF rep->>'nivel' <> 'novo' OR (rep->>'servicos_concluidos_total')::int <> 30 OR (rep->>'clientes_unicos_total')::int <> 1 THEN falhas := array_append(falhas, format('nível %s com %s serviços e %s clientes', rep->>'nivel', rep->>'servicos_concluidos_total', rep->>'clientes_unicos_total')); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Segunda empresa ganha + uma ocorrência com reflexo; recalcular'; r.esperado := 'não sobe (ocorrências = 0 exigido)';
  INSERT INTO public.marketplace_leads (tenant_id, profissional_id, servico_id, criado_por, status, ganho_em, created_at, primeira_resposta_em)
  VALUES ((s->>'t2')::uuid, p, (s->>'a_pub')::uuid, (s->>'y')::uuid, 'ganho', now() - interval '1 day', now() - interval '2 days', now() - interval '2 days' + interval '1 hour');
  INSERT INTO public.marketplace_ocorrencias (profissional_id, tipo, descricao, reflexo_visibilidade) VALUES (p, 'ocorrencia', 'Ocorrência fictícia de teste', true) RETURNING id INTO v_oc;
  rep := public.marketye_recalcular_reputacao(p);
  IF rep->>'nivel' <> 'novo' THEN falhas := array_append(falhas, 'subiu para ' || (rep->>'nivel') || ' com ocorrência aberta'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Ocorrência sem reflexo; recalcular'; r.esperado := 'sobe para bronze (30+ serviços, 2 clientes, média 5, resposta 100%)';
  UPDATE public.marketplace_ocorrencias SET reflexo_visibilidade = false WHERE id = v_oc;
  rep := public.marketye_recalcular_reputacao(p);
  IF rep->>'nivel' <> 'bronze' THEN falhas := array_append(falhas, format('nível %s (esperado bronze; clientes %s, taxa %s, ocorrências %s)', rep->>'nivel', rep->>'clientes_unicos_total', rep->>'taxa_resposta_90d', rep->>'ocorrencias_90d')); END IF;
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := '30 serviços com uma só empresa não dão bronze; com a segunda empresa mas uma ocorrência aberta também não; só com todas as métricas ao mesmo tempo sobe para bronze (e para em bronze).';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-086 — direito de resposta: uma resposta, mascarada, visível na vitrine
CREATE OR REPLACE FUNCTION public.qa_caso_mky_086()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; a record; n int; v_resp text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  r.passo_ordem := 1; r.passo_acao := 'marketye_avaliacao_responder(id, "Obrigado! Me chame no 46 99999-0000")'; r.esperado := 'resposta gravada mascarada; respondido_em preenchido';
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  PERFORM public.marketye_avaliacao_responder((s->>'aval_a')::uuid, 'Obrigado! Me chame no 46 99999-0000 para combinar.');
  SELECT * INTO a FROM public.marketplace_avaliacoes WHERE id = (s->>'aval_a')::uuid;
  IF a.resposta IS NULL OR a.respondido_em IS NULL OR a.resposta ~ '\d{4,5}[\s.-]?\d{4}' THEN falhas := array_append(falhas, 'resposta sem máscara ou sem data: ' || COALESCE(a.resposta, 'nula')); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Responder de novo'; r.esperado := 'sobrescreve ou recusa, nunca duplica';
  BEGIN PERFORM public.marketye_avaliacao_responder((s->>'aval_a')::uuid, 'Segunda resposta de teste, sem contato.'); EXCEPTION WHEN OTHERS THEN NULL; END;
  SELECT count(*) INTO n FROM public.marketplace_avaliacoes WHERE lead_id = (s->>'lead_ya')::uuid AND direcao = 'cliente_para_especialista'; IF n <> 1 THEN falhas := array_append(falhas, 'avaliação duplicada'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Empresa lê as avaliações do especialista'; r.esperado := 'avaliação com a resposta visível';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  SET LOCAL ROLE authenticated;
  SELECT resposta INTO v_resp FROM public.marketplace_avaliacoes WHERE id = (s->>'aval_a')::uuid;
  RESET ROLE;
  IF v_resp IS NULL THEN falhas := array_append(falhas, 'resposta não visível para a empresa'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'A resposta entra mascarada (' || left(a.resposta, 50) || '…) com data; responder de novo sobrescreve sem duplicar; a empresa vê a avaliação com a resposta.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN RESET ROLE; PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-087 — avaliação moderada sai do portal, do cálculo e da vitrine
CREATE OR REPLACE FUNCTION public.qa_caso_mky_087()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v_ct uuid; n int; v_portal jsonb; p record; v_mod boolean;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  r.passo_ordem := 1; r.passo_acao := 'Especialista contesta a avaliação; superadmin defere (moderada = true)'; r.esperado := 'some do portal e da leitura pública';
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  v_ct := (public.marketye_contestar('avaliacao', (s->>'aval_a')::uuid, 'Comentário ofensivo e sem relação com o serviço prestado (teste).', '[]'::jsonb)->>'id')::uuid;
  PERFORM public.qa_mky_claims((s->>'sa')::uuid);
  PERFORM public.marketye_contestacao_decidir(v_ct, 'deferida', 'Avaliação moderada por conteúdo ofensivo (teste).');
  SELECT moderada INTO v_mod FROM public.marketplace_avaliacoes WHERE id = (s->>'aval_a')::uuid; IF NOT COALESCE(v_mod, false) THEN falhas := array_append(falhas, 'avaliação não marcada como moderada'); END IF;
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  v_portal := public.marketye_meu_portal();
  IF v_portal->'avaliacoes' @> jsonb_build_array(jsonb_build_object('id', (s->>'aval_a')::uuid)) THEN falhas := array_append(falhas, 'portal ainda mostra a avaliação moderada'); END IF;
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.marketplace_avaliacoes WHERE id = (s->>'aval_a')::uuid AND NOT moderada;
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.marketplace_avaliacoes WHERE id = (s->>'aval_a')::uuid;
  RESET ROLE;
  IF n > 0 THEN falhas := array_append(falhas, 'avaliação moderada continua legível na tabela pública (o card a mostra)'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Recalcular'; r.esperado := 'nota_media e total_avaliacoes sem ela';
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  PERFORM public.marketye_recalcular_reputacao((s->>'a_prof')::uuid);
  SELECT * INTO p FROM public.marketplace_profissionais WHERE id = (s->>'a_prof')::uuid;
  IF p.total_avaliacoes <> 0 OR p.nota_media <> 0 THEN falhas := array_append(falhas, format('cálculo ainda conta a moderada (total %s, média %s)', p.total_avaliacoes, p.nota_media)); END IF;
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Contestação deferida marca a avaliação como moderada; ela some do portal e da leitura pública e sai da nota e do total.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN RESET ROLE; PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-088 — reputação da empresa chega ao especialista sem expor quem avaliou
CREATE OR REPLACE FUNCTION public.qa_caso_mky_088()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; l uuid; z record; v_portal jsonb; e jsonb; v_txt text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  -- A e B avaliam a empresa X (t1).
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  l := (public.marketye_abrir_lead((s->>'a_prof')::uuid, (s->>'a_pub')::uuid, 'Serviço fictício de teste com A.')->>'id')::uuid; PERFORM public.marketye_lead_status(l, 'ganho', NULL);
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid); PERFORM public.marketye_avaliar('lead', l, '{"clareza":4}'::jsonb, 'Empresa organizada (teste).');
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  PERFORM public.marketye_lead_status((s->>'lead_xb')::uuid, 'ganho', NULL);
  PERFORM public.qa_mky_claims((s->>'b_uid')::uuid); PERFORM public.marketye_avaliar('lead', (s->>'lead_xb')::uuid, '{"clareza":5}'::jsonb, NULL);
  SELECT * INTO z FROM public.qa_mky_especialista('088z', '900.000.034-33');
  PERFORM public.qa_mky_claims((s->>'sa')::uuid); PERFORM public.marketye_moderar_especialista(z.prof_id, 'aprovado', NULL, true);
  r.passo_ordem := 1; r.passo_acao := 'Especialista Z recebe conversa de X e abre o portal'; r.esperado := 'leads[].reputacao_empresa com média 4.5 e total 2';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  l := (public.marketye_abrir_lead(z.prof_id, NULL, 'Serviço fictício de teste com Z.')->>'id')::uuid;
  PERFORM public.qa_mky_claims(z.uid);
  v_portal := public.marketye_meu_portal();
  SELECT x INTO e FROM jsonb_array_elements(v_portal->'leads') x WHERE x->>'id' = l::text;
  IF e IS NULL OR (e->'reputacao_empresa'->>'media')::numeric <> 4.5 OR (e->'reputacao_empresa'->>'total')::int <> 2 THEN falhas := array_append(falhas, 'reputação da empresa ausente ou errada: ' || COALESCE((e->'reputacao_empresa')::text, 'nula')); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Inspecionar o payload'; r.esperado := 'sem avaliador_id, e-mail ou nome de quem avaliou';
  v_txt := (v_portal->'leads')::text;
  IF v_txt LIKE '%' || (s->>'a_uid') || '%' OR v_txt LIKE '%' || (s->>'b_uid') || '%' OR v_txt LIKE '%' || (s->>'a_prof') || '%' OR v_txt LIKE '%' || (s->>'b_prof') || '%' OR v_txt LIKE '%@%' OR v_txt ILIKE '%avaliador%' OR v_txt ILIKE '%QA Especialista 110%' THEN falhas := array_append(falhas, 'payload identifica quem avaliou'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'O portal de Z mostra a reputação da empresa (média 4.5, 2 avaliações) sem id, e-mail ou nome de quem avaliou.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ===== Família G — LGPD e privacidade (MKY-090..096) =====
-- MKY-090 — exportar meus dados: tudo o que é meu, nada de terceiros
CREATE OR REPLACE FUNCTION public.qa_caso_mky_090()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v jsonb; v_txt text; k text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  r.passo_ordem := 1; r.passo_acao := 'marketye_exportar_meus_dados() como A'; r.esperado := 'perfil, consentimentos, anúncios, cupons, leads (sem contato da empresa além do nome), avaliações, contestações, autonomia';
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  v := public.marketye_exportar_meus_dados(); v_txt := v::text;
  IF v->'perfil'->>'id' <> s->>'a_prof' THEN falhas := array_append(falhas, 'perfil errado ou ausente'); END IF;
  FOREACH k IN ARRAY ARRAY['consentimentos', 'anuncios', 'leads', 'avaliacoes', 'contestacoes', 'autonomia', 'cupons'] LOOP
    IF NOT (v ? k) THEN falhas := array_append(falhas, 'exportação não inclui ' || k); END IF;
  END LOOP;
  IF jsonb_array_length(COALESCE(v->'consentimentos', '[]'::jsonb)) < 3 OR jsonb_array_length(COALESCE(v->'anuncios', '[]'::jsonb)) < 1 OR jsonb_array_length(COALESCE(v->'leads', '[]'::jsonb)) < 1 OR jsonb_array_length(COALESCE(v->'avaliacoes', '[]'::jsonb)) < 1 THEN falhas := array_append(falhas, 'blocos vazios onde há dado'); END IF;
  IF v_txt ILIKE '%criado_por%' OR v_txt ILIKE '%avaliador_id%' OR v->'perfil' ? 'user_id' THEN falhas := array_append(falhas, 'expõe id de pessoa (criado_por/avaliador_id/user_id)'); END IF;
  IF v_txt LIKE '%' || (s->>'b_prof') || '%' OR v_txt LIKE '%qa-mky-110y%' OR v_txt LIKE '%qa-mky-esp-110b%' THEN falhas := array_append(falhas, 'contém dado de terceiro'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Outro especialista chama'; r.esperado := 'recebe só os próprios dados';
  PERFORM public.qa_mky_claims((s->>'b_uid')::uuid);
  v := public.marketye_exportar_meus_dados();
  IF v->'perfil'->>'id' <> s->>'b_prof' OR v::text LIKE '%' || (s->>'a_prof') || '%' THEN falhas := array_append(falhas, 'B recebe dado de A'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Usuário de empresa chama'; r.esperado := 'vazio (perfil nulo), nada de terceiros';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  v := public.marketye_exportar_meus_dados();
  IF v->'perfil' IS NOT NULL AND v->'perfil' <> 'null'::jsonb THEN falhas := array_append(falhas, 'empresa recebe perfil de alguém'); END IF;
  IF v::text LIKE '%' || (s->>'a_prof') || '%' OR v::text LIKE '%' || (s->>'b_prof') || '%' THEN falhas := array_append(falhas, 'empresa recebe dado de especialista'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'A exportação traz perfil, consentimentos, anúncios, cupons, leads, avaliações, contestações e autonomia do próprio especialista, sem ids de pessoas nem dado de terceiros; empresa recebe vazio.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-092 — exclusão com conversa aberta: encerra o lead para a empresa e mantém o registro
CREATE OR REPLACE FUNCTION public.qa_caso_mky_092()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; l uuid; v_st text; n int; v_c jsonb;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca(); l := (s->>'lead_xb')::uuid;
  PERFORM public.qa_mky_claims((s->>'x')::uuid); PERFORM public.marketye_lead_liberar_contato(l);
  r.passo_ordem := 1; r.passo_acao := 'Especialista B exclui o perfil com a conversa aberta'; r.esperado := 'aceito; lead encerrado com mensagem de sistema de que o especialista deixou o MarketYE';
  PERFORM public.qa_mky_claims((s->>'b_uid')::uuid); PERFORM public.marketye_excluir_meu_perfil('EXCLUIR');
  SELECT status INTO v_st FROM public.marketplace_leads WHERE id = l;
  SELECT count(*) INTO n FROM public.marketplace_lead_mensagens WHERE lead_id = l AND autor_tipo = 'sistema' AND (texto ILIKE '%deixou%' OR texto ILIKE '%saiu%' OR texto ILIKE '%excluiu%');
  IF v_st NOT IN ('encerrado', 'perdido') OR n = 0 THEN falhas := array_append(falhas, format('lead segue "%s" e sem aviso de sistema após a exclusão', v_st)); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Empresa abre Minhas conversas'; r.esperado := 'vê a conversa sem erro; os dados de contato do especialista já não aparecem (anonimizados)';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.marketplace_leads WHERE id = l;
  RESET ROLE;
  IF n <> 1 THEN falhas := array_append(falhas, 'empresa perdeu a conversa'); END IF;
  v_c := public.marketye_lead_contato(l);
  IF v_c->>'email' IS NOT NULL AND v_c->>'email' NOT LIKE 'removido+%' THEN falhas := array_append(falhas, 'e-mail do especialista excluído ainda aparece'); END IF;
  IF v_c->>'telefone' IS NOT NULL THEN falhas := array_append(falhas, 'telefone do especialista excluído ainda aparece'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'A exclusão encerra a conversa com aviso de sistema; a empresa continua vendo a conversa, já sem e-mail nem telefone do especialista.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN RESET ROLE; PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-093 — nova versão dos termos exige novo aceite antes de publicar; histórico preservado
CREATE OR REPLACE FUNCTION public.qa_caso_mky_093()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v_versoes jsonb; v_portal jsonb; v_an uuid; v_msg text; n int; v_cat uuid;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  SELECT id INTO v_cat FROM public.marketplace_categorias WHERE slug = 'seguranca-trabalho';
  r.passo_ordem := 1; r.passo_acao := 'Superadmin muda termos_versoes.termos_especialista para 2026-10-v1'; r.esperado := 'portal lista termos_pendentes com a nova versão';
  v_versoes := public.marketye_config('termos_versoes') || '{"termos_especialista": "2026-10-v1"}'::jsonb;
  PERFORM public.qa_mky_claims((s->>'sa')::uuid); PERFORM public.marketye_config_salvar('termos_versoes', v_versoes, 'teste automatizado', 'BR');
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  v_portal := public.marketye_meu_portal();
  IF NOT (v_portal->'termos_pendentes' @> '[{"tipo": "termos_especialista", "versao": "2026-10-v1"}]'::jsonb) THEN falhas := array_append(falhas, 'portal não lista o termo pendente'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Publicar anúncio sem aceitar'; r.esperado := 'recusado com aviso de termos pendentes';
  v_an := (public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Termos 093', 'descricao', 'Serviço fictício de teste do MarketYE para termos.', 'categoria_id', v_cat, 'modalidade', 'online', 'tipo_preco', 'sob_orcamento'))->>'id')::uuid;
  BEGIN PERFORM public.marketye_anuncio_publicar(v_an); v_msg := 'publicou'; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_msg = 'publicou' THEN falhas := array_append(falhas, 'publicou com termos pendentes'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'marketye_aceitar_termos(nova versão)'; r.esperado := 'nova linha de consentimento; a antiga permanece; publicar funciona';
  PERFORM public.marketye_aceitar_termos('termos_especialista', '2026-10-v1', 'QA/1.0');
  SELECT count(*) INTO n FROM public.marketplace_consentimentos WHERE profissional_id = (s->>'a_prof')::uuid AND tipo = 'termos_especialista'; IF n <> 2 THEN falhas := array_append(falhas, format('%s consentimentos de termos (esperado 2: antigo + novo)', n)); END IF;
  v_portal := public.marketye_meu_portal();
  IF jsonb_array_length(COALESCE(v_portal->'termos_pendentes', '[]'::jsonb)) <> 0 THEN falhas := array_append(falhas, 'termo continua pendente após o aceite'); END IF;
  PERFORM public.marketye_anuncio_status(v_an, 'rascunho');
  BEGIN PERFORM public.marketye_anuncio_publicar(v_an); EXCEPTION WHEN OTHERS THEN falhas := array_append(falhas, 'após o aceite não publica: ' || SQLERRM); END;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Versão nova aparece como pendente no portal; publicar fica travado até o aceite; o aceite grava linha nova mantendo a antiga e libera a publicação.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-094 — minimização: visitante e funções públicas nunca recebem contato, documento ou ids
CREATE OR REPLACE FUNCTION public.qa_caso_mky_094()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v_msg text; n int; v jsonb; v_txt text; k text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  r.passo_ordem := 1; r.passo_acao := 'SELECT em marketplace_profissionais como anon e como authenticated'; r.esperado := 'colunas sensíveis recusadas para o papel; colunas públicas e SELECT * só sem as sensíveis';
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  SET LOCAL ROLE anon;
  FOREACH k IN ARRAY ARRAY['email', 'telefone', 'cpf_cnpj', 'user_id', 'tenant_id'] LOOP
    BEGIN EXECUTE format('SELECT count(*) FROM public.marketplace_profissionais WHERE %I IS NOT NULL', k) INTO n; falhas := array_append(falhas, 'anon lê a coluna ' || k); EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  END LOOP;
  BEGIN SELECT count(*) INTO n FROM (SELECT * FROM public.marketplace_profissionais) z; falhas := array_append(falhas, 'anon faz SELECT * (todas as colunas)'); EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN SELECT count(*) INTO n FROM public.marketplace_profissionais WHERE id = (s->>'a_prof')::uuid; IF n <> 1 THEN falhas := array_append(falhas, 'controle: anon não lê colunas públicas do especialista ativo'); END IF; EXCEPTION WHEN insufficient_privilege THEN falhas := array_append(falhas, 'controle: anon não lê nem as colunas públicas'); END;
  RESET ROLE;
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  SET LOCAL ROLE authenticated;
  FOREACH k IN ARRAY ARRAY['email', 'telefone', 'cpf_cnpj', 'user_id', 'tenant_id'] LOOP
    BEGIN EXECUTE format('SELECT count(*) FROM public.marketplace_profissionais WHERE %I IS NOT NULL', k) INTO n; falhas := array_append(falhas, 'empresa lê a coluna ' || k); EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  END LOOP;
  BEGIN SELECT count(*) INTO n FROM public.marketplace_profissionais WHERE id = (s->>'a_prof')::uuid; IF n <> 1 THEN falhas := array_append(falhas, 'controle: empresa não lê colunas públicas'); END IF; EXCEPTION WHEN insufficient_privilege THEN falhas := array_append(falhas, 'controle: colunas públicas recusadas'); END;
  RESET ROLE;
  r.passo_ordem := 2; r.passo_acao := 'marketye_vitrine_publica() como anon e marketye_buscar() como empresa'; r.esperado := 'payloads sem e-mail, telefone, documento, user_id, tenant_id';
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  SET LOCAL ROLE anon; v := public.marketye_vitrine_publica(); RESET ROLE;
  v_txt := v::text;
  IF v_txt LIKE '%@%' OR v_txt LIKE '%9000000%' OR v_txt ILIKE '%user_id%' OR v_txt ILIKE '%tenant_id%' THEN falhas := array_append(falhas, 'vitrine pública expõe dado pessoal'); END IF;
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  v := public.marketye_buscar('{"q": "QA Seguranca"}'::jsonb); v_txt := (v->'resultados')::text;
  IF v_txt LIKE '%@%' OR v_txt LIKE '%9000000%' OR v_txt ILIKE '%"user_id"%' OR v_txt ILIKE '%"tenant_id"%' OR v_txt ILIKE '%"email"%' OR v_txt ILIKE '%"telefone"%' OR v_txt ILIKE '%"cpf_cnpj"%' THEN falhas := array_append(falhas, 'busca expõe contato, documento ou ids'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'marketye_meu_portal de outro especialista'; r.esperado := 'não é possível: só o próprio';
  IF public.marketye_meu_portal() IS NOT NULL THEN falhas := array_append(falhas, 'empresa recebe um portal'); END IF;
  PERFORM public.qa_mky_claims((s->>'b_uid')::uuid);
  v := public.marketye_meu_portal();
  IF v->'perfil'->>'id' <> s->>'b_prof' OR v::text LIKE '%' || (s->>'a_prof') || '%' THEN falhas := array_append(falhas, 'portal de B traz dado de A'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Visitante e empresa não leem e-mail, telefone, documento, user_id nem tenant_id (só colunas públicas); vitrine e busca saem sem contato, documento, user_id ou tenant_id; o portal é só do próprio especialista.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN RESET ROLE; PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-095 — o especialista vê da empresa só nome, cidade/UF e reputação
CREATE OR REPLACE FUNCTION public.qa_caso_mky_095()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v_portal jsonb; e jsonb; n int; l uuid; v_c jsonb;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  IF NOT EXISTS (SELECT 1 FROM public.empresa_cadastro WHERE tenant_id = (s->>'t2')::uuid) THEN
    INSERT INTO public.empresa_cadastro (tenant_id, razao_social, cnpj) VALUES ((s->>'t2')::uuid, 'Empresa QA 095', '12.345.678/0001-95');
  END IF;
  INSERT INTO public.empresa_obrigacoes (tenant_id, categoria, titulo, descricao) VALUES ((s->>'t2')::uuid, 'sst', 'PGR (teste)', 'Obrigação fictícia sigilosa de teste');
  r.passo_ordem := 1; r.passo_acao := 'Especialista A abre o portal'; r.esperado := 'leads[].empresa_nome e reputacao_empresa apenas; nada de CNPJ, riscos ou obrigações';
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  v_portal := public.marketye_meu_portal();
  SELECT x INTO e FROM jsonb_array_elements(v_portal->'leads') x WHERE x->>'id' = s->>'lead_ya';
  IF e IS NULL OR e->>'empresa_nome' IS NULL OR e ? 'tenant_id' OR e ? 'cnpj' OR e ? 'empresa_id' THEN falhas := array_append(falhas, 'conversa sem nome da empresa ou com id/CNPJ'); END IF;
  IF v_portal::text LIKE '%12.345.678%' OR v_portal::text LIKE '%12345678%' OR v_portal::text ILIKE '%sigilosa%' OR v_portal::text ILIKE '%PGR (teste)%' THEN falhas := array_append(falhas, 'portal expõe CNPJ ou obrigações da empresa'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'A lê tenants, empresa_cadastro, obrigações e pessoas da empresa'; r.esperado := 'zero linhas (RLS)';
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.tenants WHERE id = (s->>'t2')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'lê tenants'); END IF;
  SELECT count(*) INTO n FROM public.empresa_cadastro WHERE tenant_id = (s->>'t2')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'lê empresa_cadastro'); END IF;
  SELECT count(*) INTO n FROM public.empresa_obrigacoes WHERE tenant_id = (s->>'t2')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'lê empresa_obrigacoes'); END IF;
  SELECT count(*) INTO n FROM public.usuarios_base WHERE tenant_id = (s->>'t2')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'lê usuarios_base'); END IF;
  SELECT count(*) INTO n FROM public.profiles WHERE tenant_id = (s->>'t2')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'lê profiles da empresa'); END IF;
  RESET ROLE;
  r.passo_ordem := 3; r.passo_acao := 'A chama marketye_lead_contato antes da liberação'; r.esperado := 'sem contato';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  l := (public.marketye_abrir_lead((s->>'a_prof')::uuid, (s->>'a_pub')::uuid, 'Conversa fictícia de teste ainda sem contato liberado.')->>'id')::uuid;
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  BEGIN v_c := public.marketye_lead_contato(l); IF COALESCE((v_c->>'liberado')::boolean, true) THEN falhas := array_append(falhas, 'contato entregue antes da liberação'); END IF; EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'O portal mostra da empresa só o nome e a reputação; A não lê tenants, cadastro, obrigações nem pessoas da empresa; sem liberação, nenhum contato.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN RESET ROLE; PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-096 — ajuste de nível gera aviso com motivo e canal de revisão humana com efeito reversível
CREATE OR REPLACE FUNCTION public.qa_caso_mky_096()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; rep jsonb; p uuid; v_oc uuid; v_ct uuid; v_portal jsonb; v_fila jsonb; c record; n int;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca(); p := (s->>'a_prof')::uuid;
  DELETE FROM public.marketplace_avaliacoes WHERE profissional_id = p; DELETE FROM public.marketplace_leads WHERE profissional_id = p;
  WITH l AS (
    INSERT INTO public.marketplace_leads (tenant_id, profissional_id, servico_id, criado_por, status, ganho_em, created_at, primeira_resposta_em)
    SELECT CASE WHEN g <= 5 THEN (s->>'t1')::uuid ELSE (s->>'t2')::uuid END, p, (s->>'a_pub')::uuid, (s->>'x')::uuid, 'ganho', now() - interval '1 day', now() - interval '2 days', now() - interval '2 days' + interval '1 hour' FROM generate_series(1, 6) g RETURNING id, tenant_id)
  INSERT INTO public.marketplace_avaliacoes (lead_id, profissional_id, avaliador_id, tenant_id, direcao, criterios, nota_geral) SELECT id, p, (s->>'x')::uuid, tenant_id, 'cliente_para_especialista', '{}'::jsonb, 5 FROM l;
  rep := public.marketye_recalcular_reputacao(p);
  IF rep->>'nivel' <> 'bronze' THEN r.situacao := 'erro'; r.obtido := 'Mobiliário não chegou a bronze: ' || rep::text; PERFORM public.qa_mky_limpar(); RETURN r; END IF;
  r.passo_ordem := 1; r.passo_acao := 'Ocorrência com reflexo e recálculo'; r.esperado := 'nível mantido, nivel_aviso_em e nivel_aviso_motivo preenchidos; portal mostra o aviso sem texto disciplinar';
  INSERT INTO public.marketplace_ocorrencias (profissional_id, tipo, descricao, reflexo_visibilidade) VALUES (p, 'ocorrencia', 'Ocorrência fictícia de teste', true) RETURNING id INTO v_oc;
  rep := public.marketye_recalcular_reputacao(p);
  IF rep->>'nivel' <> 'bronze' OR rep->>'nivel_aviso_em' IS NULL OR rep->>'nivel_aviso_motivo' IS NULL THEN falhas := array_append(falhas, format('nível %s, aviso %s', rep->>'nivel', COALESCE(rep->>'nivel_aviso_motivo', 'nulo'))); END IF;
  IF COALESCE(rep->>'nivel_aviso_motivo', '') ~* '(penalidade|infra[çc][ãa]o|puni[çc][ãa]o|advert[êe]ncia|rebaix)' THEN falhas := array_append(falhas, 'motivo com palavra disciplinar'); END IF;
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  v_portal := public.marketye_meu_portal();
  IF v_portal->'nivel'->>'aviso_motivo' IS NULL THEN falhas := array_append(falhas, 'portal não mostra o aviso'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'marketye_contestar(reflexo_visibilidade, ocorrência, motivo)'; r.esperado := 'contestação aberta e visível na fila';
  v_ct := (public.marketye_contestar('reflexo_visibilidade', v_oc, 'A ocorrência não procede; o serviço foi entregue conforme combinado (teste).', '[]'::jsonb)->>'id')::uuid;
  PERFORM public.qa_mky_claims((s->>'sa')::uuid);
  v_fila := public.marketye_contestacoes_fila();
  IF NOT (v_fila @> jsonb_build_array(jsonb_build_object('id', v_ct, 'status', 'aberta'))) THEN falhas := array_append(falhas, 'contestação não aparece aberta na fila'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Superadmin defere'; r.esperado := 'trilha com 2 eventos; reflexo retirado; aviso de nível some; auditoria registrada';
  PERFORM public.marketye_contestacao_decidir(v_ct, 'deferida', 'Ocorrência revista; reflexo retirado (teste).');
  SELECT * INTO c FROM public.marketplace_contestacoes WHERE id = v_ct;
  IF c.status <> 'deferida' OR jsonb_array_length(c.trilha) <> 2 THEN falhas := array_append(falhas, format('contestação %s com %s eventos', c.status, jsonb_array_length(c.trilha))); END IF;
  SELECT count(*) INTO n FROM public.marketplace_ocorrencias WHERE id = v_oc AND NOT reflexo_visibilidade; IF n <> 1 THEN falhas := array_append(falhas, 'reflexo não retirado'); END IF;
  SELECT to_jsonb(x) INTO rep FROM public.marketplace_reputacao x WHERE profissional_id = p;
  IF rep->>'nivel_aviso_em' IS NOT NULL THEN falhas := array_append(falhas, 'aviso de nível continua após deferimento'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_audit_log WHERE profissional_id = p AND acao = 'contestacao_deferida'; IF n <> 1 THEN falhas := array_append(falhas, 'auditoria do deferimento ausente'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Ocorrência gera aviso de ajuste com motivo não-disciplinar sem derrubar o nível; a contestação entra na fila; deferida, retira o reflexo, apaga o aviso e fica auditada com trilha de 2 eventos.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ===== Família H — ajustes, taxonomia, painel, níveis (MKY-100..106) =====
-- MKY-100 — salvar pesos versiona, preserva a anterior e a busca usa a nova sem deploy
CREATE OR REPLACE FUNCTION public.qa_caso_mky_100()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v_old jsonb; n0 int; vmax0 int; n1 int; nvig int; vmax1 int; v_new jsonb := '{"fit": 0.9, "reputacao": 0.02, "saude": 0.02, "proximidade": 0.02, "exploracao": 0.02, "preco": 0.01, "destaque": 0.01}'::jsonb; x jsonb; v_calc numeric; v_por uuid;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  v_old := public.marketye_config('relevancia_pesos');
  SELECT count(*), max(versao) INTO n0, vmax0 FROM public.marketplace_config WHERE chave = 'relevancia_pesos' AND jurisdicao = 'BR';
  r.passo_ordem := 1; r.passo_acao := 'marketye_config_salvar(relevancia_pesos, novo JSON, descrição)'; r.esperado := 'nova versão vigente; a antiga preservada com vigente = false';
  PERFORM public.qa_mky_claims((s->>'sa')::uuid); PERFORM public.marketye_config_salvar('relevancia_pesos', v_new, 'teste automatizado', 'BR');
  SELECT count(*), count(*) FILTER (WHERE vigente), max(versao) INTO n1, nvig, vmax1 FROM public.marketplace_config WHERE chave = 'relevancia_pesos' AND jurisdicao = 'BR';
  IF n1 <> n0 + 1 OR nvig <> 1 OR vmax1 <> vmax0 + 1 THEN falhas := array_append(falhas, format('versões %s→%s, vigentes %s, máx %s→%s', n0, n1, nvig, vmax0, vmax1)); END IF;
  IF NOT EXISTS (SELECT 1 FROM public.marketplace_config WHERE chave = 'relevancia_pesos' AND jurisdicao = 'BR' AND NOT vigente AND valor = v_old) THEN falhas := array_append(falhas, 'versão anterior não preservada'); END IF;
  IF public.marketye_config('relevancia_pesos') <> v_new THEN falhas := array_append(falhas, 'vigente não é a nova'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Buscar'; r.esperado := 'fatores ponderados pelos novos pesos';
  SELECT y INTO x FROM public.marketye_buscar_interno('{"q": "QA Seguranca B publicado"}'::jsonb) y WHERE y->>'servico_id' = s->>'b_pub';
  v_calc := 0.9 * (x->'fatores'->>'fit')::numeric + 0.02 * (x->'fatores'->>'reputacao')::numeric + 0.02 * (x->'fatores'->>'saude')::numeric + 0.02 * (x->'fatores'->>'proximidade')::numeric
            + 0.02 * (x->'fatores'->>'exploracao')::numeric + 0.01 * (x->'fatores'->>'preco')::numeric + 0.01 * (x->'fatores'->>'destaque')::numeric;
  IF x IS NULL OR abs((x->>'score')::numeric - v_calc) > 0.03 THEN falhas := array_append(falhas, format('score %s não bate com os novos pesos (%s)', x->>'score', round(v_calc, 4))); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Consultar histórico'; r.esperado := 'todas as versões com quem e quando';
  SELECT criado_por INTO v_por FROM public.marketplace_config WHERE chave = 'relevancia_pesos' AND jurisdicao = 'BR' AND vigente;
  IF v_por IS DISTINCT FROM (s->>'sa')::uuid THEN falhas := array_append(falhas, 'versão nova sem autor'); END IF;
  IF EXISTS (SELECT 1 FROM public.marketplace_config WHERE chave = 'relevancia_pesos' AND criado_em IS NULL) THEN falhas := array_append(falhas, 'versão sem data'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := format('Salvar cria a versão %s vigente e mantém a %s com vigente = false; a busca já pondera com os novos pesos (score %s); histórico com autor e data.', vmax1, vmax0, x->>'score');
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-101 — pesos fora de 100% normalizados; chave faltante e negativo recusados
CREATE OR REPLACE FUNCTION public.qa_caso_mky_101()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_claims text; falhas text[] := '{}'; sa uuid; v jsonb; v_soma numeric; v_msg text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  sa := public.qa_mky_superadmin(); PERFORM public.qa_mky_claims(sa);
  r.passo_ordem := 1; r.passo_acao := 'Salvar pesos somando 120%'; r.esperado := 'gravado normalizado (soma 1,00 ± 0,01)';
  PERFORM public.marketye_config_salvar('relevancia_pesos', '{"fit": 0.45, "reputacao": 0.20, "saude": 0.20, "proximidade": 0.15, "exploracao": 0.10, "preco": 0.05, "destaque": 0.05}'::jsonb, 'teste automatizado', 'BR');
  v := public.marketye_config('relevancia_pesos');
  SELECT sum(value::numeric) INTO v_soma FROM jsonb_each_text(v);
  IF abs(v_soma - 1) > 0.01 THEN falhas := array_append(falhas, format('pesos gravados somando %s', v_soma)); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Salvar sem a chave "saude"'; r.esperado := 'recusado ou completado com padrão';
  BEGIN
    PERFORM public.marketye_config_salvar('relevancia_pesos', '{"fit": 0.30, "reputacao": 0.25, "proximidade": 0.20, "exploracao": 0.10, "preco": 0.10, "destaque": 0.05}'::jsonb, 'teste automatizado', 'BR');
    v := public.marketye_config('relevancia_pesos');
    IF NOT (v ? 'saude') THEN falhas := array_append(falhas, 'gravado sem a chave saude'); END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;
  r.passo_ordem := 3; r.passo_acao := 'Salvar peso negativo'; r.esperado := 'recusado';
  BEGIN
    PERFORM public.marketye_config_salvar('relevancia_pesos', '{"fit": 0.55, "reputacao": 0.20, "saude": 0.20, "proximidade": 0.15, "exploracao": -0.10, "preco": 0.05, "destaque": -0.05}'::jsonb, 'teste automatizado', 'BR');
    v_msg := 'aceitou';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_msg = 'aceitou' THEN falhas := array_append(falhas, 'peso negativo aceito'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Pesos são normalizados para 100%, chave faltante é completada ou recusada e peso negativo é recusado.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-102 — leitura da configuração para quem está logado (a vitrine pública leva o que precisa); escrita só superadmin
CREATE OR REPLACE FUNCTION public.qa_caso_mky_102()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v jsonb; v_msg text; n int;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  r.passo_ordem := 1; r.passo_acao := 'marketye_config(relevancia_pesos) como empresa e especialista; vitrine pública como visitante'; r.esperado := 'logados leem a vigente; visitante recebe os termos pela vitrine';
  PERFORM public.qa_mky_claims((s->>'x')::uuid); IF public.marketye_config('relevancia_pesos') IS NULL THEN falhas := array_append(falhas, 'empresa não lê a configuração'); END IF;
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid); IF public.marketye_config('relevancia_pesos') IS NULL THEN falhas := array_append(falhas, 'especialista não lê a configuração'); END IF;
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  SET LOCAL ROLE anon; v := public.marketye_vitrine_publica(); RESET ROLE;
  IF v->'termos_versoes' IS NULL THEN falhas := array_append(falhas, 'vitrine pública sem termos_versoes'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'marketye_config_salvar como empresa, especialista e visitante'; r.esperado := 'Acesso negado';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  BEGIN PERFORM public.marketye_config_salvar('piso_nota', '{"nota": 1}'::jsonb, 'x', 'BR'); v_msg := 'aceitou'; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_msg <> 'Acesso negado' THEN falhas := array_append(falhas, 'empresa: ' || left(v_msg, 40)); END IF;
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  BEGIN PERFORM public.marketye_config_salvar('piso_nota', '{"nota": 1}'::jsonb, 'x', 'BR'); v_msg := 'aceitou'; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_msg <> 'Acesso negado' THEN falhas := array_append(falhas, 'especialista: ' || left(v_msg, 40)); END IF;
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  SET LOCAL ROLE anon;
  BEGIN PERFORM public.marketye_config_salvar('piso_nota', '{"nota": 1}'::jsonb, 'x', 'BR'); v_msg := 'aceitou'; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  IF v_msg = 'aceitou' THEN falhas := array_append(falhas, 'visitante gravou configuração'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'UPDATE direto em marketplace_config como authenticated'; r.esperado := 'zero linhas ou recusado';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  SET LOCAL ROLE authenticated;
  BEGIN UPDATE public.marketplace_config SET valor = '{}'::jsonb WHERE chave = 'relevancia_pesos'; GET DIAGNOSTICS n = ROW_COUNT; v_msg := n::text; EXCEPTION WHEN insufficient_privilege THEN v_msg := 'recusado'; END;
  RESET ROLE;
  IF v_msg NOT IN ('0', 'recusado') THEN falhas := array_append(falhas, 'UPDATE direto alterou ' || v_msg || ' linhas'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Empresa e especialista leem a configuração vigente; o visitante recebe os termos pela vitrine; salvar recusa os três papéis e o UPDATE direto não altera nada.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN RESET ROLE; PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-103 — desativar subárea tira dos filtros; anúncios antigos seguem visíveis pela raiz
CREATE OR REPLACE FUNCTION public.qa_caso_mky_103()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v_an uuid; v_vit jsonb; n int;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  v_an := public.qa_mky_anuncio_publicado((s->>'a_uid')::uuid, 'QA Taxo 103', 'cipa-brigada', 'online', 'sob_orcamento', NULL);
  r.passo_ordem := 1; r.passo_acao := 'Superadmin marca a subárea cipa-brigada como inativa'; r.esperado := 'some da vitrine pública e da lista de categorias';
  UPDATE public.marketplace_categorias SET ativo = false WHERE slug = 'cipa-brigada';
  v_vit := public.marketye_vitrine_publica();
  IF v_vit::text LIKE '%"cipa-brigada"%' THEN falhas := array_append(falhas, 'subárea inativa continua na vitrine'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Buscar pela raiz'; r.esperado := 'o anúncio antigo continua aparecendo';
  SELECT count(*) INTO n FROM public.marketye_buscar_interno('{"q": "QA Taxo 103", "categoria_slug": "seguranca-trabalho"}'::jsonb) x WHERE x->>'servico_id' = v_an::text;
  IF n <> 1 THEN falhas := array_append(falhas, 'anúncio da subárea inativa sumiu da raiz'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Buscar pela subárea desativada'; r.esperado := 'ainda encontra ou orienta para a raiz, sem erro';
  BEGIN
    SELECT count(*) INTO n FROM public.marketye_buscar_interno('{"q": "QA Taxo 103", "categoria_slug": "cipa-brigada"}'::jsonb) x WHERE x->>'servico_id' = v_an::text;
    IF n <> 1 THEN falhas := array_append(falhas, 'busca pela subárea inativa não encontra o anúncio'); END IF;
  EXCEPTION WHEN OTHERS THEN falhas := array_append(falhas, 'busca pela subárea inativa deu erro: ' || SQLERRM); END;
  UPDATE public.marketplace_categorias SET ativo = true WHERE slug = 'cipa-brigada';
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Subárea inativa some da vitrine pública; o anúncio antigo continua pela raiz e pela própria subárea, sem erro.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-105 — painel de oferta e procura bate com o banco
CREATE OR REPLACE FUNCTION public.qa_caso_mky_105()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v jsonb; n int; v_pgr uuid; v_ltcat uuid; v_root text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  SELECT id INTO v_pgr FROM public.marketplace_categorias WHERE slug = 'pgr'; SELECT id INTO v_ltcat FROM public.marketplace_categorias WHERE slug = 'ltcat-laudos';
  SELECT nome INTO v_root FROM public.marketplace_categorias WHERE slug = 'seguranca-trabalho';
  PERFORM public.qa_mky_claims((s->>'x')::uuid); PERFORM public.marketye_registrar_busca(v_pgr, 'QA', NULL, 'sem oferta', 0, false, NULL);
  PERFORM public.qa_mky_claims((s->>'y')::uuid); PERFORM public.marketye_registrar_busca(v_ltcat, 'QA', NULL, 'com oferta', 5, false, NULL);
  r.passo_ordem := 1; r.passo_acao := 'marketye_painel_liquidez()'; r.esperado := 'contagens iguais a consultas diretas';
  PERFORM public.qa_mky_claims((s->>'sa')::uuid);
  v := public.marketye_painel_liquidez();
  SELECT count(*) INTO n FROM public.marketplace_profissionais WHERE status = 'ativo' AND excluido_em IS NULL; IF (v->'especialistas'->>'ativos')::int <> n THEN falhas := array_append(falhas, format('ativos %s ≠ %s', v->'especialistas'->>'ativos', n)); END IF;
  SELECT count(*) INTO n FROM public.marketplace_profissionais WHERE status = 'pendente' AND excluido_em IS NULL; IF (v->'especialistas'->>'pendentes')::int <> n THEN falhas := array_append(falhas, format('pendentes %s ≠ %s', v->'especialistas'->>'pendentes', n)); END IF;
  SELECT count(*) INTO n FROM public.marketplace_servicos WHERE status = 'publicado' AND ativo; IF (v->>'anuncios_publicados')::int <> n THEN falhas := array_append(falhas, format('anúncios %s ≠ %s', v->>'anuncios_publicados', n)); END IF;
  SELECT count(*) INTO n FROM public.marketplace_leads WHERE created_at >= now() - interval '30 days'; IF (v->'leads'->>'abertos_30d')::int <> n THEN falhas := array_append(falhas, format('leads 30d %s ≠ %s', v->'leads'->>'abertos_30d', n)); END IF;
  SELECT count(*) INTO n FROM public.marketplace_leads WHERE created_at >= now() - interval '30 days' AND primeira_resposta_em IS NOT NULL; IF (v->'leads'->>'respondidos_30d')::int <> n THEN falhas := array_append(falhas, format('respondidos %s ≠ %s', v->'leads'->>'respondidos_30d', n)); END IF;
  SELECT count(DISTINCT p.id) INTO n FROM public.marketplace_servicos sv JOIN public.marketplace_profissionais p ON p.id = sv.profissional_id JOIN public.marketplace_categorias c ON c.id = sv.categoria_id
    WHERE sv.status = 'publicado' AND sv.ativo AND p.status = 'ativo' AND p.estado = 'QA' AND COALESCE(c.pai_id, c.id) = (SELECT id FROM public.marketplace_categorias WHERE slug = 'seguranca-trabalho');
  IF NOT (v->'densidade' @> jsonb_build_array(jsonb_build_object('categoria', v_root, 'uf', 'QA', 'especialistas', n))) THEN falhas := array_append(falhas, format('densidade %s/QA ≠ %s', v_root, n)); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Buracos de liquidez'; r.esperado := 'só células com demanda e sem oferta';
  IF NOT (v->'demanda_latente' @> jsonb_build_array(jsonb_build_object('uf', 'QA', 'empresas', 1, 'categoria', (SELECT nome FROM public.marketplace_categorias WHERE id = v_pgr)))) THEN falhas := array_append(falhas, 'célula sem oferta (PGR/QA) não listada'); END IF;
  SELECT count(*) INTO n FROM jsonb_array_elements(v->'demanda_latente') e WHERE e->>'uf' = 'QA' AND e->>'categoria' = (SELECT nome FROM public.marketplace_categorias WHERE id = v_ltcat); IF n > 0 THEN falhas := array_append(falhas, 'célula com oferta (5 resultados) listada como buraco'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Ativos, pendentes, anúncios, leads e respondidos em 30 dias e densidade por categoria×UF batem com consultas diretas; buracos listam só células com demanda sem oferta.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-106 — requisitos e ordem dos níveis vêm da configuração
CREATE OR REPLACE FUNCTION public.qa_caso_mky_106()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; rep jsonb; p uuid; v_niv jsonb; v_portal jsonb;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca(); p := (s->>'a_prof')::uuid;
  DELETE FROM public.marketplace_avaliacoes WHERE profissional_id = p; DELETE FROM public.marketplace_leads WHERE profissional_id = p;
  WITH l AS (
    INSERT INTO public.marketplace_leads (tenant_id, profissional_id, servico_id, criado_por, status, ganho_em, created_at, primeira_resposta_em)
    SELECT CASE WHEN g <= 3 THEN (s->>'t1')::uuid ELSE (s->>'t2')::uuid END, p, (s->>'a_pub')::uuid, (s->>'x')::uuid, 'ganho', now() - interval '1 day', now() - interval '2 days', now() - interval '2 days' + interval '1 hour' FROM generate_series(1, 5) g RETURNING id, tenant_id)
  INSERT INTO public.marketplace_avaliacoes (lead_id, profissional_id, avaliador_id, tenant_id, direcao, criterios, nota_geral) SELECT id, p, (s->>'x')::uuid, tenant_id, 'cliente_para_especialista', '{}'::jsonb, 4.6 FROM l;
  v_niv := public.marketye_config('niveis');
  r.passo_ordem := 1; r.passo_acao := 'Config bronze exige 2 clientes e média 4,5; recalcular'; r.esperado := 'bronze';
  PERFORM public.qa_mky_claims((s->>'sa')::uuid);
  PERFORM public.marketye_config_salvar('niveis', jsonb_set(v_niv, '{requisitos,bronze}', '{"servicos": 3, "clientes_unicos": 2, "media": 4.5, "taxa_resposta": 0.6, "ocorrencias": 0}'::jsonb), 'teste automatizado', 'BR');
  rep := public.marketye_recalcular_reputacao(p);
  IF rep->>'nivel' <> 'bronze' THEN falhas := array_append(falhas, format('nível %s (clientes %s, média %s)', rep->>'nivel', rep->>'clientes_unicos_total', (SELECT nota_media FROM public.marketplace_profissionais WHERE id = p))); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Config bronze passa a exigir 3 clientes; recalcular'; r.esperado := 'aviso de ajuste, sem cair na hora';
  PERFORM public.marketye_config_salvar('niveis', jsonb_set(v_niv, '{requisitos,bronze}', '{"servicos": 3, "clientes_unicos": 3, "media": 4.5, "taxa_resposta": 0.6, "ocorrencias": 0}'::jsonb), 'teste automatizado', 'BR');
  rep := public.marketye_recalcular_reputacao(p);
  IF rep->>'nivel' <> 'bronze' OR rep->>'nivel_aviso_em' IS NULL THEN falhas := array_append(falhas, format('após apertar a regra: nível %s, aviso %s', rep->>'nivel', COALESCE(rep->>'nivel_aviso_em', 'nulo'))); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Ordem de níveis alterada na config'; r.esperado := 'portal mostra a nova ordem';
  PERFORM public.marketye_config_salvar('niveis', jsonb_set(jsonb_set(v_niv, '{ordem}', '["novo", "bronze", "prata", "ouro", "top", "lenda"]'::jsonb), '{requisitos,lenda}', '{"servicos": 100, "clientes_unicos": 40, "media": 4.9, "taxa_resposta": 0.98, "ocorrencias": 0}'::jsonb), 'teste automatizado', 'BR');
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  v_portal := public.marketye_meu_portal();
  IF v_portal->'nivel'->'ordem' <> '["novo", "bronze", "prata", "ouro", "top", "lenda"]'::jsonb THEN falhas := array_append(falhas, 'portal não reflete a nova ordem: ' || COALESCE((v_portal->'nivel'->'ordem')::text, 'nula')); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Com bronze exigindo 2 clientes o especialista sobe; apertando para 3 ele recebe aviso sem cair na hora; a ordem de níveis alterada aparece no portal. Tudo pela configuração, sem deploy.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ===== Família J — integrações (MKY-121..124) =====
-- MKY-121 — ação criada da conversa: origem marketplace, 5W2H, validação de eficácia, isolamento
CREATE OR REPLACE FUNCTION public.qa_caso_mky_121()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v_ac uuid; a record; n int; v_msg text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  INSERT INTO public.user_roles (user_id, role) VALUES ((s->>'x')::uuid, 'manager');
  r.passo_ordem := 1; r.passo_acao := 'Criar ação a partir da conversa (como a empresa, sob RLS)'; r.esperado := 'plano_acoes com origem_modulo = marketplace e origem_id = lead; 5W2H preenchidos';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  PERFORM set_config('app.qa_modo', 'off', true);  -- a trava do cercado lê tenants sob RLS como authenticated (ver MKY-001)
  SET LOCAL ROLE authenticated;
  INSERT INTO public.plano_acoes (tenant_id, titulo, descricao, porque, onde, prazo, responsavel_nome, como, custo_estimado, origem_modulo, origem_id, origem_descricao, tipo)
  VALUES ((s->>'t1')::uuid, 'Contratar PGR com especialista (teste)', 'Elaborar o PGR com o especialista da conversa', 'Obrigação NR-1 pendente', 'Unidade QA', CURRENT_DATE + 30, 'QA Empresa 110x', 'Pelo MarketYE', 1500, 'marketplace', (s->>'lead_xb')::uuid, 'Conversa MarketYE', 'corretiva')
  RETURNING id INTO v_ac;
  RESET ROLE;
  PERFORM set_config('app.qa_modo', 'on', true);
  SELECT * INTO a FROM public.plano_acoes WHERE id = v_ac;
  IF a.origem_modulo <> 'marketplace' OR a.origem_id <> (s->>'lead_xb')::uuid OR a.porque IS NULL OR a.onde IS NULL OR a.prazo IS NULL OR a.responsavel_nome IS NULL OR a.como IS NULL OR a.custo_estimado IS NULL OR a.codigo IS NULL THEN falhas := array_append(falhas, 'ação sem origem ou sem 5W2H completo'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Concluir a ação'; r.esperado := 'exige validação de eficácia (data e responsável)';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  PERFORM set_config('app.qa_modo', 'off', true);
  SET LOCAL ROLE authenticated;
  BEGIN UPDATE public.plano_acoes SET status = 'concluida', data_conclusao = CURRENT_DATE, progresso = 100 WHERE id = v_ac; GET DIAGNOSTICS n = ROW_COUNT; v_msg := CASE WHEN n = 1 THEN 'concluiu' ELSE 'zero linhas' END; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  PERFORM set_config('app.qa_modo', 'on', true);
  IF v_msg = 'concluiu' THEN falhas := array_append(falhas, 'ação de origem MarketYE concluída sem validação de eficácia'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Outra empresa consulta a ação'; r.esperado := 'não vê';
  PERFORM public.qa_mky_claims((s->>'y')::uuid);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.plano_acoes WHERE id = v_ac;
  RESET ROLE;
  IF n > 0 THEN falhas := array_append(falhas, 'outra empresa vê a ação'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Ação nasce com origem marketplace, id do lead e 5W2H; concluir exige eficácia; outra empresa não vê.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN RESET ROLE; PERFORM set_config('app.qa_modo', 'on', true); PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-122 — documento arquivado: metadados, versão e isolamento
CREATE OR REPLACE FUNCTION public.qa_caso_mky_122()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v_doc uuid; d record; n int; l uuid;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca(); l := (s->>'lead_xb')::uuid;
  INSERT INTO public.user_roles (user_id, role) VALUES ((s->>'x')::uuid, 'manager');
  INSERT INTO public.documentos (tenant_id, colaborador_nome, nome_arquivo, nome_original, tipo, tamanho, mime_type, storage_path, data_validade, criado_por, observacoes)
  VALUES ((s->>'t1')::uuid, 'Proposta MarketYE (teste)', 'proposta-teste.pdf', 'proposta-teste.pdf', 'proposta', 1000, 'application/pdf', (s->>'t1') || '/marketye/proposta-teste-v1.pdf', CURRENT_DATE + 90, (s->>'x')::uuid, 'Origem: MarketYE, conversa ' || l::text)
  RETURNING id INTO v_doc;
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  PERFORM public.marketye_lead_vincular_documento(l, v_doc, 'proposta');
  r.passo_ordem := 1; r.passo_acao := 'Consultar o módulo Documentos como a empresa'; r.esperado := 'tipo, origem MarketYE, lead, versão 1, vigência';
  SET LOCAL ROLE authenticated;
  SELECT * INTO d FROM public.documentos WHERE id = v_doc;
  RESET ROLE;
  IF d.id IS NULL OR d.tipo <> 'proposta' OR d.versao_atual <> 1 OR d.data_validade IS NULL OR d.observacoes NOT ILIKE '%MarketYE%' THEN falhas := array_append(falhas, 'metadados incompletos para a empresa'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_lead_documentos WHERE documento_id = v_doc AND lead_id = l; IF n <> 1 THEN falhas := array_append(falhas, 'vínculo com o lead ausente'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Nova versão do mesmo documento'; r.esperado := 'versão 2 vinculada; versão 1 preservada';
  PERFORM set_config('app.qa_modo', 'off', true);  -- a trava do cercado lê tenants sob RLS como authenticated (ver MKY-001)
  SET LOCAL ROLE authenticated;
  UPDATE public.documentos SET storage_path = (s->>'t1') || '/marketye/proposta-teste-v2.pdf', versao_atual = 2, total_versoes = 2 WHERE id = v_doc;
  GET DIAGNOSTICS n = ROW_COUNT;
  RESET ROLE;
  PERFORM set_config('app.qa_modo', 'on', true);
  IF n <> 1 THEN falhas := array_append(falhas, 'empresa não conseguiu versionar'); END IF;
  SELECT count(*) INTO n FROM public.documento_versoes WHERE documento_id = v_doc; IF n <> 2 THEN falhas := array_append(falhas, format('%s versões (esperado 2)', n)); END IF;
  SELECT count(*) INTO n FROM public.documento_versoes WHERE documento_id = v_doc AND versao = 1 AND storage_path LIKE '%v1.pdf'; IF n <> 1 THEN falhas := array_append(falhas, 'versão 1 não preservada'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_lead_documentos WHERE documento_id = v_doc AND lead_id = l; IF n <> 1 THEN falhas := array_append(falhas, 'vínculo perdido ao versionar'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Outra empresa'; r.esperado := 'não vê';
  PERFORM public.qa_mky_claims((s->>'y')::uuid);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.documentos WHERE id = v_doc; IF n > 0 THEN falhas := array_append(falhas, 'outra empresa lê o documento'); END IF;
  SELECT count(*) INTO n FROM public.documento_versoes WHERE documento_id = v_doc; IF n > 0 THEN falhas := array_append(falhas, 'outra empresa lê as versões'); END IF;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'A empresa vê o documento com tipo, origem MarketYE, vínculo com o lead, versão 1 e vigência; a nova versão vira 2 mantendo a 1 e o vínculo; outra empresa não vê nada.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN RESET ROLE; PERFORM set_config('app.qa_modo', 'on', true); PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-123 — endereço da empresa vem do cadastro; mudar lá muda a busca padrão
CREATE OR REPLACE FUNCTION public.qa_caso_mky_123()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v_emp uuid; v_res jsonb;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  SELECT id INTO v_emp FROM public.empresa_cadastro WHERE tenant_id = (s->>'t1')::uuid ORDER BY created_at LIMIT 1;
  IF v_emp IS NULL THEN INSERT INTO public.empresa_cadastro (tenant_id, razao_social) VALUES ((s->>'t1')::uuid, 'Empresa QA 123') RETURNING id INTO v_emp; END IF;
  UPDATE public.empresa_cadastro SET latitude = -25.0, longitude = -52.0, estado = 'QA' WHERE id = v_emp;
  PERFORM public.qa_mky_anuncio_publicado((s->>'a_uid')::uuid, 'QA UF 123 A1', 'seguranca-trabalho', 'online', 'sob_orcamento', NULL);
  PERFORM public.qa_mky_anuncio_publicado((s->>'a_uid')::uuid, 'QA UF 123 A2', 'seguranca-trabalho', 'online', 'sob_orcamento', NULL);
  PERFORM public.qa_mky_anuncio_publicado((s->>'b_uid')::uuid, 'QA UF 123 B1', 'seguranca-trabalho', 'online', 'sob_orcamento', NULL);
  r.passo_ordem := 1; r.passo_acao := 'Buscar sem coordenadas'; r.esperado := 'usa latitude/longitude/UF da empresa';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  v_res := public.marketye_buscar('{"q": "QA UF 123"}'::jsonb);
  IF (v_res->>'total')::int < 3 OR (v_res->'filtros_aplicados'->>'lat')::numeric <> -25.0 OR v_res->'filtros_aplicados'->>'uf' <> 'QA' OR (v_res->'filtros_aplicados'->>'uf_padrao')::boolean IS DISTINCT FROM true THEN falhas := array_append(falhas, 'busca não partiu do cadastro da empresa: ' || (v_res->'filtros_aplicados')::text); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Mudar a UF da empresa e buscar'; r.esperado := 'nova UF padrão';
  UPDATE public.empresa_cadastro SET estado = 'ZZ' WHERE id = v_emp;
  v_res := public.marketye_buscar('{"q": "QA UF 123"}'::jsonb);
  IF v_res->'filtros_aplicados'->>'uf' <> 'ZZ' THEN falhas := array_append(falhas, 'UF nova não virou padrão: ' || COALESCE(v_res->'filtros_aplicados'->>'uf', 'nula')); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'A busca padrão parte de latitude, longitude e UF do cadastro da empresa; trocar a UF lá troca a UF padrão da busca. (O passo da tela sem campo de endereço é conferido no Cypress, não no motor.)';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-124 — parceiro do canal não ganha ranking; contabilidades separadas
CREATE OR REPLACE FUNCTION public.qa_caso_mky_124()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_claims text; falhas text[] := '{}'; sa uuid; p record; q record; v_parc uuid; sp numeric; sq numeric; v_txt text; n int; v_fns text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  sa := public.qa_mky_superadmin();
  SELECT * INTO p FROM public.qa_mky_especialista('124p', '900.000.034-33');
  SELECT * INTO q FROM public.qa_mky_especialista('124q', '900.000.035-14');
  PERFORM public.qa_mky_claims(sa);
  PERFORM public.marketye_moderar_especialista(p.prof_id, 'aprovado', NULL, true); PERFORM public.marketye_moderar_especialista(q.prof_id, 'aprovado', NULL, true);
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  INSERT INTO public.parceiros (codigo, nome) VALUES ('QA-MKY-124', 'Parceiro QA 124') RETURNING id INTO v_parc;
  UPDATE public.marketplace_profissionais SET parceiro_id = v_parc WHERE id = p.prof_id;
  PERFORM public.qa_mky_anuncio_publicado(p.uid, 'QA Parceiro 124 P', 'seguranca-trabalho', 'online', 'sob_orcamento', NULL);
  PERFORM public.qa_mky_anuncio_publicado(q.uid, 'QA Parceiro 124 Q', 'seguranca-trabalho', 'online', 'sob_orcamento', NULL);
  r.passo_ordem := 1; r.passo_acao := 'Buscar'; r.esperado := 'scores iguais; fatores não citam parceiro';
  SELECT (x->>'score')::numeric INTO sp FROM public.marketye_buscar_interno('{"q": "QA Parceiro 124"}'::jsonb) x WHERE x->'profissional'->>'id' = p.prof_id::text;
  SELECT (x->>'score')::numeric INTO sq FROM public.marketye_buscar_interno('{"q": "QA Parceiro 124"}'::jsonb) x WHERE x->'profissional'->>'id' = q.prof_id::text;
  IF sp IS NULL OR sq IS NULL OR sp <> sq THEN falhas := array_append(falhas, format('scores diferentes: parceiro %s × não parceiro %s', sp, sq)); END IF;
  SELECT string_agg(x::text, ' ') INTO v_txt FROM public.marketye_buscar_interno('{"q": "QA Parceiro 124"}'::jsonb) x;
  IF v_txt ILIKE '%parceiro_id%' OR v_txt ILIKE '%"parceiro"%' THEN falhas := array_append(falhas, 'resultado da busca cita o papel de parceiro'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Consultar comissões do parceiro'; r.esperado := 'separadas do MarketYE, sem cruzar leads';
  SELECT count(*) INTO n FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'parceiro_comissoes' AND (column_name ILIKE '%lead%' OR column_name ILIKE '%profissional%' OR column_name ILIKE '%servico%');
  IF n > 0 THEN falhas := array_append(falhas, 'comissões do parceiro referenciam leads ou especialistas'); END IF;
  SELECT string_agg(proname, ', ') INTO v_fns FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname LIKE 'marketye_%' AND (prosrc ILIKE '%parceiro_comissoes%' OR prosrc ILIKE '%parceiro_eventos_remuneracao%');
  IF v_fns IS NOT NULL THEN falhas := array_append(falhas, 'funções do MarketYE escrevem em comissões do canal: ' || v_fns); END IF;
  DELETE FROM public.parceiros WHERE id = v_parc;
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := format('Especialista com parceiro_id e outro sem, iguais no resto, têm o mesmo score (%s) e nenhum fator cita parceiro; as comissões do canal não referenciam leads nem especialistas e nenhuma função do MarketYE mexe nelas.', sp);
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ---------------------------------------------------------------------
-- 2) Registro das rotinas no motor
-- ---------------------------------------------------------------------
INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES
  ('MKY-031', 'qa_caso_mky_031'), ('MKY-032', 'qa_caso_mky_032'), ('MKY-033', 'qa_caso_mky_033'), ('MKY-034', 'qa_caso_mky_034'),
  ('MKY-035', 'qa_caso_mky_035'), ('MKY-037', 'qa_caso_mky_037'), ('MKY-038', 'qa_caso_mky_038'), ('MKY-041', 'qa_caso_mky_041'),
  ('MKY-042', 'qa_caso_mky_042'), ('MKY-043', 'qa_caso_mky_043'), ('MKY-045', 'qa_caso_mky_045'), ('MKY-046', 'qa_caso_mky_046'),
  ('MKY-051', 'qa_caso_mky_051'), ('MKY-052', 'qa_caso_mky_052'), ('MKY-053', 'qa_caso_mky_053'), ('MKY-054', 'qa_caso_mky_054'),
  ('MKY-055', 'qa_caso_mky_055'), ('MKY-056', 'qa_caso_mky_056'), ('MKY-057', 'qa_caso_mky_057'), ('MKY-058', 'qa_caso_mky_058'),
  ('MKY-060', 'qa_caso_mky_060'), ('MKY-061', 'qa_caso_mky_061'), ('MKY-062', 'qa_caso_mky_062'), ('MKY-063', 'qa_caso_mky_063'),
  ('MKY-064', 'qa_caso_mky_064'), ('MKY-065', 'qa_caso_mky_065'), ('MKY-068', 'qa_caso_mky_068'), ('MKY-071', 'qa_caso_mky_071'),
  ('MKY-072', 'qa_caso_mky_072'), ('MKY-073', 'qa_caso_mky_073'), ('MKY-074', 'qa_caso_mky_074'), ('MKY-075', 'qa_caso_mky_075'),
  ('MKY-077', 'qa_caso_mky_077'), ('MKY-080', 'qa_caso_mky_080'), ('MKY-081', 'qa_caso_mky_081'), ('MKY-082', 'qa_caso_mky_082'),
  ('MKY-083', 'qa_caso_mky_083'), ('MKY-084', 'qa_caso_mky_084'), ('MKY-085', 'qa_caso_mky_085'), ('MKY-086', 'qa_caso_mky_086'),
  ('MKY-087', 'qa_caso_mky_087'), ('MKY-088', 'qa_caso_mky_088'), ('MKY-090', 'qa_caso_mky_090'), ('MKY-092', 'qa_caso_mky_092'),
  ('MKY-093', 'qa_caso_mky_093'), ('MKY-094', 'qa_caso_mky_094'), ('MKY-095', 'qa_caso_mky_095'), ('MKY-096', 'qa_caso_mky_096'),
  ('MKY-100', 'qa_caso_mky_100'), ('MKY-101', 'qa_caso_mky_101'), ('MKY-102', 'qa_caso_mky_102'), ('MKY-103', 'qa_caso_mky_103'),
  ('MKY-105', 'qa_caso_mky_105'), ('MKY-106', 'qa_caso_mky_106'), ('MKY-121', 'qa_caso_mky_121'), ('MKY-122', 'qa_caso_mky_122'),
  ('MKY-123', 'qa_caso_mky_123'), ('MKY-124', 'qa_caso_mky_124')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- ---------------------------------------------------------------------
-- 3) Ajustes de texto nos casos cujo desenho da construção difere da
--    redação original (cupom automático, contestação de avaliação, etc.)
-- ---------------------------------------------------------------------
UPDATE public.qa_casos_teste SET passos = '[{"ordem": 1, "acao": "Chamar marketye_transparencia(ano)", "resultado_esperado": "JSON com contagens: denúncias recebidas e procedentes, cadastros aprovados/rejeitados, anúncios publicados, impulsionamentos, contestações abertas/deferidas/indeferidas, exclusões LGPD"}, {"ordem": 2, "acao": "Inspecionar o JSON", "resultado_esperado": "nenhum nome, e-mail, CPF ou id de pessoa; usuário comum recebe nulo"}]'::jsonb, observacoes = COALESCE(observacoes, '') || ' Ajuste 12/09: o requisito (3.3) pede notificações, anúncios e impulsionamentos; anúncios removidos, suspensões e prazo médio de decisão ficam como sugestão de evolução.', updated_at = now() WHERE codigo = 'MKY-045';
UPDATE public.qa_casos_teste SET passos = '[{"ordem": 1, "acao": "Salvar com tipo_preco = hora (qualquer tipo que não seja sob orçamento) e preco_referencia = 0", "resultado_esperado": "recusado: \"Informe um preço-base ou marque sob orçamento\""}, {"ordem": 2, "acao": "Salvar com tipo_preco = sob_orcamento sem preço", "resultado_esperado": "aceito"}, {"ordem": 3, "acao": "Salvar faixa com preco_minimo 500 e preco_maximo 100", "resultado_esperado": "recusado ou normalizado, nunca gravado invertido"}]'::jsonb, updated_at = now() WHERE codigo = 'MKY-052';
UPDATE public.qa_casos_teste SET passos = '[{"ordem": 1, "acao": "Criar cupom BEMVINDO 15% válido até +10 dias, limite 2", "resultado_esperado": "criado; busca devolve tem_cupom = true"}, {"ordem": 2, "acao": "Criar outro cupom com o mesmo código", "resultado_esperado": "atualiza o existente (não duplica)"}, {"ordem": 3, "acao": "Duas empresas abrem conversa (o melhor cupom válido entra sozinho na conversa) e uma terceira conversa nova é aberta", "resultado_esperado": "as duas primeiras com cupom_codigo e usos = 2; a terceira sem cupom; busca passa a tem_cupom = false"}, {"ordem": 4, "acao": "Cupom com validade ontem", "resultado_esperado": "tem_cupom = false; conversa nova sem cupom"}]'::jsonb, pre_condicoes = 'Especialista aprovado. Desenho da construção: a empresa não digita código; o melhor cupom válido do especialista é aplicado ao abrir a conversa.', updated_at = now() WHERE codigo = 'MKY-055';
UPDATE public.qa_casos_teste SET passos = '[{"ordem": 1, "acao": "Só existe cupom vencido: empresa abre conversa", "resultado_esperado": "conversa sem cupom"}, {"ordem": 2, "acao": "Cupom válido com limite 1: outra empresa abre conversa", "resultado_esperado": "lead.cupom_codigo preenchido; usos = 1; mensagem de sistema cita o cupom"}, {"ordem": 3, "acao": "Terceira conversa nova com o cupom esgotado", "resultado_esperado": "sem cupom; usos continua 1"}]'::jsonb, pre_condicoes = 'Especialista com cupom vencido e, depois, um válido com limite 1. O cupom entra sozinho na conversa (não há código digitado pela empresa).', updated_at = now() WHERE codigo = 'MKY-077';
UPDATE public.qa_casos_teste SET passos = '[{"ordem": 1, "acao": "Recalcular", "resultado_esperado": "nível continua \"novo\": clientes únicos abaixo do exigido"}, {"ordem": 2, "acao": "Segunda empresa ganha + uma ocorrência com reflexo; recalcular", "resultado_esperado": "não sobe (ocorrencias = 0 exigido)"}, {"ordem": 3, "acao": "Ocorrência sem reflexo; recalcular", "resultado_esperado": "sobe para bronze (30+ serviços, 2 clientes, média 5, resposta 100%) e para em bronze"}]'::jsonb, pre_condicoes = 'Especialista com 30 conversas ganhas e avaliadas nota 5, todas da mesma empresa; zero ocorrências.', updated_at = now() WHERE codigo = 'MKY-085';
UPDATE public.qa_casos_teste SET passos = '[{"ordem": 1, "acao": "Especialista contesta a avaliação (tipo avaliacao) e o superadmin defere: moderada = true", "resultado_esperado": "some do portal, da leitura pública e do card"}, {"ordem": 2, "acao": "Recalcular", "resultado_esperado": "nota_media e total_avaliacoes sem ela"}]'::jsonb, observacoes = COALESCE(observacoes, '') || ' Ajuste 12/09: o caminho construído é a contestação deferida; não existe moderação iniciada pelo superadmin sem contestação (sugestão).', updated_at = now() WHERE codigo = 'MKY-087';
UPDATE public.qa_casos_teste SET passos = '[{"ordem": 1, "acao": "marketye_exportar_meus_dados()", "resultado_esperado": "JSON com perfil, consentimentos (versões, datas), anúncios, cupons, leads (sem dados pessoais de contato da empresa além do nome), avaliações recebidas e dadas, contestações, eventos de autonomia"}, {"ordem": 2, "acao": "Outro especialista chama a função", "resultado_esperado": "recebe só os próprios dados"}, {"ordem": 3, "acao": "Usuário de empresa chama", "resultado_esperado": "devolve vazio (perfil nulo) e nada de terceiros"}]'::jsonb, updated_at = now() WHERE codigo = 'MKY-090';
UPDATE public.qa_casos_teste SET passos = '[{"ordem": 1, "acao": "Especialista exclui o perfil", "resultado_esperado": "aceito; lead passa a encerrado com mensagem de sistema \"especialista deixou o MarketYE\""}, {"ordem": 2, "acao": "Empresa abre Minhas conversas", "resultado_esperado": "vê a conversa encerrada, sem erro; os dados de contato do especialista já não aparecem (anonimizados pela exclusão)"}]'::jsonb, updated_at = now() WHERE codigo = 'MKY-092';
UPDATE public.qa_casos_teste SET passos = '[{"ordem": 1, "acao": "Ocorrência com reflexo e recálculo", "resultado_esperado": "reputacao com nivel_aviso_em e nivel_aviso_motivo; nível mantido; portal mostra o aviso com texto não-disciplinar"}, {"ordem": 2, "acao": "marketye_contestar(reflexo_visibilidade, ocorrência, motivo)", "resultado_esperado": "contestação aberta e visível na fila"}, {"ordem": 3, "acao": "Superadmin defere", "resultado_esperado": "trilha com 2 eventos; reflexo retirado; aviso de nível some; auditoria registrada"}]'::jsonb, pre_condicoes = 'Especialista em bronze que recebe uma ocorrência com reflexo (aviso de ajuste de nível).', updated_at = now() WHERE codigo = 'MKY-096';
UPDATE public.qa_casos_teste SET passos = '[{"ordem": 1, "acao": "marketye_config(relevancia_pesos) como empresa e especialista; visitante lê os termos vigentes pela vitrine pública", "resultado_esperado": "logados recebem a vigente; visitante recebe termos_versoes na vitrine (a função de configuração não é exposta a anon — D-05)"}, {"ordem": 2, "acao": "marketye_config_salvar como cada papel", "resultado_esperado": "\"Acesso negado\""}, {"ordem": 3, "acao": "UPDATE direto em marketplace_config como authenticated", "resultado_esperado": "zero linhas ou recusado"}]'::jsonb, updated_at = now() WHERE codigo = 'MKY-102';
UPDATE public.qa_casos_teste SET passos = '[{"ordem": 1, "acao": "Config bronze exige 2 clientes e média 4,5 → recalcular", "resultado_esperado": "bronze"}, {"ordem": 2, "acao": "Config bronze passa a exigir 3 clientes → recalcular", "resultado_esperado": "aviso de ajuste (não cai na hora: MKY-010)"}, {"ordem": 3, "acao": "Ordem de níveis alterada na config", "resultado_esperado": "portal mostra a nova ordem"}]'::jsonb, pre_condicoes = 'Especialista com 2 clientes únicos (5 conversas ganhas) e média 4,6.', updated_at = now() WHERE codigo = 'MKY-106';
UPDATE public.qa_casos_teste SET observacoes = COALESCE(observacoes, '') || ' Ajuste 12/09: o passo 3 (tela sem campo de endereço) é do Cypress; o motor cobre os passos 1 e 2.', updated_at = now() WHERE codigo = 'MKY-123';
UPDATE public.qa_casos_teste SET observacoes = COALESCE(observacoes, '') || ' Ajuste 12/09: a rotina usa 20 km, 250 km e remoto a 800 km (250 km entra só pelo relaxamento de raio x3).', updated_at = now() WHERE codigo = 'MKY-063';

-- ---------------------------------------------------------------------
-- 4) Disposição dos casos que a primeira execução provou falhando
-- ---------------------------------------------------------------------
UPDATE public.qa_casos_teste SET disposicao = 'bug_confirmado', disposicao_motivo = 'Bio gravada com telefone e e-mail em texto claro por marketye_meu_perfil_salvar; a vitrine mostra a bio (a máscara cobre anúncio, mensagens e avaliações, não a apresentação). Rotina qa_caso_mky_037.', disposicao_em = now(), disposicao_por = 'qa-agente', updated_at = now() WHERE codigo = 'MKY-037';
UPDATE public.qa_casos_teste SET disposicao = 'bug_confirmado', disposicao_motivo = 'marketye_denuncia_decidir(procedente) registra a ocorrência mas não remove o anúncio denunciado: ele segue publicado e na busca (sem takedown). Rotina qa_caso_mky_042.', disposicao_em = now(), disposicao_por = 'qa-agente', updated_at = now() WHERE codigo = 'MKY-042';
UPDATE public.qa_casos_teste SET disposicao = 'bug_confirmado', disposicao_motivo = 'Job pg_cron bloquear-profissionais-expirados e gatilho trg_verificar_registro_profissional (herdados da Rede de Parceiros) põem o especialista em bloqueado sozinhos, sem decisão humana, motivo ou trilha. Rotina qa_caso_mky_046.', disposicao_em = now(), disposicao_por = 'qa-agente', updated_at = now() WHERE codigo = 'MKY-046';
UPDATE public.qa_casos_teste SET disposicao = 'bug_confirmado', disposicao_motivo = 'marketye_anuncio_salvar grava faixa invertida (mínimo 500 > máximo 100). Rotina qa_caso_mky_052.', disposicao_em = now(), disposicao_por = 'qa-agente', updated_at = now() WHERE codigo = 'MKY-052';
UPDATE public.qa_casos_teste SET disposicao = 'bug_confirmado', disposicao_motivo = 'Anúncio removido volta a publicado por marketye_anuncio_publicar e volta a rascunho por marketye_anuncio_salvar: a remoção não é definitiva. Rotina qa_caso_mky_053.', disposicao_em = now(), disposicao_por = 'qa-agente', updated_at = now() WHERE codigo = 'MKY-053';
UPDATE public.qa_casos_teste SET disposicao = 'bug_confirmado', disposicao_motivo = 'Percentual de promoção não é validado: 0 e 95 são aceitos. Rotina qa_caso_mky_054.', disposicao_em = now(), disposicao_por = 'qa-agente', updated_at = now() WHERE codigo = 'MKY-054';
UPDATE public.qa_casos_teste SET disposicao = 'bug_confirmado', disposicao_motivo = 'A política pública de marketplace_servicos e a contagem da vitrine não conferem o status do especialista: anúncios publicados de pendente, suspenso e bloqueado ficam legíveis por visitante e entram na contagem (a busca está correta). Rotina qa_caso_mky_068.', disposicao_em = now(), disposicao_por = 'qa-agente', updated_at = now() WHERE codigo = 'MKY-068';
UPDATE public.qa_casos_teste SET disposicao = 'bug_confirmado', disposicao_motivo = 'CRÍTICO: marketye_lead_liberar_contato e marketye_lead_status aceitam terceiro — o papel nulo não é recusado (NULL <> cliente não dispara o RAISE); qualquer especialista logado libera o contato e muda o status de conversa alheia. marketye_lead_mensagem só recusa por acidente (NOT NULL de autor_tipo). Rotina qa_caso_mky_071.', disposicao_em = now(), disposicao_por = 'qa-agente', updated_at = now() WHERE codigo = 'MKY-071';
UPDATE public.qa_casos_teste SET disposicao = 'bug_confirmado', disposicao_motivo = 'Recusa pelo especialista (perdido/encerrado) não marca primeira_resposta_em: a taxa de resposta trata a recusa como falta. A mensagem de sistema ainda atribui o encerramento à empresa. Rotina qa_caso_mky_072.', disposicao_em = now(), disposicao_por = 'qa-agente', updated_at = now() WHERE codigo = 'MKY-072';
UPDATE public.qa_casos_teste SET disposicao = 'bug_confirmado', disposicao_motivo = 'Usuário que é empresa e especialista abre conversa consigo mesmo, marca ganho, avalia, e a própria empresa conta como cliente único e serviço. Rotina qa_caso_mky_082.', disposicao_em = now(), disposicao_por = 'qa-agente', updated_at = now() WHERE codigo = 'MKY-082';
UPDATE public.qa_casos_teste SET disposicao = 'bug_confirmado', disposicao_motivo = 'Avaliação moderada some do portal e do cálculo, mas continua legível na tabela pública (política SELECT true para authenticated) e nenhuma tela filtra moderada. Rotina qa_caso_mky_087.', disposicao_em = now(), disposicao_por = 'qa-agente', updated_at = now() WHERE codigo = 'MKY-087';
UPDATE public.qa_casos_teste SET disposicao = 'bug_confirmado', disposicao_motivo = 'marketye_exportar_meus_dados não inclui os cupons do especialista (LGPD art. 18, portabilidade). Rotina qa_caso_mky_090.', disposicao_em = now(), disposicao_por = 'qa-agente', updated_at = now() WHERE codigo = 'MKY-090';
UPDATE public.qa_casos_teste SET disposicao = 'bug_confirmado', disposicao_motivo = 'marketye_excluir_meu_perfil não encerra as conversas abertas nem avisa a empresa; o lead segue aberto com o especialista anonimizado. Rotina qa_caso_mky_092.', disposicao_em = now(), disposicao_por = 'qa-agente', updated_at = now() WHERE codigo = 'MKY-092';
UPDATE public.qa_casos_teste SET disposicao = 'bug_confirmado', disposicao_motivo = 'O termo novo aparece como pendente no portal, mas marketye_anuncio_publicar não exige o aceite da versão vigente. Rotina qa_caso_mky_093.', disposicao_em = now(), disposicao_por = 'qa-agente', updated_at = now() WHERE codigo = 'MKY-093';
UPDATE public.qa_casos_teste SET disposicao = 'bug_confirmado', disposicao_motivo = 'marketye_config_salvar grava relevancia_pesos como vier: soma 120%, chave faltante e peso negativo aceitos (D-11). Rotina qa_caso_mky_101.', disposicao_em = now(), disposicao_por = 'qa-agente', updated_at = now() WHERE codigo = 'MKY-101';
UPDATE public.qa_casos_teste SET disposicao = 'aguardando_construcao', disposicao_motivo = 'Ação de origem marketplace conclui sem validação de eficácia: a regra existe só para ações nascidas de alerta do ponto (ponto_acao_concluir_com_eficacia). Origem, 5W2H e isolamento passam. Rotina qa_caso_mky_121.', disposicao_em = now(), disposicao_por = 'qa-agente', updated_at = now() WHERE codigo = 'MKY-121';
