-- =====================================================================
-- PONTO — o dia incompleto vira pendencia, e a falta sai do banco de horas
--
-- DE ONDE VEIO
-- Auditoria de fechamento de 01/09/2026 sobre uma competencia real. Dois
-- achados, os dois cobrando do trabalhador duas vezes pela mesma coisa.
--
-- ACHADO 1 — O DIA COM MARCACAO SEM PAR VIRAVA DEBITO
-- Quando falta uma batida (a pessoa esqueceu a saida, o relogio falhou, a
-- marcacao chegou pela metade), a apuracao do dia ja sabe que a conta esta
-- incompleta: ela marca o dia como "incompleto" e escreve na observacao
-- que as horas do periodo nao pareado NAO foram contabilizadas.
--
-- So que a apuracao de saldo ignorava esse aviso e fazia a conta assim
-- mesmo: horas contadas menos jornada prevista. Como as horas contadas
-- estao sabidamente incompletas, o resultado era um debito enorme —
-- muitas vezes o dia inteiro — lancado contra o trabalhador por uma falha
-- de REGISTRO, que e responsabilidade do empregador (CLT art. 74, §2º;
-- Sumula 338 do TST, que ate presume verdadeira a jornada alegada quando o
-- controle nao se sustenta).
--
-- Agora: dia incompleto NAO GERA DEBITO. O dia fica valendo zero no saldo
-- ate alguem ajustar, que e o que "pendencia" quer dizer. Se as marcacoes
-- que sobraram ja mostram tempo A MAIOR, esse credito e mantido — o que
-- falta so pode aumentar o tempo trabalhado, nunca diminuir.
--
-- ACHADO 2 — A FALTA INJUSTIFICADA ERA DESCONTADA DUAS VEZES
-- A falta injustificada lancava um debito de uma jornada inteira no BANCO
-- DE HORAS. Mas a falta ja e tratada na FOLHA: desconta-se o dia e o
-- repouso da semana (Lei 605/1949, art. 6º). Debitar o banco alem disso e
-- cobrar a mesma ausencia duas vezes — e ainda apaga horas extras que a
-- pessoa realmente trabalhou em outros dias.
--
-- O banco de horas existe para COMPENSAR jornada (CLT art. 59, §2º), nao
-- para punir ausencia. Agora a falta nao entra nele. Ela continua contada
-- e visivel: o espelho tem a coluna de faltas nao justificadas e o total
-- de faltas da competencia, que e o que a folha usa.
--
-- O QUE NAO MUDA
-- Nada mais. Dia justificado, atestado, ferias, feriado, equalizacao,
-- tolerancia, extras e o teto de 120 min/dia seguem exatamente como estao.
-- Nenhum dado e alterado ou apagado: muda a CONTA, e ela e refeita a cada
-- consulta.
-- =====================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- 1) As duas correcoes, por remendo cirurgico sobre o corpo vivo
--    (alcanca os dois nomes: no repositorio a apuracao esta partida em
--    casca + miolo _bruto; em producao ela segue num corpo unico)
-- ---------------------------------------------------------------------
DO $item4$
DECLARE
  v_nome  text;
  v_src   text;
  v_novo  text;
  v_achou boolean := false;
  v_falta_alvo text := E'      ELSIF r.status = ''falta'' THEN\n'
                    || E'        v_diff := -v_jornada_efetiva;';
  v_falta_troca text;
  v_prot_alvo text := E'    IF v_prot_credito AND v_diff < 0 THEN\n'
                   || E'      v_diff := 0;\n'
                   || E'    END IF;';
  v_prot_troca text;
