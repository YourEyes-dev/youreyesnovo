-- ============================================================================
-- ISOL-006 — re-varredura das rotinas sensíveis abertas ao anônimo
--
-- Toda função nasce com EXECUTE para PUBLIC (o anon herda). Funções criadas
-- DEPOIS da varredura de 28/09 (20260928122918) reabriram o flanco — inclusive
-- as de reconciliação de documentos desta leva (20260928195238, cujo corpo cita
-- usuarios_base) e cargo_perfil_ideal_por_mapa (20260928124216, cita admissoes).
-- Esta migration re-roda a MESMA varredura genérica e idempotente: fecha só o
-- que o anon ainda pode executar e que toca dado sensível, preservando a lista
-- de PERMITIDOS (idêntica à da rotina de QA ISOL-006).
--
-- Observação de processo: enquanto cada migration que cria função sensível não
-- revogar de anon no próprio arquivo, o padrão vai reincidir. Uma re-varredura
-- fecha o estado atual; a solução estrutural é revogar na origem.
-- ============================================================================

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
  RAISE NOTICE 'ISOL-006 (re-varredura): % rotina(s) fechadas ao anonimo: %', v_n, v_lista;
END $anon$;
