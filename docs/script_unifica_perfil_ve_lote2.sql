-- ============================================================================
-- UNIFICAÇÃO 2º LOTE — avaliação, humor e ouvidoria no porteiro escopo-aware
-- (public.perfil_ve_cpf). Decisões da fundadora (27/10):
--   • avaliação: escopo setor vê avaliações de quem é do setor; preserva avaliador.
--   • humor/clima: compartilhável p/ intervenção — setor vê o humor de quem é do
--     setor; empresa_inteira vê todos; a pessoa sempre vê o próprio.
--   • ouvidoria: setor vê manifestação de autor do setor; preserva autor/
--     responsável/respondente. ANÔNIMA (autor_id nulo) só aparece p/ escopo amplo
--     (empresa+) — setor NÃO vê anônima (protege o sigilo da Lei 14.457).
-- Tightening (RESTRICTIVE só narrow); respeita setor=departamento, fail-closed
-- nos escopos não mapeados. NÃO altera dado. Idempotente.
-- ============================================================================

SET lock_timeout = '10s';

DO $lote2$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      -- AVALIAÇÃO: sujeito = avaliado; preserva o avaliador (Minha Caixa)
      ('avaliacao_respostas',
       $p$public.perfil_ve_colaborador_ref(tenant_id, avaliado_id, 'avaliacoes')
          OR avaliador_id = auth.uid()$p$),

      ('avaliacao_9box',
       $p$public.perfil_ve_colaborador_ref(tenant_id, colaborador_id, 'avaliacoes')
          OR avaliador_id = auth.uid()$p$),

      -- feedbacks de avaliação: herdam da resposta-pai (que já é escopo-aware)
      ('avaliacao_feedbacks',
       $p$EXISTS (SELECT 1 FROM public.avaliacao_respostas r WHERE r.id = resposta_id)$p$),

      ('feedbacks',
       $p$public.perfil_ve_colaborador_ref(tenant_id, colaborador_id, 'avaliacoes', 'feedback')
          OR registrado_por = auth.uid()$p$),

      -- HUMOR / CLIMA: sujeito = a pessoa (user_id -> cpf -> setor); próprio sempre
      ('humor_diario',
       $p$public.perfil_ve_cpf(tenant_id,
            (SELECT ub.cpf FROM public.usuarios_base ub
              WHERE ub.auth_user_id = humor_diario.user_id
                AND ub.tenant_id = humor_diario.tenant_id LIMIT 1),
            'bem_estar', 'psicossocial')
          OR humor_diario.user_id = auth.uid()$p$),

      ('humor_historico',
       $p$public.perfil_ve_cpf(tenant_id,
            (SELECT ub.cpf FROM public.usuarios_base ub
              WHERE ub.auth_user_id = humor_historico.user_id
                AND ub.tenant_id = humor_historico.tenant_id LIMIT 1),
            'bem_estar', 'psicossocial')
          OR humor_historico.user_id = auth.uid()$p$),

      -- OUVIDORIA: autor por setor (autor_id -> cpf); anônima só p/ escopo amplo
      -- (perfil_ve_cpf com cpf nulo só libera empresa_inteira+). Preserva autor/
      -- responsável/respondente.
      ('ouvidoria',
       $p$public.perfil_ve_cpf(tenant_id,
            (SELECT ub.cpf FROM public.usuarios_base ub
              WHERE ub.auth_user_id = ouvidoria.autor_id
                AND ub.tenant_id = ouvidoria.tenant_id LIMIT 1),
            'ouvidoria')
          OR ouvidoria.autor_id = auth.uid()
          OR ouvidoria.responsavel_id = auth.uid()
          OR ouvidoria.respondido_por = auth.uid()$p$)
    ) AS t(tabela, predicado)
  LOOP
    IF to_regclass('public.' || r.tabela) IS NULL THEN
      RAISE NOTICE 'LOTE2: % inexistente, pulando.', r.tabela; CONTINUE;
    END IF;
    BEGIN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', r.tabela);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',
                     'perfil_restringe_leitura_' || r.tabela, r.tabela);
      EXECUTE format('CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR SELECT TO authenticated USING (%s)',
                     'perfil_restringe_leitura_' || r.tabela, r.tabela, r.predicado);
      RAISE NOTICE 'LOTE2: % migrada para perfil_ve_cpf.', r.tabela;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'LOTE2: FALHA em % -> %', r.tabela, SQLERRM;
    END;
  END LOOP;
END
$lote2$;

SELECT t.tabela,
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_policies p
         WHERE p.schemaname = 'public' AND p.tablename = t.tabela
           AND p.policyname = 'perfil_restringe_leitura_' || t.tabela
           AND p.permissive = 'RESTRICTIVE' AND p.cmd = 'SELECT'
           AND (position('perfil_ve_' IN COALESCE(p.qual, '')) > 0
                OR position('avaliacao_respostas' IN COALESCE(p.qual, '')) > 0)
       ) THEN 'OK (escopo-aware)' ELSE 'FALTA' END AS leitura_escopo_aware
FROM (VALUES
  ('avaliacao_respostas'),('avaliacao_9box'),('avaliacao_feedbacks'),
  ('feedbacks'),('humor_diario'),('humor_historico'),('ouvidoria')
) AS t(tabela)
ORDER BY t.tabela;
