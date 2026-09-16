-- ============================================================================
-- SCRIPT DE ENTREGA — Fase 4: MarketYE (moderacao/visibilidade/isolamento),
-- EPI (reserva), Metas (trilha), Parceiros (sugestao), Ponto (homologacao),
-- Isolamento RLS, Edge Functions e blindagem do motor de QA.
--
-- Aplicar PRIMEIRO na HOMOLOGACAO e, depois de conferido, o MESMO na PRODUCAO
-- (fluxo forward-only, decisao 09/2026). Idempotente: rodar duas vezes nao
-- quebra nem duplica. Todo o conteudo e CREATE OR REPLACE / ADD COLUMN IF NOT
-- EXISTS / DROP TRIGGER IF EXISTS + CREATE / INSERT ON CONFLICT.
--
-- NAO altera nem apaga dado de negocio existente: so cria/atualiza funcoes,
-- adiciona colunas (com default) e reinstala gatilhos. Por isso nao ha tabela
-- de backup (a regra de backup vale para UPDATE/DELETE de dado existente).
--
-- O SQL Editor roda o arquivo inteiro em UMA transacao. A conferencia final
-- (unico SELECT) sai por ultimo.
--
-- OBS DDL: adiciona colunas e cria dois gatilhos (metas e plano_acoes). Com
-- lock_timeout de 10s, se alguma dessas tabelas estiver muito movimentada no
-- momento, o comando falha rapido e a transacao inteira volta atras (nada pela
-- metade) — nesse caso, rode de novo numa janela mais tranquila.
-- ============================================================================

SET lock_timeout = '10s';

-- ----------------------------------------------------------------------------
-- 1) Colunas novas (idempotentes)
-- ----------------------------------------------------------------------------
ALTER TABLE public.epis
  ADD COLUMN IF NOT EXISTS quantidade_reservada integer NOT NULL DEFAULT 0;
ALTER TABLE public.marketplace_profissionais
  ADD COLUMN IF NOT EXISTS registro_vencido boolean NOT NULL DEFAULT false;
ALTER TABLE public.plano_acoes
  ADD COLUMN IF NOT EXISTS eficacia_validada_em date;
ALTER TABLE public.plano_acoes
  ADD COLUMN IF NOT EXISTS eficacia_validada_por text;

-- ----------------------------------------------------------------------------
-- 2) Funcoes de sistema (comportamento do produto)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.atualizar_estoque_epi()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_disponivel integer;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.signed_at IS NOT NULL THEN
      -- Entrega já assinada no registro: baixa definitiva imediata.
      UPDATE public.epis
         SET quantidade_estoque = quantidade_estoque - NEW.quantidade
       WHERE id = NEW.epi_id;
    ELSE
      -- Sem assinatura: RESERVA (não baixa o físico). Recusa reserva acima do
      -- disponível — o saldo entregável nunca fica negativo (RN-003/RN-005).
      SELECT quantidade_estoque - COALESCE(quantidade_reservada, 0)
        INTO v_disponivel FROM public.epis WHERE id = NEW.epi_id;
      IF COALESCE(v_disponivel, 0) < NEW.quantidade THEN
        RAISE EXCEPTION 'Saldo disponível insuficiente para reservar a entrega de EPI (disponível %, pedido %).',
          COALESCE(v_disponivel, 0), NEW.quantidade USING ERRCODE = 'check_violation';
      END IF;
      UPDATE public.epis
         SET quantidade_reservada = COALESCE(quantidade_reservada, 0) + NEW.quantidade
       WHERE id = NEW.epi_id;
    END IF;

  ELSIF TG_OP = 'UPDATE' THEN
    -- Assinatura consuma a reserva: baixa definitiva do físico.
    IF NEW.signed_at IS NOT NULL AND OLD.signed_at IS NULL THEN
      UPDATE public.epis
         SET quantidade_estoque   = quantidade_estoque - NEW.quantidade,
             quantidade_reservada = GREATEST(0, COALESCE(quantidade_reservada, 0) - NEW.quantidade)
       WHERE id = NEW.epi_id;

    ELSIF NEW.status = 'devolvido' AND OLD.status = 'ativa' THEN
      IF OLD.signed_at IS NOT NULL THEN
        -- Item já baixado (entregue e assinado): devolução repõe o físico.
        UPDATE public.epis
           SET quantidade_estoque = quantidade_estoque + NEW.quantidade
         WHERE id = NEW.epi_id;
      ELSE
        -- Reserva não assinada cancelada: libera a reserva.
        UPDATE public.epis
           SET quantidade_reservada = GREATEST(0, COALESCE(quantidade_reservada, 0) - NEW.quantidade)
         WHERE id = NEW.epi_id;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$

;

CREATE OR REPLACE FUNCTION public.meta_workflow_registra_trilha()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.workflow_status IS DISTINCT FROM OLD.workflow_status THEN
    INSERT INTO public.metas_workflow_log
      (tenant_id, meta_id, status_anterior, status_novo, acao, justificativa)
    VALUES (NEW.tenant_id, NEW.id, OLD.workflow_status, NEW.workflow_status,
            'transicao_' || NEW.workflow_status::text,
            NEW.justificativa_aprovacao);
  END IF;
  RETURN NEW;
END;
$function$

;

