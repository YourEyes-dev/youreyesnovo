-- =====================================================================
-- SCRIPT DE ENTREGA — MarketYE na HOMOLOGACAO (esquema + funcoes)
--
-- POR QUE: a homologacao nao recebe migrations automaticas (forward-only).
-- As funcoes/tabelas do MarketYE sao migrations recentes (11-13/09) que so
-- estao no ambiente de TESTE. Sem elas, a homologacao devolve 404 em
-- rpc/marketye_meu_id e os testes de MarketYE / portal falham.
--
-- O QUE FAZ: traz para a homologacao a superficie de RUNTIME do MarketYE
-- (tabelas marketplace_*, ~50 funcoes marketye_*, politicas RLS, gatilhos,
-- bucket de fotos e as travas de seguranca). E a MESMA SQL das migrations do
-- repositorio, apenas concatenada em ordem. Nao inclui as rotinas de QA do
-- MarketYE (opcionais) para manter o script menor.
--
-- SEGURANCA: 100% idempotente (todas as tabelas com IF NOT EXISTS, tipos
-- inexistentes, toda politica/gatilho com DROP IF EXISTS + CREATE, toda funcao
-- CREATE OR REPLACE, todo seed com ON CONFLICT, bordas em DO/EXCEPTION). O SQL
-- Editor roda tudo em UMA transacao: se algo falhar, desfaz sozinho e nada e
-- gravado pela metade. Pode rodar de novo sem quebrar nem duplicar.
--
-- COMO USAR: cole o arquivo INTEIRO no SQL Editor do projeto de HOMOLOGACAO
-- (fgsblefvdabgdouipigz) e rode. A ultima linha e uma conferencia.
-- =====================================================================

SET lock_timeout = '15s';


-- ===================================================================
-- ORIGEM: 20260911220000_marketye_fundacao.sql
-- ===================================================================
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

-- ===================================================================
-- ORIGEM: 20260911221000_marketye_funcoes.sql
-- ===================================================================
-- =====================================================================
-- MARKETYE · FUNÇÕES DO MÓDULO (segunda parte da fundação)
--
-- Doutrina do módulo (a mesma do Programa de Parceiros): leitura por
-- política, escrita por função SECURITY DEFINER. Nenhuma ação sensível do
-- prestador (cadastro, publicação, aceite de termos, avaliação, contato)
-- acontece por UPDATE direto de tabela exposta (RN-021).
--
-- Grupos: cadastro/consentimento · portal · anúncios · leads · avaliação e
-- reputação em dois eixos · busca com relevância personalizada · demanda
-- latente e vitrine pública · moderação, contestação e transparência ·
-- LGPD · painel de liquidez.
--
-- Idempotente: só CREATE OR REPLACE e GRANT.
-- =====================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- 1) Cadastro e consentimento (RF-001, RN-001, RN-012, RN-018)
-- ---------------------------------------------------------------------
-- Núcleo do cadastro. Chamada pela função autenticada (abaixo) e pela Edge
-- Function marketye-cadastro (service_role), que antes cria a conta.
CREATE OR REPLACE FUNCTION public.marketye_cadastrar_especialista_para(p_user_id uuid, _dados jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_cadastrar_especialista_para$
DECLARE
  v_id uuid; v_nome text; v_email text; v_doc text; v_tipo text; v_versoes jsonb; v_modalidades text[];
  v_parceiro uuid; v_ip text; v_ua text; v_status text;
BEGIN
  IF p_user_id IS NULL THEN RAISE EXCEPTION 'Conta não identificada'; END IF;
  SELECT id, status::text INTO v_id, v_status FROM public.marketplace_profissionais WHERE user_id = p_user_id ORDER BY created_at LIMIT 1;
  IF v_id IS NOT NULL THEN
    RETURN jsonb_build_object('id', v_id, 'status', v_status, 'ja_existia', true);
  END IF;

  v_nome  := trim(COALESCE(_dados->>'nome_completo', _dados->>'nome', ''));
  v_email := lower(trim(COALESCE(_dados->>'email', '')));
  v_doc   := public.marketye_so_digitos(_dados->>'cpf_cnpj');
  v_tipo  := CASE WHEN length(v_doc) = 14 THEN 'pj' WHEN COALESCE(_dados->>'tipo_pessoa', '') = 'pj' THEN 'pj' ELSE 'pf' END;
  IF length(v_nome) < 3 THEN RAISE EXCEPTION 'Informe o nome (mínimo 3 letras)'; END IF;
  IF v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN RAISE EXCEPTION 'E-mail inválido'; END IF;
  IF v_doc = '' THEN RAISE EXCEPTION 'Informe o CPF ou CNPJ'; END IF;
  IF NOT public.marketye_documento_valido(v_doc) THEN RAISE EXCEPTION 'CPF/CNPJ inválido: confira os dígitos'; END IF;
  IF EXISTS (SELECT 1 FROM public.marketplace_profissionais WHERE public.marketye_so_digitos(cpf_cnpj) = v_doc AND excluido_em IS NULL) THEN
    RAISE EXCEPTION 'Este CPF/CNPJ já possui cadastro de especialista.';
  END IF;
  IF COALESCE((_dados->>'aceite_termos')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'É preciso aceitar os Termos do Especialista e a Política de Privacidade';
  END IF;

  v_modalidades := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_dados->'modalidades')), ARRAY['presencial']);
  IF array_length(v_modalidades, 1) IS NULL THEN v_modalidades := ARRAY['presencial']; END IF;
  v_versoes := COALESCE(public.marketye_config('termos_versoes'), '{}'::jsonb);
  v_ip := _dados->>'ip'; v_ua := _dados->>'user_agent';

  -- Papéis sobrepostos (0.6): quem já é parceiro do canal reaproveita a identidade.
  IF to_regclass('public.parceiro_usuarios') IS NOT NULL THEN
    SELECT parceiro_id INTO v_parceiro FROM public.parceiro_usuarios WHERE user_id = p_user_id LIMIT 1;
  END IF;

  INSERT INTO public.marketplace_profissionais
    (user_id, tenant_id, nome_completo, email, telefone, cpf_cnpj, tipo_pessoa, bio, formacao_academica, registro_profissional, conselho,
     uf_registro, registro_validade, certificacoes, especialidades, areas_atuacao, modalidades_atendimento, cidade, estado,
     latitude, longitude, atende_remoto, raio_atendimento_km, aceite_codigo_etica, aceite_codigo_etica_data,
     status, plano, selo_verificado, consentimento_versao, consentimento_em, origem_cadastro, parceiro_id, pais, moeda, site_url)
  VALUES
    (p_user_id, NULLIF(_dados->>'tenant_origem', '')::uuid, v_nome, v_email, NULLIF(trim(_dados->>'telefone'), ''), v_doc, v_tipo, NULLIF(_dados->>'bio', ''),
     NULLIF(_dados->>'formacao_academica', ''), NULLIF(_dados->>'registro_profissional', ''), NULLIF(_dados->>'conselho', ''),
     NULLIF(upper(_dados->>'uf_registro'), ''), NULLIF(_dados->>'registro_validade', '')::date,
     NULLIF(ARRAY(SELECT jsonb_array_elements_text(COALESCE(_dados->'certificacoes', '[]'::jsonb))), '{}'),
     NULLIF(ARRAY(SELECT jsonb_array_elements_text(COALESCE(_dados->'especialidades', '[]'::jsonb))), '{}'),
     NULLIF(ARRAY(SELECT jsonb_array_elements_text(COALESCE(_dados->'areas_atuacao', '[]'::jsonb))), '{}'),
     v_modalidades::public.marketplace_servico_modalidade[], NULLIF(_dados->>'cidade', ''), NULLIF(upper(_dados->>'estado'), ''),
     NULLIF(_dados->>'latitude', '')::double precision, NULLIF(_dados->>'longitude', '')::double precision,
     COALESCE((_dados->>'atende_remoto')::boolean, 'online' = ANY(v_modalidades) OR 'hibrido' = ANY(v_modalidades)),
     COALESCE(NULLIF(_dados->>'raio_atendimento_km', '')::int, 100), true, now(),
     'pendente', 'base', false, v_versoes->>'termos_especialista', now(), COALESCE(_dados->>'origem', 'sistema'), v_parceiro,
     COALESCE(NULLIF(_dados->>'pais', ''), COALESCE(public.marketye_config('localizacao')->>'pais', 'BR')),
     COALESCE(NULLIF(_dados->>'moeda', ''), COALESCE(public.marketye_config('localizacao')->>'moeda', 'BRL')),
     NULLIF(_dados->>'site_url', ''))
  RETURNING id INTO v_id;

  INSERT INTO public.marketplace_consentimentos (profissional_id, tipo, versao, ip, user_agent, origem)
  SELECT v_id, t.tipo, COALESCE(v_versoes->>t.tipo, 'sem-versao'), v_ip, v_ua, COALESCE(_dados->>'origem', 'sistema')
  FROM (VALUES ('termos_especialista'), ('privacidade_nao_usuario'), ('codigo_etica')) AS t(tipo);

  INSERT INTO public.marketplace_reputacao (profissional_id, protegido_ate)
  VALUES (v_id, now() + make_interval(days => COALESCE((public.marketye_config('protecao_novato')->>'dias')::int, 30)))
  ON CONFLICT (profissional_id) DO NOTHING;

  IF v_parceiro IS NOT NULL AND to_regclass('public.parceiros') IS NOT NULL THEN
    UPDATE public.parceiros SET marketplace_profissional_id = v_id WHERE id = v_parceiro AND marketplace_profissional_id IS NULL;
  END IF;

  INSERT INTO public.marketplace_audit_log (tenant_id, profissional_id, acao, descricao, dados, usuario_id)
  VALUES (NULLIF(_dados->>'tenant_origem', '')::uuid, v_id, 'especialista_cadastrado', 'Cadastro de especialista recebido para verificação',
          json_build_object('origem', COALESCE(_dados->>'origem', 'sistema'), 'tipo_pessoa', v_tipo), p_user_id);

  RETURN jsonb_build_object('id', v_id, 'status', 'pendente', 'ja_existia', false);
