-- ============================================================================
-- QA — LOTE 5 (FERIAS): entregar a familia Ferias a producao, com o AJUSTE das
-- sondas. ~7 rotinas pegavam um tenant REAL (FROM public.tenants LIMIT 1), que
-- o modo-QA da producao bloqueia; aqui elas usam qa_sandbox_tenant_id() (cercado
-- + satisfaz a FK). As demais vao como no dev. Aditivo (CREATE OR REPLACE) +
-- vinculo. Read-only. Conferencia agrupa por situacao.
-- OBS: FERIAS-015 continua 'falhou' de proposito — e ACHADO REAL (trava etaria
-- legada), esta no relatorio; nao e drift.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_001()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_cpf text := public.qa_cpf(40001); v_id uuid; v_direito numeric;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem := 1;
  r.passo_acao := 'Gravar período aquisitivo com 8 faltas e direito INCOERENTE de 30 dias';
  r.esperado := 'O banco deriva ou recusa: com 8 faltas, o art. 130 dá 24 dias';
  INSERT INTO public.ferias_periodos_aquisitivos
    (tenant_id, colaborador_cpf, colaborador_nome, data_admissao,
     aquisitivo_inicio, aquisitivo_fim, faltas_carga, dias_gozados,
     fonte_faltas, dias_direito, dias_saldo, faltas_consideradas, status, origem)
  VALUES (v_t, v_cpf, '[QA-FERIAS] Oito Faltas', CURRENT_DATE - interval '2 years',
          CURRENT_DATE - interval '2 years', CURRENT_DATE - interval '1 year',
          8, 0, 'carga', 30, 30, 8, 'ativo', 'manual')
  RETURNING id INTO v_id;

  SELECT dias_direito INTO v_direito FROM public.ferias_periodos_aquisitivos WHERE id = v_id;
  IF v_direito = 24 THEN
    r.situacao := 'passou';
    r.obtido := 'O banco corrigiu o direito para 24 dias — a escala do art. 130 é garantida na escrita.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('O BANCO ACEITOU direito de %s dias com 8 faltas — o art. 130 manda 24. '
      'A função ferias_dias_por_faltas_clt existe e está correta, mas nada obriga o dado gravado a '
      'passar por ela: entrada manual ou importação grava qualquer número. Correção: trigger '
      'derivando dias_direito das faltas consideradas (com exceção auditada para validação manual).',
      v_direito);
  END IF;
  RETURN r;
EXCEPTION
  WHEN check_violation THEN
    r.situacao := 'passou'; r.obtido := 'Incoerência recusada na escrita.'; RETURN r;
  WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_002()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_err text := '';
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Avaliar ferias_dias_por_faltas_clt nas fronteiras 5/6, 14/15, 23/24, 32/33';
  r.esperado := '30/24, 24/18, 18/12, 12/0 — cada fronteira no degrau certo';

  IF public.ferias_dias_por_faltas_clt(5)  <> 30 THEN v_err := v_err || ' 5->'  || public.ferias_dias_por_faltas_clt(5); END IF;
  IF public.ferias_dias_por_faltas_clt(6)  <> 24 THEN v_err := v_err || ' 6->'  || public.ferias_dias_por_faltas_clt(6); END IF;
  IF public.ferias_dias_por_faltas_clt(14) <> 24 THEN v_err := v_err || ' 14->' || public.ferias_dias_por_faltas_clt(14); END IF;
  IF public.ferias_dias_por_faltas_clt(15) <> 18 THEN v_err := v_err || ' 15->' || public.ferias_dias_por_faltas_clt(15); END IF;
  IF public.ferias_dias_por_faltas_clt(23) <> 18 THEN v_err := v_err || ' 23->' || public.ferias_dias_por_faltas_clt(23); END IF;
  IF public.ferias_dias_por_faltas_clt(24) <> 12 THEN v_err := v_err || ' 24->' || public.ferias_dias_por_faltas_clt(24); END IF;
  IF public.ferias_dias_por_faltas_clt(32) <> 12 THEN v_err := v_err || ' 32->' || public.ferias_dias_por_faltas_clt(32); END IF;
  IF public.ferias_dias_por_faltas_clt(33) <> 0  THEN v_err := v_err || ' 33->' || public.ferias_dias_por_faltas_clt(33); END IF;

  IF v_err = '' THEN
    r.situacao := 'passou';
    r.obtido := 'As oito fronteiras da escala do art. 130 caem no degrau certo.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'FRONTEIRA ERRADA na escala do art. 130:' || v_err || '. Cada erro aqui é dia de férias a mais ou a menos para alguém.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_003()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_olha boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o recálculo do período aquisitivo consulta os afastamentos?';
  r.esperado := 'Benefício previdenciário > 6 meses e licença > 30 dias zeram o aquisitivo (art. 133)';
  SELECT bool_or(p.prosrc ILIKE '%afastament%') INTO v_olha
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN ('ferias_recalcular_periodo', 'ferias_recalcular_empresa');
  IF NOT coalesce(v_olha, false) THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o recálculo de férias não consulta o módulo de Afastamentos — as '
             || 'hipóteses do art. 133 (benefício previdenciário por mais de 6 meses, licença '
             || 'remunerada acima de 30 dias, paralisação > 30 dias) nunca zeram o período '
             || 'aquisitivo. Colaborador que passou 8 meses no INSS volta com o aquisitivo '
             || 'contando como se nada houvesse. Correção: cruzar afastamentos no recálculo, '
             || 'reiniciando o aquisitivo com a origem registrada.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'O recálculo consulta os afastamentos.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_004()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text := public.qa_cpf(6004); v_aceitou boolean := false;
BEGIN
  PERFORM public.qa_ferias_periodo(v_cpf, 'QA Dois Períodos', 0, CURRENT_DATE - 400);
  PERFORM public.qa_ferias_periodo(v_cpf, 'QA Dois Períodos', 0, CURRENT_DATE - 30);

  r.passo_ordem := 1;
  r.passo_acao := 'Com dois aquisitivos em aberto (um vencendo!), programar férias contra o MAIS NOVO';
  r.esperado := 'Recusado ou alertado — o período antigo é o que vira dobra se vencer';
  BEGIN
    INSERT INTO public.ferias_programacao
      (tenant_id, colaborador_cpf, colaborador_nome,
       aquisitivo_inicio, aquisitivo_fim,
       p1_inicio, p1_fim, p1_dias, abono_vender, abono_dias, adiantar_13, estado)
    VALUES (public.qa_sandbox_tenant_id(), v_cpf, 'QA Dois Períodos',
            CURRENT_DATE - 395, CURRENT_DATE - 30,
            CURRENT_DATE + 40, CURRENT_DATE + 69, 30, false, 0, false, 'planejado');
    v_aceitou := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_aceitou := false; END;

  IF v_aceitou THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: com o período ANTIGO a caminho da dobra, o banco aceitou programação '
             || 'contra o período NOVO sem recusa nem alerta — nada prioriza a baixa do '
             || 'aquisitivo mais antigo (a programação nem referencia formalmente qual período '
             || 'baixa: os campos aquisitivo_inicio/fim são texto livre, sem FK). É o erro '
             || 'mais caro possível: programar contra o novo e deixar o velho vencer em dobro '
             || '(art. 137). Correção: vínculo formal programação → período aquisitivo + '
             || 'trava/alerta priorizando o mais antigo.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'A programação contra o período novo foi recusada/alertada com o antigo em aberto.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_005()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text := public.qa_cpf(6105);
        v_ini date := CURRENT_DATE - 60; v_fim date := CURRENT_DATE - 10; v_n int;
BEGIN
  -- 1 falta injustificada + 1 dia justificado no mesmo intervalo
  PERFORM public.qa_ponto_dia(v_cpf, 'QA Art131', v_ini + 5, NULL, 'falta');
  PERFORM public.qa_ponto_dia(v_cpf, 'QA Art131', v_ini + 6, NULL, 'justificado');

  r.passo_ordem := 1;
  r.passo_acao := 'Contar as faltas do período pela fonte do Ponto (1 falta + 1 dia justificado)';
  r.esperado := 'Conta 1 — ausência amparada (art. 131) não entra na escala do art. 130';
  v_n := public.ferias_faltas_do_ponto(public.qa_sandbox_tenant_id(), v_cpf, v_ini, v_fim);

  IF v_n = 1 THEN
    r.situacao := 'passou';
    r.obtido := 'Só a falta injustificada contou; o dia justificado ficou fora da escala. '
             || 'Ressalva: isso vale quando a fonte é o Ponto — no modo carga (faltas_carga '
             || 'digitadas), a distinção depende de quem digita.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('A contagem devolveu %s (esperado 1). Somar ausência amparada à escala '
             || 'do art. 130 corta férias de quem adoeceu — o art. 131 lista o que NÃO é falta.',
             coalesce(v_n::text, 'NULL'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_006()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_dias int; v_subtrai text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Apurar o direito com 8 faltas: faixa, nunca subtração';
  r.esperado := '24 dias (faixa do art. 130) — jamais 22 (30 - 8)';
  v_dias := public.ferias_dias_por_faltas_clt(8);

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA (somente leitura): alguma função de férias subtrai faltas dos dias?';
  r.esperado := 'Nenhuma — o §1º veda o desconto um-a-um';
  SELECT string_agg(p.proname, ', ') INTO v_subtrai
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname ILIKE '%ferias%' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%- falta%' OR p.prosrc ILIKE '%-falta%');

  IF v_dias = 24 AND v_subtrai IS NULL THEN
    r.situacao := 'passou';
    r.obtido := '8 faltas renderam a faixa de 24 dias e nenhuma função subtrai faltas dos dias '
             || 'de gozo — o §1º do art. 130 está respeitado.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Violação do art. 130, §1º: faixa devolveu %s (esperado 24)%s.',
             coalesce(v_dias::text, 'NULL'),
             CASE WHEN v_subtrai IS NOT NULL
                  THEN format('; função(ões) subtraindo faltas: %s', v_subtrai) ELSE '' END);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_007()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_resq text; v_dias int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): há resquício da tabela do 130-A (tempo parcial, máx. 18 dias)?';
  r.esperado := 'Nenhum — revogada em 2017; o parcial usa a escala geral (30 dias com até 5 faltas)';
  SELECT string_agg(p.proname, ', ') INTO v_resq
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname ILIKE '%ferias%' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%parcial%' OR p.prosrc ILIKE '%130-A%' OR p.prosrc ILIKE '%18 dias%');
  v_dias := public.ferias_dias_por_faltas_clt(0);

  IF v_resq IS NULL AND v_dias = 30 THEN
    r.situacao := 'passou';
    r.obtido := 'Nenhuma tabela de tempo parcial no código e a escala geral devolve 30 dias — '
             || 'contrato parcial recebe férias inteiras, como manda a redação pós-2017 '
             || '(mesmo guarda-corpo do FERIAS-015 contra regra revogada).';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Resquício de regra revogada: %s (escala geral: %s dias). A tabela do '
             || '130-A não pode voltar.', coalesce(v_resq, '—'), coalesce(v_dias::text, '?'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_008()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_est text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o marco prescricional dos períodos é calculado/vigiado?';
  r.esperado := 'Fim do concessivo + 5 anos (2 após a rescisão), com alerta antes de consumar';
  v_est := coalesce(public.qa_col_existe(NULL, '%prescri%'), public.qa_fns_com('%prescri%'));
  IF v_est IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: prescrição não existe no módulo — nenhum campo ou função calcula o '
             || 'marco do art. 149 (fim do concessivo + 5 anos; 2 anos após a extinção do '
             || 'contrato, CF art. 7º XXIX). Período esquecido atravessa o marco sem aviso: '
             || 'vira perda definitiva do trabalhador e evidência de desorganização na '
             || 'fiscalização. Correção: data de prescrição derivada por período, com alerta '
             || 'antecipado a RH/Jurídico.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Prescrição controlada: %s.', v_est);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_010()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text := public.qa_cpf(6010);
        v_aceitou boolean := false; v_concord text;
