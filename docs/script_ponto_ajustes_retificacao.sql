-- ============================================================================
-- ENTREGA: ponto_ajustes aceita 'retificacao'
-- Corrige o incidente CEN-e4653a (pego pela Sentinela) e o caso de QA JOR-AJ-001.
--
-- O que faz: amplia a restricao de tipo_ajuste para aceitar 'retificacao', o tipo
-- que a retificacao direta do gestor ja grava (como aprovado e auditado). Sem isso,
-- toda retificacao de marcacao falha com ponto_ajustes_tipo_ajuste_check.
--
-- Seguro e idempotente: so mexe na restricao (nao cria tabela, nao altera nem apaga
-- dado existente — por isso nao precisa de backup). Rodar duas vezes nao quebra.
-- Rode PRIMEIRO na HOMOLOGACAO, confira, e so depois na PRODUCAO.
-- ============================================================================

SET lock_timeout = '10s';

DO $ldp$
BEGIN
  ALTER TABLE public.ponto_ajustes
    DROP CONSTRAINT IF EXISTS ponto_ajustes_tipo_ajuste_check;
  ALTER TABLE public.ponto_ajustes
    ADD CONSTRAINT ponto_ajustes_tipo_ajuste_check
    CHECK (tipo_ajuste IN ('inclusao', 'correcao', 'justificativa', 'abono', 'retificacao'));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Falha ao ajustar ponto_ajustes_tipo_ajuste_check: %', SQLERRM;
END
$ldp$;

-- Conferencia (o editor mostra so o ultimo resultado): a definicao deve listar os
-- cinco valores, incluindo 'retificacao'.
SELECT conname,
       pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE conrelid = 'public.ponto_ajustes'::regclass
  AND conname = 'ponto_ajustes_tipo_ajuste_check';
