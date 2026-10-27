-- ============================================================================
-- CADASTRO DE COLABORADORES (passo 2.6, PARTE 1): funcoes de leitura para quem nao e do RH
--
-- A tabela admissoes (CPF, banco, saude do exame admissional, salario) e lida por quase todo o sistema. Antes de restringir
-- a leitura por perfil (PARTE 2, depois de publicar as telas), os recursos que TODOS usam passam a ler por funcoes proprias,
-- que devolvem so o necessario. Esta parte e ADITIVA: nada fecha ainda e nenhuma tela quebra.
--
--   colaboradores_diretorio(empresa)   lista de pessoas ativas (nome, cargo, departamento, filial, gestor, foto, tipo de
--                                      contrato...), como uma lista de ramais. CPF, e-mail e celular so vem para: a propria
--                                      pessoa, quem tem acesso de gestao a dados de pessoas, e o lider (so da equipe).
--                                      O hook useColaboradores passa a usar esta funcao (seletores, mural, PDI, trilhas...).
--   celebracoes_pessoas(empresa)       aniversariantes e tempo de casa para o mural e a Cultura; a data de nascimento sai
--                                      SEM O ANO (so dia e mes), decisao do dono do produto.
--   meu_time_admissoes()               equipe do gestor (mesma regra de hoje: gestor imediato pelo nome ou chefe do depto).
--   admissoes_contagens(empresa)       totais do Inicio (ativos, pendentes, em aberto), sem dado pessoal.
--   admissoes_historico_status(...)    status e data de criacao por admissao, para o grafico historico, sem dado pessoal.
--   ye_modulos_dados_pessoas()         fonte unica da lista de modulos que leem a ficha completa (usada tambem na PARTE 2).
-- Todas security definer, fechadas a anon, restritas a empresa de quem chama. Nao altera dado. Idempotente.
-- ============================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.ye_modulos_dados_pessoas()
RETURNS text[]
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT ARRAY['colaboradores', 'ponto', 'analise_jornada', 'ferias', 'financeiro', 'beneficios', 'psicossocial',
               'sst', 'atestados', 'epi', 'incidentes', 'avaliacoes', 'onboarding', 'contratos_experiencia',
               'usuarios', 'hub_contabil', 'configuracoes', 'cargos', 'departamentos', 'filiais', 'empresa',
               'ergonomia']::text[]
$fn$;

REVOKE EXECUTE ON FUNCTION public.ye_modulos_dados_pessoas() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ye_modulos_dados_pessoas() TO authenticated, service_role;

