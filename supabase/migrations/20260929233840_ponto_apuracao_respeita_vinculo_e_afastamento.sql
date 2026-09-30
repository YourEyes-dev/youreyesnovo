-- ============================================================================
-- Ponto — a apuração de saldo só conta dias em que a pessoa está TRABALHANDO
--
-- RAIZ (relato: "o banco puxa débito de quem já saiu / de quem está afastado";
-- desligadas e afastada reapareciam com -518/mês). O gerador de dias da
-- apuração (ponto_saldo_dias_competencia_bruto) emite um dia "sintético" — sem
-- marcação, débito de uma jornada inteira — para todo dia útil dentro da janela
-- da ESCALA, mesmo depois do desligamento ou durante o afastamento. Duas causas:
--   (1) não havia limite de VÍNCULO: a janela vinha só das atribuições de
--       escala, que nunca eram fechadas no desligamento; e
--   (2) o afastamento só protegia o dia quando havia uma linha em ponto_diario
--       com tipo_dia='afastamento' — o dia sintético (sem linha) escapava.
--
-- O QUE FAZ (aditivo, cirúrgico — só a apuração, nada de reescrever passado):
--   A) [vinculo-corte] Se o CPF tem admissão efetivada (concluido/desligado) e
--      NENHUMA cobre o dia por [data_admissao, COALESCE(data_desligamento,∞)],
--      o dia está fora de contrato e não gera saldo. Mantém o dia da admissão e
--      o do desligamento (corte estritamente APÓS — cobre aviso prévio
--      trabalhado). Filtra por VÍNCULO, não por pessoa: dois vínculos = união
--      das janelas; sem admissão efetivada, não corta nada (preserva o antigo).
--   B) [afast-protege] Dia dentro do período de QUALQUER afastamento registrado
--      (por intervalo de datas — ativo/encerrado/beneficio_inss; o próprio
--      registro delimita por data_inicio/data_fim; data_fim nula protege de
--      data_inicio em diante) fica protegido (saldo 0), sem depender de linha em
--      ponto_diario. EXCEÇÃO: dia de FRONTEIRA (=data_inicio ou =data_fim) COM
--      marcação apura normal (meio período trabalha, meio afasta — art. 60 CLT).
--      O tipo do afastamento segue disponível para a folha (nada é apagado).
--   C) Fecha a atribuição de escala no desligamento (gatilho + backfill): o
--      gerador de dias para de emitir dias após o fim do contrato também pela
--      via da escala (defesa em profundidade da causa 1).
--
-- NÃO reapura competências passadas. Só corrige o MOTOR; a reapuração auditável
-- dos meses já fechados (com versão do espelho e trilha) é etapa à parte.
--
-- Aplicação por pg_get_functiondef + replace (o corpo real vem de várias ondas
-- de patch; ancoramos em trechos estáveis, com marcadores idempotentes e recusa
-- segura se o corpo divergir). Espelha o padrão de 20260902100000.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- A + B) Motor: corte por vínculo e proteção por afastamento
-- ----------------------------------------------------------------------------
DO $item$
DECLARE
  v_nome text;
  v_src  text;
  v_novo text;
  v_achou boolean := false;
  v_ja_alvo text;
  v_ja_troca text;
  v_prot_alvo text;
  v_prot_troca text;
