-- ============================================================================
-- HOMOLOGACAO — DEMONSTRACAO, PARTE 06b: Financeiro (folha, provisoes, ferias, 13o,
-- rescisoes, rubricas, tabelas legais, CCT, alertas), Beneficios e Hub Contabil
--
-- PARA QUE SERVE
-- Preenche, para a "Metalurgica Exemplo Ltda" (tenant de demonstracao da parte 00),
-- as telas /financeiro (todas as abas), /financeiro/beneficios e /hub-contabil
-- (painel, listas por tipo, kanban, colaboradores, relatorios, configuracoes),
-- com seis meses de historico de folha. Independente da parte 06a.
--
-- ONDE COLAR
-- SQL Editor do projeto de HOMOLOGACAO, DEPOIS da parte 00. O arquivo se RECUSA
-- a rodar em qualquer outro banco (mesma trava da parte 00). Nunca na producao.
--
-- O QUE FAZ
--   1. cria duas funcoes auxiliares (demo_calc_inss e demo_calc_irrf) usadas para
--      calcular os descontos da folha de demonstracao com as tabelas de 2025;
--   2. rubricas, tabelas de INSS/IRRF, matriz de encargos por vinculo, tabelas
--      fiscais e convencao coletiva (CCT);
--   3. seis competencias de folha (a atual em previa, a anterior em conferencia e
--      quatro fechadas) com um item por colaborador e lancamentos por rubrica;
--   4. provisoes mensais de ferias e 13o, calculos de ferias, 13o (2025 e 2026) com
--      eventos eSocial montados, rescisoes e alertas de prazo;
--   5. tipos de beneficio e o vinculo de cada colaborador;
--   6. Hub Contabil: contabilidades, configuracao de prazos, processos de todos
--      os tipos e situacoes, com checklist, documentos, comentarios, assinaturas e
--      historico; competencias, guias, certidoes e calendario de envios.
--
-- GARANTIAS
--   - Nenhum dado real: nomes inventados, CPFs 900.000.0XX (public.demo_cpf), CNPJ e
--     e-mails ficticios (.demo). Valores de folha sao ilustrativos.
--   - So toca o tenant de demonstracao. Nenhum UPDATE/DELETE fora dele.
--   - Idempotente: ids fixos (public.demo_id) + "so insere se nao existe". Os UPDATEs
--     sao sobre linhas criadas aqui (totais da folha, situacao final dos periodos,
--     marcacao do checklist do Hub).
--   - Cada bloco roda isolado: se uma tabela da homologacao tiver estrutura
--     diferente da replica, o bloco avisa (NOTICE) e o resto segue.
--   - Roda numa transacao so; sem tabela temporaria; nenhuma tabela criada.
-- ============================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- (0) Trava de ambiente (copia da parte 00): so homologacao ou teste
-- ---------------------------------------------------------------------------
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
    RAISE EXCEPTION 'RECUSADO: rode antes a parte 00 (tenant de demonstracao nao existe).';
  END IF;
END $trava$;

-- ---------------------------------------------------------------------------
-- (1) Funcoes auxiliares: INSS progressivo e IRRF pela tabela 2025 (a mesma do app)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.demo_calc_inss(base numeric)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT round(
      LEAST(base, 1518.00) * 0.075
    + GREATEST(LEAST(base, 2793.88) - 1518.00, 0) * 0.09
    + GREATEST(LEAST(base, 4190.83) - 2793.88, 0) * 0.12
    + GREATEST(LEAST(base, 8157.41) - 4190.83, 0) * 0.14, 2)
$fn$;

CREATE OR REPLACE FUNCTION public.demo_calc_irrf(base numeric, dependentes integer)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT GREATEST(round(
    CASE
      WHEN base - dependentes * 189.59 <= 2259.20 THEN 0
      WHEN base - dependentes * 189.59 <= 2826.65 THEN (base - dependentes * 189.59) * 0.075 - 169.44
      WHEN base - dependentes * 189.59 <= 3751.05 THEN (base - dependentes * 189.59) * 0.15 - 381.44
      WHEN base - dependentes * 189.59 <= 4664.68 THEN (base - dependentes * 189.59) * 0.225 - 662.77
      ELSE (base - dependentes * 189.59) * 0.275 - 896.00
    END, 2), 0)
