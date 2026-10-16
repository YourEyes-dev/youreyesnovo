-- ============================================================================
-- ENTREGA — Escopo "próprio usuário" no módulo DOCUMENTOS
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de PRODUCAO.
-- PRE-REQUISITO: a camada de perfil ja existe nesta base
-- (perfil_permite_modulo, cpf_do_usuario_logado) — ja aplicada ha tempos.
--
-- Roda em UMA transacao, idempotente. NAO cria tabela (cria FUNCAO + 2
-- politicas RESTRICTIVE de leitura) -> sem auto-RLS do editor. Nao altera nem
-- apaga dado.
--
-- O que muda: um perfil com o modulo "documentos" no escopo 'proprio_usuario'
-- deixa de enxergar a estrutura inteira de pastas e passa a ver SO a propria
-- pasta de colaborador e a subarvore dela (subpastas + documentos). Acesso
-- amplo (escopo <> proprio_usuario, superadmin, manager, administrador/gestor)
-- segue vendo tudo.
-- ============================================================================

-- ── 1. Motor: ids da minha pasta de colaborador + toda a subarvore ──────────
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

-- ── 3. documentos: alinha ao mesmo criterio (modulo 'documentos' + subarvore) ─
DROP POLICY IF EXISTS perfil_restringe_leitura_documentos ON public.documentos;
CREATE POLICY perfil_restringe_leitura_documentos
  ON public.documentos
  AS RESTRICTIVE FOR SELECT TO authenticated
  USING (
    public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['documentos', 'configuracoes', 'colaboradores'])
    OR regexp_replace(COALESCE(colaborador_cpf, ''), '[^0-9]', '', 'g') = public.cpf_do_usuario_logado()
    OR pasta_id = ANY (public.ye_pastas_do_usuario(tenant_id))
  );

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT
  (SELECT count(*) FROM pg_policies
     WHERE schemaname='public' AND tablename='documento_pastas'
       AND policyname='perfil_restringe_leitura_documento_pastas') AS pol_pastas_esperado_1,
  (SELECT count(*) FROM pg_policies
     WHERE schemaname='public' AND tablename='documentos'
       AND policyname='perfil_restringe_leitura_documentos') AS pol_docs_esperado_1,
  (SELECT count(*) FROM pg_proc
     WHERE proname='ye_pastas_do_usuario') AS func_esperado_1;
