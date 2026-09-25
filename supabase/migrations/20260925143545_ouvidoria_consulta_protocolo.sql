-- ============================================================================
-- Ouvidoria: consulta pública de status por protocolo
--
-- Complementa o link público (20260925134309): a pessoa que enviou uma
-- manifestação pelo link consulta o andamento digitando o protocolo, sem login.
-- Devolve APENAS campos de status (tipo, assunto, status, resposta, datas) — NUNCA
-- dados de identidade do autor. O protocolo é o segredo (código de alta entropia).
-- ============================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.consultar_manifestacao_ouvidoria(p_token text, p_protocolo text)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_link RECORD;
  v_m RECORD;
BEGIN
  SELECT * INTO v_link
  FROM public.ouvidoria_links
  WHERE token = p_token AND ativo = true
    AND (data_expiracao IS NULL OR data_expiracao > now());
  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Link inválido ou expirado');
  END IF;

  SELECT tipo, assunto, status, resposta, respondido_em, created_at
    INTO v_m
  FROM public.ouvidoria
  WHERE tenant_id = v_link.tenant_id
    AND protocolo = upper(TRIM(COALESCE(p_protocolo, '')))
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN json_build_object('encontrado', false);
  END IF;

  RETURN json_build_object(
    'encontrado', true,
    'tipo', v_m.tipo,
    'assunto', v_m.assunto,
    'status', v_m.status,
    'resposta', v_m.resposta,
    'respondido_em', v_m.respondido_em,
    'created_at', v_m.created_at
  );
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.consultar_manifestacao_ouvidoria(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.consultar_manifestacao_ouvidoria(text, text) TO anon, authenticated;
