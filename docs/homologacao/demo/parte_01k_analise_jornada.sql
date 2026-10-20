-- ============================================================================
-- HOMOLOGACAO — DEMONSTRACAO, PARTE 01k: Analise de Jornada
--
-- PARA QUE SERVE
-- Analise de Carga de Trabalho e Jornada (/analise-jornada): uma analise por colaborador sobre o ponto
-- apurado (horas extras = credito de cada dia na apuracao oficial), alertas derivados, parametros,
-- documentos, historico de importacoes e modelo de mapeamento.
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
-- (13) Analise de Carga de Trabalho e Jornada (/analise-jornada)
--      Mesma conta do botao "Executar Analise", feita sobre o ponto apurado acima
--      (horas extras = credito de cada dia na apuracao oficial), uma analise por
--      colaborador cobrindo o historico inteiro, alertas derivados com as mesmas
--      regras, parametros, documentos, importacoes e modelo de mapeamento.
-- ---------------------------------------------------------------------------
DO $w1$
BEGIN
INSERT INTO public.jornada_parametros (id, tenant_id, nome, jornada_diaria_max, jornada_semanal_max, horas_extras_diaria_max,
  intervalo_intrajornada_min, descanso_interjornada_min, descanso_semanal_min, ativo)
SELECT public.demo_id('jornada_param:padrao'), 'd3e00000-0000-4000-8000-000000000001', 'Parâmetros CLT (padrão da empresa)',
       8.8, 44, 2, 60, 11, 24, true
WHERE NOT EXISTS (SELECT 1 FROM public.jornada_parametros p WHERE p.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND p.nome = 'Parâmetros CLT (padrão da empresa)')
  AND NOT EXISTS (SELECT 1 FROM public.jornada_parametros p WHERE p.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND p.ativo);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco jornada_parametros nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w1$;

DO $w2$
BEGIN
INSERT INTO public.jornada_analises (
  id, tenant_id, colaborador_cpf, colaborador_nome, periodo_inicio, periodo_fim, dias_trabalhados, total_horas_trabalhadas,
  total_horas_extras, media_diaria_horas, media_semanal_horas, total_atrasos, total_ajustes_manuais,
  violacoes_intervalo, violacoes_interjornada, violacoes_jornada_diaria, violacoes_horas_extras, violacoes_dsr,
  nivel_risco, score_risco, status_conformidade, detalhes_conformidade, departamento, cargo, setor, unidade, gestor, created_at, updated_at)
SELECT public.demo_id('jornada_analise:' || m.cpf),
       'd3e00000-0000-4000-8000-000000000001', m.cpf, m.nome,
       m.ini, m.fim, m.dias, round(m.horas::numeric, 2), round(m.extras::numeric, 2),
       round((m.horas / GREATEST(m.dias, 1))::numeric, 2), round((m.horas / GREATEST(m.dias / 5.0, 1))::numeric, 2),
       m.atrasos, m.ajustes, m.v_int, m.v_inter, m.v_jd, m.v_he, m.v_dsr,
       CASE WHEN m.score >= 60 THEN 'alto' WHEN m.score >= 30 THEN 'moderado' ELSE 'baixo' END,
       round(m.score::numeric, 2),
       CASE WHEN m.viol > m.dias * 0.3 THEN 'nao_conforme' WHEN m.viol > 0 THEN 'atencao' ELSE 'conforme' END,
       jsonb_build_object('periodo', to_char(m.ini, 'DD/MM/YYYY') || ' a ' || to_char(m.fim, 'DD/MM/YYYY'),
                          'total_violacoes', m.viol, 'dias_com_hora_extra', m.dias_he),
       m.depto, m.cargo, m.depto, m.unidade, m.gestor, now() - interval '1 day', now() - interval '1 day'