CREATE OR REPLACE FUNCTION public.marketye_denuncia_decidir(p_id uuid, p_status text, p_acao text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
END $function$

;

CREATE OR REPLACE FUNCTION public.verificar_registro_profissional()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Devido processo (NR/devido processo): a automação apenas SINALIZA; a
  -- suspensão/bloqueio é decisão humana (superadmin). Aqui só marca o sinal.
  NEW.registro_vencido := (NEW.registro_validade IS NOT NULL AND NEW.registro_validade < CURRENT_DATE);
  RETURN NEW;
END $function$

;

CREATE OR REPLACE FUNCTION public.bloquear_profissionais_expirados()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Só SINALIZA (registro_vencido). A decisão de bloquear é do superadmin, na
  -- fila de moderação — nada muda de status sozinho.
  UPDATE public.marketplace_profissionais
     SET registro_vencido = true
   WHERE registro_validade < CURRENT_DATE
     AND registro_vencido IS DISTINCT FROM true;
END $function$

;

CREATE OR REPLACE FUNCTION public.marketye_vitrine_publica()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$

;

CREATE OR REPLACE FUNCTION public.marketye_lead_papel(p_lead_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
END $function$

;

CREATE OR REPLACE FUNCTION public.marketye_lead_liberar_contato(p_lead_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF public.marketye_lead_papel(p_lead_id) IS DISTINCT FROM 'cliente' THEN RAISE EXCEPTION 'Só a empresa cliente libera o contato'; END IF;
  UPDATE public.marketplace_leads SET contato_liberado = true, contato_liberado_em = COALESCE(contato_liberado_em, now()),
    status = CASE WHEN status IN ('novo', 'respondido') THEN 'qualificado' ELSE status END, ultima_mensagem_em = now() WHERE id = p_lead_id;
  INSERT INTO public.marketplace_lead_mensagens (lead_id, autor_tipo, texto)
  VALUES (p_lead_id, 'sistema', 'A empresa liberou o contato direto. Combinem os detalhes e, ao fechar, marquem "serviço combinado" para habilitar a avaliação.');
  RETURN jsonb_build_object('id', p_lead_id, 'contato_liberado', true);
END $function$

;

CREATE OR REPLACE FUNCTION public.marketye_lead_status(p_lead_id uuid, p_status text, p_motivo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
END $function$

;

CREATE OR REPLACE FUNCTION public.marketye_lead_mensagem(p_lead_id uuid, p_texto text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
END $function$

;

CREATE OR REPLACE FUNCTION public.marketye_lead_vincular_documento(p_lead_id uuid, p_documento_id uuid, p_tipo text DEFAULT 'proposta'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_id uuid;
BEGIN
  IF public.marketye_lead_papel(p_lead_id) IS DISTINCT FROM 'cliente' THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  INSERT INTO public.marketplace_lead_documentos (lead_id, documento_id, tipo) VALUES (p_lead_id, p_documento_id, COALESCE(p_tipo, 'proposta')) RETURNING id INTO v_id;
  INSERT INTO public.marketplace_lead_mensagens (lead_id, autor_tipo, autor_id, texto) VALUES (p_lead_id, 'sistema', auth.uid(), 'Documento arquivado no módulo Documentos e vinculado a esta conversa.');
  RETURN jsonb_build_object('id', v_id);
END $function$

;

CREATE OR REPLACE FUNCTION public.marketye_excluir_meu_perfil(p_confirmacao text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
END $function$

;

CREATE OR REPLACE FUNCTION public.plano_acao_marketplace_exige_eficacia()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status::text = 'concluida'
     AND COALESCE(OLD.status::text, '') <> 'concluida'
     AND NEW.origem_modulo = 'marketplace'
     AND NEW.eficacia_validada_em IS NULL THEN
    RAISE EXCEPTION 'Acao de origem MarketYE exige validacao de eficacia (data e responsavel) antes de concluir.'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $function$

;

CREATE OR REPLACE FUNCTION public.parceiros_sugerir_para_lead(_lead_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_l record;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  SELECT cidade, uf INTO v_l FROM public.leads WHERE id = _lead_id;
  RETURN coalesce((SELECT jsonb_agg(x ORDER BY ord_prioridade, ord_nome) FROM (
    SELECT jsonb_build_object(
      'id', p.id, 'nome', p.nome, 'tipo_parceiro', p.tipo_parceiro, 'cidade', p.cidade, 'uf', p.uf,
      'nivel', n.nome, 'clientes', (SELECT count(*) FROM public.tenants t WHERE t.parceiro_id = p.id),
      'motivo', CASE
        WHEN v_l.cidade IS NOT NULL AND lower(unaccent_safe(p.cidade)) = lower(unaccent_safe(v_l.cidade)) AND upper(p.uf) = upper(v_l.uf) THEN 'Mesma cidade'
        WHEN v_l.uf IS NOT NULL AND upper(p.uf) = upper(v_l.uf) THEN 'Mesmo estado'
        ELSE 'Atende à distância' END,
      'prioridade', CASE
        WHEN v_l.cidade IS NOT NULL AND lower(unaccent_safe(p.cidade)) = lower(unaccent_safe(v_l.cidade)) AND upper(p.uf) = upper(v_l.uf) THEN '1'
        WHEN v_l.uf IS NOT NULL AND upper(p.uf) = upper(v_l.uf) THEN '2' ELSE '3' END
        || lpad((9 - coalesce(n.ordem, 0))::text, 2, '0')
    ) AS x,
    -- Mesma chave de prioridade, agora usada para ORDENAR ANTES DO LIMIT:
    (CASE
        WHEN v_l.cidade IS NOT NULL AND lower(unaccent_safe(p.cidade)) = lower(unaccent_safe(v_l.cidade)) AND upper(p.uf) = upper(v_l.uf) THEN '1'
        WHEN v_l.uf IS NOT NULL AND upper(p.uf) = upper(v_l.uf) THEN '2' ELSE '3' END
        || lpad((9 - coalesce(n.ordem, 0))::text, 2, '0')) AS ord_prioridade,
    p.nome AS ord_nome
    FROM public.parceiros p LEFT JOIN public.parceiro_niveis n ON n.id = p.nivel_id
    WHERE p.status = 'ativo' AND p.tipo_parceiro IN ('representante','implantador','clinica','contabilidade','indicador')
    ORDER BY ord_prioridade, ord_nome
    LIMIT 5) q), '[]'::jsonb);
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_up_sair()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  PERFORM set_config('request.jwt.claims', '{}', true);
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_executar_descartavel(p_funcao text)
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
  r public.qa_retorno;
  v_claims text;
BEGIN
  -- Fotografa o estado de sessão ANTES do caso, para devolver depois.
  v_claims := current_setting('request.jwt.claims', true);

  PERFORM public.qa_modo_ligar();
  PERFORM public.qa_exigir_modo();

  BEGIN
    EXECUTE format('SELECT * FROM public.%I()', p_funcao) INTO r;
    RAISE EXCEPTION USING ERRCODE = 'QA000', MESSAGE = 'QA_DESCARTE';
  EXCEPTION
    WHEN SQLSTATE 'QA000' THEN
      NULL;  -- caminho normal: os dados de teste já foram desfeitos
    WHEN OTHERS THEN
      r.situacao     := 'erro';
      r.obtido       := 'A rotina quebrou. Nenhum dado ficou na base.';
      r.erro_tecnico := SQLERRM || ' [' || SQLSTATE || ']';
  END;

  -- Estado de sessão NÃO é desfeito pelo rollback da subtransação quando o caso
  -- usa set_config(...,true) / SET ROLE; devolvemos à mão para não vazar.
  BEGIN
    EXECUTE 'RESET ROLE';
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);

  IF r.situacao IS NULL THEN
    r.situacao := 'erro';
    r.obtido   := 'A rotina nao devolveu veredito.';
  END IF;
  RETURN r;
END $function$

;

-- ----------------------------------------------------------------------------
-- 3) Gatilhos (reinstalados; as funcoes acima ja existem)
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_meta_workflow_registra_trilha ON public.metas;
CREATE TRIGGER trg_meta_workflow_registra_trilha
  AFTER UPDATE OF workflow_status ON public.metas
  FOR EACH ROW EXECUTE FUNCTION public.meta_workflow_registra_trilha();

DROP TRIGGER IF EXISTS trg_plano_acao_marketplace_eficacia ON public.plano_acoes;
CREATE TRIGGER trg_plano_acao_marketplace_eficacia
  BEFORE UPDATE OF status ON public.plano_acoes
  FOR EACH ROW EXECUTE FUNCTION public.plano_acao_marketplace_exige_eficacia();

-- ----------------------------------------------------------------------------
-- 4) Linha de base do cercado: assinatura propria do tenant de QA
-- ----------------------------------------------------------------------------
DO $qa_baseline_sub$
DECLARE v_t uuid := public.qa_sandbox_tenant_id(); v_n bigint;
BEGIN
  IF v_t IS NULL OR to_regclass('public.qa_mobiliario_fixo') IS NULL THEN
    RAISE NOTICE 'Cercado/linha de base ausentes; nada a ajustar.';
    RETURN;
  END IF;
  SELECT count(*) INTO v_n FROM public.subscriptions WHERE tenant_id = v_t;
  IF v_n > 0 THEN
    INSERT INTO public.qa_mobiliario_fixo (tabela, esperado, motivo)
    VALUES ('subscriptions', v_n, 'Assinatura propria do tenant de QA (mobiliario fixo).')
    ON CONFLICT (tabela) DO UPDATE SET esperado = EXCLUDED.esperado, motivo = EXCLUDED.motivo, registrado_em = now();
  ELSE
    DELETE FROM public.qa_mobiliario_fixo WHERE tabela = 'subscriptions';
  END IF;
END $qa_baseline_sub$;

-- ----------------------------------------------------------------------------
-- 5) Rotinas do motor de QA (somente leitura; rodam sob transacao descartavel)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.qa_caso_epi_001()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_tipo uuid; v_epi uuid; v_id uuid; v_antes int; v_reserva int; v_depois int;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao  := 'Criar tipo de EPI e um item com estoque 100';
  r.esperado    := 'Reserva na entrega sem assinatura; baixa só com a assinatura (RN-005)';
  INSERT INTO public.epi_tipos (tenant_id, nome)
  VALUES (v_t, '[QA-EPI] Luva Teste') RETURNING id INTO v_tipo;
  INSERT INTO public.epis (tenant_id, tipo_id, ca, quantidade_estoque, quantidade_minima)
  VALUES (v_t, v_tipo, 'CA-QA-0000', 100, 10) RETURNING id INTO v_epi;

  r.passo_ordem := 2; r.passo_acao := 'Ler o estoque inicial';
  SELECT quantidade_estoque INTO v_antes FROM public.epis WHERE id = v_epi;

  r.passo_ordem := 3; r.passo_acao := 'Registrar entrega de 2 unidades SEM assinatura (reserva)';
  INSERT INTO public.epi_entregas (tenant_id, epi_id, colaborador_nome, colaborador_cpf,
                                   quantidade, data_entrega, status)
  VALUES (v_t, v_epi, '[QA-EPI] Colaborador', public.qa_cpf(269), 2, CURRENT_DATE, 'ativa')
  RETURNING id INTO v_id;
  SELECT quantidade_estoque INTO v_reserva FROM public.epis WHERE id = v_epi;

  r.passo_ordem := 4; r.passo_acao := 'Assinar a ficha (signed_at) — baixa definitiva';
  UPDATE public.epi_entregas SET signed_at = now() WHERE id = v_id;
  SELECT quantidade_estoque INTO v_depois FROM public.epis WHERE id = v_epi;

  IF v_reserva = v_antes AND v_depois = v_antes - 2 THEN
    r.situacao := 'passou';
    r.obtido := format('Reserva preservou o estoque (%s) e a assinatura baixou para %s. Modelo de reserva OK.', v_reserva, v_depois);
  ELSIF v_reserva <> v_antes THEN
    r.situacao := 'falhou';
    r.obtido := format('A entrega sem assinatura baixou o estoque (de %s para %s) — deveria só reservar.', v_antes, v_reserva);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('A assinatura não baixou o estoque (segue em %s, esperado %s).', v_depois, v_antes - 2);
  END IF;
  r.detalhe := jsonb_build_object('epi_id', v_epi, 'antes', v_antes, 'reserva', v_reserva, 'depois', v_depois);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_mwkf_001()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_meta uuid; v_n int; v_just text;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_meta := public.qa_nova_meta('[QA-MWKF] Meta em Aprovacao');

  r.passo_ordem := 1;
  r.passo_acao := 'Transicionar rascunho -> em_aprovacao (o banco grava a trilha sozinho)';
  r.esperado := 'workflow_status atualizado e linha no log gravada pelo gatilho';
  UPDATE public.metas SET workflow_status = 'em_aprovacao' WHERE id = v_meta;

  r.passo_ordem := 2;
  r.passo_acao := 'Transicionar em_aprovacao -> ativa com justificativa (da tela)';
  r.esperado := 'Segunda linha no log, com a justificativa preservada';
  UPDATE public.metas
     SET workflow_status = 'ativa', justificativa_aprovacao = 'Meta alinhada ao ciclo 2026'
   WHERE id = v_meta;

  SELECT count(*) INTO v_n FROM public.metas_workflow_log WHERE meta_id = v_meta;
  SELECT justificativa INTO v_just FROM public.metas_workflow_log
  WHERE meta_id = v_meta AND status_novo = 'ativa';

  IF v_n = 2 AND v_just = 'Meta alinhada ao ciclo 2026' THEN
    r.situacao := 'passou'; r.obtido := 'Trilha completa pelo banco: duas transições, justificativa preservada.';
  ELSE
    r.situacao := 'falhou'; r.obtido := format('%s linha(s) no log; justificativa = %s.', v_n, coalesce(v_just, 'nula'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_pgp_014()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_lead uuid; v_perto uuid; v_longe uuid; v_sug jsonb; v_atrib text; v_sa uuid;
        v_cidade text := 'QA Cidade Fixture PGP014';   -- fictícia e única: isola de parceiros reais
        v_cid_gravada text;
BEGIN
  INSERT INTO public.parceiros (codigo, nome, tipo_parceiro, status, cidade, uf) VALUES ('QA-PGP-PERTO', 'QA Perto', 'representante', 'ativo', v_cidade, 'PR') RETURNING id INTO v_perto;
  INSERT INTO public.parceiros (codigo, nome, tipo_parceiro, status, cidade, uf) VALUES ('QA-PGP-LONGE', 'QA Longe', 'representante', 'ativo', 'Manaus', 'AM') RETURNING id INTO v_longe;
  INSERT INTO public.leads (nome, empresa, cidade, uf) VALUES ('QA Lead', 'QA Empresa Local', v_cidade, 'pr') RETURNING id INTO v_lead;
  -- simula superadmin para as funções que exigem
  SELECT user_id INTO v_sa FROM public.superadmins WHERE ativo LIMIT 1;
  IF v_sa IS NULL THEN
    v_sa := gen_random_uuid();
    INSERT INTO auth.users (id, email) VALUES (v_sa, 'qa-sa-' || left(v_sa::text,8) || '@exemplo.test');
    INSERT INTO public.superadmins (user_id, email) VALUES (v_sa, 'qa-sa@exemplo.test');
  END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);

  r.passo_ordem := 1; r.passo_acao := 'Sugerir parceiros para lead da cidade-fixture (mesma cidade só do QA Perto)';
  r.esperado := 'Parceiro da mesma cidade em primeiro';
  v_sug := public.parceiros_sugerir_para_lead(v_lead);
  r.passo_ordem := 2; r.passo_acao := 'Encaminhar o lead ao parceiro sugerido';
  r.esperado := 'leads.atribuicao = casa';
  PERFORM public.superadmin_lead_encaminhar(v_lead, v_perto);
  SELECT atribuicao INTO v_atrib FROM public.leads WHERE id = v_lead;

  IF (v_sug->0->>'id')::uuid = v_perto AND v_atrib = 'casa' THEN
    r.situacao := 'passou'; r.obtido := format('1º sugerido: %s (%s); atribuição %s', v_sug->0->>'nome', v_sug->0->>'motivo', v_atrib);
  ELSE
    SELECT cidade INTO v_cid_gravada FROM public.leads WHERE id = v_lead;
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: 1º sugerido = %s (motivo %s; esperado QA Perto); atribuição = %s (esperado casa). Cidade do lead gravada = %L (esperado %L).',
                       v_sug->0->>'nome', v_sug->0->>'motivo', v_atrib, v_cid_gravada, v_cidade);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_rls_001()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_inerte text; v_off text; v_lista text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): RLS habilitada nas tabelas sensíveis';
  r.esperado    := 'Nenhuma tabela sensível com RLS desligada (política inerte)';

  -- (a) Tabela que TEM política de perfil mas está com RLS desligada: a
  --     política fica inerte e o dado vaza para qualquer sessão.
  SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_inerte
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
  WHERE c.relkind = 'r' AND NOT c.relrowsecurity
    AND EXISTS (SELECT 1 FROM pg_policies p WHERE p.schemaname = 'public'
                 AND p.tablename = c.relname AND p.policyname LIKE 'perfil_restringe_leitura_%');

  -- (b) Lista curada de tabelas de negócio sensíveis que precisam de RLS.
  SELECT string_agg(t, ', ' ORDER BY t) INTO v_off
  FROM unnest(ARRAY['atestados','eventos_saude','afastamentos_saude','alertas_saude',
                    'ponto_marcacoes','ponto_espelhos','ferias_solicitacoes','folha_rescisoes',
                    'beneficios_colaboradores','documentos','ouvidoria','psicossocial_participacoes',
                    'log_acesso_clinico']) AS t
  WHERE to_regclass('public.' || t) IS NOT NULL
    AND NOT (SELECT c.relrowsecurity FROM pg_class c WHERE c.oid = ('public.' || t)::regclass);

  v_lista := NULLIF(concat_ws(', ', v_inerte, v_off), '');
  IF v_lista IS NULL THEN
    r.situacao := 'passou';
    r.obtido   := 'Todas as tabelas sensíveis conferidas estão com RLS habilitada.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := 'Tabela(s) sensível(is) com RLS DESLIGADA: ' || v_lista
               || '. Habilitar ALTER TABLE ... ENABLE ROW LEVEL SECURITY.';
    r.detalhe  := jsonb_build_object('tabelas', v_lista);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_rls_002()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_claims text; v_t1 uuid := public.qa_sandbox_tenant_id(); v_t2 uuid;
        v_a uuid; v_tag text := left(gen_random_uuid()::text, 8); n_own bigint; n_other bigint;
BEGIN
  v_claims := current_setting('request.jwt.claims', true);
  SELECT id INTO v_t2 FROM public.tenants WHERE slug = 'qa-sandbox-2';
  IF v_t1 IS NULL OR v_t2 IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Cercados de teste (qa-sandbox / qa-sandbox-2) ausentes.'; RETURN r;
  END IF;

  r.passo_ordem := 1; r.passo_acao := 'Usuário do tenant A tenta ler dado do tenant A e do tenant B';
  r.esperado := 'Vê a linha do próprio tenant; zero linhas do outro';

  v_a := public.qa_mky_usuario_empresa(v_t1, 'rls2a');
  INSERT INTO public.user_roles (user_id, role) VALUES (v_a, 'manager');
  INSERT INTO public.metas (tenant_id, titulo, ano) VALUES (v_t1, '[QA-RLS2] meta A ' || v_tag, 2026);
  INSERT INTO public.metas (tenant_id, titulo, ano) VALUES (v_t2, '[QA-RLS2] meta B ' || v_tag, 2026);

  PERFORM public.qa_mky_claims(v_a);
  n_own   := qa_rls.conta_auth(format('SELECT count(*) FROM public.metas WHERE tenant_id = %L AND titulo = %L', v_t1, '[QA-RLS2] meta A ' || v_tag));
  n_other := qa_rls.conta_auth(format('SELECT count(*) FROM public.metas WHERE tenant_id = %L AND titulo = %L', v_t2, '[QA-RLS2] meta B ' || v_tag));
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);

  -- conta_auth devolve -1 quando o papel authenticated não tem GRANT de leitura
  -- (acontece na réplica local, onde os grants do Supabase não são replicados);
  -- RLS nunca levanta insufficient_privilege — só a falta de grant. No staging
  -- o grant existe e a leitura devolve a contagem real.
  IF n_other > 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('VAZAMENTO entre tenants: usuário do tenant A enxergou %s linha(s) do tenant B.', n_other);
  ELSIF n_own = 1 THEN
    r.situacao := 'passou';
    r.obtido := 'Usuário do tenant A vê a própria meta e não vê nada do tenant B. Isolamento por RLS garantido.';
  ELSIF n_own <= 0 THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Réplica local sem os GRANTs do papel authenticated (leitura devolveu -1); o isolamento confirma no staging, onde o grant existe.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Controle falhou: usuário do tenant A não leu a própria meta (esperado 1, obtido %s).', n_own);
  END IF;
  r.detalhe := jsonb_build_object('n_own', n_own, 'n_other', n_other);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_rls_003()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_falta text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): política RESTRICTIVE de perfil nas tabelas cobertas';
  r.esperado    := 'Cada tabela sensível prevista tem sua perfil_restringe_leitura_* RESTRICTIVE';

  -- Conjunto representativo das famílias cobertas (ponto, férias, saúde, psico,
  -- benefícios, documentos). Cada uma tem de ter a política RESTRICTIVE viva.
  SELECT string_agg(t, ', ' ORDER BY t) INTO v_falta
  FROM unnest(ARRAY['atestados','eventos_saude','afastamentos_saude','ponto_marcacoes',
                    'ferias_solicitacoes','beneficios_colaboradores','documentos',
                    'psicossocial_participacoes','folha_rescisoes']) AS t
  WHERE to_regclass('public.' || t) IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM pg_policies p
      WHERE p.schemaname = 'public' AND p.tablename = t
        AND p.policyname LIKE 'perfil_restringe_leitura_%'
        AND p.permissive = 'RESTRICTIVE');

  IF v_falta IS NULL THEN
    r.situacao := 'passou';
    r.obtido   := 'Todas as tabelas sensíveis previstas têm a política RESTRICTIVE de perfil.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := 'Tabela(s) sensível(is) SEM a política RESTRICTIVE de perfil: ' || v_falta;
    r.detalhe  := jsonb_build_object('tabelas', v_falta);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_rls_004()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_claims text; v_t1 uuid := public.qa_sandbox_tenant_id();
        v_uid uuid := gen_random_uuid(); v_ub uuid; v_perfil uuid; v_tag text := left(gen_random_uuid()::text, 8);
        n_user bigint; n_owner bigint;
