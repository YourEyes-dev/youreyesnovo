-- =========================================================
-- QA / Cypress — histórico próprio, seleção por módulo e agendamento correto
--
-- 1) HISTÓRICO: a aba Cypress lia as últimas 20 execuções de TODOS os tipos
--    (qa_listar_baterias) e só depois filtrava as de tela. As rodadas do motor
--    SQL (agendadas + manuais) empurravam as do Cypress para fora da janela e
--    a aba parecia parada na última corrida "visível" (15/10), embora a
--    esteira tenha rodado e gravado todas. Função nova: só disparo='e2e'.
-- 2) MÓDULOS: lista os módulos que têm teste de tela (caso e2e com ponte
--    qa_cobertura_e2e) e quais specs cada um roda — alimenta o seletor
--    "rodar só estes módulos".
-- 3) AGENDAMENTO: o disparo agendado chamava o staging.yml (pipeline inteira:
--    migrations + functions + site + testes, ~1h) em vez do cypress.yml (só a
--    suíte contra o site já publicado). Passa a mirar cypress.yml; um valor
--    antigo 'staging.yml' em app_config é ignorado de propósito.
-- 4) STATUS: expõe à tela se o agendamento TEM como disparar (token + jobs).
-- Só funções (sem criar tabela).
-- =========================================================

-- ─────────────────────────────────────────────────────────
-- 1) Histórico só das corridas do Cypress
-- ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_listar_baterias_e2e(p_limite int DEFAULT 30)
RETURNS TABLE(
  id uuid, iniciada_em timestamptz, disparo text, modulo_path text,
  total int, passou int, falhou int, nao_implementado int, erro int,
  duracao_ms int, observacao text, disparada_por_nome text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $fn$
  SELECT e.id, e.iniciada_em, e.disparo::text, e.modulo_path,
         e.total, e.passou, e.falhou, e.nao_implementado, e.erro,
         e.duracao_ms, e.observacao, u.nome_completo
  FROM public.qa_execucoes e
  LEFT JOIN public.usuarios_base u ON u.id = e.disparada_por
  WHERE e.disparo::text = 'e2e'
    AND public.is_superadmin(auth.uid())
  ORDER BY e.iniciada_em DESC
  LIMIT p_limite;
$fn$;

REVOKE EXECUTE ON FUNCTION public.qa_listar_baterias_e2e(int) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.qa_listar_baterias_e2e(int) TO authenticated;

-- ─────────────────────────────────────────────────────────
-- 2) Módulos com teste de tela e os specs de cada um
-- ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_modulos_e2e()
RETURNS TABLE(modulo_path text, label text, testes bigint, specs text[])
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $fn$
  SELECT m.path, m.label, count(*), array_agg(DISTINCT cob.spec ORDER BY cob.spec)
  FROM public.qa_cobertura_e2e cob
  JOIN public.qa_casos_teste c ON c.codigo = cob.codigo AND c.nivel = 'e2e'
  JOIN public.qa_modulos m ON m.id = c.modulo_id
  WHERE cob.ativo
    AND public.is_superadmin(auth.uid())
  GROUP BY m.path, m.label
  ORDER BY m.path;
$fn$;

REVOKE EXECUTE ON FUNCTION public.qa_modulos_e2e() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.qa_modulos_e2e() TO authenticated;

-- ─────────────────────────────────────────────────────────
-- 3) Disparo agendado mira o cypress.yml (só a suíte), não o staging.yml
-- ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_e2e_disparar_esteira()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_token    text := (SELECT valor FROM public.app_config WHERE chave = 'github_dispatch_token');
  v_repo     text := (SELECT valor FROM public.app_config WHERE chave = 'github_dispatch_repo');
  v_workflow text := (SELECT valor FROM public.app_config WHERE chave = 'github_dispatch_workflow');
  v_ref      text := (SELECT valor FROM public.app_config WHERE chave = 'github_dispatch_ref');
