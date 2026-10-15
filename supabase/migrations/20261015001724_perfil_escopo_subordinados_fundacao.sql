-- ============================================================================
-- Escopo "subordinados diretos" — FUNDAÇÃO (hierarquia + motor de resolução)
--
-- Até aqui a camada de perfil só distinguia "próprio usuário" de "mais que
-- isso": a função perfil_permite_modulo devolve true para QUALQUER escopo que
-- não seja proprio_usuario, então "subordinados diretos" se comportava como
-- "empresa inteira". Esta migration NÃO altera nenhuma política ainda — só
-- cria a base para o filtro real:
--   1) um vínculo ESTRUTURADO de chefe imediato por pessoa
--      (admissoes.gestor_admissao_id), com apoio do gestor do departamento;
--   2) funções SOMENTE LEITURA que resolvem "quem são meus subordinados
--      diretos" e "qual é o escopo efetivo do meu perfil num módulo".
-- As políticas que usam este motor entram em migrations seguintes, módulo a
-- módulo (ponto, férias, atestados…), para poder validar cada uma.
-- ============================================================================

SET lock_timeout = '10s';

-- ── 1. Vínculo estruturado de chefe imediato ────────────────────────────────
-- Aponta para a admissão do gestor. ON DELETE SET NULL: se o gestor sai, o
-- subordinado não some — só fica sem chefe até ser reatribuído.
ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS gestor_admissao_id uuid
    REFERENCES public.admissoes(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_admissoes_gestor_admissao
  ON public.admissoes(gestor_admissao_id);

-- Backfill best-effort a partir do texto livre `gestor_imediato` (um nome):
-- liga ao colaborador de mesmo nome no mesmo tenant, quando houver um único
-- correspondente. Não sobrescreve vínculo já definido, não liga a si mesmo, e
-- ignora nomes ambíguos (mais de um colaborador com o mesmo nome).
DO $backfill$
BEGIN
  UPDATE public.admissoes a
     SET gestor_admissao_id = g.id
    FROM (
      SELECT tenant_id, lower(btrim(nome_completo)) AS nome_norm,
             min(id::text)::uuid AS id, count(*) AS n
        FROM public.admissoes
       GROUP BY tenant_id, lower(btrim(nome_completo))
      HAVING count(*) = 1
    ) g
   WHERE a.gestor_admissao_id IS NULL
     AND a.gestor_imediato IS NOT NULL
     AND btrim(a.gestor_imediato) <> ''
     AND a.tenant_id = g.tenant_id
     AND lower(btrim(a.gestor_imediato)) = g.nome_norm
     AND g.id <> a.id;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Backfill de gestor_admissao_id pulado: %', SQLERRM;
END $backfill$;

-- ── 2. Minha admissão (a do usuário logado), por CPF ────────────────────────
-- Não existe admissoes.usuario_id; o elo é o CPF normalizado, igual ao resto
-- da camada de perfil (cpf_do_usuario_logado).
CREATE OR REPLACE FUNCTION public.ye_minha_admissao_id(p_tenant_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT a.id
    FROM public.admissoes a
   WHERE a.tenant_id = p_tenant_id
     AND regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g')
         = public.cpf_do_usuario_logado()
     AND public.cpf_do_usuario_logado() <> ''
   ORDER BY a.created_at DESC NULLS LAST
   LIMIT 1;
$fn$;

-- ── 3. CPFs dos meus subordinados diretos (vínculo direto + depto) ──────────
-- Direto: admissoes.gestor_admissao_id = a minha admissão.
-- Apoio:  colaboradores do(s) departamento(s) que eu chefio
--         (departamentos.gestor_admissao_id = a minha admissão).
-- Não inclui a mim mesmo (o próprio CPF já é coberto por outro predicado).
CREATE OR REPLACE FUNCTION public.ye_cpfs_subordinados_diretos(p_tenant_id uuid)
RETURNS text[]
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_cpf text := public.cpf_do_usuario_logado();
  v_minha_adm uuid;
  v_res text[];
BEGIN
  IF p_tenant_id IS NULL OR v_cpf IS NULL OR v_cpf = '' THEN
    RETURN ARRAY[]::text[];
  END IF;

  v_minha_adm := public.ye_minha_admissao_id(p_tenant_id);
  IF v_minha_adm IS NULL THEN
    RETURN ARRAY[]::text[];
  END IF;

  SELECT COALESCE(array_agg(DISTINCT cpf_norm), ARRAY[]::text[])
    INTO v_res
    FROM (
      -- vínculo direto estruturado
      SELECT regexp_replace(COALESCE(s.cpf, ''), '[^0-9]', '', 'g') AS cpf_norm
        FROM public.admissoes s
       WHERE s.tenant_id = p_tenant_id
         AND s.gestor_admissao_id = v_minha_adm
      UNION
      -- apoio: colaboradores do departamento que eu chefio
      SELECT regexp_replace(COALESCE(s.cpf, ''), '[^0-9]', '', 'g')
        FROM public.admissoes s
        JOIN public.departamentos d
          ON d.id = s.departamento_id
         AND d.tenant_id = p_tenant_id
         AND d.gestor_admissao_id = v_minha_adm
       WHERE s.tenant_id = p_tenant_id
    ) q
   WHERE cpf_norm <> '' AND cpf_norm <> v_cpf;

  RETURN v_res;
END;
$fn$;

-- Conveniência booleana para usar nas políticas (um CPF é meu subordinado?).
CREATE OR REPLACE FUNCTION public.ye_cpf_eh_subordinado_direto(
  p_tenant_id uuid, p_cpf text
)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT regexp_replace(COALESCE(p_cpf, ''), '[^0-9]', '', 'g')
         = ANY (public.ye_cpfs_subordinados_diretos(p_tenant_id))
     AND regexp_replace(COALESCE(p_cpf, ''), '[^0-9]', '', 'g') <> '';
$fn$;

-- ── 4. Meu perfil concede ESCOPO 'subordinados_diretos' neste módulo? ───────
-- Espelha o recorte por empresa ativa de perfil_permite_modulo, mas olha só o
-- tier 'subordinados_diretos'. Usada nas políticas para ligar o OR dos
-- subordinados apenas a quem foi configurado com esse escopo.
CREATE OR REPLACE FUNCTION public.perfil_tem_escopo_subordinados(
  p_tenant_id uuid, VARIADIC p_modulos text[]
)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_status text;
  v_empresa uuid;
BEGIN
  IF v_uid IS NULL OR p_tenant_id IS NULL THEN
    RETURN false;
  END IF;

  SELECT ub.status::text INTO v_status
    FROM public.usuarios_base ub
   WHERE ub.auth_user_id = v_uid AND ub.tenant_id = p_tenant_id
   LIMIT 1;

  -- Com cadastro, só 'ativo' conta (igual perfil_permite_modulo).
  IF v_status IS NOT NULL AND v_status <> 'ativo' THEN
    RETURN false;
  END IF;

  v_empresa := public.empresa_ativa();
  IF v_empresa IS NULL AND public.empresa_ativa_obrigatoria() THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1
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
        ON pp.perfil_id = v.perfil_id
       AND COALESCE(pp.ativo, true) = true
       AND pp.modulo = ANY (p_modulos)
       AND COALESCE(pp.escopo::text, '') = 'subordinados_diretos'
     WHERE ub.auth_user_id = v_uid
       AND ub.tenant_id = p_tenant_id
  );
END;
$fn$;

-- ── 5. Acesso AMPLO (empresa inteira) SEM contar 'subordinados_diretos' ─────
-- Cópia de perfil_permite_modulo, mas no tier por perfil/exceção o escopo
-- 'subordinados_diretos' DEIXA de valer como amplo (passa a ser tratado como
-- recorte, não como liberação geral). Papéis de gestão (superadmin, manager,
-- tipo administrador/gestor) seguem vendo tudo, de propósito. As políticas dos
-- módulos implementados usam ESTA função no lugar de perfil_permite_modulo e
-- acrescentam o OR dos subordinados; os módulos ainda não implementados
-- continuam com perfil_permite_modulo (subordinados = empresa inteira lá).
CREATE OR REPLACE FUNCTION public.perfil_amplo_sem_subordinados(
  p_tenant_id uuid, VARIADIC p_modulos text[]
)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_status text;
  v_empresa uuid;
BEGIN
  IF v_uid IS NULL OR p_tenant_id IS NULL THEN
    RETURN false;
  END IF;

  IF public.is_superadmin(v_uid) THEN
    RETURN true;
  END IF;

  SELECT ub.status::text INTO v_status
    FROM public.usuarios_base ub
   WHERE ub.auth_user_id = v_uid AND ub.tenant_id = p_tenant_id
   LIMIT 1;

  IF v_status IS NULL THEN
    RETURN public.has_minimum_role(v_uid, 'manager'::public.app_role)
       AND EXISTS (
             SELECT 1 FROM public.profiles pr
              WHERE pr.user_id = v_uid AND pr.tenant_id = p_tenant_id
           );
  END IF;

  IF v_status <> 'ativo' THEN
    RETURN false;
  END IF;

  IF public.has_minimum_role(v_uid, 'manager'::public.app_role) THEN
    RETURN true;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.usuarios_base ub
     WHERE ub.auth_user_id = v_uid
       AND ub.tenant_id = p_tenant_id
       AND ub.tipo_usuario::text IN ('administrador', 'gestor')
  ) THEN
    RETURN true;
  END IF;

  v_empresa := public.empresa_ativa();
  IF v_empresa IS NULL AND public.empresa_ativa_obrigatoria() THEN
    RETURN false;
  END IF;

  -- Tier por perfil: amplo só com escopo que NÃO seja próprio NEM subordinados.
  IF EXISTS (
    SELECT 1
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
        ON pp.perfil_id = v.perfil_id
       AND COALESCE(pp.ativo, true) = true
       AND pp.modulo = ANY (p_modulos)
       AND COALESCE(pp.escopo::text, '') NOT IN ('proprio_usuario', 'subordinados_diretos')
     WHERE ub.auth_user_id = v_uid
       AND ub.tenant_id = p_tenant_id
  ) THEN
    RETURN true;
  END IF;

  RETURN EXISTS (
    SELECT 1
      FROM public.usuarios_base ub
      JOIN public.perfil_excecoes pe
        ON pe.usuario_id = ub.id
       AND pe.tenant_id = ub.tenant_id
       AND COALESCE(pe.ativo, true) = true
       AND COALESCE(pe.tipo, 'adicional') = 'adicional'
       AND (pe.expira_em IS NULL OR pe.expira_em > now())
       AND pe.modulo = ANY (p_modulos)
       AND COALESCE(pe.escopo::text, '') NOT IN ('proprio_usuario', 'subordinados_diretos')
       AND (v_empresa IS NULL OR pe.empresa_id IS NULL OR pe.empresa_id = v_empresa)
     WHERE ub.auth_user_id = v_uid
       AND ub.tenant_id = p_tenant_id
  );
END;
$fn$;

-- Permissões de execução (iguais ao padrão da camada de perfil).
DO $grants$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY[
    'public.ye_minha_admissao_id(uuid)',
    'public.ye_cpfs_subordinados_diretos(uuid)',
    'public.ye_cpf_eh_subordinado_direto(uuid, text)',
    'public.perfil_tem_escopo_subordinados(uuid, text[])',
    'public.perfil_amplo_sem_subordinados(uuid, text[])'
  ]
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', r);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', r);
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Ajuste de grants pulado: %', SQLERRM;
END $grants$;
