-- ============================================================================
-- Fase 4 (motores) — Marketplace: ciclo do anúncio removido e exportação LGPD.
--
-- MKY-053: anúncio REMOVIDO é terminal — não volta por publicar nem ressuscita
--          por salvar (precisa de anúncio novo).
-- MKY-090: exportação de dados do especialista inclui os cupons.
--
-- Lógica em funções SECURITY DEFINER. Conferir a família MKY no ambiente de
-- teste (parte dos casos de RLS não reproduz na réplica local).
-- ============================================================================

-- ── MKY-053: publicar não ressuscita anúncio removido ───────────────────────
CREATE OR REPLACE FUNCTION public.marketye_anuncio_publicar(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $mkyfn$
DECLARE v_prof uuid := public.marketye_meu_id(); s record; p record; c record;
BEGIN
  IF v_prof IS NULL THEN RAISE EXCEPTION 'Sem cadastro de especialista'; END IF;
  SELECT * INTO s FROM public.marketplace_servicos WHERE id = p_id AND profissional_id = v_prof;
  IF s.id IS NULL THEN RAISE EXCEPTION 'Anúncio não encontrado'; END IF;
  -- Removido é terminal: não volta pela publicação; crie um anúncio novo.
  IF s.status = 'removido' THEN
    RAISE EXCEPTION 'Anúncio removido não pode ser republicado. Crie um novo anúncio.';
  END IF;
  SELECT * INTO p FROM public.marketplace_profissionais WHERE id = v_prof;
  IF p.status::text <> 'ativo' THEN
    RAISE EXCEPTION 'Seu cadastro ainda está em verificação. O anúncio fica salvo e aparece na vitrine assim que a verificação concluir.';
  END IF;
  IF p.excluido_em IS NOT NULL THEN RAISE EXCEPTION 'Perfil excluído'; END IF;
  IF s.categoria_id IS NOT NULL THEN
    SELECT * INTO c FROM public.marketplace_categorias WHERE id = s.categoria_id;
    IF c.exige_registro AND (p.registro_profissional IS NULL OR p.conselho IS NULL) THEN
      RAISE EXCEPTION 'Para publicar em %, informe seu registro profissional (%).', c.nome, COALESCE(array_to_string(c.conselhos_aceitos, '/'), 'conselho');
    END IF;
  END IF;
  IF public.marketye_texto_tem_contato(s.nome) OR public.marketye_texto_tem_contato(s.descricao) THEN
    RAISE EXCEPTION 'Remova telefones, e-mails ou links do texto — o contato acontece pelo MarketYE.';
  END IF;
  UPDATE public.marketplace_servicos SET status = 'publicado', ativo = true, publicado_em = COALESCE(publicado_em, now()) WHERE id = p_id;
  RETURN jsonb_build_object('id', p_id, 'status', 'publicado');
END $mkyfn$;

-- ── MKY-053: salvar não ressuscita anúncio removido ─────────────────────────
-- (Reaplica as travas de preço/promoção de MKY-052/054 e remove a "ressurreição"
--  removido→rascunho: editar um removido mantém removido.)
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
  IF NULLIF(_dados->>'promocao_percentual', '') IS NOT NULL THEN
    IF (_dados->>'promocao_percentual')::numeric <= 0 OR (_dados->>'promocao_percentual')::numeric > 90 THEN
      RAISE EXCEPTION 'Percentual de promoção inválido: informe um valor entre 1%% e 90%%.';
    END IF;
  END IF;
  IF NULLIF(_dados->>'preco_minimo', '') IS NOT NULL AND NULLIF(_dados->>'preco_maximo', '') IS NOT NULL
     AND (_dados->>'preco_minimo')::numeric > (_dados->>'preco_maximo')::numeric THEN
    _dados := _dados || jsonb_build_object('preco_minimo', _dados->'preco_maximo', 'preco_maximo', _dados->'preco_minimo');
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
      promocao_fim = NULLIF(_dados->>'promocao_fim', '')::date, promocao_descricao = NULLIF(_dados->>'promocao_descricao', '')
      -- (sem ressurreição: um anúncio removido permanece removido)
    WHERE id = v_id AND profissional_id = v_prof;
    IF NOT FOUND THEN RAISE EXCEPTION 'Anúncio não encontrado'; END IF;
  END IF;
  RETURN jsonb_build_object('id', v_id);
END $mkyfn$;

-- ── MKY-090: exportação inclui os cupons ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.marketye_exportar_meus_dados()
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $mkyfn$
  SELECT jsonb_build_object(
    'perfil', (SELECT to_jsonb(p) - 'user_id' FROM public.marketplace_profissionais p WHERE p.id = public.marketye_meu_id()),
    'anuncios', (SELECT COALESCE(jsonb_agg(to_jsonb(s)), '[]'::jsonb) FROM public.marketplace_servicos s WHERE s.profissional_id = public.marketye_meu_id()),
    'leads', (SELECT COALESCE(jsonb_agg(to_jsonb(l) - 'criado_por'), '[]'::jsonb) FROM public.marketplace_leads l WHERE l.profissional_id = public.marketye_meu_id()),
    'avaliacoes', (SELECT COALESCE(jsonb_agg(to_jsonb(a) - 'avaliador_id'), '[]'::jsonb) FROM public.marketplace_avaliacoes a WHERE a.profissional_id = public.marketye_meu_id()),
    'consentimentos', (SELECT COALESCE(jsonb_agg(to_jsonb(c)), '[]'::jsonb) FROM public.marketplace_consentimentos c WHERE c.profissional_id = public.marketye_meu_id()),
    'contestacoes', (SELECT COALESCE(jsonb_agg(to_jsonb(c)), '[]'::jsonb) FROM public.marketplace_contestacoes c WHERE c.profissional_id = public.marketye_meu_id()),
    'cupons', (SELECT COALESCE(jsonb_agg(to_jsonb(cp)), '[]'::jsonb) FROM public.marketplace_cupons cp WHERE cp.profissional_id = public.marketye_meu_id()),
    'autonomia', (SELECT COALESCE(jsonb_agg(to_jsonb(e)), '[]'::jsonb) FROM public.marketplace_autonomia_eventos e WHERE e.profissional_id = public.marketye_meu_id()),
    'exportado_em', now());
$mkyfn$;
