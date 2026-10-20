-- ============================================================================
-- HOMOLOGACAO — DEMONSTRACAO, PARTE 05c: Trilhas de aprendizagem + Academia
--
-- PARA QUE SERVE
-- Preenche /trilhas (Minhas Trilhas, Gamificacao, Analytics, Gestao) e /academia
-- (cursos, modulos, aulas, progresso, XP, medalhas e favoritos) da "Metalurgica
-- Exemplo Ltda" (100% ficticia). O Onboarding Gamificado (/onboarding-rh: modelos,
-- etapas, processos, indicadores) ja e semeado pela PARTE 02a e NAO e repetido aqui.
-- Depende da PARTE 00 (tenant, empresa, 64 colaboradores e o login da demo).
--
-- ONDE COLAR
-- SQL Editor do projeto de HOMOLOGACAO, depois da parte 00. O arquivo se RECUSA a
-- rodar fora da homologacao/teste (mesma trava da parte 00). Nunca na producao.
--
-- O QUE FAZ (tudo no tenant demo, empresa matriz)
--   1. 13 trilhas (11 ativas, 1 rascunho, 1 arquivada) com ~60 modulos de texto,
--      quizzes com perguntas, atribuicoes por departamento/colaborador/todos;
--   2. progresso de ~60 colaboradores (concluidos, parciais e parados), certificados
--      com codigo, 5 medalhas conquistadas, notificacoes e o progresso do proprio
--      login da demo (Minhas Trilhas, certificados e medalhas aparecem);
--   3. Academia: 4 categorias, 7 treinamentos de uso do sistema com modulos e aulas
--      em texto, progresso/XP/medalhas/favoritos do login da demo.
--
-- GARANTIAS
--   - Nenhum dado real; nomes e CPFs vem da parte 00 (ficticios).
--   - Idempotente: ids fixos (demo_id) + "so insere se nao existe".
--   - Nao cria tabela, nao apaga nada, nao altera linhas existentes.
--   - Sem arquivos de storage: videos/PDFs ficam fora (conteudo em texto); nenhuma
--     URL real e usada.
--   - Os certificados e medalhas sao gravados ANTES do progresso, para que o gatilho de
--     conclusao do banco (que geraria codigo aleatorio) nao crie linhas duplicadas.
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

-- ---------------------------------------------------------------------------
-- (1) Trilhas
-- ---------------------------------------------------------------------------
INSERT INTO public.trilhas (
  id, tenant_id, empresa_id, nome, descricao, objetivo, tipo, prioridade, visibilidade, status,
  pontuacao_minima, prazo_dias, conexao_pdi, criado_por_nome, created_at, updated_at
)
SELECT public.demo_id('trilha:' || v.chave), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       v.nome, v.descr, v.objetivo, v.tipo::public.trilha_tipo, v.prio::public.trilha_prioridade, 'publica'::public.trilha_visibilidade,
       v.status::public.trilha_status, v.minimo, v.prazo, false, 'Leiri',
       now() - v.idade * interval '1 day', now() - v.idade * interval '1 day'
FROM (VALUES
  ('integ', 'Integração e Segurança do Trabalho', 'Trilha de boas-vindas: regras de segurança, EPIs, rotas de emergência e rotina do posto de trabalho.', 'Garantir que todo novo colaborador comece o trabalho conhecendo os riscos e as regras de segurança.', 'onboarding', 'obrigatoria', 'ativa', 70, 30, 320),
  ('cultura', 'Cultura e Valores da Metalúrgica Exemplo', 'Conheça a história, a missão e os valores que orientam o dia a dia da empresa.', 'Alinhar comportamento e expectativas com a cultura da empresa.', 'cultura', 'obrigatoria', 'ativa', 60, 45, 310),
  ('nr12', 'NR-12 — Segurança em Máquinas e Equipamentos', 'Proteções, dispositivos de segurança, bloqueio e etiquetagem e inspeção das máquinas.', 'Reduzir acidentes com máquinas e atender à NR-12.', 'tecnica', 'obrigatoria', 'ativa', 70, 60, 290),
  ('nr35', 'NR-35 — Trabalho em Altura', 'Fundamentos e equipamentos de proteção contra quedas para quem atua em altura.', 'Habilitar a equipe de manutenção para trabalho seguro em altura.', 'tecnica', 'obrigatoria', 'ativa', 70, 90, 280),
  ('ergo', 'Ergonomia no Posto de Trabalho', 'Postura, pausas, organização do posto e prevenção de lesões por esforço repetitivo.', 'Prevenir queixas osteomusculares e afastamentos.', 'ergonomia_saude', 'recomendada', 'ativa', 60, 60, 240),
  ('lider', 'Liderança na Prática', 'Feedback, delegação, reunião de turno e gestão de conflitos para líderes e supervisores.', 'Preparar líderes para conduzir equipes com segurança e resultado.', 'lideranca', 'recomendada', 'ativa', 70, 120, 230),
  ('desenho', 'Leitura e Interpretação de Desenho Técnico', 'Vistas, cotas, tolerâncias e simbologia de soldagem aplicadas às ordens de produção.', 'Aumentar a autonomia dos operadores na leitura de desenhos.', 'tecnica', 'recomendada', 'ativa', 60, 90, 200),
  ('qual5s', 'Qualidade e 5S na Produção', 'Conceitos de qualidade, 5S, inspeção na fonte e tratamento de não conformidades.', 'Reduzir retrabalho e padronizar os postos.', 'processos', 'recomendada', 'ativa', 60, 60, 180),
  ('comun', 'Comunicação e Feedback', 'Como se comunicar com clareza, receber e dar feedback no dia a dia da fábrica.', 'Melhorar a comunicação entre turnos e setores.', 'comportamental', 'opcional', 'ativa', 50, 90, 150),
  ('empil', 'Operação Segura de Empilhadeira (NR-11)', 'Inspeção diária, movimentação segura de cargas e sinalização do pátio.', 'Zerar incidentes de movimentação interna.', 'tecnica', 'obrigatoria', 'ativa', 70, 60, 260),
  ('socorro', 'Primeiros Socorros e Brigada de Emergência', 'Atendimento inicial a acidentes, uso de extintores e abandono de área.', 'Formar a brigada e ampliar a cultura de resposta a emergências.', 'ergonomia_saude', 'opcional', 'ativa', 50, 120, 120),
  ('manut', 'Gestão da Manutenção (em construção)', 'Indicadores de manutenção, preventiva e preditiva. Conteúdo em elaboração.', 'Formar supervisores e técnicos em gestão de manutenção.', 'tecnica', 'recomendada', 'rascunho', 70, 90, 20),
  ('metro', 'Metrologia Básica (versão antiga)', 'Substituída pela trilha de Desenho Técnico e Metrologia.', 'Conteúdo arquivado.', 'tecnica', 'opcional', 'arquivada', 60, 60, 400)
) AS v(chave, nome, descr, objetivo, tipo, prio, status, minimo, prazo, idade)
WHERE NOT EXISTS (SELECT 1 FROM public.trilhas t WHERE t.id = public.demo_id('trilha:' || v.chave));

