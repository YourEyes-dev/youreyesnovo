-- ============================================================================
-- ENTREGA — a batida pelo link externo passa a gravar a empresa do colaborador
--
-- O QUE ESTE SCRIPT FAZ (e por que):
--   O registro pelo link externo inseria a marcação SEM empresa_id. Como os
--   painéis e o espelho filtram por empresa_id, a batida do link ficava sem
--   empresa e podia sumir dos painéis por empresa (num tenant com mais de uma
--   empresa). Agora a marcação herda a empresa da ADMISSÃO do colaborador, via
--   public.ponto_empresa_do_colaborador(colaborador_id) — mesmo princípio já
--   usado na correção dos ajustes.
--
--   Substitui as duas funções externas (a por CPF e a legada por colaborador).
--   Corpo idêntico ao da migration 20260924175330. Cada função num bloco
--   DO/EXECUTE (elas têm SELECT ... INTO). Rode BLOCO 1, BLOCO 2 e a conferência.
--
-- SEGURANCA: só substitui funções; NÃO altera dado existente (o backfill das
--   batidas antigas sem empresa, se for preciso, é entrega à parte com backup).
--   Idempotente.
-- ============================================================================

SET lock_timeout = '10s';

-- ── BLOCO 1: registrar_ponto_externo_cpf ────────────────────────────────────
DO $ptdo$
BEGIN
  EXECUTE $ptsql$
