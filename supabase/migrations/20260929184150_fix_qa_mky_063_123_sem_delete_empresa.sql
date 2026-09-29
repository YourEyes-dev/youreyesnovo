-- ============================================================================
-- FIX MKY-063 / MKY-123 (erro no motor): determinismo sem apagar empresas
--
-- PROBLEMA: as duas rotinas forcavam "uma empresa so no cercado" com
--   DELETE FROM public.empresa_cadastro WHERE tenant_id = <cercado>;
-- porque marketye_buscar escolhe a empresa por ORDER BY created_at LIMIT 1. Mas
-- as rotinas irmas (PONTO/ADM/FER) deixam admissoes e feriados apontando para
-- essas empresas: o DELETE bate na FK admissoes_empresa_id_fkey (e afins) e o
-- caso vira "erro". Em cercado limpo passava; em cercado com dados acumulados
-- (homologacao), quebra. E efeito colateral do proprio arnes de teste.
--
-- CORRECAO: nenhum DELETE de empresa. Cada rotina reaproveita a SUA empresa QA
-- e a torna a UNICA mais antiga do cercado (created_at = 1970-01-01), empurrando
-- a irma MKY para frente (created_at = now()). Assim o ORDER BY created_at
-- LIMIT 1 do marketye_buscar sempre devolve a empresa do caso, sem empate e sem
-- tocar em FK. Idempotente. Só CREATE OR REPLACE de FUNCAO (nao cria tabela).
--
-- MKY-063 e MKY-123 compartilham o tenant qa-sandbox (qa_mky_cenario_seguranca
-- devolve t1 = qa_sandbox_tenant_id): por isso o "empurra a irma" e necessario.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.qa_caso_mky_063()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_claims text; falhas text[] := '{}'; sa uuid; g1 record; g2 record; g3 record; a1 uuid; a2 uuid; a3 uuid; t1 uuid := public.qa_sandbox_tenant_id(); v_x uuid; v_res jsonb; ids text[]; v_emp uuid; d1 numeric;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  sa := public.qa_mky_superadmin(); v_x := public.qa_mky_usuario_empresa(t1, '063x');
  -- Determinístico: no staging o cercado já tem linhas de empresa_cadastro e o ORDER BY created_at
  -- LIMIT 1 do marketye_buscar fica ambíguo com empates. Deixa exatamente uma (transação descartada).
  -- FK-safe + deterministico: em vez de apagar TODAS as empresas do cercado (o que
  -- colide com as FKs de admissoes/feriados deixadas pelas rotinas irmas), reaproveita
  -- a empresa QA deste caso e a torna a UNICA mais antiga do tenant -- marketye_buscar
  -- usa ORDER BY created_at LIMIT 1. Nenhum DELETE de empresa.
  SELECT id INTO v_emp FROM public.empresa_cadastro
   WHERE tenant_id = t1 AND razao_social = 'Empresa QA 063' ORDER BY created_at LIMIT 1;
  IF v_emp IS NULL THEN
    INSERT INTO public.empresa_cadastro (tenant_id, razao_social, latitude, longitude, estado, created_at)
    VALUES (t1, 'Empresa QA 063', -25.0, -52.0, 'QA', '1970-01-01'::timestamptz) RETURNING id INTO v_emp;
  ELSE
    UPDATE public.empresa_cadastro SET latitude=-25.0, longitude=-52.0, estado='QA',
           created_at='1970-01-01'::timestamptz WHERE id = v_emp;
  END IF;
  -- empurra a irma MKY (unica outra empresa "epoca" do cercado) para frente: sem empate no ORDER BY
  UPDATE public.empresa_cadastro SET created_at = now()
   WHERE tenant_id = t1 AND id <> v_emp AND created_at <= '1970-01-01'::timestamptz;
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
  -- FK-safe + deterministico (mesmo padrao do 063): sem apagar empresas.
  SELECT id INTO v_emp FROM public.empresa_cadastro
   WHERE tenant_id = (s->>'t1')::uuid AND razao_social = 'Empresa QA 123' ORDER BY created_at LIMIT 1;
  IF v_emp IS NULL THEN
    INSERT INTO public.empresa_cadastro (tenant_id, razao_social, latitude, longitude, estado, created_at)
    VALUES ((s->>'t1')::uuid, 'Empresa QA 123', -25.0, -52.0, 'QA', '1970-01-01'::timestamptz) RETURNING id INTO v_emp;
  ELSE
    UPDATE public.empresa_cadastro SET latitude=-25.0, longitude=-52.0, estado='QA',
           created_at='1970-01-01'::timestamptz WHERE id = v_emp;
  END IF;
  UPDATE public.empresa_cadastro SET created_at = now()
   WHERE tenant_id = (s->>'t1')::uuid AND id <> v_emp AND created_at <= '1970-01-01'::timestamptz;
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
