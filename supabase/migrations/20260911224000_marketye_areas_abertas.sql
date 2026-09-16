-- =====================================================================
-- MARKETYE · ÁREAS ABERTAS A TODO TIPO DE PRESTADOR
--
-- Decisão do dono do produto (11/09/2026): o MarketYE é para qualquer
-- serviço prestado a empresas — treinamentos, consultorias, palestras,
-- contabilidade, fisioterapia, manutenção... — sem prender o prestador a
-- rótulos fixos. A árvore de áreas continua existindo (ela alimenta o
-- encaixe com as obrigações legais das empresas), mas passa a ter raízes
-- genéricas para o que não é SST/RH e uma raiz "Outros serviços" que
-- acolhe qualquer coisa. Na tela, a área é sugestão, nunca obrigação: o
-- prestador descreve o que faz em uma frase e a IA sugere a área.
--
-- Idempotente: só INSERT com WHERE NOT EXISTS por slug.
-- =====================================================================

SET lock_timeout = '10s';

INSERT INTO public.marketplace_categorias (nome, descricao, icone, ordem, ativo, slug, obrigacao_legal, exige_registro, conselhos_aceitos, aliases)
SELECT v.nome, v.descricao, v.icone, v.ordem, true, v.slug, '{}'::text[], false, '{}'::text[], v.aliases
FROM (VALUES
  ('Manutenção e instalações', 'Manutenção predial, elétrica, ar-condicionado, equipamentos e instalações', 'Wrench', 30, 'manutencao-instalacoes',
   ARRAY['manutencao','manutenção','ar-condicionado','eletrica','elétrica','hidraulica','predial','instalacao','instalação','reforma','equipamentos','limpeza']),
  ('Palestras e eventos', 'Palestras, workshops, SIPAT, dinâmicas e eventos corporativos', 'Mic', 31, 'palestras-eventos',
   ARRAY['palestra','palestrante','evento','sipat','workshop','dinamica','dinâmica','motivacional','semana']),
  ('Consultoria e gestão', 'Consultoria empresarial, processos, qualidade, ESG e gestão', 'Compass', 32, 'consultoria-gestao',
   ARRAY['consultoria','consultor','gestao','gestão','processos','qualidade','iso','esg','lean','planejamento']),
  ('Saúde e bem-estar', 'Nutrição, fisioterapia, psicologia clínica, atividade física e bem-estar no trabalho', 'HeartHandshake', 33, 'saude-bem-estar',
   ARRAY['nutricao','nutrição','nutricionista','fisioterapeuta','bem-estar','massagem','quick massage','yoga','meditacao','meditação','qualidade de vida']),
  ('Outros serviços', 'Qualquer outro serviço prestado a empresas', 'Sparkles', 99, 'outros-servicos',
   ARRAY['outros','diversos','geral'])
) AS v(nome, descricao, icone, ordem, slug, aliases)
WHERE NOT EXISTS (SELECT 1 FROM public.marketplace_categorias c WHERE c.slug = v.slug);

-- Sinônimos que ajudam a busca em linguagem natural a cair na raiz certa.
UPDATE public.marketplace_categorias SET aliases = aliases || ARRAY['curso','capacitacao','capacitação','instrutor','treinamento in company']
WHERE slug = 'treinamentos' AND NOT ('instrutor' = ANY(aliases));
UPDATE public.marketplace_categorias SET aliases = aliases || ARRAY['contador','escritorio contabil','escritório contábil','fiscal','folha de pagamento']
WHERE slug = 'contabil-fiscal' AND NOT ('contador' = ANY(aliases));
UPDATE public.marketplace_categorias SET aliases = aliases || ARRAY['desenvolvimento de sistemas','suporte','infraestrutura','lgpd tecnica','seguranca da informacao']
WHERE slug = 'tecnologia' AND NOT ('suporte' = ANY(aliases));
