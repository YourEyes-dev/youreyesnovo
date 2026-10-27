-- ============================================================================
-- CRITICAS DE PERFIL (PERFIL-AUD-007/005/002) — LEITURA POR PERFIL
--
-- Achado da auditoria de perfil (PERFIL-AUD-*): uma classe de tabelas de
-- registro-sujeito (um trabalhador por linha) com tenant_id tinha apenas a
-- politica PERMISSIVE por tenant e NENHUMA camada RESTRICTIVE por perfil
-- (perfil_restringe_leitura_*). Resultado: qualquer membro autenticado da
-- empresa lia esses dados pela API, mesmo sem o modulo da area. Mesma classe
-- do DASH-PERFIL-01 (#913), que fechou avaliacao_respostas, avaliacao_9box e
-- metas; aqui fecham-se as CRITICAS restantes.
--
-- Esta entrega fecha (RESTRICTIVE soma-se por E as PERMISSIVE por tenant):
--   SAUDE (LGPD art. 11) — espelha a mae colaborador_condicoes_especiais
--     (20261023210000):
--     restricoes_laborais            Atestados/SST/Colaboradores amplo, OU o
--                                    titular do afastamento (por CPF), OU o
--                                    proprio trabalhador (trabalhador_id).
--     condicoes_especiais_historico  Atestados/SST/Colaboradores amplo OU o
--                                    titular (colaborador_id por CPF/admissao).
--   HUMOR/CLIMA (LGPD art. 11) — espelha bem_estar_respostas (20260409134833):
--     humor_diario / humor_historico Bem-estar/Psicossocial amplo (indicador
--                                    agregado) OU o PROPRIO (user_id). INSERT/
--                                    UPDATE ja eram por titular.
--     onboarding_percepcao_cultural  Onboarding/Psicossocial/Bem-estar amplo OU
--                                    o titular (colaborador_id por CPF/admissao).
--     onboarding_respostas           Onboarding amplo OU o titular (via
--                                    onboarding_processos por CPF).
--   AVALIACAO (LGPD art. 46) — mesmo predicado do #913 para avaliacao:
--     avaliacao_feedbacks            desce por FK de avaliacao_respostas (texto
--                                    de feedback por criterio): modulo
--                                    avaliacoes amplo OU o avaliador da resposta.
--     feedbacks                      Avaliacoes/Feedback amplo, OU quem registrou
--                                    (registrado_por), OU o proprio avaliado
--                                    (colaborador_id por uid/CPF/admissao).
--
-- Quem legitimamente le continua lendo: superadmin e dono ficam acima do
-- perfil; sem perfil vinculado vale o legado por papel/tipo; com perfil, o
-- escopo amplo do modulo libera — tudo em perfil_permite_modulo /
-- perfil_amplo_sem_subordinados. Preserva-se SEMPRE o titular (autosservico) e,
-- no humor, o indicador agregado continua para quem tem o modulo.
--
-- Nao altera dado. Nao cria tabela. Idempotente. Atomico por tabela (se uma
-- falhar, so ela fica de fora e o aviso diz qual).
-- ============================================================================

SET lock_timeout = '10s';

DO $cr$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      -- ── SAUDE ──────────────────────────────────────────────────────────────
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

      -- ── HUMOR / CLIMA ────────────────────────────────────────────────────────
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

      -- ── AVALIACAO ──────────────────────────────────────────────────────────
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

-- ── Conferencia ──────────────────────────────────────────────────────────────
DO $verifica$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n
  FROM pg_policies
  WHERE schemaname = 'public'
    AND permissive = 'RESTRICTIVE'
    AND cmd = 'SELECT'
    AND policyname LIKE 'perfil_restringe_leitura_%'
    AND tablename IN ('restricoes_laborais', 'condicoes_especiais_historico',
                      'humor_diario', 'humor_historico', 'onboarding_percepcao_cultural',
                      'onboarding_respostas', 'avaliacao_feedbacks', 'feedbacks')
    AND to_regclass('public.' || tablename) IS NOT NULL;

  RAISE NOTICE 'Criticas de perfil: % de 8 tabelas com leitura condicionada ao perfil.', v_n;
END $verifica$;