BEGIN
  v_ja_alvo := E'    v_ja_emitiu := v_ja_emitiu || r.data;';

  v_ja_troca := v_ja_alvo || E'\n'
    || E'\n'
    || E'    -- [vinculo-corte] So apura dias dentro de um vinculo de emprego real.\n'
    || E'    -- Se o CPF tem admissao efetivada (concluido/desligado) e NENHUMA cobre\n'
    || E'    -- este dia pelo intervalo [data_admissao, COALESCE(data_desligamento,\n'
    || E'    -- ''infinity'')], o dia esta fora de contrato (antes de admitir, ou depois\n'
    || E'    -- de desligar, incluindo aviso previo trabalhado) e nao gera saldo. Mantem\n'
    || E'    -- o dia da admissao e o do desligamento (corte estritamente APOS). Filtra\n'
    || E'    -- por VINCULO, nao por pessoa: dois vinculos = uniao das janelas; sem\n'
    || E'    -- nenhuma admissao efetivada, nao corta nada (preserva o anterior).\n'
    || E'    IF EXISTS (\n'
    || E'      SELECT 1 FROM public.admissoes adm\n'
    || E'      WHERE adm.tenant_id = p_tenant_id\n'
    || E'        AND regexp_replace(COALESCE(adm.cpf, ''''), ''[^0-9]'', '''', ''g'') = v_cpf\n'
    || E'        AND adm.data_admissao IS NOT NULL\n'
    || E'        AND adm.status::text IN (''concluido'', ''desligado'')\n'
    || E'    ) AND NOT EXISTS (\n'
    || E'      SELECT 1 FROM public.admissoes adm\n'
    || E'      WHERE adm.tenant_id = p_tenant_id\n'
    || E'        AND regexp_replace(COALESCE(adm.cpf, ''''), ''[^0-9]'', '''', ''g'') = v_cpf\n'
    || E'        AND adm.data_admissao IS NOT NULL\n'
    || E'        AND adm.status::text IN (''concluido'', ''desligado'')\n'
    || E'        AND adm.data_admissao <= r.data\n'
    || E'        AND COALESCE(adm.data_desligamento, ''infinity''::date) >= r.data\n'
    || E'    ) THEN\n'
    || E'      CONTINUE;\n'
    || E'    END IF;';

  v_prot_alvo := E'    v_prot_credito := v_protegido';

  v_prot_troca :=
       E'    -- [afast-protege] Dia dentro do periodo de um afastamento (por intervalo\n'
    || E'    -- de datas, nao por status): protege o dia para nao virar debito enquanto\n'
    || E'    -- o colaborador esta afastado. Vale para qualquer afastamento registrado\n'
    || E'    -- (ativo, encerrado, beneficio_inss) — o proprio registro delimita o\n'
    || E'    -- periodo por data_inicio/data_fim; data_fim nula protege de data_inicio em\n'
    || E'    -- diante. EXCECAO (art. 60 CLT / operacao): dia de FRONTEIRA (= data_inicio\n'
    || E'    -- ou = data_fim) COM marcacao apura normal — meio periodo trabalha, meio\n'
    || E'    -- afasta. O tipo do afastamento segue disponivel para a folha (esta funcao\n'
    || E'    -- nao apaga nada; so deixa de debitar).\n'
    || E'    -- v_protegido pode vir NULL (dia sintetico: r.status NULL => a\n'
    || E'    -- expressao acima resolve NULL), por isso o COALESCE.\n'
    || E'    IF NOT COALESCE(v_protegido, false) THEN\n'
    || E'      v_protegido := EXISTS (\n'
    || E'        SELECT 1 FROM public.afastamentos af\n'
    || E'        WHERE af.tenant_id = p_tenant_id\n'
    || E'          AND regexp_replace(COALESCE(af.colaborador_cpf, ''''), ''[^0-9]'', '''', ''g'') = v_cpf\n'
    || E'          AND af.data_inicio IS NOT NULL\n'
    || E'          AND af.data_inicio <= r.data\n'
    || E'          AND COALESCE(af.data_fim, ''infinity''::date) >= r.data\n'
    || E'          AND NOT (\n'
    || E'            (r.data = af.data_inicio OR (af.data_fim IS NOT NULL AND r.data = af.data_fim))\n'
    || E'            AND (\n'
    || E'              r.entrada IS NOT NULL OR r.saida IS NOT NULL\n'
    || E'              OR COALESCE(floor(EXTRACT(EPOCH FROM r.horas_trabalhadas)/60)::int, 0) > 0\n'
    || E'            )\n'
    || E'          )\n'
    || E'      );\n'
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
      CONTINUE;  -- nao existe, ou e so a casca que delega para o miolo
    END IF;

    IF position('[vinculo-corte]' IN v_src) > 0
       AND position('[afast-protege]' IN v_src) > 0 THEN
      RAISE NOTICE '% ja corta fora do vinculo e protege dia de afastamento — nada a fazer.', v_nome;
      v_achou := true;
      CONTINUE;
    END IF;

    IF position(v_ja_alvo IN v_src) = 0 OR position(v_prot_alvo IN v_src) = 0 THEN
      RAISE NOTICE 'ATENCAO: em % as ancoras esperadas nao foram encontradas. Corpo divergente; NADA alterado. Envie o pg_get_functiondef para reconciliar.', v_nome;
      CONTINUE;
    END IF;

    v_novo := replace(v_src, v_ja_alvo, v_ja_troca);
    v_novo := replace(v_novo, v_prot_alvo, v_prot_troca);
    EXECUTE v_novo;
    v_achou := true;
    RAISE NOTICE 'Em %: dia fora do vinculo nao debita e dia de afastamento fica protegido.', v_nome;
  END LOOP;

  IF NOT v_achou THEN
    RAISE NOTICE 'A apuracao de saldo nao foi encontrada nesta base — nada a corrigir.';
  END IF;
END $item$;

