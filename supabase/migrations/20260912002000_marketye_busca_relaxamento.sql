-- =====================================================================
-- MARKETYE · BUSCA NÃO QUEBRA AO RELAXAR FILTROS (regressão 12/09/2026)
--
-- O que aconteceu: no ambiente de teste a vitrine filtrada por Segurança
-- do Trabalho respondia "malformed array literal: uf". A empresa de teste
-- tem estado cadastrado; a busca entra com UF, acha menos de 3 anúncios e
-- vai relaxar o filtro. Na hora de anotar a etapa relaxada, a função fazia
-- lista || 'uf' — com o literal sem tipo, o banco entende os dois lados
-- como lista e tenta ler "uf" como uma lista, e a busca inteira falha.
-- Vale para as cinco etapas (raio, cidade, modalidade, uf, nota_min).
-- Na réplica de desenvolvimento não apareceu porque a empresa de teste
-- local não tinha endereço: o relaxamento nunca rodava.
--
-- Correção: array_append(lista, 'etapa'), que não deixa dúvida de tipo.
-- Caso de QA MKY-015 documenta e cobre (força as cinco etapas).
--
-- Idempotente: CREATE OR REPLACE e ON CONFLICT.
-- =====================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.marketye_buscar(p_filtros jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $marketye_buscar$
DECLARE
  f jsonb := COALESCE(p_filtros, '{}'::jsonb); v_res jsonb; v_n int; v_relax text[] := '{}'; v_tenant uuid := public.get_user_tenant_id();
  v_lat double precision; v_lng double precision; v_uf text; v_min int := 3; v_adj jsonb; v_cat uuid;
BEGIN
  -- Origem do endereço do cliente (9.2): a empresa do usuário, salvo se a tela mandou coordenadas.
  IF (f->>'lat') IS NULL AND v_tenant IS NOT NULL THEN
    SELECT latitude, longitude, estado INTO v_lat, v_lng, v_uf FROM public.empresa_cadastro WHERE tenant_id = v_tenant ORDER BY created_at LIMIT 1;
    IF v_lat IS NOT NULL AND v_lng IS NOT NULL THEN f := f || jsonb_build_object('lat', v_lat, 'lng', v_lng); END IF;
    IF (f->>'uf') IS NULL AND (f->>'ignorar_uf_padrao') IS NULL AND v_uf IS NOT NULL THEN f := f || jsonb_build_object('uf', v_uf, 'uf_padrao', true); END IF;
  END IF;

  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb), count(*) INTO v_res, v_n FROM public.marketye_buscar_interno(f) x;
  IF v_n < v_min AND (f->>'lat') IS NOT NULL THEN
    f := f || jsonb_build_object('raio_km', COALESCE(NULLIF(f->>'raio_km', '')::numeric, 100) * 3); v_relax := array_append(v_relax, 'raio');
    SELECT COALESCE(jsonb_agg(x), '[]'::jsonb), count(*) INTO v_res, v_n FROM public.marketye_buscar_interno(f) x;
  END IF;
  IF v_n < v_min AND (f->>'cidade') IS NOT NULL THEN
    f := f - 'cidade'; v_relax := array_append(v_relax, 'cidade');
    SELECT COALESCE(jsonb_agg(x), '[]'::jsonb), count(*) INTO v_res, v_n FROM public.marketye_buscar_interno(f) x;
  END IF;
  IF v_n < v_min AND (f->>'modalidade') IS NOT NULL THEN
    f := f - 'modalidade'; v_relax := array_append(v_relax, 'modalidade');
    SELECT COALESCE(jsonb_agg(x), '[]'::jsonb), count(*) INTO v_res, v_n FROM public.marketye_buscar_interno(f) x;
  END IF;
  IF v_n < v_min AND (f->>'uf') IS NOT NULL THEN
    f := (f - 'uf') - 'lat' - 'lng'; v_relax := array_append(v_relax, 'uf');
    SELECT COALESCE(jsonb_agg(x), '[]'::jsonb), count(*) INTO v_res, v_n FROM public.marketye_buscar_interno(f) x;
  END IF;
  IF v_n < v_min AND (f->>'nota_min') IS NOT NULL THEN
    f := f - 'nota_min'; v_relax := array_append(v_relax, 'nota_min');
    SELECT COALESCE(jsonb_agg(x), '[]'::jsonb), count(*) INTO v_res, v_n FROM public.marketye_buscar_interno(f) x;
  END IF;

  v_cat := NULLIF(f->>'categoria_id', '')::uuid;
  IF v_cat IS NULL AND (f->>'categoria_slug') IS NOT NULL THEN SELECT id INTO v_cat FROM public.marketplace_categorias WHERE slug = f->>'categoria_slug' LIMIT 1; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.nome, 'slug', c.slug)), '[]'::jsonb) INTO v_adj
  FROM public.marketplace_categorias c WHERE v_cat IS NOT NULL AND c.ativo AND c.id <> v_cat
    AND c.pai_id IS NOT DISTINCT FROM (SELECT pai_id FROM public.marketplace_categorias WHERE id = v_cat)
  LIMIT 6;

  RETURN jsonb_build_object('total', v_n, 'resultados', v_res, 'relaxamentos', to_jsonb(v_relax), 'filtros_aplicados', f,
                            'categorias_adjacentes', v_adj, 'oferta_insuficiente', v_n < v_min);
