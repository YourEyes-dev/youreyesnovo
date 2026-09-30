-- =====================================================================
-- GHE snapshot: casar respondente -> GHE por cargo_id (não só por texto)
--
-- Sintoma (produção): respondentes caindo em "Sem GHE definido" no Plano
-- de Ação PGR mesmo com GHEs vinculados e com composição (cargos) definida.
--
-- Causa: preencher_ghe_snapshot_respostas/_entrevistas casavam o cargo do
-- respondente pelo NOME (texto digitado na admissão x nome do cargo no
-- catálogo). Quando os textos divergem — o que é comum — o casamento falha,
-- mesmo o cargo_id sendo o mesmo. Diagnóstico de um cliente real: 64 de 64
-- respostas casam por cargo_id; só 23 casavam por texto.
--
-- Correção: casar o cargo por cargo_id (admissoes.cargo_id x
-- psicossocial_ghe_cargos.cargo_id), mantendo o nome como reforço e o
-- departamento por nome (admissoes não tem departamento_id). Camadas de
-- preferência preservadas: cargo+setor (1) > só cargo (2) > só setor (3).
-- A camada "só cargo" agora vale mesmo quando o par do GHE tem setor mas o
-- setor do respondente (texto) não bate — é o que recupera os respondentes.
--
-- Sem mudança de assinatura nem de contrato. Idempotente (CREATE OR REPLACE).
-- =====================================================================

CREATE OR REPLACE FUNCTION public.preencher_ghe_snapshot_entrevistas(p_campanha_ids uuid[])
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_tenant      uuid;
  v_atualizadas integer := 0;
  v_permitido   boolean := false;
BEGIN
  IF p_campanha_ids IS NULL OR array_length(p_campanha_ids, 1) IS NULL THEN
    RETURN 0;
  END IF;

  SELECT DISTINCT c.tenant_id INTO v_tenant
    FROM public.questionario_psicossocial_campanhas c
   WHERE c.id = ANY(p_campanha_ids)
   LIMIT 1;

  IF v_tenant IS NULL THEN
    RETURN 0;
  END IF;

  v_permitido := (v_tenant = public.get_user_tenant_id());

  IF NOT v_permitido THEN
    SELECT EXISTS (
      SELECT 1
        FROM public.usuario_vinculos uv
        JOIN public.empresa_cadastro e ON e.id = uv.empresa_id
       WHERE uv.user_id = auth.uid()
         AND COALESCE(uv.ativo, true)
         AND e.tenant_id = v_tenant
    ) INTO v_permitido;
  END IF;

  IF NOT v_permitido THEN
    RETURN 0;
  END IF;

  WITH camp AS (
    SELECT c.id AS campanha_id, c.empresa_id, c.tenant_id,
           COALESCE(c.ghe_ids, ARRAY[]::uuid[]) AS ghe_ids
      FROM public.questionario_psicossocial_campanhas c
     WHERE c.id = ANY(p_campanha_ids)
  ),
  ghes_campanha AS (
    SELECT DISTINCT g.id AS ghe_id, g.codigo, cm.campanha_id
      FROM public.psicossocial_ghe g
      JOIN camp cm
        ON cm.tenant_id = g.tenant_id
       AND (g.empresa_id IS NULL OR cm.empresa_id IS NULL OR g.empresa_id = cm.empresa_id)
     WHERE COALESCE(g.ativo, true)
       AND (
         array_length(cm.ghe_ids, 1) IS NULL
         OR g.id = ANY(cm.ghe_ids)
       )
  ),
  ghe_pares AS (
    SELECT ge.campanha_id,
           gc.ghe_id,
           ge.codigo,
           gc.cargo_id,
           COALESCE(lower(trim(c.nome)), '') AS cargo_nome,
           COALESCE(lower(trim(d.nome)), '') AS depto
      FROM public.psicossocial_ghe_cargos gc
      JOIN ghes_campanha ge ON ge.ghe_id = gc.ghe_id
      LEFT JOIN public.cargos c        ON c.id = gc.cargo_id
      LEFT JOIN public.departamentos d ON d.id = gc.departamento_id
  ),
  ent AS (
    SELECT e.id AS entrevista_id, e.campanha_id, e.colaborador_id, e.ghe_id_snapshot,
           a.cargo_id,
           COALESCE(lower(trim(a.cargo)), '')        AS cargo_nome,
           COALESCE(lower(trim(a.departamento)), '') AS depto
      FROM public.psicossocial_entrevistas e
      LEFT JOIN public.admissoes a ON a.id = e.colaborador_id
     WHERE e.campanha_id = ANY(p_campanha_ids)
  ),
  -- Casamento em camadas: cargo+setor (1) > só cargo (2) > só setor (3).
  -- Cargo casa por cargo_id (preferencial) OU por nome (reforço). A camada 2
  -- (só cargo) vale mesmo quando o par do GHE tem setor mas o setor do
  -- respondente (texto livre) não bate — recupera quem o texto perdia.
  ent_ghe AS (
    SELECT DISTINCT ON (e.entrevista_id)
           e.entrevista_id,
           gp.ghe_id
      FROM ent e
      JOIN ghe_pares gp
        ON gp.campanha_id = e.campanha_id
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
           CASE
             WHEN eg.ghe_id IS NOT NULL THEN eg.ghe_id
             WHEN (SELECT array_length(cm.ghe_ids, 1) FROM camp cm WHERE cm.campanha_id = e.campanha_id) = 1
               THEN (SELECT cm.ghe_ids[1] FROM camp cm WHERE cm.campanha_id = e.campanha_id)
             WHEN EXISTS (SELECT 1 FROM public.psicossocial_ghe g WHERE g.id = e.ghe_id_snapshot)
               THEN e.ghe_id_snapshot
             ELSE NULL
           END AS ghe_id
      FROM ent e
      LEFT JOIN ent_ghe eg ON eg.entrevista_id = e.entrevista_id
  )
  UPDATE public.psicossocial_entrevistas e
     SET ghe_id_snapshot = a.ghe_id
    FROM alvo a
   WHERE e.id = a.entrevista_id
     AND a.ghe_id IS NOT NULL
     AND e.ghe_id_snapshot IS DISTINCT FROM a.ghe_id;

  GET DIAGNOSTICS v_atualizadas = ROW_COUNT;
  RETURN v_atualizadas;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.preencher_ghe_snapshot_respostas(p_campanha_ids uuid[])
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn2$
DECLARE
  v_tenant      uuid;
  v_atualizadas integer := 0;
  v_permitido   boolean := false;