$fn$;

-- ---------------------------------------------------------------------------
-- (2) Cadastros da folha: rubricas, tabelas legais, encargos por vinculo, CCT
-- ---------------------------------------------------------------------------
DO $s_rubricas$
BEGIN
  INSERT INTO public.folha_rubricas (
    id, tenant_id, codigo_interno, descricao, tipo, natureza, incide_inss, incide_irrf, incide_fgts, incide_ferias,
    incide_13, incide_rescisao, forma_calculo, prioridade_calculo, permitido_para_vinculos, classificacao_esocial,
    natureza_contabil, protegida, ativa
  )
  SELECT public.demo_id('rubrica:' || v.cod), 'd3e00000-0000-4000-8000-000000000001', v.cod, v.descr,
         v.tipo::public.rubrica_tipo, v.nat::public.rubrica_natureza,
         v.inss, v.irrf, v.fgts, v.fer, v.d13, v.resc, v.forma::public.forma_calculo, v.prio,
         ARRAY['CLT_PRAZO_INDETERMINADO', 'CLT_EXPERIENCIA', 'CLT_TEMPO_PARCIAL', 'TEMPORARIO_LEI6019'],
         v.esoc, v.contabil, v.protegida, true
  FROM (VALUES
    ('001', 'Salário Base',                       'PROVENTO',    'REMUNERATORIA', true,  true,  true,  true,  true,  true,  'VALOR_FIXO',                 10,  '1000', 'Despesa com pessoal - salários',        true),
    ('002', 'Horas Extras 50%',                   'PROVENTO',    'REMUNERATORIA', true,  true,  true,  true,  true,  true,  'QUANTIDADE_X_VALOR',         20,  '1003', 'Despesa com pessoal - horas extras',    false),
    ('003', 'Horas Extras 100%',                  'PROVENTO',    'REMUNERATORIA', true,  true,  true,  true,  true,  true,  'QUANTIDADE_X_VALOR',         21,  '1003', 'Despesa com pessoal - horas extras',    false),
    ('004', 'Adicional Noturno 20%',              'PROVENTO',    'REMUNERATORIA', true,  true,  true,  true,  true,  true,  'PERCENTUAL_SALARIO',         30,  '1007', 'Despesa com pessoal - adicionais',      false),
    ('005', 'DSR sobre Horas Extras',             'PROVENTO',    'REMUNERATORIA', true,  true,  true,  true,  true,  true,  'PERCENTUAL_BASE_ESPECIFICA', 40,  '1004', 'Despesa com pessoal - DSR',             false),
    ('006', 'Adicional de Insalubridade',         'PROVENTO',    'REMUNERATORIA', true,  true,  true,  true,  true,  true,  'PERCENTUAL_BASE_ESPECIFICA', 50,  '1009', 'Despesa com pessoal - adicionais',      false),
    ('007', 'Adicional de Periculosidade 30%',    'PROVENTO',    'REMUNERATORIA', true,  true,  true,  true,  true,  true,  'PERCENTUAL_SALARIO',         51,  '1010', 'Despesa com pessoal - adicionais',      false),
    ('008', 'Comissões',                          'PROVENTO',    'REMUNERATORIA', true,  true,  true,  true,  true,  true,  'IMPORTADA_EXTERNA',          60,  '1011', 'Despesa com pessoal - comissões',       false),
    ('009', 'Gratificação de Função',             'PROVENTO',    'REMUNERATORIA', true,  true,  true,  true,  true,  true,  'VALOR_FIXO',                 70,  '1012', 'Despesa com pessoal - gratificações',   false),
    ('010', 'Salário-Família',                    'PROVENTO',    'INDENIZATORIA', false, false, false, false, false, false, 'QUANTIDADE_X_VALOR',         80,  '1020', 'Despesa com pessoal - benefícios legais', false),
    ('011', 'Prêmio de Produtividade',            'PROVENTO',    'REMUNERATORIA', true,  true,  true,  true,  true,  true,  'IMPORTADA_EXTERNA',          90,  '1013', 'Despesa com pessoal - prêmios',         false),
    ('012', 'Ajuda de Custo (indenizatória)',     'PROVENTO',    'INDENIZATORIA', false, false, false, false, false, false, 'VALOR_FIXO',                 95,  '1030', 'Despesa com pessoal - indenizações',    false),
    ('101', 'INSS',                               'DESCONTO',    'OUTRA',         false, false, false, false, false, false, 'PERCENTUAL_BASE_ESPECIFICA', 200, '9201', 'Retenções a recolher - INSS',        true),
    ('102', 'IRRF',                               'DESCONTO',    'OUTRA',         false, false, false, false, false, false, 'PERCENTUAL_BASE_ESPECIFICA', 210, '9203', 'Retenções a recolher - IRRF',        true),
    ('103', 'Vale-Transporte (6%)',               'DESCONTO',    'OUTRA',         false, false, false, false, false, false, 'PERCENTUAL_SALARIO',         220, '9219', 'Descontos de benefícios',              false),
    ('104', 'Coparticipação Plano de Saúde',      'DESCONTO',    'OUTRA',         false, false, false, false, false, false, 'VALOR_FIXO',                 230, '9214', 'Descontos de benefícios',              false),
    ('105', 'Desconto Vale-Alimentação',          'DESCONTO',    'OUTRA',         false, false, false, false, false, false, 'VALOR_FIXO',                 240, '9215', 'Descontos de benefícios',              false),
    ('106', 'Adiantamento Salarial',              'DESCONTO',    'OUTRA',         false, false, false, false, false, false, 'VALOR_FIXO',                 250, '9217', 'Adiantamentos a compensar',            false),
    ('107', 'Faltas e Atrasos',                   'DESCONTO',    'OUTRA',         false, false, false, false, false, false, 'QUANTIDADE_X_VALOR',         260, '9211', 'Descontos de ponto',                   false),
    ('108', 'Contribuição Assistencial',          'DESCONTO',    'OUTRA',         false, false, false, false, false, false, 'PERCENTUAL_SALARIO',         270, '9218', 'Contribuições sindicais',              false),
    ('201', 'FGTS (8%)',                          'INFORMATIVA', 'OUTRA',         false, false, false, false, false, false, 'PERCENTUAL_BASE_ESPECIFICA', 300, '9301', 'Encargos sociais - FGTS',              true),
    ('202', 'Base de cálculo do INSS',            'INFORMATIVA', 'OUTRA',         false, false, false, false, false, false, 'PERCENTUAL_BASE_ESPECIFICA', 310, '9302', 'Bases de cálculo',                    false),
    ('203', 'Base de cálculo do IRRF',            'INFORMATIVA', 'OUTRA',         false, false, false, false, false, false, 'PERCENTUAL_BASE_ESPECIFICA', 320, '9303', 'Bases de cálculo',                    false)
  ) AS v(cod, descr, tipo, nat, inss, irrf, fgts, fer, d13, resc, forma, prio, esoc, contabil, protegida)
  WHERE NOT EXISTS (SELECT 1 FROM public.folha_rubricas x
                    WHERE x.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND x.codigo_interno = v.cod);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(2a) rubricas nao semeadas: % (%)', SQLERRM, SQLSTATE;
