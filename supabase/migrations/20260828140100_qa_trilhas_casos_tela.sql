-- =========================================================
-- QA — Trilhas (Aprendizagem): documentação de casos do módulo (13 casos)
--
-- Módulo desenvolvimento-performance/trilhas, zero casos até aqui.
-- Casos de TELA (nivel e2e) ancorados em src/pages/Trilhas.tsx +
-- components/trilhas/*: abas Minhas Trilhas / Gamificação / Analytics /
-- Gestão; "Nova Trilha", geração por IA, módulos e conteúdos, quiz
-- (player/perguntas), execução com evidências, certificados, medalhas e
-- ranking, atribuição a colaboradores.
--
-- Regra da casa: caso e2e sem spec só gera aviso na guarda.
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'desenvolvimento-performance/trilhas';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo desenvolvimento-performance/trilhas não encontrado.'; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'TRILHA-001', 'Tela de Trilhas abre com as abas do módulo',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O módulo organiza aprendizagem em abas (Minhas Trilhas, Gamificação, Analytics, Gestão). Se não monta, o colaborador não aprende e o gestor não acompanha.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar Trilhas pelo menu","resultado_esperado":"Tela carrega"},
     {"ordem":2,"acao":"Alternar entre Minhas Trilhas, Gamificação, Analytics e Gestão","resultado_esperado":"Cada aba monta conforme permissão"}]'::jsonb,
   'As abas do módulo montam de acordo com o perfil.', NULL),

  (v_mod, 'TRILHA-002', 'Minhas Trilhas lista o que foi atribuído ao usuário',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'É a visão do colaborador: as trilhas que ele precisa fazer, com progresso.',
   'Usuário com ao menos uma trilha atribuída.',
   '[{"ordem":1,"acao":"Abrir Minhas Trilhas","resultado_esperado":"Trilhas atribuídas montam com progresso"}]'::jsonb,
   'O aluno vê suas trilhas e o andamento.', NULL),

  (v_mod, 'TRILHA-003', 'Sem trilhas atribuídas, estado vazio orientativo',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Colaborador novo abre sem trilhas. A tela deve orientar, não quebrar.',
   'Usuário sem trilhas atribuídas.',
   '[{"ordem":1,"acao":"Abrir Minhas Trilhas sem atribuições","resultado_esperado":"Estado vazio amigável; sem erro"}]'::jsonb,
   'O vazio é tratado.', NULL),

  (v_mod, 'TRILHA-010', 'Criar uma trilha na Gestão',
   'feliz', 'critica', 'aprovado', 'e2e', NULL,
   'A trilha é o contêiner de aprendizagem (módulos, conteúdos, quiz). Sem criação, não há o que atribuir.',
   'Perfil gestor; aba Gestão acessível.',
   '[{"ordem":1,"acao":"Clicar em Nova Trilha","resultado_esperado":"Formulário de trilha abre"},
     {"ordem":2,"acao":"Preencher os dados da trilha e salvar","resultado_esperado":"Trilha criada aparece na Gestão"}]'::jsonb,
   'A trilha é criada e listada.',
   'Componente TrilhaForm. Botão "Nova Trilha" (handleNewTrilha).'),

  (v_mod, 'TRILHA-011', 'Gerar trilha por IA',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'A geração por IA acelera a montagem da trilha a partir de um tema. Com a chave configurada, retorna estrutura; sem ela, avisa.',
   'Perfil gestor; chave de IA no ambiente.',
   '[{"ordem":1,"acao":"Abrir a geração de trilha por IA e informar um tema","resultado_esperado":"Modal aceita a entrada"},
     {"ordem":2,"acao":"Gerar","resultado_esperado":"Estrutura de trilha proposta (ou aviso claro de chave ausente)"}]'::jsonb,
   'A geração por IA responde ou avisa — nunca falha muda.',
   'Componente GerarTrilhaIAModal.'),

  (v_mod, 'TRILHA-012', 'Adicionar módulos e conteúdos à trilha',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'A trilha se compõe de módulos com conteúdos (texto, vídeo). Montar essa estrutura é o corpo do curso.',
   'Uma trilha criada.',
   '[{"ordem":1,"acao":"Abrir a trilha e adicionar um módulo","resultado_esperado":"Módulo criado"},
     {"ordem":2,"acao":"Adicionar um conteúdo ao módulo e salvar","resultado_esperado":"Conteúdo persistido e visível na estrutura"}]'::jsonb,
   'A estrutura módulo→conteúdo é montável e persiste.',
   'Componentes ModuloForm, ConteudoEditorItem.'),

  (v_mod, 'TRILHA-013', 'Montar um quiz com perguntas na trilha',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O quiz é a verificação de aprendizagem. Criar perguntas e salvá-las é o que permite avaliar o aluno.',
   'Uma trilha/módulo criado.',
   '[{"ordem":1,"acao":"Abrir o gerenciador de quiz da trilha","resultado_esperado":"Editor de quiz monta"},
     {"ordem":2,"acao":"Adicionar uma pergunta com alternativas e a correta, salvar","resultado_esperado":"Pergunta persistida no quiz"}]'::jsonb,
   'O quiz é editável e persiste as perguntas.',
   'Componentes QuizManager, QuizPerguntaForm.'),

  (v_mod, 'TRILHA-020', 'Atribuir uma trilha a colaboradores',
   'feliz', 'critica', 'aprovado', 'e2e', NULL,
   'Atribuição é o que transforma trilha em obrigação de aprendizagem. Deve criar a atribuição e refletir em Minhas Trilhas do colaborador.',
   'Uma trilha publicável e colaboradores no ambiente.',
   '[{"ordem":1,"acao":"Abrir a atribuição da trilha","resultado_esperado":"Modal de atribuição abre"},
     {"ordem":2,"acao":"Selecionar colaboradores e confirmar","resultado_esperado":"Atribuição criada"}]'::jsonb,
   'A trilha chega ao colaborador via atribuição.',
   'Componente AtribuicaoTrilhaModal.'),

  (v_mod, 'TRILHA-030', 'Executar uma trilha e avançar o progresso',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'A execução é a experiência do aluno: consumir conteúdo e avançar. O progresso deve subir e persistir.',
   'Usuário com trilha atribuída.',
   '[{"ordem":1,"acao":"Abrir uma trilha atribuída e iniciar a execução","resultado_esperado":"Player/execução monta o primeiro conteúdo"},
     {"ordem":2,"acao":"Concluir um conteúdo","resultado_esperado":"Progresso da trilha avança e persiste ao reabrir"}]'::jsonb,
   'O progresso do aluno é registrado.',
   'Componentes TrilhaExecucao, ConteudoView.'),

  (v_mod, 'TRILHA-031', 'Responder o quiz durante a execução',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O aluno responde o quiz e recebe o resultado. É a nota de aprendizagem que alimenta certificado e gamificação.',
   'Trilha com quiz, em execução.',
   '[{"ordem":1,"acao":"Chegar ao quiz na execução e respondê-lo","resultado_esperado":"Player registra as respostas"},
     {"ordem":2,"acao":"Finalizar","resultado_esperado":"Resultado do quiz exibido e vinculado ao progresso"}]'::jsonb,
   'O quiz é respondível e pontua a trilha.',
   'Componente QuizPlayer.'),

  (v_mod, 'TRILHA-032', 'Anexar evidência quando a trilha exige',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Trilhas práticas pedem evidência (foto/arquivo) da atividade. O upload deve concluir e ficar vinculado à execução.',
   'Trilha em execução que solicita evidência; arquivo válido.',
   '[{"ordem":1,"acao":"Anexar a evidência solicitada","resultado_esperado":"Upload conclui e evidência listada"}]'::jsonb,
   'A evidência acompanha a execução.',
   'Componente EvidenciaUpload.'),

  (v_mod, 'TRILHA-040', 'Gamificação exibe medalhas e ranking',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'A aba Gamificação motiva com medalhas e ranking. Deve montar com dados e tratar o estado vazio.',
   'Aba Gamificação acessível.',
   '[{"ordem":1,"acao":"Abrir a aba Gamificação","resultado_esperado":"Medalhas e ranking montam (ou estado vazio controlado)"}]'::jsonb,
   'Gamificação renderiza nos dois estados.',
   'Componentes MedalhasGaleria, RankingBoard, GamificacaoTab.'),

  (v_mod, 'TRILHA-050', 'Certificado é emitido ao concluir a trilha',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'A conclusão gera certificado — a prova formal da capacitação. Deve constar na lista de certificados do aluno.',
   'Uma trilha concluída por um usuário.',
   '[{"ordem":1,"acao":"Concluir 100% de uma trilha com aprovação no quiz","resultado_esperado":"Trilha marcada como concluída"},
     {"ordem":2,"acao":"Abrir os certificados","resultado_esperado":"Certificado da trilha disponível"}]'::jsonb,
   'A conclusão produz certificado consultável.',
   'Componente CertificadosList.')

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Trilhas: antes=%, depois=% (esperado +13)', v_antes, v_depois;
END $doc$;
