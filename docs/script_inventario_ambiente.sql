-- ============================================================================
-- INVENTARIO ESTRUTURAL DO AMBIENTE — uma linha por objeto (para cruzar os 3)
--
-- SOMENTE LEITURA. Nao cria, nao altera e nao apaga NADA. So le o catalogo.
--
-- PARA QUE SERVE
-- E o detalhe da "impressao digital": em vez de um hash por area, devolve UMA
-- LINHA POR OBJETO, com um hash do proprio objeto. Rode nos tres ambientes,
-- baixe o resultado em CSV (botao de exportar do SQL Editor) e me mande os tres
-- arquivos. Cruzando os tres eu digo, objeto a objeto: o que falta em cada
-- ambiente, o que sobra, e o que existe nos tres mas esta DIFERENTE (mesmo
-- identificador, hash diferente = foi modificado num lado so).
--
-- COLUNAS
--   area .......... tabela | coluna | funcao | gatilho | politica | enum | indice
--   escopo ........ negocio | qa   (qa_* = motor de testes; separavel do resto)
--   identificador . o nome do objeto (estavel entre ambientes)
--   impressao ..... hash do CONTEUDO do objeto (tipo/definicao/corpo). Some com
--                   o identificador, distingue "faltando" de "modificado".
--
-- Ordenado por area, escopo, identificador — dois ambientes alinhados dao
-- arquivos que batem linha a linha.
-- ============================================================================

SELECT 'tabela' AS area,
       CASE WHEN tablename LIKE 'qa\_%' THEN 'qa' ELSE 'negocio' END AS escopo,
       tablename AS identificador,
       '' AS impressao
FROM pg_tables WHERE schemaname = 'public'

UNION ALL
SELECT 'coluna',
       CASE WHEN table_name LIKE 'qa\_%' THEN 'qa' ELSE 'negocio' END,
       table_name || '.' || column_name,
       md5(data_type || '|' || is_nullable || '|' || COALESCE(column_default, ''))
FROM information_schema.columns WHERE table_schema = 'public'

UNION ALL
SELECT 'funcao',
       CASE WHEN p.proname LIKE 'qa\_%' THEN 'qa' ELSE 'negocio' END,
       p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
       md5(pg_get_functiondef(p.oid))
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prokind IN ('f', 'p')

UNION ALL
SELECT 'gatilho',
       CASE WHEN c.relname LIKE 'qa\_%' THEN 'qa' ELSE 'negocio' END,
       c.relname || '.' || t.tgname,
       md5(pg_get_triggerdef(t.oid))
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND NOT t.tgisinternal

UNION ALL
SELECT 'politica',
       CASE WHEN tablename LIKE 'qa\_%' THEN 'qa' ELSE 'negocio' END,
       tablename || '.' || policyname,
       md5(cmd || '|' || COALESCE(permissive, '') || '|' || COALESCE(qual, '')
           || '|' || COALESCE(with_check, '') || '|'
           || array_to_string(COALESCE(roles, ARRAY[]::name[]), ','))
FROM pg_policies WHERE schemaname = 'public'

UNION ALL
SELECT 'enum',
       CASE WHEN x.typname LIKE 'qa\_%' THEN 'qa' ELSE 'negocio' END,
       x.typname,
       md5(x.labels)
FROM (
  SELECT t.typname,
         string_agg(e.enumlabel, ',' ORDER BY e.enumsortorder) AS labels
  FROM pg_enum e
  JOIN pg_type t ON t.oid = e.enumtypid
  JOIN pg_namespace n ON n.oid = t.typnamespace
  WHERE n.nspname = 'public'
  GROUP BY t.typname
) x

UNION ALL
SELECT 'indice',
       CASE WHEN tablename LIKE 'qa\_%' THEN 'qa' ELSE 'negocio' END,
       indexname,
       md5(indexdef)
FROM pg_indexes WHERE schemaname = 'public'

ORDER BY 1, 2, 3;
