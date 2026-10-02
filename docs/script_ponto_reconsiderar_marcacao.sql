-- ============================================================================
-- ENTREGA (produção) — Reconsiderar marcação: desfazer uma desconsideração
-- ----------------------------------------------------------------------------
-- Cole no SQL Editor de PRODUÇÃO. Idempotente (roda duas vezes sem quebrar).
-- Só cria FUNÇÃO (não cria tabela) — não aciona o auto-RLS do editor.
--
-- Cria reconsiderar_marcacao_ponto(id, motivo): devolve ao cálculo do dia uma
-- batida que havia sido desconsiderada (desconsiderada = false), registra a
-- reativação na trilha e reconsolida o dia. Mesmo papel mínimo da
-- desconsideração (gestor/RH). A batida nunca saiu do acervo nem da cadeia de
-- hash — só volta a contar. É o inverso de desconsiderar_marcacao_ponto.
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

  SELECT EXISTS (
    SELECT 1 FROM public.usuarios_base ub
    WHERE ub.auth_user_id = v_uid AND ub.tenant_id = v_marc.tenant_id AND ub.status = 'ativo'
  ) INTO v_has_access;

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

  IF NOT v_has_access THEN
    SELECT EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.user_id = v_uid AND p.tenant_id = v_marc.tenant_id
    ) INTO v_has_access;
  END IF;

  IF NOT v_has_access THEN RAISE EXCEPTION 'Sem acesso a este tenant'; END IF;

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

-- Documentação de testes (idempotente) -------------------------------------
INSERT INTO public.qa_casos_teste
  (codigo, modulo_id, titulo, objetivo, tipo, nivel, prioridade, status,
   base_legal, passos, disposicao, observacoes)
SELECT
  'PONTO-486',
  m.id,
  'Reconsiderar devolve a batida desconsiderada ao cálculo do dia',
  'A desconsideração tira a batida do cálculo sem apagá-la. Quando feita por engano '
  || '(ex.: a saída real retirada junto com a duplicada), o RH precisa de um caminho de '
  || 'volta pela tela, sem SQL. Reconsiderar devolve a batida ao cálculo e reconsolida o dia; '
  || 'a batida nunca saiu do acervo (Portaria MTP 671/2021).',
  'positivo', 'api', 'alta', 'aprovado',
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

-- Conferência final (o editor mostra só o último SELECT) --------------------
SELECT
  EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'reconsiderar_marcacao_ponto'
  ) AS funcao_criada,
  EXISTS (SELECT 1 FROM public.qa_casos_teste WHERE codigo = 'PONTO-486') AS caso_documentado;