BEGIN
  PERFORM public.qa_ferias_periodo(v_cpf, 'QA Fraciona OK', 0, CURRENT_DATE - 30);

  r.passo_ordem := 1;
  r.passo_acao := 'Programar a composição LEGAL 14+11+5 (art. 134, §1º)';
  r.esperado := 'Aceita — e com a concordância do empregado registrada como evidência';
  BEGIN
    INSERT INTO public.ferias_programacao
      (tenant_id, colaborador_cpf, colaborador_nome, aquisitivo_inicio, aquisitivo_fim,
       p1_inicio, p1_fim, p1_dias, p2_inicio, p2_fim, p2_dias,
       p3_inicio, p3_fim, p3_dias, abono_vender, abono_dias, adiantar_13, estado)
    VALUES (public.qa_sandbox_tenant_id(), v_cpf, 'QA Fraciona OK',
            CURRENT_DATE - 395, CURRENT_DATE - 30,
            CURRENT_DATE + 30, CURRENT_DATE + 43, 14,
            CURRENT_DATE + 90, CURRENT_DATE + 100, 11,
            CURRENT_DATE + 150, CURRENT_DATE + 154, 5,
            false, 0, false, 'planejado');
    v_aceitou := true;
  EXCEPTION WHEN OTHERS THEN v_aceitou := false; END;

  r.passo_ordem := 2;
  r.passo_acao := 'Conferir onde fica registrada a CONCORDÂNCIA do empregado com o fracionamento';
  r.esperado := 'Campo/evidência de concordância — o §1º só permite fracionar com ela';
  v_concord := public.qa_col_existe('ferias_programacao', '%concord%');

  IF v_aceitou AND v_concord IS NOT NULL THEN
    r.situacao := 'passou';
    r.obtido := 'Composição legal aceita com evidência de concordância.';
  ELSIF v_aceitou THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a composição válida 14+11+5 foi aceita, mas NÃO EXISTE campo de '
             || 'concordância do empregado — o art. 134, §1º só admite o fracionamento "desde '
             || 'que haja concordância", e sem a evidência registrada a empresa não prova o '
             || 'requisito em juízo. Correção: campo de concordância (quem, quando, como) '
             || 'obrigatório para programação fracionada.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'A composição LEGAL 14+11+5 foi recusada — validação mais restritiva que a lei.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_011()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_cpf text := public.qa_cpf(40011);
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM public.qa_ferias_periodo(v_cpf, '[QA-FERIAS] Sem Quatorze', 0);

  r.passo_ordem := 1;
  r.passo_acao := 'Programar P1=10, P2=10, P3=10 (soma 30, nenhum período com 14 dias)';
  r.esperado := 'Recusado — o art. 134, §1º exige um período de ao menos 14 dias corridos';
  BEGIN
    INSERT INTO public.ferias_programacao
      (tenant_id, colaborador_cpf, colaborador_nome, aquisitivo_inicio, aquisitivo_fim,
       p1_inicio, p1_fim, p1_dias, p2_inicio, p2_fim, p2_dias, p3_inicio, p3_fim, p3_dias,
       abono_vender, abono_dias, adiantar_13, estado)
    VALUES (v_t, v_cpf, '[QA-FERIAS] Sem Quatorze',
            CURRENT_DATE - interval '13 months', CURRENT_DATE - 30,
            CURRENT_DATE + 30, CURRENT_DATE + 39, 10,
            CURRENT_DATE + 90, CURRENT_DATE + 99, 10,
            CURRENT_DATE + 150, CURRENT_DATE + 159, 10,
            false, 0, false, 'planejado');
    r.situacao := 'falhou';
    r.obtido := 'O BANCO ACEITOU 10+10+10: a soma fecha 30, mas nenhum período atinge os 14 dias '
      'corridos do art. 134, §1º. A regra do fracionamento não existe em nenhuma camada do banco — '
      'é o motor de regras da seção 5 do documento de requisitos, ainda a construir.';
  EXCEPTION WHEN check_violation THEN
    r.situacao := 'passou'; r.obtido := 'Composição sem período de 14 dias recusada.';
  END;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_012()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_cpf text := public.qa_cpf(40012); v_aceitou boolean := false;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM public.qa_ferias_periodo(v_cpf, '[QA-FERIAS] Terceiro Curto', 0);

  r.passo_ordem := 1;
  r.passo_acao := 'Programar P1=20, P2=7, P3=3 (terceiro período abaixo de 5 dias)';
  r.esperado := 'Recusado — todo período do fracionamento tem piso de 5 dias corridos';
  BEGIN
    INSERT INTO public.ferias_programacao
      (tenant_id, colaborador_cpf, colaborador_nome, aquisitivo_inicio, aquisitivo_fim,
       p1_inicio, p1_fim, p1_dias, p2_inicio, p2_fim, p2_dias, p3_inicio, p3_fim, p3_dias,
       abono_vender, abono_dias, adiantar_13, estado)
    VALUES (v_t, v_cpf, '[QA-FERIAS] Terceiro Curto',
            CURRENT_DATE - interval '13 months', CURRENT_DATE - 30,
            CURRENT_DATE + 30, CURRENT_DATE + 49, 20,
            CURRENT_DATE + 90, CURRENT_DATE + 96, 7,
            CURRENT_DATE + 150, CURRENT_DATE + 152, 3,
            false, 0, false, 'planejado');
    v_aceitou := true;
  EXCEPTION WHEN check_violation THEN v_aceitou := false;
  END;

  r.passo_ordem := 2;
  r.passo_acao := 'Conferir o teto estrutural de 3 períodos';
  r.esperado := 'Não existe P4 — a estrutura limita a 3, como manda a lei';
  -- A tabela tem apenas p1/p2/p3: o teto de 3 períodos é estrutural.

  IF NOT v_aceitou THEN
    r.situacao := 'passou';
    r.obtido := 'Período abaixo de 5 dias recusado; teto de 3 períodos garantido pela estrutura.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'O BANCO ACEITOU um período de 3 dias — abaixo do piso de 5 dias corridos do art. 134, §1º. '
      'O lado bom: o teto de 3 períodos é estrutural (só existem P1/P2/P3). Falta o piso por período no motor de regras.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_013()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_cpf text := public.qa_cpf(40013);
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM public.qa_ferias_periodo(v_cpf, '[QA-FERIAS] Sem Saldo', 0);

  r.passo_ordem := 1;
  r.passo_acao := 'Solicitar 42 dias com saldo de 30';
  r.esperado := 'Recusado, com o saldo e o período aquisitivo na mensagem';
  BEGIN
    INSERT INTO public.ferias_solicitacoes
      (tenant_id, colaborador_nome, colaborador_cpf, data_inicio, data_fim,
       dias_solicitados, saldo_dias, status)
    VALUES (v_t, '[QA-FERIAS] Sem Saldo', v_cpf,
            CURRENT_DATE + 30, CURRENT_DATE + 71, 42, 30, 'pendente');
    r.situacao := 'falhou';
    r.obtido := 'O BANCO ACEITOU solicitação de 42 dias com saldo de 30 — a própria linha carrega '
      'as duas colunas (dias_solicitados e saldo_dias) e nada as compara. O direito do art. 130 é '
      'teto duro; a validação vive só na tela. Correção: CHECK (dias_solicitados <= saldo_dias) '
      'como rede mínima, e o motor de regras por cima.';
  EXCEPTION WHEN check_violation THEN
    r.situacao := 'passou'; r.obtido := 'Solicitação acima do saldo recusada.';
  END;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_014()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_cpf text := public.qa_cpf(40014); v_emp uuid; v_feriado date := CURRENT_DATE + 45;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_emp := public.qa_nova_empresa('[QA-FERIAS] Unidade Com Feriado', '11222333040014');
  PERFORM public.qa_feriado_da_unidade(v_emp, v_feriado, '[QA] Feriado Municipal');
  PERFORM public.qa_ferias_periodo(v_cpf, '[QA-FERIAS] Vespera', 0);

  r.passo_ordem := 1;
  r.passo_acao := format('Programar início em %s — 1 dia antes do feriado da unidade (%s)', v_feriado - 1, v_feriado);
  r.esperado := 'Recusado — vedado iniciar nos 2 dias que antecedem feriado (art. 134, §3º)';
  BEGIN
    INSERT INTO public.ferias_programacao
      (tenant_id, empresa_id, colaborador_cpf, colaborador_nome, aquisitivo_inicio, aquisitivo_fim,
       p1_inicio, p1_fim, p1_dias, abono_vender, abono_dias, adiantar_13, estado)
    VALUES (v_t, v_emp, v_cpf, '[QA-FERIAS] Vespera',
            CURRENT_DATE - interval '13 months', CURRENT_DATE - 30,
            v_feriado - 1, v_feriado + 28, 30, false, 0, false, 'planejado');
    r.situacao := 'falhou';
    r.obtido := 'O BANCO ACEITOU férias iniciando na véspera de feriado da unidade — o art. 134, §3º '
      'veda o início nos 2 dias que antecedem feriado ou DSR. A fonte única de feriados por unidade '
      '(RN22, feriados_da_empresa) existe e não é consultada aqui. Correção: validação na programação '
      'usando o calendário da unidade, com sugestão da data válida mais próxima.';
  EXCEPTION WHEN check_violation THEN
    r.situacao := 'passou'; r.obtido := 'Véspera de feriado recusada pelo calendário da unidade.';
  END;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_015()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_n int; v_lista text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): procurar trava por idade nas funções de férias';
  r.esperado := 'Nenhuma — a restrição etária do antigo art. 134, §2º foi revogada pela Lei 13.467/2017';

  -- Corrigido: casa a PALAVRA "idade" (limite de palavra) ou "data_nascimento";
  -- a substring solta pegava severidade/prioridade/unidade/liberalidade e
  -- acusava trava onde não há (falso-positivo).
  SELECT count(*), string_agg(p.proname, ', ')
  INTO v_n, v_lista
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname ILIKE '%ferias%'
    AND p.proname NOT LIKE 'qa\_%'
    AND (pg_get_functiondef(p.oid) ~* '\midade\M'
         OR pg_get_functiondef(p.oid) ILIKE '%data_nascimento%');

  IF v_n = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'Nenhuma função de férias condiciona o gozo à idade — o sistema não carrega a trava revogada (erro comum em legados).';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('POSSÍVEL TRAVA ETÁRIA em %s função(ões) de férias: %s. A obrigação de período único para menor de 18/maior de 50 foi REVOGADA pela Lei 13.467/2017 — conferir e remover se for restrição de gozo.', v_n, v_lista);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_016()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_est text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o domínio de férias conhece o estudante menor de 18?';
  r.esperado := 'Sinalização do colaborador e alerta na janela de programação (art. 136, §2º)';
  v_est := coalesce(public.qa_col_existe(NULL, '%estudante%'),
                    public.qa_fns_com('%estudante%'));
  IF v_est IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nenhum campo registra a condição de estudante — o direito do menor de '
             || '18 de fazer coincidir as férias com as escolares (art. 136, §2º) não tem como '
             || 'ser sinalizado na programação. Correção: flag de estudante no cadastro + '
             || 'alerta na programação de menor de idade fora do recesso escolar.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Condição de estudante presente: %s.', v_est);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_017()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
  r public.qa_retorno;
  v_est text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o cadastro registra vínculo familiar entre colaboradores?';
  r.esperado := 'Familiares na mesma empresa sinalizados para a preferência de coincidência';

  -- Evidência principal: a tabela dedicada. Não depende de nada do motor.
  v_est := CASE WHEN to_regclass('public.ferias_vinculo_familiar') IS NOT NULL
                THEN 'tabela ferias_vinculo_familiar' END;

  -- Plano B (bases antigas, em que o vínculo podia estar como coluna).
  -- Protegido: onde as auxiliares do motor não existem, seguimos sem elas.
  IF v_est IS NULL THEN
    BEGIN
      v_est := COALESCE(public.qa_col_existe(NULL, '%conjuge%'),
                        public.qa_col_existe(NULL, '%familiar%'),
                        public.qa_fns_com('%familiar%ferias%'));
    EXCEPTION WHEN undefined_function THEN
      v_est := NULL;
    END;
  END IF;

  IF v_est IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nenhum campo liga colaboradores da mesma família — a preferência do '
             || 'art. 136, §1º (familiares na mesma empresa tirarem férias juntos, se não '
             || 'prejudicar o serviço) não tem como ser sinalizada na programação. É direito '
             || 'informativo, não bloqueante. Correção: vínculo familiar no cadastro + aviso '
             || 'de coincidência na programação.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Vínculo familiar presente: %s. A regra do art. 136, §1º é avaliada na '
                    || 'programação como informativo.', v_est);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_020()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_cpf text := public.qa_cpf(40020); v_fim date := CURRENT_DATE - interval '13 months';
