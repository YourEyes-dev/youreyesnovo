-- Férias: via de exceção auditada para aprovar fora do prazo de 30 dias (art. 135).
-- A trava ferias_solic_valida_aviso_30d barra aprovar com menos de 30 dias de
-- antecedência SEM aviso e SEM justificativa. A tela de Solicitações passou a
-- detectar o fora-do-prazo e, em vez de bater na trava, abre um diálogo que exige
-- uma justificativa; ao aprovar, a justificativa vai para `justificativa_excecao`
-- (a trava libera) e fica como trilha auditável, com badge "Exceção art. 135" no
-- card. Não antedata aviso, não altera datas. Documenta o caso e2e FERIAS-TELA-11.
-- Idempotente. Não cria tabela nem função.

DO $doc$
DECLARE
  v_mod uuid;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos
   WHERE path = 'jornada-rotina/ferias';

  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo jornada-rotina/ferias ausente; FERIAS-TELA-11 não documentado.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'FERIAS-TELA-11',
   'Aprovar férias fora do prazo de 30 dias pela via de exceção (art. 135)',
   'alternativo', 'alta', 'aprovado', 'e2e',
   'CLT art. 135: a concessão de férias deve ser participada ao empregado com 30 dias de antecedência. A falta do aviso é irregularidade formal (não invalida férias gozadas nem gera dobra do art. 137, que trata do período concessivo). O sistema não pode travar a regularização de um fato consumado, mas deve registrar a exceção de forma auditável.',
   'Permitir que o gestor aprove uma solicitação com menos de 30 dias de antecedência (ou já no passado) informando uma justificativa obrigatória, que fica gravada como trilha; sem antedatar aviso nem alterar datas.',
   'Solicitação de férias pendente cujo início está a menos de 30 dias (ou já ocorreu); usuário com permissão de aprovar férias.',
   '[{"ordem":1,"acao":"Férias > Solicitações > numa solicitação pendente fora do prazo, clicar Aprovar","resultado_esperado":"Abre o diálogo \"Aprovar fora do prazo de 30 dias\" pedindo justificativa obrigatória (mín. 10 caracteres), citando o art. 135"},
     {"ordem":2,"acao":"Preencher a justificativa e confirmar \"Aprovar com exceção\"","resultado_esperado":"A solicitação é aprovada (a trava dos 30 dias não barra), a justificativa fica gravada em justificativa_excecao e o card passa a exibir o selo \"Exceção art. 135\" com o motivo"},
     {"ordem":3,"acao":"Aprovar uma solicitação DENTRO do prazo (30+ dias)","resultado_esperado":"Aprova direto, sem o diálogo de exceção"}]'::jsonb,
   'Fora do prazo: só aprova com justificativa (trilha auditável + selo). Dentro do prazo: aprova direto. Nenhuma data é alterada e nenhum aviso é antedatado.',
   'A trava real é ferias_solic_valida_aviso_30d (BEFORE UPDATE), que libera quando justificativa_excecao vem preenchida. Sem it() automatizado ainda (depende de seed de solicitação fora do prazo no staging).')
  ON CONFLICT (codigo) DO UPDATE SET
     modulo_id = EXCLUDED.modulo_id, titulo = EXCLUDED.titulo, tipo = EXCLUDED.tipo,
     prioridade = EXCLUDED.prioridade, status = EXCLUDED.status, nivel = EXCLUDED.nivel,
     base_legal = EXCLUDED.base_legal, objetivo = EXCLUDED.objetivo,
     pre_condicoes = EXCLUDED.pre_condicoes, passos = EXCLUDED.passos,
     resultado_esperado = EXCLUDED.resultado_esperado, observacoes = EXCLUDED.observacoes;

  RAISE NOTICE 'FERIAS-TELA-11 documentado (e2e).';
END
$doc$;