END $s_rubricas$;

DO $s_tabelas_legais$
BEGIN
  INSERT INTO public.folha_tabelas_inss (id, tenant_id, vigencia_inicio, vigencia_fim, faixas, teto)
  SELECT public.demo_id('tabelainss:' || v.ano), 'd3e00000-0000-4000-8000-000000000001', v.ini, v.fim, v.faixas::jsonb, v.teto
  FROM (VALUES
    (2025, DATE '2025-01-01', NULL::date,    '[{"de":0,"ate":1518.00,"aliquota":7.5},{"de":1518.01,"ate":2793.88,"aliquota":9},{"de":2793.89,"ate":4190.83,"aliquota":12},{"de":4190.84,"ate":8157.41,"aliquota":14}]', 8157.41),
    (2024, DATE '2024-01-01', DATE '2024-12-31', '[{"de":0,"ate":1412.00,"aliquota":7.5},{"de":1412.01,"ate":2666.68,"aliquota":9},{"de":2666.69,"ate":4000.03,"aliquota":12},{"de":4000.04,"ate":7786.02,"aliquota":14}]', 7786.02)
  ) AS v(ano, ini, fim, faixas, teto)
  WHERE NOT EXISTS (SELECT 1 FROM public.folha_tabelas_inss x WHERE x.id = public.demo_id('tabelainss:' || v.ano));

  INSERT INTO public.folha_tabelas_irrf (id, tenant_id, vigencia_inicio, vigencia_fim, faixas, deducao_por_dependente)
  SELECT public.demo_id('tabelairrf:' || v.ano), 'd3e00000-0000-4000-8000-000000000001', v.ini, v.fim, v.faixas::jsonb, 189.59
  FROM (VALUES
    (2025, DATE '2025-01-01', NULL::date,    '[{"de":0,"ate":2259.20,"aliquota":0,"deducao":0},{"de":2259.21,"ate":2826.65,"aliquota":7.5,"deducao":169.44},{"de":2826.66,"ate":3751.05,"aliquota":15,"deducao":381.44},{"de":3751.06,"ate":4664.68,"aliquota":22.5,"deducao":662.77},{"de":4664.69,"ate":999999999,"aliquota":27.5,"deducao":896.00}]'),
    (2024, DATE '2024-02-01', DATE '2024-12-31', '[{"de":0,"ate":2259.20,"aliquota":0,"deducao":0},{"de":2259.21,"ate":2826.65,"aliquota":7.5,"deducao":169.44},{"de":2826.66,"ate":3751.05,"aliquota":15,"deducao":381.44},{"de":3751.06,"ate":4664.68,"aliquota":22.5,"deducao":662.77},{"de":4664.69,"ate":999999999,"aliquota":27.5,"deducao":896.00}]')
  ) AS v(ano, ini, fim, faixas)
  WHERE NOT EXISTS (SELECT 1 FROM public.folha_tabelas_irrf x WHERE x.id = public.demo_id('tabelairrf:' || v.ano));

  INSERT INTO public.folha_vinculos_config (
    id, tenant_id, tipo_vinculo, inss_empregado, fgts, aliquota_fgts, multa_fgts_dispensa, direito_13, direito_ferias, direito_aviso_previo
  )
  SELECT public.demo_id('vinculocfg:' || v.tipo), 'd3e00000-0000-4000-8000-000000000001', v.tipo, v.inss, v.fgts, v.aliq, v.multa, v.d13, v.fer, v.aviso
  FROM (VALUES
    ('CLT_PRAZO_INDETERMINADO', true,  true,  8, 40, true,  true,  true),
    ('CLT_EXPERIENCIA',         true,  true,  8, 40, true,  true,  false),
    ('CLT_INTERMITENTE',        true,  true,  8, 40, true,  true,  true),
    ('CLT_TEMPO_PARCIAL',       true,  true,  8, 40, true,  true,  true),
    ('APRENDIZ',                true,  true,  2, 0,  true,  true,  false),
    ('ESTAGIO',                 false, false, 0, 0,  false, false, false),
    ('TEMPORARIO_LEI6019',      true,  true,  8, 0,  true,  true,  false)
  ) AS v(tipo, inss, fgts, aliq, multa, d13, fer, aviso)
  WHERE NOT EXISTS (SELECT 1 FROM public.folha_vinculos_config x
                    WHERE x.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND x.tipo_vinculo = v.tipo);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(2b) tabelas legais e encargos nao semeados: % (%)', SQLERRM, SQLSTATE;
