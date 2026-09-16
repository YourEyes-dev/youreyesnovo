-- =========================================================
-- QA — Avaliações: primeira documentação de casos do módulo (14 casos)
--
-- Módulo desenvolvimento-performance/avaliacoes, zero casos até aqui.
-- Casos de TELA (nivel e2e) ancorados em src/pages/Avaliacoes.tsx +
-- components/avaliacoes/*: 8 abas (Inbox, Ciclos, Formulário, Metas,
-- Templates, Resultados, 9-Box, Config), stats, ciclos de avaliação
-- (autoavaliação/gestor/pares/360), formulário de resposta, matriz 9-Box.
--
-- Regra da casa: caso e2e sem spec só gera aviso na guarda.
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'desenvolvimento-performance/avaliacoes';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo desenvolvimento-performance/avaliacoes não encontrado.'; END IF;
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
