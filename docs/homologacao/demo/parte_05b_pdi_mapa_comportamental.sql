-- ============================================================================
-- HOMOLOGACAO — DEMONSTRACAO, PARTE 05b: PDI + Mapa Comportamental
--
-- PARA QUE SERVE
-- Preenche as telas /pdi (lista, detalhe com metas SMART, acoes, check-ins,
-- feedbacks, assinaturas) e /mapa-comportamental (Meu Mapa, Painel, Mapa do Time,
-- Campanhas, Governanca/politica de uso, Guia do Lider) da "Metalurgica Exemplo
-- Ltda" (100% ficticia). Depende da PARTE 00 (e, para o vinculo dos PDIs com a
-- avaliacao, da PARTE 05a — mas roda sozinha se a 05a ainda nao foi aplicada).
--
-- ONDE COLAR
-- SQL Editor do projeto de HOMOLOGACAO, depois da parte 00. O arquivo se RECUSA a
-- rodar fora da homologacao/teste (mesma trava da parte 00). Nunca na producao.
--
-- O QUE FAZ (tudo no tenant demo, empresa matriz)
--   1. 21 PDIs (ativos, concluidos, rascunhos, 1 pausado e 1 cancelado) com 2 metas
--      SMART cada (quando aplicavel), acoes, check-ins, feedbacks e links de
--      assinatura (assinados e pendentes); acoes do Plano de Acao ligadas a metas;
--   2. Politica de uso publicada, 3 campanhas do Mapa Comportamental (encerrada,
--      ativa, rascunho) com cobertura, 47 mapas concluidos de colaboradores
--      (resultados calculados com o MESMO algoritmo do app), 2 mapas do login da demo
--      (atual + reaplicacao anterior), contestacoes, registro de acessos, link
--      publico e perfil ideal por cargo (aderencia a funcao).
--
-- GARANTIAS
--   - Nenhum dado real; CPFs so pela funcao ficticia da casa (900.000.0XX).
--   - Idempotente: ids fixos (demo_id) + "so insere se nao existe".
--   - Nao cria tabela e so altera linhas do proprio tenant demo (o status final de
--     PDIs pausado/cancelado, que o gatilho de progresso recalcula).
--   - As respostas item a item do mapa so sao gravadas para o login da demo
--     (as dos colaboradores ficam fora, como manda a regra de privacidade do modulo).
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
END $trava$;

CREATE OR REPLACE FUNCTION public.demo_id(chave text)
RETURNS uuid
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT md5('youreyes-demo:' || chave)::uuid
$fn$;

CREATE OR REPLACE FUNCTION public.demo_dev_rnd(chave text, m integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT (('x' || substr(md5('youreyes-demo-rnd:' || chave), 1, 7))::bit(28)::int) % GREATEST(m, 1)
$fn$;

-- CPF ficticio da casa (mesmo corpo da parte 00), para rodar isolada.
CREATE OR REPLACE FUNCTION public.demo_cpf(n integer)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
DECLARE
  b text := '900000' || lpad(n::text, 3, '0');
  s integer := 0;
  d1 integer;
  d2 integer;
  i integer;
BEGIN
  FOR i IN 1..9 LOOP
    s := s + substr(b, i, 1)::integer * (11 - i);
  END LOOP;
  d1 := (s * 10) % 11;
  IF d1 = 10 THEN d1 := 0; END IF;
  s := 0;
  FOR i IN 1..9 LOOP
    s := s + substr(b, i, 1)::integer * (12 - i);
  END LOOP;
  s := s + d1 * 2;
  d2 := (s * 10) % 11;
  IF d2 = 10 THEN d2 := 0; END IF;
  RETURN b || d1::text || d2::text;
END
$fn$;

-- ---------------------------------------------------------------------------
-- (1) PDIs
--     ini/fim em dias a partir de hoje; resp = numero do colaborador lider (admissao)
--     ou texto livre quando o gestor e uma funcao sem pessoa cadastrada.
-- ---------------------------------------------------------------------------
INSERT INTO public.pdis (
  id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cargo, colaborador_departamento,
  titulo, descricao, periodo, status, data_inicio, data_fim, responsavel_nome, co_responsavel_nome,
  progresso, pontuacao, gatilho, ciclo_avaliacao_id, observacoes, criado_por_nome, created_at, updated_at
)
SELECT public.demo_id('pdi:' || v.chave), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       a.id::text, a.nome_completo, a.cargo, a.departamento,
       v.titulo, v.descr, v.periodo::public.pdi_periodo, v.status::public.pdi_status,
       CURRENT_DATE + v.ini, CURRENT_DATE + v.fim,
       COALESCE((SELECT l.nome_completo FROM public.admissoes l WHERE l.id = public.demo_id('admissao:' || v.resp)), v.resp_txt),
       'Leiri', 0, v.pontos, v.gatilho,
       CASE WHEN v.gatilho = 'avaliacao_desempenho' THEN public.demo_id('avciclo:c2') END,
       v.obs, 'Leiri', now() + (v.ini - 2) * interval '1 day', now() - interval '1 day'
FROM (VALUES
  ('p1',  13, 'Qualificação em solda MIG/MAG nível 2', 'Plano para elevar o domínio técnico de solda e reduzir o retrabalho, definido após a avaliação do 1º semestre.', 'semestral', -120, 60, 'ativo', 'avaliacao_desempenho', 28, NULL, 120, NULL),
  ('p2',  28, 'Liderança de equipe de produção', 'Desenvolvimento de habilidades de gestão de pessoas e de rotina de turno.', 'anual', -200, 165, 'ativo', 'avaliacao_desempenho', NULL, 'Direção Industrial', 180, NULL),
  ('p3',  29, 'Formação de liderança operacional', 'Preparação para assumir o turno B. Concluído com sucesso.', 'semestral', -300, -120, 'concluido', 'avaliacao_desempenho', NULL, 'Direção Industrial', 300, 'Assumiu a liderança do turno B em maio.'),
  ('p4',  40, 'Gestão da manutenção preditiva', 'Implantação da manutenção preditiva nas máquinas CNC e formação da equipe.', 'semestral', -90, 90, 'ativo', 'avaliacao_desempenho', NULL, 'Direção Industrial', 150, NULL),
  ('p5',  52, 'Gestão de estoques e indicadores logísticos', 'Fortalecer o controle de inventário e o acompanhamento de indicadores.', 'anual', -150, 215, 'ativo', 'avaliacao_desempenho', NULL, 'Direção Industrial', 90, NULL),
  ('p6',  3,  'Integração — Operador de Usinagem CNC', 'PDI de integração gerado após a admissão: segurança, cultura e autonomia na máquina.', 'trimestral', -60, 30, 'ativo', 'onboarding', 28, NULL, 80, NULL),
  ('p7',  1,  'Integração — Operador de Usinagem CNC', 'PDI de integração dos primeiros 90 dias.', 'trimestral', -45, 45, 'ativo', 'onboarding', 28, NULL, 40, NULL),
  ('p8',  30, 'Hidráulica e pneumática industrial', 'Aprofundar o diagnóstico de falhas em prensas e sistemas hidráulicos. Prazo vencido: replanejar com o supervisor.', 'semestral', -185, -5, 'ativo', 'manual', 40, NULL, 100, 'Prazo vencido; renovar o período após reunião com o supervisor.'),
  ('p9',  36, 'Reciclagem NR-10 e SEP', 'Reciclagem obrigatória de segurança em instalações elétricas.', 'trimestral', -200, -110, 'concluido', 'manual', 40, NULL, 200, NULL),
  ('p10', 53, 'Excel avançado e análise financeira', 'Automatizar rotinas do fechamento e melhorar a análise de contas a receber.', 'semestral', -80, 100, 'ativo', 'avaliacao_desempenho', NULL, 'Gerência Administrativa', 110, NULL),
  ('p11', 55, 'Auditor interno ISO 9001', 'Formação e prática como auditor interno do sistema da qualidade.', 'semestral', -260, -80, 'concluido', 'avaliacao_desempenho', NULL, 'Gerência Administrativa', 250, NULL),
  ('p12', 58, 'Integração — Analista de RH', 'PDI de integração em elaboração (rascunho).', 'trimestral', -5, 85, 'rascunho', 'onboarding', NULL, 'Gerência Administrativa', 0, NULL),
  ('p13', 59, 'Integração — Analista de RH', 'PDI de integração em elaboração (rascunho).', 'trimestral', -4, 86, 'rascunho', 'onboarding', NULL, 'Gerência Administrativa', 0, NULL),
  ('p14', 22, 'Leitura e interpretação de desenho técnico', 'Capacitação para interpretar desenhos de conjuntos soldados.', 'trimestral', -70, 20, 'pausado', 'avaliacao_desempenho', 28, NULL, 20, 'Pausado até a liberação da agenda do turno B.'),
  ('p15', 45, 'Operador de empilhadeira — reciclagem NR-11 e direção defensiva', 'Reciclagem de segurança e redução de incidentes de movimentação.', 'trimestral', -50, 40, 'ativo', 'avaliacao_desempenho', 52, NULL, 100, NULL),
  ('p16', 9,  'Programação CNC avançada', 'Perfil identificado no mapa comportamental: aprendizado prático. Foco em programação de peças novas.', 'semestral', -60, 120, 'ativo', 'mapa_comportamental', 28, NULL, 90, NULL),
  ('p17', 17, 'Certificação de solda posição 6G', 'Cancelado: a certificação passou a ser conduzida por entidade externa em 2027.', 'semestral', -90, 90, 'cancelado', 'manual', 28, NULL, 0, 'Cancelado por mudança de estratégia de certificação.'),
  ('p18', 41, 'Segurança na movimentação de cargas', 'Reciclagem e prática de direção defensiva. Concluído.', 'trimestral', -150, -60, 'concluido', 'avaliacao_desempenho', 52, NULL, 160, NULL),
  ('p19', 56, 'Estatística aplicada à qualidade (CEP)', 'Aplicar controle estatístico de processo em características críticas.', 'semestral', -40, 140, 'ativo', 'avaliacao_desempenho', NULL, 'Gerência Administrativa', 40, NULL),
  ('p20', 8,  'Leitura de desenho e metrologia', 'Metrologia básica e leitura de desenho para operadores CNC.', 'trimestral', -30, 60, 'ativo', 'avaliacao_desempenho', 28, NULL, 70, NULL),
  ('p21', 24, 'Soldagem básica para montadores', 'Habilitação básica de solda para apoiar o setor de montagem. Concluído.', 'semestral', -280, -100, 'concluido', 'avaliacao_desempenho', 28, NULL, 220, NULL)
) AS v(chave, n, titulo, descr, periodo, ini, fim, status, gatilho, resp, resp_txt, pontos, obs)
JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || v.n)
WHERE NOT EXISTS (SELECT 1 FROM public.pdis p WHERE p.id = public.demo_id('pdi:' || v.chave));

