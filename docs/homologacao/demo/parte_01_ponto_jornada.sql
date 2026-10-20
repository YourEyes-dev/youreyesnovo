-- ============================================================================
-- HOMOLOGACAO — DEMONSTRACAO, PARTE 01: Ponto, Jornada e Analise de Jornada
--
-- PARA QUE SERVE
-- Da vida as telas /ponto (todas as abas), /analise-jornada e /ponto-externo
-- da "Metalurgica Exemplo Ltda" (tenant demo da parte 00), para a equipe
-- comercial demonstrar o modulo de Ponto a clientes: ~3 meses de marcacoes
-- dos colaboradores que batem ponto, escalas 44h e 6x2, horas extras, atrasos,
-- faltas, banco de horas com saldo positivo e negativo, ajustes pendentes /
-- aprovados / recusados, competencias fechadas e abertas, feriados, acordo e
-- CCT, links de ponto externo, alertas, espelhos e a analise de jornada.
--
-- ONDE COLAR
-- SQL Editor do projeto de HOMOLOGACAO, DEPOIS da parte 00
-- (docs/homologacao/demo/parte_00_base_empresa_demo.sql). O arquivo se RECUSA a
-- rodar em qualquer outro banco: so aceita se a URL gravada em app_config for a
-- da homologacao ou a do teste. Nunca na producao.
--
-- COMO OS DADOS ENTRAM (via oficial, nada calculado e gravado a mao)
--   - marcacoes: INSERT em ponto_marcacoes, os gatilhos do sistema geram o
--     hash, o NSR, a classificacao CLT, a auditoria e a apuracao diaria
--     (ponto_diario), os alertas de falta/atraso e a consolidacao semanal,
--   - faltas: consolidar_ponto_diario_manual (a mesma rotina da materializacao),
--   - ajustes: INSERT pendente + processar_ajuste_ponto (aprovar / recusar),
--     como o gestor faz na tela,
--   - banco de horas: apurar_banco_horas_colaborador (a rotina do botao Apurar)
--     + lancamentos manuais, fechamento e espelhos pelo mesmo caminho do botao
--     Fechar periodo (ponto_espelho_resumo_empresa + ponto_fechar_competencia_banco).
--   - historico: vai de 3 meses atras (dia 1) ate ONTEM/HOJE em relacao a data
--     em que o script roda. Rodar de novo perto da demonstracao completa os dias
--     novos (nada duplica), competencias ja fechadas nao sao tocadas.
--
-- GARANTIAS
--   - Nenhum dado real: nomes e CPFs da parte 00 (900.000.0XX), e-mails
--     @metalurgica-exemplo.demo, tokens de link ficticios.
--   - So toca o tenant demo (d3e00000-0000-4000-8000-000000000001).
--   - Idempotente: ids fixos (demo_id) + "so insere se nao existe".
--   - Nao cria tabela. Nao desliga gatilho.
--   - Sem tabela temporaria entre comandos. As marcacoes sao confirmadas em
--     etapas (varios COMMIT): com ~16 mil batidas, uma unica transacao ficaria
--     cada vez mais lenta. O aviso "there is no transaction in progress" que o
--     editor mostra a cada COMMIT e normal.
--   - Leva de 2 a 4 minutos (cada marcacao dispara a apuracao do dia).
--   - Altera apenas dados do proprio tenant demo: liga a cerca (geofence) da matriz,
--     carimba datas dos registros que este arquivo mesmo cria e corrige a cor
--     (classificacao CLT) da volta do almoco, que o sistema marca como interjornada.
--
-- ORDEM: se as partes de ferias, afastamentos e atestados da demonstracao forem coladas,
-- cole-as ANTES desta. O ponto respeita afastamento e ferias (o dia vira abonado), e dias
-- de competencia fechada (os 2 meses mais antigos) nao aceitam mais lancamento depois.
--
-- SE O EDITOR RECLAMAR DE TEMPO LIMITE: rode em dois pedacos. O pedaco A vai do
-- inicio ate a linha "FIM DO PEDACO A". O pedaco B comeca na linha "INICIO DO
-- PEDACO B" e vai ate o fim (ele repete a trava de ambiente). Cada pedaco e
-- idempotente. O pedaco A deixa funcoes auxiliares (demo_ponto_*) que o pedaco B
-- usa e que o pedaco B remove no final.
--
-- TELAS: /ponto (Visao geral, Espelho, Escalas, Apuracao, Ajustes, Compliance,
-- Configuracoes), /analise-jornada (8 abas) e /ponto-externo (links e tokens).
-- ============================================================================

SET lock_timeout = '10s';
SET LOCAL statement_timeout = '900s';

-- ---------------------------------------------------------------------------
-- (1) Trava de ambiente + helpers
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
    RAISE EXCEPTION 'Rode antes a parte 00 (base da empresa demo): o tenant demo nao existe.';
  END IF;
END $trava$;

-- Id deterministico por chave (igual ao da parte 00, recriado aqui por seguranca).
CREATE OR REPLACE FUNCTION public.demo_id(chave text)
RETURNS uuid
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT md5('youreyes-demo:' || chave)::uuid
$fn$;

-- Numero pseudo-aleatorio deterministico (0 .. m-1) a partir de um texto:
-- o mesmo dia/colaborador sempre gera a mesma batida, em qualquer execucao.
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

-- (fim da etapa: confirma o que ja foi feito, para a transacao nao ficar longa demais)
COMMIT;
SET LOCAL statement_timeout = '600s';

-- ---------------------------------------------------------------------------
-- (6) Gerador de marcacoes do historico (funcoes auxiliares, removidas no fim)
--     Cada marcacao entra por INSERT em ponto_marcacoes e os gatilhos do sistema
--     fazem o resto (hash, NSR, classificacao, apuracao diaria, alertas).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.demo_ponto_marca_dia(
  p_cpf text, p_colab uuid, p_nome text, p_dia date, p_horas time[], p_tipos text[], p_disp text, p_agora time)
RETURNS integer
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_n integer;
BEGIN
  -- Todas as batidas do dia entram num unico INSERT: os gatilhos de apuracao so
  -- rodam depois que o dia esta completo (sem estados intermediarios).
  INSERT INTO public.ponto_marcacoes (
    id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
    data_marcacao, hora_marcacao, tipo_marcacao, ip_origem, user_agent, latitude, longitude, dispositivo,
    hash_marcacao, marcacao_original, created_at)
  SELECT public.demo_id('marc:' || p_cpf || '|' || p_dia::text || '|' || u.ord::text),
         'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
         p_colab, p_nome, p_cpf, p_dia, u.hora, u.tipo,
         '10.20.' || (public.demo_ponto_rnd(p_cpf || p_dia::text || u.ord::text, 4) + 1) || '.' || (public.demo_ponto_rnd(p_cpf || p_dia::text || u.ord::text || 'i', 200) + 10),
         CASE WHEN p_disp = 'Mobile' THEN 'Mozilla/5.0 (Linux; Android 13) YourEyes/1.0 Mobile'
              ELSE 'Mozilla/5.0 (Windows NT 10.0; Win64) YourEyes/1.0' END,
         -26.3045 + CASE WHEN public.demo_ponto_rnd(p_cpf || p_dia::text || u.ord::text || 'fc', 100) < 2 THEN 0.006
                         ELSE (public.demo_ponto_rnd(p_cpf || p_dia::text || u.ord::text || 'la', 800) - 400) / 1000000.0 END,
         -48.8487 + (public.demo_ponto_rnd(p_cpf || p_dia::text || u.ord::text || 'lo', 800) - 400) / 1000000.0,
         p_disp, 'demo', true,
         (p_dia + u.hora) AT TIME ZONE 'America/Sao_Paulo'
  FROM unnest(p_horas, p_tipos) WITH ORDINALITY AS u(hora, tipo, ord)
  WHERE (p_dia < (timezone('America/Sao_Paulo', now()))::date OR (p_agora > time '00:10' AND u.hora <= p_agora - interval '8 minutes'))
    AND NOT EXISTS (SELECT 1 FROM public.ponto_marcacoes m WHERE m.id = public.demo_id('marc:' || p_cpf || '|' || p_dia::text || '|' || u.ord::text))
  ORDER BY u.ord;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END
$fn$;

CREATE OR REPLACE FUNCTION public.demo_ponto_gerar(p_ini date, p_fim date)
RETURNS integer
LANGUAGE plpgsql
AS $fn$
DECLARE
  c_t constant uuid := 'd3e00000-0000-4000-8000-000000000001';
  c_e constant uuid := 'd3e00000-0000-4000-8000-000000000002';
  v_hoje date := (timezone('America/Sao_Paulo', now()))::date;
  v_agora time := (timezone('America/Sao_Paulo', now()))::time;
  v_fechado_ate date := (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '1 month')::date - 1;
  r record;
  v_dia date;
  v_dow int;
  v_dk text;
  v_cfg jsonb;
  v_rev boolean;
  v_trab_dia boolean;
  v_feriado text;
  v_k text;
  v_ent time; v_sai time; v_ia time; v_fa time;
  v_ent_r time; v_sai_r time; v_ai_r time; v_af_r time;
  v_ioff int; v_soff int; v_ldur int; v_x int;
  v_heavy boolean; v_late boolean; v_saidor boolean; v_faltoso boolean; v_intcurto boolean; v_extra boolean; v_over boolean;
  v_jorn int; v_trab int; v_short int;
  v_disp text;
  v_hs time[];
  v_ts text[];
  v_i int;
  v_total int := 0;
  v_acao text;
  v_erros integer := 0;
  v_ultimo_erro text;
