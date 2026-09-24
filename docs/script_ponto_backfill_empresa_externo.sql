-- ============================================================================
-- ENTREGA — backfill: batidas externas antigas sem empresa (homologação/produção)
--
-- O QUE FAZ: preenche o empresa_id das batidas do link externo que ficaram
--   NULL (feitas antes da correção 20260924175330), usando a empresa da
--   ADMISSÃO do colaborador. UPDATE com JOIN (rápido, sem função por linha).
--   Só toca linhas com empresa_id NULL — nunca sobrescreve empresa já gravada.
--
-- SEGURANCA: ALTERA dado existente. A produção NÃO tem PITR, então este script
--   GUARDA as linhas afetadas num backup ANTES do UPDATE (só id + empresa_id
--   atual, que é NULL). Se algo sair errado, o comentário final devolve tudo.
--   Rode o arquivo inteiro (roda numa transação; se der erro, desfaz sozinho).
-- ============================================================================

SET lock_timeout = '10s';

-- 1) Backup do que será tocado (id + empresa_id atual).
CREATE TABLE IF NOT EXISTS backup_ponto_marc_empresa_20260924 AS
SELECT id, empresa_id
FROM public.ponto_marcacoes
WHERE dispositivo = 'mobile_web' AND empresa_id IS NULL;

-- 2) Backfill via JOIN.
UPDATE public.ponto_marcacoes m
SET empresa_id = a.empresa_id
FROM public.admissoes a
WHERE m.colaborador_id = a.id
  AND m.tenant_id = a.tenant_id
  AND m.dispositivo = 'mobile_web'
  AND m.empresa_id IS NULL
  AND a.empresa_id IS NOT NULL;

-- 3) Conferência (o editor mostra só o último resultado).
--    ainda_sem_empresa = batidas externas que seguem sem empresa (colaborador
--    sem admissão vinculada ou admissão sem empresa) — esperado baixar a ~0.
SELECT
  count(*) FILTER (WHERE empresa_id IS NULL)     AS ainda_sem_empresa,
  count(*) FILTER (WHERE empresa_id IS NOT NULL) AS com_empresa,
  (SELECT count(*) FROM backup_ponto_marc_empresa_20260924) AS linhas_no_backup
FROM public.ponto_marcacoes
WHERE dispositivo = 'mobile_web';

-- ── DESFAZER (se precisar), rode separado:
--   UPDATE public.ponto_marcacoes m
--   SET empresa_id = b.empresa_id
--   FROM backup_ponto_marc_empresa_20260924 b
--   WHERE m.id = b.id;
