-- ============================================================================
-- QA — EC 141/2026, ENTREGA F2a (validação ao salvar, assistente de migração,
-- aditivo individual e cancelamento em lote)
--
--   PONTO-EC141-009  marco inativo: nada muda (salvar 48h em 6 dias passa, sem
--                    bloqueio; assistente invisível e recusado)
--   PONTO-EC141-010  42h ativo: escala acima de 42h valendo a partir da data é
--                    BLOQUEADA ao salvar (CF art. 7º, XIII); antes da data só
--                    avisa; 8h24 passa com aviso forte; edição só de tolerância
--                    não bloqueia
--   PONTO-EC141-011  6 dias sem instrumento coletivo a partir da data:
--                    bloqueado (CF art. 7º, XV e §2º); com CCT vigente passa
--   PONTO-EC141-012  assistente 42h com CCT: prévia, gravação com "vale a partir
--                    de" = data, dias anteriores idênticos, aditivo com EC 141
--                    art. 2º e CLT 468, reexecutar não duplica
--   PONTO-EC141-013  sem CCT/ACT: recomenda 40h; 8h24 só com confirmação
--                    (aviso forte, art. 7º); 40h direto grava 5 x 8h
--   PONTO-EC141-014  exceção por colaborador na mesma escala: escala nova a
--                    partir da data, atribuição anterior termina na véspera,
--                    dia anterior idêntico
--   PONTO-EC141-015  6x1 de 44h -> 40h: sábado sai, 5 x 8h
--   PONTO-EC141-016  cancelamento em lote da migração restaura o estado exato
--                    (escalas, blocos, atribuições, apuração); aditivos
--                    cancelados; depois da data, recusa
--   PONTO-EC141-017  auditoria e permissão: quem acionou fica gravado; sem
--                    login de usuário da conta, recusado
--   PONTO-EC141-018  cancelar o agendamento pela própria escala (F1) desfaz a
--                    migração daquele colaborador e permite refazer
--   (ajuste) PONTO-EC141-007: a escala de 44h passa a ser criada antes da
--                    ativação do marco (criar escala acima do teto com a lei em
--                    vigor agora é bloqueado ao salvar); o que se testa (a
--                    batida) não muda
--
-- As rotinas chamam as MESMAS funções da tela (ponto_ec141_migracao_previa /
-- _aplicar / _cancelar, ponto_escala_ec141_validar_salvar e o UPDATE da escala
-- pelo gatilho). Rodam no cercado, desfeitas pelo motor. Marcos alterados só
-- como exceção da conta do cercado. Variáveis só por subconsulta escalar.
-- ============================================================================

SET lock_timeout = '10s';

-- Ajudante: segunda atribuição numa escala existente (colegas na mesma escala).
CREATE OR REPLACE FUNCTION public.qa_ec141_atribuir(p_escala uuid, p_cpf text, p_inicio date)
RETURNS void LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
BEGIN
  INSERT INTO public.ponto_escala_atribuicoes
    (tenant_id, escala_id, colaborador_id, colaborador_nome, colaborador_cpf, data_inicio, ativa)
  VALUES (public.qa_sandbox_tenant_id(), p_escala, p_cpf, '[QA-EC141] Colaborador', p_cpf, p_inicio, true);
END $fn$;

-- Ajudante: CCT vigente (ou nenhuma) para o cercado.
CREATE OR REPLACE FUNCTION public.qa_ec141_coletivo(p_ter boolean)
RETURNS void LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
BEGIN
  UPDATE public.ponto_acordos SET ativo = false WHERE tenant_id = public.qa_sandbox_tenant_id();
  IF p_ter THEN
    INSERT INTO public.ponto_acordos (tenant_id, tipo, titulo, ativo, vigencia_inicio, vigencia_fim)
    VALUES (public.qa_sandbox_tenant_id(), 'cct', '[QA-EC141] CCT vigente', true, CURRENT_DATE - 30, CURRENT_DATE + 800);
  END IF;
END $fn$;

-- Ajudante: marco 42h (ou 40h) ativo para a conta do cercado na data.
CREATE OR REPLACE FUNCTION public.qa_ec141_ativar(p_codigo text, p_data date)
RETURNS void LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
BEGIN
  PERFORM public.ponto_marco_desativar('EC141_42H', '[QA] estado inicial', public.qa_sandbox_tenant_id());
  PERFORM public.ponto_marco_desativar('EC141_40H', '[QA] estado inicial', public.qa_sandbox_tenant_id());
  IF p_codigo IS NOT NULL THEN
    PERFORM public.ponto_marco_ativar(p_codigo, p_data, '[QA] ativação', public.qa_sandbox_tenant_id());
  END IF;
END $fn$;

-- Ajudante: "fotografia" do estado das escalas de teste (linhas, blocos,
-- versões e atribuições), para provar que o cancelamento restaura o exato.
CREATE OR REPLACE FUNCTION public.qa_ec141_estado()
RETURNS jsonb LANGUAGE sql SET search_path TO 'public' AS $fn$
  WITH esc AS MATERIALIZED (
    SELECT e.* FROM public.ponto_escalas e
     WHERE e.tenant_id = public.qa_sandbox_tenant_id() AND e.nome LIKE '[QA-EC141]%'
  )
  SELECT jsonb_build_object(
    'escalas', (SELECT jsonb_agg(to_jsonb(e) - 'updated_at' ORDER BY e.id) FROM esc e),
    'blocos', (SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id) FROM public.ponto_escala_periodos p WHERE p.escala_id IN (SELECT id FROM esc)),
    'versoes', (SELECT jsonb_agg(to_jsonb(v) ORDER BY v.id) FROM public.ponto_escala_param_versoes v WHERE v.escala_id IN (SELECT id FROM esc)),
    'atribuicoes', (SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id) FROM public.ponto_escala_atribuicoes a
                     WHERE a.tenant_id = public.qa_sandbox_tenant_id() AND a.colaborador_nome LIKE '[QA-EC141]%'))
$fn$;

-- Ajudante: jornada esperada do colaborador no dia (mesma função da apuração).
CREATE OR REPLACE FUNCTION public.qa_ec141_jornada(p_cpf text, p_dia date)
RETURNS integer LANGUAGE sql SET search_path TO 'public' AS $fn$
  SELECT j.jornada_min FROM public.ponto_jornada_do_dia(public.qa_sandbox_tenant_id(), p_cpf, p_cpf, p_dia) j LIMIT 1
$fn$;

-- Ajudante: linha da prévia de um colaborador.
CREATE OR REPLACE FUNCTION public.qa_ec141_linha(p_previa jsonb, p_cpf text)
RETURNS jsonb LANGUAGE sql SET search_path TO 'public' AS $fn$
  SELECT x FROM jsonb_array_elements(p_previa->'linhas') x WHERE x->>'chave' = p_cpf LIMIT 1
$fn$;

