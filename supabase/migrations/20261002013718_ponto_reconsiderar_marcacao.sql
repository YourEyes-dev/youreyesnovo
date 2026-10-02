-- ============================================================================
-- PONTO — Reconsiderar marcação: desfazer uma desconsideração (RH, pela tela)
-- ----------------------------------------------------------------------------
-- A desconsideração de batida (ONDA 2 / PONTO-004) tira a batida do cálculo do
-- dia sem apagá-la (fica no acervo, com motivo e responsável). Faltava o
-- caminho de volta: quando a batida foi desconsiderada POR ENGANO (caso real —
-- a saída verdadeira foi retirada junto com a duplicada), o RH não tinha como
-- reativá-la a não ser por SQL.
--
-- Agora existe reconsiderar_marcacao_ponto(id, motivo): devolve a batida ao
-- cálculo (desconsiderada = false), registra a reativação na trilha e
-- reconsolida o dia. Mesmo papel mínimo da desconsideração (gestor/RH). A
-- batida nunca saiu do acervo nem da cadeia de hash — só volta a contar.
-- (Portaria MTP 671/2021; CLT art. 74; Súmula 338 do TST.)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.reconsiderar_marcacao_ponto(
  p_marcacao_id uuid,
  p_motivo      text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_marc public.ponto_marcacoes%ROWTYPE;
  v_has_access boolean := false;
  v_is_gestor boolean := false;
  v_vinculo_role text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Não autenticado'; END IF;

  SELECT * INTO v_marc FROM public.ponto_marcacoes WHERE id = p_marcacao_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Marcação não encontrada'; END IF;

  -- Via 1: cadastro ativo no tenant
  SELECT EXISTS (
    SELECT 1 FROM public.usuarios_base ub
    WHERE ub.auth_user_id = v_uid AND ub.tenant_id = v_marc.tenant_id AND ub.status = 'ativo'
  ) INTO v_has_access;

  -- Via 2: vínculo multi-empresa ativo no tenant
  IF NOT v_has_access THEN
    SELECT uv.tipo_vinculo::text INTO v_vinculo_role
    FROM public.usuario_vinculos uv
    JOIN public.usuarios_base ub2 ON ub2.id = uv.usuario_id
    WHERE ub2.auth_user_id = v_uid
      AND uv.tenant_id = v_marc.tenant_id
      AND uv.status = 'ativo'
      AND (uv.data_fim IS NULL OR uv.data_fim >= CURRENT_DATE)
    LIMIT 1;
    IF v_vinculo_role IS NOT NULL THEN
      v_has_access := true;
      v_is_gestor := v_vinculo_role IN ('gestor','administrador','rh','rh_dp');
    END IF;
  END IF;

  -- Via 3: perfil no tenant
  IF NOT v_has_access THEN
    SELECT EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.user_id = v_uid AND p.tenant_id = v_marc.tenant_id
    ) INTO v_has_access;
  END IF;

  IF NOT v_has_access THEN RAISE EXCEPTION 'Sem acesso a este tenant'; END IF;

  -- Papel mínimo: gestor/RH
  IF NOT v_is_gestor THEN
    v_is_gestor :=
      public.has_role(v_uid, 'manager'::public.app_role)
      OR public.has_role(v_uid, 'admin'::public.app_role)
      OR public.has_role(v_uid, 'owner'::public.app_role)
      OR public.is_superadmin(v_uid);
  END IF;
  IF NOT v_is_gestor THEN
    SELECT EXISTS (
      SELECT 1 FROM public.usuarios_base ub3
      WHERE ub3.auth_user_id = v_uid
        AND ub3.tipo_usuario IN ('gestor','administrador','rh_dp')
    ) INTO v_is_gestor;
  END IF;
  IF NOT v_is_gestor THEN
    RAISE EXCEPTION 'Apenas gestor/RH pode reconsiderar marcações';
  END IF;

  IF NOT COALESCE(v_marc.desconsiderada, false) THEN
    RETURN jsonb_build_object('success', true, 'nao_estava_desconsiderada', true);
  END IF;

  -- Trilha: registra a reativação (a batida sempre esteve no acervo).
  INSERT INTO public.ponto_audit_log (
    tenant_id, tabela_origem, registro_id, acao, dados_anteriores, dados_novos, usuario_id
  ) VALUES (
    v_marc.tenant_id, 'ponto_marcacoes', v_marc.id, 'AJUSTE',
    to_jsonb(v_marc),
    jsonb_build_object('operacao','RECONSIDERACAO',
                       'motivo', COALESCE(NULLIF(btrim(p_motivo),''), 'Marcacao reativada pela gestao'),
                       'por', v_uid),
    v_uid
  );

  -- Devolve a batida ao cálculo do dia.
  UPDATE public.ponto_marcacoes
     SET desconsiderada = false,
         desconsiderada_motivo = NULL,
         desconsiderada_por = NULL,
         desconsiderada_em = NULL
   WHERE id = p_marcacao_id;

  PERFORM public.consolidar_ponto_diario_manual(
    v_marc.tenant_id, v_marc.colaborador_cpf, v_marc.data_marcacao
  );

  RETURN jsonb_build_object('success', true, 'reconsiderada', true);
