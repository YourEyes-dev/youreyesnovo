-- =========================================================
-- QA — Onda 1, lote 2: permissões em tela (perfil restrito) + Academia.
--
-- Plano: docs/PLANO_COBERTURA_CYPRESS.md. Documenta PER-050/051/052 (perfil restrito:
-- controle positivo e bloqueios de Colaboradores, Financeiro, Ponto e Empresa) e liga ao
-- Cypress dois casos que já estavam documentados e sem teste: CFG-002 (usuário comum não
-- recebe aba administrativa em Usuários) e ACAD-030 (Academia restrita ao Super Admin).
-- Specs: cypress/e2e/permissoes.cy.ts e acesso-critico.cy.ts. O usuário restrito é
-- semeado por seed-e2e-user (e-mail fictício, perfil só de Documentos).
--
-- Idempotente: casos com ON CONFLICT (codigo) DO NOTHING; pontes por delete-then-insert.
-- Só dado de QA — sem tabela nova.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'infraestrutura-auth/usuarios-permissoes';
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo infraestrutura-auth/usuarios-permissoes não encontrado — casos não documentados.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PER-050', 'Perfil restrito entra e abre o módulo que o perfil libera',
   'feliz', 'critica', 'aprovado', 'e2e', 'LGPD art. 46 / princípio do menor privilégio',
   'Controle positivo da trava por perfil: o usuário com perfil restrito precisa conseguir entrar e abrir exatamente o que o perfil libera. Sem isso, um teste de bloqueio poderia passar só porque o login quebrou.',
   'Usuário colaborador com perfil que libera apenas Documentos (escopo próprio).',
   '[{"ordem": 1, "acao": "Entrar com o usuário de perfil restrito e abrir /documentos", "resultado_esperado": "O módulo Documentos abre, sem o aviso de Acesso Restrito"}]'::jsonb,
   'O perfil restrito acessa o que o perfil libera.', 'Spec: cypress/e2e/permissoes.cy.ts. Usuário semeado por seed-e2e-user (restrito.e2e@youreyes.local).'),
  (v_mod, 'PER-051', 'Perfil restrito é barrado em Colaboradores',
   'negativo', 'critica', 'aprovado', 'e2e', 'LGPD art. 46 / princípio do menor privilégio',
   'Menor privilégio e LGPD: quem tem perfil sem o módulo Colaboradores não pode ver a lista de colaboradores (dado pessoal e sensível). A tela precisa trancar, não só esconder o menu.',
   'Usuário colaborador com perfil que libera apenas Documentos (escopo próprio).',
   '[{"ordem": 1, "acao": "Entrar com o usuário de perfil restrito e abrir /colaboradores pelo endereço", "resultado_esperado": "Aparece Acesso Restrito com a orientação de falar com o administrador; a lista de colaboradores não monta"}]'::jsonb,
   'Rota de módulo fora do perfil é barrada na tela.', 'Spec: cypress/e2e/permissoes.cy.ts. Usuário semeado por seed-e2e-user (restrito.e2e@youreyes.local).'),
  (v_mod, 'PER-052', 'Perfil restrito é barrado em Financeiro, Ponto e Empresa',
   'negativo', 'critica', 'aprovado', 'e2e', 'LGPD art. 46 / princípio do menor privilégio',
   'Financeiro, Ponto e Empresa concentram dado de folha, jornada e cadastro da empresa. Um perfil que não os inclui nunca pode alcançá-los digitando o endereço.',
   'Usuário colaborador com perfil que libera apenas Documentos (escopo próprio).',
   '[{"ordem": 1, "acao": "Com o usuário de perfil restrito, abrir /financeiro", "resultado_esperado": "Acesso Restrito"}, {"ordem": 2, "acao": "Abrir /ponto", "resultado_esperado": "Acesso Restrito"}, {"ordem": 3, "acao": "Abrir /empresa", "resultado_esperado": "Acesso Restrito"}]'::jsonb,
   'Os módulos administrativos fora do perfil ficam fechados.', 'Spec: cypress/e2e/permissoes.cy.ts. Usuário semeado por seed-e2e-user (restrito.e2e@youreyes.local).')
  ON CONFLICT (codigo) DO NOTHING;
END $doc$;

DO $ponte$
BEGIN
  DELETE FROM public.qa_cobertura_e2e
  WHERE codigo IN ('PER-050', 'PER-051', 'PER-052', 'CFG-002', 'ACAD-030');

  INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
  VALUES
  ('PER-050', 'cypress/e2e/permissoes.cy.ts', 'perfil restrito entra e abre o módulo que o perfil libera'),
  ('PER-051', 'cypress/e2e/permissoes.cy.ts', 'perfil restrito é barrado em Colaboradores'),
  ('PER-052', 'cypress/e2e/permissoes.cy.ts', 'perfil restrito é barrado em Financeiro, Ponto e Empresa'),
  ('CFG-002', 'cypress/e2e/permissoes.cy.ts', 'usuário comum abre Usuários sem nenhuma aba administrativa'),
  ('ACAD-030', 'cypress/e2e/acesso-critico.cy.ts', 'a Academia é restrita ao Super Admin');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Ponte e2e (permissões) não gravada: %', SQLERRM;
END $ponte$;

SELECT 'casos PER-05x documentados' AS item,
       (SELECT count(*)::text FROM public.qa_casos_teste WHERE codigo IN ('PER-050','PER-051','PER-052')) AS valor
UNION ALL SELECT 'pontes do lote 2 ligadas',
       (SELECT count(*)::text FROM public.qa_cobertura_e2e WHERE codigo IN ('PER-050', 'PER-051', 'PER-052', 'CFG-002', 'ACAD-030'));