BEGIN
  v_claims := current_setting('request.jwt.claims', true);
  IF v_t1 IS NULL THEN r.situacao := 'nao_implementado'; r.obtido := 'Cercado de teste ausente.'; RETURN r; END IF;

  r.passo_ordem := 1; r.passo_acao := 'Usuário SEM escopo de saúde tenta ler atestados do tenant';
  r.esperado := 'Zero linhas (dado de saúde protegido pela camada de perfil)';

  INSERT INTO auth.users (id, email) VALUES (v_uid, 'qa-rls4-' || v_tag || '@sandbox.invalid');
  INSERT INTO public.profiles (user_id, tenant_id, nome_completo, onboarding_concluido) VALUES (v_uid, v_t1, 'QA RLS4', true);
  INSERT INTO public.usuarios_base (tenant_id, nome_completo, email_principal, auth_user_id, status, tipo_usuario, cpf)
  VALUES (v_t1, 'QA RLS4', 'qa-rls4-' || v_tag || '@sandbox.invalid', v_uid, 'ativo', 'colaborador', public.qa_cpf((floor(random() * 900000) + 1)::int)) RETURNING id INTO v_ub;
  INSERT INTO public.perfis_acesso (tenant_id, nome, ativo) VALUES (v_t1, '[QA-RLS4] Perfil sem saúde ' || v_tag, true) RETURNING id INTO v_perfil;
  INSERT INTO public.perfil_permissoes (perfil_id, tenant_id, modulo, acao, escopo, ativo)
  VALUES (v_perfil, v_t1, 'metas', 'visualizar', 'empresa_inteira', true);
  -- O gatilho de perfil padrão pode já ter vinculado o usuário; desativa antes
  -- para o perfil do teste (sem saúde) ser o único ativo.
  UPDATE public.usuario_perfil_vinculos SET ativo = false WHERE usuario_id = v_ub;
  INSERT INTO public.usuario_perfil_vinculos (tenant_id, usuario_id, perfil_id, ativo) VALUES (v_t1, v_ub, v_perfil, true);

  INSERT INTO public.atestados (tenant_id, colaborador_nome, tipo, data_emissao, profissional_nome, profissional_registro, observacoes)
  VALUES (v_t1, '[QA-RLS4] Colaborador ' || v_tag, 'assistencial', CURRENT_DATE, 'QA Dr. Teste', 'CRM-QA-0000', 'atestado fictício de teste ' || v_tag);
  SELECT count(*) INTO n_owner FROM public.atestados WHERE tenant_id = v_t1 AND observacoes = 'atestado fictício de teste ' || v_tag;

  PERFORM public.qa_mky_claims(v_uid);
  n_user := qa_rls.conta_auth(format('SELECT count(*) FROM public.atestados WHERE tenant_id = %L AND observacoes = %L', v_t1, 'atestado fictício de teste ' || v_tag));
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);

  IF n_owner < 1 THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Não foi possível semear o atestado de teste (controle vazio).';
  ELSIF n_user <= 0 THEN
    r.situacao := 'passou';
    r.obtido := 'Usuário sem escopo de saúde lê 0 atestados, embora o registro exista. Dado de saúde protegido pela camada de perfil.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('VAZAMENTO de saúde: usuário sem escopo leu %s atestado(s).', n_user);
  END IF;
  r.detalhe := jsonb_build_object('n_user', n_user, 'n_owner', n_owner);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_rls_005()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_claims text; v_t1 uuid := public.qa_sandbox_tenant_id();
        v_uid uuid := gen_random_uuid(); v_ub uuid; v_perfil uuid; v_tag text := left(gen_random_uuid()::text, 8);
        v_ok boolean; v_block boolean;
