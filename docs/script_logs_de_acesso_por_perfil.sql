-- ============================================================================
-- ENTREGA — Trilhas de auditoria de usuarios e perfis: leitura por perfil, autor carimbado pelo banco, imutaveis
-- Cole no SQL Editor (TESTE e HOMOLOGACAO primeiro; depois PRODUCAO). UMA transacao, idempotente.
-- Cria 1 funcao de gatilho, 3 gatilhos e 12 politicas RESTRICTIVE. Nenhum dado e alterado e nenhuma tabela e criada.
-- Rode ANTES a consulta_logs_de_acesso_quem_muda.sql. Termina com UMA conferencia SELECT.
-- ============================================================================
SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.audit_carimba_autor()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $fn$
DECLARE
  v_nome text;
BEGIN
  -- so a gravacao feita direto pelo navegador (papel authenticated); rotinas do sistema mantem o que informam
  IF current_user <> 'authenticated' OR auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;
  v_nome := (SELECT p.nome_completo FROM public.profiles p WHERE p.user_id = auth.uid() LIMIT 1);
  IF TG_TABLE_NAME = 'usuario_audit_log' THEN
    NEW.executor_id := auth.uid();
    NEW.executor_nome := v_nome;
    NEW.created_at := now();
  ELSIF TG_TABLE_NAME = 'perfil_audit_log' THEN
    NEW.realizado_por := auth.uid();
    NEW.realizado_por_nome := v_nome;
    NEW.created_at := now();
  ELSIF TG_TABLE_NAME = 'perfil_acesso_sensivel_log' THEN
    NEW.usuario_id := auth.uid();
    NEW.usuario_nome := v_nome;
    NEW.created_at := now();
  END IF;
  RETURN NEW;
END;
$fn$;

DO $log$
DECLARE
  r record;
  v_mods text;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('usuario_audit_log',          ARRAY['usuarios','configuracoes']),
      ('perfil_audit_log',           ARRAY['perfis_acesso','usuarios','configuracoes']),
      ('perfil_acesso_sensivel_log', ARRAY['perfis_acesso','usuarios','configuracoes'])
    ) AS t(tabela, modulos)
  LOOP
    BEGIN
      IF to_regclass('public.' || r.tabela) IS NULL THEN
        RAISE NOTICE 'Logs de acesso: tabela % nao existe; pulada.', r.tabela;
        CONTINUE;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema = 'public' AND table_name = r.tabela AND column_name = 'tenant_id') THEN
        RAISE NOTICE 'ATENCAO: % sem tenant_id; ficou SEM a trava.', r.tabela;
        CONTINUE;
      END IF;

      v_mods := quote_literal(r.modulos) || '::text[]';
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', r.tabela);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'perfil_restringe_leitura_' || r.tabela, r.tabela);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'perfil_restringe_escrita_' || r.tabela || '_ins', r.tabela);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'log_imutavel_' || r.tabela || '_upd', r.tabela);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'log_imutavel_' || r.tabela || '_del', r.tabela);

      EXECUTE format(
        'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR SELECT TO authenticated '
        || 'USING (public.perfil_permite_modulo(tenant_id, VARIADIC %s))',
        'perfil_restringe_leitura_' || r.tabela, r.tabela, v_mods);
      EXECUTE format(
        'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR INSERT TO authenticated '
        || 'WITH CHECK (public.is_superadmin(auth.uid()) OR (public.perfil_permite_modulo(tenant_id, VARIADIC %s) '
        || 'AND public.perfil_escreve(tenant_id, %s, ARRAY[''criar'',''editar'',''aprovar'',''excluir'']::text[], NULL)))',
        'perfil_restringe_escrita_' || r.tabela || '_ins', r.tabela, v_mods, v_mods);
      EXECUTE format('CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR UPDATE TO authenticated USING (false) WITH CHECK (false)',
                     'log_imutavel_' || r.tabela || '_upd', r.tabela);
      EXECUTE format('CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR DELETE TO authenticated USING (false)',
                     'log_imutavel_' || r.tabela || '_del', r.tabela);

      EXECUTE format('DROP TRIGGER IF EXISTS trg_audit_carimba_autor ON public.%I', r.tabela);
      EXECUTE format('CREATE TRIGGER trg_audit_carimba_autor BEFORE INSERT ON public.%I '
                     || 'FOR EACH ROW EXECUTE FUNCTION public.audit_carimba_autor()', r.tabela);
      RAISE NOTICE 'Logs de acesso: trava aplicada em %.', r.tabela;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ATENCAO: % ficou SEM a trava: %', r.tabela, SQLERRM;
    END;
  END LOOP;
END $log$;

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT
  (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND permissive='RESTRICTIVE'
     AND tablename IN ('usuario_audit_log','perfil_audit_log','perfil_acesso_sensivel_log')
     AND (policyname LIKE 'perfil_restringe_leitura_%' OR policyname LIKE 'perfil_restringe_escrita_%' OR policyname LIKE 'log_imutavel_%')) AS politicas,
  (SELECT count(*) FROM pg_trigger WHERE tgname = 'trg_audit_carimba_autor' AND NOT tgisinternal) AS gatilhos;
-- Esperado: 12 e 3.
-- DESFAZER (so se algo errado aparecer): para cada tabela, DROP POLICY nas 4 politicas acima e
--   DROP TRIGGER IF EXISTS trg_audit_carimba_autor ON public.<tabela>;