END $marketye_cadastrar_especialista_para$;
REVOKE ALL ON FUNCTION public.marketye_cadastrar_especialista_para(uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.marketye_cadastrar_especialista_para(uuid, jsonb) TO service_role;

-- Quem já tem conta (cliente, parceiro) se cadastra autenticado.
CREATE OR REPLACE FUNCTION public.marketye_cadastrar_especialista(_dados jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_cadastrar_especialista$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre na sua conta para se cadastrar'; END IF;
  -- tenant_origem só registra de qual empresa a pessoa se cadastrou (a entidade continua global).
  RETURN public.marketye_cadastrar_especialista_para(auth.uid(), COALESCE(_dados, '{}'::jsonb)
    || jsonb_build_object('origem', COALESCE(_dados->>'origem', 'sistema'), 'tenant_origem', public.get_user_tenant_id()));
END $marketye_cadastrar_especialista$;
GRANT EXECUTE ON FUNCTION public.marketye_cadastrar_especialista(jsonb) TO authenticated;

-- Aceite de termos versionado (RN-018), sempre por função.
CREATE OR REPLACE FUNCTION public.marketye_aceitar_termos(p_tipo text, p_versao text DEFAULT NULL, p_user_agent text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_aceitar_termos$
DECLARE v_id uuid := public.marketye_meu_id(); v_versao text;
BEGIN
  IF v_id IS NULL THEN RAISE EXCEPTION 'Sem cadastro de especialista'; END IF;
  IF p_tipo NOT IN ('termos_especialista', 'privacidade_nao_usuario', 'codigo_etica') THEN RAISE EXCEPTION 'Tipo de termo desconhecido'; END IF;
  v_versao := COALESCE(p_versao, public.marketye_config('termos_versoes')->>p_tipo, 'sem-versao');
  INSERT INTO public.marketplace_consentimentos (profissional_id, tipo, versao, user_agent, origem) VALUES (v_id, p_tipo, v_versao, p_user_agent, 'portal');
  IF p_tipo = 'termos_especialista' THEN
    UPDATE public.marketplace_profissionais SET consentimento_versao = v_versao, consentimento_em = now() WHERE id = v_id;
  END IF;
  RETURN jsonb_build_object('tipo', p_tipo, 'versao', v_versao, 'aceito_em', now());
END $marketye_aceitar_termos$;
GRANT EXECUTE ON FUNCTION public.marketye_aceitar_termos(text, text, text) TO authenticated;

-- ---------------------------------------------------------------------
-- 2) Reputação em dois eixos e níveis (RF-009, RF-011, RN-005/009/010/029)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marketye_nivel_indice(p_nivel text)
RETURNS int LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $marketye_nivel_indice$
  SELECT COALESCE((SELECT (i - 1)::int FROM jsonb_array_elements_text(COALESCE(public.marketye_config('niveis')->'ordem', '["novo","bronze","prata","ouro","top"]'::jsonb)) WITH ORDINALITY AS o(nome, i) WHERE o.nome = p_nivel), 0);
$marketye_nivel_indice$;
GRANT EXECUTE ON FUNCTION public.marketye_nivel_indice(text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.marketye_recalcular_reputacao(p_profissional_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_recalcular_reputacao$
DECLARE
  v_cfg_saude jsonb := COALESCE(public.marketye_config('saude_recente'), '{"janela_dias":90,"verde":75,"amarelo":50}'::jsonb);
  v_cfg_piso  jsonb := COALESCE(public.marketye_config('piso_nota'), '{"nota":3.5,"minimo_avaliacoes":3}'::jsonb);
  v_cfg_niv   jsonb := COALESCE(public.marketye_config('niveis'), '{}'::jsonb);
  v_cfg_nov   jsonb := COALESCE(public.marketye_config('protecao_novato'), '{"dias":30,"ate_avaliacoes":3}'::jsonb);
  v_janela interval; v_media_total numeric; v_total_aval int; v_media_90 numeric; v_aval_90 int;
  v_leads_90 int; v_resp_90 int; v_tempo_med int; v_canc_90 int; v_concl_90 int; v_ocorr_90 int;
  v_serv_total int; v_cli_total int; v_cli_90 int; v_taxa_resp numeric; v_taxa_canc numeric;
  v_score numeric; v_cor text; v_abaixo boolean; v_ordem text[]; v_nivel_atual text; v_alvo text; v_req jsonb; v_i int;
  v_aviso timestamptz; v_amort int; v_criado timestamptz; v_protegido timestamptz; v_resultado jsonb;
BEGIN
  IF p_profissional_id IS NULL THEN RETURN NULL; END IF;
  v_janela := make_interval(days => COALESCE((v_cfg_saude->>'janela_dias')::int, 90));
  SELECT created_at INTO v_criado FROM public.marketplace_profissionais WHERE id = p_profissional_id;
  IF v_criado IS NULL THEN RETURN NULL; END IF;

  SELECT round(avg(nota_geral)::numeric, 2), count(*) INTO v_media_total, v_total_aval
  FROM public.marketplace_avaliacoes WHERE profissional_id = p_profissional_id AND direcao = 'cliente_para_especialista' AND NOT moderada;
  SELECT round(avg(nota_geral)::numeric, 2), count(*) INTO v_media_90, v_aval_90
  FROM public.marketplace_avaliacoes WHERE profissional_id = p_profissional_id AND direcao = 'cliente_para_especialista' AND NOT moderada AND created_at >= now() - v_janela;

  SELECT count(*), count(*) FILTER (WHERE primeira_resposta_em IS NOT NULL),
         percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (primeira_resposta_em - created_at)) / 60) FILTER (WHERE primeira_resposta_em IS NOT NULL)
  INTO v_leads_90, v_resp_90, v_tempo_med
  FROM public.marketplace_leads WHERE profissional_id = p_profissional_id AND created_at >= now() - v_janela AND created_at < now() - interval '1 hour';

  SELECT count(*) FILTER (WHERE status = 'cancelada'), count(*) FILTER (WHERE status = 'concluida') INTO v_canc_90, v_concl_90
  FROM public.marketplace_contratacoes WHERE profissional_id = p_profissional_id AND created_at >= now() - v_janela;
  SELECT count(*) INTO v_ocorr_90 FROM public.marketplace_ocorrencias WHERE profissional_id = p_profissional_id AND reflexo_visibilidade AND created_at >= now() - v_janela;

  SELECT count(*) INTO v_serv_total FROM (
    SELECT id FROM public.marketplace_contratacoes WHERE profissional_id = p_profissional_id AND status = 'concluida'
    UNION ALL SELECT id FROM public.marketplace_leads WHERE profissional_id = p_profissional_id AND status = 'ganho') x;
  SELECT count(DISTINCT tenant_id) INTO v_cli_total FROM (
    SELECT tenant_id FROM public.marketplace_contratacoes WHERE profissional_id = p_profissional_id AND status = 'concluida'
    UNION ALL SELECT tenant_id FROM public.marketplace_leads WHERE profissional_id = p_profissional_id AND status = 'ganho') x;
  SELECT count(DISTINCT tenant_id) INTO v_cli_90 FROM (
    SELECT tenant_id FROM public.marketplace_contratacoes WHERE profissional_id = p_profissional_id AND status = 'concluida' AND created_at >= now() - v_janela
    UNION ALL SELECT tenant_id FROM public.marketplace_leads WHERE profissional_id = p_profissional_id AND status = 'ganho' AND created_at >= now() - v_janela) x;

  v_taxa_resp := CASE WHEN v_leads_90 > 0 THEN round(v_resp_90::numeric / v_leads_90, 3) END;
  v_taxa_canc := CASE WHEN (v_canc_90 + v_concl_90) > 0 THEN round(v_canc_90::numeric / (v_canc_90 + v_concl_90), 3) END;

  -- Eixo A — saúde recente: reflete o "agora"; sem dado recente fica cinza (neutro).
  IF v_aval_90 = 0 AND v_leads_90 = 0 AND (v_canc_90 + v_concl_90) = 0 AND v_ocorr_90 = 0 THEN
    v_score := 60; v_cor := 'cinza';
  ELSE
    v_score := 100 * (0.5 * COALESCE(v_media_90 / 5, 0.8) + 0.25 * COALESCE(v_taxa_resp, 0.8) + 0.25 * (1 - COALESCE(v_taxa_canc, 0)))
               - 10 * COALESCE(v_ocorr_90, 0);
    v_score := GREATEST(0, LEAST(100, round(v_score, 2)));
    v_cor := CASE WHEN v_score >= COALESCE((v_cfg_saude->>'verde')::numeric, 75) THEN 'verde'
                  WHEN v_score >= COALESCE((v_cfg_saude->>'amarelo')::numeric, 50) THEN 'amarelo' ELSE 'vermelho' END;
  END IF;
  v_abaixo := COALESCE(v_total_aval, 0) >= COALESCE((v_cfg_piso->>'minimo_avaliacoes')::int, 3)
              AND COALESCE(v_media_total, 5) < COALESCE((v_cfg_piso->>'nota')::numeric, 3.5);
  v_protegido := CASE WHEN COALESCE(v_total_aval, 0) < COALESCE((v_cfg_nov->>'ate_avaliacoes')::int, 3)
                      THEN v_criado + make_interval(days => COALESCE((v_cfg_nov->>'dias')::int, 30)) END;

  -- Eixo B — nível: só sobe com TODAS as métricas ao mesmo tempo (RN-009);
  -- só desce com aviso + amortecedor (RN-010); só afeta visibilidade (RN-029).
  INSERT INTO public.marketplace_reputacao (profissional_id) VALUES (p_profissional_id) ON CONFLICT (profissional_id) DO NOTHING;
  SELECT nivel, nivel_aviso_em INTO v_nivel_atual, v_aviso FROM public.marketplace_reputacao WHERE profissional_id = p_profissional_id;
  v_ordem := ARRAY(SELECT jsonb_array_elements_text(COALESCE(v_cfg_niv->'ordem', '["novo","bronze","prata","ouro","top"]'::jsonb)));
  v_alvo := v_ordem[1];
  FOR v_i IN 2..COALESCE(array_length(v_ordem, 1), 1) LOOP
    v_req := v_cfg_niv->'requisitos'->v_ordem[v_i];
    IF v_req IS NULL THEN EXIT; END IF;
    IF v_serv_total >= COALESCE((v_req->>'servicos')::int, 0)
       AND v_cli_total >= COALESCE((v_req->>'clientes_unicos')::int, 0)
       AND COALESCE(v_media_total, 0) >= COALESCE((v_req->>'media')::numeric, 0)
       AND COALESCE(v_taxa_resp, 1) >= COALESCE((v_req->>'taxa_resposta')::numeric, 0)
       AND COALESCE(v_ocorr_90, 0) <= COALESCE((v_req->>'ocorrencias')::int, 0) THEN
      v_alvo := v_ordem[v_i];
    ELSE
      EXIT;
    END IF;
  END LOOP;
  v_amort := COALESCE((v_cfg_niv->>'amortecedor_dias')::int, 14);

  IF public.marketye_nivel_indice(v_alvo) > public.marketye_nivel_indice(v_nivel_atual) THEN
    UPDATE public.marketplace_reputacao SET nivel = v_alvo, nivel_desde = now(), nivel_aviso_em = NULL, nivel_aviso_motivo = NULL WHERE profissional_id = p_profissional_id;
    v_nivel_atual := v_alvo;
  ELSIF public.marketye_nivel_indice(v_alvo) < public.marketye_nivel_indice(v_nivel_atual) THEN
    IF v_aviso IS NULL THEN
      UPDATE public.marketplace_reputacao SET nivel_aviso_em = now(),
        nivel_aviso_motivo = format('As métricas atuais correspondem ao nível %s. Há %s dias para recuperar antes do ajuste de nível (só afeta a visibilidade).', v_alvo, v_amort)
      WHERE profissional_id = p_profissional_id;
    ELSIF v_aviso < now() - make_interval(days => v_amort) THEN
      UPDATE public.marketplace_reputacao SET nivel = v_alvo, nivel_desde = now(), nivel_aviso_em = NULL, nivel_aviso_motivo = NULL WHERE profissional_id = p_profissional_id;
      v_nivel_atual := v_alvo;
    END IF;
  ELSE
    UPDATE public.marketplace_reputacao SET nivel_aviso_em = NULL, nivel_aviso_motivo = NULL WHERE profissional_id = p_profissional_id AND nivel_aviso_em IS NOT NULL;
  END IF;

  UPDATE public.marketplace_reputacao SET
    saude_score = v_score, saude_cor = v_cor, media_90d = v_media_90, avaliacoes_90d = COALESCE(v_aval_90, 0),
    clientes_unicos_total = COALESCE(v_cli_total, 0), clientes_unicos_90d = COALESCE(v_cli_90, 0), taxa_resposta_90d = v_taxa_resp,
    tempo_resposta_mediano_min = v_tempo_med, taxa_cancelamento_90d = v_taxa_canc, ocorrencias_90d = COALESCE(v_ocorr_90, 0),
    servicos_concluidos_total = COALESCE(v_serv_total, 0), abaixo_piso = v_abaixo, protegido_ate = v_protegido, calculado_em = now()
  WHERE profissional_id = p_profissional_id;

  UPDATE public.marketplace_profissionais SET nota_media = COALESCE(v_media_total, 0), total_avaliacoes = COALESCE(v_total_aval, 0),
    total_servicos_executados = COALESCE(v_serv_total, 0) WHERE id = p_profissional_id;

  SELECT to_jsonb(r) INTO v_resultado FROM public.marketplace_reputacao r WHERE r.profissional_id = p_profissional_id;
  RETURN v_resultado;
END $marketye_recalcular_reputacao$;
REVOKE ALL ON FUNCTION public.marketye_recalcular_reputacao(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.marketye_recalcular_reputacao(uuid) TO service_role;

-- ---------------------------------------------------------------------
-- 3) Portal do especialista (RF-004)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marketye_meu_portal()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_meu_portal$
DECLARE v_id uuid := public.marketye_meu_id(); v_perfil jsonb; v_rep jsonb; v_versoes jsonb; v_niveis jsonb; v_nivel text; v_ordem text[]; v_prox text; v_i int;
BEGIN
  IF v_id IS NULL THEN RETURN NULL; END IF;
  SELECT to_jsonb(p) - 'user_id' INTO v_perfil FROM public.marketplace_profissionais p WHERE p.id = v_id;
  SELECT to_jsonb(r) INTO v_rep FROM public.marketplace_reputacao r WHERE r.profissional_id = v_id;
  v_versoes := COALESCE(public.marketye_config('termos_versoes'), '{}'::jsonb);
  v_niveis := COALESCE(public.marketye_config('niveis'), '{}'::jsonb);
  v_nivel := COALESCE(v_rep->>'nivel', 'novo');
  v_ordem := ARRAY(SELECT jsonb_array_elements_text(COALESCE(v_niveis->'ordem', '["novo","bronze","prata","ouro","top"]'::jsonb)));
  v_prox := NULL;
  FOR v_i IN 1..COALESCE(array_length(v_ordem, 1), 1) LOOP
    IF v_ordem[v_i] = v_nivel AND v_i < array_length(v_ordem, 1) THEN v_prox := v_ordem[v_i + 1]; END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'perfil', v_perfil,
    'reputacao', v_rep,
    'nivel', jsonb_build_object('atual', v_nivel, 'proximo', v_prox, 'requisitos_proximo', v_niveis->'requisitos'->v_prox,
                                'aviso_em', v_rep->>'nivel_aviso_em', 'aviso_motivo', v_rep->>'nivel_aviso_motivo', 'ordem', to_jsonb(v_ordem)),
    'completude', (SELECT round(100.0 * (
        (v_perfil->>'foto_url' IS NOT NULL)::int + (COALESCE(v_perfil->>'bio', '') <> '')::int + (v_perfil->>'registro_profissional' IS NOT NULL)::int
        + (jsonb_array_length(COALESCE(v_perfil->'especialidades', '[]'::jsonb)) > 0)::int + (v_perfil->>'cidade' IS NOT NULL)::int
        + (v_perfil->>'video_url' IS NOT NULL)::int + (v_perfil->>'telefone' IS NOT NULL)::int
        + (EXISTS (SELECT 1 FROM public.marketplace_servicos s WHERE s.profissional_id = v_id AND s.status = 'publicado'))::int) / 8)),
    'anuncios', COALESCE((SELECT jsonb_agg(to_jsonb(s) || jsonb_build_object('categoria_nome', c.nome, 'categoria_slug', c.slug, 'exige_registro', c.exige_registro) ORDER BY s.created_at DESC)
                          FROM public.marketplace_servicos s LEFT JOIN public.marketplace_categorias c ON c.id = s.categoria_id WHERE s.profissional_id = v_id AND s.status <> 'removido'), '[]'::jsonb),
    'leads', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                'id', l.id, 'status', l.status, 'created_at', l.created_at, 'contato_liberado', l.contato_liberado, 'primeira_resposta_em', l.primeira_resposta_em,
                'ultima_mensagem_em', l.ultima_mensagem_em, 'servico_nome', s.nome, 'empresa_nome', t.nome, 'origem_modulo', l.origem_modulo,
                'obrigacao_legal', l.obrigacao_legal, 'cupom_codigo', l.cupom_codigo, 'ganho_em', l.ganho_em,
                'reputacao_empresa', (SELECT jsonb_build_object('media', round(avg(a.nota_geral)::numeric, 1), 'total', count(*))
                                      FROM public.marketplace_avaliacoes a WHERE a.tenant_id = l.tenant_id AND a.direcao = 'especialista_para_cliente'),
                'ultima_mensagem', (SELECT m.texto FROM public.marketplace_lead_mensagens m WHERE m.lead_id = l.id ORDER BY m.created_at DESC LIMIT 1),
                'avaliei', EXISTS (SELECT 1 FROM public.marketplace_avaliacoes a WHERE a.lead_id = l.id AND a.direcao = 'especialista_para_cliente')
              ) ORDER BY COALESCE(l.ultima_mensagem_em, l.created_at) DESC)
              FROM public.marketplace_leads l LEFT JOIN public.marketplace_servicos s ON s.id = l.servico_id LEFT JOIN public.tenants t ON t.id = l.tenant_id
              WHERE l.profissional_id = v_id), '[]'::jsonb),
    'metricas', jsonb_build_object(
      'leads_30d', (SELECT count(*) FROM public.marketplace_leads WHERE profissional_id = v_id AND created_at >= now() - interval '30 days'),
      'leads_ganhos_30d', (SELECT count(*) FROM public.marketplace_leads WHERE profissional_id = v_id AND status = 'ganho' AND ganho_em >= now() - interval '30 days'),
      'sem_resposta', (SELECT count(*) FROM public.marketplace_leads WHERE profissional_id = v_id AND status = 'novo'),
      'avaliacoes', (SELECT count(*) FROM public.marketplace_avaliacoes WHERE profissional_id = v_id AND direcao = 'cliente_para_especialista')),
    'avaliacoes', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', a.id, 'nota_geral', a.nota_geral, 'comentario', a.comentario, 'created_at', a.created_at,
                              'resposta', a.resposta, 'criterios', a.criterios, 'pontualidade', a.pontualidade, 'clareza', a.clareza,
                              'aderencia_escopo', a.aderencia_escopo, 'profissionalismo', a.profissionalismo) ORDER BY a.created_at DESC)
                            FROM public.marketplace_avaliacoes a WHERE a.profissional_id = v_id AND a.direcao = 'cliente_para_especialista' AND NOT a.moderada), '[]'::jsonb),
    'consentimentos', COALESCE((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.aceito_em DESC) FROM public.marketplace_consentimentos c WHERE c.profissional_id = v_id), '[]'::jsonb),
    'termos_pendentes', COALESCE((SELECT jsonb_agg(jsonb_build_object('tipo', t.tipo, 'versao', v_versoes->>t.tipo))
                                  FROM (VALUES ('termos_especialista'), ('privacidade_nao_usuario'), ('codigo_etica')) AS t(tipo)
                                  WHERE v_versoes->>t.tipo IS NOT NULL AND NOT EXISTS (
                                    SELECT 1 FROM public.marketplace_consentimentos c WHERE c.profissional_id = v_id AND c.tipo = t.tipo AND c.versao = v_versoes->>t.tipo)), '[]'::jsonb),
    'contestacoes', COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM public.marketplace_contestacoes x WHERE x.profissional_id = v_id), '[]'::jsonb),
    'ocorrencias', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', o.id, 'tipo', o.tipo, 'descricao', o.descricao, 'created_at', o.created_at, 'reflexo_visibilidade', o.reflexo_visibilidade) ORDER BY o.created_at DESC)
                             FROM public.marketplace_ocorrencias o WHERE o.profissional_id = v_id), '[]'::jsonb),
    'cupons', COALESCE((SELECT jsonb_agg(to_jsonb(k) ORDER BY k.created_at DESC) FROM public.marketplace_cupons k WHERE k.profissional_id = v_id), '[]'::jsonb),
    'destaques', COALESCE((SELECT jsonb_agg(to_jsonb(d) ORDER BY d.fim DESC) FROM public.marketplace_destaques d WHERE d.profissional_id = v_id), '[]'::jsonb),
    'autonomia_eventos', (SELECT count(*) FROM public.marketplace_autonomia_eventos WHERE profissional_id = v_id),
    'termos_versoes', v_versoes,
    'parceiro', CASE WHEN v_perfil->>'parceiro_id' IS NOT NULL THEN jsonb_build_object('id', v_perfil->>'parceiro_id') END
  );
END $marketye_meu_portal$;
GRANT EXECUTE ON FUNCTION public.marketye_meu_portal() TO authenticated;

