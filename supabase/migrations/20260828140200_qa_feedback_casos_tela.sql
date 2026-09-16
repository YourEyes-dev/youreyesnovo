-- =========================================================
-- QA — Feedback & Ocorrências: primeira documentação do módulo (14 casos)
--
-- Módulo pessoas-cultura/feedback-desenvolvimento, zero casos até aqui.
-- Casos de TELA (nivel e2e) ancorados em src/pages/FeedbackOcorrencias.tsx +
-- components/feedback/*: 4 abas (Novo Feedback, Feedbacks, Nova Ocorrência,
-- Ocorrências), formulário de feedback (colaborador, categoria, descrição,
-- estruturação por IA, envio por e-mail), formulário de ocorrência com
-- vínculo de advertência, e estatísticas do gestor.
--
-- Regra da casa: caso e2e sem spec só gera aviso na guarda.
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'pessoas-cultura/feedback-desenvolvimento';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo pessoas-cultura/feedback-desenvolvimento não encontrado.'; END IF;
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
