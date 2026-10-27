-- ============================================================================
-- ENTREGA — Criticas de perfil: saude, humor/clima e avaliacao por perfil
-- (PERFIL-AUD-007/005/002). Cole no SQL Editor (TESTE/HOMOLOGACAO primeiro;
-- depois PRODUCAO, so apos "aprovado"). UMA transacao, idempotente.
-- Cria apenas politicas RESTRICTIVE de SELECT. NAO altera dado, NAO cria tabela
-- (por isso nao aciona o auto-RLS do editor nem precisa de backup). Cada tabela
-- e atomica: se uma falhar, so ela fica de fora e o aviso diz qual.
--
-- O QUE FECHA (RESTRICTIVE soma por E as politicas PERMISSIVE por tenant):
--   SAUDE (LGPD art. 11) — espelha a mae colaborador_condicoes_especiais:
--     restricoes_laborais            Atestados/SST/Colaboradores amplo, OU o
--                                    titular do afastamento (CPF), OU o proprio
--                                    trabalhador (trabalhador_id).
--     condicoes_especiais_historico  Atestados/SST/Colaboradores amplo OU o
--                                    titular (colaborador_id por CPF/admissao).
--   HUMOR/CLIMA (LGPD art. 11) — espelha bem_estar_respostas:
--     humor_diario / humor_historico Bem-estar/Psicossocial amplo (indicador
--                                    agregado) OU o PROPRIO (user_id).
--     onboarding_percepcao_cultural  Onboarding/Psicossocial/Bem-estar amplo OU
--                                    o titular (colaborador_id).
--     onboarding_respostas           Onboarding amplo OU o titular (via
--                                    onboarding_processos por CPF).
--   AVALIACAO (LGPD art. 46) — mesmo predicado do #913:
--     avaliacao_feedbacks            modulo avaliacoes amplo OU o avaliador da
--                                    resposta (desce por FK de avaliacao_respostas).
--     feedbacks                      Avaliacoes/Feedback amplo, OU quem registrou,
--                                    OU o proprio avaliado (colaborador_id).
--
-- Superadmin/dono ficam acima; sem perfil vinculado vale o legado por papel/tipo;
-- com perfil, o escopo amplo do modulo libera (perfil_permite_modulo /
-- perfil_amplo_sem_subordinados). Preserva-se SEMPRE o titular (autosservico).
-- INSERT/UPDATE do humor ja eram por titular; mexe-se so no SELECT.
--
-- Rode ANTES, se quiser, a consulta_perfil_criticas_leitura.sql (so leitura).
-- Termina com UMA conferencia SELECT (OK/FALTA por tabela).
-- ============================================================================
SET lock_timeout = '10s';

