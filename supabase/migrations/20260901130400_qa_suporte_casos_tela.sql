-- =========================================================
-- QA — Suporte: primeira documentação do módulo (12 casos)
--
-- Módulo sistema/suporte, zero casos até aqui.
-- Casos de TELA (nivel e2e) ancorados em src/pages/Suporte.tsx: central de
-- tickets multi-tenant — abrir chamados (bug/falha/reclamação/sugestão/
-- dúvida), acompanhar por status, comentar; admin muda status; superadmin
-- vê todos os tenants.
--
-- Regra da casa: caso e2e sem spec só gera aviso na guarda.
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'sistema/suporte';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo sistema/suporte não encontrado.'; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'SUP-001', 'Central de Suporte abre com stats e filtros',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'É o canal de chamados do sistema. Se não monta, o usuário fica sem reportar problemas e o time sem acompanhar.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar Suporte pelo menu","resultado_esperado":"Título Central de Suporte carrega"},
     {"ordem":2,"acao":"Conferir os cards e as abas de status","resultado_esperado":"Total/Abertos/Em Andamento/Resolvidos e as abas por status"}]'::jsonb,
   'A central monta com indicadores e abas.', NULL),

  (v_mod, 'SUP-010', 'Abrir um ticket',
   'feliz', 'critica', 'aprovado', 'e2e', NULL,
   'Abrir chamado é o ato central: registrar um problema com tipo e prioridade para o time tratar.',
   'Usuário autenticado.',
   '[{"ordem":1,"acao":"Clicar em Novo Ticket","resultado_esperado":"Modal Novo Ticket abre"},
     {"ordem":2,"acao":"Informar Título, Descrição, Tipo e Prioridade e enviar","resultado_esperado":"Aviso Ticket criado com sucesso!; o chamado aparece na lista"}]'::jsonb,
   'O ticket é aberto e listado.', NULL),

  (v_mod, 'SUP-011', 'Bloquear envio de ticket sem título ou descrição',
   'negativo', 'alta', 'aprovado', 'e2e', NULL,
   'Chamado sem título ou descrição não diz nada ao time. O Enviar deve ficar desabilitado sem os dois.',
   'Modal Novo Ticket aberto.',
   '[{"ordem":1,"acao":"Deixar Título ou Descrição em branco","resultado_esperado":"O botão Enviar Ticket fica desabilitado"}]'::jsonb,
   'Ticket incompleto não é enviado.', NULL),

  (v_mod, 'SUP-012', 'Escolher tipo, prioridade e módulo relacionado',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Classificar por tipo, prioridade e módulo ajuda o time a triar. As opções precisam estar disponíveis e persistir no ticket.',
   'Modal Novo Ticket aberto.',
   '[{"ordem":1,"acao":"Selecionar Tipo, Prioridade e Módulo relacionado","resultado_esperado":"Opções aceitas e refletidas no ticket criado"}]'::jsonb,
   'A classificação do ticket é registrada.', NULL),

  (v_mod, 'SUP-020', 'Filtrar e buscar tickets',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Numa fila de chamados, buscar por texto e filtrar por tipo/status é como se acha o que importa.',
   'Alguns tickets cadastrados.',
   '[{"ordem":1,"acao":"Buscar por texto e filtrar por tipo","resultado_esperado":"A lista restringe conforme a busca/filtro"},
     {"ordem":2,"acao":"Alternar as abas de status (Abertos, Em Andamento, Resolvidos...)","resultado_esperado":"A lista mostra os tickets do status escolhido"}]'::jsonb,
   'Busca, filtro e abas de status funcionam.', NULL),

  (v_mod, 'SUP-030', 'Abrir o detalhe de um ticket',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'O detalhe reúne descrição, metadados e comentários — o histórico do chamado.',
   'Um ticket na lista.',
   '[{"ordem":1,"acao":"Abrir um ticket","resultado_esperado":"Detalhe mostra reportado por, data, módulo, descrição e comentários"}]'::jsonb,
   'O detalhe do ticket monta.', NULL),

  (v_mod, 'SUP-031', 'Comentar em um ticket',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'O comentário é a conversa do chamado (pedir detalhe, dar retorno). Enviar deve exibi-lo no histórico.',
   'Detalhe de um ticket aberto.',
   '[{"ordem":1,"acao":"Escrever um comentário e enviar","resultado_esperado":"Aviso Comentário adicionado!; comentário aparece no histórico"}]'::jsonb,
   'O comentário é registrado no ticket.', NULL),

  (v_mod, 'SUP-040', 'Mudar o status do ticket é ação de admin',
   'negativo', 'alta', 'aprovado', 'e2e', NULL,
   'Quem trata o chamado muda o status (Em Análise, Em Andamento, Resolvido...). Usuário comum não deve ter esse controle.',
   'Contas admin e usuário comum; um ticket aberto.',
   '[{"ordem":1,"acao":"Abrir um ticket como admin","resultado_esperado":"Aparece Alterar status com as opções"},
     {"ordem":2,"acao":"Abrir como usuário comum","resultado_esperado":"A mudança de status não é oferecida"}]'::jsonb,
   'A mudança de status respeita o papel.',
   'Controle só com isAdmin e status não fechado/cancelado.'),

  (v_mod, 'SUP-041', 'Resolver um ticket registra a resolução',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Marcar como Resolvido fecha o ciclo e carimba quando foi resolvido — a métrica de atendimento.',
   'Admin num ticket aberto.',
   '[{"ordem":1,"acao":"Marcar o ticket como Resolvido","resultado_esperado":"Status vira Resolvido e a data de resolução é gravada"}]'::jsonb,
   'A resolução é registrada.', NULL),

  (v_mod, 'SUP-050', 'Lista vazia orienta a abrir um ticket',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'Sem chamados, a tela deve convidar a abrir o primeiro, não exibir erro.',
   'Ambiente sem tickets.',
   '[{"ordem":1,"acao":"Abrir a central sem tickets","resultado_esperado":"Nenhum ticket encontrado + convite a criar um Novo Ticket"}]'::jsonb,
   'O estado vazio é tratado.', NULL),

  (v_mod, 'SUP-060', 'Tickets isolados por tenant (superadmin vê todos)',
   'negativo', 'alta', 'aprovado', 'e2e', 'LGPD art. 37 / isolamento multi-tenant',
   'Chamado é dado da empresa. Usuário comum só vê os do próprio tenant; superadmin vê todos, com o tenant identificado.',
   'Tickets de mais de um tenant; contas comum e superadmin.',
   '[{"ordem":1,"acao":"Listar tickets como usuário comum","resultado_esperado":"Só os tickets do próprio tenant"},
     {"ordem":2,"acao":"Listar como superadmin","resultado_esperado":"Todos os tenants, com o identificador do tenant"}]'::jsonb,
   'O isolamento por tenant é respeitado.', NULL),

  (v_mod, 'SUP-070', 'Abrir ticket exige contexto de empresa (tenant)',
   'negativo', 'media', 'aprovado', 'e2e', NULL,
   'Sem tenant, o chamado não tem dono. A criação deve exigir o contexto de empresa.',
   'Usuário sem tenant resolvido.',
   '[{"ordem":1,"acao":"Tentar abrir um ticket sem tenant","resultado_esperado":"A criação é barrada (Sem tenant)"}]'::jsonb,
   'A criação exige o tenant.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Suporte: antes=%, depois=% (esperado +12)', v_antes, v_depois;
END $doc$;
