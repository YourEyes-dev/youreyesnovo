-- ============================================================================
-- QA — EC 141/2026, ENTREGA F1 (marcos legais + escala "vigente a partir de")
--
--   PONTO-EC141-001  com os marcos EC 141 inativos, jornada e saldo de uma semana
--                    5x2 8h48 saem idênticos (nada muda sozinho)
--   PONTO-EC141-002  agendamento 8h48 -> 8h24 em D: D-1 com 8h48 = 0; D com
--                    8h48 = +24; D+1 com 8h24 = 0
--   PONTO-EC141-003  cancelar o agendamento restaura a escala e a jornada de D
--   PONTO-EC141-004  retroativo: sem justificativa recusado; sobre competência
--                    fechada recusado; em competência aberta também recusado nesta
--                    entrega (falta a reconsolidação do ponto_diario — F2)
--   PONTO-EC141-005  ponto_teto_legal ignora marco inativo e respeita ativação,
--                    mudança de data, desativação e exceção por conta; só o
--                    SuperAdmin altera marco
--   PONTO-EC141-006  painel de impacto conta a 6x1 sem instrumento coletivo e
--                    some para o cliente sem marco ativo
--   PONTO-EC141-007  batida em escala acima do teto continua aceita (nunca
--                    bloquear a batida — Portaria MTP 671/2021)
--   PONTO-EC141-008  com um agendamento para D, TUDO dos dias < D fica idêntico
--                    (saldo, jornada, horários e blocos, intervalo, débito,
--                    equalização, espelho) e cancelar devolve o estado exato
--
-- As rotinas chamam as MESMAS funções da tela (UPDATE da escala pelo gatilho,
-- ponto_escala_cancelar_agendamento, ponto_marco_*, ponto_teto_legal,
-- ponto_ec141_impacto, ponto_saldo_dias_competencia). Rodam no cercado e são
-- desfeitas pelo motor (qa_executar_descartavel). Os marcos são alterados só
-- como EXCEÇÃO DA CONTA do cercado: a regra global nunca é tocada pelo teste.
-- Variáveis só por subconsulta escalar (padrão do SQL Editor de produção). Idempotente.
-- ============================================================================

SET lock_timeout = '10s';

-- Ajudante: escala por dia no cercado (entrada 08:00, almoço 12:00-13:00),
-- tolerâncias zeradas, atribuída ao CPF fictício desde p_inicio.
CREATE OR REPLACE FUNCTION public.qa_ec141_escala(
  p_cpf text, p_jornada_min integer, p_dias text[], p_inicio date)
RETURNS uuid LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  v_id    uuid := gen_random_uuid();
  v_cfg   jsonb := '{}'::jsonb;
  v_saida text;
  k       text;
BEGIN
  v_saida := to_char(TIME '08:00' + make_interval(mins => p_jornada_min + 60), 'HH24:MI');
  FOREACH k IN ARRAY ARRAY['segunda','terca','quarta','quinta','sexta','sabado','domingo'] LOOP
    v_cfg := v_cfg || jsonb_build_object(k, jsonb_build_object(
      'trabalha', k = ANY (p_dias), 'tem_almoco', true, 'entrada', '08:00',
      'inicio_almoco', '12:00', 'fim_almoco', '13:00', 'saida', v_saida));
  END LOOP;
  INSERT INTO public.ponto_escalas
    (id, tenant_id, nome, tipo, modalidade, jornada_diaria_minutos, jornada_semanal_minutos,
     intervalo_intrajornada_minutos, tolerancia_minutos, tolerancia_diaria_minutos,
     hora_entrada_padrao, hora_saida_padrao, equalizacao_mensal_ativa, carga_semanal_contratada_min,
     ativa, dias_config)
  VALUES (v_id, public.qa_sandbox_tenant_id(), '[QA-EC141] Escala ' || p_cpf,
          CASE cardinality(p_dias) WHEN 6 THEN '6x1' ELSE '5x2' END, 'fixa',
          p_jornada_min, p_jornada_min * cardinality(p_dias), 60, 0, 0,
          TIME '08:00', v_saida::time, false, 2640, true, v_cfg);
  INSERT INTO public.ponto_escala_atribuicoes
    (tenant_id, escala_id, colaborador_id, colaborador_nome, colaborador_cpf, data_inicio, ativa)
  VALUES (public.qa_sandbox_tenant_id(), v_id, p_cpf, '[QA-EC141] Colaborador', p_cpf, p_inicio, true);
  -- Blocos diários, como a tela grava ao criar.
  PERFORM public._ponto_ec141_sincronizar_periodos(v_id);
  RETURN v_id;
END $fn$;

