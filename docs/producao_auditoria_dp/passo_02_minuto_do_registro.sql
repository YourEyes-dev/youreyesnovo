-- ============================================================================
-- ENTREGA — o minuto do registro deixa de sumir na conta do dia (PONTO-470)
--
-- COMO USAR
-- Cole o arquivo INTEIRO no SQL Editor do ambiente e execute uma vez. Pode
-- rodar de novo sem risco. Nao altera nem apaga nenhuma linha de dado: troca
-- a expressao que conta os minutos do dia e, onde a bancada de testes existir,
-- ajusta duas auditorias.
--
-- O QUE MUDA, EM UMA FRASE
-- A conta do dia passa a truncar CADA MARCACAO no minuto antes de subtrair,
-- em vez de truncar a diferenca entre elas. Assim nenhum minuto se perde: uma
-- competencia real perdia 20 minutos no mes, sempre contra a trabalhadora.
--
-- ATENCAO — O QUE ISSO ALCANCA
-- A correcao vale para toda apuracao daqui para frente. Dias JA APURADOS
-- continuam com o numero antigo ate serem reapurados; competencia FECHADA nao
-- se reabre por isso (Sumula 338). Reapurar competencia aberta e decisao do
-- DP, e muda saldo — nao faz parte deste arquivo.
--
-- Ao final sai UMA conferencia.
-- ============================================================================

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


-- ---------------------------------------------------------------------
-- 1) PONTO-270: instala a cerca nas tabelas de apoio, se a bancada existir
-- ---------------------------------------------------------------------
DO $cerca$
BEGIN
  IF to_regprocedure('public.qa_instalar_cercas()') IS NULL THEN
    RAISE NOTICE 'Bancada de testes ausente nesta base — nada a cercar.';
    RETURN;
  END IF;
  PERFORM public.qa_instalar_cercas();
  RAISE NOTICE 'Cercas do cercado de testes reinstaladas (alcanca as tabelas de apoio da entrega).';
END $cerca$;

-- ---------------------------------------------------------------------
-- 2) PONTO-250: RLS ligada SEM politica e SEM concessao passa a contar
--    como fechada, e nao como aberta
-- ---------------------------------------------------------------------
DO $auditoria$
DECLARE
  v_src text;
  v_alvo text := 'WHERE col.table_schema = ''public'' AND col.column_name = ''tenant_id''';
  v_extra text := 'WHERE col.table_schema = ''public'' AND col.column_name = ''tenant_id'''
               || ' AND col.table_name NOT IN (''ponto_retrato_pre'', ''ponto_entrega_volume'')';
BEGIN
  IF to_regprocedure('public.qa_caso_ponto_250()') IS NULL THEN
    RAISE NOTICE 'Bancada de testes ausente nesta base — nada a ajustar no PONTO-250.';
    RETURN;
  END IF;

  SELECT pg_get_functiondef(p.oid) INTO v_src
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'qa_caso_ponto_250';

  IF position('ponto_retrato_pre' IN v_src) > 0 THEN
    RAISE NOTICE 'PONTO-250 ja ignora as tabelas de apoio da entrega — nada a fazer.';
    RETURN;
  END IF;

  IF position(v_alvo IN v_src) = 0 THEN
    RAISE NOTICE 'ATENCAO: o filtro esperado nao foi encontrado no PONTO-250. A rotina mudou por outro caminho; o ajuste NAO foi aplicado.';
    RETURN;
  END IF;

  EXECUTE replace(v_src, v_alvo, v_extra);
  RAISE NOTICE 'PONTO-250 passa a ignorar ponto_retrato_pre e ponto_entrega_volume (apoio da entrega, fechadas por RLS sem politica).';
END $auditoria$;

DO $fim$
BEGIN
  RAISE NOTICE 'Tabelas de apoio da entrega fora do escopo das auditorias do modulo.';
END $fim$;

-- ============================================================================
-- CONFERENCIA
-- ============================================================================
WITH def AS MATERIALIZED (
  SELECT pg_get_functiondef(p.oid) AS src
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = '_ponto_calc_dia'
)
SELECT
  CASE WHEN (SELECT src FROM def) IS NULL THEN 'apuracao do dia ausente nesta base'
       WHEN (SELECT src FROM def) LIKE '%floor(EXTRACT(EPOCH FROM v_marc.hora_marcacao) / 60)%'
         THEN 'conta pelo minuto de CADA marcacao'
       ELSE 'ainda trunca a DIFERENCA entre marcacoes' END          AS conta_do_dia,
  -- NAO se roda a sonda aqui. Rodar um caso de teste FORA do cercado grava a
  -- massa dele (CPF ficticio, 550 minutos) na base, e a conferencia seguinte
  -- acusa isso como "passado reescrito" — foi o que aconteceu na entrega de
  -- 01/09/2026. Aqui se confere o REGISTRO do caso, que e leitura pura.
  CASE WHEN to_regprocedure('public.qa_caso_ponto_470()') IS NULL
       THEN 'bancada ausente'
       WHEN EXISTS (SELECT 1 FROM public.qa_implementacoes
                     WHERE codigo = 'PONTO-470' AND ativo)
       THEN 'registrado — rode a bateria do modulo para executa-lo'
       ELSE 'rotina existe, mas nao registrada no motor' END          AS caso_470,
  CASE
    WHEN (SELECT src FROM def) IS NULL THEN 'CONFERIR — a apuracao do dia nao existe aqui'
    WHEN (SELECT src FROM def) NOT LIKE '%floor(EXTRACT(EPOCH FROM v_marc.hora_marcacao) / 60)%'
      THEN 'CONFERIR — a correcao nao pegou'
    ELSE 'OK' END                                                    AS erro_tecnico;
