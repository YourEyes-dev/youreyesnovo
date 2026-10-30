-- ============================================================================
-- ASSINATURA — Fatia 1, parte 3: o ciclo da solicitação no servidor
--
-- Funções que as funções de borda chamam com a chave de serviço (o colaborador
-- que abre o link é anônimo) e as que o RH chama logado:
--
--   assinatura_criar_solicitacao   (borda) PDF já congelado no bucket + hash; uma
--                                  ativa por documento; competência fechada
--   assinatura_emitir_token        (borda) token novo de 256 bits; o banco guarda
--                                  só o hash; o anterior deixa de valer
--   assinatura_rh_novo_link        (RH)    idem, pelo RH ("copiar link"); destrava
--                                  o bloqueio de CPF
--   assinatura_registrar_envio     (borda) resultado do e-mail (convite/lembrete)
--   assinatura_abrir               (borda) link aberto: registra e devolve o estado
--   assinatura_cpf_conferir        (borda) CPF do signatário; 5 erros bloqueiam 24 h
--   assinatura_otp_registrar       (borda) código de 6 dígitos (só o hash), 10 min
--   assinatura_otp_validar         (borda) 5 tentativas por código
--   assinatura_registrar_consentimento (borda) aceite LGPD ou recusa da câmera
--   assinatura_registrar_evidencia (borda) quadros da prova de vida (no bucket)
--   assinatura_concluir            (borda) TUDO numa transação: trilha selada,
--                                  Documentos (Jornada/AAAA/MM-Mês), solicitação
--                                  e espelho (ciência do colaborador)
--   assinatura_cancelar            (RH ou borda)
--   ponto_reabrir_competencia      reabrir também cancela as solicitações ativas
--   ponto_espelho_registrar_ciencia_papel  papel vai para Jornada/AAAA/MM-Mês e
--                                  cancela a solicitação eletrônica ativa
--
-- Regras da fundadora (30/10/2026): prova de vida obrigatória; se o colaborador
-- recusar a câmera, assina com CPF + código e fica marcado "sem prova de vida
-- (recusou câmera)"; sem e-mail o link não assina; lembretes D+2/D+5/D+8; expira
-- D+10; sem aceite tácito; contestação não bloqueia o fechamento.
--
-- Sem SELECT INTO (atribuição por subconsulta escalar). Idempotente.
-- ============================================================================

SET lock_timeout = '10s';

