-- ============================================================================
-- Permissão de perfil "pode ver salário" — FUNDAÇÃO (flag + verificador)
--
-- Config por perfil que, quando desligada, esconde o salário/valores de
-- remuneração para quem tem aquele perfil — inclusive no servidor (o valor nem
-- sai do banco). Esta migration cria só a base:
--   1) perfis_acesso.pode_ver_salario (default TRUE: ninguém perde acesso hoje);
--   2) a função public.pode_ver_salario(tenant) que responde se o usuário
--      logado pode ver salário.
-- O mascaramento em si (views/colunas) entra nas migrations seguintes, que
-- usam esta função. Até lá, nada muda no que cada um vê.
--
-- Regra do verificador: superadmin e OWNER (dono) sempre veem. Os demais veem
-- conforme o perfil: sem perfil vinculado -> vê (legado, não regride); com
-- perfil -> vê se ALGUM perfil ativo permitir. Papel 'manager'/'admin' NÃO
-- libera sozinho — a intenção é poder esconder salário de um "Gerente".
-- ============================================================================

ALTER TABLE public.perfis_acesso
  ADD COLUMN IF NOT EXISTS pode_ver_salario boolean NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION public.pode_ver_salario(p_tenant_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_tem_perfil boolean;
BEGIN
  IF v_uid IS NULL OR p_tenant_id IS NULL THEN
    RETURN false;
  END IF;

  IF public.is_superadmin(v_uid) THEN
    RETURN true;
  END IF;

  -- Dono da organização vê tudo (não o 'manager'/'admin', de propósito).
  BEGIN
    IF public.has_role(v_uid, 'owner'::public.app_role) THEN
      RETURN true;
    END IF;
  EXCEPTION WHEN undefined_function THEN
    NULL; -- base sem has_role: segue pela regra de perfil
  END;

  -- Tem algum vínculo de perfil ativo neste tenant?
  SELECT EXISTS (
    SELECT 1
      FROM public.usuarios_base ub
      JOIN public.usuario_perfil_vinculos v
        ON v.usuario_id = ub.id AND v.tenant_id = ub.tenant_id
       AND COALESCE(v.ativo, true) = true
       AND (v.expira_em IS NULL OR v.expira_em > now())
      JOIN public.perfis_acesso pa
        ON pa.id = v.perfil_id AND COALESCE(pa.ativo, true) = true
     WHERE ub.auth_user_id = v_uid AND ub.tenant_id = p_tenant_id
  ) INTO v_tem_perfil;

  -- Sem perfil vinculado: mantém o comportamento legado (vê).
  IF NOT v_tem_perfil THEN
    RETURN true;
  END IF;

  -- Com perfil: vê se ALGUM perfil ativo permitir.
  RETURN EXISTS (
    SELECT 1
      FROM public.usuarios_base ub
      JOIN public.usuario_perfil_vinculos v
        ON v.usuario_id = ub.id AND v.tenant_id = ub.tenant_id
       AND COALESCE(v.ativo, true) = true
       AND (v.expira_em IS NULL OR v.expira_em > now())
      JOIN public.perfis_acesso pa
        ON pa.id = v.perfil_id AND COALESCE(pa.ativo, true) = true
       AND COALESCE(pa.pode_ver_salario, true) = true
     WHERE ub.auth_user_id = v_uid AND ub.tenant_id = p_tenant_id
  );
END;
$fn$;

DO $grants$
BEGIN
  EXECUTE 'REVOKE EXECUTE ON FUNCTION public.pode_ver_salario(uuid) FROM PUBLIC, anon';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.pode_ver_salario(uuid) TO authenticated';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Ajuste de grants pulado: %', SQLERRM;
END $grants$;
