-- =========================================================
-- QA — Cultura & Celebrações: primeira documentação do módulo (13 casos)
--
-- Módulo pessoas-cultura/cultura-celebracoes, zero casos até aqui.
-- Casos de TELA (nivel e2e) ancorados em src/pages/CulturaCelebracoes.tsx +
-- components/cultura/*: planejamento e acompanhamento de ações culturais e
-- celebrações (aniversários, tempo de casa, rituais, datas, marcos,
-- preferências), com KPIs culturais e integração ao Mural Interno.
--
-- Regra da casa: caso e2e sem spec só gera aviso na guarda.
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'pessoas-cultura/cultura-celebracoes';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo pessoas-cultura/cultura-celebracoes não encontrado.'; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'CULT-001', 'Tela de Cultura & Celebrações abre com abas e KPIs',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'É onde a cultura vira plano: celebrações, rituais e reconhecimento. Se não monta, o RH perde o acompanhamento das ações culturais.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar Cultura & Celebrações pelo menu","resultado_esperado":"Tela carrega com os cards e as abas"},
     {"ordem":2,"acao":"Conferir as abas","resultado_esperado":"Experiência do Colaborador, Preferências, Rituais e Reconhecimento"}]'::jsonb,
   'A tela monta com abas e indicadores.',
   'Cards: Datas Ativas, Ações Pendentes, Ações Concluídas, Rituais Ativos.'),

  (v_mod, 'CULT-002', 'Próximas Celebrações lista aniversários e tempo de casa',
   'feliz', 'alta', 'aprovado', 'e2e', 'LGPD art. 6º (dado pessoal)',
   'O card Próximas Celebrações (30 dias) puxa aniversários e tempo de casa dos colaboradores. É o radar das datas a celebrar.',
   'Colaboradores ativos com datas nos próximos 30 dias.',
   '[{"ordem":1,"acao":"Conferir Próximas Celebrações (30 dias)","resultado_esperado":"Itens com selo (Aniversário / N anos de empresa) e Hoje!/Amanhã/em N dias"}]'::jsonb,
   'As celebrações dos próximos 30 dias aparecem.', NULL),

  (v_mod, 'CULT-010', 'Criar uma ação cultural',
   'feliz', 'critica', 'aprovado', 'e2e', NULL,
   'A ação cultural é o que se planeja para celebrar/engajar. Criar é o ato central do módulo.',
   'Aba Experiência do Colaborador.',
   '[{"ordem":1,"acao":"Clicar em Nova Ação","resultado_esperado":"Modal Nova Ação Cultural abre"},
     {"ordem":2,"acao":"Informar título e data de referência e salvar","resultado_esperado":"Ação criada aparece na agenda"}]'::jsonb,
   'A ação cultural é criada.',
   'Modal Nova Ação Cultural; título e data de referência obrigatórios.'),

  (v_mod, 'CULT-011', 'Não criar ação sem título ou data de referência',
   'negativo', 'media', 'aprovado', 'e2e', NULL,
   'Ação sem título ou data não agenda nada. O salvar não deve prosseguir sem esses campos.',
   'Modal Nova Ação Cultural aberto.',
   '[{"ordem":1,"acao":"Tentar salvar sem título ou sem data de referência","resultado_esperado":"A ação não é criada"}]'::jsonb,
   'Ação incompleta não é criada.',
   'Guarda silenciosa (sem toast): o salvar apenas não age.'),

  (v_mod, 'CULT-012', 'Criar ação a partir de uma celebração detectada',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'Do aniversário/tempo de casa detectado, um clique já monta a ação — e ela também aparece no Mural Interno.',
   'Uma celebração detectada em Próximas Celebrações.',
   '[{"ordem":1,"acao":"Clicar em Criar Ação num aniversário/tempo de casa","resultado_esperado":"Ação criada (pendente); aviso de que também aparece no Mural Interno"}]'::jsonb,
   'A ação nasce da celebração detectada e cruza para o mural.', NULL),

  (v_mod, 'CULT-013', 'Concluir uma ação cultural',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Concluir marca a celebração como feita e alimenta os indicadores de realização.',
   'Uma ação pendente na agenda.',
   '[{"ordem":1,"acao":"Clicar em Concluir na ação","resultado_esperado":"Status vira concluída; aviso Status atualizado"}]'::jsonb,
   'A ação é concluída e contabilizada.', NULL),

  (v_mod, 'CULT-020', 'Filtrar a agenda por tipo, status e período',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'A agenda pode ter muitas ações. Filtrar por tipo/status/período e buscar colaborador é como se navega.',
   'Ações cadastradas.',
   '[{"ordem":1,"acao":"Aplicar filtros de tipo, status e período","resultado_esperado":"A lista restringe conforme os filtros"}]'::jsonb,
   'Os filtros da agenda funcionam.', NULL),

  (v_mod, 'CULT-030', 'Registrar a preferência de celebração de um colaborador',
   'alternativo', 'media', 'aprovado', 'e2e', 'LGPD art. 6º (dado pessoal)',
   'Saber como cada um gosta de ser celebrado personaliza o reconhecimento. Registrar deve salvar a preferência do colaborador.',
   'Aba Preferências.',
   '[{"ordem":1,"acao":"Clicar em Registrar Preferência","resultado_esperado":"Modal de preferência abre"},
     {"ordem":2,"acao":"Escolher colaborador e preferências e salvar","resultado_esperado":"Preferência registrada aparece na lista"}]'::jsonb,
   'A preferência do colaborador é registrada.', NULL),

  (v_mod, 'CULT-040', 'Criar um ritual cultural',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Rituais são as práticas recorrentes da cultura. Criar um ritual com frequência é montar o calendário cultural.',
   'Aba Rituais e Reconhecimento → sub-aba Rituais Culturais.',
   '[{"ordem":1,"acao":"Clicar em Novo Ritual","resultado_esperado":"Modal Novo Ritual Cultural abre"},
     {"ordem":2,"acao":"Informar nome e frequência e salvar","resultado_esperado":"Ritual criado aparece na lista"}]'::jsonb,
   'O ritual cultural é criado.', NULL),

  (v_mod, 'CULT-041', 'Cadastrar uma data comemorativa e um marco de tempo',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Datas configuráveis e marcos de tempo (X anos de casa) automatizam o calendário. Cadastrar deve persistir os dois.',
   'Sub-abas Datas Configuráveis e Marcos de Tempo.',
   '[{"ordem":1,"acao":"Em Datas Configuráveis, criar uma Nova Data (título, dia, mês)","resultado_esperado":"Data cadastrada"},
     {"ordem":2,"acao":"Em Marcos de Tempo, criar um Novo Marco (anos, tipo)","resultado_esperado":"Marco cadastrado"}]'::jsonb,
   'Datas e marcos são cadastráveis.', NULL),

  (v_mod, 'CULT-050', 'Configurar o módulo (o que celebrar e o padrão)',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'A configuração define quais eventos entram (aniversário, tempo de casa, dia da profissão), limite de presente e responsável padrão.',
   'Sub-aba Configuração.',
   '[{"ordem":1,"acao":"Alternar os eventos e ajustar o responsável padrão","resultado_esperado":"Aviso Configuração salva!; escolhas persistem"}]'::jsonb,
   'A configuração do módulo persiste.', NULL),

  (v_mod, 'CULT-060', 'Indicadores culturais consolidam a realização',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Taxa de Realização, no prazo, atrasadas e tempo médio dizem se a cultura sai do papel. Devem montar sem erro nem divisão por zero.',
   'Tela aberta (com ou sem ações).',
   '[{"ordem":1,"acao":"Conferir Indicadores Culturais","resultado_esperado":"Taxa de Realização, Ações no Prazo, Atrasadas e Tempo Médio montam; sem ações, 0% e 0d sem quebrar"}]'::jsonb,
   'Os indicadores culturais são consistentes.', NULL),

  (v_mod, 'CULT-070', 'Ações e datas isoladas por empresa',
   'negativo', 'alta', 'aprovado', 'e2e', 'LGPD art. 6º',
   'As celebrações trazem nomes e datas reais de pessoas. A tela não pode misturar colaboradores de outra empresa.',
   'Base com mais de uma empresa.',
   '[{"ordem":1,"acao":"Abrir o módulo com uma empresa ativa","resultado_esperado":"Só aparecem celebrações/ações da empresa/tenant do usuário"}]'::jsonb,
   'O escopo por empresa é respeitado.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Cultura & Celebrações: antes=%, depois=% (esperado +13)', v_antes, v_depois;
END $doc$;
