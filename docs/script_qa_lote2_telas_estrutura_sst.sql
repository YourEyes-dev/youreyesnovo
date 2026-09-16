-- =========================================================
-- ENTREGA QA — Lote 2 de telas (30 casos e2e em 4 módulos só-motor)
--
-- Cole este arquivo inteiro no SQL Editor do ambiente de HOMOLOGACAO
-- (projeto fgsblefvdabgdouipigz). Documenta o LADO DE TELA (nivel e2e) de:
--   Departamentos (7), Cargos (7), Estabelecimentos (7), Compliance SST (9).
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
-- DEPARTAMENTOS  (estrutura-organizacional/departamentos) — /cadastros/departamentos
-- ══════════════════════════════════════════════════════════
DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'estrutura-organizacional/departamentos';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo estrutura-organizacional/departamentos não encontrado — nada a fazer.'; RETURN; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'DEPTO-TELA-01', 'Módulo Departamentos abre com a lista',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'Departamento é a base do organograma e da lotação. Se a lista não monta, o cadastro da estrutura para.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar /cadastros/departamentos","resultado_esperado":"Título Departamentos carrega"},
     {"ordem":2,"acao":"Conferir a tabela e as ações","resultado_esperado":"Colunas Nome, Estabelecimento/Obra, Gestor, Substituto e Status; botão Novo Departamento; campo de busca"}]'::jsonb,
   'O módulo monta com a lista e as ações.', NULL),

  (v_mod, 'DEPTO-TELA-02', 'Abrir o formulário de Novo Departamento',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'Criar departamento é o ato central. O formulário precisa abrir com os campos.',
   'Rota /cadastros/departamentos.',
   '[{"ordem":1,"acao":"Clicar em Novo Departamento","resultado_esperado":"Abre o diálogo Novo Departamento com nome, estabelecimento/obra, gestor e substituto"},
     {"ordem":2,"acao":"Fechar sem salvar","resultado_esperado":"Fecha sem criar nada"}]'::jsonb,
   'O formulário de Novo Departamento abre e fecha sem efeito.', NULL),

  (v_mod, 'DEPTO-TELA-03', 'Busca filtra a lista de departamentos',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'A busca é o caminho rápido em listas grandes. Deve recortar a lista pelo termo.',
   'Existirem departamentos.',
   '[{"ordem":1,"acao":"Digitar um termo em Buscar departamentos","resultado_esperado":"A lista recorta para os que casam"},
     {"ordem":2,"acao":"Buscar um termo inexistente","resultado_esperado":"Mostra Nenhum departamento encontrado"}]'::jsonb,
   'A busca filtra e trata o sem-resultado.', NULL),

  (v_mod, 'DEPTO-TELA-04', 'Vincular a estabelecimento/obra ou à empresa',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'O departamento pertence a um estabelecimento/obra ativo, ou fica vinculado à empresa. O vínculo organiza a lotação.',
   'Formulário de departamento aberto.',
   '[{"ordem":1,"acao":"Abrir o select de Estabelecimento/Obra no formulário","resultado_esperado":"Lista os estabelecimentos/obras ativos da empresa, mais a opção Nenhum (vinculado à empresa)"}]'::jsonb,
   'O vínculo com estabelecimento/obra é oferecido no formulário.', NULL),

  (v_mod, 'DEPTO-TELA-05', 'Definir gestor titular e substituto',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Gestor e substituto sustentam alçadas e coberturas. O formulário precisa oferecer os dois.',
   'Formulário de departamento aberto.',
   '[{"ordem":1,"acao":"Abrir os campos de Gestor e Substituto","resultado_esperado":"Permitem escolher o gestor titular e um substituto entre os colaboradores"}]'::jsonb,
   'Gestor e substituto podem ser definidos.', NULL),

  (v_mod, 'DEPTO-TELA-06', 'Estado vazio orienta a cadastrar o primeiro',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Sem departamentos, a tela precisa orientar a começar — não ficar em branco.',
   'Empresa sem departamentos.',
   '[{"ordem":1,"acao":"Abrir a lista sem nenhum departamento","resultado_esperado":"Mostra Nenhum departamento cadastrado, sem quebrar"}]'::jsonb,
   'O vazio orienta a cadastrar.', NULL),

  (v_mod, 'DEPTO-TELA-07', 'Excluir departamento pede confirmação',
   'negativo', 'media', 'aprovado', 'e2e', NULL,
   'Excluir é irreversível e afeta a lotação. Precisa de confirmação explícita antes de apagar.',
   'Existir ao menos um departamento.',
   '[{"ordem":1,"acao":"Acionar excluir num departamento","resultado_esperado":"Abre a confirmação Excluir Departamento"},
     {"ordem":2,"acao":"Cancelar","resultado_esperado":"Nada é apagado"}]'::jsonb,
   'A exclusão exige confirmação.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Departamentos (tela): antes=%, depois=% (esperado +7)', v_antes, v_depois;
