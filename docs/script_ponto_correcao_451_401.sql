-- ============================================================================
-- ENTREGA — PONTO-451 (aviso repetido nao derruba o afastamento) e
--           PONTO-401 (sonda mede o arredondamento em vez de procurar palavra)
--
-- COMO USAR
-- Cole o arquivo INTEIRO no SQL Editor do ambiente e execute uma vez. Pode
-- ser executado de novo sem risco: tudo aqui e CREATE OR REPLACE, nao altera
-- nem apaga dado existente (por isso nao ha copia de seguranca a fazer).
--
-- O QUE ESTE ARQUIVO FAZ
-- 1) Alerta de atestado sobreposto: gravado so quando ainda nao existe o
--    mesmo aviso em aberto (mesmo CPF, mesmo tipo, mesma data de referencia).
-- 2) Encaminhamento ao INSS: o alerta ganha bloco proprio. Hoje, se o aviso
--    repetido bate no indice de deduplicacao, a excecao desfaz junto o
--    afastamento previdenciario do 16o dia (Lei 8.213, arts. 59-60) e ate o
--    proprio atestado e recusado. Depois desta entrega, o afastamento fica.
-- 3) Sondas PONTO-451 e PONTO-401 passam a exercitar comportamento no cercado
--    de testes, em vez de auditar o texto das rotinas.
--
-- Ao final sai UMA conferencia. Ela le o ambiente: onde uma peca nao existir,
-- diz isso em vez de reprovar.
-- ============================================================================

SET lock_timeout = '10s';


CREATE OR REPLACE FUNCTION public.ponto_atestado_detectar_sobreposicao()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_prev RECORD;
  v_ini  date;
  v_fim  date;