-- ── PONTO-EC141-009 ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_ec141_009()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r      public.qa_retorno;
  v_t    uuid := public.qa_sandbox_tenant_id();
  v_cpf  text := public.qa_cpf(6241);
  v_esc  uuid;
  v_ok   boolean := false;
  v_msg  text;
  v_val  jsonb;
  v_prev jsonb;
  v_apl  jsonb;
  v_jd   int;
  v_migs int;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM public.qa_ec141_ativar(NULL, NULL);
  PERFORM public.qa_ec141_coletivo(false);
  v_esc := public.qa_ec141_escala(v_cpf, 440, ARRAY['segunda','terca','quarta','quinta','sexta','sabado'], DATE '2026-01-01');

  r.passo_ordem := 1;
  r.passo_acao := 'Com os marcos EC 141 inativos, salvar a 6x1 com 8h/dia (48h) valendo daqui a 20 dias, sem instrumento coletivo';
  r.esperado := 'Salva como hoje (nenhum bloqueio novo); a conferência do salvar não se aplica';
  v_val := public.ponto_escala_ec141_validar_salvar(v_esc, jsonb_build_object('jornada_diaria_minutos', 480), CURRENT_DATE + 20);
  BEGIN
    PERFORM public.qa_ec141_salvar_escala(v_esc, 480, CURRENT_DATE + 20, NULL, NULL);
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
  END;
  v_jd := public.qa_ec141_jornada(v_cpf, CURRENT_DATE + 20 + ((1 - EXTRACT(ISODOW FROM CURRENT_DATE + 20)::int + 7) % 7));

  r.passo_ordem := 2;
  r.passo_acao := 'RH abre o assistente e tenta gravar a migração';
  r.esperado := 'Assistente invisível (visivel = false); gravação recusada (sem_marco_ativo); nenhuma migração registrada';
  v_prev := public.ponto_ec141_migracao_previa(v_t, NULL, '40', '{}'::jsonb, ARRAY[v_esc]);
  v_apl := public.ponto_ec141_migracao_aplicar(v_t, NULL, '40', '{}'::jsonb, true, ARRAY[v_esc]);
  v_migs := (SELECT count(*) FROM public.ponto_ec141_migracoes WHERE tenant_id = v_t);

  IF NOT v_ok THEN
    r.situacao := 'falhou'; r.obtido := 'Com marco inativo o salvar passou a bloquear: ' || COALESCE(v_msg, '');
  ELSIF COALESCE((v_val->>'aplica')::boolean, true) OR COALESCE((v_val->>'bloqueia')::boolean, true) THEN
    r.situacao := 'falhou'; r.obtido := 'A conferência do salvar agiu sem marco ativo: ' || COALESCE(v_val::text, 'nulo');
  ELSIF v_jd IS DISTINCT FROM 480 THEN
    r.situacao := 'falhou'; r.obtido := format('O agendamento da F1 deixou de funcionar: jornada na segunda após a data = %s', COALESCE(v_jd::text, 'nula'));
  ELSIF COALESCE((v_prev->>'visivel')::boolean, true) THEN
    r.situacao := 'falhou'; r.obtido := 'O assistente apareceu sem marco ativo: ' || left(v_prev::text, 300);
  ELSIF COALESCE(v_apl->>'erro', '') <> 'sem_marco_ativo' OR v_migs <> 0 THEN
    r.situacao := 'falhou'; r.obtido := format('Gravação sem marco ativo não foi recusada (%s; %s migração(ões))', left(v_apl::text, 200), v_migs);
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Marcos inativos: salvar e agendar seguem como antes (sem bloqueio); assistente invisível e gravação recusada.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-EC141-010 ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_ec141_010()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r       public.qa_retorno;
  v_cpf   text := public.qa_cpf(6242);
  v_cpf2  text := public.qa_cpf(6243);
  v_d     date := CURRENT_DATE + 20;
  v_esc   uuid;
  v_esc2  uuid;
  v_bloq  text;
  v_antes boolean := false;
  v_msg_a text;
  v_8h24  boolean := false;
  v_msg_b text;
  v_val   jsonb;
  v_tol   boolean := false;
  v_msg_t text;
  v_bloq2 text;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM public.qa_ec141_coletivo(false);
  PERFORM public.qa_ec141_ativar('EC141_42H', v_d);
  v_esc := public.qa_ec141_escala(v_cpf, 528, ARRAY['segunda','terca','quarta','quinta','sexta'], DATE '2026-01-01');
  v_esc2 := public.qa_ec141_escala(v_cpf2, 528, ARRAY['segunda','terca','quarta','quinta','sexta'], DATE '2026-01-01');

  r.passo_ordem := 1;
  r.passo_acao := format('42h ativo a partir de %s: salvar a escala com 9h/dia (45h) valendo a partir dessa data', to_char(v_d, 'DD/MM/YYYY'));
  r.esperado := 'Bloqueado ao salvar, com a base legal (CF art. 7º, XIII) na mensagem';
  BEGIN
    PERFORM public.qa_ec141_salvar_escala(v_esc, 540, v_d, NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    v_bloq := SQLERRM;
  END;

  r.passo_ordem := 2;
  r.passo_acao := 'Salvar a mesma mudança sem data (vale de hoje, antes do marco)';
  r.esperado := 'Aceito (antes da data a lei ainda não vale; fica só o aviso)';
  BEGIN
    PERFORM public.qa_ec141_salvar_escala(v_esc, 540, NULL, NULL, NULL);
    v_antes := true;
  EXCEPTION WHEN OTHERS THEN
    v_msg_a := SQLERRM;
  END;

  r.passo_ordem := 3;
  r.passo_acao := 'Salvar 8h24/dia (42h) valendo a partir da data, sem instrumento coletivo';
  r.esperado := 'Aceito; a conferência mostra o aviso forte de jornada acima de 8h (EC 141, art. 7º)';
  v_val := public.ponto_escala_ec141_validar_salvar(v_esc,
             jsonb_build_object('dias_config', (SELECT jsonb_object_agg(x.k, x.v || CASE WHEN COALESCE((x.v->>'trabalha')::boolean, false)
                                     THEN jsonb_build_object('saida', '17:24') ELSE '{}'::jsonb END)
                                   FROM public.ponto_escalas e CROSS JOIN LATERAL jsonb_each(e.dias_config) x(k, v) WHERE e.id = v_esc)), v_d);
  BEGIN
    PERFORM public.qa_ec141_salvar_escala(v_esc, 504, v_d, NULL, NULL);
    v_8h24 := true;
  EXCEPTION WHEN OTHERS THEN
    v_msg_b := SQLERRM;
  END;

  r.passo_ordem := 4;
  r.passo_acao := 'Lei já em vigor (data = ontem): mudar só a tolerância de uma escala de 44h ainda não migrada; depois mudar a jornada para 9h';
  r.esperado := 'Tolerância: aceita (não mexe na carga). Jornada 9h: bloqueada';
  PERFORM public.qa_ec141_ativar('EC141_42H', CURRENT_DATE - 1);
  BEGIN
    UPDATE public.ponto_escalas SET tolerancia_minutos = 3 WHERE id = v_esc2;
    v_tol := true;
  EXCEPTION WHEN OTHERS THEN
    v_msg_t := SQLERRM;
  END;
  BEGIN
    PERFORM public.qa_ec141_salvar_escala(v_esc2, 540, NULL, NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    v_bloq2 := SQLERRM;
  END;

  IF v_bloq IS NULL OR position('CF art. 7º, XIII' IN v_bloq) = 0 THEN
    r.situacao := 'falhou'; r.obtido := 'Escala de 45h a partir da data não foi bloqueada com a base legal: ' || COALESCE(v_bloq, 'aceita');
  ELSIF NOT v_antes THEN
    r.situacao := 'falhou'; r.obtido := 'Antes da data a mudança devia ser aceita: ' || COALESCE(v_msg_a, '');
  ELSIF NOT v_8h24 THEN
    r.situacao := 'falhou'; r.obtido := '8h24 (42h) devia ser aceita: ' || COALESCE(v_msg_b, '');
  ELSIF COALESCE((v_val->>'bloqueia')::boolean, true)
        OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_val->'avisos') a WHERE a->>'nivel' = 'forte' AND position('art. 7º' IN a->>'mensagem') > 0) THEN
    r.situacao := 'falhou'; r.obtido := '8h24 sem coletivo devia trazer aviso forte sem bloquear: ' || COALESCE(v_val::text, 'nulo');
  ELSIF NOT v_tol THEN
    r.situacao := 'falhou'; r.obtido := 'Mudar só a tolerância foi bloqueado: ' || COALESCE(v_msg_t, '');
  ELSIF v_bloq2 IS NULL THEN
    r.situacao := 'falhou'; r.obtido := 'Com a lei em vigor, aumentar a jornada para 45h não foi bloqueado';
  ELSE
    r.situacao := 'passou';
    r.obtido := '45h a partir da data: bloqueada (CF art. 7º, XIII). Antes da data: aceita. 8h24: aceita com aviso forte. Só tolerância: aceita. 45h com a lei em vigor: bloqueada.';
  END IF;
  r.detalhe := jsonb_build_object('bloqueio', v_bloq, 'conferencia_8h24', v_val);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-EC141-011 ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_ec141_011()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r      public.qa_retorno;
  v_cpf  text := public.qa_cpf(6244);
  v_d    date := CURRENT_DATE + 20;
  v_esc  uuid;
  v_sem  text;
  v_com  boolean := false;
  v_msg  text;
  v_bat  int;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM public.qa_ec141_coletivo(false);
  PERFORM public.qa_ec141_ativar('EC141_42H', v_d);
  -- 6x1 de 7h (42h): dentro do teto semanal, mas com 1 repouso só.
  v_esc := public.qa_ec141_escala(v_cpf, 420, ARRAY['segunda','terca','quarta','quinta','sexta','sabado'], DATE '2026-01-01');

  r.passo_ordem := 1;
  r.passo_acao := 'Salvar a 6x1 com 6h50/dia valendo a partir da data, sem instrumento coletivo';
  r.esperado := 'Bloqueado ao salvar: 2 repousos semanais (CF art. 7º, XV e §2º)';
  BEGIN
    PERFORM public.qa_ec141_salvar_escala(v_esc, 410, v_d, NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    v_sem := SQLERRM;
  END;

  r.passo_ordem := 2;
  r.passo_acao := 'Cadastrar CCT vigente e salvar de novo';
  r.esperado := 'Aceito (6 dias só com instrumento coletivo)';
  PERFORM public.qa_ec141_coletivo(true);
  BEGIN
    PERFORM public.qa_ec141_salvar_escala(v_esc, 410, v_d, NULL, NULL);
    v_com := true;
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
  END;

  r.passo_ordem := 3;
  r.passo_acao := 'Bater o ponto ontem nessa escala';
  r.esperado := 'A batida é gravada (bloqueio só ao salvar a escala, nunca na batida)';
  PERFORM public.qa_ponto_marca(v_cpf, '[QA-EC141] Colaborador', CURRENT_DATE - 1, TIME '08:00', 'entrada');
  PERFORM public.qa_ponto_marca(v_cpf, '[QA-EC141] Colaborador', CURRENT_DATE - 1, TIME '15:00', 'saida');
  v_bat := (SELECT count(*) FROM public.ponto_marcacoes m
             WHERE m.tenant_id = public.qa_sandbox_tenant_id() AND m.colaborador_cpf = v_cpf AND m.data_marcacao = CURRENT_DATE - 1);

  IF v_sem IS NULL OR position('CF art. 7º, XV' IN v_sem) = 0 THEN
    r.situacao := 'falhou'; r.obtido := '6 dias sem coletivo a partir da data não foi bloqueado com a base legal: ' || COALESCE(v_sem, 'aceito');
  ELSIF NOT v_com THEN
    r.situacao := 'falhou'; r.obtido := 'Com CCT vigente a 6x1 devia ser aceita: ' || COALESCE(v_msg, '');
  ELSIF v_bat < 1 THEN
    r.situacao := 'falhou'; r.obtido := 'A batida não foi gravada';
  ELSE
    r.situacao := 'passou';
    r.obtido := '6x1 sem coletivo a partir da data: bloqueada (CF art. 7º, XV). Com CCT vigente: aceita. Batida gravada normalmente.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-EC141-012 ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_ec141_012()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r       public.qa_retorno;
  v_t     uuid := public.qa_sandbox_tenant_id();
  v_cpf   text := public.qa_cpf(6245);
  v_d     date;
  v_esc   uuid;
  v_prev  jsonb;
  v_lin   jsonb;
  v_apl   jsonb;
  v_apl2  jsonb;
  v_f0    jsonb;
  v_f1    jsonb;
  v_jd    int;
  v_jd_1  int;
  v_ver   jsonb;
  v_txt   text;
  v_itens int;
  v_adit  int;
  v_mig   jsonb;
  g       date;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM set_config('request.jwt.claims', '', true);
  -- D = terça-feira daqui a pelo menos duas semanas.
  v_d := CURRENT_DATE + 14 + ((2 - EXTRACT(ISODOW FROM CURRENT_DATE + 14)::int + 7) % 7);
  PERFORM public.qa_ec141_coletivo(true);
  PERFORM public.qa_ec141_ativar('EC141_42H', v_d);
  v_esc := public.qa_ec141_escala(v_cpf, 528, ARRAY['segunda','terca','quarta','quinta','sexta'], DATE '2026-01-01');
  FOR g IN SELECT x::date FROM generate_series(v_d - 6, v_d + 2, INTERVAL '1 day') x LOOP
    IF EXTRACT(ISODOW FROM g) BETWEEN 1 AND 5 THEN
      PERFORM public.qa_ponto_dia_min(v_cpf, '[QA-EC141] Colaborador', g, 528 + 60);
    END IF;
  END LOOP;
  v_f0 := public.qa_ec141_foto(v_cpf, v_esc, v_d - 6, v_d - 1, ARRAY[]::text[], ARRAY[]::text[]);

  r.passo_ordem := 1;
  r.passo_acao := 'Assistente, destino 42h, com CCT vigente: prévia do colaborador';
  r.esperado := 'Escala atual 8h48 (44h) -> proposta 8h24 (42h); tem CCT; recomendação 42h; sem confirmação extra; modo "escala"';
  v_prev := public.ponto_ec141_migracao_previa(v_t, NULL, '42', '{}'::jsonb, ARRAY[v_esc]);
  v_lin := public.qa_ec141_linha(v_prev, v_cpf);

  r.passo_ordem := 2;
  r.passo_acao := 'Confirmar a migração e reexecutar';
  r.esperado := 'Escala agendada para D (marco EC141_42H); dias < D idênticos; D com 504; aditivo com EC 141 art. 2º e CLT 468; reexecutar não duplica';
  v_apl := public.ponto_ec141_migracao_aplicar(v_t, NULL, '42', '{}'::jsonb, false, ARRAY[v_esc]);
  v_f1 := public.qa_ec141_foto(v_cpf, v_esc, v_d - 6, v_d - 1, ARRAY[]::text[], ARRAY[]::text[]);
  v_jd := public.qa_ec141_jornada(v_cpf, v_d);
  v_jd_1 := public.qa_ec141_jornada(v_cpf, v_d - 1);
  v_ver := (SELECT jsonb_build_object('fim', pv.vigencia_fim, 'marco', pv.marco_codigo) FROM public.ponto_escala_param_versoes pv
             WHERE pv.escala_id = v_esc ORDER BY pv.vigencia_fim DESC LIMIT 1);
  v_txt := (SELECT a.texto FROM public.ponto_ec141_aditivos a WHERE a.migracao_id = (v_apl->>'migracao_id')::uuid LIMIT 1);
  v_mig := (SELECT to_jsonb(m) FROM public.ponto_ec141_migracoes m WHERE m.id = (v_apl->>'migracao_id')::uuid);
  v_apl2 := public.ponto_ec141_migracao_aplicar(v_t, NULL, '42', '{}'::jsonb, false, ARRAY[v_esc]);
  v_itens := (SELECT count(*) FROM public.ponto_ec141_migracao_itens WHERE tenant_id = v_t AND colaborador_chave = v_cpf);
  v_adit := (SELECT count(*) FROM public.ponto_ec141_aditivos WHERE tenant_id = v_t AND colaborador_cpf = v_cpf);

  IF v_lin IS NULL OR v_lin->>'status' <> 'migrar' OR (v_lin->>'carga_antes_min')::int <> 2640
     OR (v_lin->>'carga_depois_min')::int <> 2520 OR (v_lin->>'maior_dia_depois_min')::int <> 504
     OR NOT (v_lin->>'tem_coletivo')::boolean OR v_lin->>'recomendacao' <> '42'
     OR (v_lin->>'requer_confirmacao_8h24')::boolean OR v_lin->>'modo' <> 'escala' THEN
    r.situacao := 'falhou'; r.obtido := 'Prévia incorreta: ' || COALESCE(left(v_lin::text, 600), 'sem linha');
  ELSIF NOT COALESCE((v_apl->>'ok')::boolean, false) OR (v_apl->>'migrados')::int <> 1 THEN
    r.situacao := 'falhou'; r.obtido := 'Migração não gravada: ' || COALESCE(v_apl::text, 'nulo');
  ELSIF v_ver IS NULL OR (v_ver->>'fim')::date <> v_d - 1 OR v_ver->>'marco' <> 'EC141_42H' THEN
    r.situacao := 'falhou'; r.obtido := 'A escala não ficou agendada para D com o marco: ' || COALESCE(v_ver::text, 'sem versão');
  ELSIF v_f0 IS DISTINCT FROM v_f1 THEN
    r.situacao := 'falhou'; r.obtido := 'A migração mudou algo antes de D: '
      || COALESCE((SELECT string_agg(k, ', ') FROM jsonb_object_keys(v_f0) k WHERE v_f0->k IS DISTINCT FROM v_f1->k), '?');
  ELSIF v_jd_1 IS DISTINCT FROM 528 OR v_jd IS DISTINCT FROM 504 THEN
    r.situacao := 'falhou'; r.obtido := format('Jornada D-1 = %s (esperado 528), D = %s (esperado 504)', v_jd_1, v_jd);
  ELSIF v_txt IS NULL OR position('art. 2º' IN v_txt) = 0 OR position('CLT, art. 468' IN v_txt) = 0
        OR position('{{' IN v_txt) > 0 OR position('42h por semana' IN v_txt) = 0 THEN
    r.situacao := 'falhou'; r.obtido := 'Aditivo ausente ou incompleto: ' || COALESCE(left(v_txt, 400), 'nenhum');
  ELSIF v_mig IS NULL OR v_mig->>'acionado_em' IS NULL OR v_mig->>'status' <> 'aplicada' THEN
    r.situacao := 'falhou'; r.obtido := 'Registro de auditoria ausente: ' || COALESCE(v_mig::text, 'nulo');
  ELSIF COALESCE((v_apl2->>'migrados')::int, -1) <> 0 OR v_itens <> 1 OR v_adit <> 1 THEN
    r.situacao := 'falhou'; r.obtido := format('Reexecutar duplicou (%s; itens %s, aditivos %s)', v_apl2::text, v_itens, v_adit);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('42h com CCT: 44h -> 42h (8h24) agendada para %s; dias anteriores idênticos; aditivo gerado (EC 141 art. 2º, CLT 468); reexecutar não duplicou.', to_char(v_d, 'DD/MM/YYYY'));
  END IF;
  r.detalhe := jsonb_build_object('linha', v_lin, 'aplicar', v_apl);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-EC141-013 ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_ec141_013()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r      public.qa_retorno;
  v_t    uuid := public.qa_sandbox_tenant_id();
  v_a    text := public.qa_cpf(6246);
  v_b    text := public.qa_cpf(6247);
  v_d    date;
  v_ea   uuid;
  v_eb   uuid;
  v_prev jsonb;
  v_la   jsonb;
  v_apl0 jsonb;
  v_apl1 jsonb;
  v_apl2 jsonb;
  v_n0   int;
  v_ja   int;
  v_jb   int;
  v_txtb text;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM set_config('request.jwt.claims', '', true);
  v_d := CURRENT_DATE + 14 + ((1 - EXTRACT(ISODOW FROM CURRENT_DATE + 14)::int + 7) % 7);   -- segunda
  PERFORM public.qa_ec141_coletivo(false);
  PERFORM public.qa_ec141_ativar('EC141_42H', v_d);
  v_ea := public.qa_ec141_escala(v_a, 528, ARRAY['segunda','terca','quarta','quinta','sexta'], DATE '2026-01-01');
  v_eb := public.qa_ec141_escala(v_b, 528, ARRAY['segunda','terca','quarta','quinta','sexta'], DATE '2026-01-01');

  r.passo_ordem := 1;
  r.passo_acao := 'Sem CCT/ACT, prévia com destino 42h';
  r.esperado := 'Recomendação 40h; 8h24 exige confirmação; aviso forte citando o art. 7º da EC 141';
  v_prev := public.ponto_ec141_migracao_previa(v_t, NULL, '42', '{}'::jsonb, ARRAY[v_ea, v_eb]);
  v_la := public.qa_ec141_linha(v_prev, v_a);

  r.passo_ordem := 2;
  r.passo_acao := 'Gravar 42h SEM a confirmação';
  r.esperado := 'Nada gravado (2 aguardando confirmação)';
  v_apl0 := public.ponto_ec141_migracao_aplicar(v_t, NULL, '42', '{}'::jsonb, false, ARRAY[v_ea, v_eb]);
  v_n0 := (SELECT count(*) FROM public.ponto_ec141_migracao_itens WHERE tenant_id = v_t AND colaborador_chave IN (v_a, v_b));

  r.passo_ordem := 3;
  r.passo_acao := 'Exceção: colaborador A em 40h direto; gravar sem confirmação; depois confirmar o B em 42h';
  r.esperado := 'A: 5 x 8h (480 em D); B só com a confirmação: 8h24 (504 em D), aditivo remete à negociação coletiva';
  v_apl1 := public.ponto_ec141_migracao_aplicar(v_t, NULL, '42', jsonb_build_object(v_a, '40'), false, ARRAY[v_ea, v_eb]);
  v_apl2 := public.ponto_ec141_migracao_aplicar(v_t, NULL, '42', jsonb_build_object(v_a, '40'), true, ARRAY[v_ea, v_eb]);
  v_ja := public.qa_ec141_jornada(v_a, v_d);
  v_jb := public.qa_ec141_jornada(v_b, v_d);
  v_txtb := (SELECT a.texto FROM public.ponto_ec141_aditivos a WHERE a.tenant_id = v_t AND a.colaborador_cpf = v_b LIMIT 1);

  IF v_la IS NULL OR v_la->>'recomendacao' <> '40' OR NOT (v_la->>'requer_confirmacao_8h24')::boolean
     OR (v_la->>'tem_coletivo')::boolean
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_la->'avisos') x WHERE x->>'nivel' = 'forte' AND position('art. 7º' IN x->>'mensagem') > 0) THEN
    r.situacao := 'falhou'; r.obtido := 'Prévia sem CCT incorreta: ' || COALESCE(left(v_la::text, 600), 'sem linha');
  ELSIF COALESCE((v_apl0->>'migrados')::int, -1) <> 0 OR COALESCE((v_apl0->>'aguardando_confirmacao')::int, 0) <> 2 OR v_n0 <> 0 THEN
    r.situacao := 'falhou'; r.obtido := 'Sem confirmação a 8h24 foi gravada: ' || COALESCE(v_apl0::text, 'nulo');
  ELSIF COALESCE((v_apl1->>'migrados')::int, -1) <> 1 OR COALESCE((v_apl2->>'migrados')::int, -1) <> 1 THEN
    r.situacao := 'falhou'; r.obtido := format('Gravação em etapas incorreta: %s / %s', v_apl1::text, v_apl2::text);
  ELSIF v_ja IS DISTINCT FROM 480 OR v_jb IS DISTINCT FROM 504 THEN
    r.situacao := 'falhou'; r.obtido := format('Jornada em D: A = %s (esperado 480), B = %s (esperado 504)', v_ja, v_jb);
  ELSIF v_txtb IS NULL OR position('negociação coletiva' IN v_txtb) = 0 THEN
    r.situacao := 'falhou'; r.obtido := 'Aditivo do B sem a remissão à negociação coletiva: ' || COALESCE(left(v_txtb, 300), 'nenhum');
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Sem CCT: recomenda 40h; 8h24 só com confirmação (aviso forte, art. 7º); 40h direto grava 5 x 8h; 8h24 confirmada grava 504.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-EC141-014 ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_ec141_014()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r      public.qa_retorno;
  v_t    uuid := public.qa_sandbox_tenant_id();
  v_a    text := public.qa_cpf(6248);
  v_b    text := public.qa_cpf(6249);
  v_d    date;
  v_esc  uuid;
  v_row0 jsonb;
  v_row1 jsonb;
  v_prev jsonb;
  v_apl  jsonb;
  v_f0   jsonb;
  v_f1   jsonb;
  v_fim  int;
  v_ja1  int; v_jb1 int; v_ja int; v_jb int;
  v_novas int;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM set_config('request.jwt.claims', '', true);
  v_d := CURRENT_DATE + 14 + ((2 - EXTRACT(ISODOW FROM CURRENT_DATE + 14)::int + 7) % 7);   -- terça
  PERFORM public.qa_ec141_coletivo(true);
  PERFORM public.qa_ec141_ativar('EC141_42H', v_d);
  v_esc := public.qa_ec141_escala(v_a, 528, ARRAY['segunda','terca','quarta','quinta','sexta'], DATE '2026-01-01');
  PERFORM public.qa_ec141_atribuir(v_esc, v_b, DATE '2026-01-01');
  PERFORM public.qa_ponto_dia_min(v_a, '[QA-EC141] Colaborador', v_d - 1, 528 + 60);
  v_row0 := (SELECT to_jsonb(e) - 'updated_at' FROM public.ponto_escalas e WHERE e.id = v_esc);
  v_f0 := public.qa_ec141_foto(v_a, v_esc, v_d - 3, v_d - 1, ARRAY[]::text[], ARRAY[]::text[]);

  r.passo_ordem := 1;
  r.passo_acao := 'Padrão da empresa 40h; exceção: colaborador B em 42h (há CCT). Os dois estão na mesma escala';
  r.esperado := 'Prévia em modo "nova_escala" para os dois; gravar cria 2 escalas novas a partir de D; a escala original não muda';
  v_prev := public.ponto_ec141_migracao_previa(v_t, NULL, '40', jsonb_build_object(v_b, '42'), ARRAY[v_esc]);
  v_apl := public.ponto_ec141_migracao_aplicar(v_t, NULL, '40', jsonb_build_object(v_b, '42'), false, ARRAY[v_esc]);
  v_row1 := (SELECT to_jsonb(e) - 'updated_at' FROM public.ponto_escalas e WHERE e.id = v_esc);
  v_f1 := public.qa_ec141_foto(v_a, v_esc, v_d - 3, v_d - 1, ARRAY[]::text[], ARRAY[]::text[]);
  v_fim := (SELECT count(*) FROM public.ponto_escala_atribuicoes a
             WHERE a.escala_id = v_esc AND a.data_fim = v_d - 1 AND COALESCE(a.ativa, true));
  v_novas := (SELECT count(*) FROM public.ponto_escalas e WHERE e.tenant_id = v_t AND e.nome LIKE '[QA-EC141]%(EC 141)');

  r.passo_ordem := 2;
  r.passo_acao := 'Jornada na véspera e na data';
  r.esperado := 'D-1: 528 para os dois (idêntico); D: A = 480, B = 504';
  v_ja1 := public.qa_ec141_jornada(v_a, v_d - 1);
  v_jb1 := public.qa_ec141_jornada(v_b, v_d - 1);
  v_ja := public.qa_ec141_jornada(v_a, v_d);
  v_jb := public.qa_ec141_jornada(v_b, v_d);

  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_prev->'linhas') x WHERE x->>'chave' IN (v_a, v_b) AND COALESCE(x->>'modo', '') <> 'nova_escala') THEN
    r.situacao := 'falhou'; r.obtido := 'Prévia devia propor escala nova para os dois: ' || left((v_prev->'linhas')::text, 400);
  ELSIF NOT COALESCE((v_apl->>'ok')::boolean, false) OR (v_apl->>'escalas_novas')::int <> 2 OR v_novas <> 2 THEN
    r.situacao := 'falhou'; r.obtido := 'Gravação incorreta: ' || COALESCE(v_apl::text, 'nulo');
  ELSIF v_row0 IS DISTINCT FROM v_row1 THEN
    r.situacao := 'falhou'; r.obtido := 'A escala original mudou (devia ficar intacta para os dois)';
  ELSIF v_fim <> 2 THEN
    r.situacao := 'falhou'; r.obtido := format('%s atribuição(ões) terminando na véspera (esperado 2, ainda ativas)', v_fim);
  ELSIF v_f0 IS DISTINCT FROM v_f1 THEN
    r.situacao := 'falhou'; r.obtido := 'A migração mudou algo antes de D: '
      || COALESCE((SELECT string_agg(k, ', ') FROM jsonb_object_keys(v_f0) k WHERE v_f0->k IS DISTINCT FROM v_f1->k), '?');
  ELSIF v_ja1 IS DISTINCT FROM 528 OR v_jb1 IS DISTINCT FROM 528 OR v_ja IS DISTINCT FROM 480 OR v_jb IS DISTINCT FROM 504 THEN
    r.situacao := 'falhou'; r.obtido := format('Jornadas D-1 %s/%s, D %s/%s (esperado 528/528, 480/504)', v_ja1, v_jb1, v_ja, v_jb);
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Destinos diferentes na mesma escala: 2 escalas novas a partir de D, original intacta, véspera idêntica; D: 40h para A e 42h para B.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-EC141-015 ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_ec141_015()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r      public.qa_retorno;
  v_t    uuid := public.qa_sandbox_tenant_id();
  v_cpf  text := public.qa_cpf(6250);
  v_d    date;
  v_seg  date;
  v_sab  date;
  v_esc  uuid;
  v_lin  jsonb;
  v_apl  jsonb;
  v_js   int;
  v_jsab int;
  v_jsab0 int;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM set_config('request.jwt.claims', '', true);
  v_d := CURRENT_DATE + 14 + ((1 - EXTRACT(ISODOW FROM CURRENT_DATE + 14)::int + 7) % 7);   -- segunda
  v_seg := v_d; v_sab := v_d + 5;
  PERFORM public.qa_ec141_coletivo(false);
  PERFORM public.qa_ec141_ativar('EC141_40H', v_d);
  v_esc := public.qa_ec141_escala(v_cpf, 440, ARRAY['segunda','terca','quarta','quinta','sexta','sabado'], DATE '2026-01-01');

  r.passo_ordem := 1;
  r.passo_acao := '6x1 de 7h20 (44h), sem CCT, destino 40h';
  r.esperado := 'Proposta 5 x 8h (40h), sábado sai (aviso de 2 repousos), sem confirmação extra';
  v_lin := public.qa_ec141_linha(public.ponto_ec141_migracao_previa(v_t, NULL, '40', '{}'::jsonb, ARRAY[v_esc]), v_cpf);
  v_jsab0 := public.qa_ec141_jornada(v_cpf, v_sab - 7);
  v_apl := public.ponto_ec141_migracao_aplicar(v_t, NULL, '40', '{}'::jsonb, false, ARRAY[v_esc]);
  v_js := public.qa_ec141_jornada(v_cpf, v_seg);
  v_jsab := COALESCE(public.qa_ec141_jornada(v_cpf, v_sab), 0);

  IF v_lin IS NULL OR v_lin->>'status' <> 'migrar' OR (v_lin->>'carga_depois_min')::int <> 2400
     OR (v_lin->>'maior_dia_depois_min')::int <> 480 OR (v_lin->>'requer_confirmacao_8h24')::boolean
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_lin->'avisos') x WHERE x->>'codigo' = 'dia_sai') THEN
    r.situacao := 'falhou'; r.obtido := 'Proposta 6x1 -> 40h incorreta: ' || COALESCE(left(v_lin::text, 600), 'sem linha');
  ELSIF NOT COALESCE((v_apl->>'ok')::boolean, false) OR (v_apl->>'migrados')::int <> 1 THEN
    r.situacao := 'falhou'; r.obtido := 'Migração não gravada: ' || COALESCE(v_apl::text, 'nulo');
  ELSIF v_jsab0 IS DISTINCT FROM 440 OR v_js IS DISTINCT FROM 480 OR v_jsab <> 0 THEN
    r.situacao := 'falhou'; r.obtido := format('Sábado antes de D = %s (esperado 440); segunda D = %s (480); sábado depois = %s (0)', v_jsab0, v_js, v_jsab);
  ELSE
    r.situacao := 'passou';
    r.obtido := '6x1 44h -> 5 x 8h (40h) a partir de D; sábado anterior segue 7h20; sábado depois de D sem jornada.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-EC141-016 ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_ec141_016()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r       public.qa_retorno;
  v_t     uuid := public.qa_sandbox_tenant_id();
  v_a     text := public.qa_cpf(6251);
  v_b     text := public.qa_cpf(6252);
  v_c     text := public.qa_cpf(6253);
  v_d     date;
  v_ex    uuid;
  v_ey    uuid;
  v_e0    jsonb; v_e2 jsonb;
  v_f0    jsonb; v_f2 jsonb;
  v_apl   jsonb;
  v_sem   jsonb;
  v_tarde jsonb;
  v_can   jsonb;
  v_adit  int;
  v_mig   jsonb;
  v_prev  jsonb;
  g       date;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM set_config('request.jwt.claims', '', true);
  v_d := CURRENT_DATE + 14 + ((3 - EXTRACT(ISODOW FROM CURRENT_DATE + 14)::int + 7) % 7);   -- quarta
  PERFORM public.qa_ec141_coletivo(true);
  PERFORM public.qa_ec141_ativar('EC141_42H', v_d);
  -- X: só o A (modo escala). Y: B e C com destinos diferentes (escalas novas).
  v_ex := public.qa_ec141_escala(v_a, 528, ARRAY['segunda','terca','quarta','quinta','sexta'], DATE '2026-01-01');
  v_ey := public.qa_ec141_escala(v_b, 528, ARRAY['segunda','terca','quarta','quinta','sexta'], DATE '2026-01-01');
  PERFORM public.qa_ec141_atribuir(v_ey, v_c, DATE '2026-01-01');
  FOR g IN SELECT x::date FROM generate_series(v_d - 3, v_d + 3, INTERVAL '1 day') x LOOP
    IF EXTRACT(ISODOW FROM g) BETWEEN 1 AND 5 THEN
      PERFORM public.qa_ponto_dia_min(v_a, '[QA-EC141] Colaborador', g, 528 + 60);
      PERFORM public.qa_ponto_dia_min(v_b, '[QA-EC141] Colaborador', g, 528 + 60);
    END IF;
  END LOOP;
  v_e0 := public.qa_ec141_estado();
  v_f0 := public.qa_ec141_foto(v_a, v_ex, v_d - 3, v_d + 3, ARRAY[]::text[], ARRAY[]::text[])
       || jsonb_build_object('b', public.qa_ec141_foto(v_b, v_ey, v_d - 3, v_d + 3, ARRAY[]::text[], ARRAY[]::text[]));

  r.passo_ordem := 1;
  r.passo_acao := 'Migrar a empresa (42h; exceção C em 40h): uma escala agendada e duas escalas novas';
  r.esperado := 'Gravado; 3 aditivos pendentes';
  v_apl := public.ponto_ec141_migracao_aplicar(v_t, NULL, '42', jsonb_build_object(v_c, '40'), false, ARRAY[v_ex, v_ey]);

  r.passo_ordem := 2;
  r.passo_acao := 'Cancelar em lote sem motivo; depois simular que a data já chegou';
  r.esperado := 'Sem motivo: recusado. Depois da data: recusado (alteraria dias já apurados)';
  v_sem := public.ponto_ec141_migracao_cancelar(v_t, NULL, 'EC141_42H', NULL);
  UPDATE public.ponto_ec141_migracoes SET vigencia_inicio = CURRENT_DATE WHERE id = (v_apl->>'migracao_id')::uuid;
  v_tarde := public.ponto_ec141_migracao_cancelar(v_t, NULL, 'EC141_42H', '[QA] lei revogada');
  UPDATE public.ponto_ec141_migracoes SET vigencia_inicio = v_d WHERE id = (v_apl->>'migracao_id')::uuid;

  r.passo_ordem := 3;
  r.passo_acao := 'Cancelar em lote com motivo (lei revogada)';
  r.esperado := 'Escalas, blocos, versões, atribuições e apuração (antes e depois de D) voltam ao estado exato; aditivos cancelados; registro com quem cancelou';
  v_can := public.ponto_ec141_migracao_cancelar(v_t, NULL, 'EC141_42H', '[QA] lei revogada');
  v_e2 := public.qa_ec141_estado();
  v_f2 := public.qa_ec141_foto(v_a, v_ex, v_d - 3, v_d + 3, ARRAY[]::text[], ARRAY[]::text[])
       || jsonb_build_object('b', public.qa_ec141_foto(v_b, v_ey, v_d - 3, v_d + 3, ARRAY[]::text[], ARRAY[]::text[]));
  v_adit := (SELECT count(*) FROM public.ponto_ec141_aditivos WHERE migracao_id = (v_apl->>'migracao_id')::uuid AND status <> 'cancelado');
  v_mig := (SELECT to_jsonb(m) FROM public.ponto_ec141_migracoes m WHERE m.id = (v_apl->>'migracao_id')::uuid);
  v_prev := public.ponto_ec141_migracao_previa(v_t, NULL, '42', jsonb_build_object(v_c, '40'), ARRAY[v_ex, v_ey]);

  IF NOT COALESCE((v_apl->>'ok')::boolean, false) OR (v_apl->>'migrados')::int <> 3 OR (v_apl->>'aditivos')::int <> 3 THEN
    r.situacao := 'falhou'; r.obtido := 'Migração não gravada como esperado: ' || COALESCE(v_apl::text, 'nulo');
  ELSIF COALESCE(v_sem->>'erro', '') <> 'motivo_obrigatorio' THEN
    r.situacao := 'falhou'; r.obtido := 'Cancelar sem motivo foi aceito: ' || COALESCE(v_sem::text, 'nulo');
  ELSIF COALESCE((v_tarde->>'migracoes_canceladas')::int, -1) <> 0 OR position('data_ja_chegou' IN COALESCE(v_tarde::text, '')) = 0 THEN
    r.situacao := 'falhou'; r.obtido := 'Cancelar depois da data foi aceito: ' || COALESCE(v_tarde::text, 'nulo');
  ELSIF NOT COALESCE((v_can->>'ok')::boolean, false) OR (v_can->>'colaboradores_restaurados')::int <> 3 THEN
    r.situacao := 'falhou'; r.obtido := 'Cancelamento falhou: ' || COALESCE(v_can::text, 'nulo');
  ELSIF v_e0 IS DISTINCT FROM v_e2 THEN
    r.situacao := 'falhou'; r.obtido := 'O estado não voltou ao exato: '
      || COALESCE((SELECT string_agg(k, ', ') FROM jsonb_object_keys(v_e0) k WHERE v_e0->k IS DISTINCT FROM v_e2->k), '?');
  ELSIF v_f0 IS DISTINCT FROM v_f2 THEN
    r.situacao := 'falhou'; r.obtido := 'A apuração não voltou ao estado anterior: '
      || COALESCE((SELECT string_agg(k, ', ') FROM jsonb_object_keys(v_f0) k WHERE v_f0->k IS DISTINCT FROM v_f2->k), '?');
  ELSIF v_adit <> 0 THEN
    r.situacao := 'falhou'; r.obtido := format('%s aditivo(s) não cancelado(s)', v_adit);
  ELSIF v_mig->>'status' <> 'cancelada' OR v_mig->>'cancelado_motivo' IS NULL OR v_mig->>'cancelado_em' IS NULL THEN
    r.situacao := 'falhou'; r.obtido := 'Registro do cancelamento incompleto: ' || COALESCE(v_mig::text, 'nulo');
  ELSIF (v_prev->'totais'->>'migrar')::int <> 3 THEN
    r.situacao := 'falhou'; r.obtido := 'Depois de cancelar, a migração devia poder ser refeita: ' || left(v_prev::text, 300);
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Cancelamento em lote: estado exato restaurado (escalas, blocos, versões, atribuições, apuração); 3 aditivos cancelados; sem motivo e depois da data, recusado.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-EC141-017 ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_ec141_017()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r        public.qa_retorno;
  v_claims text := current_setting('request.jwt.claims', true);
  v_t      uuid := public.qa_sandbox_tenant_id();
  v_cpf    text := public.qa_cpf(6254);
  v_d      date := CURRENT_DATE + 25;
  v_esc    uuid;
  v_user   uuid;
  v_anon   jsonb;
  v_apl    jsonb;
  v_mig    jsonb;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM public.qa_ec141_coletivo(false);
  PERFORM public.qa_ec141_ativar('EC141_40H', v_d);
  v_esc := public.qa_ec141_escala(v_cpf, 528, ARRAY['segunda','terca','quarta','quinta','sexta'], DATE '2026-01-01');

  r.passo_ordem := 1;
  r.passo_acao := 'Chamada sem login (chave pública) tenta gravar a migração';
  r.esperado := 'Recusada (sem_permissao)';
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  v_anon := public.ponto_ec141_migracao_aplicar(v_t, NULL, '40', '{}'::jsonb, false, ARRAY[v_esc]);
  PERFORM set_config('request.jwt.claims', '', true);

  r.passo_ordem := 2;
  r.passo_acao := 'Usuário do RH da conta aciona o assistente (40h)';
  r.esperado := 'Gravado; o registro guarda quem acionou e quando';
  v_user := public.qa_mky_usuario_empresa(v_t, 'ec141-f2');
  PERFORM public.qa_mky_claims(v_user);
  v_apl := public.ponto_ec141_migracao_aplicar(v_t, NULL, '40', '{}'::jsonb, false, ARRAY[v_esc]);
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  v_mig := (SELECT to_jsonb(m) FROM public.ponto_ec141_migracoes m WHERE m.id = NULLIF(v_apl->>'migracao_id', '')::uuid);

  IF COALESCE(v_anon->>'erro', '') <> 'sem_permissao' THEN
    r.situacao := 'falhou'; r.obtido := 'Chamada sem login não foi recusada: ' || COALESCE(left(v_anon::text, 300), 'nulo');
  ELSIF NOT COALESCE((v_apl->>'ok')::boolean, false) OR v_mig IS NULL THEN
    r.situacao := 'falhou'; r.obtido := 'O RH da conta não conseguiu migrar: ' || COALESCE(v_apl::text, 'nulo');
  ELSIF (v_mig->>'acionado_por')::uuid IS DISTINCT FROM v_user OR v_mig->>'acionado_em' IS NULL
        OR v_mig->>'destino_padrao' <> '40' OR v_mig->>'marco_codigo' <> 'EC141_40H' THEN
    r.situacao := 'falhou'; r.obtido := 'Auditoria incompleta: ' || v_mig::text;
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Sem login: recusado. RH da conta: gravado, com quem acionou, quando, marco e destino.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  BEGIN PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); EXCEPTION WHEN OTHERS THEN NULL; END;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-EC141-018 ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_ec141_018()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r      public.qa_retorno;
  v_t    uuid := public.qa_sandbox_tenant_id();
  v_cpf  text := public.qa_cpf(6255);
  v_d    date := CURRENT_DATE + 18;
  v_esc  uuid;
  v_apl  jsonb;
  v_can  jsonb;
  v_lin  jsonb;
  v_adt  jsonb;
  v_apl2 jsonb;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM public.qa_ec141_coletivo(false);
  PERFORM public.qa_ec141_ativar('EC141_40H', v_d);
  v_esc := public.qa_ec141_escala(v_cpf, 528, ARRAY['segunda','terca','quarta','quinta','sexta'], DATE '2026-01-01');

  r.passo_ordem := 1;
  r.passo_acao := 'Migrar (40h) e depois cancelar o agendamento pelo botão da própria escala (F1), fora do assistente';
  r.esperado := 'O colaborador volta a aparecer como "a migrar"; o aditivo dele aparece cancelado';
  v_apl := public.ponto_ec141_migracao_aplicar(v_t, NULL, '40', '{}'::jsonb, false, ARRAY[v_esc]);
  v_can := public.ponto_escala_cancelar_agendamento(v_esc);
  v_lin := public.qa_ec141_linha(public.ponto_ec141_migracao_previa(v_t, NULL, '40', '{}'::jsonb, ARRAY[v_esc]), v_cpf);
  v_adt := (SELECT x FROM jsonb_array_elements(public.ponto_ec141_aditivos_lista(v_t, NULL, false)) x
             WHERE x->>'colaborador_cpf' = v_cpf LIMIT 1);

  r.passo_ordem := 2;
  r.passo_acao := 'Rodar o assistente de novo';
  r.esperado := 'Grava de novo sem erro de duplicidade';
  v_apl2 := public.ponto_ec141_migracao_aplicar(v_t, NULL, '40', '{}'::jsonb, false, ARRAY[v_esc]);

  IF NOT COALESCE((v_apl->>'ok')::boolean, false) OR NOT COALESCE((v_can->>'ok')::boolean, false) THEN
    r.situacao := 'falhou'; r.obtido := format('Preparo falhou: %s / %s', v_apl::text, v_can::text);
  ELSIF v_lin IS NULL OR v_lin->>'status' <> 'migrar' THEN
    r.situacao := 'falhou'; r.obtido := 'Depois de cancelar pela escala, seguiu como migrado: ' || COALESCE(left(v_lin::text, 300), 'sem linha');
  ELSIF COALESCE(v_adt->>'situacao', '') <> 'cancelado' THEN
    r.situacao := 'falhou'; r.obtido := 'Aditivo do agendamento cancelado não aparece cancelado: ' || COALESCE(v_adt::text, 'nulo');
  ELSIF NOT COALESCE((v_apl2->>'ok')::boolean, false) OR (v_apl2->>'migrados')::int <> 1 THEN
    r.situacao := 'falhou'; r.obtido := 'Nova gravação falhou: ' || COALESCE(v_apl2::text, 'nulo');
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Cancelar pela escala desfaz a migração do colaborador (aditivo cancelado) e o assistente grava de novo sem duplicar.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-EC141-007 (ajuste de preparo da F2a) ───────────────────────────────────────────────────────
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
  -- Escala de 44h que já existia; depois a lei (42h) entra em vigor para a
  -- conta. [EC 141 F2a] a escala é criada ANTES da ativação: criar escala nova
  -- acima do teto com a lei em vigor passou a ser bloqueado ao salvar
  -- (PONTO-EC141-010), e este caso testa a BATIDA, não o salvar.
  v_esc := public.qa_ec141_escala(v_cpf, 528, ARRAY['segunda','terca','quarta','quinta','sexta'], DATE '2026-01-01');
  PERFORM public.ponto_marco_ativar('EC141_42H', CURRENT_DATE - 30, '[QA] teto em vigor', v_t);
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