-- ── Ajudantes ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.assinatura_hash_token(p_token text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $fn$
  SELECT encode(public.digest(COALESCE(p_token, ''), 'sha256'), 'hex');
$fn$;

CREATE OR REPLACE FUNCTION public.assinatura_evento(
  p_solicitacao_id uuid,
  p_tipo           text,
  p_ator           text DEFAULT 'sistema',
  p_ator_id        uuid DEFAULT NULL,
  p_dados          jsonb DEFAULT '{}'::jsonb,
  p_origem         jsonb DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_id uuid := gen_random_uuid();
  v_tenant uuid := (SELECT s.tenant_id FROM public.assinatura_solicitacoes s WHERE s.id = p_solicitacao_id);
BEGIN
  IF v_tenant IS NULL THEN
    RETURN NULL;
  END IF;
  INSERT INTO public.assinatura_eventos (id, tenant_id, solicitacao_id, tipo, ator, ator_id, ip, user_agent, dados)
  VALUES (v_id, v_tenant, p_solicitacao_id, p_tipo, COALESCE(p_ator, 'sistema'), p_ator_id,
          NULLIF(COALESCE(p_origem->>'ip', p_origem->>'ip_address'), ''),
          NULLIF(p_origem->>'user_agent', ''),
          COALESCE(p_dados, '{}'::jsonb));
  RETURN v_id;
END;
$fn$;

-- O RH desta empresa pode gerir a assinatura deste colaborador?
CREATE OR REPLACE FUNCTION public.assinatura_rh_pode_gerir(p_tenant uuid, p_cpf text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  IF auth.uid() IS NULL OR p_tenant IS NULL THEN
    RETURN false;
  END IF;
  IF p_tenant IS DISTINCT FROM public.get_user_tenant_id() THEN
    RETURN false;
  END IF;
  RETURN public.perfil_permite_modulo(p_tenant, VARIADIC ARRAY['ponto', 'colaboradores'])
     AND public.perfil_escreve(p_tenant, ARRAY['ponto', 'colaboradores'], ARRAY['editar', 'aprovar'], p_cpf);
END;
$fn$;

-- ── Criar a solicitação ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.assinatura_criar_solicitacao(p_dados jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_id        uuid := COALESCE(NULLIF(p_dados->>'id', '')::uuid, gen_random_uuid());
  v_tenant    uuid := NULLIF(p_dados->>'tenant_id', '')::uuid;
  v_contexto  text := COALESCE(NULLIF(p_dados->>'contexto', ''), 'ponto_espelho');
  v_ref_id    uuid := NULLIF(p_dados->>'documento_ref_id', '')::uuid;
  v_sha       text := lower(COALESCE(p_dados->>'original_sha256', ''));
  v_path      text := NULLIF(p_dados->>'original_path', '');
  v_cpf       text := regexp_replace(COALESCE(p_dados->>'colaborador_cpf', ''), '[^0-9]', '', 'g');
  v_ativa     uuid;
  v_esp_cpf   text;
  v_esp_status text;
  v_esp_origem text;
  v_esp_comp  text;
  v_esp_emp   uuid;
  v_fechada   boolean;
  v_snapshot  jsonb := p_dados->'dados_snapshot';
BEGIN
  IF v_tenant IS NULL OR v_ref_id IS NULL OR v_cpf = '' THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'dados_incompletos');
  END IF;
  -- Sem o PDF congelado e o hash dele, não há o que assinar.
  IF v_path IS NULL OR v_sha !~ '^[0-9a-f]{64}$' THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'hash_obrigatorio');
  END IF;

  v_ativa := (SELECT s.id FROM public.assinatura_solicitacoes s
               WHERE s.contexto = v_contexto AND s.documento_ref_id = v_ref_id
                 AND s.status IN ('preparando', 'na_fila', 'enviado', 'visualizado') LIMIT 1);
  IF v_ativa IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'ja_existe_ativa', 'solicitacao_id', v_ativa);
  END IF;

  IF v_contexto = 'ponto_espelho' THEN
    v_esp_cpf    := (SELECT regexp_replace(COALESCE(e.colaborador_cpf, ''), '[^0-9]', '', 'g') FROM public.ponto_espelhos e WHERE e.id = v_ref_id AND e.tenant_id = v_tenant);
    v_esp_status := (SELECT COALESCE(e.status, 'gerado') FROM public.ponto_espelhos e WHERE e.id = v_ref_id);
    v_esp_origem := (SELECT e.ciencia_origem FROM public.ponto_espelhos e WHERE e.id = v_ref_id);
    v_esp_comp   := (SELECT e.competencia FROM public.ponto_espelhos e WHERE e.id = v_ref_id);
    v_esp_emp    := (SELECT e.empresa_id FROM public.ponto_espelhos e WHERE e.id = v_ref_id);
    IF v_esp_cpf IS NULL OR v_esp_cpf <> v_cpf THEN
      RETURN jsonb_build_object('ok', false, 'erro', 'espelho_nao_encontrado');
    END IF;
    IF v_esp_origem IS NOT NULL AND v_esp_status <> 'contestado' THEN
      RETURN jsonb_build_object('ok', false, 'erro', 'espelho_ja_tem_ciencia');
    END IF;
    v_fechada := EXISTS (
      SELECT 1 FROM public.ponto_fechamentos f
       WHERE f.tenant_id = v_tenant AND f.competencia = v_esp_comp AND f.status = 'fechado'
         AND (v_esp_emp IS NULL OR f.empresa_id IS NULL OR f.empresa_id = v_esp_emp));
    IF NOT v_fechada THEN
      RETURN jsonb_build_object('ok', false, 'erro', 'competencia_nao_fechada');
    END IF;
    v_snapshot := COALESCE(v_snapshot, (SELECT to_jsonb(e) FROM public.ponto_espelhos e WHERE e.id = v_ref_id));
  END IF;

  INSERT INTO public.assinatura_solicitacoes
    (id, tenant_id, empresa_id, lote_id, contexto, documento_ref_tabela, documento_ref_id, referencia,
     colaborador_id, colaborador_cpf, colaborador_nome, email, celular, status, link_base,
     expira_em, original_path, original_sha256, original_bytes, dados_snapshot, dados_sha256,
     enviado_por, enviado_por_nome, canais, proximo_lembrete_em)
  VALUES
    (v_id, v_tenant, COALESCE(NULLIF(p_dados->>'empresa_id', '')::uuid, v_esp_emp),
     NULLIF(p_dados->>'lote_id', '')::uuid, v_contexto,
     COALESCE(NULLIF(p_dados->>'documento_ref_tabela', ''), CASE WHEN v_contexto = 'ponto_espelho' THEN 'ponto_espelhos' END),
     v_ref_id, COALESCE(NULLIF(p_dados->>'referencia', ''), v_esp_comp),
     NULLIF(p_dados->>'colaborador_id', ''), v_cpf, NULLIF(p_dados->>'colaborador_nome', ''),
     NULLIF(btrim(COALESCE(p_dados->>'email', '')), ''), NULLIF(btrim(COALESCE(p_dados->>'celular', '')), ''),
     'na_fila', NULLIF(p_dados->>'link_base', ''),
     now() + interval '10 days', v_path, v_sha, NULLIF(p_dados->>'original_bytes', '')::int,
     v_snapshot, CASE WHEN v_snapshot IS NULL THEN NULL ELSE encode(public.digest(v_snapshot::text, 'sha256'), 'hex') END,
     NULLIF(p_dados->>'enviado_por', '')::uuid, NULLIF(p_dados->>'enviado_por_nome', ''),
     COALESCE(ARRAY(SELECT jsonb_array_elements_text(p_dados->'canais')), ARRAY[]::text[]),
     now() + interval '2 days');

  PERFORM public.assinatura_evento(v_id, 'criada', 'rh', NULLIF(p_dados->>'enviado_por', '')::uuid,
    jsonb_build_object('original_sha256', v_sha, 'referencia', COALESCE(NULLIF(p_dados->>'referencia', ''), v_esp_comp),
                       'lote_id', p_dados->>'lote_id'));

  IF v_contexto = 'ponto_espelho' THEN
    PERFORM set_config('ye.espelho_ciencia', 'on', true);
    UPDATE public.ponto_espelhos
       SET status = CASE WHEN COALESCE(status, 'gerado') = 'gerado' THEN 'enviado' ELSE status END,
           assinatura_solicitacao_id = v_id
     WHERE id = v_ref_id;
    PERFORM set_config('ye.espelho_ciencia', 'off', true);
  END IF;

  RETURN jsonb_build_object('ok', true, 'id', v_id, 'status', 'na_fila');
END;
$fn$;

-- ── Token (256 bits; o banco guarda só o hash) ─────────────────────────────
CREATE OR REPLACE FUNCTION public.assinatura_emitir_token(
  p_solicitacao_id uuid,
  p_ator           text DEFAULT 'sistema',
  p_ator_id        uuid DEFAULT NULL,
  p_motivo         text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_status text := (SELECT s.status FROM public.assinatura_solicitacoes s WHERE s.id = p_solicitacao_id);
  v_token  text;
BEGIN
  IF v_status IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'solicitacao_nao_encontrada');
  END IF;
  IF v_status NOT IN ('na_fila', 'enviado', 'visualizado', 'assinado', 'assinado_com_ressalva', 'contestado') THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'solicitacao_inativa', 'status', v_status);
  END IF;
  v_token := encode(public.gen_random_bytes(32), 'hex');
  UPDATE public.assinatura_solicitacoes
     SET token_hash = public.assinatura_hash_token(v_token),
         token_gerado_em = now()
   WHERE id = p_solicitacao_id;
  PERFORM public.assinatura_evento(p_solicitacao_id, 'link_gerado', p_ator, p_ator_id,
                                   jsonb_build_object('motivo', p_motivo));
  RETURN jsonb_build_object('ok', true, 'token', v_token);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.assinatura_rh_novo_link(p_solicitacao_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_tenant uuid := (SELECT s.tenant_id FROM public.assinatura_solicitacoes s WHERE s.id = p_solicitacao_id);
  v_cpf    text := (SELECT s.colaborador_cpf FROM public.assinatura_solicitacoes s WHERE s.id = p_solicitacao_id);
  v_status text := (SELECT s.status FROM public.assinatura_solicitacoes s WHERE s.id = p_solicitacao_id);
  v_res    jsonb;
BEGIN
  IF v_tenant IS NULL OR NOT public.assinatura_rh_pode_gerir(v_tenant, v_cpf) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_permissao');
  END IF;
  IF v_status NOT IN ('na_fila', 'enviado', 'visualizado') THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'solicitacao_inativa', 'status', v_status);
  END IF;
  -- Ato do RH: destrava o bloqueio por CPF errado e conta como envio manual.
  UPDATE public.assinatura_solicitacoes
     SET tentativas_cpf = 0, bloqueado_ate = NULL,
         status = CASE WHEN status = 'na_fila' THEN 'enviado' ELSE status END,
         enviado_em = COALESCE(enviado_em, now()),
         canais = CASE WHEN 'link' = ANY(canais) THEN canais ELSE array_append(canais, 'link') END
   WHERE id = p_solicitacao_id;
  v_res := public.assinatura_emitir_token(p_solicitacao_id, 'rh', auth.uid(), 'link_copiado');
  PERFORM public.assinatura_evento(p_solicitacao_id, 'link_copiado', 'rh', auth.uid(), '{}'::jsonb);
  RETURN v_res;
END;
$fn$;

