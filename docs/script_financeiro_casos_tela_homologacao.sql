-- =====================================================================
-- ENTREGA — Financeiro: documentação de TELA (nível e2e) + ponte
--
-- Cole este arquivo INTEIRO no SQL Editor da HOMOLOGAÇÃO (e, depois de
-- aprovado, no da PRODUÇÃO). Espelha a migration
-- 20260917120000_qa_financeiro_casos_tela.sql: documenta os 10 casos
-- FINAN-TELA-01..10 no módulo financeiro e liga cada um ao it() de
-- cypress/e2e/financeiro.cy.ts na tabela qa_cobertura_e2e.
--
-- Por que a homologação precisa disto ANTES de rodar a bateria de tela: a
-- guarda de cobertura reprova a corrida se um it() novo não tiver caso
-- documentado (seria lido como "inventado").
--
-- Regras da casa: só CRIA documentação (não altera/apaga dado — dispensa
-- backup); idempotente (ON CONFLICT DO NOTHING, pode rodar 2x); bloco DO com
-- EXCEPTION por segurança; sem BEGIN/COMMIT; termina com UMA conferência SELECT.
-- =====================================================================

DO $finan$
DECLARE v_mod uuid;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'financeiro';

  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo financeiro nao existe nesta base. Casos FINAN-TELA NAO inseridos.';
  ELSE
    INSERT INTO public.qa_casos_teste
      (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
       base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
    VALUES
    (v_mod, 'FINAN-TELA-01', 'Módulo Financeiro abre com o cabeçalho e as abas',
     'feliz', 'alta', 'aprovado', 'e2e', NULL,
     'Porta de entrada do financeiro do RH: se não monta, some folha, benefícios, provisões e eSocial.',
     'Usuário autenticado com acesso ao módulo.',
     '[{"ordem":1,"acao":"Acessar /financeiro pelo menu","resultado_esperado":"Título Módulo Financeiro carrega"},
       {"ordem":2,"acao":"Conferir as abas","resultado_esperado":"Abas Painel, Folha, Rubricas, Férias, 13º, Rescisão, Provisões, Benefícios, Tabelas, CCT, eSocial, Alertas e Tab. Fiscais"}]'::jsonb,
     'O módulo monta com o cabeçalho e as abas.', NULL),

    (v_mod, 'FINAN-TELA-02', 'Painel mostra os KPIs e os cards',
     'feliz', 'media', 'aprovado', 'e2e', NULL,
     'A aba inicial resume o financeiro: última folha, custo de benefícios, custos por categoria e histórico. É o panorama.',
     'Aba Painel (padrão ao abrir).',
     '[{"ordem":1,"acao":"Abrir a aba Painel","resultado_esperado":"Aparecem os KPIs (Última Folha, Custo Benefícios/mês...) e os cards Custos por Categoria e Histórico de Folha"}]'::jsonb,
     'O Painel resume o financeiro em KPIs e cards.', NULL),

    (v_mod, 'FINAN-TELA-03', 'Aba Folha abre com a ação de Novo Período',
     'feliz', 'alta', 'aprovado', 'e2e', NULL,
     'A aba Folha é o coração do módulo. Deve montar com a ação de criar período (ou o vazio orientativo).',
     'Aba Folha.',
     '[{"ordem":1,"acao":"Abrir a aba Folha","resultado_esperado":"Aparece o botão Novo Período; sem períodos, um vazio orientativo, sem quebrar"}]'::jsonb,
     'A aba Folha monta com a ação de Novo Período.', NULL),

    (v_mod, 'FINAN-TELA-04', 'Abrir o modal de Novo Período de Folha',
     'feliz', 'alta', 'aprovado', 'e2e', NULL,
     'Criar período é o ato central da folha. O modal precisa abrir com o campo de competência.',
     'Aba Folha.',
     '[{"ordem":1,"acao":"Clicar em Novo Período","resultado_esperado":"Abre o modal Novo Período de Folha com o campo de competência"},
       {"ordem":2,"acao":"Fechar em Cancelar","resultado_esperado":"O modal fecha sem criar nada"}]'::jsonb,
     'O modal de Novo Período abre e fecha sem efeito colateral.', NULL),

    (v_mod, 'FINAN-TELA-05', 'Aba Benefícios abre com as ações',
     'feliz', 'media', 'aprovado', 'e2e', NULL,
     'A aba Benefícios cadastra tipos e vincula colaboradores. Deve montar com as duas ações.',
     'Aba Benefícios.',
     '[{"ordem":1,"acao":"Abrir a aba Benefícios","resultado_esperado":"Aparecem os botões Novo Benefício e Vincular Colaborador; sem tipos, um vazio orientativo"}]'::jsonb,
     'A aba Benefícios monta com as ações de novo e vincular.', NULL),

    (v_mod, 'FINAN-TELA-06', 'Abrir o modal de Novo Tipo de Benefício',
     'feliz', 'media', 'aprovado', 'e2e', NULL,
     'Cadastrar benefício é o ato central da aba. O modal precisa abrir com o formulário (nome, categoria, valores).',
     'Aba Benefícios.',
     '[{"ordem":1,"acao":"Clicar em Novo Benefício","resultado_esperado":"Abre o modal Novo Tipo de Benefício com o formulário"},
       {"ordem":2,"acao":"Fechar em Cancelar","resultado_esperado":"O modal fecha sem criar nada"}]'::jsonb,
     'O modal de Novo Tipo de Benefício abre e fecha sem efeito.', NULL),

    (v_mod, 'FINAN-TELA-07', 'Aba Rubricas abre sem erro',
     'feliz', 'media', 'aprovado', 'e2e', NULL,
     'As rubricas classificam proventos e descontos da folha. A aba deve montar sem erro.',
     'Aba Rubricas.',
     '[{"ordem":1,"acao":"Abrir a aba Rubricas","resultado_esperado":"O painel de rubricas carrega sem erro"}]'::jsonb,
     'A aba Rubricas abre sem quebrar.', NULL),

    (v_mod, 'FINAN-TELA-08', 'Aba Provisões abre sem erro',
     'feliz', 'media', 'aprovado', 'e2e', NULL,
     'As provisões (férias, 13º, encargos) são o passivo trabalhista. A aba deve montar sem erro.',
     'Aba Provisões.',
     '[{"ordem":1,"acao":"Abrir a aba Provisões","resultado_esperado":"O painel de provisões carrega sem erro"}]'::jsonb,
     'A aba Provisões abre sem quebrar.', NULL),

    (v_mod, 'FINAN-TELA-09', 'Aba eSocial abre sem erro',
     'feliz', 'media', 'aprovado', 'e2e', NULL,
     'A aba eSocial acompanha os eventos da folha para o governo. Deve montar sem erro.',
     'Aba eSocial.',
     '[{"ordem":1,"acao":"Abrir a aba eSocial","resultado_esperado":"O painel do eSocial carrega sem erro"}]'::jsonb,
     'A aba eSocial abre sem quebrar.', NULL),

    (v_mod, 'FINAN-TELA-10', 'Aba Tabelas abre sem erro',
     'feliz', 'baixa', 'aprovado', 'e2e', NULL,
     'A aba Tabelas traz as tabelas legais (INSS, IRRF, salário família). Deve montar sem erro.',
     'Aba Tabelas.',
     '[{"ordem":1,"acao":"Abrir a aba Tabelas","resultado_esperado":"O painel de tabelas legais carrega sem erro"}]'::jsonb,
     'A aba Tabelas abre sem quebrar.', NULL)

    ON CONFLICT (codigo) DO NOTHING;

    INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
    SELECT v.codigo, v.spec, v.teste
    FROM (VALUES
      ('FINAN-TELA-01', 'cypress/e2e/financeiro.cy.ts', 'carrega o módulo Financeiro com o cabeçalho e as abas'),
      ('FINAN-TELA-02', 'cypress/e2e/financeiro.cy.ts', 'o Painel mostra os KPIs e os cards'),
      ('FINAN-TELA-03', 'cypress/e2e/financeiro.cy.ts', 'abre a aba Folha com a ação de Novo Período'),
      ('FINAN-TELA-04', 'cypress/e2e/financeiro.cy.ts', 'abre o modal de Novo Período de Folha'),
      ('FINAN-TELA-05', 'cypress/e2e/financeiro.cy.ts', 'abre a aba Benefícios com as ações'),
      ('FINAN-TELA-06', 'cypress/e2e/financeiro.cy.ts', 'abre o modal de Novo Tipo de Benefício'),
      ('FINAN-TELA-07', 'cypress/e2e/financeiro.cy.ts', 'abre a aba Rubricas'),
      ('FINAN-TELA-08', 'cypress/e2e/financeiro.cy.ts', 'abre a aba Provisões'),
      ('FINAN-TELA-09', 'cypress/e2e/financeiro.cy.ts', 'abre a aba eSocial'),
      ('FINAN-TELA-10', 'cypress/e2e/financeiro.cy.ts', 'abre a aba Tabelas')
    ) AS v(codigo, spec, teste)
    ON CONFLICT (codigo) DO NOTHING;

    RAISE NOTICE 'Casos e ponte FINAN-TELA aplicados (idempotente).';
  END IF;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Erro ao aplicar FINAN-TELA: %', SQLERRM;
END $finan$;

-- ── Conferência (o editor mostra só o último resultado) ──────────────
SELECT
  (SELECT count(*) FROM public.qa_casos_teste     WHERE codigo LIKE 'FINAN-TELA-%') AS casos_finan_tela,
  (SELECT count(*) FROM public.qa_cobertura_e2e   WHERE codigo LIKE 'FINAN-TELA-%') AS pontes_finan_tela,
  (SELECT count(*) FROM public.qa_casos_teste c
      JOIN public.qa_modulos m ON m.id = c.modulo_id
     WHERE m.path = 'financeiro' AND c.nivel = 'e2e')                               AS e2e_no_modulo_financeiro;
-- Esperado após aplicar: casos_finan_tela = 10, pontes_finan_tela = 10.
