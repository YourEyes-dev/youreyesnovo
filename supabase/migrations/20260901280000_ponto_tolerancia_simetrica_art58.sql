-- =====================================================================
-- PONTO — a tolerancia passa a valer a MESMA REGUA nos dois sentidos
--
-- DE ONDE VEIO
-- Auditoria de fechamento de uma cliente real (competencia 08/2026, feita
-- por especialista em DP em 01/09/2026). Ela apontou que o sistema tratava
-- o atraso e a sobra com pesos diferentes:
--
--   * o trabalhador que ficava 6 minutos A MENOS tinha os 6 descontados;
--   * o trabalhador que ficava 10 minutos A MAIS nao recebia nada.
--
-- Ou seja: a tolerancia mordia so de um lado. Toda variacao de fronteira
-- entre 6 e 10 minutos era perda certa para quem trabalha.
--
-- O QUE A LEI DIZ
-- CLT art. 58, §1º: nao serao descontadas NEM COMPUTADAS como jornada
-- extraordinaria as variacoes de ate 5 minutos POR MARCACAO, observado o
-- limite de 10 minutos DIARIOS. Sumula 366 do TST: ultrapassado qualquer
-- um dos limites, computa-se a TOTALIDADE do tempo — nao so o excedente.
--
-- O texto e simetrico de proposito: "nao serao descontadas nem computadas"
-- e a mesma frase para os dois lados. Nao ha na lei um teto para o atraso e
-- outro, maior, para a sobra.
--
-- A CORRECAO
-- Os dois blocos de tolerancia da apuracao passam a usar um unico teste:
--
--     IF abs(v_diff) <= LEAST(teto_por_marcacao, teto_diario) THEN 0
--
-- onde teto_por_marcacao e o da escala (padrao 5) e teto_diario e o
-- configurado na escala, ou 10 quando nada foi configurado. O LEAST
-- garante os dois limites CUMULATIVOS: nenhum dos dois pode ser furado.
--
-- O QUE MUDA NA PRATICA
--   -6 min -> -6  (ja era assim)
--   +6 min -> +6  (antes virava 0: era o lado que so o patrao ganhava)
--   +-5 min -> 0  (dentro do limite legal, nos dois sentidos)
-- Escala com tolerancia MENOR que 5 (ex.: 3) manda nos dois lados: 4 min
-- passa a contar, para mais e para menos.
--
-- O CASO PONTO-353 MUDA DE EXPECTATIVA, e de proposito: ele documentava
-- "+10 no dia nao computa", que era exatamente a assimetria. A fronteira
-- correta e a mesma do PONTO-041 (deficit): 5 absorve, 6 computa inteiro.
-- O PONTO-471, novo, prova que os dois sentidos tem o mesmo peso.
--
-- NADA MAIS MUDA: jornada, intervalo, banco de horas, extras e o teto de
-- 120 min/dia seguem exatamente como estao.
-- =====================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- 1) A correcao, por remendo cirurgico sobre o corpo vivo
--    Alcanca os DOIS nomes porque os ambientes divergem: no repositorio a
--    apuracao esta partida em casca + miolo (_bruto); em producao e na
--    homologacao ela segue num corpo monolitico so. O que os dois tem
--    identico e justamente o bloco trocado aqui (ele nasceu do mesmo
--    remendo da onda 3).
-- ---------------------------------------------------------------------
DO $simetria$
DECLARE
  v_nome  text;
  v_src   text;
  v_novo  text;
  v_teto  text := 'LEAST(COALESCE(v_tol_bat, 5), COALESCE(NULLIF(v_tol, 0), 10))';
  v_alvo1 text := E'        IF v_diff < 0 THEN\n'
               || E'          IF abs(v_diff) <= COALESCE(v_tol_bat, 5) THEN\n'
               || E'            v_diff := 0;\n'
               || E'          END IF;\n'
               || E'        ELSIF abs(v_diff) <= COALESCE(v_tol, 0) THEN\n'
               || E'          v_diff := 0;\n'
               || E'        END IF;';
  v_alvo2 text := E'    IF v_diff < 0 THEN\n'
               || E'      IF abs(v_diff) <= COALESCE(v_tol_bat, 5) THEN\n'
               || E'        v_diff := 0;\n'
               || E'      END IF;\n'
               || E'    ELSIF v_diff <= 10 THEN\n'
               || E'      v_diff := 0;\n'
               || E'    END IF;';
  v_troca1 text;
  v_troca2 text;
  v_achou  boolean := false;