-- ── Resultado do e-mail (convite, lembrete, via) ───────────────────────────
CREATE OR REPLACE FUNCTION public.assinatura_registrar_envio(
  p_solicitacao_id uuid,
  p_tipo           text,             -- 'solicitacao' | 'lembrete' | 'via'
  p_ok             boolean,
  p_erro           text DEFAULT NULL,
  p_manter_fila    boolean DEFAULT false,
  p_dados          jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_enviado  timestamptz := (SELECT s.enviado_em FROM public.assinatura_solicitacoes s WHERE s.id = p_solicitacao_id);
  v_lemb     int := (SELECT s.lembretes_enviados FROM public.assinatura_solicitacoes s WHERE s.id = p_solicitacao_id);
  v_tent     int := (SELECT s.envio_tentativas FROM public.assinatura_solicitacoes s WHERE s.id = p_solicitacao_id);
  v_base     timestamptz;
BEGIN
  IF v_tent IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'solicitacao_nao_encontrada');
  END IF;

  IF p_tipo = 'solicitacao' THEN
    IF p_ok THEN
      UPDATE public.assinatura_solicitacoes
         SET status = CASE WHEN status = 'na_fila' THEN 'enviado' ELSE status END,
             enviado_em = COALESCE(enviado_em, now()),
             envio_tentativas = envio_tentativas + 1, envio_erro = NULL, envio_proxima_em = NULL,
             canais = CASE WHEN 'email' = ANY(canais) THEN canais ELSE array_append(canais, 'email') END,
             proximo_lembrete_em = COALESCE(enviado_em, now()) + interval '2 days'
       WHERE id = p_solicitacao_id;
      PERFORM public.assinatura_evento(p_solicitacao_id, 'email_enviado', 'sistema', NULL, p_dados);
    ELSIF p_manter_fila AND v_tent + 1 < 3 THEN
      -- Fila (lote): tenta de novo com espera crescente.
      UPDATE public.assinatura_solicitacoes
         SET envio_tentativas = envio_tentativas + 1, envio_erro = left(p_erro, 500),
             envio_proxima_em = now() + make_interval(mins => (2 ^ (v_tent + 1))::int)
       WHERE id = p_solicitacao_id;
      PERFORM public.assinatura_evento(p_solicitacao_id, 'email_falhou', 'sistema', NULL,
                                       p_dados || jsonb_build_object('erro', left(p_erro, 300)));
    ELSE
      -- Sem fila (envio individual) ou tentativas esgotadas: o link já foi
      -- entregue ao RH para copiar; a solicitação segue aberta.
      UPDATE public.assinatura_solicitacoes
         SET status = CASE WHEN status = 'na_fila' AND NOT p_manter_fila THEN 'enviado'
                           WHEN status = 'na_fila' THEN 'falha' ELSE status END,
             enviado_em = CASE WHEN p_manter_fila THEN enviado_em ELSE COALESCE(enviado_em, now()) END,
             envio_tentativas = envio_tentativas + 1, envio_erro = left(p_erro, 500), envio_proxima_em = NULL,
             proximo_lembrete_em = CASE WHEN p_manter_fila THEN NULL ELSE COALESCE(enviado_em, now()) + interval '2 days' END
       WHERE id = p_solicitacao_id;
      PERFORM public.assinatura_evento(p_solicitacao_id, 'email_falhou', 'sistema', NULL,
                                       p_dados || jsonb_build_object('erro', left(p_erro, 300)));
    END IF;

  ELSIF p_tipo = 'lembrete' THEN
    IF p_ok THEN
      v_base := COALESCE(v_enviado, now());
      UPDATE public.assinatura_solicitacoes
         SET lembretes_enviados = lembretes_enviados + 1,
             -- D+2, D+5, D+8 contados do envio.
             proximo_lembrete_em = CASE v_lemb + 1
                                     WHEN 1 THEN v_base + interval '5 days'
                                     WHEN 2 THEN v_base + interval '8 days'
                                     ELSE NULL END
       WHERE id = p_solicitacao_id;
      PERFORM public.assinatura_evento(p_solicitacao_id, 'lembrete', 'sistema', NULL,
                                       p_dados || jsonb_build_object('numero', v_lemb + 1));
    ELSE
      UPDATE public.assinatura_solicitacoes
         SET proximo_lembrete_em = now() + interval '1 day'
       WHERE id = p_solicitacao_id;
      PERFORM public.assinatura_evento(p_solicitacao_id, 'lembrete_falhou', 'sistema', NULL,
                                       p_dados || jsonb_build_object('erro', left(p_erro, 300)));
    END IF;

  ELSE
    PERFORM public.assinatura_evento(p_solicitacao_id,
      CASE WHEN p_ok THEN 'via_enviada' ELSE 'via_falhou' END, 'sistema', NULL,
      p_dados || jsonb_build_object('erro', left(p_erro, 300)));
  END IF;

  RETURN jsonb_build_object('ok', true);
END;
$fn$;

-- ── Link aberto ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.assinatura_abrir(p_token text, p_origem jsonb DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_id     uuid;
  v_status text;
  v_expira timestamptz;
  v_row    jsonb;
BEGIN
  IF COALESCE(p_token, '') !~ '^[0-9a-f]{64}$' THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'link_invalido');
  END IF;
  v_id := (SELECT s.id FROM public.assinatura_solicitacoes s
            WHERE s.token_hash = public.assinatura_hash_token(p_token));
  IF v_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'link_invalido');
  END IF;
  v_status := (SELECT s.status FROM public.assinatura_solicitacoes s WHERE s.id = v_id);
  v_expira := (SELECT s.expira_em FROM public.assinatura_solicitacoes s WHERE s.id = v_id);

  IF v_status IN ('na_fila', 'enviado', 'visualizado') AND v_expira IS NOT NULL AND v_expira < now() THEN
    UPDATE public.assinatura_solicitacoes SET status = 'expirado', proximo_lembrete_em = NULL WHERE id = v_id;
    PERFORM public.assinatura_evento(v_id, 'expirado', 'sistema', NULL, '{}'::jsonb);
    v_status := 'expirado';
  END IF;

  IF v_status IN ('na_fila', 'enviado', 'visualizado') THEN
    UPDATE public.assinatura_solicitacoes
       SET status = 'visualizado',
           visualizado_em = COALESCE(visualizado_em, now())
     WHERE id = v_id;
  END IF;
  PERFORM public.assinatura_evento(v_id, 'aberto', 'colaborador', NULL, '{}'::jsonb, p_origem);

  v_row := (SELECT to_jsonb(s) - 'token_hash' FROM public.assinatura_solicitacoes s WHERE s.id = v_id);
  RETURN jsonb_build_object('ok', true, 'solicitacao', v_row,
    'empresa', (SELECT COALESCE(ec.razao_social, ec.nome_fantasia)
                  FROM public.empresa_cadastro ec WHERE ec.id = (v_row->>'empresa_id')::uuid));
END;
$fn$;

-- Estado pelo token, sem registrar abertura (uso interno da borda a cada ação).
CREATE OR REPLACE FUNCTION public.assinatura_por_token(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  IF COALESCE(p_token, '') !~ '^[0-9a-f]{64}$' THEN
    RETURN NULL;
  END IF;
  RETURN (SELECT to_jsonb(s) - 'token_hash' FROM public.assinatura_solicitacoes s
           WHERE s.token_hash = public.assinatura_hash_token(p_token));
END;
$fn$;

-- ── CPF (5 erros bloqueiam por 24 h) ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.assinatura_cpf_conferir(
  p_solicitacao_id uuid,
  p_cpf            text,
  p_origem         jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_cpf      text := (SELECT s.colaborador_cpf FROM public.assinatura_solicitacoes s WHERE s.id = p_solicitacao_id);
  v_bloq     timestamptz := (SELECT s.bloqueado_ate FROM public.assinatura_solicitacoes s WHERE s.id = p_solicitacao_id);
  v_tent     int := (SELECT s.tentativas_cpf FROM public.assinatura_solicitacoes s WHERE s.id = p_solicitacao_id);
  v_status   text := (SELECT s.status FROM public.assinatura_solicitacoes s WHERE s.id = p_solicitacao_id);
  v_digitado text := regexp_replace(COALESCE(p_cpf, ''), '[^0-9]', '', 'g');
BEGIN
  IF v_cpf IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'solicitacao_nao_encontrada');
  END IF;
  IF v_status NOT IN ('enviado', 'visualizado') THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'solicitacao_inativa', 'status', v_status);
  END IF;
  IF v_bloq IS NOT NULL AND v_bloq > now() THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'bloqueado', 'bloqueado_ate', v_bloq);
  END IF;

  IF v_digitado = regexp_replace(v_cpf, '[^0-9]', '', 'g') THEN
    UPDATE public.assinatura_solicitacoes
       SET tentativas_cpf = 0, bloqueado_ate = NULL,
           autenticacao = autenticacao || jsonb_build_object('cpf_validado', true, 'cpf_validado_em', now())
     WHERE id = p_solicitacao_id;
    PERFORM public.assinatura_evento(p_solicitacao_id, 'cpf_ok', 'colaborador', NULL, '{}'::jsonb, p_origem);
    RETURN jsonb_build_object('ok', true);
  END IF;

  v_tent := COALESCE(v_tent, 0) + 1;
  UPDATE public.assinatura_solicitacoes
     SET tentativas_cpf = v_tent,
         bloqueado_ate = CASE WHEN v_tent >= 5 THEN now() + interval '24 hours' ELSE NULL END
   WHERE id = p_solicitacao_id;
  PERFORM public.assinatura_evento(p_solicitacao_id, 'cpf_falhou', 'colaborador', NULL,
                                   jsonb_build_object('tentativa', v_tent), p_origem);
  IF v_tent >= 5 THEN
    PERFORM public.assinatura_evento(p_solicitacao_id, 'bloqueado', 'sistema', NULL,
                                     jsonb_build_object('motivo', 'cpf_errado_5x'), p_origem);
    RETURN jsonb_build_object('ok', false, 'erro', 'bloqueado', 'tentativas', v_tent);
  END IF;
  RETURN jsonb_build_object('ok', false, 'erro', 'cpf_nao_confere', 'restantes', 5 - v_tent);
