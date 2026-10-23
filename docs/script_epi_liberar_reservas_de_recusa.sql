-- ============================================================================
-- REPARO — EPI: libera as unidades presas por recusas de assinatura antigas
--
-- Rode DEPOIS de script_epi_fix_recusa_nao_reserva_estoque.sql. Cole inteiro no
-- SQL Editor do projeto de TESTE e, só depois de aprovado, no de PRODUCAO.
-- ALTERA dado: epis.quantidade_reservada. Só DIMINUI: o novo valor é o menor
-- entre o atual e a soma das entregas ativas ainda aguardando assinatura (a
-- reserva legítima). Nunca mexe em quantidade_estoque. Antes de alterar, guarda
-- as linhas afetadas em backup_epi_reservas_20261023. UMA transação,
-- idempotente (segunda rodada não encontra mais nada a corrigir).
-- ============================================================================

SET lock_timeout = '10s';

DO $bk$
BEGIN
  IF to_regclass('public.backup_epi_reservas_20261023') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.backup_epi_reservas_20261023 AS '
         || 'SELECT e.id, e.tenant_id, e.quantidade_estoque, e.quantidade_reservada, now() AS guardado_em '
         || 'FROM public.epis e '
         || 'WHERE COALESCE(e.quantidade_reservada, 0) > COALESCE((SELECT sum(x.quantidade) FROM public.epi_entregas x '
         || 'WHERE x.epi_id = e.id AND x.signed_at IS NULL AND x.status = ''ativa''), 0)';
    EXECUTE 'ALTER TABLE public.backup_epi_reservas_20261023 ENABLE ROW LEVEL SECURITY';
    EXECUTE 'REVOKE ALL ON public.backup_epi_reservas_20261023 FROM anon, authenticated';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Backup não criado: %', SQLERRM;
END $bk$;

UPDATE public.epis e
   SET quantidade_reservada = LEAST(
         COALESCE(e.quantidade_reservada, 0),
         COALESCE((SELECT sum(x.quantidade) FROM public.epi_entregas x
                    WHERE x.epi_id = e.id AND x.signed_at IS NULL AND x.status = 'ativa'), 0))
 WHERE COALESCE(e.quantidade_reservada, 0) >
       COALESCE((SELECT sum(x.quantidade) FROM public.epi_entregas x
                  WHERE x.epi_id = e.id AND x.signed_at IS NULL AND x.status = 'ativa'), 0);

-- Conferência final (o editor mostra só este resultado):
SELECT
  (SELECT count(*) FROM public.epis e
    WHERE COALESCE(e.quantidade_reservada, 0) >
          COALESCE((SELECT sum(x.quantidade) FROM public.epi_entregas x
                     WHERE x.epi_id = e.id AND x.signed_at IS NULL AND x.status = 'ativa'), 0)) AS ainda_presas,
  (SELECT count(*) FROM public.backup_epi_reservas_20261023) AS linhas_no_backup,
  NULL::text AS erro_tecnico;

-- Para desfazer (devolve só as linhas corrigidas):
--   UPDATE public.epis e SET quantidade_reservada = b.quantidade_reservada
--     FROM public.backup_epi_reservas_20261023 b WHERE b.id = e.id;
