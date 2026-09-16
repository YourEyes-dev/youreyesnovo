-- =========================================================
-- QA — Contratos de Experiência: primeira documentação do módulo (14 casos)
--
-- Módulo pessoas-cultura/contratos-experiencia, zero casos até aqui.
-- Casos de TELA (nivel e2e) ancorados em src/pages/ContratosExperiencia.tsx:
-- painel de ciclo de vida do contrato de experiência (CLT art. 445), abas
-- Painel / Configuração da Empresa, KPIs de vencimento, ações Prorrogar /
-- Efetivar / Encerrar / Gerar Documento e a configuração de períodos.
--
-- Regra da casa: caso e2e sem spec só gera aviso na guarda.
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'pessoas-cultura/contratos-experiencia';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo pessoas-cultura/contratos-experiencia não encontrado.'; END IF;
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