-- ----------------------------------------------------------------------------
-- C) Fechar a atribuicao de escala no desligamento (gatilho + backfill)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admissao_fecha_escala_desligamento()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_cpf text := regexp_replace(COALESCE(NEW.cpf, ''), '[^0-9]', '', 'g');
BEGIN
  -- So age quando ha data de desligamento (fim efetivo do contrato, incluindo
  -- aviso previo trabalhado). Fecha as atribuicoes de escala ainda abertas (ou
  -- que terminariam depois) na data do desligamento, para o gerador de dias da
  -- apuracao parar de emitir dias apos o fim do contrato tambem pela via da
  -- escala. Toca so as atribuicoes que comecaram ate a data do desligamento
  -- (nao mexe em vinculo posterior, no caso de readmissao). Idempotente.
  IF NEW.data_desligamento IS NOT NULL AND v_cpf <> '' THEN
    UPDATE public.ponto_escala_atribuicoes
       SET data_fim = NEW.data_desligamento
     WHERE tenant_id = NEW.tenant_id
       AND regexp_replace(COALESCE(colaborador_cpf, ''), '[^0-9]', '', 'g') = v_cpf
       AND data_inicio <= NEW.data_desligamento
       AND (data_fim IS NULL OR data_fim > NEW.data_desligamento);
  END IF;
  RETURN NEW;
END $function$;

DROP TRIGGER IF EXISTS trg_admissao_fecha_escala_desligamento ON public.admissoes;
CREATE TRIGGER trg_admissao_fecha_escala_desligamento
AFTER UPDATE OF data_desligamento, status ON public.admissoes
FOR EACH ROW EXECUTE FUNCTION public.admissao_fecha_escala_desligamento();

-- Backfill: fecha atribuicoes de escala de quem JA esta desligado e nao tem
-- vinculo ativo (concluido). Conservador para nao tocar readmitidos/ativos.
-- (Em producao, o script de entrega guarda as linhas antes de alterar.)
DO $bf$
BEGIN
  UPDATE public.ponto_escala_atribuicoes ea
     SET data_fim = d.desl
  FROM (
    SELECT a.tenant_id,
           regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g') AS cpf_num,
           MAX(a.data_desligamento) AS desl
    FROM public.admissoes a
    WHERE a.status::text = 'desligado'
      AND a.data_desligamento IS NOT NULL
    GROUP BY a.tenant_id, regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g')
  ) d
  WHERE d.tenant_id = ea.tenant_id
    AND regexp_replace(COALESCE(ea.colaborador_cpf, ''), '[^0-9]', '', 'g') = d.cpf_num
    AND ea.data_inicio <= d.desl
    AND (ea.data_fim IS NULL OR ea.data_fim > d.desl)
    AND NOT EXISTS (
      SELECT 1 FROM public.admissoes a2
      WHERE a2.tenant_id = ea.tenant_id
        AND regexp_replace(COALESCE(a2.cpf, ''), '[^0-9]', '', 'g') = d.cpf_num
        AND a2.status::text = 'concluido'
    );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Backfill de escala pulado: %', SQLERRM;
END $bf$;

-- ----------------------------------------------------------------------------
-- QA — Documentação de Testes + Execução (casos api)
-- ----------------------------------------------------------------------------
-- PONTO-475 — apuração não debita dia fora do vínculo
INSERT INTO public.qa_casos_teste
  (codigo, modulo_id, titulo, objetivo, tipo, nivel, prioridade, status,
   base_legal, passos, disposicao, observacoes)
SELECT
  'PONTO-475',
  m.id,
  'Apuração só conta dias dentro do vínculo de emprego',
  'A apuração de saldo emitia um dia "sintético" — sem marcação, débito de uma '
  || 'jornada inteira — para todo dia útil dentro da janela da escala, mesmo depois '
  || 'do desligamento. Ex-colaborador reaparecia devendo horas de meses em que já '
  || 'não trabalhava. O dia da apuração tem de respeitar o contrato: nada antes da '
  || 'admissão nem depois do desligamento (mantendo o próprio dia da admissão e o do '
  || 'desligamento, que cobre o aviso prévio trabalhado). Filtra por VÍNCULO: dois '
  || 'contratos somam suas janelas; sem admissão efetivada registrada, nada muda.',
  'negativo',
  'api',
  'critica',
  'aprovado',
  'CLT art. 59, §2º; CLT art. 487-491 (aviso prévio)',
  jsonb_build_array(
    jsonb_build_object('ordem', 1,
      'acao', 'Apurar um dia útil POSTERIOR ao desligamento, sem marcação',
      'esperado', 'O dia não gera linha nem débito — está fora do contrato'),
    jsonb_build_object('ordem', 2,
      'acao', 'Conferir que o dia do desligamento (trabalhado) continua sendo apurado',
      'esperado', 'O dia do desligamento é mantido e apurado normalmente')
  ),
  'em_triagem',
  'Nasceu da correção de raiz do banco de horas (set/2026): desligados e afastados reapareciam com débito.'
