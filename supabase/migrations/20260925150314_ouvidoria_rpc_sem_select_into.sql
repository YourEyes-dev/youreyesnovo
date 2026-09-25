-- ============================================================================
-- Ouvidoria: RPCs sem "SELECT ... INTO" (compatível com o SQL Editor)
--
-- O SQL Editor do Supabase tem um auxiliar que "habilita RLS em tabelas novas":
-- ele lê o texto cru e trata cada "SELECT ... INTO <nome>" como criação de tabela,
-- injetando "ALTER TABLE <nome> ENABLE ROW LEVEL SECURITY" DENTRO do corpo da
-- função — o que quebra a string com aspas-dólar ("unterminated dollar-quoted
-- string"). No db push/psql isso não acontece (por isso o staging não pegou).
--
-- Correção: as funções deixam de usar "SELECT ... INTO" e passam a atribuir por
-- subconsulta escalar (v := (SELECT ...)) e por to_json(...). Comportamento e
-- retornos idênticos. Só CREATE OR REPLACE — nenhuma estrutura ou dado muda.
-- ============================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.buscar_ouvidoria_link_por_token(p_token text)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_tenant uuid;
BEGIN
  v_tenant := (
    SELECT tenant_id FROM public.ouvidoria_links
    WHERE token = p_token AND ativo = true
      AND (data_expiracao IS NULL OR data_expiracao > now())
    LIMIT 1
  );
  IF v_tenant IS NULL THEN
    RETURN json_build_object('error', 'Link inválido ou expirado');
  END IF;
  RETURN json_build_object('valido', true, 'empresa_nome', public._ouvidoria_nome_empresa(v_tenant));
END;
$fn$;

CREATE OR REPLACE FUNCTION public.buscar_colaborador_ouvidoria_por_cpf(p_token text, p_cpf text)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_tenant uuid;
  v_colab json;
BEGIN
  v_tenant := (
    SELECT tenant_id FROM public.ouvidoria_links
    WHERE token = p_token AND ativo = true
      AND (data_expiracao IS NULL OR data_expiracao > now())
    LIMIT 1
  );
  IF v_tenant IS NULL THEN
    RETURN json_build_object('error', 'Link inválido ou expirado');
  END IF;

  v_colab := (
    SELECT json_build_object('nome', nome, 'empresa_id', empresa_id)
    FROM public._ouvidoria_resolver_colaborador_cpf(v_tenant, p_cpf)
  );
  IF v_colab IS NULL THEN
    RETURN json_build_object('encontrado', false);
  END IF;

  RETURN json_build_object(
    'encontrado', true,
    'nome', v_colab->>'nome',
    'empresa_id', v_colab->>'empresa_id',
    'empresa_nome', public._ouvidoria_nome_empresa(v_tenant)
  );
END;
$fn$;

CREATE OR REPLACE FUNCTION public.registrar_manifestacao_externa(
  p_token text,
  p_tipo text,
  p_assunto text,
  p_mensagem text,
  p_anonimo boolean,
  p_cpf text DEFAULT NULL,
  p_nome text DEFAULT NULL,
  p_email text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_tenant uuid;
  v_rot json;
  v_colab json;
  v_assunto text := NULLIF(TRIM(COALESCE(p_assunto,'')), '');
  v_mensagem text := NULLIF(TRIM(COALESCE(p_mensagem,'')), '');
  v_cpf_digits text := regexp_replace(COALESCE(p_cpf,''), '\D', '', 'g');
  v_nome text := NULLIF(TRIM(COALESCE(p_nome,'')), '');
  v_email text := NULLIF(TRIM(COALESCE(p_email,'')), '');
  v_empresa_id uuid;
  v_protocolo text;
  v_tentativa int := 0;
BEGIN
  v_tenant := (
    SELECT tenant_id FROM public.ouvidoria_links
    WHERE token = p_token AND ativo = true
      AND (data_expiracao IS NULL OR data_expiracao > now())
    LIMIT 1
  );
  IF v_tenant IS NULL THEN
    RETURN json_build_object('error', 'Link inválido ou expirado');
  END IF;

  IF p_tipo NOT IN ('sugestao','reclamacao','denuncia','elogio','duvida') THEN
    RETURN json_build_object('error', 'Tipo de manifestação inválido');
  END IF;
  IF v_assunto IS NULL OR v_mensagem IS NULL THEN
    RETURN json_build_object('error', 'Preencha o assunto e a mensagem');
  END IF;
  v_assunto := left(v_assunto, 200);
  v_mensagem := left(v_mensagem, 5000);

  IF COALESCE(p_anonimo, false) = false THEN
    IF length(v_cpf_digits) = 11 THEN
      v_colab := (
        SELECT json_build_object('nome', nome, 'empresa_id', empresa_id)
        FROM public._ouvidoria_resolver_colaborador_cpf(v_tenant, v_cpf_digits)
      );
      IF v_colab IS NOT NULL THEN
        v_empresa_id := (v_colab->>'empresa_id')::uuid;
        IF v_nome IS NULL THEN v_nome := v_colab->>'nome'; END IF;
      END IF;
    END IF;
  ELSE
    v_cpf_digits := NULL;
    v_nome := NULL;
    v_email := NULL;
    v_empresa_id := NULL;
  END IF;

  v_rot := (
    SELECT to_json(t) FROM (
      SELECT responsavel_id, responsavel_nome, departamento_responsavel
      FROM public.ouvidoria_roteamento
      WHERE tenant_id = v_tenant AND tipo_manifestacao = p_tipo AND ativo = true
      LIMIT 1
    ) t
  );

  LOOP
    v_tentativa := v_tentativa + 1;
    v_protocolo := 'OUV-' || to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'YYYYMMDD') || '-' ||
                   upper(substring(encode(gen_random_bytes(4), 'hex') from 1 for 6));
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.ouvidoria WHERE tenant_id = v_tenant AND protocolo = v_protocolo
    );
    IF v_tentativa >= 8 THEN
      v_protocolo := 'OUV-' || upper(substring(encode(gen_random_bytes(8), 'hex') from 1 for 12));
      EXIT;
    END IF;
  END LOOP;

  INSERT INTO public.ouvidoria (
    tenant_id, tipo, assunto, mensagem, anonimo,
    autor_id, autor_nome, autor_email, autor_cpf, empresa_id,
    status, prioridade, anexos, origem, protocolo,
    responsavel_id, responsavel_nome, departamento_destino
  ) VALUES (
    v_tenant, p_tipo, v_assunto, v_mensagem, COALESCE(p_anonimo, false),
    NULL, v_nome, v_email, v_cpf_digits, v_empresa_id,
    'pendente', 'normal', '[]'::jsonb, 'link_publico', v_protocolo,
    (v_rot->>'responsavel_id')::uuid, v_rot->>'responsavel_nome', v_rot->>'departamento_responsavel'
  );

  RETURN json_build_object('success', true, 'protocolo', v_protocolo);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.buscar_ouvidoria_link_por_ponto_token(p_ponto_token text)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_tenant uuid;
  v_token text;