FROM (
  SELECT t.*,
         LEAST(100, (t.viol::numeric / GREATEST(1, t.dias)) * 100 + (t.extras / GREATEST(1, t.horas)) * 50) AS score
  FROM (
    SELECT b.cpf, b.nome, b.depto, b.cargo, b.unidade, b.gestor, b.ini, b.fim,
           COALESCE(dd.dias, 0) AS dias, COALESCE(dd.horas, 0) AS horas, COALESCE(ee.extras, 0) AS extras,
           COALESCE(ee.dias_he, 0) AS dias_he, COALESCE(dd.atrasos, 0) AS atrasos,
           COALESCE((SELECT count(*) FROM public.ponto_ajustes aj
                     WHERE aj.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND aj.colaborador_cpf = b.cpf AND aj.status = 'aprovado'
                       AND aj.data_referencia BETWEEN b.ini AND b.fim), 0)::int AS ajustes,
           COALESCE(dd.v_int, 0) AS v_int, COALESCE(dd.v_inter, 0) AS v_inter, COALESCE(dd.v_jd, 0) AS v_jd,
           COALESCE(ee.v_he, 0) AS v_he, COALESCE(ds.v_dsr, 0) AS v_dsr,
           (COALESCE(dd.v_int, 0) + COALESCE(dd.v_inter, 0) + COALESCE(dd.v_jd, 0) + COALESCE(ee.v_he, 0) + COALESCE(ds.v_dsr, 0))::int AS viol
    FROM (
      SELECT a.cpf, a.nome_completo AS nome, a.departamento AS depto, a.cargo, a.filial AS unidade, a.gestor_imediato AS gestor,
             (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date AS ini,
             (timezone('America/Sao_Paulo', now()))::date - 1 AS fim
      FROM public.admissoes a
      WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a.status = 'concluido' AND COALESCE(a.bate_ponto, true)
    ) b
    LEFT JOIN LATERAL (
      SELECT count(*)::int AS dias,
             sum(EXTRACT(EPOCH FROM p.horas_trabalhadas) / 3600.0) AS horas,
             count(*) FILTER (WHERE p.status = 'atraso')::int AS atrasos,
             count(*) FILTER (WHERE EXTRACT(EPOCH FROM p.horas_trabalhadas) / 3600.0 > 10.8)::int AS v_jd,
             count(*) FILTER (WHERE p.saida_almoco IS NOT NULL AND p.retorno_almoco IS NOT NULL
                                AND (EXTRACT(EPOCH FROM (p.retorno_almoco - p.saida_almoco)) / 60.0) <
                                    CASE WHEN EXTRACT(EPOCH FROM p.horas_trabalhadas) / 3600.0 > 6 THEN 60 ELSE 15 END)::int AS v_int,
             count(*) FILTER (WHERE p.saida_ant IS NOT NULL AND p.data_ant = p.data - 1
                                AND (1440 - EXTRACT(EPOCH FROM p.saida_ant) / 60.0 + EXTRACT(EPOCH FROM p.entrada) / 60.0) < 660
                                AND (1440 - EXTRACT(EPOCH FROM p.saida_ant) / 60.0 + EXTRACT(EPOCH FROM p.entrada) / 60.0) > 0)::int AS v_inter
      FROM (
        SELECT d.*, lag(d.saida) OVER (ORDER BY d.data) AS saida_ant, lag(d.data) OVER (ORDER BY d.data) AS data_ant
        FROM public.ponto_diario d
        WHERE d.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND d.colaborador_cpf = b.cpf
          AND d.data BETWEEN b.ini AND b.fim AND d.entrada IS NOT NULL
      ) p
    ) dd ON true
    LEFT JOIN LATERAL (
      SELECT sum(GREATEST(s.saldo_min, 0)) / 60.0 AS extras,
             count(*) FILTER (WHERE s.saldo_min > 0)::int AS dias_he,
             count(*) FILTER (WHERE s.saldo_min >= 120 OR s.excedente_retido_min > 0)::int AS v_he
      FROM generate_series(date_trunc('month', b.ini), date_trunc('month', b.fim), interval '1 month') mm
      CROSS JOIN LATERAL public.ponto_saldo_dias_competencia('d3e00000-0000-4000-8000-000000000001', b.cpf, to_char(mm, 'YYYY-MM')) s
      WHERE s.dia BETWEEN b.ini AND b.fim
    ) ee ON true
    LEFT JOIN LATERAL (
      -- 7 dias seguidos ou mais trabalhados, sem o descanso semanal
      SELECT COALESCE(sum(GREATEST(il.len - 6, 0)), 0)::int AS v_dsr
      FROM (
        SELECT count(*) AS len
        FROM (
          SELECT d.data - (row_number() OVER (ORDER BY d.data))::int AS grp
          FROM public.ponto_diario d
          WHERE d.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND d.colaborador_cpf = b.cpf
            AND d.data BETWEEN b.ini AND b.fim AND d.entrada IS NOT NULL
        ) g
        GROUP BY g.grp
      ) il
    ) ds ON true
  ) t
) m
WHERE m.dias > 0
  AND NOT EXISTS (SELECT 1 FROM public.jornada_analises x WHERE x.id = public.demo_id('jornada_analise:' || m.cpf));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco jornada_analises nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w2$;

-- Alertas inteligentes (mesmas regras do botao Executar Analise + atraso e ajustes)
DO $w3$
BEGIN
INSERT INTO public.jornada_alertas (id, tenant_id, analise_id, colaborador_cpf, colaborador_nome, tipo, severidade, titulo, descricao, data_referencia, lido, resolvido, resolvido_em, resolvido_por, acao_sugerida, departamento, setor, created_at)
SELECT public.demo_id('jornada_alerta:' || al.tipo || ':' || al.cpf), 'd3e00000-0000-4000-8000-000000000001', al.analise_id, al.cpf, al.nome,
       al.tipo, al.sev, al.titulo, al.descricao, (timezone('America/Sao_Paulo', now()))::date - al.dias_atras,
       al.resolvido, al.resolvido, CASE WHEN al.resolvido THEN now() - interval '2 days' END,
       CASE WHEN al.resolvido THEN 'Leiri' END, al.acao, al.depto, al.depto,
       now() - make_interval(days => al.dias_atras)
FROM (
  SELECT x.*, public.demo_ponto_rnd(x.cpf || x.tipo, 100) < 35 AS resolvido,
         1 + public.demo_ponto_rnd(x.cpf || x.tipo || 'd', 14) AS dias_atras
  FROM (
    SELECT a.id AS analise_id, a.colaborador_cpf AS cpf, a.colaborador_nome AS nome, a.departamento AS depto,
           'excesso_horas_extras' AS tipo,
           CASE WHEN a.total_horas_extras > a.dias_trabalhados * 1.0 THEN 'alta' ELSE 'media' END AS sev,
           'Excesso de horas extras — ' || a.colaborador_nome AS titulo,
           format('%sh extras em %s dias trabalhados no período.', to_char(a.total_horas_extras, 'FM999990.0'), a.dias_trabalhados) AS descricao,
           'Verificar demanda de trabalho e redistribuir tarefas' AS acao
    FROM public.jornada_analises a
    WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a.total_horas_extras > a.dias_trabalhados * 0.6
    UNION ALL
    SELECT a.id, a.colaborador_cpf, a.colaborador_nome, a.departamento, 'falta_intervalo', 'alta',
           'Intervalo intrajornada insuficiente — ' || a.colaborador_nome,
           format('%s violações de intervalo no período.', a.violacoes_intervalo),
           'Garantir cumprimento do intervalo mínimo de 1h'
    FROM public.jornada_analises a
    WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a.violacoes_intervalo > 3
    UNION ALL
    SELECT a.id, a.colaborador_cpf, a.colaborador_nome, a.departamento, 'descanso_insuficiente', 'critica',
           'Descanso interjornada insuficiente — ' || a.colaborador_nome,
           format('%s violações de descanso mínimo de 11h.', a.violacoes_interjornada),
           'Ação imediata: ajustar escalas para garantir 11h de descanso'
    FROM public.jornada_analises a
    WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a.violacoes_interjornada > 0
    UNION ALL
    SELECT a.id, a.colaborador_cpf, a.colaborador_nome, a.departamento, 'atraso_recorrente', 'media',
           'Atrasos recorrentes — ' || a.colaborador_nome,
           format('%s atrasos no período (mais de 10 minutos após a tolerância).', a.total_atrasos),
           'Conversar com o colaborador e avaliar causa (transporte, saúde, escala)'
    FROM public.jornada_analises a
    WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a.total_atrasos >= 6
    UNION ALL
    SELECT a.id, a.colaborador_cpf, a.colaborador_nome, a.departamento, 'ajustes_excessivos', 'baixa',
           'Muitos ajustes manuais — ' || a.colaborador_nome,
           format('%s ajustes de ponto aprovados no período.', a.total_ajustes_manuais),
           'Orientar o registro correto das batidas e revisar o uso do aplicativo'
    FROM public.jornada_analises a
    WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a.total_ajustes_manuais >= 3
    UNION ALL
    SELECT a.id, a.colaborador_cpf, a.colaborador_nome, a.departamento, 'jornada_excessiva', 'alta',
           'Jornada excessiva — ' || a.colaborador_nome,
           format('Média de %sh/dia no período.', to_char(a.media_diaria_horas, 'FM990.0')),
           'Avaliar carga de trabalho e riscos psicossociais'
    FROM public.jornada_analises a
    WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a.media_diaria_horas > 9.2
  ) x
) al
WHERE NOT EXISTS (SELECT 1 FROM public.jornada_alertas j WHERE j.id = public.demo_id('jornada_alerta:' || al.tipo || ':' || al.cpf));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco jornada_alertas nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w3$;

-- Documentos (aba Documentos): so registros, sem arquivo anexado no armazenamento
DO $w4$
BEGIN
INSERT INTO public.jornada_documentos (id, tenant_id, nome, arquivo_url, arquivo_nome, arquivo_tamanho, tipo, vinculo_tipo, vinculo_valor, periodo_inicio, periodo_fim, observacoes, enviado_por, created_at)
SELECT public.demo_id('jornada_doc:' || v.k), 'd3e00000-0000-4000-8000-000000000001', v.nome, 'demo/jornada/' || v.arq, v.arq, v.tam,
       v.tipo, v.vinc, v.valor, v.ini, v.fim, v.obs, 'Leiri', now() - make_interval(days => v.dias)
FROM (VALUES
  (1, 'Convenção Coletiva dos Metalúrgicos 2026/2027', 'cct-metalurgicos-2026-2027.pdf', 1843200, 'convencao_coletiva', 'empresa', 'Metalúrgica Exemplo Ltda', DATE '2026-05-01', DATE '2027-04-30', 'Convenção vigente, base das regras de hora extra e intervalo.', 48),
  (2, 'Acordo coletivo de banco de horas (ACT 2026)', 'act-banco-horas-2026.pdf', 624640, 'acordo_compensacao', 'empresa', 'Metalúrgica Exemplo Ltda', DATE '2026-01-01', DATE '2026-12-31', 'Autoriza banco de horas com compensação em até 12 meses.', 95),
  (3, 'Relatório de jornada - Produção (trimestre)', 'relatorio-jornada-producao.pdf', 412672, 'relatorio_jornada', 'setor', 'Produção', DATE '2026-07-01', DATE '2026-09-30', 'Resumo para a reunião da CIPA: horas extras, intervalos e descanso entre jornadas.', 14),
  (4, 'Espelho de ponto - Filial Curitiba (agosto)', 'espelho-curitiba-2026-08.pdf', 298496, 'espelho_ponto', 'unidade', 'Filial Curitiba', DATE '2026-08-01', DATE '2026-08-31', 'Espelhos assinados pelos colaboradores da filial.', 40),
  (5, 'Relatório de auditoria interna de jornada', 'auditoria-jornada-2026-t3.pdf', 733184, 'auditoria', 'periodo', 'Julho a setembro de 2026', DATE '2026-07-01', DATE '2026-09-30', 'Conferência do cumprimento do intervalo e do descanso interjornada.', 6)
) AS v(k, nome, arq, tam, tipo, vinc, valor, ini, fim, obs, dias)
WHERE NOT EXISTS (SELECT 1 FROM public.jornada_documentos d WHERE d.id = public.demo_id('jornada_doc:' || v.k));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco jornada_documentos nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w4$;

-- Historico de importacoes de planilhas de ponto (aba Importacao)
DO $w5$
BEGIN
INSERT INTO public.jornada_importacoes (id, tenant_id, nome_arquivo, tipo_arquivo, total_registros, registros_importados, registros_erros, periodo_inicio, periodo_fim, status, erros, mapeamento_colunas, importado_por, created_at, updated_at)
SELECT public.demo_id('jornada_imp:' || v.k), 'd3e00000-0000-4000-8000-000000000001', v.nome, v.tipo, v.total, v.imp, v.err, v.ini, v.fim, v.status, v.erros,
       '{"colaboradorNome": 0, "colaboradorCpf": 1, "data": 2, "entrada": 3, "saidaAlmoco": 4, "retornoAlmoco": 5, "saida": 6}'::jsonb,
       'Leiri', now() - make_interval(days => v.dias), now() - make_interval(days => v.dias)
FROM (VALUES
  (1, 'ponto_filial_curitiba_agosto.xlsx', 'xlsx', 412, 412, 0, DATE '2026-08-01', DATE '2026-08-31', 'concluido', '[]'::jsonb, 38),
  (2, 'ponto_cd_itajai_setembro.csv', 'csv', 268, 259, 9, DATE '2026-09-01', DATE '2026-09-30', 'parcial',
     '[{"linha": 14, "mensagem": "Data inválida ou ausente"}, {"linha": 57, "mensagem": "Nome é obrigatório"}]'::jsonb, 11)
) AS v(k, nome, tipo, total, imp, err, ini, fim, status, erros, dias)
WHERE NOT EXISTS (SELECT 1 FROM public.jornada_importacoes i WHERE i.id = public.demo_id('jornada_imp:' || v.k));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco jornada_importacoes nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w5$;

DO $w6$
BEGIN
INSERT INTO public.jornada_templates_mapeamento (id, tenant_id, nome, descricao, mapeamento, headers_originais, criado_por, created_at)
SELECT public.demo_id('jornada_tpl:' || v.k), 'd3e00000-0000-4000-8000-000000000001', v.nome, v.descr,
       '{"colaboradorNome": 0, "colaboradorCpf": 1, "data": 2, "entrada": 3, "saidaAlmoco": 4, "retornoAlmoco": 5, "saida": 6}'::jsonb,
       ARRAY['Nome', 'CPF', 'Data', 'Entrada', 'Saída Almoço', 'Retorno Almoço', 'Saída'], 'Leiri', now() - interval '40 days'
FROM (VALUES (1, 'Planilha do relógio da filial', 'Layout exportado pelo relógio de ponto das filiais.')) AS v(k, nome, descr)
WHERE NOT EXISTS (SELECT 1 FROM public.jornada_templates_mapeamento t WHERE t.id = public.demo_id('jornada_tpl:' || v.k));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco jornada_templates_mapeamento nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w6$;

DROP FUNCTION IF EXISTS public.demo_ponto_rnd(text, integer);

-- Conferencia final (uma linha)
SELECT
  (SELECT count(*) FROM public.jornada_analises WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS analises,
  (SELECT count(*) FROM public.jornada_alertas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS alertas,
  (SELECT count(*) FROM public.jornada_documentos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS documentos,
  (SELECT count(*) FROM public.jornada_importacoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS importacoes,
  CASE WHEN (SELECT count(*) FROM public.jornada_analises WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 50 THEN 'OK' ELSE 'CONFERIR' END AS situacao;