BEGIN
  v_falta_troca := E'      ELSIF r.status = ''falta'' THEN\n'
                || E'        -- [falta-fora-do-banco] A falta injustificada ja e descontada na\n'
                || E'        -- FOLHA (o dia e o repouso da semana, Lei 605/1949 art. 6). Debitar\n'
                || E'        -- o banco de horas alem disso cobra a mesma ausencia duas vezes e\n'
                || E'        -- apaga extras realmente trabalhadas. O banco compensa jornada (CLT\n'
                || E'        -- art. 59, §2º), nao pune ausencia. A falta segue contada na coluna\n'
                || E'        -- de faltas e no total da competencia.\n'
                || E'        v_diff := 0;';

  v_prot_troca := E'    -- [dia-incompleto] Marcacao sem par: a apuracao do dia ja avisou que\n'
               || E'    -- as horas do periodo nao pareado NAO foram contabilizadas. Fazer a\n'
               || E'    -- conta assim mesmo transformava uma falha de REGISTRO — que e do\n'
               || E'    -- empregador (CLT art. 74, §2º; Sumula 338 do TST) — em debito do\n'
               || E'    -- trabalhador. O dia fica valendo zero ate alguem ajustar. Credito\n'
               || E'    -- apurado e mantido: o que falta so pode aumentar o tempo trabalhado.\n'
               || E'    IF r.status = ''incompleto'' AND v_diff < 0 THEN\n'
               || E'      v_diff := 0;\n'
               || E'    END IF;\n'
               || E'\n'
               || v_prot_alvo;

  FOREACH v_nome IN ARRAY ARRAY['ponto_saldo_dias_competencia_bruto',
                                'ponto_saldo_dias_competencia'] LOOP
    SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = v_nome
      AND pg_get_function_identity_arguments(p.oid)
          = 'p_tenant_id uuid, p_colaborador_cpf text, p_competencia text'
    LIMIT 1;

    IF v_src IS NULL OR position('v_tol_bat' IN v_src) = 0 THEN
      -- Nao existe, ou e so a casca que delega para o miolo.
      CONTINUE;
    END IF;

    IF position('[dia-incompleto]' IN v_src) > 0
       AND position('[falta-fora-do-banco]' IN v_src) > 0 THEN
      RAISE NOTICE '% ja trata dia incompleto como pendencia e mantem a falta fora do banco — nada a fazer.', v_nome;
      v_achou := true;
      CONTINUE;
    END IF;

    IF position(v_falta_alvo IN v_src) = 0 OR position(v_prot_alvo IN v_src) = 0 THEN
      RAISE NOTICE 'ATENCAO: em % os trechos esperados nao foram encontrados. O corpo foi alterado por outro caminho; NADA foi mexido nesta funcao. Envie o pg_get_functiondef para reconciliarmos a mao.', v_nome;
      CONTINUE;
    END IF;

    v_novo := replace(v_src, v_falta_alvo, v_falta_troca);
    v_novo := replace(v_novo, v_prot_alvo, v_prot_troca);
    EXECUTE v_novo;
    v_achou := true;
    RAISE NOTICE 'Em %: dia incompleto vira pendencia e a falta sai do banco de horas.', v_nome;
  END LOOP;

  IF NOT v_achou THEN
    RAISE NOTICE 'A apuracao de saldo nao foi encontrada nesta base — nada a corrigir.';
  END IF;
END $item4$;

-- ---------------------------------------------------------------------
-- 2) PONTO-473 — dia incompleto nao vira debito
-- ---------------------------------------------------------------------
INSERT INTO public.qa_casos_teste
  (codigo, modulo_id, titulo, objetivo, tipo, nivel, prioridade, status,
   base_legal, passos, disposicao, observacoes)
SELECT
  'PONTO-473',
  m.id,
  'Dia com marcação sem par é pendência, não é débito',
  'Quando falta uma batida, a apuração do dia já sabe que a conta está incompleta e avisa '
  || 'na observação que as horas do período não pareado não foram contabilizadas. Fazer a conta '
  || 'assim mesmo — horas contadas menos jornada prevista — transforma uma falha de REGISTRO, '
  || 'que é responsabilidade do empregador (CLT art. 74, §2º; Súmula 338 do TST), em débito do '
  || 'trabalhador, muitas vezes de um dia inteiro. O dia tem de ficar valendo zero no saldo até '
  || 'alguém ajustar. Crédito já apurado é mantido: o que falta só pode aumentar o tempo '
  || 'trabalhado, nunca diminuir.',
  'negativo',
  'api',
  'critica',
  'aprovado',
  'CLT art. 74, §2º; Súmula 338 do TST',
  jsonb_build_array(
    jsonb_build_object('ordem', 1,
      'acao', 'Apurar um dia marcado como incompleto, com menos horas contadas que a jornada',
      'esperado', 'Saldo 0 — o dia não gera débito enquanto a marcação não for completada'),
    jsonb_build_object('ordem', 2,
      'acao', 'Conferir que um dia REGULAR com a mesma falta de horas continua gerando débito',
      'esperado', 'Saldo negativo — a regra vale só para o dia incompleto, não afrouxa o resto')
  ),
  'em_triagem',
  'Nasceu da auditoria de fechamento de 01/09/2026 feita por especialista em DP.'
