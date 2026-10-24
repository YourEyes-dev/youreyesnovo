-- ============================================================================
-- ENTREGA — cadastro de usuarios, PARTE 1: funcoes de leitura (usuarios_diretorio, usuario_por_cpf, usuarios_contar_por_cargo)
-- NAO fecha nada e NAO altera dado: so cria funcoes que as telas novas passam a usar. Cole no SQL Editor.
-- Ordem segura: aplique em teste -> homologacao -> producao, PUBLIQUE AS TELAS (Vercel) e so entao rode a PARTE 2 (a trava).
-- Para desfazer: DROP FUNCTION das tres funcoes (as telas antigas nao as usam).
-- ============================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.usuarios_diretorio()
RETURNS TABLE (
  id uuid, nome_completo text, nome_social text, foto_url text, cargo_funcao text,
  email_principal text, cpf text, tipo_usuario text, status text, auth_user_id uuid
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_tenant uuid := public.get_user_tenant_id();
  v_amplo boolean;
BEGIN
  IF v_tenant IS NULL OR auth.uid() IS NULL THEN
    RETURN;
  END IF;
  v_amplo := public.perfil_amplo_sem_subordinados(v_tenant, VARIADIC public.ye_modulos_dados_pessoas());

  RETURN QUERY
    SELECT ub.id, ub.nome_completo::text, ub.nome_social::text, ub.foto_url::text, ub.cargo_funcao::text,
           CASE WHEN v_amplo OR ub.auth_user_id = auth.uid() THEN ub.email_principal::text ELSE NULL::text END,
           CASE WHEN v_amplo OR ub.auth_user_id = auth.uid() THEN ub.cpf::text ELSE ''::text END,
           CASE WHEN v_amplo OR ub.auth_user_id = auth.uid() THEN ub.tipo_usuario::text ELSE NULL::text END,
           CASE WHEN v_amplo OR ub.auth_user_id = auth.uid() THEN ub.status::text ELSE NULL::text END,
           CASE WHEN v_amplo OR ub.auth_user_id = auth.uid() THEN ub.auth_user_id ELSE NULL::uuid END
      FROM public.usuarios_base ub
     WHERE ub.tenant_id = v_tenant
       AND (v_amplo OR ub.auth_user_id = auth.uid() OR ub.status::text = 'ativo')
     ORDER BY ub.nome_completo;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.usuario_por_cpf(p_cpf text)
RETURNS TABLE (
  id uuid, nome_completo text, email_principal text, cpf text, telefone_principal text,
  cargo_funcao text, data_nascimento text
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_tenant uuid := public.get_user_tenant_id();
  v_cpf text := regexp_replace(COALESCE(p_cpf, ''), '[^0-9]', '', 'g');
BEGIN
  IF v_tenant IS NULL OR auth.uid() IS NULL OR length(v_cpf) <> 11 THEN
    RETURN;
  END IF;
  IF NOT public.perfil_amplo_sem_subordinados(v_tenant, VARIADIC public.ye_modulos_dados_pessoas()) THEN
    RETURN;
  END IF;

  RETURN QUERY
    SELECT ub.id, ub.nome_completo::text, ub.email_principal::text, ub.cpf::text, ub.telefone_principal::text,
           ub.cargo_funcao::text, ub.data_nascimento::text
      FROM public.usuarios_base ub
     WHERE ub.tenant_id = v_tenant
       AND regexp_replace(COALESCE(ub.cpf, ''), '[^0-9]', '', 'g') = v_cpf
     LIMIT 1;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.usuarios_contar_por_cargo(p_cargo text)
RETURNS bigint
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_tenant uuid := public.get_user_tenant_id();
BEGIN
  IF v_tenant IS NULL OR auth.uid() IS NULL THEN
    RETURN 0;
  END IF;
  RETURN (SELECT count(*) FROM public.usuarios_base ub
           WHERE ub.tenant_id = v_tenant AND ub.cargo_funcao = p_cargo);
END;
$fn$;

DO $perm$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY['usuarios_diretorio()', 'usuario_por_cpf(text)', 'usuarios_contar_por_cargo(text)'] LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION public.%s FROM PUBLIC, anon', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO authenticated, service_role', f);
  END LOOP;
END $perm$;

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT count(*) AS funcoes_criadas_esperado_3
FROM pg_proc WHERE pronamespace = 'public'::regnamespace
  AND proname IN ('usuarios_diretorio', 'usuario_por_cpf', 'usuarios_contar_por_cargo');
