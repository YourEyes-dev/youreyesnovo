-- =========================================================
-- EPI — devolução com destino (estoque, manutenção, descarte) numa transação
-- só, e substituição com o destino escolhido a cada vez.
--
-- PROBLEMA (provado numa réplica com todas as migrations): o gatilho de
-- epi_entregas devolve o item ao estoque global em QUALQUER devolução. Com
-- destino "descarte" o estoque subia (entrega 2: 10 para 8; devolver para
-- descarte: 8 para 10), como se o EPI descartado ainda existisse. A tela fazia
-- vários passos soltos depois, sem transação. Além disso, a substituição do
-- wizard usava colunas que não existem (data_devolucao, observacoes_devolucao)
-- e nunca marcou a entrega anterior como devolvida.
--
-- CORREÇÃO:
--  1. epi_devolver_entrega(entrega, destino, observação): trava a entrega,
--     encerra (status devolvido, data efetiva, observação ACRESCENTADA, sem
--     apagar a anterior), deixa o gatilho repor o saldo e então ajusta pelo
--     destino:
--       estoque    -> o saldo fica recomposto; movimentação de entrada;
--       manutencao -> saldo recomposto + a unidade vai ao local Em Manutenção;
--       descarte   -> o saldo NÃO recompõe (sai de novo), com a movimentação
--                     de entrada da devolução e a de saída do descarte.
--     Recusa entrega que não está ativa e destino inválido. Entrega não
--     assinada só libera a reserva (nada a movimentar).
--  2. epi_registrar_entrega ganha p_substitui e p_destino_substituicao: a
--     entrega nova e a devolução da anterior acontecem juntas.
--
-- A devolução não volta a um local específico: a entrega não guarda o local de
-- origem, então só o saldo global é recomposto (limite conhecido).
-- SECURITY INVOKER: as políticas de acesso do usuário continuam valendo.
-- Idempotente. Só funções: não cria tabela nem gatilho.
-- =========================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.epi_devolver_entrega(
  p_entrega uuid,
  p_destino text,
  p_obs     text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public'
AS $fn$
DECLARE
  v_ent      public.epi_entregas;
  v_qtd      integer;
  v_antes    integer;
  v_depois   integer;
  v_assin    boolean;
  v_rot      text;
  v_loc      uuid;
  v_nome     text;
  v_linhas   integer;
BEGIN
  IF p_destino IS NULL OR p_destino NOT IN ('estoque', 'descarte', 'manutencao') THEN
    RAISE EXCEPTION 'Destino da devolução inválido: informe estoque, manutenção ou descarte.'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT e.* INTO v_ent FROM public.epi_entregas e WHERE e.id = p_entrega FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Entrega não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_ent.status <> 'ativa' THEN
    RAISE EXCEPTION 'Esta entrega já foi encerrada (situação: %).', v_ent.status
      USING ERRCODE = 'check_violation';
  END IF;

  v_qtd   := v_ent.quantidade;
  v_assin := v_ent.signed_at IS NOT NULL;
  v_rot   := CASE p_destino WHEN 'manutencao' THEN 'Manutenção'
                            WHEN 'descarte' THEN 'Descarte' ELSE 'Estoque' END;
  v_nome  := (SELECT p.nome_completo FROM public.profiles p WHERE p.user_id = auth.uid() LIMIT 1);

  v_antes := (SELECT e.quantidade_estoque FROM public.epis e WHERE e.id = v_ent.epi_id FOR UPDATE);

  UPDATE public.epi_entregas
     SET status = 'devolvido',
         data_devolucao_efetiva = now(),
         observacoes = COALESCE(NULLIF(btrim(observacoes), '') || ' | ', '')
                       || COALESCE(NULLIF(btrim(p_obs), '') || ' | ', '')
                       || 'Destino: ' || v_rot
   WHERE id = p_entrega;

  -- O gatilho repôs o saldo global se a entrega estava assinada; se não estava,
  -- só liberou a reserva e não há o que movimentar.
  v_depois := (SELECT e.quantidade_estoque FROM public.epis e WHERE e.id = v_ent.epi_id);

  IF v_assin THEN
    IF p_destino = 'manutencao' THEN
      v_loc := (SELECT l.id FROM public.epi_locais_estoque l
                 WHERE l.tenant_id = v_ent.tenant_id AND l.nome = 'Em Manutenção' LIMIT 1);
      IF v_loc IS NULL THEN
        INSERT INTO public.epi_locais_estoque (tenant_id, nome, tipo)
        VALUES (v_ent.tenant_id, 'Em Manutenção', 'almoxarifado_setorial')
        RETURNING id INTO v_loc;
      END IF;
      UPDATE public.epi_estoque_local l
         SET quantidade = COALESCE(l.quantidade, 0) + v_qtd, updated_at = now()
       WHERE l.epi_id = v_ent.epi_id AND l.local_estoque_id = v_loc
         AND l.tenant_id = v_ent.tenant_id AND COALESCE(l.tamanho, '') = COALESCE(v_ent.tamanho, '');
      GET DIAGNOSTICS v_linhas = ROW_COUNT;
      IF v_linhas = 0 THEN
        INSERT INTO public.epi_estoque_local (tenant_id, epi_id, local_estoque_id, quantidade, tamanho)
        VALUES (v_ent.tenant_id, v_ent.epi_id, v_loc, v_qtd, COALESCE(v_ent.tamanho, ''));
      END IF;
    END IF;

    INSERT INTO public.epi_movimentacoes
      (tenant_id, epi_id, tipo, subtipo, local_estoque_id, quantidade, quantidade_anterior,
       quantidade_atual, motivo, tamanho, realizado_por, realizado_por_nome)
    VALUES
      (v_ent.tenant_id, v_ent.epi_id, 'entrada', 'devolucao', v_loc, v_qtd, v_antes, v_depois,
       'Devolução (' || lower(v_rot) || ') de ' || v_ent.colaborador_nome,
       NULLIF(v_ent.tamanho, ''), auth.uid(), v_nome);

    IF p_destino = 'descarte' THEN
      UPDATE public.epis SET quantidade_estoque = quantidade_estoque - v_qtd, updated_at = now()
       WHERE id = v_ent.epi_id;
      INSERT INTO public.epi_movimentacoes
        (tenant_id, epi_id, tipo, subtipo, quantidade, quantidade_anterior, quantidade_atual,
         motivo, tamanho, realizado_por, realizado_por_nome)
      VALUES
        (v_ent.tenant_id, v_ent.epi_id, 'saida', 'descarte', v_qtd, v_depois, v_antes,
         'Descarte de EPI devolvido por ' || v_ent.colaborador_nome,
         NULLIF(v_ent.tamanho, ''), auth.uid(), v_nome);
    END IF;
  END IF;

  RETURN to_jsonb((SELECT e FROM public.epi_entregas e WHERE e.id = p_entrega));
END;
$fn$;

COMMENT ON FUNCTION public.epi_devolver_entrega(uuid, text, text) IS
  'EPI: devolve a entrega com destino (estoque, manutencao ou descarte) numa transacao; descarte nao volta ao saldo.';

GRANT EXECUTE ON FUNCTION public.epi_devolver_entrega(uuid, text, text) TO authenticated;

-- A assinatura nova substitui a de 2 argumentos (evita sobrecarga ambígua).
DROP FUNCTION IF EXISTS public.epi_registrar_entrega(jsonb, uuid);

CREATE OR REPLACE FUNCTION public.epi_registrar_entrega(
  p_entrega              jsonb,
  p_local                uuid DEFAULT NULL,
  p_substitui            uuid DEFAULT NULL,
  p_destino_substituicao text DEFAULT NULL
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
     CASE WHEN v_assin THEN now() END,
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

  -- Substituição: o EPI anterior é devolvido NA MESMA transação, com o destino
  -- que o usuário escolheu (estoque, manutenção ou descarte).
  IF p_substitui IS NOT NULL AND v_assin THEN
    IF p_destino_substituicao IS NULL THEN
      RAISE EXCEPTION 'Informe o destino do EPI anterior (estoque, manutenção ou descarte).'
        USING ERRCODE = 'invalid_parameter_value';
    END IF;
    PERFORM public.epi_devolver_entrega(p_substitui, p_destino_substituicao,
      'Substituição pela entrega ' || v_ent.id);
  END IF;

  RETURN to_jsonb(v_ent);
END;
$fn$;

COMMENT ON FUNCTION public.epi_registrar_entrega(jsonb, uuid, uuid, text) IS
  'EPI: registra a entrega, a baixa por local, a movimentacao e a devolucao do EPI substituido (com destino) numa unica transacao; falha desfaz tudo. signed_at e a hora do servidor.';

GRANT EXECUTE ON FUNCTION public.epi_registrar_entrega(jsonb, uuid, uuid, text) TO authenticated;