BEGIN
  IF p_campanha_ids IS NULL OR array_length(p_campanha_ids, 1) IS NULL THEN
    RETURN 0;
  END IF;

  SELECT DISTINCT c.tenant_id INTO v_tenant
    FROM public.questionario_psicossocial_campanhas c
   WHERE c.id = ANY(p_campanha_ids)
   LIMIT 1;

  IF v_tenant IS NULL THEN
    RETURN 0;
  END IF;

  v_permitido := (v_tenant = public.get_user_tenant_id());

  IF NOT v_permitido THEN
    SELECT EXISTS (
      SELECT 1
        FROM public.usuario_vinculos uv
        JOIN public.empresa_cadastro e ON e.id = uv.empresa_id
       WHERE uv.user_id = auth.uid()
         AND COALESCE(uv.ativo, true)
         AND e.tenant_id = v_tenant
    ) INTO v_permitido;
  END IF;

  IF NOT v_permitido THEN
    RETURN 0;
  END IF;

  WITH camp AS (
    SELECT c.id AS campanha_id, c.empresa_id, c.tenant_id,
           COALESCE(c.ghe_ids, ARRAY[]::uuid[]) AS ghe_ids
      FROM public.questionario_psicossocial_campanhas c
     WHERE c.id = ANY(p_campanha_ids)
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
       AND (
         array_length(cm.ghe_ids, 1) IS NULL
         OR g.id = ANY(cm.ghe_ids)
       )
  ),
  ghe_pares AS (
    SELECT ge.campanha_id,
           gc.ghe_id,
           ge.codigo,
           gc.cargo_id,
           COALESCE(lower(trim(c.nome)), '') AS cargo_nome,
           COALESCE(lower(trim(d.nome)), '') AS depto
      FROM public.psicossocial_ghe_cargos gc
      JOIN ghes_campanha ge ON ge.ghe_id = gc.ghe_id
      LEFT JOIN public.cargos c        ON c.id = gc.cargo_id
      LEFT JOIN public.departamentos d ON d.id = gc.departamento_id
  ),
  resp AS (
    SELECT r.id AS resposta_id, r.campanha_id, r.cpf_hash, r.ghe_id_snapshot
      FROM public.questionario_psicossocial_respostas r
     WHERE r.campanha_id = ANY(p_campanha_ids)
  ),
  resp_ghe AS (
    SELECT DISTINCT ON (r.resposta_id)
      r.resposta_id,
      gp.ghe_id
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
    WHERE r.cpf_hash IS NOT NULL AND r.cpf_hash <> ''
      AND m.rank IS NOT NULL
    ORDER BY r.resposta_id, a.prioridade, m.rank, gp.codigo NULLS LAST
  ),
  alvo AS (
    SELECT
      r.resposta_id,
      CASE
        WHEN rg.ghe_id IS NOT NULL THEN rg.ghe_id
        WHEN (SELECT array_length(cm.ghe_ids, 1) FROM camp cm WHERE cm.campanha_id = r.campanha_id) = 1
          THEN (SELECT cm.ghe_ids[1] FROM camp cm WHERE cm.campanha_id = r.campanha_id)
        WHEN EXISTS (SELECT 1 FROM public.psicossocial_ghe g WHERE g.id = r.ghe_id_snapshot)
          THEN r.ghe_id_snapshot
        ELSE NULL
      END AS ghe_id
    FROM resp r
    LEFT JOIN resp_ghe rg ON rg.resposta_id = r.resposta_id
  )
  UPDATE public.questionario_psicossocial_respostas r
     SET ghe_id_snapshot   = a.ghe_id,
         ghe_nome_snapshot = (SELECT g.nome FROM public.psicossocial_ghe g WHERE g.id = a.ghe_id)
    FROM alvo a
   WHERE r.id = a.resposta_id
     AND a.ghe_id IS NOT NULL
     AND r.ghe_id_snapshot IS DISTINCT FROM a.ghe_id;

  GET DIAGNOSTICS v_atualizadas = ROW_COUNT;
  RETURN v_atualizadas;
