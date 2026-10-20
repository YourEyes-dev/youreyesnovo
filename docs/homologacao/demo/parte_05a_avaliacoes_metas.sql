-- ============================================================================
-- HOMOLOGACAO — DEMONSTRACAO, PARTE 05a: Avaliacoes de desempenho + Metas
--
-- PARA QUE SERVE
-- Preenche as telas /avaliacoes (caixa de entrada, ciclos, templates, resultados,
-- matriz 9-Box, aba de metas com OKRs) e /metas (dashboard, lista, consolidacao,
-- indicadores, configuracao) da "Metalurgica Exemplo Ltda" (100% ficticia).
-- Depende da PARTE 00 (tenant, empresa, departamentos, 64 colaboradores e o login).
--
-- ONDE COLAR
-- SQL Editor do projeto de HOMOLOGACAO, depois da parte 00. O arquivo se RECUSA a
-- rodar fora da homologacao/teste (mesma trava da parte 00). Nunca na producao.
--
-- O QUE FAZ (tudo no tenant demo, empresa matriz)
--   1. 5 templates de avaliacao (90 graus, 180 graus, 360 de lideranca, experiencia,
--      autoavaliacao) com categorias, criterios e escala 1 a 5;
--   2. 4 ciclos: 2 encerrados (historico), 1 em analise e 1 ATIVO em andamento;
--   3. cerca de 170 respostas (concluidas, em andamento e pendentes) com notas por
--      criterio, comentarios, pontos fortes e areas de desenvolvimento; as pendentes
--      do ciclo 360 aparecem na caixa de entrada do login da demo;
--   4. matriz 9-Box do ciclo encerrado mais recente (os 9 quadrantes, com calibracao do comite);
--   5. 32 metas em 4 niveis (estrategica > unidade > setor > individual) com
--      indicadores, status variados (no prazo, atrasadas, concluidas, em aprovacao,
--      rascunho, cancelada), 42 OKRs com check-ins, check-ins de metas, trilha de
--      aprovacao, participantes, evidencias (so links), catalogo de indicadores e
--      a configuracao do modulo.
--
-- GARANTIAS
--   - Nenhum dado real: nomes dos colaboradores vem da parte 00 (ficticios).
--   - Idempotente: ids fixos (demo_id) + "so insere se nao existe". Rodar de novo
--     nao duplica nada.
--   - Nao cria tabela, nao apaga nada e so ALTERA metas do proprio tenant demo
--     (marca como "atrasada" a meta ativa vencida e incompleta — regra do modulo —
--     porque o gatilho de check-in devolve o status para "em andamento").
--   - Roda numa transacao so; sem tabela temporaria entre comandos.
-- ============================================================================

SET lock_timeout = '10s';

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
END $trava$;

-- Helpers da parte 00 (recriados com o mesmo corpo, caso esta parte rode isolada).
CREATE OR REPLACE FUNCTION public.demo_id(chave text)
RETURNS uuid
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT md5('youreyes-demo:' || chave)::uuid
$fn$;