BEGIN
  -- Deteccao de sobreposicao de periodos de atestado por CPF (nao bloqueia).
  IF NEW.data_inicio_afastamento IS NULL OR NEW.colaborador_cpf IS NULL THEN
    RETURN NEW;
  END IF;

  v_ini := NEW.data_inicio_afastamento;
  v_fim := COALESCE(NEW.data_fim_afastamento, NEW.data_inicio_afastamento);

  -- Procura um atestado JA registrado do mesmo colaborador cujo periodo se
  -- sobrepoe ao novo (intervalos se cruzam: inicio_a <= fim_b E fim_a >= inicio_b).
  SELECT a.id, a.data_inicio_afastamento AS di, a.data_fim_afastamento AS df
    INTO v_prev
  FROM public.atestados a
  WHERE a.tenant_id = NEW.tenant_id
    AND a.colaborador_cpf = NEW.colaborador_cpf
    AND (NEW.id IS NULL OR a.id <> NEW.id)
    AND a.data_inicio_afastamento IS NOT NULL
    AND a.data_inicio_afastamento <= v_fim
    AND COALESCE(a.data_fim_afastamento, a.data_inicio_afastamento) >= v_ini
  ORDER BY a.data_inicio_afastamento DESC
  LIMIT 1;

  IF FOUND THEN
    BEGIN
      -- Um aviso por ocorrencia: mesmo tenant, mesmo CPF, mesmo tipo e mesma
      -- data de referencia, enquanto ninguem resolveu. Rodar a vigilancia de
      -- novo nao empilha copias do mesmo aviso.
      INSERT INTO public.ponto_alertas
        (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
         tipo, severidade, titulo, descricao, data_referencia)
      SELECT
        NEW.tenant_id, NEW.empresa_id, NEW.colaborador_id, NEW.colaborador_nome, NEW.colaborador_cpf,
        'atestado_sobreposto', 'media',
        'Atestados com periodos sobrepostos',
        format('O atestado novo (%s a %s) se sobrepoe a um atestado ja registrado (%s a %s) do mesmo '
            || 'colaborador. Confira se e reenvio/duplicidade ou dois atendimentos: o DP decide qual '
            || 'vale, mantendo o tratamento mais favoravel, e os dias em comum contam UMA vez (nao '
            || 'abona em dobro nem infla a contagem dos 15 dias).',
            v_ini, v_fim, v_prev.di, COALESCE(v_prev.df, v_prev.di)),
        v_ini
      WHERE NOT EXISTS (
        SELECT 1 FROM public.ponto_alertas al
        WHERE al.tenant_id = NEW.tenant_id
          AND al.colaborador_cpf = NEW.colaborador_cpf
          AND al.tipo = 'atestado_sobreposto'
          AND al.data_referencia = v_ini
          AND COALESCE(al.resolvido, false) = false
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Nao foi possivel registrar o alerta de atestado sobreposto (%). O atestado foi registrado.', SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ponto_atestado_encaminhar_afastamento()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_dias   integer;
  v_dia16  date;
  v_afast  uuid;
BEGIN
  -- Só faz a ponte quando o atestado ainda não tem afastamento vinculado.
  IF NEW.afastamento_id IS NOT NULL OR NEW.data_inicio_afastamento IS NULL THEN
    RETURN NEW;
  END IF;

  v_dias := COALESCE(NEW.dias_afastamento,
                     (NEW.data_fim_afastamento - NEW.data_inicio_afastamento + 1),
                     0);

  -- Até 15 dias: abono da empresa; nada a encaminhar.
  IF v_dias <= 15 THEN
    RETURN NEW;
  END IF;

  v_dia16 := NEW.data_inicio_afastamento + 15;  -- 16º dia: início do benefício INSS

  BEGIN
    INSERT INTO public.afastamentos
      (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
       data_inicio, data_fim, data_atestado, status, tipo_principal_new, observacoes)
    VALUES
      (NEW.tenant_id, NEW.empresa_id, NEW.colaborador_id, NEW.colaborador_nome, NEW.colaborador_cpf,
       v_dia16, NEW.data_fim_afastamento, NEW.data_emissao, 'beneficio_inss', 'beneficio_b31',
       'Encaminhamento previdenciario automatico — atestado acima de 15 dias (Lei 8.213, arts. 59-60). '
       || 'Empresa abona os primeiros 15 dias; do 16o dia em diante e beneficio do INSS (auxilio-doenca B31).')
    RETURNING id INTO v_afast;

    NEW.afastamento_id := v_afast;
  EXCEPTION WHEN OTHERS THEN
    -- A ponte nunca quebra o registro do atestado; fica o aviso para tratamento manual.
    RAISE NOTICE 'Nao foi possivel encaminhar o afastamento automaticamente (%). O atestado foi registrado; abra o afastamento no modulo Afastamentos.', SQLERRM;
  END;

  -- O alerta ao DP tem bloco PROPRIO: um tropeco aqui (aviso repetido, por
  -- exemplo) nao pode desfazer o afastamento previdenciario acima, que e a
  -- parte que garante o beneficio do trabalhador a partir do 16o dia.
  BEGIN
    INSERT INTO public.ponto_alertas
      (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
       tipo, severidade, titulo, descricao, data_referencia)
    SELECT
      NEW.tenant_id, NEW.empresa_id, NULL, NEW.colaborador_nome, NEW.colaborador_cpf,
      'atestado_encaminhado_inss', 'alta',
      'Atestado acima de 15 dias encaminhado ao INSS',
      format('O atestado de %s dias de %s (inicio %s) passou dos 15 dias abonados pela empresa. '
          || 'Foi criado o afastamento previdenciario a partir do 16o dia (%s), status beneficio_inss. '
          || 'Confira a documentacao e o encaminhamento ao INSS (Lei 8.213, arts. 59-60).',
          v_dias, COALESCE(NEW.colaborador_nome,'-'), NEW.data_inicio_afastamento, v_dia16),
      v_dia16
    WHERE NOT EXISTS (
      SELECT 1 FROM public.ponto_alertas al
      WHERE al.tenant_id = NEW.tenant_id
        AND al.colaborador_cpf = NEW.colaborador_cpf
        AND al.tipo = 'atestado_encaminhado_inss'
        AND al.data_referencia = v_dia16
        AND COALESCE(al.resolvido, false) = false
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Nao foi possivel registrar o alerta de encaminhamento ao INSS (%). O afastamento foi criado.', SQLERRM;
  END;

  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------
-- SONDA PONTO-451 — comportamento, nao texto de codigo
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_451()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid;
  v_cpf text;
  v_ini date := (current_date - 40);
  v_alertas int;
  v_afast int;
  v_idx text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Registrar duas vezes o mesmo atestado e conferir a fila de alertas do Ponto';
  r.esperado    := 'Um alerta por ocorrencia (a repeticao nao empilha copias) e o afastamento previdenciario preservado';

  IF to_regclass('public.ponto_alertas') IS NULL OR to_regclass('public.atestados') IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: este ambiente nao tem a fila de alertas do Ponto (ponto_alertas) '
             || 'ou a tabela de atestados — nao ha vigilancia a conferir.';
    RETURN r;
  END IF;

  -- Guarda de ambiente: onde a chave da apuracao diaria ainda nao inclui a
  -- empresa (anterior a onda 1, migration 20260818190000), qualquer gravacao
  -- que dispare a consolidacao do dia quebra no ON CONFLICT. Nesse ambiente o
  -- caso nao tem como ser exercitado — e isso e um achado, nao um defeito da
  -- sonda. E o mesmo achado do PONTO-394.
  SELECT indexdef INTO v_idx
  FROM pg_indexes
  WHERE schemaname = 'public' AND tablename = 'ponto_diario'
    AND indexname = 'unique_ponto_diario';

  IF v_idx IS NOT NULL AND v_idx NOT ILIKE '%empresa_id%' THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO ESTRUTURAL (o mesmo do PONTO-394): a chave da apuracao diaria deste '
             || 'ambiente e (tenant, CPF, data), sem a empresa. Enquanto ela nao incluir a '
             || 'empresa, qualquer gravacao que dispare a consolidacao do dia e recusada e '
             || 'este caso nao chega a ser exercitado. A correcao ja existe no projeto '
             || '(migration 20260818190000).';
    r.erro_tecnico := 'Indice atual: ' || v_idx;
    RETURN r;
  END IF;

  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();
  v_cpf := public.qa_cpf(45101);

  DELETE FROM public.ponto_alertas WHERE tenant_id = v_t AND colaborador_cpf = v_cpf;
  DELETE FROM public.afastamentos  WHERE tenant_id = v_t AND colaborador_cpf = v_cpf;
  DELETE FROM public.atestados     WHERE tenant_id = v_t AND colaborador_cpf = v_cpf;

  -- Dois atestados iguais, de 20 dias: o segundo se sobrepoe ao primeiro e
  -- tambem passa dos 15 dias. Cada passagem tenta criar os dois avisos.
  INSERT INTO public.atestados
    (tenant_id, colaborador_nome, colaborador_cpf, tipo, data_emissao,
     profissional_nome, profissional_registro,
     data_inicio_afastamento, data_fim_afastamento, dias_afastamento)
  VALUES
    (v_t, 'Colaborador QA 451', v_cpf, 'assistencial', v_ini,
     'Profissional QA', 'CRM 000000', v_ini, v_ini + 19, 20),
    (v_t, 'Colaborador QA 451', v_cpf, 'assistencial', v_ini,
     'Profissional QA', 'CRM 000000', v_ini, v_ini + 19, 20);

  SELECT count(*) INTO v_alertas
  FROM public.ponto_alertas
  WHERE tenant_id = v_t AND colaborador_cpf = v_cpf
    AND tipo IN ('atestado_sobreposto', 'atestado_encaminhado_inss');

  SELECT count(*) INTO v_afast
  FROM public.afastamentos
  WHERE tenant_id = v_t AND colaborador_cpf = v_cpf;

  -- Esperado: 1 aviso de encaminhamento ao INSS (a 1a passagem) + 1 aviso de
  -- sobreposicao (so a 2a passagem tem com quem se sobrepor) = 2 avisos
  -- distintos, nenhum repetido; e 2 afastamentos, um por atestado.
  IF v_alertas > 2 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: registrar o mesmo atestado duas vezes deixou %s avisos na fila '
             || 'do Ponto, quando ha apenas 2 ocorrencias distintas (sobreposicao e '
             || 'encaminhamento ao INSS). A vigilancia repetida — e ela se repete sempre que '
             || 'alguem confere a tarde o que a madrugada gerou — empilha copias do mesmo '
             || 'aviso; o DP aprende a ignorar a lista e o alerta que importa se perde no meio. '
             || 'Correcao: NOT EXISTS por ocorrencia (tipo + CPF + data de referencia, nao '
             || 'resolvido), como ja se faz na materializacao de faltas (PONTO-292).', v_alertas);
  ELSIF v_afast < 2 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: dos 2 atestados acima de 15 dias, apenas %s gerou afastamento '
             || 'previdenciario. O aviso repetido derrubou junto o encaminhamento ao INSS a '
             || 'partir do 16o dia (Lei 8.213, arts. 59-60): o trabalhador fica sem o beneficio '
             || 'e ninguem e avisado. Correcao: gravar o alerta em bloco proprio, separado do '
             || 'afastamento.', v_afast);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('A segunda passagem nao duplicou aviso (%s avisos para 2 ocorrencias '
             || 'distintas) e os %s afastamentos previdenciarios foram preservados.',
             v_alertas, v_afast);
  END IF;

  RETURN r;
