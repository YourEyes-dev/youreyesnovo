-- =========================================================
-- ASS-0001 — FASE 0: trilha do CONSENTIMENTO LGPD biométrico.
--
-- Hoje NÃO existe registro de consentimento antes de ligar a câmera na assinatura.
-- Dado biométrico é sensível (LGPD art. 11) e exige consentimento ESPECÍFICO e
-- destacado (art. 11, I) com finalidade clara (art. 9º). A tela de consentimento
-- (src/components/assinatura/ConsentimentoBiometrico.tsx) aparece ANTES da câmera e,
-- ao ser aceita, chama esta RPC para registrar quem/quando/qual versão do texto.
--
-- Tabela consentimentos_assinatura: a trilha. A RPC registrar_consentimento_biometrico
-- deriva IP/dispositivo/hora do SERVIDOR (selar_assinatura_origem) e nunca do corpo —
-- o navegador pode mandar contexto, finalidade e versão, mas não a origem.
--
-- SECURITY DEFINER: o signatário por link é anônimo (a edge chama com service_role);
-- e o registro é só-inserção (sem UPDATE/DELETE por política). RLS liga com leitura
-- escopada ao tenant. NÃO toca módulo nenhum. Idempotente.
-- =========================================================

SET lock_timeout = '10s';

CREATE TABLE IF NOT EXISTS public.consentimentos_assinatura (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid NOT NULL,
  contexto       text NOT NULL,                 -- 'advertencia' | 'epi' | 'experiencia' | ...
  documento_ref  text,                          -- id/token do documento sendo assinado
  signatario_nome text,
  signatario_cpf text,
  finalidade     text NOT NULL,                 -- finalidade específica mostrada ao titular
  versao_texto   text NOT NULL,                 -- versão do texto de consentimento aceito
  aceito         boolean NOT NULL DEFAULT true,
  ip_address     text,                          -- do servidor (cabeçalhos), não do corpo
  user_agent     text,
  aceito_em      timestamptz NOT NULL DEFAULT now(),
  criado_em      timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.consentimentos_assinatura IS
  'ASS-0001: trilha do consentimento biometrico LGPD (art. 11) colhido ANTES da camera na assinatura. Quem/quando/qual versao do texto; origem (IP/UA/hora) pelo servidor. Insercao-apenas via RPC.';

CREATE INDEX IF NOT EXISTS idx_consentimentos_assinatura_tenant
  ON public.consentimentos_assinatura (tenant_id, contexto, aceito_em DESC);

ALTER TABLE public.consentimentos_assinatura ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "consentimentos_assinatura_leitura_tenant" ON public.consentimentos_assinatura;
CREATE POLICY "consentimentos_assinatura_leitura_tenant"
  ON public.consentimentos_assinatura FOR SELECT
  TO authenticated
  USING (tenant_id = public.get_user_tenant_id());

-- Sem política de INSERT/UPDATE/DELETE: a trilha só é escrita pela RPC abaixo
-- (SECURITY DEFINER) e é imutável.

CREATE OR REPLACE FUNCTION public.registrar_consentimento_biometrico(p_dados jsonb)
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
BEGIN
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'Consentimento inválido: informe o tenant.'
      USING ERRCODE = 'invalid_parameter_value';
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

COMMENT ON FUNCTION public.registrar_consentimento_biometrico(jsonb) IS
  'ASS-0001: registra o consentimento biometrico (LGPD art. 11) na trilha, com origem (IP/UA/hora) derivada do servidor. Chamada pelo app autenticado e pelas edges de link (service_role). Devolve id e versao.';

REVOKE EXECUTE ON FUNCTION public.registrar_consentimento_biometrico(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.registrar_consentimento_biometrico(jsonb) TO authenticated, service_role;