CREATE OR REPLACE FUNCTION public.marketye_meu_perfil_salvar(_dados jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_meu_perfil_salvar$
DECLARE v_id uuid := public.marketye_meu_id(); v_mod text[];
BEGIN
  IF v_id IS NULL THEN RAISE EXCEPTION 'Sem cadastro de especialista'; END IF;
  IF _dados ? 'modalidades' THEN v_mod := ARRAY(SELECT jsonb_array_elements_text(_dados->'modalidades')); END IF;
  UPDATE public.marketplace_profissionais SET
    nome_completo = CASE WHEN status = 'pendente' AND length(COALESCE(_dados->>'nome_completo', '')) >= 3 THEN _dados->>'nome_completo' ELSE nome_completo END,
    telefone = CASE WHEN _dados ? 'telefone' THEN NULLIF(_dados->>'telefone', '') ELSE telefone END,
    bio = CASE WHEN _dados ? 'bio' THEN NULLIF(_dados->>'bio', '') ELSE bio END,
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
END $marketye_meu_perfil_salvar$;
GRANT EXECUTE ON FUNCTION public.marketye_meu_perfil_salvar(jsonb) TO authenticated;

-- ---------------------------------------------------------------------
-- 4) Anúncios (RF-003, RN-011, RN-013): salvar como rascunho, publicar por função
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marketye_anuncio_salvar(_dados jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_anuncio_salvar$
DECLARE v_prof uuid := public.marketye_meu_id(); v_id uuid := NULLIF(_dados->>'id', '')::uuid; v_cat uuid := NULLIF(_dados->>'categoria_id', '')::uuid; v_obr text[];
BEGIN
  IF v_prof IS NULL THEN RAISE EXCEPTION 'Sem cadastro de especialista'; END IF;
  IF length(trim(COALESCE(_dados->>'nome', ''))) < 5 THEN RAISE EXCEPTION 'Dê um título ao anúncio (mínimo 5 letras)'; END IF;
  IF length(trim(COALESCE(_dados->>'descricao', ''))) < 20 THEN RAISE EXCEPTION 'Descreva o serviço (mínimo 20 letras)'; END IF;
  IF COALESCE(_dados->>'tipo_preco', 'sob_orcamento') <> 'sob_orcamento' AND COALESCE(NULLIF(_dados->>'preco_referencia', '')::numeric, 0) <= 0 THEN
    RAISE EXCEPTION 'Informe um preço-base ou marque "sob orçamento".';
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
END $marketye_anuncio_salvar$;
GRANT EXECUTE ON FUNCTION public.marketye_anuncio_salvar(jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.marketye_anuncio_publicar(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_anuncio_publicar$
DECLARE v_prof uuid := public.marketye_meu_id(); s record; p record; c record;
BEGIN
  IF v_prof IS NULL THEN RAISE EXCEPTION 'Sem cadastro de especialista'; END IF;
  SELECT * INTO s FROM public.marketplace_servicos WHERE id = p_id AND profissional_id = v_prof;
  IF s.id IS NULL THEN RAISE EXCEPTION 'Anúncio não encontrado'; END IF;
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
END $marketye_anuncio_publicar$;
GRANT EXECUTE ON FUNCTION public.marketye_anuncio_publicar(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.marketye_anuncio_status(p_id uuid, p_status text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_anuncio_status$
DECLARE v_prof uuid := public.marketye_meu_id();
BEGIN
  IF v_prof IS NULL THEN RAISE EXCEPTION 'Sem cadastro de especialista'; END IF;
  IF p_status NOT IN ('pausado', 'removido', 'rascunho') THEN RAISE EXCEPTION 'Use marketye_anuncio_publicar para publicar'; END IF;
  UPDATE public.marketplace_servicos SET status = p_status, ativo = (p_status <> 'removido') WHERE id = p_id AND profissional_id = v_prof;
  IF NOT FOUND THEN RAISE EXCEPTION 'Anúncio não encontrado'; END IF;
  RETURN jsonb_build_object('id', p_id, 'status', p_status);
END $marketye_anuncio_status$;
GRANT EXECUTE ON FUNCTION public.marketye_anuncio_status(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.marketye_cupom_salvar(_dados jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_cupom_salvar$
DECLARE v_prof uuid := public.marketye_meu_id(); v_id uuid;
BEGIN
  IF v_prof IS NULL THEN RAISE EXCEPTION 'Sem cadastro de especialista'; END IF;
  IF COALESCE(_dados->>'codigo', '') !~ '^[A-Za-z0-9_-]{3,20}$' THEN RAISE EXCEPTION 'Código do cupom: 3 a 20 letras/números'; END IF;
  INSERT INTO public.marketplace_cupons (profissional_id, codigo, descricao, desconto_percentual, validade, limite_uso)
  VALUES (v_prof, upper(_dados->>'codigo'), NULLIF(_dados->>'descricao', ''), (_dados->>'desconto_percentual')::numeric,
          NULLIF(_dados->>'validade', '')::date, NULLIF(_dados->>'limite_uso', '')::int)
  ON CONFLICT (profissional_id, codigo) DO UPDATE SET descricao = EXCLUDED.descricao, desconto_percentual = EXCLUDED.desconto_percentual,
    validade = EXCLUDED.validade, limite_uso = EXCLUDED.limite_uso, ativo = COALESCE((_dados->>'ativo')::boolean, true)
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id);
END $marketye_cupom_salvar$;
GRANT EXECUTE ON FUNCTION public.marketye_cupom_salvar(jsonb) TO authenticated;

-- ---------------------------------------------------------------------
-- 5) Leads (RF-012, RN-020, RN-027, RN-030)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marketye_lead_papel(p_lead_id uuid)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $marketye_lead_papel$
DECLARE l record;
BEGIN
  SELECT tenant_id, profissional_id INTO l FROM public.marketplace_leads WHERE id = p_lead_id;
  IF l.tenant_id IS NULL THEN RETURN NULL; END IF;
  IF l.profissional_id = public.marketye_meu_id() THEN RETURN 'especialista'; END IF;
  IF l.tenant_id = public.get_user_tenant_id() THEN RETURN 'cliente'; END IF;
  IF public.is_superadmin(auth.uid()) THEN RETURN 'moderador'; END IF;
  RETURN NULL;
END $marketye_lead_papel$;
GRANT EXECUTE ON FUNCTION public.marketye_lead_papel(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.marketye_abrir_lead(p_profissional_id uuid, p_servico_id uuid, p_mensagem text,
                                                      p_origem_modulo text DEFAULT NULL, p_origem_id uuid DEFAULT NULL, p_obrigacao text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_abrir_lead$
DECLARE v_tenant uuid := public.get_user_tenant_id(); v_lead uuid; v_nome text; v_cupom text; v_mascarar boolean; v_texto text; v_existente uuid;
BEGIN
  IF v_tenant IS NULL THEN RAISE EXCEPTION 'Só usuários de uma empresa cliente abrem contato'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.marketplace_profissionais WHERE id = p_profissional_id AND status = 'ativo' AND excluido_em IS NULL) THEN
    RAISE EXCEPTION 'Especialista indisponível no momento';
  END IF;
  IF length(trim(COALESCE(p_mensagem, ''))) < 5 THEN RAISE EXCEPTION 'Escreva uma mensagem com o que você precisa'; END IF;
  SELECT id INTO v_existente FROM public.marketplace_leads WHERE tenant_id = v_tenant AND profissional_id = p_profissional_id
    AND status IN ('novo', 'respondido', 'qualificado') ORDER BY created_at DESC LIMIT 1;
  IF v_existente IS NOT NULL THEN
    PERFORM public.marketye_lead_mensagem(v_existente, p_mensagem);
    RETURN jsonb_build_object('id', v_existente, 'reaproveitado', true);
  END IF;
  SELECT nome_completo INTO v_nome FROM public.profiles WHERE user_id = auth.uid() LIMIT 1;
  SELECT codigo INTO v_cupom FROM public.marketplace_cupons WHERE profissional_id = p_profissional_id AND ativo
    AND (validade IS NULL OR validade >= CURRENT_DATE) AND (limite_uso IS NULL OR usos < limite_uso) ORDER BY desconto_percentual DESC LIMIT 1;
  v_mascarar := COALESCE(public.marketye_config('mascaramento_contato')->>'ate', 'contato_qualificado') <> 'nunca';
  v_texto := CASE WHEN v_mascarar THEN public.marketye_mascarar_contato(p_mensagem) ELSE p_mensagem END;

  INSERT INTO public.marketplace_leads (tenant_id, profissional_id, servico_id, criado_por, solicitante_nome, origem_modulo, origem_id, obrigacao_legal, cupom_codigo, ultima_mensagem_em)
  VALUES (v_tenant, p_profissional_id, p_servico_id, auth.uid(), v_nome, p_origem_modulo, p_origem_id, p_obrigacao, v_cupom, now()) RETURNING id INTO v_lead;
  INSERT INTO public.marketplace_lead_mensagens (lead_id, autor_tipo, autor_id, texto, texto_original, mascarada, sinal_saida)
  VALUES (v_lead, 'cliente', auth.uid(), v_texto, CASE WHEN v_texto <> p_mensagem THEN p_mensagem END, v_texto <> p_mensagem, public.marketye_texto_tem_contato(p_mensagem));
  IF v_cupom IS NOT NULL THEN
    INSERT INTO public.marketplace_lead_mensagens (lead_id, autor_tipo, texto) VALUES (v_lead, 'sistema', format('Este especialista tem o cupom %s ativo para esta conversa.', v_cupom));
    UPDATE public.marketplace_cupons SET usos = usos + 1 WHERE profissional_id = p_profissional_id AND codigo = v_cupom;
  END IF;
  RETURN jsonb_build_object('id', v_lead, 'reaproveitado', false);
END $marketye_abrir_lead$;
GRANT EXECUTE ON FUNCTION public.marketye_abrir_lead(uuid, uuid, text, text, uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.marketye_lead_mensagem(p_lead_id uuid, p_texto text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_lead_mensagem$
DECLARE v_papel text := public.marketye_lead_papel(p_lead_id); l record; v_texto text; v_mascarar boolean; v_id uuid;
BEGIN
  IF v_papel NOT IN ('cliente', 'especialista') THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  IF length(trim(COALESCE(p_texto, ''))) = 0 THEN RAISE EXCEPTION 'Mensagem vazia'; END IF;
  SELECT * INTO l FROM public.marketplace_leads WHERE id = p_lead_id;
  IF l.status IN ('perdido', 'encerrado') THEN RAISE EXCEPTION 'Esta conversa foi encerrada'; END IF;
  v_mascarar := NOT l.contato_liberado AND COALESCE(public.marketye_config('mascaramento_contato')->>'ate', 'contato_qualificado') <> 'nunca';
  v_texto := CASE WHEN v_mascarar THEN public.marketye_mascarar_contato(p_texto) ELSE p_texto END;
  INSERT INTO public.marketplace_lead_mensagens (lead_id, autor_tipo, autor_id, texto, texto_original, mascarada, sinal_saida)
  VALUES (p_lead_id, v_papel, auth.uid(), v_texto, CASE WHEN v_texto <> p_texto THEN p_texto END, v_texto <> p_texto, public.marketye_texto_tem_contato(p_texto))
  RETURNING id INTO v_id;
  UPDATE public.marketplace_leads SET ultima_mensagem_em = now(),
    primeira_resposta_em = CASE WHEN v_papel = 'especialista' AND primeira_resposta_em IS NULL THEN now() ELSE primeira_resposta_em END,
    status = CASE WHEN v_papel = 'especialista' AND status = 'novo' THEN 'respondido' ELSE status END
  WHERE id = p_lead_id;
  RETURN jsonb_build_object('id', v_id, 'mascarada', v_texto <> p_texto);
END $marketye_lead_mensagem$;
GRANT EXECUTE ON FUNCTION public.marketye_lead_mensagem(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.marketye_lead_liberar_contato(p_lead_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_lead_liberar_contato$
BEGIN
  IF public.marketye_lead_papel(p_lead_id) <> 'cliente' THEN RAISE EXCEPTION 'Só a empresa cliente libera o contato'; END IF;
  UPDATE public.marketplace_leads SET contato_liberado = true, contato_liberado_em = COALESCE(contato_liberado_em, now()),
    status = CASE WHEN status IN ('novo', 'respondido') THEN 'qualificado' ELSE status END, ultima_mensagem_em = now() WHERE id = p_lead_id;
  INSERT INTO public.marketplace_lead_mensagens (lead_id, autor_tipo, texto)
  VALUES (p_lead_id, 'sistema', 'A empresa liberou o contato direto. Combinem os detalhes e, ao fechar, marquem "serviço combinado" para habilitar a avaliação.');
  RETURN jsonb_build_object('id', p_lead_id, 'contato_liberado', true);
END $marketye_lead_liberar_contato$;
GRANT EXECUTE ON FUNCTION public.marketye_lead_liberar_contato(uuid) TO authenticated;

-- Fechamento do lead. Recusar não gera reflexo algum (RN-030): o prestador é livre.
CREATE OR REPLACE FUNCTION public.marketye_lead_status(p_lead_id uuid, p_status text, p_motivo text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_lead_status$
DECLARE v_papel text := public.marketye_lead_papel(p_lead_id); v_prof uuid;
BEGIN
  IF v_papel NOT IN ('cliente', 'especialista') THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  IF p_status NOT IN ('ganho', 'perdido', 'encerrado') THEN RAISE EXCEPTION 'Situação inválida'; END IF;
  UPDATE public.marketplace_leads SET status = p_status, ganho_em = CASE WHEN p_status = 'ganho' THEN COALESCE(ganho_em, now()) ELSE ganho_em END,
    contato_liberado = CASE WHEN p_status = 'ganho' THEN true ELSE contato_liberado END, ultima_mensagem_em = now()
  WHERE id = p_lead_id RETURNING profissional_id INTO v_prof;
  INSERT INTO public.marketplace_lead_mensagens (lead_id, autor_tipo, autor_id, texto)
  VALUES (p_lead_id, 'sistema', auth.uid(), CASE p_status WHEN 'ganho' THEN 'Serviço combinado. Os dois lados já podem avaliar.'
                                                   WHEN 'perdido' THEN 'A empresa encerrou esta conversa sem contratar.'
                                                   ELSE COALESCE('Conversa encerrada. ' || p_motivo, 'Conversa encerrada.') END);
  IF p_status = 'ganho' THEN PERFORM public.marketye_recalcular_reputacao(v_prof); END IF;
  RETURN jsonb_build_object('id', p_lead_id, 'status', p_status);
END $marketye_lead_status$;
GRANT EXECUTE ON FUNCTION public.marketye_lead_status(uuid, text, text) TO authenticated;

-- Contato da outra parte, só depois da liberação (RN-020).
CREATE OR REPLACE FUNCTION public.marketye_lead_contato(p_lead_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_lead_contato$
DECLARE v_papel text := public.marketye_lead_papel(p_lead_id); l record; v_email text;
BEGIN
  IF v_papel IS NULL THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  SELECT * INTO l FROM public.marketplace_leads WHERE id = p_lead_id;
  IF NOT l.contato_liberado THEN RETURN jsonb_build_object('liberado', false); END IF;
  IF v_papel IN ('cliente', 'moderador') THEN
    RETURN (SELECT jsonb_build_object('liberado', true, 'nome', p.nome_completo, 'email', p.email, 'telefone', p.telefone, 'site_url', p.site_url)
            FROM public.marketplace_profissionais p WHERE p.id = l.profissional_id);
  END IF;
  SELECT email INTO v_email FROM auth.users WHERE id = l.criado_por;
  RETURN (SELECT jsonb_build_object('liberado', true, 'empresa', t.nome, 'solicitante', l.solicitante_nome, 'email', v_email, 'telefone', pr.telefone)
          FROM public.tenants t LEFT JOIN public.profiles pr ON pr.user_id = l.criado_por WHERE t.id = l.tenant_id);
END $marketye_lead_contato$;
GRANT EXECUTE ON FUNCTION public.marketye_lead_contato(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.marketye_lead_vincular_documento(p_lead_id uuid, p_documento_id uuid, p_tipo text DEFAULT 'proposta')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_lead_vincular_documento$
DECLARE v_id uuid;
BEGIN
  IF public.marketye_lead_papel(p_lead_id) <> 'cliente' THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  INSERT INTO public.marketplace_lead_documentos (lead_id, documento_id, tipo) VALUES (p_lead_id, p_documento_id, COALESCE(p_tipo, 'proposta')) RETURNING id INTO v_id;
  INSERT INTO public.marketplace_lead_mensagens (lead_id, autor_tipo, autor_id, texto) VALUES (p_lead_id, 'sistema', auth.uid(), 'Documento arquivado no módulo Documentos e vinculado a esta conversa.');
  RETURN jsonb_build_object('id', v_id);
END $marketye_lead_vincular_documento$;
GRANT EXECUTE ON FUNCTION public.marketye_lead_vincular_documento(uuid, uuid, text) TO authenticated;

-- ---------------------------------------------------------------------
-- 6) Avaliação bidirecional só com transação verificada (RF-010, RN-004/022)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marketye_avaliar(p_ref_tipo text, p_ref_id uuid, p_notas jsonb, p_comentario text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_avaliar$
DECLARE
  v_tenant uuid; v_prof uuid; v_servico uuid; v_concluido timestamptz; v_direcao text; v_janela int; v_notas numeric[]; v_media numeric;
  v_id uuid; v_coment text; k text; v_val numeric; v_meu uuid := public.marketye_meu_id(); v_lead uuid; v_contr uuid;
BEGIN
  v_janela := COALESCE((public.marketye_config('janela_avaliacao_dias')->>'dias')::int, 14);
  IF p_ref_tipo = 'contratacao' THEN
    SELECT tenant_id, profissional_id, servico_id, CASE WHEN status = 'concluida' THEN COALESCE(data_conclusao, updated_at) END
      INTO v_tenant, v_prof, v_servico, v_concluido FROM public.marketplace_contratacoes WHERE id = p_ref_id;
    v_contr := p_ref_id;
  ELSIF p_ref_tipo = 'lead' THEN
    SELECT tenant_id, profissional_id, servico_id, CASE WHEN status = 'ganho' THEN ganho_em END
      INTO v_tenant, v_prof, v_servico, v_concluido FROM public.marketplace_leads WHERE id = p_ref_id;
    v_lead := p_ref_id;
  ELSE
    RAISE EXCEPTION 'Referência inválida';
  END IF;
  IF v_tenant IS NULL THEN RAISE EXCEPTION 'Registro não encontrado'; END IF;
  IF v_concluido IS NULL THEN RAISE EXCEPTION 'Avaliações ficam disponíveis após o atendimento (serviço concluído ou combinado).'; END IF;
  IF v_concluido < now() - make_interval(days => v_janela) THEN RAISE EXCEPTION 'O prazo de % dias para avaliar já passou.', v_janela; END IF;

  IF v_meu IS NOT NULL AND v_meu = v_prof THEN v_direcao := 'especialista_para_cliente';
  ELSIF public.get_user_tenant_id() = v_tenant THEN v_direcao := 'cliente_para_especialista';
  ELSE RAISE EXCEPTION 'Só quem participou do atendimento avalia'; END IF;

  -- Anti-gaming (11.4): no máximo 3 avaliações por par empresa×especialista em 30 dias.
  IF (SELECT count(*) FROM public.marketplace_avaliacoes WHERE tenant_id = v_tenant AND profissional_id = v_prof AND direcao = v_direcao AND created_at >= now() - interval '30 days') >= 3 THEN
    RAISE EXCEPTION 'Limite de avaliações entre esta empresa e este especialista no período.';
  END IF;

  v_notas := '{}';
  FOR k, v_val IN SELECT key, value::text::numeric FROM jsonb_each(COALESCE(p_notas, '{}'::jsonb)) LOOP
    IF v_val < 1 OR v_val > 5 THEN RAISE EXCEPTION 'Notas vão de 1 a 5'; END IF;
    v_notas := v_notas || v_val;
  END LOOP;
  IF array_length(v_notas, 1) IS NULL THEN RAISE EXCEPTION 'Avalie ao menos um critério'; END IF;
  SELECT round(avg(x)::numeric, 2) INTO v_media FROM unnest(v_notas) x;
  v_coment := NULLIF(trim(COALESCE(p_comentario, '')), '');
  IF v_coment IS NOT NULL AND public.marketye_texto_tem_contato(v_coment) THEN v_coment := public.marketye_mascarar_contato(v_coment); END IF;

  INSERT INTO public.marketplace_avaliacoes (contratacao_id, lead_id, profissional_id, servico_id, avaliador_id, tenant_id, direcao, criterios,
    pontualidade, clareza, aderencia_escopo, profissionalismo, nota_geral, comentario)
  VALUES (v_contr, v_lead, v_prof, v_servico, auth.uid(), v_tenant, v_direcao, COALESCE(p_notas, '{}'::jsonb),
    CASE WHEN v_direcao = 'cliente_para_especialista' THEN NULLIF(p_notas->>'pontualidade', '')::int END,
    CASE WHEN v_direcao = 'cliente_para_especialista' THEN NULLIF(p_notas->>'clareza', '')::int END,
    CASE WHEN v_direcao = 'cliente_para_especialista' THEN NULLIF(p_notas->>'aderencia_escopo', '')::int END,
    CASE WHEN v_direcao = 'cliente_para_especialista' THEN NULLIF(p_notas->>'profissionalismo', '')::int END,
    v_media, v_coment)
  RETURNING id INTO v_id;

  INSERT INTO public.marketplace_audit_log (tenant_id, contratacao_id, profissional_id, acao, descricao, dados, usuario_id)
  VALUES (v_tenant, v_contr, v_prof, 'avaliacao_enviada', format('Avaliação %s: %s/5', v_direcao, v_media), json_build_object('avaliacao_id', v_id, 'lead_id', v_lead), auth.uid());
  IF v_direcao = 'cliente_para_especialista' THEN PERFORM public.marketye_recalcular_reputacao(v_prof); END IF;
  RETURN jsonb_build_object('id', v_id, 'nota_geral', v_media, 'direcao', v_direcao);
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Este atendimento já foi avaliado por você.';
END $marketye_avaliar$;
GRANT EXECUTE ON FUNCTION public.marketye_avaliar(text, uuid, jsonb, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.marketye_avaliacao_responder(p_avaliacao_id uuid, p_resposta text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_avaliacao_responder$
BEGIN
  UPDATE public.marketplace_avaliacoes SET resposta = public.marketye_mascarar_contato(left(trim(p_resposta), 1000)), respondido_em = now()
  WHERE id = p_avaliacao_id AND profissional_id = public.marketye_meu_id() AND direcao = 'cliente_para_especialista';
  IF NOT FOUND THEN RAISE EXCEPTION 'Avaliação não encontrada'; END IF;
  RETURN jsonb_build_object('id', p_avaliacao_id);
END $marketye_avaliacao_responder$;
GRANT EXECUTE ON FUNCTION public.marketye_avaliacao_responder(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------
-- 7) Busca com relevância personalizada e busca nunca-vazia (RF-006/008, RN-006/007/008/023)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marketye_buscar_interno(p jsonb)
RETURNS SETOF jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $marketye_buscar_interno$
  WITH cfg AS (
    SELECT COALESCE(public.marketye_config('relevancia_pesos'), '{"fit":0.25,"reputacao":0.20,"saude":0.20,"proximidade":0.15,"exploracao":0.10,"preco":0.05,"destaque":0.05}'::jsonb) AS pesos,
           COALESCE(public.marketye_config('protecao_novato'), '{"dias":30,"ate_avaliacoes":3}'::jsonb) AS nov
  ), f AS (
    SELECT NULLIF(trim(p->>'q'), '') AS q,
           NULLIF(p->>'categoria_id', '')::uuid AS categoria_id,
           NULLIF(p->>'categoria_slug', '') AS categoria_slug,
           NULLIF(p->>'modalidade', '') AS modalidade,
           NULLIF(upper(p->>'uf'), '') AS uf,
           NULLIF(trim(p->>'cidade'), '') AS cidade,
           COALESCE((p->>'somente_remoto')::boolean, false) AS somente_remoto,
           NULLIF(p->>'preco_max', '')::numeric AS preco_max,
           NULLIF(p->>'nota_min', '')::numeric AS nota_min,
           COALESCE((p->>'selo')::boolean, false) AS selo,
           NULLIF(p->>'nivel_min', '') AS nivel_min,
           NULLIF(p->>'lat', '')::double precision AS lat,
           NULLIF(p->>'lng', '')::double precision AS lng,
           COALESCE(NULLIF(p->>'raio_km', '')::double precision, 100) AS raio_km,
           COALESCE(ARRAY(SELECT jsonb_array_elements_text(COALESCE(p->'obrigacoes', '[]'::jsonb))), '{}'::text[]) AS obrigacoes,
           COALESCE(NULLIF(p->>'limite', '')::int, 60) AS limite
  ), cat AS (
    SELECT c.id FROM public.marketplace_categorias c, f
    WHERE (f.categoria_id IS NOT NULL AND (c.id = f.categoria_id OR c.pai_id = f.categoria_id))
       OR (f.categoria_slug IS NOT NULL AND (c.slug = f.categoria_slug OR c.pai_id = (SELECT id FROM public.marketplace_categorias WHERE slug = f.categoria_slug LIMIT 1)))
  ), base AS (
    SELECT s.id AS servico_id, s.nome, s.descricao, s.base_legal, s.modalidade::text AS modalidade, s.preco_referencia, s.tipo_preco, s.preco_minimo, s.preco_maximo,
           s.moeda, s.duracao_estimada_minutos, s.tags, s.obrigacao_legal, s.prazo_tipico, s.midia, s.promocao_percentual, s.promocao_descricao,
           s.categoria_id, c.nome AS categoria_nome, c.slug AS categoria_slug, c.obrigacao_legal AS cat_obrigacao, c.pai_id,
           p.id AS profissional_id, p.nome_completo, p.foto_url, p.bio, p.cidade, p.estado, p.selo_verificado, p.nota_media, p.total_avaliacoes,
           p.total_servicos_executados, p.atende_remoto, p.conselho, p.registro_profissional, p.especialidades, p.modalidades_atendimento,
           p.created_at AS prof_created_at, p.tipo_pessoa, p.video_url,
           COALESCE(r.saude_score, 60) AS saude_score, COALESCE(r.saude_cor, 'cinza') AS saude_cor, COALESCE(r.nivel, 'novo') AS nivel,
           COALESCE(r.abaixo_piso, false) AS abaixo_piso, COALESCE(r.clientes_unicos_total, 0) AS clientes_unicos, r.tempo_resposta_mediano_min, r.taxa_resposta_90d,
           (s.modalidade::text = 'online' OR (s.modalidade::text = 'hibrido' AND p.atende_remoto) OR p.atende_remoto) AS remoto,
           (s.promocao_percentual IS NOT NULL AND CURRENT_DATE BETWEEN COALESCE(s.promocao_inicio, CURRENT_DATE) AND COALESCE(s.promocao_fim, CURRENT_DATE)) AS promocao_ativa,
           EXISTS (SELECT 1 FROM public.marketplace_cupons k WHERE k.profissional_id = p.id AND k.ativo AND (k.validade IS NULL OR k.validade >= CURRENT_DATE) AND (k.limite_uso IS NULL OR k.usos < k.limite_uso)) AS tem_cupom,
           EXISTS (SELECT 1 FROM public.marketplace_destaques d, f WHERE d.profissional_id = p.id AND d.ativo AND CURRENT_DATE BETWEEN d.inicio AND d.fim
                     AND (d.servico_id IS NULL OR d.servico_id = s.id)
                     AND (d.tipo = 'topo' OR (d.tipo = 'categoria' AND (d.categoria_id = s.categoria_id OR d.categoria_id = c.pai_id))
                          OR (d.tipo = 'regiao' AND d.uf IS NOT NULL AND d.uf = COALESCE(f.uf, p.estado)))) AS destaque_ativo,
           CASE WHEN f.lat IS NOT NULL AND f.lng IS NOT NULL AND p.latitude IS NOT NULL AND p.longitude IS NOT NULL
                THEN public.haversine_distance(f.lat, f.lng, p.latitude, p.longitude) END AS distancia_km,
           (COALESCE(r.protegido_ate, p.created_at + make_interval(days => COALESCE((cfg.nov->>'dias')::int, 30))) > now()
              AND p.total_avaliacoes < COALESCE((cfg.nov->>'ate_avaliacoes')::int, 3)) AS novato_protegido
    FROM public.marketplace_servicos s
    JOIN public.marketplace_profissionais p ON p.id = s.profissional_id
    LEFT JOIN public.marketplace_categorias c ON c.id = s.categoria_id
    LEFT JOIN public.marketplace_reputacao r ON r.profissional_id = p.id
    CROSS JOIN f CROSS JOIN cfg
    WHERE s.ativo AND s.status = 'publicado' AND p.status = 'ativo' AND p.excluido_em IS NULL
      AND (f.q IS NULL OR s.nome ILIKE '%' || f.q || '%' OR s.descricao ILIKE '%' || f.q || '%' OR p.nome_completo ILIKE '%' || f.q || '%'
           OR c.nome ILIKE '%' || f.q || '%' OR EXISTS (SELECT 1 FROM unnest(s.tags || c.aliases || COALESCE(p.especialidades, '{}')) t WHERE t ILIKE '%' || f.q || '%'))
      AND ((f.categoria_id IS NULL AND f.categoria_slug IS NULL) OR s.categoria_id IN (SELECT id FROM cat))
      AND (f.modalidade IS NULL OR s.modalidade::text = f.modalidade OR (f.modalidade = 'online' AND s.modalidade::text = 'hibrido'))
      AND (NOT f.somente_remoto OR s.modalidade::text IN ('online', 'hibrido') OR p.atende_remoto)
      AND (f.uf IS NULL OR p.estado = f.uf OR s.modalidade::text = 'online' OR p.atende_remoto)
      AND (f.cidade IS NULL OR p.cidade ILIKE f.cidade OR s.modalidade::text = 'online' OR p.atende_remoto)
      AND (f.lat IS NULL OR f.lng IS NULL OR p.latitude IS NULL OR p.longitude IS NULL OR s.modalidade::text = 'online' OR p.atende_remoto
           OR public.haversine_distance(f.lat, f.lng, p.latitude, p.longitude) <= f.raio_km)
      AND (f.preco_max IS NULL OR s.preco_referencia IS NULL OR s.preco_referencia <= f.preco_max)
      AND (f.nota_min IS NULL OR p.nota_media >= f.nota_min OR p.total_avaliacoes = 0)
      AND (NOT f.selo OR p.selo_verificado)
      AND (f.nivel_min IS NULL OR public.marketye_nivel_indice(COALESCE(r.nivel, 'novo')) >= public.marketye_nivel_indice(f.nivel_min))
  ), pontuado AS (
    SELECT b.*,
      CASE WHEN array_length(f.obrigacoes, 1) IS NOT NULL AND (b.obrigacao_legal && f.obrigacoes OR COALESCE(b.cat_obrigacao, '{}') && f.obrigacoes) THEN 1.0
           WHEN f.categoria_id IS NOT NULL OR f.categoria_slug IS NOT NULL THEN 0.6 ELSE 0.3 END AS f_fit,
      CASE WHEN b.total_avaliacoes = 0 THEN 0.5 ELSE 0.7 * (b.nota_media / 5.0) + 0.3 * (public.marketye_nivel_indice(b.nivel) / 4.0) END AS f_reputacao,
      b.saude_score / 100.0 AS f_saude,
      CASE WHEN b.remoto THEN 0.8
           WHEN b.distancia_km IS NOT NULL THEN GREATEST(0, 1 - b.distancia_km / GREATEST(f.raio_km, 1))
           WHEN f.uf IS NOT NULL AND b.estado = f.uf THEN 0.7 ELSE 0.3 END AS f_proximidade,
      CASE WHEN b.novato_protegido THEN 1.0 ELSE (abs(hashtext(b.servico_id::text || CURRENT_DATE::text)) % 30) / 100.0 END AS f_exploracao,
      CASE WHEN b.promocao_ativa THEN 0.9 WHEN b.preco_referencia IS NULL THEN 0.5 ELSE 0.6 END AS f_preco,
      CASE WHEN b.destaque_ativo AND NOT b.abaixo_piso THEN 1.0 ELSE 0.0 END AS f_destaque
    FROM base b CROSS JOIN f
  ), final AS (
    SELECT p.*, round(((
        (cfg.pesos->>'fit')::numeric * f_fit::numeric + (cfg.pesos->>'reputacao')::numeric * f_reputacao::numeric + (cfg.pesos->>'saude')::numeric * f_saude::numeric
        + (cfg.pesos->>'proximidade')::numeric * f_proximidade::numeric + (cfg.pesos->>'exploracao')::numeric * f_exploracao::numeric
        + (cfg.pesos->>'preco')::numeric * f_preco::numeric + (cfg.pesos->>'destaque')::numeric * f_destaque::numeric
      ) * CASE WHEN p.abaixo_piso THEN 0.25 ELSE 1 END)::numeric, 4) AS score
    FROM pontuado p CROSS JOIN cfg
  )
  SELECT jsonb_build_object(
    'servico_id', servico_id, 'nome', nome, 'descricao', descricao, 'base_legal', base_legal, 'modalidade', modalidade,
    'preco_referencia', preco_referencia, 'tipo_preco', tipo_preco, 'preco_minimo', preco_minimo, 'preco_maximo', preco_maximo, 'moeda', moeda,
    'duracao_estimada_minutos', duracao_estimada_minutos, 'tags', to_jsonb(tags), 'obrigacao_legal', to_jsonb(obrigacao_legal), 'prazo_tipico', prazo_tipico,
    'midia', midia, 'promocao_ativa', promocao_ativa, 'promocao_percentual', promocao_percentual, 'promocao_descricao', promocao_descricao, 'tem_cupom', tem_cupom,
    'categoria_id', categoria_id, 'categoria_nome', categoria_nome, 'categoria_slug', categoria_slug,
    'profissional', jsonb_build_object('id', profissional_id, 'nome_completo', nome_completo, 'foto_url', foto_url, 'bio', bio, 'cidade', cidade, 'estado', estado,
      'selo_verificado', selo_verificado, 'nota_media', nota_media, 'total_avaliacoes', total_avaliacoes, 'total_servicos_executados', total_servicos_executados,
      'atende_remoto', atende_remoto, 'conselho', conselho, 'registro_profissional', registro_profissional, 'especialidades', to_jsonb(especialidades),
      'modalidades_atendimento', to_jsonb(modalidades_atendimento), 'tipo_pessoa', tipo_pessoa, 'video_url', video_url,
      'saude_score', saude_score, 'saude_cor', saude_cor, 'nivel', nivel, 'clientes_unicos', clientes_unicos,
      'tempo_resposta_mediano_min', tempo_resposta_mediano_min, 'taxa_resposta_90d', taxa_resposta_90d, 'novato', novato_protegido),
    'distancia_km', CASE WHEN distancia_km IS NULL THEN NULL ELSE round(distancia_km::numeric, 1) END, 'remoto', remoto,
    'patrocinado', (f_destaque > 0), 'abaixo_piso', abaixo_piso, 'score', score,
    'fatores', jsonb_build_object('fit', round(f_fit::numeric, 2), 'reputacao', round(f_reputacao::numeric, 2), 'saude', round(f_saude::numeric, 2), 'proximidade', round(f_proximidade::numeric, 2),
                                  'exploracao', round(f_exploracao::numeric, 2), 'preco', round(f_preco::numeric, 2), 'destaque', round(f_destaque::numeric, 2)))
  FROM final
  ORDER BY score DESC, nota_media DESC, prof_created_at DESC
  LIMIT (SELECT limite FROM f);
$marketye_buscar_interno$;
REVOKE ALL ON FUNCTION public.marketye_buscar_interno(jsonb) FROM PUBLIC, anon, authenticated;

-- Busca com relaxamento progressivo (RN-023): nunca "0 resultados" seco.
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
    f := f || jsonb_build_object('raio_km', COALESCE(NULLIF(f->>'raio_km', '')::numeric, 100) * 3); v_relax := v_relax || 'raio';
    SELECT COALESCE(jsonb_agg(x), '[]'::jsonb), count(*) INTO v_res, v_n FROM public.marketye_buscar_interno(f) x;
  END IF;
  IF v_n < v_min AND (f->>'cidade') IS NOT NULL THEN
    f := f - 'cidade'; v_relax := v_relax || 'cidade';
    SELECT COALESCE(jsonb_agg(x), '[]'::jsonb), count(*) INTO v_res, v_n FROM public.marketye_buscar_interno(f) x;
  END IF;
  IF v_n < v_min AND (f->>'modalidade') IS NOT NULL THEN
    f := f - 'modalidade'; v_relax := v_relax || 'modalidade';
    SELECT COALESCE(jsonb_agg(x), '[]'::jsonb), count(*) INTO v_res, v_n FROM public.marketye_buscar_interno(f) x;
  END IF;
  IF v_n < v_min AND (f->>'uf') IS NOT NULL THEN
    f := (f - 'uf') - 'lat' - 'lng'; v_relax := v_relax || 'uf';
    SELECT COALESCE(jsonb_agg(x), '[]'::jsonb), count(*) INTO v_res, v_n FROM public.marketye_buscar_interno(f) x;
  END IF;
  IF v_n < v_min AND (f->>'nota_min') IS NOT NULL THEN
    f := f - 'nota_min'; v_relax := v_relax || 'nota_min';
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
-- 8) Demanda latente e vitrine pública (6.3, RN-034, CA-021)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marketye_registrar_busca(p_categoria_id uuid, p_uf text, p_cidade text, p_termos text, p_resultados int,
                                                           p_avisar boolean DEFAULT false, p_email text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_registrar_busca$
DECLARE v_tenant uuid := public.get_user_tenant_id();
BEGIN
  IF v_tenant IS NULL THEN RETURN jsonb_build_object('registrado', false); END IF;
  INSERT INTO public.marketplace_demanda_latente (tenant_id, categoria_id, uf, cidade, termos, resultados, avisar, avisar_email)
  VALUES (v_tenant, p_categoria_id, NULLIF(upper(p_uf), ''), NULLIF(p_cidade, ''), left(p_termos, 200), COALESCE(p_resultados, 0), COALESCE(p_avisar, false), p_email)
  ON CONFLICT (tenant_id, categoria_id, uf, dia) DO UPDATE SET resultados = LEAST(public.marketplace_demanda_latente.resultados, EXCLUDED.resultados),
    avisar = public.marketplace_demanda_latente.avisar OR EXCLUDED.avisar, avisar_email = COALESCE(EXCLUDED.avisar_email, public.marketplace_demanda_latente.avisar_email),
    termos = COALESCE(EXCLUDED.termos, public.marketplace_demanda_latente.termos);
  RETURN jsonb_build_object('registrado', true);
END $marketye_registrar_busca$;
GRANT EXECUTE ON FUNCTION public.marketye_registrar_busca(uuid, text, text, text, int, boolean, text) TO authenticated;

-- Agregado anonimizado com célula mínima: nada abaixo do piso aparece.
CREATE OR REPLACE FUNCTION public.marketye_vagas_demanda(p_dias int DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $marketye_vagas_demanda$
  WITH cfg AS (SELECT COALESCE((public.marketye_config('demanda_latente')->>'piso_celula')::int, 5) AS piso,
                      COALESCE(p_dias, (public.marketye_config('demanda_latente')->>'janela_dias')::int, 30) AS dias)
  SELECT COALESCE(jsonb_agg(jsonb_build_object('categoria', c.nome, 'categoria_slug', c.slug, 'uf', x.uf, 'empresas', x.empresas) ORDER BY x.empresas DESC), '[]'::jsonb)
  FROM (
    SELECT d.categoria_id, d.uf, count(DISTINCT d.tenant_id) AS empresas
    FROM public.marketplace_demanda_latente d, cfg
    WHERE d.dia >= CURRENT_DATE - cfg.dias AND d.resultados < 3
    GROUP BY d.categoria_id, d.uf
  ) x JOIN public.marketplace_categorias c ON c.id = x.categoria_id, cfg
  WHERE x.empresas >= cfg.piso;
$marketye_vagas_demanda$;
GRANT EXECUTE ON FUNCTION public.marketye_vagas_demanda(int) TO anon, authenticated;

-- Números da página de captação: faixas, nunca contagens exatas de clientes.
CREATE OR REPLACE FUNCTION public.marketye_vitrine_publica()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $marketye_vitrine_publica$
  SELECT jsonb_build_object(
    'empresas_faixa', (SELECT CASE WHEN n >= 100 THEN (floor(n / 100.0) * 100)::int::text || '+' ELSE 'dezenas de' END FROM (SELECT count(*) AS n FROM public.tenants WHERE ativo) t),
    'especialistas_ativos', (SELECT count(*) FROM public.marketplace_profissionais WHERE status = 'ativo' AND excluido_em IS NULL),
    'anuncios_publicados', (SELECT count(*) FROM public.marketplace_servicos WHERE status = 'publicado' AND ativo),
    'categorias', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.nome, 'slug', c.slug, 'icone', c.icone, 'obrigacao_legal', to_jsonb(c.obrigacao_legal),
                                    'filhas', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', s.id, 'nome', s.nome, 'slug', s.slug, 'obrigacao_legal', to_jsonb(s.obrigacao_legal), 'exige_registro', s.exige_registro) ORDER BY s.ordem), '[]'::jsonb)
                                               FROM public.marketplace_categorias s WHERE s.pai_id = c.id AND s.ativo)) ORDER BY c.ordem), '[]'::jsonb)
                   FROM public.marketplace_categorias c WHERE c.pai_id IS NULL AND c.ativo),
    'vagas_demanda', public.marketye_vagas_demanda(NULL),
    'termos_versoes', public.marketye_config('termos_versoes'));
$marketye_vitrine_publica$;
GRANT EXECUTE ON FUNCTION public.marketye_vitrine_publica() TO anon, authenticated;

-- ---------------------------------------------------------------------
-- 9) Moderação, contestação e transparência (RF-018/028, RN-013/032/033)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marketye_moderacao_fila(p_status text DEFAULT 'pendente')
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $marketye_moderacao_fila$
  SELECT CASE WHEN NOT public.is_superadmin(auth.uid()) THEN NULL ELSE COALESCE((
    SELECT jsonb_agg((to_jsonb(p) - 'user_id') || jsonb_build_object(
      'documentos', (SELECT COALESCE(jsonb_agg(to_jsonb(d) ORDER BY d.created_at), '[]'::jsonb) FROM public.marketplace_profissional_documentos d WHERE d.profissional_id = p.id),
      'consentimentos', (SELECT COALESCE(jsonb_agg(jsonb_build_object('tipo', c.tipo, 'versao', c.versao, 'aceito_em', c.aceito_em)), '[]'::jsonb) FROM public.marketplace_consentimentos c WHERE c.profissional_id = p.id),
      'anuncios', (SELECT count(*) FROM public.marketplace_servicos s WHERE s.profissional_id = p.id AND s.status <> 'removido'),
      'denuncias_abertas', (SELECT count(*) FROM public.marketplace_denuncias x WHERE x.profissional_id = p.id AND x.status IN ('aberta', 'em_analise')),
      'reputacao', (SELECT to_jsonb(r) FROM public.marketplace_reputacao r WHERE r.profissional_id = p.id)
    ) ORDER BY p.created_at)
    FROM public.marketplace_profissionais p WHERE p.status::text = COALESCE(p_status, 'pendente') AND p.excluido_em IS NULL), '[]'::jsonb) END;
$marketye_moderacao_fila$;
GRANT EXECUTE ON FUNCTION public.marketye_moderacao_fila(text) TO authenticated;

-- Aprovar/rejeitar cadastro. O selo comunica VERIFICAÇÃO DE DADOS, não garantia de qualidade (RN-026).
CREATE OR REPLACE FUNCTION public.marketye_moderar_especialista(p_id uuid, p_resultado text, p_motivo text DEFAULT NULL, p_selo boolean DEFAULT true)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_moderar_especialista$
DECLARE v_nome text;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  IF p_resultado NOT IN ('aprovado', 'rejeitado') THEN RAISE EXCEPTION 'Resultado inválido'; END IF;
  IF p_resultado = 'rejeitado' AND length(trim(COALESCE(p_motivo, ''))) < 5 THEN RAISE EXCEPTION 'Informe o motivo (o especialista pode contestar)'; END IF;
  UPDATE public.marketplace_profissionais SET
    status = CASE WHEN p_resultado = 'aprovado' THEN 'ativo'::public.marketplace_profissional_status ELSE 'bloqueado'::public.marketplace_profissional_status END,
    selo_verificado = (p_resultado = 'aprovado' AND COALESCE(p_selo, true)),
    moderacao_resultado = p_resultado, moderacao_motivo = p_motivo, moderado_por = auth.uid(), moderado_em = now()
  WHERE id = p_id RETURNING nome_completo INTO v_nome;
  IF v_nome IS NULL THEN RAISE EXCEPTION 'Especialista não encontrado'; END IF;
  INSERT INTO public.marketplace_reputacao (profissional_id) VALUES (p_id) ON CONFLICT (profissional_id) DO NOTHING;
  INSERT INTO public.marketplace_audit_log (tenant_id, profissional_id, acao, descricao, dados, usuario_id)
  VALUES ((SELECT tenant_id FROM public.marketplace_profissionais WHERE id = p_id), p_id, 'especialista_' || p_resultado, format('Especialista %s %s', v_nome, p_resultado), json_build_object('motivo', p_motivo, 'selo', p_selo), auth.uid());
  PERFORM public.marketye_recalcular_reputacao(p_id);
  RETURN jsonb_build_object('id', p_id, 'resultado', p_resultado);
END $marketye_moderar_especialista$;
GRANT EXECUTE ON FUNCTION public.marketye_moderar_especialista(uuid, text, text, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.marketye_especialista_situacao(p_id uuid, p_situacao text, p_motivo text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_especialista_situacao$
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  IF p_situacao NOT IN ('ativo', 'suspenso', 'pendente') THEN RAISE EXCEPTION 'Situação inválida'; END IF;
  UPDATE public.marketplace_profissionais SET status = p_situacao::public.marketplace_profissional_status, moderacao_motivo = COALESCE(p_motivo, moderacao_motivo) WHERE id = p_id;
  INSERT INTO public.marketplace_audit_log (tenant_id, profissional_id, acao, descricao, dados, usuario_id)
  VALUES ((SELECT tenant_id FROM public.marketplace_profissionais WHERE id = p_id), p_id, 'especialista_' || p_situacao, COALESCE(p_motivo, 'Situação alterada pela moderação'), json_build_object('situacao', p_situacao), auth.uid());
  RETURN jsonb_build_object('id', p_id, 'status', p_situacao);
END $marketye_especialista_situacao$;
GRANT EXECUTE ON FUNCTION public.marketye_especialista_situacao(uuid, text, text) TO authenticated;

-- Decisão sobre denúncia: procedente vira OCORRÊNCIA (reflexo na visibilidade), nunca "punição".
CREATE OR REPLACE FUNCTION public.marketye_denuncia_decidir(p_id uuid, p_status text, p_acao text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_denuncia_decidir$
DECLARE d record;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  IF p_status NOT IN ('em_analise', 'procedente', 'improcedente', 'resolvida') THEN RAISE EXCEPTION 'Situação inválida'; END IF;
  UPDATE public.marketplace_denuncias SET status = p_status, acao_tomada = COALESCE(p_acao, acao_tomada), analisado_por = auth.uid(), analisado_em = now()
  WHERE id = p_id RETURNING * INTO d;
  IF d.id IS NULL THEN RAISE EXCEPTION 'Denúncia não encontrada'; END IF;
  IF p_status = 'procedente' THEN
    INSERT INTO public.marketplace_ocorrencias (profissional_id, tipo, descricao, origem_tipo, origem_id, registrado_por)
    VALUES (d.profissional_id, d.tipo, COALESCE(p_acao, d.descricao), 'denuncia', d.id, auth.uid());
    PERFORM public.marketye_recalcular_reputacao(d.profissional_id);
  END IF;
  RETURN jsonb_build_object('id', p_id, 'status', p_status);
END $marketye_denuncia_decidir$;
GRANT EXECUTE ON FUNCTION public.marketye_denuncia_decidir(uuid, text, text) TO authenticated;

-- Canal único de contestação (devido processo + LGPD art. 20).
CREATE OR REPLACE FUNCTION public.marketye_contestar(p_tipo text, p_referencia_id uuid, p_motivo text, p_evidencias jsonb DEFAULT '[]'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_contestar$
DECLARE v_prof uuid := public.marketye_meu_id(); v_id uuid;
BEGIN
  IF v_prof IS NULL THEN RAISE EXCEPTION 'Sem cadastro de especialista'; END IF;
  IF length(trim(COALESCE(p_motivo, ''))) < 10 THEN RAISE EXCEPTION 'Explique o motivo da contestação (mínimo 10 letras)'; END IF;
  IF EXISTS (SELECT 1 FROM public.marketplace_contestacoes WHERE profissional_id = v_prof AND decisao_tipo = p_tipo AND referencia_id IS NOT DISTINCT FROM p_referencia_id AND status IN ('aberta', 'em_analise')) THEN
    RAISE EXCEPTION 'Já existe uma contestação aberta sobre esta decisão';
  END IF;
  INSERT INTO public.marketplace_contestacoes (profissional_id, decisao_tipo, referencia_id, motivo, evidencias, trilha)
  VALUES (v_prof, p_tipo, p_referencia_id, trim(p_motivo), COALESCE(p_evidencias, '[]'::jsonb),
          jsonb_build_array(jsonb_build_object('evento', 'aberta', 'em', now(), 'por', 'especialista')))
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id, 'status', 'aberta');
END $marketye_contestar$;
GRANT EXECUTE ON FUNCTION public.marketye_contestar(text, uuid, text, jsonb) TO authenticated;

-- A decisão é sempre de uma pessoa (human-in-the-loop): a IA não fecha contestação.
CREATE OR REPLACE FUNCTION public.marketye_contestacao_decidir(p_id uuid, p_resultado text, p_resposta text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_contestacao_decidir$
DECLARE c record;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  IF p_resultado NOT IN ('em_analise', 'deferida', 'indeferida') THEN RAISE EXCEPTION 'Resultado inválido'; END IF;
  IF p_resultado <> 'em_analise' AND length(trim(COALESCE(p_resposta, ''))) < 10 THEN RAISE EXCEPTION 'Escreva a resposta ao especialista (trilha de evidência)'; END IF;
  UPDATE public.marketplace_contestacoes SET status = p_resultado, resposta = COALESCE(p_resposta, resposta),
    analisado_por = CASE WHEN p_resultado <> 'em_analise' THEN auth.uid() END, analisado_em = CASE WHEN p_resultado <> 'em_analise' THEN now() END,
    trilha = trilha || jsonb_build_object('evento', p_resultado, 'em', now(), 'por', 'moderador', 'resposta', p_resposta)
  WHERE id = p_id RETURNING * INTO c;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Contestação não encontrada'; END IF;
  IF p_resultado = 'deferida' THEN
    IF c.decisao_tipo = 'rejeicao_cadastro' THEN
      UPDATE public.marketplace_profissionais SET status = 'pendente', moderacao_resultado = NULL, moderacao_motivo = NULL WHERE id = c.profissional_id;
    ELSIF c.decisao_tipo = 'suspensao' THEN
      UPDATE public.marketplace_profissionais SET status = 'ativo' WHERE id = c.profissional_id AND status = 'suspenso';
    ELSIF c.decisao_tipo = 'remocao_anuncio' AND c.referencia_id IS NOT NULL THEN
      UPDATE public.marketplace_servicos SET status = 'pausado', ativo = true WHERE id = c.referencia_id AND profissional_id = c.profissional_id;
    ELSIF c.decisao_tipo = 'reflexo_visibilidade' AND c.referencia_id IS NOT NULL THEN
      UPDATE public.marketplace_ocorrencias SET reflexo_visibilidade = false WHERE id = c.referencia_id AND profissional_id = c.profissional_id;
      PERFORM public.marketye_recalcular_reputacao(c.profissional_id);
    ELSIF c.decisao_tipo = 'avaliacao' AND c.referencia_id IS NOT NULL THEN
      UPDATE public.marketplace_avaliacoes SET moderada = true, moderacao_motivo = p_resposta WHERE id = c.referencia_id AND profissional_id = c.profissional_id;
      PERFORM public.marketye_recalcular_reputacao(c.profissional_id);
    END IF;
  END IF;
  INSERT INTO public.marketplace_audit_log (tenant_id, profissional_id, acao, descricao, dados, usuario_id)
  VALUES ((SELECT tenant_id FROM public.marketplace_profissionais WHERE id = c.profissional_id), c.profissional_id, 'contestacao_' || p_resultado, left(p_resposta, 500), json_build_object('contestacao_id', c.id, 'tipo', c.decisao_tipo), auth.uid());
  RETURN jsonb_build_object('id', p_id, 'status', p_resultado);
END $marketye_contestacao_decidir$;
GRANT EXECUTE ON FUNCTION public.marketye_contestacao_decidir(uuid, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.marketye_contestacoes_fila()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $marketye_contestacoes_fila$
  SELECT CASE WHEN NOT public.is_superadmin(auth.uid()) THEN NULL ELSE COALESCE((
    SELECT jsonb_agg(to_jsonb(c) || jsonb_build_object('especialista', p.nome_completo, 'especialista_status', p.status) ORDER BY (c.status IN ('aberta', 'em_analise')) DESC, c.created_at)
    FROM public.marketplace_contestacoes c JOIN public.marketplace_profissionais p ON p.id = c.profissional_id), '[]'::jsonb) END;
$marketye_contestacoes_fila$;
GRANT EXECUTE ON FUNCTION public.marketye_contestacoes_fila() TO authenticated;

-- Destaque pago (camada rotulada). Só acima do piso e dentro do teto por categoria.
CREATE OR REPLACE FUNCTION public.marketye_destaque_criar(p_profissional_id uuid, p_servico_id uuid, p_tipo text, p_categoria_id uuid, p_uf text,
                                                          p_inicio date, p_fim date, p_valor numeric DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_destaque_criar$
DECLARE v_cfg jsonb := COALESCE(public.marketye_config('destaque'), '{"teto_slots_por_categoria":2,"exige_acima_do_piso":true}'::jsonb); v_id uuid; v_abaixo boolean; v_slots int;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  IF p_tipo NOT IN ('categoria', 'regiao', 'topo') THEN RAISE EXCEPTION 'Tipo de destaque inválido'; END IF;
  IF p_fim < COALESCE(p_inicio, CURRENT_DATE) THEN RAISE EXCEPTION 'Período inválido'; END IF;
  SELECT COALESCE(abaixo_piso, false) INTO v_abaixo FROM public.marketplace_reputacao WHERE profissional_id = p_profissional_id;
  IF COALESCE((v_cfg->>'exige_acima_do_piso')::boolean, true) AND COALESCE(v_abaixo, false) THEN
    RAISE EXCEPTION 'Melhore sua nota para ativar destaques.';
  END IF;
  IF p_tipo = 'categoria' THEN
    SELECT count(*) INTO v_slots FROM public.marketplace_destaques WHERE tipo = 'categoria' AND categoria_id = p_categoria_id AND ativo AND fim >= COALESCE(p_inicio, CURRENT_DATE) AND inicio <= p_fim;
    IF v_slots >= COALESCE((v_cfg->>'teto_slots_por_categoria')::int, 2) THEN RAISE EXCEPTION 'Teto de destaques desta categoria atingido no período.'; END IF;
  END IF;
  INSERT INTO public.marketplace_destaques (profissional_id, servico_id, tipo, categoria_id, uf, inicio, fim, valor, criado_por)
  VALUES (p_profissional_id, p_servico_id, p_tipo, p_categoria_id, NULLIF(upper(p_uf), ''), COALESCE(p_inicio, CURRENT_DATE), p_fim, p_valor, auth.uid()) RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id);
END $marketye_destaque_criar$;
GRANT EXECUTE ON FUNCTION public.marketye_destaque_criar(uuid, uuid, text, uuid, text, date, date, numeric) TO authenticated;

-- Relatório anual de transparência (RN-032).
CREATE OR REPLACE FUNCTION public.marketye_transparencia(p_ano int DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $marketye_transparencia$
  WITH a AS (SELECT COALESCE(p_ano, EXTRACT(YEAR FROM now())::int) AS ano)
  SELECT CASE WHEN NOT public.is_superadmin(auth.uid()) THEN NULL ELSE jsonb_build_object(
    'ano', a.ano,
    'denuncias_recebidas', (SELECT count(*) FROM public.marketplace_denuncias d WHERE EXTRACT(YEAR FROM d.created_at) = a.ano),
    'denuncias_procedentes', (SELECT count(*) FROM public.marketplace_denuncias d WHERE EXTRACT(YEAR FROM d.created_at) = a.ano AND d.status = 'procedente'),
    'cadastros_rejeitados', (SELECT count(*) FROM public.marketplace_profissionais p WHERE EXTRACT(YEAR FROM p.moderado_em) = a.ano AND p.moderacao_resultado = 'rejeitado'),
    'cadastros_aprovados', (SELECT count(*) FROM public.marketplace_profissionais p WHERE EXTRACT(YEAR FROM p.moderado_em) = a.ano AND p.moderacao_resultado = 'aprovado'),
    'anuncios_publicados', (SELECT count(*) FROM public.marketplace_servicos s WHERE EXTRACT(YEAR FROM s.publicado_em) = a.ano),
    'impulsionamentos', (SELECT count(*) FROM public.marketplace_destaques d WHERE EXTRACT(YEAR FROM d.created_at) = a.ano),
    'contestacoes', (SELECT jsonb_build_object('abertas', count(*) FILTER (WHERE status IN ('aberta','em_analise')), 'deferidas', count(*) FILTER (WHERE status = 'deferida'), 'indeferidas', count(*) FILTER (WHERE status = 'indeferida'))
                     FROM public.marketplace_contestacoes c WHERE EXTRACT(YEAR FROM c.created_at) = a.ano),
    'exclusoes_lgpd', (SELECT count(*) FROM public.marketplace_profissionais p WHERE EXTRACT(YEAR FROM p.excluido_em) = a.ano)
  ) END FROM a;
$marketye_transparencia$;
GRANT EXECUTE ON FUNCTION public.marketye_transparencia(int) TO authenticated;

-- ---------------------------------------------------------------------
-- 10) LGPD do não-usuário (RF-021, RN-019, CA-014)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marketye_exportar_meus_dados()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $marketye_exportar_meus_dados$
  SELECT jsonb_build_object(
    'perfil', (SELECT to_jsonb(p) - 'user_id' FROM public.marketplace_profissionais p WHERE p.id = public.marketye_meu_id()),
    'anuncios', (SELECT COALESCE(jsonb_agg(to_jsonb(s)), '[]'::jsonb) FROM public.marketplace_servicos s WHERE s.profissional_id = public.marketye_meu_id()),
    'leads', (SELECT COALESCE(jsonb_agg(to_jsonb(l) - 'criado_por'), '[]'::jsonb) FROM public.marketplace_leads l WHERE l.profissional_id = public.marketye_meu_id()),
    'avaliacoes', (SELECT COALESCE(jsonb_agg(to_jsonb(a) - 'avaliador_id'), '[]'::jsonb) FROM public.marketplace_avaliacoes a WHERE a.profissional_id = public.marketye_meu_id()),
    'consentimentos', (SELECT COALESCE(jsonb_agg(to_jsonb(c)), '[]'::jsonb) FROM public.marketplace_consentimentos c WHERE c.profissional_id = public.marketye_meu_id()),
    'contestacoes', (SELECT COALESCE(jsonb_agg(to_jsonb(c)), '[]'::jsonb) FROM public.marketplace_contestacoes c WHERE c.profissional_id = public.marketye_meu_id()),
    'autonomia', (SELECT COALESCE(jsonb_agg(to_jsonb(e)), '[]'::jsonb) FROM public.marketplace_autonomia_eventos e WHERE e.profissional_id = public.marketye_meu_id()),
    'exportado_em', now());
$marketye_exportar_meus_dados$;
GRANT EXECUTE ON FUNCTION public.marketye_exportar_meus_dados() TO authenticated;

-- Sai da vitrine e anonimiza o perfil; leads, avaliações e contratações
-- ficam pelo prazo legal (sem o nome). Os prazos por tipo aguardam advogado.
CREATE OR REPLACE FUNCTION public.marketye_excluir_meu_perfil(p_confirmacao text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_excluir_meu_perfil$
DECLARE v_id uuid := public.marketye_meu_id();
BEGIN
  IF v_id IS NULL THEN RAISE EXCEPTION 'Sem cadastro de especialista'; END IF;
  IF COALESCE(p_confirmacao, '') <> 'EXCLUIR' THEN RAISE EXCEPTION 'Digite EXCLUIR para confirmar'; END IF;
  UPDATE public.marketplace_servicos SET status = 'removido', ativo = false WHERE profissional_id = v_id;
  UPDATE public.marketplace_cupons SET ativo = false WHERE profissional_id = v_id;
  UPDATE public.marketplace_destaques SET ativo = false WHERE profissional_id = v_id;
  INSERT INTO public.marketplace_consentimentos (profissional_id, tipo, versao, origem) VALUES (v_id, 'revogacao_exclusao', 'lgpd', 'portal');
  UPDATE public.marketplace_profissionais SET
    status = 'bloqueado', excluido_em = now(), nome_completo = 'Especialista removido', email = 'removido+' || v_id::text || '@anonimizado.invalid',
    telefone = NULL, cpf_cnpj = NULL, foto_url = NULL, bio = NULL, formacao_academica = NULL, registro_profissional = NULL, certificacoes = NULL,
    especialidades = NULL, areas_atuacao = NULL, latitude = NULL, longitude = NULL, site_url = NULL, video_url = NULL, disponibilidade = '{}'::jsonb,
    politicas = NULL, link_afiliado = NULL, user_id = NULL
  WHERE id = v_id;
  INSERT INTO public.marketplace_audit_log (tenant_id, profissional_id, acao, descricao, usuario_id)
  VALUES ((SELECT tenant_id FROM public.marketplace_profissionais WHERE id = v_id), v_id, 'exclusao_lgpd', 'Perfil removido a pedido do titular; transações retidas pelo prazo legal', auth.uid());
  RETURN jsonb_build_object('id', v_id, 'excluido', true);
END $marketye_excluir_meu_perfil$;
GRANT EXECUTE ON FUNCTION public.marketye_excluir_meu_perfil(text) TO authenticated;

-- ---------------------------------------------------------------------
-- 11) Painel de liquidez (RF-019, 2.4, 23)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marketye_painel_liquidez()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $marketye_painel_liquidez$
  SELECT CASE WHEN NOT public.is_superadmin(auth.uid()) THEN NULL ELSE jsonb_build_object(
    'especialistas', jsonb_build_object(
      'ativos', (SELECT count(*) FROM public.marketplace_profissionais WHERE status = 'ativo' AND excluido_em IS NULL),
      'pendentes', (SELECT count(*) FROM public.marketplace_profissionais WHERE status = 'pendente' AND excluido_em IS NULL),
      'novos_30d', (SELECT count(*) FROM public.marketplace_profissionais WHERE created_at >= now() - interval '30 days'),
      'excluidos_30d', (SELECT count(*) FROM public.marketplace_profissionais WHERE excluido_em >= now() - interval '30 days')),
    'anuncios_publicados', (SELECT count(*) FROM public.marketplace_servicos WHERE status = 'publicado' AND ativo),
    'densidade', (SELECT COALESCE(jsonb_agg(jsonb_build_object('categoria', categoria, 'uf', uf, 'especialistas', n) ORDER BY n DESC), '[]'::jsonb) FROM (
        SELECT COALESCE(cr.nome, c.nome) AS categoria, p.estado AS uf, count(DISTINCT p.id) AS n
        FROM public.marketplace_servicos s JOIN public.marketplace_profissionais p ON p.id = s.profissional_id
        LEFT JOIN public.marketplace_categorias c ON c.id = s.categoria_id LEFT JOIN public.marketplace_categorias cr ON cr.id = c.pai_id
        WHERE s.status = 'publicado' AND s.ativo AND p.status = 'ativo' GROUP BY 1, 2) d),
    'cobertura', (SELECT jsonb_build_object('celulas_total', count(*), 'celulas_densas', count(*) FILTER (WHERE n >= 3)) FROM (
        SELECT count(DISTINCT p.id) AS n FROM public.marketplace_servicos s JOIN public.marketplace_profissionais p ON p.id = s.profissional_id
        WHERE s.status = 'publicado' AND s.ativo AND p.status = 'ativo' GROUP BY s.categoria_id, p.estado) x),
    'leads', jsonb_build_object(
      'abertos_30d', (SELECT count(*) FROM public.marketplace_leads WHERE created_at >= now() - interval '30 days'),
      'respondidos_30d', (SELECT count(*) FROM public.marketplace_leads WHERE created_at >= now() - interval '30 days' AND primeira_resposta_em IS NOT NULL),
      'ganhos_30d', (SELECT count(*) FROM public.marketplace_leads WHERE created_at >= now() - interval '30 days' AND status = 'ganho'),
      'tempo_resposta_mediano_min', (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (primeira_resposta_em - created_at)) / 60)
                                     FROM public.marketplace_leads WHERE primeira_resposta_em IS NOT NULL AND created_at >= now() - interval '90 days')),
    'demanda_latente', (SELECT COALESCE(jsonb_agg(jsonb_build_object('categoria', c.nome, 'uf', d.uf, 'empresas', d.n, 'avisar', d.avisar) ORDER BY d.n DESC), '[]'::jsonb) FROM (
        SELECT categoria_id, uf, count(DISTINCT tenant_id) AS n, bool_or(avisar) AS avisar FROM public.marketplace_demanda_latente
        WHERE dia >= CURRENT_DATE - 30 AND resultados < 3 GROUP BY categoria_id, uf) d JOIN public.marketplace_categorias c ON c.id = d.categoria_id),
    'tempo_ate_primeira_venda_dias', (SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (x.primeira - p.created_at)) / 86400)::numeric, 1)
        FROM public.marketplace_profissionais p JOIN (SELECT profissional_id, min(ganho_em) AS primeira FROM public.marketplace_leads WHERE status = 'ganho' GROUP BY 1) x ON x.profissional_id = p.id),
    'contestacoes_abertas', (SELECT count(*) FROM public.marketplace_contestacoes WHERE status IN ('aberta', 'em_analise')),
    'gerado_em', now()) END;
$marketye_painel_liquidez$;
GRANT EXECUTE ON FUNCTION public.marketye_painel_liquidez() TO authenticated;

-- Reputação inicial para quem já estava ativo antes desta onda.
INSERT INTO public.marketplace_reputacao (profissional_id)
SELECT id FROM public.marketplace_profissionais p WHERE NOT EXISTS (SELECT 1 FROM public.marketplace_reputacao r WHERE r.profissional_id = p.id)
ON CONFLICT (profissional_id) DO NOTHING;

-- ===================================================================
-- ORIGEM: 20260911224000_marketye_areas_abertas.sql
-- ===================================================================
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

-- ===================================================================
-- ORIGEM: 20260911230000_marketye_portal_robusto.sql
-- ===================================================================
-- =====================================================================
-- MARKETYE · PORTAL ABRE LOGO DEPOIS DO CADASTRO MÍNIMO (regressão 11/09/2026)
--
-- O que aconteceu: um prestador se cadastrou pela página pública (nome,
-- documento, uma frase sobre o que faz, e-mail) e o portal ficou preso no
-- círculo de carregamento. Causa: o cadastro guarda "especialidades" vazias
-- como nulo; ao montar o portal, a conta de completude do perfil tentava
-- medir esse nulo como lista ("cannot get array length of a scalar") e a
-- função inteira falhava. Como a tela só tratava "carregando", ninguém via
-- o erro.
--
-- Correção: a completude só mede a lista quando ela é lista. A tela passou
-- a mostrar "Tentar de novo" em vez do círculo eterno (mudança de front).
-- Caso de QA MKY-014 documenta e cobre a regressão.
--
-- Idempotente: CREATE OR REPLACE e ON CONFLICT.
-- =====================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.marketye_meu_portal()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_meu_portal$
DECLARE v_id uuid := public.marketye_meu_id(); v_perfil jsonb; v_rep jsonb; v_versoes jsonb; v_niveis jsonb; v_nivel text; v_ordem text[]; v_prox text; v_i int;
BEGIN
  IF v_id IS NULL THEN RETURN NULL; END IF;
  SELECT to_jsonb(p) - 'user_id' INTO v_perfil FROM public.marketplace_profissionais p WHERE p.id = v_id;
  SELECT to_jsonb(r) INTO v_rep FROM public.marketplace_reputacao r WHERE r.profissional_id = v_id;
  v_versoes := COALESCE(public.marketye_config('termos_versoes'), '{}'::jsonb);
  v_niveis := COALESCE(public.marketye_config('niveis'), '{}'::jsonb);
  v_nivel := COALESCE(v_rep->>'nivel', 'novo');
  v_ordem := ARRAY(SELECT jsonb_array_elements_text(COALESCE(v_niveis->'ordem', '["novo","bronze","prata","ouro","top"]'::jsonb)));
  v_prox := NULL;
  FOR v_i IN 1..COALESCE(array_length(v_ordem, 1), 1) LOOP
    IF v_ordem[v_i] = v_nivel AND v_i < array_length(v_ordem, 1) THEN v_prox := v_ordem[v_i + 1]; END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'perfil', v_perfil,
    'reputacao', v_rep,
    'nivel', jsonb_build_object('atual', v_nivel, 'proximo', v_prox, 'requisitos_proximo', v_niveis->'requisitos'->v_prox,
                                'aviso_em', v_rep->>'nivel_aviso_em', 'aviso_motivo', v_rep->>'nivel_aviso_motivo', 'ordem', to_jsonb(v_ordem)),
    'completude', (SELECT round(100.0 * (
        (v_perfil->>'foto_url' IS NOT NULL)::int + (COALESCE(v_perfil->>'bio', '') <> '')::int + (v_perfil->>'registro_profissional' IS NOT NULL)::int
        + ((CASE WHEN jsonb_typeof(v_perfil->'especialidades') = 'array' THEN jsonb_array_length(v_perfil->'especialidades') ELSE 0 END) > 0)::int + (v_perfil->>'cidade' IS NOT NULL)::int
        + (v_perfil->>'video_url' IS NOT NULL)::int + (v_perfil->>'telefone' IS NOT NULL)::int
        + (EXISTS (SELECT 1 FROM public.marketplace_servicos s WHERE s.profissional_id = v_id AND s.status = 'publicado'))::int) / 8)),
    'anuncios', COALESCE((SELECT jsonb_agg(to_jsonb(s) || jsonb_build_object('categoria_nome', c.nome, 'categoria_slug', c.slug, 'exige_registro', c.exige_registro) ORDER BY s.created_at DESC)
                          FROM public.marketplace_servicos s LEFT JOIN public.marketplace_categorias c ON c.id = s.categoria_id WHERE s.profissional_id = v_id AND s.status <> 'removido'), '[]'::jsonb),
    'leads', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                'id', l.id, 'status', l.status, 'created_at', l.created_at, 'contato_liberado', l.contato_liberado, 'primeira_resposta_em', l.primeira_resposta_em,
                'ultima_mensagem_em', l.ultima_mensagem_em, 'servico_nome', s.nome, 'empresa_nome', t.nome, 'origem_modulo', l.origem_modulo,
                'obrigacao_legal', l.obrigacao_legal, 'cupom_codigo', l.cupom_codigo, 'ganho_em', l.ganho_em,
                'reputacao_empresa', (SELECT jsonb_build_object('media', round(avg(a.nota_geral)::numeric, 1), 'total', count(*))
                                      FROM public.marketplace_avaliacoes a WHERE a.tenant_id = l.tenant_id AND a.direcao = 'especialista_para_cliente'),
                'ultima_mensagem', (SELECT m.texto FROM public.marketplace_lead_mensagens m WHERE m.lead_id = l.id ORDER BY m.created_at DESC LIMIT 1),
                'avaliei', EXISTS (SELECT 1 FROM public.marketplace_avaliacoes a WHERE a.lead_id = l.id AND a.direcao = 'especialista_para_cliente')
              ) ORDER BY COALESCE(l.ultima_mensagem_em, l.created_at) DESC)
              FROM public.marketplace_leads l LEFT JOIN public.marketplace_servicos s ON s.id = l.servico_id LEFT JOIN public.tenants t ON t.id = l.tenant_id
              WHERE l.profissional_id = v_id), '[]'::jsonb),
    'metricas', jsonb_build_object(
      'leads_30d', (SELECT count(*) FROM public.marketplace_leads WHERE profissional_id = v_id AND created_at >= now() - interval '30 days'),
      'leads_ganhos_30d', (SELECT count(*) FROM public.marketplace_leads WHERE profissional_id = v_id AND status = 'ganho' AND ganho_em >= now() - interval '30 days'),
      'sem_resposta', (SELECT count(*) FROM public.marketplace_leads WHERE profissional_id = v_id AND status = 'novo'),
      'avaliacoes', (SELECT count(*) FROM public.marketplace_avaliacoes WHERE profissional_id = v_id AND direcao = 'cliente_para_especialista')),
    'avaliacoes', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', a.id, 'nota_geral', a.nota_geral, 'comentario', a.comentario, 'created_at', a.created_at,
                              'resposta', a.resposta, 'criterios', a.criterios, 'pontualidade', a.pontualidade, 'clareza', a.clareza,
                              'aderencia_escopo', a.aderencia_escopo, 'profissionalismo', a.profissionalismo) ORDER BY a.created_at DESC)
                            FROM public.marketplace_avaliacoes a WHERE a.profissional_id = v_id AND a.direcao = 'cliente_para_especialista' AND NOT a.moderada), '[]'::jsonb),
    'consentimentos', COALESCE((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.aceito_em DESC) FROM public.marketplace_consentimentos c WHERE c.profissional_id = v_id), '[]'::jsonb),
    'termos_pendentes', COALESCE((SELECT jsonb_agg(jsonb_build_object('tipo', t.tipo, 'versao', v_versoes->>t.tipo))
                                  FROM (VALUES ('termos_especialista'), ('privacidade_nao_usuario'), ('codigo_etica')) AS t(tipo)
                                  WHERE v_versoes->>t.tipo IS NOT NULL AND NOT EXISTS (
                                    SELECT 1 FROM public.marketplace_consentimentos c WHERE c.profissional_id = v_id AND c.tipo = t.tipo AND c.versao = v_versoes->>t.tipo)), '[]'::jsonb),
    'contestacoes', COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM public.marketplace_contestacoes x WHERE x.profissional_id = v_id), '[]'::jsonb),
    'ocorrencias', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', o.id, 'tipo', o.tipo, 'descricao', o.descricao, 'created_at', o.created_at, 'reflexo_visibilidade', o.reflexo_visibilidade) ORDER BY o.created_at DESC)
                             FROM public.marketplace_ocorrencias o WHERE o.profissional_id = v_id), '[]'::jsonb),
    'cupons', COALESCE((SELECT jsonb_agg(to_jsonb(k) ORDER BY k.created_at DESC) FROM public.marketplace_cupons k WHERE k.profissional_id = v_id), '[]'::jsonb),
    'destaques', COALESCE((SELECT jsonb_agg(to_jsonb(d) ORDER BY d.fim DESC) FROM public.marketplace_destaques d WHERE d.profissional_id = v_id), '[]'::jsonb),
    'autonomia_eventos', (SELECT count(*) FROM public.marketplace_autonomia_eventos WHERE profissional_id = v_id),
    'termos_versoes', v_versoes,
    'parceiro', CASE WHEN v_perfil->>'parceiro_id' IS NOT NULL THEN jsonb_build_object('id', v_perfil->>'parceiro_id') END
  );
