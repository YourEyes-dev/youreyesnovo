-- ============================================================================
-- HOMOLOGAÇÃO — recria o schema "externo" (funções do link do colaborador)
-- A homologação foi montada copiando só o schema public da produção; o schema
-- externo (pedido de ajuste e folha pelo link do colaborador) nunca chegou e o
-- pedido de ajuste pelo link falhava com: schema "externo" does not exist.
-- Recria o schema e as 4 funções na versão vigente do repositório:
--   listar_ponto_externo / listar_ponto_externo_cpf  (20261001010105)
--   solicitar_ajustes_ponto_externo_batch / _cpf_batch (20260828100000)
-- Não altera dados. Idempotente. Só para a HOMOLOGAÇÃO (produção já tem).
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS externo;
GRANT USAGE ON SCHEMA externo TO anon, authenticated;

CREATE OR REPLACE FUNCTION externo.listar_ponto_externo(p_token text, p_dias integer DEFAULT 45)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_link RECORD;
  v_cpf text;
  v_marcacoes JSONB;
  v_ajustes JSONB;
  v_pre boolean := false;
BEGIN
  SELECT * INTO v_link FROM public.ponto_links
  WHERE token = p_token AND ativo = true
    AND (data_expiracao IS NULL OR data_expiracao > now());
  IF NOT FOUND THEN
    RETURN json_build_object('error','Link inválido ou expirado.');
  END IF;

  v_cpf := regexp_replace(COALESCE(v_link.colaborador_cpf,''), '\D', '', 'g');
  IF length(v_cpf) <> 11 THEN
    -- Sem CPF válido no link, mantém o casamento por id (comportamento antigo).
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', m.id, 'data', m.data_marcacao, 'hora', m.hora_marcacao, 'tipo', m.tipo_marcacao
    ) ORDER BY m.data_marcacao DESC, m.hora_marcacao ASC), '[]'::jsonb)
    INTO v_marcacoes
    FROM public.ponto_marcacoes m
    WHERE m.colaborador_id = v_link.colaborador_id::uuid
      AND m.data_marcacao >= (CURRENT_DATE - (p_dias || ' days')::interval)::date
      AND m.data_marcacao <= CURRENT_DATE;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', a.id, 'data', a.data_referencia, 'hora', a.hora_solicitada, 'tipo', a.tipo_marcacao,
      'tipo_ajuste', a.tipo_ajuste, 'status', a.status, 'motivo', a.motivo
    ) ORDER BY a.data_referencia DESC, a.created_at DESC), '[]'::jsonb)
    INTO v_ajustes
    FROM public.ponto_ajustes a
    WHERE a.colaborador_id = v_link.colaborador_id::uuid
      AND a.data_referencia >= (CURRENT_DATE - (p_dias || ' days')::interval)::date;
  ELSE
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', m.id, 'data', m.data_marcacao, 'hora', m.hora_marcacao, 'tipo', m.tipo_marcacao
    ) ORDER BY m.data_marcacao DESC, m.hora_marcacao ASC), '[]'::jsonb)
    INTO v_marcacoes
    FROM public.ponto_marcacoes m
    WHERE m.tenant_id = v_link.tenant_id
      AND regexp_replace(COALESCE(m.colaborador_cpf,''), '\D', '', 'g') = v_cpf
      AND m.data_marcacao >= (CURRENT_DATE - (p_dias || ' days')::interval)::date
      AND m.data_marcacao <= CURRENT_DATE;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', a.id, 'data', a.data_referencia, 'hora', a.hora_solicitada, 'tipo', a.tipo_marcacao,
      'tipo_ajuste', a.tipo_ajuste, 'status', a.status, 'motivo', a.motivo
    ) ORDER BY a.data_referencia DESC, a.created_at DESC), '[]'::jsonb)
    INTO v_ajustes
    FROM public.ponto_ajustes a
    WHERE a.tenant_id = v_link.tenant_id
      AND regexp_replace(COALESCE(a.colaborador_cpf,''), '\D', '', 'g') = v_cpf
      AND a.data_referencia >= (CURRENT_DATE - (p_dias || ' days')::interval)::date;
  END IF;

  -- Pré-assinalação vigente hoje para este vínculo (resolver canônico).
  v_pre := EXISTS (
    SELECT 1 FROM public.ponto_pre_assinalacao_do_dia(
      v_link.tenant_id, v_cpf, v_link.colaborador_id::text, CURRENT_DATE
    ) WHERE aplica
  );

  RETURN json_build_object(
    'success', true,
    'colaborador_nome', v_link.colaborador_nome,
    'pre_assinalado', v_pre,
    'marcacoes', v_marcacoes,
    'ajustes', v_ajustes
  );
