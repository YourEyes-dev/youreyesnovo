-- =========================================================
-- QA — Ergonomia: primeira documentação de casos do módulo (32 casos)
--
-- O módulo Ergonomia (saude-seguranca/ergonomia) estava no catálogo de
-- QA com ZERO casos documentados. Este arquivo abre a família ERGO com
-- casos funcionais de TELA (nivel e2e), derivados de duas fontes:
--   1) o documento de QA "Testes_Ergonomia" (regras do manual: AEP por
--      Situação de Trabalho, Inventário GRO, Motor AET, análise por IA,
--      plano 5W2H, monitoramento/score, documentos RQ-26 e RQ-19/20);
--   2) a TELA REAL (src/pages/Ergonomia.tsx + components/ergonomia/*):
--      7 abas (AEP, Inventário GRO, Prioritários, Ações, Monitoramento,
--      Análise IA, Base Ergonômica), botões "Novo Risco" e "Nova Ação",
--      RiscoForm com Título*, Eixo Ergonômico* (físico/cognitivo/
--      organizacional), Severidade*, Probabilidade* (escala qualitativa),
--      item NR-17 opcional; fluxo de AEP em etapas (identificação,
--      descrição, riscos, psicossocial, ações, assinaturas, síntese,
--      evidências); geração de Documento de Metodologia e Comunicação
--      aos Trabalhadores; radares Burnout/Boreout/Energia.
--
-- Onde o documento de origem descreve regra que a tela pode ainda não
-- impor (ex.: bloqueios), o caso diz "conforme regra implementada" — o
-- teste então DOCUMENTA a expectativa sem inventar comportamento.
--
-- Regra da casa: caso e2e documentado SEM spec só gera aviso na guarda
-- (não reprova). A implementação dos it() vem em levas próprias.
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'saude-seguranca/ergonomia';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo saude-seguranca/ergonomia não encontrado.'; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  -- ══════════ A) TELA E NAVEGAÇÃO ══════════

  (v_mod, 'ERGO-001', 'Tela de Ergonomia abre com as 7 abas do fluxo GRO',
   'feliz', 'alta', 'aprovado', 'e2e',
   'NR-17 (AEP) e NR-01 (GRO)',
   'O módulo organiza o fluxo em abas que espelham as etapas do programa (AEP → Inventário → Prioritários → Ações → Monitoramento → IA → Base). Se uma aba não monta, uma etapa inteira do programa fica inacessível.',
   'Usuário autenticado com acesso ao módulo de Ergonomia.',
   '[{"ordem":1,"acao":"Acessar o módulo de Ergonomia pelo menu","resultado_esperado":"A tela carrega sem erro"},
     {"ordem":2,"acao":"Conferir as abas exibidas","resultado_esperado":"AEP, Inventário GRO, Prioritários, Ações, Monitoramento, Análise IA e Base Ergonômica visíveis"},
     {"ordem":3,"acao":"Clicar em cada aba","resultado_esperado":"Cada aba monta seu conteúdo sem tela quebrada"}]'::jsonb,
   'As 7 abas do fluxo abrem e renderizam conteúdo.',
   'Âncoras estáveis: ids tab-ergo-aep, tab-ergo-inventario, tab-ergo-prioritarios, tab-ergo-acoes, tab-ergo-monitoramento, tab-ergo-analise-ia, tab-ergo-base.'),

  (v_mod, 'ERGO-002', 'Guia Rápido abre e fecha sem afetar a tela',
   'alternativo', 'baixa', 'aprovado', 'e2e',
   NULL,
   'O Guia Rápido é a porta de entrada didática do módulo. Abrir e fechar não pode travar a navegação (scroll-lock preso é defeito recorrente de dialogs).',
   'Tela de Ergonomia aberta.',
   '[{"ordem":1,"acao":"Clicar em Guia Rápido","resultado_esperado":"O guia abre em modal"},
     {"ordem":2,"acao":"Fechar o guia","resultado_esperado":"Modal fecha e a tela continua clicável"}]'::jsonb,
   'Guia abre e fecha; tela permanece operável.',
   'Âncora: id btn-ergo-guia-rapido.'),

  -- ══════════ B) INVENTÁRIO GRO — CADASTRO DE RISCO ══════════

  (v_mod, 'ERGO-010', 'Cadastrar risco ergonômico com os campos obrigatórios',
   'feliz', 'critica', 'aprovado', 'e2e',
   'NR-01 (inventário de riscos do GRO)',
   'O Inventário GRO é o coração do módulo: cada risco nasce com título, eixo ergonômico, severidade e probabilidade. Sem cadastro funcionando, não há inventário, não há priorização e não há PGR.',
   'Tela de Ergonomia aberta; botão Novo Risco disponível.',
   '[{"ordem":1,"acao":"Clicar em Novo Risco","resultado_esperado":"Formulário de risco abre"},
     {"ordem":2,"acao":"Preencher Título, Eixo Ergonômico, Severidade e Probabilidade","resultado_esperado":"Campos aceitam os valores"},
     {"ordem":3,"acao":"Salvar","resultado_esperado":"Risco criado aparece no Inventário GRO"}]'::jsonb,
   'O risco é criado e listado no inventário com os dados informados.',
   'Âncora: id btn-ergo-novo-risco. Severidade/probabilidade na tela são qualitativas (baixo/médio/alto), não a matriz numérica 1-25 do manual — o caso valida o que a tela oferece.'),

  (v_mod, 'ERGO-011', 'Bloquear cadastro de risco sem título',
   'negativo', 'alta', 'aprovado', 'e2e',
   NULL,
   'Título é o identificador humano do risco no inventário e nos documentos gerados. Risco sem título vira linha ilegível no PGR.',
   'Formulário de Novo Risco aberto.',
   '[{"ordem":1,"acao":"Deixar o Título em branco e preencher o resto","resultado_esperado":"—"},
     {"ordem":2,"acao":"Tentar salvar","resultado_esperado":"Sistema impede o salvamento e indica o campo obrigatório"}]'::jsonb,
   'O risco não é criado; a validação aponta o título.',
   NULL),

  (v_mod, 'ERGO-012', 'Eixo ergonômico classifica o risco (físico, cognitivo, organizacional)',
   'feliz', 'alta', 'aprovado', 'e2e',
   'NR-17 e ISO 45003 (fatores físicos, cognitivos e organizacionais)',
   'O módulo trabalha com três eixos e a tela filtra o inventário por eles. Um risco no eixo errado sai do radar do filtro e das análises por categoria.',
   'Pelo menos um risco cadastrado em cada eixo (criar durante o teste).',
   '[{"ordem":1,"acao":"Cadastrar um risco no eixo físico, um no cognitivo e um no organizacional","resultado_esperado":"Os três são criados"},
     {"ordem":2,"acao":"Usar os filtros de eixo do inventário (Todos, Físico, Cognitivo, Organizacional)","resultado_esperado":"Cada filtro mostra apenas os riscos do eixo correspondente"}]'::jsonb,
   'Os filtros de eixo segmentam o inventário corretamente.',
   NULL),

  (v_mod, 'ERGO-013', 'Vincular risco a item do checklist NR-17 (opcional)',
   'alternativo', 'media', 'aprovado', 'e2e',
   'NR-17',
   'O vínculo com o item NR-17 dá rastreabilidade normativa ao risco. É opcional no formulário — mas quando informado, precisa ficar gravado e visível.',
   'Formulário de Novo Risco aberto.',
   '[{"ordem":1,"acao":"Cadastrar risco selecionando um item NR-17 no campo Vinculado ao Item NR-17","resultado_esperado":"Risco salvo"},
     {"ordem":2,"acao":"Abrir o detalhe do risco","resultado_esperado":"O item NR-17 vinculado aparece"}]'::jsonb,
   'O vínculo normativo é persistido e exibido.',
   NULL),

  (v_mod, 'ERGO-014', 'Severidade e probabilidade compõem a criticidade exibida do risco',
   'feliz', 'critica', 'aprovado', 'e2e',
   'NR-01 (gradação de riscos)',
   'A combinação severidade × probabilidade define a criticidade que ordena todo o resto (prioritários, prazos, bloqueios). O usuário precisa VER a classificação resultante no card do risco.',
   'Formulário de Novo Risco disponível.',
   '[{"ordem":1,"acao":"Cadastrar risco com severidade alta e probabilidade alta","resultado_esperado":"Risco criado"},
     {"ordem":2,"acao":"Cadastrar risco com severidade baixa e probabilidade baixa","resultado_esperado":"Risco criado"},
     {"ordem":3,"acao":"Comparar a classificação exibida nos dois cards","resultado_esperado":"O primeiro aparece com criticidade claramente maior que o segundo"}]'::jsonb,
   'A criticidade exibida reflete o par severidade × probabilidade.',
   'O manual descreve matriz 1-25 com faixas Baixo/Moderado/Alto/Crítico; a tela expressa o mesmo conceito em escala qualitativa.'),

  (v_mod, 'ERGO-015', 'Risco de alta criticidade aparece na aba Prioritários',
   'feliz', 'critica', 'aprovado', 'e2e',
   'NR-01 (priorização por nível de risco)',
   'A aba Prioritários é a fila de trabalho do gestor. Se um risco crítico não sobe para ela, a priorização do programa falha em silêncio.',
   'Um risco de alta criticidade cadastrado (criar durante o teste).',
   '[{"ordem":1,"acao":"Cadastrar risco com severidade e probabilidade máximas","resultado_esperado":"Risco criado"},
     {"ordem":2,"acao":"Abrir a aba Prioritários","resultado_esperado":"O risco recém-criado está listado"}]'::jsonb,
   'O risco crítico é promovido à fila de prioritários.',
   NULL),

  (v_mod, 'ERGO-016', 'Duplo clique no salvar não cria risco duplicado',
   'negativo', 'media', 'aprovado', 'e2e',
   NULL,
   'Duplo clique é o jeito mais comum de duplicar registro em formulário. Inventário com risco duplicado infla contagens, score e documentos gerados.',
   'Formulário de Novo Risco preenchido.',
   '[{"ordem":1,"acao":"Clicar duas vezes rapidamente em salvar","resultado_esperado":"Apenas um risco é criado"},
     {"ordem":2,"acao":"Conferir o inventário","resultado_esperado":"Sem duplicata do mesmo título"}]'::jsonb,
   'Um clique duplo produz um único registro.',
   NULL),

  -- ══════════ C) AÇÕES (5W2H) ══════════

  (v_mod, 'ERGO-020', 'Criar ação vinculada a um risco do inventário',
   'feliz', 'critica', 'aprovado', 'e2e',
   'NR-01 (plano de ação do GRO)',
   'Risco sem ação é diagnóstico sem tratamento. A tela tem botão Nova Ação; a ação nasce vinculada ao risco e aparece na aba Ações.',
   'Pelo menos um risco cadastrado.',
   '[{"ordem":1,"acao":"Clicar em Nova Ação","resultado_esperado":"Formulário de ação abre"},
     {"ordem":2,"acao":"Preencher a ação e vincular ao risco","resultado_esperado":"Campos aceitos"},
     {"ordem":3,"acao":"Salvar e abrir a aba Ações","resultado_esperado":"A ação aparece listada, vinculada ao risco"}]'::jsonb,
   'A ação é criada e listada com o vínculo ao risco de origem.',
   'Âncora: id btn-ergo-nova-acao.'),

  (v_mod, 'ERGO-021', 'Responsável é exigido na ação',
   'negativo', 'alta', 'aprovado', 'e2e',
   'Modelo 5W2H (Who)',
   'Ação sem dono não anda. O 5W2H exige responsável nominal; o formulário deve impedir ação sem responsável, conforme regra implementada.',
   'Formulário de Nova Ação aberto.',
   '[{"ordem":1,"acao":"Preencher a ação deixando o responsável em branco","resultado_esperado":"—"},
     {"ordem":2,"acao":"Tentar salvar","resultado_esperado":"Sistema impede ou sinaliza a ausência de responsável"}]'::jsonb,
   'A ação não é salva sem responsável (ou a pendência fica sinalizada).',
   NULL),

  (v_mod, 'ERGO-022', 'Atualizar progresso da ação até a conclusão',
   'feliz', 'alta', 'aprovado', 'e2e',
   NULL,
   'O progresso (0 a 100%) alimenta o monitoramento e o ciclo PDCA. Atualizações precisam persistir e refletir na lista.',
   'Uma ação criada.',
   '[{"ordem":1,"acao":"Abrir a ação e atualizar o progresso para um valor intermediário","resultado_esperado":"Valor salvo e exibido"},
     {"ordem":2,"acao":"Atualizar para 100% / concluída","resultado_esperado":"Ação passa a constar como concluída"}]'::jsonb,
   'O progresso persiste em cada atualização e a conclusão muda o estado da ação.',
   NULL),

  (v_mod, 'ERGO-023', 'Ação vencida é sinalizada no monitoramento',
   'alternativo', 'alta', 'aprovado', 'e2e',
   NULL,
   'Prazo estourado sem sinalização é como não ter prazo. O monitoramento deve destacar ações atrasadas, conforme regra implementada.',
   'Uma ação com prazo no passado (criar com data retroativa, se a tela permitir).',
   '[{"ordem":1,"acao":"Criar ou localizar ação com prazo vencido","resultado_esperado":"—"},
     {"ordem":2,"acao":"Abrir a aba Monitoramento","resultado_esperado":"A ação aparece sinalizada como atrasada"}]'::jsonb,
   'O atraso fica visível no monitoramento.',
   NULL),

  (v_mod, 'ERGO-024', 'Encerramento de risco crítico sem ação vinculada é impedido ou sinalizado',
   'negativo', 'critica', 'aprovado', 'e2e',
   'NR-01 (tratamento obrigatório de riscos graves)',
   'A regra de ouro do manual: risco alto/crítico não se encerra sem plano de ação. Se a tela permitir encerrar em silêncio, o programa perde a prova de tratamento.',
   'Um risco crítico cadastrado, sem ação vinculada.',
   '[{"ordem":1,"acao":"Tentar encerrar/arquivar o risco crítico sem nenhuma ação vinculada","resultado_esperado":"Sistema bloqueia ou exibe sinalização de pendência, conforme regra implementada"},
     {"ordem":2,"acao":"Vincular uma ação e tentar de novo","resultado_esperado":"Encerramento passa a ser permitido"}]'::jsonb,
   'Não há encerramento silencioso de risco grave sem tratamento.',
   'Espelha TELA-PSICO-024/025, que validam a mesma regra no módulo Psicossocial.'),

  -- ══════════ D) AEP — AVALIAÇÃO ERGONÔMICA PRELIMINAR ══════════

  (v_mod, 'ERGO-030', 'Iniciar AEP por Situação de Trabalho (setor + função)',
   'feliz', 'critica', 'aprovado', 'e2e',
   'NR-17 item 17.3 (AEP por situação de trabalho)',
   'A AEP nasce da Situação de Trabalho — o par setor + função —, nunca de forma genérica por empresa. É a unidade de análise que dá valor técnico ao documento.',
   'Aba AEP acessível.',
   '[{"ordem":1,"acao":"Abrir a aba AEP e iniciar uma nova avaliação","resultado_esperado":"Fluxo de AEP abre na etapa de identificação"},
     {"ordem":2,"acao":"Informar setor e função/posto","resultado_esperado":"A situação de trabalho fica registrada como unidade da análise"}]'::jsonb,
   'A AEP é criada ancorada em setor + função.',
   NULL),

  (v_mod, 'ERGO-031', 'AEP registra a descrição do trabalho real',
   'feliz', 'alta', 'aprovado', 'e2e',
   'NR-17 (análise do trabalho real, não só do prescrito)',
   'A AEP documenta o trabalho COMO ELE É — posturas, ferramentas, variabilidade — e não só o descrito no papel do cargo. A etapa de descrição precisa aceitar e persistir esse conteúdo.',
   'Uma AEP iniciada.',
   '[{"ordem":1,"acao":"Avançar até a etapa de descrição","resultado_esperado":"Campos de descrição do trabalho disponíveis"},
     {"ordem":2,"acao":"Preencher a descrição do trabalho real e salvar","resultado_esperado":"Conteúdo persistido ao navegar entre etapas"}]'::jsonb,
   'A descrição do trabalho real fica gravada na AEP.',
   NULL),

  (v_mod, 'ERGO-032', 'AEP integra a dimensão psicossocial na avaliação',
   'alternativo', 'alta', 'aprovado', 'e2e',
   'ISO 45003 (riscos psicossociais)',
   'O fluxo da AEP tem etapa psicossocial — é a ponte ergo + psico do manual. A etapa deve montar e aceitar registro.',
   'Uma AEP em preenchimento.',
   '[{"ordem":1,"acao":"Avançar até a etapa psicossocial da AEP","resultado_esperado":"A seção monta sem erro"},
     {"ordem":2,"acao":"Registrar os fatores pedidos e salvar","resultado_esperado":"Dados persistidos na AEP"}]'::jsonb,
   'A etapa psicossocial funciona dentro do fluxo da AEP.',
   NULL),

  (v_mod, 'ERGO-033', 'AEP anexa evidências (fotos e arquivos)',
   'alternativo', 'media', 'aprovado', 'e2e',
   NULL,
   'Evidência visual é o que sustenta a AEP em auditoria. O fluxo tem etapa de evidências; upload precisa funcionar e listar o que foi anexado.',
   'Uma AEP em preenchimento; arquivo de imagem válido disponível.',
   '[{"ordem":1,"acao":"Na etapa de evidências, anexar uma imagem válida","resultado_esperado":"Upload conclui e a evidência aparece na lista"},
     {"ordem":2,"acao":"Salvar e reabrir a AEP","resultado_esperado":"A evidência continua listada"}]'::jsonb,
   'Evidências são anexadas e persistem na AEP.',
   NULL),

  (v_mod, 'ERGO-034', 'AEP fecha com síntese e assinaturas',
   'alternativo', 'alta', 'aprovado', 'e2e',
   'NR-17 (documentação da avaliação)',
   'A AEP termina em síntese conclusiva e assinaturas — é o que a transforma em documento. As etapas finais devem montar e concluir o fluxo.',
   'Uma AEP preenchida até as etapas finais.',
   '[{"ordem":1,"acao":"Preencher a síntese conclusiva","resultado_esperado":"Conteúdo aceito"},
     {"ordem":2,"acao":"Registrar assinaturas e concluir","resultado_esperado":"AEP concluída sem erro e disponível para consulta/geração de documento"}]'::jsonb,
   'O fluxo da AEP conclui gerando um documento consultável.',
   NULL),

  -- ══════════ E) ANÁLISE POR IA ══════════

  (v_mod, 'ERGO-040', 'Análise por IA a partir de descrição textual do posto',
   'feliz', 'alta', 'aprovado', 'e2e',
   NULL,
   'A análise por IA é o atalho de triagem: descreve-se o posto e o sistema devolve riscos classificados e recomendações. O resultado deve chegar legível na tela.',
   'Aba Análise IA acessível; chave de IA configurada no ambiente de teste.',
   '[{"ordem":1,"acao":"Abrir a aba Análise IA e informar uma descrição detalhada de posto","resultado_esperado":"Campo aceita o texto"},
     {"ordem":2,"acao":"Enviar a análise","resultado_esperado":"Sistema retorna riscos identificados, classificação e recomendações"}]'::jsonb,
   'A análise retorna diagnóstico estruturado a partir do texto.',
   'Sem a chave de IA no ambiente, a função responde com aviso claro — o caso então valida o AVISO, não o diagnóstico.'),

  (v_mod, 'ERGO-041', 'Resultado da análise por IA vai para a Base Ergonômica',
   'feliz', 'media', 'aprovado', 'e2e',
   NULL,
   'A análise que não é arquivada se perde. O resultado da IA deve ficar consultável na aba Base Ergonômica.',
   'Uma análise por IA executada com sucesso.',
   '[{"ordem":1,"acao":"Executar uma análise por IA","resultado_esperado":"Resultado exibido"},
     {"ordem":2,"acao":"Abrir a aba Base Ergonômica","resultado_esperado":"O resultado da análise está salvo e consultável"}]'::jsonb,
   'A Base Ergonômica guarda o histórico das análises.',
   NULL),

  (v_mod, 'ERGO-042', 'Upload inválido na análise por IA é tratado com mensagem',
   'negativo', 'media', 'aprovado', 'e2e',
   NULL,
   'Arquivo de tipo errado ou grande demais não pode quebrar o fluxo: a tela deve recusar com mensagem e continuar utilizável.',
   'Aba Análise IA acessível; arquivo não-imagem disponível.',
   '[{"ordem":1,"acao":"Tentar enviar um arquivo de formato não suportado","resultado_esperado":"Sistema recusa e informa os formatos aceitos"},
     {"ordem":2,"acao":"Continuar usando a aba","resultado_esperado":"Fluxo permanece operável"}]'::jsonb,
   'A recusa é clara e não corrompe o fluxo.',
   NULL),

  -- ══════════ F) DOCUMENTOS DE CONFORMIDADE ══════════

  (v_mod, 'ERGO-050', 'Gerar o Documento de Metodologia a partir do inventário',
   'feliz', 'alta', 'aprovado', 'e2e',
   'NR-01/NR-17 (documentação do programa — RQ-26)',
   'O Documento de Metodologia é a evidência formal do programa ergonômico. Deve ser gerado a partir dos dados reais do inventário, sem retrabalho manual.',
   'Inventário com riscos cadastrados.',
   '[{"ordem":1,"acao":"Acessar a geração do Documento de Metodologia","resultado_esperado":"Fluxo de geração abre"},
     {"ordem":2,"acao":"Gerar o documento","resultado_esperado":"Documento produzido com os dados do inventário, sem erro"}]'::jsonb,
   'O documento de metodologia é gerado com o conteúdo do inventário.',
   'Componente DocumentoMetodologia (RQ-26 no vocabulário do manual).'),

  (v_mod, 'ERGO-051', 'Gerar a Comunicação aos Trabalhadores',
   'feliz', 'alta', 'aprovado', 'e2e',
   'NR-01 (comunicação de riscos aos trabalhadores — RQ-19/20)',
   'A comunicação formal dos riscos aos trabalhadores é exigência do GRO. O sistema gera o documento com base nos riscos registrados.',
   'Inventário com riscos cadastrados.',
   '[{"ordem":1,"acao":"Acessar a geração da Comunicação aos Trabalhadores","resultado_esperado":"Fluxo abre"},
     {"ordem":2,"acao":"Gerar o documento","resultado_esperado":"Documento produzido com os riscos registrados"}]'::jsonb,
   'A comunicação é gerada a partir do inventário.',
   'Componente ComunicacaoTrabalhadores (RQ-19/20 no vocabulário do manual).'),

  (v_mod, 'ERGO-052', 'Exportar relatório de ergonomia em PDF',
   'feliz', 'media', 'aprovado', 'e2e',
   NULL,
   'O PDF é o formato que circula (auditoria, cliente, arquivo). A exportação deve concluir e produzir arquivo legível com acentuação correta.',
   'Dados no módulo (riscos e/ou AEP).',
   '[{"ordem":1,"acao":"Acionar a exportação de relatório","resultado_esperado":"Geração conclui sem erro"},
     {"ordem":2,"acao":"Abrir o arquivo gerado","resultado_esperado":"Conteúdo legível e coerente com os dados cadastrados"}]'::jsonb,
   'O relatório em PDF sai íntegro.',
   NULL),

  (v_mod, 'ERGO-053', 'Gerar documento com inventário vazio não quebra',
   'negativo', 'media', 'aprovado', 'e2e',
   NULL,
   'Ambiente novo tem inventário vazio. A geração deve bloquear com mensagem clara ou produzir documento vazio controlado — nunca erro cru.',
   'Tenant/empresa sem riscos cadastrados (ou filtro que resulte em vazio).',
   '[{"ordem":1,"acao":"Tentar gerar documento sem riscos no inventário","resultado_esperado":"Mensagem clara ou documento vazio controlado, conforme regra implementada"}]'::jsonb,
   'Sem dados não há erro cru — há tratamento.',
   NULL),

  -- ══════════ G) MONITORAMENTO E PAINEL ══════════

  (v_mod, 'ERGO-060', 'Monitoramento exibe o ciclo PDCA dos riscos',
   'feliz', 'alta', 'aprovado', 'e2e',
   'NR-01 (melhoria contínua do GRO)',
   'O ciclo PDCA mostra em que fase cada risco está (identificado, em execução, verificação, encerrado). É o painel de governança do programa.',
   'Riscos e ações cadastrados em estados variados.',
   '[{"ordem":1,"acao":"Abrir a aba Monitoramento","resultado_esperado":"Painel PDCA monta"},
     {"ordem":2,"acao":"Conferir as fases exibidas contra os riscos cadastrados","resultado_esperado":"Distribuição coerente com os estados reais"}]'::jsonb,
   'O PDCA reflete o estado real do inventário.',
   'Componente GROCicloPDCA.'),

  (v_mod, 'ERGO-061', 'Cards de estatísticas refletem o inventário',
   'feliz', 'media', 'aprovado', 'e2e',
   NULL,
   'Os cards do topo são a leitura de 5 segundos do gestor. Números que não batem com o inventário corroem a confiança no módulo inteiro.',
   'Inventário com riscos em estados variados.',
   '[{"ordem":1,"acao":"Cadastrar riscos com criticidades diferentes","resultado_esperado":"—"},
     {"ordem":2,"acao":"Conferir os cards de estatísticas","resultado_esperado":"Contagens coerentes com o que foi cadastrado"}]'::jsonb,
   'Estatísticas do painel batem com os registros.',
   'Componente ErgonomiaStats.'),

  (v_mod, 'ERGO-062', 'Radares (Burnout, Boreout, Energia) montam com os dados disponíveis',
   'alternativo', 'media', 'aprovado', 'e2e',
   'ISO 45003',
   'Os radares traduzem a dimensão psicossocial-cognitiva em visual. Devem montar sem erro com dados e mostrar estado vazio digno sem dados.',
   'Tela de Ergonomia aberta.',
   '[{"ordem":1,"acao":"Abrir a seção de radares","resultado_esperado":"Radares montam (com dados ou em estado vazio controlado)"},
     {"ordem":2,"acao":"Abrir o detalhe de um radar","resultado_esperado":"Modal de detalhe abre e fecha sem travar"}]'::jsonb,
   'Radares renderizam nos dois estados (com e sem dados).',
   NULL),

  -- ══════════ H) INTEGRAÇÕES ══════════

  (v_mod, 'ERGO-070', 'Ação de ergonomia aparece no Plano de Ação global',
   'feliz', 'alta', 'aprovado', 'e2e',
   NULL,
   'O módulo não é ilha: ações criadas aqui compõem o Plano de Ação global da empresa, com vínculo de origem preservado.',
   'Uma ação criada no módulo de Ergonomia.',
   '[{"ordem":1,"acao":"Criar ação no módulo de Ergonomia","resultado_esperado":"Ação criada"},
     {"ordem":2,"acao":"Abrir o módulo Plano de Ação","resultado_esperado":"A ação aparece com vínculo/origem de Ergonomia"}]'::jsonb,
   'A integração com o Plano de Ação global funciona de ponta a ponta.',
   'Espelho do lado Ergonomia do que CT-IA-036 valida para Incidentes.'),

  (v_mod, 'ERGO-071', 'Dados psicossociais alimentam a leitura ergonômica',
   'alternativo', 'media', 'aprovado', 'e2e',
   'ISO 45003 / NR-17 (análise integrada)',
   'Campanhas psicossociais críticas devem enriquecer a análise ergonômica (AEP e recomendações). Do lado do Psicossocial isso já é testado (TELA-PSICO-030); aqui valida-se o lado consumidor.',
   'Campanha psicossocial com resultados no ambiente de teste.',
   '[{"ordem":1,"acao":"Abrir a Ergonomia com dados psicossociais existentes no ambiente","resultado_esperado":"Seções que consomem psicossocial (AEP/integração cognitiva) montam com os dados"},
     {"ordem":2,"acao":"Conferir ausência de erro quando NÃO há dados psicossociais","resultado_esperado":"Estado vazio tratado"}]'::jsonb,
   'A integração psico → ergo funciona nos dois estados.',
   'Componente IntegracaoCognitiva.'),

  (v_mod, 'ERGO-072', 'Estado vazio do módulo é digno (primeiro acesso)',
   'alternativo', 'media', 'aprovado', 'e2e',
   NULL,
   'Empresa recém-criada abre o módulo sem nenhum dado. Cada aba deve mostrar estado vazio orientativo — não spinner eterno nem tela quebrada.',
   'Empresa/tenant sem dados de ergonomia.',
   '[{"ordem":1,"acao":"Abrir cada aba do módulo sem dados cadastrados","resultado_esperado":"Estados vazios com orientação de próximo passo; sem erro"}]'::jsonb,
   'Todas as abas tratam o estado vazio.',
   'Componente EmptyState.')

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Ergonomia: casos antes=%, depois=% (esperado +32 na primeira execução)', v_antes, v_depois;
END $doc$;
