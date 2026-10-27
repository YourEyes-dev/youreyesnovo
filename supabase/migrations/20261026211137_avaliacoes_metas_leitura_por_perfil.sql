-- ============================================================================
-- AVALIACOES E METAS — LEITURA POR PERFIL (DASH-PERFIL-01)
--
-- Achado (DASH-PERFIL-01, CRITICA, LGPD art. 11/art. 6): a Central de Pendencias
-- e os blocos da tela inicial (pendencias e indicadores) mostravam NOME do
-- colaborador + avaliacoes e metas a QUALQUER membro da empresa. O filtro por
-- perfil daquelas telas e cosmetico (so esconde no front); a protecao real e a
-- RLS de cada tabela. As tabelas de avaliacoes/metas tinham apenas a politica
-- PERMISSIVE por tenant (tenant_id = get_user_tenant_id()) e NENHUMA camada
-- RESTRICTIVE por perfil (perfil_restringe_leitura_*), ao contrario de
-- alertas_saude/afastamentos, que ja a tem.
--
-- Nota: afastamentos e afastamentos_pendencias (dois dos quatro citados na
-- demanda) JA receberam a camada em 20261023210000_saude_rh_leitura_por_perfil.
-- Faltavam as de avaliacao/metas. Esta entrega fecha:
--   avaliacao_respostas   nota, pontos fortes, areas de desenvolvimento de UMA pessoa
--   avaliacao_9box        9-box (desempenho x potencial) de um colaborador nominal
--   metas                 metas individuais de um colaborador nominal
-- avaliacao_9box nao estava na demanda original, mas e o mesmo tipo de vazamento
-- (registro-sujeito de um trabalhador, legivel por toda a empresa) e a sonda de
-- QA endurecida (PERFIL-003, migration de QA irma) passa a acusa-lo; fecha-se
-- junto em vez de silenciar.
--
-- Regra (RESTRICTIVE, soma-se as politicas PERMISSIVE por tenant ja existentes):
--   avaliacao_respostas  modulo 'avaliacoes' em escopo amplo, OU ser o AVALIADOR
--                        da resposta (avaliador_id = auth.uid()) — preserva a
--                        "Minha Caixa" de avaliacoes (auto/pares/360), onde um
--                        colaborador sem o modulo precisa ler a resposta que vai
--                        preencher. NAO se abre a resposta ao AVALIADO (evita
--                        expor a identidade/os comentarios dos pares; nenhuma
--                        tela le por avaliado_id hoje).
--   avaliacao_9box       modulo 'avaliacoes' em escopo amplo (calibracao e
--                        atividade de gestao; nenhuma tela de autosservico a le).
--   metas                modulo 'avaliacoes' ou 'metas' em escopo amplo, OU a
--                        PROPRIA meta individual (colaborador_id -> admissoes por
--                        CPF). Metas de equipe/departamento/empresa (sem
--                        colaborador_id) ficam so para quem tem o modulo.
--
-- Quem legitimamente le continua lendo: superadmin e dono ficam acima do perfil;
-- sem perfil vinculado vale o legado por papel/tipo; com perfil, o escopo amplo
-- do modulo libera — tudo isso ja embutido em perfil_permite_modulo. As telas de
-- /avaliacoes e /metas sao gated a esses modulos no front, entao quem chega nelas
-- passa na funcao. Nao ha VIEW sobre estas tabelas (o dashboard le as tabelas-base
-- direto), entao a politica na base ja protege e nao quebra nenhuma view.
--
-- Nao altera dado. Nao cria tabela. Idempotente. Atomico por tabela (se uma
-- falhar, so ela fica de fora e o aviso diz qual).
-- ============================================================================

SET lock_timeout = '10s';

DO $av$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('avaliacao_respostas',
       $p$public.perfil_permite_modulo(tenant_id, 'avaliacoes')
          OR avaliador_id = auth.uid()$p$),

      ('avaliacao_9box',
       $p$public.perfil_permite_modulo(tenant_id, 'avaliacoes')$p$),

      ('metas',
       $p$public.perfil_permite_modulo(tenant_id, 'avaliacoes', 'metas')
          OR (metas.colaborador_id IS NOT NULL
              AND public.cpf_do_usuario_logado() <> ''
              AND EXISTS (
                    SELECT 1 FROM public.admissoes a
                     WHERE a.id::text = metas.colaborador_id
                       AND a.tenant_id = metas.tenant_id
                       AND regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g')
                           = public.cpf_do_usuario_logado()))$p$)
    ) AS t(tabela, predicado)
  LOOP
    BEGIN
      IF to_regclass('public.' || r.tabela) IS NULL THEN
        RAISE NOTICE 'Avaliacoes/Metas: tabela % nao existe nesta base; pulada.', r.tabela;
        CONTINUE;
      END IF;
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', r.tabela);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',
                     'perfil_restringe_leitura_' || r.tabela, r.tabela);
      EXECUTE format('CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR SELECT TO authenticated USING (%s)',
                     'perfil_restringe_leitura_' || r.tabela, r.tabela, r.predicado);
      RAISE NOTICE 'Avaliacoes/Metas: leitura por perfil aplicada em %.', r.tabela;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ATENCAO: % ficou SEM a camada de leitura por perfil: %', r.tabela, SQLERRM;
    END;
  END LOOP;
END $av$;

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
    AND tablename IN ('avaliacao_respostas', 'avaliacao_9box', 'metas')
    AND to_regclass('public.' || tablename) IS NOT NULL;

  RAISE NOTICE 'Avaliacoes/Metas: % de 3 tabelas com leitura condicionada ao perfil.', v_n;
END $verifica$;
