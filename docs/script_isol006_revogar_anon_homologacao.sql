-- ============================================================================
-- ENTREGA — ISOL-006 · fechar rotinas sensíveis abertas ao anônimo — HOMOLOGAÇÃO
--
-- Cole no SQL Editor da HOMOLOGAÇÃO; depois de conferido, o MESMO na PRODUÇÃO.
--
-- ISOL-006 voltou a acusar 5 rotinas que tocam dado de cliente executáveis pelo
-- anônimo. No PostgreSQL toda função nasce com EXECUTE para PUBLIC (o anon herda),
-- então rotina NOVA criada depois da última varredura (16/09 e 28/09) reabre o
-- flanco. A correção é a MESMA varredura genérica e idempotente: revoga de PUBLIC
-- e de anon o que ainda está aberto e devolve a quem deve (usuário logado + papel
-- de serviço das edge functions). A lista de PERMITIDOS é idêntica à da rotina de
-- QA — o que é público por desenho (rotinas *_by_token, portal do parceiro,
-- helpers de política) não é derrubado. O filtro has_function_privilege('anon',…)
-- faz tocar SÓ o que ainda está aberto; o já fechado não reentra.
--
-- SEGURANÇA: só REVOKE/GRANT — não cria tabela, não apaga dado, sem lock
-- relevante. Idempotente.
-- ============================================================================

SET lock_timeout = '10s';

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

-- ════════════════════ CONFERÊNCIA (esperado 'ok' — 0 abertas) ═════════════════
WITH abertas AS MATERIALIZED (
  SELECT p.proname
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.prokind = 'f' AND p.proname NOT LIKE 'qa\_%'
    AND p.proname NOT IN (
      'get_admissao_by_token','get_admissao_documentos_by_token','update_admissao_documento_by_token',
      'update_admissao_foto_by_token','finalizar_admissao_by_token','ensure_admissao_documentos_by_token',
      'parceiro_meu_portal','parceiro_estagio_tenant','validar_cpf_colaborador_campanha',
      'get_user_tenant_id','current_user_tenant_id','user_tenant_ids','has_tenant_access',
      'user_has_empresa_vinculo','get_current_user_tipo','user_can_access_storage_object')
    AND has_function_privilege('anon', p.oid, 'EXECUTE')
    AND pg_get_functiondef(p.oid) ~* '(usuarios_base|perfis_acesso|perfil_permissoes|perfil_excecoes|usuario_perfil_vinculos|profiles|admissoes|atestados)'
)
SELECT 'ISOL-006 · rotinas sensíveis abertas ao anônimo (ideal 0)'::text AS item,
       CASE WHEN (SELECT count(*) FROM abertas) = 0 THEN 'ok'
            ELSE (SELECT count(*)::text FROM abertas) || ' — CONFERIR' END AS situacao;
