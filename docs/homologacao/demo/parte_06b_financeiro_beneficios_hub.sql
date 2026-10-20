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

-- ---------------------------------------------------------------------------
-- (5) Ferias: calculos financeiros (pagas, aprovadas, calculadas e uma em dobro)
-- ---------------------------------------------------------------------------
DO $s_ferias$
BEGIN
  INSERT INTO public.folha_ferias_calculo (
    id, tenant_id, colaborador_id, colaborador_nome, colaborador_cpf, tipo_vinculo, periodo_aquisitivo_inicio, periodo_aquisitivo_fim,
    data_inicio_gozo, data_fim_gozo, dias_gozo, dias_abono, remuneracao_base, media_variaveis, valor_ferias, valor_terco, valor_abono,
    valor_abono_terco, base_inss, valor_inss, base_irrf, valor_irrf, base_fgts, valor_fgts, total_bruto, total_descontos, total_liquido,
    em_dobro, data_pagamento, prazo_legal, status, memoria_calculo, media_origem, created_at
  )
  WITH cand AS MATERIALIZED (
    SELECT a.*, row_number() OVER (ORDER BY md5(a.id::text)) AS rn
    FROM public.admissoes a
    WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a.status = 'concluido'
      AND a.data_admissao <= CURRENT_DATE - 800
  ), esc AS (
    SELECT c.*, (date_part('year', age(CURRENT_DATE, c.data_admissao)))::int AS anos,
           CASE WHEN c.rn <= 5 THEN 'pago' WHEN c.rn <= 8 THEN 'aprovado' ELSE 'calculado' END AS situacao,
           (CASE WHEN c.rn <= 5 THEN -(20 + c.rn * 22) WHEN c.rn <= 8 THEN 7 + c.rn * 6 WHEN c.rn = 12 THEN 3 ELSE 55 + c.rn * 5 END)::int AS gozo_off,
           CASE WHEN c.rn % 2 = 0 THEN 20 ELSE 30 END AS dgozo,
           CASE WHEN c.rn % 2 = 0 THEN 10 ELSE 0 END AS dabono,
           (c.rn = 12) AS dobro
    FROM cand c WHERE c.rn <= 12
  ), val AS (
    SELECT e.*, (e.data_admissao + ((e.anos - 1) || ' years')::interval)::date AS aq_ini,
           e.salario::numeric AS sal,
           CASE WHEN e.departamento IN ('Produção', 'Manutenção', 'Logística') THEN round(e.salario::numeric * 0.04, 2) ELSE 0 END AS media
    FROM esc e
  ), calc AS (
    SELECT v.*, round((v.sal + v.media) / 30 * v.dgozo, 2) AS vf, round((v.sal + v.media) / 30 * v.dabono, 2) AS vab,
           (abs(hashtext(v.id::text)) % 3) AS dep
    FROM val v
  ), calc2 AS (
    SELECT c.*, round(c.vf / 3, 2) AS vt, round(c.vab / 3, 2) AS vabt FROM calc c
  ), calc3 AS (
    SELECT c.*, c.vf + c.vt AS binss, public.demo_calc_inss(c.vf + c.vt) AS inss FROM calc2 c
  )
  SELECT public.demo_id('feriascalc:' || c.id::text), 'd3e00000-0000-4000-8000-000000000001', c.id::text, c.nome_completo, c.cpf,
         'CLT_PRAZO_INDETERMINADO', c.aq_ini, (c.aq_ini + interval '1 year - 1 day')::date,
         CURRENT_DATE + c.gozo_off, CURRENT_DATE + c.gozo_off + c.dgozo - 1, c.dgozo, c.dabono, c.sal, c.media, c.vf, c.vt, c.vab, c.vabt,
         c.binss, c.inss, c.binss - c.inss, public.demo_calc_irrf(c.binss - c.inss, c.dep), c.binss, round(c.binss * 0.08, 2),
         c.vf + c.vt + c.vab + c.vabt, c.inss + public.demo_calc_irrf(c.binss - c.inss, c.dep),
         c.vf + c.vt + c.vab + c.vabt - c.inss - public.demo_calc_irrf(c.binss - c.inss, c.dep),
         c.dobro, CURRENT_DATE + c.gozo_off - 2, CURRENT_DATE + c.gozo_off - 2, c.situacao,
         jsonb_build_object('observacao', 'Cálculo de demonstração', 'dependentes_irrf', c.dep), 'apurada',
         now() - ((20 + c.rn * 3) || ' days')::interval
  FROM calc3 c
  WHERE NOT EXISTS (SELECT 1 FROM public.folha_ferias_calculo x WHERE x.id = public.demo_id('feriascalc:' || c.id::text));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(5) calculos de ferias nao semeados: % (%)', SQLERRM, SQLSTATE;
END $s_ferias$;

-- ---------------------------------------------------------------------------
-- (6) 13o salario: politica, calculos de 2025 (pagos) e 2026 (1a parcela) e eventos eSocial
-- ---------------------------------------------------------------------------
DO $s_13_config$
BEGIN
  INSERT INTO public.decimo_terceiro_config (
    id, tenant_id, media_divisor, afastamento_regra, afastamento_dias_empregador, adiantamento_base,
    parametros_vigencia_inicio, media_inclui_protegidas, media_horas_extras, divisor_horas_mes
  )
  SELECT public.demo_id('decimoconfig:1'), 'd3e00000-0000-4000-8000-000000000001', 'avos_apurados', 'previdenciario_suspende', 15,
         'proporcional_apurado', DATE '2025-01-01', false, 'fisica', 220
  WHERE NOT EXISTS (SELECT 1 FROM public.decimo_terceiro_config x WHERE x.tenant_id = 'd3e00000-0000-4000-8000-000000000001');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(6a) politica do 13o nao semeada: % (%)', SQLERRM, SQLSTATE;
END $s_13_config$;

DO $s_13_calculos$
BEGIN
  INSERT INTO public.folha_13_calculo (
    id, tenant_id, ano, colaborador_id, colaborador_nome, colaborador_cpf, tipo_vinculo, parcela, meses_trabalhados, remuneracao_base,
    media_variaveis, valor_bruto, valor_primeira_parcela, base_inss, valor_inss, base_irrf, valor_irrf, base_fgts, valor_fgts,
    total_descontos, total_liquido, status, memoria_calculo, avos_origem, media_origem, admissao_id, empresa_id, competencia,
    data_prevista, data_pagamento, aprovado_por_nome, aprovado_em, pago_em, created_at
  )
  WITH anos AS (
    SELECT g.ano, g.parcela FROM (VALUES (2025, 1), (2025, 2), (2026, 1)) AS g(ano, parcela)
  ), base AS MATERIALIZED (
    SELECT an.ano, an.parcela, a.id AS aid, a.nome_completo, a.cpf, a.salario::numeric AS sal, a.data_admissao,
           (abs(hashtext(a.id::text)) % 10) AS bucket, (abs(hashtext(a.id::text)) % 3) AS dep,
           CASE WHEN a.departamento IN ('Produção', 'Manutenção', 'Logística') THEN round(a.salario::numeric * 0.04, 2) ELSE 0 END AS media,
           CASE WHEN a.data_admissao < make_date(an.ano, 1, 1) THEN 12
                ELSE GREATEST(1, 12 - (extract(month FROM a.data_admissao)::int - 1) - CASE WHEN extract(day FROM a.data_admissao) > 15 THEN 1 ELSE 0 END) END AS avos
    FROM anos an
    JOIN public.admissoes a ON a.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a.status IN ('concluido', 'desligado')
    WHERE a.data_admissao <= make_date(an.ano, 12, 1) AND a.data_admissao <= CURRENT_DATE
      AND NOT (a.status = 'desligado' AND an.ano = 2026)
  ), v1 AS (
    SELECT b.*, round((b.sal + b.media) * b.avos / 12, 2) AS bruto FROM base b
  ), v2 AS (
    SELECT v.*, round(v.bruto / 2, 2) AS p1,
           CASE WHEN v.parcela = 2 THEN public.demo_calc_inss(v.bruto) ELSE 0 END AS inss FROM v1 v
  ), v3 AS (
    SELECT v.*, CASE WHEN v.parcela = 2 THEN public.demo_calc_irrf(v.bruto - v.inss, v.dep) ELSE 0 END AS irrf FROM v2 v
  ), v4 AS (
    SELECT v.*,
           CASE WHEN v.ano = 2025 THEN 'pago'
                WHEN v.bucket = 0 THEN 'pago'
                WHEN v.bucket IN (1, 2, 3) THEN 'aprovado'
                ELSE 'calculado' END AS situacao,
           CASE WHEN v.ano = 2025 AND v.parcela = 1 THEN DATE '2025-11-30'
                WHEN v.ano = 2025 THEN DATE '2025-12-20'
                ELSE make_date(v.ano, 11, 30) END AS prevista
    FROM v3 v
  )
  SELECT public.demo_id('decimo:' || v.ano || ':' || v.parcela || ':' || v.aid::text), 'd3e00000-0000-4000-8000-000000000001', v.ano, v.aid::text,
         v.nome_completo, v.cpf, 'CLT_PRAZO_INDETERMINADO', v.parcela, v.avos, v.sal, v.media, v.bruto, v.p1,
         CASE WHEN v.parcela = 2 THEN v.bruto ELSE 0 END, v.inss, CASE WHEN v.parcela = 2 THEN v.bruto - v.inss ELSE 0 END, v.irrf,
         CASE WHEN v.parcela = 1 THEN v.p1 ELSE v.bruto - v.p1 END,
         round((CASE WHEN v.parcela = 1 THEN v.p1 ELSE v.bruto - v.p1 END) * 0.08, 2),
         CASE WHEN v.parcela = 1 THEN 0 ELSE v.inss + v.irrf + v.p1 END,
         CASE WHEN v.parcela = 1 THEN v.p1 ELSE v.bruto - (v.inss + v.irrf + v.p1) END,
         v.situacao, jsonb_build_object('observacao', 'Cálculo de demonstração', 'dependentes_irrf', v.dep), 'apurado', 'apurado', v.aid,
         'd3e00000-0000-4000-8000-000000000002', to_char(v.prevista, 'YYYY-MM'), v.prevista,
         CASE WHEN v.situacao = 'pago' THEN CASE WHEN v.ano = 2025 THEN v.prevista - 2 ELSE CURRENT_DATE - (5 + v.bucket * 3) END END,
         CASE WHEN v.situacao IN ('aprovado', 'pago') THEN 'Leiri Nuernberg' END,
         CASE WHEN v.situacao IN ('aprovado', 'pago') THEN CASE WHEN v.ano = 2025 THEN (v.prevista - 5)::timestamptz ELSE now() - interval '4 days' END END,
         CASE WHEN v.situacao = 'pago' THEN CASE WHEN v.ano = 2025 THEN (v.prevista - 2)::timestamptz ELSE now() - interval '3 days' END END,
         CASE WHEN v.ano = 2025 THEN (v.prevista - 20)::timestamptz ELSE now() - interval '12 days' END
  FROM v4 v
  WHERE NOT EXISTS (SELECT 1 FROM public.folha_13_calculo x WHERE x.id = public.demo_id('decimo:' || v.ano || ':' || v.parcela || ':' || v.aid::text));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(6b) calculos do 13o nao semeados: % (%)', SQLERRM, SQLSTATE;
