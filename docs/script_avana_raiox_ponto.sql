-- ============================================================================
-- RAIO-X DO PONTO — AVANA  (SOMENTE LEITURA — não altera nada)
-- Cole INTEIRO no SQL Editor de PRODUÇÃO, sozinho, e rode. Retorna 1 tabela.
-- Para analisar outro mês, troque 'comp' no bloco params abaixo.
-- Empresa SEM banco de horas: o esperado é tem_regime = sem_regime em todos.
-- ============================================================================
WITH params AS (
  SELECT '2026-09'::text AS comp                 -- << competência a conferir/fechar
),
alvo AS (
  SELECT id AS empresa_id, tenant_id, razao_social, nome_fantasia, cnpj, usa_controle_ponto
  FROM public.empresa_cadastro
  WHERE razao_social ILIKE '%avana%' OR nome_fantasia ILIKE '%avana%'
),
ativos AS (
  SELECT a.empresa_id, a.tenant_id, a.cpf, a.nome_completo, a.data_admissao,
         a.bate_ponto, a.dispensado_ponto, a.data_desligamento
  FROM public.admissoes a
  JOIN alvo t ON t.empresa_id = a.empresa_id
  WHERE COALESCE(a.inativo, false) = false
    AND a.status = 'concluido'
),
s0 AS (
  SELECT 0 AS ord, '0. EMPRESA'::text AS secao,
         (t.razao_social || COALESCE(' ('||t.nome_fantasia||')',''))::text AS item,
         ('CNPJ '||COALESCE(t.cnpj,'—')||' · usa_controle_ponto='||t.usa_controle_ponto
          ||' · empresa_id='||t.empresa_id||' · tenant='||t.tenant_id)::text AS detalhe
  FROM alvo t
),
s0b AS (
  SELECT 0, '0. EMPRESA'::text, '(nenhuma)'::text,
         'Nenhuma empresa com "avana" no nome/fantasia — me diga o nome ou CNPJ exato.'::text
  WHERE NOT EXISTS (SELECT 1 FROM alvo)
),
s1 AS (
  SELECT 1, '1. BANCO DE HORAS'::text, 'regime vigente (por colaborador)'::text,
         ('com_regime='||COUNT(*) FILTER (WHERE of.tem_regime)
          ||'  ·  sem_regime='||COUNT(*) FILTER (WHERE NOT of.tem_regime)
          ||'  (esperado: tudo em sem_regime)')::text
  FROM alvo t, params p,
       LATERAL public.ponto_banco_horas_oficial(t.tenant_id, p.comp, t.empresa_id) of
),
s2 AS (
  SELECT 2, '2. COLABORADORES ATIVOS'::text,
         av.nome_completo::text,
         ('CPF '||av.cpf||' · admissão '||COALESCE(av.data_admissao::text,'—')
          ||CASE WHEN av.bate_ponto THEN '' ELSE ' · NÃO bate ponto' END
          ||CASE WHEN av.dispensado_ponto THEN ' · dispensado (art.62)' ELSE '' END
          ||CASE WHEN av.data_desligamento IS NOT NULL THEN ' · DESLIGADO '||av.data_desligamento::text ELSE '' END)::text
  FROM ativos av
),
s2c AS (
  SELECT 2, '2. COLABORADORES ATIVOS'::text, 'TOTAL'::text,
         (COUNT(*)||' ativos · '||COUNT(*) FILTER (WHERE bate_ponto)||' batem ponto')::text
  FROM ativos
),
s3 AS (
  SELECT 3, '3. ESCALAS'::text,
         e.nome::text,
         ('jornada dia '||COALESCE(e.jornada_diaria_minutos,0)||'min · semana '||COALESCE(e.jornada_semanal_minutos,0)
          ||'min · tol.dia '||COALESCE(e.tolerancia_diaria_minutos,0)||'min · equalização '
          ||CASE WHEN COALESCE(e.equalizacao_mensal_ativa,false) THEN 'LIGADA' ELSE 'desligada' END
          ||' · '||CASE WHEN COALESCE(e.ativa,true) THEN 'ativa' ELSE 'INATIVA' END)::text
  FROM public.ponto_escalas e
  JOIN alvo t ON t.tenant_id = e.tenant_id AND (e.empresa_id = t.empresa_id OR e.empresa_id IS NULL)
),
s4 AS (
  SELECT 4, '4. ATRIBUIÇÃO DE ESCALA (vigente)'::text,
         COALESCE(at.colaborador_nome, at.colaborador_cpf)::text,
         ('escala '||COALESCE(e.nome,'?')||' · desde '||COALESCE(at.data_inicio::text,'—')
          ||CASE WHEN at.data_fim IS NOT NULL THEN ' até '||at.data_fim::text ELSE '' END)::text
  FROM public.ponto_escala_atribuicoes at
  JOIN alvo t ON t.tenant_id = at.tenant_id
  LEFT JOIN public.ponto_escalas e ON e.id = at.escala_id
  WHERE COALESCE(at.ativa,true) = true
    AND (at.data_fim IS NULL OR at.data_fim >= (SELECT (comp||'-01')::date FROM params))
),
s5 AS (
  SELECT 5, '5. FECHAMENTOS (últimos meses)'::text,
         f.competencia::text,
         ('status '||f.status||COALESCE(' · '||f.data_fechamento::text,'')
          ||COALESCE(' · colaboradores '||f.total_colaboradores,''))::text
  FROM public.ponto_fechamentos f
  JOIN alvo t ON t.tenant_id = f.tenant_id AND f.empresa_id = t.empresa_id
  WHERE f.competencia >= to_char((SELECT (comp||'-01')::date FROM params) - INTERVAL '7 months','YYYY-MM')
),
-- Pendências medidas INLINE (a função ponto_fechamento_pendencias_criticas está
-- quebrada em produção: referencia a coluna dia_curto_bloqueia_fechamento_minutos
-- que não existe lá). Conferimos aqui os dois bloqueios seguros.
s6a AS (
  SELECT 6, ('6. PENDÊNCIAS ('||p.comp||') — ajustes')::text,
         COALESCE(a.colaborador_nome, a.colaborador_cpf)::text,
         ('ajuste pendente em '||a.data_referencia::text||COALESCE(' · '||a.tipo_ajuste,''))::text
  FROM public.ponto_ajustes a
  JOIN alvo t ON t.tenant_id = a.tenant_id
  JOIN ativos av ON regexp_replace(av.cpf,'[^0-9]','','g')
                  = regexp_replace(COALESCE(a.colaborador_cpf,''),'[^0-9]','','g')
  JOIN params p ON true
  WHERE a.status = 'pendente'
    AND to_char(a.data_referencia,'YYYY-MM') = p.comp
),
s6b AS (
  SELECT 6, ('6. PENDÊNCIAS ('||p.comp||') — dias incompletos')::text,
         COALESCE(d.colaborador_nome, d.colaborador_cpf)::text,
         ('dia '||d.data::text||' · status '||COALESCE(d.status,''))::text
  FROM public.ponto_diario d
  JOIN alvo t ON t.tenant_id = d.tenant_id AND d.empresa_id = t.empresa_id
  JOIN params p ON true
  WHERE to_char(d.data,'YYYY-MM') = p.comp
    AND COALESCE(d.status,'') IN ('incompleto','ajuste_pendente')
),
s7 AS (
  SELECT 7, ('7. APURAÇÃO ('||p.comp||')')::text,
         COALESCE(r.colaborador_nome, r.colaborador_cpf)::text,
         ('trab '||COALESCE(r.total_trabalhado_min,0)||'min / prev '||COALESCE(r.total_jornada_prevista_min,0)||'min'
          ||' · faltas '||COALESCE(r.total_faltas,0)
          ||' · HE50 '||COALESCE(r.he_50_min,0)||'min · HE100 '||COALESCE(r.he_100_min,0)||'min'
          ||' · atrasos '||COALESCE(r.atrasos_min,0)||'min · saldo '||COALESCE(r.saldo_min,0)||'min'
          ||' · dias c/reg '||COALESCE(r.dias_com_registro,0))::text
  FROM alvo t, params p,
       LATERAL public.ponto_espelho_resumo_empresa(t.tenant_id, t.empresa_id, p.comp) r
)
SELECT secao, item, detalhe
FROM (
  SELECT * FROM s0   UNION ALL SELECT * FROM s0b
  UNION ALL SELECT * FROM s1
  UNION ALL SELECT * FROM s2  UNION ALL SELECT * FROM s2c
  UNION ALL SELECT * FROM s3
  UNION ALL SELECT * FROM s4
  UNION ALL SELECT * FROM s5
  UNION ALL SELECT * FROM s6a  UNION ALL SELECT * FROM s6b
  UNION ALL SELECT * FROM s7
) x
ORDER BY ord, item;