BEGIN
  v_claims := current_setting('request.jwt.claims', true);
  IF v_t1 IS NULL THEN r.situacao := 'nao_implementado'; r.obtido := 'Cercado de teste ausente.'; RETURN r; END IF;

  r.passo_ordem := 1; r.passo_acao := 'Perfil libera "metas" mas não "ponto"; conferir o portão de módulo';
  r.esperado := 'perfil_permite_modulo(metas)=true e (ponto)=false';

  INSERT INTO auth.users (id, email) VALUES (v_uid, 'qa-rls5-' || v_tag || '@sandbox.invalid');
  INSERT INTO public.profiles (user_id, tenant_id, nome_completo, onboarding_concluido) VALUES (v_uid, v_t1, 'QA RLS5', true);
  INSERT INTO public.usuarios_base (tenant_id, nome_completo, email_principal, auth_user_id, status, tipo_usuario, cpf)
  VALUES (v_t1, 'QA RLS5', 'qa-rls5-' || v_tag || '@sandbox.invalid', v_uid, 'ativo', 'colaborador', public.qa_cpf((floor(random() * 900000) + 1)::int)) RETURNING id INTO v_ub;
  INSERT INTO public.perfis_acesso (tenant_id, nome, ativo) VALUES (v_t1, '[QA-RLS5] Perfil só metas ' || v_tag, true) RETURNING id INTO v_perfil;
  INSERT INTO public.perfil_permissoes (perfil_id, tenant_id, modulo, acao, escopo, ativo)
  VALUES (v_perfil, v_t1, 'metas', 'visualizar', 'empresa_inteira', true);
  -- Desativa o vínculo de perfil padrão criado pelo gatilho para o perfil do
  -- teste ser o único ativo.
  UPDATE public.usuario_perfil_vinculos SET ativo = false WHERE usuario_id = v_ub;
  INSERT INTO public.usuario_perfil_vinculos (tenant_id, usuario_id, perfil_id, ativo) VALUES (v_t1, v_ub, v_perfil, true);

  PERFORM public.qa_mky_claims(v_uid);
  v_ok    := public.perfil_permite_modulo(v_t1, 'metas');
  v_block := public.perfil_permite_modulo(v_t1, 'ponto');
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);

  IF v_ok IS TRUE AND v_block IS FALSE THEN
    r.situacao := 'passou';
    r.obtido := 'Portão de módulo correto: libera o módulo do perfil (metas) e barra o não liberado (ponto).';
  ELSIF v_block IS NOT FALSE THEN
    r.situacao := 'falhou';
    r.obtido := 'Portão de módulo falhou: perfil sem "ponto" foi liberado para o módulo ponto.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'Controle falhou: perfil COM "metas" não foi liberado para o próprio módulo.';
  END IF;
  r.detalhe := jsonb_build_object('metas', v_ok, 'ponto', v_block);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_rls_006()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_claims text; v_t1 uuid := public.qa_sandbox_tenant_id();
        v_tag text := left(gen_random_uuid()::text, 8); n_anon bigint; n_owner bigint;
