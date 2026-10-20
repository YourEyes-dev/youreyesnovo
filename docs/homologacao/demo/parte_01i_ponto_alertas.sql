-- ============================================================================
-- HOMOLOGACAO — DEMONSTRACAO, PARTE 01i: Ponto: alertas e analises sugeridas
--
-- PARA QUE SERVE
-- Alertas de ponto (aba Compliance > Alertas CLT): limpa o ruido de gravacao em tempo real, carimba a
-- data do fato, resolve os antigos e deriva alertas de excesso de jornada, interjornada, horas extras
-- recorrentes, falta de marcacao e banco vencendo. Inclui analises sugeridas (texto pronto).
--
-- Tenant demo d3e00000-0000-4000-8000-000000000001 (Metalurgica Exemplo Ltda). Nenhum dado real.
-- SQL Editor do projeto de HOMOLOGACAO. Recusa rodar em qualquer outro banco
-- (so aceita a URL de app_config da homologacao ou do teste). Nunca na producao.
-- Idempotente, sem COMMIT, sem criar tabela, gatilhos do sistema continuam ligados.
--
-- ORDEM DE EXECUCAO (cada arquivo e uma colagem independente, sem COMMIT, e roda em menos de 30 s):
--   parte_00_base_empresa_demo.sql           (base: empresa, colaboradores, login)
--   parte_02a / parte_02b                    (recomendado ANTES: pessoas, ferias, atestados, afastamentos)
--   parte_01a_ponto_escalas_instrumentos.sql escalas 44h e 6x2, atribuicoes, feriados, acordo, CCT, regime do banco
--   parte_01b_ponto_marcacoes_mes1.sql       marcacoes e apuracao do 1o mes (3 meses atras)
--   parte_01c_ponto_marcacoes_mes2.sql       marcacoes e apuracao do 2o mes
--   parte_01d_ponto_marcacoes_mes3.sql       marcacoes e apuracao do 3o mes (mes passado)
--   parte_01e_ponto_marcacoes_mes_atual.sql  marcacoes e apuracao do mes corrente, ate hoje
--   parte_01f_ponto_ajustes.sql              solicitacoes de ajuste (pendentes, aprovadas, recusadas)
--   parte_01g_ponto_banco_fechamento.sql     banco de horas, fechamento e espelhos (2 meses mais antigos)
--   parte_01h_ponto_fluxos_gestao.sql        troca de turno, compensacao de falta, excedente, folgas
--   parte_01i_ponto_alertas.sql              alertas CLT e analises sugeridas
--   parte_01j_ponto_externo_arquivos.sql     links de ponto externo, REP-C, certificado, dossie, folha, AEJ
--   parte_01k_analise_jornada.sql            /analise-jornada (analises, alertas, documentos)
-- Todos sao idempotentes (rodar de novo nao duplica) e recusam rodar fora da homologacao/teste.
-- Rodar de novo perto da demonstracao completa os dias novos.
-- ============================================================================

SET lock_timeout = '10s';

DO $trava$
DECLARE
  v_url text;
BEGIN
  v_url := (SELECT valor FROM public.app_config WHERE chave = 'supabase_url' LIMIT 1);
  IF v_url IS NULL
     OR (v_url NOT ILIKE '%fgsblefvdabgdouipigz%' AND v_url NOT ILIKE '%bmehdgthciuvdbvutsdv%') THEN
    RAISE EXCEPTION
      'RECUSADO: app_config.supabase_url (%) nao e a homologacao nem o teste. Os dados de demonstracao nunca entram em producao.',
      COALESCE(v_url, '(vazio)');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.tenants WHERE id = 'd3e00000-0000-4000-8000-000000000001') THEN
    RAISE EXCEPTION 'Rode antes a parte 00 (base da empresa demo): o tenant demo nao existe.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ponto_fechamentos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND status = 'fechado') THEN
    RAISE EXCEPTION 'Rode antes a parte_01g (banco de horas e fechamento).';
  END IF;
END $trava$;

CREATE OR REPLACE FUNCTION public.demo_id(chave text)
RETURNS uuid
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT md5('youreyes-demo:' || chave)::uuid
$fn$;

