-- =====================================================================
-- MARKETYE · FUNDAÇÃO DO MARKETPLACE DE SERVIÇOS (antiga "Rede de Parceiros")
--
-- POR QUE ESTA MIGRATION EXISTE
-- O módulo /marketplace já tinha profissionais, serviços, contratações,
-- avaliações e denúncias, mas nascia com quatro lacunas apontadas no
-- documento de requisitos do MarketYE (v2.0, 11/09/2026):
--   1. Todo dado sensível do prestador (status, selo, nota) mudava por
--      UPDATE direto de tabela exposta — a mesma classe de brecha da
--      assinatura por anônimo. Agora há uma GUARDA por trigger: essas
--      colunas só mudam por função do sistema (RN-021 / CA-013).
--   2. E-mail, telefone e CPF/CNPJ do prestador eram lidos por qualquer
--      usuário autenticado de qualquer empresa. Agora a leitura direta fica
--      restrita às colunas públicas; o contato sai só pelo lead liberado
--      (RN-020, LGPD).
--   3. nota_media / total_avaliacoes nunca eram recalculados por ninguém, e
--      qualquer membro de empresa podia avaliar sem contratação. Agora a
--      avaliação passa pela função marketye_avaliar (só transação
--      verificada, RN-004) e a reputação é apurada em dois eixos (RN-005).
--   4. Não existia lead, parametrização versionada, consentimento LGPD do
--      não-usuário, contestação com pessoa decidindo, trilha de autonomia
--      nem demanda latente — tudo isso entra aqui.
--
-- LÉXICO (RN-028): nada aqui se chama infração, punição, sanção ou demoção.
-- Os nomes são ocorrência, reflexo na visibilidade e ajuste de nível. Nenhum
-- ajuste bloqueia o prestador de trabalhar ou de definir preço (RN-029).
--
-- ESCOPO DESTA ONDA (MVP conexão/lead): nada de pagamento intra-plataforma,
-- split ou escrow — é GATE jurídico pré-build (seção 14). O destaque pago
-- entra só como camada rotulada e parametrizada; a cobrança fica para depois.
--
-- Idempotente: colunas com IF NOT EXISTS, políticas recriadas, funções
-- CREATE OR REPLACE, seeds com ON CONFLICT. Rodar de novo não duplica.
-- Não altera nem apaga dado existente: só cria estrutura e preenche colunas
-- novas com o valor neutro (slug das categorias, status 'publicado' nos
-- serviços que já estavam ativos).
-- =====================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- 0) Utilitários
-- ---------------------------------------------------------------------

-- Só dígitos (CPF/CNPJ/telefone).
CREATE OR REPLACE FUNCTION public.marketye_so_digitos(p_texto text)
RETURNS text LANGUAGE sql IMMUTABLE AS $marketye_so_digitos$
  SELECT regexp_replace(COALESCE(p_texto, ''), '\D', '', 'g');
$marketye_so_digitos$;

-- Dígito verificador do CNPJ (o CPF já tem public.cpf_valido).
CREATE OR REPLACE FUNCTION public.marketye_cnpj_valido(p_cnpj text)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $marketye_cnpj_valido$
DECLARE d text := public.marketye_so_digitos(p_cnpj); s int; i int; p1 int[] := ARRAY[5,4,3,2,9,8,7,6,5,4,3,2]; p2 int[] := ARRAY[6,5,4,3,2,9,8,7,6,5,4,3,2]; dv1 int; dv2 int;
BEGIN
  IF length(d) <> 14 OR d ~ '^(\d)\1{13}$' THEN RETURN false; END IF;
  s := 0; FOR i IN 1..12 LOOP s := s + substr(d, i, 1)::int * p1[i]; END LOOP;
  dv1 := CASE WHEN s % 11 < 2 THEN 0 ELSE 11 - (s % 11) END;
  s := 0; FOR i IN 1..13 LOOP s := s + substr(d, i, 1)::int * p2[i]; END LOOP;
  dv2 := CASE WHEN s % 11 < 2 THEN 0 ELSE 11 - (s % 11) END;
  RETURN substr(d, 13, 1)::int = dv1 AND substr(d, 14, 1)::int = dv2;
END $marketye_cnpj_valido$;