END $s_tabelas_legais$;

DO $s_tabelas_fiscais$
BEGIN
  INSERT INTO public.tabelas_fiscais (id, tenant_id, tipo, vigencia_inicio, vigencia_fim, ativo, faixas, teto, deducao_por_dependente, observacoes)
  SELECT public.demo_id('tabelafiscal:' || v.tipo || ':' || v.ano), 'd3e00000-0000-4000-8000-000000000001', v.tipo, v.ini, v.fim, v.ativo,
         v.faixas::jsonb, v.teto, v.ded, v.obs
  FROM (VALUES
    ('inss', 2025, DATE '2025-01-01', NULL::date,    true,  '[{"de":0,"ate":1518.00,"aliquota":7.5},{"de":1518.01,"ate":2793.88,"aliquota":9},{"de":2793.89,"ate":4190.83,"aliquota":12},{"de":4190.84,"ate":8157.41,"aliquota":14}]', 8157.41::numeric, NULL::numeric, 'Tabela progressiva vigente (dados de demonstração).'),
    ('irrf', 2025, DATE '2025-01-01', NULL::date,    true,  '[{"de":0,"ate":2259.20,"aliquota":0,"deducao":0},{"de":2259.21,"ate":2826.65,"aliquota":7.5,"deducao":169.44},{"de":2826.66,"ate":3751.05,"aliquota":15,"deducao":381.44},{"de":3751.06,"ate":4664.68,"aliquota":22.5,"deducao":662.77},{"de":4664.69,"ate":999999999,"aliquota":27.5,"deducao":896.00}]', NULL, 189.59, 'Tabela mensal vigente (dados de demonstração).'),
    ('inss', 2024, DATE '2024-01-01', DATE '2024-12-31', false, '[{"de":0,"ate":1412.00,"aliquota":7.5},{"de":1412.01,"ate":2666.68,"aliquota":9},{"de":2666.69,"ate":4000.03,"aliquota":12},{"de":4000.04,"ate":7786.02,"aliquota":14}]', 7786.02, NULL, 'Tabela anterior, mantida para consulta.'),
    ('irrf', 2024, DATE '2024-02-01', DATE '2024-12-31', false, '[{"de":0,"ate":2259.20,"aliquota":0,"deducao":0},{"de":2259.21,"ate":2826.65,"aliquota":7.5,"deducao":169.44},{"de":2826.66,"ate":3751.05,"aliquota":15,"deducao":381.44},{"de":3751.06,"ate":4664.68,"aliquota":22.5,"deducao":662.77},{"de":4664.69,"ate":999999999,"aliquota":27.5,"deducao":896.00}]', NULL, 189.59, 'Tabela anterior, mantida para consulta.')
  ) AS v(tipo, ano, ini, fim, ativo, faixas, teto, ded, obs)
  WHERE NOT EXISTS (SELECT 1 FROM public.tabelas_fiscais x
                    WHERE x.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND x.tipo = v.tipo AND x.vigencia_inicio = v.ini);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(2c) tabelas fiscais nao semeadas: % (%)', SQLERRM, SQLSTATE;
