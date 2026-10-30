-- ============================================================================
-- ASSINATURA — Fatia 1, parte 2: ajustes da fundação ASS-0001
--
-- (a) ORIGEM PELO SERVIDOR QUANDO QUEM CHAMA É A FUNÇÃO DE BORDA.
--     registrar_consentimento_biometrico e registrar_assinatura_trilha tiravam o
--     IP de request.headers. Quando quem chama é uma função de borda (link público,
--     colaborador anônimo), esse é o IP da própria borda. Agora aceitam
--     p_dados.origem (ip, user_agent, assinado_em) SOMENTE quando a chamada vem com
--     a chave de serviço; para qualquer outro chamador a origem continua sendo a
--     dos cabeçalhos (o corpo não prevalece). E pela API (usuário logado) só se
--     grava na própria empresa.
-- (b) SUBPASTAS EM VÁRIOS NÍVEIS.
--     arquivar_documento_servidor aceitava um nível e só as quatro subpastas
--     fixas. Agora aceita subpasta_caminho (lista de pastas, criadas sob demanda,
--     de forma idempotente) sob a pasta do colaborador — ex.: Jornada/2026/
--     10-Outubro. Mesma assinatura da função; o resto do corpo é o mesmo. Pela API
--     (usuário logado) só arquiva na própria empresa.
-- (c) Ajudantes: documento_pasta_garantir_caminho e assinatura_caminho_jornada.
--
-- Funções sem bloco injetado em runtime (conferido). Sem SELECT INTO. Idempotente.
-- ============================================================================

SET lock_timeout = '10s';

-- Quem chama é a chave de serviço (função de borda)?
CREATE OR REPLACE FUNCTION public.assinatura_chamada_do_servico()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $fn$
DECLARE
  v_claims text := NULLIF(current_setting('request.jwt.claims', true), '');
BEGIN
  IF v_claims IS NOT NULL AND COALESCE(v_claims::jsonb->>'role', '') = 'service_role' THEN
    RETURN true;
  END IF;
  RETURN COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role';
EXCEPTION WHEN OTHERS THEN
  RETURN false;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.assinatura_chamada_do_servico() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assinatura_chamada_do_servico() TO authenticated, service_role;

