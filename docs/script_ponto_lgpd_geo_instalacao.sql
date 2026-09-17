-- ============================================================================
-- PONTO-253 — PASSO 2 de 2: retencao da geolocalizacao (LGPD art. 15 e 16)
--
-- RODE O PASSO 1 ANTES (script_ponto_lgpd_geo_medicao.sql). Ele diz quantas
-- batidas serao alcancadas e confere a pre-condicao do hash. Este arquivo se
-- recusa a instalar se a pre-condicao nao valer.
--
-- O QUE ESTE ARQUIVO FAZ: instala a maquinaria e a agenda. NAO expurga nada
-- agora. A conferencia final diz quantas batidas serao alcancadas na primeira
-- passada.
--
-- O QUE ESTE ARQUIVO NAO FAZ, E PRECISA FICAR CLARO: depois de colado, o
-- expurgo passa a acontecer — no domingo seguinte, as 04:41, pela agenda. Se
-- preferir ver acontecer sob supervisao, rode a mao antes disso:
--     SELECT public.ponto_expurgar_geolocalizacao();
-- Essa e a porta de uma via so. Nao ha volta para a coordenada apagada.
--
-- O QUE E APAGADO: latitude, longitude, endereco e distancia das batidas mais
-- antigas que o prazo. A MARCACAO PERMANECE INTEIRA — data, hora, tipo, CPF,
-- NSR, hash. Nenhuma linha e apagada. A marcacao tem prazo de guarda proprio
-- (CLT art. 74); a coordenada nao, e a finalidade dela se esgota quando a
-- batida e conferida.
--
-- PRAZO: 180 dias por tenant, configuravel entre 30 e 1825 em
-- ponto_retencao_config. Para mudar antes da primeira passada:
--     UPDATE public.ponto_retencao_config SET geolocalizacao_dias = 365;
--
-- IMUTABILIDADE: conferido que o gatilho de imutabilidade da marcacao
-- (Portaria MTP 671/2021) barra data, hora, tipo, CPF, colaborador e NSR — e
-- NAO barra as colunas de geolocalizacao. O expurgo convive com ela.
--
-- POR QUE NAO HA COPIA DE RESGATE, contrariando a regra da casa: copiar as
-- coordenadas antes de apaga-las guardaria exatamente o dado pessoal que se
-- quer eliminar, numa tabela nova e sem politica de acesso — o resgate viraria
-- o problema. O registro que a LGPD pede (art. 37) e de que o expurgo
-- ACONTECEU, e disso cuida a tabela ponto_expurgo_eventos, que fica com
-- tenant, criterio, data de corte e quantidade.
--
-- Idempotente. Roda inteiro em UMA transacao.
-- ============================================================================

SET lock_timeout = '10s';

DO $instala$
DECLARE
  v_hash_ok boolean;
