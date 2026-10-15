-- ============================================================================
-- Escopo "próprio usuário" — aplicação no módulo DOCUMENTOS
--
-- Problema: a tela de Documentos listava as pastas pela política permissiva
-- "Usuários podem ver pastas do tenant" (qualquer membro do tenant via TODAS as
-- pastas — empresa, unidades, outros colaboradores). Não havia camada de perfil
-- em documento_pastas, então um perfil com o módulo "documentos" no escopo
-- 'proprio_usuario' ainda enxergava a estrutura inteira.
--
-- Correção (server-side): camada RESTRICTIVE de leitura em documento_pastas.
-- Quem tem acesso AMPLO ao módulo (perfil_permite_modulo = escopo <>
-- proprio_usuario, mais superadmin/manager/administrador/gestor) continua vendo
-- tudo. Quem só tem 'proprio_usuario' passa a ver apenas a PRÓPRIA pasta de
-- colaborador e a subárvore dela (subpastas + documentos), nada da empresa.
--
--   ye_pastas_do_usuario(tenant) → ids da minha pasta de colaborador + descendentes
--
-- A pasta "minha" é a de tipo 'colaborador' cujo CPF (coluna colaborador_cpf) ou
-- cuja admissão vinculada (colaborador_id → admissoes.cpf) bate com
-- cpf_do_usuario_logado(). A função é SECURITY DEFINER para montar a subárvore
-- sem recair na própria RLS.
--
-- Também estende a política já existente de `documentos` para liberar os
-- arquivos que estão DENTRO da minha subárvore (além do já previsto por
-- colaborador_cpf), e inclui o módulo 'documentos' no teste de acesso amplo —
-- alinhando documentos e pastas ao mesmo critério.
-- ============================================================================

-- ── 1. Motor: ids da minha pasta de colaborador + toda a subárvore ──────────
CREATE OR REPLACE FUNCTION public.ye_pastas_do_usuario(p_tenant_id uuid)
RETURNS uuid[]
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_cpf text := public.cpf_do_usuario_logado();
  v_res uuid[];
BEGIN
  IF p_tenant_id IS NULL OR v_cpf IS NULL OR v_cpf = '' THEN
    RETURN ARRAY[]::uuid[];
  END IF;

  WITH RECURSIVE minhas_raizes AS (
    SELECT p.id
      FROM public.documento_pastas p
     WHERE p.tenant_id = p_tenant_id
       AND p.tipo::text = 'colaborador'
       AND (
             regexp_replace(COALESCE(p.colaborador_cpf, ''), '[^0-9]', '', 'g') = v_cpf
          OR p.colaborador_id IN (
               SELECT a.id
                 FROM public.admissoes a
                WHERE a.tenant_id = p_tenant_id
                  AND regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g') = v_cpf
             )
       )
  ),
  subarvore AS (
    SELECT id FROM minhas_raizes
    UNION
    SELECT f.id
      FROM public.documento_pastas f
      JOIN subarvore s ON f.pasta_pai_id = s.id
     WHERE f.tenant_id = p_tenant_id
  )
  SELECT COALESCE(array_agg(id), ARRAY[]::uuid[]) INTO v_res FROM subarvore;

  RETURN v_res;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.ye_pastas_do_usuario(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ye_pastas_do_usuario(uuid) TO authenticated;

-- ── 2. Camada de perfil em documento_pastas (leitura) ───────────────────────
DROP POLICY IF EXISTS perfil_restringe_leitura_documento_pastas ON public.documento_pastas;
CREATE POLICY perfil_restringe_leitura_documento_pastas
  ON public.documento_pastas
  AS RESTRICTIVE FOR SELECT TO authenticated
  USING (
    public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['documentos', 'configuracoes', 'colaboradores'])
    OR id = ANY (public.ye_pastas_do_usuario(tenant_id))
  );

-- ── 3. documentos: alinha ao mesmo critério (módulo 'documentos' + subárvore) ─
DROP POLICY IF EXISTS perfil_restringe_leitura_documentos ON public.documentos;
CREATE POLICY perfil_restringe_leitura_documentos
  ON public.documentos
  AS RESTRICTIVE FOR SELECT TO authenticated
  USING (
    public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['documentos', 'configuracoes', 'colaboradores'])
    OR regexp_replace(COALESCE(colaborador_cpf, ''), '[^0-9]', '', 'g') = public.cpf_do_usuario_logado()
    OR pasta_id = ANY (public.ye_pastas_do_usuario(tenant_id))
  );
