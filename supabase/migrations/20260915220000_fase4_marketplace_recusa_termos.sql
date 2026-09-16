-- ============================================================================
-- Fase 4 (motores) — Marketplace: recusa como resposta e aceite de termos.
--
-- MKY-072: quando o ESPECIALISTA encerra a conversa (recusa "Não vou atender"),
--          isso conta como RESPOSTA (carimba primeira_resposta_em) e o texto de
--          sistema reflete que foi o especialista, não a empresa.
-- MKY-093: publicar exige os termos vigentes aceitos — versão nova pendente
--          trava a publicação até o aceite.
--
-- Lógica em funções SECURITY DEFINER. Conferir a família MKY no ambiente de teste.
-- ============================================================================

-- ── MKY-072: a recusa do especialista conta como resposta ───────────────────
CREATE OR REPLACE FUNCTION public.marketye_lead_status(p_lead_id uuid, p_status text, p_motivo text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $mkyfn$
DECLARE v_papel text := public.marketye_lead_papel(p_lead_id); v_prof uuid;
BEGIN
  IF v_papel NOT IN ('cliente', 'especialista') THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  IF p_status NOT IN ('ganho', 'perdido', 'encerrado') THEN RAISE EXCEPTION 'Situação inválida'; END IF;
  UPDATE public.marketplace_leads SET
    status = p_status,
    ganho_em = CASE WHEN p_status = 'ganho' THEN COALESCE(ganho_em, now()) ELSE ganho_em END,
    contato_liberado = CASE WHEN p_status = 'ganho' THEN true ELSE contato_liberado END,
    -- Recusar/encerrar pelo especialista É uma resposta: carimba a 1ª resposta.
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

-- ── MKY-093: publicar exige os termos vigentes aceitos ──────────────────────
CREATE OR REPLACE FUNCTION public.marketye_anuncio_publicar(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $mkyfn$
DECLARE v_prof uuid := public.marketye_meu_id(); s record; p record; c record; v_versoes jsonb;
BEGIN
  IF v_prof IS NULL THEN RAISE EXCEPTION 'Sem cadastro de especialista'; END IF;
  SELECT * INTO s FROM public.marketplace_servicos WHERE id = p_id AND profissional_id = v_prof;
  IF s.id IS NULL THEN RAISE EXCEPTION 'Anúncio não encontrado'; END IF;
  IF s.status = 'removido' THEN
    RAISE EXCEPTION 'Anúncio removido não pode ser republicado. Crie um novo anúncio.';
  END IF;
  SELECT * INTO p FROM public.marketplace_profissionais WHERE id = v_prof;
  IF p.status::text <> 'ativo' THEN
    RAISE EXCEPTION 'Seu cadastro ainda está em verificação. O anúncio fica salvo e aparece na vitrine assim que a verificação concluir.';
  END IF;
  IF p.excluido_em IS NOT NULL THEN RAISE EXCEPTION 'Perfil excluído'; END IF;

  -- Termos vigentes: versão nova não aceita trava a publicação (aceite no portal).
  v_versoes := COALESCE(public.marketye_config('termos_versoes'), '{}'::jsonb);
  IF EXISTS (
    SELECT 1 FROM (VALUES ('termos_especialista'), ('privacidade_nao_usuario'), ('codigo_etica')) AS t(tipo)
     WHERE (v_versoes->>t.tipo) IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM public.marketplace_consentimentos co
                        WHERE co.profissional_id = v_prof AND co.tipo = t.tipo
                          AND co.versao = v_versoes->>t.tipo)
  ) THEN
    RAISE EXCEPTION 'Há novos termos a aceitar antes de publicar. Aceite os termos pendentes no seu portal.';
  END IF;

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