-- Modulos (conteudo em texto; o gatilho do banco atualiza o total de modulos da trilha)
INSERT INTO public.trilha_modulos (
  id, tenant_id, trilha_id, titulo, descricao, objetivo, tipo, conteudo_texto, tempo_estimado_min, pontuacao, ordem,
  evidencia_obrigatoria, competencia_relacionada, ativo, conteudos, created_at, updated_at
)
SELECT public.demo_id('trilhamod:' || v.trilha || ':' || v.ordem), 'd3e00000-0000-4000-8000-000000000001', t.id,
       v.titulo, 'Módulo ' || v.ordem || ' da trilha "' || t.nome || '".', 'Aplicar o conteúdo na rotina do posto de trabalho.',
       v.tipo::public.trilha_modulo_tipo,
       CASE v.tipo
         WHEN 'conteudo_interno' THEN 'Neste módulo você vai conhecer os pontos essenciais de "' || v.titulo || '" aplicados à rotina da Metalúrgica Exemplo. Leia com atenção e relacione cada ponto com as atividades do seu posto de trabalho. Em caso de dúvida, converse com o seu líder ou com o time de SST.'
         WHEN 'quiz' THEN 'Responda às perguntas para consolidar o conteúdo. A nota mínima de aprovação é definida na trilha; você pode refazer o quiz quantas vezes precisar.'
         WHEN 'checklist' THEN 'Confira cada item no seu posto de trabalho e marque como concluído. Itens pendentes devem ser comunicados ao líder no mesmo turno.'
         WHEN 'atividade_pratica' THEN 'Execute a atividade no seu setor, registre o resultado e anexe a evidência combinada com o líder (foto ou descrição do que foi feito).'
         WHEN 'reflexao' THEN 'Escreva com suas palavras como este tema aparece no seu dia a dia e o que você pode fazer de diferente a partir de hoje.'
         WHEN 'estudo_caso' THEN 'Leia o caso a seguir, discuta com seu líder e registre as lições aprendidas e as ações que poderiam evitar a ocorrência.'
         ELSE 'Complete o desafio rápido durante o turno e registre o resultado no campo de evidência.' END,
       v.min, v.pts, v.ordem, v.tipo IN ('atividade_pratica', 'estudo_caso'), v.comp, true,
       jsonb_build_array(jsonb_build_object('id', 'c1', 'tipo', 'texto', 'titulo', v.titulo,
         'texto', 'Conteúdo de apoio do módulo "' || v.titulo || '". Material de demonstração da Metalúrgica Exemplo.')),
       t.created_at, t.created_at
FROM (VALUES
  ('integ', 1, 'Boas-vindas à Metalúrgica Exemplo', 'conteudo_interno', 10, 10, 'Integração'),
  ('integ', 2, 'Regras de ouro de segurança e uso de EPIs', 'conteudo_interno', 15, 15, 'Segurança do trabalho'),
  ('integ', 3, 'Quiz: segurança no primeiro dia', 'quiz', 10, 20, 'Segurança do trabalho'),
  ('integ', 4, 'Checklist do posto de trabalho', 'checklist', 15, 15, 'Organização do posto'),
  ('integ', 5, 'Mapa de riscos e rotas de emergência', 'estudo_caso', 20, 20, 'Prevenção de acidentes'),
  ('integ', 6, 'Reflexão: o que me ajuda a trabalhar com segurança', 'reflexao', 10, 10, 'Autocuidado'),
  ('cultura', 1, 'Nossa história, missão e visão', 'conteudo_interno', 10, 10, 'Cultura'),
  ('cultura', 2, 'Os valores no dia a dia da fábrica', 'conteudo_interno', 15, 15, 'Cultura'),
  ('cultura', 3, 'Quiz: valores da empresa', 'quiz', 10, 20, 'Cultura'),
  ('cultura', 4, 'Reflexão guiada: um valor que me representa', 'reflexao', 10, 15, 'Autoconhecimento'),
  ('cultura', 5, 'Microdesafio: reconhecer um colega', 'microdesafio', 5, 10, 'Reconhecimento'),
  ('nr12', 1, 'Fundamentos da NR-12', 'conteudo_interno', 20, 15, 'NR-12'),
  ('nr12', 2, 'Proteções, dispositivos de segurança e paradas de emergência', 'conteudo_interno', 25, 20, 'NR-12'),
  ('nr12', 3, 'Procedimento de bloqueio e etiquetagem (LOTO)', 'estudo_caso', 20, 20, 'NR-12'),
  ('nr12', 4, 'Quiz NR-12', 'quiz', 15, 25, 'NR-12'),
  ('nr12', 5, 'Atividade prática: inspeção das proteções da máquina', 'atividade_pratica', 30, 20, 'NR-12'),
  ('nr35', 1, 'Fundamentos do trabalho em altura', 'conteudo_interno', 20, 20, 'NR-35'),
  ('nr35', 2, 'Equipamentos de proteção contra quedas', 'conteudo_interno', 20, 20, 'NR-35'),
  ('nr35', 3, 'Quiz NR-35', 'quiz', 15, 30, 'NR-35'),
  ('nr35', 4, 'Atividade prática: inspeção de cinto e talabarte', 'atividade_pratica', 30, 30, 'NR-35'),
  ('ergo', 1, 'Postura e organização do posto', 'conteudo_interno', 15, 15, 'Ergonomia'),
  ('ergo', 2, 'Pausas, alongamento e prevenção de lesões', 'conteudo_interno', 15, 15, 'Ergonomia'),
  ('ergo', 3, 'Checklist ergonômico do meu posto', 'checklist', 15, 15, 'Ergonomia'),
  ('ergo', 4, 'Quiz de ergonomia', 'quiz', 10, 20, 'Ergonomia'),
  ('ergo', 5, 'Microdesafio: uma semana de pausas ativas', 'microdesafio', 10, 15, 'Autocuidado'),
  ('lider', 1, 'O papel do líder no chão de fábrica', 'conteudo_interno', 20, 15, 'Liderança'),
  ('lider', 2, 'Como dar feedback que desenvolve', 'conteudo_interno', 20, 20, 'Feedback'),
  ('lider', 3, 'Delegação e acompanhamento', 'conteudo_interno', 20, 20, 'Delegação'),
  ('lider', 4, 'Estudo de caso: conflito entre turnos', 'estudo_caso', 25, 20, 'Gestão de conflitos'),
  ('lider', 5, 'Quiz de liderança', 'quiz', 15, 25, 'Liderança'),
  ('lider', 6, 'Atividade prática: conduzir uma reunião de início de turno', 'atividade_pratica', 30, 25, 'Liderança'),
  ('desenho', 1, 'Vistas, cortes e cotas', 'conteudo_interno', 25, 20, 'Desenho técnico'),
  ('desenho', 2, 'Tolerâncias e ajustes', 'conteudo_interno', 25, 20, 'Metrologia'),
  ('desenho', 3, 'Simbologia de soldagem', 'conteudo_interno', 20, 20, 'Soldagem'),
  ('desenho', 4, 'Quiz de leitura de desenho', 'quiz', 15, 25, 'Desenho técnico'),
  ('desenho', 5, 'Atividade prática: interpretar uma ordem de produção', 'atividade_pratica', 30, 25, 'Desenho técnico'),
  ('qual5s', 1, 'Os 5 sensos na prática', 'conteudo_interno', 15, 15, '5S'),
  ('qual5s', 2, 'Inspeção na fonte e autocontrole', 'conteudo_interno', 15, 15, 'Qualidade'),
  ('qual5s', 3, 'Checklist 5S do meu posto', 'checklist', 15, 15, '5S'),
  ('qual5s', 4, 'Quiz de qualidade', 'quiz', 10, 20, 'Qualidade'),
  ('qual5s', 5, 'Microdesafio: antes e depois do posto', 'microdesafio', 10, 15, '5S'),
  ('comun', 1, 'Comunicação clara entre turnos', 'conteudo_interno', 15, 15, 'Comunicação'),
  ('comun', 2, 'Receber feedback sem se defender', 'conteudo_interno', 15, 15, 'Feedback'),
  ('comun', 3, 'Reflexão: uma conversa difícil que tive', 'reflexao', 10, 15, 'Comunicação'),
  ('comun', 4, 'Quiz de comunicação', 'quiz', 10, 20, 'Comunicação'),
  ('empil', 1, 'Inspeção diária da empilhadeira', 'checklist', 15, 15, 'NR-11'),
  ('empil', 2, 'Movimentação segura de cargas', 'conteudo_interno', 20, 20, 'NR-11'),
  ('empil', 3, 'Circulação e sinalização do pátio', 'conteudo_interno', 15, 15, 'NR-11'),
  ('empil', 4, 'Quiz NR-11', 'quiz', 15, 25, 'NR-11'),
  ('empil', 5, 'Atividade prática: manobra com carga sob supervisão', 'atividade_pratica', 30, 25, 'NR-11'),
  ('socorro', 1, 'Avaliação da cena e acionamento do socorro', 'conteudo_interno', 15, 15, 'Primeiros socorros'),
  ('socorro', 2, 'Uso de extintores e combate a princípio de incêndio', 'conteudo_interno', 20, 20, 'Brigada'),
  ('socorro', 3, 'Estudo de caso: queimadura na área de solda', 'estudo_caso', 20, 20, 'Primeiros socorros'),
  ('socorro', 4, 'Quiz de emergência', 'quiz', 10, 20, 'Brigada'),
  ('manut', 1, 'Indicadores de manutenção (MTBF, MTTR)', 'conteudo_interno', 20, 15, 'Manutenção'),
  ('manut', 2, 'Preventiva x preditiva', 'conteudo_interno', 20, 15, 'Manutenção'),
  ('manut', 3, 'Quiz de manutenção', 'quiz', 10, 20, 'Manutenção'),
  ('metro', 1, 'Instrumentos de medição', 'conteudo_interno', 20, 15, 'Metrologia'),
  ('metro', 2, 'Calibração e incerteza', 'conteudo_interno', 20, 15, 'Metrologia'),
  ('metro', 3, 'Quiz de metrologia', 'quiz', 10, 20, 'Metrologia')
) AS v(trilha, ordem, titulo, tipo, min, pts, comp)
JOIN public.trilhas t ON t.id = public.demo_id('trilha:' || v.trilha)
WHERE NOT EXISTS (SELECT 1 FROM public.trilha_modulos m WHERE m.id = public.demo_id('trilhamod:' || v.trilha || ':' || v.ordem));

