-- ============================================================================
-- DIAGNÓSTICO ADM-101/102/103/108 — passivo de documentos de admissão
--                                    (SOMENTE LEITURA)
--
-- NÃO altera nada. Mede, no ambiente onde é colado, o tamanho do passivo e se as
-- funções/gatilhos de reconciliação já existem — para decidir com segurança o
-- reparo (que mexe em documento real e por isso exige backup antes).
--
-- Rode PRIMEIRO na HOMOLOGAÇÃO, depois na PRODUÇÃO — cada banco tem o seu estado.
--
-- Como ler:
--  • SEÇÃO 1 (objetos): 'presente' = já existe; 'FALTA' = o reparo precisa criar.
--  • SEÇÃO 2 (passivo): as contas EXATAS das auditorias ADM-101/102/103/108.
--    Ideal para verde = 0 em cada.
--  • SEÇÃO 3 (resolubilidade): dos documentos no limbo, quantos VÃO resolver
--    (CPF casa um usuário) e quantos são admissão EM CURSO (sem usuário ainda —
--    ficam sem dono de forma legítima; enquanto existirem, ADM-101/102 não zeram,
--    e isso não é bug). ADM-103 só conta admissões CONCLUÍDAS, então tende a
--    zerar após o reparo.
-- ============================================================================

WITH
-- ── SEÇÃO 1 — objetos de reconciliação presentes? ───────────────────────────
obj AS MATERIALIZED (
  SELECT 10 AS ord, 'objetos'::text AS secao,
         'documento_pasta_do_colaborador (função)'::text AS metrica,
         CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='documento_pasta_do_colaborador') THEN 'presente' ELSE 'FALTA' END AS valor
  UNION ALL SELECT 11,'objetos','documento_resolver_dono_e_pasta (função)',
         CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='documento_resolver_dono_e_pasta') THEN 'presente' ELSE 'FALTA' END
  UNION ALL SELECT 12,'objetos','trg_documento_resolver_dono_e_pasta (gatilho documentos)',
         CASE WHEN EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_documento_resolver_dono_e_pasta' AND NOT tgisinternal) THEN 'presente' ELSE 'FALTA' END
  UNION ALL SELECT 13,'objetos','reconciliar_documentos_colaborador (função retroativa)',
         CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='reconciliar_documentos_colaborador') THEN 'presente' ELSE 'FALTA' END
  UNION ALL SELECT 14,'objetos','admissao_reconciliar_documentos (função)',
         CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='admissao_reconciliar_documentos') THEN 'presente' ELSE 'FALTA' END
  UNION ALL SELECT 15,'objetos','trg_admissao_reconciliar_documentos (gatilho admissoes)',
         CASE WHEN EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_admissao_reconciliar_documentos' AND NOT tgisinternal) THEN 'presente' ELSE 'FALTA' END
  UNION ALL SELECT 16,'objetos','reconciliar_documentos_admissao (função ADM-108)',
         CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='reconciliar_documentos_admissao') THEN 'presente' ELSE 'FALTA' END
),
-- ── SEÇÃO 2 — passivo (contas idênticas às auditorias) ──────────────────────
docs_adm AS MATERIALIZED (
  SELECT * FROM public.documentos WHERE observacoes = 'Documento da admissão'
),
passivo AS MATERIALIZED (
  SELECT 20 AS ord,'passivo'::text AS secao,
         'ADM-101/102 · total de documentos de admissão'::text AS metrica,
         (SELECT count(*) FROM docs_adm)::text AS valor
  UNION ALL SELECT 21,'passivo','ADM-101 · documentos SEM pasta_id (ideal 0)',
         (SELECT count(*) FROM docs_adm WHERE pasta_id IS NULL)::text
  UNION ALL SELECT 22,'passivo','ADM-102 · documentos SEM colaborador_id (ideal 0)',
         (SELECT count(*) FROM docs_adm WHERE colaborador_id IS NULL)::text
  UNION ALL SELECT 23,'passivo','ADM-103 · admissões CONCLUÍDAS com doc no limbo (ideal 0)',
         (SELECT count(DISTINCT a.id)
            FROM public.admissoes a
            JOIN docs_adm d ON d.colaborador_cpf = a.cpf AND d.tenant_id = a.tenant_id
           WHERE a.status='concluido' AND (d.colaborador_id IS NULL OR d.pasta_id IS NULL))::text
  UNION ALL SELECT 24,'passivo','ADM-108 · arquivos de admissão órfãos em Documentos (ideal 0)',
         (SELECT count(*) FROM public.admissao_documentos ad
           WHERE ad.arquivo_url IS NOT NULL AND btrim(ad.arquivo_url) <> ''
             AND NOT EXISTS (SELECT 1 FROM public.documentos d
                              WHERE d.storage_path = ad.arquivo_url AND d.tenant_id = ad.tenant_id))::text
),
-- ── SEÇÃO 3 — resolubilidade do limbo (101/102) ─────────────────────────────
-- Documento no limbo com CPF: casa algum usuário no tenant? Se sim, o reparo
-- resolve; se não, é admissão em curso (fica legítimo). Mesma escolha de dono da
-- função (colaborador primeiro, senão o mais antigo — aqui só EXISTS, não ordem).
limbo AS MATERIALIZED (
  SELECT d.id, d.tenant_id,
         regexp_replace(COALESCE(d.colaborador_cpf,''),'[^0-9]','','g') AS cpf
  FROM docs_adm d
  WHERE (d.colaborador_id IS NULL OR d.pasta_id IS NULL)
    AND COALESCE(d.colaborador_cpf,'') <> ''
),
resol AS MATERIALIZED (
  SELECT 30 AS ord,'resolubilidade'::text AS secao,
         'Limbo com CPF (candidatos ao reparo)'::text AS metrica,
         (SELECT count(*) FROM limbo)::text AS valor
  UNION ALL SELECT 31,'resolubilidade','  destes: VÃO resolver (CPF casa um usuário)',
         (SELECT count(*) FROM limbo l WHERE EXISTS (
            SELECT 1 FROM public.usuarios_base ub
             WHERE ub.tenant_id = l.tenant_id
               AND regexp_replace(COALESCE(ub.cpf,''),'[^0-9]','','g') = l.cpf
               AND COALESCE(ub.status::text,'ativo') <> 'excluido'))::text
  UNION ALL SELECT 32,'resolubilidade','  destes: admissão EM CURSO (sem usuário — ficam, legítimo)',
         (SELECT count(*) FROM limbo l WHERE NOT EXISTS (
            SELECT 1 FROM public.usuarios_base ub
             WHERE ub.tenant_id = l.tenant_id
               AND regexp_replace(COALESCE(ub.cpf,''),'[^0-9]','','g') = l.cpf
               AND COALESCE(ub.status::text,'ativo') <> 'excluido'))::text
  UNION ALL SELECT 33,'resolubilidade','  limbo SEM CPF (não resolve por chave — triagem manual)',
         (SELECT count(*) FROM docs_adm d
           WHERE (d.colaborador_id IS NULL OR d.pasta_id IS NULL)
             AND COALESCE(d.colaborador_cpf,'') = '')::text
)
SELECT secao, metrica, valor FROM (
  SELECT * FROM obj
  UNION ALL SELECT * FROM passivo
  UNION ALL SELECT * FROM resol
) t ORDER BY ord;
