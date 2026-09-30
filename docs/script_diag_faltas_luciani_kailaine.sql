-- ============================================================================
-- DIAGNÓSTICO (SOMENTE LEITURA) — mês completo
--   PARTE 1: Luciani — agosto/2026 (dia a dia, para conferir as 8 faltas)
--   PARTE 2: Kailaine — setembro/2026 (dia a dia) + sábado de EQUALIZAÇÃO
-- Seguro em PRODUÇÃO. Não altera nada. Rode e cole as duas saídas.
--
-- Colunas: status (falta/justificado/regular/atraso/incompleto), tipo_dia,
-- entrada/saida, jornada_prevista (0 = escala não prevê trabalho no dia),
-- saldo_dia, protegido, equalizacao (dia tratado como sábado de equalização).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- PARTE 1 — Luciani (CPF 117.626.459-12), agosto/2026 inteiro
-- ---------------------------------------------------------------------------
WITH ctx AS (
  SELECT b.tenant_id
  FROM public.ponto_banco_horas b
  WHERE regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g') = '11762645912'
  ORDER BY b.competencia DESC LIMIT 1
),
sal AS (
  SELECT s.* FROM ctx, public.ponto_saldo_dias_competencia(ctx.tenant_id, '11762645912', '2026-08') s
)
SELECT
  'Luciani' AS quem,
  g.d::date AS dia, to_char(g.d::date,'Dy') AS sem,
  d.status, d.tipo_dia, d.entrada, d.saida,
  (SELECT j.jornada_min FROM ctx, public.ponto_jornada_do_dia(ctx.tenant_id,'11762645912',NULL,g.d::date) j) AS jornada,
  sal.saldo_min AS saldo, sal.protegido AS prot, sal.equalizacao AS eq
FROM ctx
CROSS JOIN generate_series(DATE '2026-08-01', DATE '2026-08-31', INTERVAL '1 day') g(d)
LEFT JOIN public.ponto_diario d
  ON d.tenant_id=ctx.tenant_id
 AND regexp_replace(COALESCE(d.colaborador_cpf,''),'[^0-9]','','g')='11762645912'
 AND d.data=g.d::date
LEFT JOIN sal ON sal.dia = g.d::date
ORDER BY g.d;

-- ---------------------------------------------------------------------------
-- PARTE 2 — Kailaine (por nome), setembro/2026 inteiro
-- ---------------------------------------------------------------------------
WITH ctx AS (
  SELECT b.tenant_id, regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g') AS cpf,
         b.colaborador_nome
  FROM public.ponto_banco_horas b
  WHERE b.colaborador_nome ILIKE '%Kailaine%'
  ORDER BY b.competencia DESC LIMIT 1
),
sal AS (
  SELECT s.* FROM ctx, public.ponto_saldo_dias_competencia(ctx.tenant_id, ctx.cpf, '2026-09') s
)
SELECT
  ctx.colaborador_nome AS quem,
  g.d::date AS dia, to_char(g.d::date,'Dy') AS sem,
  d.status, d.tipo_dia, d.entrada, d.saida,
  (SELECT j.jornada_min FROM public.ponto_jornada_do_dia(ctx.tenant_id, ctx.cpf, NULL, g.d::date) j) AS jornada,
  sal.saldo_min AS saldo, sal.protegido AS prot, sal.equalizacao AS eq
FROM ctx
CROSS JOIN generate_series(DATE '2026-09-01', DATE '2026-09-30', INTERVAL '1 day') g(d)
LEFT JOIN public.ponto_diario d
  ON d.tenant_id=ctx.tenant_id
 AND regexp_replace(COALESCE(d.colaborador_cpf,''),'[^0-9]','','g')=ctx.cpf
 AND d.data=g.d::date
LEFT JOIN sal ON sal.dia = g.d::date
ORDER BY g.d;

-- ---------------------------------------------------------------------------
-- PARTE 2b — Kailaine: configuração do sábado de equalização em setembro
-- ---------------------------------------------------------------------------
WITH ctx AS (
  SELECT regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g') AS cpf, b.tenant_id
  FROM public.ponto_banco_horas b
  WHERE b.colaborador_nome ILIKE '%Kailaine%'
  ORDER BY b.competencia DESC LIMIT 1
)
SELECT pem.colaborador_nome, pem.competencia, pem.data_equalizacao,
       pem.total_equalizacao_min, (pem.art61_liberado_em IS NOT NULL) AS art61_liberado
FROM public.ponto_equalizacao_mensal pem, ctx
WHERE pem.tenant_id = ctx.tenant_id
  AND regexp_replace(COALESCE(pem.colaborador_cpf,''),'[^0-9]','','g') = ctx.cpf
  AND pem.competencia = '2026-09';