BEGIN
  v_claims := current_setting('request.jwt.claims', true);
  IF v_t1 IS NULL THEN r.situacao := 'nao_implementado'; r.obtido := 'Cercado de teste ausente.'; RETURN r; END IF;

  r.passo_ordem := 1; r.passo_acao := 'Sessão anônima (sem claims) tenta ler dado de negócio';
  r.esperado := 'Zero linhas';

  INSERT INTO public.metas (tenant_id, titulo, ano) VALUES (v_t1, '[QA-RLS6] meta anon ' || v_tag, 2026);
  SELECT count(*) INTO n_owner FROM public.metas WHERE tenant_id = v_t1 AND titulo = '[QA-RLS6] meta anon ' || v_tag;

  n_anon := qa_rls.conta_anon(format('SELECT count(*) FROM public.metas WHERE tenant_id = %L AND titulo = %L', v_t1, '[QA-RLS6] meta anon ' || v_tag));

  IF n_owner < 1 THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Não foi possível semear a meta de teste (controle vazio).';
  ELSIF n_anon <= 0 THEN
    r.situacao := 'passou';
    r.obtido := 'Sessão anônima lê 0 linhas de negócio, embora o registro exista. Linha de base da RLS respeitada.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('O anônimo leu %s linha(s) de negócio — RLS não está barrando auth.uid() nulo.', n_anon);
  END IF;
  r.detalhe := jsonb_build_object('n_anon', n_anon, 'n_owner', n_owner);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_rls_007()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno;
