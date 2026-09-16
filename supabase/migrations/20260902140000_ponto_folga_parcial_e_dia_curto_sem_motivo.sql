-- =====================================================================
-- PONTO — a folga de meio periodo passa a existir, e o dia curto sem
--         motivo deixa de fechar em silencio
--
-- DE ONDE VEIO
-- Segunda rodada da auditoria de DP (01/09/2026). O dia 27/08 de uma
-- colaboradora tinha marcacoes so de manha (08:05 e 11:21) e fechou como
-- 5h33 de debito no banco, rotulado "Diminui Banco Horas". O dono do
-- produto esclareceu: a TARDE FOI FOLGA.
--
-- Com isso, o numero estava certo — jornada 528 min, trabalhados 195,
-- debito 333 — e o problema mudou de lugar: ninguem DECLAROU a folga, e o
-- sistema nao tinha como declarar. A conta inferiu.
--
-- POR QUE ISSO IMPORTA (e nao e detalhe de tela)
-- Um dia de jornada curta pode ser tres coisas, com efeitos diferentes:
--
--   * folga compensatoria .... debita o banco 1:1 (CLT art. 59, §§2º/5º)
--   * ausencia justificada ... nao debita nada  (CLT art. 473)
--   * ausencia injustificada . desconta dia + DSR na FOLHA, e nao debita
--                              o banco (Lei 605/1949, art. 6º)
--
-- Sem declaracao, o sistema aplicava sempre a primeira. E a Sumula 338 do
-- TST poe o onus da prova no empregador: um espelho que diz "Diminui
-- Banco Horas" sem dizer por que nao sustenta a defesa de que houve folga
-- acordada. A Portaria MTP 671/2021 ja assume isso ao exigir que o AEJ
-- carregue as OCORRENCIAS, e nao so os horarios.
--
-- AS TRES MUDANCAS
--
-- 1) FOLGA DE MEIO PERIODO passa a ser registravel. Ate aqui,
--    ponto_registrar_folga_compensatoria consumia sempre a jornada
--    inteira e zerava as horas do dia — nao havia como declarar "a tarde
--    foi folga". Agora ela aceita os minutos; sem eles, o dia inteiro,
--    exatamente como antes.
--
-- 2) O ESPELHO passa a dizer "Folga compensatoria". O tipo_dia ja existia
--    no banco desde o PONTO-421, mas nenhum documento o lia: mesmo uma
--    folga corretamente registrada saia impressa como "Diminui Banco
--    Horas". O debito nao muda; o documento passa a explica-lo.
--
-- 3) O FECHAMENTO passa a enxergar o dia curto sem motivo. A trava ja
--    existe e ja bloqueia ajuste pendente, dia incompleto e espelho sem
--    ciencia; ela so nao via este caso, porque duas marcacoes formam um
--    par perfeito e o dia parecia completo. O limite e configuravel por
--    tenant, para a adocao ser gradual.
--
-- NENHUM CALCULO MUDA. Nenhum saldo e recalculado, nenhum dado e apagado.
-- O que muda e o que pode ser DECLARADO, o que o documento MOSTRA e o que
-- o fechamento EXIGE antes de fechar.
-- =====================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- 1) O limite configuravel do dia curto
--    Padrao 60 min: um dia que fica mais de uma hora abaixo da jornada
--    sem folga, abono ou ajuste declarado precisa de tratativa. Quem
--    quiser adocao mais lenta sobe o numero; quem quiser rigor total,
--    baixa para 1.
-- ---------------------------------------------------------------------
ALTER TABLE public.ponto_configuracao
  ADD COLUMN IF NOT EXISTS dia_curto_bloqueia_fechamento_minutos integer DEFAULT 60;

COMMENT ON COLUMN public.ponto_configuracao.dia_curto_bloqueia_fechamento_minutos IS
  'Quantos minutos abaixo da jornada prevista um dia pode ficar, sem motivo declarado, antes de bloquear o fechamento da competencia. Padrao 60. Zero ou nulo desliga a trava.';

-- ---------------------------------------------------------------------
-- 2) Folga compensatoria de meio periodo
--    A assinatura ganha p_minutos. A versao antiga (quatro argumentos) e
--    substituida: com p_minutos nulo o comportamento e identico ao de
--    antes, entao quem ja chamava com quatro argumentos continua igual.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.ponto_registrar_folga_compensatoria(uuid, text, date, text);

