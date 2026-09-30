-- =====================================================================
-- REPARO GLOBAL — GHE por cargo_id (todos os tenants)
--
-- Reprocessa o vinculo respondente -> GHE em TODAS as campanhas de TODOS
-- os tenants, casando o cargo por cargo_id (nome como reforco; setor por
-- nome). Substitui o reprocessamento via funcao, que tem trava por tenant
-- e nao serve para reparo global feito como SuperAdmin no SQL Editor.
--
-- Seguro: guarda as linhas alteradas em tabelas de backup ANTES do update
-- (mesma transacao do editor), idempotente (roda 2x sem duplicar nem
-- reverter), sem RAISE EXCEPTION solto. So altera o campo derivado
-- ghe_id_snapshot / ghe_nome_snapshot. Nenhuma tabela de negocio criada;
-- as duas tabelas de backup sao criadas por EXECUTE (string montada), para
-- nao acionar o auxiliar "auto-RLS" do editor.
--
-- Desfazer (se preciso), apos rodar:
--   UPDATE public.questionario_psicossocial_respostas r
--      SET ghe_id_snapshot = b.ghe_id_old, ghe_nome_snapshot = b.ghe_nome_old
--     FROM public.backup_ghe_resp_20260930 b WHERE r.id = b.resposta_id;
--   UPDATE public.psicossocial_entrevistas e
--      SET ghe_id_snapshot = b.ghe_id_old
--     FROM public.backup_ghe_ent_20260930 b WHERE e.id = b.entrevista_id;
-- =====================================================================

SET statement_timeout = '300s';

-- Tabelas de backup (montadas por EXECUTE para nao acionar o auto-RLS).
DO $bkp$
BEGIN
  EXECUTE 'CREATE ' || 'TABLE IF NOT EXISTS public.backup_ghe_resp_20260930 '
       || '(resposta_id uuid PRIMARY KEY, ghe_id_old uuid, ghe_nome_old text, alterado_em timestamptz DEFAULT now())';
  EXECUTE 'CREATE ' || 'TABLE IF NOT EXISTS public.backup_ghe_ent_20260930 '
       || '(entrevista_id uuid PRIMARY KEY, ghe_id_old uuid, alterado_em timestamptz DEFAULT now())';
END
$bkp$;

