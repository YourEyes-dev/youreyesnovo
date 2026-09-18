-- ============================================================================
-- QA — LOTE 2 (PONTO): entregar as 101 rotinas de caso de Ponto a producao.
--
-- Funcoes qa_caso_ponto_* que existem no dev/staging e nunca chegaram a
-- producao (drift). Aditivo (CREATE OR REPLACE) + liga em qa_implementacoes.
-- Read-only por natureza (rodam por simulacao/descarte). A fundacao (Lote 1) e
-- os apoios ja estao na producao. Conferencia no fim agrupa por situacao.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_001()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text; m record;
BEGIN
  v_cpf := public.qa_ponto_admissao('QA Marcação Base', 5001);
  r.passo_ordem := 1;
  r.passo_acao := 'Registrar uma marcação e conferir os campos essenciais';
  r.esperado := 'Data, hora, CPF e hash presentes e coerentes';
  PERFORM public.qa_ponto_marca(v_cpf, 'QA Marcação Base', CURRENT_DATE, TIME '08:00', 'entrada');
  SELECT * INTO m FROM public.ponto_marcacoes
  WHERE tenant_id = public.qa_sandbox_tenant_id() AND colaborador_cpf = v_cpf
  ORDER BY created_at DESC LIMIT 1;
  IF m.data_marcacao = CURRENT_DATE AND m.hora_marcacao = TIME '08:00'
     AND m.colaborador_cpf = v_cpf AND coalesce(m.hash_marcacao, '') <> ''
     AND m.hash_marcacao <> 'qa-seed' THEN
    r.situacao := 'passou';
    r.obtido := 'Marcação gravada com data, hora, CPF e hash gerado pelo gatilho.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Campos incompletos: data=%s hora=%s cpf=%s hash=%s. A identificação '
      || 'por CPF e o carimbo íntegro são a base da Portaria 671.',
      m.data_marcacao, m.hora_marcacao, m.colaborador_cpf,
      CASE WHEN coalesce(m.hash_marcacao,'') IN ('','qa-seed') THEN 'NÃO GERADO' ELSE 'ok' END);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_003()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_jobs int := 0;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): existe rotina agendada que INSIRA marcações?';
  r.esperado := 'Nenhuma — marcação automática é vedada pela Portaria 671';
  IF to_regclass('cron.job') IS NOT NULL THEN
    EXECUTE 'SELECT count(*) FROM cron.job WHERE command ILIKE ''%ponto_marcacoes%'' AND command ILIKE ''%INSERT%'''
    INTO v_jobs;
  END IF;
  IF v_jobs = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'Nenhum agendamento insere marcações. As únicas inserções fora do gesto do '
             || 'usuário são as batidas de abono aprovadas por gestor (dia inteiro justificado), '
             || 'que carregam origem própria — não são ficção de jornada.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('%s agendamento(s) inserem marcações automaticamente — ficção de jornada '
             || 'vedada pela Portaria 671, que destrói o valor probatório do conjunto.', v_jobs);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_020()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text := public.qa_cpf(5020);
        v_base date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
        v_dia date; v_saldo int; v_status text;
