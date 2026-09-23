-- ============================================================================
-- YourEyes · Inventário de estrutura — DETALHE (uma linha por objeto)
--
-- SOMENTE LEITURA. Não altera nada. Companheiro do script_inventario_resumo.sql:
-- o resumo diz QUANTO diverge; este diz O QUE diverge, objeto por objeto.
--
-- ESCOPO: as 6 categorias com dívida medida (tabelas, funcoes, gatilhos,
--   indices, politicas, restricoes). Enums e visões saíram porque já vieram
--   idênticos nos três bancos. Schema public. Extensões excluídas.
--
-- COMO USAR
--   1. Rode no SQL Editor do TESTE       (bmehdgthciuvdbvutsdv)
--   2. Rode no SQL Editor da HOMOLOGAÇÃO (fgsblefvdabgdouipigz)
--   3. Rode no SQL Editor da PRODUÇÃO    (diayjpsrcerycycyaxst)
--   Em cada um, use o botão de DOWNLOAD CSV do resultado (é grande, ~6 mil
--   linhas) e me mande os três arquivos. A primeira linha de cada saída
--   carimba de qual banco ela veio.
--
-- O QUE EU FAÇO COM ISSO
--   Comparo as listas: "objeto" que está no teste e falta na produção =
--   passivo a aplicar; "objeto" com a mesma identidade mas "assinatura"
--   diferente = corpo/definição divergente (o caso silencioso). Devolvo a
--   lista nominal e o mapa para os scripts de entrega.
-- ============================================================================

-- Carimbo de identidade (primeira linha)
SELECT '0-AMBIENTE'::text AS categoria,
       coalesce((SELECT valor FROM public.app_config WHERE chave = 'supabase_url'),
                '(app_config sem supabase_url)') AS objeto,
       NULL::text AS assinatura

UNION ALL
-- TABELAS — identidade = nome; assinatura = conjunto de colunas
SELECT 'tabelas',
       c.relname,
       md5(coalesce(string_agg(
            a.attname || '|' || format_type(a.atttypid, a.atttypmod)
                      || '|' || a.attnotnull::text,
            ',' ORDER BY a.attnum), ''))
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
LEFT JOIN pg_attribute a
       ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
WHERE c.relkind = 'r'
  AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = c.oid AND d.deptype = 'e')
GROUP BY c.relname

UNION ALL
-- FUNCOES/PROCEDURES — identidade = nome(args); assinatura = corpo inteiro
SELECT 'funcoes',
       p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
       md5(pg_get_functiondef(p.oid))
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
WHERE p.prokind IN ('f', 'p')
  AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')

UNION ALL
-- GATILHOS — identidade = tabela.gatilho; assinatura = definição
SELECT 'gatilhos',
       c.relname || '.' || tg.tgname,
       md5(pg_get_triggerdef(tg.oid))
FROM pg_trigger tg
JOIN pg_class c ON c.oid = tg.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
WHERE NOT tg.tgisinternal

UNION ALL
-- INDICES — identidade = nome; assinatura = definição
SELECT 'indices', i.indexname, md5(i.indexdef)
FROM pg_indexes i
WHERE i.schemaname = 'public'

UNION ALL
-- POLITICAS RLS — identidade = tabela.política; assinatura = comando+condições
SELECT 'politicas',
       pol.tablename || '.' || pol.policyname,
       md5(pol.cmd || '||' || coalesce(pol.qual, '') || '||' || coalesce(pol.with_check, ''))
FROM pg_policies pol
WHERE pol.schemaname = 'public'

UNION ALL
-- RESTRICOES — identidade = tabela.restrição; assinatura = tipo
SELECT 'restricoes',
       c.relname || '.' || con.conname,
       con.contype::text
FROM pg_constraint con
JOIN pg_class c ON c.oid = con.conrelid
JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'

ORDER BY 1, 2;