-- Ajudante: o MESMO gesto da tela de escalas — salvar novos horários (saída
-- do dia) com "vale a partir de" e, se for o caso, justificativa e marco.
CREATE OR REPLACE FUNCTION public.qa_ec141_salvar_escala(
  p_escala uuid, p_jornada_min integer, p_desde date, p_motivo text DEFAULT NULL, p_marco text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  v_saida text := to_char(TIME '08:00' + make_interval(mins => p_jornada_min + 60), 'HH24:MI');
BEGIN
  UPDATE public.ponto_escalas e
     SET dias_config = (SELECT jsonb_object_agg(x.k, x.v || CASE WHEN COALESCE((x.v->>'trabalha')::boolean, false)
                                                                  THEN jsonb_build_object('saida', v_saida)
                                                                  ELSE '{}'::jsonb END)
                          FROM jsonb_each(e.dias_config) x(k, v)),
         jornada_diaria_minutos = p_jornada_min,
         jornada_semanal_minutos = p_jornada_min * 5,
         hora_saida_padrao = v_saida::time,
         parametros_vigentes_desde = p_desde,
         parametros_vigencia_motivo = p_motivo,
         parametros_marco_codigo = p_marco
   WHERE e.id = p_escala;
  -- A tela regrava os blocos diários logo depois de salvar.
  PERFORM public._ponto_ec141_sincronizar_periodos(p_escala);
END $fn$;

-- Ajudante: saldo e jornada de um dia pela mesma função da tela.
CREATE OR REPLACE FUNCTION public.qa_ec141_dia(p_cpf text, p_dia date)
RETURNS jsonb LANGUAGE sql SET search_path TO 'public' AS $fn$
  SELECT jsonb_build_object('jornada', s.jornada_min, 'trabalhado', s.trabalhado_min, 'saldo', s.saldo_min)
    FROM public.ponto_saldo_dias_competencia(public.qa_sandbox_tenant_id(), p_cpf, to_char(p_dia, 'YYYY-MM')) s
   WHERE s.dia = p_dia
   LIMIT 1
$fn$;

-- ── PONTO-EC141-001 ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_ec141_001()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r       public.qa_retorno;
  v_t     uuid := public.qa_sandbox_tenant_id();
  v_cpf   text := public.qa_cpf(6141);
  v_seg   date := DATE '2026-08-10';   -- semana sem feriado nacional
  v_trab  int[] := ARRAY[528, 540, 500, 528, 600];
  v_esc   uuid;
  v_dia   jsonb;
  v_falha text := NULL;
  v_ver   int;
  v_teto  jsonb;
  i       int;
BEGIN
  PERFORM public.qa_modo_ligar();
  -- Marcos EC 141 inativos para a conta do cercado (exceção da conta),
  -- seja qual for o estado global.
  PERFORM public.ponto_marco_desativar('EC141_42H', '[QA] marcos inativos', v_t);
  PERFORM public.ponto_marco_desativar('EC141_40H', '[QA] marcos inativos', v_t);

  r.passo_ordem := 1;
  r.passo_acao := 'Escala 5x2 de 8h48 sem nenhuma alteração; batidas de 8h48, 9h00, 8h20, 8h48 e 10h00 na semana de 10/08/2026';
  r.esperado := 'Jornada 528 nos 5 dias, 0 no fim de semana; saldo = trabalhado - 528 (0, +12, -28, 0, +72); nenhuma versão; teto CF/88 44h';
  v_esc := public.qa_ec141_escala(v_cpf, 528, ARRAY['segunda','terca','quarta','quinta','sexta'], DATE '2026-01-01');
  FOR i IN 1..5 LOOP
    PERFORM public.qa_ponto_dia_min(v_cpf, '[QA-EC141] Colaborador', v_seg + (i - 1), v_trab[i] + 60);
  END LOOP;

  FOR i IN 1..5 LOOP
    v_dia := public.qa_ec141_dia(v_cpf, v_seg + (i - 1));
    IF (v_dia->>'jornada')::int IS DISTINCT FROM 528
       OR (v_dia->>'trabalhado')::int IS DISTINCT FROM v_trab[i]
       OR (v_dia->>'saldo')::int IS DISTINCT FROM v_trab[i] - 528 THEN
      v_falha := COALESCE(v_falha || '; ', '') || format('%s: %s', to_char(v_seg + (i - 1), 'DD/MM'), COALESCE(v_dia::text, 'sem linha'));
    END IF;
  END LOOP;
  v_dia := public.qa_ec141_dia(v_cpf, v_seg + 5);
  IF COALESCE((v_dia->>'jornada')::int, 0) <> 0 OR COALESCE((v_dia->>'saldo')::int, 0) <> 0 THEN
    v_falha := COALESCE(v_falha || '; ', '') || 'sábado: ' || v_dia::text;
  END IF;

  v_ver := (SELECT count(*) FROM public.ponto_escala_param_versoes WHERE escala_id = v_esc);
  v_teto := public.ponto_teto_legal(v_t, NULL, DATE '2028-06-01');

  IF v_falha IS NOT NULL THEN
    r.situacao := 'falhou'; r.obtido := 'A apuração mudou sem nenhum marco ativo: ' || v_falha;
  ELSIF v_ver <> 0 THEN
    r.situacao := 'falhou'; r.obtido := format('Surgiram %s versão(ões) sem edição da escala', v_ver);
  ELSIF COALESCE(v_teto->>'codigo', '') <> 'CF88_44H' OR (v_teto->>'teto_semanal_min')::int <> 2640 THEN
    r.situacao := 'falhou'; r.obtido := 'Com os marcos EC 141 inativos o teto deveria seguir 44h: ' || COALESCE(v_teto::text, 'nulo');
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Semana 5x2 8h48 apurada igual (528 por dia; saldos 0, +12, -28, 0, +72); teto 44h com os marcos inativos.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-EC141-002 ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_ec141_002()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r      public.qa_retorno;
  v_cpf  text := public.qa_cpf(6142);
  v_d    date;
  v_esc  uuid;
  v_ant  jsonb; v_dia jsonb; v_dep jsonb;
  v_ver  jsonb;
BEGIN
  PERFORM public.qa_modo_ligar();
  -- D = terça-feira daqui a pelo menos duas semanas (D-1 segunda, D+1 quarta).
  v_d := CURRENT_DATE + 14 + ((2 - EXTRACT(ISODOW FROM CURRENT_DATE + 14)::int + 7) % 7);
  v_esc := public.qa_ec141_escala(v_cpf, 528, ARRAY['segunda','terca','quarta','quinta','sexta'], DATE '2026-01-01');

  r.passo_ordem := 1;
  r.passo_acao := format('Na tela de escalas, salvar 8h24 (17:24) com "vale a partir de" %s, marcado para EC141_42H', to_char(v_d, 'DD/MM/YYYY'));
  r.esperado := 'Versão com os valores antigos até a véspera; escala viva com 8h24 e vigente desde D';
  PERFORM public.qa_ec141_salvar_escala(v_esc, 504, v_d, NULL, 'EC141_42H');
  v_ver := (SELECT jsonb_build_object('fim', pv.vigencia_fim, 'origem', pv.origem, 'marco', pv.marco_codigo,
                                      'semanal', pv.jornada_semanal_minutos)
              FROM public.ponto_escala_param_versoes pv WHERE pv.escala_id = v_esc LIMIT 1);

  r.passo_ordem := 2;
  r.passo_acao := 'Batidas: D-1 com 8h48; D com 8h48; D+1 com 8h24';
  r.esperado := 'D-1: jornada 528, saldo 0; D: jornada 504, saldo +24; D+1: jornada 504, saldo 0';
  PERFORM public.qa_ponto_dia_min(v_cpf, '[QA-EC141] Colaborador', v_d - 1, 528 + 60);
  PERFORM public.qa_ponto_dia_min(v_cpf, '[QA-EC141] Colaborador', v_d,     528 + 60);
  PERFORM public.qa_ponto_dia_min(v_cpf, '[QA-EC141] Colaborador', v_d + 1, 504 + 60);
  v_ant := public.qa_ec141_dia(v_cpf, v_d - 1);
  v_dia := public.qa_ec141_dia(v_cpf, v_d);
  v_dep := public.qa_ec141_dia(v_cpf, v_d + 1);

  IF v_ver IS NULL OR (v_ver->>'fim')::date <> v_d - 1 OR v_ver->>'origem' <> 'agendamento'
     OR COALESCE(v_ver->>'marco', '') <> 'EC141_42H' OR (v_ver->>'semanal')::int <> 2640 THEN
    r.situacao := 'falhou'; r.obtido := 'A versão congelada não ficou até a véspera de D: ' || COALESCE(v_ver::text, 'nenhuma');
  ELSIF (v_ant->>'jornada')::int IS DISTINCT FROM 528 OR (v_ant->>'saldo')::int IS DISTINCT FROM 0 THEN
    r.situacao := 'falhou'; r.obtido := 'D-1 devia ser 528/0 e veio ' || COALESCE(v_ant::text, 'sem linha');
  ELSIF (v_dia->>'jornada')::int IS DISTINCT FROM 504 OR (v_dia->>'saldo')::int IS DISTINCT FROM 24 THEN
    r.situacao := 'falhou'; r.obtido := 'D devia ser 504/+24 e veio ' || COALESCE(v_dia::text, 'sem linha');
  ELSIF (v_dep->>'jornada')::int IS DISTINCT FROM 504 OR (v_dep->>'saldo')::int IS DISTINCT FROM 0 THEN
    r.situacao := 'falhou'; r.obtido := 'D+1 devia ser 504/0 e veio ' || COALESCE(v_dep::text, 'sem linha');
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Agendado para %s: véspera 528/0, dia D 504/+24, dia seguinte 504/0.', to_char(v_d, 'DD/MM/YYYY'));
  END IF;
  r.detalhe := jsonb_build_object('versao', v_ver, 'd_menos_1', v_ant, 'd', v_dia, 'd_mais_1', v_dep);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-EC141-003 ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_ec141_003()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r       public.qa_retorno;
  v_t     uuid := public.qa_sandbox_tenant_id();
  v_cpf   text := public.qa_cpf(6143);
  v_d     date := CURRENT_DATE + 10;
  v_esc   uuid;
  v_seg   boolean := false;
  v_res   jsonb;
  v_row   jsonb;
  v_jd    int;
  v_vers  int;
  v_lista int;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_esc := public.qa_ec141_escala(v_cpf, 528, ARRAY['segunda','terca','quarta','quinta','sexta'], DATE '2026-01-01');
  PERFORM public.qa_ec141_salvar_escala(v_esc, 504, v_d, NULL, 'EC141_42H');
  v_lista := (SELECT count(*) FROM public.ponto_escalas_agendamentos(v_t) a WHERE a.escala_id = v_esc);

  r.passo_ordem := 1;
  r.passo_acao := 'Com agendamento pendente, tentar programar outra data';
  r.esperado := 'Recusado: um agendamento pendente por escala';
  BEGIN
    PERFORM public.qa_ec141_salvar_escala(v_esc, 480, v_d + 7, NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    v_seg := true;
  END;

  r.passo_ordem := 2;
  r.passo_acao := 'Cancelar o agendamento (ponto_escala_cancelar_agendamento)';
  r.esperado := 'Escala volta a 8h48 (17:48), sem versão pendente; jornada de D volta a 528';
  v_res := public.ponto_escala_cancelar_agendamento(v_esc);
  v_row := (SELECT jsonb_build_object('jd', e.jornada_diaria_minutos, 'js', e.jornada_semanal_minutos,
                                      'saida', e.dias_config->'segunda'->>'saida', 'desde', e.parametros_vigentes_desde)
              FROM public.ponto_escalas e WHERE e.id = v_esc);
  v_vers := (SELECT count(*) FROM public.ponto_escala_param_versoes WHERE escala_id = v_esc);
  v_jd := (SELECT j.jornada_min FROM public.ponto_jornada_do_dia(v_t, v_cpf, v_cpf, v_d) j LIMIT 1);

  IF v_lista <> 1 THEN
    r.situacao := 'falhou'; r.obtido := 'O agendamento não apareceu na lista de agendamentos da conta';
  ELSIF NOT v_seg THEN
    r.situacao := 'falhou'; r.obtido := 'Um segundo agendamento foi aceito com outro pendente';
  ELSIF NOT COALESCE((v_res->>'ok')::boolean, false) THEN
    r.situacao := 'falhou'; r.obtido := 'O cancelamento foi recusado: ' || COALESCE(v_res::text, 'nulo');
  ELSIF (v_row->>'jd')::int <> 528 OR (v_row->>'js')::int <> 2640 OR v_row->>'saida' <> '17:48' THEN
    r.situacao := 'falhou'; r.obtido := 'A escala não voltou aos valores antigos: ' || v_row::text;
  ELSIF v_vers <> 0 THEN
    r.situacao := 'falhou'; r.obtido := format('Sobrou %s versão(ões) depois do cancelamento', v_vers);
  ELSIF v_jd IS DISTINCT FROM 528 THEN
    r.situacao := 'falhou'; r.obtido := format('A jornada de D devia voltar a 528 e veio %s', COALESCE(v_jd::text, 'nula'));
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Segundo agendamento recusado; cancelamento restaurou 8h48 (17:48), sem versão pendente; D voltou a 528.';
  END IF;
  r.detalhe := jsonb_build_object('cancelamento', v_res, 'escala', v_row);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-EC141-004 ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_ec141_004()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r          public.qa_retorno;
  v_t        uuid := public.qa_sandbox_tenant_id();
  v_cpf1     text := public.qa_cpf(6144);
  v_cpf2     text := public.qa_cpf(6145);
  v_esc1     uuid;
  v_esc2     uuid;
  v_mes_ant  date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
  v_sem_mot  boolean := false;
  v_fechada  boolean := false;
  v_msg      text;
  v_msg2     text;
  v_aberta   boolean := false;
  v_jd_ant   int;
BEGIN
  PERFORM public.qa_modo_ligar();
  DELETE FROM public.ponto_fechamentos WHERE tenant_id = v_t;
  v_esc1 := public.qa_ec141_escala(v_cpf1, 528, ARRAY['segunda','terca','quarta','quinta','sexta'], DATE '2026-01-01');
  v_esc2 := public.qa_ec141_escala(v_cpf2, 528, ARRAY['segunda','terca','quarta','quinta','sexta'], DATE '2026-01-01');

  r.passo_ordem := 1;
  r.passo_acao := 'Salvar a escala valendo desde ontem, SEM justificativa';
  r.esperado := 'Recusado (data anterior a hoje exige justificativa)';
  BEGIN
    PERFORM public.qa_ec141_salvar_escala(v_esc1, 504, CURRENT_DATE - 1, NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    v_sem_mot := true;
  END;

  r.passo_ordem := 2;
  r.passo_acao := 'Salvar valendo desde ontem COM justificativa (competência aberta)';
  r.esperado := 'Recusado nesta entrega (dias já apurados exigiriam reconsolidação); a escala não muda';
  BEGIN
    PERFORM public.qa_ec141_salvar_escala(v_esc1, 504, CURRENT_DATE - 1, '[QA] correção de cadastro', NULL);
    v_aberta := true;
  EXCEPTION WHEN OTHERS THEN
    v_msg2 := SQLERRM;
  END;
  v_jd_ant := (SELECT j.jornada_min FROM public.ponto_jornada_do_dia(v_t, v_cpf1, v_cpf1, CURRENT_DATE - 1) j LIMIT 1);

  r.passo_ordem := 3;
  r.passo_acao := 'Fechar a competência do mês passado e salvar outra escala valendo desde o dia 1º dele, com justificativa';
  r.esperado := 'Recusado: a alteração não retroage sobre competência fechada';
  INSERT INTO public.ponto_fechamentos (tenant_id, empresa_id, competencia, status, data_fechamento)
  VALUES (v_t, NULL, to_char(v_mes_ant, 'YYYY-MM'), 'fechado', now());
  BEGIN
    PERFORM public.qa_ec141_salvar_escala(v_esc2, 504, v_mes_ant, '[QA] tentativa sobre mês fechado', NULL);
  EXCEPTION WHEN OTHERS THEN
    v_fechada := position('fechada' IN SQLERRM) > 0;
    v_msg := SQLERRM;
  END;

  IF NOT v_sem_mot THEN
    r.situacao := 'falhou'; r.obtido := 'Retroativo sem justificativa foi aceito';
  ELSIF v_aberta OR position('ainda não está disponível' IN COALESCE(v_msg2, '')) = 0 THEN
    r.situacao := 'falhou'; r.obtido := 'Retroativo em competência aberta devia ser bloqueado nesta entrega: ' || COALESCE(v_msg2, 'aceito');
  ELSIF v_jd_ant IS DISTINCT FROM 528 THEN
    r.situacao := 'falhou'; r.obtido := format('Ontem devia manter 528 e veio %s', COALESCE(v_jd_ant::text, 'nulo'));
  ELSIF NOT v_fechada THEN
    r.situacao := 'falhou'; r.obtido := 'Retroativo sobre competência fechada não foi recusado como tal: ' || COALESCE(v_msg, 'aceito');
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Sem justificativa: recusado. Com justificativa em mês aberto: bloqueado (falta reconsolidação; F2), ontem segue 528. Sobre mês fechado: recusado.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-EC141-005 ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_ec141_005()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r        public.qa_retorno;
  v_claims text := current_setting('request.jwt.claims', true);
  v_t      uuid := public.qa_sandbox_tenant_id();
  v_outra  uuid := gen_random_uuid();
  v_d      date := CURRENT_DATE + 30;
  t0 jsonb; t1 jsonb; t2 jsonb; t3 jsonb; t4 jsonb; t5 jsonb; t_outra jsonb; t_glob jsonb;
  v_user   uuid;
  v_negado jsonb;
  v_hist   int;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM public.ponto_marco_desativar('EC141_42H', '[QA] estado inicial', v_t);
  PERFORM public.ponto_marco_desativar('EC141_40H', '[QA] estado inicial', v_t);

  r.passo_ordem := 1;
  r.passo_acao := 'Teto na data com os marcos EC 141 INATIVOS na conta';
  r.esperado := 'CF/88: 2640 min (44h), 1 repouso';
  t0 := public.ponto_teto_legal(v_t, NULL, v_d + 400);

  r.passo_ordem := 2;
  r.passo_acao := format('SuperAdmin ativa EC141_42H para a conta a partir de %s', to_char(v_d, 'DD/MM/YYYY'));
  r.esperado := 'Na véspera segue 44h; na data passa a 42h (2520), 2 repousos, divisor 210';
  PERFORM public.ponto_marco_ativar('EC141_42H', v_d, '[QA] ativação', v_t);
  t1 := public.ponto_teto_legal(v_t, NULL, v_d - 1);
  t2 := public.ponto_teto_legal(v_t, NULL, v_d);

  r.passo_ordem := 3;
  r.passo_acao := 'Adiar a data em 10 dias (ponto_marco_definir_data)';
  r.esperado := 'Na data antiga volta a 44h';
  PERFORM public.ponto_marco_definir_data('EC141_42H', v_d + 10, '[QA] adiamento', v_t);
  t3 := public.ponto_teto_legal(v_t, NULL, v_d);

  r.passo_ordem := 4;
  r.passo_acao := 'Desativar (revogação)';
  r.esperado := 'Mesmo depois da data, volta a 44h';
  PERFORM public.ponto_marco_desativar('EC141_42H', '[QA] revogação', v_t);
  t4 := public.ponto_teto_legal(v_t, NULL, v_d + 20);

  r.passo_ordem := 5;
  r.passo_acao := 'Reativar só para a conta do cercado e comparar com outra conta';
  r.esperado := 'A exceção da conta vale só para ela; a outra conta segue a regra global';
  PERFORM public.ponto_marco_ativar('EC141_42H', v_d, '[QA] reativação', v_t);
  t5 := public.ponto_teto_legal(v_t, NULL, v_d);
  t_outra := public.ponto_teto_legal(v_outra, NULL, v_d);
  t_glob := public.ponto_teto_legal(NULL, NULL, v_d);   -- só a regra global
  v_hist := (SELECT count(*) FROM public.ponto_marcos_legais_historico h WHERE h.tenant_id = v_t AND h.codigo = 'EC141_42H');

  r.passo_ordem := 6;
  r.passo_acao := 'Usuário comum (não SuperAdmin) tenta ativar um marco';
  r.esperado := 'Recusado (sem_permissao)';
  v_user := public.qa_mky_usuario_empresa(v_t, 'ec141');
  PERFORM public.qa_mky_claims(v_user);
  v_negado := public.ponto_marco_ativar('EC141_40H', v_d, '[QA] tentativa indevida', v_t);
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);

  IF (t0->>'teto_semanal_min')::int <> 2640 OR t0->>'codigo' <> 'CF88_44H' THEN
    r.situacao := 'falhou'; r.obtido := 'Marco inativo foi considerado: ' || t0::text;
  ELSIF (t1->>'teto_semanal_min')::int <> 2640 OR (t2->>'teto_semanal_min')::int <> 2520
        OR (t2->>'repousos_semana')::int <> 2 OR (t2->>'divisor_padrao')::int <> 210 OR t2->>'origem' <> 'conta' THEN
    r.situacao := 'falhou'; r.obtido := format('Ativação não respeitou a data: véspera %s, data %s', t1::text, t2::text);
  ELSIF (t3->>'teto_semanal_min')::int <> 2640 THEN
    r.situacao := 'falhou'; r.obtido := 'Adiamento não foi respeitado: ' || t3::text;
  ELSIF (t4->>'teto_semanal_min')::int <> 2640 THEN
    r.situacao := 'falhou'; r.obtido := 'Desativação não foi respeitada: ' || t4::text;
  ELSIF (t5->>'teto_semanal_min')::int <> 2520
        OR t_outra->>'origem' = 'conta'
        OR (t_outra->>'teto_semanal_min')::int <> (t_glob->>'teto_semanal_min')::int THEN
    r.situacao := 'falhou'; r.obtido := format('Exceção por conta vazou ou não valeu: conta %s, outra %s', t5::text, t_outra::text);
  ELSIF v_hist < 5 THEN
    r.situacao := 'falhou'; r.obtido := format('Histórico com %s registro(s); esperado ao menos 5', v_hist);
  ELSIF COALESCE(v_negado->>'erro', '') <> 'sem_permissao' THEN
    r.situacao := 'falhou'; r.obtido := 'Usuário comum conseguiu alterar marco: ' || COALESCE(v_negado::text, 'nulo');
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Inativo ignorado; ativação, adiamento, desativação e reativação respeitados; exceção vale só para a conta; histórico gravado; usuário comum barrado.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  BEGIN PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); EXCEPTION WHEN OTHERS THEN NULL; END;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-EC141-006 ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_ec141_006()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r         public.qa_retorno;
  v_claims  text := current_setting('request.jwt.claims', true);
  v_t       uuid := public.qa_sandbox_tenant_id();
  v_cpf     text := public.qa_cpf(6146);
  v_d       date := CURRENT_DATE + 45;
  v_esc     uuid;
  v_user    uuid;
  v_cli_off jsonb;
  v_imp     jsonb;
  v_lin     jsonb;
  v_lin_col jsonb;
  v_cli_on  jsonb;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM set_config('request.jwt.claims', '', true);
  UPDATE public.ponto_acordos SET ativo = false WHERE tenant_id = v_t;
  PERFORM public.ponto_marco_desativar('EC141_42H', '[QA] estado inicial', v_t);
  PERFORM public.ponto_marco_desativar('EC141_40H', '[QA] estado inicial', v_t);
  -- 6x1 de 7h20 (44h), sem instrumento coletivo.
  v_esc := public.qa_ec141_escala(v_cpf, 440, ARRAY['segunda','terca','quarta','quinta','sexta','sabado'], DATE '2026-01-01');

  r.passo_ordem := 1;
  r.passo_acao := 'Usuário da conta abre o painel de impacto sem marco EC 141 ativo';
  r.esperado := 'Nada aparece (visivel = false)';
  v_user := public.qa_mky_usuario_empresa(v_t, 'ec141-imp');
  PERFORM public.qa_mky_claims(v_user);
  v_cli_off := public.ponto_ec141_impacto(v_t, NULL, NULL);
  PERFORM set_config('request.jwt.claims', '', true);

  r.passo_ordem := 2;
  r.passo_acao := 'SuperAdmin ativa EC141_42H para a conta e consulta o impacto';
  r.esperado := 'A 6x1 aparece com 1 colaborador, 44h acima do teto de 42h e "6 dias sem coletivo"';
  PERFORM public.ponto_marco_ativar('EC141_42H', v_d, '[QA] impacto', v_t);
  v_imp := public.ponto_ec141_impacto(v_t, NULL, NULL);
  v_lin := (SELECT x FROM jsonb_array_elements(v_imp->'linhas') x WHERE x->>'escala_id' = v_esc::text LIMIT 1);
  PERFORM public.qa_mky_claims(v_user);
  v_cli_on := public.ponto_ec141_impacto(v_t, NULL, NULL);
  PERFORM set_config('request.jwt.claims', '', true);

  r.passo_ordem := 3;
  r.passo_acao := 'Cadastrar uma CCT vigente na data e consultar de novo';
  r.esperado := 'A mesma 6x1 deixa de contar como "sem coletivo"';
  INSERT INTO public.ponto_acordos (tenant_id, tipo, titulo, ativo, vigencia_inicio, vigencia_fim)
  VALUES (v_t, 'cct', '[QA-EC141] CCT vigente', true, CURRENT_DATE - 30, v_d + 365);
  v_lin_col := (SELECT x FROM jsonb_array_elements(public.ponto_ec141_impacto(v_t, NULL, NULL)->'linhas') x
                 WHERE x->>'escala_id' = v_esc::text LIMIT 1);
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);

  IF COALESCE((v_cli_off->>'visivel')::boolean, true) THEN
    r.situacao := 'falhou'; r.obtido := 'Sem marco ativo o cliente viu o painel: ' || COALESCE(v_cli_off::text, 'nulo');
  ELSIF v_lin IS NULL THEN
    r.situacao := 'falhou'; r.obtido := 'A escala 6x1 não apareceu no impacto: ' || COALESCE(v_imp::text, 'nulo');
  ELSIF (v_lin->>'colaboradores')::int <> 1 OR (v_lin->>'carga_semanal_atual_min')::int <> 2640
        OR NOT (v_lin->>'acima_do_teto')::boolean OR NOT (v_lin->>'seis_dias_sem_coletivo')::boolean THEN
    r.situacao := 'falhou'; r.obtido := 'Linha da 6x1 incorreta: ' || v_lin::text;
  ELSIF NOT COALESCE((v_cli_on->>'visivel')::boolean, false) THEN
    r.situacao := 'falhou'; r.obtido := 'Com marco ativo o cliente não viu o painel: ' || COALESCE(v_cli_on::text, 'nulo');
  ELSIF v_lin_col IS NULL OR (v_lin_col->>'seis_dias_sem_coletivo')::boolean THEN
    r.situacao := 'falhou'; r.obtido := 'Com CCT vigente a 6x1 seguiu como "sem coletivo": ' || COALESCE(v_lin_col::text, 'nulo');
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Sem marco ativo o cliente não vê nada; com 42h ativo a 6x1 aparece (1 colaborador, 44h, sem coletivo); com CCT vigente deixa de contar.';
  END IF;
  r.detalhe := jsonb_build_object('linha', v_lin, 'totais', v_imp->'totais');
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  BEGIN PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); EXCEPTION WHEN OTHERS THEN NULL; END;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-EC141-007 ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_ec141_007()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r      public.qa_retorno;
  v_t    uuid := public.qa_sandbox_tenant_id();
  v_cpf  text := public.qa_cpf(6147);
  v_dia  date := CURRENT_DATE - 1;
  v_esc  uuid;
  v_aceita boolean := false;
  v_msg  text;
  v_n    int;
  v_val  jsonb;
  v_sal  jsonb;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM set_config('request.jwt.claims', '', true);
  -- 42h já em vigor para a conta; escala de 44h (acima do teto).
  PERFORM public.ponto_marco_ativar('EC141_42H', CURRENT_DATE - 30, '[QA] teto em vigor', v_t);
  v_esc := public.qa_ec141_escala(v_cpf, 528, ARRAY['segunda','terca','quarta','quinta','sexta'], DATE '2026-01-01');
  v_val := public.ponto_escala_validar_teto(v_esc, v_dia);

  r.passo_ordem := 1;
  r.passo_acao := 'Colaborador bate entrada e saída numa escala acima do teto legal ativo';
  r.esperado := 'As batidas são gravadas e apuradas; a validação só AVISA (bloqueia = false)';
  BEGIN
    PERFORM public.qa_ponto_marca(v_cpf, '[QA-EC141] Colaborador', v_dia, TIME '08:00', 'entrada');
    PERFORM public.qa_ponto_marca(v_cpf, '[QA-EC141] Colaborador', v_dia, TIME '17:48', 'saida');
    PERFORM public.consolidar_ponto_diario_manual(v_t, v_cpf, v_dia);
    v_aceita := true;
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
  END;
  v_n := (SELECT count(*) FROM public.ponto_marcacoes m
           WHERE m.tenant_id = v_t AND m.colaborador_cpf = v_cpf AND m.data_marcacao = v_dia);
  v_sal := public.qa_ec141_dia(v_cpf, v_dia);

  IF NOT v_aceita OR v_n <> 2 THEN
    r.situacao := 'falhou'; r.obtido := format('Batida recusada em escala acima do teto (%s marcação(ões)): %s', v_n, COALESCE(v_msg, ''));
  ELSIF COALESCE((v_val->>'bloqueia')::boolean, true) THEN
    r.situacao := 'falhou'; r.obtido := 'A validação do teto passou a bloquear: ' || COALESCE(v_val::text, 'nulo');
  ELSIF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_val->'avisos') a WHERE a->>'codigo' = 'acima_teto_semanal') THEN
    r.situacao := 'falhou'; r.obtido := 'A escala de 44h com teto de 42h não gerou o aviso: ' || COALESCE(v_val::text, 'nulo');
  ELSIF v_sal IS NULL THEN
    r.situacao := 'falhou'; r.obtido := 'O dia batido não foi apurado';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Batidas gravadas e apuradas; o teto de 42h gerou só o aviso (sem bloqueio).';
  END IF;
  r.detalhe := jsonb_build_object('validacao', v_val, 'dia', v_sal);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- Ajudante: "fotografia" de tudo o que a apuração e as telas leem da escala