FROM public.qa_modulos m
WHERE m.path = 'jornada-rotina/ponto'
ON CONFLICT (codigo) DO NOTHING;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_473()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid;
  v_cpf text := public.qa_cpf(4731);
  v_cpf2 text := public.qa_cpf(4732);
  v_base date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
  v_d1 date;
  v_inc int;
  v_reg int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Apurar um dia incompleto com 300 min contados contra jornada de 480';
  r.esperado    := 'Saldo 0 — falha de registro não vira débito do trabalhador';

  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();
  v_d1 := v_base + ((8 - EXTRACT(ISODOW FROM v_base)::int) % 7);

  -- Dia INCOMPLETO: a marcação de saída não veio, e só 300 min foram contados.
  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Dia Incompleto', 480, 10, v_d1, v_d1);
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Dia Incompleto', v_d1, 300);
  UPDATE public.ponto_diario
     SET status = 'incompleto'
   WHERE tenant_id = v_t AND colaborador_cpf = v_cpf AND data = v_d1;

  -- Controle: mesmo buraco de horas, mas dia REGULAR — tem de seguir devendo.
  PERFORM public.qa_ponto_escala_tol(v_cpf2, 'QA Dia Regular', 480, 10, v_d1, v_d1);
  PERFORM public.qa_ponto_dia_min(v_cpf2, 'QA Dia Regular', v_d1, 300);

  SELECT s.saldo_min INTO v_inc
  FROM public.ponto_saldo_dias_competencia(v_t, v_cpf, to_char(v_d1, 'YYYY-MM')) s
  WHERE s.dia = v_d1;

  SELECT s.saldo_min INTO v_reg
  FROM public.ponto_saldo_dias_competencia(v_t, v_cpf2, to_char(v_d1, 'YYYY-MM')) s
  WHERE s.dia = v_d1;

  IF COALESCE(v_inc, -999) = 0 AND COALESCE(v_reg, 0) < 0 THEN
    r.situacao := 'passou';
    r.obtido := format('O dia incompleto fechou em 0 e o dia regular com o mesmo buraco fechou '
             || 'em %s: a pendencia nao vira debito, e a regra nao afrouxou o resto.', v_reg);
  ELSIF COALESCE(v_inc, 0) < 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o dia com marcacao sem par gerou debito de %s minutos. A propria '
             || 'apuracao do dia marcou o dia como incompleto e avisou que as horas do periodo '
             || 'nao pareado NAO foram contabilizadas — e a apuracao de saldo fez a conta assim '
             || 'mesmo. O trabalhador paga, em horas, por uma falha de REGISTRO que e do '
             || 'empregador (CLT art. 74, §2º; Sumula 338 do TST). Correcao: dia incompleto '
             || 'fica valendo zero ate o ajuste.', v_inc);
    r.detalhe := jsonb_build_object('saldo_dia_incompleto', v_inc, 'saldo_dia_regular', v_reg);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Resultado inesperado: dia incompleto deu %s (esperado 0) e dia regular '
             || 'deu %s (esperado negativo).',
             coalesce(v_inc::text, 'sem linha'), coalesce(v_reg::text, 'sem linha'));
    r.detalhe := jsonb_build_object('saldo_dia_incompleto', v_inc, 'saldo_dia_regular', v_reg);
  END IF;

  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
VALUES ('PONTO-473', 'qa_caso_ponto_473', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- ---------------------------------------------------------------------
-- 3) PONTO-474 — falta injustificada nao debita o banco de horas
-- ---------------------------------------------------------------------
INSERT INTO public.qa_casos_teste
  (codigo, modulo_id, titulo, objetivo, tipo, nivel, prioridade, status,
   base_legal, passos, disposicao, observacoes)