BEGIN
  v_tenant := (
    SELECT tenant_id FROM public.ponto_links
    WHERE token = p_ponto_token AND ativo = true
      AND (data_expiracao IS NULL OR data_expiracao > now())
    LIMIT 1
  );
  IF v_tenant IS NULL THEN
    RETURN json_build_object('encontrado', false);
  END IF;

  v_token := (
    SELECT token FROM public.ouvidoria_links
    WHERE tenant_id = v_tenant AND ativo = true
      AND (data_expiracao IS NULL OR data_expiracao > now())
    LIMIT 1
  );
  IF v_token IS NULL THEN
    RETURN json_build_object('encontrado', false);
  END IF;

  RETURN json_build_object('encontrado', true, 'token', v_token);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.consultar_manifestacao_ouvidoria(p_token text, p_protocolo text)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_tenant uuid;
  v_m json;
BEGIN
  v_tenant := (
    SELECT tenant_id FROM public.ouvidoria_links
    WHERE token = p_token AND ativo = true
      AND (data_expiracao IS NULL OR data_expiracao > now())
    LIMIT 1
  );
  IF v_tenant IS NULL THEN
    RETURN json_build_object('error', 'Link inválido ou expirado');
  END IF;

  v_m := (
    SELECT to_json(t) FROM (
      SELECT tipo, assunto, status, resposta, respondido_em, created_at
      FROM public.ouvidoria
      WHERE tenant_id = v_tenant AND protocolo = upper(TRIM(COALESCE(p_protocolo, '')))
      LIMIT 1
    ) t
  );
  IF v_m IS NULL THEN
    RETURN json_build_object('encontrado', false);
  END IF;

  RETURN json_build_object(
    'encontrado', true,
    'tipo', v_m->>'tipo',
    'assunto', v_m->>'assunto',
    'status', v_m->>'status',
    'resposta', v_m->>'resposta',
    'respondido_em', v_m->>'respondido_em',
    'created_at', v_m->>'created_at'
  );
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.buscar_ouvidoria_link_por_token(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.buscar_colaborador_ouvidoria_por_cpf(text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.registrar_manifestacao_externa(text, text, text, text, boolean, text, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.buscar_ouvidoria_link_por_ponto_token(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.consultar_manifestacao_ouvidoria(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.buscar_ouvidoria_link_por_token(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.buscar_colaborador_ouvidoria_por_cpf(text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.registrar_manifestacao_externa(text, text, text, text, boolean, text, text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.buscar_ouvidoria_link_por_ponto_token(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consultar_manifestacao_ouvidoria(text, text) TO anon, authenticated;
