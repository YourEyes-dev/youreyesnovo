-- =====================================================================
-- PONTO — o minuto do registro deixa de sumir na conta do dia
--
-- DE ONDE VEIO
-- Auditoria de fechamento de uma cliente real (competencia 08/2026, feita
-- por um especialista em DP em 01/09/2026). Somando as marcacoes impressas
-- no proprio espelho, o mes dava 179h39; o espelho fechava 179h19. Vinte
-- minutos a menos, e SEMPRE para baixo — nunca para cima.
--
-- A CAUSA
-- A apuracao do dia media cada par entrada/saida em SEGUNDOS e so entao
-- truncava para minutos:
--
--     v_dif := FLOOR(EXTRACT(EPOCH FROM (saida - entrada)) / 60)
--
-- Com dois pares por dia, isso descarta ate 59 segundos DUAS VEZES por dia,
-- sempre no mesmo sentido. Da cerca de 1 a 2 minutos por dia, 20 por mes,
-- perto de 4 horas por ano — todas contra o trabalhador.
--
-- Exemplo do proprio espelho, dia 03/08: 07:25-12:03 mais 13:03-17:35 sao
-- 550 minutos; o sistema imprimia 549.
--
-- A CORRECAO
-- O registro legal do ponto e em HORA E MINUTO — o AFD da Portaria MTP
-- 671/2021 nao tem campo de segundos, e e o minuto que o trabalhador ve e
-- assina no espelho. Entao o truncamento passa a ser feito EM CADA
-- MARCACAO, antes da subtracao, e nao no resultado dela:
--
--     v_dif := minuto(saida) - minuto(entrada)
--
-- Assim 07:25:43 -> 12:03:12 conta 278 minutos (12:03 menos 07:25), que e
-- exatamente o que o espelho mostra. Nenhum minuto se perde no caminho, e a
-- conta passa a bater com o documento que o trabalhador assina.
--
-- POR QUE ISSO NAO E O PONTO-401
-- O PONTO-401 conferia se o EXCEDENTE era arredondado, e media com
-- marcacoes em minutos redondos — onde este defeito nao aparece. Ele
-- continua valendo; este caso (PONTO-470) cobre a perda que so existe
-- quando a marcacao tem segundos.
--
-- NADA MAIS MUDA. A regra de tolerancia, o calculo de extras e o saldo do
-- banco seguem exatamente como estao; o que muda e o numero de minutos
-- trabalhados de onde tudo parte.
-- =====================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- 1) A correcao, aplicada por remendo sobre a definicao vigente
--    (a funcao difere entre ambientes; trocar a expressao e mais seguro
--    do que reescrever o corpo inteiro por cima)
-- ---------------------------------------------------------------------
DO $corrige$
DECLARE
  v_src  text;
  v_novo text;
  v_alvo text := 'v_dif := FLOOR(EXTRACT(EPOCH FROM (v_marc.hora_marcacao - v_abr)) / 60)::INT;';
  v_troca text := 'v_dif := floor(EXTRACT(EPOCH FROM v_marc.hora_marcacao) / 60)::INT'
               || ' - floor(EXTRACT(EPOCH FROM v_abr) / 60)::INT;';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = '_ponto_calc_dia';

  IF v_src IS NULL THEN
    RAISE NOTICE 'A apuracao do dia (_ponto_calc_dia) nao existe nesta base — nada a corrigir.';
    RETURN;
  END IF;

  IF position(v_troca IN v_src) > 0 THEN
    RAISE NOTICE 'A apuracao do dia ja conta pelo minuto de cada marcacao — nada a fazer.';
    RETURN;
  END IF;

  IF position(v_alvo IN v_src) = 0 THEN
    RAISE NOTICE 'ATENCAO: a expressao esperada nao foi encontrada em _ponto_calc_dia. A funcao foi alterada por outro caminho; a correcao NAO foi aplicada. Confira manualmente antes de seguir.';
    RETURN;
  END IF;

  v_novo := replace(v_src, v_alvo, v_troca);
  v_novo := replace(v_novo,
    '-- Trunca os segundos (FLOOR) para alinhar com a exibição do Espelho',
    '-- O registro legal e em hora e minuto (AFD da Portaria 671 nao tem'
    || E'\n        -- segundos). Trunca-se CADA MARCACAO antes de subtrair: truncar a'
    || E'\n        -- diferenca perdia ate 59s por par, duas vezes ao dia, sempre'
    || E'\n        -- contra o trabalhador (PONTO-470).');

  EXECUTE v_novo;
  RAISE NOTICE 'Apuracao do dia corrigida: o minuto de cada marcacao passa a ser a unidade da conta.';
END $corrige$;

-- ---------------------------------------------------------------------
-- 2) O caso de teste que prova a correcao
-- ---------------------------------------------------------------------
INSERT INTO public.qa_casos_teste
  (codigo, modulo_id, titulo, objetivo, tipo, nivel, prioridade, status,
   base_legal, passos, disposicao, observacoes)