-- Origem a usar: a que a borda mandou (só com a chave de serviço) ou a dos cabeçalhos.
CREATE OR REPLACE FUNCTION public.assinatura_origem_efetiva(p_dados jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $fn$
DECLARE
  v_o jsonb := p_dados->'origem';
  v_quando timestamptz;
BEGIN
  IF public.assinatura_chamada_do_servico() AND jsonb_typeof(v_o) = 'object' THEN
    BEGIN
      v_quando := NULLIF(v_o->>'assinado_em', '')::timestamptz;
    EXCEPTION WHEN OTHERS THEN
      v_quando := NULL;
    END;
    v_quando := COALESCE(v_quando, now());
    -- A hora da borda só vale se estiver perto do relógio do banco (5 min).
    IF abs(extract(epoch FROM (v_quando - now()))) > 300 THEN
      v_quando := now();
    END IF;
    RETURN jsonb_build_object(
      'ip_address', NULLIF(btrim(COALESCE(v_o->>'ip', v_o->>'ip_address', '')), ''),
      'user_agent', NULLIF(btrim(COALESCE(v_o->>'user_agent', '')), ''),
      'assinado_em', to_char(v_quando AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'fonte', 'borda');
  END IF;
  RETURN public.selar_assinatura_origem() || jsonb_build_object('fonte', 'cabecalhos');
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.assinatura_origem_efetiva(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assinatura_origem_efetiva(jsonb) TO authenticated, service_role;

-- (a.1) Consentimento -------------------------------------------------------
CREATE OR REPLACE FUNCTION public.registrar_consentimento_biometrico(p_dados jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_id       uuid := gen_random_uuid();
  v_tenant   uuid := NULLIF(p_dados->>'tenant_id', '')::uuid;
  v_origem   jsonb := public.assinatura_origem_efetiva(p_dados);
  v_ip       text := v_origem->>'ip_address';
  v_ua       text := v_origem->>'user_agent';
  v_quando   timestamptz := (v_origem->>'assinado_em')::timestamptz;
BEGIN
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'Consentimento inválido: informe o tenant.'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF auth.uid() IS NOT NULL AND NOT public.assinatura_chamada_do_servico()
     AND v_tenant IS DISTINCT FROM public.get_user_tenant_id() THEN
    RAISE EXCEPTION 'Consentimento inválido: empresa diferente da do usuário.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF COALESCE(p_dados->>'finalidade', '') = '' OR COALESCE(p_dados->>'versao_texto', '') = '' THEN
    RAISE EXCEPTION 'Consentimento inválido: finalidade e versão do texto são obrigatórias.'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF COALESCE((p_dados->>'aceito')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'Consentimento não pode ser registrado sem o aceite do titular.'
      USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.consentimentos_assinatura
    (id, tenant_id, contexto, documento_ref, signatario_nome, signatario_cpf,
     finalidade, versao_texto, aceito, ip_address, user_agent, aceito_em)
  VALUES
    (v_id, v_tenant, COALESCE(NULLIF(p_dados->>'contexto', ''), 'assinatura'),
     NULLIF(p_dados->>'documento_ref', ''), NULLIF(p_dados->>'signatario_nome', ''),
     NULLIF(p_dados->>'signatario_cpf', ''), p_dados->>'finalidade', p_dados->>'versao_texto',
     true, v_ip, v_ua, v_quando);

  RETURN jsonb_build_object(
    'id', v_id,
    'versao_texto', p_dados->>'versao_texto',
    'aceito_em', v_quando,
    'ip_address', v_ip);
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.registrar_consentimento_biometrico(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.registrar_consentimento_biometrico(jsonb) TO authenticated, service_role;

-- (a.2) Trilha --------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.registrar_assinatura_trilha(p_dados jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_id       uuid := gen_random_uuid();
  v_tenant   uuid := NULLIF(p_dados->>'tenant_id', '')::uuid;
  v_origem   jsonb := public.assinatura_origem_efetiva(p_dados);
  v_ip       text := v_origem->>'ip_address';
  v_ua       text := v_origem->>'user_agent';
  v_quando   timestamptz := (v_origem->>'assinado_em')::timestamptz;
  v_ref      text := NULLIF(p_dados->>'documento_ref', '');
  v_hash     text;
BEGIN
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'Trilha inválida: informe o tenant.'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF auth.uid() IS NOT NULL AND NOT public.assinatura_chamada_do_servico()
     AND v_tenant IS DISTINCT FROM public.get_user_tenant_id() THEN
    RAISE EXCEPTION 'Trilha inválida: empresa diferente da do usuário.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Sela o hash no servidor sobre a hora efetiva, quando houver conteúdo e
  -- assinatura; senão, aceita um hash já selado por outra camada do servidor.
  IF COALESCE(p_dados->>'conteudo', '') <> '' OR COALESCE(p_dados->>'assinatura', '') <> '' THEN
    v_hash := public.selar_assinatura(
      p_dados->>'conteudo', p_dados->>'assinatura', v_quando, COALESCE(v_ref, v_id::text));
  ELSE
    v_hash := NULLIF(p_dados->>'assinatura_hash', '');
  END IF;

  INSERT INTO public.assinaturas_trilha
    (id, tenant_id, contexto, documento_ref, signatario_nome, signatario_papel,
     signatario_cpf, cpf_validado, metodo_liveness, versao_detector, assinatura_hash,
     ip_address, user_agent, assinado_em, versao_consentimento, consentimento_id,
     frames_refs, liveness_data)
  VALUES
    (v_id, v_tenant, COALESCE(NULLIF(p_dados->>'contexto', ''), 'assinatura'), v_ref,
     NULLIF(p_dados->>'signatario_nome', ''), NULLIF(p_dados->>'signatario_papel', ''),
     NULLIF(p_dados->>'signatario_cpf', ''), COALESCE((p_dados->>'cpf_validado')::boolean, false),
     NULLIF(p_dados->>'metodo_liveness', ''), NULLIF(p_dados->>'versao_detector', ''), v_hash,
     v_ip, v_ua, v_quando, NULLIF(p_dados->>'versao_consentimento', ''),
     NULLIF(p_dados->>'consentimento_id', '')::uuid,
     COALESCE(p_dados->'frames_refs', '[]'::jsonb), p_dados->'liveness_data');

  RETURN jsonb_build_object(
    'id', v_id,
    'assinatura_hash', v_hash,
    'assinado_em', v_quando,
    'ip_address', v_ip);
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.registrar_assinatura_trilha(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.registrar_assinatura_trilha(jsonb) TO authenticated, service_role;

-- (c.1) Caminho de pastas, criado sob demanda --------------------------------
-- p_caminho: lista JSON; cada item é o nome (texto) ou {nome, tipo, ano, mes}.
CREATE OR REPLACE FUNCTION public.documento_pasta_garantir_caminho(
  p_tenant    uuid,
  p_empresa   uuid,
  p_pai       uuid,
  p_caminho   jsonb,
  p_user      uuid DEFAULT NULL,
  p_user_nome text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_atual uuid := p_pai;
  v_item  jsonb;
  v_nome  text;
  v_tipo  text;
  v_id    uuid;
  v_ordem int := 0;
BEGIN
  IF p_tenant IS NULL OR p_pai IS NULL OR jsonb_typeof(p_caminho) <> 'array' THEN
    RETURN p_pai;
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_caminho) LOOP
    v_nome := CASE WHEN jsonb_typeof(v_item) = 'string' THEN v_item #>> '{}'
                   ELSE v_item->>'nome' END;
    v_nome := NULLIF(btrim(COALESCE(v_nome, '')), '');
    CONTINUE WHEN v_nome IS NULL;
    v_tipo := COALESCE(NULLIF(CASE WHEN jsonb_typeof(v_item) = 'object' THEN v_item->>'tipo' END, ''), 'custom');

    -- Duas assinaturas ao mesmo tempo não podem criar a mesma pasta duas vezes.
    PERFORM pg_advisory_xact_lock(hashtext(v_atual::text || '/' || v_nome));

    v_id := (SELECT p.id FROM public.documento_pastas p
              WHERE p.tenant_id = p_tenant AND p.pasta_pai_id = v_atual AND p.nome = v_nome
              ORDER BY p.created_at LIMIT 1);
    IF v_id IS NULL THEN
      v_id := gen_random_uuid();
      INSERT INTO public.documento_pastas
        (id, tenant_id, empresa_id, nome, tipo, pasta_pai_id, ano, mes, ordem, criado_por, criado_por_nome)
      VALUES
        (v_id, p_tenant, p_empresa, v_nome, v_tipo, v_atual,
         NULLIF(CASE WHEN jsonb_typeof(v_item) = 'object' THEN v_item->>'ano' END, '')::int,
         NULLIF(CASE WHEN jsonb_typeof(v_item) = 'object' THEN v_item->>'mes' END, '')::int,
         v_ordem, p_user, p_user_nome);
    END IF;
    v_atual := v_id;
    v_ordem := v_ordem + 1;
  END LOOP;

  RETURN v_atual;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.documento_pasta_garantir_caminho(uuid, uuid, uuid, jsonb, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.documento_pasta_garantir_caminho(uuid, uuid, uuid, jsonb, uuid, text) TO service_role;

COMMENT ON FUNCTION public.documento_pasta_garantir_caminho(uuid, uuid, uuid, jsonb, uuid, text) IS
  'Garante (cria sob demanda, sem duplicar) um caminho de subpastas sob p_pai e devolve a ultima. Itens: nome (texto) ou {nome, tipo, ano, mes}. Uso interno do servidor.';

-- (c.2) Jornada/AAAA/MM-NomeDoMês de uma competência 'AAAA-MM'.
CREATE OR REPLACE FUNCTION public.assinatura_caminho_jornada(p_competencia text)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
DECLARE
  v_ano int := split_part(p_competencia, '-', 1)::int;
  v_mes int := split_part(p_competencia, '-', 2)::int;
  v_nomes text[] := ARRAY['Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho', 'Julho',
                          'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'];
BEGIN
  RETURN jsonb_build_array(
    jsonb_build_object('nome', 'Jornada', 'tipo', 'categoria'),
    jsonb_build_object('nome', v_ano::text, 'tipo', 'ano', 'ano', v_ano),
    jsonb_build_object('nome', lpad(v_mes::text, 2, '0') || '-' || v_nomes[v_mes], 'tipo', 'mes',
                       'ano', v_ano, 'mes', v_mes));
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.assinatura_caminho_jornada(text) TO authenticated, service_role;

-- (b) Arquivo canônico com caminho de subpastas --------------------------------
CREATE OR REPLACE FUNCTION public.arquivar_documento_servidor(p_doc jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_tenant    uuid := NULLIF(p_doc->>'tenant_id', '')::uuid;
  v_empresa   uuid := NULLIF(p_doc->>'empresa_id', '')::uuid;
  v_user      uuid := NULLIF(p_doc->>'user_id', '')::uuid;
  v_user_nome text := NULLIF(p_doc->>'user_nome', '');
  v_colab_id  uuid := NULLIF(p_doc->>'colaborador_id', '')::uuid;
  v_colab_nome text := NULLIF(p_doc->>'colaborador_nome', '');
  v_colab_cpf text := NULLIF(p_doc->>'colaborador_cpf', '');
  v_categoria text := NULLIF(p_doc->>'pasta_categoria', '');
  v_subpasta  text := NULLIF(p_doc->>'subpasta_colaborador', '');
  v_caminho   jsonb := p_doc->'subpasta_caminho';
  v_storage   text := NULLIF(p_doc->>'storage_path', '');
  v_nome_orig text := NULLIF(p_doc->>'file_name', '');
  v_tipo      text := COALESCE(NULLIF(p_doc->>'tipo', ''), 'documento');
  v_mime      text := COALESCE(NULLIF(p_doc->>'mime_type', ''), 'application/pdf');
  v_tamanho   integer := COALESCE((p_doc->>'tamanho')::integer, 0);
  v_validade  date := NULLIF(p_doc->>'data_validade', '')::date;
  v_gp        uuid;
  v_colab_pasta uuid;
  v_pasta_id  uuid;
  v_doc_id    uuid := gen_random_uuid();
  v_status    text := 'valido';
  v_sub       text;
  v_i         int := 0;
  v_cand      text;
  v_cultura_root uuid;
BEGIN
  IF v_tenant IS NULL OR v_storage IS NULL OR v_nome_orig IS NULL THEN
    RAISE EXCEPTION 'Arquivamento inválido: informe tenant, storage_path e file_name.'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  -- Pela API (usuário logado), só na própria empresa.
  IF auth.uid() IS NOT NULL AND NOT public.assinatura_chamada_do_servico()
     AND v_tenant IS DISTINCT FROM public.get_user_tenant_id() THEN
    RAISE EXCEPTION 'Arquivamento inválido: empresa diferente da do usuário.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- 1) Resolver a pasta de destino -------------------------------------------
  IF v_colab_id IS NOT NULL AND v_colab_nome IS NOT NULL THEN
    -- Pasta do colaborador, sob "Gestão de Pessoas" (espelha criarPastaColaborador).
    v_colab_pasta := (
      SELECT id FROM public.documento_pastas
       WHERE tenant_id = v_tenant AND colaborador_id = v_colab_id AND tipo = 'colaborador'
         AND COALESCE(empresa_id::text, '') = COALESCE(v_empresa::text, '')
       LIMIT 1);

    IF v_colab_pasta IS NULL THEN
      v_gp := (
        SELECT id FROM public.documento_pastas
         WHERE tenant_id = v_tenant AND nome = 'Gestão de Pessoas'
           AND COALESCE(empresa_id::text, '') = COALESCE(v_empresa::text, '')
         LIMIT 1);
      IF v_gp IS NULL THEN
        v_gp := gen_random_uuid();
        INSERT INTO public.documento_pastas
          (id, tenant_id, empresa_id, nome, tipo, ordem, icone, criado_por, criado_por_nome)
        VALUES (v_gp, v_tenant, v_empresa, 'Gestão de Pessoas', 'root', 5, 'Users', v_user, v_user_nome);
      END IF;

      v_colab_pasta := gen_random_uuid();
      INSERT INTO public.documento_pastas
        (id, tenant_id, empresa_id, nome, tipo, pasta_pai_id, colaborador_id, colaborador_cpf,
         colaborador_nome, ordem, icone, criado_por, criado_por_nome)
      VALUES (v_colab_pasta, v_tenant, v_empresa, v_colab_nome, 'colaborador', v_gp, v_colab_id,
              v_colab_cpf, v_colab_nome, 0, 'User', v_user, v_user_nome);
    END IF;

    -- Garante as subpastas padrão (idempotente).
    v_i := 0;
    FOREACH v_sub IN ARRAY ARRAY['Admissão', 'Vida Funcional', 'Saúde Ocupacional', 'Desligamento'] LOOP
      IF NOT EXISTS (
        SELECT 1 FROM public.documento_pastas
         WHERE tenant_id = v_tenant AND pasta_pai_id = v_colab_pasta AND nome = v_sub) THEN
        INSERT INTO public.documento_pastas
          (id, tenant_id, empresa_id, nome, tipo, pasta_pai_id, ordem, criado_por, criado_por_nome)
        VALUES (gen_random_uuid(), v_tenant, v_empresa, v_sub, 'categoria', v_colab_pasta, v_i, v_user, v_user_nome);
      END IF;
      v_i := v_i + 1;
    END LOOP;

    IF jsonb_typeof(v_caminho) = 'array' AND jsonb_array_length(v_caminho) > 0 THEN
      -- Caminho em vários níveis sob a pasta do colaborador (ex.: Jornada/2026/10-Outubro).
      v_pasta_id := public.documento_pasta_garantir_caminho(
        v_tenant, v_empresa, v_colab_pasta, v_caminho, v_user, v_user_nome);
    ELSIF v_subpasta IS NOT NULL THEN
      v_pasta_id := (
        SELECT id FROM public.documento_pastas
         WHERE tenant_id = v_tenant AND pasta_pai_id = v_colab_pasta AND nome = v_subpasta LIMIT 1);
    END IF;
    v_pasta_id := COALESCE(v_pasta_id, v_colab_pasta);

  ELSIF v_categoria = 'Cultura' THEN
    v_cultura_root := (
      SELECT id FROM public.documento_pastas
       WHERE tenant_id = v_tenant AND nome = 'Cultura Organizacional'
         AND COALESCE(empresa_id::text, '') = COALESCE(v_empresa::text, '') AND pasta_pai_id IS NULL
       LIMIT 1);
    IF v_cultura_root IS NULL THEN
      v_cultura_root := gen_random_uuid();
      INSERT INTO public.documento_pastas
        (id, tenant_id, empresa_id, nome, tipo, ordem, icone, criado_por, criado_por_nome)
      VALUES (v_cultura_root, v_tenant, v_empresa, 'Cultura Organizacional', 'root', 4, 'Heart', v_user, v_user_nome);
    END IF;
    v_pasta_id := v_cultura_root;

  ELSIF v_categoria IS NOT NULL THEN
    -- Primeira pasta existente entre os nomes candidatos da categoria.
    FOREACH v_cand IN ARRAY (CASE v_categoria
        WHEN 'SST' THEN ARRAY['SST e Segurança do Trabalho', 'SST da Empresa']
        WHEN 'Ergonomia' THEN ARRAY['Ergonomia', 'AEP — Avaliação Ergonômica Preliminar']
        WHEN 'Psicossocial' THEN ARRAY['Riscos Psicossociais (NR-01)', 'Diagnóstico Psicossocial']
        WHEN 'Ponto' THEN ARRAY['Gestão de Pessoas', 'Processos Organizacionais']
        WHEN 'Financeiro' THEN ARRAY['Processos Organizacionais', 'Gestão de Pessoas']
        WHEN 'Desligamento' THEN ARRAY['Gestão de Pessoas']
        WHEN 'Admissão' THEN ARRAY['Gestão de Pessoas']
        WHEN 'Aprendizado' THEN ARRAY['Processos Organizacionais', 'Gestão de Pessoas']
        ELSE ARRAY[v_categoria] END) LOOP
      v_pasta_id := (
        SELECT id FROM public.documento_pastas
         WHERE tenant_id = v_tenant AND nome = v_cand LIMIT 1);
      EXIT WHEN v_pasta_id IS NOT NULL;
    END LOOP;
  END IF;

  -- 2) Status pela validade ---------------------------------------------------
  IF v_validade IS NOT NULL THEN
    IF v_validade < CURRENT_DATE THEN v_status := 'vencido';
    ELSIF v_validade <= CURRENT_DATE + 30 THEN v_status := 'vencendo';
    END IF;
  END IF;

  -- 3) Registro do documento (colunas canônicas) ------------------------------
  INSERT INTO public.documentos
    (id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
     nome_arquivo, nome_original, tipo, tamanho, mime_type, storage_path, data_validade,
     status, observacoes, criado_por, criado_por_nome, pasta_id, versao_atual, total_versoes)
  VALUES
    (v_doc_id, v_tenant, v_empresa, v_colab_id, COALESCE(v_colab_nome, ''), v_colab_cpf,
     v_storage, v_nome_orig, v_tipo, v_tamanho, v_mime, v_storage, v_validade,
     v_status, NULLIF(p_doc->>'observacoes', ''), v_user, v_user_nome, v_pasta_id, 1, 1);

  -- 4) Auditoria (não bloqueante) ---------------------------------------------
  BEGIN
    INSERT INTO public.documento_audit_logs
      (tenant_id, documento_id, documento_nome, acao, pasta_destino_id, pasta_destino_nome,
       usuario_id, usuario_nome)
    VALUES
      (v_tenant, v_doc_id, v_nome_orig, 'upload', v_pasta_id, v_tipo, v_user, v_user_nome);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'arquivar_documento_servidor: auditoria falhou (seguindo): %', SQLERRM;
  END;

  RETURN jsonb_build_object('id', v_doc_id, 'storage_path', v_storage, 'pasta_id', v_pasta_id, 'status', v_status);
END;
$fn$;

COMMENT ON FUNCTION public.arquivar_documento_servidor(jsonb) IS
  'ASS-0001: arquivo canonico no servidor (espelha src/utils/arquivarDocumento.ts): resolve pasta (colaborador/categoria; subpasta_caminho em varios niveis, ex.: Jornada/AAAA/MM-Mes), insere em documentos e grava documento_audit_logs. Pela API so na propria empresa.';

REVOKE EXECUTE ON FUNCTION public.arquivar_documento_servidor(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.arquivar_documento_servidor(jsonb) TO authenticated, service_role;
