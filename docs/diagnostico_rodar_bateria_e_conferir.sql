-- ============================================================================
-- RODAR A BATERIA DO MOTOR E CONFERIR OS CASOS-ALVO — direto no SQL Editor
--
-- Use quando o botão "Rodar bateria" da tela não estiver registrando execução
-- nova (a tela pode não atualizar a lista; isto roda e mostra o resultado na
-- hora, gravando a execução do mesmo jeito que o botão).
--
-- Roda no CERCADO (tenant qa-sandbox): não cria, altera nem lê dado de cliente.
-- Leva ~40-60s (784 casos). Cole INTEIRO no SQL Editor da HOMOLOGAÇÃO.
-- O editor mostra só o ÚLTIMO resultado — que é o resumo + os casos-alvo.
-- ============================================================================

-- 1) Roda a bateria inteira (todos os módulos). Grava em qa_execucoes/qa_resultados.
SELECT public.qa_rodar_bateria('manual', NULL);

-- 2) Resumo da última execução + situação dos casos que mexemos nesta rodada.
WITH ult AS (
  SELECT id, total, passou, falhou, erro, nao_implementado
    FROM public.qa_execucoes
   ORDER BY iniciada_em DESC
   LIMIT 1
)
SELECT '=RESUMO='::text AS codigo,
       format('total=%s · passou=%s · falhou=%s · erro=%s · sem_rotina=%s',
              total, passou, falhou, erro, nao_implementado) AS situacao,
       ''::text AS detalhe
  FROM ult
UNION ALL
SELECT r.codigo,
       r.situacao::text,
       left(COALESCE(NULLIF(r.obtido,''), r.erro_tecnico, ''), 160) AS detalhe
  FROM public.qa_resultados r
  JOIN ult ON ult.id = r.execucao_id
 WHERE r.codigo IN ('PONTO-402','MKY-063','MKY-123','ISOL-005','ISOL-006',
                    'ADM-103','DESL-065','AFAST-021')
 ORDER BY codigo;