END $s_tabelas_fiscais$;

DO $s_cct$
BEGIN
  INSERT INTO public.folha_cct (
    id, tenant_id, sindicato, numero_registro, vigencia_inicio, vigencia_fim, piso_salarial, adicional_he_50, adicional_he_100,
    adicional_noturno, beneficios_obrigatorios, observacoes, ativo
  )
  SELECT public.demo_id('cct:' || v.n), 'd3e00000-0000-4000-8000-000000000001', v.sind, v.reg, CURRENT_DATE + v.ini, CURRENT_DATE + v.fim,
         v.piso, 50, 100, 20, v.benef::jsonb, v.obs, v.ativo
  FROM (VALUES
    (1, 'Sindicato dos Metalúrgicos de Joinville e Região (fictício)', 'SC000123/2026', -170, 195, 2450.00,
        '[{"nome":"Vale-alimentação","valor":650.00},{"nome":"Seguro de vida em grupo","valor":18.00},{"nome":"Auxílio-creche","valor":450.00}]',
        'Data-base em maio. Reajuste de 5,2% sobre salários e pisos; PLR conforme acordo específico.', true),
    (2, 'Sindicato dos Metalúrgicos de Joinville e Região (fictício)', 'SC000087/2025', -535, -171, 2330.00,
        '[{"nome":"Vale-alimentação","valor":590.00},{"nome":"Seguro de vida em grupo","valor":15.00}]',
        'Convenção do período anterior, mantida para consulta.', false)
  ) AS v(n, sind, reg, ini, fim, piso, benef, obs, ativo)
  WHERE NOT EXISTS (SELECT 1 FROM public.folha_cct x WHERE x.id = public.demo_id('cct:' || v.n));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(2d) CCT nao semeada: % (%)', SQLERRM, SQLSTATE;
