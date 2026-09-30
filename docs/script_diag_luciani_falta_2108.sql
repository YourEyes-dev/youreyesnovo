-- ============================================================================
-- DIAGNÓSTICO (SOMENTE LEITURA) — Luciani, ausência de 21/08/2026
-- Seguro em PRODUÇÃO. Mostra, dia a dia de agosto, o que o sistema entende do
-- 21/08: existe linha? qual status (falta / justificado / regular)? qual a
-- jornada prevista (21/08 é dia útil para a escala dela)? qual o saldo do dia?
-- E o total de faltas do mês. Assim sabemos se a ausência está sendo CONTADA
-- como falta (para a folha descontar) ou passou batida.
-- ============================================================================

WITH ctx AS (
  SELECT b.tenant_id, b.empresa_id
  FROM public.ponto_banco_horas b
  WHERE regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g') = '11762645912'
  ORDER BY b.competencia DESC LIMIT 1
)
SELECT
  g.d::date AS dia,
  to_char(g.d::date,'Dy') AS semana,
  d.status,
  d.tipo_dia,
  d.entrada, d.saida,
  (SELECT j.jornada_min
     FROM public.ponto_jornada_do_dia(ctx.tenant_id, '11762645912', NULL, g.d::date) j) AS jornada_prevista,
  (SELECT s.saldo_min
     FROM public.ponto_saldo_dias_competencia(ctx.tenant_id, '11762645912', '2026-08') s
     WHERE s.dia = g.d::date) AS saldo_dia,
  (SELECT s.protegido
     FROM public.ponto_saldo_dias_competencia(ctx.tenant_id, '11762645912', '2026-08') s
     WHERE s.dia = g.d::date) AS protegido
FROM ctx
CROSS JOIN generate_series(DATE '2026-08-18', DATE '2026-08-24', INTERVAL '1 day') g(d)
LEFT JOIN public.ponto_diario d
  ON d.tenant_id = ctx.tenant_id
 AND regexp_replace(COALESCE(d.colaborador_cpf,''),'[^0-9]','','g') = '11762645912'
 AND d.data = g.d::date
ORDER BY g.d;

-- Total de faltas de agosto (o que a folha usaria) + há afastamento/férias no dia?
WITH ctx AS (
  SELECT b.tenant_id FROM public.ponto_banco_horas b
  WHERE regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g') = '11762645912'
  ORDER BY b.competencia DESC LIMIT 1
)
SELECT
  (SELECT count(*) FROM public.ponto_diario d, ctx
     WHERE d.tenant_id=ctx.tenant_id
       AND regexp_replace(COALESCE(d.colaborador_cpf,''),'[^0-9]','','g')='11762645912'
       AND to_char(d.data,'YYYY-MM')='2026-08' AND d.status='falta') AS faltas_agosto,
  EXISTS (SELECT 1 FROM public.afastamentos af, ctx
     WHERE af.tenant_id=ctx.tenant_id
       AND regexp_replace(COALESCE(af.colaborador_cpf,''),'[^0-9]','','g')='11762645912'
       AND af.data_inicio <= DATE '2026-08-21'
       AND COALESCE(af.data_fim,'infinity'::date) >= DATE '2026-08-21') AS afastada_em_2108;