FROM public.qa_modulos m
WHERE m.path = 'jornada-rotina/ponto'
ON CONFLICT (codigo) DO NOTHING;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_475()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid;
  v_cpf text := public.qa_cpf(4751);
  v_base date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
  v_mon date;
  v_desl date;
  v_apos date;
  v_rows_apos int;
  v_rows_desl int;
  v_saldo_desl int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Apurar um dia util posterior ao desligamento, sem marcacao';
  r.esperado    := 'O dia nao gera linha nem debito — esta fora do contrato';

  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();
  v_mon := v_base + ((8 - EXTRACT(ISODOW FROM v_base)::int) % 7);  -- 1a segunda
  v_desl := v_mon + 7;    -- desligamento na 2a segunda
  v_apos := v_mon + 14;   -- 3a segunda, apos o desligamento

  -- Vinculo limpo a cada corrida (evita "reversao de desligamento" ao reusar a
  -- linha desligada de uma corrida anterior): apaga e cria concluido, depois
  -- desliga.
  DELETE FROM public.admissoes WHERE tenant_id = v_t AND cpf = v_cpf;
  INSERT INTO public.admissoes
    (tenant_id, nome_completo, cpf, email, cargo, status, data_admissao)
  VALUES (v_t, 'QA Vinculo Corte', v_cpf,
          public.qa_fixture_email('PONTO-475', 4751), 'Operador', 'concluido', v_base - 200);
  UPDATE public.admissoes SET status = 'desligado', data_desligamento = v_desl
   WHERE tenant_id = v_t AND cpf = v_cpf;
  -- Escala aberta cobrindo o mes, criada APOS o desligamento (isola o corte por
  -- vinculo do fechamento de escala pelo gatilho).
  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Vinculo Corte', 480, 10, v_base - 200, NULL);
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Vinculo Corte', v_desl, 480);  -- trabalhou o dia do desligamento

  SELECT COUNT(*) INTO v_rows_apos
  FROM public.ponto_saldo_dias_competencia(v_t, v_cpf, to_char(v_apos, 'YYYY-MM')) s
  WHERE s.dia = v_apos;

  SELECT COUNT(*), COALESCE(MIN(s.saldo_min), 999) INTO v_rows_desl, v_saldo_desl
  FROM public.ponto_saldo_dias_competencia(v_t, v_cpf, to_char(v_desl, 'YYYY-MM')) s
  WHERE s.dia = v_desl;

  IF v_rows_apos = 0 AND v_rows_desl = 1 AND v_saldo_desl = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'O dia posterior ao desligamento nao gerou linha e o dia do desligamento foi apurado (saldo 0).';
  ELSIF v_rows_apos > 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: um dia posterior ao desligamento (%s) ainda gera apuracao. '
             || 'Ex-colaborador volta a acumular debito de mes em que nao trabalhava.', v_apos);
    r.detalhe := jsonb_build_object('linhas_apos_desligamento', v_rows_apos,
                   'dia_desligamento_linhas', v_rows_desl, 'dia_desligamento_saldo', v_saldo_desl);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Resultado inesperado: dia do desligamento linhas=%s saldo=%s (esperado 1/0).',
                   v_rows_desl, v_saldo_desl);
    r.detalhe := jsonb_build_object('dia_desligamento_linhas', v_rows_desl, 'dia_desligamento_saldo', v_saldo_desl);
  END IF;

  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
