-- ============================================================================
-- ISOL-006 / PRONT-ISOL-006 (critico de seguranca) — fechar ao ANONIMO as 9
-- rotinas sensiveis que o anon ainda consegue executar SEM LOGIN.
--
-- CAUSA RAIZ. No PostgreSQL toda funcao nasce com EXECUTE para PUBLIC, e o papel
-- anon (chave publica) herda de PUBLIC. Por isso "REVOKE ... FROM anon" sozinho
-- NAO fecha nada: a funcao continua executavel pelo anon atraves de PUBLIC. Duas
-- destas rotinas (ponto_registrar_compensacao_falta, ponto_dar_ciencia_compensacao_falta)
-- JA faziam REVOKE ALL FROM anon na migration de origem e mesmo assim seguem
-- abertas — e a prova de que o certo e revogar de PUBLIC. As outras foram criadas
-- depois das varreduras de 16/09 e 28/09 e nasceram abertas.
--
-- O QUE ESTA MIGRATION FAZ: para a LISTA EXPLICITA das 9 rotinas acusadas pelo
-- caso ISOL-006, revoga EXECUTE de PUBLIC e de anon (fecha ao anonimo) e devolve
-- a quem deve (usuario logado + papel de servico das edge functions). Escopo
-- fechado na lista nomeada de proposito: nao e uma varredura por regex, entao
-- NAO ha risco de derrubar um fluxo publico legitimo (admissao por link, portal
-- do parceiro, formulario de campanha e, em especial, o QUESTIONARIO PSICOSSOCIAL
-- publico `salvar_resposta_psicossocial`, que tem GRANT ... TO anon por desenho e
-- NAO esta nesta lista). Idempotente: rodar duas vezes nao quebra; nome que nao
-- existir no banco e so pulado (ex.: demo_dev_trilha_pool, que e drift so da
-- homologacao e nao existe no repositorio/producao).
--
-- Classificacao das 9 (todas: REVOKE de PUBLIC+anon; GRANT a authenticated+service_role):
--   ESCRITA (chamadas por usuario logado na tela — manter authenticated):
--     epi_devolver_entrega(uuid,text,text)                      SECURITY INVOKER
--     ponto_registrar_compensacao_falta(uuid,text,date,text)    SECURITY DEFINER
--     ponto_dar_ciencia_compensacao_falta(uuid,uuid,text)       SECURITY DEFINER
--     reconsiderar_marcacao_ponto(uuid,text)                    SECURITY DEFINER
--   GATILHO (disparadas pelo trigger, NAO precisam de EXECUTE de ninguem;
--            fechar ao anon e seguro e nao quebra o trigger):
--     admissoes_preserva_salario_mascarado()  profiles_protege_tenant()  audit_carimba_autor()
--   AUXILIAR (chamada de dentro de funcoes SECURITY DEFINER — nao em politica RLS):
--     ponto_vinculo_cobre_periodo(uuid,text,date,date)          SECURITY DEFINER
--   DRIFT (so na homologacao, corpo fora do repositorio — fechar ao anon e seguro;
--          revisar com a fundadora se deve existir / se e so demo):
--     demo_dev_trilha_pool(...)
--
-- SEGURANCA: so REVOKE/GRANT de EXECUTE — nao cria tabela, nao altera nem apaga
-- dado de cliente (logo nao precisa de backup de dados; a regra SEG-0006 vale
-- para alteracao de DADO, nao de privilegio). Sem lock relevante. Reversivel.
-- ============================================================================

SET lock_timeout = '10s';

DO $g$
DECLARE
  v_alvos CONSTANT text[] := ARRAY[
    'epi_devolver_entrega',
    'ponto_registrar_compensacao_falta',
    'ponto_dar_ciencia_compensacao_falta',
    'reconsiderar_marcacao_ponto',
    'admissoes_preserva_salario_mascarado',
    'profiles_protege_tenant',
    'audit_carimba_autor',
    'ponto_vinculo_cobre_periodo',
    'demo_dev_trilha_pool'
  ];
  v_nome text;
  c record;
  v_fechadas int := 0;
  v_lista text := '';
BEGIN
  FOREACH v_nome IN ARRAY v_alvos LOOP
    FOR c IN
      SELECT p.oid, p.proname, pg_get_function_identity_arguments(p.oid) AS args
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.prokind = 'f'
        AND p.proname = v_nome
    LOOP
      BEGIN
        EXECUTE format('REVOKE EXECUTE ON FUNCTION public.%I(%s) FROM PUBLIC, anon', c.proname, c.args);
        EXECUTE format('GRANT EXECUTE ON FUNCTION public.%I(%s) TO authenticated, service_role', c.proname, c.args);
        v_fechadas := v_fechadas + 1;
        v_lista := v_lista || CASE WHEN v_lista = '' THEN '' ELSE ', ' END
                           || c.proname || '(' || c.args || ')';
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'ISOL-006: nao foi possivel fechar %(%): %', c.proname, c.args, SQLERRM;
      END;
    END LOOP;
  END LOOP;
  RAISE NOTICE 'ISOL-006 (PRONT-ISOL-006): % rotina(s) fechadas ao anonimo: %', v_fechadas, v_lista;
END $g$;

-- ════════════════════ CONFERENCIA (esperado 'ok' — 0 abertas) ═════════════════
-- Mesmo criterio da rotina de QA qa_caso_isol_006(): funcao sensivel (corpo cita
-- tabela de dado de cliente) ainda executavel pelo anon, fora as publicas por
-- desenho. 0 = ISOL-006 passa.
WITH abertas AS MATERIALIZED (
  SELECT p.proname
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
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
SELECT 'ISOL-006 · rotinas sensiveis abertas ao anonimo (ideal 0)'::text AS item,
       CASE WHEN (SELECT count(*) FROM abertas) = 0 THEN 'ok'
            ELSE (SELECT count(*)::text FROM abertas) || ' — CONFERIR: '
                 || (SELECT string_agg(proname, ', ' ORDER BY proname) FROM abertas) END AS situacao;
