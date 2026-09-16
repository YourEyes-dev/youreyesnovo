-- ============================================================================
-- Fase 4 (motores) — Marketplace: leva final (moderação, visibilidade,
-- isolamento e devido processo). Correções guiadas pelo `obtido` do staging.
--
-- MKY-042: denúncia procedente REMOVE o anúncio (takedown) e registra ocorrência
--          com reflexo na visibilidade.
-- MKY-046: automação só SINALIZA — registro vencido vira flag (registro_vencido),
--          nunca muda status sozinho (sem job/gatilho/função que bloqueie).
-- MKY-068: a vitrine pública conta só anúncios de especialistas ATIVOS.
-- MKY-071: outro especialista (mesmo no cercado) não vira "cliente" de conversa
--          alheia — só o dono da conversa ou usuário comum da empresa.
-- MKY-092: excluir o perfil ENCERRA as conversas abertas com aviso de sistema.
-- MKY-121: ação de origem MarketYE exige validação de eficácia para concluir.
-- ============================================================================

-- ── MKY-042: takedown na denúncia procedente ────────────────────────────────
CREATE OR REPLACE FUNCTION public.marketye_denuncia_decidir(p_id uuid, p_status text, p_acao text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $mkyfn$
DECLARE d record;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  IF p_status NOT IN ('em_analise', 'procedente', 'improcedente', 'resolvida') THEN RAISE EXCEPTION 'Situação inválida'; END IF;
  UPDATE public.marketplace_denuncias SET status = p_status, acao_tomada = COALESCE(p_acao, acao_tomada), analisado_por = auth.uid(), analisado_em = now()
  WHERE id = p_id RETURNING * INTO d;
  IF d.id IS NULL THEN RAISE EXCEPTION 'Denúncia não encontrada'; END IF;
  IF p_status = 'procedente' THEN
    INSERT INTO public.marketplace_ocorrencias (profissional_id, tipo, descricao, origem_tipo, origem_id, registrado_por, reflexo_visibilidade)
    VALUES (d.profissional_id, d.tipo, COALESCE(p_acao, d.descricao), 'denuncia', d.id, auth.uid(), true);
    -- Takedown: os anúncios publicados do denunciado saem da vitrine.
    UPDATE public.marketplace_servicos SET status = 'removido', ativo = false
     WHERE profissional_id = d.profissional_id AND status = 'publicado';
    PERFORM public.marketye_recalcular_reputacao(d.profissional_id);
  END IF;
  RETURN jsonb_build_object('id', p_id, 'status', p_status);
END $mkyfn$;

-- ── MKY-046: automação só sinaliza (registro vencido = flag, não status) ─────
ALTER TABLE public.marketplace_profissionais
  ADD COLUMN IF NOT EXISTS registro_vencido boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.marketplace_profissionais.registro_vencido IS
  'MKY-046: sinaliza registro profissional vencido (fila de revisão humana) — nunca bloqueia sozinho.';

CREATE OR REPLACE FUNCTION public.verificar_registro_profissional()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $mkyfn$
BEGIN
  -- Devido processo (NR/devido processo): a automação apenas SINALIZA; a
  -- suspensão/bloqueio é decisão humana (superadmin). Aqui só marca o sinal.
  NEW.registro_vencido := (NEW.registro_validade IS NOT NULL AND NEW.registro_validade < CURRENT_DATE);
  RETURN NEW;
END $mkyfn$;

CREATE OR REPLACE FUNCTION public.bloquear_profissionais_expirados()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $mkyfn$
BEGIN
  -- Só SINALIZA (registro_vencido). A decisão de bloquear é do superadmin, na
  -- fila de moderação — nada muda de status sozinho.
  UPDATE public.marketplace_profissionais
     SET registro_vencido = true
   WHERE registro_validade < CURRENT_DATE
     AND registro_vencido IS DISTINCT FROM true;
END $mkyfn$;

-- ── MKY-068: vitrine pública conta só anúncios de especialistas ativos ──────
CREATE OR REPLACE FUNCTION public.marketye_vitrine_publica()
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $mkyfn$
  SELECT jsonb_build_object(
    'empresas_faixa', (SELECT CASE WHEN n >= 100 THEN (floor(n / 100.0) * 100)::int::text || '+' ELSE 'dezenas de' END FROM (SELECT count(*) AS n FROM public.tenants WHERE ativo) t),
    'especialistas_ativos', (SELECT count(*) FROM public.marketplace_profissionais WHERE status = 'ativo' AND excluido_em IS NULL),
    'anuncios_publicados', (SELECT count(*) FROM public.marketplace_servicos s
                              WHERE s.status = 'publicado' AND s.ativo
                                AND EXISTS (SELECT 1 FROM public.marketplace_profissionais p
                                             WHERE p.id = s.profissional_id AND p.status = 'ativo' AND p.excluido_em IS NULL)),
    'categorias', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.nome, 'slug', c.slug, 'icone', c.icone, 'obrigacao_legal', to_jsonb(c.obrigacao_legal),
                                    'filhas', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', s.id, 'nome', s.nome, 'slug', s.slug, 'obrigacao_legal', to_jsonb(s.obrigacao_legal), 'exige_registro', s.exige_registro) ORDER BY s.ordem), '[]'::jsonb)
                                               FROM public.marketplace_categorias s WHERE s.pai_id = c.id AND s.ativo)) ORDER BY c.ordem), '[]'::jsonb)
                   FROM public.marketplace_categorias c WHERE c.pai_id IS NULL AND c.ativo),
    'vagas_demanda', public.marketye_vagas_demanda(NULL),
    'termos_versoes', public.marketye_config('termos_versoes'));
