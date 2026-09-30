-- ============================================================================
-- LIMPEZA — faltas materializadas de desligados (fora do vínculo)
-- Colar no SQL Editor de PRODUÇÃO (projeto diayjpsrcerycycyaxst).
-- PRÉ-REQUISITO: o script de "listas do mês respeitam o vínculo" já aplicado
-- (usa a função public.ponto_vinculo_cobre_periodo).
--
-- O QUE APAGA: linhas de ponto_diario com status='falta', SEM marcação
-- (entrada e saída nulas), cujo dia NÃO é coberto pelo vínculo do colaborador —
-- isto é, faltas geradas pela materialização depois da data de desligamento
-- (ou antes da admissão). Essas linhas já NÃO aparecem nas telas (filtradas por
-- vínculo); esta limpeza só as remove da base.
--
-- NÃO apaga: dia com marcação (entrada/saída), dia coberto pelo vínculo, nem
-- dia de quem não tem admissão efetivada (a regra de vínculo devolve "cobre").
--
-- SEGURANÇA: guarda um BACKUP das linhas antes de apagar (a produção não tem
-- PITR). A trava de exclusão de ponto é liberada pelo caminho controlado que a
-- própria trava prevê (flag de sessão, transação-local). Idempotente. Desfazer
-- no rodapé.
--
-- COMO USAR: rode o PASSO 1 sozinho e confira a contagem/amostra; se concordar,
-- rode o PASSO 2 (backup + exclusão + conferência).
-- ============================================================================


-- ---------------------------------------------------------------------------
-- PASSO 1 — CONFERIR (somente leitura): quanto e de quem será apagado
-- ---------------------------------------------------------------------------
SELECT
  count(*)                                  AS linhas_a_apagar,
  count(DISTINCT regexp_replace(COALESCE(pd.colaborador_cpf,''),'[^0-9]','','g')) AS colaboradores,
  min(pd.data)                              AS primeiro_dia,
  max(pd.data)                              AS ultimo_dia
FROM public.ponto_diario pd
WHERE pd.status = 'falta'
  AND pd.entrada IS NULL AND pd.saida IS NULL
  AND NOT public.ponto_vinculo_cobre_periodo(
        pd.tenant_id,
        regexp_replace(COALESCE(pd.colaborador_cpf,''),'[^0-9]','','g'),
        pd.data, pd.data);


-- ---------------------------------------------------------------------------
-- PASSO 2 — BACKUP + APAGAR (rode depois de conferir o PASSO 1)
-- ---------------------------------------------------------------------------

-- (a) Backup das linhas exatas que serão apagadas (mesmo filtro).
CREATE TABLE IF NOT EXISTS public.backup_faltas_desligados_20260930 AS
SELECT pd.*
FROM public.ponto_diario pd
WHERE pd.status = 'falta'
  AND pd.entrada IS NULL AND pd.saida IS NULL
  AND NOT public.ponto_vinculo_cobre_periodo(
        pd.tenant_id,
        regexp_replace(COALESCE(pd.colaborador_cpf,''),'[^0-9]','','g'),
        pd.data, pd.data);

-- (b) Libera o caminho controlado de exclusão (transação-local) e apaga
--     apenas as linhas salvas no backup (por id) — rápido e idêntico ao filtro.
SELECT set_config('app.allow_ponto_delete', 'true', true);

DELETE FROM public.ponto_diario pd
USING public.backup_faltas_desligados_20260930 b
WHERE pd.id = b.id;

-- (c) Conferência (o editor mostra só o último resultado): restou algo? (0) e
--     quantas linhas o backup guardou.
SELECT
  (SELECT count(*) FROM public.ponto_diario pd
     WHERE pd.status='falta' AND pd.entrada IS NULL AND pd.saida IS NULL
       AND NOT public.ponto_vinculo_cobre_periodo(
             pd.tenant_id,
             regexp_replace(COALESCE(pd.colaborador_cpf,''),'[^0-9]','','g'),
             pd.data, pd.data))                                  AS restantes_apos_limpeza,
  (SELECT count(*) FROM public.backup_faltas_desligados_20260930) AS linhas_no_backup;

-- ---------------------------------------------------------------------------
-- DESFAZER (se precisar restaurar): reinsere do backup as linhas apagadas.
--   SELECT set_config('app.allow_ponto_delete', 'true', true);
--   INSERT INTO public.ponto_diario
--   SELECT b.* FROM public.backup_faltas_desligados_20260930 b
--   WHERE NOT EXISTS (SELECT 1 FROM public.ponto_diario p WHERE p.id = b.id);
-- Depois de confiar no resultado, o backup pode ser removido:
--   DROP TABLE IF EXISTS public.backup_faltas_desligados_20260930;
-- ---------------------------------------------------------------------------