BEGIN
  -- PRE-CONDICAO. Se o hash de integridade da marcacao dependesse da
  -- coordenada, zera-la quebraria a cadeia de todas as batidas antigas. Nesse
  -- caso nada e instalado.
  SELECT COALESCE(
           (SELECT NOT (prosrc ILIKE '%latitude%' OR prosrc ILIKE '%longitude%'
                        OR prosrc ILIKE '%endereco_geo%')
              FROM pg_proc WHERE proname = 'gerar_hash_marcacao' LIMIT 1), true)
    INTO v_hash_ok;

  IF NOT v_hash_ok THEN
    RAISE NOTICE 'PULADO — neste banco o hash da marcacao usa a coordenada. Expurga-la quebraria a cadeia de integridade das batidas antigas. Nada foi instalado.';
    RETURN;
  END IF;

  -- (1) Configuracao de retencao, por tenant.
  CREATE TABLE IF NOT EXISTS public.ponto_retencao_config (
    tenant_id uuid PRIMARY KEY,
    geolocalizacao_dias integer NOT NULL DEFAULT 180
      CHECK (geolocalizacao_dias BETWEEN 30 AND 1825),
    ativo boolean NOT NULL DEFAULT true,
    updated_at timestamptz NOT NULL DEFAULT now()
  );

  -- (2) Registro do expurgo — o art. 37 da LGPD exige poder demonstrar o que
  --     foi feito. Apagar sem registrar troca um problema por outro.
  CREATE TABLE IF NOT EXISTS public.ponto_expurgo_eventos (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL,
    executado_em timestamptz NOT NULL DEFAULT now(),
    criterio text NOT NULL,
    corte date NOT NULL,
    marcacoes_afetadas integer NOT NULL
  );

  GRANT SELECT, INSERT, UPDATE ON public.ponto_retencao_config TO authenticated;
  GRANT ALL    ON public.ponto_retencao_config TO service_role;
  GRANT SELECT ON public.ponto_expurgo_eventos TO authenticated;
  GRANT ALL    ON public.ponto_expurgo_eventos TO service_role;

  ALTER TABLE public.ponto_retencao_config ENABLE ROW LEVEL SECURITY;
  ALTER TABLE public.ponto_expurgo_eventos ENABLE ROW LEVEL SECURITY;

  -- As politicas so entram se a funcao de tenant existir; sem ela, a tabela
  -- fica com RLS ligada e sem politica — fechada, que e o lado seguro.
  IF to_regprocedure('public.current_user_tenant_id()') IS NOT NULL THEN
    DROP POLICY IF EXISTS "Tenant gerencia ponto_retencao_config" ON public.ponto_retencao_config;
    CREATE POLICY "Tenant gerencia ponto_retencao_config" ON public.ponto_retencao_config
      FOR ALL TO authenticated
      USING (tenant_id = public.current_user_tenant_id())
      WITH CHECK (tenant_id = public.current_user_tenant_id());

    DROP POLICY IF EXISTS "Tenant le ponto_expurgo_eventos" ON public.ponto_expurgo_eventos;
    CREATE POLICY "Tenant le ponto_expurgo_eventos" ON public.ponto_expurgo_eventos
      FOR SELECT TO authenticated
      USING (tenant_id = public.current_user_tenant_id());
  ELSE
    RAISE NOTICE 'current_user_tenant_id() ausente — tabelas criadas com RLS ligada e sem politica (fechadas). Instale a funcao de tenant e recoloque as politicas.';
  END IF;

  -- (3) A rotina. Fica DENTRO da guarda: se a pre-condicao do hash nao
  --     valesse, nao faz sentido instalar a rotina que apaga a coordenada.
  EXECUTE $def$
  CREATE OR REPLACE FUNCTION public.ponto_expurgar_geolocalizacao(p_tenant_id uuid DEFAULT NULL)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $expurgo$
  DECLARE
    r RECORD;
    v_corte date;
    v_n int;
    v_total int := 0;
    v_tenants int := 0;
  BEGIN
    FOR r IN
      SELECT c.tenant_id, c.geolocalizacao_dias
      FROM public.ponto_retencao_config c
      WHERE c.ativo = true
        AND (p_tenant_id IS NULL OR c.tenant_id = p_tenant_id)
    LOOP
      v_corte := (CURRENT_DATE - r.geolocalizacao_dias)::date;

      -- Zera SOMENTE as colunas de geolocalizacao. A linha permanece.
      UPDATE public.ponto_marcacoes m
         SET latitude = NULL, longitude = NULL,
             endereco_geolocalizacao = NULL,
             distancia_metros = NULL
       WHERE m.tenant_id = r.tenant_id
         AND m.data_marcacao < v_corte
         AND (m.latitude IS NOT NULL OR m.longitude IS NOT NULL
              OR m.endereco_geolocalizacao IS NOT NULL);
      GET DIAGNOSTICS v_n = ROW_COUNT;

      IF v_n > 0 THEN
        INSERT INTO public.ponto_expurgo_eventos (tenant_id, criterio, corte, marcacoes_afetadas)
        VALUES (r.tenant_id,
                format('geolocalizacao apos %s dias (LGPD art. 16)', r.geolocalizacao_dias),
                v_corte, v_n);
      END IF;

      v_total := v_total + v_n;
      v_tenants := v_tenants + 1;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'tenants', v_tenants, 'marcacoes_anonimizadas', v_total);
  END;
  $expurgo$;
  $def$;

  EXECUTE 'REVOKE EXECUTE ON FUNCTION public.ponto_expurgar_geolocalizacao(uuid) FROM PUBLIC, anon';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.ponto_expurgar_geolocalizacao(uuid) TO authenticated, service_role';
  EXECUTE 'COMMENT ON FUNCTION public.ponto_expurgar_geolocalizacao(uuid) IS ''Zera latitude, longitude, endereco e distancia das marcacoes mais antigas que o prazo de ponto_retencao_config. A marcacao permanece: ela tem base legal e prazo de guarda proprios (CLT art. 74). Registra cada passada em ponto_expurgo_eventos (LGPD art. 37).''';

  RAISE NOTICE 'Tabelas e rotina de retencao prontas.';
END $instala$;

-- (4) Matricula os tenants que ja usam ponto e agenda a passada semanal.
DO $agenda$
DECLARE
  v_novos int := 0;
