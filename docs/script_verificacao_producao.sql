-- ============================================================================
-- VERIFICAÇÃO (somente leitura) — a produção está de acordo com as correções?
--
-- Cole no SQL Editor da PRODUÇÃO e execute. NÃO altera nada, NÃO liga o modo de
-- teste, NÃO roda a bateria: é só introspecção do banco (existe a função? a
-- trava está lá? o anônimo perdeu o EXECUTE?). Por isso é seguro rodar na
-- produção a qualquer momento e quantas vezes quiser.
--
-- O comportamento de cada correção já foi provado na homologação (bateria
-- verde). Aqui só confirmamos que os MESMOS objetos chegaram à produção.
--
-- Resultado esperado: todas as linhas com situacao = 'ok'.
--   'ok'        = a correção está presente
--   'CONFERIR'  = está diferente do esperado (a correção não chegou ou regrediu)
--   'AUSENTE'   = o objeto nem existe nesta base (avalie se deveria)
-- ============================================================================

WITH checagens AS MATERIALIZED (

  -- 1) Cerca revertida: as 2 tabelas multi-tenant por desenho SEM a trava
  SELECT 1 AS ord,
         'Cerca: marketplace_demanda_latente e parceiro_mrr_snapshots sem trava'::text AS item,
         ( (SELECT count(*) FROM pg_trigger tg
              JOIN pg_class c ON c.oid = tg.tgrelid
             WHERE tg.tgname = 'qa_guarda_cercado' AND NOT tg.tgisinternal
               AND c.relname IN ('marketplace_demanda_latente','parceiro_mrr_snapshots')) = 0 )::text AS ok

  UNION ALL
  -- 2) Cercas fechadas: nenhuma tabela com tenant_id sem a trava (fora as 2 exceções)
  SELECT 2,
         'Cercas fechadas: nenhuma tabela com tenant_id sem a trava (PONTO-270)',
         ( (SELECT count(*)
              FROM information_schema.columns col
              JOIN information_schema.tables tb
                ON tb.table_schema = col.table_schema AND tb.table_name = col.table_name
             WHERE col.table_schema = 'public' AND col.column_name = 'tenant_id'
               AND tb.table_type = 'BASE TABLE'
               AND col.table_name NOT LIKE 'qa\_%'
               AND col.table_name NOT IN ('marketplace_demanda_latente','parceiro_mrr_snapshots')
               AND NOT EXISTS (
                 SELECT 1 FROM pg_trigger tg
                  WHERE tg.tgname = 'qa_guarda_cercado'
                    AND tg.tgrelid = ('public.' || quote_ident(col.table_name))::regclass
                    AND NOT tg.tgisinternal)) = 0 )::text

  UNION ALL
  -- 3) ISOL-006: nenhuma rotina sensível executável pelo anônimo (fora as públicas por desenho)
  SELECT 3,
         'ISOL-006: nenhuma rotina sensível aberta ao anônimo',
         ( (SELECT count(*)
              FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public' AND p.prokind = 'f' AND p.proname NOT LIKE 'qa\_%'
               AND has_function_privilege('anon', p.oid, 'EXECUTE')
               AND pg_get_functiondef(p.oid) ~* '(usuarios_base|perfis_acesso|perfil_permissoes|perfil_excecoes|usuario_perfil_vinculos|profiles|admissoes|atestados)'
               AND p.proname NOT IN (
                 'get_admissao_by_token','get_admissao_documentos_by_token',
                 'update_admissao_documento_by_token','update_admissao_foto_by_token',
                 'finalizar_admissao_by_token','ensure_admissao_documentos_by_token',
                 'parceiro_meu_portal','parceiro_estagio_tenant','validar_cpf_colaborador_campanha',
                 'get_user_tenant_id','current_user_tenant_id','user_tenant_ids',
                 'has_tenant_access','user_has_empresa_vinculo','get_current_user_tipo',
                 'user_can_access_storage_object')) = 0 )::text

  UNION ALL
  -- 4) ISOL-008: admissao_qualificacao_cadastral reamarra o cliente
  SELECT 4,
         'ISOL-008: admissao_qualificacao_cadastral reamarra o cliente',
         CASE WHEN to_regprocedure('public.admissao_qualificacao_cadastral(uuid)') IS NULL
              THEN 'AUSENTE'
              ELSE (pg_get_functiondef('public.admissao_qualificacao_cadastral(uuid)'::regprocedure)
                    ~* '(auth\.uid\(\)|get_user_tenant_id|is_superadmin)')::text END

  UNION ALL
  -- 5) AFAST-001: afastamento_encerrar_vencidos aceita filtro de tenant
  SELECT 5,
         'AFAST-001: afastamento_encerrar_vencidos aceita filtro de tenant',
         (to_regprocedure('public.afastamento_encerrar_vencidos(uuid)') IS NOT NULL)::text

  UNION ALL
  -- 6) FER-002: qa_caso_fer_002 sem min(uuid)
  SELECT 6,
         'FER-002: qa_caso_fer_002 sem min(uuid)',
         CASE WHEN to_regprocedure('public.qa_caso_fer_002()') IS NULL
              THEN 'AUSENTE'
              ELSE (pg_get_functiondef('public.qa_caso_fer_002()'::regprocedure)
                    !~* 'min\s*\(\s*tabela_id')::text END
)
SELECT item,
       CASE ok WHEN 'true' THEN 'ok'
               WHEN 'false' THEN 'CONFERIR'
               ELSE ok END AS situacao
FROM checagens
ORDER BY ord;