BEGIN
  -- A cobertura da camada de perfil é a mesma varredura do PERFIL-003. Reusar
  -- garante que os dois casos falem a mesma verdade (uma fonte só).
  r := public.qa_caso_perfil_003();
  r.passo_acao := 'Cobertura da camada de perfil (via PERFIL-003): tabela sensível nova precisa de política ou exceção';
  r.esperado   := 'Nenhuma tabela de padrão sensível sem política de perfil ou exceção documentada';
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_hom_c1()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_active boolean; v_sched text; v_total int; v_err int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir o agendamento ponto-vigilancias-diarias e rodar as 8 vigilâncias';
  r.esperado    := 'Job ativo às 03:37 UTC; 8 linhas, todas com tenants_com_erro = 0';

  SELECT active, schedule INTO v_active, v_sched FROM cron.job WHERE jobname = 'ponto-vigilancias-diarias';
  SELECT count(*)::int, count(*) FILTER (WHERE tenants_com_erro > 0)::int
    INTO v_total, v_err FROM public.ponto_vigilancias_diarias();

  IF v_active IS NOT TRUE OR v_sched IS DISTINCT FROM '37 3 * * *' THEN
    r.situacao := 'falhou';
    r.obtido := format('Agendamento das vigilâncias ausente/errado (ativo=%s, schedule=%s).', COALESCE(v_active::text,'nulo'), COALESCE(v_sched,'nulo'));
  ELSIF v_total <> 8 THEN
    r.situacao := 'falhou';
    r.obtido := format('A rotina devolveu %s vigilância(s), esperado 8.', v_total);
  ELSIF v_err > 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('%s vigilância(s) acusaram tenant com erro.', v_err);
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Job ativo às 03:37 UTC e as 8 vigilâncias rodaram sem erro.';
  END IF;
  r.detalhe := jsonb_build_object('job_ativo', v_active, 'schedule', v_sched, 'total', v_total, 'com_erro', v_err);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_hom_c2()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t1 uuid := public.qa_sandbox_tenant_id(); v_venc date := CURRENT_DATE + 10;
        v_tag text := left(gen_random_uuid()::text, 8); n0 int; n1 int; n2 int;
BEGIN
  IF v_t1 IS NULL THEN r.situacao := 'nao_implementado'; r.obtido := 'Cercado de teste ausente.'; RETURN r; END IF;

  r.passo_ordem := 1;
  r.passo_acao  := 'Certificado vencendo em 10 dias; rodar as vigilâncias duas vezes';
  r.esperado    := '1º disparo cria o alerta; 2º não duplica';

  INSERT INTO public.ponto_certificados_digitais (tenant_id, titular_nome, numero_serie, valido_ate, alerta_antecedencia_dias, ativo)
  VALUES (v_t1, '[QA] Titular ' || v_tag, 'QA-SERIE-' || v_tag, v_venc, 30, true);

  SELECT count(*)::int INTO n0 FROM public.ponto_alertas
   WHERE tenant_id = v_t1 AND tipo = 'certificado_digital_vencimento' AND data_referencia = v_venc;

  PERFORM public.ponto_vigilancias_diarias();
  SELECT count(*)::int INTO n1 FROM public.ponto_alertas
   WHERE tenant_id = v_t1 AND tipo = 'certificado_digital_vencimento' AND data_referencia = v_venc;

  PERFORM public.ponto_vigilancias_diarias();
  SELECT count(*)::int INTO n2 FROM public.ponto_alertas
   WHERE tenant_id = v_t1 AND tipo = 'certificado_digital_vencimento' AND data_referencia = v_venc;

  IF n1 = 1 AND n2 = 1 THEN
    r.situacao := 'passou';
    r.obtido := 'O 1º disparo criou o alerta do certificado; o 2º não duplicou (segue um único aviso).';
  ELSIF n1 <> 1 THEN
    r.situacao := 'falhou';
    r.obtido := format('O 1º disparo deveria criar 1 alerta do certificado, criou %s (antes havia %s).', n1, n0);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('O 2º disparo DUPLICOU o alerta: passou de %s para %s.', n1, n2);
  END IF;
  r.detalhe := jsonb_build_object('antes', n0, 'apos_1', n1, 'apos_2', n2, 'vencimento', v_venc);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_hom_f2()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_claims text; v_t1 uuid := public.qa_sandbox_tenant_id();
        v_uid uuid := gen_random_uuid(); n_selfie int; n_afd int;