SELECT
  'PONTO-474',
  m.id,
  'Falta injustificada não é descontada duas vezes',
  'A falta injustificada é tratada na FOLHA: desconta-se o dia e o repouso semanal remunerado '
  || '(Lei 605/1949, art. 6º). Debitar também o banco de horas cobra a mesma ausência duas vezes '
  || 'e ainda apaga horas extras realmente trabalhadas em outros dias. O banco existe para '
  || 'compensar jornada (CLT art. 59, §2º), não para punir ausência. A falta continua contada e '
  || 'visível no espelho, que é o que a folha usa.',
  'negativo',
  'api',
  'critica',
  'aprovado',
  'CLT art. 59, §2º; Lei 605/1949, art. 6º',
  jsonb_build_array(
    jsonb_build_object('ordem', 1,
      'acao', 'Apurar uma competência com um dia de falta injustificada e um dia com 60 min de extra',
      'esperado', 'O saldo do mês é +60: a falta não come a hora extra'),
    jsonb_build_object('ordem', 2,
      'acao', 'Conferir que a falta continua contada no espelho',
      'esperado', 'O total de faltas da competência registra o dia — a informação não se perde')
  ),
  'em_triagem',
  'Nasceu da auditoria de fechamento de 01/09/2026 feita por especialista em DP.'
FROM public.qa_modulos m
WHERE m.path = 'jornada-rotina/ponto'
ON CONFLICT (codigo) DO NOTHING;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_474()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid;
  v_cpf text := public.qa_cpf(4741);
  v_base date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
  v_d1 date; v_d2 date;
  v_comp text;
  v_saldo_falta int;
  v_total int;
  v_faltas int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Apurar um mês com uma falta injustificada e um dia com 60 min de extra';
  r.esperado    := 'Saldo do mês +60 e a falta contada no espelho — descontada na folha, não no banco';

  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();

  v_d1   := v_base + ((8 - EXTRACT(ISODOW FROM v_base)::int) % 7);  -- segunda
  v_d2   := v_d1 + 1;                                               -- terça
  v_comp := to_char(v_d1, 'YYYY-MM');

  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Falta Fora do Banco', 480, 10, v_d1, v_d2);
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Falta Fora do Banco', v_d1, 540);  -- +60
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Falta Fora do Banco', v_d2, 0);
  UPDATE public.ponto_diario
     SET status = 'falta', entrada = NULL, saida = NULL,
         horas_trabalhadas = INTERVAL '0'
   WHERE tenant_id = v_t AND colaborador_cpf = v_cpf AND data = v_d2;

  SELECT s.saldo_min INTO v_saldo_falta
  FROM public.ponto_saldo_dias_competencia(v_t, v_cpf, v_comp) s
  WHERE s.dia = v_d2;

  SELECT COALESCE(SUM(s.saldo_min), 0) INTO v_total
  FROM public.ponto_saldo_dias_competencia(v_t, v_cpf, v_comp) s;

  SELECT e.total_faltas INTO v_faltas
  FROM public.ponto_espelho_resumo(v_t, v_cpf, v_comp) e;

  IF COALESCE(v_saldo_falta, -999) = 0 AND v_total = 60 AND COALESCE(v_faltas, 0) >= 1 THEN
    r.situacao := 'passou';
    r.obtido := format('A falta ficou fora do banco: o dia fechou em 0, o mes fechou em +60 (a '
             || 'hora extra sobreviveu) e o espelho conta %s falta(s) — a informacao que a folha '
             || 'usa nao se perdeu.', v_faltas);
  ELSIF COALESCE(v_saldo_falta, 0) < 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a falta injustificada debitou %s minutos do banco de horas, e o '
             || 'mes fechou em %s em vez de +60. A falta ja e descontada na folha (o dia e o '
             || 'repouso da semana, Lei 605/1949 art. 6) — debitar o banco alem disso cobra a '
             || 'mesma ausencia duas vezes e apaga hora extra realmente trabalhada. O banco '
             || 'compensa jornada (CLT art. 59, §2º), nao pune ausencia.', v_saldo_falta, v_total);
    r.detalhe := jsonb_build_object('saldo_do_dia_de_falta', v_saldo_falta,
                                    'saldo_do_mes', v_total, 'faltas_no_espelho', v_faltas);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Resultado inesperado: dia de falta %s (esperado 0), mes %s (esperado 60), '
             || 'faltas no espelho %s (esperado ao menos 1).',
             coalesce(v_saldo_falta::text, 'sem linha'), v_total, coalesce(v_faltas::text, '-'));
    r.detalhe := jsonb_build_object('saldo_do_dia_de_falta', v_saldo_falta,
                                    'saldo_do_mes', v_total, 'faltas_no_espelho', v_faltas);
  END IF;

  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
VALUES ('PONTO-474', 'qa_caso_ponto_474', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

DO $fim$
BEGIN
  RAISE NOTICE 'Dia incompleto e pendencia; falta injustificada fica fora do banco de horas.';
END $fim$;
