-- ============================================================================
-- ENTREGA — EPI: a recusa de assinatura não prende mais estoque (EPI-057)
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de TESTE (staging) e, só
-- depois de aprovado, no de PRODUCAO. Espelha a migration deste mesmo acerto.
-- Reescreve UMA função (atualizar_estoque_epi, mesma assinatura); não altera
-- nem apaga dado, não mexe em gatilho e não cria tabela. UMA transação,
-- idempotente. PRÉ-REQUISITO: o modelo de reserva (EPI-043) já instalado.
-- EFEITO: entrega gravada como recusa (status extraviado) não reserva nem exige
-- saldo. Só a entrega ativa aguardando assinatura reserva.
-- NÃO corrige reservas já presas: isso é o script_epi_liberar_reservas_de_recusa.sql.
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

-- Conferência final (o editor mostra só este resultado):
SELECT
  position('NEW.status = ''ativa''' IN pg_get_functiondef('public.atualizar_estoque_epi()'::regprocedure)) > 0 AS so_reserva_ativa,
  position('GREATEST(0' IN pg_get_functiondef('public.atualizar_estoque_epi()'::regprocedure)) > 0 AS devolucao_preservada,
  NULL::text AS erro_tecnico;

-- Para desfazer: reaplicar a função de 20260916120000_fase4_epi043_modelo_reserva.sql.
