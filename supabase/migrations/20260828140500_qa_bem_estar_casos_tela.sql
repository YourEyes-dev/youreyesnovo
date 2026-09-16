-- =========================================================
-- QA — Meu Bem-Estar: primeira documentação do módulo (11 casos)
--
-- Módulo pessoas-cultura/bem-estar, zero casos até aqui.
-- Casos de TELA (nivel e2e) ancorados em src/pages/BemEstar.tsx +
-- components/bem-estar/*: aviso de espaço seguro (privacidade), Mapa de
-- Bem-Estar (radar de 7 eixos), painel do eixo com registro de resposta e
-- eixo especial de gratidão. Módulo de autopercepção — dados pessoais e
-- não punitivos.
--
-- Regra da casa: caso e2e sem spec só gera aviso na guarda.
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'pessoas-cultura/bem-estar';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo pessoas-cultura/bem-estar não encontrado.'; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'BEM-001', 'Meu Bem-Estar abre com o Mapa de Bem-Estar',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O módulo é o espaço de autopercepção do colaborador. Se a tela não monta, some a ferramenta de autoconhecimento.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar Meu Bem-Estar pelo menu","resultado_esperado":"Título Meu Bem-Estar no Trabalho e o Meu Mapa de Bem-Estar carregam"}]'::jsonb,
   'O módulo monta com o mapa de bem-estar.',
   'Âncoras: h1 Meu Bem-Estar no Trabalho; h2 Meu Mapa de Bem-Estar; BemEstarRadar.'),

  (v_mod, 'BEM-002', 'Aviso de espaço seguro é exibido',
   'feliz', 'critica', 'aprovado', 'e2e',
   'NR-1 (riscos psicossociais) / LGPD art. 6º (finalidade)',
   'O contrato de confiança do módulo: nada registrado ali serve para punição. O aviso precisa estar visível para o colaborador se sentir à vontade.',
   'Módulo aberto.',
   '[{"ordem":1,"acao":"Abrir o módulo e ler o aviso de privacidade","resultado_esperado":"Mensagem de Espaço seguro (uso não punitivo) visível"}]'::jsonb,
   'O aviso de espaço seguro é apresentado.',
   'Alert Espaço seguro / reflexões são pessoais.'),

  (v_mod, 'BEM-010', 'Radar mostra os sete eixos de bem-estar',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O radar traduz o bem-estar em eixos (emoções, propósito, relações, autonomia, autorrealização, presença, gratidão). Deve montar com todos os eixos.',
   'Módulo aberto.',
   '[{"ordem":1,"acao":"Conferir o radar do Mapa de Bem-Estar","resultado_esperado":"Os sete eixos aparecem no gráfico"}]'::jsonb,
   'O radar representa os sete eixos.',
   'EIXOS_CONFIG: emoções, propósito, relações, autonomia, autorrealização, presença, gratidão.'),

  (v_mod, 'BEM-011', 'Clicar em um eixo abre o painel do eixo',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'A interação central: clicar num eixo abre o painel para refletir e registrar. Sem isso o radar é só uma figura.',
   'Módulo aberto com o radar montado.',
   '[{"ordem":1,"acao":"Clicar em um eixo do radar","resultado_esperado":"O painel daquele eixo abre"},
     {"ordem":2,"acao":"Conferir o conteúdo do painel","resultado_esperado":"Título e itens de reflexão do eixo escolhido"}]'::jsonb,
   'O painel do eixo abre a partir do radar.',
   'onEixoClick → EixoPanel; texto Clique em qualquer eixo para interagir.'),

  (v_mod, 'BEM-020', 'Registrar uma resposta de reflexão no eixo',
   'feliz', 'critica', 'aprovado', 'e2e', NULL,
   'Registrar a resposta é o que alimenta o mapa e o histórico pessoal. Deve salvar e refletir no eixo.',
   'Painel de um eixo aberto.',
   '[{"ordem":1,"acao":"Responder um item de reflexão do eixo","resultado_esperado":"Resposta aceita"},
     {"ordem":2,"acao":"Salvar","resultado_esperado":"Resposta persistida; o mapa reflete a atualização"}]'::jsonb,
   'A resposta de reflexão é registrada.',
   'onSalvarResposta (salvarResposta).'),

  (v_mod, 'BEM-021', 'Eixo de gratidão permite registrar uma gratidão',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'O eixo de gratidão tem um registro próprio (o que agradeço). Deve aceitar e salvar a gratidão.',
   'Painel do eixo Gratidão aberto.',
   '[{"ordem":1,"acao":"Abrir o eixo de gratidão e escrever uma gratidão","resultado_esperado":"Entrada aceita"},
     {"ordem":2,"acao":"Salvar","resultado_esperado":"Gratidão registrada no eixo"}]'::jsonb,
   'O registro de gratidão funciona no eixo próprio.',
   'onSalvarGratidao (salvarGratidao), só quando selectedEixo === gratidao.'),

  (v_mod, 'BEM-030', 'Fechar o painel volta ao mapa',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'Fechar o painel devolve a visão do radar sem recarregar a tela.',
   'Painel de um eixo aberto.',
   '[{"ordem":1,"acao":"Fechar o painel do eixo","resultado_esperado":"Painel some e o mapa volta ao foco"}]'::jsonb,
   'O fechamento do painel retorna ao mapa.',
   'onClose → setSelectedEixo(null).'),

  (v_mod, 'BEM-040', 'As respostas persistem ao reabrir o módulo',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O valor do módulo é acompanhar a evolução. O que foi registrado precisa continuar lá numa nova visita.',
   'Ao menos uma resposta registrada anteriormente.',
   '[{"ordem":1,"acao":"Sair e reabrir Meu Bem-Estar","resultado_esperado":"O mapa reflete as respostas já registradas"}]'::jsonb,
   'O histórico de bem-estar persiste entre sessões.', NULL),

  (v_mod, 'BEM-050', 'Bem-estar do usuário é privado a ele',
   'negativo', 'critica', 'aprovado', 'e2e',
   'LGPD art. 6º e 11 (dado pessoal sensível; espaço não punitivo)',
   'A promessa de espaço seguro exige isolamento: um usuário não pode ver o mapa de outro. É o alicerce ético do módulo.',
   'Dois usuários com registros distintos.',
   '[{"ordem":1,"acao":"Abrir Meu Bem-Estar com o usuário A","resultado_esperado":"Vê apenas o próprio mapa e respostas"},
     {"ordem":2,"acao":"Confirmar que não há acesso ao mapa de outro colaborador","resultado_esperado":"Dados de terceiros nunca aparecem"}]'::jsonb,
   'O bem-estar registrado é estritamente pessoal.', NULL),

  (v_mod, 'BEM-060', 'Estado de carregamento e vazio sem quebra',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'Primeiro acesso, sem nenhuma resposta, deve mostrar carregamento e depois um mapa neutro — não erro.',
   'Usuário sem respostas registradas.',
   '[{"ordem":1,"acao":"Abrir o módulo pela primeira vez","resultado_esperado":"Carregando e depois mapa neutro; sem erro"}]'::jsonb,
   'Carregamento e vazio são tratados.',
   'Estado Carregando... enquanto isLoading.'),

  (v_mod, 'BEM-070', 'Módulo responde em largura de celular',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'A autopercepção acontece muitas vezes no celular. O radar e o painel de eixo devem se ajustar sem estourar o layout.',
   'Viewport de celular.',
   '[{"ordem":1,"acao":"Abrir o módulo em largura de celular","resultado_esperado":"Radar e painel se ajustam sem quebra de layout"}]'::jsonb,
   'O módulo é utilizável no celular.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Meu Bem-Estar: antes=%, depois=% (esperado +11)', v_antes, v_depois;
END $doc$;