-- Perguntas dos quizzes (3 por quiz)
INSERT INTO public.trilha_quiz_perguntas (id, tenant_id, modulo_id, pergunta, opcoes, resposta_correta, ordem, created_at)
SELECT public.demo_id('trilhaquiz:' || v.trilha || ':' || v.modulo || ':' || v.ordem), 'd3e00000-0000-4000-8000-000000000001',
       public.demo_id('trilhamod:' || v.trilha || ':' || v.modulo), v.pergunta, v.opcoes, v.correta, v.ordem, now() - interval '250 days'
FROM (VALUES
  ('integ', 3, 1, 'Quando o uso de óculos de proteção é obrigatório?', ARRAY['Somente em soldas', 'Em toda a área produtiva sinalizada', 'Apenas quando há visita', 'Quando o líder está presente'], 1),
  ('integ', 3, 2, 'Ao perceber uma condição insegura, o que você deve fazer?', ARRAY['Ignorar se for rápido', 'Comunicar ao líder e sinalizar o local', 'Esperar o turno acabar', 'Resolver sozinho sem avisar'], 1),
  ('integ', 3, 3, 'Onde fica o ponto de encontro em caso de emergência?', ARRAY['Na portaria', 'No local indicado no mapa de riscos', 'No refeitório', 'Dentro do galpão'], 1),
  ('cultura', 3, 1, 'Qual valor orienta a decisão quando segurança e prazo entram em conflito?', ARRAY['Prazo acima de tudo', 'Segurança em primeiro lugar', 'Custo mínimo', 'Decisão do cliente'], 1),
  ('cultura', 3, 2, 'Reconhecer um colega que ajudou na entrega representa qual valor?', ARRAY['Respeito e colaboração', 'Competição interna', 'Individualismo', 'Hierarquia'], 0),
  ('cultura', 3, 3, 'A missão da empresa está ligada a:', ARRAY['Entregar qualidade com segurança e respeito às pessoas', 'Reduzir pessoal', 'Aumentar o estoque', 'Terceirizar a produção'], 0),
  ('nr12', 4, 1, 'O que é o bloqueio e etiquetagem (LOTO)?', ARRAY['Pintar a máquina', 'Impedir a energização durante a manutenção', 'Trocar o óleo', 'Registrar a produção'], 1),
  ('nr12', 4, 2, 'Uma proteção fixa pode ser removida para agilizar a produção?', ARRAY['Sim, se o turno estiver atrasado', 'Sim, com autorização verbal', 'Não, nunca sem procedimento formal', 'Somente à noite'], 2),
  ('nr12', 4, 3, 'A parada de emergência deve estar:', ARRAY['Escondida', 'Sempre acessível e sinalizada', 'Somente no painel central', 'Desativada na produção'], 1),
  ('nr35', 3, 1, 'A partir de qual altura o trabalho é considerado em altura?', ARRAY['1,0 m', '1,5 m', '2,0 m', '3,0 m'], 2),
  ('nr35', 3, 2, 'O talabarte deve ser fixado:', ARRAY['Em qualquer estrutura', 'Em ponto de ancoragem resistente e certificado', 'No corrimão', 'Na própria cintura'], 1),
  ('nr35', 3, 3, 'Antes de subir, o cinto deve ser:', ARRAY['Guardado', 'Inspecionado visualmente', 'Lavado', 'Emprestado'], 1),
  ('ergo', 4, 1, 'Qual a melhor prática de pausa em atividade repetitiva?', ARRAY['Nenhuma pausa', 'Pausas curtas e frequentes com alongamento', 'Uma pausa longa no fim do turno', 'Somente no almoço'], 1),
  ('ergo', 4, 2, 'A altura da bancada deve:', ARRAY['Ser a mesma para todos', 'Ser ajustada à altura do trabalhador e à tarefa', 'Ficar sempre baixa', 'Ficar sempre alta'], 1),
  ('ergo', 4, 3, 'Dor persistente no punho deve ser:', ARRAY['Ignorada', 'Comunicada ao líder e ao SST', 'Tratada em casa', 'Escondida'], 1),
  ('lider', 5, 1, 'Um bom feedback deve ser:', ARRAY['Público e genérico', 'Específico, respeitoso e baseado em fatos', 'Só negativo', 'Dado uma vez por ano'], 1),
  ('lider', 5, 2, 'Delegar significa:', ARRAY['Abandonar a tarefa', 'Passar a tarefa com clareza e acompanhar', 'Fazer tudo sozinho', 'Cobrar sem orientar'], 1),
  ('lider', 5, 3, 'A reunião de início de turno serve para:', ARRAY['Cobrar culpados', 'Alinhar metas, riscos do dia e pendências', 'Substituir o DDS', 'Atrasar o início'], 1),
  ('desenho', 4, 1, 'A cota indica:', ARRAY['A cor da peça', 'A medida de uma dimensão', 'O peso', 'O material'], 1),
  ('desenho', 4, 2, 'Tolerância é:', ARRAY['Erro do operador', 'Variação permitida na dimensão', 'Um tipo de solda', 'Uma ferramenta'], 1),
  ('desenho', 4, 3, 'A simbologia de soldagem informa:', ARRAY['O preço da solda', 'Tipo, posição e dimensões da junta soldada', 'O nome do soldador', 'A data da ordem'], 1),
  ('qual5s', 4, 1, 'Qual sentido do 5S trata de "descartar o desnecessário"?', ARRAY['Seiri (utilização)', 'Seiton (organização)', 'Seiso (limpeza)', 'Shitsuke (disciplina)'], 0),
  ('qual5s', 4, 2, 'Inspeção na fonte significa:', ARRAY['Inspecionar só no final', 'Verificar a qualidade onde o defeito pode surgir', 'Contar peças', 'Pintar a peça'], 1),
  ('qual5s', 4, 3, 'Ao encontrar uma peça não conforme, você deve:', ARRAY['Misturar com as boas', 'Segregar, identificar e avisar a qualidade', 'Esconder', 'Retrabalhar sem registro'], 1),
  ('comun', 4, 1, 'Uma comunicação clara entre turnos inclui:', ARRAY['Apenas o essencial verbal', 'Passagem de turno registrada com pendências e riscos', 'Nada, o turno seguinte descobre', 'Recados no banheiro'], 1),
  ('comun', 4, 2, 'Receber feedback é:', ARRAY['Um ataque pessoal', 'Uma oportunidade de ajuste', 'Opcional', 'Sempre injusto'], 1),
  ('comun', 4, 3, 'Ao discordar de uma instrução, o melhor é:', ARRAY['Ignorar', 'Expor a dúvida com respeito e buscar entendimento', 'Fazer do seu jeito', 'Reclamar no corredor'], 1),
  ('empil', 4, 1, 'Antes de operar a empilhadeira, deve-se:', ARRAY['Começar logo', 'Fazer o checklist diário de inspeção', 'Trocar o garfo', 'Pedir autorização do cliente'], 1),
  ('empil', 4, 2, 'Com carga elevada, o deslocamento deve ser:', ARRAY['Com a carga no alto', 'Com a carga a cerca de 20 cm do piso e inclinada para trás', 'Em alta velocidade', 'Em marcha ré sempre'], 1),
  ('empil', 4, 3, 'Em cruzamentos do pátio, o operador deve:', ARRAY['Acelerar', 'Reduzir, buzinar e observar pedestres', 'Desligar a luz', 'Usar o celular'], 1),
  ('socorro', 4, 1, 'O primeiro passo no atendimento a um acidente é:', ARRAY['Mover a vítima', 'Avaliar a cena e garantir a própria segurança', 'Dar água', 'Esperar passar'], 1),
  ('socorro', 4, 2, 'Para princípio de incêndio em equipamento elétrico, usa-se:', ARRAY['Água', 'Extintor adequado (CO2 ou pó)', 'Cobertor molhado', 'Areia molhada'], 1),
  ('socorro', 4, 3, 'Em queimadura leve, deve-se:', ARRAY['Aplicar pasta de dente', 'Resfriar com água corrente e procurar avaliação', 'Estourar a bolha', 'Cobrir com graxa'], 1)
) AS v(trilha, modulo, ordem, pergunta, opcoes, correta)
WHERE EXISTS (SELECT 1 FROM public.trilha_modulos m WHERE m.id = public.demo_id('trilhamod:' || v.trilha || ':' || v.modulo))
  AND NOT EXISTS (SELECT 1 FROM public.trilha_quiz_perguntas q WHERE q.id = public.demo_id('trilhaquiz:' || v.trilha || ':' || v.modulo || ':' || v.ordem));