END $s_13_calculos$;

-- Eventos eSocial do 13o: 2025 processados; 2026 montados e pendentes (um rejeitado, para o fluxo de correcao)
DO $s_13_esocial$
BEGIN
  INSERT INTO public.esocial_transmissoes (
    id, tenant_id, empresa_id, tipo_evento, status, protocolo, numero_recibo, mensagem_retorno, tentativas, criado_por_nome,
    origem_modulo, origem_id, ano, parcela, periodo_apuracao, ind_apuracao, leiaute_versao, colaborador_cpf, data_limite, created_at
  )
  SELECT public.demo_id('esocial13:' || t.tipo || ':' || c.id::text), c.tenant_id, c.empresa_id, t.tipo,
         CASE WHEN c.ano = 2025 THEN 'processado' WHEN c.rn = 3 AND t.tipo = 'S-1200' THEN 'rejeitado' ELSE 'pendente' END,
         CASE WHEN c.ano = 2025 THEN '1.2.' || lpad((abs(hashtext(c.id::text || t.tipo)) % 99999999)::text, 8, '0') END,
         CASE WHEN c.ano = 2025 THEN 'RC' || lpad((abs(hashtext(c.id::text)) % 999999)::text, 6, '0') END,
         CASE WHEN c.ano = 2025 THEN 'Evento processado com sucesso (demonstração)'
              WHEN c.rn = 3 AND t.tipo = 'S-1200' THEN 'Rejeitado: base de cálculo divergente. Corrigir o valor e remontar o evento (demonstração)' END,
         CASE WHEN c.ano = 2025 THEN 1 ELSE 0 END, 'Leiri Nuernberg', 'decimo_terceiro', c.id, c.ano, c.parcela,
         c.ano::text, 2, 'S-1.2', regexp_replace(c.colaborador_cpf, '[^0-9]', '', 'g'),
         make_date(c.ano + (CASE WHEN c.ano = 2025 THEN 1 ELSE 0 END), 1, 15),
         c.created_at + interval '2 days'
  FROM (SELECT x.*, row_number() OVER (PARTITION BY x.ano, x.parcela ORDER BY md5(x.id::text)) AS rn
        FROM public.folha_13_calculo x
        WHERE x.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND x.status IN ('aprovado', 'pago')) c
  CROSS JOIN (VALUES ('S-1200'), ('S-1210')) AS t(tipo)
  WHERE c.rn <= 12
    AND NOT EXISTS (SELECT 1 FROM public.esocial_transmissoes e WHERE e.id = public.demo_id('esocial13:' || t.tipo || ':' || c.id::text));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(6c) eventos eSocial do 13o nao semeados: % (%)', SQLERRM, SQLSTATE;
END $s_13_esocial$;

-- ---------------------------------------------------------------------------
-- (7) Rescisoes: dois desligados reais da base, mais ex-colaboradores ficticios
--     (em calculo, em conferencia, aprovada, paga e reaberta)
-- ---------------------------------------------------------------------------
DO $s_rescisoes$
BEGIN
  INSERT INTO public.folha_rescisoes (
    id, tenant_id, colaborador_id, colaborador_nome, colaborador_cpf, admissao_id, tipo_vinculo, tipo_rescisao, data_desligamento,
    data_aviso, aviso_tipo, dias_aviso, motivo, saldo_salario, dias_saldo, aviso_previo_valor, ferias_vencidas, ferias_proporcionais,
    terco_ferias, decimo_terceiro_proporcional, base_inss, valor_inss, base_irrf, valor_irrf, base_fgts, valor_fgts, multa_fgts,
    aliquota_multa_fgts, total_bruto, total_descontos, total_liquido, status, data_pagamento, prazo_legal, memoria_calculo,
    aprovado_por_nome, aprovado_em, created_at
  )
  WITH fonte AS (
    SELECT public.demo_id('rescisao:adm:' || a.id::text) AS rid, a.id::text AS cid, a.nome_completo AS nome, a.cpf, a.id AS aid,
           CASE WHEN a.motivo_desligamento ILIKE 'Pedido%' THEN 'PEDIDO_DEMISSAO' ELSE 'DISPENSA_SEM_JUSTA_CAUSA' END AS tipo,
           a.data_admissao AS adm, a.data_desligamento AS deslig, a.salario::numeric AS sal,
           CASE WHEN a.motivo_desligamento ILIKE 'Pedido%' THEN 'trabalhado' ELSE 'indenizado' END AS aviso, 30 AS davi,
           a.motivo_desligamento AS motivo,
           CASE WHEN a.motivo_desligamento ILIKE 'Pedido%' THEN 'paga' ELSE 'aprovada' END AS situacao
    FROM public.admissoes a
    WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a.status = 'desligado'
    UNION ALL
    SELECT public.demo_id('rescisao:ex:' || v.n), 'ex-' || v.n, v.nome, public.demo_cpf(200 + v.n), NULL::uuid, v.tipo,
           CURRENT_DATE - v.adm_dias, CURRENT_DATE + v.deslig_off, v.sal, v.aviso, v.davi, v.motivo, v.situacao
    FROM (VALUES
      (1, 'Rogério Tavares Lins',    'ACORDO_484A',              1500, -95, 3300::numeric, 'indenizado', 15, 'Acordo entre as partes (art. 484-A)',        'paga'),
      (2, 'Sandra Mara Pacheco',     'DISPENSA_SEM_JUSTA_CAUSA', 2600, -150, 3100::numeric, 'indenizado', 30, 'Reestruturação do setor de logística',     'paga'),
      (3, 'Vitor Hugo Camargo',      'TERMINO_EXPERIENCIA',      90,   -70, 2700::numeric, 'trabalhado', 0,  'Término do contrato de experiência',        'paga'),
      (4, 'Elaine Cristina Duarte',  'PEDIDO_DEMISSAO',          900,   5,  3900::numeric, 'trabalhado', 30, 'Pedido de demissão com aviso trabalhado',  'em_calculo'),
      (5, 'Marcelo Antunes Dias',    'DISPENSA_SEM_JUSTA_CAUSA', 2100, -45, 4200::numeric, 'indenizado', 33, 'Dispensa; verbas complementares em revisão', 'reaberta'),
      (6, 'Fabiana Rocha Moura',     'PEDIDO_DEMISSAO',          1200, -8,  3600::numeric, 'trabalhado', 30, 'Pedido de demissão',                         'em_conferencia')
    ) AS v(n, nome, tipo, adm_dias, deslig_off, sal, aviso, davi, motivo, situacao)
  ), t1 AS (
    SELECT f.*, GREATEST(1, extract(day FROM f.deslig)::int) AS dsaldo,
           GREATEST(0, (extract(year FROM age(f.deslig, f.adm)) * 12 + extract(month FROM age(f.deslig, f.adm)))::int) AS meses_casa
    FROM fonte f
  ), t2 AS (
    SELECT t.*, round(t.sal / 30 * t.dsaldo, 2) AS saldo,
           CASE WHEN t.aviso = 'indenizado' THEN round(t.sal / 30 * t.davi, 2) ELSE 0 END AS aviso_v,
           CASE WHEN t.meses_casa >= 12 THEN round(t.sal, 2) ELSE 0 END AS fer_venc,
           round(t.sal * (t.meses_casa % 12) / 12, 2) AS fer_prop,
           round(t.sal * LEAST(extract(month FROM t.deslig)::int, 12) / 12, 2) AS d13
    FROM t1 t
  ), t3 AS (
    SELECT t.*, round((t.fer_venc + t.fer_prop) / 3, 2) AS terco FROM t2 t
  ), t4 AS (
    SELECT t.*, t.saldo + t.aviso_v + t.fer_venc + t.fer_prop + t.terco + t.d13 AS bruto,
           t.saldo + t.aviso_v + t.d13 AS binss, public.demo_calc_inss(t.saldo + t.aviso_v + t.d13) AS inss FROM t3 t
  ), t5 AS (
    SELECT t.*, public.demo_calc_irrf(t.binss - t.inss, 0) AS irrf,
           CASE WHEN t.tipo = 'DISPENSA_SEM_JUSTA_CAUSA' THEN 40 WHEN t.tipo = 'ACORDO_484A' THEN 20 ELSE 0 END AS aliq_multa,
           round(t.sal * 0.08 * t.meses_casa, 2) AS saldo_fgts
    FROM t4 t
  )
  SELECT t.rid, 'd3e00000-0000-4000-8000-000000000001', t.cid, t.nome, t.cpf, t.aid, 'CLT_PRAZO_INDETERMINADO', t.tipo::public.rescisao_tipo,
         t.deslig, t.deslig - 30, t.aviso, t.davi, t.motivo, t.saldo, t.dsaldo, t.aviso_v, t.fer_venc, t.fer_prop, t.terco, t.d13,
         t.binss, t.inss, t.binss - t.inss, t.irrf, t.binss, round(t.binss * 0.08, 2), round(t.saldo_fgts * t.aliq_multa / 100, 2), t.aliq_multa,
         t.bruto, t.inss + t.irrf, t.bruto - t.inss - t.irrf, t.situacao::public.rescisao_status,
         CASE WHEN t.situacao = 'paga' THEN t.deslig + 8 END, t.deslig + 10,
         jsonb_build_object('observacao', 'Cálculo de demonstração', 'meses_de_casa', t.meses_casa),
         CASE WHEN t.situacao IN ('aprovada', 'paga', 'reaberta') THEN 'Leiri Nuernberg' END,
         CASE WHEN t.situacao IN ('aprovada', 'paga', 'reaberta') THEN (t.deslig + 4)::timestamptz END,
         (t.deslig - 5)::timestamptz
  FROM t5 t
  WHERE NOT EXISTS (SELECT 1 FROM public.folha_rescisoes x WHERE x.id = t.rid);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(7) rescisoes nao semeadas: % (%)', SQLERRM, SQLSTATE;