END $marketye_meu_portal$;
GRANT EXECUTE ON FUNCTION public.marketye_meu_portal() TO authenticated;

-- ---------------------------------------------------------------------
-- QA: caso MKY-014 documentado + rotina
-- ---------------------------------------------------------------------
DO $qa$
DECLARE v_mod uuid;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'rede-parceiros';
  IF v_mod IS NULL THEN RETURN; END IF;

  INSERT INTO public.qa_casos_teste (modulo_id, codigo, titulo, tipo, prioridade, status, nivel, base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes) VALUES
  (v_mod, 'MKY-014', 'Portal do especialista abre logo depois do cadastro mínimo (sem área, sem registro, sem cidade)',
   'feliz', 'critica', 'aprovado', 'api', 'RN-001, RN-012 (cadastro sem acesso ao sistema); RN-021',
   'O cadastro curto (nome, documento, uma frase sobre o que faz, e-mail) precisa abrir o portal em seguida; nenhum campo opcional em branco pode derrubar a leitura do portal.',
   'Versões de termos em marketplace_config (chave termos_versoes).',
   '[{"ordem":1,"acao":"Cadastrar pela função só com nome, CPF fictício, uma frase e aceite","resultado_esperado":"status pendente"},
     {"ordem":2,"acao":"Como o próprio especialista (papel authenticated), abrir o portal (marketye_meu_portal)","resultado_esperado":"devolve o perfil, lista de anúncios vazia e completude entre 0 e 100"},
     {"ordem":3,"acao":"Salvar o perfil sem área e sem cidade; abrir o portal de novo","resultado_esperado":"continua abrindo"}]'::jsonb,
   'O portal nunca fica em branco por causa de campo opcional vazio.',
   'Regressão real de 11/09/2026: especialidades nulas derrubavam a função do portal. Roda em transação descartada.')
  ON CONFLICT (codigo) DO UPDATE SET titulo = EXCLUDED.titulo, tipo = EXCLUDED.tipo, prioridade = EXCLUDED.prioridade, nivel = EXCLUDED.nivel,
    base_legal = EXCLUDED.base_legal, objetivo = EXCLUDED.objetivo, pre_condicoes = EXCLUDED.pre_condicoes, passos = EXCLUDED.passos,
    resultado_esperado = EXCLUDED.resultado_esperado, observacoes = EXCLUDED.observacoes;
