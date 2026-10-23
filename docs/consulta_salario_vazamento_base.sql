-- SOMENTE LEITURA — o salario esta protegido tambem nas tabelas de ORIGEM, ou so nas telas/visoes?
-- A configuracao "Pode ver salario" do perfil mascara o valor nas visoes (admissoes_segura, cargos_segura...).
-- Esta consulta confere se quem esta logado (papel authenticated) ainda consegue LER a coluna direto na tabela de origem
-- e se existe alguma trava RESTRICTIVE de leitura nelas. Nao le valor de salario nenhum.
SELECT x.tabela, x.coluna,
       has_column_privilege('authenticated', format('public.%I', x.tabela), x.coluna, 'SELECT') AS authenticated_le_a_coluna,
       has_column_privilege('anon', format('public.%I', x.tabela), x.coluna, 'SELECT')          AS anon_le_a_coluna,
       (SELECT count(*) FROM pg_policies p WHERE p.schemaname='public' AND p.tablename = x.tabela AND p.permissive='RESTRICTIVE' AND p.cmd IN ('SELECT','ALL')) AS travas_restritivas_de_leitura
FROM (VALUES
  ('admissoes','salario'),
  ('cargos','faixa_salarial_min'),
  ('contratos_experiencia','salario'),
  ('ferias_solicitacoes','valor_total_bruto'),
  ('beneficios_colaboradores','valor'),
  ('ferias_alertas','custo_estimado')
) AS x(tabela, coluna)
WHERE to_regclass('public.' || x.tabela) IS NOT NULL
ORDER BY 1;