END $s_rescisoes$;

-- ---------------------------------------------------------------------------
-- (8) Alertas de prazo da folha (4 competencias) e alertas do 13o
--     A chave unica do banco nao inclui a competencia; por isso o campo "faixa"
--     leva a competencia (e "ano" o ano) para os alertas mensais conviverem.
-- ---------------------------------------------------------------------------
DO $s_alertas$
BEGIN
  INSERT INTO public.folha_alertas_prazo (
    id, tenant_id, empresa_id, competencia, tipo, descricao, data_limite, status, concluido_em, concluido_por, severidade, faixa, ano
  )
  WITH meses AS (
    SELECT to_char(m, 'YYYY-MM') AS comp, m::date AS ini, (m + interval '1 month')::date AS prox,
           extract(year FROM m)::int AS ano, g.k
    FROM generate_series(0, 3) AS g(k)
    CROSS JOIN LATERAL (SELECT date_trunc('month', CURRENT_DATE) - (g.k || ' months')::interval AS m) q
  ), tipos AS (
    SELECT * FROM (VALUES
      ('fechamento_folha', 'Fechar folha de %s para cálculo de proventos e descontos', 'fim_mes', 0),
      ('pagamento',        'Pagamento dos salários ref. %s (até o 5º dia útil)',        'dia',     7),
      ('esocial_s1200',    'Envio do evento S-1200 (Remuneração) ref. %s',              'dia',     15),
      ('esocial_s1210',    'Envio do evento S-1210 (Pagamentos) ref. %s',               'dia',     15),
      ('dctfweb',          'Transmissão da DCTFWeb ref. %s',                            'dia',     15),
      ('fgts',             'Recolhimento do FGTS Digital ref. %s',                      'dia',     20),
      ('inss_patronal',    'Recolhimento do INSS patronal ref. %s',                     'dia',     20)
    ) AS t(tipo, modelo, regra, dia)
  ), alvo AS (
    SELECT m.*, t.tipo, replace(t.modelo, '%s', m.comp) AS descr,
           CASE WHEN t.regra = 'fim_mes' THEN (m.prox - 1) ELSE (m.prox + (t.dia - 1)) END AS limite
    FROM meses m CROSS JOIN tipos t
  )
  SELECT public.demo_id('folhaalerta:' || a.comp || ':' || a.tipo), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
         a.comp, a.tipo, a.descr, a.limite,
         CASE WHEN a.k >= 2 THEN 'concluido'
              WHEN a.k = 1 AND a.tipo IN ('fechamento_folha', 'pagamento') THEN 'concluido'
              WHEN a.k = 1 AND a.limite < CURRENT_DATE THEN 'atrasado'
              WHEN a.k = 0 AND a.tipo = 'fechamento_folha' AND a.limite < CURRENT_DATE THEN 'atrasado'
              ELSE 'pendente' END,
         CASE WHEN a.k >= 2 OR (a.k = 1 AND a.tipo IN ('fechamento_folha', 'pagamento')) THEN (a.limite - 1)::timestamptz END,
         CASE WHEN a.k >= 2 OR (a.k = 1 AND a.tipo IN ('fechamento_folha', 'pagamento')) THEN 'Leiri Nuernberg' END,
         CASE WHEN a.tipo IN ('fgts', 'dctfweb', 'inss_patronal') THEN 'alta' ELSE 'media' END, a.comp, a.ano
  FROM alvo a
  WHERE NOT EXISTS (SELECT 1 FROM public.folha_alertas_prazo x WHERE x.id = public.demo_id('folhaalerta:' || a.comp || ':' || a.tipo));

  -- Alertas do 13o salario (valem para o ano inteiro)
  INSERT INTO public.folha_alertas_prazo (
    id, tenant_id, empresa_id, competencia, tipo, descricao, data_limite, status, colaborador_id, colaborador_nome, severidade, faixa, ano
  )
  SELECT public.demo_id('folhaalerta13:' || v.chave), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
         v.comp, v.tipo, v.descr, v.limite, 'pendente', a.id::text, a.nome_completo, v.sev, v.faixa, extract(year FROM CURRENT_DATE)::int
  FROM (VALUES
    ('p1', to_char(make_date(extract(year FROM CURRENT_DATE)::int, 11, 1), 'YYYY-MM'), 'decimo_terceiro_1a_parcela',
        '1ª parcela do 13º salário: pagar até 30/11 (cálculos já gerados, aguardando aprovação)', make_date(extract(year FROM CURRENT_DATE)::int, 11, 30), 'alta', 'parcela-1', NULL::int),
    ('p2', to_char(make_date(extract(year FROM CURRENT_DATE)::int, 12, 1), 'YYYY-MM'), 'decimo_terceiro_2a_parcela',
        '2ª parcela do 13º salário: pagar até 20/12 (com INSS e IRRF)', make_date(extract(year FROM CURRENT_DATE)::int, 12, 20), 'media', 'parcela-2', NULL),
    ('base', to_char(CURRENT_DATE, 'YYYY-MM'), 'decimo_terceiro_base_incompleta',
        'Média de variáveis do 13º incompleta: faltam lançamentos de horas extras de um colaborador', CURRENT_DATE + 12, 'media', 'base', 12),
    ('afast', to_char(CURRENT_DATE, 'YYYY-MM'), 'decimo_terceiro_afastamento',
        'Afastamento previdenciário a validar na contagem de avos do 13º', CURRENT_DATE + 20, 'media', 'afastamento', 30)
  ) AS v(chave, comp, tipo, descr, limite, sev, faixa, n)
  LEFT JOIN public.admissoes a ON v.n IS NOT NULL AND a.id = public.demo_id('admissao:' || v.n)
  WHERE NOT EXISTS (SELECT 1 FROM public.folha_alertas_prazo x WHERE x.id = public.demo_id('folhaalerta13:' || v.chave));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(8) alertas de prazo nao semeados: % (%)', SQLERRM, SQLSTATE;
END $s_alertas$;

