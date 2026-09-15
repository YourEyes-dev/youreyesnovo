-- ============================================================================
-- Fase 4 (motores) — Marketplace (MarketYE): regras de anúncio e perfil.
--
-- Correções de LÓGICA de negócio (não mexem em RLS/moderação):
-- MKY-037: a apresentação (bio) do especialista é mascarada — telefone/e-mail/
--          link ocultos até a liberação (a vitrine mostra a bio).
-- MKY-052: faixa de preço nunca é gravada invertida (mínimo > máximo).
-- MKY-054: percentual de promoção validado (maior que 0 e no máximo 90%).
--
-- Observação: os demais casos do Marketplace (denúncia/moderação/isolamento por
-- RLS — MKY-042/046/068/071/072/082/087/090/092/093/101/121) dependem do
-- comportamento de auth/RLS do Supabase e devem ser validados no ambiente de
-- teste real, não na réplica local. Ficam para um lote com verificação no
-- staging.
-- ============================================================================

-- ── MKY-037: mascara o contato na apresentação (bio) ────────────────────────
CREATE OR REPLACE FUNCTION public.marketye_meu_perfil_salvar(_dados jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $mkyfn$
DECLARE v_id uuid := public.marketye_meu_id(); v_mod text[];
BEGIN
  IF v_id IS NULL THEN RAISE EXCEPTION 'Sem cadastro de especialista'; END IF;
  IF _dados ? 'modalidades' THEN v_mod := ARRAY(SELECT jsonb_array_elements_text(_dados->'modalidades')); END IF;
  UPDATE public.marketplace_profissionais SET
    nome_completo = CASE WHEN status = 'pendente' AND length(COALESCE(_dados->>'nome_completo', '')) >= 3 THEN _dados->>'nome_completo' ELSE nome_completo END,
    telefone = CASE WHEN _dados ? 'telefone' THEN NULLIF(_dados->>'telefone', '') ELSE telefone END,
    -- A bio aparece na vitrine pública: contato direto fica oculto ate a liberacao.
    bio = CASE WHEN _dados ? 'bio' THEN NULLIF(public.marketye_mascarar_contato(_dados->>'bio'), '') ELSE bio END,
    formacao_academica = CASE WHEN _dados ? 'formacao_academica' THEN NULLIF(_dados->>'formacao_academica', '') ELSE formacao_academica END,
    registro_profissional = CASE WHEN _dados ? 'registro_profissional' THEN NULLIF(_dados->>'registro_profissional', '') ELSE registro_profissional END,
    conselho = CASE WHEN _dados ? 'conselho' THEN NULLIF(_dados->>'conselho', '') ELSE conselho END,
    uf_registro = CASE WHEN _dados ? 'uf_registro' THEN NULLIF(upper(_dados->>'uf_registro'), '') ELSE uf_registro END,
    registro_validade = CASE WHEN _dados ? 'registro_validade' THEN NULLIF(_dados->>'registro_validade', '')::date ELSE registro_validade END,
    certificacoes = CASE WHEN _dados ? 'certificacoes' THEN NULLIF(ARRAY(SELECT jsonb_array_elements_text(_dados->'certificacoes')), '{}') ELSE certificacoes END,
    especialidades = CASE WHEN _dados ? 'especialidades' THEN NULLIF(ARRAY(SELECT jsonb_array_elements_text(_dados->'especialidades')), '{}') ELSE especialidades END,
    areas_atuacao = CASE WHEN _dados ? 'areas_atuacao' THEN NULLIF(ARRAY(SELECT jsonb_array_elements_text(_dados->'areas_atuacao')), '{}') ELSE areas_atuacao END,
    modalidades_atendimento = CASE WHEN v_mod IS NOT NULL AND array_length(v_mod, 1) > 0 THEN v_mod::public.marketplace_servico_modalidade[] ELSE modalidades_atendimento END,
    cidade = CASE WHEN _dados ? 'cidade' THEN NULLIF(_dados->>'cidade', '') ELSE cidade END,
    estado = CASE WHEN _dados ? 'estado' THEN NULLIF(upper(_dados->>'estado'), '') ELSE estado END,
    latitude = CASE WHEN _dados ? 'latitude' THEN NULLIF(_dados->>'latitude', '')::double precision ELSE latitude END,
    longitude = CASE WHEN _dados ? 'longitude' THEN NULLIF(_dados->>'longitude', '')::double precision ELSE longitude END,
    atende_remoto = CASE WHEN _dados ? 'atende_remoto' THEN (_dados->>'atende_remoto')::boolean ELSE atende_remoto END,
    raio_atendimento_km = CASE WHEN _dados ? 'raio_atendimento_km' THEN COALESCE(NULLIF(_dados->>'raio_atendimento_km', '')::int, raio_atendimento_km) ELSE raio_atendimento_km END,
    disponibilidade = CASE WHEN _dados ? 'disponibilidade' THEN COALESCE(_dados->'disponibilidade', '{}'::jsonb) ELSE disponibilidade END,
    politicas = CASE WHEN _dados ? 'politicas' THEN NULLIF(_dados->>'politicas', '') ELSE politicas END,
    site_url = CASE WHEN _dados ? 'site_url' THEN NULLIF(_dados->>'site_url', '') ELSE site_url END,
    video_url = CASE WHEN _dados ? 'video_url' THEN NULLIF(_dados->>'video_url', '') ELSE video_url END,
    foto_url = CASE WHEN _dados ? 'foto_url' THEN NULLIF(_dados->>'foto_url', '') ELSE foto_url END,
    tipo_pessoa = CASE WHEN _dados->>'tipo_pessoa' IN ('pf', 'pj') THEN _dados->>'tipo_pessoa' ELSE tipo_pessoa END
  WHERE id = v_id;
  RETURN jsonb_build_object('id', v_id, 'ok', true);
END $mkyfn$;

-- ── MKY-052 / MKY-054: faixa de preço e percentual de promoção ──────────────
CREATE OR REPLACE FUNCTION public.marketye_anuncio_salvar(_dados jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $mkyfn$
DECLARE v_prof uuid := public.marketye_meu_id(); v_id uuid := NULLIF(_dados->>'id', '')::uuid; v_cat uuid := NULLIF(_dados->>'categoria_id', '')::uuid; v_obr text[];
BEGIN
  IF v_prof IS NULL THEN RAISE EXCEPTION 'Sem cadastro de especialista'; END IF;
  IF length(trim(COALESCE(_dados->>'nome', ''))) < 5 THEN RAISE EXCEPTION 'Dê um título ao anúncio (mínimo 5 letras)'; END IF;
  IF length(trim(COALESCE(_dados->>'descricao', ''))) < 20 THEN RAISE EXCEPTION 'Descreva o serviço (mínimo 20 letras)'; END IF;
  IF COALESCE(_dados->>'tipo_preco', 'sob_orcamento') <> 'sob_orcamento' AND COALESCE(NULLIF(_dados->>'preco_referencia', '')::numeric, 0) <= 0 THEN
    RAISE EXCEPTION 'Informe um preço-base ou marque "sob orçamento".';
  END IF;

  -- MKY-054: percentual de promoção deve ser > 0 e no máximo 90%.
  IF NULLIF(_dados->>'promocao_percentual', '') IS NOT NULL THEN
    IF (_dados->>'promocao_percentual')::numeric <= 0 OR (_dados->>'promocao_percentual')::numeric > 90 THEN
      RAISE EXCEPTION 'Percentual de promoção inválido: informe um valor entre 1%% e 90%%.';
    END IF;
  END IF;

  -- MKY-052: faixa de preço nunca gravada invertida — normaliza (troca) se vier
  -- mínimo maior que máximo.
  IF NULLIF(_dados->>'preco_minimo', '') IS NOT NULL AND NULLIF(_dados->>'preco_maximo', '') IS NOT NULL
     AND (_dados->>'preco_minimo')::numeric > (_dados->>'preco_maximo')::numeric THEN
    _dados := _dados || jsonb_build_object(
      'preco_minimo', _dados->'preco_maximo',
      'preco_maximo', _dados->'preco_minimo');
  END IF;

  v_obr := ARRAY(SELECT jsonb_array_elements_text(COALESCE(_dados->'obrigacao_legal', '[]'::jsonb)));
  IF array_length(v_obr, 1) IS NULL AND v_cat IS NOT NULL THEN
    SELECT obrigacao_legal INTO v_obr FROM public.marketplace_categorias WHERE id = v_cat;
  END IF;
  IF v_id IS NULL THEN
    INSERT INTO public.marketplace_servicos (profissional_id, categoria_id, nome, descricao, base_legal, modalidade, publico_alvo, evidencia_minima,
      preco_referencia, tipo_preco, preco_minimo, preco_maximo, duracao_estimada_minutos, tags, obrigacao_legal, area_atendimento, prazo_tipico,
      politica_cancelamento, midia, gerado_por_ia, promocao_percentual, promocao_inicio, promocao_fim, promocao_descricao, ativo, status, moeda, pais)
    VALUES (v_prof, v_cat, trim(_dados->>'nome'), trim(_dados->>'descricao'), NULLIF(_dados->>'base_legal', ''),
      COALESCE(NULLIF(_dados->>'modalidade', ''), 'presencial')::public.marketplace_servico_modalidade, NULLIF(_dados->>'publico_alvo', ''), NULLIF(_dados->>'evidencia_minima', ''),
      NULLIF(_dados->>'preco_referencia', '')::numeric, COALESCE(NULLIF(_dados->>'tipo_preco', ''), 'sob_orcamento'), NULLIF(_dados->>'preco_minimo', '')::numeric,
      NULLIF(_dados->>'preco_maximo', '')::numeric, NULLIF(_dados->>'duracao_estimada_minutos', '')::int,
      ARRAY(SELECT jsonb_array_elements_text(COALESCE(_dados->'tags', '[]'::jsonb))), COALESCE(v_obr, '{}'), COALESCE(_dados->'area_atendimento', '{}'::jsonb),
      NULLIF(_dados->>'prazo_tipico', ''), NULLIF(_dados->>'politica_cancelamento', ''), COALESCE(_dados->'midia', '[]'::jsonb),
      COALESCE((_dados->>'gerado_por_ia')::boolean, false), NULLIF(_dados->>'promocao_percentual', '')::numeric, NULLIF(_dados->>'promocao_inicio', '')::date,
      NULLIF(_dados->>'promocao_fim', '')::date, NULLIF(_dados->>'promocao_descricao', ''), true, 'rascunho',
      COALESCE(NULLIF(_dados->>'moeda', ''), 'BRL'), COALESCE(NULLIF(_dados->>'pais', ''), 'BR'))
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.marketplace_servicos SET
      categoria_id = v_cat, nome = trim(_dados->>'nome'), descricao = trim(_dados->>'descricao'), base_legal = NULLIF(_dados->>'base_legal', ''),
      modalidade = COALESCE(NULLIF(_dados->>'modalidade', ''), modalidade::text)::public.marketplace_servico_modalidade,
      publico_alvo = NULLIF(_dados->>'publico_alvo', ''), evidencia_minima = NULLIF(_dados->>'evidencia_minima', ''),
      preco_referencia = NULLIF(_dados->>'preco_referencia', '')::numeric, tipo_preco = COALESCE(NULLIF(_dados->>'tipo_preco', ''), 'sob_orcamento'),
      preco_minimo = NULLIF(_dados->>'preco_minimo', '')::numeric, preco_maximo = NULLIF(_dados->>'preco_maximo', '')::numeric,
      duracao_estimada_minutos = NULLIF(_dados->>'duracao_estimada_minutos', '')::int,
      tags = ARRAY(SELECT jsonb_array_elements_text(COALESCE(_dados->'tags', '[]'::jsonb))), obrigacao_legal = COALESCE(v_obr, '{}'),
      area_atendimento = COALESCE(_dados->'area_atendimento', '{}'::jsonb), prazo_tipico = NULLIF(_dados->>'prazo_tipico', ''),
      politica_cancelamento = NULLIF(_dados->>'politica_cancelamento', ''), midia = COALESCE(_dados->'midia', midia),
      promocao_percentual = NULLIF(_dados->>'promocao_percentual', '')::numeric, promocao_inicio = NULLIF(_dados->>'promocao_inicio', '')::date,
      promocao_fim = NULLIF(_dados->>'promocao_fim', '')::date, promocao_descricao = NULLIF(_dados->>'promocao_descricao', ''),
      status = CASE WHEN status = 'removido' THEN 'rascunho' ELSE status END
    WHERE id = v_id AND profissional_id = v_prof;
    IF NOT FOUND THEN RAISE EXCEPTION 'Anúncio não encontrado'; END IF;
  END IF;
  RETURN jsonb_build_object('id', v_id);
END $mkyfn$;
