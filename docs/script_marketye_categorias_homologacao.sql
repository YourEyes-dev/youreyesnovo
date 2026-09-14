-- =====================================================================
-- SCRIPT DE ENTREGA (complemento) — Categorias-base do MarketYE na HOMOLOGACAO
--
-- POR QUE: a homologacao nao tinha NENHUMA categoria-raiz do marketplace
-- (as 8 raizes de Fev/2026 nunca foram semeadas ali). O script do MarketYE
-- assume que essas raizes ja existem e so completa a arvore (slugs +
-- subcategorias). Sem as raizes, as subcategorias 'pgr'/'aep-aet' nao nascem,
-- os anuncios do seed ficam sem categoria e o teste MKY-021 (filtro por
-- 'seguranca-trabalho') nao acha anuncio.
--
-- O QUE FAZ: garante as colunas da taxonomia, semeia as 8 raizes base e
-- reconstroi a arvore (slugs por nome + subcategorias por slug). 100%
-- idempotente (IF NOT EXISTS / WHERE NOT EXISTS / ON CONFLICT). Uma transacao.
--
-- COMO USAR: cole o arquivo INTEIRO no SQL Editor da HOMOLOGACAO
-- (fgsblefvdabgdouipigz) e rode. A ultima linha e uma conferencia.
-- Depois disso, a proxima corrida do seed categoriza os anuncios sozinha.
-- =====================================================================

SET lock_timeout = '10s';

-- 1) Colunas da taxonomia (o script principal ja pode ter adicionado; IF NOT EXISTS).
ALTER TABLE public.marketplace_categorias
  ADD COLUMN IF NOT EXISTS slug              text,
  ADD COLUMN IF NOT EXISTS pai_id            uuid REFERENCES public.marketplace_categorias(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS aliases           text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS obrigacao_legal   text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS exige_registro    boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS conselhos_aceitos text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS jurisdicao        text NOT NULL DEFAULT 'BR',
  ADD COLUMN IF NOT EXISTS versao            int NOT NULL DEFAULT 1;

-- 2) Raizes-base do marketplace (Fev/2026), que faltam na homologacao.
INSERT INTO public.marketplace_categorias (nome, descricao, icone, ordem)
SELECT v.nome, v.descricao, v.icone, v.ordem
FROM (VALUES
  ('Segurança do Trabalho', 'Serviços de SST, laudos técnicos, PPRA, PCMSO', 'Shield', 1),
  ('Ergonomia', 'Análises ergonômicas, AEP, AET, laudos ergonômicos', 'Activity', 2),
  ('Saúde Ocupacional', 'Exames ocupacionais, ASO, medicina do trabalho', 'Stethoscope', 3),
  ('Saúde Mental', 'Psicologia organizacional, apoio psicossocial', 'Brain', 4),
  ('Fisioterapia', 'Ginástica laboral, reabilitação, fisioterapia preventiva', 'HeartPulse', 5),
  ('Treinamentos', 'NRs, capacitações obrigatórias, workshops', 'GraduationCap', 6),
  ('Jurídico Trabalhista', 'Consultoria jurídica, compliance trabalhista', 'Scale', 7),
  ('RH Estratégico', 'Consultoria em gestão de pessoas, clima organizacional', 'Users', 8)
) AS v(nome, descricao, icone, ordem)
WHERE NOT EXISTS (
  SELECT 1 FROM public.marketplace_categorias c WHERE c.nome = v.nome AND c.pai_id IS NULL
);

-- 3) Slugs nas raizes + subcategorias (pgr/aep-aet/...) — extraido do fundacao.
UPDATE public.marketplace_categorias SET slug = CASE nome
  WHEN 'Segurança do Trabalho' THEN 'seguranca-trabalho'
  WHEN 'Ergonomia' THEN 'ergonomia'
  WHEN 'Saúde Ocupacional' THEN 'saude-ocupacional'
  WHEN 'Saúde Mental' THEN 'saude-mental'
  WHEN 'Fisioterapia' THEN 'fisioterapia'
  WHEN 'Treinamentos' THEN 'treinamentos'
  WHEN 'Jurídico Trabalhista' THEN 'juridico-trabalhista'
  WHEN 'RH Estratégico' THEN 'rh-estrategico'
  ELSE lower(regexp_replace(translate(nome, 'áàâãéêíóôõúçÁÀÂÃÉÊÍÓÔÕÚÇ', 'aaaaeeiooouc' || 'AAAAEEIOOOUC'), '[^A-Za-z0-9]+', '-', 'g')) END
