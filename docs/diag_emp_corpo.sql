-- ============================================================================
-- DIAGNOSTICO 2 (somente leitura) — a funcao que o GATILHO realmente chama.
-- Na HOMOLOGACAO. Uma consulta, duas linhas:
--  (a) quantas funcoes 'prevent_duplicate_active_cnpj' existem e em que schema;
--  (b) o corpo da funcao efetivamente ligada ao gatilho (via tgfoid).
-- ============================================================================
SELECT 'a. FUNCOES COM ESSE NOME' AS bloco,
       (SELECT string_agg(n.nspname || '.' || p.proname || ' (oid ' || p.oid || ')', ' | ')
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE p.proname = 'prevent_duplicate_active_cnpj') AS valor
UNION ALL
SELECT 'b. CORPO QUE O GATILHO CHAMA',
       (SELECT pg_get_functiondef(tg.tgfoid)
          FROM pg_trigger tg
         WHERE tg.tgname = 'trg_prevent_duplicate_active_cnpj'
           AND tg.tgrelid = 'public.empresa_cadastro'::regclass)
ORDER BY bloco;