-- ---------------------------------------------------------------------------
-- (2) Atribuicoes (por departamento, por colaborador ou para todos)
-- ---------------------------------------------------------------------------
INSERT INTO public.trilha_atribuicoes (id, tenant_id, trilha_id, tipo_alvo, alvo_id, alvo_nome, created_at)
SELECT public.demo_id('trilhaatr:' || v.trilha || ':' || COALESCE(v.alvo, 'todos')), 'd3e00000-0000-4000-8000-000000000001',
       public.demo_id('trilha:' || v.trilha), v.tipo, 
       CASE v.tipo WHEN 'departamento' THEN public.demo_id('depto:' || v.alvo)::text END, 
       CASE v.tipo WHEN 'departamento' THEN v.alvo END, now() - interval '200 days'
FROM (VALUES
  ('integ', 'todos', NULL), ('cultura', 'todos', NULL), ('qual5s', 'todos', NULL), ('comun', 'todos', NULL), ('socorro', 'todos', NULL),
  ('nr12', 'departamento', 'Produção'), ('nr12', 'departamento', 'Manutenção'),
  ('nr35', 'departamento', 'Manutenção'),
  ('ergo', 'departamento', 'Administrativo'), ('ergo', 'departamento', 'Logística'), ('ergo', 'departamento', 'Recursos Humanos'),
  ('desenho', 'departamento', 'Produção')
) AS v(trilha, tipo, alvo)
WHERE NOT EXISTS (SELECT 1 FROM public.trilha_atribuicoes a WHERE a.id = public.demo_id('trilhaatr:' || v.trilha || ':' || COALESCE(v.alvo, 'todos')));

-- Atribuicoes individuais: lideranca (lideres/supervisores) e empilhadeira
INSERT INTO public.trilha_atribuicoes (id, tenant_id, trilha_id, tipo_alvo, alvo_id, alvo_nome, created_at)
SELECT public.demo_id('trilhaatr:' || v.trilha || ':c' || v.n), 'd3e00000-0000-4000-8000-000000000001',
       public.demo_id('trilha:' || v.trilha), 'colaborador', a.id::text, a.nome_completo, now() - interval '200 days'
FROM (VALUES ('lider', 28), ('lider', 29), ('lider', 40), ('lider', 52),
             ('empil', 41), ('empil', 42), ('empil', 43), ('empil', 44), ('empil', 45)) AS v(trilha, n)
JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || v.n)
WHERE NOT EXISTS (SELECT 1 FROM public.trilha_atribuicoes x WHERE x.id = public.demo_id('trilhaatr:' || v.trilha || ':c' || v.n));

-- ---------------------------------------------------------------------------
-- (3) Quem faz o que: funcao auxiliar (somente leitura) que decide, de forma
--     deterministica, quem concluiu, quem parou no meio e quem nao comecou cada
--     trilha. E usada pelos tres comandos seguintes (certificados, medalhas e progresso).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.demo_dev_trilha_pool()
RETURNS TABLE (trilha_key text, aid uuid, nome text, tier text, k integer, m integer, base_days integer, since_adm integer, pts_total integer)
LANGUAGE sql
STABLE
AS $fn$
  WITH regra(trilha, depts, ids, adesao, pc, pp) AS (
    VALUES
      ('integ',   NULL::text[], NULL::uuid[], 100, 88, 10),
      ('cultura', NULL, NULL, 100, 72, 20),
      ('qual5s',  NULL, NULL, 45, 45, 30),
      ('comun',   NULL, NULL, 35, 15, 40),
      ('socorro', NULL, NULL, 30, 25, 30),
      ('nr12',    ARRAY['Produção','Manutenção'], NULL, 90, 55, 30),
      ('nr35',    ARRAY['Manutenção'], NULL, 100, 60, 25),
      ('ergo',    ARRAY['Administrativo','Logística','Recursos Humanos'], NULL, 80, 40, 35),
      ('desenho', ARRAY['Produção'], NULL, 60, 35, 40),
      ('lider',   NULL, ARRAY[public.demo_id('admissao:28'), public.demo_id('admissao:29'), public.demo_id('admissao:40'), public.demo_id('admissao:52')], 100, 50, 50),
      ('empil',   NULL, ARRAY[public.demo_id('admissao:41'), public.demo_id('admissao:42'), public.demo_id('admissao:43'), public.demo_id('admissao:44'), public.demo_id('admissao:45')], 100, 80, 20)
  ),
  mods AS (
    SELECT t.id AS tid, regexp_replace(m.chave, ':.*$', '') AS trilha, count(*)::int AS m, sum(m.pontuacao)::int AS pts
    FROM (SELECT mo.trilha_id, mo.pontuacao, k.chave
            FROM public.trilha_modulos mo
            JOIN (VALUES ('integ'), ('cultura'), ('qual5s'), ('comun'), ('socorro'), ('nr12'), ('nr35'), ('ergo'), ('desenho'), ('lider'), ('empil')) AS k0(chave0)
              ON mo.trilha_id = public.demo_id('trilha:' || k0.chave0)
            CROSS JOIN LATERAL (SELECT k0.chave0 AS chave) k
           WHERE mo.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND mo.ativo) m
    JOIN public.trilhas t ON t.id = m.trilha_id
    GROUP BY t.id, regexp_replace(m.chave, ':.*$', '')
  ),
  base AS (
    SELECT r.trilha, a.id AS aid, a.nome_completo AS nome, md.m, md.pts,
           (CURRENT_DATE - a.data_admissao) AS since_adm,
           public.demo_dev_rnd(a.id::text || r.trilha || 'eng', 100) AS eng,
           public.demo_dev_rnd(a.id::text || r.trilha || 'cmp', 100) AS cmp,
           r.adesao, r.pc, r.pp
    FROM regra r
    JOIN mods md ON md.trilha = r.trilha
    JOIN public.admissoes a ON a.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a.status = 'concluido'
     AND (r.depts IS NULL AND r.ids IS NULL OR a.departamento = ANY (r.depts) OR a.id = ANY (r.ids))
    WHERE (CURRENT_DATE - a.data_admissao) >= 5
  )
  SELECT b.trilha, b.aid, b.nome,
         CASE WHEN b.since_adm < 60 OR b.cmp >= b.pc THEN 'partial' ELSE 'complete' END AS tier,
         CASE WHEN b.since_adm < 60 OR b.cmp >= b.pc
              THEN 1 + public.demo_dev_rnd(b.aid::text || b.trilha || 'k', GREATEST(b.m - 1, 1)) END AS k,
         b.m,
         CASE WHEN b.since_adm < 60 OR b.cmp >= b.pc
              THEN 3 + public.demo_dev_rnd(b.aid::text || b.trilha || 'last', 40)
              ELSE 8 + public.demo_dev_rnd(b.aid::text || b.trilha || 'd', 150) END AS base_days,
         b.since_adm, b.pts
  FROM base b
  WHERE b.eng < b.adesao
    AND ((b.since_adm >= 60 AND b.cmp < b.pc + b.pp) OR (b.since_adm < 60 AND b.trilha IN ('integ', 'cultura')))