END;
$fn$;

-- ── Código de uso único (só o hash; 10 min; 5 tentativas) ──────────────────
CREATE OR REPLACE FUNCTION public.assinatura_otp_registrar(
  p_solicitacao_id    uuid,
  p_codigo_hash       text,
  p_canal             text DEFAULT 'email',
  p_destino_mascarado text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_tenant uuid := (SELECT s.tenant_id FROM public.assinatura_solicitacoes s WHERE s.id = p_solicitacao_id);
  v_cpf_ok boolean := (SELECT COALESCE((s.autenticacao->>'cpf_validado')::boolean, false)
                         FROM public.assinatura_solicitacoes s WHERE s.id = p_solicitacao_id);
  v_ultimo timestamptz := (SELECT max(o.criado_em) FROM public.assinatura_otps o WHERE o.solicitacao_id = p_solicitacao_id);
  v_hora   int := (SELECT count(*) FROM public.assinatura_otps o
                    WHERE o.solicitacao_id = p_solicitacao_id AND o.criado_em > now() - interval '1 hour');
BEGIN
  IF v_tenant IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'solicitacao_nao_encontrada');
  END IF;
  IF NOT COALESCE(v_cpf_ok, false) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'cpf_primeiro');
  END IF;
  IF COALESCE(p_codigo_hash, '') !~ '^[0-9a-f]{64}$' THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'codigo_invalido');
  END IF;
  IF v_ultimo IS NOT NULL AND v_ultimo > now() - interval '60 seconds' THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'aguarde_um_minuto');
  END IF;
  IF v_hora >= 5 THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'limite_de_codigos');
  END IF;

  -- Só o último código vale.
  UPDATE public.assinatura_otps SET expira_em = now()
   WHERE solicitacao_id = p_solicitacao_id AND usado_em IS NULL AND expira_em > now();
  INSERT INTO public.assinatura_otps (tenant_id, solicitacao_id, codigo_hash, canal, destino_mascarado, expira_em)
  VALUES (v_tenant, p_solicitacao_id, p_codigo_hash, COALESCE(p_canal, 'email'), p_destino_mascarado,
          now() + interval '10 minutes');
  PERFORM public.assinatura_evento(p_solicitacao_id, 'otp_enviado', 'sistema', NULL,
    jsonb_build_object('canal', COALESCE(p_canal, 'email'), 'destino', p_destino_mascarado));
  RETURN jsonb_build_object('ok', true, 'expira_em', now() + interval '10 minutes');
END;
$fn$;

CREATE OR REPLACE FUNCTION public.assinatura_otp_validar(
  p_solicitacao_id uuid,
  p_codigo_hash    text,
  p_origem         jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_otp   uuid := (SELECT o.id FROM public.assinatura_otps o
                    WHERE o.solicitacao_id = p_solicitacao_id AND o.usado_em IS NULL AND o.expira_em > now()
                    ORDER BY o.criado_em DESC LIMIT 1);
  v_hash  text;
  v_tent  int;
  v_canal text;
  v_dest  text;
  v_ev    uuid;
BEGIN
  IF v_otp IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'codigo_expirado');
  END IF;
  v_hash  := (SELECT o.codigo_hash FROM public.assinatura_otps o WHERE o.id = v_otp);
  v_tent  := (SELECT o.tentativas FROM public.assinatura_otps o WHERE o.id = v_otp);
  v_canal := (SELECT o.canal FROM public.assinatura_otps o WHERE o.id = v_otp);
  v_dest  := (SELECT o.destino_mascarado FROM public.assinatura_otps o WHERE o.id = v_otp);
  IF v_tent >= 5 THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'codigo_bloqueado');
  END IF;

  IF lower(COALESCE(p_codigo_hash, '')) = v_hash THEN
    UPDATE public.assinatura_otps SET usado_em = now() WHERE id = v_otp;
    v_ev := public.assinatura_evento(p_solicitacao_id, 'otp_ok', 'colaborador', NULL,
                                     jsonb_build_object('canal', v_canal, 'destino', v_dest), p_origem);
    UPDATE public.assinatura_solicitacoes
       SET autenticacao = autenticacao || jsonb_build_object(
             'otp_validado_em', now(), 'otp_canal', v_canal, 'otp_destino', v_dest, 'otp_evento_id', v_ev)
     WHERE id = p_solicitacao_id;
    RETURN jsonb_build_object('ok', true);
  END IF;

  UPDATE public.assinatura_otps SET tentativas = tentativas + 1 WHERE id = v_otp;
  UPDATE public.assinatura_solicitacoes SET tentativas_otp = tentativas_otp + 1 WHERE id = p_solicitacao_id;
  PERFORM public.assinatura_evento(p_solicitacao_id, 'otp_falhou', 'colaborador', NULL,
                                   jsonb_build_object('tentativa', v_tent + 1), p_origem);
  RETURN jsonb_build_object('ok', false, 'erro', 'codigo_nao_confere', 'restantes', greatest(0, 4 - v_tent));
END;
$fn$;

