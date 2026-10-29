-- ============================================================================
-- SCRIPT DE ENTREGA (PRODUÇÃO) — SEGURANÇA: anexos de ajuste de ponto
-- Remove a leitura pública (anon) da pasta externo/ do bucket privado
-- ponto-ajustes-anexos; RH logado lê só os anexos da própria empresa.
-- O envio pelo app continua igual. Não toca dado. Idempotente.
-- Desfazer (não recomendado): recriar a política antiga de 20260523171905.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ponto_anexo_externo_do_meu_tenant(p_token text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.ponto_links l
    WHERE l.token = p_token
      AND l.tenant_id = public.current_user_tenant_id()
  );
$function$;

COMMENT ON FUNCTION public.ponto_anexo_externo_do_meu_tenant(text) IS
  'true quando o token de link de ponto pertence à empresa do usuário logado. '
  'Usada pela política de leitura dos anexos externos de ajuste de ponto.';

REVOKE ALL ON FUNCTION public.ponto_anexo_externo_do_meu_tenant(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ponto_anexo_externo_do_meu_tenant(text) TO authenticated;

DROP POLICY IF EXISTS "ponto_ajustes_externo_select" ON storage.objects;
DROP POLICY IF EXISTS "ponto_ajustes_externo_select_tenant" ON storage.objects;
CREATE POLICY "ponto_ajustes_externo_select_tenant"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'ponto-ajustes-anexos'
  AND (storage.foldername(name))[1] = 'externo'
  AND public.ponto_anexo_externo_do_meu_tenant((storage.foldername(name))[2])
);

-- Conferência (o editor mostra só este resultado)
SELECT json_build_object(
  'politica_antiga_removida', NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='ponto_ajustes_externo_select'),
  'politica_nova_presente', EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='ponto_ajustes_externo_select_tenant'),
  'politicas_anon_lendo_anexos', (SELECT count(*) FROM pg_policies p WHERE p.schemaname='storage' AND p.tablename='objects'
       AND p.cmd IN ('SELECT','ALL') AND ('anon' = ANY (p.roles) OR 'public' = ANY (p.roles))
       AND COALESCE(p.qual,'') ILIKE '%ponto-ajustes-anexos%'),
  'envio_do_app_mantido', EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='ponto_ajustes_externo_insert')
) AS resultado;