WHERE slug IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_marketplace_categorias_slug ON public.marketplace_categorias (jurisdicao, slug) WHERE slug IS NOT NULL;

-- Raízes que faltam (a árvore antiga só tinha 8 raízes) + subcategorias do
-- beachhead SST/RH (2.3). Cada subcategoria já nasce amarrada à obrigação
-- legal que atende (7.3) e diz se exige registro profissional (RN-011 —
-- a lista fechada ainda passa por advogado).
INSERT INTO public.marketplace_categorias (nome, descricao, icone, ordem, ativo, slug, obrigacao_legal, exige_registro, conselhos_aceitos, aliases) VALUES
  ('Contábil e Fiscal', 'Contabilidade, folha, eSocial e obrigações fiscais', 'Calculator', 20, true, 'contabil-fiscal', '{}', false, '{CRC}', '{contador,contabilidade,esocial}'),
  ('Tecnologia', 'TI, sistemas e segurança da informação', 'Cpu', 21, true, 'tecnologia', '{}', false, '{}', '{ti,software,sistemas}')
ON CONFLICT DO NOTHING;

WITH raiz AS (SELECT id, slug FROM public.marketplace_categorias WHERE pai_id IS NULL AND slug IS NOT NULL)
INSERT INTO public.marketplace_categorias (nome, descricao, icone, ordem, ativo, slug, pai_id, obrigacao_legal, exige_registro, conselhos_aceitos, aliases)
SELECT v.nome, v.descricao, v.icone, v.ordem, true, v.slug, r.id, v.obrigacao, v.exige_registro, v.conselhos, v.aliases
FROM (VALUES
  ('seguranca-trabalho', 'PGR — Programa de Gerenciamento de Riscos', 'Elaboração e revisão do PGR e inventário de riscos', 'ShieldCheck', 1, 'pgr', '{NR-1}'::text[], true, '{CREA,MTE}'::text[], '{pgr,gerenciamento de riscos,inventario de riscos,ppra}'::text[]),
  ('seguranca-trabalho', 'LTCAT, insalubridade e periculosidade', 'Laudos técnicos das condições ambientais e adicionais', 'FileText', 2, 'ltcat-laudos', '{NR-15,NR-16}', true, '{CREA,CRM}', '{ltcat,laudo,insalubridade,periculosidade,ruido}'),
  ('seguranca-trabalho', 'Técnico de Segurança do Trabalho', 'Atuação in loco, inspeções, DDS e ordens de serviço', 'HardHat', 3, 'tecnico-seguranca', '{NR-1,NR-4}', true, '{MTE}', '{tst,tecnico de seguranca,sesmt}'),
  ('seguranca-trabalho', 'CIPA e Brigada de Incêndio', 'Implantação e treinamento de CIPA e brigada', 'Flame', 4, 'cipa-brigada', '{NR-5,NR-23}', false, '{}', '{cipa,brigada,incendio}'),
  ('seguranca-trabalho', 'EPI e gestão de riscos operacionais', 'Especificação de EPI, matriz de riscos, APR', 'Shield', 5, 'epi-riscos', '{NR-6}', false, '{}', '{epi,apr,matriz de risco}'),
  ('saude-ocupacional', 'Médico do Trabalho / PCMSO', 'Coordenação do PCMSO e exames ocupacionais', 'Stethoscope', 1, 'pcmso', '{NR-7}', true, '{CRM}', '{pcmso,medico do trabalho,aso,exame admissional}'),
  ('saude-ocupacional', 'Exames complementares e audiometria', 'Audiometria, espirometria e exames complementares', 'Activity', 2, 'exames-complementares', '{NR-7}', true, '{CRM,CFFa}', '{audiometria,espirometria,exames}'),
  ('saude-ocupacional', 'Enfermagem do trabalho', 'Enfermagem ocupacional e campanhas de saúde', 'HeartPulse', 3, 'enfermagem-trabalho', '{NR-7}', true, '{COREN}', '{enfermagem,enfermeiro do trabalho}'),
  ('ergonomia', 'AEP e AET — Análise Ergonômica', 'Avaliação ergonômica preliminar e do trabalho', 'Ruler', 1, 'aep-aet', '{NR-17}', true, '{CREFITO,CREA,CRM}', '{aep,aet,laudo ergonomico,ergonomista}'),
  ('ergonomia', 'Ginástica laboral', 'Programas de ginástica laboral e pausas ativas', 'Dumbbell', 2, 'ginastica-laboral', '{NR-17}', true, '{CREF,CREFITO}', '{ginastica laboral,pausa ativa}'),
  ('saude-mental', 'Gestão de riscos psicossociais (NR-1)', 'Diagnóstico, plano e acompanhamento dos fatores psicossociais', 'Brain', 1, 'psicossocial-nr1', '{NR-1}', true, '{CRP}', '{psicossocial,nr-1,riscos psicossociais,burnout}'),
  ('saude-mental', 'Psicologia organizacional', 'Clima, escuta e apoio psicológico organizacional', 'Users', 2, 'psicologia-organizacional', '{NR-1}', true, '{CRP}', '{psicologo,clima,escuta}'),
  ('treinamentos', 'Treinamentos NR (10, 12, 33, 35)', 'Capacitações obrigatórias por norma regulamentadora', 'GraduationCap', 1, 'treinamentos-nr', '{NR-10,NR-12,NR-33,NR-35}', false, '{}', '{nr-10,nr-35,nr-33,nr-12,treinamento,capacitacao}'),
  ('treinamentos', 'Primeiros socorros e emergências', 'Treinamento de primeiros socorros e plano de emergência', 'Siren', 2, 'primeiros-socorros', '{NR-7}', false, '{}', '{primeiros socorros,emergencia}'),
  ('juridico-trabalhista', 'Consultoria trabalhista e sindical', 'Assessoria trabalhista, acordos e convenções', 'Scale', 1, 'consultoria-trabalhista', '{}', true, '{OAB}', '{advogado,trabalhista,sindicato,convencao}'),
  ('rh-estrategico', 'Recrutamento e seleção', 'Atração, triagem e seleção de pessoas', 'UserSearch', 1, 'recrutamento', '{}', false, '{}', '{recrutamento,selecao,vagas}'),
  ('rh-estrategico', 'Treinamento e desenvolvimento', 'Trilhas, liderança e desenvolvimento de equipes', 'BookOpen', 2, 'treinamento-desenvolvimento', '{}', false, '{}', '{t&d,desenvolvimento,lideranca}'),
  ('rh-estrategico', 'Cargos, salários e departamento pessoal', 'Estrutura de cargos, folha e rotinas de DP', 'Briefcase', 3, 'cargos-salarios-dp', '{}', false, '{}', '{cargos,salarios,dp,departamento pessoal}'),
  ('fisioterapia', 'Fisioterapia ocupacional', 'Reabilitação e prevenção de lesões no trabalho', 'Accessibility', 1, 'fisioterapia-ocupacional', '{NR-17}', true, '{CREFITO}', '{fisioterapia,ler,dort,reabilitacao}'),
  ('contabil-fiscal', 'eSocial e obrigações acessórias', 'Eventos de SST no eSocial (S-2210, S-2220, S-2240)', 'FileSpreadsheet', 1, 'esocial-sst', '{eSocial}', false, '{CRC}', '{esocial,s-2240,s-2220,s-2210}')
) AS v(raiz_slug, nome, descricao, icone, ordem, slug, obrigacao, exige_registro, conselhos, aliases)
JOIN raiz r ON r.slug = v.raiz_slug
WHERE NOT EXISTS (SELECT 1 FROM public.marketplace_categorias c WHERE c.slug = v.slug);

-- ===================================================================
-- CONFERENCIA (o SQL Editor mostra so o ultimo resultado)
-- ===================================================================
SELECT
  (SELECT count(*) FROM public.marketplace_categorias WHERE pai_id IS NULL AND slug IS NOT NULL) AS raizes_com_slug,
  (SELECT count(*) FROM public.marketplace_categorias WHERE slug = 'seguranca-trabalho') AS tem_seguranca_trabalho,
  (SELECT count(*) FROM public.marketplace_categorias WHERE slug = 'pgr')                AS tem_pgr,
  (SELECT count(*) FROM public.marketplace_categorias WHERE slug = 'aep-aet')            AS tem_aep_aet;
