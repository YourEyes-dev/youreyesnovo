-- ============================================================================
-- CONFERÊNCIA OFICIAL DO BANCO — SUDOMED (somente leitura)
-- Colar no SQL Editor de PRODUÇÃO (projeto diayjpsrcerycycyaxst).
-- NÃO altera nada. Mostra, por pessoa e por mês (julho e agosto/2026):
--   - SALDO OFICIAL = o que o sistema recalcula AO VIVO (da marcação/escala);
--   - GRAVADO       = o que está salvo na tabela do banco;
--   - DIVERGÊNCIA   = diferença entre os dois (se ≠ 0, o gravado está desatualizado).
-- Serve para descobrir de ONDE vêm os números do RH e qual é o saldo real a zerar.
-- ============================================================================
WITH emp AS MATERIALIZED (
  SELECT id, tenant_id, razao_social
  FROM public.empresa_cadastro
  WHERE regexp_replace(COALESCE(cnpj,''),'[^0-9]','','g')
        IN ('26114701000145','31219374000126','41085456000189','41085456000260')
),
comps(competencia) AS (VALUES ('2026-06'),('2026-07'),('2026-08'),('2026-09'),('2026-10'))
SELECT
  e.razao_social AS empresa,
  o.colaborador_nome AS colaborador,
  c.competencia,
  (CASE WHEN o.saldo_atual_min<0 THEN '-' ELSE '' END)
    ||(abs(o.saldo_atual_min)/60)||'h'||lpad((abs(o.saldo_atual_min)%60)::text,2,'0')
    AS saldo_oficial,
  (CASE WHEN (o.saldo_atual_min - o.divergencia_min)<0 THEN '-' ELSE '' END)
    ||(abs(o.saldo_atual_min - o.divergencia_min)/60)||'h'||lpad((abs(o.saldo_atual_min - o.divergencia_min)%60)::text,2,'0')
    AS gravado,
  (CASE WHEN o.divergencia_min<0 THEN '-' ELSE '' END)
    ||(abs(o.divergencia_min)/60)||'h'||lpad((abs(o.divergencia_min)%60)::text,2,'0')
    AS divergencia,
  o.fonte,
  o.tem_regime
FROM emp e
CROSS JOIN comps c
, LATERAL public.ponto_banco_horas_oficial(e.tenant_id, c.competencia, e.id, NULL) o
ORDER BY e.razao_social, o.colaborador_nome, c.competencia;
