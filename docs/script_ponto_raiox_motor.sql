-- SOMENTE LEITURA — raio-X do motor do Ponto neste ambiente.
-- Nao cria, nao altera, nao apaga. Diz QUAL ambiente respondeu e se cada
-- correcao da fila esta de fato DENTRO do corpo das funcoes (existir com o
-- nome certo nao garante que a versao seja a corrigida).
WITH amb AS MATERIALIZED (
  SELECT COALESCE(
           substring((SELECT valor FROM public.app_config WHERE chave = 'supabase_url')
                     FROM 'https?://([a-z0-9]+)\.'),
           '(app_config sem supabase_url)') AS projeto
),
f AS MATERIALIZED (
  SELECT p.proname, p.prosrc
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
),
x AS MATERIALIZED (
  SELECT
    (SELECT projeto FROM amb) AS projeto,
    EXISTS (SELECT 1 FROM f WHERE proname='ponto_jornada_do_dia'
              AND prosrc ILIKE '%ponto_pre_assinalacao_do_dia%')        AS p57_jornada_le_declaracao,
    EXISTS (SELECT 1 FROM f WHERE proname='ponto_saldo_dias_competencia'
              AND prosrc ILIKE '%ponto_saldo_dias_competencia_bruto%')  AS p56_involucro_delega,
    EXISTS (SELECT 1 FROM f WHERE proname='ponto_saldo_dias_competencia_bruto'
              AND prosrc ILIKE '%ponto_apurar_ciclo_plantao_do_dia%')   AS p26_ciclo_12x36,
    EXISTS (SELECT 1 FROM f WHERE proname='ponto_feriados_trabalhados'
              AND prosrc ILIKE '%ponto_apurar_ciclo_plantao_do_dia%')   AS p53_rn23_feriado,
    EXISTS (SELECT 1 FROM f WHERE proname='apurar_banco_horas_colaborador'
              AND prosrc ILIKE '%ponto_banco_regime_vigente%')          AS p21_regime_vigente,
    EXISTS (SELECT 1 FROM f WHERE proname='apurar_banco_horas_colaborador'
              AND prosrc ILIKE '%prazo_compensacao%')                   AS p22_prazo_banco,
    EXISTS (SELECT 1 FROM f WHERE proname='calcular_he_adicional_noturno_dia'
              AND prosrc ILIKE '%ponto_cct_config%'
              AND prosrc ILIKE '%vigencia%')                            AS cct_vigencia,
    EXISTS (SELECT 1 FROM f WHERE proname='ponto_diario_supressao_intervalo'
              AND prosrc ILIKE '%pre_assinalado%')                      AS p18_supressao_intervalo,
    EXISTS (SELECT 1 FROM f WHERE proname='ponto_verificar_cadeia_hash'
              AND prosrc ILIKE '%hash_marcacao%' AND prosrc ILIKE '%anterior%') AS p55_cadeia_encadeada
)
SELECT projeto,
       p57_jornada_le_declaracao, p56_involucro_delega, p26_ciclo_12x36,
       p53_rn23_feriado, p21_regime_vigente, p22_prazo_banco,
       cct_vigencia, p18_supressao_intervalo, p55_cadeia_encadeada,
       ( p57_jornada_le_declaracao::int + p56_involucro_delega::int + p26_ciclo_12x36::int
       + p53_rn23_feriado::int + p21_regime_vigente::int + p22_prazo_banco::int
       + cct_vigencia::int + p18_supressao_intervalo::int + p55_cadeia_encadeada::int
       ) || ' de 9' AS correcoes_presentes
FROM x;
