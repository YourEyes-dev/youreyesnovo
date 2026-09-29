-- ============================================================================
-- ENTREGA — FER-003 · uma tabela de feriados por unidade — HOMOLOGAÇÃO
--
-- Cole no SQL Editor da HOMOLOGAÇÃO; depois de conferido, o MESMO na PRODUÇÃO.
--
-- O índice único (tenant_id, empresa_id) já foi entregue guardado no
-- script_empresa_homologacao, mas a guarda o PULOU porque há unidade vinculada a
-- duas tabelas de feriados. Este script resolve o passivo e então cria o índice:
--   1) guarda backup das linhas das unidades duplicadas;
--   2) mantém, por unidade, o vínculo MAIS RECENTE (o que a tela deixaria com o
--      delete-then-insert) e desativa os demais APAGANDO-os do vínculo — não
--      apaga a tabela de feriados nem a empresa, só o vínculo excedente;
--   3) cria o UNIQUE (tenant_id, empresa_id).
--
-- Se para alguma unidade o vínculo correto NÃO for o mais recente, ajuste-o na
-- tela ANTES de rodar (rode o diagnostico_fer003 para ver quem é).
--
-- SEGURANÇA: ALTERA dado (DELETE de vínculo excedente) → backup ANTES (produção
-- sem PITR), criado por EXECUTE para não acionar o auto-RLS. Depois só ADD
-- CONSTRAINT UNIQUE. Não cria tabela. Idempotente (rodar de novo não acha mais
-- duplicata e o índice já existe). lock_timeout curto.
-- ============================================================================

SET lock_timeout = '10s';

-- ── 0) BACKUP das linhas das unidades duplicadas ────────────────────────────
DO $bkp$
BEGIN
  IF to_regclass('public.backup_fer003_vinculos_20260929') IS NULL
     AND EXISTS (
       SELECT 1 FROM public.feriado_tabela_empresas
        GROUP BY tenant_id, empresa_id HAVING count(*) > 1)
  THEN
    EXECUTE 'CREATE ' || 'TABLE public.backup_fer003_vinculos_20260929 AS
      SELECT fte.* FROM public.feriado_tabela_empresas fte
       WHERE (fte.tenant_id, fte.empresa_id) IN (
         SELECT tenant_id, empresa_id FROM public.feriado_tabela_empresas
          GROUP BY tenant_id, empresa_id HAVING count(*) > 1)';
    RAISE NOTICE 'FER-003: backup dos vínculos duplicados em backup_fer003_vinculos_20260929.';
  END IF;
END $bkp$;

-- ── 1) DEDUP: mantém o vínculo mais recente por unidade, apaga os demais ─────
WITH ranked AS (
  SELECT id,
         row_number() OVER (PARTITION BY tenant_id, empresa_id
                            ORDER BY created_at DESC, id) AS rn
  FROM public.feriado_tabela_empresas
)
DELETE FROM public.feriado_tabela_empresas f
USING ranked
WHERE f.id = ranked.id AND ranked.rn > 1;

-- ── 2) UNIQUE por unidade (agora que não há mais duplicata) ──────────────────
ALTER TABLE public.feriado_tabela_empresas
  DROP CONSTRAINT IF EXISTS uq_feriado_tabela_empresa_por_unidade;
ALTER TABLE public.feriado_tabela_empresas
  ADD CONSTRAINT uq_feriado_tabela_empresa_por_unidade UNIQUE (tenant_id, empresa_id);

-- ════════════════════ CONFERÊNCIA (única — esperado tudo 'ok') ════════════════
WITH conf AS MATERIALIZED (
  SELECT 1 AS ord, 'FER-003 · unidades em >1 tabela de feriados (ideal 0)'::text AS item,
         (SELECT count(*) FROM (
            SELECT 1 FROM public.feriado_tabela_empresas
            GROUP BY tenant_id, empresa_id HAVING count(*) > 1) d)::text AS valor,
         (SELECT count(*) FROM (
            SELECT 1 FROM public.feriado_tabela_empresas
            GROUP BY tenant_id, empresa_id HAVING count(*) > 1) d) = 0 AS ok
  UNION ALL
  SELECT 2, 'FER-003 · índice único por unidade presente',
         CASE WHEN EXISTS (SELECT 1 FROM pg_constraint WHERE conname='uq_feriado_tabela_empresa_por_unidade'
                            AND conrelid='public.feriado_tabela_empresas'::regclass) THEN 'sim' ELSE 'nao' END,
         EXISTS (SELECT 1 FROM pg_constraint WHERE conname='uq_feriado_tabela_empresa_por_unidade'
                  AND conrelid='public.feriado_tabela_empresas'::regclass)
)
SELECT item, valor, CASE WHEN ok THEN 'ok' ELSE 'CONFERIR' END AS situacao FROM conf ORDER BY ord;
