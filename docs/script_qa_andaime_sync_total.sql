-- ============================================================================
-- QA — ANDAIME SYNC TOTAL: sincronizar TODOS os apoios de QA com o dev.
--
-- Os diagnosticos anteriores olhavam por NOME; apoios presentes na producao
-- porem em versao ANTIGA (ex.: qa_ponto_dia) passaram batido e faziam rotinas
-- falharem (status invalido, assinatura errada). Este lote faz CREATE OR REPLACE
-- de TODOS os apoios public.qa_* (exceto qa_caso_*) + as sub-rotinas _corpo,
-- deixando a producao identica ao dev. Read-only por natureza; nao toca dado.
-- Idempotente. Roda numa transacao (se algo falhar, desfaz tudo).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.qa_afast_legado(p_nome text, p_inicio date)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  -- Nasce legítimo: prazo indeterminado pode existir sem data de término.
  v_id := public.qa_afast_novo(p_nome, p_inicio, NULL, true);

  -- Retira a marcação. A guarda de UPDATE só reage quando havia uma data
  -- de término e alguém tenta apagá-la; aqui nunca houve.
  UPDATE public.afastamentos
     SET prazo_indeterminado = false,
         status_geral_new    = 'registrado'
   WHERE id = v_id;

  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_afast_novo(p_nome text, p_inicio date, p_fim date, p_prazo_indeterminado boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.afastamentos
    (tenant_id, colaborador_nome, colaborador_cpf, data_inicio, data_fim,
     status, prazo_indeterminado)
  VALUES (public.qa_sandbox_tenant_id(), p_nome, public.qa_cpf(9101),
          p_inicio, p_fim, 'ativo', p_prazo_indeterminado)
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_afast_tipado(p_nome text, p_semente integer, p_inicio date, p_fim date, p_tipo text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.afastamentos
    (tenant_id, colaborador_nome, colaborador_cpf, data_inicio, data_fim,
     status, tipo_principal_new)
  VALUES (public.qa_sandbox_tenant_id(), p_nome, public.qa_cpf(p_semente),
          p_inicio, p_fim, 'ativo', p_tipo::public.afastamento_tipo_principal)
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_agendamento_e2e_ler_dias()
 RETURNS TABLE(dia_semana integer, dia_nome text, ligado boolean, hora integer, minuto integer)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT d.dia_semana,
         (ARRAY['Domingo','Segunda','Terça','Quarta','Quinta','Sexta','Sábado'])[d.dia_semana + 1],
         d.ligado, d.hora, d.minuto
  FROM public.qa_agendamento_e2e_dias d
  WHERE public.is_superadmin(auth.uid())
  ORDER BY d.dia_semana;
$function$

;

CREATE OR REPLACE FUNCTION public.qa_agendamento_e2e_proxima()
 RETURNS text
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT to_char(min(prox), 'DD/MM (Dy) HH24:MI')
  FROM (
    SELECT
      date_trunc('day', v_now)
        + make_interval(days =>
            ((d.dia_semana - extract(dow from v_now)::int) + 7) % 7
            + CASE
                WHEN ((d.dia_semana - extract(dow from v_now)::int) + 7) % 7 = 0
                     AND make_time(d.hora, d.minuto, 0) <= v_now::time
                THEN 7 ELSE 0 END)
        + make_interval(hours => d.hora, mins => d.minuto) AS prox
    FROM public.qa_agendamento_e2e_dias d,
         (SELECT timezone('America/Sao_Paulo', now()) AS v_now) t
    WHERE d.ligado AND public.is_superadmin(auth.uid())
  ) x;
$function$

;

CREATE OR REPLACE FUNCTION public.qa_agendamento_e2e_salvar_dia(p_dia integer, p_ligado boolean, p_hora integer, p_minuto integer)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'cron'
AS $function$
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN
    RAISE EXCEPTION 'Apenas superadmin pode configurar o agendamento.';
  END IF;
  IF p_dia NOT BETWEEN 0 AND 6 THEN
    RAISE EXCEPTION 'Dia invalido: %.', p_dia;
  END IF;
  IF p_hora NOT BETWEEN 0 AND 23 OR p_minuto NOT BETWEEN 0 AND 59 THEN
    RAISE EXCEPTION 'Horario invalido: %:%.', p_hora, p_minuto;
  END IF;

  UPDATE public.qa_agendamento_e2e_dias
  SET ligado = p_ligado, hora = p_hora, minuto = p_minuto
  WHERE dia_semana = p_dia;

  RETURN public.qa_cron_sincronizar_e2e();
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_agendamento_ler()
 RETURNS TABLE(ligado boolean, hora integer, minuto integer, modulo_path text, proxima_execucao text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'cron'
AS $function$
  SELECT a.ligado, a.hora, a.minuto, a.modulo_path,
         (SELECT to_char(
            (CURRENT_DATE + CASE WHEN make_time(a.hora,a.minuto,0) > CURRENT_TIME
                                 THEN 0 ELSE 1 END)::timestamp
            + make_interval(hours => a.hora, mins => a.minuto),
            'DD/MM HH24:MI')
          WHERE a.ligado)
  FROM public.qa_agendamento a
  WHERE a.id = 1 AND public.is_superadmin(auth.uid());
$function$

;

CREATE OR REPLACE FUNCTION public.qa_agendamento_ler_dias()
 RETURNS TABLE(dia_semana integer, dia_nome text, ligado boolean, hora integer, minuto integer)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT d.dia_semana,
         (ARRAY['Domingo','Segunda','Terça','Quarta','Quinta','Sexta','Sábado'])[d.dia_semana + 1],
         d.ligado, d.hora, d.minuto
  FROM public.qa_agendamento_dias d
  WHERE public.is_superadmin(auth.uid())
  ORDER BY d.dia_semana;
$function$

;

CREATE OR REPLACE FUNCTION public.qa_agendamento_proxima()
 RETURNS text
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT to_char(min(prox), 'DD/MM (Dy) HH24:MI')
  FROM (
    SELECT
      date_trunc('day', v_now)
        + make_interval(days =>
            ((d.dia_semana - extract(dow from v_now)::int) + 7) % 7
            + CASE
                WHEN ((d.dia_semana - extract(dow from v_now)::int) + 7) % 7 = 0
                     AND make_time(d.hora, d.minuto, 0) <= v_now::time
                THEN 7 ELSE 0 END)
        + make_interval(hours => d.hora, mins => d.minuto) AS prox
    FROM public.qa_agendamento_dias d,
         (SELECT timezone('America/Sao_Paulo', now()) AS v_now) t
    WHERE d.ligado AND public.is_superadmin(auth.uid())
  ) x;
$function$

;

CREATE OR REPLACE FUNCTION public.qa_agendamento_salvar(p_ligado boolean, p_hora integer, p_minuto integer, p_modulo text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'cron'
AS $function$
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN
    RAISE EXCEPTION 'Apenas superadmin pode configurar o agendamento.';
  END IF;
  IF p_hora NOT BETWEEN 0 AND 23 OR p_minuto NOT BETWEEN 0 AND 59 THEN
    RAISE EXCEPTION 'Horario invalido: %:%.', p_hora, p_minuto;
  END IF;

  UPDATE public.qa_agendamento
  SET ligado = p_ligado, hora = p_hora, minuto = p_minuto,
      modulo_path = p_modulo, atualizado_em = now(),
      atualizado_por = (SELECT id FROM public.usuarios_base WHERE auth_user_id = auth.uid() LIMIT 1)
  WHERE id = 1;

  -- aplica no cron imediatamente
  RETURN public.qa_cron_sincronizar();
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_agendamento_salvar_dia(p_dia integer, p_ligado boolean, p_hora integer, p_minuto integer)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'cron'
AS $function$
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN
    RAISE EXCEPTION 'Apenas superadmin pode configurar o agendamento.';
  END IF;
  IF p_dia NOT BETWEEN 0 AND 6 THEN
    RAISE EXCEPTION 'Dia invalido: %.', p_dia;
  END IF;
  IF p_hora NOT BETWEEN 0 AND 23 OR p_minuto NOT BETWEEN 0 AND 59 THEN
    RAISE EXCEPTION 'Horario invalido: %:%.', p_hora, p_minuto;
  END IF;

  UPDATE public.qa_agendamento_dias
  SET ligado = p_ligado, hora = p_hora, minuto = p_minuto
  WHERE dia_semana = p_dia;

  RETURN public.qa_cron_sincronizar();
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_anexar_print_e2e(p_execucao_id uuid, p_spec text, p_teste text, p_evidencia_png text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_codigo text;
  v_n      int;
BEGIN
  IF p_evidencia_png IS NULL OR btrim(p_evidencia_png) = '' THEN
    RETURN false;
  END IF;

  -- O reporter conhece (spec, teste), não o código do caso — a ligação
  -- vive no banco. Resolve aqui, do mesmo jeito que a gravação faz.
  SELECT e.codigo INTO v_codigo
  FROM public.qa_cobertura_e2e e
  WHERE e.ativo AND e.spec = p_spec AND e.teste = p_teste;

  IF v_codigo IS NULL THEN
    RETURN false; -- teste sem caso documentado: não há linha para anexar
  END IF;

  UPDATE public.qa_resultados
  SET evidencia_png = p_evidencia_png
  WHERE execucao_id = p_execucao_id AND codigo = v_codigo;

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n > 0;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_assert_sandbox(p_tenant_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE v_sandbox uuid;
BEGIN
  v_sandbox := public.qa_sandbox_tenant_id();

  IF v_sandbox IS NULL THEN
    RAISE EXCEPTION 'QA ABORTADO: o cercado de teste (slug qa-sandbox) nao existe.';
  END IF;

  IF p_tenant_id IS NULL OR p_tenant_id <> v_sandbox THEN
    RAISE EXCEPTION
      'QA ABORTADO: tentativa de escrever FORA do cercado. Alvo: %, permitido: %. Nenhuma alteracao foi feita.',
      COALESCE(p_tenant_id::text,'(nulo)'), v_sandbox;
  END IF;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_bloqueia_fora_do_cercado()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_tenant  uuid;
  v_s1 uuid; v_s2 uuid;
BEGIN
  IF COALESCE(current_setting('app.qa_modo', true), 'off') <> 'on' THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;

  IF TG_OP = 'DELETE' THEN v_tenant := (to_jsonb(OLD) ->> 'tenant_id')::uuid;
  ELSE v_tenant := (to_jsonb(NEW) ->> 'tenant_id')::uuid; END IF;

  v_s1 := public.qa_sandbox_tenant_id();
  SELECT id INTO v_s2 FROM public.tenants WHERE slug = 'qa-sandbox-2';

  IF v_tenant IS DISTINCT FROM v_s1 AND v_tenant IS DISTINCT FROM v_s2 THEN
    RAISE EXCEPTION
      'QA BLOQUEADO: modo de teste ligado. Operacao % em %.% tentou tocar o tenant %. Permitido apenas os cercados. Transacao abortada.',
      TG_OP, TG_TABLE_SCHEMA, TG_TABLE_NAME, COALESCE(v_tenant::text,'(nulo)');
  END IF;

  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_210_corpo()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
  r public.qa_retorno;
  v_cpf text; v_t uuid := public.qa_sandbox_tenant_id();
  v_n1 bigint; v_n2 bigint;
  v_mudou boolean := false;
  v_unico boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Gravar duas marcacoes e conferir se o NSR nasce sozinho e continua a serie';
  r.esperado := 'NSR atribuido na gravacao, sequencial, sem buraco';

  v_cpf := public.qa_ponto_admissao('QA NSR', 2101);
  PERFORM public.qa_ponto_marca(v_cpf, 'QA NSR', CURRENT_DATE - 2, TIME '08:00', 'entrada');
  PERFORM public.qa_ponto_marca(v_cpf, 'QA NSR', CURRENT_DATE - 2, TIME '12:00', 'saida');

  SELECT min(nsr), max(nsr) INTO v_n1, v_n2
  FROM public.ponto_marcacoes
  WHERE tenant_id = v_t AND colaborador_cpf = v_cpf;

  r.passo_ordem := 2;
  r.passo_acao := 'Tentar ALTERAR o NSR de uma marcacao ja gravada';
  r.esperado := 'Recusado — o numero amarra o registro ao arquivo-fonte';
  BEGIN
    UPDATE public.ponto_marcacoes SET nsr = nsr + 1000
    WHERE tenant_id = v_t AND colaborador_cpf = v_cpf;
    v_mudou := true;
  EXCEPTION WHEN OTHERS THEN v_mudou := false; END;

  r.passo_ordem := 3;
  r.passo_acao := 'Conferir que o NSR nao se repete dentro do estabelecimento';
  r.esperado := 'Indice unico por (tenant, empresa, nsr)';
  SELECT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public' AND tablename = 'ponto_marcacoes'
      AND indexname = 'ponto_marcacoes_nsr_unico'
  ) INTO v_unico;

  IF v_n1 IS NOT NULL AND v_n2 = v_n1 + 1 AND NOT v_mudou AND v_unico THEN
    r.situacao := 'passou';
    r.obtido := format('NSR atribuido na gravacao (%s e %s, sem buraco), imutavel depois de '
             || 'gravado e unico por estabelecimento. Marcacoes anteriores a esta '
             || 'funcionalidade ficam sem NSR ate rodar o preenchimento historico.', v_n1, v_n2);
  ELSIF v_n1 IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a marcacao foi gravada SEM NSR. Sem numeracao sequencial de registro, '
             || 'o AFD improvisa numeros na exportacao e nada demonstra que nenhum registro foi '
             || 'removido. E o requisito central do arquivo-fonte da Portaria 671.';
  ELSIF v_n2 <> v_n1 + 1 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a serie do NSR tem buraco (%s depois de %s). Buraco na sequencia '
             || 'e exatamente o que a fiscalizacao le como registro removido.', v_n2, v_n1);
  ELSIF v_mudou THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o NSR de uma marcacao ja gravada pode ser ALTERADO. Numero que muda nao '
             || 'amarra nada — o vinculo entre a marcacao e o arquivo-fonte deixa de provar.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: falta o indice que impede NSR repetido dentro do estabelecimento.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_301_corpo()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_cpf text; v_comp text := to_char(CURRENT_DATE - 7, 'YYYY-MM'); v_dif int;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_cpf := public.qa_ponto_admissao('[QA-PONTO] Intocado', 30101);
  PERFORM public.qa_ponto_dia(v_cpf, '[QA-PONTO] Intocado', public.qa_dia_util_passado());

  r.passo_ordem := 1;
  r.passo_acao := 'Comparar a apuração pública com a bruta num período sem duplicatas';
  r.esperado := 'Idênticas, linha a linha — o invólucro só age quando há duplicata';
  SELECT count(*) INTO v_dif FROM (
    SELECT * FROM public.ponto_saldo_dias_competencia(v_t, v_cpf, v_comp)
    EXCEPT
    SELECT * FROM public.ponto_saldo_dias_competencia_bruto(v_t, v_cpf, v_comp)
  ) x;

  IF v_dif = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'Sem duplicata, a saída pública é idêntica à bruta — a correção foi cirúrgica como prometido.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('%s linha(s) diferentes entre a função pública e a bruta num período SEM duplicatas — o invólucro está alterando dias que deveria deixar em paz.', v_dif);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_321_corpo()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_emp uuid; v_cpf text; v_dia date := public.qa_dia_util_passado();
        v_comp text; v_colab uuid := gen_random_uuid(); a record;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_comp := to_char(v_dia, 'YYYY-MM');
  v_emp := public.qa_nova_empresa('[QA-RN23] Unidade Compensada', '11222333032102');
  v_cpf := public.qa_ponto_admissao('[QA-RN23] Compensou a Folga', 32101, v_emp);
  PERFORM public.qa_feriado_da_unidade(v_emp, v_dia);
  PERFORM public.qa_ponto_dia(v_cpf, '[QA-RN23] Compensou a Folga', v_dia, v_emp);

  r.passo_ordem := 1;
  r.passo_acao := 'Registrar a folga compensatória do feriado trabalhado';
  r.esperado := 'Registro aceito, vinculando feriado, colaborador e dia da folga';
  INSERT INTO public.feriado_folga_compensatoria
    (tenant_id, colaborador_id, colaborador_cpf, data_feriado, data_folga)
  VALUES (v_t, v_colab, v_cpf, v_dia, v_dia + 7);

  r.passo_ordem := 2;
  r.passo_acao := 'Apurar o adicional da competência com a folga registrada';
  r.esperado := 'O feriado compensado sai do cálculo do adicional (art. 9º, parte final)';
  SELECT * INTO a FROM public.ponto_feriado_adicional_competencia(v_t, v_emp, v_comp) f
  WHERE regexp_replace(f.colaborador_cpf, '[^0-9]', '', 'g') = v_cpf;

  IF a.colaborador_cpf IS NULL OR COALESCE(a.minutos_adicional_100, 0) = 0 THEN
    r.situacao := 'passou';
    r.obtido := format('Compensou, não dobra: com a folga registrada, o adicional zerou (dias compensados: %s).', COALESCE(a.dias_compensados, 0));
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('A FOLGA REGISTRADA NÃO AFASTOU A DOBRA: adicional_100 = %s minuto(s) mesmo com compensação. Pagaria em dobro E daria a folga — duas vezes a mesma hora.', a.minutos_adicional_100);
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

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_394_corpo()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_cpf text := public.qa_cpf(3941);
  v_ea uuid; v_eb uuid;
  v_data date := CURRENT_DATE - 3;
  v_linhas_dois int;
  v_cpf_uni text := public.qa_cpf(3942);
  v_data_uni date := CURRENT_DATE - 4;
  v_linhas_uni int;
BEGIN
  v_ea := public.qa_nova_empresa('QA Vinculo A ' || v_cpf, '11.222.333/0001-81', true);
  v_eb := public.qa_nova_empresa('QA Vinculo B ' || v_cpf, '11.444.777/0001-61', true);

  r.passo_ordem := 1;
  r.passo_acao := 'Registrar o MESMO dia do MESMO CPF em dois vinculos (duas empresas)';
  r.esperado := 'Cada vinculo tem a sua linha de apuracao — contratos autonomos';
  PERFORM public.qa_ponto_dia(v_cpf, 'QA Dois Vinculos', v_data, v_ea);
  PERFORM public.qa_ponto_dia(v_cpf, 'QA Dois Vinculos', v_data, v_eb);

  SELECT count(*) INTO v_linhas_dois
  FROM public.ponto_diario
  WHERE tenant_id = v_t AND colaborador_cpf = v_cpf AND data = v_data;

  r.passo_ordem := 2;
  r.passo_acao := 'Nao-regressao: um unico vinculo, marcacoes + abono, no mesmo dia';
  r.esperado := 'Uma unica linha — a empresa na chave nao parte o dia de quem tem um vinculo';
  -- admissao com empresa unica; consolidacao deriva a empresa do cadastro
  PERFORM public.qa_ponto_admissao('QA Um Vinculo', 3942, v_ea);
  PERFORM public.qa_ponto_marca(v_cpf_uni, 'QA Um Vinculo', v_data_uni, TIME '08:00', 'entrada');
  PERFORM public.qa_ponto_marca(v_cpf_uni, 'QA Um Vinculo', v_data_uni, TIME '17:00', 'saida');
  PERFORM public.consolidar_ponto_diario_manual(v_t, v_cpf_uni, v_data_uni);
  -- uma segunda escrita no mesmo dia (abono) nao pode criar uma segunda linha
  PERFORM public.consolidar_ponto_diario_manual(v_t, v_cpf_uni, v_data_uni);

  SELECT count(*) INTO v_linhas_uni
  FROM public.ponto_diario
  WHERE tenant_id = v_t AND colaborador_cpf = v_cpf_uni AND data = v_data_uni;

  IF v_linhas_dois = 2 AND v_linhas_uni = 1 THEN
    r.situacao := 'passou';
    r.obtido := 'Dois vinculos do mesmo CPF apuraram o mesmo dia em linhas separadas (2), e o '
             || 'colaborador de um unico vinculo manteve uma linha (1) apos duas escritas no '
             || 'mesmo dia. A empresa entrou na chave sem partir o dia de quem tem um vinculo.';
  ELSIF v_linhas_dois < 2 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO ESTRUTURAL: dois vinculos do mesmo CPF no mesmo dia produziram %s '
             || 'linha(s), nao 2 — a apuracao continua chaveada de um jeito que impede o segundo '
             || 'contrato. O documento de requisitos exige apuracao e arquivos POR VINCULO.',
             v_linhas_dois);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('REGRESSAO: um colaborador de UNICO vinculo ficou com %s linhas no mesmo '
             || 'dia. A empresa na chave partiu o dia de quem tem um vinculo so — o gatilho de '
             || 'reconciliacao nao esta fundindo as escritas.', v_linhas_uni);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_431_corpo()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_comp text := to_char(CURRENT_DATE, 'YYYY-MM'); v_qtd int; v_uq text;
        v_recusou boolean := false;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Montar o dossie da competencia DUAS vezes e contar';
  r.esperado := 'Um unico dossie por competencia, com data e hash atualizados';

  INSERT INTO public.ponto_dossies_fiscalizacao
    (tenant_id, competencia, periodo_ini, periodo_fim, total_pecas, hash_pacote)
  VALUES (v_t, v_comp, date_trunc('month', CURRENT_DATE)::date, CURRENT_DATE, 5, 'qa-hash-1')
  ON CONFLICT DO NOTHING;

  BEGIN
    INSERT INTO public.ponto_dossies_fiscalizacao
      (tenant_id, competencia, periodo_ini, periodo_fim, total_pecas, hash_pacote)
    VALUES (v_t, v_comp, date_trunc('month', CURRENT_DATE)::date, CURRENT_DATE, 7, 'qa-hash-2');
  EXCEPTION WHEN unique_violation THEN
    v_recusou := true;  -- a trava existe: e exatamente o que o caso cobra
  END;

  SELECT count(*) INTO v_qtd FROM public.ponto_dossies_fiscalizacao d
  WHERE d.tenant_id = v_t AND d.competencia = v_comp;

  SELECT string_agg(indexname, ', ') INTO v_uq FROM pg_indexes
  WHERE schemaname = 'public' AND tablename = 'ponto_dossies_fiscalizacao'
    AND indexdef ILIKE '%unique%';

  IF v_qtd > 1 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a mesma competencia ficou com %s dossies — remontar empilha '
             || 'copias em vez de atualizar. Dois dossies da mesma competencia com conteudos '
             || 'e hashes diferentes e o pior cenario na fiscalizacao: a empresa apresenta um '
             || 'e o auditor encontra o outro. Correcao: unicidade por tenant+competencia com '
             || 'atualizacao no lugar.', v_qtd);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Dossie unico por competencia (registros: %s; segundo lancamento %s; '
             || 'unicidade: %s).', v_qtd,
             CASE WHEN v_recusou THEN 'recusado pela trava' ELSE 'atualizou o existente' END,
             coalesce(v_uq, 'na gravacao'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_cercas_faltando()
 RETURNS TABLE(tabela text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT col.table_name::text
  FROM information_schema.columns col
  JOIN information_schema.tables t
    ON t.table_schema = col.table_schema AND t.table_name = col.table_name
  WHERE col.table_schema = 'public'
    AND col.column_name  = 'tenant_id'
    AND t.table_type     = 'BASE TABLE'
    AND col.table_name NOT LIKE 'qa\_%'
    AND NOT EXISTS (
      SELECT 1 FROM pg_trigger tg
      WHERE tg.tgname = 'qa_guarda_cercado'
        AND tg.tgrelid = ('public.' || quote_ident(col.table_name))::regclass
        AND NOT tg.tgisinternal)
  ORDER BY 1;
$function$

;

CREATE OR REPLACE FUNCTION public.qa_col_existe(p_tabela text, p_col_padrao text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT string_agg(table_name || '.' || column_name, ', ')
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND (p_tabela IS NULL OR table_name = p_tabela)
    AND column_name ILIKE p_col_padrao;
$function$

;

CREATE OR REPLACE FUNCTION public.qa_coluna_existe(p_tabela text, p_coluna text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = p_tabela AND column_name = p_coluna);
$function$

;

CREATE OR REPLACE FUNCTION public.qa_conferir_seguranca()
 RETURNS TABLE(item text, situacao text, detalhe text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_sandbox uuid;
  v_sandbox2 uuid;
  v_modo boolean;
  v_protegidas int;
  v_escritas int;
  v_sem_trava text;
  v_vazamento int;
  v_rotinas int;
  v_casos int;
BEGIN
  -- ── 1. o cercado existe? ──
  v_sandbox  := public.qa_sandbox_tenant_id();
  v_sandbox2 := public.qa_sandbox2_tenant_id();

  IF v_sandbox IS NULL THEN
    RETURN QUERY SELECT
      'Cercado principal'::text, 'FALHA'::text,
      'O tenant de teste nao existe. Nenhuma bateria pode rodar com seguranca.'::text;
  ELSE
    RETURN QUERY SELECT
      'Cercado principal'::text, 'ok'::text,
      format('Existe (%s). Todos os dados de teste sao criados nele.', v_sandbox)::text;
  END IF;

  IF v_sandbox2 IS NULL THEN
    RETURN QUERY SELECT
      'Cercado secundario'::text, 'atencao'::text,
      'Nao existe. Os casos de isolamento entre clientes nao conseguem rodar.'::text;
  ELSE
    RETURN QUERY SELECT
      'Cercado secundario'::text, 'ok'::text,
      'Existe. Usado para provar que um cliente nao enxerga o outro.'::text;
  END IF;

  -- ── 2. o modo de teste esta desligado? ──
  BEGIN
    SELECT current_setting('qa.modo_teste', true) = 'on' INTO v_modo;
  EXCEPTION WHEN OTHERS THEN
    v_modo := false;
  END;

  IF COALESCE(v_modo, false) THEN
    RETURN QUERY SELECT
      'Modo de teste'::text, 'atencao'::text,
      'LIGADO nesta sessao. Fora de uma bateria em execucao, deveria estar desligado.'::text;
  ELSE
    RETURN QUERY SELECT
      'Modo de teste'::text, 'ok'::text,
      'Desligado, como esperado fora de uma bateria.'::text;
  END IF;

  -- ── 3. as tabelas escritas pelas rotinas tem trava? ──
  SELECT count(*) INTO v_protegidas
  FROM pg_trigger tg
  JOIN pg_class c ON c.oid = tg.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE tg.tgname = 'qa_guarda_cercado' AND n.nspname = 'public' AND NOT tg.tgisinternal;

  -- tabelas do sistema que aparecem em INSERT/UPDATE/DELETE dentro de funcoes qa_*
  WITH corpo AS (
    SELECT p.proname, pg_get_functiondef(p.oid) AS def
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname LIKE 'qa\_%'
  ),
  tocadas AS (
    SELECT DISTINCT lower((regexp_matches(
             def, '(?:INSERT INTO|UPDATE|DELETE FROM)\s+public\.(\w+)', 'gi'))[1]) AS tabela
    FROM corpo
  ),
  protegidas AS (
    SELECT c.relname AS tabela
    FROM pg_trigger tg
    JOIN pg_class c ON c.oid = tg.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE tg.tgname = 'qa_guarda_cercado' AND n.nspname = 'public' AND NOT tg.tgisinternal
  )
  SELECT count(*), string_agg(t.tabela, ', ' ORDER BY t.tabela)
    INTO v_escritas, v_sem_trava
  FROM tocadas t
  WHERE t.tabela NOT LIKE 'qa\_%'
    AND t.tabela NOT IN (SELECT tabela FROM protegidas);

  IF COALESCE(v_escritas, 0) = 0 THEN
    RETURN QUERY SELECT
      'Travas do cercado'::text, 'ok'::text,
      format('%s tabelas protegidas. Toda tabela escrita pelas rotinas tem a trava.', v_protegidas)::text;
  ELSE
    RETURN QUERY SELECT
      'Travas do cercado'::text, 'FALHA'::text,
      format('%s tabela(s) escrita(s) por rotinas SEM trava: %s. Rode o SQL de instalacao da trava.',
             v_escritas, v_sem_trava)::text;
  END IF;

  -- ── 4. algum dado de teste vazou para fora do cercado? ──
  SELECT count(*) INTO v_vazamento
  FROM public.empresa_cadastro
  WHERE razao_social LIKE '[QA]%'
    AND tenant_id <> v_sandbox
    AND (v_sandbox2 IS NULL OR tenant_id <> v_sandbox2);

  IF v_vazamento = 0 THEN
    RETURN QUERY SELECT
      'Dados de teste fora do cercado'::text, 'ok'::text,
      'Nenhum registro marcado como [QA] existe fora do ambiente de teste.'::text;
  ELSE
    RETURN QUERY SELECT
      'Dados de teste fora do cercado'::text, 'FALHA'::text,
      format('%s registro(s) [QA] encontrado(s) em tenant de cliente. Investigar e remover.',
             v_vazamento)::text;
  END IF;

  -- ── 5. o inventario de casos e rotinas ──
  SELECT count(*) INTO v_casos   FROM public.qa_casos_teste;
  SELECT count(*) INTO v_rotinas FROM public.qa_implementacoes WHERE ativo;

  RETURN QUERY SELECT
    'Inventario'::text, 'ok'::text,
    format('%s casos documentados, %s com rotina executavel.', v_casos, v_rotinas)::text;

END $function$

;

CREATE OR REPLACE FUNCTION public.qa_cpf(p_semente integer)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  v_base text;
  v_d    int[];
  v_soma int;
  v_dv1  int;
  v_dv2  int;
  i      int;
BEGIN
  -- Base de 9 dígitos: prefixo 999 mantém a fixture reconhecível como teste.
  v_base := '999' || lpad((abs(p_semente) % 1000000)::text, 6, '0');

  SELECT array_agg(substring(v_base FROM g FOR 1)::int ORDER BY g)
    INTO v_d FROM generate_series(1, 9) g;

  -- 1º dígito: soma dos 9 primeiros por pesos de 10 a 2
  v_soma := 0;
  FOR i IN 1..9 LOOP v_soma := v_soma + v_d[i] * (11 - i); END LOOP;
  v_dv1 := 11 - (v_soma % 11);
  IF v_dv1 >= 10 THEN v_dv1 := 0; END IF;

  -- 2º dígito: soma dos 10 primeiros por pesos de 11 a 2
  v_soma := 0;
  FOR i IN 1..9 LOOP v_soma := v_soma + v_d[i] * (12 - i); END LOOP;
  v_soma := v_soma + v_dv1 * 2;
  v_dv2 := 11 - (v_soma % 11);
  IF v_dv2 >= 10 THEN v_dv2 := 0; END IF;

  RETURN v_base || v_dv1::text || v_dv2::text;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_cpf_formatado(p_cpf text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT format('%s.%s.%s-%s',
                substr(p_cpf,1,3), substr(p_cpf,4,3), substr(p_cpf,7,3), substr(p_cpf,10,2))
$function$

;

CREATE OR REPLACE FUNCTION public.qa_cron_sincronizar()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'cron'
AS $function$
DECLARE
  d record;
  v_utc timestamptz;
  v_hora_utc int;
  v_min_utc int;
  v_dow_utc int;
  v_ligados int := 0;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN
    RAISE EXCEPTION 'Apenas superadmin pode configurar o agendamento.';
  END IF;

  PERFORM cron.unschedule(jobname)
  FROM cron.job
  WHERE jobname = 'qa-bateria-agendada' OR jobname LIKE 'qa-bateria-dia-%';

  FOR d IN SELECT * FROM public.qa_agendamento_dias WHERE ligado ORDER BY dia_semana
  LOOP
    -- Converte o horario/dia escolhido (Brasil) para UTC, que e o que o cron usa.
    -- Ancoramos numa data qualquer que caia no dia da semana desejado.
    -- 2024-01-07 e um domingo (dow=0); somamos d.dia_semana para chegar no dia.
    v_utc := (
      (date '2024-01-07' + d.dia_semana)::timestamp
      + make_interval(hours => d.hora, mins => d.minuto)
    ) AT TIME ZONE 'America/Sao_Paulo';   -- interpreta como horario de SP -> vira timestamptz UTC

    v_hora_utc := extract(hour   from v_utc AT TIME ZONE 'UTC')::int;
    v_min_utc  := extract(minute from v_utc AT TIME ZONE 'UTC')::int;
    v_dow_utc  := extract(dow    from v_utc AT TIME ZONE 'UTC')::int;

    PERFORM cron.schedule(
      'qa-bateria-dia-' || d.dia_semana,
      format('%s %s * * %s', v_min_utc, v_hora_utc, v_dow_utc),
      $cmd$SELECT public.qa_rodar_agendada()$cmd$
    );
    v_ligados := v_ligados + 1;
  END LOOP;

  IF v_ligados = 0 THEN
    RETURN 'Nenhum dia agendado. O robo so roda manualmente.';
  END IF;
  RETURN format('%s dia(s) agendado(s), no seu horario (Brasilia).', v_ligados);
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_cron_sincronizar_e2e()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'cron'
AS $function$
DECLARE
  d record;
  v_utc timestamptz;
  v_ligados int := 0;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN
    RAISE EXCEPTION 'Apenas superadmin pode configurar o agendamento.';
  END IF;

  PERFORM cron.unschedule(jobname)
  FROM cron.job
  WHERE jobname LIKE 'qa-e2e-dia-%';

  FOR d IN SELECT * FROM public.qa_agendamento_e2e_dias WHERE ligado ORDER BY dia_semana
  LOOP
    -- 2024-01-07 é um domingo (dow=0); somamos d.dia_semana p/ chegar no dia.
    v_utc := (
      (date '2024-01-07' + d.dia_semana)::timestamp
      + make_interval(hours => d.hora, mins => d.minuto)
    ) AT TIME ZONE 'America/Sao_Paulo';   -- horário de SP -> timestamptz (UTC)

    PERFORM cron.schedule(
      'qa-e2e-dia-' || d.dia_semana,
      format('%s %s * * %s',
             extract(minute from v_utc AT TIME ZONE 'UTC')::int,
             extract(hour   from v_utc AT TIME ZONE 'UTC')::int,
             extract(dow    from v_utc AT TIME ZONE 'UTC')::int),
      $cmd$SELECT public.qa_e2e_disparar_esteira()$cmd$
    );
    v_ligados := v_ligados + 1;
  END LOOP;

  IF v_ligados = 0 THEN
    RETURN 'Nenhum dia agendado. A suíte só roda quando você publica uma mudança.';
  END IF;
  RETURN format('%s dia(s) agendado(s), no seu horário (Brasília).', v_ligados);
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_dia_util_passado(p_atras integer DEFAULT 7)
 RETURNS date
 LANGUAGE sql
 STABLE
AS $function$
  SELECT d::date FROM generate_series(CURRENT_DATE - p_atras, CURRENT_DATE - 1, interval '1 day') d
  WHERE EXTRACT(ISODOW FROM d) BETWEEN 1 AND 5
  ORDER BY d LIMIT 1
$function$

;

CREATE OR REPLACE FUNCTION public.qa_disparar_bateria(p_modulo text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '120s'
AS $function$
DECLARE v_exec uuid;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN
    RAISE EXCEPTION 'Apenas superadmin pode disparar a bateria de testes.';
  END IF;

  v_exec := public.qa_rodar_bateria('manual', p_modulo);

  UPDATE public.qa_execucoes
  SET disparada_por = (SELECT id FROM public.usuarios_base WHERE auth_user_id = auth.uid() LIMIT 1)
  WHERE id = v_exec;

  RETURN v_exec;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_e2e_disparar_esteira()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_token    text;
  v_repo     text;
  v_workflow text;
  v_ref      text;
BEGIN
  SELECT valor INTO v_token    FROM public.app_config WHERE chave = 'github_dispatch_token';
  SELECT valor INTO v_repo     FROM public.app_config WHERE chave = 'github_dispatch_repo';
  SELECT valor INTO v_workflow FROM public.app_config WHERE chave = 'github_dispatch_workflow';
  SELECT valor INTO v_ref      FROM public.app_config WHERE chave = 'github_dispatch_ref';

  -- Proteção de ambiente: sem token, não chama ninguém (avisa no log).
  IF v_token IS NULL OR btrim(v_token) = '' THEN
    RAISE NOTICE 'qa_e2e_disparar_esteira: app_config sem github_dispatch_token — nenhuma corrida disparada (proteção de ambiente).';
    RETURN;
  END IF;

  -- Padrões públicos (o repo/workflow já aparecem no código do painel e
  -- na esteira); só o token é segredo. Podem ser sobrescritos por app_config.
  v_repo     := COALESCE(NULLIF(btrim(v_repo),     ''), 'ustudy123/seguramente-0aed4f79');
  v_workflow := COALESCE(NULLIF(btrim(v_workflow), ''), 'staging.yml');
  v_ref      := COALESCE(NULLIF(btrim(v_ref),      ''), 'main');

  PERFORM net.http_post(
    url := format('https://api.github.com/repos/%s/actions/workflows/%s/dispatches',
                  v_repo, v_workflow),
    headers := jsonb_build_object(
      'Accept',               'application/vnd.github+json',
      'Authorization',        'Bearer ' || v_token,
      'X-GitHub-Api-Version', '2022-11-28',
      'User-Agent',           'youreyes-qa-esteira',
      'Content-Type',         'application/json'
    ),
    body := jsonb_build_object('ref', v_ref)
  );

  RAISE NOTICE 'qa_e2e_disparar_esteira: pedido de corrida enviado à esteira (% / % @ %).',
    v_repo, v_workflow, v_ref;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_empresa(p_nome text)
 RETURNS uuid
 LANGUAGE sql
 STABLE
AS $function$
  SELECT id FROM public.empresa_cadastro
  WHERE tenant_id = public.qa_sandbox_tenant_id() AND nome_fantasia = p_nome
  LIMIT 1
$function$

;

CREATE OR REPLACE FUNCTION public.qa_empresa_com_cota(p_nome text, p_cnpj text, p_total integer DEFAULT NULL::integer, p_pct numeric DEFAULT NULL::numeric, p_exigida integer DEFAULT NULL::integer, p_atual integer DEFAULT NULL::integer)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.empresa_cadastro
    (tenant_id, razao_social, cnpj, total_colaboradores,
     pcd_obrigatoria, pcd_percentual_exigido, pcd_quantidade_exigida, pcd_quantidade_atual)
  VALUES (public.qa_sandbox_tenant_id(), p_nome, p_cnpj, COALESCE(p_total,0),
          COALESCE(p_total,0) >= 100, COALESCE(p_pct,0), COALESCE(p_exigida,0), COALESCE(p_atual,0))
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_empresa_com_ponto(p_nome text, p_cnpj text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  v_id := public.qa_nova_empresa(p_nome, p_cnpj);
  UPDATE public.empresa_cadastro SET usa_controle_ponto = true WHERE id = v_id;
  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_executar_descartavel(p_funcao text)
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
  r public.qa_retorno;
  v_claims text;
BEGIN
  -- Fotografa o estado de sessão ANTES do caso, para devolver depois.
  v_claims := current_setting('request.jwt.claims', true);

  PERFORM public.qa_modo_ligar();
  PERFORM public.qa_exigir_modo();

  BEGIN
    EXECUTE format('SELECT * FROM public.%I()', p_funcao) INTO r;
    RAISE EXCEPTION USING ERRCODE = 'QA000', MESSAGE = 'QA_DESCARTE';
  EXCEPTION
    WHEN SQLSTATE 'QA000' THEN
      NULL;  -- caminho normal: os dados de teste já foram desfeitos
    WHEN OTHERS THEN
      r.situacao     := 'erro';
      r.obtido       := 'A rotina quebrou. Nenhum dado ficou na base.';
      r.erro_tecnico := SQLERRM || ' [' || SQLSTATE || ']';
  END;

  -- Estado de sessão NÃO é desfeito pelo rollback da subtransação quando o caso
  -- usa set_config(...,true) / SET ROLE; devolvemos à mão para não vazar.
  BEGIN
    EXECUTE 'RESET ROLE';
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);

  IF r.situacao IS NULL THEN
    r.situacao := 'erro';
    r.obtido   := 'A rotina nao devolveu veredito.';
  END IF;
  RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_exigir_modo()
 RETURNS void
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
  IF COALESCE(current_setting('app.qa_modo', true), 'off') <> 'on' THEN
    RAISE EXCEPTION
      'QA ABORTADO: modo de teste desligado. A trava do cercado estaria inerte e a rotina poderia escrever em cliente real. Nada foi executado.';
  END IF;
  IF public.qa_sandbox_tenant_id() IS NULL THEN
    RAISE EXCEPTION 'QA ABORTADO: o cercado nao existe.';
  END IF;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_feriado_da_unidade(p_empresa_id uuid, p_data date, p_nome text DEFAULT '[QA] Feriado de Teste'::text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_t uuid := public.qa_sandbox_tenant_id(); v_tab uuid;
BEGIN
  INSERT INTO public.feriado_tabelas (tenant_id, nome, uf, municipio, ano, ativo)
  VALUES (v_t, p_nome || ' ' || p_data, 'SP', 'São Paulo', EXTRACT(YEAR FROM p_data)::int, true)
  RETURNING id INTO v_tab;
  INSERT INTO public.feriado_tabela_itens (tenant_id, tabela_id, nome, data, recorrente, tipo, ativo)
  VALUES (v_t, v_tab, p_nome, p_data, false, 'feriado', true);
  INSERT INTO public.feriado_tabela_empresas (tenant_id, tabela_id, empresa_id)
  VALUES (v_t, v_tab, p_empresa_id);
  RETURN v_tab;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_ferias_periodo(p_cpf text, p_nome text, p_faltas integer DEFAULT 0, p_aquisitivo_fim date DEFAULT (CURRENT_DATE - 30))
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid; v_direito int := public.ferias_dias_por_faltas_clt(p_faltas);
BEGIN
  INSERT INTO public.ferias_periodos_aquisitivos
    (tenant_id, colaborador_cpf, colaborador_nome, data_admissao,
     aquisitivo_inicio, aquisitivo_fim, faltas_carga, dias_gozados,
     fonte_faltas, dias_direito, dias_saldo, faltas_consideradas, status, origem)
  VALUES (public.qa_sandbox_tenant_id(), p_cpf, p_nome,
          p_aquisitivo_fim - interval '1 year',
          p_aquisitivo_fim - interval '1 year', p_aquisitivo_fim,
          p_faltas, 0, 'carga', v_direito, v_direito, p_faltas, 'ativo', 'sistema')
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_ferias_sonda_calculo(p_tenant uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id UUID;
BEGIN
    INSERT INTO public.folha_ferias_calculo
        (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
         periodo_aquisitivo_inicio, periodo_aquisitivo_fim,
         data_inicio_gozo, data_fim_gozo, dias_gozo,
         valor_ferias, valor_terco, total_liquido, data_pagamento, status)
    VALUES
        (p_tenant, 'QA-ESOCIAL', 'QA eSocial', '90000000191',
         CURRENT_DATE - 400, CURRENT_DATE - 35,
         CURRENT_DATE + 40, CURRENT_DATE + 69, 30,
         3000, 1000, 3600, CURRENT_DATE + 37, 'calculado')
    RETURNING id INTO v_id;
    RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_fixture_email(p_codigo text, p_n integer)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT 'qa.' || lower(replace(p_codigo, '-', '')) || '.' || p_n || '@sandbox.invalid'
$function$

;

CREATE OR REPLACE FUNCTION public.qa_fixture_limpar(p_codigo text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE v_tenant uuid := public.qa_sandbox_tenant_id();
BEGIN
  PERFORM public.qa_modo_ligar();
  -- usuario_vinculos tem ON DELETE CASCADE a partir de usuarios_base
  DELETE FROM public.usuarios_base
  WHERE tenant_id = v_tenant
    AND email_principal LIKE 'qa.' || lower(replace(p_codigo, '-', '')) || '.%@sandbox.invalid';
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_fns_com(p_padrao text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT string_agg(p.proname, ', ')
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE p_padrao;
$function$

;

CREATE OR REPLACE FUNCTION public.qa_houve_vazamento()
 RETURNS boolean
 LANGUAGE sql
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.qa_verifica_vazamento() v
    WHERE v.veredito LIKE '>>>%'
  );
$function$

;

CREATE OR REPLACE FUNCTION public.qa_instalar_cercas()
 RETURNS TABLE(nome_tabela text, acao text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  c        record;
  v_tinha  boolean;
  v_novas  int := 0;
  v_ja     int := 0;
BEGIN
  IF to_regprocedure('public.qa_bloqueia_fora_do_cercado()') IS NULL THEN
    RAISE EXCEPTION 'qa_bloqueia_fora_do_cercado() nao existe — rode as migrations do cercado antes.';
  END IF;

  FOR c IN
    SELECT col.table_name
    FROM information_schema.columns col
    JOIN information_schema.tables t
      ON t.table_schema = col.table_schema AND t.table_name = col.table_name
    WHERE col.table_schema = 'public'
      AND col.column_name  = 'tenant_id'
      AND t.table_type     = 'BASE TABLE'
      AND col.table_name NOT LIKE 'qa\_%'   -- as tabelas do proprio QA ficam de fora
    ORDER BY col.table_name
  LOOP
    SELECT EXISTS (
      SELECT 1 FROM pg_trigger tg
      WHERE tg.tgname = 'qa_guarda_cercado'
        AND tg.tgrelid = ('public.' || quote_ident(c.table_name))::regclass
        AND NOT tg.tgisinternal
    ) INTO v_tinha;

    IF NOT v_tinha THEN
      EXECUTE format(
        'CREATE TRIGGER qa_guarda_cercado
           BEFORE INSERT OR UPDATE OR DELETE ON public.%I
           FOR EACH ROW EXECUTE FUNCTION public.qa_bloqueia_fora_do_cercado()',
        c.table_name);
      v_novas := v_novas + 1;
      nome_tabela := c.table_name; acao := 'trava instalada'; RETURN NEXT;
    ELSE
      v_ja := v_ja + 1;
    END IF;

    -- ON CONFLICT nomeando a coluna colidiria com o parametro de saida.
    INSERT INTO public.qa_tabelas_protegidas AS p (tabela, motivo)
    SELECT c.table_name, 'Cerca generica: tabela tem tenant_id'
    WHERE NOT EXISTS (SELECT 1 FROM public.qa_tabelas_protegidas x
                      WHERE x.tabela = c.table_name);
  END LOOP;

  nome_tabela := format('%s tabela(s) ja protegida(s), %s nova(s)', v_ja, v_novas);
  acao        := 'resumo';
  RETURN NEXT;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_limpa_config_metas(p_tenant uuid)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  DELETE FROM public.metas_configuracao WHERE tenant_id = p_tenant;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_limpa_identidade(p_tenant uuid)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  DELETE FROM public.estrategia_cultura WHERE tenant_id = p_tenant;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_limpar_historico(p_dias integer DEFAULT 90)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE v_n int;
BEGIN
  WITH alvo AS (
    SELECT id FROM public.qa_execucoes
    WHERE iniciada_em < now() - make_interval(days => p_dias)
      AND falhou = 0 AND erro = 0        -- bateria que achou algo fica para sempre
  )
  DELETE FROM public.qa_execucoes e USING alvo a WHERE e.id = a.id;
  GET DIAGNOSTICS v_n = ROW_COUNT;       -- qa_resultados cai por CASCADE
  RETURN v_n;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_listar_baterias(p_limite integer DEFAULT 20)
 RETURNS TABLE(id uuid, iniciada_em timestamp with time zone, disparo text, modulo_path text, total integer, passou integer, falhou integer, nao_implementado integer, erro integer, duracao_ms integer, observacao text, disparada_por_nome text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT e.id, e.iniciada_em, e.disparo::text, e.modulo_path,
         e.total, e.passou, e.falhou, e.nao_implementado, e.erro,
         e.duracao_ms, e.observacao, u.nome_completo
  FROM public.qa_execucoes e
  LEFT JOIN public.usuarios_base u ON u.id = e.disparada_por
  WHERE public.is_superadmin(auth.uid())
  ORDER BY e.iniciada_em DESC
  LIMIT p_limite;
$function$

;

CREATE OR REPLACE FUNCTION public.qa_mky_anuncio_publicado(p_uid uuid, p_nome text, p_slug text, p_modalidade text, p_tipo_preco text, p_preco numeric, p_extra jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_claims text := current_setting('request.jwt.claims', true); v_cat uuid; v_id uuid;
BEGIN
  SELECT id INTO v_cat FROM public.marketplace_categorias WHERE slug = p_slug;
  IF v_cat IS NULL THEN RAISE EXCEPTION 'Categoria % não existe na taxonomia', p_slug; END IF;
  PERFORM public.qa_mky_claims(p_uid);
  v_id := (public.marketye_anuncio_salvar(jsonb_build_object('nome', p_nome, 'descricao', 'Serviço fictício de teste do MarketYE para a rotina automatizada de busca.', 'categoria_id', v_cat,
            'modalidade', p_modalidade, 'tipo_preco', p_tipo_preco, 'preco_referencia', p_preco) || COALESCE(p_extra, '{}'::jsonb))->>'id')::uuid;
  PERFORM public.marketye_anuncio_publicar(v_id);
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_mky_cenario_seguranca()
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_claims text := current_setting('request.jwt.claims', true);
  t1 uuid := public.qa_sandbox_tenant_id(); t2 uuid; sa uuid; x uuid; y uuid; a record; b record; cat uuid;
  b_pub uuid; b_rasc uuid; a_pub uuid; lead_xb uuid; lead_ya uuid; msg_xb uuid; msg_ya uuid; cupom_b uuid; contest_b uuid; ocorr_b uuid;
  dest_b uuid; doc_xb uuid; den_y uuid; contr_y uuid; dem_y uuid; aval_a uuid; v jsonb;
BEGIN
  IF t1 IS NULL THEN RAISE EXCEPTION 'Cercado qa-sandbox não existe'; END IF;
  SELECT id INTO t2 FROM public.tenants WHERE slug = 'qa-sandbox-2';
  IF t2 IS NULL THEN RAISE EXCEPTION 'Segundo cercado (qa-sandbox-2) não existe'; END IF;
  sa := public.qa_mky_superadmin();
  x := public.qa_mky_usuario_empresa(t1, '110x'); y := public.qa_mky_usuario_empresa(t2, '110y');
  SELECT * INTO a FROM public.qa_mky_especialista('110a', '900.000.032-71');
  SELECT * INTO b FROM public.qa_mky_especialista('110b', '900.000.033-52');
  SELECT id INTO cat FROM public.marketplace_categorias WHERE slug = 'seguranca-trabalho';

  PERFORM public.qa_mky_claims(sa);
  PERFORM public.marketye_moderar_especialista(a.prof_id, 'aprovado', NULL, true);
  PERFORM public.marketye_moderar_especialista(b.prof_id, 'aprovado', NULL, true);

  PERFORM public.qa_mky_claims(b.uid);
  v := public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Seguranca B publicado', 'descricao', 'Serviço fictício de teste do MarketYE, apenas para a rotina automatizada de segurança.', 'categoria_id', cat, 'modalidade', 'online', 'tipo_preco', 'hora', 'preco_referencia', 300));
  b_pub := (v->>'id')::uuid; PERFORM public.marketye_anuncio_publicar(b_pub);
  v := public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Seguranca B rascunho', 'descricao', 'Rascunho fictício de teste do MarketYE que não deve aparecer para ninguém.', 'categoria_id', cat, 'modalidade', 'online', 'tipo_preco', 'sob_orcamento'));
  b_rasc := (v->>'id')::uuid;
  v := public.marketye_cupom_salvar(jsonb_build_object('codigo', 'QASEG110', 'descricao', 'cupom de teste', 'desconto_percentual', 10));
  SELECT id INTO cupom_b FROM public.marketplace_cupons WHERE profissional_id = b.prof_id AND codigo = 'QASEG110';

  PERFORM public.qa_mky_claims(a.uid);
  v := public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Seguranca A publicado', 'descricao', 'Serviço fictício de teste do MarketYE, apenas para a rotina automatizada de segurança.', 'categoria_id', cat, 'modalidade', 'presencial', 'tipo_preco', 'hora', 'preco_referencia', 250));
  a_pub := (v->>'id')::uuid; PERFORM public.marketye_anuncio_publicar(a_pub);

  PERFORM public.qa_mky_claims(x);
  lead_xb := (public.marketye_abrir_lead(b.prof_id, b_pub, 'Preciso de um PGR para a minha empresa de teste.')->>'id')::uuid;
  SELECT id INTO msg_xb FROM public.marketplace_lead_mensagens WHERE lead_id = lead_xb ORDER BY created_at LIMIT 1;

  PERFORM public.qa_mky_claims(y);
  lead_ya := (public.marketye_abrir_lead(a.prof_id, a_pub, 'Preciso de um laudo para a minha empresa de teste.')->>'id')::uuid;
  SELECT id INTO msg_ya FROM public.marketplace_lead_mensagens WHERE lead_id = lead_ya ORDER BY created_at LIMIT 1;
  PERFORM public.qa_mky_claims(a.uid); PERFORM public.marketye_lead_mensagem(lead_ya, 'Posso atender na próxima semana.');
  PERFORM public.qa_mky_claims(y); PERFORM public.marketye_lead_status(lead_ya, 'ganho');
  v := public.marketye_avaliar('lead', lead_ya, '{"pontualidade":4,"clareza":5,"aderencia_escopo":4,"profissionalismo":5}'::jsonb, 'Avaliação fictícia de teste.');
  SELECT id INTO aval_a FROM public.marketplace_avaliacoes WHERE lead_id = lead_ya AND direcao = 'cliente_para_especialista' LIMIT 1;

  PERFORM public.qa_mky_claims(sa);
  v := public.marketye_destaque_criar(b.prof_id, NULL, 'topo', NULL, NULL, CURRENT_DATE, CURRENT_DATE + 7, NULL);
  dest_b := (v->>'id')::uuid;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);

  -- Mobiliário inserido direto (a rotina roda como o dono do banco): contestação, ocorrência, documento, denúncia, contratação legada, demanda latente.
  INSERT INTO public.marketplace_contestacoes (profissional_id, decisao_tipo, motivo) VALUES (b.prof_id, 'outro', 'Contestação fictícia de teste da rotina de segurança.') RETURNING id INTO contest_b;
  INSERT INTO public.marketplace_ocorrencias (profissional_id, tipo, descricao, reflexo_visibilidade) VALUES (b.prof_id, 'ocorrencia', 'Ocorrência fictícia de teste.', false) RETURNING id INTO ocorr_b;
  INSERT INTO public.marketplace_lead_documentos (lead_id, documento_id, tipo) VALUES (lead_xb, gen_random_uuid(), 'proposta') RETURNING id INTO doc_xb;
  INSERT INTO public.marketplace_denuncias (tenant_id, profissional_id, denunciante_id, denunciante_nome, tipo, descricao) VALUES (t2, a.prof_id, y, 'QA Empresa 110y', 'outro', 'Denúncia fictícia de teste.') RETURNING id INTO den_y;
  INSERT INTO public.marketplace_contratacoes (tenant_id, servico_id, profissional_id, solicitante_id, solicitante_nome, modalidade) VALUES (t2, a_pub, a.prof_id, y, 'QA Empresa 110y', 'presencial') RETURNING id INTO contr_y;
  INSERT INTO public.marketplace_demanda_latente (tenant_id, categoria_id, uf, termos, resultados) VALUES (t2, cat, 'QA', 'demanda fictícia', 0) RETURNING id INTO dem_y;

  RETURN jsonb_build_object('t1', t1, 't2', t2, 'sa', sa, 'x', x, 'y', y, 'a_uid', a.uid, 'a_prof', a.prof_id, 'b_uid', b.uid, 'b_prof', b.prof_id,
                            'b_pub', b_pub, 'b_rasc', b_rasc, 'a_pub', a_pub, 'lead_xb', lead_xb, 'lead_ya', lead_ya, 'msg_xb', msg_xb, 'msg_ya', msg_ya,
                            'cupom_b', cupom_b, 'contest_b', contest_b, 'ocorr_b', ocorr_b, 'dest_b', dest_b, 'doc_xb', doc_xb, 'den_y', den_y,
                            'contr_y', contr_y, 'dem_y', dem_y, 'aval_a', aval_a);
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_mky_claims(p_uid uuid)
 RETURNS void
 LANGUAGE sql
AS $function$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$function$

;

CREATE OR REPLACE FUNCTION public.qa_mky_especialista(p_marca text, p_cpf text)
 RETURNS TABLE(uid uuid, prof_id uuid)
 LANGUAGE plpgsql
AS $function$
DECLARE v_uid uuid := gen_random_uuid(); v_res jsonb;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_uid, 'qa-mky-esp-' || p_marca || '-' || left(v_uid::text, 8) || '@sandbox.invalid');
  v_res := public.marketye_cadastrar_especialista_para(v_uid, jsonb_build_object(
    'nome_completo', 'QA Especialista ' || p_marca, 'email', 'qa-mky-esp-' || p_marca || '-' || left(v_uid::text, 8) || '@sandbox.invalid',
    'cpf_cnpj', p_cpf, 'cidade', 'Cidade QA', 'estado', 'QA', 'modalidades', '["presencial","online"]'::jsonb, 'aceite_termos', true,
    'conselho', 'CREA', 'registro_profissional', 'QA-' || p_marca, 'origem', 'qa', 'tenant_origem', public.qa_sandbox_tenant_id()));
  RETURN QUERY SELECT v_uid, (v_res->>'id')::uuid;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_mky_limpar()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Dependentes sem ON DELETE CASCADE primeiro (auditoria, avaliações, denúncias, contratações), depois o especialista (o resto cascateia).
  DELETE FROM public.marketplace_audit_log WHERE profissional_id IN (SELECT id FROM public.marketplace_profissionais WHERE nome_completo LIKE 'QA Especialista %' OR email LIKE 'qa-mky-%@sandbox.invalid');
  DELETE FROM public.marketplace_avaliacoes WHERE profissional_id IN (SELECT id FROM public.marketplace_profissionais WHERE nome_completo LIKE 'QA Especialista %' OR email LIKE 'qa-mky-%@sandbox.invalid');
  DELETE FROM public.marketplace_denuncias WHERE profissional_id IN (SELECT id FROM public.marketplace_profissionais WHERE nome_completo LIKE 'QA Especialista %' OR email LIKE 'qa-mky-%@sandbox.invalid');
  DELETE FROM public.marketplace_contratacoes WHERE profissional_id IN (SELECT id FROM public.marketplace_profissionais WHERE nome_completo LIKE 'QA Especialista %' OR email LIKE 'qa-mky-%@sandbox.invalid');
  DELETE FROM public.marketplace_leads WHERE profissional_id IN (SELECT id FROM public.marketplace_profissionais WHERE nome_completo LIKE 'QA Especialista %' OR email LIKE 'qa-mky-%@sandbox.invalid');
  DELETE FROM public.marketplace_profissionais WHERE nome_completo LIKE 'QA Especialista %' OR email LIKE 'qa-mky-%@sandbox.invalid';
  DELETE FROM public.marketplace_demanda_latente WHERE uf = 'QA';
  DELETE FROM public.marketplace_categorias WHERE slug LIKE 'qa-mky-%';
  DELETE FROM public.superadmins WHERE email LIKE 'qa-mky-%@sandbox.invalid';
  DELETE FROM public.profiles WHERE nome_completo LIKE 'QA Empresa %' AND user_id IN (SELECT id FROM auth.users WHERE email LIKE 'qa-mky-%@sandbox.invalid');
  DELETE FROM public.tenants WHERE slug LIKE 'qa-mky-%';
  DELETE FROM auth.users WHERE email LIKE 'qa-mky-%@sandbox.invalid';
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_mky_superadmin()
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_uid uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_uid, 'qa-mky-sa-' || left(v_uid::text, 8) || '@sandbox.invalid');
  INSERT INTO public.superadmins (user_id, email, nome, ativo) VALUES (v_uid, 'qa-mky-sa-' || left(v_uid::text, 8) || '@sandbox.invalid', 'QA Superadmin MKY', true);
  RETURN v_uid;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_mky_usuario_empresa(p_tenant uuid, p_marca text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_uid uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_uid, 'qa-mky-' || p_marca || '-' || left(v_uid::text, 8) || '@sandbox.invalid');
  INSERT INTO public.profiles (user_id, tenant_id, nome_completo, onboarding_concluido) VALUES (v_uid, p_tenant, 'QA Empresa ' || p_marca, true);
  RETURN v_uid;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_mobiliario_registrar()
 RETURNS TABLE(tabela text, esperado bigint)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_t uuid := public.qa_sandbox_tenant_id();
  c   record;
  v_n bigint;
BEGIN
  IF v_t IS NULL THEN
    RAISE EXCEPTION 'Cercado nao existe. Nao da para medir a linha de base.';
  END IF;

  -- WHERE true pelo mesmo motivo do detector: safeupdate nos papeis da API.
  DELETE FROM public.qa_mobiliario_fixo WHERE true;

  FOR c IN
    SELECT col.table_name
    FROM information_schema.columns col
    JOIN information_schema.tables t
      ON t.table_schema = col.table_schema AND t.table_name = col.table_name
    WHERE col.table_schema = 'public'
      AND col.column_name  = 'tenant_id'
      AND t.table_type     = 'BASE TABLE'
      AND col.table_name NOT LIKE 'qa\_%'
    ORDER BY col.table_name
  LOOP
    EXECUTE format('SELECT count(*) FROM public.%I WHERE tenant_id = $1', c.table_name)
      INTO v_n USING v_t;

    IF v_n > 0 THEN
      INSERT INTO public.qa_mobiliario_fixo (tabela, esperado, motivo)
      VALUES (c.table_name, v_n, 'Medido com o cercado em repouso');
    END IF;
  END LOOP;

  RETURN QUERY
  SELECT m.tabela, m.esperado FROM public.qa_mobiliario_fixo m ORDER BY m.tabela;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_modo_ligado()
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$ SELECT COALESCE(current_setting('app.qa_modo', true), 'off') = 'on' $function$

;

CREATE OR REPLACE FUNCTION public.qa_modo_ligar()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  PERFORM set_config('app.qa_modo', 'on', true);  -- true = morre com a transação
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_modulos_testaveis()
 RETURNS TABLE(modulo_path text, label text, casos_executaveis bigint)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT m.path, m.label, count(*)
  FROM public.qa_casos_teste c
  JOIN public.qa_modulos m ON m.id = c.modulo_id
  JOIN public.qa_implementacoes i ON i.codigo = c.codigo AND i.ativo
  WHERE c.status = 'aprovado'
    AND public.is_superadmin(auth.uid())
  GROUP BY m.path, m.label
  ORDER BY m.path;
$function$

;

CREATE OR REPLACE FUNCTION public.qa_nova_acao(p_titulo text, p_codigo text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid; v_cod text;
BEGIN
  v_cod := COALESCE(p_codigo, 'QA-' || substr(gen_random_uuid()::text, 1, 8));
  INSERT INTO public.plano_acoes (tenant_id, codigo, titulo, origem_modulo)
  VALUES (public.qa_sandbox_tenant_id(), v_cod, p_titulo, 'manual') RETURNING id INTO v_id;
  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_nova_competencia(p_comp text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.hub_competencias (tenant_id, competencia)
  VALUES (public.qa_sandbox_tenant_id(), p_comp) RETURNING id INTO v_id;
  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_nova_condicao(p_nome text, p_insal boolean DEFAULT false, p_grau text DEFAULT NULL::text, p_val_insal numeric DEFAULT 0, p_peric boolean DEFAULT false, p_val_peric numeric DEFAULT 0, p_aplicado text DEFAULT NULL::text, p_val_aplicado numeric DEFAULT 0)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.colaborador_condicoes_especiais
    (tenant_id, colaborador_id, colaborador_nome,
     insalubridade, insalubridade_grau, insalubridade_valor_calculado,
     periculosidade, periculosidade_valor_calculado,
     adicional_aplicado, adicional_valor_aplicado)
  VALUES (public.qa_sandbox_tenant_id(), '52998224725', p_nome,
          p_insal, p_grau, p_val_insal, p_peric, p_val_peric, p_aplicado, p_val_aplicado)
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_nova_empresa(p_razao text, p_cnpj text, p_ativo boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_t  uuid := public.qa_sandbox_tenant_id();
  v_id uuid;
BEGIN
  -- Reaproveita a empresa do cercado com o mesmo CNPJ, se ela ja existe.
  SELECT e.id INTO v_id
  FROM public.empresa_cadastro e
  WHERE e.tenant_id = v_t AND e.cnpj = p_cnpj
  ORDER BY (e.ativo IS TRUE) DESC, e.created_at NULLS LAST
  LIMIT 1;

  IF v_id IS NOT NULL THEN
    UPDATE public.empresa_cadastro
       SET razao_social = p_razao, nome_fantasia = p_razao, ativo = p_ativo
     WHERE id = v_id;
    RETURN v_id;
  END IF;

  INSERT INTO public.empresa_cadastro (tenant_id, razao_social, nome_fantasia, cnpj, ativo)
  VALUES (v_t, p_razao, p_razao, p_cnpj, p_ativo)
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_nova_empresa_pf(p_razao text, p_cpf text, p_ativo boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.empresa_cadastro
    (tenant_id, razao_social, nome_fantasia, tipo_pessoa, cpf, ativo)
  VALUES (public.qa_sandbox_tenant_id(), p_razao, p_razao, 'pf', p_cpf, p_ativo)
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_nova_meta(p_titulo text, p_ano integer DEFAULT 2026)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.metas (tenant_id, titulo, ano)
  VALUES (public.qa_sandbox_tenant_id(), p_titulo, p_ano) RETURNING id INTO v_id;
  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_nova_obrigacao(p_categoria text, p_titulo text, p_status text DEFAULT 'pendente'::text, p_criticidade text DEFAULT 'media'::text, p_subcategoria text DEFAULT NULL::text, p_acao uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.empresa_obrigacoes
    (tenant_id, categoria, subcategoria, titulo, status, criticidade, acao_gerada_id)
  VALUES (public.qa_sandbox_tenant_id(), p_categoria, p_subcategoria, p_titulo,
          p_status, p_criticidade, p_acao)
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_nova_pasta(p_nome text, p_pai uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.documento_pastas (tenant_id, nome, pasta_pai_id)
  VALUES (public.qa_sandbox_tenant_id(), p_nome, p_pai) RETURNING id INTO v_id;
  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_nova_swot(p_titulo text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.estrategia_swot (tenant_id, titulo)
  VALUES (public.qa_sandbox_tenant_id(), p_titulo) RETURNING id INTO v_id;
  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_nova_tabela_feriados(p_nome text, p_tenant uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_t uuid := COALESCE(p_tenant, public.qa_sandbox_tenant_id()); v_id uuid;
BEGIN
  INSERT INTO public.feriado_tabelas (tenant_id, nome, uf, municipio, ano, ativo)
  VALUES (v_t, p_nome, 'SP', 'São Paulo', 2026, true)
  RETURNING id INTO v_id;
  INSERT INTO public.feriado_tabela_itens (tenant_id, tabela_id, nome, data, recorrente, tipo, ativo)
  VALUES (v_t, v_id, '[QA] Aniversário da Cidade', DATE '2026-01-25', false, 'feriado', true);
  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_novo_doc_terceiro(p_terceiro uuid, p_tipo text, p_nome text, p_validade date DEFAULT NULL::date, p_trabalhador uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.terceiro_documentos
    (tenant_id, terceiro_id, trabalhador_id, tipo, nome, data_validade)
  VALUES (public.qa_sandbox_tenant_id(), p_terceiro, p_trabalhador, p_tipo, p_nome, p_validade)
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_novo_documento(p_nome text, p_pasta uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.documentos
    (tenant_id, colaborador_nome, nome_arquivo, nome_original, tipo, tamanho, mime_type, storage_path, pasta_id)
  VALUES (public.qa_sandbox_tenant_id(), '[QA] Colaborador', p_nome, p_nome, 'pdf', 1024,
          'application/pdf', 'qa/'||p_nome, p_pasta) RETURNING id INTO v_id;
  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_novo_hub_processo(p_titulo text, p_tipo hub_processo_tipo DEFAULT 'admissao'::hub_processo_tipo)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.hub_processos (tenant_id, tipo, titulo)
  VALUES (public.qa_sandbox_tenant_id(), p_tipo, p_titulo)
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_novo_no_org(p_titulo text, p_parent uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.estrategia_organograma (tenant_id, titulo, parent_id)
  VALUES (public.qa_sandbox_tenant_id(), p_titulo, p_parent) RETURNING id INTO v_id;
  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_novo_oceano(p_titulo text, p_swot uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.estrategia_oceano_azul (tenant_id, titulo, swot_id)
  VALUES (public.qa_sandbox_tenant_id(), p_titulo, p_swot) RETURNING id INTO v_id;
  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_novo_terceiro(p_razao text, p_cnpj text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.terceiros (tenant_id, razao_social, cnpj)
  VALUES (public.qa_sandbox_tenant_id(), p_razao, p_cnpj) RETURNING id INTO v_id;
  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_obrigacao_existe(p_empresa uuid, p_subcategoria text)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE v_existe boolean;
BEGIN
  SELECT EXISTS(
    SELECT 1 FROM public.empresa_obrigacoes
     WHERE tenant_id    = public.qa_sandbox_tenant_id()
       AND empresa_id   = p_empresa          -- <— o parametro passa a valer
       AND subcategoria = p_subcategoria
       AND origem       = 'cadastro_empresa'
  ) INTO v_existe;
  RETURN v_existe;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_pgp_cenario(OUT o_parceiro uuid, OUT o_impl uuid, OUT o_tenant_pub uuid)
 RETURNS record
 LANGUAGE plpgsql
AS $function$
DECLARE v_plano uuid; v_uid uuid := gen_random_uuid();
BEGIN
  PERFORM public.qa_modo_ligar();
  o_tenant_pub := public.qa_sandbox_tenant_id();
  IF o_tenant_pub IS NULL THEN RAISE EXCEPTION 'Cercado qa-sandbox não existe neste ambiente'; END IF;
  INSERT INTO public.parceiros (codigo, nome, tipo_parceiro, trilha, status) VALUES ('QA-PGP-ORIG', 'QA Origem', 'representante', 'representante', 'ativo') RETURNING id INTO o_parceiro;
  INSERT INTO public.parceiros (codigo, nome, tipo_parceiro, trilha, status) VALUES ('QA-PGP-IMPL', 'QA Operador', 'implantador', 'operador', 'ativo') RETURNING id INTO o_impl;
  SELECT id INTO v_plano FROM public.plans WHERE code = 'performance';
  UPDATE public.tenants SET parceiro_id = o_parceiro, implantador_parceiro_id = o_impl, originado_em = now() - interval '90 days', ativo = true WHERE id = o_tenant_pub;
  INSERT INTO public.subscriptions (tenant_id, plan_id, status) VALUES (o_tenant_pub, v_plano, 'active')
  ON CONFLICT (tenant_id) DO UPDATE SET plan_id = EXCLUDED.plan_id, status = 'active';
  UPDATE public.subscriptions SET setup_valor_cents = 120000, contrato_assinado_em = CURRENT_DATE - 60,
    primeira_mensalidade_compensada_em = CURRENT_DATE - 50, go_live_homologado_em = CURRENT_DATE - 45,
    terceira_mensalidade_compensada_em = NULL, cancelado_em = NULL, ciclo_inicio = NULL, ciclo_fim = NULL, desconto_pct = 0
  WHERE tenant_id = o_tenant_pub;
  INSERT INTO auth.users (id, email) VALUES (v_uid, 'qa-pgp-' || left(v_uid::text,8) || '@exemplo.test');
  INSERT INTO public.profiles (user_id, tenant_id, nome_completo, onboarding_concluido) VALUES (v_uid, o_tenant_pub, 'QA Owner', true);
  DELETE FROM public.parceiro_comissoes WHERE tenant_id = o_tenant_pub;
  DELETE FROM public.parceiro_mrr_snapshots WHERE tenant_id = o_tenant_pub;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_ponto_admissao(p_nome text, p_cpf_semente integer, p_empresa_id uuid DEFAULT NULL::uuid, p_data_admissao date DEFAULT (CURRENT_DATE - 60))
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_t   uuid := public.qa_sandbox_tenant_id();
  v_cpf text := public.qa_cpf(p_cpf_semente);
  v_id  uuid;
BEGIN
  -- Reaproveita a admissao do cercado com o mesmo CPF, se ela ja existe.
  SELECT a.id INTO v_id
  FROM public.admissoes a
  WHERE a.tenant_id = v_t AND a.cpf = v_cpf
  ORDER BY (a.status = 'concluido') DESC, a.created_at NULLS LAST
  LIMIT 1;

  IF v_id IS NOT NULL THEN
    UPDATE public.admissoes
       SET nome_completo = p_nome,
           status        = 'concluido',
           data_admissao = p_data_admissao,
           empresa_id    = COALESCE(p_empresa_id, empresa_id)
     WHERE id = v_id;
    RETURN v_cpf;
  END IF;

  INSERT INTO public.admissoes
    (tenant_id, nome_completo, cpf, email, cargo, status, data_admissao, empresa_id)
  VALUES (v_t, p_nome, v_cpf,
          public.qa_fixture_email('PONTO-AGO', p_cpf_semente),
          'Operador', 'concluido', p_data_admissao, p_empresa_id);
  RETURN v_cpf;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_ponto_dia(p_cpf text, p_nome text, p_data date, p_empresa_id uuid DEFAULT NULL::uuid, p_status text DEFAULT 'regular'::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  INSERT INTO public.ponto_diario
    (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
     data, entrada, saida_almoco, retorno_almoco, saida, horas_trabalhadas, status)
  VALUES (public.qa_sandbox_tenant_id(), p_empresa_id, gen_random_uuid(), p_nome, p_cpf,
          p_data, TIME '08:00', TIME '12:00', TIME '13:00', TIME '17:00',
          INTERVAL '8 hours', p_status);
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_ponto_dia_horarios(p_cpf text, p_nome text, p_data date, p_entrada time without time zone, p_saida time without time zone, p_salm time without time zone DEFAULT NULL::time without time zone, p_ralm time without time zone DEFAULT NULL::time without time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_t uuid := public.qa_sandbox_tenant_id();
  v_id uuid; v_colab uuid; v_min int;
BEGIN
  v_min := floor(EXTRACT(EPOCH FROM (p_saida - p_entrada))/60)::int;
  IF v_min < 0 THEN v_min := v_min + 1440; END IF;
  IF p_salm IS NOT NULL AND p_ralm IS NOT NULL THEN
    v_min := v_min - floor(EXTRACT(EPOCH FROM (p_ralm - p_salm))/60)::int;
  END IF;

  SELECT d.id, d.colaborador_id INTO v_id, v_colab
  FROM public.ponto_diario d
  WHERE d.tenant_id = v_t AND d.colaborador_cpf = p_cpf AND d.data = p_data
  ORDER BY d.created_at NULLS LAST
  LIMIT 1;

  IF v_id IS NOT NULL THEN
    UPDATE public.ponto_diario
       SET entrada = p_entrada, saida = p_saida,
           saida_almoco = p_salm, retorno_almoco = p_ralm,
           horas_trabalhadas = make_interval(mins => v_min)
     WHERE id = v_id;
    RETURN coalesce(v_colab, gen_random_uuid());
  END IF;

  v_colab := gen_random_uuid();
  INSERT INTO public.ponto_diario
    (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf, data,
     entrada, saida_almoco, retorno_almoco, saida, horas_trabalhadas, status)
  VALUES (v_t, v_colab, p_nome, p_cpf, p_data,
          p_entrada, p_salm, p_ralm, p_saida, make_interval(mins => v_min), 'regular');
  RETURN v_colab;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_ponto_dia_min(p_cpf text, p_nome text, p_data date, p_minutos integer)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE v_t uuid := public.qa_sandbox_tenant_id(); v_id uuid;
BEGIN
  -- Atualiza a linha do dia se ela existir; senão, insere. Vale tanto na
  -- chave nova (com empresa) quanto na antiga (sem), porque não nomeia
  -- índice nenhum.
  SELECT d.id INTO v_id
  FROM public.ponto_diario d
  WHERE d.tenant_id = v_t AND d.colaborador_cpf = p_cpf AND d.data = p_data
  ORDER BY d.created_at NULLS LAST
  LIMIT 1;

  IF v_id IS NOT NULL THEN
    UPDATE public.ponto_diario
       SET horas_trabalhadas = make_interval(mins => p_minutos),
           saida = TIME '08:00' + make_interval(mins => p_minutos)
     WHERE id = v_id;
  ELSE
    INSERT INTO public.ponto_diario
      (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
       data, entrada, saida, horas_trabalhadas, status)
    VALUES (v_t, gen_random_uuid(), p_nome, p_cpf,
            p_data, TIME '08:00', TIME '08:00' + make_interval(mins => p_minutos),
            make_interval(mins => p_minutos), 'regular');
  END IF;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_ponto_escala_tol(p_cpf text, p_nome text, p_jornada_min integer, p_tol_min integer, p_data_inicio date, p_data_fim date)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.ponto_escalas
    (tenant_id, nome, tipo, modalidade, jornada_diaria_minutos,
     jornada_semanal_minutos, intervalo_intrajornada_minutos,
     tolerancia_minutos, tolerancia_diaria_minutos,
     hora_entrada_padrao, hora_saida_padrao,
     equalizacao_mensal_ativa, carga_semanal_contratada_min, ativa)
  VALUES (public.qa_sandbox_tenant_id(), 'QA escala ' || p_cpf, 'fixa', 'fixa',
          p_jornada_min, p_jornada_min * 5, 60,
          LEAST(p_tol_min, 5), p_tol_min,
          TIME '08:00', TIME '17:00',
          false, p_jornada_min * 5, true)
  RETURNING id INTO v_id;

  INSERT INTO public.ponto_escala_atribuicoes
    (tenant_id, escala_id, colaborador_id, colaborador_nome, colaborador_cpf,
     data_inicio, data_fim, ativa)
  VALUES (public.qa_sandbox_tenant_id(), v_id, p_cpf, p_nome, p_cpf,
          p_data_inicio, p_data_fim, true);
  RETURN v_id;
END;
$function$

;

CREATE OR REPLACE FUNCTION public.qa_ponto_marca(p_cpf text, p_nome text, p_data date, p_hora time without time zone, p_tipo text, p_original boolean DEFAULT true)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.ponto_marcacoes
    (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
     data_marcacao, hora_marcacao, tipo_marcacao,
     hash_marcacao, marcacao_original, origem_marcacao)
  VALUES (public.qa_sandbox_tenant_id(), gen_random_uuid(), p_nome, p_cpf,
          p_data, p_hora, p_tipo,
          'qa-seed', p_original, CASE WHEN p_original THEN 'O' ELSE 'A' END);
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_registrar_bateria_e2e(p_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_exec       uuid;
  v_item       jsonb;
  v_codigo     text;
  v_caso       uuid;
  v_situacao   public.qa_situacao;
  v_sem_caso   int := 0;
  v_gravados   int := 0;
  v_total      int;
BEGIN
  IF p_payload IS NULL OR jsonb_typeof(p_payload->'resultados') <> 'array' THEN
    RAISE EXCEPTION 'Payload invalido: esperava { "resultados": [...] }.';
  END IF;

  v_total := jsonb_array_length(p_payload->'resultados');

  INSERT INTO public.qa_execucoes (disparo, modulo_path, terminada_em)
  VALUES ('e2e', 'cypress', now())
  RETURNING id INTO v_exec;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_payload->'resultados')
  LOOP
    v_situacao := CASE lower(COALESCE(v_item->>'situacao', ''))
                    WHEN 'passou' THEN 'passou'
                    WHEN 'falhou' THEN 'falhou'
                    WHEN 'pulado' THEN 'nao_implementado'
                    ELSE 'erro'
                  END::public.qa_situacao;

    SELECT e.codigo INTO v_codigo
    FROM public.qa_cobertura_e2e e
    WHERE e.ativo
      AND e.spec  = v_item->>'spec'
      AND e.teste = v_item->>'teste';

    IF v_codigo IS NULL THEN
      v_sem_caso := v_sem_caso + 1;
      CONTINUE;
    END IF;

    SELECT c.id INTO v_caso FROM public.qa_casos_teste c WHERE c.codigo = v_codigo;

    INSERT INTO public.qa_resultados
      (execucao_id, caso_id, codigo, situacao, passo_acao, esperado, obtido,
       erro_tecnico, duracao_ms, evidencia_png)
    VALUES
      (v_exec, v_caso, v_codigo, v_situacao,
       v_item->>'teste',
       'Teste de tela em ' || COALESCE(v_item->>'spec', '(spec desconhecido)'),
       CASE v_situacao
         WHEN 'passou' THEN 'A tela se comportou como o caso descreve.'
         WHEN 'nao_implementado' THEN 'O teste existe mas nao rodou nesta corrida.'
         ELSE 'A tela fez diferente do que o caso descreve.'
       END,
       NULLIF(v_item->>'erro', ''),
       NULLIF(v_item->>'duracao_ms', '')::int,
       NULLIF(v_item->>'evidencia_png', ''))
    ON CONFLICT (execucao_id, codigo) DO NOTHING;

    v_gravados := v_gravados + 1;
    v_codigo := NULL;
  END LOOP;

  UPDATE public.qa_execucoes e SET
    total            = (SELECT count(*) FROM public.qa_resultados WHERE execucao_id = v_exec),
    passou           = (SELECT count(*) FROM public.qa_resultados WHERE execucao_id = v_exec AND situacao = 'passou'),
    falhou           = (SELECT count(*) FROM public.qa_resultados WHERE execucao_id = v_exec AND situacao = 'falhou'),
    nao_implementado = (SELECT count(*) FROM public.qa_resultados WHERE execucao_id = v_exec AND situacao = 'nao_implementado'),
    erro             = (SELECT count(*) FROM public.qa_resultados WHERE execucao_id = v_exec AND situacao = 'erro'),
    observacao       = 'Corrida do Cypress (origem: '
                       || COALESCE(p_payload->>'origem', 'nao informada') || '). '
                       || v_total || ' teste(s) na suite, ' || v_gravados || ' ligado(s) a caso'
                       || CASE WHEN v_sem_caso > 0
                               THEN '. >>> ' || v_sem_caso || ' teste(s) de tela SEM caso documentado '
                                 || '(rodaram, mas nao aparecem no relatorio: falta linha em qa_cobertura_e2e).'
                               ELSE '. Todos os testes tem caso documentado.' END
  WHERE e.id = v_exec;

  RETURN v_exec;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_relatorio_falhas(p_modulo text DEFAULT NULL::text)
 RETURNS TABLE(codigo text, prio text, disposicao text, situacao text, achado text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT r.codigo,
         left(ct.prioridade::text, 4),
         CASE ct.disposicao
           WHEN 'em_triagem'            THEN '>>> NOVO'
           WHEN 'bug_confirmado'        THEN 'bug'
           WHEN 'aguardando_construcao' THEN 'a construir'
           WHEN 'decisao_de_produto'    THEN 'decidido'
           WHEN 'fora_de_escopo'        THEN 'fora escopo'
           WHEN 'comportamento_correto' THEN 'caso errado'
           ELSE ct.disposicao END,
         left(r.situacao::text, 6),
         left(regexp_replace(COALESCE(r.obtido,''), '\s+', ' ', 'g'), 100)
  FROM public.qa_resultados r
  JOIN public.qa_casos_teste ct ON ct.codigo = r.codigo
  WHERE r.execucao_id = (
          SELECT e.id FROM public.qa_execucoes e
          WHERE p_modulo IS NULL OR e.modulo_path = p_modulo
          ORDER BY e.iniciada_em DESC LIMIT 1)
    AND r.situacao IN ('falhou','erro')
  ORDER BY (ct.disposicao <> 'em_triagem'),   -- o que ainda não foi triado vem primeiro
           CASE ct.prioridade WHEN 'critica' THEN 1 WHEN 'alta' THEN 2
                              WHEN 'media' THEN 3 ELSE 4 END,
           r.codigo;
$function$

;

CREATE OR REPLACE FUNCTION public.qa_resultados_da_bateria(p_execucao_id uuid)
 RETURNS TABLE(codigo text, situacao text, passo_ordem integer, passo_acao text, esperado text, obtido text, erro_tecnico text, duracao_ms integer, titulo text, objetivo text, pre_condicoes text, passos jsonb, resultado_esperado text, observacoes text, evidencia_png text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT r.codigo, r.situacao::text, r.passo_ordem, r.passo_acao,
         r.esperado, r.obtido, r.erro_tecnico, r.duracao_ms,
         c.titulo, c.objetivo, c.pre_condicoes,
         c.passos, c.resultado_esperado, c.observacoes,
         r.evidencia_png
  FROM public.qa_resultados r
  LEFT JOIN public.qa_casos_teste c ON c.codigo = r.codigo
  WHERE r.execucao_id = p_execucao_id
    AND public.is_superadmin(auth.uid())
  ORDER BY
    CASE r.situacao WHEN 'falhou' THEN 0 WHEN 'erro' THEN 1
                    WHEN 'passou' THEN 2 ELSE 3 END,
    r.codigo;
$function$

;

CREATE OR REPLACE FUNCTION public.qa_rodar_agendada()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_modulo text;
BEGIN
  SELECT modulo_path INTO v_modulo FROM public.qa_agendamento WHERE id = 1;
  -- disparo 'agendado', sem disparada_por (nao foi ninguem, foi o relogio)
  PERFORM public.qa_rodar_bateria('agendado', v_modulo);
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_rodar_bateria(p_disparo qa_disparo DEFAULT 'manual'::qa_disparo, p_modulo text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET statement_timeout TO '120s'
AS $function$
DECLARE
  v_exec uuid;
  v_t0   timestamptz := clock_timestamp();
  c      record;
  r      public.qa_retorno;
  v_ini  timestamptz;
  v_vaz  int;
  v_todos boolean := (p_modulo IS NULL OR btrim(p_modulo) = '');
BEGIN
  IF public.qa_sandbox_tenant_id() IS NULL THEN
    RAISE EXCEPTION 'Cercado nao existe. Bateria abortada.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'qa_guarda_cercado' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'A trava do cercado nao esta instalada. Bateria abortada por seguranca.';
  END IF;

  PERFORM public.qa_modo_ligar();
  PERFORM public.qa_exigir_modo();

  INSERT INTO public.qa_execucoes (disparo, modulo_path)
  VALUES (p_disparo, CASE WHEN v_todos THEN 'todos' ELSE p_modulo END)
  RETURNING id INTO v_exec;

  FOR c IN
    SELECT ct.id AS caso_id, ct.codigo, ct.titulo, ct.nivel, i.funcao_sql
    FROM public.qa_casos_teste ct
    JOIN public.qa_modulos m ON m.id = ct.modulo_id
    LEFT JOIN public.qa_implementacoes i ON i.codigo = ct.codigo AND i.ativo
    WHERE ct.status = 'aprovado'
      AND (v_todos OR m.path = p_modulo)
    ORDER BY ct.codigo
  LOOP
    v_ini := clock_timestamp();

    IF c.funcao_sql IS NULL THEN
      INSERT INTO public.qa_resultados
        (execucao_id, caso_id, codigo, situacao, esperado, obtido, duracao_ms)
      VALUES (v_exec, c.caso_id, c.codigo, 'nao_implementado', c.titulo,
              CASE WHEN c.nivel = 'e2e'
                   THEN 'Caso de TELA (e2e). Nao roda no motor SQL por natureza — '
                     || 'depende de navegador, clique e latencia. A cobertura dele '
                     || 'vive no Cypress (pasta cypress/e2e). Este resultado nao e '
                     || 'divida do motor.'
                   ELSE 'Caso documentado e aprovado. Nenhuma rotina foi escrita para executa-lo.'
              END, 0);
    ELSE
      r := public.qa_executar_descartavel(c.funcao_sql);
      INSERT INTO public.qa_resultados
        (execucao_id, caso_id, codigo, situacao, passo_ordem, passo_acao,
         esperado, obtido, erro_tecnico, detalhe, duracao_ms)
      VALUES (v_exec, c.caso_id, c.codigo, r.situacao, r.passo_ordem, r.passo_acao,
              r.esperado, r.obtido, r.erro_tecnico, r.detalhe,
              extract(milliseconds from clock_timestamp() - v_ini)::int);
    END IF;
  END LOOP;

  SELECT count(*) INTO v_vaz FROM public.qa_verifica_vazamento()
  WHERE veredito NOT IN ('limpo','ok');

  UPDATE public.qa_execucoes e SET
    terminada_em     = now(),
    duracao_ms       = extract(milliseconds from clock_timestamp() - v_t0)::int,
    total            = (SELECT count(*) FROM public.qa_resultados WHERE execucao_id = v_exec),
    passou           = (SELECT count(*) FROM public.qa_resultados WHERE execucao_id = v_exec AND situacao='passou'),
    falhou           = (SELECT count(*) FROM public.qa_resultados WHERE execucao_id = v_exec AND situacao='falhou'),
    nao_implementado = (SELECT count(*) FROM public.qa_resultados WHERE execucao_id = v_exec AND situacao='nao_implementado'),
    erro             = (SELECT count(*) FROM public.qa_resultados WHERE execucao_id = v_exec AND situacao='erro'),
    observacao       = CASE WHEN v_vaz > 0
                            THEN '>>> VAZAMENTO: sobrou dado de teste no cercado.'
                            ELSE 'Cercado limpo ao final.' END
  WHERE e.id = v_exec;

  PERFORM public.qa_limpar_historico(90);
  RETURN v_exec;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_sandbox2_tenant_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE
AS $function$
  SELECT id FROM public.tenants WHERE slug = 'qa-sandbox-2'
$function$

;

CREATE OR REPLACE FUNCTION public.qa_sandbox_tenant_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ SELECT id FROM public.tenants WHERE slug = 'qa-sandbox' $function$

;

CREATE OR REPLACE FUNCTION public.qa_um_usuario()
 RETURNS uuid
 LANGUAGE sql
 STABLE
AS $function$
  SELECT id FROM auth.users ORDER BY created_at LIMIT 1
$function$

;

CREATE OR REPLACE FUNCTION public.qa_up_decisao_le_excecoes()
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f'
      AND p.proname NOT LIKE 'qa\_%'
      AND pg_get_functiondef(p.oid) ILIKE '%perfil_excecoes%'
  )
$function$

;

CREATE OR REPLACE FUNCTION public.qa_up_entrar(p_uid uuid)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', p_uid, 'role', 'authenticated')::text,
                     true);
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_up_outro_tenant()
 RETURNS uuid
 LANGUAGE sql
 STABLE
AS $function$
  SELECT t.id FROM public.tenants t
  WHERE t.id <> public.qa_sandbox_tenant_id()
    AND EXISTS (SELECT 1 FROM public.usuarios_base u WHERE u.tenant_id = t.id)
  ORDER BY t.created_at NULLS LAST
  LIMIT 1
$function$

;

CREATE OR REPLACE FUNCTION public.qa_up_perfil(p_codigo text, p_sufixo text, p_modulo text, p_escopo text DEFAULT 'empresa_inteira'::text, p_acao text DEFAULT 'visualizar'::text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_t uuid := public.qa_sandbox_tenant_id(); v_id uuid;
BEGIN
  INSERT INTO public.perfis_acesso (tenant_id, nome, descricao, tipo, ativo)
  VALUES (v_t, '[QA-' || p_codigo || '] ' || p_sufixo,
          'Perfil sintético do motor de QA.', 'personalizado', true)
  RETURNING id INTO v_id;

  INSERT INTO public.perfil_permissoes (perfil_id, tenant_id, modulo, acao, escopo, ativo)
  VALUES (v_id, v_t, p_modulo, p_acao::public.perfil_acao,
          p_escopo::public.perfil_escopo_tipo, true);

  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_up_pode_virar_usuario()
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
BEGIN
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
  EXCEPTION WHEN OTHERS THEN
    RETURN false;
  END;
  EXECUTE 'RESET ROLE';
  RETURN true;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_up_sair()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  PERFORM set_config('request.jwt.claims', '{}', true);
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_up_tem_empresa_ativa()
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f'
      AND p.proname NOT LIKE 'qa\_%'
      AND (p.proname ~* 'empresa_ativa'
           OR pg_get_functiondef(p.oid) ~* '(empresa_ativa|request\.jwt\.claims.*empresa)')
  )
$function$

;

CREATE OR REPLACE FUNCTION public.qa_up_tem_identidade(p_auth_uid uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT EXISTS (SELECT 1 FROM public.profiles WHERE user_id = p_auth_uid)
$function$

;

CREATE OR REPLACE FUNCTION public.qa_up_usuario(p_codigo text, p_n integer, p_cpf text, p_status text DEFAULT 'ativo'::text, p_auth_uid uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_t uuid := public.qa_sandbox_tenant_id(); v_id uuid; v_auth uuid;
BEGIN
  INSERT INTO public.usuarios_base
    (tenant_id, nome_completo, email_principal, cpf, tipo_usuario, status, auth_user_id)
  VALUES (v_t, '[QA-' || p_codigo || '] Usuario ' || p_n,
          public.qa_fixture_email(p_codigo, p_n), p_cpf,
          'colaborador', p_status::public.usuario_status,
          COALESCE(p_auth_uid, gen_random_uuid()))
  RETURNING id INTO v_id;

  -- Desarma o vínculo automático do perfil padrão: o cenário tem que ser
  -- exatamente o que a rotina declara, nem um vínculo a mais.
  DELETE FROM public.usuario_perfil_vinculos WHERE usuario_id = v_id;

  -- O sistema identifica o usuário por DOIS caminhos, e a fixture precisa dos
  -- dois para ser um usuário de verdade:
  --   · a decisão de PERMISSÃO acha a pessoa por usuarios_base.auth_user_id;
  --   · o ISOLAMENTO acha o cliente dela por profiles.user_id (é o que
  --     get_user_tenant_id() consulta, e é nele que as políticas se apoiam).
  -- Sem a linha em profiles, o usuário sintético não enxerga nem o próprio
  -- cliente, e as rotinas de isolamento mediriam a falta da fixture em vez de
  -- medir o isolamento. profiles.user_id tem chave estrangeira para auth.users,
  -- então a identidade de autenticação também precisa existir.
  SELECT auth_user_id INTO v_auth FROM public.usuarios_base WHERE id = v_id;

  BEGIN
    INSERT INTO auth.users (id, email) VALUES (v_auth, public.qa_fixture_email(p_codigo, p_n))
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.profiles (user_id, tenant_id, nome_completo)
    VALUES (v_auth, v_t, '[QA-' || p_codigo || '] Usuario ' || p_n)
    ON CONFLICT (user_id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN
    -- Ambiente onde o motor não pode escrever na identidade de autenticação.
    -- Não é motivo para abortar: as rotinas que dependem disso conferem com
    -- qa_up_tem_identidade() e dizem o que faltou, em vez de dar veredito.
    RAISE NOTICE 'QA Usuários & Permissões: identidade completa não criada para %: %', v_id, SQLERRM;
  END;

  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_up_usuario_isolado(p_codigo text, p_cpf text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_u uuid; v_p uuid; v_uid uuid;
BEGIN
  PERFORM public.qa_fixture_limpar(p_codigo);
  v_u := public.qa_up_usuario(p_codigo, 1, p_cpf, 'ativo');
  v_p := public.qa_up_perfil(p_codigo, 'Amplo', 'ponto', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_p);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;
  IF NOT public.qa_up_tem_identidade(v_uid) THEN
    RETURN NULL;
  END IF;
  RETURN v_uid;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_up_vincular(p_usuario uuid, p_empresa uuid, p_perfil uuid, p_ativo boolean DEFAULT true, p_expira timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_t uuid := public.qa_sandbox_tenant_id(); v_id uuid;
BEGIN
  INSERT INTO public.usuario_perfil_vinculos
    (tenant_id, usuario_id, empresa_id, perfil_id, ativo, expira_em)
  VALUES (v_t, p_usuario, p_empresa, p_perfil, p_ativo, p_expira)
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_verifica_contaminacao(p_execucao_id uuid)
 RETURNS TABLE(tabela text, linhas_fora_do_cercado bigint)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_ini timestamptz;
  v_fim timestamptz;
  v_sandbox uuid;
  t record;
  n bigint;
BEGIN
  SELECT iniciada_em, COALESCE(terminada_em, now())
    INTO v_ini, v_fim
  FROM public.qa_execucoes WHERE id = p_execucao_id;

  IF v_ini IS NULL THEN
    RAISE EXCEPTION 'Execucao % nao encontrada.', p_execucao_id;
  END IF;

  v_sandbox := public.qa_sandbox_tenant_id();

  FOR t IN SELECT qtp.tabela FROM public.qa_tabelas_protegidas qtp LOOP
    EXECUTE format(
      'SELECT count(*) FROM public.%I
        WHERE created_at >= $1 AND created_at <= $2 AND tenant_id IS DISTINCT FROM $3',
      t.tabela)
    INTO n USING v_ini, v_fim, v_sandbox;

    IF n > 0 THEN
      tabela := t.tabela;
      linhas_fora_do_cercado := n;
      RETURN NEXT;
    END IF;
  END LOOP;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_verifica_vazamento()
 RETURNS TABLE(o_que text, encontrado bigint, esperado bigint, veredito text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_t         uuid := public.qa_sandbox_tenant_id();
  c           record;
  v_n         bigint;
  v_esperado  bigint;
  v_varridas  int := 0;
  v_problemas int := 0;
  v_pulos     int := 0;
  v_base      int;
BEGIN
  IF v_t IS NULL THEN
    RETURN QUERY SELECT 'cercado'::text, 0::bigint, 0::bigint,
      '>>> o cercado nao existe'::text;
    RETURN;
  END IF;

  SELECT count(*) INTO v_base FROM public.qa_mobiliario_fixo;
  IF v_base = 0 THEN
    RETURN QUERY SELECT 'linha de base'::text, 0::bigint, 0::bigint,
      '>>> sem linha de base — rode qa_mobiliario_registrar() com o cercado limpo'::text;
    RETURN;
  END IF;

  CREATE TEMP TABLE IF NOT EXISTS qa_vaz_tmp
    (o_que text, encontrado bigint, esperado bigint, veredito text) ON COMMIT DROP;

  -- WHERE true: o safeupdate do Supabase recusa DELETE sem WHERE nos papeis
  -- da API. Apagar tudo aqui e intencional — a tabela e temporaria e serve
  -- so para acumular o resultado desta chamada.
  DELETE FROM qa_vaz_tmp WHERE true;

  FOR c IN
    SELECT col.table_name
    FROM information_schema.columns col
    JOIN information_schema.tables t
      ON t.table_schema = col.table_schema AND t.table_name = col.table_name
    WHERE col.table_schema = 'public'
      AND col.column_name  = 'tenant_id'
      AND t.table_type     = 'BASE TABLE'
      AND col.table_name NOT LIKE 'qa\_%'
    ORDER BY col.table_name
  LOOP
    BEGIN
      EXECUTE format('SELECT count(*) FROM public.%I WHERE tenant_id = $1', c.table_name)
        INTO v_n USING v_t;
      v_varridas := v_varridas + 1;
    EXCEPTION WHEN OTHERS THEN
      v_pulos := v_pulos + 1;
      CONTINUE;
    END;

    SELECT m.esperado INTO v_esperado
    FROM public.qa_mobiliario_fixo m WHERE m.tabela = c.table_name;
    v_esperado := COALESCE(v_esperado, 0);

    IF v_n <> v_esperado THEN
      v_problemas := v_problemas + 1;
      INSERT INTO qa_vaz_tmp VALUES (
        c.table_name, v_n, v_esperado,
        CASE
          WHEN v_esperado = 0    THEN '>>> VAZOU'
          WHEN v_n > v_esperado  THEN '>>> SOBROU'
          ELSE                        '>>> FALTA'
        END);
    END IF;
  END LOOP;

  IF v_problemas = 0 THEN
    RETURN QUERY SELECT
      format('%s tabelas varridas%s', v_varridas,
             CASE WHEN v_pulos > 0
                  THEN format(', %s sem permissao de leitura', v_pulos)
                  ELSE '' END)::text,
      0::bigint, 0::bigint, 'limpo'::text;
  ELSE
    RETURN QUERY SELECT
      format('%s tabelas varridas, %s com problema', v_varridas, v_problemas)::text,
      v_problemas::bigint, 0::bigint, '>>> VAZOU'::text;
    RETURN QUERY SELECT * FROM qa_vaz_tmp ORDER BY 1;
  END IF;
END $function$

;

-- Conferencia: as 10 rotinas de Ponto que falhavam pela trava/apoio antigo ────
WITH alvo(codigo) AS (VALUES
  ('PONTO-131'),('PONTO-300'),('PONTO-301'),('PONTO-310'),('PONTO-311'),
  ('PONTO-320'),('PONTO-321'),('PONTO-322'),('PONTO-330'),('PONTO-394'))
SELECT (public.qa_executar_descartavel(i.funcao_sql)).situacao::text AS situacao, count(*) AS qtd
FROM alvo a JOIN public.qa_implementacoes i ON i.codigo=a.codigo GROUP BY 1 ORDER BY 2 DESC;
