-- ============================================================================
-- ESPELHO DE PONTO — ciência antiga do RH (rh_legado) não bloqueia o envio
--
-- DEFEITO: depois da entrega do espelho com assinatura (30/10/2026), os espelhos
-- marcados com ciencia_origem = 'rh_legado' (ciência registrada pelo botão
-- antigo do RH, que não vale como ciência do colaborador) eram tratados como
-- "já tem ciência" e bloqueavam o "Enviar para assinatura" e o "Registrar
-- ciência em papel" (erro espelho_ja_tem_ciencia). Na homologação todos os
-- espelhos de julho/agosto estão assim: nada podia ser enviado.
--
-- REGRA (decisão de 30/10/2026): só a ciência VÁLIDA bloqueia um novo envio ou
-- registro: colaborador_eletronica e papel_digitalizado (e a solicitação ativa,
-- que já era conferida). rh_legado deixa o espelho ir para assinatura e para o
-- papel; a nova ciência SUBSTITUI a antiga (status, ciencia_origem,
-- data_confirmacao, confirmado_por, assinatura_hash, arquivo_url).
--
-- ONDE A CIÊNCIA ANTIGA FICA GUARDADA (padrão da F0/F1, sem tabela nova):
--   * assinatura concluída: evento 'ciencia_legado_substituida' em
--     assinatura_eventos (trilha só de inserção) com dados.ciencia_anterior =
--     os valores antigos, e uma linha em ponto_audit_log (dados_anteriores);
--   * papel registrado: ponto_audit_log, dados_anteriores = valores antigos,
--     dados_novos.substitui_ciencia_rh_legado = true (a F0 já usava esse log).
-- ponto_espelhos_historico NÃO é usado aqui: ele guarda versões de REABERTURA
-- (versao/motivo_reabertura), não troca de ciência.
--
-- O QUE NÃO MUDA
--   * O portão do fechamento e a reabertura continuam aceitando rh_legado como
--     ciência (não reabre nem trava mês fechado).
--   * O gatilho de guarda (ponto_espelho_ciencia_guarda) não muda: ele já deixa
--     passar as funções do servidor que acendem ye.espelho_ciencia.
--   * Enquanto a assinatura de um espelho rh_legado está pendente, o espelho
--     continua com a ciência antiga (status confirmado) até a conclusão.
--
-- Funções redefinidas (CREATE OR REPLACE integral, a partir da versão de
-- 20261030100330; conferido: nenhuma migration injeta blocos no corpo delas):
--   assinatura_criar_solicitacao, assinatura_concluir,
--   ponto_espelho_registrar_ciencia_papel.
-- QA: novo caso ESP-ASS-017; descrições de ESP-ASS-001/004/015 e ESP-CIE-001
-- atualizadas.
--
-- Sem SELECT INTO. Idempotente.
-- ============================================================================

SET lock_timeout = '10s';

-- ── Criar a solicitação: rh_legado não bloqueia ────────────────────────────
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
    -- Só a ciência VÁLIDA bloqueia (do colaborador: eletrônica ou papel assinado).
    -- A ciência antiga do RH (rh_legado) não vale como ciência do colaborador:
    -- o espelho pode ir para assinatura, e a nova ciência substitui a antiga ao
    -- concluir (a antiga fica guardada nos eventos da solicitação).
    IF v_esp_origem IN ('colaborador_eletronica', 'papel_digitalizado') AND v_esp_status <> 'contestado' THEN
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
                       'lote_id', p_dados->>'lote_id', 'ciencia_anterior_origem', v_esp_origem));

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

