-- SUBSTITUÍDO (30/10/2026): use docs/script_assinatura_fundacao_parte1_estrutura.sql
-- e docs/script_assinatura_fundacao_parte2_funcoes.sql (ordem e conferência no
-- cabeçalho deles). Este arquivo fica só como histórico; não cole.
-- =========================================================
-- ASS-0001 — FASE 0 (FUNDAÇÃO): script de ENTREGA (SQL Editor de homologação/produção).
--
-- Entrega as peças reutilizáveis da assinatura forte, SEM tocar nenhum módulo:
--   1) selar_assinatura / selar_assinatura_origem  (selo + origem pelo servidor)
--   2) bucket privado neutro assinatura-evidencias + políticas
--   3) consentimentos_assinatura + registrar_consentimento_biometrico (LGPD)
--   4) assinaturas_trilha + registrar_assinatura_trilha (trilha padronizada)
--   5) documento_audit_logs (IF NOT EXISTS) + arquivar_documento_servidor (arquivo canônico)
--
-- Regras da casa aplicadas (scripts de entrega):
--   - roda o arquivo inteiro em UMA transação; idempotente (rodar 2x não quebra);
--   - tabela nova criada por EXECUTE 'CREATE '||'TABLE ...' dentro de bloco DO, para
--     NÃO acionar o auto-RLS do editor (que corromperia as funções do mesmo arquivo);
--   - nenhuma função usa SELECT ... INTO (só atribuição por subconsulta escalar);
--   - marcas de aspas-dólar em número PAR e NUNCA dentro de comentário;
--   - REVOKE EXECUTE ... FROM PUBLIC nas funções; conferência SELECT ao fim.
-- Só CRIA objetos novos (sem UPDATE/DELETE de dados): não precisa de backup prévio.
-- =========================================================

SET lock_timeout = '10s';

-- ── 1) SELO + ORIGEM PELO SERVIDOR ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.selar_assinatura(
  p_conteudo text, p_assinatura text, p_quando timestamptz, p_id text
) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path TO 'public'
AS $fn$
  SELECT encode(
    public.digest(
      COALESCE(p_conteudo, '') || '|' ||
      COALESCE(p_assinatura, '') || '|' ||
      to_char(p_quando AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') || '|' ||
      COALESCE(p_id, ''),
      'sha256'),
    'hex');
$fn$;

CREATE OR REPLACE FUNCTION public.selar_assinatura_origem()
RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path TO 'public'
AS $fn$
DECLARE v_h jsonb; v_ip text; v_ua text;
BEGIN
  BEGIN
    v_h := NULLIF(current_setting('request.headers', true), '')::jsonb;
  EXCEPTION WHEN OTHERS THEN
    v_h := NULL;
  END;
  IF v_h IS NOT NULL THEN
    v_ip := COALESCE(
      NULLIF(btrim(v_h->>'cf-connecting-ip'), ''),
      NULLIF(btrim(split_part(COALESCE(v_h->>'x-forwarded-for', ''), ',', 1)), ''));
    v_ua := NULLIF(btrim(v_h->>'user-agent'), '');
  END IF;
  RETURN jsonb_build_object(
    'ip_address', v_ip, 'user_agent', v_ua,
    'assinado_em', to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.selar_assinatura(text, text, timestamptz, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.selar_assinatura_origem() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.selar_assinatura(text, text, timestamptz, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.selar_assinatura_origem() TO authenticated, service_role;

-- ── 2) BUCKET PRIVADO NEUTRO ──────────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public)
VALUES ('assinatura-evidencias', 'assinatura-evidencias', false)
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS "assinatura_evidencias_leitura_da_empresa" ON storage.objects;
CREATE POLICY "assinatura_evidencias_leitura_da_empresa"
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'assinatura-evidencias'
    AND (storage.foldername(name))[1] = public.get_user_tenant_id()::text);

DROP POLICY IF EXISTS "assinatura_evidencias_gravacao_da_empresa" ON storage.objects;
CREATE POLICY "assinatura_evidencias_gravacao_da_empresa"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'assinatura-evidencias'
    AND (storage.foldername(name))[1] = public.get_user_tenant_id()::text);

