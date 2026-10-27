-- ============================================================================
-- ENTREGA — profiles: o usuario nao troca a propria empresa (achado grave)
-- Cole no SQL Editor (TESTE e HOMOLOGACAO primeiro; depois PRODUCAO). UMA transacao, idempotente.
-- Nao altera dado e nao cria tabela: so um gatilho BEFORE UPDATE e a remocao de uma politica de INSERT.
-- Termina com UMA conferencia SELECT.
-- ============================================================================
SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.profiles_protege_tenant()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $fn$
BEGIN
  IF (NEW.tenant_id IS DISTINCT FROM OLD.tenant_id OR NEW.user_id IS DISTINCT FROM OLD.user_id)
     AND auth.uid() IS NOT NULL
     AND NOT public.is_superadmin(auth.uid()) THEN
    RAISE EXCEPTION 'A empresa e o usuario de um profile nao podem ser alterados.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN NEW;
END;
$fn$;

DO $trg$
BEGIN
  IF to_regclass('public.profiles') IS NULL THEN
    RAISE NOTICE 'profiles ausente nesta base; nada a fazer.';
    RETURN;
  END IF;
  DROP TRIGGER IF EXISTS trg_profiles_protege_tenant ON public.profiles;
  CREATE TRIGGER trg_profiles_protege_tenant
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.profiles_protege_tenant();
  DROP POLICY IF EXISTS "Novos usuários podem criar próprio profile" ON public.profiles;
  RAISE NOTICE 'profiles: troca de empresa fechada.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENCAO: profiles nao foi protegida: %', SQLERRM;
END $trg$;

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT
  (SELECT count(*) FROM pg_trigger WHERE tgrelid = 'public.profiles'::regclass AND tgname = 'trg_profiles_protege_tenant' AND NOT tgisinternal) AS gatilho_ativo,
  (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename='profiles' AND cmd='INSERT' AND policyname = 'Novos usuários podem criar próprio profile') AS politica_aberta_restante;
-- Esperado: 1 e 0.
--
-- DESFAZER (so se algo errado aparecer):
--   DROP TRIGGER IF EXISTS trg_profiles_protege_tenant ON public.profiles;
--   CREATE POLICY "Novos usuários podem criar próprio profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
