-- =====================================================================
-- Intervalo pré-assinalado que "não aparece" — reprocessar a competência
--
-- Para colar no SQL Editor. Roda inteiro numa transação; rodar duas vezes
-- não muda nada.
--
-- O QUE A USUÁRIA RELATOU (Avana, 09/2026)
-- "Fiz o cadastro do intervalo pré-assinalado e não está aparecendo."
-- Precisa que AGOSTO passe a considerar a declaração para fechar o ponto.
--
-- O QUE ACONTECEU
-- A declaração está correta e vigente — o cadastro dela não é o problema.
-- O que acontece é que ela não é lida na hora de EXIBIR: ela é aplicada no
-- instante em que o dia é CONSOLIDADO. Quem cadastra depois do mês corrido
-- tem vigência retroativa no papel, mas os dias de agosto já foram gravados
-- quando nada existia — ficaram sem origem de intervalo e, por consequência,
-- com supressão TOTAL do intervalo. Nada revisita esses dias sozinho.
--
-- Por isso o efeito aparece em três lugares ao mesmo tempo:
--   · o espelho não imprime a linha "Interv. pré-assinalado (P)";
--   · o relatório de pré-assinalação não traz os dias;
--   · o pacote da folha SOMA a supressão indevida como verba indenizatória —
--     é o que impede o fechamento correto de agosto.
--
-- A tela já avisava disso ("dias já apurados só mudam quando forem
-- reconsiderados"), no cadastro e na exclusão. O que faltava era o MEIO de
-- fazer a reconsideração. Este script entrega esse meio e o aplica a agosto.
--
-- O QUE ESTE SCRIPT FAZ
--   1. Cria a rotina de reprocessamento (a mesma que passa a existir no
--      botão "Reprocessar competência" da tela).
--   2. Guarda o retrato dos dias de agosto antes de tocar em qualquer coisa.
--   3. Reprocessa agosto do cliente, e só ele.
--
-- MEDIDO EM RÉPLICA ANTES DE ESCREVER
--   · Cirúrgico: comparação coluna a coluna mostrou mudança APENAS em
--     intervalo_origem e he_intervalo_suprimido_minutos. Horas trabalhadas,
--     horas extras, batidas e situação do dia ficam idênticas — o saldo do
--     colaborador não é tocado.
--   · Súmula 338 preservada: dia COM almoço batido continua 'marcado'; só o
--     dia de duas batidas recebe o intervalo declarado.
--   · Competência fechada não é remexida: a rotina recusa e pede a reabertura
--     formal, que já existe e é auditada.
--   · Idempotente: rodar de novo não encontra divergência e não faz nada.
--
-- SOBRE DADO EXISTENTE — COMO DESFAZER
-- A tabela backup_ponto_diario_preassin_20260909 guarda o retrato completo
-- dos dias antes do reprocessamento. O caminho de volta, porém, é mais
-- simples e foi ensaiado: desative a declaração e reprocesse de novo —
-- os dias voltam à origem vazia, a supressão volta ao valor anterior e os
-- alertas retirados são recriados pelo próprio sistema:
--   UPDATE public.ponto_pre_assinalacao SET ativa = false WHERE id = '<id>';
--   SELECT public.ponto_reprocessar_pre_assinalacao('<tenant>', '2026-08');
-- (Restaurar as colunas direto do backup NÃO funciona sozinho: os gatilhos
-- recalculam no próprio UPDATE. Por isso o caminho é desativar e reprocessar.)
--
-- CLIENTE ALVO: o filtro é o texto 'avana', casado contra o nome do cliente e
-- contra razão social / nome fantasia das empresas dele. Se casar com mais de
-- um, ou com nenhum, o script NÃO faz nada e a conferência diz o que houve.
-- =====================================================================

SET lock_timeout = '10s';

-- 1) A rotina de reprocessamento --------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_reprocessar_pre_assinalacao(
  p_tenant_id   uuid,
  p_competencia text,
  p_empresa_id  uuid DEFAULT NULL
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

  IF auth.uid() IS NOT NULL
     AND to_regprocedure('public.get_user_tenant_id()') IS NOT NULL
     AND p_tenant_id IS DISTINCT FROM public.get_user_tenant_id() THEN
    RETURN json_build_object('error','Sem permissão para reprocessar outro cliente.');
  END IF;

  v_ini := (p_competencia || '-01')::date;
  v_fim := (v_ini + interval '1 month - 1 day')::date;

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

  UPDATE public.ponto_diario SET updated_at = now() WHERE id = ANY(v_ids);
  GET DIAGNOSTICS v_dias = ROW_COUNT;

  SELECT count(*) INTO v_pre
  FROM public.ponto_diario
  WHERE id = ANY(v_ids) AND intervalo_origem = 'pre_assinalado';

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

-- 2) Retrato dos dias ANTES de tocar em qualquer coisa -----------------------
-- Só nasce se o filtro casar com exatamente UM cliente.
CREATE TABLE IF NOT EXISTS public.backup_ponto_diario_preassin_20260909 AS
WITH alvo AS MATERIALIZED (
  SELECT DISTINCT t.id
  FROM public.tenants t
  LEFT JOIN public.empresa_cadastro e ON e.tenant_id = t.id
  WHERE t.nome ILIKE '%avana%'
     OR e.razao_social ILIKE '%avana%'
     OR e.nome_fantasia ILIKE '%avana%'
), unico AS MATERIALIZED (
  SELECT a.id FROM alvo a WHERE (SELECT count(*) FROM alvo) = 1
)
SELECT d.*
FROM public.ponto_diario d
JOIN unico u ON u.id = d.tenant_id
WHERE d.data BETWEEN '2026-08-01' AND '2026-08-31';

