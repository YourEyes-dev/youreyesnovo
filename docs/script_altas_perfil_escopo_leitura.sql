-- ============================================================================
-- 2ª ONDA (ALTAS) — leitura por PERFIL DE ACESSO que RESPEITA O ESCOPO
-- ----------------------------------------------------------------------------
-- A leitura passa a respeitar o escopo configurado em perfil_permissoes(modulo,
-- escopo) — como o lado da ESCRITA já faz. Cria um porteiro de leitura único e
-- aplica RESTRICTIVE (soma por E ao RLS de tenant) nas tabelas ALTAS.
--
-- Escopos ENFORCADOS agora (decisão da fundadora 27/10):
--   proprio_usuario       -> só o próprio (via CPF)
--   subordinados_diretos  -> próprio + subordinados diretos (ye_cpfs_subordinados_diretos)
--   setor                 -> mesmo 'departamento' do solicitante (admissoes.departamento;
--                            SUPOSIÇÃO: setor ≡ departamento — confirmar)
--   empresa_inteira / grupo_economico / multiplas_empresas -> tudo do tenant
-- FAIL-CLOSED (tratados como 'proprio_usuario' até terem mapeamento claro):
--   unidade, equipe_direta_indireta, carteira_clientes, customizado
-- Plataforma/owner ficam acima do perfil (igual aos porteiros existentes).
-- Legado (usuário sem perfil vinculado, papel manager/gestor) -> amplo, como hoje.
--
-- NÃO altera dado. Idempotente (CREATE OR REPLACE / DROP+CREATE POLICY).
-- ============================================================================

SET lock_timeout = '10s';

-- ----------------------------------------------------------------------------
-- 1) PORTEIRO DE LEITURA (escopo-aware), por CPF do sujeito do registro
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.perfil_ve_cpf(
  p_tenant uuid, p_cpf text, VARIADIC p_modulos text[]
)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid       uuid := auth.uid();
  v_cpf_me    text := public.cpf_do_usuario_logado();
  v_sub       text := regexp_replace(COALESCE(p_cpf, ''), '[^0-9]', '', 'g');
  v_empresa   uuid;
  v_tem_perfil boolean := false;
  v_dep_me    text;
  r RECORD;
BEGIN
  IF v_uid IS NULL OR p_tenant IS NULL THEN
    RETURN false;
  END IF;

  -- Plataforma e dono da empresa acima do perfil (consistência com os porteiros).
  IF public.is_superadmin(v_uid) THEN RETURN true; END IF;
  IF public.has_minimum_role(v_uid, 'owner'::public.app_role) THEN RETURN true; END IF;

  -- Precisa ter o módulo; se nem isso, não vê.
  IF NOT public.perfil_permite_modulo(p_tenant, VARIADIC p_modulos) THEN
    RETURN false;
  END IF;

  -- Sempre vê o próprio.
  IF v_sub <> '' AND v_cpf_me IS NOT NULL AND v_sub = v_cpf_me THEN
    RETURN true;
  END IF;

  v_empresa := public.empresa_ativa();

  -- Varre o(s) escopo(s) do perfil do usuário para esses módulos. Se QUALQUER
  -- (modulo, escopo) cobrir o sujeito, libera.
  FOR r IN
    SELECT pp.escopo::text AS escopo
    FROM public.usuarios_base ub
    JOIN public.usuario_perfil_vinculos v
      ON v.usuario_id = ub.id
     AND v.tenant_id = ub.tenant_id
     AND COALESCE(v.ativo, true) = true
     AND (v.expira_em IS NULL OR v.expira_em > now())
     AND (v_empresa IS NULL OR v.empresa_id IS NULL OR v.empresa_id = v_empresa)
    JOIN public.perfis_acesso pa
      ON pa.id = v.perfil_id
     AND COALESCE(pa.ativo, true) = true
     AND (pa.expira_em IS NULL OR pa.expira_em > now())
    JOIN public.perfil_permissoes pp
      ON pp.perfil_id = pa.id
     AND pp.modulo = ANY(p_modulos)
    WHERE ub.auth_user_id = v_uid
      AND ub.tenant_id = p_tenant
      AND ub.status::text = 'ativo'
  LOOP
    v_tem_perfil := true;
    IF r.escopo IN ('empresa_inteira', 'grupo_economico', 'multiplas_empresas') THEN
      RETURN true;
    ELSIF r.escopo = 'subordinados_diretos' THEN
      IF v_sub <> '' AND v_sub = ANY(public.ye_cpfs_subordinados_diretos(p_tenant)) THEN
        RETURN true;
      END IF;
    ELSIF r.escopo = 'setor' THEN
      IF v_cpf_me IS NOT NULL THEN
        SELECT regexp_replace(COALESCE(a.departamento, ''), '\s+', ' ', 'g')
          INTO v_dep_me
          FROM public.admissoes a
         WHERE a.tenant_id = p_tenant
           AND regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g') = v_cpf_me
         LIMIT 1;
        IF v_dep_me IS NOT NULL AND v_dep_me <> '' AND v_sub <> '' AND EXISTS (
             SELECT 1 FROM public.admissoes a2
              WHERE a2.tenant_id = p_tenant
                AND regexp_replace(COALESCE(a2.cpf, ''), '[^0-9]', '', 'g') = v_sub
                AND regexp_replace(COALESCE(a2.departamento, ''), '\s+', ' ', 'g') = v_dep_me
           ) THEN
          RETURN true;
        END IF;
      END IF;
    -- proprio_usuario / unidade / equipe_direta_indireta / carteira_clientes /
    -- customizado: fail-closed (o próprio já foi liberado acima).
    END IF;
  END LOOP;

  -- Legado: sem perfil vinculado, mas papel de gestão -> amplo (como hoje).
  IF NOT v_tem_perfil THEN
    IF public.has_minimum_role(v_uid, 'manager'::public.app_role) THEN
      RETURN true;
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.usuarios_base ub
      WHERE ub.auth_user_id = v_uid AND ub.tenant_id = p_tenant
        AND ub.tipo_usuario::text IN ('administrador', 'gestor')
    ) THEN
      RETURN true;
    END IF;
  END IF;

  RETURN false;