-- ── 3/4/5) TABELAS NOVAS (via EXECUTE, sem o literal contíguo que liga o auto-RLS)
DO $blk$
BEGIN
  IF to_regclass('public.consentimentos_assinatura') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.consentimentos_assinatura (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      tenant_id uuid NOT NULL,
      contexto text NOT NULL,
      documento_ref text,
      signatario_nome text,
      signatario_cpf text,
      finalidade text NOT NULL,
      versao_texto text NOT NULL,
      aceito boolean NOT NULL DEFAULT true,
      ip_address text,
      user_agent text,
      aceito_em timestamptz NOT NULL DEFAULT now(),
      criado_em timestamptz NOT NULL DEFAULT now())';
  END IF;

  IF to_regclass('public.assinaturas_trilha') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.assinaturas_trilha (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      tenant_id uuid NOT NULL,
      contexto text NOT NULL,
      documento_ref text,
      signatario_nome text,
      signatario_papel text,
      signatario_cpf text,
      cpf_validado boolean NOT NULL DEFAULT false,
      metodo_liveness text,
      versao_detector text,
      assinatura_hash text,
      ip_address text,
      user_agent text,
      assinado_em timestamptz NOT NULL DEFAULT now(),
      versao_consentimento text,
      consentimento_id uuid REFERENCES public.consentimentos_assinatura(id) ON DELETE SET NULL,
      frames_refs jsonb NOT NULL DEFAULT ''[]''::jsonb,
      liveness_data jsonb,
      criado_em timestamptz NOT NULL DEFAULT now())';
  END IF;

  -- Nasceu fora das migrations em produção: só cria onde faltar (ex.: homologação nova).
  IF to_regclass('public.documento_audit_logs') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.documento_audit_logs (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      tenant_id uuid NOT NULL,
      documento_id uuid,
      documento_nome text,
      acao text NOT NULL,
      pasta_destino_id uuid,
      pasta_destino_nome text,
      usuario_id uuid,
      usuario_nome text,
      created_at timestamptz NOT NULL DEFAULT now())';
  END IF;
END $blk$;

CREATE INDEX IF NOT EXISTS idx_consentimentos_assinatura_tenant
  ON public.consentimentos_assinatura (tenant_id, contexto, aceito_em DESC);
CREATE INDEX IF NOT EXISTS idx_assinaturas_trilha_tenant
  ON public.assinaturas_trilha (tenant_id, contexto, assinado_em DESC);
CREATE INDEX IF NOT EXISTS idx_assinaturas_trilha_documento
  ON public.assinaturas_trilha (documento_ref);

ALTER TABLE public.consentimentos_assinatura ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assinaturas_trilha ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "consentimentos_assinatura_leitura_tenant" ON public.consentimentos_assinatura;
CREATE POLICY "consentimentos_assinatura_leitura_tenant"
  ON public.consentimentos_assinatura FOR SELECT TO authenticated
  USING (tenant_id = public.get_user_tenant_id());

DROP POLICY IF EXISTS "assinaturas_trilha_leitura_tenant" ON public.assinaturas_trilha;
CREATE POLICY "assinaturas_trilha_leitura_tenant"
  ON public.assinaturas_trilha FOR SELECT TO authenticated
  USING (tenant_id = public.get_user_tenant_id());

