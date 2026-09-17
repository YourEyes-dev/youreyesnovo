-- =========================================================
-- QA — Usuários ganha documentação de TELA (nível e2e) + ponte
--
-- A tela de Usuários (/usuarios) — identidades, vínculos e ciclo de vida —
-- já tem cobertura de MOTOR (o módulo infraestrutura-auth/usuarios-permissoes,
-- com 59 casos api de permissão/isolamento). Faltava a TELA. Mesmo passo de
-- Metas/Férias/Colaboradores/Financeiro: o módulo monta, as métricas e os
-- filtros aparecem, o modal de Novo Usuário abre e o vazio orienta.
--
-- Prefixo USR-TELA- não colide com os códigos de motor (USR-*, CTX-*, ISOL-*,
-- PER-*, VIN-*). Todos os casos são DATA-INDEPENDENTES (sem fixtures).
--
-- Módulo: garante a linha (idempotente) para não depender da ordem de outra
-- sessão — em teste ela já existe (20260916160000); aqui é ON CONFLICT DO NOTHING.
-- =========================================================

SET lock_timeout = '10s';

-- ══════════════════════════════════════════════════════════
-- USUÁRIOS  (infraestrutura-auth/usuarios-permissoes)  — rota /usuarios
-- ══════════════════════════════════════════════════════════
DO $doc$
DECLARE v_sec uuid; v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_sec FROM public.qa_modulos WHERE path = 'infraestrutura-auth';
  IF v_sec IS NOT NULL THEN
    INSERT INTO public.qa_modulos (parent_id, label, path, ordem)
    VALUES (v_sec, 'Usuarios & Permissoes', 'infraestrutura-auth/usuarios-permissoes', 4)
    ON CONFLICT (path) DO NOTHING;
  END IF;

  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'infraestrutura-auth/usuarios-permissoes';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo usuarios-permissoes ausente e seção infraestrutura-auth não encontrada.'; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'USR-TELA-01', 'Módulo Usuários abre com o cabeçalho, as métricas e a ação',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'Porta de entrada da gestão de identidades: se não monta, some o controle de usuários, vínculos e convites.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar /usuarios pelo menu","resultado_esperado":"Título Usuários carrega"},
     {"ordem":2,"acao":"Conferir as métricas e a ação","resultado_esperado":"Cartões Ativos, Com convite, Multiempresa e Alertas IA; botão Novo Usuário"}]'::jsonb,
   'O módulo monta com o cabeçalho, as métricas e a ação.', NULL),

  (v_mod, 'USR-TELA-02', 'Mostra os filtros de busca, empresa, status e tipo',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Os filtros são o caminho para achar quem se procura numa base grande. Precisam estar sempre disponíveis.',
   'Rota /usuarios.',
   '[{"ordem":1,"acao":"Olhar a barra de filtros","resultado_esperado":"Aparecem a busca (nome/e-mail/CPF/telefone), o filtro por empresa, o de status e o de tipo de usuário"}]'::jsonb,
   'Os filtros aparecem.', NULL),

  (v_mod, 'USR-TELA-03', 'Abrir o modal de Novo Usuário',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'Cadastrar usuário é o ato central. O modal precisa abrir com o formulário de dados básicos.',
   'Rota /usuarios.',
   '[{"ordem":1,"acao":"Clicar em Novo Usuário","resultado_esperado":"Abre o modal Novo Usuário — Dados Básicos com o formulário"},
     {"ordem":2,"acao":"Fechar sem salvar","resultado_esperado":"O modal fecha sem criar nada"}]'::jsonb,
   'O modal de Novo Usuário abre e fecha sem efeito colateral.', NULL),

  (v_mod, 'USR-TELA-04', 'O filtro de status abre com as opções',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'O filtro de status recorta os usuários por situação (ativo, convite, etc.). Deve abrir com as opções.',
   'Rota /usuarios.',
   '[{"ordem":1,"acao":"Abrir o filtro de status","resultado_esperado":"Aparece a opção Todos os status (e os demais status)"}]'::jsonb,
   'O filtro de status abre com as opções.', NULL),

  (v_mod, 'USR-TELA-05', 'Buscar um usuário inexistente mostra o vazio orientativo',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Sem resultado, a tela não pode ficar em branco: precisa orientar, sem quebrar.',
   'Rota /usuarios.',
   '[{"ordem":1,"acao":"Buscar um termo que não existe","resultado_esperado":"A lista mostra Nenhum usuário encontrado, sem quebrar"}]'::jsonb,
   'A busca sem resultado mostra o vazio orientativo.', NULL),

  (v_mod, 'USR-TELA-06', 'O filtro de tipo de usuário abre com as opções',
   'feliz', 'baixa', 'aprovado', 'e2e', NULL,
   'O filtro por tipo (colaborador, admin, etc.) recorta a lista. Deve abrir com as opções.',
   'Rota /usuarios.',
   '[{"ordem":1,"acao":"Abrir o filtro de tipo de usuário","resultado_esperado":"Aparece a opção Todos os tipos de usuário (e os demais tipos)"}]'::jsonb,
   'O filtro de tipo abre com as opções.', NULL),

  (v_mod, 'USR-TELA-07', 'O filtro por empresa abre',
   'feliz', 'baixa', 'aprovado', 'e2e', NULL,
   'A base é multiempresa; o filtro por empresa recorta quem pertence a cada uma. Deve abrir com a busca de empresa.',
   'Rota /usuarios.',
   '[{"ordem":1,"acao":"Abrir o filtro por empresa","resultado_esperado":"Abre o seletor de empresa com o campo Buscar empresa e a opção Todas as empresas"}]'::jsonb,
   'O filtro por empresa abre.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Usuários (tela): antes=%, depois=% (esperado +7)', v_antes, v_depois;
END $doc$;

-- ══════════════════════════════════════════════════════════
-- Ponte de cobertura e2e: liga cada it() de usuarios.cy.ts ao caso.
-- ══════════════════════════════════════════════════════════
INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  ('USR-TELA-01', 'cypress/e2e/usuarios.cy.ts', 'carrega o módulo Usuários com o cabeçalho, as métricas e a ação'),
  ('USR-TELA-02', 'cypress/e2e/usuarios.cy.ts', 'mostra os filtros de busca, empresa, status e tipo'),
  ('USR-TELA-03', 'cypress/e2e/usuarios.cy.ts', 'abre o modal de Novo Usuário'),
  ('USR-TELA-04', 'cypress/e2e/usuarios.cy.ts', 'o filtro de status abre com as opções'),
  ('USR-TELA-05', 'cypress/e2e/usuarios.cy.ts', 'buscar um usuário inexistente mostra o vazio orientativo'),
  ('USR-TELA-06', 'cypress/e2e/usuarios.cy.ts', 'o filtro de tipo de usuário abre com as opções'),
  ('USR-TELA-07', 'cypress/e2e/usuarios.cy.ts', 'o filtro por empresa abre')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;
