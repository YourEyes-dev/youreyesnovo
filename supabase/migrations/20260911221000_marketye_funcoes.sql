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