END $s_cct$;

-- ---------------------------------------------------------------------------
-- (3) Folha: 6 competencias (a atual em previa, a anterior em conferencia, quatro fechadas)
-- ---------------------------------------------------------------------------
DO $s_folha$
BEGIN
  -- Periodos (nascem abertos: lancamentos em periodo fechado sao barrados pelo banco;
  -- a situacao final e aplicada no fim do bloco)
  INSERT INTO public.folha_periodos (id, tenant_id, empresa_id, competencia, status, data_abertura, total_bruto, total_descontos,
                                     total_liquido, total_colaboradores, observacoes)
  SELECT public.demo_id('folhaperiodo:' || c.comp), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
         c.comp, 'aberto', c.ini, 0, 0, 0, 0, 'Folha mensal da Metalúrgica Exemplo (dados de demonstração)'
  FROM (SELECT to_char(m, 'YYYY-MM') AS comp, m::date AS ini
        FROM generate_series(date_trunc('month', CURRENT_DATE) - interval '5 months', date_trunc('month', CURRENT_DATE), interval '1 month') AS m) c
  WHERE NOT EXISTS (SELECT 1 FROM public.folha_periodos x
                    WHERE x.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND x.competencia = c.comp);

  -- Um item por colaborador e competencia
  INSERT INTO public.folha_itens (
    id, tenant_id, periodo_id, colaborador_id, colaborador_nome, colaborador_cpf, cargo, departamento, salario_base,
    total_proventos, total_descontos, total_liquido, status, observacoes
  )
  WITH base AS MATERIALIZED (
    SELECT p.id AS periodo_id, p.competencia, a.id AS aid, a.nome_completo, a.cpf, a.cargo, a.departamento,
           a.salario::numeric AS sal,
           CASE WHEN a.departamento IN ('Produção', 'Manutenção', 'Logística')
                THEN round(a.salario::numeric / 220 * 1.5 * (abs(hashtext(a.id::text || p.competencia)) % 12), 2) ELSE 0 END AS he,
           (abs(hashtext(a.id::text)) % 3) AS dep
    FROM public.folha_periodos p
    JOIN public.admissoes a ON a.tenant_id = p.tenant_id AND a.status IN ('concluido', 'desligado')
    WHERE p.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
      AND p.id = public.demo_id('folhaperiodo:' || p.competencia)
      AND a.data_admissao <= ((p.competencia || '-01')::date + interval '1 month - 1 day')
      AND (a.data_desligamento IS NULL OR a.data_desligamento >= (p.competencia || '-01')::date)
  ), calc AS (
    SELECT b.*, b.sal + b.he AS prov, public.demo_calc_inss(b.sal + b.he) AS inss,
           public.demo_calc_irrf(b.sal + b.he - public.demo_calc_inss(b.sal + b.he), b.dep) AS irrf,
           round(LEAST(b.sal * 0.06, 220), 2) AS vt
    FROM base b
  )
  SELECT public.demo_id('folhaitem:' || c.competencia || ':' || c.aid::text), 'd3e00000-0000-4000-8000-000000000001', c.periodo_id,
         c.aid::text, c.nome_completo, c.cpf, c.cargo, c.departamento, c.sal, c.prov, c.inss + c.irrf + c.vt,
         c.prov - (c.inss + c.irrf + c.vt),
         CASE WHEN c.competencia < to_char(date_trunc('month', CURRENT_DATE) - interval '1 month', 'YYYY-MM') THEN 'fechado' ELSE 'calculado' END,
         CASE WHEN abs(hashtext(c.aid::text || c.competencia)) % 17 = 0 THEN 'Férias gozadas no período (abono e 1/3 em folha própria)' END
  FROM calc c
  WHERE NOT EXISTS (SELECT 1 FROM public.folha_itens x WHERE x.id = public.demo_id('folhaitem:' || c.competencia || ':' || c.aid::text));

  -- Lancamentos por rubrica nas 3 competencias mais recentes (ainda abertas neste ponto)
  INSERT INTO public.folha_lancamentos (
    id, tenant_id, periodo_id, colaborador_id, colaborador_nome, colaborador_cpf, rubrica_id, rubrica_codigo, rubrica_descricao,
    tipo, referencia, valor, origem
  )
  WITH itens AS MATERIALIZED (
    SELECT i.*, p.competencia, (abs(hashtext(i.colaborador_id)) % 3) AS dep
    FROM public.folha_itens i
    JOIN public.folha_periodos p ON p.id = i.periodo_id
    WHERE i.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
      AND p.competencia >= to_char(date_trunc('month', CURRENT_DATE) - interval '2 months', 'YYYY-MM')
      AND p.status = 'aberto'
  ), linhas AS (
    SELECT i.*, '001'::text AS cod, 'Salário Base'::text AS descr, 'PROVENTO'::text AS tp, '30 dias'::text AS ref, i.salario_base AS valor, 'folha'::text AS origem FROM itens i
    UNION ALL
    SELECT i.*, '002', 'Horas Extras 50%', 'PROVENTO', (round(i.total_proventos - i.salario_base) / NULLIF(round(i.salario_base / 220 * 1.5, 2), 0))::int || 'h', i.total_proventos - i.salario_base, 'ponto'
      FROM itens i WHERE i.total_proventos > i.salario_base
    UNION ALL
    SELECT i.*, '101', 'INSS', 'DESCONTO', 'Tabela 2025', public.demo_calc_inss(i.total_proventos), 'folha' FROM itens i
    UNION ALL
    SELECT i.*, '102', 'IRRF', 'DESCONTO', i.dep || ' dep.', public.demo_calc_irrf(i.total_proventos - public.demo_calc_inss(i.total_proventos), i.dep), 'folha'
      FROM itens i WHERE public.demo_calc_irrf(i.total_proventos - public.demo_calc_inss(i.total_proventos), i.dep) > 0
    UNION ALL
    SELECT i.*, '103', 'Vale-Transporte (6%)', 'DESCONTO', '6%', round(LEAST(i.salario_base * 0.06, 220), 2), 'beneficios' FROM itens i
  )
  SELECT public.demo_id('folhalanc:' || l.competencia || ':' || l.colaborador_id || ':' || l.cod), l.tenant_id, l.periodo_id,
         l.colaborador_id, l.colaborador_nome, l.colaborador_cpf, r.id, l.cod, l.descr, l.tp::public.rubrica_tipo, l.ref, l.valor, l.origem
  FROM linhas l
  LEFT JOIN public.folha_rubricas r ON r.tenant_id = l.tenant_id AND r.codigo_interno = l.cod
  WHERE NOT EXISTS (SELECT 1 FROM public.folha_lancamentos x
                    WHERE x.id = public.demo_id('folhalanc:' || l.competencia || ':' || l.colaborador_id || ':' || l.cod));

  -- Totais de cada periodo = soma dos itens
  UPDATE public.folha_periodos p
     SET total_bruto = s.bruto, total_descontos = s.descontos, total_liquido = s.liquido, total_colaboradores = s.qtd
    FROM (SELECT periodo_id, sum(total_proventos) AS bruto, sum(total_descontos) AS descontos, sum(total_liquido) AS liquido, count(*)::int AS qtd
          FROM public.folha_itens WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' GROUP BY periodo_id) s
   WHERE p.id = s.periodo_id AND p.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
     AND (p.total_bruto IS DISTINCT FROM s.bruto OR p.total_colaboradores IS DISTINCT FROM s.qtd OR p.total_liquido IS DISTINCT FROM s.liquido);

  -- Situacao final: atual em previa, anterior em conferencia, as demais fechadas
  UPDATE public.folha_periodos p
     SET status = CASE WHEN p.competencia = to_char(date_trunc('month', CURRENT_DATE), 'YYYY-MM') THEN 'previa'
                       WHEN p.competencia = to_char(date_trunc('month', CURRENT_DATE) - interval '1 month', 'YYYY-MM') THEN 'conferencia'
                       ELSE 'fechado' END,
         data_fechamento = CASE WHEN p.competencia < to_char(date_trunc('month', CURRENT_DATE) - interval '1 month', 'YYYY-MM')
                                THEN ((p.competencia || '-01')::date + interval '1 month' + interval '4 days')::date END,
         fechado_por_nome = CASE WHEN p.competencia < to_char(date_trunc('month', CURRENT_DATE) - interval '1 month', 'YYYY-MM')
                                 THEN 'Leiri Nuernberg' END
   WHERE p.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
     AND p.id = public.demo_id('folhaperiodo:' || p.competencia)
     AND p.status = 'aberto';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(3) folha nao semeada: % (%)', SQLERRM, SQLSTATE;
END $s_folha$;

-- ---------------------------------------------------------------------------
-- (4) Provisoes mensais de ferias e 13o (6 competencias)
-- ---------------------------------------------------------------------------
DO $s_provisoes$
BEGIN
  INSERT INTO public.folha_provisoes (
    id, tenant_id, competencia, colaborador_id, colaborador_nome, tipo, valor_provisao, valor_terco, encargos_inss,
    encargos_fgts, valor_total, revertida, data_reversao
  )
  WITH base AS MATERIALIZED (
    SELECT to_char(m, 'YYYY-MM') AS comp, a.id AS aid, a.nome_completo, a.salario::numeric AS sal, t.tipo, a.data_desligamento,
           (CASE WHEN a.data_desligamento IS NOT NULL AND to_char(a.data_desligamento, 'YYYY-MM') = to_char(m, 'YYYY-MM') THEN true ELSE false END) AS revertida
    FROM generate_series(date_trunc('month', CURRENT_DATE) - interval '5 months', date_trunc('month', CURRENT_DATE), interval '1 month') AS m
    CROSS JOIN (VALUES ('ferias'), ('13_salario')) AS t(tipo)
    JOIN public.admissoes a ON a.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a.status IN ('concluido', 'desligado')
    WHERE a.data_admissao <= (m + interval '1 month - 1 day')
      AND (a.data_desligamento IS NULL OR to_char(a.data_desligamento, 'YYYY-MM') >= to_char(m, 'YYYY-MM'))
  ), calc AS (
    SELECT b.*, round(b.sal / 12, 2) AS prov, CASE WHEN b.tipo = 'ferias' THEN round(b.sal / 12 / 3, 2) ELSE 0 END AS terco
    FROM base b
  )
  SELECT public.demo_id('provisao:' || c.comp || ':' || c.tipo || ':' || c.aid::text), 'd3e00000-0000-4000-8000-000000000001', c.comp,
         c.aid::text, c.nome_completo, c.tipo, c.prov, c.terco, round((c.prov + c.terco) * 0.20, 2), round((c.prov + c.terco) * 0.08, 2),
         round((c.prov + c.terco) * 1.28, 2), c.revertida, CASE WHEN c.revertida THEN c.data_desligamento END
  FROM calc c
  WHERE NOT EXISTS (SELECT 1 FROM public.folha_provisoes x
                    WHERE x.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND x.competencia = c.comp
                      AND x.tipo = c.tipo AND x.colaborador_id = c.aid::text);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(4) provisoes nao semeadas: % (%)', SQLERRM, SQLSTATE;
END $s_provisoes$;
