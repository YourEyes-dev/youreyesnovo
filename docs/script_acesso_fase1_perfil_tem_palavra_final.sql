-- ============================================================================
-- ENTREGA — Acesso Fase 1a: o PERFIL vinculado tem a palavra final
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de PRODUCAO.
--
-- Roda em UMA transacao, idempotente (CREATE OR REPLACE). NAO cria tabela ->
-- sem auto-RLS do editor. Nao altera nem apaga dado.
--
-- O que muda: as duas funcoes centrais que gov. a LEITURA das tabelas sensiveis
-- (perfil_permite_modulo e perfil_amplo_sem_subordinados) passam a respeitar o
-- perfil: quando a pessoa TEM um perfil de acesso vinculado aplicavel, o papel
-- manager+ e o tipo administrador/gestor DEIXAM de conceder acesso amplo
-- automatico -> quem decide e o escopo do perfil. Super Admin e o DONO (owner)
-- ficam acima. Quem NAO tem perfil vinculado mantem o comportamento atual.
--
-- ATENCAO (pre-producao): antes de aplicar, convem conferir se algum
-- gestor/administrador REAL ja tem um perfil vinculado RESTRITIVO por engano
-- (ele passaria a ser restringido). Consulta de apoio ao final (comentada).
-- ============================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.perfil_permite_modulo(
  p_tenant_id uuid,
  VARIADIC p_modulos text[]
)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_status text;
  v_empresa uuid;
  v_tem_perfil boolean;
BEGIN
  IF v_uid IS NULL OR p_tenant_id IS NULL THEN
    RETURN false;
  END IF;

  IF public.is_superadmin(v_uid) THEN
    RETURN true;
  END IF;
  IF public.has_minimum_role(v_uid, 'owner'::public.app_role) THEN
    RETURN true;
  END IF;

  SELECT ub.status::text INTO v_status
  FROM public.usuarios_base ub
  WHERE ub.auth_user_id = v_uid AND ub.tenant_id = p_tenant_id
  LIMIT 1;

  IF v_status IS NULL THEN
    RETURN public.has_minimum_role(v_uid, 'manager'::public.app_role)
       AND EXISTS (
             SELECT 1 FROM public.profiles pr
             WHERE pr.user_id = v_uid AND pr.tenant_id = p_tenant_id
           );
  END IF;

  IF v_status <> 'ativo' THEN
    RETURN false;
  END IF;

  v_empresa := public.empresa_ativa();

  v_tem_perfil := EXISTS (
    SELECT 1
    FROM public.usuarios_base ub
    JOIN public.usuario_perfil_vinculos v
      ON v.usuario_id = ub.id
     AND v.tenant_id = ub.tenant_id
     AND COALESCE(v.ativo, true) = true
     AND (v.expira_em IS NULL OR v.expira_em > now())
     AND (v_empresa IS NULL OR v.empresa_id IS NULL OR v.empresa_id = v_empresa)
    JOIN public.perfis_acesso pa
      ON pa.id = v.perfil_id
     AND COALESCE(pa.ativo, true) = true
     AND (pa.expira_em IS NULL OR pa.expira_em > now())
    WHERE ub.auth_user_id = v_uid
      AND ub.tenant_id = p_tenant_id
  );

  IF NOT v_tem_perfil THEN
    IF public.has_minimum_role(v_uid, 'manager'::public.app_role) THEN
      RETURN true;
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.usuarios_base ub
      WHERE ub.auth_user_id = v_uid
        AND ub.tenant_id = p_tenant_id
        AND ub.tipo_usuario::text IN ('administrador', 'gestor')
    ) THEN
      RETURN true;
    END IF;
  END IF;

  IF v_empresa IS NULL AND public.empresa_ativa_obrigatoria() THEN
    RETURN false;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.usuarios_base ub
    JOIN public.usuario_perfil_vinculos v
      ON v.usuario_id = ub.id
     AND v.tenant_id = ub.tenant_id
     AND COALESCE(v.ativo, true) = true
     AND (v.expira_em IS NULL OR v.expira_em > now())
     AND (v_empresa IS NULL OR v.empresa_id IS NULL OR v.empresa_id = v_empresa)
    JOIN public.perfis_acesso pa
      ON pa.id = v.perfil_id
     AND COALESCE(pa.ativo, true) = true
     AND (pa.expira_em IS NULL OR pa.expira_em > now())
    JOIN public.perfil_permissoes pp
      ON pp.perfil_id = v.perfil_id
     AND COALESCE(pp.ativo, true) = true
     AND pp.modulo = ANY (p_modulos)
     AND COALESCE(pp.escopo::text, '') <> 'proprio_usuario'
    WHERE ub.auth_user_id = v_uid
      AND ub.tenant_id = p_tenant_id
  ) THEN
    RETURN true;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.usuarios_base ub
    JOIN public.perfil_excecoes pe
      ON pe.usuario_id = ub.id
     AND pe.tenant_id = ub.tenant_id
     AND COALESCE(pe.ativo, true) = true
     AND COALESCE(pe.tipo, 'adicional') = 'adicional'
     AND (pe.expira_em IS NULL OR pe.expira_em > now())
     AND pe.modulo = ANY (p_modulos)
     AND COALESCE(pe.escopo::text, '') <> 'proprio_usuario'
     AND (v_empresa IS NULL OR pe.empresa_id IS NULL OR pe.empresa_id = v_empresa)
    WHERE ub.auth_user_id = v_uid
      AND ub.tenant_id = p_tenant_id
  );
END $fn$;

