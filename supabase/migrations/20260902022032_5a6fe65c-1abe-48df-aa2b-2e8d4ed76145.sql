CREATE OR REPLACE FUNCTION public.preencher_ghe_snapshot_entrevistas(p_campanha_ids uuid[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  ghes_empresa AS (
    SELECT DISTINCT g.id AS ghe_id, g.codigo, cm.campanha_id
      FROM public.psicossocial_ghe g
      JOIN camp cm
        ON cm.tenant_id = g.tenant_id
       AND (g.empresa_id IS NULL OR cm.empresa_id IS NULL OR g.empresa_id = cm.empresa_id)
     WHERE COALESCE(g.ativo, true)
  ),
  ghe_pares AS (
    SELECT ge.campanha_id,
           gc.ghe_id,
           ge.codigo,
           lower(trim(c.nome))               AS cargo,
           COALESCE(lower(trim(d.nome)), '') AS depto
      FROM public.psicossocial_ghe_cargos gc
      JOIN ghes_empresa ge ON ge.ghe_id = gc.ghe_id
      JOIN public.cargos c ON c.id = gc.cargo_id
      LEFT JOIN public.departamentos d ON d.id = gc.departamento_id
  ),
  ent AS (
    SELECT e.id AS entrevista_id, e.campanha_id, e.colaborador_id, e.ghe_id_snapshot
      FROM public.psicossocial_entrevistas e
     WHERE e.campanha_id = ANY(p_campanha_ids)
  ),
  ent_ghe AS (
    SELECT DISTINCT ON (e.entrevista_id)
           e.entrevista_id,
           gp.ghe_id
      FROM ent e
      JOIN public.admissoes a ON a.id = e.colaborador_id
      JOIN ghe_pares gp
        ON gp.campanha_id = e.campanha_id
       AND gp.cargo = lower(trim(a.cargo))
       AND (gp.depto = COALESCE(lower(trim(a.departamento)), '') OR gp.depto = '')
     ORDER BY e.entrevista_id, gp.codigo NULLS LAST
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
$function$;