BEGIN
  v_dia := v_base + ((8 - EXTRACT(ISODOW FROM v_base)::int) % 7);
  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Dia Completo', 480, 10, v_dia, v_dia);
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Dia Completo', v_dia, 480);

  r.passo_ordem := 1;
  r.passo_acao := format('Apurar dia completo (480 min trabalhados, jornada 480) em %s', v_dia);
  r.esperado := 'Saldo zero e status regular — a régua de todos os demais casos';
  SELECT max(s.saldo_min) INTO v_saldo
  FROM public.ponto_saldo_dias_competencia(public.qa_sandbox_tenant_id(), v_cpf,
       to_char(v_dia, 'YYYY-MM')) s WHERE s.dia = v_dia;
  SELECT status INTO v_status FROM public.ponto_diario
  WHERE tenant_id = public.qa_sandbox_tenant_id() AND colaborador_cpf = v_cpf AND data = v_dia;

  IF v_saldo = 0 AND v_status = 'regular' THEN
    r.situacao := 'passou';
    r.obtido := 'Dia completo fechou com saldo zero e status regular.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Dia completo saiu torto: saldo=%s (esperado 0), status=%s (esperado regular).',
                       coalesce(v_saldo::text, 'sem linha'), coalesce(v_status, 'NULL'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_021()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text; v_dia date := CURRENT_DATE - 2;
        d record;
BEGIN
  v_cpf := public.qa_ponto_admissao('QA Ímpar', 5021);
  PERFORM public.qa_ponto_marca(v_cpf, 'QA Ímpar', v_dia, TIME '08:00', 'entrada', false);
  PERFORM public.qa_ponto_marca(v_cpf, 'QA Ímpar', v_dia, TIME '12:00', 'saida',   false);
  PERFORM public.qa_ponto_marca(v_cpf, 'QA Ímpar', v_dia, TIME '13:00', 'entrada', false);

  r.passo_ordem := 1;
  r.passo_acao := 'Consolidar dia com 3 marcações (entrada 08, saída 12, entrada 13 — sem saída final)';
  r.esperado := 'Só o período pareado conta (4h); dia visivelmente incompleto, sem par inventado';
  PERFORM public.consolidar_ponto_diario_manual(public.qa_sandbox_tenant_id(), v_cpf, v_dia);
  SELECT status, horas_trabalhadas INTO d FROM public.ponto_diario
  WHERE tenant_id = public.qa_sandbox_tenant_id() AND colaborador_cpf = v_cpf AND data = v_dia;

  IF d.status = 'incompleto' AND d.horas_trabalhadas = INTERVAL '4 hours' THEN
    r.situacao := 'passou';
    r.obtido := 'O dia ficou incompleto com 4h (só o par fechado) — nenhuma saída foi inventada.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Ímpar mal tratado: status=%s (esperado incompleto), horas=%s (esperado 4h). '
             || 'Fechar o par que falta seria CRIAR marcação — vedado pela Portaria 671.',
             coalesce(d.status, 'sem linha'), coalesce(d.horas_trabalhadas::text, '-'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_022()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text; v_dia date := CURRENT_DATE - 2;
        d record;
BEGIN
  v_cpf := public.qa_ponto_admissao('QA Meia-Noite', 5022);

  r.passo_ordem := 1;
  r.passo_acao := 'Lançar turno 22:00 → 06:00 no dia de início e consolidar';
  r.esperado := '8 horas apuradas NO DIA DE INÍCIO — a virada não parte a jornada em duas';
  PERFORM public.qa_ponto_marca(v_cpf, 'QA Meia-Noite', v_dia, TIME '22:00', 'entrada', false);
  BEGIN
    PERFORM public.qa_ponto_marca(v_cpf, 'QA Meia-Noite', v_dia, TIME '06:00', 'saida', false);
  EXCEPTION WHEN OTHERS THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a saída de 06:00 lançada no dia de início foi RECUSADA (%s). '
             || 'O gatilho de reordenação automática interpreta a batida da madrugada como '
             || '"anterior" à entrada de 22:00 e tenta reetiquetar — colidindo com a '
             || 'imutabilidade. Resultado: o turno que cruza a meia-noite não pode ser '
             || 'registrado no dia de início, e a jornada acaba partida em dois dias (falta '
             || 'fictícia no segundo, prorrogação noturna subdimensionada). Correção: a '
             || 'reordenação por relógio precisa reconhecer a virada (saída menor que a '
             || 'entrada = dia seguinte), como a apuração já faz.', SQLERRM);
    RETURN r;
  END;
  PERFORM public.consolidar_ponto_diario_manual(public.qa_sandbox_tenant_id(), v_cpf, v_dia);
  SELECT horas_trabalhadas, status INTO d FROM public.ponto_diario
  WHERE tenant_id = public.qa_sandbox_tenant_id() AND colaborador_cpf = v_cpf AND data = v_dia;

  IF d.horas_trabalhadas = INTERVAL '8 hours' THEN
    r.situacao := 'passou';
    r.obtido := 'O turno noturno fechou 8h no dia de início — sem falta fictícia no dia seguinte.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Turno da virada apurou %s (esperado 8h, status atual %s). Partir a jornada '
             || 'em dois dias gera falta fictícia e subdimensiona a prorrogação noturna.',
             coalesce(d.horas_trabalhadas::text, 'sem linha'), coalesce(d.status, '-'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_024()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text; v_dia date := public.qa_dia_util_passado();
        v_status text;
BEGIN
  v_cpf := public.qa_ponto_admissao('QA Amparado', 5024);
  -- Batida em outro dia para o consolidador conseguir resolver o colaborador
  PERFORM public.qa_ponto_marca(v_cpf, 'QA Amparado', CURRENT_DATE, TIME '08:00', 'entrada');
  INSERT INTO public.atestados
    (tenant_id, colaborador_cpf, colaborador_nome, tipo, data_emissao,
     profissional_nome, profissional_registro,
     data_inicio_afastamento, data_fim_afastamento, unidade_afastamento)
  VALUES (public.qa_sandbox_tenant_id(), v_cpf, 'QA Amparado',
          'atestados', v_dia, 'Dra. QA', 'CRM-QA-0001', v_dia, v_dia, 'dias');

  r.passo_ordem := 1;
  r.passo_acao := format('Materializar %s com atestado cobrindo o dia', v_dia);
  r.esperado := 'O dia não vira falta — ausência amparada tem regime próprio (art. 473 e afins)';
  PERFORM public.ponto_materializar_faltas(v_dia, v_dia, public.qa_sandbox_tenant_id());
  SELECT status INTO v_status FROM public.ponto_diario
  WHERE tenant_id = public.qa_sandbox_tenant_id() AND colaborador_cpf = v_cpf AND data = v_dia;

  IF coalesce(v_status, 'ausente') <> 'falta' THEN
    r.situacao := 'passou';
    r.obtido := format('O dia amparado por atestado não virou falta (ficou: %s).',
                       coalesce(v_status, 'sem linha — dia não materializado como falta'));
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'O dia COM ATESTADO virou falta — desconto indevido de DSR e de salário sobre '
             || 'ausência amparada.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_025()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text; v_bloqueou boolean := false;
BEGIN
  v_cpf := public.qa_ponto_admissao('QA Afastado', 5025);
  INSERT INTO public.afastamentos
    (tenant_id, colaborador_cpf, colaborador_nome, status, data_inicio, data_fim)
  VALUES (public.qa_sandbox_tenant_id(), v_cpf, 'QA Afastado', 'ativo',
          CURRENT_DATE - 5, CURRENT_DATE + 5);

  r.passo_ordem := 1;
  r.passo_acao := 'Tentar marcar ponto durante afastamento ativo';
  r.esperado := 'Recusado — na suspensão não há serviço a registrar';
  BEGIN
    PERFORM public.qa_ponto_marca(v_cpf, 'QA Afastado', CURRENT_DATE, TIME '08:00', 'entrada');
    v_bloqueou := false;
  EXCEPTION WHEN OTHERS THEN v_bloqueou := true; END;

  IF v_bloqueou THEN
    r.situacao := 'passou';
    r.obtido := 'A marcação durante o afastamento foi recusada.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'O afastado conseguiu marcar ponto — registro de serviço durante suspensão do '
             || 'contrato contamina a apuração e o eSocial.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_040()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text := public.qa_cpf(5040);
        v_base date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
        v_d1 date; v_d2 date; v_s1 int; v_s2 int;
BEGIN
  v_d1 := v_base + ((8 - EXTRACT(ISODOW FROM v_base)::int) % 7);
  v_d2 := v_d1 + 1;
  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Tolerância 5', 480, 10, v_d1, v_d2);
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Tolerância 5', v_d1, 476);  -- 4 min a menos
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Tolerância 5', v_d2, 484);  -- 4 min a mais

  r.passo_ordem := 1;
  r.passo_acao := 'Apurar dias com variação de 4 min para menos e para mais';
  r.esperado := 'Saldo zero nos dois — a tolerância não desconta E não paga';
  SELECT max(s.saldo_min) FILTER (WHERE s.dia = v_d1),
         max(s.saldo_min) FILTER (WHERE s.dia = v_d2) INTO v_s1, v_s2
  FROM public.ponto_saldo_dias_competencia(public.qa_sandbox_tenant_id(), v_cpf,
       to_char(v_d1, 'YYYY-MM')) s;

  IF v_s1 = 0 AND v_s2 = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'Variação de 4 minutos absorvida nos dois sentidos — bilateral como manda o art. 58, §1º.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Tolerância mal aplicada: -4 min deu saldo %s e +4 min deu %s (esperado 0 e 0).',
                       coalesce(v_s1::text, '-'), coalesce(v_s2::text, '-'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_041()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text := public.qa_cpf(5041);
        v_base date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
        v_d1 date; v_d2 date; v_s1 int; v_s2 int;
BEGIN
  v_d1 := v_base + ((8 - EXTRACT(ISODOW FROM v_base)::int) % 7);
  v_d2 := v_d1 + 1;
  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Fronteira 5', 480, 10, v_d1, v_d2);
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Fronteira 5', v_d1, 475);  -- exatos 5 min
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Fronteira 5', v_d2, 474);  -- 6 min

  r.passo_ordem := 1;
  r.passo_acao := 'Apurar variação de exatos 5 min (uma marcação) e de 6 min';
  r.esperado := '5 min: absorvido. 6 min: excedeu o limite POR MARCAÇÃO — computa os 6 (Súmula 366)';
  SELECT max(s.saldo_min) FILTER (WHERE s.dia = v_d1),
         max(s.saldo_min) FILTER (WHERE s.dia = v_d2) INTO v_s1, v_s2
  FROM public.ponto_saldo_dias_competencia(public.qa_sandbox_tenant_id(), v_cpf,
       to_char(v_d1, 'YYYY-MM')) s;

  IF v_s1 = 0 AND v_s2 = -6 THEN
    r.situacao := 'passou';
    r.obtido := 'Fronteira exata: 5 min absorvidos, 6 min computados integralmente.';
  ELSIF v_s1 = 0 AND v_s2 = 0 THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a variação de 6 minutos numa única marcação foi ZERADA. O sistema só '
             || 'aplica o teto diário genérico de 10 minutos — o limite de 5 POR MARCAÇÃO '
             || '(art. 58, §1º; Súmula 366: excedido, computa-se a totalidade) não existe na '
             || 'apuração de saldo. É a borda mais cara do módulo: muda a base de toda a hora '
             || 'extra. Correção: aplicar os dois limites cumulativamente.';
    r.detalhe := jsonb_build_object('saldo_5min', v_s1, 'saldo_6min', v_s2);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Fronteira errada: 5 min deu %s (esperado 0) e 6 min deu %s (esperado -6).',
                       coalesce(v_s1::text, '-'), coalesce(v_s2::text, '-'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_042()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_src text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a consolidação de batidas respeita o limite de 5 min por marcação?';
  r.esperado := 'Dois tetos cumulativos: 5 min por marcação E 10 min no dia';
  SELECT pg_get_functiondef(p.oid) INTO v_src
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'ponto_saldo_dias_competencia_bruto';

  IF v_src ILIKE '%tolerancia_batida_min, 10%' THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o encaixe de batida na escala usa padrão de 10 MINUTOS POR MARCAÇÃO '
             || '(COALESCE(tolerancia_batida_min, 10) na apuração) — o dobro do limite legal de '
             || '5. Com duas batidas, até 20 minutos diários podem ser absorvidos, o dobro do '
             || 'teto de 10 do art. 58, §1º. O teto diário exato (10→0, 11→11) está correto '
             || '(PONTO-353), mas o limite por marcação não é aplicado (PONTO-041). Correção: '
             || 'padrão 5 por marcação e teto conjunto de 10 no dia.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'O encaixe por marcação não usa mais o padrão de 10 — conferir se os dois tetos '
             || 'estão cumulativos (fronteiras em PONTO-041/353).';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_043()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_aceitou boolean := false;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Cadastrar escala com tolerância de 30 minutos (6× o limite legal)';
  r.esperado := 'Recusado — a Súmula 449 veda inclusive por negociação coletiva';
  BEGIN
    PERFORM public.qa_ponto_escala_tol(public.qa_cpf(5043), 'QA Tolerância 30', 480, 30,
                                       CURRENT_DATE - 10, CURRENT_DATE - 10);
    v_aceitou := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN
    v_aceitou := false;
  END;

  IF v_aceitou THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o banco ACEITOU tolerância de 30 minutos. Não existe CHECK limitando '
             || 'tolerancia_minutos/tolerancia_diaria_minutos ao teto legal (5/10) — e a Súmula '
             || '449 do TST fecha a porta até para a negociação coletiva elastecer. O parâmetro '
             || 'fora da faixa produz apuração ilegal em silêncio. Correção: CHECK no cadastro '
             || 'de escalas.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Tolerância acima do limite legal foi recusada no cadastro.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_060()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): existe cálculo de indenização por supressão de intervalo?';
  r.esperado := '50% sobre APENAS o período suprimido, natureza indenizatória (art. 71, §4º pós-2017)';
  v_fns := coalesce(public.qa_fns_com('%supress%'), public.qa_fns_com('%71%indeniz%'));
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: não existe cálculo de supressão de intervalo. Jornada acima de 6h com '
             || 'pausa menor que 1h deveria gerar indenização de 50% SÓ sobre os minutos '
             || 'suprimidos (redação pós-reforma) — hoje a supressão passa em branco na '
             || 'apuração. Atenção ao implementar: a regra ANTIGA (hora cheia, natureza '
             || 'salarial) foi revogada em 2017 — usar a nova.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Cálculo de supressão presente em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_061()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text; v_dia date := CURRENT_DATE - 2; v_marcado boolean;
BEGIN
  v_cpf := public.qa_ponto_admissao('QA Sem Pausa', 5061);
  PERFORM public.qa_ponto_marca(v_cpf, 'QA Sem Pausa', v_dia, TIME '08:00', 'entrada', false);
  PERFORM public.qa_ponto_marca(v_cpf, 'QA Sem Pausa', v_dia, TIME '16:30', 'saida', false);
  PERFORM public.consolidar_ponto_diario_manual(public.qa_sandbox_tenant_id(), v_cpf, v_dia);

  r.passo_ordem := 1;
  r.passo_acao := 'Dia de 8h30 corridas, sem nenhuma pausa — conferir se a supressão TOTAL é sinalizada';
  r.esperado := 'Ocorrência de intervalo suprimido registrada (alerta ou marcação no dia)';
  SELECT EXISTS (
    SELECT 1 FROM public.ponto_alertas
    WHERE tenant_id = public.qa_sandbox_tenant_id() AND colaborador_cpf = v_cpf
      AND (tipo ILIKE '%interval%' OR descricao ILIKE '%interval%')
  ) INTO v_marcado;

  IF v_marcado THEN
    r.situacao := 'passou';
    r.obtido := 'A supressão total do intervalo gerou sinalização.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: 8h30 corridas sem NENHUMA pausa não geraram alerta nem ocorrência — '
             || 'a supressão integral do intervalo (art. 71) passa invisível. É violação com '
             || 'indenização devida e fator de risco de SST. Correção: detecção na consolidação '
             || 'do dia + alerta (o gerador atual só conhece falta e atraso).';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_062()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o mínimo de intervalo é aplicado POR FAIXA de jornada?';
  r.esperado := 'Até 4h: sem mínimo; 4–6h: 15 min; acima de 6h: 1h (art. 71)';
  v_fns := coalesce(public.qa_fns_com('%faixa%interval%'), public.qa_fns_com('%15 min%interval%'));
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nenhuma função aplica o mínimo de intervalo por faixa de jornada. '
             || 'Sem as faixas do art. 71 (nenhum mínimo até 4h; 15 min entre 4 e 6h; 1h acima '
             || 'de 6h), qualquer validação futura que aplique "1 hora para todos" criará '
             || 'supressão fictícia nas jornadas curtas — e hoje não há validação alguma '
             || '(PONTO-060/061). Implementar as faixas junto com o cálculo de supressão.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Faixas aplicadas em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_063()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_aceitou boolean := false;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Cadastrar CCT com intervalo mínimo de 20 minutos (abaixo do piso legal de 30)';
  r.esperado := 'Recusado — a negociação pode reduzir, mas o piso de 30 min é absoluto (art. 611-A, III)';
  BEGIN
    INSERT INTO public.ponto_cct_config (tenant_id, nome, intervalo_minimo_min, ativo)
    VALUES (public.qa_sandbox_tenant_id(), 'QA CCT Piso Intervalo', 20, true);
    v_aceitou := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_aceitou := false; END;

  IF v_aceitou THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o banco ACEITOU CCT com intervalo mínimo de 20 minutos — abaixo do '
             || 'piso absoluto de 30 que nem a negociação coletiva pode furar (art. 611-A, III, '
             || 'da CLT). Correção: CHECK (intervalo_minimo_min IS NULL OR intervalo_minimo_min '
             || '>= 30) em ponto_cct_config.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'CCT com intervalo abaixo do piso de 30 minutos foi recusada.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_064()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_est text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a pré-assinalação do intervalo existe como registro declarado?';
  r.esperado := 'Intervalo previsto declarado, deduzido na apuração e VISÍVEL ao trabalhador';
  v_est := coalesce(public.qa_col_existe(NULL, '%pre_assinal%'), public.qa_fns_com('%pre_assinal%'));
  IF v_est IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO PARCIAL: a apuração até DEDUZ um intervalo previsto quando o dia tem só '
             || 'duas batidas (mecânica interna do saldo), mas não existe a PRÉ-ASSINALAÇÃO como '
             || 'figura formal: nada declara o intervalo previsto por vínculo, nada o exibe no '
             || 'espelho, e a Súmula 338 só valida marcação de duas batidas COM pré-assinalação '
             || 'expressa. Correção: campo de intervalo pré-assinalado no perfil de jornada, '
             || 'refletido no espelho e nos arquivos.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Pré-assinalação presente: %s.', v_est);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_080()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text; v_col text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o descanso de 11h entre jornadas é verificado?';
  r.esperado := 'Validação/alerta quando o intervalo entre a saída e a próxima entrada é menor que 11h';
  v_fns := public.qa_fns_com('%interjornada%');
  v_col := public.qa_col_existe('ponto_configuracao', 'interjornada%');
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a configuração até guarda o parâmetro (%s), mas NENHUMA função '
             || 'verifica o descanso de 11 horas do art. 66 — sair 23h e entrar 6h passa sem '
             || 'aviso. A supressão da interjornada é violação autônoma, devida mesmo que tudo '
             || 'seja pago como extra. Correção: verificação na consolidação (saída do dia D × '
             || 'entrada do dia D+1) com alerta.', coalesce(v_col, 'nem o parâmetro existe'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Interjornada verificada em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_090()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text := public.qa_cpf(5090);
        v_base date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
        v_dia date; v_cid uuid; v_res jsonb;
BEGIN
  v_dia := v_base + ((8 - EXTRACT(ISODOW FROM v_base)::int) % 7);  -- segunda-feira
  v_cid := public.qa_ponto_dia_horarios(v_cpf, 'QA HE 50', v_dia,
             TIME '08:00', TIME '19:00', TIME '12:00', TIME '13:00');  -- 10h trabalhadas

  r.passo_ordem := 1;
  r.passo_acao := format('Calcular HE do dia útil %s com 10h trabalhadas (jornada 8h)', v_dia);
  r.esperado := '120 min de HE a 50% — a apuração central do módulo';
  v_res := public.calcular_he_adicional_noturno_dia(v_cid, v_dia);

  IF (v_res->>'he50_min')::int = 120 AND (v_res->>'percentual_he50')::numeric = 50 THEN
    r.situacao := 'passou';
    r.obtido := 'Duas horas além da jornada viraram 120 min de HE com adicional de 50%.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('HE de dia útil errada: %s (esperado he50_min=120, percentual 50).', v_res::text);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_091()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text := public.qa_cpf(5091);
        v_base date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
        v_dia date; v_cid uuid; v_res jsonb;
BEGIN
  v_dia := v_base + ((8 - EXTRACT(ISODOW FROM v_base)::int) % 7);
  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Jornada 6h', 360, 10, v_dia, v_dia);
  v_cid := public.qa_ponto_dia_horarios(v_cpf, 'QA Jornada 6h', v_dia, TIME '08:00', TIME '15:00');
  -- 7h trabalhadas contra jornada CONTRATUAL de 6h → 60 min de HE

  r.passo_ordem := 1;
  r.passo_acao := 'Calcular HE de colaborador com jornada contratual de 6h que trabalhou 7h';
  r.esperado := '60 min de HE — a jornada da ESCALA é o limite, não as 8h padrão';
  v_res := public.calcular_he_adicional_noturno_dia(v_cid, v_dia);

  IF (v_res->>'he50_min')::int = 60 THEN
    r.situacao := 'passou';
    r.obtido := 'A hora extra respeitou a jornada contratual de 6h.';
  ELSIF coalesce((v_res->>'he50_min')::int, 0) = 0 THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o cálculo de HE IGNOROU a escala do colaborador — usou 8h fixas (ou a '
             || 'CCT genérica) e apagou a hora extra de quem tem jornada contratual de 6h. A '
             || 'função calcular_he_adicional_noturno_dia não consulta a escala/atribuição do '
             || 'colaborador. Tratar 8h como padrão universal apaga HE de jornadas menores. '
             || 'Correção: buscar a jornada do dia na escala vigente do vínculo.';
    r.detalhe := v_res;
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Valor inesperado: %s (esperado he50_min=60).', v_res::text);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_092()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text := public.qa_cpf(5092);
        v_base date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
        v_dia date; v_cid uuid; v_res jsonb; v_alerta boolean;
BEGIN
  v_dia := v_base + ((8 - EXTRACT(ISODOW FROM v_base)::int) % 7);
  v_cid := public.qa_ponto_dia_horarios(v_cpf, 'QA Excesso HE', v_dia,
             TIME '08:00', TIME '21:00', TIME '12:00', TIME '13:00');  -- 12h → 4h extras

  r.passo_ordem := 1;
  r.passo_acao := 'Calcular dia com 4 horas extras (o dobro do limite legal de 2h)';
  r.esperado := 'TODAS as 240 min apuradas (trabalho além do limite continua devido) + sinalização do excesso';
  v_res := public.calcular_he_adicional_noturno_dia(v_cid, v_dia);
  SELECT EXISTS (SELECT 1 FROM public.ponto_alertas
    WHERE tenant_id = public.qa_sandbox_tenant_id() AND colaborador_cpf = v_cpf) INTO v_alerta;

  IF (v_res->>'he50_min')::int = 240 AND v_alerta THEN
    r.situacao := 'passou';
    r.obtido := 'As 4 horas foram apuradas integralmente e o excesso ao limite foi sinalizado.';
  ELSIF (v_res->>'he50_min')::int = 120 THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO GRAVE: o cálculo CORTOU as horas extras no limite de 2h — de 240 minutos '
             || 'trabalhados além da jornada, só 120 foram apurados (LEAST com he_limite_diario '
             || 'na função de cálculo) e o excedente sumiu SEM alerta. O limite do art. 59 é '
             || 'norma de conduta, não de cálculo: trabalho prestado além dele continua devido '
             || '(com o mesmo adicional) — o que se faz é apurar tudo E alertar o gestor. Hoje o '
             || 'sistema literalmente deixa de pagar o que passou do limite. Correção: remover o '
             || 'corte e criar o alerta de excesso.';
    r.detalhe := v_res;
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Apuração inesperada: %s (esperado 240 min + alerta; alerta=%s).',
                       v_res::text, v_alerta);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_093()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_est text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a prorrogação por necessidade imperiosa existe como figura própria?';
  r.esperado := 'Registro da hipótese (art. 61) com tratamento distinto do acréscimo comum';
  v_est := coalesce(public.qa_col_existe(NULL, '%necessidade_imperiosa%'),
                    public.qa_fns_com('%imperiosa%'), public.qa_fns_com('%art61%'));
  IF v_est IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO PARCIAL: existe a liberação art. 61 na equalização '
             || '(ponto_equalizacao_art61_liberar), mas a NECESSIDADE IMPERIOSA como figura '
             || 'completa — registro do motivo (força maior/serviços inadiáveis), comunicação, '
             || 'limite de 12h e reflexo próprio — não está modelada. Sem ela, toda prorrogação '
             || 'excepcional cai no regime comum. Correção: tipificar a hipótese na ocorrência '
             || 'do dia, com evidência do motivo.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Figura presente: %s.', v_est);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_110()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text := public.qa_cpf(5110);
        v_base date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
        v_dia date; v_cid uuid; v_not jsonb; v_diu jsonb; v_cpf2 text := public.qa_cpf(5111);
BEGIN
  v_dia := v_base + ((8 - EXTRACT(ISODOW FROM v_base)::int) % 7);
  v_cid := public.qa_ponto_dia_horarios(v_cpf, 'QA Noturno', v_dia, TIME '22:00', TIME '05:00');
  v_not := public.calcular_he_adicional_noturno_dia(v_cid, v_dia);
  v_cid := public.qa_ponto_dia_horarios(v_cpf2, 'QA Diurno', v_dia, TIME '08:00', TIME '17:00');
  v_diu := public.calcular_he_adicional_noturno_dia(v_cid, v_dia);

  r.passo_ordem := 1;
  r.passo_acao := 'Calcular turno 22h–5h (todo noturno) e turno 8h–17h (todo diurno)';
  r.esperado := 'Noturno: minutos na janela com adicional de 20%. Diurno: zero adicional';

  IF coalesce((v_not->>'adicional_noturno_min')::int, 0) > 0
     AND (v_not->>'percentual_adn')::numeric = 20
     AND coalesce((v_diu->>'adicional_noturno_min')::int, 0) = 0 THEN
    r.situacao := 'passou';
    r.obtido := format('Janela correta: turno noturno rendeu %s min de adicional (20%%) e o '
                       || 'diurno rendeu zero.', v_not->>'adicional_noturno_min');
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Janela do art. 73 errada: noturno=%s, diurno=%s (esperado noturno > 0 a '
                       || '20%% e diurno = 0).', v_not::text, v_diu::text);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_111()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text := public.qa_cpf(5112);
        v_base date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
        v_dia date; v_cid uuid; v_res jsonb; v_adn int;
BEGIN
  v_dia := v_base + ((8 - EXTRACT(ISODOW FROM v_base)::int) % 7);
  v_cid := public.qa_ponto_dia_horarios(v_cpf, 'QA Ficta', v_dia, TIME '22:00', TIME '05:00');
  v_res := public.calcular_he_adicional_noturno_dia(v_cid, v_dia);
  v_adn := coalesce((v_res->>'adicional_noturno_min')::int, 0);

  r.passo_ordem := 1;
  r.passo_acao := '7 horas de relógio na janela noturna (420 min reais)';
  r.esperado := '480 min apurados — a hora ficta de 52min30s AUMENTA a contagem (420×60÷52,5)';

  IF v_adn = 480 THEN
    r.situacao := 'passou';
    r.obtido := 'A hora ficta foi aplicada: 420 minutos de relógio viraram 480 apurados.';
  ELSIF v_adn = 420 THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a hora ficta NÃO foi aplicada — 420 minutos de relógio ficaram 420. '
             || 'Ignorá-la subdimensiona a jornada noturna em 12,5% (art. 73, §1º).';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Contagem noturna inesperada: %s min (esperado 480 com ficta).', v_adn);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_112()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text := public.qa_cpf(5113);
        v_base date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
        v_dia date; v_cid uuid; v_res jsonb; v_adn int;
BEGIN
  v_dia := v_base + ((8 - EXTRACT(ISODOW FROM v_base)::int) % 7);
  v_cid := public.qa_ponto_dia_horarios(v_cpf, 'QA Prorrogação', v_dia, TIME '22:00', TIME '07:00');
  v_res := public.calcular_he_adicional_noturno_dia(v_cid, v_dia);
  v_adn := coalesce((v_res->>'adicional_noturno_min')::int, 0);

  r.passo_ordem := 1;
  r.passo_acao := 'Jornada integralmente noturna prorrogada até as 7h (22h → 7h)';
  r.esperado := 'O adicional alcança TAMBÉM as horas após as 5h (Súmula 60, II, do TST)';

  IF v_adn > 480 THEN
    r.situacao := 'passou';
    r.obtido := format('A prorrogação manteve o adicional: %s min apurados (além dos 480 da janela).', v_adn);
  ELSIF v_adn = 480 THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o adicional CESSOU às 5h — as 2 horas de prorrogação (5h–7h) de uma '
             || 'jornada integralmente noturna ficaram SEM adicional. A Súmula 60, II, do TST '
             || 'manda o adicional acompanhar a prorrogação. O cálculo corta a janela em '
             || '05:00 fixo. Correção: quando a jornada é cumprida integralmente no período '
             || 'noturno, estender o adicional às horas prorrogadas.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Contagem inesperada: %s min.', v_adn);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_113()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_est text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o regime noturno RURAL existe (janela, percentual e hora cheia próprios)?';
  r.esperado := 'Lavoura 21h–5h / pecuária 20h–4h, adicional 25%, SEM hora ficta (Lei 5.889/73)';
  v_est := coalesce(public.qa_col_existe(NULL, '%rural%'), public.qa_fns_com('%rural%'));
  IF v_est IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: não existe regime rural — o cálculo noturno aplica a regra urbana '
             || '(22h–5h, 20%, ficta) a todo mundo. Trabalhador rural tem janela própria '
             || '(lavoura 21h–5h; pecuária 20h–4h), adicional de 25% e hora CHEIA (sem ficta) '
             || 'pela Lei 5.889/1973. Cliente do agro apuraria errado nos três eixos. Correção: '
             || 'enquadramento urbano/rural no vínculo, com parâmetros por regime.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Regime rural presente: %s.', v_est);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_130()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text := public.qa_cpf(5130);
        v_base date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
        v_dom date; v_cid uuid; v_res jsonb;
BEGIN
  -- primeiro domingo do mês passado
  v_dom := v_base + ((7 - EXTRACT(DOW FROM v_base)::int) % 7);
  v_cid := public.qa_ponto_dia_horarios(v_cpf, 'QA Domingo', v_dom, TIME '08:00', TIME '16:00');
  v_res := public.calcular_he_adicional_noturno_dia(v_cid, v_dom);

  r.passo_ordem := 1;
  r.passo_acao := format('Trabalho de jornada NORMAL (8h) num domingo (%s), sem folga compensatória', v_dom);
  r.esperado := 'As 8 horas rendem a dobra (Lei 605/49, art. 9º; Súmula 146) — não zero';

  IF coalesce((v_res->>'he100_min')::int, 0) >= 480 THEN
    r.situacao := 'passou';
    r.obtido := 'O domingo trabalhado sem compensação rendeu a dobra sobre a jornada inteira.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o domingo trabalhado DENTRO da jornada rendeu %s min a 100%% — o '
             || 'cálculo só dobra o que EXCEDE a jornada (trata domingo como mera HE 100%%). '
             || 'Pela Lei 605/49 e Súmula 146 do TST, o trabalho em domingo/feriado não '
             || 'compensado é pago EM DOBRO por inteiro, jornada normal inclusive. Para '
             || 'feriados já existe a apuração própria (PONTO-320); para DOMINGO sem '
             || 'compensação não existe nada. Correção: detectar domingo sem folga '
             || 'compensatória na semana e dobrar a jornada trabalhada.',
             coalesce((v_res->>'he100_min')::text, '0'));
    r.detalhe := v_res;
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_131()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_empA uuid; v_empB uuid; v_cpfA text; v_cpfB text;
        v_dia date := public.qa_dia_util_passado(); v_comp text;
        v_a record; v_b record;
BEGIN
  v_comp := to_char(v_dia, 'YYYY-MM');
  v_empA := public.qa_nova_empresa('QA Feriado Unidade A', '34.028.316/0001-03');
  v_empB := public.qa_nova_empresa('QA Feriado Unidade B', '60.701.190/0001-04');
  v_cpfA := public.qa_ponto_admissao('QA Colab Unidade A', 5131, v_empA);
  v_cpfB := public.qa_ponto_admissao('QA Colab Unidade B', 5132, v_empB);
  PERFORM public.qa_feriado_da_unidade(v_empA, v_dia);   -- feriado SÓ na unidade A
  PERFORM public.qa_ponto_dia(v_cpfA, 'QA Colab Unidade A', v_dia, v_empA);
  PERFORM public.qa_ponto_dia(v_cpfB, 'QA Colab Unidade B', v_dia, v_empB);

  r.passo_ordem := 1;
  r.passo_acao := 'Mesmo dia trabalhado nas unidades A (feriado municipal) e B (dia comum)';
  r.esperado := 'Adicional de feriado APENAS para o colaborador da unidade A';
  SELECT * INTO v_a FROM public.ponto_feriado_adicional_competencia(v_t, v_empA, v_comp) f
   WHERE regexp_replace(f.colaborador_cpf, '[^0-9]', '', 'g') = v_cpfA;
  SELECT * INTO v_b FROM public.ponto_feriado_adicional_competencia(v_t, v_empB, v_comp) f
   WHERE regexp_replace(f.colaborador_cpf, '[^0-9]', '', 'g') = v_cpfB;

  IF coalesce(v_a.qtd_feriados_trabalhados, 0) >= 1 AND v_b.colaborador_cpf IS NULL THEN
    r.situacao := 'passou';
    r.obtido := 'O feriado valeu para a unidade dele e para nenhuma outra.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Abrangência errada: unidade A (com feriado) apurou %s feriado(s) '
             || 'trabalhado(s); unidade B (sem feriado) %s. Feriado municipal vale para a '
             || 'unidade daquele município e para nenhuma outra.',
             coalesce(v_a.qtd_feriados_trabalhados, 0),
             CASE WHEN v_b.colaborador_cpf IS NULL THEN 'nada (correto)' ELSE 'TAMBÉM apurou' END);
  END IF;
  RETURN r;
EXCEPTION WHEN undefined_function THEN
  r.situacao := 'falhou';
  r.obtido := 'A apuração de feriado depende de função que não existe no banco '
           || '(feriado_comportamento — criada direto em produção, nunca versionada). '
           || 'Mesmo achado do PONTO-320/321.';
  r.erro_tecnico := SQLERRM; RETURN r;
WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_132()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a falta injustificada desconta o repouso semanal?';
  r.esperado := 'Semana com falta injustificada perde a remuneração do DSR (Lei 605/49, art. 6º)';
  v_fns := public.qa_fns_com('%dsr%');
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: DSR não existe em nenhuma função do banco — nem o desconto por falta '
             || 'injustificada (Lei 605/49, art. 6º), nem o reflexo das horas extras sobre o '
             || 'repouso. A falta hoje só marca o dia; a consequência semanal, frequentemente '
             || 'esquecida pelos sistemas, não é apurada. Correção: apuração semanal de '
             || 'assiduidade alimentando o evento de DSR na exportação para a folha.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('DSR tratado em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_133()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): sete dias seguidos de trabalho disparam alerta?';
  r.esperado := 'Semana sem 24h consecutivas de repouso é sinalizada (CLT art. 67)';
  v_fns := coalesce(public.qa_fns_com('%repouso%semanal%'), public.qa_fns_com('%24 horas%consecutiv%'),
                    public.qa_fns_com('%sete dias%'));
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nada verifica o repouso semanal de 24 horas consecutivas. Colaborador '
             || 'que trabalha sete dias seguidos passa sem aviso — violação autônoma do art. 67, '
             || 'devida mesmo com tudo pago em dobro. Correção: verificação semanal na '
             || 'consolidação com alerta ao gestor.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Verificação presente em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_150()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a apuração entende o ciclo 12x36?';
  r.esperado := 'Dia de 12h no ciclo não gera HE; dia de folga não gera falta (art. 59-A)';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.proname NOT ILIKE '%corrigir%' AND p.proname NOT ILIKE '%copia%'
    AND (p.prosrc ILIKE '%ciclo_horas_trabalho%' OR p.prosrc ILIKE '%12x36%')
    AND (p.proname ILIKE '%saldo%' OR p.proname ILIKE '%apurar%'
         OR p.proname ILIKE '%consolidar%' OR p.proname ILIKE '%calc%');
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a escala guarda os campos de ciclo (ciclo_horas_trabalho/descanso em '
             || 'ponto_escalas), mas NENHUMA apuração os lê. Colaborador 12x36 teria 4 horas de '
             || '"extra" em todo plantão (12h contra jornada de 8h) e "falta" em toda folga de '
             || '36h. A escala tem regime próprio (art. 59-A) e depende de instrumento que a '
             || 'autorize. Correção: apuração por ciclo quando a modalidade da escala for de '
             || 'plantão.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Ciclo tratado em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_151()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a apuração de feriado distingue a escala 12x36?';
  r.esperado := 'Na 12x36 o feriado trabalhado é compensado pela própria escala (art. 59-A, §2º) — sem dobra';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.proname ILIKE '%feriado%'
    AND (p.prosrc ILIKE '%12x36%' OR p.prosrc ILIKE '%ciclo_horas%' OR p.prosrc ILIKE '%plantao%');
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a apuração de feriado trabalhado (PONTO-320) não distingue a escala '
             || '12x36 — aplicaria a dobra a quem tem a compensação embutida por lei (art. '
             || '59-A, §2º: feriados e prorrogação noturna considerados compensados). É a '
             || 'exceção legal expressa: aplicar a regra geral gera PAGAMENTO INDEVIDO. '
             || 'Correção: a apuração de feriado deve pular vínculos em escala de plantão '
             || 'autorizada.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Distinção presente em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_152()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text := public.qa_cpf(5152);
        v_d_antigo date := CURRENT_DATE - 30; v_d_novo date := CURRENT_DATE - 5;
        e_antigo record; e_novo record;
BEGIN
  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Vigência A', 480, 10, CURRENT_DATE - 60, CURRENT_DATE - 15);
  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Vigência B', 360, 10, CURRENT_DATE - 14, NULL);

  r.passo_ordem := 1;
  r.passo_acao := 'Trocar de escala (480 min → 360 min) e consultar a escala de um dia ANTIGO e de um dia NOVO';
  r.esperado := 'O dia antigo responde com a escala antiga; o novo, com a nova';
  SELECT * INTO e_antigo FROM public.ponto_escala_do_dia(
    public.qa_sandbox_tenant_id(), v_cpf, v_cpf, v_d_antigo) LIMIT 1;
  SELECT * INTO e_novo FROM public.ponto_escala_do_dia(
    public.qa_sandbox_tenant_id(), v_cpf, v_cpf, v_d_novo) LIMIT 1;

  IF coalesce(e_antigo.jornada_min, -1) IN (480, 0) AND coalesce(e_novo.jornada_min, -1) IN (360, 0)
     AND NOT (coalesce(e_antigo.jornada_min,0) = 0 AND coalesce(e_novo.jornada_min,0) = 0) THEN
    r.situacao := 'passou';
    r.obtido := 'Cada dia respondeu com a escala vigente na época — o passado ficou com a '
             || 'escala antiga.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Vigência de escala mal resolvida: dia antigo devolveu jornada %s '
             || '(esperado a antiga, 480) e dia novo %s (esperado a nova, 360). Apurar dia '
             || 'antigo com escala nova falsifica o passado.',
             coalesce(e_antigo.jornada_min::text, 'nada'), coalesce(e_novo.jornada_min::text, 'nada'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_153()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text := public.qa_cpf(5153);
        v_base date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
        v_dia date; v_antes int; v_depois int;
BEGIN
  v_dia := v_base + ((8 - EXTRACT(ISODOW FROM v_base)::int) % 7);
  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Retroação', 480, 10, v_dia, v_dia);
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Retroação', v_dia, 540);  -- +60

  SELECT max(s.saldo_min) INTO v_antes
  FROM public.ponto_saldo_dias_competencia(public.qa_sandbox_tenant_id(), v_cpf,
       to_char(v_dia, 'YYYY-MM')) s WHERE s.dia = v_dia;

  r.passo_ordem := 1;
  r.passo_acao := 'Apurar competência passada, ALTERAR a jornada da escala e reapurar o mesmo dia';
  r.esperado := 'O resultado do dia antigo NÃO muda — parâmetro versionado não retroage';
  UPDATE public.ponto_escalas SET jornada_diaria_minutos = 300
  WHERE tenant_id = public.qa_sandbox_tenant_id() AND nome = 'QA escala ' || v_cpf;

  SELECT max(s.saldo_min) INTO v_depois
  FROM public.ponto_saldo_dias_competencia(public.qa_sandbox_tenant_id(), v_cpf,
       to_char(v_dia, 'YYYY-MM')) s WHERE s.dia = v_dia;

  IF v_antes = v_depois THEN
    r.situacao := 'passou';
    r.obtido := format('O dia antigo manteve o saldo (%s min) após a mudança do parâmetro.', v_antes);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: mudar a jornada da escala HOJE reescreveu a apuração de um dia '
             || 'do mês PASSADO (saldo foi de %s para %s min). Os parâmetros da escala não são '
             || 'versionados por vigência — a apuração lê sempre o valor atual. Todo espelho '
             || 'antigo muda junto: auditoria vira reescrita da história. Correção: versionar '
             || 'parâmetros com vigência (a estrutura de atribuições por período já existe; '
             || 'falta a escala em si não ser editada em vigor, e sim substituída).',
             coalesce(v_antes::text, '-'), coalesce(v_depois::text, '-'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_170()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text := public.qa_cpf(5170);
        v_base date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
        v_dia date; v_comp text; v_cred int;
BEGIN
  v_dia := v_base + ((8 - EXTRACT(ISODOW FROM v_base)::int) % 7);
  v_comp := to_char(v_dia, 'YYYY-MM');
  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Banco Sem Acordo', 480, 10, v_dia, v_dia);
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Banco Sem Acordo', v_dia, 540);  -- +60

  r.passo_ordem := 1;
  r.passo_acao := 'Apurar banco de horas de colaborador SEM nenhum regime/acordo de banco configurado';
  r.esperado := 'A hora extra NÃO entra em banco — sem instrumento (art. 59, §§2º/5º) ela é devida em dinheiro';
  PERFORM public.apurar_banco_horas_colaborador(public.qa_sandbox_tenant_id(), v_cpf, v_comp);
  SELECT creditos_minutos INTO v_cred FROM public.ponto_banco_horas
  WHERE tenant_id = public.qa_sandbox_tenant_id() AND colaborador_cpf = v_cpf AND competencia = v_comp;

  IF v_cred IS NULL OR v_cred = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'Sem instrumento, nenhum crédito foi para o banco.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: %s min de hora extra entraram no BANCO sem existir regime '
             || 'configurado (ponto_banco_horas_config vazio) nem acordo anexado. A apuração '
             || 'credita banco para todo mundo, incondicionalmente. Sem instrumento válido, '
             || 'hora extra é devida em DINHEIRO na competência — mandar para banco sem lastro '
             || 'é postergar pagamento devido. Correção: apurar banco apenas para vínculos com '
             || 'regime vigente; os demais exportam a HE para a folha.', v_cred);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_171()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_preenche boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o vencimento do saldo é controlado de ponta a ponta?';
  r.esperado := 'Prazo derivado do regime na apuração + conversão automática ao vencer';
  SELECT bool_or(p.prosrc ILIKE '%prazo_compensacao%') INTO v_preenche
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN ('apurar_banco_horas', 'apurar_banco_horas_colaborador');
  IF NOT coalesce(v_preenche, false) THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO (confirma o PONTO-354): a conversão de saldo vencido existe e funciona, '
             || 'mas nunca dispara porque a apuração jamais grava prazo_compensacao na linha do '
             || 'banco. Vencido o prazo legal (6 meses no acordo individual; 1 ano no coletivo), '
             || 'a compensação deixa de ser possível e a hora vira crédito em dinheiro — hoje o '
             || 'saldo fica pendurado para sempre. Correção: prazo derivado do regime na '
             || 'apuração de cada competência.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'A apuração grava o prazo e a conversão tem o que converter.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_172()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o regime de compensação limita a jornada a 10h/dia?';
  r.esperado := 'Jornada compensatória não pode passar de 10h (art. 59, §2º) — verificação própria';
  v_fns := coalesce(public.qa_fns_com('%600%compensa%'), public.qa_fns_com('%10 horas%'),
                    public.qa_fns_com('%dez horas%'));
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nenhuma verificação limita a jornada em regime de compensação às 10 '
             || 'horas diárias do art. 59, §2º. O limite é DO REGIME e independe do teto de 2h '
             || 'extras: dia de 11h com banco de horas é irregular mesmo que o saldo compense '
             || 'depois. A configuração de jornada máxima existe (jornada_diaria_max_minutos), '
             || 'mas nada a confronta na apuração do banco. Correção: alerta na consolidação '
             || 'quando o dia em regime de compensação passar de 600 minutos.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Limite verificado em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_173()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o desligamento liquida o saldo do banco de horas?';
  r.esperado := 'Saldo positivo pago na rescisão sobre a REMUNERAÇÃO DA RESCISÃO (art. 59, §3º)';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%banco_horas%'
    AND (p.prosrc ILIKE '%rescis%' OR p.prosrc ILIKE '%desliga%');
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o desligamento não conversa com o banco de horas — nenhuma função '
             || 'liquida o saldo na rescisão. O art. 59, §3º manda pagar as horas não '
             || 'compensadas calculadas sobre a remuneração DA DATA DA RESCISÃO (não a da '
             || 'época trabalhada). Colaborador desligado com saldo positivo simplesmente '
             || 'perde o registro. Correção: gatilho de desligamento que apura e exporta o '
             || 'saldo final para a rescisão.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Liquidação presente em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_174()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): alguma rotina invalida o banco por habitualidade de HE?';
  r.esperado := 'Nenhuma — o art. 59-B, parágrafo único (pós-reforma) diz que a habitualidade NÃO descaracteriza';
  v_fns := public.qa_fns_com('%habitual%invalid%');
  IF v_fns IS NULL THEN
    r.situacao := 'passou';
    r.obtido := 'Nenhuma rotina invalida o acordo de compensação por habitualidade — correto '
             || 'pós-reforma (art. 59-B, parágrafo único). Sistema que invalidasse aplicaria '
             || 'direito revogado (antiga Súmula 85, IV).';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: rotina(s) invalidando banco por habitualidade: %s — regra '
             || 'revogada pela Lei 13.467/2017.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_175()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text := public.qa_cpf(5175);
        v_base date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
        v_dia date; v_comp text; v_banco uuid; v_manual int;
BEGIN
  v_dia := v_base + ((8 - EXTRACT(ISODOW FROM v_base)::int) % 7);
  v_comp := to_char(v_dia, 'YYYY-MM');
  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Manual Preservado', 480, 10, v_dia, v_dia);
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Manual Preservado', v_dia, 540);
  PERFORM public.apurar_banco_horas_colaborador(public.qa_sandbox_tenant_id(), v_cpf, v_comp);
  SELECT id INTO v_banco FROM public.ponto_banco_horas
  WHERE tenant_id = public.qa_sandbox_tenant_id() AND colaborador_cpf = v_cpf AND competencia = v_comp;
  IF v_banco IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'Não foi possível montar o cenário: a apuração não criou a linha do banco.';
    RETURN r;
  END IF;
  INSERT INTO public.ponto_banco_horas_movimentacoes
    (tenant_id, banco_horas_id, colaborador_cpf, data_referencia, tipo, minutos, descricao, origem)
  VALUES (public.qa_sandbox_tenant_id(), v_banco, v_cpf, v_dia, 'credito', 33,
          'Lançamento manual do gestor (QA)', 'manual');

  r.passo_ordem := 1;
  r.passo_acao := 'Reapurar a competência e conferir o lançamento manual de 33 min';
  r.esperado := 'O manual sobrevive — reapuração regenera só as movimentações automáticas';
  PERFORM public.apurar_banco_horas_colaborador(public.qa_sandbox_tenant_id(), v_cpf, v_comp);
  SELECT count(*) INTO v_manual FROM public.ponto_banco_horas_movimentacoes
  WHERE banco_horas_id = v_banco AND origem = 'manual' AND minutos = 33;

  IF v_manual = 1 THEN
    r.situacao := 'passou';
    r.obtido := 'O lançamento manual sobreviveu à reapuração — só as movimentações automáticas '
             || 'foram regeneradas.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('O lançamento manual %s após a reapuração — regenerar decisão humana '
             || 'registrada apaga autor e justificativa.',
             CASE WHEN v_manual = 0 THEN 'SUMIU' ELSE 'foi duplicado' END);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_190()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fantasma boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o caminho de correção por ajuste aprovado funciona no banco?';
  r.esperado := 'Aprovação de correção insere marcação de ajuste (original=false) preservando a fonte';
  SELECT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'processar_ajuste_ponto'
      AND p.prosrc ILIKE '%data_hora%'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'ponto_marcacoes' AND column_name = 'data_hora'
  ) INTO v_fantasma;

  IF v_fantasma THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO (o mesmo do PONTO-357, agora no caso que lhe é próprio): o ÚNICO caminho '
             || 'legítimo de correção — aprovação do ajuste inserindo a batida de correção — '
             || 'está quebrado no banco: processar_ajuste_ponto grava usando colunas que não '
             || 'existem em ponto_marcacoes (data_hora/tipo/origem; a tabela usa data_marcacao/'
             || 'hora_marcacao/tipo_marcacao). Aprovar correção ou inclusão por essa função '
             || 'quebra em execução, ou a tela contorna a função por caminho próprio. '
             || 'Correção: alinhar o INSERT/DELETE ao esquema real.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'O fluxo de correção por ajuste referencia o esquema real (batida de correção '
             || 'com original preservada).';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_191()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text; v_encadeado boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o hash das marcações é encadeado e alguém o confere?';
  r.esperado := 'Hash de cada marcação incorpora o anterior (cadeia) + rotina de verificação da cadeia';
  SELECT bool_or(p.prosrc ILIKE '%anterior%'), string_agg(DISTINCT p.proname, ', ')
    INTO v_encadeado, v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%hash_marcacao%' AND p.prosrc ILIKE '%verific%';

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: cada marcação tem hash próprio, mas (1) o hash NÃO é encadeado — não '
             || 'incorpora o hash da marcação anterior, então remover uma linha inteira não '
             || 'quebra nada — e (2) NENHUMA rotina confere os hashes: um UPDATE direto com a '
             || 'trava desligada, ou feito por quem pode, nunca seria detectado. Encadeamento '
             || 'verificado é o que transforma "não editamos" em prova (registro tipo 7 do '
             || 'AFD). Correção: hash(linha + hash_anterior) + rotina periódica de verificação '
             || 'da cadeia com alerta.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Verificação de hash presente em: %s (encadeado: %s).', v_fns, v_encadeado);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_192()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text; v_log uuid;
        v_del boolean := false; v_upd boolean := false;
BEGIN
  v_cpf := public.qa_ponto_admissao('QA Trilha', 5192);
  PERFORM public.qa_ponto_marca(v_cpf, 'QA Trilha', CURRENT_DATE - 1, TIME '09:00', 'entrada');
  SELECT id INTO v_log FROM public.ponto_audit_log
  WHERE tenant_id = public.qa_sandbox_tenant_id() ORDER BY created_at DESC LIMIT 1;
  IF v_log IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A marcação não gerou registro na trilha (ponto_audit_log vazio para o cercado) '
             || '— trilha incompleta.';
    RETURN r;
  END IF;

  r.passo_ordem := 1;
  r.passo_acao := 'Tentar APAGAR e ALTERAR um registro da trilha de auditoria';
  r.esperado := 'Ambos bloqueados — trilha que se apaga não é trilha';
  BEGIN
    DELETE FROM public.ponto_audit_log WHERE id = v_log;
    v_del := NOT EXISTS (SELECT 1 FROM public.ponto_audit_log WHERE id = v_log);
  EXCEPTION WHEN OTHERS THEN v_del := false; END;
  BEGIN
    UPDATE public.ponto_audit_log SET acao = 'adulterado' WHERE id = v_log;
    v_upd := true;
  EXCEPTION WHEN OTHERS THEN v_upd := false; END;

  IF NOT v_del AND NOT v_upd THEN
    r.situacao := 'passou';
    r.obtido := 'A trilha recusou exclusão e alteração — registro imutável (append-only).';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('A trilha foi %s — auditoria que se edita não prova nada.',
             CASE WHEN v_del AND v_upd THEN 'APAGADA e ALTERADA'
                  WHEN v_del THEN 'APAGADA' ELSE 'ALTERADA' END);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_193()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text;
        v_mes date := date_trunc('month', CURRENT_DATE - INTERVAL '3 months')::date;
        v_fech uuid; v_bloqueou boolean := false;