-- CPF ou CNPJ válido (aceita formatado ou só dígitos).
CREATE OR REPLACE FUNCTION public.marketye_documento_valido(p_doc text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $marketye_documento_valido$
  SELECT CASE length(public.marketye_so_digitos(p_doc))
           WHEN 11 THEN public.cpf_valido(public.marketye_so_digitos(p_doc))
           WHEN 14 THEN public.marketye_cnpj_valido(p_doc)
           ELSE false END;
$marketye_documento_valido$;

-- O texto traz contato direto (telefone, e-mail, link, "me chama no zap")?
CREATE OR REPLACE FUNCTION public.marketye_texto_tem_contato(p_texto text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $marketye_texto_tem_contato$
  SELECT COALESCE(p_texto, '') ~* '[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}'
      OR COALESCE(p_texto, '') ~* '(https?://|www\.)[^\s]+'
      OR COALESCE(p_texto, '') ~ '(\(?\d{2}\)?[\s.-]?)?\d{4,5}[\s.-]?\d{4}'
      OR COALESCE(p_texto, '') ~* '\m(whats(app)?|zap|telegram|me liga|meu (fone|celular|telefone))\M';
$marketye_texto_tem_contato$;

-- Mascara contato direto até a liberação (RN-020).
CREATE OR REPLACE FUNCTION public.marketye_mascarar_contato(p_texto text)
RETURNS text LANGUAGE sql IMMUTABLE AS $marketye_mascarar_contato$
  SELECT regexp_replace(
           regexp_replace(
             regexp_replace(COALESCE(p_texto, ''), '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[contato oculto até a liberação]', 'g'),
             '(https?://|www\.)[^\s]+', '[link oculto até a liberação]', 'g'),
           '(\(?\d{2}\)?[\s.-]?)?\d{4,5}[\s.-]?\d{4}', '[telefone oculto até a liberação]', 'g');
$marketye_mascarar_contato$;

-- "Esta escrita veio por função do sistema?" Dentro das funções marketye_*
-- (SECURITY DEFINER, dono postgres) o usuário corrente é o dono; pela API o
-- usuário corrente é 'authenticated'. Sem marcador de sessão de propósito:
-- um marcador transação-local vazaria para escritas diretas feitas na mesma
-- transação.
CREATE OR REPLACE FUNCTION public.marketye_via_funcao()
RETURNS boolean LANGUAGE sql STABLE AS $marketye_via_funcao$
  SELECT current_user IN ('postgres', 'supabase_admin', 'service_role');
$marketye_via_funcao$;
DROP FUNCTION IF EXISTS public.marketye_marcar_via_funcao();

-- Quem sou eu como especialista (NULL se a conta não tem cadastro).
CREATE OR REPLACE FUNCTION public.marketye_meu_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $marketye_meu_id$
  SELECT id FROM public.marketplace_profissionais WHERE user_id = auth.uid() ORDER BY created_at LIMIT 1;
$marketye_meu_id$;
GRANT EXECUTE ON FUNCTION public.marketye_meu_id() TO authenticated;

-- ---------------------------------------------------------------------
-- 1) Parametrização versionada (RN-016 / CA-015)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.marketplace_config (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chave       text NOT NULL,
  versao      int  NOT NULL DEFAULT 1,
  valor       jsonb NOT NULL,
  descricao   text,
  vigente     boolean NOT NULL DEFAULT true,
  jurisdicao  text NOT NULL DEFAULT 'BR',
  criado_por  uuid,
  criado_em   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (chave, jurisdicao, versao)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_marketplace_config_vigente ON public.marketplace_config (chave, jurisdicao) WHERE vigente;
ALTER TABLE public.marketplace_config ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.marketplace_config FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.marketplace_config TO authenticated;
DROP POLICY IF EXISTS marketplace_config_leitura ON public.marketplace_config;
CREATE POLICY marketplace_config_leitura ON public.marketplace_config FOR SELECT TO authenticated USING (true);

CREATE OR REPLACE FUNCTION public.marketye_config(p_chave text, p_jurisdicao text DEFAULT 'BR')
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $marketye_config$
  SELECT valor FROM public.marketplace_config WHERE chave = p_chave AND jurisdicao = p_jurisdicao AND vigente LIMIT 1;
$marketye_config$;
GRANT EXECUTE ON FUNCTION public.marketye_config(text, text) TO anon, authenticated;

-- Nova versão de um parâmetro (superadmin). A anterior deixa de ser vigente,
-- mas fica no histórico — é config, não deploy.
CREATE OR REPLACE FUNCTION public.marketye_config_salvar(p_chave text, p_valor jsonb, p_descricao text DEFAULT NULL, p_jurisdicao text DEFAULT 'BR')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_config_salvar$
DECLARE v_versao int; v_id uuid;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  IF p_chave IS NULL OR p_valor IS NULL THEN RAISE EXCEPTION 'Informe chave e valor'; END IF;
  UPDATE public.marketplace_config SET vigente = false WHERE chave = p_chave AND jurisdicao = p_jurisdicao AND vigente;
  SELECT COALESCE(max(versao), 0) + 1 INTO v_versao FROM public.marketplace_config WHERE chave = p_chave AND jurisdicao = p_jurisdicao;
  INSERT INTO public.marketplace_config (chave, versao, valor, descricao, vigente, jurisdicao, criado_por)
  VALUES (p_chave, v_versao, p_valor, p_descricao, true, p_jurisdicao, auth.uid()) RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id, 'chave', p_chave, 'versao', v_versao);
END $marketye_config_salvar$;
GRANT EXECUTE ON FUNCTION public.marketye_config_salvar(text, jsonb, text, text) TO authenticated;

INSERT INTO public.marketplace_config (chave, valor, descricao) VALUES
  ('relevancia_pesos', '{"fit":0.25,"reputacao":0.20,"saude":0.20,"proximidade":0.15,"exploracao":0.10,"preco":0.05,"destaque":0.05}',
   'Pesos do motor de relevância (seção 10.2). Somam 1. Destaque pago é camada aditiva com teto.'),
  ('piso_nota', '{"nota":3.5,"minimo_avaliacoes":3}',
   'Abaixo deste piso (com pelo menos N avaliações) a visibilidade orgânica é rebaixada e o destaque não se aplica (RN-006/RN-007).'),
  ('protecao_novato', '{"dias":30,"ate_avaliacoes":3}',
   'Boost de exploração para prestador novo: por N dias ou até acumular N avaliações (RN-008).'),
  ('niveis', '{"ordem":["novo","bronze","prata","ouro","top"],"requisitos":{"bronze":{"servicos":3,"clientes_unicos":2,"media":4.0,"taxa_resposta":0.6,"ocorrencias":0},"prata":{"servicos":10,"clientes_unicos":5,"media":4.5,"taxa_resposta":0.8,"ocorrencias":0},"ouro":{"servicos":25,"clientes_unicos":10,"media":4.7,"taxa_resposta":0.9,"ocorrencias":0},"top":{"servicos":50,"clientes_unicos":20,"media":4.8,"taxa_resposta":0.95,"ocorrencias":0}},"amortecedor_dias":14}',
   'Requisitos simultâneos por nível (RN-009) e amortecedor: aviso + período de recuperação antes do ajuste de nível (RN-010). Só afeta visibilidade (RN-029).'),
  ('saude_recente', '{"janela_dias":90,"verde":75,"amarelo":50}',
   'Eixo A da reputação: janela móvel e cortes de cor do termômetro de saúde recente (RN-005).'),
  ('demanda_latente', '{"piso_celula":5,"janela_dias":30}',
   'Célula mínima das "vagas de demanda": contagens abaixo do piso não aparecem (RN-034 / CA-021).'),
  ('mascaramento_contato', '{"ate":"contato_qualificado"}',
   'Contatos mascarados até o cliente liberar o contato no lead (RN-020). Só incentivo, sem penalização por sinal de saída.'),
  ('janela_avaliacao_dias', '{"dias":14}',
   'Prazo para avaliar após a conclusão ou o lead ganho (11.3).'),
  ('termos_versoes', '{"termos_especialista":"2026-09-v1","privacidade_nao_usuario":"2026-09-v1","codigo_etica":"2026-02-v1","termos_cliente":"2026-09-v1"}',
   'Versões vigentes dos instrumentos (3.4). Redação final exige advogado; o consentimento é registrado por versão (RN-018).'),
  ('localizacao', '{"pais":"BR","moeda":"BRL","idioma":"pt-BR"}',
   'Padrões de país/moeda/idioma. Preparação para expansão América do Sul: nada de Brasil fixado em código (0.3).'),
  ('destaque', '{"teto_slots_por_categoria":2,"exige_acima_do_piso":true}',
   'Destaque pago: camada rotulada "Patrocinado", com teto por categoria e piso de nota (8.2).')
ON CONFLICT (chave, jurisdicao, versao) DO NOTHING;

-- ---------------------------------------------------------------------
-- 2) Taxonomia: árvore parametrizável, versionada por jurisdição (7.1)
-- ---------------------------------------------------------------------
ALTER TABLE public.marketplace_categorias
  ADD COLUMN IF NOT EXISTS slug              text,
  ADD COLUMN IF NOT EXISTS pai_id            uuid REFERENCES public.marketplace_categorias(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS aliases           text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS obrigacao_legal   text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS exige_registro    boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS conselhos_aceitos text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS jurisdicao        text NOT NULL DEFAULT 'BR',
  ADD COLUMN IF NOT EXISTS versao            int NOT NULL DEFAULT 1;

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

-- ---------------------------------------------------------------------
-- 3) Especialista: colunas novas (entidade global, sem tenant)
-- ---------------------------------------------------------------------
ALTER TABLE public.marketplace_profissionais
  ADD COLUMN IF NOT EXISTS tipo_pessoa           text NOT NULL DEFAULT 'pf' CHECK (tipo_pessoa IN ('pf','pj')),
  ADD COLUMN IF NOT EXISTS pais                  text NOT NULL DEFAULT 'BR',
  ADD COLUMN IF NOT EXISTS moeda                 text NOT NULL DEFAULT 'BRL',
  ADD COLUMN IF NOT EXISTS atende_remoto         boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS raio_atendimento_km   int NOT NULL DEFAULT 100,
  ADD COLUMN IF NOT EXISTS disponibilidade       jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS politicas             text,
  ADD COLUMN IF NOT EXISTS site_url              text,
  ADD COLUMN IF NOT EXISTS video_url             text,
  ADD COLUMN IF NOT EXISTS moderacao_resultado   text CHECK (moderacao_resultado IN ('aprovado','rejeitado')),
  ADD COLUMN IF NOT EXISTS moderacao_motivo      text,
  ADD COLUMN IF NOT EXISTS moderado_por          uuid,
  ADD COLUMN IF NOT EXISTS moderado_em           timestamptz,
  ADD COLUMN IF NOT EXISTS excluido_em           timestamptz,
  ADD COLUMN IF NOT EXISTS consentimento_versao  text,
  ADD COLUMN IF NOT EXISTS consentimento_em      timestamptz,
  ADD COLUMN IF NOT EXISTS origem_cadastro       text NOT NULL DEFAULT 'sistema',
  ADD COLUMN IF NOT EXISTS parceiro_id           uuid;

