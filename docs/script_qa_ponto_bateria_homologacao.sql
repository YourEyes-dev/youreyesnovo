-- =========================================================
-- ENTREGA QA — Bateria de Homologação do Ponto (31 casos, lado de tela)
--
-- Cole este arquivo inteiro no SQL Editor do ambiente de HOMOLOGACAO
-- (projeto fgsblefvdabgdouipigz). Documenta, no módulo jornada-rotina/ponto,
-- os 31 casos do roteiro de homologação do Ponto (o testador segue A1..I3 na
-- tela). Códigos PONTO-HOM-<familia><n> preservam os rótulos A1..I3.
--   28 casos de tela (nivel e2e) + 3 de banco (nivel api: C1, C2, F2).
-- Complementa as sondas de motor PONTO-4xx (mesma matéria, nivel api).
--
-- Só INSERE linhas em qa_casos_teste — não cria nem altera estrutura, então
-- não mexe na fidelidade com a producao. Idempotente: ON CONFLICT DO NOTHING.
-- Procura o modulo pelo path; se nao achar, avisa e sai sem abortar (RAISE
-- NOTICE + RETURN dentro do IF). Roda inteiro em UMA transacao — sem tabela
-- temporaria. Ao final, uma unica conferencia SELECT lista o registrado.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'jornada-rotina/ponto';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo jornada-rotina/ponto não encontrado — nada a fazer.'; RETURN; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  -- ══════════ A. INTERVALO PRÉ-ASSINALADO ══════════

  (v_mod, 'PONTO-HOM-A1', 'Cadastrar a declaração de intervalo pré-assinalado',
   'feliz', 'alta', 'aprovado', 'e2e',
   'Súmula 338, III, do TST; CLT art. 74, §2º',
   'A declaração formal do intervalo de quem bate só entrada e saída. Sem ela, o dia de duas batidas aparece como intervalo suprimido.',
   'Usuário RH/gestor; uma escala com colaboradores no ambiente de teste.',
   '[{"ordem":1,"acao":"Em Ponto › Configurações › Intervalo pré-assinalado, clicar em Nova declaração","resultado_esperado":"O formulário abre"},
     {"ordem":2,"acao":"Alcance Escala inteira (escala com colaboradores); intervalo 60 min; janela 12:00 às 13:00","resultado_esperado":"Campos aceitos"},
     {"ordem":3,"acao":"Vigência com início anterior ao dia do espelho; lastro CCT 2026/2027 cláusula 12ª; Salvar","resultado_esperado":"A declaração aparece na lista com alcance Escala, 60 min, janela 12:00 — 13:00, vigência e situação Ativa"}]'::jsonb,
   'A declaração de intervalo é cadastrada e fica Ativa na lista.',
   'Bateria de Homologação do Ponto, caso A1. Onde: Ponto › Configurações › Intervalo pré-assinalado.'),

  (v_mod, 'PONTO-HOM-A2', 'Aviso quando o intervalo declarado é menor que o mínimo legal',
   'alternativo', 'media', 'aprovado', 'e2e',
   'CLT art. 71 (intervalo mínimo de 1h para jornada acima de 6h)',
   'Declarar menos que o mínimo deve avisar, sem bloquear — a diferença segue contando como intervalo suprimido. O aviso informa, não impede salvar.',
   'Uma escala com jornada acima de 6 horas.',
   '[{"ordem":1,"acao":"Abrir Nova declaração e escolher uma escala com jornada acima de 6 horas","resultado_esperado":"Formulário aberto"},
     {"ordem":2,"acao":"Digitar 30 no campo de minutos","resultado_esperado":"Surge o aviso âmbar de que a jornada exige no mínimo 60 minutos (art. 71 da CLT) e que a diferença continua contando como intervalo suprimido; o sistema deixa salvar"}]'::jsonb,
   'O aviso de mínimo legal informa mas não bloqueia o salvamento.',
   'Bateria de Homologação do Ponto, caso A2. Onde: mesma tela, no formulário.'),

  (v_mod, 'PONTO-HOM-A3', 'Selo do intervalo pré-assinalado no espelho',
   'feliz', 'alta', 'aprovado', 'e2e',
   'Súmula 338, III, do TST',
   'No espelho, o dia batido só com entrada e saída de quem tem declaração vigente recebe o selo do intervalo pré-assinalado.',
   'Declaração do A1 vigente; um dia apurado DEPOIS do cadastro, com colaborador da escala batendo só entrada e saída.',
   '[{"ordem":1,"acao":"Em Ponto › Espelho, escolher um dia em que o colaborador bateu só entrada e saída (sem almoço)","resultado_esperado":"A linha do dia fica visível"},
     {"ordem":2,"acao":"Olhar a linha junto das marcações","resultado_esperado":"Aparece o selo azul INTERVALO PRÉ-ASSINALADO · 1h; o tooltip explica a origem e onde se cadastra"}]'::jsonb,
   'O selo azul de 1h aparece no dia, com explicação no tooltip.',
   'Bateria de Homologação do Ponto, caso A3. Onde: Ponto › Espelho. Atenção: se o dia foi apurado ANTES do cadastro, o selo só aparece após reconsolidar o dia — prefira um dia apurado depois do cadastro.'),

  (v_mod, 'PONTO-HOM-A4', 'Cartão de ponto e planilha declaram o intervalo',
   'feliz', 'media', 'aprovado', 'e2e',
   'CLT art. 74, §2º; Portaria MTP 671/2021',
   'Os relatórios oficiais precisam declarar o intervalo pré-assinalado — no PDF do cartão de ponto e na planilha do espelho.',
   'Dia do A3 disponível na competência.',
   '[{"ordem":1,"acao":"Em Ponto › Apuração › Relatórios, gerar o Cartão de ponto (PDF) na competência do dia do A3","resultado_esperado":"O PDF é gerado; o dia traz a linha Interv. pré-assinalado 1h (P) junto das marcações, e a legenda do rodapé explica a sigla (P)"},
     {"ordem":2,"acao":"Gerar o Espelho em planilha (Excel)","resultado_esperado":"A aba dia a dia tem a coluna Intervalo pré-assinalado (min) preenchida naquele dia"}]'::jsonb,
   'PDF e planilha declaram o intervalo pré-assinalado do dia.',
   'Bateria de Homologação do Ponto, caso A4. Onde: Ponto › Apuração › Relatórios.'),

  -- ══════════ B. PORTÃO DO FECHAMENTO ══════════

  (v_mod, 'PONTO-HOM-B1', 'Fechamento bloqueado com pendência aberta',
   'negativo', 'critica', 'aprovado', 'e2e',
   'Súmula 338 do TST (ciência do espelho); CLT art. 74',
   'A competência não pode fechar por cima de pendência: ajuste esperando aprovação, dia incompleto ou espelho sem ciência do colaborador. Fechar por cima destrói a prova que a súmula exige.',
   'Competência com ao menos um ajuste aguardando aprovação (ou um espelho sem confirmação).',
   '[{"ordem":1,"acao":"Garantir na competência ao menos um ajuste de ponto aguardando aprovação (crie um em Ajustes, se preciso) ou um espelho sem ciência","resultado_esperado":"Pendência existente"},
     {"ordem":2,"acao":"Em Ponto › Apuração › Fechamento, abrir a competência preparada","resultado_esperado":"Aparece o cartão âmbar Pendências que impedem o fechamento (N), listando colaborador, tipo e dia"},
     {"ordem":3,"acao":"Clicar em Fechar Período","resultado_esperado":"No diálogo o resumo se repete e o botão fica Bloqueado por pendências, desabilitado; nada é gravado"}]'::jsonb,
   'O fechamento fica bloqueado enquanto houver pendência; nada é gravado.',
   'Bateria de Homologação do Ponto, caso B1. Onde: Ponto › Apuração › Fechamento. Risco alto.'),

  (v_mod, 'PONTO-HOM-B2', 'Tratada a pendência, o fechamento libera',
   'feliz', 'alta', 'aprovado', 'e2e',
   'Súmula 338 do TST; CLT art. 74',
   'Resolvidas as pendências, o fechamento volta ao normal — a trava é só enquanto há pendência.',
   'Cenário do B1, agora com as pendências tratáveis.',
   '[{"ordem":1,"acao":"Aprovar ou recusar o ajuste pendente e confirmar a ciência dos espelhos apontados","resultado_esperado":"Pendências resolvidas"},
     {"ordem":2,"acao":"Voltar à aba Fechamento e recarregar","resultado_esperado":"O cartão de pendências some; o botão volta a Confirmar Fechamento"},
     {"ordem":3,"acao":"Clicar em Fechar Período e confirmar","resultado_esperado":"A competência fecha normalmente, como antes"}]'::jsonb,
   'Sem pendências, a competência fecha normalmente.',
   'Bateria de Homologação do Ponto, caso B2. Onde: Ponto › Apuração › Fechamento.'),

  -- ══════════ C. VIGILÂNCIAS DIÁRIAS (banco) ══════════

  (v_mod, 'PONTO-HOM-C1', 'O agendamento das vigilâncias existe e a rotina roda',
   'feliz', 'critica', 'aprovado', 'api',
   'Portaria MTP 671/2021 e CLT art. 74 (controle efetivo depende de a rotina rodar)',
   'As oito vigilâncias do ponto precisam rodar agendadas (03:37 UTC), sem erro. Vigilância que não é chamada por nenhum agendamento é alerta que nunca chega.',
   'SQL Editor do projeto de TESTE (bmehdgthciuvdbvutsdv).',
   '[{"ordem":1,"acao":"Rodar SELECT jobname, schedule, active FROM cron.job WHERE jobname = ponto-vigilancias-diarias","resultado_esperado":"Uma linha com horário 37 3 * * * e ativa"},
     {"ordem":2,"acao":"Rodar SELECT * FROM public.ponto_vigilancias_diarias()","resultado_esperado":"Devolve 8 linhas (banco de horas, art. 62, estabelecimento, CCT, formalização de escala, cobertura de turno, certificado e prazo de 48h), com a coluna tenants_com_erro zerada em todas"}]'::jsonb,
   'O job existe e está ativo, e a rotina roda as 8 vigilâncias sem erro.',
   'Bateria de Homologação do Ponto, caso C1 (banco). Onde: SQL Editor · projeto de teste. A coluna alertas pode vir zerada (dados fictícios): o que se confere é que roda sem erro. Sonda de motor correspondente: PONTO-450.'),

  (v_mod, 'PONTO-HOM-C2', 'Rodar as vigilâncias duas vezes não repete o alerta',
   'negativo', 'alta', 'aprovado', 'api',
   'Idempotência aplicada ao dever de vigilância (CLT art. 74; Portaria MTP 671/2021)',
   'A rotina roda de madrugada e pode ser rodada de novo à tarde; a segunda execução não pode duplicar alertas.',
   'Um certificado digital vencendo em 10 dias (caso E1); SQL Editor de teste.',
   '[{"ordem":1,"acao":"Cadastrar um certificado digital vencendo em 10 dias (caso E1)","resultado_esperado":"Cenário de alerta preparado"},
     {"ordem":2,"acao":"Rodar SELECT * FROM public.ponto_vigilancias_diarias() duas vezes seguidas","resultado_esperado":"Na 1ª execução a linha certificado_vencimento traz 1; na 2ª, 0"},
     {"ordem":3,"acao":"Abrir Ponto › Compliance › Alertas CLT","resultado_esperado":"Há um único aviso do certificado, não dois"}]'::jsonb,
   'A segunda execução não cria alerta novo; o painel mostra um único aviso.',
   'Bateria de Homologação do Ponto, caso C2 (banco). Onde: SQL Editor · projeto de teste. Sonda de motor correspondente: PONTO-451.'),

  -- ══════════ D. COMPROVANTE, AEJ E IMPORTAÇÃO DE AFD ══════════

  (v_mod, 'PONTO-HOM-D1', 'Bater ponto emite o comprovante',
   'feliz', 'alta', 'aprovado', 'e2e',
   'Portaria MTP 671/2021 (comprovante de registro é direito do trabalhador)',
   'Cada batida gera um comprovante com número de série do registro (NSR) e assinatura, acessível pelo próprio colaborador.',
   'Colaborador de teste com CPF vinculado à conta.',
   '[{"ordem":1,"acao":"Registrar uma batida para um colaborador de teste","resultado_esperado":"Batida registrada"},
     {"ordem":2,"acao":"Entrar no sistema com esse colaborador e abrir Meu Perfil","resultado_esperado":"O cartão Meus comprovantes de ponto aparece"},
     {"ordem":3,"acao":"No cartão, escolher o período do mês e clicar em Buscar","resultado_esperado":"A batida aparece com data e hora, NSR, empregador e assinatura; o botão Baixar gera o arquivo"}]'::jsonb,
   'O colaborador vê e baixa o próprio comprovante, com NSR e assinatura.',
   'Bateria de Homologação do Ponto, caso D1. Onde: Ponto › registrar ponto · depois Meu Perfil. O cartão só aparece para quem tem CPF vinculado à conta.'),

  (v_mod, 'PONTO-HOM-D2', 'Um colaborador não vê os comprovantes de outro',
   'negativo', 'critica', 'aprovado', 'e2e',
   'LGPD art. 6º (necessidade); Portaria MTP 671/2021',
   'Cada colaborador só pode ver os PRÓPRIOS comprovantes; RH/gestor consulta de terceiros onde precisa. Vazamento entre colegas expõe dado pessoal.',
   'Dois colaboradores (A e B) com batidas.',
   '[{"ordem":1,"acao":"Entrar como colaborador A e conferir que vê os comprovantes dele","resultado_esperado":"Vê os próprios"},
     {"ordem":2,"acao":"Sair e entrar como colaborador B (também com batidas), buscar o mesmo período","resultado_esperado":"Vê apenas os próprios; nenhuma linha do colega aparece"},
     {"ordem":3,"acao":"Entrar como usuário de RH ou gestor","resultado_esperado":"Continua conseguindo consultar de terceiros onde precisa"}]'::jsonb,
   'O isolamento é garantido: ninguém vê o comprovante do outro; RH/gestor mantém o alcance legítimo.',
   'Bateria de Homologação do Ponto, caso D2. Onde: Meu Perfil · com dois usuários. Risco alto — é a razão do script de banco nº 54; se falhar, NÃO publicar as telas em produção (avise antes).'),

  (v_mod, 'PONTO-HOM-D3', 'AEJ: arquivo oficial e cópia assinada',
   'feliz', 'alta', 'aprovado', 'e2e',
   'Portaria MTP 671/2021 (Arquivo Eletrônico de Jornada)',
   'O AEJ sai no formato oficial e gera uma cópia arquivada e assinada da competência.',
   'Competência com movimento.',
   '[{"ordem":1,"acao":"Em Ponto › Apuração › Relatórios › AEJ, escolher uma competência com movimento e gerar","resultado_esperado":"O arquivo oficial é baixado; o aviso de sucesso menciona a cópia arquivada e assinada"},
     {"ordem":2,"acao":"Observar o cartão que aparece","resultado_esperado":"Surge o cartão Cópia arquivada e assinada desta competência com data, número de trabalhadores, marcações, registros e a assinatura completa"},
     {"ordem":3,"acao":"Clicar em Baixar cópia tratada","resultado_esperado":"A cópia tratada é baixada"}]'::jsonb,
   'O AEJ oficial e a cópia assinada são gerados e baixáveis.',
   'Bateria de Homologação do Ponto, caso D3. Onde: Ponto › Apuração › Relatórios › AEJ.'),

  (v_mod, 'PONTO-HOM-D4', 'Importar AFD válido',
   'feliz', 'alta', 'aprovado', 'e2e',
   'Portaria MTP 671/2021 (integridade do AFD: CRC, assinatura, sequência de NSR)',
   'A importação de AFD confere CRC, assinatura, sequência de NSR e reimportação antes de gravar as marcações.',
   'Arquivo AFD de teste válido.',
   '[{"ordem":1,"acao":"Em Ponto › Configurações › REP-C, preencher fabricante, modelo e nº de série","resultado_esperado":"O equipamento fica identificado nas batidas"},
     {"ordem":2,"acao":"Selecionar um arquivo AFD de teste e importar","resultado_esperado":"Cartão verde Arquivo aprovado na conferência com os quatro selos em ordem (CRC, assinatura, sequência de NSR, reimportação); o aviso diz quantas marcações foram gravadas; o histórico mostra Aprovado na coluna Conferência"}]'::jsonb,
   'O AFD válido é aprovado nas quatro conferências e gravado.',
   'Bateria de Homologação do Ponto, caso D4. Onde: Ponto › Configurações › REP-C.'),

  (v_mod, 'PONTO-HOM-D5', 'O mesmo arquivo AFD não entra duas vezes',
   'negativo', 'alta', 'aprovado', 'e2e',
   'Portaria MTP 671/2021 (integridade do registro)',
   'Reimportar o mesmo AFD não pode duplicar marcações.',
   'AFD do D4 já importado.',
   '[{"ordem":1,"acao":"Importar exatamente o mesmo arquivo do D4 de novo","resultado_esperado":"O sistema recusa dizendo que o arquivo já foi importado; nenhuma marcação nova é gravada"},
     {"ordem":2,"acao":"Conferir o espelho","resultado_esperado":"As batidas não dobraram"}]'::jsonb,
   'A reimportação é recusada e nada é duplicado.',
   'Bateria de Homologação do Ponto, caso D5. Onde: Ponto › Configurações › REP-C.'),

  (v_mod, 'PONTO-HOM-D6', 'Arquivo AFD adulterado vai para quarentena',
   'negativo', 'critica', 'aprovado', 'e2e',
   'Portaria MTP 671/2021 (sequência de NSR e integridade do arquivo)',
   'AFD com sequência de NSR quebrada (batida removida) deve cair em quarentena, sem gravar nada.',
   'Cópia do AFD do D4.',
   '[{"ordem":1,"acao":"Abrir uma cópia do AFD num editor de texto simples (Bloco de Notas)","resultado_esperado":"Arquivo aberto"},
     {"ordem":2,"acao":"Apagar uma linha do meio do arquivo (quebra a sequência de NSR) e salvar com outro nome","resultado_esperado":"Arquivo alterado"},
     {"ordem":3,"acao":"Importar esse arquivo","resultado_esperado":"Cartão vermelho Arquivo em quarentena — nada foi gravado; o selo da sequência de NSR marca com lacuna; a lista explica o achado. Nenhuma marcação entra"}]'::jsonb,
   'O arquivo adulterado é barrado em quarentena; nenhuma marcação entra.',
   'Bateria de Homologação do Ponto, caso D6. Onde: Ponto › Configurações › REP-C. Risco alto.'),

  -- ══════════ E. CERTIFICADO DIGITAL E DOSSIÊ ══════════

  (v_mod, 'PONTO-HOM-E1', 'Cadastrar certificado e ver o aviso de vencimento',
   'feliz', 'alta', 'aprovado', 'e2e',
   'Portaria MTP 671/2021 (assinatura do AFD/AEJ); ICP-Brasil',
   'Sem certificado vigente, o AFD e o AEJ ficam sem assinatura; o sistema avisa e sinaliza o vencimento.',
   'Ponto › Configurações › Certificado digital.',
   '[{"ordem":1,"acao":"Antes de cadastrar qualquer coisa, olhar o cartão do topo","resultado_esperado":"Avisa que não há certificado vigente e explica que o AFD e o AEJ ficam sem assinatura"},
     {"ordem":2,"acao":"Clicar em Novo certificado: tipo A1, ICP-Brasil ligado, titular e emissor preenchidos, vencimento daqui a 10 dias, avisar com 30 dias; Salvar","resultado_esperado":"O cartão passa a mostrar o certificado e a lista traz a situação Vence em 10 dia(s)"}]'::jsonb,
   'O certificado é cadastrado e o vencimento em 10 dias é sinalizado.',
   'Bateria de Homologação do Ponto, caso E1. Onde: Ponto › Configurações › Certificado digital. Prepara o cenário do caso C2.'),

  (v_mod, 'PONTO-HOM-E2', 'Montar o dossiê de fiscalização',
   'feliz', 'alta', 'aprovado', 'e2e',
   'Portaria MTP 671/2021 (documentação apresentada à fiscalização)',
   'O dossiê fiscal reúne as peças da competência (AEJ, comprovantes, espelhos e AFD) com assinatura — e não esconde as ausentes.',
   'Competência usada no caso D3.',
   '[{"ordem":1,"acao":"Em Ponto › Compliance › Dossiê fiscal, escolher a competência do D3 e clicar em Montar dossiê","resultado_esperado":"O dossiê é montado"},
     {"ordem":2,"acao":"Conferir o índice e clicar em Baixar índice","resultado_esperado":"O índice lista as quatro peças (AEJ, comprovantes, espelhos e AFD importado) com quantidade e assinatura, mais a assinatura do pacote; peça inexistente aparece marcada como nenhuma, não sumida da lista"}]'::jsonb,
   'O dossiê reúne as quatro peças assinadas, sinalizando as ausentes.',
   'Bateria de Homologação do Ponto, caso E2. Onde: Ponto › Compliance › Dossiê fiscal.'),

  (v_mod, 'PONTO-HOM-E3', 'Remontar o dossiê não duplica',
   'negativo', 'media', 'aprovado', 'e2e',
   'Portaria MTP 671/2021 (peça única de fiscalização)',
   'Remontar o dossiê atualiza o existente, não empilha cópias. Dois dossiês da mesma competência é o pior cenário na fiscalização.',
   'Dossiê do E2 já montado.',
   '[{"ordem":1,"acao":"Na mesma competência, clicar em Montar de novo","resultado_esperado":"Remonta"},
     {"ordem":2,"acao":"Olhar a lista Dossiês montados","resultado_esperado":"Continua havendo um único dossiê para aquela competência, com a data atualizada"}]'::jsonb,
   'Um dossiê por competência; remontar atualiza, não multiplica.',
   'Bateria de Homologação do Ponto, caso E3. Onde: Ponto › Compliance › Dossiê fiscal. Sonda de motor correspondente: PONTO-431.'),

  -- ══════════ F. DADO SENSÍVEL E PROTEÇÃO DO LINK ══════════

  (v_mod, 'PONTO-HOM-F1', 'Selfie fica coberta até alguém pedir para ver',
   'feliz', 'alta', 'aprovado', 'e2e',
   'LGPD art. 11 (dado pessoal sensível: biometria/imagem)',
   'Selfie é dado pessoal; não aparece por padrão no espelho — só depois de um clique explícito.',
   'Um dia com marcação que tenha selfie.',
   '[{"ordem":1,"acao":"Em Ponto › Espelho, abrir um dia em que exista marcação com selfie","resultado_esperado":"No lugar da foto há um ícone de câmera; a foto não aparece ao abrir a tela"},
     {"ordem":2,"acao":"Clicar no ícone de câmera ao lado da marcação","resultado_esperado":"A miniatura aparece e amplia ao passar o mouse"}]'::jsonb,
   'A selfie fica coberta até um clique explícito.',
   'Bateria de Homologação do Ponto, caso F1. Onde: Ponto › Espelho.'),

  (v_mod, 'PONTO-HOM-F2', 'O acesso e as exportações ficam registrados',
   'feliz', 'alta', 'aprovado', 'api',
   'LGPD arts. 37 e 46 (registro das operações de tratamento)',
   'Ver selfie e exportar ponto tocam dado sensível; ambos deixam rastro na trilha de acesso.',
   'Ter feito o F1 e exportado um AFD; SQL Editor de teste.',
   '[{"ordem":1,"acao":"Depois do caso F1, exportar um AFD (Relatórios › AFD)","resultado_esperado":"Exportação feita"},
     {"ordem":2,"acao":"Rodar SELECT usuario_nome, acao, recurso, escopo, created_at FROM public.ponto_acesso_sensivel_log ORDER BY created_at DESC LIMIT 10","resultado_esperado":"Há uma linha visualizou_selfie com o seu nome e a marcação, e outra exportou_afd com a competência e a empresa no escopo"}]'::jsonb,
   'O acesso à selfie e a exportação de AFD ficam registrados na trilha.',
   'Bateria de Homologação do Ponto, caso F2 (banco). Onde: SQL Editor · projeto de teste.'),

  (v_mod, 'PONTO-HOM-F3', 'Link compartilhado se protege de tentativa em série',
   'negativo', 'critica', 'aprovado', 'e2e',
   'LGPD arts. 46-48 (segurança e prevenção de acessos indevidos); Portaria MTP 671/2021',
   'O link externo de marcação é porta na internet; tentativas em série (varredura de CPF) devem ser contidas, sem prender quem é legítimo.',
   'Link compartilhado de marcação ativo.',
   '[{"ordem":1,"acao":"Abrir o link compartilhado de marcação num navegador anônimo","resultado_esperado":"A tela do link aparece"},
     {"ordem":2,"acao":"Digitar cinco CPFs inválidos diferentes, um após o outro","resultado_esperado":"Na quinta tentativa errada, o link avisa que ficou bloqueado por alguns minutos e orienta procurar o RH"},
     {"ordem":3,"acao":"Passado o bloqueio, digitar um CPF válido de colaborador daquele link","resultado_esperado":"Identifica normalmente e o contador zera — quem é legítimo não fica preso"}]'::jsonb,
   'O link bloqueia a varredura e libera o legítimo depois do prazo.',
   'Bateria de Homologação do Ponto, caso F3. Onde: Link externo de marcação (modo compartilhado). Risco alto. Sonda de motor correspondente: PONTO-460.'),

  -- ══════════ G. ART. 62, ESTABELECIMENTO E REP-A ══════════

  (v_mod, 'PONTO-HOM-G1', 'Gestor enquadrado no art. 62 sai do controle de ponto',
   'feliz', 'alta', 'aprovado', 'e2e',
   'CLT art. 62, II (cargo de gestão dispensado do controle de jornada)',
   'Enquadrar no art. 62, II tira o colaborador do módulo de Ponto — e, por consequência, ele deixa de receber falta por não marcar.',
   'Colaborador de teste que hoje bate ponto.',
   '[{"ordem":1,"acao":"Editar o colaborador; no bloco Dispensa de controle de jornada (art. 62 da CLT), escolher II — cargo de gestão / confiança e preencher o documento; Salvar","resultado_esperado":"Enquadramento salvo"},
     {"ordem":2,"acao":"Ir ao módulo Ponto e procurar esse colaborador","resultado_esperado":"Ele deixa de aparecer no Ponto e deixa de receber falta por não marcar"}]'::jsonb,
   'O enquadrado no art. 62 sai do controle de ponto.',
   'Bateria de Homologação do Ponto, caso G1. Onde: Colaboradores › editar.'),

  (v_mod, 'PONTO-HOM-G2', 'Teletrabalho por jornada continua marcando ponto',
   'negativo', 'critica', 'aprovado', 'e2e',
   'Lei 14.442/2022 (teletrabalho por jornada permanece sujeito a controle)',
   'Teletrabalho POR JORNADA continua sujeito a controle mesmo com o inciso III marcado — a dispensa não se aplica.',
   'Outro colaborador de teste.',
   '[{"ordem":1,"acao":"Editar o colaborador, escolher III — teletrabalho por produção e, no campo Teletrabalho, escolher Por jornada","resultado_esperado":"Aparece o aviso âmbar de que teletrabalho por jornada continua sujeito a controle (Lei 14.442/2022)"},
     {"ordem":2,"acao":"Salvar e procurar o colaborador no Ponto","resultado_esperado":"Continua no módulo de Ponto — a dispensa não se aplica, mesmo com o inciso marcado"}]'::jsonb,
   'Teletrabalho por jornada permanece no controle de ponto.',
   'Bateria de Homologação do Ponto, caso G2. Onde: Colaboradores › editar. Risco alto.'),

  (v_mod, 'PONTO-HOM-G3', 'Link externo exige o instrumento coletivo',
   'negativo', 'alta', 'aprovado', 'e2e',
   'CLT art. 74, §2º; CF art. 7º, XXVI',
   'O modo Somente Link Externo exige o instrumento coletivo cadastrado; sem ele, o sistema recusa e diz o que fazer.',
   'Ambiente sem acordo coletivo vigente cadastrado.',
   '[{"ordem":1,"acao":"Em Ponto › Configurações › Geral, escolher Somente Link Externo com o campo do instrumento em branco e salvar","resultado_esperado":"Recusa com a mensagem Falta o instrumento coletivo, dizendo o que fazer"},
     {"ordem":2,"acao":"Preencher o campo do instrumento e salvar de novo","resultado_esperado":"Salva normalmente"}]'::jsonb,
   'Sem instrumento, o modo é recusado; com instrumento, é aceito.',
   'Bateria de Homologação do Ponto, caso G3. Onde: Ponto › Configurações › Geral. Se já houver acordo vigente em Compliance › Acordos, o primeiro passo salva (e está correto) — para testar a recusa, use um ambiente sem acordo vigente.'),

  (v_mod, 'PONTO-HOM-G4', 'Selo de ponto obrigatório acima de 20 empregados',
   'feliz', 'media', 'aprovado', 'e2e',
   'CLT art. 74, §2º (registro de jornada obrigatório acima de 20 empregados)',
   'Empresa com mais de 20 colaboradores ativos recebe o selo de ponto obrigatório, com a explicação legal.',
   'Empresa com mais de 20 colaboradores ativos.',
   '[{"ordem":1,"acao":"Garantir uma empresa com mais de 20 colaboradores ativos","resultado_esperado":"Empresa preparada"},
     {"ordem":2,"acao":"No SQL Editor, rodar SELECT public.ponto_vigilancias_diarias()","resultado_esperado":"Vigilância rodada"},
     {"ordem":3,"acao":"Abrir a lista de Empresas","resultado_esperado":"A empresa mostra o selo ponto obrigatório ao lado da contagem de colaboradores, com a explicação legal ao passar o mouse"}]'::jsonb,
   'O selo de ponto obrigatório aparece acima de 20 empregados.',
   'Bateria de Homologação do Ponto, caso G4. Onde: Empresas.'),

  -- ══════════ H. ESCALAS E TROCA DE TURNO ══════════

  (v_mod, 'PONTO-HOM-H1', 'Escala 12x36 sem acordo aparece como pendente',
   'negativo', 'alta', 'aprovado', 'e2e',
   'CLT art. 59-A (regime 12x36 mediante acordo)',
   'Escala 12x36 sem acordo anexado aparece como pendente de formalização; anexado o acordo, entra em ordem.',
   'Uma escala 12x36 sem acordo.',
   '[{"ordem":1,"acao":"Criar ou usar uma escala 12x36 sem acordo anexado","resultado_esperado":"A escala existe"},
     {"ordem":2,"acao":"Olhar a coluna Formalização e o cartão no topo da aba","resultado_esperado":"Coluna mostra Falta acordo e a escala aparece no cartão de aviso do topo, com a explicação legal"},
     {"ordem":3,"acao":"Anexar o acordo na escala e recarregar","resultado_esperado":"Vira Em ordem e some do cartão"}]'::jsonb,
   'Sem acordo a 12x36 fica pendente; com acordo entra em ordem.',
   'Bateria de Homologação do Ponto, caso H1. Onde: Ponto › Escalas.'),

  (v_mod, 'PONTO-HOM-H2', 'Revezamento acima de 6h só com acordo coletivo',
   'negativo', 'critica', 'aprovado', 'e2e',
   'CF art. 7º, XIV (turno ininterrupto de revezamento; jornada de 6h salvo negociação coletiva)',
   'Turno ininterrupto de revezamento acima de 6h só se autoriza por instrumento COLETIVO (CCT/ACT); acordo individual não amplia.',
   'Ponto › Escalas › nova escala.',
   '[{"ordem":1,"acao":"Criar uma escala com modalidade Turno ininterrupto de revezamento e jornada de 8 horas","resultado_esperado":"Surge o aviso das 6 horas"},
     {"ordem":2,"acao":"Anexar um acordo individual e recarregar a lista","resultado_esperado":"A escala continua como Falta acordo — só o instrumento coletivo autoriza ampliar (CF art. 7º, XIV)"},
     {"ordem":3,"acao":"Trocar por uma CCT/ACT e recarregar de novo","resultado_esperado":"Vira Em ordem"}]'::jsonb,
   'Só o instrumento coletivo autoriza o revezamento acima de 6h.',
   'Bateria de Homologação do Ponto, caso H2. Onde: Ponto › Escalas › nova escala. Risco alto.'),

  (v_mod, 'PONTO-HOM-H3', 'Troca de turno avisa risco de interjornada',
   'alternativo', 'critica', 'aprovado', 'e2e',
   'CLT art. 66 (interjornada mínima de 11 horas)',
   'Troca de turno que deixe menos de 11h de descanso entre jornadas deve avisar o risco e exigir confirmação digitada — sem bloquear a decisão do gestor.',
   'Duas escalas com viradas próximas (uma sai às 23:00, outra entra às 07:00), com um colaborador em cada.',
   '[{"ordem":1,"acao":"Em Ponto › Escalas › Troca de turno, clicar em Nova troca, escolher os dois, informar a data e registrar","resultado_esperado":"Troca registrada"},
     {"ordem":2,"acao":"Olhar a linha da troca","resultado_esperado":"Selo vermelho abaixo de 11h; o detalhe da simulação aparece no título"},
     {"ordem":3,"acao":"Tentar aprovar a troca","resultado_esperado":"O sistema pede confirmação digitada; o gestor pode assumir a decisão, mas não sem ver o risco (CLT art. 66)"}]'::jsonb,
   'A troca sinaliza o risco de interjornada e exige confirmação consciente.',
   'Bateria de Homologação do Ponto, caso H3. Onde: Ponto › Escalas › Troca de turno. Risco alto.'),

  (v_mod, 'PONTO-HOM-H4', 'Efetivar a troca preserva o histórico',
   'feliz', 'media', 'aprovado', 'e2e',
   'Portaria MTP 671/2021 (rastreabilidade das atribuições de escala)',
   'Efetivar a troca só depois de aprovada, encerrando a atribuição antiga na véspera — sem apagar o histórico.',
   'Troca do H3 registrada.',
   '[{"ordem":1,"acao":"Numa troca ainda não aprovada, conferir que o botão Efetivar não aparece","resultado_esperado":"Ausente antes da aprovação"},
     {"ordem":2,"acao":"Aprovar e depois clicar em Efetivar, confirmando","resultado_esperado":"Troca efetivada"},
     {"ordem":3,"acao":"Voltar à lista de Escalas e olhar as atribuições dos dois colaboradores","resultado_esperado":"Cada colaborador está na escala do outro a partir da data da troca, e a atribuição antiga foi encerrada na véspera, não apagada"}]'::jsonb,
   'Efetivar preserva o histórico e só ocorre após aprovação.',
   'Bateria de Homologação do Ponto, caso H4. Onde: Ponto › Escalas › Troca de turno.'),

  -- ══════════ I. DO ALERTA AO PLANO DE AÇÃO ══════════

  (v_mod, 'PONTO-HOM-I1', 'Gerar ação a partir de um alerta',
   'feliz', 'media', 'aprovado', 'e2e',
   'NR-1 (gestão de riscos) c/c CLT art. 74',
   'Um alerta CLT pode virar ação no Plano de Ação, com a origem apontando para o ponto — e o botão não se repete.',
   'Ao menos um alerta na lista de Alertas CLT.',
   '[{"ordem":1,"acao":"Em Ponto › Compliance › Alertas CLT, num alerta qualquer, clicar em Gerar ação","resultado_esperado":"O alerta passa a mostrar o selo Ação criada; o botão não se repete"},
     {"ordem":2,"acao":"Abrir o módulo Plano de Ação","resultado_esperado":"A ação aparece com a origem apontando para o ponto"}]'::jsonb,
   'O alerta gera uma ação rastreável no Plano de Ação.',
   'Bateria de Homologação do Ponto, caso I1. Onde: Ponto › Compliance › Alertas CLT.'),

  (v_mod, 'PONTO-HOM-I2', 'A análise sugere; quem decide é a pessoa',
   'alternativo', 'media', 'aprovado', 'e2e',
   'LGPD art. 20 (revisão por pessoa natural de decisões automatizadas)',
   'A Análise com IA apenas sugere (causa, impacto, ação); recusar não cria nada, aceitar cria a ação — e a decisão fica registrada nos dois casos.',
   'Alertas na lista de Alertas CLT.',
   '[{"ordem":1,"acao":"Em outro alerta, clicar em Analisar com IA","resultado_esperado":"O diálogo mostra causa provável, impacto e ação sugerida, e diz que a análise apenas sugere"},
     {"ordem":2,"acao":"Escrever uma observação e clicar em Recusar sugestão","resultado_esperado":"Nada é criado; a decisão fica registrada"},
     {"ordem":3,"acao":"Repetir em um terceiro alerta, agora escolhendo Aceitar e criar ação","resultado_esperado":"A ação é criada e o alerta ganha o selo Ação criada"}]'::jsonb,
   'A IA sugere, a pessoa decide, e a decisão (recusa ou aceite) fica registrada.',
   'Bateria de Homologação do Ponto, caso I2. Onde: Ponto › Compliance › Alertas CLT.'),

  (v_mod, 'PONTO-HOM-I3', 'Conclusão não dá baixa cega',
   'alternativo', 'critica', 'aprovado', 'e2e',
   'NR-1 (eficácia das medidas de controle)',
   'Concluir a ação cuja ocorrência ainda acontece abre um alerta de eficácia, em vez de o problema sumir junto com a ação.',
   'Ação do I1 cuja ocorrência de origem ainda acontece.',
   '[{"ordem":1,"acao":"Pegar a ação criada em I1, cuja ocorrência de origem ainda acontece (por exemplo, o intervalo segue suprimido)","resultado_esperado":"Ação em aberto"},
     {"ordem":2,"acao":"Marcar a ação como concluída","resultado_esperado":"A ação é concluída, mas aparece o aviso de que a ocorrência ainda acontece e que um alerta de eficácia foi aberto para acompanhamento"}]'::jsonb,
   'Concluir não apaga o problema: abre alerta de eficácia se a ocorrência persiste.',
   'Bateria de Homologação do Ponto, caso I3. Onde: Plano de Ação. Risco alto.')

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'PONTO (bateria de homologação): casos antes=%, depois=% (esperado +31 na primeira execução).', v_antes, v_depois;
END $doc$;

-- ── Conferência (última query: é o que o SQL Editor exibe) ──
SELECT m.path AS modulo,
       count(*)                                   AS casos_hom,
       count(*) FILTER (WHERE c.nivel = 'e2e')    AS de_tela,
       count(*) FILTER (WHERE c.nivel = 'api')    AS de_banco,
       min(c.codigo)                              AS primeiro,
       max(c.codigo)                              AS ultimo
FROM public.qa_casos_teste c
JOIN public.qa_modulos m ON m.id = c.modulo_id
WHERE c.codigo LIKE 'PONTO-HOM-%'
GROUP BY m.path;
