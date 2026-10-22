-- ============================================================================
-- ENTREGA — EPI: movimentação e baixa do descarte por rotina de sistema
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de TESTE (staging) e, só
-- depois de aprovado, no de PRODUCAO. Espelha a migration deste mesmo acerto.
-- Cria duas rotinas de sistema (SECURITY DEFINER, com guarda de empresa, perfil e
-- operação recente) e REESCREVE epi_registrar_entrega e epi_devolver_entrega para
-- usá-las. Não altera nem apaga dado, não mexe em gatilho e não cria tabela. UMA
-- transação, idempotente.
-- EFEITO: quem tem perfil para entregar EPI, mas não o papel de gestor (como o
-- Super Admin do teste), deixa de levar "new row violates row-level security
-- policy" ao entregar com local de estoque.
-- PRÉ-REQUISITO: scripts anteriores de EPI (entrega atômica e devolução com destino).
-- ============================================================================

-- =========================================================
-- EPI — registro de movimentação e baixa do descarte por rotina de SISTEMA.
--
-- PROBLEMA (achado na primeira entrega ponta a ponta no staging): as políticas
-- de epi_entregas aceitam quem tem perfil de "criar" no módulo EPI (o vínculo de
-- empresa é verdadeiro quando a entrega não tem empresa), mas a política de
-- INSERT de epi_movimentacoes aceita SÓ quem tem o papel de gestor. O wizard
-- antigo ignorava o erro desse registro (nunca verificava o resultado) e a
-- entrega concluía sem a movimentação; epi_registrar_entrega, atômica, propaga o
-- erro e derruba a entrega: "new row violates row-level security policy for
-- table epi_movimentacoes". Quem entrega por perfil, como o Super Admin do
-- teste, não conseguia entregar. O mesmo vale para a devolução com descarte
-- (UPDATE em epis).
--
-- CORREÇÃO: duas rotinas de sistema (SECURITY DEFINER) com guarda própria, usadas
-- pelas funções de entrega e de devolução:
--   epi_registrar_movimentacao : grava a linha do histórico de estoque;
--   epi_baixar_saldo_descarte  : tira do saldo o item descartado.
-- Guarda: chamada por usuário autenticado exige a MESMA empresa do usuário, perfil
-- de escrita no módulo (perfil_escreve criar/editar), o EPI da empresa e uma
-- entrega ou devolução REAL e recente (2 minutos) daquele EPI: não dá para
-- gravar histórico solto chamando a rotina direto. Sem usuário (rotina interna, QA, service role) a guarda não se
-- aplica. EXECUTE é negado a anônimo e a PUBLIC. O usuário e o nome gravados no
-- histórico são os de quem está logado, não os que o cliente mandar.
-- A autorização da OPERAÇÃO continua sendo a das políticas de epi_entregas, que
-- as funções de entrega e devolução seguem exercendo como o usuário (INVOKER).
--
-- Idempotente. Só funções: não cria tabela nem gatilho.
-- =========================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.epi_registrar_movimentacao(
  p_tenant uuid, p_epi uuid, p_tipo text, p_subtipo text, p_local uuid,
  p_quantidade integer, p_anterior integer, p_atual integer, p_motivo text,
  p_tamanho text, p_usuario uuid DEFAULT NULL, p_nome text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid  uuid := auth.uid();
  v_nome text;
BEGIN
  IF v_uid IS NOT NULL THEN
    IF p_tenant IS DISTINCT FROM public.get_user_tenant_id() THEN
      RAISE EXCEPTION 'Sem acesso a esta empresa.' USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF NOT public.perfil_escreve(p_tenant, ARRAY['epi', 'sst', 'colaboradores'],
                                 ARRAY['criar', 'editar'], NULL) THEN
      RAISE EXCEPTION 'Sem permissão para movimentar EPI.' USING ERRCODE = 'insufficient_privilege';
    END IF;
    -- Amarra o registro a uma operação REAL e recente (mesma transação): sem isso,
    -- qualquer usuário com perfil de criar poderia gravar histórico à vontade.
    IF p_subtipo IS NULL OR p_subtipo NOT IN ('entrega', 'devolucao', 'descarte') THEN
      RAISE EXCEPTION 'Tipo de movimentação não permitido.' USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.epi_entregas e
       WHERE e.epi_id = p_epi AND e.tenant_id = p_tenant
         AND ((p_subtipo = 'entrega' AND e.status = 'ativa' AND e.signed_at IS NOT NULL
               AND e.created_at > now() - interval '2 minutes')
           OR (p_subtipo IN ('devolucao', 'descarte') AND e.status = 'devolvido'
               AND e.data_devolucao_efetiva > now() - interval '2 minutes'))
    ) THEN
      RAISE EXCEPTION 'Não há entrega ou devolução recente de EPI que justifique esta movimentação.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
    v_nome := (SELECT p.nome_completo FROM public.profiles p WHERE p.user_id = v_uid LIMIT 1);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.epis e WHERE e.id = p_epi AND e.tenant_id = p_tenant) THEN
    RAISE EXCEPTION 'EPI não encontrado para esta empresa.' USING ERRCODE = 'no_data_found';
  END IF;

  INSERT INTO public.epi_movimentacoes
    (tenant_id, epi_id, tipo, subtipo, local_estoque_id, quantidade, quantidade_anterior,
     quantidade_atual, motivo, tamanho, realizado_por, realizado_por_nome)
  VALUES
    (p_tenant, p_epi, p_tipo, p_subtipo, p_local, p_quantidade, p_anterior, p_atual, p_motivo,
     p_tamanho, COALESCE(v_uid, p_usuario), COALESCE(v_nome, p_nome));
