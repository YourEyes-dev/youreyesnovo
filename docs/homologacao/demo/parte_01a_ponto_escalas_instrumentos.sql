-- ============================================================================
-- HOMOLOGACAO — DEMONSTRACAO, PARTE 01a: Ponto: escalas, atribuicoes, feriados e instrumentos
--
-- PARA QUE SERVE
-- Configuracao do ponto, catalogo de justificativas, escalas (44h e 6x2), blocos diarios,
-- atribuicao aos colaboradores que batem ponto, cerca (geofence) da matriz, feriados,
-- acordo/CCT, regime do banco de horas e intervalo pre-assinalado.
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
-- (2) Configuracao do ponto, catalogo de justificativas
-- ---------------------------------------------------------------------------
DO $w1$
BEGIN
INSERT INTO public.ponto_configuracao (
  tenant_id, hora_entrada_padrao, hora_saida_almoco_padrao, hora_retorno_almoco_padrao, hora_saida_padrao,
  tolerancia_atraso, tolerancia_hora_extra, permitir_registro_fora_horario, exigir_localizacao,
  bloquear_dispositivo_nao_autorizado, modo_registro, exigir_selfie_link, exigir_selfie_interno, modo_apuracao,
  jornada_diaria_max_minutos, jornada_semanal_max_minutos, he_diaria_max_minutos, interjornada_min_minutos,
  controle_ponto_ativo, dia_curto_bloqueia_fechamento_minutos
)
SELECT 'd3e00000-0000-4000-8000-000000000001', '08:00', '12:00', '13:00', '17:48',
       10, 10, true, true, false, 'ambos', true, false, 'padrao',
       600, 2640, 120, 660, true, 60
