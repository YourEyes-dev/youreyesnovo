-- ============================================================================
-- BLOCO A2 — FASE A: renomear a conta + inativar cópias exatas de admissão.
-- ALTERA DADO. Roda inteiro em UMA transação (SQL Editor). Idempotente.
-- NADA é apagado — as cópias viram inativas (reversível pelo backup).
--
-- O que faz, em ordem (backup SEMPRE antes de alterar):
--   1. Renomeia a conta 299779a8… para "Sudomed - Psicossocial" (guardando o
--      nome antigo em backup_tenant_rename_20260917).
--   2. Guarda as linhas que serão inativadas em backup_admissoes_dedup_20260917.
--   3. Inativa as CÓPIAS EXATAS: dentro de cada grupo de mesma
--      (conta, empresa, CPF, data de admissão, cargo) entre as admissões ATIVAS
--      e ainda não inativas, mantém UMA (a mais completa/recente) e marca as
--      demais como inativo=true (com inativado_em/por/motivo). Histórico
--      legítimo (datas/cargos diferentes) e multi-CNPJ NÃO são tocados.
--   4. Confere.
--
-- Reversão (se algum dia precisar):
--   UPDATE public.admissoes a SET inativo=false, inativado_em=NULL,
--     inativado_por=NULL, motivo_inativacao=NULL
--   FROM backup_admissoes_dedup_20260917 b WHERE b.id=a.id;
-- ============================================================================

SET lock_timeout = '10s';

-- 1) RENOMEAR A CONTA (backup do nome antigo, depois troca) ──────────────────
CREATE TABLE IF NOT EXISTS public.backup_tenant_rename_20260917 AS
  SELECT id, nome AS nome_antigo, now() AS backup_em
  FROM public.tenants
  WHERE left(id::text,8) = '299779a8';

UPDATE public.tenants
   SET nome = 'Sudomed - Psicossocial'
 WHERE left(id::text,8) = '299779a8'
   AND nome <> 'Sudomed - Psicossocial';

-- 2) BACKUP das linhas que serão inativadas ─────────────────────────────────
CREATE TABLE IF NOT EXISTS public.backup_admissoes_dedup_20260917 AS
WITH ranked AS MATERIALIZED (
  SELECT a.*,
         row_number() OVER (
           PARTITION BY a.tenant_id,
                        COALESCE(a.empresa_id,'00000000-0000-0000-0000-000000000000'::uuid),
                        regexp_replace(a.cpf,'[^0-9]','','g'),
                        COALESCE(a.data_admissao,'0001-01-01'::date),
                        COALESCE(a.cargo,'')
           ORDER BY
             ( (a.matricula_esocial IS NOT NULL)::int + (a.cbo IS NOT NULL)::int
             + (a.email IS NOT NULL)::int + (a.salario IS NOT NULL)::int
             + (a.data_nascimento IS NOT NULL)::int ) DESC,
             a.updated_at DESC NULLS LAST, a.created_at DESC NULLS LAST, a.id DESC
         ) AS rn
  FROM public.admissoes a
  WHERE a.cpf IS NOT NULL
    AND a.status <> ALL (ARRAY['desligado','reprovado']::admissao_status[])
    AND COALESCE(a.inativo,false) = false
)
SELECT * FROM ranked WHERE rn > 1;

-- 3) INATIVAR as cópias exatas (mesma seleção do backup) ─────────────────────
WITH ranked AS MATERIALIZED (
  SELECT a.id,
         row_number() OVER (
           PARTITION BY a.tenant_id,
                        COALESCE(a.empresa_id,'00000000-0000-0000-0000-000000000000'::uuid),
                        regexp_replace(a.cpf,'[^0-9]','','g'),
                        COALESCE(a.data_admissao,'0001-01-01'::date),
                        COALESCE(a.cargo,'')
           ORDER BY
             ( (a.matricula_esocial IS NOT NULL)::int + (a.cbo IS NOT NULL)::int
             + (a.email IS NOT NULL)::int + (a.salario IS NOT NULL)::int
             + (a.data_nascimento IS NOT NULL)::int ) DESC,
             a.updated_at DESC NULLS LAST, a.created_at DESC NULLS LAST, a.id DESC
         ) AS rn
  FROM public.admissoes a
  WHERE a.cpf IS NOT NULL
    AND a.status <> ALL (ARRAY['desligado','reprovado']::admissao_status[])
    AND COALESCE(a.inativo,false) = false
)
UPDATE public.admissoes a
   SET inativo = true,
       inativado_em = now(),
       inativado_por = 'A2-dedup',
       motivo_inativacao = 'duplicata (re-importacao) - contrato identico empresa+CPF+data+cargo - A2'
  FROM ranked r
 WHERE r.rn > 1 AND a.id = r.id;

-- 4) CONFERÊNCIA (única, o editor só mostra o último resultado) ──────────────
SELECT '1. linhas inativadas (guardadas no backup)' AS item,
       (SELECT count(*)::text FROM public.backup_admissoes_dedup_20260917) AS valor
UNION ALL
SELECT '2. grupos de copia exata ATIVOS restantes (esperado 0)',
       (SELECT count(*)::text FROM (
          SELECT 1 FROM public.admissoes a
          WHERE a.cpf IS NOT NULL
            AND a.status <> ALL (ARRAY['desligado','reprovado']::admissao_status[])
            AND COALESCE(a.inativo,false) = false
          GROUP BY a.tenant_id,
                   COALESCE(a.empresa_id,'00000000-0000-0000-0000-000000000000'::uuid),
                   regexp_replace(a.cpf,'[^0-9]','','g'),
                   COALESCE(a.data_admissao,'0001-01-01'::date),
                   COALESCE(a.cargo,'')
          HAVING count(*) > 1
        ) g)
UNION ALL
SELECT '3. conta renomeada para',
       (SELECT nome FROM public.tenants WHERE left(id::text,8) = '299779a8')
ORDER BY item;
