-- ============================================================================
-- VINCULOS DE USUARIO (usuario_vinculos): leitura e escrita pelo perfil de acesso
--
-- usuario_vinculos diz a quais EMPRESAS do grupo cada usuario tem acesso (e, para os externos, e o que limita o
-- que enxergam). Estava decidida so pela conta: qualquer membro lia o vinculo de todos e podia criar ou alterar
-- vinculos, inclusive os proprios. Um consultor externo, por exemplo, podia ampliar sozinho as empresas que ve.
--
-- Regra nova (RESTRICTIVE, somam-se as politicas antigas da conta):
--   LEITURA   o proprio vinculo (indispensavel: seletor de empresa e isolamento por empresa) ou quem tem o modulo
--             Usuarios/Configuracoes em escopo amplo (a tela de gestao de usuarios).
--   ESCRITA   quem tem o modulo Usuarios/Configuracoes E o verbo criar (inclui) ou editar/aprovar (altera, encerra).
--             Excecao: quem pode cadastrar empresa (modulos Empresa/Filiais/Configuracoes, verbo criar) vincula a
--             SI MESMO a empresa que acabou de criar (o app faz isso sozinho no cadastro da empresa).
--   Sem perfil vinculado vale o legado por papel (gestao), como nas demais travas.
-- Nao ha politica de exclusao (o app encerra o vinculo por UPDATE): nada de novo ali.
-- Nada de dado e alterado. Funcoes que leem a tabela por dentro do banco sao security definer e nao mudam.
-- Idempotente.
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
