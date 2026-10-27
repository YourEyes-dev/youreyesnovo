-- =========================================================
-- QA — Perfil de acesso x tela Início: casos de TELA (nível e2e) PERFIL-022..025
--
-- Complementa o PERFIL-021 (api, estrutura do banco) com a prova no navegador:
--   PERFIL-022  editor de perfil oferece "Tela inicial" com os quatro blocos
--   PERFIL-023  perfil sem blocos vê só a saudação (sem números nem alertas)
--   PERFIL-024  cabeçalho mostra o nome do perfil, não o papel técnico "Gestor"
--   PERFIL-025  dono continua vendo o painel completo (controle positivo)
-- Spec: cypress/e2e/perfis-tela-inicial.cy.ts. O usuário restrito é o já semeado por
-- seed-e2e-user (perfil "E2E Restrito (Cypress)", agora com inicio_blocos vazio).
--
-- Idempotente: casos com ON CONFLICT (codigo) DO NOTHING; pontes por delete-then-insert.
-- Só dado de QA — sem tabela nova.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid;
BEGIN
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'seguranca-acesso/perfis' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; PERFIL-022..025 nao documentados.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PERFIL-022', 'Editor de perfil oferece a seção Tela inicial com os quatro blocos',
   'feliz', 'alta', 'aprovado', 'e2e', 'LGPD art. 46 / princípio do menor privilégio',
   'O administrador precisa ter onde escolher o que cada perfil vê ao entrar. Um perfil NOVO nasce sem nenhum bloco marcado: informação da empresa só aparece se for liberada de propósito.',
   'Conta-robô (owner) da Empresa Staging.',
   '[{"ordem": 1, "acao": "Abrir Usuários, aba Perfis & Acessos, e clicar em Novo Perfil", "resultado_esperado": "O formulário abre"}, {"ordem": 2, "acao": "Olhar a seção Tela inicial (Início) em Informações gerais", "resultado_esperado": "Quatro opções (pilares, indicadores, pendências, alertas críticos), todas desmarcadas"}]'::jsonb,
   'Seção presente, com os quatro blocos desmarcados no perfil novo.', 'Spec: cypress/e2e/perfis-tela-inicial.cy.ts. O teste abre e cancela o formulário; não grava perfil.'),
  (v_mod, 'PERFIL-023', 'Perfil sem blocos vê só a saudação na tela Início',
   'negativo', 'critica', 'aprovado', 'e2e', 'LGPD art. 46 / princípio do menor privilégio',
   'Achado de campo (10/2026): a tela Início mostrava números e alertas da empresa a qualquer usuário. Com o perfil sem blocos, nada disso pode ser montado na tela.',
   'Usuário restrito semeado (perfil E2E Restrito, inicio_blocos vazio).',
   '[{"ordem": 1, "acao": "Entrar com o usuário restrito e abrir o Início", "resultado_esperado": "Aparece Olá, [nome] e a orientação de usar o menu"}, {"ordem": 2, "acao": "Procurar Governança do Trabalho Humano, KPIs Operacionais, Colaboradores Ativos, Pendências e Alertas Críticos", "resultado_esperado": "Nenhum existe na página"}]'::jsonb,
   'Só a saudação; sem números nem alertas da empresa.', 'Spec: cypress/e2e/perfis-tela-inicial.cy.ts.'),
  (v_mod, 'PERFIL-024', 'Cabeçalho mostra o nome do perfil de acesso, não o papel técnico',
   'feliz', 'alta', 'aprovado', 'e2e', 'Clareza do acesso concedido',
   'O cabeçalho mostrava Gestor (papel técnico) para quem tinha um perfil básico criado pelo cliente. Deve mostrar o nome do perfil de acesso.',
   'Usuário restrito semeado (perfil E2E Restrito (Cypress), sem cargo cadastrado).',
   '[{"ordem": 1, "acao": "Entrar com o usuário restrito e olhar o cabeçalho", "resultado_esperado": "Aparece E2E Restrito (Cypress) e não aparece Gestor"}]'::jsonb,
   'Nome do perfil no cabeçalho.', 'Spec: cypress/e2e/perfis-tela-inicial.cy.ts.'),
  (v_mod, 'PERFIL-025', 'Dono continua vendo o painel completo na tela Início',
   'feliz', 'critica', 'aprovado', 'e2e', 'Controle positivo da trava por perfil',
   'Controle positivo: sem ele, o teste de bloqueio poderia passar só porque o painel quebrou. O dono (e o Super Admin) não são afetados pela configuração de blocos.',
   'Conta-robô (owner) da Empresa Staging.',
   '[{"ordem": 1, "acao": "Entrar com a conta-robô e abrir o Início", "resultado_esperado": "Dashboard completo: KPIs Operacionais, Pendências e Alertas Críticos"}]'::jsonb,
   'Painel completo para o dono.', 'Spec: cypress/e2e/perfis-tela-inicial.cy.ts.')
  ON CONFLICT (codigo) DO NOTHING;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao PERFIL-022..025 nao registrada: %', SQLERRM;
END $doc$;

DO $ponte$
BEGIN
  DELETE FROM public.qa_cobertura_e2e
  WHERE codigo IN ('PERFIL-022', 'PERFIL-023', 'PERFIL-024', 'PERFIL-025');

  INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
  VALUES
  ('PERFIL-022', 'cypress/e2e/perfis-tela-inicial.cy.ts', 'o editor de perfil oferece a seção Tela inicial com os quatro blocos, todos desmarcados no perfil novo'),
  ('PERFIL-023', 'cypress/e2e/perfis-tela-inicial.cy.ts', 'perfil sem blocos vê só a saudação na tela Início, sem números nem alertas da empresa'),
  ('PERFIL-024', 'cypress/e2e/perfis-tela-inicial.cy.ts', 'o cabeçalho mostra o nome do perfil de acesso, não o papel técnico'),
  ('PERFIL-025', 'cypress/e2e/perfis-tela-inicial.cy.ts', 'o dono continua vendo o painel completo na tela Início');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Ponte e2e (tela inicial) nao gravada: %', SQLERRM;
END $ponte$;
