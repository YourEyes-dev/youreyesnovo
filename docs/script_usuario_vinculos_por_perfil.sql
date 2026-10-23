-- ============================================================================
-- ENTREGA — Vinculos de usuario (usuario_vinculos): leitura e escrita pelo perfil de acesso
-- Cole no SQL Editor (TESTE e HOMOLOGACAO primeiro; depois PRODUCAO). UMA transacao, idempotente.
-- Cria 1 funcao auxiliar e 3 politicas RESTRICTIVE. Nenhum dado e alterado e nenhuma tabela e criada.
-- Rode ANTES a consulta_vinculos_quem_muda.sql. Termina com UMA conferencia SELECT.
-- ============================================================================
SET lock_timeout = '10s';

-- id do cadastro do usuario logado (a PROPRIA linha de usuarios_base), sem depender da leitura da tabela
CREATE OR REPLACE FUNCTION public.ye_meu_usuario_base_id(p_tenant_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT ub.id FROM public.usuarios_base ub
   WHERE ub.auth_user_id = auth.uid() AND ub.tenant_id = p_tenant_id
   LIMIT 1
$fn$;

REVOKE EXECUTE ON FUNCTION public.ye_meu_usuario_base_id(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ye_meu_usuario_base_id(uuid) TO authenticated, service_role;

DO $vin$
BEGIN
  IF to_regclass('public.usuario_vinculos') IS NULL THEN
    RAISE NOTICE 'usuario_vinculos ausente nesta base; nada a fazer.';
    RETURN;
  END IF;

  ALTER TABLE public.usuario_vinculos ENABLE ROW LEVEL SECURITY;
  DROP POLICY IF EXISTS perfil_restringe_leitura_usuario_vinculos ON public.usuario_vinculos;
  DROP POLICY IF EXISTS perfil_restringe_escrita_usuario_vinculos_ins ON public.usuario_vinculos;
  DROP POLICY IF EXISTS perfil_restringe_escrita_usuario_vinculos_upd ON public.usuario_vinculos;

  CREATE POLICY perfil_restringe_leitura_usuario_vinculos ON public.usuario_vinculos
    AS RESTRICTIVE FOR SELECT TO authenticated
    USING (
      usuario_id = public.ye_meu_usuario_base_id(tenant_id)
      OR public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['usuarios','configuracoes']::text[])
    );

  CREATE POLICY perfil_restringe_escrita_usuario_vinculos_ins ON public.usuario_vinculos
    AS RESTRICTIVE FOR INSERT TO authenticated
    WITH CHECK (
      (public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['usuarios','configuracoes']::text[])
        AND public.perfil_escreve(tenant_id, ARRAY['usuarios','configuracoes']::text[], ARRAY['criar']::text[], NULL))
      OR (usuario_id = public.ye_meu_usuario_base_id(tenant_id)
        AND public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['empresa','filiais','configuracoes']::text[])
        AND public.perfil_escreve(tenant_id, ARRAY['empresa','filiais','configuracoes']::text[], ARRAY['criar']::text[], NULL))
    );

  CREATE POLICY perfil_restringe_escrita_usuario_vinculos_upd ON public.usuario_vinculos
    AS RESTRICTIVE FOR UPDATE TO authenticated
    USING (
      public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['usuarios','configuracoes']::text[])
      AND public.perfil_escreve(tenant_id, ARRAY['usuarios','configuracoes']::text[], ARRAY['editar','aprovar']::text[], NULL)
    )
    WITH CHECK (
      public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['usuarios','configuracoes']::text[])
      AND public.perfil_escreve(tenant_id, ARRAY['usuarios','configuracoes']::text[], ARRAY['editar','aprovar']::text[], NULL)
    );

  RAISE NOTICE 'usuario_vinculos: leitura e escrita pelo perfil aplicadas.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENCAO: usuario_vinculos ficou SEM a trava: %', SQLERRM;
END $vin$;

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT
  (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename='usuario_vinculos' AND permissive='RESTRICTIVE'
     AND policyname IN ('perfil_restringe_leitura_usuario_vinculos','perfil_restringe_escrita_usuario_vinculos_ins','perfil_restringe_escrita_usuario_vinculos_upd')) AS politicas_novas,
  (SELECT count(*) FROM pg_proc WHERE proname = 'ye_meu_usuario_base_id' AND pronamespace = 'public'::regnamespace AND prosecdef) AS funcao_auxiliar;
-- Esperado: 3 e 1.
-- DESFAZER: DROP POLICY IF EXISTS perfil_restringe_leitura_usuario_vinculos ON public.usuario_vinculos; (e perfil_restringe_escrita_usuario_vinculos_ins / _upd)
