-- =========================================================
-- QA — agendamento automático dos Testes de tela (Cypress)
--
-- ESPELHO do agendamento do Motor (qa_agendamento_dias), mas para a
-- suíte Cypress. A diferença essencial:
--
--   · O Motor roda a bateria DENTRO do banco (qa_rodar_agendada) —
--     é SQL puro, o cron executa e pronto.
--   · O Cypress NÃO roda no banco: ele abre o site de teste num
--     navegador de verdade, na esteira do GitHub Actions. O banco não
--     tem como "rodar Cypress". O que ele PODE fazer é PEDIR à esteira
--     que rode — exatamente o mesmo gesto de publicar uma mudança.
--
-- COMO PEDE: a API do GitHub tem o endpoint workflow_dispatch. Um
-- POST autenticado dispara o workflow staging.yml (que constrói o site
-- de teste e roda a suíte). O disparo sai daqui por net.http_post
-- (pg_net), no horário marcado, via um job de pg_cron por dia ligado.
--
-- PROTEÇÃO DE AMBIENTE (mesmo princípio do dispatch dos agentes):
--   O token do GitHub NÃO vive no código — vive em app_config. Sem o
--   token configurado, a rotina não chama ninguém e apenas avisa no
--   log. Assim um banco novo (ou o staging) nunca dispara nada por
--   acidente; só dispara o ambiente onde alguém colou o token de
--   propósito.
--
-- Nomes dos jobs: 'qa-e2e-dia-N' (N = 0..6). Não colidem com os do
-- Motor ('qa-bateria-dia-N'), que são sincronizados por outra função.
-- =========================================================

-- ─────────────────────────────────────────────────────────
-- 0) app_config já existe (20260810100000). Documentamos as chaves
--    que esta rotina lê. NENHUM valor é semeado aqui — o token é
--    colado à mão no ambiente que deve disparar (staging e/ou prod).
--      github_dispatch_token     (obrigatório p/ disparar) fine-grained PAT, Actions:write
--      github_dispatch_repo      (opcional) padrão 'YourEyes-dev/youreyesnovo'
--      github_dispatch_workflow  (opcional) padrão 'staging.yml'
--      github_dispatch_ref       (opcional) padrão 'main'
-- ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.app_config (
  chave text PRIMARY KEY,
  valor text NOT NULL,
  atualizado_em timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_config FROM PUBLIC, anon, authenticated;

-- ─────────────────────────────────────────────────────────
-- 1) A GRADE — uma linha por dia da semana (7 linhas fixas)
-- ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.qa_agendamento_e2e_dias (
  dia_semana int PRIMARY KEY CHECK (dia_semana BETWEEN 0 AND 6),  -- 0=dom..6=sab
  ligado     boolean NOT NULL DEFAULT false,
  hora       int NOT NULL DEFAULT 3 CHECK (hora BETWEEN 0 AND 23),
  minuto     int NOT NULL DEFAULT 0 CHECK (minuto BETWEEN 0 AND 59)
);

INSERT INTO public.qa_agendamento_e2e_dias (dia_semana, ligado, hora, minuto)
SELECT d, false, 3, 0 FROM generate_series(0,6) d
ON CONFLICT (dia_semana) DO NOTHING;

ALTER TABLE public.qa_agendamento_e2e_dias ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "QA agendamento e2e: apenas superadmin" ON public.qa_agendamento_e2e_dias;
CREATE POLICY "QA agendamento e2e: apenas superadmin"
  ON public.qa_agendamento_e2e_dias FOR ALL
  USING (public.is_superadmin(auth.uid()))
  WITH CHECK (public.is_superadmin(auth.uid()));

-- ─────────────────────────────────────────────────────────
-- 2) O QUE O CRON CHAMA — pede à esteira que rode a suíte
--    Sem checagem de superadmin: quem chama é o relógio (auth.uid()
--    é NULL no cron), igual a qa_rodar_agendada.
-- ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_e2e_disparar_esteira()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_token    text;
  v_repo     text;
  v_workflow text;
  v_ref      text;