END $doc$;

-- ══════════════════════════════════════════════════════════
-- CARGOS  (estrutura-organizacional/cargos) — /cadastros/cargos
-- ══════════════════════════════════════════════════════════
DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'estrutura-organizacional/cargos';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo estrutura-organizacional/cargos não encontrado — nada a fazer.'; RETURN; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'CARGO-TELA-01', 'Módulo Cargos abre com a lista',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'Cargo liga pessoa a salário, nível e risco. Se a lista não monta, o cadastro da estrutura para.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar /cadastros/cargos","resultado_esperado":"Título Cargos carrega"},
     {"ordem":2,"acao":"Conferir a tabela e as ações","resultado_esperado":"Colunas Nome, Departamentos, Nível, Faixa Salarial, Condições Especiais e Status; botão Novo Cargo; campo de busca"}]'::jsonb,
   'O módulo monta com a lista e as ações.', NULL),

  (v_mod, 'CARGO-TELA-02', 'Abrir o formulário de Novo Cargo com as abas',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O cadastro de cargo separa dados gerais de SST. O formulário precisa abrir com as duas abas.',
   'Rota /cadastros/cargos.',
   '[{"ordem":1,"acao":"Clicar em Novo Cargo","resultado_esperado":"Abre o diálogo Novo Cargo com as abas Dados Gerais e SST"},
     {"ordem":2,"acao":"Fechar sem salvar","resultado_esperado":"Fecha sem criar nada"}]'::jsonb,
   'O formulário de Novo Cargo abre com as abas.', NULL),

  (v_mod, 'CARGO-TELA-03', 'Aba SST captura grau de risco e condições especiais',
   'feliz', 'media', 'aprovado', 'e2e', 'NR-1 / NR-9 (agentes e riscos ocupacionais)',
   'O SST do cargo alimenta PGR/PCMSO e o eSocial. A aba precisa capturar risco e agentes.',
   'Formulário de cargo aberto.',
   '[{"ordem":1,"acao":"Abrir a aba SST","resultado_esperado":"Permite informar grau de risco e condições especiais (ex.: agente e grau, como ruído acima de 85 dB)"}]'::jsonb,
   'A aba SST captura risco e condições especiais.', NULL),

  (v_mod, 'CARGO-TELA-04', 'Vincular o cargo a departamentos',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Um cargo pode existir em vários departamentos. O formulário precisa permitir o vínculo.',
   'Formulário de cargo aberto; existirem departamentos.',
   '[{"ordem":1,"acao":"Abrir a seleção de Departamentos no formulário","resultado_esperado":"Permite vincular o cargo a um ou mais departamentos"}]'::jsonb,
   'O cargo pode ser vinculado a departamentos.', NULL),

  (v_mod, 'CARGO-TELA-05', 'Faixa salarial no cadastro',
   'feliz', 'baixa', 'aprovado', 'e2e', NULL,
   'A faixa salarial orienta admissão e enquadramento. O formulário precisa capturá-la.',
   'Formulário de cargo aberto.',
   '[{"ordem":1,"acao":"Preencher a faixa salarial (mínimo e máximo)","resultado_esperado":"Os campos aceitam os valores em R$"}]'::jsonb,
   'A faixa salarial é capturada no cadastro.', NULL),

  (v_mod, 'CARGO-TELA-06', 'Busca filtra a lista de cargos',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'A busca é o caminho rápido em listas grandes. Deve recortar a lista pelo termo.',
   'Existirem cargos.',
   '[{"ordem":1,"acao":"Digitar um termo em Buscar cargos","resultado_esperado":"A lista recorta para os que casam"}]'::jsonb,
   'A busca filtra a lista de cargos.', NULL),

  (v_mod, 'CARGO-TELA-07', 'Estado vazio orienta a cadastrar o primeiro',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Sem cargos, a tela precisa orientar a começar — não ficar em branco.',
   'Empresa sem cargos.',
   '[{"ordem":1,"acao":"Abrir a lista sem nenhum cargo","resultado_esperado":"Mostra a mensagem de nenhum cargo cadastrado, sem quebrar"}]'::jsonb,
   'O vazio orienta a cadastrar.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Cargos (tela): antes=%, depois=% (esperado +7)', v_antes, v_depois;
END $doc$;

-- ══════════════════════════════════════════════════════════
-- ESTABELECIMENTOS  (estrutura-organizacional/estabelecimentos) — /cadastros/filiais
-- ══════════════════════════════════════════════════════════
DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'estrutura-organizacional/estabelecimentos';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo estrutura-organizacional/estabelecimentos não encontrado — nada a fazer.'; RETURN; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'ESTAB-TELA-01', 'Selecionar a empresa (matriz) para gerenciar',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'Estabelecimentos e obras pertencem a uma matriz. A tela primeiro pede escolher a empresa — sem ela, não há o que listar.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar /cadastros/filiais","resultado_esperado":"Título Estabelecimento ou Obra; orientação para selecionar a empresa"},
     {"ordem":2,"acao":"Selecionar uma empresa (matriz)","resultado_esperado":"A tela passa a gerenciar os estabelecimentos/obras daquela empresa"}]'::jsonb,
   'A tela pede a empresa antes de gerenciar.', NULL),

  (v_mod, 'ESTAB-TELA-02', 'Listar estabelecimentos e obras da empresa',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'Escolhida a empresa, a lista mostra estabelecimentos e obras. É a base para lotação e para o eSocial (S-1005).',
   'Empresa selecionada.',
   '[{"ordem":1,"acao":"Com a empresa selecionada, conferir a lista","resultado_esperado":"Colunas Nome, Tipo, Localização, Contato e Status; botão Novo Registro; campo de busca"}]'::jsonb,
   'A lista de estabelecimentos e obras monta.', NULL),

  (v_mod, 'ESTAB-TELA-03', 'Abrir o formulário de Novo Registro',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'Cadastrar estabelecimento/obra é o ato central. O formulário precisa abrir com tipo e endereço.',
   'Empresa selecionada.',
   '[{"ordem":1,"acao":"Clicar em Novo Registro","resultado_esperado":"Abre o diálogo Novo Registro com tipo (estabelecimento/obra), endereço e contato"},
     {"ordem":2,"acao":"Fechar sem salvar","resultado_esperado":"Fecha sem criar nada"}]'::jsonb,
   'O formulário de Novo Registro abre e fecha sem efeito.', NULL),

  (v_mod, 'ESTAB-TELA-04', 'Obra pede o CNO',
   'alternativo', 'media', 'aprovado', 'e2e', 'eSocial S-1005 / obrigações de obra (CNO)',
   'Obra tem CNO (Cadastro Nacional de Obras); estabelecimento não. O formulário deve pedir o CNO só quando o tipo é Obra.',
   'Formulário de novo registro aberto.',
   '[{"ordem":1,"acao":"Escolher o tipo Obra","resultado_esperado":"Aparece o campo CNO"},
     {"ordem":2,"acao":"Voltar o tipo para Estabelecimento","resultado_esperado":"O campo CNO deixa de ser exigido"}]'::jsonb,
   'O CNO é pedido apenas para obra.', NULL),

  (v_mod, 'ESTAB-TELA-05', 'Busca filtra estabelecimentos e obras',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'A busca é o caminho rápido na lista da empresa. Deve recortar pelo termo.',
   'Empresa com estabelecimentos/obras.',
   '[{"ordem":1,"acao":"Digitar em Buscar estabelecimentos ou obras","resultado_esperado":"A lista recorta"},
     {"ordem":2,"acao":"Buscar um termo inexistente","resultado_esperado":"Mostra Nenhum registro encontrado"}]'::jsonb,
   'A busca filtra e trata o sem-resultado.', NULL),

  (v_mod, 'ESTAB-TELA-06', 'Estado vazio orienta a cadastrar o primeiro',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Empresa sem estabelecimento precisa orientar a começar — não ficar em branco.',
   'Empresa selecionada sem estabelecimentos/obras.',
   '[{"ordem":1,"acao":"Selecionar uma empresa sem registros","resultado_esperado":"Mostra Nenhum registro cadastrado para esta empresa, sem quebrar"}]'::jsonb,
   'O vazio orienta a cadastrar.', NULL),

  (v_mod, 'ESTAB-TELA-07', 'Busca de empresa por CNPJ',
   'feliz', 'baixa', 'aprovado', 'e2e', NULL,
   'Em quem tem muitas matrizes, achar a empresa por CNPJ é o atalho. Deve filtrar e tratar o sem-resultado.',
   'Rota /cadastros/filiais.',
   '[{"ordem":1,"acao":"Buscar por CNPJ da empresa","resultado_esperado":"A lista de empresas recorta pelo CNPJ"},
     {"ordem":2,"acao":"Buscar um CNPJ inexistente","resultado_esperado":"Mostra Nenhuma empresa (Matriz) encontrada com este CNPJ"}]'::jsonb,
   'A empresa pode ser achada por CNPJ.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Estabelecimentos (tela): antes=%, depois=% (esperado +7)', v_antes, v_depois;