-- Papéis sobrepostos (0.6): a mesma pessoa pode ser parceiro do canal.
DO $fk_parceiro$
BEGIN
  IF to_regclass('public.parceiros') IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM pg_constraint WHERE conname = 'marketplace_profissionais_parceiro_id_fkey') THEN
    ALTER TABLE public.marketplace_profissionais
      ADD CONSTRAINT marketplace_profissionais_parceiro_id_fkey FOREIGN KEY (parceiro_id) REFERENCES public.parceiros(id) ON DELETE SET NULL;
  END IF;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'FK parceiro_id: %', SQLERRM;
END $fk_parceiro$;

-- Novo cadastro nasce pendente (o default tinha virado 'ativo' em 05/2026).
ALTER TABLE public.marketplace_profissionais ALTER COLUMN status SET DEFAULT 'pendente';

-- Um CPF/CNPJ = uma conta de especialista (RN-012). Só para documentos
-- válidos e cadastros vivos; registros antigos sem documento não colidem.
CREATE UNIQUE INDEX IF NOT EXISTS idx_marketplace_prof_documento_unico
  ON public.marketplace_profissionais (public.marketye_so_digitos(cpf_cnpj))
  WHERE cpf_cnpj IS NOT NULL AND length(public.marketye_so_digitos(cpf_cnpj)) IN (11, 14) AND excluido_em IS NULL;

