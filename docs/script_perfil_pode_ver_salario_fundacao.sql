-- ============================================================================
-- ENTREGA — Perfil "pode ver salário" · FUNDAÇÃO (flag + verificador)
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de PRODUCAO.
-- Roda em UMA transacao, idempotente.
--
-- Cria a config por perfil (perfis_acesso.pode_ver_salario, default TRUE —
-- ninguem perde acesso hoje) e a funcao public.pode_ver_salario(tenant) que
-- responde se o usuario logado pode ver salario. O mascaramento em si entra em
-- entregas seguintes, que usam esta funcao; ate la nada muda no que cada um ve.
--
-- Regra: superadmin e OWNER (dono) sempre veem. Os demais: sem perfil
-- vinculado -> ve (legado); com perfil -> ve se ALGUM perfil ativo permitir.
-- Papel 'manager'/'admin' NAO libera sozinho (a intencao e poder esconder
-- salario de um "Gerente").
--
-- OBS de editor: NAO cria tabela (so ALTER + funcao) -> sem auto-RLS. Adiciona
-- coluna nova (nasce TRUE), nao altera nem apaga dado existente.
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

  BEGIN
    IF public.has_role(v_uid, 'owner'::public.app_role) THEN
      RETURN true;
    END IF;
  EXCEPTION WHEN undefined_function THEN
    NULL;
  END;

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

  IF NOT v_tem_perfil THEN
    RETURN true;
  END IF;

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

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT
  (SELECT count(*) FROM information_schema.columns
     WHERE table_schema='public' AND table_name='perfis_acesso'
       AND column_name='pode_ver_salario')                 AS coluna_ok,
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname='pode_ver_salario') AS funcao_ok,
  (SELECT count(*) FROM public.perfis_acesso WHERE pode_ver_salario = false) AS perfis_que_nao_veem;
