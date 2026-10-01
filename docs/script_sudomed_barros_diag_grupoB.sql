-- ============================================================================
-- DIAGNÓSTICO (SOMENTE LEITURA) — Barros Grupo B: linhas de banco (todas as
-- competências), para ver a duplicata da Tania e o trabalho de jun/jul.
-- Colar no SQL Editor de PRODUÇÃO. NÃO altera nada.
-- ============================================================================
SELECT
  bh.colaborador_nome,
  bh.colaborador_cpf,
  bh.competencia,
  bh.id AS banco_id,
  bh.saldo_anterior_minutos AS sa,
  bh.creditos_minutos AS cr,
  bh.debitos_minutos AS db,
  bh.compensados_minutos AS cp,
  bh.saldo_atual_minutos AS st,
  (SELECT count(*) FROM public.ponto_banco_horas_movimentacoes mv WHERE mv.banco_horas_id = bh.id) AS n_movs
FROM public.ponto_banco_horas bh
JOIN public.empresa_cadastro ec ON ec.id = bh.empresa_id
WHERE ec.razao_social ILIKE '%BARROS & NUERNBERG ENG%'
  AND (bh.colaborador_nome ILIKE '%Tania Mara%'
       OR bh.colaborador_nome ILIKE '%Kailaine%'
       OR bh.colaborador_nome ILIKE '%Natiele Cust%')
ORDER BY bh.colaborador_nome, bh.competencia, bh.saldo_atual_minutos;
