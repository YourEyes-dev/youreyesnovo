-- ============================================================================
-- ENTREGA — Ouvidoria: o escopo do PERFIL DE ACESSO passa a valer
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de PRODUCAO.
-- ANTES, rode docs/consulta_ouvidoria_quem_muda.sql (somente leitura) para ver quem passa a
-- enxergar so o que e seu.
-- Roda em UMA transacao, idempotente. So POLITICAS (nenhuma tabela criada, nenhum dado
-- alterado): sem auto-RLS do editor e sem necessidade de backup de linhas.
-- Para DESFAZER: recriar a politica antiga de leitura (ver abaixo) e apagar as duas de escrita:
--   DROP POLICY perfil_restringe_escrita_ouvidoria_upd ON public.ouvidoria;
--   DROP POLICY perfil_restringe_escrita_ouvidoria_del ON public.ouvidoria;
--   (a antiga de leitura usava perfil_permite_modulo(tenant_id, VARIADIC ARRAY['configuracoes'])
--    no lugar de 'ouvidoria'.)
-- Termina com UMA conferencia SELECT.
-- ============================================================================

SET lock_timeout = '10s';

-- 1) LEITURA ---------------------------------------------------------------
DO $leit$
BEGIN
  DROP POLICY IF EXISTS perfil_restringe_leitura_ouvidoria ON public.ouvidoria;
  CREATE POLICY perfil_restringe_leitura_ouvidoria
    ON public.ouvidoria AS RESTRICTIVE FOR SELECT
    USING (
      public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['ouvidoria'::text])
      OR autor_id = auth.uid()
      OR responsavel_id = auth.uid()
      OR respondido_por = auth.uid()
    );
  COMMENT ON POLICY perfil_restringe_leitura_ouvidoria ON public.ouvidoria IS
    'RESTRICTIVE: ver todas as manifestacoes exige o modulo ouvidoria com escopo amplo no perfil (ou ser dono/Super Admin, ou legado sem perfil). Escopo proprio_usuario: so a que registrou, a que lhe foi encaminhada ou a que respondeu. Sigilo da Lei 14.457 (SST-041).';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENCAO: trava de leitura da Ouvidoria nao aplicada: %', SQLERRM;
END $leit$;

-- 2) ESCRITA ---------------------------------------------------------------
DO $escr$
BEGIN
  DROP POLICY IF EXISTS perfil_restringe_escrita_ouvidoria_upd ON public.ouvidoria;
  CREATE POLICY perfil_restringe_escrita_ouvidoria_upd
    ON public.ouvidoria AS RESTRICTIVE FOR UPDATE TO authenticated
    USING (public.perfil_escreve(tenant_id, ARRAY['ouvidoria']::text[], ARRAY['editar', 'aprovar']::text[], NULL::text))
    WITH CHECK (public.perfil_escreve(tenant_id, ARRAY['ouvidoria']::text[], ARRAY['editar', 'aprovar']::text[], NULL::text));

  DROP POLICY IF EXISTS perfil_restringe_escrita_ouvidoria_del ON public.ouvidoria;
  CREATE POLICY perfil_restringe_escrita_ouvidoria_del
    ON public.ouvidoria AS RESTRICTIVE FOR DELETE TO authenticated
    USING (public.perfil_escreve(tenant_id, ARRAY['ouvidoria']::text[], ARRAY['excluir']::text[], NULL::text));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENCAO: trava de escrita da Ouvidoria nao aplicada: %', SQLERRM;
END $escr$;

-- 3) ANEXOS ----------------------------------------------------------------
DO $anx$
BEGIN
  DROP POLICY IF EXISTS "Managers do tenant podem ler ouvidoria-anexos" ON storage.objects;
  DROP POLICY IF EXISTS "Ouvidoria: anexos lidos pelo perfil ou pelo proprio autor" ON storage.objects;
  CREATE POLICY "Ouvidoria: anexos lidos pelo perfil ou pelo proprio autor"
    ON storage.objects FOR SELECT TO authenticated
    USING (
      bucket_id = 'ouvidoria-anexos'
      AND public.user_can_access_storage_object('ouvidoria-anexos', name)
      AND (
        public.perfil_permite_modulo(public.get_user_tenant_id(), VARIADIC ARRAY['ouvidoria'::text])
        OR (storage.foldername(name))[1] = auth.uid()::text
      )
    );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENCAO: politica de anexos da Ouvidoria nao aplicada: %', SQLERRM;
END $anx$;

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT
  (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename='ouvidoria'
     AND policyname='perfil_restringe_leitura_ouvidoria' AND permissive='RESTRICTIVE'
     AND position('ouvidoria' IN COALESCE(qual,'')) > 0
     AND position('configuracoes' IN COALESCE(qual,'')) = 0)                         AS leitura_pelo_modulo_ouvidoria,
  (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename='ouvidoria'
     AND policyname IN ('perfil_restringe_escrita_ouvidoria_upd','perfil_restringe_escrita_ouvidoria_del')) AS travas_de_escrita,
  (SELECT count(*) FROM pg_policies WHERE schemaname='storage' AND tablename='objects'
     AND policyname='Ouvidoria: anexos lidos pelo perfil ou pelo proprio autor')       AS politica_de_anexos;