SELECT
  'PONTO-470',
  m.id,
  'Marcação com segundos não faz o dia perder minuto',
  'O registro legal da jornada é em hora e minuto: o AFD da Portaria MTP 671/2021 não '
  || 'tem campo de segundos, e é o minuto que o trabalhador vê e assina no espelho. A conta '
  || 'do dia tem de truncar CADA MARCAÇÃO e só então subtrair. Truncar a diferença descarta '
  || 'até 59 segundos por par de marcações — duas vezes ao dia, sempre para baixo. Numa '
  || 'auditoria de fechamento real isso deu 20 minutos no mês e perto de 4 horas no ano, '
  || 'todas contra a trabalhadora.',
  'feliz',
  'api',
  'critica',
  'aprovado',
  'CLT art. 74, §2º; Portaria MTP 671/2021 (leiaute do AFD, hora e minuto); Súmula 338 do TST',
  jsonb_build_array(
    jsonb_build_object('ordem', 1,
      'acao', 'Registrar um dia com quatro marcações COM SEGUNDOS (07:25:43, 12:03:12, 13:03:51, 17:35:29)',
      'esperado', 'O dia conta 550 minutos — 12:03 menos 07:25 mais 17:35 menos 13:03'),
    jsonb_build_object('ordem', 2,
      'acao', 'Conferir contra o que o espelho mostraria',
      'esperado', 'O número da apuração e o do espelho são o mesmo: nenhum minuto se perde entre um e outro')
  ),
  'em_triagem',
  'Nasceu da auditoria de fechamento de 01/09/2026 feita por especialista em DP sobre uma '
  || 'competência real. Complementa o PONTO-401, que confere o arredondamento do excedente e '
  || 'mede com marcações em minutos redondos, onde esta perda não aparece.'
FROM public.qa_modulos m
WHERE m.path = 'jornada-rotina/ponto'
ON CONFLICT (codigo) DO NOTHING;

-- ---------------------------------------------------------------------
-- 3) A rotina que executa o caso
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_470()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid;
  v_cpf text;
  v_cid uuid;
  v_dia date := CURRENT_DATE - 4;
  v_calc RECORD;
  v_min int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Registrar um dia com quatro marcações COM SEGUNDOS e conferir a conta';
  r.esperado    := '550 minutos — o minuto de cada marcação, como no espelho e no AFD';

  IF to_regprocedure('public._ponto_calc_dia(uuid, text, date, uuid)') IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A apuracao do dia (_ponto_calc_dia) nao existe nesta base.';
    RETURN r;
  END IF;

  PERFORM public.qa_modo_ligar();
  v_t   := public.qa_sandbox_tenant_id();
  v_cpf := public.qa_cpf(47001);

  -- A marcacao e imutavel (Sumula 338): a massa e criada uma vez e reusada.
  SELECT m.colaborador_id INTO v_cid
  FROM public.ponto_marcacoes m
  WHERE m.tenant_id = v_t AND m.colaborador_cpf = v_cpf AND m.data_marcacao = v_dia
  LIMIT 1;

  IF v_cid IS NULL THEN
    v_cid := gen_random_uuid();
    INSERT INTO public.ponto_marcacoes
      (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
       data_marcacao, hora_marcacao, tipo_marcacao, hash_marcacao)
    VALUES
      (v_t, v_cid, 'Colaborador QA 470', v_cpf, v_dia, time '07:25:43', 'entrada', md5(v_cpf || v_dia::text || '470a')),
      (v_t, v_cid, 'Colaborador QA 470', v_cpf, v_dia, time '12:03:12', 'saida',   md5(v_cpf || v_dia::text || '470b')),
      (v_t, v_cid, 'Colaborador QA 470', v_cpf, v_dia, time '13:03:51', 'entrada', md5(v_cpf || v_dia::text || '470c')),
      (v_t, v_cid, 'Colaborador QA 470', v_cpf, v_dia, time '17:35:29', 'saida',   md5(v_cpf || v_dia::text || '470d'));
  END IF;

  SELECT * INTO v_calc FROM public._ponto_calc_dia(v_t, v_cpf, v_dia, v_cid);
  v_min := COALESCE(EXTRACT(EPOCH FROM v_calc.o_horas) / 60, 0)::int;

  IF v_min = 550 THEN
    r.situacao := 'passou';
    r.obtido := 'O dia contou 550 minutos exatos: o minuto de cada marcacao e a unidade da '
             || 'conta, como no espelho e no AFD.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o dia contou %s minutos, e nao 550. Faltam %s minuto(s) — a '
             || 'conta esta truncando a DIFERENCA entre marcacoes em vez do minuto de cada '
             || 'uma, e assim descarta ate 59 segundos por par, duas vezes ao dia, sempre '
             || 'para baixo. Numa competencia real isso deu 20 minutos no mes e perto de 4 '
             || 'horas no ano, todas contra o trabalhador. Pior: encolhe o excedente o '
             || 'bastante para ele caber na tolerancia (deixa de virar hora extra) e infla o '
             || 'deficit o bastante para ele estourar a tolerancia (passa a ser descontado). '
             || 'Correcao: truncar CADA MARCACAO antes de subtrair.', v_min, 550 - v_min);
    r.detalhe := jsonb_build_object('minutos_apurados', v_min, 'minutos_corretos', 550);
  END IF;

  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
VALUES ('PONTO-470', 'qa_caso_ponto_470', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

DO $fim$
BEGIN
  RAISE NOTICE 'PONTO-470: o minuto de cada marcacao passa a ser a unidade da conta do dia.';
END $fim$;