-- num intervalo de dias (por dia) e em competências (por mês).
CREATE OR REPLACE FUNCTION public.qa_ec141_foto(
  p_cpf text, p_escala uuid, p_de date, p_ate date, p_comps text[], p_comps_espelho text[])
RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  v_t uuid := public.qa_sandbox_tenant_id();
BEGIN
  RETURN jsonb_build_object(
    'saldo', (SELECT jsonb_agg(to_jsonb(s) ORDER BY s.dia)
                FROM (SELECT DISTINCT to_char(g::date, 'YYYY-MM') AS c
                        FROM generate_series(p_de, p_ate, INTERVAL '1 day') g) cc
                CROSS JOIN LATERAL public.ponto_saldo_dias_competencia(v_t, p_cpf, cc.c) s
               WHERE s.dia BETWEEN p_de AND p_ate),
    'dias', (SELECT jsonb_agg(jsonb_build_object(
                'd', g::date,
                'jornada', (SELECT to_jsonb(j) FROM public.ponto_jornada_do_dia(v_t, p_cpf, p_cpf, g::date) j LIMIT 1),
                'escala', (SELECT to_jsonb(e) FROM public.ponto_escala_do_dia(v_t, p_cpf, p_cpf, g::date) e LIMIT 1),
                'intervalo', (SELECT to_jsonb(i) FROM public.ponto_intervalo_janela_do_dia(v_t, p_cpf, p_cpf, g::date) i LIMIT 1),
                'debito', public.ponto_debito_batida_do_dia(v_t, p_cpf, g::date, TIME '08:20', TIME '16:30'),
                'blocos', (SELECT jsonb_agg(jsonb_build_object('b', b.ordem_bloco, 'i', b.hora_inicio, 'f', b.hora_fim) ORDER BY b.ordem_bloco)
                             FROM public.ponto_escalas_periodos_na_data(ARRAY[p_escala], g::date) b),
                'tela', (SELECT jsonb_build_object('jd', x.jornada_diaria_minutos, 'ent', x.hora_entrada_padrao, 'sai', x.hora_saida_padrao)
                           FROM public.ponto_escalas_na_data(g::date, ARRAY[p_escala]) x))
              ORDER BY g)
               FROM generate_series(p_de, p_ate, INTERVAL '1 day') g),
    'meses', (SELECT jsonb_agg(jsonb_build_object(
                'c', c,
                'equalizacao', public.ponto_equalizacao_competencia(v_t, p_escala, c) - 'gerado_em',
                'equalizacao_conta', (SELECT jsonb_agg(jsonb_build_object('t', q.total_equalizacao_min, 'd', q.dias_uteis_efetivos))
                     FROM public.ponto_equalizacao_competencia_tenant(v_t, c, NULL) q WHERE q.escala_id = p_escala),
                'espelho', CASE WHEN c = ANY (p_comps_espelho)
                                THEN (SELECT to_jsonb(er) FROM public.ponto_espelho_resumo(v_t, p_cpf, c) er LIMIT 1) END)
              ORDER BY c)
               FROM unnest(p_comps) c));
