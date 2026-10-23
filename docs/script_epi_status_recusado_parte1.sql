-- ============================================================================
-- ENTREGA — EPI situação "Recusada" — PARTE 1 de 2: cria o valor
--
-- Cole ESTE arquivo no SQL Editor do projeto de TESTE (staging) e, só depois de
-- aprovado, no de PRODUCAO. Rode a PARTE 1, ESPERE terminar, e só então rode a
-- PARTE 2 (script_epi_status_recusado_parte2.sql): um valor novo de enum não
-- pode ser usado na mesma transação em que é criado.
-- Não altera dado. Idempotente. Não cria tabela.
-- ============================================================================

ALTER TYPE public.entrega_status ADD VALUE IF NOT EXISTS 'recusado';

-- Conferência final (o editor mostra só este resultado):
SELECT
  EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
           WHERE t.typname = 'entrega_status' AND e.enumlabel = 'recusado') AS valor_criado,
  NULL::text AS erro_tecnico;

-- Para desfazer: um valor de enum não é removido; basta não usá-lo.
