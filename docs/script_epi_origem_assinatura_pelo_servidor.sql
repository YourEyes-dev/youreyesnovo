-- ============================================================================
-- ENTREGA — EPI: IP, dispositivo e hora da assinatura gravados pelo servidor
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de TESTE (staging) e, só
-- depois de aprovado, no de PRODUCAO. Espelha a migration deste mesmo acerto.
-- Cria um gatilho de INSERT em epi_entregas (uma tabela só, sem risco de
-- deadlock) e atualiza a função epi_registrar_entrega. Não altera nem apaga
-- dado e não cria tabela. UMA transação, idempotente.
-- PRÉ-REQUISITO: a função epi_registrar_entrega já criada (script anterior).
-- ============================================================================

-- =========================================================
-- EPI — a origem da assinatura (IP, dispositivo e hora) vem do SERVIDOR.
--
-- O wizard gravava ip_address como string vazia e signed_at com o relógio do
-- aparelho. Uma ficha sem IP e com hora alterável não prova onde nem quando a
-- assinatura foi colhida (Lei 14.063/2020, art. 4º).
--
-- 1) Gatilho BEFORE INSERT em epi_entregas: se a requisição traz cabeçalhos
--    (PostgREST: request.headers), o IP e o dispositivo gravados são os DELES,
--    sobrescrevendo o que o navegador mandou. Prefere cf-connecting-ip (o
--    Cloudflare o define; o cliente não consegue forjá-lo) e cai para o primeiro
--    endereço de x-forwarded-for. Sem cabeçalhos (SQL Editor, rotina interna),
--    mantém o valor informado e não inventa nenhum.
-- 2) epi_registrar_entrega passa a gravar signed_at com now() do servidor
--    quando a entrega é assinada, ignorando a hora que o aparelho mandou. O
--    hash de integridade é calculado sobre essa hora.
--
-- Fora de escopo: geolocalização (exige consentimento específico, LGPD).
-- Idempotente. Uma tabela só (epi_entregas) e só gatilho de linha.
-- =========================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.epi_entrega_origem_pelo_servidor()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $fn$
DECLARE
  v_h  jsonb;
  v_ip text;
  v_ua text;
BEGIN
  BEGIN
    v_h := NULLIF(current_setting('request.headers', true), '')::jsonb;
  EXCEPTION WHEN OTHERS THEN
    v_h := NULL;
  END;

  IF v_h IS NOT NULL THEN
    v_ip := COALESCE(
      NULLIF(btrim(v_h->>'cf-connecting-ip'), ''),
      NULLIF(btrim(split_part(COALESCE(v_h->>'x-forwarded-for', ''), ',', 1)), ''));
    v_ua := NULLIF(btrim(v_h->>'user-agent'), '');
    IF v_ip IS NOT NULL THEN
      NEW.ip_address := v_ip;
    END IF;
    IF v_ua IS NOT NULL THEN
      NEW.user_agent := v_ua;
    END IF;
  END IF;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_epi_entrega_origem_pelo_servidor ON public.epi_entregas;
CREATE TRIGGER trg_epi_entrega_origem_pelo_servidor
  BEFORE INSERT ON public.epi_entregas
  FOR EACH ROW EXECUTE FUNCTION public.epi_entrega_origem_pelo_servidor();

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

  RETURN to_jsonb(v_ent);
END;
$fn$;

COMMENT ON FUNCTION public.epi_registrar_entrega(jsonb, uuid) IS
  'EPI: registra a entrega, a baixa por local e a movimentacao numa unica transacao; falha desfaz tudo (sem DELETE de entrega). signed_at e a hora do servidor.';

GRANT EXECUTE ON FUNCTION public.epi_registrar_entrega(jsonb, uuid) TO authenticated;

-- Conferência final (o editor mostra só este resultado):
SELECT
  EXISTS (SELECT 1 FROM pg_trigger t
           WHERE t.tgrelid = 'public.epi_entregas'::regclass
             AND t.tgname = 'trg_epi_entrega_origem_pelo_servidor'
             AND (t.tgtype & 4) <> 0) AS gatilho_de_origem_no_insert,
  position('CASE WHEN v_assin THEN now() END' IN
           pg_get_functiondef('public.epi_registrar_entrega(jsonb, uuid)'::regprocedure)) > 0 AS hora_do_servidor,
  (SELECT count(*) FROM public.epi_entregas
     WHERE signed_at IS NOT NULL AND COALESCE(ip_address, '') = '') AS fichas_antigas_sem_ip,
  NULL::text AS erro_tecnico;

-- Para desfazer (volta a hora e o IP do navegador):
--   DROP TRIGGER IF EXISTS trg_epi_entrega_origem_pelo_servidor ON public.epi_entregas;
--   DROP FUNCTION IF EXISTS public.epi_entrega_origem_pelo_servidor();
--   (e reaplicar script_epi_registrar_entrega_atomica.sql para voltar a função anterior)
