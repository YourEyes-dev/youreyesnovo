-- ============================================================================
-- ENTREGA — ADM-101/102/103 · reconciliação de documentos de admissão
--            PARTE 2/2: BACKFILL (mexe em documento real) — HOMOLOGAÇÃO
--
-- Rode SÓ DEPOIS da PARTE 1 (objetos) conferida. Cole na HOMOLOGAÇÃO; depois de
-- conferido, o MESMO na PRODUÇÃO.
--
-- O QUE FAZ: guarda backup das linhas que vai tocar e roda a reconciliação
-- retroativa — preenche colaborador_id e pasta_id nos documentos de admissão
-- cujo dono JÁ existe como usuário. Documento de admissão EM CURSO (sem usuário
-- ainda) é deixado como está (legítimo). NÃO apaga nada; só preenche campos NULL.
--
-- SEGURANÇA:
--   • ALTERA documento real (UPDATE) → guarda ANTES as linhas do limbo numa
--     tabela de backup (produção sem PITR). Backup criado por EXECUTE (marca não
--     contígua → auto-RLS não liga). Desfazer: reaplicar colaborador_id/pasta_id
--     do backup (ou zerar de volta), a partir de backup_doc_reconc_20260928.
--   • Idempotente (rodar de novo reconcilia 0 e não recria o backup).
--   • O UPDATE dispara o gatilho versiona_documento? Não — ele só reage a
--     mudança de storage_path; aqui mudam colaborador_id/pasta_id. lock_timeout curto.
--
-- Ao fim, conferência: reconciliados, resíduo legítimo (em curso) e o que sobra
-- resolvível (esperado 0) + ADM-103 (esperado 0 onde os concluídos são usuários).
-- ============================================================================

SET lock_timeout = '10s';

-- ── 0) BACKUP das linhas em limbo com CPF (as candidatas ao UPDATE) ──────────
DO $bkp$
BEGIN
  IF to_regclass('public.backup_doc_reconc_20260928') IS NULL
     AND EXISTS (
       SELECT 1 FROM public.documentos d
        WHERE d.observacoes = 'Documento da admissão'
          AND (d.colaborador_id IS NULL OR d.pasta_id IS NULL)
          AND COALESCE(d.colaborador_cpf,'') <> '')
  THEN
    EXECUTE 'CREATE ' || 'TABLE public.backup_doc_reconc_20260928 AS
      SELECT d.* FROM public.documentos d
       WHERE d.observacoes = ''Documento da admissão''
         AND (d.colaborador_id IS NULL OR d.pasta_id IS NULL)
         AND COALESCE(d.colaborador_cpf,'''') <> ''''';
    RAISE NOTICE 'ADM-reconc: backup das linhas em limbo em backup_doc_reconc_20260928.';
  END IF;
END $bkp$;

-- ── 1) RECONCILIAÇÃO RETROATIVA (todos os tenants) ───────────────────────────
DO $run$
DECLARE v_res jsonb;
BEGIN
  v_res := public.reconciliar_documentos_colaborador(NULL, NULL);
  RAISE NOTICE 'ADM-reconc: %', v_res::text;
END $run$;

-- ════════════════════ CONFERÊNCIA (única) ════════════════════════════════════
-- Esperado: "resolvível restante" = 0 e "ADM-103 restante" = 0 (onde os
-- concluídos são usuários). "em curso (legítimo)" pode ser > 0 — não é falha.
WITH docs_adm AS MATERIALIZED (
  SELECT * FROM public.documentos WHERE observacoes = 'Documento da admissão'
),
conf AS MATERIALIZED (
  SELECT 1 AS ord, 'ADM-101/102 · resolvível ainda no limbo (ideal 0)'::text AS item,
         (SELECT count(*) FROM docs_adm d
           WHERE (d.colaborador_id IS NULL OR d.pasta_id IS NULL)
             AND COALESCE(d.colaborador_cpf,'') <> ''
             AND EXISTS (SELECT 1 FROM public.usuarios_base ub
                          WHERE ub.tenant_id = d.tenant_id
                            AND regexp_replace(COALESCE(ub.cpf,''),'[^0-9]','','g')
                                = regexp_replace(COALESCE(d.colaborador_cpf,''),'[^0-9]','','g')
                            AND COALESCE(ub.status::text,'ativo') <> 'excluido')) AS n
  UNION ALL
  SELECT 2, 'ADM-101/102 · em curso, sem usuário (legítimo — pode ser > 0)',
         (SELECT count(*) FROM docs_adm d
           WHERE (d.colaborador_id IS NULL OR d.pasta_id IS NULL)
             AND COALESCE(d.colaborador_cpf,'') <> ''
             AND NOT EXISTS (SELECT 1 FROM public.usuarios_base ub
                              WHERE ub.tenant_id = d.tenant_id
                                AND regexp_replace(COALESCE(ub.cpf,''),'[^0-9]','','g')
                                    = regexp_replace(COALESCE(d.colaborador_cpf,''),'[^0-9]','','g')
                                AND COALESCE(ub.status::text,'ativo') <> 'excluido'))
  UNION ALL
  SELECT 3, 'ADM-103 · admissões concluídas ainda no limbo (ideal 0)',
         (SELECT count(DISTINCT a.id)
            FROM public.admissoes a
            JOIN docs_adm d ON d.colaborador_cpf = a.cpf AND d.tenant_id = a.tenant_id
           WHERE a.status='concluido' AND (d.colaborador_id IS NULL OR d.pasta_id IS NULL))
)
SELECT item,
       CASE WHEN ord IN (1,3) AND n = 0 THEN 'ok'
            WHEN ord = 2 THEN n::text || ' (legítimo)'
            ELSE n::text || ' — CONFERIR' END AS situacao
FROM conf ORDER BY ord;