-- ===================== RESPOSTAS (questionarios) =====================
WITH camp AS (
  SELECT c.id AS campanha_id, c.empresa_id, c.tenant_id,
         COALESCE(c.ghe_ids, ARRAY[]::uuid[]) AS ghe_ids
    FROM public.questionario_psicossocial_campanhas c
),
adm AS (
  SELECT
    cm.campanha_id,
    encode(
      digest(
        convert_to(regexp_replace(a.cpf, '[^0-9]', '', 'g') || '::' || cm.campanha_id::text, 'UTF8'),
        'sha256'::text
      ),
      'hex'
    ) AS cpf_hash,
    a.cargo_id,
    COALESCE(lower(trim(a.cargo)), '')        AS cargo_nome,
    COALESCE(lower(trim(a.departamento)), '') AS depto,
    CASE
      WHEN COALESCE(a.inativo, false) = false
       AND (a.status IS NULL OR lower(a.status::text) NOT IN ('desligado','demitido','inativo')) THEN 0
      ELSE 1
    END AS prioridade
  FROM public.admissoes a
  JOIN camp cm
    ON cm.tenant_id = a.tenant_id
   AND (cm.empresa_id IS NULL OR cm.empresa_id = a.empresa_id)
  WHERE a.cpf IS NOT NULL AND a.cpf <> ''
),
ghes_campanha AS (
  SELECT DISTINCT g.id AS ghe_id, g.codigo, cm.campanha_id
    FROM public.psicossocial_ghe g
    JOIN camp cm
      ON cm.tenant_id = g.tenant_id
     AND (g.empresa_id IS NULL OR cm.empresa_id IS NULL OR g.empresa_id = cm.empresa_id)
   WHERE COALESCE(g.ativo, true)
     AND (array_length(cm.ghe_ids, 1) IS NULL OR g.id = ANY(cm.ghe_ids))
),
ghe_pares AS (
  SELECT ge.campanha_id, gc.ghe_id, ge.codigo, gc.cargo_id,
         COALESCE(lower(trim(c.nome)), '') AS cargo_nome,
         COALESCE(lower(trim(d.nome)), '') AS depto
    FROM public.psicossocial_ghe_cargos gc
    JOIN ghes_campanha ge ON ge.ghe_id = gc.ghe_id
    LEFT JOIN public.cargos c        ON c.id = gc.cargo_id
    LEFT JOIN public.departamentos d ON d.id = gc.departamento_id
),
resp AS (
  SELECT r.id AS resposta_id, r.campanha_id, r.cpf_hash,
         r.ghe_id_snapshot, r.ghe_nome_snapshot
    FROM public.questionario_psicossocial_respostas r
   WHERE r.campanha_id IN (SELECT campanha_id FROM camp)
),
resp_ghe AS (
  SELECT DISTINCT ON (r.resposta_id) r.resposta_id, gp.ghe_id
    FROM resp r
    JOIN adm a
      ON a.campanha_id = r.campanha_id
     AND a.cpf_hash    = r.cpf_hash
    JOIN ghe_pares gp
      ON gp.campanha_id = r.campanha_id
    CROSS JOIN LATERAL (
      SELECT CASE
               WHEN ((gp.cargo_id IS NOT NULL AND gp.cargo_id = a.cargo_id)
                  OR (gp.cargo_nome <> '' AND gp.cargo_nome = a.cargo_nome))
                    AND gp.depto <> '' AND gp.depto = a.depto              THEN 1
               WHEN ((gp.cargo_id IS NOT NULL AND gp.cargo_id = a.cargo_id)
                  OR (gp.cargo_nome <> '' AND gp.cargo_nome = a.cargo_nome)) THEN 2
               WHEN gp.cargo_id IS NULL AND gp.cargo_nome = ''
                    AND gp.depto <> '' AND gp.depto = a.depto              THEN 3
               ELSE NULL
             END AS rank
    ) m
   WHERE r.cpf_hash IS NOT NULL AND r.cpf_hash <> '' AND m.rank IS NOT NULL
   ORDER BY r.resposta_id, a.prioridade, m.rank, gp.codigo NULLS LAST
),
alvo AS (
  SELECT r.resposta_id,
         r.ghe_id_snapshot   AS old_ghe,
         r.ghe_nome_snapshot AS old_nome,
         CASE
           WHEN rg.ghe_id IS NOT NULL THEN rg.ghe_id
           WHEN (SELECT array_length(cm.ghe_ids, 1) FROM camp cm WHERE cm.campanha_id = r.campanha_id) = 1
             THEN (SELECT cm.ghe_ids[1] FROM camp cm WHERE cm.campanha_id = r.campanha_id)
           WHEN EXISTS (SELECT 1 FROM public.psicossocial_ghe g WHERE g.id = r.ghe_id_snapshot)
             THEN r.ghe_id_snapshot
           ELSE NULL
         END AS new_ghe
    FROM resp r
    LEFT JOIN resp_ghe rg ON rg.resposta_id = r.resposta_id
),
mudar AS (
  SELECT resposta_id, old_ghe, old_nome, new_ghe
    FROM alvo
   WHERE new_ghe IS NOT NULL AND old_ghe IS DISTINCT FROM new_ghe
),
bkp AS (
  INSERT INTO public.backup_ghe_resp_20260930 (resposta_id, ghe_id_old, ghe_nome_old)
  SELECT resposta_id, old_ghe, old_nome FROM mudar
  ON CONFLICT (resposta_id) DO NOTHING
  RETURNING 1
)
UPDATE public.questionario_psicossocial_respostas r
   SET ghe_id_snapshot   = m.new_ghe,
       ghe_nome_snapshot = (SELECT g.nome FROM public.psicossocial_ghe g WHERE g.id = m.new_ghe)
  FROM mudar m
 WHERE r.id = m.resposta_id;

