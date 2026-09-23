-- ============================================================================
-- YourEyes · Inventário de estrutura — RESUMO (impressão digital por categoria)
--
-- SOMENTE LEITURA. Não altera nada. Pode rodar quantas vezes quiser, em
-- qualquer banco (teste, homologação, produção). Roda em UMA transação e não
-- deixa rastro.
--
-- PARA QUE SERVE
--   Levantar o "passivo" de banco — as mudanças que foram aplicadas no
--   ambiente de TESTE (que recebe tudo pela esteira, a cada merge) mas que
--   podem NÃO ter chegado à homologação/produção pelo repasse manual de
--   scripts.
--
-- COMO USAR
--   1. Rode este arquivo no SQL Editor do banco de TESTE  (bmehdgthciuvdbvutsdv)
--   2. Rode o MESMO arquivo no SQL Editor da HOMOLOGAÇÃO (fgsblefvdabgdouipigz)
--   3. Rode o MESMO arquivo na PRODUÇÃO                  (diayjpsrcerycycyaxst)
--   Mande de volta as três saídas. Onde a coluna "assinatura" de um banco
--   diferir da do TESTE, aquela categoria tem divergência — aí rodamos o
--   script de DETALHE só naquela categoria para apontar o objeto exato.
--
-- COMO LER
--   • "quantidade" igual + "assinatura" igual  → categoria idêntica ao teste
--   • "quantidade" diferente                    → falta (ou sobra) objeto
--   • "quantidade" igual mas "assinatura" difere → mesmo nº de objetos, mas
--                                                   algum mudou por dentro
--                                                   (ex.: função com corpo velho)
--
--   A linha "AMBIENTE (url)" carimba de qual banco veio a saída — sem ela,
--   uma tabela colada numa conversa não diz de onde é. A linha
--   "migrations (registro)" mostra quantos carimbos o banco tem registrados
--   (o teste é a referência; homologação/produção recebem por script, então
--   esse número lá é só informativo, não mede o passivo).
--
-- ESCOPO: schema public (onde vive o app). Objetos de extensões são
--   excluídos para não gerar ruído. Privilégios (GRANT) não entram de
--   propósito — eles divergem por construção (ver docs/AMBIENTES.md).
-- ============================================================================

WITH itens AS (
  -- TABELAS (nome + conjunto de colunas: nome|tipo|not null)
  SELECT 'tabelas'::text AS categoria,
         c.relname
           || ':' || md5(coalesce(string_agg(
                a.attname || '|' || format_type(a.atttypid, a.atttypmod)
                          || '|' || a.attnotnull::text,
                ',' ORDER BY a.attnum), '')) AS sig
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
  LEFT JOIN pg_attribute a
         ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
  WHERE c.relkind = 'r'
    AND NOT EXISTS (SELECT 1 FROM pg_depend d
                    WHERE d.objid = c.oid AND d.deptype = 'e')
  GROUP BY c.relname

  UNION ALL
  -- VISÕES (nome + definição)
  SELECT 'visoes', v.viewname || ':' || md5(v.definition)
  FROM pg_views v
  WHERE v.schemaname = 'public'

  UNION ALL
  -- FUNÇÕES e PROCEDURES (nome+args + corpo inteiro; pega "corpo velho")
  SELECT 'funcoes',
         p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')'
           || ':' || md5(pg_get_functiondef(p.oid))
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
  WHERE p.prokind IN ('f', 'p')
    AND NOT EXISTS (SELECT 1 FROM pg_depend d
                    WHERE d.objid = p.oid AND d.deptype = 'e')

  UNION ALL
  -- ENUMS (tipo + rótulos na ordem)
  SELECT 'enums',
         t.typname || ':' || string_agg(e.enumlabel, ',' ORDER BY e.enumsortorder)
  FROM pg_type t
  JOIN pg_namespace n ON n.oid = t.typnamespace AND n.nspname = 'public'
  JOIN pg_enum e ON e.enumtypid = t.oid
  GROUP BY t.typname

  UNION ALL
  -- POLÍTICAS RLS (tabela.política + comando + condições)
  SELECT 'politicas',
         pol.tablename || '.' || pol.policyname
           || ':' || pol.cmd
           || ':' || md5(coalesce(pol.qual, '') || '||' || coalesce(pol.with_check, ''))
  FROM pg_policies pol
  WHERE pol.schemaname = 'public'

  UNION ALL
  -- GATILHOS (tabela.gatilho + definição)
  SELECT 'gatilhos',
         c.relname || '.' || tg.tgname || ':' || md5(pg_get_triggerdef(tg.oid))
  FROM pg_trigger tg
  JOIN pg_class c ON c.oid = tg.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
  WHERE NOT tg.tgisinternal

  UNION ALL
  -- ÍNDICES (nome + definição)
  SELECT 'indices', i.indexname || ':' || md5(i.indexdef)
  FROM pg_indexes i
  WHERE i.schemaname = 'public'

  UNION ALL
  -- RESTRIÇÕES (tabela.restrição + tipo)
  SELECT 'restricoes',
         c.relname || '.' || con.conname || ':' || con.contype::text
  FROM pg_constraint con
  JOIN pg_class c ON c.oid = con.conrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
)
SELECT 0 AS ord,
       'AMBIENTE (url)'::text AS categoria,
       NULL::bigint AS quantidade,
       coalesce((SELECT valor FROM public.app_config WHERE chave = 'supabase_url'),
                '(app_config sem supabase_url)') AS assinatura
UNION ALL
SELECT 1,
       'migrations (registro)',
       (SELECT count(*) FROM supabase_migrations.schema_migrations),
       (SELECT max(version) FROM supabase_migrations.schema_migrations)
UNION ALL
SELECT 2, categoria, count(*), md5(string_agg(sig, chr(10) ORDER BY sig))
FROM itens
GROUP BY categoria
ORDER BY ord, categoria;
