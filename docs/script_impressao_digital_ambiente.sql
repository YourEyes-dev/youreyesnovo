-- ============================================================================
-- IMPRESSAO DIGITAL ESTRUTURAL DO AMBIENTE — para comparar os tres iguais
--
-- SOMENTE LEITURA. Nao cria, nao altera e nao apaga NADA. So le o catalogo.
--
-- PARA QUE SERVE
-- Rode o MESMO script no SQL Editor de cada ambiente (PRODUCAO, HOMOLOGACAO e
-- TESTE) e compare as colunas "qtd" e "impressao". Onde as tres linhas baterem,
-- a area esta identica nos tres. Onde a "impressao" divergir, algo entrou num
-- ambiente e nao no outro — e a coluna "qtd" ja diz se sobrou ou faltou.
--
-- O que cada linha resume (schema public):
--   tabelas ............ nomes de tabela
--   colunas ............ nome, tipo, nulabilidade e default de cada coluna
--   funcoes (com corpo)  assinatura E o corpo de cada funcao/procedure — pega
--                        ate uma correcao interna (ex.: j.minutos -> jornada_min)
--   gatilhos ........... os triggers de cada tabela
--   politicas RLS ...... as politicas de seguranca por tabela
--   enums .............. os tipos enum e seus valores, em ordem
--   indices ............ os indices e sua definicao
--
-- ESCOPO: cada area vem separada em 'negocio' e 'qa'. O motor de testes (tudo
-- que comeca com qa_) e centenas de objetos que vivem no TESTE mas nao
-- necessariamente na producao — misturar os dois faz a producao parecer muito
-- mais divergente do que e. O que PRECISA estar igual nos tres e a linha
-- 'negocio'. A linha 'qa' so precisa bater onde o motor de QA deva existir.
--
-- A linha 0 mostra a versao do Postgres: se um ambiente estiver numa versao
-- MAIOR diferente, o corpo das funcoes pode sair formatado de outro jeito e a
-- impressao das "funcoes" divergir sem que a logica seja diferente — por isso
-- ela vem primeiro, para ler antes de assustar.
-- ============================================================================

WITH
tabs AS MATERIALIZED (
  SELECT CASE WHEN tablename LIKE 'qa\_%' THEN 'qa' ELSE 'negocio' END AS escopo,
         count(*) AS n,
         md5(COALESCE(string_agg(tablename, E'\n' ORDER BY tablename), '')) AS h
  FROM pg_tables WHERE schemaname = 'public'
  GROUP BY 1
),
cols AS MATERIALIZED (
  SELECT CASE WHEN table_name LIKE 'qa\_%' THEN 'qa' ELSE 'negocio' END AS escopo,
         count(*) AS n,
         md5(COALESCE(string_agg(
           format('%s.%s|%s|%s|%s', table_name, column_name, data_type,
                  is_nullable, COALESCE(column_default, '')),
           E'\n' ORDER BY table_name, column_name), '')) AS h
  FROM information_schema.columns WHERE table_schema = 'public'
  GROUP BY 1
),
funs AS MATERIALIZED (
  SELECT CASE WHEN p.proname LIKE 'qa\_%' THEN 'qa' ELSE 'negocio' END AS escopo,
         count(*) AS n,
         md5(COALESCE(string_agg(
           p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')|'
             || md5(pg_get_functiondef(p.oid)),
           E'\n' ORDER BY p.proname, pg_get_function_identity_arguments(p.oid)), '')) AS h
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.prokind IN ('f', 'p')
  GROUP BY 1
),
trigs AS MATERIALIZED (
  SELECT CASE WHEN c.relname LIKE 'qa\_%' THEN 'qa' ELSE 'negocio' END AS escopo,
         count(*) AS n,
         md5(COALESCE(string_agg(
           c.relname || '.' || t.tgname || '|' || md5(pg_get_triggerdef(t.oid)),
           E'\n' ORDER BY c.relname, t.tgname), '')) AS h
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND NOT t.tgisinternal
  GROUP BY 1
),
pols AS MATERIALIZED (
  SELECT CASE WHEN tablename LIKE 'qa\_%' THEN 'qa' ELSE 'negocio' END AS escopo,
         count(*) AS n,
         md5(COALESCE(string_agg(
           tablename || '.' || policyname || '|' || cmd || '|'
             || COALESCE(permissive, '') || '|' || COALESCE(qual, '') || '|'
             || COALESCE(with_check, '') || '|'
             || array_to_string(COALESCE(roles, ARRAY[]::name[]), ','),
           E'\n' ORDER BY tablename, policyname), '')) AS h
  FROM pg_policies WHERE schemaname = 'public'
  GROUP BY 1
),
enums AS MATERIALIZED (
  SELECT CASE WHEN x.typname LIKE 'qa\_%' THEN 'qa' ELSE 'negocio' END AS escopo,
         count(*) AS n,
         md5(COALESCE(string_agg(x.typname || '|' || x.labels, E'\n' ORDER BY x.typname), '')) AS h
  FROM (
    SELECT t.typname,
           string_agg(e.enumlabel, ',' ORDER BY e.enumsortorder) AS labels
    FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public'
    GROUP BY t.typname
  ) x
  GROUP BY 1
),
idx AS MATERIALIZED (
  SELECT CASE WHEN tablename LIKE 'qa\_%' THEN 'qa' ELSE 'negocio' END AS escopo,
         count(*) AS n,
         md5(COALESCE(string_agg(indexname || '|' || md5(indexdef),
             E'\n' ORDER BY tablename, indexname), '')) AS h
  FROM pg_indexes WHERE schemaname = 'public'
  GROUP BY 1
),
-- a grade fixa (area x escopo) garante uma linha ate quando o escopo esta vazio
grade AS (
  SELECT * FROM (VALUES
    (1, 'tabelas'), (2, 'colunas'), (3, 'funcoes (com corpo)'),
    (4, 'gatilhos'), (5, 'politicas RLS'), (6, 'enums'), (7, 'indices')
  ) g(ordem, area)
  CROSS JOIN (VALUES ('negocio'), ('qa')) e(escopo)
),
dados AS (
  SELECT 1 AS ordem, escopo, n, h FROM tabs
  UNION ALL SELECT 2, escopo, n, h FROM cols
  UNION ALL SELECT 3, escopo, n, h FROM funs
  UNION ALL SELECT 4, escopo, n, h FROM trigs
  UNION ALL SELECT 5, escopo, n, h FROM pols
  UNION ALL SELECT 6, escopo, n, h FROM enums
  UNION ALL SELECT 7, escopo, n, h FROM idx
)
SELECT 0 AS ordem, 'versao do Postgres'::text AS area, ''::text AS escopo,
       NULL::bigint AS qtd, split_part(version(), ' ', 2) AS impressao
UNION ALL
SELECT g.ordem, g.area, g.escopo,
       COALESCE(d.n, 0) AS qtd,
       COALESCE(d.h, '(vazio)') AS impressao
FROM grade g
LEFT JOIN dados d ON d.ordem = g.ordem AND d.escopo = g.escopo
ORDER BY ordem, escopo;