EXCEPTION
  WHEN unique_violation OR foreign_key_violation THEN
    -- O proprio registro do atestado nao passou. E o pior desfecho do aviso
    -- repetido: o tropeco no alerta desfaz o afastamento previdenciario e
    -- ainda derruba o atestado, deixando o afastamento do trabalhador sem
    -- registro nenhum.
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: registrar o mesmo atestado uma segunda vez foi RECUSADO pelo banco. '
             || 'O aviso repetido (mesmo tipo, mesmo CPF, mesma data de referencia) bate no '
             || 'indice de deduplicacao dentro do mesmo bloco em que se cria o afastamento '
             || 'previdenciario: a excecao desfaz o afastamento e o proprio atestado nao entra. '
             || 'Na pratica o DP reenvia um atestado e o sistema o rejeita sem explicacao, ou '
             || 'pior, o trabalhador fica sem o beneficio a partir do 16o dia (Lei 8.213, arts. '
             || '59-60). Correcao: gravar cada alerta com NOT EXISTS por ocorrencia e em bloco '
             || 'proprio, separado do afastamento.';
    r.erro_tecnico := SQLERRM;
    RETURN r;
  WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

DO $fim$
BEGIN
  RAISE NOTICE 'PONTO-451: alertas de atestado idempotentes e afastamento do INSS protegido.';
