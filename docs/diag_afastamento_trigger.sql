-- ============================================================================
-- DIAGNOSTICO (somente leitura) — gatilho de validacao de afastamento na
-- HOMOLOGACAO. Uma consulta, varias linhas.
-- ============================================================================
SELECT 'a. colunas de afastamentos relevantes' AS bloco,
       string_agg(column_name, ', ' ORDER BY column_name) AS valor
FROM information_schema.columns
WHERE table_schema='public' AND table_name='afastamentos'
  AND column_name IN ('prazo_indeterminado','status','status_geral_new','tipo_principal_new','data_fim')
UNION ALL
SELECT 'b. gatilhos BEFORE INSERT de afastamentos',
       (SELECT string_agg(tg.tgname || ' -> ' || p.proname, ' ; ')
          FROM pg_trigger tg JOIN pg_proc p ON p.oid=tg.tgfoid
         WHERE tg.tgrelid='public.afastamentos'::regclass AND NOT tg.tgisinternal
           AND (tg.tgtype & 4)=4)
UNION ALL
SELECT 'c. corpo de afastamento_valida_e_encerra',
       (SELECT pg_get_functiondef(p.oid)
          FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public' AND p.proname='afastamento_valida_e_encerra')
UNION ALL
SELECT 'd. funcoes que geram o texto "sem data de t"',
       (SELECT string_agg(p.proname, ', ')
          FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public' AND p.prosrc ILIKE '%sem data de t%')
ORDER BY bloco;
