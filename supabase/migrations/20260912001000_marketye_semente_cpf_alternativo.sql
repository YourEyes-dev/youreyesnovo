-- =====================================================================
-- MARKETYE · SEMENTE DO MOBILIÁRIO DE TESTE: CPF ALTERNATIVO E NOVA TENTATIVA
--
-- A corrida seguinte ao 20260912000100 continuou sem o anúncio na vitrine do
-- ambiente de teste, e o passo da esteira que chamaria a função a cada
-- corrida está pulado (segredo QA_E2E_TOKEN ausente). Hipótese mais forte:
-- o CPF fictício da semente (900.000.012-28) já foi usado num cadastro de
-- teste feito à mão, e o índice único de documento recusou a inserção.
--
-- O que muda na função: escolhe o primeiro CPF fictício livre de uma lista
-- (todos da faixa da casa, com DV válido), aceita o tenant por nome
-- aproximado e informa o CPF usado no diagnóstico. Roda de novo aqui.
-- Para ver o diagnóstico no ambiente de teste: SELECT public.marketye_semear_ilha_teste();
--
-- Não entra no script de entrega (mobiliário fictício do ambiente de teste).
-- =====================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.marketye_semear_ilha_teste()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_semear_ilha_teste$
DECLARE
  v_staging uuid; v_prof uuid; v_cat_pgr uuid; v_cat_aep uuid; v_anuncios int; v_motivo text; v_cpf text;
