-- ============================================================================
-- Atalho de ajuste (link público): sinaliza se o colaborador está sob
-- intervalo pré-assinalado, para a tela limitar a 1 par (Entrada/Saída).
--
-- POR QUÊ: a tela "dentro do sistema" já detecta a pré-assinalação (lê as
-- tabelas por RLS); o atalho (SolicitarAjusteModal) usa RPC pública sem auth,
-- então não consegue ler ponto_pre_assinalacao direto. Aqui a própria RPC
-- devolve a flag `pre_assinalado`, calculada pelo resolver canônico
-- public.ponto_pre_assinalacao_do_dia (colaborador vence escala, vigência no
-- dia). Jornada de DUAS batidas (Súmula 338, III · Portaria 671): sem marcar
-- almoço. A tela esconde/mescla as batidas de almoço e mostra só 1 par.
--
-- Só altera as funções do schema `externo` (os wrappers em public apenas
-- repassam o JSON). Nenhuma tabela criada — sem pegadinha de auto-RLS.
-- ============================================================================

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


-- ---------------------------------------------------------------------
-- QA PONTO-483 — atalho público sinaliza intervalo pré-assinalado
-- ---------------------------------------------------------------------
INSERT INTO public.qa_casos_teste
  (codigo, modulo_id, titulo, objetivo, tipo, nivel, prioridade, status,
   base_legal, passos, disposicao, observacoes)
SELECT
  'PONTO-483',
  m.id,
  'Atalho de ajuste sinaliza intervalo pré-assinalado',
  'A RPC pública listar_ponto_externo precisa devolver a flag pre_assinalado para o '
  || 'atalho limitar a folha a 1 par (Entrada/Saída). Sem declaração vigente a flag é '
  || 'false; com declaração vigente é true; declaração expirada volta a false.',
  'alternativo',
  'api',
  'alta',
  'aprovado',
  'TST Súmula 338, III · Portaria MTP 671/2021 (jornada de duas batidas)',
  jsonb_build_array(
    jsonb_build_object('ordem', 1, 'acao', 'Chamar a RPC sem declaração vigente',
      'esperado', 'pre_assinalado = false'),
    jsonb_build_object('ordem', 2, 'acao', 'Criar declaração vigente e chamar de novo',
      'esperado', 'pre_assinalado = true'),
    jsonb_build_object('ordem', 3, 'acao', 'Expirar a declaração e chamar de novo',
      'esperado', 'pre_assinalado = false')
  ),
  'em_triagem',
  'Correção dos 4 campos no ajuste para escala pré-assinalada (atalho).'
FROM public.qa_modulos m WHERE m.path = 'jornada-rotina/ponto'
ON CONFLICT (codigo) DO NOTHING;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_483()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid;
  v_cpf text := public.qa_cpf(4831);
  v_tok text := 'qa_pre_483';
  v_sem boolean; v_com boolean; v_exp boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'RPC pública do atalho devolve pre_assinalado conforme a declaração vigente';
  r.esperado := 'Sem declaração=false; com declaração vigente=true; expirada=false';

  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();

  -- Fixture: colaborador + link do atalho (casa por CPF).
  IF NOT EXISTS (SELECT 1 FROM public.admissoes a WHERE a.tenant_id=v_t AND a.cpf=v_cpf) THEN
    PERFORM public.qa_ponto_admissao('QA Pre Atalho', 4831, NULL, CURRENT_DATE - 60);
  END IF;
  DELETE FROM public.ponto_links WHERE tenant_id=v_t AND token=v_tok;
  INSERT INTO public.ponto_links (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf, token, ativo, tipo)
  VALUES (v_t, gen_random_uuid(), 'QA Pre Atalho', v_cpf, v_tok, true, 'colaborador');

  -- Estado limpo de declaração.
  DELETE FROM public.ponto_pre_assinalacao
    WHERE tenant_id=v_t AND regexp_replace(COALESCE(colaborador_cpf,''),'[^0-9]','','g')=v_cpf AND lastro='qa483';

  -- 1) Sem declaração -> false
  v_sem := COALESCE((public.listar_ponto_externo(v_tok, 45)->>'pre_assinalado')::boolean, false);

  -- 2) Declaração individual vigente -> true
  INSERT INTO public.ponto_pre_assinalacao
    (tenant_id, escala_id, colaborador_cpf, intervalo_minutos, intervalo_inicio, intervalo_fim, data_inicio, data_fim, lastro, ativa)
  VALUES
    (v_t, NULL, v_cpf, 60, '12:00', '13:00', CURRENT_DATE - 30, NULL, 'qa483', true);
  v_com := COALESCE((public.listar_ponto_externo(v_tok, 45)->>'pre_assinalado')::boolean, false);

  -- 3) Declaração expirada -> false
  UPDATE public.ponto_pre_assinalacao SET data_fim = CURRENT_DATE - 1
    WHERE tenant_id=v_t AND regexp_replace(COALESCE(colaborador_cpf,''),'[^0-9]','','g')=v_cpf AND lastro='qa483';
  v_exp := COALESCE((public.listar_ponto_externo(v_tok, 45)->>'pre_assinalado')::boolean, false);

  -- Limpeza das fixtures próprias.
  DELETE FROM public.ponto_pre_assinalacao
    WHERE tenant_id=v_t AND regexp_replace(COALESCE(colaborador_cpf,''),'[^0-9]','','g')=v_cpf AND lastro='qa483';
  DELETE FROM public.ponto_links WHERE tenant_id=v_t AND token=v_tok;

  IF v_sem <> false THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: sem declaração vigente a flag veio true (deveria ser false).';
  ELSIF v_com <> true THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: com declaração vigente a flag veio false (deveria ser true).';
  ELSIF v_exp <> false THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: com declaração expirada a flag veio true (deveria ser false).';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'A flag pre_assinalado acompanha a vigência da declaração.';
    r.detalhe := jsonb_build_object('sem', v_sem, 'com', v_com, 'expirada', v_exp);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
VALUES ('PONTO-483', 'qa_caso_ponto_483', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

DO $fim$
BEGIN
  RAISE NOTICE 'Atalho de ajuste sinaliza intervalo pre-assinalado (folha com 1 par).';
END $fim$;