BEGIN
  FOR r IN
    SELECT s.n, a.id, a.nome_completo AS nome, a.cpf, a.data_admissao, a.departamento, a.cargo
    FROM generate_series(1, 59) s(n)
    JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || s.n)
    WHERE a.status = 'concluido' AND COALESCE(a.bate_ponto, true)
    ORDER BY s.n
  LOOP
    v_heavy := r.n % 6 = 0;
    v_late := r.n % 9 = 4;
    v_saidor := r.n % 8 = 3;
    v_faltoso := r.n % 13 = 5;
    v_intcurto := r.n % 11 = 3;
    v_extra := r.n % 5 = 2;
    v_over := r.n IN (29, 41, 53);
    v_disp := CASE WHEN r.departamento IN ('Administrativo', 'Recursos Humanos', 'Comercial') THEN 'Desktop' ELSE 'Mobile' END;

    FOR v_dia IN
      SELECT g::date FROM generate_series(GREATEST(p_ini, r.data_admissao), LEAST(p_fim, v_hoje), interval '1 day') g
    LOOP
      -- dia passado que ja tem apuracao: nao refaz (idempotencia e competencia fechada)
      -- (dia que ainda estava incompleto pode ter sido "hoje" numa execucao anterior: replaneja, e
      --  o que ja existe nao e regravado porque cada batida tem id fixo)
      IF v_dia < v_hoje AND EXISTS (
           SELECT 1 FROM public.ponto_diario d
           WHERE d.tenant_id = c_t AND d.colaborador_cpf = r.cpf AND d.data = v_dia AND d.status <> 'incompleto') THEN
        CONTINUE;
      END IF;

      v_dow := EXTRACT(DOW FROM v_dia)::int;
      v_dk := (ARRAY['domingo','segunda','terca','quarta','quinta','sexta','sabado'])[v_dow + 1];
      v_k := r.n::text || '|' || v_dia::text;

      v_cfg := (SELECT e.dias_config -> v_dk
                FROM public.ponto_escala_atribuicoes pa
                JOIN public.ponto_escalas e ON e.id = pa.escala_id
                WHERE pa.tenant_id = c_t AND pa.colaborador_id = r.id::text
                  AND pa.data_inicio <= v_dia AND (pa.data_fim IS NULL OR pa.data_fim >= v_dia)
                ORDER BY pa.data_inicio DESC LIMIT 1);
      v_rev := COALESCE((SELECT e.modalidade = 'revezamento'
                FROM public.ponto_escala_atribuicoes pa
                JOIN public.ponto_escalas e ON e.id = pa.escala_id
                WHERE pa.tenant_id = c_t AND pa.colaborador_id = r.id::text
                  AND pa.data_inicio <= v_dia AND (pa.data_fim IS NULL OR pa.data_fim >= v_dia)
                ORDER BY pa.data_inicio DESC LIMIT 1), false);
      IF v_cfg IS NULL THEN
        CONTINUE;  -- sem escala vigente neste dia
      END IF;
      v_trab_dia := COALESCE((v_cfg ->> 'trabalha')::boolean, false);
      v_feriado := (SELECT h.nome FROM public.feriados_da_empresa(c_t, c_e, v_dia, v_dia) h LIMIT 1);

      v_acao := 'nada';
      v_hs := ARRAY[]::time[];
      v_ts := ARRAY[]::text[];

      IF v_trab_dia THEN
        v_ent := (v_cfg ->> 'entrada')::time;
        v_sai := (v_cfg ->> 'saida')::time;
        v_ia := (v_cfg ->> 'inicio_almoco')::time;
        v_fa := (v_cfg ->> 'fim_almoco')::time;

        IF v_feriado IS NOT NULL AND r.n % 7 <> 0 THEN
          v_acao := 'neutro';
        ELSIF v_dia < v_hoje
              AND v_dia > r.data_admissao + 3
              AND public.demo_ponto_rnd(v_k || 'f', 1000) < (CASE WHEN v_faltoso THEN 55 ELSE 16 END) THEN
          v_acao := 'falta';
        ELSE
          v_acao := 'marcar';
          -- entrada
          v_x := public.demo_ponto_rnd(v_k || 'e', 1000);
          IF v_late AND v_x < 190 THEN
            v_ioff := 11 + public.demo_ponto_rnd(v_k || 'e2', 30);
          ELSIF v_x < 30 THEN
            v_ioff := 11 + public.demo_ponto_rnd(v_k || 'e2', 18);
          ELSIF v_x < 130 THEN
            v_ioff := -(6 + public.demo_ponto_rnd(v_k || 'e2', 10));
          ELSE
            v_ioff := -5 + public.demo_ponto_rnd(v_k || 'e2', 10);
          END IF;
          -- saida
          v_x := public.demo_ponto_rnd(v_k || 's', 1000);
          IF v_rev THEN
            -- 6x2: quase sem hora extra (acima de 6 h o intervalo teria de ser de 1 h)
            IF v_heavy AND v_x < 150 THEN v_soff := 15 + public.demo_ponto_rnd(v_k || 's2', 45);
            ELSIF v_saidor AND v_x < 250 THEN v_soff := -(10 + public.demo_ponto_rnd(v_k || 's2', 26));
            ELSIF v_x < 40 THEN v_soff := -(6 + public.demo_ponto_rnd(v_k || 's2', 25));
            ELSE v_soff := public.demo_ponto_rnd(v_k || 's2', 5);
            END IF;
          ELSIF v_heavy THEN
            IF v_x < 330 THEN v_soff := 30 + public.demo_ponto_rnd(v_k || 's2', 90);
            ELSIF v_x < 345 THEN v_soff := 125 + public.demo_ponto_rnd(v_k || 's2', 80);
            ELSE v_soff := public.demo_ponto_rnd(v_k || 's2', 5);
            END IF;
          ELSIF v_saidor THEN
            IF v_x < 300 THEN v_soff := -(15 + public.demo_ponto_rnd(v_k || 's2', 36));
            ELSIF v_x < 360 THEN v_soff := 10 + public.demo_ponto_rnd(v_k || 's2', 25);
            ELSE v_soff := public.demo_ponto_rnd(v_k || 's2', 5);
            END IF;
          ELSE
            IF v_x < (CASE WHEN v_extra THEN 260 ELSE 130 END) THEN v_soff := 12 + public.demo_ponto_rnd(v_k || 's2', 48);
            ELSIF v_x < (CASE WHEN v_extra THEN 290 ELSE 165 END) THEN v_soff := -(6 + public.demo_ponto_rnd(v_k || 's2', 40));
            ELSE v_soff := public.demo_ponto_rnd(v_k || 's2', 5);
            END IF;
          END IF;
          -- sobrecarga recente: tres colaboradores com jornadas muito longas nas ultimas 7 semanas
          IF v_over AND v_dia >= v_hoje - 50 AND public.demo_ponto_rnd(v_k || 'ov', 100) < 55 THEN
            v_soff := 140 + public.demo_ponto_rnd(v_k || 'ov2', 95);
            v_ioff := -public.demo_ponto_rnd(v_k || 'ov3', 8);
          END IF;
          v_ent_r := v_ent + make_interval(mins => v_ioff, secs => public.demo_ponto_rnd(v_k || 'es', 60));
          v_sai_r := v_sai + make_interval(mins => v_soff, secs => public.demo_ponto_rnd(v_k || 'ss', 60));

          -- intervalo (almoco, ou 15 min no turno B)
          v_x := public.demo_ponto_rnd(v_k || 'l', 1000);
          IF v_rev THEN v_ldur := 15 + public.demo_ponto_rnd(v_k || 'l2', 4);
          ELSIF v_intcurto AND v_x < 250 THEN v_ldur := 32 + public.demo_ponto_rnd(v_k || 'l2', 20);
          ELSIF v_x < 15 THEN v_ldur := 40 + public.demo_ponto_rnd(v_k || 'l2', 15);
          ELSIF v_x < 260 THEN v_ldur := 63 + public.demo_ponto_rnd(v_k || 'l2', 13);
          ELSE v_ldur := 60 + public.demo_ponto_rnd(v_k || 'l2', 3);
          END IF;
          v_ai_r := v_ia + make_interval(mins => public.demo_ponto_rnd(v_k || 'a', 8) - 2, secs => public.demo_ponto_rnd(v_k || 'as', 60));
          v_af_r := v_ai_r + make_interval(mins => v_ldur, secs => public.demo_ponto_rnd(v_k || 'fs', 40));
          v_hs := ARRAY[v_ent_r, v_ai_r, v_af_r, v_sai_r];
          v_ts := ARRAY['entrada', 'saida_almoco', 'retorno_almoco', 'saida'];

          -- dia curto sem motivo: nas competencias fechadas (e em 90% das demais) o
          -- gerador evita ficar 60 min ou mais abaixo da jornada (isso viraria pendencia)
          v_jorn := (EXTRACT(EPOCH FROM (v_sai - v_ent)) / 60)::int - (EXTRACT(EPOCH FROM (v_fa - v_ia)) / 60)::int;
          v_trab := ((EXTRACT(EPOCH FROM (v_ai_r - v_ent_r)) + EXTRACT(EPOCH FROM (v_sai_r - v_af_r))) / 60)::int;
          v_short := v_jorn - v_trab;
          IF v_short >= 56 AND (v_dia <= v_fechado_ate OR public.demo_ponto_rnd(v_k || 'c', 100) < 90) THEN
            v_sai_r := v_sai_r + make_interval(mins => v_short - 38 + public.demo_ponto_rnd(v_k || 'c2', 8));
            v_hs[4] := v_sai_r;
          END IF;

          -- turno A: em alguns dias o colaborador nao bate o almoco (vale o intervalo pre-assinalado)
          IF NOT v_rev AND r.departamento IN ('Produção', 'Manutenção', 'Logística')
             AND public.demo_ponto_rnd(v_k || 'p2', 100) < 12 THEN
            v_hs := ARRAY[v_ent_r, v_hs[4]];
            v_ts := ARRAY['entrada', 'saida'];
          END IF;

          -- hoje: quem costuma atrasar chega tarde e sai cedo para uma consulta (dia completo, com atraso)
          IF v_dia = v_hoje AND v_late AND NOT v_rev THEN
            v_hs := ARRAY[v_ent + make_interval(mins => 12 + public.demo_ponto_rnd(v_k || 'td', 14), secs => public.demo_ponto_rnd(v_k || 'tds', 60)),
                          '11:40'::time + make_interval(mins => public.demo_ponto_rnd(v_k || 'tf', 10), secs => public.demo_ponto_rnd(v_k || 'tfs', 60))];
            v_ts := ARRAY['entrada', 'saida'];
          END IF;

          -- esquecimento de batida de saida (vira ajuste de inclusao mais adiante)
          IF v_dia < v_hoje AND public.demo_ponto_rnd(v_k || 'x', 1000) < 6 THEN
            v_hs := v_hs[1:(array_length(v_hs, 1) - 1)];
            v_ts := v_ts[1:(array_length(v_ts, 1) - 1)];
          END IF;
        END IF;

      ELSE
        -- dia de folga na escala
        IF v_rev AND v_dow BETWEEN 1 AND 5 THEN
          v_acao := 'folga';
        ELSIF NOT v_rev AND v_feriado IS NULL THEN
          v_ent := (SELECT (e.dias_config -> 'segunda' ->> 'entrada')::time
                    FROM public.ponto_escala_atribuicoes pa JOIN public.ponto_escalas e ON e.id = pa.escala_id
                    WHERE pa.tenant_id = c_t AND pa.colaborador_id = r.id::text
                      AND pa.data_inicio <= v_dia AND (pa.data_fim IS NULL OR pa.data_fim >= v_dia)
                    ORDER BY pa.data_inicio DESC LIMIT 1);
          IF v_dow = 6 AND v_ent IS NOT NULL THEN
            -- sabado extra: forte na equipe de muita hora extra, raro nos demais
            IF public.demo_ponto_rnd(v_k || 'sab', 1000) < (CASE WHEN v_heavy THEN 300 ELSE 25 END) THEN
              v_ent_r := v_ent + make_interval(mins => public.demo_ponto_rnd(v_k || 'e2', 10) - 3, secs => public.demo_ponto_rnd(v_k || 'es', 60));
              v_sai_r := v_ent_r + make_interval(mins => 190 + public.demo_ponto_rnd(v_k || 's2', 45), secs => public.demo_ponto_rnd(v_k || 'ss', 60));
              v_hs := ARRAY[v_ent_r, v_sai_r];
              v_ts := ARRAY['entrada', 'saida'];
              v_acao := 'marcar';
            END IF;
          ELSIF v_dow = 0 AND v_ent IS NOT NULL AND r.cargo = 'Mecânico de Manutenção' THEN
            -- plantao de domingo da manutencao (hora extra 100%)
            IF public.demo_ponto_rnd(v_k || 'dom', 1000) < 50 THEN
              v_ent_r := '08:00'::time + make_interval(mins => public.demo_ponto_rnd(v_k || 'e2', 8), secs => public.demo_ponto_rnd(v_k || 'es', 60));
              v_sai_r := v_ent_r + make_interval(mins => 200 + public.demo_ponto_rnd(v_k || 's2', 35), secs => public.demo_ponto_rnd(v_k || 'ss', 60));
              v_hs := ARRAY[v_ent_r, v_sai_r];
              v_ts := ARRAY['entrada', 'saida'];
              v_acao := 'marcar';
            END IF;
          END IF;
        END IF;
      END IF;

      IF v_acao = 'marcar' THEN
        -- hoje: so entra o que ja "aconteceu" (o sistema recusa marcacao no futuro)
        BEGIN
          v_total := v_total + public.demo_ponto_marca_dia(r.cpf, r.id, r.nome, v_dia, v_hs, v_ts, v_disp, v_agora);
        EXCEPTION WHEN OTHERS THEN
          -- dia que o sistema recusa (ex.: colaborador afastado): fica sem batida, e a
          -- apuracao do dia segue a regra do afastamento
          v_erros := v_erros + 1;
          v_ultimo_erro := SQLERRM;
          BEGIN
            PERFORM public.consolidar_ponto_diario_manual(c_t, r.cpf, v_dia);
          EXCEPTION WHEN OTHERS THEN
            NULL;
          END;
        END;
      ELSIF v_acao IN ('falta', 'neutro', 'folga') THEN
        BEGIN
          IF v_acao = 'falta' THEN
            PERFORM public.consolidar_ponto_diario_manual(c_t, r.cpf, v_dia);
          ELSIF v_acao = 'neutro' THEN
            PERFORM public.ponto_grava_feriado_neutro(c_t, c_e, r.id, r.nome, r.cpf, v_dia, v_feriado);
          ELSE
            PERFORM public._ponto_grava_abono(c_t, r.id, r.nome, r.cpf, v_dia, 'Folga de escala 6x2 (rodízio do turno B)');
          END IF;
          v_total := v_total + 1;
        EXCEPTION WHEN OTHERS THEN
          v_erros := v_erros + 1;
          v_ultimo_erro := SQLERRM;
        END;
      END IF;
    END LOOP;
  END LOOP;
  IF v_erros > 0 THEN
    RAISE NOTICE '% dia(s) nao gravados pelo gerador (ultimo motivo: %)', v_erros, v_ultimo_erro;
  END IF;
  RETURN v_total;
