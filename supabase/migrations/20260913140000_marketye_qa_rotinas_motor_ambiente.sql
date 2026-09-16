-- =====================================================================
-- MARKETYE · QA · ROTINAS DO MOTOR ROBUSTAS AO AMBIENTE REAL (staging)
--
-- O relatório do motor rodado no staging (13/09, 10:47) trouxe, além dos
-- 16 achados de produto já dispostos, três itens que passavam na réplica e
-- só apareciam no banco real:
--   · MKY-058 "erro: cannot insert a non-DEFAULT value into column
--     path_tokens" — no Storage da Supabase path_tokens é coluna GERADA;
--     a rotina inseria valor. Passa a inserir só bucket/name/owner.
--   · MKY-063 e MKY-123 — dependiam de empresa_cadastro do cercado, que no
--     staging tem várias linhas; marketye_buscar lê ORDER BY created_at
--     LIMIT 1 e, com created_at empatado, a rotina atualizava uma linha e a
--     busca lia outra. Passam a apagar e recriar exatamente UMA linha do
--     cercado (transação descartada), ficando determinísticas.
--
-- Nenhuma função de produto muda. CREATE OR REPLACE (idempotente).
-- =====================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.qa_caso_mky_058()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; n int; v_foto text; v_doc text; v_pub boolean;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  v_foto := (s->>'a_prof') || '/foto.jpg'; v_doc := (s->>'a_prof') || '/identidade.pdf';
  -- path_tokens é coluna GERADA no Storage da Supabase (não aceita valor no INSERT); só bucket/name/owner.
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('marketplace-fotos', v_foto, (s->>'a_uid')::uuid), ('marketplace-docs', v_doc, (s->>'a_uid')::uuid);
  INSERT INTO public.marketplace_profissional_documentos (profissional_id, categoria, nome_arquivo, arquivo_url, tamanho_bytes, mime_type) VALUES ((s->>'a_prof')::uuid, 'identidade', 'identidade.pdf', 'marketplace-docs/' || v_doc, 1234, 'application/pdf');
  SELECT public INTO v_pub FROM storage.buckets WHERE id = 'marketplace-fotos'; IF v_pub IS DISTINCT FROM true THEN falhas := array_append(falhas, 'bucket de fotos não é público'); END IF;
  SELECT public INTO v_pub FROM storage.buckets WHERE id = 'marketplace-docs'; IF v_pub IS DISTINCT FROM false THEN falhas := array_append(falhas, 'bucket de documentos é público'); END IF;
  r.passo_ordem := 1; r.passo_acao := 'Ler a foto sem login'; r.esperado := 'acessível';
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  n := qa_rls.conta_anon(format('SELECT count(*) FROM storage.objects WHERE bucket_id = ''marketplace-fotos'' AND name = %L', v_foto)); IF n <> 1 THEN falhas := array_append(falhas, 'foto não acessível sem login'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Ler o documento sem login e como outro especialista'; r.esperado := 'negado';
  n := qa_rls.conta_anon(format('SELECT count(*) FROM storage.objects WHERE bucket_id = ''marketplace-docs'' AND name = %L', v_doc)); IF n > 0 THEN falhas := array_append(falhas, 'documento legível sem login'); END IF;
  PERFORM public.qa_mky_claims((s->>'b_uid')::uuid);
  n := qa_rls.conta_auth(format('SELECT count(*) FROM storage.objects WHERE bucket_id = ''marketplace-docs'' AND name = %L', v_doc)); IF n > 0 THEN falhas := array_append(falhas, 'outro especialista lê o documento'); END IF;
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  n := qa_rls.conta_auth(format('SELECT count(*) FROM storage.objects WHERE bucket_id = ''marketplace-docs'' AND name = %L', v_doc)); IF n <> 1 THEN falhas := array_append(falhas, 'controle: o dono não lê o próprio documento'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Ler como superadmin'; r.esperado := 'acessível';
  PERFORM public.qa_mky_claims((s->>'sa')::uuid);
  n := qa_rls.conta_auth(format('SELECT count(*) FROM storage.objects WHERE bucket_id = ''marketplace-docs'' AND name = %L', v_doc)); IF n <> 1 THEN falhas := array_append(falhas, 'superadmin não lê o documento'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Foto no bucket público legível sem login; documento de verificação invisível para visitante e para outro especialista; dono e superadmin leem.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_063()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_claims text; falhas text[] := '{}'; sa uuid; g1 record; g2 record; g3 record; a1 uuid; a2 uuid; a3 uuid; t1 uuid := public.qa_sandbox_tenant_id(); v_x uuid; v_res jsonb; ids text[]; v_emp uuid; d1 numeric;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  sa := public.qa_mky_superadmin(); v_x := public.qa_mky_usuario_empresa(t1, '063x');
  -- Determinístico: no staging o cercado já tem linhas de empresa_cadastro e o ORDER BY created_at
  -- LIMIT 1 do marketye_buscar fica ambíguo com empates. Deixa exatamente uma (transação descartada).
  DELETE FROM public.empresa_cadastro WHERE tenant_id = t1;
  INSERT INTO public.empresa_cadastro (tenant_id, razao_social, latitude, longitude, estado) VALUES (t1, 'Empresa QA 063', -25.0, -52.0, 'QA') RETURNING id INTO v_emp;
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

CREATE OR REPLACE FUNCTION public.qa_caso_mky_123()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v_emp uuid; v_res jsonb;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  -- Determinístico: uma única linha de empresa_cadastro para o cercado (ver 063).
  DELETE FROM public.empresa_cadastro WHERE tenant_id = (s->>'t1')::uuid;
  INSERT INTO public.empresa_cadastro (tenant_id, razao_social, latitude, longitude, estado) VALUES ((s->>'t1')::uuid, 'Empresa QA 123', -25.0, -52.0, 'QA') RETURNING id INTO v_emp;
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
