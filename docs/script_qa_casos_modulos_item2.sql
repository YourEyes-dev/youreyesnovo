-- =========================================================
-- ENTREGA QA — Item 2: módulos ainda sem cobertura (105 casos)
--
-- Cole este arquivo inteiro no SQL Editor do ambiente de HOMOLOGACAO
-- (projeto fgsblefvdabgdouipigz). Documenta os casos dos módulos que ainda
-- não tinham nenhum caso:
--   Análise de Jornada (14), Contratos de Experiência (14),
--   Cultura & Celebrações (13), Onboarding (13), Suporte (12),
--   Aprendizado & Papéis (13), Autenticação (12),
--   RLS (7, nível api), Edge Functions (7, nível api).
--
-- Só INSERE dados (linhas em qa_casos_teste). Não cria nem altera estrutura,
-- então não mexe na fidelidade com a produção. Idempotente:
-- ON CONFLICT (codigo) DO NOTHING. Cada bloco procura o módulo pelo path; se
-- não achar, avisa e pula (RAISE NOTICE + RETURN dentro do IF) sem abortar os
-- demais. Roda inteiro em UMA transação — nada de tabela temporária.
--
-- Ao final, uma única conferência SELECT lista o que ficou registrado.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'jornada-rotina/analise-jornada';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo jornada-rotina/analise-jornada não encontrado.'; RETURN; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'AJOR-001', 'Tela de Análise de Jornada abre com as 8 abas',
   'feliz', 'alta', 'aprovado', 'e2e', 'CLT / NR-1',
   'O módulo cruza ponto com a lei e vira monitoramento de jornada. Se não monta, o RH/SST perde o painel de conformidade e riscos.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar Análise de Jornada pelo menu","resultado_esperado":"Título Análise de Carga de Trabalho & Jornada carrega"},
     {"ordem":2,"acao":"Conferir as abas","resultado_esperado":"Dashboard, Importação, Individual, Coletiva, Conformidade, Alertas, Documentos, Relatórios"}]'::jsonb,
   'O módulo monta com as 8 abas.', NULL),

  (v_mod, 'AJOR-010', 'Executar a análise do período',
   'feliz', 'critica', 'aprovado', 'e2e', 'CLT (art. 58, 59, 66, 71)',
   'A análise é o motor: lê o ponto do mês, calcula horas/violações/risco e gera alertas. Sem rodá-la, quase todas as abas ficam vazias.',
   'Ponto do mês em ponto_diario.',
   '[{"ordem":1,"acao":"No Dashboard, clicar em Executar Análise","resultado_esperado":"Processa (Analisando...) e conclui"},
     {"ordem":2,"acao":"Conferir o retorno","resultado_esperado":"Aviso Análise concluída: N colaboradores avaliados; KPIs e gráficos preenchem"}]'::jsonb,
   'A análise roda e alimenta o painel.', NULL),

  (v_mod, 'AJOR-011', 'Dashboard mostra os KPIs e destaca risco/não conformidade',
   'feliz', 'alta', 'aprovado', 'e2e', 'CLT',
   'Os 6 KPIs resumem a situação. Risco Alto e Não Conforme em vermelho são o chamado à ação.',
   'Uma análise executada.',
   '[{"ordem":1,"acao":"Conferir os cards","resultado_esperado":"Colaboradores, Média h/dia, Total HE, Alertas, Risco Alto, Não Conforme"},
     {"ordem":2,"acao":"Conferir com risco/não conformidade > 0","resultado_esperado":"Cards correspondentes destacados em vermelho"}]'::jsonb,
   'Os indicadores refletem a análise e destacam o crítico.', NULL),

  (v_mod, 'AJOR-020', 'Estados vazios orientam a rodar a análise primeiro',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Sem análise, Individual/Coletiva/Conformidade não têm dados. Devem orientar a rodar a análise, não quebrar.',
   'Nenhuma análise executada.',
   '[{"ordem":1,"acao":"Abrir Individual, Coletiva e Conformidade sem análise","resultado_esperado":"Cada aba mostra Execute a análise no Dashboard primeiro; sem erro"}]'::jsonb,
   'Os vazios pré-análise são tratados.', NULL),

  (v_mod, 'AJOR-030', 'Importar arquivo de ponto pelo assistente',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'A importação traz o ponto de fora (CSV/Excel) para a base. É o que alimenta a análise quando o ponto não é nativo.',
   'Arquivo CSV/Excel de jornada (até 20MB).',
   '[{"ordem":1,"acao":"Enviar o arquivo (Upload)","resultado_esperado":"Planilha lida; passo Mapeamento abre"},
     {"ordem":2,"acao":"Mapear ao menos Nome e Data, pré-visualizar e importar","resultado_esperado":"Passo Resultado mostra novos/atualizados/erros"}]'::jsonb,
   'A importação percorre os 4 passos e grava o ponto.',
   'Assistente Upload → Mapeamento → Preview → Resultado.'),

  (v_mod, 'AJOR-031', 'Importação bloqueia sem mapear Nome e Data',
   'negativo', 'alta', 'aprovado', 'e2e', NULL,
   'Sem Nome e Data não há registro de ponto válido. O preview deve exigir esses dois campos.',
   'Arquivo carregado, no passo Mapeamento.',
   '[{"ordem":1,"acao":"Tentar pré-visualizar sem mapear Nome e Data","resultado_esperado":"Aviso Mapeie pelo menos Nome e Data; não avança"}]'::jsonb,
   'O mapeamento mínimo é exigido.', NULL),

  (v_mod, 'AJOR-032', 'Importação recusa arquivo inválido (tipo/tamanho/vazio)',
   'negativo', 'media', 'aprovado', 'e2e', NULL,
   'Arquivo do tipo errado, grande demais ou vazio não pode entrar. A tela deve recusar com aviso.',
   'Passo Upload.',
   '[{"ordem":1,"acao":"Tentar enviar um arquivo não CSV/Excel, acima de 20MB, ou vazio","resultado_esperado":"Recusa com aviso claro (ex.: Arquivo vazio ou sem dados)"}]'::jsonb,
   'Arquivos inválidos são recusados.', NULL),

  (v_mod, 'AJOR-040', 'Análise Individual abre a jornada de um colaborador',
   'feliz', 'alta', 'aprovado', 'e2e', 'CLT',
   'É o detalhe por pessoa: média diária, HE, atrasos, violações e o gráfico da jornada. Base para conversas e ações.',
   'Análise executada.',
   '[{"ordem":1,"acao":"Buscar e selecionar um colaborador","resultado_esperado":"Painel com risco, conformidade, métricas e o gráfico Jornada Diária"}]'::jsonb,
   'A visão individual monta com os indicadores da pessoa.',
   'Colaborador afastado exibe o selo de afastamento.'),

  (v_mod, 'AJOR-050', 'Conformidade avalia pelos parâmetros da CLT',
   'feliz', 'critica', 'aprovado', 'e2e', 'CLT (art. 58, 59, 66, 67, 71)',
   'A aba Conformidade traduz a jornada em cumprimento da lei. Os parâmetros padrão (8/44/2/60/11/24) são o alicerce do cálculo de violações.',
   'Análise executada.',
   '[{"ordem":1,"acao":"Abrir Conformidade e Parâmetros","resultado_esperado":"Padrão CLT: 8 diária, 44 semanal, 2 HE, 60 intervalo, 11 interjornada, 24 semanal"},
     {"ordem":2,"acao":"Conferir o detalhamento de violações","resultado_esperado":"Intervalo, interjornada (11h), jornada excedida, HE excedida, DSR e o total"}]'::jsonb,
   'A conformidade reflete os limites da CLT.', NULL),

  (v_mod, 'AJOR-051', 'Salvar parâmetros de conformidade',
   'feliz', 'media', 'aprovado', 'e2e', 'CLT',
   'Cada empresa pode ajustar os limites (acordo coletivo, etc.). Salvar deve persistir o perfil que rege a próxima análise.',
   'Aba Conformidade, painel Parâmetros aberto.',
   '[{"ordem":1,"acao":"Ajustar um limite e Salvar Parâmetros","resultado_esperado":"Aviso Parâmetros salvos com sucesso"}]'::jsonb,
   'Os parâmetros de conformidade persistem.', NULL),

  (v_mod, 'AJOR-060', 'Triagem de alertas: filtrar e resolver',
   'feliz', 'alta', 'aprovado', 'e2e', 'NR-1 (gestão de riscos)',
   'Os alertas apontam onde a jornada saiu do trilho. Filtrar por tipo/status e marcar como resolvido é o fluxo de tratativa.',
   'Análise executada com alertas.',
   '[{"ordem":1,"acao":"Filtrar por tipo e status na aba Alertas","resultado_esperado":"A lista restringe conforme o filtro"},
     {"ordem":2,"acao":"Marcar um alerta como Resolver","resultado_esperado":"Aviso Alerta marcado como resolvido; vira ✓ Resolvido"}]'::jsonb,
   'Os alertas são filtráveis e resolvíveis.', NULL),

  (v_mod, 'AJOR-070', 'Anexar documento de apoio (PDF) para auditoria',
   'alternativo', 'media', 'aprovado', 'e2e', 'NR-1 / auditoria',
   'Documentos (espelho de ponto, acordo, convenção) são a evidência para auditoria/NR-1. Enviar deve armazenar e vincular por tipo/período.',
   'Aba Documentos; PDF válido (até 20MB).',
   '[{"ordem":1,"acao":"Enviar Documento com nome e tipo","resultado_esperado":"Aviso Documento enviado com sucesso; aparece na lista"}]'::jsonb,
   'O documento de apoio é anexado.', NULL),

  (v_mod, 'AJOR-080', 'Exportar relatório é gated pelo perfil de acesso',
   'negativo', 'critica', 'aprovado', 'e2e', 'LGPD art. 6º (dado pessoal e de saúde)',
   'O relatório tira dados pessoais e de saúde do sistema — é a ação de maior exposição. Deve seguir a permissão de exportar do perfil.',
   'Perfis com e sem permissão de exportar (módulo colaboradores).',
   '[{"ordem":1,"acao":"Abrir Relatórios com perfil sem permissão de exportar","resultado_esperado":"Botão de exportar desabilitado com aviso Seu perfil de acesso não permite exportar relatórios de jornada."},
     {"ordem":2,"acao":"Com perfil autorizado, exportar (Excel/PDF)","resultado_esperado":"Relatório gerado (ex.: integrado NR-1/PGR)"}]'::jsonb,
   'A exportação respeita a permissão do perfil.',
   'AcaoProtegida modulo=colaboradores acao=exportar.'),

  (v_mod, 'AJOR-081', 'Exportar sem análise avisa e não gera',
   'negativo', 'media', 'aprovado', 'e2e', NULL,
   'Sem análise não há o que exportar. A tela deve avisar em vez de gerar um relatório vazio.',
   'Nenhuma análise executada.',
   '[{"ordem":1,"acao":"Tentar exportar em Relatórios sem análise","resultado_esperado":"Aviso Nenhuma análise disponível. Execute a análise no Dashboard primeiro."}]'::jsonb,
   'A exportação sem dados é barrada com orientação.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Análise de Jornada: antes=%, depois=% (esperado +14)', v_antes, v_depois;
END $doc$;

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'pessoas-cultura/contratos-experiencia';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo pessoas-cultura/contratos-experiencia não encontrado.'; RETURN; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'EXP-001', 'Painel de Contratos de Experiência abre com abas e KPIs',
   'feliz', 'alta', 'aprovado', 'e2e', 'CLT art. 445',
   'É o painel de controle do período de experiência. Se não monta, o RH perde o acompanhamento dos prazos legais e das ações (prorrogar, efetivar, encerrar).',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar Contratos de Experiência pelo menu","resultado_esperado":"Título Contratos de Experiência carrega"},
     {"ordem":2,"acao":"Conferir as abas e os cards","resultado_esperado":"Abas Painel e Configuração da Empresa; KPIs Em Experiência / Vencendo em 7,15,30 dias / Total de Contratos"}]'::jsonb,
   'O painel monta com abas e indicadores de vencimento.', NULL),

  (v_mod, 'EXP-002', 'KPIs de vencimento refletem os contratos ativos',
   'feliz', 'alta', 'aprovado', 'e2e', 'CLT art. 445',
   'Os cards Vencendo em 7/15/30 dias dizem ao RH o que agir antes que o prazo estoure. Precisam contar só contratos ativos, não os vencidos ou efetivados.',
   'Contratos em experiência com datas de término variadas.',
   '[{"ordem":1,"acao":"Conferir Em Experiência e os Vencendo em 7/15/30 dias","resultado_esperado":"Contagens coerentes com as datas de término dos contratos ativos"}]'::jsonb,
   'Os indicadores de vencimento são consistentes.',
   'Vencido (dias negativos) não entra em nenhum card de "vencendo".'),

  (v_mod, 'EXP-003', 'Buscar e filtrar contratos por status, prazo e unidade',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Numa base grande, achar um contrato ou os que vencem exige busca e filtros. Deve filtrar por colaborador/CPF/cargo, status, prazo e unidade.',
   'Vários contratos cadastrados.',
   '[{"ordem":1,"acao":"Buscar por colaborador, CPF ou cargo","resultado_esperado":"A lista filtra pelo termo"},
     {"ordem":2,"acao":"Aplicar filtro de status (1º Período) e de prazo (Vencendo em 15 dias)","resultado_esperado":"A lista restringe aos contratos correspondentes"}]'::jsonb,
   'Busca e filtros restringem a lista corretamente.',
   'placeholder "Buscar colaborador, CPF ou cargo...".'),

  (v_mod, 'EXP-010', 'Prorrogar um contrato dentro do limite legal',
   'feliz', 'critica', 'aprovado', 'e2e', 'CLT art. 445',
   'A prorrogação estende o 1º período respeitando o teto de 90 dias. É o ato que segura a experiência sem estourar a lei.',
   'Um contrato em 1º Período, ainda não prorrogado, com dias disponíveis.',
   '[{"ordem":1,"acao":"Abrir Prorrogar Contrato","resultado_esperado":"Modal mostra 1º período, dias disponíveis e o aviso do art. 445"},
     {"ordem":2,"acao":"Informar uma duração dentro do disponível e confirmar","resultado_esperado":"Contrato passa a 2º Período (prorrogado); histórico registrado"}]'::jsonb,
   'A prorrogação é aplicada dentro do limite.',
   'Modal "Prorrogar Contrato".'),

  (v_mod, 'EXP-011', 'Bloquear prorrogação que ultrapassa 90 dias',
   'negativo', 'critica', 'aprovado', 'e2e', 'CLT art. 445 (máximo 90 dias)',
   'Passar de 90 dias no total é ilegal. A tela deve impedir e sinalizar antes de salvar.',
   'Contrato em 1º Período aberto para prorrogação.',
   '[{"ordem":1,"acao":"Informar uma duração que faça o total passar de 90 dias","resultado_esperado":"Aviso ⚠️ Total excede 90 dias! e o botão Prorrogar desabilitado"},
     {"ordem":2,"acao":"Tentar confirmar","resultado_esperado":"A prorrogação não ocorre"}]'::jsonb,
   'O teto de 90 dias é respeitado.', NULL),

  (v_mod, 'EXP-012', 'Impedir uma segunda prorrogação',
   'negativo', 'alta', 'aprovado', 'e2e', 'CLT art. 445 (uma única prorrogação)',
   'A CLT permite só uma prorrogação. Um contrato já em 2º período não pode ser prorrogado de novo.',
   'Um contrato já prorrogado (2º Período).',
   '[{"ordem":1,"acao":"Abrir um contrato já prorrogado","resultado_esperado":"A ação Prorrogar não é oferecida (ou é bloqueada com aviso de limite de uma prorrogação)"}]'::jsonb,
   'A prorrogação única é garantida.', NULL),

  (v_mod, 'EXP-020', 'Efetivar um colaborador ao fim da experiência',
   'feliz', 'critica', 'aprovado', 'e2e', 'CLT (vínculo por prazo indeterminado)',
   'Efetivar converte o vínculo para prazo indeterminado e encerra o contrato de experiência. É a decisão que confirma a contratação.',
   'Um contrato em experiência ativo.',
   '[{"ordem":1,"acao":"Abrir Efetivar Colaborador","resultado_esperado":"Modal explica o que acontece e mostra o resumo"},
     {"ordem":2,"acao":"Confirmar a efetivação","resultado_esperado":"Status vira Efetivado; a admissão passa a CLT prazo indeterminado; confirmação exibida"}]'::jsonb,
   'A efetivação converte o vínculo e encerra a experiência.',
   'Modal "Efetivar Colaborador".'),

  (v_mod, 'EXP-030', 'Encerrar contrato com rescisão antecipada mostra o aviso legal',
   'alternativo', 'alta', 'aprovado', 'e2e', 'CLT art. 479 e 480',
   'Rescindir antes do fim tem consequências (indenização ou aviso prévio conforme a cláusula assecuratória). A tela deve alertar sobre a base legal antes de encerrar.',
   'Contrato em experiência ativo.',
   '[{"ordem":1,"acao":"Abrir Encerrar Contrato e escolher Rescisão antecipada","resultado_esperado":"Aparece a Atenção Legal (art. 479/480 ou aviso prévio, conforme cláusula assecuratória)"},
     {"ordem":2,"acao":"Confirmar o encerramento","resultado_esperado":"Status vira Encerrado; histórico registrado"}]'::jsonb,
   'O encerramento antecipado informa a consequência legal.',
   'Modal "Encerrar Contrato".'),

  (v_mod, 'EXP-040', 'Dias Restantes e status urgente destacados na lista',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'A coluna Dias Restantes e o destaque vermelho dizem, num relance, quais contratos exigem ação imediata.',
   'Contratos com prazos variados, incluindo um a vencer em até 7 dias.',
   '[{"ordem":1,"acao":"Conferir a coluna Dias Restantes","resultado_esperado":"Mostra os dias, Vence hoje! ou Vencido! conforme a data"},
     {"ordem":2,"acao":"Conferir um contrato a vencer em ≤7 dias","resultado_esperado":"Linha destacada (urgência) em vermelho"}]'::jsonb,
   'A urgência do prazo é visível na lista.', NULL),

  (v_mod, 'EXP-050', 'Gerar documento respeita o estado do contrato',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Os documentos (contrato, termo de prorrogação/efetivação/rescisão) só fazem sentido no estado certo. A geração deve liberar o documento coerente e bloquear o inaplicável.',
   'Um contrato em algum estado (ex.: prorrogado).',
   '[{"ordem":1,"acao":"Abrir Gerar Documento","resultado_esperado":"Contrato de Experiência sempre disponível; termos habilitados só no estado correspondente"},
     {"ordem":2,"acao":"Gerar o documento aplicável","resultado_esperado":"Documento é produzido e exibido para impressão/download"}]'::jsonb,
   'A geração de documento segue o estado do contrato.',
   'Componente ExperienciaDocGenerator (Edge Function ai-experiencia-doc).'),

  (v_mod, 'EXP-051', 'Enviar documento para assinatura gera link com validade',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'A assinatura formaliza o documento. Enviar deve gerar um link seguro por parte (colaborador/empregador/testemunha), com expiração.',
   'Um documento gerado.',
   '[{"ordem":1,"acao":"Informar o signatário e enviar para assinatura","resultado_esperado":"Link gerado e copiável; aviso de expiração em 7 dias"}]'::jsonb,
   'O envio para assinatura produz link com validade.', NULL),

  (v_mod, 'EXP-060', 'Configurar o modelo de períodos sem exceder 90 dias',
   'negativo', 'alta', 'aprovado', 'e2e', 'CLT art. 445',
   'A empresa define 1 período único ou 2 períodos (ex.: 45+45). A soma não pode passar de 90 dias — a configuração deve recusar.',
   'Aba Configuração da Empresa; empresa selecionada.',
   '[{"ordem":1,"acao":"Escolher 2 períodos e somar mais de 90 dias","resultado_esperado":"Sinaliza (excede 90!) e o Salvar Configuração fica desabilitado"},
     {"ordem":2,"acao":"Ajustar para ≤90 e salvar","resultado_esperado":"Configuração salva"}]'::jsonb,
   'A configuração de períodos respeita o teto legal.',
   'Componente ExperienciaConfigForm.'),

  (v_mod, 'EXP-061', 'Configuração exige empresa selecionada',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'A configuração é por empresa. Sem empresa selecionada, a aba deve orientar, não quebrar.',
   'Nenhuma empresa selecionada no seletor global.',
   '[{"ordem":1,"acao":"Abrir Configuração da Empresa sem empresa selecionada","resultado_esperado":"Orientação para selecionar uma empresa; sem erro"}]'::jsonb,
   'O estado sem empresa é tratado.', NULL),

  (v_mod, 'EXP-070', 'Contratos isolados por empresa/tenant',
   'negativo', 'alta', 'aprovado', 'e2e', 'LGPD art. 6º (dado pessoal de vínculo)',
   'Contrato de experiência é dado pessoal e trabalhista. A lista não pode misturar colaboradores de outra empresa/tenant.',
   'Base com contratos de mais de uma empresa.',
   '[{"ordem":1,"acao":"Abrir o painel com uma empresa ativa","resultado_esperado":"Só aparecem contratos da empresa/tenant do usuário"}]'::jsonb,
   'O escopo por empresa/tenant é respeitado.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Contratos de Experiência: antes=%, depois=% (esperado +14)', v_antes, v_depois;
END $doc$;

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'pessoas-cultura/cultura-celebracoes';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo pessoas-cultura/cultura-celebracoes não encontrado.'; RETURN; END IF;
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

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'pessoas-cultura/onboarding';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo pessoas-cultura/onboarding não encontrado.'; RETURN; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'ONB-001', 'Onboarding Gamificado abre com as três abas',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'É o console de RH do onboarding: templates, processos e indicadores. Se não monta, o RH perde a gestão da integração de novos colaboradores.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar Onboarding pelo menu","resultado_esperado":"Título Onboarding Gamificado carrega"},
     {"ordem":2,"acao":"Conferir as abas","resultado_esperado":"Processos, Indicadores, Templates"}]'::jsonb,
   'A tela monta com as três abas.', NULL),

  (v_mod, 'ONB-010', 'Criar um template de onboarding',
   'feliz', 'critica', 'aprovado', 'e2e', NULL,
   'O template é a trilha reutilizável de integração. Sem criar template não há onboarding para atribuir.',
   'Aba Templates; perfil com permissão.',
   '[{"ordem":1,"acao":"Clicar em Novo Template","resultado_esperado":"Modal Novo Template de Onboarding abre"},
     {"ordem":2,"acao":"Informar o Nome e salvar","resultado_esperado":"Aviso Template criado!; template aparece na lista"}]'::jsonb,
   'O template é criado e listado.',
   'Só o Nome é obrigatório; demais campos têm padrão.'),

  (v_mod, 'ONB-011', 'Não criar template sem nome',
   'negativo', 'media', 'aprovado', 'e2e', NULL,
   'Template sem nome não se identifica. O botão de criar deve ficar desabilitado sem o nome.',
   'Modal Novo Template aberto.',
   '[{"ordem":1,"acao":"Deixar o Nome vazio","resultado_esperado":"O botão Criar Template fica desabilitado"}]'::jsonb,
   'Template sem nome não é criado.', NULL),

  (v_mod, 'ONB-012', 'Editar um template e persistir',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Ajustar prazo, certificado, PDI e abrangência mantém a trilha atualizada. A edição deve persistir.',
   'Um template criado.',
   '[{"ordem":1,"acao":"Abrir a edição do template, alterar um campo e salvar","resultado_esperado":"Aviso Template atualizado!; a alteração permanece"}]'::jsonb,
   'A edição de template persiste.', NULL),

  (v_mod, 'ONB-013', 'Ativar/inativar um template',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'Só templates ativos entram no fluxo. O botão de ativação alterna o estado imediatamente.',
   'Um template na lista.',
   '[{"ordem":1,"acao":"Alternar o estado ativo do template","resultado_esperado":"O selo Ativo/Inativo reflete a mudança"}]'::jsonb,
   'A ativação do template funciona.', NULL),

  (v_mod, 'ONB-020', 'Adicionar uma etapa à trilha do template',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'As etapas são o corpo da trilha (apresentação, cultura, quiz, reflexão...). Montar etapas é o que dá conteúdo ao onboarding.',
   'Um template aberto (Detalhe).',
   '[{"ordem":1,"acao":"Clicar em Adicionar Etapa","resultado_esperado":"Modal Nova Etapa abre"},
     {"ordem":2,"acao":"Informar o Título, tipo e salvar","resultado_esperado":"Aviso Etapa adicionada!; etapa numerada na trilha"}]'::jsonb,
   'A etapa é adicionada à trilha.',
   'Título obrigatório; campos condicionais por tipo/formato (ex.: URL para vídeo).'),

  (v_mod, 'ONB-021', 'Não adicionar etapa sem título',
   'negativo', 'media', 'aprovado', 'e2e', NULL,
   'Etapa sem título não se identifica na trilha. O adicionar deve exigir o título.',
   'Modal Nova Etapa aberto.',
   '[{"ordem":1,"acao":"Deixar o Título vazio","resultado_esperado":"O botão Adicionar Etapa fica desabilitado"}]'::jsonb,
   'Etapa sem título não é adicionada.', NULL),

  (v_mod, 'ONB-030', 'Excluir template e etapa com confirmação',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Remover template/etapa é destrutivo. Deve pedir confirmação antes de apagar.',
   'Um template com etapa.',
   '[{"ordem":1,"acao":"Remover uma etapa e confirmar","resultado_esperado":"Confirmação Remover etapa; após confirmar, some da trilha"},
     {"ordem":2,"acao":"Remover o template e confirmar","resultado_esperado":"Confirmação Remover template; após confirmar, some da lista"}]'::jsonb,
   'A exclusão pede confirmação e efetiva.', NULL),

  (v_mod, 'ONB-040', 'Processos mostram o andamento de cada novo colaborador',
   'feliz', 'alta', 'aprovado', 'e2e', 'LGPD art. 6º (dado de novo colaborador)',
   'A aba Processos é o acompanhamento: quem está pendente, em andamento, concluído, com progresso e pontos.',
   'Aba Processos.',
   '[{"ordem":1,"acao":"Abrir a aba Processos","resultado_esperado":"Cards Total/Pendentes/Em andamento/Concluídos e a lista com progresso e status"}]'::jsonb,
   'O acompanhamento dos processos monta.', NULL),

  (v_mod, 'ONB-050', 'Indicadores consolidam conclusão e percepção cultural',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Os indicadores dizem se o onboarding engaja: taxa de conclusão, tempo médio e as respostas de percepção cultural agregadas.',
   'Aba Indicadores.',
   '[{"ordem":1,"acao":"Abrir Indicadores","resultado_esperado":"KPIs (Total, Taxa Conclusão, Tempo Médio, Em Andamento, Respostas Culturais) montam"},
     {"ordem":2,"acao":"Filtrar a Percepção Cultural por categoria","resultado_esperado":"As respostas filtram; vazio mostra a orientação"}]'::jsonb,
   'Os indicadores de onboarding montam com filtro de percepção.', NULL),

  (v_mod, 'ONB-051', 'Estados vazios de templates, etapas e percepção orientam',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'Empresa nova abre tudo vazio. Cada área deve orientar a começar, não exibir erro.',
   'Ambiente sem templates/etapas/respostas.',
   '[{"ordem":1,"acao":"Abrir Templates sem templates","resultado_esperado":"Nenhum template de onboarding + Criar Primeiro Template"},
     {"ordem":2,"acao":"Abrir um template sem etapas e a percepção sem respostas","resultado_esperado":"Mensagens orientativas; sem erro"}]'::jsonb,
   'Os vazios são tratados com orientação.', NULL),

  (v_mod, 'ONB-060', 'Abrangência vazia significa aplicar a todos',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'Deixar funções/departamentos/vínculos em branco faz o template valer para todos — regra que precisa ficar visível.',
   'Modal de template.',
   '[{"ordem":1,"acao":"Salvar um template sem escolher funções/departamentos","resultado_esperado":"O card indica Aplica a todos os colaboradores"}]'::jsonb,
   'A abrangência vazia é interpretada como todos.', NULL),

  (v_mod, 'ONB-070', 'Processos isolados por empresa/tenant',
   'negativo', 'alta', 'aprovado', 'e2e', 'LGPD art. 6º',
   'Processos trazem nome e CPF de novos colaboradores. A lista não pode misturar outra empresa/tenant.',
   'Base com processos de mais de um tenant.',
   '[{"ordem":1,"acao":"Abrir Processos autenticado num tenant","resultado_esperado":"Só aparecem processos do tenant do usuário"}]'::jsonb,
   'O escopo por tenant é respeitado.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Onboarding (RH): antes=%, depois=% (esperado +13)', v_antes, v_depois;
END $doc$;

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'sistema/suporte';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo sistema/suporte não encontrado.'; RETURN; END IF;
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

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'desenvolvimento-performance/aprendizado-competencias';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo desenvolvimento-performance/aprendizado-competencias não encontrado.'; RETURN; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'APR-001', 'Aprendizado & Papéis abre com as abas do módulo',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'É o mapa da organização do trabalho por função. Se não monta, o RH perde atividades, competências e manuais das funções.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar Aprendizado & Papéis pelo menu","resultado_esperado":"Título Aprendizado & Papéis carrega"},
     {"ordem":2,"acao":"Conferir as abas","resultado_esperado":"Funções, Assinaturas, Indicadores, Configurações"}]'::jsonb,
   'O módulo monta com as abas.', NULL),

  (v_mod, 'APR-002', 'Lista de funções e busca',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'A aba Funções lista os cargos com contadores (atividades/competências/EPIs). É a porta para detalhar cada papel.',
   'Cargos cadastrados.',
   '[{"ordem":1,"acao":"Abrir a aba Funções","resultado_esperado":"Cards de cargo com contadores montam"},
     {"ordem":2,"acao":"Buscar uma função","resultado_esperado":"A lista filtra pelo termo"}]'::jsonb,
   'As funções listam e filtram.',
   'Sem cargos: Nenhuma função cadastrada.'),

  (v_mod, 'APR-010', 'Abrir o detalhe de uma função',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O detalhe da função reúne objetivo, escopo, sub-abas (Atividades, Competências, Indicadores, EPIs & Treinamento) — o corpo do papel.',
   'Ao menos uma função na lista.',
   '[{"ordem":1,"acao":"Clicar num cargo","resultado_esperado":"Detalhe da função abre com as sub-abas e o botão Voltar à lista"}]'::jsonb,
   'O detalhe da função monta.', NULL),

  (v_mod, 'APR-020', 'Adicionar uma atividade à função',
   'feliz', 'critica', 'aprovado', 'e2e', NULL,
   'As atividades descrevem o que a função faz. Cadastrá-las é o que dá conteúdo ao papel e alimenta manuais/POPs.',
   'Detalhe de uma função, sub-aba Atividades.',
   '[{"ordem":1,"acao":"Clicar em + Atividade","resultado_esperado":"Formulário de atividade abre"},
     {"ordem":2,"acao":"Informar o Nome (e frequência/complexidade/classificação) e salvar","resultado_esperado":"Atividade cadastrada aparece na lista"}]'::jsonb,
   'A atividade é adicionada à função.',
   'Nome obrigatório.'),

  (v_mod, 'APR-021', 'Adicionar uma competência à função',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'As competências dizem o que a função precisa saber/ser. Cadastrá-las é a base para avaliação e desenvolvimento.',
   'Detalhe de uma função, sub-aba Competências.',
   '[{"ordem":1,"acao":"Clicar em Competência","resultado_esperado":"Formulário de competência abre"},
     {"ordem":2,"acao":"Informar o Nome e o tipo (Técnica/Comportamental/Cognitiva) e salvar","resultado_esperado":"Competência cadastrada aparece na lista"}]'::jsonb,
   'A competência é adicionada à função.', NULL),

  (v_mod, 'APR-030', 'Gerar o manual da função por IA',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'O manual por IA consolida a função num documento e o arquiva. Com a chave configurada, gera e arquiva; sem ela, avisa sem quebrar.',
   'Uma função com conteúdo; chave de IA no ambiente.',
   '[{"ordem":1,"acao":"Clicar em Gerar Manual na função","resultado_esperado":"Processa e conclui (ou avisa a ausência de chave)"},
     {"ordem":2,"acao":"Conferir o resultado","resultado_esperado":"Aviso Manual gerado e arquivado com sucesso! e o manual disponível"}]'::jsonb,
   'A geração de manual responde ou avisa.',
   'Edge Function ai-manual-funcao; arquiva em Documentos (pasta Aprendizado).'),

  (v_mod, 'APR-031', 'Gerar Manual Global exige funções cadastradas',
   'negativo', 'media', 'aprovado', 'e2e', NULL,
   'Sem funções não há o que consolidar. O Gerar Manual Global deve ficar indisponível quando não há cargos.',
   'Ambiente sem cargos cadastrados.',
   '[{"ordem":1,"acao":"Conferir o botão Gerar Manual Global sem cargos","resultado_esperado":"Botão desabilitado"}]'::jsonb,
   'O manual global exige funções.', NULL),

  (v_mod, 'APR-040', 'Assinaturas listam os manuais enviados e seus status',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'A aba Assinaturas acompanha quem já assinou o manual da função — a prova de ciência do colaborador.',
   'Aba Assinaturas.',
   '[{"ordem":1,"acao":"Abrir a aba Assinaturas","resultado_esperado":"Lista de envios com colaborador/cargo/gestor e o status (Aguardando/Concluído)"}]'::jsonb,
   'As assinaturas montam com status.',
   'Sem envios: Nenhum manual enviado para assinatura ainda.'),

  (v_mod, 'APR-041', 'Copiar o link público de assinatura do manual',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'O link público é como o colaborador assina o manual sem login. Deve ser gerado/copiável a partir do envio.',
   'Um envio na aba Assinaturas.',
   '[{"ordem":1,"acao":"Acionar Links num envio","resultado_esperado":"Link público de assinatura disponível para copiar"}]'::jsonb,
   'O link de assinatura é obtido.', NULL),

  (v_mod, 'APR-050', 'Indicadores apontam funções sem atividades/competências',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Os indicadores mostram os buracos: funções sem atividades ou sem competências — onde falta mapear.',
   'Aba Indicadores.',
   '[{"ordem":1,"acao":"Abrir Indicadores","resultado_esperado":"Funções sem Atividades / sem Competências (ou o positivo Todas as funções possuem atividades ✓)"}]'::jsonb,
   'Os indicadores do módulo montam.', NULL),

  (v_mod, 'APR-060', 'Salvar as configurações do módulo',
   'alternativo', 'media', 'aprovado', 'e2e', 'NR-6 (EPI) / NR-1',
   'A configuração define regras (treinamento de EPI obrigatório, nota mínima, reaplicação periódica). Salvar deve persistir.',
   'Aba Configurações.',
   '[{"ordem":1,"acao":"Ajustar a nota mínima e a reaplicação e Salvar Configurações","resultado_esperado":"Aviso de sucesso; escolhas persistem"}]'::jsonb,
   'As configurações do módulo persistem.', NULL),

  (v_mod, 'APR-070', 'Estados vazios de atividades/competências orientam',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'Função nova abre sem atividades/competências. Deve orientar a começar, não exibir erro.',
   'Uma função sem atividades/competências.',
   '[{"ordem":1,"acao":"Abrir uma função vazia","resultado_esperado":"Mensagens Nenhuma atividade/competência cadastrada; sem erro"}]'::jsonb,
   'Os vazios são tratados com orientação.', NULL),

  (v_mod, 'APR-080', 'Dados do módulo isolados por empresa/tenant',
   'negativo', 'alta', 'aprovado', 'e2e', 'LGPD art. 6º',
   'Funções, atividades e assinaturas são dados da empresa. Não podem misturar outra empresa/tenant.',
   'Base com dados de mais de uma empresa.',
   '[{"ordem":1,"acao":"Abrir o módulo autenticado num tenant","resultado_esperado":"Só aparecem funções/assinaturas do tenant do usuário"}]'::jsonb,
   'O escopo por empresa/tenant é respeitado.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Aprendizado & Papéis: antes=%, depois=% (esperado +13)', v_antes, v_depois;
END $doc$;

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'infraestrutura-auth/autenticacao';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo infraestrutura-auth/autenticacao não encontrado.'; RETURN; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'AUTH-001', 'Tela de login monta com os campos e ações',
   'feliz', 'critica', 'aprovado', 'e2e', NULL,
   'A porta de entrada do sistema. Se não monta, ninguém entra.',
   'Sessão deslogada; rota /login.',
   '[{"ordem":1,"acao":"Abrir /login","resultado_esperado":"Título Login; campos E-mail e Senha; botão Entrar; links Esqueceu a senha? e Cadastre sua empresa"}]'::jsonb,
   'A tela de login monta completa.', NULL),

  (v_mod, 'AUTH-002', 'Login com credenciais válidas entra no sistema',
   'feliz', 'critica', 'aprovado', 'e2e', 'LGPD art. 11 (acesso a dado sensível)',
   'É o fluxo que autentica e libera o app. Deve entrar e levar ao destino.',
   'Conta válida.',
   '[{"ordem":1,"acao":"Informar e-mail e senha corretos e clicar em Entrar","resultado_esperado":"Aviso Login realizado com sucesso!; entra no app (rota inicial ou a de origem)"}]'::jsonb,
   'O login válido autentica e redireciona.', NULL),

  (v_mod, 'AUTH-003', 'Login com senha errada mostra erro genérico',
   'negativo', 'critica', 'aprovado', 'e2e', 'Segurança (anti-enumeração)',
   'Errar a senha (ou o e-mail) deve dar a MESMA mensagem genérica — sem revelar se o e-mail existe.',
   'Rota /login.',
   '[{"ordem":1,"acao":"Informar e-mail válido e senha errada e Entrar","resultado_esperado":"Aviso Não foi possível entrar / E-mail ou senha incorretos..."},
     {"ordem":2,"acao":"Informar um e-mail inexistente","resultado_esperado":"A mesma mensagem genérica (não diz que o e-mail não existe)"}]'::jsonb,
   'O erro de login não permite enumerar contas.', NULL),

  (v_mod, 'AUTH-004', 'Campos vazios/ inválidos barram o envio',
   'negativo', 'alta', 'aprovado', 'e2e', NULL,
   'E-mail malformado ou senha curta não podem ser enviados. A validação inline deve barrar antes do envio.',
   'Rota /login.',
   '[{"ordem":1,"acao":"Informar e-mail inválido e senha curta e tentar Entrar","resultado_esperado":"E-mail inválido e Senha deve ter pelo menos 6 caracteres; não envia"}]'::jsonb,
   'A validação do formulário barra entradas inválidas.', NULL),

  (v_mod, 'AUTH-005', 'Mostrar/ocultar a senha',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'O olho revela/oculta a senha — ajuda a digitar certo sem expor por padrão.',
   'Rota /login com senha digitada.',
   '[{"ordem":1,"acao":"Alternar o botão de exibir senha","resultado_esperado":"O campo troca entre oculto e visível"}]'::jsonb,
   'A alternância de visibilidade da senha funciona.', NULL),

  (v_mod, 'AUTH-010', 'A sessão persiste ao recarregar a página',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'Recarregar não pode deslogar. A sessão persistida deve manter o usuário dentro.',
   'Usuário logado.',
   '[{"ordem":1,"acao":"Recarregar a página autenticado","resultado_esperado":"Continua logado (sem voltar ao login)"}]'::jsonb,
   'A sessão sobrevive ao reload.', NULL),

  (v_mod, 'AUTH-011', 'Logout limpa a sessão',
   'feliz', 'alta', 'aprovado', 'e2e', 'LGPD (encerramento de acesso)',
   'Sair precisa encerrar de verdade: depois do logout, rota protegida volta ao login.',
   'Usuário logado.',
   '[{"ordem":1,"acao":"Sair da conta","resultado_esperado":"Sessão encerrada"},
     {"ordem":2,"acao":"Tentar abrir uma rota protegida","resultado_esperado":"Redireciona para /login"}]'::jsonb,
   'O logout encerra a sessão.', NULL),

  (v_mod, 'AUTH-020', 'Rota protegida sem login redireciona para o login',
   'negativo', 'critica', 'aprovado', 'e2e', 'LGPD art. 11',
   'Ninguém acessa dado protegido sem autenticar. Rota protegida sem sessão deve mandar ao login e voltar depois.',
   'Sessão deslogada.',
   '[{"ordem":1,"acao":"Abrir direto uma rota protegida sem login","resultado_esperado":"Redireciona para /login"},
     {"ordem":2,"acao":"Fazer login","resultado_esperado":"Retorna à rota que tentou abrir"}]'::jsonb,
   'A proteção de rota barra o não autenticado.', NULL),

  (v_mod, 'AUTH-021', 'Área de superadmin barra usuário comum',
   'negativo', 'critica', 'aprovado', 'e2e', 'Menor privilégio',
   'As áreas /admin e /academia são só de superadmin. Um usuário comum logado não pode entrar.',
   'Usuário comum logado.',
   '[{"ordem":1,"acao":"Abrir /admin como usuário comum","resultado_esperado":"Tela Acesso Restrito / Esta área é restrita a Super Administradores."}]'::jsonb,
   'A área de superadmin é protegida.', NULL),

  (v_mod, 'AUTH-022', 'Conta bloqueada não acessa o sistema',
   'negativo', 'alta', 'aprovado', 'e2e', 'LGPD / governança',
   'Uma conta bloqueada até autentica, mas não pode usar o sistema — só sair.',
   'Conta bloqueada por um administrador.',
   '[{"ordem":1,"acao":"Entrar com a conta bloqueada","resultado_esperado":"Tela Acesso Bloqueado com a única ação Sair da conta"}]'::jsonb,
   'A conta bloqueada é impedida de usar o sistema.', NULL),

  (v_mod, 'AUTH-030', 'Recuperação de senha envia o link',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Esquecer a senha não pode travar o acesso. Informar o e-mail deve disparar o link de recuperação.',
   'Rota /forgot-password.',
   '[{"ordem":1,"acao":"Informar o e-mail e Enviar link de recuperação","resultado_esperado":"Confirmação Verifique seu e-mail / E-mail enviado!"}]'::jsonb,
   'A recuperação de senha dispara o link.',
   'Não confirma nem nega a existência da conta.'),

  (v_mod, 'AUTH-031', 'Redefinir senha sem sessão de recuperação é barrado',
   'negativo', 'media', 'aprovado', 'e2e', 'Segurança',
   'A tela de nova senha só vale com um link de recuperação válido. Sem ele, deve barrar e oferecer novo link.',
   'Rota /reset-password sem sessão de recuperação.',
   '[{"ordem":1,"acao":"Abrir /reset-password sem link válido","resultado_esperado":"Link inválido ou expirado + Solicitar novo link"}]'::jsonb,
   'A redefinição exige um link válido.',
   'A nova senha exige a política (mín. 12, com complexidade).')

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Autenticação: antes=%, depois=% (esperado +12)', v_antes, v_depois;
END $doc$;

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'infraestrutura-auth/rls';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo infraestrutura-auth/rls não encontrado.'; RETURN; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'RLS-001', 'Tabelas sensíveis têm RLS habilitada',
   'feliz', 'critica', 'aprovado', 'api', 'LGPD art. 46 (segurança)',
   'RLS desligada numa tabela sensível expõe dados a qualquer sessão. A base deve ter RLS ativa em todas as tabelas de negócio sensíveis.',
   'Simular sessão authenticated.',
   '[{"ordem":1,"acao":"Conferir rowsecurity nas tabelas sensíveis (atestados, ponto_diario, férias, psico, benefícios, documentos...)","resultado_esperado":"Todas com RLS habilitada"}]'::jsonb,
   'Nenhuma tabela sensível fica sem RLS.', NULL),

  (v_mod, 'RLS-002', 'Isolamento por tenant: não se lê dado de outra empresa',
   'negativo', 'critica', 'aprovado', 'api', 'LGPD art. 6º / multi-tenant',
   'O sistema é multiempresa. Um usuário de um tenant não pode, em hipótese alguma, ler linhas de outro tenant.',
   'Duas empresas (tenants) com dados; simular usuário do tenant A.',
   '[{"ordem":1,"acao":"Como usuário do tenant A, consultar tabelas de negócio","resultado_esperado":"Só retornam linhas do tenant A; nada do tenant B"}]'::jsonb,
   'O isolamento por tenant é garantido pela RLS.', NULL),

  (v_mod, 'RLS-003', 'Políticas RESTRICTIVE de perfil aplicadas nas tabelas sensíveis',
   'feliz', 'critica', 'aprovado', 'api', 'LGPD art. 6º (necessidade)',
   'A camada de perfil usa políticas RESTRICTIVE perfil_restringe_leitura_* para limitar leitura por escopo do perfil. Cada tabela sensível prevista precisa ter a sua.',
   'Simular usuário com perfil restrito.',
   '[{"ordem":1,"acao":"Conferir a existência das políticas perfil_restringe_leitura_* nas tabelas cobertas","resultado_esperado":"Presentes nas tabelas sensíveis (ponto, férias, saúde, psico, benefícios, documentos)"}]'::jsonb,
   'As políticas RESTRICTIVE de perfil estão presentes.',
   'Alinhado à rotina de QA PERFIL-003 (acusa tabela sensível sem política).'),

  (v_mod, 'RLS-004', 'Dado de saúde só é lido por perfil autorizado',
   'negativo', 'critica', 'aprovado', 'api', 'LGPD art. 11 (dado sensível de saúde)',
   'Atestados, afastamentos e eventos de saúde são dado sensível. Perfil sem escopo de saúde não pode lê-los, mesmo dentro do tenant.',
   'Usuário do tenant com perfil sem escopo de saúde.',
   '[{"ordem":1,"acao":"Consultar atestados/afastamentos/eventos_saude com perfil sem escopo de saúde","resultado_esperado":"Leitura bloqueada pela política RESTRICTIVE"}]'::jsonb,
   'O dado de saúde é protegido por perfil.', NULL),

  (v_mod, 'RLS-005', 'perfil_permite_modulo barra módulo não liberado ao perfil',
   'negativo', 'alta', 'aprovado', 'api', 'Menor privilégio',
   'A função perfil_permite_modulo é o portão de módulo. Um perfil sem o módulo não deve ler as tabelas daquele módulo.',
   'Perfil sem um módulo específico.',
   '[{"ordem":1,"acao":"Consultar tabelas do módulo não liberado ao perfil","resultado_esperado":"Retorno vazio/bloqueado pela camada de perfil"}]'::jsonb,
   'O acesso por módulo respeita o perfil.', NULL),

  (v_mod, 'RLS-006', 'Sessão sem autenticação não lê dado de negócio',
   'negativo', 'critica', 'aprovado', 'api', 'LGPD art. 46',
   'auth.uid() nulo (não autenticado) não pode enxergar dado de negócio. É a linha de base da RLS.',
   'Sessão sem claims (auth.uid() NULL).',
   '[{"ordem":1,"acao":"Consultar tabelas de negócio sem autenticação","resultado_esperado":"Nada é retornado"}]'::jsonb,
   'O anônimo não lê dado de negócio.', NULL),

  (v_mod, 'RLS-007', 'Tabela sensível nova precisa de política de perfil',
   'excecao', 'alta', 'aprovado', 'api', 'LGPD art. 6º',
   'Toda tabela sensível nova tem de entrar na camada de perfil (ou ter exceção documentada). É o que evita vazamento por esquecimento ao crescer o schema.',
   'Rotina de QA que varre tabelas sensíveis.',
   '[{"ordem":1,"acao":"Rodar a checagem de cobertura de perfil (PERFIL-003)","resultado_esperado":"Nenhuma tabela sensível sem política/exceção"}]'::jsonb,
   'A camada de perfil acompanha o crescimento do schema.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'RLS: antes=%, depois=% (esperado +7)', v_antes, v_depois;
END $doc$;

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'infraestrutura-auth/edge-functions';
  IF v_mod IS NULL THEN RAISE NOTICE 'Módulo infraestrutura-auth/edge-functions não encontrado.'; RETURN; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'EDGE-001', 'Rotinas de disparo respeitam a config do ambiente',
   'negativo', 'critica', 'aprovado', 'api', 'Proteção de ambiente',
   'Sem supabase_url/anon_key em app_config, uma rotina de disparo não pode chamar ninguém — é a trava que evita um ambiente falar pelo outro.',
   'app_config sem os valores de disparo.',
   '[{"ordem":1,"acao":"Acionar uma rotina que depende de app_config sem os valores","resultado_esperado":"Não dispara chamada externa; falha/segura de forma controlada"}]'::jsonb,
   'A ausência de config protege o ambiente.', NULL),

  (v_mod, 'EDGE-002', 'seed-e2e-user nunca semeia a produção',
   'negativo', 'critica', 'aprovado', 'api', 'LGPD (produção com dado real)',
   'A conta-robô só pode ser semeada em teste/homologação. A função deve recusar o ref da produção — o pior caso é semear sobre dado real.',
   'Chamada com ref de produção.',
   '[{"ordem":1,"acao":"Chamar seed-e2e-user apontando para o ref de produção","resultado_esperado":"Recusa explícita; nada é semeado na produção"},
     {"ordem":2,"acao":"Chamar para o ref de teste/homologação","resultado_esperado":"Semeia normalmente"}]'::jsonb,
   'A semeadura é barrada na produção.', NULL),

  (v_mod, 'EDGE-003', 'Funções de QA exigem o token QA_E2E_TOKEN',
   'negativo', 'alta', 'aprovado', 'api', 'Segurança',
   'qa-registrar-e2e e qa-cobertura-e2e expõem/gravam dados de QA; sem o token (ou com token errado) devem recusar.',
   'Chamada sem o cabeçalho x-qa-token.',
   '[{"ordem":1,"acao":"Chamar qa-registrar-e2e / qa-cobertura-e2e sem token","resultado_esperado":"Recusa (401/403)"},
     {"ordem":2,"acao":"Chamar com o token correto","resultado_esperado":"Responde normalmente"}]'::jsonb,
   'As funções de QA são fechadas por token.', NULL),

  (v_mod, 'EDGE-004', 'Funções de IA degradam sem a chave, sem quebrar a tela',
   'alternativo', 'media', 'aprovado', 'api', NULL,
   'As funções de IA (feedback, trilha, manual, etc.) dependem de chave externa. Sem ela, devem avisar de forma clara — nunca derrubar a tela que as chama.',
   'Ambiente sem a chave de IA.',
   '[{"ordem":1,"acao":"Acionar uma função de IA sem a chave configurada","resultado_esperado":"Retorna aviso/erro claro; a tela trata sem quebrar"}]'::jsonb,
   'A IA ausente é degradada com elegância.', NULL),

  (v_mod, 'EDGE-005', 'Entrada inválida e CORS/preflight tratados',
   'negativo', 'media', 'aprovado', 'api', NULL,
   'Uma função robusta valida o corpo e responde ao preflight (OPTIONS). Entrada inválida deve dar erro claro, não 500 silencioso.',
   'Chamada com corpo inválido e uma requisição OPTIONS.',
   '[{"ordem":1,"acao":"Enviar corpo inválido a uma função","resultado_esperado":"Erro 4xx com mensagem clara"},
     {"ordem":2,"acao":"Enviar OPTIONS (preflight)","resultado_esperado":"Responde com os cabeçalhos de CORS"}]'::jsonb,
   'Validação de entrada e CORS são tratados.', NULL),

  (v_mod, 'EDGE-006', 'service_role fica só no servidor',
   'negativo', 'critica', 'aprovado', 'api', 'Segurança (segredo)',
   'A chave service_role (bypassa RLS) só pode viver dentro da Edge Function. Ela nunca pode chegar ao cliente/tela.',
   'Inspeção do fluxo cliente ↔ função.',
   '[{"ordem":1,"acao":"Conferir que a tela nunca recebe a service_role","resultado_esperado":"O segredo permanece no servidor; o cliente usa só anon/JWT do usuário"}]'::jsonb,
   'O segredo de serviço não vaza ao cliente.', NULL),

  (v_mod, 'EDGE-007', 'Links por token (assinatura/advertência) têm validade',
   'alternativo', 'media', 'aprovado', 'api', 'Segurança',
   'Links públicos por token (assinatura de manual/experiência, advertência) dão acesso sem login; precisam expirar para não virarem porta aberta.',
   'Função que gera link por token.',
   '[{"ordem":1,"acao":"Gerar um link por token e conferir a expiração","resultado_esperado":"Link válido com prazo (ex.: 7 dias) e recusado após expirar"}]'::jsonb,
   'Os links por token têm validade.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Edge Functions: antes=%, depois=% (esperado +7)', v_antes, v_depois;
END $doc$;

-- =========================================================
-- CONFERÊNCIA (o SQL Editor mostra só o último resultado)
-- Esperado: 9 linhas, uma por módulo, com as contagens abaixo.
-- =========================================================
SELECT m.path AS modulo, count(c.*) AS casos, min(c.codigo) AS primeiro, max(c.codigo) AS ultimo
FROM public.qa_modulos m
JOIN public.qa_casos_teste c ON c.modulo_id = m.id
WHERE m.path IN (
  'jornada-rotina/analise-jornada','pessoas-cultura/contratos-experiencia',
  'pessoas-cultura/cultura-celebracoes','pessoas-cultura/onboarding',
  'sistema/suporte','desenvolvimento-performance/aprendizado-competencias',
  'infraestrutura-auth/autenticacao','infraestrutura-auth/rls',
  'infraestrutura-auth/edge-functions')
GROUP BY m.path ORDER BY m.path;