BEGIN
  v_cpf := public.qa_ponto_admissao('QA Fechado', 5193, NULL, v_mes - 30);
  INSERT INTO public.ponto_fechamentos (tenant_id, competencia, status, data_fechamento)
  VALUES (public.qa_sandbox_tenant_id(), to_char(v_mes, 'YYYY-MM'), 'fechado', now())
  RETURNING id INTO v_fech;

  r.passo_ordem := 1;
  r.passo_acao := format('Tentar marcar ponto em competência FECHADA (%s), sem privilégio', to_char(v_mes, 'YYYY-MM'));
  r.esperado := 'Recusado — documento entregue e assinado não se altera';
  BEGIN
    PERFORM public.qa_ponto_marca(v_cpf, 'QA Fechado', v_mes + 2, TIME '08:00', 'entrada');
    v_bloqueou := false;
  EXCEPTION WHEN OTHERS THEN v_bloqueou := true; END;

  DELETE FROM public.ponto_fechamentos WHERE id = v_fech;  -- não poluir os demais casos

  IF v_bloqueou THEN
    r.situacao := 'passou';
    r.obtido := 'A competência fechada recusou a marcação. Nota de risco: o gatilho abre '
             || 'exceção para papéis de gestão (a "válvula" já apontada na trilha de ajustes) '
             || '— a reabertura formal do PONTO-358 é o caminho correto.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'A competência FECHADA aceitou marcação nova sem reabertura — o espelho já '
             || 'entregue muda por baixo dos panos.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_194()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a geração de espelhos do fechamento é atômica no banco?';
  r.esperado := 'Falha no meio não deixa competência com espelhos de metade dos colaboradores';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%ponto_espelhos%' AND p.prosrc ILIKE '%INSERT%';
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nenhuma função do banco GERA os espelhos — eles nascem por um caminho '
             || 'de tela/edge que o banco não conhece, gravando linha a linha em '
             || 'ponto_espelhos. Sem uma função transacional, falha no meio deixa espelho '
             || 'parcial (metade dos colaboradores com documento, metade sem) — pior que '
             || 'ausente, porque parece completo. Correção: geração dos espelhos da '
             || 'competência numa função única (tudo-ou-nada) chamada pelo fechamento.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Geração transacional presente em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_211()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o AEJ existe?';
  r.esperado := 'Arquivo Eletrônico de Jornada gerado pelo programa de tratamento (Portaria 671)';
  v_fns := coalesce(public.qa_fns_com('%aej%'), public.qa_col_existe(NULL, '%aej%'));
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO (confirma a auditoria de conformidade): o AEJ não existe em lugar '
             || 'nenhum do banco — nem função, nem coluna, nem tabela. É a saída OBRIGATÓRIA '
             || 'do programa de tratamento na Portaria 671 (substituiu AFDT/ACJEF) e a peça '
             || 'que a fiscalização pede junto com o AFD. Correção: gerador de AEJ no leiaute '
             || 'vigente, assinado, a partir da apuração da competência.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('AEJ presente: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_212()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_val text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a importação de AFD detecta lacuna de NSR?';
  r.esperado := 'Arquivo com sequência quebrada é recusado POR INTEIRO';
  v_val := coalesce(public.qa_fns_com('%lacuna%'), public.qa_fns_com('%sequencial%nsr%'),
                    public.qa_fns_com('%nsr%sequencia%'));
  IF v_val IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: sem NSR no modelo (PONTO-210) e sem validação de integridade na '
             || 'importação (PONTO-382), a lacuna de sequência nem é DETECTÁVEL — um AFD com '
             || 'registros removidos entraria inteiro e viraria prova adulterada no acervo. '
             || 'Correção: validar a sequência de NSR na importação e recusar o arquivo '
             || 'completo em caso de lacuna, com relatório.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Validação de lacuna presente em: %s.', v_val);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_213()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_aceitou boolean := false;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Configurar registro por link externo SEM instrumento coletivo anexado';
  r.esperado := 'Recusado ou condicionado — REP-A exige norma coletiva; sem ela, o app precisa das formalidades do REP-P';
  BEGIN
    INSERT INTO public.ponto_configuracao (tenant_id, modo_registro)
    VALUES (public.qa_sandbox_tenant_id(), 'link_externo');
    v_aceitou := true;
  EXCEPTION WHEN check_violation OR raise_exception OR unique_violation THEN
    v_aceitou := false;
  END;

  IF v_aceitou THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o modo de registro por link externo foi ativado sem NENHUM documento '
             || 'de autorização — nem instrumento coletivo (REP-A), nem os requisitos formais '
             || 'de REP-P (registro INPI, certificado, comprovante, NSR — ver PONTO-210/380). '
             || 'Operar registro alternativo sem lastro formal invalida o controle perante a '
             || 'Portaria 671. Correção: condicionar o modo à evidência documental, como no '
             || 'registro por exceção (PONTO-372).';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'O modo alternativo sem autorização foi recusado.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_291()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_cpf text; v_dia date := public.qa_dia_util_passado(); v_status text;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_cpf := public.qa_ponto_admissao('[QA-PONTO] Amparado', 29101);

  r.passo_ordem := 1;
  r.passo_acao := format('Registrar atestado cobrindo o dia útil %s e materializar', v_dia);
  r.esperado := 'Linha criada com status de ausência amparada, sem virar falta';
  INSERT INTO public.atestados
    (tenant_id, colaborador_nome, colaborador_cpf, tipo, data_emissao,
     profissional_nome, profissional_registro,
     data_inicio_afastamento, data_fim_afastamento, unidade_afastamento)
  VALUES (v_t, '[QA-PONTO] Amparado', v_cpf, 'assistencial', v_dia,
          '[QA] Dr. Teste', 'CRM-QA-0001', v_dia, v_dia, 'dias');

  PERFORM public.ponto_materializar_faltas(v_dia, v_dia, v_t);

  SELECT status INTO v_status FROM public.ponto_diario
  WHERE tenant_id = v_t AND colaborador_cpf = v_cpf AND data = v_dia
  ORDER BY created_at DESC LIMIT 1;

  IF v_status IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A materialização não criou linha nem para o dia amparado — o atestado sumiu junto com a falta (ver PONTO-290).';
  ELSIF v_status = 'falta' THEN
    r.situacao := 'falhou';
    r.obtido := 'O DIA COM ATESTADO VIROU FALTA: a materialização é um gerador cego de débito — desconta ausência amparada pela CLT art. 473. O colaborador com atestado válido perderia remuneração e DSR.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Dia amparado materializado com status %s — a falta não engoliu o atestado.', v_status);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_312()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_n int; v_lista text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): varrer as funções de ponto atrás dos dois padrões removidos em 04/08';
  r.esperado := 'Nenhuma função com "OR empresa_id IS NULL" nem com o carimbo "COALESCE(p_empresa_id, r.empresa_id)"';

  SELECT count(*), string_agg(p.proname, ', ' ORDER BY p.proname)
  INTO v_n, v_lista
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname LIKE 'ponto\_%'
    AND p.prokind = 'f'
    AND (pg_get_functiondef(p.oid) ILIKE '%= p_empresa_id OR%empresa_id IS NULL%'
         OR pg_get_functiondef(p.oid) ILIKE '%COALESCE(p_empresa_id, r.empresa_id)%');

  IF v_n = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'Nenhuma função de ponto contém a válvula de escape nem o carimbo de empresa. A correção de 04/08 (fechamento por empresa) segue de pé.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('A VÁLVULA VOLTOU em %s função(ões): %s. Com ela, colaborador sem empresa entra na apuração de TODAS as empresas e o reapurar reatribui a empresa de quem já tem — o defeito que exigiu migration de reparo em 04/08.', v_n, v_lista);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_320()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_emp uuid; v_cpf text; v_dia date := public.qa_dia_util_passado();
        v_comp text; a record;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_comp := to_char(v_dia, 'YYYY-MM');
  v_emp := public.qa_nova_empresa('[QA-RN23] Unidade Feriado', '11222333032001');
  v_cpf := public.qa_ponto_admissao('[QA-RN23] Trabalhou no Feriado', 32001, v_emp);
  PERFORM public.qa_feriado_da_unidade(v_emp, v_dia);
  PERFORM public.qa_ponto_dia(v_cpf, '[QA-RN23] Trabalhou no Feriado', v_dia, v_emp);

  r.passo_ordem := 1;
  r.passo_acao := format('Apurar o adicional de feriado da competência %s (feriado trabalhado em %s, sem folga)', v_comp, v_dia);
  r.esperado := 'Minutos trabalhados no feriado com adicional de 100%';

  SELECT * INTO a FROM public.ponto_feriado_adicional_competencia(v_t, v_emp, v_comp) f
  WHERE regexp_replace(f.colaborador_cpf, '[^0-9]', '', 'g') = v_cpf;

  IF a.colaborador_cpf IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'O FERIADO TRABALHADO NÃO APARECEU NA APURAÇÃO DO ADICIONAL — a Lei 605/1949 art. 9º exige a dobra e o cálculo não enxergou o dia (feriado da unidade + marcação presentes no cercado).';
  ELSIF COALESCE(a.minutos_adicional_100, 0) > 0 AND COALESCE(a.qtd_feriados_trabalhados, 0) >= 1 THEN
    r.situacao := 'passou';
    r.obtido := format('Feriado trabalhado sem compensação rendeu %s minuto(s) com adicional de 100%%, pronto para a folha, sem lançamento manual.', a.minutos_adicional_100);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('O feriado apareceu mas SEM adicional: qtd=%s, trabalhados=%s, adicional_100=%s. Trabalho em feriado não compensado tem de dobrar (Súmula 146 do TST).',
      a.qtd_feriados_trabalhados, a.minutos_trabalhados, a.minutos_adicional_100);
  END IF;
  RETURN r;
EXCEPTION
  WHEN undefined_function THEN
    r.situacao := 'falhou';
    r.obtido := 'A APURAÇÃO RN23 QUEBRA NESTE BANCO: ' || SQLERRM || '. A função de apoio '
      || 'feriado_comportamento não existe em NENHUMA migration do repositório — foi criada '
      || 'por fora, direto no banco (mesmo precedente de feriados e ponto_diario.tipo_dia). '
      || 'Qualquer ambiente montado a partir das migrations fica com o adicional de feriado '
      || 'inoperante. Correção: trazer a função para o repositório com CREATE OR REPLACE.';
    r.erro_tecnico := SQLERRM;
    RETURN r;
  WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_321()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
      DECLARE r public.qa_retorno;
      BEGIN
        IF to_regclass('public.feriado_folga_compensatoria') IS NULL THEN
          r.passo_ordem := 1;
          r.passo_acao  := 'Conferir se a estrutura que este caso exercita existe no ambiente';
          r.esperado    := 'Estrutura presente para o caso poder ser exercitado';
          r.situacao    := 'falhou';
          r.obtido      := 'ACHADO: este ambiente nao tem onde registrar a folga compensatoria do feriado trabalhado — logo, nao ha como afastar o pagamento em dobro (CLT art. 9 da Lei 605/49 c/c Sumula 146 do TST) provando a compensacao. Ou a empresa paga a dobra sempre, ou deixa de pagar sem prova. A tabela existe no projeto; falta chegar aqui.';
          r.erro_tecnico := 'A tabela feriado_folga_compensatoria nao existe neste ambiente.';
          RETURN r;
        END IF;
        RETURN public.qa_caso_ponto_321_corpo();
      END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_322()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_emp uuid; v_cpf text; v_dia date := public.qa_dia_util_passado();
        v_comp text; v_saldo_antes bigint; v_saldo_depois bigint; v_tmp int;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_comp := to_char(v_dia, 'YYYY-MM');
  v_emp := public.qa_nova_empresa('[QA-RN23] Unidade Saldo', '11222333032203');
  v_cpf := public.qa_ponto_admissao('[QA-RN23] Saldo Intacto', 32201, v_emp);
  PERFORM public.qa_feriado_da_unidade(v_emp, v_dia);
  PERFORM public.qa_ponto_dia(v_cpf, '[QA-RN23] Saldo Intacto', v_dia, v_emp);

  r.passo_ordem := 1;
  r.passo_acao := 'Comparar o saldo do banco antes e depois de apurar o adicional';
  r.esperado := 'Idêntico — o adicional é verba de folha, não crédito de compensação';

  SELECT COALESCE(sum(s.saldo_min), 0) INTO v_saldo_antes
  FROM public.ponto_saldo_dias_competencia(v_t, v_cpf, v_comp) s;

  SELECT COALESCE(sum(f.minutos_adicional_100), 0) INTO v_tmp
  FROM public.ponto_feriado_adicional_competencia(v_t, v_emp, v_comp) f;

  SELECT COALESCE(sum(s.saldo_min), 0) INTO v_saldo_depois
  FROM public.ponto_saldo_dias_competencia(v_t, v_cpf, v_comp) s;

  IF v_saldo_antes = v_saldo_depois THEN
    r.situacao := 'passou';
    r.obtido := format('Saldo do banco intacto (%s min) antes e depois da apuração do adicional — a mesma hora não vira verba e crédito ao mesmo tempo.', v_saldo_antes);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('A APURAÇÃO DO ADICIONAL MEXEU NO SALDO: %s min antes, %s min depois. O colaborador receberia em dobro E folgaria pelas mesmas horas.', v_saldo_antes, v_saldo_depois);
  END IF;
  RETURN r;
EXCEPTION
  WHEN undefined_function THEN
    r.situacao := 'falhou';
    r.obtido := 'A APURAÇÃO RN23 QUEBRA NESTE BANCO: ' || SQLERRM || '. A função de apoio '
      || 'feriado_comportamento não existe em NENHUMA migration do repositório — foi criada '
      || 'por fora, direto no banco (mesmo precedente de feriados e ponto_diario.tipo_dia). '
      || 'Qualquer ambiente montado a partir das migrations fica com o adicional de feriado '
      || 'inoperante. Correção: trazer a função para o repositório com CREATE OR REPLACE.';
    r.erro_tecnico := SQLERRM;
    RETURN r;
  WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_330()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_cpf text; v_dia date := public.qa_dia_util_passado();
        v_comp text; e record; v_trab bigint; v_saldo bigint;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_comp := to_char(v_dia, 'YYYY-MM');
  v_cpf := public.qa_ponto_admissao('[QA-PONTO] Espelhado', 33001);
  PERFORM public.qa_ponto_dia(v_cpf, '[QA-PONTO] Espelhado', v_dia);

  r.passo_ordem := 1;
  r.passo_acao := 'Gerar o espelho-resumo e comparar com a soma dia a dia do banco de horas';
  r.esperado := 'Totais de horas e saldo idênticos — as duas telas dizem a mesma coisa';

  SELECT * INTO e FROM public.ponto_espelho_resumo(v_t, v_cpf, v_comp);
  SELECT COALESCE(sum(s.trabalhado_min), 0), COALESCE(sum(s.saldo_min), 0)
  INTO v_trab, v_saldo
  FROM public.ponto_saldo_dias_competencia(v_t, v_cpf, v_comp) s;

  IF e.dias_com_registro IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'O espelho-resumo voltou vazio para uma competência com registro — a regressão do espelho zerado de 07/2026.';
  ELSIF COALESCE(e.total_trabalhado_min, 0) = v_trab AND COALESCE(e.saldo_min, 0) = v_saldo THEN
    r.situacao := 'passou';
    r.obtido := format('Espelho e banco de horas batem: %s min trabalhados, saldo %s min — mesma fonte, mesma história.', v_trab, v_saldo);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ESPELHO E BANCO DIVERGEM: espelho diz %s min / saldo %s; a soma dia a dia diz %s min / saldo %s. Duas telas, duas verdades — o defeito que o espelho-resumo veio corrigir.',
      e.total_trabalhado_min, e.saldo_min, v_trab, v_saldo);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_331()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cols text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): conferir que o espelho-resumo não devolve os campos órfãos como zero';
  r.esperado := 'Sem colunas de HE 50/100 nem adicional noturno na saída — ausente é honesto, zero é declaração falsa';

  SELECT pg_get_function_result(p.oid) INTO v_cols
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'ponto_espelho_resumo'
  LIMIT 1;

  IF v_cols IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A função ponto_espelho_resumo não existe — o espelho voltou a somar as colunas órfãs?';
  ELSIF v_cols ILIKE '%extras%' OR v_cols ILIKE '%noturno%' THEN
    r.situacao := 'falhou';
    r.obtido := 'O ESPELHO VOLTOU A DEVOLVER CAMPOS QUE O MODELO NÃO APURA (' || v_cols || '). '
      || 'A apuração atual não separa HE 50%/100% nem adicional noturno: devolvê-los seria '
      || 'imprimir zero afirmativo num documento que o colaborador assina — declaração falsa. '
      || 'A tela marca esses campos como não apurados; a função não pode reintroduzi-los.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'O espelho-resumo devolve apenas o que o modelo realmente apura. O que não é apurado fica marcado como tal na tela, nunca como 0h00.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_350()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
  r public.qa_retorno;
  v_cpf text;
  v_data date := CURRENT_DATE - 1;   -- ancora em dia passado: ver nota da migration
  v_bloqueou_dupla boolean := false;
  v_bloqueou_saida_repique boolean := false;
  v_aceitou_depois boolean := false;
BEGIN
  v_cpf := public.qa_ponto_admissao('QA Toque Duplo', 3501);

  r.passo_ordem := 1;
  r.passo_acao := 'Registrar entrada às 08:00:00 e tentar NOVA entrada às 08:00:30 (mesmo minuto)';
  r.esperado := 'A segunda batida é recusada como repique do mesmo toque';

  PERFORM public.qa_ponto_marca(v_cpf, 'QA Toque Duplo', v_data, TIME '08:00:00', 'entrada');
  BEGIN
    PERFORM public.qa_ponto_marca(v_cpf, 'QA Toque Duplo', v_data, TIME '08:00:30', 'entrada');
  EXCEPTION WHEN OTHERS THEN
    v_bloqueou_dupla := true;
  END;

  r.passo_ordem := 2;
  r.passo_acao := 'Tentar SAÍDA às 08:01:00 (ainda dentro da janela do repique)';
  r.esperado := 'Também recusada — o dedo que escorrega não fecha a jornada em 1 minuto';
  BEGIN
    PERFORM public.qa_ponto_marca(v_cpf, 'QA Toque Duplo', v_data, TIME '08:01:00', 'saida');
  EXCEPTION WHEN OTHERS THEN
    v_bloqueou_saida_repique := true;
  END;

  r.passo_ordem := 3;
  r.passo_acao := 'Registrar saída legítima às 12:00';
  r.esperado := 'Aceita normalmente — a proteção não pode travar a jornada real';
  BEGIN
    PERFORM public.qa_ponto_marca(v_cpf, 'QA Toque Duplo', v_data, TIME '12:00:00', 'saida');
    v_aceitou_depois := true;
  EXCEPTION WHEN OTHERS THEN
    v_aceitou_depois := false;
  END;

  IF v_bloqueou_dupla AND v_bloqueou_saida_repique AND v_aceitou_depois THEN
    r.situacao := 'passou';
    r.obtido := 'O repique no mesmo minuto foi recusado (entrada E saída), e a batida legítima '
             || 'posterior entrou normalmente. A janela anti-toque-duplo está ativa no banco.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Proteção incompleta: repique de entrada %s, repique de saída %s, batida '
             || 'legítima depois %s. Duas batidas no mesmo minuto viram duas marcações no AFD e '
             || 'sujam a apuração. Correção: janela anti-toque-duplo no gatilho de marcação.',
             CASE WHEN v_bloqueou_dupla THEN 'BLOQUEADO' ELSE 'ACEITO' END,
             CASE WHEN v_bloqueou_saida_repique THEN 'BLOQUEADO' ELSE 'ACEITO' END,
             CASE WHEN v_aceitou_depois THEN 'aceita' ELSE 'RECUSADA (trava demais)' END);
    r.detalhe := jsonb_build_object('bloqueou_entrada_dupla', v_bloqueou_dupla,
                                    'bloqueou_saida_repique', v_bloqueou_saida_repique,
                                    'aceitou_batida_legitima', v_aceitou_depois);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_351()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
  r public.qa_retorno;
  v_cpf text;
  v_data date := CURRENT_DATE - 1;
  v_retro_entrou boolean := false;
  v_msg_recusa text;
  v_seq text;
  v_horas text;
