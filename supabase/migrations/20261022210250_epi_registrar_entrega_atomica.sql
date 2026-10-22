-- =========================================================
-- EPI — registrar a entrega numa única transação (some o "apaga a entrega").
--
-- PROBLEMA (provado numa réplica com todas as migrations): o wizard grava a
-- entrega já assinada e o gatilho atualizar_estoque_epi baixa o estoque global
-- na hora. Em seguida o wizard, com o controle de estoque ligado (o padrão),
-- faz uma SEGUNDA baixa "otimista" esperando o valor lido antes do INSERT: ela
-- nunca bate, o wizard acusa "conflito de concorrência" e APAGA a entrega
-- assinada. O estoque global já tinha baixado e o gatilho não trata DELETE:
-- sobram unidades sumidas do estoque e nenhuma ficha que as explique, com a
-- foto e a assinatura órfãs no storage.
--
-- CORREÇÃO: epi_registrar_entrega faz tudo numa transação do banco. Se
-- qualquer passo falha, nada é gravado, e não existe mais DELETE de entrega.
--   1. trava o item (FOR UPDATE) e lê o saldo anterior;
--   2. grava a entrega (o gatilho baixa o global; o selo de integridade vale);
--   3. recusa se o saldo global ficaria negativo;
--   4. baixa o local (tamanho nulo e vazio contam como o mesmo tamanho) e recusa
--      se o saldo do local não cobre; sem linha de estoque no local, segue só
--      com o global, como o wizard fazia;
--   5. registra a movimentação (uma só: o gatilho não grava movimentação).
-- A substituição (marcar a entrega anterior como devolvida) NÃO entra aqui de
-- propósito: o wizard usa colunas que não existem (data_devolucao,
-- observacoes_devolucao), então essa marcação nunca funcionou, e ligá-la faria
-- o gatilho de devolução repor ao estoque um EPI desgastado. É decisão de regra
-- de negócio (descarte x estoque), tratada à parte.
-- SECURITY INVOKER: as políticas de acesso do usuário continuam valendo.
--
-- Idempotente (CREATE OR REPLACE). Só função: não cria tabela nem gatilho.
-- =========================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.epi_registrar_entrega(
  p_entrega jsonb,
  p_local   uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public'
AS $fn$
DECLARE
  v_tenant uuid := (p_entrega->>'tenant_id')::uuid;
  v_epi    uuid := (p_entrega->>'epi_id')::uuid;
  v_qtd    integer := COALESCE((p_entrega->>'quantidade')::integer, 0);
  v_tam    text := NULLIF(p_entrega->>'tamanho', '');
  v_assin  boolean := (p_entrega->>'signed_at') IS NOT NULL;
  v_antes  integer;
  v_depois integer;
  v_ent    public.epi_entregas;
  v_linhas integer;
  v_tem_local boolean;
BEGIN
  IF v_tenant IS NULL OR v_epi IS NULL OR v_qtd < 1 THEN
    RAISE EXCEPTION 'Entrega de EPI inválida: informe tenant, EPI e quantidade maior que zero.'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  v_antes := (SELECT e.quantidade_estoque FROM public.epis e
               WHERE e.id = v_epi AND e.tenant_id = v_tenant FOR UPDATE);
  IF v_antes IS NULL THEN
    RAISE EXCEPTION 'EPI não encontrado para esta empresa.' USING ERRCODE = 'no_data_found';
  END IF;

  -- Mensagem clara antes do INSERT (o banco também barra estoque negativo, mas
  -- com erro técnico). A entrega não assinada reserva e é checada pelo gatilho.
  IF v_assin AND v_antes < v_qtd THEN
    RAISE EXCEPTION 'Saldo insuficiente: a entrega de % unidade(s) excede o saldo do EPI (%).',
      v_qtd, v_antes USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.epi_entregas
    (tenant_id, epi_id, colaborador_nome, colaborador_cpf, colaborador_cargo,
     colaborador_departamento, employee_id, quantidade, data_entrega, data_validade,
     status, tamanho, foto_entrega_url, assinatura_url, signed_at, liveness_detected,
     liveness_data, ip_address, user_agent, observacoes, entregue_por, entregue_por_nome)
  VALUES
    (v_tenant, v_epi, p_entrega->>'colaborador_nome', p_entrega->>'colaborador_cpf',
     p_entrega->>'colaborador_cargo', p_entrega->>'colaborador_departamento',
     NULLIF(p_entrega->>'employee_id', '')::uuid, v_qtd,
     (p_entrega->>'data_entrega')::date, NULLIF(p_entrega->>'data_validade', '')::date,
     COALESCE(p_entrega->>'status', 'ativa')::public.entrega_status, v_tam,
     p_entrega->>'foto_entrega_url', p_entrega->>'assinatura_url',
     (p_entrega->>'signed_at')::timestamptz,
     COALESCE((p_entrega->>'liveness_detected')::boolean, false),
     p_entrega->'liveness_data', p_entrega->>'ip_address', p_entrega->>'user_agent',
     p_entrega->>'observacoes', NULLIF(p_entrega->>'entregue_por', '')::uuid,
     p_entrega->>'entregue_por_nome')
  RETURNING * INTO v_ent;

  v_depois := (SELECT e.quantidade_estoque FROM public.epis e WHERE e.id = v_epi);

  -- Baixa por local/tamanho: só entrega assinada (a não assinada é reserva).
  IF p_local IS NOT NULL AND v_assin THEN
    UPDATE public.epi_estoque_local l
       SET quantidade = l.quantidade - v_qtd, updated_at = now()
     WHERE l.epi_id = v_epi AND l.local_estoque_id = p_local AND l.tenant_id = v_tenant
       AND COALESCE(l.tamanho, '') = COALESCE(v_tam, '')
       AND l.quantidade >= v_qtd;
    GET DIAGNOSTICS v_linhas = ROW_COUNT;
    IF v_linhas = 0 THEN
      v_tem_local := EXISTS (SELECT 1 FROM public.epi_estoque_local l
                              WHERE l.epi_id = v_epi AND l.local_estoque_id = p_local
                                AND l.tenant_id = v_tenant
                                AND COALESCE(l.tamanho, '') = COALESCE(v_tam, ''));
      IF v_tem_local THEN
        RAISE EXCEPTION 'Saldo insuficiente neste local para entregar % unidade(s).', v_qtd
          USING ERRCODE = 'check_violation';
      END IF;
    END IF;

    INSERT INTO public.epi_movimentacoes
      (tenant_id, epi_id, tipo, subtipo, local_estoque_id, quantidade, quantidade_anterior,
       quantidade_atual, motivo, tamanho, realizado_por, realizado_por_nome)
    VALUES
      (v_tenant, v_epi, 'saida', 'entrega', p_local, v_qtd, v_antes, v_depois,
       'Entrega para ' || (p_entrega->>'colaborador_nome'), v_tam,
       v_ent.entregue_por, v_ent.entregue_por_nome);
  END IF;

  RETURN to_jsonb(v_ent);
END;
$fn$;

COMMENT ON FUNCTION public.epi_registrar_entrega(jsonb, uuid) IS
  'EPI: registra a entrega, a baixa por local e a movimentacao numa unica transacao; falha desfaz tudo (sem DELETE de entrega).';

GRANT EXECUTE ON FUNCTION public.epi_registrar_entrega(jsonb, uuid) TO authenticated;
