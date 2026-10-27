-- ============================================================================
-- ENTREGA — perfis de acesso: leitura e escrita pelo proprio perfil
-- (perfis_acesso, perfil_permissoes, perfil_excecoes, usuario_perfil_vinculos)
-- Rode ANTES a consulta_perfis_acesso_quem_muda.sql e confira a lista. Cole no SQL Editor.
-- So APERTA politicas (RESTRICTIVE); nenhum dado e alterado. Idempotente. Para desfazer: DROP POLICY das
-- politicas perfil_restringe_leitura_<tabela> e perfil_restringe_escrita_<tabela>_ins/_upd/_del.
-- ============================================================================

SET lock_timeout = '10s';

-- ids dos perfis ativos do usuario logado, sem depender da leitura das tabelas (evita recursao de politica)
CREATE OR REPLACE FUNCTION public.ye_meus_perfis_ids(p_tenant_id uuid)
RETURNS uuid[]
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT COALESCE(array_agg(DISTINCT v.perfil_id), ARRAY[]::uuid[])
    FROM public.usuarios_base ub
    JOIN public.usuario_perfil_vinculos v
      ON v.usuario_id = ub.id AND v.tenant_id = ub.tenant_id
     AND COALESCE(v.ativo, true) = true
     AND (v.expira_em IS NULL OR v.expira_em > now())
   WHERE ub.auth_user_id = auth.uid() AND ub.tenant_id = p_tenant_id
$fn$;

REVOKE EXECUTE ON FUNCTION public.ye_meus_perfis_ids(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ye_meus_perfis_ids(uuid) TO authenticated, service_role;

DO $perf$
DECLARE
  r record;
  v_mods text;
  v_dono text;
BEGIN
  -- tabela | filtro "e seu" | modulos | verbos insert | update | delete
  FOR r IN SELECT * FROM (VALUES
    ('perfis_acesso',           'id = ANY(public.ye_meus_perfis_ids(tenant_id))',
       'perfis_acesso,configuracoes', 'criar',        'editar',        'excluir'),
    ('perfil_permissoes',       'perfil_id = ANY(public.ye_meus_perfis_ids(tenant_id))',
       'perfis_acesso,configuracoes', 'criar,editar', 'editar',        'editar,excluir'),
    ('usuario_perfil_vinculos', 'usuario_id = public.ye_meu_usuario_base_id(tenant_id)',
       'usuarios,configuracoes,perfis_acesso', 'criar', 'editar,aprovar', 'editar,excluir'),
    ('perfil_excecoes',         'usuario_id = public.ye_meu_usuario_base_id(tenant_id)',
       'usuarios,configuracoes,perfis_acesso', 'criar', 'editar,aprovar', 'editar,excluir')
  ) AS t(tab, proprio, modulos, v_ins, v_upd, v_del)
  LOOP
    BEGIN
      IF to_regclass('public.' || r.tab) IS NULL THEN
        RAISE NOTICE '% ausente nesta base; ignorada.', r.tab;
        CONTINUE;
      END IF;

      v_mods := (SELECT string_agg(quote_literal(m), ',') FROM unnest(string_to_array(r.modulos, ',')) m);
      v_dono := format('public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY[%s]::text[])', v_mods);

      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', r.tab);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'perfil_restringe_leitura_' || r.tab, r.tab);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'perfil_restringe_escrita_' || r.tab || '_ins', r.tab);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'perfil_restringe_escrita_' || r.tab || '_upd', r.tab);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'perfil_restringe_escrita_' || r.tab || '_del', r.tab);

      EXECUTE format(
        'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR SELECT TO authenticated USING ((%s) OR %s)',
        'perfil_restringe_leitura_' || r.tab, r.tab, r.proprio, v_dono);

      EXECUTE format(
        'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (%s AND public.perfil_escreve(tenant_id, ARRAY[%s]::text[], ARRAY[%s]::text[], NULL))',
        'perfil_restringe_escrita_' || r.tab || '_ins', r.tab, v_dono, v_mods,
        (SELECT string_agg(quote_literal(m), ',') FROM unnest(string_to_array(r.v_ins, ',')) m));

      EXECUTE format(
        'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR UPDATE TO authenticated USING (%s AND public.perfil_escreve(tenant_id, ARRAY[%s]::text[], ARRAY[%s]::text[], NULL)) WITH CHECK (%s AND public.perfil_escreve(tenant_id, ARRAY[%s]::text[], ARRAY[%s]::text[], NULL))',
        'perfil_restringe_escrita_' || r.tab || '_upd', r.tab, v_dono, v_mods,
        (SELECT string_agg(quote_literal(m), ',') FROM unnest(string_to_array(r.v_upd, ',')) m),
        v_dono, v_mods,
        (SELECT string_agg(quote_literal(m), ',') FROM unnest(string_to_array(r.v_upd, ',')) m));

      EXECUTE format(
        'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR DELETE TO authenticated USING (%s AND public.perfil_escreve(tenant_id, ARRAY[%s]::text[], ARRAY[%s]::text[], NULL))',
        'perfil_restringe_escrita_' || r.tab || '_del', r.tab, v_dono, v_mods,
        (SELECT string_agg(quote_literal(m), ',') FROM unnest(string_to_array(r.v_del, ',')) m));

      RAISE NOTICE '%: leitura e escrita pelo perfil aplicadas.', r.tab;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ATENCAO: % ficou SEM a trava: %', r.tab, SQLERRM;
    END;
  END LOOP;
END $perf$;

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND policyname LIKE 'perfil\_restringe\_%'
         AND tablename IN ('perfis_acesso','perfil_permissoes','perfil_excecoes','usuario_perfil_vinculos')) AS politicas_novas_esperado_16,
       (SELECT count(*) FROM pg_proc WHERE proname = 'ye_meus_perfis_ids')                                    AS funcao_auxiliar;
