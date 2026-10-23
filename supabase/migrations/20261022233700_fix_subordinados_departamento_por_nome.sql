-- Corrige ye_cpfs_subordinados_diretos: a parte de apoio (pessoas do departamento que eu chefio)
-- usava admissoes.departamento_id, coluna que NAO existe em producao (admissoes guarda o departamento
-- por nome, em admissoes.departamento). Resultado: a funcao dava erro na execucao para qualquer lider
-- com escopo subordinados_diretos. Agora liga pelo nome (sem diferenciar maiuscula e espacos).
CREATE OR REPLACE FUNCTION public.ye_cpfs_subordinados_diretos(p_tenant_id uuid)
RETURNS text[]
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_cpf text := public.cpf_do_usuario_logado();
  v_res text[];
BEGIN
  IF p_tenant_id IS NULL OR v_cpf IS NULL OR v_cpf = '' THEN
    RETURN ARRAY[]::text[];
  END IF;

  v_res := (
    SELECT COALESCE(array_agg(DISTINCT q.cpf_norm), ARRAY[]::text[])
      FROM (
        SELECT regexp_replace(COALESCE(s.cpf, ''), '[^0-9]', '', 'g') AS cpf_norm
          FROM public.admissoes s
         WHERE s.tenant_id = p_tenant_id
           AND regexp_replace(COALESCE(s.gestor_cpf, ''), '[^0-9]', '', 'g') = v_cpf
        UNION
        SELECT regexp_replace(COALESCE(s.cpf, ''), '[^0-9]', '', 'g')
          FROM public.admissoes s
          JOIN public.departamentos d
            ON lower(trim(d.nome)) = lower(trim(s.departamento))
           AND d.tenant_id = p_tenant_id
          JOIN public.admissoes g
            ON g.id = d.gestor_admissao_id
           AND g.tenant_id = p_tenant_id
           AND regexp_replace(COALESCE(g.cpf, ''), '[^0-9]', '', 'g') = v_cpf
         WHERE s.tenant_id = p_tenant_id
      ) q
     WHERE q.cpf_norm <> '' AND q.cpf_norm <> v_cpf
  );

  RETURN v_res;
END;
$fn$;