BEGIN
  IF to_regclass('public.ponto_retencao_config') IS NULL THEN
    RAISE NOTICE 'PULADO — a maquinaria nao foi instalada (ver aviso acima).';
    RETURN;
  END IF;

  INSERT INTO public.ponto_retencao_config (tenant_id)
  SELECT DISTINCT m.tenant_id FROM public.ponto_marcacoes m
  ON CONFLICT (tenant_id) DO NOTHING;
  GET DIAGNOSTICS v_novos = ROW_COUNT;
  RAISE NOTICE 'Tenants matriculados agora: % (os ja existentes mantiveram o prazo que tinham).', v_novos;

  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('ponto-expurgo-geo')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ponto-expurgo-geo');
    PERFORM cron.schedule('ponto-expurgo-geo', '41 4 * * 0',
                          'SELECT public.ponto_expurgar_geolocalizacao();');
    RAISE NOTICE 'Agendado: domingos as 04:41. A PRIMEIRA PASSADA VAI APAGAR COORDENADAS.';
  ELSE
    RAISE NOTICE 'pg_cron ausente — nada foi agendado. Chame ponto_expurgar_geolocalizacao() pela aplicacao.';
  END IF;
END $agenda$;

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | t | t | <n> | <n> | OK
--   hash_ignora_geo  : a pre-condicao valeu (se 'f', nada foi instalado)
--   tem_config       : a tabela de prazos existe
--   tem_rotina       : a rotina de expurgo existe
--   tem_registro     : a tabela de registro do expurgo existe
--   tenants_ativos   : quantos tenants tem prazo configurado e ativo
--   alvo_1a_passada  : quantas batidas serao alcancadas na primeira passada
--
-- alvo_1a_passada e o numero que vai virar coordenada apagada. Se ele for
-- maior do que o esperado, AUMENTE o prazo antes que a agenda rode:
--     UPDATE public.ponto_retencao_config SET geolocalizacao_dias = 365;
-- ---------------------------------------------------------------------------
WITH x AS MATERIALIZED (
  SELECT
    COALESCE(substring((SELECT valor FROM public.app_config WHERE chave = 'supabase_url')
                       FROM 'https?://([a-z0-9]+)\.'), '(sem supabase_url)')  AS projeto,
    COALESCE((SELECT NOT (prosrc ILIKE '%latitude%' OR prosrc ILIKE '%longitude%'
                          OR prosrc ILIKE '%endereco_geo%')
                FROM pg_proc WHERE proname = 'gerar_hash_marcacao' LIMIT 1), true) AS hash_ignora_geo,
    (to_regclass('public.ponto_retencao_config') IS NOT NULL)                 AS tem_config,
    (to_regprocedure('public.ponto_expurgar_geolocalizacao(uuid)') IS NOT NULL) AS tem_rotina,
    (to_regclass('public.ponto_expurgo_eventos') IS NOT NULL)                 AS tem_registro,
    -- Contas feitas por consulta dinamica: onde a instalacao foi PULADA a
    -- tabela de prazos nao existe, e nomea-la aqui faria o arquivo terminar
    -- num erro de "relation does not exist" em vez do aviso claro.
    CASE WHEN to_regclass('public.ponto_retencao_config') IS NULL THEN 0
         ELSE (xpath('/row/c/text()', query_to_xml(
                'SELECT count(*) AS c FROM public.ponto_retencao_config WHERE ativo',
                false, true, '')))[1]::text::bigint END                       AS tenants_ativos,
    CASE WHEN to_regclass('public.ponto_retencao_config') IS NULL THEN 0
         ELSE (xpath('/row/c/text()', query_to_xml(
                'SELECT COALESCE(sum((SELECT count(*) FROM public.ponto_marcacoes m
                                       WHERE m.tenant_id = rc.tenant_id
                                         AND m.data_marcacao < CURRENT_DATE - rc.geolocalizacao_dias
                                         AND (m.latitude IS NOT NULL OR m.longitude IS NOT NULL
                                              OR m.endereco_geolocalizacao IS NOT NULL))), 0) AS c
                   FROM public.ponto_retencao_config rc WHERE rc.ativo',
                false, true, '')))[1]::text::bigint END                       AS alvo_1a_passada
)
SELECT projeto, hash_ignora_geo, tem_config, tem_rotina, tem_registro,
       tenants_ativos, alvo_1a_passada,
       CASE
         WHEN NOT hash_ignora_geo THEN 'PULADO — o hash usa a coordenada; nada foi instalado'
         WHEN tem_config AND tem_rotina AND tem_registro THEN 'OK'
         ELSE 'CONFERIR'
       END AS erro_tecnico
FROM x;
