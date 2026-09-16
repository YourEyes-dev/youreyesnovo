-- =========================================================
-- QA — Edge Functions: primeira documentação do módulo (7 casos)
--
-- Módulo infraestrutura-auth/edge-functions, zero casos até aqui.
-- Casos de INFRAESTRUTURA (nivel api): documentam as garantias das Edge
-- Functions — proteção de ambiente (app_config), recusa de produção,
-- segredos (QA_E2E_TOKEN, service_role), degradação sem chave de IA e
-- tratamento de CORS/erros. Rotina do motor a implementar.
--
-- Regra da casa: caso api sem rotina fica 'nao_implementado' (não é erro).
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'infraestrutura-auth/edge-functions';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo infraestrutura-auth/edge-functions não encontrado.'; END IF;
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