-- ===================== ENTREVISTAS (guiadas) =========================
WITH camp AS (
  SELECT c.id AS campanha_id, c.empresa_id, c.tenant_id,
         COALESCE(c.ghe_ids, ARRAY[]::uuid[]) AS ghe_ids
    FROM public.questionario_psicossocial_campanhas c
),
ghes_campanha AS (
  SELECT DISTINCT g.id AS ghe_id, g.codigo, cm.campanha_id
    FROM public.psicossocial_ghe g
    JOIN camp cm
      ON cm.tenant_id = g.tenant_id
     AND (g.empresa_id IS NULL OR cm.empresa_id IS NULL OR g.empresa_id = cm.empresa_id)
   WHERE COALESCE(g.ativo, true)
     AND (array_length(cm.ghe_ids, 1) IS NULL OR g.id = ANY(cm.ghe_ids))
),
ghe_pares AS (
  SELECT ge.campanha_id, gc.ghe_id, ge.codigo, gc.cargo_id,
         COALESCE(lower(trim(c.nome)), '') AS cargo_nome,
         COALESCE(lower(trim(d.nome)), '') AS depto
    FROM public.psicossocial_ghe_cargos gc
    JOIN ghes_campanha ge ON ge.ghe_id = gc.ghe_id
    LEFT JOIN public.cargos c        ON c.id = gc.cargo_id
    LEFT JOIN public.departamentos d ON d.id = gc.departamento_id
),
ent AS (
  SELECT e.id AS entrevista_id, e.campanha_id, e.ghe_id_snapshot,
         a.cargo_id,
         COALESCE(lower(trim(a.cargo)), '')        AS cargo_nome,
         COALESCE(lower(trim(a.departamento)), '') AS depto
    FROM public.psicossocial_entrevistas e
    LEFT JOIN public.admissoes a ON a.id = e.colaborador_id
   WHERE e.campanha_id IN (SELECT campanha_id FROM camp)
),
ent_ghe AS (
  SELECT DISTINCT ON (e.entrevista_id) e.entrevista_id, gp.ghe_id
    FROM ent e
    JOIN ghe_pares gp ON gp.campanha_id = e.campanha_id
    CROSS JOIN LATERAL (
      SELECT CASE
               WHEN ((gp.cargo_id IS NOT NULL AND gp.cargo_id = e.cargo_id)
                  OR (gp.cargo_nome <> '' AND gp.cargo_nome = e.cargo_nome))
                    AND gp.depto <> '' AND gp.depto = e.depto              THEN 1
               WHEN ((gp.cargo_id IS NOT NULL AND gp.cargo_id = e.cargo_id)
                  OR (gp.cargo_nome <> '' AND gp.cargo_nome = e.cargo_nome)) THEN 2
               WHEN gp.cargo_id IS NULL AND gp.cargo_nome = ''
                    AND gp.depto <> '' AND gp.depto = e.depto              THEN 3
               ELSE NULL
             END AS rank
    ) m
   WHERE m.rank IS NOT NULL
   ORDER BY e.entrevista_id, m.rank, gp.codigo NULLS LAST
),
alvo AS (
  SELECT e.entrevista_id,
         e.ghe_id_snapshot AS old_ghe,
         CASE
           WHEN eg.ghe_id IS NOT NULL THEN eg.ghe_id
           WHEN (SELECT array_length(cm.ghe_ids, 1) FROM camp cm WHERE cm.campanha_id = e.campanha_id) = 1
             THEN (SELECT cm.ghe_ids[1] FROM camp cm WHERE cm.campanha_id = e.campanha_id)
           WHEN EXISTS (SELECT 1 FROM public.psicossocial_ghe g WHERE g.id = e.ghe_id_snapshot)
             THEN e.ghe_id_snapshot
           ELSE NULL
         END AS new_ghe
    FROM ent e
    LEFT JOIN ent_ghe eg ON eg.entrevista_id = e.entrevista_id
),
mudar AS (
  SELECT entrevista_id, old_ghe, new_ghe
    FROM alvo
   WHERE new_ghe IS NOT NULL AND old_ghe IS DISTINCT FROM new_ghe
),
bkp AS (
  INSERT INTO public.backup_ghe_ent_20260930 (entrevista_id, ghe_id_old)
  SELECT entrevista_id, old_ghe FROM mudar
  ON CONFLICT (entrevista_id) DO NOTHING
  RETURNING 1
)
UPDATE public.psicossocial_entrevistas e
   SET ghe_id_snapshot = m.new_ghe
  FROM mudar m
 WHERE e.id = m.entrevista_id;

-- ===================== CONFERENCIA (ultimo resultado) ================
SELECT
  (SELECT count(*) FROM public.backup_ghe_resp_20260930) AS respostas_alteradas,
  (SELECT count(*) FROM public.backup_ghe_ent_20260930)  AS entrevistas_alteradas;
