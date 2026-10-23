-- ============================================================================
-- ENTREGA — EPI: entrega ASSINADA exige a imagem da assinatura (barreira no banco)
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de TESTE (staging) e, só
-- depois de aprovado, no de PRODUCAO. Espelha a migration deste mesmo acerto.
-- Reescreve UMA função (epi_registrar_entrega, mesma assinatura); não altera
-- nem apaga dado, não mexe em gatilho e não cria tabela. UMA transação,
-- idempotente. PRÉ-REQUISITO: os scripts anteriores de EPI.
-- EFEITO: a função passa a recusar entrega com assinatura e sem a imagem dela.
-- A tela corrigida (publicada pela esteira) passa a mandar a assinatura sempre.
-- ============================================================================

-- =========================================================
-- EPI — entrega ASSINADA exige a imagem da assinatura (barreira no banco).
--
-- Achado na primeira entrega ponta a ponta no staging: na etapa da assinatura o
-- wizard fazia setSignatureData(data) e, na mesma hora, saveEntrega("entregue").
-- O estado do React ainda estava vazio, então o envio da foto e da assinatura era
-- pulado e a entrega era gravada com signed_at preenchido e assinatura_url e foto
-- NULOS: uma "ficha assinada" sem assinatura, que não prova nada.
--
-- Correção no banco: epi_registrar_entrega recusa entrega com signed_at e sem
-- assinatura_url. A tela é corrigida à parte (passa a assinatura de forma
-- explícita). A foto é exigida pela tela, não pelo banco. A recusa de assinatura
-- (sem signed_at) segue aceita.
--
-- Mesma assinatura da função; demais regras inalteradas. Idempotente. Só função.
-- =========================================================

SET lock_timeout = '10s';

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

  -- Entrega ASSINADA exige a imagem da assinatura. O banco é a última barreira:
  -- antes, um erro do wizard (estado do React ainda vazio ao salvar) gravava a
  -- ficha com signed_at e SEM assinatura nem foto, e ela não provava nada.
  IF v_assin AND COALESCE(NULLIF(btrim(p_entrega->>'assinatura_url'), ''), '') = '' THEN
    RAISE EXCEPTION 'Entrega assinada exige a imagem da assinatura do colaborador.'
      USING ERRCODE = 'check_violation';
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
  position('exige a imagem da assinatura' IN
           pg_get_functiondef('public.epi_registrar_entrega(jsonb, uuid, uuid, text)'::regprocedure)) > 0 AS barreira_presente,
  (SELECT count(*) FROM pg_proc WHERE proname = 'epi_registrar_entrega'
      AND pronamespace = 'public'::regnamespace) AS versoes_deve_ser_1,
  (SELECT count(*) FROM public.epi_entregas
     WHERE signed_at IS NOT NULL AND assinatura_url IS NULL) AS fichas_assinadas_sem_assinatura_ja_gravadas,
  NULL::text AS erro_tecnico;

-- Para desfazer: reaplicar script_epi_fix_movimentacao_por_rotina_de_sistema.sql.
