-- ============================================================================
-- NATIELI — raio-x diário de agosto e setembro (somente leitura)
-- Colar no SQL Editor de PRODUÇÃO (projeto diayjpsrcerycycyaxst).
-- NÃO altera nada. Mostra, dia a dia: o que ela TRABALHOU, a JORNADA PREVISTA
-- que o sistema usou naquele dia, o SALDO do dia e se é dia de EQUALIZAÇÃO.
-- Objetivo: ver se AGOSTO foi calculado contra 44h (escala antiga) e qual o
-- saldo real do mês respeitando a escala de cada período.
-- ============================================================================
WITH tn AS MATERIALIZED (
  SELECT DISTINCT tenant_id
  FROM public.empresa_cadastro
  WHERE regexp_replace(COALESCE(cnpj,''),'[^0-9]','','g')
        IN ('26114701000145','31219374000126','41085456000189','41085456000260')
),
pes AS MATERIALIZED (
  SELECT regexp_replace(COALESCE(a.colaborador_cpf,''),'[^0-9]','','g') AS cpf
  FROM public.ponto_escala_atribuicoes a
  WHERE a.tenant_id IN (SELECT tenant_id FROM tn)
    AND a.colaborador_nome ILIKE '%natiele%'
  LIMIT 1
),
dias AS (
  SELECT '2026-08' AS mes, d.*
  FROM tn, pes, LATERAL public.ponto_saldo_dias_competencia(tn.tenant_id, pes.cpf, '2026-08') d
  UNION ALL
  SELECT '2026-09' AS mes, d.*
  FROM tn, pes, LATERAL public.ponto_saldo_dias_competencia(tn.tenant_id, pes.cpf, '2026-09') d
)
SELECT
  mes,
  dia::text AS dia,
  to_char(dia,'Dy') AS semana,
  COALESCE(entrada::text,'--') AS entrada,
  COALESCE(saida::text,'--')   AS saida,
  (trabalhado_min/60)||'h'||lpad((trabalhado_min%60)::text,2,'0') AS trabalhado,
  (jornada_min/60)||'h'||lpad((jornada_min%60)::text,2,'0')       AS previsto,
  (CASE WHEN saldo_min<0 THEN '-' ELSE '' END)||(abs(saldo_min)/60)||'h'||lpad((abs(saldo_min)%60)::text,2,'0') AS saldo_dia,
  CASE WHEN equalizacao THEN 'EQUALIZA' ELSE '' END AS equaliza,
  0 AS ord
FROM dias
UNION ALL
SELECT
  mes, 'TOTAL '||mes, '', '', '',
  (sum(trabalhado_min)/60)||'h'||lpad((sum(trabalhado_min)%60)::text,2,'0'),
  (sum(jornada_min)/60)||'h'||lpad((sum(jornada_min)%60)::text,2,'0'),
  (CASE WHEN sum(saldo_min)<0 THEN '-' ELSE '' END)||(abs(sum(saldo_min))/60)||'h'||lpad((abs(sum(saldo_min))%60)::text,2,'0'),
  '', 1
FROM dias
GROUP BY mes
ORDER BY mes, ord, dia;