CREATE OR REPLACE FUNCTION public.demo_ponto_rnd(seed text, m integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT (('x' || substr(md5(seed), 1, 7))::bit(28)::int) % GREATEST(m, 1)
$fn$;


-- ---------------------------------------------------------------------------
-- (10) Alertas de ponto (aba Compliance > Alertas CLT) e analises sugeridas
--      Os alertas de falta / atraso / intervalo nascem dos gatilhos do ponto, aqui
--      so se limpa o ruido de gravacao em tempo real, se carimba a data do fato e
--      se resolvem os antigos. Os demais tipos sao derivados dos proprios dias.
-- ---------------------------------------------------------------------------
-- Intervalo "suprimido" que so existiu enquanto o dia estava sendo batido
-- (almoco sem retorno ainda) e que o dia final nao confirma
DO $w1$
BEGIN
DELETE FROM public.ponto_alertas a
 WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
   AND a.tipo = 'intervalo_suprimido'
   AND NOT EXISTS (
     SELECT 1 FROM public.ponto_diario d
     WHERE d.tenant_id = a.tenant_id AND d.colaborador_cpf = a.colaborador_cpf
       AND d.data = a.data_referencia AND COALESCE(d.he_intervalo_suprimido_minutos, 0) > 0);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_alertas nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w1$;

-- Falta de marcacao: dias incompletos ou com ajuste pendente (ultimos 15 dias)
DO $w2$
BEGIN
INSERT INTO public.ponto_alertas (id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, tipo, severidade, titulo, descricao, data_referencia, resolvido)
SELECT public.demo_id('ponto_alerta:falta_marcacao:' || d.colaborador_cpf || '|' || d.data::text),
       d.tenant_id, d.empresa_id, d.colaborador_id::text, d.colaborador_nome, d.colaborador_cpf,
       'falta_marcacao', 'alta', 'Falta de marcação de saída',
       format('%s não registrou a saída em %s. O dia ficou incompleto e as horas do período não pareado não foram contabilizadas. Solicite ou aprove o ajuste de ponto.',
              d.colaborador_nome, to_char(d.data, 'DD/MM/YYYY')),
       d.data, false
FROM public.ponto_diario d
WHERE d.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
  AND d.status IN ('incompleto', 'ajuste_pendente')
  AND d.data < (timezone('America/Sao_Paulo', now()))::date
  AND d.data >= (timezone('America/Sao_Paulo', now()))::date - 25
  AND NOT EXISTS (SELECT 1 FROM public.ponto_alertas a WHERE a.id = public.demo_id('ponto_alerta:falta_marcacao:' || d.colaborador_cpf || '|' || d.data::text));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_alertas nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w2$;

-- Excesso de jornada: dias com mais de 10 h trabalhadas (art. 59 CLT)
DO $w3$
BEGIN
INSERT INTO public.ponto_alertas (id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, tipo, severidade, titulo, descricao, data_referencia, resolvido)
SELECT public.demo_id('ponto_alerta:excesso_jornada:' || x.cpf || '|' || x.dia::text),
       'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002', a.id::text, a.nome_completo, x.cpf,
       'excesso_jornada', 'alta', 'Jornada acima de 10 horas',
       format('%s trabalhou %sh%s em %s (limite diário de 10h, incluindo até 2h extras).',
              a.nome_completo, (x.trab / 60)::text, lpad((x.trab % 60)::text, 2, '0'), to_char(x.dia, 'DD/MM/YYYY')),
       x.dia, false
FROM (
  SELECT a0.cpf, s.dia, s.trabalhado_min AS trab
  FROM public.admissoes a0
  CROSS JOIN LATERAL (
    SELECT * FROM public.ponto_saldo_dias_competencia('d3e00000-0000-4000-8000-000000000001', a0.cpf,
             to_char(date_trunc('month', timezone('America/Sao_Paulo', now())), 'YYYY-MM'))
    UNION ALL
    SELECT * FROM public.ponto_saldo_dias_competencia('d3e00000-0000-4000-8000-000000000001', a0.cpf,
             to_char(date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '1 month', 'YYYY-MM'))
  ) s
  WHERE a0.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a0.status = 'concluido'
    AND s.trabalhado_min > 600 AND s.dia < (timezone('America/Sao_Paulo', now()))::date
) x
JOIN public.admissoes a ON a.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a.cpf = x.cpf
WHERE NOT EXISTS (SELECT 1 FROM public.ponto_alertas p WHERE p.id = public.demo_id('ponto_alerta:excesso_jornada:' || x.cpf || '|' || x.dia::text));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_alertas nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w3$;

-- Interjornada insuficiente: menos de 11 h entre a saida e a entrada seguinte (art. 66 CLT)
DO $w4$
BEGIN
INSERT INTO public.ponto_alertas (id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, tipo, severidade, titulo, descricao, data_referencia, resolvido)
SELECT public.demo_id('ponto_alerta:interjornada:' || y.colaborador_cpf || '|' || y.data::text),
       y.tenant_id, y.empresa_id, y.colaborador_id::text, y.colaborador_nome, y.colaborador_cpf,
       'interjornada_insuficiente', 'media', 'Descanso entre jornadas inferior a 11 horas',
       format('%s encerrou a jornada às %s de %s e iniciou a seguinte às %s de %s (descanso de %sh%s).',
              y.colaborador_nome, to_char(y.saida_ant, 'HH24:MI'), to_char(y.data - 1, 'DD/MM'),
              to_char(y.entrada, 'HH24:MI'), to_char(y.data, 'DD/MM'),
              (y.gap_min / 60)::text, lpad((y.gap_min % 60)::text, 2, '0')),
       y.data, false
FROM (
  SELECT d.*, lag(d.saida) OVER w AS saida_ant, lag(d.data) OVER w AS data_ant,
         (1440 - (EXTRACT(EPOCH FROM lag(d.saida) OVER w) / 60)::int + (EXTRACT(EPOCH FROM d.entrada) / 60)::int) AS gap_min
  FROM public.ponto_diario d
  WHERE d.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND d.entrada IS NOT NULL
  WINDOW w AS (PARTITION BY d.colaborador_cpf ORDER BY d.data)
) y
WHERE y.saida_ant IS NOT NULL AND y.data_ant = y.data - 1 AND y.gap_min < 660 AND y.gap_min > 0
  AND y.data >= (timezone('America/Sao_Paulo', now()))::date - 70
  AND NOT EXISTS (SELECT 1 FROM public.ponto_alertas p WHERE p.id = public.demo_id('ponto_alerta:interjornada:' || y.colaborador_cpf || '|' || y.data::text));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_alertas nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w4$;

-- Horas extras recorrentes: quem teve credito em muitos dos ultimos 30 dias
DO $w5$
BEGIN
INSERT INTO public.ponto_alertas (id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, tipo, severidade, titulo, descricao, data_referencia, resolvido)
SELECT public.demo_id('ponto_alerta:he_recorrentes:' || z.cpf),
       'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002', a.id::text, a.nome_completo, z.cpf,
       'horas_extras_recorrentes', CASE WHEN z.dias >= 9 THEN 'alta' ELSE 'media' END, 'Horas extras recorrentes',
       format('%s fez horas extras em %s dos últimos 30 dias (média de %s min por ocorrência). Avalie redistribuir a carga do setor.',
              a.nome_completo, z.dias, z.media),
       (timezone('America/Sao_Paulo', now()))::date - 1, false
FROM (
  SELECT a0.cpf, count(*) AS dias, round(avg(s.saldo_min))::int AS media
  FROM public.admissoes a0
  CROSS JOIN LATERAL (
    SELECT * FROM public.ponto_saldo_dias_competencia('d3e00000-0000-4000-8000-000000000001', a0.cpf,
             to_char(date_trunc('month', timezone('America/Sao_Paulo', now())), 'YYYY-MM'))
    UNION ALL
    SELECT * FROM public.ponto_saldo_dias_competencia('d3e00000-0000-4000-8000-000000000001', a0.cpf,
             to_char(date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '1 month', 'YYYY-MM'))
  ) s
  WHERE a0.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a0.status = 'concluido'
    AND s.saldo_min >= 20 AND s.dia >= (timezone('America/Sao_Paulo', now()))::date - 30
    AND s.dia < (timezone('America/Sao_Paulo', now()))::date
  GROUP BY a0.cpf
  HAVING count(*) >= 6
) z
JOIN public.admissoes a ON a.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a.cpf = z.cpf
WHERE NOT EXISTS (SELECT 1 FROM public.ponto_alertas p WHERE p.id = public.demo_id('ponto_alerta:he_recorrentes:' || z.cpf));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_alertas nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w5$;

-- Banco vencendo: tres colaboradores com saldo positivo e prazo de compensacao proximo
DO $w6$
BEGIN
UPDATE public.ponto_banco_horas b
   SET prazo_compensacao = (timezone('America/Sao_Paulo', now()))::date + (ARRAY[9, 17, 26])[1 + (x.rk - 1)]
  FROM (
    SELECT bb.id, row_number() OVER (ORDER BY bb.saldo_atual_minutos DESC, bb.colaborador_cpf) AS rk
    FROM public.ponto_banco_horas bb
    WHERE bb.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
      AND bb.competencia = to_char(date_trunc('month', timezone('America/Sao_Paulo', now())), 'YYYY-MM')
      AND bb.saldo_atual_minutos > 0
  ) x
 WHERE b.id = x.id AND x.rk <= 3;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_banco_horas nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w6$;

DO $w7$
BEGIN
INSERT INTO public.ponto_alertas (id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, tipo, severidade, titulo, descricao, data_referencia, resolvido)
SELECT public.demo_id('ponto_alerta:banco_vencendo:' || b.colaborador_cpf || '|' || b.competencia),
       b.tenant_id, b.empresa_id, b.colaborador_id, b.colaborador_nome, b.colaborador_cpf,
       'banco_vencendo', CASE WHEN b.prazo_compensacao - (timezone('America/Sao_Paulo', now()))::date <= 10 THEN 'alta' ELSE 'media' END,
       'Banco de horas próximo do prazo de compensação',
       format('%s tem saldo positivo de %sh%s com prazo de compensação em %s (%s dias). Programe a folga ou o pagamento antes do vencimento.',
              b.colaborador_nome, (b.saldo_atual_minutos / 60)::text, lpad((b.saldo_atual_minutos % 60)::text, 2, '0'),
              to_char(b.prazo_compensacao, 'DD/MM/YYYY'), b.prazo_compensacao - (timezone('America/Sao_Paulo', now()))::date),
       (timezone('America/Sao_Paulo', now()))::date, false
FROM public.ponto_banco_horas b
WHERE b.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
  AND b.competencia = to_char(date_trunc('month', timezone('America/Sao_Paulo', now())), 'YYYY-MM')
  AND b.saldo_atual_minutos > 0
  AND b.prazo_compensacao <= (timezone('America/Sao_Paulo', now()))::date + 30
  AND NOT EXISTS (SELECT 1 FROM public.ponto_alertas p WHERE p.id = public.demo_id('ponto_alerta:banco_vencendo:' || b.colaborador_cpf || '|' || b.competencia));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_alertas nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w7$;

-- Carimba a data do fato e resolve os alertas antigos (so os dos ultimos 10 dias ficam abertos)
DO $w8$
BEGIN
UPDATE public.ponto_alertas a
   SET created_at = LEAST(now() - interval '30 minutes',
         (a.data_referencia::timestamp + time '09:00' + make_interval(mins => public.demo_ponto_rnd(a.id::text, 600))) AT TIME ZONE 'America/Sao_Paulo'
         + CASE WHEN a.tipo IN ('falta', 'atraso', 'intervalo_suprimido') THEN interval '9 hours' ELSE interval '0' END)
 WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
   AND a.data_referencia IS NOT NULL
   AND a.resolvido = false;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_alertas nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w8$;

DO $w9$
BEGIN
UPDATE public.ponto_alertas a
   SET resolvido = true,
       resolvido_em = LEAST(now(), a.created_at + interval '1 day' + make_interval(mins => public.demo_ponto_rnd(a.id::text || 'r', 480))),
       resolvido_por = 'Leiri'
 WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
   AND a.resolvido = false
   AND a.data_referencia < (timezone('America/Sao_Paulo', now()))::date - 10;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_alertas nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w9$;

-- Analises sugeridas (texto pronto, a IA nao roda neste script)
DO $w10$
BEGIN
INSERT INTO public.ponto_ia_analises (id, tenant_id, empresa_id, alerta_id, causa_provavel, impacto, acao_sugerida, confianca, status, decidido_por, decidido_por_nome, decidido_em, decisao_observacao, created_at)
SELECT public.demo_id('ponto_ia:' || x.alerta_id), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002', x.alerta_id,
       x.causa, x.impacto, x.acao, x.conf, x.situacao,
       CASE WHEN x.situacao <> 'sugerido' THEN (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' ORDER BY u.created_at LIMIT 1) END,
       CASE WHEN x.situacao <> 'sugerido' THEN 'Leiri' END,
       CASE WHEN x.situacao <> 'sugerido' THEN now() - interval '2 days' END,
       CASE WHEN x.situacao = 'decidido_aceito' THEN 'De acordo. Reorganizar o escalonamento da semana.'
            WHEN x.situacao = 'decidido_rejeitado' THEN 'Situação pontual, já tratada com o líder.' END,
       now() - interval '3 days'
FROM (
  SELECT al.id AS alerta_id, al.tipo, row_number() OVER (PARTITION BY al.tipo ORDER BY al.data_referencia DESC, al.id) AS rk,
         CASE al.tipo
           WHEN 'horas_extras_recorrentes' THEN 'Demanda contínua acima da capacidade do turno, com a mesma pessoa concentrando as horas extras.'
           WHEN 'excesso_jornada' THEN 'Pico de produção ou parada de máquina estendeu a jornada além do limite diário.'
           WHEN 'interjornada_insuficiente' THEN 'Prorrogação do turno anterior sem ajuste do horário de entrada do dia seguinte.'
           WHEN 'falta_marcacao' THEN 'Esquecimento recorrente da batida de saída ao final do expediente.'
           ELSE 'Padrão fora da escala contratada.' END AS causa,
         CASE al.tipo
           WHEN 'horas_extras_recorrentes' THEN 'Risco de ultrapassar o limite do banco de horas e de adoecimento por sobrecarga.'
           WHEN 'excesso_jornada' THEN 'Infração ao art. 59 da CLT; possível auto de infração em fiscalização.'
           WHEN 'interjornada_insuficiente' THEN 'Horas do descanso suprimido devem ser pagas como extras (Súmula 110 TST).'
           WHEN 'falta_marcacao' THEN 'Horas não contabilizadas e espelho de ponto incompleto até o ajuste.'
           ELSE 'Impacto a avaliar.' END AS impacto,
         CASE al.tipo
           WHEN 'horas_extras_recorrentes' THEN 'Redistribuir tarefas entre os turnos e avaliar reforço da equipe; acompanhar o saldo do banco.'
           WHEN 'excesso_jornada' THEN 'Conversar com o líder, limitar a prorrogação a 2 h e registrar a justificativa da necessidade.'
           WHEN 'interjornada_insuficiente' THEN 'Ajustar o horário de entrada do dia seguinte ou compensar o descanso suprimido.'
           WHEN 'falta_marcacao' THEN 'Solicitar o ajuste de ponto ao colaborador e reforçar a orientação de registro.'
           ELSE 'Revisar a escala.' END AS acao,
         (ARRAY[0.62, 0.78, 0.86, 0.91, 0.71])[1 + public.demo_ponto_rnd(al.id::text, 5)] AS conf,
         (ARRAY['sugerido', 'sugerido', 'decidido_aceito', 'sugerido', 'decidido_rejeitado'])[1 + public.demo_ponto_rnd(al.id::text || 's', 5)] AS situacao
  FROM public.ponto_alertas al
  WHERE al.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND al.resolvido = false
    AND al.tipo IN ('horas_extras_recorrentes', 'excesso_jornada', 'interjornada_insuficiente', 'falta_marcacao')
) x
WHERE x.rk <= 2
  AND NOT EXISTS (SELECT 1 FROM public.ponto_ia_analises i WHERE i.id = public.demo_id('ponto_ia:' || x.alerta_id));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_ia_analises nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w10$;

DROP FUNCTION IF EXISTS public.demo_ponto_rnd(text, integer);

-- Conferencia final (uma linha)
SELECT
  (SELECT count(*) FROM public.ponto_alertas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND NOT resolvido) AS alertas_abertos,
  (SELECT count(*) FROM public.ponto_alertas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND resolvido) AS alertas_resolvidos,
  (SELECT count(*) FROM public.ponto_ia_analises WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS analises_sugeridas,
  CASE WHEN (SELECT count(*) FROM public.ponto_alertas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 20 THEN 'OK' ELSE 'CONFERIR' END AS situacao;