$fn$;

-- ---------------------------------------------------------------------------
-- (4) Medalhas, certificados e medalhas conquistadas
-- ---------------------------------------------------------------------------
INSERT INTO public.trilha_medalhas (id, tenant_id, nome, descricao, icone, cor, tipo, criterio, pontos_bonus, ativo, created_at)
SELECT public.demo_id('trilhamedalha:' || v.chave), 'd3e00000-0000-4000-8000-000000000001', v.nome, v.descr, v.icone, v.cor, v.tipo,
       v.criterio::jsonb, v.bonus, true, now() - interval '300 days'
FROM (VALUES
  ('m1', 'Primeiros Passos', 'Concluiu a primeira trilha de aprendizado.', 'star', '#F59E0B', 'conclusao_trilha', '{"trilhas":1}', 20),
  ('m2', 'Guardião da Segurança', 'Concluiu a trilha de NR-12 em máquinas e equipamentos.', 'award', '#16A34A', 'trilha_especifica', '{"trilha":"NR-12"}', 30),
  ('m3', 'Embaixador da Cultura', 'Concluiu a trilha de Cultura e Valores.', 'heart', '#E11D48', 'trilha_especifica', '{"trilha":"Cultura e Valores"}', 20),
  ('m4', 'Maratonista do Conhecimento', 'Concluiu 3 ou mais trilhas.', 'flame', '#7C3AED', 'marco_trilhas', '{"trilhas":3}', 50),
  ('m5', 'Nota Máxima', 'Obteve 9,5 ou mais em um quiz.', 'crown', '#0EA5E9', 'nota_maxima', '{"nota":9.5}', 25)
) AS v(chave, nome, descr, icone, cor, tipo, criterio, bonus)
WHERE NOT EXISTS (SELECT 1 FROM public.trilha_medalhas x WHERE x.id = public.demo_id('trilhamedalha:' || v.chave));

INSERT INTO public.trilha_certificados (id, tenant_id, trilha_id, colaborador_id, colaborador_nome, data_conclusao, pontos_obtidos, codigo, created_at)
SELECT public.demo_id('trilhacert:' || p.trilha_key || ':' || p.aid::text), 'd3e00000-0000-4000-8000-000000000001',
       public.demo_id('trilha:' || p.trilha_key), p.aid, p.nome,
       now() - GREATEST(1, LEAST(p.base_days + 2 * p.m, p.since_adm - 1) - 2 * (p.m - 1)) * interval '1 day',
       p.pts_total,
       'CERT-' || upper(substr(md5('demo-cert:' || p.trilha_key || ':' || p.aid::text), 1, 8)),
       now() - GREATEST(1, LEAST(p.base_days + 2 * p.m, p.since_adm - 1) - 2 * (p.m - 1)) * interval '1 day'
FROM public.demo_dev_trilha_pool() p
WHERE p.tier = 'complete'
  AND NOT EXISTS (SELECT 1 FROM public.trilha_certificados c WHERE c.id = public.demo_id('trilhacert:' || p.trilha_key || ':' || p.aid::text));

-- certificados do proprio login da demo: integracao e cultura
INSERT INTO public.trilha_certificados (id, tenant_id, trilha_id, colaborador_id, colaborador_nome, data_conclusao, pontos_obtidos, codigo, created_at)
SELECT public.demo_id('trilhacert:' || v.trilha || ':demo'), 'd3e00000-0000-4000-8000-000000000001', public.demo_id('trilha:' || v.trilha),
       u.id, COALESCE((SELECT p.nome_completo FROM public.profiles p WHERE p.user_id = u.id LIMIT 1), 'Leiri'),
       now() - v.dias * interval '1 day', v.pts, 'CERT-' || upper(substr(md5('demo-cert:' || v.trilha || ':demo'), 1, 8)),
       now() - v.dias * interval '1 day'
FROM (VALUES ('integ', 90, 70), ('cultura', 75, 70)) AS v(trilha, dias, pts)
CROSS JOIN (SELECT id FROM auth.users WHERE lower(email) = 'leirinuernberg@gmail.com' LIMIT 1) u
WHERE NOT EXISTS (SELECT 1 FROM public.trilha_certificados c WHERE c.id = public.demo_id('trilhacert:' || v.trilha || ':demo'));

-- medalhas conquistadas (todas as regras derivam dos certificados acima)
INSERT INTO public.trilha_medalhas_colaboradores (id, tenant_id, medalha_id, colaborador_id, colaborador_nome, trilha_id, data_conquista, created_at)
SELECT public.demo_id('trilhamedcol:' || x.medalha || ':' || x.colab::text), 'd3e00000-0000-4000-8000-000000000001',
       public.demo_id('trilhamedalha:' || x.medalha), x.colab, x.nome, x.trilha_id, x.data, x.data
FROM (
  -- m1: primeiro certificado de cada pessoa
  SELECT DISTINCT ON (c.colaborador_id) 'm1'::text AS medalha, c.colaborador_id AS colab, c.colaborador_nome AS nome, c.trilha_id, c.data_conclusao AS data
  FROM public.trilha_certificados c WHERE c.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
  ORDER BY c.colaborador_id, c.data_conclusao
) x
WHERE NOT EXISTS (SELECT 1 FROM public.trilha_medalhas_colaboradores y WHERE y.id = public.demo_id('trilhamedcol:' || x.medalha || ':' || x.colab::text));

INSERT INTO public.trilha_medalhas_colaboradores (id, tenant_id, medalha_id, colaborador_id, colaborador_nome, trilha_id, data_conquista, created_at)
SELECT public.demo_id('trilhamedcol:' || v.medalha || ':' || c.colaborador_id::text), 'd3e00000-0000-4000-8000-000000000001',
       public.demo_id('trilhamedalha:' || v.medalha), c.colaborador_id, c.colaborador_nome, c.trilha_id, c.data_conclusao, c.data_conclusao
FROM (VALUES ('m2', 'nr12'), ('m3', 'cultura')) AS v(medalha, trilha)
JOIN public.trilha_certificados c ON c.trilha_id = public.demo_id('trilha:' || v.trilha) AND c.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
WHERE NOT EXISTS (SELECT 1 FROM public.trilha_medalhas_colaboradores y WHERE y.id = public.demo_id('trilhamedcol:' || v.medalha || ':' || c.colaborador_id::text));

INSERT INTO public.trilha_medalhas_colaboradores (id, tenant_id, medalha_id, colaborador_id, colaborador_nome, trilha_id, data_conquista, created_at)
SELECT public.demo_id('trilhamedcol:m4:' || g.colab::text), 'd3e00000-0000-4000-8000-000000000001',
       public.demo_id('trilhamedalha:m4'), g.colab, g.nome, NULL, g.data, g.data
FROM (
  SELECT c.colaborador_id AS colab, max(c.colaborador_nome) AS nome, max(c.data_conclusao) AS data
  FROM public.trilha_certificados c
  WHERE c.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
  GROUP BY c.colaborador_id HAVING count(*) >= 3
) g
WHERE NOT EXISTS (SELECT 1 FROM public.trilha_medalhas_colaboradores y WHERE y.id = public.demo_id('trilhamedcol:m4:' || g.colab::text));

INSERT INTO public.trilha_medalhas_colaboradores (id, tenant_id, medalha_id, colaborador_id, colaborador_nome, trilha_id, data_conquista, created_at)
SELECT public.demo_id('trilhamedcol:m5:' || g.colab::text), 'd3e00000-0000-4000-8000-000000000001',
       public.demo_id('trilhamedalha:m5'), g.colab, g.nome, g.trilha_id, g.data, g.data