END
$fn$;

-- (fim da etapa: confirma o que ja foi feito, para a transacao nao ficar longa demais)
COMMIT;
SET LOCAL statement_timeout = '600s';

-- ---------------------------------------------------------------------------
-- (7) Historico de marcacoes: um comando por semana (cada marcacao dispara a apuracao
--     do dia pelos gatilhos, e comandos curtos evitam estouro de tempo no editor).
--     Semanas depois de hoje nao fazem nada.
-- ---------------------------------------------------------------------------
DO $g1$
BEGIN
  PERFORM public.demo_ponto_gerar(
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 0,
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 6);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Marcacoes da semana 1 nao concluidas: % (%)', SQLERRM, SQLSTATE;
END $g1$;

DO $g2$
BEGIN
  PERFORM public.demo_ponto_gerar(
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 7,
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 13);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Marcacoes da semana 2 nao concluidas: % (%)', SQLERRM, SQLSTATE;
END $g2$;

DO $g3$
BEGIN
  PERFORM public.demo_ponto_gerar(
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 14,
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 20);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Marcacoes da semana 3 nao concluidas: % (%)', SQLERRM, SQLSTATE;
END $g3$;


-- (fim da etapa: confirma o que ja foi feito, para a transacao nao ficar longa demais)
COMMIT;
SET LOCAL statement_timeout = '600s';
DO $g4$
BEGIN
  PERFORM public.demo_ponto_gerar(
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 21,
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 27);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Marcacoes da semana 4 nao concluidas: % (%)', SQLERRM, SQLSTATE;
END $g4$;

DO $g5$
BEGIN
  PERFORM public.demo_ponto_gerar(
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 28,
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 34);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Marcacoes da semana 5 nao concluidas: % (%)', SQLERRM, SQLSTATE;
END $g5$;

DO $g6$
BEGIN
  PERFORM public.demo_ponto_gerar(
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 35,
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 41);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Marcacoes da semana 6 nao concluidas: % (%)', SQLERRM, SQLSTATE;
END $g6$;


-- (fim da etapa: confirma o que ja foi feito, para a transacao nao ficar longa demais)
COMMIT;
SET LOCAL statement_timeout = '600s';
DO $g7$
BEGIN
  PERFORM public.demo_ponto_gerar(
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 42,
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 48);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Marcacoes da semana 7 nao concluidas: % (%)', SQLERRM, SQLSTATE;
END $g7$;

DO $g8$
BEGIN
  PERFORM public.demo_ponto_gerar(
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 49,
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 55);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Marcacoes da semana 8 nao concluidas: % (%)', SQLERRM, SQLSTATE;
END $g8$;

DO $g9$
BEGIN
  PERFORM public.demo_ponto_gerar(
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 56,
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 62);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Marcacoes da semana 9 nao concluidas: % (%)', SQLERRM, SQLSTATE;
END $g9$;


-- (fim da etapa: confirma o que ja foi feito, para a transacao nao ficar longa demais)
COMMIT;
SET LOCAL statement_timeout = '600s';
DO $g10$
BEGIN
  PERFORM public.demo_ponto_gerar(
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 63,
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 69);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Marcacoes da semana 10 nao concluidas: % (%)', SQLERRM, SQLSTATE;
END $g10$;

DO $g11$
BEGIN
  PERFORM public.demo_ponto_gerar(
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 70,
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 76);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Marcacoes da semana 11 nao concluidas: % (%)', SQLERRM, SQLSTATE;
END $g11$;

DO $g12$
BEGIN
  PERFORM public.demo_ponto_gerar(
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 77,
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 83);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Marcacoes da semana 12 nao concluidas: % (%)', SQLERRM, SQLSTATE;
END $g12$;


-- (fim da etapa: confirma o que ja foi feito, para a transacao nao ficar longa demais)
COMMIT;
SET LOCAL statement_timeout = '600s';
DO $g13$
BEGIN
  PERFORM public.demo_ponto_gerar(
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 84,
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 90);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Marcacoes da semana 13 nao concluidas: % (%)', SQLERRM, SQLSTATE;
END $g13$;

DO $g14$
BEGIN
  PERFORM public.demo_ponto_gerar(
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 91,
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 97);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Marcacoes da semana 14 nao concluidas: % (%)', SQLERRM, SQLSTATE;
END $g14$;

DO $g15$
BEGIN
  PERFORM public.demo_ponto_gerar(
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 98,
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 104);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Marcacoes da semana 15 nao concluidas: % (%)', SQLERRM, SQLSTATE;
END $g15$;


-- (fim da etapa: confirma o que ja foi feito, para a transacao nao ficar longa demais)
COMMIT;
SET LOCAL statement_timeout = '600s';
DO $g16$
BEGIN
  PERFORM public.demo_ponto_gerar(
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 105,
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 111);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Marcacoes da semana 16 nao concluidas: % (%)', SQLERRM, SQLSTATE;
END $g16$;

DO $g17$
BEGIN
  PERFORM public.demo_ponto_gerar(
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 112,
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 118);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Marcacoes da semana 17 nao concluidas: % (%)', SQLERRM, SQLSTATE;
END $g17$;

