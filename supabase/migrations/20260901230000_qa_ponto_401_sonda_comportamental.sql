-- =====================================================================
-- PONTO-401 — a sonda passa a MEDIR o arredondamento, em vez de procurar
-- a palavra no código
--
-- O QUE FOI ENCONTRADO
-- O caso reprovava porque a apuração do dia (_ponto_calc_dia) contém um
-- FLOOR. Abrindo a rotina, esse FLOOR não arredonda hora extra: ele apenas
-- despreza os SEGUNDOS ao converter cada par entrada/saída em minutos
-- inteiros — que é a unidade do próprio registro legal (o AFD da Portaria
-- MTP 671/2021 grava hora e minuto, sem segundos) e a unidade que o
-- espelho mostra ao trabalhador. Nenhum minuto de excedente é arredondado.
--
-- Ou seja: era um falso positivo da sonda, não um defeito do sistema. A
-- auditoria por texto de código não distingue "arredondar o excedente"
-- (supressão sistemática, vedada pela Súmula 449 do TST) de "converter
-- segundos em minutos" (a granularidade legal do registro).
--
-- O QUE MUDA
-- Só a sonda. Ela passa a exercitar o comportamento no cercado de testes:
-- apura um dia com minutos quebrados (08:00–12:00 e 13:00–17:07) e confere
-- que o resultado é EXATAMENTE 487 minutos — nem 480 (arredondado para
-- baixo, para o bloco de meia hora), nem 495 (para cima), nem 490 (bloco
-- de 5 ou 10 minutos). Se qualquer dia vier em bloco redondo em vez do
-- minuto exato, o caso reprova com o achado.
--
-- NADA DE REGRA DE NEGÓCIO MUDA.
-- =====================================================================

SET lock_timeout = '10s';

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
