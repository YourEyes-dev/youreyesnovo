-- ============================================================================
-- QA — BANCO DE HORAS CONFIGURÁVEL, FATIA 1 (casos api)
--
--   PONTO-520  precedência do instrumento do colaborador (ACT > vínculo > CCT preponderante)
--   PONTO-521  vínculo ao instrumento: aviso da Súmula 374 e sem sobreposição de vigência
--   PONTO-522  avisos da configuração do banco (sem bloqueio) e sumiço com CCT/ACT vigente
--   PONTO-523  bloqueios legais da configuração + padrões que reproduzem o comportamento de hoje
--   PONTO-524  ponto_banco_regime_vigente: sem_banco é sem banco, respeita data_fim,
--              ignora regra presa a instrumento
--   PONTO-525  restrições do colaborador: aprendiz (bloqueio), menor e insalubre (aviso)
--   PONTO-526  modalidade inferida do prazo nas regras que já existiam (sem aviso falso)
--
-- Rotinas no cercado (tenant sandbox), desfeitas pelo motor ao fim
-- (qa_executar_descartavel). Atribuição só por subconsulta escalar
-- (padrão do SQL Editor de produção). Idempotente.
-- ============================================================================

SET lock_timeout = '10s';

-- Ajudante: id da admissão do cercado pelo CPF-semente (cria se faltar).
CREATE OR REPLACE FUNCTION public.qa_bhf1_admissao(p_nome text, p_semente int, p_empresa uuid)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v_cpf text;
BEGIN
  v_cpf := public.qa_ponto_admissao(p_nome, p_semente, p_empresa, DATE '2026-01-01');
  RETURN (SELECT a.id FROM public.admissoes a
           WHERE a.tenant_id = public.qa_sandbox_tenant_id() AND a.cpf = v_cpf
           ORDER BY (a.status = 'concluido') DESC, a.created_at DESC NULLS LAST LIMIT 1);
END $fn$;

