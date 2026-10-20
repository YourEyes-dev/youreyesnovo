import json, sys
d=json.load(open('/tmp/rs/out/fingerprint.json'))
for k,v in d.items():
    s='\n'.join(v); assert "'" not in s and '\\' not in s, k
def lit(k): return "'"+'\n'.join(d[k])+"'"
HEAD="""-- =====================================================================
-- LEVANTAMENTO main x PRODUCAO — parte {n}/4: {titulo}  (SOMENTE LEITURA)
-- Cole no SQL Editor da PRODUCAO (diayjpsrcerycycyaxst), numa aba nova e vazia.
-- Nao altera nada. O 'esperado' vem de um banco montado aplicando as 1189 migrations
-- da main (20/10/2026); a producao so e lida. O resultado traz o RESUMO (contagens) e,
-- abaixo dele, os itens que diferem (no maximo 150 por tipo). Me mande o resultado inteiro.
-- Leitura: FALTA = a main espera e a producao nao tem. Objeto que SO existe na producao
-- nao aparece aqui (isso e outra consulta: docs/diagnostico_producao_vs_migrations.sql).
-- =====================================================================
"""
def final(res):
    return f"""
, numerado AS (
  SELECT tipo, objeto, situacao, detalhe,
         row_number() OVER (PARTITION BY tipo, situacao ORDER BY ord DESC NULLS LAST, objeto) AS rn
  FROM ({res}) r
), resumo AS (
  SELECT 0 AS g, tipo, tipo || ' / ' || situacao AS objeto, 'RESUMO' AS situacao, count(*)::text AS detalhe, 0 AS rn
  FROM numerado GROUP BY tipo, situacao
)
SELECT tipo, objeto, situacao, detalhe FROM (
  SELECT 0 AS g, tipo, objeto, situacao, detalhe, rn FROM resumo
  UNION ALL
  SELECT 1, tipo, objeto, situacao, detalhe, rn FROM numerado WHERE rn <= 150
) x ORDER BY g, tipo, situacao, rn;
"""
EXTP="NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = {o} AND d.deptype = 'e')"
def esp(nome,k): return f"{nome} AS MATERIALIZED (SELECT l AS item FROM unnest(string_to_array({lit(k)}, E'\\n')) l WHERE l <> '')"
files={}
# ---- parte 1: estrutura
p1=f"""{HEAD.format(n=1,titulo='tabelas, colunas, RLS, gatilhos, views, cron e valores de enum')}
WITH esp_tab AS MATERIALIZED (
  SELECT split_part(l,'|',1) AS tabela, split_part(l,'|',2)::int AS rls, split_part(l,'|',3) AS md
  FROM unnest(string_to_array({lit('tab')}, E'\\n')) l WHERE l <> ''
), prod_tab AS MATERIALIZED (
  SELECT c.relname::text AS tabela, c.relrowsecurity::int AS rls,
         (SELECT md5(string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull::int, ',' ORDER BY a.attname))
            FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped) AS md,
         (SELECT count(*) FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped) AS ncol
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind IN ('r','p') AND {EXTP.format(o='c.oid')}
), {esp('esp_trig','trig')}, prod_trig AS MATERIALIZED (
  SELECT t.tgname::text || '@' || c.relname::text AS item FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND NOT t.tgisinternal
), {esp('esp_view','views')}, prod_view AS MATERIALIZED (
  SELECT c.relname::text AS item FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind IN ('v','m') AND {EXTP.format(o='c.oid')}
), {esp('esp_cron','cron')}, prod_cron AS MATERIALIZED (SELECT jobname::text AS item FROM cron.job),
{esp('esp_enum','enums')}, prod_enum AS MATERIALIZED (
  SELECT t.typname::text || '.' || e.enumlabel::text AS item FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
  JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'public'
)
, res AS (
  SELECT 'tabela' AS tipo, e.tabela AS objeto, 'FALTA' AS situacao, NULL::text AS detalhe, NULL::text AS ord
    FROM esp_tab e WHERE NOT EXISTS (SELECT 1 FROM prod_tab p WHERE p.tabela = e.tabela)
  UNION ALL
  SELECT 'tabela', e.tabela, 'RLS_DIFERENTE', 'main espera RLS=' || e.rls || ', producao tem RLS=' || p.rls, NULL
    FROM esp_tab e JOIN prod_tab p ON p.tabela = e.tabela WHERE e.rls <> p.rls
  UNION ALL
  SELECT 'colunas', e.tabela, 'DIFERENTES', 'producao tem ' || p.ncol || ' colunas', NULL
    FROM esp_tab e JOIN prod_tab p ON p.tabela = e.tabela WHERE e.md IS DISTINCT FROM p.md
  UNION ALL
  SELECT 'gatilho', item, 'FALTA', NULL, NULL FROM esp_trig e WHERE NOT EXISTS (SELECT 1 FROM prod_trig p WHERE p.item = e.item)
  UNION ALL
  SELECT 'view', item, 'FALTA', NULL, NULL FROM esp_view e WHERE NOT EXISTS (SELECT 1 FROM prod_view p WHERE p.item = e.item)
  UNION ALL
  SELECT 'cron', item, 'FALTA', NULL, NULL FROM esp_cron e WHERE NOT EXISTS (SELECT 1 FROM prod_cron p WHERE p.item = e.item)
  UNION ALL
  SELECT 'enum', item, 'FALTA', NULL, NULL FROM esp_enum e WHERE NOT EXISTS (SELECT 1 FROM prod_enum p WHERE p.item = e.item)
)"""
p1=p1.replace(", res AS (","\n, res_base AS (",1)
files['1_estrutura']=p1.replace("FROM (SELECT","FROM (SELECT")  # placeholder
files['1_estrutura']+=final("SELECT * FROM res_base")
# ---- parte 2: policies
p2=f"""{HEAD.format(n=2,titulo='politicas de acesso (RLS)')}
WITH {esp('esp_pol','pol')}, prod_pol AS MATERIALIZED (SELECT tablename::text || '.' || policyname::text AS item FROM pg_policies WHERE schemaname = 'public')
, res_base AS (
  SELECT 'politica' AS tipo, item AS objeto, 'FALTA' AS situacao, NULL::text AS detalhe, NULL::text AS ord
    FROM esp_pol e WHERE NOT EXISTS (SELECT 1 FROM prod_pol p WHERE p.item = e.item)
)"""
files['2_politicas']=p2+final("SELECT * FROM res_base")
p3=f"""{HEAD.format(n=3,titulo='indices e restricoes (CHECK, UNIQUE, chave estrangeira)')}
WITH {esp('esp_idx','idx')}, prod_idx AS MATERIALIZED (SELECT indexname::text AS item FROM pg_indexes WHERE schemaname = 'public'),
{esp('esp_con','con')}, prod_con AS MATERIALIZED (
  SELECT c.conname::text || '@' || cl.relname::text AS item FROM pg_constraint c JOIN pg_class cl ON cl.oid = c.conrelid
  JOIN pg_namespace n ON n.oid = cl.relnamespace WHERE n.nspname = 'public' AND c.contype IN ('c','u','f')
)
, res_base AS (
  SELECT 'indice' AS tipo, item AS objeto, 'FALTA' AS situacao, NULL::text AS detalhe, NULL::text AS ord
    FROM esp_idx e WHERE NOT EXISTS (SELECT 1 FROM prod_idx p WHERE p.item = e.item)
  UNION ALL
  SELECT 'restricao', item, 'FALTA', NULL, NULL FROM esp_con e WHERE NOT EXISTS (SELECT 1 FROM prod_con p WHERE p.item = e.item)
)"""
files['3_indices_restricoes']=p3+final("SELECT * FROM res_base")
p4=f"""{HEAD.format(n=4,titulo='funcoes (existencia e corpo)')}
-- detalhe de CORPO_DIFERENTE: 'ultima migration que define a funcao: AAMMDDHHMM'. A lista vem da mais recente
-- para a mais antiga. Diferenca de corpo pode ser so formatacao/comentario (script colado a mao) ou versao velha.
WITH esp_fn AS MATERIALIZED (
  SELECT substring(l from '^(.*)=[0-9a-f]{{8}}@') AS sig, substring(l from '=([0-9a-f]{{8}})@') AS h, substring(l from '@([0-9]*)') AS stamp
  FROM unnest(string_to_array({lit('fn')}, E'\\n')) l WHERE l <> ''
), prod_fn AS MATERIALIZED (
  SELECT p.proname::text || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig, left(md5(p.prosrc), 8) AS h
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND {EXTP.format(o='p.oid')}
)
, res_base AS (
  SELECT 'funcao' AS tipo, e.sig AS objeto, 'FALTA' AS situacao, 'definida na migration ' || e.stamp AS detalhe, e.stamp AS ord
    FROM esp_fn e WHERE NOT EXISTS (SELECT 1 FROM prod_fn p WHERE p.sig = e.sig)
  UNION ALL
  SELECT 'funcao', e.sig, 'CORPO_DIFERENTE', 'ultima migration que define: ' || e.stamp, e.stamp
    FROM esp_fn e JOIN prod_fn p ON p.sig = e.sig WHERE p.h <> e.h
)"""
files['4_funcoes']=p4+final("SELECT * FROM res_base")
import os
os.makedirs('/tmp/rs/out/sql',exist_ok=True)
for k,v in files.items():
    open(f'/tmp/rs/out/sql/levantamento_{k}.sql','w').write(v)
    print(k,len(v))