-- ---------------------------------------------------------------------------
-- (9) Beneficios: tipos e vinculo de cada colaborador (custos mensais e descontos)
-- ---------------------------------------------------------------------------
DO $s_beneficios_tipos$
BEGIN
  INSERT INTO public.beneficios_tipos (
    id, tenant_id, nome, categoria, descricao, valor_padrao, tipo_desconto, percentual_desconto, valor_desconto_fixo, ativo,
    limite_participacao_pat, limite_vigencia_inicio
  )
  SELECT public.demo_id('beneficiotipo:' || v.nome), 'd3e00000-0000-4000-8000-000000000001', v.nome, v.cat, v.descr, v.valor,
         v.tdesc, v.pdesc, v.fdesc, v.ativo, v.pat, DATE '2025-01-01'
  FROM (VALUES
    ('Vale Alimentação',        'alimentacao', 'Crédito mensal em cartão alimentação (PAT).',                         650.00, 'percentual', 1.00, 0.00,  true,  20.00),
    ('Refeição no Refeitório',  'alimentacao', 'Almoço servido no refeitório da empresa para a produção e logística.', 480.00, 'percentual', 10.00, 0.00, true,  20.00),
    ('Plano de Saúde',          'saude',       'Plano médico-hospitalar com coparticipação, extensivo a dependentes.',   480.00, 'fixo',       0.00, 96.00, true,  NULL),
    ('Plano Odontológico',      'saude',       'Cobertura odontológica nacional.',                                       38.00,  'fixo',       0.00, 12.00, true,  NULL),
    ('Vale-Transporte',         'transporte',  'Vale-transporte conforme itinerário informado (desconto de até 6%).',    242.00, 'percentual', 6.00, 0.00,  true,  NULL),
    ('Seguro de Vida em Grupo', 'seguro',      'Seguro de vida em grupo previsto na convenção coletiva.',                18.00,  'fixo',       0.00, 0.00,  true,  NULL),
    ('Auxílio-Creche',          'outros',      'Reembolso de creche até os 5 anos e 11 meses do filho.',                 450.00, 'fixo',       0.00, 0.00,  true,  NULL),
    ('Wellhub (academia)',      'outros',      'Programa de bem-estar com acesso a academias parceiras.',                99.00,  'fixo',       0.00, 30.00, true,  NULL),
    ('Auxílio Educação',        'outros',      'Programa encerrado: bolsa para cursos técnicos (mantido para histórico).', 300.00, 'fixo',     0.00, 0.00,  false, NULL)
  ) AS v(nome, cat, descr, valor, tdesc, pdesc, fdesc, ativo, pat)
  WHERE NOT EXISTS (SELECT 1 FROM public.beneficios_tipos x WHERE x.id = public.demo_id('beneficiotipo:' || v.nome));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(9a) tipos de beneficio nao semeados: % (%)', SQLERRM, SQLSTATE;
END $s_beneficios_tipos$;

DO $s_beneficios_vinculos$
BEGIN
  INSERT INTO public.beneficios_colaboradores (
    id, tenant_id, beneficio_tipo_id, colaborador_id, colaborador_nome, colaborador_cpf, valor, valor_desconto, data_inicio, data_fim,
    status, motivo_cancelamento, observacoes, empresa_id
  )
  WITH col AS MATERIALIZED (
    SELECT a.id, a.nome_completo, a.cpf, a.salario::numeric AS sal, a.departamento, a.status AS st, a.data_admissao, a.data_desligamento,
           abs(hashtext(a.id::text)) AS h
    FROM public.admissoes a
    WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a.status IN ('concluido', 'desligado')
  ), linhas AS (
    SELECT c.*, 'Vale Alimentação' AS tipo, 650.00::numeric AS valor, 6.50::numeric AS desconto FROM col c
    UNION ALL
    SELECT c.*, 'Refeição no Refeitório', 480.00, 48.00 FROM col c WHERE c.departamento IN ('Produção', 'Manutenção', 'Logística')
    UNION ALL
    SELECT c.*, 'Plano de Saúde', 480.00, 96.00 FROM col c WHERE c.h % 10 < 7
    UNION ALL
    SELECT c.*, 'Plano Odontológico', 38.00, 12.00 FROM col c WHERE c.h % 2 = 0
    UNION ALL
    SELECT c.*, 'Vale-Transporte', 242.00, round(LEAST(c.sal * 0.06, 242), 2) FROM col c WHERE c.h % 5 <> 0
    UNION ALL
    SELECT c.*, 'Seguro de Vida em Grupo', 18.00, 0.00 FROM col c
    UNION ALL
    SELECT c.*, 'Auxílio-Creche', 450.00, 0.00 FROM col c WHERE c.h % 12 = 0
    UNION ALL
    SELECT c.*, 'Wellhub (academia)', 99.00, 30.00 FROM col c WHERE c.h % 7 = 0
    UNION ALL
    SELECT c.*, 'Auxílio Educação', 300.00, 0.00 FROM col c WHERE c.h % 19 = 0 AND c.st = 'concluido'
  )
  SELECT public.demo_id('beneficiovinculo:' || l.tipo || ':' || l.id::text), 'd3e00000-0000-4000-8000-000000000001',
         public.demo_id('beneficiotipo:' || l.tipo), l.id::text, l.nome_completo, l.cpf, l.valor, l.desconto,
         GREATEST(l.data_admissao, DATE '2024-01-01'),
         CASE WHEN l.st = 'desligado' OR l.tipo = 'Auxílio Educação' THEN COALESCE(l.data_desligamento, CURRENT_DATE - 120) END,
         CASE WHEN l.st = 'desligado' OR l.tipo = 'Auxílio Educação' THEN 'cancelado' ELSE 'ativo' END,
         CASE WHEN l.st = 'desligado' THEN 'Desligamento do colaborador'
              WHEN l.tipo = 'Auxílio Educação' THEN 'Programa encerrado' END,
         CASE WHEN l.tipo = 'Plano de Saúde' AND l.h % 3 = 0 THEN 'Inclui 1 dependente' END,
         'd3e00000-0000-4000-8000-000000000002'
  FROM linhas l
  WHERE NOT EXISTS (SELECT 1 FROM public.beneficios_colaboradores x WHERE x.id = public.demo_id('beneficiovinculo:' || l.tipo || ':' || l.id::text));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(9b) vinculos de beneficio nao semeados: % (%)', SQLERRM, SQLSTATE;
END $s_beneficios_vinculos$;

-- ---------------------------------------------------------------------------
-- (10) Hub Contabil: contabilidades, configuracao e processos de todos os tipos
-- ---------------------------------------------------------------------------
DO $s_hub_base$
BEGIN
  INSERT INTO public.hub_contabilidades (id, tenant_id, nome, cnpj, email_principal, email_notificacoes, telefone, responsavel_nome, ativo, observacoes)
  SELECT public.demo_id('hubcontab:' || v.n), 'd3e00000-0000-4000-8000-000000000001', v.nome, v.cnpj, v.email, v.email2, v.tel, v.resp, true, v.obs
  FROM (VALUES
    (1, 'Contabilidade Exemplo & Associados', '11.222.333/0001-81', 'contato@contabilidade-exemplo.demo', 'dp@contabilidade-exemplo.demo', '(47) 3333-4000', 'Marta Cristina Olivetto', 'Escritório responsável pela folha, eSocial e obrigações acessórias.'),
    (2, 'Escritório Fiscal Sul', '22.333.444/0001-62', 'atendimento@fiscalsul-exemplo.demo', NULL, '(41) 3222-5000', 'Paulo Henrique Vasconcelos', 'Apoio em assuntos trabalhistas da filial Curitiba.')
  ) AS v(n, nome, cnpj, email, email2, tel, resp, obs)
  WHERE NOT EXISTS (SELECT 1 FROM public.hub_contabilidades x WHERE x.id = public.demo_id('hubcontab:' || v.n));

  INSERT INTO public.hub_config (
    id, tenant_id, empresa_id, modulo_ativo, contabilidade_id, sla_admissao, sla_demissao, sla_ferias, sla_advertencia, sla_folha,
    sla_geral, auto_gerar_admissao, auto_gerar_demissao, auto_gerar_ferias, auto_gerar_advertencia, auto_gerar_atestado,
    auto_gerar_folha, notificar_email, notificar_sistema, observacoes
  )
  SELECT public.demo_id('hubconfig:1'), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002', true,
         public.demo_id('hubcontab:1'), 24, 48, 72, 48, 120, 72, true, true, true, true, true, true, true, true,
         'Prazos combinados com a contabilidade em contrato de prestação de serviços.'
  WHERE NOT EXISTS (SELECT 1 FROM public.hub_config x
                    WHERE x.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND x.empresa_id = 'd3e00000-0000-4000-8000-000000000002');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(10a) base do Hub nao semeada: % (%)', SQLERRM, SQLSTATE;
END $s_hub_base$;

