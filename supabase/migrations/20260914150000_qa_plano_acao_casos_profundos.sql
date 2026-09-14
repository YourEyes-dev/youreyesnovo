-- =========================================================
-- QA — Plano de Ação: casos e2e "profundos" (padrão "fixtures na ilha")
--
-- Segue o piloto do Metas: o seed-e2e-user passou a semear ações fictícias na
-- ilha de QA (semearPlanoAcao), o que destrava conferências que EXIGEM ações
-- já existentes — listagem e filtros por situação e por prioridade (que aqui
-- recortam a lista no servidor). Este arquivo:
--
--   1) DOCUMENTA os casos novos PACAO-TELA-10/11/12 (nivel e2e).
--   2) LIGA cada it() ao caso, em qa_cobertura_e2e (codigo -> spec + título
--      exato do it()). Sem a ponte, a guarda verificar-cobertura-e2e trataria
--      os it() novos como "inventados".
--
-- Idempotente: INSERTs com ON CONFLICT (codigo) DO NOTHING. Só documentação e
-- ponte — nada de dado de negócio (as ações vêm do seed / da migration irmã).
-- =========================================================

SET lock_timeout = '10s';

-- ── 1) Documenta PACAO-TELA-10/11/12 ────────────────────────────────────────
DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'planejamento-gestao/plano-de-acao';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo planejamento-gestao/plano-de-acao não encontrado.'; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'PACAO-TELA-10', 'Lista de Plano de Ação exibe as ações cadastradas',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Com ações na base, a lista precisa exibi-las pelo título — é o acompanhamento do dia a dia.',
   'Ambiente com ações cadastradas (ilha de QA semeada).',
   '[{"ordem":1,"acao":"Abrir Plano de Ação na aba Todas","resultado_esperado":"As ações cadastradas aparecem na lista, cada uma pelo seu título"}]'::jsonb,
   'A lista exibe as ações cadastradas pelo título.', NULL),

  (v_mod, 'PACAO-TELA-11', 'Filtro por situação recorta a lista',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'O filtro por situação (chips) recorta a lista para a situação escolhida; ações de outras situações somem.',
   'Ambiente com ações de mais de uma situação (ilha de QA semeada).',
   '[{"ordem":1,"acao":"Abrir a aba Todas","resultado_esperado":"A lista mostra ações de várias situações"},
     {"ordem":2,"acao":"Clicar no chip Concluídas","resultado_esperado":"Só as ações concluídas permanecem; as de outras situações somem"}]'::jsonb,
   'O filtro por situação recorta a lista corretamente.', NULL),

  (v_mod, 'PACAO-TELA-12', 'Filtro por prioridade recorta a lista',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'O filtro por prioridade (chips) recorta a lista para a prioridade escolhida; ações de outras prioridades somem.',
   'Ambiente com ações de mais de uma prioridade (ilha de QA semeada).',
   '[{"ordem":1,"acao":"Abrir a aba Todas","resultado_esperado":"A lista mostra ações de várias prioridades"},
     {"ordem":2,"acao":"Clicar no chip Imediato","resultado_esperado":"Só as ações de prioridade imediata permanecem; as de outras prioridades somem"}]'::jsonb,
   'O filtro por prioridade recorta a lista corretamente.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Plano de Ação (casos profundos): antes=%, depois=% (esperado +3)', v_antes, v_depois;
END $doc$;

-- ── 2) Ponte caso -> it() (título EXATO do it() em cypress/e2e/plano-acao.cy.ts) ──
INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  ('PACAO-TELA-10', 'cypress/e2e/plano-acao.cy.ts', 'lista as ações semeadas na aba Todas'),
  ('PACAO-TELA-11', 'cypress/e2e/plano-acao.cy.ts', 'filtra a lista pela situação Concluídas'),
  ('PACAO-TELA-12', 'cypress/e2e/plano-acao.cy.ts', 'filtra a lista pela prioridade Imediato')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;
