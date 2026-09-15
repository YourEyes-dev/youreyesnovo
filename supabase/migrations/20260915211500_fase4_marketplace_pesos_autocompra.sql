-- ============================================================================
-- Fase 4 (motores) — Marketplace: pesos de relevância e autocompra.
--
-- MKY-101: pesos de relevância normalizados a 100%, chave faltante completada,
--          peso negativo recusado (marketye_config_salvar).
-- MKY-082: autocompra bloqueada — a empresa não abre conversa com o próprio
--          anúncio (marketye_abrir_lead).
--
-- Correções de lógica em funções SECURITY DEFINER (não mexem em RLS). Conferir
-- a família MKY no ambiente de teste (a réplica local não reproduz a RLS de
-- alguns casos com fidelidade).
-- ============================================================================

-- ── MKY-101: normalização e validação dos pesos de relevância ───────────────
CREATE OR REPLACE FUNCTION public.marketye_config_salvar(p_chave text, p_valor jsonb, p_descricao text DEFAULT NULL::text, p_jurisdicao text DEFAULT 'BR'::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $mkyfn$
DECLARE v_versao int; v_id uuid; v_soma numeric; v_norm jsonb;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  IF p_chave IS NULL OR p_valor IS NULL THEN RAISE EXCEPTION 'Informe chave e valor'; END IF;

  -- Pesos de relevância: nunca negativos; chaves padrão completadas; soma
  -- normalizada a 1,00 (o operador digita a intenção, o motor cuida da conta).
  IF p_chave = 'relevancia_pesos' THEN
    IF EXISTS (SELECT 1 FROM jsonb_each_text(p_valor) WHERE value::numeric < 0) THEN
      RAISE EXCEPTION 'Peso de relevância não pode ser negativo';
    END IF;
    p_valor := '{"fit":0,"reputacao":0,"saude":0,"proximidade":0,"exploracao":0,"preco":0,"destaque":0}'::jsonb || p_valor;
    SELECT sum(value::numeric) INTO v_soma FROM jsonb_each_text(p_valor);
    IF v_soma IS NULL OR v_soma <= 0 THEN RAISE EXCEPTION 'Pesos de relevância inválidos'; END IF;
    SELECT jsonb_object_agg(key, round(value::numeric / v_soma, 4)) INTO v_norm FROM jsonb_each_text(p_valor);
    p_valor := v_norm;
  END IF;

  UPDATE public.marketplace_config SET vigente = false WHERE chave = p_chave AND jurisdicao = p_jurisdicao AND vigente;
  SELECT COALESCE(max(versao), 0) + 1 INTO v_versao FROM public.marketplace_config WHERE chave = p_chave AND jurisdicao = p_jurisdicao;
  INSERT INTO public.marketplace_config (chave, versao, valor, descricao, vigente, jurisdicao, criado_por)
  VALUES (p_chave, v_versao, p_valor, p_descricao, true, p_jurisdicao, auth.uid()) RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id, 'chave', p_chave, 'versao', v_versao);
END $mkyfn$;

-- ── MKY-082: autocompra bloqueada ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.marketye_abrir_lead(p_profissional_id uuid, p_servico_id uuid, p_mensagem text, p_origem_modulo text DEFAULT NULL::text, p_origem_id uuid DEFAULT NULL::uuid, p_obrigacao text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $mkyfn$
DECLARE v_tenant uuid := public.get_user_tenant_id(); v_lead uuid; v_nome text; v_cupom text; v_mascarar boolean; v_texto text; v_existente uuid;
BEGIN
  IF v_tenant IS NULL THEN RAISE EXCEPTION 'Só usuários de uma empresa cliente abrem contato'; END IF;
  -- Autocompra: quem abre a conversa não pode ser o dono do anúncio (o mesmo
  -- usuário que é especialista) — infla reputação avaliando a si mesmo.
  IF p_profissional_id = public.marketye_meu_id() THEN
    RAISE EXCEPTION 'Você não pode abrir conversa com o seu próprio anúncio';
  END IF;
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
END $mkyfn$;
