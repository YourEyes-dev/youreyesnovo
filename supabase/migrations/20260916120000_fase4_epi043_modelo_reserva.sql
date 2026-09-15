-- ============================================================================
-- Fase 4 — EPI-043: modelo de RESERVA (decisão do dono do produto, 16/09).
--
-- A entrega registrada SEM assinatura passa a RESERVAR o item (separa do
-- disponível) em vez de baixar o físico; a baixa definitiva acontece quando a
-- ficha é assinada (signed_at). Devolução de item já baixado repõe o físico;
-- devolução/cancelamento de reserva libera a reserva. Reserva acima do
-- disponível é recusada (RN-003, saldo nunca negativo).
--
-- O EPI-001 é ajustado JUNTO (decisão de produto): antes ele exigia baixa no
-- registro; agora valida o ciclo reserva → assinatura → baixa.
-- ============================================================================

ALTER TABLE public.epis
  ADD COLUMN IF NOT EXISTS quantidade_reservada integer NOT NULL DEFAULT 0;
COMMENT ON COLUMN public.epis.quantidade_reservada IS
  'EPI-043: unidades reservadas por entregas sem assinatura (disponivel = estoque - reservada).';

-- ── Motor de estoque com reserva ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.atualizar_estoque_epi()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_disponivel integer;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.signed_at IS NOT NULL THEN
      -- Entrega já assinada no registro: baixa definitiva imediata.
      UPDATE public.epis
         SET quantidade_estoque = quantidade_estoque - NEW.quantidade
       WHERE id = NEW.epi_id;
    ELSE
      -- Sem assinatura: RESERVA (não baixa o físico). Recusa reserva acima do
      -- disponível — o saldo entregável nunca fica negativo (RN-003/RN-005).
      SELECT quantidade_estoque - COALESCE(quantidade_reservada, 0)
        INTO v_disponivel FROM public.epis WHERE id = NEW.epi_id;
      IF COALESCE(v_disponivel, 0) < NEW.quantidade THEN
        RAISE EXCEPTION 'Saldo disponível insuficiente para reservar a entrega de EPI (disponível %, pedido %).',
          COALESCE(v_disponivel, 0), NEW.quantidade USING ERRCODE = 'check_violation';
      END IF;
      UPDATE public.epis
         SET quantidade_reservada = COALESCE(quantidade_reservada, 0) + NEW.quantidade
       WHERE id = NEW.epi_id;
    END IF;

  ELSIF TG_OP = 'UPDATE' THEN
    -- Assinatura consuma a reserva: baixa definitiva do físico.
    IF NEW.signed_at IS NOT NULL AND OLD.signed_at IS NULL THEN
      UPDATE public.epis
         SET quantidade_estoque   = quantidade_estoque - NEW.quantidade,
             quantidade_reservada = GREATEST(0, COALESCE(quantidade_reservada, 0) - NEW.quantidade)
       WHERE id = NEW.epi_id;

    ELSIF NEW.status = 'devolvido' AND OLD.status = 'ativa' THEN
      IF OLD.signed_at IS NOT NULL THEN
        -- Item já baixado (entregue e assinado): devolução repõe o físico.
        UPDATE public.epis
           SET quantidade_estoque = quantidade_estoque + NEW.quantidade
         WHERE id = NEW.epi_id;
      ELSE
        -- Reserva não assinada cancelada: libera a reserva.
        UPDATE public.epis
           SET quantidade_reservada = GREATEST(0, COALESCE(quantidade_reservada, 0) - NEW.quantidade)
         WHERE id = NEW.epi_id;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ── EPI-001 ajustado ao modelo de reserva ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_epi_001()
RETURNS public.qa_retorno
LANGUAGE plpgsql
AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_tipo uuid; v_epi uuid; v_id uuid; v_antes int; v_reserva int; v_depois int;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao  := 'Criar tipo de EPI e um item com estoque 100';
  r.esperado    := 'Reserva na entrega sem assinatura; baixa só com a assinatura (RN-005)';
  INSERT INTO public.epi_tipos (tenant_id, nome)
  VALUES (v_t, '[QA-EPI] Luva Teste') RETURNING id INTO v_tipo;
  INSERT INTO public.epis (tenant_id, tipo_id, ca, quantidade_estoque, quantidade_minima)
  VALUES (v_t, v_tipo, 'CA-QA-0000', 100, 10) RETURNING id INTO v_epi;

  r.passo_ordem := 2; r.passo_acao := 'Ler o estoque inicial';
  SELECT quantidade_estoque INTO v_antes FROM public.epis WHERE id = v_epi;

  r.passo_ordem := 3; r.passo_acao := 'Registrar entrega de 2 unidades SEM assinatura (reserva)';
  INSERT INTO public.epi_entregas (tenant_id, epi_id, colaborador_nome, colaborador_cpf,
                                   quantidade, data_entrega, status)
  VALUES (v_t, v_epi, '[QA-EPI] Colaborador', public.qa_cpf(269), 2, CURRENT_DATE, 'ativa')
  RETURNING id INTO v_id;
  SELECT quantidade_estoque INTO v_reserva FROM public.epis WHERE id = v_epi;

  r.passo_ordem := 4; r.passo_acao := 'Assinar a ficha (signed_at) — baixa definitiva';
  UPDATE public.epi_entregas SET signed_at = now() WHERE id = v_id;
  SELECT quantidade_estoque INTO v_depois FROM public.epis WHERE id = v_epi;

  IF v_reserva = v_antes AND v_depois = v_antes - 2 THEN
    r.situacao := 'passou';
    r.obtido := format('Reserva preservou o estoque (%s) e a assinatura baixou para %s. Modelo de reserva OK.', v_reserva, v_depois);
  ELSIF v_reserva <> v_antes THEN
    r.situacao := 'falhou';
    r.obtido := format('A entrega sem assinatura baixou o estoque (de %s para %s) — deveria só reservar.', v_antes, v_reserva);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('A assinatura não baixou o estoque (segue em %s, esperado %s).', v_depois, v_antes - 2);
  END IF;
  r.detalhe := jsonb_build_object('epi_id', v_epi, 'antes', v_antes, 'reserva', v_reserva, 'depois', v_depois);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;
