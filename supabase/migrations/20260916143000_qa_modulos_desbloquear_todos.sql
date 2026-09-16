-- =========================================================
-- QA — libera TODOS os modulos ainda bloqueados na Documentacao de Testes
--
-- O status 'bloqueado' foi usado enquanto as regras de negocio de um modulo
-- estavam em alteracao ("documentar agora eternizaria comportamento que vai
-- mudar"). O caso original foi o bloco Jornada & Rotina (seed de jul/2026);
-- parte dele ja foi liberada em 20260812120000. O usuario confirmou que os
-- modulos restantes estao prontos — as regras estabilizaram. Este arquivo
-- libera qualquer modulo que ainda esteja 'bloqueado', seja qual for, com um
-- status honesto derivado da propria cobertura:
--   · tem casos documentados .............. documentado
--   · sem casos, mas e um bloco (tem filhos) em_andamento
--   · sem casos e folha .................... nao_iniciado
-- e limpa o motivo_bloqueio em todos.
--
-- Nao mexe em modulos 'dispensado' (decisao explicita de nao documentar) nem
-- em nenhum outro status. So desfaz o cadeado.
--
-- Idempotente: rodar de novo nao acha mais nada 'bloqueado' e nao faz nada.
-- Generico de proposito: cada ambiente (teste, homologacao, producao) pode
-- ter um conjunto diferente de bloqueados; este UPDATE atende todos.
-- =========================================================

SET lock_timeout = '10s';

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

-- Conferencia
SELECT status_doc, count(*) AS modulos
FROM public.qa_modulos
GROUP BY status_doc
ORDER BY status_doc;
