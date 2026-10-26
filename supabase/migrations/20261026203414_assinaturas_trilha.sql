-- =========================================================
-- ASS-0001 — FASE 0 (aditivo): trilha de auditoria de assinatura PADRONIZADA.
--
-- Uma linha por assinatura forte, com tudo o que sustenta a assinatura avançada
-- em juízo (Lei 14.063/2020, art. 4º; MP 2.200-2/2001; LGPD art. 6º, X):
--   signatário, papel, CPF (e se foi validado), método do liveness + versão do
--   detector, hash de integridade, IP/UA/hora DO SERVIDOR, versão do consentimento
--   aceito (ligando à trilha de consentimento) e as referências dos frames no
--   bucket privado.
--
-- A RPC registrar_assinatura_trilha deriva a origem pelo servidor (selar_assinatura_origem)
-- e SELA o hash no servidor (selar_assinatura) sobre a hora do servidor — o que o
-- navegador mandar de IP, hora ou hash não prevalece. Guarda a prova, não o conteúdo.
--
-- SECURITY DEFINER (signatário por link é anônimo via edge service_role); trilha
-- imutável, sem UPDATE/DELETE por política; RLS liga com leitura escopada ao tenant.
-- NÃO toca módulo nenhum. Idempotente.
-- =========================================================

SET lock_timeout = '10s';

CREATE TABLE IF NOT EXISTS public.assinaturas_trilha (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id            uuid NOT NULL,
  contexto             text NOT NULL,                 -- 'advertencia' | 'epi' | ...
  documento_ref        text,                          -- id/token do documento assinado
  signatario_nome      text,
  signatario_papel     text,                          -- 'colaborador' | 'gestor' | 'testemunha' | ...
  signatario_cpf       text,
  cpf_validado         boolean NOT NULL DEFAULT false,
  metodo_liveness      text,                          -- 'face-landmarker' | 'manual' | null
  versao_detector      text,
  assinatura_hash      text,                          -- selado no servidor
  ip_address           text,                          -- do servidor (cabeçalhos)
  user_agent           text,
  assinado_em          timestamptz NOT NULL DEFAULT now(),
  versao_consentimento text,
  consentimento_id     uuid REFERENCES public.consentimentos_assinatura(id) ON DELETE SET NULL,
  frames_refs          jsonb NOT NULL DEFAULT '[]'::jsonb,   -- caminhos no bucket privado
  liveness_data        jsonb,
  criado_em            timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.assinaturas_trilha IS
  'ASS-0001: trilha padronizada da assinatura forte (quem/papel/CPF validado/metodo liveness+versao/hash/IP-UA-hora do servidor/versao consentimento/refs dos frames). Prova, nao conteudo. Insercao-apenas via RPC.';

CREATE INDEX IF NOT EXISTS idx_assinaturas_trilha_tenant
  ON public.assinaturas_trilha (tenant_id, contexto, assinado_em DESC);
CREATE INDEX IF NOT EXISTS idx_assinaturas_trilha_documento
  ON public.assinaturas_trilha (documento_ref);

ALTER TABLE public.assinaturas_trilha ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "assinaturas_trilha_leitura_tenant" ON public.assinaturas_trilha;
CREATE POLICY "assinaturas_trilha_leitura_tenant"
  ON public.assinaturas_trilha FOR SELECT
  TO authenticated
  USING (tenant_id = public.get_user_tenant_id());

CREATE OR REPLACE FUNCTION public.registrar_assinatura_trilha(p_dados jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_id       uuid := gen_random_uuid();
  v_tenant   uuid := NULLIF(p_dados->>'tenant_id', '')::uuid;
  v_origem   jsonb := public.selar_assinatura_origem();
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

  -- Sela o hash no servidor sobre a hora do servidor, quando houver conteúdo e
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

COMMENT ON FUNCTION public.registrar_assinatura_trilha(jsonb) IS
  'ASS-0001: grava a trilha padronizada da assinatura, selando hash e origem pelo servidor. App autenticado e edges de link (service_role). Devolve id e hash.';

REVOKE EXECUTE ON FUNCTION public.registrar_assinatura_trilha(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.registrar_assinatura_trilha(jsonb) TO authenticated, service_role;
