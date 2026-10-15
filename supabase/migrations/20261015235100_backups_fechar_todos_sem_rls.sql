-- Fecha o acesso via API a TODA tabela public.backup_* que esteja sem RLS.
--
-- Por que: a lista fixa da migration 20261015165521 cobriu 8 tabelas da producao, mas
-- backups novos continuam nascendo abertos (a conferencia da homologacao achou
-- backup_superadmin_20260831, legivel por anon e authenticated). Em vez de listar
-- nomes, o laco olha o catalogo, entao pega tambem o que ainda vai ser criado.
-- Nao altera nem apaga dado: so liga RLS e retira o acesso de anon e authenticated.
-- Sem politica, service_role e o dono do banco continuam lendo (rollback, conferencia).
-- Idempotente; banco sem tabela de backup (staging, banco novo) nao faz nada.
DO $rls$
DECLARE
  v_tab text;
BEGIN
  SET LOCAL lock_timeout = '10s';
  FOR v_tab IN
    SELECT c.relname
      FROM pg_class c
     WHERE c.relnamespace = 'public'::regnamespace
       AND c.relkind IN ('r', 'p')
       AND c.relname LIKE 'backup\_%'
     ORDER BY c.relname
  LOOP
    BEGIN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', v_tab);
      EXECUTE format('REVOKE ALL ON TABLE public.%I FROM anon, authenticated', v_tab);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'backup %: % (%)', v_tab, SQLERRM, SQLSTATE;
    END;
  END LOOP;
END
$rls$;