CREATE OR REPLACE FUNCTION public.registrar_ponto_externo_cpf(
  p_token text,
  p_cpf text,
  p_tipo_marcacao text DEFAULT NULL,
  p_latitude double precision DEFAULT NULL,
  p_longitude double precision DEFAULT NULL,
  p_endereco text DEFAULT NULL,
  p_selfie_url text DEFAULT NULL,
  p_selfie_nome text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_link RECORD; v_colab RECORD; v_marcacao_id UUID; v_hora TIME; v_data DATE;
  v_now TIMESTAMP; v_err TEXT; v_tipo TEXT; v_esperado TEXT; v_ultima RECORD;
  v_afast public.afastamentos;
BEGIN
  v_now := timezone('America/Sao_Paulo', now());
  v_hora := v_now::TIME;
  v_data := v_now::DATE;

  SELECT * INTO v_link FROM public.ponto_links
  WHERE token = p_token AND tipo = 'compartilhado' AND ativo = true
    AND (data_expiracao IS NULL OR data_expiracao > now());
  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Link inválido ou expirado.');
  END IF;

  SELECT * INTO v_colab FROM public._ponto_resolver_colaborador_cpf(v_link.tenant_id, p_cpf);
  IF v_colab.colaborador_id IS NULL THEN
    RETURN json_build_object('error', 'CPF não encontrado ou colaborador sem ponto ativo.');
  END IF;

  IF COALESCE((SELECT c.exigir_selfie_link FROM public.ponto_configuracao c
                WHERE c.tenant_id = v_link.tenant_id), true)
     AND (p_selfie_url IS NULL OR btrim(p_selfie_url) = '') THEN
    RETURN json_build_object('error', 'É obrigatório tirar a selfie para registrar o ponto.');
  END IF;

  v_afast := public.afastamento_vigente(v_link.tenant_id, v_colab.colaborador_cpf, v_data);
  IF v_afast.id IS NOT NULL THEN
    RETURN json_build_object('error',
      'Você está afastado(a) ' ||
      CASE WHEN v_afast.data_fim IS NOT NULL
        THEN 'até ' || to_char(v_afast.data_fim, 'DD/MM/YYYY')
        ELSE 'por tempo indeterminado' END ||
      '. Durante o afastamento seus dias ficam abonados automaticamente — não é necessário registrar ponto.');
  END IF;

  SELECT hora_marcacao, tipo_marcacao INTO v_ultima
  FROM public.ponto_marcacoes
  WHERE tenant_id = v_link.tenant_id
    AND colaborador_cpf = v_colab.colaborador_cpf
    AND data_marcacao = v_data
  ORDER BY hora_marcacao DESC, created_at DESC
  LIMIT 1;

  IF v_ultima.tipo_marcacao IS NULL THEN
    v_esperado := 'entrada';
  ELSIF COALESCE(public.ponto_classifica_tipo(v_ultima.tipo_marcacao), 'in') = 'in' THEN
    v_esperado := 'saida';
  ELSE
    v_esperado := 'entrada';
  END IF;

  v_tipo := p_tipo_marcacao;
  IF v_tipo = 'saida_almoco' THEN v_tipo := 'saida'; END IF;
  IF v_tipo = 'retorno_almoco' THEN v_tipo := 'entrada'; END IF;
  IF v_tipo IS NULL OR v_tipo = 'batida' THEN v_tipo := v_esperado; END IF;

  IF v_tipo NOT IN ('entrada', 'saida') THEN
    RETURN json_build_object('error', 'Tipo de marcação inválido.');
  END IF;

  IF v_tipo <> v_esperado THEN
    IF v_esperado = 'saida' THEN
      RETURN json_build_object('error',
        'Sua última marcação foi uma ENTRADA — a próxima deve ser uma SAÍDA. Se precisar corrigir algum horário, use "Solicitar Ajuste de Ponto".');
    ELSE
      RETURN json_build_object('error',
        'Sua última marcação foi uma SAÍDA — a próxima deve ser uma ENTRADA. Se precisar corrigir algum horário, use "Solicitar Ajuste de Ponto".');
    END IF;
  END IF;

  BEGIN
    INSERT INTO public.ponto_marcacoes (
      tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
      data_marcacao, hora_marcacao, tipo_marcacao,
      latitude, longitude, dispositivo, hash_marcacao, marcacao_original,
      endereco_geolocalizacao, selfie_url, selfie_nome
    ) VALUES (
      v_link.tenant_id, public.ponto_empresa_do_colaborador(v_colab.colaborador_id),
      v_colab.colaborador_id, v_colab.colaborador_nome, v_colab.colaborador_cpf,
      v_data, v_hora, v_tipo, p_latitude, p_longitude, 'mobile_web',
      encode(sha256((v_colab.colaborador_cpf || v_data::text || v_hora::text || v_tipo || clock_timestamp()::text)::bytea), 'hex'),
      true, p_endereco, p_selfie_url, p_selfie_nome
    ) RETURNING id INTO v_marcacao_id;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    RETURN json_build_object('error', COALESCE(v_err, 'Não foi possível registrar agora.'));
  END;

  RETURN json_build_object(
    'success', true,
    'marcacao_id', v_marcacao_id,
    'colaborador_nome', v_colab.colaborador_nome,
    'tipo_marcacao', v_tipo,
    'hora', to_char(v_hora, 'HH24:MI:SS'),
    'data', to_char(v_data, 'DD/MM/YYYY')
  );
END;
$fn$;
  $ptsql$;
END
$ptdo$;

REVOKE EXECUTE ON FUNCTION public.registrar_ponto_externo_cpf(text, text, text, double precision, double precision, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.registrar_ponto_externo_cpf(text, text, text, double precision, double precision, text, text, text) TO anon, authenticated;

-- ── BLOCO 2: registrar_ponto_externo (link legado por colaborador) ──────────
DO $ptdo$
BEGIN
  EXECUTE $ptsql$
CREATE OR REPLACE FUNCTION public.registrar_ponto_externo(
  p_token text,
  p_tipo_marcacao text DEFAULT NULL,
  p_latitude double precision DEFAULT NULL,
  p_longitude double precision DEFAULT NULL,
  p_endereco text DEFAULT NULL,
  p_selfie_url text DEFAULT NULL,
  p_selfie_nome text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_link RECORD; v_marcacao_id UUID; v_hora TIME; v_data DATE;
  v_now TIMESTAMP; v_err TEXT; v_ultimo TEXT; v_tipo TEXT;
BEGIN
  v_now := timezone('America/Sao_Paulo', now());
  v_hora := v_now::TIME;
  v_data := v_now::DATE;

  SELECT * INTO v_link FROM public.ponto_links
  WHERE token = p_token AND ativo = true
    AND (data_expiracao IS NULL OR data_expiracao > now());
  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Link inválido ou expirado.');
  END IF;

  SELECT tipo_marcacao INTO v_ultimo
  FROM public.ponto_marcacoes
  WHERE tenant_id = v_link.tenant_id
    AND colaborador_cpf = v_link.colaborador_cpf
    AND data_marcacao = v_data
  ORDER BY hora_marcacao DESC, created_at DESC
  LIMIT 1;

  IF v_ultimo IS NULL THEN
    v_tipo := 'entrada';
  ELSIF v_ultimo IN ('entrada', 'retorno_almoco') THEN
    v_tipo := 'saida';
  ELSE
    v_tipo := 'entrada';
  END IF;

  BEGIN
    INSERT INTO public.ponto_marcacoes (
      tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
      data_marcacao, hora_marcacao, tipo_marcacao,
      latitude, longitude, dispositivo, hash_marcacao, marcacao_original,
      endereco_geolocalizacao, selfie_url, selfie_nome
    ) VALUES (
      v_link.tenant_id, public.ponto_empresa_do_colaborador(v_link.colaborador_id::uuid),
      v_link.colaborador_id::uuid, v_link.colaborador_nome, v_link.colaborador_cpf,
      v_data, v_hora, v_tipo, p_latitude, p_longitude, 'mobile_web',
      encode(sha256((v_link.colaborador_cpf || v_data::text || v_hora::text || v_tipo || clock_timestamp()::text)::bytea), 'hex'),
      true, p_endereco, p_selfie_url, p_selfie_nome
    ) RETURNING id INTO v_marcacao_id;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    RETURN json_build_object('error', COALESCE(v_err, 'Não foi possível registrar agora.'));
  END;

  RETURN json_build_object(
    'success', true,
    'marcacao_id', v_marcacao_id,
    'colaborador_nome', v_link.colaborador_nome,
    'tipo_marcacao', v_tipo,
    'hora', to_char(v_hora, 'HH24:MI:SS'),
    'data', to_char(v_data, 'DD/MM/YYYY')
  );
END;
$fn$;
  $ptsql$;
END
$ptdo$;

REVOKE EXECUTE ON FUNCTION public.registrar_ponto_externo(text, text, double precision, double precision, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.registrar_ponto_externo(text, text, double precision, double precision, text, text, text) TO anon, authenticated;

-- ── BLOCO 3 (conferência) — RODE SEPARADO. Esperado: 2 linhas, grava_empresa=true
--   SELECT p.proname AS objeto,
--          (pg_get_functiondef(p.oid) LIKE '%ponto_empresa_do_colaborador%') AS grava_empresa
--   FROM pg_proc p
--   JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
--   WHERE p.proname IN ('registrar_ponto_externo_cpf', 'registrar_ponto_externo')
--   ORDER BY p.proname;