-- ── Diretorio de pessoas ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.colaboradores_diretorio(p_empresa_id uuid DEFAULT NULL)
RETURNS TABLE (
  id uuid, nome_completo text, cpf text, cargo text, cargo_id uuid, departamento text, email text, celular text,
  filial text, data_admissao text, empresa_id uuid, gestor_imediato text, foto_url text, tipo_contrato text,
  bate_ponto boolean, inativo boolean
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_tenant uuid := public.get_user_tenant_id();
  v_amplo boolean;
  v_subs text[] := ARRAY[]::text[];
  v_cpf text;
BEGIN
  IF v_tenant IS NULL OR auth.uid() IS NULL THEN
    RETURN;
  END IF;
  v_amplo := public.perfil_amplo_sem_subordinados(v_tenant, VARIADIC public.ye_modulos_dados_pessoas());
  IF NOT v_amplo AND public.perfil_tem_escopo_subordinados(v_tenant, VARIADIC public.ye_modulos_dados_pessoas()) THEN
    v_subs := public.ye_cpfs_subordinados_diretos(v_tenant);
  END IF;
  v_cpf := COALESCE(public.cpf_do_usuario_logado(), '');

  RETURN QUERY
    SELECT a.id, a.nome_completo::text,
           CASE WHEN v_amplo
                  OR (v_cpf <> '' AND regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g') = v_cpf)
                  OR regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g') = ANY (v_subs)
                THEN a.cpf::text ELSE ''::text END AS cpf,
           a.cargo::text, a.cargo_id::uuid, a.departamento::text,
           CASE WHEN v_amplo
                  OR (v_cpf <> '' AND regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g') = v_cpf)
                  OR regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g') = ANY (v_subs)
                THEN a.email::text ELSE NULL::text END AS email,
           CASE WHEN v_amplo
                  OR (v_cpf <> '' AND regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g') = v_cpf)
                  OR regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g') = ANY (v_subs)
                THEN a.celular::text ELSE NULL::text END AS celular,
           a.filial::text, a.data_admissao::text, a.empresa_id::uuid, a.gestor_imediato::text, a.foto_url::text,
           a.tipo_contrato::text, a.bate_ponto::boolean, a.inativo::boolean
      FROM public.admissoes a
     WHERE a.tenant_id = v_tenant
       AND a.status::text = 'concluido'
       AND (p_empresa_id IS NULL OR a.empresa_id = p_empresa_id)
     ORDER BY a.data_admissao DESC NULLS LAST;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.colaboradores_diretorio(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.colaboradores_diretorio(uuid) TO authenticated, service_role;

-- ── Celebracoes (aniversario sem o ano) ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.celebracoes_pessoas(p_empresa_id uuid DEFAULT NULL)
RETURNS TABLE (id uuid, nome_completo text, data_nascimento text, data_admissao text, cargo text)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_tenant uuid := public.get_user_tenant_id();
BEGIN
  IF v_tenant IS NULL OR auth.uid() IS NULL THEN
    RETURN;
  END IF;
  RETURN QUERY
    SELECT a.id, a.nome_completo::text,
           -- so dia e mes: o ano real de nascimento nao sai daqui (2000 e bissexto, entao 29/02 continua valendo)
           CASE WHEN a.data_nascimento IS NOT NULL THEN '2000-' || to_char(a.data_nascimento::date, 'MM-DD') ELSE NULL END,
           a.data_admissao::text, a.cargo::text
      FROM public.admissoes a
     WHERE a.tenant_id = v_tenant
       AND a.status::text = 'concluido'
       AND (p_empresa_id IS NULL OR a.empresa_id = p_empresa_id);
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.celebracoes_pessoas(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.celebracoes_pessoas(uuid) TO authenticated, service_role;

-- ── Meu time ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.meu_time_admissoes()
RETURNS SETOF uuid
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_tenant uuid := public.get_user_tenant_id();
  v_uid uuid := auth.uid();
  v_nome text;
  v_cpf text := COALESCE(public.cpf_do_usuario_logado(), '');
  v_meu uuid;
BEGIN
  IF v_tenant IS NULL OR v_uid IS NULL THEN
    RETURN;
  END IF;
  v_nome := COALESCE(
    (SELECT btrim(ub.nome_completo) FROM public.usuarios_base ub
      WHERE ub.auth_user_id = v_uid AND ub.tenant_id = v_tenant LIMIT 1),
    (SELECT btrim(p.nome_completo) FROM public.profiles p WHERE p.user_id = v_uid LIMIT 1), '');
  IF v_cpf <> '' THEN
    v_meu := (SELECT a.id FROM public.admissoes a
               WHERE a.tenant_id = v_tenant
                 AND regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g') = v_cpf
               ORDER BY a.created_at DESC NULLS LAST LIMIT 1);
  END IF;
  RETURN QUERY
    SELECT DISTINCT a.id
      FROM public.admissoes a
     WHERE a.tenant_id = v_tenant
       AND a.status::text = 'concluido'
       AND ( (v_nome <> '' AND lower(btrim(COALESCE(a.gestor_imediato, ''))) = lower(v_nome))
             OR (v_meu IS NOT NULL AND a.departamento IN (
                   SELECT d.nome FROM public.departamentos d
                    WHERE d.tenant_id = v_tenant
                      AND (d.gestor_admissao_id = v_meu
                           OR (d.substituto_ativo AND d.gestor_substituto_admissao_id = v_meu)))) )
       AND (v_meu IS NULL OR a.id <> v_meu);
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.meu_time_admissoes() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.meu_time_admissoes() TO authenticated, service_role;

-- ── Contagens do Inicio ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admissoes_contagens(p_empresa_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_tenant uuid := public.get_user_tenant_id();
BEGIN
  IF v_tenant IS NULL OR auth.uid() IS NULL THEN
    RETURN jsonb_build_object('concluidos', 0, 'pendentes', 0, 'em_aberto', 0);
  END IF;
  RETURN (
    SELECT jsonb_build_object(
      'concluidos', count(*) FILTER (WHERE a.status::text = 'concluido'),
      'pendentes',  count(*) FILTER (WHERE a.status::text NOT IN ('concluido', 'reprovado', 'desligado')),
      'em_aberto',  count(*) FILTER (WHERE a.status::text NOT IN ('concluido', 'reprovado')))
      FROM public.admissoes a
     WHERE a.tenant_id = v_tenant
       AND (p_empresa_id IS NULL OR a.empresa_id = p_empresa_id)
  );
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.admissoes_contagens(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admissoes_contagens(uuid) TO authenticated, service_role;

-- ── Historico por status (grafico do Inicio) ────────────────────────────────
CREATE OR REPLACE FUNCTION public.admissoes_historico_status(
  p_empresa_id uuid DEFAULT NULL, p_de timestamptz DEFAULT NULL, p_ate timestamptz DEFAULT NULL
)
RETURNS TABLE (status text, created_at timestamptz)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_tenant uuid := public.get_user_tenant_id();
BEGIN
  IF v_tenant IS NULL OR auth.uid() IS NULL THEN
    RETURN;
  END IF;
  RETURN QUERY
    SELECT a.status::text, a.created_at
      FROM public.admissoes a
     WHERE a.tenant_id = v_tenant
       AND (p_empresa_id IS NULL OR a.empresa_id = p_empresa_id)
       AND (p_de IS NULL OR a.created_at >= p_de)
       AND (p_ate IS NULL OR a.created_at <= p_ate);
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.admissoes_historico_status(uuid, timestamptz, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admissoes_historico_status(uuid, timestamptz, timestamptz) TO authenticated, service_role;
