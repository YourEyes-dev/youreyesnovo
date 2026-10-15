-- ============================================================================
-- Acesso — Fase 1a: o PERFIL vinculado tem a palavra final
--
-- Hoje papel de gestão (manager+) e tipo administrador/gestor concedem acesso
-- amplo AUTOMÁTICO, por cima do escopo do perfil. Resultado: definir um perfil
-- com escopo "próprio usuário" não restringe quem também é gestor — as duas
-- camadas (papel/tipo x perfil) brigam e o papel vence em silêncio.
--
-- Decisão do dono do produto (10/2026): unificar em uma régua só — o perfil é a
-- fonte da verdade; o "tipo" vira apenas um modelo inicial. Esta é a 1ª etapa,
-- de menor risco: muda só o PORTEIRO de LEITURA das ~37 tabelas sensíveis (as
-- políticas RESTRICTIVE perfil_restringe_leitura_*), que passa por estas duas
-- funções centrais.
--
-- Regra nova:
--   • Super Admin e DONO da empresa (owner) seguem ACIMA de tudo (não se
--     trancam pra fora) — inclusive se tiverem perfil.
--   • Quando a pessoa TEM um perfil de acesso vinculado APLICÁVEL neste
--     contexto (empresa ativa), o papel manager+ e o tipo administrador/gestor
--     DEIXAM de conceder acesso amplo automático; quem decide é o escopo do
--     perfil.
--   • Quem NÃO tem perfil vinculado mantém o comportamento legado por
--     papel/tipo — ninguém é trancado pra fora nesta etapa.
--
-- Escopo intencional desta etapa: apenas perfil_permite_modulo e
-- perfil_amplo_sem_subordinados (leitura das tabelas sensíveis). As centenas de
-- políticas PERMISSIVE de base, as RPCs de ponto/folha por tipo_usuario e
-- perfil_permite_acao (escrita) seguem como estão — serão tratadas na Fase 2,
-- módulo a módulo. Tudo idempotente (CREATE OR REPLACE).
-- ============================================================================

SET lock_timeout = '10s';

-- ── perfil_permite_modulo ───────────────────────────────────────────────────
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

  -- Plataforma e dono da empresa ficam acima do perfil.
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

  -- SEM CADASTRO NO CLIENTE: gestão DESTE cliente = papel de gestão E pertencer
  -- (profiles). Sem usuarios_base não há vínculo de perfil, então a regra segue
  -- idêntica à correção de 09/2026.
  IF v_status IS NULL THEN
    RETURN public.has_minimum_role(v_uid, 'manager'::public.app_role)
       AND EXISTS (
             SELECT 1 FROM public.profiles pr
             WHERE pr.user_id = v_uid AND pr.tenant_id = p_tenant_id
           );
  END IF;

  -- COM CADASTRO: só 'ativo' abre porta.
  IF v_status <> 'ativo' THEN
    RETURN false;
  END IF;

  v_empresa := public.empresa_ativa();

  -- Tem perfil de acesso vinculado APLICÁVEL neste contexto? (qualquer perfil
  -- ativo; o vínculo sem empresa conta em qualquer contexto.)
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

  -- Papel/tipo só concedem amplo quando NÃO há perfil vinculado (legado).
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

  -- Vínculo de perfil com escopo amplo (≠ proprio_usuario), recortado pela
  -- empresa ativa.
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

  -- Liberação pontual: mesmo recorte.
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

-- ── perfil_amplo_sem_subordinados ───────────────────────────────────────────
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

  -- Amplo só com escopo que NÃO seja próprio NEM subordinados.
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

COMMENT ON FUNCTION public.perfil_permite_modulo(uuid, text[]) IS
  'Porteiro das politicas RESTRICTIVE de perfil. Fase 1: quando a pessoa tem perfil vinculado aplicavel, o escopo do perfil decide (papel manager+/tipo administrador-gestor NAO concedem amplo). Sem perfil vinculado, mantem legado por papel/tipo. Super Admin e owner ficam acima.';