DO $s_hub_processos$
BEGIN
  INSERT INTO public.hub_processos (
    id, tenant_id, empresa_id, contabilidade_id, tipo, status, prioridade, titulo, descricao, colaborador_id, colaborador_nome,
    colaborador_cpf, colaborador_matricula, competencia, data_referencia, data_limite, origem_modulo, origem_descricao,
    gerado_automaticamente, enviado_em, enviado_por, recebido_em, processado_em, concluido_em, cancelado_em, cancelado_por,
    motivo_cancelamento, sla_horas, sla_vencimento, sla_status, protocolo_externo, created_at
  )
  WITH v AS (
    SELECT * FROM (VALUES
      (1,  'admissao',             'enviado_contabilidade',  'alta',    'Admissão',                   64,  NULL, 2,   24, 'admissoes',   true),
      (2,  'admissao',             'aguardando_documentos',  'normal',  'Admissão',                   63,  NULL, 3,   24, 'admissoes',   true),
      (3,  'admissao',             'rascunho',               'normal',  'Admissão',                   62,  NULL, 1,   24, 'admissoes',   true),
      (4,  'admissao',             'concluido',              'normal',  'Admissão',                   57,  NULL, 9,   24, 'admissoes',   true),
      (5,  'admissao',             'concluido',              'normal',  'Admissão',                   58,  NULL, 10,  24, 'admissoes',   true),
      (6,  'admissao',             'em_analise',             'normal',  'Admissão',                   59,  NULL, 7,   24, 'admissoes',   true),
      (7,  'demissao',             'processado',             'normal',  'Desligamento',               60,  NULL, 38,  48, 'admissoes',   true),
      (8,  'demissao',             'pendente_complementacao','urgente', 'Desligamento',               61,  NULL, 38,  48, 'admissoes',   true),
      (9,  'demissao',             'concluido',              'normal',  'Rescisão (ex-colaboradora)', NULL, NULL, 94, 48, 'folha',       false),
      (10, 'ferias',               'concluido',              'normal',  'Férias',                     5,   NULL, 40,  72, 'ferias',      true),
      (11, 'ferias',               'concluido',              'normal',  'Férias',                     8,   NULL, 21,  72, 'ferias',      true),
      (12, 'ferias',               'aguardando_assinatura',  'normal',  'Férias',                     12,  NULL, 6,   72, 'ferias',      true),
      (13, 'ferias',               'enviado_contabilidade',  'normal',  'Férias',                     17,  NULL, 3,   72, 'ferias',      true),
      (14, 'ferias',               'pronto_para_envio',      'normal',  'Férias',                     24,  NULL, 1,   72, 'ferias',      true),
      (15, 'ferias',               'recebido_contabilidade', 'normal',  'Férias',                     31,  NULL, 4,   72, 'ferias',      true),
      (16, 'advertencia',          'concluido',              'normal',  'Advertência',                14,  NULL, 30,  48, 'feedback',    false),
      (17, 'advertencia',          'aguardando_assinatura',  'alta',    'Advertência',                19,  NULL, 5,   48, 'feedback',    false),
      (18, 'atestado_afastamento', 'em_analise',             'alta',    'Afastamento por doença',     26,  NULL, 8,   72, 'atestados',   true),
      (19, 'atestado_afastamento', 'concluido',              'normal',  'Atestado médico',            33,  NULL, 27,  72, 'atestados',   true),
      (20, 'atestado_afastamento', 'pendente_complementacao','alta',    'Afastamento previdenciário', 44,  NULL, 12,  72, 'atestados',   true),
      (21, 'ponto_folha',          'pronto_para_envio',      'normal',  'Fechamento de ponto',        NULL, 0,    1,   120, 'ponto',      true),
      (22, 'ponto_folha',          'enviado_contabilidade',  'alta',    'Fechamento de ponto',        NULL, 1,    18,  120, 'ponto',      true),
      (23, 'ponto_folha',          'concluido',              'normal',  'Fechamento de ponto',        NULL, 2,    48,  120, 'ponto',      true),
      (24, 'ponto_folha',          'concluido',              'normal',  'Fechamento de ponto',        NULL, 3,    78,  120, 'ponto',      true),
      (25, 'ponto_folha',          'concluido',              'normal',  'Fechamento de ponto',        NULL, 4,    108, 120, 'ponto',      true),
      (26, 'eventos_variaveis',    'rascunho',               'normal',  'Eventos variáveis',          NULL, 0,    1,   72,  'folha',      false),
      (27, 'eventos_variaveis',    'concluido',              'normal',  'Eventos variáveis',          NULL, 1,    32,  72,  'folha',      false),
      (28, 'eventos_variaveis',    'recebido_contabilidade', 'normal',  'Eventos variáveis',          NULL, 1,    16,  72,  'folha',      false),
      (29, 'solicitacao_geral',    'em_analise',             'normal',  'Solicitação',                NULL, NULL, 6,   72,  NULL,         false),
      (30, 'solicitacao_geral',    'aguardando_documentos',  'baixa',   'Solicitação',                NULL, NULL, 4,   72,  NULL,         false),
      (31, 'alteracao_contratual', 'aguardando_assinatura',  'normal',  'Alteração contratual',       36,  NULL, 5,   72,  NULL,         false),
      (32, 'alteracao_contratual', 'concluido',              'normal',  'Alteração contratual',       47,  NULL, 52,  72,  NULL,         false),
      (33, 'mudanca_salarial',     'processado',             'normal',  'Reajuste salarial',          9,   NULL, 14,  72,  NULL,         false),
      (34, 'mudanca_salarial',     'concluido',              'normal',  'Promoção com reajuste',      28,  NULL, 65,  72,  NULL,         false),
      (35, 'cat',                  'enviado_contabilidade',  'urgente', 'Comunicação de acidente',    16,  NULL, 2,   24,  'incidentes',  true),
      (36, 'ppp_ltcat',            'documentos_devolvidos',  'normal',  'PPP',                        60,  NULL, 20,  72,  'sst',         false),
      (37, 'pro_labore',           'concluido',              'normal',  'Pró-labore dos sócios',      NULL, 1,    33,  72,  NULL,         false),
      (38, 'solicitacao_geral',    'cancelado',              'baixa',   'Solicitação cancelada',      NULL, NULL, 25,  72,  NULL,         false),
      (39, 'ponto_folha',          'erro_integracao',        'alta',    'Integração de ponto',        NULL, 0,    2,   120, 'ponto',      true)
    ) AS t(n, tipo, status, prio, titulo, colab, comp_off, dias, sla, origem, auto)
  ), b AS (
    SELECT v.*, a.id AS aid, a.nome_completo, a.cpf,
           (now() - (v.dias || ' days')::interval) AS criado,
           CASE WHEN v.comp_off IS NOT NULL THEN to_char(date_trunc('month', CURRENT_DATE) - (v.comp_off || ' months')::interval, 'YYYY-MM') END AS competencia,
           CASE v.status WHEN 'rascunho' THEN 1 WHEN 'aguardando_documentos' THEN 2 WHEN 'pronto_para_envio' THEN 3
             WHEN 'enviado_contabilidade' THEN 4 WHEN 'recebido_contabilidade' THEN 5 WHEN 'em_analise' THEN 6
             WHEN 'pendente_complementacao' THEN 6 WHEN 'processado' THEN 7 WHEN 'documentos_devolvidos' THEN 8
             WHEN 'aguardando_assinatura' THEN 9 WHEN 'assinado_parcialmente' THEN 10 WHEN 'concluido' THEN 11 ELSE 0 END AS pos
    FROM v LEFT JOIN public.admissoes a ON v.colab IS NOT NULL AND a.id = public.demo_id('admissao:' || v.colab)
  )
  SELECT public.demo_id('hubproc:' || b.n), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
         public.demo_id('hubcontab:' || CASE WHEN b.n IN (20, 33) THEN 2 ELSE 1 END),
         b.tipo::public.hub_processo_tipo, b.status::public.hub_processo_status, b.prio::public.hub_prioridade,
         b.titulo || COALESCE(' — ' || b.nome_completo, COALESCE(' — ' || b.competencia, '')),
         CASE WHEN b.n = 8 THEN 'Faltam o termo de quitação assinado e o comprovante de devolução de EPIs.'
              WHEN b.n = 20 THEN 'Contabilidade pediu o laudo do INSS e a data de alta programada.'
              WHEN b.n = 39 THEN 'Falha ao importar os dados do relógio de ponto; reprocessar a competência.'
              WHEN b.n = 38 THEN 'Solicitação aberta em duplicidade.'
              ELSE 'Processo de demonstração gerado para a Metalúrgica Exemplo.' END,
         b.aid::text, b.nome_completo, b.cpf, CASE WHEN b.aid IS NOT NULL THEN 'MAT-' || lpad((abs(hashtext(b.aid::text)) % 9000 + 1000)::text, 5, '0') END,
         COALESCE(b.competencia, to_char(b.criado, 'YYYY-MM')), b.criado::date, (b.criado + ((b.sla / 24 + 2) || ' days')::interval)::date,
         b.origem, CASE WHEN b.auto THEN 'Gerado automaticamente pelo módulo de origem' END, b.auto,
         CASE WHEN b.pos >= 4 THEN b.criado + interval '1 day' END, CASE WHEN b.pos >= 4 THEN 'Leiri Nuernberg' END,
         CASE WHEN b.pos >= 5 THEN b.criado + interval '1 day 6 hours' END,
         CASE WHEN b.pos >= 7 THEN b.criado + interval '3 days' END,
         CASE WHEN b.pos = 11 THEN b.criado + interval '5 days' END,
         CASE WHEN b.status = 'cancelado' THEN b.criado + interval '1 day' END, CASE WHEN b.status = 'cancelado' THEN 'Leiri Nuernberg' END,
         CASE WHEN b.status = 'cancelado' THEN 'Aberta em duplicidade' END,
         b.sla,
         CASE WHEN b.status = 'concluido' THEN NULL
              WHEN b.n IN (8, 13, 17, 22, 39) THEN b.criado + (b.sla || ' hours')::interval
              ELSE GREATEST(b.criado + (b.sla || ' hours')::interval, now() + (((b.n % 5) + 1) * 20 || ' hours')::interval) END,
         CASE WHEN b.status IN ('concluido', 'cancelado') THEN 'concluido'
              WHEN b.n IN (8, 13, 17, 22, 39) THEN 'vencido'
              WHEN ((b.n % 5) + 1) * 20 < 48 THEN 'em_risco'
              ELSE 'no_prazo' END,
         CASE WHEN b.pos >= 4 THEN 'PROT-' || to_char(b.criado, 'YYMM') || '-' || lpad(b.n::text, 4, '0') END,
         b.criado
  FROM b
  WHERE NOT EXISTS (SELECT 1 FROM public.hub_processos x WHERE x.id = public.demo_id('hubproc:' || b.n));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(10b) processos do Hub nao semeados: % (%)', SQLERRM, SQLSTATE;
END $s_hub_processos$;

