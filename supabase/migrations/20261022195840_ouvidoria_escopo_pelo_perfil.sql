-- ============================================================================
-- OUVIDORIA: o escopo do PERFIL DE ACESSO passa a valer (achado grave, 10/2026)
--
-- Sintoma: usuário com perfil "Ouvidoria: Próprio usuário" via manifestações de OUTRAS
-- pessoas. Causa: a leitura "ver todas" era liberada pelo PAPEL técnico (manager,
-- gravado a partir do tipo de usuário "Gestor") e a única trava por perfil consultava
-- o módulo errado (configuracoes). O escopo de Ouvidoria nunca era lido pelo servidor.
--
-- Esta entrega fecha o buraco no mesmo estilo das demais travas por perfil:
--   1) LEITURA: a política RESTRICTIVE passa a consultar o módulo 'ouvidoria'. Escopo amplo
--      vê todas; "Próprio usuário" vê só a que ele registrou (autor), a que lhe foi
--      encaminhada (responsável) ou a que ele respondeu. Sem perfil vinculado nada muda
--      (a função devolve o legado por papel).
--   2) ESCRITA: UPDATE (responder, mudar status) e DELETE exigem o verbo no módulo com
--      escopo amplo. INSERT segue aberto: todos podem registrar a própria manifestação.
--   3) ANEXOS (storage): leitura pelo perfil, e cada pessoa lê o que ela mesma enviou.
--
-- Só políticas — nenhum dado é alterado. Quem hoje vê tudo só pelo papel e não tem
-- Ouvidoria em escopo amplo no perfil passa a ver apenas o que é seu: é o efeito
-- pretendido, e o script de entrega traz a lista de quem muda.
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
