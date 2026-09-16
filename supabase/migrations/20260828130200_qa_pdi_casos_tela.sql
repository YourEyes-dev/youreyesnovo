-- =========================================================
-- QA — PDI: primeira documentação de casos do módulo (18 casos)
--
-- O módulo PDI (desenvolvimento-performance/pdi) estava no catálogo de
-- QA com ZERO casos. Este arquivo abre a família PDI com casos de TELA
-- (nivel e2e), derivados da tela real (src/pages/Pdi.tsx +
-- components/pdi/*):
--   · lista com abas Todos / Ativos / Concluídos e cards de estatística;
--   · criação com Colaborador*, Título* (com sugestão por IA),
--     Descrição, Período (ex.: trimestral), Gatilho opcional,
--     Data início*, Data fim*, Responsável (líder);
--   · dentro do PDI: metas (com progresso), check-ins, feedbacks,
--     edição, documento imprimível;
--   · FAQ em accordion na própria tela.
--
-- Regra da casa: caso e2e documentado sem spec só gera aviso na guarda.
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'desenvolvimento-performance/pdi';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo desenvolvimento-performance/pdi não encontrado.'; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  -- ══════════ A) TELA E LISTA ══════════

  (v_mod, 'PDI-001', 'Tela de PDI abre com lista e abas Todos, Ativos e Concluídos',
   'feliz', 'alta', 'aprovado', 'e2e',
   NULL,
   'A tela organiza os planos por estado. As três abas devem montar e a lista carregar sem erro.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar o PDI pelo menu","resultado_esperado":"Tela carrega com a lista"},
     {"ordem":2,"acao":"Alternar entre Todos, Ativos e Concluídos","resultado_esperado":"Cada aba filtra a lista pelo estado correspondente"}]'::jsonb,
   'As abas segmentam os PDIs por estado corretamente.',
   NULL),

  (v_mod, 'PDI-002', 'Estado vazio orientativo no primeiro acesso',
   'alternativo', 'media', 'aprovado', 'e2e',
   NULL,
   'Sem nenhum PDI cadastrado, a lista deve orientar o próximo passo — não exibir tela quebrada ou spinner sem fim.',
   'Empresa/colaboradores sem PDIs cadastrados.',
   '[{"ordem":1,"acao":"Abrir o PDI sem planos cadastrados","resultado_esperado":"Estado vazio com orientação; sem erro"}]'::jsonb,
   'O vazio inicial é tratado.',
   NULL),

  (v_mod, 'PDI-003', 'FAQ da tela abre e fecha em accordion',
   'alternativo', 'baixa', 'aprovado', 'e2e',
   NULL,
   'A tela traz FAQ embutido para reduzir dúvida de uso. O accordion deve expandir e recolher sem afetar o resto.',
   'Tela de PDI aberta.',
   '[{"ordem":1,"acao":"Expandir o FAQ","resultado_esperado":"Conteúdo aparece"},
     {"ordem":2,"acao":"Recolher","resultado_esperado":"Conteúdo esconde; tela segue operável"}]'::jsonb,
   'O FAQ funciona como accordion.',
   NULL),

  -- ══════════ B) CRIAÇÃO DO PDI ══════════

  (v_mod, 'PDI-010', 'Criar PDI com colaborador, título e período de vigência',
   'feliz', 'critica', 'aprovado', 'e2e',
   NULL,
   'O caminho feliz do módulo: um plano nasce para um colaborador, com título e janela de vigência (início e fim). Sem isso não existe desenvolvimento acompanhável.',
   'Pelo menos um colaborador ativo no ambiente de teste.',
   '[{"ordem":1,"acao":"Abrir a criação de PDI","resultado_esperado":"Formulário abre"},
     {"ordem":2,"acao":"Selecionar Colaborador, preencher Título, Data início e Data fim","resultado_esperado":"Campos aceitos"},
     {"ordem":3,"acao":"Salvar","resultado_esperado":"PDI criado aparece na lista como ativo"}]'::jsonb,
   'O PDI é criado com os campos mínimos e entra na lista.',
   'Campos obrigatórios reais do PdiFormModal: colaborador_id, titulo, data_inicio, data_fim.'),

  (v_mod, 'PDI-011', 'Bloquear criação de PDI sem colaborador',
   'negativo', 'alta', 'aprovado', 'e2e',
   NULL,
   'PDI é individual por definição. O formulário não salva sem colaborador selecionado.',
   'Formulário de criação aberto.',
   '[{"ordem":1,"acao":"Preencher título e datas sem selecionar colaborador","resultado_esperado":"—"},
     {"ordem":2,"acao":"Tentar salvar","resultado_esperado":"Sistema impede o salvamento"}]'::jsonb,
   'Não há PDI sem dono.',
   NULL),

  (v_mod, 'PDI-012', 'Bloquear criação de PDI sem título ou sem datas',
   'negativo', 'alta', 'aprovado', 'e2e',
   NULL,
   'Título e vigência são o esqueleto do plano — obrigatórios no formulário.',
   'Formulário de criação aberto.',
   '[{"ordem":1,"acao":"Tentar salvar sem título","resultado_esperado":"Salvamento impedido"},
     {"ordem":2,"acao":"Tentar salvar sem data de início ou de fim","resultado_esperado":"Salvamento impedido"}]'::jsonb,
   'Os obrigatórios do formulário são exigidos.',
   NULL),

  (v_mod, 'PDI-013', 'Sugestão por IA preenche título e descrição',
   'alternativo', 'media', 'aprovado', 'e2e',
   NULL,
   'O botão de sugestão consulta a IA com o contexto do colaborador e preenche o campo. Com chave configurada, a sugestão chega; sem colaborador selecionado, a tela avisa.',
   'Formulário de criação aberto; chave de IA configurada no ambiente.',
   '[{"ordem":1,"acao":"Pedir sugestão de título SEM selecionar colaborador","resultado_esperado":"Aviso pedindo para selecionar o colaborador antes"},
     {"ordem":2,"acao":"Selecionar colaborador e pedir sugestão","resultado_esperado":"Campo preenchido com o texto sugerido (ou aviso claro de chave ausente)"}]'::jsonb,
   'A sugestão responde ou avisa — nunca falha muda.',
   'Toast real: "Selecione um colaborador antes de pedir sugestão".'),

  (v_mod, 'PDI-014', 'Período e gatilho opcionais qualificam o plano',
   'alternativo', 'media', 'aprovado', 'e2e',
   NULL,
   'Período (trimestral, semestral...) e gatilho (origem do PDI) são metadados de gestão. Quando informados, precisam persistir.',
   'Formulário de criação aberto.',
   '[{"ordem":1,"acao":"Criar PDI informando período e gatilho","resultado_esperado":"PDI salvo"},
     {"ordem":2,"acao":"Reabrir o PDI","resultado_esperado":"Período e gatilho gravados"}]'::jsonb,
   'Metadados opcionais persistem.',
   NULL),

  (v_mod, 'PDI-015', 'Duplo clique no salvar não duplica o PDI',
   'negativo', 'media', 'aprovado', 'e2e',
   NULL,
   'Dois PDIs idênticos para o mesmo colaborador no mesmo período confundem gestor e colaborador. O salvar deve ser idempotente ao duplo clique.',
   'Formulário preenchido.',
   '[{"ordem":1,"acao":"Clicar duas vezes rapidamente em salvar","resultado_esperado":"Apenas um PDI criado"}]'::jsonb,
   'Um gesto, um registro.',
   NULL),

  -- ══════════ C) DENTRO DO PDI: METAS, CHECK-INS, FEEDBACK ══════════

  (v_mod, 'PDI-020', 'Adicionar meta ao PDI',
   'feliz', 'critica', 'aprovado', 'e2e',
   NULL,
   'O PDI se materializa em metas. Adicionar meta é o gesto central do acompanhamento.',
   'Um PDI criado.',
   '[{"ordem":1,"acao":"Abrir o PDI e adicionar uma meta","resultado_esperado":"Formulário de meta abre e aceita os dados"},
     {"ordem":2,"acao":"Salvar","resultado_esperado":"Meta listada dentro do PDI"}]'::jsonb,
   'A meta nasce vinculada ao plano.',
   'Componente PdiMetaForm / PdiMetaCard.'),

  (v_mod, 'PDI-021', 'Atualizar o progresso de uma meta',
   'feliz', 'alta', 'aprovado', 'e2e',
   NULL,
   'O progresso da meta é o termômetro do plano. Atualizações devem persistir e refletir no card.',
   'Um PDI com meta cadastrada.',
   '[{"ordem":1,"acao":"Atualizar o progresso da meta","resultado_esperado":"Valor salvo"},
     {"ordem":2,"acao":"Reabrir o PDI","resultado_esperado":"Progresso persistido no card da meta"}]'::jsonb,
   'O termômetro do plano é confiável.',
   NULL),

  (v_mod, 'PDI-022', 'Registrar check-in de acompanhamento',
   'feliz', 'alta', 'aprovado', 'e2e',
   NULL,
   'O check-in é o ritual de acompanhamento entre líder e colaborador. O registro deve entrar no histórico do PDI.',
   'Um PDI ativo.',
   '[{"ordem":1,"acao":"Abrir o PDI e registrar um check-in","resultado_esperado":"Formulário aceita o registro"},
     {"ordem":2,"acao":"Salvar","resultado_esperado":"Check-in aparece no histórico do plano"}]'::jsonb,
   'O acompanhamento fica documentado.',
   'Componente PdiCheckinForm.'),

  (v_mod, 'PDI-023', 'Registrar feedback no PDI',
   'feliz', 'media', 'aprovado', 'e2e',
   NULL,
   'Feedback registrado no plano transforma conversa em desenvolvimento rastreável.',
   'Um PDI ativo.',
   '[{"ordem":1,"acao":"Registrar um feedback no PDI","resultado_esperado":"Feedback salvo e listado no plano"}]'::jsonb,
   'O feedback compõe o histórico do plano.',
   'Componente PdiFeedbackForm.'),

  (v_mod, 'PDI-024', 'Editar um PDI existente',
   'feliz', 'media', 'aprovado', 'e2e',
   NULL,
   'Planos mudam (prazo, descrição, responsável). A edição deve persistir sem efeitos colaterais nas metas já cadastradas.',
   'Um PDI com meta cadastrada.',
   '[{"ordem":1,"acao":"Editar título/descrição do PDI","resultado_esperado":"Alterações salvas"},
     {"ordem":2,"acao":"Conferir as metas","resultado_esperado":"Metas intactas após a edição"}]'::jsonb,
   'Editar o plano não corrompe o conteúdo.',
   'Componente PdiEditModal.'),

  (v_mod, 'PDI-025', 'Concluir PDI move o plano para a aba Concluídos',
   'feliz', 'alta', 'aprovado', 'e2e',
   NULL,
   'O encerramento do plano é o fim do ciclo: o PDI concluído sai de Ativos e passa a constar em Concluídos.',
   'Um PDI ativo com metas encerradas.',
   '[{"ordem":1,"acao":"Concluir o PDI","resultado_esperado":"Estado muda para concluído"},
     {"ordem":2,"acao":"Conferir as abas","resultado_esperado":"O plano sai de Ativos e aparece em Concluídos"}]'::jsonb,
   'O ciclo de vida do plano fecha corretamente.',
   NULL),

  -- ══════════ D) DOCUMENTO E VISÃO GERENCIAL ══════════

  (v_mod, 'PDI-030', 'Gerar o documento do PDI',
   'alternativo', 'media', 'aprovado', 'e2e',
   NULL,
   'O documento consolidado (para assinatura/arquivo) apresenta o plano completo. A geração deve abrir com os dados reais do PDI.',
   'Um PDI com metas e check-ins.',
   '[{"ordem":1,"acao":"Abrir o documento do PDI","resultado_esperado":"Documento monta com dados do plano (colaborador, metas, período)"}]'::jsonb,
   'O documento espelha o plano.',
   'Componente PdiDocumentoModal.'),

  (v_mod, 'PDI-031', 'Estatísticas do topo refletem os planos',
   'feliz', 'media', 'aprovado', 'e2e',
   NULL,
   'Os cards de estatística resumem a carteira de PDIs (ativos, concluídos...). Devem bater com a lista.',
   'PDIs em estados variados.',
   '[{"ordem":1,"acao":"Conferir os cards contra as abas","resultado_esperado":"Contagens coerentes com os planos cadastrados"}]'::jsonb,
   'A visão gerencial é confiável.',
   'Componente PdiStats.'),

  (v_mod, 'PDI-032', 'Colaborador comum não gerencia PDI de terceiros',
   'negativo', 'critica', 'aprovado', 'e2e',
   'LGPD (dados de desenvolvimento são pessoais)',
   'PDI carrega avaliação e desenvolvimento — dado pessoal do colaborador. Perfil comum não deve ver nem editar planos de outros; a visão segue o papel.',
   'Duas contas: gestor e colaborador comum; PDIs de colaboradores distintos.',
   '[{"ordem":1,"acao":"Abrir o módulo com perfil de colaborador comum","resultado_esperado":"Apenas o próprio PDI (ou visão permitida ao papel) aparece"},
     {"ordem":2,"acao":"Tentar acessar PDI de outro colaborador","resultado_esperado":"Acesso negado ou item invisível"}]'::jsonb,
   'O escopo de visão respeita o papel do usuário.',
   'A camada RESTRICTIVE por perfil cobre a leitura no banco; este caso valida o comportamento NA TELA.')

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'PDI: casos antes=%, depois=% (esperado +18 na primeira execução)', v_antes, v_depois;
END $doc$;