-- Metas SMART (2 por PDI, quando houver). O gatilho do banco recalcula o progresso
-- e o status do PDI a partir das metas.
INSERT INTO public.pdi_metas (
  id, tenant_id, pdi_id, titulo, descricao, categoria, status, especifica, mensuravel, atingivel, relevante, temporal,
  indicador_sucesso, valor_base, valor_alvo, valor_atual, unidade, data_inicio, data_fim, frequencia_checkin, peso,
  progresso, created_at, updated_at
)
SELECT public.demo_id('pdimeta:' || v.pdi || ':' || v.idx), 'd3e00000-0000-4000-8000-000000000001', p.id,
       v.titulo, v.titulo || ' — meta do ' || lower(left(p.titulo, 1)) || substr(p.titulo, 2) || '.',
       v.cat::public.pdi_meta_categoria,
       CASE WHEN p.status = 'cancelado' THEN 'cancelada'::public.pdi_meta_status
            WHEN v.prog >= 100 THEN 'concluida'::public.pdi_meta_status
            WHEN v.prog > 0 AND p.data_fim < CURRENT_DATE THEN 'atrasada'::public.pdi_meta_status
            WHEN v.prog > 0 THEN 'em_andamento'::public.pdi_meta_status
            ELSE 'nao_iniciada'::public.pdi_meta_status END,
       'Específica: ' || v.titulo || '.',
       'Mensurável: ' || COALESCE('de ' || v.base || ' para ' || v.alvo || ' ' || v.un, 'conclusão comprovada por evidência ou certificado') || '.',
       'Atingível: carga horária compatível com a escala do turno e apoio do líder.',
       'Relevante: alinhada à função e às metas do setor.',
       'Temporal: até ' || to_char(p.data_fim, 'DD/MM/YYYY') || '.',
       COALESCE(v.alvo::text || ' ' || v.un, 'Certificado/entrega validada pelo líder'),
       v.base, v.alvo,
       CASE WHEN v.alvo IS NOT NULL THEN round((v.base + (v.alvo - v.base) * v.prog / 100.0)::numeric, 2) END,
       v.un, p.data_inicio, p.data_fim,
       (CASE WHEN v.idx = 1 THEN 'quinzenal' ELSE 'mensal' END)::public.pdi_checkin_frequencia,
       v.peso, v.prog, p.created_at, now() - interval '2 days'
FROM (VALUES
  ('p1', 1, 'Concluir a qualificação de soldador nível 2', 'tecnica', 65, 0, 4, 'etapas', 3),
  ('p1', 2, 'Reduzir o retrabalho de solda para 2%', 'processos', 40, 6, 2, '% de retrabalho', 2),
  ('p2', 1, 'Conduzir a reunião de início de turno com as metas do dia', 'lideranca', 70, 0, 100, '% dos dias', 3),
  ('p2', 2, 'Realizar feedback individual quinzenal com a equipe', 'lideranca', 45, 0, 24, 'feedbacks', 3),
  ('p3', 1, 'Concluir a trilha Liderança Operacional', 'lideranca', 100, NULL, NULL, NULL, 3),
  ('p3', 2, 'Assumir a liderança do turno B', 'lideranca', 100, NULL, NULL, NULL, 3),
  ('p4', 1, 'Instalar sensores de vibração em 5 máquinas CNC', 'tecnica', 60, 0, 5, 'máquinas', 3),
  ('p4', 2, 'Formar a equipe para leitura de laudos de vibração', 'tecnica', 30, 0, 6, 'técnicos', 2),
  ('p5', 1, 'Reduzir a divergência de inventário para 0,5%', 'processos', 20, 1.8, 0.5, '%', 3),
  ('p5', 2, 'Criar o painel de indicadores de logística', 'tecnica', 55, 0, 4, 'indicadores', 2),
  ('p6', 1, 'Concluir a trilha de integração e segurança', 'cultura', 85, NULL, NULL, NULL, 2),
  ('p6', 2, 'Operar a CNC com autonomia nas ordens padrão', 'tecnica', 40, 0, 100, '% do checklist', 3),
  ('p7', 1, 'Concluir a trilha de integração e segurança', 'cultura', 30, NULL, NULL, NULL, 2),
  ('p7', 2, 'Operar a CNC com autonomia nas ordens padrão', 'tecnica', 10, 0, 100, '% do checklist', 3),
  ('p8', 1, 'Concluir o curso de hidráulica industrial', 'tecnica', 55, 0, 40, 'horas', 3),
  ('p8', 2, 'Diagnosticar falhas hidráulicas sem apoio', 'tecnica', 20, 0, 10, 'casos', 2),
  ('p9', 1, 'Reciclagem NR-10 (40 horas)', 'tecnica', 100, NULL, NULL, NULL, 3),
  ('p9', 2, 'Reciclagem SEP — Sistema Elétrico de Potência', 'tecnica', 100, NULL, NULL, NULL, 2),
  ('p10', 1, 'Concluir o curso de Excel avançado', 'tecnica', 80, 0, 100, '% do curso', 3),
  ('p10', 2, 'Automatizar o fechamento mensal em planilha', 'processos', 50, 0, 5, 'rotinas', 2),
  ('p11', 1, 'Certificar-se como auditor interno ISO 9001', 'tecnica', 100, NULL, NULL, NULL, 3),
  ('p11', 2, 'Conduzir 3 auditorias internas acompanhadas', 'processos', 100, NULL, NULL, NULL, 3),
  ('p12', 1, 'Conhecer os processos de departamento pessoal e SST', 'cultura', 0, NULL, NULL, NULL, 2),
  ('p14', 1, 'Concluir o curso de leitura de desenho técnico', 'tecnica', 25, 0, 30, 'horas', 3),
  ('p14', 2, 'Interpretar o desenho de 3 conjuntos soldados', 'tecnica', 0, 0, 3, 'conjuntos', 2),
  ('p15', 1, 'Reciclagem NR-11 e direção defensiva', 'tecnica', 60, 0, 16, 'horas', 3),
  ('p15', 2, 'Manter zero incidentes de movimentação', 'saude_bem_estar', 100, NULL, NULL, NULL, 2),
  ('p16', 1, 'Concluir o curso de programação CNC (G-code)', 'tecnica', 45, 0, 60, 'horas', 3),
  ('p16', 2, 'Programar 5 peças novas sem apoio', 'tecnica', 20, 0, 5, 'peças', 3),
  ('p17', 1, 'Concluir a qualificação 6G', 'tecnica', 20, 0, 5, 'etapas', 3),
  ('p18', 1, 'Reciclagem NR-11', 'tecnica', 100, NULL, NULL, NULL, 3),
  ('p18', 2, 'Treinamento prático de direção defensiva', 'saude_bem_estar', 100, NULL, NULL, NULL, 2),
  ('p19', 1, 'Concluir o curso de CEP (controle estatístico)', 'tecnica', 35, 0, 40, 'horas', 3),
  ('p19', 2, 'Aplicar o CEP em 2 características críticas', 'processos', 0, 0, 2, 'características', 2),
  ('p20', 1, 'Concluir o curso de metrologia básica', 'tecnica', 70, 0, 24, 'horas', 3),
  ('p20', 2, 'Ler desenho técnico sem apoio', 'tecnica', 50, 0, 100, '% das ordens', 2),
  ('p21', 1, 'Concluir o curso de soldagem básica', 'tecnica', 100, NULL, NULL, NULL, 3),
  ('p21', 2, 'Ser aprovado na avaliação prática', 'tecnica', 100, NULL, NULL, NULL, 3)
) AS v(pdi, idx, titulo, cat, prog, base, alvo, un, peso)
JOIN public.pdis p ON p.id = public.demo_id('pdi:' || v.pdi)
WHERE NOT EXISTS (SELECT 1 FROM public.pdi_metas m WHERE m.id = public.demo_id('pdimeta:' || v.pdi || ':' || v.idx));

-- Acoes: 2 por meta; o status acompanha o progresso da meta.
INSERT INTO public.pdi_acoes (
  id, tenant_id, meta_id, titulo, descricao, tipo, status, data_vencimento, frequencia, duracao_estimada,
  evidencia_obrigatoria, created_at, updated_at
)
SELECT public.demo_id('pdiacao:' || m.id::text || ':' || s.i), 'd3e00000-0000-4000-8000-000000000001', m.id,
       s.titulo, s.titulo || '.', s.tipo::public.pdi_acao_tipo,
       CASE WHEN m.progresso >= 100 THEN 'concluida'
            WHEN s.i = 1 AND m.progresso >= 50 THEN 'concluida'
            WHEN s.i = 1 AND m.progresso > 0 THEN 'em_andamento'
            WHEN s.i = 2 AND m.progresso >= 50 THEN 'em_andamento'
            WHEN m.progresso = 0 AND p.status = 'pausado' THEN 'bloqueada'
            ELSE 'nao_iniciada' END::public.pdi_acao_status,
       m.data_inicio + ((m.data_fim - m.data_inicio) * s.i / 3),
       CASE s.tipo WHEN 'habito' THEN 'diária' WHEN 'rotina' THEN 'semanal' ELSE NULL END,
       CASE s.tipo WHEN 'treinamento' THEN '16 horas' WHEN 'mentoria' THEN '8 horas' WHEN 'projeto' THEN '30 dias' ELSE '2 horas' END,
       s.tipo IN ('treinamento', 'projeto'), m.created_at, now() - interval '3 days'