WHERE NOT EXISTS (SELECT 1 FROM public.ponto_configuracao WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_configuracao nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w1$;

-- Cerca (geofence) da matriz: as batidas passam a registrar se foram dentro ou fora da empresa
DO $w2$
BEGIN
UPDATE public.empresa_cadastro
   SET latitude = -26.3045, longitude = -48.8487, raio_geofence_metros = COALESCE(raio_geofence_metros, 150), geofence_ativo = true
 WHERE id = 'd3e00000-0000-4000-8000-000000000002'
   AND tenant_id = 'd3e00000-0000-4000-8000-000000000001'
   AND latitude IS NULL AND longitude IS NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco empresa_cadastro nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w2$;

DO $just$
BEGIN
  PERFORM public.seed_justificativas_padrao('d3e00000-0000-4000-8000-000000000001');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Justificativas padrao nao semeadas: % (%)', SQLERRM, SQLSTATE;
END $just$;

DO $w3$
BEGIN
INSERT INTO public.ponto_justificativas (id, tenant_id, empresa_id, nome, codigo, descricao, tipo_abono, requer_anexo, horas_abono, base_legal, sistema, ativo, ordem)
SELECT public.demo_id('ponto_just:' || v.codigo), 'd3e00000-0000-4000-8000-000000000001', NULL,
       v.nome, v.codigo, v.descricao, v.tipo_abono, v.anexo, 0, v.base_legal, v.base_legal IS NOT NULL, true, v.ordem
FROM (VALUES
  ('DECLARACAO_COMPARECIMENTO', 'DECLARAÇÃO DE COMPARECIMENTO', 'Comparecimento a consulta, exame ou órgão público por algumas horas.', 'configuravel', true, NULL::text, 20),
  ('CONSULTA_MEDICA', 'CONSULTA MÉDICA / EXAME', 'Consulta ou exame médico do próprio colaborador, com comprovante.', 'configuravel', true, NULL, 21),
  ('DOACAO_SANGUE', 'DOAÇÃO DE SANGUE', 'Um dia a cada 12 meses, mediante comprovação.', 'sim', true, 'CLT art. 473, IV', 22),
  ('CASAMENTO', 'CASAMENTO (3 DIAS)', 'Até 3 dias consecutivos em virtude de casamento.', 'sim', true, 'CLT art. 473, II', 23),
  ('FALECIMENTO_FAMILIAR', 'FALECIMENTO DE FAMILIAR', 'Até 2 dias consecutivos em caso de falecimento de familiar.', 'sim', true, 'CLT art. 473, I', 24),
  ('ESQUECIMENTO_BATIDA', 'ESQUECIMENTO DE BATIDA', 'Inclusão de marcação esquecida, sem abono de horas.', 'nao', false, NULL, 25)
) AS v(codigo, nome, descricao, tipo_abono, anexo, base_legal, ordem)
WHERE NOT EXISTS (
  SELECT 1 FROM public.ponto_justificativas j
  WHERE j.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND j.empresa_id IS NULL AND j.codigo = v.codigo
);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_justificativas nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w3$;

-- ---------------------------------------------------------------------------
-- (3) Escalas (44h e 6x2) + blocos diarios
--     Obs.: 44h = segunda a sexta, 8h48 por dia (528 min trabalhados).
--           6x2 = revezamento de 6h, dois grupos com folgas diferentes.
-- ---------------------------------------------------------------------------
DO $w4$
BEGIN
INSERT INTO public.ponto_escalas (
  id, tenant_id, empresa_id, nome, tipo, modalidade, jornada_diaria_minutos, jornada_semanal_minutos,
  intervalo_intrajornada_minutos, tolerancia_minutos, tolerancia_diaria_minutos,
  hora_entrada_padrao, hora_saida_padrao, sabado_util, domingo_util, ativa,
  carga_semanal_contratada_min, dias_config, descricao_contratual, observacoes, origem_input
)
SELECT public.demo_id('ponto_escala:' || v.chave), 'd3e00000-0000-4000-8000-000000000001',
       'd3e00000-0000-4000-8000-000000000002', v.nome, v.tipo, v.modalidade, v.jornada, v.semanal,
       v.interv, 5, 10, v.ent::time, v.sai::time, v.sab, v.dom, true, v.semanal,
       (SELECT jsonb_object_agg(d.dia,
                CASE WHEN d.dia = ANY (v.folgas) THEN jsonb_build_object('trabalha', false)
                     ELSE jsonb_build_object('trabalha', true, 'entrada', v.ent, 'saida', v.sai,
                                             'tem_almoco', true, 'inicio_almoco', v.ia, 'fim_almoco', v.fa) END)
        FROM (VALUES ('segunda'),('terca'),('quarta'),('quinta'),('sexta'),('sabado'),('domingo')) AS d(dia)),
       v.contrato, v.obs, 'manual'
FROM (VALUES
  ('adm44', 'Administrativo 44h (Seg a Sex, 08:00-17:48)', '5x2', 'fixa', 528, 2640, 60, '08:00', '17:48', '12:00', '13:00', false, false,
     ARRAY['sabado','domingo'],
     'Jornada de 44 horas semanais, de segunda a sexta, das 08:00 às 17:48, com 1 hora de intervalo.',
     'Escala dos setores administrativos, RH e comercial.'),
  ('ind44', 'Industrial 44h - Turno A (Seg a Sex, 06:00-15:48)', '5x2', 'fixa', 528, 2640, 60, '06:00', '15:48', '11:00', '12:00', false, false,
     ARRAY['sabado','domingo'],
     'Jornada de 44 horas semanais, de segunda a sexta, das 06:00 às 15:48, com 1 hora de intervalo.',
     'Turno A da produção, manutenção e logística.'),
  ('rev6x2a', 'Revezamento 6x2 - Turno B, Grupo 1 (folga Dom e Seg)', 'personalizada', 'revezamento', 345, 2070, 15, '14:00', '20:00', '17:00', '17:15', true, false,
     ARRAY['segunda','domingo'],
     'Turno de revezamento de 6 horas (14:00 às 20:00) com 15 minutos de intervalo, jornada efetiva de 5h45; seis dias de trabalho e duas folgas (grupo 1: domingo e segunda).',
     'Turno B da produção. Jornada de 6h conforme CF art. 7º, XIV.'),
  ('rev6x2b', 'Revezamento 6x2 - Turno B, Grupo 2 (folga Qua e Qui)', 'personalizada', 'revezamento', 345, 2070, 15, '14:00', '20:00', '17:00', '17:15', true, true,
     ARRAY['quarta','quinta'],
     'Turno de revezamento de 6 horas (14:00 às 20:00) com 15 minutos de intervalo, jornada efetiva de 5h45; seis dias de trabalho e duas folgas (grupo 2: quarta e quinta).',
     'Turno B da produção. Jornada de 6h conforme CF art. 7º, XIV.')
) AS v(chave, nome, tipo, modalidade, jornada, semanal, interv, ent, sai, ia, fa, sab, dom, folgas, contrato, obs)
WHERE NOT EXISTS (SELECT 1 FROM public.ponto_escalas e WHERE e.id = public.demo_id('ponto_escala:' || v.chave));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_escalas nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w4$;

-- Blocos diarios (mesma conta que a tela faz ao salvar a escala).
DO $w5$
BEGIN
INSERT INTO public.ponto_escala_periodos (id, tenant_id, escala_id, dia_semana, ordem_bloco, hora_inicio, hora_fim)
SELECT public.demo_id('ponto_per:' || b.escala_id || ':' || b.dia || ':' || b.ordem),
       'd3e00000-0000-4000-8000-000000000001', b.escala_id, b.dia, b.ordem, b.ini::time, b.fim::time
FROM (
  SELECT e.id AS escala_id, k.dia, 1 AS ordem, k.cfg ->> 'entrada' AS ini, k.cfg ->> 'inicio_almoco' AS fim
  FROM public.ponto_escalas e CROSS JOIN LATERAL jsonb_each(e.dias_config) AS k(dia, cfg)
  WHERE e.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND (k.cfg ->> 'trabalha')::boolean
  UNION ALL
  SELECT e.id, k.dia, 2, k.cfg ->> 'fim_almoco', k.cfg ->> 'saida'
  FROM public.ponto_escalas e CROSS JOIN LATERAL jsonb_each(e.dias_config) AS k(dia, cfg)
  WHERE e.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND (k.cfg ->> 'trabalha')::boolean
) b
WHERE NOT EXISTS (
  SELECT 1 FROM public.ponto_escala_periodos p
  WHERE p.id = public.demo_id('ponto_per:' || b.escala_id || ':' || b.dia || ':' || b.ordem)
);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_escala_periodos nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w5$;

-- ---------------------------------------------------------------------------
-- (4) Atribuicao de escala aos colaboradores que batem ponto (status concluido)
--     Administrativo/RH/Comercial -> 44h adm, Producao/Manutencao: n par -> 6x2
--     (grupo 1 ou 2), n impar -> Turno A, Logistica -> Turno A.
--     Dois colaboradores (15 e 33) mudaram do Turno A para o 6x2 no mes passado.
-- ---------------------------------------------------------------------------
DO $w6$
BEGIN
INSERT INTO public.ponto_escala_atribuicoes (id, tenant_id, escala_id, colaborador_id, colaborador_nome, colaborador_cpf, data_inicio, data_fim, ativa)
SELECT public.demo_id('ponto_atrib:' || x.n || ':' || x.fase),
       'd3e00000-0000-4000-8000-000000000001', public.demo_id('ponto_escala:' || x.escala),
       x.id::text, x.nome, x.cpf, x.inicio, x.fim, x.ativa
FROM (
  -- vigencia atual (ou unica)
  SELECT s.n, 'atual' AS fase, a.id, a.nome_completo AS nome, a.cpf,
         CASE
           WHEN s.n IN (15, 33) THEN (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '1 month')::date
           ELSE GREATEST(a.data_admissao, (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date)
         END AS inicio,
         NULL::date AS fim, true AS ativa,
         CASE
           WHEN a.departamento IN ('Administrativo', 'Recursos Humanos', 'Comercial') THEN 'adm44'
           WHEN a.departamento IN ('Produção', 'Manutenção') AND s.n % 2 = 0 THEN CASE WHEN s.n % 4 = 0 THEN 'rev6x2a' ELSE 'rev6x2b' END
           WHEN s.n IN (15, 33) THEN 'rev6x2a'
           ELSE 'ind44'
         END AS escala
  FROM generate_series(1, 59) s(n)
  JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || s.n)
  WHERE a.status = 'concluido' AND COALESCE(a.bate_ponto, true)
  UNION ALL
  -- vigencia anterior dos que mudaram de escala
  SELECT s.n, 'anterior', a.id, a.nome_completo, a.cpf,
         GREATEST(a.data_admissao, (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date),
         (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '1 month')::date - 1,
         false, 'ind44'
  FROM generate_series(1, 59) s(n)
  JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || s.n)
  WHERE a.status = 'concluido' AND s.n IN (15, 33)
) x
WHERE x.inicio <= COALESCE(x.fim, x.inicio)
  AND NOT EXISTS (
    SELECT 1 FROM public.ponto_escala_atribuicoes pa
    WHERE pa.id = public.demo_id('ponto_atrib:' || x.n || ':' || x.fase)
  );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_escala_atribuicoes nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w6$;

-- ---------------------------------------------------------------------------
-- (5) Feriados (nacionais, SC e Joinville) + tabela nomeada por unidade
--     So entra feriado que ainda nao esta visivel para o tenant (global ou proprio).
-- ---------------------------------------------------------------------------
DO $w7$
BEGIN
INSERT INTO public.feriados (id, tenant_id, empresa_id, nome, tipo, abrangencia, data, recorrente, ativo, uf, municipio, observacao)
SELECT public.demo_id('feriado:' || v.data::text || ':' || v.abr), 'd3e00000-0000-4000-8000-000000000001', NULL,
       v.nome, v.tipo, v.abr, v.data, false, true,
       CASE WHEN v.abr = 'nacional' THEN NULL ELSE 'SC' END,
       CASE WHEN v.abr = 'municipal' THEN 'Joinville' ELSE NULL END,
       'Calendário da empresa demonstração'
FROM (VALUES
  (DATE '2026-01-01', 'Confraternização Universal', 'feriado', 'nacional'),
  (DATE '2026-02-16', 'Carnaval (segunda-feira)', 'facultativo', 'nacional'),
  (DATE '2026-02-17', 'Carnaval (terça-feira)', 'facultativo', 'nacional'),
  (DATE '2026-03-09', 'Aniversário de Joinville', 'feriado', 'municipal'),
  (DATE '2026-04-03', 'Sexta-feira Santa', 'feriado', 'nacional'),
  (DATE '2026-04-21', 'Tiradentes', 'feriado', 'nacional'),
  (DATE '2026-05-01', 'Dia do Trabalho', 'feriado', 'nacional'),
  (DATE '2026-06-04', 'Corpus Christi', 'facultativo', 'nacional'),
  (DATE '2026-08-11', 'Dia de Santa Catarina', 'feriado', 'estadual'),
  (DATE '2026-09-07', 'Independência do Brasil', 'feriado', 'nacional'),
  (DATE '2026-10-12', 'Nossa Senhora Aparecida', 'feriado', 'nacional'),
  (DATE '2026-11-02', 'Finados', 'feriado', 'nacional'),
  (DATE '2026-11-15', 'Proclamação da República', 'feriado', 'nacional'),
  (DATE '2026-11-20', 'Consciência Negra', 'feriado', 'nacional'),
  (DATE '2026-12-25', 'Natal', 'feriado', 'nacional'),
  (DATE '2027-01-01', 'Confraternização Universal', 'feriado', 'nacional')
) AS v(data, nome, tipo, abr)
WHERE NOT EXISTS (
  SELECT 1 FROM public.feriados f
  WHERE f.data = v.data AND f.abrangencia = v.abr
    AND (f.tenant_id IS NULL OR f.tenant_id = 'd3e00000-0000-4000-8000-000000000001')
);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco feriados nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w7$;

-- Tabela nomeada de feriados, vinculada a matriz (aba Configuracoes > Feriados)
DO $w8$
BEGIN
INSERT INTO public.feriado_tabelas (id, tenant_id, nome, uf, municipio, codigo_ibge, ano, descricao, ativo)
SELECT public.demo_id('feriado_tabela:joinville2026'), 'd3e00000-0000-4000-8000-000000000001',
       'Calendário Joinville/SC 2026', 'SC', 'Joinville', '4209102', 2026,
       'Feriados municipais e estaduais aplicados à matriz e às unidades de Joinville.', true
WHERE NOT EXISTS (SELECT 1 FROM public.feriado_tabelas WHERE id = public.demo_id('feriado_tabela:joinville2026'));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco feriado_tabelas nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w8$;

DO $w9$
BEGIN
INSERT INTO public.feriado_tabela_itens (id, tenant_id, tabela_id, nome, data, recorrente, dia, mes, tipo, ativo)
SELECT public.demo_id('feriado_item:' || v.chave), 'd3e00000-0000-4000-8000-000000000001',
       public.demo_id('feriado_tabela:joinville2026'), v.nome, v.data, false, EXTRACT(DAY FROM v.data)::smallint, EXTRACT(MONTH FROM v.data)::smallint, v.tipo, true
FROM (VALUES
  ('aniv', 'Aniversário de Joinville', DATE '2026-03-09', 'feriado'),
  ('sc', 'Dia de Santa Catarina', DATE '2026-08-11', 'feriado'),
  ('recesso', 'Recesso de fim de ano (ponto facultativo)', DATE '2026-12-24', 'facultativo'),
  ('recesso2', 'Recesso de fim de ano (ponto facultativo)', DATE '2026-12-31', 'facultativo')
) AS v(chave, nome, data, tipo)
WHERE EXISTS (SELECT 1 FROM public.feriado_tabelas WHERE id = public.demo_id('feriado_tabela:joinville2026'))
  AND NOT EXISTS (SELECT 1 FROM public.feriado_tabela_itens i WHERE i.id = public.demo_id('feriado_item:' || v.chave));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco feriado_tabela_itens nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w9$;

DO $w10$
BEGIN
INSERT INTO public.feriado_tabela_empresas (id, tenant_id, tabela_id, empresa_id)
SELECT public.demo_id('feriado_tabela_emp:joinville2026'), 'd3e00000-0000-4000-8000-000000000001',
       public.demo_id('feriado_tabela:joinville2026'), 'd3e00000-0000-4000-8000-000000000002'
WHERE EXISTS (SELECT 1 FROM public.feriado_tabelas WHERE id = public.demo_id('feriado_tabela:joinville2026'))
  AND NOT EXISTS (SELECT 1 FROM public.feriado_tabela_empresas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND empresa_id = 'd3e00000-0000-4000-8000-000000000002');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco feriado_tabela_empresas nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w10$;

-- ---------------------------------------------------------------------------
-- (6) Instrumentos: acordos (ACT/CCT/individual), CCT parametrizada, regime do
--     banco de horas e intervalo pre-assinalado do turno 6x2
--     (precisam existir ANTES das marcacoes: a apuracao os consulta)
-- ---------------------------------------------------------------------------
DO $w11$
BEGIN
INSERT INTO public.ponto_acordos (id, tenant_id, empresa_id, tipo, titulo, vigencia_inicio, vigencia_fim, documento_url, observacoes, ativo, permite_compensacao_falta, colaborador_cpf)
SELECT public.demo_id('ponto_acordo:' || v.chave), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       v.tipo, v.titulo, v.ini, v.fim, 'demo/acordos/' || v.chave || '.pdf', v.obs, v.ativo, v.compfalta, v.cpf
FROM (VALUES
  ('act2026', 'act', 'ACT 2026 - Banco de horas e compensação de faltas (Sindicato dos Metalúrgicos de Joinville)',
     DATE '2026-01-01', DATE '2026-12-31',
     'Acordo coletivo fictício para demonstração: autoriza banco de horas com compensação em até 12 meses e compensação de faltas por horas (CLT art. 462).', true, true, NULL::text),
  ('cct2526', 'cct', 'CCT 2025/2026 - Metalúrgicos de Joinville e Região',
     DATE '2025-05-01', DATE '2026-04-30',
     'Convenção coletiva anterior, substituída pela CCT 2026/2027.', false, false, NULL),
  ('cct2627', 'cct', 'CCT 2026/2027 - Metalúrgicos de Joinville e Região',
     DATE '2026-05-01', DATE '2027-04-30',
     'Convenção coletiva vigente (fictícia): jornada de 44h, adicional de hora extra de 60% e intervalo de 15 minutos no turno de 6 horas.', true, false, NULL),
  ('ind_vigente', 'individual', 'Acordo individual de banco de horas - Analista Financeiro',
     (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '5 months')::date,
     (date_trunc('month', timezone('America/Sao_Paulo', now())) + interval '1 month')::date + 8,
     'Acordo individual escrito (compensação em até 6 meses). Vence em breve: renovar.', true, false, public.demo_cpf(53)),
  ('ind_vencido', 'individual', 'Acordo individual de banco de horas - Analista da Qualidade',
     DATE '2025-09-01', DATE '2026-02-28',
     'Acordo individual semestral encerrado; não foi renovado.', false, false, public.demo_cpf(55))
) AS v(chave, tipo, titulo, ini, fim, obs, ativo, compfalta, cpf)
WHERE NOT EXISTS (SELECT 1 FROM public.ponto_acordos a WHERE a.id = public.demo_id('ponto_acordo:' || v.chave));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_acordos nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w11$;

DO $w12$
BEGIN
INSERT INTO public.ponto_cct_config (
  id, tenant_id, nome, sindicato, categoria_profissional, empresa_id, vigencia_inicio, vigencia_fim,
  jornada_semanal_horas, jornada_diaria_horas, he_percentual_dia_util, he_percentual_domingos, he_percentual_feriados,
  he_limite_diario_min, adicional_noturno_percentual, hora_noturna_inicio, hora_noturna_fim, usa_hora_ficta,
  intervalo_minimo_min, intervalo_maximo_min, banco_horas_permitido, banco_horas_prazo_compensacao_meses, dsr_proporcional,
  observacoes, ativo)
SELECT public.demo_id('ponto_cct:' || v.chave), 'd3e00000-0000-4000-8000-000000000001', v.nome,
       'Sindicato dos Metalúrgicos de Joinville e Região (fictício)', 'Metalúrgicos', 'd3e00000-0000-4000-8000-000000000002',
       v.ini, v.fim, 44, 8.8, v.he, 100, 100, 120, 25, '22:00', '05:00', true, 60, 120, true, 12, true, v.obs, v.ativo
FROM (VALUES
  ('cct2627', 'CCT Metalúrgicos 2026/2027', DATE '2026-05-01', DATE '2027-04-30', 60,
     'Parâmetros da convenção vigente: HE 60% em dia útil, 100% domingos e feriados, adicional noturno de 25%.', true),
  ('cct2526', 'CCT Metalúrgicos 2025/2026', DATE '2025-05-01', DATE '2026-04-30', 50,
     'Convenção anterior (histórico).', false)
) AS v(chave, nome, ini, fim, he, obs, ativo)
WHERE NOT EXISTS (SELECT 1 FROM public.ponto_cct_config c WHERE c.id = public.demo_id('ponto_cct:' || v.chave));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_cct_config nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w12$;

-- Regime do banco de horas: coletivo, amparado no ACT 2026
DO $w13$
BEGIN
INSERT INTO public.ponto_banco_horas_config (
  id, tenant_id, empresa_id, escala_id, tipo, prazo_compensacao_dias, permite_saldo_positivo, permite_saldo_negativo,
  limite_acumulo_horas, forma_compensacao, forma_pagamento_vencer, exige_acordo_individual, exige_cct_act,
  acordo_id, data_inicio, ativo, homologacao_rh_acima_min)
SELECT public.demo_id('ponto_bh_config:coletivo'), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002', NULL,
       'coletivo', 365, true, true, 60, 'folga', 'pagar_com_adicional', false, true,
       public.demo_id('ponto_acordo:act2026'), DATE '2026-01-01', true, 400
WHERE EXISTS (SELECT 1 FROM public.ponto_acordos WHERE id = public.demo_id('ponto_acordo:act2026'))
  AND NOT EXISTS (SELECT 1 FROM public.ponto_banco_horas_config WHERE id = public.demo_id('ponto_bh_config:coletivo'));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_banco_horas_config nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w13$;

-- Intervalo pre-assinalado (aba Configuracoes > Intervalo pre-assinalado): turno A
-- (almoco de 1 h no refeitorio, sem batida em alguns dias) e turno B (15 min)
DO $w14$
BEGIN
INSERT INTO public.ponto_pre_assinalacao (id, tenant_id, empresa_id, escala_id, intervalo_minutos, intervalo_inicio, intervalo_fim, data_inicio, lastro, observacao, ativa)
SELECT public.demo_id('ponto_pre:' || v.chave), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       public.demo_id('ponto_escala:' || v.chave), v.minutos, v.ini::time, v.fim::time, DATE '2026-01-01', v.lastro, v.obs, true
FROM (VALUES
  ('ind44', 60, '11:00', '12:00', 'CCT 2026/2027, cláusula 12ª (pré-assinalação do intervalo de refeição)',
     'Declaração formal do intervalo de 1 hora do turno A (Súmula 338, III do TST): vale nos dias em que o colaborador não bate o almoço; se bater, vale a batida.'),
  ('rev6x2a', 15, '17:00', '17:15', 'ACT 2026, cláusula 14ª (intervalo de 15 minutos em turno de 6 horas)',
     'Intervalo do turno B usufruído no refeitório; vale quando não houver batida.'),
  ('rev6x2b', 15, '17:00', '17:15', 'ACT 2026, cláusula 14ª (intervalo de 15 minutos em turno de 6 horas)',
     'Intervalo do turno B usufruído no refeitório; vale quando não houver batida.')
) AS v(chave, minutos, ini, fim, lastro, obs)
WHERE NOT EXISTS (SELECT 1 FROM public.ponto_pre_assinalacao p WHERE p.id = public.demo_id('ponto_pre:' || v.chave));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_pre_assinalacao nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w14$;

DROP FUNCTION IF EXISTS public.demo_ponto_rnd(text, integer);

-- Conferencia final (uma linha)
SELECT
  (SELECT count(*) FROM public.ponto_escalas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS escalas,
  (SELECT count(*) FROM public.ponto_escala_atribuicoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS atribuicoes,
  (SELECT count(*) FROM public.feriados WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS feriados,
  (SELECT count(*) FROM public.ponto_acordos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS acordos,
  (SELECT count(*) FROM public.ponto_banco_horas_config WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS regimes_banco,
  (SELECT count(*) FROM public.ponto_pre_assinalacao WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS pre_assinalacoes,
  CASE WHEN (SELECT count(*) FROM public.ponto_escalas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 4 AND (SELECT count(*) FROM public.ponto_escala_atribuicoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 59 THEN 'OK' ELSE 'CONFERIR' END AS situacao;