-- Ajuste de ponto pelo app do funcionário: parar de morrer com erro técnico
-- =========================================================================
--
-- Sintoma relatado: "Solicitação de Ajuste pelo app do funcionário não está
-- funcionando". O pedido saía do celular e voltava a mensagem crua do banco
-- "Período AAAA-MM está fechado. Alterações bloqueadas." (ou a do dia
-- abonado), sem que o funcionário tivesse como saber o que fazer.
--
-- A cadeia é esta: gravar em ponto_ajustes dispara
-- trigger_consolidar_ponto_ajustes -> consolidar_ponto_por_ajuste ->
-- consolidar_ponto_diario_manual, que faz INSERT ... ON CONFLICT DO UPDATE em
-- ponto_diario; o UPDATE acorda trg_validar_periodo_aberto_ponto_diario, que
-- só libera quem tem cargo — e pelo app o pedido chega como `anon`, sem
-- auth.uid(). Resultado: o mesmo pedido passa quando o RH faz pela folha
-- interna e explode quando o próprio funcionário faz pelo app.
--
-- Duas correções, nesta ordem de importância:
--
-- 1) O fechamento era do TENANT inteiro. ponto_fechamentos é único por
--    (tenant_id, empresa_id, competencia) — ou seja, fecha-se a folha de UMA
--    empresa —, mas a trava olhava só tenant + competência. Fechar a folha da
--    empresa A travava o ajuste de todo mundo das empresas B, C e D do mesmo
--    cliente. Agora a trava compara também a empresa da linha (fechamento sem
--    empresa segue valendo para o cliente inteiro, que é como ele foi criado).
--
-- 2) As rotinas do app passam a CONFERIR antes de gravar e devolver recado em
--    português — período fechado e dia já abonado —, em vez de deixar a
--    exceção do gatilho derrubar a transação inteira. Sem isso, um único dia
--    impedido derrubava o lote inteiro de até 40 itens com um texto técnico.
--
-- Nada aqui afrouxa o fechamento: continua impossível mexer em folha fechada
-- pelo app. O que muda é que a pessoa passa a saber disso.

-- 1) Trava de período fechado, agora ciente da empresa ---------------------
CREATE OR REPLACE FUNCTION public.validar_periodo_aberto_ponto_diario()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_competencia TEXT;
  v_fechado BOOLEAN;
  v_uid uuid := auth.uid();
  v_pode_burlar boolean := false;
BEGIN
  v_competencia := to_char(NEW.data::date, 'YYYY-MM');

  -- Fechamento é por empresa (chave única tenant+empresa+competência).
  -- Fechamento antigo, gravado sem empresa, vale para o cliente inteiro.
  SELECT EXISTS(
    SELECT 1 FROM ponto_fechamentos f
    WHERE f.tenant_id = NEW.tenant_id
      AND f.competencia = v_competencia
      AND f.status = 'fechado'
      AND (f.empresa_id IS NULL OR f.empresa_id = NEW.empresa_id)
  ) INTO v_fechado;

  IF TG_OP = 'UPDATE' AND v_fechado AND NEW.status != 'justificado' THEN
    -- Permitir override para gestores/admins/proprietários/RH/superadmin
    IF v_uid IS NOT NULL THEN
      SELECT
        public.has_role(v_uid, 'manager'::public.app_role)
        OR public.has_role(v_uid, 'admin'::public.app_role)
        OR public.has_role(v_uid, 'owner'::public.app_role)
        OR public.has_role(v_uid, 'superadmin'::public.app_role)
        OR EXISTS (
          SELECT 1 FROM public.usuarios_base ub
          WHERE ub.auth_user_id = v_uid
            AND ub.tenant_id = NEW.tenant_id
            AND ub.tipo_usuario IN ('gestor','administrador','proprietario','rh','rh_dp')
        )
        OR EXISTS (
          SELECT 1 FROM public.usuario_vinculos uv
          JOIN public.usuarios_base ub2 ON ub2.id = uv.usuario_id
          WHERE ub2.auth_user_id = v_uid
            AND uv.tenant_id = NEW.tenant_id
            AND uv.status = 'ativo'
            AND uv.tipo_vinculo::text IN ('gestor','administrador','proprietario','rh')
        )
      INTO v_pode_burlar;
    END IF;

    IF NOT v_pode_burlar THEN
      RAISE EXCEPTION 'Período % está fechado. Alterações bloqueadas.', v_competencia;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

-- 2) Conferência auxiliar: a competência daquele dia está fechada para a
--    empresa daquele colaborador? Usada pelas rotinas do app antes de gravar,
--    com exatamente o mesmo critério da trava acima.
CREATE OR REPLACE FUNCTION public._ponto_competencia_fechada(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_data date
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS(
    SELECT 1 FROM public.ponto_fechamentos f
    WHERE f.tenant_id = p_tenant_id
      AND f.competencia = to_char(p_data, 'YYYY-MM')
      AND f.status = 'fechado'
      AND (f.empresa_id IS NULL OR f.empresa_id = p_empresa_id)
  );
$function$;

GRANT EXECUTE ON FUNCTION public._ponto_competencia_fechada(uuid, uuid, date) TO anon, authenticated;

-- 3) Rotina do app com link individual --------------------------------------
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

-- 4) Rotina do app com link compartilhado (identificação por CPF) -----------
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
