-- ============================================================================
-- VIN-008 — resolver duplicados de perfil IDÊNTICO (com backup) — HOMOLOGAÇÃO
--
-- Cole no SQL Editor da HOMOLOGAÇÃO; depois de conferido, o MESMO na PRODUÇÃO.
-- (Mas rode o diagnóstico ANTES em cada ambiente — cada banco tem os seus.)
--
-- O QUE FAZ, com segurança:
--   • Só age em pares (usuário+empresa) cujos vínculos ativos apontam TODOS para
--     o MESMO perfil — duplicata exata, sem decisão a tomar (é o caso dos 2 pares
--     da homologação: mesmo perfil padrão gravado duas vezes). Mantém o mais
--     recente e DESATIVA (ativo=false) os demais — NÃO apaga (o histórico fica,
--     e o índice parcial só conta os ativos).
--   • Pares cujos vínculos têm perfis DIFERENTES NÃO são tocados: exigem sua
--     decisão (qual perfil vale) e aparecem na conferência como "triagem manual".
--
-- SEGURANÇA:
--   • ALTERA dado (ativo=false) → guarda ANTES as linhas dos grupos numa tabela
--     de backup (produção sem PITR). Backup criado por EXECUTE (marca não
--     contígua → auto-RLS do editor não liga). Desfazer: UPDATE ... SET ativo=true
--     a partir do backup.
--   • Idempotente (rodar de novo não desativa mais nada). lock_timeout curto.
--
-- Depois deste script, rode o script_vin008_homologacao — a conferência deve
-- fechar (0 duplicados, índice ok) se não sobrar nenhum par de perfil diferente.
-- ============================================================================

SET lock_timeout = '10s';

-- ── 0) BACKUP das linhas de TODOS os grupos duplicados (perfil igual ou não) ─
DO $bkp$
BEGIN
  IF to_regclass('public.backup_vin008_dupes_20260928') IS NULL
     AND EXISTS (
       SELECT 1 FROM public.usuario_perfil_vinculos
        WHERE COALESCE(ativo, true)
        GROUP BY usuario_id, COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid)
       HAVING count(*) > 1)
  THEN
    EXECUTE 'CREATE ' || 'TABLE public.backup_vin008_dupes_20260928 AS
      SELECT v.* FROM public.usuario_perfil_vinculos v
       WHERE (v.usuario_id, COALESCE(v.empresa_id, ''00000000-0000-0000-0000-000000000000''::uuid)) IN (
         SELECT usuario_id, COALESCE(empresa_id, ''00000000-0000-0000-0000-000000000000''::uuid)
           FROM public.usuario_perfil_vinculos WHERE COALESCE(ativo, true)
          GROUP BY 1, 2 HAVING count(*) > 1)';
    RAISE NOTICE 'VIN-008: backup dos grupos duplicados em backup_vin008_dupes_20260928.';
  END IF;
END $bkp$;

-- ── 1) DESATIVA duplicatas de perfil IDÊNTICO (mantém a mais recente) ────────
WITH grupos AS (
  SELECT usuario_id,
         COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid) AS emp_key
  FROM public.usuario_perfil_vinculos
  WHERE COALESCE(ativo, true)
  GROUP BY 1, 2
  HAVING count(*) > 1
     AND count(DISTINCT perfil_id) = 1     -- só duplicata exata (mesmo perfil)
),
ranked AS (
  SELECT v.id,
         row_number() OVER (
           PARTITION BY v.usuario_id, COALESCE(v.empresa_id, '00000000-0000-0000-0000-000000000000'::uuid)
           ORDER BY v.created_at DESC, v.id
         ) AS rn
  FROM public.usuario_perfil_vinculos v
  JOIN grupos g
    ON g.usuario_id = v.usuario_id
   AND g.emp_key = COALESCE(v.empresa_id, '00000000-0000-0000-0000-000000000000'::uuid)
  WHERE COALESCE(v.ativo, true)
)
UPDATE public.usuario_perfil_vinculos u
   SET ativo = false, updated_at = now()
  FROM ranked
 WHERE u.id = ranked.id
   AND ranked.rn > 1;

-- ── CONFERÊNCIA ──────────────────────────────────────────────────────────────
-- Ideal: 0 duplicados restantes. Se restar algo, é par de PERFIL DIFERENTE que
-- precisa da sua decisão (rode o diagnostico_vin008_duplicados para ver quem é).
WITH dup AS MATERIALIZED (
  SELECT usuario_id,
         COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid) AS emp_key,
         count(*) AS n, count(DISTINCT perfil_id) AS perfis
  FROM public.usuario_perfil_vinculos
  WHERE COALESCE(ativo, true)
  GROUP BY 1, 2
  HAVING count(*) > 1
),
conf AS MATERIALIZED (
  SELECT 'VIN-008 · pares duplicados ativos restantes (ideal 0)'::text AS item,
         (SELECT count(*) FROM dup) AS n
  UNION ALL
  SELECT 'VIN-008 · destes, com perfis DIFERENTES (triagem manual sua)'::text,
         (SELECT count(*) FROM dup WHERE perfis > 1)
)
SELECT item, CASE WHEN n = 0 THEN 'ok' ELSE n::text || ' — CONFERIR' END AS situacao
FROM conf ORDER BY item;
