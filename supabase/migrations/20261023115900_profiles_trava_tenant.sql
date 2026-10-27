-- ============================================================================
-- PROFILES — fecha a troca de empresa (tenant_id) pelo proprio usuario (achado grave, 10/2026)
--
-- O que estava aberto (confirmado nas politicas reais de teste e producao):
--   * UPDATE "Usuarios podem atualizar proprio profile": USING e WITH CHECK so exigem user_id = auth.uid();
--     nada impede o usuario de trocar o proprio tenant_id.
--   * INSERT "Novos usuarios podem criar proprio profile": WITH CHECK so exige user_id = auth.uid();
--     quem acabou de se cadastrar pode criar o profile apontando para QUALQUER empresa.
-- Como get_user_tenant_id() le exatamente profiles.tenant_id, e quase toda politica do sistema compara com ela,
-- trocar esse campo daria acesso aos dados da outra empresa. Exige conhecer o identificador da empresa-alvo.
--
-- O que muda:
--   1) gatilho BEFORE UPDATE: tenant_id e user_id do profile nao mudam por usuario logado. Passam o Super Admin e a
--      chave de servico / SQL Editor (auth.uid() nulo), que sao os unicos caminhos legitimos (funcoes de borda).
--   2) a politica de INSERT "Novos usuarios podem criar proprio profile" e removida. O cadastro de empresa nova usa a
--      funcao de borda onboarding-signup (chave de servico); o convite usa invite-tenant-user (chave de servico); e o
--      administrador da empresa continua inserindo no proprio tenant pela politica "Admins podem inserir profiles no
--      seu tenant". Unico caminho que deixa de funcionar: AuthContext.signUp com tenantId de empresa existente, que
--      nenhuma tela usa hoje.
-- Nenhum dado e alterado. Idempotente.
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