-- Ajudante: instrumento no cercado.
CREATE OR REPLACE FUNCTION public.qa_bhf1_instrumento(
  p_tipo text, p_titulo text, p_empresa uuid, p_categoria text DEFAULT 'preponderante',
  p_representada boolean DEFAULT true, p_ini date DEFAULT NULL, p_fim date DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO public.ponto_acordos
    (id, tenant_id, empresa_id, tipo, titulo, vigencia_inicio, vigencia_fim, ativo, categoria, empresa_representada)
  VALUES (v_id, public.qa_sandbox_tenant_id(), p_empresa, p_tipo, p_titulo, p_ini, p_fim, true, p_categoria, p_representada);
  RETURN v_id;
END $fn$;

-- ── PONTO-520 ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_520()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid; v_emp uuid; v_adm uuid; v_cct uuid; v_dif uuid; v_act uuid;
  d date := DATE '2026-06-01';
  r0 jsonb; r1 jsonb; r2 jsonb; r3 jsonb;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();
  UPDATE public.ponto_acordos SET ativo = false WHERE tenant_id = v_t;
  v_emp := public.qa_nova_empresa('[QA-BHF1] Empresa Precedencia', '11222333052068');
  v_adm := public.qa_bhf1_admissao('[QA-BHF1] Colab Precedencia', 5201, v_emp);

  r.passo_ordem := 1;
  r.passo_acao := 'Resolver o instrumento sem nada cadastrado; depois com CCT preponderante, com CCT diferenciada vinculada e com ACT da empresa';
  r.esperado := 'nenhum -> cct_preponderante -> vinculo_colaborador (com alerta Súm. 374) -> act_empresa';

  r0 := public.ponto_instrumento_do_colaborador(v_t, v_adm, d);
  v_cct := public.qa_bhf1_instrumento('cct', '[QA-BHF1] CCT principal', v_emp, 'preponderante', true, DATE '2026-01-01', DATE '2026-12-31');
  r1 := public.ponto_instrumento_do_colaborador(v_t, v_adm, d);
  v_dif := public.qa_bhf1_instrumento('cct', '[QA-BHF1] CCT diferenciada', NULL, 'diferenciada', false, DATE '2026-01-01', NULL);
  INSERT INTO public.ponto_instrumento_colaborador (tenant_id, admissao_id, instrumento_id, data_inicio)
  VALUES (v_t, v_adm, v_dif, DATE '2026-01-01');
  r2 := public.ponto_instrumento_do_colaborador(v_t, v_adm, d);
  v_act := public.qa_bhf1_instrumento('act', '[QA-BHF1] ACT da empresa', v_emp, 'preponderante', true, DATE '2026-01-01', NULL);
  r3 := public.ponto_instrumento_do_colaborador(v_t, v_adm, d);

  IF r0->>'origem' <> 'nenhum' THEN
    r.situacao := 'falhou'; r.obtido := 'Sem instrumento devia vir nenhum e veio ' || r0::text;
  ELSIF r1->>'origem' <> 'cct_preponderante' OR (r1->>'instrumento_id')::uuid <> v_cct THEN
    r.situacao := 'falhou'; r.obtido := 'Com CCT da empresa devia vir cct_preponderante e veio ' || r1::text;
  ELSIF r2->>'origem' <> 'vinculo_colaborador' OR (r2->>'instrumento_id')::uuid <> v_dif
        OR NOT COALESCE((r2->>'alerta_sumula_374')::boolean, false) THEN
    r.situacao := 'falhou'; r.obtido := 'Com vínculo à diferenciada devia vir vinculo_colaborador com alerta 374 e veio ' || r2::text;
  ELSIF r3->>'origem' <> 'act_empresa' OR (r3->>'instrumento_id')::uuid <> v_act THEN
    r.situacao := 'falhou'; r.obtido := 'Com ACT da empresa devia prevalecer o ACT (CLT 620) e veio ' || r3::text;
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Precedência correta: nenhum, CCT preponderante, vínculo (com alerta Súm. 374), ACT da empresa.';
  END IF;
  r.detalhe := jsonb_build_object('r0', r0, 'r1', r1, 'r2', r2, 'r3', r3);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-521 ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_521()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid; v_emp uuid; v_adm uuid; v_dif uuid; v_ok uuid; v_venc uuid;
  v_av_dif text[]; v_av_ok text[]; v_av_venc text[];
  v_sobrepos_recusada boolean := false;
  v_sequencial_ok boolean := false;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();
  v_emp := public.qa_nova_empresa('[QA-BHF1] Empresa Vinculo', '11222333052149');
  v_adm := public.qa_bhf1_admissao('[QA-BHF1] Colab Vinculo', 5211, v_emp);
  v_dif := public.qa_bhf1_instrumento('cct', '[QA-BHF1] Dif nao representada', NULL, 'diferenciada', false);
  v_ok  := public.qa_bhf1_instrumento('cct', '[QA-BHF1] Dif representada', NULL, 'diferenciada', true);
  v_venc := public.qa_bhf1_instrumento('cct', '[QA-BHF1] CCT vencida', v_emp, 'preponderante', true, DATE '2024-01-01', DATE '2024-12-31');

  r.passo_ordem := 1;
  r.passo_acao := 'Avisos ao vincular: diferenciada sem representação, diferenciada representada, instrumento vencido';
  r.esperado := 'SUMULA_374 só na não representada; INSTRUMENTO_FORA_VIGENCIA na vencida';
  v_av_dif := ARRAY(SELECT codigo FROM public.ponto_instrumento_avisos_vinculo(v_t, v_dif, v_adm));
  v_av_ok := ARRAY(SELECT codigo FROM public.ponto_instrumento_avisos_vinculo(v_t, v_ok, v_adm));
  v_av_venc := ARRAY(SELECT codigo FROM public.ponto_instrumento_avisos_vinculo(v_t, v_venc, v_adm));

  r.passo_ordem := 2;
  r.passo_acao := 'Vincular o colaborador e tentar um segundo vínculo no mesmo período; depois um vínculo sequencial';
  r.esperado := 'Sobreposição recusada; sequencial aceito';
  INSERT INTO public.ponto_instrumento_colaborador (tenant_id, admissao_id, instrumento_id, data_inicio, data_fim)
  VALUES (v_t, v_adm, v_dif, DATE '2026-01-01', DATE '2026-06-30');
  BEGIN
    INSERT INTO public.ponto_instrumento_colaborador (tenant_id, admissao_id, instrumento_id, data_inicio)
    VALUES (v_t, v_adm, v_ok, DATE '2026-03-01');
  EXCEPTION WHEN check_violation THEN v_sobrepos_recusada := true;
  END;
  BEGIN
    INSERT INTO public.ponto_instrumento_colaborador (tenant_id, admissao_id, instrumento_id, data_inicio)
    VALUES (v_t, v_adm, v_ok, DATE '2026-07-01');
    v_sequencial_ok := true;
  EXCEPTION WHEN OTHERS THEN v_sequencial_ok := false;
  END;

  IF NOT ('SUMULA_374' = ANY (v_av_dif)) THEN
    r.situacao := 'falhou'; r.obtido := 'Diferenciada sem representação não avisou a Súmula 374: ' || array_to_string(v_av_dif, ',');
  ELSIF 'SUMULA_374' = ANY (v_av_ok) THEN
    r.situacao := 'falhou'; r.obtido := 'Diferenciada representada avisou a Súmula 374 indevidamente';
  ELSIF NOT ('INSTRUMENTO_FORA_VIGENCIA' = ANY (v_av_venc)) THEN
    r.situacao := 'falhou'; r.obtido := 'Instrumento vencido não avisou: ' || array_to_string(v_av_venc, ',');
  ELSIF NOT v_sobrepos_recusada THEN
    r.situacao := 'falhou'; r.obtido := 'Dois vínculos no mesmo período foram aceitos';
  ELSIF NOT v_sequencial_ok THEN
    r.situacao := 'falhou'; r.obtido := 'Vínculo sequencial (sem sobreposição) foi recusado';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Aviso da Súmula 374 só quando não representada; vencido avisado; sobreposição recusada; sequencial aceito.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-522 ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_522()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid; v_emp uuid;
  v_anual jsonb; v_sem jsonb;
  a1 text[]; a2 text[]; a3 text[]; a4 text[];
  v_forte text;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();
  UPDATE public.ponto_acordos SET ativo = false WHERE tenant_id = v_t;
  v_emp := public.qa_nova_empresa('[QA-BHF1] Empresa Avisos', '11222333052220');

  v_anual := jsonb_build_object('tipo', 'individual', 'empresa_id', v_emp, 'modalidade', 'anual',
    'prazo_compensacao_dias', 365, 'negativo_fim_ciclo', 'descontar',
    'negativo_rescisao_sem_justa_causa', 'descontar', 'falta_injustificada_destino', 'banco',
    'permite_saldo_negativo', true);
  v_sem := jsonb_build_object('tipo', 'individual', 'empresa_id', v_emp, 'modalidade', 'semestral',
    'prazo_compensacao_dias', 180, 'permite_saldo_negativo', true, 'limite_saldo_negativo_min', 600);

  r.passo_ordem := 1;
  r.passo_acao := 'Avisos sem CCT/ACT vigente: banco anual com desconto do negativo e desconto na dispensa sem justa causa; banco semestral sem acordo';
  r.esperado := 'ANUAL_SEM_COLETIVO, NEGATIVO_FIM_CICLO_SEM_COLETIVO, RESCISAO_SEM_JUSTA_CAUSA_DESCONTO (forte), FALTA_NO_BANCO, NEGATIVO_SEM_LIMITE; SEMESTRAL_SEM_ACORDO';
  a1 := ARRAY(SELECT codigo FROM public.ponto_banco_config_avisos_previa(v_t, v_anual));
  a2 := ARRAY(SELECT codigo FROM public.ponto_banco_config_avisos_previa(v_t, v_sem));
  v_forte := (SELECT nivel FROM public.ponto_banco_config_avisos_previa(v_t, v_anual)
               WHERE codigo = 'RESCISAO_SEM_JUSTA_CAUSA_DESCONTO' LIMIT 1);

  r.passo_ordem := 2;
  r.passo_acao := 'Cadastrar uma CCT vigente para a empresa e reavaliar';
  r.esperado := 'Somem os avisos que dependem de CCT/ACT; o aviso forte da dispensa sem justa causa continua';
  PERFORM public.qa_bhf1_instrumento('cct', '[QA-BHF1] CCT vigente', v_emp);
  a3 := ARRAY(SELECT codigo FROM public.ponto_banco_config_avisos_previa(v_t, v_anual));
  a4 := ARRAY(SELECT codigo FROM public.ponto_banco_config_avisos_previa(v_t, v_sem));

  IF NOT (a1 @> ARRAY['ANUAL_SEM_COLETIVO','NEGATIVO_FIM_CICLO_SEM_COLETIVO','RESCISAO_SEM_JUSTA_CAUSA_DESCONTO','FALTA_NO_BANCO','NEGATIVO_SEM_LIMITE']) THEN
    r.situacao := 'falhou'; r.obtido := 'Sem CCT faltou aviso. Veio: ' || array_to_string(a1, ',');
  ELSIF v_forte IS DISTINCT FROM 'forte' THEN
    r.situacao := 'falhou'; r.obtido := 'Desconto na dispensa sem justa causa devia ser aviso forte e veio ' || COALESCE(v_forte, 'nulo');
  ELSIF NOT ('SEMESTRAL_SEM_ACORDO' = ANY (a2)) OR 'NEGATIVO_SEM_LIMITE' = ANY (a2) THEN
    r.situacao := 'falhou'; r.obtido := 'Semestral: esperado SEMESTRAL_SEM_ACORDO e sem NEGATIVO_SEM_LIMITE (há limite). Veio: ' || array_to_string(a2, ',');
  ELSIF a3 && ARRAY['ANUAL_SEM_COLETIVO','NEGATIVO_FIM_CICLO_SEM_COLETIVO'] OR 'SEMESTRAL_SEM_ACORDO' = ANY (a4) THEN
    r.situacao := 'falhou'; r.obtido := 'Com CCT vigente os avisos deviam sumir. Veio: ' || array_to_string(a3, ',') || ' | ' || array_to_string(a4, ',');
  ELSIF NOT ('RESCISAO_SEM_JUSTA_CAUSA_DESCONTO' = ANY (a3)) THEN
    r.situacao := 'falhou'; r.obtido := 'O aviso forte da dispensa sem justa causa não pode depender de CCT. Veio: ' || array_to_string(a3, ',');
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Avisos corretos sem CCT; somem com CCT vigente; o aviso forte da rescisão permanece.';
  END IF;
  r.detalhe := jsonb_build_object('sem_cct_anual', a1, 'sem_cct_semestral', a2, 'com_cct_anual', a3, 'com_cct_semestral', a4);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-523 ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_523()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid; v_id uuid := gen_random_uuid();
  v_pos_bloq boolean := false; v_teto_bloq boolean := false;
  v_ciclo_bloq boolean := false; v_ciclo_ok boolean := false;
  v_cols_proibidas text; v_row jsonb; v_nat text;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();

  r.passo_ordem := 1;
  r.passo_acao := 'Gravar config com positivo zerado no vencimento, teto de crédito 121 min e semestral com fechamento só em dezembro';
  r.esperado := 'As três gravações recusadas; semestral com junho e dezembro aceito';
  BEGIN
    INSERT INTO public.ponto_banco_horas_config (tenant_id, tipo, forma_pagamento_vencer, ativo)
    VALUES (v_t, 'individual', 'zerar', false);
  EXCEPTION WHEN check_violation THEN v_pos_bloq := true;
  END;
  BEGIN
    INSERT INTO public.ponto_banco_horas_config (tenant_id, tipo, teto_credito_diario_min, ativo)
    VALUES (v_t, 'individual', 121, false);
  EXCEPTION WHEN check_violation THEN v_teto_bloq := true;
  END;
  BEGIN
    INSERT INTO public.ponto_banco_horas_config (tenant_id, tipo, modalidade, meses_fechamento, ativo)
    VALUES (v_t, 'individual', 'semestral', ARRAY[12], false);
  EXCEPTION WHEN check_violation THEN v_ciclo_bloq := true;
  END;
  BEGIN
    INSERT INTO public.ponto_banco_horas_config (tenant_id, tipo, modalidade, meses_fechamento, ativo)
    VALUES (v_t, 'individual', 'semestral', ARRAY[6,12], false);
    v_ciclo_ok := true;
  EXCEPTION WHEN OTHERS THEN v_ciclo_ok := false;
  END;

  r.passo_ordem := 2;
  r.passo_acao := 'Gravar config mínima e conferir os padrões; procurar opção de debitar atestado/ausência legal; conferir natureza do débito';
  r.esperado := 'Padrões = hoje (mensal, fixo, 12 meses, teto 120, fatores 1, falta na folha, atraso no banco, negativo zerado, teto de rescisão ligado, extrato ligado); nenhuma coluna de atestado/ausência legal; natureza_debito aceita só ausencia_empregado/dispensa_empresa';
  INSERT INTO public.ponto_banco_horas_config (id, tenant_id, tipo, ativo) VALUES (v_id, v_t, 'individual', false);
  v_row := (SELECT to_jsonb(c) FROM public.ponto_banco_horas_config c WHERE c.id = v_id);
  v_cols_proibidas := (SELECT string_agg(column_name, ',') FROM information_schema.columns
                        WHERE table_schema = 'public' AND table_name = 'ponto_banco_horas_config'
                          AND column_name ~ '(atestad|ausencia_legal|473|licenca)');
  v_nat := (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'ponto_bh_mov_natureza_debito_chk' LIMIT 1);

  IF NOT v_pos_bloq THEN
    r.situacao := 'falhou'; r.obtido := 'Aceitou zerar o saldo positivo no vencimento (devia pagar HE)';
  ELSIF NOT v_teto_bloq THEN
    r.situacao := 'falhou'; r.obtido := 'Aceitou teto de crédito diário acima de 120 min';
  ELSIF NOT v_ciclo_bloq OR NOT v_ciclo_ok THEN
    r.situacao := 'falhou'; r.obtido := format('Coerência do ciclo: dezembro só recusado=%s, junho+dezembro aceito=%s', v_ciclo_bloq, v_ciclo_ok);
  ELSIF v_row->>'modalidade' <> 'mensal' OR v_row->>'tipo_ciclo' <> 'fixo'
        OR jsonb_array_length(v_row->'meses_fechamento') <> 12
        OR (v_row->>'teto_credito_diario_min')::int <> 120
        OR (v_row->>'fator_credito_util')::numeric <> 1 OR (v_row->>'fator_credito_feriado')::numeric <> 1
        OR v_row->>'falta_injustificada_destino' <> 'folha' OR v_row->>'atraso_destino' <> 'banco'
        OR v_row->>'saida_antecipada_destino' <> 'banco' OR v_row->>'negativo_fim_ciclo' <> 'zerar'
        OR v_row->>'negativo_rescisao_sem_justa_causa' <> 'zerar'
        OR NOT (v_row->>'teto_desconto_rescisao_uma_remuneracao')::boolean
        OR NOT (v_row->>'extrato_mensal')::boolean
        OR v_row->>'limite_saldo_acao' <> 'alertar' THEN
    r.situacao := 'falhou'; r.obtido := 'Padrões diferentes do comportamento de hoje: ' || v_row::text;
  ELSIF v_cols_proibidas IS NOT NULL THEN
    r.situacao := 'falhou'; r.obtido := 'Existe configuração que permitiria debitar ausência legal/atestado: ' || v_cols_proibidas;
  ELSIF v_nat IS NULL OR position('dispensa_empresa' IN v_nat) = 0 THEN
    r.situacao := 'falhou'; r.obtido := 'Movimentações sem a natureza do débito (ausencia_empregado x dispensa_empresa)';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Bloqueios legais ativos; padrões iguais aos de hoje; sem opção de debitar ausência legal; natureza do débito prevista.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-524 ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_524()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid; v_cpf text := public.qa_cpf(5241);
  v_a uuid := gen_random_uuid(); v_b uuid := gen_random_uuid();
  v_d uuid := gen_random_uuid(); v_e uuid := gen_random_uuid();
  v_inst uuid;
  g1 uuid; g2 uuid; g3 uuid; g4 uuid; g5 uuid;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();
  UPDATE public.ponto_banco_horas_config SET ativo = false WHERE tenant_id = v_t;

  r.passo_ordem := 1;
  r.passo_acao := 'Regra A (banco, desde 2025) e regra B (sem banco, desde 2026) no tenant';
  r.esperado := 'Em 06/2025 vale A; em 06/2026 não há regime (antes, B contava como banco)';
  INSERT INTO public.ponto_banco_horas_config (id, tenant_id, tipo, data_inicio, ativo)
  VALUES (v_a, v_t, 'individual', DATE '2025-01-01', true);
  INSERT INTO public.ponto_banco_horas_config (id, tenant_id, tipo, data_inicio, ativo)
  VALUES (v_b, v_t, 'sem_banco', DATE '2026-01-01', true);
  g1 := (public.ponto_banco_regime_vigente(v_t, v_cpf, NULL, DATE '2025-06-01')).id;
  g2 := (public.ponto_banco_regime_vigente(v_t, v_cpf, NULL, DATE '2026-06-01')).id;

  r.passo_ordem := 2;
  r.passo_acao := 'Encerrar A em 31/03/2025 (data_fim)';
  r.esperado := 'Em 06/2025 não há regime';
  UPDATE public.ponto_banco_horas_config SET data_fim = DATE '2025-03-31' WHERE id = v_a;
  g3 := (public.ponto_banco_regime_vigente(v_t, v_cpf, NULL, DATE '2025-06-01')).id;

  r.passo_ordem := 3;
  r.passo_acao := 'Regra D presa a instrumento (desde 03/2026) e regra E comum (desde 04/2026)';
  r.esperado := 'D é ignorada nesta fatia; em 06/2026 vale E';
  v_inst := public.qa_bhf1_instrumento('cct', '[QA-BHF1] CCT regra', NULL);
  INSERT INTO public.ponto_banco_horas_config (id, tenant_id, tipo, data_inicio, instrumento_id, ativo)
  VALUES (v_d, v_t, 'individual', DATE '2026-03-01', v_inst, true);
  g4 := (public.ponto_banco_regime_vigente(v_t, v_cpf, NULL, DATE '2026-06-01')).id;
  INSERT INTO public.ponto_banco_horas_config (id, tenant_id, tipo, data_inicio, ativo)
  VALUES (v_e, v_t, 'individual', DATE '2026-04-01', true);
  g5 := (public.ponto_banco_regime_vigente(v_t, v_cpf, NULL, DATE '2026-06-01')).id;

  IF g1 IS DISTINCT FROM v_a THEN
    r.situacao := 'falhou'; r.obtido := 'Em 06/2025 devia valer a regra A';
  ELSIF g2 IS NOT NULL THEN
    r.situacao := 'falhou'; r.obtido := 'ACHADO: a regra sem_banco ainda conta como regime de banco (id ' || g2 || ')';
  ELSIF g3 IS NOT NULL THEN
    r.situacao := 'falhou'; r.obtido := 'Regra encerrada (data_fim) ainda vale depois do fim';
  ELSIF g4 IS NOT NULL THEN
    r.situacao := 'falhou'; r.obtido := 'Regra presa a instrumento entrou no cálculo antes da Fatia 2';
  ELSIF g5 IS DISTINCT FROM v_e THEN
    r.situacao := 'falhou'; r.obtido := 'Em 06/2026 devia valer a regra E';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'sem_banco = sem regime; data_fim respeitada; regra por instrumento ignorada; demais regras como antes.';
  END IF;
  r.detalhe := jsonb_build_object('g1', g1, 'g2', g2, 'g3', g3, 'g4', g4, 'g5', g5);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-525 ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_525()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid; v_emp uuid; v_apr uuid; v_men uuid; v_ins uuid;
  a_apr text[]; a_men text[]; a_ins text[]; a_cfg text[];
  v_nivel_apr text; v_bloq_apr boolean; v_bloq_ins boolean;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();
  UPDATE public.ponto_acordos SET ativo = false WHERE tenant_id = v_t;
  v_emp := public.qa_nova_empresa('[QA-BHF1] Empresa Restricoes', '11222333052300');
  v_apr := public.qa_bhf1_admissao('[QA-BHF1] Aprendiz', 5251, v_emp);
  v_men := public.qa_bhf1_admissao('[QA-BHF1] Menor', 5252, v_emp);
  v_ins := public.qa_bhf1_admissao('[QA-BHF1] Insalubre', 5253, v_emp);
  UPDATE public.admissoes SET contrato_aprendiz = true, data_nascimento = DATE '2006-01-01' WHERE id = v_apr;
  UPDATE public.admissoes SET data_nascimento = (CURRENT_DATE - INTERVAL '17 years')::date WHERE id = v_men;
  UPDATE public.admissoes SET funcao_insalubre = true, data_nascimento = DATE '1990-01-01' WHERE id = v_ins;

  r.passo_ordem := 1;
  r.passo_acao := 'Avisos de banco para aprendiz, menor e insalubre (sem CCT/ACT)';
  r.esperado := 'APRENDIZ_SEM_BANCO (bloqueio), MENOR_SEM_COLETIVO, INSALUBRE_SEM_LICENCA; aprendiz sinalizado para o cálculo; config da empresa avisa APRENDIZES_NO_ESCOPO';
  a_apr := ARRAY(SELECT codigo FROM public.ponto_banco_avisos_colaborador(v_t, v_apr));
  a_men := ARRAY(SELECT codigo FROM public.ponto_banco_avisos_colaborador(v_t, v_men));
  a_ins := ARRAY(SELECT codigo FROM public.ponto_banco_avisos_colaborador(v_t, v_ins));
  v_nivel_apr := (SELECT nivel FROM public.ponto_banco_avisos_colaborador(v_t, v_apr) WHERE codigo = 'APRENDIZ_SEM_BANCO' LIMIT 1);
  v_bloq_apr := public.ponto_banco_colaborador_bloqueado(v_t, public.qa_cpf(5251));
  v_bloq_ins := public.ponto_banco_colaborador_bloqueado(v_t, public.qa_cpf(5253));
  a_cfg := ARRAY(SELECT codigo FROM public.ponto_banco_config_avisos_previa(v_t,
             jsonb_build_object('tipo', 'individual', 'empresa_id', v_emp)));

  IF NOT ('APRENDIZ_SEM_BANCO' = ANY (a_apr)) OR v_nivel_apr IS DISTINCT FROM 'bloqueio' THEN
    r.situacao := 'falhou'; r.obtido := 'Aprendiz sem o bloqueio do art. 432: ' || array_to_string(a_apr, ',');
  ELSIF NOT ('MENOR_SEM_COLETIVO' = ANY (a_men)) THEN
    r.situacao := 'falhou'; r.obtido := 'Menor sem aviso do art. 413: ' || array_to_string(a_men, ',');
  ELSIF NOT ('INSALUBRE_SEM_LICENCA' = ANY (a_ins)) THEN
    r.situacao := 'falhou'; r.obtido := 'Insalubre sem aviso do art. 60: ' || array_to_string(a_ins, ',');
  ELSIF NOT v_bloq_apr OR v_bloq_ins THEN
    r.situacao := 'falhou'; r.obtido := format('Sinal para o cálculo: aprendiz=%s (esperado true), insalubre=%s (esperado false)', v_bloq_apr, v_bloq_ins);
  ELSIF NOT (a_cfg @> ARRAY['APRENDIZES_NO_ESCOPO','MENORES_SEM_COLETIVO','INSALUBRES_SEM_COLETIVO']) THEN
    r.situacao := 'falhou'; r.obtido := 'A configuração da empresa não avisou as restrições: ' || array_to_string(a_cfg, ',');
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Aprendiz bloqueado (art. 432), menor (art. 413) e insalubre (art. 60) avisados, no colaborador e na configuração.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-526 ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_526()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid; v_id uuid := gen_random_uuid();
  v_lim text; v_av text[]; v_nova text;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();

  r.passo_ordem := 1;
  r.passo_acao := 'Inferir a modalidade pelos limites do prazo (31/32, 183/184, sem prazo) e avaliar uma regra antiga de 180 dias com a modalidade inferida';
  r.esperado := 'mensal, semestral, semestral, anual, mensal; sem PRAZO_ACIMA_MODALIDADE; regra nova nasce mensal';
  v_lim := public.ponto_banco_modalidade_do_prazo(31) || ',' || public.ponto_banco_modalidade_do_prazo(32) || ','
        || public.ponto_banco_modalidade_do_prazo(183) || ',' || public.ponto_banco_modalidade_do_prazo(184) || ','
        || public.ponto_banco_modalidade_do_prazo(NULL);
  v_av := ARRAY(SELECT codigo FROM public.ponto_banco_config_avisos_previa(v_t,
            jsonb_build_object('tipo', 'individual', 'prazo_compensacao_dias', 180,
                               'modalidade', public.ponto_banco_modalidade_do_prazo(180))));
  INSERT INTO public.ponto_banco_horas_config (id, tenant_id, tipo, prazo_compensacao_dias, ativo)
  VALUES (v_id, v_t, 'individual', 180, false);
  v_nova := (SELECT modalidade FROM public.ponto_banco_horas_config WHERE id = v_id);

  IF v_lim <> 'mensal,semestral,semestral,anual,mensal' THEN
    r.situacao := 'falhou'; r.obtido := 'Limites da inferência errados: ' || v_lim;
  ELSIF 'PRAZO_ACIMA_MODALIDADE' = ANY (v_av) THEN
    r.situacao := 'falhou'; r.obtido := 'Regra antiga de 180 dias com modalidade inferida ainda gera aviso falso';
  ELSIF v_nova IS DISTINCT FROM 'mensal' THEN
    r.situacao := 'falhou'; r.obtido := 'Regra nova devia nascer mensal e nasceu ' || COALESCE(v_nova, 'nula');
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Inferência correta nos limites; sem aviso falso; regra nova nasce mensal.';
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
    RAISE NOTICE 'Motor de QA ausente; casos PONTO-520..526 não documentados.';
    RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'jornada-rotina/ponto' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo jornada-rotina/ponto ausente; casos PONTO-520..526 não documentados.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PONTO-520',
   'Convenção do colaborador: ACT da empresa > instrumento vinculado > CCT preponderante',
   'feliz', 'alta', 'aprovado', 'api',
   'CLT arts. 511 §§2º e 3º, 570, 581 §2º e 620; Súmula 374 do TST',
   'Com várias convenções na mesma conta, cada colaborador precisa de UMA convenção resolvida por data. O ACT prevalece sobre a CCT; quem tem vínculo próprio (ex.: categoria diferenciada) segue o vínculo; os demais seguem a CCT da atividade principal da empresa.',
   'Cercado de QA; empresa e admissão de teste; instrumentos fictícios.',
   '[{"ordem":1,"acao":"Resolver sem instrumento","resultado_esperado":"origem nenhum"},
     {"ordem":2,"acao":"Cadastrar CCT preponderante da empresa","resultado_esperado":"origem cct_preponderante"},
     {"ordem":3,"acao":"Vincular o colaborador a uma CCT diferenciada sem representação","resultado_esperado":"origem vinculo_colaborador, alerta_sumula_374 = true"},
     {"ordem":4,"acao":"Cadastrar ACT da empresa","resultado_esperado":"origem act_empresa"}]'::jsonb,
   'ponto_instrumento_do_colaborador devolve a precedência correta em cada passo.',
   'Banco de horas configurável — Fatia 1 (30/10/2026). O cálculo passa a usar na Fatia 2.'),
  (v_mod, 'PONTO-521',
   'Vínculo do colaborador à convenção: aviso da Súmula 374 e um vínculo por período',
   'negativo', 'alta', 'aprovado', 'api',
   'Súmula 374 do TST; CLT art. 511 §3º; art. 614 §3º',
   'Vincular a uma CCT de categoria diferenciada em que a empresa não foi representada não obriga a empresa: o sistema avisa (não bloqueia). Dois vínculos no mesmo período deixariam a convenção ambígua: recusado.',
   'Cercado de QA; instrumentos diferenciada (com e sem representação) e um vencido.',
   '[{"ordem":1,"acao":"Avisos de vínculo para os três instrumentos","resultado_esperado":"SUMULA_374 só no não representado; INSTRUMENTO_FORA_VIGENCIA no vencido"},
     {"ordem":2,"acao":"Segundo vínculo sobreposto; depois sequencial","resultado_esperado":"Sobreposto recusado; sequencial aceito"}]'::jsonb,
   'Aviso correto e vigência sem sobreposição.',
   'ponto_instrumento_avisos_vinculo + gatilho trg_ponto_instr_colab_guarda.'),
  (v_mod, 'PONTO-522',
   'Avisos da configuração do banco sem CCT/ACT vigente, e que somem quando a convenção é cadastrada',
   'negativo', 'critica', 'aprovado', 'api',
   'CLT art. 59 §§2º e 5º; art. 611-A II; art. 462; art. 477 §5º; art. 2º; Lei 605/49 art. 6º',
   'Regra da fundadora (30/10): o que depende de CCT/ACT não bloqueia, avisa até a convenção ser cadastrada. Descontar o negativo na dispensa sem justa causa é aviso FORTE (risco do empregador) e não some com CCT.',
   'Cercado de QA; acordos do cercado desativados; empresa de teste.',
   '[{"ordem":1,"acao":"Avaliar banco anual com desconto do negativo, desconto na dispensa sem justa causa, falta no banco, negativo sem limite; e banco semestral","resultado_esperado":"ANUAL_SEM_COLETIVO, NEGATIVO_FIM_CICLO_SEM_COLETIVO, RESCISAO_SEM_JUSTA_CAUSA_DESCONTO (forte), FALTA_NO_BANCO, NEGATIVO_SEM_LIMITE; SEMESTRAL_SEM_ACORDO"},
     {"ordem":2,"acao":"Cadastrar CCT vigente e reavaliar","resultado_esperado":"Somem os avisos dependentes de CCT; o forte permanece"}]'::jsonb,
   'Avisos certos, sem bloquear a gravação.',
   'ponto_banco_config_avisos_previa (a tela chama enquanto o RH edita) e ponto_banco_config_avisos (config salva).'),
  (v_mod, 'PONTO-523',
   'Bloqueios legais da configuração do banco e padrões iguais ao comportamento atual',
   'negativo', 'critica', 'aprovado', 'api',
   'CLT art. 59 caput, §§2º e 5º; art. 473; Lei 605/49 art. 6º §1º; CLT art. 2º',
   'Só a lei proíbe em qualquer caso vira bloqueio: (a) não existe transportar/zerar saldo positivo (paga HE); (b) não existe opção de debitar ausência legal ou atestado; (c) teto de crédito diário entre 0 e 120 min. Ciclo fixo não pode passar do máximo da modalidade. Os campos novos nascem com o comportamento de hoje. A natureza do débito (ausência do empregado x dispensa pela empresa) fica prevista.',
   'Cercado de QA.',
   '[{"ordem":1,"acao":"Gravar positivo zerado, teto 121, semestral só em dezembro; semestral junho+dezembro","resultado_esperado":"Três recusas; o último aceito"},
     {"ordem":2,"acao":"Gravar config mínima e conferir padrões; procurar colunas de atestado/ausência legal; conferir natureza_debito","resultado_esperado":"Padrões de hoje; nenhuma coluna proibida; natureza_debito com ausencia_empregado/dispensa_empresa"}]'::jsonb,
   'Bloqueios ativos e padrões neutros.',
   'Gatilho trg_ponto_banco_config_valida + CHECKs ponto_bh_cfg_*. A Fatia 3 aplica no cálculo min(teto, 600 - jornada do dia), exceção 12x36 (art. 59-A); limita o crédito, nunca a batida.'),
  (v_mod, 'PONTO-524',
   'Regime de banco vigente: regra "sem banco" é sem banco e a data de fim é respeitada',
   'negativo', 'critica', 'aprovado', 'api',
   'CLT art. 59 §§2º e 5º',
   'Antes, uma configuração do tipo sem_banco ativa contava como regime de banco (o excedente ia para o banco em vez da folha). Agora a regra mais específica sem_banco significa sem regime, a data de fim encerra a regra, e a regra presa a um instrumento só entra na Fatia 2.',
   'Cercado de QA; regras de banco do cercado desativadas.',
   '[{"ordem":1,"acao":"Regra A (banco, 2025) e B (sem banco, 2026)","resultado_esperado":"06/2025 = A; 06/2026 = sem regime"},
     {"ordem":2,"acao":"Encerrar A em 31/03/2025","resultado_esperado":"06/2025 = sem regime"},
     {"ordem":3,"acao":"Regra D presa a instrumento; regra E comum mais recente","resultado_esperado":"D ignorada; 06/2026 = E"}]'::jsonb,
   'ponto_banco_regime_vigente corrigido sem mudar o resto.',
   'Única mudança de cálculo da Fatia 1. Conferir quem é afetado: configs ativas tipo sem_banco (conferência do script).'),
  (v_mod, 'PONTO-525',
   'Restrições do colaborador ao banco: aprendiz bloqueado, menor e insalubre avisados',
   'negativo', 'alta', 'aprovado', 'api',
   'CLT art. 432; art. 413 I; art. 60; art. 611-A XIII; art. 59-A',
   'Aprendiz não pode ter prorrogação nem compensação (bloqueio sinalizado ao cálculo). Menor só compensa com CCT/ACT; atividade insalubre exige licença prévia salvo CCT/ACT ou 12x36 (avisos).',
   'Cercado de QA; três admissões fictícias (aprendiz, menor, insalubre); sem CCT/ACT.',
   '[{"ordem":1,"acao":"Avisos por colaborador, sinal para o cálculo e avisos da configuração da empresa","resultado_esperado":"APRENDIZ_SEM_BANCO (bloqueio), MENOR_SEM_COLETIVO, INSALUBRE_SEM_LICENCA; bloqueado só o aprendiz; APRENDIZES_NO_ESCOPO, MENORES_SEM_COLETIVO, INSALUBRES_SEM_COLETIVO"}]'::jsonb,
   'Restrições sinalizadas no colaborador e na configuração.',
   'Fatia 1 só sinaliza: o cálculo passa a excluir aprendiz na Fatia 2 (ponto_banco_colaborador_bloqueado).'),
  (v_mod, 'PONTO-526',
   'Regras de banco que já existiam ganham a modalidade pelo prazo atual, sem aviso falso',
   'feliz', 'alta', 'aprovado', 'api',
   'CLT art. 59 §§2º, 5º e 6º',
   'Ao nascer a coluna modalidade, cada regra existente recebe mensal (prazo até 31 dias), semestral (até 183) ou anual (acima), uma única vez. Sem isso, todas nasceriam mensais e as de 180 dias mostrariam em massa o aviso "prazo acima da modalidade". Regra nova nasce mensal.',
   'Cercado de QA.',
   '[{"ordem":1,"acao":"ponto_banco_modalidade_do_prazo em 31, 32, 183, 184 e nulo; avisos de uma regra de 180 dias com a modalidade inferida; inserir regra nova","resultado_esperado":"mensal, semestral, semestral, anual, mensal; sem PRAZO_ACIMA_MODALIDADE; nova = mensal"}]'::jsonb,
   'Inferência correta e sem aviso falso.',
   'A inferência roda só quando a coluna é criada (migration e script); regras editadas depois não são tocadas.')
  ON CONFLICT (codigo) DO UPDATE SET
    modulo_id = EXCLUDED.modulo_id, titulo = EXCLUDED.titulo, objetivo = EXCLUDED.objetivo,
    passos = EXCLUDED.passos, resultado_esperado = EXCLUDED.resultado_esperado,
    base_legal = EXCLUDED.base_legal, observacoes = EXCLUDED.observacoes, status = 'aprovado';

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
      ('PONTO-520', 'qa_caso_ponto_520', true),
      ('PONTO-521', 'qa_caso_ponto_521', true),
      ('PONTO-522', 'qa_caso_ponto_522', true),
      ('PONTO-523', 'qa_caso_ponto_523', true),
      ('PONTO-524', 'qa_caso_ponto_524', true),
      ('PONTO-525', 'qa_caso_ponto_525', true),
      ('PONTO-526', 'qa_caso_ponto_526', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentação PONTO-520..526 não registrada: %', SQLERRM;
END $doc$;
