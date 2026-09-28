-- ============================================================================
-- ENTREGA — ISOL-005 · cercar tabelas de backup sem RLS — HOMOLOGAÇÃO
--
-- Cole no SQL Editor da HOMOLOGAÇÃO; depois de conferido, o MESMO na PRODUÇÃO.
--
-- O ISOL-005 acusou 1 tabela sensível com isolamento DESLIGADO: a
-- backup_doc_reconc_20260928, cópia que o backfill do ADM criou (e que nasceu
-- sem RLS, como toda tabela de backup dos scripts de entrega). É SEGURO cercá-la:
-- backup só é acessado pelo dono do banco/superadmin, então ligar RLS + política
-- somente_superadmin não corta acesso de ninguém e não atrapalha o desfazer.
--
-- Este bloco varre TODA tabela public LIKE 'backup_%' com coluna tenant_id e RLS
-- desligado, liga o RLS e cria a política somente_superadmin (mesmo nome/forma da
-- varredura ISOL-005 original → idempotente). Fecha a atual e qualquer outra
-- cópia de backup que esteja aberta.
--
-- SEGURANÇA: só ENABLE RLS + CREATE POLICY via EXECUTE (dinâmico) — não cria
-- tabela (auto-RLS não liga), não apaga/altera dado. Idempotente. lock curto.
-- ============================================================================

SET lock_timeout = '10s';

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
      IF NOT EXISTS (SELECT 1 FROM pg_policies p WHERE p.schemaname='public' AND p.tablename=r.tabela AND p.policyname='somente_superadmin') THEN
        EXECUTE format(
          'CREATE POLICY somente_superadmin ON public.%I FOR ALL TO authenticated '
          'USING (public.is_superadmin(auth.uid())) WITH CHECK (public.is_superadmin(auth.uid()))',
          r.tabela);
      END IF;
      v_feitas := v_feitas + 1;
      RAISE NOTICE 'ISOL-005: copia de seguranca % protegida.', r.tabela;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ISOL-005: nao deu para proteger %: %', r.tabela, SQLERRM;
    END;
  END LOOP;
  RAISE NOTICE 'ISOL-005: % copia(s) de seguranca protegida(s).', v_feitas;
END $isol005backup$;

-- ════════════════════ CONFERÊNCIA (esperado tudo 'ok') ════════════════════════
WITH sens AS MATERIALIZED (
  SELECT c.relname, c.relrowsecurity, (c.relname LIKE 'backup\_%') AS eh_backup
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname='public' AND c.relkind='r' AND c.relname NOT LIKE 'qa\_%'
    AND EXISTS (SELECT 1 FROM pg_attribute a
                 WHERE a.attrelid=c.oid AND a.attname='tenant_id' AND a.attnum>0 AND NOT a.attisdropped)
),
conf AS MATERIALIZED (
  SELECT 1 AS ord, 'ISOL-005 · cópias backup_* ainda sem RLS'::text AS item,
         (SELECT count(*) FROM sens WHERE NOT relrowsecurity AND eh_backup) AS n
  UNION ALL
  SELECT 2, 'ISOL-005 · tabelas expostas — RLS off (não backup)',
         (SELECT count(*) FROM sens WHERE NOT relrowsecurity AND NOT eh_backup)
)
SELECT item, CASE WHEN n = 0 THEN 'ok' ELSE n::text || ' — CONFERIR' END AS situacao
FROM conf ORDER BY ord;
