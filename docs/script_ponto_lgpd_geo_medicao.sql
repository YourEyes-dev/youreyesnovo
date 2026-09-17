-- ============================================================================
-- PONTO-253 — PASSO 1 de 2: MEDIR antes de expurgar (SOMENTE LEITURA)
--
-- Nao cria, nao altera, nao apaga NADA. Existe para que a decisao do passo 2
-- seja tomada com o tamanho real na mao, e nao no escuro.
--
-- O QUE ESTA EM JOGO. A marcacao de ponto tem prazo de guarda proprio (CLT
-- art. 74). A COORDENADA nao: a finalidade dela se esgota quando a batida e
-- conferida. Guardar as duas coisas para sempre trata prazos distintos como um
-- so, e isso e retencao de dado pessoal alem do necessario (LGPD art. 15 e 16).
--
-- O expurgo do passo 2 zera latitude, longitude, endereco e distancia das
-- batidas mais antigas que o prazo. A MARCACAO PERMANECE — hora, tipo, CPF,
-- hash, tudo. Nenhuma linha e apagada.
--
-- PRE-CONDICAO QUE ESTE ARQUIVO CONFERE: o hash de integridade da marcacao nao
-- pode depender da coordenada. Se dependesse, zerar a coordenada quebraria a
-- cadeia de todas as batidas antigas — e ai o expurgo NAO pode ser aplicado
-- como esta. A coluna hash_ignora_geo abaixo responde isso NESTE banco. Ela
-- precisa vir 't'; vindo 'f', pare e me chame.
--
-- POR QUE NAO HA COPIA DE RESGATE no passo 2, contrariando a regra da casa:
-- copiar as coordenadas antes de apaga-las guardaria exatamente o dado pessoal
-- que se quer eliminar, so que numa tabela nova e sem politica de acesso. O
-- resgate viraria o problema. O registro que a LGPD pede (art. 37) e de que o
-- expurgo ACONTECEU, nao do que foi apagado — e disso o passo 2 cuida, na
-- tabela ponto_expurgo_eventos.
-- ============================================================================

WITH parametro AS MATERIALIZED (
  -- 180 dias e o padrao do projeto. Troque aqui para simular outro prazo.
  SELECT 180 AS dias
),
base AS MATERIALIZED (
  SELECT m.tenant_id,
         count(*)                                                    AS marcacoes,
         count(*) FILTER (WHERE m.latitude IS NOT NULL
                            OR m.longitude IS NOT NULL
                            OR m.endereco_geolocalizacao IS NOT NULL) AS com_geo,
         count(*) FILTER (WHERE (m.latitude IS NOT NULL
                            OR m.longitude IS NOT NULL
                            OR m.endereco_geolocalizacao IS NOT NULL)
                            AND m.data_marcacao < CURRENT_DATE - (SELECT dias FROM parametro)
                         )                                            AS seriam_expurgadas,
         min(m.data_marcacao) FILTER (WHERE m.latitude IS NOT NULL
                            OR m.longitude IS NOT NULL
                            OR m.endereco_geolocalizacao IS NOT NULL) AS geo_mais_antiga
    FROM public.ponto_marcacoes m
   GROUP BY m.tenant_id
)
SELECT
  COALESCE(substring((SELECT valor FROM public.app_config WHERE chave = 'supabase_url')
                     FROM 'https?://([a-z0-9]+)\.'), '(sem supabase_url)') AS projeto,
  (SELECT dias FROM parametro)                                             AS prazo_simulado_dias,
  (SELECT count(*) FROM base)                                              AS tenants_com_marcacao,
  COALESCE((SELECT sum(marcacoes) FROM base), 0)                           AS marcacoes_no_total,
  COALESCE((SELECT sum(com_geo) FROM base), 0)                             AS com_coordenada_hoje,
  COALESCE((SELECT sum(seriam_expurgadas) FROM base), 0)                   AS seriam_expurgadas_agora,
  (SELECT min(geo_mais_antiga) FROM base)                                  AS coordenada_mais_antiga,
  -- Pre-condicao: o hash nao pode depender da coordenada.
  COALESCE((SELECT NOT (prosrc ILIKE '%latitude%' OR prosrc ILIKE '%longitude%'
                        OR prosrc ILIKE '%endereco_geo%')
              FROM pg_proc WHERE proname = 'gerar_hash_marcacao' LIMIT 1), true)
                                                                           AS hash_ignora_geo,
  (to_regclass('public.ponto_retencao_config') IS NOT NULL)                AS ja_tem_config,
  (to_regprocedure('public.ponto_expurgar_geolocalizacao(uuid)') IS NOT NULL) AS ja_tem_rotina,
  CASE
    WHEN COALESCE((SELECT NOT (prosrc ILIKE '%latitude%' OR prosrc ILIKE '%longitude%'
                               OR prosrc ILIKE '%endereco_geo%')
                     FROM pg_proc WHERE proname = 'gerar_hash_marcacao' LIMIT 1), true) = false
      THEN 'PARE — o hash da marcacao usa a coordenada neste banco. Expurgar quebraria a cadeia de integridade.'
    WHEN COALESCE((SELECT sum(seriam_expurgadas) FROM base), 0) = 0
      THEN 'OK — nada a expurgar neste prazo. A rotina entra para valer daqui para frente.'
    ELSE 'OK — medido. Veja seriam_expurgadas_agora antes de aplicar o passo 2.'
  END                                                                      AS erro_tecnico;