END;
$fn2$;

-- Mesma correção na contagem de respondentes por GHE (o "responderam X":
-- também cruzava o cargo por nome). Sem isto, o número por GHE continuaria
-- subestimado mesmo com o snapshot certo.
CREATE OR REPLACE FUNCTION public.contar_respondentes_por_ghe(p_campanha_ids uuid[])
RETURNS TABLE (
  out_ghe_id       uuid,
  out_ghe_nome     text,
  out_respondentes bigint,
  out_sem_ghe      bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $fn3$
DECLARE
  v_tenant uuid;
BEGIN
  IF p_campanha_ids IS NULL OR array_length(p_campanha_ids, 1) IS NULL THEN
    RETURN;
  END IF;

  SELECT DISTINCT c.tenant_id INTO v_tenant
  FROM public.questionario_psicossocial_campanhas c
  WHERE c.id = ANY(p_campanha_ids)
  LIMIT 1;

  IF v_tenant IS NULL OR v_tenant <> public.get_user_tenant_id() THEN
    RAISE EXCEPTION 'Sem permissão para estas campanhas.';
  END IF;

  RETURN QUERY
  WITH
  camp AS (
    SELECT c.id AS campanha_id, c.empresa_id, c.tenant_id
    FROM public.questionario_psicossocial_campanhas c
    WHERE c.id = ANY(p_campanha_ids)
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
      lower(trim(a.cargo))        AS cargo,
      lower(trim(a.departamento)) AS depto
    FROM public.admissoes a
    JOIN camp cm
      ON cm.tenant_id = a.tenant_id
     AND (cm.empresa_id IS NULL OR cm.empresa_id = a.empresa_id)
    WHERE a.cpf IS NOT NULL AND a.cpf <> ''
      AND (a.status IS NULL OR lower(a.status::text) NOT IN ('desligado','demitido','inativo'))
  ),
  ghes_empresa AS (
    SELECT g.id AS ghe_id
    FROM public.psicossocial_ghe g
    JOIN camp cm
      ON cm.tenant_id = g.tenant_id
     AND (g.empresa_id IS NULL OR cm.empresa_id IS NULL OR g.empresa_id = cm.empresa_id)
  ),
  ghe_pares AS (
    SELECT
      gc.ghe_id,
      gc.cargo_id,
      COALESCE(lower(trim(c.nome)), '')                AS cargo_nome,
      COALESCE(lower(trim(d.nome)), '')                AS depto
    FROM public.psicossocial_ghe_cargos gc
    LEFT JOIN public.cargos c        ON c.id = gc.cargo_id
    LEFT JOIN public.departamentos d ON d.id = gc.departamento_id
    WHERE gc.ghe_id IN (SELECT ghe_id FROM ghes_empresa)
  ),
  resp AS (
    SELECT r.id AS resposta_id, r.campanha_id, r.cpf_hash
    FROM public.questionario_psicossocial_respostas r
    WHERE r.campanha_id = ANY(p_campanha_ids)
      AND r.cpf_hash IS NOT NULL AND r.cpf_hash <> ''
  ),
  resp_ghe AS (
    SELECT
      r.resposta_id,
      gp.ghe_id
    FROM resp r
    JOIN adm a
      ON a.campanha_id = r.campanha_id
     AND a.cpf_hash    = r.cpf_hash
    LEFT JOIN ghe_pares gp
      ON ((gp.cargo_id IS NOT NULL AND gp.cargo_id = a.cargo_id)
          OR (gp.cargo_nome <> '' AND gp.cargo_nome = a.cargo))
     AND (gp.depto = a.depto OR gp.depto = '')
  ),
  distintos AS (
    SELECT DISTINCT resposta_id, ghe_id FROM resp_ghe WHERE ghe_id IS NOT NULL
  )
  SELECT
    g.id,
    g.nome,
    (SELECT count(*) FROM distintos d WHERE d.ghe_id = g.id)                AS respondentes,
    (SELECT count(*) FROM resp_ghe rg WHERE rg.ghe_id IS NULL)             AS sem_ghe
  FROM public.psicossocial_ghe g
  WHERE g.id IN (SELECT ghe_id FROM ghe_pares)
  ORDER BY g.codigo NULLS LAST, g.nome;
END;
$fn3$;

GRANT EXECUTE ON FUNCTION public.contar_respondentes_por_ghe(uuid[]) TO authenticated;
