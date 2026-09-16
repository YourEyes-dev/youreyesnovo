-- =========================================================
-- QA — Ouvidoria: casos complementares (fecha a cobertura da tela)
--
-- A familia OUV ja tinha 19 casos (20260828130100). Faltavam opcoes da
-- tela e cenarios de excecao. Esta migration adiciona 11 casos de TELA
-- (nivel e2e) revisando a tela real (src/pages/Ouvidoria.tsx +
-- components/ouvidoria/* + hooks/useOuvidoria*), cobrindo:
--   · CRUD completo — faltava o EXCLUIR (OUV-028) e a regra de quem pode
--     excluir (OUV-033);
--   · limites do formulario — Assunto 200 / Mensagem 5000 (OUV-007) e
--     anexos ate 5 arquivos de 10MB (OUV-008);
--   · recursos de IA — Pre-analisar no envio (OUV-009) e Gerar sugestoes
--     de acoes (OUV-029), com o comportamento quando a IA esta indisponivel
--     (OUV-041);
--   · visibilidade por perfil — colaborador so ve as proprias (OUV-034);
--   · roteamento automatico no envio (OUV-035) e o Responder que fecha o
--     ciclo mudando o status (OUV-036);
--   · excecao de envio — falha comunicada sem perder o texto (OUV-040),
--     guarda de regressao do erro que existia ao enviar manifestacao.
--
-- Regra da casa: caso e2e documentado sem spec so gera aviso na guarda.
-- Idempotente: ON CONFLICT (codigo) DO NOTHING. So documenta — nao toca dado.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'pessoas-cultura/ouvidoria';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Modulo pessoas-cultura/ouvidoria nao encontrado.'; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  -- ══════════ A) ENVIO — LIMITES E IA ══════════

  (v_mod, 'OUV-007', 'Assunto e Mensagem respeitam os limites de caracteres',
   'negativo', 'media', 'aprovado', 'e2e',
   NULL,
   'O Assunto aceita ate 200 caracteres e a Mensagem ate 5000 (contadores na tela). Passar disso truncaria o registro ou abriria porta para texto abusivo — o campo deve travar no limite.',
   'Aba Enviar aberta.',
   '[{"ordem":1,"acao":"Digitar mais de 200 caracteres no Assunto","resultado_esperado":"O campo trava em 200 e o contador mostra 200/200"},
     {"ordem":2,"acao":"Digitar mais de 5000 caracteres na Mensagem","resultado_esperado":"O campo trava em 5000 e o contador mostra 5000/5000"}]'::jsonb,
   'Nenhum dos campos ultrapassa o limite; os contadores refletem o uso.',
   'Limites reais do formulario de envio (maxLength 200 e 5000).'),

  (v_mod, 'OUV-008', 'Anexos respeitam o limite de 5 arquivos e 10MB cada',
   'negativo', 'media', 'aprovado', 'e2e',
   NULL,
   'A area de anexos aceita ate 5 arquivos, 10MB cada. Acima disso o upload deve ser recusado com aviso — protege o armazenamento e evita travar a fila.',
   'Aba Enviar aberta; arquivos de teste disponiveis (validos e um acima de 10MB).',
   '[{"ordem":1,"acao":"Anexar 5 arquivos validos","resultado_esperado":"Os 5 anexos sao listados"},
     {"ordem":2,"acao":"Tentar anexar um 6o arquivo","resultado_esperado":"O upload e recusado com aviso de limite"},
     {"ordem":3,"acao":"Tentar anexar um arquivo maior que 10MB","resultado_esperado":"O upload e recusado com aviso de tamanho"}]'::jsonb,
   'Nunca mais de 5 anexos, nem arquivo acima de 10MB.',
   'Limites reais da area de anexos (maxFiles 5, maxSize 10MB).'),

  (v_mod, 'OUV-009', 'Pre-analisar a manifestacao com IA antes de enviar',
   'alternativo', 'media', 'aprovado', 'e2e',
   NULL,
   'No proprio formulario, o botao Pre-analisar com IA le tipo, assunto e mensagem e devolve uma leitura (sentimento, categoria e prioridade sugerida) para o manifestante revisar antes de enviar. Com a chave de IA configurada, a analise retorna; sem ela, o aviso e claro.',
   'Aba Enviar com tipo, assunto e mensagem preenchidos.',
   '[{"ordem":1,"acao":"Preencher a manifestacao (tipo, assunto e mensagem)","resultado_esperado":"Campos aceitos"},
     {"ordem":2,"acao":"Clicar em Pre-analisar com IA","resultado_esperado":"A analise aparece (categoria, prioridade e resumo) OU um aviso claro se a IA estiver indisponivel"}]'::jsonb,
   'A pre-analise responde ou avisa — nunca falha em silencio.',
   'Botao Pre-analisar com IA do formulario de envio (componente de analise por IA).'),

  -- ══════════ B) GESTAO — EXCLUIR E ACOES POR IA ══════════

  (v_mod, 'OUV-028', 'Excluir manifestacao com confirmacao',
   'feliz', 'alta', 'aprovado', 'e2e',
   NULL,
   'Fecha o CRUD do modulo: o gestor autorizado remove uma manifestacao (por exemplo, duplicada ou de teste). A exclusao pede confirmacao antes de ser definitiva, para nao apagar por engano.',
   'Perfil administrador; uma manifestacao existente na fila.',
   '[{"ordem":1,"acao":"No card da manifestacao, acionar Excluir (icone de lixeira)","resultado_esperado":"Abre um dialogo de confirmacao"},
     {"ordem":2,"acao":"Confirmar a exclusao","resultado_esperado":"A manifestacao some da lista e deixa de contar nas estatisticas"},
     {"ordem":3,"acao":"Em outra manifestacao, acionar Excluir e Cancelar","resultado_esperado":"Nada e removido"}]'::jsonb,
   'A exclusao so ocorre apos confirmacao e remove a manifestacao da fila.',
   'Card com confirmacao (dialogo) antes de excluir.'),

  (v_mod, 'OUV-029', 'Gerar sugestoes de acoes com IA e criar as selecionadas',
   'alternativo', 'alta', 'aprovado', 'e2e',
   NULL,
   'A partir da manifestacao, Gerar Sugestoes com IA propoe ate 5 acoes no formato 5W2H (com GUT). O gestor seleciona as pertinentes e cria de uma vez no Plano de Acao, vinculadas a manifestacao — da escuta a providencia sem redigitar.',
   'Perfil gestor; manifestacao com texto substancial; recurso de IA disponivel.',
   '[{"ordem":1,"acao":"Abrir Criar Acoes na manifestacao","resultado_esperado":"O modal de acoes abre com o texto da manifestacao"},
     {"ordem":2,"acao":"Clicar em Gerar Sugestoes com IA","resultado_esperado":"Ate 5 acoes sugeridas aparecem (ou aviso claro se a IA estiver indisponivel)"},
     {"ordem":3,"acao":"Selecionar uma ou mais sugestoes e criar","resultado_esperado":"As acoes sao criadas no Plano de Acao com vinculo a manifestacao"},
     {"ordem":4,"acao":"Tentar criar sem selecionar nenhuma","resultado_esperado":"Nenhuma acao e criada"}]'::jsonb,
   'As sugestoes viram acoes rastreaveis; nada e criado sem selecao.',
   'Modal de acoes da Ouvidoria (sugestoes por IA + Plano de Acao).'),

  -- ══════════ C) PERMISSOES E VISIBILIDADE ══════════

  (v_mod, 'OUV-033', 'Excluir manifestacao e restrito ao administrador',
   'negativo', 'alta', 'aprovado', 'e2e',
   'LGPD (controle de acesso a dado sensivel; trilha)',
   'Remover manifestacao — inclusive denuncia — e acao de administrador. Perfis abaixo de administrador nao podem excluir, nem pela tela nem por baixo dela (a politica de exclusao do banco recusa).',
   'Tres contas no mesmo tenant: administrador, gestor (manager) e colaborador comum.',
   '[{"ordem":1,"acao":"Com o administrador, excluir uma manifestacao","resultado_esperado":"Exclusao permitida"},
     {"ordem":2,"acao":"Com gestor (manager) ou colaborador, tentar excluir a mesma manifestacao","resultado_esperado":"A acao esta ausente ou e recusada; a manifestacao permanece"}]'::jsonb,
   'Somente o administrador exclui; os demais nao conseguem remover.',
   'Regra de exclusao restrita a administrador (has_minimum_role admin).'),

  (v_mod, 'OUV-034', 'Colaborador comum ve apenas as proprias manifestacoes identificadas',
   'negativo', 'alta', 'aprovado', 'e2e',
   'LGPD (confidencialidade; minimizacao)',
   'Na fila, um colaborador comum nao pode ver manifestacoes de outras pessoas — enxerga so as proprias, nao anonimas. Ver a fila alheia seria vazamento de dado sensivel.',
   'Colaborador comum autenticado; manifestacoes de varios autores no tenant.',
   '[{"ordem":1,"acao":"Com colaborador comum, abrir a aba Manifestacoes","resultado_esperado":"Aparecem apenas as manifestacoes identificadas do proprio usuario"},
     {"ordem":2,"acao":"Com perfil gestor (manager ou acima), abrir a mesma aba","resultado_esperado":"Aparecem todas as manifestacoes do tenant"}]'::jsonb,
   'A visibilidade da fila respeita o perfil; colaborador nao ve manifestacao de terceiros.',
   'Politicas de leitura: propria (colaborador) versus todas do tenant (manager+).'),

  -- ══════════ D) ROTEAMENTO E CICLO ══════════

  (v_mod, 'OUV-035', 'Roteamento automatico direciona a manifestacao no envio',
   'alternativo', 'media', 'aprovado', 'e2e',
   NULL,
   'Havendo roteamento configurado para o tipo, a manifestacao ja nasce direcionada — responsavel e departamento de destino preenchidos. A triagem deixa de depender de alguem lembrar de encaminhar.',
   'Perfil gestor; roteamento configurado para um tipo (exemplo: denuncia direcionada a Compliance).',
   '[{"ordem":1,"acao":"Enviar uma manifestacao do tipo que tem roteamento configurado","resultado_esperado":"Envio confirmado"},
     {"ordem":2,"acao":"Abrir a manifestacao na gestao","resultado_esperado":"Responsavel e departamento de destino ja vem preenchidos conforme o roteamento"}]'::jsonb,
   'O tipo roteado chega direcionado, sem passo manual.',
   'Consulta ao roteamento no momento do envio.'),

  (v_mod, 'OUV-036', 'Responder marca a manifestacao como respondida',
   'alternativo', 'media', 'aprovado', 'e2e',
   NULL,
   'Ao enviar a resposta, o status passa a respondido automaticamente e o retorno fica registrado com quem respondeu e quando — o ciclo nao fica pendente por esquecimento de mudar o status.',
   'Perfil gestor; uma manifestacao em tratamento.',
   '[{"ordem":1,"acao":"Abrir a manifestacao e enviar uma resposta","resultado_esperado":"Resposta registrada"},
     {"ordem":2,"acao":"Conferir o status da manifestacao","resultado_esperado":"Status passou para respondido"},
     {"ordem":3,"acao":"Conferir o retorno","resultado_esperado":"Mostra o autor da resposta e a data"}]'::jsonb,
   'Responder fecha o ciclo e o status reflete isso.',
   'Ao responder, o status vira respondido e grava autor e data.'),

  -- ══════════ E) EXCECOES ══════════

  (v_mod, 'OUV-040', 'Falha ao enviar mostra mensagem clara sem perder o texto',
   'excecao', 'alta', 'aprovado', 'e2e',
   NULL,
   'Se o envio falhar (indisponibilidade ou recusa do backend), a tela mostra um erro claro e mantem o que foi digitado — o manifestante nao perde o conteudo nem fica sem saber o que aconteceu, e nunca ve uma confirmacao falsa de sucesso.',
   'Aba Enviar preenchida.',
   '[{"ordem":1,"acao":"Tentar enviar numa condicao de falha","resultado_esperado":"Aparece uma mensagem de erro clara"},
     {"ordem":2,"acao":"Observar o formulario apos a falha","resultado_esperado":"O tipo, o assunto e a mensagem continuam preenchidos"},
     {"ordem":3,"acao":"Confirmar que nao houve confirmacao de sucesso","resultado_esperado":"Nenhuma mensagem de enviado com sucesso e exibida"}]'::jsonb,
   'Erro de envio e comunicado; o conteudo e preservado; sem sucesso enganoso.',
   'Guarda de regressao: houve um erro de envio corrigido; este caso garante que qualquer falha futura seja comunicada, nao silenciosa.'),

  (v_mod, 'OUV-041', 'Recurso de IA sem chave configurada avisa com clareza',
   'excecao', 'media', 'aprovado', 'e2e',
   NULL,
   'Se a chave de IA nao estiver configurada no ambiente, os recursos de IA (pre-analise e sugestao de acoes) devem recusar com aviso claro, sem quebrar a tela e sem deixar o usuario no escuro — o fluxo manual continua disponivel.',
   'Ambiente sem a chave de IA configurada.',
   '[{"ordem":1,"acao":"Acionar Pre-analisar com IA num ambiente sem a chave","resultado_esperado":"Aviso claro de recurso de IA indisponivel"},
     {"ordem":2,"acao":"Acionar Gerar Sugestoes com IA no mesmo ambiente","resultado_esperado":"Aviso claro, sem quebrar a tela"},
     {"ordem":3,"acao":"Continuar o tratamento manualmente (responder, mudar status, criar acao a mao)","resultado_esperado":"O fluxo manual segue funcionando"}]'::jsonb,
   'IA indisponivel vira aviso, nao erro silencioso; o fluxo manual permanece.',
   'Guarda de regressao: a chave de IA precisa estar cadastrada por ambiente; sem ela o aviso tem de ser claro.')

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Ouvidoria: casos antes=%, depois=% (esperado +11 na primeira execucao)', v_antes, v_depois;
END $doc$;
