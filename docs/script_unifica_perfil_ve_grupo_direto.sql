-- ============================================================================
-- UNIFICAÇÃO (grupo direto) — migra as políticas de leitura por perfil do
-- #913/#915 pro porteiro escopo-aware public.perfil_ve_cpf.
--
-- Antes: usavam perfil_amplo_sem_subordinados / perfil_permite_modulo (que
-- tratam setor/unidade como "vê tudo") OR titular. Agora: perfil_ve_cpf, que
-- respeita o escopo (próprio/subordinados/setor=departamento/empresa+; demais
-- = fail-closed ao próprio). TIGHTENING: perfis com escopo setor/unidade deixam
-- de ver tudo e passam a ver só o devido. RESTRICTIVE só NARROW -> nunca vaza.
--
-- Só grupo DIRETO (sujeito = colaborador por CPF/admissão). Avaliação (avaliador
-- ×avaliado), humor (user_id) e ouvidoria (autor) ficam para depois (dependem de
-- decisão de produto sobre o que o escopo significa ali).
--
-- NÃO altera dado. Idempotente (DROP+CREATE da mesma política).
-- ============================================================================

SET lock_timeout = '10s';

DO $unifica$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      -- metas (#913): colaborador_id (CPF | admissão.id | uid)
      ('metas',
       $p$public.perfil_ve_colaborador_ref(tenant_id, colaborador_id, 'avaliacoes', 'metas')$p$),

      -- SAÚDE (#915)
      ('condicoes_especiais_historico',
       $p$public.perfil_ve_colaborador_ref(tenant_id, colaborador_id, 'colaboradores', 'atestados', 'sst')$p$),

      ('restricoes_laborais',
       $p$public.perfil_ve_cpf(tenant_id,
            COALESCE(
              (SELECT af.colaborador_cpf FROM public.afastamentos af WHERE af.id = restricoes_laborais.afastamento_id),
              (SELECT a.cpf FROM public.admissoes a WHERE a.id = restricoes_laborais.trabalhador_id)
            ),
            'atestados', 'sst', 'colaboradores')
          OR restricoes_laborais.trabalhador_id = auth.uid()$p$),

      -- ONBOARDING (#915)
      ('onboarding_percepcao_cultural',
       $p$public.perfil_ve_colaborador_ref(tenant_id, colaborador_id, 'onboarding', 'psicossocial', 'bem_estar')$p$),

      ('onboarding_respostas',
       $p$public.perfil_ve_cpf(tenant_id,
            (SELECT p.colaborador_cpf FROM public.onboarding_processos p WHERE p.id = onboarding_respostas.processo_id),
            'onboarding')$p$)
    ) AS t(tabela, predicado)
  LOOP
    IF to_regclass('public.' || r.tabela) IS NULL THEN
      RAISE NOTICE 'UNIFICA: % inexistente, pulando.', r.tabela; CONTINUE;
    END IF;
    BEGIN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', r.tabela);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',
                     'perfil_restringe_leitura_' || r.tabela, r.tabela);
      EXECUTE format('CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR SELECT TO authenticated USING (%s)',
                     'perfil_restringe_leitura_' || r.tabela, r.tabela, r.predicado);
      RAISE NOTICE 'UNIFICA: % migrada para perfil_ve_cpf.', r.tabela;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'UNIFICA: FALHA em % -> %', r.tabela, SQLERRM;
    END;
  END LOOP;
END
$unifica$;

-- Conferência: a política existe e já referencia o porteiro novo.
SELECT t.tabela,
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_policies p
         WHERE p.schemaname = 'public' AND p.tablename = t.tabela
           AND p.policyname = 'perfil_restringe_leitura_' || t.tabela
           AND p.permissive = 'RESTRICTIVE' AND p.cmd = 'SELECT'
           AND position('perfil_ve_' IN COALESCE(p.qual, '')) > 0
       ) THEN 'OK (perfil_ve_cpf)' ELSE 'FALTA' END AS leitura_escopo_aware
FROM (VALUES
  ('metas'),('condicoes_especiais_historico'),('restricoes_laborais'),
  ('onboarding_percepcao_cultural'),('onboarding_respostas')
) AS t(tabela)
ORDER BY t.tabela;