BEGIN
  v_troca1 := E'        -- [tol-simetrica] a mesma regua nos dois sentidos: 5 min por\n'
           || E'        -- marcacao, teto de 10 no dia (art. 58 §1º + Sumula 366).\n'
           || E'        IF abs(v_diff) <= ' || v_teto || E' THEN\n'
           || E'          v_diff := 0;\n'
           || E'        END IF;';
  v_troca2 := E'    -- [tol-simetrica] a mesma regua nos dois sentidos: 5 min por\n'
           || E'    -- marcacao, teto de 10 no dia (art. 58 §1º + Sumula 366).\n'
           || E'    -- Estourou, computa-se a TOTALIDADE, para mais e para menos.\n'
           || E'    IF abs(v_diff) <= ' || v_teto || E' THEN\n'
           || E'      v_diff := 0;\n'
           || E'    END IF;';

  FOREACH v_nome IN ARRAY ARRAY['ponto_saldo_dias_competencia_bruto',
                                'ponto_saldo_dias_competencia'] LOOP
    SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = v_nome
      AND pg_get_function_identity_arguments(p.oid)
          = 'p_tenant_id uuid, p_colaborador_cpf text, p_competencia text'
    LIMIT 1;

    IF v_src IS NULL THEN
      CONTINUE;
    END IF;

    IF position('[tol-simetrica]' IN v_src) > 0 THEN
      RAISE NOTICE '% ja aplica a mesma regua nos dois sentidos — nada a fazer.', v_nome;
      v_achou := true;
      CONTINUE;
    END IF;

    -- No repositorio, ponto_saldo_dias_competencia e so a casca que delega
    -- para o miolo: nao tem conta de tolerancia nenhuma para trocar.
    IF position('v_tol_bat' IN v_src) = 0 THEN
      CONTINUE;
    END IF;

    IF position(v_alvo2 IN v_src) = 0 THEN
      RAISE NOTICE 'ATENCAO: em % o bloco de tolerancia esperado nao foi encontrado. O corpo foi alterado por outro caminho; NADA foi mexido nesta funcao. Envie o pg_get_functiondef para reconciliarmos a mao.', v_nome;
      CONTINUE;
    END IF;

    v_novo := replace(v_src, v_alvo1, v_troca1);
    v_novo := replace(v_novo, v_alvo2, v_troca2);

    -- Os comentarios da regra ANTIGA passariam a dizer o contrario do codigo.
    -- Saem daqui — nas duas redacoes que existem (a da producao, sem acento,
    -- e a do repositorio). Se alguma nao casar, sobra so um comentario velho:
    -- nada de calculo depende disto.
    v_novo := replace(v_novo,
      E'        -- [onda3-tol] deficit absorvido so ate o teto POR MARCACAO\n'
   || E'        -- (art. 58 §1º / Sumula 366); sobra mantem o teto DIARIO.\n', '');
    v_novo := replace(v_novo,
      E'    -- [onda3-tol] dois tetos cumulativos (art. 58 §1º + Sumula 366):\n'
   || E'    -- deficit no teto POR MARCACAO; sobra no teto DIARIO (10). Estourou\n'
   || E'    -- qualquer um, computa-se a totalidade que excede a jornada.\n', '');
    v_novo := replace(v_novo,
      E'        -- Déficit absorvido só até o teto POR MARCAÇÃO (art. 58 §1º / Súmula\n'
   || E'        -- 366); sobra no dia mantém o teto DIÁRIO configurado.\n', '');
    v_novo := replace(v_novo,
      E'    -- Tolerância do art. 58, §1º + Súmula 366, com os dois tetos cumulativos:\n'
   || E'    --   · déficit (atraso/antecipação): absorvido só até o teto POR MARCAÇÃO;\n'
   || E'    --   · sobra no dia: absorvida até o teto DIÁRIO (10).\n'
   || E'    -- Estourou o teto aplicável, computa-se a TOTALIDADE (não só o excedente).\n', '');

    EXECUTE v_novo;
    v_achou := true;
    RAISE NOTICE 'Tolerancia simetrica aplicada em %.', v_nome;
  END LOOP;

  IF NOT v_achou THEN
    RAISE NOTICE 'A apuracao de saldo nao foi encontrada nesta base — nada a corrigir.';
  END IF;
END $simetria$;