BEGIN
  PERFORM public.qa_modo_ligar();
  -- aquisitivo terminou há 13 meses: o limite concessivo (12 meses) já venceu
  PERFORM public.qa_ferias_periodo(v_cpf, '[QA-FERIAS] Concessivo Vencido', 0, v_fim::date);

  r.passo_ordem := 1;
  r.passo_acao := 'Programar férias com o limite concessivo já vencido, sem alçada de diretoria';
  r.esperado := 'Bloqueado para perfis comuns — e, quando autorizado, com o custo da dobra exibido (art. 137)';
  BEGIN
    INSERT INTO public.ferias_programacao
      (tenant_id, colaborador_cpf, colaborador_nome, aquisitivo_inicio, aquisitivo_fim,
       p1_inicio, p1_fim, p1_dias, abono_vender, abono_dias, adiantar_13, estado)
    VALUES (v_t, v_cpf, '[QA-FERIAS] Concessivo Vencido',
            v_fim - interval '1 year', v_fim,
            CURRENT_DATE + 30, CURRENT_DATE + 59, 30, false, 0, false, 'planejado');
    r.situacao := 'falhou';
    r.obtido := 'O BANCO ACEITOU programação com o concessivo vencido, sem alçada e sem sinalizar a '
      'dobra: as férias deviam ter sido concedidas nos 12 meses seguintes ao aquisitivo (art. 134) e '
      'agora o pagamento é em dobro (art. 137). Programar sem ver o custo é assinar o passivo no '
      'escuro. Correção: bloqueio com exceção de diretoria + exibição do valor da dobra (motor da seção 5).';
  EXCEPTION WHEN check_violation THEN
    r.situacao := 'passou'; r.obtido := 'Programação além do concessivo bloqueada sem alçada.';
  END;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_021()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o valor em dobro do concessivo vencido é calculado por alguém?';
  r.esperado := 'No dia seguinte ao vencimento, a dobra do art. 137 aparece automaticamente';
  v_fns := public.qa_fns_com('%dobro%');
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO (par financeiro do FERIAS-020): nenhuma função calcula a dobra do art. '
             || '137 — o concessivo vencido não vira valor em lugar algum, e o passivo só '
             || 'aparece quando alguém lembra de procurar. O painel deveria exibir o dobro '
             || 'automaticamente no dia seguinte ao vencimento: passivo visível é o que dispara '
             || 'a gestão. Correção: rotina diária que identifica concessivos vencidos e '
             || 'materializa a obrigação em dobro.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Dobra calculada em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_022()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): existe cálculo da dobra com o corte da Súmula 81?';
  r.esperado := 'Dobro APENAS sobre os dias gozados após o fim do concessivo';
  v_fns := public.qa_fns_com('%dobro%');
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO (encadeado ao FERIAS-021): a dobra do art. 137 não é calculada em '
             || 'lugar nenhum — e quando for construída, precisa nascer com o corte da Súmula '
             || '81: férias que atravessam o vencimento dobram SÓ os dias excedentes (5 dentro '
             || 'do prazo saem simples; 25 fora saem em dobro). Dobrar o período inteiro '
             || 'superestima o passivo; ignorar o corte o esconde. Correção: cálculo dia a dia '
             || 'contra a data-limite do concessivo, com memória.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Dobra presente (conferir o corte da Súmula 81): %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_023()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
    r        public.qa_retorno;
    v_tem    BOOLEAN;
    v_ten    UUID;
    v_gerou_venc  INTEGER := 0;
    v_gerou_d60   INTEGER := 0;
    v_crit_id     UUID;
    v_acao        UUID;
BEGIN
    r.passo_ordem := 1;
    r.passo_acao  := 'AUDITORIA: existe motor de alertas de vencimento (D-90/60/30 + dobro + acao)?';
    r.esperado    := 'Varredura gera alertas por marco; vencido sinaliza dobro e cria acao no Plano';

    SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                    WHERE n.nspname='public' AND p.proname='ferias_alertas_varrer')
      INTO v_tem;
    IF NOT v_tem THEN
        r.situacao := 'falhou';
        r.obtido := 'ACHADO: o vencimento aparece so para quem entra na tela — passivo. Falta o '
                 || 'motor do RF-009: alerta em D-90/60/30, dobro ao vencer (art. 137) e acao no '
                 || 'Plano de Acao com 5W2H.';
        RETURN r;
    END IF;

    v_ten := public.qa_sandbox_tenant_id();
    IF v_ten IS NULL THEN
        r.situacao := 'nao_implementado';
        r.obtido := 'Sem tenants para montar a sonda; o motor existe mas nao foi exercitado.';
        RETURN r;
    END IF;

    BEGIN
        -- Periodo VENCIDO (concessivo ja passou): aquisitivo_fim ha ~13 meses.
        INSERT INTO public.ferias_periodos_aquisitivos
            (tenant_id, colaborador_cpf, colaborador_nome, data_admissao,
             aquisitivo_inicio, aquisitivo_fim, dias_direito, dias_saldo, status)
        VALUES (v_ten, '00000000191', 'QA Vencido', CURRENT_DATE - 800,
                CURRENT_DATE - 760, (CURRENT_DATE - INTERVAL '13 months')::date, 30, 30, 'ativo');

        -- Periodo a vencer em ~50 dias (faixa d60): concessivo = hoje + 50.
        -- concessivo = aquisitivo_fim + 12m  =>  aquisitivo_fim = hoje + 50 - 12m.
        INSERT INTO public.ferias_periodos_aquisitivos
            (tenant_id, colaborador_cpf, colaborador_nome, data_admissao,
             aquisitivo_inicio, aquisitivo_fim, dias_direito, dias_saldo, status)
        VALUES (v_ten, '00000000272', 'QA D60', CURRENT_DATE - 400,
                CURRENT_DATE - 380, (CURRENT_DATE + 50 - INTERVAL '12 months')::date, 30, 30, 'ativo');

        PERFORM public.ferias_alertas_varrer(v_ten);

        SELECT count(*) INTO v_gerou_venc FROM public.ferias_alertas
         WHERE tenant_id = v_ten AND tipo = 'risco_dobro' AND faixa = 'vencido';
        SELECT count(*) INTO v_gerou_d60 FROM public.ferias_alertas
         WHERE tenant_id = v_ten AND faixa = 'd60';

        SELECT id, plano_acao_id INTO v_crit_id, v_acao FROM public.ferias_alertas
         WHERE tenant_id = v_ten AND faixa = 'vencido' LIMIT 1;

        RAISE EXCEPTION 'qa_rollback';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM <> 'qa_rollback' THEN
            r.situacao := 'erro'; r.obtido := 'A sonda quebrou'; r.erro_tecnico := SQLERRM;
            RETURN r;
        END IF;
    END;

    IF v_gerou_venc >= 1 AND v_gerou_d60 >= 1 AND v_acao IS NOT NULL THEN
        r.situacao := 'passou';
        r.obtido := 'Motor OK: gera alerta em D-60 e alerta de dobro ao vencer, e o critico ja '
                 || 'nasce com acao no Plano de Acao (art. 134/137).';
    ELSIF v_gerou_venc = 0 OR v_gerou_d60 = 0 THEN
        r.situacao := 'falhou';
        r.obtido := format('A varredura nao gerou os marcos esperados (vencido=%s, d60=%s).',
                           v_gerou_venc, v_gerou_d60);
    ELSE
        r.situacao := 'falhou';
        r.obtido := 'Os alertas nascem, mas o critico (dobro) nao virou acao automatica no Plano.';
    END IF;
    RETURN r;