END $qa$;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_014()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_claims text; v_portal jsonb; v_uid uuid := gen_random_uuid(); v_res jsonb; v_id uuid;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);

  r.passo_ordem := 1; r.passo_acao := 'Cadastrar só com nome, CPF, uma frase e aceite'; r.esperado := 'pendente';
  INSERT INTO auth.users (id, email) VALUES (v_uid, 'qa-mky-esp-014-' || left(v_uid::text, 8) || '@sandbox.invalid');
  v_res := public.marketye_cadastrar_especialista_para(v_uid, jsonb_build_object(
    'nome_completo', 'QA Especialista 014', 'email', 'qa-mky-esp-014-' || left(v_uid::text, 8) || '@sandbox.invalid',
    'cpf_cnpj', '900.000.013-09', 'bio', 'Dou treinamentos para equipes de manutenção', 'modalidades', '["presencial"]'::jsonb,
    'especialidades', '[]'::jsonb, 'aceite_termos', true, 'origem', 'qa', 'tenant_origem', public.qa_sandbox_tenant_id()));
  v_id := (v_res->>'id')::uuid;
  IF COALESCE(v_res->>'status', '') <> 'pendente' THEN
    r.situacao := 'falhou'; r.obtido := 'ACHADO: cadastro nasceu ' || COALESCE(v_res->>'status', 'sem status'); PERFORM public.qa_mky_limpar(); RETURN r;
  END IF;

  r.passo_ordem := 2; r.passo_acao := 'Abrir o portal como o próprio especialista'; r.esperado := 'perfil, anúncios vazios e completude entre 0 e 100';
  PERFORM public.qa_mky_claims(v_uid);
  SET LOCAL ROLE authenticated;
  v_portal := public.marketye_meu_portal();
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF v_portal IS NULL OR (v_portal->'perfil'->>'id')::uuid IS DISTINCT FROM v_id OR jsonb_typeof(v_portal->'anuncios') <> 'array'
     OR (v_portal->>'completude')::numeric NOT BETWEEN 0 AND 100 THEN
    r.situacao := 'falhou'; r.obtido := 'ACHADO: portal veio incompleto: ' || left(COALESCE(v_portal::text, 'NULL'), 200); PERFORM public.qa_mky_limpar(); RETURN r;
  END IF;

  r.passo_ordem := 3; r.passo_acao := 'Salvar o perfil sem área e sem cidade; abrir de novo'; r.esperado := 'continua abrindo';
  PERFORM public.qa_mky_claims(v_uid);
  PERFORM public.marketye_meu_perfil_salvar(jsonb_build_object('especialidades', '[]'::jsonb, 'cidade', '', 'estado', ''));
  SET LOCAL ROLE authenticated;
  v_portal := public.marketye_meu_portal();
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF v_portal IS NULL OR (v_portal->>'completude') IS NULL THEN
    r.situacao := 'falhou'; r.obtido := 'ACHADO: portal vazio depois de salvar o perfil'; PERFORM public.qa_mky_limpar(); RETURN r;
  END IF;

  r.situacao := 'passou'; r.obtido := 'Portal abriu nas duas leituras; completude ' || (v_portal->>'completude') || '%.';
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE; PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES ('MKY-014', 'qa_caso_mky_014')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- ===================================================================
-- ORIGEM: 20260912000100_marketye_semear_ilha_teste.sql
-- ===================================================================
-- =====================================================================
-- MARKETYE · SEMENTE DO MOBILIÁRIO DE TESTE COMO FUNÇÃO (com diagnóstico)
--
-- Por quê: a migration 20260911223000 semeia o "Especialista Staging (QA)"
-- dentro de um bloco que engole qualquer erro em um aviso — e o robô que
-- aplica migrations não mostra avisos. No ambiente de teste o mobiliário
-- não apareceu na vitrine (teste de tela MKY-021 caiu por "nenhum anúncio")
-- e não havia como saber o motivo.
--
-- O que muda: a semente vira a função marketye_semear_ilha_teste(), que
--   1. só age onde existe a Empresa Staging LTDA (ambiente de teste);
--   2. é idempotente: se o especialista já existe, REPARA (ativo, com selo,
--      anúncios publicados) em vez de pular;
--   3. devolve um JSON com o resultado ou o erro (SQLSTATE + mensagem),
--      para a esteira imprimir no log em vez de esconder.
-- A função de semear a conta-robô (seed-e2e-user) passa a chamá-la a cada
-- corrida, com o papel service_role. Aqui mesmo ela roda uma vez.
--
-- Não entra no script de entrega: é mobiliário fictício do ambiente de teste.
-- Idempotente: CREATE OR REPLACE; a semente tem sentinela pelo e-mail.
-- =====================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.marketye_semear_ilha_teste()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_semear_ilha_teste$
DECLARE
  v_staging uuid; v_prof uuid; v_cat_pgr uuid; v_cat_aep uuid; v_anuncios int; v_motivo text;
