-- ============================================================================
-- ENTREGA — MKY-063 e MKY-123 · rotinas de QA robustas ao ambiente — HOMOLOGAÇÃO
--
-- Cole no SQL Editor da HOMOLOGAÇÃO; depois de conferido, o MESMO na PRODUÇÃO.
--
-- Os dois davam ERRO na produção ("empresa_cadastro violates chk_empresa_tipo_pessoa"):
-- a versão ANTIGA das rotinas dava UPDATE numa linha legada de empresa_cadastro
-- (semeada no staging com tipo_pessoa='juridica', valor legado fora de {'pj','pf'});
-- a CHECK, adicionada depois, revalida a linha no UPDATE e a rotina quebrava no
-- próprio setup. A versão CORRIGIDA (migration 20260913140000) apaga e recria
-- exatamente UMA linha do cercado (tipo_pessoa cai no default 'pj'), sem tocar a
-- linha legada — determinística e sem violar a CHECK.
--
-- SEGURANÇA: só CREATE OR REPLACE de duas rotinas de QA (read-mostly; o
-- DELETE/INSERT é no tenant do cercado, dentro da transação descartada do motor).
-- Não cria tabela, não muda função de produto, não toca dado real. Idempotente.
--
-- NOTA: a linha legada 'juridica' em empresa_cadastro continua na base e fará
-- QUALQUER update dela falhar com o mesmo 23514 (inclusive em telas reais, não só
-- no QA). A higienização desse dado é separada — ver docs/script_normaliza_tipo_pessoa_empresa.sql
-- (normaliza 'juridica'→'pj', 'fisica'→'pf' e valida a constraint). Recomendo
-- aplicá-la também, mas não é necessária para fechar MKY-063/123.
--
-- Origem: migration 20260913140000 (seções MKY-063 e MKY-123).
-- ============================================================================

SET lock_timeout = '10s';

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

-- ════════════════════ CONFERÊNCIA (única — esperado tudo 'ok') ════════════════
WITH alvo(item, presente) AS (
  VALUES
    ('MKY-063 · rotina presente e corrigida (recria linha do cercado)',
       (to_regprocedure('public.qa_caso_mky_063()') IS NOT NULL
        AND pg_get_functiondef('public.qa_caso_mky_063()'::regprocedure) ~* 'Empresa QA 063')),
    ('MKY-123 · rotina presente e corrigida (recria linha do cercado)',
       (to_regprocedure('public.qa_caso_mky_123()') IS NOT NULL
        AND pg_get_functiondef('public.qa_caso_mky_123()'::regprocedure) ~* 'Empresa QA 123')),
    ('MKY-063/123 · não fazem mais UPDATE da linha legada',
       (pg_get_functiondef('public.qa_caso_mky_063()'::regprocedure) ~* 'DELETE FROM public.empresa_cadastro'
        AND pg_get_functiondef('public.qa_caso_mky_123()'::regprocedure) ~* 'DELETE FROM public.empresa_cadastro'))
)
SELECT item, CASE WHEN presente THEN 'ok' ELSE 'FALTOU' END AS situacao FROM alvo ORDER BY item;
