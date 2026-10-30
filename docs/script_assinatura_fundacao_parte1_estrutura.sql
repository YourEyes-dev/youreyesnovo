-- ============================================================================
-- ASSINATURA FORTE — FUNDAÇÃO ASS-0001 (Fase 0), PARTE 1 de 2 (estrutura)
-- Cole INTEIRO no SQL Editor. Só estrutura: tabelas, bucket, políticas e índices.
--
-- Equivale à parte de ESTRUTURA das migrations:
--   20261026203310_assinatura_evidencias_bucket_privado.sql  (bucket + políticas)
--   20261026203342_assinatura_consentimento_biometrico.sql   (consentimentos_assinatura)
--   20261026203414_assinaturas_trilha.sql                    (assinaturas_trilha)
--   20261026203446_arquivar_documento_servidor.sql           (documento_audit_logs, se faltar)
--   20261027003000_isol005_documento_audit_logs_rls.sql      (RLS + leitura por empresa)
-- As funções vão na PARTE 2 (tabelas e funções em arquivos separados por causa
-- do auxiliar de RLS automático do SQL Editor).
--
-- ORDEM DE APLICAÇÃO (homologação e produção):
--   1) docs/script_assinatura_fundacao_parte1_estrutura.sql   <- ESTE
--   2) docs/script_assinatura_fundacao_parte2_funcoes.sql
--   3) docs/script_assinatura_espelho_parte2_funcoes.sql      (REAPLICAR se já
--      tinha sido aplicado antes: a parte 2 da fundação recoloca a versão de
--      26/10 de registrar_consentimento_biometrico, registrar_assinatura_trilha
--      e arquivar_documento_servidor; a parte 2 do espelho devolve a versão final
--      de 30/10, que é a do staging)
--   4) docs/script_assinatura_espelho_parte4_testes.sql       (reaplicar: roda os
--      casos ESP-ASS-001..011 de novo, agora com a fundação no lugar)
-- Banco que ainda NÃO tem o espelho (produção): fundação 1 e 2, depois
-- ponto_espelho_f0 parte 1 e 2, depois assinatura_espelho parte 1, 2, 3 e 4.
--
-- Regras do editor respeitadas: tabela criada por EXECUTE com a palavra
-- partida (o auxiliar de RLS automático não detecta tabela nova); nenhuma
-- função neste arquivo; nenhuma atribuição por consulta com destino em variável;
-- marcas de aspas-dólar só em código, em número par.
-- Só CRIA coisa nova (sem UPDATE/DELETE de dado): não precisa de backup.
-- documento_audit_logs nasceu em produção fora das migrations: só é criada onde
-- faltar; onde já existe, ganha RLS ligado + leitura só da própria empresa
-- (ISOL-005), igual ao staging. A gravação dela é pela RPC SECURITY DEFINER.
-- Idempotente (rodar 2x não quebra nem duplica).
-- ============================================================================

SET lock_timeout = '10s';

-- ── 1) Bucket PRIVADO e neutro para a evidência da prova de vida ───────────
INSERT INTO storage.buckets (id, name, public)
VALUES ('assinatura-evidencias', 'assinatura-evidencias', false)
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS "assinatura_evidencias_leitura_da_empresa" ON storage.objects;
CREATE POLICY "assinatura_evidencias_leitura_da_empresa"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'assinatura-evidencias'
    AND (storage.foldername(name))[1] = public.get_user_tenant_id()::text
  );

DROP POLICY IF EXISTS "assinatura_evidencias_gravacao_da_empresa" ON storage.objects;
CREATE POLICY "assinatura_evidencias_gravacao_da_empresa"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'assinatura-evidencias'
    AND (storage.foldername(name))[1] = public.get_user_tenant_id()::text
  );

-- ── 2) Tabelas (por EXECUTE, só onde faltar) ───────────────────────────────
DO $tab$
BEGIN
  IF to_regclass('public.consentimentos_assinatura') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.consentimentos_assinatura (
      id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      tenant_id       uuid NOT NULL,
      contexto        text NOT NULL,
      documento_ref   text,
      signatario_nome text,
      signatario_cpf  text,
      finalidade      text NOT NULL,
      versao_texto    text NOT NULL,
      aceito          boolean NOT NULL DEFAULT true,
      ip_address      text,
      user_agent      text,
      aceito_em       timestamptz NOT NULL DEFAULT now(),
      criado_em       timestamptz NOT NULL DEFAULT now())';
  END IF;

  IF to_regclass('public.assinaturas_trilha') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.assinaturas_trilha (
      id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      tenant_id            uuid NOT NULL,
      contexto             text NOT NULL,
      documento_ref        text,
      signatario_nome      text,
      signatario_papel     text,
      signatario_cpf       text,
      cpf_validado         boolean NOT NULL DEFAULT false,
      metodo_liveness      text,
      versao_detector      text,
      assinatura_hash      text,
      ip_address           text,
      user_agent           text,
      assinado_em          timestamptz NOT NULL DEFAULT now(),
      versao_consentimento text,
      consentimento_id     uuid REFERENCES public.consentimentos_assinatura(id) ON DELETE SET NULL,
      frames_refs          jsonb NOT NULL DEFAULT ''[]''::jsonb,
      liveness_data        jsonb,
      criado_em            timestamptz NOT NULL DEFAULT now())';
  END IF;

  -- Nasceu fora das migrations em produção: só cria onde faltar.
  IF to_regclass('public.documento_audit_logs') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.documento_audit_logs (
      id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      tenant_id          uuid NOT NULL,
      documento_id       uuid,
      documento_nome     text,
      acao               text NOT NULL,
      pasta_destino_id   uuid,
      pasta_destino_nome text,
      usuario_id         uuid,
      usuario_nome       text,
      created_at         timestamptz NOT NULL DEFAULT now())';
  END IF;