BEGIN
  SELECT id INTO v_staging FROM public.tenants WHERE nome = 'Empresa Staging LTDA' LIMIT 1;
  IF v_staging IS NULL THEN
    -- id fixo da ilha de teste (supabase/seeds/staging.sql); só vale se for mesmo a empresa de teste
    SELECT id INTO v_staging FROM public.tenants WHERE id = '11111111-1111-1111-1111-111111111111' AND nome ILIKE '%staging%';
  END IF;
  IF v_staging IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'sem Empresa Staging neste banco (esperado fora do ambiente de teste)');
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
      (NULL, v_staging, 'Especialista Staging (QA)', 'especialista.staging@youreyes.local', '(46) 90000-0000', '90000001228', 'pf',
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
  RETURN jsonb_build_object('ok', true, 'motivo', v_motivo, 'profissional_id', v_prof, 'tenant_id', v_staging, 'anuncios_publicados', v_anuncios,
                            'categoria_pgr', v_cat_pgr IS NOT NULL, 'categoria_aep', v_cat_aep IS NOT NULL);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'erro', SQLERRM, 'sqlstate', SQLSTATE);
END $marketye_semear_ilha_teste$;
REVOKE ALL ON FUNCTION public.marketye_semear_ilha_teste() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.marketye_semear_ilha_teste() TO service_role;

-- Roda uma vez aqui também (no ambiente de teste semeia; em outros bancos só devolve o motivo).
DO $semente$
DECLARE v jsonb;
BEGIN
  v := public.marketye_semear_ilha_teste();
  RAISE NOTICE 'MarketYE · mobiliário de teste: %', v;
END $semente$;

-- ===================================================================
-- ORIGEM: 20260912001000_marketye_semente_cpf_alternativo.sql
-- ===================================================================
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

-- ===================================================================
-- ORIGEM: 20260912002000_marketye_busca_relaxamento.sql
-- ===================================================================
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

-- ===================================================================
-- ORIGEM: 20260912013000_marketye_anexos_fotos.sql
-- ===================================================================
-- MarketYE: anexos do especialista (documentos comprobatórios e foto de perfil)
--
-- Defeito visto no ambiente de teste (12/09/2026): o cadastro pelo formulário
-- de especialista criava o perfil, mas os documentos não subiam. A política de
-- upload do bucket `marketplace-docs` exige que a primeira pasta do caminho
-- seja o id do especialista, e a tela mandava o id do usuário na frente. A tela
-- foi corrigida; aqui entra o que faltava no banco:
--  1. bucket PÚBLICO `marketplace-fotos` para a foto de perfil (a vitrine lê por
--     URL pública; `marketplace-docs` é privado e a URL "pública" dele não abre);
--  2. superadmin lê `marketplace-docs`: é quem aprova os cadastros, e o painel
--     de moderação passa a abrir cada documento por link assinado;
--  3. leitura ampla demais retirada: a política antiga deixava qualquer
--     admin/owner de EMPRESA CLIENTE ler os documentos pessoais de todos os
--     especialistas (no bucket e na tabela). Só o dono e o superadmin leem.
-- Idempotente: rodar de novo não duplica nem quebra.
SET lock_timeout = '10s';

INSERT INTO storage.buckets (id, name, public)
VALUES ('marketplace-fotos', 'marketplace-fotos', true)
ON CONFLICT (id) DO NOTHING;

-- Foto de perfil: qualquer um lê (bucket público); só o especialista dono sobe, troca e apaga a própria.
DROP POLICY IF EXISTS "MarketYE: foto de perfil publica" ON storage.objects;
CREATE POLICY "MarketYE: foto de perfil publica" ON storage.objects FOR SELECT
  USING (bucket_id = 'marketplace-fotos');

DROP POLICY IF EXISTS "MarketYE: especialista sobe a propria foto" ON storage.objects;
CREATE POLICY "MarketYE: especialista sobe a propria foto" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'marketplace-fotos'
    AND split_part(name, '/', 1) IN (SELECT id::text FROM public.marketplace_profissionais WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS "MarketYE: especialista troca a propria foto" ON storage.objects;
CREATE POLICY "MarketYE: especialista troca a propria foto" ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'marketplace-fotos'
    AND split_part(name, '/', 1) IN (SELECT id::text FROM public.marketplace_profissionais WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS "MarketYE: especialista apaga a propria foto" ON storage.objects;
CREATE POLICY "MarketYE: especialista apaga a propria foto" ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'marketplace-fotos'
    AND split_part(name, '/', 1) IN (SELECT id::text FROM public.marketplace_profissionais WHERE user_id = auth.uid()));

-- Documentos comprobatórios (bucket privado): o superadmin lê para aprovar o cadastro.
DROP POLICY IF EXISTS "MarketYE: superadmin le os documentos" ON storage.objects;
CREATE POLICY "MarketYE: superadmin le os documentos" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'marketplace-docs' AND public.is_superadmin(auth.uid()));

-- Leitura ampla demais (admin de qualquer empresa cliente) sai do bucket e da tabela.
DROP POLICY IF EXISTS "Admins can view all docs" ON storage.objects;

DROP POLICY IF EXISTS "Users can view own docs" ON public.marketplace_profissional_documentos;
CREATE POLICY "Users can view own docs" ON public.marketplace_profissional_documentos FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM public.marketplace_profissionais p WHERE p.id = profissional_id AND p.user_id = auth.uid())
    OR public.is_superadmin(auth.uid())
  );

COMMENT ON COLUMN public.marketplace_profissional_documentos.arquivo_url IS
  'Caminho do objeto no bucket marketplace-docs. Registros anteriores a 12/09/2026 guardam a URL publica, que nao abre (bucket privado). Quem exibe gera link assinado.';

-- ===================================================================
-- ORIGEM: 20260912030000_marketye_qa_rotinas_seguranca.sql
-- ===================================================================
-- =====================================================================
-- MARKETYE · QA: ROTINAS DA FAMÍLIA DE SEGURANÇA (MKY-110 a MKY-116)
--
-- Pacote de QA de 12/09: os sete casos de segurança e RLS ganham rotina.
-- Cada rotina monta um cenário completo no cercado (dois especialistas,
-- duas empresas, conversas, mensagens, cupom, contestação, ocorrência,
-- destaque, documento, denúncia, contratação, demanda latente), troca de
-- papel e de claims (SET LOCAL ROLE authenticated + request.jwt.claims)
-- e prova o LADO NEGATIVO do isolamento tabela a tabela, com controles
-- positivos para a rotina nunca passar à toa.
--
-- Duas correções de defesa em profundidade que as rotinas exigem:
--   D-05: EXECUTE das funções marketye_* deixa de ser herdado de PUBLIC
--         (visitante anônimo executava 47 funções, guardadas só por dentro).
--         Só a vitrine pública e as vagas de demanda ficam para anon; as
--         internas ficam só para service_role.
--   D-15: marketplace_reputacao expunha a qualquer usuário autenticado o
--         motivo do aviso de ajuste de nível de todos os especialistas;
--         as colunas de aviso saem da leitura direta (o portal lê por função).
--
-- Idempotente: REVOKE/GRANT repetíveis, CREATE OR REPLACE, ON CONFLICT.
-- =====================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- 1) D-05 — superfície mínima de EXECUTE nas funções do módulo
-- ---------------------------------------------------------------------
DO $seg$
DECLARE f record;
BEGIN
  FOR f IN SELECT p.oid::regprocedure AS assinatura, p.proname
           FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public' AND p.proname LIKE 'marketye_%'
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', f.assinatura);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', f.assinatura);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM authenticated', f.assinatura);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f.assinatura);
    IF f.proname NOT IN ('marketye_buscar_interno', 'marketye_cadastrar_especialista_para', 'marketye_recalcular_reputacao', 'marketye_semear_ilha_teste') THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', f.assinatura);
    END IF;
    IF f.proname IN ('marketye_vitrine_publica', 'marketye_vagas_demanda', 'marketye_meu_id') THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon', f.assinatura);
    END IF;
  END LOOP;
END $seg$;

-- ---------------------------------------------------------------------
-- 2) D-15 — aviso de ajuste de nível não é leitura pública
--    D-16 — visitante anônimo tinha SELECT de tabela inteira em avaliações
--    (inclusive tenant_id e avaliador_id). A política de leitura é só para
--    authenticated, então devolvia zero linhas — mas a concessão ficava lá.
--    Visitante não lê avaliações direto (a vitrine exige login; a página
--    pública lê por função).
-- ---------------------------------------------------------------------
REVOKE SELECT ON public.marketplace_avaliacoes FROM anon;
REVOKE SELECT ON public.marketplace_reputacao FROM authenticated, anon;
GRANT SELECT (profissional_id, saude_score, saude_cor, media_90d, avaliacoes_90d, clientes_unicos_total, clientes_unicos_90d, taxa_resposta_90d,
              tempo_resposta_mediano_min, taxa_cancelamento_90d, ocorrencias_90d, servicos_concluidos_total, nivel, nivel_desde, abaixo_piso,
              protegido_ate, calculado_em)
  ON public.marketplace_reputacao TO authenticated;