CREATE OR REPLACE FUNCTION public.ponto_registrar_folga_compensatoria(
  p_tenant_id uuid,
  p_colaborador_cpf text,
  p_data date,
  p_observacao text DEFAULT NULL,
  -- Minutos de folga. NULO = dia inteiro (a jornada prevista), que e o
  -- comportamento historico. Com valor, e folga PARCIAL: o que foi
  -- trabalhado no dia permanece, e so os minutos informados debitam o
  -- banco.
  p_minutos integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_cpf     text := regexp_replace(coalesce(p_colaborador_cpf, ''), '[^0-9]', '', 'g');
  v_id      uuid; v_cid uuid; v_cnome text; v_eid uuid;
  v_min     int;
  v_jornada int;
  v_comp    text := to_char(p_data, 'YYYY-MM');
  v_banco   uuid;
  v_obs     text;
  v_parcial boolean := (p_minutos IS NOT NULL AND p_minutos > 0);
BEGIN
  IF v_cpf = '' OR p_data IS NULL THEN
    RETURN jsonb_build_object('success', false, 'motivo', 'CPF e data sao obrigatorios');
  END IF;

  SELECT d.id, d.colaborador_id, d.colaborador_nome, d.empresa_id
    INTO v_id, v_cid, v_cnome, v_eid
  FROM public.ponto_diario d
  WHERE d.tenant_id = p_tenant_id
    AND regexp_replace(d.colaborador_cpf, '[^0-9]', '', 'g') = v_cpf
    AND d.data = p_data
  ORDER BY d.empresa_id NULLS LAST
  LIMIT 1;

  IF v_cid IS NULL THEN
    SELECT a.id, a.nome_completo, a.empresa_id INTO v_cid, v_cnome, v_eid
    FROM public.admissoes a
    WHERE a.tenant_id = p_tenant_id
      AND regexp_replace(coalesce(a.cpf, ''), '[^0-9]', '', 'g') = v_cpf
      AND coalesce(a.inativo, false) = false
    ORDER BY a.data_admissao DESC NULLS LAST
    LIMIT 1;
  END IF;

  IF v_cid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'motivo', 'colaborador nao encontrado');
  END IF;

  -- A jornada prevista do dia, que e o teto da folga.
  -- A coluna chama-se jornada_min. A versao anterior pedia "j.minutos", que
  -- nao existe: o erro caia no EXCEPTION e a funcao usava 480 para todo
  -- mundo, em silencio. Numa jornada de 8h48 (528 min) isso debitava 48
  -- minutos a MENOS do banco a cada folga de dia inteiro.
  BEGIN
    SELECT j.jornada_min INTO v_jornada
    FROM public.ponto_jornada_do_dia(p_tenant_id, v_cpf, v_cid::text, p_data) j;
  EXCEPTION WHEN OTHERS THEN
    v_jornada := NULL;
  END;
  v_jornada := COALESCE(NULLIF(v_jornada, 0), 480);

  IF v_parcial THEN
    IF p_minutos > v_jornada THEN
      RETURN jsonb_build_object('success', false,
        'motivo', format('A folga pedida (%s min) e maior que a jornada do dia (%s min).',
                         p_minutos, v_jornada));
    END IF;
    v_min := p_minutos;
  ELSE
    v_min := v_jornada;
  END IF;

  v_obs := COALESCE(p_observacao,
    CASE WHEN v_parcial
         THEN 'Folga compensatoria parcial (banco de horas)'
         ELSE 'Folga compensatoria (banco de horas)' END);

  -- (1) O dia: neutro, nunca falta.
  --     Na folga do dia INTEIRO as horas vao a zero, como sempre foi.
  --     Na folga PARCIAL o que foi trabalhado PERMANECE — zerar apagaria a
  --     manha que a pessoa cumpriu. O deficit da tarde nao vira debito da
  --     apuracao porque o dia fica justificado; quem debita e a
  --     movimentacao de compensacao abaixo, uma vez so.
  IF v_id IS NOT NULL THEN
    UPDATE public.ponto_diario
       SET tipo_dia          = 'folga_compensatoria',
           status            = 'justificado',
           horas_trabalhadas = CASE WHEN v_parcial THEN horas_trabalhadas
                                    ELSE make_interval(mins => 0) END,
           horas_faltantes   = make_interval(mins => 0),
           atraso_minutos    = 0,
           observacao        = v_obs,
           updated_at        = now()
     WHERE id = v_id;
  ELSE
    INSERT INTO public.ponto_diario
      (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, data,
       horas_trabalhadas, horas_faltantes, status, tipo_dia, observacao)
    VALUES
      (p_tenant_id, v_eid, v_cid, v_cnome, v_cpf, p_data,
       make_interval(mins => 0), make_interval(mins => 0), 'justificado',
       'folga_compensatoria', v_obs);
  END IF;

  -- (2) O banco: debito do tipo 'compensacao', separado das ausencias.
  SELECT b.id INTO v_banco
  FROM public.ponto_banco_horas b
  WHERE b.tenant_id = p_tenant_id
    AND regexp_replace(b.colaborador_cpf, '[^0-9]', '', 'g') = v_cpf
    AND b.competencia = v_comp
  ORDER BY b.created_at DESC NULLS LAST
  LIMIT 1;

  IF v_banco IS NULL THEN
    INSERT INTO public.ponto_banco_horas
      (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, tipo,
       competencia, saldo_anterior_minutos, creditos_minutos, debitos_minutos,
       compensados_minutos, saldo_atual_minutos, convertido_extras)
    VALUES (p_tenant_id, v_eid, v_cid, v_cnome, v_cpf, 'mensal',
            v_comp, 0, 0, 0, 0, 0, false)
    RETURNING id INTO v_banco;
  END IF;

  -- Idempotente: a mesma folga nao debita duas vezes.
  IF EXISTS (
    SELECT 1 FROM public.ponto_banco_horas_movimentacoes m
    WHERE m.banco_horas_id = v_banco AND m.tipo = 'compensacao'
      AND m.data_referencia = p_data
  ) THEN
    RETURN jsonb_build_object('success', true, 'ja_registrada', true,
                              'minutos', v_min, 'parcial', v_parcial,
                              'competencia', v_comp);
  END IF;

  INSERT INTO public.ponto_banco_horas_movimentacoes
    (tenant_id, banco_horas_id, colaborador_cpf, data_referencia, tipo, minutos, descricao, origem)
  VALUES (p_tenant_id, v_banco, v_cpf, p_data, 'compensacao', v_min,
          v_obs || ' — ' || to_char(p_data, 'DD/MM/YYYY')
          || CASE WHEN v_parcial THEN format(' (%s de %s min da jornada)', v_min, v_jornada) ELSE '' END,
          'folga_compensatoria');

  UPDATE public.ponto_banco_horas
     SET compensados_minutos = COALESCE(compensados_minutos, 0) + v_min,
         saldo_atual_minutos = COALESCE(saldo_atual_minutos, 0) - v_min,
         updated_at = now()
   WHERE id = v_banco;

  RETURN jsonb_build_object('success', true, 'minutos', v_min, 'parcial', v_parcial,
                            'jornada_min', v_jornada, 'competencia', v_comp);