CREATE OR REPLACE FUNCTION public.perfil_amplo_sem_subordinados(
  p_tenant_id uuid, VARIADIC p_modulos text[]
)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_status text;
  v_empresa uuid;
  v_tem_perfil boolean;
BEGIN
  IF v_uid IS NULL OR p_tenant_id IS NULL THEN
    RETURN false;
  END IF;

  IF public.is_superadmin(v_uid) THEN
    RETURN true;
  END IF;
  IF public.has_minimum_role(v_uid, 'owner'::public.app_role) THEN
    RETURN true;
  END IF;

  SELECT ub.status::text INTO v_status
    FROM public.usuarios_base ub
   WHERE ub.auth_user_id = v_uid AND ub.tenant_id = p_tenant_id
   LIMIT 1;

  IF v_status IS NULL THEN
    RETURN public.has_minimum_role(v_uid, 'manager'::public.app_role)
       AND EXISTS (
             SELECT 1 FROM public.profiles pr
              WHERE pr.user_id = v_uid AND pr.tenant_id = p_tenant_id
           );
  END IF;

  IF v_status <> 'ativo' THEN
    RETURN false;
  END IF;

  v_empresa := public.empresa_ativa();

  v_tem_perfil := EXISTS (
    SELECT 1
    FROM public.usuarios_base ub
    JOIN public.usuario_perfil_vinculos v
      ON v.usuario_id = ub.id
     AND v.tenant_id = ub.tenant_id
     AND COALESCE(v.ativo, true) = true
     AND (v.expira_em IS NULL OR v.expira_em > now())
     AND (v_empresa IS NULL OR v.empresa_id IS NULL OR v.empresa_id = v_empresa)
    JOIN public.perfis_acesso pa
      ON pa.id = v.perfil_id
     AND COALESCE(pa.ativo, true) = true
     AND (pa.expira_em IS NULL OR pa.expira_em > now())
    WHERE ub.auth_user_id = v_uid
      AND ub.tenant_id = p_tenant_id
  );

  IF NOT v_tem_perfil THEN
    IF public.has_minimum_role(v_uid, 'manager'::public.app_role) THEN
      RETURN true;
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.usuarios_base ub
       WHERE ub.auth_user_id = v_uid
         AND ub.tenant_id = p_tenant_id
         AND ub.tipo_usuario::text IN ('administrador', 'gestor')
    ) THEN
      RETURN true;
    END IF;
  END IF;

  IF v_empresa IS NULL AND public.empresa_ativa_obrigatoria() THEN
    RETURN false;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.usuarios_base ub
    JOIN public.usuario_perfil_vinculos v
      ON v.usuario_id = ub.id
     AND v.tenant_id = ub.tenant_id
     AND COALESCE(v.ativo, true) = true
     AND (v.expira_em IS NULL OR v.expira_em > now())
     AND (v_empresa IS NULL OR v.empresa_id IS NULL OR v.empresa_id = v_empresa)
    JOIN public.perfis_acesso pa
      ON pa.id = v.perfil_id
     AND COALESCE(pa.ativo, true) = true
     AND (pa.expira_em IS NULL OR pa.expira_em > now())
    JOIN public.perfil_permissoes pp
      ON pp.perfil_id = v.perfil_id
     AND COALESCE(pp.ativo, true) = true
     AND pp.modulo = ANY (p_modulos)
     AND COALESCE(pp.escopo::text, '') NOT IN ('proprio_usuario', 'subordinados_diretos')
    WHERE ub.auth_user_id = v_uid
      AND ub.tenant_id = p_tenant_id
  ) THEN
    RETURN true;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.usuarios_base ub
    JOIN public.perfil_excecoes pe
      ON pe.usuario_id = ub.id
     AND pe.tenant_id = ub.tenant_id
     AND COALESCE(pe.ativo, true) = true
     AND COALESCE(pe.tipo, 'adicional') = 'adicional'
     AND (pe.expira_em IS NULL OR pe.expira_em > now())
     AND pe.modulo = ANY (p_modulos)
     AND COALESCE(pe.escopo::text, '') NOT IN ('proprio_usuario', 'subordinados_diretos')
     AND (v_empresa IS NULL OR pe.empresa_id IS NULL OR pe.empresa_id = v_empresa)
    WHERE ub.auth_user_id = v_uid
      AND ub.tenant_id = p_tenant_id
  );
END $fn$;

-- ── Conferencia ─────────────────────────────────────────────────────────────
-- As duas funcoes agora contem a trava v_tem_perfil (2 esperado).
SELECT count(*) AS funcoes_atualizadas_esperado_2
  FROM pg_proc
 WHERE proname IN ('perfil_permite_modulo','perfil_amplo_sem_subordinados')
   AND pg_get_functiondef(oid) LIKE '%v_tem_perfil%';

-- ── (opcional) Quem seria afetado: gestor/admin com perfil RESTRITIVO ──────
-- Rode ANTES de aplicar para ver se algum gestor real passaria a ser limitado.
-- SELECT ub.nome_completo, ub.tipo_usuario::text, pa.nome AS perfil,
--        pp.modulo, pp.escopo::text
--   FROM public.usuarios_base ub
--   JOIN public.usuario_perfil_vinculos v ON v.usuario_id = ub.id AND COALESCE(v.ativo,true)
--   JOIN public.perfis_acesso pa ON pa.id = v.perfil_id
--   JOIN public.perfil_permissoes pp ON pp.perfil_id = v.perfil_id
--  WHERE ub.tipo_usuario::text IN ('administrador','gestor')
--    AND COALESCE(pp.escopo::text,'') = 'proprio_usuario'
--  ORDER BY ub.nome_completo;