END $marketye_buscar$;
GRANT EXECUTE ON FUNCTION public.marketye_buscar(jsonb) TO authenticated;

-- ---------------------------------------------------------------------
-- QA: caso MKY-015 documentado + rotina
-- ---------------------------------------------------------------------
DO $qa$
DECLARE v_mod uuid;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'rede-parceiros';
  IF v_mod IS NULL THEN RETURN; END IF;

  INSERT INTO public.qa_casos_teste (modulo_id, codigo, titulo, tipo, prioridade, status, nivel, base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes) VALUES
  (v_mod, 'MKY-015', 'Busca com poucos resultados relaxa os filtros (raio, cidade, modalidade, UF, nota) sem quebrar e ainda encontra o anúncio',
   'feliz', 'critica', 'aprovado', 'api', 'RN-023 (busca nunca vazia); RF-006/008',
   'Quando os filtros exatos acham menos de 3 anúncios, a busca afrouxa um filtro por vez e informa quais afrouxou. Nenhuma dessas etapas pode derrubar a busca.',
   'Cercado qa-sandbox; versões de termos em marketplace_config.',
   '[{"ordem":1,"acao":"Especialista aprovado com anúncio presencial publicado (estado QA, sem coordenadas)","resultado_esperado":"anúncio na vitrine"},
     {"ordem":2,"acao":"Empresa busca pelo nome com UF diferente, cidade inexistente, modalidade presencial, nota mínima 4,5 e coordenadas","resultado_esperado":"sem erro; ao menos 1 resultado; a lista de etapas relaxadas inclui uf"}]'::jsonb,
   'A busca afrouxa os filtros em ordem e devolve o anúncio, informando as etapas relaxadas.',
   'Regressão real de 12/09/2026: "malformed array literal: uf" na etapa de relaxar a UF. Roda em transação descartada.')
  ON CONFLICT (codigo) DO UPDATE SET titulo = EXCLUDED.titulo, tipo = EXCLUDED.tipo, prioridade = EXCLUDED.prioridade, nivel = EXCLUDED.nivel,
    base_legal = EXCLUDED.base_legal, objetivo = EXCLUDED.objetivo, pre_condicoes = EXCLUDED.pre_condicoes, passos = EXCLUDED.passos,
    resultado_esperado = EXCLUDED.resultado_esperado, observacoes = EXCLUDED.observacoes;
END $qa$;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_015()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; e record; v_sa uuid; v_t uuid := public.qa_sandbox_tenant_id(); v_u uuid; v_claims text; v_an uuid; v_cat uuid; v_res jsonb; v_relax text[];
BEGIN
  PERFORM public.qa_mky_limpar();
  IF v_t IS NULL THEN r.situacao := 'erro'; r.obtido := 'Cercado qa-sandbox não existe'; RETURN r; END IF;
  v_claims := current_setting('request.jwt.claims', true);
  v_u := public.qa_mky_usuario_empresa(v_t, '015'); v_sa := public.qa_mky_superadmin();
  SELECT * INTO e FROM public.qa_mky_especialista('015', '900.000.031-90');
  SELECT id INTO v_cat FROM public.marketplace_categorias WHERE slug = 'seguranca-trabalho';

  r.passo_ordem := 1; r.passo_acao := 'Aprovar o especialista e publicar um anúncio presencial'; r.esperado := 'anúncio na vitrine';
  PERFORM public.qa_mky_claims(v_sa); PERFORM public.marketye_moderar_especialista(e.prof_id, 'aprovado', NULL, true);
  PERFORM public.qa_mky_claims(e.uid);
  v_res := public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Treinamento MKY-015 exclusivo', 'descricao', 'Serviço fictício de teste do MarketYE, apenas para a rotina automatizada.', 'categoria_id', v_cat, 'modalidade', 'presencial', 'tipo_preco', 'sob_orcamento'));
  v_an := (v_res->>'id')::uuid;
  PERFORM public.marketye_anuncio_publicar(v_an);

  r.passo_ordem := 2; r.passo_acao := 'Buscar com UF diferente, cidade inexistente, modalidade, nota mínima e coordenadas'; r.esperado := 'sem erro; >= 1 resultado; relaxou uf';
  PERFORM public.qa_mky_claims(v_u);
  v_res := public.marketye_buscar(jsonb_build_object('q', 'QA Treinamento MKY-015', 'uf', 'ZZ', 'cidade', 'Lugar Nenhum', 'modalidade', 'presencial', 'nota_min', 4.5, 'lat', -26.2, 'lng', -52.6));
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  v_relax := ARRAY(SELECT jsonb_array_elements_text(COALESCE(v_res->'relaxamentos', '[]'::jsonb)));
  IF (v_res->>'total')::int >= 1 AND 'uf' = ANY(v_relax) THEN
    r.situacao := 'passou'; r.obtido := format('Busca relaxou %s e encontrou %s anúncio(s) sem quebrar.', array_to_string(v_relax, ', '), v_res->>'total');
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: total %s, etapas relaxadas %s', v_res->>'total', array_to_string(v_relax, ', '));
  END IF;
  r.detalhe := jsonb_build_object('relaxamentos', v_res->'relaxamentos');
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES ('MKY-015', 'qa_caso_mky_015')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
