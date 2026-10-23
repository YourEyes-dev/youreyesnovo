-- Situação "recusado" para a entrega cuja assinatura o colaborador recusou.
-- Parte 1: só cria o valor do enum (um valor novo não pode ser usado na mesma
-- transação em que nasce; a conversão dos dados fica na parte 2).
ALTER TYPE public.entrega_status ADD VALUE IF NOT EXISTS 'recusado';
