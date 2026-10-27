-- =========================================================
-- EPI — o gatilho da troca periódica deixa de quebrar a entrega.
--
-- epi_entrega_calcula_troca fazia NEW.data_entrega + periodicidade_troca_dias,
-- mas data_entrega é timestamptz e timestamptz + inteiro não existe no
-- PostgreSQL. Toda entrega de EPI cujo tipo tem periodicidade de troca falhava
-- com "operator does not exist: timestamp with time zone + integer", no
-- wizard antigo e no novo. Achado na primeira entrega ponta a ponta no staging.
--
-- Correção: NEW.data_entrega::date + dias (date + inteiro = date, o tipo de
-- data_devolucao_prevista). A conversão usa o fuso da sessão, o mesmo com que a
-- data digitada virou timestamptz na gravação, então o dia não escorrega.
-- Mesma regra de antes: só calcula quando a data prevista não foi informada e o
-- tipo tem periodicidade maior que zero. Mesma assinatura, SECURITY DEFINER e
-- search_path de antes; o gatilho existente continua ligado.
--
-- Idempotente. Só função: não cria tabela nem gatilho.
-- =========================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.epi_entrega_calcula_troca()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE v_periodicidade_troca_dias integer;
BEGIN
  IF NEW.data_devolucao_prevista IS NULL AND NEW.data_entrega IS NOT NULL THEN
    SELECT et.periodicidade_troca_dias INTO v_periodicidade_troca_dias
      FROM public.epis e JOIN public.epi_tipos et ON et.id = e.tipo_id
     WHERE e.id = NEW.epi_id;
    IF v_periodicidade_troca_dias IS NOT NULL AND v_periodicidade_troca_dias > 0 THEN
      NEW.data_devolucao_prevista := NEW.data_entrega::date + v_periodicidade_troca_dias;
    END IF;
  END IF;
  RETURN NEW;
END;
$fn$;