BEGIN
  IF v_token IS NULL OR btrim(v_token) = '' THEN
    RAISE NOTICE 'qa_e2e_disparar_esteira: app_config sem github_dispatch_token — nenhuma corrida disparada (proteção de ambiente).';
    RETURN;
  END IF;

  v_repo     := COALESCE(NULLIF(btrim(v_repo), ''), 'YourEyes-dev/youreyesnovo');
  v_workflow := COALESCE(NULLIF(btrim(v_workflow), ''), 'cypress.yml');
  -- staging.yml refaria migrations/functions/site: não é "rodar os testes".
  IF v_workflow = 'staging.yml' THEN v_workflow := 'cypress.yml'; END IF;
  v_ref      := COALESCE(NULLIF(btrim(v_ref), ''), 'main');

  PERFORM net.http_post(
    url := format('https://api.github.com/repos/%s/actions/workflows/%s/dispatches',
                  v_repo, v_workflow),
    headers := jsonb_build_object(
      'Accept',               'application/vnd.github+json',
      'Authorization',        'Bearer ' || btrim(v_token),
      'X-GitHub-Api-Version', '2022-11-28',
      'User-Agent',           'youreyes-qa-esteira',
      'Content-Type',         'application/json'
    ),
    body := jsonb_build_object('ref', v_ref)
  );

  RAISE NOTICE 'qa_e2e_disparar_esteira: pedido de corrida enviado à esteira (% / % @ %).',
    v_repo, v_workflow, v_ref;
END $fn$;

REVOKE EXECUTE ON FUNCTION public.qa_e2e_disparar_esteira() FROM PUBLIC, anon, authenticated;

-- ─────────────────────────────────────────────────────────
-- 4) Status do agendamento: tem como disparar?
-- ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_agendamento_e2e_status()
RETURNS TABLE(token_configurado boolean, dias_ligados int, jobs_cron int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, cron
AS $fn$
DECLARE
  v_jobs int := 0;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN
    RETURN;
  END IF;
  BEGIN
    v_jobs := (SELECT count(*) FROM cron.job WHERE jobname LIKE 'qa-e2e-dia-%');
  EXCEPTION WHEN OTHERS THEN
    v_jobs := 0;
  END;
  RETURN QUERY SELECT
    EXISTS (SELECT 1 FROM public.app_config
            WHERE chave = 'github_dispatch_token' AND btrim(valor) <> ''),
    (SELECT count(*)::int FROM public.qa_agendamento_e2e_dias WHERE ligado),
    v_jobs;
END $fn$;

REVOKE EXECUTE ON FUNCTION public.qa_agendamento_e2e_status() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.qa_agendamento_e2e_status() TO authenticated;

-- ─────────────────────────────────────────────────────────
-- Conferência
-- ─────────────────────────────────────────────────────────
SELECT 'qa_listar_baterias_e2e' AS item,
       COALESCE(to_regprocedure('public.qa_listar_baterias_e2e(int)')::text, 'FALHOU') AS valor
UNION ALL SELECT 'qa_modulos_e2e',
       COALESCE(to_regprocedure('public.qa_modulos_e2e()')::text, 'FALHOU')
UNION ALL SELECT 'qa_agendamento_e2e_status',
       COALESCE(to_regprocedure('public.qa_agendamento_e2e_status()')::text, 'FALHOU')
UNION ALL SELECT 'corridas Cypress gravadas (total)',
       (SELECT count(*)::text FROM public.qa_execucoes WHERE disparo::text = 'e2e')
UNION ALL SELECT 'última corrida Cypress',
       COALESCE((SELECT to_char(max(iniciada_em) AT TIME ZONE 'America/Sao_Paulo','DD/MM HH24:MI')
                 FROM public.qa_execucoes WHERE disparo::text = 'e2e'), 'nenhuma')
UNION ALL SELECT 'token do GitHub no banco',
       CASE WHEN EXISTS (SELECT 1 FROM public.app_config
                         WHERE chave='github_dispatch_token' AND btrim(valor) <> '')
            THEN 'sim' ELSE 'NÃO (agendamento não dispara)' END
UNION ALL SELECT 'dias de agendamento ligados',
       (SELECT count(*)::text FROM public.qa_agendamento_e2e_dias WHERE ligado);
