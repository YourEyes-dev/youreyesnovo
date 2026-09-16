-- =====================================================================
-- ENTREGA — Colaboradores: documentação de TELA (nível e2e) + ponte
--
-- Cole este arquivo INTEIRO no SQL Editor da HOMOLOGAÇÃO (e, depois de
-- aprovado, no da PRODUÇÃO). Espelha a migration
-- 20260916180500_qa_colaboradores_casos_tela.sql: documenta os 9 casos
-- COLAB-TELA-01..09 no módulo estrutura-organizacional/colaboradores e liga
-- cada um ao it() de cypress/e2e/colaboradores.cy.ts na tabela qa_cobertura_e2e.
--
-- Por que a homologação precisa disto ANTES de rodar a bateria de tela: a
-- guarda de cobertura reprova a corrida se um it() novo não tiver caso
-- documentado (seria lido como "inventado").
--
-- Regras da casa: só CRIA documentação (não altera/apaga dado — dispensa
-- backup); idempotente (ON CONFLICT DO NOTHING, pode rodar 2x); bloco DO com
-- EXCEPTION por segurança; sem BEGIN/COMMIT; termina com UMA conferência SELECT.
-- =====================================================================

DO $colab$
DECLARE v_mod uuid;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'estrutura-organizacional/colaboradores';

  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo estrutura-organizacional/colaboradores nao existe nesta base. Casos COLAB-TELA NAO inseridos.';
  ELSE
    INSERT INTO public.qa_casos_teste
      (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
       base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
    VALUES
    (v_mod, 'COLAB-TELA-01', 'Módulo Colaboradores abre com o cabeçalho, as abas e as ações',
     'feliz', 'alta', 'aprovado', 'e2e', NULL,
     'Porta de entrada do núcleo de gente: se não monta, o RH perde admissão, ativos e desligados.',
     'Usuário autenticado com acesso ao módulo (perfil que pode criar).',
     '[{"ordem":1,"acao":"Acessar /colaboradores pelo menu","resultado_esperado":"Título Colaboradores carrega"},
       {"ordem":2,"acao":"Conferir abas e ações","resultado_esperado":"Abas Ativos, Admissões e Desligados; botões Novo Cadastro e Importar Colaboradores"}]'::jsonb,
     'O módulo monta com o cabeçalho, as abas e as ações.', NULL),

    (v_mod, 'COLAB-TELA-02', 'Aba Ativos traz a busca e os filtros',
     'feliz', 'alta', 'aprovado', 'e2e', NULL,
     'A aba Ativos é a lista de trabalho do dia a dia. A busca e os filtros precisam estar sempre disponíveis.',
     'Aba Ativos (padrão).',
     '[{"ordem":1,"acao":"Abrir a aba Ativos","resultado_esperado":"Aparecem a busca por nome/email/função e os filtros de Departamento e Estabelecimento/Obra"}]'::jsonb,
     'A aba Ativos mostra a busca e os filtros.', NULL),

    (v_mod, 'COLAB-TELA-03', 'Alternar entre visualização em cards e em lista',
     'feliz', 'media', 'aprovado', 'e2e', NULL,
     'A lista de colaboradores pode ser vista em cards ou em tabela. O botão de alternância deve trocar a visualização.',
     'Aba Ativos.',
     '[{"ordem":1,"acao":"Clicar na visualização em lista","resultado_esperado":"O modo lista fica ativo"},
       {"ordem":2,"acao":"Clicar na visualização em cards","resultado_esperado":"O modo cards volta a ficar ativo"}]'::jsonb,
     'A alternância de visualização funciona.', NULL),

    (v_mod, 'COLAB-TELA-04', 'Novo Cadastro abre a escolha (colaborador ou terceiro)',
     'feliz', 'alta', 'aprovado', 'e2e', NULL,
     'Cadastrar é o ato central. O botão Novo Cadastro deve abrir a escolha entre colaborador (CLT/estágio) e empresa terceira (PJ).',
     'Rota /colaboradores.',
     '[{"ordem":1,"acao":"Clicar em Novo Cadastro","resultado_esperado":"Abre o diálogo O que deseja cadastrar?, com Colaborador e Empresa Terceira"},
       {"ordem":2,"acao":"Fechar sem escolher","resultado_esperado":"O diálogo fecha sem criar nada"}]'::jsonb,
     'A escolha de novo cadastro abre e fecha sem efeito colateral.', NULL),

    (v_mod, 'COLAB-TELA-05', 'Importar Colaboradores abre o modal de importação',
     'feliz', 'media', 'aprovado', 'e2e', NULL,
     'A importação por planilha é como se traz uma equipe inteira. O modal de importação precisa abrir.',
     'Rota /colaboradores.',
     '[{"ordem":1,"acao":"Clicar em Importar Colaboradores","resultado_esperado":"Abre o modal de importação de planilha"},
       {"ordem":2,"acao":"Fechar sem importar","resultado_esperado":"O modal fecha sem efeito"}]'::jsonb,
     'O modal de importação abre e fecha sem efeito.', NULL),

    (v_mod, 'COLAB-TELA-06', 'Filtro de Departamento abre com as opções',
     'feliz', 'media', 'aprovado', 'e2e', NULL,
     'O filtro por departamento recorta a lista. Deve abrir com as opções (ao menos Todos Departamentos).',
     'Aba Ativos.',
     '[{"ordem":1,"acao":"Abrir o filtro de Departamento","resultado_esperado":"Aparece a opção Todos Departamentos (e os departamentos existentes, se houver)"}]'::jsonb,
     'O filtro de Departamento abre com as opções.', NULL),

    (v_mod, 'COLAB-TELA-07', 'Aba Admissões abre sem erro',
     'feliz', 'media', 'aprovado', 'e2e', NULL,
     'A aba Admissões acompanha as entradas em andamento. Deve montar mesmo com poucos dados.',
     'Aba Admissões.',
     '[{"ordem":1,"acao":"Abrir a aba Admissões","resultado_esperado":"O painel de admissões carrega sem erro"}]'::jsonb,
     'A aba Admissões abre sem quebrar.', NULL),

    (v_mod, 'COLAB-TELA-08', 'Aba Desligados abre sem erro (lista ou vazio orientativo)',
     'alternativo', 'media', 'aprovado', 'e2e', NULL,
     'A aba Desligados guarda o histórico de saídas. Sem nenhum, não pode ficar em branco: orienta o vazio.',
     'Aba Desligados.',
     '[{"ordem":1,"acao":"Abrir a aba Desligados","resultado_esperado":"Aparece a tabela de desligados; sem nenhum, o vazio (Nenhum colaborador desligado), sem quebrar"}]'::jsonb,
     'A aba Desligados monta a lista ou o vazio.', NULL),

    (v_mod, 'COLAB-TELA-09', 'Contador de colaboradores aparece',
     'feliz', 'baixa', 'aprovado', 'e2e', NULL,
     'O contador Mostrando X de Y é a referência rápida do tamanho da equipe e do efeito dos filtros.',
     'Aba Ativos.',
     '[{"ordem":1,"acao":"Olhar acima da lista","resultado_esperado":"Aparece o contador Mostrando X de Y colaboradores"}]'::jsonb,
     'O contador de colaboradores aparece.', NULL)

    ON CONFLICT (codigo) DO NOTHING;

    INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
    SELECT v.codigo, v.spec, v.teste
    FROM (VALUES
      ('COLAB-TELA-01', 'cypress/e2e/colaboradores.cy.ts', 'carrega o módulo de Colaboradores com o cabeçalho, as abas e as ações'),
      ('COLAB-TELA-02', 'cypress/e2e/colaboradores.cy.ts', 'a aba Ativos traz a busca e os filtros'),
      ('COLAB-TELA-03', 'cypress/e2e/colaboradores.cy.ts', 'alterna entre a visualização em cards e em lista'),
      ('COLAB-TELA-04', 'cypress/e2e/colaboradores.cy.ts', 'abre a escolha de Novo Cadastro (colaborador ou terceiro)'),
      ('COLAB-TELA-05', 'cypress/e2e/colaboradores.cy.ts', 'abre o modal de Importar Colaboradores'),
      ('COLAB-TELA-06', 'cypress/e2e/colaboradores.cy.ts', 'o filtro de Departamento abre com as opções'),
      ('COLAB-TELA-07', 'cypress/e2e/colaboradores.cy.ts', 'abre a aba Admissões'),
      ('COLAB-TELA-08', 'cypress/e2e/colaboradores.cy.ts', 'abre a aba Desligados'),
      ('COLAB-TELA-09', 'cypress/e2e/colaboradores.cy.ts', 'mostra o contador de colaboradores')
    ) AS v(codigo, spec, teste)
    ON CONFLICT (codigo) DO NOTHING;

    RAISE NOTICE 'Casos e ponte COLAB-TELA aplicados (idempotente).';
  END IF;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Erro ao aplicar COLAB-TELA: %', SQLERRM;
END $colab$;

-- ── Conferência (o editor mostra só o último resultado) ──────────────
SELECT
  (SELECT count(*) FROM public.qa_casos_teste     WHERE codigo LIKE 'COLAB-TELA-%') AS casos_colab_tela,
  (SELECT count(*) FROM public.qa_cobertura_e2e   WHERE codigo LIKE 'COLAB-TELA-%') AS pontes_colab_tela,
  (SELECT count(*) FROM public.qa_casos_teste c
      JOIN public.qa_modulos m ON m.id = c.modulo_id
     WHERE m.path = 'estrutura-organizacional/colaboradores' AND c.nivel = 'e2e')   AS e2e_no_modulo_colab;
-- Esperado após aplicar: casos_colab_tela = 9, pontes_colab_tela = 9.
