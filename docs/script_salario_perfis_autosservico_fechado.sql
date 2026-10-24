-- ============================================================================
-- ENTREGA — Salario (2.3, 2a fatia): perfis de autosservico nao veem salario
-- Cole no SQL Editor (TESTE e HOMOLOGACAO primeiro; depois PRODUCAO). UMA transacao, idempotente.
-- Altera DADO: desliga "Pode ver salario" nos perfis ATIVOS que so liberam os proprios dados. Antes copia essas linhas para
-- backup_perfis_salario_autoss_20261024 (tabela criada por EXECUTE, por causa do RLS automatico do editor).
-- Nao toca perfis com acesso amplo ou de equipe (gestor, RH, administrador, "Perfil Basico" da Taeco): decisao de cada cliente.
-- Termina com UMA conferencia SELECT.
-- ============================================================================
SET lock_timeout = '10s';

DO $aut$
BEGIN
  IF to_regclass('public.perfis_acesso') IS NULL OR to_regclass('public.perfil_permissoes') IS NULL THEN
    RAISE NOTICE 'perfis_acesso/perfil_permissoes ausentes; nada a fazer.';
    RETURN;
  END IF;

  -- a tabela de copia e criada por EXECUTE para o editor de SQL nao acionar o RLS automatico
  IF to_regclass('public.backup_perfis_salario_autoss_20261024') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.backup_perfis_salario_autoss_20261024 AS '
         || 'SELECT pa.id, pa.tenant_id, pa.nome, pa.pode_ver_salario, now() AS copiado_em FROM public.perfis_acesso pa '
         || 'WHERE COALESCE(pa.ativo, true) AND pa.pode_ver_salario '
         || 'AND NOT EXISTS (SELECT 1 FROM public.perfil_permissoes pp WHERE pp.perfil_id = pa.id AND COALESCE(pp.ativo, true) '
         || 'AND COALESCE(pp.escopo::text, '''') <> ''proprio_usuario'')';
  END IF;

  UPDATE public.perfis_acesso pa
     SET pode_ver_salario = false
   WHERE COALESCE(pa.ativo, true) AND pa.pode_ver_salario
     AND NOT EXISTS (SELECT 1 FROM public.perfil_permissoes pp
                      WHERE pp.perfil_id = pa.id AND COALESCE(pp.ativo, true)
                        AND COALESCE(pp.escopo::text, '') <> 'proprio_usuario');
  RAISE NOTICE 'Salario: perfis de autosservico desligados.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENCAO: perfis de autosservico nao foram ajustados: %', SQLERRM;
END $aut$;

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT
  (SELECT count(*) FROM public.backup_perfis_salario_autoss_20261024) AS perfis_desligados_agora,
  (SELECT count(*) FROM public.perfis_acesso pa WHERE COALESCE(pa.ativo, true) AND pa.pode_ver_salario
      AND NOT EXISTS (SELECT 1 FROM public.perfil_permissoes pp WHERE pp.perfil_id = pa.id AND COALESCE(pp.ativo, true)
                        AND COALESCE(pp.escopo::text, '') <> 'proprio_usuario')) AS autosservico_ainda_ve;
-- Esperado: (quantos estavam ligados) e 0.
-- DESFAZER: UPDATE public.perfis_acesso p SET pode_ver_salario = true FROM public.backup_perfis_salario_autoss_20261024 b WHERE p.id = b.id;
