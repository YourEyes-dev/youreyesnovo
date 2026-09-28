-- ============================================================================
-- Segurança · ISOL-006 e ISOL-008 nas rotinas de admissão/eSocial de 17/09
--
-- O conserto de 16/09 (20260916210000 e 20260916230000) fechou ao anônimo as
-- rotinas sensíveis que existiam ATÉ ali, e reamarrou o cliente em duas rotinas
-- privilegiadas. Mas ele deixou registrado o próprio limite: "ROTINA NOVA
-- CONTINUA NASCENDO ABERTA AO ANÔNIMO" — no PostgreSQL toda função nasce com
-- EXECUTE concedido a PUBLIC. As rotinas de admissão/eSocial criadas em 17/09
-- nasceram, portanto, abertas, e as duas rotinas de QA voltaram a acusá-las:
--
--   ISOL-006 (executável por anônimo): admissao_esocial_gerar_s2200,
--       admissao_qualificacao_cadastral, admissoes_contrato_duplicado,
--       desligamento_esocial_gerar_s2299.
--   ISOL-008 (privilégio do dono sem reamarrar o cliente):
--       admissao_qualificacao_cadastral.
--
-- Este script:
--   1) reamarra o cliente em admissao_qualificacao_cadastral (ISOL-008);
--   2) refecha ao anônimo TODA rotina sensível que tenha nascido aberta desde
--      16/09 (ISOL-006), pelo MESMO mecanismo do bloco 8 de 16/09 — genérico e
--      idempotente, então pega as quatro acima e qualquer outra no mesmo caso,
--      sem depender de acertar a lista à mão.
--
-- Idempotente; NO-OP em base sem essas funções.
-- ============================================================================

SET lock_timeout = '10s';

-- ═════════════════════════════════════════════════════════
-- 1) ISOL-008 — admissao_qualificacao_cadastral reamarra o cliente
--
-- A rotina roda com privilégio do dono (SECURITY DEFINER) e toca admissoes;
-- sem reamarrar, um usuário logado poderia passar o id de uma admissão de OUTRO
-- cliente e tanto descobrir se CPF/nome/nascimento batem (já é informação)
-- quanto gravar 'qualificacao_cadastral' na admissão alheia. Mesma correção
-- (e mesma preservação do uso interno) das rotinas tratadas em 16/09.
-- ═════════════════════════════════════════════════════════
DO $isol008$
BEGIN
  IF to_regprocedure('public.admissao_qualificacao_cadastral(uuid)') IS NULL THEN
    RAISE NOTICE 'ISOL-008: admissao_qualificacao_cadastral(uuid) ausente — nada a fazer.';
    RETURN;
  END IF;

  CREATE OR REPLACE FUNCTION public.admissao_qualificacao_cadastral(p_admissao uuid)
  RETURNS text
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
  AS $fn$
  DECLARE a RECORD; v_cpf text; v_probs text[] := '{}'; v_status text;
  BEGIN
    -- Qualificacao cadastral: consistencia dos dados que o eSocial cruza com a
    -- base do governo antes de aceitar o S-2200 (CPF x nome x nascimento).
    SELECT * INTO a FROM public.admissoes WHERE id = p_admissao;
    IF NOT FOUND THEN RETURN NULL; END IF;

    -- ISOL-008: para quem chega com identidade, só responde sobre admissão do
    -- próprio cliente; superadmin atravessa por desenho; em contexto interno
    -- (cron, gatilho, outra função privilegiada, sem login) segue como antes.
    IF auth.uid() IS NOT NULL
       AND NOT public.is_superadmin(auth.uid())
       AND a.tenant_id IS DISTINCT FROM public.get_user_tenant_id()
    THEN
      RETURN NULL;
    END IF;

    v_cpf := regexp_replace(COALESCE(a.cpf,''), '\D', '', 'g');
    IF length(v_cpf) <> 11 THEN v_probs := array_append(v_probs, 'CPF incompleto'); END IF;
    IF COALESCE(btrim(a.nome_completo),'') = '' THEN v_probs := array_append(v_probs, 'nome ausente'); END IF;
    IF a.data_nascimento IS NULL THEN v_probs := array_append(v_probs, 'data de nascimento ausente'); END IF;
    IF a.data_nascimento IS NOT NULL AND a.data_nascimento > CURRENT_DATE THEN
      v_probs := array_append(v_probs, 'data de nascimento no futuro'); END IF;

    IF array_length(v_probs,1) IS NULL THEN
      v_status := 'apto';
    ELSE
      v_status := 'divergente: ' || array_to_string(v_probs, '; ');
    END IF;

    UPDATE public.admissoes SET qualificacao_cadastral = v_status WHERE id = p_admissao;
    RETURN v_status;
  END $fn$;

  RAISE NOTICE 'ISOL-008: admissao_qualificacao_cadastral reamarra o cliente.';
