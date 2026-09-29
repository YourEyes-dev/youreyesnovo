-- ============================================================================
-- O3-A/O3-B: perfil comportamental IDEAL por cargo + aderência (match)
--
-- cargo_perfil_ideal guarda o ALVO comportamental de cada cargo (arquétipo/motor/
-- modo esperados), definido por RH/admin. É dado de CARGO, não dado pessoal do
-- titular — portanto NÃO é tabela sensível (LGPD) e NÃO recebe a política
-- RESTRICTIVE perfil_restringe_leitura_* (exceção documentada aqui para a rotina
-- de QA PERFIL-003): leitura liberada no tenant, escrita só admin/superadmin.
--
-- A aderência (O3-B) é exposta pela RPC cargo_perfil_ideal_por_mapa: dado o id do
-- mapa de uma pessoa, resolve cpf -> admissão recente -> cargo_id -> perfil ideal
-- e devolve APENAS o alvo do cargo (nível cargo). O cálculo da aderência em si é
-- determinístico e roda no front (função pura testada), a partir do resultado do
-- mapa que o gestor já enxerga — sem vazar respostas item a item (RN-003).
-- ============================================================================

SET lock_timeout = '10s';

CREATE TABLE IF NOT EXISTS public.cargo_perfil_ideal (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id         uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  empresa_id        uuid,
  cargo_id          uuid NOT NULL REFERENCES public.cargos(id) ON DELETE CASCADE,
  arquetipo_ideal   text,        -- 'pioneiro'|'conector'|'guardiao'|'estrategista'
  motor_ideal       text[],      -- subconjunto de 'racional'|'relacional'|'pragmatico'
  modo_ideal        text,        -- 'constante'|'cadenciado'|'misto'
  observacoes       text,
  definido_por      uuid,
  definido_por_nome text,
  algoritmo_versao  text NOT NULL DEFAULT 'v1',
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, cargo_id)
);

CREATE INDEX IF NOT EXISTS idx_cargo_perfil_ideal_cargo ON public.cargo_perfil_ideal (cargo_id);

-- updated_at automático (função utilitária já existente no schema).
DO $trg$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_cargo_perfil_ideal_updated') THEN
    CREATE TRIGGER trg_cargo_perfil_ideal_updated
      BEFORE UPDATE ON public.cargo_perfil_ideal
      FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
  END IF;
END
$trg$;

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

-- RPC: perfil ideal do cargo que a PESSOA (dona do mapa) ocupa.
CREATE OR REPLACE FUNCTION public.cargo_perfil_ideal_por_mapa(p_mapa_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_tenant   uuid;
  v_titular  uuid;
  v_cpf      text;
  v_cargo_id uuid;
  v_cargo_nome text;
  v_perfil   public.cargo_perfil_ideal;
BEGIN
  SELECT tenant_id, auth_user_id, regexp_replace(COALESCE(colaborador_cpf,''), '[^0-9]', '', 'g')
    INTO v_tenant, v_titular, v_cpf
    FROM public.mapa_comportamental_respostas
   WHERE id = p_mapa_id
   LIMIT 1;

  IF v_tenant IS NULL THEN RETURN NULL; END IF;

  -- Mesmo gate das RPCs do Mapa: titular, superadmin, ou perfil com o módulo.
  IF NOT (v_titular = auth.uid()
          OR public.is_superadmin(auth.uid())
          OR public.perfil_permite_modulo(v_tenant, VARIADIC ARRAY['mapa_comportamental'::text])) THEN
    RETURN NULL;
  END IF;

  IF v_cpf IS NULL OR v_cpf = '' THEN RETURN NULL; END IF;

  -- Cargo pela admissão ATIVA mais recente do CPF (normaliza os dois lados).
  SELECT a.cargo_id, c.nome
    INTO v_cargo_id, v_cargo_nome
    FROM public.admissoes a
    LEFT JOIN public.cargos c ON c.id = a.cargo_id
   WHERE a.tenant_id = v_tenant
     AND a.cargo_id IS NOT NULL
     AND regexp_replace(COALESCE(a.cpf,''), '[^0-9]', '', 'g') = v_cpf
     AND COALESCE(a.inativo, false) = false
   ORDER BY a.data_admissao DESC NULLS LAST, a.created_at DESC
   LIMIT 1;

  IF v_cargo_id IS NULL THEN RETURN NULL; END IF;

  SELECT * INTO v_perfil
    FROM public.cargo_perfil_ideal
   WHERE tenant_id = v_tenant AND cargo_id = v_cargo_id
   LIMIT 1;

  IF v_perfil.id IS NULL THEN
    RETURN jsonb_build_object('cargo_id', v_cargo_id, 'cargo_nome', v_cargo_nome, 'tem_perfil', false);
  END IF;

  RETURN jsonb_build_object(
    'cargo_id', v_cargo_id,
    'cargo_nome', v_cargo_nome,
    'tem_perfil', true,
    'arquetipo_ideal', v_perfil.arquetipo_ideal,
    'motor_ideal', to_jsonb(v_perfil.motor_ideal),
    'modo_ideal', v_perfil.modo_ideal,
    'algoritmo_versao', v_perfil.algoritmo_versao
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.cargo_perfil_ideal_por_mapa(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cargo_perfil_ideal_por_mapa(uuid) TO authenticated;
