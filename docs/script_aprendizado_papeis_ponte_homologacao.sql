-- =====================================================================
-- ENTREGA — Aprendizado & Papéis: teste de tela (ponte e2e) + garante os casos
--
-- Cole este arquivo INTEIRO no SQL Editor da HOMOLOGAÇÃO (projeto
-- fgsblefvdabgdouipigz). É infra de TESTE (documentação/ponte do Cypress) e NÃO
-- vai para a produção — a produção não roda Cypress e a ponte qa_cobertura_e2e
-- só serve à guarda das esteiras. Espelha a
-- migration 20260917164458_qa_aprendizado_papeis_ponte_e2e.sql: liga cada it()
-- de cypress/e2e/aprendizado-papeis.cy.ts ao seu caso APR-* na tabela
-- qa_cobertura_e2e, e GARANTE os 5 casos ligados (idempotente) — porque a
-- documentação dos casos APR entrou por outra entrega (Item 2) que pode não ter
-- sido aplicada aqui. Se já estiver, o INSERT dos casos vira no-op.
--
-- Por que a homologação precisa disto ANTES de rodar a bateria de tela: a
-- guarda de cobertura reprova a corrida se um it() novo não casar com um caso
-- e2e documentado + ligado (seria lido como "inventado").
--
-- Casos ligados (subconjunto data-independente; a ilha de QA tem 4 cargos fixos):
--   APR-001 abas · APR-002 lista+busca · APR-010 detalhe da função ·
--   APR-040 assinaturas (vazio) · APR-050 indicadores.
--
-- Regras da casa: só CRIA documentação (não altera/apaga dado — dispensa
-- backup); idempotente (ON CONFLICT DO NOTHING, pode rodar 2x); bloco DO com
-- EXCEPTION por segurança; sem BEGIN/COMMIT; termina com UMA conferência SELECT.
-- =====================================================================

DO $apr$
DECLARE v_mod uuid;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'desenvolvimento-performance/aprendizado-competencias';

  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo desenvolvimento-performance/aprendizado-competencias ausente. Casos APR NAO inseridos (a ponte ainda entra).';
  ELSE
    INSERT INTO public.qa_casos_teste
      (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
       base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
    VALUES

    (v_mod, 'APR-001', 'Aprendizado & Papéis abre com as abas do módulo',
     'feliz', 'alta', 'aprovado', 'e2e', NULL,
     'É o mapa da organização do trabalho por função. Se não monta, o RH perde atividades, competências e manuais das funções.',
     'Usuário autenticado com acesso ao módulo.',
     '[{"ordem":1,"acao":"Acessar Aprendizado & Papéis pelo menu","resultado_esperado":"Título Aprendizado & Papéis carrega"},
       {"ordem":2,"acao":"Conferir as abas","resultado_esperado":"Funções, Assinaturas, Indicadores, Configurações"}]'::jsonb,
     'O módulo monta com as abas.', NULL),

    (v_mod, 'APR-002', 'Lista de funções e busca',
     'feliz', 'alta', 'aprovado', 'e2e', NULL,
     'A aba Funções lista os cargos com contadores (atividades/competências/EPIs). É a porta para detalhar cada papel.',
     'Cargos cadastrados.',
     '[{"ordem":1,"acao":"Abrir a aba Funções","resultado_esperado":"Cards de cargo com contadores montam"},
       {"ordem":2,"acao":"Buscar uma função","resultado_esperado":"A lista filtra pelo termo"}]'::jsonb,
     'As funções listam e filtram.',
     'Sem cargos: Nenhuma função cadastrada.'),

    (v_mod, 'APR-010', 'Abrir o detalhe de uma função',
     'feliz', 'alta', 'aprovado', 'e2e', NULL,
     'O detalhe da função reúne objetivo, escopo, sub-abas (Atividades, Competências, Indicadores, EPIs & Treinamento) — o corpo do papel.',
     'Ao menos uma função na lista.',
     '[{"ordem":1,"acao":"Clicar num cargo","resultado_esperado":"Detalhe da função abre com as sub-abas e o botão Voltar à lista"}]'::jsonb,
     'O detalhe da função monta.', NULL),

    (v_mod, 'APR-040', 'Assinaturas listam os manuais enviados e seus status',
     'feliz', 'alta', 'aprovado', 'e2e', NULL,
     'A aba Assinaturas acompanha quem já assinou o manual da função — a prova de ciência do colaborador.',
     'Aba Assinaturas.',
     '[{"ordem":1,"acao":"Abrir a aba Assinaturas","resultado_esperado":"Lista de envios com colaborador/cargo/gestor e o status (Aguardando/Concluído)"}]'::jsonb,
     'As assinaturas montam com status.',
     'Sem envios: Nenhum manual enviado para assinatura ainda.'),

    (v_mod, 'APR-050', 'Indicadores apontam funções sem atividades/competências',
     'feliz', 'media', 'aprovado', 'e2e', NULL,
     'Os indicadores mostram os buracos: funções sem atividades ou sem competências — onde falta mapear.',
     'Aba Indicadores.',
     '[{"ordem":1,"acao":"Abrir Indicadores","resultado_esperado":"Funções sem Atividades / sem Competências (ou o positivo Todas as funções possuem atividades ✓)"}]'::jsonb,
     'Os indicadores do módulo montam.', NULL)

    ON CONFLICT (codigo) DO NOTHING;

    RAISE NOTICE 'Casos APR (5 ligados) garantidos (idempotente).';
  END IF;

  INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
  SELECT v.codigo, v.spec, v.teste
  FROM (VALUES
    ('APR-001', 'cypress/e2e/aprendizado-papeis.cy.ts', 'carrega o módulo Aprendizado & Papéis com as abas'),
    ('APR-002', 'cypress/e2e/aprendizado-papeis.cy.ts', 'a aba Funções lista as funções e a busca filtra'),
    ('APR-010', 'cypress/e2e/aprendizado-papeis.cy.ts', 'abre o detalhe de uma função e volta à lista'),
    ('APR-040', 'cypress/e2e/aprendizado-papeis.cy.ts', 'a aba Assinaturas orienta quando não há manual enviado'),
    ('APR-050', 'cypress/e2e/aprendizado-papeis.cy.ts', 'a aba Indicadores monta com os cartões')
  ) AS v(codigo, spec, teste)
  ON CONFLICT (codigo) DO NOTHING;

  RAISE NOTICE 'Ponte APR (aprendizado-papeis.cy.ts) aplicada (idempotente).';

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Erro ao aplicar APR (ponte/casos): %', SQLERRM;
END $apr$;

-- ── Conferência (o editor mostra só o último resultado) ──────────────
SELECT
  (SELECT count(*) FROM public.qa_casos_teste
     WHERE codigo IN ('APR-001','APR-002','APR-010','APR-040','APR-050')) AS casos_apr_ligados,
  (SELECT count(*) FROM public.qa_cobertura_e2e
     WHERE spec = 'cypress/e2e/aprendizado-papeis.cy.ts')               AS pontes_apr_tela,
  (SELECT count(*) FROM public.qa_casos_teste c
      JOIN public.qa_modulos m ON m.id = c.modulo_id
     WHERE m.path = 'desenvolvimento-performance/aprendizado-competencias'
       AND c.nivel = 'e2e')                                            AS e2e_no_modulo_aprendizado;
-- Esperado após aplicar: casos_apr_ligados = 5, pontes_apr_tela = 5.
-- e2e_no_modulo_aprendizado = 13 se o Item 2 já entrou aqui, ou 5 se só esta entrega.