-- ---------------------------------------------------------------------
-- 2) PONTO-353 muda de expectativa: a fronteira da SOBRA e a mesma do
--    deficit. O texto do caso e reescrito junto com a rotina, para a
--    documentacao nao ficar dizendo o contrario do sistema.
-- ---------------------------------------------------------------------
UPDATE public.qa_casos_teste
   SET titulo = 'Fronteira da sobra é a mesma do atraso: 5 min absorve, 6 computa inteiro',
       objetivo = 'O art. 58, §1º é simétrico: as variações de até 5 minutos por marcação, '
                || 'observado o limite de 10 minutos diários, não são descontadas NEM computadas '
                || 'como extra. Não existe na lei um teto para o atraso e outro, maior, para a '
                || 'sobra. Ultrapassado o limite, computa-se a totalidade (Súmula 366), para os '
                || 'dois lados.',
       base_legal = 'CLT art. 58, §1º; Súmula 366 do TST',
       passos = jsonb_build_array(
         jsonb_build_object('ordem', 1,
           'acao', 'Apurar um dia com exatos 5 minutos a MAIS que a jornada',
           'esperado', 'Saldo 0 — dentro do limite legal'),
         jsonb_build_object('ordem', 2,
           'acao', 'Apurar um dia com 6 minutos a MAIS que a jornada',
           'esperado', 'Saldo +6 INTEIRO — estourou o limite, computa-se a totalidade')
       ),
       observacoes = 'Reescrito em 01/09/2026. A versão anterior documentava "+10 no dia não '
                || 'computa", que era justamente a assimetria apontada pela auditoria de '
                || 'fechamento: o atraso de 6 min era descontado e a sobra de 10 min não era '
                || 'paga. A simetria é provada pelo PONTO-471.'
 WHERE codigo = 'PONTO-353';

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_353()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_cpf text := public.qa_cpf(3531);
  v_base date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
  v_d1 date; v_d2 date;
  v_s1 int; v_s2 int;
BEGIN
  v_d1 := v_base + ((8 - EXTRACT(ISODOW FROM v_base)::int) % 7);  -- segunda-feira
  v_d2 := v_d1 + 1;                                               -- terça-feira

  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Fronteira Sobra', 480, 10, v_d1, v_d2);
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Fronteira Sobra', v_d1, 485);  -- +5 min
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Fronteira Sobra', v_d2, 486);  -- +6 min

  r.passo_ordem := 1;
  r.passo_acao := format('Apurar dois dias com jornada de 480: %s com 485 min e %s com 486 min', v_d1, v_d2);
  r.esperado := '+5 min: saldo 0 (dentro do limite). +6 min: saldo +6 INTEIRO, não só o excedente';

  SELECT max(s.saldo_min) FILTER (WHERE s.dia = v_d1),
         max(s.saldo_min) FILTER (WHERE s.dia = v_d2)
    INTO v_s1, v_s2
  FROM public.ponto_saldo_dias_competencia(public.qa_sandbox_tenant_id(), v_cpf,
                                           to_char(v_d1, 'YYYY-MM')) s;

  IF v_s1 = 0 AND v_s2 = 6 THEN
    r.situacao := 'passou';
    r.obtido := 'Fronteira da sobra igual à do atraso: +5 min absorvidos e +6 min computados '
             || 'por inteiro, como manda a Súmula 366.';
  ELSIF v_s1 = 0 AND v_s2 = 0 THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a sobra de 6 minutos foi ZERADA, enquanto um atraso de 6 minutos é '
             || 'descontado por inteiro (PONTO-041). A tolerância está mordendo só de um lado: '
             || 'toda variação entre 6 e 10 minutos vira perda certa para quem trabalha. O art. '
             || '58, §1º usa a mesma frase para os dois sentidos ("não serão descontadas nem '
             || 'computadas"). Correção: um único teste, abs(saldo) <= menor dos dois tetos.';
    r.detalhe := jsonb_build_object('saldo_5min', v_s1, 'saldo_6min', v_s2);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Fronteira errada: +5 min rendeu %s (esperado 0) e +6 min rendeu %s '
             || '(esperado 6).', coalesce(v_s1::text, 'sem linha'), coalesce(v_s2::text, 'sem linha'));
    r.detalhe := jsonb_build_object('saldo_5min', v_s1, 'saldo_6min', v_s2);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $function$;

-- ---------------------------------------------------------------------
-- 3) PONTO-471 — a prova da simetria, e do teto configurado abaixo de 5
-- ---------------------------------------------------------------------
INSERT INTO public.qa_casos_teste
  (codigo, modulo_id, titulo, objetivo, tipo, nivel, prioridade, status,
   base_legal, passos, disposicao, observacoes)
SELECT
  'PONTO-471',
  m.id,
  'A tolerância pesa igual para os dois lados',
  'A mesma variação, em minutos, tem de dar o mesmo número no saldo — só que com o sinal '
  || 'trocado. Se 6 minutos a menos descontam 6, então 6 minutos a mais têm de creditar 6. '
  || 'E quando a escala configura uma tolerância MENOR que o limite legal por marcação, é ela '
  || 'que manda — também nos dois sentidos.',
  'feliz',
  'api',
  'critica',
  'aprovado',
  'CLT art. 58, §1º; Súmula 366 do TST',
  jsonb_build_array(
    jsonb_build_object('ordem', 1,
      'acao', 'Apurar um dia com 6 minutos a menos e outro com 6 minutos a mais, mesma escala',
      'esperado', 'Saldos -6 e +6: mesma grandeza, sinais opostos'),
    jsonb_build_object('ordem', 2,
      'acao', 'Com escala de tolerância 3 (abaixo do limite legal), apurar 4 min a mais e 4 a menos',
      'esperado', 'Saldos -4 e +4: a tolerância configurada manda, e manda nos dois sentidos')
  ),
  'em_triagem',
  'Nasceu da auditoria de fechamento de 01/09/2026. Complementa o PONTO-041 (fronteira do '
  || 'atraso) e o PONTO-353 (fronteira da sobra), provando que as duas são a mesma régua.'