EXCEPTION WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_024()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text := public.qa_cpf(6124);
        v_status text;
BEGIN
  INSERT INTO public.ferias_solicitacoes
    (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
     data_inicio, data_fim, dias_solicitados, saldo_dias, status)
  VALUES (public.qa_sandbox_tenant_id(), public.qa_um_usuario(), 'QA Sobreposição', v_cpf,
          CURRENT_DATE - 10, CURRENT_DATE + 19, 30, 30, 'em_gozo');

  r.passo_ordem := 1;
  r.passo_acao := 'Registrar afastamento por doença no meio do gozo e observar a reação';
  r.esperado := 'Sobreposição detectada: gozo suspenso/interrompido e dias restantes preservados';
  INSERT INTO public.afastamentos
    (tenant_id, colaborador_cpf, colaborador_nome, status, data_inicio, data_fim)
  VALUES (public.qa_sandbox_tenant_id(), v_cpf, 'QA Sobreposição', 'ativo',
          CURRENT_DATE, CURRENT_DATE + 30);

  SELECT status INTO v_status FROM public.ferias_solicitacoes
  WHERE tenant_id = public.qa_sandbox_tenant_id() AND colaborador_cpf = v_cpf;

  IF v_status = 'em_gozo' THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o afastamento entrou por cima das férias e NADA reagiu — a solicitação '
             || 'segue "em gozo" com o colaborador afastado por doença. Os dois institutos não '
             || 'coexistem: o gozo deveria suspender, os 20 dias restantes voltarem ao saldo e '
             || 'o eSocial ser ajustado. Sem a detecção, o colaborador "gasta" férias doente — '
             || 'e as férias não gozadas viram passivo. Correção: gatilho de afastamento '
             || 'verificando sobreposição com férias em gozo/aprovadas.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('A sobreposição reagiu: solicitação passou a "%s".', v_status);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_030()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o aviso de férias (D-30) é gerado e vigiado?';
  r.esperado := 'Alerta em D-45 e aviso emitido com 30 dias, com recibo de ciência (art. 135)';
  SELECT string_agg(p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.proname NOT ILIKE '%historico%'  -- o gatilho de histórico só copia colunas
    AND p.prosrc ILIKE '%aviso_gerado%';
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o campo aviso_gerado existe na solicitação, mas NENHUMA função o '
             || 'preenche ou vigia — não há relógio do art. 135 (aviso por escrito com 30 dias '
             || 'de antecedência, mediante recibo). Sem o aviso tempestivo documentado, a '
             || 'concessão é irregular mesmo com as férias gozadas. Correção: alerta em D-45, '
             || 'emissão do aviso em D-30 via módulo de Documentos com recibo de ciência.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Aviso vigiado em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_031()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text := public.qa_cpf(6031); v_aceitou boolean := false;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Aprovar solicitação com início em 20 dias, sem aviso emitido e sem justificativa';
  r.esperado := 'Travado — início em menos de 30 dias significa aviso fora do prazo legal';
  BEGIN
    INSERT INTO public.ferias_solicitacoes
      (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
       data_inicio, data_fim, dias_solicitados, saldo_dias, status, aviso_gerado)
    VALUES (public.qa_sandbox_tenant_id(), public.qa_um_usuario(), 'QA Aviso Curto', v_cpf,
            CURRENT_DATE + 20, CURRENT_DATE + 49, 30, 30, 'aprovado', false);
    v_aceitou := true;
  EXCEPTION WHEN check_violation OR raise_exception OR not_null_violation THEN
    v_aceitou := false;
  END;

  IF v_aceitou THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o banco aceitou solicitação APROVADA com início em 20 dias, sem aviso '
             || 'emitido e sem justificativa registrada. O art. 135 exige o aviso com 30 dias; '
             || 'a exceção operacional até pode existir, mas só com alerta aceito e '
             || 'justificativa em trilha. Correção: trava no status aprovado quando '
             || '(data_inicio - hoje) < 30 e aviso_gerado = false, com campo de justificativa '
             || 'da exceção.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'A aprovação com prazo de aviso inviável foi travada.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_032()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a aprovação gera a obrigação financeira (D-2) com o terço?';
  r.esperado := 'Vencimento em D-2 do início (art. 145) e terço constitucional em TODOS os cálculos';
  SELECT string_agg(p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%valor_terco%' OR p.prosrc ILIKE '%registro_financeiro_id%');
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a solicitação tem os campos financeiros (valor_ferias, valor_terco, '
             || 'valor_total_bruto, registro_financeiro_id), mas NENHUMA função os calcula ou '
             || 'preenche — o terço constitucional (CF art. 7º, XVII) e o vencimento em D-2 '
             || '(art. 145) dependem de alguém lembrar e digitar. Pagamento fora do D-2 gera '
             || 'dobra do valor pela Súmula 450 (discussão atual no TST, mas o prazo segue '
             || 'legal). Correção: aprovação dispara o cálculo (salário base + terço, abono '
             || 'incluído) e cria a obrigação com vencimento D-2, alertando a tesouraria.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Financeiro de férias calculado em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_033()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
    r          public.qa_retorno;
    v_existe   BOOLEAN;
    v_sonda    JSONB;
    v_faltando TEXT[];
    v_param    BOOLEAN;
BEGIN
    r.passo_ordem := 1;
    r.passo_acao  := 'AUDITORIA (somente leitura): a média das variáveis do art. 142 é apurada da folha, com memória?';
    r.esperado    := 'Função que soma as rubricas marcadas como integrantes das férias na janela do período e devolve média + memória competência a competência';

    SELECT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'ferias_media_variaveis'
    ) INTO v_existe;

    IF NOT v_existe THEN
        r.situacao := 'falhou';
        r.obtido := 'ACHADO CENTRAL do documento de requisitos: a média das variáveis não é '
                 || 'apurada — o campo é digitado e nasce zerado. Quem recebe hora extra '
                 || 'habitual, comissão ou adicional leva a MÉDIA para as férias; calcular só '
                 || 'o fixo paga a menos, e sem memória nada se audita. Correção: apuração '
                 || 'determinística a partir das rubricas marcadas com incide_ferias, com '
                 || 'memória exportável (RF-004 e RNF-001 do documento).';
        RETURN r;
    END IF;

    -- Sonda: CPF que não existe. Interessa a FORMA da resposta, não o valor.
    v_sonda := public.ferias_media_variaveis(
        '00000000-0000-0000-0000-000000000000'::uuid,
        '00000000000', DATE '2025-01-01', DATE '2025-12-31'
    );

    SELECT array_agg(chave) INTO v_faltando
      FROM unnest(ARRAY['media','total','meses_divisor','base','divisor_regra',
                        'janela_inicio','janela_fim','competencias','rubricas',
                        'parametros_vigencia','fundamento']) AS chave
     WHERE NOT (v_sonda ? chave);

    SELECT public.qa_col_existe('ferias_config', 'media_base') IS NOT NULL
       AND public.qa_col_existe('ferias_config', 'media_divisor') IS NOT NULL
      INTO v_param;

    IF v_faltando IS NOT NULL THEN
        r.situacao := 'falhou';
        r.obtido := format('A apuração existe, mas a memória está incompleta: faltam %s no '
                 || 'retorno. Sem esses campos o valor não se reproduz depois (RNF-008).',
                 array_to_string(v_faltando, ', '));
    ELSIF NOT coalesce(v_param, false) THEN
        r.situacao := 'falhou';
        r.obtido := 'A apuração existe e devolve memória, mas a base e o divisor não são '
                 || 'parametrizáveis por empresa (ferias_config.media_base / media_divisor). '
                 || 'O documento pede parâmetro com vigência, não regra fixa no código (RNF-002).';
    ELSE
        r.situacao := 'passou';
        r.obtido := format('Média apurada da folha por ferias_media_variaveis, com memória '
                 || 'completa (janela %s a %s, base "%s", divisor "%s") e parâmetros por '
                 || 'empresa com vigência.',
                 v_sonda->>'janela_inicio', v_sonda->>'janela_fim',
                 v_sonda->>'base', v_sonda->>'divisor_regra');
    END IF;

    RETURN r;
EXCEPTION WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_034()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): as naturezas tributáveis × indenizatórias são distinguidas?';
  r.esperado := 'Gozo + 1/3 com INSS/FGTS/IRRF (Tema 985 na patronal); abono + 1/3 fora da base (art. 144)';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.proname ILIKE '%ferias%'
    AND (p.prosrc ILIKE '%inss%' OR p.prosrc ILIKE '%irrf%' OR p.prosrc ILIKE '%indenizat%');
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: não existe apuração de encargos de férias — nenhuma função distingue '
             || 'as duas naturezas que convivem no mesmo pagamento: férias gozadas + 1/3 '
             || 'sofrem INSS/FGTS/IRRF (o terço inclusive na patronal, Tema 985 do STF, '
             || 'modulado desde 15/09/2020); abono pecuniário + seu 1/3 são indenizatórios '
             || '(art. 144) e ficam FORA da base. Misturar erra o encargo para os dois lados. '
             || 'Depende do motor de cálculo do FERIAS-033 existir primeiro; as incidências '
             || 'nascem junto, versionadas ([VAL] contábil).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Incidências tratadas em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_035()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a opção adiantar_13 da programação é consumida por alguém?';
  r.esperado := 'Marcada, soma a 1ª parcela ao pagamento das férias e abate na apuração de novembro';
  v_fns := public.qa_fns_com('%adiantar_13%');
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o campo adiantar_13 existe na programação e NENHUMA função o lê — a '
             || 'opção é decorativa. O empregado que requer no prazo (Lei 4.749/65, art. 2º, '
             || '§2º) tem DIREITO à 1ª parcela do 13º junto com as férias; marcado o campo e '
             || 'nada acontecendo, ou o DP paga por fora (sem baixa, risco de duplicidade em '
             || 'novembro) ou o direito é ignorado. Correção: opção integrando o cálculo do '
             || 'pagamento e a baixa na apuração do 13º.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Adiantamento consumido em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_040()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text := public.qa_cpf(6040);
        v_aceitou boolean := false; v_carimbo text;
BEGIN
  PERFORM public.qa_ferias_periodo(v_cpf, 'QA Abono Prazo', 0, CURRENT_DATE + 60);

  r.passo_ordem := 1;
  r.passo_acao := 'Requerer abono de 10 dias (1/3 de 30) faltando 60 dias para o fim do aquisitivo';
  r.esperado := 'Aceito — prazo legal respeitado (até 15 dias antes do término, art. 143, §1º)';
  BEGIN
    INSERT INTO public.ferias_programacao
      (tenant_id, colaborador_cpf, colaborador_nome, aquisitivo_inicio, aquisitivo_fim,
       p1_inicio, p1_fim, p1_dias, abono_vender, abono_dias, adiantar_13, estado)
    VALUES (public.qa_sandbox_tenant_id(), v_cpf, 'QA Abono Prazo',
            CURRENT_DATE - 305, CURRENT_DATE + 60,
            CURRENT_DATE + 90, CURRENT_DATE + 109, 20, true, 10, false, 'planejado');
    v_aceitou := true;
  EXCEPTION WHEN OTHERS THEN v_aceitou := false; END;

  r.passo_ordem := 2;
  r.passo_acao := 'Conferir o carimbo de QUANDO o abono foi requerido';
  r.esperado := 'Data do requerimento registrada — sem ela não se prova o prazo do §1º';
  v_carimbo := public.qa_col_existe('ferias_programacao', '%requer%');

  IF v_aceitou AND v_carimbo IS NOT NULL THEN
    r.situacao := 'passou';
    r.obtido := 'Abono no prazo aceito, com data de requerimento registrada.';
  ELSIF v_aceitou THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o abono dentro do prazo foi aceito, mas a programação NÃO GUARDA a '
             || 'data do requerimento — e o prazo do art. 143, §1º (até 15 dias antes do fim '
             || 'do aquisitivo) se prova exatamente por esse carimbo. Sem ele, qualquer abono '
             || 'vira discutível. Correção: data/autor do requerimento na programação '
             || '(complementa o FERIAS-041, que já apontou a falta do limite de 1/3).';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'O abono legítimo (1/3, no prazo) foi recusado — validação mais restritiva que a lei.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_041()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_cpf text := public.qa_cpf(40041);
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM public.qa_ferias_periodo(v_cpf, '[QA-FERIAS] Abono Guloso', 0);

  r.passo_ordem := 1;
  r.passo_acao := 'Programar abono de 15 dias num direito de 30 (limite legal: 10)';
  r.esperado := 'Recusado — o abono é de ATÉ 1/3 do período (art. 143)';
  BEGIN
    INSERT INTO public.ferias_programacao
      (tenant_id, colaborador_cpf, colaborador_nome, aquisitivo_inicio, aquisitivo_fim,
       p1_inicio, p1_fim, p1_dias, abono_vender, abono_dias, adiantar_13, estado)
    VALUES (v_t, v_cpf, '[QA-FERIAS] Abono Guloso',
            CURRENT_DATE - interval '13 months', CURRENT_DATE - 30,
            CURRENT_DATE + 30, CURRENT_DATE + 44, 15, true, 15, false, 'planejado');
    r.situacao := 'falhou';
    r.obtido := 'O BANCO ACEITOU abono de 15 dias num direito de 30 — o art. 143 limita a 1/3 '
      '(10 dias; e em direito reduzido pelo art. 130 o teto acompanha). abono_dias é inteiro sem '
      'validação contra o direito. Correção: validação do 1/3 sobre o direito REAL no motor de regras.';
  EXCEPTION WHEN check_violation THEN
    r.situacao := 'passou'; r.obtido := 'Abono acima de 1/3 recusado.';
  END;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_042()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text := public.qa_cpf(6042); v_aceitou boolean := false;
BEGIN
  PERFORM public.qa_ferias_periodo(v_cpf, 'QA Abono Tarde', 0, CURRENT_DATE + 10);

  r.passo_ordem := 1;
  r.passo_acao := 'Requerer abono faltando só 10 dias para o fim do aquisitivo (prazo legal: 15)';
  r.esperado := 'Indisponível/recusado, com explicação do prazo — não um aceite silencioso';
  BEGIN
    INSERT INTO public.ferias_programacao
      (tenant_id, colaborador_cpf, colaborador_nome, aquisitivo_inicio, aquisitivo_fim,
       p1_inicio, p1_fim, p1_dias, abono_vender, abono_dias, adiantar_13, estado)
    VALUES (public.qa_sandbox_tenant_id(), v_cpf, 'QA Abono Tarde',
            CURRENT_DATE - 355, CURRENT_DATE + 10,
            CURRENT_DATE + 30, CURRENT_DATE + 49, 20, true, 10, false, 'planejado');
    v_aceitou := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_aceitou := false; END;

  IF v_aceitou THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o abono requerido FORA do prazo (10 dias do fim do aquisitivo; a lei '
             || 'exige requerimento até 15 dias antes — art. 143, §1º) foi aceito sem aviso. '
             || 'O empregador não é obrigado a aceitar abono extemporâneo, e aceitá-lo sem '
             || 'saber cria expectativa e passivo. Correção: validar o prazo contra o fim do '
             || 'aquisitivo e recusar com mensagem clara (ou exigir aceite expresso do '
             || 'empregador como liberalidade).';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'O abono fora do prazo foi recusado.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_050()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_labels text; v_faltando text := '';
        v_esperados text[] := ARRAY['sugerido','planejado','confirmado','ciente','solicitado',
                                    'aprovado','em_gozo','concluido','cancelado'];
  e text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Conferir o enum ferias_prog_estado contra os 9 estados do ciclo (seção 4.2)';
  r.esperado := 'Todos presentes; valor fora da lista é recusado';

  SELECT string_agg(en.enumlabel, ',') INTO v_labels
  FROM pg_enum en JOIN pg_type t ON t.oid = en.enumtypid
  WHERE t.typname = 'ferias_prog_estado';

  IF v_labels IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'O enum ferias_prog_estado não existe — o ciclo de estados do documento não tem contrato no banco.';
    RETURN r;
  END IF;

  FOREACH e IN ARRAY v_esperados LOOP
    IF position(e IN v_labels) = 0 THEN v_faltando := v_faltando || ' ' || e; END IF;
  END LOOP;

  r.passo_ordem := 2;
  r.passo_acao := 'Gravar programação com estado inventado';
  r.esperado := 'Recusado pelo enum';
  BEGIN
    EXECUTE format(
      'INSERT INTO public.ferias_programacao
         (tenant_id, colaborador_cpf, colaborador_nome, aquisitivo_inicio, aquisitivo_fim,
          abono_vender, abono_dias, adiantar_13, estado)
       VALUES (%L, %L, %L, %L, %L, false, 0, false, %L::public.ferias_prog_estado)',
      public.qa_sandbox_tenant_id(), public.qa_cpf(40050), '[QA-FERIAS] Estado Inventado',
      CURRENT_DATE - interval '13 months', CURRENT_DATE - 30, 'aprovadissimo');
    r.situacao := 'falhou';
    r.obtido := 'ACEITOU estado fora da lista fechada do ciclo.';
    RETURN r;
  EXCEPTION WHEN invalid_text_representation THEN
    NULL; -- recusado, como esperado
  END;

  IF v_faltando = '' THEN
    r.situacao := 'passou';
    r.obtido := 'Os 9 estados do ciclo existem no enum e valor inventado é recusado — o contrato da seção 4.2 está no banco.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'Estados do ciclo AUSENTES no enum:' || v_faltando || '. O documento (4.2) define 9; o banco conhece: ' || v_labels || '.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_051()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_devolve boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): cancelar férias aprovadas devolve os dias ao saldo?';
  r.esperado := 'Dias voltam ao período aquisitivo, alerta de vencimento reabre, trilha registra motivo';
  SELECT bool_or(p.prosrc ILIKE '%cancelad%' AND p.prosrc ILIKE '%saldo%') INTO v_devolve
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.proname ILIKE '%ferias%' OR p.prosrc ILIKE '%ferias_solicitacoes%');
  IF NOT coalesce(v_devolve, false) THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nenhuma função devolve os dias ao saldo quando a solicitação é '
             || 'cancelada — o status muda para "cancelado" e os dias ficam perdidos entre a '
             || 'solicitação e o período aquisitivo (que nem são formalmente ligados). O risco '
             || 'do concessivo também não reabre. Correção: cancelamento com motivo '
             || 'obrigatório que devolva os dias ao período, reabra o alerta de vencimento e '
             || 'registre quem/quando/por quê na trilha.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'O cancelamento devolve o saldo.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_052()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text := public.qa_cpf(6052); v_id uuid;
        v_mudou boolean := false;
