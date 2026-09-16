-- =========================================================
-- QA — Mural Interno: primeira documentação do módulo (13 casos)
--
-- Módulo pessoas-cultura/mural-interno, zero casos até aqui.
-- Casos de TELA (nivel e2e) ancorados em src/pages/Feed.tsx +
-- components/feed/*: publicação (texto/imagem), reações, comentários,
-- exclusão do próprio post, widget de avisos/felicitações e lembretes de
-- aniversário e tempo de casa.
--
-- Regra da casa: caso e2e sem spec só gera aviso na guarda.
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'pessoas-cultura/mural-interno';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo pessoas-cultura/mural-interno não encontrado.'; END IF;
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
