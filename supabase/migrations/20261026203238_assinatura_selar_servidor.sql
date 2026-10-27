-- =========================================================
-- ASS-0001 — FASE 0 (FUNDAÇÃO): o selo de assinatura, feito pelo SERVIDOR.
--
-- O coração da "assinatura avançada forte": nenhum valor que prova QUEM, QUANDO
-- e DE ONDE a assinatura foi colhida pode vir do navegador — o servidor os deriva
-- e sela. Isto generaliza, para QUALQUER módulo, os dois gatilhos que o EPI já
-- tinha nas entregas:
--   - epi_entrega_sela_integridade   (20261022203847): hash sha256 no servidor
--     sobre conteúdo + assinatura + hora + id;
--   - epi_entrega_origem_pelo_servidor (20261022213306): IP e dispositivo vindos
--     dos cabeçalhos cf-connecting-ip / x-forwarded-for, nunca do corpo; hora = now().
--
-- ESTA MIGRATION NÃO toca o EPI nem nenhum módulo. Entrega só as peças reutilizáveis:
--   1) public.selar_assinatura(conteudo, assinatura, quando, id) -> hash hex sha256.
--      Fórmula e separador idênticos aos do EPI, com a hora canonizada em ISO-8601
--      UTC (to_char ...'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') para bater byte a byte com o
--      módulo Deno _shared/selar-assinatura.ts (que usa Date.toISOString()). Assim a
--      edge por link e o banco produzem o MESMO selo para a mesma assinatura lógica.
--   2) public.selar_assinatura_origem() -> jsonb {ip_address, user_agent, assinado_em}
--      derivado de request.headers (PostgREST) e de now(); sem cabeçalhos (SQL Editor,
--      rotina interna) devolve ip/ua nulos e a hora do servidor. É a peça que um
--      gatilho BEFORE INSERT de qualquer tabela de assinatura pode chamar para gravar
--      origem confiável, em vez de reescrever a lógica.
--
-- Base legal: Lei 14.063/2020, art. 4º (identificar o signatário e detectar
-- alteração); MP 2.200-2/2001, art. 10, §2º; LGPD art. 6º, X (prestação de contas).
-- FORA DE ESCOPO (fase 1): aplicar isto à Advertência (piloto) e aos demais links.
-- Idempotente (CREATE OR REPLACE). Só funções: não cria tabela nem gatilho.
-- =========================================================

SET lock_timeout = '10s';

-- 1) O SELO DE INTEGRIDADE (hash) ------------------------------------------------
CREATE OR REPLACE FUNCTION public.selar_assinatura(
  p_conteudo   text,
  p_assinatura text,
  p_quando     timestamptz,
  p_id         text
) RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
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

COMMENT ON FUNCTION public.selar_assinatura(text, text, timestamptz, text) IS
  'ASS-0001: selo de integridade (sha256 hex) de uma assinatura, calculado no servidor sobre conteudo|assinatura|hora-ISO-UTC|id. Hora canonizada para bater com o modulo Deno selar-assinatura.ts. Reutilizavel por qualquer modulo.';

-- 2) A ORIGEM PELO SERVIDOR (IP, dispositivo, hora) ------------------------------
CREATE OR REPLACE FUNCTION public.selar_assinatura_origem()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $fn$
DECLARE
  v_h  jsonb;
  v_ip text;
  v_ua text;
BEGIN
  BEGIN
    v_h := NULLIF(current_setting('request.headers', true), '')::jsonb;
  EXCEPTION WHEN OTHERS THEN
    v_h := NULL;
  END;

  IF v_h IS NOT NULL THEN
    -- cf-connecting-ip o Cloudflare define e o cliente nao forja; cai para o
    -- PRIMEIRO endereco de x-forwarded-for. Nunca o que o corpo mandou.
    v_ip := COALESCE(
      NULLIF(btrim(v_h->>'cf-connecting-ip'), ''),
      NULLIF(btrim(split_part(COALESCE(v_h->>'x-forwarded-for', ''), ',', 1)), ''));
    v_ua := NULLIF(btrim(v_h->>'user-agent'), '');
  END IF;

  RETURN jsonb_build_object(
    'ip_address', v_ip,
    'user_agent', v_ua,
    'assinado_em', to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
END;
$fn$;

COMMENT ON FUNCTION public.selar_assinatura_origem() IS
  'ASS-0001: IP/dispositivo/hora da assinatura derivados do servidor (request.headers + now()); sem cabecalhos devolve ip/ua nulos. Um gatilho BEFORE INSERT de assinatura chama isto em vez de confiar no corpo.';

REVOKE EXECUTE ON FUNCTION public.selar_assinatura(text, text, timestamptz, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.selar_assinatura_origem() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.selar_assinatura(text, text, timestamptz, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.selar_assinatura_origem() TO authenticated, service_role;
