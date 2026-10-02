-- ============================================================================
-- DIAGNÓSTICO (SOMENTE LEITURA) — Barros: composição do banco jun/jul/ago
-- Colar no SQL Editor de PRODUÇÃO (projeto diayjpsrcerycycyaxst).
--
-- Mostra, por colaborador e competência, como o saldo está montado:
--   saldo_anterior + creditos - debitos - compensados = saldo_atual.
-- Serve para saber EXATAMENTE quanto lançar para zerar julho de cada um do
-- Grupo A, sem tocar no migrado (que está em junho). NÃO altera nada.
-- ============================================================================
WITH hhmm AS (
  SELECT
    bh.colaborador_nome,
    bh.competencia,
    bh.saldo_anterior_minutos AS sa,
    bh.creditos_minutos       AS cr,
    bh.debitos_minutos        AS db,
    bh.compensados_minutos    AS cp,
    bh.saldo_atual_minutos    AS st
  FROM public.ponto_banco_horas bh
  JOIN public.empresa_cadastro ec ON ec.id = bh.empresa_id
  WHERE ec.razao_social ILIKE '%BARROS & NUERNBERG ENG%'
    AND bh.competencia IN ('2026-06','2026-07','2026-08')
)
SELECT
  colaborador_nome,
  competencia,
  (CASE WHEN sa<0 THEN '-' ELSE '' END)||abs(sa)/60||'h'||lpad((abs(sa)%60)::text,2,'0') AS saldo_anterior,
  (CASE WHEN cr<0 THEN '-' ELSE '' END)||abs(cr)/60||'h'||lpad((abs(cr)%60)::text,2,'0') AS creditos,
  (CASE WHEN db<0 THEN '-' ELSE '' END)||abs(db)/60||'h'||lpad((abs(db)%60)::text,2,'0') AS debitos,
  (CASE WHEN cp<0 THEN '-' ELSE '' END)||abs(cp)/60||'h'||lpad((abs(cp)%60)::text,2,'0') AS compensados,
  (CASE WHEN st<0 THEN '-' ELSE '' END)||abs(st)/60||'h'||lpad((abs(st)%60)::text,2,'0') AS saldo_atual,
  st AS saldo_atual_min
FROM hhmm
ORDER BY colaborador_nome, competencia;