BEGIN
  INSERT INTO public.ferias_programacao
    (tenant_id, colaborador_cpf, colaborador_nome, aquisitivo_inicio, aquisitivo_fim,
     p1_inicio, p1_fim, p1_dias, abono_vender, abono_dias, adiantar_13, estado)
  VALUES (public.qa_sandbox_tenant_id(), v_cpf, 'QA Data Firmada',
          CURRENT_DATE - 395, CURRENT_DATE - 30,
          CURRENT_DATE + 45, CURRENT_DATE + 74, 30, false, 0, false, 'confirmado')
  RETURNING id INTO v_id;

  r.passo_ordem := 1;
  r.passo_acao := 'Alterar a data de início de uma programação CONFIRMADA, sem justificativa';
  r.esperado := 'Recusado ou exigindo justificativa — data confirmada é compromisso';
  BEGIN
    UPDATE public.ferias_programacao SET p1_inicio = CURRENT_DATE + 80, p1_fim = CURRENT_DATE + 109
    WHERE id = v_id;
    v_mudou := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_mudou := false; END;

  IF v_mudou THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a data de férias CONFIRMADAS mudou silenciosamente — sem justificativa '
             || 'obrigatória, sem alçada. O histórico até registra a mudança (gatilho de '
             || 'histórico existe), mas registrar não é o mesmo que exigir motivo: a alteração '
             || 'unilateral de data confirmada é a origem clássica de conflito trabalhista. '
             || 'Correção: a partir do estado confirmado, alteração de data exige campo de '
             || 'justificativa preenchido e registra o autor.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'A alteração sem justificativa foi recusada.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_053()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text; v_marcou boolean := false;
