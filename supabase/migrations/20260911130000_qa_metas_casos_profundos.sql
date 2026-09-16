-- =========================================================
-- QA — Metas: casos e2e "profundos" (piloto do padrão "fixtures na ilha")
--
-- Piloto: o seed-e2e-user passou a semear metas fictícias na ilha de QA
-- (função semearMetas), o que destrava conferências que EXIGEM metas já
-- existentes — listagem, filtro por nível e consolidação. Este arquivo:
--
--   1) RE-DOCUMENTA METAS-TELA-09. O vazio natural ("crie a primeira meta")
--      não é mais alcançável na ilha semeada; o caso passa a cobrir o
--      vazio-por-busca (buscar texto inexistente esvazia a lista).
--   2) DOCUMENTA os casos novos METAS-TELA-10/11/12 (nivel e2e).
--   3) LIGA cada it() novo ao caso, em qa_cobertura_e2e (codigo -> spec +
--      título exato do it()). Sem a ponte, a guarda verificar-cobertura-e2e
--      trataria os it() novos como "inventados" e reprovaria.
--
-- Idempotente: UPDATE reescreve o mesmo texto; INSERTs com ON CONFLICT
-- (codigo) DO NOTHING. Só documentação e ponte — nada de dado de negócio.
-- =========================================================

SET lock_timeout = '10s';

-- ── 1) Re-documenta METAS-TELA-09 (vazio natural -> vazio-por-busca) ─────────
UPDATE public.qa_casos_teste SET
  titulo = 'Minhas Metas mostra vazio quando a busca não encontra metas',
  tipo = 'alternativo',
  objetivo = 'Com metas cadastradas, uma busca sem correspondência deve esvaziar a lista com aviso claro (Nenhuma meta corresponde aos filtros aplicados), sem quebrar.',
  pre_condicoes = 'Ambiente com metas cadastradas (ilha de QA semeada pelo seed-e2e-user).',
  passos = '[{"ordem":1,"acao":"Abrir Minhas Metas","resultado_esperado":"A lista de metas aparece"},
             {"ordem":2,"acao":"Buscar por um texto inexistente","resultado_esperado":"A lista fica vazia com o aviso de que nenhuma meta corresponde aos filtros"}]'::jsonb,
  resultado_esperado = 'A busca sem resultado mostra o vazio orientativo, sem quebrar.'
WHERE codigo = 'METAS-TELA-09';

-- ── 2) Documenta METAS-TELA-10/11/12 ────────────────────────────────────────
DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'planejamento-gestao/metas';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo planejamento-gestao/metas não encontrado.'; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'METAS-TELA-10', 'Minhas Metas lista as metas cadastradas',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Com metas na base, a lista precisa exibi-las pelo título — é o acompanhamento do dia a dia.',
   'Ambiente com metas cadastradas (ilha de QA semeada).',
   '[{"ordem":1,"acao":"Abrir Minhas Metas","resultado_esperado":"As metas cadastradas aparecem na lista, cada uma pelo seu título"}]'::jsonb,
   'A lista exibe as metas cadastradas pelo título.', NULL),

  (v_mod, 'METAS-TELA-11', 'Filtro por nível recorta Minhas Metas',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'O filtro por nível (chips) recorta a lista para o nível escolhido; metas de outros níveis somem.',
   'Ambiente com metas de mais de um nível (ilha de QA semeada).',
   '[{"ordem":1,"acao":"Abrir Minhas Metas","resultado_esperado":"A lista mostra metas de vários níveis"},
     {"ordem":2,"acao":"Clicar no chip Estratégicas","resultado_esperado":"Só as metas estratégicas permanecem; as de outros níveis somem"}]'::jsonb,
   'O filtro por nível recorta a lista corretamente.', NULL),

  (v_mod, 'METAS-TELA-12', 'Consolidação resume as metas por nível',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Com metas na base, a Consolidação mostra o atingimento ponderado e um cartão por nível presente.',
   'Ambiente com metas cadastradas (ilha de QA semeada).',
   '[{"ordem":1,"acao":"Abrir a aba Consolidação","resultado_esperado":"Aparece o Atingimento Geral Ponderado e um cartão por nível com metas (ex.: Estratégica)"}]'::jsonb,
   'A Consolidação resume as metas por nível.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Metas (casos profundos): antes=%, depois=% (esperado +3)', v_antes, v_depois;
END $doc$;

-- ── 3) Ponte caso -> it() (título EXATO do it() em cypress/e2e/metas.cy.ts) ──
INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  ('METAS-TELA-10', 'cypress/e2e/metas.cy.ts', 'lista as metas semeadas em Minhas Metas'),
  ('METAS-TELA-11', 'cypress/e2e/metas.cy.ts', 'filtra Minhas Metas pelo nível Estratégica'),
  ('METAS-TELA-12', 'cypress/e2e/metas.cy.ts', 'consolida as metas semeadas por nível')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;