-- ---------------------------------------------------------------------
-- 4) Anúncio (marketplace_servicos): colunas novas
-- ---------------------------------------------------------------------
ALTER TABLE public.marketplace_servicos
  ADD COLUMN IF NOT EXISTS status               text NOT NULL DEFAULT 'rascunho' CHECK (status IN ('rascunho','publicado','pausado','removido')),
  ADD COLUMN IF NOT EXISTS publicado_em         timestamptz,
  ADD COLUMN IF NOT EXISTS tipo_preco           text NOT NULL DEFAULT 'sob_orcamento' CHECK (tipo_preco IN ('hora','visita','pacote','mensal','sob_orcamento')),
  ADD COLUMN IF NOT EXISTS preco_minimo         numeric(10,2),
  ADD COLUMN IF NOT EXISTS preco_maximo         numeric(10,2),
  ADD COLUMN IF NOT EXISTS moeda                text NOT NULL DEFAULT 'BRL',
  ADD COLUMN IF NOT EXISTS pais                 text NOT NULL DEFAULT 'BR',
  ADD COLUMN IF NOT EXISTS tags                 text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS obrigacao_legal      text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS area_atendimento     jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS prazo_tipico         text,
  ADD COLUMN IF NOT EXISTS politica_cancelamento text,
  ADD COLUMN IF NOT EXISTS midia                jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS gerado_por_ia        boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS promocao_percentual  numeric(5,2),
  ADD COLUMN IF NOT EXISTS promocao_inicio      date,
  ADD COLUMN IF NOT EXISTS promocao_fim         date,
  ADD COLUMN IF NOT EXISTS promocao_descricao   text,
  ADD COLUMN IF NOT EXISTS impressoes           int NOT NULL DEFAULT 0;

-- Serviços que já estavam ativos continuam na vitrine: viram 'publicado'.
UPDATE public.marketplace_servicos SET status = 'publicado', publicado_em = COALESCE(publicado_em, created_at)
WHERE ativo AND status = 'rascunho' AND created_at < now() - interval '1 minute';
UPDATE public.marketplace_servicos SET tipo_preco = 'visita' WHERE preco_referencia IS NOT NULL AND tipo_preco = 'sob_orcamento';

CREATE INDEX IF NOT EXISTS idx_marketplace_servicos_vitrine ON public.marketplace_servicos (status, ativo, categoria_id) WHERE status = 'publicado' AND ativo;

-- ---------------------------------------------------------------------
-- 5) Avaliação bidirecional atrelada a transação verificada (RN-004/RN-022)
-- ---------------------------------------------------------------------
ALTER TABLE public.marketplace_avaliacoes
  ADD COLUMN IF NOT EXISTS lead_id               uuid,
  ADD COLUMN IF NOT EXISTS direcao               text NOT NULL DEFAULT 'cliente_para_especialista' CHECK (direcao IN ('cliente_para_especialista','especialista_para_cliente')),
  ADD COLUMN IF NOT EXISTS criterios             jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS resposta              text,
  ADD COLUMN IF NOT EXISTS respondido_em         timestamptz,
  ADD COLUMN IF NOT EXISTS moderada              boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS moderacao_motivo      text;
ALTER TABLE public.marketplace_avaliacoes ALTER COLUMN contratacao_id DROP NOT NULL;
ALTER TABLE public.marketplace_avaliacoes ALTER COLUMN servico_id DROP NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_marketplace_avaliacoes_contratacao_direcao ON public.marketplace_avaliacoes (contratacao_id, direcao) WHERE contratacao_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_marketplace_avaliacoes_lead_direcao ON public.marketplace_avaliacoes (lead_id, direcao) WHERE lead_id IS NOT NULL;

