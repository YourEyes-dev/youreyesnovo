-- ============================================================================
-- ENTREGA — ISOL-005 (toda tabela sensível com isolamento coerente) — HOMOLOGAÇÃO
--
-- Cole no SQL Editor da HOMOLOGAÇÃO; depois de conferido, o MESMO na PRODUÇÃO.
--
-- ISOL-005: toda tabela com tenant_id precisa de RLS ligado E de pelo menos uma
--   política. RLS ligado SEM política não protege — TRANCA (ninguém lê, nem o
--   dono do dado), e o risco é o conserto apressado de amanhã desligar o RLS e
--   virar tabela exposta. A correção é DERIVADA (não uma lista fixa): varre quem
--   está nessa situação e dá a política mínima — só superadmin. Não afrouxa
--   nada (de "ninguém lê" para "só superadmin lê"); tabela que cair nisso amanhã
--   é pega pela mesma varredura.
--
-- Duas metades:
--   1) tabelas de cobrança/limites com RLS ligado e ZERO política → cria
--      somente_superadmin.
--   2) tabelas backup_* (cópias com dado real que nascem sem isolamento) →
--      liga RLS + cria somente_superadmin. (O desfazer não é afetado: quem roda
--      restauração é o dono do banco, para quem o RLS não se aplica.)
--
-- SEGURANÇA: só ENABLE RLS e CREATE POLICY, via EXECUTE format (dinâmico) — não
--   cria tabela (auto-RLS não é acionado), não cria gatilho, não apaga/altera
--   dado. Nome de política fixo (somente_superadmin, único por tabela) → rodar
--   de novo não duplica. Idempotente. lock_timeout curto.
--   Depende de public.is_superadmin(auth.uid()) — helper antigo, já em produção.
--
-- Origem: migration 20260916235851 (seção ISOL-005). Ao fim, conferência que
--   audita o estado real (esperado: zero tabela exposta e zero travada).
-- ============================================================================

SET lock_timeout = '10s';

-- ── 1) tabelas sensíveis com RLS ligado e ZERO política ─────────────────────
DO $isol005$
DECLARE r record; v_feitas int := 0;
BEGIN
  FOR r IN
    SELECT c.relname AS tabela
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
      AND c.relrowsecurity
      AND c.relname NOT LIKE 'qa\_%'
      AND EXISTS (SELECT 1 FROM pg_attribute a
                   WHERE a.attrelid = c.oid AND a.attname = 'tenant_id'
                     AND a.attnum > 0 AND NOT a.attisdropped)
      AND NOT EXISTS (SELECT 1 FROM pg_policies p
                       WHERE p.schemaname = 'public' AND p.tablename = c.relname)
    ORDER BY c.relname
  LOOP
    BEGIN
      EXECUTE format(
        'CREATE POLICY somente_superadmin ON public.%I FOR ALL TO authenticated '
        'USING (public.is_superadmin(auth.uid())) WITH CHECK (public.is_superadmin(auth.uid()))',
        r.tabela);
      v_feitas := v_feitas + 1;
      RAISE NOTICE 'ISOL-005: politica somente_superadmin criada em %', r.tabela;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ISOL-005: nao deu para criar politica em %: %', r.tabela, SQLERRM;
    END;
  END LOOP;
  RAISE NOTICE 'ISOL-005: % tabela(s) destrancada(s) com politica minima.', v_feitas;
END $isol005$;

-- ── 2) cópias de segurança backup_* sem isolamento ──────────────────────────
DO $isol005backup$
DECLARE r record; v_feitas int := 0;
BEGIN
  FOR r IN
    SELECT c.relname AS tabela
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
      AND c.relname LIKE 'backup\_%'
      AND EXISTS (SELECT 1 FROM pg_attribute a
                   WHERE a.attrelid = c.oid AND a.attname = 'tenant_id'
                     AND a.attnum > 0 AND NOT a.attisdropped)
      AND NOT c.relrowsecurity
    ORDER BY c.relname
  LOOP
    BEGIN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', r.tabela);
      EXECUTE format(
        'CREATE POLICY somente_superadmin ON public.%I FOR ALL TO authenticated '
        'USING (public.is_superadmin(auth.uid())) WITH CHECK (public.is_superadmin(auth.uid()))',
        r.tabela);
      v_feitas := v_feitas + 1;
      RAISE NOTICE 'ISOL-005: copia de seguranca % protegida.', r.tabela;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ISOL-005: nao deu para proteger %: %', r.tabela, SQLERRM;
    END;
  END LOOP;
  RAISE NOTICE 'ISOL-005: % copia(s) de seguranca protegida(s).', v_feitas;
END $isol005backup$;

-- ════════════════════ CONFERÊNCIA (única — mesma lógica do ISOL-005) ═════════
-- Esperado: todas as contagens em 0.
--   • exposta  = tabela com tenant_id e RLS DESLIGADO (não protege).
--   • travada  = tabela com tenant_id, RLS ligado e ZERO política (tranca).
WITH sens AS MATERIALIZED (
  SELECT c.oid, c.relname, c.relrowsecurity,
         (c.relname LIKE 'backup\_%') AS eh_backup
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname='public' AND c.relkind='r' AND c.relname NOT LIKE 'qa\_%'
    AND EXISTS (SELECT 1 FROM pg_attribute a
                 WHERE a.attrelid=c.oid AND a.attname='tenant_id'
                   AND a.attnum>0 AND NOT a.attisdropped)
),
conf AS MATERIALIZED (
  SELECT 'ISOL-005 · tabelas expostas — RLS desligado (não backup)'::text AS item,
         (SELECT count(*) FROM sens WHERE NOT relrowsecurity AND NOT eh_backup) AS n
  UNION ALL
  SELECT 'ISOL-005 · cópias backup_* ainda sem RLS',
         (SELECT count(*) FROM sens WHERE NOT relrowsecurity AND eh_backup)
  UNION ALL
  SELECT 'ISOL-005 · tabelas travadas — RLS ligado e zero política',
         (SELECT count(*) FROM sens s WHERE s.relrowsecurity
            AND NOT EXISTS (SELECT 1 FROM pg_policies p
                             WHERE p.schemaname='public' AND p.tablename=s.relname))
)
SELECT item, CASE WHEN n = 0 THEN 'ok' ELSE n::text || ' — CONFERIR' END AS situacao
FROM conf ORDER BY item;