FROM public.qa_modulos m
WHERE m.path = 'jornada-rotina/ponto'
ON CONFLICT (codigo) DO NOTHING;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_471()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid;
  v_cpf text := public.qa_cpf(4711);
  v_cpf2 text := public.qa_cpf(4712);
  v_base date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
  v_d1 date; v_d2 date;
  v_menos int; v_mais int;
  v_menos3 int; v_mais3 int;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();

  v_d1 := v_base + ((8 - EXTRACT(ISODOW FROM v_base)::int) % 7);  -- segunda-feira
  v_d2 := v_d1 + 1;                                               -- terça-feira

  r.passo_ordem := 1;
  r.passo_acao := 'Apurar 6 minutos a menos e 6 minutos a mais na mesma escala';
  r.esperado    := 'Saldos -6 e +6 — mesma grandeza, sinais opostos';

  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Simetria', 480, 10, v_d1, v_d2);
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Simetria', v_d1, 474);  -- -6
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Simetria', v_d2, 486);  -- +6

  SELECT max(s.saldo_min) FILTER (WHERE s.dia = v_d1),
         max(s.saldo_min) FILTER (WHERE s.dia = v_d2)
    INTO v_menos, v_mais
  FROM public.ponto_saldo_dias_competencia(v_t, v_cpf, to_char(v_d1, 'YYYY-MM')) s;

  IF coalesce(v_menos, 99) <> -6 OR coalesce(v_mais, 99) <> 6 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a mesma variação de 6 minutos deu %s para menos e %s para mais '
             || '(esperado -6 e +6). A tolerância está pesando diferente conforme o lado que '
             || 'favorece. O art. 58, §1º usa a mesma frase para os dois sentidos ("não serão '
             || 'descontadas nem computadas"), e a Súmula 366 manda computar a totalidade '
             || 'quando o limite é ultrapassado — também na sobra.',
             coalesce(v_menos::text, 'sem linha'), coalesce(v_mais::text, 'sem linha'));
    r.detalhe := jsonb_build_object('saldo_menos_6', v_menos, 'saldo_mais_6', v_mais);
    RETURN r;
  END IF;

  r.passo_ordem := 2;
  r.passo_acao := 'Com escala de tolerância 3, apurar 4 minutos para menos e para mais';
  r.esperado    := 'Saldos -4 e +4 — a tolerância configurada manda nos dois sentidos';

  PERFORM public.qa_ponto_escala_tol(v_cpf2, 'QA Simetria Tol 3', 480, 3, v_d1, v_d2);
  PERFORM public.qa_ponto_dia_min(v_cpf2, 'QA Simetria Tol 3', v_d1, 476);  -- -4
  PERFORM public.qa_ponto_dia_min(v_cpf2, 'QA Simetria Tol 3', v_d2, 484);  -- +4

  SELECT max(s.saldo_min) FILTER (WHERE s.dia = v_d1),
         max(s.saldo_min) FILTER (WHERE s.dia = v_d2)
    INTO v_menos3, v_mais3
  FROM public.ponto_saldo_dias_competencia(v_t, v_cpf2, to_char(v_d1, 'YYYY-MM')) s;

  IF coalesce(v_menos3, 99) = -4 AND coalesce(v_mais3, 99) = 4 THEN
    r.situacao := 'passou';
    r.obtido := 'A régua é a mesma nos dois sentidos: 6 min renderam -6 e +6, e com tolerância '
             || 'configurada em 3 os 4 minutos passaram a contar para menos e para mais.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: com tolerância configurada em 3 minutos, uma variação de 4 deu '
             || '%s para menos e %s para mais (esperado -4 e +4). A tolerância da escala não '
             || 'está sendo respeitada, ou não está sendo respeitada nos dois sentidos — a '
             || 'empresa que adota régua menor que a legal não consegue aplicá-la.',
             coalesce(v_menos3::text, 'sem linha'), coalesce(v_mais3::text, 'sem linha'));
    r.detalhe := jsonb_build_object('saldo_menos_4', v_menos3, 'saldo_mais_4', v_mais3);
  END IF;

  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
VALUES ('PONTO-471', 'qa_caso_ponto_471', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

DO $fim$
BEGIN
  RAISE NOTICE 'Tolerancia simetrica: a mesma regua para o atraso e para a sobra.';
END $fim$;