-- ---------------------------------------------------------------------
-- 6) Leads (RF-012): o elo entre demanda e oferta, com contato mascarado
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.marketplace_leads (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id            uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  empresa_id           uuid,
  profissional_id      uuid NOT NULL REFERENCES public.marketplace_profissionais(id) ON DELETE CASCADE,
  servico_id           uuid REFERENCES public.marketplace_servicos(id) ON DELETE SET NULL,
  criado_por           uuid,
  solicitante_nome     text,
  canal                text NOT NULL DEFAULT 'chat',
  status               text NOT NULL DEFAULT 'novo' CHECK (status IN ('novo','respondido','qualificado','ganho','perdido','encerrado')),
  contato_liberado     boolean NOT NULL DEFAULT false,
  contato_liberado_em  timestamptz,
  primeira_resposta_em timestamptz,
  ultima_mensagem_em   timestamptz,
  ganho_em             timestamptz,
  origem_modulo        text,
  origem_id            uuid,
  obrigacao_legal      text,
  cupom_codigo         text,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_marketplace_leads_tenant ON public.marketplace_leads (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_marketplace_leads_prof ON public.marketplace_leads (profissional_id, created_at DESC);
DROP TRIGGER IF EXISTS update_marketplace_leads_updated_at ON public.marketplace_leads;
CREATE TRIGGER update_marketplace_leads_updated_at BEFORE UPDATE ON public.marketplace_leads FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.marketplace_lead_mensagens (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id        uuid NOT NULL REFERENCES public.marketplace_leads(id) ON DELETE CASCADE,
  autor_tipo     text NOT NULL CHECK (autor_tipo IN ('cliente','especialista','sistema')),
  autor_id       uuid,
  texto          text NOT NULL,
  texto_original text,
  mascarada      boolean NOT NULL DEFAULT false,
  sinal_saida    boolean NOT NULL DEFAULT false,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_marketplace_lead_mensagens_lead ON public.marketplace_lead_mensagens (lead_id, created_at);

CREATE TABLE IF NOT EXISTS public.marketplace_lead_documentos (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id      uuid NOT NULL REFERENCES public.marketplace_leads(id) ON DELETE CASCADE,
  documento_id uuid NOT NULL,
  tipo         text NOT NULL DEFAULT 'proposta',
  created_at   timestamptz NOT NULL DEFAULT now()
);

DO $fk_avaliacao_lead$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'marketplace_avaliacoes_lead_id_fkey') THEN
    ALTER TABLE public.marketplace_avaliacoes ADD CONSTRAINT marketplace_avaliacoes_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES public.marketplace_leads(id) ON DELETE CASCADE;
  END IF;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'FK avaliacoes.lead_id: %', SQLERRM;
END $fk_avaliacao_lead$;

-- ---------------------------------------------------------------------
-- 7) Reputação em dois eixos (RF-009) — uma linha por especialista
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.marketplace_reputacao (
  profissional_id          uuid PRIMARY KEY REFERENCES public.marketplace_profissionais(id) ON DELETE CASCADE,
  saude_score              numeric(5,2) NOT NULL DEFAULT 60,
  saude_cor                text NOT NULL DEFAULT 'cinza' CHECK (saude_cor IN ('verde','amarelo','vermelho','cinza')),
  media_90d                numeric(3,2),
  avaliacoes_90d           int NOT NULL DEFAULT 0,
  clientes_unicos_total    int NOT NULL DEFAULT 0,
  clientes_unicos_90d      int NOT NULL DEFAULT 0,
  taxa_resposta_90d        numeric(4,3),
  tempo_resposta_mediano_min int,
  taxa_cancelamento_90d    numeric(4,3),
  ocorrencias_90d          int NOT NULL DEFAULT 0,
  servicos_concluidos_total int NOT NULL DEFAULT 0,
  nivel                    text NOT NULL DEFAULT 'novo',
  nivel_desde              timestamptz NOT NULL DEFAULT now(),
  nivel_aviso_em           timestamptz,
  nivel_aviso_motivo       text,
  abaixo_piso              boolean NOT NULL DEFAULT false,
  protegido_ate            timestamptz,
  calculado_em             timestamptz NOT NULL DEFAULT now()
);

-- Ocorrências (léxico não-disciplinar): registro factual com reflexo na
-- visibilidade; nunca condição para continuar operando.
CREATE TABLE IF NOT EXISTS public.marketplace_ocorrencias (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profissional_id      uuid NOT NULL REFERENCES public.marketplace_profissionais(id) ON DELETE CASCADE,
  tipo                 text NOT NULL,
  descricao            text,
  origem_tipo          text,
  origem_id            uuid,
  reflexo_visibilidade boolean NOT NULL DEFAULT true,
  registrado_por       uuid,
  created_at           timestamptz NOT NULL DEFAULT now()
);

-- Destaque pago: camada aditiva, rotulada, com teto (8.2). A cobrança em si
-- não está nesta onda — só o registro e o reflexo no ranking.
CREATE TABLE IF NOT EXISTS public.marketplace_destaques (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profissional_id uuid NOT NULL REFERENCES public.marketplace_profissionais(id) ON DELETE CASCADE,
  servico_id      uuid REFERENCES public.marketplace_servicos(id) ON DELETE CASCADE,
  tipo            text NOT NULL DEFAULT 'categoria' CHECK (tipo IN ('categoria','regiao','topo')),
  categoria_id    uuid REFERENCES public.marketplace_categorias(id) ON DELETE SET NULL,
  uf              text,
  inicio          date NOT NULL DEFAULT CURRENT_DATE,
  fim             date NOT NULL,
  valor           numeric(10,2),
  moeda           text NOT NULL DEFAULT 'BRL',
  ativo           boolean NOT NULL DEFAULT true,
  criado_por      uuid,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.marketplace_cupons (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profissional_id     uuid NOT NULL REFERENCES public.marketplace_profissionais(id) ON DELETE CASCADE,
  codigo              text NOT NULL,
  descricao           text,
  desconto_percentual numeric(5,2) NOT NULL CHECK (desconto_percentual > 0 AND desconto_percentual <= 100),
  validade            date,
  limite_uso          int,
  usos                int NOT NULL DEFAULT 0,
  ativo               boolean NOT NULL DEFAULT true,
  created_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (profissional_id, codigo)
);

-- ---------------------------------------------------------------------
-- 8) LGPD, devido processo e trilha de autonomia
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.marketplace_consentimentos (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profissional_id uuid NOT NULL REFERENCES public.marketplace_profissionais(id) ON DELETE CASCADE,
  tipo            text NOT NULL,
  versao          text NOT NULL,
  aceito_em       timestamptz NOT NULL DEFAULT now(),
  ip              text,
  user_agent      text,
  origem          text
);
CREATE INDEX IF NOT EXISTS idx_marketplace_consentimentos_prof ON public.marketplace_consentimentos (profissional_id, tipo, aceito_em DESC);

-- Canal único de contestação (RN-032/RN-033): a decisão é sempre de uma
-- pessoa (human-in-the-loop), com trilha de evidência.
CREATE TABLE IF NOT EXISTS public.marketplace_contestacoes (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profissional_id uuid NOT NULL REFERENCES public.marketplace_profissionais(id) ON DELETE CASCADE,
  decisao_tipo    text NOT NULL CHECK (decisao_tipo IN ('rejeicao_cadastro','suspensao','remocao_anuncio','ajuste_nivel','reflexo_visibilidade','avaliacao','outro')),
  referencia_id   uuid,
  motivo          text NOT NULL,
  evidencias      jsonb NOT NULL DEFAULT '[]'::jsonb,
  status          text NOT NULL DEFAULT 'aberta' CHECK (status IN ('aberta','em_analise','deferida','indeferida')),
  resposta        text,
  analisado_por   uuid,
  analisado_em    timestamptz,
  trilha          jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- Trilha de autonomia (RN-031): toda definição de preço/horário/política é
-- do prestador e fica registrada como evento.
CREATE TABLE IF NOT EXISTS public.marketplace_autonomia_eventos (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profissional_id uuid NOT NULL REFERENCES public.marketplace_profissionais(id) ON DELETE CASCADE,
  tipo            text NOT NULL,
  referencia_id   uuid,
  anterior        jsonb,
  novo            jsonb,
  autor_id        uuid,
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_marketplace_autonomia_prof ON public.marketplace_autonomia_eventos (profissional_id, created_at DESC);

-- Demanda latente (busca sem oferta suficiente): uma linha por
-- (empresa × categoria × UF × dia); a página pública só vê agregados com
-- célula mínima (RN-034).
CREATE TABLE IF NOT EXISTS public.marketplace_demanda_latente (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL,
  categoria_id  uuid REFERENCES public.marketplace_categorias(id) ON DELETE CASCADE,
  uf            text,
  cidade        text,
  dia           date NOT NULL DEFAULT CURRENT_DATE,
  termos        text,
  resultados    int NOT NULL DEFAULT 0,
  avisar        boolean NOT NULL DEFAULT false,
  avisar_email  text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, categoria_id, uf, dia)
);

-- ---------------------------------------------------------------------
-- 9) RLS das tabelas novas: leitura por política, escrita por função
-- ---------------------------------------------------------------------
ALTER TABLE public.marketplace_leads              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_lead_mensagens     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_lead_documentos    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_reputacao          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_ocorrencias        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_destaques          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_cupons             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_consentimentos     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_contestacoes       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_autonomia_eventos  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_demanda_latente    ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.marketplace_leads, public.marketplace_lead_mensagens, public.marketplace_lead_documentos,
  public.marketplace_reputacao, public.marketplace_ocorrencias, public.marketplace_destaques, public.marketplace_cupons,
  public.marketplace_consentimentos, public.marketplace_contestacoes, public.marketplace_autonomia_eventos,
  public.marketplace_demanda_latente FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.marketplace_leads, public.marketplace_lead_mensagens, public.marketplace_lead_documentos,
  public.marketplace_reputacao, public.marketplace_ocorrencias, public.marketplace_destaques, public.marketplace_cupons,
  public.marketplace_consentimentos, public.marketplace_contestacoes, public.marketplace_autonomia_eventos,
  public.marketplace_demanda_latente TO authenticated;

DROP POLICY IF EXISTS marketplace_leads_leitura ON public.marketplace_leads;
CREATE POLICY marketplace_leads_leitura ON public.marketplace_leads FOR SELECT TO authenticated
  USING (tenant_id = public.get_user_tenant_id() OR profissional_id = public.marketye_meu_id() OR public.is_superadmin(auth.uid()));

DROP POLICY IF EXISTS marketplace_lead_mensagens_leitura ON public.marketplace_lead_mensagens;
CREATE POLICY marketplace_lead_mensagens_leitura ON public.marketplace_lead_mensagens FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.marketplace_leads l WHERE l.id = lead_id
                   AND (l.tenant_id = public.get_user_tenant_id() OR l.profissional_id = public.marketye_meu_id() OR public.is_superadmin(auth.uid()))));