-- Documentos, assinaturas, comentarios, historico e checklist dos processos
DO $s_hub_detalhes$
BEGIN
  -- Documento principal de cada processo + devolutiva da contabilidade quando ja houve retorno
  INSERT INTO public.hub_processo_documentos (
    id, tenant_id, processo_id, tipo, nome, descricao, origem, arquivo_nome, arquivo_tamanho, arquivo_mime, versao, eh_versao_final,
    eh_obrigatorio, status, requer_assinatura, assinatura_status, enviado_por, created_at
  )
  WITH p AS MATERIALIZED (
    SELECT hp.*, CASE hp.status::text WHEN 'rascunho' THEN 1 WHEN 'aguardando_documentos' THEN 2 WHEN 'pronto_para_envio' THEN 3
             WHEN 'enviado_contabilidade' THEN 4 WHEN 'recebido_contabilidade' THEN 5 WHEN 'em_analise' THEN 6
             WHEN 'pendente_complementacao' THEN 6 WHEN 'processado' THEN 7 WHEN 'documentos_devolvidos' THEN 8
             WHEN 'aguardando_assinatura' THEN 9 WHEN 'assinado_parcialmente' THEN 10 WHEN 'concluido' THEN 11 ELSE 0 END AS pos,
           hp.tipo::text IN ('ferias', 'advertencia', 'demissao', 'alteracao_contratual', 'mudanca_salarial') AS assina
    FROM public.hub_processos hp
    WHERE hp.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND hp.id IN (SELECT public.demo_id('hubproc:' || g.n) FROM generate_series(1, 39) g(n))
  ), d AS (
    SELECT p.*, 1 AS seq,
           CASE p.tipo::text WHEN 'admissao' THEN 'ficha_registro' WHEN 'demissao' THEN 'aviso_previo' WHEN 'ferias' THEN 'aviso_ferias'
             WHEN 'advertencia' THEN 'advertencia' WHEN 'ponto_folha' THEN 'espelho_ponto' WHEN 'eventos_variaveis' THEN 'relatorio_folha'
             WHEN 'solicitacao_geral' THEN 'declaracao' WHEN 'alteracao_contratual' THEN 'aditivo' WHEN 'mudanca_salarial' THEN 'aditivo'
             WHEN 'ppp_ltcat' THEN 'laudo' ELSE 'outros' END AS dtipo,
           CASE WHEN p.gerado_automaticamente THEN 'sistema_automatico' ELSE 'upload_rh' END AS dorigem
    FROM p WHERE p.pos >= 2
    UNION ALL
    SELECT p.*, 2,
           CASE p.tipo::text WHEN 'demissao' THEN 'trct' WHEN 'ferias' THEN 'recibo_ferias' WHEN 'ponto_folha' THEN 'relatorio_folha'
             WHEN 'admissao' THEN 'contrato' WHEN 'advertencia' THEN 'advertencia' WHEN 'alteracao_contratual' THEN 'aditivo'
             WHEN 'mudanca_salarial' THEN 'aditivo' WHEN 'ppp_ltcat' THEN 'laudo' WHEN 'eventos_variaveis' THEN 'relatorio_folha' ELSE 'outros' END,
           'devolutiva_contabilidade'
    FROM p WHERE p.pos >= 8 AND p.status::text <> 'cancelado'
  )
  SELECT public.demo_id('hubdoc:' || regexp_replace(d.id::text, '-', '', 'g') || ':' || d.seq), d.tenant_id, d.id,
         d.dtipo::public.hub_doc_tipo,
         CASE WHEN d.seq = 1 THEN replace(initcap(replace(d.dtipo, '_', ' ')), ' ', '') ELSE 'Devolutiva - ' || replace(initcap(replace(d.dtipo, '_', ' ')), ' ', '') END,
         CASE WHEN d.seq = 1 THEN 'Documento enviado pelo RH à contabilidade.' ELSE 'Documento devolvido pela contabilidade após o processamento.' END,
         d.dorigem::public.hub_doc_origem,
         'demo-' || d.dtipo || '-' || d.seq || '.pdf', 120000 + d.seq * 35000, 'application/pdf', 1, d.seq = 2 OR d.pos < 8, true,
         CASE WHEN d.pos >= 7 THEN 'aprovado' WHEN d.pos >= 4 THEN 'recebido' ELSE 'pendente' END,
         d.assina AND d.seq = 2,
         CASE WHEN d.assina AND d.seq = 2 THEN (CASE WHEN d.pos = 11 THEN 'assinado' WHEN d.pos >= 9 THEN 'enviado' ELSE 'pendente' END)::public.hub_assinatura_status END,
         CASE WHEN d.seq = 1 THEN 'Leiri Nuernberg' ELSE 'Contabilidade Exemplo & Associados' END,
         d.created_at + (d.seq * interval '10 hours')
  FROM d
  WHERE NOT EXISTS (SELECT 1 FROM public.hub_processo_documentos x
                    WHERE x.id = public.demo_id('hubdoc:' || regexp_replace(d.id::text, '-', '', 'g') || ':' || d.seq));

  -- Assinaturas (colaborador e empresa) nos processos que chegaram a essa etapa
  INSERT INTO public.hub_processo_assinaturas (
    id, tenant_id, processo_id, documento_id, signatario_nome, signatario_email, signatario_cpf, signatario_papel, ordem, expira_em,
    status, assinado_em, created_at
  )
  SELECT public.demo_id('hubass:' || regexp_replace(hp.id::text, '-', '', 'g') || ':' || s.ordem), hp.tenant_id, hp.id, doc.id,
         CASE WHEN s.ordem = 1 THEN COALESCE(hp.colaborador_nome, 'Colaborador') ELSE 'Leiri Nuernberg' END,
         CASE WHEN s.ordem = 1 THEN 'colaborador' || (abs(hashtext(hp.id::text)) % 60) || '@metalurgica-exemplo.demo' ELSE 'rh@metalurgica-exemplo.demo' END,
         CASE WHEN s.ordem = 1 THEN hp.colaborador_cpf END, CASE WHEN s.ordem = 1 THEN 'colaborador' ELSE 'empresa' END, s.ordem,
         now() + interval '10 days',
         (CASE WHEN hp.status::text = 'concluido' THEN 'assinado' WHEN s.ordem = 2 THEN 'assinado' ELSE 'enviado' END)::public.hub_assinatura_status,
         CASE WHEN hp.status::text = 'concluido' OR s.ordem = 2 THEN hp.created_at + interval '3 days' END,
         hp.created_at + interval '2 days'
  FROM public.hub_processos hp
  JOIN public.hub_processo_documentos doc ON doc.processo_id = hp.id AND doc.requer_assinatura
  CROSS JOIN (VALUES (1), (2)) AS s(ordem)
  WHERE hp.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
    AND hp.status::text IN ('aguardando_assinatura', 'assinado_parcialmente', 'concluido')
    AND NOT EXISTS (SELECT 1 FROM public.hub_processo_assinaturas x
                    WHERE x.id = public.demo_id('hubass:' || regexp_replace(hp.id::text, '-', '', 'g') || ':' || s.ordem));

  -- Comentarios (RH e contabilidade), inclusive pendencias abertas e resolvidas
  INSERT INTO public.hub_processo_comentarios (
    id, tenant_id, processo_id, autor_nome, autor_perfil, conteudo, eh_interno, eh_pendencia, pendencia_resolvida,
    pendencia_resolvida_em, created_at
  )
  SELECT public.demo_id('hubcom:' || v.n || ':' || v.seq), 'd3e00000-0000-4000-8000-000000000001', public.demo_id('hubproc:' || v.n),
         v.autor, v.perfil, v.texto, v.interno, v.pend, v.resolvida,
         CASE WHEN v.resolvida THEN hp.created_at + (v.horas + 20 || ' hours')::interval END,
         hp.created_at + (v.horas || ' hours')::interval
  FROM (VALUES
    (1,  1, 'Leiri Nuernberg',          'rh',          'Enviado o pacote de admissão com exame admissional e documentos pessoais.', false, false, false, 6),
    (1,  2, 'Marta Olivetto',           'contador',    'Recebido. Iniciamos o registro e o evento S-2200 do eSocial.',             false, false, false, 10),
    (2,  1, 'Leiri Nuernberg',          'rh',          'Aguardando o candidato entregar comprovante de residência e PIS.',         true,  true,  false, 4),
    (6,  1, 'Marta Olivetto',           'contador',    'Conferimos a ficha de registro. Falta apenas o número do PIS.',            false, true,  true,  12),
    (6,  2, 'Leiri Nuernberg',          'rh',          'PIS informado e anexado ao processo.',                                     false, false, false, 30),
    (8,  1, 'Marta Olivetto',           'contador',    'Para fechar o TRCT precisamos do termo de quitação assinado e do comprovante de devolução de EPIs.', false, true, false, 8),
    (8,  2, 'Leiri Nuernberg',          'rh',          'Solicitado ao ex-colaborador. Retorno previsto em 3 dias úteis.',          true,  false, false, 20),
    (12, 1, 'Marta Olivetto',           'contador',    'Recibo de férias devolvido para assinatura do colaborador.',               false, false, false, 24),
    (17, 1, 'Leiri Nuernberg',          'rh',          'Advertência entregue ao colaborador, aguardando assinatura.',              true,  false, false, 5),
    (18, 1, 'Camila Fontes Barreto',    'rh',          'Atestado de 18 dias anexado. Avaliar encaminhamento ao INSS.',             true,  false, false, 5),
    (20, 1, 'Marta Olivetto',           'contador',    'Precisamos do laudo do INSS e da data de alta programada para o eSocial S-2230.', false, true, false, 10),
    (22, 1, 'Marta Olivetto',           'contador',    'Espelho de ponto recebido. Há 3 colaboradores com horas extras acima do limite; confirmar.', false, true, false, 14),
    (22, 2, 'Leiri Nuernberg',          'rh',          'Confirmado com os gestores. Seguem as justificativas no anexo.',           false, false, false, 28),
    (31, 1, 'Marta Olivetto',           'contador',    'Aditivo de mudança de função enviado para assinatura.',                    false, false, false, 8),
    (35, 1, 'Marcos Vinícius Teles',    'rh',          'CAT emitida e protocolada. Acompanhar o prazo de comunicação ao INSS.',    false, false, false, 3),
    (36, 1, 'Marta Olivetto',           'contador',    'PPP devolvido com os dados de exposição atualizados.',                     false, false, false, 20),
    (39, 1, 'Sistema',                  'sistema',     'Falha na importação das marcações do relógio. Reprocessar a competência.',  true,  true,  false, 2)
  ) AS v(n, seq, autor, perfil, texto, interno, pend, resolvida, horas)
  JOIN public.hub_processos hp ON hp.id = public.demo_id('hubproc:' || v.n)
  WHERE NOT EXISTS (SELECT 1 FROM public.hub_processo_comentarios x WHERE x.id = public.demo_id('hubcom:' || v.n || ':' || v.seq));

  -- Historico de situacoes de cada processo (do rascunho ate a situacao atual)
  INSERT INTO public.hub_processo_historico (
    id, tenant_id, processo_id, acao, status_anterior, status_novo, usuario_nome, perfil, descricao, created_at
  )
  WITH pipe AS (
    SELECT u.s, u.i::int AS i
    FROM unnest(ARRAY['rascunho', 'aguardando_documentos', 'pronto_para_envio', 'enviado_contabilidade', 'recebido_contabilidade',
                      'em_analise', 'processado', 'documentos_devolvidos', 'aguardando_assinatura', 'assinado_parcialmente', 'concluido'])
         WITH ORDINALITY AS u(s, i)
  ), proc AS (
    SELECT hp.*, CASE hp.status::text WHEN 'pendente_complementacao' THEN 6 WHEN 'cancelado' THEN 2 WHEN 'erro_integracao' THEN 3
                 ELSE (SELECT pp.i FROM pipe pp WHERE pp.s = hp.status::text) END AS pos
    FROM public.hub_processos hp
    WHERE hp.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND hp.id IN (SELECT public.demo_id('hubproc:' || g.n) FROM generate_series(1, 39) g(n))
  ), passos AS (
    SELECT pr.id AS pid, pr.tenant_id, pr.created_at, pipe.i, pipe.s, lag(pipe.s) OVER (PARTITION BY pr.id ORDER BY pipe.i) AS anterior,
           pr.status::text AS final_status, pr.pos
    FROM proc pr JOIN pipe ON pipe.i <= pr.pos
  )
  SELECT public.demo_id('hubhist:' || regexp_replace(p.pid::text, '-', '', 'g') || ':' || p.i), p.tenant_id, p.pid,
         CASE WHEN p.i = 1 THEN 'criado' ELSE 'status_alterado' END,
         p.anterior::public.hub_processo_status, p.s::public.hub_processo_status,
         CASE WHEN p.i IN (5, 6, 7, 8) THEN 'Marta Olivetto' ELSE 'Leiri Nuernberg' END,
         CASE WHEN p.i IN (5, 6, 7, 8) THEN 'contador' ELSE 'rh' END,
         CASE WHEN p.i = 1 THEN 'Processo criado' ELSE 'Status alterado de ' || p.anterior || ' para ' || p.s END,
         p.created_at + (p.i * interval '7 hours')
  FROM passos p
  WHERE NOT EXISTS (SELECT 1 FROM public.hub_processo_historico x
                    WHERE x.id = public.demo_id('hubhist:' || regexp_replace(p.pid::text, '-', '', 'g') || ':' || p.i));

  INSERT INTO public.hub_processo_historico (
    id, tenant_id, processo_id, acao, status_anterior, status_novo, usuario_nome, perfil, descricao, created_at
  )
  SELECT public.demo_id('hubhist:' || regexp_replace(hp.id::text, '-', '', 'g') || ':final'), hp.tenant_id, hp.id, 'status_alterado',
         CASE hp.status::text WHEN 'pendente_complementacao' THEN 'em_analise' WHEN 'cancelado' THEN 'aguardando_documentos'
              ELSE 'pronto_para_envio' END::public.hub_processo_status,
         hp.status, CASE WHEN hp.status::text = 'pendente_complementacao' THEN 'Marta Olivetto' ELSE 'Leiri Nuernberg' END,
         CASE WHEN hp.status::text = 'pendente_complementacao' THEN 'contador' ELSE 'rh' END,
         CASE hp.status::text WHEN 'pendente_complementacao' THEN 'A contabilidade solicitou complementação de documentos'
              WHEN 'cancelado' THEN 'Processo cancelado: aberto em duplicidade'
              ELSE 'Falha de integração ao enviar os dados' END,
         hp.created_at + interval '3 days'
  FROM public.hub_processos hp
  WHERE hp.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND hp.status::text IN ('pendente_complementacao', 'cancelado', 'erro_integracao')
    AND NOT EXISTS (SELECT 1 FROM public.hub_processo_historico x
                    WHERE x.id = public.demo_id('hubhist:' || regexp_replace(hp.id::text, '-', '', 'g') || ':final'));

  -- Checklist (criado pelo banco a partir dos modelos): marca o avanco conforme a situacao do processo
  UPDATE public.hub_processo_checklist c
     SET concluido = (r.rn <= r.alvo), concluido_em = CASE WHEN r.rn <= r.alvo THEN COALESCE(c.concluido_em, now() - interval '1 day') END,
         concluido_por = CASE WHEN r.rn <= r.alvo THEN COALESCE(c.concluido_por, 'Leiri Nuernberg') END
    FROM (
      SELECT ck.id, row_number() OVER (PARTITION BY ck.processo_id ORDER BY ck.ordem, ck.item) AS rn,
             ceil(count(*) OVER (PARTITION BY ck.processo_id) *
               (CASE hp.status::text WHEN 'rascunho' THEN 0.0 WHEN 'aguardando_documentos' THEN 0.2 WHEN 'pronto_para_envio' THEN 0.6
                  WHEN 'enviado_contabilidade' THEN 0.7 WHEN 'recebido_contabilidade' THEN 0.8 WHEN 'em_analise' THEN 0.8
                  WHEN 'pendente_complementacao' THEN 0.6 WHEN 'processado' THEN 0.9 WHEN 'documentos_devolvidos' THEN 0.9
                  WHEN 'aguardando_assinatura' THEN 0.9 WHEN 'assinado_parcialmente' THEN 0.95 WHEN 'concluido' THEN 1.0 ELSE 0.3 END))::int AS alvo
      FROM public.hub_processo_checklist ck
      JOIN public.hub_processos hp ON hp.id = ck.processo_id
      WHERE ck.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
        AND hp.id IN (SELECT public.demo_id('hubproc:' || g.n) FROM generate_series(1, 39) g(n))
    ) r
   WHERE c.id = r.id AND c.concluido IS DISTINCT FROM (r.rn <= r.alvo);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(10c) detalhes dos processos do Hub nao semeados: % (%)', SQLERRM, SQLSTATE;
