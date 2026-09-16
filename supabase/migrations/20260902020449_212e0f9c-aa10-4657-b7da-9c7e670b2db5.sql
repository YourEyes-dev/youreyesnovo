CREATE OR REPLACE FUNCTION public.preencher_ghe_snapshot_respostas(p_campanha_ids uuid[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
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

  -- Acesso: perfil do usuário no mesmo tenant OU vínculo ativo com alguma
  -- empresa do tenant (gestores externos ficavam de fora e o preenchimento
  -- do GHE nunca rodava para eles).
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

  -- Sem permissão: não é erro de tela, apenas nada a preencher.
  IF NOT v_permitido THEN
    RETURN 0;
  END IF;

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
      lower(trim(a.cargo))        AS cargo,
      lower(trim(a.departamento)) AS depto,
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
  ghes_empresa AS (
    SELECT g.id AS ghe_id, g.codigo
      FROM public.psicossocial_ghe g
      JOIN camp cm
        ON cm.tenant_id = g.tenant_id
       AND (g.empresa_id IS NULL OR cm.empresa_id IS NULL OR g.empresa_id = cm.empresa_id)
  ),
  ghe_pares AS (
    SELECT
      gc.ghe_id,
      ge.codigo,
      lower(trim(c.nome))               AS cargo,
      COALESCE(lower(trim(d.nome)), '') AS depto
    FROM public.psicossocial_ghe_cargos gc
    JOIN ghes_empresa ge      ON ge.ghe_id = gc.ghe_id
    JOIN public.cargos c      ON c.id = gc.cargo_id
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
      ON gp.cargo = a.cargo
     AND (gp.depto = a.depto OR gp.depto = '')
    WHERE r.cpf_hash IS NOT NULL AND r.cpf_hash <> ''
    ORDER BY r.resposta_id, a.prioridade, gp.codigo NULLS LAST
  ),
  alvo AS (
    SELECT
      r.resposta_id,
      CASE
        WHEN rg.ghe_id IS NOT NULL THEN rg.ghe_id
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
     AND r.ghe_id_snapshot IS DISTINCT FROM a.ghe_id;

  GET DIAGNOSTICS v_atualizadas = ROW_COUNT;
  RETURN v_atualizadas;
END;
$function$;