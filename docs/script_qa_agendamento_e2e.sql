-- =====================================================================
-- YourEyes — Agendar os Testes de tela (Cypress) para rodar sozinhos
--
-- COLE ESTE ARQUIVO INTEIRO no SQL Editor do Supabase e execute UMA vez.
-- É idempotente: pode rodar de novo sem medo (não duplica nem quebra).
--
-- O QUE ELE FAZ e por quê:
--   O painel de Testes automatizados ganhou, na aba "Testes Cypress",
--   a mesma opção de "Rodar automaticamente" que o Motor (banco) já
--   tinha. Mas a suíte Cypress NÃO roda dentro do banco — ela abre o
--   site de teste num navegador de verdade, na esteira do GitHub. O
--   que o banco pode fazer é, no horário marcado, PEDIR à esteira que
--   rode (o mesmo gesto de publicar uma mudança).
--
--   Este script instala a grade de horários (7 dias), as funções que a
--   tela usa e a rotina que, na hora certa, chama a esteira.
--
-- PROTEÇÃO DE AMBIENTE:
--   O token do GitHub que autoriza o disparo NÃO vai no código nem
--   neste script. Ele fica na tabela app_config. SEM o token, a rotina
--   não chama ninguém e apenas avisa no log — o horário fica salvo,
--   mas nada é disparado. Só dispara o ambiente onde alguém colar o
--   token de propósito (veja o passo 7, comentado, no fim).
-- =====================================================================

SET lock_timeout = '10s';

-- 1) app_config (já deve existir; recriada por segurança, idempotente) -
CREATE TABLE IF NOT EXISTS public.app_config (
  chave text PRIMARY KEY,
  valor text NOT NULL,
  atualizado_em timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_config FROM PUBLIC, anon, authenticated;

-- 2) A GRADE — uma linha por dia da semana (7 linhas fixas) ------------
CREATE TABLE IF NOT EXISTS public.qa_agendamento_e2e_dias (
  dia_semana int PRIMARY KEY CHECK (dia_semana BETWEEN 0 AND 6),
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

-- 3) O QUE O CRON CHAMA — pede à esteira que rode a suíte --------------
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

  IF v_token IS NULL OR btrim(v_token) = '' THEN
    RAISE NOTICE 'qa_e2e_disparar_esteira: app_config sem github_dispatch_token — nenhuma corrida disparada (proteção de ambiente).';
    RETURN;
  END IF;

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

-- Sem trava de superadmin (quem chama é o relógio). Por isso NÃO exposta
-- a authenticated: só o cron (dono = postgres) executa.
REVOKE EXECUTE ON FUNCTION public.qa_e2e_disparar_esteira() FROM PUBLIC, anon, authenticated;

-- 4) SINCRONIZAR — recria os jobs 'qa-e2e-dia-%' (Brasil -> UTC) -------
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

  PERFORM cron.unschedule(jobname) FROM cron.job WHERE jobname LIKE 'qa-e2e-dia-%';

  FOR d IN SELECT * FROM public.qa_agendamento_e2e_dias WHERE ligado ORDER BY dia_semana
  LOOP
    v_utc := ((date '2024-01-07' + d.dia_semana)::timestamp
              + make_interval(hours => d.hora, mins => d.minuto))
             AT TIME ZONE 'America/Sao_Paulo';
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

-- 5) A TELA LÊ a grade + a próxima corrida ----------------------------
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

-- 6) A TELA SALVA um dia e re-sincroniza ------------------------------
CREATE OR REPLACE FUNCTION public.qa_agendamento_e2e_salvar_dia(
  p_dia int, p_ligado boolean, p_hora int, p_minuto int
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

-- Aplica no cron o estado atual da grade (por item, sem abortar o todo) -
DO $sync$
DECLARE d record; v_utc timestamptz;
BEGIN
  BEGIN
    PERFORM cron.unschedule(jobname) FROM cron.job WHERE jobname LIKE 'qa-e2e-dia-%';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Nao foi possivel limpar jobs antigos: %', SQLERRM;
  END;

  FOR d IN SELECT * FROM public.qa_agendamento_e2e_dias WHERE ligado LOOP
    BEGIN
      v_utc := ((date '2024-01-07' + d.dia_semana)::timestamp
                + make_interval(hours => d.hora, mins => d.minuto))
               AT TIME ZONE 'America/Sao_Paulo';
      PERFORM cron.schedule('qa-e2e-dia-'||d.dia_semana,
        format('%s %s * * %s',
               extract(minute from v_utc AT TIME ZONE 'UTC')::int,
               extract(hour   from v_utc AT TIME ZONE 'UTC')::int,
               extract(dow    from v_utc AT TIME ZONE 'UTC')::int),
        $cmd$SELECT public.qa_e2e_disparar_esteira()$cmd$);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Falha ao agendar dia %: %', d.dia_semana, SQLERRM;
    END;
  END LOOP;
END $sync$;

-- 7) (OPCIONAL) LIGAR O DISPARO NESTE AMBIENTE ------------------------
--   Cole aqui o token do GitHub que VOCÊ criou (fine-grained PAT com
--   permissão Actions: Read and write neste repositório). Sem ele, tudo
--   acima fica instalado, mas nada é disparado. NÃO versionar o token.
--
--   Descomente e substitua <COLE_AQUI_O_TOKEN> antes de rodar:
--
-- INSERT INTO public.app_config (chave, valor) VALUES
--   ('github_dispatch_token', '<COLE_AQUI_O_TOKEN>')
-- ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor, atualizado_em = now();
--
--   (Opcionais — só se quiser mudar dos padrões
--    YourEyes-dev/youreyesnovo, staging.yml, main:)
-- INSERT INTO public.app_config (chave, valor) VALUES
--   ('github_dispatch_repo',     'YourEyes-dev/youreyesnovo'),
--   ('github_dispatch_workflow', 'staging.yml'),
--   ('github_dispatch_ref',      'main')
-- ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor, atualizado_em = now();

-- 8) CONFERÊNCIA (o editor mostra só o último resultado) --------------
SELECT
  (SELECT count(*) FROM public.qa_agendamento_e2e_dias)                         AS dias_na_grade,
  (SELECT count(*) FROM public.qa_agendamento_e2e_dias WHERE ligado)            AS dias_ligados,
  (SELECT count(*) FROM cron.job WHERE jobname LIKE 'qa-e2e-dia-%')             AS jobs_no_cron,
  CASE WHEN EXISTS (SELECT 1 FROM public.app_config
                    WHERE chave='github_dispatch_token' AND btrim(valor) <> '')
       THEN 'sim' ELSE 'NAO (passo 7 nao rodado — nada dispara ainda)' END      AS token_configurado,
  COALESCE(to_regprocedure('public.qa_e2e_disparar_esteira()')::text,'FALHOU')  AS fn_disparar,
  COALESCE(to_regprocedure('public.qa_agendamento_e2e_salvar_dia(int,boolean,int,int)')::text,'FALHOU') AS fn_salvar_dia,
  ''::text                                                                       AS erro_tecnico;
