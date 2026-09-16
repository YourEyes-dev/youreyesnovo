-- =========================================================
-- QA — Ouvidoria: primeira documentação de casos do módulo (19 casos)
--
-- O módulo Ouvidoria (pessoas-cultura/ouvidoria) estava no catálogo de
-- QA com ZERO casos. Este arquivo abre a família OUV com casos de TELA
-- (nivel e2e), derivados da tela real (src/pages/Ouvidoria.tsx +
-- components/ouvidoria/*):
--   · abas Enviar / Manifestações / Configurações (a última só para
--     perfil gestor);
--   · formulário com Tipo* (sugestão, reclamação, denúncia, elogio,
--     dúvida), Assunto*, Mensagem*, anexos e envio ANÔNIMO por switch;
--   · gestão: filtros (busca/tipo/status), status pendente → em_analise
--     → respondido → arquivado, prioridade, resposta ao manifestante,
--     análise por IA (categoria/subcategorias), ações vinculadas e
--     roteamento configurável por tipo.
--
-- Sensibilidade especial: DENÚNCIA ANÔNIMA. O anonimato prometido na
-- tela de envio é compromisso de LGPD e de confiança — os casos OUV-010
-- e OUV-011 tratam disso como prioridade crítica.
--
-- Regra da casa: caso e2e documentado sem spec só gera aviso na guarda.
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'pessoas-cultura/ouvidoria';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo pessoas-cultura/ouvidoria não encontrado.'; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  -- ══════════ A) ENVIO DE MANIFESTAÇÃO ══════════

  (v_mod, 'OUV-001', 'Tela da Ouvidoria abre na aba Enviar com o formulário pronto',
   'feliz', 'alta', 'aprovado', 'e2e',
   NULL,
   'A porta de entrada da Ouvidoria é o envio. A tela deve abrir com o formulário utilizável — tipo, assunto, mensagem e a opção de anonimato visíveis.',
   'Usuário autenticado (qualquer perfil com acesso ao módulo).',
   '[{"ordem":1,"acao":"Acessar a Ouvidoria pelo menu","resultado_esperado":"Tela abre na aba Enviar"},
     {"ordem":2,"acao":"Conferir o formulário","resultado_esperado":"Tipo de Manifestação, Assunto, Mensagem e switch de anonimato visíveis"}]'::jsonb,
   'O formulário de envio está pronto ao abrir o módulo.',
   NULL),

  (v_mod, 'OUV-002', 'Enviar manifestação identificada com tipo, assunto e mensagem',
   'feliz', 'critica', 'aprovado', 'e2e',
   NULL,
   'O caminho feliz do módulo: colaborador envia manifestação identificada e ela chega à gestão. É o fluxo que justifica a existência da Ouvidoria.',
   'Usuário autenticado; aba Enviar aberta.',
   '[{"ordem":1,"acao":"Selecionar um Tipo de Manifestação","resultado_esperado":"Tipo selecionado"},
     {"ordem":2,"acao":"Preencher Assunto e Mensagem","resultado_esperado":"Campos aceitos"},
     {"ordem":3,"acao":"Enviar","resultado_esperado":"Confirmação de envio exibida"},
     {"ordem":4,"acao":"Abrir a aba Manifestações (com perfil gestor)","resultado_esperado":"A manifestação aparece com status inicial pendente"}]'::jsonb,
   'A manifestação identificada é registrada e visível na gestão.',
   NULL),

  (v_mod, 'OUV-003', 'Os cinco tipos de manifestação estão disponíveis',
   'feliz', 'media', 'aprovado', 'e2e',
   NULL,
   'A tipologia (sugestão, reclamação, denúncia, elogio, dúvida) direciona o tratamento e o roteamento. Tipo faltando no seletor é canal fechado sem aviso.',
   'Aba Enviar aberta.',
   '[{"ordem":1,"acao":"Abrir o seletor Tipo de Manifestação","resultado_esperado":"Sugestão, Reclamação, Denúncia, Elogio e Dúvida listados"}]'::jsonb,
   'Os cinco tipos aparecem para escolha.',
   'Vocabulário real de src/types/ouvidoria.ts (TipoManifestacao).'),

  (v_mod, 'OUV-004', 'Bloquear envio sem assunto',
   'negativo', 'alta', 'aprovado', 'e2e',
   NULL,
   'Assunto é obrigatório (marcado com asterisco na tela). Sem ele, a fila de gestão vira lista de itens sem identificação.',
   'Aba Enviar aberta.',
   '[{"ordem":1,"acao":"Preencher tipo e mensagem, deixando o Assunto vazio","resultado_esperado":"—"},
     {"ordem":2,"acao":"Tentar enviar","resultado_esperado":"Sistema impede o envio e sinaliza o campo"}]'::jsonb,
   'Não há envio sem assunto.',
   NULL),

  (v_mod, 'OUV-005', 'Bloquear envio sem mensagem',
   'negativo', 'alta', 'aprovado', 'e2e',
   NULL,
   'A mensagem é o conteúdo da manifestação — obrigatória por definição.',
   'Aba Enviar aberta.',
   '[{"ordem":1,"acao":"Preencher tipo e assunto, deixando a Mensagem vazia","resultado_esperado":"—"},
     {"ordem":2,"acao":"Tentar enviar","resultado_esperado":"Sistema impede o envio e sinaliza o campo"}]'::jsonb,
   'Não há envio sem mensagem.',
   NULL),

  (v_mod, 'OUV-006', 'Anexar arquivo à manifestação',
   'alternativo', 'media', 'aprovado', 'e2e',
   NULL,
   'Evidência anexada (print, documento) fortalece a apuração. O upload deve concluir e o anexo ficar disponível na gestão.',
   'Aba Enviar aberta; arquivo válido disponível.',
   '[{"ordem":1,"acao":"Preencher a manifestação e anexar um arquivo válido","resultado_esperado":"Anexo listado no formulário"},
     {"ordem":2,"acao":"Enviar e abrir a manifestação na gestão","resultado_esperado":"O anexo está acessível"}]'::jsonb,
   'O anexo acompanha a manifestação de ponta a ponta.',
   'Componentes AnexoUpload / AnexosList.'),

  -- ══════════ B) ANONIMATO (LGPD) ══════════

  (v_mod, 'OUV-010', 'Envio anônimo não expõe a identidade na gestão',
   'feliz', 'critica', 'aprovado', 'e2e',
   'LGPD (minimização); boas práticas de canal de denúncia (Lei 14.457/2022 para o contexto de escuta)',
   'É a promessa mais sensível do módulo: quem escolhe o anonimato NÃO pode aparecer identificado para quem gerencia. Uma denúncia anônima que exibe o autor destrói a confiança no canal inteiro — e é incidente de privacidade.',
   'Usuário autenticado; aba Enviar aberta.',
   '[{"ordem":1,"acao":"Ativar o switch de envio anônimo","resultado_esperado":"Aviso sobre anonimato exibido"},
     {"ordem":2,"acao":"Enviar uma manifestação de teste","resultado_esperado":"Envio confirmado"},
     {"ordem":3,"acao":"Abrir a manifestação na aba Manifestações (perfil gestor)","resultado_esperado":"O card exibe indicação de anônimo — nunca nome, e-mail ou matrícula do autor"}]'::jsonb,
   'A identidade do manifestante anônimo não aparece em nenhum ponto da gestão.',
   'Prioridade máxima da família. O card já diferencia manifestacao.anonimo — o teste garante que continua assim.'),

  (v_mod, 'OUV-011', 'Aviso claro ao ativar o modo anônimo',
   'alternativo', 'alta', 'aprovado', 'e2e',
   'LGPD (transparência)',
   'Ao ligar o anonimato, a tela explica o que muda (sem identificação, sem retorno individual). O manifestante decide informado.',
   'Aba Enviar aberta.',
   '[{"ordem":1,"acao":"Alternar o switch de anonimato","resultado_esperado":"Texto explicativo muda para o modo anônimo"},
     {"ordem":2,"acao":"Desligar o switch","resultado_esperado":"Texto volta ao modo identificado"}]'::jsonb,
   'A explicação acompanha o estado do switch.',
   NULL),

  -- ══════════ C) GESTÃO DAS MANIFESTAÇÕES ══════════

  (v_mod, 'OUV-020', 'Lista de manifestações com filtros de busca, tipo e status',
   'feliz', 'alta', 'aprovado', 'e2e',
   NULL,
   'A gestão vive da fila filtrável. Busca textual + filtro de tipo + filtro de status precisam segmentar a lista corretamente.',
   'Perfil gestor; manifestações variadas cadastradas (criar durante o teste).',
   '[{"ordem":1,"acao":"Abrir a aba Manifestações","resultado_esperado":"Lista carrega"},
     {"ordem":2,"acao":"Buscar por um termo do assunto","resultado_esperado":"Apenas manifestações compatíveis aparecem"},
     {"ordem":3,"acao":"Filtrar por tipo e por status","resultado_esperado":"Cada filtro segmenta a lista corretamente"}]'::jsonb,
   'Os três filtros funcionam combinados.',
   NULL),

  (v_mod, 'OUV-021', 'Busca sem correspondência mostra lista vazia sem erro',
   'negativo', 'media', 'aprovado', 'e2e',
   NULL,
   'Filtro que não encontra nada deve terminar em estado vazio amigável — não em erro nem em spinner eterno.',
   'Aba Manifestações aberta.',
   '[{"ordem":1,"acao":"Buscar por um termo inexistente","resultado_esperado":"Lista vazia com mensagem adequada; sem erro"}]'::jsonb,
   'O vazio é um estado, não um defeito.',
   NULL),

  (v_mod, 'OUV-022', 'Card da manifestação exibe tipo, status e data',
   'feliz', 'media', 'aprovado', 'e2e',
   NULL,
   'O card é a unidade de leitura da fila: tipo (com cor própria), status e data precisam estar visíveis sem abrir o detalhe.',
   'Pelo menos uma manifestação cadastrada.',
   '[{"ordem":1,"acao":"Observar um card na lista","resultado_esperado":"Badge de tipo, badge de status e data visíveis"}]'::jsonb,
   'A leitura rápida da fila funciona.',
   NULL),

  (v_mod, 'OUV-023', 'Alterar o status da manifestação pelo fluxo de tratamento',
   'feliz', 'critica', 'aprovado', 'e2e',
   NULL,
   'O tratamento caminha por status: pendente → em análise → respondido → arquivado. O gestor muda o status e a mudança persiste e reflete na lista.',
   'Perfil gestor; uma manifestação pendente.',
   '[{"ordem":1,"acao":"Abrir a manifestação e mudar o status para Em análise","resultado_esperado":"Status atualizado no card"},
     {"ordem":2,"acao":"Mudar para Respondido e depois Arquivado","resultado_esperado":"Cada mudança persiste e aparece na lista"}]'::jsonb,
   'O ciclo de status funciona de ponta a ponta.',
   'Vocabulário real: pendente, em_analise, respondido, arquivado (StatusManifestacao).'),

  (v_mod, 'OUV-024', 'Definir prioridade da manifestação',
   'alternativo', 'media', 'aprovado', 'e2e',
   NULL,
   'Denúncia grave não espera atrás de sugestão de café. A prioridade ordena o tratamento e deve ser ajustável pelo gestor.',
   'Perfil gestor; uma manifestação aberta.',
   '[{"ordem":1,"acao":"Alterar a prioridade da manifestação","resultado_esperado":"Prioridade salva e exibida no card"}]'::jsonb,
   'A prioridade é ajustável e persiste.',
   NULL),

  (v_mod, 'OUV-025', 'Responder a manifestação',
   'feliz', 'critica', 'aprovado', 'e2e',
   NULL,
   'A resposta fecha o ciclo de escuta: o gestor escreve o retorno e ele fica registrado na manifestação.',
   'Perfil gestor; uma manifestação em tratamento.',
   '[{"ordem":1,"acao":"Abrir a manifestação e escrever a resposta","resultado_esperado":"Campo de resposta aceita o texto"},
     {"ordem":2,"acao":"Enviar a resposta","resultado_esperado":"Resposta registrada na manifestação"}]'::jsonb,
   'A resposta fica gravada e visível no histórico da manifestação.',
   NULL),

  (v_mod, 'OUV-026', 'Análise por IA sugere categoria da manifestação',
   'alternativo', 'media', 'aprovado', 'e2e',
   NULL,
   'A IA classifica a manifestação (categoria e subcategorias) para acelerar a triagem. Com a chave configurada, a análise retorna; sem ela, o aviso é claro.',
   'Perfil gestor; manifestação com texto substancial.',
   '[{"ordem":1,"acao":"Acionar a análise por IA na manifestação","resultado_esperado":"Categoria e subcategorias sugeridas aparecem (ou aviso claro de chave ausente)"}]'::jsonb,
   'A análise responde ou avisa — nunca falha em silêncio.',
   'Componente OuvidoriaIAAnalise.'),

  (v_mod, 'OUV-027', 'Criar ação vinculada à manifestação',
   'alternativo', 'alta', 'aprovado', 'e2e',
   NULL,
   'Manifestação procedente vira ação de correção. O vínculo manifestação → ação preserva a rastreabilidade da escuta à providência.',
   'Perfil gestor; uma manifestação aberta.',
   '[{"ordem":1,"acao":"Abrir o fluxo de ações da manifestação","resultado_esperado":"Modal de ações abre"},
     {"ordem":2,"acao":"Criar uma ação vinculada","resultado_esperado":"Ação criada com vínculo à manifestação"}]'::jsonb,
   'A providência nasce ligada à escuta que a motivou.',
   'Componente OuvidoriaAcoesModal.'),

  -- ══════════ D) PERMISSÕES E CONFIGURAÇÃO ══════════

  (v_mod, 'OUV-030', 'Aba Configurações restrita ao perfil gestor',
   'negativo', 'critica', 'aprovado', 'e2e',
   'LGPD (controle de acesso a dado sensível)',
   'Configurações de roteamento definem QUEM recebe denúncias — não é tela de colaborador. Perfil comum não deve ver a aba.',
   'Duas contas: uma gestora e uma de colaborador comum.',
   '[{"ordem":1,"acao":"Abrir a Ouvidoria com perfil gestor","resultado_esperado":"Aba Configurações visível"},
     {"ordem":2,"acao":"Abrir com perfil colaborador comum","resultado_esperado":"Aba Configurações ausente ou inacessível"}]'::jsonb,
   'A superfície administrativa segue o perfil.',
   NULL),

  (v_mod, 'OUV-031', 'Configurar roteamento por tipo de manifestação',
   'alternativo', 'media', 'aprovado', 'e2e',
   NULL,
   'O roteamento define destinatários por tipo (denúncia → compliance, sugestão → RH...). A configuração deve salvar e ser reaberta com os valores.',
   'Perfil gestor; aba Configurações acessível.',
   '[{"ordem":1,"acao":"Ajustar o roteamento de um tipo","resultado_esperado":"Configuração salva com confirmação"},
     {"ordem":2,"acao":"Recarregar e reabrir","resultado_esperado":"Valores persistidos"}]'::jsonb,
   'O roteamento persiste entre sessões.',
   'Componente OuvidoriaRoteamentoConfig.'),

  (v_mod, 'OUV-032', 'Estatísticas da Ouvidoria refletem as manifestações',
   'feliz', 'media', 'aprovado', 'e2e',
   NULL,
   'Os cards de estatísticas resumem a saúde do canal (volumes por tipo/status). Números divergentes da lista minam a leitura gerencial.',
   'Manifestações cadastradas em tipos e status variados.',
   '[{"ordem":1,"acao":"Conferir os cards de estatísticas contra a lista filtrada","resultado_esperado":"Contagens coerentes com os registros"}]'::jsonb,
   'As estatísticas batem com a fila.',
   'Componente OuvidoriaStats.')

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Ouvidoria: casos antes=%, depois=% (esperado +19 na primeira execução)', v_antes, v_depois;
END $doc$;