-- Documentação dos casos + implementações
DO $doc$
DECLARE v_mod uuid;
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL OR to_regclass('public.qa_modulos') IS NULL THEN
    RAISE NOTICE 'Motor de QA ausente; casos PONTO-EC141 F2a não documentados.';
    RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'jornada-rotina/ponto' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo jornada-rotina/ponto ausente; casos PONTO-EC141 F2a não documentados.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PONTO-EC141-009',
   'EC 141 F2: com os marcos inativos, salvar e agendar escalas segue como antes e o assistente não aparece',
   'alternativo', 'critica', 'aprovado', 'api',
   'EC 141/2026, art. 6º (transição só por ativação manual); CF art. 7º, XIII (redação original)',
   'Decisão da fundadora: nada muda sozinho. Sem marco EC 141 ativo, a validação nova ao salvar não age (só o aviso da F1) e o assistente de migração fica invisível e recusa gravar.',
   'Cercado de QA; marcos EC 141 inativos para a conta; sem instrumento coletivo; escala 6x1 7h20.',
   '[{"ordem":1,"acao":"Salvar a 6x1 com 8h/dia (48h) valendo daqui a 20 dias","resultado_esperado":"Aceito; conferência do salvar não se aplica; a jornada da data passa a 8h (agendamento da F1)"},
     {"ordem":2,"acao":"Abrir o assistente e tentar gravar","resultado_esperado":"visivel = false; sem_marco_ativo; nenhuma migração registrada"}]'::jsonb,
   'Comportamento idêntico ao de antes com os marcos inativos.',
   'Função ponto_escala_ec141_validar_salvar / gatilho trg_ponto_escala_zz_ec141_valida; ponto_ec141_migracao_previa / _aplicar.'),
  (v_mod, 'PONTO-EC141-010',
   'EC 141 F2: escala acima do teto semanal valendo a partir da data é bloqueada ao salvar; antes da data só avisa',
   'negativo', 'critica', 'aprovado', 'api',
   'CF art. 7º, XIII (redação da EC 141/2026); EC 141/2026, art. 7º (jornada acima de 8h na transição remete à negociação coletiva)',
   'Só proibição legal bloqueia, e só ao salvar a escala. Com o marco ativo, a escala que vale a partir da data com carga acima do teto não é salva; antes da data (a lei ainda não vale) só há aviso; 8h24 (42h) passa com aviso forte; editar só a tolerância de uma escala ainda não migrada não trava.',
   'Cercado de QA; EC141_42H ativo para a conta a partir de hoje+20 (passo 4: desde ontem); sem coletivo.',
   '[{"ordem":1,"acao":"Salvar 9h/dia (45h) valendo a partir da data","resultado_esperado":"Bloqueado; mensagem cita CF art. 7º, XIII"},
     {"ordem":2,"acao":"Salvar 9h/dia sem data (antes do marco)","resultado_esperado":"Aceito"},
     {"ordem":3,"acao":"Salvar 8h24/dia (42h) valendo a partir da data","resultado_esperado":"Aceito; aviso forte (art. 7º)"},
     {"ordem":4,"acao":"Lei em vigor: mudar só a tolerância; depois a jornada para 9h","resultado_esperado":"Tolerância aceita; 9h bloqueada"}]'::jsonb,
   'Bloqueio só da proibição legal, só ao salvar.',
   'Mensagens em pt-BR com a base legal. A batida nunca é bloqueada (PONTO-EC141-007 e 011).'),
  (v_mod, 'PONTO-EC141-011',
   'EC 141 F2: 6 dias de trabalho sem instrumento coletivo a partir da data é bloqueado ao salvar; com CCT passa; a batida segue',
   'negativo', 'critica', 'aprovado', 'api',
   'CF art. 7º, XV e §2º (redação da EC 141/2026): 2 repousos semanais, média mensal só por CCT/ACT; Portaria MTP 671/2021',
   'A 6x1 a partir da data exige convenção ou acordo coletivo vigente. Sem ele, o salvar da escala é recusado com a base legal; com CCT vigente, passa. A batida do colaborador nunca é impedida.',
   'Cercado de QA; EC141_42H ativo a partir de hoje+20; escala 6x1 7h.',
   '[{"ordem":1,"acao":"Salvar 6x1 6h50 valendo a partir da data, sem coletivo","resultado_esperado":"Bloqueado; mensagem cita CF art. 7º, XV"},
     {"ordem":2,"acao":"Cadastrar CCT vigente e salvar","resultado_esperado":"Aceito"},
     {"ordem":3,"acao":"Bater o ponto ontem","resultado_esperado":"Batida gravada"}]'::jsonb,
   'Repousos exigidos só ao salvar a escala.',
   'Coletivo por ponto_tem_coletivo_vigente (Parte 1).'),
  (v_mod, 'PONTO-EC141-012',
   'Assistente "Migrar para 42h/40h" (42h com CCT): prévia, gravação a partir da data, dias anteriores idênticos, aditivo e idempotência',
   'feliz', 'critica', 'aprovado', 'api',
   'EC 141/2026, arts. 2º, 6º e 7º; CLT art. 468 (sem redução salarial; alteração só para frente)',
   'O RH aciona o assistente por empresa. A prévia por colaborador mostra a escala atual e a proposta, a carga antes/depois, se há CCT/ACT, a recomendação e os avisos. Ao confirmar, a escala é gravada com "vale a partir de" = data do marco (mecanismo da F1), sem tocar os dias anteriores; o aditivo individual é gerado; reexecutar não duplica.',
   'Cercado de QA; CCT vigente; EC141_42H ativo para D (terça daqui a ~2 semanas); escala 5x2 8h48 com batidas de D-6 a D+2.',
   '[{"ordem":1,"acao":"Prévia destino 42h","resultado_esperado":"44h -> 42h (8h24), tem CCT, recomendação 42h, sem confirmação extra, modo escala"},
     {"ordem":2,"acao":"Gravar e reexecutar","resultado_esperado":"Versão até D-1 com o marco; fotografia dos dias < D idêntica; D = 504; aditivo cita EC 141 art. 2º e CLT 468, sem variável vazia; 2ª execução não grava nada"}]'::jsonb,
   'Migração para frente, auditável e idempotente.',
   'ponto_ec141_migracao_previa / _aplicar; aditivo em ponto_ec141_aditivos (modelo ponto_ec141_aditivo_modelo).'),
  (v_mod, 'PONTO-EC141-013',
   'Assistente sem CCT/ACT: recomenda 40h; 8h24/dia só com confirmação (aviso forte); 40h direto grava 5 x 8h',
   'alternativo', 'critica', 'aprovado', 'api',
   'EC 141/2026, art. 7º (jornada diária acima de 8h na transição depende de negociação coletiva); CF art. 7º, XIII',
   'Decisão da fundadora: sem instrumento coletivo vigente para o colaborador, o assistente recomenda 40h direto (5 x 8h) e só libera 8h24/dia (42h em 5 dias) com aviso forte e confirmação explícita.',
   'Cercado de QA; sem coletivo; EC141_42H ativo para D; dois colaboradores em escalas 5x2 8h48.',
   '[{"ordem":1,"acao":"Prévia destino 42h","resultado_esperado":"Recomendação 40h; requer confirmação; aviso forte com art. 7º"},
     {"ordem":2,"acao":"Gravar sem confirmar","resultado_esperado":"Nada gravado; 2 aguardando confirmação"},
     {"ordem":3,"acao":"Exceção A = 40h; gravar; depois confirmar B","resultado_esperado":"A: 480 em D; B: 504 em D; aditivo do B remete à negociação coletiva"}]'::jsonb,
   'Recomendação e trava da 8h24 sem CCT.',
   'Instrumento do colaborador por ponto_instrumento_do_colaborador (Parte 1); sem admissão, o da conta/empresa.'),
  (v_mod, 'PONTO-EC141-014',
   'Assistente com exceção por colaborador: destinos diferentes na mesma escala criam escala nova a partir da data',
   'alternativo', 'alta', 'aprovado', 'api',
   'CLT art. 468 (alteração só para frente); Plano Mestre do Ponto, princípios 1 e 4',
   'Quando colegas da mesma escala vão para destinos diferentes, a escala original não é alterada: o assistente cria "<nome> — 40h (EC 141)" e "— 42h (EC 141)" e troca a atribuição a partir da data (a anterior termina na véspera, ainda ativa). Nada antes da data muda.',
   'Cercado de QA; CCT vigente; EC141_42H ativo para D; uma escala 5x2 8h48 com os colaboradores A e B.',
   '[{"ordem":1,"acao":"Padrão 40h, exceção B = 42h; gravar","resultado_esperado":"2 escalas novas; original intacta; atribuições antigas terminam em D-1; fotografia de A antes de D idêntica"},
     {"ordem":2,"acao":"Jornada D-1 e D","resultado_esperado":"D-1: 528/528; D: 480 (A) e 504 (B)"}]'::jsonb,
   'Exceção por colaborador sem efeito retroativo.',
   'Atribuição anterior mantém ativa = true (ponto_escala_do_dia filtra ativa).'),
  (v_mod, 'PONTO-EC141-015',
   'Assistente 6x1 de 44h para 40h: o sábado sai e ficam 5 dias de 8h',
   'feliz', 'alta', 'aprovado', 'api',
   'CF art. 7º, XIII e XV (redação da EC 141/2026): 40h e 2 repousos semanais',
   'Escala de 6 dias sem coletivo: a proposta reduz para 5 dias (sai o domingo, depois o sábado) e divide o destino igualmente, mantendo entrada e almoço.',
   'Cercado de QA; sem coletivo; EC141_40H ativo para D (segunda); escala 6x1 7h20.',
   '[{"ordem":1,"acao":"Prévia e gravação destino 40h","resultado_esperado":"40h, 8h por dia, aviso de sábado que sai, sem confirmação; sábado antes de D = 440; segunda D = 480; sábado depois de D = 0"}]'::jsonb,
   '6x1 migrada para 5 x 8h a partir da data.',
   'Proposta em _ponto_ec141_proposta.'),
  (v_mod, 'PONTO-EC141-016',
   'Cancelamento em lote da migração (lei revogada) restaura exatamente o estado anterior e cancela os aditivos',
   'feliz', 'critica', 'aprovado', 'api',
   'EC 141/2026 (pode ser revogada ou adiada antes da data); CLT art. 468; Plano Mestre do Ponto, princípio 4',
   'Se a lei mudar antes da data, o RH cancela a migração da empresa num gesto: escalas agendadas voltam pelo cancelamento da F1, atribuições voltam como eram, escalas novas são apagadas e os aditivos não assinados ficam cancelados. Exige motivo; depois da data é recusado.',
   'Cercado de QA; CCT vigente; EC141_42H ativo para D; escala X (A) e escala Y (B e C, destinos diferentes); batidas de D-3 a D+3.',
   '[{"ordem":1,"acao":"Migrar (42h, exceção C = 40h)","resultado_esperado":"3 migrados, 3 aditivos"},
     {"ordem":2,"acao":"Cancelar sem motivo; simular data já chegada","resultado_esperado":"motivo_obrigatorio; data_ja_chegou"},
     {"ordem":3,"acao":"Cancelar com motivo","resultado_esperado":"Escalas, blocos, versões, atribuições e apuração idênticos ao estado anterior; aditivos cancelados; registro com motivo; migração pode ser refeita"}]'::jsonb,
   'Desfazer exato antes da data.',
   'ponto_ec141_migracao_cancelar (usa ponto_escala_cancelar_agendamento da F1).'),
  (v_mod, 'PONTO-EC141-017',
   'Assistente: registro de auditoria de quem acionou e recusa sem login da conta',
   'negativo', 'alta', 'aprovado', 'api',
   'LGPD art. 37 (registro das operações); Portaria MTP 671/2021 (rastreabilidade das alterações de jornada)',
   'Cada acionamento grava quem, quando, empresa, marco, destino e exceções. Chamada sem usuário da conta é recusada.',
   'Cercado de QA; EC141_40H ativo; escala 5x2 8h48.',
   '[{"ordem":1,"acao":"Chamada com a chave pública (sem login)","resultado_esperado":"sem_permissao"},
     {"ordem":2,"acao":"Usuário do RH da conta grava (40h)","resultado_esperado":"Registro com acionado_por = usuário, acionado_em, marco e destino"}]'::jsonb,
   'Auditoria e permissão do assistente.',
   'ponto_ec141_migracoes.'),
  (v_mod, 'PONTO-EC141-018',
   'Assistente: cancelar o agendamento pela própria escala desfaz a migração daquele colaborador e permite refazer',
   'alternativo', 'media', 'aprovado', 'api',
   'CLT art. 468; EC 141/2026 (lei pode mudar antes da data)',
   'O botão de cancelar agendamento da escala (F1) e o cancelamento em lote do SuperAdmin continuam valendo. Se usados numa escala migrada pelo assistente, a migração daquele colaborador deixa de contar, o aditivo não enviado fica cancelado e o assistente pode gravar de novo.',
   'Cercado de QA; EC141_40H ativo; escala 5x2 8h48.',
   '[{"ordem":1,"acao":"Migrar e cancelar pelo botão da escala","resultado_esperado":"Prévia volta a mostrar migrar; aditivo cancelado"},
     {"ordem":2,"acao":"Gravar de novo","resultado_esperado":"1 migrado, sem duplicidade"}]'::jsonb,
   'Coerência entre o assistente e o cancelamento da F1.',
   '_ponto_ec141_item_vivo / _ponto_ec141_fechar_orfaos.')
  ON CONFLICT (codigo) DO UPDATE SET
    modulo_id = EXCLUDED.modulo_id, titulo = EXCLUDED.titulo, objetivo = EXCLUDED.objetivo,
    passos = EXCLUDED.passos, resultado_esperado = EXCLUDED.resultado_esperado,
    base_legal = EXCLUDED.base_legal, observacoes = EXCLUDED.observacoes,
    pre_condicoes = EXCLUDED.pre_condicoes, status = 'aprovado';

  -- PONTO-EC141-007 continua: a validação nova também nunca bloqueia a batida.
  UPDATE public.qa_casos_teste
     SET observacoes = COALESCE(observacoes, '') ||
         CASE WHEN position('EC 141 F2a' IN COALESCE(observacoes, '')) > 0 THEN ''
              ELSE ' EC 141 F2a (31/10/2026): o SALVAR da escala passa a bloquear carga acima do teto e 6 dias sem coletivo a partir da data do marco ativo (PONTO-EC141-010/011); a batida continua nunca bloqueada.' END
   WHERE codigo = 'PONTO-EC141-007';

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
      ('PONTO-EC141-009', 'qa_caso_ponto_ec141_009', true),
      ('PONTO-EC141-010', 'qa_caso_ponto_ec141_010', true),
      ('PONTO-EC141-011', 'qa_caso_ponto_ec141_011', true),
      ('PONTO-EC141-012', 'qa_caso_ponto_ec141_012', true),
      ('PONTO-EC141-013', 'qa_caso_ponto_ec141_013', true),
      ('PONTO-EC141-014', 'qa_caso_ponto_ec141_014', true),
      ('PONTO-EC141-015', 'qa_caso_ponto_ec141_015', true),
      ('PONTO-EC141-016', 'qa_caso_ponto_ec141_016', true),
      ('PONTO-EC141-017', 'qa_caso_ponto_ec141_017', true),
      ('PONTO-EC141-018', 'qa_caso_ponto_ec141_018', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentação PONTO-EC141 F2a não registrada: %', SQLERRM;
END $doc$;

-- Resumo da bateria (conferência do script de entrega). Descartável.
CREATE OR REPLACE FUNCTION public.qa_ponto_ec141_f2a_resumo()
RETURNS text LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  v_out text := '';
  v_cod text;
  v_fn  text;
  v_sit text;
BEGIN
  IF to_regprocedure('public.qa_executar_descartavel(text)') IS NULL THEN
    RETURN 'motor de QA ausente';
  END IF;
  FOR v_cod, v_fn IN
    SELECT 'PONTO-EC141-' || lpad(n::text, 3, '0'), 'qa_caso_ponto_ec141_' || lpad(n::text, 3, '0')
      FROM generate_series(1, 18) n
    UNION ALL SELECT 'PONTO-153', 'qa_caso_ponto_153'
    UNION ALL SELECT 'PONTO-478', 'qa_caso_ponto_478'
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
