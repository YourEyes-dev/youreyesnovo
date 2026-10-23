-- ============================================================================
-- TRILHAS DE AUDITORIA DE USUARIOS E PERFIS: leitura por perfil, autor carimbado pelo banco, imutaveis
-- (usuario_audit_log, perfil_audit_log, perfil_acesso_sensivel_log)
--
-- O que estava aberto (levantamento 10/2026):
--   * usuario_audit_log e perfil_acesso_sensivel_log: qualquer membro da empresa LIA a trilha de todos
--     (os valores anterior/novo trazem CPF, e-mail, tipo e perfil de cada pessoa). perfil_audit_log ja exigia
--     papel de administrador, mas nao olhava o perfil de acesso.
--   * qualquer membro INSERIA linha nas trilhas, e o autor vinha do navegador (executor_id nem era gravado):
--     o log podia ser forjado e nao dizia quem agiu.
--
-- O que muda (RESTRICTIVE, soma-se as politicas antigas):
--   LEITURA   quem tem Usuarios, Perfis & Acessos ou Configuracoes em escopo amplo (a mesma porta das telas que
--             mostram as trilhas). Sem perfil vinculado, vale o legado por papel de gestao.
--   INSERT    Super Admin, ou quem tem esses modulos E algum verbo de escrita (criar, editar, aprovar, excluir).
--   AUTOR     gatilho BEFORE INSERT: quando a gravacao vem do navegador (papel authenticated), o BANCO preenche
--             quem agiu (id e nome) e a hora; o que o navegador mandar nesses campos e descartado. Gravacoes das
--             rotinas do sistema (security definer, agendador, borda) nao sao tocadas.
--   IMUTAVEL  UPDATE e DELETE negados ao navegador (so rotinas do sistema alteram).
-- Nao altera dado. Idempotente. Atomico por tabela.
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
