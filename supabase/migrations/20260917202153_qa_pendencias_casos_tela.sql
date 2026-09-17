-- =========================================================
-- QA — Central de Pendências ganha documentação de TELA (nível e2e) + ponte
--
-- A Central de Pendências (/pendencias) — o agregador de ações/providências por
-- perfil (férias, documentos, ajustes, avaliações, desligamentos, afastamentos,
-- alertas de saúde) — não tinha módulo nem casos no QA. Documentamos primeiro os
-- casos (fonte da verdade) e só então os it(). Mesmo passo de
-- Férias/Colaboradores/Financeiro/Usuários: o módulo monta com cabeçalho e
-- cartões, a busca e os filtros por perfil aparecem, o vazio orienta.
--
-- Módulo: garante a linha `sistema/pendencias` (idempotente, sob a seção
-- `sistema`) para não depender da ordem de outra sessão. Todos os casos são
-- DATA-INDEPENDENTES (o vazio é forçado via busca) — sem fixtures.
-- =========================================================

SET lock_timeout = '10s';

-- ══════════════════════════════════════════════════════════
-- CENTRAL DE PENDÊNCIAS  (sistema/pendencias)  — rota /pendencias
-- ══════════════════════════════════════════════════════════
DO $doc$
DECLARE v_sec uuid; v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_sec FROM public.qa_modulos WHERE path = 'sistema';
  IF v_sec IS NOT NULL THEN
    INSERT INTO public.qa_modulos (parent_id, label, path, ordem)
    VALUES (v_sec, 'Central de Pendências', 'sistema/pendencias', 3)
    ON CONFLICT (path) DO NOTHING;
  END IF;

  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'sistema/pendencias';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo sistema/pendencias ausente e seção sistema não encontrada.'; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'PEND-TELA-01', 'Central de Pendências abre com o cabeçalho e os cartões',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'É o painel único do que precisa de ação. Se não monta, o RH/gestor perde a visão consolidada das providências.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar /pendencias (pelo dashboard ou direto)","resultado_esperado":"Título Central de Pendências carrega"},
     {"ordem":2,"acao":"Conferir os cartões","resultado_esperado":"Urgentes, Em Atenção e Total de Ações"}]'::jsonb,
   'O módulo monta com o cabeçalho e os três cartões.', NULL),

  (v_mod, 'PEND-TELA-02', 'Mostra a busca e os filtros por perfil',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'A busca e os filtros por perfil (Tudo/Meu Perfil/Minha Equipe/Gestão / RH) são como se recorta a lista de pendências.',
   'Rota /pendencias.',
   '[{"ordem":1,"acao":"Olhar a barra de filtros","resultado_esperado":"Aparecem a busca de pendências e os filtros Tudo, Meu Perfil, Minha Equipe e Gestão / RH (Tudo ativo)"}]'::jsonb,
   'A busca e os filtros por perfil aparecem.', NULL),

  (v_mod, 'PEND-TELA-03', 'Buscar uma pendência inexistente mostra o vazio orientativo',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Sem resultado, a tela não pode ficar em branco: precisa orientar (você está em dia), sem quebrar.',
   'Rota /pendencias.',
   '[{"ordem":1,"acao":"Buscar um termo que não existe","resultado_esperado":"Aparece Nenhuma pendência encontrada e a mensagem de que está em dia, sem quebrar"}]'::jsonb,
   'A busca sem resultado mostra o vazio orientativo.', NULL),

  (v_mod, 'PEND-TELA-04', 'Selecionar o filtro por perfil (Gestão / RH) ativa a aba',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Trocar o perfil de atuação recorta as pendências de cada papel. O filtro escolhido deve ficar ativo e a tela seguir consistente.',
   'Rota /pendencias.',
   '[{"ordem":1,"acao":"Clicar no filtro Gestão / RH","resultado_esperado":"O filtro fica ativo (destacado)"},
     {"ordem":2,"acao":"Conferir a tela","resultado_esperado":"Cabeçalho e busca permanecem; sem erro"}]'::jsonb,
   'O filtro por perfil é selecionável e a tela segue consistente.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Central de Pendências (tela): antes=%, depois=% (esperado +4)', v_antes, v_depois;
END $doc$;

-- ══════════════════════════════════════════════════════════
-- Ponte de cobertura e2e: liga cada it() de pendencias.cy.ts ao caso.
-- ══════════════════════════════════════════════════════════
INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  ('PEND-TELA-01', 'cypress/e2e/pendencias.cy.ts', 'carrega a Central de Pendências com o cabeçalho e os cartões'),
  ('PEND-TELA-02', 'cypress/e2e/pendencias.cy.ts', 'mostra a busca e os filtros por perfil'),
  ('PEND-TELA-03', 'cypress/e2e/pendencias.cy.ts', 'buscar um termo inexistente mostra o vazio orientativo'),
  ('PEND-TELA-04', 'cypress/e2e/pendencias.cy.ts', 'selecionar o filtro Gestão / RH ativa a aba')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;