END;
$function$;


CREATE OR REPLACE FUNCTION externo.listar_ponto_externo_cpf(p_token text, p_cpf text, p_dias integer DEFAULT 45)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_link RECORD;
  v_colab RECORD;
  v_cpf text;
  v_marcacoes JSONB;
  v_ajustes JSONB;
  v_pre boolean := false;
BEGIN
  SELECT * INTO v_link FROM public.ponto_links
  WHERE token = p_token AND tipo = 'compartilhado' AND ativo = true
    AND (data_expiracao IS NULL OR data_expiracao > now());
  IF NOT FOUND THEN
    RETURN json_build_object('error','Link inválido ou expirado.');
  END IF;

  SELECT * INTO v_colab FROM public._ponto_resolver_colaborador_cpf(v_link.tenant_id, p_cpf);
  IF v_colab.colaborador_id IS NULL THEN
    RETURN json_build_object('error','CPF não encontrado ou colaborador sem ponto ativo.');
  END IF;

  v_cpf := regexp_replace(COALESCE(v_colab.colaborador_cpf,''), '\D', '', 'g');

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', m.id, 'data', m.data_marcacao, 'hora', m.hora_marcacao, 'tipo', m.tipo_marcacao
  ) ORDER BY m.data_marcacao DESC, m.hora_marcacao ASC), '[]'::jsonb)
  INTO v_marcacoes
  FROM public.ponto_marcacoes m
  WHERE m.tenant_id = v_link.tenant_id
    AND regexp_replace(COALESCE(m.colaborador_cpf,''), '\D', '', 'g') = v_cpf
    AND m.data_marcacao >= (CURRENT_DATE - (p_dias || ' days')::interval)::date
    AND m.data_marcacao <= CURRENT_DATE;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', a.id, 'data', a.data_referencia, 'hora', a.hora_solicitada, 'tipo', a.tipo_marcacao,
    'tipo_ajuste', a.tipo_ajuste, 'status', a.status, 'motivo', a.motivo
  ) ORDER BY a.data_referencia DESC, a.created_at DESC), '[]'::jsonb)
  INTO v_ajustes
  FROM public.ponto_ajustes a
  WHERE a.tenant_id = v_link.tenant_id
    AND regexp_replace(COALESCE(a.colaborador_cpf,''), '\D', '', 'g') = v_cpf
    AND a.data_referencia >= (CURRENT_DATE - (p_dias || ' days')::interval)::date;

  -- Pré-assinalação vigente hoje para este vínculo (resolver canônico).
  v_pre := EXISTS (
    SELECT 1 FROM public.ponto_pre_assinalacao_do_dia(
      v_link.tenant_id, v_cpf, v_colab.colaborador_id::text, CURRENT_DATE
    ) WHERE aplica
  );

  RETURN json_build_object(
    'success', true,
    'colaborador_nome', v_colab.colaborador_nome,
    'pre_assinalado', v_pre,
    'marcacoes', v_marcacoes,
    'ajustes', v_ajustes
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION externo.listar_ponto_externo(text, integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION externo.listar_ponto_externo_cpf(text, text, integer) TO anon, authenticated;

CREATE OR REPLACE FUNCTION externo.solicitar_ajustes_ponto_externo_batch(
  p_token text,
  p_itens jsonb,
  p_motivo text DEFAULT NULL::text,
  p_anexos jsonb DEFAULT '[]'::jsonb
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_link RECORD;
  v_item JSONB;
  v_data DATE;
  v_hora TIME;
  v_tipo TEXT;
  v_hora_original TIME;
  v_tipo_ajuste TEXT;
  v_motivo_item TEXT;
  v_now TIMESTAMPTZ := now();
  v_ids UUID[] := ARRAY[]::UUID[];
  v_id UUID;
  v_count INT := 0;
  v_empresa UUID;
  v_afast public.afastamentos;
BEGIN
  IF p_itens IS NULL OR jsonb_array_length(p_itens) = 0 THEN
    RETURN json_build_object('error','Inclua ao menos uma marcação para ajuste.');
  END IF;
  IF jsonb_array_length(p_itens) > 40 THEN
    RETURN json_build_object('error','Máximo de 40 ajustes por solicitação.');
  END IF;

  SELECT * INTO v_link FROM public.ponto_links
  WHERE token = p_token AND ativo = true
    AND (data_expiracao IS NULL OR data_expiracao > now());
  IF NOT FOUND THEN
    RETURN json_build_object('error','Link inválido ou expirado.');
  END IF;

  v_empresa := COALESCE(
    public.ponto_empresa_do_colaborador(v_link.colaborador_id::uuid),
    public.ponto_empresa_do_cpf(v_link.tenant_id, v_link.colaborador_cpf)
  );

  -- PRIMEIRA passada: só confere. Nada é gravado enquanto houver um item
  -- impedido, e o recado diz qual é o dia e o que fazer com ele.
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_itens) LOOP
    v_data := (v_item->>'data')::date;
    v_hora := (v_item->>'hora')::time;
    v_tipo := v_item->>'tipo';
    v_motivo_item := COALESCE(NULLIF(trim(v_item->>'motivo'),''), NULLIF(trim(p_motivo),''));

    IF v_motivo_item IS NULL OR length(v_motivo_item) < 5 THEN
      RETURN json_build_object('error','Cada ajuste precisa de uma justificativa (mín. 5 caracteres).');
    END IF;
    IF v_tipo NOT IN ('entrada','saida','saida_almoco','retorno_almoco') THEN
      RETURN json_build_object('error','Tipo de marcação inválido: ' || COALESCE(v_tipo,'(vazio)'));
    END IF;
    IF v_data IS NULL OR v_hora IS NULL THEN
      RETURN json_build_object('error','Data e hora são obrigatórios para cada ajuste.');
    END IF;
    IF v_data > CURRENT_DATE THEN
      RETURN json_build_object('error','Não é permitido solicitar ajuste para data futura.');
    END IF;
    IF v_data = CURRENT_DATE AND (v_data + v_hora) > v_now THEN
      RETURN json_build_object('error','Não é permitido solicitar ajuste para horário futuro.');
    END IF;

    IF public._ponto_competencia_fechada(v_link.tenant_id, v_empresa, v_data) THEN
      RETURN json_build_object(
        'error',
        'A folha de ' || to_char(v_data, 'MM/YYYY') ||
        ' já foi fechada pelo RH e não aceita mais ajustes. Fale com o RH: se houver correção a fazer, ele reabre o período.'
      );
    END IF;

    v_afast := public.afastamento_vigente(v_link.tenant_id, v_link.colaborador_cpf, v_data);
    IF v_afast.id IS NOT NULL THEN
      RETURN json_build_object(
        'error',
        'O dia ' || to_char(v_data, 'DD/MM/YYYY') || ' já está abonado por afastamento (' ||
        to_char(v_afast.data_inicio, 'DD/MM/YYYY') || ' a ' ||
        COALESCE(to_char(v_afast.data_fim, 'DD/MM/YYYY'), 'em aberto') ||
        ') — não é preciso pedir ajuste para ele. Retire esse dia e envie os demais.'
      );
    END IF;
  END LOOP;

  -- SEGUNDA passada: grava.
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_itens) LOOP
    v_data := (v_item->>'data')::date;
    v_hora := (v_item->>'hora')::time;
    v_tipo := v_item->>'tipo';
    -- hora_original presente => é correção de uma batida existente
    v_hora_original := NULLIF(v_item->>'hora_original','')::time;
    v_tipo_ajuste := CASE WHEN v_hora_original IS NOT NULL THEN 'correcao' ELSE 'inclusao' END;
    v_motivo_item := COALESCE(NULLIF(trim(v_item->>'motivo'),''), NULLIF(trim(p_motivo),''));

    INSERT INTO public.ponto_ajustes (
      tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
      data_referencia, tipo_ajuste, tipo_marcacao,
      hora_solicitada, hora_original, motivo, status, created_by_nome, anexos
    ) VALUES (
      v_link.tenant_id, v_link.colaborador_id::uuid, v_link.colaborador_nome, v_link.colaborador_cpf,
      v_data, v_tipo_ajuste, v_tipo,
      v_hora, v_hora_original, v_motivo_item, 'pendente',
      v_link.colaborador_nome || ' (link externo)', COALESCE(p_anexos, '[]'::jsonb)
    ) RETURNING id INTO v_id;
    v_ids := v_ids || v_id;
    v_count := v_count + 1;
  END LOOP;

  RETURN json_build_object('success', true, 'total', v_count, 'ids', to_jsonb(v_ids));
END;
$function$;

GRANT EXECUTE ON FUNCTION externo.solicitar_ajustes_ponto_externo_batch(text, jsonb, text, jsonb) TO anon, authenticated;

CREATE OR REPLACE FUNCTION externo.solicitar_ajustes_ponto_externo_cpf_batch(
  p_token text,
  p_cpf text,
  p_itens jsonb,
  p_motivo text DEFAULT NULL::text,
  p_anexos jsonb DEFAULT '[]'::jsonb
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_link RECORD;
  v_colab RECORD;
  v_item JSONB;
  v_data DATE;
  v_hora TIME;
  v_tipo TEXT;
  v_hora_original TIME;
  v_tipo_ajuste TEXT;
  v_motivo_item TEXT;
  v_now TIMESTAMPTZ := now();
  v_ids UUID[] := ARRAY[]::UUID[];
  v_id UUID;
  v_count INT := 0;
  v_empresa UUID;
  v_afast public.afastamentos;
BEGIN
  IF p_itens IS NULL OR jsonb_array_length(p_itens) = 0 THEN
    RETURN json_build_object('error','Inclua ao menos uma marcação para ajuste.');
  END IF;
  IF jsonb_array_length(p_itens) > 40 THEN
    RETURN json_build_object('error','Máximo de 40 ajustes por solicitação.');
  END IF;

  SELECT * INTO v_link FROM public.ponto_links
  WHERE token = p_token AND tipo = 'compartilhado' AND ativo = true
    AND (data_expiracao IS NULL OR data_expiracao > now());
  IF NOT FOUND THEN
    RETURN json_build_object('error','Link inválido ou expirado.');
  END IF;

  SELECT * INTO v_colab FROM public._ponto_resolver_colaborador_cpf(v_link.tenant_id, p_cpf);
  IF v_colab.colaborador_id IS NULL THEN
    RETURN json_build_object('error','CPF não encontrado ou colaborador sem ponto ativo.');
  END IF;

  v_empresa := COALESCE(
    public.ponto_empresa_do_colaborador(v_colab.colaborador_id),
    public.ponto_empresa_do_cpf(v_link.tenant_id, v_colab.colaborador_cpf)
  );

  -- PRIMEIRA passada: só confere (mesmo critério da rotina do link individual).
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_itens) LOOP
    v_data := (v_item->>'data')::date;
    v_hora := (v_item->>'hora')::time;
    v_tipo := v_item->>'tipo';
    v_motivo_item := COALESCE(NULLIF(trim(v_item->>'motivo'),''), NULLIF(trim(p_motivo),''));

    IF v_motivo_item IS NULL OR length(v_motivo_item) < 5 THEN
      RETURN json_build_object('error','Cada ajuste precisa de uma justificativa (mín. 5 caracteres).');
    END IF;
    IF v_tipo NOT IN ('entrada','saida','saida_almoco','retorno_almoco') THEN
      RETURN json_build_object('error','Tipo de marcação inválido: ' || COALESCE(v_tipo,'(vazio)'));
    END IF;
    IF v_data IS NULL OR v_hora IS NULL THEN
      RETURN json_build_object('error','Data e hora são obrigatórios para cada ajuste.');
    END IF;
    IF v_data > CURRENT_DATE THEN
      RETURN json_build_object('error','Não é permitido solicitar ajuste para data futura.');
    END IF;
    IF v_data = CURRENT_DATE AND (v_data + v_hora) > v_now THEN
      RETURN json_build_object('error','Não é permitido solicitar ajuste para horário futuro.');
    END IF;

    IF public._ponto_competencia_fechada(v_link.tenant_id, v_empresa, v_data) THEN
      RETURN json_build_object(
        'error',
        'A folha de ' || to_char(v_data, 'MM/YYYY') ||
        ' já foi fechada pelo RH e não aceita mais ajustes. Fale com o RH: se houver correção a fazer, ele reabre o período.'
      );
    END IF;

    v_afast := public.afastamento_vigente(v_link.tenant_id, v_colab.colaborador_cpf, v_data);
    IF v_afast.id IS NOT NULL THEN
      RETURN json_build_object(
        'error',
        'O dia ' || to_char(v_data, 'DD/MM/YYYY') || ' já está abonado por afastamento (' ||
        to_char(v_afast.data_inicio, 'DD/MM/YYYY') || ' a ' ||
        COALESCE(to_char(v_afast.data_fim, 'DD/MM/YYYY'), 'em aberto') ||
        ') — não é preciso pedir ajuste para ele. Retire esse dia e envie os demais.'
      );
    END IF;
  END LOOP;

  -- SEGUNDA passada: grava.
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_itens) LOOP
    v_data := (v_item->>'data')::date;
    v_hora := (v_item->>'hora')::time;
    v_tipo := v_item->>'tipo';
    v_hora_original := NULLIF(v_item->>'hora_original','')::time;
    v_tipo_ajuste := CASE WHEN v_hora_original IS NOT NULL THEN 'correcao' ELSE 'inclusao' END;
    v_motivo_item := COALESCE(NULLIF(trim(v_item->>'motivo'),''), NULLIF(trim(p_motivo),''));

    INSERT INTO public.ponto_ajustes (
      tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
      data_referencia, tipo_ajuste, tipo_marcacao,
      hora_solicitada, hora_original, motivo, status, created_by_nome, anexos
    ) VALUES (
      v_link.tenant_id, v_colab.colaborador_id, v_colab.colaborador_nome, v_colab.colaborador_cpf,
      v_data, v_tipo_ajuste, v_tipo,
      v_hora, v_hora_original, v_motivo_item, 'pendente',
      v_colab.colaborador_nome || ' (link compartilhado)', COALESCE(p_anexos, '[]'::jsonb)
    ) RETURNING id INTO v_id;
    v_ids := v_ids || v_id;
    v_count := v_count + 1;
  END LOOP;

  RETURN json_build_object('success', true, 'total', v_count, 'ids', to_jsonb(v_ids));
END;
$function$;

GRANT EXECUTE ON FUNCTION externo.solicitar_ajustes_ponto_externo_cpf_batch(text, text, jsonb, text, jsonb) TO anon, authenticated;

-- Conferência
SELECT json_build_object(
  'schema_externo', EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'externo'),
  'funcoes_externo', (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'externo'),
  'wrappers_publicos', (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                         WHERE n.nspname = 'public' AND p.proname IN ('solicitar_ajustes_ponto_externo_batch','solicitar_ajustes_ponto_externo_cpf_batch','listar_ponto_externo','listar_ponto_externo_cpf'))
) AS resultado;