END $s_hub_detalhes$;

-- Competencias, guias, certidoes, documentos de competencia e calendario de envios
-- (tabelas do modulo de comunicacao contabil por competencia)
DO $s_hub_competencias$
BEGIN
  INSERT INTO public.hub_competencias (id, tenant_id, competencia, status, data_envio, data_aprovacao, data_finalizacao, enviado_por, aprovado_por, observacoes, checklist)
  SELECT public.demo_id('hubcomp:' || c.comp), 'd3e00000-0000-4000-8000-000000000001', c.comp,
         CASE c.k WHEN 0 THEN 'em_preparacao' WHEN 1 THEN 'em_conferencia' WHEN 2 THEN 'aprovado' ELSE 'finalizado' END,
         CASE WHEN c.k >= 1 THEN c.ini + interval '1 month 2 days' END,
         CASE WHEN c.k >= 2 THEN c.ini + interval '1 month 6 days' END,
         CASE WHEN c.k >= 3 THEN c.ini + interval '1 month 9 days' END,
         CASE WHEN c.k >= 1 THEN 'Leiri Nuernberg' END, CASE WHEN c.k >= 2 THEN 'Marta Olivetto' END,
         'Competência de demonstração', '[]'::jsonb
  FROM (SELECT to_char(m, 'YYYY-MM') AS comp, m AS ini, g.k
        FROM generate_series(0, 5) AS g(k)
        CROSS JOIN LATERAL (SELECT date_trunc('month', CURRENT_DATE) - (g.k || ' months')::interval AS m) q) c
  WHERE NOT EXISTS (SELECT 1 FROM public.hub_competencias x WHERE x.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND x.competencia = c.comp);

  INSERT INTO public.hub_guias (id, tenant_id, competencia_id, competencia, tipo, descricao, valor, data_vencimento, data_pagamento, status, observacoes)
  SELECT public.demo_id('hubguia:' || c.comp || ':' || t.tipo), 'd3e00000-0000-4000-8000-000000000001', public.demo_id('hubcomp:' || c.comp), c.comp,
         t.tipo, t.descr || ' ref. ' || c.comp, round(t.valor * (1 + (c.k * -0.01)), 2), (c.ini + interval '1 month')::date + t.dia - 1,
         CASE WHEN c.k >= 1 THEN (c.ini + interval '1 month')::date + t.dia - 3 END,
         CASE WHEN c.k >= 1 THEN 'paga' ELSE 'pendente' END, NULL
  FROM (SELECT to_char(m, 'YYYY-MM') AS comp, m::date AS ini, g.k
        FROM generate_series(0, 5) AS g(k)
        CROSS JOIN LATERAL (SELECT date_trunc('month', CURRENT_DATE) - (g.k || ' months')::interval AS m) q) c
  CROSS JOIN (VALUES ('inss', 'GPS - INSS patronal e empregados', 62000.00, 20), ('fgts', 'FGTS Digital', 18700.00, 20),
                     ('irrf', 'DARF - IRRF sobre folha', 9400.00, 20)) AS t(tipo, descr, valor, dia)
  WHERE NOT EXISTS (SELECT 1 FROM public.hub_guias x WHERE x.id = public.demo_id('hubguia:' || c.comp || ':' || t.tipo));

  INSERT INTO public.hub_certidoes (id, tenant_id, tipo, orgao_emissor, numero, data_emissao, data_validade, observacoes)
  SELECT public.demo_id('hubcert:' || v.tipo), 'd3e00000-0000-4000-8000-000000000001', v.tipo, v.orgao, v.numero, CURRENT_DATE + v.emis, CURRENT_DATE + v.valid, v.obs
  FROM (VALUES
    ('receita_federal', 'Receita Federal do Brasil', 'CND-2026-000123', -80, 100, 'Certidão conjunta de débitos federais.'),
    ('fgts',            'Caixa Econômica Federal',  'CRF-2026-004567', -25, 5,   'Certificado de regularidade do FGTS: renovar nos próximos dias.'),
    ('cndt',            'Tribunal Superior do Trabalho', 'CNDT-2026-778899', -150, 30, 'Certidão negativa de débitos trabalhistas.'),
    ('estadual',        'Secretaria da Fazenda de SC', 'EST-2026-3321', -200, -20, 'Vencida: solicitar nova certidão.'),
    ('municipal',       'Prefeitura de Joinville',  'MUN-2026-0099',    -40, 140, NULL)
  ) AS v(tipo, orgao, numero, emis, valid, obs)
  WHERE NOT EXISTS (SELECT 1 FROM public.hub_certidoes x WHERE x.id = public.demo_id('hubcert:' || v.tipo));

  INSERT INTO public.hub_documentos (id, tenant_id, competencia_id, competencia, tipo, descricao, arquivo_nome, arquivo_tamanho, versao, direcao, enviado_por, status, created_at)
  SELECT public.demo_id('hubdocc:' || c.comp || ':' || t.tipo), 'd3e00000-0000-4000-8000-000000000001', public.demo_id('hubcomp:' || c.comp), c.comp,
         t.tipo, t.descr, 'demo-' || t.tipo || '-' || c.comp || '.pdf', 180000, 1, t.dir,
         CASE WHEN t.dir = 'enviado' THEN 'Leiri Nuernberg' ELSE 'Contabilidade Exemplo & Associados' END, 'ativo',
         c.ini + interval '1 month 3 days'
  FROM (SELECT to_char(m, 'YYYY-MM') AS comp, m AS ini, g.k
        FROM generate_series(1, 5) AS g(k)
        CROSS JOIN LATERAL (SELECT date_trunc('month', CURRENT_DATE) - (g.k || ' months')::interval AS m) q) c
  CROSS JOIN (VALUES ('relatorio_folha', 'Relatório analítico da folha', 'enviado'), ('holerite', 'Holerites da competência', 'recebido'),
                     ('darf', 'Guia DARF paga', 'recebido'), ('fgts', 'Comprovante FGTS Digital', 'recebido')) AS t(tipo, descr, dir)
  WHERE NOT EXISTS (SELECT 1 FROM public.hub_documentos x WHERE x.id = public.demo_id('hubdocc:' || c.comp || ':' || t.tipo));

  INSERT INTO public.hub_calendario_envios (id, tenant_id, titulo, tipo, categoria, dia_limite, descricao, ativo)
  SELECT public.demo_id('hubcal:' || v.n), 'd3e00000-0000-4000-8000-000000000001', v.titulo, v.tipo, v.cat, v.dia, v.descr, true
  FROM (VALUES
    (1, 'Enviar movimentações e ponto fechado',   'envio',   'folha',   25, 'Movimentações do mês (admissões, desligamentos, faltas e horas extras).'),
    (2, 'Pagamento de salários',                  'pagamento','folha',  7,  'Pagar até o 5º dia útil.'),
    (3, 'Recolhimento do FGTS Digital',           'guia',    'fgts',    20, 'Guia gerada pela contabilidade.'),
    (4, 'Recolhimento do INSS (GPS/DCTFWeb)',     'guia',    'inss',    20, 'Guia conforme DCTFWeb transmitida.'),
    (5, 'Envio do S-1200 e S-1210 ao eSocial',    'envio',   'esocial', 15, 'Remuneração e pagamentos da competência anterior.'),
    (6, 'DARF do IRRF sobre a folha',             'guia',    'irrf',    20, 'Código de receita 0561.')
  ) AS v(n, titulo, tipo, cat, dia, descr)
  WHERE NOT EXISTS (SELECT 1 FROM public.hub_calendario_envios x WHERE x.id = public.demo_id('hubcal:' || v.n));

  INSERT INTO public.hub_calendario_status (id, tenant_id, calendario_id, competencia, status, concluido_por, concluido_em)
  SELECT public.demo_id('hubcalst:' || v.n || ':' || to_char(m, 'YYYY-MM')), 'd3e00000-0000-4000-8000-000000000001', public.demo_id('hubcal:' || v.n),
         to_char(m, 'YYYY-MM'), 'concluido', 'Leiri Nuernberg', m + interval '1 month 2 days'
  FROM generate_series(1, 6) AS v(n)
  CROSS JOIN generate_series(date_trunc('month', CURRENT_DATE) - interval '3 months', date_trunc('month', CURRENT_DATE) - interval '1 month', interval '1 month') AS m
  WHERE EXISTS (SELECT 1 FROM public.hub_calendario_envios e WHERE e.id = public.demo_id('hubcal:' || v.n))
    AND NOT EXISTS (SELECT 1 FROM public.hub_calendario_status x WHERE x.id = public.demo_id('hubcalst:' || v.n || ':' || to_char(m, 'YYYY-MM')));

  INSERT INTO public.hub_historico (id, tenant_id, competencia, tipo_documento, acao, usuario_nome, perfil, descricao, created_at)
  SELECT public.demo_id('hubhistc:' || c.comp || ':' || a.acao), 'd3e00000-0000-4000-8000-000000000001', c.comp, a.tdoc, a.acao,
         a.quem, a.perfil, a.descr || ' (' || c.comp || ')', c.ini + (a.dias || ' days')::interval
  FROM (SELECT to_char(m, 'YYYY-MM') AS comp, m AS ini FROM generate_series(date_trunc('month', CURRENT_DATE) - interval '3 months', date_trunc('month', CURRENT_DATE) - interval '1 month', interval '1 month') AS m) c
  CROSS JOIN (VALUES ('enviado', 'relatorio_folha', 'Leiri Nuernberg', 'rh', 'Relatório da folha enviado à contabilidade', 33),
                     ('recebido', 'holerite', 'Marta Olivetto', 'contador', 'Holerites recebidos da contabilidade', 36),
                     ('aprovado', 'relatorio_folha', 'Leiri Nuernberg', 'rh', 'Competência aprovada pelo RH', 38)) AS a(acao, tdoc, quem, perfil, descr, dias)
  WHERE NOT EXISTS (SELECT 1 FROM public.hub_historico x WHERE x.id = public.demo_id('hubhistc:' || c.comp || ':' || a.acao));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(10d) competencias/guias/certidoes do Hub nao semeadas: % (%)', SQLERRM, SQLSTATE;
