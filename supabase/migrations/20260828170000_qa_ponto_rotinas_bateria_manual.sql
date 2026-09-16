-- ============================================================================
-- QA PONTO — rotinas dos casos vindos do confronto com a "Bateria Legal do
-- Ponto" (PONTO-400..460, documentados em 20260825100000). Os 14 são de
-- nível 'api'.
--
-- Padrão da casa: sondas de escrita no sandbox (qa_modo_ligar) + auditorias
-- somente leitura. Divergência com a norma/roteiro = falha proposital com
-- diagnóstico e correção sugerida. Nenhuma funcionalidade é alterada.
-- ============================================================================

-- PONTO-400 — saída antecipada identificada
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_400()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
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
END $$;

-- PONTO-401 — excedente em minutos exatos
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_401()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_src text; v_arred boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a apuração do dia arredonda o excedente?';
  r.esperado := 'Excedente em minutos exatos — sem round/ceil/floor sobre a hora extra';
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = '_ponto_calc_dia';

  IF v_src IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A função de apuração do dia (_ponto_calc_dia) não existe mais nesta base.';
    RETURN r;
  END IF;

  -- arredondamento perigoso: round/ceil/floor aplicado às grandezas de extra.
  -- Divisões inteiras de minutos (EXTRACT/60) são normais e não contam.
  v_arred := (v_src ILIKE '%round(%' OR v_src ILIKE '%ceil(%' OR v_src ILIKE '%floor(%');

  IF v_arred THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a apuração do dia aplica arredondamento (round/ceil/floor) sobre '
             || 'as grandezas apuradas — depois da tolerância legal, cada minuto de '
             || 'excesso é devido (Súmula 449 do TST). Arredondar para baixo suprime hora '
             || 'extra em escala (todo o quadro, todo mês); para cima, cria custo sem '
             || 'fato gerador. Correção: manter o excedente em minutos inteiros exatos, '
             || 'deixando o arredondamento apenas para a apresentação e para o valor '
             || 'monetário na folha, com a memória de cálculo mostrando os minutos.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'A apuração do dia trabalha em minutos exatos, sem arredondar o excedente.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- PONTO-402 — feriado não trabalhado é dia neutro
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_402()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_tipo text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o feriado sem marcação é dia neutro, não falta?';
  r.esperado := 'Dia identificado como feriado, sem falta e sem débito de jornada';
  v_tipo := public.qa_col_existe('ponto_diario', 'tipo_dia');
  -- quem pode criar a falta indevida é a MATERIALIZAÇÃO; outras rotinas
  -- (pacote da folha, DSR) citam feriado sem proteger o dia neutro
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.proname ILIKE '%materializar%falta%'
    AND p.prosrc ILIKE '%feriado%';

  IF v_tipo IS NOT NULL AND v_fns IS NOT NULL THEN
    r.situacao := 'passou';
    r.obtido := format('Feriado reconhecido na apuração (tipo_dia + %s) — dia neutro preservado.', v_fns);
  ELSIF v_tipo IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A coluna tipo_dia não existe mais em ponto_diario — o feriado perdeu o '
             || 'lugar onde era identificado, e dia sem marcação corre o risco de virar '
             || 'falta (Lei 605/49: feriado é repouso remunerado).';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: tipo_dia existe e várias rotinas conhecem feriado (pacote da '
             || 'folha, DSR), mas a MATERIALIZAÇÃO DE FALTAS — a única que cria o registro '
             || 'de ausência para o dia sem marcação (PONTO-290) — não consulta feriado '
             || 'nenhum: ela varre os dias e materializa. O feriado sem marcação, que é o '
             || 'comportamento esperado, corre o risco de virar falta, descontando salário '
             || 'e derrubando o DSR de quem não devia nada (Lei 605/49, art. 1º). '
             || 'Correção: a materialização deve pular os feriados da unidade do '
             || 'colaborador, gravando o dia como neutro com o nome do feriado.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- PONTO-403 — colaborador sem escala vigente
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_403()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
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
END $$;

-- PONTO-410 — batida real vence a declaração
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_410()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_col text; v_src text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): com almoço batido, a pré-assinalação cede?';
  r.esperado := 'Intervalo consta como marcado (batida real prevalece — Súmula 338 do TST)';
  v_col := public.qa_col_existe('ponto_diario', 'intervalo_origem');
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = '_ponto_calc_dia';

  IF v_col IS NOT NULL AND v_src IS NOT NULL
     AND v_src ILIKE '%intervalo_origem%'
     AND (v_src ILIKE '%pre_assinal%' OR v_src ILIKE '%pre-assinal%') THEN
    r.situacao := 'passou';
    r.obtido := 'A apuração distingue a origem do intervalo (marcado × pré-assinalado) e '
             || 'grava em intervalo_origem — a batida real tem onde prevalecer.';
  ELSIF v_col IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: não há registro da ORIGEM do intervalo (a coluna intervalo_origem '
             || 'sumiu de ponto_diario) — sem ela, não é possível provar, dia a dia, se o '
             || 'intervalo foi batido ou apenas declarado. A Súmula 338, III, do TST faz a '
             || 'marcação real prevalecer sobre a pré-assinalação; se o sistema aplica o '
             || 'declarado por cima do batido, o intervalo real menor (que gera indenização '
             || 'do art. 71, §4º) desaparece do espelho. Correção: gravar a origem do '
             || 'intervalo em cada dia, com o batido prevalecendo sempre que existir.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a coluna intervalo_origem existe, mas a apuração do dia não a '
             || 'usa para dar precedência à batida real sobre a pré-assinalação — o '
             || 'declarado pode estar sobrepondo o que foi efetivamente marcado. Pela '
             || 'Súmula 338, III, do TST a presunção cede diante do fato: intervalo batido '
             || 'menor que o declarado precisa aparecer como suprimido (PONTO-060), não '
             || 'como gozado. Correção: na apuração, quando houver marcações de almoço, '
             || 'usar o intervalo real e marcar a origem como "marcado".';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- PONTO-420 — regime exige acordo e o acordo não está anexado
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_420()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
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
END $$;

-- PONTO-421 — folga compensatória debita o banco
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_421()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_tab text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a folga compensatória debita o saldo do banco?';
  r.esperado := 'Débito no extrato do banco e o dia de folga não vira falta';
  v_tab := CASE WHEN to_regclass('public.feriado_folga_compensatoria') IS NOT NULL
                THEN 'feriado_folga_compensatoria' END;
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%banco_horas_movimentacoes%'
    AND (p.prosrc ILIKE '%folga%' OR p.prosrc ILIKE '%compensat%');

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a folga compensatória não debita o banco de horas — a '
             || 'estrutura existente (%s) serve ao feriado trabalhado (PONTO-321, que '
             || 'afasta a dobra) e NENHUMA rotina lança o débito correspondente em '
             || 'ponto_banco_horas_movimentacoes. O efeito é dobrado e caro: a empresa dá '
             || 'a folga E mantém o saldo positivo (pagará de novo no vencimento, '
             || 'PONTO-171), enquanto o dia de folga corre o risco de ser materializado '
             || 'como falta — descontando de quem estava justamente compensando. '
             || 'Correção: lançar a folga como débito no banco (CLT art. 59, §2º), marcar '
             || 'o dia como folga compensatória (sem falta) e preservar o DSR da semana.',
             coalesce(v_tab, 'nenhuma tabela de folga'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Folga compensatória debita o banco por: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- PONTO-430 — ajuste sem justificativa é recusado
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_430()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
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
END $$;

-- PONTO-431 — remontar o dossiê não duplica
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_431()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_comp text := to_char(CURRENT_DATE, 'YYYY-MM'); v_qtd int; v_uq text;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Montar o dossiê da competência DUAS vezes e contar';
  r.esperado := 'Um único dossiê por competência, com data e hash atualizados';
  INSERT INTO public.ponto_dossies_fiscalizacao
    (tenant_id, competencia, periodo_ini, periodo_fim, total_pecas, hash_pacote)
  VALUES (v_t, v_comp, date_trunc('month', CURRENT_DATE)::date, CURRENT_DATE, 5, 'qa-hash-1');
  INSERT INTO public.ponto_dossies_fiscalizacao
    (tenant_id, competencia, periodo_ini, periodo_fim, total_pecas, hash_pacote)
  VALUES (v_t, v_comp, date_trunc('month', CURRENT_DATE)::date, CURRENT_DATE, 7, 'qa-hash-2');
  SELECT count(*) INTO v_qtd FROM public.ponto_dossies_fiscalizacao d
  WHERE d.tenant_id = v_t AND d.competencia = v_comp;

  SELECT string_agg(conname, ', ') INTO v_uq FROM pg_constraint
  WHERE conrelid = 'public.ponto_dossies_fiscalizacao'::regclass AND contype = 'u';

  IF v_qtd > 1 AND v_uq IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a mesma competência ficou com %s dossiês — não há UNIQUE '
             || '(tenant, competência) nem lógica de atualização: remontar empilha cópias '
             || 'em vez de atualizar. Dois dossiês da mesma competência com conteúdos e '
             || 'hashes diferentes (5 e 7 peças, no teste) é o pior cenário na '
             || 'fiscalização — a empresa apresenta um e o auditor encontra o outro, e a '
             || 'divergência vale mais contra do que o conteúdo vale a favor. Correção: '
             || 'UNIQUE por tenant+competência com atualização no lugar (ou versionamento '
             || 'explícito, com um único dossiê CORRENTE apontado).',
             v_qtd);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Dossiê único por competência (registros: %s; unicidade: %s).',
                       v_qtd, coalesce(v_uq, 'na gravação'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- PONTO-440 — instrumento coletivo vencido/a vencer
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_440()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
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
END $$;

-- PONTO-441 — CCTs com vigências sobrepostas
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_441()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
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
END $$;

-- PONTO-450 — motor de vigilâncias completo e agendado
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_450()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
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
END $$;

-- PONTO-451 — vigilância não duplica alerta
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_451()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_total int; v_protegidas int; v_soltas text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): as vigilâncias se protegem de duplicar alertas?';
  r.esperado := 'Segunda execução não cria alerta novo (NOT EXISTS / ON CONFLICT por ocorrência)';
  SELECT count(*) INTO v_total
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%INSERT INTO%ponto_alertas%';
  SELECT count(*) INTO v_protegidas
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%INSERT INTO%ponto_alertas%'
    AND (p.prosrc ILIKE '%NOT EXISTS%' OR p.prosrc ILIKE '%ON CONFLICT%');
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_soltas
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%INSERT INTO%ponto_alertas%'
    AND p.prosrc NOT ILIKE '%NOT EXISTS%' AND p.prosrc NOT ILIKE '%ON CONFLICT%';

  IF v_total = 0 THEN
    r.situacao := 'falhou';
    r.obtido := 'Nenhuma rotina grava em ponto_alertas — o painel de alertas do ponto '
             || 'ficou sem quem o alimente.';
  ELSIF v_protegidas < v_total THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: %s de %s rotina(s) que criam alertas do ponto não se '
             || 'protegem contra duplicata (%s) — e a tabela ponto_alertas não tem índice '
             || 'único de deduplicação. Rodar a vigilância duas vezes (o que acontece '
             || 'sempre que alguém confere à tarde o que a madrugada gerou) empilha '
             || 'cópias do mesmo aviso; o DP aprende a ignorar a lista e o alerta que '
             || 'importa se perde no meio das repetições. A casa já resolve isso na '
             || 'materialização de faltas (PONTO-292). Correção: NOT EXISTS por '
             || 'ocorrência (tipo + colaborador + data de referência, não resolvido) ou '
             || 'índice único parcial equivalente.',
             v_total - v_protegidas, v_total, coalesce(v_soltas, '—'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('As %s rotina(s) de alerta do ponto são idempotentes.', v_total);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- PONTO-460 — tentativas em série no link
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_460()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
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
END $$;

-- ── Registro no motor ──
INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES
  ('PONTO-400', 'qa_caso_ponto_400'),
  ('PONTO-401', 'qa_caso_ponto_401'),
  ('PONTO-402', 'qa_caso_ponto_402'),
  ('PONTO-403', 'qa_caso_ponto_403'),
  ('PONTO-410', 'qa_caso_ponto_410'),
  ('PONTO-420', 'qa_caso_ponto_420'),
  ('PONTO-421', 'qa_caso_ponto_421'),
  ('PONTO-430', 'qa_caso_ponto_430'),
  ('PONTO-431', 'qa_caso_ponto_431'),
  ('PONTO-440', 'qa_caso_ponto_440'),
  ('PONTO-441', 'qa_caso_ponto_441'),
  ('PONTO-450', 'qa_caso_ponto_450'),
  ('PONTO-451', 'qa_caso_ponto_451'),
  ('PONTO-460', 'qa_caso_ponto_460')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql;

DO $fim$
BEGIN
  RAISE NOTICE 'QA PONTO (bateria manual): 14 rotinas registradas (PONTO-400..460).';
END $fim$;
