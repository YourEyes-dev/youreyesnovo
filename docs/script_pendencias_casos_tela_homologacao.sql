-- =====================================================================
-- ENTREGA — Central de Pendências: documentação de TELA (nível e2e) + ponte
--
-- Cole este arquivo INTEIRO no SQL Editor da HOMOLOGAÇÃO (projeto
-- fgsblefvdabgdouipigz). É infra de TESTE (documentação/ponte do Cypress) e NÃO
-- vai para a produção — a produção não roda Cypress e a ponte qa_cobertura_e2e
-- só serve à guarda das esteiras. Espelha a
-- migration 20260917202153_qa_pendencias_casos_tela.sql: documenta os 4 casos
-- PEND-TELA-01..04 no módulo sistema/pendencias e liga cada um ao it() de
-- cypress/e2e/pendencias.cy.ts na tabela qa_cobertura_e2e.
--
-- Garante a linha do módulo (idempotente, sob a seção `sistema`) para não
-- depender de outra entrega ter passado antes.
--
-- Por que a homologação precisa disto ANTES de rodar a bateria de tela: a
-- guarda de cobertura reprova a corrida se um it() novo não tiver caso
-- documentado (seria lido como "inventado").
--
-- Regras da casa: só CRIA documentação (não altera/apaga dado — dispensa
-- backup); idempotente (ON CONFLICT DO NOTHING, pode rodar 2x); bloco DO com
-- EXCEPTION por segurança; sem BEGIN/COMMIT; termina com UMA conferência SELECT.
-- =====================================================================

DO $pend$
DECLARE v_sec uuid; v_mod uuid;
BEGIN
  SELECT id INTO v_sec FROM public.qa_modulos WHERE path = 'sistema';
  IF v_sec IS NOT NULL THEN
    INSERT INTO public.qa_modulos (parent_id, label, path, ordem)
    VALUES (v_sec, 'Central de Pendências', 'sistema/pendencias', 3)
    ON CONFLICT (path) DO NOTHING;
  END IF;

  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'sistema/pendencias';

  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo sistema/pendencias ausente e secao sistema nao encontrada. Casos PEND-TELA NAO inseridos.';
  ELSE
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

    INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
    SELECT v.codigo, v.spec, v.teste
    FROM (VALUES
      ('PEND-TELA-01', 'cypress/e2e/pendencias.cy.ts', 'carrega a Central de Pendências com o cabeçalho e os cartões'),
      ('PEND-TELA-02', 'cypress/e2e/pendencias.cy.ts', 'mostra a busca e os filtros por perfil'),
      ('PEND-TELA-03', 'cypress/e2e/pendencias.cy.ts', 'buscar um termo inexistente mostra o vazio orientativo'),
      ('PEND-TELA-04', 'cypress/e2e/pendencias.cy.ts', 'selecionar o filtro Gestão / RH ativa a aba')
    ) AS v(codigo, spec, teste)
    ON CONFLICT (codigo) DO NOTHING;

    RAISE NOTICE 'Casos e ponte PEND-TELA aplicados (idempotente).';
  END IF;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Erro ao aplicar PEND-TELA: %', SQLERRM;
END $pend$;

-- ── Conferência (o editor mostra só o último resultado) ──────────────
SELECT
  (SELECT count(*) FROM public.qa_casos_teste     WHERE codigo LIKE 'PEND-TELA-%') AS casos_pend_tela,
  (SELECT count(*) FROM public.qa_cobertura_e2e   WHERE codigo LIKE 'PEND-TELA-%') AS pontes_pend_tela,
  (SELECT count(*) FROM public.qa_casos_teste c
      JOIN public.qa_modulos m ON m.id = c.modulo_id
     WHERE m.path = 'sistema/pendencias' AND c.nivel = 'e2e') AS e2e_no_modulo_pendencias;
-- Esperado após aplicar: casos_pend_tela = 4, pontes_pend_tela = 4, e2e_no_modulo_pendencias = 4.
