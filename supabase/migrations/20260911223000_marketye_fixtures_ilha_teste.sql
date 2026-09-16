-- =====================================================================
-- MARKETYE · MOBILIÁRIO DA ILHA DE TESTE (só onde existe a Empresa Staging)
--
-- Semeia um especialista fictício já verificado, com dois anúncios
-- publicados, para que a vitrine do ambiente de teste tenha o que mostrar
-- e os testes de tela (MKY-020/021) encontrem um card. Roda só quando o
-- tenant 'Empresa Staging LTDA' existe (ambiente de teste); em qualquer
-- outro banco é um no-op com aviso.
--
-- Não gera script de entrega: é dado fictício, exclusivo do ambiente de
-- teste. CPF da faixa da casa (900.000.0XX com DV válido). Nada real.
-- Idempotente: sentinela pelo e-mail do especialista.
-- =====================================================================

SET lock_timeout = '10s';

DO $seed_mky$
DECLARE v_staging uuid; v_prof uuid; v_cat_pgr uuid; v_cat_aep uuid;
BEGIN
  SELECT id INTO v_staging FROM public.tenants WHERE nome = 'Empresa Staging LTDA' LIMIT 1;
  IF v_staging IS NULL THEN
    RAISE NOTICE 'MarketYE: tenant Empresa Staging LTDA ausente — mobiliário de teste não semeado (esperado fora do ambiente de teste).';
    RETURN;
  END IF;
  IF EXISTS (SELECT 1 FROM public.marketplace_profissionais WHERE email = 'especialista.staging@youreyes.local') THEN
    RAISE NOTICE 'MarketYE: mobiliário de teste já existe.';
    RETURN;
  END IF;

  INSERT INTO public.marketplace_profissionais
    (user_id, tenant_id, nome_completo, email, telefone, cpf_cnpj, tipo_pessoa, bio, formacao_academica, registro_profissional, conselho, uf_registro,
     certificacoes, especialidades, areas_atuacao, modalidades_atendimento, cidade, estado, latitude, longitude, atende_remoto, raio_atendimento_km,
     aceite_codigo_etica, aceite_codigo_etica_data, status, plano, selo_verificado, moderacao_resultado, moderado_em, consentimento_versao, consentimento_em, origem_cadastro)
  VALUES
    (NULL, v_staging, 'Especialista Staging (QA)', 'especialista.staging@youreyes.local', '(46) 90000-0000', '90000001228', 'pf',
     'Perfil fictício do ambiente de teste. Engenheira de segurança do trabalho com atuação em PGR e laudos. Nada aqui é real.',
     'Engenharia de Segurança do Trabalho (fictícia)', 'QA-000001', 'CREA', 'PR', ARRAY['NR-1 (fictício)'], ARRAY['PGR', 'LTCAT', 'Ergonomia'],
     ARRAY['PGR', 'Laudos'], ARRAY['presencial', 'online']::public.marketplace_servico_modalidade[], 'Pato Branco', 'PR', -26.2292, -52.6706, true, 150,
     true, now(), 'ativo', 'base', true, 'aprovado', now(), '2026-09-v1', now(), 'ilha_teste')
  RETURNING id INTO v_prof;

  INSERT INTO public.marketplace_consentimentos (profissional_id, tipo, versao, origem)
  VALUES (v_prof, 'termos_especialista', '2026-09-v1', 'ilha_teste'), (v_prof, 'privacidade_nao_usuario', '2026-09-v1', 'ilha_teste'), (v_prof, 'codigo_etica', '2026-02-v1', 'ilha_teste');
  INSERT INTO public.marketplace_reputacao (profissional_id) VALUES (v_prof) ON CONFLICT (profissional_id) DO NOTHING;

  SELECT id INTO v_cat_pgr FROM public.marketplace_categorias WHERE slug = 'pgr';
  SELECT id INTO v_cat_aep FROM public.marketplace_categorias WHERE slug = 'aep-aet';

  INSERT INTO public.marketplace_servicos (profissional_id, categoria_id, nome, descricao, base_legal, modalidade, publico_alvo, preco_referencia, tipo_preco, duracao_estimada_minutos,
                                           tags, obrigacao_legal, prazo_tipico, ativo, status, publicado_em, promocao_percentual, promocao_inicio, promocao_fim, promocao_descricao)
  VALUES
    (v_prof, v_cat_pgr, 'PGR completo com inventário de riscos (teste)', 'Elaboração fictícia do Programa de Gerenciamento de Riscos com visita técnica, inventário e plano de ação. Anúncio do ambiente de teste.',
     'NR-1', 'hibrido', 'Empresas de 10 a 200 colaboradores', 2500, 'pacote', 480, ARRAY['pgr', 'nr-1', 'inventario'], ARRAY['NR-1'], '15 dias úteis', true, 'publicado', now(),
     10, CURRENT_DATE - 1, CURRENT_DATE + 60, 'Primeira contratação com 10% de desconto (teste)'),
    (v_prof, v_cat_aep, 'Análise Ergonômica Preliminar — AEP (teste)', 'Avaliação ergonômica preliminar fictícia por posto de trabalho, com relatório e recomendações. Anúncio do ambiente de teste.',
     'NR-17', 'presencial', 'Escritórios e indústrias', 180, 'hora', 120, ARRAY['ergonomia', 'aep', 'nr-17'], ARRAY['NR-17'], '5 dias úteis', true, 'publicado', now(), NULL, NULL, NULL, NULL);

  RAISE NOTICE 'MarketYE: mobiliário de teste semeado (especialista % com 2 anúncios).', v_prof;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'MarketYE: mobiliário de teste não semeado: %', SQLERRM;
END $seed_mky$;