END
$fn$;

-- ----------------------------------------------------------------------------
-- 2) PORTEIRO por referência livre de colaborador (cpf | admissao.id | auth.uid)
--    -> resolve para CPF e delega ao perfil_ve_cpf. Para colunas colaborador_id
--    TEXT heterogêneas (ex.: pdis).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.perfil_ve_colaborador_ref(
  p_tenant uuid, p_ref text, VARIADIC p_modulos text[]
)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_ref  text := COALESCE(p_ref, '');
  v_cpf  text;
BEGIN
  IF v_ref = '' THEN
    RETURN public.perfil_ve_cpf(p_tenant, NULL, VARIADIC p_modulos);
  END IF;

  -- auth.uid() direto (dono) -> resolve pelo próprio CPF
  IF v_ref = auth.uid()::text THEN
    RETURN public.perfil_ve_cpf(p_tenant, public.cpf_do_usuario_logado(), VARIADIC p_modulos);
  END IF;

  -- é um id de admissao? pega o CPF dela
  SELECT regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g')
    INTO v_cpf
    FROM public.admissoes a
   WHERE a.tenant_id = p_tenant AND a.id::text = v_ref
   LIMIT 1;

  IF v_cpf IS NOT NULL AND v_cpf <> '' THEN
    RETURN public.perfil_ve_cpf(p_tenant, v_cpf, VARIADIC p_modulos);
  END IF;

  -- senão trata o próprio ref como CPF
  RETURN public.perfil_ve_cpf(p_tenant, v_ref, VARIADIC p_modulos);
END
$fn$;

-- ----------------------------------------------------------------------------
-- 3) POLÍTICAS RESTRICTIVE DE LEITURA — tabelas com sujeito DIRETO
--    (benefícios individuais, desligamento, ocorrências, pdis pai)
-- ----------------------------------------------------------------------------
DO $aplica_diretas$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      -- Benefícios individuais (sub de beneficios_colaboradores): CPF direto
      ('beneficios_consignado',        $p$public.perfil_ve_cpf(tenant_id, colaborador_cpf, 'beneficios')$p$),
      ('beneficios_dependentes',       $p$public.perfil_ve_cpf(tenant_id, colaborador_cpf, 'beneficios')$p$),
      ('beneficios_inss',              $p$public.perfil_ve_cpf(tenant_id, colaborador_cpf, 'beneficios')$p$),
      -- beneficios_plr (programa PLR da empresa) e beneficios_faturas (faturas da
      -- operadora, agregado) são NÍVEL EMPRESA, não dado individual -> fora do escopo.
      ('beneficios_manutencao_plano',  $p$public.perfil_ve_cpf(tenant_id, colaborador_cpf, 'beneficios')$p$),
      -- Desligamento: CPF direto
      ('admissao_desligamento_historico', $p$public.perfil_ve_cpf(tenant_id, colaborador_cpf, 'desligamento', 'rescisao', 'colaboradores')$p$),
      ('desligamento_eventos',            $p$public.perfil_ve_cpf(tenant_id, colaborador_cpf, 'desligamento', 'rescisao', 'colaboradores')$p$),
      -- Ocorrências (disciplinar) — colaborador_id TEXT livre
      ('ocorrencias',                  $p$public.perfil_ve_colaborador_ref(tenant_id, colaborador_id, 'advertencia', 'colaboradores')$p$),
      -- PDI pai: colaborador_id TEXT livre
      ('pdis',                         $p$public.perfil_ve_colaborador_ref(tenant_id, colaborador_id, 'pdi', 'desenvolvimento')$p$)
    ) AS t(tabela, predicado)
  LOOP
    IF to_regclass('public.' || r.tabela) IS NULL THEN
      RAISE NOTICE 'ALTAS: % inexistente, pulando.', r.tabela; CONTINUE;
    END IF;
    BEGIN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', r.tabela);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',
                     'perfil_restringe_leitura_' || r.tabela, r.tabela);
      EXECUTE format('CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR SELECT TO authenticated USING (%s)',
                     'perfil_restringe_leitura_' || r.tabela, r.tabela, r.predicado);
      RAISE NOTICE 'ALTAS: camada por perfil aplicada em % (sujeito direto).', r.tabela;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ALTAS: FALHA em % -> %', r.tabela, SQLERRM;
    END;
  END LOOP;
