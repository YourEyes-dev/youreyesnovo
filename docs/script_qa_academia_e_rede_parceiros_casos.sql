-- ============================================================================
-- ENTREGA — QA Academia e Rede de Parceiros: primeira documentacao de casos
--
-- SO DOCUMENTA. Insere 30 casos de teste na Documentacao de Testes
-- (qa_casos_teste): 15 da Academia (familia ACAD) e 15 da Rede de Parceiros /
-- Marketplace (familia PARC). Os dois modulos estavam com ZERO casos. Nao cria
-- tabela, nao altera dado de negocio, nao apaga nada.
--
-- ONDE COLAR
-- No SQL Editor da PRODUCAO (diayjpsrcerycycyaxst), quando aprovado. E a mesma
-- documentacao que ja foi para o ambiente de teste pela esteira.
--
-- Idempotente: ON CONFLICT (codigo) DO NOTHING. Rodar duas vezes nao duplica.
-- Cada bloco pula sozinho se o modulo nao existir no ambiente.
-- Termina com UMA conferencia: total de casos por modulo e quantos desta entrega.
-- ============================================================================

SET lock_timeout = '10s';

-- ── ACADEMIA ────────────────────────────────────────────────────────────────
DO $acad$
DECLARE v_mod uuid;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'academia';
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo academia nao encontrado — casos ACAD nao inseridos.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  -- ── A) ADMIN — CRUD do conteudo ──
  (v_mod, 'ACAD-001', 'Criar categoria de treinamento',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'A categoria organiza o catalogo. Sem ela, os treinamentos ficam soltos e a busca por area nao funciona.',
   'Super Admin; area de administracao da Academia aberta.',
   '[{"ordem":1,"acao":"Abrir a administracao e criar uma nova categoria (nome)","resultado_esperado":"Categoria salva"},
     {"ordem":2,"acao":"Conferir a lista de categorias","resultado_esperado":"A nova categoria aparece"}]'::jsonb,
   'A categoria e criada e passa a estar disponivel para os treinamentos.',
   NULL),

  (v_mod, 'ACAD-002', 'Criar treinamento com categoria e nivel',
   'feliz', 'critica', 'aprovado', 'e2e', NULL,
   'Caminho feliz central da Academia: publicar um treinamento. E o que justifica o modulo existir.',
   'Super Admin; ao menos uma categoria criada.',
   '[{"ordem":1,"acao":"Criar um novo treinamento com titulo, categoria e nivel","resultado_esperado":"Campos aceitos"},
     {"ordem":2,"acao":"Salvar","resultado_esperado":"Treinamento criado e visivel no catalogo"}]'::jsonb,
   'O treinamento e registrado com categoria e nivel e aparece para os alunos.',
   'Niveis: iniciante, intermediario, avancado.'),

  (v_mod, 'ACAD-003', 'Adicionar modulo a um treinamento',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O treinamento se organiza em modulos. Cada modulo agrupa aulas na ordem certa.',
   'Super Admin; um treinamento existente.',
   '[{"ordem":1,"acao":"Abrir o treinamento na administracao e clicar em Novo Modulo","resultado_esperado":"Formulario do modulo abre"},
     {"ordem":2,"acao":"Preencher o nome e salvar","resultado_esperado":"O modulo aparece dentro do treinamento"}]'::jsonb,
   'O modulo passa a compor a estrutura do treinamento.',
   NULL),

  (v_mod, 'ACAD-004', 'Adicionar aula a um modulo',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'A aula e a unidade de estudo (video/conteudo). E o que o aluno de fato assiste.',
   'Super Admin; um modulo existente.',
   '[{"ordem":1,"acao":"Dentro do modulo, adicionar uma nova aula com titulo e conteudo","resultado_esperado":"Campos aceitos"},
     {"ordem":2,"acao":"Salvar","resultado_esperado":"A aula aparece listada no modulo"}]'::jsonb,
   'A aula fica disponivel para ser assistida pelo aluno.',
   NULL),

  (v_mod, 'ACAD-005', 'Editar um treinamento',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Conteudo evolui: titulo, descricao ou nivel mudam. A edicao deve persistir e refletir no catalogo.',
   'Super Admin; um treinamento existente.',
   '[{"ordem":1,"acao":"Abrir o treinamento em edicao e alterar titulo/descricao/nivel","resultado_esperado":"Alteracoes aceitas"},
     {"ordem":2,"acao":"Salvar e reabrir","resultado_esperado":"As alteracoes persistem"}]'::jsonb,
   'A edicao do treinamento e salva e visivel.',
   NULL),

  (v_mod, 'ACAD-006', 'Excluir item do catalogo com confirmacao',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'Fecha o CRUD: remover categoria, treinamento, modulo ou aula que nao valem mais, com confirmacao antes de apagar.',
   'Super Admin; item existente no catalogo.',
   '[{"ordem":1,"acao":"Acionar Excluir em um item (aula, modulo, treinamento ou categoria)","resultado_esperado":"Pede confirmacao"},
     {"ordem":2,"acao":"Confirmar","resultado_esperado":"O item some do catalogo"}]'::jsonb,
   'A exclusao so ocorre apos confirmacao e remove o item.',
   NULL),

  (v_mod, 'ACAD-007', 'Bloquear salvar treinamento sem titulo',
   'negativo', 'media', 'aprovado', 'e2e', NULL,
   'Titulo e obrigatorio. Sem ele, o catalogo vira lista de itens sem nome.',
   'Super Admin; formulario de treinamento aberto.',
   '[{"ordem":1,"acao":"Deixar o titulo vazio e tentar salvar","resultado_esperado":"O sistema impede e sinaliza o campo"}]'::jsonb,
   'Nao ha treinamento sem titulo.',
   NULL),

  -- ── B) ALUNO — consumo ──
  (v_mod, 'ACAD-020', 'Explorar e filtrar treinamentos por categoria e nivel',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O aluno acha o que precisa: busca por texto e filtros de categoria e nivel devem segmentar o catalogo.',
   'Catalogo com treinamentos variados.',
   '[{"ordem":1,"acao":"Abrir a aba Explorar","resultado_esperado":"Catalogo carrega"},
     {"ordem":2,"acao":"Buscar por um termo e aplicar filtro de categoria e de nivel","resultado_esperado":"A lista segmenta conforme os filtros"}]'::jsonb,
   'Busca e filtros funcionam combinados.',
   NULL),

  (v_mod, 'ACAD-021', 'Busca sem correspondencia mostra vazio amigavel',
   'negativo', 'baixa', 'aprovado', 'e2e', NULL,
   'Filtro que nao encontra nada deve terminar em estado vazio claro, sem erro nem spinner eterno.',
   'Aba Explorar aberta.',
   '[{"ordem":1,"acao":"Buscar por um termo inexistente","resultado_esperado":"Estado vazio adequado; sem erro"}]'::jsonb,
   'O vazio e um estado, nao um defeito.',
   NULL),

  (v_mod, 'ACAD-022', 'Abrir um treinamento e ver modulos e aulas',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'O detalhe do treinamento mostra a trilha: modulos e aulas na ordem, com o progresso do aluno.',
   'Um treinamento com modulos e aulas.',
   '[{"ordem":1,"acao":"Abrir um treinamento do catalogo","resultado_esperado":"Detalhe abre com os modulos e aulas listados"}]'::jsonb,
   'A estrutura do treinamento fica visivel para o aluno.',
   NULL),

  (v_mod, 'ACAD-023', 'Assistir e concluir uma aula avanca o progresso e ganha XP',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O motor de gamificacao: concluir uma aula marca progresso e credita XP. E o que engaja o aluno.',
   'Aluno com um treinamento aberto; aula pendente.',
   '[{"ordem":1,"acao":"Abrir uma aula e marca-la como concluida","resultado_esperado":"A aula fica marcada como concluida"},
     {"ordem":2,"acao":"Conferir o progresso e o XP","resultado_esperado":"O progresso do treinamento avanca e o XP aumenta"}]'::jsonb,
   'Concluir aula reflete em progresso e XP.',
   NULL),

  (v_mod, 'ACAD-024', 'Favoritar e desfavoritar um treinamento',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'O aluno guarda o que interessa. Favoritar liga, desfavoritar desliga, e a aba Favoritos reflete.',
   'Aluno autenticado; um treinamento no catalogo.',
   '[{"ordem":1,"acao":"Favoritar um treinamento","resultado_esperado":"Passa a aparecer na aba Favoritos"},
     {"ordem":2,"acao":"Desfavoritar o mesmo treinamento","resultado_esperado":"Sai da aba Favoritos"}]'::jsonb,
   'O favorito acompanha a acao do aluno.',
   NULL),

  (v_mod, 'ACAD-025', 'Concluir todas as aulas fecha o treinamento com badge e XP',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'A recompensa do fim: ao concluir todas as aulas, o treinamento e dado como concluido e o aluno recebe o badge e o XP.',
   'Aluno com um treinamento com poucas aulas, quase todo concluido.',
   '[{"ordem":1,"acao":"Concluir a ultima aula pendente do treinamento","resultado_esperado":"O treinamento aparece como concluido"},
     {"ordem":2,"acao":"Conferir badges e XP","resultado_esperado":"O badge do treinamento e o XP sao creditados"}]'::jsonb,
   'Concluir tudo gera badge e XP.',
   NULL),

  (v_mod, 'ACAD-026', 'Meus Cursos lista os treinamentos em andamento',
   'feliz', 'baixa', 'aprovado', 'e2e', NULL,
   'O aluno retoma de onde parou: Meus Cursos reune os treinamentos comecados e nao concluidos.',
   'Aluno com pelo menos um treinamento em progresso.',
   '[{"ordem":1,"acao":"Abrir a aba Meus Cursos","resultado_esperado":"Aparecem os treinamentos em andamento com o progresso de cada um"}]'::jsonb,
   'A retomada dos estudos e direta.',
   NULL),

  -- ── C) ACESSO ──
  (v_mod, 'ACAD-030', 'Academia restrita ao Super Admin',
   'negativo', 'critica', 'aprovado', 'e2e', NULL,
   'A Academia e area de Super Admin. Perfil comum nao deve ver o menu nem acessar a rota.',
   'Duas contas: uma Super Admin e uma de colaborador comum.',
   '[{"ordem":1,"acao":"Entrar como Super Admin","resultado_esperado":"O menu Academia aparece e a tela abre"},
     {"ordem":2,"acao":"Entrar como colaborador comum","resultado_esperado":"O menu Academia nao aparece e a rota nao abre"}]'::jsonb,
   'A superficie da Academia segue o perfil.',
   'A rota /academia e protegida como Super Admin.')

  ON CONFLICT (codigo) DO NOTHING;