DO $cr$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('restricoes_laborais',
       $p$public.perfil_amplo_sem_subordinados(tenant_id, 'atestados', 'sst', 'colaboradores')
          OR (afastamento_id IS NOT NULL AND EXISTS (
                SELECT 1 FROM public.afastamentos af
                 WHERE af.id = afastamento_id
                   AND regexp_replace(COALESCE(af.colaborador_cpf, ''), '[^0-9]', '', 'g')
                       = public.cpf_do_usuario_logado()))
          OR (trabalhador_id IS NOT NULL AND (
                trabalhador_id = auth.uid()
                OR EXISTS (SELECT 1 FROM public.admissoes a
                            WHERE a.id = trabalhador_id
                              AND a.tenant_id = restricoes_laborais.tenant_id
                              AND regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g')
                                  = public.cpf_do_usuario_logado())))$p$),

      ('condicoes_especiais_historico',
       $p$public.perfil_amplo_sem_subordinados(tenant_id, 'colaboradores', 'atestados', 'sst')
          OR regexp_replace(COALESCE(colaborador_id, ''), '[^0-9]', '', 'g')
             = public.cpf_do_usuario_logado()
          OR EXISTS (SELECT 1 FROM public.admissoes a
                      WHERE a.id::text = colaborador_id
                        AND regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g')
                            = public.cpf_do_usuario_logado())$p$),

      ('humor_diario',
       $p$public.perfil_permite_modulo(tenant_id, 'bem_estar', 'psicossocial')
          OR user_id = auth.uid()$p$),

      ('humor_historico',
       $p$public.perfil_permite_modulo(tenant_id, 'bem_estar', 'psicossocial')
          OR user_id = auth.uid()$p$),

      ('onboarding_percepcao_cultural',
       $p$public.perfil_permite_modulo(tenant_id, 'onboarding', 'psicossocial', 'bem_estar')
          OR regexp_replace(COALESCE(colaborador_id, ''), '[^0-9]', '', 'g')
             = public.cpf_do_usuario_logado()
          OR EXISTS (SELECT 1 FROM public.admissoes a
                      WHERE a.id::text = colaborador_id
                        AND regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g')
                            = public.cpf_do_usuario_logado())$p$),

      ('onboarding_respostas',
       $p$public.perfil_permite_modulo(tenant_id, 'onboarding')
          OR EXISTS (SELECT 1 FROM public.onboarding_processos p
                      WHERE p.id = processo_id
                        AND regexp_replace(COALESCE(p.colaborador_cpf, ''), '[^0-9]', '', 'g')
                            = public.cpf_do_usuario_logado())$p$),

      ('avaliacao_feedbacks',
       $p$EXISTS (SELECT 1 FROM public.avaliacao_respostas r
                   WHERE r.id = resposta_id
                     AND (public.perfil_permite_modulo(r.tenant_id, 'avaliacoes')
                          OR r.avaliador_id = auth.uid()))$p$),

      ('feedbacks',
       $p$public.perfil_permite_modulo(tenant_id, 'avaliacoes', 'feedback')
          OR registrado_por = auth.uid()
          OR colaborador_id = auth.uid()::text
          OR regexp_replace(COALESCE(colaborador_id, ''), '[^0-9]', '', 'g')
             = public.cpf_do_usuario_logado()
          OR EXISTS (SELECT 1 FROM public.admissoes a
                      WHERE a.id::text = colaborador_id
                        AND a.tenant_id = feedbacks.tenant_id
                        AND regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g')
                            = public.cpf_do_usuario_logado())$p$)
    ) AS t(tabela, predicado)
  LOOP
    BEGIN
      IF to_regclass('public.' || r.tabela) IS NULL THEN
        RAISE NOTICE 'Criticas de perfil: tabela % nao existe nesta base; pulada.', r.tabela;
        CONTINUE;
      END IF;
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', r.tabela);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',
                     'perfil_restringe_leitura_' || r.tabela, r.tabela);
      EXECUTE format('CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR SELECT TO authenticated USING (%s)',
                     'perfil_restringe_leitura_' || r.tabela, r.tabela, r.predicado);
      RAISE NOTICE 'Criticas de perfil: leitura por perfil aplicada em %.', r.tabela;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ATENCAO: % ficou SEM a camada de leitura por perfil: %', r.tabela, SQLERRM;
    END;
  END LOOP;
END $cr$;

-- ── Conferencia final (o editor mostra so o ultimo resultado) ────────────────
-- Esperado: OK (RESTRICTIVE/SELECT) nas 8 tabelas. Qualquer "FALTA" indica que a
-- tabela ficou sem a camada (o furo continua aberto ali).
SELECT t.tabela,
       CASE WHEN to_regclass('public.' || t.tabela) IS NULL THEN 'tabela ausente nesta base'
            WHEN p.policyname IS NULL THEN 'FALTA'
            ELSE 'OK (' || p.permissive || '/' || p.cmd || ')' END AS camada_perfil
FROM (VALUES ('restricoes_laborais'), ('condicoes_especiais_historico'),
             ('humor_diario'), ('humor_historico'), ('onboarding_percepcao_cultural'),
             ('onboarding_respostas'), ('avaliacao_feedbacks'), ('feedbacks')) AS t(tabela)
LEFT JOIN pg_policies p
  ON p.schemaname = 'public'
 AND p.tablename = t.tabela
 AND p.policyname = 'perfil_restringe_leitura_' || t.tabela
ORDER BY t.tabela;
