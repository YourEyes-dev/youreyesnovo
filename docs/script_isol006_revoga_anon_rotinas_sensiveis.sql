-- ============================================================================
-- ENTREGA — ISOL-006 / PRONT-ISOL-006 · fechar ao ANONIMO 9 rotinas sensiveis
--
-- Aplicacao: primeiro na HOMOLOGACAO (esteira "homologacao-aplicar-script" via
-- psql, ou colado no SQL Editor da homologacao); depois de conferido, o MESMO
-- na PRODUCAO (SQL Editor da producao, gesto manual da fundadora). A producao
-- NAO e tocada por esteira.
--
-- CAUSA RAIZ. No PostgreSQL toda funcao nasce com EXECUTE para PUBLIC, e o papel
-- anon (chave publica) herda de PUBLIC. "REVOKE ... FROM anon" sozinho NAO fecha:
-- a funcao segue executavel pelo anon via PUBLIC. Duas destas rotinas ja faziam
-- REVOKE ALL FROM anon na origem e mesmo assim seguem abertas — prova de que o
-- certo e revogar de PUBLIC. As demais nasceram abertas apos as varreduras
-- anteriores (funcao nova reabre o flanco).
--
-- O QUE FAZ: para a LISTA EXPLICITA das 9 rotinas acusadas pelo ISOL-006, revoga
-- EXECUTE de PUBLIC e de anon e devolve a authenticated + service_role (usuario
-- logado + papel de servico das edge functions). Escopo fechado na lista nomeada:
-- NAO e varredura por regex, entao NAO derruba fluxo publico legitimo. Em especial
-- o QUESTIONARIO PSICOSSOCIAL publico (salvar_resposta_psicossocial, com GRANT TO
-- anon por desenho) NAO esta na lista e segue acessivel sem login.
--
-- As 9 (todas: REVOKE PUBLIC+anon; GRANT authenticated+service_role):
--   ESCRITA (chamadas pelo usuario logado — manter authenticated):
--     epi_devolver_entrega, ponto_registrar_compensacao_falta,
--     ponto_dar_ciencia_compensacao_falta, reconsiderar_marcacao_ponto
--   GATILHO (so disparadas pelo trigger; fechar ao anon nao quebra o trigger):
--     admissoes_preserva_salario_mascarado, profiles_protege_tenant, audit_carimba_autor
--   AUXILIAR (chamada de dentro de funcoes SECURITY DEFINER, nao de politica RLS):
--     ponto_vinculo_cobre_periodo
--   DRIFT (so na homologacao, corpo fora do repositorio — revisar com a fundadora
--          se deve existir / se e so demo; fechar ao anon e seguro):
--     demo_dev_trilha_pool
--
-- SEGURANCA: so REVOKE/GRANT de EXECUTE — nao cria tabela (sem pegadinha do
-- auto-RLS do editor), nao altera nem apaga DADO de cliente (logo sem backup de
-- dados; SEG-0006 vale para alteracao de dado, nao de privilegio). Idempotente.
-- Reversivel: para desfazer um item, GRANT EXECUTE ... TO PUBLIC (reabre o anon;
-- so em rollback consciente, pois reintroduz a exposicao).
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