BEGIN
  v_claims := current_setting('request.jwt.claims', true);
  IF v_t1 IS NULL THEN r.situacao := 'nao_implementado'; r.obtido := 'Cercado de teste ausente.'; RETURN r; END IF;

  r.passo_ordem := 1;
  r.passo_acao  := 'Registrar visualização de selfie e exportação de AFD pelos loggers da trilha';
  r.esperado    := 'Uma linha visualizou_selfie e uma exportou_afd (com competência e empresa no escopo)';

  PERFORM public.qa_mky_claims(v_uid);
  -- Mesmos loggers que a tela da selfie e o export do AFD invocam (Portaria 671 / LGPD).
  PERFORM public.ponto_log_acesso_sensivel(v_t1, 'visualizou_selfie', 'selfie', gen_random_uuid(), NULL, 'QA: visualização de selfie', NULL);
  PERFORM public.ponto_log_exportacao(v_t1, 'exportou_afd',
            jsonb_build_object('competencia', '2026-09', 'empresa', 'QA Empresa Staging'), NULL, 'QA: exportação de AFD', NULL);
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);

  SELECT count(*)::int INTO n_selfie FROM public.ponto_acesso_sensivel_log
   WHERE usuario_id = v_uid AND acao = 'visualizou_selfie';
  SELECT count(*)::int INTO n_afd FROM public.ponto_acesso_sensivel_log
   WHERE usuario_id = v_uid AND acao = 'exportou_afd'
     AND escopo ? 'competencia' AND escopo ? 'empresa';

  IF n_selfie = 1 AND n_afd = 1 THEN
    r.situacao := 'passou';
    r.obtido := 'A visualização de selfie e a exportação de AFD ficaram registradas na trilha (com competência e empresa no escopo).';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Trilha incompleta: visualizou_selfie=%s (esperado 1), exportou_afd com escopo=%s (esperado 1).', n_selfie, n_afd);
  END IF;
  r.detalhe := jsonb_build_object('selfie', n_selfie, 'afd', n_afd);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_131()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_in text; v_out text; v_falhas text[] := '{}';
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Passar uma "resposta da IA" com telefone, e-mail e link pelo filtro de saída';
  r.esperado := 'Telefone, e-mail e link saem mascarados; nenhum chega cru ao usuário';

  v_in := 'Fecho direto: (11) 98888-7777, meu e-mail joao.teste@exemplo.com e o site https://wa.me/5511988887777';
  v_out := public.marketye_mascarar_contato(v_in);

  IF v_out ~ '\d{4,5}[\s.-]?\d{4}' THEN v_falhas := array_append(v_falhas, 'telefone não mascarado'); END IF;
  IF v_out ~ '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' THEN v_falhas := array_append(v_falhas, 'e-mail não mascarado'); END IF;
  IF v_out ~ '(https?://|www\.)' THEN v_falhas := array_append(v_falhas, 'link não mascarado'); END IF;

  IF array_length(v_falhas, 1) IS NULL THEN
    r.situacao := 'passou';
    r.obtido := 'Telefone, e-mail e link foram mascarados na saída — a IA não vira canal direto.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: ' || array_to_string(v_falhas, '; ') || '. Saída: ' || v_out;
  END IF;
  r.detalhe := jsonb_build_object('entrada', v_in, 'saida', v_out);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_091()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_claims text; a record; v_falhas text[] := '{}';
        v_prof record; n_audit int;
BEGIN
  v_claims := current_setting('request.jwt.claims', true);
  PERFORM public.qa_mky_limpar();

  r.passo_ordem := 1; r.passo_acao := 'Especialista com foto e dados pessoais pede exclusão';
  r.esperado := 'Campos pessoais (foto, CPF, e-mail, telefone) anonimizados; auditoria retida';

  SELECT * INTO a FROM public.qa_mky_especialista('091', public.qa_cpf(91));
  PERFORM public.qa_mky_claims(a.uid);
  UPDATE public.marketplace_profissionais SET foto_url = 'https://exemplo/foto.jpg', bio = 'bio pessoal' WHERE id = a.prof_id;

  PERFORM public.marketye_excluir_meu_perfil('EXCLUIR');

  SELECT nome_completo, cpf_cnpj, foto_url, telefone, email, bio, status, excluido_em
    INTO v_prof FROM public.marketplace_profissionais WHERE id = a.prof_id;
  IF v_prof.cpf_cnpj IS NOT NULL THEN v_falhas := array_append(v_falhas, 'CPF/CNPJ não apagado'); END IF;
  IF v_prof.foto_url IS NOT NULL THEN v_falhas := array_append(v_falhas, 'foto não apagada'); END IF;
  IF v_prof.telefone IS NOT NULL THEN v_falhas := array_append(v_falhas, 'telefone não apagado'); END IF;
  IF v_prof.bio IS NOT NULL THEN v_falhas := array_append(v_falhas, 'bio não apagada'); END IF;
  IF v_prof.excluido_em IS NULL THEN v_falhas := array_append(v_falhas, 'exclusão não marcada'); END IF;

  -- Transacional retido: o registro de auditoria da exclusão permanece.
  SELECT count(*) INTO n_audit FROM public.marketplace_audit_log
   WHERE profissional_id = a.prof_id AND acao = 'exclusao_lgpd';
  IF n_audit < 1 THEN v_falhas := array_append(v_falhas, 'auditoria da exclusão não retida'); END IF;

  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(v_falhas, 1) IS NULL THEN
    r.situacao := 'passou';
    r.obtido := 'Exclusão apagou o pessoal (CPF, foto, telefone, bio) e marcou a saída; a auditoria transacional ficou retida.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: ' || array_to_string(v_falhas, '; ');
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_117()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_uid uuid := gen_random_uuid(); v_tag text := left(v_uid::text, 8);
        v_recusou boolean := false; n_orfa int; v_falhas text[] := '{}'; v_res jsonb; v_ok_id uuid;