-- ---------------------------------------------------------------------
-- 2b) D-17 — políticas que liam marketplace_profissionais.user_id como o
--     próprio usuário. Desde que a coluna user_id foi fechada para usuário
--     comum (MKY-012), essas 13 políticas quebravam com "permission denied
--     for table marketplace_profissionais" em qualquer leitura direta de
--     anúncios, pacotes, contratações, comissões e documentos, e no upload
--     de foto e documento do especialista (Storage). Achado pela MKY-110.
--     Correção: comparar com marketye_meu_id() (função segura que devolve
--     o id do especialista da sessão), sem ler a coluna fechada.
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS "Professionals view own commissions" ON public.marketplace_afiliados_comissoes;
CREATE POLICY "Professionals view own commissions" ON public.marketplace_afiliados_comissoes FOR SELECT TO authenticated
  USING (profissional_id = public.marketye_meu_id());

DROP POLICY IF EXISTS "Authenticated users can insert audit" ON public.marketplace_audit_log;
CREATE POLICY "Authenticated users can insert audit" ON public.marketplace_audit_log FOR INSERT TO authenticated
  WITH CHECK (tenant_id = public.get_user_tenant_id() OR profissional_id = public.marketye_meu_id());

DROP POLICY IF EXISTS "Professionals can update their contracts" ON public.marketplace_contratacoes;
CREATE POLICY "Professionals can update their contracts" ON public.marketplace_contratacoes FOR UPDATE TO authenticated
  USING (profissional_id = public.marketye_meu_id());
DROP POLICY IF EXISTS "Professionals can view their contracts" ON public.marketplace_contratacoes;
CREATE POLICY "Professionals can view their contracts" ON public.marketplace_contratacoes FOR SELECT TO authenticated
  USING (profissional_id = public.marketye_meu_id());

DROP POLICY IF EXISTS "Profissionais manage own pacotes" ON public.marketplace_pacotes;
CREATE POLICY "Profissionais manage own pacotes" ON public.marketplace_pacotes FOR ALL TO public
  USING (profissional_id = public.marketye_meu_id()) WITH CHECK (profissional_id = public.marketye_meu_id());

DROP POLICY IF EXISTS "Users can insert own docs" ON public.marketplace_profissional_documentos;
CREATE POLICY "Users can insert own docs" ON public.marketplace_profissional_documentos FOR INSERT TO public
  WITH CHECK (profissional_id = public.marketye_meu_id());
DROP POLICY IF EXISTS "Users can view own docs" ON public.marketplace_profissional_documentos;
CREATE POLICY "Users can view own docs" ON public.marketplace_profissional_documentos FOR SELECT TO public
  USING (profissional_id = public.marketye_meu_id() OR public.is_superadmin(auth.uid()));

DROP POLICY IF EXISTS "Professionals manage own services" ON public.marketplace_servicos;
CREATE POLICY "Professionals manage own services" ON public.marketplace_servicos FOR ALL TO authenticated
  USING (profissional_id = public.marketye_meu_id()) WITH CHECK (profissional_id = public.marketye_meu_id());

DO $pol$
BEGIN
  DROP POLICY IF EXISTS "MarketYE: especialista apaga a propria foto" ON storage.objects;
  CREATE POLICY "MarketYE: especialista apaga a propria foto" ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'marketplace-fotos' AND split_part(name, '/', 1) = public.marketye_meu_id()::text);
  DROP POLICY IF EXISTS "MarketYE: especialista sobe a propria foto" ON storage.objects;
  CREATE POLICY "MarketYE: especialista sobe a propria foto" ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'marketplace-fotos' AND split_part(name, '/', 1) = public.marketye_meu_id()::text);
  DROP POLICY IF EXISTS "MarketYE: especialista troca a propria foto" ON storage.objects;
  CREATE POLICY "MarketYE: especialista troca a propria foto" ON storage.objects FOR UPDATE TO authenticated
    USING (bucket_id = 'marketplace-fotos' AND split_part(name, '/', 1) = public.marketye_meu_id()::text);
  DROP POLICY IF EXISTS "Profissional dono pode ler marketplace-docs" ON storage.objects;
  CREATE POLICY "Profissional dono pode ler marketplace-docs" ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'marketplace-docs' AND EXISTS (
      SELECT 1 FROM public.marketplace_profissional_documentos d
      WHERE d.arquivo_url LIKE '%' || storage.objects.name AND d.profissional_id = public.marketye_meu_id()));
  DROP POLICY IF EXISTS "Profissional pode subir marketplace-docs" ON storage.objects;
  CREATE POLICY "Profissional pode subir marketplace-docs" ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'marketplace-docs' AND split_part(name, '/', 1) = public.marketye_meu_id()::text);
EXCEPTION WHEN undefined_table OR undefined_object OR insufficient_privilege THEN
  RAISE NOTICE 'MarketYE: políticas de storage não ajustadas neste banco (%): %', SQLSTATE, SQLERRM;
END $pol$;

-- ---------------------------------------------------------------------
-- 3) Limpeza ampliada (denúncias, contratações e demanda das contas de QA)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.qa_mky_limpar()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  -- Dependentes sem ON DELETE CASCADE primeiro (auditoria, avaliações, denúncias, contratações), depois o especialista (o resto cascateia).
  DELETE FROM public.marketplace_audit_log WHERE profissional_id IN (SELECT id FROM public.marketplace_profissionais WHERE nome_completo LIKE 'QA Especialista %' OR email LIKE 'qa-mky-%@sandbox.invalid');
  DELETE FROM public.marketplace_avaliacoes WHERE profissional_id IN (SELECT id FROM public.marketplace_profissionais WHERE nome_completo LIKE 'QA Especialista %' OR email LIKE 'qa-mky-%@sandbox.invalid');
  DELETE FROM public.marketplace_denuncias WHERE profissional_id IN (SELECT id FROM public.marketplace_profissionais WHERE nome_completo LIKE 'QA Especialista %' OR email LIKE 'qa-mky-%@sandbox.invalid');
  DELETE FROM public.marketplace_contratacoes WHERE profissional_id IN (SELECT id FROM public.marketplace_profissionais WHERE nome_completo LIKE 'QA Especialista %' OR email LIKE 'qa-mky-%@sandbox.invalid');
  DELETE FROM public.marketplace_leads WHERE profissional_id IN (SELECT id FROM public.marketplace_profissionais WHERE nome_completo LIKE 'QA Especialista %' OR email LIKE 'qa-mky-%@sandbox.invalid');
  DELETE FROM public.marketplace_profissionais WHERE nome_completo LIKE 'QA Especialista %' OR email LIKE 'qa-mky-%@sandbox.invalid';
  DELETE FROM public.marketplace_demanda_latente WHERE uf = 'QA';
  DELETE FROM public.marketplace_categorias WHERE slug LIKE 'qa-mky-%';
  DELETE FROM public.superadmins WHERE email LIKE 'qa-mky-%@sandbox.invalid';
  DELETE FROM public.profiles WHERE nome_completo LIKE 'QA Empresa %' AND user_id IN (SELECT id FROM auth.users WHERE email LIKE 'qa-mky-%@sandbox.invalid');
  DELETE FROM public.tenants WHERE slug LIKE 'qa-mky-%';
  DELETE FROM auth.users WHERE email LIKE 'qa-mky-%@sandbox.invalid';
END $$;

-- ---------------------------------------------------------------------
-- 4) Cenário compartilhado da família de segurança
--    A e B: especialistas aprovados (B com anúncio publicado + rascunho, cupom,
--    contestação, ocorrência, destaque). X (cercado 1) conversa com B; Y
--    (cercado 2) conversa com A, avalia A, denuncia A, tem contratação legada
--    e demanda latente. Devolve todos os ids em JSON. Restaura os claims.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.qa_mky_cenario_seguranca()
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v_claims text := current_setting('request.jwt.claims', true);
  t1 uuid := public.qa_sandbox_tenant_id(); t2 uuid; sa uuid; x uuid; y uuid; a record; b record; cat uuid;
  b_pub uuid; b_rasc uuid; a_pub uuid; lead_xb uuid; lead_ya uuid; msg_xb uuid; msg_ya uuid; cupom_b uuid; contest_b uuid; ocorr_b uuid;
  dest_b uuid; doc_xb uuid; den_y uuid; contr_y uuid; dem_y uuid; aval_a uuid; v jsonb;
BEGIN
  IF t1 IS NULL THEN RAISE EXCEPTION 'Cercado qa-sandbox não existe'; END IF;
  SELECT id INTO t2 FROM public.tenants WHERE slug = 'qa-sandbox-2';
  IF t2 IS NULL THEN RAISE EXCEPTION 'Segundo cercado (qa-sandbox-2) não existe'; END IF;
  sa := public.qa_mky_superadmin();
  x := public.qa_mky_usuario_empresa(t1, '110x'); y := public.qa_mky_usuario_empresa(t2, '110y');
  SELECT * INTO a FROM public.qa_mky_especialista('110a', '900.000.032-71');
  SELECT * INTO b FROM public.qa_mky_especialista('110b', '900.000.033-52');
  SELECT id INTO cat FROM public.marketplace_categorias WHERE slug = 'seguranca-trabalho';

  PERFORM public.qa_mky_claims(sa);
  PERFORM public.marketye_moderar_especialista(a.prof_id, 'aprovado', NULL, true);
  PERFORM public.marketye_moderar_especialista(b.prof_id, 'aprovado', NULL, true);

  PERFORM public.qa_mky_claims(b.uid);
  v := public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Seguranca B publicado', 'descricao', 'Serviço fictício de teste do MarketYE, apenas para a rotina automatizada de segurança.', 'categoria_id', cat, 'modalidade', 'online', 'tipo_preco', 'hora', 'preco_referencia', 300));
  b_pub := (v->>'id')::uuid; PERFORM public.marketye_anuncio_publicar(b_pub);
  v := public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Seguranca B rascunho', 'descricao', 'Rascunho fictício de teste do MarketYE que não deve aparecer para ninguém.', 'categoria_id', cat, 'modalidade', 'online', 'tipo_preco', 'sob_orcamento'));
  b_rasc := (v->>'id')::uuid;
  v := public.marketye_cupom_salvar(jsonb_build_object('codigo', 'QASEG110', 'descricao', 'cupom de teste', 'desconto_percentual', 10));
  SELECT id INTO cupom_b FROM public.marketplace_cupons WHERE profissional_id = b.prof_id AND codigo = 'QASEG110';

  PERFORM public.qa_mky_claims(a.uid);
  v := public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Seguranca A publicado', 'descricao', 'Serviço fictício de teste do MarketYE, apenas para a rotina automatizada de segurança.', 'categoria_id', cat, 'modalidade', 'presencial', 'tipo_preco', 'hora', 'preco_referencia', 250));
  a_pub := (v->>'id')::uuid; PERFORM public.marketye_anuncio_publicar(a_pub);

  PERFORM public.qa_mky_claims(x);
  lead_xb := (public.marketye_abrir_lead(b.prof_id, b_pub, 'Preciso de um PGR para a minha empresa de teste.')->>'id')::uuid;
  SELECT id INTO msg_xb FROM public.marketplace_lead_mensagens WHERE lead_id = lead_xb ORDER BY created_at LIMIT 1;

  PERFORM public.qa_mky_claims(y);
  lead_ya := (public.marketye_abrir_lead(a.prof_id, a_pub, 'Preciso de um laudo para a minha empresa de teste.')->>'id')::uuid;
  SELECT id INTO msg_ya FROM public.marketplace_lead_mensagens WHERE lead_id = lead_ya ORDER BY created_at LIMIT 1;
  PERFORM public.qa_mky_claims(a.uid); PERFORM public.marketye_lead_mensagem(lead_ya, 'Posso atender na próxima semana.');
  PERFORM public.qa_mky_claims(y); PERFORM public.marketye_lead_status(lead_ya, 'ganho');
  v := public.marketye_avaliar('lead', lead_ya, '{"pontualidade":4,"clareza":5,"aderencia_escopo":4,"profissionalismo":5}'::jsonb, 'Avaliação fictícia de teste.');
  SELECT id INTO aval_a FROM public.marketplace_avaliacoes WHERE lead_id = lead_ya AND direcao = 'cliente_para_especialista' LIMIT 1;

  PERFORM public.qa_mky_claims(sa);
  v := public.marketye_destaque_criar(b.prof_id, NULL, 'topo', NULL, NULL, CURRENT_DATE, CURRENT_DATE + 7, NULL);
  dest_b := (v->>'id')::uuid;
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);

  -- Mobiliário inserido direto (a rotina roda como o dono do banco): contestação, ocorrência, documento, denúncia, contratação legada, demanda latente.
  INSERT INTO public.marketplace_contestacoes (profissional_id, decisao_tipo, motivo) VALUES (b.prof_id, 'outro', 'Contestação fictícia de teste da rotina de segurança.') RETURNING id INTO contest_b;
  INSERT INTO public.marketplace_ocorrencias (profissional_id, tipo, descricao, reflexo_visibilidade) VALUES (b.prof_id, 'ocorrencia', 'Ocorrência fictícia de teste.', false) RETURNING id INTO ocorr_b;
  INSERT INTO public.marketplace_lead_documentos (lead_id, documento_id, tipo) VALUES (lead_xb, gen_random_uuid(), 'proposta') RETURNING id INTO doc_xb;
  INSERT INTO public.marketplace_denuncias (tenant_id, profissional_id, denunciante_id, denunciante_nome, tipo, descricao) VALUES (t2, a.prof_id, y, 'QA Empresa 110y', 'outro', 'Denúncia fictícia de teste.') RETURNING id INTO den_y;
  INSERT INTO public.marketplace_contratacoes (tenant_id, servico_id, profissional_id, solicitante_id, solicitante_nome, modalidade) VALUES (t2, a_pub, a.prof_id, y, 'QA Empresa 110y', 'presencial') RETURNING id INTO contr_y;
  INSERT INTO public.marketplace_demanda_latente (tenant_id, categoria_id, uf, termos, resultados) VALUES (t2, cat, 'QA', 'demanda fictícia', 0) RETURNING id INTO dem_y;

  RETURN jsonb_build_object('t1', t1, 't2', t2, 'sa', sa, 'x', x, 'y', y, 'a_uid', a.uid, 'a_prof', a.prof_id, 'b_uid', b.uid, 'b_prof', b.prof_id,
                            'b_pub', b_pub, 'b_rasc', b_rasc, 'a_pub', a_pub, 'lead_xb', lead_xb, 'lead_ya', lead_ya, 'msg_xb', msg_xb, 'msg_ya', msg_ya,
                            'cupom_b', cupom_b, 'contest_b', contest_b, 'ocorr_b', ocorr_b, 'dest_b', dest_b, 'doc_xb', doc_xb, 'den_y', den_y,
                            'contr_y', contr_y, 'dem_y', dem_y, 'aval_a', aval_a);
END $$;