-- Numero pseudo-aleatorio DETERMINISTICO de 0 a m-1 a partir de uma chave
-- (mesma chave, mesmo numero: mantem a carga repetivel).
CREATE OR REPLACE FUNCTION public.demo_dev_rnd(chave text, m integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT (('x' || substr(md5('youreyes-demo-rnd:' || chave), 1, 7))::bit(28)::int) % GREATEST(m, 1)
$fn$;

-- ---------------------------------------------------------------------------
-- (2) Templates de avaliacao
-- ---------------------------------------------------------------------------
INSERT INTO public.avaliacao_templates (
  id, tenant_id, nome, descricao, tipo, categorias, criterios, escala_min, escala_max, escala_labels,
  permite_comentarios, ativo, criado_por_nome, created_at, updated_at
)
SELECT public.demo_id('avtpl:' || v.chave), 'd3e00000-0000-4000-8000-000000000001',
       v.nome, v.descricao, v.tipo::public.avaliacao_tipo, v.categorias::jsonb, v.criterios::jsonb, 1, 5,
       '[{"valor":1,"label":"Insuficiente"},{"valor":2,"label":"Em desenvolvimento"},{"valor":3,"label":"Atende"},{"valor":4,"label":"Supera"},{"valor":5,"label":"Excepcional"}]'::jsonb,
       true, v.ativo, 'Leiri', now() - v.idade, now() - v.idade
FROM (VALUES
  ('t90', 'Avaliação 90° — Gestor avalia a equipe', 'Avaliação do gestor sobre cada integrante da equipe de chão de fábrica: entregas, segurança e comportamento.', 'simples',
   '[{"id":"resultados","nome":"Resultados e entregas","peso":1.5},{"id":"seguranca","nome":"Segurança e qualidade","peso":1.5},{"id":"comportamento","nome":"Comportamento e equipe","peso":1}]',
   '[{"id":"Produção","nome":"Cumprimento das metas de produção","peso":1,"categoria":"resultados"},{"id":"Prazos","nome":"Cumprimento de prazos e rotinas","peso":1,"categoria":"resultados"},{"id":"Qualidade","nome":"Qualidade do que entrega","peso":1,"categoria":"seguranca"},{"id":"Segurança","nome":"Uso de EPIs e normas de segurança","peso":1.5,"categoria":"seguranca"},{"id":"5S","nome":"Organização e limpeza (5S)","peso":1,"categoria":"seguranca"},{"id":"Equipe","nome":"Trabalho em equipe e respeito","peso":1,"categoria":"comportamento"}]',
   true, interval '400 days'),
  ('t180', 'Avaliação 180° — Autoavaliação + Gestor', 'O colaborador se avalia e o gestor responde o mesmo formulário; o RH compara as duas visões.', 'simples',
   '[{"id":"resultados","nome":"Resultados","peso":1.5},{"id":"competencias","nome":"Competências","peso":1},{"id":"atitude","nome":"Atitude","peso":1}]',
   '[{"id":"Entregas","nome":"Entregas e resultados do período","peso":1.5,"categoria":"resultados"},{"id":"Qualidade","nome":"Qualidade e atenção aos detalhes","peso":1,"categoria":"resultados"},{"id":"Segurança","nome":"Cultura de segurança","peso":1.5,"categoria":"competencias"},{"id":"Iniciativa","nome":"Iniciativa e proatividade","peso":1,"categoria":"atitude"},{"id":"Equipe","nome":"Colaboração com a equipe","peso":1,"categoria":"atitude"},{"id":"Comunicação","nome":"Clareza na comunicação","peso":1,"categoria":"competencias"}]',
   true, interval '400 days'),
  ('t360', 'Avaliação 360° — Liderança e Gestão', 'Autoavaliação, gestor, pares e liderados avaliam líderes e supervisores.', '360',
   '[{"id":"pessoas","nome":"Gestão de pessoas","peso":1.5},{"id":"resultados","nome":"Resultados","peso":1.5},{"id":"cultura","nome":"Cultura e segurança","peso":1}]',
   '[{"id":"Feedback","nome":"Dá feedback claro e frequente","peso":1,"categoria":"pessoas"},{"id":"Equipe","nome":"Desenvolve e engaja a equipe","peso":1,"categoria":"pessoas"},{"id":"Decisão","nome":"Toma decisões no tempo certo","peso":1,"categoria":"resultados"},{"id":"Resultados","nome":"Entrega as metas do setor","peso":1.5,"categoria":"resultados"},{"id":"Segurança","nome":"É exemplo em segurança do trabalho","peso":1.5,"categoria":"cultura"},{"id":"Ética","nome":"Age com ética e transparência","peso":1,"categoria":"cultura"}]',
   true, interval '300 days'),
  ('texp', 'Avaliação de Experiência (45/90 dias)', 'Aplicada a quem foi contratado há pouco: adaptação, segurança e aprendizado.', 'simples',
   '[{"id":"adaptacao","nome":"Adaptação","peso":1},{"id":"desempenho","nome":"Desempenho inicial","peso":1.5}]',
   '[{"id":"Adaptação","nome":"Adaptação à rotina e à equipe","peso":1,"categoria":"adaptacao"},{"id":"Pontualidade","nome":"Pontualidade e assiduidade","peso":1,"categoria":"adaptacao"},{"id":"Segurança","nome":"Aplica as regras de segurança","peso":1.5,"categoria":"desempenho"},{"id":"Aprendizado","nome":"Velocidade de aprendizado","peso":1,"categoria":"desempenho"},{"id":"Equipe","nome":"Integração com a equipe","peso":1,"categoria":"adaptacao"}]',
   true, interval '200 days'),
  ('tauto', 'Autoavaliação de Competências', 'Modelo livre para o colaborador refletir sobre o próprio desenvolvimento antes do PDI.', 'simples',
   '[{"id":"tecnicas","nome":"Competências técnicas","peso":1},{"id":"comportamentais","nome":"Competências comportamentais","peso":1}]',
   '[{"id":"Técnica","nome":"Domínio técnico da função","peso":1,"categoria":"tecnicas"},{"id":"Autonomia","nome":"Autonomia na execução","peso":1,"categoria":"tecnicas"},{"id":"Comunicação","nome":"Comunicação","peso":1,"categoria":"comportamentais"},{"id":"Aprendizado","nome":"Disposição para aprender","peso":1,"categoria":"comportamentais"},{"id":"Equipe","nome":"Colaboração","peso":1,"categoria":"comportamentais"}]',
   true, interval '150 days')
) AS v(chave, nome, descricao, tipo, categorias, criterios, ativo, idade)
WHERE NOT EXISTS (SELECT 1 FROM public.avaliacao_templates t WHERE t.id = public.demo_id('avtpl:' || v.chave));

-- ---------------------------------------------------------------------------
-- (3) Ciclos: 2 encerrados, 1 em analise, 1 ativo
-- ---------------------------------------------------------------------------
INSERT INTO public.avaliacao_ciclos (
  id, tenant_id, template_id, nome, descricao, status, data_inicio, data_fim, config_360,
  departamentos_ids, notificacoes_enviadas, criado_por_nome, created_at, updated_at, empresa_id
)
SELECT public.demo_id('avciclo:' || v.chave), 'd3e00000-0000-4000-8000-000000000001',
       public.demo_id('avtpl:' || v.tpl), v.nome, v.descricao, v.status::public.avaliacao_ciclo_status,
       CURRENT_DATE + v.ini, CURRENT_DATE + v.fim, v.cfg::jsonb,
       CASE WHEN v.chave = 'c4'
            THEN ARRAY[public.demo_id('depto:Produção'), public.demo_id('depto:Manutenção'), public.demo_id('depto:Logística')]
       END,
       true, 'Leiri', now() + (v.ini - 7) * interval '1 day', now() + LEAST(v.fim, 0) * interval '1 day',
       'd3e00000-0000-4000-8000-000000000002'
FROM (VALUES
  ('c1', 't180', 'Avaliação Anual de Desempenho 2025', 'Ciclo anual 180°: autoavaliação e avaliação do gestor para todos os colaboradores.', 'encerrado', -380, -330,
   '{"auto":true,"gestor":true,"pares":0,"subordinados":false,"cliente_interno":false}'),
  ('c2', 't90', 'Ciclo 1º Semestre 2026 — Operações', 'Avaliação 90° semestral conduzida pelos líderes de Produção, Manutenção e Logística.', 'encerrado', -200, -150,
   '{"auto":false,"gestor":true,"pares":0,"subordinados":false,"cliente_interno":false}'),
  ('c3', 'texp', 'Avaliação de Experiência — Contratados do 2º trimestre', 'Acompanhamento de 45/90 dias dos colaboradores contratados entre fevereiro e agosto. Em análise pelo RH.', 'analisando', -75, -30,
   '{"auto":true,"gestor":true,"pares":0,"subordinados":false,"cliente_interno":false}'),
  ('c4', 't360', 'Avaliação 360° de Liderança 2026', 'Líderes e supervisores avaliados por si mesmos, pelo gestor, por pares e por liderados. Em andamento.', 'ativo', -18, 27,
   '{"auto":true,"gestor":true,"pares":2,"subordinados":true,"cliente_interno":false}')
) AS v(chave, tpl, nome, descricao, status, ini, fim, cfg)
WHERE NOT EXISTS (SELECT 1 FROM public.avaliacao_ciclos c WHERE c.id = public.demo_id('avciclo:' || v.chave));

-- ---------------------------------------------------------------------------
-- (4) Respostas das avaliacoes
--     c1/c2: gestor para quem ja estava na empresa (+ autoavaliacao em c1)
--     c3: gestor + auto dos contratados recentes
--     c4: 360 dos 4 lideres (auto, gestor, 2 pares, 2 liderados)
-- ---------------------------------------------------------------------------
INSERT INTO public.avaliacao_respostas (
  id, tenant_id, ciclo_id, avaliado_id, avaliado_nome, avaliador_id, avaliador_nome, tipo_avaliador, status,
  notas_criterios, nota_geral, comentario_geral, pontos_fortes, areas_desenvolvimento,
  data_inicio, data_conclusao, created_at, updated_at
)
WITH alvo AS (
  -- c1: encerrado, 180
  SELECT 'c1'::text AS ck, a.id AS avaliado_id, a.nome_completo AS avaliado_nome, a.departamento AS dep,
         'gestor'::text AS tipo, '0'::text AS k, 'concluida'::text AS st, NULL::uuid AS avaliador_uid, NULL::uuid AS avaliador_ref
  FROM public.admissoes a
  WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a.status IN ('concluido','desligado')
    AND a.data_admissao <= CURRENT_DATE - 410
  UNION ALL
  SELECT 'c1', a.id, a.nome_completo, a.departamento, 'auto', '0', 'concluida', NULL, a.id
  FROM public.admissoes a
  WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a.status IN ('concluido','desligado')
    AND a.data_admissao <= CURRENT_DATE - 410
    AND public.demo_dev_rnd(a.id::text || 'auto-c1', 2) = 0
  UNION ALL
  -- c2: encerrado, 90
  SELECT 'c2', a.id, a.nome_completo, a.departamento, 'gestor', '0', 'concluida', NULL, NULL
  FROM public.admissoes a
  WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a.status IN ('concluido','desligado')
    AND a.data_admissao <= CURRENT_DATE - 230
  UNION ALL
  -- c3: em analise, experiencia
  SELECT 'c3', a.id, a.nome_completo, a.departamento, 'gestor', '0', 'concluida', NULL, NULL
  FROM public.admissoes a
  WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a.status = 'concluido'
    AND a.data_admissao > CURRENT_DATE - 260 AND a.data_admissao <= CURRENT_DATE - 40
  UNION ALL
  SELECT 'c3', a.id, a.nome_completo, a.departamento, 'auto', '0', 'concluida', NULL, a.id
  FROM public.admissoes a
  WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a.status = 'concluido'
    AND a.data_admissao > CURRENT_DATE - 260 AND a.data_admissao <= CURRENT_DATE - 40
  UNION ALL
  -- c4: 360 de lideranca (avaliados: admissoes 28, 29, 40, 52)
  SELECT 'c4', a.id, a.nome_completo, a.departamento, r.tipo, r.k, r.st,
         CASE WHEN r.demo THEN (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' LIMIT 1) END,
         CASE WHEN r.tipo = 'auto' THEN a.id
              WHEN r.tipo = 'par' AND NOT r.demo THEN public.demo_id('admissao:' || r.ref)
              WHEN r.tipo = 'subordinado' THEN public.demo_id('admissao:' || r.ref) END
  FROM public.admissoes a
  JOIN (VALUES
    (28, 'auto',        '0', 'concluida',    false, NULL::int),
    (28, 'gestor',      '0', 'concluida',    false, NULL),
    (28, 'par',         '1', 'concluida',    false, 29),
    (28, 'par',         '2', 'pendente',     true,  NULL),
    (28, 'subordinado', '1', 'concluida',    false, 1),
    (28, 'subordinado', '2', 'em_andamento', false, 2),
    (29, 'auto',        '0', 'concluida',    false, NULL),
    (29, 'gestor',      '0', 'concluida',    false, NULL),
    (29, 'par',         '1', 'concluida',    false, 28),
    (29, 'par',         '2', 'pendente',     true,  NULL),
    (29, 'subordinado', '1', 'concluida',    false, 13),
    (29, 'subordinado', '2', 'concluida',    false, 14),
    (40, 'auto',        '0', 'em_andamento', false, NULL),
    (40, 'gestor',      '0', 'concluida',    false, NULL),
    (40, 'par',         '1', 'concluida',    false, 52),
    (40, 'par',         '2', 'em_andamento', true,  NULL),
    (40, 'subordinado', '1', 'concluida',    false, 30),
    (40, 'subordinado', '2', 'pendente',     false, 31),
    (52, 'auto',        '0', 'concluida',    false, NULL),
    (52, 'gestor',      '0', 'em_andamento', false, NULL),
    (52, 'par',         '1', 'concluida',    false, 40),
    (52, 'par',         '2', 'em_andamento', true,  NULL),
    (52, 'subordinado', '1', 'concluida',    false, 41),
    (52, 'subordinado', '2', 'concluida',    false, 42)
  ) AS r(n, tipo, k, st, demo, ref) ON a.id = public.demo_id('admissao:' || r.n)
  WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
),
ciclo AS (
  SELECT c.id AS ciclo_id, c.data_inicio, c.data_fim, c.template_id,
         t.criterios, k.ck
  FROM (VALUES ('c1'), ('c2'), ('c3'), ('c4')) AS k(ck)
  JOIN public.avaliacao_ciclos c ON c.id = public.demo_id('avciclo:' || k.ck)
  JOIN public.avaliacao_templates t ON t.id = c.template_id
),
base AS (
  SELECT al.*, ci.ciclo_id, ci.data_inicio AS ini, ci.data_fim AS fim, ci.criterios,
         public.demo_id('avresp:' || al.ck || ':' || al.avaliado_id::text || ':' || al.tipo || ':' || al.k) AS rid,
         -- nota-base da pessoa no ciclo (2.7 a 4.9); o 2o semestre melhora um pouco
         LEAST(4.9, 2.7 + public.demo_dev_rnd(al.avaliado_id::text || al.ck, 215) / 100.0
               + CASE al.ck WHEN 'c2' THEN 0.15 WHEN 'c3' THEN 0.1 WHEN 'c4' THEN 0.2 ELSE 0 END
               + CASE al.tipo WHEN 'auto' THEN 0.25 ELSE 0 END) AS nb,
         CASE
           WHEN al.avaliador_ref IS NOT NULL AND al.tipo <> 'auto'
             THEN (SELECT x.nome_completo FROM public.admissoes x WHERE x.id = al.avaliador_ref)
           WHEN al.tipo = 'auto' THEN al.avaliado_nome
           WHEN al.avaliador_uid IS NOT NULL THEN 'Leiri'
           WHEN al.ck = 'c4' AND al.tipo = 'gestor' THEN 'Direção Industrial'
           WHEN al.dep = 'Produção' THEN (SELECT x.nome_completo FROM public.admissoes x WHERE x.id = public.demo_id('admissao:28'))
           WHEN al.dep = 'Manutenção' THEN (SELECT x.nome_completo FROM public.admissoes x WHERE x.id = public.demo_id('admissao:40'))
           WHEN al.dep = 'Logística' THEN (SELECT x.nome_completo FROM public.admissoes x WHERE x.id = public.demo_id('admissao:52'))
           WHEN al.dep = 'Administrativo' THEN 'Gerência Administrativa'
           ELSE 'Leiri'
         END AS avaliador_nome
  FROM alvo al
  JOIN ciclo ci ON ci.ck = al.ck
),
calc AS (
  SELECT b.*,
         q.notas, q.media
  FROM base b
  LEFT JOIN LATERAL (
    SELECT jsonb_object_agg(z.cid, z.n) FILTER (WHERE b.st = 'concluida' OR (b.st = 'em_andamento' AND z.ord <= 3)) AS notas,
           CASE WHEN b.st = 'concluida' THEN round(avg(z.n)::numeric, 1) END AS media
    FROM (
      SELECT c.elem ->> 'id' AS cid, c.ord,
             GREATEST(1, LEAST(5, round(b.nb + (public.demo_dev_rnd(b.rid::text || (c.elem ->> 'id'), 5) - 2) * 0.4)::int)) AS n
      FROM jsonb_array_elements(b.criterios) WITH ORDINALITY AS c(elem, ord)
    ) z
  ) q ON true
)
SELECT c.rid, 'd3e00000-0000-4000-8000-000000000001', c.ciclo_id, c.avaliado_id::text, c.avaliado_nome,
       c.avaliador_uid, c.avaliador_nome, c.tipo::public.tipo_avaliador, c.st::public.resposta_status,
       COALESCE(c.notas, '{}'::jsonb), c.media,
       CASE WHEN c.st = 'concluida' THEN
         CASE WHEN c.media >= 4.0 THEN (ARRAY[
              'Colaborador referência na área: entrega acima do esperado e ajuda os colegas.',
              'Excelente período. Mantém qualidade e prazo mesmo em semanas de pico de produção.',
              'Resultado consistente, boa atitude e postura de segurança exemplar.',
              'Supera as expectativas da função e tem potencial para assumir novas responsabilidades.'])[1 + public.demo_dev_rnd(c.rid::text || 'cm', 4)]
              WHEN c.media >= 3.0 THEN (ARRAY[
              'Atende ao esperado para a função, com evolução visível ao longo do período.',
              'Bom desempenho geral. Há espaço para ganhar autonomia nas atividades mais complexas.',
              'Entrega dentro do combinado; pode melhorar a comunicação com o turno seguinte.',
              'Cumpre as rotinas e mantém bom relacionamento com a equipe.'])[1 + public.demo_dev_rnd(c.rid::text || 'cm', 4)]
              ELSE (ARRAY[
              'Desempenho abaixo do esperado neste ciclo; combinado plano de acompanhamento próximo.',
              'Precisa reforçar o cumprimento de procedimentos e prazos. Será acompanhado no PDI.',
              'Oscilou ao longo do período. Recomenda-se treinamento direcionado e feedback quinzenal.'])[1 + public.demo_dev_rnd(c.rid::text || 'cm', 3)]
         END
       END,
       CASE WHEN c.st = 'concluida' THEN (ARRAY[
         'Comprometimento e responsabilidade com a segurança.',
         'Qualidade do trabalho e atenção aos detalhes.',
         'Boa comunicação e disposição para ajudar a equipe.',
         'Pontualidade e assiduidade.',
         'Domínio técnico da função.',
         'Organização do posto de trabalho (5S).',
         'Iniciativa para propor melhorias no processo.',
         'Calma e foco em situações de pressão.'])[1 + public.demo_dev_rnd(c.rid::text || 'pf', 8)] END,
       CASE WHEN c.st = 'concluida' THEN (ARRAY[
         'Ampliar o conhecimento de outras máquinas/etapas do processo.',
         'Registrar melhor as ocorrências no fim do turno.',
         'Participar mais das reuniões de início de turno.',
         'Aprofundar a leitura de desenho técnico.',
         'Desenvolver autonomia para resolver pequenos desvios.',
         'Melhorar o feedback dado aos colegas.',
         'Reforçar o uso consistente de todos os EPIs.',
         'Planejar melhor o setup entre ordens de produção.'])[1 + public.demo_dev_rnd(c.rid::text || 'ad', 8)] END,
       CASE WHEN c.st <> 'pendente' THEN (c.ini + public.demo_dev_rnd(c.rid::text || 'di', 8))::timestamptz + interval '9 hours' END,
       CASE WHEN c.st = 'concluida'
            THEN LEAST(c.fim, CURRENT_DATE - 1, c.ini + 3 + public.demo_dev_rnd(c.rid::text || 'dc', 12))::timestamptz + interval '15 hours' END,
       c.ini::timestamptz, now()
FROM calc c
WHERE NOT EXISTS (SELECT 1 FROM public.avaliacao_respostas r WHERE r.id = c.rid);

-- ---------------------------------------------------------------------------
-- (5) Matriz 9-Box (ciclo encerrado mais recente, c2): desempenho vem da nota do gestor
-- ---------------------------------------------------------------------------
INSERT INTO public.avaliacao_9box (
  id, tenant_id, ciclo_id, colaborador_id, colaborador_nome, desempenho, potencial, quadrante, justificativa,
  avaliador_nome, data_avaliacao, created_at, updated_at
)
WITH base AS (
  SELECT r.avaliado_id, r.avaliado_nome, r.nota_geral, r.ciclo_id, a.departamento,
         CASE WHEN r.nota_geral >= 4.0 THEN 3 WHEN r.nota_geral >= 3.2 THEN 2 ELSE 1 END AS d,
         public.demo_dev_rnd(r.avaliado_id || 'pot', 100) AS p
  FROM public.avaliacao_respostas r
  JOIN public.admissoes a ON a.id::text = r.avaliado_id
  WHERE r.ciclo_id = public.demo_id('avciclo:c2') AND r.tipo_avaliador = 'gestor' AND r.status = 'concluida'
    AND a.status = 'concluido'
),
nivel AS (
  SELECT b.avaliado_id, b.avaliado_nome, b.ciclo_id,
         COALESCE(ov.d, b.d) AS d,
         -- potencial acompanha o desempenho com variacao; a calibracao do comite
         -- (ov) posiciona alguns casos de "enigma" e "especialista" para cobrir os 9 quadrantes
         COALESCE(ov.p, GREATEST(1, LEAST(3, b.d + CASE WHEN b.p < 22 THEN -1 WHEN b.p > 72 THEN 1 ELSE 0 END))) AS pot
  FROM base b
  LEFT JOIN (VALUES (9, 1, 3), (44, 1, 3), (20, 3, 1), (14, 3, 1), (31, 2, 1)) AS ov(n, d, p)
         ON public.demo_id('admissao:' || ov.n)::text = b.avaliado_id
)
SELECT public.demo_id('9box:' || n.avaliado_id), 'd3e00000-0000-4000-8000-000000000001', n.ciclo_id,
       n.avaliado_id, n.avaliado_nome, n.d, n.pot, n.d || '-' || n.pot,
       CASE n.d || '-' || n.pot
         WHEN '3-3' THEN 'Entrega acima do esperado e demonstra capacidade de assumir uma liderança. Candidato a sucessão.'
         WHEN '3-2' THEN 'Alto contribuidor, confiável. Valorizar e oferecer desafios técnicos.'
         WHEN '3-1' THEN 'Especialista no que faz; manter motivado e reconhecer a contribuição.'
         WHEN '2-3' THEN 'Desempenho adequado com muito potencial. Acelerar com PDI e trilha de liderança.'
         WHEN '2-2' THEN 'Profissional sólido em desenvolvimento. Manter acompanhamento semestral.'
         WHEN '2-1' THEN 'Contribuidor estável; sem sinais de mudança de função no curto prazo.'
         WHEN '1-3' THEN 'Potencial claro, mas resultados abaixo. Investigar bloqueios e apoiar com mentoria.'
         WHEN '1-2' THEN 'Desempenho abaixo do esperado; definir plano de melhoria de 90 dias.'
         ELSE 'Resultados e engajamento baixos. Avaliar continuidade/realocação após o plano de acompanhamento.'
       END,
       'Leiri', CURRENT_DATE - 140, now() - interval '140 days', now() - interval '140 days'
FROM nivel n
WHERE NOT EXISTS (SELECT 1 FROM public.avaliacao_9box x WHERE x.id = public.demo_id('9box:' || n.avaliado_id));

-- ---------------------------------------------------------------------------
-- (6) Catalogo de indicadores e configuracao do modulo de metas
-- ---------------------------------------------------------------------------
INSERT INTO public.metas_indicadores (
  id, tenant_id, nome, descricao, tipo, unidade_medida, formula, direcao, origem_dados, frequencia_atualizacao,
  ativo, criado_por_nome, created_at, updated_at
)
SELECT public.demo_id('metaind:' || v.chave), 'd3e00000-0000-4000-8000-000000000001', v.nome, v.descricao,
       v.tipo::public.indicador_tipo, v.un, v.formula, v.dir::public.indicador_direcao, v.origem, v.freq,
       true, 'Leiri', now() - interval '300 days', now() - interval '300 days'
FROM (VALUES
  ('oee', 'OEE — Eficiência Global dos Equipamentos', 'Disponibilidade x desempenho x qualidade das linhas de usinagem e solda.', 'percentual', '%', '(Disponibilidade x Desempenho x Qualidade)', 'maior_melhor', 'MES / apontamento de produção', 'mensal'),
  ('freq', 'Taxa de frequência de acidentes', 'Acidentes com afastamento por milhão de horas trabalhadas.', 'quantitativo', 'acidentes/milhão h', '(Acidentes x 1.000.000) / horas trabalhadas', 'menor_melhor', 'SST / CAT', 'mensal'),
  ('turnover', 'Turnover voluntário', 'Pedidos de demissão no período dividido pelo efetivo médio.', 'percentual', '%', 'Desligamentos voluntários / efetivo médio x 100', 'menor_melhor', 'RH / folha', 'mensal'),
  ('otif', 'OTIF — Entrega no prazo e completa', 'Pedidos entregues no prazo e sem faltas sobre o total expedido.', 'percentual', '%', 'Pedidos OTIF / pedidos expedidos x 100', 'maior_melhor', 'ERP / expedição', 'mensal'),
  ('retrabalho', 'Índice de retrabalho', 'Peças que voltam para a linha sobre o total produzido.', 'percentual', '%', 'Peças retrabalhadas / peças produzidas x 100', 'menor_melhor', 'Qualidade', 'semanal'),
  ('absenteismo', 'Absenteísmo', 'Horas de ausência não programada sobre horas contratadas.', 'percentual', '%', 'Horas ausentes / horas contratadas x 100', 'menor_melhor', 'Ponto eletrônico', 'mensal'),
  ('dso', 'DSO — Prazo médio de recebimento', 'Dias médios entre a venda e o recebimento.', 'quantitativo', 'dias', 'Contas a receber / faturamento x dias do período', 'menor_melhor', 'Financeiro', 'mensal'),
  ('contratacao', 'Tempo médio de contratação', 'Dias entre a abertura da vaga e a admissão.', 'quantitativo', 'dias', 'Soma dos dias de vagas fechadas / vagas fechadas', 'menor_melhor', 'RH / recrutamento', 'mensal')
) AS v(chave, nome, descricao, tipo, un, formula, dir, origem, freq)
WHERE NOT EXISTS (SELECT 1 FROM public.metas_indicadores i WHERE i.id = public.demo_id('metaind:' || v.chave));

INSERT INTO public.metas_configuracao (tenant_id)
SELECT 'd3e00000-0000-4000-8000-000000000001'
WHERE NOT EXISTS (SELECT 1 FROM public.metas_configuracao c WHERE c.tenant_id = 'd3e00000-0000-4000-8000-000000000001');

-- ---------------------------------------------------------------------------
-- (7) Metas (32): estrategicas > unidade > setor > individual
--     Datas em relacao ao inicio do ano corrente (ys): trimestres Q1 0-89, Q2 90-180,
--     Q3 181-272, Q4 273-364; "hoje" fica sempre dentro do ultimo trimestre aberto.
-- ---------------------------------------------------------------------------
INSERT INTO public.metas (
  id, tenant_id, empresa_id, titulo, descricao, nivel, tipo, periodo, ano, trimestre, data_inicio, data_fim, peso,
  status, workflow_status, progresso, meta_pai_id, indicador_nome, indicador_tipo, indicador_unidade, indicador_direcao,
  valor_baseline, valor_alvo, valor_atual, objetivo_estrategico, unidade_nome, setor_id, setor_nome,
  departamento_id, departamento_nome, colaborador_id, colaborador_nome, responsavel_id, responsavel_nome,
  aprovador_nome, data_aprovacao, risco_nivel, risco_descricao, compartilhada, tags, vinculo_ciclo_id,
  criado_por_nome, created_at, updated_at, versao
)
SELECT public.demo_id('meta:' || m.chave), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       m.titulo, m.descricao, m.nivel::public.meta_nivel,
       CASE m.nivel WHEN 'individual' THEN 'individual' WHEN 'setor' THEN 'equipe' ELSE 'departamento' END,
       m.periodo::public.meta_periodo,
       EXTRACT(YEAR FROM (date_trunc('year', CURRENT_DATE)::date + m.ini))::int, m.tri,
       date_trunc('year', CURRENT_DATE)::date + m.ini, date_trunc('year', CURRENT_DATE)::date + m.fim, m.peso,
       CASE WHEN m.wf = 'cancelada' THEN 'cancelada'::public.meta_status
            WHEN m.prog >= 100 THEN 'concluida'::public.meta_status
            WHEN m.prog > 0 AND m.wf IN ('ativa','em_revisao','suspensa','encerrada')
                 AND date_trunc('year', CURRENT_DATE)::date + m.fim < CURRENT_DATE THEN 'atrasada'::public.meta_status
            WHEN m.prog > 0 THEN 'em_andamento'::public.meta_status
            ELSE 'nao_iniciada'::public.meta_status END,
       m.wf::public.meta_workflow_status, m.prog,
       CASE WHEN m.pai IS NOT NULL THEN public.demo_id('meta:' || m.pai) END,
       m.ind, m.ind_tipo::public.indicador_tipo, m.un, m.dir::public.indicador_direcao,
       m.base, m.alvo,
       CASE WHEN m.base IS NOT NULL THEN round((m.base + (m.alvo - m.base) * m.prog / 100.0)::numeric, 2) END,
       m.obj, m.unidade,
       CASE WHEN m.setor IS NOT NULL THEN public.demo_id('depto:' || m.setor) END, m.setor,
       CASE WHEN m.setor IS NOT NULL THEN public.demo_id('depto:' || m.setor) END, m.setor,
       CASE WHEN m.colab IS NOT NULL THEN public.demo_id('admissao:' || m.colab)::text END,
       (SELECT a.nome_completo FROM public.admissoes a WHERE a.id = public.demo_id('admissao:' || m.colab)),
       CASE WHEN COALESCE(m.colab, m.resp) IS NOT NULL THEN public.demo_id('admissao:' || COALESCE(m.colab, m.resp))::text
            ELSE (SELECT u.id::text FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' LIMIT 1) END,
       COALESCE((SELECT a.nome_completo FROM public.admissoes a WHERE a.id = public.demo_id('admissao:' || COALESCE(m.colab, m.resp))), 'Leiri'),
       CASE WHEN m.wf IN ('ativa','encerrada','em_revisao','suspensa') THEN 'Leiri' END,
       CASE WHEN m.wf IN ('ativa','encerrada','em_revisao','suspensa')
            THEN now() + (date_trunc('year', CURRENT_DATE)::date + m.ini - CURRENT_DATE + 3) * interval '1 day' END,
       m.risco, m.risco_desc, m.partic, m.tags,
       CASE WHEN m.nivel = 'individual' AND m.wf <> 'cancelada' THEN public.demo_id('avciclo:c4') END,
       'Leiri',
       LEAST(now() - interval '2 days', now() + (date_trunc('year', CURRENT_DATE)::date + m.ini - CURRENT_DATE - 5) * interval '1 day'),
       now() - (1 + public.demo_dev_rnd(m.chave || 'upd', 12)) * interval '1 day', 1
FROM (VALUES
  -- chave, pai, nivel, periodo, tri, ini, fim, peso, wf, prog, titulo, descricao, obj, ind, ind_tipo, un, dir, base, alvo, setor, unidade, colab, resp, risco, risco_desc, partic, tags
  ('est_oee', NULL, 'estrategica', 'anual', NULL, 0, 364, 3, 'ativa', 52, 'Elevar o OEE da fábrica de 68% para 80%', 'Aumentar a eficiência global dos equipamentos reduzindo paradas não planejadas, setups longos e refugo.', 'Excelência operacional', 'OEE', 'percentual', '%', 'maior_melhor', 68, 80, NULL, 'Matriz', NULL, NULL, NULL, NULL, false, ARRAY['operacoes','oee']),
  ('est_acid', NULL, 'estrategica', 'anual', NULL, 0, 364, 3, 'ativa', 70, 'Zerar acidentes com afastamento até dezembro', 'Consolidar a cultura de segurança: inspeções, DDS semanais, treinamentos de NR-12/NR-35 e uso correto de EPIs.', 'Segurança em primeiro lugar', 'Taxa de frequência de acidentes', 'quantitativo', 'acidentes/milhão h', 'menor_melhor', 4.2, 0, NULL, 'Matriz', NULL, NULL, NULL, NULL, true, ARRAY['sst','seguranca']),
  ('est_turn', NULL, 'estrategica', 'anual', NULL, 0, 364, 2, 'ativa', 58, 'Reduzir o turnover voluntário de 14% para 8%', 'Retenção de talentos: plano de carreira, PDI, pesquisa de clima e revisão de benefícios.', 'Retenção de talentos', 'Turnover voluntário', 'percentual', '%', 'menor_melhor', 14, 8, NULL, 'Matriz', NULL, NULL, 'medio', 'Dois pedidos de demissão no último trimestre concentrados na usinagem.', false, ARRAY['pessoas','retencao']),
  ('est_otif', NULL, 'estrategica', 'anual', NULL, 0, 364, 3, 'ativa', 66, 'Atingir 98% de entregas no prazo e completas (OTIF)', 'Melhorar a pontualidade de entrega ao cliente integrando programação de produção e expedição.', 'Satisfação do cliente', 'OTIF', 'percentual', '%', 'maior_melhor', 91, 98, NULL, 'Matriz', NULL, NULL, NULL, NULL, false, ARRAY['clientes','logistica']),
  ('est_iso', NULL, 'estrategica', 'anual', NULL, -365, -1, 2, 'encerrada', 100, 'Renovar a certificação ISO 9001:2015 (2025)', 'Auditoria de recertificação concluída sem não conformidades maiores.', 'Qualidade certificada', 'Certificação ISO 9001', 'marco', 'marco', 'maior_melhor', 0, 100, NULL, 'Matriz', NULL, NULL, NULL, NULL, false, ARRAY['qualidade','iso']),
  ('est_cd', NULL, 'estrategica', 'anual', NULL, 285, 364, 2, 'em_aprovacao', 0, 'Ampliar em 20% a capacidade do CD Itajaí', 'Estudo e contratação de nova área de armazenagem para suportar o crescimento previsto de pedidos.', 'Crescimento sustentável', 'Área de armazenagem', 'quantitativo', 'm²', 'maior_melhor', 4000, 4800, NULL, 'Centro de Distribuição Itajaí', NULL, NULL, NULL, NULL, false, ARRAY['expansao']),
  ('uni_mat3', 'est_oee', 'unidade', 'trimestral', 3, 181, 272, 2, 'encerrada', 100, 'Cumprir 100% do plano de produção — Matriz (3º tri)', 'Aderência ao plano mensal de produção da matriz no terceiro trimestre.', 'Excelência operacional', 'Aderência ao plano de produção', 'percentual', '%', 'maior_melhor', 92, 100, NULL, 'Matriz', NULL, NULL, NULL, NULL, false, ARRAY['producao']),
  ('uni_mat4', 'est_oee', 'unidade', 'trimestral', 4, 273, 364, 2, 'ativa', 38, 'Cumprir 100% do plano de produção — Matriz (4º tri)', 'Aderência ao plano de produção no quarto trimestre, com pico de pedidos em novembro.', 'Excelência operacional', 'Aderência ao plano de produção', 'percentual', '%', 'maior_melhor', 92, 100, NULL, 'Matriz', NULL, NULL, NULL, NULL, false, ARRAY['producao']),
  ('uni_cwb', 'est_oee', 'unidade', 'semestral', NULL, 181, 364, 2, 'ativa', 35, 'Reduzir o retrabalho da Filial Curitiba para 3%', 'Padronizar a montagem e o checklist de qualidade na filial.', 'Excelência operacional', 'Índice de retrabalho', 'percentual', '%', 'menor_melhor', 6.5, 3, NULL, 'Filial Curitiba', NULL, NULL, 'alto', 'Retrabalho acima do limite em dois lotes recentes.', false, ARRAY['qualidade']),
  ('uni_itj', 'est_otif', 'unidade', 'trimestral', 3, 181, 272, 2, 'ativa', 80, 'Expedir pedidos em até 24 horas — CD Itajaí', 'Reduzir o tempo entre a separação e a saída do caminhão.', 'Satisfação do cliente', 'Tempo de expedição', 'quantitativo', 'horas', 'menor_melhor', 40, 24, NULL, 'Centro de Distribuição Itajaí', NULL, NULL, 'medio', 'Meta vencida: faltam ajustes no turno da tarde.', false, ARRAY['logistica']),
  ('set_prod', 'uni_mat4', 'setor', 'trimestral', 4, 273, 364, 2, 'ativa', 45, 'Reduzir o refugo de usinagem para 1,5%', 'Ajustes de setup, manutenção de ferramentas e treinamento dos operadores CNC.', 'Excelência operacional', 'Refugo de usinagem', 'percentual', '%', 'menor_melhor', 3.2, 1.5, 'Produção', 'Matriz', NULL, 28, NULL, NULL, true, ARRAY['producao','refugo']),
  ('set_manut', 'est_oee', 'setor', 'trimestral', 3, 181, 272, 2, 'ativa', 60, 'Elevar a disponibilidade das máquinas para 95%', 'Plano de manutenção preventiva e preditiva nas máquinas críticas.', 'Excelência operacional', 'Disponibilidade de máquinas', 'percentual', '%', 'maior_melhor', 88, 95, 'Manutenção', 'Matriz', NULL, 40, 'medio', 'Duas máquinas CNC aguardam peças de reposição.', true, ARRAY['manutencao']),
  ('set_log', 'est_otif', 'setor', 'trimestral', 4, 273, 364, 2, 'ativa', 20, 'Reduzir a divergência de inventário para 0,5%', 'Inventário rotativo semanal e conferência cega no recebimento.', 'Satisfação do cliente', 'Divergência de inventário', 'percentual', '%', 'menor_melhor', 1.8, 0.5, 'Logística', 'Matriz', NULL, 52, NULL, NULL, false, ARRAY['estoque']),
  ('set_adm', 'est_otif', 'setor', 'trimestral', 3, 181, 272, 1, 'encerrada', 100, 'Fechar o mês contábil em D+5', 'Fechamento mensal concluído até o 5º dia útil em todos os meses do trimestre.', 'Governança financeira', 'Dias para fechamento', 'quantitativo', 'dias úteis', 'menor_melhor', 9, 5, 'Administrativo', 'Matriz', NULL, 53, NULL, NULL, false, ARRAY['financeiro']),
  ('set_rh', 'est_turn', 'setor', 'trimestral', 4, 273, 364, 2, 'ativa', 55, 'Reduzir o tempo médio de contratação para 25 dias', 'Funil de recrutamento padronizado, banco de talentos e agenda fixa de entrevistas.', 'Retenção de talentos', 'Tempo médio de contratação', 'quantitativo', 'dias', 'menor_melhor', 38, 25, 'Recursos Humanos', 'Matriz', NULL, NULL, NULL, NULL, false, ARRAY['rh']),
  ('set_com', 'est_otif', 'setor', 'trimestral', 4, 273, 364, 1, 'em_revisao', 30, 'Converter 25% das propostas em pedidos', 'Revisão de preços e acompanhamento ativo das propostas em aberto.', 'Crescimento sustentável', 'Taxa de conversão de propostas', 'percentual', '%', 'maior_melhor', 18, 25, 'Comercial', 'Matriz', NULL, NULL, 'baixo', 'Meta em revisão: alvo será reajustado após fechamento de novembro.', false, ARRAY['vendas']),
  ('set_sst', 'est_acid', 'setor', 'semestral', NULL, 181, 364, 2, 'ativa', 85, 'Treinar 100% da equipe em NR-12 e NR-35', 'Cobertura de treinamentos obrigatórios de máquinas e trabalho em altura.', 'Segurança em primeiro lugar', 'Colaboradores treinados', 'percentual', '%', 'maior_melhor', 60, 100, 'Recursos Humanos', 'Matriz', NULL, NULL, NULL, NULL, true, ARRAY['sst','treinamento']),
  ('i28', 'set_prod', 'individual', 'trimestral', 4, 273, 364, 2, 'ativa', 40, 'Zerar não conformidades de solda no turno A', 'Inspeção visual das juntas, registro das NCs e reforço do procedimento de soldagem.', 'Excelência operacional', 'Não conformidades de solda', 'quantitativo', 'NCs/mês', 'menor_melhor', 6, 0, 'Produção', 'Matriz', 28, NULL, NULL, NULL, false, ARRAY['solda']),
  ('i29', 'set_prod', 'individual', 'trimestral', 3, 181, 272, 2, 'encerrada', 100, 'Implantar o 5S nas 3 células de montagem', 'Auditorias 5S quinzenais com pontuação mínima de 85%.', 'Excelência operacional', 'Pontuação 5S', 'percentual', '%', 'maior_melhor', 60, 85, 'Produção', 'Matriz', 29, NULL, NULL, NULL, false, ARRAY['5s']),
  ('i40', 'set_manut', 'individual', 'semestral', NULL, 181, 364, 2, 'ativa', 60, 'Implantar manutenção preditiva em 5 máquinas CNC', 'Sensores de vibração e rotina de análise mensal.', 'Excelência operacional', 'Máquinas com preditiva', 'quantitativo', 'máquinas', 'maior_melhor', 0, 5, 'Manutenção', 'Matriz', 40, NULL, NULL, NULL, false, ARRAY['preditiva']),
  ('i52', 'set_log', 'individual', 'trimestral', 4, 273, 364, 2, 'ativa', 25, 'Reduzir em 30% as avarias na expedição', 'Padronizar embalagens e treinar a equipe de carregamento.', 'Satisfação do cliente', 'Avarias na expedição', 'quantitativo', 'ocorrências/mês', 'menor_melhor', 10, 7, 'Logística', 'Matriz', 52, NULL, NULL, NULL, false, ARRAY['expedicao']),
  ('i30', 'set_manut', 'individual', 'trimestral', 3, 181, 272, 1, 'ativa', 90, 'Executar 100% dos preventivos no prazo', 'Cumprir o cronograma de preventivas das prensas e tornos.', 'Excelência operacional', 'Preventivas no prazo', 'percentual', '%', 'maior_melhor', 78, 100, 'Manutenção', 'Matriz', 30, NULL, 'baixo', 'Falta concluir 2 preventivas pendentes de peça.', false, ARRAY['preventiva']),
  ('i36', 'set_manut', 'individual', 'semestral', NULL, 181, 364, 2, 'ativa', 70, 'Concluir a adequação NR-10 dos quadros elétricos', 'Identificar, sinalizar e aterrar 100% dos quadros da planta.', 'Segurança em primeiro lugar', 'Quadros adequados', 'percentual', '%', 'maior_melhor', 35, 100, 'Manutenção', 'Filial Curitiba', 36, NULL, NULL, NULL, false, ARRAY['nr10']),
  ('i53', 'set_adm', 'individual', 'trimestral', 4, 273, 364, 1, 'ativa', 50, 'Reduzir o DSO de 48 para 40 dias', 'Régua de cobrança automatizada e revisão de limites de crédito.', 'Governança financeira', 'DSO', 'quantitativo', 'dias', 'menor_melhor', 48, 40, 'Administrativo', 'Matriz', 53, NULL, NULL, NULL, false, ARRAY['cobranca']),
  ('i55', 'set_adm', 'individual', 'semestral', NULL, 181, 364, 1, 'ativa', 75, 'Concluir 12 auditorias internas do sistema da qualidade', 'Calendário anual de auditorias internas com relatório de ações corretivas.', 'Qualidade certificada', 'Auditorias concluídas', 'quantitativo', 'auditorias', 'maior_melhor', 0, 12, 'Administrativo', 'Centro de Distribuição Itajaí', 55, NULL, NULL, NULL, false, ARRAY['auditoria']),
  ('i56', 'set_adm', 'individual', 'trimestral', 3, 181, 272, 1, 'encerrada', 100, 'Fechar 90% das não conformidades em até 30 dias', 'Acompanhamento semanal dos planos de ação corretiva.', 'Qualidade certificada', 'NCs fechadas no prazo', 'percentual', '%', 'maior_melhor', 70, 90, 'Administrativo', 'Matriz', 56, NULL, NULL, NULL, false, ARRAY['qualidade']),
  ('i58', 'set_rh', 'individual', 'trimestral', 4, 273, 364, 1, 'rascunho', 0, 'Revisar 100% das descrições de cargo', 'Atualizar objetivo da função, responsabilidades e exames dos 16 cargos.', 'Governança de pessoas', 'Cargos revisados', 'percentual', '%', 'maior_melhor', 0, 100, 'Recursos Humanos', 'Matriz', 58, NULL, NULL, NULL, false, ARRAY['cargos']),
  ('i59', 'set_rh', 'individual', 'trimestral', 4, 273, 364, 1, 'em_aprovacao', 0, 'Aplicar a pesquisa de clima e montar o plano de ação', 'Pesquisa anônima com participação mínima de 80% e plano de ação em até 30 dias.', 'Retenção de talentos', 'Participação na pesquisa', 'percentual', '%', 'maior_melhor', 0, 80, 'Recursos Humanos', 'Matriz', 59, NULL, NULL, NULL, false, ARRAY['clima']),
  ('i13', 'set_prod', 'individual', 'anual', NULL, 0, 364, 1, 'ativa', 65, 'Obter a qualificação de soldador nível 2', 'Concluir as horas práticas e a prova de qualificação do processo MIG/MAG.', 'Excelência operacional', 'Etapas da qualificação', 'quantitativo', 'etapas', 'maior_melhor', 0, 4, 'Produção', 'Matriz', 13, NULL, NULL, NULL, false, ARRAY['qualificacao']),
  ('i1', 'set_prod', 'individual', 'mensal', NULL, 273, 303, 1, 'ativa', 40, 'Reduzir o tempo de setup de 45 para 30 minutos', 'Padronizar ferramentas e preparar o próximo lote com o equipamento em operação.', 'Excelência operacional', 'Tempo de setup', 'quantitativo', 'min', 'menor_melhor', 45, 30, 'Produção', 'Matriz', 1, NULL, NULL, NULL, false, ARRAY['setup']),
  ('i41', 'set_log', 'individual', 'mensal', NULL, 243, 272, 1, 'encerrada', 100, 'Zero incidentes na movimentação com empilhadeira (setembro)', 'Checklist diário da empilhadeira e circulação sinalizada.', 'Segurança em primeiro lugar', 'Incidentes de movimentação', 'quantitativo', 'incidentes', 'menor_melhor', 2, 0, 'Logística', 'Matriz', 41, NULL, NULL, NULL, false, ARRAY['empilhadeira']),
  ('i17', 'set_prod', 'individual', 'semestral', NULL, 181, 364, 1, 'cancelada', 20, 'Certificação de solda posição 6G', 'Cancelada: a certificação passou a ser conduzida por entidade externa em 2027.', 'Excelência operacional', 'Etapas da certificação', 'quantitativo', 'etapas', 'maior_melhor', 0, 5, 'Produção', 'Matriz', 17, NULL, NULL, NULL, false, ARRAY['certificacao'])
) AS m(chave, pai, nivel, periodo, tri, ini, fim, peso, wf, prog, titulo, descricao, obj, ind, ind_tipo, un, dir, base, alvo, setor, unidade, colab, resp, risco, risco_desc, partic, tags)
WHERE NOT EXISTS (SELECT 1 FROM public.metas x WHERE x.id = public.demo_id('meta:' || m.chave));

-- ---------------------------------------------------------------------------
-- (8) OKRs (key results) das metas e seus check-ins
--     O valor atual de cada KR acompanha o progresso da meta (com pequena variacao).
-- ---------------------------------------------------------------------------
INSERT INTO public.meta_okrs (
  id, tenant_id, meta_id, key_result, descricao, tipo, valor_inicial, valor_atual, valor_alvo, unidade,
  progresso, status, responsavel_id, responsavel_nome, created_at, updated_at
)
SELECT public.demo_id('okr:' || k.chave), 'd3e00000-0000-4000-8000-000000000001', m.id,
       k.kr, k.descr, k.tipo::public.okr_tipo, k.vi,
       round((k.vi + (k.va - k.vi) * pr.p / 100.0)::numeric, 1), k.va, k.un,
       pr.p::int,
       CASE WHEN m.status = 'cancelada' THEN 'cancelada'::public.meta_status
            WHEN pr.p >= 100 THEN 'concluida'::public.meta_status
            WHEN pr.p > 0 AND m.data_fim < CURRENT_DATE THEN 'atrasada'::public.meta_status
            WHEN pr.p > 0 THEN 'em_andamento'::public.meta_status
            ELSE 'nao_iniciada'::public.meta_status END,
       m.responsavel_id::uuid, m.responsavel_nome, m.created_at, now() - interval '3 days'
FROM (VALUES
  -- chave, meta, key result, descricao, tipo, unidade, inicial, alvo, ajuste do progresso
  ('set_prod:1', 'set_prod', 'Refugo da célula CNC A', 'Percentual de peças refugadas na célula A', 'percentual', '%', 3.2, 1.5, 5),
  ('set_prod:2', 'set_prod', 'Refugo da célula CNC B', 'Percentual de peças refugadas na célula B', 'percentual', '%', 3.0, 1.5, -5),
  ('set_prod:3', 'set_prod', 'Operadores treinados em setup rápido', 'Total de operadores CNC com o treinamento concluído', 'quantidade', 'operadores', 0, 12, 10),
  ('set_manut:1', 'set_manut', 'Disponibilidade das máquinas críticas', 'Horas disponíveis / horas programadas', 'percentual', '%', 88, 95, 0),
  ('set_manut:2', 'set_manut', 'Paradas não planejadas', 'Horas de parada corretiva por mês', 'quantidade', 'h/mês', 40, 16, 10),
  ('set_log:1', 'set_log', 'Inventários rotativos realizados', 'Contagens semanais concluídas no trimestre', 'quantidade', 'contagens', 0, 12, 0),
  ('set_log:2', 'set_log', 'Divergência de inventário', 'Percentual de itens com divergência', 'percentual', '%', 1.8, 0.5, 0),
  ('set_rh:1', 'set_rh', 'Tempo médio de contratação', 'Dias entre abertura e admissão', 'quantidade', 'dias', 38, 25, 5),
  ('set_rh:2', 'set_rh', 'Vagas com perfil de cargo atualizado', 'Percentual de vagas abertas com descrição revisada', 'percentual', '%', 40, 100, -10),
  ('set_sst:1', 'set_sst', 'Treinados em NR-12', 'Colaboradores de máquinas com NR-12 em dia', 'percentual', '%', 60, 100, 5),
  ('set_sst:2', 'set_sst', 'Treinados em NR-35', 'Colaboradores em altura com NR-35 em dia', 'percentual', '%', 55, 100, -5),
  ('set_com:1', 'set_com', 'Taxa de conversão de propostas', 'Pedidos / propostas enviadas', 'percentual', '%', 18, 25, 0),
  ('uni_cwb:1', 'uni_cwb', 'Retrabalho na linha de montagem', 'Percentual de peças retrabalhadas', 'percentual', '%', 6.5, 3, 0),
  ('uni_cwb:2', 'uni_cwb', 'Checklist de qualidade aplicado', 'Lotes com checklist completo', 'percentual', '%', 50, 100, 5),
  ('uni_mat4:1', 'uni_mat4', 'Aderência ao plano — outubro', 'Percentual do plano mensal executado', 'percentual', '%', 92, 100, 0),
  ('uni_itj:1', 'uni_itj', 'Tempo médio de expedição', 'Horas entre separação e saída do caminhão', 'quantidade', 'horas', 40, 24, 0),
  ('uni_itj:2', 'uni_itj', 'Pedidos expedidos em até 24 h', 'Percentual dos pedidos do mês', 'percentual', '%', 62, 95, 0),
  ('i28:1', 'i28', 'Não conformidades de solda por mês', 'Total de NCs registradas no turno A', 'quantidade', 'NCs', 6, 0, 0),
  ('i28:2', 'i28', 'Soldadores com reciclagem do procedimento', 'Reciclagem do procedimento de soldagem', 'quantidade', 'soldadores', 0, 9, 10),
  ('i29:1', 'i29', 'Pontuação média nas auditorias 5S', 'Média das auditorias quinzenais', 'percentual', '%', 60, 85, 0),
  ('i29:2', 'i29', 'Células auditadas', 'Células de montagem com 5S implantado', 'quantidade', 'células', 0, 3, 0),
  ('i40:1', 'i40', 'Máquinas com sensor de vibração', 'Instalação dos sensores nas CNC', 'quantidade', 'máquinas', 0, 5, 0),
  ('i40:2', 'i40', 'Laudos mensais de análise', 'Relatórios de análise emitidos', 'quantidade', 'laudos', 0, 6, -10),
  ('i52:1', 'i52', 'Avarias por mês', 'Ocorrências de avaria na expedição', 'quantidade', 'ocorrências', 10, 7, 0),
  ('i30:1', 'i30', 'Preventivas executadas no prazo', 'Percentual do cronograma cumprido', 'percentual', '%', 78, 100, 0),
  ('i36:1', 'i36', 'Quadros elétricos adequados', 'Quadros identificados, sinalizados e aterrados', 'percentual', '%', 35, 100, 0),
  ('i36:2', 'i36', 'Prontuário NR-10 atualizado', 'Documentos do prontuário revisados', 'percentual', '%', 20, 100, 10),
  ('i53:1', 'i53', 'DSO (dias)', 'Prazo médio de recebimento', 'quantidade', 'dias', 48, 40, 0),
  ('i53:2', 'i53', 'Clientes na régua de cobrança', 'Percentual de clientes com cobrança automática', 'percentual', '%', 0, 100, 10),
  ('i55:1', 'i55', 'Auditorias internas concluídas', 'Auditorias do calendário anual', 'quantidade', 'auditorias', 0, 12, 0),
  ('i56:1', 'i56', 'NCs fechadas em até 30 dias', 'Percentual de NCs fechadas no prazo', 'percentual', '%', 70, 90, 0),
  ('i13:1', 'i13', 'Etapas da qualificação concluídas', 'Horas práticas, teoria, prova e laudo', 'quantidade', 'etapas', 0, 4, 0),
  ('i1:1', 'i1', 'Tempo de setup', 'Minutos para trocar de ordem na CNC', 'quantidade', 'min', 45, 30, 0),
  ('est_oee:1', 'est_oee', 'OEE médio da fábrica', 'OEE consolidado das linhas de usinagem e solda', 'percentual', '%', 68, 80, 0),
  ('est_oee:2', 'est_oee', 'Setup médio das CNC', 'Redução do tempo de setup', 'quantidade', 'min', 45, 30, 10),
  ('est_oee:3', 'est_oee', 'Refugo médio', 'Percentual de refugo da usinagem', 'percentual', '%', 3.2, 1.5, -10),
  ('est_acid:1', 'est_acid', 'Taxa de frequência de acidentes', 'Acidentes com afastamento por milhão de horas', 'quantidade', 'taxa', 4.2, 0, 0),
  ('est_acid:2', 'est_acid', 'Inspeções de segurança realizadas', 'Inspeções mensais nas áreas produtivas', 'quantidade', 'inspeções', 0, 36, 10),
  ('est_turn:1', 'est_turn', 'Turnover voluntário (12 meses)', 'Pedidos de demissão / efetivo médio', 'percentual', '%', 14, 8, 0),
  ('est_turn:2', 'est_turn', 'PDIs ativos', 'Colaboradores com PDI em andamento', 'quantidade', 'PDIs', 0, 40, 5),
  ('est_otif:1', 'est_otif', 'OTIF mensal', 'Pedidos entregues no prazo e completos', 'percentual', '%', 91, 98, 0),
  ('est_otif:2', 'est_otif', 'Pedidos atrasados', 'Pedidos com atraso superior a 2 dias', 'quantidade', 'pedidos', 38, 8, -10)
) AS k(chave, meta, kr, descr, tipo, un, vi, va, aj)
JOIN public.metas m ON m.id = public.demo_id('meta:' || k.meta)
CROSS JOIN LATERAL (SELECT GREATEST(0, LEAST(100, m.progresso + k.aj)) AS p) pr
WHERE NOT EXISTS (SELECT 1 FROM public.meta_okrs o WHERE o.id = public.demo_id('okr:' || k.chave));

-- Check-ins dos OKRs: 3 por KR (cerca de 8, 4 e 1 semana atras) chegando ao valor atual.
INSERT INTO public.okr_checkins (
  id, tenant_id, okr_id, valor_anterior, valor_novo, observacao, realizado_por_nome, created_at
)
SELECT public.demo_id('okrchk:' || o.id::text || ':' || s.i), 'd3e00000-0000-4000-8000-000000000001', o.id,
       round((o.valor_inicial + (o.valor_atual - o.valor_inicial) * (s.f_ant)::numeric)::numeric, 1),
       round((o.valor_inicial + (o.valor_atual - o.valor_inicial) * (s.f)::numeric)::numeric, 1),
       (ARRAY['Atualização mensal conforme apontamento.',
              'Avanço dentro do previsto; equipe engajada.',
              'Ritmo abaixo do esperado por falta de peças; ação corretiva aberta.',
              'Resultado validado com o gestor na reunião de acompanhamento.'])[1 + public.demo_dev_rnd(o.id::text || s.i, 4)],
       o.responsavel_nome, now() - s.dias * interval '1 day'
FROM public.meta_okrs o
CROSS JOIN (VALUES (1, 0.0, 0.4, 56), (2, 0.4, 0.75, 28), (3, 0.75, 1.0, 6)) AS s(i, f_ant, f, dias)
WHERE o.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
  AND o.progresso > 0
  AND NOT EXISTS (SELECT 1 FROM public.okr_checkins c WHERE c.id = public.demo_id('okrchk:' || o.id::text || ':' || s.i));

-- ---------------------------------------------------------------------------
-- (9) Trilha de aprovacao (workflow) e participantes
-- ---------------------------------------------------------------------------
INSERT INTO public.metas_workflow_log (
  id, tenant_id, meta_id, status_anterior, status_novo, acao, justificativa, usuario_nome, created_at
)
SELECT public.demo_id('metawf:' || m.id::text || ':' || s.i), 'd3e00000-0000-4000-8000-000000000001', m.id,
       s.ant::public.meta_workflow_status, s.novo::public.meta_workflow_status, s.acao, s.just, 'Leiri',
       m.created_at + s.dias * interval '1 day'
FROM public.metas m
JOIN (VALUES
  (1, NULL, 'rascunho',     'criacao',    'Meta criada.',                                              0),
  (2, 'rascunho', 'em_aprovacao', 'envio',      'Enviada para aprovação da diretoria.',                      1),
  (3, 'em_aprovacao', 'ativa',    'aprovacao',  'Aprovada: indicador, alvo e prazo coerentes com o plano.',  3)
) AS s(i, ant, novo, acao, just, dias)
  ON (s.i = 1)
  OR (s.i = 2 AND m.workflow_status <> 'rascunho')
  OR (s.i = 3 AND m.workflow_status IN ('ativa','encerrada','em_revisao','suspensa'))
WHERE m.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
  AND NOT EXISTS (SELECT 1 FROM public.metas_workflow_log w WHERE w.id = public.demo_id('metawf:' || m.id::text || ':' || s.i));

INSERT INTO public.metas_workflow_log (
  id, tenant_id, meta_id, status_anterior, status_novo, acao, justificativa, usuario_nome, created_at
)
SELECT public.demo_id('metawf:' || m.id::text || ':enc'), 'd3e00000-0000-4000-8000-000000000001', m.id,
       'ativa'::public.meta_workflow_status, 'encerrada'::public.meta_workflow_status, 'encerramento',
       'Meta concluída e validada pelo gestor.', 'Leiri', now() - interval '12 days'
FROM public.metas m
WHERE m.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND m.workflow_status = 'encerrada' AND m.status = 'concluida'
  AND NOT EXISTS (SELECT 1 FROM public.metas_workflow_log w WHERE w.id = public.demo_id('metawf:' || m.id::text || ':enc'));

INSERT INTO public.metas_participantes (
  id, tenant_id, meta_id, participante_id, participante_nome, papel, peso, created_at
)
SELECT public.demo_id('metapart:' || v.meta || ':' || v.n), 'd3e00000-0000-4000-8000-000000000001',
       public.demo_id('meta:' || v.meta), a.id::text, a.nome_completo, v.papel, v.peso, now() - interval '40 days'
FROM (VALUES
  ('set_prod', 29, 'co_responsavel', 1), ('set_prod', 13, 'colaborador', 1), ('set_prod', 5, 'colaborador', 1),
  ('set_manut', 30, 'co_responsavel', 1), ('set_manut', 31, 'colaborador', 1), ('set_manut', 36, 'colaborador', 1),
  ('est_acid', 40, 'co_responsavel', 1), ('est_acid', 28, 'co_responsavel', 1), ('est_acid', 58, 'apoio', 1),
  ('set_sst', 58, 'co_responsavel', 1), ('set_sst', 59, 'apoio', 1)
) AS v(meta, n, papel, peso)
JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || v.n)
WHERE NOT EXISTS (SELECT 1 FROM public.metas_participantes p WHERE p.id = public.demo_id('metapart:' || v.meta || ':' || v.n));

-- ---------------------------------------------------------------------------
-- (10) Evidencias (somente links/descricoes; nenhum arquivo de storage)
-- ---------------------------------------------------------------------------
INSERT INTO public.metas_evidencias (
  id, tenant_id, meta_id, tipo, titulo, descricao, link_externo, periodo_referencia, criado_por_nome, created_at
)
SELECT public.demo_id('metaev:' || v.chave), 'd3e00000-0000-4000-8000-000000000001', public.demo_id('meta:' || v.meta),
       v.tipo, v.titulo, v.descr, v.link, v.periodo, 'Leiri', now() - v.dias * interval '1 day'
FROM (VALUES
  ('1', 'i29', 'link', 'Relatório das auditorias 5S (3º tri)', 'Planilha com as 6 auditorias quinzenais e a pontuação por célula.', 'https://docs.metalurgica-exemplo.demo/5s/auditorias-3tri', '3º trimestre', 25),
  ('2', 'uni_mat3', 'link', 'Painel de aderência ao plano', 'Painel do planejamento com 100% de aderência nos três meses.', 'https://docs.metalurgica-exemplo.demo/pcp/aderencia-3tri', '3º trimestre', 22),
  ('3', 'i56', 'descricao', 'Fechamento das NCs de setembro', 'Todas as 14 NCs do trimestre foram fechadas em até 30 dias; média de 21 dias.', NULL, '3º trimestre', 20),
  ('4', 'est_iso', 'link', 'Certificado ISO 9001 renovado', 'Certificado emitido pelo organismo certificador, validade de 3 anos.', 'https://docs.metalurgica-exemplo.demo/qualidade/certificado-iso-9001', '2025', 300),
  ('5', 'i40', 'descricao', 'Instalação dos sensores nas CNC 1 a 3', 'Fotos e laudo de instalação arquivados na pasta da manutenção.', NULL, '3º trimestre', 15),
  ('6', 'set_sst', 'link', 'Lista de presença NR-12', 'Listas de presença dos treinamentos de NR-12 realizados.', 'https://docs.metalurgica-exemplo.demo/sst/treinamentos-nr12', '2º semestre', 10),
  ('7', 'i36', 'descricao', 'Quadros adequados na Filial Curitiba', '14 de 20 quadros identificados, sinalizados e aterrados.', NULL, '2º semestre', 8)
) AS v(chave, meta, tipo, titulo, descr, link, periodo, dias)
WHERE NOT EXISTS (SELECT 1 FROM public.metas_evidencias e WHERE e.id = public.demo_id('metaev:' || v.chave));

-- ---------------------------------------------------------------------------
-- (11) Check-ins das metas (modulo /metas): 3 por meta com andamento.
--      O gatilho do banco aplica valor e progresso na meta; o ultimo check-in
--      de cada meta coincide com o valor atual ja gravado.
-- ---------------------------------------------------------------------------
INSERT INTO public.metas_checkins (
  id, tenant_id, meta_id, valor_anterior, valor_novo, progresso_anterior, progresso_novo, observacao, bloqueios,
  previsao_atingimento, realizado_por, realizado_por_nome, created_at
)
SELECT public.demo_id('metachk:' || m.id::text || ':' || s.i), 'd3e00000-0000-4000-8000-000000000001', m.id,
       CASE WHEN m.valor_baseline IS NOT NULL
            THEN round((m.valor_baseline + (m.valor_alvo - m.valor_baseline) * (m.progresso * s.f_ant / 100.0))::numeric, 2) END,
       CASE WHEN m.valor_baseline IS NOT NULL
            THEN round((m.valor_baseline + (m.valor_alvo - m.valor_baseline) * (m.progresso * s.f / 100.0))::numeric, 2) END,
       round(m.progresso * s.f_ant)::int, round(m.progresso * s.f)::int,
       (ARRAY['Atualização do período conforme apontamentos do setor.',
              'Avanço dentro do planejado; próximos passos alinhados com a equipe.',
              'Resultado validado na reunião mensal de acompanhamento.',
              'Entrega parcial concluída; ajustes de processo em andamento.'])[1 + public.demo_dev_rnd(m.id::text || s.i, 4)],
       CASE WHEN s.i = 3 AND m.status = 'atrasada' THEN 'Atraso por falta de peças de reposição e agenda de parada da linha.'
            WHEN s.i = 2 AND public.demo_dev_rnd(m.id::text || 'blq', 5) = 0 THEN 'Aguardando aprovação de compra de material.' END,
       CASE WHEN m.status IN ('em_andamento','atrasada') THEN CURRENT_DATE + 15 + public.demo_dev_rnd(m.id::text || 'prev', 40) END,
       m.responsavel_id, m.responsavel_nome, now() - s.dias * interval '1 day'
FROM public.metas m
CROSS JOIN (VALUES (1, 0.0, 0.4, 55), (2, 0.4, 0.75, 27), (3, 0.75, 1.0, 5)) AS s(i, f_ant, f, dias)
WHERE m.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
  AND m.progresso > 0 AND m.status <> 'cancelada'
  AND m.created_at < now() - s.dias * interval '1 day'
  AND NOT EXISTS (SELECT 1 FROM public.metas_checkins c WHERE c.id = public.demo_id('metachk:' || m.id::text || ':' || s.i));

-- O check-in devolve a meta para "em andamento"; a regra do modulo marca como
-- "atrasada" a meta ativa, vencida e incompleta (somente metas do tenant demo).
UPDATE public.metas
   SET status = 'atrasada'
 WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001'
   AND workflow_status IN ('ativa','em_revisao','suspensa')
   AND status = 'em_andamento'
   AND data_fim < CURRENT_DATE
   AND progresso < 100;

-- ---------------------------------------------------------------------------
-- Conferencia final
-- ---------------------------------------------------------------------------
SELECT
  (SELECT count(*) FROM public.avaliacao_templates WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS templates,
  (SELECT count(*) FROM public.avaliacao_ciclos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS ciclos,
  (SELECT count(*) FROM public.avaliacao_respostas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS respostas,
  (SELECT count(*) FROM public.avaliacao_9box WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS nine_box,
  (SELECT count(*) FROM public.metas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS metas,
  (SELECT count(*) FROM public.metas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND status = 'atrasada') AS metas_atrasadas,
  (SELECT count(*) FROM public.metas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND status = 'concluida') AS metas_concluidas,
  (SELECT count(*) FROM public.meta_okrs WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS okrs,
  (SELECT count(*) FROM public.okr_checkins WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS okr_checkins,
  (SELECT count(*) FROM public.metas_checkins WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS metas_checkins,
  (SELECT count(*) FROM public.metas_workflow_log WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS metas_workflow,
  CASE WHEN (SELECT count(*) FROM public.avaliacao_ciclos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') = 4
        AND (SELECT count(*) FROM public.metas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') = 32
       THEN 'OK' ELSE 'CONFERIR' END AS situacao;