-- ── Concluir: a ciência do colaborador substitui a rh_legado e a guarda ────
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
  v_esp_ant  jsonb;
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
    -- A ciência que estava no espelho antes desta assinatura (para a trilha).
    v_esp_ant := (SELECT jsonb_build_object(
                    'status', e.status, 'ciencia_origem', e.ciencia_origem,
                    'data_confirmacao', e.data_confirmacao, 'confirmado_por', e.confirmado_por,
                    'assinatura_hash', e.assinatura_hash, 'arquivo_url', e.arquivo_url,
                    'ressalva_texto', e.ressalva_texto, 'assinatura_solicitacao_id', e.assinatura_solicitacao_id)
                    FROM public.ponto_espelhos e WHERE e.id = (v_sol->>'documento_ref_id')::uuid);
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

    -- A ciência antiga do RH (rh_legado) foi substituída pela do colaborador: os
    -- valores antigos ficam na trilha da solicitação (imutável) e no log do Ponto.
    IF (v_esp_ant->>'ciencia_origem') = 'rh_legado' THEN
      PERFORM public.assinatura_evento(v_id, 'ciencia_legado_substituida', 'sistema', NULL,
        jsonb_build_object('ciencia_anterior', v_esp_ant,
                           'ciencia_nova', 'colaborador_eletronica', 'decisao', v_decisao));
      BEGIN
        INSERT INTO public.ponto_audit_log
          (tenant_id, tabela_origem, registro_id, acao, dados_anteriores, dados_novos, usuario_id)
        VALUES ((v_sol->>'tenant_id')::uuid, 'ponto_espelhos', (v_sol->>'documento_ref_id')::uuid, 'UPDATE',
                v_esp_ant,
                jsonb_build_object('evento', 'ciencia_legado_substituida', 'ciencia_origem', 'colaborador_eletronica',
                                   'decisao', v_decisao, 'solicitacao_id', v_id),
                NULL);
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'assinatura_concluir: log do Ponto nao gravado (%)', SQLERRM;
      END;
    END IF;
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

-- ── Ciência em papel: aceita rh_legado e guarda a antiga no log ───────────
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
  v_ant       jsonb;
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
  -- Sem ciência ainda, contestado pelo colaborador (o papel assinado resolve) ou
  -- só com a ciência antiga do RH (rh_legado), que não vale como ciência do
  -- colaborador e é substituída pelo papel (a antiga fica no log do Ponto).
  IF NOT ((v_origem IS NULL AND v_status IN ('gerado', 'enviado'))
          OR v_status = 'contestado'
          OR v_origem = 'rh_legado') THEN
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

  v_ant := (SELECT jsonb_build_object(
              'status', e.status, 'ciencia_origem', e.ciencia_origem,
              'data_confirmacao', e.data_confirmacao, 'confirmado_por', e.confirmado_por,
              'assinatura_hash', e.assinatura_hash, 'arquivo_url', e.arquivo_url,
              'ressalva_texto', e.ressalva_texto, 'assinatura_solicitacao_id', e.assinatura_solicitacao_id)
              FROM public.ponto_espelhos e WHERE e.id = p_espelho_id);

  PERFORM set_config('ye.espelho_ciencia', 'on', true);
  UPDATE public.ponto_espelhos
     SET status           = v_novo,
         ressalva_texto   = v_ressalva,
         data_confirmacao = now(),
         confirmado_por   = 'colaborador',
         ciencia_origem   = 'papel_digitalizado',
         assinatura_hash  = NULL,
         arquivo_url      = v_doc_path
   WHERE id = p_espelho_id;
  PERFORM set_config('ye.espelho_ciencia', 'off', true);

  BEGIN
    INSERT INTO public.ponto_audit_log
      (tenant_id, tabela_origem, registro_id, acao, dados_anteriores, dados_novos, usuario_id)
    VALUES (v_tenant, 'ponto_espelhos', p_espelho_id, 'UPDATE',
            COALESCE(v_ant, jsonb_build_object('status', v_status)),
            jsonb_build_object('evento', 'ciencia_papel_digitalizado', 'status', v_novo,
                               'documento_id', p_documento_id, 'com_ressalva', v_ressalva IS NOT NULL,
                               'registrado_por_nome', v_nome_rh,
                               'substitui_ciencia_rh_legado', v_origem IS NOT DISTINCT FROM 'rh_legado'),
            v_uid);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'ponto_espelho_registrar_ciencia_papel: trilha nao gravada (%)', SQLERRM;
  END;

  RETURN jsonb_build_object('ok', true, 'status', v_novo, 'ciencia_origem', 'papel_digitalizado', 'pasta_id', v_jornada);
END;
$fn$;