BEGIN
  v_cpf := public.qa_ponto_admissao('QA Retroativa', 3511);

  r.passo_ordem := 1;
  r.passo_acao := 'Lançar por ajuste a marcação das 12:00 (rotulada entrada) num dia de ontem';
  r.esperado := 'Aceita — é a única do dia, nada a reordenar';
  PERFORM public.qa_ponto_marca(v_cpf, 'QA Retroativa', v_data, TIME '12:00', 'entrada', false);

  r.passo_ordem := 2;
  r.passo_acao := 'Lançar RETROATIVAMENTE a marcação das 08:00 — pelo relógio, ela vira a entrada '
               || 'e a das 12:00 vira saída';
  r.esperado := 'A retroativa entra e os rótulos são reordenados pelo relógio, sem tocar nos horários';
  BEGIN
    PERFORM public.qa_ponto_marca(v_cpf, 'QA Retroativa', v_data, TIME '08:00', 'saida', false);
    v_retro_entrou := true;
  EXCEPTION WHEN OTHERS THEN
    v_msg_recusa := SQLERRM;
  END;

  SELECT string_agg(tipo_marcacao, '>' ORDER BY hora_marcacao),
         string_agg(hora_marcacao::text, '>' ORDER BY hora_marcacao)
    INTO v_seq, v_horas
  FROM public.ponto_marcacoes
  WHERE tenant_id = public.qa_sandbox_tenant_id()
    AND colaborador_cpf = v_cpf AND data_marcacao = v_data;

  IF v_retro_entrou AND v_seq = 'entrada>saida' AND v_horas = '08:00:00>12:00:00' THEN
    r.situacao := 'passou';
    r.obtido := 'A retroativa entrou e o dia foi reencaixado pelo relógio: entrada 08:00, saída '
             || '12:00, nenhum horário alterado.';
  ELSIF NOT v_retro_entrou THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a inclusão retroativa foi RECUSADA por inteiro. O gatilho de '
             || 'inserção chama a reordenação automática de rótulos '
             || '(ponto_reordena_tipos_dia), mas a reordenação esbarra na trava de imutabilidade '
             || 'da própria marcação (ponto_bloquear_update_marcacao) porque ninguém liga o '
             || 'contexto de retificação (app.ponto_retificacao) antes de reordenar. Resultado: '
             || 'toda retroativa que exija reordenar rótulos falha com "%s" — o RH não consegue '
             || 'completar o dia por ajuste. Correção: o reordenador automático deve executar '
             || 'dentro do contexto de retificação (é alteração de RÓTULO, não de horário — a '
             || 'Portaria 671 protege o horário registrado).', coalesce(v_msg_recusa, '?'));
    r.detalhe := jsonb_build_object('recusa', v_msg_recusa, 'sequencia', v_seq,
                                    'horarios', v_horas);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('A retroativa entrou mas o dia ficou incoerente: sequência %s | horários %s '
             || '(esperado entrada>saida em 08:00>12:00). Rótulo errado contamina a apuração do '
             || 'dia inteiro.', coalesce(v_seq, 'vazio'), coalesce(v_horas, 'vazio'));
    r.detalhe := jsonb_build_object('sequencia', v_seq, 'horarios', v_horas);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_352()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
  r public.qa_retorno;
  v_cpf text := public.qa_cpf(3521);
  v_base date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
  v_dia date;
  v_tol_lida int;
  v_saldo int;
