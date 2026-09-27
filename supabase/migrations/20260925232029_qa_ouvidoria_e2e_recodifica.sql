-- =====================================================================
-- QA — Ouvidoria: reconcilia os testes de tela com a Documentação (e2e)
--
-- Conflito de código a resolver:
--   · A migration 0828 documentou OUV-003/004/005 como casos de TELA (e2e):
--     "os cinco tipos aparecem", "bloqueia envio sem assunto/mensagem".
--   · A migration 0903 RECLASSIFICOU esses mesmos códigos para 'api' (o motor
--     passou a verificar a regra no banco: CHECK dos tipos, NOT NULL do
--     assunto/mensagem).
--   · A migration 0909 criou pontes e2e apontando para eles — que já eram api.
-- Resultado na guarda (verificar-cobertura-e2e): os 3 it() de tela viram
-- "inventados" (sem caso e2e) e as pontes viram "órfãs" → a esteira reprova.
--
-- Correção (regra da casa: documentação → teste; não apagar teste de tela
-- válido): os 3 it() testam UI que o motor NÃO cobre (seletor mostra os 5
-- tipos; botão Enviar desabilitado). Então ganham casos e2e PRÓPRIOS
-- (OUV-050/051/052) e as pontes passam a apontar para eles. OUV-003/004/005
-- seguem como casos de motor (api). Nenhum it() do Cypress muda.
--
-- Idempotente. qa_cobertura_e2e tem UNIQUE(spec, teste): por isso a ponte
-- antiga é REMOVIDA antes de a nova entrar.
-- =====================================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'pessoas-cultura/ouvidoria';
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo pessoas-cultura/ouvidoria não encontrado — nada a fazer.';
    RETURN;
  END IF;

  -- 1) Casos e2e próprios para os 3 testes de tela (cobrem a UI).
  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
    (v_mod, 'OUV-050', 'Seletor mostra os cinco tipos de manifestação (tela)',
     'feliz', 'media', 'aprovado', 'e2e', NULL,
     'A tipologia (sugestão, reclamação, denúncia, elogio, dúvida) precisa aparecer no seletor da tela de envio; tipo faltando é canal fechado sem aviso.',
     'Aba Enviar aberta.',
     '[{"ordem":1,"acao":"Abrir a aba Enviar e olhar o seletor de Tipo de Manifestação","resultado_esperado":"Sugestão, Reclamação, Denúncia, Elogio e Dúvida visíveis"}]'::jsonb,
     'Os cinco tipos aparecem para escolha na tela.',
     'Cobre a UI. A regra no banco (CHECK dos tipos) é o caso OUV-003 (motor).'),
    (v_mod, 'OUV-051', 'Tela bloqueia o envio sem assunto',
     'negativo', 'alta', 'aprovado', 'e2e', NULL,
     'Assunto é obrigatório; a tela deve manter o botão Enviar desabilitado enquanto ele estiver vazio.',
     'Aba Enviar aberta.',
     '[{"ordem":1,"acao":"Selecionar um tipo e preencher a mensagem, deixando o Assunto vazio","resultado_esperado":"Botão Enviar Manifestação desabilitado"}]'::jsonb,
     'Não há envio sem assunto (trava de tela).',
     'Cobre a UI. A regra no banco (NOT NULL) é o caso OUV-004 (motor).'),
    (v_mod, 'OUV-052', 'Tela bloqueia o envio sem mensagem',
     'negativo', 'alta', 'aprovado', 'e2e', NULL,
     'Mensagem é o conteúdo da manifestação; a tela deve manter o botão Enviar desabilitado enquanto ela estiver vazia.',
     'Aba Enviar aberta.',
     '[{"ordem":1,"acao":"Selecionar um tipo e preencher o assunto, deixando a Mensagem vazia","resultado_esperado":"Botão Enviar Manifestação desabilitado"}]'::jsonb,
     'Não há envio sem mensagem (trava de tela).',
     'Cobre a UI. A regra no banco (NOT NULL) é o caso OUV-005 (motor).')
  ON CONFLICT (codigo) DO NOTHING;

  -- 2) Repontar as pontes: remove as antigas (para o UNIQUE(spec,teste)) e
  --    liga os it() aos casos e2e novos.
  DELETE FROM public.qa_cobertura_e2e
   WHERE codigo IN ('OUV-003','OUV-004','OUV-005')
     AND spec = 'cypress/e2e/ouvidoria.cy.ts';

  INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste) VALUES
    ('OUV-050', 'cypress/e2e/ouvidoria.cy.ts', 'mostra os cinco tipos de manifestação'),
    ('OUV-051', 'cypress/e2e/ouvidoria.cy.ts', 'bloqueia o envio sem assunto'),
    ('OUV-052', 'cypress/e2e/ouvidoria.cy.ts', 'bloqueia o envio sem mensagem')
  ON CONFLICT (codigo) DO NOTHING;

  RAISE NOTICE 'OK: OUV-050/051/052 (e2e) documentados e pontes repontadas.';
END $doc$;