-- ---------------------------------------------------------------------
-- 5) Rotinas
-- ---------------------------------------------------------------------
-- MKY-110 — especialista A não lê nem escreve nas linhas de B (tabela a tabela)
CREATE OR REPLACE FUNCTION public.qa_caso_mky_110()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; n int;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  r.passo_ordem := 1; r.passo_acao := 'Como A: ler as linhas de B em cada tabela'; r.esperado := 'zero linhas nas tabelas privadas; só o anúncio publicado de B; as próprias linhas visíveis (controle)';
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.marketplace_consentimentos WHERE profissional_id = (s->>'a_prof')::uuid; IF n = 0 THEN falhas := array_append(falhas, 'controle: A não lê os próprios consentimentos'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_leads WHERE profissional_id = (s->>'b_prof')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'leads de B'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_lead_mensagens WHERE lead_id = (s->>'lead_xb')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'mensagens de B'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_lead_documentos WHERE lead_id = (s->>'lead_xb')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'documentos da conversa de B'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_cupons WHERE profissional_id = (s->>'b_prof')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'cupons de B'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_consentimentos WHERE profissional_id = (s->>'b_prof')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'consentimentos de B'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_contestacoes WHERE profissional_id = (s->>'b_prof')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'contestações de B'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_ocorrencias WHERE profissional_id = (s->>'b_prof')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'ocorrências de B'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_autonomia_eventos WHERE profissional_id = (s->>'b_prof')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'trilha de autonomia de B'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_destaques WHERE profissional_id = (s->>'b_prof')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'destaques de B'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_servicos WHERE id = (s->>'b_rasc')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'rascunho de anúncio de B'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_servicos WHERE id = (s->>'b_pub')::uuid; IF n <> 1 THEN falhas := array_append(falhas, 'controle: anúncio publicado de B deveria ser visível'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Como A: escrever nas linhas de B'; r.esperado := 'nada muda';
  UPDATE public.marketplace_servicos SET nome = 'invadido' WHERE id = (s->>'b_pub')::uuid; GET DIAGNOSTICS n = ROW_COUNT; IF n > 0 THEN falhas := array_append(falhas, 'UPDATE no anúncio de B alterou linha'); END IF;
  BEGIN
    INSERT INTO public.marketplace_cupons (profissional_id, codigo, desconto_percentual) VALUES ((s->>'b_prof')::uuid, 'INVASAO', 5);
    falhas := array_append(falhas, 'INSERT de cupom em nome de B foi aceito');
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    INSERT INTO public.marketplace_servicos (profissional_id, nome, descricao, modalidade) VALUES ((s->>'b_prof')::uuid, 'invasao', 'anúncio em nome de outro', 'online');
    falhas := array_append(falhas, 'INSERT de anúncio em nome de B foi aceito');
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    DELETE FROM public.marketplace_cupons WHERE id = (s->>'cupom_b')::uuid; GET DIAGNOSTICS n = ROW_COUNT; IF n > 0 THEN falhas := array_append(falhas, 'DELETE do cupom de B apagou linha'); END IF;
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF array_length(falhas, 1) IS NULL THEN
    r.situacao := 'passou'; r.obtido := 'A não lê nem altera leads, mensagens, documentos, cupons, consentimentos, contestações, ocorrências, trilha, destaques e rascunhos de B; só o anúncio publicado, como a vitrine exige.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; ');
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE; PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-111 — empresa X não lê nem escreve nas linhas da empresa Y
CREATE OR REPLACE FUNCTION public.qa_caso_mky_111()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; n int;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  r.passo_ordem := 1; r.passo_acao := 'Como usuário de X: ler as linhas de Y em cada tabela'; r.esperado := 'zero linhas; a própria conversa visível (controle)';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  PERFORM set_config('app.qa_modo', 'off', true);  -- a trava do cercado dispara antes do RLS e lê tenants sob RLS como authenticated (ver MKY-001)
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.marketplace_leads WHERE id = (s->>'lead_xb')::uuid; IF n <> 1 THEN falhas := array_append(falhas, 'controle: X não lê a própria conversa'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_leads WHERE id = (s->>'lead_ya')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'lead de Y'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_lead_mensagens WHERE lead_id = (s->>'lead_ya')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'mensagens de Y'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_denuncias WHERE id = (s->>'den_y')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'denúncia de Y'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_contratacoes WHERE id = (s->>'contr_y')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'contratação de Y'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_demanda_latente WHERE id = (s->>'dem_y')::uuid; IF n > 0 THEN falhas := array_append(falhas, 'demanda latente de Y'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_avaliacoes WHERE id = (s->>'aval_a')::uuid AND direcao = 'cliente_para_especialista'; IF n <> 1 THEN falhas := array_append(falhas, 'controle: avaliação pública de especialista deveria ser legível'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Como usuário de X: escrever em nome de Y'; r.esperado := 'recusado ou nada muda';
  BEGIN
    INSERT INTO public.marketplace_denuncias (tenant_id, profissional_id, denunciante_id, denunciante_nome, tipo, descricao) VALUES ((s->>'t2')::uuid, (s->>'a_prof')::uuid, (s->>'x')::uuid, 'QA Empresa 110x', 'outro', 'denúncia em nome de outra empresa');
    falhas := array_append(falhas, 'INSERT de denúncia com tenant de Y foi aceito');
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  UPDATE public.marketplace_contratacoes SET observacoes = 'invadido' WHERE id = (s->>'contr_y')::uuid; GET DIAGNOSTICS n = ROW_COUNT; IF n > 0 THEN falhas := array_append(falhas, 'UPDATE na contratação de Y alterou linha'); END IF;
  RESET ROLE;
  PERFORM set_config('app.qa_modo', 'on', true);
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF array_length(falhas, 1) IS NULL THEN
    r.situacao := 'passou'; r.obtido := 'X não lê leads, mensagens, denúncias, contratações nem demanda latente de Y, e não escreve em nome de Y; lê a própria conversa e as avaliações públicas de especialistas.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; ');
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE; PERFORM set_config('app.qa_modo', 'on', true); PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-112 — estrutura do RLS: toda tabela com política; nada permissivo demais; colunas sensíveis fechadas
CREATE OR REPLACE FUNCTION public.qa_caso_mky_112()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; falhas text[] := '{}'; v text;
BEGIN
  r.passo_ordem := 1; r.passo_acao := 'Tabelas marketplace_* com RLS ligado e zero políticas, ou sem RLS'; r.esperado := 'nenhuma';
  SELECT string_agg(c.relname, ', ') INTO v FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relname LIKE 'marketplace_%' AND c.relrowsecurity
    AND NOT EXISTS (SELECT 1 FROM pg_policies p WHERE p.schemaname = 'public' AND p.tablename = c.relname);
  IF v IS NOT NULL THEN falhas := array_append(falhas, 'RLS ligado sem política (inacessível por engano): ' || v); END IF;
  SELECT string_agg(c.relname, ', ') INTO v FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relname LIKE 'marketplace_%' AND NOT c.relrowsecurity;
  IF v IS NOT NULL THEN falhas := array_append(falhas, 'sem RLS: ' || v); END IF;

  r.passo_ordem := 2; r.passo_acao := 'Políticas com USING true ou WITH CHECK true em tabela sensível'; r.esperado := 'só nas públicas por desenho (categorias, escopo, config, pacotes) e nas de conteúdo público com colunas fechadas (avaliações, reputação)';
  SELECT string_agg(p.tablename || '.' || p.policyname, ', ') INTO v FROM pg_policies p
  WHERE p.schemaname = 'public' AND p.tablename LIKE 'marketplace_%'
    AND (btrim(COALESCE(p.qual, '')) = 'true' OR btrim(COALESCE(p.with_check, '')) = 'true')
    AND p.tablename NOT IN ('marketplace_categorias', 'marketplace_escopo_habilitacao', 'marketplace_config', 'marketplace_pacotes', 'marketplace_avaliacoes', 'marketplace_reputacao');
  IF v IS NOT NULL THEN falhas := array_append(falhas, 'política permissiva demais: ' || v); END IF;
  SELECT string_agg(p.tablename || '.' || p.policyname, ', ') INTO v FROM pg_policies p
  WHERE p.schemaname = 'public' AND p.tablename LIKE 'marketplace_%' AND btrim(COALESCE(p.with_check, '')) = 'true';
  IF v IS NOT NULL THEN falhas := array_append(falhas, 'WITH CHECK true (escrita aberta): ' || v); END IF;

  r.passo_ordem := 3; r.passo_acao := 'Colunas sensíveis legíveis por authenticated ou anon'; r.esperado := 'nenhuma';
  SELECT string_agg(table_name || '.' || column_name || ' (' || grantee || ')', ', ') INTO v FROM information_schema.column_privileges
  WHERE table_schema = 'public' AND privilege_type = 'SELECT' AND grantee IN ('authenticated', 'anon')
    AND ((table_name = 'marketplace_profissionais' AND column_name IN ('email', 'telefone', 'cpf_cnpj', 'user_id', 'tenant_id'))
      OR (table_name = 'marketplace_avaliacoes' AND column_name IN ('tenant_id', 'avaliador_id'))
      OR (table_name = 'marketplace_reputacao' AND column_name IN ('nivel_aviso_motivo', 'nivel_aviso_em')));
  IF v IS NOT NULL THEN falhas := array_append(falhas, 'coluna sensível exposta: ' || v); END IF;
  -- Leitura de tabela inteira (sem restrição de coluna) nas três tabelas com colunas sensíveis:
  SELECT string_agg(table_name || ' (' || grantee || ')', ', ') INTO v FROM information_schema.role_table_grants
  WHERE table_schema = 'public' AND privilege_type = 'SELECT' AND grantee IN ('authenticated', 'anon')
    AND table_name IN ('marketplace_profissionais', 'marketplace_avaliacoes', 'marketplace_reputacao');
  IF v IS NOT NULL THEN falhas := array_append(falhas, 'SELECT de tabela inteira onde deveria ser por coluna: ' || v); END IF;

  IF array_length(falhas, 1) IS NULL THEN
    r.situacao := 'passou'; r.obtido := 'Toda tabela do módulo tem RLS e política; nenhuma política aberta fora das públicas por desenho; e-mail, telefone, documento, avaliador e aviso de nível não são legíveis por usuário comum.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; ');
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-113 — UPDATE/DELETE onde o papel só tem SELECT: zero linhas e valor inalterado
CREATE OR REPLACE FUNCTION public.qa_caso_mky_113()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; n int; v_nota numeric; v_texto text; v_status text; v_lib boolean; v_nivel text; v_cons int;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  SELECT count(*) INTO v_cons FROM public.marketplace_consentimentos WHERE profissional_id = (s->>'a_prof')::uuid;
  r.passo_ordem := 1; r.passo_acao := 'Como A: alterar a avaliação recebida, a mensagem da empresa, o próprio consentimento, a própria reputação e o próprio lead'; r.esperado := '0 linhas em todos';
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  PERFORM set_config('app.qa_modo', 'off', true);  -- a trava do cercado lê tenants sob RLS como authenticated (ver MKY-001)
  SET LOCAL ROLE authenticated;
  BEGIN UPDATE public.marketplace_avaliacoes SET nota_geral = 5 WHERE id = (s->>'aval_a')::uuid; GET DIAGNOSTICS n = ROW_COUNT; IF n > 0 THEN falhas := array_append(falhas, 'avaliação recebida alterada'); END IF; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN UPDATE public.marketplace_lead_mensagens SET texto = 'invadido' WHERE id = (s->>'msg_ya')::uuid; GET DIAGNOSTICS n = ROW_COUNT; IF n > 0 THEN falhas := array_append(falhas, 'mensagem da empresa alterada'); END IF; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN DELETE FROM public.marketplace_consentimentos WHERE profissional_id = (s->>'a_prof')::uuid; GET DIAGNOSTICS n = ROW_COUNT; IF n > 0 THEN falhas := array_append(falhas, 'consentimento apagado'); END IF; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN UPDATE public.marketplace_reputacao SET nivel = 'top' WHERE profissional_id = (s->>'a_prof')::uuid; GET DIAGNOSTICS n = ROW_COUNT; IF n > 0 THEN falhas := array_append(falhas, 'reputação alterada'); END IF; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN UPDATE public.marketplace_leads SET status = 'ganho' WHERE id = (s->>'lead_xb')::uuid; GET DIAGNOSTICS n = ROW_COUNT; IF n > 0 THEN falhas := array_append(falhas, 'lead alterado pelo especialista'); END IF; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  RESET ROLE;
  r.passo_ordem := 2; r.passo_acao := 'Como usuário de X: liberar o contato e mudar o status direto na tabela'; r.esperado := '0 linhas';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  SET LOCAL ROLE authenticated;
  BEGIN UPDATE public.marketplace_leads SET contato_liberado = true, status = 'ganho' WHERE id = (s->>'lead_xb')::uuid; GET DIAGNOSTICS n = ROW_COUNT; IF n > 0 THEN falhas := array_append(falhas, 'lead alterado pela empresa'); END IF; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  RESET ROLE;
  PERFORM set_config('app.qa_modo', 'on', true);
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.passo_ordem := 3; r.passo_acao := 'Reler os valores como o dono do banco'; r.esperado := 'tudo como antes';
  SELECT nota_geral INTO v_nota FROM public.marketplace_avaliacoes WHERE id = (s->>'aval_a')::uuid;
  SELECT texto INTO v_texto FROM public.marketplace_lead_mensagens WHERE id = (s->>'msg_ya')::uuid;
  SELECT status::text, contato_liberado INTO v_status, v_lib FROM public.marketplace_leads WHERE id = (s->>'lead_xb')::uuid;
  SELECT nivel INTO v_nivel FROM public.marketplace_reputacao WHERE profissional_id = (s->>'a_prof')::uuid;
  SELECT count(*) INTO n FROM public.marketplace_consentimentos WHERE profissional_id = (s->>'a_prof')::uuid;
  IF v_nota = 5 OR v_texto = 'invadido' OR v_status = 'ganho' OR v_lib OR v_nivel = 'top' OR n <> v_cons THEN
    falhas := array_append(falhas, format('valor mudou (nota %s, texto %s, status %s, liberado %s, nível %s, consentimentos %s/%s)', v_nota, v_texto, v_status, v_lib, v_nivel, n, v_cons));
  END IF;
  IF array_length(falhas, 1) IS NULL THEN
    r.situacao := 'passou'; r.obtido := 'Toda escrita direta onde o papel só lê foi negada ou afetou 0 linhas, e nada mudou: avaliação, mensagem, consentimento, reputação e lead intactos.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; ');
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE; PERFORM set_config('app.qa_modo', 'on', true); PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-114 — superfície de EXECUTE: anon só nas públicas; internas só service_role; anon barrado nas sensíveis
CREATE OR REPLACE FUNCTION public.qa_caso_mky_114()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_claims text; falhas text[] := '{}'; v text; v_msg text; f text;
BEGIN
  v_claims := current_setting('request.jwt.claims', true);
  r.passo_ordem := 1; r.passo_acao := 'Funções marketye_* executáveis por anon'; r.esperado := 'só marketye_vitrine_publica, marketye_vagas_demanda e marketye_meu_id (devolve nulo sem sessão; as políticas a chamam)';
  SELECT string_agg(p.proname, ', ' ORDER BY p.proname) INTO v FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname LIKE 'marketye_%' AND has_function_privilege('anon', p.oid, 'EXECUTE')
    AND p.proname NOT IN ('marketye_vitrine_publica', 'marketye_vagas_demanda', 'marketye_meu_id');
  IF v IS NOT NULL THEN falhas := array_append(falhas, 'anon executa: ' || v); END IF;
  SELECT string_agg(p.proname, ', ') INTO v FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname IN ('marketye_vitrine_publica', 'marketye_vagas_demanda') AND NOT has_function_privilege('anon', p.oid, 'EXECUTE');
  IF v IS NOT NULL THEN falhas := array_append(falhas, 'controle: a página pública precisa de anon em ' || v); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Funções internas executáveis por authenticated ou anon'; r.esperado := 'nenhuma (só service_role)';
  SELECT string_agg(p.proname, ', ') INTO v FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname IN ('marketye_buscar_interno', 'marketye_cadastrar_especialista_para', 'marketye_recalcular_reputacao', 'marketye_semear_ilha_teste')
    AND (has_function_privilege('anon', p.oid, 'EXECUTE') OR has_function_privilege('authenticated', p.oid, 'EXECUTE'));
  IF v IS NOT NULL THEN falhas := array_append(falhas, 'interna exposta: ' || v); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Como anon: chamar moderação, ajustes, painel e busca'; r.esperado := 'recusado antes de qualquer efeito';
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  SET LOCAL ROLE anon;
  FOREACH f IN ARRAY ARRAY['SELECT public.marketye_moderar_especialista(gen_random_uuid(), ''aprovado'', NULL, true)',
                           'SELECT public.marketye_config_salvar(''relevancia_pesos'', ''{}''::jsonb, NULL)',
                           'SELECT public.marketye_painel_liquidez()',
                           'SELECT public.marketye_buscar(''{}''::jsonb)',
                           'SELECT public.marketye_moderacao_fila()'] LOOP
    BEGIN
      EXECUTE f;
      falhas := array_append(falhas, 'anon executou sem barreira: ' || f);
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    WHEN OTHERS THEN falhas := array_append(falhas, 'anon chegou a rodar a função (erro interno, não de permissão): ' || left(f, 60) || ' -> ' || SQLERRM);
    END;
  END LOOP;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF array_length(falhas, 1) IS NULL THEN
    r.situacao := 'passou'; r.obtido := 'anon só executa a vitrine pública, as vagas de demanda e a consulta do próprio id; internas só service_role; moderação, ajustes, painel, fila e busca recusam o visitante por permissão.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; ');
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE; PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-115 — entrada hostil vira texto; busca não quebra com curingas e aspas
CREATE OR REPLACE FUNCTION public.qa_caso_mky_115()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; e record; v_claims text; falhas text[] := '{}'; v_t uuid := public.qa_sandbox_tenant_id(); v_u uuid; v_nome text; v_desc text; v_an uuid; q text; v jsonb;
        v_hostil text := 'Robert''); DROP TABLE marketplace_leads;--';
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  v_u := public.qa_mky_usuario_empresa(v_t, '115');
  SELECT * INTO e FROM public.qa_mky_especialista('115', '900.000.030-00');
  r.passo_ordem := 1; r.passo_acao := 'Salvar nome com injeção SQL e apresentação com HTML'; r.esperado := 'gravados como texto; tabela intacta';
  PERFORM public.qa_mky_claims(e.uid);
  PERFORM public.marketye_meu_perfil_salvar(jsonb_build_object('nome_completo', v_hostil, 'bio', '<script>alert(1)</script> apresentação de teste'));
  SELECT nome_completo, bio INTO v_nome, v_desc FROM public.marketplace_profissionais WHERE id = e.prof_id;
  IF v_nome <> v_hostil THEN falhas := array_append(falhas, 'nome não ficou literal: ' || COALESCE(v_nome, 'NULL')); END IF;
  IF v_desc NOT LIKE '<script>%' THEN falhas := array_append(falhas, 'apresentação não ficou literal'); END IF;
  IF to_regclass('public.marketplace_leads') IS NULL THEN falhas := array_append(falhas, 'tabela marketplace_leads sumiu'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Salvar anúncio com HTML na descrição'; r.esperado := 'texto literal';
  v := public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Anuncio 115', 'descricao', '<img src=x onerror=alert(1)> descrição fictícia de teste', 'modalidade', 'online', 'tipo_preco', 'sob_orcamento'));
  v_an := (v->>'id')::uuid;
  SELECT descricao INTO v_desc FROM public.marketplace_servicos WHERE id = v_an;
  IF v_desc NOT LIKE '<img src=x onerror=alert(1)>%' THEN falhas := array_append(falhas, 'descrição do anúncio não ficou literal'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Buscar com curingas, aspas e barra'; r.esperado := 'sem erro';
  PERFORM public.qa_mky_claims(v_u);
  FOREACH q IN ARRAY ARRAY['%', '_', '''', '\', '"; DROP TABLE marketplace_leads;--', '%%%', '\%'] LOOP
    BEGIN
      v := public.marketye_buscar(jsonb_build_object('q', q, 'ignorar_uf_padrao', true));
    EXCEPTION WHEN OTHERS THEN falhas := array_append(falhas, 'busca quebrou com ' || quote_literal(q) || ': ' || SQLERRM); END;
  END LOOP;
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF array_length(falhas, 1) IS NULL THEN
    r.situacao := 'passou'; r.obtido := 'Injeção e HTML ficaram como texto, a tabela continua, e a busca aceitou curingas, aspas e barra sem erro.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; ');
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-116 — escrita direta nas tabelas expostas por usuário autenticado é recusada
CREATE OR REPLACE FUNCTION public.qa_caso_mky_116()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; n int; v_sql text; v_msg text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  PERFORM set_config('app.qa_modo', 'off', true);
  r.passo_ordem := 1; r.passo_acao := 'Como usuário de X: INSERT direto em leads, mensagens, avaliações, demanda latente e configuração'; r.esperado := 'recusado pelo RLS (42501) em todos';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  SET LOCAL ROLE authenticated;
  FOREACH v_sql IN ARRAY ARRAY[
    format('INSERT INTO public.marketplace_leads (tenant_id, profissional_id, servico_id, criado_por) VALUES (%L, %L, %L, %L)', s->>'t1', s->>'b_prof', s->>'b_pub', s->>'x'),
    format('INSERT INTO public.marketplace_lead_mensagens (lead_id, autor_tipo, autor_id, texto) VALUES (%L, ''cliente'', %L, ''me liga no 46 99999-0000'')', s->>'lead_xb', s->>'x'),
    format('INSERT INTO public.marketplace_avaliacoes (profissional_id, tenant_id, lead_id, direcao, nota_geral, avaliador_id) VALUES (%L, %L, %L, ''cliente_para_especialista'', 5, %L)', s->>'b_prof', s->>'t1', s->>'lead_xb', s->>'x'),
    format('INSERT INTO public.marketplace_demanda_latente (tenant_id, uf, termos, resultados) VALUES (%L, ''QA'', ''x'', 0)', s->>'t1'),
    'INSERT INTO public.marketplace_config (chave, versao, valor, vigente) VALUES (''relevancia_pesos'', 999, ''{}''::jsonb, true)'
  ] LOOP
    BEGIN
      EXECUTE v_sql;
      falhas := array_append(falhas, 'aceito: ' || left(v_sql, 70));
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    WHEN OTHERS THEN falhas := array_append(falhas, 'passou pelo RLS e caiu em outra barreira (' || SQLSTATE || '): ' || left(v_sql, 60));
    END;
  END LOOP;
  BEGIN UPDATE public.marketplace_config SET valor = '{}'::jsonb WHERE vigente; GET DIAGNOSTICS n = ROW_COUNT; IF n > 0 THEN falhas := array_append(falhas, 'UPDATE em marketplace_config alterou linhas'); END IF; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  -- Controle positivo: a mesma pessoa escreve pela porta certa.
  BEGIN PERFORM public.marketye_lead_mensagem((s->>'lead_xb')::uuid, 'Mensagem pela função, permitida.'); EXCEPTION WHEN OTHERS THEN falhas := array_append(falhas, 'controle: a função de mensagem falhou: ' || SQLERRM); END;
  RESET ROLE;
  r.passo_ordem := 2; r.passo_acao := 'Como especialista A: INSERT direto em reputação, destaques, consentimentos, contestações e ocorrências'; r.esperado := 'recusado pelo RLS (42501) em todos';
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  SET LOCAL ROLE authenticated;
  FOREACH v_sql IN ARRAY ARRAY[
    format('INSERT INTO public.marketplace_reputacao (profissional_id, nivel) VALUES (%L, ''top'')', gen_random_uuid()),
    format('INSERT INTO public.marketplace_destaques (profissional_id, tipo, inicio, fim, ativo) VALUES (%L, ''topo'', CURRENT_DATE, CURRENT_DATE + 30, true)', s->>'a_prof'),
    format('INSERT INTO public.marketplace_consentimentos (profissional_id, tipo, versao) VALUES (%L, ''termos_especialista'', ''falsa'')', s->>'a_prof'),
    format('INSERT INTO public.marketplace_contestacoes (profissional_id, decisao_tipo, motivo) VALUES (%L, ''outro'', ''contestação por fora da função'')', s->>'a_prof'),
    format('INSERT INTO public.marketplace_ocorrencias (profissional_id, tipo, descricao) VALUES (%L, ''ocorrencia'', ''apagando o histórico'')', s->>'b_prof')
  ] LOOP
    BEGIN
      EXECUTE v_sql;
      falhas := array_append(falhas, 'aceito: ' || left(v_sql, 70));
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    WHEN OTHERS THEN falhas := array_append(falhas, 'passou pelo RLS e caiu em outra barreira (' || SQLSTATE || '): ' || left(v_sql, 60));
    END;
  END LOOP;
  RESET ROLE;
  PERFORM set_config('app.qa_modo', 'on', true);
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF array_length(falhas, 1) IS NULL THEN
    r.situacao := 'passou'; r.obtido := 'Nenhuma escrita direta passou: leads, mensagens, avaliações, demanda latente, configuração, reputação, destaques, consentimentos, contestações e ocorrências só aceitam a porta das funções.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; ');
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE; PERFORM set_config('app.qa_modo', 'on', true); PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ---------------------------------------------------------------------
-- 6) Registro das rotinas
-- ---------------------------------------------------------------------
INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES
  ('MKY-110', 'qa_caso_mky_110'), ('MKY-111', 'qa_caso_mky_111'), ('MKY-112', 'qa_caso_mky_112'), ('MKY-113', 'qa_caso_mky_113'),
  ('MKY-114', 'qa_caso_mky_114'), ('MKY-115', 'qa_caso_mky_115'), ('MKY-116', 'qa_caso_mky_116')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- ===================================================================
-- CONFERENCIA (o SQL Editor mostra so o ultimo resultado)
-- ===================================================================
SELECT
  to_regprocedure('public.marketye_meu_id()')            IS NOT NULL AS meu_id_ok,
  to_regprocedure('public.marketye_semear_ilha_teste()') IS NOT NULL AS semear_ok,
  (SELECT count(*) FROM pg_proc p
     JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname LIKE 'marketye\_%')       AS marketye_fns,
  (SELECT count(*) FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name LIKE 'marketplace\_%') AS marketplace_tabelas;