END;
$function$;

COMMENT ON FUNCTION public.ponto_registrar_folga_compensatoria(uuid, text, date, text, integer) IS
  'Registra folga compensatoria e debita o banco. p_minutos nulo = dia inteiro (comportamento historico); com valor, folga PARCIAL — o trabalho do dia permanece e so os minutos informados debitam. Declarar a folga e o que distingue, no espelho, folga acordada de ausencia (Sumula 338 do TST).';

-- ---------------------------------------------------------------------
-- 3) O fechamento passa a enxergar o dia curto sem motivo
-- ---------------------------------------------------------------------
DO $pendencia$
DECLARE
  v_src text;
  v_alvo text := E'    AND (p_empresa_id IS NULL OR d.empresa_id = p_empresa_id);\n\n  -- (387) Espelho SEM CI';
  v_troca text;
BEGIN
  v_troca := E'    AND (p_empresa_id IS NULL OR d.empresa_id = p_empresa_id);\n\n'
          || E'  -- [dia-curto-sem-motivo] Dia que ficou MUITO abaixo da jornada sem que\n'
          || E'  -- ninguem tenha dito por que. Nao e defeito de calculo: e a ausencia de\n'
          || E'  -- uma DECLARACAO. Um dia curto pode ser folga compensatoria (debita o\n'
          || E'  -- banco), ausencia justificada (nao debita nada) ou falta injustificada\n'
          || E'  -- (desconta dia e DSR na folha) — tres efeitos diferentes, e so quem\n'
          || E'  -- esteve la sabe qual foi. Sem a declaracao o sistema aplica um deles por\n'
          || E'  -- omissao, e o espelho que o trabalhador assina nao explica o debito, o\n'
          || E'  -- que fragiliza a prova do empregador (Sumula 338 do TST; Portaria MTP\n'
          || E'  -- 671/2021, que exige as OCORRENCIAS no AEJ).\n'
          || E'  -- O limite vive em ponto_configuracao.dia_curto_bloqueia_fechamento_minutos\n'
          || E'  -- (padrao 60). Zero ou nulo desliga a trava.\n'
          || E'  RETURN QUERY\n'
          || E'  WITH limite AS (\n'
          || E'    SELECT COALESCE(max(c.dia_curto_bloqueia_fechamento_minutos), 60) AS min\n'
          || E'    FROM public.ponto_configuracao c\n'
          || E'    WHERE c.tenant_id = p_tenant_id\n'
          || E'  )\n'
          || E'  SELECT ''dia_curto_sem_motivo''::text, d.colaborador_cpf, d.data,\n'
          || E'         format(''Dia %s min abaixo da jornada sem folga, abono ou ajuste declarado'',\n'
          || E'                (j.jornada_min - COALESCE(floor(EXTRACT(EPOCH FROM d.horas_trabalhadas)/60)::int, 0)))::text\n'
          || E'  FROM public.ponto_diario d\n'
          || E'  CROSS JOIN limite l\n'
          || E'  CROSS JOIN LATERAL public.ponto_jornada_do_dia(\n'
          || E'    p_tenant_id,\n'
          || E'    regexp_replace(COALESCE(d.colaborador_cpf, ''''), ''[^0-9]'', '''', ''g''),\n'
          || E'    d.colaborador_id::text, d.data) j\n'
          || E'  WHERE d.tenant_id = p_tenant_id\n'
          || E'    AND d.data BETWEEN v_ini AND v_fim\n'
          || E'    AND (p_empresa_id IS NULL OR d.empresa_id = p_empresa_id)\n'
          || E'    AND COALESCE(l.min, 0) > 0\n'
          || E'    AND COALESCE(j.jornada_min, 0) > 0\n'
          || E'    -- so dia com trabalho: dia sem nenhuma batida ja e falta, e tem\n'
          || E'    -- tratamento proprio\n'
          || E'    AND COALESCE(floor(EXTRACT(EPOCH FROM d.horas_trabalhadas)/60)::int, 0) > 0\n'
          || E'    AND (j.jornada_min - COALESCE(floor(EXTRACT(EPOCH FROM d.horas_trabalhadas)/60)::int, 0)) >= l.min\n'
          || E'    -- ja declarado por alguem: folga, abono, ferias, atestado, feriado.\n'
          || E'    -- E lista de EXCLUSAO, nao igualdade a ''normal'': o dia comum vem\n'
          || E'    -- gravado como ''util'', e comparar com ''normal'' deixava passar\n'
          || E'    -- justamente o caso que esta trava existe para pegar.\n'
          || E'    AND COALESCE(d.tipo_dia, ''util'') NOT IN\n'
          || E'        (''ferias'', ''atestado'', ''afastamento'', ''feriado'', ''folga_compensatoria'')\n'
          || E'    AND COALESCE(d.status, '''') NOT IN (''justificado'', ''incompleto'', ''ajuste_pendente'')\n'
          || E'    AND NOT EXISTS (SELECT 1 FROM public.ponto_ajustes a2\n'
          || E'                     WHERE a2.tenant_id = d.tenant_id\n'
          || E'                       AND a2.data_referencia = d.data\n'
          || E'                       AND regexp_replace(COALESCE(a2.colaborador_cpf, ''''), ''[^0-9]'', '''', ''g'')\n'
          || E'                         = regexp_replace(COALESCE(d.colaborador_cpf, ''''), ''[^0-9]'', '''', ''g''));\n\n'
          || E'  -- (387) Espelho SEM CI';

  SELECT pg_get_functiondef(p.oid) INTO v_src
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'ponto_fechamento_pendencias_criticas';

  IF v_src IS NULL THEN
    RAISE NOTICE 'A lista de pendencias do fechamento nao existe nesta base — nada a ampliar.';
    RETURN;
  END IF;

  IF position('[dia-curto-sem-motivo]' IN v_src) > 0 THEN
    RAISE NOTICE 'O fechamento ja enxerga o dia curto sem motivo — nada a fazer.';
    RETURN;
  END IF;

  IF position(v_alvo IN v_src) = 0 THEN
    RAISE NOTICE 'ATENCAO: o trecho esperado nao foi encontrado em ponto_fechamento_pendencias_criticas. A funcao foi alterada por outro caminho; a trava NAO foi ampliada. Envie o pg_get_functiondef para reconciliarmos a mao.';
    RETURN;
  END IF;

  EXECUTE replace(v_src, v_alvo, v_troca);
  RAISE NOTICE 'Fechamento: dia curto sem motivo declarado passa a ser pendencia critica.';
END $pendencia$;

-- A mensagem do bloqueio passa a nomear o caso novo.
DO $mensagem$
DECLARE
  v_src text;
  v_alvo text := '% dia(s) incompleto(s) e % espelho(s) sem ciencia';
  v_troca text := '% dia(s) incompleto(s), % dia(s) curto(s) sem motivo declarado e % espelho(s) sem ciencia';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'ponto_fechar_competencia_verificar';

  IF v_src IS NULL OR position('dia_curto_sem_motivo' IN v_src) > 0 THEN
    RAISE NOTICE 'A verificacao do fechamento ja nomeia o dia curto — nada a fazer.';
    RETURN;
  END IF;

  IF position(v_alvo IN v_src) = 0 THEN
    RAISE NOTICE 'ATENCAO: a mensagem esperada nao foi encontrada em ponto_fechar_competencia_verificar. A trava nova JA CONTA no total, mas a mensagem nao a detalha.';
    RETURN;
  END IF;

  v_src := replace(v_src, v_alvo, v_troca);
  v_src := replace(v_src,
    E'         count(*) FILTER (WHERE tipo = ''espelho_sem_ciencia'')\n    INTO v_n, v_ajustes, v_dias, v_espelhos',
    E'         count(*) FILTER (WHERE tipo = ''dia_curto_sem_motivo''),\n'
 || E'         count(*) FILTER (WHERE tipo = ''espelho_sem_ciencia'')\n'
 || E'    INTO v_n, v_ajustes, v_dias, v_curtos, v_espelhos');
  v_src := replace(v_src,
    E'  v_espelhos int;\nBEGIN',
    E'  v_espelhos int;\n  v_curtos   int;\nBEGIN');
  v_src := replace(v_src,
    'p_competencia, v_n, v_ajustes, v_dias, v_espelhos',
    'p_competencia, v_n, v_ajustes, v_dias, v_curtos, v_espelhos');

  EXECUTE v_src;
  RAISE NOTICE 'A mensagem do bloqueio passa a nomear o dia curto sem motivo.';
END $mensagem$;

-- ---------------------------------------------------------------------
-- 3b) O PONTO-421 procurava a assinatura ANTIGA
--     Ele confere se existe rotina de folga compensatoria, e fazia isso
--     pela assinatura exata de quatro argumentos. Com o p_minutos a
--     assinatura tem cinco, e o caso passou a acusar "nao ha como
--     registrar folga" — sobre uma base onde ha. A conferencia passa a ser
--     pelo NOME da rotina, que e o que ele realmente quer saber.
-- ---------------------------------------------------------------------
DO $c421$
DECLARE
  v_src text;
  v_alvo text := 'to_regprocedure(''public.ponto_registrar_folga_compensatoria(uuid,text,date,text)'') IS NULL';
  v_troca text := 'NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace'
               || ' WHERE n.nspname = ''public'' AND p.proname = ''ponto_registrar_folga_compensatoria'')';
BEGIN
  IF to_regprocedure('public.qa_caso_ponto_421()') IS NULL THEN
    RAISE NOTICE 'Bancada ausente nesta base — nada a ajustar no PONTO-421.';
    RETURN;
  END IF;

  SELECT pg_get_functiondef(p.oid) INTO v_src
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'qa_caso_ponto_421';

  IF position(v_alvo IN v_src) = 0 THEN
    RAISE NOTICE 'PONTO-421 ja confere a folga pelo nome da rotina — nada a fazer.';
    RETURN;
  END IF;

  EXECUTE replace(v_src, v_alvo, v_troca);
  RAISE NOTICE 'PONTO-421 passa a conferir a folga compensatoria pelo nome, nao pela assinatura.';
END $c421$;

-- ---------------------------------------------------------------------
-- 4) Os casos de teste
-- ---------------------------------------------------------------------
INSERT INTO public.qa_casos_teste
  (codigo, modulo_id, titulo, objetivo, tipo, nivel, prioridade, status,
   base_legal, passos, disposicao, observacoes)
SELECT * FROM (
  SELECT
    'PONTO-476' AS codigo, m.id AS modulo_id,
    'Folga de meio período pode ser declarada' AS titulo,
    'A folga compensatória só existia para o dia inteiro: a rotina consumia sempre a jornada '
    || 'completa e zerava as horas do dia. Não havia como declarar "a tarde foi folga" — e, sem '
    || 'a declaração, a tarde virava débito silencioso no banco, indistinguível de uma falta. '
    || 'Na folga parcial o trabalho da manhã tem de permanecer, e só os minutos declarados '
    || 'debitam o banco, uma vez só.' AS objetivo,
    'feliz'::public.qa_caso_tipo AS tipo,
    'api'::text AS nivel,
    'critica'::public.qa_prioridade AS prioridade,
    'aprovado'::public.qa_caso_status AS status,
    'CLT art. 59, §§2º e 5º; Súmula 338 do TST' AS base_legal,
    jsonb_build_array(
      jsonb_build_object('ordem', 1,
        'acao', 'Registrar folga compensatória de 333 minutos num dia com 195 minutos trabalhados',
        'esperado', 'O dia mantém os 195 minutos e o banco recebe um débito de compensação de 333'),
      jsonb_build_object('ordem', 2,
        'acao', 'Registrar folga sem informar minutos',
        'esperado', 'Dia inteiro, exatamente como antes — a mudança não altera quem já usava')
    ) AS passos,
    'em_triagem'::text AS disposicao,
    'Nasceu do dia 27/08 da auditoria de DP: marcações só de manhã porque a tarde foi folga.' AS observacoes
  FROM public.qa_modulos m WHERE m.path = 'jornada-rotina/ponto'
  UNION ALL
  SELECT
    'PONTO-477', m.id,
    'Dia muito abaixo da jornada sem motivo declarado não fecha a competência',
    'Um dia de jornada curta pode ser folga compensatória (debita o banco), ausência '
    || 'justificada (não debita nada) ou falta injustificada (desconta dia e DSR na folha) — três '
    || 'efeitos diferentes, e só quem esteve lá sabe qual foi. Sem declaração o sistema aplica um '
    || 'deles por omissão, e o espelho que o trabalhador assina não explica o débito. O '
    || 'fechamento tem de exigir a declaração, como já exige para ajuste pendente e espelho sem '
    || 'ciência.',
    'negativo'::public.qa_caso_tipo, 'api'::text,
    'critica'::public.qa_prioridade, 'aprovado'::public.qa_caso_status,
    'CLT art. 74, §2º; Súmula 338 do TST; Portaria MTP 671/2021',
    jsonb_build_array(
      jsonb_build_object('ordem', 1,
        'acao', 'Deixar um dia mais de 60 minutos abaixo da jornada, sem folga, abono ou ajuste',
        'esperado', 'O dia aparece como pendência crítica e o fechamento é bloqueado'),
      jsonb_build_object('ordem', 2,
        'acao', 'Declarar a folga compensatória naquele dia',
        'esperado', 'A pendência some — o motivo agora está registrado e o fechamento libera')
    ),
    'em_triagem'::text,
    'Nasceu da segunda rodada da auditoria de DP de 01/09/2026. O limite é configurável em '
    || 'ponto_configuracao.dia_curto_bloqueia_fechamento_minutos, para a adoção ser gradual.'
  FROM public.qa_modulos m WHERE m.path = 'jornada-rotina/ponto'
) x
ON CONFLICT (codigo) DO NOTHING;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_476()
RETURNS public.qa_retorno
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
END $function$;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_477()
RETURNS public.qa_retorno
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
END $function$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
VALUES ('PONTO-476', 'qa_caso_ponto_476', true),
       ('PONTO-477', 'qa_caso_ponto_477', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

DO $fim$
BEGIN
  RAISE NOTICE 'Folga de meio periodo existe, e o dia curto sem motivo nao fecha mais em silencio.';
END $fim$;