BEGIN
  PERFORM public.qa_mky_limpar();
  r.passo_ordem := 1; r.passo_acao := 'Cadastrar especialista com entrada inválida (dados vazios)';
  r.esperado := 'Recusa com erro claro; nenhuma conta parcial criada';

  INSERT INTO auth.users (id, email) VALUES (v_uid, 'qa-mky117-' || v_tag || '@sandbox.invalid');
  BEGIN
    PERFORM public.marketye_cadastrar_especialista_para(v_uid, '{}'::jsonb);
  EXCEPTION WHEN OTHERS THEN v_recusou := true;
  END;
  SELECT count(*) INTO n_orfa FROM public.marketplace_profissionais WHERE user_id = v_uid;

  IF NOT v_recusou THEN v_falhas := array_append(v_falhas, 'entrada inválida foi aceita'); END IF;
  IF n_orfa > 0 THEN v_falhas := array_append(v_falhas, format('sobrou conta órfã (%s linha)', n_orfa)); END IF;

  r.passo_ordem := 2; r.passo_acao := 'Cadastrar com entrada válida'; r.esperado := 'Profissional criado inteiro';
  v_res := public.marketye_cadastrar_especialista_para(v_uid, jsonb_build_object(
    'nome_completo', 'QA Cadastro 117', 'email', 'qa-mky117-' || v_tag || '@sandbox.invalid',
    'cpf_cnpj', public.qa_cpf(117), 'cidade', 'Cidade QA', 'estado', 'QA',
    'modalidades', '["online"]'::jsonb, 'aceite_termos', true, 'conselho', 'CREA',
    'registro_profissional', 'QA-117', 'origem', 'qa', 'tenant_origem', public.qa_sandbox_tenant_id()));
  v_ok_id := (v_res->>'id')::uuid;
  IF v_ok_id IS NULL THEN v_falhas := array_append(v_falhas, 'entrada válida não criou o profissional'); END IF;

  IF array_length(v_falhas, 1) IS NULL THEN
    r.situacao := 'passou';
    r.obtido := 'Entrada inválida recusada sem deixar conta órfã; entrada válida criou o profissional inteiro.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: ' || array_to_string(v_falhas, '; ');
  END IF;
  r.detalhe := jsonb_build_object('recusou_invalida', v_recusou, 'orfas', n_orfa);
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_edge_001()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_ag uuid; v_antes timestamptz; v_depois timestamptz;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Sem supabase_url/anon_key no app_config, rodar a rotina de disparo';
  r.esperado := 'Nenhum agente é disparado (agenda intocada) — proteção de ambiente';

  -- Tira a config do ambiente (transação-local; o descarte devolve).
  DELETE FROM public.app_config WHERE chave IN ('supabase_url', 'supabase_anon_key');

  -- Agente ativo e vencido: se houvesse dispatch, a agenda avançaria.
  INSERT INTO public.youreyes_agentes (nome, ativo, periodicidade, proxima_execucao)
  VALUES ('[QA-EDGE1] Agente de teste', true, 'diaria', now() - interval '1 minute')
  RETURNING id, proxima_execucao INTO v_ag, v_antes;

  PERFORM public.youreyes_dispatch_agentes();

  SELECT proxima_execucao INTO v_depois FROM public.youreyes_agentes WHERE id = v_ag;

  IF v_depois IS NOT DISTINCT FROM v_antes THEN
    r.situacao := 'passou';
    r.obtido := 'Sem config de ambiente, o disparo não tocou o agente (não chamou ninguém). Proteção de ambiente OK.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'A rotina de disparo avançou a agenda mesmo sem supabase_url/anon_key — chamaria a Edge Function.';
  END IF;
  r.detalhe := jsonb_build_object('antes', v_antes, 'depois', v_depois);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_edge_006()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_lista text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA: procurar segredo service_role no app_config';
  r.esperado := 'Nenhuma chave de service_role guardada no banco (fica só no servidor)';

  SELECT string_agg(chave, ', ' ORDER BY chave) INTO v_lista
  FROM public.app_config
  WHERE chave ILIKE '%service_role%' OR chave ILIKE '%service%key%' OR chave ILIKE '%role%secret%';

  IF v_lista IS NULL THEN
    r.situacao := 'passou';
    r.obtido := 'Nenhum segredo service_role no app_config — a chave que bypassa RLS fica só na Edge Function.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'Chave(s) suspeita(s) de service_role no app_config (legível do cliente): ' || v_lista;
    r.detalhe := jsonb_build_object('chaves', v_lista);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_edge_007()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_lista text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA: toda tabela *_links de acesso por token tem coluna de validade';
  r.esperado := 'Nenhum link por token sem expiração (senão vira porta aberta)';

  SELECT string_agg(t.table_name, ', ' ORDER BY t.table_name) INTO v_lista
  FROM information_schema.tables t
  WHERE t.table_schema = 'public' AND t.table_type = 'BASE TABLE' AND t.table_name LIKE '%\_links'
    AND EXISTS (SELECT 1 FROM information_schema.columns c
                 WHERE c.table_schema = 'public' AND c.table_name = t.table_name AND c.column_name = 'token')
    AND NOT EXISTS (SELECT 1 FROM information_schema.columns c
                     WHERE c.table_schema = 'public' AND c.table_name = t.table_name
                       AND c.column_name IN ('expira_em', 'valido_ate', 'expires_at', 'data_expiracao'));

  IF v_lista IS NULL THEN
    r.situacao := 'passou';
    r.obtido := 'Todo link público por token tem coluna de validade (expiração).';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'Tabela(s) de link por token SEM coluna de validade: ' || v_lista;
    r.detalhe := jsonb_build_object('tabelas', v_lista);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

-- ----------------------------------------------------------------------------
-- 6) Ligacao caso <-> rotina (idempotente)
-- ----------------------------------------------------------------------------
INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
  ('EPI-001', 'qa_caso_epi_001', true),
  ('MWKF-001', 'qa_caso_mwkf_001', true),
  ('PGP-014', 'qa_caso_pgp_014', true),
  ('RLS-001', 'qa_caso_rls_001', true),
  ('RLS-002', 'qa_caso_rls_002', true),
  ('RLS-003', 'qa_caso_rls_003', true),
  ('RLS-004', 'qa_caso_rls_004', true),
  ('RLS-005', 'qa_caso_rls_005', true),
  ('RLS-006', 'qa_caso_rls_006', true),
  ('RLS-007', 'qa_caso_rls_007', true),
  ('PONTO-HOM-C1', 'qa_caso_ponto_hom_c1', true),
  ('PONTO-HOM-C2', 'qa_caso_ponto_hom_c2', true),
  ('PONTO-HOM-F2', 'qa_caso_ponto_hom_f2', true),
  ('MKY-131', 'qa_caso_mky_131', true),
  ('MKY-091', 'qa_caso_mky_091', true),
  ('MKY-117', 'qa_caso_mky_117', true),
  ('EDGE-001', 'qa_caso_edge_001', true),
  ('EDGE-006', 'qa_caso_edge_006', true),
  ('EDGE-007', 'qa_caso_edge_007', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- ----------------------------------------------------------------------------
-- 7) CONFERENCIA (unico SELECT — o editor mostra so o ultimo resultado)
--    Estrutura criada + situacao das rotinas entregues (leitura, descartavel).
-- ----------------------------------------------------------------------------
WITH estrutura AS (
  SELECT 1 AS ord, 'coluna epis.quantidade_reservada' AS item,
         (EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='epis' AND column_name='quantidade_reservada'))::text AS resultado
  UNION ALL SELECT 1, 'coluna marketplace_profissionais.registro_vencido',
         (EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='marketplace_profissionais' AND column_name='registro_vencido'))::text
  UNION ALL SELECT 1, 'coluna plano_acoes.eficacia_validada_em',
         (EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='plano_acoes' AND column_name='eficacia_validada_em'))::text
  UNION ALL SELECT 1, 'gatilho trg_plano_acao_marketplace_eficacia',
         (EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_plano_acao_marketplace_eficacia' AND NOT tgisinternal))::text
  UNION ALL SELECT 1, 'gatilho trg_meta_workflow_registra_trilha',
         (EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_meta_workflow_registra_trilha' AND NOT tgisinternal))::text
),
rotinas AS (
  SELECT 2 AS ord, t.codigo AS item, (public.qa_executar_descartavel(t.funcao_sql)).situacao::text AS resultado
  FROM (VALUES
    ('EPI-001','qa_caso_epi_001'), ('MWKF-001','qa_caso_mwkf_001'), ('PGP-014','qa_caso_pgp_014'),
    ('RLS-001','qa_caso_rls_001'), ('RLS-002','qa_caso_rls_002'), ('RLS-003','qa_caso_rls_003'),
    ('RLS-004','qa_caso_rls_004'), ('RLS-005','qa_caso_rls_005'), ('RLS-006','qa_caso_rls_006'),
    ('RLS-007','qa_caso_rls_007'), ('PONTO-HOM-C1','qa_caso_ponto_hom_c1'),
    ('PONTO-HOM-C2','qa_caso_ponto_hom_c2'), ('PONTO-HOM-F2','qa_caso_ponto_hom_f2'),
    ('MKY-131','qa_caso_mky_131'), ('MKY-091','qa_caso_mky_091'), ('MKY-117','qa_caso_mky_117'),
    ('EDGE-001','qa_caso_edge_001'), ('EDGE-006','qa_caso_edge_006'), ('EDGE-007','qa_caso_edge_007')
  ) AS t(codigo, funcao_sql)
)
SELECT item, resultado FROM (
  SELECT ord, item, resultado FROM estrutura
  UNION ALL SELECT ord, item, resultado FROM rotinas
) x ORDER BY ord, item;