-- =====================================================================
-- 3) REPROCESSAMENTO + CONFERÊNCIA — o editor mostra só este resultado
--
-- Esperado: situacao = 'ok', com o nome do cliente e a contagem de dias.
-- Se vier 'NENHUM' ou 'MAIS DE UM', nada foi alterado: me mande o
-- resultado que eu ajusto o filtro para o identificador exato.
-- =====================================================================
WITH alvo AS MATERIALIZED (
  SELECT DISTINCT t.id, t.nome
  FROM public.tenants t
  LEFT JOIN public.empresa_cadastro e ON e.tenant_id = t.id
  WHERE t.nome ILIKE '%avana%'
     OR e.razao_social ILIKE '%avana%'
     OR e.nome_fantasia ILIKE '%avana%'
), quantos AS MATERIALIZED (
  SELECT count(*) AS n FROM alvo
), unico AS MATERIALIZED (
  SELECT a.id, a.nome FROM alvo a, quantos q WHERE q.n = 1
), execucao AS MATERIALIZED (
  SELECT u.nome,
         public.ponto_reprocessar_pre_assinalacao(u.id, '2026-08') AS r
  FROM unico u
)
SELECT
  CASE (SELECT n FROM quantos)
    WHEN 0 THEN 'NENHUM cliente casou com o filtro — nada foi alterado'
    WHEN 1 THEN 'ok'
    ELSE 'MAIS DE UM cliente casou com o filtro — nada foi alterado'
  END                                                   AS situacao,
  (SELECT nome FROM execucao)                           AS cliente,
  (SELECT r->>'dias_reprocessados' FROM execucao)       AS dias_reprocessados,
  (SELECT r->>'dias_pre_assinalados' FROM execucao)     AS dias_com_intervalo_declarado,
  (SELECT r->>'alertas_removidos' FROM execucao)        AS alertas_de_supressao_retirados,
  (SELECT COALESCE(r->>'error', r->>'aviso') FROM execucao) AS observacao,
  (SELECT count(*) FROM public.backup_ponto_diario_preassin_20260909) AS linhas_guardadas_no_resgate;