BEGIN
  SELECT valor INTO v_token    FROM public.app_config WHERE chave = 'github_dispatch_token';
  SELECT valor INTO v_repo     FROM public.app_config WHERE chave = 'github_dispatch_repo';
  SELECT valor INTO v_workflow FROM public.app_config WHERE chave = 'github_dispatch_workflow';
  SELECT valor INTO v_ref      FROM public.app_config WHERE chave = 'github_dispatch_ref';

  -- Proteção de ambiente: sem token, não chama ninguém (avisa no log).
  IF v_token IS NULL OR btrim(v_token) = '' THEN
    RAISE NOTICE 'qa_e2e_disparar_esteira: app_config sem github_dispatch_token — nenhuma corrida disparada (proteção de ambiente).';
    RETURN;
  END IF;

  -- Padrões públicos (o repo/workflow já aparecem no código do painel e
  -- na esteira); só o token é segredo. Podem ser sobrescritos por app_config.
  v_repo     := COALESCE(NULLIF(btrim(v_repo),     ''), 'YourEyes-dev/youreyesnovo');
  v_workflow := COALESCE(NULLIF(btrim(v_workflow), ''), 'staging.yml');
  v_ref      := COALESCE(NULLIF(btrim(v_ref),      ''), 'main');

  PERFORM net.http_post(
    url := format('https://api.github.com/repos/%s/actions/workflows/%s/dispatches',
                  v_repo, v_workflow),
    headers := jsonb_build_object(
      'Accept',               'application/vnd.github+json',
      'Authorization',        'Bearer ' || v_token,
      'X-GitHub-Api-Version', '2022-11-28',
      'User-Agent',           'youreyes-qa-esteira',
      'Content-Type',         'application/json'
    ),
    body := jsonb_build_object('ref', v_ref)
  );

  RAISE NOTICE 'qa_e2e_disparar_esteira: pedido de corrida enviado à esteira (% / % @ %).',
    v_repo, v_workflow, v_ref;
END $$;

COMMENT ON FUNCTION public.qa_e2e_disparar_esteira() IS
  'Chamada pelo pg_cron. No horário configurado, pede à esteira do GitHub (workflow_dispatch) que rode a suíte Cypress. Token vem de app_config.github_dispatch_token; sem ele, não dispara.';

-- Esta função NÃO tem trava de superadmin (quem a chama é o relógio, sem
-- auth.uid()). Por isso NÃO a exponha a authenticated: só o cron (que roda
-- como o dono, postgres) precisa executá-la. Sem esta trava, qualquer usuário
-- logado poderia disparar corridas na esteira à vontade.
REVOKE EXECUTE ON FUNCTION public.qa_e2e_disparar_esteira() FROM PUBLIC, anon, authenticated;

-- ─────────────────────────────────────────────────────────
-- 3) SINCRONIZAR — remove os jobs 'qa-e2e-dia-%' e recria os ligados
--    Converte o horário/dia escolhido (Brasil) para UTC, que é o que
--    o cron usa — mesma correção de fuso do Motor (20260717140000).
-- ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_cron_sincronizar_e2e()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, cron
AS $$
DECLARE
  d record;
  v_utc timestamptz;
  v_ligados int := 0;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN
    RAISE EXCEPTION 'Apenas superadmin pode configurar o agendamento.';
  END IF;

  PERFORM cron.unschedule(jobname)
  FROM cron.job
  WHERE jobname LIKE 'qa-e2e-dia-%';

  FOR d IN SELECT * FROM public.qa_agendamento_e2e_dias WHERE ligado ORDER BY dia_semana
  LOOP
    -- 2024-01-07 é um domingo (dow=0); somamos d.dia_semana p/ chegar no dia.
    v_utc := (
      (date '2024-01-07' + d.dia_semana)::timestamp
      + make_interval(hours => d.hora, mins => d.minuto)
    ) AT TIME ZONE 'America/Sao_Paulo';   -- horário de SP -> timestamptz (UTC)

    PERFORM cron.schedule(
      'qa-e2e-dia-' || d.dia_semana,
      format('%s %s * * %s',
             extract(minute from v_utc AT TIME ZONE 'UTC')::int,
             extract(hour   from v_utc AT TIME ZONE 'UTC')::int,
             extract(dow    from v_utc AT TIME ZONE 'UTC')::int),
      $cmd$SELECT public.qa_e2e_disparar_esteira()$cmd$
    );
    v_ligados := v_ligados + 1;
  END LOOP;

  IF v_ligados = 0 THEN
    RETURN 'Nenhum dia agendado. A suíte só roda quando você publica uma mudança.';
  END IF;
  RETURN format('%s dia(s) agendado(s), no seu horário (Brasília).', v_ligados);
END $$;

REVOKE EXECUTE ON FUNCTION public.qa_cron_sincronizar_e2e() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.qa_cron_sincronizar_e2e() TO authenticated;

-- ─────────────────────────────────────────────────────────
-- 4) A TELA LÊ a grade inteira (7 dias) + a próxima corrida
-- ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_agendamento_e2e_ler_dias()
RETURNS TABLE(dia_semana int, dia_nome text, ligado boolean, hora int, minuto int)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT d.dia_semana,
         (ARRAY['Domingo','Segunda','Terça','Quarta','Quinta','Sexta','Sábado'])[d.dia_semana + 1],
         d.ligado, d.hora, d.minuto
  FROM public.qa_agendamento_e2e_dias d
  WHERE public.is_superadmin(auth.uid())
  ORDER BY d.dia_semana;
$$;

REVOKE EXECUTE ON FUNCTION public.qa_agendamento_e2e_ler_dias() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.qa_agendamento_e2e_ler_dias() TO authenticated;