VALUES ('PONTO-475', 'qa_caso_ponto_475', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- PONTO-476 — dia dentro do afastamento não vira débito (fronteira com marcação apura)
INSERT INTO public.qa_casos_teste
  (codigo, modulo_id, titulo, objetivo, tipo, nivel, prioridade, status,
   base_legal, passos, disposicao, observacoes)
SELECT
  'PONTO-476',
  m.id,
  'Dia dentro do afastamento é protegido; fronteira com marcação apura',
  'Durante um afastamento, os dias úteis sem marcação viravam débito de jornada '
  || 'inteira na apuração de saldo. Quem está afastado não deve horas. O dia dentro '
  || 'do período do afastamento (por intervalo de datas — vale para afastamento '
  || 'ativo, encerrado ou benefício INSS) fica protegido, com saldo zero, sem '
  || 'depender de uma linha no espelho. Exceção: o dia de fronteira (início ou fim '
  || 'do afastamento) com marcação é apurado normalmente — meio período de trabalho, '
  || 'meio de afastamento (CLT art. 60). O tipo do afastamento segue disponível para '
  || 'a folha; a apuração apenas deixa de debitar, não apaga nada.',
  'negativo',
  'api',
  'critica',
  'aprovado',
  'CLT art. 59, §2º; CLT art. 60; Lei 8.213/1991 (benefício)',
  jsonb_build_array(
    jsonb_build_object('ordem', 1,
      'acao', 'Apurar um dia útil no interior de um afastamento, sem marcação',
      'esperado', 'Saldo 0 e dia marcado como protegido — afastado não deve horas'),
    jsonb_build_object('ordem', 2,
      'acao', 'Apurar o dia de início do afastamento com marcação parcial (240 de 480)',
      'esperado', 'O dia é apurado normalmente (saldo negativo), não protegido')
  ),
  'em_triagem',
  'Nasceu da correção de raiz do banco de horas (set/2026): desligados e afastados reapareciam com débito.'
FROM public.qa_modulos m
WHERE m.path = 'jornada-rotina/ponto'
ON CONFLICT (codigo) DO NOTHING;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_476()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid;
  v_cpf text := public.qa_cpf(4761);
  v_base date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
  v_mon date;
  v_ini date; v_fim date; v_interior date;
  v_saldo_int int; v_prot_int boolean; v_rows_int int;
  v_saldo_ini int; v_prot_ini boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Apurar um dia interior de afastamento (sem marcacao) e a fronteira com marcacao';
  r.esperado    := 'Interior protegido (saldo 0); fronteira com marcacao apura (saldo negativo)';

  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();
  v_mon := v_base + ((8 - EXTRACT(ISODOW FROM v_base)::int) % 7);  -- 1a segunda
  v_ini := v_mon;          -- inicio do afastamento
  v_fim := v_mon + 10;     -- fim do afastamento
  v_interior := v_mon + 2; -- 1a quarta (interior, dia util)

  PERFORM public.qa_ponto_admissao('QA Afast Protege', 4761, NULL, v_base - 200);
  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Afast Protege', 480, 10, v_base - 200, NULL);
  INSERT INTO public.afastamentos (tenant_id, colaborador_nome, colaborador_cpf,
     data_inicio, data_fim, status)
  VALUES (v_t, 'QA Afast Protege', v_cpf, v_ini, v_fim, 'ativo');
  -- Marcacao parcial no dia de INICIO (fronteira com marcacao): apura normal.
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Afast Protege', v_ini, 240);

  SELECT COUNT(*), COALESCE(MIN(s.saldo_min), 999), COALESCE(bool_or(s.protegido), false)
    INTO v_rows_int, v_saldo_int, v_prot_int
  FROM public.ponto_saldo_dias_competencia(v_t, v_cpf, to_char(v_interior, 'YYYY-MM')) s
  WHERE s.dia = v_interior;

  SELECT COALESCE(MIN(s.saldo_min), 999), COALESCE(bool_or(s.protegido), false)
    INTO v_saldo_ini, v_prot_ini
  FROM public.ponto_saldo_dias_competencia(v_t, v_cpf, to_char(v_ini, 'YYYY-MM')) s
  WHERE s.dia = v_ini;

  IF v_rows_int = 1 AND v_saldo_int = 0 AND v_prot_int
     AND v_saldo_ini = (240 - 480) AND NOT v_prot_ini THEN
    r.situacao := 'passou';
    r.obtido := format('Dia interior protegido (saldo 0) e fronteira com marcacao apurada (saldo %s).', v_saldo_ini);
  ELSIF v_saldo_int < 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: dia interior de afastamento gerou debito de %s minutos. '
             || 'Quem esta afastado nao deve horas.', v_saldo_int);
    r.detalhe := jsonb_build_object('saldo_interior', v_saldo_int, 'prot_interior', v_prot_int,
                   'saldo_inicio', v_saldo_ini, 'prot_inicio', v_prot_ini);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Resultado inesperado: interior saldo=%s prot=%s; inicio saldo=%s prot=%s '
             || '(esperado interior 0/protegido, inicio -240/nao protegido).',
             v_saldo_int, v_prot_int, v_saldo_ini, v_prot_ini);
    r.detalhe := jsonb_build_object('saldo_interior', v_saldo_int, 'prot_interior', v_prot_int,
                   'saldo_inicio', v_saldo_ini, 'prot_inicio', v_prot_ini);
  END IF;

  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
VALUES ('PONTO-476', 'qa_caso_ponto_476', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