END
$aplica_diretas$;

-- ----------------------------------------------------------------------------
-- 4) POLÍTICAS RESTRICTIVE — SUB-TABELAS que herdam a visibilidade da PAI
--    (linha visível sse a linha-pai é visível; a RLS da pai é aplicada no EXISTS)
-- ----------------------------------------------------------------------------
DO $aplica_filhas$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      -- Sub de metas -> pai public.metas (já tem camada por perfil)
      ('meta_acoes',         $p$EXISTS (SELECT 1 FROM public.metas m WHERE m.id = meta_id)$p$),
      ('meta_historico',     $p$EXISTS (SELECT 1 FROM public.metas m WHERE m.id = meta_id)$p$),
      ('metas_evidencias',   $p$EXISTS (SELECT 1 FROM public.metas m WHERE m.id = meta_id)$p$),
      -- metas_indicadores = catálogo de indicadores reutilizáveis (sem meta/colaborador) -> fora do escopo.
      ('metas_participantes',$p$EXISTS (SELECT 1 FROM public.metas m WHERE m.id = meta_id)$p$),
      ('metas_checkins',     $p$EXISTS (SELECT 1 FROM public.metas m WHERE m.id = meta_id)$p$),
      ('metas_workflow_log', $p$EXISTS (SELECT 1 FROM public.metas m WHERE m.id = meta_id)$p$),
      -- Sub de PDI com pdi_id direto -> pai public.pdis
      ('pdi_feedbacks',      $p$EXISTS (SELECT 1 FROM public.pdis p WHERE p.id = pdi_id)$p$),
      ('pdi_metas',          $p$EXISTS (SELECT 1 FROM public.pdis p WHERE p.id = pdi_id)$p$),
      ('pdi_assinatura_links', $p$EXISTS (SELECT 1 FROM public.pdis p WHERE p.id = pdi_id)$p$),
      -- pdi_checkins/evidencias/acoes ligam por meta_id -> pdi_metas (que herda de pdis)
      ('pdi_checkins',       $p$EXISTS (SELECT 1 FROM public.pdi_metas pm WHERE pm.id = meta_id)$p$),
      ('pdi_evidencias',     $p$EXISTS (SELECT 1 FROM public.pdi_metas pm WHERE pm.id = meta_id)$p$),
      ('pdi_acoes',          $p$EXISTS (SELECT 1 FROM public.pdi_metas pm WHERE pm.id = meta_id)$p$)
    ) AS t(tabela, predicado)
  LOOP
    IF to_regclass('public.' || r.tabela) IS NULL THEN
      RAISE NOTICE 'ALTAS: % inexistente, pulando.', r.tabela; CONTINUE;
    END IF;
    BEGIN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', r.tabela);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',
                     'perfil_restringe_leitura_' || r.tabela, r.tabela);
      EXECUTE format('CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR SELECT TO authenticated USING (%s)',
                     'perfil_restringe_leitura_' || r.tabela, r.tabela, r.predicado);
      RAISE NOTICE 'ALTAS: camada por perfil aplicada em % (herda da pai).', r.tabela;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ALTAS: FALHA em % -> %', r.tabela, SQLERRM;
    END;
  END LOOP;
END
$aplica_filhas$;

-- ----------------------------------------------------------------------------
-- 5) CONFERÊNCIA
-- ----------------------------------------------------------------------------
SELECT t.tabela,
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_policies p
         WHERE p.schemaname = 'public' AND p.tablename = t.tabela
           AND p.policyname = 'perfil_restringe_leitura_' || t.tabela
           AND p.permissive = 'RESTRICTIVE' AND p.cmd = 'SELECT'
       ) THEN 'OK (RESTRICTIVE/SELECT)' ELSE 'FALTA' END AS camada_perfil
FROM (VALUES
  ('beneficios_consignado'),('beneficios_dependentes'),('beneficios_inss'),
  ('beneficios_manutencao_plano'),
  ('admissao_desligamento_historico'),('desligamento_eventos'),('ocorrencias'),
  ('pdis'),('meta_acoes'),('meta_historico'),('metas_evidencias'),
  ('metas_participantes'),('metas_checkins'),
  ('metas_workflow_log'),('pdi_checkins'),('pdi_evidencias'),('pdi_feedbacks'),
  ('pdi_metas'),('pdi_assinatura_links'),('pdi_acoes')
) AS t(tabela)
ORDER BY t.tabela;