END $fim$;


CREATE OR REPLACE FUNCTION public.qa_caso_ponto_401()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid;
  v_cpf text;
  v_cid uuid;
  v_dia date := CURRENT_DATE - 3;
  v_calc RECORD;
  v_min int;
  v_idx text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Apurar um dia de minutos quebrados (08:00-12:00 e 13:00-17:07)';
  r.esperado    := 'Exatamente 487 minutos — o excedente contado no minuto, sem bloco arredondado';

  IF to_regprocedure('public._ponto_calc_dia(uuid, text, date, uuid)') IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A funcao de apuracao do dia (_ponto_calc_dia) nao existe nesta base — '
             || 'nao ha como conferir como o tempo trabalhado e contado.';
    RETURN r;
  END IF;

  -- Guarda de ambiente: onde a chave da apuracao diaria ainda nao inclui a
  -- empresa (anterior a onda 1, migration 20260818190000), qualquer gravacao
  -- que dispare a consolidacao do dia quebra no ON CONFLICT. Nesse ambiente o
  -- caso nao tem como ser exercitado — e isso e um achado, nao um defeito da
  -- sonda. E o mesmo achado do PONTO-394.
  SELECT indexdef INTO v_idx
  FROM pg_indexes
  WHERE schemaname = 'public' AND tablename = 'ponto_diario'
    AND indexname = 'unique_ponto_diario';

  IF v_idx IS NOT NULL AND v_idx NOT ILIKE '%empresa_id%' THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO ESTRUTURAL (o mesmo do PONTO-394): a chave da apuracao diaria deste '
             || 'ambiente e (tenant, CPF, data), sem a empresa. Enquanto ela nao incluir a '
             || 'empresa, qualquer gravacao que dispare a consolidacao do dia e recusada e '
             || 'este caso nao chega a ser exercitado. A correcao ja existe no projeto '
             || '(migration 20260818190000).';
    r.erro_tecnico := 'Indice atual: ' || v_idx;
    RETURN r;
  END IF;

  PERFORM public.qa_modo_ligar();
  v_t   := public.qa_sandbox_tenant_id();
  v_cpf := public.qa_cpf(40101);
  v_cid := gen_random_uuid();

  -- A marcacao de ponto e imutavel (Sumula 338 / Portaria MTP 671): a sonda
  -- NAO apaga nem regrava. Se a massa do dia ja existe de uma execucao
  -- anterior, ela e reaproveitada como esta; senao, e criada uma vez.
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
      (v_t, v_cid, 'Colaborador QA 401', v_cpf, v_dia, time '08:00:00', 'entrada', md5(v_cpf || v_dia::text || '401a')),
      (v_t, v_cid, 'Colaborador QA 401', v_cpf, v_dia, time '12:00:00', 'saida',   md5(v_cpf || v_dia::text || '401b')),
      (v_t, v_cid, 'Colaborador QA 401', v_cpf, v_dia, time '13:00:00', 'entrada', md5(v_cpf || v_dia::text || '401c')),
      (v_t, v_cid, 'Colaborador QA 401', v_cpf, v_dia, time '17:07:00', 'saida',   md5(v_cpf || v_dia::text || '401d'));
  END IF;

  SELECT * INTO v_calc FROM public._ponto_calc_dia(v_t, v_cpf, v_dia, v_cid);
  v_min := COALESCE(EXTRACT(EPOCH FROM v_calc.o_horas) / 60, 0)::int;

  IF v_min = 487 THEN
    r.situacao := 'passou';
    r.obtido := 'A apuracao devolveu 487 minutos exatos: os 7 minutos alem das 8 horas '
             || 'foram contados um a um, sem arredondar para bloco.';
  ELSIF v_min < 487 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o dia de 487 minutos foi apurado como %s — a apuracao '
             || 'arredondou o excedente PARA BAIXO. Depois da tolerancia legal, cada minuto '
             || 'de excesso e devido (CLT art. 58 par. 1o c/c Sumula 449 do TST); arredondar '
             || 'para baixo suprime hora extra em escala — todo o quadro, todo mes, sem que '
             || 'nada apareca no espelho. Correcao: manter o excedente em minutos inteiros '
             || 'exatos, deixando o arredondamento apenas para a apresentacao e para o valor '
             || 'monetario na folha, com a memoria de calculo mostrando os minutos.', v_min);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o dia de 487 minutos foi apurado como %s — a apuracao '
             || 'arredondou o excedente PARA CIMA, criando hora extra sem fato gerador. O '
             || 'erro e menos visivel que o inverso (ninguem reclama de receber a mais), mas '
             || 'contamina a folha, o custo por centro de resultado e a prova em eventual '
             || 'fiscalizacao. Correcao: contar o excedente no minuto exato.', v_min);
  END IF;

  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

