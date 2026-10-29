-- ============================================================================
-- Ponto — Fase 2 / F5: telas do pedido (app do colaborador e RH) — documentação
-- de testes. [fase2-f5-telas]
-- ----------------------------------------------------------------------------
-- As telas mudam (Folha de Ponto · Ajustes do app e do RH, planilha de
-- aprovação, Atestados). No banco, só a Documentação de Testes:
--   * PONTO-499 (e2e, homologação MANUAL, sem it(): o fluxo depende de link de
--     ponto e colaborador semeados);
--   * PONTO-AJUSTE-FOLGA passa a descrever os três modos do dia na tela do RH;
--   * ESC-012 registra que a ausência pedida pelo app/RH sempre leva anexo.
-- Idempotente.
-- ============================================================================

DO $doc$
DECLARE v_mod uuid;
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL OR to_regclass('public.qa_modulos') IS NULL THEN
    RAISE NOTICE 'Motor de QA ausente; documentação F5 não registrada.';
    RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'jornada-rotina/ponto' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo jornada-rotina/ponto ausente; documentação F5 não registrada.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PONTO-499',
   'App de ajuste: ausência com atestado chega ao RH e vira lançamento em Atestados',
   'feliz', 'critica', 'aprovado', 'e2e',
   'CLT art. 473; Lei 605/1949, art. 6º, § 1º; Portaria MTP 671/2021; LGPD art. 11',
   'Ponta a ponta: o colaborador pede uma ausência pelo app (com o atestado e a selfie, quando a empresa exige), o RH vê '
   || 'o pedido como "Ausência" na planilha de aprovação, com o anexo e a selfie, aprova, e o lançamento aparece em Atestados '
   || 'com o arquivo — sem nenhuma batida nova no espelho.',
   'Ambiente de teste com Empresa Staging, colaborador com link de ponto (CPF fictício 900000xxx) e catálogo com as justificativas do app.',
   '[{"ordem":1,"acao":"No link do colaborador, Folha de Ponto · Ajustes: num dia, escolher Ausência, Dia inteiro, Atestado médico, anexar o PDF, tirar a selfie e enviar","resultado_esperado":"Pedido enviado"},
     {"ordem":2,"acao":"No RH, Ponto > Ajustes > Folha de Aprovação","resultado_esperado":"O dia aparece com o selo Ausência, o anexo e o botão da selfie"},
     {"ordem":3,"acao":"Aprovar o dia","resultado_esperado":"Status Aprovado"},
     {"ordem":4,"acao":"Abrir Atestados","resultado_esperado":"Lançamento do colaborador no dia, com o arquivo do pedido"},
     {"ordem":5,"acao":"Abrir o espelho do colaborador no dia","resultado_esperado":"Nenhuma batida nova; dia Justificado"}]'::jsonb,
   'Ausência pedida no app termina em Atestados, com o documento, sem batida inventada.',
   'Fase 2 do Ponto, F5 (out/2026). Homologação MANUAL (sem it(): depende de link e colaborador semeados).')
  ON CONFLICT (codigo) DO NOTHING;

  UPDATE public.qa_casos_teste
     SET titulo = 'Ajuste pelo RH: três modos no dia (Correção de batida, Ausência, Dia inteiro do RH) com a regra de abono',
         objetivo = 'Na tela de Ajuste de ponto do RH, cada dia tem três modos: Correção de batida (horários, só justificativas '
                 || 'de correção ou de lançamento do RH), Ausência (dia inteiro ou início/fim, só justificativas de ausência, '
                 || 'anexo obrigatório; na aprovação vira lançamento em Atestados) e Dia inteiro (lançamento do RH: folga, '
                 || 'day off, abono). Ao escolher a justificativa, a tela mostra se ela abona ou não (tipo_abono), com a '
                 || 'citação legal quando houver.',
         passos = '[{"ordem":1,"acao":"Ponto > Solicitar Ajuste; selecionar o colaborador","resultado_esperado":"A folha do mês abre"},
                    {"ordem":2,"acao":"Num dia, escolher Correção de batida e alterar um horário","resultado_esperado":"O seletor só lista justificativas de correção (ou de lançamento do RH)"},
                    {"ordem":3,"acao":"Noutro dia, escolher Ausência","resultado_esperado":"Pede dia inteiro ou início/fim, só lista justificativas de ausência e exige o anexo"},
                    {"ordem":4,"acao":"Noutro dia, escolher Dia inteiro (lançamento do RH) e uma justificativa que ABONA / NÃO abona / CONFIGURÁVEL","resultado_esperado":"Mostra Abona o dia / Não abona / Abono configurável com o checkbox Abonar o dia"}]'::jsonb,
         resultado_esperado = 'Cada modo lista só as justificativas certas; ausência exige anexo; a diretriz de abono aparece conforme a configuração.',
         observacoes = 'Fase 2 do Ponto, F5 (out/2026): três modos no dia. Validação por homologação MANUAL (fluxo depende de colaborador/catálogo semeados).'
   WHERE codigo = 'PONTO-AJUSTE-FOLGA';

  UPDATE public.qa_casos_teste
     SET observacoes = COALESCE(observacoes, '')
                    || ' | Fase 2 do Ponto (out/2026): o pedido de AUSÊNCIA (natureza ausencia, pelo app ou pelo RH) sempre '
                    || 'leva o documento anexado — sem anexo o banco recusa (PONTO-494) — e, aprovado, vira lançamento em '
                    || 'Atestados (PONTO-495/496). A pendência de comprovação continua valendo para o lançamento de dia '
                    || 'inteiro do RH com justificativa que exige anexo.'
   WHERE codigo = 'ESC-012'
     AND position('Fase 2 do Ponto (out/2026)' IN COALESCE(observacoes, '')) = 0;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentação F5 não registrada: %', SQLERRM;
END $doc$;