-- ── Permissões (as mesmas da entrega de 30/10) ─────────────────────────────
REVOKE EXECUTE ON FUNCTION public.assinatura_criar_solicitacao(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.assinatura_criar_solicitacao(jsonb) TO service_role;
REVOKE EXECUTE ON FUNCTION public.assinatura_concluir(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.assinatura_concluir(jsonb) TO service_role;
REVOKE EXECUTE ON FUNCTION public.ponto_espelho_registrar_ciencia_papel(uuid, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ponto_espelho_registrar_ciencia_papel(uuid, uuid, text) TO authenticated, service_role;

COMMENT ON FUNCTION public.assinatura_concluir(jsonb) IS
  'Conclui a assinatura numa transacao: confere CPF, codigo e prova de vida (ou a recusa registrada da camera), sela a trilha no servidor (conteudo = hash do PDF congelado), arquiva o PDF assinado em Documentos (Jornada/AAAA/MM-Mes) e grava a ciencia do colaborador no espelho (colaborador_eletronica). Se o espelho tinha a ciencia antiga do RH (rh_legado), ela e substituida e os valores antigos ficam no evento ciencia_legado_substituida e no ponto_audit_log. Contestacao nao assina e nao bloqueia o fechamento.';

COMMENT ON FUNCTION public.ponto_espelho_registrar_ciencia_papel(uuid, uuid, text) IS
  'Registra a ciencia do espelho a partir do PAPEL assinado pelo colaborador e digitalizado (anexo obrigatorio, ja arquivado em documentos). Aceita espelho sem ciencia, contestado ou so com a ciencia antiga do RH (rh_legado, substituida; os valores antigos vao para ponto_audit_log). Grava ciencia_origem=papel_digitalizado e confirmado_por=colaborador; quem registrou vai para ponto_audit_log.';

-- ── ESP-ASS-017 ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_esp_ass_017()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r          public.qa_retorno;
  v_claims   text := current_setting('request.jwt.claims', true);
  v_t        uuid := public.qa_sandbox_tenant_id();
  v_comp     text := '2097-07';
  v_nome     text := '[QA-ESP-ASS] Legado 931';
  v_cpf      text;
  v_adm      uuid;
  v_esp      uuid := gen_random_uuid();
  v_sol      uuid := gen_random_uuid();
  v_rh_antigo text := gen_random_uuid()::text;
  v_criar    jsonb;
  v_res      jsonb;
  v_row      jsonb;
  v_ev       jsonb;
  v_de_novo  jsonb;
  v_esp_ele  uuid;
  v_esp_pap  uuid;
  v_bloq_ele jsonb;
  v_bloq_pap jsonb;
  v_esp_leg2 uuid;
  v_doc      uuid;
  v_papel    jsonb;
  v_papel_ele jsonb;
  v_row2     jsonb;
  v_log      jsonb;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM set_config('request.jwt.claims', '', true);

  -- Cenário: competência fechada e espelho com a ciência antiga do RH.
  IF NOT EXISTS (SELECT 1 FROM public.ponto_fechamentos f
                  WHERE f.tenant_id = v_t AND f.competencia = v_comp AND f.empresa_id IS NULL) THEN
    INSERT INTO public.ponto_fechamentos (tenant_id, empresa_id, competencia, status, data_fechamento)
    VALUES (v_t, NULL, v_comp, 'fechado', now());
  END IF;
  v_cpf := public.qa_ponto_admissao(v_nome, 931);
  v_adm := (SELECT a.id FROM public.admissoes a WHERE a.tenant_id = v_t AND a.cpf = v_cpf
             ORDER BY (a.status::text = 'concluido') DESC LIMIT 1);
  INSERT INTO public.ponto_espelhos
    (id, tenant_id, colaborador_id, colaborador_nome, colaborador_cpf, competencia,
     status, ciencia_origem, data_confirmacao, confirmado_por)
  VALUES (v_esp, v_t, v_adm::text, v_nome, v_cpf, v_comp,
          'confirmado', 'rh_legado', now() - interval '30 days', v_rh_antigo);

  r.passo_ordem := 1; r.passo_acao := 'Enviar para assinatura um espelho com a ciência antiga do RH (rh_legado)';
  r.esperado := 'Solicitação criada (rh_legado não bloqueia)';
  PERFORM public.qa_esp_como_servico();
  v_criar := public.assinatura_criar_solicitacao(jsonb_build_object(
    'id', v_sol, 'tenant_id', v_t, 'contexto', 'ponto_espelho', 'documento_ref_id', v_esp,
    'colaborador_id', v_adm, 'colaborador_cpf', v_cpf, 'colaborador_nome', v_nome,
    'email', 'qa-esp-ass-931@sandbox.invalid',
    'original_path', v_t::text || '/ponto_espelho/' || v_sol::text || '/original.pdf',
    'original_sha256', encode(public.digest('qa-original-' || v_sol::text, 'sha256'), 'hex'),
    'original_bytes', 1000, 'link_base', 'https://youreyes.com.br/'));
  IF COALESCE((v_criar->>'ok')::boolean, false) THEN
    PERFORM public.assinatura_registrar_envio(v_sol, 'solicitacao', true);
    PERFORM public.assinatura_emitir_token(v_sol);
  END IF;
  PERFORM set_config('request.jwt.claims', '', true);

  r.passo_ordem := 2; r.passo_acao := 'Colaborador assina (CPF, código, consentimento, prova de vida)';
  r.esperado := 'Ciência passa a colaborador_eletronica; a antiga (rh_legado) fica no evento ciencia_legado_substituida';
  IF COALESCE((v_criar->>'ok')::boolean, false) THEN
    PERFORM public.qa_esp_ass_autenticar(v_sol, v_cpf, 'camera');
    v_res := public.qa_esp_ass_concluir(v_sol, 'assinado');
  END IF;
  v_row := (SELECT to_jsonb(e) FROM public.ponto_espelhos e WHERE e.id = v_esp);
  v_ev  := (SELECT ev.dados FROM public.assinatura_eventos ev
             WHERE ev.solicitacao_id = v_sol AND ev.tipo = 'ciencia_legado_substituida' LIMIT 1);

  r.passo_ordem := 3; r.passo_acao := 'Tentar enviar de novo o mesmo espelho e espelhos com ciência eletrônica ou em papel';
  r.esperado := 'Os três recusados: espelho_ja_tem_ciencia';
  v_esp_ele := public.qa_esp_espelho(v_comp, 932, 'confirmado', 'colaborador_eletronica');
  v_esp_pap := public.qa_esp_espelho(v_comp, 933, 'confirmado', 'papel_digitalizado');
  PERFORM public.qa_esp_como_servico();
  v_de_novo := public.assinatura_criar_solicitacao(jsonb_build_object(
    'tenant_id', v_t, 'contexto', 'ponto_espelho', 'documento_ref_id', v_esp, 'colaborador_cpf', v_cpf,
    'original_path', 'x/original.pdf', 'original_sha256', repeat('b', 64)));
  v_bloq_ele := public.assinatura_criar_solicitacao(jsonb_build_object(
    'tenant_id', v_t, 'contexto', 'ponto_espelho', 'documento_ref_id', v_esp_ele, 'colaborador_cpf', public.qa_cpf(932),
    'original_path', 'x/original.pdf', 'original_sha256', repeat('c', 64)));
  v_bloq_pap := public.assinatura_criar_solicitacao(jsonb_build_object(
    'tenant_id', v_t, 'contexto', 'ponto_espelho', 'documento_ref_id', v_esp_pap, 'colaborador_cpf', public.qa_cpf(933),
    'original_path', 'x/original.pdf', 'original_sha256', repeat('d', 64)));
  PERFORM set_config('request.jwt.claims', '', true);

  r.passo_ordem := 4; r.passo_acao := 'RH registra ciência em papel sobre um espelho rh_legado e sobre um com ciência eletrônica';
  r.esperado := 'rh_legado: aceito, vira papel_digitalizado e a antiga vai para o log; eletrônica: espelho_ja_tem_ciencia';
  v_esp_leg2 := public.qa_esp_espelho(v_comp, 934, 'confirmado', 'rh_legado');
  v_doc := public.qa_novo_documento('qa-esp-ass-017-papel.pdf');
  UPDATE public.documentos SET colaborador_cpf = public.qa_cpf(934) WHERE id = v_doc;
  PERFORM public.qa_esp_rh_logado();
  v_papel     := public.ponto_espelho_registrar_ciencia_papel(v_esp_leg2, v_doc, NULL);
  v_papel_ele := public.ponto_espelho_registrar_ciencia_papel(v_esp_ele, v_doc, NULL);
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  v_row2 := (SELECT to_jsonb(e) FROM public.ponto_espelhos e WHERE e.id = v_esp_leg2);
  v_log  := (SELECT l.dados_anteriores FROM public.ponto_audit_log l
              WHERE l.registro_id = v_esp_leg2 AND l.tabela_origem = 'ponto_espelhos'
                AND l.dados_novos->>'evento' = 'ciencia_papel_digitalizado' LIMIT 1);

  IF NOT COALESCE((v_criar->>'ok')::boolean, false) THEN
    r.situacao := 'falhou'; r.obtido := 'O envio do espelho rh_legado foi recusado: ' || COALESCE(v_criar::text, 'nulo');
  ELSIF NOT COALESCE((v_res->>'ok')::boolean, false) THEN
    r.situacao := 'falhou'; r.obtido := 'A assinatura sobre o espelho rh_legado não concluiu: ' || COALESCE(v_res::text, 'nulo');
  ELSIF (v_row->>'ciencia_origem') IS DISTINCT FROM 'colaborador_eletronica' OR (v_row->>'status') <> 'confirmado'
     OR (v_row->>'confirmado_por') IS DISTINCT FROM 'colaborador'
     OR COALESCE(v_row->>'assinatura_hash', '') = ''
     OR (v_row->>'data_confirmacao')::timestamptz < now() - interval '1 day' THEN
    r.situacao := 'falhou';
    r.obtido := format('A ciência nova não substituiu a antiga: %s / %s / %s', v_row->>'status', v_row->>'ciencia_origem', v_row->>'confirmado_por');
  ELSIF v_ev IS NULL OR (v_ev->'ciencia_anterior'->>'ciencia_origem') IS DISTINCT FROM 'rh_legado'
     OR (v_ev->'ciencia_anterior'->>'confirmado_por') IS DISTINCT FROM v_rh_antigo THEN
    r.situacao := 'falhou'; r.obtido := 'A ciência antiga não ficou preservada na trilha: ' || COALESCE(v_ev::text, 'sem evento');
  ELSIF COALESCE(v_de_novo->>'erro', '') <> 'espelho_ja_tem_ciencia' THEN
    r.situacao := 'falhou'; r.obtido := 'O espelho já assinado devia recusar novo envio e veio ' || COALESCE(v_de_novo::text, 'nulo');
  ELSIF COALESCE(v_bloq_ele->>'erro', '') <> 'espelho_ja_tem_ciencia' THEN
    r.situacao := 'falhou'; r.obtido := 'Espelho com ciência eletrônica devia recusar envio e veio ' || COALESCE(v_bloq_ele::text, 'nulo');
  ELSIF COALESCE(v_bloq_pap->>'erro', '') <> 'espelho_ja_tem_ciencia' THEN
    r.situacao := 'falhou'; r.obtido := 'Espelho com ciência em papel devia recusar envio e veio ' || COALESCE(v_bloq_pap::text, 'nulo');
  ELSIF NOT COALESCE((v_papel->>'ok')::boolean, false) OR (v_row2->>'ciencia_origem') IS DISTINCT FROM 'papel_digitalizado' THEN
    r.situacao := 'falhou'; r.obtido := 'O papel sobre espelho rh_legado devia ser aceito e veio ' || COALESCE(v_papel::text, 'nulo');
  ELSIF (v_log->>'ciencia_origem') IS DISTINCT FROM 'rh_legado' THEN
    r.situacao := 'falhou'; r.obtido := 'A ciência antiga não ficou no log do Ponto ao registrar o papel: ' || COALESCE(v_log::text, 'nulo');
  ELSIF COALESCE(v_papel_ele->>'erro', '') <> 'espelho_ja_tem_ciencia' THEN
    r.situacao := 'falhou'; r.obtido := 'Papel sobre espelho com ciência eletrônica devia ser recusado e veio ' || COALESCE(v_papel_ele::text, 'nulo');
  ELSE
    r.situacao := 'passou';
    r.obtido := 'rh_legado não bloqueia: envio criado, assinatura substituiu a ciência (antiga preservada no evento) e o papel também substitui (antiga no log); eletrônica e papel seguem bloqueando.';
  END IF;
  r.detalhe := jsonb_build_object('criar', v_criar, 'concluir', v_res, 'evento', v_ev, 'papel', v_papel);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  BEGIN PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); EXCEPTION WHEN OTHERS THEN NULL; END;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── Documentação ───────────────────────────────────────────────────────────
DO $doc$
DECLARE v_mod uuid;
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL OR to_regclass('public.qa_modulos') IS NULL THEN
    RAISE NOTICE 'Motor de QA ausente; caso ESP-ASS-017 não documentado.';
    RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'jornada-rotina/ponto' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo jornada-rotina/ponto ausente; caso ESP-ASS-017 não documentado.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'ESP-ASS-017',
   'Ciência antiga do RH (rh_legado) não bloqueia o envio para assinatura nem o papel; a nova ciência substitui a antiga e a antiga fica guardada',
   'feliz', 'critica', 'aprovado', 'api',
   'Súmula 338 do TST (a ciência tem de ser do trabalhador); MP 2.200-2/2001, art. 10, §2º',
   'A ciência registrada pelo botão antigo do RH (rh_legado) não vale como ciência do colaborador. O espelho nessa situação pode ir para assinatura eletrônica e para o registro do papel assinado; ao concluir, a ciência do colaborador substitui a antiga (status, origem, data, confirmado_por, hash, arquivo) e a antiga fica no evento ciencia_legado_substituida da solicitação e no ponto_audit_log. Ciência válida (colaborador_eletronica, papel_digitalizado) continua bloqueando novo envio e novo papel. O portão do fechamento segue aceitando rh_legado.',
   'Cercado de QA; competência 2097-07 fechada; espelho confirmado com ciencia_origem rh_legado e confirmado_por = id do RH.',
   '[{"ordem":1,"acao":"Criar a solicitação de um espelho rh_legado","resultado_esperado":"Criada"},
     {"ordem":2,"acao":"Colaborador assina com CPF, código e prova de vida","resultado_esperado":"Espelho confirmado/colaborador_eletronica/confirmado_por colaborador, com hash; evento ciencia_legado_substituida com a ciência antiga"},
     {"ordem":3,"acao":"Criar de novo no mesmo espelho e em espelhos colaborador_eletronica e papel_digitalizado","resultado_esperado":"espelho_ja_tem_ciencia nos três"},
     {"ordem":4,"acao":"Registrar papel num espelho rh_legado e num colaborador_eletronica","resultado_esperado":"rh_legado vira papel_digitalizado (antiga no ponto_audit_log); eletrônica recusa espelho_ja_tem_ciencia"}]'::jsonb,
   'rh_legado libera envio e papel; ciência válida bloqueia; a antiga nunca some.',
   'Correção de 30/10/2026: na homologação todos os espelhos de jul/ago eram rh_legado e nada podia ser enviado.')
  ON CONFLICT (codigo) DO UPDATE SET
    modulo_id = EXCLUDED.modulo_id, titulo = EXCLUDED.titulo, objetivo = EXCLUDED.objetivo,
    pre_condicoes = EXCLUDED.pre_condicoes, passos = EXCLUDED.passos,
    resultado_esperado = EXCLUDED.resultado_esperado, nivel = EXCLUDED.nivel,
    base_legal = EXCLUDED.base_legal, observacoes = EXCLUDED.observacoes, status = 'aprovado';

  -- Casos afetados: a descrição passa a dizer o que bloqueia de fato.
  UPDATE public.qa_casos_teste
     SET objetivo = 'Assina-se o PDF congelado no envio: sem o hash dele não há solicitação. Um espelho tem no máximo uma solicitação ativa, e só depois da competência fechada. Só a ciência válida do colaborador (colaborador_eletronica ou papel_digitalizado) recusa o envio com espelho_ja_tem_ciencia; a ciência antiga do RH (rh_legado) não bloqueia (ESP-ASS-017).'
   WHERE codigo = 'ESP-ASS-001';
  UPDATE public.qa_casos_teste
     SET objetivo = 'O espelho passa a confirmado com ciencia_origem colaborador_eletronica e confirmado_por colaborador; a trilha guarda o selo e a origem enviada pela borda; o PDF assinado vai para Jornada/AAAA/MM-Mês. Quem recusa a câmera assina com CPF + código e a trilha registra sem_prova_vida_recusou_camera. Se o espelho tinha a ciência antiga do RH (rh_legado), ela é substituída e fica no evento ciencia_legado_substituida (ESP-ASS-017).'
   WHERE codigo = 'ESP-ASS-004';
  UPDATE public.qa_casos_teste
     SET observacoes = 'Teste automático confere o painel e a legenda; o selo Assinado numa linha real é conferido na homologação com massa semeada. O selo "Ciência antiga (RH)" (rh_legado) mostra a ação Enviar enquanto não há envio ativo; com envio ativo, o selo vira Pendente.'
   WHERE codigo = 'ESP-ASS-015';
  UPDATE public.qa_casos_teste
     SET objetivo = 'O antigo botão Confirmar gravava o id do usuário do RH em confirmado_por: a ciência era do RH, não do colaborador. Agora o RH só registra a ciência que o colaborador deu no PAPEL, anexando a digitalização. Vale para espelho sem ciência, contestado ou só com a ciência antiga do RH (rh_legado, que é substituída e vai para o ponto_audit_log); espelho com ciência válida (eletrônica ou papel) recusa com espelho_ja_tem_ciencia.'
   WHERE codigo = 'ESP-CIE-001';

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
      ('ESP-ASS-017', 'qa_caso_esp_ass_017', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentação ESP-ASS-017 não registrada: %', SQLERRM;
END $doc$;