-- ── Consentimento LGPD ou recusa da câmera ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.assinatura_registrar_consentimento(p_solicitacao_id uuid, p_dados jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_sol  jsonb := (SELECT to_jsonb(s) FROM public.assinatura_solicitacoes s WHERE s.id = p_solicitacao_id);
  v_res  jsonb;
BEGIN
  IF v_sol IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'solicitacao_nao_encontrada');
  END IF;
  IF (v_sol->'autenticacao'->>'otp_validado_em') IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'otp_primeiro');
  END IF;

  IF COALESCE((p_dados->>'recusou')::boolean, false) THEN
    UPDATE public.assinatura_solicitacoes
       SET autenticacao = autenticacao || jsonb_build_object('sem_prova_vida', true, 'prova_vida_recusada_em', now())
     WHERE id = p_solicitacao_id;
    PERFORM public.assinatura_evento(p_solicitacao_id, 'prova_vida_recusada', 'colaborador', NULL,
      jsonb_build_object('motivo', 'recusou_camera', 'versao_texto', p_dados->>'versao_texto'), p_dados->'origem');
    RETURN jsonb_build_object('ok', true, 'sem_prova_vida', true);
  END IF;

  v_res := public.registrar_consentimento_biometrico(jsonb_build_object(
    'tenant_id', v_sol->>'tenant_id', 'contexto', v_sol->>'contexto', 'documento_ref', p_solicitacao_id::text,
    'signatario_nome', v_sol->>'colaborador_nome', 'signatario_cpf', v_sol->>'colaborador_cpf',
    'finalidade', p_dados->>'finalidade', 'versao_texto', p_dados->>'versao_texto',
    'aceito', true, 'origem', p_dados->'origem'));
  UPDATE public.assinatura_solicitacoes
     SET consentimento_id = (v_res->>'id')::uuid,
         autenticacao = (autenticacao - 'sem_prova_vida') || jsonb_build_object('consentimento_versao', p_dados->>'versao_texto')
   WHERE id = p_solicitacao_id;
  PERFORM public.assinatura_evento(p_solicitacao_id, 'consentimento', 'colaborador', NULL,
    jsonb_build_object('consentimento_id', v_res->>'id', 'versao_texto', p_dados->>'versao_texto'), p_dados->'origem');
  RETURN jsonb_build_object('ok', true, 'consentimento_id', v_res->>'id');
END;
$fn$;

-- ── Prova de vida (quadros já no bucket privado de evidências) ─────────────
CREATE OR REPLACE FUNCTION public.assinatura_registrar_evidencia(p_solicitacao_id uuid, p_dados jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_cons uuid := (SELECT s.consentimento_id FROM public.assinatura_solicitacoes s WHERE s.id = p_solicitacao_id);
  v_n    int := COALESCE(jsonb_array_length(CASE WHEN jsonb_typeof(p_dados->'frames_refs') = 'array'
                                                 THEN p_dados->'frames_refs' END), 0);
BEGIN
  IF v_cons IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'consentimento_primeiro');
  END IF;
  IF v_n = 0 OR COALESCE(p_dados->>'metodo_liveness', '') = '' THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'evidencia_incompleta');
  END IF;
  UPDATE public.assinatura_solicitacoes
     SET autenticacao = autenticacao || jsonb_build_object('prova_vida', jsonb_build_object(
           'metodo_liveness', p_dados->>'metodo_liveness',
           'versao_detector', p_dados->>'versao_detector',
           'frames_refs', p_dados->'frames_refs',
           'liveness_data', p_dados->'liveness_data',
           'em', now()))
   WHERE id = p_solicitacao_id;
  PERFORM public.assinatura_evento(p_solicitacao_id, 'prova_vida_ok', 'colaborador', NULL,
    jsonb_build_object('quadros', v_n, 'metodo', p_dados->>'metodo_liveness',
                       'versao_detector', p_dados->>'versao_detector'), p_dados->'origem');
  RETURN jsonb_build_object('ok', true);
END;
$fn$;

