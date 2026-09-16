-- =========================================================
-- QA — Saúde Ocupacional (ASO): primeira documentação do módulo (13 casos)
--
-- Módulo jornada-rotina/saude-ocupacional, zero casos até aqui.
-- Casos de TELA (nivel e2e) ancorados em src/pages/SaudeOcupacional.tsx +
-- components/atestados/AtestadoForm: cards Total de ASOs / ASOs Vencidos /
-- A Vencer (30 dias), lista filtrada por tipo ocupacional, busca por
-- colaborador ou médico, "Novo ASO" (subtipos admissional/periódico/
-- demissional), controle de vencimento e status.
--
-- Regra da casa: caso e2e sem spec só gera aviso na guarda.
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'jornada-rotina/saude-ocupacional';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo jornada-rotina/saude-ocupacional não encontrado.'; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'ASO-001', 'Tela de Saúde Ocupacional abre com o painel de ASOs',
   'feliz', 'alta', 'aprovado', 'e2e',
   'NR-7 (PCMSO) / eSocial S-2220',
   'O módulo controla os exames ocupacionais (ASO) e sua periodicidade. Se a tela não monta, o RH perde a gestão do PCMSO.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar Saúde Ocupacional pelo menu","resultado_esperado":"Título Saúde Ocupacional (ASO) e painel carregam"},
     {"ordem":2,"acao":"Conferir os cards de resumo","resultado_esperado":"Total de ASOs, ASOs Vencidos e A Vencer (30 dias) presentes"}]'::jsonb,
   'O painel de ASOs monta com os cards de resumo.',
   'Âncoras: h1 Saúde Ocupacional (ASO); cards Total de ASOs / ASOs Vencidos / A Vencer (30 dias).'),

  (v_mod, 'ASO-002', 'Cards de resumo refletem os ASOs cadastrados',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'Os cards são a leitura rápida de compliance: quantos exames existem, quantos venceram, quantos vencem em 30 dias. Precisam bater com a lista.',
   'Alguns ASOs cadastrados com datas variadas.',
   '[{"ordem":1,"acao":"Conferir o número de Total de ASOs","resultado_esperado":"Igual à contagem de registros ocupacionais"},
     {"ordem":2,"acao":"Conferir ASOs Vencidos e A Vencer (30 dias)","resultado_esperado":"Coerentes com as datas de vencimento da lista"}]'::jsonb,
   'Os indicadores de vencimento são consistentes com os dados.', NULL),

  (v_mod, 'ASO-010', 'Registrar um novo ASO',
   'feliz', 'critica', 'aprovado', 'e2e',
   'NR-7 (PCMSO)',
   'Registrar o ASO é o que traz o exame para o controle. O formulário deve abrir, aceitar os dados e o exame passar a constar na lista.',
   'Perfil com permissão; colaborador cadastrado.',
   '[{"ordem":1,"acao":"Clicar em Novo ASO","resultado_esperado":"Formulário de ASO abre"},
     {"ordem":2,"acao":"Selecionar colaborador, subtipo e data do exame e salvar","resultado_esperado":"ASO registrado aparece na lista"}]'::jsonb,
   'O ASO é registrado e listado.',
   'Botão Novo ASO abre AtestadoForm (tipo ocupacional).'),

  (v_mod, 'ASO-011', 'Escolher o subtipo do exame (admissional, periódico, demissional)',
   'feliz', 'alta', 'aprovado', 'e2e',
   'NR-7 (tipos de exame do PCMSO)',
   'O subtipo do ASO define a finalidade e a periodicidade. As opções precisam estar disponíveis e persistir no registro.',
   'Formulário de ASO aberto.',
   '[{"ordem":1,"acao":"Selecionar o subtipo do exame","resultado_esperado":"Opções admissional, periódico e demissional disponíveis"},
     {"ordem":2,"acao":"Salvar e reabrir o registro","resultado_esperado":"O subtipo escolhido é exibido na lista"}]'::jsonb,
   'O subtipo do exame é registrado e refletido.',
   'subtipo_ocupacional: periodico / admissional / demissional.'),

  (v_mod, 'ASO-012', 'Bloquear ASO sem colaborador ou sem data do exame',
   'negativo', 'alta', 'aprovado', 'e2e', NULL,
   'ASO sem titular ou sem data não controla vencimento nem serve ao eSocial. O formulário deve exigir os campos essenciais.',
   'Formulário de ASO aberto.',
   '[{"ordem":1,"acao":"Deixar colaborador ou data do exame em branco","resultado_esperado":"—"},
     {"ordem":2,"acao":"Tentar salvar","resultado_esperado":"Sistema impede e aponta os campos obrigatórios"}]'::jsonb,
   'Não há registro de ASO sem os dados essenciais.', NULL),

  (v_mod, 'ASO-020', 'Buscar ASO por colaborador ou médico',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'A busca localiza o exame de uma pessoa ou do profissional que emitiu. Sem ela, achar um ASO numa base grande é inviável.',
   'ASOs cadastrados com nomes distintos.',
   '[{"ordem":1,"acao":"Digitar o nome de um colaborador no campo de busca","resultado_esperado":"A lista filtra para os ASOs desse colaborador"},
     {"ordem":2,"acao":"Buscar pelo nome do médico","resultado_esperado":"A lista filtra pelos exames do profissional"}]'::jsonb,
   'A busca por colaborador ou médico filtra a lista.',
   'placeholder Buscar por colaborador ou médico...'),

  (v_mod, 'ASO-021', 'Busca sem resultado mostra mensagem, não erro',
   'negativo', 'media', 'aprovado', 'e2e', NULL,
   'Buscar um nome inexistente deve resultar em lista vazia orientativa, não em quebra da tabela.',
   'Painel de ASOs aberto.',
   '[{"ordem":1,"acao":"Buscar um termo que não existe","resultado_esperado":"Mensagem Nenhum registro de ASO encontrado; sem erro"}]'::jsonb,
   'A busca sem resultado é tratada.',
   'Texto Nenhum registro de ASO encontrado.'),

  (v_mod, 'ASO-030', 'Status de vencimento classifica cada ASO',
   'feliz', 'critica', 'aprovado', 'e2e',
   'NR-7 (periodicidade dos exames)',
   'Regular, Próximo ao Vencimento e Vencido dizem ao RH o que agir. A classificação deve corresponder às datas.',
   'ASOs com datas que caiam em cada faixa.',
   '[{"ordem":1,"acao":"Conferir um ASO com vencimento futuro distante","resultado_esperado":"Status Regular"},
     {"ordem":2,"acao":"Conferir um ASO a vencer em até 30 dias","resultado_esperado":"Status Próximo ao Vencimento"},
     {"ordem":3,"acao":"Conferir um ASO com vencimento passado","resultado_esperado":"Status Vencido"}]'::jsonb,
   'O status de vencimento reflete corretamente a data.',
   'getStatusVencimento: Regular / Próximo ao Vencimento / Vencido.'),

  (v_mod, 'ASO-031', 'Próximo vencimento calculado a partir da data do exame',
   'feliz', 'alta', 'aprovado', 'e2e',
   'NR-7',
   'A coluna Próximo Vencimento orienta o agendamento do próximo exame. Deve derivar da data de emissão.',
   'ASO periódico cadastrado.',
   '[{"ordem":1,"acao":"Conferir a coluna Próximo Vencimento de um ASO periódico","resultado_esperado":"Data coerente com a periodicidade a partir da emissão"}]'::jsonb,
   'O próximo vencimento é calculado de forma consistente.',
   'getProximoVencimento (periódico ~1 ano).'),

  (v_mod, 'ASO-040', 'Apenas exames do tipo ocupacional aparecem no módulo',
   'negativo', 'alta', 'aprovado', 'e2e',
   'LGPD art. 11 (dado de saúde é sensível)',
   'Este módulo é do ASO (ocupacional), não do atestado clínico. Atestados de afastamento não devem vazar para cá.',
   'Base com atestados ocupacionais e não ocupacionais.',
   '[{"ordem":1,"acao":"Abrir a lista de Saúde Ocupacional","resultado_esperado":"Somente registros do tipo ocupacional aparecem"},
     {"ordem":2,"acao":"Conferir que atestados clínicos comuns não aparecem aqui","resultado_esperado":"Ausentes deste módulo"}]'::jsonb,
   'O módulo isola os exames ocupacionais.',
   'asos = atestados.filter(a => a.tipo === ocupacional).'),

  (v_mod, 'ASO-050', 'Painel vazio (sem ASOs) mostra estado orientativo',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Empresa nova sem exames deve ver um painel zerado e coerente, não erro nem números quebrados.',
   'Ambiente sem ASOs cadastrados.',
   '[{"ordem":1,"acao":"Abrir o módulo sem ASOs","resultado_esperado":"Cards zerados e lista com mensagem de vazio; sem erro"}]'::jsonb,
   'O estado vazio é tratado.', NULL),

  (v_mod, 'ASO-060', 'Acesso ao módulo respeita o perfil',
   'negativo', 'alta', 'aprovado', 'e2e',
   'LGPD art. 11 (dado de saúde ocupacional)',
   'Dados de saúde ocupacional são sensíveis. Quem não tem o módulo não deve alcançá-lo pela navegação.',
   'Conta sem permissão ao módulo.',
   '[{"ordem":1,"acao":"Tentar abrir Saúde Ocupacional sem permissão","resultado_esperado":"Acesso negado/ausente; sem dados de exame expostos"}]'::jsonb,
   'O módulo respeita a camada de acesso por perfil.', NULL),

  (v_mod, 'ASO-070', 'Painel responde em largura de celular',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'O RH consulta vencimentos no celular. Cards e tabela devem se ajustar com rolagem horizontal quando preciso, sem estourar o layout.',
   'Viewport de celular.',
   '[{"ordem":1,"acao":"Abrir o módulo em largura de celular","resultado_esperado":"Cards empilham e a tabela rola sem quebrar o layout"}]'::jsonb,
   'O painel é utilizável no celular.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Saúde Ocupacional (ASO): antes=%, depois=% (esperado +13)', v_antes, v_depois;
END $doc$;