FROM (
  SELECT DISTINCT ON (c.colaborador_id) c.colaborador_id AS colab, c.colaborador_nome AS nome, c.trilha_id, c.data_conclusao AS data
  FROM public.trilha_certificados c
  WHERE c.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND public.demo_dev_rnd(c.colaborador_id::text || 'nota', 100) < 12
  ORDER BY c.colaborador_id, c.data_conclusao DESC
) g
WHERE NOT EXISTS (SELECT 1 FROM public.trilha_medalhas_colaboradores y WHERE y.id = public.demo_id('trilhamedcol:m5:' || g.colab::text));

-- ---------------------------------------------------------------------------
-- (5) Progresso por modulo dos colaboradores
-- ---------------------------------------------------------------------------
INSERT INTO public.trilha_progresso (
  id, tenant_id, trilha_id, modulo_id, colaborador_id, colaborador_nome, status, nota, evidencia_texto,
  data_inicio, data_conclusao, pontos_obtidos, created_at, updated_at, conteudos_concluidos
)
SELECT public.demo_id('trilhaprog:' || p.trilha_key || ':' || p.aid::text || ':' || mo.ordem),
       'd3e00000-0000-4000-8000-000000000001', mo.trilha_id, mo.id, p.aid::text, p.nome,
       x.status::public.trilha_progresso_status,
       CASE WHEN x.status = 'concluido' AND mo.tipo = 'quiz' THEN round((6 + public.demo_dev_rnd(p.aid::text || mo.id::text, 41) / 10.0)::numeric, 1) END,
       CASE WHEN x.status = 'concluido' AND mo.evidencia_obrigatoria THEN 'Atividade realizada no setor e validada pelo líder.' END,
       x.t_ini, x.t_fim,
       CASE WHEN x.status = 'concluido' THEN mo.pontuacao ELSE 0 END,
       COALESCE(x.t_fim, x.t_ini), COALESCE(x.t_fim, x.t_ini),
       CASE WHEN x.status = 'concluido' THEN jsonb_build_array('c1') ELSE '[]'::jsonb END
FROM public.demo_dev_trilha_pool() p
JOIN public.trilha_modulos mo ON mo.trilha_id = public.demo_id('trilha:' || p.trilha_key) AND mo.ativo
CROSS JOIN LATERAL (
  SELECT CASE WHEN p.tier = 'complete' OR mo.ordem <= p.k THEN 'concluido'
              WHEN mo.ordem = p.k + 1 THEN 'em_andamento' END AS status,
         CASE WHEN p.tier = 'complete'
              THEN GREATEST(1, LEAST(p.base_days + 2 * p.m, p.since_adm - 1) - 2 * (mo.ordem - 1))
              ELSE GREATEST(1, LEAST(p.base_days + 2 * (p.k - mo.ordem), p.since_adm - 1)) END AS dias
) d
CROSS JOIN LATERAL (
  SELECT d.status AS status,
         now() - (d.dias + 1) * interval '1 day' AS t_ini,
         CASE WHEN d.status = 'concluido' THEN now() - d.dias * interval '1 day' END AS t_fim
) x
WHERE x.status IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.trilha_progresso g WHERE g.id = public.demo_id('trilhaprog:' || p.trilha_key || ':' || p.aid::text || ':' || mo.ordem));

-- progresso do proprio login da demo: concluiu integracao e cultura, esta no meio de
-- "Comunicacao e Feedback" e ainda nao comecou "Qualidade e 5S" e "Primeiros Socorros"
INSERT INTO public.trilha_progresso (
  id, tenant_id, trilha_id, modulo_id, colaborador_id, colaborador_nome, status, nota, data_inicio, data_conclusao,
  pontos_obtidos, created_at, updated_at, conteudos_concluidos
)
SELECT public.demo_id('trilhaprog:' || v.trilha || ':demo:' || mo.ordem), 'd3e00000-0000-4000-8000-000000000001', mo.trilha_id, mo.id,
       u.id::text, COALESCE((SELECT p.nome_completo FROM public.profiles p WHERE p.user_id = u.id LIMIT 1), 'Leiri'),
       'concluido'::public.trilha_progresso_status,
       CASE WHEN mo.tipo = 'quiz' THEN 9.0 + (mo.ordem % 2) * 0.5 END,
       now() - (v.dias_ini - mo.ordem) * interval '1 day', now() - (v.dias_ini - mo.ordem) * interval '1 day' + interval '2 hours',
       mo.pontuacao, now() - (v.dias_ini - mo.ordem) * interval '1 day', now() - (v.dias_ini - mo.ordem) * interval '1 day',
       jsonb_build_array('c1')
FROM (VALUES ('integ', 95, 99), ('cultura', 80, 99), ('comun', 12, 2)) AS v(trilha, dias_ini, ate)
JOIN public.trilha_modulos mo ON mo.trilha_id = public.demo_id('trilha:' || v.trilha) AND mo.ativo AND mo.ordem <= v.ate
CROSS JOIN (SELECT id FROM auth.users WHERE lower(email) = 'leirinuernberg@gmail.com' LIMIT 1) u
WHERE NOT EXISTS (SELECT 1 FROM public.trilha_progresso g WHERE g.id = public.demo_id('trilhaprog:' || v.trilha || ':demo:' || mo.ordem));

INSERT INTO public.trilha_progresso (
  id, tenant_id, trilha_id, modulo_id, colaborador_id, colaborador_nome, status, data_inicio, pontos_obtidos, created_at, updated_at
)
SELECT public.demo_id('trilhaprog:comun:demo:3'), 'd3e00000-0000-4000-8000-000000000001', mo.trilha_id, mo.id, u.id::text,
       COALESCE((SELECT p.nome_completo FROM public.profiles p WHERE p.user_id = u.id LIMIT 1), 'Leiri'),
       'em_andamento'::public.trilha_progresso_status, now() - interval '9 days', 0, now() - interval '9 days', now() - interval '9 days'
FROM public.trilha_modulos mo
CROSS JOIN (SELECT id FROM auth.users WHERE lower(email) = 'leirinuernberg@gmail.com' LIMIT 1) u
WHERE mo.id = public.demo_id('trilhamod:comun:3')
  AND NOT EXISTS (SELECT 1 FROM public.trilha_progresso g WHERE g.id = public.demo_id('trilhaprog:comun:demo:3'));

-- notificacoes do sino (login da demo)
INSERT INTO public.trilha_notificacoes (id, tenant_id, colaborador_id, colaborador_nome, trilha_id, trilha_nome, tipo, titulo, descricao, lida, created_at)
SELECT public.demo_id('trilhanot:' || v.chave), 'd3e00000-0000-4000-8000-000000000001', u.id,
       COALESCE((SELECT p.nome_completo FROM public.profiles p WHERE p.user_id = u.id LIMIT 1), 'Leiri'),
       t.id, t.nome, v.tipo, v.titulo, v.descr, v.lida, now() - v.horas * interval '1 hour'
FROM (VALUES
  ('1', 'comun', 'lembrete_retorno', 'Continue sua trilha', 'Você parou no módulo 3 de "Comunicação e Feedback". Que tal retomar hoje?', false, 20),
  ('2', 'qual5s', 'prazo_proximo', 'Prazo próximo', 'A trilha "Qualidade e 5S na Produção" vence em 6 dias.', false, 36),
  ('3', 'socorro', 'prazo_proximo', 'Nova trilha disponível', 'Participe da trilha opcional de Primeiros Socorros e Brigada de Emergência.', true, 120),
  ('4', 'integ', 'lembrete_retorno', 'Parabéns!', 'Você concluiu a trilha de Integração e ganhou a medalha Primeiros Passos.', true, 2160)
) AS v(chave, trilha, tipo, titulo, descr, lida, horas)
JOIN public.trilhas t ON t.id = public.demo_id('trilha:' || v.trilha)
CROSS JOIN (SELECT id FROM auth.users WHERE lower(email) = 'leirinuernberg@gmail.com' LIMIT 1) u
WHERE NOT EXISTS (SELECT 1 FROM public.trilha_notificacoes n WHERE n.id = public.demo_id('trilhanot:' || v.chave));

-- ===========================================================================
-- ACADEMIA (/academia — area do SuperAdmin)
-- ===========================================================================