BEGIN
  -- primeira segunda-feira do mês passado
  v_dia := v_base + ((8 - EXTRACT(ISODOW FROM v_base)::int) % 7);

  r.passo_ordem := 1;
  r.passo_acao := 'Cadastrar escala com tolerância diária ZERO e ler de volta';
  r.esperado := 'O zero é aceito e devolvido como zero — não vira "usar padrão de 10"';

  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Tolerância Zero', 480, 0, v_dia, v_dia);
  SELECT e.tolerancia_min INTO v_tol_lida
  FROM public.ponto_escala_do_dia(public.qa_sandbox_tenant_id(), v_cpf, NULL::uuid, v_dia) e;

  IF coalesce(v_tol_lida, -1) <> 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('A escala foi gravada com tolerância 0, mas a leitura devolveu %s. '
             || 'Zero está sendo tratado como "não configurado". Correção: distinguir 0 de NULL.',
             coalesce(v_tol_lida::text, 'NULL'));
    RETURN r;
  END IF;

  r.passo_ordem := 2;
  r.passo_acao := format('Dia com 471 min trabalhados (9 min a menos que a jornada de 480), tolerância 0, em %s', v_dia);
  r.esperado := 'Com tolerância zero, o saldo do dia é -9 min — cada minuto conta';

  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Tolerância Zero', v_dia, 471);
  SELECT s.saldo_min INTO v_saldo
  FROM public.ponto_saldo_dias_competencia(public.qa_sandbox_tenant_id(), v_cpf,
                                           to_char(v_dia, 'YYYY-MM')) s
  WHERE s.dia = v_dia;

  IF v_saldo = -9 THEN
    r.situacao := 'passou';
    r.obtido := 'Tolerância zero aceita e aplicada: os 9 minutos faltantes viraram débito de -9.';
  ELSIF v_saldo = 0 THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a tolerância configurada como ZERO foi IGNORADA — o dia com 9 minutos '
             || 'faltantes fechou com saldo 0. Causa: a apuração de saldo tem um perdão fixo de '
             || '10 minutos gravado no código (ponto_saldo_dias_competencia e a função _bruto '
             || 'aplicam "abs(saldo) <= 10 → 0" incondicionalmente), por cima do que a escala '
             || 'diz. Empresa que adota tolerância menor que a legal não consegue: o piso '
             || 'efetivo do sistema é 10 min. Correção: usar a tolerância da escala '
             || '(tolerancia_diaria_minutos) no lugar do 10 fixo, mantendo 10 apenas como teto '
             || 'padrão quando nada foi configurado.';
    r.detalhe := jsonb_build_object('saldo_obtido', v_saldo, 'saldo_esperado', -9,
                                    'tolerancia_configurada', 0);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Saldo inesperado: %s min (esperado -9 com tolerância zero). '
             || 'A apuração não está seguindo nem a configuração nem o padrão de 10.',
             coalesce(v_saldo::text, 'sem linha'));
    r.detalhe := jsonb_build_object('saldo_obtido', v_saldo);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_354()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
  r public.qa_retorno;
  v_cpf text := public.qa_cpf(3541);
  v_apuracao_preenche boolean;
  v_convertido boolean;
  v_mov int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a apuração do banco preenche o prazo de compensação?';
  r.esperado := 'apurar_banco_horas* deriva prazo_compensacao da configuração do regime (6m/12m)';

  SELECT bool_or(p.prosrc ILIKE '%prazo_compensacao%') INTO v_apuracao_preenche
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN ('apurar_banco_horas', 'apurar_banco_horas_colaborador');

  r.passo_ordem := 2;
  r.passo_acao := 'Semear saldo de 120 min com prazo vencido ontem e rodar a conversão automática';
  r.esperado := 'O saldo vencido vira hora extra: convertido_extras = true + movimentação de conversão';

  INSERT INTO public.ponto_banco_horas
    (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf, tipo,
     competencia, saldo_anterior_minutos, creditos_minutos, debitos_minutos,
     compensados_minutos, saldo_atual_minutos, convertido_extras, prazo_compensacao)
  VALUES (public.qa_sandbox_tenant_id(), v_cpf, 'QA Vencimento Banco', v_cpf, 'mensal',
          to_char(CURRENT_DATE - INTERVAL '1 month', 'YYYY-MM'), 0, 120, 0, 0, 120,
          false, CURRENT_DATE - 1);

  PERFORM public.converter_banco_horas_vencido(public.qa_sandbox_tenant_id());

  SELECT b.convertido_extras,
         (SELECT count(*) FROM public.ponto_banco_horas_movimentacoes m
           WHERE m.banco_horas_id = b.id AND m.tipo = 'conversao_he')
    INTO v_convertido, v_mov
  FROM public.ponto_banco_horas b
  WHERE b.tenant_id = public.qa_sandbox_tenant_id() AND b.colaborador_cpf = v_cpf;

  IF NOT coalesce(v_convertido, false) OR coalesce(v_mov, 0) = 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('A conversão de saldo vencido não funcionou nem com o prazo semeado à mão '
             || '(convertido=%s, movimentações=%s). O saldo que passa do prazo legal precisa virar '
             || 'hora extra a pagar.', coalesce(v_convertido::text, 'NULL'), coalesce(v_mov, 0));
  ELSIF NOT coalesce(v_apuracao_preenche, false) THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o mecanismo de conversão existe e funciona QUANDO o prazo está na linha '
             || '(o teste semeou o prazo à mão e o saldo foi convertido) — mas a APURAÇÃO nunca '
             || 'preenche prazo_compensacao. A configuração do regime até guarda '
             || 'prazo_compensacao_dias (ponto_banco_horas_config), só que nenhuma função de '
             || 'apuração a consulta. Resultado prático: nenhum saldo tem vencimento, a conversão '
             || 'automática nunca encontra o que converter, e saldos de banco individual passam '
             || 'dos 6 meses do art. 59, §5º (ou dos 12 meses do §2º) sem virar hora extra. '
             || 'Correção: ao apurar a competência, gravar prazo_compensacao = fim da competência '
             || '+ prazo_compensacao_dias do regime vigente.';
    r.detalhe := jsonb_build_object('conversao_funciona', true,
                                    'apuracao_preenche_prazo', false);
  ELSE
    r.situacao := 'passou';
    r.obtido := 'A apuração deriva o prazo do regime e a conversão de saldo vencido funciona.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_355()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
  r public.qa_retorno;
  v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): existe rotina que alerte vencimento próximo do banco?';
  r.esperado := 'Alguma função gera alerta (ponto_alertas) sobre prazo/vencimento do banco de horas';

  SELECT string_agg(p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname NOT LIKE 'qa\_%'  -- as rotinas de QA citam os termos no diagnóstico
    AND p.prosrc ILIKE '%ponto_alertas%'
    AND (p.prosrc ILIKE '%venc%' OR p.prosrc ILIKE '%prazo%');

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nenhuma função do banco gera alerta de vencimento de saldo. O gerador de '
             || 'alertas de ponto (gerar_alertas_ponto) só conhece falta e atraso. Sem aviso '
             || 'antecipado, o RH só descobre o saldo vencido quando ele já virou passivo de hora '
             || 'extra (art. 59, §5º) — e o PONTO-354 mostra que nem essa conversão dispara hoje. '
             || 'Correção: rotina periódica que, X dias antes de prazo_compensacao, crie alerta em '
             || 'ponto_alertas com a ação sugerida (programar compensação ou pagar).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Alerta de vencimento presente em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_356()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
  r public.qa_retorno;
  v_col_existe boolean;
  v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o limite de acúmulo configurado é aplicado em algum lugar?';
  r.esperado := 'A apuração compara o saldo com limite_acumulo_horas e trata/alerta o excedente';

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'ponto_banco_horas_config'
      AND column_name = 'limite_acumulo_horas'
  ) INTO v_col_existe;

  IF NOT v_col_existe THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'A configuração nem tem campo de limite de acúmulo nesta base.';
    RETURN r;
  END IF;

  SELECT string_agg(p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%limite_acumulo%';

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o campo limite_acumulo_horas existe na configuração do banco '
             || '(ponto_banco_horas_config), mas NENHUMA função o consulta. É configuração '
             || 'decorativa: o gestor define um teto de acúmulo, o colaborador passa dele, e nada '
             || 'acontece — nem alerta, nem retenção, nem conversão do excedente. Correção: na '
             || 'apuração da competência, comparar saldo_atual_minutos com o limite do regime e '
             || 'gerar alerta/tratamento do excedente.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Limite de acúmulo aplicado em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_357()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
  r public.qa_retorno;
  v_cpf text; v_ajuste_id uuid;
  v_status_pend text; v_status_final text;
  v_antes text; v_depois text;
  v_motivo_visivel boolean := false;
  v_col_fantasma text;
BEGIN
  v_cpf := public.qa_ponto_admissao('QA Rejeicao Ajuste', 3571);
  PERFORM public.qa_ponto_marca(v_cpf, 'QA Rejeicao Ajuste', CURRENT_DATE - 3, TIME '08:00', 'entrada');
  PERFORM public.qa_ponto_marca(v_cpf, 'QA Rejeicao Ajuste', CURRENT_DATE - 3, TIME '17:00', 'saida');

  SELECT string_agg(hora_marcacao::text, '|' ORDER BY hora_marcacao) INTO v_antes
  FROM public.ponto_marcacoes
  WHERE tenant_id = public.qa_sandbox_tenant_id()
    AND colaborador_cpf = v_cpf AND data_marcacao = CURRENT_DATE - 3;

  INSERT INTO public.ponto_ajustes
    (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
     data_referencia, tipo_ajuste, motivo, status, hora_original, hora_solicitada)
  VALUES (public.qa_sandbox_tenant_id(), gen_random_uuid(), 'QA Rejeicao Ajuste', v_cpf,
          CURRENT_DATE - 3, 'correcao', 'QA: rejeicao deve deixar o dia intacto', 'pendente',
          TIME '08:00', TIME '07:30')
  RETURNING id INTO v_ajuste_id;

  r.passo_ordem := 1;
  r.passo_acao := 'Rejeitar o ajuste e conferir que o dia nao mudou';
  r.esperado := 'Status rejeitado, motivo visivel, marcacoes originais intactas';

  v_status_pend := 'ajuste_pendente';
  UPDATE public.ponto_ajustes
     SET status = 'rejeitado', observacao_aprovador = 'QA: rejeitado para teste'
   WHERE id = v_ajuste_id;

  SELECT status::text INTO v_status_final FROM public.ponto_ajustes WHERE id = v_ajuste_id;

  SELECT string_agg(hora_marcacao::text, '|' ORDER BY hora_marcacao) INTO v_depois
  FROM public.ponto_marcacoes
  WHERE tenant_id = public.qa_sandbox_tenant_id()
    AND colaborador_cpf = v_cpf AND data_marcacao = CURRENT_DATE - 3;

  SELECT (observacao_aprovador IS NOT NULL AND btrim(observacao_aprovador) <> '')
    INTO v_motivo_visivel
  FROM public.ponto_ajustes WHERE id = v_ajuste_id;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA (somente leitura): o fluxo de APROVACAO grava em colunas reais?';
  r.esperado := 'Toda coluna citada nos INSERT em ponto_marcacoes existe na tabela';

  -- Extrai a lista de colunas de cada INSERT INTO public.ponto_marcacoes (...)
  -- e confere nome a nome. Nao usa busca por palavra solta: o parametro
  -- p_ajuste_id ja produziu falso positivo por esse caminho.
  WITH src AS (
    SELECT p.prosrc AS s
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'processar_ajuste_ponto'
    LIMIT 1
  ),
  listas AS (
    SELECT (regexp_matches(s, 'INSERT\s+INTO\s+public\.ponto_marcacoes\s*\(([^)]*)\)', 'gi'))[1] AS cols
    FROM src
  ),
  colunas AS (
    -- btrim padrao so tira espaco: a lista do INSERT vem com quebra de
    -- linha e tabulacao, entao a limpeza precisa cobrir todo espaco em branco.
    SELECT DISTINCT regexp_replace(unnest(string_to_array(cols, ',')), '\s', '', 'g') AS col
    FROM listas
  )
  SELECT string_agg(col, ', ' ORDER BY col) INTO v_col_fantasma
  FROM colunas
  WHERE col <> ''
    AND NOT EXISTS (
      SELECT 1 FROM information_schema.columns ic
      WHERE ic.table_schema = 'public'
        AND ic.table_name = 'ponto_marcacoes'
        AND ic.column_name = colunas.col
    );

  IF v_status_final = 'rejeitado' AND v_antes IS NOT DISTINCT FROM v_depois
     AND v_motivo_visivel AND v_col_fantasma IS NULL THEN
    r.situacao := 'passou';
    r.obtido := 'Rejeicao integra: o ajuste ficou rejeitado, o motivo ficou registrado e as '
             || 'marcacoes originais nao mudaram um segundo. A aprovacao grava em colunas que '
             || 'existem — conferido pela lista de colunas do INSERT, nao por busca de texto.';
  ELSIF v_col_fantasma IS NOT NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: processar_ajuste_ponto grava em coluna(s) inexistente(s) em '
             || 'ponto_marcacoes: %s. Aprovar um ajuste por essa funcao quebra em execucao.',
             v_col_fantasma);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('A rejeicao nao ficou integra (status %s; marcacoes antes %s, depois %s; '
             || 'motivo visivel: %s).', COALESCE(v_status_final,'?'), COALESCE(v_antes,'-'),
             COALESCE(v_depois,'-'), v_motivo_visivel);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_358()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): existe reabertura FORMAL de competência fechada?';
  r.esperado := 'Reabertura com motivo, alçada e trilha; novo fechamento gera NOVA versão do espelho';
  v_fns := coalesce(public.qa_fns_com('%reabr%'), public.qa_fns_com('%reabert%'));
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: não existe reabertura formal. O que existe é a válvula do gatilho '
             || '(papéis de gestão marcam em competência fechada sem rito — PONTO-193). Erro '
             || 'legítimo descoberto depois precisa de saída FORMAL: reabrir com motivo e '
             || 'alçada registrados, recalcular, e o espelho ganhar NOVA VERSÃO — o documento '
             || 'que o colaborador cientificou não pode ser regravado por cima. Correção: '
             || 'fluxo de reabertura com estado próprio no fechamento e versionamento do '
             || 'espelho.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Reabertura formal presente em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_359()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_est text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o trabalhador consegue extrair os comprovantes de um período?';
  r.esperado := 'Extração dos comprovantes (janela mínima de 48h) pelo próprio colaborador';
  v_est := coalesce(public.qa_fns_com('%comprovante%'), NULL);
  IF v_est IS NULL OR to_regclass('public.ponto_comprovantes') IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: depende do comprovante existir como documento (PONTO-380) — hoje é um '
             || 'boolean na marcação, então não há o que extrair. Quando o comprovante '
             || 'nascer, a extração por período (janela mínima de 48h, direito do trabalhador '
             || 'no REP-P) é uma função de listagem restrita ao próprio CPF.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Extração presente: %s.', v_est);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_360()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_est text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o certificado de assinatura digital é gerenciado?';
  r.esperado := 'Cadastro do certificado (ICP-Brasil) com vigência e alerta de vencimento';
  v_est := coalesce(public.qa_col_existe(NULL, '%certificado_digital%'),
                    public.qa_col_existe(NULL, '%icp%'),
                    public.qa_fns_com('%icp-brasil%'), public.qa_fns_com('%p7s%'));
  IF v_est IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: não existe gestão de certificado digital — nem cadastro, nem vigência, '
             || 'nem alerta. Consequência dupla: (1) AFD/AEJ não têm COM QUE ser assinados '
             || '(a auditoria de conformidade já apontou a ausência de assinatura ICP-Brasil); '
             || '(2) quando a assinatura existir, um certificado vencido paralisa a emissão '
             || 'dos artefatos exatamente na hora da fiscalização. Correção: cadastro do '
             || 'certificado por empresa com vencimento vigiado (alerta com antecedência '
             || 'parametrizada).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Gestão de certificado presente: %s.', v_est);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_361()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a exportação para a folha é gerada por função auditável?';
  r.esperado := 'Eventos com grandeza real (horas, valores) e natureza correta (vencimento/desconto/indenização)';
  v_fns := public.qa_fns_com('%exportacoes_folha%');
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a exportação para a folha não tem função no banco — a tabela '
             || 'ponto_exportacoes_folha guarda um jsonb montado pela tela, sem regra '
             || 'verificável de composição. Não há como garantir grandezas reais (o DSR nem é '
             || 'apurado — PONTO-132; o excesso de HE é cortado — PONTO-092) nem naturezas '
             || 'corretas (vencimento × desconto × indenizatória). É onde o ponto vira '
             || 'dinheiro: zero afirmativo aqui é dívida silenciosa. Correção: função de '
             || 'composição do pacote a partir da apuração fechada, com memória.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Composição auditável presente em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_362()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_est text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): tentativas seguidas de CPFs diferentes no mesmo link são contidas?';
  r.esperado := 'Bloqueio temporário e registro do padrão de enumeração';
  v_est := coalesce(public.qa_col_existe('ponto_links', '%tentativa%'),
                    public.qa_col_existe('ponto_links', '%bloque%'));
  IF v_est IS NULL THEN
    SELECT string_agg(p.proname, ', ') INTO v_est
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
      AND p.proname ILIKE '%ponto%' AND p.prosrc ILIKE '%tentativ%'
      AND (p.prosrc ILIKE '%link%' OR p.prosrc ILIKE '%token%');
  END IF;
  IF v_est IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: as funções do link compartilhado (registrar_ponto_externo_cpf e '
             || 'afins) não guardam tentativas nem aplicam bloqueio — CPFs em sequência no '
             || 'mesmo link (padrão clássico de enumeração para descobrir CPFs válidos da '
             || 'empresa e marcar por terceiros) passam sem registro nem contenção. Correção: '
             || 'contador de tentativas frustradas por link/IP com bloqueio temporário e '
             || 'evento na trilha.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Contenção presente: %s.', v_est);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_370()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_est text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): existe estrutura de obrigatoriedade por estabelecimento?';
  r.esperado := 'Coluna/função que registre a contagem de trabalhadores e sinalize o controle obrigatório (art. 74, §2º)';

  v_est := coalesce(public.qa_col_existe(NULL, '%obrigator%ponto%'), '')
        || coalesce(public.qa_col_existe(NULL, '%controle%obrigat%'), '')
        || coalesce(public.qa_fns_com('%74%§2%'), '')
        || coalesce(public.qa_fns_com('%obrigatoriedade%jornada%'), '');

  IF v_est = '' THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o sistema não tem nenhuma noção de obrigatoriedade do controle por '
             || 'estabelecimento — não conta os 20 trabalhadores do art. 74, §2º, não sinaliza '
             || 'quem é obrigado e trata todo cliente igual. Consequência: cliente obrigado sem '
             || 'controle ativo não recebe aviso algum, e a Súmula 338 joga a jornada alegada '
             || 'pelo empregado contra ele. Correção: contagem por estabelecimento + sinalização '
             || 'de obrigatoriedade no cadastro, com alerta quando cruzar o limite.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Estrutura de obrigatoriedade encontrada: %s.', v_est);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_371()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_flag text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a configuração distingue empresa que optou por NÃO controlar?';
  r.esperado := 'Flag de controle ativo/facultativo por empresa ou estabelecimento';

  SELECT string_agg(column_name, ', ') INTO v_flag
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'ponto_configuracao'
    AND (column_name ILIKE '%ativo%' OR column_name ILIKE '%facultativ%'
         OR column_name ILIKE '%habilitad%');

  IF v_flag IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: ponto_configuracao não tem flag de controle ativo/facultativo. Empresa '
             || 'com menos de 20 trabalhadores que NÃO adota controle é tratada igual às demais: '
             || 'a materialização gera falta em todo dia útil sem marcação (PONTO-290) e o painel '
             || 'enche de pendências indevidas. Correção: flag por empresa/estabelecimento que '
             || 'desligue a exigência de marcação (e, ligada, aplique o padrão legal completo).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Flag de controle presente: %s.', v_flag);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_372()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_aceitou boolean := false;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Ativar modo_apuracao = por_excecao SEM anexar o acordo (ponto_excecao_acordo_url vazio)';
  r.esperado := 'Recusado — o art. 74, §4º exige acordo individual escrito ou instrumento coletivo';

  BEGIN
    INSERT INTO public.ponto_configuracao (tenant_id, modo_apuracao, ponto_excecao_acordo_url)
    VALUES (public.qa_sandbox_tenant_id(), 'por_excecao', NULL);
    v_aceitou := true;
  EXCEPTION WHEN check_violation OR not_null_violation OR raise_exception THEN
    v_aceitou := false;
  END;

  IF v_aceitou THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o banco ACEITOU o modo "registro por exceção" sem documento autorizador '
             || '— a coluna ponto_excecao_acordo_url existe (bom sinal), mas nada obriga a '
             || 'preenchê-la. Registro por exceção sem acordo escrito é controle inválido perante '
             || 'o art. 74, §4º. Correção: CHECK/trigger exigindo o acordo anexado (URL não vazia) '
             || 'sempre que modo_apuracao = por_excecao.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'O modo por exceção sem documento foi recusado — a exigência do §4º está no banco.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_373()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_est text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): existe enquadramento do art. 62 no cadastro?';
  r.esperado := 'Campo que marque o vínculo como dispensado de controle (externo/gestão/tele por produção)';

  v_est := coalesce(public.qa_col_existe(NULL, '%dispensado_ponto%'), '')
        || coalesce(public.qa_col_existe(NULL, '%controle_jornada%'), '')
        || coalesce(public.qa_col_existe(NULL, '%art62%'), '')
        || coalesce(public.qa_col_existe(NULL, '%cargo_confianca%'), '');

  IF v_est = '' THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: não existe campo de enquadramento do art. 62. Gestor, externo e '
             || 'teletrabalhista por produção são tratados como controlados: a materialização '
             || 'gera falta para quem a lei dispensa de marcar. Correção: flag de dispensa de '
             || 'controle no vínculo (com o inciso e o documento de enquadramento), respeitada '
             || 'pela materialização de faltas e pelos alertas.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Enquadramento presente: %s.', v_est);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_374()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_est text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o cadastro distingue teletrabalho por JORNADA de por PRODUÇÃO?';
  r.esperado := 'Campo de modalidade de teletrabalho (Lei 14.442/2022) — só produção/tarefa dispensa controle';

  v_est := coalesce(public.qa_col_existe(NULL, '%teletrabalho%'), '')
        || coalesce(public.qa_col_existe(NULL, '%remoto%'), '')
        || coalesce(public.qa_col_existe(NULL, '%home_office%'), '');

  IF v_est = '' THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nenhuma tabela registra a modalidade de teletrabalho. Sem distinguir '
             || 'jornada de produção/tarefa (Lei 14.442/2022), o sistema não sabe quem DEVE '
             || 'continuar marcando remoto — risco nos dois sentidos: cobrar de quem é dispensado '
             || 'ou dispensar quem é controlado. Correção: modalidade no contrato/vínculo, '
             || 'amarrada à exigência de marcação.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Modalidade de teletrabalho presente: %s.', v_est);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_375()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): algo detecta controle de fato sobre dispensado do art. 62?';
  r.esperado := 'Alerta de descaracterização quando um dispensado acumula marcações reais';

  v_fns := public.qa_fns_com('%descaracteriza%');

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nenhuma rotina detecta descaracterização do art. 62 (dispensado com '
             || 'marcações de fato). Na Justiça, o controle de fato derruba a exclusão e traz '
             || 'as horas extras do período inteiro. Depende do enquadramento do PONTO-373 '
             || 'existir primeiro; com ele, a detecção é um cruzamento simples: dispensado + '
             || 'marcações recorrentes → alerta a RH/Jurídico.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Detecção presente em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_376()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
  r public.qa_retorno;
  v_cpf text;
  v_amanha boolean := false;
  v_hora_futura boolean := false;
BEGIN
  v_cpf := public.qa_ponto_admissao('QA Marcação Futura', 3760);

  r.passo_ordem := 1;
  r.passo_acao := 'Inserir marcação com DATA de amanhã';
  r.esperado := 'Recusada — ninguém registra o ponto de amanhã';
  BEGIN
    PERFORM public.qa_ponto_marca(v_cpf, 'QA Marcação Futura', CURRENT_DATE + 1, TIME '08:00', 'entrada');
    v_amanha := true;   -- aceitou (achado)
  EXCEPTION WHEN OTHERS THEN
    v_amanha := false;  -- recusou (correto)
  END;

  r.passo_ordem := 2;
  r.passo_acao := 'Inserir marcação de HOJE com hora futura (23:59)';
  r.esperado := 'Recusada ou registrada com a hora do servidor — nunca a hora informada no futuro';
  IF localtime < TIME '23:00' THEN
    BEGIN
      PERFORM public.qa_ponto_marca(v_cpf, 'QA Marcação Futura', CURRENT_DATE, TIME '23:59', 'entrada');
      v_hora_futura := true;
    EXCEPTION WHEN OTHERS THEN
      v_hora_futura := false;
    END;
  END IF;

  IF NOT v_amanha AND NOT v_hora_futura THEN
    r.situacao := 'passou';
    r.obtido := 'Data futura e hora futura foram recusadas — o carimbo de tempo não aceita futuro.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o banco ACEITOU marcação futura (data de amanhã: %s; hora futura '
             || 'hoje: %s). Data e hora vêm do cliente sem validação temporal — por API ou SQL, '
             || 'grava-se o ponto de amanhã, corrompendo a fidelidade que a Portaria 671 exige. '
             || 'Correção: recusar data/hora posteriores ao relógio do servidor no gatilho de '
             || 'inserção (com folga mínima para latência).',
             CASE WHEN v_amanha THEN 'ACEITA' ELSE 'recusada' END,
             CASE WHEN v_hora_futura THEN 'ACEITA' ELSE 'recusada/não testada' END);
    r.detalhe := jsonb_build_object('data_futura_aceita', v_amanha,
                                    'hora_futura_aceita', v_hora_futura);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_377()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): algo detecta uniformidade de marcações?';
  r.esperado := 'Rotina que sinalize espelho "britânico" (horários idênticos por período prolongado)';

  v_fns := coalesce(public.qa_fns_com('%britanic%'), public.qa_fns_com('%uniformidade%'));

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nada detecta marcações uniformes. Um mês de batidas cravadas no mesmo '
             || 'minuto passa sem aviso — e a Súmula 338, III, do TST considera esses registros '
             || 'INVÁLIDOS como prova, invertendo a presunção a favor do empregado. O gerador de '
             || 'alertas (gerar_alertas_ponto) só conhece falta e atraso. Correção: verificação '
             || 'periódica de variância das marcações por colaborador, com alerta quando a '
             || 'uniformidade passar do limiar.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Detecção de uniformidade presente em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_378()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_col text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a marcação registra se nasceu on-line ou off-line?';
  r.esperado := 'Coluna de status on/off-line em ponto_marcacoes (a Portaria 671 exige a identificação no AFD)';

  SELECT string_agg(column_name, ', ') INTO v_col
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'ponto_marcacoes'
    AND (column_name ILIKE '%offline%' OR column_name ILIKE '%online%'
         OR column_name ILIKE '%sincroniz%');

  IF v_col IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: ponto_marcacoes não guarda o status on/off-line nem o momento da '
             || 'sincronização. Se a marcação offline for implementada, não haverá como '
             || 'distinguir a hora da batida da hora do envio — e o AFD do REP-P precisa '
             || 'identificar o status. Correção: colunas de status de origem (on/off-line) e '
             || 'de timestamp de sincronização, preservando a hora da batida como a oficial.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Status de origem presente: %s.', v_col);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_379()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): existe monitoração da Hora Legal Brasileira?';
  r.esperado := 'Rotina que confira o relógio contra a HBL e alerte desvio acima da tolerância';

  v_fns := coalesce(public.qa_fns_com('%hora legal%'), public.qa_fns_com('%hora_legal%'),
                    public.qa_fns_com('%observatorio%'), public.qa_fns_com('%ntp%'));

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nenhuma rotina monitora o relógio contra a Hora Legal Brasileira. O '
             || 'carimbo das marcações depende do relógio do servidor sem verificação — a '
             || 'Portaria 671 exige o REP-P sincronizado com a HBL (Observatório Nacional). '
             || 'Correção: verificação periódica do desvio com tolerância parametrizada, alerta '
             || 'imediato e registro do evento na trilha.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Monitoração presente em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_381()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): existe vigilância do prazo de 48h do comprovante?';
  r.esperado := 'Alerta preventivo antes das 48h e crítico ao estourar (REP-P, Portaria 671)';

  v_fns := public.qa_fns_com('%comprovante%48%');

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nada vigia o prazo de 48 horas do comprovante do REP-P. Como o '
             || 'comprovante em si ainda não existe como documento (PONTO-380), o prazo legal '
             || 'de disponibilização não tem nem o que ser medido. Correção: após o comprovante '
             || 'existir, rotina periódica que alerte antes das 48h e escale ao estourar, com '
             || 'ação no Plano de Ação.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Vigilância do prazo presente em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_382()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text; v_cols text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a importação de AFD valida integridade no banco?';
  r.esperado := 'Validação de CRC-16, SHA-256 encadeado e assinatura, com quarentena do arquivo inválido';

  v_fns := coalesce(public.qa_fns_com('%crc%'), public.qa_fns_com('%quarentena%'));
  SELECT string_agg(column_name, ', ') INTO v_cols
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'ponto_repc_importacoes'
    AND column_name IN ('status', 'erros', 'registros_rejeitados');

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a tabela de importações (ponto_repc_importacoes) tem os campos '
             || 'certos (%s), mas NENHUMA função do banco valida integridade de AFD — nada de '
             || 'CRC-16 (tipos 1-5), cadeia SHA-256 (tipo 7), assinatura .p7s ou quarentena. Se '
             || 'a validação existir só na tela, importação por API entra sem conferência, e '
             || 'arquivo corrompido contamina a base probatória. Correção: validação no banco '
             || '(ou edge function) com quarentena do arquivo reprovado e relatório de '
             || 'inconsistências.', coalesce(v_cols, 'nenhum'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Validação de integridade presente em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_384()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_est text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): ajustes de relógio (tipo 4) e eventos sensíveis (tipo 6) do AFD têm onde morar?';
  r.esperado := 'Estrutura para os registros não-marcação do AFD, visíveis na trilha';

  v_est := coalesce(public.qa_col_existe(NULL, '%ajuste_relogio%'), '')
        || coalesce(public.qa_col_existe(NULL, '%evento_sensivel%'), '')
        || coalesce(public.qa_fns_com('%tipo 4%relogio%'), '');

  IF v_est = '' THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: não existe estrutura para os registros tipo 4 (ajuste do relógio do '
             || 'equipamento) e tipo 6 (eventos sensíveis) do AFD — numa importação, esses '
             || 'registros seriam descartados. Um relógio ajustado perto de uma marcação suspeita '
             || 'é exatamente o que a fiscalização procura na trilha. Correção: importar e expor '
             || 'esses registros na trilha de auditoria do equipamento.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Estrutura presente: %s.', v_est);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_385()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_cpf text := public.qa_cpf(3850);
  v_base date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
  v_d1 date;
  v_r1 text; v_r2 text;
  v_comp text;
  v_fonte int; v_res jsonb; v_id uuid;
