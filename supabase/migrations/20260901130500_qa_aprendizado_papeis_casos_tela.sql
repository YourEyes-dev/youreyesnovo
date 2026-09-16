-- =========================================================
-- QA — Aprendizado & Papéis: primeira documentação do módulo (13 casos)
--
-- Módulo desenvolvimento-performance/aprendizado-competencias, zero casos.
-- Casos de TELA (nivel e2e) ancorados em src/pages/AprendizadoPapeis.tsx +
-- components/aprendizado/*: mapeamento organizacional por função — atividades,
-- competências, EPIs/treinamentos, geração de manuais e POPs por IA,
-- assinaturas de manuais e configurações. Abas Funções / Assinaturas /
-- Indicadores / Configurações.
--
-- Regra da casa: caso e2e sem spec só gera aviso na guarda.
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'desenvolvimento-performance/aprendizado-competencias';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo desenvolvimento-performance/aprendizado-competencias não encontrado.'; END IF;
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