INSERT INTO public.academia_categorias (id, tenant_id, nome, slug, descricao, icone, ordem, ativo, created_at, updated_at)
SELECT public.demo_id('acadcat:' || v.slug), 'd3e00000-0000-4000-8000-000000000001', v.nome, v.slug, v.descr, v.icone, v.ordem, true,
       now() - interval '200 days', now() - interval '200 days'
FROM (VALUES
  ('primeiros-passos', 'Primeiros Passos', 'Comece por aqui: navegação, cadastros e perfis de acesso.', 'rocket', 1),
  ('ponto-jornada', 'Ponto e Jornada', 'Registro de ponto, escalas, banco de horas e fechamento.', 'clock', 2),
  ('saude-sst', 'Saúde e Segurança do Trabalho', 'ASO, exames, atestados, riscos psicossociais e NR.', 'heart-pulse', 3),
  ('gestao-pessoas', 'Gestão de Pessoas', 'Avaliações, PDI, metas e desenvolvimento.', 'users', 4)
) AS v(slug, nome, descr, icone, ordem)
WHERE NOT EXISTS (SELECT 1 FROM public.academia_categorias c WHERE c.id = public.demo_id('acadcat:' || v.slug));

INSERT INTO public.academia_treinamentos (
  id, tenant_id, categoria_id, titulo, subtitulo, descricao_curta, descricao_completa, slug, nivel, instrutor, duracao_estimada,
  tags, status, destaque, ordem, created_at, updated_at
)
SELECT public.demo_id('acadtrein:' || v.slug), 'd3e00000-0000-4000-8000-000000000001', public.demo_id('acadcat:' || v.cat),
       v.titulo, v.sub, v.curta, v.curta || ' O treinamento é dividido em módulos curtos, com aulas em texto e exemplos da rotina de uma indústria metalúrgica.',
       v.slug, v.nivel, 'Equipe de Sucesso do Cliente', v.dur, v.tags, v.status, v.destaque, v.ordem, now() - interval '180 days', now() - interval '30 days'
FROM (VALUES
  ('conhecendo-o-sistema', 'primeiros-passos', 'Conhecendo o YourEyes', 'Do primeiro acesso ao dia a dia', 'Tour pelo sistema: menus, cadastros básicos e perfis de acesso.', 'iniciante', '45 min', ARRAY['início', 'navegação'], 'publicado', true, 1),
  ('ponto-na-pratica', 'ponto-jornada', 'Ponto eletrônico na prática', 'Registros, espelho e fechamento', 'Como acompanhar o espelho de ponto, tratar inconsistências e fechar o período.', 'iniciante', '1 h 10 min', ARRAY['ponto', 'jornada'], 'publicado', false, 2),
  ('banco-de-horas-escalas', 'ponto-jornada', 'Banco de horas e escalas', 'Regras da CLT e acordos coletivos', 'Escalas 6x2, turnos, compensações e saldo do banco de horas.', 'intermediario', '55 min', ARRAY['banco de horas', 'escalas'], 'publicado', false, 3),
  ('saude-ocupacional', 'saude-sst', 'Saúde ocupacional: ASO, exames e atestados', 'PCMSO sem complicação', 'Agenda de exames, ASO, atestados e controle de afastamentos.', 'intermediario', '1 h 20 min', ARRAY['aso', 'pcmso', 'atestados'], 'publicado', true, 4),
  ('riscos-psicossociais', 'saude-sst', 'Riscos psicossociais (NR-01) com o YourEyes', 'Do diagnóstico ao plano de ação', 'Campanhas, indicadores, GHE e inventário de riscos psicossociais.', 'avancado', '1 h 30 min', ARRAY['nr-01', 'psicossocial'], 'publicado', false, 5),
  ('avaliacoes-pdi', 'gestao-pessoas', 'Avaliações de desempenho e PDI', 'Ciclos, 9-Box e desenvolvimento', 'Como criar ciclos, acompanhar resultados e transformar avaliações em PDI.', 'intermediario', '1 h', ARRAY['avaliação', 'pdi'], 'publicado', false, 6),
  ('metas-e-okrs', 'gestao-pessoas', 'Metas e OKRs', 'Do objetivo estratégico ao individual', 'Desdobramento de metas, indicadores e check-ins. Em produção.', 'intermediario', '50 min', ARRAY['metas', 'okr'], 'rascunho', false, 7)
) AS v(slug, cat, titulo, sub, curta, nivel, dur, tags, status, destaque, ordem)
WHERE NOT EXISTS (SELECT 1 FROM public.academia_treinamentos t WHERE t.id = public.demo_id('acadtrein:' || v.slug));

INSERT INTO public.academia_modulos (id, tenant_id, treinamento_id, nome, descricao, ordem, created_at, updated_at)
SELECT public.demo_id('acadmod:' || v.trein || ':' || v.ordem), 'd3e00000-0000-4000-8000-000000000001', public.demo_id('acadtrein:' || v.trein),
       v.nome, v.nome || ' — módulo do treinamento.', v.ordem, now() - interval '180 days', now() - interval '180 days'
FROM (VALUES
  ('conhecendo-o-sistema', 1, 'Navegação e menus'), ('conhecendo-o-sistema', 2, 'Cadastros básicos'), ('conhecendo-o-sistema', 3, 'Perfis de acesso'),
  ('ponto-na-pratica', 1, 'Registro e espelho de ponto'), ('ponto-na-pratica', 2, 'Correções e justificativas'), ('ponto-na-pratica', 3, 'Fechamento do período'),
  ('banco-de-horas-escalas', 1, 'Escalas e turnos'), ('banco-de-horas-escalas', 2, 'Banco de horas'),
  ('saude-ocupacional', 1, 'Exames e ASO'), ('saude-ocupacional', 2, 'Atestados e afastamentos'), ('saude-ocupacional', 3, 'Indicadores de saúde'),
  ('riscos-psicossociais', 1, 'Campanhas e coleta'), ('riscos-psicossociais', 2, 'Análise e plano de ação'),
  ('avaliacoes-pdi', 1, 'Ciclos e resultados'), ('avaliacoes-pdi', 2, 'PDI e acompanhamento'),
  ('metas-e-okrs', 1, 'Desdobramento de metas'), ('metas-e-okrs', 2, 'Check-ins e evidências')
) AS v(trein, ordem, nome)
WHERE NOT EXISTS (SELECT 1 FROM public.academia_modulos m WHERE m.id = public.demo_id('acadmod:' || v.trein || ':' || v.ordem));

INSERT INTO public.academia_aulas (
  id, tenant_id, modulo_id, titulo, descricao, tipo, conteudo_texto, duracao, ordem, obrigatoria, created_at, updated_at
)
SELECT public.demo_id('acadaula:' || v.trein || ':' || v.modulo || ':' || v.ordem), 'd3e00000-0000-4000-8000-000000000001',
       public.demo_id('acadmod:' || v.trein || ':' || v.modulo), v.titulo, 'Aula em texto: ' || lower(v.titulo) || '.', 'texto',
       v.titulo || E'\n\nNesta aula você vê, passo a passo, como executar esta tarefa no sistema usando como exemplo a Metalúrgica Exemplo. Siga as etapas, teste com dados fictícios e, em caso de dúvida, consulte a central de ajuda.',
       v.dur, v.ordem, true, now() - interval '180 days', now() - interval '180 days'