FROM public.pdi_metas m
JOIN public.pdis p ON p.id = m.pdi_id
JOIN (VALUES
  ('p1', 1, 1, 'Cumprir as 80 horas de prática supervisionada', 'treinamento'), ('p1', 1, 2, 'Realizar a prova prática de qualificação', 'tarefa'),
  ('p1', 2, 1, 'Aplicar o checklist de inspeção em todas as juntas', 'habito'), ('p1', 2, 2, 'Analisar semanalmente os defeitos recorrentes com o líder', 'rotina'),
  ('p2', 1, 1, 'Preparar o roteiro padrão de DDS e metas do dia', 'tarefa'), ('p2', 1, 2, 'Registrar presença e pendências no quadro do turno', 'habito'),
  ('p2', 2, 1, 'Agendar os feedbacks quinzenais na agenda', 'tarefa'), ('p2', 2, 2, 'Participar da trilha Liderança na Prática', 'treinamento'),
  ('p3', 1, 1, 'Concluir os 6 módulos da trilha', 'treinamento'), ('p3', 1, 2, 'Aplicar o plano de ação no turno', 'projeto'),
  ('p3', 2, 1, 'Acompanhar o líder atual por 30 dias', 'mentoria'), ('p3', 2, 2, 'Assumir a escala e os indicadores do turno', 'projeto'),
  ('p4', 1, 1, 'Especificar e comprar os sensores', 'tarefa'), ('p4', 1, 2, 'Instalar e calibrar nas CNC 1 a 5', 'projeto'),
  ('p4', 2, 1, 'Contratar o treinamento de análise de vibração', 'treinamento'), ('p4', 2, 2, 'Mentoria com especialista externo', 'mentoria'),
  ('p5', 1, 1, 'Implantar a contagem cíclica semanal', 'rotina'), ('p5', 1, 2, 'Treinar o time na conferência cega', 'treinamento'),
  ('p5', 2, 1, 'Definir os 4 indicadores com a diretoria', 'tarefa'), ('p5', 2, 2, 'Construir o painel semanal', 'projeto'),
  ('p6', 1, 1, 'Fazer os módulos de segurança (NR-12)', 'treinamento'), ('p6', 1, 2, 'Assinar o manual da função', 'tarefa'),
  ('p6', 2, 1, 'Acompanhar operador sênior por 15 dias', 'mentoria'), ('p6', 2, 2, 'Operar sozinho a ordem padrão com supervisão', 'tarefa'),
  ('p7', 1, 1, 'Fazer os módulos de segurança (NR-12)', 'treinamento'), ('p7', 1, 2, 'Assinar o manual da função', 'tarefa'),
  ('p7', 2, 1, 'Acompanhar operador sênior por 15 dias', 'mentoria'), ('p7', 2, 2, 'Operar sozinho a ordem padrão com supervisão', 'tarefa'),
  ('p8', 1, 1, 'Cursar os módulos de hidráulica', 'treinamento'), ('p8', 1, 2, 'Resolver 2 casos reais com acompanhamento', 'tarefa'),
  ('p8', 2, 1, 'Registrar os diagnósticos no relatório de manutenção', 'habito'), ('p8', 2, 2, 'Apresentar um caso para a equipe', 'tarefa'),
  ('p9', 1, 1, 'Cursar as 40 horas do curso', 'treinamento'), ('p9', 1, 2, 'Entregar o certificado ao RH', 'tarefa'),
  ('p9', 2, 1, 'Cursar o módulo SEP', 'treinamento'), ('p9', 2, 2, 'Entregar o certificado ao RH', 'tarefa'),
  ('p10', 1, 1, 'Cursar os módulos de tabelas dinâmicas e macros', 'treinamento'), ('p10', 1, 2, 'Aplicar em um relatório real', 'tarefa'),
  ('p10', 2, 1, 'Mapear as rotinas do fechamento', 'tarefa'), ('p10', 2, 2, 'Automatizar as 5 rotinas priorizadas', 'projeto'),
  ('p11', 1, 1, 'Cursar a formação de auditor interno', 'treinamento'), ('p11', 1, 2, 'Realizar a prova de certificação', 'tarefa'),
  ('p11', 2, 1, 'Acompanhar 2 auditorias como observador', 'mentoria'), ('p11', 2, 2, 'Conduzir 3 auditorias com supervisão', 'projeto'),
  ('p12', 1, 1, 'Visita guiada ao departamento pessoal', 'tarefa'), ('p12', 1, 2, 'Reunião de apresentação do SST', 'tarefa'),
  ('p14', 1, 1, 'Cursar os módulos de leitura de desenho', 'treinamento'), ('p14', 1, 2, 'Resolver exercícios com desenhos reais', 'tarefa'),
  ('p14', 2, 1, 'Praticar com os desenhos das ordens da semana', 'rotina'), ('p14', 2, 2, 'Validar a interpretação com o líder', 'mentoria'),
  ('p15', 1, 1, 'Cursar a reciclagem NR-11', 'treinamento'), ('p15', 1, 2, 'Treinamento prático de direção defensiva', 'treinamento'),
  ('p15', 2, 1, 'Aplicar o checklist diário da empilhadeira', 'habito'), ('p15', 2, 2, 'Participar do DDS semanal', 'rotina'),
  ('p16', 1, 1, 'Cursar os módulos de G-code', 'treinamento'), ('p16', 1, 2, 'Simular programas no software da máquina', 'tarefa'),
  ('p16', 2, 1, 'Programar a primeira peça com supervisão', 'projeto'), ('p16', 2, 2, 'Programar 4 peças sem apoio', 'projeto'),
  ('p17', 1, 1, 'Mapear os requisitos da qualificação', 'tarefa'), ('p17', 1, 2, 'Agendar as horas práticas', 'tarefa'),
  ('p18', 1, 1, 'Cursar a reciclagem NR-11', 'treinamento'), ('p18', 1, 2, 'Entregar o certificado ao RH', 'tarefa'),
  ('p18', 2, 1, 'Treinamento prático', 'treinamento'), ('p18', 2, 2, 'Avaliação prática com o coordenador', 'tarefa'),
  ('p19', 1, 1, 'Cursar os módulos de estatística', 'treinamento'), ('p19', 1, 2, 'Resolver exercícios com dados da fábrica', 'tarefa'),
  ('p19', 2, 1, 'Escolher as 2 características críticas', 'tarefa'), ('p19', 2, 2, 'Implantar as cartas de controle', 'projeto'),
  ('p20', 1, 1, 'Cursar o módulo de instrumentos de medição', 'treinamento'), ('p20', 1, 2, 'Calibrar paquímetro e micrômetro com o líder', 'mentoria'),
  ('p20', 2, 1, 'Ler o desenho de cada ordem antes do setup', 'habito'), ('p20', 2, 2, 'Revisão semanal com o líder', 'rotina'),
  ('p21', 1, 1, 'Cursar os módulos de soldagem básica', 'treinamento'), ('p21', 1, 2, 'Praticar no posto de treinamento', 'tarefa'),
  ('p21', 2, 1, 'Agendar a avaliação prática', 'tarefa'), ('p21', 2, 2, 'Realizar a avaliação com o instrutor', 'tarefa')
) AS s(pdi, midx, i, titulo, tipo) ON public.demo_id('pdi:' || s.pdi) = m.pdi_id AND m.id = public.demo_id('pdimeta:' || s.pdi || ':' || s.midx)
WHERE m.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
  AND NOT EXISTS (SELECT 1 FROM public.pdi_acoes x WHERE x.id = public.demo_id('pdiacao:' || m.id::text || ':' || s.i));

-- Check-ins (2 por meta com andamento) com valor atualizado quando a meta tem alvo.
INSERT INTO public.pdi_checkins (
  id, tenant_id, meta_id, avancos, bloqueios, proximo_passo, valor_atualizado, realizado_por_nome, created_at
)
SELECT public.demo_id('pdichk:' || m.id::text || ':' || s.i), 'd3e00000-0000-4000-8000-000000000001', m.id,
       (ARRAY['Avanço conforme o planejado; equipe apoiou nas atividades práticas.',
              'Concluída mais uma etapa e registrada a evidência no sistema.',
              'Boa evolução na prática; dúvidas esclarecidas com o líder.',
              'Retomada após semana de pico de produção; ritmo normalizado.'])[1 + public.demo_dev_rnd(m.id::text || s.i, 4)],
       CASE WHEN s.i = 1 AND public.demo_dev_rnd(m.id::text || 'blq', 4) = 0 THEN 'Dificuldade de conciliar horário do curso com o turno.' END,
       (ARRAY['Agendar a próxima etapa com o líder.',
              'Reservar 2 horas semanais para estudo.',
              'Enviar a evidência para validação.',
              'Revisar o plano no próximo check-in.'])[1 + public.demo_dev_rnd(m.id::text || 'pp' || s.i, 4)],
       CASE WHEN m.valor_alvo IS NOT NULL
            THEN round((m.valor_base + (m.valor_alvo - m.valor_base) * (m.progresso * s.f / 100.0))::numeric, 2) END,
       p.responsavel_nome, GREATEST(p.created_at, now() - s.dias * interval '1 day')
FROM public.pdi_metas m
JOIN public.pdis p ON p.id = m.pdi_id
CROSS JOIN (VALUES (1, 0.5, 30), (2, 1.0, 9)) AS s(i, f, dias)
WHERE m.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND m.progresso > 0
  AND NOT EXISTS (SELECT 1 FROM public.pdi_checkins c WHERE c.id = public.demo_id('pdichk:' || m.id::text || ':' || s.i));

-- Feedbacks do PDI (lider, autoavaliacao e par)
INSERT INTO public.pdi_feedbacks (
  id, tenant_id, pdi_id, meta_id, tipo, ponto_forte, ponto_melhorar, recomendacao, comentario, autor_nome, created_at
)
SELECT public.demo_id('pdifb:' || v.pdi || ':' || v.i), 'd3e00000-0000-4000-8000-000000000001', public.demo_id('pdi:' || v.pdi),
       public.demo_id('pdimeta:' || v.pdi || ':1'), v.tipo, v.forte, v.melhorar, v.recom, v.coment, v.autor, now() - v.dias * interval '1 day'
FROM (VALUES
  ('p1', 1, 'lider', 'Dedicação e capricho na solda; boa evolução técnica.', 'Registrar melhor os parâmetros de solda no relatório.', 'Manter as horas práticas semanais.', 'Está no caminho para a qualificação N2.', 'Márcio Rezende Matos', 20),
  ('p1', 2, 'autoavaliacao', 'Sinto mais segurança nas juntas de ângulo.', 'Preciso treinar mais a posição vertical.', 'Pedir mais horas de bancada.', NULL, 'Colaborador', 12),
  ('p2', 1, 'lider', 'Boa condução das reuniões de turno.', 'Dar feedback individual com mais frequência.', 'Agendar os feedbacks na agenda fixa.', NULL, 'Direção Industrial', 25),
  ('p4', 1, 'lider', 'Visão técnica forte para manutenção preditiva.', 'Delegar mais a instalação aos técnicos.', 'Priorizar a formação da equipe.', NULL, 'Direção Industrial', 15),
  ('p6', 1, 'lider', 'Rápida adaptação e atenção às regras de segurança.', 'Ganhar autonomia nos setups.', 'Continuar o acompanhamento com o operador sênior.', NULL, 'Márcio Rezende Matos', 10),
  ('p10', 1, 'lider', 'Excelente domínio das planilhas após o curso.', 'Documentar as macros criadas.', 'Compartilhar a técnica com o time.', NULL, 'Gerência Administrativa', 14),
  ('p15', 1, 'par', 'Cuidadoso na movimentação e sempre sinaliza o pátio.', 'Comunicar antes de manobras em área de pedestres.', 'Fazer o checklist junto com o colega do turno.', NULL, 'Colega de turno', 18),
  ('p16', 1, 'lider', 'Aprende rápido com prática; cria bons programas.', 'Documentar os programas criados.', 'Seguir para peças de maior complexidade.', NULL, 'Márcio Rezende Matos', 8),
  ('p20', 1, 'autoavaliacao', 'Estou conseguindo ler os desenhos mais simples.', 'Tolerâncias geométricas ainda são difíceis.', 'Revisar semanalmente com o líder.', NULL, 'Colaborador', 6)
) AS v(pdi, i, tipo, forte, melhorar, recom, coment, autor, dias)
WHERE EXISTS (SELECT 1 FROM public.pdis p WHERE p.id = public.demo_id('pdi:' || v.pdi))
  AND NOT EXISTS (SELECT 1 FROM public.pdi_feedbacks f WHERE f.id = public.demo_id('pdifb:' || v.pdi || ':' || v.i));

