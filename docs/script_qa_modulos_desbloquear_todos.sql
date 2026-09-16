-- ============================================================================
-- ENTREGA — Libera TODOS os modulos ainda bloqueados na Documentacao de Testes
--
-- O status 'bloqueado' travava a documentacao de um modulo enquanto suas regras
-- de negocio estavam em alteracao (cadeado na tela, botao "Novo caso" desligado).
-- As regras estabilizaram; o usuario confirmou que os modulos restantes estao
-- prontos. Este script libera qualquer modulo que ainda esteja 'bloqueado', com
-- um status honesto derivado da propria cobertura:
--   . tem casos documentados .............. documentado
--   . sem casos, mas e um bloco (tem filhos) em_andamento
--   . sem casos e folha .................... nao_iniciado
-- e limpa o motivo_bloqueio. Nao toca em 'dispensado' nem em nenhum outro status.
--
-- ONDE COLAR
-- No SQL Editor da PRODUCAO (diayjpsrcerycycyaxst), quando aprovado. E a mesma
-- mudanca que ja foi para o ambiente de teste pela esteira.
--
-- SEGURANCA
-- Antes de alterar, guarda as linhas afetadas numa tabela de backup do dia (a
-- producao nao tem PITR). O desfazer esta no comentario final. Idempotente:
-- rodar de novo nao acha mais nada 'bloqueado'. So mexe no cadeado; nao cria
-- nem apaga modulo, nem toca em caso de teste.
-- ============================================================================

SET lock_timeout = '10s';

-- 1) Backup das linhas que serao alteradas (so os bloqueados de hoje).
CREATE TABLE IF NOT EXISTS backup_qa_modulos_desbloqueio_20260916 AS
SELECT * FROM public.qa_modulos WHERE status_doc = 'bloqueado';

-- 2) Libera todos os bloqueados, com status derivado da cobertura.
DO $desbloq$
DECLARE v_antes int; v_depois int;
BEGIN
  SELECT count(*) INTO v_antes FROM public.qa_modulos WHERE status_doc = 'bloqueado';

  UPDATE public.qa_modulos m
  SET status_doc = CASE
        WHEN EXISTS (SELECT 1 FROM public.qa_casos_teste c WHERE c.modulo_id = m.id)
             THEN 'documentado'
        WHEN EXISTS (SELECT 1 FROM public.qa_modulos ch WHERE ch.parent_id = m.id)
             THEN 'em_andamento'
        ELSE 'nao_iniciado'
      END::public.qa_status_doc,
      motivo_bloqueio = NULL
  WHERE m.status_doc = 'bloqueado';

  SELECT count(*) INTO v_depois FROM public.qa_modulos WHERE status_doc = 'bloqueado';
  RAISE NOTICE 'Desbloqueio de modulos QA: bloqueados antes=%, depois=% (esperado 0).', v_antes, v_depois;
END $desbloq$;

-- 3) Conferencia (o editor mostra so o ultimo resultado): distribuicao por status
--    e o numero de modulos ainda bloqueados (esperado 0).
SELECT
  count(*) FILTER (WHERE status_doc = 'bloqueado')    AS ainda_bloqueados,
  count(*) FILTER (WHERE status_doc = 'documentado')  AS documentado,
  count(*) FILTER (WHERE status_doc = 'em_andamento') AS em_andamento,
  count(*) FILTER (WHERE status_doc = 'nao_iniciado') AS nao_iniciado,
  count(*) FILTER (WHERE status_doc = 'dispensado')   AS dispensado,
  count(*)                                             AS total_modulos
FROM public.qa_modulos;

-- ----------------------------------------------------------------------------
-- DESFAZER (se necessario), enquanto a tabela de backup existir:
--   UPDATE public.qa_modulos m
--   SET status_doc = b.status_doc, motivo_bloqueio = b.motivo_bloqueio
--   FROM backup_qa_modulos_desbloqueio_20260916 b
--   WHERE m.id = b.id;
-- ----------------------------------------------------------------------------
