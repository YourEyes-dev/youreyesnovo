-- =========================================================
-- ENTREGA QA — Leva 2 de módulos sem cobertura (92 casos de tela)
--
-- Cole este arquivo inteiro no SQL Editor do ambiente de HOMOLOGACAO
-- (projeto fgsblefvdabgdouipigz). Documenta os casos de TELA (nivel e2e)
-- dos módulos que ainda não tinham nenhum caso:
--   Avaliações (14), Trilhas (13), Feedback & Ocorrências (14),
--   Saúde Ocupacional/ASO (13), Mural Interno (13), Meu Bem-Estar (11),
--   Configurações (14).
--
-- Só INSERE dados (linhas em qa_casos_teste). Não cria nem altera
-- estrutura, então não mexe na fidelidade com a produção. Idempotente:
-- ON CONFLICT (codigo) DO NOTHING; rodar duas vezes não duplica.
-- Cada bloco procura o módulo pelo path; se não achar, avisa e pula
-- (RAISE NOTICE + RETURN dentro do IF) sem abortar os demais.
-- Roda inteiro em UMA transação — nada de tabela temporária entre passos.
--
-- Ao final, uma única conferência SELECT lista o que ficou registrado.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'desenvolvimento-performance/avaliacoes';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo desenvolvimento-performance/avaliacoes não encontrado.'; RETURN; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'AVAL-001', 'Tela de Avaliações abre com as abas do fluxo',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O módulo organiza a avaliação de desempenho em abas (Inbox, Ciclos, Formulário, Metas, Templates, Resultados, 9-Box, Config). Se a tela não monta, todo o processo de avaliação fica inacessível.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar Avaliações pelo menu","resultado_esperado":"Tela carrega sem erro"},
     {"ordem":2,"acao":"Conferir as abas disponíveis ao perfil","resultado_esperado":"Inbox, Ciclos, Formulário, Metas, Templates, Resultados, 9-Box e Config conforme permissão"}]'::jsonb,
   'As abas do módulo montam de acordo com o perfil.',
   'Âncoras: ids tab-aval-inbox, tab-aval-ciclos, tab-aval-formulario, tab-aval-metas, tab-aval-templates, tab-aval-resultados, tab-aval-9box, tab-aval-config.'),

  (v_mod, 'AVAL-002', 'Inbox lista as avaliações pendentes do usuário',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'A Inbox é a fila de "o que preciso responder". É a porta de entrada do avaliado e do avaliador.',
   'Usuário com ao menos uma avaliação atribuída.',
   '[{"ordem":1,"acao":"Abrir a aba Inbox","resultado_esperado":"Lista de avaliações pendentes/atribuídas monta"},
     {"ordem":2,"acao":"Conferir cada item","resultado_esperado":"Exibe tipo, ciclo e estado da avaliação"}]'::jsonb,
   'A Inbox mostra o que o usuário tem a fazer.',
   NULL),

  (v_mod, 'AVAL-003', 'Inbox vazia mostra estado orientativo',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Sem avaliações atribuídas, a Inbox deve orientar — não exibir erro nem spinner infinito.',
   'Usuário sem avaliações pendentes.',
   '[{"ordem":1,"acao":"Abrir a Inbox sem pendências","resultado_esperado":"Estado vazio amigável; sem erro"}]'::jsonb,
   'O vazio é tratado.', NULL),

  (v_mod, 'AVAL-010', 'Criar um ciclo de avaliação',
   'feliz', 'critica', 'aprovado', 'e2e', NULL,
   'O ciclo é o contêiner do processo (período, participantes, tipo). Sem criar ciclo não há avaliação para ninguém responder.',
   'Perfil gestor; aba Ciclos acessível.',
   '[{"ordem":1,"acao":"Abrir a aba Ciclos e iniciar um novo ciclo","resultado_esperado":"Formulário de ciclo abre"},
     {"ordem":2,"acao":"Preencher período e configurações do ciclo","resultado_esperado":"Campos aceitos"},
     {"ordem":3,"acao":"Salvar","resultado_esperado":"Ciclo criado aparece na lista de ciclos"}]'::jsonb,
   'O ciclo é criado e listado.', NULL),

  (v_mod, 'AVAL-011', 'Bloquear ciclo com período inválido (fim antes do início)',
   'negativo', 'alta', 'aprovado', 'e2e', NULL,
   'Período invertido gera prazos impossíveis. O formulário deve recusar data fim anterior à data início.',
   'Formulário de ciclo aberto.',
   '[{"ordem":1,"acao":"Informar data fim anterior à data início","resultado_esperado":"—"},
     {"ordem":2,"acao":"Tentar salvar","resultado_esperado":"Sistema impede e sinaliza o período"}]'::jsonb,
   'Período inconsistente é recusado.', NULL),

  (v_mod, 'AVAL-012', 'Definir tipos de avaliação do ciclo (auto, gestor, pares, 360)',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O tipo define quem avalia quem. As opções (autoavaliação, gestor, pares, 360) precisam estar disponíveis e persistir no ciclo.',
   'Formulário/config de ciclo aberto.',
   '[{"ordem":1,"acao":"Selecionar os tipos de avaliação do ciclo","resultado_esperado":"Opções aceitas"},
     {"ordem":2,"acao":"Salvar e reabrir o ciclo","resultado_esperado":"Os tipos escolhidos permanecem"}]'::jsonb,
   'A configuração de tipos persiste no ciclo.', NULL),

  (v_mod, 'AVAL-020', 'Construir/editar o formulário de avaliação',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O formulário são as competências/perguntas avaliadas. Montar e salvar o formulário é pré-requisito para responder.',
   'Perfil gestor; aba Formulário acessível.',
   '[{"ordem":1,"acao":"Abrir a aba Formulário","resultado_esperado":"Editor de formulário monta"},
     {"ordem":2,"acao":"Adicionar itens/competências e salvar","resultado_esperado":"Itens persistidos"}]'::jsonb,
   'O formulário de avaliação é editável e persiste.', NULL),

  (v_mod, 'AVAL-021', 'Salvar um template de avaliação para reuso',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Templates evitam remontar o formulário a cada ciclo. Salvar e reabrir um template deve preservar a estrutura.',
   'Aba Templates acessível.',
   '[{"ordem":1,"acao":"Salvar um formulário como template","resultado_esperado":"Template aparece na lista"},
     {"ordem":2,"acao":"Aplicar o template em um novo ciclo","resultado_esperado":"Estrutura reaproveitada"}]'::jsonb,
   'Templates são reutilizáveis.', NULL),

  (v_mod, 'AVAL-030', 'Responder uma avaliação da Inbox',
   'feliz', 'critica', 'aprovado', 'e2e', NULL,
   'O ato central do módulo: o avaliador abre o formulário, preenche e envia. É o que gera os resultados.',
   'Usuário com uma avaliação pendente na Inbox.',
   '[{"ordem":1,"acao":"Abrir uma avaliação pendente","resultado_esperado":"Formulário de resposta abre"},
     {"ordem":2,"acao":"Preencher as respostas e enviar","resultado_esperado":"Avaliação registrada; sai das pendências"}]'::jsonb,
   'A resposta é gravada e a pendência é resolvida.', NULL),

  (v_mod, 'AVAL-031', 'Bloquear envio de avaliação incompleta',
   'negativo', 'alta', 'aprovado', 'e2e', NULL,
   'Avaliação com itens obrigatórios em branco distorce os resultados. O envio deve exigir os itens obrigatórios.',
   'Formulário de resposta aberto.',
   '[{"ordem":1,"acao":"Deixar itens obrigatórios em branco","resultado_esperado":"—"},
     {"ordem":2,"acao":"Tentar enviar","resultado_esperado":"Sistema impede e aponta os itens faltantes"}]'::jsonb,
   'Não há envio de avaliação incompleta.', NULL),

  (v_mod, 'AVAL-040', 'Vincular metas ao ciclo/colaborador',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'A aba Metas conecta desempenho a objetivos. As metas do colaborador devem aparecer e ser gerenciáveis no contexto da avaliação.',
   'Aba Metas acessível; colaborador com metas.',
   '[{"ordem":1,"acao":"Abrir a aba Metas","resultado_esperado":"Metas do escopo montam"},
     {"ordem":2,"acao":"Conferir o vínculo com o ciclo/colaborador","resultado_esperado":"Metas exibidas coerentes com o contexto"}]'::jsonb,
   'A aba Metas integra objetivos à avaliação.', NULL),

  (v_mod, 'AVAL-050', 'Ver resultados consolidados de um ciclo',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'Resultados é onde o ciclo vira insight. Deve consolidar as respostas recebidas sem erro.',
   'Um ciclo com respostas registradas.',
   '[{"ordem":1,"acao":"Abrir a aba Resultados e selecionar o ciclo","resultado_esperado":"Consolidação monta"},
     {"ordem":2,"acao":"Conferir os números","resultado_esperado":"Coerentes com as respostas enviadas"}]'::jsonb,
   'Os resultados refletem as respostas do ciclo.', NULL),

  (v_mod, 'AVAL-051', 'Matriz 9-Box posiciona os avaliados',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O 9-Box cruza desempenho × potencial em 9 quadrantes — leitura estratégica de talentos. A matriz deve montar e posicionar os avaliados com dados.',
   'Ciclo com resultados suficientes.',
   '[{"ordem":1,"acao":"Abrir a aba 9-Box","resultado_esperado":"Matriz de 9 quadrantes monta"},
     {"ordem":2,"acao":"Conferir o posicionamento","resultado_esperado":"Avaliados distribuídos conforme desempenho × potencial"}]'::jsonb,
   'A matriz 9-Box representa os avaliados corretamente.', NULL),

  (v_mod, 'AVAL-060', 'Aba Config restrita ao perfil gestor',
   'negativo', 'critica', 'aprovado', 'e2e',
   'LGPD (avaliação é dado pessoal sensível de RH)',
   'Config e resultados agregados não são tela de colaborador. As abas administrativas seguem o perfil.',
   'Contas gestor e colaborador comum.',
   '[{"ordem":1,"acao":"Abrir Avaliações com perfil gestor","resultado_esperado":"Abas administrativas (Config, Templates, 9-Box, Resultados) visíveis"},
     {"ordem":2,"acao":"Abrir com colaborador comum","resultado_esperado":"Vê apenas Inbox/Formulário do próprio escopo; abas administrativas ausentes"}]'::jsonb,
   'A superfície administrativa respeita o papel.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Avaliações: antes=%, depois=% (esperado +14)', v_antes, v_depois;
