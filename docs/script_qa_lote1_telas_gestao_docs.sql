-- =========================================================
-- ENTREGA QA — Lote 1 de telas (36 casos e2e em 4 módulos só-motor)
--
-- Cole este arquivo inteiro no SQL Editor do ambiente de HOMOLOGACAO
-- (projeto fgsblefvdabgdouipigz). Documenta o LADO DE TELA (nivel e2e) de
-- quatro módulos que tinham só sondas de motor:
--   Metas (9), Plano de Ação (9), Documentos (9), Hub Contábil (9).
-- Códigos <MOD>-TELA-NN, sem colisão com as sondas (MCHK/PLEV/DOC/HUB/...).
--
-- Só INSERE linhas em qa_casos_teste — não cria nem altera estrutura, então
-- não mexe na fidelidade com a producao. Idempotente: ON CONFLICT DO NOTHING.
-- Cada bloco procura o módulo pelo path; se não achar, avisa e pula (RAISE
-- NOTICE + RETURN dentro do IF) sem abortar os demais. Roda em UMA transacao.
-- Ao final, uma unica conferencia SELECT lista o registrado por módulo.
-- =========================================================

SET lock_timeout = '10s';

-- ══════════════════════════════════════════════════════════
-- METAS  (planejamento-gestao/metas)  — rota /metas
-- ══════════════════════════════════════════════════════════
DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'planejamento-gestao/metas';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo planejamento-gestao/metas não encontrado — nada a fazer.'; RETURN; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'METAS-TELA-01', 'Módulo Metas abre com o cabeçalho e as abas',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'Porta de entrada do módulo: se não monta, o RH perde o planejamento e o acompanhamento de metas.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar /metas pelo menu","resultado_esperado":"Título Metas carrega"},
     {"ordem":2,"acao":"Conferir as abas e a ação principal","resultado_esperado":"Abas Visão Geral, Minhas Metas, Consolidação e Assistente IA; botão Nova Meta"}]'::jsonb,
   'O módulo monta com o cabeçalho, as abas e o botão Nova Meta.', NULL),

  (v_mod, 'METAS-TELA-02', 'Visão Geral mostra os cards por nível',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'A aba inicial resume as metas por nível da organização. É o panorama que orienta onde agir.',
   'Aba Visão Geral (padrão ao abrir).',
   '[{"ordem":1,"acao":"Abrir a aba Visão Geral","resultado_esperado":"Aparecem os cards rápidos por nível, com a contagem de metas de cada um"}]'::jsonb,
   'A Visão Geral resume as metas por nível.', NULL),

  (v_mod, 'METAS-TELA-03', 'Abrir o formulário de Nova Meta',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'Criar meta é o ato central do módulo. O formulário precisa abrir com os campos da meta.',
   'Rota /metas.',
   '[{"ordem":1,"acao":"Clicar em Nova Meta","resultado_esperado":"Abre o diálogo Nova Meta com o formulário da meta (nível, título e demais campos)"},
     {"ordem":2,"acao":"Fechar sem salvar","resultado_esperado":"O diálogo fecha sem criar nada"}]'::jsonb,
   'O formulário de Nova Meta abre e fecha sem efeito colateral.', NULL),

  (v_mod, 'METAS-TELA-04', 'Minhas Metas lista e filtra por nível',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'A aba de lista é onde se acompanha e filtra as metas. O filtro por nível recorta a lista.',
   'Aba Minhas Metas.',
   '[{"ordem":1,"acao":"Abrir a aba Minhas Metas","resultado_esperado":"A lista das metas aparece, com o filtro por nível (Todas + níveis), cada um com a contagem"},
     {"ordem":2,"acao":"Escolher um nível no filtro","resultado_esperado":"A lista recorta para aquele nível"}]'::jsonb,
   'A lista de metas monta e o filtro por nível funciona.', NULL),

  (v_mod, 'METAS-TELA-05', 'Consolidação abre sem erro',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'A consolidação cruza as metas dos níveis. Deve montar mesmo com poucos dados.',
   'Aba Consolidação.',
   '[{"ordem":1,"acao":"Abrir a aba Consolidação","resultado_esperado":"O painel de consolidação carrega sem erro"}]'::jsonb,
   'A Consolidação abre sem quebrar.', NULL),

  (v_mod, 'METAS-TELA-06', 'Assistente IA abre e degrada sem a chave',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'O assistente de IA ajuda a redigir/desdobrar metas. Sem a chave de IA, deve avisar com elegância, nunca derrubar a aba.',
   'Aba Assistente IA.',
   '[{"ordem":1,"acao":"Abrir a aba Assistente IA","resultado_esperado":"O assistente carrega"},
     {"ordem":2,"acao":"Acionar sem a chave de IA configurada","resultado_esperado":"Mostra aviso claro; a tela não quebra"}]'::jsonb,
   'O assistente abre e trata a ausência de IA sem quebrar.', NULL),

  (v_mod, 'METAS-TELA-07', 'Guia rápido abre',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'O guia rápido explica o módulo para quem chega. É apoio de adoção.',
   'Rota /metas.',
   '[{"ordem":1,"acao":"Clicar em Guia","resultado_esperado":"Abre o guia rápido de Metas"}]'::jsonb,
   'O guia rápido abre.', NULL),

  (v_mod, 'METAS-TELA-08', 'Indicadores e Configurações só para quem tem permissão',
   'excecao', 'media', 'aprovado', 'e2e', 'Menor privilégio',
   'As áreas de Indicadores e Configurações são de gestão. Um usuário sem permissão não deve sequer vê-las.',
   'Comparar um usuário com permissão de configuração e outro sem.',
   '[{"ordem":1,"acao":"Abrir /metas com permissão de configuração","resultado_esperado":"Aparecem as ações Indicadores e Configurações"},
     {"ordem":2,"acao":"Abrir com um usuário sem essa permissão","resultado_esperado":"Indicadores e Configurações não aparecem"}]'::jsonb,
   'As áreas de gestão respeitam a permissão do perfil.', NULL),

  (v_mod, 'METAS-TELA-09', 'Estado vazio orienta a criar a primeira meta',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Sem metas, a tela não pode ficar em branco: precisa orientar a criar a primeira, sem erro.',
   'Ambiente sem metas cadastradas.',
   '[{"ordem":1,"acao":"Abrir Minhas Metas sem nenhuma meta","resultado_esperado":"A lista mostra um vazio orientativo (criar a primeira via Nova Meta), sem quebrar"}]'::jsonb,
   'O vazio de metas orienta e não quebra.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Metas (tela): antes=%, depois=% (esperado +9)', v_antes, v_depois;
END $doc$;

-- ══════════════════════════════════════════════════════════
-- PLANO DE AÇÃO  (planejamento-gestao/plano-de-acao)  — rota /plano-acao
-- ══════════════════════════════════════════════════════════
DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'planejamento-gestao/plano-de-acao';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo planejamento-gestao/plano-de-acao não encontrado — nada a fazer.'; RETURN; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'PACAO-TELA-01', 'Módulo Plano de Ação abre com estatísticas e abas',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O módulo organiza as ações (5W2H / Matriz GUT). Se não monta, o acompanhamento das ações se perde.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar /plano-acao","resultado_esperado":"Título Plano de Ação carrega"},
     {"ordem":2,"acao":"Conferir os cartões de estatística e as abas","resultado_esperado":"Cartões de resumo; abas Todas, Minha Caixa e Críticas; botão Nova Ação"}]'::jsonb,
   'O módulo monta com estatísticas, abas e o botão Nova Ação.', NULL),

  (v_mod, 'PACAO-TELA-02', 'Abrir o formulário de Nova Ação',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'Criar ação é o ato central. O modal precisa abrir com o formulário (5W2H e prioridade GUT).',
   'Rota /plano-acao.',
   '[{"ordem":1,"acao":"Clicar em Nova Ação","resultado_esperado":"Abre o modal de nova ação com o formulário"},
     {"ordem":2,"acao":"Fechar sem salvar","resultado_esperado":"O modal fecha sem criar nada"}]'::jsonb,
   'O formulário de Nova Ação abre e fecha sem efeito colateral.', NULL),

  (v_mod, 'PACAO-TELA-03', 'Busca filtra por código, título, descrição ou responsável',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'A busca é o caminho rápido para achar uma ação. Deve recortar a lista pelo termo.',
   'Existirem ações na carteira.',
   '[{"ordem":1,"acao":"Digitar um termo na busca","resultado_esperado":"A lista recorta para as ações que casam com código, título, descrição ou responsável"}]'::jsonb,
   'A busca recorta a lista pelo termo.', NULL),

  (v_mod, 'PACAO-TELA-04', 'Chips de status filtram a lista',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Os chips de status são o filtro de um clique. Devem alternar e recortar a lista.',
   'Rota /plano-acao.',
   '[{"ordem":1,"acao":"Clicar no chip Pendentes (e depois Em andamento / Concluídas)","resultado_esperado":"A lista recorta para o status escolhido; clicar de novo desativa o filtro"}]'::jsonb,
   'Os chips de status filtram e alternam.', NULL),

  (v_mod, 'PACAO-TELA-05', 'Chips de prioridade filtram (Imediato / Urgente)',
   'feliz', 'baixa', 'aprovado', 'e2e', NULL,
   'A prioridade GUT vira chip de filtro para achar o que não pode esperar.',
   'Rota /plano-acao.',
   '[{"ordem":1,"acao":"Clicar no chip Imediato ou Urgente","resultado_esperado":"A lista recorta pela prioridade escolhida"}]'::jsonb,
   'Os chips de prioridade filtram a lista.', NULL),

  (v_mod, 'PACAO-TELA-06', 'Minha Caixa mostra as ações do usuário',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'A caixa pessoal reúne o que é do usuário (responsável ou criador), com contador — é o foco do dia a dia.',
   'Aba Minha Caixa.',
   '[{"ordem":1,"acao":"Abrir a aba Minha Caixa","resultado_esperado":"Aparecem as ações onde o usuário é responsável ou criador; o contador reflete o total"}]'::jsonb,
   'A Minha Caixa reúne as ações do usuário com contador.', NULL),

  (v_mod, 'PACAO-TELA-07', 'Críticas lista só o crítico e o atrasado',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'A aba Críticas recorta imediato, urgente e atrasado — o que exige ação agora. Sem nenhum, orienta o vazio.',
   'Aba Críticas.',
   '[{"ordem":1,"acao":"Abrir a aba Críticas","resultado_esperado":"Só aparecem ações imediatas, urgentes ou com prazo vencido"},
     {"ordem":2,"acao":"Conferir quando não há nenhuma","resultado_esperado":"Mostra Nenhuma ação crítica ou atrasada"}]'::jsonb,
   'A aba Críticas recorta o urgente e trata o vazio.', NULL),

  (v_mod, 'PACAO-TELA-08', 'Filtros avançados abrem e limpam',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'Além dos chips, há um painel de filtros avançados. Deve abrir, aplicar e limpar sem travar.',
   'Rota /plano-acao.',
   '[{"ordem":1,"acao":"Clicar em Filtros","resultado_esperado":"O painel de filtros avançados abre"},
     {"ordem":2,"acao":"Limpar os filtros","resultado_esperado":"O painel zera os filtros e a lista volta ao completo"}]'::jsonb,
   'Os filtros avançados abrem e limpam.', NULL),

  (v_mod, 'PACAO-TELA-09', 'Cartões de estatística refletem a carteira',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Os cartões de resumo são o pulso da carteira. Devem bater com a lista e servir de atalho de filtro.',
   'Rota /plano-acao.',
   '[{"ordem":1,"acao":"Conferir os cartões de estatística","resultado_esperado":"As contagens refletem a carteira; clicar num cartão filtra a lista pelo recorte dele"}]'::jsonb,
   'Os cartões de estatística refletem a carteira e filtram.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Plano de Ação (tela): antes=%, depois=% (esperado +9)', v_antes, v_depois;
END $doc$;

-- ══════════════════════════════════════════════════════════
-- DOCUMENTOS  (documentos-governanca/documentos)  — rota /documentos
-- ══════════════════════════════════════════════════════════
DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'documentos-governanca/documentos';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo documentos-governanca/documentos não encontrado — nada a fazer.'; RETURN; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'DOCS-TELA-01', 'Módulo Documentos abre com as abas',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'A gestão documental é a espinha de conformidade. Se não monta, some o acervo e o controle de validade.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar /documentos","resultado_esperado":"Título Documentos carrega"},
     {"ordem":2,"acao":"Conferir as abas e as ações","resultado_esperado":"Abas Estrutura, Conformidade, Governança, PDCA, Notificações e Auditoria; botões Nova Pasta e Upload"}]'::jsonb,
   'O módulo monta com as abas e as ações de pasta e upload.', NULL),

  (v_mod, 'DOCS-TELA-02', 'Estrutura mostra a árvore de pastas (ou vazio orientativo)',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'A aba Estrutura é a navegação do acervo. Deve mostrar a árvore, ou um vazio que orienta a começar.',
   'Aba Estrutura (padrão).',
   '[{"ordem":1,"acao":"Abrir a aba Estrutura","resultado_esperado":"Aparece a árvore de pastas; sem pastas, um vazio orientativo, sem quebrar"}]'::jsonb,
   'A Estrutura mostra a árvore ou um vazio orientativo.', NULL),

  (v_mod, 'DOCS-TELA-03', 'Abrir o formulário de Nova Pasta',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Organizar o acervo começa por criar pasta. O formulário precisa abrir.',
   'Rota /documentos.',
   '[{"ordem":1,"acao":"Clicar em Nova Pasta","resultado_esperado":"Abre o formulário de nova pasta"},
     {"ordem":2,"acao":"Fechar sem salvar","resultado_esperado":"Fecha sem criar nada"}]'::jsonb,
   'O formulário de Nova Pasta abre e fecha sem efeito.', NULL),

  (v_mod, 'DOCS-TELA-04', 'Abrir o formulário de Upload',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'Subir documento é o ato central do acervo. O formulário de upload precisa abrir.',
   'Rota /documentos.',
   '[{"ordem":1,"acao":"Clicar em Upload","resultado_esperado":"Abre o formulário de envio de documento (seleção de arquivo e destino)"}]'::jsonb,
   'O formulário de Upload abre.', NULL),

  (v_mod, 'DOCS-TELA-05', 'Conformidade abre',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'A aba Conformidade mostra o que está em dia e o que falta. Deve montar sem erro.',
   'Aba Conformidade.',
   '[{"ordem":1,"acao":"Abrir a aba Conformidade","resultado_esperado":"O painel de conformidade carrega"}]'::jsonb,
   'A Conformidade abre sem quebrar.', NULL),

  (v_mod, 'DOCS-TELA-06', 'Governança abre',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'A aba Governança (radar) traz a visão de risco documental. Deve montar sem erro.',
   'Aba Governança.',
   '[{"ordem":1,"acao":"Abrir a aba Governança","resultado_esperado":"O radar de governança carrega"}]'::jsonb,
   'A Governança abre sem quebrar.', NULL),

  (v_mod, 'DOCS-TELA-07', 'PDCA abre',
   'feliz', 'baixa', 'aprovado', 'e2e', NULL,
   'A aba PDCA acompanha o ciclo de melhoria dos documentos. Deve montar sem erro.',
   'Aba PDCA.',
   '[{"ordem":1,"acao":"Abrir a aba PDCA","resultado_esperado":"O painel do ciclo PDCA carrega"}]'::jsonb,
   'O PDCA abre sem quebrar.', NULL),

  (v_mod, 'DOCS-TELA-08', 'Notificações sinaliza vencidos e a vencer',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Documento vencido é risco. A aba Notificações deve destacar vencidos e a vencer — com o selo no próprio nome da aba.',
   'Existirem documentos com validade.',
   '[{"ordem":1,"acao":"Conferir o selo na aba Notificações","resultado_esperado":"Quando há vencidos/vencendo, a aba exibe o contador"},
     {"ordem":2,"acao":"Abrir a aba Notificações","resultado_esperado":"A lista de vencidos e a vencer aparece"}]'::jsonb,
   'As Notificações sinalizam vencidos e a vencer.', NULL),

  (v_mod, 'DOCS-TELA-09', 'Auditoria mostra o histórico',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'A trilha de auditoria registra o que aconteceu com cada documento. É a prova na fiscalização.',
   'Aba Auditoria.',
   '[{"ordem":1,"acao":"Abrir a aba Auditoria","resultado_esperado":"O histórico de ações sobre os documentos aparece"}]'::jsonb,
   'A Auditoria mostra o histórico.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Documentos (tela): antes=%, depois=% (esperado +9)', v_antes, v_depois;
END $doc$;

-- ══════════════════════════════════════════════════════════
-- HUB CONTÁBIL  (documentos-governanca/hub-contabil)  — rota /hub-contabil
-- ══════════════════════════════════════════════════════════
DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'documentos-governanca/hub-contabil';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo documentos-governanca/hub-contabil não encontrado — nada a fazer.'; RETURN; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'HUBC-TELA-01', 'Hub Contábil abre com o painel e as abas por tipo',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O hub centraliza a comunicação entre DP, RH e Contabilidade. Se não monta, os processos ficam sem trilha comum.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar /hub-contabil","resultado_esperado":"Título Hub de Comunicação Contábil carrega"},
     {"ordem":2,"acao":"Conferir as abas","resultado_esperado":"Painel, Admissão, Demissão, Férias, Advertência, Folha/Ponto, Atestados, Geral, Todos, Kanban, Colaboradores, Relatórios e Config."}]'::jsonb,
   'O módulo monta com o painel e as abas por tipo.', NULL),

  (v_mod, 'HUBC-TELA-02', 'Painel resume os processos abertos',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'O painel é o pulso do hub: quantos processos abertos, por tipo. Orienta onde agir.',
   'Aba Painel (padrão).',
   '[{"ordem":1,"acao":"Abrir a aba Painel","resultado_esperado":"O resumo dos processos abertos carrega; as abas por tipo trazem o contador de pendentes"}]'::jsonb,
   'O Painel resume os processos abertos.', NULL),

  (v_mod, 'HUBC-TELA-03', 'Abrir o modal de Novo processo',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'Abrir processo é o ato central do hub. O modal precisa abrir com o formulário.',
   'Rota /hub-contabil.',
   '[{"ordem":1,"acao":"Acionar Novo processo (pelo Painel ou por uma aba de tipo)","resultado_esperado":"Abre o modal de novo processo com o formulário"},
     {"ordem":2,"acao":"Fechar sem salvar","resultado_esperado":"Fecha sem criar nada"}]'::jsonb,
   'O modal de Novo processo abre e fecha sem efeito.', NULL),

  (v_mod, 'HUBC-TELA-04', 'Abas por tipo listam os processos do tipo',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Cada tipo (admissão, férias, atestado...) tem sua aba, que recorta os processos daquele tipo.',
   'Rota /hub-contabil.',
   '[{"ordem":1,"acao":"Abrir uma aba de tipo (ex.: Férias ou Admissão)","resultado_esperado":"A lista mostra só os processos daquele tipo; o contador da aba bate com a lista"}]'::jsonb,
   'As abas por tipo recortam os processos.', NULL),

  (v_mod, 'HUBC-TELA-05', 'Kanban mostra os processos por status',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'O Kanban dá a visão de fluxo: cada processo na sua coluna de status. É o acompanhamento visual.',
   'Aba Kanban.',
   '[{"ordem":1,"acao":"Abrir a aba Kanban","resultado_esperado":"As colunas por status aparecem com os processos distribuídos"}]'::jsonb,
   'O Kanban distribui os processos por status.', NULL),

  (v_mod, 'HUBC-TELA-06', 'Colaboradores mostra a linha do tempo',
   'feliz', 'baixa', 'aprovado', 'e2e', NULL,
   'A visão por colaborador reúne os processos de cada pessoa numa linha do tempo.',
   'Aba Colaboradores.',
   '[{"ordem":1,"acao":"Abrir a aba Colaboradores","resultado_esperado":"A linha do tempo por colaborador carrega"}]'::jsonb,
   'A aba Colaboradores mostra a linha do tempo.', NULL),

  (v_mod, 'HUBC-TELA-07', 'Relatórios abre',
   'feliz', 'baixa', 'aprovado', 'e2e', NULL,
   'A aba Relatórios consolida os números do hub para prestação de contas.',
   'Aba Relatórios.',
   '[{"ordem":1,"acao":"Abrir a aba Relatórios","resultado_esperado":"Os relatórios do hub carregam"}]'::jsonb,
   'A aba Relatórios abre.', NULL),

  (v_mod, 'HUBC-TELA-08', 'Config: SLA e modelos de checklist',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'A configuração define o SLA por tipo e os modelos de checklist — o que padroniza cada processo.',
   'Aba Config.',
   '[{"ordem":1,"acao":"Abrir a aba Config.","resultado_esperado":"Aparecem a configuração de SLA e os modelos de checklist"}]'::jsonb,
   'A Config traz SLA e modelos de checklist.', NULL),

  (v_mod, 'HUBC-TELA-09', 'Integração de férias aparece no topo',
   'feliz', 'baixa', 'aprovado', 'e2e', NULL,
   'A integração automática de férias liga o módulo de férias ao hub — aparece no topo para dar visibilidade.',
   'Rota /hub-contabil.',
   '[{"ordem":1,"acao":"Abrir /hub-contabil e olhar o topo","resultado_esperado":"O bloco de integração de férias aparece acima das abas"}]'::jsonb,
   'A integração de férias aparece no topo do hub.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Hub Contábil (tela): antes=%, depois=% (esperado +9)', v_antes, v_depois;
END $doc$;

-- ── Conferência (última query: é o que o SQL Editor exibe) ──
SELECT m.path AS modulo,
       count(*)                                AS casos_tela,
       min(c.codigo)                           AS primeiro,
       max(c.codigo)                           AS ultimo
FROM public.qa_casos_teste c
JOIN public.qa_modulos m ON m.id = c.modulo_id
WHERE c.codigo LIKE '%-TELA-%'
  AND m.path IN ('planejamento-gestao/metas','planejamento-gestao/plano-de-acao',
                 'documentos-governanca/documentos','documentos-governanca/hub-contabil')
GROUP BY m.path
ORDER BY m.path;