END $doc$;

-- ══════════════════════════════════════════════════════════
-- COMPLIANCE SST  (saude-seguranca/compliance-sst) — /compliance-sst
-- ══════════════════════════════════════════════════════════
DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'saude-seguranca/compliance-sst';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo saude-seguranca/compliance-sst não encontrado — nada a fazer.'; RETURN; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'CSST-TELA-01', 'Módulo abre com o aviso legal e as 7 abas',
   'feliz', 'alta', 'aprovado', 'e2e', 'NR-1 (GRO/PGR); NR-7 (PCMSO)',
   'O módulo orquestra a conformidade de SST. Se não monta, some o painel de governança e os alertas de vencimento.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar /compliance-sst","resultado_esperado":"Título Compliance SST carrega, com o aviso legal em destaque"},
     {"ordem":2,"acao":"Conferir as abas","resultado_esperado":"Importação IA, Documentos, Ordem De Serviço, Painel, Alertas, Ações e eSocial"}]'::jsonb,
   'O módulo monta com o aviso legal e as 7 abas.', NULL),

  (v_mod, 'CSST-TELA-02', 'Importação IA abre',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'A importação por IA lê documentos de SST e extrai o que importa. Deve abrir e degradar sem a chave, sem quebrar.',
   'Aba Importação IA.',
   '[{"ordem":1,"acao":"Abrir a aba Importação IA","resultado_esperado":"A área de importação por IA carrega"},
     {"ordem":2,"acao":"Acionar sem a chave de IA","resultado_esperado":"Mostra aviso claro; a tela não quebra"}]'::jsonb,
   'A Importação IA abre e trata a ausência de chave.', NULL),

  (v_mod, 'CSST-TELA-03', 'Documentos lista (ou vazio) com contador na aba',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'A aba Documentos reúne o que foi importado, com contagem no próprio nome da aba. Vazio orienta.',
   'Aba Documentos.',
   '[{"ordem":1,"acao":"Abrir a aba Documentos","resultado_esperado":"Aparece Documentos Importados; sem nenhum, Nenhum documento ainda"},
     {"ordem":2,"acao":"Conferir o selo da aba quando há documentos","resultado_esperado":"A aba mostra a contagem"}]'::jsonb,
   'A aba Documentos lista com contador e trata o vazio.', NULL),

  (v_mod, 'CSST-TELA-04', 'Ordem De Serviço abre',
   'feliz', 'media', 'aprovado', 'e2e', 'NR-1 (ordem de serviço de segurança)',
   'A ordem de serviço formaliza os riscos e as instruções por função. A aba precisa montar.',
   'Aba Ordem De Serviço.',
   '[{"ordem":1,"acao":"Abrir a aba Ordem De Serviço","resultado_esperado":"O painel de ordem de serviço carrega"}]'::jsonb,
   'A aba Ordem De Serviço abre sem quebrar.', NULL),

  (v_mod, 'CSST-TELA-05', 'Painel resume a conformidade',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'O painel dá a leitura de conformidade de SST — o pulso do módulo.',
   'Aba Painel.',
   '[{"ordem":1,"acao":"Abrir a aba Painel","resultado_esperado":"O painel de conformidade carrega com os indicadores"}]'::jsonb,
   'O Painel resume a conformidade.', NULL),

  (v_mod, 'CSST-TELA-06', 'Alertas mostra vencimentos (ou vazio)',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Documento/exame vencido é risco legal. A aba Alertas destaca os vencimentos; sem nenhum, orienta o vazio.',
   'Aba Alertas.',
   '[{"ordem":1,"acao":"Abrir a aba Alertas","resultado_esperado":"Aparecem os vencimentos; sem nenhum, Nenhum vencimento registrado"}]'::jsonb,
   'Os Alertas mostram vencimentos e tratam o vazio.', NULL),

  (v_mod, 'CSST-TELA-07', 'Ações abre',
   'feliz', 'baixa', 'aprovado', 'e2e', NULL,
   'As ações fecham o ciclo entre alerta e providência. A aba precisa montar.',
   'Aba Ações.',
   '[{"ordem":1,"acao":"Abrir a aba Ações","resultado_esperado":"O painel de ações carrega"}]'::jsonb,
   'A aba Ações abre sem quebrar.', NULL),

  (v_mod, 'CSST-TELA-08', 'eSocial mostra a auditoria de eventos SST',
   'feliz', 'media', 'aprovado', 'e2e', 'eSocial (S-2210, S-2220, S-2240)',
   'A aba eSocial audita os eventos de SST — o que foi (ou não) transmitido. É a coerência com o governo.',
   'Aba eSocial.',
   '[{"ordem":1,"acao":"Abrir a aba eSocial","resultado_esperado":"Aparece a Auditoria eSocial — Eventos SST"}]'::jsonb,
   'A aba eSocial mostra a auditoria de eventos SST.', NULL),

  (v_mod, 'CSST-TELA-09', 'Aviso legal deixa claro o escopo do módulo',
   'alternativo', 'media', 'aprovado', 'e2e', 'NR-1 / NR-7 (documentos por profissional habilitado)',
   'O módulo não substitui profissional habilitado nem elabora PGR/PCMSO/LTCAT. O aviso precisa estar visível para não induzir a erro.',
   'Rota /compliance-sst.',
   '[{"ordem":1,"acao":"Ler o aviso legal no topo","resultado_esperado":"Deixa claro que o módulo não substitui profissionais habilitados nem elabora PGR, PCMSO ou LTCAT — atua como orquestrador e auditor"}]'::jsonb,
   'O aviso legal delimita o escopo do módulo.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Compliance SST (tela): antes=%, depois=% (esperado +9)', v_antes, v_depois;
END $doc$;

-- ── Conferência (última query: é o que o SQL Editor exibe) ──
SELECT m.path AS modulo, count(*) AS casos_tela, min(c.codigo) AS primeiro, max(c.codigo) AS ultimo
FROM public.qa_casos_teste c
JOIN public.qa_modulos m ON m.id = c.modulo_id
WHERE c.codigo LIKE '%-TELA-%'
  AND m.path IN ('estrutura-organizacional/departamentos','estrutura-organizacional/cargos',
                 'estrutura-organizacional/estabelecimentos','saude-seguranca/compliance-sst')
GROUP BY m.path ORDER BY m.path;