BEGIN
  v_cpf := public.qa_ponto_admissao('QA Em Gozo', 6053);
  INSERT INTO public.ferias_solicitacoes
    (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
     data_inicio, data_fim, dias_solicitados, saldo_dias, status)
  VALUES (public.qa_sandbox_tenant_id(), public.qa_um_usuario(), 'QA Em Gozo', v_cpf,
          CURRENT_DATE - 5, CURRENT_DATE + 10, 16, 30, 'em_gozo');

  r.passo_ordem := 1;
  r.passo_acao := 'Tentar marcar ponto DURANTE férias em gozo';
  r.esperado := 'Recusado — férias suspendem a prestação de serviço, como o afastamento';
  BEGIN
    PERFORM public.qa_ponto_marca(v_cpf, 'QA Em Gozo', CURRENT_DATE, TIME '08:00', 'entrada');
    v_marcou := true;
  EXCEPTION WHEN OTHERS THEN v_marcou := false; END;

  IF v_marcou THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o colaborador EM FÉRIAS marcou ponto normalmente. O validador de '
             || 'marcação só consulta a tabela de afastamentos — férias em gozo não bloqueiam '
             || 'nada (a ponte férias→afastamentos não existe). Trabalho registrado durante as '
             || 'férias é indício de férias não gozadas: passivo em dobro. Correção: o '
             || 'validador de marcação também consultar ferias_solicitacoes em_gozo (ou o '
             || 'início do gozo gerar afastamento automático).';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'A marcação durante o gozo foi recusada.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_054()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): existe reabertura formal de cálculo de férias fechado?';
  r.esperado := 'Motivo + dupla aprovação + diferença/estorno, preservando a versão anterior';
  v_fns := coalesce(public.qa_fns_com('%ferias%reabr%'), public.qa_fns_com('%reabert%ferias%'));
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO (encadeado ao FERIAS-033): sem motor de cálculo, não há fechamento — e '
             || 'sem fechamento, não há reabertura formal. Quando o cálculo nascer, o rito '
             || 'nasce junto: cálculo pago não se edita; reabre-se com motivo e DUPLA '
             || 'aprovação, gerando DIFERENÇA (a pagar/estornar) e preservando a versão que o '
             || 'colaborador recebeu. Mesmo desenho da reabertura de competência do Ponto '
             || '(PONTO-358).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Reabertura formal presente em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_055()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
    r          public.qa_retorno;
    v_tem_fn   BOOLEAN;
    v_tem_trg  BOOLEAN;
    v_barrou   BOOLEAN := false;
    v_liberou  BOOLEAN := false;
    v_id       UUID;
    v_ten      UUID;
BEGIN
    r.passo_ordem := 1;
    r.passo_acao  := 'AUDITORIA: a ciencia do aviso trava o inicio do gozo (em_gozo)?';
    r.esperado    := 'Sem ciencia, em_gozo e barrado; com ciencia registrada, em_gozo passa (art. 135)';

    SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                    WHERE n.nspname='public' AND p.proname='ferias_aviso_tem_ciencia')
      INTO v_tem_fn;
    SELECT EXISTS (SELECT 1 FROM pg_trigger
                    WHERE tgname='trg_ferias_trava_em_gozo' AND NOT tgisinternal)
      INTO v_tem_trg;

    IF NOT v_tem_fn OR NOT v_tem_trg THEN
        r.situacao := 'falhou';
        r.obtido := 'ACHADO: nada condiciona a concessao a ciencia do aviso — em_gozo avanca '
                 || 'com o aviso pendente. O art. 135 exige comunicacao MEDIANTE RECIBO. '
                 || 'Correcao: trava de transicao para em_gozo condicionada a ciencia.';
        RETURN r;
    END IF;

    v_ten := public.qa_sandbox_tenant_id();
    IF v_ten IS NULL THEN
        r.situacao := 'nao_implementado';
        r.obtido := 'Sem tenants na base para montar a sonda; a trava existe (funcao + trigger) '
                 || 'mas nao foi exercitada com dados.';
        RETURN r;
    END IF;

    BEGIN
        -- aviso_gerado=true: cumpre a FERIAS-031 (aviso EMITIDO); a sonda testa a CIENCIA.
        INSERT INTO public.ferias_solicitacoes
            (tenant_id, colaborador_nome, data_inicio, data_fim, dias_solicitados, status, aviso_gerado)
        VALUES (v_ten, 'QA Sonda FERIAS-055', CURRENT_DATE, CURRENT_DATE + 20, 20, 'aprovado', true)
        RETURNING id INTO v_id;

        BEGIN
            UPDATE public.ferias_solicitacoes SET status='em_gozo' WHERE id=v_id;
        EXCEPTION WHEN check_violation THEN
            v_barrou := true;
        END;

        UPDATE public.ferias_solicitacoes
           SET aviso_ciencia_em = now(), aviso_ciencia_origem = 'manual'
         WHERE id = v_id;
        BEGIN
            UPDATE public.ferias_solicitacoes SET status='em_gozo' WHERE id=v_id;
            v_liberou := true;
        EXCEPTION WHEN OTHERS THEN
            v_liberou := false;
        END;

        RAISE EXCEPTION 'qa_rollback';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM <> 'qa_rollback' THEN
            r.situacao := 'erro'; r.obtido := 'A sonda quebrou'; r.erro_tecnico := SQLERRM;
            RETURN r;
        END IF;
    END;

    IF v_barrou AND v_liberou THEN
        r.situacao := 'passou';
        r.obtido := 'A trava funciona: sem ciencia o inicio do gozo e barrado; com a ciencia '
                 || 'registrada, passa. A regra vive em ferias_aviso_tem_ciencia e na trigger '
                 || 'trg_ferias_trava_em_gozo.';
    ELSIF NOT v_barrou THEN
        r.situacao := 'falhou';
        r.obtido := 'A trava existe mas NAO barrou o em_gozo sem ciencia — a concessao avanca '
                 || 'sem a prova do art. 135.';
    ELSE
        r.situacao := 'falhou';
        r.obtido := 'A trava barrou ate com a ciencia registrada — esta bloqueando concessao '
                 || 'legitima. Revisar ferias_aviso_tem_ciencia.';
    END IF;
    RETURN r;
EXCEPTION WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_056()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text := public.qa_cpf(6156);
        v_uid uuid := public.qa_um_usuario(); v_aceitou boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    BEGIN
      INSERT INTO auth.users (id, email)
      VALUES (gen_random_uuid(), public.qa_fixture_email('FERIAS-056', 1))
      RETURNING id INTO v_uid;
    EXCEPTION WHEN OTHERS THEN
      r.situacao := 'nao_implementado';
      r.obtido := 'Sem usuário de autenticação disponível para simular o cenário.';
      RETURN r;
    END;
  END IF;

  r.passo_ordem := 1;
  r.passo_acao := 'Gravar solicitação APROVADA onde o aprovador é o próprio solicitante';
  r.esperado := 'Recusado — segregação de funções (mesma trava que o ajuste de ponto tem)';
  BEGIN
    INSERT INTO public.ferias_solicitacoes
      (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
       data_inicio, data_fim, dias_solicitados, saldo_dias, status,
       aprovado_por, aprovado_por_nome, data_aprovacao)
    VALUES (public.qa_sandbox_tenant_id(), v_uid, 'QA Autoaprovação', v_cpf,
            CURRENT_DATE + 40, CURRENT_DATE + 69, 30, 30, 'aprovado',
            v_uid, 'QA Autoaprovação', now());
    v_aceitou := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_aceitou := false; END;

  IF v_aceitou THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o banco aceitou férias APROVADAS PELO PRÓPRIO SOLICITANTE '
             || '(aprovado_por = colaborador_id) — não existe a trava de segregação que o '
             || 'ajuste de ponto já tem (chk_ajuste_sem_autoaprovacao, PONTO-252). Um gestor '
             || 'escolhe as próprias datas e valores sem contrapeso. Correção: CHECK '
             || '(aprovado_por IS NULL OR aprovado_por <> colaborador_id) em '
             || 'ferias_solicitacoes.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'A autoaprovação foi recusada.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_060()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
    r public.qa_retorno; v_tem boolean; v_ten uuid; v_id uuid;
    v_com int; v_prazo date;
BEGIN
    r.passo_ordem := 1;
    r.passo_acao := 'AUDITORIA: existe fluxo de ferias coletivas com comunicados (15 dias)?';
    r.esperado := 'Programa por setor, ate 2 periodos >= 10 dias, comunicados MTE/sindicato/empregados';

    SELECT to_regclass('public.ferias_coletivas') IS NOT NULL INTO v_tem;
    IF NOT v_tem THEN
        r.situacao := 'falhou';
        r.obtido := 'ACHADO: sem fluxo de coletivas (arts. 139-141). Sem ele, nem os limites '
                 || 'nem as comunicacoes de 15 dias nem o art. 140 tem onde viver.';
        RETURN r;
    END IF;

    v_ten := public.qa_sandbox_tenant_id();
    IF v_ten IS NULL THEN
        r.situacao := 'nao_implementado'; r.obtido := 'Sem tenants para a sonda.'; RETURN r;
    END IF;

    BEGIN
        INSERT INTO public.ferias_coletivas (tenant_id, ano, departamento, p1_inicio, p1_fim)
        VALUES (v_ten, EXTRACT(YEAR FROM CURRENT_DATE)::int, 'QA-Producao',
                CURRENT_DATE + 40, CURRENT_DATE + 51)   -- 12 dias
        RETURNING id INTO v_id;

        v_com := public.ferias_coletiva_abrir_comunicados(v_id);
        SELECT count(*), min(prazo_limite) INTO v_com, v_prazo
          FROM public.ferias_coletivas_comunicados WHERE coletiva_id = v_id;

        RAISE EXCEPTION 'qa_rollback';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM <> 'qa_rollback' THEN
            r.situacao := 'erro'; r.obtido := 'A sonda quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
        END IF;
    END;

    IF v_com = 3 AND v_prazo = (CURRENT_DATE + 40 - 15) THEN
        r.situacao := 'passou';
        r.obtido := 'Coletiva de 12 dias aceita; 3 comunicados (MTE, sindicato, empregados) '
                 || 'abertos com prazo 15 dias antes do inicio.';
    ELSE
        r.situacao := 'falhou';
        r.obtido := format('Rito incompleto: comunicados=%s (esperado 3), prazo=%s (esperado %s).',
                           v_com, v_prazo, CURRENT_DATE + 40 - 15);
    END IF;
    RETURN r;