FROM (VALUES
  ('conhecendo-o-sistema', 1, 1, 'Acessando o sistema e o painel inicial', '6 min'), ('conhecendo-o-sistema', 1, 2, 'Menu lateral, busca e atalhos', '5 min'), ('conhecendo-o-sistema', 1, 3, 'Trocando de empresa e unidade', '4 min'),
  ('conhecendo-o-sistema', 2, 1, 'Cadastro de departamentos e cargos', '8 min'), ('conhecendo-o-sistema', 2, 2, 'Cadastro de colaboradores', '10 min'), ('conhecendo-o-sistema', 2, 3, 'Importação em lote', '7 min'),
  ('conhecendo-o-sistema', 3, 1, 'Perfis e permissões', '8 min'), ('conhecendo-o-sistema', 3, 2, 'Convidando usuários', '5 min'),
  ('ponto-na-pratica', 1, 1, 'Como o registro de ponto chega ao sistema', '7 min'), ('ponto-na-pratica', 1, 2, 'Lendo o espelho de ponto', '9 min'), ('ponto-na-pratica', 1, 3, 'Entendendo as marcações do dia', '6 min'),
  ('ponto-na-pratica', 2, 1, 'Justificando faltas e atrasos', '8 min'), ('ponto-na-pratica', 2, 2, 'Correção de marcações', '8 min'),
  ('ponto-na-pratica', 3, 1, 'Conferência antes do fechamento', '7 min'), ('ponto-na-pratica', 3, 2, 'Fechando o período e exportando', '6 min'),
  ('banco-de-horas-escalas', 1, 1, 'Escalas 6x2 e turnos A/B', '10 min'), ('banco-de-horas-escalas', 1, 2, 'Troca de escala', '6 min'),
  ('banco-de-horas-escalas', 2, 1, 'Regras de compensação', '9 min'), ('banco-de-horas-escalas', 2, 2, 'Acompanhando o saldo', '7 min'),
  ('saude-ocupacional', 1, 1, 'Agenda de exames periódicos', '8 min'), ('saude-ocupacional', 1, 2, 'Registrando o ASO', '7 min'),
  ('saude-ocupacional', 2, 1, 'Lançamento de atestados', '8 min'), ('saude-ocupacional', 2, 2, 'Afastamentos e retorno ao trabalho', '9 min'),
  ('saude-ocupacional', 3, 1, 'Painel de saúde da empresa', '6 min'),
  ('riscos-psicossociais', 1, 1, 'Criando uma campanha', '9 min'), ('riscos-psicossociais', 1, 2, 'Distribuição e acompanhamento', '7 min'),
  ('riscos-psicossociais', 2, 1, 'Lendo os indicadores', '10 min'), ('riscos-psicossociais', 2, 2, 'Do diagnóstico ao plano de ação', '9 min'),
  ('avaliacoes-pdi', 1, 1, 'Criando um ciclo de avaliação', '8 min'), ('avaliacoes-pdi', 1, 2, 'Resultados e matriz 9-Box', '9 min'),
  ('avaliacoes-pdi', 2, 1, 'Criando PDI a partir da avaliação', '7 min'), ('avaliacoes-pdi', 2, 2, 'Check-ins e evidências', '6 min'),
  ('metas-e-okrs', 1, 1, 'Níveis de metas e desdobramento', '8 min'), ('metas-e-okrs', 2, 1, 'Check-ins de metas', '6 min')
) AS v(trein, modulo, ordem, titulo, dur)
WHERE NOT EXISTS (SELECT 1 FROM public.academia_aulas a WHERE a.id = public.demo_id('acadaula:' || v.trein || ':' || v.modulo || ':' || v.ordem));

-- Progresso, XP, medalhas e favoritos do login da demo
INSERT INTO public.academia_progresso (id, tenant_id, user_id, aula_id, treinamento_id, concluida, concluida_em, created_at)
SELECT public.demo_id('acadprog:' || a.id::text), 'd3e00000-0000-4000-8000-000000000001', u.id, a.id, t.id, true,
       now() - (60 - 3 * row_number() OVER (PARTITION BY t.id ORDER BY m.ordem, a.ordem)) * interval '1 day',
       now() - (60 - 3 * row_number() OVER (PARTITION BY t.id ORDER BY m.ordem, a.ordem)) * interval '1 day'
FROM public.academia_aulas a
JOIN public.academia_modulos m ON m.id = a.modulo_id
JOIN public.academia_treinamentos t ON t.id = m.treinamento_id
CROSS JOIN (SELECT id FROM auth.users WHERE lower(email) = 'leirinuernberg@gmail.com' LIMIT 1) u
WHERE t.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
  AND (t.id = public.demo_id('acadtrein:conhecendo-o-sistema')
       OR (t.id = public.demo_id('acadtrein:ponto-na-pratica') AND m.ordem <= 2)
       OR (t.id = public.demo_id('acadtrein:saude-ocupacional') AND m.ordem = 1 AND a.ordem = 1))
  AND NOT EXISTS (SELECT 1 FROM public.academia_progresso p WHERE p.id = public.demo_id('acadprog:' || a.id::text));

INSERT INTO public.academia_xp (id, tenant_id, user_id, pontos, tipo, referencia_id, descricao, created_at)
SELECT public.demo_id('acadxp:' || p.id::text), p.tenant_id, p.user_id, 10, 'aula_concluida', p.aula_id, 'Aula concluída', p.concluida_em
FROM public.academia_progresso p
WHERE p.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
  AND NOT EXISTS (SELECT 1 FROM public.academia_xp x WHERE x.id = public.demo_id('acadxp:' || p.id::text));

INSERT INTO public.academia_xp (id, tenant_id, user_id, pontos, tipo, referencia_id, descricao, created_at)
SELECT public.demo_id('acadxp:trein:conhecendo-o-sistema'), 'd3e00000-0000-4000-8000-000000000001', u.id, 50, 'treinamento_concluido',
       public.demo_id('acadtrein:conhecendo-o-sistema'), 'Treinamento concluído: Conhecendo o YourEyes', now() - interval '40 days'
FROM (SELECT id FROM auth.users WHERE lower(email) = 'leirinuernberg@gmail.com' LIMIT 1) u
WHERE EXISTS (SELECT 1 FROM public.academia_treinamentos WHERE id = public.demo_id('acadtrein:conhecendo-o-sistema'))
  AND NOT EXISTS (SELECT 1 FROM public.academia_xp x WHERE x.id = public.demo_id('acadxp:trein:conhecendo-o-sistema'));

INSERT INTO public.academia_badges (id, tenant_id, user_id, nome, descricao, icone, treinamento_id, created_at)
SELECT public.demo_id('acadbadge:1'), 'd3e00000-0000-4000-8000-000000000001', u.id, 'Primeiros Passos',
       'Concluiu o treinamento Conhecendo o YourEyes.', 'trophy', public.demo_id('acadtrein:conhecendo-o-sistema'), now() - interval '40 days'
FROM (SELECT id FROM auth.users WHERE lower(email) = 'leirinuernberg@gmail.com' LIMIT 1) u
WHERE EXISTS (SELECT 1 FROM public.academia_treinamentos WHERE id = public.demo_id('acadtrein:conhecendo-o-sistema'))
  AND NOT EXISTS (SELECT 1 FROM public.academia_badges b WHERE b.id = public.demo_id('acadbadge:1'));

INSERT INTO public.academia_favoritos (id, tenant_id, user_id, treinamento_id, created_at)
SELECT public.demo_id('acadfav:' || v.slug), 'd3e00000-0000-4000-8000-000000000001', u.id, public.demo_id('acadtrein:' || v.slug), now() - interval '20 days'
FROM (VALUES ('saude-ocupacional'), ('ponto-na-pratica')) AS v(slug)
CROSS JOIN (SELECT id FROM auth.users WHERE lower(email) = 'leirinuernberg@gmail.com' LIMIT 1) u
WHERE EXISTS (SELECT 1 FROM public.academia_treinamentos WHERE id = public.demo_id('acadtrein:' || v.slug))
  AND NOT EXISTS (SELECT 1 FROM public.academia_favoritos f WHERE f.id = public.demo_id('acadfav:' || v.slug));

-- ---------------------------------------------------------------------------
-- Conferencia final
-- ---------------------------------------------------------------------------
SELECT
  (SELECT count(*) FROM public.trilhas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS trilhas,
  (SELECT count(*) FROM public.trilha_modulos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS modulos,
  (SELECT count(*) FROM public.trilha_progresso WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS progresso,
  (SELECT count(*) FROM public.trilha_certificados WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS certificados,
  (SELECT count(*) FROM public.trilha_medalhas_colaboradores WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS medalhas_conquistadas,
  (SELECT count(*) FROM public.academia_treinamentos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS academia_treinamentos,
  (SELECT count(*) FROM public.academia_aulas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS academia_aulas,
  CASE WHEN (SELECT count(*) FROM public.trilhas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') = 13
        AND (SELECT count(*) FROM public.academia_treinamentos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') = 7
       THEN 'OK' ELSE 'CONFERIR' END AS situacao;
