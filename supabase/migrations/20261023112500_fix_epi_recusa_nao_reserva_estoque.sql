-- ============================================================================
-- EPI-057: a RECUSA de assinatura não reserva estoque.
--
-- A recusa é gravada como entrega status 'extraviado', sem assinatura. O motor
-- tratava toda entrega sem assinatura como reserva: a recusa prendia unidades
-- em quantidade_reservada para sempre (nada as libera) e ainda podia ser
-- barrada por falta de saldo. Agora só reserva a entrega 'ativa' (aguardando
-- assinatura); qualquer outro status não mexe no estoque.
-- ============================================================================
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
      UPDATE public.epis
         SET quantidade_estoque = quantidade_estoque - NEW.quantidade
       WHERE id = NEW.epi_id;
    ELSIF NEW.status = 'ativa' THEN
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
    IF NEW.signed_at IS NOT NULL AND OLD.signed_at IS NULL THEN
      UPDATE public.epis
         SET quantidade_estoque   = quantidade_estoque - NEW.quantidade,
             quantidade_reservada = GREATEST(0, COALESCE(quantidade_reservada, 0) - NEW.quantidade)
       WHERE id = NEW.epi_id;

    ELSIF NEW.status = 'devolvido' AND OLD.status = 'ativa' THEN
      IF OLD.signed_at IS NOT NULL THEN
        UPDATE public.epis
           SET quantidade_estoque = quantidade_estoque + NEW.quantidade
         WHERE id = NEW.epi_id;
      ELSE
        UPDATE public.epis
           SET quantidade_reservada = GREATEST(0, COALESCE(quantidade_reservada, 0) - NEW.quantidade)
         WHERE id = NEW.epi_id;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;