DROP POLICY IF EXISTS marketplace_lead_documentos_leitura ON public.marketplace_lead_documentos;
CREATE POLICY marketplace_lead_documentos_leitura ON public.marketplace_lead_documentos FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.marketplace_leads l WHERE l.id = lead_id
                   AND (l.tenant_id = public.get_user_tenant_id() OR l.profissional_id = public.marketye_meu_id() OR public.is_superadmin(auth.uid()))));

DROP POLICY IF EXISTS marketplace_reputacao_leitura ON public.marketplace_reputacao;
CREATE POLICY marketplace_reputacao_leitura ON public.marketplace_reputacao FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS marketplace_ocorrencias_leitura ON public.marketplace_ocorrencias;
CREATE POLICY marketplace_ocorrencias_leitura ON public.marketplace_ocorrencias FOR SELECT TO authenticated
  USING (profissional_id = public.marketye_meu_id() OR public.is_superadmin(auth.uid()));

DROP POLICY IF EXISTS marketplace_destaques_leitura ON public.marketplace_destaques;
CREATE POLICY marketplace_destaques_leitura ON public.marketplace_destaques FOR SELECT TO authenticated
  USING (profissional_id = public.marketye_meu_id() OR public.is_superadmin(auth.uid()));

DROP POLICY IF EXISTS marketplace_cupons_leitura ON public.marketplace_cupons;
CREATE POLICY marketplace_cupons_leitura ON public.marketplace_cupons FOR SELECT TO authenticated
  USING (profissional_id = public.marketye_meu_id() OR public.is_superadmin(auth.uid()));

DROP POLICY IF EXISTS marketplace_consentimentos_leitura ON public.marketplace_consentimentos;
CREATE POLICY marketplace_consentimentos_leitura ON public.marketplace_consentimentos FOR SELECT TO authenticated
  USING (profissional_id = public.marketye_meu_id() OR public.is_superadmin(auth.uid()));

DROP POLICY IF EXISTS marketplace_contestacoes_leitura ON public.marketplace_contestacoes;
CREATE POLICY marketplace_contestacoes_leitura ON public.marketplace_contestacoes FOR SELECT TO authenticated
  USING (profissional_id = public.marketye_meu_id() OR public.is_superadmin(auth.uid()));

DROP POLICY IF EXISTS marketplace_autonomia_leitura ON public.marketplace_autonomia_eventos;
CREATE POLICY marketplace_autonomia_leitura ON public.marketplace_autonomia_eventos FOR SELECT TO authenticated
  USING (profissional_id = public.marketye_meu_id() OR public.is_superadmin(auth.uid()));