END $doc$;

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'desenvolvimento-performance/trilhas';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo desenvolvimento-performance/trilhas não encontrado.'; RETURN; END IF;
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

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'pessoas-cultura/feedback-desenvolvimento';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo pessoas-cultura/feedback-desenvolvimento não encontrado.'; RETURN; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'FBK-001', 'Tela de Feedback & Ocorrências abre com as quatro abas',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O módulo separa registro e histórico de feedbacks e ocorrências em quatro abas. Se a tela não monta, gestor e colaborador perdem o canal estruturado de retorno.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar Feedback & Ocorrências pelo menu","resultado_esperado":"Tela carrega com o título Feedback & Ocorrências"},
     {"ordem":2,"acao":"Conferir as abas","resultado_esperado":"Novo Feedback, Feedbacks, Nova Ocorrência e Ocorrências disponíveis"}]'::jsonb,
   'As quatro abas do módulo montam.',
   'Âncoras: value feedback-novo, feedback-lista, ocorrencia-nova, ocorrencia-lista.'),

  (v_mod, 'FBK-010', 'Registrar um feedback estruturado',
   'feliz', 'critica', 'aprovado', 'e2e', NULL,
   'É o ato central: escolher colaborador, categoria e descrever o fato. Sem isso não há feedback documentado.',
   'Perfil com permissão de dar feedback; colaboradores no ambiente.',
   '[{"ordem":1,"acao":"Na aba Novo Feedback, selecionar o colaborador","resultado_esperado":"Colaborador selecionado"},
     {"ordem":2,"acao":"Escolher a categoria e descrever o fato","resultado_esperado":"Categoria marcada e descrição preenchida"},
     {"ordem":3,"acao":"Clicar em Registrar Feedback","resultado_esperado":"Feedback gravado; confirmação exibida"}]'::jsonb,
   'O feedback é registrado com colaborador, categoria e descrição.',
   'Componente FeedbackForm; botão Registrar Feedback.'),

  (v_mod, 'FBK-011', 'Bloquear feedback sem colaborador, categoria ou descrição',
   'negativo', 'alta', 'aprovado', 'e2e', NULL,
   'Feedback sem alvo, categoria ou fato é ruído. O botão de registrar só habilita com os três campos obrigatórios.',
   'Aba Novo Feedback aberta.',
   '[{"ordem":1,"acao":"Deixar colaborador, categoria ou descrição em branco","resultado_esperado":"—"},
     {"ordem":2,"acao":"Tentar registrar","resultado_esperado":"O botão Registrar Feedback permanece desabilitado"}]'::jsonb,
   'Não há registro de feedback incompleto.',
   'Botão desabilitado por !colaboradorId || !categoria || !descricao.'),

  (v_mod, 'FBK-012', 'Estruturar o feedback por IA',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Com descrição e categoria preenchidas, a IA propõe um texto estruturado. Com a chave configurada retorna sugestão; sem ela, avisa sem quebrar.',
   'Descrição e categoria preenchidas; chave de IA no ambiente.',
   '[{"ordem":1,"acao":"Clicar em Ajudar a estruturar feedback","resultado_esperado":"Processa e devolve texto estruturado (ou aviso claro)"},
     {"ordem":2,"acao":"Conferir a sugestão","resultado_esperado":"Texto editável aparece; sem falha muda"}]'::jsonb,
   'A estruturação por IA responde ou avisa.',
   'Botão Ajudar a estruturar feedback aparece só com descrição e categoria.'),

  (v_mod, 'FBK-013', 'Alternar o envio por e-mail ao colaborador',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'O feedback pode ser notificado por e-mail ao colaborador. O switch deve refletir a escolha antes do registro.',
   'Aba Novo Feedback aberta.',
   '[{"ordem":1,"acao":"Ligar/desligar o Enviar por e-mail ao colaborador","resultado_esperado":"O switch reflete o estado escolhido"}]'::jsonb,
   'A opção de envio por e-mail é controlável.',
   'Switch enviarEmail.'),

  (v_mod, 'FBK-020', 'Histórico de Feedbacks lista os registros',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'A aba Feedbacks é a memória do que foi dado. Deve montar a lista dos feedbacks registrados.',
   'Ao menos um feedback registrado.',
   '[{"ordem":1,"acao":"Abrir a aba Feedbacks","resultado_esperado":"Histórico de Feedbacks monta com os registros"}]'::jsonb,
   'O histórico de feedbacks é consultável.',
   'Componente FeedbackList; h2 Histórico de Feedbacks.'),

  (v_mod, 'FBK-021', 'Histórico de feedbacks vazio mostra estado orientativo',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'Sem feedbacks, a lista deve orientar — não exibir erro nem carregamento infinito.',
   'Usuário sem feedbacks visíveis.',
   '[{"ordem":1,"acao":"Abrir a aba Feedbacks sem registros","resultado_esperado":"Estado vazio amigável; sem erro"}]'::jsonb,
   'O vazio é tratado.', NULL),

  (v_mod, 'FBK-030', 'Registrar uma ocorrência',
   'feliz', 'critica', 'aprovado', 'e2e', NULL,
   'A ocorrência documenta um fato relevante do colaborador. Registrar é o que dá rastreabilidade ao evento.',
   'Perfil com permissão; aba Nova Ocorrência acessível.',
   '[{"ordem":1,"acao":"Abrir a aba Nova Ocorrência","resultado_esperado":"Formulário de ocorrência monta"},
     {"ordem":2,"acao":"Preencher os dados da ocorrência e salvar","resultado_esperado":"Ocorrência registrada; confirmação exibida"}]'::jsonb,
   'A ocorrência é registrada.',
   'Componente OcorrenciaForm.'),

  (v_mod, 'FBK-031', 'Gerar advertência vinculada a partir da ocorrência',
   'alternativo', 'alta', 'aprovado', 'e2e', NULL,
   'Ocorrências graves podem originar uma advertência formal vinculada. O gesto deve criar o vínculo sem duplicar a ocorrência.',
   'Uma ocorrência em contexto que permita advertência.',
   '[{"ordem":1,"acao":"Acionar a criação de advertência vinculada na ocorrência","resultado_esperado":"Advertência criada e ligada à ocorrência"}]'::jsonb,
   'A ocorrência gera advertência vinculada quando aplicável.',
   'onCreateAdvertenciaLink (criarAdvertenciaLink).'),

  (v_mod, 'FBK-040', 'Histórico de Ocorrências lista os registros',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'A aba Ocorrências guarda o histórico dos fatos registrados. Deve montar a lista.',
   'Ao menos uma ocorrência registrada.',
   '[{"ordem":1,"acao":"Abrir a aba Ocorrências","resultado_esperado":"Histórico de Ocorrências monta com os registros"}]'::jsonb,
   'O histórico de ocorrências é consultável.',
   'Componente OcorrenciaList; h2 Histórico de Ocorrências.'),

  (v_mod, 'FBK-050', 'Estatísticas do gestor aparecem só para gestor',
   'negativo', 'alta', 'aprovado', 'e2e',
   'LGPD (feedback e ocorrência são dados pessoais de RH)',
   'O painel de estatísticas consolida dados de várias pessoas — visão de gestão. Colaborador comum não deve vê-lo.',
   'Contas gestor e colaborador comum.',
   '[{"ordem":1,"acao":"Abrir o módulo com perfil gestor","resultado_esperado":"Bloco de estatísticas de feedbacks/ocorrências visível"},
     {"ordem":2,"acao":"Abrir com colaborador comum","resultado_esperado":"Estatísticas de gestão ausentes"}]'::jsonb,
   'O consolidado de gestão respeita o papel.',
   'FeedbackStats renderizado apenas com isManager.'),

  (v_mod, 'FBK-051', 'Feedback é dirigido ao escopo permitido do usuário',
   'negativo', 'alta', 'aprovado', 'e2e',
   'LGPD art. 6º (finalidade e necessidade)',
   'O seletor de colaborador não pode expor toda a base a quem só gerencia sua equipe. O escopo de destinatários segue o perfil.',
   'Perfil com escopo restrito (ex.: gestor de uma área).',
   '[{"ordem":1,"acao":"Abrir o seletor de colaborador no Novo Feedback","resultado_esperado":"Aparecem apenas colaboradores do escopo permitido"}]'::jsonb,
   'O alcance do feedback respeita o escopo do perfil.', NULL),

  (v_mod, 'FBK-060', 'Alternar entre as abas preserva o que foi digitado no formulário aberto',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'Trocar de aba por engano não deve descartar um rascunho longo de feedback ou ocorrência sem aviso.',
   'Formulário de feedback com texto digitado.',
   '[{"ordem":1,"acao":"Digitar uma descrição, alternar para outra aba e voltar","resultado_esperado":"O conteúdo digitado é preservado ou o descarte é avisado"}]'::jsonb,
   'A troca de abas não perde o rascunho silenciosamente.',
   'Comportamento observável; validar sem depender de implementação específica.'),

  (v_mod, 'FBK-070', 'Tela responde em largura de celular',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'O registro de feedback/ocorrência é usado por gestores em campo, no celular. As abas e o formulário não podem estourar o layout.',
   'Viewport de celular.',
   '[{"ordem":1,"acao":"Abrir o módulo em largura de celular","resultado_esperado":"Abas e formulário se ajustam sem quebra de layout"}]'::jsonb,
   'O módulo é utilizável no celular.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Feedback & Ocorrências: antes=%, depois=% (esperado +14)', v_antes, v_depois;
END $doc$;

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'jornada-rotina/saude-ocupacional';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo jornada-rotina/saude-ocupacional não encontrado.'; RETURN; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'ASO-001', 'Tela de Saúde Ocupacional abre com o painel de ASOs',
   'feliz', 'alta', 'aprovado', 'e2e',
   'NR-7 (PCMSO) / eSocial S-2220',
   'O módulo controla os exames ocupacionais (ASO) e sua periodicidade. Se a tela não monta, o RH perde a gestão do PCMSO.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar Saúde Ocupacional pelo menu","resultado_esperado":"Título Saúde Ocupacional (ASO) e painel carregam"},
     {"ordem":2,"acao":"Conferir os cards de resumo","resultado_esperado":"Total de ASOs, ASOs Vencidos e A Vencer (30 dias) presentes"}]'::jsonb,
   'O painel de ASOs monta com os cards de resumo.',
   'Âncoras: h1 Saúde Ocupacional (ASO); cards Total de ASOs / ASOs Vencidos / A Vencer (30 dias).'),

  (v_mod, 'ASO-002', 'Cards de resumo refletem os ASOs cadastrados',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'Os cards são a leitura rápida de compliance: quantos exames existem, quantos venceram, quantos vencem em 30 dias. Precisam bater com a lista.',
   'Alguns ASOs cadastrados com datas variadas.',
   '[{"ordem":1,"acao":"Conferir o número de Total de ASOs","resultado_esperado":"Igual à contagem de registros ocupacionais"},
     {"ordem":2,"acao":"Conferir ASOs Vencidos e A Vencer (30 dias)","resultado_esperado":"Coerentes com as datas de vencimento da lista"}]'::jsonb,
   'Os indicadores de vencimento são consistentes com os dados.', NULL),

  (v_mod, 'ASO-010', 'Registrar um novo ASO',
   'feliz', 'critica', 'aprovado', 'e2e',
   'NR-7 (PCMSO)',
   'Registrar o ASO é o que traz o exame para o controle. O formulário deve abrir, aceitar os dados e o exame passar a constar na lista.',
   'Perfil com permissão; colaborador cadastrado.',
   '[{"ordem":1,"acao":"Clicar em Novo ASO","resultado_esperado":"Formulário de ASO abre"},
     {"ordem":2,"acao":"Selecionar colaborador, subtipo e data do exame e salvar","resultado_esperado":"ASO registrado aparece na lista"}]'::jsonb,
   'O ASO é registrado e listado.',
   'Botão Novo ASO abre AtestadoForm (tipo ocupacional).'),

  (v_mod, 'ASO-011', 'Escolher o subtipo do exame (admissional, periódico, demissional)',
   'feliz', 'alta', 'aprovado', 'e2e',
   'NR-7 (tipos de exame do PCMSO)',
   'O subtipo do ASO define a finalidade e a periodicidade. As opções precisam estar disponíveis e persistir no registro.',
   'Formulário de ASO aberto.',
   '[{"ordem":1,"acao":"Selecionar o subtipo do exame","resultado_esperado":"Opções admissional, periódico e demissional disponíveis"},
     {"ordem":2,"acao":"Salvar e reabrir o registro","resultado_esperado":"O subtipo escolhido é exibido na lista"}]'::jsonb,
   'O subtipo do exame é registrado e refletido.',
   'subtipo_ocupacional: periodico / admissional / demissional.'),

  (v_mod, 'ASO-012', 'Bloquear ASO sem colaborador ou sem data do exame',
   'negativo', 'alta', 'aprovado', 'e2e', NULL,
   'ASO sem titular ou sem data não controla vencimento nem serve ao eSocial. O formulário deve exigir os campos essenciais.',
   'Formulário de ASO aberto.',
   '[{"ordem":1,"acao":"Deixar colaborador ou data do exame em branco","resultado_esperado":"—"},
     {"ordem":2,"acao":"Tentar salvar","resultado_esperado":"Sistema impede e aponta os campos obrigatórios"}]'::jsonb,
   'Não há registro de ASO sem os dados essenciais.', NULL),

  (v_mod, 'ASO-020', 'Buscar ASO por colaborador ou médico',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'A busca localiza o exame de uma pessoa ou do profissional que emitiu. Sem ela, achar um ASO numa base grande é inviável.',
   'ASOs cadastrados com nomes distintos.',
   '[{"ordem":1,"acao":"Digitar o nome de um colaborador no campo de busca","resultado_esperado":"A lista filtra para os ASOs desse colaborador"},
     {"ordem":2,"acao":"Buscar pelo nome do médico","resultado_esperado":"A lista filtra pelos exames do profissional"}]'::jsonb,
   'A busca por colaborador ou médico filtra a lista.',
   'placeholder Buscar por colaborador ou médico...'),

  (v_mod, 'ASO-021', 'Busca sem resultado mostra mensagem, não erro',
   'negativo', 'media', 'aprovado', 'e2e', NULL,
   'Buscar um nome inexistente deve resultar em lista vazia orientativa, não em quebra da tabela.',
   'Painel de ASOs aberto.',
   '[{"ordem":1,"acao":"Buscar um termo que não existe","resultado_esperado":"Mensagem Nenhum registro de ASO encontrado; sem erro"}]'::jsonb,
   'A busca sem resultado é tratada.',
   'Texto Nenhum registro de ASO encontrado.'),

  (v_mod, 'ASO-030', 'Status de vencimento classifica cada ASO',
   'feliz', 'critica', 'aprovado', 'e2e',
   'NR-7 (periodicidade dos exames)',
   'Regular, Próximo ao Vencimento e Vencido dizem ao RH o que agir. A classificação deve corresponder às datas.',
   'ASOs com datas que caiam em cada faixa.',
   '[{"ordem":1,"acao":"Conferir um ASO com vencimento futuro distante","resultado_esperado":"Status Regular"},
     {"ordem":2,"acao":"Conferir um ASO a vencer em até 30 dias","resultado_esperado":"Status Próximo ao Vencimento"},
     {"ordem":3,"acao":"Conferir um ASO com vencimento passado","resultado_esperado":"Status Vencido"}]'::jsonb,
   'O status de vencimento reflete corretamente a data.',
   'getStatusVencimento: Regular / Próximo ao Vencimento / Vencido.'),

  (v_mod, 'ASO-031', 'Próximo vencimento calculado a partir da data do exame',
   'feliz', 'alta', 'aprovado', 'e2e',
   'NR-7',
   'A coluna Próximo Vencimento orienta o agendamento do próximo exame. Deve derivar da data de emissão.',
   'ASO periódico cadastrado.',
   '[{"ordem":1,"acao":"Conferir a coluna Próximo Vencimento de um ASO periódico","resultado_esperado":"Data coerente com a periodicidade a partir da emissão"}]'::jsonb,
   'O próximo vencimento é calculado de forma consistente.',
   'getProximoVencimento (periódico ~1 ano).'),

  (v_mod, 'ASO-040', 'Apenas exames do tipo ocupacional aparecem no módulo',
   'negativo', 'alta', 'aprovado', 'e2e',
   'LGPD art. 11 (dado de saúde é sensível)',
   'Este módulo é do ASO (ocupacional), não do atestado clínico. Atestados de afastamento não devem vazar para cá.',
   'Base com atestados ocupacionais e não ocupacionais.',
   '[{"ordem":1,"acao":"Abrir a lista de Saúde Ocupacional","resultado_esperado":"Somente registros do tipo ocupacional aparecem"},
     {"ordem":2,"acao":"Conferir que atestados clínicos comuns não aparecem aqui","resultado_esperado":"Ausentes deste módulo"}]'::jsonb,
   'O módulo isola os exames ocupacionais.',
   'asos = atestados.filter(a => a.tipo === ocupacional).'),

  (v_mod, 'ASO-050', 'Painel vazio (sem ASOs) mostra estado orientativo',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Empresa nova sem exames deve ver um painel zerado e coerente, não erro nem números quebrados.',
   'Ambiente sem ASOs cadastrados.',
   '[{"ordem":1,"acao":"Abrir o módulo sem ASOs","resultado_esperado":"Cards zerados e lista com mensagem de vazio; sem erro"}]'::jsonb,
   'O estado vazio é tratado.', NULL),

  (v_mod, 'ASO-060', 'Acesso ao módulo respeita o perfil',
   'negativo', 'alta', 'aprovado', 'e2e',
   'LGPD art. 11 (dado de saúde ocupacional)',
   'Dados de saúde ocupacional são sensíveis. Quem não tem o módulo não deve alcançá-lo pela navegação.',
   'Conta sem permissão ao módulo.',
   '[{"ordem":1,"acao":"Tentar abrir Saúde Ocupacional sem permissão","resultado_esperado":"Acesso negado/ausente; sem dados de exame expostos"}]'::jsonb,
   'O módulo respeita a camada de acesso por perfil.', NULL),

  (v_mod, 'ASO-070', 'Painel responde em largura de celular',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'O RH consulta vencimentos no celular. Cards e tabela devem se ajustar com rolagem horizontal quando preciso, sem estourar o layout.',
   'Viewport de celular.',
   '[{"ordem":1,"acao":"Abrir o módulo em largura de celular","resultado_esperado":"Cards empilham e a tabela rola sem quebrar o layout"}]'::jsonb,
   'O painel é utilizável no celular.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Saúde Ocupacional (ASO): antes=%, depois=% (esperado +13)', v_antes, v_depois;
END $doc$;

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'pessoas-cultura/mural-interno';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo pessoas-cultura/mural-interno não encontrado.'; RETURN; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'MURAL-001', 'Mural Interno abre com o compositor e o feed',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O Mural é o canal social da empresa. Se a tela não monta, some o espaço de comunicação e reconhecimento entre colegas.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar Mural Interno pelo menu","resultado_esperado":"Título Mural Interno, compositor de post e feed carregam"}]'::jsonb,
   'O Mural monta com o compositor e a lista de posts.',
   'Âncoras: h1 Mural Interno; PostForm; PostCard.'),

  (v_mod, 'MURAL-010', 'Publicar um post de texto',
   'feliz', 'critica', 'aprovado', 'e2e', NULL,
   'Publicar texto é o uso básico do Mural. O post deve ser criado e aparecer no topo do feed.',
   'Usuário autenticado.',
   '[{"ordem":1,"acao":"Escrever um texto no compositor","resultado_esperado":"Texto aceito no campo No que você está pensando?"},
     {"ordem":2,"acao":"Publicar","resultado_esperado":"O post aparece no feed"}]'::jsonb,
   'O post de texto é publicado e listado.',
   'placeholder No que você está pensando?; botão de envio (Send).'),

  (v_mod, 'MURAL-011', 'Publicar um post com imagem',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'Fotos de eventos e conquistas fazem o Mural viver. O upload deve concluir e a imagem aparecer no post.',
   'Usuário autenticado; imagem válida até 5MB.',
   '[{"ordem":1,"acao":"Anexar uma imagem no compositor","resultado_esperado":"Pré-visualização da imagem exibida"},
     {"ordem":2,"acao":"Publicar","resultado_esperado":"Post publicado com a imagem"}]'::jsonb,
   'O post com imagem é publicado.',
   'handleImageSelect; uploadImagem.'),

  (v_mod, 'MURAL-012', 'Bloquear publicação vazia (sem texto e sem imagem)',
   'negativo', 'media', 'aprovado', 'e2e', NULL,
   'Post sem conteúdo polui o feed. A publicação só ocorre com texto ou imagem.',
   'Compositor aberto sem conteúdo.',
   '[{"ordem":1,"acao":"Tentar publicar sem texto e sem imagem","resultado_esperado":"A publicação não ocorre"}]'::jsonb,
   'Não há publicação vazia.',
   'Guard: !conteudo.trim() && !imagemFile.'),

  (v_mod, 'MURAL-013', 'Recusar imagem acima do limite de tamanho',
   'negativo', 'media', 'aprovado', 'e2e', NULL,
   'Imagem grande demais trava upload e estoura armazenamento. O compositor deve recusar acima de 5MB com aviso.',
   'Arquivo de imagem maior que 5MB.',
   '[{"ordem":1,"acao":"Selecionar uma imagem acima de 5MB","resultado_esperado":"Aviso de imagem muito grande; imagem não anexada"}]'::jsonb,
   'O limite de tamanho de imagem é respeitado.',
   'Alerta Imagem muito grande. Máximo 5MB.'),

  (v_mod, 'MURAL-020', 'Reagir a um post',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'As reações são o reconhecimento leve do Mural. Reagir deve marcar a reação do usuário e atualizar a contagem.',
   'Ao menos um post no feed.',
   '[{"ordem":1,"acao":"Clicar em uma reação no post","resultado_esperado":"Minha reação fica marcada e a contagem sobe"},
     {"ordem":2,"acao":"Clicar novamente para remover","resultado_esperado":"A reação é retirada e a contagem ajusta"}]'::jsonb,
   'As reações registram e refletem a interação.',
   'REACOES_CONFIG; handleReacao; minhaReacao.'),

  (v_mod, 'MURAL-021', 'Comentar em um post',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O comentário é a conversa do Mural. Abrir os comentários e enviar um deve exibi-lo e atualizar a contagem.',
   'Ao menos um post no feed.',
   '[{"ordem":1,"acao":"Abrir Comentar no post","resultado_esperado":"Lista de comentários expande"},
     {"ordem":2,"acao":"Escrever e enviar um comentário","resultado_esperado":"Comentário aparece e a contagem aumenta"}]'::jsonb,
   'O comentário é publicado e contabilizado.',
   'ComentariosList; contador Comentar / N comentário(s).'),

  (v_mod, 'MURAL-022', 'Mencionar um colega no comentário',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'A menção (@) chama a pessoa certa para a conversa. Digitar @ deve sugerir colegas para menção.',
   'Comentário em edição com colegas cadastrados.',
   '[{"ordem":1,"acao":"Digitar @ no comentário","resultado_esperado":"Sugestões de colegas para menção aparecem"},
     {"ordem":2,"acao":"Selecionar um colega","resultado_esperado":"A menção é inserida no texto"}]'::jsonb,
   'A menção por @ funciona no comentário.',
   'Componente MentionInput.'),

  (v_mod, 'MURAL-030', 'Excluir o próprio post',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'O autor pode remover o que publicou. Excluir deve tirar o post do feed.',
   'Um post publicado pelo próprio usuário.',
   '[{"ordem":1,"acao":"Abrir o menu do próprio post e escolher Excluir","resultado_esperado":"Confirmação e remoção do post"},
     {"ordem":2,"acao":"Conferir o feed","resultado_esperado":"O post não aparece mais"}]'::jsonb,
   'O autor consegue excluir o próprio post.',
   'Ação Excluir (Trash2) no PostCard.'),

  (v_mod, 'MURAL-031', 'Não oferecer exclusão em post de outro usuário',
   'negativo', 'alta', 'aprovado', 'e2e', NULL,
   'Ninguém apaga o post alheio. A opção de excluir só existe para o autor (ou moderação prevista).',
   'Um post de outro usuário no feed.',
   '[{"ordem":1,"acao":"Abrir um post de outra pessoa","resultado_esperado":"A ação Excluir não é oferecida ao usuário comum"}]'::jsonb,
   'A exclusão é restrita ao autor.', NULL),

  (v_mod, 'MURAL-040', 'Widget de avisos e felicitações preenche o compositor',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'O lateral sugere felicitar aniversariantes e marcos. Escolher uma felicitação deve pré-preencher o compositor.',
   'Widget de avisos disponível com sugestão.',
   '[{"ordem":1,"acao":"Acionar uma felicitação no widget lateral","resultado_esperado":"O compositor é pré-preenchido com a mensagem"}]'::jsonb,
   'A felicitação sugerida alimenta o compositor.',
   'AvisosCulturaWidget onFelicitar → prefillContent.'),

  (v_mod, 'MURAL-050', 'Feed vazio mostra estado orientativo',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'Empresa recém-criada abre o Mural sem posts. Deve ver um estado vazio convidativo, não erro.',
   'Ambiente sem posts.',
   '[{"ordem":1,"acao":"Abrir o Mural sem posts","resultado_esperado":"Estado vazio amigável; sem erro"}]'::jsonb,
   'O feed vazio é tratado.',
   'EmptyState.'),

  (v_mod, 'MURAL-060', 'Atualizar recarrega o feed',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'O Mural é dinâmico; o botão Atualizar traz o que os colegas publicaram sem recarregar a página.',
   'Feed carregado.',
   '[{"ordem":1,"acao":"Clicar em Atualizar","resultado_esperado":"O feed recarrega sem recarregar a página"}]'::jsonb,
   'A atualização do feed funciona.',
   'Botão Atualizar (refetch).')

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Mural Interno: antes=%, depois=% (esperado +13)', v_antes, v_depois;
END $doc$;

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'pessoas-cultura/bem-estar';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo pessoas-cultura/bem-estar não encontrado.'; RETURN; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'BEM-001', 'Meu Bem-Estar abre com o Mapa de Bem-Estar',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O módulo é o espaço de autopercepção do colaborador. Se a tela não monta, some a ferramenta de autoconhecimento.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar Meu Bem-Estar pelo menu","resultado_esperado":"Título Meu Bem-Estar no Trabalho e o Meu Mapa de Bem-Estar carregam"}]'::jsonb,
   'O módulo monta com o mapa de bem-estar.',
   'Âncoras: h1 Meu Bem-Estar no Trabalho; h2 Meu Mapa de Bem-Estar; BemEstarRadar.'),

  (v_mod, 'BEM-002', 'Aviso de espaço seguro é exibido',
   'feliz', 'critica', 'aprovado', 'e2e',
   'NR-1 (riscos psicossociais) / LGPD art. 6º (finalidade)',
   'O contrato de confiança do módulo: nada registrado ali serve para punição. O aviso precisa estar visível para o colaborador se sentir à vontade.',
   'Módulo aberto.',
   '[{"ordem":1,"acao":"Abrir o módulo e ler o aviso de privacidade","resultado_esperado":"Mensagem de Espaço seguro (uso não punitivo) visível"}]'::jsonb,
   'O aviso de espaço seguro é apresentado.',
   'Alert Espaço seguro / reflexões são pessoais.'),

  (v_mod, 'BEM-010', 'Radar mostra os sete eixos de bem-estar',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O radar traduz o bem-estar em eixos (emoções, propósito, relações, autonomia, autorrealização, presença, gratidão). Deve montar com todos os eixos.',
   'Módulo aberto.',
   '[{"ordem":1,"acao":"Conferir o radar do Mapa de Bem-Estar","resultado_esperado":"Os sete eixos aparecem no gráfico"}]'::jsonb,
   'O radar representa os sete eixos.',
   'EIXOS_CONFIG: emoções, propósito, relações, autonomia, autorrealização, presença, gratidão.'),

  (v_mod, 'BEM-011', 'Clicar em um eixo abre o painel do eixo',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'A interação central: clicar num eixo abre o painel para refletir e registrar. Sem isso o radar é só uma figura.',
   'Módulo aberto com o radar montado.',
   '[{"ordem":1,"acao":"Clicar em um eixo do radar","resultado_esperado":"O painel daquele eixo abre"},
     {"ordem":2,"acao":"Conferir o conteúdo do painel","resultado_esperado":"Título e itens de reflexão do eixo escolhido"}]'::jsonb,
   'O painel do eixo abre a partir do radar.',
   'onEixoClick → EixoPanel; texto Clique em qualquer eixo para interagir.'),

  (v_mod, 'BEM-020', 'Registrar uma resposta de reflexão no eixo',
   'feliz', 'critica', 'aprovado', 'e2e', NULL,
   'Registrar a resposta é o que alimenta o mapa e o histórico pessoal. Deve salvar e refletir no eixo.',
   'Painel de um eixo aberto.',
   '[{"ordem":1,"acao":"Responder um item de reflexão do eixo","resultado_esperado":"Resposta aceita"},
     {"ordem":2,"acao":"Salvar","resultado_esperado":"Resposta persistida; o mapa reflete a atualização"}]'::jsonb,
   'A resposta de reflexão é registrada.',
   'onSalvarResposta (salvarResposta).'),

  (v_mod, 'BEM-021', 'Eixo de gratidão permite registrar uma gratidão',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'O eixo de gratidão tem um registro próprio (o que agradeço). Deve aceitar e salvar a gratidão.',
   'Painel do eixo Gratidão aberto.',
   '[{"ordem":1,"acao":"Abrir o eixo de gratidão e escrever uma gratidão","resultado_esperado":"Entrada aceita"},
     {"ordem":2,"acao":"Salvar","resultado_esperado":"Gratidão registrada no eixo"}]'::jsonb,
   'O registro de gratidão funciona no eixo próprio.',
   'onSalvarGratidao (salvarGratidao), só quando selectedEixo === gratidao.'),

  (v_mod, 'BEM-030', 'Fechar o painel volta ao mapa',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'Fechar o painel devolve a visão do radar sem recarregar a tela.',
   'Painel de um eixo aberto.',
   '[{"ordem":1,"acao":"Fechar o painel do eixo","resultado_esperado":"Painel some e o mapa volta ao foco"}]'::jsonb,
   'O fechamento do painel retorna ao mapa.',
   'onClose → setSelectedEixo(null).'),

  (v_mod, 'BEM-040', 'As respostas persistem ao reabrir o módulo',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O valor do módulo é acompanhar a evolução. O que foi registrado precisa continuar lá numa nova visita.',
   'Ao menos uma resposta registrada anteriormente.',
   '[{"ordem":1,"acao":"Sair e reabrir Meu Bem-Estar","resultado_esperado":"O mapa reflete as respostas já registradas"}]'::jsonb,
   'O histórico de bem-estar persiste entre sessões.', NULL),

  (v_mod, 'BEM-050', 'Bem-estar do usuário é privado a ele',
   'negativo', 'critica', 'aprovado', 'e2e',
   'LGPD art. 6º e 11 (dado pessoal sensível; espaço não punitivo)',
   'A promessa de espaço seguro exige isolamento: um usuário não pode ver o mapa de outro. É o alicerce ético do módulo.',
   'Dois usuários com registros distintos.',
   '[{"ordem":1,"acao":"Abrir Meu Bem-Estar com o usuário A","resultado_esperado":"Vê apenas o próprio mapa e respostas"},
     {"ordem":2,"acao":"Confirmar que não há acesso ao mapa de outro colaborador","resultado_esperado":"Dados de terceiros nunca aparecem"}]'::jsonb,
   'O bem-estar registrado é estritamente pessoal.', NULL),

  (v_mod, 'BEM-060', 'Estado de carregamento e vazio sem quebra',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'Primeiro acesso, sem nenhuma resposta, deve mostrar carregamento e depois um mapa neutro — não erro.',
   'Usuário sem respostas registradas.',
   '[{"ordem":1,"acao":"Abrir o módulo pela primeira vez","resultado_esperado":"Carregando e depois mapa neutro; sem erro"}]'::jsonb,
   'Carregamento e vazio são tratados.',
   'Estado Carregando... enquanto isLoading.'),

  (v_mod, 'BEM-070', 'Módulo responde em largura de celular',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'A autopercepção acontece muitas vezes no celular. O radar e o painel de eixo devem se ajustar sem estourar o layout.',
   'Viewport de celular.',
   '[{"ordem":1,"acao":"Abrir o módulo em largura de celular","resultado_esperado":"Radar e painel se ajustam sem quebra de layout"}]'::jsonb,
   'O módulo é utilizável no celular.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Meu Bem-Estar: antes=%, depois=% (esperado +11)', v_antes, v_depois;
END $doc$;

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'sistema/configuracoes';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo sistema/configuracoes não encontrado.'; RETURN; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'CFG-001', 'Configurações abre com as abas administrativas (admin)',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'A tela concentra a administração do tenant. Para o admin, precisa montar com as cinco abas.',
   'Usuário administrador autenticado.',
   '[{"ordem":1,"acao":"Acessar Configurações pelo menu como admin","resultado_esperado":"Título Configurações e as abas carregam"},
     {"ordem":2,"acao":"Conferir as abas","resultado_esperado":"Usuários, Perfis & Acessos, eSocial, Auditoria e Logo presentes"}]'::jsonb,
   'As cinco abas administrativas montam para o admin.',
   'Âncoras: value usuarios, perfis, esocial, auditoria, logo.'),

  (v_mod, 'CFG-002', 'Configurações é inacessível ao usuário comum',
   'negativo', 'critica', 'aprovado', 'e2e',
   'LGPD art. 37 (governança) / princípio do menor privilégio',
   'Usuários, perfis, auditoria e eSocial são poder administrativo. Colaborador comum não pode alcançar essa superfície.',
   'Conta de colaborador comum.',
   '[{"ordem":1,"acao":"Tentar abrir Configurações como colaborador comum","resultado_esperado":"Abas administrativas ausentes/acesso negado"}]'::jsonb,
   'A superfície administrativa é restrita ao admin.',
   'Todas as TabsTrigger/TabsContent gated por isAdmin.'),

  (v_mod, 'CFG-010', 'Aba Usuários lista e gerencia usuários',
   'feliz', 'alta', 'aprovado', 'e2e',
   'LGPD art. 37 (registro de operações)',
   'É onde se cria e administra quem entra no sistema. A aba deve montar a gestão de usuários.',
   'Admin autenticado.',
   '[{"ordem":1,"acao":"Abrir a aba Usuários","resultado_esperado":"Lista/gestão de usuários monta"}]'::jsonb,
   'A gestão de usuários é acessível ao admin.',
   'Componente UsuariosContent.'),

  (v_mod, 'CFG-011', 'Aba Perfis & Acessos monta a gestão de perfis',
   'feliz', 'critica', 'aprovado', 'e2e',
   'LGPD art. 6º (necessidade) / camada perfil_permite_modulo',
   'Perfis definem o que cada papel vê e faz — o coração da camada de acesso. A aba deve montar a gestão de perfis.',
   'Admin autenticado.',
   '[{"ordem":1,"acao":"Abrir a aba Perfis & Acessos","resultado_esperado":"Gestão de perfis e permissões monta"}]'::jsonb,
   'A gestão de perfis é acessível ao admin.',
   'Componente PerfisContent.'),

  (v_mod, 'CFG-012', 'Editar um perfil altera o acesso do papel',
   'feliz', 'critica', 'aprovado', 'e2e',
   'camada perfil_permite_modulo + políticas RESTRICTIVE',
   'A edição de perfil precisa persistir e valer: liberar/restringir um módulo muda o que o papel enxerga. É o teste que prova que a camada de acesso é operável pela tela.',
   'Admin; um perfil editável.',
   '[{"ordem":1,"acao":"Abrir um perfil e alterar o acesso a um módulo","resultado_esperado":"Alteração aceita"},
     {"ordem":2,"acao":"Salvar e reabrir o perfil","resultado_esperado":"A alteração persiste"}]'::jsonb,
   'A edição de perfil persiste e reflete no acesso.',
   'Sensível: mudança de perfil afeta a camada de leitura.'),

  (v_mod, 'CFG-020', 'Aba eSocial monta a configuração de integração',
   'feliz', 'alta', 'aprovado', 'e2e',
   'eSocial (obrigações trabalhistas)',
   'O eSocial é a ponte com as obrigações do governo. A aba deve montar a configuração sem erro.',
   'Admin autenticado.',
   '[{"ordem":1,"acao":"Abrir a aba eSocial","resultado_esperado":"Configuração do eSocial monta"}]'::jsonb,
   'A configuração do eSocial é acessível ao admin.',
   'Componente EsocialConfig.'),

  (v_mod, 'CFG-030', 'Aba Auditoria mostra o histórico de operações',
   'feliz', 'alta', 'aprovado', 'e2e',
   'LGPD art. 37 (registro das operações de tratamento)',
   'A auditoria é a prova de quem fez o quê. A aba deve montar o histórico para consulta.',
   'Admin autenticado.',
   '[{"ordem":1,"acao":"Abrir a aba Auditoria","resultado_esperado":"Registro de auditoria monta"}]'::jsonb,
   'A auditoria é consultável pelo admin.',
   'Componente AuditoriaTab.'),

  (v_mod, 'CFG-031', 'Auditoria é somente leitura',
   'negativo', 'alta', 'aprovado', 'e2e',
   'LGPD art. 37 (integridade do registro)',
   'Registro de auditoria que se pode apagar não vale como prova. A aba não deve oferecer edição/exclusão dos eventos.',
   'Admin na aba Auditoria com eventos.',
   '[{"ordem":1,"acao":"Conferir as ações disponíveis sobre um evento de auditoria","resultado_esperado":"Apenas consulta; sem editar ou excluir registros"}]'::jsonb,
   'A auditoria preserva a integridade do histórico.', NULL),

  (v_mod, 'CFG-040', 'Aba Logo permite personalizar a marca da empresa',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'A logo aparece no sistema e em documentos. A aba deve montar o envio e a troca da imagem da empresa.',
   'Admin autenticado; imagem válida.',
   '[{"ordem":1,"acao":"Abrir a aba Logo","resultado_esperado":"Gestão da logo da empresa monta"},
     {"ordem":2,"acao":"Enviar uma imagem de logo","resultado_esperado":"Upload conclui e a logo é atualizada"}]'::jsonb,
   'A logo da empresa é personalizável.',
   'Componente EmpresaLogoTab.'),

  (v_mod, 'CFG-050', 'Banner de configuração inicial pendente aparece quando há pendência',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Tenant recém-criado precisa ser guiado a finalizar a configuração. O aviso e o atalho devem aparecer enquanto houver pendência.',
   'Tenant com configuração inicial incompleta.',
   '[{"ordem":1,"acao":"Abrir Configurações com a configuração inicial pendente","resultado_esperado":"Banner Configuração inicial pendente e ação Finalizar Configuração visíveis"}]'::jsonb,
   'O onboarding de configuração é sinalizado.',
   'Textos Configuração inicial pendente / Finalizar Configuração.'),

  (v_mod, 'CFG-051', 'Sem pendência, o banner de configuração não aparece',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'Depois de configurado, o aviso não deve poluir a tela.',
   'Tenant com configuração inicial concluída.',
   '[{"ordem":1,"acao":"Abrir Configurações com a configuração concluída","resultado_esperado":"Banner de pendência ausente"}]'::jsonb,
   'O banner some quando a configuração está completa.', NULL),

  (v_mod, 'CFG-060', 'Alternar entre as abas mantém a tela estável',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'O admin transita entre as áreas o tempo todo. A troca de abas deve montar cada conteúdo sem erro nem estado preso.',
   'Admin autenticado.',
   '[{"ordem":1,"acao":"Percorrer as abas Usuários, Perfis, eSocial, Auditoria e Logo","resultado_esperado":"Cada aba monta seu conteúdo sem erro"}]'::jsonb,
   'A navegação entre abas é estável.', NULL),

  (v_mod, 'CFG-070', 'Criar usuário exige os campos essenciais',
   'negativo', 'alta', 'aprovado', 'e2e', NULL,
   'Usuário sem e-mail/identificação ou sem papel não entra de forma útil. A criação deve exigir os campos essenciais.',
   'Admin na aba Usuários.',
   '[{"ordem":1,"acao":"Tentar criar um usuário deixando campos essenciais em branco","resultado_esperado":"Sistema impede e aponta os campos obrigatórios"}]'::jsonb,
   'Não há criação de usuário incompleto.', NULL),

  (v_mod, 'CFG-080', 'Tela de Configurações responde em largura de celular',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'O admin às vezes ajusta algo pelo celular. As abas colapsam para ícones e o conteúdo se ajusta sem estourar o layout.',
   'Admin; viewport de celular.',
   '[{"ordem":1,"acao":"Abrir Configurações em largura de celular","resultado_esperado":"Abas viram ícones e o conteúdo se ajusta sem quebra"}]'::jsonb,
   'Configurações é utilizável no celular.',
   'Rótulos das abas usam hidden sm:inline.')

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Configurações: antes=%, depois=% (esperado +14)', v_antes, v_depois;
END $doc$;

-- =========================================================
-- CONFERÊNCIA (o SQL Editor mostra só o último resultado)
-- Esperado: 7 linhas, uma por módulo, com a contagem de casos abaixo.
-- =========================================================
SELECT m.path AS modulo,
       count(c.*) AS casos,
       min(c.codigo) AS primeiro,
       max(c.codigo) AS ultimo
FROM public.qa_modulos m
JOIN public.qa_casos_teste c ON c.modulo_id = m.id
WHERE m.path IN (
        'desenvolvimento-performance/avaliacoes',
        'desenvolvimento-performance/trilhas',
        'pessoas-cultura/feedback-desenvolvimento',
        'jornada-rotina/saude-ocupacional',
        'pessoas-cultura/mural-interno',
        'pessoas-cultura/bem-estar',
        'sistema/configuracoes')
  AND c.nivel = 'e2e'
GROUP BY m.path
ORDER BY m.path;
