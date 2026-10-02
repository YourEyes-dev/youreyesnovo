-- ============================================================================
-- RAIO-X AVANA — PARTE 2: classificação das pessoas (SOMENTE LEITURA)
-- Para cada pessoa da Avana: status da admissão, se bate ponto, se tem escala
-- vigente e quantas marcações teve no mês. Cole inteiro numa aba vazia.
-- Troque 'comp' se o mês for outro.
-- ============================================================================
WITH params AS (
  SELECT '2026-09'::text AS comp
),
mes AS (
  SELECT (comp||'-01')::date AS d0,
         (date_trunc('month',(comp||'-01')::date) + INTERVAL '1 month - 1 day')::date AS d1
  FROM params
),
alvo AS (
  SELECT id AS empresa_id, tenant_id
  FROM public.empresa_cadastro
  WHERE razao_social ILIKE '%avana%' OR nome_fantasia ILIKE '%avana%'
)
SELECT
  a.nome_completo                                   AS nome,
  a.status::text                                    AS status_admissao,
  COALESCE(a.inativo,false)                         AS inativo,
  a.bate_ponto,
  a.dispensado_ponto,
  a.data_admissao,
  a.data_desligamento,
  EXISTS (
    SELECT 1 FROM public.ponto_escala_atribuicoes x
    WHERE x.tenant_id = a.tenant_id
      AND COALESCE(x.ativa,true) = true
      AND regexp_replace(COALESCE(x.colaborador_cpf,''),'[^0-9]','','g')
        = regexp_replace(a.cpf,'[^0-9]','','g')
      AND (x.data_fim IS NULL OR x.data_fim >= (SELECT d0 FROM mes))
  )                                                 AS tem_escala,
  (
    SELECT count(*) FROM public.ponto_marcacoes m
    WHERE m.tenant_id = a.tenant_id
      AND regexp_replace(m.colaborador_cpf,'[^0-9]','','g')
        = regexp_replace(a.cpf,'[^0-9]','','g')
      AND m.data_marcacao BETWEEN (SELECT d0 FROM mes) AND (SELECT d1 FROM mes)
      AND NOT COALESCE(m.desconsiderada,false)
  )                                                 AS marcacoes_mes
FROM public.admissoes a
JOIN alvo t ON t.empresa_id = a.empresa_id
ORDER BY tem_escala DESC, marcacoes_mes DESC, a.nome_completo;