END $fn$;

-- ── PONTO-EC141-008 ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_ec141_008()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r        public.qa_retorno;
  v_t      uuid := public.qa_sandbox_tenant_id();
  v_cpf    text := public.qa_cpf(6148);
  v_mes    date := date_trunc('month', CURRENT_DATE + 45)::date;   -- mês que contém D
  v_d      date;
  v_ant    date;
  v_comps  text[];
  v_esc    uuid;
  g        date;
  v_antes_menor  jsonb; v_depois_menor jsonb;
  v_antes_tudo   jsonb; v_cancel_tudo  jsonb;
  v_row0   jsonb; v_row2 jsonb;
  v_per0   jsonb; v_per2 jsonb;
  v_jd_d   int;
  v_res    jsonb;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM set_config('request.jwt.claims', '', true);
  v_d   := v_mes + 14;                                   -- dia 15
  v_ant := (v_mes - INTERVAL '1 month')::date;           -- mês inteiro antes de D
  v_comps := ARRAY[to_char(v_ant, 'YYYY-MM'), to_char(v_mes, 'YYYY-MM')];

  -- Escala 5x2 8h (40h) com equalização mensal ligada (contratada 44h).
  v_esc := public.qa_ec141_escala(v_cpf, 480, ARRAY['segunda','terca','quarta','quinta','sexta'], DATE '2026-01-01');
  UPDATE public.ponto_escalas SET equalizacao_mensal_ativa = true, carga_semanal_contratada_min = 2640 WHERE id = v_esc;
  -- Batidas: dias úteis variando em torno de 8h; o 1º sábado de cada mês trabalhado.
  FOR g IN SELECT x::date FROM generate_series(v_ant, v_d + 10, INTERVAL '1 day') x LOOP
    IF EXTRACT(ISODOW FROM g) BETWEEN 1 AND 5 THEN
      PERFORM public.qa_ponto_dia_min(v_cpf, '[QA-EC141] Colaborador', g, 540 + ((EXTRACT(DAY FROM g)::int * 7) % 25) - 12);
    ELSIF EXTRACT(ISODOW FROM g) = 6 AND EXTRACT(DAY FROM g) <= 7 THEN
      PERFORM public.qa_ponto_dia_min(v_cpf, '[QA-EC141] Colaborador', g, 300);
    END IF;
  END LOOP;

  r.passo_ordem := 1;
  r.passo_acao := 'Fotografar tudo dos dias e meses antes de D; agendar para D (dia 15 do mês) 7h/dia, tolerâncias novas, equalização desligada e contratada 40h; a tela regrava os blocos';
  r.esperado := 'A fotografia dos dias < D (saldo, jornada, horários, blocos, intervalo, débito, equalização, espelho do mês anterior) fica idêntica; D já usa 7h';
  -- Espelho: o mês anterior (inteiro antes de D) na comparação "antes de D";
  -- os dois meses na comparação do cancelamento.
  v_antes_menor := public.qa_ec141_foto(v_cpf, v_esc, v_ant, v_d - 1, v_comps, v_comps[1:1]);
  v_antes_tudo  := public.qa_ec141_foto(v_cpf, v_esc, v_ant, v_d + 10, v_comps, v_comps);
  v_row0 := (SELECT to_jsonb(e) - 'updated_at' FROM public.ponto_escalas e WHERE e.id = v_esc);
  v_per0 := (SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id) FROM public.ponto_escala_periodos p WHERE p.escala_id = v_esc);

  UPDATE public.ponto_escalas e
     SET dias_config = (SELECT jsonb_object_agg(x.k, x.v || CASE WHEN COALESCE((x.v->>'trabalha')::boolean, false)
                                                                  THEN jsonb_build_object('saida', '16:00') ELSE '{}'::jsonb END)
                          FROM jsonb_each(e.dias_config) x(k, v)),
         jornada_diaria_minutos = 420, jornada_semanal_minutos = 2100, hora_saida_padrao = TIME '16:00',
         tolerancia_minutos = 3, tolerancia_diaria_minutos = 7,
         equalizacao_mensal_ativa = false, carga_semanal_contratada_min = 2400,
         parametros_vigentes_desde = v_d, parametros_marco_codigo = 'EC141_40H'
   WHERE e.id = v_esc;
  PERFORM public._ponto_ec141_sincronizar_periodos(v_esc);
  v_depois_menor := public.qa_ec141_foto(v_cpf, v_esc, v_ant, v_d - 1, v_comps, v_comps[1:1]);
  v_jd_d := (SELECT j.jornada_min FROM public.ponto_jornada_do_dia(v_t, v_cpf, v_cpf, v_d) j LIMIT 1);

  r.passo_ordem := 2;
  r.passo_acao := 'Cancelar o agendamento';
  r.esperado := 'Escala, blocos e a fotografia de TODOS os dias (antes e depois de D) voltam exatamente ao estado anterior';
  v_res := public.ponto_escala_cancelar_agendamento(v_esc);
  v_cancel_tudo := public.qa_ec141_foto(v_cpf, v_esc, v_ant, v_d + 10, v_comps, v_comps);
  v_row2 := (SELECT to_jsonb(e) - 'updated_at' FROM public.ponto_escalas e WHERE e.id = v_esc);
  v_per2 := (SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id) FROM public.ponto_escala_periodos p WHERE p.escala_id = v_esc);

  IF v_antes_menor IS DISTINCT FROM v_depois_menor THEN
    r.situacao := 'falhou';
    r.obtido := 'O agendamento mudou algo ANTES da data D: '
      || COALESCE((SELECT string_agg(k, ', ') FROM jsonb_object_keys(v_antes_menor) k
                    WHERE v_antes_menor->k IS DISTINCT FROM v_depois_menor->k), '?');
    r.detalhe := jsonb_build_object('antes', v_antes_menor, 'depois', v_depois_menor);
  ELSIF v_jd_d IS DISTINCT FROM 420 THEN
    r.situacao := 'falhou'; r.obtido := format('Em D a jornada devia ser 420 e veio %s', COALESCE(v_jd_d::text, 'nula'));
  ELSIF NOT COALESCE((v_res->>'ok')::boolean, false) THEN
    r.situacao := 'falhou'; r.obtido := 'Cancelamento recusado: ' || COALESCE(v_res::text, 'nulo');
  ELSIF v_row0 IS DISTINCT FROM v_row2 THEN
    r.situacao := 'falhou'; r.obtido := 'A escala não voltou ao estado exato: '
      || COALESCE((SELECT string_agg(k, ', ') FROM jsonb_object_keys(v_row0) k WHERE v_row0->k IS DISTINCT FROM v_row2->k), '?');
  ELSIF v_per0 IS DISTINCT FROM v_per2 THEN
    r.situacao := 'falhou'; r.obtido := 'Os blocos diários não voltaram ao estado exato';
  ELSIF v_antes_tudo IS DISTINCT FROM v_cancel_tudo THEN
    r.situacao := 'falhou';
    r.obtido := 'Depois de cancelar a apuração não voltou ao estado anterior: '
      || COALESCE((SELECT string_agg(k, ', ') FROM jsonb_object_keys(v_antes_tudo) k
                    WHERE v_antes_tudo->k IS DISTINCT FROM v_cancel_tudo->k), '?');
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Agendado para %s: dias e meses anteriores idênticos (saldo, jornada, horários, blocos, intervalo, débito, equalização, espelho); D com 7h; cancelar devolveu escala, blocos e apuração exatos.', to_char(v_d, 'DD/MM/YYYY'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- Documentação dos casos + implementações
DO $doc$
DECLARE v_mod uuid;
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL OR to_regclass('public.qa_modulos') IS NULL THEN
    RAISE NOTICE 'Motor de QA ausente; casos PONTO-EC141 não documentados.';
    RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'jornada-rotina/ponto' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo jornada-rotina/ponto ausente; casos PONTO-EC141 não documentados.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PONTO-EC141-001',
   'EC 141: com os marcos 42h/40h inativos, a apuração de uma semana 5x2 8h48 não muda',
   'alternativo', 'critica', 'aprovado', 'api',
   'CF art. 7º, XIII (redação original, 44h); EC 141/2026, art. 6º (transição só por ativação manual)',
   'A entrega F1 cria os marcos legais e a escala com "vigente a partir de" desligados. Nada pode mudar sozinho numa data: sem marco ativo e sem agendamento, jornada e saldo saem exatamente como antes.',
   'Cercado de QA; marcos EC141_42H e EC141_40H inativos para a conta (exceção da conta).',
   '[{"ordem":1,"acao":"Escala 5x2 8h48 sem edição; batidas de 8h48, 9h, 8h20, 8h48 e 10h na semana de 10/08/2026","resultado_esperado":"Jornada 528 por dia útil; saldos 0, +12, -28, 0, +72; sábado 0; nenhuma versão; teto 44h"}]'::jsonb,
   'Apuração idêntica e teto CF/88 enquanto nenhum marco EC 141 estiver ativo.',
   'Fotografia mínima da F1 (Plano Mestre, princípio 1). Semana fixa para não depender de feriado.'),
  (v_mod, 'PONTO-EC141-002',
   'Escala com "vale a partir de": a nova jornada só vale da data em diante',
   'feliz', 'critica', 'aprovado', 'api',
   'EC 141/2026, art. 6º e 7º; CLT art. 58 e 59; CLT art. 468 (alteração só para frente)',
   'A HE é diária (trabalhado - jornada do dia). Ao agendar 8h48 -> 8h24 para a data D, a véspera continua com 8h48 e o dia D em diante passa a 8h24. Antes desta entrega o gatilho de versão só sabia congelar até ontem.',
   'Cercado de QA; escala 5x2 8h48 atribuída.',
   '[{"ordem":1,"acao":"Salvar 8h24 com \"vale a partir de\" D (terça futura), marco EC141_42H","resultado_esperado":"Versão antiga até D-1 (origem agendamento, marco gravado)"},
     {"ordem":2,"acao":"D-1 com 8h48; D com 8h48; D+1 com 8h24","resultado_esperado":"D-1: 528/0; D: 504/+24; D+1: 504/0"}]'::jsonb,
   'Corte exato na data agendada, sem tocar o passado.',
   'Mesmo gesto da tela (UPDATE da escala com parametros_vigentes_desde); saldo pela ponto_saldo_dias_competencia.'),
  (v_mod, 'PONTO-EC141-003',
   'Cancelar o agendamento da escala restaura os valores antigos (e só um agendamento por escala)',
   'feliz', 'alta', 'aprovado', 'api',
   'EC 141/2026 (lei pode ser revogada/adiada antes da data); CLT art. 468',
   'Se a lei mudar antes da data, o RH (ou o lote do SuperAdmin) cancela o agendamento e a escala volta a ser o que era, sem resíduo de versão.',
   'Cercado de QA; escala 5x2 8h48 com 8h24 agendada para daqui a 10 dias.',
   '[{"ordem":1,"acao":"Tentar agendar outra data com um pendente","resultado_esperado":"Recusado"},
     {"ordem":2,"acao":"ponto_escala_cancelar_agendamento","resultado_esperado":"Escala volta a 8h48 (17:48), nenhuma versão pendente; jornada de D = 528"}]'::jsonb,
   'Cancelamento devolve a escala ao estado anterior.',
   'O lote (ponto_escalas_cancelar_agendamentos_lote) chama a mesma função por escala.'),
  (v_mod, 'PONTO-EC141-004',
   'Alteração retroativa da escala: exige justificativa, nunca atinge competência fechada e, nesta entrega, fica bloqueada',
   'negativo', 'critica', 'aprovado', 'api',
   'Plano Mestre do Ponto, princípio 3 (meses fechados são intocáveis); Súmula 338 do TST',
   'Uma data anterior a hoje reescreve dias já apurados. Exige justificativa e nunca atinge competência fechada; como os dias já consolidados no ponto_diario precisariam ser recalculados e essa reconsolidação ainda não existe, a F1 bloqueia o retroativo (liberação prevista na F2).',
   'Cercado de QA; duas escalas 5x2 8h48; fechamento do mês passado criado no passo 3.',
   '[{"ordem":1,"acao":"Valer desde ontem, sem justificativa","resultado_esperado":"Recusado"},
     {"ordem":2,"acao":"Valer desde ontem, com justificativa","resultado_esperado":"Bloqueado nesta entrega; ontem segue 528"},
     {"ordem":3,"acao":"Fechar o mês passado e valer desde o dia 1º dele","resultado_esperado":"Recusado (competência fechada)"}]'::jsonb,
   'Retroativo controlado; mês fechado protegido.',
   'Gatilho ponto_escala_arquiva_versao.'),
  (v_mod, 'PONTO-EC141-005',
   'Teto legal: marco inativo é ignorado; ativação, data, desativação e exceção por conta são respeitadas; só o SuperAdmin altera',
   'feliz', 'critica', 'aprovado', 'api',
   'CF art. 7º, XIII e XV (redação da EC 141/2026); EC 141/2026, art. 6º',
   'Decisão da fundadora (30/10/2026): a transição é manual. ponto_teto_legal só considera marcos ATIVOS, a exceção da conta vence a regra global, e toda alteração fica no histórico.',
   'Cercado de QA; marcos alterados apenas como exceção da conta do cercado.',
   '[{"ordem":1,"acao":"Teto com os marcos inativos","resultado_esperado":"44h"},
     {"ordem":2,"acao":"Ativar 42h em D","resultado_esperado":"D-1: 44h; D: 42h, 2 repousos, divisor 210"},
     {"ordem":3,"acao":"Adiar 10 dias","resultado_esperado":"D: 44h"},
     {"ordem":4,"acao":"Desativar","resultado_esperado":"44h mesmo após a data"},
     {"ordem":5,"acao":"Reativar só na conta; comparar com outra conta","resultado_esperado":"Só a conta muda"},
     {"ordem":6,"acao":"Usuário comum tenta ativar","resultado_esperado":"sem_permissao"}]'::jsonb,
   'Teto obedece só ao gesto do SuperAdmin.',
   'Histórico em ponto_marcos_legais_historico.'),
  (v_mod, 'PONTO-EC141-006',
   'Painel de impacto da EC 141 conta a 6x1 sem instrumento coletivo e fica oculto ao cliente sem marco ativo',
   'feliz', 'alta', 'aprovado', 'api',
   'CF art. 7º, XV e §2º (redação da EC 141/2026): 2 repousos, ou média mensal só por CCT/ACT',
   'O painel é somente leitura. Para o cliente só aparece com marco EC 141 ativo; mostra por empresa e escala os colaboradores, a carga atual contra o teto e a 6x1 sem coletivo.',
   'Cercado de QA; escala 6x1 7h20 (44h) com 1 colaborador; sem coletivo.',
   '[{"ordem":1,"acao":"Cliente abre o painel sem marco ativo","resultado_esperado":"visivel = false"},
     {"ordem":2,"acao":"Ativar 42h e consultar","resultado_esperado":"6x1 com 1 colaborador, 44h acima do teto, 6 dias sem coletivo; cliente passa a ver"},
     {"ordem":3,"acao":"Cadastrar CCT vigente e consultar","resultado_esperado":"Deixa de contar como sem coletivo"}]'::jsonb,
   'Impacto correto e oculto enquanto a lei não for ativada.',
   'ponto_ec141_impacto; coletivo por ponto_tem_coletivo_vigente (Parte 1) quando existe.'),
  (v_mod, 'PONTO-EC141-007',
   'Batida em escala acima do teto legal continua aceita (o teto só gera aviso)',
   'negativo', 'critica', 'aprovado', 'api',
   'Portaria MTP 671/2021 (o registro não pode ser impedido); Plano Mestre do Ponto, princípio 2',
   'Mesmo com o teto de 42h em vigor, a batida de quem está numa escala de 44h é gravada e apurada. A validação do teto devolve avisos e nunca bloqueia.',
   'Cercado de QA; EC141_42H ativo para a conta desde 30 dias atrás; escala 5x2 8h48.',
   '[{"ordem":1,"acao":"Bater entrada e saída ontem e consolidar o dia","resultado_esperado":"2 marcações gravadas; dia apurado; validação com aviso acima_teto_semanal e bloqueia = false"}]'::jsonb,
   'Nunca bloquear a batida.',
   'ponto_escala_validar_teto é a função usada como aviso na tela de escalas.'),
  (v_mod, 'PONTO-EC141-008',
   'Com uma alteração agendada para D, nada dos dias anteriores a D muda; cancelar devolve o estado exato',
   'alternativo', 'critica', 'aprovado', 'api',
   'CLT art. 468 (alteração só para frente); Plano Mestre do Ponto, princípios 1 e 4',
   'Critério "nada muda antes da data D": saldo, jornada do dia, horários esperados e blocos diários, intervalo, débito por batida, equalização (da escala e da conta) e espelho seguem idênticos para os dias e meses anteriores a D. O cancelamento restaura escala, blocos e apuração exatamente.',
   'Cercado de QA; escala 5x2 8h com equalização (contratada 44h); batidas do mês anterior a D até D+10.',
   '[{"ordem":1,"acao":"Fotografar; agendar 7h/dia, tolerâncias, equalização desligada e contratada 40h para D (dia 15); a tela regrava os blocos","resultado_esperado":"Fotografia dos dias < D idêntica; D com jornada 420"},
     {"ordem":2,"acao":"Cancelar o agendamento","resultado_esperado":"Escala, blocos e fotografia de todos os dias iguais ao estado anterior"}]'::jsonb,
   'Nada muda antes de D; cancelamento exato.',
   'Leitores cobertos por reinjeção [ec141-f1] e pelas funções ponto_escala_na_data_agendada / ponto_escala_periodos_na_data.')
  ON CONFLICT (codigo) DO UPDATE SET
    modulo_id = EXCLUDED.modulo_id, titulo = EXCLUDED.titulo, objetivo = EXCLUDED.objetivo,
    passos = EXCLUDED.passos, resultado_esperado = EXCLUDED.resultado_esperado,
    base_legal = EXCLUDED.base_legal, observacoes = EXCLUDED.observacoes,
    pre_condicoes = EXCLUDED.pre_condicoes, status = 'aprovado';

  -- PONTO-153 continua valendo; a descrição ganha o "vale a partir de".
  UPDATE public.qa_casos_teste
     SET observacoes = COALESCE(observacoes, '') ||
         CASE WHEN position('EC 141 F1' IN COALESCE(observacoes, '')) > 0 THEN ''
              ELSE ' EC 141 F1 (30/10/2026): a edição pode valer "a partir de" uma data (versão congelada até a véspera); sem data, segue congelando até ontem. Na edição com data a versão guarda também compensações, carga contratada, equalização, tipo e jornada semanal (ver PONTO-EC141-002/003/004).' END
   WHERE codigo = 'PONTO-153';

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
      ('PONTO-EC141-001', 'qa_caso_ponto_ec141_001', true),
      ('PONTO-EC141-002', 'qa_caso_ponto_ec141_002', true),
      ('PONTO-EC141-003', 'qa_caso_ponto_ec141_003', true),
      ('PONTO-EC141-004', 'qa_caso_ponto_ec141_004', true),
      ('PONTO-EC141-005', 'qa_caso_ponto_ec141_005', true),
      ('PONTO-EC141-006', 'qa_caso_ponto_ec141_006', true),
      ('PONTO-EC141-007', 'qa_caso_ponto_ec141_007', true),
      ('PONTO-EC141-008', 'qa_caso_ponto_ec141_008', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentação PONTO-EC141 não registrada: %', SQLERRM;
END $doc$;

-- Resumo da bateria da entrega (usado na conferência do script de entrega).
-- Roda os casos pelo motor (descartável: nada fica na base) e devolve
-- "codigo:situacao | ...". Sem motor, devolve o aviso em vez de quebrar.
CREATE OR REPLACE FUNCTION public.qa_ponto_ec141_f1_resumo()
RETURNS text LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  v_out  text := '';
  v_cod  text;
  v_fn   text;
  v_sit  text;
BEGIN
  IF to_regprocedure('public.qa_executar_descartavel(text)') IS NULL THEN
    RETURN 'motor de QA ausente';
  END IF;
  FOR v_cod, v_fn IN
    SELECT x.cod, x.fn FROM (VALUES
      ('PONTO-EC141-001', 'qa_caso_ponto_ec141_001'), ('PONTO-EC141-002', 'qa_caso_ponto_ec141_002'),
      ('PONTO-EC141-003', 'qa_caso_ponto_ec141_003'), ('PONTO-EC141-004', 'qa_caso_ponto_ec141_004'),
      ('PONTO-EC141-005', 'qa_caso_ponto_ec141_005'), ('PONTO-EC141-006', 'qa_caso_ponto_ec141_006'),
      ('PONTO-EC141-007', 'qa_caso_ponto_ec141_007'), ('PONTO-EC141-008', 'qa_caso_ponto_ec141_008'),
      ('PONTO-153', 'qa_caso_ponto_153'),
      ('PONTO-478', 'qa_caso_ponto_478')) AS x(cod, fn)
  LOOP
    IF to_regprocedure('public.' || v_fn || '()') IS NULL THEN
      v_sit := 'ausente';
    ELSE
      BEGIN
        v_sit := (SELECT (public.qa_executar_descartavel(v_fn)).situacao::text);
      EXCEPTION WHEN OTHERS THEN
        v_sit := 'erro: ' || SQLERRM;
      END;
    END IF;
    v_out := v_out || CASE WHEN v_out = '' THEN '' ELSE ' | ' END || v_cod || ':' || COALESCE(v_sit, 'nulo');
  END LOOP;
  RETURN v_out;
END $fn$;