END $tab$;

COMMENT ON TABLE public.consentimentos_assinatura IS
  'ASS-0001: trilha do consentimento biometrico LGPD (art. 11) colhido ANTES da camera na assinatura. Quem/quando/qual versao do texto; origem (IP/UA/hora) pelo servidor. Insercao-apenas via RPC.';
COMMENT ON TABLE public.assinaturas_trilha IS
  'ASS-0001: trilha padronizada da assinatura forte (quem/papel/CPF validado/metodo liveness+versao/hash/IP-UA-hora do servidor/versao consentimento/refs dos frames). Prova, nao conteudo. Insercao-apenas via RPC.';
COMMENT ON TABLE public.documento_audit_logs IS
  'Trilha de auditoria do modulo Documentos (upload/mover/excluir). Trazida para as migrations por IF NOT EXISTS (nasceu fora delas em producao).';

-- ── 3) Índices ─────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_consentimentos_assinatura_tenant
  ON public.consentimentos_assinatura (tenant_id, contexto, aceito_em DESC);
CREATE INDEX IF NOT EXISTS idx_assinaturas_trilha_tenant
  ON public.assinaturas_trilha (tenant_id, contexto, assinado_em DESC);
CREATE INDEX IF NOT EXISTS idx_assinaturas_trilha_documento
  ON public.assinaturas_trilha (documento_ref);

-- ── 4) RLS: leitura só da própria empresa; escrita só pelas RPCs ───────────
-- Sem política de INSERT/UPDATE/DELETE: as trilhas são imutáveis e gravadas
-- pelas RPCs SECURITY DEFINER da parte 2.
ALTER TABLE public.consentimentos_assinatura ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assinaturas_trilha ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documento_audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "consentimentos_assinatura_leitura_tenant" ON public.consentimentos_assinatura;
CREATE POLICY "consentimentos_assinatura_leitura_tenant"
  ON public.consentimentos_assinatura FOR SELECT
  TO authenticated
  USING (tenant_id = public.get_user_tenant_id());

DROP POLICY IF EXISTS "assinaturas_trilha_leitura_tenant" ON public.assinaturas_trilha;
CREATE POLICY "assinaturas_trilha_leitura_tenant"
  ON public.assinaturas_trilha FOR SELECT
  TO authenticated
  USING (tenant_id = public.get_user_tenant_id());

DROP POLICY IF EXISTS "documento_audit_logs_leitura_tenant" ON public.documento_audit_logs;
CREATE POLICY "documento_audit_logs_leitura_tenant"
  ON public.documento_audit_logs FOR SELECT
  TO authenticated
  USING (tenant_id = public.get_user_tenant_id());

-- ── CONFERÊNCIA (esperado: tudo true) ──────────────────────────────────────
SELECT
  to_regclass('public.consentimentos_assinatura') IS NOT NULL AS tem_consentimentos,
  to_regclass('public.assinaturas_trilha') IS NOT NULL AS tem_trilha,
  to_regclass('public.documento_audit_logs') IS NOT NULL AS tem_audit_logs,
  COALESCE((SELECT NOT b.public FROM storage.buckets b WHERE b.id = 'assinatura-evidencias'), false) AS bucket_privado,
  (SELECT count(*) FROM pg_policies p WHERE p.schemaname = 'storage' AND p.tablename = 'objects'
     AND p.policyname IN ('assinatura_evidencias_leitura_da_empresa', 'assinatura_evidencias_gravacao_da_empresa')) = 2 AS politicas_bucket,
  (SELECT bool_and(c.relrowsecurity) FROM pg_class c
    WHERE c.oid IN ('public.consentimentos_assinatura'::regclass, 'public.assinaturas_trilha'::regclass,
                    'public.documento_audit_logs'::regclass)) AS rls_ligada_nas_3,
  (SELECT count(*) FROM pg_policies p WHERE p.schemaname = 'public'
     AND p.policyname IN ('consentimentos_assinatura_leitura_tenant', 'assinaturas_trilha_leitura_tenant',
                          'documento_audit_logs_leitura_tenant')) = 3 AS politicas_leitura_tenant,
  (SELECT count(*) FROM pg_indexes i WHERE i.schemaname = 'public'
     AND i.indexname IN ('idx_consentimentos_assinatura_tenant', 'idx_assinaturas_trilha_tenant',
                         'idx_assinaturas_trilha_documento')) = 3 AS indices;