END $s_hub_competencias$;

-- ---------------------------------------------------------------------------
-- Conferencia final (UMA consulta): contagens do que foi semeado para o tenant demo
-- ---------------------------------------------------------------------------
SELECT
  (SELECT count(*) FROM public.folha_periodos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS periodos_folha,
  (SELECT count(*) FROM public.folha_itens WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS itens_folha,
  (SELECT count(*) FROM public.folha_lancamentos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS lancamentos,
  (SELECT count(*) FROM public.folha_rubricas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS rubricas,
  (SELECT count(*) FROM public.folha_provisoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS provisoes,
  (SELECT count(*) FROM public.folha_ferias_calculo WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS ferias,
  (SELECT count(*) FROM public.folha_13_calculo WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS decimo_terceiro,
  (SELECT count(*) FROM public.folha_rescisoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS rescisoes,
  (SELECT count(*) FROM public.folha_alertas_prazo WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS alertas,
  (SELECT count(*) FROM public.beneficios_tipos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS beneficios_tipos,
  (SELECT count(*) FROM public.beneficios_colaboradores WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS beneficios_vinculos,
  (SELECT count(*) FROM public.hub_processos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS hub_processos,
  (SELECT count(*) FROM public.hub_processo_documentos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS hub_documentos,
  (SELECT count(*) FROM public.hub_competencias WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS hub_competencias,
  CASE WHEN (SELECT count(*) FROM public.folha_periodos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 6
        AND (SELECT count(*) FROM public.folha_itens WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 300
        AND (SELECT count(*) FROM public.beneficios_colaboradores WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 200
        AND (SELECT count(*) FROM public.hub_processos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 39
       THEN 'OK' ELSE 'CONFERIR' END AS situacao;