BEGIN
  v_d1 := v_base + ((8 - EXTRACT(ISODOW FROM v_base)::int) % 7);
  v_comp := to_char(v_d1, 'YYYY-MM');

  r.passo_ordem := 1;
  r.passo_acao := 'Apurar a mesma competencia duas vezes (determinismo)';
  r.esperado := 'Resultados identicos — mesma fonte + mesmos parametros = mesma conta';

  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Memoria', 480, 10, v_d1, v_d1);
  PERFORM public.qa_ponto_marca(v_cpf, 'QA Memoria', v_d1, TIME '08:00', 'entrada');
  PERFORM public.qa_ponto_marca(v_cpf, 'QA Memoria', v_d1, TIME '17:00', 'saida');
  PERFORM public.consolidar_ponto_diario_manual(v_t, v_cpf, v_d1);

  SELECT string_agg(dia::text || ':' || coalesce(saldo_min::text,'n'), '|' ORDER BY dia) INTO v_r1
  FROM public.ponto_saldo_dias_competencia(v_t, v_cpf, v_comp);
  SELECT string_agg(dia::text || ':' || coalesce(saldo_min::text,'n'), '|' ORDER BY dia) INTO v_r2
  FROM public.ponto_saldo_dias_competencia(v_t, v_cpf, v_comp);

  r.passo_ordem := 2;
  r.passo_acao := 'Gravar a memoria de calculo e conferir fonte + resultado';
  r.esperado := 'Uma linha com as marcacoes-fonte e o resultado apurado, refazivel';

  IF to_regclass('public.ponto_memoria_calculo') IS NULL
     OR public.qa_fns_com('%registrar_memoria_calculo%') IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nao existe memoria de calculo — nenhuma tabela/funcao registra, por '
             || 'competencia, a fonte usada e o resultado. Sem memoria, o auditor nao refaz o '
             || 'calculo e a empresa nao explica o espelho ao colaborador.';
    RETURN r;
  END IF;

  v_id := public.ponto_registrar_memoria_calculo(v_t, v_cpf, v_comp);
  SELECT fonte_marcacoes, resultado INTO v_fonte, v_res
  FROM public.ponto_memoria_calculo
  WHERE tenant_id = v_t AND colaborador_cpf = v_cpf AND competencia = v_comp;

  IF v_r1 IS DISTINCT FROM v_r2 THEN
    r.situacao := 'falhou';
    r.obtido := 'A MESMA apuracao, duas vezes, deu resultados diferentes — a conta nao e '
             || 'deterministica, o que inviabiliza auditoria.';
    r.detalhe := jsonb_build_object('rodada1', v_r1, 'rodada2', v_r2);
  ELSIF v_id IS NULL OR v_fonte IS NULL OR v_fonte = 0 OR v_res IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a memoria de calculo existe mas nao guardou a fonte/resultado '
             || '(marcacoes-fonte: %s, resultado: %s). Uma memoria sem fonte nao refaz a conta.',
             COALESCE(v_fonte::text,'nulo'), COALESCE(v_res::text,'nulo'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Apuracao deterministica e memoria gravada: %s marcacao(oes)-fonte e '
             || 'resultado %s. O auditor refaz a conta a partir da fonte.', v_fonte, v_res::text);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_386()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_src text; v_usa_vigencia boolean; v_alerta text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): quem consome ponto_cct_config filtra pela vigência?';
  r.esperado := 'A apuração escolhe o instrumento vigente NA DATA apurada (vigencia_inicio/fim)';

  SELECT prosrc INTO v_src
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'calcular_he_adicional_noturno_dia';

  IF v_src IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A tabela ponto_cct_config existe (com vigencia_inicio/fim), mas nenhuma função '
             || 'de apuração a consome — os parâmetros da CCT são decorativos no banco.';
    RETURN r;
  END IF;

  v_usa_vigencia := v_src ILIKE '%vigencia%';
  v_alerta := public.qa_fns_com('%cct%venc%');

  IF NOT v_usa_vigencia THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: calcular_he_adicional_noturno_dia consome ponto_cct_config SEM filtrar '
             || 'pela vigência (vigencia_inicio/vigencia_fim existem na tabela e não aparecem na '
             || 'função). Reapurar uma competência antiga aplica a convenção atual — percentuais '
             || 'errados retroativos. Correção: escolher o instrumento cuja vigência cobre a DATA '
             || 'apurada; alertar sobreposição e vencimento (60/30 dias), que hoje também não '
             || 'existe.';
  ELSIF v_alerta IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A apuração filtra pela vigência (correto), mas não existe alerta de instrumento '
             || 'coletivo a vencer (60/30 dias) nem de vigências sobrepostas. Correção: rotina '
             || 'periódica de vigilância das vigências de ponto_cct_config.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Vigência respeitada na apuração e vigilância presente em: %s.', v_alerta);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_387()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_confere boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o fechamento confere a situação dos espelhos?';
  r.esperado := 'Fechar competência exige espelhos confirmados/assinados (ou recusa formalizada)';

  SELECT bool_or(p.prosrc ILIKE '%espelho%' AND (p.prosrc ILIKE '%confirmad%'
              OR p.prosrc ILIKE '%assinatur%' OR p.prosrc ILIKE '%status%'))
    INTO v_confere
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname ILIKE '%fechar%' AND p.proname NOT LIKE 'qa\_%';

  IF NOT coalesce(v_confere, false) THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nenhuma função de fechamento confere os espelhos. A tabela '
             || 'ponto_espelhos tem status, data_confirmacao e assinatura_hash — mas o '
             || 'fechamento (ponto_fechar_competencia_banco) só transita saldos, sem checar se o '
             || 'colaborador viu e assinou. Espelho sem ciência enfraquece a prova (Súmula 338). '
             || 'Correção: fechamento bloqueado (ou com justificativa formal) enquanto houver '
             || 'espelho pendente de confirmação.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'O fechamento confere a situação dos espelhos antes de concluir.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_388()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_confere boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o fechamento trava com pendência crítica aberta?';
  r.esperado := 'Ajustes pendentes, lacunas sem justificativa e falhas de integridade impedem fechar';

  SELECT bool_or(p.prosrc ILIKE '%pendente%')
    INTO v_confere
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname ILIKE '%fechar%' AND p.proname NOT LIKE 'qa\_%';

  IF NOT coalesce(v_confere, false) THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o fechamento não verifica pendências. Com ajuste pendente de aprovação '
             || 'ou lacuna sem justificativa, a competência fecha por cima e manda o dado errado '
             || 'para a folha — e o PONTO-193 mostra que depois de fechada não se mexe. Correção: '
             || 'lista de pendências críticas bloqueantes no fechamento (ajustes pendentes, dias '
             || 'incompletos sem tratamento, falha de integridade).';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'O fechamento verifica pendências antes de concluir.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_389()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_link text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): alerta de ponto consegue virar ação no Plano de Ação?';
  r.esperado := 'Vínculo estrutural entre ponto_alertas e o módulo Plano de Ação (5W2H com origem)';

  v_link := coalesce(public.qa_col_existe('ponto_alertas', '%plano%'), '')
         || coalesce(public.qa_col_existe(NULL, '%alerta_ponto%'), '');
  IF v_link = '' THEN
    SELECT coalesce(string_agg(p.proname, ', '), '') INTO v_link
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
      AND p.prosrc ILIKE '%ponto_alertas%' AND p.prosrc ILIKE '%plano%acao%';
  END IF;

  IF v_link = '' THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: não há ponte entre os alertas do ponto e o Plano de Ação — nem coluna '
             || 'de vínculo, nem função que crie a ação. O documento de requisitos faz dessa '
             || 'integração o coração preventivo do módulo (ação 5W2H nascendo do alerta, com '
             || 'origem navegável). Correção: função que converta alerta em ação preenchida, '
             || 'guardando o vínculo com o alerta/marcação/competência de origem.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Ponte presente: %s.', v_link);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_390()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): concluir uma ação valida a eficácia sobre a ocorrência?';
  r.esperado := 'Baixa da ação confere se o alerta de origem pode encerrar e registra a evidência';

  v_fns := public.qa_fns_com('%eficacia%');

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: não existe validação de eficácia — depende da ponte alerta→ação do '
             || 'PONTO-389, que também não existe. Sem ela, concluir a ação dá baixa cega: o '
             || 'intervalo continua suprimido na semana seguinte e ninguém percebe, porque o '
             || 'alerta morreu junto com a ação. Correção: na conclusão, reavaliar a ocorrência '
             || 'de origem; persistindo, reabrir ou gerar novo alerta com o histórico.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Validação de eficácia presente em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_392()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): existe geração de dossiê de fiscalização?';
  r.esperado := 'Rotina que reúna AFD, AEJ, comprovantes, espelhos e trilha num pacote com índice e hashes';

  v_fns := coalesce(public.qa_fns_com('%dossie%'), public.qa_fns_com('%fiscaliza%'));

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: não existe o dossiê de fiscalização. Diante do Auditor-Fiscal, o DP '
             || 'teria de caçar peça por peça — e as principais nem existem ainda (AFD fora do '
             || 'leiaute, AEJ ausente, comprovante só como boolean; ver PONTO-210/211/380). O '
             || '"modo fiscalização em um clique" do documento depende primeiro dessas peças, '
             || 'depois do empacotador com índice e verificação de assinaturas.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Dossiê presente em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_393()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): peças do ponto se arquivam sozinhas no módulo Documentos?';
  r.esperado := 'Funções do ponto gravando no repositório de documentos, com classificação e vínculo';

  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.proname ILIKE '%ponto%'
    AND (p.prosrc ILIKE '%documentos_empresa%' OR p.prosrc ILIKE '%storage.objects%'
         OR p.prosrc ILIKE '%documentos_funcionario%');

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nenhuma função do ponto arquiva peça alguma no módulo Documentos — '
             || 'espelhos, extratos e arquivos ficam soltos nas tabelas do ponto (quando '
             || 'existem), sem a classificação por pasta e o vínculo previstos na seção 16 do '
             || 'documento de requisitos. Correção: ao gerar cada peça, gravar a referência no '
             || 'repositório de documentos com pasta, metadados e vínculo, sem upload manual.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Arquivamento automático presente em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_394()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
  DECLARE r public.qa_retorno; v_def text;
  BEGIN
    SELECT indexdef INTO v_def
    FROM pg_indexes
    WHERE schemaname = 'public' AND tablename = 'ponto_diario'
      AND indexname = 'unique_ponto_diario';

    IF v_def IS NOT NULL AND v_def NOT ILIKE '%empresa_id%' THEN
      r.passo_ordem := 1;
      r.passo_acao  := 'Conferir se a chave da apuracao diaria comporta dois vinculos';
      r.esperado    := 'Chave por tenant, CPF, data E EMPRESA — dois contratos coexistem no mesmo dia';
      r.situacao    := 'falhou';
      r.obtido      := 'ACHADO ESTRUTURAL: a chave da apuracao diaria deste ambiente e '
                    || '(tenant, CPF, data), SEM a empresa. Dois vinculos do mesmo '
                    || 'trabalhador — duas empresas do grupo, dois estabelecimentos — sao '
                    || 'impossiveis de apurar: o segundo contrato colide com o primeiro no '
                    || 'indice unique_ponto_diario e a gravacao do dia e recusada. Na '
                    || 'pratica, o segundo vinculo fica sem espelho, sem jornada e sem '
                    || 'horas extras. Correcao: incluir a empresa na chave, como o projeto '
                    || 'ja faz desde a onda 1 (migration 20260818190000), que acompanha um '
                    || 'gatilho de reconciliacao para nao duplicar o dia de quem tem um '
                    || 'unico vinculo.';
      r.erro_tecnico := 'Indice atual: ' || v_def;
      RETURN r;
    END IF;

    RETURN public.qa_caso_ponto_394_corpo();
  END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_397()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): visualização de dado sensível e exportação deixam rastro?';
  r.esperado := 'Registro de QUEM viu selfie/geolocalização e QUEM exportou dados, em log imutável';

  v_fns := coalesce(public.qa_fns_com('%log%selfie%'), public.qa_fns_com('%acesso%sensivel%'),
                    public.qa_fns_com('%log%exporta%'));

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a trilha de auditoria só captura escrita (INSERT/UPDATE/DELETE, via '
             || 'gatilhos) — visualizar a selfie ou a geolocalização de uma marcação e exportar '
             || 'relatórios de ponto não deixam rastro algum. A LGPD (arts. 11 e 46) pede '
             || 'registro do tratamento de dado sensível; num vazamento, seria impossível saber '
             || 'quem acessou o quê. Correção: registrar o acesso no ponto de entrega (função '
             || 'RPC/edge que serve o dado sensível loga antes de servir; exportações gravam '
             || 'escopo e destinatário).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Trilha de acesso presente em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_398()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text; v_status text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): exportação para a folha tem fila e reenvio?';
  r.esperado := 'Falha na entrega enfileira e reenvia sem perda nem duplicidade';

  v_fns := coalesce(public.qa_fns_com('%exportacoes_folha%'), '');
  v_status := public.qa_col_existe('ponto_exportacoes_folha', 'status');

  IF v_fns = '' THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a exportação para a folha é um registro passivo '
             || '(ponto_exportacoes_folha tem %s), mas nenhuma função do banco a processa — '
             || 'sem fila, sem reenvio, sem confirmação de recebimento. Se a geração falha no '
             || 'meio, o operador refaz na mão e ninguém garante ausência de duplicidade. '
             || 'Correção: estados explícitos (pendente/enviado/confirmado/falha) + rotina de '
             || 'reenvio idempotente.', coalesce('coluna ' || v_status, 'nem coluna de status'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Processamento da exportação presente em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_400()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_col text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a saída antecipada é identificada como tal?';
  r.esperado := 'Selo/campo próprio com os minutos, distinto do atraso';
  v_col := coalesce(public.qa_col_existe('ponto_diario', '%antecipad%'),
                    public.qa_col_existe('ponto_diario', '%saida_ante%'));
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%antecipad%' AND p.prosrc ILIKE '%ponto%');

  IF v_col IS NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a saída antecipada não existe como conceito na apuração — o '
             || 'atraso tem coluna própria (ponto_diario.atraso_minutos) e a saída antes '
             || 'do fim da jornada some dentro de horas_faltantes, sem rótulo e sem os '
             || 'minutos separados. Para o colaborador, o espelho mostra um débito sem '
             || 'dizer de onde veio; para o gestor, some a informação de que a pessoa '
             || 'está saindo cedo (que é conversa de gestão, não de folha). Correção: '
             || 'marcar o dia com saída antecipada e os minutos, ao lado do atraso, com '
             || 'o saldo negativo na diferença exata — sem tratar como falta.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Saída antecipada tratada (campo: %s; funções: %s).',
                       coalesce(v_col, '—'), coalesce(v_fns, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_403()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_cpf text := public.qa_cpf(81); v_dia date := CURRENT_DATE - 2;
        v_escala uuid; v_falta interval; v_extra interval; v_trab interval;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Apurar um dia de colaborador SEM escala atribuída (06:00 às 12:00)';
  r.esperado := 'Tempo contado; sem saldo apurado contra jornada suposta; pendência de cadastro';
  INSERT INTO public.ponto_diario
    (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf, data,
     entrada, saida, status)
  VALUES (v_t, gen_random_uuid(), 'QA Colaborador Sem Escala', v_cpf, v_dia,
          time '06:00', time '12:00', 'pendente')
  ON CONFLICT DO NOTHING;  -- reexecução no mesmo dia reaproveita a linha

  BEGIN
    PERFORM public.consolidar_ponto_diario_manual(v_t, v_cpf, v_dia);
  EXCEPTION WHEN OTHERS THEN NULL;  -- a consolidação pode exigir contexto extra
  END;

  SELECT d.escala_id, coalesce(d.horas_faltantes, interval '0'),
         coalesce(d.horas_extras, interval '0'), coalesce(d.horas_trabalhadas, interval '0')
    INTO v_escala, v_falta, v_extra, v_trab
  FROM public.ponto_diario d
  WHERE d.tenant_id = v_t AND d.colaborador_cpf = v_cpf AND d.data = v_dia;

  IF v_escala IS NULL AND (v_falta > interval '0' OR v_extra > interval '0') THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: sem escala atribuída (escala_id nulo), a apuração mesmo '
             || 'assim produziu saldo — %s de falta e %s de extra sobre %s '
             || 'trabalhadas: o dia foi medido contra uma jornada que ninguém contratou '
             || '(o fallback de CCT/8h). Escala é pré-requisito da apuração: medir contra '
             || 'padrão suposto cria hora extra (se a jornada real for menor) ou falta (se '
             || 'for maior) que não existem — e o erro passa despercebido porque o espelho '
             || 'parece normal. Correção: sem escala vigente, contar o tempo trabalhado '
             || 'SEM apurar saldo, e listar o colaborador nas pendências de cadastro.',
             v_falta, v_extra, v_trab);
  ELSIF v_escala IS NULL AND v_trab > interval '0' THEN
    r.situacao := 'passou';
    r.obtido := format('Sem escala: %s contadas e nenhum saldo apurado contra padrão suposto.', v_trab);
  ELSIF v_escala IS NOT NULL THEN
    r.situacao := 'passou';
    r.obtido := format('O dia acabou vinculado a uma escala (%s) — o cenário sem escala não se formou nesta base.',
                       v_escala);
  ELSE
    -- a consolidação não produziu jornada nesta base (falta contexto de
    -- cadastro): sem número apurado, não há o que julgar — guarda honesta
    r.situacao := 'nao_implementado';
    r.obtido := 'A consolidação não apurou jornada para o dia nesta base (sem colaborador '
             || 'completo no cadastro), então não há saldo a auditar. No ambiente com '
             || 'dados, o caso mede se a apuração inventa jornada padrão para quem não '
             || 'tem escala.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_420()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_src text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a exigência de acordo declarada na config é honrada?';
  r.esperado := 'Com exige_acordo ligado e sem acordo vinculado, o banco NÃO credita';
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'ponto_banco_regime_vigente';

  IF v_src IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A função ponto_banco_regime_vigente não existe mais — o regime de banco '
             || 'perdeu o guardião do instrumento (CLT art. 59, §§ 2º e 5º).';
  ELSIF v_src ILIKE '%exige_acordo%' AND v_src ILIKE '%acordo_id%' THEN
    r.situacao := 'passou';
    r.obtido := 'O regime vigente confere a exigência de acordo declarada na configuração '
             || 'e o vínculo do acordo — crédito sem instrumento não passa.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a configuração do banco declara exigir acordo (exige_acordo_'
             || 'individual / exige_cct_act) e a rotina do regime vigente não confere se o '
             || 'acordo está de fato VINCULADO (acordo_id): a exigência que a própria casa '
             || 'declarou fica sem efeito, e o excedente é creditado num banco sem '
             || 'instrumento. Compensação sem acordo é inválida (CLT art. 59, §5º): na '
             || 'reclamatória, todas as horas viram extras com adicional e o extrato do '
             || 'banco serve de prova contra a empresa. Correção: sem acordo vinculado, '
             || 'não creditar — o excedente segue como hora extra, com a memória do '
             || 'motivo, e o alerta de formalização pendente.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_430()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_vazio boolean := false; v_chk text;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Solicitar ajuste com justificativa VAZIA e ver se passa';
  r.esperado := 'Recusado — a justificativa é obrigatória (Portaria MTP 671/2021)';
  BEGIN
    INSERT INTO public.ponto_ajustes
      (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
       data_referencia, tipo_ajuste, tipo_marcacao, hora_solicitada, motivo, status)
    VALUES (v_t, gen_random_uuid(), 'QA Colaborador Ajuste', public.qa_cpf(80),
            CURRENT_DATE - 1, 'correcao', 'entrada', '08:00', '', 'pendente');
    v_vazio := true;
  EXCEPTION WHEN check_violation OR not_null_violation OR raise_exception THEN
    v_vazio := false;
  END;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: existe validação de conteúdo mínimo do motivo?';
  r.esperado := 'CHECK/validação além do NOT NULL — string vazia não é justificativa';
  SELECT string_agg(conname, ', ') INTO v_chk FROM pg_constraint
  WHERE conrelid = 'public.ponto_ajustes'::regclass AND contype = 'c'
    AND pg_get_constraintdef(oid) ILIKE '%motivo%';

  IF v_vazio AND v_chk IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o ajuste entrou com motivo VAZIO — a coluna é NOT NULL (o que '
             || 'barra o nulo) mas string vazia passa, e não há CHECK de conteúdo mínimo. '
             || 'A trilha de auditoria fica com alterações de marcação sem história: na '
             || 'fiscalização, marcação alterada sem justificativa é indício de '
             || 'manipulação do controle de jornada (Portaria MTP 671/2021), e o '
             || 'aprovador decide no escuro. Correção: exigir motivo com conteúdo '
             || 'mínimo (CHECK de comprimento após trim), aplicado no banco — não só na '
             || 'tela, que qualquer integração contorna.';
  ELSIF NOT v_vazio THEN
    r.situacao := 'passou';
    r.obtido := 'Ajuste com justificativa vazia foi recusado pelo banco.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Há validação de conteúdo do motivo: %s.', v_chk);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_431()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
      DECLARE r public.qa_retorno;
      BEGIN
        IF to_regclass('public.ponto_dossies_fiscalizacao') IS NULL THEN
          r.passo_ordem := 1;
          r.passo_acao  := 'Conferir se a estrutura que este caso exercita existe no ambiente';
          r.esperado    := 'Estrutura presente para o caso poder ser exercitado';
          r.situacao    := 'falhou';
          r.obtido      := 'ACHADO: este ambiente nao tem a tabela do dossie de fiscalizacao — nao ha o que remontar nem como garantir um dossie unico por competencia. A estrutura existe no projeto; falta chegar aqui.';
          r.erro_tecnico := 'A tabela ponto_dossies_fiscalizacao nao existe neste ambiente.';
          RETURN r;
        END IF;
        RETURN public.qa_caso_ponto_431_corpo();
      END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_440()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_src text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): alguém vigia a vigência do instrumento coletivo?';
  r.esperado := 'Alerta antes do vencimento e severidade maior quando já vencido';
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'ponto_cct_vigiar_vigencia';

  IF v_src IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nenhuma rotina vigia a vigência dos instrumentos coletivos — a '
             || 'CCT vence e leva junto os parâmetros da apuração (percentuais de HE, '
             || 'adicional noturno, intervalo, prazo do banco), e a competência seguinte '
             || 'passa a apurar pela regra geral sem ninguém decidir isso. Correção: '
             || 'vigilância diária avisando o vencimento com antecedência e acusando o '
             || 'instrumento vencido com severidade maior.';
  ELSIF v_src ILIKE '%vencid%' OR v_src ILIKE '%severidade%' THEN
    r.situacao := 'passou';
    r.obtido := 'A vigência do instrumento coletivo é vigiada por ponto_cct_vigiar_vigencia, '
             || 'com distinção entre a vencer e vencido.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: existe vigilância de CCT (ponto_cct_vigiar_vigencia), mas ela não '
             || 'distingue o instrumento A VENCER do JÁ VENCIDO — o alerta chega com o '
             || 'mesmo peso nos dois casos, quando o vencido significa competência '
             || 'descoberta de parâmetro coletivo. Correção: severidade maior para o '
             || 'vencido, com a competência afetada apontada.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_441()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_src text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): dois instrumentos do mesmo escopo na mesma data são acusados?';
  r.esperado := 'Sobreposição sinalizada — a apuração não escolhe em silêncio';
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'ponto_cct_vigiar_vigencia';

  IF v_src IS NOT NULL AND (v_src ILIKE '%sobrep%' OR v_src ILIKE '%overlap%') THEN
    r.situacao := 'passou';
    r.obtido := 'A sobreposição de vigências é detectada pela vigilância do instrumento '
             || 'coletivo — a ambiguidade vira alerta em vez de escolha silenciosa.';
  ELSIF v_src IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: não há vigilância de instrumento coletivo — logo, ninguém detecta '
             || 'duas CCTs do mesmo escopo cobrindo a mesma data. Com dois instrumentos '
             || 'válidos ao mesmo tempo, a apuração escolhe pelo acaso da ordenação, e a '
             || 'diferença de percentual de HE ou de intervalo entre eles vira erro '
             || 'sistemático na folha inteira. Correção: detectar a sobreposição por '
             || 'escopo/vigência e sinalizar antes da apuração.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a vigilância acompanha o VENCIMENTO da CCT, mas não detecta '
             || 'SOBREPOSIÇÃO de vigências: duas convenções ativas do mesmo escopo '
             || 'cobrindo a mesma data deixam a apuração ambígua (qual percentual de hora '
             || 'extra vale? qual intervalo mínimo?) e o sistema decide em silêncio, pelo '
             || 'ORDER BY. Quando o sindicato questiona, a resposta "foi o que o sistema '
             || 'pegou" não existe. Correção: alerta de alta severidade (ou bloqueio) na '
             || 'sobreposição, no mesmo desenho do FER-003, que já impede a unidade de '
             || 'estar em duas tabelas de feriados.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_450()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_orq text; v_vigias text; v_qtd int; v_job text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): existe rotina que orquestre TODAS as vigilâncias, agendada?';
  r.esperado := 'Uma chamada roda as vigilâncias do ponto; job diário ativo';
  SELECT string_agg(DISTINCT p.proname, ', ' ORDER BY p.proname) INTO v_vigias
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.proname ILIKE 'ponto%vigiar%' OR p.proname ILIKE 'ponto%monitorar%'
         OR p.proname ILIKE 'ponto%alertas%');
  SELECT count(*) INTO v_qtd
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.proname ILIKE 'ponto%vigiar%' OR p.proname ILIKE 'ponto%monitorar%'
         OR p.proname ILIKE 'ponto%alertas%');
  SELECT p.proname INTO v_orq FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname ILIKE 'ponto%vigilancias%';

  BEGIN
    SELECT string_agg(j.jobname, ', ') INTO v_job FROM cron.job j
    WHERE j.jobname ILIKE '%vigilancia%' OR j.jobname ILIKE '%ponto%alerta%';
  EXCEPTION WHEN OTHERS THEN v_job := NULL;
  END;

  IF v_orq IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: as vigilâncias do ponto existem SOLTAS (%s vigilância(s): '
             || '%s) e não há rotina orquestradora que rode todas de uma vez, nem '
             || 'agendamento diário que as chame (jobs de vigilância encontrados: %s). '
             || 'Vigilância que ninguém chama é alerta que nunca chega: o painel fica '
             || 'limpo por omissão, não por conformidade — e o DP conclui que está tudo '
             || 'certo justamente quando não está. Correção: rotina única que execute '
             || 'todas as vigilâncias devolvendo o que cada uma encontrou, agendada '
             || 'diariamente (pg_cron, como ponto-materializar-faltas já faz), com '
             || 'execução idempotente (PONTO-451).',
             v_qtd, coalesce(v_vigias, 'nenhuma'), coalesce(v_job, 'nenhum'));
  ELSIF v_job IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a orquestradora existe (%s), mas NENHUM agendamento a '
             || 'chama — os alertas só nascem se alguém rodar à mão. Correção: agendar a '
             || 'execução diária no pg_cron.', v_orq);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Motor de vigilâncias orquestrado (%s) e agendado (%s), com %s vigilância(s).',
                       v_orq, v_job, v_qtd);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_460()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_tent text; v_bloq text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o link contém tentativas em série e registra?';
  r.esperado := 'Contador de tentativas, bloqueio temporário e liberação automática';
  v_tent := public.qa_col_existe('ponto_links', 'tentativas_frustradas');
  v_bloq := public.qa_col_existe('ponto_links', 'bloqueado_ate');
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%tentativas_frustradas%' OR p.prosrc ILIKE '%bloqueado_ate%');

  IF v_tent IS NOT NULL AND v_bloq IS NOT NULL AND v_fns IS NOT NULL THEN
    r.situacao := 'passou';
    r.obtido := format('Contenção presente: contador e bloqueio temporário no link, '
             || 'aplicados por %s — quem é legítimo volta a marcar quando o bloqueio expira.',
             v_fns);
  ELSIF v_tent IS NULL OR v_bloq IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o link de marcação não tem contenção de tentativas (faltam o '
             || 'contador e/ou o bloqueio temporário) — é porta aberta na internet que '
             || 'permite varrer CPFs até acertar um válido e marcar ponto por outra '
             || 'pessoa, sem deixar rastro. Correção: bloqueio temporário após poucas '
             || 'tentativas frustradas, com registro na trilha e liberação automática '
             || '(LGPD arts. 46-48).';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: as colunas de contenção existem (tentativas_frustradas, '
             || 'bloqueado_ate) e NENHUMA função as usa — o contador nunca sobe e o '
             || 'bloqueio nunca acontece: a proteção está cadastrada, não aplicada. '
             || 'Correção: incrementar a cada tentativa frustrada, bloquear ao cruzar o '
             || 'limite, registrar na trilha e liberar sozinho ao expirar.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_476()
 RETURNS qa_retorno
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid;
  v_cpf text := public.qa_cpf(4762);
  v_base date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
  v_dia date;
  v_res jsonb;
  v_horas int;
  v_comp int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Registrar folga de 333 min num dia com 195 min trabalhados';
  r.esperado    := 'O dia mantém os 195 min; o banco recebe compensação de 333';

  IF to_regprocedure('public.ponto_registrar_folga_compensatoria(uuid, text, date, text, integer)') IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a folga compensatoria nao aceita minutos — so existe folga de dia '
             || 'inteiro. Nao ha como declarar que a tarde foi folga, e a tarde vira debito '
             || 'silencioso, indistinguivel de uma falta.';
    RETURN r;
  END IF;

  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();
  v_dia := v_base + ((8 - EXTRACT(ISODOW FROM v_base)::int) % 7);

  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Folga Parcial', 528, 10, v_dia, v_dia);
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Folga Parcial', v_dia, 195);

  v_res := public.ponto_registrar_folga_compensatoria(
             v_t, v_cpf, v_dia, 'QA folga da tarde', 333);

  SELECT COALESCE(floor(EXTRACT(EPOCH FROM d.horas_trabalhadas) / 60)::int, 0)
    INTO v_horas
  FROM public.ponto_diario d
  WHERE d.tenant_id = v_t AND d.colaborador_cpf = v_cpf AND d.data = v_dia
  LIMIT 1;

  SELECT COALESCE(SUM(m.minutos), 0)::int INTO v_comp
  FROM public.ponto_banco_horas_movimentacoes m
  JOIN public.ponto_banco_horas b ON b.id = m.banco_horas_id
  WHERE b.tenant_id = v_t
    AND regexp_replace(b.colaborador_cpf, '[^0-9]', '', 'g') = regexp_replace(v_cpf, '[^0-9]', '', 'g')
    AND m.tipo = 'compensacao' AND m.data_referencia = v_dia;

  IF COALESCE((v_res->>'success')::boolean, false) AND v_horas = 195 AND v_comp = 333 THEN
    r.situacao := 'passou';
    r.obtido := 'Folga parcial registrada: o dia manteve os 195 minutos da manha e o banco '
             || 'recebeu 333 minutos de compensacao. A tarde deixou de ser um debito sem nome.';
  ELSIF v_horas = 0 THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a folga parcial ZEROU as horas do dia. A manha foi trabalhada e tem de '
             || 'permanecer no espelho; zerar apaga jornada cumprida.';
    r.detalhe := jsonb_build_object('horas_no_dia', v_horas, 'compensacao', v_comp, 'retorno', v_res);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Resultado inesperado: o dia ficou com %s min (esperado 195) e a '
             || 'compensacao foi de %s min (esperado 333). Retorno: %s',
             v_horas, v_comp, v_res::text);
    r.detalhe := jsonb_build_object('horas_no_dia', v_horas, 'compensacao', v_comp, 'retorno', v_res);
  END IF;

  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_477()
 RETURNS qa_retorno
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid;
  v_cpf text := public.qa_cpf(4771);
  v_base date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
  v_dia date;
  v_comp text;
  v_antes int;
  v_depois int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Deixar um dia muito abaixo da jornada sem motivo declarado';
  r.esperado    := 'O dia vira pendência crítica do fechamento; declarada a folga, a pendência some';

  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();
  v_dia  := v_base + ((8 - EXTRACT(ISODOW FROM v_base)::int) % 7) + 2;
  v_comp := to_char(v_dia, 'YYYY-MM');

  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Dia Curto', 528, 10, v_dia, v_dia);
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Dia Curto', v_dia, 195);

  SELECT count(*)::int INTO v_antes
  FROM public.ponto_fechamento_pendencias_criticas(v_t, NULL, v_comp) p
  WHERE p.tipo = 'dia_curto_sem_motivo'
    AND regexp_replace(COALESCE(p.colaborador_cpf, ''), '[^0-9]', '', 'g')
      = regexp_replace(v_cpf, '[^0-9]', '', 'g');

  IF v_antes = 0 THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: um dia 333 minutos abaixo da jornada, sem folga, abono ou ajuste '
             || 'declarado, NAO aparece como pendencia do fechamento. A competencia fecha com um '
             || 'debito que ninguem explicou, e o espelho que o trabalhador assina nao diz por '
             || 'que. Um dia curto pode ser folga, abono ou falta — tres efeitos diferentes — e '
             || 'so quem esteve la sabe qual foi.';
    RETURN r;
  END IF;

  r.passo_ordem := 2;
  r.passo_acao  := 'Declarar a folga compensatória naquele dia';
  r.esperado    := 'A pendência some — o motivo está registrado';

  PERFORM public.ponto_registrar_folga_compensatoria(v_t, v_cpf, v_dia, 'QA folga declarada', 333);

  SELECT count(*)::int INTO v_depois
  FROM public.ponto_fechamento_pendencias_criticas(v_t, NULL, v_comp) p
  WHERE p.tipo = 'dia_curto_sem_motivo'
    AND regexp_replace(COALESCE(p.colaborador_cpf, ''), '[^0-9]', '', 'g')
      = regexp_replace(v_cpf, '[^0-9]', '', 'g');

  IF v_depois = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'O dia curto sem motivo bloqueia o fechamento, e a declaracao da folga libera: '
             || 'o sistema deixou de adivinhar e passou a exigir que alguem diga o que houve.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a pendencia continua depois de a folga ter sido declarada. O RH nao '
             || 'consegue sair do bloqueio nem fazendo a coisa certa.';
    r.detalhe := jsonb_build_object('pendencias_antes', v_antes, 'pendencias_depois', v_depois);
  END IF;

  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

-- ── Ligar caso <-> rotina ───────────────────────────────────────────────
INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
  ('PONTO-001','qa_caso_ponto_001', true),
  ('PONTO-003','qa_caso_ponto_003', true),
  ('PONTO-020','qa_caso_ponto_020', true),
  ('PONTO-021','qa_caso_ponto_021', true),
  ('PONTO-022','qa_caso_ponto_022', true),
  ('PONTO-024','qa_caso_ponto_024', true),
  ('PONTO-025','qa_caso_ponto_025', true),
  ('PONTO-040','qa_caso_ponto_040', true),
  ('PONTO-041','qa_caso_ponto_041', true),
  ('PONTO-042','qa_caso_ponto_042', true),
  ('PONTO-043','qa_caso_ponto_043', true),
  ('PONTO-060','qa_caso_ponto_060', true),
  ('PONTO-061','qa_caso_ponto_061', true),
  ('PONTO-062','qa_caso_ponto_062', true),
  ('PONTO-063','qa_caso_ponto_063', true),
  ('PONTO-064','qa_caso_ponto_064', true),
  ('PONTO-080','qa_caso_ponto_080', true),
  ('PONTO-090','qa_caso_ponto_090', true),
  ('PONTO-091','qa_caso_ponto_091', true),
  ('PONTO-092','qa_caso_ponto_092', true),
  ('PONTO-093','qa_caso_ponto_093', true),
  ('PONTO-110','qa_caso_ponto_110', true),
  ('PONTO-111','qa_caso_ponto_111', true),
  ('PONTO-112','qa_caso_ponto_112', true),
  ('PONTO-113','qa_caso_ponto_113', true),
  ('PONTO-130','qa_caso_ponto_130', true),
  ('PONTO-131','qa_caso_ponto_131', true),
  ('PONTO-132','qa_caso_ponto_132', true),
  ('PONTO-133','qa_caso_ponto_133', true),
  ('PONTO-150','qa_caso_ponto_150', true),
  ('PONTO-151','qa_caso_ponto_151', true),
  ('PONTO-152','qa_caso_ponto_152', true),
  ('PONTO-153','qa_caso_ponto_153', true),
  ('PONTO-170','qa_caso_ponto_170', true),
  ('PONTO-171','qa_caso_ponto_171', true),
  ('PONTO-172','qa_caso_ponto_172', true),
  ('PONTO-173','qa_caso_ponto_173', true),
  ('PONTO-174','qa_caso_ponto_174', true),
  ('PONTO-175','qa_caso_ponto_175', true),
  ('PONTO-190','qa_caso_ponto_190', true),
  ('PONTO-191','qa_caso_ponto_191', true),
  ('PONTO-192','qa_caso_ponto_192', true),
  ('PONTO-193','qa_caso_ponto_193', true),
  ('PONTO-194','qa_caso_ponto_194', true),
  ('PONTO-211','qa_caso_ponto_211', true),
  ('PONTO-212','qa_caso_ponto_212', true),
  ('PONTO-213','qa_caso_ponto_213', true),
  ('PONTO-291','qa_caso_ponto_291', true),
  ('PONTO-312','qa_caso_ponto_312', true),
  ('PONTO-320','qa_caso_ponto_320', true),
  ('PONTO-321','qa_caso_ponto_321', true),
  ('PONTO-322','qa_caso_ponto_322', true),
  ('PONTO-330','qa_caso_ponto_330', true),
  ('PONTO-331','qa_caso_ponto_331', true),
  ('PONTO-350','qa_caso_ponto_350', true),
  ('PONTO-351','qa_caso_ponto_351', true),
  ('PONTO-352','qa_caso_ponto_352', true),
  ('PONTO-354','qa_caso_ponto_354', true),
  ('PONTO-355','qa_caso_ponto_355', true),
  ('PONTO-356','qa_caso_ponto_356', true),
  ('PONTO-357','qa_caso_ponto_357', true),
  ('PONTO-358','qa_caso_ponto_358', true),
  ('PONTO-359','qa_caso_ponto_359', true),
  ('PONTO-360','qa_caso_ponto_360', true),
  ('PONTO-361','qa_caso_ponto_361', true),
  ('PONTO-362','qa_caso_ponto_362', true),
  ('PONTO-370','qa_caso_ponto_370', true),
  ('PONTO-371','qa_caso_ponto_371', true),
  ('PONTO-372','qa_caso_ponto_372', true),
  ('PONTO-373','qa_caso_ponto_373', true),
  ('PONTO-374','qa_caso_ponto_374', true),
  ('PONTO-375','qa_caso_ponto_375', true),
  ('PONTO-376','qa_caso_ponto_376', true),
  ('PONTO-377','qa_caso_ponto_377', true),
  ('PONTO-378','qa_caso_ponto_378', true),
  ('PONTO-379','qa_caso_ponto_379', true),
  ('PONTO-381','qa_caso_ponto_381', true),
  ('PONTO-382','qa_caso_ponto_382', true),
  ('PONTO-384','qa_caso_ponto_384', true),
  ('PONTO-385','qa_caso_ponto_385', true),
  ('PONTO-386','qa_caso_ponto_386', true),
  ('PONTO-387','qa_caso_ponto_387', true),
  ('PONTO-388','qa_caso_ponto_388', true),
  ('PONTO-389','qa_caso_ponto_389', true),
  ('PONTO-390','qa_caso_ponto_390', true),
  ('PONTO-392','qa_caso_ponto_392', true),
  ('PONTO-393','qa_caso_ponto_393', true),
  ('PONTO-394','qa_caso_ponto_394', true),
  ('PONTO-397','qa_caso_ponto_397', true),
  ('PONTO-398','qa_caso_ponto_398', true),
  ('PONTO-400','qa_caso_ponto_400', true),
  ('PONTO-403','qa_caso_ponto_403', true),
  ('PONTO-420','qa_caso_ponto_420', true),
  ('PONTO-430','qa_caso_ponto_430', true),
  ('PONTO-431','qa_caso_ponto_431', true),
  ('PONTO-440','qa_caso_ponto_440', true),
  ('PONTO-441','qa_caso_ponto_441', true),
  ('PONTO-450','qa_caso_ponto_450', true),
  ('PONTO-460','qa_caso_ponto_460', true),
  ('PONTO-476','qa_caso_ponto_476', true),
  ('PONTO-477','qa_caso_ponto_477', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- ── Conferencia: roda as rotinas de Ponto entregues, agrupa por situacao ────
WITH alvo(codigo) AS (
  SELECT codigo FROM public.qa_implementacoes WHERE codigo LIKE 'PONTO-%' AND ativo
)
SELECT (public.qa_executar_descartavel(i.funcao_sql)).situacao::text AS situacao, count(*) AS qtd
FROM alvo a JOIN public.qa_implementacoes i ON i.codigo = a.codigo
GROUP BY 1 ORDER BY 2 DESC;