-- ── Concluir (tudo numa transação) ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.assinatura_concluir(p_dados jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_id       uuid := NULLIF(p_dados->>'solicitacao_id', '')::uuid;
  v_decisao  text := COALESCE(p_dados->>'decisao', '');
  v_texto    text := NULLIF(btrim(COALESCE(p_dados->>'texto', '')), '');
  v_sol      jsonb;
  v_aut      jsonb;
  v_sem_pv   boolean;
  v_pv       jsonb;
  v_trilha   jsonb;
  v_doc      jsonb;
  v_doc_id   uuid;
  v_novo_st  text;
  v_assinado_sha text := lower(COALESCE(p_dados->>'assinado_sha256', ''));
  v_colab_uuid uuid;
BEGIN
  IF v_id IS NULL OR v_decisao NOT IN ('assinado', 'assinado_com_ressalva', 'contestado') THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'dados_incompletos');
  END IF;
  PERFORM 1 FROM public.assinatura_solicitacoes s WHERE s.id = v_id FOR UPDATE;
  v_sol := (SELECT to_jsonb(s) FROM public.assinatura_solicitacoes s WHERE s.id = v_id);
  IF v_sol IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'solicitacao_nao_encontrada');
  END IF;
  IF (v_sol->>'status') NOT IN ('enviado', 'visualizado') THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'solicitacao_inativa', 'status', v_sol->>'status');
  END IF;
  IF (v_sol->>'expira_em')::timestamptz < now() THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'expirado');
  END IF;

  v_aut := COALESCE(v_sol->'autenticacao', '{}'::jsonb);
  IF NOT COALESCE((v_aut->>'cpf_validado')::boolean, false) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_cpf');
  END IF;
  IF (v_aut->>'otp_validado_em') IS NULL AND (v_aut->>'login_user_id') IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_otp');
  END IF;
  IF v_decisao IN ('assinado_com_ressalva', 'contestado') AND v_texto IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'texto_obrigatorio');
  END IF;

  v_sem_pv := COALESCE((v_aut->>'sem_prova_vida')::boolean, false);
  v_pv := v_aut->'prova_vida';
  IF v_decisao <> 'contestado' THEN
    -- Prova de vida é obrigatória; a única saída é a recusa registrada da câmera.
    IF NOT v_sem_pv AND ((v_sol->>'consentimento_id') IS NULL OR v_pv IS NULL) THEN
      RETURN jsonb_build_object('ok', false, 'erro', 'sem_prova_vida');
    END IF;
    IF v_assinado_sha !~ '^[0-9a-f]{64}$' OR COALESCE(p_dados->>'assinado_path', '') = ''
       OR COALESCE(p_dados->>'documento_storage_path', '') = '' THEN
      RETURN jsonb_build_object('ok', false, 'erro', 'pdf_assinado_ausente');
    END IF;
  END IF;

  -- Trilha selada no servidor: conteúdo = hash do PDF congelado; assinatura =
  -- cpf|decisão|hash do texto|evento do código.
  v_trilha := public.registrar_assinatura_trilha(jsonb_build_object(
    'tenant_id', v_sol->>'tenant_id', 'contexto', v_sol->>'contexto', 'documento_ref', v_id::text,
    'signatario_nome', v_sol->>'colaborador_nome', 'signatario_papel', 'colaborador',
    'signatario_cpf', v_sol->>'colaborador_cpf', 'cpf_validado', true,
    'metodo_liveness', CASE WHEN v_sem_pv OR v_pv IS NULL THEN 'sem_prova_vida_recusou_camera'
                            ELSE v_pv->>'metodo_liveness' END,
    'versao_detector', v_pv->>'versao_detector',
    'conteudo', v_sol->>'original_sha256',
    'assinatura', concat_ws('|', v_sol->>'colaborador_cpf', v_decisao,
                            CASE WHEN v_texto IS NULL THEN '' ELSE encode(public.digest(v_texto, 'sha256'), 'hex') END,
                            COALESCE(v_aut->>'otp_evento_id', v_aut->>'login_user_id', '')),
    'versao_consentimento', v_aut->>'consentimento_versao',
    'consentimento_id', v_sol->>'consentimento_id',
    'frames_refs', COALESCE(v_pv->'frames_refs', '[]'::jsonb),
    'liveness_data', v_pv->'liveness_data',
    'origem', p_dados->'origem'));

  -- O selo que a borda imprimiu no manifesto tem de ser o mesmo da trilha.
  IF COALESCE(p_dados->>'selo', '') <> '' AND (p_dados->>'selo') IS DISTINCT FROM (v_trilha->>'assinatura_hash') THEN
    RAISE EXCEPTION 'Selo divergente entre o manifesto e a trilha.' USING ERRCODE = 'data_exception';
  END IF;

  IF v_decisao <> 'contestado' THEN
    v_colab_uuid := CASE WHEN COALESCE(v_sol->>'colaborador_id', '') ~ '^[0-9a-fA-F-]{36}$'
                         THEN (v_sol->>'colaborador_id')::uuid END;
    v_doc := public.arquivar_documento_servidor(jsonb_build_object(
      'tenant_id', v_sol->>'tenant_id', 'empresa_id', v_sol->>'empresa_id',
      'user_nome', 'Assinatura eletrônica',
      'colaborador_id', v_colab_uuid, 'colaborador_nome', v_sol->>'colaborador_nome',
      'colaborador_cpf', v_sol->>'colaborador_cpf',
      'storage_path', p_dados->>'documento_storage_path',
      'file_name', COALESCE(NULLIF(p_dados->>'nome_arquivo', ''), 'Espelho de Ponto assinado.pdf'),
      'tipo', CASE WHEN v_sol->>'contexto' = 'ponto_espelho' THEN 'Espelho de Ponto assinado' ELSE 'Documento assinado' END,
      'mime_type', 'application/pdf',
      'tamanho', COALESCE(NULLIF(p_dados->>'assinado_bytes', '')::int, 0),
      'subpasta_caminho', CASE WHEN v_sol->>'contexto' = 'ponto_espelho'
                               THEN public.assinatura_caminho_jornada(v_sol->>'referencia') END,
      'observacoes', 'Assinatura eletrônica com evidências. Solicitação ' || v_id::text
                     || '. SHA-256 do PDF assinado: ' || v_assinado_sha));
    v_doc_id := (v_doc->>'id')::uuid;
  END IF;

  v_novo_st := v_decisao;
  UPDATE public.assinatura_solicitacoes
     SET status = v_novo_st,
         decisao_texto = v_texto,
         respondido_em = now(),
         assinado_path = NULLIF(p_dados->>'assinado_path', ''),
         assinado_sha256 = NULLIF(v_assinado_sha, ''),
         documento_id = v_doc_id,
         trilha_id = (v_trilha->>'id')::uuid,
         proximo_lembrete_em = NULL,
         autenticacao = autenticacao || jsonb_build_object('geolocalizacao', p_dados->'geolocalizacao')
   WHERE id = v_id;

  IF v_sol->>'contexto' = 'ponto_espelho' AND (v_sol->>'documento_ref_id') IS NOT NULL THEN
    PERFORM set_config('ye.espelho_ciencia', 'on', true);
    UPDATE public.ponto_espelhos
       SET status = CASE v_decisao WHEN 'assinado' THEN 'confirmado'
                                   WHEN 'assinado_com_ressalva' THEN 'ressalva'
                                   ELSE 'contestado' END,
           ressalva_texto = CASE WHEN v_decisao = 'contestado' THEN 'Contestação: ' || v_texto ELSE v_texto END,
           data_confirmacao = CASE WHEN v_decisao = 'contestado' THEN NULL ELSE now() END,
           confirmado_por = 'colaborador',
           ciencia_origem = 'colaborador_eletronica',
           assinatura_hash = CASE WHEN v_decisao = 'contestado' THEN NULL ELSE v_assinado_sha END,
           arquivo_url = COALESCE(NULLIF(p_dados->>'assinado_path', ''), arquivo_url),
           assinatura_solicitacao_id = v_id
     WHERE id = (v_sol->>'documento_ref_id')::uuid;
    PERFORM set_config('ye.espelho_ciencia', 'off', true);
  END IF;

  PERFORM public.assinatura_evento(v_id,
    CASE v_decisao WHEN 'assinado' THEN 'assinado' WHEN 'assinado_com_ressalva' THEN 'ressalva' ELSE 'contestado' END,
    'colaborador', NULL,
    jsonb_build_object('trilha_id', v_trilha->>'id', 'assinatura_hash', v_trilha->>'assinatura_hash',
                       'assinado_sha256', NULLIF(v_assinado_sha, ''), 'sem_prova_vida', v_sem_pv),
    p_dados->'origem');
  IF v_doc_id IS NOT NULL THEN
    PERFORM public.assinatura_evento(v_id, 'arquivado', 'sistema', NULL,
      jsonb_build_object('documento_id', v_doc_id, 'pasta_id', v_doc->>'pasta_id'));
  END IF;

  RETURN jsonb_build_object('ok', true, 'status', v_novo_st, 'trilha_id', v_trilha->>'id',
                            'assinatura_hash', v_trilha->>'assinatura_hash', 'assinado_em', v_trilha->>'assinado_em',
                            'documento_id', v_doc_id);
END;
$fn$;

-- ── Cancelar ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.assinatura_cancelar(p_solicitacao_id uuid, p_motivo text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_tenant uuid := (SELECT s.tenant_id FROM public.assinatura_solicitacoes s WHERE s.id = p_solicitacao_id);
  v_cpf    text := (SELECT s.colaborador_cpf FROM public.assinatura_solicitacoes s WHERE s.id = p_solicitacao_id);
  v_status text := (SELECT s.status FROM public.assinatura_solicitacoes s WHERE s.id = p_solicitacao_id);
  v_ref    uuid := (SELECT s.documento_ref_id FROM public.assinatura_solicitacoes s WHERE s.id = p_solicitacao_id);
  v_ctx    text := (SELECT s.contexto FROM public.assinatura_solicitacoes s WHERE s.id = p_solicitacao_id);
BEGIN
  IF v_tenant IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'solicitacao_nao_encontrada');
  END IF;
  IF auth.uid() IS NOT NULL AND NOT public.assinatura_chamada_do_servico()
     AND NOT public.assinatura_rh_pode_gerir(v_tenant, v_cpf) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_permissao');
  END IF;
  IF v_status NOT IN ('preparando', 'na_fila', 'enviado', 'visualizado') THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'solicitacao_inativa', 'status', v_status);
  END IF;

  UPDATE public.assinatura_solicitacoes
     SET status = 'cancelado', cancelado_motivo = COALESCE(NULLIF(btrim(p_motivo), ''), 'cancelado_pelo_rh'),
         cancelado_em = now(), token_hash = NULL, proximo_lembrete_em = NULL
   WHERE id = p_solicitacao_id;
  PERFORM public.assinatura_evento(p_solicitacao_id, 'cancelado',
    CASE WHEN auth.uid() IS NULL THEN 'sistema' ELSE 'rh' END, auth.uid(),
    jsonb_build_object('motivo', COALESCE(NULLIF(btrim(p_motivo), ''), 'cancelado_pelo_rh')));

  -- O espelho volta a "gerado" se ainda estava só enviado por esta solicitação.
  IF v_ctx = 'ponto_espelho' AND v_ref IS NOT NULL THEN
    UPDATE public.ponto_espelhos
       SET status = 'gerado'
     WHERE id = v_ref AND status = 'enviado' AND ciencia_origem IS NULL
       AND assinatura_solicitacao_id = p_solicitacao_id;
  END IF;
  RETURN jsonb_build_object('ok', true);
END;
$fn$;