-- Links de assinatura do documento do PDI (caminhos fictícios; nenhum arquivo real)
INSERT INTO public.pdi_assinatura_links (
  id, tenant_id, pdi_id, token, signatario_nome, signatario_papel, status, documento_storage_path, assinado_em,
  expira_em, criado_por_nome, created_at, updated_at
)
SELECT public.demo_id('pdiass:' || v.pdi || ':' || v.papel), 'd3e00000-0000-4000-8000-000000000001', p.id,
       md5('demo-pdi-ass:' || v.pdi || ':' || v.papel) || md5('demo-pdi-ass2:' || v.pdi || ':' || v.papel),
       CASE v.papel WHEN 'colab' THEN p.colaborador_nome ELSE COALESCE(p.responsavel_nome, 'Líder') END,
       CASE v.papel WHEN 'colab' THEN 'Colaborador(a)' ELSE 'Líder/Responsável' END,
       v.status, 'demo/pdi/' || v.pdi || '.html',
       CASE WHEN v.status = 'assinado' THEN now() - v.dias * interval '1 day' END,
       now() - v.dias * interval '1 day' + interval '30 days', 'Leiri', now() - (v.dias + 1) * interval '1 day', now() - v.dias * interval '1 day'
FROM (VALUES
  ('p3', 'colab', 'assinado', 290), ('p3', 'lider', 'assinado', 289),
  ('p9', 'colab', 'assinado', 195), ('p9', 'lider', 'assinado', 194),
  ('p11', 'colab', 'assinado', 250), ('p11', 'lider', 'assinado', 249),
  ('p18', 'colab', 'assinado', 148), ('p18', 'lider', 'assinado', 147),
  ('p21', 'colab', 'assinado', 270), ('p21', 'lider', 'assinado', 270),
  ('p1', 'colab', 'pendente', 6), ('p1', 'lider', 'assinado', 6),
  ('p2', 'colab', 'assinado', 40), ('p2', 'lider', 'assinado', 40),
  ('p4', 'colab', 'pendente', 3), ('p4', 'lider', 'pendente', 3)
) AS v(pdi, papel, status, dias)
JOIN public.pdis p ON p.id = public.demo_id('pdi:' || v.pdi)
WHERE NOT EXISTS (SELECT 1 FROM public.pdi_assinatura_links l WHERE l.id = public.demo_id('pdiass:' || v.pdi || ':' || v.papel));

-- O gatilho de progresso recalcula status/progresso do PDI a partir das metas e
-- devolve "pausado"/"cancelado" para "ativo": restabelece o status desejado.
UPDATE public.pdis p
   SET status = x.st::public.pdi_status
  FROM (VALUES ('p14', 'pausado'), ('p17', 'cancelado')) AS x(k, st)
 WHERE p.id = public.demo_id('pdi:' || x.k)
   AND p.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
   AND p.status::text <> x.st;