DO $g18$
BEGIN
  PERFORM public.demo_ponto_gerar(
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 119,
    (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months')::date + 125);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Marcacoes da semana 18 nao concluidas: % (%)', SQLERRM, SQLSTATE;
END $g18$;

-- ---------------------------------------------------------------------------
-- FIM DO PEDACO A
-- ---------------------------------------------------------------------------

-- (fim da etapa: confirma o que ja foi feito, para a transacao nao ficar longa demais)
COMMIT;
SET LOCAL statement_timeout = '600s';

-- ---------------------------------------------------------------------------
-- INICIO DO PEDACO B (se rodar separado, rode a partir daqui)
-- ---------------------------------------------------------------------------
SET lock_timeout = '10s';
SET LOCAL statement_timeout = '900s';

DO $trava2$
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
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'demo_ponto_rnd' AND pronamespace = 'public'::regnamespace) THEN
    RAISE EXCEPTION 'Rode antes o pedaco A deste arquivo (ele cria as funcoes auxiliares demo_ponto_*).';
  END IF;
END $trava2$;

-- Ajuste de cor dos registros: a classificacao CLT automatica trata a volta do almoco
-- como "nova entrada" e a marca de vermelho (interjornada) por causa da saida do almoco do
-- MESMO dia. Aqui so se corrige essa leitura nos registros desta demonstracao, mantendo o
-- vermelho de verdade (menos de 11 h desde a saida do dia anterior).
DO $w15$
BEGIN
UPDATE public.ponto_marcacoes m
   SET classificacao_clt = 'verde'
 WHERE m.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
   AND m.classificacao_clt = 'vermelho'
   AND m.tipo_marcacao = 'entrada'
   AND EXISTS (SELECT 1 FROM public.ponto_marcacoes p
               WHERE p.tenant_id = m.tenant_id AND p.colaborador_cpf = m.colaborador_cpf
                 AND p.data_marcacao = m.data_marcacao AND p.tipo_marcacao = 'saida'
                 AND p.hora_marcacao < m.hora_marcacao);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_marcacoes nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w15$;

-- ---------------------------------------------------------------------------
-- (8) Solicitacoes de ajuste de ponto: nascem dos proprios dias do historico
--     (batida de saida esquecida, atraso contestado, falta justificada).
--     Entram PENDENTES e os mais antigos sao aprovados/recusados pela rotina
--     oficial processar_ajuste_ponto, como o gestor faz na tela.
-- ---------------------------------------------------------------------------
-- Regra de decisao (deterministica): competencias fechadas -> tudo resolvido,
-- mes anterior -> metade resolvida, mes corrente -> quase tudo pendente.
CREATE OR REPLACE FUNCTION public.demo_ponto_decisao(p_id uuid, p_tipo text, p_data date)
RETURNS text
LANGUAGE sql
STABLE
AS $fn$
  SELECT CASE
    WHEN p_tipo = 'inclusao' THEN
      CASE
        WHEN p_data <= (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '1 month')::date - 1 THEN 'aprovado'
        WHEN p_data < date_trunc('month', timezone('America/Sao_Paulo', now()))::date
          THEN CASE WHEN public.demo_ponto_rnd(p_id::text || 'dec', 100) < 55 THEN 'aprovado' ELSE 'pendente' END
        WHEN p_data < (timezone('America/Sao_Paulo', now()))::date - 12
          THEN CASE WHEN public.demo_ponto_rnd(p_id::text || 'dec', 100) < 25 THEN 'aprovado' ELSE 'pendente' END
        ELSE 'pendente'
      END
    ELSE
      CASE
        WHEN p_data <= (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '1 month')::date - 1
          THEN CASE WHEN public.demo_ponto_rnd(p_id::text || 'dec', 100) < 84 THEN 'aprovado' ELSE 'rejeitado' END
        WHEN p_data < date_trunc('month', timezone('America/Sao_Paulo', now()))::date
          THEN CASE WHEN public.demo_ponto_rnd(p_id::text || 'dec', 100) < 40 THEN 'aprovado'
                    WHEN public.demo_ponto_rnd(p_id::text || 'dec', 100) < 55 THEN 'rejeitado' ELSE 'pendente' END
        WHEN p_data < (timezone('America/Sao_Paulo', now()))::date - 5
          THEN CASE WHEN public.demo_ponto_rnd(p_id::text || 'dec', 100) < 20 THEN 'aprovado'
                    WHEN public.demo_ponto_rnd(p_id::text || 'dec', 100) < 26 THEN 'rejeitado' ELSE 'pendente' END
        ELSE 'pendente'
      END
  END
$fn$;

DO $w16$
BEGIN
INSERT INTO public.ponto_ajustes (
  id, tenant_id, empresa_id, ponto_diario_id, colaborador_id, colaborador_nome, colaborador_cpf, data_referencia,
  tipo_ajuste, tipo_marcacao, hora_original, hora_solicitada, motivo, status, created_at, created_by_nome,
  justificativa_id, anexos, dia_inteiro, abonar_se_aprovado)
SELECT public.demo_id('ponto_ajuste:' || x.colaborador_cpf || '|' || x.data::text),
       x.tenant_id, x.empresa_id, x.id, x.colaborador_id, x.colaborador_nome, x.colaborador_cpf, x.data,
       x.tipo_ajuste, x.tipo_marcacao, x.hora_original, x.hora_solicitada, x.motivo, 'pendente',
       LEAST(now() - interval '3 hours', ((x.data + 1)::timestamp + time '08:10') AT TIME ZONE 'America/Sao_Paulo'),
       x.colaborador_nome,
       x.justificativa_id, x.anexos, x.dia_inteiro, x.abonar
FROM (
  SELECT d.*,
         CASE WHEN d.status = 'incompleto' THEN 'inclusao'
              WHEN d.status = 'atraso' THEN 'correcao'
              ELSE 'justificativa' END AS tipo_ajuste,
         CASE WHEN d.status = 'incompleto' THEN 'saida' WHEN d.status = 'atraso' THEN 'entrada' END AS tipo_marcacao,
         CASE WHEN d.status = 'atraso' THEN d.entrada END AS hora_original,
         CASE WHEN d.status = 'incompleto'
                THEN (esc.cfg ->> 'saida')::time + make_interval(mins => public.demo_ponto_rnd(d.id::text || 'hs', 9))
              WHEN d.status = 'atraso'
                THEN (esc.cfg ->> 'entrada')::time + make_interval(mins => public.demo_ponto_rnd(d.id::text || 'hs', 4))
         END AS hora_solicitada,
         CASE
           WHEN d.status = 'incompleto' THEN
             (ARRAY['Esqueci de registrar a saída ao final do expediente.',
                    'Celular sem bateria na hora de sair; saí no horário normal.',
                    'Saí às pressas por urgência familiar e não bati a saída.',
                    'O aplicativo não carregou na saída; informo o horário correto.'])[1 + public.demo_ponto_rnd(d.id::text || 'mt', 4)]
           WHEN d.status = 'atraso' THEN
             (ARRAY['Cheguei no horário, mas a fila na portaria atrasou o registro.',
                    'Trânsito interditado na BR-101; avisei o líder por mensagem.',
                    'Registrei a entrada após guardar meus pertences; já estava no posto às 08:00.'])[1 + public.demo_ponto_rnd(d.id::text || 'mt', 3)]
           ELSE
             (ARRAY['Atestado médico apresentado ao RH (consulta de urgência).',
                    'Consulta com especialista agendada pelo plano de saúde; comprovante anexo.',
                    'Acompanhamento de filho menor em consulta pediátrica; declaração anexa.'])[1 + public.demo_ponto_rnd(d.id::text || 'mt', 3)]
         END AS motivo,
         CASE WHEN d.status = 'falta'
              THEN (SELECT j.id FROM public.ponto_justificativas j
                    WHERE j.tenant_id = d.tenant_id AND j.empresa_id IS NULL
                      AND j.codigo = CASE WHEN public.demo_ponto_rnd(d.id::text || 'jt', 100) < 60
                                          THEN 'FALTA_JUSTIFICADA_ABONADA' ELSE 'CONSULTA_MEDICA' END
                    LIMIT 1)
         END AS justificativa_id,
         CASE WHEN d.status = 'falta'
              THEN jsonb_build_array(jsonb_build_object(
                     'nome', 'comprovante-' || to_char(d.data, 'YYYYMMDD') || '.pdf',
                     'url', 'demo/anexos/ponto/comprovante-' || to_char(d.data, 'YYYYMMDD') || '.pdf',
                     'tamanho', 184320, 'tipo', 'application/pdf'))
              ELSE '[]'::jsonb END AS anexos,
         (d.status = 'falta') AS dia_inteiro,
         (d.status = 'falta') AS abonar
  FROM public.ponto_diario d
  LEFT JOIN LATERAL (
    SELECT e.dias_config -> (ARRAY['domingo','segunda','terca','quarta','quinta','sexta','sabado'])[EXTRACT(DOW FROM d.data)::int + 1] AS cfg
    FROM public.ponto_escala_atribuicoes pa
    JOIN public.ponto_escalas e ON e.id = pa.escala_id
    WHERE pa.tenant_id = d.tenant_id AND pa.colaborador_id = d.colaborador_id::text
      AND pa.data_inicio <= d.data AND (pa.data_fim IS NULL OR pa.data_fim >= d.data)
    ORDER BY pa.data_inicio DESC LIMIT 1
  ) esc ON true
  WHERE d.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
    AND d.data < (timezone('America/Sao_Paulo', now()))::date
    AND (
      d.status = 'incompleto'
      OR (d.status = 'atraso' AND public.demo_ponto_rnd(d.id::text || 'cor', 100) < 20)
      OR (d.status = 'falta' AND d.data < (timezone('America/Sao_Paulo', now()))::date - 1
          AND public.demo_ponto_rnd(d.id::text || 'jus', 100) < 30)
    )
) x
WHERE (x.status <> 'falta' OR x.justificativa_id IS NOT NULL)
  AND (x.status NOT IN ('incompleto', 'atraso') OR x.hora_solicitada IS NOT NULL)
  AND NOT EXISTS (SELECT 1 FROM public.ponto_ajustes a WHERE a.id = public.demo_id('ponto_ajuste:' || x.colaborador_cpf || '|' || x.data::text));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_ajustes nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w16$;

-- Decisao do gestor: a mesma rotina da tela (aprovar / recusar), com o login da demo.
DO $ajuste$
DECLARE
  v_uid uuid;
  r record;
  v_dec text;
BEGIN
  v_uid := (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' ORDER BY u.created_at LIMIT 1);
  IF v_uid IS NULL THEN
    RAISE NOTICE 'Login leirinuernberg@gmail.com nao existe neste ambiente: os ajustes ficam todos pendentes.';
    RETURN;
  END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);

  FOR r IN
    SELECT a.id, a.tipo_ajuste, a.data_referencia
    FROM public.ponto_ajustes a
    WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
      AND a.status = 'pendente'
      AND a.id = public.demo_id('ponto_ajuste:' || a.colaborador_cpf || '|' || a.data_referencia::text)
    ORDER BY a.data_referencia, a.id
  LOOP
    v_dec := public.demo_ponto_decisao(r.id, r.tipo_ajuste, r.data_referencia);
    IF v_dec = 'pendente' THEN
      CONTINUE;
    END IF;
    BEGIN
      PERFORM public.processar_ajuste_ponto(
        r.id, v_dec = 'aprovado',
        CASE WHEN v_dec = 'aprovado'
             THEN (ARRAY['Conferido com o gestor imediato e com o registro de portaria.',
                         'Aprovado conforme documento apresentado ao RH.',
                         'Horário confirmado pelo líder do setor.'])[1 + public.demo_ponto_rnd(r.id::text || 'ob', 3)]
             ELSE (ARRAY['Sem comprovação do horário informado. Procure o RH com o documento.',
                         'Divergência com o registro da portaria; solicitação não acatada.'])[1 + public.demo_ponto_rnd(r.id::text || 'ob', 2)]
        END);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Ajuste % nao processado: % (%)', r.id, SQLERRM, SQLSTATE;
    END;
  END LOOP;

  PERFORM set_config('request.jwt.claims', '', true);
END $ajuste$;

-- Datas de aprovacao coerentes com a data do pedido (a rotina carimba "agora").
DO $w17$
BEGIN
UPDATE public.ponto_ajustes a
   SET data_aprovacao = LEAST(now() - interval '1 hour',
         a.created_at + interval '1 day' + make_interval(mins => public.demo_ponto_rnd(a.id::text || 'da', 360)))
 WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
   AND a.data_aprovacao IS NOT NULL
   AND a.id = public.demo_id('ponto_ajuste:' || a.colaborador_cpf || '|' || a.data_referencia::text);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_ajustes nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w17$;

-- (fim da etapa: confirma o que ja foi feito, para a transacao nao ficar longa demais)
COMMIT;
SET LOCAL statement_timeout = '600s';

-- ---------------------------------------------------------------------------
-- (9) Banco de horas e fechamento de competencias
--     Para cada mes, do mais antigo ao atual: saldo de implantacao (so no 1o mes),
--     apuracao oficial, lancamentos manuais (folga compensada, credito, debito) e
--     reapuracao, os meses mais antigos (ate 2 meses atras) sao FECHADOS pelo mesmo
--     caminho do botao "Fechar periodo": fechamento + espelhos + regra RN29.
--     Competencias ja fechadas numa execucao anterior nao sao tocadas.
-- ---------------------------------------------------------------------------
DO $banco$
DECLARE
  c_t constant uuid := 'd3e00000-0000-4000-8000-000000000001';
  c_e constant uuid := 'd3e00000-0000-4000-8000-000000000002';
  v_hoje date := (timezone('America/Sao_Paulo', now()))::date;
  v_uid uuid;
  v_comp text;
  v_ini date;
  v_fim date;
  v_primeira text := to_char(date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months', 'YYYY-MM');
  v_ate_fechar text := to_char(date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '2 months', 'YYYY-MM');
  v_cpf text;
  v_n int;
  v_fech uuid;
  v_dias_fech date;
  rr record;
BEGIN
  v_uid := (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' ORDER BY u.created_at LIMIT 1);

  FOR v_comp IN
    SELECT to_char(m, 'YYYY-MM')
    FROM generate_series(date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months',
                         date_trunc('month', timezone('America/Sao_Paulo', now())), interval '1 month') m
    ORDER BY 1
  LOOP
    v_ini := to_date(v_comp || '-01', 'YYYY-MM-DD');
    v_fim := (v_ini + interval '1 month - 1 day')::date;

    -- competencia ja fechada: nada a refazer
    IF EXISTS (SELECT 1 FROM public.ponto_fechamentos f
               WHERE f.tenant_id = c_t AND f.empresa_id = c_e AND f.competencia = v_comp AND f.status = 'fechado') THEN
      CONTINUE;
    END IF;

    BEGIN
      -- (a) saldo de implantacao no primeiro mes: horas que vieram do controle anterior
      IF v_comp = v_primeira THEN
        INSERT INTO public.ponto_banco_horas (id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, tipo, competencia, saldo_anterior_minutos, observacoes)
        SELECT public.demo_id('bh:' || a.cpf || '|' || v_comp), c_t, c_e, a.id::text, a.nome_completo, a.cpf, 'mensal', v_comp,
               (ARRAY[300, -150, 480, 0, 120, -240, 0, 600, 0, -60, 90, 180])[1 + public.demo_ponto_rnd(a.cpf, 12)],
               'Saldo de implantação (controle anterior à adoção do sistema).'
        FROM generate_series(1, 59) s(n)
        JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || s.n)
        WHERE a.status = 'concluido' AND s.n % 3 = 1 AND a.data_admissao < v_ini
          AND NOT EXISTS (SELECT 1 FROM public.ponto_banco_horas b
                          WHERE b.tenant_id = c_t AND b.colaborador_cpf = a.cpf AND b.competencia = v_comp);
      END IF;

      -- (b) apuracao oficial de todos que tem dia apurado no mes
      FOR v_cpf IN
        SELECT DISTINCT d.colaborador_cpf FROM public.ponto_diario d
        WHERE d.tenant_id = c_t AND d.data BETWEEN v_ini AND v_fim AND d.colaborador_cpf IS NOT NULL
      LOOP
        PERFORM public.apurar_banco_horas_colaborador(c_t, v_cpf, v_comp, c_e);
      END LOOP;

      -- (c) lancamentos manuais (a tela "Movimentar")
      -- folga compensada: quem acumulou saldo positivo tira folga no meio do mes
      INSERT INTO public.ponto_banco_horas_movimentacoes (id, tenant_id, banco_horas_id, colaborador_cpf, data_referencia, tipo, minutos, descricao, created_by, origem, created_at)
      SELECT public.demo_id('bh_mov:comp:' || b.colaborador_cpf || '|' || v_comp), c_t, b.id, b.colaborador_cpf,
             LEAST(v_hoje, v_ini + 14 + public.demo_ponto_rnd(b.colaborador_cpf || v_comp, 8)), 'compensacao',
             CASE WHEN b.saldo_anterior_minutos + b.creditos_minutos - b.debitos_minutos - b.compensados_minutos >= 700 THEN 480 ELSE 240 END,
             'Folga compensada autorizada pelo gestor (banco de horas).', v_uid::text, 'manual',
             LEAST(now(), (v_ini + 10)::timestamp AT TIME ZONE 'America/Sao_Paulo')
      FROM public.ponto_banco_horas b
      WHERE b.tenant_id = c_t AND b.competencia = v_comp AND v_comp > v_primeira
        AND b.saldo_anterior_minutos + b.creditos_minutos - b.debitos_minutos - b.compensados_minutos >= 360
        AND v_ini + 14 <= v_hoje
        AND NOT EXISTS (SELECT 1 FROM public.ponto_banco_horas_movimentacoes m WHERE m.id = public.demo_id('bh_mov:comp:' || b.colaborador_cpf || '|' || v_comp));

      -- credito manual: horas de inventario / evento autorizadas fora do ponto
      INSERT INTO public.ponto_banco_horas_movimentacoes (id, tenant_id, banco_horas_id, colaborador_cpf, data_referencia, tipo, minutos, descricao, created_by, origem, created_at)
      SELECT public.demo_id('bh_mov:cred:' || b.colaborador_cpf || '|' || v_comp), c_t, b.id, b.colaborador_cpf,
             LEAST(v_hoje, v_ini + 19), 'credito', 180,
             'Inventário geral do almoxarifado (horas autorizadas e registradas pelo gestor).', v_uid::text, 'manual',
             LEAST(now(), (v_ini + 20)::timestamp AT TIME ZONE 'America/Sao_Paulo')
      FROM public.ponto_banco_horas b
      WHERE b.tenant_id = c_t AND b.competencia = v_comp
        AND b.colaborador_cpf IN (SELECT a2.cpf FROM generate_series(1, 59) s2(n)
                                  JOIN public.admissoes a2 ON a2.id = public.demo_id('admissao:' || s2.n)
                                  WHERE s2.n IN (42, 44, 47, 49) AND v_comp = to_char(date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '1 month', 'YYYY-MM'))
        AND v_ini + 19 <= v_hoje
        AND NOT EXISTS (SELECT 1 FROM public.ponto_banco_horas_movimentacoes m WHERE m.id = public.demo_id('bh_mov:cred:' || b.colaborador_cpf || '|' || v_comp));

      -- debito manual: saida antecipada autorizada para compensar no banco
      INSERT INTO public.ponto_banco_horas_movimentacoes (id, tenant_id, banco_horas_id, colaborador_cpf, data_referencia, tipo, minutos, descricao, created_by, origem, created_at)
      SELECT public.demo_id('bh_mov:deb:' || b.colaborador_cpf || '|' || v_comp), c_t, b.id, b.colaborador_cpf,
             LEAST(v_hoje, v_ini + 8), 'debito', (ARRAY[120, 150, 180])[1 + public.demo_ponto_rnd(b.colaborador_cpf || v_comp, 3)],
             'Saída antecipada autorizada (compromisso pessoal) a compensar no banco de horas.', v_uid::text, 'manual',
             LEAST(now(), (v_ini + 9)::timestamp AT TIME ZONE 'America/Sao_Paulo')
      FROM public.ponto_banco_horas b
      WHERE b.tenant_id = c_t AND b.competencia = v_comp
        AND b.colaborador_cpf IN (SELECT a2.cpf FROM generate_series(1, 59) s2(n)
                                  JOIN public.admissoes a2 ON a2.id = public.demo_id('admissao:' || s2.n)
                                  WHERE s2.n IN (3, 19, 35) AND v_comp = to_char(date_trunc('month', timezone('America/Sao_Paulo', now())), 'YYYY-MM'))
        AND v_ini + 8 <= v_hoje
        AND NOT EXISTS (SELECT 1 FROM public.ponto_banco_horas_movimentacoes m WHERE m.id = public.demo_id('bh_mov:deb:' || b.colaborador_cpf || '|' || v_comp));

      -- (d) reapura para os totais do banco refletirem os lancamentos manuais
      FOR v_cpf IN
        SELECT DISTINCT d.colaborador_cpf FROM public.ponto_diario d
        WHERE d.tenant_id = c_t AND d.data BETWEEN v_ini AND v_fim AND d.colaborador_cpf IS NOT NULL
      LOOP
        PERFORM public.apurar_banco_horas_colaborador(c_t, v_cpf, v_comp, c_e);
      END LOOP;

      -- (e) fechamento das competencias antigas (mesmo caminho do botao Fechar periodo)
      IF v_comp <= v_ate_fechar
         AND EXISTS (SELECT 1 FROM public.ponto_diario d WHERE d.tenant_id = c_t AND d.data BETWEEN v_ini AND v_fim) THEN
        -- o portao do fechamento: se houver pendencia critica, nao fecha (avisa)
        BEGIN
          PERFORM public.ponto_fechar_competencia_verificar(c_t, c_e, v_comp);
        EXCEPTION WHEN OTHERS THEN
          RAISE NOTICE 'Competencia % NAO fechada: %', v_comp, SQLERRM;
          CONTINUE;
        END;

        -- 5o dia util aproximado do mes seguinte
        v_dias_fech := v_fim + 6;

        INSERT INTO public.ponto_fechamentos (
          id, tenant_id, empresa_id, competencia, data_fechamento, status, fechado_por, fechado_por_nome,
          total_colaboradores, total_horas_normais_minutos, total_horas_extras_minutos, total_adicional_noturno_minutos,
          total_faltas, total_atrasos, observacoes, created_at)
        SELECT public.demo_id('ponto_fech:' || v_comp), c_t, c_e, v_comp,
               (v_dias_fech::timestamp + time '10:30') AT TIME ZONE 'America/Sao_Paulo', 'fechado',
               v_uid::text, 'Leiri',
               count(*), COALESCE(sum(r.total_trabalhado_min), 0), COALESCE(sum(r.total_creditos_min), 0), 0,
               COALESCE(sum(r.total_faltas), 0),
               (SELECT count(*) FROM public.ponto_diario d
                 WHERE d.tenant_id = c_t AND d.data BETWEEN v_ini AND v_fim AND d.status = 'atraso'),
               'Fechamento da competência conferido pelo RH e enviado à folha.',
               (v_dias_fech::timestamp + time '10:30') AT TIME ZONE 'America/Sao_Paulo'
        FROM public.ponto_espelho_resumo_empresa(c_t, c_e, v_comp) r
        ON CONFLICT (tenant_id, empresa_id, competencia) DO NOTHING;

        v_fech := (SELECT f.id FROM public.ponto_fechamentos f WHERE f.tenant_id = c_t AND f.empresa_id = c_e AND f.competencia = v_comp);

        INSERT INTO public.ponto_espelhos (
          id, tenant_id, empresa_id, fechamento_id, colaborador_id, colaborador_nome, colaborador_cpf, competencia,
          total_horas_normais_minutos, total_trabalhado_minutos, total_jornada_prevista_minutos,
          total_creditos_minutos, total_debitos_minutos, total_horas_extras_50_minutos, total_horas_extras_100_minutos,
          total_atrasos_minutos, banco_horas_saldo_minutos, total_faltas, total_dias_trabalhados, total_dias_protegidos,
          total_excedente_retido_minutos, dia_equalizacao, status, created_at)
        SELECT public.demo_id('ponto_espelho:' || r.colaborador_cpf || '|' || v_comp), c_t, c_e, v_fech,
               r.colaborador_id::text, r.colaborador_nome, r.colaborador_cpf, v_comp,
               COALESCE(r.total_trabalhado_min, 0), COALESCE(r.total_trabalhado_min, 0), COALESCE(r.total_jornada_prevista_min, 0),
               COALESCE(r.total_creditos_min, 0), COALESCE(r.total_debitos_min, 0), COALESCE(r.he_50_min, 0), COALESCE(r.he_100_min, 0),
               COALESCE(r.atrasos_min, 0), COALESCE(r.saldo_banco_min, r.saldo_min, 0), COALESCE(r.total_faltas, 0),
               COALESCE(r.dias_trabalhados, 0), COALESCE(r.dias_protegidos, 0),
               COALESCE(r.excedente_retido_min, 0), r.dia_equalizacao, 'gerado',
               (v_dias_fech::timestamp + time '10:31') AT TIME ZONE 'America/Sao_Paulo'
        FROM public.ponto_espelho_resumo_empresa(c_t, c_e, v_comp) r
        WHERE NOT EXISTS (SELECT 1 FROM public.ponto_espelhos e
                          WHERE e.tenant_id = c_t AND e.colaborador_cpf = r.colaborador_cpf AND e.competencia = v_comp);

        -- regra RN29: so o saldo negativo transita para o mes seguinte
        PERFORM public.ponto_fechar_competencia_banco(c_t, c_e, v_comp);

        -- ciencia dos colaboradores (a maioria confirmou, alguns com ressalva)
        UPDATE public.ponto_espelhos e
           SET status = CASE WHEN public.demo_ponto_rnd(e.colaborador_cpf || v_comp || 'sc', 100) < 6 THEN 'ressalva' ELSE 'confirmado' END,
               ressalva_texto = CASE WHEN public.demo_ponto_rnd(e.colaborador_cpf || v_comp || 'sc', 100) < 6
                                     THEN 'Discordo de uma das faltas do mês: estava em consulta e o atestado foi entregue ao RH.' END,
               data_confirmacao = ((v_dias_fech - 2)::timestamp + time '09:00' + make_interval(mins => public.demo_ponto_rnd(e.colaborador_cpf || v_comp || 'dc', 480)))
                                  AT TIME ZONE 'America/Sao_Paulo',
               confirmado_por = e.colaborador_nome,
               assinatura_hash = md5('demo-espelho|' || e.colaborador_cpf || '|' || v_comp)
         WHERE e.tenant_id = c_t AND e.competencia = v_comp AND e.status = 'gerado'
           AND e.id = public.demo_id('ponto_espelho:' || e.colaborador_cpf || '|' || v_comp);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Banco/fechamento da competencia % nao concluido: % (%)', v_comp, SQLERRM, SQLSTATE;
    END;
  END LOOP;
END $banco$;

-- (fim da etapa: confirma o que ja foi feito, para a transacao nao ficar longa demais)
COMMIT;
SET LOCAL statement_timeout = '600s';

-- ---------------------------------------------------------------------------
-- (11) Fluxos de gestao pela via oficial: troca de turno, compensacao de falta,
--      excedente de hora extra retido, excecoes de feriado e folgas compensatorias
-- ---------------------------------------------------------------------------
DO $fluxos$
DECLARE
  c_t constant uuid := 'd3e00000-0000-4000-8000-000000000001';
  c_e constant uuid := 'd3e00000-0000-4000-8000-000000000002';
  v_hoje date := (timezone('America/Sao_Paulo', now()))::date;
  v_uid uuid;
  v_id uuid;
  v_res jsonb;
  v_status text;
  r record;
BEGIN
  v_uid := (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' ORDER BY u.created_at LIMIT 1);
  IF v_uid IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  END IF;

  -- ---- Troca de turno (aba Escalas > Troca de turno) ----
  FOR r IN
    SELECT * FROM (VALUES
      (1, 22, 23, 5, NULL::int, 'solicitada', 'Consulta médica de acompanhamento; combinei a troca com o colega do turno A.', NULL::text),
      (2, 1, 2, 4, 6, 'aprovada', 'Troca temporária por uma semana para curso de capacitação em horário de turno.', NULL),
      (3, 9, 10, 2, 7, 'efetivada', 'Troca de semana entre soldadores para acompanhar a manutenção programada da linha 2.', NULL),
      (4, 11, 12, 3, NULL, 'recusada', 'Preciso trocar de turno para resolver assunto pessoal.', 'Sem cobertura no turno B nesta semana; reapresentar após o fechamento da produção.'),
      (5, 25, 26, 6, NULL, 'cancelada', 'Troca solicitada e depois desnecessária.', NULL)
    ) AS t(k, na, nb, d_ini, d_dur, alvo, motivo, recusa)
  LOOP
    BEGIN
      IF EXISTS (SELECT 1 FROM public.ponto_troca_turno t WHERE t.id = public.demo_id('ponto_troca:' || r.k)) THEN
        CONTINUE;
      END IF;
      v_id := public.ponto_troca_turno_solicitar(
        c_t, public.demo_id('ponto_atrib:' || r.na || ':atual'), public.demo_id('ponto_atrib:' || r.nb || ':atual'),
        v_hoje + r.d_ini, CASE WHEN r.d_dur IS NULL THEN NULL ELSE v_hoje + r.d_ini + r.d_dur END,
        public.demo_id('admissao:' || r.na),
        (SELECT a.nome_completo FROM public.admissoes a WHERE a.id = public.demo_id('admissao:' || r.na)),
        r.motivo);
      UPDATE public.ponto_troca_turno SET id = public.demo_id('ponto_troca:' || r.k) WHERE id = v_id;
      v_id := public.demo_id('ponto_troca:' || r.k);
      IF r.alvo IN ('aprovada', 'efetivada') THEN
        PERFORM public.ponto_troca_turno_aprovar(v_id, v_uid, 'Leiri');
      END IF;
      IF r.alvo = 'efetivada' THEN
        PERFORM public.ponto_troca_turno_efetivar(v_id);
      END IF;
      IF r.alvo = 'recusada' THEN
        PERFORM public.ponto_troca_turno_recusar(v_id, v_uid, 'Leiri', r.recusa);
      END IF;
      IF r.alvo = 'cancelada' THEN
        UPDATE public.ponto_troca_turno SET status = 'cancelada' WHERE id = v_id;
      END IF;
      UPDATE public.ponto_troca_turno SET solicitada_em = now() - make_interval(days => 2 + r.k) WHERE id = v_id;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Troca de turno % nao criada: % (%)', r.k, SQLERRM, SQLSTATE;
    END;
  END LOOP;

  -- ---- Compensacao de falta (aba Apuracao > Comp. Faltas) ----
  FOR r IN
    SELECT q.*, row_number() OVER (ORDER BY q.data DESC, q.cpf) AS rn
    FROM (
      SELECT DISTINCT ON (d.colaborador_cpf) d.colaborador_cpf AS cpf, d.data
      FROM public.ponto_diario d
      WHERE d.tenant_id = c_t AND d.status = 'falta'
        AND d.data BETWEEN v_hoje - 38 AND v_hoje - 2
        AND NOT EXISTS (SELECT 1 FROM public.ponto_compensacao_falta c WHERE c.tenant_id = c_t)
      ORDER BY d.colaborador_cpf, d.data DESC
    ) q
    ORDER BY q.data DESC, q.cpf
    LIMIT 8
  LOOP
    BEGIN
      v_res := public.ponto_registrar_compensacao_falta(c_t, r.cpf, r.data,
                 'Colaborador solicita compensar a falta com horas do banco (acordo coletivo vigente).');
      IF COALESCE((v_res ->> 'success')::boolean, false) IS NOT TRUE THEN
        RAISE NOTICE 'Compensacao de falta % / %: %', r.cpf, r.data, v_res ->> 'motivo';
        CONTINUE;
      END IF;
      v_id := (v_res ->> 'id')::uuid;
      IF r.rn BETWEEN 3 AND 6 THEN
        v_res := public.ponto_autorizar_compensacao_falta(c_t, v_id, 'Leiri');
        v_status := v_res ->> 'status';
        IF r.rn >= 4 AND v_status = 'pendente_homologacao' THEN
          PERFORM public.ponto_homologar_compensacao_falta(c_t, v_id, 'Leiri');
        END IF;
        IF r.rn >= 5 THEN
          PERFORM public.ponto_dar_ciencia_compensacao_falta(c_t, v_id, 'Colaborador (ciência registrada no espelho)');
        END IF;
      ELSIF r.rn = 7 THEN
        UPDATE public.ponto_compensacao_falta
           SET status = 'recusada', updated_at = now(),
               motivo = 'Falta sem justificativa; compensação não autorizada neste mês.'
         WHERE id = v_id;
      ELSIF r.rn = 8 THEN
        UPDATE public.ponto_compensacao_falta SET status = 'cancelada', updated_at = now() WHERE id = v_id;
      END IF;
      UPDATE public.ponto_compensacao_falta
         SET created_at = LEAST(now(), (r.data + 1)::timestamp AT TIME ZONE 'America/Sao_Paulo' + interval '10 hours')
       WHERE id = v_id;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Compensacao de falta % / % nao registrada: % (%)', r.cpf, r.data, SQLERRM, SQLSTATE;
    END;
  END LOOP;

  -- ---- Excedente de hora extra retido (decisao do gestor, art. 61 CLT) ----
  FOR r IN
    SELECT p.*, row_number() OVER (ORDER BY p.dia, p.colaborador_cpf) AS rn
    FROM public.ponto_excedente_pendentes(c_t,
           to_char(date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '1 month', 'YYYY-MM'), c_e) p
    WHERE NOT EXISTS (SELECT 1 FROM public.ponto_excedente_decisao x0 WHERE x0.tenant_id = c_t)
  LOOP
    BEGIN
      IF r.rn = 1 THEN
        PERFORM public.ponto_excedente_decidir(c_t, r.colaborador_cpf, r.dia, 'liberado',
          'Pico de produção autorizado pelo gestor para atender pedido urgente de cliente (necessidade imperiosa, art. 61 CLT).');
      ELSIF r.rn = 2 THEN
        PERFORM public.ponto_excedente_decidir(c_t, r.colaborador_cpf, r.dia, 'irregularidade',
          'Permanência além do limite sem autorização prévia; orientar o líder do setor e registrar advertência verbal.');
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Decisao de excedente % / % nao registrada: % (%)', r.colaborador_cpf, r.dia, SQLERRM, SQLSTATE;
    END;
  END LOOP;

  PERFORM set_config('request.jwt.claims', '', true);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Fluxos de gestao do ponto nao concluidos: % (%)', SQLERRM, SQLSTATE;
END $fluxos$;

-- Excecoes de feriado (aba Configuracoes > Feriados > Excecoes por colaborador):
-- a equipe de expedicao trabalha em feriados por escala de plantao
DO $w18$
BEGIN
INSERT INTO public.feriado_excecao (id, tenant_id, colaborador_id, data, comportamento, observacao)
SELECT public.demo_id('feriado_exc:' || s.n || ':' || h.data::text), 'd3e00000-0000-4000-8000-000000000001',
       public.demo_id('admissao:' || s.n), h.data, 'trabalha',
       'Plantão de feriado da produção (escala combinada com o líder).'
FROM generate_series(1, 59) s(n)
CROSS JOIN (VALUES (DATE '2026-09-07'), (DATE '2026-10-12')) AS h(data)
WHERE s.n % 7 = 0
  AND EXISTS (SELECT 1 FROM public.admissoes a WHERE a.id = public.demo_id('admissao:' || s.n) AND a.status = 'concluido')
  AND NOT EXISTS (SELECT 1 FROM public.feriado_excecao e WHERE e.id = public.demo_id('feriado_exc:' || s.n || ':' || h.data::text));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco feriado_excecao nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w18$;

-- Folga compensatoria do feriado trabalhado em 12/10 (quem nao a tem recebe adicional de 100%)
DO $w19$
BEGIN
INSERT INTO public.feriado_folga_compensatoria (id, tenant_id, colaborador_id, colaborador_cpf, data_feriado, data_folga, observacao)
SELECT public.demo_id('feriado_folga:' || s.n), 'd3e00000-0000-4000-8000-000000000001', a.id, a.cpf,
       DATE '2026-10-12', (timezone('America/Sao_Paulo', now()))::date + 3 + (s.n % 3),
       'Folga compensatória do feriado de Nossa Senhora Aparecida (acordada com o gestor).'
FROM generate_series(1, 59) s(n)
JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || s.n)
WHERE s.n IN (7, 14, 21) AND a.status = 'concluido'
  AND NOT EXISTS (SELECT 1 FROM public.feriado_folga_compensatoria f WHERE f.id = public.demo_id('feriado_folga:' || s.n));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco feriado_folga_compensatoria nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w19$;

-- (fim da etapa: confirma o que ja foi feito, para a transacao nao ficar longa demais)
COMMIT;
SET LOCAL statement_timeout = '600s';

-- Reapuracao final do banco de horas das competencias ainda abertas (depois dos
-- fluxos acima), para a fotografia do banco bater com a apuracao oficial
DO $reap$
DECLARE
  c_t constant uuid := 'd3e00000-0000-4000-8000-000000000001';
  c_e constant uuid := 'd3e00000-0000-4000-8000-000000000002';
  v_comp text;
  v_cpf text;
BEGIN
  FOR v_comp IN
    SELECT to_char(m, 'YYYY-MM')
    FROM generate_series(date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months',
                         date_trunc('month', timezone('America/Sao_Paulo', now())), interval '1 month') m
    ORDER BY 1
  LOOP
    IF EXISTS (SELECT 1 FROM public.ponto_fechamentos f
               WHERE f.tenant_id = c_t AND f.empresa_id = c_e AND f.competencia = v_comp AND f.status = 'fechado') THEN
      CONTINUE;
    END IF;
    FOR v_cpf IN
      SELECT DISTINCT d.colaborador_cpf FROM public.ponto_diario d
      WHERE d.tenant_id = c_t AND to_char(d.data, 'YYYY-MM') = v_comp AND d.colaborador_cpf IS NOT NULL
    LOOP
      PERFORM public.apurar_banco_horas_colaborador(c_t, v_cpf, v_comp, c_e);
    END LOOP;
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Reapuracao final do banco de horas nao concluida: % (%)', SQLERRM, SQLSTATE;
END $reap$;

-- (fim da etapa: confirma o que ja foi feito, para a transacao nao ficar longa demais)
COMMIT;
SET LOCAL statement_timeout = '600s';

-- ---------------------------------------------------------------------------
-- (10) Alertas de ponto (aba Compliance > Alertas CLT) e analises sugeridas
--      Os alertas de falta / atraso / intervalo nascem dos gatilhos do ponto, aqui
--      so se limpa o ruido de gravacao em tempo real, se carimba a data do fato e
--      se resolvem os antigos. Os demais tipos sao derivados dos proprios dias.
-- ---------------------------------------------------------------------------
-- Intervalo "suprimido" que so existiu enquanto o dia estava sendo batido
-- (almoco sem retorno ainda) e que o dia final nao confirma
DO $w20$
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
END $w20$;

-- Falta de marcacao: dias incompletos ou com ajuste pendente (ultimos 15 dias)
DO $w21$
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
END $w21$;

-- Excesso de jornada: dias com mais de 10 h trabalhadas (art. 59 CLT)
DO $w22$
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
END $w22$;

-- Interjornada insuficiente: menos de 11 h entre a saida e a entrada seguinte (art. 66 CLT)
DO $w23$
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
END $w23$;

-- Horas extras recorrentes: quem teve credito em muitos dos ultimos 30 dias
DO $w24$
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
END $w24$;

-- Banco vencendo: tres colaboradores com saldo positivo e prazo de compensacao proximo
DO $w25$
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
END $w25$;

DO $w26$
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
END $w26$;

-- Carimba a data do fato e resolve os alertas antigos (so os dos ultimos 10 dias ficam abertos)
DO $w27$
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
END $w27$;

DO $w28$
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
END $w28$;

-- Analises sugeridas (texto pronto, a IA nao roda neste script)
DO $w29$
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
END $w29$;

-- (fim da etapa: confirma o que ja foi feito, para a transacao nao ficar longa demais)
COMMIT;
SET LOCAL statement_timeout = '600s';

-- ---------------------------------------------------------------------------
-- (12) Links de ponto externo, REP-C, certificado digital, dossie de fiscalizacao
--      e historico de exportacoes para a folha (tokens e hashes sao ficticios)
-- ---------------------------------------------------------------------------
-- Link compartilhado da empresa (um por tenant) — valido por mais 45 dias
DO $w30$
BEGIN
INSERT INTO public.ponto_links (id, tenant_id, colaborador_id, colaborador_nome, colaborador_cpf, token, ativo, data_expiracao, tipo, tentativas_frustradas, created_at)
SELECT public.demo_id('ponto_link:compartilhado'), 'd3e00000-0000-4000-8000-000000000001',
       '00000000-0000-0000-0000-000000000000', 'Link compartilhado', '',
       md5('demo-ponto-link-compartilhado-metalurgica'), true, now() + interval '45 days', 'compartilhado', 0,
       now() - interval '135 days'
WHERE NOT EXISTS (SELECT 1 FROM public.ponto_links WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND tipo = 'compartilhado');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_links nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w30$;

-- Links individuais (operadores de chao de fabrica, sem acesso ao sistema)
DO $w31$
BEGIN
INSERT INTO public.ponto_links (id, tenant_id, colaborador_id, colaborador_nome, colaborador_cpf, token, ativo, data_expiracao, tipo, tentativas_frustradas, bloqueado_ate, created_at)
SELECT public.demo_id('ponto_link:' || s.n), 'd3e00000-0000-4000-8000-000000000001', a.id::text, a.nome_completo, a.cpf,
       md5('demo-ponto-link-individual-' || s.n),
       s.n <> 45,
       CASE WHEN s.n = 45 THEN now() - interval '12 days'
            WHEN s.n = 3 THEN now() + interval '9 days'
            ELSE now() + make_interval(days => 40 + public.demo_ponto_rnd('lnk' || s.n, 130)) END,
       'colaborador',
       CASE WHEN s.n = 17 THEN 5 ELSE 0 END,
       CASE WHEN s.n = 17 THEN now() + interval '40 minutes' END,
       now() - make_interval(days => 20 + public.demo_ponto_rnd('lnkc' || s.n, 100))
FROM generate_series(1, 59) s(n)
JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || s.n)
WHERE s.n IN (1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 41, 43, 45, 47) AND a.status = 'concluido'
  AND NOT EXISTS (SELECT 1 FROM public.ponto_links l WHERE l.id = public.demo_id('ponto_link:' || s.n));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_links nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w31$;

-- Importacoes de AFD de REP-C (aba Configuracoes > REP-C)
DO $w32$
BEGIN
INSERT INTO public.ponto_repc_importacoes (
  id, tenant_id, empresa_id, arquivo_nome, tipo_equipamento, fabricante, modelo, numero_serie,
  total_registros, registros_importados, registros_rejeitados, status, erros, importado_por, importado_por_id,
  arquivo_hash, crc_valido, assinatura_valida, cadeia_valida, quarentena, relatorio, created_at, updated_at)
SELECT public.demo_id('ponto_repc:' || v.k), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       v.arquivo, 'REP-C', 'Fabricante Demo', 'Relógio Eletrônico Modelo X1', '00001.00002.00003.0001',
       v.total, v.imp, v.rej, v.status, v.erros, 'Leiri',
       (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' ORDER BY u.created_at LIMIT 1),
       md5('demo-afd-' || v.k), v.crc, v.ass, v.cad, v.quarentena, v.relatorio,
       now() - make_interval(days => v.dias), now() - make_interval(days => v.dias)
FROM (VALUES
  (1, 'AFD00001000200030001_portaria_acesso.txt', 1480, 1480, 0, 'concluido', '[]'::jsonb, true, true, true, false,
     '{"resumo": "Arquivo íntegro: CRC, assinatura e cadeia de NSR conferidos."}'::jsonb, 52),
  (2, 'AFD00001000200030001_expedicao.txt', 912, 904, 8, 'concluido',
     '[{"linha": 118, "mensagem": "Colaborador não encontrado para o CPF informado"}, {"linha": 431, "mensagem": "Marcação duplicada no mesmo minuto"}]'::jsonb,
     true, true, true, false, '{"resumo": "8 registros rejeitados; os demais foram importados."}'::jsonb, 24),
  (3, 'AFD00001000200030001_adulterado.txt', 640, 0, 640, 'erro',
     '[{"linha": 1, "mensagem": "Assinatura digital inválida: o arquivo foi alterado após a emissão"}]'::jsonb,
     true, false, false, true, '{"resumo": "Arquivo em quarentena: assinatura e cadeia de NSR não conferem."}'::jsonb, 9)
) AS v(k, arquivo, total, imp, rej, status, erros, crc, ass, cad, quarentena, relatorio, dias)
WHERE NOT EXISTS (SELECT 1 FROM public.ponto_repc_importacoes r WHERE r.id = public.demo_id('ponto_repc:' || v.k));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_repc_importacoes nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w32$;

-- Certificados digitais ICP-Brasil (assinatura dos documentos de ponto)
DO $w33$
BEGIN
INSERT INTO public.ponto_certificados_digitais (
  id, tenant_id, empresa_id, certificado_digital_tipo, icp_brasil, titular_nome, titular_documento, numero_serie,
  emissor, fingerprint, valido_de, valido_ate, alerta_antecedencia_dias, ativo)
SELECT public.demo_id('ponto_cert:' || v.k), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       'A1', true, 'METALURGICA EXEMPLO LTDA', '98.765.432/0001-02', v.serie, 'AC Demonstração ICP-Brasil (fictícia)',
       upper(md5('demo-cert-' || v.k) || substr(md5('x-demo-cert-' || v.k), 1, 8)),
       (timezone('America/Sao_Paulo', now()))::date + v.de, (timezone('America/Sao_Paulo', now()))::date + v.ate, 30, v.ativo
FROM (VALUES
  (1, '5A3F00D1C2B4E6A7', -150, 215, true),
  (2, '4C21B9E0A7D35F18', -515, -150, false)
) AS v(k, serie, de, ate, ativo)
WHERE NOT EXISTS (SELECT 1 FROM public.ponto_certificados_digitais c WHERE c.id = public.demo_id('ponto_cert:' || v.k));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_certificados_digitais nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w33$;

-- Dossie de fiscalizacao das competencias fechadas (pecas e hashes do pacote)
DO $w34$
BEGIN
INSERT INTO public.ponto_dossies_fiscalizacao (id, tenant_id, empresa_id, competencia, periodo_ini, periodo_fim, total_pecas, indice, hash_pacote, gerado_em, created_at)
SELECT public.demo_id('ponto_dossie:' || f.competencia), f.tenant_id, f.empresa_id, f.competencia,
       to_date(f.competencia || '-01', 'YYYY-MM-DD'), (to_date(f.competencia || '-01', 'YYYY-MM-DD') + interval '1 month - 1 day')::date,
       p.marc + p.esp + 1,
       jsonb_build_array(
         jsonb_build_object('peca', 'aej', 'quantidade', 1, 'hash', md5('aej' || f.competencia)),
         jsonb_build_object('peca', 'comprovantes', 'quantidade', p.marc, 'hash', md5('comp' || f.competencia)),
         jsonb_build_object('peca', 'espelhos', 'quantidade', p.esp, 'hash', md5('esp' || f.competencia)),
         jsonb_build_object('peca', 'afd_importado', 'quantidade', 1, 'hash', md5('afd' || f.competencia))),
       md5('demo-dossie|' || f.competencia),
       f.data_fechamento + interval '1 day', f.data_fechamento + interval '1 day'
FROM public.ponto_fechamentos f
CROSS JOIN LATERAL (
  SELECT (SELECT count(*) FROM public.ponto_marcacoes m
           WHERE m.tenant_id = f.tenant_id AND to_char(m.data_marcacao, 'YYYY-MM') = f.competencia)::int AS marc,
         (SELECT count(*) FROM public.ponto_espelhos e WHERE e.tenant_id = f.tenant_id AND e.competencia = f.competencia)::int AS esp
) p
WHERE f.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND f.status = 'fechado'
  AND NOT EXISTS (SELECT 1 FROM public.ponto_dossies_fiscalizacao d
                  WHERE d.tenant_id = f.tenant_id AND d.competencia = f.competencia);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_dossies_fiscalizacao nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w34$;

-- Exportacoes para a folha das competencias fechadas
DO $w35$
BEGIN
INSERT INTO public.ponto_exportacoes_folha (id, tenant_id, empresa_id, competencia, formato, sistema_destino, total_colaboradores, arquivo_nome, status, gerado_por, gerado_por_id, dados_exportados, created_at)
SELECT public.demo_id('ponto_export:' || f.competencia), f.tenant_id, f.empresa_id, f.competencia,
       'xlsx', 'generico', f.total_colaboradores, 'Folha_' || f.competencia || '.xlsx', 'processado', 'Leiri',
       (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' ORDER BY u.created_at LIMIT 1),
       jsonb_build_object('total', f.total_colaboradores, 'sistema', 'generico'),
       f.data_fechamento + interval '3 hours'
FROM public.ponto_fechamentos f
WHERE f.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND f.status = 'fechado'
  AND NOT EXISTS (SELECT 1 FROM public.ponto_exportacoes_folha x WHERE x.id = public.demo_id('ponto_export:' || f.competencia));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_exportacoes_folha nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w35$;

-- (fim da etapa: confirma o que ja foi feito, para a transacao nao ficar longa demais)
COMMIT;
SET LOCAL statement_timeout = '600s';

-- ---------------------------------------------------------------------------
-- (12b) Arquivos oficiais: AEJ das competencias fechadas (Portaria MTP 671) e
--       comprovantes de registro das marcacoes dos ultimos 15 dias
-- ---------------------------------------------------------------------------
DO $arquivos$
DECLARE
  v_comp text;
BEGIN
  FOR v_comp IN
    SELECT f.competencia FROM public.ponto_fechamentos f
    WHERE f.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND f.status = 'fechado'
    ORDER BY f.competencia
  LOOP
    BEGIN
      PERFORM public.ponto_gerar_aej('d3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002', v_comp);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'AEJ % nao gerado: % (%)', v_comp, SQLERRM, SQLSTATE;
    END;
  END LOOP;

  BEGIN
    PERFORM public.ponto_gerar_comprovante(m.tenant_id, m.id)
    FROM public.ponto_marcacoes m
    WHERE m.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
      AND m.data_marcacao >= (timezone('America/Sao_Paulo', now()))::date - 15
      AND NOT COALESCE(m.comprovante_gerado, false)
      AND to_char(m.data_marcacao, 'YYYY-MM') NOT IN (
        SELECT f.competencia FROM public.ponto_fechamentos f
        WHERE f.tenant_id = m.tenant_id AND f.status = 'fechado');
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Comprovantes nao gerados: % (%)', SQLERRM, SQLSTATE;
  END;
END $arquivos$;

-- (fim da etapa: confirma o que ja foi feito, para a transacao nao ficar longa demais)
COMMIT;
SET LOCAL statement_timeout = '600s';

-- ---------------------------------------------------------------------------
-- (13) Analise de Carga de Trabalho e Jornada (/analise-jornada)
--      Mesma conta do botao "Executar Analise", feita sobre o ponto apurado acima
--      (horas extras = credito de cada dia na apuracao oficial), uma analise por
--      colaborador cobrindo o historico inteiro, alertas derivados com as mesmas
--      regras, parametros, documentos, importacoes e modelo de mapeamento.
-- ---------------------------------------------------------------------------
DO $w36$
BEGIN
INSERT INTO public.jornada_parametros (id, tenant_id, nome, jornada_diaria_max, jornada_semanal_max, horas_extras_diaria_max,
  intervalo_intrajornada_min, descanso_interjornada_min, descanso_semanal_min, ativo)
SELECT public.demo_id('jornada_param:padrao'), 'd3e00000-0000-4000-8000-000000000001', 'Parâmetros CLT (padrão da empresa)',
       8.8, 44, 2, 60, 11, 24, true
WHERE NOT EXISTS (SELECT 1 FROM public.jornada_parametros p WHERE p.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND p.nome = 'Parâmetros CLT (padrão da empresa)')
  AND NOT EXISTS (SELECT 1 FROM public.jornada_parametros p WHERE p.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND p.ativo);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco jornada_parametros nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w36$;

DO $w37$
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
END $w37$;

-- Alertas inteligentes (mesmas regras do botao Executar Analise + atraso e ajustes)
DO $w38$
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
END $w38$;

-- Documentos (aba Documentos): so registros, sem arquivo anexado no armazenamento
DO $w39$
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
END $w39$;

-- Historico de importacoes de planilhas de ponto (aba Importacao)
DO $w40$
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
END $w40$;

DO $w41$
BEGIN
INSERT INTO public.jornada_templates_mapeamento (id, tenant_id, nome, descricao, mapeamento, headers_originais, criado_por, created_at)
SELECT public.demo_id('jornada_tpl:' || v.k), 'd3e00000-0000-4000-8000-000000000001', v.nome, v.descr,
       '{"colaboradorNome": 0, "colaboradorCpf": 1, "data": 2, "entrada": 3, "saidaAlmoco": 4, "retornoAlmoco": 5, "saida": 6}'::jsonb,
       ARRAY['Nome', 'CPF', 'Data', 'Entrada', 'Saída Almoço', 'Retorno Almoço', 'Saída'], 'Leiri', now() - interval '40 days'
FROM (VALUES (1, 'Planilha do relógio da filial', 'Layout exportado pelo relógio de ponto das filiais.')) AS v(k, nome, descr)
WHERE NOT EXISTS (SELECT 1 FROM public.jornada_templates_mapeamento t WHERE t.id = public.demo_id('jornada_tpl:' || v.k));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco jornada_templates_mapeamento nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w41$;

-- (fim da etapa: confirma o que ja foi feito, para a transacao nao ficar longa demais)
COMMIT;
SET LOCAL statement_timeout = '600s';

-- ---------------------------------------------------------------------------
-- (14) Limpeza das funcoes auxiliares deste arquivo
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.demo_ponto_gerar(date, date);
DROP FUNCTION IF EXISTS public.demo_ponto_marca_dia(text, uuid, text, date, time without time zone[], text[], text, time without time zone);
DROP FUNCTION IF EXISTS public.demo_ponto_decisao(uuid, text, date);
DROP FUNCTION IF EXISTS public.demo_ponto_rnd(text, integer);

-- ---------------------------------------------------------------------------
-- Conferencia final (uma linha)
-- ---------------------------------------------------------------------------
SELECT
  (SELECT count(*) FROM public.ponto_marcacoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS marcacoes,
  (SELECT count(*) FROM public.ponto_diario WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS dias_apurados,
  (SELECT count(*) FROM public.ponto_diario WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND status = 'falta') AS faltas,
  (SELECT count(*) FROM public.ponto_diario WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND status = 'atraso') AS atrasos,
  (SELECT count(*) FROM public.ponto_escalas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS escalas,
  (SELECT count(*) FROM public.ponto_escala_atribuicoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS atribuicoes,
  (SELECT count(*) FROM public.ponto_ajustes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND status = 'pendente') AS ajustes_pendentes,
  (SELECT count(*) FROM public.ponto_ajustes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND status = 'aprovado') AS ajustes_aprovados,
  (SELECT count(*) FROM public.ponto_ajustes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND status = 'rejeitado') AS ajustes_recusados,
  (SELECT count(*) FROM public.ponto_fechamentos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND status = 'fechado') AS competencias_fechadas,
  (SELECT count(*) FROM public.ponto_espelhos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS espelhos,
  (SELECT count(*) FROM public.ponto_banco_horas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS bancos_de_horas,
  (SELECT count(*) FROM public.ponto_banco_horas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND saldo_atual_minutos > 0) AS saldos_positivos,
  (SELECT count(*) FROM public.ponto_banco_horas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND saldo_atual_minutos < 0) AS saldos_negativos,
  (SELECT count(*) FROM public.ponto_alertas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND NOT resolvido) AS alertas_abertos,
  (SELECT count(*) FROM public.feriados WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS feriados,
  (SELECT count(*) FROM public.ponto_links WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS links_ponto_externo,
  (SELECT count(*) FROM public.jornada_analises WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS analises_jornada,
  (SELECT count(*) FROM public.jornada_alertas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS alertas_jornada,
  CASE WHEN (SELECT count(*) FROM public.ponto_marcacoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') > 8000
        AND (SELECT count(*) FROM public.ponto_escalas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 4
        AND (SELECT count(*) FROM public.ponto_ajustes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 20
        AND (SELECT count(*) FROM public.ponto_fechamentos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND status = 'fechado') >= 2
        AND (SELECT count(*) FROM public.ponto_banco_horas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 100
        AND (SELECT count(*) FROM public.jornada_analises WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 50
       THEN 'OK' ELSE 'CONFERIR' END AS situacao;

-- ---------------------------------------------------------------------------
-- COMO REFAZER: este arquivo so cria dados do tenant demo e as marcacoes nao podem
-- ser apagadas (regra legal do ponto). Para recomecar do zero, recrie o tenant
-- demo pela parte 00 em outro identificador de tenant. Nenhum dado existente de
-- outro tenant foi lido para escrita, alterado ou apagado por este arquivo.
-- ---------------------------------------------------------------------------
