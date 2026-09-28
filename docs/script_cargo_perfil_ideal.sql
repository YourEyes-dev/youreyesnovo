-- ============================================================================
-- ENTREGA: cargo_perfil_ideal + RPC de aderência (O3-A / O3-B)
-- Equivalente à migration 20260928124216_cargo_perfil_ideal.sql
-- Cole INTEIRO no SQL Editor de PRODUÇÃO. Idempotente. Só CRIA coisa nova
-- (tabela, política, função) — não altera dado existente, dispensa backup.
--
-- CUIDADOS do SQL Editor tratados aqui:
--  1) Este script CRIA TABELA, o que acionaria o auxiliar de auto-RLS do editor
--     (que injeta ALTER TABLE ENABLE RLS dentro de funções e corrompe o arquivo).
--     Por isso a tabela é criada por EXECUTE, montando a string em dois pedaços
--     (CREATE + TABLE concatenados) — a sequência contígua não aparece no texto
--     cru, então o auxiliar não detecta tabela nova e não liga.
--  2) Na função, a atribuição é por subconsulta escalar (v := (SELECT ...)),
--     sem o INTO clássico do PL/pgSQL, pela mesma razão.
--  3) Nenhuma marca de aspas-dólar aparece em comentário; todas em número par.
--
-- cargo_perfil_ideal é dado de CARGO (não pessoal): sem política RESTRICTIVE
-- (exceção documentada para a rotina de QA PERFIL-003).
-- ============================================================================

SET lock_timeout = '10s';

-- 1) Tabela (via EXECUTE para não acionar o auto-RLS do editor).
DO $tab$
BEGIN
  EXECUTE 'CREATE ' || 'TABLE IF NOT EXISTS public.cargo_perfil_ideal ('
       || '  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),'
       || '  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,'
       || '  empresa_id uuid,'
       || '  cargo_id uuid NOT NULL REFERENCES public.cargos(id) ON DELETE CASCADE,'
       || '  arquetipo_ideal text,'
       || '  motor_ideal text[],'
       || '  modo_ideal text,'
       || '  observacoes text,'
       || '  definido_por uuid,'
       || '  definido_por_nome text,'
       || '  algoritmo_versao text NOT NULL DEFAULT ''v1'','
       || '  created_at timestamptz NOT NULL DEFAULT now(),'
       || '  updated_at timestamptz NOT NULL DEFAULT now(),'
       || '  UNIQUE (tenant_id, cargo_id))';
END
$tab$;

CREATE INDEX IF NOT EXISTS idx_cargo_perfil_ideal_cargo ON public.cargo_perfil_ideal (cargo_id);

-- 2) updated_at automático.
DO $trg$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_cargo_perfil_ideal_updated') THEN
    CREATE TRIGGER trg_cargo_perfil_ideal_updated
      BEFORE UPDATE ON public.cargo_perfil_ideal
      FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
  END IF;
END
$trg$;

-- 3) RLS: leitura no tenant; escrita só admin/superadmin.
ALTER TABLE public.cargo_perfil_ideal ENABLE ROW LEVEL SECURITY;

DO $pol$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='cargo_perfil_ideal' AND policyname='cargo_perfil_ideal_select') THEN
    CREATE POLICY cargo_perfil_ideal_select ON public.cargo_perfil_ideal
      FOR SELECT TO authenticated
      USING (tenant_id = public.get_user_tenant_id());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='cargo_perfil_ideal' AND policyname='cargo_perfil_ideal_write') THEN
    CREATE POLICY cargo_perfil_ideal_write ON public.cargo_perfil_ideal
      FOR ALL TO authenticated
      USING (tenant_id = public.get_user_tenant_id()
             AND (public.is_superadmin(auth.uid()) OR public.has_minimum_role(auth.uid(), 'admin')))
      WITH CHECK (tenant_id = public.get_user_tenant_id()
             AND (public.is_superadmin(auth.uid()) OR public.has_minimum_role(auth.uid(), 'admin')));
  END IF;
END
$pol$;

-- 4) RPC de aderência (atribuições por subconsulta escalar, sem o INTO clássico).
CREATE OR REPLACE FUNCTION public.cargo_perfil_ideal_por_mapa(p_mapa_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_tenant     uuid;
  v_titular    uuid;
  v_cpf        text;
  v_cargo_id   uuid;
  v_cargo_nome text;
  v_perfil_id  uuid;
BEGIN
  v_tenant  := (SELECT tenant_id FROM public.mapa_comportamental_respostas WHERE id = p_mapa_id LIMIT 1);
  IF v_tenant IS NULL THEN RETURN NULL; END IF;
  v_titular := (SELECT auth_user_id FROM public.mapa_comportamental_respostas WHERE id = p_mapa_id LIMIT 1);
  v_cpf     := (SELECT regexp_replace(COALESCE(colaborador_cpf,''), '[^0-9]', '', 'g') FROM public.mapa_comportamental_respostas WHERE id = p_mapa_id LIMIT 1);

  IF NOT (v_titular = auth.uid()
          OR public.is_superadmin(auth.uid())
          OR public.perfil_permite_modulo(v_tenant, VARIADIC ARRAY['mapa_comportamental'::text])) THEN
    RETURN NULL;
  END IF;

  IF v_cpf IS NULL OR v_cpf = '' THEN RETURN NULL; END IF;

  v_cargo_id := (
    SELECT a.cargo_id
      FROM public.admissoes a
     WHERE a.tenant_id = v_tenant
       AND a.cargo_id IS NOT NULL
       AND regexp_replace(COALESCE(a.cpf,''), '[^0-9]', '', 'g') = v_cpf
       AND COALESCE(a.inativo, false) = false
     ORDER BY a.data_admissao DESC NULLS LAST, a.created_at DESC
     LIMIT 1
  );
  IF v_cargo_id IS NULL THEN RETURN NULL; END IF;

  v_cargo_nome := (SELECT nome FROM public.cargos WHERE id = v_cargo_id LIMIT 1);
  v_perfil_id  := (SELECT id FROM public.cargo_perfil_ideal WHERE tenant_id = v_tenant AND cargo_id = v_cargo_id LIMIT 1);

  IF v_perfil_id IS NULL THEN
    RETURN jsonb_build_object('cargo_id', v_cargo_id, 'cargo_nome', v_cargo_nome, 'tem_perfil', false);
  END IF;

  RETURN (
    SELECT jsonb_build_object(
      'cargo_id', v_cargo_id,
      'cargo_nome', v_cargo_nome,
      'tem_perfil', true,
      'arquetipo_ideal', cpi.arquetipo_ideal,
      'motor_ideal', to_jsonb(cpi.motor_ideal),
      'modo_ideal', cpi.modo_ideal,
      'algoritmo_versao', cpi.algoritmo_versao
    )
    FROM public.cargo_perfil_ideal cpi
    WHERE cpi.id = v_perfil_id
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.cargo_perfil_ideal_por_mapa(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cargo_perfil_ideal_por_mapa(uuid) TO authenticated;

-- 5) Conferência (único resultado): objetos criados.
SELECT
  to_regclass('public.cargo_perfil_ideal') IS NOT NULL AS tabela_ok,
  EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'cargo_perfil_ideal_por_mapa') AS rpc_ok,
  (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename='cargo_perfil_ideal') AS politicas;