EXCEPTION WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_061()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
    r public.qa_retorno; v_ten uuid; v_ano int := EXTRACT(YEAR FROM CURRENT_DATE)::int;
    v_barrou_curto boolean := false; v_barrou_terceiro boolean := false;
BEGIN
    r.passo_ordem := 1;
    r.passo_acao := 'AUDITORIA: os limites das coletivas valem (min 10 dias; max 2/ano)?';
    r.esperado := 'Periodo de 8 dias barrado; segundo programa no mesmo ano/setor barrado';

    IF to_regclass('public.ferias_coletivas') IS NULL THEN
        r.situacao := 'falhou'; r.obtido := 'Sem tabela de coletivas (encadeado ao FERIAS-060).'; RETURN r;
    END IF;
    v_ten := public.qa_sandbox_tenant_id();
    IF v_ten IS NULL THEN r.situacao := 'nao_implementado'; r.obtido := 'Sem tenants.'; RETURN r; END IF;

    BEGIN
        -- 8 dias: deve barrar
        BEGIN
            INSERT INTO public.ferias_coletivas (tenant_id, ano, departamento, p1_inicio, p1_fim)
            VALUES (v_ten, v_ano, 'QA-Limites', CURRENT_DATE + 40, CURRENT_DATE + 47);
        EXCEPTION WHEN check_violation THEN v_barrou_curto := true;
        END;

        -- 1 valido + 2o programa no mesmo ano/setor: o 2o deve barrar
        INSERT INTO public.ferias_coletivas (tenant_id, ano, departamento, p1_inicio, p1_fim)
        VALUES (v_ten, v_ano, 'QA-Limites2', CURRENT_DATE + 40, CURRENT_DATE + 51);
        BEGIN
            INSERT INTO public.ferias_coletivas (tenant_id, ano, departamento, p1_inicio, p1_fim)
            VALUES (v_ten, v_ano, 'QA-Limites2', CURRENT_DATE + 100, CURRENT_DATE + 111);
        EXCEPTION WHEN check_violation THEN v_barrou_terceiro := true;
        END;

        RAISE EXCEPTION 'qa_rollback';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM <> 'qa_rollback' THEN
            r.situacao := 'erro'; r.obtido := 'A sonda quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
        END IF;
    END;

    IF v_barrou_curto AND v_barrou_terceiro THEN
        r.situacao := 'passou';
        r.obtido := 'Limites valem: periodo de 8 dias barrado (min 10) e segundo programa no '
                 || 'mesmo ano/setor barrado (max 2 periodos anuais).';
    ELSE
        r.situacao := 'falhou';
        r.obtido := format('Limites frouxos: barrou_8dias=%s, barrou_2o_programa=%s.',
                           v_barrou_curto, v_barrou_terceiro);
    END IF;
    RETURN r;
EXCEPTION WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_062()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
    r public.qa_retorno;
    v_novato   RECORD;
    v_veterano RECORD;
BEGIN
    r.passo_ordem := 1;
    r.passo_acao := 'AUDITORIA: quem tem menos de 12 meses entra proporcional (art. 140)?';
    r.esperado := 'Novato de 6 meses: art_140=true e ~15 dias proporcionais; veterano: art_140=false';

    IF to_regproc('public.ferias_art140_calc') IS NULL THEN
        r.situacao := 'falhou';
        r.obtido := 'Sem tratamento do art. 140 (encadeado ao FERIAS-060).';
        RETURN r;
    END IF;

    SELECT * INTO v_novato   FROM public.ferias_art140_calc(
        (DATE '2026-01-01' - INTERVAL '6 months')::date, DATE '2026-01-01');
    SELECT * INTO v_veterano FROM public.ferias_art140_calc(
        (DATE '2026-01-01' - INTERVAL '3 years')::date, DATE '2026-01-01');

    IF v_novato.art_140 AND v_novato.dias_proporcionais BETWEEN 12 AND 18
       AND NOT v_veterano.art_140 THEN
        r.situacao := 'passou';
        r.obtido := format('Art. 140 OK: novato de 6 meses entra proporcional (%s dias); '
                 || 'veterano nao e afetado.', v_novato.dias_proporcionais);
    ELSE
        r.situacao := 'falhou';
        r.obtido := format('Art. 140 incorreto: novato_140=%s dias=%s veterano_140=%s.',
                           v_novato.art_140, v_novato.dias_proporcionais, v_veterano.art_140);
    END IF;
    RETURN r;