DROP POLICY IF EXISTS marketplace_demanda_latente_leitura ON public.marketplace_demanda_latente;
CREATE POLICY marketplace_demanda_latente_leitura ON public.marketplace_demanda_latente FOR SELECT TO authenticated
  USING (public.is_superadmin(auth.uid()));

-- ---------------------------------------------------------------------
-- 10) RLS das tabelas antigas: fecha as brechas herdadas
-- ---------------------------------------------------------------------
-- 10.1 "Admins manage all professionals" usava has_minimum_role('admin'),
--      que NÃO é por empresa: o admin de qualquer empresa gerenciava todos
--      os prestadores. Agora só superadmin (a moderação é da casa).
DROP POLICY IF EXISTS "Admins manage all professionals" ON public.marketplace_profissionais;
DROP POLICY IF EXISTS marketplace_profissionais_superadmin ON public.marketplace_profissionais;
CREATE POLICY marketplace_profissionais_superadmin ON public.marketplace_profissionais FOR ALL TO authenticated
  USING (public.is_superadmin(auth.uid())) WITH CHECK (public.is_superadmin(auth.uid()));

-- 10.2 Leitura direta só das colunas públicas: e-mail, telefone, CPF/CNPJ,
--      user_id e tenant_id saem da leitura por tabela. O próprio prestador e
--      a moderação leem o perfil completo por função (marketye_meu_portal,
--      marketye_moderacao_fila); o cliente recebe o contato pelo lead
--      liberado (marketye_lead_contato).
REVOKE SELECT ON public.marketplace_profissionais FROM authenticated;
GRANT SELECT (id, nome_completo, foto_url, bio, formacao_academica, registro_profissional, conselho, uf_registro, registro_validade,
              certificacoes, especialidades, areas_atuacao, modalidades_atendimento, cidade, estado, status, plano, selo_verificado,
              nota_media, total_avaliacoes, total_servicos_executados, tem_atestado_capacidade, latitude, longitude, created_at, updated_at,
              tipo_pessoa, pais, moeda, atende_remoto, raio_atendimento_km, disponibilidade, politicas, site_url, video_url,
              excluido_em, consentimento_versao, consentimento_em, origem_cadastro, moderacao_resultado, aceite_codigo_etica)
  ON public.marketplace_profissionais TO authenticated;

-- 10.3 Avaliação: só por função (transação verificada). A leitura continua
--      pública (é reputação), mas sem expor quem avaliou.
DROP POLICY IF EXISTS "Tenant members can create reviews" ON public.marketplace_avaliacoes;
REVOKE SELECT ON public.marketplace_avaliacoes FROM authenticated;
GRANT SELECT (id, contratacao_id, profissional_id, servico_id, pontualidade, clareza, aderencia_escopo, profissionalismo, nota_geral,
              comentario, created_at, lead_id, direcao, criterios, resposta, respondido_em, moderada)
  ON public.marketplace_avaliacoes TO authenticated;

-- 10.4 Vitrine só mostra anúncio publicado (rascunho e pausado ficam com o dono).
DROP POLICY IF EXISTS "Public can view active services" ON public.marketplace_servicos;
CREATE POLICY "Public can view active services" ON public.marketplace_servicos FOR SELECT TO anon, authenticated
  USING (ativo = true AND status = 'publicado');

-- 10.5 A antiga busca por proximidade devolvia e-mail e telefone; some.
DROP FUNCTION IF EXISTS public.buscar_profissionais_proximos(double precision, double precision, double precision);

-- ---------------------------------------------------------------------
-- 11) Guardas (RN-021 / CA-013): dado sensível só muda por função
-- ---------------------------------------------------------------------
-- As guardas NÃO são SECURITY DEFINER de propósito: rodam como quem escreve.
-- Escrita direta pela API chega como 'authenticated' (guarda ativa); escrita
-- de dentro das funções marketye_* chega como o dono delas (postgres) e passa.
CREATE OR REPLACE FUNCTION public.marketye_guarda_profissional()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $marketye_guarda_profissional$
BEGIN
  IF public.marketye_via_funcao() OR public.is_superadmin(auth.uid()) THEN RETURN NEW; END IF;
  IF TG_OP = 'INSERT' THEN
    -- Cadastro direto pela tabela nasce pendente, sem selo e sem reputação.
    NEW.status := 'pendente'; NEW.selo_verificado := false; NEW.nota_media := 0; NEW.total_avaliacoes := 0;
    NEW.total_servicos_executados := 0; NEW.plano := 'base'; NEW.moderacao_resultado := NULL; NEW.moderacao_motivo := NULL;
    NEW.moderado_por := NULL; NEW.moderado_em := NULL; NEW.excluido_em := NULL; NEW.tem_atestado_capacidade := false;
    NEW.user_id := auth.uid();
    RETURN NEW;
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status OR NEW.selo_verificado IS DISTINCT FROM OLD.selo_verificado
     OR NEW.nota_media IS DISTINCT FROM OLD.nota_media OR NEW.total_avaliacoes IS DISTINCT FROM OLD.total_avaliacoes
     OR NEW.total_servicos_executados IS DISTINCT FROM OLD.total_servicos_executados OR NEW.plano IS DISTINCT FROM OLD.plano
     OR NEW.moderacao_resultado IS DISTINCT FROM OLD.moderacao_resultado OR NEW.moderacao_motivo IS DISTINCT FROM OLD.moderacao_motivo
     OR NEW.moderado_por IS DISTINCT FROM OLD.moderado_por OR NEW.moderado_em IS DISTINCT FROM OLD.moderado_em
     OR NEW.excluido_em IS DISTINCT FROM OLD.excluido_em OR NEW.consentimento_versao IS DISTINCT FROM OLD.consentimento_versao
     OR NEW.consentimento_em IS DISTINCT FROM OLD.consentimento_em OR NEW.user_id IS DISTINCT FROM OLD.user_id
     OR NEW.cpf_cnpj IS DISTINCT FROM OLD.cpf_cnpj OR NEW.tem_atestado_capacidade IS DISTINCT FROM OLD.tem_atestado_capacidade
     OR NEW.parceiro_id IS DISTINCT FROM OLD.parceiro_id THEN
    RAISE EXCEPTION 'MarketYE: status, selo, reputação, documento e consentimento só mudam por função do sistema'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN NEW;
