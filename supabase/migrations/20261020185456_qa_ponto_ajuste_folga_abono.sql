-- =========================================================
-- QA — Caso e2e PONTO-AJUSTE-FOLGA: clareza do lançamento de folga/justificativa
-- de dia inteiro na tela de Ajuste de ponto, com a diretriz de abono lida da
-- configuração.
--
-- Contexto: o RH lança uma folga/justificativa de dia inteiro pela tela de
-- Ajuste (SolicitarAjusteFolhaInterno) marcando "Dia inteiro" e escolhendo uma
-- justificativa do catálogo (ponto_justificativas). A melhoria de UX passou a:
--   - deixar explícito que "Dia inteiro" é o lançamento de uma folga/justificativa;
--   - mostrar, ao escolher a justificativa, se ela ABONA (sim), NÃO abona (nao)
--     ou é CONFIGURÁVEL — lido de tipo_abono, com a citação legal quando houver
--     base_legal (art. 473).
--
-- Nível e2e, módulo jornada-rotina/ponto. Sem ponte Cypress: o fluxo depende de
-- colaborador + catálogo semeados (selecionar colaborador, achar o dia, marcar
-- dia inteiro, escolher a justificativa), que o módulo de Ponto valida por
-- homologação MANUAL (mesma política dos demais fluxos semeados do ponto.cy.ts).
--
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'jornada-rotina/ponto';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo jornada-rotina/ponto não encontrado.'; END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PONTO-AJUSTE-FOLGA',
   'Ajuste: lançar folga de dia inteiro e ver se a justificativa abona',
   'feliz', 'media', 'aprovado', 'e2e',
   NULL,
   'Na tela de Ajuste de ponto, o RH deve entender que "Dia inteiro" é o lançamento de uma folga/justificativa e ver, ao escolher a justificativa do catálogo, se ela abona ou não (lido da configuração, tipo_abono), com as diretrizes.',
   'Usuário autenticado (RH/admin); colaborador com folha no mês; catálogo de Justificativas de Ponto com ao menos uma justificativa de cada tipo de abono.',
   '[{"ordem":1,"acao":"Ponto > Solicitar Ajuste; selecionar o colaborador","resultado_esperado":"A folha do mês abre"},
     {"ordem":2,"acao":"Num dia, marcar Dia inteiro","resultado_esperado":"Aparece Lançamento de dia inteiro (folga/licença/abono) e o seletor de justificativa"},
     {"ordem":3,"acao":"Escolher uma justificativa que ABONA (tipo sim)","resultado_esperado":"Mostra Abona o dia (ou Abono obrigatório por lei, quando base_legal)"},
     {"ordem":4,"acao":"Escolher uma justificativa que NÃO abona (tipo nao)","resultado_esperado":"Mostra Não abona — o dia segue contando como falta"},
     {"ordem":5,"acao":"Escolher uma justificativa CONFIGURÁVEL","resultado_esperado":"Mostra Abono configurável e o checkbox Abonar o dia (quando aprovado)"}]'::jsonb,
   'A tela deixa claro o lançamento de folga de dia inteiro e exibe a diretriz de abono conforme a configuração da justificativa.',
   'Melhoria de UX da tela de Ajuste (SolicitarAjusteFolhaInterno). Validação por homologação MANUAL (fluxo depende de colaborador/catálogo semeados).')
  ON CONFLICT (codigo) DO NOTHING;
END $doc$;