-- Acoes do Plano de Acao ligadas a metas de PDI (a meta mostra o vinculo pelo texto
-- "Meta: <titulo>"). Uma por vez, porque o codigo ACO-xxxxx e gerado por gatilho.
DO $acoes$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT v.chave, v.titulo, v.meta, v.prog, v.status, v.prazo_dias, v.tipo
    FROM (VALUES
      ('1', 'Contratar curso de leitura de desenho técnico', 'Concluir o curso de leitura de desenho técnico', 30, 'em_andamento', 25, 'melhoria'),
      ('2', 'Liberar a agenda do turno B para treinamento', 'Concluir o curso de leitura de desenho técnico', 0, 'pendente', 12, 'corretiva'),
      ('3', 'Comprar sensores de vibração para as CNC', 'Instalar sensores de vibração em 5 máquinas CNC', 60, 'em_andamento', 40, 'preventiva'),
      ('4', 'Agendar a contagem cíclica semanal no ERP', 'Reduzir a divergência de inventário para 0,5%', 100, 'concluida', -15, 'melhoria')
    ) AS v(chave, titulo, meta, prog, status, prazo_dias, tipo)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM public.plano_acoes WHERE id = public.demo_id('pdiplano:' || r.chave)) THEN
      INSERT INTO public.plano_acoes (
        id, tenant_id, empresa_id, titulo, descricao, porque, prazo, responsavel_id, responsavel_nome, como,
        origem_modulo, origem_descricao, gravidade, urgencia, tendencia, status, progresso,
        data_inicio, data_conclusao, exige_evidencia, tipo, criado_por_nome, created_at, updated_at, codigo
      ) VALUES (
        public.demo_id('pdiplano:' || r.chave), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
        r.titulo, r.titulo || ', necessário para o avanço da meta do PDI.', 'Garantir o cumprimento da meta de desenvolvimento do colaborador.',
        CURRENT_DATE + r.prazo_dias,
        (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' LIMIT 1), 'Leiri',
        'Tratar com o líder do setor e o RH, registrando a evidência no PDI.',
        'pdi', 'PDI — Meta: ' || r.meta, 3, 3, 3,
        r.status::public.acao_status, r.prog, CURRENT_DATE - 30,
        CASE WHEN r.status = 'concluida' THEN CURRENT_DATE - 15 END, false, r.tipo, 'Leiri', now() - interval '30 days', now() - interval '2 days', ''
      );
    END IF;
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Acoes do Plano de Acao ligadas ao PDI nao semeadas: % (%)', SQLERRM, SQLSTATE;
END $acoes$;

-- ===========================================================================
-- MAPA COMPORTAMENTAL
-- ===========================================================================

-- (M1) Politica de uso publicada (exigida para ativar campanhas)
INSERT INTO public.mapa_comportamental_politicas (
  id, tenant_id, versao, titulo, texto_politica, texto_aviso, publicada, publicada_em, publicada_por_nome, created_at, updated_at
)
SELECT public.demo_id('mapapol:1'), 'd3e00000-0000-4000-8000-000000000001', 1,
       'Política de Uso — Mapa Comportamental',
       'O Mapa Comportamental é um instrumento de autoconhecimento e apoio ao desenvolvimento. Ele descreve preferências de trabalho e NÃO é usado para classificar, promover, punir ou desligar pessoas. O resultado interpretado fica visível ao próprio colaborador e a quem tem permissão do módulo; as respostas item a item não são exibidas a terceiros. Os dados são tratados conforme a LGPD, com base no legítimo interesse da empresa para desenvolvimento de pessoas, e o colaborador pode contestar o resultado e solicitar nova aplicação a qualquer momento.',
       'Este questionário leva cerca de 10 minutos. Não há respostas certas ou erradas. O resultado mostra tendências de comportamento no trabalho, serve para conversas de desenvolvimento e não é usado para decisões de contratação, promoção ou desligamento. Você poderá contestar o resultado.',
       true, now() - interval '160 days', 'Leiri', now() - interval '161 days', now() - interval '160 days'
WHERE NOT EXISTS (SELECT 1 FROM public.mapa_comportamental_politicas p WHERE p.id = public.demo_id('mapapol:1'));

-- (M2) Campanhas: uma encerrada, uma ativa e um rascunho
INSERT INTO public.mapa_comportamental_campanhas (
  id, tenant_id, empresa_id, nome, descricao, publico, status, data_inicio, data_fim, instrumento_versao,
  politica_id, criado_por_nome, created_at, updated_at
)
SELECT public.demo_id('mapacamp:' || v.chave), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       v.nome, v.descr, v.publico::jsonb, v.status, CURRENT_DATE + v.ini, CURRENT_DATE + v.fim, 1,
       public.demo_id('mapapol:1'), 'Leiri', now() + (v.ini - 5) * interval '1 day', now()
FROM (VALUES
  ('c1', 'Mapeamento Geral 2026', 'Primeira rodada de mapeamento comportamental com toda a empresa.', '{"tipo":"empresa_inteira"}', 'encerrada', -150, -90),
  ('c2', 'Mapeamento de Liderança e Gestão', 'Líderes, supervisores e analistas: base para o programa de desenvolvimento de lideranças.', '{"tipo":"empresa_inteira"}', 'ativa', -20, 25),
  ('c3', 'Integração dos Novos Contratados', 'Aplicação automática para quem acabou de ser admitido (a ativar no próximo ciclo).', '{"tipo":"empresa_inteira"}', 'rascunho', 30, 60)
) AS v(chave, nome, descr, publico, status, ini, fim)
WHERE EXISTS (SELECT 1 FROM public.mapa_comportamental_politicas WHERE id = public.demo_id('mapapol:1'))
  AND NOT EXISTS (SELECT 1 FROM public.mapa_comportamental_campanhas c WHERE c.id = public.demo_id('mapacamp:' || v.chave));

-- (M3) Mapas concluidos dos colaboradores (resultado calculado com o algoritmo do app;
--      as respostas item a item nao sao gravadas para os colaboradores)
DO $mapa1$
BEGIN
INSERT INTO public.mapa_comportamental_respostas (
  id, tenant_id, empresa_id, colaborador_nome, colaborador_cpf, campanha_id, instrumento_versao, algoritmo_versao, status,
  respostas, resultado, arquetipo, indice_consistencia, confiabilidade, aviso_versao, aviso_aceite_em,
  tempo_total_segundos, concluido_em, vence_em, created_at, updated_at, origem
)
SELECT public.demo_id('mapa:' || v.n), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       a.nome_completo, public.demo_cpf(v.n), public.demo_id('mapacamp:' || v.camp), 1, 'v1', 'concluido',
       '{}'::jsonb, v.res::jsonb, v.arq, v.idx, v.conf, 'v1', now() - v.dias * interval '1 day' - interval '3 hours',
       v.tempo, now() - v.dias * interval '1 day', (CURRENT_DATE - v.dias + 730), now() - v.dias * interval '1 day' - interval '3 hours',
       now() - v.dias * interval '1 day', 'app'
FROM (VALUES
  (1, 'estrategista', 'alta', 0, 337, 'c1', 108, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["estrategista"],"arquetipoMisto":false,"foco":{"pontosA":0,"pontosB":10,"intensidade":10,"ladoPredominante":"B","misto":false},"ritmo":{"pontosA":0,"pontosB":11,"intensidade":11,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":0,"relacional":1,"pragmatico":5},"predominantes":["pragmatico"]},"modo":{"pontosA":7,"pontosB":1,"resultado":"constante","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Estrategista-Pragmático, Modo Constante"}'),
  (2, 'guardiao', 'alta', 0, 374, 'c1', 121, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["guardiao"],"arquetipoMisto":false,"foco":{"pontosA":11,"pontosB":0,"intensidade":11,"ladoPredominante":"A","misto":false},"ritmo":{"pontosA":0,"pontosB":10,"intensidade":10,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":1,"relacional":1,"pragmatico":4},"predominantes":["pragmatico"]},"modo":{"pontosA":8,"pontosB":0,"resultado":"constante","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Guardião-Pragmático, Modo Constante"}'),
  (3, 'pioneiro', 'alta', 0, 411, 'c1', 134, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["pioneiro"],"arquetipoMisto":false,"foco":{"pontosA":3,"pontosB":6,"intensidade":3,"ladoPredominante":"B","misto":false},"ritmo":{"pontosA":7,"pontosB":0,"intensidade":7,"ladoPredominante":"A","misto":false},"motor":{"contagem":{"racional":1,"relacional":0,"pragmatico":5},"predominantes":["pragmatico"]},"modo":{"pontosA":2,"pontosB":6,"resultado":"cadenciado","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Pioneiro-Pragmático, Modo Cadenciado"}'),
  (4, 'guardiao-estrategista', 'alta', 0, 448, 'c1', 102, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["guardiao","estrategista"],"arquetipoMisto":true,"foco":{"pontosA":5,"pontosB":4,"intensidade":1,"ladoPredominante":null,"misto":true},"ritmo":{"pontosA":0,"pontosB":10,"intensidade":10,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":0,"relacional":1,"pragmatico":5},"predominantes":["pragmatico"]},"modo":{"pontosA":8,"pontosB":3,"resultado":"constante","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Guardião-Estrategista-Pragmático, Modo Constante"}'),
  (6, 'estrategista', 'alta', 0, 522, 'c1', 128, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["estrategista"],"arquetipoMisto":false,"foco":{"pontosA":0,"pontosB":8,"intensidade":8,"ladoPredominante":"B","misto":false},"ritmo":{"pontosA":2,"pontosB":7,"intensidade":5,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":1,"relacional":0,"pragmatico":5},"predominantes":["pragmatico"]},"modo":{"pontosA":0,"pontosB":9,"resultado":"cadenciado","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Estrategista-Pragmático, Modo Cadenciado"}'),
  (8, 'pioneiro', 'alta', 0, 596, 'c1', 109, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["pioneiro"],"arquetipoMisto":false,"foco":{"pontosA":2,"pontosB":6,"intensidade":4,"ladoPredominante":"B","misto":false},"ritmo":{"pontosA":8,"pontosB":4,"intensidade":4,"ladoPredominante":"A","misto":false},"motor":{"contagem":{"racional":5,"relacional":0,"pragmatico":1},"predominantes":["racional"]},"modo":{"pontosA":8,"pontosB":2,"resultado":"constante","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Pioneiro-Racional, Modo Constante"}'),
  (9, 'guardiao-estrategista', 'alta', 0, 633, 'c1', 122, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["guardiao","estrategista"],"arquetipoMisto":true,"foco":{"pontosA":5,"pontosB":3,"intensidade":2,"ladoPredominante":null,"misto":true},"ritmo":{"pontosA":2,"pontosB":7,"intensidade":5,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":4,"relacional":1,"pragmatico":1},"predominantes":["racional"]},"modo":{"pontosA":5,"pontosB":5,"resultado":"misto","misto":true},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Guardião-Estrategista-Racional, Modo Misto"}'),
  (10, 'estrategista', 'alta', 0, 670, 'c1', 135, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["estrategista"],"arquetipoMisto":false,"foco":{"pontosA":3,"pontosB":7,"intensidade":4,"ladoPredominante":"B","misto":false},"ritmo":{"pontosA":2,"pontosB":7,"intensidade":5,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":1,"relacional":1,"pragmatico":4},"predominantes":["pragmatico"]},"modo":{"pontosA":4,"pontosB":8,"resultado":"cadenciado","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Estrategista-Pragmático, Modo Cadenciado"}'),
  (11, 'pioneiro', 'baixa', 2, 707, 'c1', 103, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["pioneiro"],"arquetipoMisto":false,"foco":{"pontosA":2,"pontosB":7,"intensidade":5,"ladoPredominante":"B","misto":false},"ritmo":{"pontosA":9,"pontosB":0,"intensidade":9,"ladoPredominante":"A","misto":false},"motor":{"contagem":{"racional":5,"relacional":1,"pragmatico":0},"predominantes":["racional"]},"modo":{"pontosA":8,"pontosB":2,"resultado":"constante","misto":false},"indiceConsistencia":2,"confiabilidade":"baixa","motivoBaixaConfiabilidade":["Respostas de controle divergentes."],"assinatura":"Pioneiro-Racional, Modo Constante"}'),
  (12, 'guardiao', 'alta', 0, 744, 'c1', 116, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["guardiao"],"arquetipoMisto":false,"foco":{"pontosA":9,"pontosB":2,"intensidade":7,"ladoPredominante":"A","misto":false},"ritmo":{"pontosA":2,"pontosB":6,"intensidade":4,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":6,"relacional":0,"pragmatico":0},"predominantes":["racional"]},"modo":{"pontosA":4,"pontosB":4,"resultado":"misto","misto":true},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Guardião-Racional, Modo Misto"}'),
  (13, 'estrategista', 'alta', 0, 781, 'c2', 15, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["estrategista"],"arquetipoMisto":false,"foco":{"pontosA":1,"pontosB":6,"intensidade":5,"ladoPredominante":"B","misto":false},"ritmo":{"pontosA":0,"pontosB":9,"intensidade":9,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":3,"relacional":0,"pragmatico":3},"predominantes":["racional","pragmatico"]},"modo":{"pontosA":7,"pontosB":0,"resultado":"constante","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Estrategista-Racional-Pragmático, Modo Constante"}'),
  (15, 'guardiao', 'alta', 0, 335, 'c1', 110, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["guardiao"],"arquetipoMisto":false,"foco":{"pontosA":10,"pontosB":0,"intensidade":10,"ladoPredominante":"A","misto":false},"ritmo":{"pontosA":0,"pontosB":12,"intensidade":12,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":2,"relacional":0,"pragmatico":4},"predominantes":["pragmatico"]},"modo":{"pontosA":8,"pontosB":1,"resultado":"constante","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Guardião-Pragmático, Modo Constante"}'),
  (17, 'conector', 'alta', 0, 409, 'c1', 136, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["conector"],"arquetipoMisto":false,"foco":{"pontosA":6,"pontosB":3,"intensidade":3,"ladoPredominante":"A","misto":false},"ritmo":{"pontosA":8,"pontosB":0,"intensidade":8,"ladoPredominante":"A","misto":false},"motor":{"contagem":{"racional":6,"relacional":0,"pragmatico":0},"predominantes":["racional"]},"modo":{"pontosA":0,"pontosB":12,"resultado":"cadenciado","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Conector-Racional, Modo Cadenciado"}'),
  (18, 'estrategista-guardiao', 'alta', 0, 446, 'c1', 104, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["estrategista","guardiao"],"arquetipoMisto":true,"foco":{"pontosA":4,"pontosB":5,"intensidade":1,"ladoPredominante":null,"misto":true},"ritmo":{"pontosA":0,"pontosB":9,"intensidade":9,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":2,"relacional":0,"pragmatico":4},"predominantes":["pragmatico"]},"modo":{"pontosA":4,"pontosB":6,"resultado":"misto","misto":true},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Estrategista-Guardião-Pragmático, Modo Misto"}'),
  (19, 'pioneiro', 'baixa', 0, 48, 'c1', 117, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["pioneiro"],"arquetipoMisto":false,"foco":{"pontosA":1,"pontosB":9,"intensidade":8,"ladoPredominante":"B","misto":false},"ritmo":{"pontosA":11,"pontosB":0,"intensidade":11,"ladoPredominante":"A","misto":false},"motor":{"contagem":{"racional":3,"relacional":1,"pragmatico":2},"predominantes":["racional"]},"modo":{"pontosA":0,"pontosB":9,"resultado":"cadenciado","misto":false},"indiceConsistencia":0,"confiabilidade":"baixa","motivoBaixaConfiabilidade":["Tempo de resposta abaixo do mínimo."],"assinatura":"Pioneiro-Racional, Modo Cadenciado"}'),
  (20, 'guardiao', 'alta', 0, 520, 'c1', 130, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["guardiao"],"arquetipoMisto":false,"foco":{"pontosA":11,"pontosB":0,"intensidade":11,"ladoPredominante":"A","misto":false},"ritmo":{"pontosA":0,"pontosB":11,"intensidade":11,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":4,"relacional":0,"pragmatico":2},"predominantes":["racional"]},"modo":{"pontosA":4,"pontosB":6,"resultado":"misto","misto":true},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Guardião-Racional, Modo Misto"}'),
  (22, 'conector', 'alta', 0, 594, 'c1', 111, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["conector"],"arquetipoMisto":false,"foco":{"pontosA":6,"pontosB":1,"intensidade":5,"ladoPredominante":"A","misto":false},"ritmo":{"pontosA":11,"pontosB":0,"intensidade":11,"ladoPredominante":"A","misto":false},"motor":{"contagem":{"racional":1,"relacional":4,"pragmatico":1},"predominantes":["relacional"]},"modo":{"pontosA":9,"pontosB":0,"resultado":"constante","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Conector-Relacional, Modo Constante"}'),
  (23, 'estrategista', 'alta', 0, 631, 'c1', 124, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["estrategista"],"arquetipoMisto":false,"foco":{"pontosA":2,"pontosB":8,"intensidade":6,"ladoPredominante":"B","misto":false},"ritmo":{"pontosA":0,"pontosB":9,"intensidade":9,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":4,"relacional":1,"pragmatico":1},"predominantes":["racional"]},"modo":{"pontosA":9,"pontosB":2,"resultado":"constante","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Estrategista-Racional, Modo Constante"}'),
  (24, 'pioneiro-conector-estrategista', 'alta', 0, 668, 'c1', 137, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["pioneiro","conector","estrategista"],"arquetipoMisto":true,"foco":{"pontosA":3,"pontosB":5,"intensidade":2,"ladoPredominante":null,"misto":true},"ritmo":{"pontosA":5,"pontosB":4,"intensidade":1,"ladoPredominante":null,"misto":true},"motor":{"contagem":{"racional":1,"relacional":0,"pragmatico":5},"predominantes":["pragmatico"]},"modo":{"pontosA":1,"pontosB":9,"resultado":"cadenciado","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Pioneiro-Conector-Estrategista-Pragmático, Modo Cadenciado"}'),
  (25, 'estrategista', 'alta', 0, 705, 'c1', 105, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["estrategista"],"arquetipoMisto":false,"foco":{"pontosA":0,"pontosB":6,"intensidade":6,"ladoPredominante":"B","misto":false},"ritmo":{"pontosA":1,"pontosB":8,"intensidade":7,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":0,"relacional":1,"pragmatico":5},"predominantes":["pragmatico"]},"modo":{"pontosA":3,"pontosB":5,"resultado":"misto","misto":true},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Estrategista-Pragmático, Modo Misto"}'),
  (26, 'estrategista', 'alta', 0, 742, 'c1', 118, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["estrategista"],"arquetipoMisto":false,"foco":{"pontosA":2,"pontosB":5,"intensidade":3,"ladoPredominante":"B","misto":false},"ritmo":{"pontosA":2,"pontosB":6,"intensidade":4,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":1,"relacional":1,"pragmatico":4},"predominantes":["pragmatico"]},"modo":{"pontosA":2,"pontosB":10,"resultado":"cadenciado","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Estrategista-Pragmático, Modo Cadenciado"}'),
  (28, 'pioneiro', 'alta', 0, 816, 'c2', 5, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["pioneiro"],"arquetipoMisto":false,"foco":{"pontosA":2,"pontosB":8,"intensidade":6,"ladoPredominante":"B","misto":false},"ritmo":{"pontosA":8,"pontosB":2,"intensidade":6,"ladoPredominante":"A","misto":false},"motor":{"contagem":{"racional":0,"relacional":1,"pragmatico":5},"predominantes":["pragmatico"]},"modo":{"pontosA":0,"pontosB":10,"resultado":"cadenciado","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Pioneiro-Pragmático, Modo Cadenciado"}'),
  (29, 'conector', 'alta', 0, 333, 'c2', 10, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["conector"],"arquetipoMisto":false,"foco":{"pontosA":8,"pontosB":1,"intensidade":7,"ladoPredominante":"A","misto":false},"ritmo":{"pontosA":9,"pontosB":0,"intensidade":9,"ladoPredominante":"A","misto":false},"motor":{"contagem":{"racional":0,"relacional":6,"pragmatico":0},"predominantes":["relacional"]},"modo":{"pontosA":8,"pontosB":1,"resultado":"constante","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Conector-Relacional, Modo Constante"}'),
  (30, 'pioneiro', 'alta', 0, 370, 'c2', 15, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["pioneiro"],"arquetipoMisto":false,"foco":{"pontosA":0,"pontosB":8,"intensidade":8,"ladoPredominante":"B","misto":false},"ritmo":{"pontosA":9,"pontosB":0,"intensidade":9,"ladoPredominante":"A","misto":false},"motor":{"contagem":{"racional":4,"relacional":1,"pragmatico":1},"predominantes":["racional"]},"modo":{"pontosA":1,"pontosB":9,"resultado":"cadenciado","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Pioneiro-Racional, Modo Cadenciado"}'),
  (31, 'estrategista', 'alta', 0, 407, 'c1', 138, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["estrategista"],"arquetipoMisto":false,"foco":{"pontosA":1,"pontosB":8,"intensidade":7,"ladoPredominante":"B","misto":false},"ritmo":{"pontosA":0,"pontosB":9,"intensidade":9,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":0,"relacional":4,"pragmatico":2},"predominantes":["relacional"]},"modo":{"pontosA":0,"pontosB":9,"resultado":"cadenciado","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Estrategista-Relacional, Modo Cadenciado"}'),
  (32, 'estrategista', 'alta', 0, 444, 'c1', 106, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["estrategista"],"arquetipoMisto":false,"foco":{"pontosA":2,"pontosB":8,"intensidade":6,"ladoPredominante":"B","misto":false},"ritmo":{"pontosA":1,"pontosB":6,"intensidade":5,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":6,"relacional":0,"pragmatico":0},"predominantes":["racional"]},"modo":{"pontosA":5,"pontosB":5,"resultado":"misto","misto":true},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Estrategista-Racional, Modo Misto"}'),
  (33, 'guardiao-estrategista', 'baixa', 2, 481, 'c1', 119, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["guardiao","estrategista"],"arquetipoMisto":true,"foco":{"pontosA":5,"pontosB":3,"intensidade":2,"ladoPredominante":null,"misto":true},"ritmo":{"pontosA":2,"pontosB":7,"intensidade":5,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":5,"relacional":1,"pragmatico":0},"predominantes":["racional"]},"modo":{"pontosA":5,"pontosB":4,"resultado":"misto","misto":true},"indiceConsistencia":2,"confiabilidade":"baixa","motivoBaixaConfiabilidade":["Respostas de controle divergentes."],"assinatura":"Guardião-Estrategista-Racional, Modo Misto"}'),
  (34, 'guardiao', 'alta', 0, 518, 'c1', 132, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["guardiao"],"arquetipoMisto":false,"foco":{"pontosA":8,"pontosB":2,"intensidade":6,"ladoPredominante":"A","misto":false},"ritmo":{"pontosA":1,"pontosB":8,"intensidade":7,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":6,"relacional":0,"pragmatico":0},"predominantes":["racional"]},"modo":{"pontosA":7,"pontosB":3,"resultado":"constante","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Guardião-Racional, Modo Constante"}'),
  (36, 'estrategista', 'alta', 0, 592, 'c2', 11, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["estrategista"],"arquetipoMisto":false,"foco":{"pontosA":0,"pontosB":9,"intensidade":9,"ladoPredominante":"B","misto":false},"ritmo":{"pontosA":3,"pontosB":7,"intensidade":4,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":4,"relacional":1,"pragmatico":1},"predominantes":["racional"]},"modo":{"pontosA":9,"pontosB":0,"resultado":"constante","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Estrategista-Racional, Modo Constante"}'),
  (37, 'estrategista', 'alta', 0, 629, 'c1', 126, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["estrategista"],"arquetipoMisto":false,"foco":{"pontosA":0,"pontosB":7,"intensidade":7,"ladoPredominante":"B","misto":false},"ritmo":{"pontosA":2,"pontosB":9,"intensidade":7,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":4,"relacional":1,"pragmatico":1},"predominantes":["racional"]},"modo":{"pontosA":11,"pontosB":0,"resultado":"constante","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Estrategista-Racional, Modo Constante"}'),
  (39, 'pioneiro', 'alta', 0, 703, 'c1', 107, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["pioneiro"],"arquetipoMisto":false,"foco":{"pontosA":1,"pontosB":9,"intensidade":8,"ladoPredominante":"B","misto":false},"ritmo":{"pontosA":8,"pontosB":0,"intensidade":8,"ladoPredominante":"A","misto":false},"motor":{"contagem":{"racional":5,"relacional":1,"pragmatico":0},"predominantes":["racional"]},"modo":{"pontosA":8,"pontosB":1,"resultado":"constante","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Pioneiro-Racional, Modo Constante"}'),
  (40, 'conector', 'alta', 0, 740, 'c2', 14, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["conector"],"arquetipoMisto":false,"foco":{"pontosA":7,"pontosB":0,"intensidade":7,"ladoPredominante":"A","misto":false},"ritmo":{"pontosA":7,"pontosB":1,"intensidade":6,"ladoPredominante":"A","misto":false},"motor":{"contagem":{"racional":0,"relacional":1,"pragmatico":5},"predominantes":["pragmatico"]},"modo":{"pontosA":1,"pontosB":7,"resultado":"cadenciado","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Conector-Pragmático, Modo Cadenciado"}'),
  (41, 'guardiao-estrategista', 'alta', 0, 777, 'c2', 2, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["guardiao","estrategista"],"arquetipoMisto":true,"foco":{"pontosA":5,"pontosB":4,"intensidade":1,"ladoPredominante":null,"misto":true},"ritmo":{"pontosA":0,"pontosB":9,"intensidade":9,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":1,"relacional":2,"pragmatico":3},"predominantes":["pragmatico"]},"modo":{"pontosA":2,"pontosB":7,"resultado":"cadenciado","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Guardião-Estrategista-Pragmático, Modo Cadenciado"}'),
  (43, 'guardiao', 'alta', 0, 331, 'c1', 114, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["guardiao"],"arquetipoMisto":false,"foco":{"pontosA":8,"pontosB":2,"intensidade":6,"ladoPredominante":"A","misto":false},"ritmo":{"pontosA":2,"pontosB":9,"intensidade":7,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":3,"relacional":2,"pragmatico":1},"predominantes":["racional"]},"modo":{"pontosA":4,"pontosB":7,"resultado":"cadenciado","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Guardião-Racional, Modo Cadenciado"}'),
  (44, 'guardiao', 'alta', 0, 368, 'c1', 127, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["guardiao"],"arquetipoMisto":false,"foco":{"pontosA":9,"pontosB":1,"intensidade":8,"ladoPredominante":"A","misto":false},"ritmo":{"pontosA":2,"pontosB":6,"intensidade":4,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":5,"relacional":0,"pragmatico":1},"predominantes":["racional"]},"modo":{"pontosA":1,"pontosB":8,"resultado":"cadenciado","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Guardião-Racional, Modo Cadenciado"}'),
  (45, 'estrategista', 'alta', 0, 405, 'c1', 95, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["estrategista"],"arquetipoMisto":false,"foco":{"pontosA":0,"pontosB":10,"intensidade":10,"ladoPredominante":"B","misto":false},"ritmo":{"pontosA":2,"pontosB":5,"intensidade":3,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":0,"relacional":2,"pragmatico":4},"predominantes":["pragmatico"]},"modo":{"pontosA":9,"pontosB":0,"resultado":"constante","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Estrategista-Pragmático, Modo Constante"}'),
  (46, 'estrategista', 'alta', 0, 442, 'c1', 108, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["estrategista"],"arquetipoMisto":false,"foco":{"pontosA":2,"pontosB":8,"intensidade":6,"ladoPredominante":"B","misto":false},"ritmo":{"pontosA":0,"pontosB":9,"intensidade":9,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":0,"relacional":0,"pragmatico":6},"predominantes":["pragmatico"]},"modo":{"pontosA":5,"pontosB":2,"resultado":"constante","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Estrategista-Pragmático, Modo Constante"}'),
  (47, 'estrategista', 'baixa', 2, 479, 'c1', 121, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["estrategista"],"arquetipoMisto":false,"foco":{"pontosA":3,"pontosB":6,"intensidade":3,"ladoPredominante":"B","misto":false},"ritmo":{"pontosA":1,"pontosB":8,"intensidade":7,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":1,"relacional":5,"pragmatico":0},"predominantes":["relacional"]},"modo":{"pontosA":3,"pontosB":7,"resultado":"cadenciado","misto":false},"indiceConsistencia":2,"confiabilidade":"baixa","motivoBaixaConfiabilidade":["Respostas de controle divergentes."],"assinatura":"Estrategista-Relacional, Modo Cadenciado"}'),
  (48, 'guardiao', 'alta', 0, 516, 'c1', 134, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["guardiao"],"arquetipoMisto":false,"foco":{"pontosA":10,"pontosB":1,"intensidade":9,"ladoPredominante":"A","misto":false},"ritmo":{"pontosA":1,"pontosB":7,"intensidade":6,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":1,"relacional":4,"pragmatico":1},"predominantes":["relacional"]},"modo":{"pontosA":4,"pontosB":8,"resultado":"cadenciado","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Guardião-Relacional, Modo Cadenciado"}'),
  (50, 'conector', 'alta', 0, 590, 'c1', 115, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["conector"],"arquetipoMisto":false,"foco":{"pontosA":7,"pontosB":2,"intensidade":5,"ladoPredominante":"A","misto":false},"ritmo":{"pontosA":10,"pontosB":1,"intensidade":9,"ladoPredominante":"A","misto":false},"motor":{"contagem":{"racional":1,"relacional":4,"pragmatico":1},"predominantes":["relacional"]},"modo":{"pontosA":2,"pontosB":6,"resultado":"cadenciado","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Conector-Relacional, Modo Cadenciado"}'),
  (51, 'conector-guardiao', 'alta', 0, 627, 'c1', 128, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["conector","guardiao"],"arquetipoMisto":true,"foco":{"pontosA":7,"pontosB":2,"intensidade":5,"ladoPredominante":"A","misto":false},"ritmo":{"pontosA":5,"pontosB":5,"intensidade":0,"ladoPredominante":null,"misto":true},"motor":{"contagem":{"racional":1,"relacional":1,"pragmatico":4},"predominantes":["pragmatico"]},"modo":{"pontosA":2,"pontosB":8,"resultado":"cadenciado","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Conector-Guardião-Pragmático, Modo Cadenciado"}'),
  (52, 'guardiao-estrategista', 'alta', 0, 664, 'c2', 6, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["guardiao","estrategista"],"arquetipoMisto":true,"foco":{"pontosA":4,"pontosB":3,"intensidade":1,"ladoPredominante":null,"misto":true},"ritmo":{"pontosA":2,"pontosB":9,"intensidade":7,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":4,"relacional":0,"pragmatico":2},"predominantes":["racional"]},"modo":{"pontosA":2,"pontosB":8,"resultado":"cadenciado","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Guardião-Estrategista-Racional, Modo Cadenciado"}'),
  (53, 'conector-guardiao', 'alta', 0, 701, 'c2', 11, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["conector","guardiao"],"arquetipoMisto":true,"foco":{"pontosA":6,"pontosB":3,"intensidade":3,"ladoPredominante":"A","misto":false},"ritmo":{"pontosA":6,"pontosB":4,"intensidade":2,"ladoPredominante":null,"misto":true},"motor":{"contagem":{"racional":4,"relacional":0,"pragmatico":2},"predominantes":["racional"]},"modo":{"pontosA":7,"pontosB":3,"resultado":"constante","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Conector-Guardião-Racional, Modo Constante"}'),
  (54, 'pioneiro-estrategista', 'alta', 0, 738, 'c1', 122, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["pioneiro","estrategista"],"arquetipoMisto":true,"foco":{"pontosA":2,"pontosB":7,"intensidade":5,"ladoPredominante":"B","misto":false},"ritmo":{"pontosA":6,"pontosB":4,"intensidade":2,"ladoPredominante":null,"misto":true},"motor":{"contagem":{"racional":2,"relacional":3,"pragmatico":1},"predominantes":["relacional"]},"modo":{"pontosA":7,"pontosB":2,"resultado":"constante","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Pioneiro-Estrategista-Relacional, Modo Constante"}'),
  (55, 'conector-pioneiro', 'alta', 0, 775, 'c2', 4, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["conector","pioneiro"],"arquetipoMisto":true,"foco":{"pontosA":6,"pontosB":6,"intensidade":0,"ladoPredominante":null,"misto":true},"ritmo":{"pontosA":9,"pontosB":0,"intensidade":9,"ladoPredominante":"A","misto":false},"motor":{"contagem":{"racional":2,"relacional":4,"pragmatico":0},"predominantes":["relacional"]},"modo":{"pontosA":1,"pontosB":9,"resultado":"cadenciado","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Conector-Pioneiro-Relacional, Modo Cadenciado"}'),
  (58, 'estrategista', 'alta', 0, 366, 'c2', 2, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["estrategista"],"arquetipoMisto":false,"foco":{"pontosA":0,"pontosB":10,"intensidade":10,"ladoPredominante":"B","misto":false},"ritmo":{"pontosA":4,"pontosB":7,"intensidade":3,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":3,"relacional":2,"pragmatico":1},"predominantes":["racional"]},"modo":{"pontosA":3,"pontosB":5,"resultado":"misto","misto":true},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Estrategista-Racional, Modo Misto"}'),
  (59, 'conector-guardiao', 'alta', 0, 403, 'c2', 7, '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["conector","guardiao"],"arquetipoMisto":true,"foco":{"pontosA":9,"pontosB":2,"intensidade":7,"ladoPredominante":"A","misto":false},"ritmo":{"pontosA":4,"pontosB":4,"intensidade":0,"ladoPredominante":null,"misto":true},"motor":{"contagem":{"racional":0,"relacional":6,"pragmatico":0},"predominantes":["relacional"]},"modo":{"pontosA":6,"pontosB":3,"resultado":"constante","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Conector-Guardião-Relacional, Modo Constante"}')
) AS v(n, arq, conf, idx, tempo, camp, dias, res)
JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || v.n)
WHERE EXISTS (SELECT 1 FROM public.mapa_comportamental_campanhas WHERE id = public.demo_id('mapacamp:' || v.camp))
  AND NOT EXISTS (SELECT 1 FROM public.mapa_comportamental_respostas r WHERE r.id = public.demo_id('mapa:' || v.n));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Mapas dos colaboradores nao semeados (cota do plano ou estrutura diferente): % (%)', SQLERRM, SQLSTATE;
END $mapa1$;

-- (M4) Mapas do proprio login da demo: o atual (campanha de lideranca) e a aplicacao anterior
DO $mapa2$
BEGIN
INSERT INTO public.mapa_comportamental_respostas (
  id, tenant_id, empresa_id, auth_user_id, usuario_id, colaborador_nome, colaborador_cpf, campanha_id, instrumento_versao,
  algoritmo_versao, status, respostas, resultado, arquetipo, indice_consistencia, confiabilidade, aviso_versao, aviso_aceite_em,
  tempo_total_segundos, concluido_em, vence_em, created_at, updated_at, origem
)
SELECT public.demo_id('mapa:demo:' || v.qual), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       ub.auth_user_id, ub.id, ub.nome_completo, NULLIF(regexp_replace(COALESCE(ub.cpf, ''), '[^0-9]', '', 'g'), ''),
       CASE WHEN v.qual = 'atual' THEN public.demo_id('mapacamp:c2') END, 1, 'v1', 'concluido',
       v.resp::jsonb, v.res::jsonb, v.arq, v.idx, v.conf, 'v1',
       now() - (CASE v.qual WHEN 'atual' THEN 3 ELSE 320 END) * interval '1 day' - interval '2 hours',
       v.tempo, now() - (CASE v.qual WHEN 'atual' THEN 3 ELSE 320 END) * interval '1 day',
       CURRENT_DATE - (CASE v.qual WHEN 'atual' THEN 3 ELSE 320 END) + 730,
       now() - (CASE v.qual WHEN 'atual' THEN 3 ELSE 320 END) * interval '1 day' - interval '2 hours',
       now() - (CASE v.qual WHEN 'atual' THEN 3 ELSE 320 END) * interval '1 day', 'app'
FROM (VALUES
  ('ant', 'guardiao-conector', 'alta', 0, 540, '{"1":-2,"2":-1,"3":-1,"4":1,"5":-1,"6":-2,"7":2,"8":2,"9":-2,"10":-1,"11":-2,"12":2,"13":2,"14":3,"15":2,"16":2,"17":2,"18":2,"19":-1,"20":2,"21":1,"22":2,"23":1,"24":2,"25":-1,"26":2,"27":-2,"28":-1}', '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["guardiao","conector"],"arquetipoMisto":true,"foco":{"pontosA":7,"pontosB":1,"intensidade":6,"ladoPredominante":"A","misto":false},"ritmo":{"pontosA":5,"pontosB":6,"intensidade":1,"ladoPredominante":null,"misto":true},"motor":{"contagem":{"racional":0,"relacional":5,"pragmatico":1},"predominantes":["relacional"]},"modo":{"pontosA":1,"pontosB":8,"resultado":"cadenciado","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Guardião-Conector-Relacional, Modo Cadenciado"}'),
  ('atual', 'estrategista', 'alta', 0, 540, '{"1":1,"2":2,"3":2,"4":1,"5":2,"6":1,"7":1,"8":-1,"9":1,"10":1,"11":1,"12":1,"13":2,"14":1,"15":1,"16":2,"17":2,"18":2,"19":-1,"20":-2,"21":1,"22":-2,"23":-2,"24":-1,"25":2,"26":2,"27":1,"28":-1}', '{"instrumentoNome":"MODUS","instrumentoVersao":1,"algoritmoVersao":"v1","arquetipos":["estrategista"],"arquetipoMisto":false,"foco":{"pontosA":0,"pontosB":9,"intensidade":9,"ladoPredominante":"B","misto":false},"ritmo":{"pontosA":1,"pontosB":5,"intensidade":4,"ladoPredominante":"B","misto":false},"motor":{"contagem":{"racional":2,"relacional":4,"pragmatico":0},"predominantes":["relacional"]},"modo":{"pontosA":8,"pontosB":1,"resultado":"constante","misto":false},"indiceConsistencia":0,"confiabilidade":"alta","motivoBaixaConfiabilidade":[],"assinatura":"Estrategista-Relacional, Modo Constante"}')
) AS v(qual, arq, conf, idx, tempo, resp, res)
JOIN public.usuarios_base ub ON ub.auth_user_id = (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' LIMIT 1)
WHERE ub.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
  AND NOT EXISTS (SELECT 1 FROM public.mapa_comportamental_respostas r WHERE r.id = public.demo_id('mapa:demo:' || v.qual));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Mapas do login da demo nao semeados (cota do plano ou estrutura diferente): % (%)', SQLERRM, SQLSTATE;
END $mapa2$;

-- (M5) Participacoes nas campanhas (convidados x respondidos = cobertura)
INSERT INTO public.mapa_comportamental_participacoes (
  id, tenant_id, campanha_id, usuario_id, colaborador_nome, colaborador_cpf, token, status, respondido_em, created_at
)
WITH resp AS (
  SELECT CASE WHEN r.campanha_id = public.demo_id('mapacamp:c1') THEN 'c1' ELSE 'c2' END AS camp, a.id AS aid
  FROM public.mapa_comportamental_respostas r
  JOIN public.admissoes a ON a.tenant_id = r.tenant_id AND a.cpf = r.colaborador_cpf
  WHERE r.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND r.auth_user_id IS NULL AND r.status = 'concluido'
    AND r.campanha_id IN (public.demo_id('mapacamp:c1'), public.demo_id('mapacamp:c2'))
),
pend AS (
  SELECT 'c1'::text AS camp, public.demo_id('admissao:' || x) AS aid FROM unnest(ARRAY[5, 7, 14, 16, 21, 27, 35, 38, 42, 49]) AS x
  UNION ALL
  SELECT 'c2', public.demo_id('admissao:' || x) FROM unnest(ARRAY[54, 56, 1, 2, 3, 14, 22, 45]) AS x
)
SELECT public.demo_id('mapapart:' || v.camp || ':' || v.aid::text), 'd3e00000-0000-4000-8000-000000000001',
       public.demo_id('mapacamp:' || v.camp), v.aid, a.nome_completo, a.cpf,
       md5('demo-mapa-part:' || v.camp || ':' || v.aid::text) || substr(md5('demo-mapa-part2:' || v.camp || ':' || v.aid::text), 1, 8),
       CASE WHEN r.id IS NOT NULL THEN 'respondido' ELSE 'pendente' END, r.concluido_em,
       now() - (CASE v.camp WHEN 'c1' THEN 150 ELSE 20 END) * interval '1 day'
FROM (SELECT camp, aid FROM resp UNION SELECT camp, aid FROM pend) v
JOIN public.admissoes a ON a.id = v.aid
LEFT JOIN public.mapa_comportamental_respostas r
       ON r.campanha_id = public.demo_id('mapacamp:' || v.camp) AND r.colaborador_cpf = a.cpf AND r.status = 'concluido'
WHERE EXISTS (SELECT 1 FROM public.mapa_comportamental_campanhas WHERE id = public.demo_id('mapacamp:' || v.camp))
  AND NOT EXISTS (SELECT 1 FROM public.mapa_comportamental_participacoes p WHERE p.id = public.demo_id('mapapart:' || v.camp || ':' || v.aid::text));

-- participacao do login da demo na campanha ativa (ja respondida)
INSERT INTO public.mapa_comportamental_participacoes (
  id, tenant_id, campanha_id, usuario_id, colaborador_nome, colaborador_cpf, token, status, respondido_em, created_at
)
SELECT public.demo_id('mapapart:c2:demo'), 'd3e00000-0000-4000-8000-000000000001', public.demo_id('mapacamp:c2'),
       r.usuario_id, r.colaborador_nome, r.colaborador_cpf, md5('demo-mapa-part:c2:demo') || 'a1b2c3d4', 'respondido', r.concluido_em, now() - interval '20 days'
FROM public.mapa_comportamental_respostas r
WHERE r.id = public.demo_id('mapa:demo:atual') AND r.usuario_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.mapa_comportamental_participacoes p WHERE p.id = public.demo_id('mapapart:c2:demo'));

-- (M6) Contestacoes (governanca), registro de acessos e link publico
INSERT INTO public.mapa_comportamental_contestacoes (
  id, tenant_id, mapa_id, colaborador_cpf, colaborador_nome, texto, solicitou_reaplicacao, status, resposta,
  resolvido_por_nome, resolvido_em, created_at, updated_at
)
SELECT public.demo_id('mapacont:' || v.n), 'd3e00000-0000-4000-8000-000000000001', r.id, r.colaborador_cpf, r.colaborador_nome,
       v.texto, v.reaplic, v.status, v.resposta, CASE WHEN v.status = 'resolvida' THEN 'Leiri' END,
       CASE WHEN v.status = 'resolvida' THEN now() - interval '60 days' END, now() - v.dias * interval '1 day', now() - v.dias * interval '1 day'
FROM (VALUES
  (11, 'Respondi o questionário com pressa em um dia de muito serviço e acho que o resultado não me representa.', true, 'aberta', NULL, 4),
  (33, 'Acredito que algumas respostas foram marcadas sem atenção. Gostaria de refazer com calma.', true, 'em_analise', NULL, 12),
  (47, 'O resultado indicou baixa confiabilidade, mas respondi com atenção. Peço revisão.', false, 'resolvida', 'Revisamos em conjunto: o resultado foi mantido como interpretação de apoio ao desenvolvimento. Reaplicação oferecida e recusada.', 70)
) AS v(n, texto, reaplic, status, resposta, dias)
JOIN public.mapa_comportamental_respostas r ON r.id = public.demo_id('mapa:' || v.n)
WHERE NOT EXISTS (SELECT 1 FROM public.mapa_comportamental_contestacoes c WHERE c.id = public.demo_id('mapacont:' || v.n));

INSERT INTO public.mapa_comportamental_acessos (id, tenant_id, mapa_id, acessado_por, acessado_por_nome, acessado_em)
SELECT public.demo_id('mapaacc:' || v.i), 'd3e00000-0000-4000-8000-000000000001', m.id,
       public.demo_id('admissao:' || v.por_n), v.por_nome, now() - v.dias * interval '1 day'
FROM (VALUES
  (1, 'demo:atual', 59, 'Priscila Ornelas Vidal (RH)', 2),
  (2, 'demo:atual', 58, 'Fábio Gouveia Leme (RH)', 1),
  (3, 'demo:ant', 59, 'Priscila Ornelas Vidal (RH)', 40),
  (4, '28', 59, 'Priscila Ornelas Vidal (RH)', 6),
  (5, '28', 40, 'Carlos Albuquerque Teles (Gestor)', 5),
  (6, '1', 58, 'Fábio Gouveia Leme (RH)', 9),
  (7, '13', 28, 'Márcio Rezende Matos (Gestor)', 3),
  (8, '40', 59, 'Priscila Ornelas Vidal (RH)', 8)
) AS v(i, mapa, por_n, por_nome, dias)
JOIN public.mapa_comportamental_respostas m ON m.id = public.demo_id('mapa:' || v.mapa)
WHERE NOT EXISTS (SELECT 1 FROM public.mapa_comportamental_acessos x WHERE x.id = public.demo_id('mapaacc:' || v.i));

INSERT INTO public.mapa_comportamental_links (id, tenant_id, empresa_id, token, ativo, data_expiracao, created_at, updated_at)
SELECT public.demo_id('mapalink:1'), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       md5('demo-mapa-link:1'), true, NULL, now() - interval '30 days', now() - interval '30 days'
WHERE NOT EXISTS (SELECT 1 FROM public.mapa_comportamental_links l WHERE l.tenant_id = 'd3e00000-0000-4000-8000-000000000001');

-- (M7) Perfil ideal por cargo (alimenta o card "Aderencia a funcao" do mapa)
INSERT INTO public.cargo_perfil_ideal (
  id, tenant_id, empresa_id, cargo_id, arquetipo_ideal, motor_ideal, modo_ideal, observacoes, definido_por_nome,
  algoritmo_versao, created_at, updated_at
)
SELECT public.demo_id('perfilideal:' || v.cargo), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       public.demo_id('cargo:' || v.cargo), v.arq, v.motor, v.modo, v.obs, 'Leiri', 'v1', now() - interval '100 days', now() - interval '100 days'
FROM (VALUES
  ('Operador de Usinagem CNC', 'estrategista', ARRAY['racional'], 'constante', 'Precisão, atenção ao detalhe e constância na rotina de setup.'),
  ('Soldador', 'guardiao', ARRAY['pragmatico'], 'constante', 'Constância e cuidado com procedimentos; trabalho de alta repetição.'),
  ('Montador de Estruturas Metálicas', 'guardiao', ARRAY['relacional','pragmatico'], 'misto', 'Trabalho em dupla e leitura de desenho com mão na massa.'),
  ('Líder de Produção', 'pioneiro', ARRAY['pragmatico'], 'cadenciado', 'Decisão rápida e foco em resultado, com ciclos de pico e ajuste.'),
  ('Mecânico de Manutenção', 'estrategista', ARRAY['racional'], 'cadenciado', 'Diagnóstico técnico e atuação em ciclos de parada.'),
  ('Eletricista de Manutenção', 'estrategista', ARRAY['racional'], 'constante', 'Segurança e método em intervenções elétricas.'),
  ('Supervisor de Manutenção', 'pioneiro', ARRAY['racional','pragmatico'], 'cadenciado', 'Liderança técnica com decisão sob pressão.'),
  ('Operador de Empilhadeira', 'guardiao', ARRAY['pragmatico'], 'constante', 'Atenção contínua e disciplina de segurança.'),
  ('Auxiliar de Logística', 'conector', ARRAY['relacional'], 'misto', 'Trabalho em equipe e flexibilidade entre tarefas.'),
  ('Coordenador de Logística', 'conector', ARRAY['relacional','pragmatico'], 'cadenciado', 'Coordenação de pessoas e picos de expedição.'),
  ('Analista Financeiro', 'estrategista', ARRAY['racional'], 'constante', 'Rigor com números e rotina de fechamento.'),
  ('Analista da Qualidade', 'estrategista', ARRAY['racional'], 'constante', 'Método, evidência e atenção a desvios.'),
  ('Comprador', 'conector', ARRAY['relacional','pragmatico'], 'cadenciado', 'Negociação com fornecedores.'),
  ('Analista de RH', 'conector', ARRAY['relacional'], 'misto', 'Escuta e relacionamento com colaboradores.'),
  ('Técnico de Segurança do Trabalho', 'guardiao', ARRAY['racional','relacional'], 'constante', 'Rigor normativo e presença constante na fábrica.'),
  ('Vendedor Interno', 'conector', ARRAY['relacional'], 'cadenciado', 'Relacionamento com clientes e metas por ciclos de venda.')
) AS v(cargo, arq, motor, modo, obs)
WHERE EXISTS (SELECT 1 FROM public.cargos c WHERE c.id = public.demo_id('cargo:' || v.cargo))
  AND NOT EXISTS (SELECT 1 FROM public.cargo_perfil_ideal x WHERE x.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND x.cargo_id = public.demo_id('cargo:' || v.cargo));

-- ---------------------------------------------------------------------------
-- Conferencia final
-- ---------------------------------------------------------------------------
SELECT
  (SELECT count(*) FROM public.pdis WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS pdis,
  (SELECT count(*) FROM public.pdi_metas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS pdi_metas,
  (SELECT count(*) FROM public.pdi_acoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS pdi_acoes,
  (SELECT count(*) FROM public.pdi_checkins WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS pdi_checkins,
  (SELECT count(*) FROM public.pdi_feedbacks WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS pdi_feedbacks,
  (SELECT count(*) FROM public.pdi_assinatura_links WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS pdi_assinaturas,
  (SELECT count(*) FROM public.mapa_comportamental_campanhas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS mapa_campanhas,
  (SELECT count(*) FROM public.mapa_comportamental_respostas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND status = 'concluido') AS mapas_concluidos,
  (SELECT count(*) FROM public.mapa_comportamental_participacoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS mapa_participacoes,
  (SELECT count(*) FROM public.cargo_perfil_ideal WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS perfis_ideais,
  CASE WHEN (SELECT count(*) FROM public.pdis WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') = 21
        AND (SELECT count(*) FROM public.mapa_comportamental_respostas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND status = 'concluido') >= 40
       THEN 'OK' ELSE 'CONFERIR' END AS situacao;