BEGIN
  SELECT id INTO v_staging FROM public.tenants WHERE nome = 'Empresa Staging LTDA' LIMIT 1;
  IF v_staging IS NULL THEN
    -- id fixo da ilha de teste (supabase/seeds/staging.sql); só vale se for mesmo a empresa de teste
    SELECT id INTO v_staging FROM public.tenants WHERE id = '11111111-1111-1111-1111-111111111111' AND nome ILIKE '%staging%';
  END IF;
  IF v_staging IS NULL THEN
    SELECT id INTO v_staging FROM public.tenants WHERE nome ILIKE 'Empresa Staging%' ORDER BY created_at LIMIT 1;
  END IF;
  IF v_staging IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'sem Empresa Staging neste banco (esperado fora do ambiente de teste)');
  END IF;

  -- CPF fictício da casa (faixa 900.000.0XX, DV válido). Se alguém já usou o
  -- primeiro num cadastro de teste, o índice único recusaria: pega o próximo livre.
  SELECT c INTO v_cpf FROM unnest(ARRAY['90000001228', '90000003000', '90000003190', '90000003271']) AS c
  WHERE NOT EXISTS (SELECT 1 FROM public.marketplace_profissionais p
                    WHERE public.marketye_so_digitos(p.cpf_cnpj) = c AND p.excluido_em IS NULL AND p.email <> 'especialista.staging@youreyes.local')
  LIMIT 1;
  IF v_cpf IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'todos os CPFs fictícios da semente já estão em uso por outros cadastros');
  END IF;

  SELECT id INTO v_cat_pgr FROM public.marketplace_categorias WHERE slug = 'pgr';
  SELECT id INTO v_cat_aep FROM public.marketplace_categorias WHERE slug = 'aep-aet';

  SELECT id INTO v_prof FROM public.marketplace_profissionais WHERE email = 'especialista.staging@youreyes.local' LIMIT 1;

  IF v_prof IS NULL THEN
    INSERT INTO public.marketplace_profissionais
      (user_id, tenant_id, nome_completo, email, telefone, cpf_cnpj, tipo_pessoa, bio, formacao_academica, registro_profissional, conselho, uf_registro,
       certificacoes, especialidades, areas_atuacao, modalidades_atendimento, cidade, estado, latitude, longitude, atende_remoto, raio_atendimento_km,
       aceite_codigo_etica, aceite_codigo_etica_data, status, plano, selo_verificado, moderacao_resultado, moderado_em, consentimento_versao, consentimento_em, origem_cadastro)
    VALUES
      (NULL, v_staging, 'Especialista Staging (QA)', 'especialista.staging@youreyes.local', '(46) 90000-0000', v_cpf, 'pf',
       'Perfil fictício do ambiente de teste. Engenheira de segurança do trabalho com atuação em PGR e laudos. Nada aqui é real.',
       'Engenharia de Segurança do Trabalho (fictícia)', 'QA-000001', 'CREA', 'PR', ARRAY['NR-1 (fictício)'], ARRAY['PGR', 'LTCAT', 'Ergonomia'],
       ARRAY['PGR', 'Laudos'], ARRAY['presencial', 'online']::public.marketplace_servico_modalidade[], 'Pato Branco', 'PR', -26.2292, -52.6706, true, 150,
       true, now(), 'ativo', 'base', true, 'aprovado', now(), '2026-09-v1', now(), 'ilha_teste')
    RETURNING id INTO v_prof;
    v_motivo := 'semeado';
  ELSE
    -- Já existia: garante que está visível na vitrine (o teste de tela depende disto).
    UPDATE public.marketplace_profissionais
       SET status = 'ativo', selo_verificado = true, excluido_em = NULL, moderacao_resultado = 'aprovado',
           moderado_em = COALESCE(moderado_em, now()), tenant_id = COALESCE(tenant_id, v_staging)
     WHERE id = v_prof;
    v_motivo := 'já existia (reparado)';
  END IF;

  INSERT INTO public.marketplace_consentimentos (profissional_id, tipo, versao, origem)
  SELECT v_prof, t.tipo, t.versao, 'ilha_teste'
  FROM (VALUES ('termos_especialista', '2026-09-v1'), ('privacidade_nao_usuario', '2026-09-v1'), ('codigo_etica', '2026-02-v1')) AS t(tipo, versao)
  WHERE NOT EXISTS (SELECT 1 FROM public.marketplace_consentimentos c WHERE c.profissional_id = v_prof AND c.tipo = t.tipo AND c.versao = t.versao);
  INSERT INTO public.marketplace_reputacao (profissional_id) VALUES (v_prof) ON CONFLICT (profissional_id) DO NOTHING;

  IF NOT EXISTS (SELECT 1 FROM public.marketplace_servicos WHERE profissional_id = v_prof AND nome = 'PGR completo com inventário de riscos (teste)') THEN
    INSERT INTO public.marketplace_servicos (profissional_id, categoria_id, nome, descricao, base_legal, modalidade, publico_alvo, preco_referencia, tipo_preco, duracao_estimada_minutos,
                                             tags, obrigacao_legal, prazo_tipico, ativo, status, publicado_em, promocao_percentual, promocao_inicio, promocao_fim, promocao_descricao)
    VALUES (v_prof, v_cat_pgr, 'PGR completo com inventário de riscos (teste)', 'Elaboração fictícia do Programa de Gerenciamento de Riscos com visita técnica, inventário e plano de ação. Anúncio do ambiente de teste.',
            'NR-1', 'hibrido', 'Empresas de 10 a 200 colaboradores', 2500, 'pacote', 480, ARRAY['pgr', 'nr-1', 'inventario'], ARRAY['NR-1'], '15 dias úteis', true, 'publicado', now(),
            10, CURRENT_DATE - 1, CURRENT_DATE + 60, 'Primeira contratação com 10% de desconto (teste)');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.marketplace_servicos WHERE profissional_id = v_prof AND nome = 'Análise Ergonômica Preliminar — AEP (teste)') THEN
    INSERT INTO public.marketplace_servicos (profissional_id, categoria_id, nome, descricao, base_legal, modalidade, publico_alvo, preco_referencia, tipo_preco, duracao_estimada_minutos,
                                             tags, obrigacao_legal, prazo_tipico, ativo, status, publicado_em)
    VALUES (v_prof, v_cat_aep, 'Análise Ergonômica Preliminar — AEP (teste)', 'Avaliação ergonômica preliminar fictícia por posto de trabalho, com relatório e recomendações. Anúncio do ambiente de teste.',
            'NR-17', 'presencial', 'Escritórios e indústrias', 180, 'hora', 120, ARRAY['ergonomia', 'aep', 'nr-17'], ARRAY['NR-17'], '5 dias úteis', true, 'publicado', now());
  END IF;
  -- Reparo dos anúncios (categoria certa, publicados e ativos), para o caso de terem sido pausados/removidos em testes manuais.
  UPDATE public.marketplace_servicos SET status = 'publicado', ativo = true, publicado_em = COALESCE(publicado_em, now()),
         categoria_id = CASE WHEN nome LIKE 'PGR completo%' THEN COALESCE(v_cat_pgr, categoria_id) ELSE COALESCE(v_cat_aep, categoria_id) END
   WHERE profissional_id = v_prof AND nome IN ('PGR completo com inventário de riscos (teste)', 'Análise Ergonômica Preliminar — AEP (teste)');

  SELECT count(*) INTO v_anuncios FROM public.marketplace_servicos WHERE profissional_id = v_prof AND status = 'publicado' AND ativo;
  RETURN jsonb_build_object('ok', true, 'motivo', v_motivo, 'profissional_id', v_prof, 'tenant_id', v_staging, 'anuncios_publicados', v_anuncios, 'cpf_usado', v_cpf,
                            'categoria_pgr', v_cat_pgr IS NOT NULL, 'categoria_aep', v_cat_aep IS NOT NULL);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'erro', SQLERRM, 'sqlstate', SQLSTATE);
END $marketye_semear_ilha_teste$;
REVOKE ALL ON FUNCTION public.marketye_semear_ilha_teste() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.marketye_semear_ilha_teste() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.marketye_semear_ilha_teste() TO service_role;

DO $semente$
DECLARE v jsonb;
BEGIN
  v := public.marketye_semear_ilha_teste();
  RAISE NOTICE 'MarketYE · mobiliário de teste (nova tentativa): %', v;
END $semente$;
