-- =========================================================
-- QA — Aprendizado & Papéis ganha TESTE de tela: ponte e2e (+ garante os casos)
--
-- A DOCUMENTAÇÃO do módulo já existia (13 casos APR-*, migration
-- 20260901130500). Faltavam o teste de tela (cypress/e2e/aprendizado-papeis.cy.ts)
-- e a PONTE qa_cobertura_e2e que liga cada it() ao seu caso. Sem a ponte, a
-- guarda leria os it() novos como "inventados" e reprovaria a corrida.
--
-- Implementamos o subconjunto DATA-INDEPENDENTE (roda na ilha de QA, cujos 4
-- cargos fixos existem no teste e na homologação):
--   APR-001  o módulo monta com as 4 abas;
--   APR-002  a aba Funções lista os cargos e a busca filtra;
--   APR-010  abrir o detalhe de uma função e voltar à lista;
--   APR-040  a aba Assinaturas orienta quando não há manual enviado;
--   APR-050  a aba Indicadores monta com os cartões.
--
-- Este arquivo GARANTE esses 5 casos (idempotente, ON CONFLICT DO NOTHING) além
-- da ponte — assim é espelho fiel do script de entrega, que não pode supor que
-- os casos APR já tenham chegado na homologação. No teste os 5 já existem (da
-- 20260901130500): o INSERT vira no-op e só a ponte é adicionada.
-- =========================================================

SET lock_timeout = '10s';

-- ══════════════════════════════════════════════════════════
-- Garante os 5 casos que serão ligados (idempotente).
-- ══════════════════════════════════════════════════════════
DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'desenvolvimento-performance/aprendizado-competencias';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo desenvolvimento-performance/aprendizado-competencias não encontrado.'; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

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

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Aprendizado & Papéis (garantia de casos): antes=%, depois=% (no teste já existem; espera-se sem mudança)', v_antes, v_depois;
END $doc$;

-- ══════════════════════════════════════════════════════════
-- Ponte de cobertura e2e: liga cada it() de aprendizado-papeis.cy.ts ao caso.
-- ══════════════════════════════════════════════════════════
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