-- ── Reabertura: também cancela as solicitações ativas da competência ───────
CREATE OR REPLACE FUNCTION public.ponto_reabrir_competencia(
  p_tenant_id   uuid,
  p_empresa_id  uuid,
  p_competencia text,
  p_motivo      text,
  p_por         text DEFAULT NULL,
  p_por_nome    text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid        uuid := auth.uid();
  v_alcada     boolean := false;
  v_fech_id    uuid;
  v_fech_st    text;
  v_versao     int;
  v_qtd        int := 0;
  v_retirados  int := 0;
  v_canceladas int := 0;
  v_sol        uuid;
BEGIN
  IF p_motivo IS NULL OR btrim(p_motivo) = '' THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'motivo_obrigatorio');
  END IF;

  IF v_uid IS NOT NULL AND p_tenant_id IS DISTINCT FROM public.get_user_tenant_id()
     AND NOT COALESCE(public.is_superadmin(v_uid), false) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_alcada_para_reabrir');
  END IF;

  v_fech_id := (
    SELECT f.id FROM public.ponto_fechamentos f
     WHERE f.tenant_id = p_tenant_id
       AND f.competencia = p_competencia
       AND (p_empresa_id IS NULL OR f.empresa_id IS NOT DISTINCT FROM p_empresa_id)
     ORDER BY f.data_fechamento DESC NULLS LAST
     LIMIT 1);
  IF v_fech_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'competencia_sem_fechamento');
  END IF;
  v_fech_st := (SELECT COALESCE(f.status, '') FROM public.ponto_fechamentos f WHERE f.id = v_fech_id);
  IF v_fech_st <> 'fechado' THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'competencia_nao_esta_fechada', 'status_atual', v_fech_st);
  END IF;

  IF v_uid IS NULL THEN
    v_alcada := true;
  ELSE
    v_alcada := public.has_role(v_uid, 'manager'::public.app_role)
             OR public.has_role(v_uid, 'admin'::public.app_role)
             OR public.has_role(v_uid, 'owner'::public.app_role)
             OR public.has_role(v_uid, 'superadmin'::public.app_role)
             OR COALESCE(public.is_superadmin(v_uid), false);
  END IF;
  IF NOT COALESCE(v_alcada, false) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_alcada_para_reabrir');
  END IF;

  v_versao := (
    SELECT COALESCE(max(h.versao), 0) + 1 FROM public.ponto_espelhos_historico h
     WHERE h.tenant_id = p_tenant_id AND h.competencia = p_competencia
       AND h.empresa_id IS NOT DISTINCT FROM p_empresa_id);

  INSERT INTO public.ponto_espelhos_historico
    (tenant_id, empresa_id, competencia, colaborador_cpf, colaborador_nome,
     versao, espelho_snapshot, motivo_reabertura, reaberto_por, reaberto_por_nome)
  SELECT e.tenant_id, e.empresa_id, e.competencia, e.colaborador_cpf, e.colaborador_nome,
         v_versao, to_jsonb(e.*), p_motivo, p_por, p_por_nome
  FROM public.ponto_espelhos e
  WHERE e.tenant_id = p_tenant_id AND e.competencia = p_competencia
    AND (p_empresa_id IS NULL OR e.empresa_id IS NOT DISTINCT FROM p_empresa_id);
  GET DIAGNOSTICS v_qtd = ROW_COUNT;

  -- O documento enviado para assinatura deixa de valer: os números vão mudar.
  FOR v_sol IN
    SELECT s.id FROM public.assinatura_solicitacoes s
     WHERE s.tenant_id = p_tenant_id AND s.contexto = 'ponto_espelho' AND s.referencia = p_competencia
       AND s.status IN ('preparando', 'na_fila', 'enviado', 'visualizado')
       AND (p_empresa_id IS NULL OR s.empresa_id IS NOT DISTINCT FROM p_empresa_id)
  LOOP
    UPDATE public.assinatura_solicitacoes
       SET status = 'cancelado', cancelado_motivo = 'competencia_reaberta', cancelado_em = now(),
           token_hash = NULL, proximo_lembrete_em = NULL
     WHERE id = v_sol;
    PERFORM public.assinatura_evento(v_sol, 'cancelado', 'sistema', v_uid,
                                     jsonb_build_object('motivo', 'competencia_reaberta'));
    v_canceladas := v_canceladas + 1;
  END LOOP;

  DELETE FROM public.ponto_espelhos e
   WHERE e.tenant_id = p_tenant_id AND e.competencia = p_competencia
     AND (p_empresa_id IS NULL OR e.empresa_id IS NOT DISTINCT FROM p_empresa_id)
     AND e.ciencia_origem IS NULL
     AND COALESCE(e.status, '') NOT IN ('confirmado', 'assinado', 'ressalva')
     AND e.data_confirmacao IS NULL
     AND COALESCE(e.assinatura_hash, '') = ''
     AND NULLIF(btrim(COALESCE(e.ressalva_texto, '')), '') IS NULL;
  GET DIAGNOSTICS v_retirados = ROW_COUNT;

  UPDATE public.ponto_fechamentos
     SET status = 'reaberto',
         reaberto_em = now(),
         reaberto_por = p_por,
         reaberto_por_nome = p_por_nome,
         motivo_reabertura = p_motivo,
         updated_at = now()
   WHERE id = v_fech_id;

  BEGIN
    INSERT INTO public.ponto_audit_log
      (tenant_id, tabela_origem, registro_id, acao, dados_anteriores, dados_novos, usuario_id)
    VALUES (p_tenant_id, 'ponto_fechamentos', v_fech_id, 'UPDATE',
            jsonb_build_object('status', 'fechado', 'competencia', p_competencia),
            jsonb_build_object('evento', 'REABERTURA', 'status', 'reaberto', 'competencia', p_competencia,
                               'motivo', p_motivo, 'por', p_por, 'por_nome', p_por_nome,
                               'espelhos_arquivados', v_qtd, 'espelhos_sem_ciencia_retirados', v_retirados,
                               'assinaturas_canceladas', v_canceladas, 'versao_arquivada', v_versao),
            v_uid);
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN jsonb_build_object(
    'ok', true,
    'competencia', p_competencia,
    'espelhos_arquivados', v_qtd,
    'espelhos_sem_ciencia_retirados', v_retirados,
    'assinaturas_canceladas', v_canceladas,
    'versao_arquivada', v_versao,
    'status', 'reaberto'
  );
END;
$fn$;