END $marketye_guarda_profissional$;
DROP TRIGGER IF EXISTS marketye_guarda_profissional ON public.marketplace_profissionais;
CREATE TRIGGER marketye_guarda_profissional BEFORE INSERT OR UPDATE ON public.marketplace_profissionais
  FOR EACH ROW EXECUTE FUNCTION public.marketye_guarda_profissional();

CREATE OR REPLACE FUNCTION public.marketye_guarda_anuncio()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $marketye_guarda_anuncio$
BEGIN
  IF public.marketye_via_funcao() OR public.is_superadmin(auth.uid()) THEN RETURN NEW; END IF;
  IF TG_OP = 'INSERT' THEN
    NEW.status := 'rascunho'; NEW.publicado_em := NULL; NEW.impressoes := 0;
    RETURN NEW;
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'publicado' THEN
    RAISE EXCEPTION 'MarketYE: a publicação do anúncio passa pela função marketye_anuncio_publicar' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NEW.impressoes IS DISTINCT FROM OLD.impressoes THEN NEW.impressoes := OLD.impressoes; END IF;
  RETURN NEW;
END $marketye_guarda_anuncio$;
DROP TRIGGER IF EXISTS marketye_guarda_anuncio ON public.marketplace_servicos;
CREATE TRIGGER marketye_guarda_anuncio BEFORE INSERT OR UPDATE ON public.marketplace_servicos
  FOR EACH ROW EXECUTE FUNCTION public.marketye_guarda_anuncio();

-- Trilha de autonomia (RN-031): preço, horário e política são do prestador.
CREATE OR REPLACE FUNCTION public.marketye_trilha_autonomia_anuncio()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_trilha_autonomia_anuncio$
DECLARE v_ant jsonb; v_novo jsonb;
BEGIN
  v_novo := jsonb_build_object('preco_referencia', NEW.preco_referencia, 'tipo_preco', NEW.tipo_preco, 'preco_minimo', NEW.preco_minimo,
                               'preco_maximo', NEW.preco_maximo, 'prazo_tipico', NEW.prazo_tipico, 'politica_cancelamento', NEW.politica_cancelamento,
                               'area_atendimento', NEW.area_atendimento, 'modalidade', NEW.modalidade::text);
  IF TG_OP = 'UPDATE' THEN
    v_ant := jsonb_build_object('preco_referencia', OLD.preco_referencia, 'tipo_preco', OLD.tipo_preco, 'preco_minimo', OLD.preco_minimo,
                                'preco_maximo', OLD.preco_maximo, 'prazo_tipico', OLD.prazo_tipico, 'politica_cancelamento', OLD.politica_cancelamento,
                                'area_atendimento', OLD.area_atendimento, 'modalidade', OLD.modalidade::text);
    IF v_ant = v_novo THEN RETURN NEW; END IF;
  END IF;
  INSERT INTO public.marketplace_autonomia_eventos (profissional_id, tipo, referencia_id, anterior, novo, autor_id)
  VALUES (NEW.profissional_id, 'anuncio_preco_politica', NEW.id, v_ant, v_novo, auth.uid());
  RETURN NEW;
END $marketye_trilha_autonomia_anuncio$;
DROP TRIGGER IF EXISTS marketye_trilha_autonomia_anuncio ON public.marketplace_servicos;
CREATE TRIGGER marketye_trilha_autonomia_anuncio AFTER INSERT OR UPDATE ON public.marketplace_servicos
  FOR EACH ROW EXECUTE FUNCTION public.marketye_trilha_autonomia_anuncio();

CREATE OR REPLACE FUNCTION public.marketye_trilha_autonomia_perfil()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_trilha_autonomia_perfil$
DECLARE v_ant jsonb; v_novo jsonb;
BEGIN
  v_novo := jsonb_build_object('modalidades', to_jsonb(NEW.modalidades_atendimento), 'atende_remoto', NEW.atende_remoto,
                               'raio_atendimento_km', NEW.raio_atendimento_km, 'disponibilidade', NEW.disponibilidade, 'politicas', NEW.politicas);
  v_ant  := jsonb_build_object('modalidades', to_jsonb(OLD.modalidades_atendimento), 'atende_remoto', OLD.atende_remoto,
                               'raio_atendimento_km', OLD.raio_atendimento_km, 'disponibilidade', OLD.disponibilidade, 'politicas', OLD.politicas);
  IF v_ant = v_novo THEN RETURN NEW; END IF;
  INSERT INTO public.marketplace_autonomia_eventos (profissional_id, tipo, referencia_id, anterior, novo, autor_id)
  VALUES (NEW.id, 'perfil_horario_politica', NEW.id, v_ant, v_novo, auth.uid());
  RETURN NEW;
END $marketye_trilha_autonomia_perfil$;
DROP TRIGGER IF EXISTS marketye_trilha_autonomia_perfil ON public.marketplace_profissionais;
CREATE TRIGGER marketye_trilha_autonomia_perfil AFTER UPDATE ON public.marketplace_profissionais
  FOR EACH ROW EXECUTE FUNCTION public.marketye_trilha_autonomia_perfil();