$mkyfn$;

-- ── MKY-071: especialista de terceiro não vira "cliente" de conversa alheia ─
CREATE OR REPLACE FUNCTION public.marketye_lead_papel(p_lead_id uuid)
RETURNS text
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $mkyfn$
DECLARE l record;
BEGIN
  SELECT tenant_id, profissional_id, criado_por INTO l FROM public.marketplace_leads WHERE id = p_lead_id;
  IF l.tenant_id IS NULL THEN RETURN NULL; END IF;
  IF l.profissional_id = public.marketye_meu_id() THEN RETURN 'especialista'; END IF;
  -- Um especialista registrado que NÃO é o profissional do lead não recebe o
  -- papel de cliente pela simples partilha de tenant (isolamento da conversa);
  -- só o criador da conversa ou um usuário comum da empresa é 'cliente'.
  IF l.tenant_id = public.get_user_tenant_id()
     AND (public.marketye_meu_id() IS NULL OR l.criado_por = auth.uid()) THEN
    RETURN 'cliente';
  END IF;
  IF public.is_superadmin(auth.uid()) THEN RETURN 'moderador'; END IF;
  RETURN NULL;
END $mkyfn$;

-- ── MKY-071 (raiz): as travas de papel FALHAVAM ABERTAS com papel NULL ──────
-- `papel <> 'cliente'` e `papel NOT IN (...)` avaliam para NULL (não TRUE)
-- quando o papel é NULL — o RAISE não dispara e o terceiro passa. Aqui as
-- travas passam a recusar NULL explicitamente (IS DISTINCT FROM / COALESCE).
CREATE OR REPLACE FUNCTION public.marketye_lead_liberar_contato(p_lead_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $mkyfn$
BEGIN
  IF public.marketye_lead_papel(p_lead_id) IS DISTINCT FROM 'cliente' THEN RAISE EXCEPTION 'Só a empresa cliente libera o contato'; END IF;
  UPDATE public.marketplace_leads SET contato_liberado = true, contato_liberado_em = COALESCE(contato_liberado_em, now()),
    status = CASE WHEN status IN ('novo', 'respondido') THEN 'qualificado' ELSE status END, ultima_mensagem_em = now() WHERE id = p_lead_id;
  INSERT INTO public.marketplace_lead_mensagens (lead_id, autor_tipo, texto)
  VALUES (p_lead_id, 'sistema', 'A empresa liberou o contato direto. Combinem os detalhes e, ao fechar, marquem "serviço combinado" para habilitar a avaliação.');
  RETURN jsonb_build_object('id', p_lead_id, 'contato_liberado', true);
END $mkyfn$;

CREATE OR REPLACE FUNCTION public.marketye_lead_status(p_lead_id uuid, p_status text, p_motivo text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $mkyfn$
DECLARE v_papel text := public.marketye_lead_papel(p_lead_id); v_prof uuid;
BEGIN
  IF COALESCE(v_papel, '') NOT IN ('cliente', 'especialista') THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  IF p_status NOT IN ('ganho', 'perdido', 'encerrado') THEN RAISE EXCEPTION 'Situação inválida'; END IF;
  UPDATE public.marketplace_leads SET
    status = p_status,
    ganho_em = CASE WHEN p_status = 'ganho' THEN COALESCE(ganho_em, now()) ELSE ganho_em END,
    contato_liberado = CASE WHEN p_status = 'ganho' THEN true ELSE contato_liberado END,
    primeira_resposta_em = CASE WHEN v_papel = 'especialista' THEN COALESCE(primeira_resposta_em, now()) ELSE primeira_resposta_em END,
    ultima_mensagem_em = now()
  WHERE id = p_lead_id RETURNING profissional_id INTO v_prof;
  INSERT INTO public.marketplace_lead_mensagens (lead_id, autor_tipo, autor_id, texto)
  VALUES (p_lead_id, 'sistema', auth.uid(),
          CASE p_status
            WHEN 'ganho' THEN 'Serviço combinado. Os dois lados já podem avaliar.'
            WHEN 'perdido' THEN CASE WHEN v_papel = 'especialista'
                                     THEN 'O especialista não pôde atender e encerrou esta conversa.'
                                     ELSE 'A empresa encerrou esta conversa sem contratar.' END
            ELSE COALESCE('Conversa encerrada. ' || p_motivo, 'Conversa encerrada.') END);
  IF p_status IN ('ganho', 'perdido', 'encerrado') THEN PERFORM public.marketye_recalcular_reputacao(v_prof); END IF;
  RETURN jsonb_build_object('id', p_lead_id, 'status', p_status);
END $mkyfn$;

CREATE OR REPLACE FUNCTION public.marketye_lead_mensagem(p_lead_id uuid, p_texto text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $mkyfn$
DECLARE v_papel text := public.marketye_lead_papel(p_lead_id); l record; v_texto text; v_mascarar boolean; v_id uuid;
BEGIN
  IF COALESCE(v_papel, '') NOT IN ('cliente', 'especialista') THEN RAISE EXCEPTION 'Acesso negado'; END IF;
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
END $mkyfn$;

CREATE OR REPLACE FUNCTION public.marketye_lead_vincular_documento(p_lead_id uuid, p_documento_id uuid, p_tipo text DEFAULT 'proposta'::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $mkyfn$
DECLARE v_id uuid;
BEGIN
  IF public.marketye_lead_papel(p_lead_id) IS DISTINCT FROM 'cliente' THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  INSERT INTO public.marketplace_lead_documentos (lead_id, documento_id, tipo) VALUES (p_lead_id, p_documento_id, COALESCE(p_tipo, 'proposta')) RETURNING id INTO v_id;
  INSERT INTO public.marketplace_lead_mensagens (lead_id, autor_tipo, autor_id, texto) VALUES (p_lead_id, 'sistema', auth.uid(), 'Documento arquivado no módulo Documentos e vinculado a esta conversa.');
  RETURN jsonb_build_object('id', v_id);
END $mkyfn$;

-- ── MKY-092: excluir perfil encerra as conversas abertas ────────────────────
CREATE OR REPLACE FUNCTION public.marketye_excluir_meu_perfil(p_confirmacao text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $mkyfn$
DECLARE v_id uuid := public.marketye_meu_id();
BEGIN
  IF v_id IS NULL THEN RAISE EXCEPTION 'Sem cadastro de especialista'; END IF;
  IF COALESCE(p_confirmacao, '') <> 'EXCLUIR' THEN RAISE EXCEPTION 'Digite EXCLUIR para confirmar'; END IF;

  -- Encerra as conversas abertas com aviso de sistema (o especialista saiu).
  INSERT INTO public.marketplace_lead_mensagens (lead_id, autor_tipo, texto)
    SELECT id, 'sistema', 'O especialista deixou o MarketYE; esta conversa foi encerrada.'
      FROM public.marketplace_leads
     WHERE profissional_id = v_id AND status NOT IN ('ganho', 'perdido', 'encerrado');
  UPDATE public.marketplace_leads SET status = 'encerrado', ultima_mensagem_em = now()
   WHERE profissional_id = v_id AND status NOT IN ('ganho', 'perdido', 'encerrado');

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
END $mkyfn$;

-- ── MKY-121: ação de origem MarketYE exige validação de eficácia ────────────
ALTER TABLE public.plano_acoes
  ADD COLUMN IF NOT EXISTS eficacia_validada_em date;
ALTER TABLE public.plano_acoes
  ADD COLUMN IF NOT EXISTS eficacia_validada_por text;
COMMENT ON COLUMN public.plano_acoes.eficacia_validada_em IS
  'MKY-121: validacao de eficacia (data) exigida para concluir acao de origem marketplace.';

CREATE OR REPLACE FUNCTION public.plano_acao_marketplace_exige_eficacia()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $mkyfn$
BEGIN
  IF NEW.status::text = 'concluida'
     AND COALESCE(OLD.status::text, '') <> 'concluida'
     AND NEW.origem_modulo = 'marketplace'
     AND NEW.eficacia_validada_em IS NULL THEN
    RAISE EXCEPTION 'Acao de origem MarketYE exige validacao de eficacia (data e responsavel) antes de concluir.'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $mkyfn$;

DROP TRIGGER IF EXISTS trg_plano_acao_marketplace_eficacia ON public.plano_acoes;
CREATE TRIGGER trg_plano_acao_marketplace_eficacia
  BEFORE UPDATE OF status ON public.plano_acoes
  FOR EACH ROW EXECUTE FUNCTION public.plano_acao_marketplace_exige_eficacia();