DO $fim$
BEGIN
  RAISE NOTICE 'PONTO-401: sonda comportamental de arredondamento do excedente.';
END $fim$;

-- ============================================================================
-- CONFERENCIA
-- ============================================================================
WITH amb AS MATERIALIZED (
  SELECT to_regclass('public.ponto_alertas') IS NOT NULL AS tem_alertas,
         to_regclass('public.atestados')     IS NOT NULL AS tem_atestados,
         COALESCE((SELECT indexdef ILIKE '%empresa_id%' FROM pg_indexes
                    WHERE schemaname = 'public' AND tablename = 'ponto_diario'
                      AND indexname = 'unique_ponto_diario'), true) AS chave_nova
), res AS MATERIALIZED (
  SELECT (SELECT situacao FROM public.qa_caso_ponto_451()) AS c451,
         (SELECT situacao FROM public.qa_caso_ponto_401()) AS c401
)
SELECT a.tem_alertas, a.tem_atestados, a.chave_nova, r.c451, r.c401,
       CASE
         WHEN NOT (a.tem_alertas AND a.tem_atestados) THEN
           'CORRECOES GRAVADAS. Este ambiente ainda nao tem a fila de alertas ou a tabela de atestados — elas passam a valer quando a estrutura chegar.'
         WHEN NOT a.chave_nova THEN
           'CORRECOES GRAVADAS. Os dois casos nao podem ser exercitados aqui porque a chave da apuracao diaria ainda nao inclui a empresa (o achado do PONTO-394); eles voltam a rodar quando essa correcao chegar.'
         WHEN r.c451 = 'passou' AND r.c401 = 'passou' THEN 'OK'
         ELSE 'CONFERIR'
       END AS resultado
FROM amb a, res r;