END $isol008$;

-- ═════════════════════════════════════════════════════════
-- 2) ISOL-006 — refecha ao anônimo as rotinas sensíveis nascidas abertas
--
-- Mesmo bloco de 16/09 (20260916210000, item 8), reaplicado: revoga de PUBLIC
-- e de anon (revogar só de anon não tira o que vem por PUBLIC) e devolve a quem
-- deve ter — usuário logado e papel de serviço das edge functions. O filtro por
-- has_function_privilege('anon', ...) faz o bloco tocar SÓ o que ainda está
-- aberto: as rotinas já fechadas em 16/09 não reentram. A lista de PERMITIDOS
-- é a mesma da rotina de QA — o que é público por desenho não é derrubado.
-- ═════════════════════════════════════════════════════════
DO $anon$
DECLARE
  c record; v_n int := 0; v_lista text := '';
  v_permitidos CONSTANT text[] := ARRAY[
    'get_admissao_by_token', 'get_admissao_documentos_by_token',
    'update_admissao_documento_by_token', 'update_admissao_foto_by_token',
    'finalizar_admissao_by_token', 'ensure_admissao_documentos_by_token',
    'parceiro_meu_portal', 'parceiro_estagio_tenant',
    'validar_cpf_colaborador_campanha',
    'get_user_tenant_id', 'current_user_tenant_id', 'user_tenant_ids',
    'has_tenant_access', 'user_has_empresa_vinculo', 'get_current_user_tipo',
    'user_can_access_storage_object'
  ];
BEGIN
  FOR c IN
    SELECT p.oid, p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND p.proname NOT LIKE 'qa\_%'
      AND NOT (p.proname = ANY (v_permitidos))
      AND has_function_privilege('anon', p.oid, 'EXECUTE')
      AND pg_get_functiondef(p.oid) ~* '(usuarios_base|perfis_acesso|perfil_permissoes|perfil_excecoes|usuario_perfil_vinculos|profiles|admissoes|atestados)'
    ORDER BY p.proname
  LOOP
    BEGIN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION public.%I(%s) FROM PUBLIC, anon', c.proname, c.args);
      EXECUTE format('GRANT EXECUTE ON FUNCTION public.%I(%s) TO authenticated, service_role', c.proname, c.args);
      v_n := v_n + 1;
      v_lista := v_lista || CASE WHEN v_lista = '' THEN '' ELSE ', ' END || c.proname;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ISOL-006: nao foi possivel fechar %: %', c.proname, SQLERRM;
    END;
  END LOOP;
  RAISE NOTICE 'ISOL-006: % rotina(s) fechadas ao anonimo: %', v_n, v_lista;
END $anon$;

-- ─────────────────────────────────────────────────────────
-- 3) Conferência
-- ─────────────────────────────────────────────────────────
DO $confere$
DECLARE v_anon int; v_sem_filtro int;
BEGIN
  -- ISOL-006: nenhuma rotina sensível aberta ao anônimo (fora as públicas)
  SELECT count(*) INTO v_anon
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.prokind = 'f' AND p.proname NOT LIKE 'qa\_%'
    AND has_function_privilege('anon', p.oid, 'EXECUTE')
    AND pg_get_functiondef(p.oid) ~* '(usuarios_base|perfis_acesso|perfil_permissoes|perfil_excecoes|usuario_perfil_vinculos|profiles|admissoes|atestados)'
    AND p.proname NOT IN (
      'get_admissao_by_token', 'get_admissao_documentos_by_token',
      'update_admissao_documento_by_token', 'update_admissao_foto_by_token',
      'finalizar_admissao_by_token', 'ensure_admissao_documentos_by_token',
      'parceiro_meu_portal', 'parceiro_estagio_tenant', 'validar_cpf_colaborador_campanha',
      'get_user_tenant_id', 'current_user_tenant_id', 'user_tenant_ids',
      'has_tenant_access', 'user_has_empresa_vinculo', 'get_current_user_tipo',
      'user_can_access_storage_object');

  -- ISOL-008: a rotina consertada não fica mais na lista dos que não reamarram
  SELECT count(*) INTO v_sem_filtro
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.prokind = 'f' AND p.prosecdef AND p.proname NOT LIKE 'qa\_%'
    AND p.proname = 'admissao_qualificacao_cadastral'
    AND pg_get_functiondef(p.oid) !~* '(tenant_id|auth\.uid\(\)|get_user_tenant_id|is_superadmin|has_minimum_role)';

  RAISE NOTICE 'Conferência: ISOL-006 rotinas sensíveis abertas ao anônimo = % (esperado 0); ISOL-008 qualificacao sem reamarrar = % (esperado 0).',
    v_anon, v_sem_filtro;
END $confere$;