-- ── 3) RPC do CONSENTIMENTO ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.registrar_consentimento_biometrico(p_dados jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_id uuid := gen_random_uuid();
  v_tenant uuid := NULLIF(p_dados->>'tenant_id', '')::uuid;
  v_origem jsonb := public.selar_assinatura_origem();
  v_ip text := v_origem->>'ip_address';
  v_ua text := v_origem->>'user_agent';
  v_quando timestamptz := (v_origem->>'assinado_em')::timestamptz;
BEGIN
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'Consentimento inválido: informe o tenant.' USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF COALESCE(p_dados->>'finalidade', '') = '' OR COALESCE(p_dados->>'versao_texto', '') = '' THEN
    RAISE EXCEPTION 'Consentimento inválido: finalidade e versão do texto são obrigatórias.' USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF COALESCE((p_dados->>'aceito')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'Consentimento não pode ser registrado sem o aceite do titular.' USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.consentimentos_assinatura
    (id, tenant_id, contexto, documento_ref, signatario_nome, signatario_cpf,
     finalidade, versao_texto, aceito, ip_address, user_agent, aceito_em)
  VALUES
    (v_id, v_tenant, COALESCE(NULLIF(p_dados->>'contexto', ''), 'assinatura'),
     NULLIF(p_dados->>'documento_ref', ''), NULLIF(p_dados->>'signatario_nome', ''),
     NULLIF(p_dados->>'signatario_cpf', ''), p_dados->>'finalidade', p_dados->>'versao_texto',
     true, v_ip, v_ua, v_quando);

  RETURN jsonb_build_object('id', v_id, 'versao_texto', p_dados->>'versao_texto',
                            'aceito_em', v_quando, 'ip_address', v_ip);
END;
$fn$;

-- ── 4) RPC da TRILHA ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.registrar_assinatura_trilha(p_dados jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_id uuid := gen_random_uuid();
  v_tenant uuid := NULLIF(p_dados->>'tenant_id', '')::uuid;
  v_origem jsonb := public.selar_assinatura_origem();
  v_ip text := v_origem->>'ip_address';
  v_ua text := v_origem->>'user_agent';
  v_quando timestamptz := (v_origem->>'assinado_em')::timestamptz;
  v_ref text := NULLIF(p_dados->>'documento_ref', '');
  v_hash text;
BEGIN
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'Trilha inválida: informe o tenant.' USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF COALESCE(p_dados->>'conteudo', '') <> '' OR COALESCE(p_dados->>'assinatura', '') <> '' THEN
    v_hash := public.selar_assinatura(p_dados->>'conteudo', p_dados->>'assinatura', v_quando, COALESCE(v_ref, v_id::text));
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

  RETURN jsonb_build_object('id', v_id, 'assinatura_hash', v_hash,
                            'assinado_em', v_quando, 'ip_address', v_ip);
END;
$fn$;

-- ── 5) RPC do ARQUIVO CANÔNICO ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.arquivar_documento_servidor(p_doc jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_tenant uuid := NULLIF(p_doc->>'tenant_id', '')::uuid;
  v_empresa uuid := NULLIF(p_doc->>'empresa_id', '')::uuid;
  v_user uuid := NULLIF(p_doc->>'user_id', '')::uuid;
  v_user_nome text := NULLIF(p_doc->>'user_nome', '');
  v_colab_id uuid := NULLIF(p_doc->>'colaborador_id', '')::uuid;
  v_colab_nome text := NULLIF(p_doc->>'colaborador_nome', '');
  v_colab_cpf text := NULLIF(p_doc->>'colaborador_cpf', '');
  v_categoria text := NULLIF(p_doc->>'pasta_categoria', '');
  v_subpasta text := NULLIF(p_doc->>'subpasta_colaborador', '');
  v_storage text := NULLIF(p_doc->>'storage_path', '');
  v_nome_orig text := NULLIF(p_doc->>'file_name', '');
  v_tipo text := COALESCE(NULLIF(p_doc->>'tipo', ''), 'documento');
  v_mime text := COALESCE(NULLIF(p_doc->>'mime_type', ''), 'application/pdf');
  v_tamanho integer := COALESCE((p_doc->>'tamanho')::integer, 0);
  v_validade date := NULLIF(p_doc->>'data_validade', '')::date;
  v_gp uuid; v_colab_pasta uuid; v_pasta_id uuid;
  v_doc_id uuid := gen_random_uuid(); v_status text := 'valido';
  v_sub text; v_i int := 0; v_cand text; v_cultura_root uuid;
BEGIN
  IF v_tenant IS NULL OR v_storage IS NULL OR v_nome_orig IS NULL THEN
    RAISE EXCEPTION 'Arquivamento inválido: informe tenant, storage_path e file_name.' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF v_colab_id IS NOT NULL AND v_colab_nome IS NOT NULL THEN
    v_colab_pasta := (SELECT id FROM public.documento_pastas
       WHERE tenant_id = v_tenant AND colaborador_id = v_colab_id AND tipo = 'colaborador'
         AND COALESCE(empresa_id::text, '') = COALESCE(v_empresa::text, '') LIMIT 1);
    IF v_colab_pasta IS NULL THEN
      v_gp := (SELECT id FROM public.documento_pastas
         WHERE tenant_id = v_tenant AND nome = 'Gestão de Pessoas'
           AND COALESCE(empresa_id::text, '') = COALESCE(v_empresa::text, '') LIMIT 1);
      IF v_gp IS NULL THEN
        v_gp := gen_random_uuid();
        INSERT INTO public.documento_pastas (id, tenant_id, empresa_id, nome, tipo, ordem, icone, criado_por, criado_por_nome)
        VALUES (v_gp, v_tenant, v_empresa, 'Gestão de Pessoas', 'root', 5, 'Users', v_user, v_user_nome);
      END IF;
      v_colab_pasta := gen_random_uuid();
      INSERT INTO public.documento_pastas (id, tenant_id, empresa_id, nome, tipo, pasta_pai_id, colaborador_id, colaborador_cpf, colaborador_nome, ordem, icone, criado_por, criado_por_nome)
      VALUES (v_colab_pasta, v_tenant, v_empresa, v_colab_nome, 'colaborador', v_gp, v_colab_id, v_colab_cpf, v_colab_nome, 0, 'User', v_user, v_user_nome);
    END IF;
    v_i := 0;
    FOREACH v_sub IN ARRAY ARRAY['Admissão', 'Vida Funcional', 'Saúde Ocupacional', 'Desligamento'] LOOP
      IF NOT EXISTS (SELECT 1 FROM public.documento_pastas WHERE tenant_id = v_tenant AND pasta_pai_id = v_colab_pasta AND nome = v_sub) THEN
        INSERT INTO public.documento_pastas (id, tenant_id, empresa_id, nome, tipo, pasta_pai_id, ordem, criado_por, criado_por_nome)
        VALUES (gen_random_uuid(), v_tenant, v_empresa, v_sub, 'categoria', v_colab_pasta, v_i, v_user, v_user_nome);
      END IF;
      v_i := v_i + 1;
    END LOOP;
    IF v_subpasta IS NOT NULL THEN
      v_pasta_id := (SELECT id FROM public.documento_pastas WHERE tenant_id = v_tenant AND pasta_pai_id = v_colab_pasta AND nome = v_subpasta LIMIT 1);
    END IF;
    v_pasta_id := COALESCE(v_pasta_id, v_colab_pasta);
  ELSIF v_categoria = 'Cultura' THEN
    v_cultura_root := (SELECT id FROM public.documento_pastas
       WHERE tenant_id = v_tenant AND nome = 'Cultura Organizacional'
         AND COALESCE(empresa_id::text, '') = COALESCE(v_empresa::text, '') AND pasta_pai_id IS NULL LIMIT 1);
    IF v_cultura_root IS NULL THEN
      v_cultura_root := gen_random_uuid();
      INSERT INTO public.documento_pastas (id, tenant_id, empresa_id, nome, tipo, ordem, icone, criado_por, criado_por_nome)
      VALUES (v_cultura_root, v_tenant, v_empresa, 'Cultura Organizacional', 'root', 4, 'Heart', v_user, v_user_nome);
    END IF;
    v_pasta_id := v_cultura_root;
  ELSIF v_categoria IS NOT NULL THEN
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
      v_pasta_id := (SELECT id FROM public.documento_pastas WHERE tenant_id = v_tenant AND nome = v_cand LIMIT 1);
      EXIT WHEN v_pasta_id IS NOT NULL;
    END LOOP;
  END IF;

  IF v_validade IS NOT NULL THEN
    IF v_validade < CURRENT_DATE THEN v_status := 'vencido';
    ELSIF v_validade <= CURRENT_DATE + 30 THEN v_status := 'vencendo';
    END IF;
  END IF;

  INSERT INTO public.documentos
    (id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
     nome_arquivo, nome_original, tipo, tamanho, mime_type, storage_path, data_validade,
     status, observacoes, criado_por, criado_por_nome, pasta_id, versao_atual, total_versoes)
  VALUES
    (v_doc_id, v_tenant, v_empresa, v_colab_id, COALESCE(v_colab_nome, ''), v_colab_cpf,
     v_storage, v_nome_orig, v_tipo, v_tamanho, v_mime, v_storage, v_validade,
     v_status, NULLIF(p_doc->>'observacoes', ''), v_user, v_user_nome, v_pasta_id, 1, 1);

  BEGIN
    INSERT INTO public.documento_audit_logs
      (tenant_id, documento_id, documento_nome, acao, pasta_destino_id, pasta_destino_nome, usuario_id, usuario_nome)
    VALUES (v_tenant, v_doc_id, v_nome_orig, 'upload', v_pasta_id, v_tipo, v_user, v_user_nome);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'arquivar_documento_servidor: auditoria falhou (seguindo): %', SQLERRM;
  END;

  RETURN jsonb_build_object('id', v_doc_id, 'storage_path', v_storage, 'pasta_id', v_pasta_id, 'status', v_status);
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.registrar_consentimento_biometrico(jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.registrar_assinatura_trilha(jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.arquivar_documento_servidor(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.registrar_consentimento_biometrico(jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.registrar_assinatura_trilha(jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.arquivar_documento_servidor(jsonb) TO authenticated, service_role;

-- ── CONFERÊNCIA (o editor mostra só o último resultado) ───────────────────────
SELECT
  (SELECT count(*) FROM pg_proc WHERE proname IN
     ('selar_assinatura','selar_assinatura_origem','registrar_consentimento_biometrico',
      'registrar_assinatura_trilha','arquivar_documento_servidor')) AS funcoes_ok_esperado_5,
  (to_regclass('public.consentimentos_assinatura') IS NOT NULL) AS tem_consentimentos,
  (to_regclass('public.assinaturas_trilha') IS NOT NULL) AS tem_trilha,
  (to_regclass('public.documento_audit_logs') IS NOT NULL) AS tem_audit,
  (SELECT public = false FROM storage.buckets WHERE id = 'assinatura-evidencias') AS bucket_privado,
  public.selar_assinatura('a','b','2026-01-01T00:00:00.000Z'::timestamptz,'id') AS exemplo_hash;
