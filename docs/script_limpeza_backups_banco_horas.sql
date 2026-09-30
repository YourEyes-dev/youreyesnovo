-- ============================================================================
-- LIMPEZA — tabelas de backup da correção do banco de horas (set/2026)
-- Colar no SQL Editor de PRODUÇÃO (projeto diayjpsrcerycycyaxst).
--
-- O QUE APAGA: só as tabelas de rede de segurança que ESTA correção criou —
-- as de prefixo:
--     backup_fase3_%             (Fase 3: reapuração + zeragem do grupo)
--     backup_fechamento_banco_%  (zeragem corretiva do fechamento)
-- NÃO toca em nenhum outro backup de produção (13o, tenants, escalas, admissoes,
-- perfis, etc.) — esses são de outras entregas e ficam intactos.
--
-- COMO USAR (dois passos):
--   PASSO 1 — rode SÓ o bloco do PASSO 1 e confira a lista do que será apagado.
--   PASSO 2 — se concordar com a lista, rode o bloco do PASSO 2 para apagar.
--
-- ATENÇÃO: apagar tabela é irreversível. Só rode o PASSO 2 quando estiver
-- seguro dos resultados em produção (saldos conferidos). Estas são apenas
-- CÓPIAS de segurança — não afetam nenhuma tela nem cálculo do sistema.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- PASSO 1 — CONFERIR (somente leitura): o que existe hoje e será apagado
-- ---------------------------------------------------------------------------
SELECT c.relname AS tabela,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS tamanho,
       GREATEST(c.reltuples::bigint, 0) AS linhas_aprox
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
  AND (c.relname LIKE 'backup_fase3_%'
    OR c.relname LIKE 'backup_fechamento_banco_%')
ORDER BY c.relname;


-- ---------------------------------------------------------------------------
-- PASSO 2 — APAGAR (rode depois de conferir a lista acima)
-- Remove só as tabelas dos dois prefixos. Idempotente: rodar 2x não quebra.
-- ---------------------------------------------------------------------------
DO $limpa$
DECLARE
  r record;
  v_n int := 0;
BEGIN
  FOR r IN
    SELECT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
      AND (c.relname LIKE 'backup_fase3_%'
        OR c.relname LIKE 'backup_fechamento_banco_%')
    ORDER BY c.relname
  LOOP
    EXECUTE format('DROP TABLE IF EXISTS public.%I', r.relname);
    RAISE NOTICE 'Removida: %', r.relname;
    v_n := v_n + 1;
  END LOOP;

  IF v_n = 0 THEN
    RAISE NOTICE 'Nenhuma tabela de backup do banco de horas encontrada — nada a apagar.';
  ELSE
    RAISE NOTICE 'Total de tabelas de backup removidas: %', v_n;
  END IF;
END $limpa$;

-- Conferência final (o editor mostra só o último resultado): deve retornar 0.
SELECT count(*) AS backups_restantes
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
  AND (c.relname LIKE 'backup_fase3_%'
    OR c.relname LIKE 'backup_fechamento_banco_%');