END;
$fn$;

CREATE OR REPLACE FUNCTION public.epi_baixar_saldo_descarte(
  p_tenant uuid, p_epi uuid, p_quantidade integer
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_linhas integer;
BEGIN
  IF p_quantidade IS NULL OR p_quantidade < 1 THEN
    RAISE EXCEPTION 'Quantidade do descarte inválida.' USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_uid IS NOT NULL THEN
    IF p_tenant IS DISTINCT FROM public.get_user_tenant_id() THEN
      RAISE EXCEPTION 'Sem acesso a esta empresa.' USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF NOT public.perfil_escreve(p_tenant, ARRAY['epi', 'sst', 'colaboradores'],
                                 ARRAY['criar', 'editar'], NULL) THEN
      RAISE EXCEPTION 'Sem permissão para movimentar EPI.' USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.epi_entregas e
       WHERE e.epi_id = p_epi AND e.tenant_id = p_tenant AND e.status = 'devolvido'
         AND e.quantidade >= p_quantidade AND e.data_devolucao_efetiva > now() - interval '2 minutes'
    ) THEN
      RAISE EXCEPTION 'Não há devolução recente de EPI que justifique este descarte.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  UPDATE public.epis
     SET quantidade_estoque = quantidade_estoque - p_quantidade, updated_at = now()
   WHERE id = p_epi AND tenant_id = p_tenant;
  GET DIAGNOSTICS v_linhas = ROW_COUNT;
  IF v_linhas = 0 THEN
    RAISE EXCEPTION 'EPI não encontrado para esta empresa.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$fn$;

REVOKE ALL ON FUNCTION public.epi_registrar_movimentacao(uuid, uuid, text, text, uuid, integer, integer, integer, text, text, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.epi_registrar_movimentacao(uuid, uuid, text, text, uuid, integer, integer, integer, text, text, uuid, text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.epi_baixar_saldo_descarte(uuid, uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.epi_baixar_saldo_descarte(uuid, uuid, integer) TO authenticated, service_role;

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

    PERFORM public.epi_registrar_movimentacao(
      v_ent.tenant_id, v_ent.epi_id, 'entrada', 'devolucao', v_loc, v_qtd, v_antes, v_depois,
      'Devolução (' || lower(v_rot) || ') de ' || v_ent.colaborador_nome,
      NULLIF(v_ent.tamanho, ''), auth.uid(), v_nome);

    IF p_destino = 'descarte' THEN
      PERFORM public.epi_baixar_saldo_descarte(v_ent.tenant_id, v_ent.epi_id, v_qtd);
      PERFORM public.epi_registrar_movimentacao(
        v_ent.tenant_id, v_ent.epi_id, 'saida', 'descarte', NULL, v_qtd, v_depois, v_antes,
        'Descarte de EPI devolvido por ' || v_ent.colaborador_nome,
        NULLIF(v_ent.tamanho, ''), auth.uid(), v_nome);
    END IF;
  END IF;

  RETURN to_jsonb((SELECT e FROM public.epi_entregas e WHERE e.id = p_entrega));
END;
$fn$;


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

    PERFORM public.epi_registrar_movimentacao(
      v_tenant, v_epi, 'saida', 'entrega', p_local, v_qtd, v_antes, v_depois,
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


-- Conferência final (o editor mostra só este resultado):
SELECT
  (SELECT count(*) FROM pg_proc WHERE proname IN ('epi_registrar_movimentacao', 'epi_baixar_saldo_descarte')
      AND pronamespace = 'public'::regnamespace) AS rotinas_de_sistema_deve_ser_2,
  (SELECT count(*) FROM pg_proc WHERE proname IN ('epi_registrar_movimentacao', 'epi_baixar_saldo_descarte')
      AND pronamespace = 'public'::regnamespace
      AND (has_function_privilege('anon', oid, 'EXECUTE') OR has_function_privilege('public', oid, 'EXECUTE'))) AS abertas_ao_anonimo_deve_ser_0,
  position('epi_registrar_movimentacao' IN
           pg_get_functiondef('public.epi_registrar_entrega(jsonb, uuid, uuid, text)'::regprocedure)) > 0 AS entrega_usa_a_rotina,
  position('epi_baixar_saldo_descarte' IN
           pg_get_functiondef('public.epi_devolver_entrega(uuid, text, text)'::regprocedure)) > 0 AS devolucao_usa_a_rotina,
  NULL::text AS erro_tecnico;

-- Para desfazer: reaplicar script_epi_devolucao_com_destino_e_substituicao.sql
-- (recria as duas funções com o registro direto, que exige papel de gestor).