-- Próxima corrida, calculada no relógio de São Paulo.
CREATE OR REPLACE FUNCTION public.qa_agendamento_e2e_proxima()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT to_char(min(prox), 'DD/MM (Dy) HH24:MI')
  FROM (
    SELECT
      date_trunc('day', v_now)
        + make_interval(days =>
            ((d.dia_semana - extract(dow from v_now)::int) + 7) % 7
            + CASE
                WHEN ((d.dia_semana - extract(dow from v_now)::int) + 7) % 7 = 0
                     AND make_time(d.hora, d.minuto, 0) <= v_now::time
                THEN 7 ELSE 0 END)
        + make_interval(hours => d.hora, mins => d.minuto) AS prox
    FROM public.qa_agendamento_e2e_dias d,
         (SELECT timezone('America/Sao_Paulo', now()) AS v_now) t
    WHERE d.ligado AND public.is_superadmin(auth.uid())
  ) x;
$$;

REVOKE EXECUTE ON FUNCTION public.qa_agendamento_e2e_proxima() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.qa_agendamento_e2e_proxima() TO authenticated;

-- ─────────────────────────────────────────────────────────
-- 5) A TELA SALVA um dia (liga/desliga + horário) e re-sincroniza
-- ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_agendamento_e2e_salvar_dia(
  p_dia    int,
  p_ligado boolean,
  p_hora   int,
  p_minuto int
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, cron
AS $$
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN
    RAISE EXCEPTION 'Apenas superadmin pode configurar o agendamento.';
  END IF;
  IF p_dia NOT BETWEEN 0 AND 6 THEN
    RAISE EXCEPTION 'Dia invalido: %.', p_dia;
  END IF;
  IF p_hora NOT BETWEEN 0 AND 23 OR p_minuto NOT BETWEEN 0 AND 59 THEN
    RAISE EXCEPTION 'Horario invalido: %:%.', p_hora, p_minuto;
  END IF;

  UPDATE public.qa_agendamento_e2e_dias
  SET ligado = p_ligado, hora = p_hora, minuto = p_minuto
  WHERE dia_semana = p_dia;

  RETURN public.qa_cron_sincronizar_e2e();
END $$;

REVOKE EXECUTE ON FUNCTION public.qa_agendamento_e2e_salvar_dia(int, boolean, int, int) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.qa_agendamento_e2e_salvar_dia(int, boolean, int, int) TO authenticated;

-- ─────────────────────────────────────────────────────────
-- 6) Aplica no cron o estado atual da grade (roda como postgres aqui,
--    sem passar pela checagem de superadmin).
-- ─────────────────────────────────────────────────────────
DO $sync$
DECLARE d record; v_utc timestamptz;
BEGIN
  PERFORM cron.unschedule(jobname) FROM cron.job WHERE jobname LIKE 'qa-e2e-dia-%';

  FOR d IN SELECT * FROM public.qa_agendamento_e2e_dias WHERE ligado LOOP
    v_utc := ((date '2024-01-07' + d.dia_semana)::timestamp
              + make_interval(hours => d.hora, mins => d.minuto))
             AT TIME ZONE 'America/Sao_Paulo';
    PERFORM cron.schedule('qa-e2e-dia-'||d.dia_semana,
      format('%s %s * * %s',
             extract(minute from v_utc AT TIME ZONE 'UTC')::int,
             extract(hour   from v_utc AT TIME ZONE 'UTC')::int,
             extract(dow    from v_utc AT TIME ZONE 'UTC')::int),
      $cmd$SELECT public.qa_e2e_disparar_esteira()$cmd$);
  END LOOP;
END $sync$;

-- ─────────────────────────────────────────────────────────
-- Conferência
-- ─────────────────────────────────────────────────────────
SELECT 'grade e2e de 7 dias' AS item,
       (SELECT count(*)::text FROM public.qa_agendamento_e2e_dias) || ' dias' AS valor
UNION ALL SELECT 'dias ligados agora',
       (SELECT count(*)::text FROM public.qa_agendamento_e2e_dias WHERE ligado)
UNION ALL SELECT 'jobs de cron e2e',
       (SELECT count(*)::text FROM cron.job WHERE jobname LIKE 'qa-e2e-dia-%')
UNION ALL SELECT 'token do GitHub configurado',
       CASE WHEN EXISTS (SELECT 1 FROM public.app_config
                         WHERE chave='github_dispatch_token' AND btrim(valor) <> '')
            THEN 'sim' ELSE 'NÃO (o horário fica salvo, mas nada dispara)' END
UNION ALL SELECT 'disparar_esteira', COALESCE(to_regprocedure('public.qa_e2e_disparar_esteira()')::text,'FALHOU')
UNION ALL SELECT 'ler_dias',  COALESCE(to_regprocedure('public.qa_agendamento_e2e_ler_dias()')::text,'FALHOU')
UNION ALL SELECT 'salvar_dia',COALESCE(to_regprocedure('public.qa_agendamento_e2e_salvar_dia(int,boolean,int,int)')::text,'FALHOU')
UNION ALL SELECT 'proxima',   COALESCE(to_regprocedure('public.qa_agendamento_e2e_proxima()')::text,'FALHOU');