EXCEPTION WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_070()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o parâmetro de dispensa patronal do Simples é usado no cálculo?';
  r.esperado := 'Provisão distingue Anexo III (sem patronal, mantém FGTS) de Anexo IV (com patronal)';
  v_fns := public.qa_fns_com('%simples_dispensa%');
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o parâmetro existe (ferias_config.simples_dispensa_patronal), mas '
             || 'NENHUMA função o consome — não há cálculo de encargos de férias que distinga '
             || 'Simples Anexo III (dispensa a contribuição patronal, mantém FGTS) do Anexo IV '
             || '(recolhe). A provisão sai errada para um dos dois grupos. Correção: memória '
             || 'de cálculo dos encargos lendo o enquadramento do cadastro da empresa.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Encargos por enquadramento em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_071()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): programar demais gente do mesmo time gera alerta de cobertura?';
  r.esperado := 'Limite parametrizado (ex.: 20% simultâneos) com alerta informativo — não bloqueio';
  SELECT string_agg(p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%cobertura%'
    AND (p.prosrc ILIKE '%equipe%' OR p.prosrc ILIKE '%departamento%' OR p.prosrc ILIKE '%simultan%');
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: não existe verificação de cobertura — programar 40% de um departamento '
             || 'no mesmo mês passa sem aviso. É informação de gestão (a época das férias é '
             || 'prerrogativa do empregador, art. 136), então o desenho certo é ALERTA com '
             || 'mapa de calor, nunca bloqueio. Correção: parâmetro de % máximo simultâneo por '
             || 'departamento com alerta na programação.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Cobertura verificada em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_080()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
    r public.qa_retorno; v_ten uuid; v_calc uuid; v_ev RECORD;
BEGIN
    r.passo_ordem := 1;
    r.passo_acao := 'AUDITORIA: a concessao gera o S-2230 (motivo 15) com datas exatas?';
    r.esperado := 'Um S-2230 pendente, codMotAfast=15, dtIniAfast/dtTermAfast = datas do gozo';

    IF to_regproc('public.ferias_esocial_gerar') IS NULL THEN
        r.situacao := 'falhou';
        r.obtido := 'ACHADO: a concessao nao gera evento do eSocial. Sem o S-2230 (motivo 15), '
                 || 'o gozo nao existe oficialmente para o governo (RF-008).';
        RETURN r;
    END IF;
    v_ten := public.qa_sandbox_tenant_id();
    IF v_ten IS NULL THEN r.situacao := 'nao_implementado'; r.obtido := 'Sem tenants.'; RETURN r; END IF;

    BEGIN
        v_calc := public.qa_ferias_sonda_calculo(v_ten);
        PERFORM public.ferias_esocial_gerar(v_calc);
        SELECT tipo_evento, status, motivo_afastamento,
               (xml_enviado::jsonb ->> 'dtIniAfast') AS ini,
               (xml_enviado::jsonb ->> 'dtTermAfast') AS fim
          INTO v_ev
          FROM public.esocial_transmissoes
         WHERE ferias_calculo_id = v_calc AND tipo_evento = 'S-2230';
        RAISE EXCEPTION 'qa_rollback';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM <> 'qa_rollback' THEN
            r.situacao := 'erro'; r.obtido := 'A sonda quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
        END IF;
    END;

    IF v_ev.status = 'pendente' AND v_ev.motivo_afastamento = '15'
       AND v_ev.ini = (CURRENT_DATE + 40)::text AND v_ev.fim = (CURRENT_DATE + 69)::text THEN
        r.situacao := 'passou';
        r.obtido := 'S-2230 gerado: motivo 15, datas exatas do gozo, status pendente para envio.';
    ELSE
        r.situacao := 'falhou';
        r.obtido := format('S-2230 incorreto: status=%s motivo=%s ini=%s fim=%s.',
                           v_ev.status, v_ev.motivo_afastamento, v_ev.ini, v_ev.fim);
    END IF;
    RETURN r;
EXCEPTION WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_081()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
    r public.qa_retorno; v_ten uuid; v_calc uuid; v_tid uuid;
    v_traducao text; v_status text; v_qtd_antes int; v_qtd_depois int;
BEGIN
    r.passo_ordem := 1;
    r.passo_acao := 'AUDITORIA: rejeicao e traduzida e o reenvio nao duplica o evento?';
    r.esperado := 'Codigo tecnico vira mensagem clara; regerar mantem UMA linha por evento';

    IF to_regproc('public.ferias_esocial_interpretar_retorno') IS NULL THEN
        r.situacao := 'falhou'; r.obtido := 'Sem interpretacao de retorno (RF-008).'; RETURN r; END IF;
    v_ten := public.qa_sandbox_tenant_id();
    IF v_ten IS NULL THEN r.situacao := 'nao_implementado'; r.obtido := 'Sem tenants.'; RETURN r; END IF;

    BEGIN
        v_calc := public.qa_ferias_sonda_calculo(v_ten);
        PERFORM public.ferias_esocial_gerar(v_calc);
        SELECT count(*) INTO v_qtd_antes FROM public.esocial_transmissoes WHERE ferias_calculo_id = v_calc;

        SELECT id INTO v_tid FROM public.esocial_transmissoes
         WHERE ferias_calculo_id = v_calc AND tipo_evento = 'S-2230';
        v_traducao := public.ferias_esocial_interpretar_retorno(v_tid, '301', 'erro cru');
        SELECT status INTO v_status FROM public.esocial_transmissoes WHERE id = v_tid;

        -- reenvio: regenera; nao pode criar linha nova
        PERFORM public.ferias_esocial_gerar(v_calc);
        SELECT count(*) INTO v_qtd_depois FROM public.esocial_transmissoes WHERE ferias_calculo_id = v_calc;

        RAISE EXCEPTION 'qa_rollback';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM <> 'qa_rollback' THEN
            r.situacao := 'erro'; r.obtido := 'A sonda quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
        END IF;
    END;

    IF v_status = 'rejeitado' AND v_traducao NOT LIKE '%erro cru%'
       AND v_qtd_antes = 3 AND v_qtd_depois = 3 THEN
        r.situacao := 'passou';
        r.obtido := 'Rejeicao traduzida (schema/leiaute) e reenvio manteve 3 eventos — sem duplicar.';
    ELSE
        r.situacao := 'falhou';
        r.obtido := format('status=%s traducao=%s antes=%s depois=%s.',
                           v_status, v_traducao, v_qtd_antes, v_qtd_depois);
    END IF;
    RETURN r;
EXCEPTION WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_082()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
    r public.qa_retorno; v_ten uuid; v_calc uuid;
    v_s1200 jsonb; v_s1210 jsonb;
BEGIN
    r.passo_ordem := 1;
    r.passo_acao := 'AUDITORIA: as ferias refletem no S-1200 (rubricas) e S-1210 (detPgtoFer)?';
    r.esperado := 'S-1200 com ferias e terco na competencia; S-1210 com a data real do pagamento';

    IF to_regproc('public.ferias_esocial_gerar') IS NULL THEN
        r.situacao := 'falhou'; r.obtido := 'Sem geracao dos eventos de folha (RF-008).'; RETURN r; END IF;
    v_ten := public.qa_sandbox_tenant_id();
    IF v_ten IS NULL THEN r.situacao := 'nao_implementado'; r.obtido := 'Sem tenants.'; RETURN r; END IF;

    BEGIN
        v_calc := public.qa_ferias_sonda_calculo(v_ten);
        PERFORM public.ferias_esocial_gerar(v_calc);
        SELECT xml_enviado::jsonb INTO v_s1200 FROM public.esocial_transmissoes
         WHERE ferias_calculo_id = v_calc AND tipo_evento = 'S-1200';
        SELECT xml_enviado::jsonb INTO v_s1210 FROM public.esocial_transmissoes
         WHERE ferias_calculo_id = v_calc AND tipo_evento = 'S-1210';
        RAISE EXCEPTION 'qa_rollback';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM <> 'qa_rollback' THEN
            r.situacao := 'erro'; r.obtido := 'A sonda quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
        END IF;
    END;

    IF v_s1200 IS NOT NULL AND v_s1210 IS NOT NULL
       AND jsonb_array_length(v_s1200->'itensRemun') = 2
       AND (v_s1210->'detPgtoFer'->>'dtPgto') = (CURRENT_DATE + 37)::text THEN
        r.situacao := 'passou';
        r.obtido := 'S-1200 com ferias+terco e S-1210 com a data real do pagamento (prova o D-2).';
    ELSE
        r.situacao := 'falhou';
        r.obtido := format('S-1200=%s S-1210 dtPgto=%s.',
                           v_s1200 IS NOT NULL, v_s1210->'detPgtoFer'->>'dtPgto');
    END IF;
    RETURN r;
EXCEPTION WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_090()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o desligamento consome os períodos de férias?';
  r.esperado := 'Vencidas integrais (dobro se concessivo vencido) + proporcionais por duodécimos, ambas + 1/3';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%ferias_periodos%'
    AND (p.prosrc ILIKE '%rescis%' OR p.prosrc ILIKE '%deslig%' OR p.prosrc ILIKE '%indeniza%');
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o desligamento não conversa com os períodos de férias — nenhuma '
             || 'função apura vencidas + proporcionais + 1/3 na rescisão (arts. 146-148; '
             || 'Súmula 171). Colaborador desligado com período vencido sai sem a verba '
             || 'calculada e os períodos ficam abertos para sempre no módulo. Mesma lacuna do '
             || 'banco de horas na rescisão (PONTO-173): a saída do colaborador precisa '
             || 'liquidar os dois. Correção: gatilho de desligamento que fecha os períodos '
             || 'como indenizados, com memória e vínculo ao termo.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Liquidação presente em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_091()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text := public.qa_cpf(6191);
        v_colidiu boolean := false;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Abrir o MESMO período aquisitivo do MESMO CPF em duas empresas (dois vínculos)';
  r.esperado := 'Dois relógios independentes — contratos são autônomos entre si';
  INSERT INTO public.ferias_periodos_aquisitivos
    (tenant_id, empresa_id, colaborador_cpf, colaborador_nome, data_admissao,
     aquisitivo_inicio, aquisitivo_fim, faltas_carga, dias_gozados, fonte_faltas,
     dias_direito, dias_saldo, faltas_consideradas, status, origem)
  VALUES (public.qa_sandbox_tenant_id(), gen_random_uuid(), v_cpf, 'QA Dois Vínculos F',
          CURRENT_DATE - 400, CURRENT_DATE - 395, CURRENT_DATE - 30,
          0, 0, 'carga', 30, 30, 0, 'ativo', 'sistema');
  BEGIN
    INSERT INTO public.ferias_periodos_aquisitivos
      (tenant_id, empresa_id, colaborador_cpf, colaborador_nome, data_admissao,
       aquisitivo_inicio, aquisitivo_fim, faltas_carga, dias_gozados, fonte_faltas,
       dias_direito, dias_saldo, faltas_consideradas, status, origem)
    VALUES (public.qa_sandbox_tenant_id(), gen_random_uuid(), v_cpf, 'QA Dois Vínculos F',
            CURRENT_DATE - 400, CURRENT_DATE - 395, CURRENT_DATE - 30,
            0, 0, 'carga', 30, 30, 0, 'ativo', 'sistema');
  EXCEPTION WHEN unique_violation THEN
    v_colidiu := true;
  END;

  IF v_colidiu THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO ESTRUTURAL (mesma raiz do PONTO-394): o período aquisitivo é chaveado '
             || 'por (tenant, CPF, início) — a constraint ferias_periodo_unico ignora a '
             || 'empresa/vínculo, mesmo com a coluna empresa_id existindo na tabela. Dois '
             || 'contratos do mesmo CPF admitidos na mesma época COLIDEM: o segundo vínculo '
             || 'não consegue ter o próprio relógio de férias. Correção: incluir o vínculo na '
             || 'chave (tenant, empresa, CPF, início) e propagar a segregação para programação '
             || 'e solicitações.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Cada vínculo abriu o próprio período — relógios independentes.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
  ('FERIAS-001','qa_caso_ferias_001', true),
  ('FERIAS-002','qa_caso_ferias_002', true),
  ('FERIAS-003','qa_caso_ferias_003', true),
  ('FERIAS-004','qa_caso_ferias_004', true),
  ('FERIAS-005','qa_caso_ferias_005', true),
  ('FERIAS-006','qa_caso_ferias_006', true),
  ('FERIAS-007','qa_caso_ferias_007', true),
  ('FERIAS-008','qa_caso_ferias_008', true),
  ('FERIAS-010','qa_caso_ferias_010', true),
  ('FERIAS-011','qa_caso_ferias_011', true),
  ('FERIAS-012','qa_caso_ferias_012', true),
  ('FERIAS-013','qa_caso_ferias_013', true),
  ('FERIAS-014','qa_caso_ferias_014', true),
  ('FERIAS-015','qa_caso_ferias_015', true),
  ('FERIAS-016','qa_caso_ferias_016', true),
  ('FERIAS-017','qa_caso_ferias_017', true),
  ('FERIAS-020','qa_caso_ferias_020', true),
  ('FERIAS-021','qa_caso_ferias_021', true),
  ('FERIAS-022','qa_caso_ferias_022', true),
  ('FERIAS-023','qa_caso_ferias_023', true),
  ('FERIAS-024','qa_caso_ferias_024', true),
  ('FERIAS-030','qa_caso_ferias_030', true),
  ('FERIAS-031','qa_caso_ferias_031', true),
  ('FERIAS-032','qa_caso_ferias_032', true),
  ('FERIAS-033','qa_caso_ferias_033', true),
  ('FERIAS-034','qa_caso_ferias_034', true),
  ('FERIAS-035','qa_caso_ferias_035', true),
  ('FERIAS-040','qa_caso_ferias_040', true),
  ('FERIAS-041','qa_caso_ferias_041', true),
  ('FERIAS-042','qa_caso_ferias_042', true),
  ('FERIAS-050','qa_caso_ferias_050', true),
  ('FERIAS-051','qa_caso_ferias_051', true),
  ('FERIAS-052','qa_caso_ferias_052', true),
  ('FERIAS-053','qa_caso_ferias_053', true),
  ('FERIAS-054','qa_caso_ferias_054', true),
  ('FERIAS-055','qa_caso_ferias_055', true),
  ('FERIAS-056','qa_caso_ferias_056', true),
  ('FERIAS-060','qa_caso_ferias_060', true),
  ('FERIAS-061','qa_caso_ferias_061', true),
  ('FERIAS-062','qa_caso_ferias_062', true),
  ('FERIAS-070','qa_caso_ferias_070', true),
  ('FERIAS-071','qa_caso_ferias_071', true),
  ('FERIAS-080','qa_caso_ferias_080', true),
  ('FERIAS-081','qa_caso_ferias_081', true),
  ('FERIAS-082','qa_caso_ferias_082', true),
  ('FERIAS-090','qa_caso_ferias_090', true),
  ('FERIAS-091','qa_caso_ferias_091', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

WITH alvo AS (SELECT codigo, funcao_sql FROM public.qa_implementacoes WHERE codigo LIKE 'FERIAS-%' AND ativo)
SELECT (public.qa_executar_descartavel(a.funcao_sql)).situacao::text AS situacao, count(*) AS qtd
FROM alvo a GROUP BY 1 ORDER BY 2 DESC;
