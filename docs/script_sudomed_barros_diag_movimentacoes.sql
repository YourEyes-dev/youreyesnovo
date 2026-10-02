-- ============================================================================
-- DIAGNÓSTICO (SOMENTE LEITURA) — Barros: movimentações MANUAIS jun/jul/ago
-- Colar no SQL Editor de PRODUÇÃO (projeto diayjpsrcerycycyaxst).
--
-- Objetivo: ver as "liquidações lançadas por engano em agosto" (Grupo A) e
-- qualquer lançamento manual de junho/julho, ANTES de qualquer alteração.
-- Lista só o que NÃO é apuração (origem manual/liquidacao/migracao).
-- NÃO altera nada.
-- ============================================================================
SELECT
  bh.colaborador_nome,
  bh.competencia,
  mv.tipo,
  mv.minutos,
  (mv.minutos / 60) || 'h' || lpad((mv.minutos % 60)::text, 2, '0') AS hhmm,
  mv.origem,
  mv.data_referencia,
  mv.descricao,
  mv.created_at
FROM public.ponto_banco_horas_movimentacoes mv
JOIN public.ponto_banco_horas bh ON bh.id = mv.banco_horas_id
JOIN public.empresa_cadastro   ec ON ec.id = bh.empresa_id
WHERE ec.razao_social ILIKE '%BARROS & NUERNBERG ENG%'
  AND bh.competencia IN ('2026-06','2026-07','2026-08')
  AND COALESCE(mv.origem,'') NOT IN ('apuracao','apuracao_auto')
ORDER BY bh.colaborador_nome, bh.competencia, mv.data_referencia, mv.created_at;
