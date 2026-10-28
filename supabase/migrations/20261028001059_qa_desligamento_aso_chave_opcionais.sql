-- Desligamento: a Chave de Conectividade Social (FGTS) e o ASO demissional
-- deixam de BLOQUEAR a conclusao do desligamento.
--   RNDES19 (chave FGTS): com o FGTS Digital (2024) a chave nao e mais gerada;
--     as rescisoes tem apenas a guia GFD. Campo passa a ser opcional (aviso).
--   RNDES16 (ASO demissional): a NR-07 (item 7.5.11) exige o exame, mas a
--     ausencia (ex.: o funcionario nao comparece) nao pode travar o registro do
--     desligamento. Vira aviso, com a pendencia registrada nas observacoes.
-- Documenta o caso e2e DESL-067 e liga a ponte ao it() real. Idempotente.
-- Nao cria tabela; nao altera funcao de regra (so documentacao de QA).

DO $doc$
DECLARE
  v_mod uuid;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos
   WHERE path = 'estrutura-organizacional/colaboradores/desligamento';

  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo de desligamento ausente; caso DESL-067 nao documentado.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'DESL-067',
   'Chave de Conectividade (FGTS) e ASO demissional nao bloqueiam a conclusao',
   'feliz', 'alta', 'aprovado', 'e2e',
   'FGTS Digital (2024): a chave de conectividade social deixou de ser gerada, as rescisoes tem so a guia GFD. NR-07, item 7.5.11: o exame demissional e exigido, mas sua ausencia nao pode travar o registro do desligamento.',
   'Garantir que o RH conclua o desligamento mesmo sem a chave de conectividade e sem o ASO demissional, preservando os avisos de compliance (campos viram aviso, nao bloqueio).',
   'Colaborador elegivel a desligamento, sem estabilidade ativa.',
   '[{"ordem":1,"acao":"Abrir o desligamento, escolher Dispensa sem justa causa e informar uma data valida","resultado_esperado":"Formulario valido"},
     {"ordem":2,"acao":"Deixar a Chave de Conectividade (FGTS) e o ASO demissional em branco","resultado_esperado":"O botao Confirmar Desligamento permanece HABILITADO"}]'::jsonb,
   'Os dois campos sao opcionais: aparecem como aviso, nunca como trava da conclusao.',
   'Revisao 2026 das regras RNDES16 (ASO) e RNDES19 (chave FGTS).')
  ON CONFLICT (codigo) DO UPDATE SET
     modulo_id = EXCLUDED.modulo_id, titulo = EXCLUDED.titulo, tipo = EXCLUDED.tipo,
     prioridade = EXCLUDED.prioridade, status = EXCLUDED.status, nivel = EXCLUDED.nivel,
     base_legal = EXCLUDED.base_legal, objetivo = EXCLUDED.objetivo,
     pre_condicoes = EXCLUDED.pre_condicoes, passos = EXCLUDED.passos,
     resultado_esperado = EXCLUDED.resultado_esperado, observacoes = EXCLUDED.observacoes;

  -- Ponte caso -> it() real (titulo exato do it() em cypress/e2e/desligamento.cy.ts)
  DELETE FROM public.qa_cobertura_e2e WHERE codigo = 'DESL-067';
  INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
  VALUES ('DESL-067', 'cypress/e2e/desligamento.cy.ts',
          'DESL-067: Chave FGTS e ASO demissional não bloqueiam a conclusão');

  RAISE NOTICE 'DESL-067 documentado (e2e) e ligado ao it() real.';
END
$doc$;
