-- ============================================================================
-- Intervalo pré-assinalado: dar ao RH como REPROCESSAR a competência
--
-- RELATO (Avana, 09/2026): "fiz o cadastro do intervalo pré-assinalado e não
-- está aparecendo"; precisa que agosto passe a considerar a declaração para
-- poder fechar o ponto.
--
-- O QUE ACONTECE
-- A declaração não é lida na hora de exibir: ela é aplicada no momento em que
-- o dia é CONSOLIDADO. O gatilho trg_ponto_diario_pre_assinalacao é BEFORE
-- INSERT OR UPDATE em ponto_diario — grava ali intervalo_origem e
-- intervalo_pre_assinalado_minutos, e o gatilho de supressão (que roda logo
-- depois) usa esses campos para descontar o intervalo declarado.
--
-- Quem cadastra a declaração DEPOIS do mês corrido tem vigência retroativa no
-- papel, mas os dias de agosto já foram gravados quando nada existia: ficaram
-- com intervalo_origem NULL e, por consequência, com supressão TOTAL do
-- intervalo (he_intervalo_suprimido_minutos > 0). Nada revisita esses dias.
--
-- O efeito é triplo e todo ele visível para o cliente:
--   · o espelho não imprime a linha "Interv. pré-assinalado (P)";
--   · o relatório de pré-assinalação não traz o dia;
--   · o pacote da folha SOMA a supressão indevida como verba indenizatória —
--     é o que impede o fechamento correto da competência.
--
-- As duas telas já AVISAM que "dias já apurados só mudam quando forem
-- reconsolidados" — no cadastro e na exclusão. O que faltava era o meio de
-- fazer isso. Esta migration entrega esse meio.
--
-- O QUE FAZ
-- ponto_reprocessar_pre_assinalacao(tenant, competência, empresa): re-dispara
-- a consolidação apenas nos dias em que o valor gravado DIVERGE do que a
-- declaração vigente manda hoje, e apaga os alertas de intervalo suprimido que
-- perderam fundamento.
--
-- GARANTIAS (medidas em réplica antes de escrever)
--   · Cirúrgico: o UPDATE só faz os gatilhos recalcularem. Comparação coluna a
--     coluna mostrou mudança APENAS em intervalo_origem e
--     he_intervalo_suprimido_minutos — horas trabalhadas, horas extras,
--     batidas e status ficam idênticos. O saldo do colaborador não é tocado.
--   · Respeita o fechamento: competência fechada NÃO é reprocessada às
--     escondidas. A função devolve recado pedindo a reabertura formal (que já
--     existe, é auditada, e é o gesto certo).
--   · Respeita a Súmula 338: batida real de almoço continua vencendo o
--     declarado — quem tem almoço batido volta a 'marcado', não a declarado.
--   · Idempotente: rodar de novo não encontra divergência e não faz nada.
--   · Rastreável: cada linha alterada fica registrada em ponto_audit_log com o
--     estado anterior completo (trg_audit_ponto_diario).
-- ============================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.ponto_reprocessar_pre_assinalacao(
  p_tenant_id   uuid,
  p_competencia text,                    -- 'AAAA-MM'
  p_empresa_id  uuid DEFAULT NULL        -- NULL = todas as empresas do cliente
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_ini      date;
  v_fim      date;
  v_ids      uuid[];
  v_dias     int := 0;
  v_pre      int := 0;
  v_alertas  int := 0;
BEGIN
  IF p_tenant_id IS NULL OR COALESCE(p_competencia,'') !~ '^\d{4}-\d{2}$' THEN
    RETURN json_build_object('error','Informe o cliente e a competência no formato AAAA-MM.');
  END IF;

  -- Chamada pelo aplicativo só mexe no próprio cliente. No SQL Editor não há
  -- usuário (auth.uid() é NULL) e o parâmetro vale.
  IF auth.uid() IS NOT NULL
     AND to_regprocedure('public.get_user_tenant_id()') IS NOT NULL
     AND p_tenant_id IS DISTINCT FROM public.get_user_tenant_id() THEN
    RETURN json_build_object('error','Sem permissão para reprocessar outro cliente.');
  END IF;

  v_ini := (p_competencia || '-01')::date;
  v_fim := (v_ini + interval '1 month - 1 day')::date;

  -- Competência fechada não é remexida por baixo do pano: reabrir é um gesto
  -- do RH, registrado, e existe tela para isso.
  IF EXISTS (
    SELECT 1 FROM public.ponto_fechamentos f
    WHERE f.tenant_id = p_tenant_id
      AND f.competencia = p_competencia
      AND f.status = 'fechado'
      AND (p_empresa_id IS NULL OR f.empresa_id IS NULL OR f.empresa_id = p_empresa_id)
  ) THEN
    RETURN json_build_object(
      'error',
      'A folha de ' || to_char(v_ini,'MM/YYYY') || ' está fechada. Reabra a competência '
      || 'para reprocessar e feche de novo em seguida.');
  END IF;

  -- Dias em que o gravado DIVERGE do que a declaração vigente manda hoje.
  -- A regra reproduz exatamente a do gatilho: almoço batido vence sempre.
  WITH previsto AS (
    SELECT d.id,
           d.intervalo_origem                  AS origem_gravada,
           d.intervalo_pre_assinalado_minutos  AS pre_gravado,
           CASE
             WHEN d.saida_almoco IS NOT NULL AND d.retorno_almoco IS NOT NULL THEN 'marcado'
             WHEN COALESCE(p.aplica,false) THEN 'pre_assinalado'
             ELSE NULL
           END AS origem_esperada,
           CASE
             WHEN (d.saida_almoco IS NULL OR d.retorno_almoco IS NULL)
                  AND COALESCE(p.aplica,false) THEN p.intervalo_minutos
             ELSE NULL
           END AS pre_esperado
    FROM public.ponto_diario d
    LEFT JOIN LATERAL public.ponto_pre_assinalacao_do_dia(
           d.tenant_id, d.colaborador_cpf, d.colaborador_id::text, d.data) p ON true
    WHERE d.tenant_id = p_tenant_id
      AND d.data BETWEEN v_ini AND v_fim
      AND (p_empresa_id IS NULL OR d.empresa_id = p_empresa_id)
  )
  SELECT COALESCE(array_agg(id), ARRAY[]::uuid[])
    INTO v_ids
  FROM previsto
  WHERE origem_esperada IS DISTINCT FROM origem_gravada
     OR pre_esperado    IS DISTINCT FROM pre_gravado;

  IF array_length(v_ids, 1) IS NULL THEN
    RETURN json_build_object(
      'success', true, 'dias_reprocessados', 0, 'dias_pre_assinalados', 0,
      'alertas_removidos', 0,
      'aviso', 'Nada a reprocessar: os dias da competência já refletem as declarações vigentes.');
  END IF;

  -- O trabalho é este: tocar a linha faz os gatilhos recalcularem.
  UPDATE public.ponto_diario SET updated_at = now() WHERE id = ANY(v_ids);
  GET DIAGNOSTICS v_dias = ROW_COUNT;

  SELECT count(*) INTO v_pre
  FROM public.ponto_diario
  WHERE id = ANY(v_ids) AND intervalo_origem = 'pre_assinalado';

  -- O gatilho de supressão só INSERE alerta, nunca retira. Sem esta limpeza o
  -- Compliance seguiria acusando supressão nos dias que passaram a ter o
  -- intervalo regularmente declarado.
  WITH limpos AS (
    DELETE FROM public.ponto_alertas a
    USING public.ponto_diario d
    WHERE a.tenant_id = p_tenant_id
      AND a.tipo = 'intervalo_suprimido'
      AND d.id = ANY(v_ids)
      AND a.colaborador_cpf   = d.colaborador_cpf
      AND a.data_referencia   = d.data
      AND COALESCE(d.he_intervalo_suprimido_minutos, 0) = 0
    RETURNING a.id
  )
  SELECT count(*) INTO v_alertas FROM limpos;

  RETURN json_build_object(
    'success', true,
    'competencia', p_competencia,
    'dias_reprocessados', v_dias,
    'dias_pre_assinalados', v_pre,
    'alertas_removidos', v_alertas);
END;
$function$;

COMMENT ON FUNCTION public.ponto_reprocessar_pre_assinalacao(uuid, text, uuid) IS
  'Reaplica as declaracoes de intervalo pre-assinalado aos dias JA consolidados de uma competencia (cadastro retroativo). Toca apenas os dias divergentes; nao altera horas, batidas nem status; recusa competencia fechada; remove os alertas de intervalo suprimido que perderam fundamento. Sumula 338/TST.';

GRANT EXECUTE ON FUNCTION public.ponto_reprocessar_pre_assinalacao(uuid, text, uuid) TO authenticated;