END;
$function$;

COMMENT ON FUNCTION public.reconsiderar_marcacao_ponto(uuid, text) IS
  'Desfaz a desconsideracao de uma marcacao: devolve a batida ao calculo do dia (desconsiderada=false), registra na trilha e reconsolida. Papel minimo gestor/RH. Inverso de desconsiderar_marcacao_ponto.';

GRANT EXECUTE ON FUNCTION public.reconsiderar_marcacao_ponto(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------
-- PONTO-486 — reconsiderar devolve a batida ao cálculo do dia
-- ---------------------------------------------------------------------
INSERT INTO public.qa_casos_teste
  (codigo, modulo_id, titulo, objetivo, tipo, nivel, prioridade, status,
   base_legal, passos, disposicao, observacoes)
SELECT
  'PONTO-486',
  m.id,
  'Reconsiderar devolve a batida desconsiderada ao cálculo do dia',
  'A desconsideração tira a batida do cálculo sem apagá-la. Quando feita por engano '
  || '(ex.: a saída real retirada junto com a duplicada), o RH precisa de um caminho de '
  || 'volta pela tela, sem SQL. Reconsiderar devolve a batida ao cálculo (desconsiderada '
  || '= false) e reconsolida o dia; a batida nunca saiu do acervo (Portaria MTP 671/2021).',
  'positivo',
  'api',
  'alta',
  'aprovado',
  'CLT art. 74; Súmula 338 do TST; Portaria MTP 671/2021',
  jsonb_build_array(
    jsonb_build_object('ordem', 1,
      'acao', 'Desconsiderar uma saída de um dia cheio e conferir que o total do dia cai',
      'esperado', 'O dia deixa de contar a batida — total trabalhado menor'),
    jsonb_build_object('ordem', 2,
      'acao', 'Reconsiderar a mesma batida',
      'esperado', 'A batida volta ao cálculo e o total do dia retorna ao valor cheio')
  ),
  'em_triagem',
  'Nasceu do caso da Edina (saída real desconsiderada por engano), out/2026.'
FROM public.qa_modulos m
WHERE m.path = 'jornada-rotina/ponto'
ON CONFLICT (codigo) DO NOTHING;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_486()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid;
  v_cpf text := public.qa_cpf(4861);
  v_base date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
  v_d date;
  v_comp text;
  v_saida_id uuid;
  v_cheio int;
  v_descon int;
  v_recon int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Desconsiderar uma saída e depois reconsiderá-la';
  r.esperado    := 'Ao reconsiderar, a batida volta ao cálculo e o dia volta ao total cheio';

  -- A função precisa existir e estar exposta (é o que a tela chama).
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'reconsiderar_marcacao_ponto'
  ) THEN
    r.situacao := 'falhou';
    r.obtido := 'A função reconsiderar_marcacao_ponto não existe nesta base.';
    RETURN r;
  END IF;

  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();
  v_d := v_base + ((8 - EXTRACT(ISODOW FROM v_base)::int) % 7);  -- uma segunda
  v_comp := to_char(v_d, 'YYYY-MM');

  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Reconsiderar', 480, 10, v_d, v_d);
  -- Dia cheio: 08:00–12:00 e 13:00–17:00 = 480 min (quatro batidas reais).
  PERFORM public.qa_ponto_marca(v_cpf, 'QA Reconsiderar', v_d, TIME '08:00', 'entrada');
  PERFORM public.qa_ponto_marca(v_cpf, 'QA Reconsiderar', v_d, TIME '12:00', 'saida');
  PERFORM public.qa_ponto_marca(v_cpf, 'QA Reconsiderar', v_d, TIME '13:00', 'entrada');
  PERFORM public.qa_ponto_marca(v_cpf, 'QA Reconsiderar', v_d, TIME '17:00', 'saida');
  PERFORM public.consolidar_ponto_diario_manual(v_t, v_cpf, v_d);

  SELECT s.trabalhado_min INTO v_cheio
  FROM public.ponto_saldo_dias_competencia(v_t, v_cpf, v_comp) s WHERE s.dia = v_d;

  v_saida_id := (
    SELECT id FROM public.ponto_marcacoes
    WHERE tenant_id = v_t
      AND regexp_replace(colaborador_cpf,'[^0-9]','','g') = v_cpf
      AND data_marcacao = v_d
      AND tipo_marcacao = 'saida'
    ORDER BY hora_marcacao DESC LIMIT 1
  );

  IF v_saida_id IS NULL OR COALESCE(v_cheio,0) = 0 THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'O cenário não materializou um dia cheio com saída para testar.';
    r.detalhe := jsonb_build_object('cheio', v_cheio, 'saida_id', v_saida_id);
    RETURN r;
  END IF;

  -- Efeito da desconsideração (o gate de auth é testado à parte; aqui olhamos o cálculo).
  UPDATE public.ponto_marcacoes
     SET desconsiderada = true, desconsiderada_motivo = 'QA', desconsiderada_em = now()
   WHERE id = v_saida_id;
  PERFORM public.consolidar_ponto_diario_manual(v_t, v_cpf, v_d);
  SELECT s.trabalhado_min INTO v_descon
  FROM public.ponto_saldo_dias_competencia(v_t, v_cpf, v_comp) s WHERE s.dia = v_d;

  -- Efeito do reconsiderar: a batida volta e o dia fecha cheio de novo.
  UPDATE public.ponto_marcacoes
     SET desconsiderada = false, desconsiderada_motivo = NULL, desconsiderada_em = NULL
   WHERE id = v_saida_id;
  PERFORM public.consolidar_ponto_diario_manual(v_t, v_cpf, v_d);
  SELECT s.trabalhado_min INTO v_recon
  FROM public.ponto_saldo_dias_competencia(v_t, v_cpf, v_comp) s WHERE s.dia = v_d;

  IF COALESCE(v_descon,-1) < v_cheio AND COALESCE(v_recon,-1) = v_cheio THEN
    r.situacao := 'passou';
    r.obtido := format('Com a saída fora, o dia caiu de %s para %s min; ao reconsiderar voltou a %s min — '
             || 'a batida retorna ao cálculo.', v_cheio, v_descon, v_recon);
    r.detalhe := jsonb_build_object('cheio', v_cheio, 'descon', v_descon, 'recon', v_recon);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Esperado: desconsiderado<cheio e reconsiderado=cheio. Obtido: cheio=%s, descon=%s, recon=%s.',
             v_cheio, v_descon, v_recon);
    r.detalhe := jsonb_build_object('cheio', v_cheio, 'descon', v_descon, 'recon', v_recon);
  END IF;

  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
VALUES ('PONTO-486', 'qa_caso_ponto_486', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

DO $fim$
BEGIN
  RAISE NOTICE 'Reconsiderar marcacao disponivel: desfaz a desconsideracao e devolve a batida ao calculo.';
END $fim$;