-- ── Ciência em papel: guarda em Jornada/AAAA/MM-Mês e cancela o envio ativo ─
CREATE OR REPLACE FUNCTION public.ponto_espelho_registrar_ciencia_papel(
  p_espelho_id   uuid,
  p_documento_id uuid,
  p_ressalva     text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid       uuid := auth.uid();
  v_tenant    uuid;
  v_empresa   uuid;
  v_cpf       text;
  v_status    text;
  v_origem    text;
  v_comp      text;
  v_doc_path  text;
  v_doc_cpf   text;
  v_doc_pasta uuid;
  v_colab_pasta uuid;
  v_jornada   uuid;
  v_ressalva  text := NULLIF(btrim(COALESCE(p_ressalva, '')), '');
  v_novo      text;
  v_nome_rh   text;
  v_sol       uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'nao_autenticado');
  END IF;

  v_tenant := (SELECT e.tenant_id FROM public.ponto_espelhos e WHERE e.id = p_espelho_id);
  IF v_tenant IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'espelho_nao_encontrado');
  END IF;
  v_empresa := (SELECT e.empresa_id FROM public.ponto_espelhos e WHERE e.id = p_espelho_id);
  v_cpf     := (SELECT regexp_replace(COALESCE(e.colaborador_cpf, ''), '[^0-9]', '', 'g') FROM public.ponto_espelhos e WHERE e.id = p_espelho_id);
  v_status  := (SELECT COALESCE(e.status, 'gerado') FROM public.ponto_espelhos e WHERE e.id = p_espelho_id);
  v_origem  := (SELECT e.ciencia_origem FROM public.ponto_espelhos e WHERE e.id = p_espelho_id);
  v_comp    := (SELECT e.competencia FROM public.ponto_espelhos e WHERE e.id = p_espelho_id);

  IF v_tenant IS DISTINCT FROM public.get_user_tenant_id() THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'espelho_de_outra_empresa');
  END IF;
  IF NOT public.perfil_permite_modulo(v_tenant, VARIADIC ARRAY['ponto', 'colaboradores'])
     OR NOT public.perfil_escreve(v_tenant, ARRAY['ponto', 'colaboradores'], ARRAY['editar', 'aprovar'], v_cpf) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_permissao');
  END IF;
  -- Sem ciência ainda, ou contestado pelo colaborador (o papel assinado resolve).
  IF NOT ((v_origem IS NULL AND v_status IN ('gerado', 'enviado')) OR v_status = 'contestado') THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'espelho_ja_tem_ciencia');
  END IF;

  v_doc_path  := (SELECT d.storage_path FROM public.documentos d WHERE d.id = p_documento_id AND d.tenant_id = v_tenant);
  v_doc_cpf   := (SELECT regexp_replace(COALESCE(d.colaborador_cpf, ''), '[^0-9]', '', 'g')
                    FROM public.documentos d WHERE d.id = p_documento_id AND d.tenant_id = v_tenant);
  v_doc_pasta := (SELECT d.pasta_id FROM public.documentos d WHERE d.id = p_documento_id AND d.tenant_id = v_tenant);
  IF p_documento_id IS NULL OR v_doc_path IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'anexo_obrigatorio');
  END IF;
  IF COALESCE(v_doc_cpf, '') <> '' AND v_doc_cpf <> v_cpf THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'anexo_de_outro_colaborador');
  END IF;

  v_novo := CASE WHEN v_ressalva IS NULL THEN 'confirmado' ELSE 'ressalva' END;
  v_nome_rh := (SELECT p.nome_completo FROM public.profiles p WHERE p.user_id = v_uid LIMIT 1);

  -- O papel vai para Jornada/AAAA/MM-Mês dentro da pasta do colaborador.
  v_colab_pasta := (SELECT CASE WHEN p.tipo = 'colaborador' THEN p.id ELSE p.pasta_pai_id END
                      FROM public.documento_pastas p WHERE p.id = v_doc_pasta);
  IF v_colab_pasta IS NOT NULL
     AND EXISTS (SELECT 1 FROM public.documento_pastas p WHERE p.id = v_colab_pasta AND p.tipo = 'colaborador') THEN
    v_jornada := public.documento_pasta_garantir_caminho(v_tenant, v_empresa, v_colab_pasta,
                   public.assinatura_caminho_jornada(v_comp), v_uid, v_nome_rh);
    UPDATE public.documentos SET pasta_id = v_jornada WHERE id = p_documento_id;
  END IF;

  -- Envio eletrônico ainda aberto deixa de valer: a ciência veio pelo papel.
  FOR v_sol IN
    SELECT s.id FROM public.assinatura_solicitacoes s
     WHERE s.contexto = 'ponto_espelho' AND s.documento_ref_id = p_espelho_id
       AND s.status IN ('preparando', 'na_fila', 'enviado', 'visualizado')
  LOOP
    UPDATE public.assinatura_solicitacoes
       SET status = 'cancelado', cancelado_motivo = 'ciencia_em_papel', cancelado_em = now(),
           token_hash = NULL, proximo_lembrete_em = NULL
     WHERE id = v_sol;
    PERFORM public.assinatura_evento(v_sol, 'cancelado', 'rh', v_uid,
                                     jsonb_build_object('motivo', 'ciencia_em_papel'));
  END LOOP;

  PERFORM set_config('ye.espelho_ciencia', 'on', true);
  UPDATE public.ponto_espelhos
     SET status           = v_novo,
         ressalva_texto   = v_ressalva,
         data_confirmacao = now(),
         confirmado_por   = 'colaborador',
         ciencia_origem   = 'papel_digitalizado',
         arquivo_url      = v_doc_path
   WHERE id = p_espelho_id;
  PERFORM set_config('ye.espelho_ciencia', 'off', true);

  BEGIN
    INSERT INTO public.ponto_audit_log
      (tenant_id, tabela_origem, registro_id, acao, dados_anteriores, dados_novos, usuario_id)
    VALUES (v_tenant, 'ponto_espelhos', p_espelho_id, 'UPDATE',
            jsonb_build_object('status', v_status),
            jsonb_build_object('evento', 'ciencia_papel_digitalizado', 'status', v_novo,
                               'documento_id', p_documento_id, 'com_ressalva', v_ressalva IS NOT NULL,
                               'registrado_por_nome', v_nome_rh),
            v_uid);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'ponto_espelho_registrar_ciencia_papel: trilha nao gravada (%)', SQLERRM;
  END;

  RETURN jsonb_build_object('ok', true, 'status', v_novo, 'ciencia_origem', 'papel_digitalizado', 'pasta_id', v_jornada);
END;
$fn$;

-- ── Permissões ─────────────────────────────────────────────────────────────
DO $perm$
DECLARE v_f text;
BEGIN
  -- Só a chave de serviço (funções de borda).
  FOREACH v_f IN ARRAY ARRAY[
    'public.assinatura_hash_token(text)',
    'public.assinatura_evento(uuid,text,text,uuid,jsonb,jsonb)',
    'public.assinatura_criar_solicitacao(jsonb)',
    'public.assinatura_emitir_token(uuid,text,uuid,text)',
    'public.assinatura_registrar_envio(uuid,text,boolean,text,boolean,jsonb)',
    'public.assinatura_abrir(text,jsonb)',
    'public.assinatura_por_token(text)',
    'public.assinatura_cpf_conferir(uuid,text,jsonb)',
    'public.assinatura_otp_registrar(uuid,text,text,text)',
    'public.assinatura_otp_validar(uuid,text,jsonb)',
    'public.assinatura_registrar_consentimento(uuid,jsonb)',
    'public.assinatura_registrar_evidencia(uuid,jsonb)',
    'public.assinatura_concluir(jsonb)'] LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', v_f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', v_f);
  END LOOP;
  -- RH logado (as funções conferem empresa e perfil).
  FOREACH v_f IN ARRAY ARRAY[
    'public.assinatura_rh_pode_gerir(uuid,text)',
    'public.assinatura_rh_novo_link(uuid)',
    'public.assinatura_cancelar(uuid,text)',
    'public.ponto_reabrir_competencia(uuid,uuid,text,text,text,text)',
    'public.ponto_espelho_registrar_ciencia_papel(uuid,uuid,text)'] LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', v_f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', v_f);
  END LOOP;
END $perm$;

COMMENT ON FUNCTION public.assinatura_concluir(jsonb) IS
  'Conclui a assinatura numa transacao: confere CPF, codigo e prova de vida (ou a recusa registrada da camera), sela a trilha no servidor (conteudo = hash do PDF congelado), arquiva o PDF assinado em Documentos (Jornada/AAAA/MM-Mes) e grava a ciencia do colaborador no espelho (colaborador_eletronica). Contestacao nao assina e nao bloqueia o fechamento.';