END $acad$;

-- ── REDE DE PARCEIROS (Marketplace) ──────────────────────────────────────────
DO $parc$
DECLARE v_mod uuid;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'rede-parceiros';
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo rede-parceiros nao encontrado — casos PARC nao inseridos.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  -- ── A) CADASTRO E VALIDACAO DE PROFISSIONAL ──
  (v_mod, 'PARC-001', 'Cadastrar-se como profissional (com documentos e selfie)',
   'feliz', 'critica', 'aprovado', 'e2e', NULL,
   'A porta de entrada da Rede: o profissional se cadastra enviando dados, documentos comprobatorios e selfie de verificacao. O perfil vai para analise, nao entra ativo direto.',
   'Usuario autenticado; formulario de cadastro de profissional aberto.',
   '[{"ordem":1,"acao":"Preencher os dados do profissional e anexar documentos e a selfie","resultado_esperado":"Campos e anexos aceitos"},
     {"ordem":2,"acao":"Enviar o cadastro","resultado_esperado":"Confirmacao de envio; perfil criado com status em analise (pendente)"}]'::jsonb,
   'O cadastro e registrado para analise, com documentos e selfie.',
   'O texto da tela avisa que o perfil sera analisado antes de ficar visivel.'),

  (v_mod, 'PARC-002', 'Perfil pendente nao aparece na Rede antes da validacao',
   'negativo', 'critica', 'aprovado', 'e2e',
   'LGPD e confianca do canal (exibicao publica de profissional so apos validacao)',
   'Um profissional recem-cadastrado, ainda em analise, NAO pode aparecer na lista publica de profissionais. Exibir antes de validar quebra a confianca e expoe dado nao conferido.',
   'Um profissional cadastrado e ainda em analise.',
   '[{"ordem":1,"acao":"Abrir a aba de Profissionais na Rede","resultado_esperado":"O profissional em analise NAO aparece na lista publica"}]'::jsonb,
   'So profissional validado fica visivel na Rede.',
   NULL),

  (v_mod, 'PARC-003', 'Validacao: administrador aprova o profissional',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'A curadoria da Rede: o administrador analisa o cadastro e aprova. So entao o profissional fica ativo e visivel.',
   'Perfil administrador; um profissional em analise na aba Validacao.',
   '[{"ordem":1,"acao":"Abrir a aba Validacao e aprovar o profissional","resultado_esperado":"Status passa para ativo"},
     {"ordem":2,"acao":"Conferir a aba de Profissionais","resultado_esperado":"O profissional aprovado passa a aparecer na Rede"}]'::jsonb,
   'Aprovar torna o profissional ativo e visivel.',
   'A aprovacao fica registrada na trilha de auditoria.'),

  (v_mod, 'PARC-004', 'Validacao: administrador reprova com motivo',
   'alternativo', 'alta', 'aprovado', 'e2e', NULL,
   'Nem todo cadastro entra. Ao reprovar, o profissional fica rejeitado (nao visivel) e o motivo fica registrado.',
   'Perfil administrador; um profissional em analise.',
   '[{"ordem":1,"acao":"Reprovar o profissional informando o motivo","resultado_esperado":"Status passa para rejeitado"},
     {"ordem":2,"acao":"Conferir a Rede e a trilha","resultado_esperado":"O profissional nao aparece; a reprovacao fica registrada na auditoria"}]'::jsonb,
   'Reprovar mantem o profissional fora da Rede e deixa rastro.',
   NULL),

  (v_mod, 'PARC-005', 'Profissional com registro vencido e bloqueado automaticamente',
   'excecao', 'alta', 'aprovado', 'e2e', NULL,
   'Registro profissional vencido nao pode atender. O sistema bloqueia automaticamente quem esta com o registro vencido, sem depender de acao manual.',
   'Um profissional ativo cujo registro esteja vencido.',
   '[{"ordem":1,"acao":"Observar um profissional com registro vencido","resultado_esperado":"Aparece bloqueado e indisponivel para contratacao"}]'::jsonb,
   'Registro vencido bloqueia o profissional sem passo manual.',
   NULL),

  -- ── B) SERVICOS E CATALOGO ──
  (v_mod, 'PARC-010', 'Cadastrar um servico',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O profissional oferece o que faz: cadastra um servico que passa a poder ser contratado.',
   'Profissional ativo autenticado.',
   '[{"ordem":1,"acao":"Cadastrar um novo servico com os dados exigidos","resultado_esperado":"Campos aceitos"},
     {"ordem":2,"acao":"Salvar","resultado_esperado":"O servico aparece no catalogo de servicos"}]'::jsonb,
   'O servico e criado e fica disponivel para contratacao.',
   NULL),

  (v_mod, 'PARC-011', 'Cadastrar um pacote de servicos',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Pacote agrupa servicos numa oferta unica. Deve ser criavel e aparecer na aba Pacotes.',
   'Profissional ativo com servicos cadastrados.',
   '[{"ordem":1,"acao":"Criar um pacote reunindo servicos","resultado_esperado":"Pacote salvo"},
     {"ordem":2,"acao":"Conferir a aba Pacotes","resultado_esperado":"O pacote aparece"}]'::jsonb,
   'O pacote e criado e listado.',
   NULL),

  (v_mod, 'PARC-012', 'Explorar e buscar profissionais e servicos por categoria',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'A empresa acha quem precisa: a busca e o filtro por categoria segmentam profissionais e servicos.',
   'Rede com profissionais ativos e servicos em categorias variadas.',
   '[{"ordem":1,"acao":"Abrir a Rede e filtrar por uma categoria","resultado_esperado":"A lista mostra apenas o que bate com a categoria"}]'::jsonb,
   'A busca por categoria funciona.',
   NULL),

  -- ── C) CONTRATACAO, EXECUCAO E AVALIACAO ──
  (v_mod, 'PARC-020', 'Contratar um servico',
   'feliz', 'critica', 'aprovado', 'e2e', NULL,
   'Caminho feliz central da Rede: a empresa contrata um servico de um profissional. E o que a Rede existe para fazer.',
   'Empresa autenticada; um servico disponivel de um profissional ativo.',
   '[{"ordem":1,"acao":"Escolher um servico e acionar Contratar","resultado_esperado":"Fluxo de contratacao abre"},
     {"ordem":2,"acao":"Confirmar a contratacao","resultado_esperado":"Contratacao criada com status inicial e visivel na aba Contratacoes"}]'::jsonb,
   'A contratacao e registrada e acompanhavel.',
   NULL),

  (v_mod, 'PARC-021', 'Confirmar a execucao da contratacao',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'O ciclo caminha: apos o servico ser prestado, a execucao e confirmada e a contratacao avanca de status.',
   'Uma contratacao em andamento.',
   '[{"ordem":1,"acao":"Abrir a contratacao e confirmar a execucao","resultado_esperado":"O status da contratacao avanca"}]'::jsonb,
   'Confirmar execucao move a contratacao no fluxo.',
   NULL),

  (v_mod, 'PARC-022', 'Avaliar a contratacao concluida',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'A reputacao da Rede vem da avaliacao: apos concluir, a empresa avalia o profissional com nota e comentario.',
   'Uma contratacao concluida.',
   '[{"ordem":1,"acao":"Abrir a contratacao concluida e acionar Avaliar","resultado_esperado":"Modal de avaliacao abre"},
     {"ordem":2,"acao":"Dar a nota e o comentario e enviar","resultado_esperado":"Avaliacao registrada e refletida no perfil do profissional"}]'::jsonb,
   'A avaliacao fica gravada e compoe a reputacao.',
   NULL),

  (v_mod, 'PARC-023', 'Avaliacao restrita a aspectos profissionais e administrativos',
   'negativo', 'media', 'aprovado', 'e2e',
   'Etica: vedado avaliar conteudo clinico ou terapeutico',
   'A avaliacao e sobre atendimento e conduta profissional/administrativa, nao sobre conteudo clinico ou terapeutico. A tela deve deixar isso claro e nao induzir avaliacao clinica.',
   'Modal de avaliacao aberto.',
   '[{"ordem":1,"acao":"Abrir o modal de avaliacao","resultado_esperado":"O aviso de que so se avalia aspecto profissional/administrativo (nao clinico) esta visivel"}]'::jsonb,
   'A avaliacao nao induz julgamento clinico.',
   NULL),

  (v_mod, 'PARC-024', 'Nao permite avaliar sem contratacao concluida',
   'negativo', 'media', 'aprovado', 'e2e', NULL,
   'Avaliacao sem contratacao correspondente e avaliacao fantasma. So quem contratou e concluiu pode avaliar.',
   'Um profissional sem contratacao concluida pelo usuario atual.',
   '[{"ordem":1,"acao":"Tentar avaliar um profissional sem ter uma contratacao concluida com ele","resultado_esperado":"A avaliacao nao e permitida"}]'::jsonb,
   'Avaliacao exige contratacao concluida.',
   NULL),

  -- ── D) DENUNCIA E AFILIADOS ──
  (v_mod, 'PARC-030', 'Denunciar um profissional ou servico',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Canal de integridade: qualquer conduta impropria pode ser denunciada, e a denuncia vai para a gestao tratar.',
   'Rede aberta; um profissional ou servico visivel.',
   '[{"ordem":1,"acao":"Acionar Denunciar em um profissional ou servico e descrever o motivo","resultado_esperado":"Denuncia enviada"},
     {"ordem":2,"acao":"Conferir a aba de Denuncias (gestao)","resultado_esperado":"A denuncia aparece para tratamento"}]'::jsonb,
   'A denuncia e registrada e chega a gestao.',
   NULL),

  (v_mod, 'PARC-031', 'Afiliados: link de indicacao gera comissao',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'O programa de afiliados: o profissional compartilha um link exclusivo e recebe comissao quando uma empresa se cadastra por ele.',
   'Profissional ativo; painel de Afiliados aberto.',
   '[{"ordem":1,"acao":"Abrir o painel de Afiliados e obter o link de indicacao","resultado_esperado":"Link exclusivo disponivel"},
     {"ordem":2,"acao":"Conferir as comissoes","resultado_esperado":"O painel mostra as comissoes das indicacoes"}]'::jsonb,
   'O afiliado tem link e acompanha as comissoes.',
   NULL)

  ON CONFLICT (codigo) DO NOTHING;
END $parc$;

-- Conferencia (o editor mostra so o ultimo resultado)
SELECT m.label AS modulo,
       m.path,
       count(c.id) AS total_casos,
       count(c.id) FILTER (WHERE c.codigo LIKE 'ACAD-%' OR c.codigo LIKE 'PARC-%') AS desta_entrega
FROM public.qa_modulos m
LEFT JOIN public.qa_casos_teste c ON c.modulo_id = m.id
WHERE m.path IN ('academia','rede-parceiros')
GROUP BY m.label, m.path
ORDER BY m.path;
