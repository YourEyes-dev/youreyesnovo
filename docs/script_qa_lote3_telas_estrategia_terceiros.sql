-- =========================================================
-- ENTREGA QA — Lote 3 (final) de telas (35 casos e2e em 5 módulos só-motor)
--
-- Cole este arquivo inteiro no SQL Editor do ambiente de HOMOLOGACAO
-- (projeto fgsblefvdabgdouipigz). Documenta o LADO DE TELA (nivel e2e) de:
--   Planejamento Estratégico (7), Organograma (6), Identidade/Cultura (6),
--   Prestadores/Terceiros (7), Afastamentos (9).
-- Códigos <MOD>-TELA-NN, sem colisão com as sondas de motor.
--
-- Só INSERE linhas em qa_casos_teste — não cria nem altera estrutura, então
-- não mexe na fidelidade com a producao. Idempotente: ON CONFLICT DO NOTHING.
-- Cada bloco procura o módulo pelo path; se não achar, avisa e pula (RAISE
-- NOTICE + RETURN dentro do IF) sem abortar os demais. Roda em UMA transacao.
-- Ao final, uma unica conferencia SELECT lista o registrado por módulo.
-- =========================================================

SET lock_timeout = '10s';

-- ══════════════════════════════════════════════════════════
-- PLANEJAMENTO ESTRATÉGICO  (planejamento-gestao/planejamento-estrategico) — /estrategia
-- ══════════════════════════════════════════════════════════
DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'planejamento-gestao/planejamento-estrategico';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo planejamento-gestao/planejamento-estrategico não encontrado — nada a fazer.'; RETURN; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'PLEST-TELA-01', 'Módulo abre com SWOT e Oceano Azul',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O planejamento estratégico reúne as ferramentas clássicas de direção. Se não monta, o RH perde SWOT e Oceano Azul.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar /estrategia","resultado_esperado":"Título Planejamento Estratégico carrega"},
     {"ordem":2,"acao":"Conferir as sub-abas e as ações","resultado_esperado":"Sub-abas SWOT e Oceano Azul; botão Guia Rapido; seletor de escopo"}]'::jsonb,
   'O módulo monta com SWOT e Oceano Azul.', NULL),

  (v_mod, 'PLEST-TELA-02', 'SWOT lista e abre Nova Análise SWOT',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'A SWOT é a leitura de forças, fraquezas, oportunidades e ameaças. Criar uma é o ato central da aba.',
   'Sub-aba SWOT.',
   '[{"ordem":1,"acao":"Abrir a sub-aba SWOT e clicar em Nova SWOT","resultado_esperado":"Abre o diálogo Nova Análise SWOT com título, descrição e escopo (Empresa/Unidade/Projeto)"},
     {"ordem":2,"acao":"Fechar sem salvar","resultado_esperado":"Fecha sem criar nada"}]'::jsonb,
   'A SWOT lista e o formulário de nova análise abre.', NULL),

  (v_mod, 'PLEST-TELA-03', 'Oceano Azul lista e abre Nova Matriz',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'A matriz Oceano Azul (Eliminar, Reduzir, Elevar, Criar) orienta a inovação de valor. Criar uma é o ato central da aba.',
   'Sub-aba Oceano Azul.',
   '[{"ordem":1,"acao":"Abrir a sub-aba Oceano Azul e clicar em Nova Matriz","resultado_esperado":"Abre o diálogo Nova Matriz Oceano Azul; a aba explica Eliminar, Reduzir, Elevar e Criar"},
     {"ordem":2,"acao":"Conferir quando não há nenhuma","resultado_esperado":"Mostra Nenhuma matriz criada"}]'::jsonb,
   'O Oceano Azul lista e o formulário de nova matriz abre.', NULL),

  (v_mod, 'PLEST-TELA-04', 'Seletor de escopo recorta a estratégia',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'A estratégia pode ser da empresa ou de um grupo. O seletor de escopo recorta o que se vê.',
   'Rota /estrategia.',
   '[{"ordem":1,"acao":"Trocar o escopo no seletor","resultado_esperado":"As análises exibidas passam a refletir o escopo escolhido"}]'::jsonb,
   'O seletor de escopo recorta a estratégia.', NULL),

  (v_mod, 'PLEST-TELA-05', 'Excluir matriz Oceano Azul pede confirmação',
   'negativo', 'media', 'aprovado', 'e2e', NULL,
   'Excluir uma matriz é irreversível. Precisa de confirmação explícita antes de apagar.',
   'Existir ao menos uma matriz Oceano Azul.',
   '[{"ordem":1,"acao":"Acionar excluir numa matriz","resultado_esperado":"Abre a confirmação Excluir matriz Oceano Azul?"},
     {"ordem":2,"acao":"Cancelar","resultado_esperado":"Nada é apagado"}]'::jsonb,
   'A exclusão de matriz exige confirmação.', NULL),

  (v_mod, 'PLEST-TELA-06', 'Guia Rápido abre',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'O guia rápido explica as ferramentas para quem chega. É apoio de adoção.',
   'Rota /estrategia.',
   '[{"ordem":1,"acao":"Clicar em Guia Rapido","resultado_esperado":"Abre o guia rápido da estratégia"}]'::jsonb,
   'O guia rápido abre.', NULL),

  (v_mod, 'PLEST-TELA-07', 'Vazio orienta a criar a primeira análise',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Sem análises, a tela precisa orientar a começar — não ficar em branco.',
   'Ambiente sem análises SWOT.',
   '[{"ordem":1,"acao":"Abrir a sub-aba SWOT sem nenhuma análise","resultado_esperado":"Mostra Nenhuma análise SWOT criada, sem quebrar"}]'::jsonb,
   'O vazio orienta a criar a primeira análise.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Planejamento Estratégico (tela): antes=%, depois=% (esperado +7)', v_antes, v_depois;
END $doc$;

-- ══════════════════════════════════════════════════════════
-- ORGANOGRAMA  (estrutura-organizacional/organograma) — /estrategia?tab=organograma
-- ══════════════════════════════════════════════════════════
DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'estrutura-organizacional/organograma';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo estrutura-organizacional/organograma não encontrado — nada a fazer.'; RETURN; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'ORG-TELA-01', 'Organograma abre com a estrutura hierárquica',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O organograma desenha a hierarquia da empresa. Se não monta, some a visão de estrutura e de subordinação.',
   'Usuário autenticado; abrir a visão de organograma.',
   '[{"ordem":1,"acao":"Acessar /estrategia?tab=organograma (menu Organograma)","resultado_esperado":"Título Organograma carrega, com a estrutura hierárquica"}]'::jsonb,
   'O organograma monta com a estrutura.', NULL),

  (v_mod, 'ORG-TELA-02', 'Abrir o formulário de Nova Posição',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'Montar o organograma começa por criar posição. O formulário precisa abrir.',
   'Visão de organograma.',
   '[{"ordem":1,"acao":"Clicar em Nova Posição","resultado_esperado":"Abre o formulário de nova posição"},
     {"ordem":2,"acao":"Fechar sem salvar","resultado_esperado":"Fecha sem criar nada"}]'::jsonb,
   'O formulário de Nova Posição abre e fecha sem efeito.', NULL),

  (v_mod, 'ORG-TELA-03', 'Gerar Organograma com IA sugere a hierarquia',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'A geração por IA propõe a hierarquia a partir de cargos e chefias. Deve sugerir sem aplicar sozinha.',
   'Visão de organograma.',
   '[{"ordem":1,"acao":"Acionar Gerar Organograma","resultado_esperado":"Abre a sugestão com as opções Gerar (adicionar) e Limpar e Gerar (recriar)"}]'::jsonb,
   'A geração por IA sugere a hierarquia.', NULL),

  (v_mod, 'ORG-TELA-04', 'Limpar e Gerar avisa antes de recriar',
   'negativo', 'media', 'aprovado', 'e2e', NULL,
   'Limpar e Gerar apaga o organograma atual antes de recriar. É destrutivo — precisa avisar/confirmar.',
   'Sugestão de organograma aberta.',
   '[{"ordem":1,"acao":"Escolher Limpar e Gerar","resultado_esperado":"O sistema avisa que vai recriar (limpar antes) — a ação é destacada como destrutiva"}]'::jsonb,
   'Limpar e Gerar avisa antes de recriar.', NULL),

  (v_mod, 'ORG-TELA-05', 'Escopo recorta o organograma',
   'feliz', 'baixa', 'aprovado', 'e2e', NULL,
   'O organograma pode ser da empresa ou de um grupo. O escopo recorta o que se desenha.',
   'Visão de organograma.',
   '[{"ordem":1,"acao":"Trocar o escopo","resultado_esperado":"O organograma passa a refletir o escopo escolhido"}]'::jsonb,
   'O escopo recorta o organograma.', NULL),

  (v_mod, 'ORG-TELA-06', 'Vazio orienta a montar o organograma',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Sem posições, a tela precisa orientar a montar — por Nova Posição ou por Gerar com IA.',
   'Ambiente sem organograma montado.',
   '[{"ordem":1,"acao":"Abrir o organograma vazio","resultado_esperado":"Orienta a começar (Nova Posição ou Gerar), sem quebrar"}]'::jsonb,
   'O vazio orienta a montar o organograma.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Organograma (tela): antes=%, depois=% (esperado +6)', v_antes, v_depois;
END $doc$;

-- ══════════════════════════════════════════════════════════
-- IDENTIDADE / CULTURA  (planejamento-gestao/identidade-estrategica) — /estrategia?tab=cultura
-- ══════════════════════════════════════════════════════════
DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'planejamento-gestao/identidade-estrategica';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo planejamento-gestao/identidade-estrategica não encontrado — nada a fazer.'; RETURN; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'IDENT-TELA-01', 'Cultura abre com Missão, Visão e Valores',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'A identidade (missão, visão, valores) é a base cultural da empresa. Se não monta, some o alicerce do que orienta as decisões.',
   'Usuário autenticado; abrir a visão de Cultura.',
   '[{"ordem":1,"acao":"Acessar /estrategia?tab=cultura (menu Cultura)","resultado_esperado":"Título Cultura carrega, com as abas Editor e Dashboard e os campos Missão, Visão e Valores"}]'::jsonb,
   'A Cultura monta com Missão, Visão e Valores.', NULL),

  (v_mod, 'IDENT-TELA-02', 'Editar Missão e Visão',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Missão e Visão respondem por que a empresa existe e aonde quer chegar. O editor precisa capturá-las.',
   'Aba Editor da Cultura.',
   '[{"ordem":1,"acao":"Preencher os campos Missão e Visão","resultado_esperado":"Os campos aceitam o texto (propósito e futuro da empresa)"}]'::jsonb,
   'Missão e Visão podem ser editadas.', NULL),

  (v_mod, 'IDENT-TELA-03', 'Adicionar valores',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Os valores guiam o comportamento. O editor precisa permitir adicionar itens, e orientar quando vazio.',
   'Aba Editor da Cultura.',
   '[{"ordem":1,"acao":"Adicionar um valor","resultado_esperado":"O item entra na lista de Valores"},
     {"ordem":2,"acao":"Conferir a lista vazia","resultado_esperado":"Mostra Nenhum item adicionado"}]'::jsonb,
   'Os valores podem ser adicionados; o vazio orienta.', NULL),

  (v_mod, 'IDENT-TELA-04', 'Gerar Manual com IA degrada sem a chave',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'A IA gera um manual de cultura a partir da identidade. Sem a chave, deve avisar com elegância, nunca derrubar a tela.',
   'Aba Editor da Cultura.',
   '[{"ordem":1,"acao":"Acionar Gerar Manual com IA","resultado_esperado":"Gera o manual (ou Regerar, se já houver)"},
     {"ordem":2,"acao":"Acionar sem a chave de IA","resultado_esperado":"Mostra aviso claro; a tela não quebra"}]'::jsonb,
   'A geração do manual trata a ausência de IA sem quebrar.', NULL),

  (v_mod, 'IDENT-TELA-05', 'Dashboard da cultura abre',
   'feliz', 'baixa', 'aprovado', 'e2e', NULL,
   'O painel da cultura mostra a leitura consolidada. Deve montar sem erro.',
   'Aba Dashboard da Cultura.',
   '[{"ordem":1,"acao":"Abrir a aba Dashboard","resultado_esperado":"O painel da cultura carrega"}]'::jsonb,
   'O Dashboard da cultura abre sem quebrar.', NULL),

  (v_mod, 'IDENT-TELA-06', 'Escopo recorta a identidade',
   'feliz', 'baixa', 'aprovado', 'e2e', NULL,
   'A identidade pode ser da empresa ou de um grupo. O escopo recorta o que se vê.',
   'Visão de Cultura.',
   '[{"ordem":1,"acao":"Trocar o escopo","resultado_esperado":"A identidade exibida reflete o escopo escolhido"}]'::jsonb,
   'O escopo recorta a identidade.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Identidade/Cultura (tela): antes=%, depois=% (esperado +6)', v_antes, v_depois;
END $doc$;

-- ══════════════════════════════════════════════════════════
-- PRESTADORES / TERCEIROS  (estrutura-organizacional/prestadores) — /terceiros
-- ══════════════════════════════════════════════════════════
DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'estrutura-organizacional/prestadores';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo estrutura-organizacional/prestadores não encontrado — nada a fazer.'; RETURN; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'TERC-TELA-01', 'Módulo Terceiros abre com as abas',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'Terceiros/prestadores exigem controle de SST e de documentos (a empresa responde solidariamente). Se não monta, some esse controle.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar /terceiros","resultado_esperado":"Título Gestão de Terceiros & SST carrega"},
     {"ordem":2,"acao":"Conferir as abas e a ação","resultado_esperado":"Abas Dashboard, Terceiros, Permissões de Trabalho e Vencimentos; botão Novo Terceiro"}]'::jsonb,
   'O módulo monta com as abas e o botão Novo Terceiro.', NULL),

  (v_mod, 'TERC-TELA-02', 'Abrir o formulário de Novo Terceiro',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'Cadastrar o terceiro é o ato central. O formulário precisa abrir.',
   'Rota /terceiros.',
   '[{"ordem":1,"acao":"Clicar em Novo Terceiro","resultado_esperado":"Abre o formulário de novo terceiro"},
     {"ordem":2,"acao":"Fechar sem salvar","resultado_esperado":"Fecha sem criar nada"}]'::jsonb,
   'O formulário de Novo Terceiro abre e fecha sem efeito.', NULL),

  (v_mod, 'TERC-TELA-03', 'Aba Terceiros lista e busca por razão social/CNPJ',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'A aba Terceiros reúne os prestadores. A busca por razão social/CNPJ é o atalho.',
   'Aba Terceiros.',
   '[{"ordem":1,"acao":"Abrir a aba Terceiros e digitar na busca","resultado_esperado":"A lista recorta por razão social ou CNPJ"}]'::jsonb,
   'A aba Terceiros lista e a busca funciona.', NULL),

  (v_mod, 'TERC-TELA-04', 'Permissões de Trabalho abre',
   'feliz', 'media', 'aprovado', 'e2e', 'NR-33 / NR-35 (permissão de trabalho)',
   'A permissão de trabalho (PT) autoriza tarefas de risco de terceiros. A aba precisa montar.',
   'Aba Permissões de Trabalho.',
   '[{"ordem":1,"acao":"Abrir a aba Permissões de Trabalho","resultado_esperado":"O painel de permissões de trabalho carrega"}]'::jsonb,
   'A aba Permissões de Trabalho abre sem quebrar.', NULL),

  (v_mod, 'TERC-TELA-05', 'Vencimentos alerta documentos a vencer',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Documento de terceiro vencido é risco legal e de acesso. A aba Vencimentos destaca o que está por vencer.',
   'Aba Vencimentos.',
   '[{"ordem":1,"acao":"Abrir a aba Vencimentos","resultado_esperado":"Aparecem os documentos a vencer/vencidos dos terceiros"}]'::jsonb,
   'A aba Vencimentos alerta documentos.', NULL),

  (v_mod, 'TERC-TELA-06', 'Dashboard resume os terceiros',
   'feliz', 'baixa', 'aprovado', 'e2e', NULL,
   'O painel resume a situação dos terceiros — o pulso do módulo.',
   'Aba Dashboard.',
   '[{"ordem":1,"acao":"Abrir a aba Dashboard","resultado_esperado":"O resumo dos terceiros carrega"}]'::jsonb,
   'O Dashboard resume os terceiros.', NULL),

  (v_mod, 'TERC-TELA-07', 'Vazio orienta a cadastrar o primeiro terceiro',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Sem terceiros, a tela precisa orientar a começar — não ficar em branco.',
   'Ambiente sem terceiros cadastrados.',
   '[{"ordem":1,"acao":"Abrir a aba Terceiros sem nenhum cadastro","resultado_esperado":"Orienta a cadastrar o primeiro (Novo Terceiro), sem quebrar"}]'::jsonb,
   'O vazio orienta a cadastrar.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Prestadores/Terceiros (tela): antes=%, depois=% (esperado +7)', v_antes, v_depois;
END $doc$;

-- ══════════════════════════════════════════════════════════
-- AFASTAMENTOS  (jornada-rotina/afastamentos) — /atestados (MOD-GAF)
-- ══════════════════════════════════════════════════════════
DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'jornada-rotina/afastamentos';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo jornada-rotina/afastamentos não encontrado — nada a fazer.'; RETURN; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'AFAST-TELA-01', 'Central GAF abre com as abas',
   'feliz', 'alta', 'aprovado', 'e2e', 'Lei 8.213/1991 (benefício por incapacidade); eSocial S-2230',
   'A central de atestados e afastamentos é onde se controla ausência, CID e benefício. Se não monta, some o controle de absenteísmo.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar /atestados","resultado_esperado":"Título MOD-GAF (Gestão Inteligente de Atestados e Afastamentos) carrega"},
     {"ordem":2,"acao":"Conferir as abas","resultado_esperado":"Atestados, Afastamentos, Absenteísmo, Saúde Mental, FAP/RAT e Pendências"}]'::jsonb,
   'A central monta com as abas.', NULL),

  (v_mod, 'AFAST-TELA-02', 'Aba Afastamentos lista os afastamentos',
   'feliz', 'alta', 'aprovado', 'e2e', 'Lei 8.213/1991 art. 60 (afastamento a partir do 16º dia)',
   'A aba Afastamentos reúne os afastamentos e seus prazos (o 15/16º dia muda quem paga). Precisa montar.',
   'Aba Afastamentos.',
   '[{"ordem":1,"acao":"Abrir a aba Afastamentos","resultado_esperado":"A lista de afastamentos carrega"}]'::jsonb,
   'A aba Afastamentos lista os afastamentos.', NULL),

  (v_mod, 'AFAST-TELA-03', 'Abrir o formulário de Novo Afastamento',
   'feliz', 'alta', 'aprovado', 'e2e', 'eSocial S-2230 (afastamento temporário)',
   'Registrar o afastamento é o ato central. O formulário precisa abrir na aba Afastamentos.',
   'Aba Afastamentos.',
   '[{"ordem":1,"acao":"Na aba Afastamentos, acionar Novo Afastamento","resultado_esperado":"Abre o formulário de novo afastamento"},
     {"ordem":2,"acao":"Fechar sem salvar","resultado_esperado":"Fecha sem criar nada"}]'::jsonb,
   'O formulário de Novo Afastamento abre e fecha sem efeito.', NULL),

  (v_mod, 'AFAST-TELA-04', 'Atestados lista e abre Novo Atestado',
   'feliz', 'media', 'aprovado', 'e2e', 'CLT / Lei 605/1949 (abono da falta por atestado)',
   'O atestado abona a falta e pode virar afastamento. A aba Atestados precisa listar e permitir cadastrar.',
   'Aba Atestados.',
   '[{"ordem":1,"acao":"Abrir a aba Atestados e acionar Novo Atestado","resultado_esperado":"A lista de atestados aparece e o formulário de novo atestado abre"}]'::jsonb,
   'A aba Atestados lista e o formulário abre.', NULL),

  (v_mod, 'AFAST-TELA-05', 'Absenteísmo resume dias perdidos',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'O absenteísmo é o indicador de perda de jornada por ausência. A aba resume o total e os dias perdidos.',
   'Aba Absenteísmo.',
   '[{"ordem":1,"acao":"Abrir a aba Absenteísmo","resultado_esperado":"Aparecem os cards Total de Afastamentos e Dias Perdidos"}]'::jsonb,
   'A aba Absenteísmo resume os dias perdidos.', NULL),

  (v_mod, 'AFAST-TELA-06', 'Saúde Mental (CID F) sinaliza padrão coletivo',
   'alternativo', 'media', 'aprovado', 'e2e', 'LGPD art. 11 (dado sensível de saúde)',
   'Afastamentos por CID F (saúde mental) são dado sensível e sinal de risco coletivo. A aba consolida sem expor o indivíduo.',
   'Aba Saúde Mental.',
   '[{"ordem":1,"acao":"Abrir a aba Saúde Mental","resultado_esperado":"Aparecem Total Saúde Mental (CID F) e os Alertas de Padrão Coletivo"}]'::jsonb,
   'A aba Saúde Mental consolida o CID F e alerta padrão coletivo.', NULL),

  (v_mod, 'AFAST-TELA-07', 'FAP/RAT destaca CAT pendente',
   'feliz', 'media', 'aprovado', 'e2e', 'Lei 8.213/1991 art. 22 (emissão da CAT)',
   'FAP/RAT liga acidente a custo previdenciário; a CAT é obrigatória. A aba destaca o que está pendente.',
   'Aba FAP/RAT.',
   '[{"ordem":1,"acao":"Abrir a aba FAP/RAT","resultado_esperado":"Aparece o painel de FAP/RAT, com o destaque de CAT Pendente"}]'::jsonb,
   'A aba FAP/RAT destaca a CAT pendente.', NULL),

  (v_mod, 'AFAST-TELA-08', 'Pendências destaca o que falta tratar',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'A aba Pendências reúne o que precisa de ação (atestado sem CID, afastamento sem eSocial, CAT pendente). É o chamado à ação.',
   'Aba Pendências.',
   '[{"ordem":1,"acao":"Abrir a aba Pendências","resultado_esperado":"Aparece o que está pendente de tratamento"}]'::jsonb,
   'A aba Pendências destaca o que falta tratar.', NULL),

  (v_mod, 'AFAST-TELA-09', 'Busca por trabalhador ou CID',
   'feliz', 'baixa', 'aprovado', 'e2e', NULL,
   'Achar um caso por trabalhador ou CID é o atalho do dia a dia. A busca deve recortar a lista.',
   'Rota /atestados.',
   '[{"ordem":1,"acao":"Digitar em Buscar trabalhador, CID","resultado_esperado":"A lista recorta pelo trabalhador ou pelo CID informado"}]'::jsonb,
   'A busca por trabalhador/CID recorta a lista.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Afastamentos (tela): antes=%, depois=% (esperado +9)', v_antes, v_depois;
END $doc$;

-- ── Conferência (última query: é o que o SQL Editor exibe) ──
SELECT m.path AS modulo, count(*) AS casos_tela, min(c.codigo) AS primeiro, max(c.codigo) AS ultimo
FROM public.qa_casos_teste c
JOIN public.qa_modulos m ON m.id = c.modulo_id
WHERE c.codigo LIKE '%-TELA-%'
  AND m.path IN ('planejamento-gestao/planejamento-estrategico','estrutura-organizacional/organograma',
                 'planejamento-gestao/identidade-estrategica','estrutura-organizacional/prestadores',
                 'jornada-rotina/afastamentos')
GROUP BY m.path ORDER BY m.path;
