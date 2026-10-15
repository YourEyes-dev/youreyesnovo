-- ============================================================================
-- ENTREGA — Escopo "subordinados diretos" · FUNDAÇÃO (hierarquia + motor)
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de PRODUCAO.
-- Roda em UMA transacao, e idempotente (rodar duas vezes nao quebra).
--
-- O que faz:
--  1) cria a ancora de chefia por CPF do gestor (admissoes.gestor_cpf) + indice.
--     O CPF e a identidade que colaborador, pro-labore E usuario do sistema
--     compartilham — assim qualquer gestor com CPF resolve seus subordinados,
--     tenha ou nao ficha de colaborador;
--  2) backfill best-effort a partir do texto livre gestor_imediato (so quando o
--     nome e unico no tenant; nao sobrescreve, nao liga a si mesmo);
--  3) cria funcoes SOMENTE LEITURA que resolvem "meus subordinados diretos" e
--     o escopo efetivo do perfil num modulo.
--
-- IMPORTANTE: este script NAO altera nenhuma politica de acesso. As funcoes
-- ficam prontas, porem ainda nao sao usadas por politica alguma — o acesso
-- segue exatamente como hoje. A aplicacao nos modulos vem em entregas seguintes.
--
-- OBS de editor: NAO cria tabela (so ALTER + funcoes), entao o auto-RLS do
-- editor nao e acionado. Popula uma COLUNA NOVA (nasce NULL), nao altera nem
-- apaga dado existente; desfazer o backfill, se preciso, e
--   UPDATE public.admissoes SET gestor_cpf = NULL;
-- ============================================================================

SET lock_timeout = '10s';

-- ── 1. Ancora de chefia: CPF do gestor (digitos) ────────────────────────────
ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS gestor_cpf text;

CREATE INDEX IF NOT EXISTS idx_admissoes_gestor_cpf
  ON public.admissoes(gestor_cpf);

-- ── 2. Backfill best-effort a partir do texto livre gestor_imediato ─────────
DO $backfill$
BEGIN
  UPDATE public.admissoes a
     SET gestor_cpf = g.cpf_norm
    FROM (
      SELECT tenant_id, lower(btrim(nome_completo)) AS nome_norm,
             min(regexp_replace(COALESCE(cpf, ''), '[^0-9]', '', 'g')) AS cpf_norm,
             count(*) AS n
        FROM public.admissoes
       GROUP BY tenant_id, lower(btrim(nome_completo))
      HAVING count(*) = 1
    ) g
   WHERE (a.gestor_cpf IS NULL OR a.gestor_cpf = '')
     AND a.gestor_imediato IS NOT NULL
     AND btrim(a.gestor_imediato) <> ''
     AND a.tenant_id = g.tenant_id
     AND lower(btrim(a.gestor_imediato)) = g.nome_norm
     AND g.cpf_norm <> ''
     AND g.cpf_norm <> regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Backfill de gestor_cpf pulado: %', SQLERRM;
END $backfill$;

-- ── 3. CPFs dos meus subordinados diretos (vinculo por CPF + apoio depto) ───
CREATE OR REPLACE FUNCTION public.ye_cpfs_subordinados_diretos(p_tenant_id uuid)
RETURNS text[]
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_cpf text := public.cpf_do_usuario_logado();
  v_res text[];
BEGIN
  IF p_tenant_id IS NULL OR v_cpf IS NULL OR v_cpf = '' THEN
    RETURN ARRAY[]::text[];
  END IF;

  SELECT COALESCE(array_agg(DISTINCT cpf_norm), ARRAY[]::text[])
    INTO v_res
    FROM (
      SELECT regexp_replace(COALESCE(s.cpf, ''), '[^0-9]', '', 'g') AS cpf_norm
        FROM public.admissoes s
       WHERE s.tenant_id = p_tenant_id
         AND regexp_replace(COALESCE(s.gestor_cpf, ''), '[^0-9]', '', 'g') = v_cpf
      UNION
      SELECT regexp_replace(COALESCE(s.cpf, ''), '[^0-9]', '', 'g')
        FROM public.admissoes s
        JOIN public.departamentos d
          ON d.id = s.departamento_id
         AND d.tenant_id = p_tenant_id
        JOIN public.admissoes g
          ON g.id = d.gestor_admissao_id
         AND g.tenant_id = p_tenant_id
         AND regexp_replace(COALESCE(g.cpf, ''), '[^0-9]', '', 'g') = v_cpf
       WHERE s.tenant_id = p_tenant_id
    ) q
   WHERE cpf_norm <> '' AND cpf_norm <> v_cpf;

  RETURN v_res;
END;
$fn$;

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

-- ── 4. Perfil concede escopo 'subordinados_diretos' neste modulo? ───────────
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

-- Grants (iguais ao padrao da camada de perfil).
DO $grants$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY[
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

-- ── Conferencia (o editor mostra so o ultimo resultado) ─────────────────────
SELECT
  (SELECT count(*) FROM information_schema.columns
     WHERE table_schema='public' AND table_name='admissoes'
       AND column_name='gestor_cpf')                               AS coluna_gestor_cpf_ok,
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname IN
       ('ye_cpfs_subordinados_diretos','ye_cpf_eh_subordinado_direto',
        'perfil_tem_escopo_subordinados','perfil_amplo_sem_subordinados'))  AS funcoes_criadas_esperado_4,
  (SELECT count(*) FROM public.admissoes
     WHERE gestor_cpf IS NOT NULL AND gestor_cpf <> '')            AS vinculos_preenchidos;
