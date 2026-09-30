-- ============================================================================
-- DIAGNÓSTICO (SOMENTE LEITURA) — escala e equalização da Kailaine
-- Seguro em PRODUÇÃO. Explica de onde vem o sábado de trabalho (26/09 = 216) e
-- como a equalização mensal está configurada para ela.
-- ============================================================================

-- 1) A escala vigente da Kailaine (config de equalização e sábado)
WITH ctx AS (
  SELECT b.tenant_id, regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g') AS cpf
  FROM public.ponto_banco_horas b
  WHERE b.colaborador_nome ILIKE '%Kailaine%'
  ORDER BY b.competencia DESC LIMIT 1
)
SELECT e.nome, e.tipo,
       e.equalizacao_mensal_ativa, e.sabado_util, e.domingo_util,
       e.jornada_diaria_minutos AS jorn_dia, e.jornada_semanal_minutos AS jorn_sem,
       e.jornada_mensal_minutos AS jorn_mes, e.carga_semanal_contratada_min AS carga_sem,
       e.dias_config, e.compensacoes_mensais
FROM public.ponto_escala_atribuicoes a
JOIN public.ponto_escalas e ON e.id = a.escala_id
JOIN ctx ON a.tenant_id = ctx.tenant_id
        AND regexp_replace(COALESCE(a.colaborador_cpf,''),'[^0-9]','','g') = ctx.cpf
WHERE COALESCE(a.ativa, true) = true
ORDER BY a.data_inicio DESC
LIMIT 1;

-- 2) O que o motor calcula de equalização para a escala dela em setembro
WITH ctx AS (
  SELECT b.tenant_id, regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g') AS cpf
  FROM public.ponto_banco_horas b
  WHERE b.colaborador_nome ILIKE '%Kailaine%'
  ORDER BY b.competencia DESC LIMIT 1
),
esc AS (
  SELECT a.escala_id
  FROM public.ponto_escala_atribuicoes a, ctx
  WHERE a.tenant_id = ctx.tenant_id
    AND regexp_replace(COALESCE(a.colaborador_cpf,''),'[^0-9]','','g') = ctx.cpf
    AND COALESCE(a.ativa, true) = true
  ORDER BY a.data_inicio DESC LIMIT 1
)
SELECT public.ponto_equalizacao_competencia(ctx.tenant_id, esc.escala_id, '2026-09') AS equalizacao_competencia_set
FROM ctx, esc;

-- 3) Jornada prevista em cada sábado de setembro (qual sábado a escala manda trabalhar)
WITH ctx AS (
  SELECT b.tenant_id, regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g') AS cpf
  FROM public.ponto_banco_horas b
  WHERE b.colaborador_nome ILIKE '%Kailaine%'
  ORDER BY b.competencia DESC LIMIT 1
)
SELECT g.d::date AS sabado,
       (SELECT j.jornada_min FROM public.ponto_jornada_do_dia(ctx.tenant_id, ctx.cpf, NULL, g.d::date) j) AS jornada_prevista
FROM ctx
CROSS JOIN generate_series(DATE '2026-09-05', DATE '2026-09-26', INTERVAL '7 days') g(d)
ORDER BY g.d;
