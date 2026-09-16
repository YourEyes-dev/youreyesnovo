-- =========================================================
-- QA — Colaboradores ganha documentação de TELA (nível e2e) + ponte
--
-- O módulo Colaboradores (estrutura-organizacional/colaboradores) — o núcleo
-- de gente da plataforma (admissão, ativos, desligados) — não tinha
-- documentação de TELA. Mesmo passo de Metas/Plano de Ação/Documentos/Férias:
-- a bateria estrutural de tela (o módulo monta, as abas abrem, os modais
-- principais aparecem, a busca/filtros existem e o vazio orienta).
--
-- Prefixo -TELA- não colide com as sondas de motor (ADM-*, COLAB-* de dados).
-- Todos os casos são DATA-INDEPENDENTES: a busca, os filtros, a alternância de
-- visualização, o modal de novo cadastro e o de importação existem mesmo na
-- ilha vazia. Não exigem fixtures.
--
-- Duas entregas: esta migration (robô aplica no staging) e
-- docs/script_colaboradores_casos_tela_homologacao.sql (SQL Editor da
-- homologação e depois produção). Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

SET lock_timeout = '10s';

-- ══════════════════════════════════════════════════════════
-- COLABORADORES  (estrutura-organizacional/colaboradores)  — rota /colaboradores
-- ══════════════════════════════════════════════════════════
DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'estrutura-organizacional/colaboradores';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo estrutura-organizacional/colaboradores não encontrado.'; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

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

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Colaboradores (tela): antes=%, depois=% (esperado +9)', v_antes, v_depois;
END $doc$;

-- ══════════════════════════════════════════════════════════
-- Ponte de cobertura e2e: liga cada it() de colaboradores.cy.ts ao caso.
-- O "teste" é o título EXATO do it() (normalizado por espaços).
-- ══════════════════════════════════════════════════════════
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
