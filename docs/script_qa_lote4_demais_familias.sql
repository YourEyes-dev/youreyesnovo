-- ============================================================================
-- QA — LOTE 4 (demais familias, exceto Ferias): 138 rotinas de caso.
-- Familias: AFAST, BEN, COLAB, DADO, DESL, EMP, ENQ, EPI, ESC, FOLHA, HCAL,
-- HCAT, HIER, HTPL, JOR, OUV, REGRA, SST. Funcoes do dev que nunca chegaram a
-- producao (drift). Aditivo (CREATE OR REPLACE) + vinculo. Read-only por
-- natureza. O andaime (Lote 1b) ja esta na producao. Conferencia agrupa por
-- familia + situacao.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.qa_caso_afast_001()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
  r public.qa_retorno;
  v_id uuid;
  v_st text;
  v_n  int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Registrar afastamento cujo período de término já passou';
  r.esperado    := 'Não permanece ativo — encerra pelo gatilho ou pela rotina';

  v_id := public.qa_afast_legado('QA Vencido', CURRENT_DATE - 40);
  UPDATE public.afastamentos SET data_fim = CURRENT_DATE - 10 WHERE id = v_id;

  SELECT public.afastamento_encerrar_vencidos() INTO v_n;
  SELECT status::text INTO v_st FROM public.afastamentos WHERE id = v_id;

  IF v_st <> 'encerrado' THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: afastamento com término em %s continua como "%s". Enquanto '
             || 'contar como ativo, ele infla a régua dos 15 dias e o absenteísmo, e mantém o '
             || 'colaborador impedido de bater ponto — o RH só sai disso apagando o registro.',
             to_char(CURRENT_DATE - 10, 'DD/MM/YYYY'), v_st);
    RETURN r;
  END IF;

  r.passo_ordem := 2;
  r.passo_acao  := 'Rodar a rotina de encerramento de novo';
  r.esperado    := 'Nada muda — ela roda todo dia e precisa ser inócua quando não há o que fazer';
  SELECT public.afastamento_encerrar_vencidos() INTO v_n;

  IF v_n <> 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('A rotina não é idempotente: na segunda execução ainda encerrou %s '
                    || 'registro(s).', v_n);
    RETURN r;
  END IF;

  r.situacao := 'passou';
  r.obtido := 'Vencido não fica ativo, e rodar a rotina de novo não mexe em nada.';
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_afast_002()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
  r public.qa_retorno;
  v_recusou boolean := false;
  v_msg text;
  v_id uuid;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Tentar criar afastamento comum sem data de término';
  r.esperado    := 'Recusado, com mensagem que diz o que fazer';

  BEGIN
    v_id := public.qa_afast_novo('QA Sem Fim', CURRENT_DATE - 5, NULL);
  EXCEPTION WHEN OTHERS THEN
    v_recusou := true;
    v_msg := SQLERRM;
  END;

  IF NOT v_recusou THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o banco aceitou afastamento comum SEM data de término. A trava do '
             || 'ponto lê fim ausente como 31/12/9999 — o colaborador fica impedido de bater '
             || 'ponto para sempre, e o RH só resolve apagando o afastamento (perdendo o '
             || 'histórico de saúde ocupacional junto).';
    RETURN r;
  END IF;

  r.passo_ordem := 2;
  r.passo_acao  := 'Criar afastamento de prazo indeterminado sem data de término';
  r.esperado    := 'Aceito — benefício do INSS não tem previsão de retorno';

  BEGIN
    v_id := public.qa_afast_novo('QA Prazo Indeterminado', CURRENT_DATE - 5, NULL, true);
  EXCEPTION WHEN OTHERS THEN
    r.situacao := 'falhou';
    r.obtido := format('A guarda passou do ponto: recusou até o caso legítimo (prazo '
                    || 'indeterminado / benefício do INSS), que não tem data de retorno por '
                    || 'natureza. Mensagem: %s', left(SQLERRM, 120));
    RETURN r;
  END;

  r.situacao := 'passou';
  r.obtido := format('Comum sem fim recusado ("%s") e prazo indeterminado aceito.',
                     left(v_msg, 80));
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_afast_003()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
  r public.qa_retorno;
  v_id uuid;
  v_st text;
  v_fim date;
  v_existe boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Informar a data de término de um afastamento legado já vencido';
  r.esperado    := 'Encerra na hora, sem esperar a rotina da madrugada';

  v_id := public.qa_afast_legado('QA Legado', CURRENT_DATE - 60);

  -- Confere que o cenário é mesmo o legado: ativo e sem data de término.
  SELECT status::text, data_fim INTO v_st, v_fim
    FROM public.afastamentos WHERE id = v_id;
  IF v_st <> 'ativo' OR v_fim IS NOT NULL THEN
    r.situacao := 'erro';
    r.obtido := format('Não foi possível montar o cenário legado (situação %s, término %s).',
                       v_st, coalesce(v_fim::text, 'nenhum'));
    RETURN r;
  END IF;

  UPDATE public.afastamentos SET data_fim = CURRENT_DATE - 50 WHERE id = v_id;
  SELECT status::text INTO v_st FROM public.afastamentos WHERE id = v_id;

  IF v_st <> 'encerrado' THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: informar a data de término deixou o registro como "%s". Sem '
             || 'encerramento imediato, o RH continua sem caminho de saída a não ser apagar o '
             || 'afastamento — que é justamente o que estamos tentando evitar.', v_st);
    RETURN r;
  END IF;

  r.passo_ordem := 2;
  r.passo_acao  := 'Conferir que o registro continua existindo';
  r.esperado    := 'Histórico preservado, nada apagado';
  SELECT EXISTS (SELECT 1 FROM public.afastamentos WHERE id = v_id) INTO v_existe;

  IF NOT v_existe THEN
    r.situacao := 'falhou';
    r.obtido := 'O encerramento apagou o registro. Afastamento é histórico de saúde '
             || 'ocupacional: encerra, não some.';
    RETURN r;
  END IF;

  r.situacao := 'passou';
  r.obtido := 'Ao informar a data de término o afastamento encerrou na hora, e o registro '
           || 'continua na base para consulta e para o eSocial.';
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_afast_010()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_param text; v_cod text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): cada tipo de afastamento carrega efeito legal e código da Tabela 18?';
  r.esperado := 'Parametrização por tipo: interrupção × suspensão + código do eSocial, com vigência';
  SELECT string_agg(table_name, ', ') INTO v_param
  FROM information_schema.tables
  WHERE table_schema = 'public'
    AND (table_name ILIKE '%afastamento%tipo%' OR table_name ILIKE '%afastamento%efeito%'
         OR table_name ILIKE '%afastamento%config%');
  v_cod := coalesce(public.qa_col_existe('afastamentos', '%tabela_18%'),
                    public.qa_col_existe('afastamentos', '%codigo_esocial%'),
                    public.qa_col_existe(NULL, '%tabela18%'));

  IF v_param IS NULL AND v_cod IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o tipo do afastamento é só um NOME — o enum '
             || 'afastamento_tipo_principal tem um catálogo rico (18 tipos), mas nenhuma '
             || 'tabela parametriza o EFEITO legal de cada um (interrupção mantém salário '
             || 'e tempo; suspensão não) nem o código da Tabela 18 do eSocial que o S-2230 '
             || 'exige. As consequências ficam por conta de quem lê o nome do tipo: a '
             || 'inteligência trata alguns casos por lista fixa em código (acidentes, '
             || 'maternidade), e o resto não tem efeito definido em lugar nenhum. Correção: '
             || 'tabela de tipos com efeito (interrupção/suspensão), efeito no FGTS/tempo, '
             || 'código da Tabela 18 e vigência — a matriz por cliente é [VAL] (seção 30).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Parametrização presente (tabelas: %s; código: %s).',
                       coalesce(v_param, '—'), coalesce(v_cod, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_afast_011()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_cpf text := public.qa_cpf(9111); v_aceitou boolean := false;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Registrar dois afastamentos ATIVOS sobrepostos para o mesmo colaborador';
  r.esperado := 'O segundo é recusado — sobreposição é prorrogação ou é erro, nunca registro paralelo';
  INSERT INTO public.afastamentos
    (tenant_id, colaborador_nome, colaborador_cpf, data_inicio, data_fim, status)
  VALUES (v_t, '[QA-AFAST-011] Sobreposto', v_cpf, CURRENT_DATE - 20, CURRENT_DATE + 10, 'ativo');
  BEGIN
    INSERT INTO public.afastamentos
      (tenant_id, colaborador_nome, colaborador_cpf, data_inicio, data_fim, status)
    VALUES (v_t, '[QA-AFAST-011] Sobreposto', v_cpf, CURRENT_DATE - 5, CURRENT_DATE + 20, 'ativo');
    v_aceitou := true;
  EXCEPTION WHEN check_violation OR raise_exception OR exclusion_violation THEN
    v_aceitou := false; END;

  IF v_aceitou THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o banco aceitou dois afastamentos ATIVOS sobrepostos do mesmo CPF — '
             || 'não há constraint de exclusão nem validação de período. Com dois registros '
             || 'vigentes, o Ponto não sabe qual regra aplicar, a folha pode suspender duas '
             || 'vezes (ou nenhuma) e o eSocial recebe S-2230 conflitantes do mesmo vínculo. '
             || 'A inteligência até ACUMULA dias por CID, mas não impede o paralelismo. '
             || 'Correção: EXCLUDE USING gist (colaborador × daterange) para status ativos, '
             || 'com a prorrogação como caminho explícito (UPDATE do fim, com trilha).';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'A sobreposição foi recusada na gravação.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_afast_020()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_id uuid; v_pend int; v_status text;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Registrar doença comum de 20 dias e conferir o que a inteligência produz';
  r.esperado := 'Pendência de INSS/S-2230 criada E status virado para aguardando_inss (Lei 8.213, art. 60)';
  v_id := public.qa_afast_tipado('[QA-AFAST-020] Doenca 20d', 9120,
                                 CURRENT_DATE - 20, CURRENT_DATE, 'doenca_comum');
  SELECT count(*) INTO v_pend FROM public.afastamentos_pendencias
  WHERE afastamento_id = v_id AND tipo_pendencia IN ('inss', 's2230');
  SELECT status_geral_new::text INTO v_status FROM public.afastamentos WHERE id = v_id;

  IF v_pend > 0 AND v_status = 'aguardando_inss' THEN
    r.situacao := 'passou';
    r.obtido := format('Regra viva: %s pendência(s) criada(s) e status %s.', v_pend, v_status);
  ELSIF v_pend > 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO (regressão parcial na reescrita de 24/07): as PENDÊNCIAS dos '
             || '15 dias nasceram (%s: avaliar INSS + S-2230), mas o afastamento NÃO virou '
             || 'para aguardando_inss — ficou "%s". A versão de 23/07 fazia a virada no '
             || 'próprio registro (era o que habilitava o bloco de benefício INSS na tela); '
             || 'a reescrita de 24/07 moveu a inteligência para gatilho AFTER, que não '
             || 'altera a própria linha, e a virada se perdeu. Sem ela, o DP depende de ler '
             || 'a pendência — e a tela que filtra por status não mostra o caso. Correção: '
             || 'devolver a mudança de status ao gatilho BEFORE (afastamento_campos_before).',
             v_pend, coalesce(v_status, 'NULL'));
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO (regressão da reescrita de 24/07): doença ÚNICA de 20 dias '
             || 'entrou sem pendência de INSS/S-2230 e com status "%s". A versão de 23/07 '
             || 'disparava a regra para afastamento único > 15 dias mesmo sem CID e virava '
             || 'o status para aguardando_inss; a versão viva só dispara pela ACUMULAÇÃO '
             || '(exige CID em afastamentos_saude + colaborador vinculado — que o '
             || 'formulário de atestado nem sempre preenche) e não muda status nenhum. '
             || 'Resultado: o caso mais comum — um atestado longo — passa em silêncio, a '
             || 'folha paga dias do INSS e o S-2230 do 16º dia perde o prazo. Correção: '
             || 'restaurar o ramo do afastamento único (basta dias_totais > 15) e a virada '
             || 'de status no gatilho BEFORE.',
             coalesce(v_status, 'NULL'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_afast_021()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_acum text; v_prazo text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a acumulação por CID em 60 dias existe e produz o efeito completo?';
  r.esperado := 'Recaída soma os dias (sem novos 15 da empresa) e o S-2230 sai no 1º dia';
  SELECT left(p.prosrc, 1) INTO v_acum
  FROM pg_proc p WHERE p.proname = 'processar_inteligencia_afastamento'
    AND p.prosrc ILIKE '%60%' AND p.prosrc ILIKE '%cid%';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_prazo
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%recaida%' AND p.prosrc ILIKE '%prazo%';

  IF v_acum IS NOT NULL AND v_prazo IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO (metade boa, metade ausente): a ACUMULAÇÃO existe — a inteligência '
             || 'soma os dias de afastamentos com o mesmo CID em 60 dias e dispara a '
             || 'pendência de INSS quando o acumulado passa de 15 (a empresa não paga novos '
             || '15 dias, correto) — mas ela depende de o formulário preencher CID e '
             || 'colaborador vinculado, e a RECAÍDA não muda o PRAZO do S-2230: na recaída '
             || 'o evento vai no 1º DIA, não no 16º nem no dia 15 do mês seguinte, e '
             || 'nenhuma função trata esse relógio. Recaída identificada com prazo errado '
             || 'ainda é multa. Correção: prazo diferenciado na pendência de S-2230 quando '
             || 'a origem é acumulação por CID + garantir CID/vínculo obrigatórios no '
             || 'fluxo de atestado. Regra exata da recaída é [VAL] (seção 30).';
  ELSIF v_acum IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A acumulação por CID em 60 dias não existe mais na inteligência do afastamento.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Acumulação viva e prazo de recaída tratado (%s).', v_prazo);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_afast_022()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o afastamento registrado vira lançamento de folha?';
  r.esperado := '15 dias pagos em rubrica própria; suspensão do 16º; origem rastreável — sem redigitação';
  -- exige que a função ESCREVA na folha — "afastamento + folha" solto pega as
  -- funções de exclusão de colaborador, que só CONTAM vínculos nas tabelas
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%afastamento%'
    AND (p.prosrc ILIKE '%INSERT INTO%folha_lancamentos%'
         OR p.prosrc ILIKE '%INSERT INTO%folha_itens%');

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o afastamento não chega à folha — nenhuma função gera lançamento a '
             || 'partir do afastamento registrado: os 15 dias pela empresa, a suspensão do '
             || '16º e a divisão da competência que atravessa a virada dependem de o DP '
             || 'REDIGITAR na folha o que o afastamento já sabe. É o primeiro elo do "erro '
             || 'em cadeia" que o documento descreve: registrado aqui, esquecido lá, a '
             || 'folha paga salário integral de quem está no INSS. Par do FOLHA-080 (visto '
             || 'do lado da folha). Correção: geração de lançamentos por competência a '
             || 'partir dos afastamentos vigentes, com origem rastreável e rubrica própria.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Reflexo na folha presente: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_afast_030()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_id uuid; v_cat int; v_prazo text;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Registrar acidente típico e conferir a pendência de CAT e o prazo dela';
  r.esperado := 'Pendência de CAT criada com prazo no 1º dia útil seguinte (art. 22 da Lei 8.213)';
  v_id := public.qa_afast_tipado('[QA-AFAST-030] Acidente', 9130,
                                 CURRENT_DATE, CURRENT_DATE + 10, 'acidente_tipico');
  SELECT count(*) INTO v_cat FROM public.afastamentos_pendencias
  WHERE afastamento_id = v_id AND tipo_pendencia = 'cat';
  -- a COLUNA prazo existe; o que importa é se a inteligência a PREENCHE
  SELECT max(prazo)::text INTO v_prazo FROM public.afastamentos_pendencias
  WHERE afastamento_id = v_id AND tipo_pendencia = 'cat';

  IF v_cat > 0 AND v_prazo IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO (metade boa, metade sem relógio): o acidente DISPAROU a pendência de '
             || 'CAT (marcadores cat_obrigatoria/cat_pendente e pendências de CAT e S-2210 — '
             || 'a inteligência funciona), mas o PRAZO ficou vazio: a coluna '
             || 'afastamentos_pendencias.prazo existe e a inteligência não a preenche — o '
             || '"1º dia útil seguinte", o prazo mais curto do DP, vira prioridade textual '
             || 'sem relógio. Acidente na sexta dá CAT até segunda; sem o cálculo pelo '
             || 'calendário (tabela feriados), ninguém escala o alerta a tempo e a multa do '
             || 'art. 22 chega junto com a fiscalização. Correção: preencher prazo = 1º dia '
             || 'útil seguinte (imediato em óbito) na criação da pendência, com escalada '
             || 'crítica na aproximação.';
  ELSIF v_cat = 0 THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o acidente típico NÃO gerou pendência de CAT — a regra da '
             || 'inteligência não disparou. Conferir o gatilho.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('CAT disparada com prazo controlado (%s).', v_prazo);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_afast_031()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_id uuid; v_marc int; v_fim date;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Registrar acidente com data de retorno e conferir a estabilidade gravada';
  r.esperado := 'data_fim_estabilidade = retorno + 12 meses (art. 118) — o registro que a Rescisão lê';
  v_id := public.qa_afast_tipado('[QA-AFAST-031] Estabilidade', 9131,
                                 CURRENT_DATE - 40, CURRENT_DATE - 5, 'acidente_tipico');
  SELECT count(*) INTO v_marc FROM public.afastamentos_marcadores
  WHERE afastamento_id = v_id AND marcador = 'estabilidade_provisoria';
  SELECT data_fim_estabilidade INTO v_fim FROM public.afastamentos WHERE id = v_id;

  IF v_fim = (CURRENT_DATE - 5 + interval '12 months')::date THEN
    r.situacao := 'passou';
    r.obtido := format('Estabilidade gravada até %s (retorno + 12 meses); marcador: %s.',
                       v_fim, v_marc);
  ELSIF v_marc > 0 AND v_fim IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO (regressão na reescrita de 24/07): o MARCADOR de estabilidade nasceu, '
             || 'mas data_fim_estabilidade ficou NULA — a versão de 23/07 gravava retorno + '
             || '12 meses no próprio registro (era esse campo que o mapa de estabilidades e '
             || 'a Rescisão liam); o gatilho AFTER de 24/07 não altera a própria linha e a '
             || 'gravação se perdeu. Sem a data, a estabilidade existe como etiqueta sem '
             || 'vencimento: o DESL-071 bloqueia dispensa lendo este campo, e o falso '
             || 'negativo do DESL-077 volta por outra porta. Correção: gravar '
             || 'data_fim_estabilidade no gatilho BEFORE (afastamento_campos_before), '
             || 'com expiração conferível.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO (regressão da reescrita de 24/07): o acidente encerrado não '
             || 'criou estabilidade NENHUMA (marcador: %s; data_fim_estabilidade: %s). Duas '
             || 'perdas na mesma reescrita: a Regra 9 da inteligência trocou a lista de '
             || 'tipos — acidente_tipico/trajeto e doenca_ocupacional SAÍRAM (ficaram só '
             || 'b91, maternidade e sindical), justamente os casos do art. 118 — e a '
             || 'gravação de data_fim_estabilidade (retorno + 12 meses, versão de 23/07) '
             || 'desapareceu: a coluna ficou órfã. O DESL-071 bloqueia dispensa lendo esse '
             || 'campo; vazio, o falso negativo do DESL-077 volta por outra porta. '
             || 'Correção: devolver os tipos acidentários à Regra 9 e gravar '
             || 'data_fim_estabilidade no gatilho BEFORE (AFTER não altera a própria linha).',
             v_marc, coalesce(v_fim::text, 'NULL'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_afast_032()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_est text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o efeito do afastamento no FGTS existe em algum lugar?';
  r.esperado := 'Acidente e serviço militar mantêm o depósito (art. 15, §5º); demais suspendem';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_est
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%afastamento%' AND p.prosrc ILIKE '%fgts%';

  IF v_est IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o FGTS do afastado não é tratado em lugar nenhum — nenhuma função '
             || 'cruza afastamento com FGTS. A regra tem dois lados que erram em direções '
             || 'opostas: no acidente de trabalho (e serviço militar) o depósito de 8% '
             || 'CONTINUA o afastamento inteiro (art. 15, §5º — não depositar é dívida que '
             || 'o FGTS Digital denuncia); na doença comum a partir do 16º e na licença '
             || 'sem remuneração, SUSPENDE (depositar é custo indevido). O efeito por tipo '
             || 'pertence à matriz do AFAST-010 e ao reflexo na folha do AFAST-022 — este '
             || 'caso garante que o FGTS não fique de fora dela. Efeitos exatos por tipo '
             || 'são [VAL] (seção 30).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Efeito no FGTS tratado por: %s.', v_est);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_afast_040()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_adesao text; v_gest text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): os prazos da licença e a estabilidade gestante têm estrutura?';
  r.esperado := '120 (+60 Empresa Cidadã) / 5 (+15) dias parametrizados pela adesão; estabilidade gestante com vencimento';
  v_adesao := coalesce(public.qa_col_existe('empresa_cadastro', '%cidada%'),
                       public.qa_col_existe(NULL, '%empresa_cidada%'));
  v_gest := coalesce(public.qa_fns_com('%gestante%'),
                     public.qa_col_existe(NULL, '%estabilidade_gestante%'));

  IF v_adesao IS NULL AND v_gest IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a maternidade existe só como TIPO — licenca_maternidade está no '
             || 'enum e ganha marcador de estabilidade provisória, mas: (1) a adesão ao '
             || 'Empresa Cidadã não é cadastrada em lugar nenhum, então o sistema não sabe '
             || 'se a licença é de 120 ou 180 dias (nem 5 ou 20 na paternidade); (2) a '
             || 'estabilidade GESTANTE (confirmação da gravidez até 5 meses pós-parto — '
             || 'ADCT art. 10) não tem estrutura própria: o vencimento dela não é "fim da '
             || 'licença + 12 meses" como no acidente, é "parto + 5 meses", e nenhum campo '
             || 'ou função a calcula. A Rescisão bloqueia gestante (DESL-070) lendo o quê? '
             || 'Correção: adesão ao programa no cadastro da empresa (com vigência) + '
             || 'estabilidade tipada com regra de vencimento própria por espécie.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Estrutura presente (adesão: %s; gestante: %s).',
                       coalesce(v_adesao, '—'), coalesce(v_gest, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_afast_050()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_param text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): as hipóteses do art. 473 existem com seus prazos?';
  r.esperado := 'Catálogo por hipótese (falecimento 2d, casamento 3d, doação de sangue 1/ano...) com limite conferido';
  SELECT string_agg(table_name, ', ') INTO v_param
  FROM information_schema.tables
  WHERE table_schema = 'public'
    AND (table_name ILIKE '%falta%justificada%' OR table_name ILIKE '%473%'
         OR table_name ILIKE '%hipotese%');

  IF v_param IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o art. 473 inteiro virou UM tipo genérico — falta_justificada_legal '
             || '— sem as hipóteses nem os prazos de cada uma: 2 dias por falecimento, 3 '
             || 'por casamento, 1 por ano para doar sangue, juízo pelo tempo necessário, '
             || 'pré-natal... Sem o catálogo, ninguém confere o LIMITE (4 dias de '
             || '"falecimento" passam como justificados quando 2 deveriam virar falta '
             || 'comum) nem o teto anual da doação de sangue. A decisão fica com o '
             || 'operador, caso a caso, sem trilha do enquadramento. Correção: catálogo de '
             || 'hipóteses (inciso, dias, frequência) parametrizável — CCTs ampliam '
             || 'hipóteses [RCC] — com o excedente tratado como falta comum e alertado.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Catálogo de hipóteses presente: %s.', v_param);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_afast_051()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_aceitou boolean := false; v_id uuid;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Registrar suspensão disciplinar de 45 dias corridos';
  r.esperado := 'Recusada — o art. 474 limita a 30 dias; acima disso a lei converte em rescisão injusta';
  BEGIN
    v_id := public.qa_afast_tipado('[QA-AFAST-051] Suspensao 45d', 9151,
                                   CURRENT_DATE, CURRENT_DATE + 44, 'suspensao_disciplinar');
    v_aceitou := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_aceitou := false; END;

  IF v_aceitou THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a suspensão disciplinar de 45 dias entrou sem resistência — nenhuma '
             || 'validação compara a duração com o teto do art. 474 quando o tipo é '
             || 'suspensao_disciplinar. O 31º dia não é "punição longa": é rescisão injusta '
             || 'por força de lei — o empregado pode se considerar dispensado com todas as '
             || 'verbas, e foi o próprio sistema que documentou a prova. Correção: validação '
             || 'tipo × duração na gravação (teto de 30 dias corridos), com alerta ao '
             || 'jurídico se alguém tentar.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'A suspensão acima de 30 dias foi recusada.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_afast_060()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_pend text; v_prazo text; v_ger text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o S-2230 tem a tabela de prazos e a geração do evento?';
  r.esperado := 'Prazo por motivo/duração (dia 15; 16º dia; 1º dia na recaída; término) + evento gerado';
  SELECT left(p.prosrc, 1) INTO v_pend
  FROM pg_proc p WHERE p.proname = 'processar_inteligencia_afastamento'
    AND p.prosrc ILIKE '%s2230%';
  -- a coluna prazo existe; conta apenas se alguma função a PREENCHE
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_prazo
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%afastamentos_pendencias%' AND p.prosrc ILIKE '%prazo%';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_ger
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%S-2230%' AND p.prosrc ILIKE '%esocial_transmissoes%');

  IF v_pend IS NOT NULL AND (v_prazo IS NULL OR v_ger IS NULL) THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO (o lembrete existe, o relógio e o evento não): a inteligência cria a '
             || 'pendência de S-2230 na doença longa — mas (1) a pendência não tem '
             || 'data-limite, e o prazo do S-2230 é uma TABELA: dia 15 do mês seguinte na '
             || 'regra geral, 16º DIA do afastamento na doença > 15 dias, 1º dia na '
             || 'recaída, dia 15 seguinte no término — cada motivo com seu relógio; e (2) '
             || 'nenhuma função GERA o evento para esocial_transmissoes — o afastamento '
             || 'não existe para o governo, mesmo vazio dos S-1200/S-2299 (FOLHA-060, '
             || 'DESL-091). Correção: data-limite por motivo/duração na pendência + '
             || 'geração do S-2230 (afastamento e término) na fila com anti-duplicidade '
             || '(série ADM-093..DESL-094). Prazos vigentes são [VAL].';
  ELSIF v_pend IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A pendência de S-2230 sumiu da inteligência do afastamento.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Prazos e geração presentes (prazo: %s; geração: %s).',
                       coalesce(v_prazo, '—'), coalesce(v_ger, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_afast_070()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_id uuid; v_pend int; v_encerrou boolean := false;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Registrar afastamento de 45 dias e conferir a exigência de ASO de retorno';
  r.esperado := 'Pendência de ASO criada e o encerramento condicionado ao exame (NR-7)';
  v_id := public.qa_afast_tipado('[QA-AFAST-070] Longo 45d', 9170,
                                 CURRENT_DATE - 45, CURRENT_DATE, 'doenca_comum');
  SELECT count(*) INTO v_pend FROM public.afastamentos_pendencias
  WHERE afastamento_id = v_id AND tipo_pendencia = 'aso_retorno';

  r.passo_ordem := 2;
  r.passo_acao := 'Encerrar o afastamento SEM registrar o ASO de retorno';
  r.esperado := 'Retido — retorno de afastamento ≥ 30 dias só se completa com o exame';
  BEGIN
    UPDATE public.afastamentos SET status = 'encerrado' WHERE id = v_id;
    v_encerrou := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_encerrou := false; END;

  IF v_pend > 0 AND v_encerrou THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO (a pendência existe, a trava não): o afastamento de 45 dias GEROU a '
             || 'pendência de ASO de retorno (a inteligência acertou — NR-7 exige o exame '
             || 'antes da retomada em afastamento ≥ 30 dias), mas o ENCERRAMENTO passou '
             || 'direto com a pendência aberta: nada condiciona o fim do afastamento ao '
             || 'exame. Encerrado, o Ponto volta a cobrar marcação e a pessoa volta ao '
             || 'posto sem o crivo médico — exatamente o que a norma quis impedir (e um '
             || 'risco real se o afastamento foi psiquiátrico ou acidentário). Correção: '
             || 'encerramento retido enquanto houver pendência de aso_retorno aberta, com '
             || 'exceção justificada em trilha (alta administrativa) para não travar '
             || 'operação legítima.';
  ELSIF v_pend = 0 THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o afastamento de 45 dias NÃO gerou pendência de ASO de retorno — '
             || 'a regra dos 30 dias da inteligência não disparou. Conferir o gatilho.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Pendência criada e encerramento retido até o ASO.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_afast_080()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_atest int; v_saude int; v_log text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o CID está restrito e o acesso a ele é logado?';
  r.esperado := 'Camada de perfil sobre atestados/afastamentos_saude + log específico de acesso ao CID';
  SELECT count(*) INTO v_atest FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'atestados'
    AND policyname ILIKE 'perfil_restringe%';
  SELECT count(*) INTO v_saude FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'afastamentos_saude'
    AND policyname ILIKE 'perfil_restringe%';
  -- "cid" solto casa com "cidade" (gerar_estrutura_padrao_pastas) — exige a
  -- coluna clínica de verdade no corpo da função
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_log
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%cid_principal%' OR p.prosrc ILIKE '%cid_codigo%')
    AND (p.prosrc ILIKE '%log%' OR p.prosrc ILIKE '%acesso%' OR p.prosrc ILIKE '%audit%');

  IF v_atest > 0 AND v_saude > 0 AND v_log IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO (a porta tem tranca, mas ninguém anota quem entrou): as DUAS '
             || 'tabelas com CID estão na camada de perfil (atestados: %s política(s); '
             || 'afastamentos_saude: %s) — a restrição de leitura existe e é das melhores '
             || 'do sistema. O que falta é o LOG ESPECÍFICO de acesso ao CID que o '
             || 'documento exige (seção 22: "log de acesso específico ao CID"; seção 29: '
             || '"cofre do CID"): nenhuma função registra QUEM consultou o diagnóstico de '
             || 'QUEM e quando. Para dado sensível do art. 11 da LGPD, a trilha de acesso '
             || 'é parte da conformidade — numa investigação de vazamento, hoje não há o '
             || 'que consultar. Correção: leitura do CID via função SECURITY DEFINER que '
             || 'registra o acesso (leitor, titular, registro, hora) em tabela append-only.',
             v_atest, v_saude);
  ELSIF v_atest = 0 OR v_saude = 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO GRAVE: tabela com CID fora da camada de perfil (atestados: %s; '
             || 'afastamentos_saude: %s políticas) — diagnóstico legível além do SST.',
             v_atest, v_saude);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Restrição e log presentes (log: %s).', v_log);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ben_001()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_col text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): alguém lê regras_cargo/vinculo/unidade na adesão?';
  r.esperado := 'Elegibilidade conferida ao aderir — cargo fora da regra é bloqueado/sinalizado';
  v_col := public.qa_col_existe('beneficios_tipos', 'regras_cargo');
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%regras_cargo%' OR p.prosrc ILIKE '%regras_vinculo%'
         OR p.prosrc ILIKE '%regras_unidade%');

  IF v_col IS NOT NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: as regras de elegibilidade estão cadastradas (regras_cargo, '
             || 'regras_vinculo, regras_unidade em beneficios_tipos) e NENHUMA função as '
             || 'lê — a adesão em beneficios_colaboradores aceita qualquer colaborador em '
             || 'qualquer benefício, e a regra vira anotação. Conceder fora da regra é '
             || 'custo sem controle e diferenciação sem critério (risco de equiparação); '
             || 'negar o que a CCT garante é passivo. Correção: validação de elegibilidade '
             || 'na adesão (gatilho ou função de adesão), com sinalização para o DP '
             || 'decidir a exceção documentada.';
  ELSIF v_col IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'As colunas de regras de elegibilidade não existem mais em beneficios_tipos.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Elegibilidade aplicada por: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ben_010()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_tipo uuid; v_status text; v_termo text;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Registrar adesão de VT SEM termo de opção e ver se algo protesta';
  r.esperado := 'Bloqueio ou pendência de termo — o VT é optativo (Lei 7.418/85)';
  INSERT INTO public.beneficios_tipos (tenant_id, nome, categoria)
  VALUES (v_t, 'QA — Vale-transporte', 'transporte')
  RETURNING id INTO v_tipo;
  INSERT INTO public.beneficios_colaboradores
    (tenant_id, beneficio_tipo_id, colaborador_id, colaborador_nome, colaborador_cpf,
     valor, valor_desconto, data_inicio, status)
  VALUES (v_t, v_tipo, gen_random_uuid(), 'QA Colaborador Ben Dez', public.qa_cpf(70),
          220.00, 90.00, CURRENT_DATE, 'ativo');
  SELECT bc.status INTO v_status FROM public.beneficios_colaboradores bc
  WHERE bc.tenant_id = v_t AND bc.beneficio_tipo_id = v_tipo LIMIT 1;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: a adesão tem onde ancorar o termo de opção/recusa?';
  r.esperado := 'Vínculo com o termo assinado (documento) na adesão';
  v_termo := coalesce(public.qa_col_existe('beneficios_colaboradores', '%termo%'),
                      public.qa_col_existe('beneficios_colaboradores', '%documento%'),
                      public.qa_col_existe('beneficios_colaboradores', '%arquivo%'));

  IF v_status = 'ativo' AND v_termo IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a adesão de VT nasceu ATIVA, com desconto, sem termo de opção — e '
             || 'pior: não existe sequer COLUNA para ancorar o termo (ou a recusa) em '
             || 'beneficios_colaboradores. O VT é optativo por lei: descontar de quem não '
             || 'optou é desconto ilegal; conceder sem opção documentada perde a prova da '
             || 'natureza não salarial. A coleta na admissão existe (ADM-050) mas não se '
             || 'conecta ao benefício. Correção: vínculo obrigatório da adesão com o termo '
             || '(assinado, no módulo Documentos — padrão ADM-070); sem termo, adesão '
             || 'pendente, sem concessão nem desconto; recusa registrada com reopção '
             || 'possível.';
  ELSIF v_status IS DISTINCT FROM 'ativo' THEN
    r.situacao := 'passou';
    r.obtido := format('A adesão sem termo não se consumou (status: %s).', coalesce(v_status, 'NULL'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Há ancoragem para o termo (%s) — a sonda fina fica com a rotina de tela.', v_termo);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ben_011()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_pct numeric; v_fns text;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Cadastrar VT com desconto de 15% no catálogo e ver se o teto legal segura';
  r.esperado := 'Percentual acima de 6% recusado ou limitado (Lei 7.418/85)';
  INSERT INTO public.beneficios_tipos
    (tenant_id, nome, categoria, tipo_desconto, percentual_desconto)
  VALUES (v_t, 'QA — VT quinze por cento', 'transporte', 'percentual', 15);
  SELECT bt.percentual_desconto INTO v_pct FROM public.beneficios_tipos bt
  WHERE bt.tenant_id = v_t AND bt.nome = 'QA — VT quinze por cento';

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: existe motor que calcule o MENOR entre 6% do salário e o custo real?';
  r.esperado := 'Cálculo com os dois tetos e memória; home office dispensa o VT';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%beneficio%'
    AND (p.prosrc ILIKE '%0.06%' OR p.prosrc ILIKE '%salario%basico%');

  IF v_pct = 15 AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o catálogo aceitou VT com desconto de 15% — nenhum CHECK ou '
             || 'gatilho conhece o teto legal de 6%, e não existe motor que calcule o '
             || 'desconto correto (o MENOR entre 6% do salário básico e o custo real do '
             || 'transporte): beneficios_colaboradores guarda valor e valor_desconto '
             || 'digitados à mão. Passe barato deve descontar menos que 6%; reajuste '
             || 'salarial deve recalcular o teto — nada disso tem onde acontecer. O limite '
             || 'genérico na folha (FOLHA-030) não substitui a conta do benefício. '
             || 'Correção: teto de 6% validado no catálogo para a categoria transporte + '
             || 'motor de cálculo por competência (salário básico × 6% vs. custo, '
             || 'proporcional aos dias — BEN-050), com memória.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Teto tratado (percentual gravado: %s; motor: %s).',
                       coalesce(v_pct::text, 'recusado'), coalesce(v_fns, 'na gravação'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ben_012()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_pct numeric; v_param text;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Cadastrar VR com desconto de 50% do valor e ver se o limite do PAT segura';
  r.esperado := 'Participação do trabalhador limitada (PAT/CCT) — 50% não passa em silêncio';
  INSERT INTO public.beneficios_tipos
    (tenant_id, nome, categoria, tipo_desconto, percentual_desconto)
  VALUES (v_t, 'QA — VR cinquenta por cento', 'alimentacao', 'percentual', 50);
  SELECT bt.percentual_desconto INTO v_pct FROM public.beneficios_tipos bt
  WHERE bt.tenant_id = v_t AND bt.nome = 'QA — VR cinquenta por cento';

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: existe parâmetro de limite do PAT/CCT em algum lugar?';
  r.esperado := 'Teto parametrizado e versionado, aplicado na competência';
  v_param := coalesce(public.qa_col_existe(NULL, '%limite%pat%'),
                      public.qa_col_existe('beneficios_tipos', '%limite%'),
                      public.qa_col_existe('beneficios_tipos', '%teto%'));

  IF v_pct = 50 AND v_param IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o VR aceitou desconto de 50% e não existe NENHUM parâmetro de '
             || 'limite (nem coluna de teto no catálogo, nem tabela de parâmetros do '
             || 'PAT): a participação do trabalhador — que o PAT limita como condição do '
             || 'benefício fiscal — é o que o operador digitar. Desconto acima do limite '
             || 'descaracteriza o VR (vira salário, com INSS/FGTS retroativos) e derruba '
             || 'o incentivo; a Lei 14.442/22 ainda veda rebate ao empregador, e o '
             || 'sistema não tem onde registrar essa vedação por fornecedora. Correção: '
             || 'teto parametrizado [VAL] por PAT/CCT, versionado por competência, '
             || 'validado no catálogo e na aplicação do desconto.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Limite tratado (percentual: %s; parâmetro: %s).',
                       coalesce(v_pct::text, 'recusado'), coalesce(v_param, 'na gravação'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ben_020()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a adesão vira rubrica na Folha com incidência parametrizada?';
  r.esperado := 'Rubricas (desconto + patronal) geradas por competência, com incidência e memória';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    -- vínculo genérico/limpeza citam a tabela sem ser motor de benefício
    AND p.proname NOT IN ('colaborador_tem_vinculos', 'excluir_colaborador_forcado')
    AND p.prosrc ILIKE '%beneficios_colaboradores%'
    AND (p.prosrc ILIKE '%folha%' OR p.prosrc ILIKE '%rubrica%');

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: não existe ponte entre os benefícios e a Folha — nenhuma função '
             || 'lê beneficios_colaboradores para gerar rubricas de desconto/patronal na '
             || 'competência: o desconto vive parado no cadastro e entra na folha na mão, '
             || 'a cada mês, para cada colaborador. Sem o motor de incidências por '
             || 'benefício (RF-009), a natureza de cada rubrica (VT/VR não integram; '
             || 'utilidade do art. 458 pode integrar) fica na memória do operador — e '
             || 'benefício mal classificado vira salário com passivo previdenciário '
             || 'retroativo. A infraestrutura do outro lado existe (folha_rubricas, '
             || 'folha_itens, memória da família FOLHA). Correção: geração automática das '
             || 'rubricas por competência a partir das adesões ativas, com incidência '
             || 'parametrizada e versionada e memória de cálculo (padrão FOLHA-080).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Ponte com a Folha presente: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ben_030()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_tab text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): existe estrutura de dependentes de benefício?';
  r.esperado := 'Dependentes com idade/parentesco/documentação validados, refletindo na operadora e no IRRF';
  SELECT string_agg(table_name, ', ') INTO v_tab
  FROM information_schema.tables
  WHERE table_schema = 'public'
    AND (table_name ILIKE '%dependente%');

  IF v_tab IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a estrutura de dependentes NÃO EXISTE — nenhuma tabela de '
             || 'dependentes no banco. Sem ela, o plano de saúde familiar não tem onde '
             || 'registrar as vidas (a fatura da operadora cobra por dependente e o '
             || 'sistema não sabe quantos são — a conciliação do BEN-042 nasce cega), o '
             || 'IRRF do titular não reflete os dependentes, e a regra de elegibilidade '
             || '(idade-limite, parentesco, documentação — RN-007) não tem onde morar. '
             || 'Correção: tabela de dependentes por titular (nome, nascimento, '
             || 'parentesco, documento, benefícios vinculados), com validação de regra na '
             || 'inclusão, alerta de idade a vencer e reflexo nas movimentações da '
             || 'operadora e no IRRF.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Estrutura de dependentes presente: %s.', v_tab);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ben_040()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text; v_tab text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a rescisão calcula a manutenção do plano (arts. 30/31)?';
  r.esperado := 'Elegibilidade, período (1/3; mín. 6, máx. 24 meses), prazo de 30 dias e custo integral tratados';
  SELECT string_agg(table_name, ', ') INTO v_tab
  FROM information_schema.tables
  WHERE table_schema = 'public' AND table_name ILIKE '%manutencao%plano%';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%art%30%plano%' OR p.prosrc ILIKE '%manutencao%plano%'
         OR (p.prosrc ILIKE '%9656%'));

  IF v_tab IS NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: os arts. 30/31 da Lei 9.656/98 não existem no sistema — nenhuma '
             || 'tabela ou função trata a manutenção do plano do demitido sem justa causa '
             || '(1/3 do tempo de contribuição, mínimo 6 e máximo 24 meses, custo '
             || 'integral) nem do aposentado (10+ anos: vitalício), e ninguém controla o '
             || 'PRAZO DE 30 DIAS da opção — o mais perigoso do pós-rescisão: perder a '
             || 'comunicação é ação judicial quase certa, com reintegração ao plano e '
             || 'danos. O desligamento da casa é rico em pendências (família DESL) e não '
             || 'tem este item. Correção: na rescisão sem justa causa de titular '
             || 'contributário, calcular elegibilidade/período/custo, gerar a comunicação '
             || 'com prazo controlado e registrar a opção do ex-empregado (termo no '
             || 'módulo Documentos).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Manutenção tratada (tabelas: %s; funções: %s).',
                       coalesce(v_tab, '—'), coalesce(v_fns, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ben_042()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_tab text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): existem operadoras, movimentações e faturas com conciliação?';
  r.esperado := 'Fatura importada, comparada (vidas/valores/coparticipação) e paga só depois de conciliada';
  SELECT string_agg(table_name, ', ') INTO v_tab
  FROM information_schema.tables
  WHERE table_schema = 'public'
    AND (table_name ILIKE '%operadora%' OR table_name ILIKE '%fatura%'
         OR table_name ILIKE 'beneficios%movim%');

  IF v_tab IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o lado das operadoras não existe — sem cadastro de '
             || 'operadoras/planos (tabelas de preço por faixa etária, coparticipação), '
             || 'sem movimentações de inclusão/alteração/exclusão (o RF-012) e sem '
             || 'faturas: a conciliação mensal (vidas cobradas × vidas ativas, '
             || 'coparticipação por uso) não tem onde acontecer, e a fatura é paga na '
             || 'confiança. Vida fantasma de ex-colaborador cobrada por meses é o custo '
             || 'invisível clássico dos benefícios — exatamente o que a RN-013 manda '
             || 'bloquear ("fatura só é paga após conciliação"). Correção: estrutura '
             || 'operadora/plano/movimentação/fatura com conciliação obrigatória, glosa '
             || 'registrada e ação no Plano de Ação por divergência.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Estrutura de operadoras/faturas presente: %s.', v_tab);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ben_050()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o benefício consome os dias efetivos do Ponto?';
  r.esperado := 'VT/VR proporcionais aos dias trabalhados; afastamento ajusta a concessão';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    -- vínculo genérico/limpeza citam a tabela sem ser motor de benefício
    AND p.proname NOT IN ('colaborador_tem_vinculos', 'excluir_colaborador_forcado')
    AND p.prosrc ILIKE '%beneficios_colaboradores%'
    AND (p.prosrc ILIKE '%ponto%' OR p.prosrc ILIKE '%dias%'
         OR p.prosrc ILIKE '%afastament%');

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o benefício não conversa com o Ponto — beneficios_colaboradores '
             || 'guarda valor e desconto FIXOS e nenhuma função os ajusta pelos dias '
             || 'efetivos da competência: colaborador afastado há dois meses segue com VT '
             || 'e VR cheios (custo indevido) ou tem o benefício cortado na mão (erro '
             || 'para o outro lado). O Ponto já apura os dias por colaborador '
             || '(ponto_saldo_dias_competencia_bruto, usada por férias) — o dado existe, '
             || 'o consumo não. Correção: apuração mensal do benefício proporcional aos '
             || 'dias efetivos (RN-011), com a regra de afastamento parametrizada por '
             || 'benefício/CCT e memória de cálculo.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Proporcionalidade presente: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ben_051()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cct text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a camada CCT alcança os benefícios?';
  r.esperado := 'Benefício/valor de CCT aplicados pela vigência, com tabela versionada';
  SELECT string_agg(table_name, ', ') INTO v_cct
  FROM information_schema.tables
  WHERE table_schema = 'public'
    AND (table_name ILIKE '%cct%' OR table_name ILIKE '%convenc%')
    AND table_name NOT ILIKE 'psicossocial%';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%beneficio%'
    AND (p.prosrc ILIKE '%cct%' OR p.prosrc ILIKE '%convenc%');

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO (a camada existe, não chega aqui): a parametrização por '
             || 'instrumento coletivo já é realidade no ponto e na folha (%s — com '
             || 'vigência por competência, PONTO-386), mas NADA a liga aos benefícios: '
             || 'cesta básica, VR mínimo e seguro de vida instituídos pela convenção da '
             || 'categoria não têm onde ser parametrizados por vigência — beneficios_'
             || 'tipos é um catálogo plano, sem instrumento nem versão. CCT nova exige '
             || 'reconfiguração manual, e a anterior se perde (competência antiga fica '
             || 'sem prova do valor da época). Correção: vínculo benefício × instrumento '
             || 'coletivo × vigência, versionado, aplicado pela data — o padrão que '
             || 'ponto_cct_config/folha_cct já praticam.',
             coalesce(v_cct, 'ponto_cct_config, folha_cct'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('CCT alcança os benefícios por: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ben_060()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_col text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a adesão gera termo e o arquiva no módulo Documentos?';
  r.esperado := 'Termo assinado com trilha, vinculado à adesão e arquivado com metadados';
  v_col := coalesce(public.qa_col_existe('beneficios_colaboradores', '%termo%'),
                    public.qa_col_existe('beneficios_colaboradores', '%documento%'),
                    public.qa_col_existe('beneficios_colaboradores', '%assinatura%'));
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.proname NOT IN ('colaborador_tem_vinculos', 'excluir_colaborador_forcado')
    AND p.prosrc ILIKE '%beneficio%'
    AND (p.prosrc ILIKE '%termo%' OR p.prosrc ILIKE '%assinatura%');

  IF v_col IS NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a adesão não gera termo — sem coluna de vínculo com documento em '
             || 'beneficios_colaboradores e sem função que gere/colha/arquive o termo de '
             || 'opção ou adesão. O padrão da casa existe e é maduro (assinatura com '
             || 'trilha em ADM-070/DESL-082; guarda com metadados no módulo Documentos) — '
             || 'os benefícios ficaram fora dele. Sem termo: a opção do VT não se prova '
             || '(BEN-010), as condições do plano e os dependentes aceitos não se provam, '
             || 'e a manutenção dos arts. 30/31 (BEN-040) não tem onde registrar a opção '
             || 'do ex-empregado. Correção: termo gerado na adesão/recusa, assinado com '
             || 'trilha e arquivado no Documentos, com o id do documento na adesão '
             || '(RN-012).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Termo tratado (vínculo: %s; funções: %s).',
                       coalesce(v_col, '—'), coalesce(v_fns, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ben_070()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_tab text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): existe estrutura de PLR (acordo, apuração, limite de 2/ano)?';
  r.esperado := 'PLR só é isenta com acordo prévio válido; IR em tabela própria; máx. 2 pagamentos/ano';
  SELECT string_agg(table_name, ', ') INTO v_tab
  FROM information_schema.tables
  WHERE table_schema = 'public' AND table_name ILIKE '%plr%';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%plr%';

  IF v_tab IS NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a PLR não existe no sistema — sem tabela de programa/acordo, sem '
             || 'apuração, sem controle dos dois pagamentos anuais e do IR em tabela '
             || 'própria. O risco é específico: pagamento rotulado de PLR sem acordo '
             || 'prévio válido (comissão paritária + sindicato, Lei 10.101/2000) é '
             || 'salário disfarçado — INSS, FGTS e reflexos retroativos sobre cada '
             || 'centavo, e é a Receita quem cobra. Enquanto a empresa não tiver '
             || 'programa, tudo bem não ter estrutura; o perigo é pagar "PLR" pela folha '
             || 'sem o cinto. Correção (quando houver programa): registro do acordo como '
             || 'condição do pagamento isento, limite de 2/ano e IR próprio (RF-014).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Estrutura de PLR presente (tabelas: %s; funções: %s).',
                       coalesce(v_tab, '—'), coalesce(v_fns, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ben_071()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_tab text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): existe controle de consignado e margem consignável?';
  r.esperado := 'Desconto de consignado validado contra a margem; excedente bloqueado';
  SELECT string_agg(table_name, ', ') INTO v_tab
  FROM information_schema.tables
  WHERE table_schema = 'public' AND (table_name ILIKE '%consign%' OR table_name ILIKE '%margem%');
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%consign%' OR p.prosrc ILIKE '%margem_consign%');

  IF v_tab IS NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: consignado e margem consignável não existem no sistema — sem '
             || 'cadastro de convênios, sem cálculo de margem sobre a remuneração '
             || 'disponível, sem trava de desconto. Se um convênio de consignado for '
             || 'operado hoje, o desconto entra na folha como lançamento manual sem teto: '
             || 'acima da margem é ilegal (Lei 10.820/2003) e derruba o líquido do '
             || 'colaborador abaixo do vital — e salário reduzido por afastamento exige '
             || 'recálculo da margem que ninguém fará à mão. Correção (quando houver '
             || 'convênio): margem consignável parametrizada [VAL], validação de cada '
             || 'contrato contra ela e bloqueio do excedente com alerta (RF-015).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Consignado tratado (tabelas: %s; funções: %s).',
                       coalesce(v_tab, '—'), coalesce(v_fns, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ben_080()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_aberta int; v_perfil int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): quem consegue LER as adesões de benefícios?';
  r.esperado := 'Leitura restrita por perfil (LGPD art. 11) — plano de saúde é dado de saúde por inferência';
  SELECT count(*) INTO v_aberta FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'beneficios_colaboradores'
    AND cmd = 'SELECT' AND policyname ILIKE '%tenant%';
  SELECT count(*) INTO v_perfil FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'beneficios_colaboradores'
    AND policyname ILIKE '%perfil%';

  IF v_aberta > 0 AND v_perfil = 0 THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: beneficios_colaboradores tem leitura aberta ao tenant '
             || '("Usuários podem ver benefícios do tenant") e NENHUMA política '
             || 'perfil_restringe_leitura_* — qualquer usuário lista quem tem plano de '
             || 'saúde, valores e descontos de todos os colegas. Adesão a plano é dado '
             || 'de saúde por inferência (LGPD art. 11), e a camada de perfil da casa já '
             || 'protege ~20 tabelas sensíveis (atestados, eventos_saude, '
             || 'folha_rescisoes...) — os benefícios ficaram fora. Mesma família do '
             || 'FOLHA-090 (salários) e do EPI-041 (biometria). Correção: política '
             || 'RESTRICTIVE por perfil na tabela, com o colaborador vendo apenas as '
             || 'próprias adesões, e log de consulta quando a estrutura de saúde '
             || 'crescer (dependentes, coparticipação).';
  ELSIF v_aberta = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'A leitura aberta ao tenant não existe mais — política revista.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Camada de perfil presente (%s política(s)).', v_perfil);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_colab_002()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_p uuid;
  v_por_nome int; v_por_cpf_limpo int; v_por_cpf_fmt int;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Criar colaborador com nome e CPF conhecidos';
  r.esperado := 'Encontravel por nome parcial, por CPF sem e com formatacao';
  INSERT INTO public.usuarios_base (tenant_id, nome_completo, email_principal, cpf, tipo_usuario, status)
  VALUES (v_t, '[QA-002] Joaquim Aparecido Testonildo', 'qa.002.1@sandbox.invalid',
          '99900000188', 'colaborador', 'ativo')
  RETURNING id INTO v_p;

  r.passo_ordem := 2;
  r.passo_acao := 'Buscar pelo nome parcial ("Testonildo")';
  SELECT count(*) INTO v_por_nome
  FROM public.usuarios_base
  WHERE tenant_id = v_t AND nome_completo ILIKE '%Testonildo%';

  r.passo_ordem := 3;
  r.passo_acao := 'Buscar pelo CPF sem formatacao (99900000188)';
  SELECT count(*) INTO v_por_cpf_limpo
  FROM public.usuarios_base
  WHERE tenant_id = v_t AND regexp_replace(cpf, '[^0-9]', '', 'g') = '99900000188';

  r.passo_ordem := 4;
  r.passo_acao := 'Buscar pelo CPF formatado (999.000.001-88)';
  -- normaliza os dois lados: o gravado e o buscado
  SELECT count(*) INTO v_por_cpf_fmt
  FROM public.usuarios_base
  WHERE tenant_id = v_t
    AND regexp_replace(cpf, '[^0-9]', '', 'g') = regexp_replace('999.000.001-88', '[^0-9]', '', 'g');

  IF v_por_nome >= 1 AND v_por_cpf_limpo >= 1 AND v_por_cpf_fmt >= 1 THEN
    r.situacao := 'passou';
    r.obtido := 'Encontrado pelas 3 vias: nome parcial, CPF limpo e CPF formatado.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Falha na busca — nome:%s, cpf_limpo:%s, cpf_fmt:%s (esperado >=1 em cada).',
                       v_por_nome, v_por_cpf_limpo, v_por_cpf_fmt);
  END IF;
  r.detalhe := jsonb_build_object('por_nome', v_por_nome,
                                  'por_cpf_limpo', v_por_cpf_limpo,
                                  'por_cpf_formatado', v_por_cpf_fmt);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_colab_030()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_est text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a importação de colaboradores existe como processo no banco?';
  r.esperado := 'Reimportar a mesma planilha identifica existentes e devolve a decisão — nunca duplica';
  v_est := coalesce(public.qa_fns_com('%importa%colaborador%'), public.qa_fns_com('%planilha%'));
  IF v_est IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a importação de colaboradores não existe como processo no banco — sem '
             || 'função de conciliação, a tela grava linha a linha e reimportar a mesma '
             || 'planilha duplicaria em silêncio (só a trava de CPF por admissão ativa segura '
             || 'parte). O desenho correto: detectar existentes pelo CPF, listar e devolver a '
             || 'decisão ao usuário (manter × substituir). Correção: função de importação com '
             || 'staging e relatório de conflitos.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Processo de importação presente: %s.', v_est);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_colab_031()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_est text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a opção "manter os dados atuais" existe na reimportação?';
  r.esperado := 'Colaborador já existente com escolha "manter" preserva o que foi alterado no sistema';
  v_est := public.qa_fns_com('%manter%colaborador%');
  IF v_est IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: sem o processo de importação (COLAB-030), a escolha "manter" não '
             || 'existe. O risco que ela previne: a planilha envelhece — depois da importação '
             || 'inicial, o RH corrige dados NO SISTEMA; uma reimportação ingênua sobrescreve '
             || 'as correções com os dados velhos da planilha. "Manter" preserva o atual e '
             || 'ignora a planilha para os existentes.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Opção presente: %s.', v_est);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_colab_032()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_est text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a opção "substituir" atualiza no lugar (UPDATE), sem recriar?';
  r.esperado := 'Substituir mantém o id da pessoa — apagar e recriar deixa todo o histórico órfão';
  v_est := public.qa_fns_com('%substitu%colaborador%');
  IF v_est IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: sem o processo de importação (COLAB-030), a escolha "substituir" não '
             || 'existe — e é a mais perigosa de improvisar: se a tela um dia apagar e '
             || 'recriar, o id muda e TODO o histórico da pessoa (ponto, férias, atestados, '
             || 'documentos) vira órfão. Substituir é UPDATE no registro existente, nunca '
             || 'DELETE+INSERT. Registrado aqui para o desenho da funcionalidade nascer certo.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Opção presente: %s.', v_est);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_dado_010()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_id uuid; v_tipo text;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Cadastrar empresa com tipo de pessoa = "mei"';
  r.esperado:='Idealmente recusado — so pj e pf sao valores previstos';
  BEGIN
    INSERT INTO public.empresa_cadastro (tenant_id, razao_social, cnpj, tipo_pessoa)
    VALUES (v_t, '[QA] Tipo Pessoa Invalido', '11333444000343', 'mei') RETURNING id INTO v_id;
    SELECT tipo_pessoa INTO v_tipo FROM public.empresa_cadastro WHERE id=v_id;
    r.situacao:='falhou';
    r.obtido:=format('O BANCO ACEITOU tipo_pessoa = "%s". So pj e pf sao previstos (MEI e uma pj). O tipo decide qual documento identifica a empresa.', v_tipo);
  EXCEPTION WHEN check_violation THEN
    r.situacao:='passou'; r.obtido:='Recusado: tipo de pessoa restrito a pj ou pf.';
  END;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_desl_013()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_tem_estado boolean; v_col text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): existe o estado "desligamento programado" (data futura)?';
  r.esperado := 'Aviso prévio trabalhado projeta o término para o futuro — registro ≠ efetivação';
  SELECT EXISTS (
    SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname = 'admissao_status' AND e.enumlabel ILIKE '%program%'
  ) INTO v_tem_estado;
  v_col := public.qa_col_existe('admissoes', '%data_deslig%');

  IF NOT v_tem_estado THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: não existe o estado intermediário "desligamento programado" — o '
             || 'vínculo vai direto de ativo para desligado%s. No aviso prévio trabalhado, o '
             || 'contrato segue vivo por até 30 dias após o registro: o colaborador ainda '
             || 'marca ponto, acumula férias e só na DATA é efetivado. Sem o estado, ou se '
             || 'desliga antecipado (corta acesso de quem ainda trabalha) ou se registra '
             || 'depois (perde o aviso). Correção: estado programado com data futura e '
             || 'efetivação automática na data.',
             CASE WHEN v_col IS NULL THEN ' e nem data de desligamento futura há onde guardar' ELSE '' END);
  ELSE
    r.situacao := 'passou';
    r.obtido := 'O estado de desligamento programado existe.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_desl_015()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_pgto text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o pagamento das verbas é registrado e conferido contra o prazo?';
  r.esperado := 'Data de pagamento gravada; atraso além do 10º dia acusa a multa do §8º; dia não útil antecipa a data-alvo';
  v_pgto := coalesce(public.qa_col_existe('folha_rescisoes', '%data_pagamento%'),
                     public.qa_col_existe('folha_rescisoes', '%pago_em%'),
                     public.qa_col_existe('admissoes', '%pagamento_rescis%'));
  -- só conta função que fale do PRAZO/MULTA da rescisão em si — "desligamento
  -- + prazo" solto pega o prazo do EXAME demissional (exame_demissional_pendencias)
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.proname NOT ILIKE '%exame%' AND p.proname NOT ILIKE '%demissional%'
    AND (p.prosrc ILIKE '%477%'
         OR (p.prosrc ILIKE '%rescis%' AND p.prosrc ILIKE '%multa%')
         OR (p.prosrc ILIKE '%data_pagamento%' AND p.prosrc ILIKE '%desligamento%'));

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO (metade boa, metade ausente): folha_rescisoes registra a data '
             || 'de pagamento (%s) — a matéria-prima existe —, mas NINGUÉM a confere contra '
             || 'o limite do art. 477: nenhuma função compara pagamento × (término + 10 '
             || 'dias), acusa o atraso ou projeta a multa do §8º (um salário ao empregado). '
             || 'O DESL-014 já provou que a data-limite aparece na tela (regra RNDES24, no '
             || 'React); do lado do banco, pagamento no 11º dia entra igual ao do 5º e o '
             || 'painel "rescisão no prazo" (seção 29) segue sem fonte. Também não há motor '
             || 'de antecipação por dia não útil (mesmo vazio do DEC13-031). Correção: '
             || 'conferência pagamento × limite (com antecipação via tabela feriados) + '
             || 'multa projetada e alerta no atraso.',
             coalesce(v_pgto, 'campo de data de pagamento AUSENTE'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Controle presente (campo: %s; funções: %s).',
                       coalesce(v_pgto, '—'), v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_desl_025()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_adm uuid; v_aceitou boolean := false; v_col text;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Desligar por JUSTA CAUSA direto no banco, sem validação jurídica nenhuma';
  r.esperado := 'Retido — o enquadramento do art. 482 exige aprovação de perfil competente com evidências';
  INSERT INTO public.admissoes
    (tenant_id, nome_completo, cpf, email, cargo, status, data_admissao)
  VALUES (v_t, '[QA-DESL-025] Colaborador', public.qa_cpf(8025),
          'qa.desl025@sandbox.invalid', 'Operador', 'concluido', CURRENT_DATE - 700)
  RETURNING id INTO v_adm;
  BEGIN
    UPDATE public.admissoes SET
      status = 'desligado', data_desligamento = CURRENT_DATE,
      motivo_desligamento = 'com_justa_causa'
    WHERE id = v_adm;
    v_aceitou := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_aceitou := false; END;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: existe onde registrar a validação (quem aprovou o enquadramento)?';
  r.esperado := 'Campo/fluxo de aprovação jurídica com evidências e trilha';
  v_col := coalesce(public.qa_col_existe('admissoes', '%validacao%'),
                    public.qa_col_existe('admissoes', '%aprovad%'),
                    public.qa_col_existe('admissoes', '%juridic%'));

  IF v_aceitou AND v_col IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a justa causa entrou SEM RITO — o banco aceitou o desligamento pelo '
             || 'art. 482 sem validação de ninguém, e não existe campo para registrar quem '
             || 'aprovou o enquadramento nem as evidências que o sustentam. Justa causa é a '
             || 'modalidade que mais reverte em juízo: revertida, vira dispensa sem justa '
             || 'causa com todas as verbas (aviso, multa de 40%, seguro-desemprego) devidas '
             || 'de uma vez. A matriz do documento (seção 6) reserva a validação ao jurídico. '
             || 'Correção: transição para justa causa/indireta condicionada a registro de '
             || 'validação (validador + data + evidências), no mesmo desenho da dupla '
             || 'aprovação já pedida para reabertura.';
  ELSIF NOT v_aceitou THEN
    r.situacao := 'passou';
    r.obtido := 'A justa causa sem validação foi retida na gravação.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Aceita com campo de validação disponível (%s) — conferir a '
                       || 'obrigatoriedade no fluxo.', v_col);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_desl_057()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_tab text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a guia rescisória do FGTS Digital tem estrutura?';
  r.esperado := 'Guia com base, percentual da modalidade e prazo; fila de reprocessamento na indisponibilidade';
  -- estrutura ESPECÍFICA de FGTS: hub_guias (Hub Contábil) é guia genérica
  -- digitada à mão (tipo texto livre) — não é geração de guia rescisória
  SELECT string_agg(table_name, ', ') INTO v_tab
  FROM information_schema.tables
  WHERE table_schema = 'public' AND table_name ILIKE '%fgts%';
  v_fns := public.qa_fns_com('%fgts%');

  IF v_tab IS NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o FGTS Digital não existe no banco — nenhuma tabela ou função '
             || 'específica de FGTS. A multa (40%/20%) é calculada no React '
             || '(calcularRescisao) e gravada como número em folha_rescisoes; o que existe '
             || 'de "guia" é o hub_guias do Hub Contábil, registro GENÉRICO digitado à mão '
             || '(tipo em texto livre, valor e vencimento manuais) — serve para anotar que '
             || 'a guia existe, não para GERÁ-LA com base, percentual da modalidade e prazo '
             || 'do FGTS rescisório. E não há fila de contingência para indisponibilidade '
             || 'do serviço (RNF-008): da apuração ao recolhimento, o caminho vive no '
             || 'navegador do DP. Correção: estrutura própria da guia rescisória (base, '
             || 'percentual, prazo, status, comprovante) alimentada pela rescisão + fila de '
             || 'reprocessamento, no desenho da transmissão do eSocial. Fluxo vigente do '
             || 'FGTS Digital é [VAL] (seção 30).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Estrutura específica de FGTS presente (tabelas: %s; funções: %s).',
                       coalesce(v_tab, '—'), coalesce(v_fns, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_desl_074()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cct boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): as estabilidades conhecem cláusulas de CCT?';
  r.esperado := 'Estabilidade pré-aposentadoria vem da CCT (período/condições variam por categoria)';
  SELECT bool_or(p.prosrc ILIKE '%cct%' OR p.prosrc ILIKE '%convencao%' OR p.prosrc ILIKE '%coletiv%')
    INTO v_cct
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'estabilidades_vigentes';
  IF NOT coalesce(v_cct, false) THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a verificação de estabilidades (estabilidades_vigentes) só conhece as '
             || 'hipóteses LEGAIS — não existe cadastro de cláusulas de CCT no domínio de '
             || 'desligamento (a única tabela de CCT do sistema, ponto_cct_config, guarda só '
             || 'parâmetros de jornada). A estabilidade pré-aposentadoria é tipicamente '
             || 'convencional: sem a cláusula cadastrada, o sistema não avisa e a demissão de '
             || 'um estável convencional vira reintegração. Correção: cadastro de cláusulas '
             || 'de estabilidade por CCT/categoria com vigência, somado às legais.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'As estabilidades consultam cláusulas convencionais.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_desl_081()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_est text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a exigência de homologação sindical tem onde ser registrada?';
  r.esperado := 'Pós-reforma, homologação só é exigível por CCT — o sistema precisa saber de qual categoria';
  v_est := public.qa_col_existe('admissoes', '%homolog%');
  IF v_est IS NOT NULL AND public.qa_fns_com('%homolog%') IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO PARCIAL: os campos de registro existem (%s) — dá para ANOTAR a '
             || 'homologação feita —, mas nada torna a homologação EXIGÍVEL: nenhuma função '
             || 'verifica se a categoria do colaborador tem cláusula de CCT exigindo o rito '
             || '(mesma raiz do DESL-074: não há cadastro de cláusulas coletivas). O '
             || 'desligamento de categoria com homologação obrigatória conclui sem aviso. '
             || 'Correção: flag de exigência na cláusula da CCT/categoria, travando ou '
             || 'alertando o checklist de desligamento.', v_est);
  ELSIF v_est IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: homologação não existe no sistema — nem campo, nem verificação. '
             || 'Correção: registro + exigência por cláusula de CCT/categoria.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Homologação registrável e verificada: %s.', v_est);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_desl_083()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_adm uuid; v_aceitou boolean := false; v_col text;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Desligar colaborador de 17 anos sem nenhum dado de assistente legal';
  r.esperado := 'Retido — a quitação final do menor exige assistência do responsável (art. 439)';
  INSERT INTO public.admissoes
    (tenant_id, nome_completo, cpf, email, cargo, status, data_admissao, data_nascimento)
  VALUES (v_t, '[QA-DESL-083] Menor', public.qa_cpf(8083),
          'qa.desl083@sandbox.invalid', 'Aprendiz', 'concluido',
          CURRENT_DATE - 300, CURRENT_DATE - interval '17 years')
  RETURNING id INTO v_adm;
  BEGIN
    UPDATE public.admissoes SET
      status = 'desligado', data_desligamento = CURRENT_DATE,
      motivo_desligamento = 'pedido_demissao'
    WHERE id = v_adm;
    v_aceitou := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_aceitou := false; END;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: existe onde registrar o assistente do menor na quitação?';
  r.esperado := 'Campo de responsável/assistente exigido quando a idade no término é < 18';
  v_col := coalesce(public.qa_col_existe(NULL, '%assistente%'),
                    public.qa_col_existe(NULL, '%responsavel_legal%'));

  IF v_aceitou AND v_col IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o menor de 18 foi desligado sem assistência — o banco não olhou a '
             || 'data de nascimento e não existe campo de assistente/responsável legal em '
             || 'lugar nenhum do sistema. O art. 439 permite ao menor assinar recibos do '
             || 'dia a dia, mas a QUITAÇÃO FINAL sem o responsável é nula: todas as verbas '
             || 'podem ser rediscutidas como se nunca quitadas. A idade já está no cadastro '
             || '(mesma fonte do ADM-030). Correção: quando idade no término < 18, exigir '
             || 'registro do assistente (nome/CPF/parentesco) e a assinatura dele junto à '
             || 'do menor no termo de quitação.';
  ELSIF NOT v_aceitou THEN
    r.situacao := 'passou';
    r.obtido := 'O desligamento do menor sem assistente foi retido.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Aceito com estrutura de assistente disponível (%s) — conferir a '
                       || 'exigência no fluxo de quitação.', v_col);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_desl_093()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_col text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a transmissão do S-2299 tem prazo projetado e vigiado?';
  r.esperado := 'Data-limite = mín(pagamento, término + 10 dias); aproximação alerta; atraso é acusado';
  IF to_regclass('public.esocial_transmissoes') IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A tabela de transmissões do eSocial não existe nesta base.';
    RETURN r;
  END IF;
  v_col := coalesce(public.qa_col_existe('esocial_transmissoes', '%prazo%'),
                    public.qa_col_existe('esocial_transmissoes', '%data_limite%'),
                    public.qa_col_existe('esocial_transmissoes', '%vencimento%'));
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%2299%' AND p.prosrc ILIKE '%prazo%');

  IF v_col IS NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o S-2299 não tem relógio — esocial_transmissoes não guarda prazo '
             || 'nem data-limite (só status e retorno), e nenhuma função projeta o '
             || 'vencimento do evento de desligamento. O prazo tem regra dupla: até 10 dias '
             || 'do desligamento, ANTECIPADO se o pagamento das verbas vier antes — dois '
             || 'relógios, vence o primeiro. Sem a projeção, a transmissão tardia entra '
             || 'como se regular fosse e a multa por atraso de obrigação acessória chega '
             || 'sem aviso. Somado ao DESL-091 (o evento do desligamento nem chega à fila), '
             || 'o quadro é: sem evento E sem prazo. Correção: data-limite calculada na '
             || 'criação do evento + alertas de aproximação + marcação explícita de FORA '
             || 'DO PRAZO na transmissão tardia.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Prazo controlado (campo: %s; funções: %s).',
                       coalesce(v_col, '—'), coalesce(v_fns, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_desl_094()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_unq text; v_trad text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a fila do eSocial tem anti-duplicidade e tradução de rejeição?';
  r.esperado := 'Reenvio corrigido retifica (nunca segundo S-2299 do mesmo vínculo) e a rejeição vira instrução';
  IF to_regclass('public.esocial_transmissoes') IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A tabela de transmissões do eSocial não existe nesta base.';
    RETURN r;
  END IF;
  SELECT string_agg(conname, ', ') INTO v_unq
  FROM pg_constraint WHERE conrelid = 'public.esocial_transmissoes'::regclass AND contype = 'u';
  v_trad := coalesce(public.qa_fns_com('%rejeic%esocial%'), public.qa_fns_com('%esocial%rejei%'));

  IF v_unq IS NULL AND v_trad IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO (quarto da série ADM-093 / FERIAS-081 / DEC13-050, agora no evento '
             || 'que ENCERRA o vínculo): esocial_transmissoes segue sem unicidade — o mesmo '
             || 'S-2299 pode ser gravado e enviado duas vezes — e nenhuma função traduz '
             || 'rejeições: o retorno técnico chega cru e o reenvio fica por conta do '
             || 'operador. Desligamento duplicado no governo é o pior da série: trava os '
             || 'eventos futuros do CPF (readmissão inclusive) até alguém excluir o evento '
             || 'errado no portal. Correção: chave natural (vínculo + tipo + competência) '
             || 'na fila + rotina que interpreta a rejeição e conduz retificação — uma vez, '
             || 'para as quatro famílias que dependem dela.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Proteções presentes (unicidade: %s; tradução: %s).',
                       coalesce(v_unq, '—'), coalesce(v_trad, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_desl_105()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_col text; v_fns text; v_unq text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a rescisão complementar tem onde existir?';
  r.esperado := 'Diferença apurada como registro próprio, vinculado à rescisão original, com reflexo no eSocial';
  v_col := coalesce(public.qa_col_existe('folha_rescisoes', '%complementar%'),
                    public.qa_col_existe('folha_rescisoes', '%origem%'),
                    public.qa_col_existe('folha_rescisoes', '%rescisao_pai%'));
  v_fns := public.qa_fns_com('%complementar%');
  SELECT string_agg(conname, ', ') INTO v_unq
  FROM pg_constraint WHERE conrelid = 'public.folha_rescisoes'::regclass AND contype = 'u';

  IF v_col IS NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a rescisão complementar não tem onde viver — folha_rescisoes '
             || 'não tem marcação de complementar nem vínculo a uma rescisão de origem, e '
             || 'nenhuma função apura diferenças. O agravante: a tabela também não tem '
             || 'unicidade (%s), então uma segunda rescisão do mesmo colaborador entra '
             || 'como linha solta — indistinguível de duplicata, de erro ou de '
             || 'complementar de verdade. Dissídio retroativo é rotina anual em categoria '
             || 'organizada: sem a estrutura, cada reajuste vira ou passivo ignorado ou '
             || 'edição da rescisão quitada (fraude de trilha). Correção: tipo '
             || '(original/complementar) + referência à rescisão-mãe + apuração da '
             || 'diferença com memória própria e S-2299 complementar.',
             coalesce('constraints: ' || v_unq, 'nenhuma constraint de unicidade'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Estrutura presente (campos: %s; funções: %s).',
                       coalesce(v_col, '—'), coalesce(v_fns, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_desl_106()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_adm uuid; v_reativou boolean := false; v_status text; v_data date;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Desligar um colaborador e depois "reativá-lo" com UPDATE direto, sem rito nenhum';
  r.esperado := 'Bloqueado — reversão exige fluxo próprio: motivo, dupla aprovação, estorno e tratamento do eSocial';
  INSERT INTO public.admissoes
    (tenant_id, nome_completo, cpf, email, cargo, status, data_admissao)
  VALUES (v_t, '[QA-DESL-106] Colaborador', public.qa_cpf(8106),
          'qa.desl106@sandbox.invalid', 'Operador', 'concluido', CURRENT_DATE - 600)
  RETURNING id INTO v_adm;
  UPDATE public.admissoes SET
    status = 'desligado', data_desligamento = CURRENT_DATE - 20,
    motivo_desligamento = 'sem_justa_causa'
  WHERE id = v_adm;

  BEGIN
    UPDATE public.admissoes SET
      status = 'concluido', data_desligamento = NULL, motivo_desligamento = NULL
    WHERE id = v_adm;
    v_reativou := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_reativou := false; END;

  r.passo_ordem := 2;
  r.passo_acao := 'Conferir o que sobrou do desligamento revertido';
  SELECT status::text, data_desligamento INTO v_status, v_data
  FROM public.admissoes WHERE id = v_adm;

  IF v_reativou AND v_status = 'concluido' AND v_data IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a reversão foi um UPDATE qualquer — o colaborador desligado voltou '
             || 'a "concluído" com data e motivo APAGADOS, sem aprovação, sem motivo de '
             || 'reversão, sem estorno das verbas e sem tratar o S-2299 (se transmitido, o '
             || 'governo continua com um desligamento que a empresa diz não existir). É a '
             || 'outra face do DESL-002: como o desligamento é colunas na admissão e não '
             || 'evento, desfazê-lo é apagar história. Correção: fluxo de reversão com '
             || 'motivo + dupla aprovação, evento de desligamento preservado como '
             || 'histórico, estorno rastreado das verbas e exclusão/retificação formal do '
             || 'evento no eSocial (mesma disciplina do FERIAS-054 e DEC13-070).';
  ELSIF NOT v_reativou THEN
    r.situacao := 'passou';
    r.obtido := 'A reativação direta foi bloqueada — reversão só por fluxo próprio.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Reativação controlada (status: %s; histórico preservado: %s).',
                       v_status, coalesce(v_data::text, 'apagado'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_desl_110()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_restr int; v_proprio int; v_perfil text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): as políticas de folha_rescisoes separam papel, equipe e o próprio?';
  r.esperado := 'Camada RESTRICTIVE por perfil; colaborador só o próprio dossiê; gestor só a equipe';
  SELECT count(*) INTO v_restr
  FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'folha_rescisoes'
    AND permissive = 'RESTRICTIVE';
  SELECT count(*) INTO v_proprio
  FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'folha_rescisoes'
    AND (qual ILIKE '%auth.uid%' OR qual ILIKE '%colaborador%uid%' OR qual ILIKE '%departamento%');
  SELECT string_agg(DISTINCT p.polname, ', ') INTO v_perfil
  FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
  WHERE c.relname = 'folha_rescisoes' AND p.polname ILIKE 'perfil_restringe%';

  IF v_restr = 0 AND v_proprio = 0 THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO (par do DEC13-071, agora no dado mais sensível do ciclo): '
             || 'folha_rescisoes tem só a política de tenant — qualquer usuário autenticado '
             || 'da empresa lê TODAS as rescisões: verbas, motivo do desligamento (justa '
             || 'causa inclusive) e, por tabela irmã, o rastro de saúde da estabilidade. A '
             || 'matriz do documento (seção 6) é explícita: colaborador só o próprio '
             || 'dossiê, gestor só a equipe, jurídico/DP/financeiro por papel. A tabela '
             || 'está fora da camada perfil_restringe_leitura_* que já protege as tabelas '
             || 'sensíveis do sistema (a rotina PERFIL-003 cobra exatamente isso de tabela '
             || 'nova). Correção: política RESTRICTIVE via perfil_permite_modulo + regra '
             || 'de próprio registro/equipe, no padrão das 20 tabelas já cobertas.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Camadas presentes (restritivas: %s; próprio/equipe: %s; perfil: %s).',
                       v_restr, v_proprio, coalesce(v_perfil, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_emp_051()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_emp uuid; v_antes int; v_depois int;
BEGIN
  v_emp := public.qa_empresa_com_cota('QA Cota Movimento', '19.131.243/0001-97', 100, NULL, NULL, NULL);
  SELECT total_colaboradores INTO v_antes FROM public.empresa_cadastro WHERE id = v_emp;

  r.passo_ordem := 1;
  r.passo_acao := 'Admitir um colaborador na empresa e conferir se o total/cota reagiu';
  r.esperado := 'A movimentação recalcula o total e a cota PcD automaticamente';
  PERFORM public.qa_ponto_admissao('QA Cota Movimento Colab', 7051, v_emp);
  SELECT total_colaboradores INTO v_depois FROM public.empresa_cadastro WHERE id = v_emp;

  IF v_depois IS DISTINCT FROM v_antes THEN
    r.situacao := 'passou';
    r.obtido := format('A admissão recalculou o total (%s → %s) — a cota acompanha a movimentação.',
                       coalesce(v_antes::text,'-'), coalesce(v_depois::text,'-'));
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: admitir um colaborador NÃO mexeu no total da empresa (segue %s). '
             || 'A cota PcD da Lei 8.213/91 muda de faixa exatamente nas movimentações '
             || '(100→101 empregados muda a exigência) — sem recálculo automático, a empresa '
             || 'cruza a faixa sem saber. Correção: gatilho de admissão/desligamento '
             || 'recalculando total e cota.', coalesce(v_antes::text, '-'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_emp_052()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_laudo text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a contagem de PcD tem lastro documental (laudo válido)?';
  r.esperado := 'Só contam PcDs com laudo dentro do prazo, ligados a pessoas reais';
  v_laudo := public.qa_col_existe(NULL, '%laudo%');
  IF v_laudo IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: não existe laudo em lugar nenhum do banco — pcd_quantidade_atual é um '
             || 'número sem ligação com pessoas nem com documentos. Na fiscalização, o que '
             || 'vale é o laudo caracterizador válido de cada PcD; um contador solto não '
             || 'sustenta a cota da Lei 8.213/91. Correção: marcação de PcD no vínculo com o '
             || 'laudo anexado e vigência, e a contagem derivando daí.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Lastro documental presente: %s.', v_laudo);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_emp_053()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_est text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a categoria "reabilitado do INSS" existe?';
  r.esperado := 'A Lei 8.213/91 admite na cota PcDs E beneficiários reabilitados — categorias distintas';
  v_est := coalesce(public.qa_col_existe(NULL, '%reabilitad%'), public.qa_fns_com('%reabilitad%'));
  IF v_est IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o sistema não conhece o beneficiário reabilitado do INSS — só "PcD". '
             || 'A Lei 8.213/91, art. 93, manda preencher a cota com as DUAS categorias; '
             || 'empresa com reabilitados no quadro não consegue computá-los e aparenta '
             || 'déficit que não tem. Correção: categoria própria no vínculo, somada na cota.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Categoria presente: %s.', v_est);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_emp_054()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_agrupa boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o recálculo de cota agrupa matriz e filiais?';
  r.esperado := 'Cota apurada sobre o total da pessoa jurídica (todos os estabelecimentos somados)';
  SELECT bool_or(p.prosrc ILIKE '%matriz%' OR p.prosrc ILIKE '%raiz%' OR p.prosrc ILIKE '%filia%')
    INTO v_agrupa
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'recalcular_cota_pcd';
  IF NOT coalesce(v_agrupa, false) THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o recálculo de cota trata cada cadastro isoladamente — não agrupa '
             || 'matriz e filiais pela raiz do CNPJ. A cota da Lei 8.213/91 é da EMPRESA '
             || '(pessoa jurídica inteira): três filiais de 40 empregados não devem 0+0+0, '
             || 'devem a cota de 120. Correção: apuração agrupada pela raiz do CNPJ, com a '
             || 'exigência exibida no grupo.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'O recálculo agrupa os estabelecimentos da mesma pessoa jurídica.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_enq_001()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_id uuid;
        v_cnae text; v_grau int; v_sesmt text; v_cipa text;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Cadastrar enquadramento: CNAE 4120-4/00, grau 3, SESMT terceirizado, CIPA ativa';
  r.esperado:='Todo o enquadramento persistido';
  INSERT INTO public.empresa_cadastro
    (tenant_id, razao_social, cnpj, cnae_principal, cnae_descricao,
     grau_risco, sesmt_situacao, cipa_situacao)
  VALUES (v_t, '[QA] Construtora Enquadrada', '11222333000181', '4120-4/00',
          'Construcao de edificios', 3, 'terceirizado', 'ativa')
  RETURNING id INTO v_id;
  SELECT cnae_principal, grau_risco, sesmt_situacao, cipa_situacao
    INTO v_cnae, v_grau, v_sesmt, v_cipa FROM public.empresa_cadastro WHERE id=v_id;
  IF v_cnae='4120-4/00' AND v_grau=3 AND v_sesmt='terceirizado' AND v_cipa='ativa' THEN
    r.situacao:='passou';
    r.obtido:='Enquadramento completo: CNAE 4120-4/00, grau 3, SESMT terceirizado, CIPA ativa.';
  ELSE
    r.situacao:='falhou';
    r.obtido:=format('cnae=%s, grau=%s, sesmt=%s, cipa=%s.', v_cnae, v_grau, v_sesmt, v_cipa);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_enq_010()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_id uuid; v_fap numeric;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Gravar FAP = 5,0000 (a Lei 10.666/2003 limita a 2,0000)';
  r.esperado:='Idealmente recusado — nao existe FAP acima de 2,0';
  BEGIN
    INSERT INTO public.empresa_cadastro (tenant_id, razao_social, cnpj, fap_atual)
    VALUES (v_t, '[QA] FAP Invalido', '11222333000262', 5.0000) RETURNING id INTO v_id;
    SELECT fap_atual INTO v_fap FROM public.empresa_cadastro WHERE id=v_id;
    r.situacao:='falhou';
    r.obtido:=format('O BANCO ACEITOU FAP = %s. A faixa legal e 0,5000 a 2,0000 (Lei 10.666/2003). O FAP multiplica a aliquota RAT — valor invalido distorce o recolhimento previdenciario.', v_fap);
  EXCEPTION WHEN check_violation THEN
    r.situacao:='passou'; r.obtido:='Recusado: FAP restrito a faixa legal de 0,5 a 2,0.';
  END;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_enq_011()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_id uuid;
        v_orig int; v_ajus int; v_just text;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1;
  r.passo_acao:='Gravar empresa com grau de risco 4 ajustado para 1, sem justificativa';
  r.esperado:='Idealmente recusado — o ajuste exige fundamentacao tecnica';
  BEGIN
    INSERT INTO public.empresa_cadastro
      (tenant_id, razao_social, cnpj, grau_risco, grau_risco_ajustado, grau_risco_justificativa)
    VALUES (v_t, '[QA] Grau Ajustado Sem Justificativa', '11222333000343', 4, 1, NULL)
    RETURNING id INTO v_id;
    SELECT grau_risco, grau_risco_ajustado, grau_risco_justificativa
      INTO v_orig, v_ajus, v_just FROM public.empresa_cadastro WHERE id=v_id;
    r.situacao:='falhou';
    r.obtido:=format('O BANCO ACEITOU ajuste de grau %s para %s sem justificativa. O grau de risco define obrigacoes de SST — reduzi-lo sem fundamento reduz exigencias legais sem deixar rastro.', v_orig, v_ajus);
  EXCEPTION WHEN check_violation THEN
    r.situacao:='passou'; r.obtido:='Recusado: ajustar o grau de risco exige justificativa.';
  END;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_enq_012()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_id uuid;
        v_obrig boolean; v_sit text;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Gravar SESMT obrigatorio com situacao "inexistente"';
  r.esperado:='Aceito (a empresa pode estar irregular), mas a irregularidade fica sem sinalizacao';
  INSERT INTO public.empresa_cadastro
    (tenant_id, razao_social, cnpj, sesmt_obrigatorio, sesmt_situacao)
  VALUES (v_t, '[QA] SESMT Irregular', '11222333000424', true, 'inexistente')
  RETURNING id INTO v_id;
  SELECT sesmt_obrigatorio, sesmt_situacao INTO v_obrig, v_sit
    FROM public.empresa_cadastro WHERE id=v_id;
  IF v_obrig AND v_sit='inexistente' THEN
    r.situacao:='passou';
    r.obtido:='Combinacao aceita, como deve ser — a empresa PODE estar irregular e precisa poder registrar. Nada e sinalizado automaticamente; hoje depende de registro manual no painel de conformidade.';
  ELSE
    r.situacao:='falhou'; r.obtido:=format('obrigatorio=%s, situacao=%s.', v_obrig, v_sit);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_enq_013()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_id uuid;
        v_ini date; v_fim date;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Gravar mandato da CIPA com fim antes do inicio';
  r.esperado:='Idealmente recusado';
  BEGIN
    INSERT INTO public.empresa_cadastro
      (tenant_id, razao_social, cnpj, cipa_situacao,
       cipa_data_mandato_inicio, cipa_data_mandato_fim)
    VALUES (v_t, '[QA] CIPA Mandato Invertido', '11222333000505', 'ativa',
            DATE '2026-12-31', DATE '2026-01-01') RETURNING id INTO v_id;
    SELECT cipa_data_mandato_inicio, cipa_data_mandato_fim INTO v_ini, v_fim
      FROM public.empresa_cadastro WHERE id=v_id;
    r.situacao:='falhou';
    r.obtido:=format('O BANCO ACEITOU mandato de %s ate %s (fim antes do inicio). O controle de renovacao da CIPA usa a data de fim — periodo invertido quebra o calculo da proxima eleicao.', v_ini, v_fim);
  EXCEPTION WHEN check_violation THEN
    r.situacao:='passou'; r.obtido:='Recusado: o fim do mandato precisa ser posterior ao inicio.';
  END;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_enq_014()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Tentar grau de risco ajustado = 7 (a NR-04 vai ate 4)';
  r.esperado:='Recusado pelo CHECK';
  BEGIN
    INSERT INTO public.empresa_cadastro
      (tenant_id, razao_social, cnpj, grau_risco, grau_risco_ajustado)
    VALUES (v_t, '[QA] Grau Ajustado Invalido', '11222333000686', 2, 7);
    r.situacao:='falhou'; r.obtido:='ACEITOU grau ajustado fora da escala 1-4.';
  EXCEPTION WHEN check_violation THEN
    r.situacao:='passou';
    r.obtido:='Recusado: o grau ajustado tambem esta limitado a 1-4, como o original.';
  END;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_enq_050()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): sesmt_obrigatorio é derivado de grau de risco × empregados?';
  r.esperado := 'A NR-04 dimensiona deterministicamente; os dois insumos já estão no cadastro';
  v_fns := public.qa_fns_com('%sesmt_obrigatorio%');
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: sesmt_obrigatorio é um interruptor manual — nenhuma função o deriva do '
             || 'cruzamento grau de risco × número de empregados (Quadro II da NR-04), embora '
             || 'os dois dados já existam no cadastro. Quem preenche errado carrega o '
             || 'enquadramento errado para todo o compliance. Correção: cálculo determinístico '
             || 'com o quadro da NR-04 parametrizado, mantendo o manual só como exceção '
             || 'justificada.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Dimensionamento presente em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_enq_051()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): cipa_obrigatoria é derivada de CNAE × empregados?';
  r.esperado := 'A NR-05 dimensiona pelo Quadro I; switch manual é fonte de erro';
  v_fns := public.qa_fns_com('%cipa_obrigatoria%');
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: cipa_obrigatoria é switch manual — nenhuma função aplica o Quadro I '
             || 'da NR-05 (dimensionamento por CNAE × número de empregados). Mesmo padrão do '
             || 'SESMT (ENQ-050): dado derivável tratado como digitação. Correção: '
             || 'dimensionamento automático com o quadro parametrizado por vigência.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Dimensionamento presente em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_epi_010()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_ca text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): alguém consulta a base oficial (CAEPI) ao cadastrar o CA?';
  r.esperado := 'Número de CA informado → dados oficiais (equipamento, fabricante, validade) preenchidos e conferidos';
  v_ca := public.qa_col_existe('epi_tipos', 'ca_numero');
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%caepi%'
         OR (p.prosrc ILIKE '%epi_tipos%' AND p.prosrc ILIKE '%http%'));

  IF v_ca IS NOT NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o CA é digitado no braço — nenhuma rotina (função ou edge function '
             || 'do repositório) consulta a base oficial CAEPI para preencher e conferir o '
             || 'cadastro: ca_numero e ca_validade entram como o usuário digitar, inclusive '
             || 'CA inexistente. O documento (RF-001/RF-002) pede a busca automática porque '
             || 'cadastro errado vira ficha de entrega errada — e ficha errada não prova '
             || 'proteção em juízo. Correção: consulta CAEPI no cadastro (edge function com '
             || 'a base pública), marcando o tipo como conferido/não confirmado.';
  ELSIF v_ca IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A coluna ca_numero não existe mais em epi_tipos.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Consulta oficial do CA presente: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_epi_011()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_ativo boolean; v_fns text;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Cadastrar tipo com CA VENCIDO e conferir se algo reage';
  r.esperado := 'CA vencido sinalizado no catálogo; alerta de renovação com antecedência';
  INSERT INTO public.epi_tipos (tenant_id, nome, ca_numero, ca_validade, is_active)
  VALUES (v_t, 'QA — Capacete CA vencido', '99001', CURRENT_DATE - 30, true);
  SELECT et.is_active INTO v_ativo FROM public.epi_tipos et
  WHERE et.tenant_id = v_t AND et.ca_numero = '99001'
  ORDER BY et.created_at DESC LIMIT 1;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: alguma rotina vigia ca_validade (alerta antes, vencido acusado)?';
  r.esperado := 'Rotina periódica marcando CA vencido e avisando a renovação/recompra';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%ca_validade%';

  IF coalesce(v_ativo, true) AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a validade do CA é decorativa no catálogo — o tipo entrou com CA '
             || '30 dias no PASSADO e ficou ativo, e NENHUMA função do banco sequer lê '
             || 'ca_validade (o mesmo vazio que o SST-011 constatou na entrega). Quando um '
             || 'CA vence, todo o estoque daquele tipo vira sucata jurídica de uma vez — e '
             || 'ninguém fica sabendo até a fiscalização (ou o acidente). Correção: rotina '
             || 'diária (pg_cron, como as demais da casa) marcando CA vencido no catálogo e '
             || 'abrindo alerta de renovação/recompra com a antecedência parametrizada '
             || '[VAL], antes de chegar ao balcão.';
  ELSIF NOT coalesce(v_ativo, true) THEN
    r.situacao := 'passou';
    r.obtido := 'O catálogo reagiu ao CA vencido na gravação (tipo desativado).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('ca_validade vigiada por: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_epi_020()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_tipo uuid; v_epi uuid; v_saldo int;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Criar item com saldo 1 e tentar ENTREGAR 5 unidades';
  r.esperado := 'Operação bloqueada — saldo insuficiente; o estoque jamais fica negativo';
  INSERT INTO public.epi_tipos (tenant_id, nome, ca_numero, ca_validade, is_active)
  VALUES (v_t, 'QA — Luva saldo curto', '99002', CURRENT_DATE + 365, true)
  RETURNING id INTO v_tipo;
  INSERT INTO public.epis (tenant_id, tipo_id, codigo, quantidade_estoque, data_validade)
  VALUES (v_t, v_tipo, 'QA-EPI-020', 1, CURRENT_DATE + 365)
  RETURNING id INTO v_epi;

  BEGIN
    INSERT INTO public.epi_entregas
      (tenant_id, epi_id, colaborador_nome, colaborador_cpf, quantidade, data_entrega)
    VALUES (v_t, v_epi, 'QA Colaborador Vinte', public.qa_cpf(20), 5, CURRENT_DATE);
  EXCEPTION WHEN check_violation OR raise_exception THEN
    r.situacao := 'passou';
    r.obtido := format('Entrega acima do saldo foi bloqueada (%s).', SQLERRM);
    RETURN r;
  END;

  r.passo_ordem := 2;
  r.passo_acao := 'Conferir o saldo após a entrega maior que o estoque';
  r.esperado := 'Saldo >= 0 sempre';
  SELECT e.quantidade_estoque INTO v_saldo FROM public.epis e WHERE e.id = v_epi;

  IF v_saldo < 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o saldo ficou NEGATIVO (%s) — a entrega de 5 unidades com '
             || 'estoque 1 passou sem protesto: o gatilho atualizar_estoque_epi subtrai sem '
             || 'conferir o saldo e não há CHECK (quantidade_estoque >= 0) na tabela. A '
             || 'RN-003 do documento proíbe saldo negativo justamente porque ficha de '
             || 'entrega sem lastro físico é ficha de papel: no acidente, a empresa "provou" '
             || 'entregar o que não tinha. As funções otimistas (epi_atualizar_estoque_'
             || 'otimista) protegem a concorrência quando o APP as usa, mas o banco aceita o '
             || 'negativo por qualquer outro caminho. Correção: CHECK >= 0 nas tabelas de '
             || 'saldo + conferência no gatilho, por combinação tipo × tamanho × local.',
             v_saldo);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Saldo preservado (%s) — a baixa respeitou o estoque.', v_saldo);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_epi_021()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_val text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a saída prioriza o lote que vence primeiro (FEFO)?';
  r.esperado := 'Baixa/sugestão ordenada por data_validade; quebra de FEFO é decisão consciente';
  v_val := public.qa_col_existe('epis', 'data_validade');
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%epi%' AND p.prosrc ILIKE '%data_validade%';

  IF v_val IS NOT NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: cada item tem data_validade, mas nenhuma função a usa na SAÍDA — a '
             || 'baixa desce no epi_id que a tela mandar, sem ordenar nem sugerir o lote '
             || 'que vence primeiro. Sem FEFO (RN-004), o lote novo gira enquanto o antigo '
             || 'apodrece na prateleira: vira perda de compra ou, pior, entrega de item '
             || 'vencido (a trava do vencido é o EPI-040 — hoje também ausente, o que '
             || 'agrava). Correção: na entrega, sugerir/baixar o lote de validade mais '
             || 'próxima da combinação tipo × tamanho × local, com registro explícito '
             || 'quando o operador quebrar o FEFO.';
  ELSIF v_val IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A coluna data_validade não existe mais em epis.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('FEFO/validade considerada na saída por: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_epi_022()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_min text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): cruzar o estoque mínimo abre reposição no Plano de Ação?';
  r.esperado := 'Ação de reposição criada (sem duplicar) quando o saldo cruza o mínimo';
  v_min := coalesce(public.qa_col_existe('epi_tipos', 'estoque_minimo'),
                    public.qa_col_existe('epi_estoque_local', 'quantidade_minima'));
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%estoque_minimo%' OR p.prosrc ILIKE '%quantidade_minima%')
    AND (p.prosrc ILIKE '%plano_acoes%' OR p.prosrc ILIKE '%plano_tarefas%');

  IF v_min IS NOT NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO (o parâmetro existe, o gatilho não): o mínimo está cadastrado '
             || 'em dois lugares (%s) e NENHUMA função o compara com o saldo para abrir a '
             || 'reposição no Plano de Ação (RF-018) — o mínimo só serve de cor no painel, '
             || 'se a tela lembrar de pintar. Ficar sem EPI em estoque para a operação: '
             || 'pela NR-6, sem o EPI da função o colaborador não pode trabalhar. Correção: '
             || 'ao movimentar o saldo (ou em rotina diária), cruzou o mínimo → ação de '
             || 'reposição com item, saldo e local, referenciando a existente em vez de '
             || 'duplicar — o padrão que o módulo Plano de Ação já pratica.',
             v_min);
  ELSIF v_min IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'O estoque mínimo não existe mais no cadastro.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Reposição automática presente: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_epi_030()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_chave text := repeat('9', 44); v_qtd int;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Lançar a MESMA NF (mesma chave de acesso) duas vezes';
  r.esperado := 'Segunda entrada bloqueada — chave de acesso é única, estoque não dobra';
  INSERT INTO public.epi_notas_fiscais (tenant_id, numero_nf, chave_acesso, origem)
  VALUES (v_t, 'QA-NF-030', v_chave, 'manual');
  BEGIN
    INSERT INTO public.epi_notas_fiscais (tenant_id, numero_nf, chave_acesso, origem)
    VALUES (v_t, 'QA-NF-030-BIS', v_chave, 'manual');
  EXCEPTION WHEN unique_violation OR check_violation OR raise_exception THEN
    r.situacao := 'passou';
    r.obtido := format('Nota duplicada foi recusada (%s).', SQLERRM);
    RETURN r;
  END;
  SELECT count(*) INTO v_qtd FROM public.epi_notas_fiscais nf
  WHERE nf.tenant_id = v_t AND nf.chave_acesso = v_chave;

  r.passo_ordem := 2;
  r.passo_acao := 'Conferir também se chave curta (10 dígitos) passa';
  r.esperado := 'Chave de acesso tem 44 dígitos — formato inválido não entra';
  BEGIN
    INSERT INTO public.epi_notas_fiscais (tenant_id, numero_nf, chave_acesso, origem)
    VALUES (v_t, 'QA-NF-030-CURTA', '1234567890', 'manual');
  EXCEPTION WHEN check_violation OR raise_exception THEN
    NULL; -- ótimo: formato validado (a duplicata acima já reprovou o caso mesmo assim)
  END;

  IF v_qtd > 1 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a mesma chave de acesso entrou %s vezes — epi_notas_fiscais '
             || 'não tem UNIQUE em chave_acesso nem validação dos 44 dígitos (a chave curta '
             || 'de 10 dígitos também passou). A nota relançada dobra o estoque no papel e '
             || 'descasa o físico do contábil; a chave existe exatamente para ser a trava '
             || 'natural (RF-007/RF-008). Correção: UNIQUE (tenant_id, chave_acesso) + CHECK '
             || 'de 44 dígitos numéricos quando informada — a conciliação dos itens '
             || '(epi_nf_itens → movimentação) já existe e fica protegida de graça.',
             v_qtd);
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Chave de acesso protegida contra duplicata.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_epi_040()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_tipo uuid; v_epi uuid; v_saiu boolean := false;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Tentar entregar item com data_validade VENCIDA';
  r.esperado := 'Entrega bloqueada — item vencido fica segregado, fora do saldo entregável';
  INSERT INTO public.epi_tipos (tenant_id, nome, ca_numero, ca_validade, is_active)
  VALUES (v_t, 'QA — Filtro vencido', '99003', CURRENT_DATE + 365, true)
  RETURNING id INTO v_tipo;
  INSERT INTO public.epis (tenant_id, tipo_id, codigo, quantidade_estoque, data_validade)
  VALUES (v_t, v_tipo, 'QA-EPI-040', 10, CURRENT_DATE - 15)
  RETURNING id INTO v_epi;

  BEGIN
    INSERT INTO public.epi_entregas
      (tenant_id, epi_id, colaborador_nome, colaborador_cpf, quantidade, data_entrega)
    VALUES (v_t, v_epi, 'QA Colaborador Quarenta', public.qa_cpf(40), 1, CURRENT_DATE);
    v_saiu := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN
    v_saiu := false;
  END;

  IF v_saiu THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o lote vencido há 15 dias SAIU do almoxarifado sem protesto — '
             || 'nenhum gatilho compara epis.data_validade com a data da entrega, e o '
             || 'estoque baixou normalmente. Entregar protetor vencido equivale a não '
             || 'entregar (NR-6), com a agravante de PARECER que entregou: a ficha assinada '
             || 'vira prova contra a própria empresa. Correção: trava na entrega (item '
             || 'vencido não compõe o saldo entregável) + segregação do lote para '
             || 'descarte/troca com o fornecedor — casa com o FEFO do EPI-021, que '
             || 'esvazia a prateleira antes de vencer.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Entrega de item vencido foi bloqueada.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_epi_041()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_bio text; v_perfil int; v_log text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): quem consegue LER o material biométrico das entregas?';
  r.esperado := 'Camada de perfil restringindo a leitura + log de quem consultou (LGPD art. 11)';
  v_bio := coalesce(public.qa_col_existe('epi_entregas', 'liveness_data'),
                    public.qa_col_existe('epi_entregas', 'foto_entrega_url'));
  SELECT count(*) INTO v_perfil FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'epi_entregas'
    AND policyname ILIKE '%perfil%';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_log
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%epi_entregas%'
    AND (p.prosrc ILIKE '%log%acesso%' OR p.prosrc ILIKE '%auditoria%');

  IF v_bio IS NOT NULL AND v_perfil = 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: epi_entregas guarda material biométrico (%s — rosto e prova '
             || 'de vida) e a leitura está aberta a QUALQUER usuário do tenant ("Usuários '
             || 'podem ver entregas de EPI do seu tenant"), sem nenhuma política '
             || 'perfil_restringe_leitura_* — a camada que já protege ~20 tabelas sensíveis '
             || 'da casa (atestados, eventos_saude...) não alcançou esta. Biometria é a '
             || 'categoria mais dura da LGPD (art. 5º, II c/c art. 11): exige acesso '
             || 'mínimo, registro de consulta (hoje: %s) e RIPD. Correção: política '
             || 'RESTRICTIVE por perfil na tabela (mesma família do FOLHA-090), log de '
             || 'acesso ao material biométrico, e o fluxo alternativo sem biometria '
             || 'documentado — a recusa não pode deixar ninguém sem EPI.',
             v_bio, coalesce(v_log, 'nenhum'));
  ELSIF v_bio IS NULL THEN
    r.situacao := 'passou';
    r.obtido := 'Não há material biométrico armazenado em epi_entregas.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Leitura restrita por perfil (%s política(s)); log: %s.',
                       v_perfil, coalesce(v_log, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_epi_042()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_trilha text; v_hash text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a assinatura da entrega carrega a trilha que a sustenta?';
  r.esperado := 'Quem, quando (carimbo), de onde (IP/dispositivo) e integridade (hash) recuperáveis';
  SELECT string_agg(c.column_name, ', ' ORDER BY c.column_name) INTO v_trilha
  FROM information_schema.columns c
  WHERE c.table_schema = 'public' AND c.table_name = 'epi_entregas'
    AND c.column_name IN ('assinatura_url', 'signed_at', 'ip_address', 'user_agent');
  v_hash := coalesce(public.qa_col_existe('epi_entregas', '%hash%'),
                     public.qa_col_existe('epi_entregas', '%integridade%'));

  IF v_trilha IS NOT NULL AND v_hash IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO (metade boa, metade frágil): a trilha da assinatura existe e '
             || 'é das melhores da casa (%s — quem, quando, de onde, com liveness), mas '
             || 'falta o lacre de INTEGRIDADE: nenhum hash do documento assinado é gravado, '
             || 'então não há como provar que a ficha exibida hoje é a mesma que o '
             || 'colaborador assinou — o requisito central da assinatura AVANÇADA (Lei '
             || '14.063/2020, art. 4º, II: detectar modificação posterior; é o que o STJ '
             || 'valorizou no REsp 2.159.442). E nada torna a trilha obrigatória: entrega '
             || 'sem assinatura alguma conclui do mesmo jeito (esse fio puxa o EPI-043). '
             || 'Correção: hash (extensions.digest, já disponível) do recibo no ato da '
             || 'assinatura, gravado com signed_at — o padrão de ADM-070/DESL-082.',
             v_trilha);
  ELSIF v_trilha IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'Os campos de trilha da assinatura sumiram de epi_entregas.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Trilha completa com integridade (%s + %s).', v_trilha, v_hash);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_epi_043()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_tipo uuid; v_epi uuid; v_saldo int;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Registrar entrega SEM assinatura e conferir quando o estoque baixa';
  r.esperado := 'Antes da assinatura: RESERVA; baixa definitiva só com signed_at (RN-005)';
  INSERT INTO public.epi_tipos (tenant_id, nome, ca_numero, ca_validade, is_active)
  VALUES (v_t, 'QA — Óculos reserva', '99004', CURRENT_DATE + 365, true)
  RETURNING id INTO v_tipo;
  INSERT INTO public.epis (tenant_id, tipo_id, codigo, quantidade_estoque, data_validade)
  VALUES (v_t, v_tipo, 'QA-EPI-043', 10, CURRENT_DATE + 365)
  RETURNING id INTO v_epi;

  INSERT INTO public.epi_entregas
    (tenant_id, epi_id, colaborador_nome, colaborador_cpf, quantidade, data_entrega)
  VALUES (v_t, v_epi, 'QA Colaborador Quarenta e Três', public.qa_cpf(43), 2, CURRENT_DATE);
  -- assinatura_url e signed_at ficaram NULL de propósito

  SELECT e.quantidade_estoque INTO v_saldo FROM public.epis e WHERE e.id = v_epi;

  IF v_saldo < 10 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o estoque baixou de 10 para %s no REGISTRO da entrega, com '
             || 'assinatura_url e signed_at ainda NULOS — o gatilho atualizar_estoque_epi '
             || 'dispara no INSERT, invertendo a RN-005 (baixa só após a assinatura). Sem a '
             || 'etapa de reserva, a entrega abandonada no meio (colaborador não assinou) '
             || 'deixa o pior dos mundos: estoque sem item e ficha sem prova — e não há '
             || 'estorno automático, o saldo só volta editando na mão. Correção: INSERT '
             || 'reserva (saldo disponível separado do físico); a baixa definitiva move no '
             || 'UPDATE que grava signed_at; reserva expirada estorna com rastro em '
             || 'epi_movimentacoes. O caminho da devolução (status devolvido) já repõe o '
             || 'saldo — falta o espelho na entrada do fluxo.',
             v_saldo);
  ELSE
    r.situacao := 'passou';
    r.obtido := 'O estoque só baixa com a assinatura — reserva respeitada.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_epi_044()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_pasta text; v_ponte text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a ficha assinada é arquivada no módulo Documentos?';
  r.esperado := 'Recibo na pasta do colaborador, com prazo de guarda parametrizado';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_pasta
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.proname ILIKE '%pasta%' AND p.prosrc ILIKE '%epi%';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_ponte
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%epi_entregas%'
    AND (p.prosrc ILIKE '%documento%' OR p.prosrc ILIKE '%pasta%');

  IF v_ponte IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO (a estante existe, o arquivista não): a estrutura de pastas '
             || 'por colaborador já prevê o lugar (%s), mas nenhuma função leva a ficha '
             || 'assinada até lá — o recibo fica em assinatura_url, um arquivo solto no '
             || 'storage, fora do módulo Documentos, sem metadados nem prazo de guarda '
             || '(RN-012; a obrigação trabalhista pede guarda longa, parâmetro [VAL]). '
             || 'Documento que a fiscalização pede e ninguém acha é documento que não '
             || 'existe. Correção: ao gravar signed_at, registrar o recibo no módulo '
             || 'Documentos (pasta do colaborador) com tipo, data e vínculo à entrega.',
             coalesce(v_pasta, 'gerar_estrutura_padrao_pastas'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Ficha arquivada no módulo Documentos por: %s.', v_ponte);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_epi_050()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_param text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): alguém conta os dias de uso e cobra a troca?';
  r.esperado := 'Data de troca calculada na entrega; substituição pendente apontada com antecedência';
  v_param := public.qa_col_existe('epi_tipos', 'periodicidade_troca_dias');
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%periodicidade_troca%'
         OR p.prosrc ILIKE '%data_devolucao_prevista%');

  IF v_param IS NOT NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO (o parâmetro existe, o relógio não): %s está no cadastro do '
             || 'tipo e epi_entregas tem data_devolucao_prevista — e nenhuma função usa um '
             || 'nem outro: a entrega não calcula a data da troca, nenhuma rotina aponta '
             || 'substituição vencendo. O mesmo desenho do SST-020 (periodicidade do exame '
             || 'sem motor): o parâmetro vira promessa. Protetor com a espuma vencida '
             || 'protege tanto quanto nenhum — e o colaborador não pede troca, quem cobra é '
             || 'o sistema (RF-016, configurável por cliente). Correção: na entrega, gravar '
             || 'a data prevista de troca (data_entrega + periodicidade); rotina diária '
             || 'apontando as trocas a vencer, com antecedência [VAL].',
             v_param);
  ELSIF v_param IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'O parâmetro periodicidade_troca_dias não existe mais.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Troca periódica vigiada por: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_epi_051()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_param text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a admissão em função de risco gera o kit inicial?';
  r.esperado := 'EPIs exigidos pela função viram pendência de entrega na admissão';
  v_param := public.qa_col_existe('epi_tipos', 'obrigatorio_para_funcoes');
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%obrigatorio_para_funcoes%'
         OR (p.prosrc ILIKE '%epi_entregas%' AND p.prosrc ILIKE '%admiss%'));

  IF v_param IS NOT NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o vínculo função→EPI está cadastrado (%s) e a admissão não '
             || 'o consulta — nenhuma função gera o kit inicial como pendência quando o '
             || 'colaborador é admitido em função de risco: o capacete do primeiro dia '
             || 'depende da memória do RH. A NR-6 (c/c NR-1) exige o fornecimento ANTES do '
             || 'início da exposição; a admissão da casa já trabalha com pendências e '
             || 'checklist (família ADM), falta o item de EPI entrar na lista (RF-020). '
             || 'Correção: ao concluir a admissão em função com EPIs exigidos, abrir a '
             || 'pendência de entrega do kit (tipos e tamanhos a colher), visível no painel '
             || 'até a última ficha assinada.',
             v_param);
  ELSIF v_param IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'O vínculo obrigatorio_para_funcoes não existe mais.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Kit de admissão gerado por: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_epi_052()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_volta text; v_check text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o desligamento gera o checklist de devolução dos EPIs?';
  r.esperado := 'Entregas ativas do colaborador viram checklist na rescisão — sem travar verbas';
  -- a volta ao saldo na devolução já existe (trigger status devolvido)
  SELECT string_agg(DISTINCT t.tgname, ', ') INTO v_volta
  FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
  WHERE t.tgrelid = 'public.epi_entregas'::regclass AND NOT t.tgisinternal
    AND t.tgname NOT ILIKE 'qa\_%' AND p.prosrc ILIKE '%devolvido%';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_check
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%epi_entregas%'
    AND (p.prosrc ILIKE '%desligamento%' OR p.prosrc ILIKE '%rescis%'
         OR p.prosrc ILIKE '%afastamento%');

  IF v_check IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO (metade boa, metade solta): a DEVOLUÇÃO em si funciona — o '
             || 'gatilho (%s) repõe o saldo quando a entrega vira "devolvido" — mas nada '
             || 'CONECTA o desligamento (nem o afastamento longo) às entregas ativas do '
             || 'colaborador: nenhum checklist de devolução é gerado na rescisão, e os EPIs '
             || 'em posse saem pela porta sem registro de cobrança. A RN-014 pede o '
             || 'equilíbrio fino: cobrar a devolução SEM reter verbas nem homologação '
             || '(desconto só nos limites da CLT art. 462, com acordo) — hoje não há nem a '
             || 'cobrança. Correção: ao iniciar o desligamento, gerar o checklist com as '
             || 'entregas ativas (a família DESL já trabalha com pendências); devolvido '
             || 'reintegra/descarta, não devolvido fica registrado para tratativa — e a '
             || 'rescisão SEGUE de qualquer forma.',
             coalesce(v_volta, 'trigger_atualizar_estoque_epi'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Checklist de devolução no desligamento presente: %s.', v_check);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_esc_001()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_id uuid; v_fns text;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Criar escala 12x36 ATIVA sem nenhum acordo anexado';
  r.esperado := 'Bloqueio ou pendência de formalização (art. 59-A) — nunca silêncio';
  INSERT INTO public.ponto_escalas
    (tenant_id, nome, tipo, ciclo_horas_trabalho, ciclo_horas_descanso, ativa)
  VALUES (v_t, 'QA — 12x36 sem acordo', '12x36', 12, 36, true)
  RETURNING id INTO v_id;
  INSERT INTO public.ponto_escala_atribuicoes
    (tenant_id, escala_id, colaborador_id, colaborador_nome, colaborador_cpf, data_inicio, ativa)
  VALUES (v_t, v_id, gen_random_uuid(), 'QA Colaborador Esc Um', public.qa_cpf(61), CURRENT_DATE, true);

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: alguém exige acordo_individual_url/cct_act_url quando a escala é 12x36?';
  r.esperado := 'Validação na criação/atribuição, com pendência enquanto o acordo não é arquivado';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%acordo_individual_url%' OR p.prosrc ILIKE '%cct_act_url%');

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a 12x36 nasceu ativa, foi atribuída a um colaborador e NADA cobrou '
             || 'o acordo — os campos existem (acordo_individual_url, cct_act_url) e '
             || 'nenhuma função os lê: são pastas vazias que ninguém confere. O art. 59-A '
             || 'condiciona a 12x36 a acordo individual ESCRITO, ACT ou CCT; sem a '
             || 'formalização, a jornada é inválida e toda hora além da 8ª vira extra com '
             || 'reflexos, do período inteiro — o passivo clássico da escala. A apuração do '
             || 'ciclo funciona (PONTO-150/151), o que agrava: o sistema apura direitinho '
             || 'uma escala juridicamente inexistente. Correção: pendência de formalização '
             || 'na criação/atribuição de 12x36 sem acordo anexado, com o documento '
             || 'arquivado no módulo Documentos (RF-003/RN-014).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Formalização cobrada por: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_esc_010()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_cpf text := public.qa_cpf(62); v_afast_vinc uuid; v_afast_novo int; v_fns text;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Registrar atestado de 20 dias e conferir se o Afastamento nasce';
  r.esperado := 'Empresa abona 15; do 16º dia em diante, afastamento previdenciário criado/encaminhado, sem duplicar';
  INSERT INTO public.atestados
    (tenant_id, colaborador_nome, colaborador_cpf, tipo, data_emissao,
     profissional_nome, profissional_registro,
     data_inicio_afastamento, data_fim_afastamento, dias_afastamento)
  VALUES (v_t, 'QA Colaborador Esc Dois', v_cpf, 'assistencial', CURRENT_DATE,
          'QA Dr. Sonda', 'CRM-QA-0001',
          CURRENT_DATE, CURRENT_DATE + 19, 20)
  RETURNING afastamento_id INTO v_afast_vinc;

  SELECT count(*) INTO v_afast_novo FROM public.afastamentos a
  WHERE a.tenant_id = v_t AND a.colaborador_cpf = v_cpf;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: alguma função cria/encaminha afastamento a partir do atestado longo?';
  r.esperado := 'Ponte automática atestado→Afastamentos no 16º dia';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%atestado%' AND p.prosrc ILIKE '%INSERT INTO%afastamentos%';

  IF v_afast_vinc IS NULL AND v_afast_novo = 0 AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o atestado de 20 dias entrou e NENHUM afastamento nasceu — '
             || 'afastamento_id ficou nulo, a tabela afastamentos não ganhou linha e não '
             || 'existe função que faça a ponte. O gatilho do atestado (trg_consolida_'
             || 'atestado) só reconsolida o ponto dos dias; a passagem de bastão do 16º '
             || 'dia (Lei 8.213, arts. 59-60 — empresa paga 15, INSS assume dali) depende '
             || 'de alguém LEMBRAR de abrir o afastamento noutro módulo. Esquecer é perder '
             || 'o encaminhamento do benefício e seguir "abonando" por conta da empresa o '
             || 'que é do INSS. A inteligência do lado dos Afastamentos existe e funciona '
             || '(AFAST-020..022) — falta o afluente. Correção: atestado com período >15 '
             || 'dias cria/encaminha o afastamento vinculado (afastamento_id), uma única '
             || 'vez, com alerta ao DP.';
  ELSIF v_afast_vinc IS NOT NULL OR v_afast_novo > 0 THEN
    r.situacao := 'passou';
    r.obtido := format('Afastamento criado/vinculado a partir do atestado (vínculo: %s; novos: %s).',
                       coalesce(v_afast_vinc::text, '—'), v_afast_novo);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Ponte presente: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_esc_011()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_cpf text := public.qa_cpf(63); v_qtd int; v_fns text;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Registrar dois atestados com períodos sobrepostos para o mesmo CPF';
  r.esperado := 'Sobreposição detectada e sinalizada — o mesmo dia não abona duas vezes';
  INSERT INTO public.atestados
    (tenant_id, colaborador_nome, colaborador_cpf, tipo, data_emissao,
     profissional_nome, profissional_registro,
     data_inicio_afastamento, data_fim_afastamento, dias_afastamento)
  VALUES (v_t, 'QA Colaborador Esc Três', v_cpf, 'assistencial', CURRENT_DATE - 12,
          'QA Dr. Sonda', 'CRM-QA-0002', CURRENT_DATE - 12, CURRENT_DATE - 3, 10);
  BEGIN
    INSERT INTO public.atestados
      (tenant_id, colaborador_nome, colaborador_cpf, tipo, data_emissao,
       profissional_nome, profissional_registro,
       data_inicio_afastamento, data_fim_afastamento, dias_afastamento)
    VALUES (v_t, 'QA Colaborador Esc Três', v_cpf, 'assistencial', CURRENT_DATE - 8,
            'QA Dr. Sonda B', 'CRM-QA-0003', CURRENT_DATE - 8, CURRENT_DATE - 1, 8);
  EXCEPTION WHEN check_violation OR exclusion_violation OR raise_exception THEN
    r.situacao := 'passou';
    r.obtido := format('Atestado sobreposto foi recusado/sinalizado (%s).', SQLERRM);
    RETURN r;
  END;
  SELECT count(*) INTO v_qtd FROM public.atestados a
  WHERE a.tenant_id = v_t AND a.colaborador_cpf = v_cpf;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: alguma função detecta sobreposição de períodos de atestado?';
  r.esperado := 'Detecção na entrada, mantendo o tratamento mais favorável';
  -- "sobrepoe" aparece em comentário de apuração (fallback de jornada) —
  -- detecção de verdade fala em sobreposição/sobreposto e olha a tabela atestados
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%atestados%'
    AND (p.prosrc ILIKE '%sobreposi%' OR p.prosrc ILIKE '%sobreposto%' OR p.prosrc ILIKE '%overlap%');

  IF v_qtd >= 2 AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: os dois atestados sobrepostos (6 dias em comum) entraram como '
             || 'registros independentes — sem constraint, gatilho ou função que detecte '
             || 'a sobreposição. A apuração diária do ponto até se salva (o EXISTS por '
             || 'data conta o dia uma vez), mas tudo que SOMA por atestado dobra: '
             || 'dias_afastamento acumulados, a régua dos 15 dias (o 16º dia do INSS '
             || 'calculado sobre dias somados em dobro) e os indicadores de absenteísmo. '
             || 'E o mesmo documento reenviado passa como atestado novo, sem ninguém ser '
             || 'avisado. Nos afastamentos a regra de não-sobreposição existe '
             || '(AFAST-011) — nos atestados, não. Correção: detecção na entrada (período '
             || '× CPF), sinalização para o DP decidir e contagem de dias única — cada '
             || 'dia doente conta uma vez.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Sobreposição tratada (registros: %s; detecção: %s).',
                       v_qtd, coalesce(v_fns, 'na gravação'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_esc_012()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_flag text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): quem cobra o anexo quando a justificativa o exige?';
  r.esperado := 'Justificativa com requer_anexo sem documento fica pendente — não abona nem desconta às cegas';
  v_flag := public.qa_col_existe('ponto_justificativas', 'requer_anexo');
  -- listar_justificativas_externo só EXIBE a flag e
  -- ponto_auditoria_ajustes_motivo apenas RELATA quantos ajustes ficaram sem
  -- anexo; cobrança de verdade valida ao justificar ou mantém pendência com prazo
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.proname NOT IN ('listar_justificativas_externo', 'seed_justificativas_padrao',
                          'ponto_auditoria_ajustes_motivo')
    AND p.prosrc ILIKE '%requer_anexo%';

  IF v_flag IS NOT NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO (a pergunta existe, a cobrança não): ponto_justificativas tem '
             || 'requer_anexo, a tela recebe a flag (listar_justificativas_externo) e o '
             || 'relatório de auditoria até CONTA os ajustes sem anexo '
             || '(ponto_auditoria_ajustes_motivo) — mas nada IMPEDE o abono sem documento, '
             || 'nada mantém a pendência com prazo de comprovação, nada alerta antes do '
             || 'desconto. O art. 473 abona MEDIANTE comprovação: sem o documento, abonar '
             || 'é abrir mão de prova; descontar às cegas é descontar direito líquido '
             || '(certidão que chega depois). O rol e os prazos já têm dono (AFAST-050) — '
             || 'falta o fluxo da pendência. Correção: justificativa com requer_anexo e '
             || 'sem documento fica "pendente de comprovação" com prazo [VAL]; alerta ao '
             || 'colaborador e ao DP antes de virar desconto; documento arquivado no '
             || 'módulo Documentos preserva o DSR da semana.';
  ELSIF v_flag IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A flag requer_anexo não existe mais em ponto_justificativas.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Anexo cobrado por: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_esc_020()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_tab text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): existe estrutura de troca de turno (solicitação, aprovação, recálculo)?';
  r.esperado := 'Troca registrada com aprovação e reflexos recalculados para os dois envolvidos';
  SELECT string_agg(table_name, ', ') INTO v_tab
  FROM information_schema.tables
  WHERE table_schema = 'public'
    AND (table_name ILIKE '%troca%turno%' OR table_name ILIKE '%turno%troca%'
         OR table_name ILIKE 'ponto%troca%');
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%ponto_escala_atribuicoes%' AND p.prosrc ILIKE '%troca%';

  IF v_tab IS NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: não há estrutura de troca de turno — nenhuma tabela de '
             || 'solicitação/aprovação, nenhuma função que troque atribuições em par. Na '
             || 'prática a troca vira edição manual de duas linhas de '
             || 'ponto_escala_atribuicoes: sem aprovação do gestor, sem registro de quem '
             || 'trocou com quem e — o ponto jurídico — sem recálculo da interjornada de '
             || '11h e dos adicionais dos DOIS envolvidos (o rapaz que sai do turno do dia '
             || 'e pega o noturno de amanhã pode estar violando o art. 66 por boa '
             || 'vontade). Correção: fluxo de troca como transação (solicita → aprova → '
             || 'efetiva) preservando o histórico de vigência (PONTO-152) e simulando '
             || 'interjornada/adicionais ANTES de consumar.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Estrutura de troca presente (tabelas: %s; funções: %s).',
                       coalesce(v_tab, '—'), coalesce(v_fns, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_esc_021()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): algum motor cruza atribuições × afastamentos para apontar turno descoberto?';
  r.esperado := 'Turno previsto sem colaborador disponível vira alerta ao gestor antes do dia';
  -- "cobertura de ponto" (apuração de férias) e "faltas descobertas" são
  -- outra coisa; o radar de escala fala de cobertura/descoberto DE TURNO
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%turno%'
    AND (p.prosrc ILIKE '%cobertura%' OR p.prosrc ILIKE '%descobert%');

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o radar de cobertura não existe — nenhuma função cruza as '
             || 'atribuições de escala com afastamentos, férias ou desligamentos para '
             || 'apontar o turno que vai ficar vazio. O sistema TEM todos os ingredientes '
             || '(ponto_escala_atribuicoes com vigência, afastamentos com período, férias '
             || 'aprovadas) e não os junta: o gestor descobre o buraco com o posto vazio, '
             || 'e a solução de última hora costuma ser dobra de turno — que estoura '
             || 'interjornada e HE (justamente o que PONTO-080/092 vigiam). Correção: '
             || 'rotina que projeta os próximos turnos por escala e acusa os descobertos, '
             || 'com alerta ao gestor e ação de cobertura no Plano de Ação (seção 15 do '
             || 'documento).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Cobertura vigiada por: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_esc_031()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_mods text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o revezamento existe como conceito e alguém valida as 6 horas?';
  r.esperado := 'Escala de revezamento acima de 6h exige instrumento coletivo (CF art. 7º, XIV)';
  SELECT pg_get_constraintdef(oid) INTO v_mods
  FROM pg_constraint
  WHERE conrelid = 'public.ponto_escalas'::regclass
    AND conname = 'ponto_escalas_modalidade_check';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%revezamento%';

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o turno ininterrupto de revezamento não existe como '
             || 'conceito no motor — a modalidade da escala só conhece %s, nenhuma função '
             || 'menciona revezamento e, portanto, nada valida a jornada constitucional de '
             || '6 HORAS (CF art. 7º, XIV; ampliável a 8h só por negociação coletiva). Uma '
             || 'indústria em 3 turnos alternados cadastrada como escala comum de 8h roda '
             || 'sem protesto — e a 7ª e a 8ª hora de TODOS os turnos viram extra em juízo, '
             || 'do período inteiro. Correção: tipificar o revezamento no cadastro; acima '
             || 'de 6h de jornada, exigir o instrumento coletivo anexado (o mesmo fio do '
             || 'ESC-001), registrando o fundamento.',
             coalesce(v_mods, '(constraint de modalidade ausente)'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Revezamento tratado por: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_folha_001()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_aceitou boolean := false; v_gate text;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Criar rubrica SEM natureza do eSocial e sem nenhuma incidência definida';
  r.esperado := 'Aceita no máximo como rascunho — jamais utilizável em cálculo';
  BEGIN
    INSERT INTO public.folha_rubricas
      (tenant_id, codigo_interno, descricao, ativa)
    VALUES (v_t, 'QA-F001', 'QA Rubrica Sem Natureza', true);
    v_aceitou := true;
  EXCEPTION WHEN check_violation OR raise_exception OR not_null_violation THEN
    v_aceitou := false; END;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: alguém bloqueia o cálculo quando há rubrica sem classificação?';
  r.esperado := 'Função/trava que impeça processar com classificacao_esocial vazia (CA-001)';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_gate
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%classificacao_esocial%';

  IF v_aceitou AND v_gate IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a rubrica nasceu ATIVA sem natureza do eSocial nem incidências — '
             || 'classificacao_esocial é NULLABLE, as incidências têm DEFAULT false (que é '
             || 'uma DEFINIÇÃO, não uma pendência) e nenhuma função confere a classificação '
             || 'antes do cálculo. Rubrica sem S-1010 que entra na folha produz base errada '
             || 'de INSS/FGTS/IRRF e evento rejeitado — ou aceito com tributo errado, que é '
             || 'pior. O CA-001 manda BLOQUEAR o cálculo até definir. Correção: estado '
             || '"incompleta" para rubrica sem classificação + trava no processamento e no '
             || 'lançamento (a tabela distingue default de decisão).';
  ELSIF NOT v_aceitou THEN
    r.situacao := 'passou';
    r.obtido := 'A rubrica sem classificação foi recusada na criação.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Classificação conferida por: %s.', v_gate);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_folha_002()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_vig text; v_hist text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a tabela de rubricas tem vigência/versionamento?';
  r.esperado := 'Alteração de incidência cria vigência nova; o passado preserva a definição da época';
  v_vig := coalesce(public.qa_col_existe('folha_rubricas', 'vigencia%'),
                    public.qa_col_existe('folha_rubricas', '%versao%'));
  SELECT string_agg(DISTINCT t.tgname, ', ') INTO v_hist
  FROM pg_trigger t
  WHERE t.tgrelid = 'public.folha_rubricas'::regclass AND NOT t.tgisinternal
    AND t.tgname NOT ILIKE '%updated_at%' AND t.tgname NOT ILIKE 'qa\_%';

  IF v_vig IS NULL AND v_hist IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: folha_rubricas não tem vigência nem trilha de versão — um UPDATE '
             || 'na incidência vale retroativamente para TODAS as épocas, e nenhum gatilho '
             || 'guarda a definição anterior. A folha de março foi calculada com a regra de '
             || 'março; mudada a rubrica em agosto, a reprodução do cálculo (RNF-007) passa '
             || 'a dar outro resultado e a auditoria não consegue explicar a diferença. O '
             || 'contraste é didático: folha_tabelas_inss/irrf JÁ SÃO versionadas por '
             || 'vigência — falta aplicar o mesmo desenho à tabela que dirige o cálculo '
             || 'inteiro (e que o S-1010 também versiona por período). Correção: vigência '
             || 'na rubrica (ou tabela de vigências filha) + resolução por competência.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Versionamento presente (vigência: %s; trilha: %s).',
                       coalesce(v_vig, '—'), coalesce(v_hist, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_folha_030()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_per uuid; v_aceitou boolean := false; v_aut text;
BEGIN
  PERFORM public.qa_modo_ligar();

  INSERT INTO public.folha_periodos (tenant_id, competencia, status)
  VALUES (v_t, '2098-01', 'aberto')
  ON CONFLICT (tenant_id, competencia) DO UPDATE SET status = 'aberto'
  RETURNING id INTO v_per;

  r.passo_ordem := 1;
  r.passo_acao := 'Lançar desconto avulso sem amparo (sem rubrica, texto livre, valor alto)';
  r.esperado := 'Bloqueado — desconto só com amparo do art. 462 (lei, CCT ou adiantamento) e dentro do teto';
  BEGIN
    INSERT INTO public.folha_lancamentos
      (tenant_id, periodo_id, colaborador_id, colaborador_nome,
       rubrica_descricao, tipo, valor, origem)
    VALUES (v_t, v_per, 'qa-folha-030', 'QA Desconto Livre',
            'Desconto avulso sem amparo', 'DESCONTO', 950.00, 'manual');
    v_aceitou := true;
  EXCEPTION WHEN check_violation OR raise_exception OR foreign_key_violation THEN
    v_aceitou := false; END;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: existe registro de autorização (desconto sindical) e teto de VT?';
  r.esperado := 'Autorização expressa para sindical; limite de 6% para VT; tipos parametrizados';
  v_aut := coalesce(public.qa_col_existe(NULL, '%autorizacao_desconto%'),
                    public.qa_col_existe(NULL, '%desconto_sindical%'),
                    public.qa_fns_com('%desconto%462%'));

  IF v_aceitou AND v_aut IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o desconto entrou SEM AMPARO — folha_lancamentos aceita DESCONTO '
             || 'com descrição em texto livre, sem rubrica, sem teto e sem vínculo a lei/'
             || 'CCT/adiantamento; não existe registro de autorização para desconto '
             || 'sindical (facultativo desde a Lei 13.467) nem trava de 6% para o VT. O '
             || 'art. 462 é taxativo: desconto fora das hipóteses é devolução em dobro na '
             || 'reclamatória. Correção: lançamento de desconto exige rubrica classificada '
             || '(amparo declarado), teto por tipo (VT 6% do salário-base) e autorização '
             || 'arquivada quando a lei a exigir.';
  ELSIF NOT v_aceitou THEN
    r.situacao := 'passou';
    r.obtido := 'O desconto sem amparo foi recusado no lançamento.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Aceito com estrutura de amparo disponível (%s) — conferir a '
                       || 'obrigatoriedade no fluxo.', v_aut);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_folha_040()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): alguém calcula o 5º dia útil de verdade?';
  r.esperado := 'Motor de dias úteis (sábado conta, domingo/feriado não) alimentando o prazo do art. 459';
  -- procura pelo prazo de PAGAMENTO em dias úteis — cuidado com os parentes
  -- falsos: "media_utilizada" contém "dia_util", e a equalização do Ponto
  -- conta dias úteis para outra finalidade (jornada, não prazo do art. 459)
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%quinto%'
         OR ((p.prosrc ILIKE '%dia_util%' OR p.prosrc ILIKE '%dias_uteis%')
             AND (p.prosrc ILIKE '%pagamento%' OR p.prosrc ILIKE '%folha_alertas%')))
    AND p.proname NOT ILIKE '%noturno%' AND p.proname NOT ILIKE '%equalizacao%';

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o 5º dia útil não é calculado em lugar nenhum — a tela de alertas '
             || 'semeia o prazo de pagamento como DIA 7 FIXO ("aprox 5º útil", literalmente '
             || 'no código), sem olhar sábados, domingos nem a tabela feriados. Nos meses em '
             || 'que o 5º dia útil cai no dia 5 ou 6, o alerta chega DEPOIS do prazo legal — '
             || 'um vigia que acorda atrasado. E não há registro de pagamento × limite para '
             || 'acusar o atraso (art. 459, §1º). Correção: função de dias úteis (sábado '
             || 'conta para este fim; domingo/feriado não) alimentando folha_alertas_prazo '
             || 'com a data real, alertas D-3/2/1 e atraso acusado com trilha. Terceiro '
             || 'módulo pedindo o mesmo motor de datas (DEC13-031, DESL-015).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Motor de dias úteis presente: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_folha_050()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_rat text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): os encargos patronais têm estrutura?';
  r.esperado := 'Patronal 20% + RAT×FAP + terceiros parametrizados por empresa, com vigência';
  -- os pedaços existem espalhados: empresa_cadastro.fap_atual/historico é o
  -- MONITORAMENTO do FAP (SST) e ferias_config.encargo_rat_fap/terceiros é o
  -- provisionamento de FÉRIAS — nada disso calcula a patronal da competência
  v_rat := coalesce(public.qa_col_existe('empresa_cadastro', 'fap_%'),
                    public.qa_col_existe('ferias_config', 'encargo_%'));
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%patronal%'
    AND (p.prosrc ILIKE '%folha_itens%' OR p.prosrc ILIKE '%folha_periodos%'
         OR p.prosrc ILIKE '%competencia%');

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO (peças espalhadas, motor ausente): os INSUMOS até existem — '
             || 'o FAP da empresa é monitorado pelo SST (empresa_cadastro.fap_atual, '
             || 'alimentado por afastamentos_fap) e as férias provisionam com '
             || 'encargo_rat_fap/terceiros parametrizados (ferias_config) — mas NENHUMA '
             || 'função calcula a contribuição patronal da COMPETÊNCIA: 20%% + RAT×FAP + '
             || 'terceiros/FPAS sobre a base da folha não são apurados em lugar nenhum '
             || '(só o INSS do empregado, no React). Sem os patronais, a DCTFWeb não tem o '
             || 'que consolidar e o custo real da folha (~26,8%%+ acima do bruto) não '
             || 'aparece em painel nenhum. Estrutura encontrada: %s. Correção: parâmetros '
             || 'patronais por empresa/estabelecimento com vigência + apuração na '
             || 'competência, reaproveitando o FAP que o SST já mantém.',
             coalesce(v_rat, 'nenhuma'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Cálculo patronal presente (funções: %s; parâmetros: %s).',
                       v_fns, coalesce(v_rat, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_folha_051()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_reg text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o regime tributário da empresa existe e é consumido?';
  r.esperado := 'Regime (Real/Presumido/Simples/CPRB) por empresa, com vigência, decidindo os patronais';
  v_reg := coalesce(public.qa_col_existe(NULL, '%regime_tributario%'),
                    public.qa_col_existe('empresa_cadastro', '%regime%'),
                    public.qa_col_existe(NULL, '%desoneracao%'),
                    public.qa_col_existe(NULL, '%simples_nacional%'));
  v_fns := coalesce(public.qa_fns_com('%regime%tribut%'), public.qa_fns_com('%cprb%'));

  IF v_reg IS NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o regime tributário não existe no sistema — nenhuma coluna guarda '
             || 'o enquadramento (Lucro Real/Presumido, Simples Nacional, desoneração/CPRB) '
             || 'e nenhuma função o consulta. O regime decide o encargo patronal: empresa '
             || 'do Simples (maioria dos anexos) não recolhe a patronal sobre a folha; '
             || 'setor desonerado recolhe CPRB sobre a receita. Numa plataforma '
             || 'multiempresa, tratar todo mundo como Lucro Real erra o custo de quase '
             || 'todos os clientes pequenos. Encadeado ao FOLHA-050: primeiro a estrutura '
             || 'patronal, depois o regime que a module — ambos por empresa/estabelecimento '
             || 'com vigência ([RCE]/[VAL], seção 30).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Regime presente (campos: %s; funções: %s).',
                       coalesce(v_reg, '—'), coalesce(v_fns, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_folha_060()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text; v_tipos text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o fechamento da competência gera os eventos periódicos?';
  r.esperado := 'S-1200 por vínculo, S-1210 dos pagamentos e S-1299 até o dia 15, com prazo vigiado';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%S-1299%' OR p.prosrc ILIKE '%S1299%'
         OR p.prosrc ILIKE '%S-1200%' OR p.prosrc ILIKE '%S1200%');
  SELECT pg_get_constraintdef(c.oid) INTO v_tipos
  FROM pg_constraint c
  WHERE c.conrelid = 'public.folha_alertas_prazo'::regclass
    AND c.contype = 'c' AND pg_get_constraintdef(c.oid) ILIKE '%s1200%';

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO (metade boa, metade ausente): o controle de prazos JÁ CONHECE '
             || 'os eventos (folha_alertas_prazo tem os tipos esocial_s1200/s1210 no CHECK'
             || '%s), mas a GERAÇÃO não existe: nenhuma função monta S-1200 por vínculo, '
             || 'S-1210 dos pagamentos ou o S-1299 que FECHA os periódicos — e é o '
             || 'fechamento que libera a DCTFWeb. O alerta, além disso, é semeado pela tela '
             || 'com dia 15 fixo só quando alguém abre a aba. Sem os eventos, a folha '
             || 'inteira não existe para o governo — mesmo vazio já achado no 13º '
             || '(DEC13-050) e no desligamento (DESL-091/093). Correção: geração dos três '
             || 'eventos no fechamento aprovado + fila com anti-duplicidade (série '
             || 'ADM-093/DESL-094) + dia 15 vigiado por rotina, não por visita à tela.',
             CASE WHEN v_tipos IS NOT NULL THEN '' ELSE ' — mas o CHECK não os lista mais' END);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Geração dos periódicos presente: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_folha_061()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_est text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): as guias tributárias nascem conciliadas com a folha?';
  r.esperado := 'DARF consolidado pela DCTFWeb e guia do FGTS Digital, com bases batendo com a competência fechada';
  v_est := coalesce(public.qa_fns_com('%dctf%'), public.qa_fns_com('%darf%'),
                    public.qa_col_existe(NULL, '%dctf%'),
                    public.qa_fns_com('%fgts%'));

  IF v_est IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: DCTFWeb e FGTS Digital não existem no banco — nenhuma função ou '
             || 'coluna trata DARF, consolidação ou guia de FGTS mensal. O que há é o '
             || 'hub_guias do Hub Contábil: registro GENÉRICO digitado à mão (mesmo achado '
             || 'do DESL-057 na guia rescisória), que anota a guia mas não a GERA da folha '
             || 'fechada nem CONCILIA os valores — a diferença entre a guia paga e o '
             || 'encargo apurado fica para a fiscalização encontrar. Correção: após o '
             || 'fechamento (FOLHA-060), gerar as guias com as bases da competência, acusar '
             || 'divergência na conciliação e arquivar comprovantes vinculados. O '
             || 'CALENDÁRIO dos envios é da família HCAL — aqui é o CONTEÚDO da guia.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Estrutura de guias presente: %s.', v_est);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_folha_070()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_col text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a folha complementar tem onde existir?';
  r.esperado := 'Competência complementar vinculada à original, com diferenças por vínculo e retificação do eSocial';
  v_col := coalesce(public.qa_col_existe('folha_periodos', '%complementar%'),
                    public.qa_col_existe('folha_periodos', '%tipo%'),
                    public.qa_col_existe('folha_periodos', '%origem%'));
  v_fns := coalesce(public.qa_fns_com('%complementar%'), public.qa_fns_com('%dissidio%'));

  IF v_col IS NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a folha complementar não tem onde viver — folha_periodos só tem a '
             || 'competência YYYY-MM com UNIQUE(tenant, competencia): não há tipo '
             || '(normal/complementar), não há vínculo a uma competência de origem e '
             || 'nenhuma função apura diferenças de dissídio. A unicidade, correta para a '
             || 'folha normal, IMPEDE a complementar por desenho: reajuste retroativo da '
             || 'CCT ou vira edição da competência fechada (trilha destruída) ou fica de '
             || 'fora (passivo). Terceiro módulo com o mesmo vazio (DEC13-033, DESL-105). '
             || 'Correção: tipo de período + referência à competência-mãe (a unicidade '
             || 'passa a valer por tenant+competência+tipo) + apuração das diferenças com '
             || 'S-1200 retificado/complementar.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Estrutura presente (campos: %s; funções: %s).',
                       coalesce(v_col, '—'), coalesce(v_fns, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_folha_071()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_per uuid; v_lancou boolean := false; v_reabriu boolean := false;
BEGIN
  PERFORM public.qa_modo_ligar();

  INSERT INTO public.folha_periodos (tenant_id, competencia, status, data_fechamento)
  VALUES (v_t, '2098-02', 'fechado', CURRENT_DATE)
  ON CONFLICT (tenant_id, competencia) DO UPDATE SET status = 'fechado'
  RETURNING id INTO v_per;

  r.passo_ordem := 1;
  r.passo_acao := 'Lançar valor novo numa competência com status FECHADO';
  r.esperado := 'Bloqueado — fechado é imutável; correção só por reabertura com rito';
  BEGIN
    INSERT INTO public.folha_lancamentos
      (tenant_id, periodo_id, colaborador_id, colaborador_nome,
       rubrica_descricao, tipo, valor, origem)
    VALUES (v_t, v_per, 'qa-folha-071', 'QA Fechado Editado',
            'Lançamento pós-fechamento', 'PROVENTO', 1234.56, 'manual');
    v_lancou := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_lancou := false; END;

  r.passo_ordem := 2;
  r.passo_acao := 'Reabrir a competência com um UPDATE simples de status, sem motivo nem aprovação';
  r.esperado := 'Bloqueado — reabertura exige motivo, dupla aprovação e trilha';
  BEGIN
    UPDATE public.folha_periodos SET status = 'aberto', data_fechamento = NULL
    WHERE id = v_per;
    v_reabriu := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_reabriu := false; END;

  IF v_lancou OR v_reabriu THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o fechamento é decorativo — lançamento novo em competência '
             || 'FECHADA foi %s e a reabertura por UPDATE simples (sem motivo, sem '
             || 'aprovação, sem trilha além do fechado_por original) foi %s. O status '
             || 'existe e o ciclo existe, mas nenhum gatilho os DEFENDE: holerite entregue, '
             || 'evento transmitido e banco podem contar três histórias. Correção: gatilho '
             || 'que rejeite INSERT/UPDATE/DELETE em lançamentos e itens de competência '
             || 'fechada + fluxo de reabertura com motivo e dupla aprovação registrados '
             || '(disciplina de FERIAS-054, DEC13-070 e DESL-106 — quarto módulo).',
             CASE WHEN v_lancou THEN 'ACEITO' ELSE 'recusado' END,
             CASE WHEN v_reabriu THEN 'ACEITA' ELSE 'recusada' END);
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Competência fechada imutável e reabertura direta bloqueada.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_folha_080()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_ponte text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): os eventos dos módulos chegam conciliados à folha?';
  r.esperado := 'Importação com origem rastreável (Ponto, Férias, 13º, Afastamentos) e divergência acusada';
  v_ponte := CASE WHEN to_regclass('public.ponto_exportacoes_folha') IS NOT NULL
                  THEN 'ponto_exportacoes_folha' END;
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%ponto_exportacoes_folha%'
         OR (p.prosrc ILIKE '%folha_lancamentos%' AND p.prosrc ILIKE '%concilia%'));

  IF v_ponte IS NOT NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a ponte existe SÓ do lado do Ponto — ponto_exportacoes_folha '
             || 'guarda a apuração exportada, mas nenhuma função a importa para '
             || 'folha_lancamentos nem concilia o apurado com o lançado; Férias, 13º e '
             || 'Afastamentos nem ponte têm. Na prática o DP redigita na folha o que o '
             || 'Ponto apurou — e a hora extra que ficar de fora não é acusada por '
             || 'ninguém: o holerite sai menor e ninguém sabe. A origem "manual" domina '
             || 'folha_lancamentos. Correção: importação por competência com origem '
             || 'rastreável (modulo + referência) + conciliação apurado × lançado '
             || 'acusando diferença ANTES do fechamento (alerta da seção 14).';
  ELSIF v_ponte IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A tabela ponto_exportacoes_folha não existe mais nesta base.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Conciliação presente: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_folha_081()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_hist text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a competência é comparada com o histórico antes de fechar?';
  r.esperado := 'Variação atípica (custo, rubrica, vínculo) destacada na conferência do fechamento';
  v_hist := CASE WHEN to_regclass('public.folha_historico') IS NOT NULL
                 THEN 'folha_historico' END;
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%folha_historico%' OR p.prosrc ILIKE '%variacao%'
         OR p.prosrc ILIKE '%atipic%');

  IF v_hist IS NOT NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a matéria-prima existe (folha_historico guarda as competências) e '
             || 'ninguém a compara — nenhuma função confronta a competência atual com o '
             || 'histórico para destacar salto de custo, rubrica que dobrou ou líquido fora '
             || 'do padrão. É [BPR], não obrigação legal — mas é a diferença entre pegar o '
             || 'zero a mais NA CONFERÊNCIA e pegá-lo na reabertura com retificação de '
             || 'eSocial e complementar (a "folha sem surpresa" da seção 29). Correção: '
             || 'conferência de fechamento com comparativo por rubrica/vínculo e limiar '
             || 'parametrizável de variação.';
  ELSIF v_hist IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A tabela folha_historico não existe mais nesta base.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Comparativo presente: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_folha_090()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_leitura_aberta int; v_restr int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): quem consegue LER os itens da folha?';
  r.esperado := 'Leitura restrita aos papéis da folha; colaborador só o próprio holerite; camada de perfil presente';
  SELECT count(*) INTO v_leitura_aberta
  FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'folha_itens'
    AND cmd IN ('SELECT','ALL') AND permissive = 'PERMISSIVE'
    AND qual NOT ILIKE '%has_minimum_role%' AND qual NOT ILIKE '%auth.uid%';
  SELECT count(*) INTO v_restr
  FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'folha_itens'
    AND permissive = 'RESTRICTIVE';

  IF v_leitura_aberta > 0 AND v_restr = 0 THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a ESCRITA da folha é bem defendida (manager+ para gerenciar — '
             || 'melhor que o 13º e a rescisão), mas a LEITURA está aberta: a política '
             || '"Usuários podem ver itens do tenant" entrega folha_itens INTEIRA — '
             || 'salário, descontos e líquido de todos — a QUALQUER usuário autenticado da '
             || 'empresa, colaborador comum incluído. É exatamente o cenário "colaborador '
             || 'tenta ver a folha da equipe" que a seção 25 manda bloquear, e a tabela '
             || 'está fora da camada perfil_restringe_leitura_*. Correção: leitura por '
             || 'papel (manager+) OU restrita ao próprio registro (colaborador vê só o '
             || 'seu item/holerite) + política RESTRICTIVE via perfil_permite_modulo — '
             || 'fechando a série DEC13-071/DESL-110 no módulo mais denso de remuneração.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Leitura defendida (políticas abertas: %s; restritivas: %s).',
                       v_leitura_aberta, v_restr);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_hcal_001()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_cal uuid; s record; v_comp text := to_char(CURRENT_DATE, 'YYYY-MM');
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem := 1; r.passo_acao := 'Criar item de calendário com dia-limite 5';
  r.esperado := 'Item gravado';
  INSERT INTO public.hub_calendario_envios (tenant_id, titulo, tipo, categoria, dia_limite)
  VALUES (v_t, '[QA-HCAL] Enviar espelhos de ponto', 'envio', 'folha', 5)
  RETURNING id INTO v_cal;

  r.passo_ordem := 2; r.passo_acao := 'Marcar a competência corrente como concluída';
  r.esperado := 'Status gravado com autor e data';
  INSERT INTO public.hub_calendario_status
    (tenant_id, calendario_id, competencia, status, concluido_por, concluido_em)
  VALUES (v_t, v_cal, v_comp, 'concluido', '[QA] Agente', now());

  SELECT * INTO s FROM public.hub_calendario_status
  WHERE calendario_id = v_cal AND competencia = v_comp;
  IF s.status = 'concluido' AND s.concluido_por IS NOT NULL AND s.concluido_em IS NOT NULL THEN
    r.situacao := 'passou'; r.obtido := 'Item e status gravados por inteiro, com autor e data.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'O status não persistiu como gravado.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_hcal_010()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem := 1; r.passo_acao := 'Criar item com dia-limite 32';
  r.esperado := 'Recusado pelo CHECK (1..31)';
  BEGIN
    INSERT INTO public.hub_calendario_envios (tenant_id, titulo, tipo, categoria, dia_limite)
    VALUES (v_t, '[QA-HCAL] Dia 32', 'envio', 'folha', 32);
    r.situacao := 'falhou'; r.obtido := 'ACEITOU dia-limite 32 — dia que não existe em mês nenhum.';
    RETURN r;
  EXCEPTION WHEN check_violation THEN
    r.obtido := 'Recusado 32.';
  END;

  r.passo_ordem := 2; r.passo_acao := 'Criar item com dia-limite 0';
  r.esperado := 'Recusado';
  BEGIN
    INSERT INTO public.hub_calendario_envios (tenant_id, titulo, tipo, categoria, dia_limite)
    VALUES (v_t, '[QA-HCAL] Dia 0', 'envio', 'folha', 0);
    r.situacao := 'falhou'; r.obtido := 'Recusou 32 mas ACEITOU 0.';
  EXCEPTION WHEN check_violation THEN
    r.situacao := 'passou'; r.obtido := 'Só entram dias de 1 a 31 — o CHECK segue de pé.';
  END;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_hcal_011()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_cal uuid; v_comp text := to_char(CURRENT_DATE, 'YYYY-MM');
BEGIN
  PERFORM public.qa_modo_ligar();
  INSERT INTO public.hub_calendario_envios (tenant_id, titulo, tipo, categoria, dia_limite)
  VALUES (v_t, '[QA-HCAL] Sem Duplicata', 'envio', 'guias', 10) RETURNING id INTO v_cal;
  INSERT INTO public.hub_calendario_status (tenant_id, calendario_id, competencia, status)
  VALUES (v_t, v_cal, v_comp, 'pendente');

  r.passo_ordem := 1;
  r.passo_acao := 'Inserir segundo status para o mesmo item e competência';
  r.esperado := 'Recusado pelo UNIQUE (tenant, calendário, competência)';
  BEGIN
    INSERT INTO public.hub_calendario_status (tenant_id, calendario_id, competencia, status)
    VALUES (v_t, v_cal, v_comp, 'concluido');
    r.situacao := 'falhou';
    r.obtido := 'ACEITOU dois status para a mesma competência — o item pode constar concluído e pendente ao mesmo tempo.';
  EXCEPTION WHEN unique_violation THEN
    r.situacao := 'passou'; r.obtido := 'Uma competência, um status — duplicata barrada pelo UNIQUE.';
  END;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_hcat_001()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); c record;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem := 1;
  r.passo_acao := 'Cadastrar documento do catálogo para o tipo admissao, obrigatório, retenção de 5 anos';
  r.esperado := 'Item gravado com tipo de processo, obrigatoriedade e retenção';
  INSERT INTO public.hub_catalogo_documentos
    (tenant_id, nome, processo_tipo, obrigatoriedade, requer_assinatura, prazo_retencao_anos, ordem)
  VALUES (v_t, '[QA-HCAT] Contrato de Trabalho', 'admissao', 'obrigatorio', true, 5, 1)
  RETURNING * INTO c;

  IF c.processo_tipo::text = 'admissao' AND c.obrigatoriedade = 'obrigatorio' AND c.prazo_retencao_anos = 5 THEN
    r.situacao := 'passou'; r.obtido := 'Catálogo gravado e relido por inteiro.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'O item do catálogo não persistiu como gravado.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_hcat_010()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_livre boolean := false; v_neg boolean := false;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1; r.passo_acao := 'Cadastrar item com obrigatoriedade = talvez';
  r.esperado := 'Recusado — lista fechada (obrigatorio/opcional/condicional)';
  BEGIN
    INSERT INTO public.hub_catalogo_documentos (tenant_id, nome, processo_tipo, obrigatoriedade, ordem)
    VALUES (v_t, '[QA-HCAT] Obrigatoriedade Livre', 'admissao', 'talvez', 90);
    v_livre := true;
  EXCEPTION WHEN check_violation THEN v_livre := false;
  END;

  r.passo_ordem := 2; r.passo_acao := 'Cadastrar item com retenção de -5 anos';
  r.esperado := 'Recusado — retenção é não negativa';
  BEGIN
    INSERT INTO public.hub_catalogo_documentos (tenant_id, nome, processo_tipo, obrigatoriedade, prazo_retencao_anos, ordem)
    VALUES (v_t, '[QA-HCAT] Retencao Negativa', 'admissao', 'obrigatorio', -5, 91);
    v_neg := true;
  EXCEPTION WHEN check_violation THEN v_neg := false;
  END;

  IF NOT v_livre AND NOT v_neg THEN
    r.situacao := 'passou'; r.obtido := 'Obrigatoriedade fora da lista e retenção negativa recusadas.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACEITOU o que não devia (obrigatoriedade livre: %s; retenção negativa: %s). '
      || 'Obrigatoriedade é texto sem lista fechada — valor inventado quebra o semeador de checklist '
      || 'em silêncio; retenção negativa é prazo que venceu antes de existir. Correção: CHECK de '
      || 'lista (obrigatorio/opcional/condicional) e CHECK (prazo_retencao_anos >= 0).', v_livre, v_neg);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_hier_001()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_grupo uuid; v_emp uuid; v_grupo_da_emp uuid;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Cadastrar um grupo economico';
  r.esperado:='A empresa fica vinculada ao grupo';
  INSERT INTO public.grupos_economicos (tenant_id, nome)
  VALUES (v_t, '[QA] Grupo Teste') RETURNING id INTO v_grupo;
  r.passo_ordem:=2; r.passo_acao:='Vincular a empresa ao grupo';
  INSERT INTO public.empresa_cadastro (tenant_id, razao_social, cnpj, grupo_economico_id)
  VALUES (v_t, '[QA] Empresa Do Grupo', '11333444000181', v_grupo) RETURNING id INTO v_emp;
  SELECT grupo_economico_id INTO v_grupo_da_emp FROM public.empresa_cadastro WHERE id=v_emp;
  IF v_grupo_da_emp = v_grupo THEN
    r.situacao:='passou'; r.obtido:='Empresa vinculada ao grupo economico.';
  ELSE
    r.situacao:='falhou'; r.obtido:='A empresa nao referenciou o grupo.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_hier_002()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_grupo uuid; v_emp uuid; v_existe boolean; v_grupo_da_emp uuid;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Criar grupo com uma empresa vinculada';
  r.esperado:='Apagar o grupo preserva a empresa (SET NULL)';
  INSERT INTO public.grupos_economicos (tenant_id, nome)
  VALUES (v_t, '[QA] Grupo Que Sera Apagado') RETURNING id INTO v_grupo;
  INSERT INTO public.empresa_cadastro (tenant_id, razao_social, cnpj, grupo_economico_id)
  VALUES (v_t, '[QA] Empresa Sobrevivente', '11333444000262', v_grupo) RETURNING id INTO v_emp;

  r.passo_ordem:=2; r.passo_acao:='Apagar o grupo economico';
  DELETE FROM public.grupos_economicos WHERE id=v_grupo;

  r.passo_ordem:=3; r.passo_acao:='Conferir que a empresa sobreviveu';
  SELECT EXISTS(SELECT 1 FROM public.empresa_cadastro WHERE id=v_emp) INTO v_existe;
  SELECT grupo_economico_id INTO v_grupo_da_emp FROM public.empresa_cadastro WHERE id=v_emp;
  IF v_existe AND v_grupo_da_emp IS NULL THEN
    r.situacao:='passou';
    r.obtido:='Grupo apagado; a empresa sobreviveu, agora sem grupo (SET NULL). Nenhum cadastro destruido.';
  ELSE
    r.situacao:='falhou';
    r.obtido:=format('Empresa existe=%s, grupo=%s. Se a empresa sumiu, apagar um grupo destroi cadastros inteiros.',
                     v_existe, v_grupo_da_emp);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_htpl_001()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_cliente uuid; v_global_bloqueado boolean := false; v_anulavel boolean;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem := 1;
  r.passo_acao := 'Criar template do cliente para o tipo ferias';
  r.esperado := 'Gravado com tenant do cercado';
  INSERT INTO public.hub_checklist_templates (tenant_id, tipo, item, obrigatorio, ordem)
  VALUES (v_t, 'ferias', '[QA-HTPL] Conferencia interna do cliente', false, 91)
  RETURNING id INTO v_cliente;

  r.passo_ordem := 2;
  r.passo_acao := 'Tentar criar template GLOBAL (tenant nulo) de dentro do teste';
  r.esperado := 'Bloqueado pela cerca do cercado';
  BEGIN
    INSERT INTO public.hub_checklist_templates (tenant_id, tipo, item, obrigatorio, ordem)
    VALUES (NULL, 'ferias', '[QA-HTPL] Global indevido', true, 90);
    v_global_bloqueado := false;
  EXCEPTION WHEN OTHERS THEN
    v_global_bloqueado := true;
  END;

  r.passo_ordem := 3;
  r.passo_acao := 'Conferir o contrato do global por catálogo';
  r.esperado := 'tenant_id anulável — o modelo global existe';
  SELECT (is_nullable = 'YES') INTO v_anulavel
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'hub_checklist_templates'
    AND column_name = 'tenant_id';

  IF v_cliente IS NOT NULL AND v_global_bloqueado AND COALESCE(v_anulavel, false) THEN
    r.situacao := 'passou';
    r.obtido := 'Template do cliente gravado; a cerca impediu o teste de escrever configuração global (proteção correta); o contrato global (tenant nulo) existe no schema.';
  ELSIF NOT v_global_bloqueado THEN
    r.situacao := 'falhou';
    r.obtido := 'O TESTE CONSEGUIU ESCREVER TEMPLATE GLOBAL: uma rotina de QA gravou configuração que vale para TODOS os clientes — a cerca do cercado não cobre escrita com tenant nulo nesta tabela.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Template do cliente: %s; tenant_id anulável: %s.', v_cliente IS NOT NULL, v_anulavel);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_htpl_010()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem := 1; r.passo_acao := 'Criar template com tipo = processo_inventado';
  r.esperado := 'Recusado — o tipo precisa existir no enum hub_processo_tipo';
  BEGIN
    INSERT INTO public.hub_checklist_templates (tenant_id, tipo, item, obrigatorio, ordem)
    VALUES (v_t, 'processo_inventado', '[QA-HTPL] Item orfao', true, 95);
    r.situacao := 'falhou';
    r.obtido := 'ACEITOU template com tipo que nenhum processo reconhece — configuração morta que a '
      || 'tela lista e o semeador de checklist nunca usa. hub_processos.tipo é enum fechado; o tipo '
      || 'do template é texto livre. Correção: converter a coluna para o enum ou CHECK contra os rótulos.';
  EXCEPTION WHEN check_violation OR invalid_text_representation THEN
    r.situacao := 'passou'; r.obtido := 'Tipo fora do enum recusado.';
  END;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_jor_001()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_id uuid;
        v_jor text; v_3t boolean; v_esc boolean; v_ins boolean; v_alt boolean;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1;
  r.passo_acao:='Registrar jornada 44h, terceiro turno, escalas especiais, insalubridade e trabalho em altura';
  r.esperado:='Jornada e condicoes persistidas';
  INSERT INTO public.empresa_cadastro
    (tenant_id, razao_social, cnpj, jornada_padrao, possui_terceiro_turno,
     possui_escalas_especiais, insalubridade, trabalho_altura, espaco_confinado, periculosidade)
  VALUES (v_t, '[QA] Industria Tres Turnos', '11222333000767', '44h semanais',
          true, true, true, true, false, false) RETURNING id INTO v_id;
  SELECT jornada_padrao, possui_terceiro_turno, possui_escalas_especiais,
         insalubridade, trabalho_altura
    INTO v_jor, v_3t, v_esc, v_ins, v_alt FROM public.empresa_cadastro WHERE id=v_id;
  IF v_jor='44h semanais' AND v_3t AND v_esc AND v_ins AND v_alt THEN
    r.situacao:='passou';
    r.obtido:='Jornada 44h, terceiro turno, escalas especiais, insalubridade e trabalho em altura registrados.';
  ELSE
    r.situacao:='falhou';
    r.obtido:=format('jornada=%s, 3turno=%s, escalas=%s, insalubridade=%s, altura=%s.',
                     v_jor, v_3t, v_esc, v_ins, v_alt);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_jor_002()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_id uuid; v_qtd int;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Registrar tres turnos com seus horarios';
  r.esperado:='Os tres turnos guardados como lista estruturada';
  INSERT INTO public.empresa_cadastro (tenant_id, razao_social, cnpj, turnos)
  VALUES (v_t, '[QA] Empresa Com Turnos', '11222333000848',
    '[{"nome":"1o turno","inicio":"06:00","fim":"14:00"},
      {"nome":"2o turno","inicio":"14:00","fim":"22:00"},
      {"nome":"3o turno","inicio":"22:00","fim":"06:00"}]'::jsonb)
  RETURNING id INTO v_id;
  SELECT jsonb_array_length(turnos) INTO v_qtd FROM public.empresa_cadastro WHERE id=v_id;
  IF v_qtd = 3 THEN
    r.situacao:='passou'; r.obtido:='3 turnos guardados como lista, cada um com inicio e fim.';
  ELSE
    r.situacao:='falhou'; r.obtido:=format('Esperava 3 turnos, achou %s.', v_qtd);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_jor_010()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_id uuid;
        v_3t boolean; v_qtd int;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Declarar terceiro turno sem cadastrar nenhum turno';
  r.esperado:='Aceito, mas a inconsistencia de preenchimento fica sem sinalizacao';
  INSERT INTO public.empresa_cadastro
    (tenant_id, razao_social, cnpj, possui_terceiro_turno, turnos)
  VALUES (v_t, '[QA] Terceiro Turno Sem Turnos', '11222333000929', true, '[]'::jsonb)
  RETURNING id INTO v_id;
  SELECT possui_terceiro_turno, jsonb_array_length(turnos) INTO v_3t, v_qtd
    FROM public.empresa_cadastro WHERE id=v_id;
  IF v_3t AND v_qtd = 0 THEN
    r.situacao:='passou';
    r.obtido:='Aceito: terceiro turno declarado com lista de turnos vazia. E preenchimento gradual, nao defeito — mas ninguem e avisado da pendencia.';
  ELSE
    r.situacao:='falhou'; r.obtido:=format('3turno=%s, turnos=%s.', v_3t, v_qtd);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ouv_003()
 RETURNS qa_retorno
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE r public.qa_retorno; v_def text; v_faltam text := '';
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir no banco que os cinco tipos de manifestacao sao aceitos';
  r.esperado    := 'CHECK de tipo aceita sugestao, reclamacao, denuncia, elogio e duvida';
  IF to_regclass('public.ouvidoria') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Tabela ouvidoria ausente neste ambiente.'; RETURN r;
  END IF;
  SELECT string_agg(pg_get_constraintdef(c.oid), ' ') INTO v_def
  FROM pg_constraint c
  WHERE c.conrelid = 'public.ouvidoria'::regclass AND c.contype = 'c'
    AND pg_get_constraintdef(c.oid) LIKE '%tipo%';
  v_def := COALESCE(v_def, '');
  IF position('sugestao'  IN v_def) = 0 THEN v_faltam := v_faltam || 'sugestao '; END IF;
  IF position('reclamacao' IN v_def) = 0 THEN v_faltam := v_faltam || 'reclamacao '; END IF;
  IF position('denuncia'  IN v_def) = 0 THEN v_faltam := v_faltam || 'denuncia '; END IF;
  IF position('elogio'    IN v_def) = 0 THEN v_faltam := v_faltam || 'elogio '; END IF;
  IF position('duvida'    IN v_def) = 0 THEN v_faltam := v_faltam || 'duvida '; END IF;
  IF v_faltam = '' THEN
    r.situacao := 'passou'; r.obtido := 'Os cinco tipos estao no CHECK de tipo.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'Tipos ausentes no CHECK: ' || v_faltam;
  END IF;
  r.detalhe := jsonb_build_object('constraint', v_def);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ouv_004()
 RETURNS qa_retorno
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE r public.qa_retorno; v boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir que o banco exige o assunto (envio sem assunto e recusado)';
  r.esperado    := 'ouvidoria.assunto e NOT NULL';
  IF to_regclass('public.ouvidoria') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Tabela ouvidoria ausente neste ambiente.'; RETURN r;
  END IF;
  SELECT a.attnotnull INTO v FROM pg_attribute a
  WHERE a.attrelid = 'public.ouvidoria'::regclass AND a.attname = 'assunto' AND NOT a.attisdropped;
  IF v IS TRUE THEN
    r.situacao := 'passou'; r.obtido := 'assunto e obrigatorio no banco; envio sem assunto e recusado.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'assunto NAO e obrigatorio — o banco aceitaria manifestacao sem assunto.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ouv_005()
 RETURNS qa_retorno
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE r public.qa_retorno; v boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir que o banco exige a mensagem';
  r.esperado    := 'ouvidoria.mensagem e NOT NULL';
  IF to_regclass('public.ouvidoria') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Tabela ouvidoria ausente neste ambiente.'; RETURN r;
  END IF;
  SELECT a.attnotnull INTO v FROM pg_attribute a
  WHERE a.attrelid = 'public.ouvidoria'::regclass AND a.attname = 'mensagem' AND NOT a.attisdropped;
  IF v IS TRUE THEN
    r.situacao := 'passou'; r.obtido := 'mensagem e obrigatoria no banco; envio sem mensagem e recusado.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'mensagem NAO e obrigatoria — o banco aceitaria manifestacao sem mensagem.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ouv_010()
 RETURNS qa_retorno
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE r public.qa_retorno; v_rls boolean; v_check text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir que o banco protege o anonimato: RLS ligada e a regra de insercao amarra anonimato e autoria';
  r.esperado    := 'RLS ligada; politica de INSERT exige (anonimo e sem autor) ou (identificado e autor = usuario logado)';
  IF to_regclass('public.ouvidoria') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Tabela ouvidoria ausente neste ambiente.'; RETURN r;
  END IF;
  SELECT relrowsecurity INTO v_rls FROM pg_class WHERE oid = 'public.ouvidoria'::regclass;
  SELECT with_check INTO v_check FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'ouvidoria' AND cmd = 'INSERT'
  ORDER BY policyname LIMIT 1;
  v_check := COALESCE(v_check, '');
  IF v_rls IS NOT TRUE THEN
    r.situacao := 'falhou'; r.obtido := 'RLS esta DESLIGADA em ouvidoria — a fila ficaria exposta.';
  ELSIF position('anonimo' IN v_check) > 0 AND position('autor_id' IN v_check) > 0 THEN
    r.situacao := 'passou';
    r.obtido := 'RLS ligada e a politica de INSERT amarra anonimato e autoria; anonimo nasce sem autor.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'A politica de INSERT nao amarra anonimato/autoria como esperado (with_check: ' || left(v_check, 120) || ').';
  END IF;
  r.detalhe := jsonb_build_object('rls', v_rls, 'with_check', v_check);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ouv_023()
 RETURNS qa_retorno
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE r public.qa_retorno; v_def text; v_faltam text := '';
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir que o banco aceita todo o ciclo de status do tratamento';
  r.esperado    := 'CHECK de status aceita pendente, em_analise, respondido e arquivado';
  IF to_regclass('public.ouvidoria') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Tabela ouvidoria ausente neste ambiente.'; RETURN r;
  END IF;
  SELECT string_agg(pg_get_constraintdef(c.oid), ' ') INTO v_def
  FROM pg_constraint c
  WHERE c.conrelid = 'public.ouvidoria'::regclass AND c.contype = 'c'
    AND pg_get_constraintdef(c.oid) LIKE '%status%';
  v_def := COALESCE(v_def, '');
  IF position('pendente'   IN v_def) = 0 THEN v_faltam := v_faltam || 'pendente '; END IF;
  IF position('em_analise' IN v_def) = 0 THEN v_faltam := v_faltam || 'em_analise '; END IF;
  IF position('respondido' IN v_def) = 0 THEN v_faltam := v_faltam || 'respondido '; END IF;
  IF position('arquivado'  IN v_def) = 0 THEN v_faltam := v_faltam || 'arquivado '; END IF;
  IF v_faltam = '' THEN
    r.situacao := 'passou'; r.obtido := 'O ciclo de status esta completo no CHECK.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'Status ausentes no CHECK: ' || v_faltam;
  END IF;
  r.detalhe := jsonb_build_object('constraint', v_def);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ouv_024()
 RETURNS qa_retorno
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE r public.qa_retorno; v_def text; v_faltam text := '';
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir que o banco aceita as prioridades de tratamento';
  r.esperado    := 'CHECK de prioridade aceita baixa, normal, alta e urgente';
  IF to_regclass('public.ouvidoria') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Tabela ouvidoria ausente neste ambiente.'; RETURN r;
  END IF;
  SELECT string_agg(pg_get_constraintdef(c.oid), ' ') INTO v_def
  FROM pg_constraint c
  WHERE c.conrelid = 'public.ouvidoria'::regclass AND c.contype = 'c'
    AND pg_get_constraintdef(c.oid) LIKE '%prioridade%';
  v_def := COALESCE(v_def, '');
  IF position('baixa'   IN v_def) = 0 THEN v_faltam := v_faltam || 'baixa '; END IF;
  IF position('normal'  IN v_def) = 0 THEN v_faltam := v_faltam || 'normal '; END IF;
  IF position('alta'    IN v_def) = 0 THEN v_faltam := v_faltam || 'alta '; END IF;
  IF position('urgente' IN v_def) = 0 THEN v_faltam := v_faltam || 'urgente '; END IF;
  IF v_faltam = '' THEN
    r.situacao := 'passou'; r.obtido := 'As quatro prioridades estao no CHECK.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'Prioridades ausentes no CHECK: ' || v_faltam;
  END IF;
  r.detalhe := jsonb_build_object('constraint', v_def);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ouv_031()
 RETURNS qa_retorno
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE r public.qa_retorno; v_rls boolean; v_admin boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir que a configuracao de roteamento existe e e restrita a administrador';
  r.esperado    := 'ouvidoria_roteamento com RLS ligada e politica de gestao exigindo papel de administrador';
  IF to_regclass('public.ouvidoria_roteamento') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Tabela ouvidoria_roteamento ausente neste ambiente.'; RETURN r;
  END IF;
  SELECT relrowsecurity INTO v_rls FROM pg_class WHERE oid = 'public.ouvidoria_roteamento'::regclass;
  SELECT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'ouvidoria_roteamento'
      AND cmd IN ('ALL','INSERT','UPDATE')
      AND COALESCE(qual,'') || COALESCE(with_check,'') LIKE '%has_minimum_role%'
      AND COALESCE(qual,'') || COALESCE(with_check,'') LIKE '%admin%'
  ) INTO v_admin;
  IF v_rls IS TRUE AND v_admin THEN
    r.situacao := 'passou'; r.obtido := 'Roteamento protegido: RLS ligada e gestao restrita a administrador.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'Roteamento sem a protecao esperada (rls=' || COALESCE(v_rls::text,'?')
             || ', politica_admin=' || COALESCE(v_admin::text,'?') || ').';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ouv_033()
 RETURNS qa_retorno
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE r public.qa_retorno; v_qual text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir que a exclusao de manifestacao exige papel de administrador';
  r.esperado    := 'politica de DELETE em ouvidoria exige has_minimum_role de administrador';
  IF to_regclass('public.ouvidoria') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Tabela ouvidoria ausente neste ambiente.'; RETURN r;
  END IF;
  SELECT qual INTO v_qual FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'ouvidoria' AND cmd = 'DELETE'
  ORDER BY policyname LIMIT 1;
  IF v_qual IS NULL THEN
    r.situacao := 'falhou'; r.obtido := 'Nao ha politica de DELETE em ouvidoria — a exclusao nao esta restrita.';
  ELSIF position('has_minimum_role' IN v_qual) > 0 AND position('admin' IN v_qual) > 0 THEN
    r.situacao := 'passou'; r.obtido := 'A exclusao exige papel de administrador, como esperado.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'A politica de DELETE nao exige administrador (qual: ' || left(v_qual,120) || ').';
  END IF;
  r.detalhe := jsonb_build_object('delete_qual', v_qual);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_ouv_034()
 RETURNS qa_retorno
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE r public.qa_retorno; v_propria boolean; v_gestor boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir que a leitura da fila e segmentada: colaborador ve so as proprias, gestao ve todas';
  r.esperado    := 'uma politica de SELECT restringe ao proprio autor e outra libera para papel de gestao';
  IF to_regclass('public.ouvidoria') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Tabela ouvidoria ausente neste ambiente.'; RETURN r;
  END IF;
  SELECT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='ouvidoria' AND cmd='SELECT'
      AND position('autor_id' IN COALESCE(qual,'')) > 0
      AND position('auth.uid' IN COALESCE(qual,'')) > 0
  ) INTO v_propria;
  SELECT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='ouvidoria' AND cmd='SELECT'
      AND position('has_minimum_role' IN COALESCE(qual,'')) > 0
  ) INTO v_gestor;
  IF v_propria AND v_gestor THEN
    r.situacao := 'passou';
    r.obtido := 'A fila e segmentada por perfil: colaborador ve as proprias, gestao ve todas.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'Faltou uma das politicas de leitura (propria=' || v_propria::text
             || ', gestao=' || v_gestor::text || ').';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_regra_001()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_emp uuid;
        v_exig int; v_atual int; v_deficit int; v_tem_obrig boolean;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Cadastrar empresa com 350 empregados e cota exigida de 11 PcDs';
  r.esperado:='Com deficit, deve existir a obrigacao "Plano de adequacao da cota PCD"';
  INSERT INTO public.empresa_cadastro
    (tenant_id, razao_social, cnpj, total_colaboradores,
     pcd_obrigatoria, pcd_percentual_exigido, pcd_quantidade_exigida, pcd_quantidade_atual)
  VALUES (v_t, '[QA] Empresa Em Deficit PcD', '11555666000181', 350, true, 3, 11, 4)
  RETURNING id INTO v_emp;

  r.passo_ordem:=2; r.passo_acao:='Conferir o deficit';
  SELECT pcd_quantidade_exigida, pcd_quantidade_atual INTO v_exig, v_atual
    FROM public.empresa_cadastro WHERE id=v_emp;
  v_deficit := v_exig - v_atual;

  r.passo_ordem:=3; r.passo_acao:='Verificar se a obrigacao de adequacao da cota foi registrada';
  v_tem_obrig := public.qa_obrigacao_existe(v_emp, 'pcd');

  IF v_tem_obrig THEN
    r.situacao:='passou';
    r.obtido:=format('Deficit de %s PcDs (exige %s, tem %s) e a obrigacao de adequacao esta registrada.',
                     v_deficit, v_exig, v_atual);
  ELSE
    r.situacao:='falhou';
    r.obtido:=format('Empresa em deficit de %s PcDs (exige %s, tem %s) e NAO ha obrigacao de adequacao registrada. A regra existe em OBRIGACOES_TEMPLATES mas so vira registro quando alguem clica em "Gerar Obrigacoes" na aba. Sem o clique, a irregularidade nao entra no painel de conformidade.',
                     v_deficit, v_exig, v_atual);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_regra_002()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_emp uuid; v_tem boolean;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Cadastrar empresa com CIPA obrigatoria e nao constituida';
  r.esperado:='Deve existir a obrigacao "Constituir CIPA" (NR-05)';
  INSERT INTO public.empresa_cadastro
    (tenant_id, razao_social, cnpj, cipa_obrigatoria, cipa_situacao)
  VALUES (v_t, '[QA] Empresa Sem CIPA', '11555666000262', true, 'nao_constituida')
  RETURNING id INTO v_emp;

  r.passo_ordem:=2; r.passo_acao:='Verificar se a obrigacao de constituir CIPA foi registrada';
  v_tem := public.qa_obrigacao_existe(v_emp, 'cipa');

  IF v_tem THEN
    r.situacao:='passou'; r.obtido:='CIPA obrigatoria e nao constituida: obrigacao registrada.';
  ELSE
    r.situacao:='falhou';
    r.obtido:='Empresa obrigada a ter CIPA, situacao nao_constituida, e NAO ha obrigacao registrada. Infracao a NR-05 sem entrada no painel de conformidade — depende do clique em "Gerar Obrigacoes".';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_regra_003()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_emp uuid; v_tem boolean;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Cadastrar empresa com SESMT obrigatorio e inexistente';
  r.esperado:='Deve existir a obrigacao "Contratar/Adequar SESMT", criticidade critica';
  INSERT INTO public.empresa_cadastro
    (tenant_id, razao_social, cnpj, sesmt_obrigatorio, sesmt_situacao)
  VALUES (v_t, '[QA] Empresa Sem SESMT', '11555666000343', true, 'inexistente')
  RETURNING id INTO v_emp;

  r.passo_ordem:=2; r.passo_acao:='Verificar se a obrigacao de contratar SESMT foi registrada';
  v_tem := public.qa_obrigacao_existe(v_emp, 'sesmt');

  IF v_tem THEN
    r.situacao:='passou'; r.obtido:='SESMT obrigatorio e inexistente: obrigacao critica registrada.';
  ELSE
    r.situacao:='falhou';
    r.obtido:='Empresa obrigada a ter SESMT, situacao inexistente, e NAO ha obrigacao registrada. E a obrigacao de maior criticidade entre os templates — a pendencia mais grave do cadastro fica fora do painel.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_regra_004()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_emp uuid;
        v_fap numeric; v_tem boolean;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Cadastrar empresa com FAP 1,8000 (acima do limite de 1,5)';
  r.esperado:='Deve existir a obrigacao "Plano de reducao do FAP"';
  INSERT INTO public.empresa_cadastro (tenant_id, razao_social, cnpj, fap_atual)
  VALUES (v_t, '[QA] Empresa FAP Alto', '11555666000424', 1.8000) RETURNING id INTO v_emp;
  SELECT fap_atual INTO v_fap FROM public.empresa_cadastro WHERE id=v_emp;

  r.passo_ordem:=2; r.passo_acao:='Verificar se a obrigacao de reducao do FAP foi registrada';
  v_tem := public.qa_obrigacao_existe(v_emp, 'fap');

  IF v_tem THEN
    r.situacao:='passou'; r.obtido:=format('FAP %s acima de 1,5: obrigacao de reducao registrada.', v_fap);
  ELSE
    r.situacao:='falhou';
    r.obtido:=format('FAP em %s (acima de 1,5) e NAO ha obrigacao de reducao registrada. A empresa recolhe %s%% a mais de RAT sem plano de reversao.',
                     v_fap, round((v_fap - 1) * 100));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_regra_005()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_emp uuid; v_tem boolean;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Cadastrar empresa que declara possuir TAC';
  r.esperado:='Deve existir a obrigacao "Cumprir obrigacoes do TAC", criticidade critica';
  INSERT INTO public.empresa_cadastro (tenant_id, razao_social, cnpj, tac_possui)
  VALUES (v_t, '[QA] Empresa Com TAC', '11555666000505', true) RETURNING id INTO v_emp;

  r.passo_ordem:=2; r.passo_acao:='Verificar se a obrigacao de cumprir o TAC foi registrada';
  v_tem := public.qa_obrigacao_existe(v_emp, 'tac');

  IF v_tem THEN
    r.situacao:='passou'; r.obtido:='TAC declarado: obrigacao de cumprimento registrada.';
  ELSE
    r.situacao:='falhou';
    r.obtido:='Empresa declarou possuir TAC e NAO ha obrigacao de cumprimento registrada. O TAC e compromisso com o MPT, com multa por clausula descumprida — o maior risco financeiro do painel fica sem acompanhamento.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_regra_006()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_emp uuid;
        v_grau int; v_tem boolean;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Cadastrar empresa com grau de risco 4 (o mais alto da NR-04)';
  r.esperado:='Deve existir a obrigacao "Avaliar impacto do grau de risco elevado"';
  INSERT INTO public.empresa_cadastro (tenant_id, razao_social, cnpj, grau_risco)
  VALUES (v_t, '[QA] Empresa Grau 4', '11555666000686', 4) RETURNING id INTO v_emp;
  SELECT grau_risco INTO v_grau FROM public.empresa_cadastro WHERE id=v_emp;

  r.passo_ordem:=2; r.passo_acao:='Verificar se a obrigacao de avaliacao foi registrada';
  v_tem := public.qa_obrigacao_existe(v_emp, 'grau_risco');

  IF v_tem THEN
    r.situacao:='passou'; r.obtido:=format('Grau de risco %s: obrigacao de avaliacao registrada.', v_grau);
  ELSE
    r.situacao:='falhou';
    r.obtido:=format('Grau de risco %s (elevado) e NAO ha obrigacao de avaliacao registrada. O grau elevado puxa exigencias adicionais que ficam sem acompanhamento.', v_grau);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_regra_010()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_emp uuid; v_tem boolean;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Cadastrar empresa que CUMPRE a cota (350 empregados, 11 exigidos, 11 atuais)';
  r.esperado:='NAO deve haver obrigacao de adequacao — a empresa esta em dia';
  INSERT INTO public.empresa_cadastro
    (tenant_id, razao_social, cnpj, total_colaboradores,
     pcd_obrigatoria, pcd_percentual_exigido, pcd_quantidade_exigida, pcd_quantidade_atual)
  VALUES (v_t, '[QA] Empresa Cota Cumprida', '11555666000767', 350, true, 3, 11, 11)
  RETURNING id INTO v_emp;

  r.passo_ordem:=2; r.passo_acao:='Verificar que NAO ha obrigacao de adequacao';
  v_tem := public.qa_obrigacao_existe(v_emp, 'pcd');

  IF NOT v_tem THEN
    r.situacao:='passou';
    r.obtido:='Empresa em dia (11 exigidos, 11 atuais) e nenhuma obrigacao de adequacao registrada, como deve ser.';
  ELSE
    r.situacao:='falhou';
    r.obtido:='Ha obrigacao de adequacao para empresa SEM deficit. A regra estaria imprecisa, poluindo o painel com pendencia falsa.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_regra_011()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_emp uuid; v_tem boolean;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Cadastrar empresa com CIPA obrigatoria e ATIVA';
  r.esperado:='NAO deve haver obrigacao de constituir CIPA';
  INSERT INTO public.empresa_cadastro
    (tenant_id, razao_social, cnpj, cipa_obrigatoria, cipa_situacao)
  VALUES (v_t, '[QA] Empresa CIPA Ativa', '11555666000848', true, 'ativa') RETURNING id INTO v_emp;

  r.passo_ordem:=2; r.passo_acao:='Verificar que NAO ha obrigacao de constituir';
  v_tem := public.qa_obrigacao_existe(v_emp, 'cipa');

  IF NOT v_tem THEN
    r.situacao:='passou';
    r.obtido:='CIPA ativa e nenhuma obrigacao de constituir registrada, como deve ser.';
  ELSE
    r.situacao:='falhou';
    r.obtido:='Ha obrigacao de constituir CIPA para empresa que ja a tem ativa — pendencia falsa no painel.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_sst_001()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_status text; v_fns text;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Cadastrar PGR com vigência VENCIDA e conferir se o status reage';
  r.esperado := 'Documento vencido acusado (status/alerta) — nunca "vigente" com data no passado';
  INSERT INTO public.sst_documentos (tenant_id, tipo, data_emissao, data_vigencia, status)
  VALUES (v_t, 'PGR', CURRENT_DATE - 800, CURRENT_DATE - 30, 'vigente');
  SELECT s.status INTO v_status FROM public.sst_documentos s
  WHERE s.tenant_id = v_t AND s.tipo = 'PGR' AND s.data_vigencia = CURRENT_DATE - 30
  ORDER BY s.created_at DESC LIMIT 1;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: alguma rotina vigia data_vigencia (alerta de renovação / marcação de vencido)?';
  r.esperado := 'Janela de 60/30 dias avisando a renovação e vencimento acusado automaticamente';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%sst_documentos%'
    AND (p.prosrc ILIKE '%vigencia%' OR p.prosrc ILIKE '%vencid%');

  IF v_status = 'vigente' AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a vigência é decorativa — o PGR entrou com validade 30 dias no '
             || 'PASSADO e ficou "vigente": nenhum gatilho compara data_vigencia com o '
             || 'calendário, nenhuma rotina (pg_cron, como as demais do projeto) marca o '
             || 'vencido nem dispara a janela de renovação de 60/30 dias. O status só muda '
             || 'se alguém lembrar de editar — e o problema que o módulo existe para '
             || 'resolver ("documento vencido descoberto pela fiscalização") continua '
             || 'inteiro. Correção: rotina diária que marca vencido e alerta a renovação, '
             || 'com ação no Plano de Ação; nova versão preserva a anterior como '
             || '"substituido" (o status já prevê).';
  ELSIF v_status IS DISTINCT FROM 'vigente' THEN
    r.situacao := 'passou';
    r.obtido := format('Vencimento reagiu na gravação (status: %s).', coalesce(v_status, 'NULL'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Vigência vigiada por: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_sst_002()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_ia text; v_rev text; v_tab text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): os dados extraídos têm fonte, confiança e estado de revisão?';
  r.esperado := 'Dado extraído aponta o documento-fonte; baixa confiança exige revisão antes de produzir efeito';
  v_ia := public.qa_col_existe('sst_documentos', 'analise_ia');
  v_rev := coalesce(public.qa_col_existe('sst_documentos', '%revis%'),
                    public.qa_col_existe('sst_documentos', '%confianca%'));
  SELECT string_agg(table_name, ', ') INTO v_tab
  FROM information_schema.tables
  WHERE table_schema = 'public'
    AND (table_name ILIKE '%sst%extra%' OR table_name ILIKE '%sst%risco%'
         OR table_name ILIKE '%pgr%risco%');

  IF v_ia IS NOT NULL AND v_rev IS NULL AND v_tab IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO (o cofre existe, o inventário não): sst_documentos guarda o resultado '
             || 'da IA num JSONB solto (analise_ia) — sem nível de confiança, sem estado de '
             || 'revisão (quem validou a extração?) e sem tabela estruturada de dados '
             || 'extraídos (riscos, exames, periodicidades, enquadramentos) ligados ao '
             || 'documento-fonte. Um blob JSON não vira OS, ficha de EPI, agenda de exame '
             || 'nem adicional: os efeitos do RF-009/RF-010 não têm de onde partir, e a '
             || 'exigência de revisão humana (RNF-003 — dado errado vira adicional errado '
             || 'na folha) não tem onde morar. Correção: tabela de extração (dado + tipo + '
             || 'documento_id + confiança + revisor) como camada entre a IA e os efeitos.';
  ELSIF v_ia IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A coluna analise_ia não existe mais em sst_documentos.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Estrutura de extração presente (revisão: %s; tabelas: %s).',
                       coalesce(v_rev, '—'), coalesce(v_tab, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_sst_003()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o plano de ação do PGR vira tarefas no módulo Plano de Ação?';
  r.esperado := 'Medidas do PGR importado criadas como ações rastreáveis, vinculadas ao risco de origem';
  -- o módulo Plano de Ação vive nas tabelas plano_acoes/plano_tarefas —
  -- "acoes" solto casa com "informacoes"/"transacoes"
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%sst_documentos%'
    AND (p.prosrc ILIKE '%plano_acoes%' OR p.prosrc ILIKE '%plano_tarefas%');

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o "documento que vira ação" — a promessa central do módulo (seção '
             || '29) — não existe: nenhuma função converte as medidas do plano de ação do '
             || 'PGR em tarefas do módulo Plano de Ação. O PGR importado é arquivo parado: '
             || 'as medidas que ele propõe (com responsável e prazo, exigência da NR-1) não '
             || 'entram em fila nenhuma, e a fiscalização que pedir evidência de execução '
             || 'do plano recebe silêncio. O módulo Plano de Ação existe e tem família '
             || 'própria no motor — falta a ponte. Correção: na importação interpretada '
             || '(depende do SST-002), criar as ações com vínculo ao risco de origem, sem '
             || 'duplicar em reimportação.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Ponte PGR→Plano de Ação presente: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_sst_010()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_os text; v_risco text; v_ger text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a OS nasce dos riscos da função e cobra ciência?';
  r.esperado := 'OS gerada por função a partir do PGR, com assinatura/ciência rastreada e pendência para os novos';
  v_os := CASE WHEN to_regclass('public.ordens_servico') IS NOT NULL THEN 'ordens_servico' END;
  v_risco := coalesce(public.qa_col_existe('ordens_servico', '%risco%'),
                      public.qa_col_existe('ordens_servico', '%funcao%'),
                      public.qa_col_existe('ordens_servico', '%cargo%'));
  -- geração de verdade escreve na tabela; marcar_os_desatualizadas_apos_pgr
  -- só INVALIDA as OS quando chega PGR novo (meio caminho — bom, mas não gera)
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_ger
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%INSERT INTO%ordens_servico%'
    AND (p.prosrc ILIKE '%risco%' OR p.prosrc ILIKE '%pgr%' OR p.prosrc ILIKE '%sst_documentos%');

  IF v_os IS NOT NULL AND v_ger IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO (metade boa, metade manual): a infraestrutura de OS EXISTE — '
             || 'ordens_servico com links de assinatura (ordem_servico_links, com token e '
             || 'expiração, o mesmo desenho da experiência) — mas a OS é redigida à MÃO: '
             || 'nenhuma função a gera dos riscos da função extraídos do PGR (campos de '
             || 'vínculo: %s). A NR-1 (1.4.1) exige informar riscos e medidas por função; '
             || 'com a OS manual, função nova ou risco novo no PGR não regeram nada, e o '
             || 'colaborador admitido pode começar sem ciência assinada. O meio caminho já '
             || 'existe: marcar_os_desatualizadas_apos_pgr INVALIDA as OS quando chega PGR '
             || 'novo — falta a outra metade, gerar as novas. Correção: geração da OS por '
             || 'função a partir da extração (SST-002), com pendência de ciência para '
             || 'admitidos e mudanças de função.',
             coalesce(v_risco, 'nenhum'));
  ELSIF v_os IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A tabela ordens_servico não existe mais nesta base.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('OS gerada dos riscos por: %s.', v_ger);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_sst_011()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_ca text; v_trava text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a entrega de EPI confere o CA vigente?';
  r.esperado := 'Entrega bloqueada com CA vencido; ficha com assinatura e treinamento evidenciado';
  v_ca := coalesce(public.qa_col_existe('epi_tipos', 'ca_validade'),
                   public.qa_col_existe('epis', '%validade%'));
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_trava
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%epi_entregas%'
    AND (p.prosrc ILIKE '%ca_validade%' OR p.prosrc ILIKE '%validade%');
  IF v_trava IS NULL THEN
    SELECT string_agg(DISTINCT t.tgname, ', ') INTO v_trava
    FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
    WHERE t.tgrelid = 'public.epi_entregas'::regclass AND NOT t.tgisinternal
      AND t.tgname NOT ILIKE '%updated_at%' AND t.tgname NOT ILIKE 'qa\_%'
      AND p.prosrc ILIKE '%validade%';
  END IF;

  IF v_ca IS NOT NULL AND v_trava IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO (o dado existe, a trava não): o CA tem validade cadastrada '
             || '(%s — o subsistema de EPI é dos mais completos: tipos, CETs, entregas, '
             || 'estoque, e o EPI-001 já protege a baixa de estoque), mas NADA confere o CA '
             || 'na hora da ENTREGA: nenhum gatilho ou função compara ca_validade com a '
             || 'data — EPI de CA vencido sai do estoque e vira ficha normalmente. Pela '
             || 'NR-6, entrega com CA vencido equivale juridicamente a não ter entregue: '
             || 'no acidente, a empresa responde como se o colaborador estivesse '
             || 'desprotegido. E a neutralização da insalubridade que o EPI sustenta '
             || '(SST-050) cai junto. Correção: trava de CA vigente na entrega + alerta de '
             || 'CA a vencer com reposição antecipada (janela da seção 14).',
             v_ca);
  ELSIF v_ca IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A validade do CA não existe mais no cadastro de EPI.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('CA conferido na entrega por: %s.', v_trava);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_sst_020()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_param text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): alguém calcula e vigia a próxima data do exame periódico?';
  r.esperado := 'Próximo exame derivado da periodicidade do risco; alertas 30/15/7; vencido acusado';
  v_param := public.qa_col_existe(NULL, 'periodicidade_exame_meses');
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%periodicidade_exame%' OR p.prosrc ILIKE '%proximo_exame%'
         OR (p.prosrc ILIKE '%periodico%' AND p.prosrc ILIKE '%exame%'));

  IF v_param IS NOT NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO (o parâmetro existe, o relógio não): a periodicidade está '
             || 'cadastrada (%s) e NINGUÉM a usa — nenhuma função calcula a próxima data do '
             || 'periódico a partir do último ASO, nenhuma rotina vigia vencimentos com a '
             || 'janela 30/15/7 da seção 14. O contraste incomoda: o exame DEMISSIONAL tem '
             || 'motor dedicado (exame_demissional_pendencias, DESL-060..067), enquanto o '
             || 'PERIÓDICO — que acontece dezenas de vezes mais — depende de planilha '
             || 'externa. ASO vencido de quem segue trabalhando é a autuação mais fácil da '
             || 'fiscalização. Correção: próxima data derivada de último ASO + '
             || 'periodicidade do risco, com rotina de alertas e painel de vencidos.',
             v_param);
  ELSIF v_param IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'O parâmetro periodicidade_exame_meses não existe mais.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Agenda do periódico viva: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_sst_021()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): mudança de função/risco exige ASO antes de efetivar?';
  r.esperado := 'Troca para função de risco diferente retida até o ASO de mudança; OS/ficha regeradas';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%mudanca%risco%' OR p.prosrc ILIKE '%mudanca%funcao%'
         OR (p.prosrc ILIKE '%exame%' AND p.prosrc ILIKE '%cargo%'));

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o ASO de mudança de risco não existe — dos cinco eventos de exame '
             || 'da NR-7, quatro têm dono (admissional ADM-060.., periódico SST-020, '
             || 'retorno AFAST-070, demissional DESL-060..) e a MUDANÇA é o único sem '
             || 'nenhuma estrutura: trocar um colaborador de função administrativa para '
             || 'função exposta não exige exame, não regera OS nem ficha de EPI e não '
             || 'revisa o adicional. A transferência silenciosa deixa a pessoa num risco '
             || 'que nenhum médico avaliou — e o exame DEPOIS da mudança não conserta: a '
             || 'NR-7 o exige ANTES. Correção: troca de cargo/função com risco diferente '
             || 'retida até ASO de mudança apto, disparando a regeração da OS/ficha '
             || '(SST-010/011) e a revisão do adicional (SST-050).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Mudança de risco tratada por: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_sst_030()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_tela text; v_prazo text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o S-2220 tem relógio — ASO registrado projeta o dia 15?';
  r.esperado := 'Data-limite (dia 15 do mês seguinte ao ASO) projetada, vigiada e atraso acusado';
  SELECT string_agg(DISTINCT tipo_evento, ', ') INTO v_tela
  FROM (SELECT DISTINCT tipo_evento FROM public.esocial_transmissoes
        WHERE tipo_evento ILIKE '%2220%' LIMIT 3) s;
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_prazo
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%2220%' AND p.prosrc ILIKE '%prazo%');

  IF v_prazo IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o S-2220 não tem relógio — a fila de transmissão aceita o evento '
             || 'quando a TELA o monta, mas nenhuma função projeta a data-limite (dia 15 '
             || 'do mês seguinte à emissão do ASO), nenhum alerta corre até lá e a '
             || 'transmissão tardia entra como regular. Cada ASO emitido e não transmitido '
             || 'é multa acumulando por competência em silêncio — e como o ASO vive em '
             || 'campos da admissão e em eventos de saúde, sem gatilho ninguém nem sabe '
             || 'QUAIS ASOs ainda devem evento. Correção: registro do ASO dispara a '
             || 'preparação do S-2220 com data-limite; pendências e atrasos visíveis '
             || '(mesmo desenho pedido para o S-2230 no AFAST-060 e o S-1299 no '
             || 'FOLHA-060 — um motor de prazos do eSocial serve aos três).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Prazo do S-2220 controlado por: %s (eventos na fila: %s).',
                       v_prazo, coalesce(v_tela, 'nenhum'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_sst_031()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_hist text; v_ger text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a exposição a agentes tem histórico e gera S-2240?';
  r.esperado := 'Exposição por colaborador (agente, período, EPI) registrada; S-2240 na admissão e a cada alteração';
  SELECT string_agg(table_name, ', ') INTO v_hist
  FROM information_schema.tables
  WHERE table_schema = 'public'
    AND (table_name ILIKE '%exposicao%' OR table_name ILIKE '%agente%nocivo%'
         OR table_name ILIKE '%ltcat%');
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_ger
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%2240%';

  IF v_hist IS NULL AND v_ger IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a exposição a agentes nocivos não tem registro estruturado — o '
             || 'LTCAT entra em sst_documentos como arquivo, mas nenhuma tabela guarda '
             || 'QUEM está exposto a QUAL agente desde QUANDO (com o EPI que atenua), e '
             || 'nenhuma função gera o S-2240 na admissão ou na mudança de exposição. O '
             || 'S-2240 é a matéria-prima do PPP eletrônico: cada mês sem o registro é um '
             || 'mês de aposentadoria especial que ninguém vai conseguir reconstituir '
             || 'quando o INSS pedir — o furo só aparece anos depois, sem conserto. '
             || 'Correção: histórico de exposição por colaborador (extraído do LTCAT — '
             || 'depende do SST-002) + geração do S-2240 com prazo dia 15, alimentando o '
             || 'PPP (SST-060).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Exposição estruturada (tabelas: %s; geração: %s).',
                       coalesce(v_hist, '—'), coalesce(v_ger, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_sst_040()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_tab text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a CIPA existe no sistema?';
  r.esperado := 'Dimensionamento pelo Quadro I, mandato controlado e atas arquivadas';
  -- palavra inteira: "parti[cipa]coes" contém "cipa" e engana o LIKE
  SELECT string_agg(table_name, ', ') INTO v_tab
  FROM information_schema.tables
  WHERE table_schema = 'public' AND table_name ~* '(^|_)cipa(_|$)';

  DECLARE v_dim text; v_atas text;
  BEGIN
    SELECT string_agg(DISTINCT p.proname, ', ') INTO v_dim
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
      AND p.prosrc ILIKE '%cipa%'
      AND (p.prosrc ILIKE '%dimension%' OR p.prosrc ILIKE '%quadro%');
    SELECT string_agg(table_name, ', ') INTO v_atas
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name ~* '(^|_)cipa(_|$)' AND table_name ILIKE '%ata%';

    IF v_tab IS NOT NULL AND (v_dim IS NULL OR v_atas IS NULL) THEN
      r.situacao := 'falhou';
      r.obtido := format('ACHADO (a comissão existe, a régua e a prova não): cipa_composicao '
               || 'está de pé com representação, condição e MANDATO (início/fim) — a '
               || 'estrutura viva que o DESL-073 usa para a estabilidade do cipeiro — mas '
               || 'faltam as outras duas pernas da NR-5: o DIMENSIONAMENTO pelo Quadro I '
               || '(%s — efetivo × grupo do CNAE decide quantos titulares/suplentes, ou o '
               || 'designado; o efetivo e o CNAE o cadastro já tem) e as ATAS mensais '
               || 'arquivadas (%s), que são a prova de que a comissão funciona. Sem a '
               || 'régua, ninguém sabe se a composição cadastrada é a exigida; sem as '
               || 'atas, a CIPA existe só no cadastro. Correção: cálculo do Quadro I por '
               || 'estabelecimento + registro de reuniões/atas em Documentos + alerta de '
               || 'fim de mandato (eleição com 60 dias).',
               coalesce('há: ' || v_dim, 'nenhuma função'),
               coalesce('há: ' || v_atas, 'nenhuma tabela'));
    ELSIF v_tab IS NULL THEN
      r.situacao := 'falhou';
      r.obtido := 'A estrutura de CIPA não existe nesta base.';
    ELSE
      r.situacao := 'passou';
      r.obtido := format('CIPA completa (composição: %s; dimensionamento: %s; atas: %s).',
                         v_tab, v_dim, v_atas);
    END IF;
  END;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_sst_041()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_tab text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): existe canal formal de denúncias com sigilo?';
  r.esperado := 'Denúncia anônima com protocolo, acesso restrito ao fluxo de apuração e prazo vigiado';
  -- a ouvidoria é o canal real; marketplace_denuncias é reclamação de loja
  SELECT string_agg(table_name, ', ') INTO v_tab
  FROM information_schema.tables
  WHERE table_schema = 'public'
    AND (table_name ILIKE 'ouvidoria%' OR table_name ILIKE '%assedio%');

  IF v_tab IS NOT NULL THEN
    DECLARE v_anon text; v_restr int; v_prazo text;
    BEGIN
      v_anon := public.qa_col_existe('ouvidoria', 'anonimo');
      SELECT count(*) INTO v_restr FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'ouvidoria'
        AND policyname ILIKE 'perfil_restringe%';
      v_prazo := coalesce(public.qa_col_existe('ouvidoria', '%prazo%'),
                          public.qa_col_existe('ouvidoria', '%data_limite%'));
      IF v_anon IS NOT NULL AND (v_restr = 0 OR v_prazo IS NULL) THEN
        r.situacao := 'falhou';
        r.obtido := format('ACHADO (o canal existe, o sigilo e o prazo mancam): a ouvidoria '
                 || 'está de pé (%s) e aceita denúncia ANÔNIMA (coluna anonimo — o requisito '
                 || 'central da Lei 14.457 atendido), mas: (1) a tabela está FORA da camada '
                 || 'perfil_restringe_leitura_* (%s políticas) — quem tem acesso ao módulo lê '
                 || 'as denúncias, inclusive potencialmente o gestor da área denunciada, e '
                 || 'para canal de assédio o sigilo precisa ser mais duro que o do CID; e '
                 || '(2) não há prazo de apuração vigiado (%s) — a lei pede tratativa, não '
                 || 'caixa de entrada. Correção: política restritiva própria (fluxo de '
                 || 'apuração, não módulo) + log de tentativas de acesso + prazo de '
                 || 'tratativa com alerta.',
                 v_tab, v_restr, coalesce(v_prazo, 'nenhum campo'));
      ELSE
        r.situacao := 'passou';
        r.obtido := format('Canal com anonimato, restrição e prazo (%s).', v_tab);
      END IF;
    END;
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o canal de denúncias da Lei 14.457/2022 não existe — nenhuma '
             || 'tabela de ouvidoria ou assédio. A família PSICO cobre o outro braço da '
             || 'lei (avaliação de riscos psicossociais), mas o CANAL formal — denúncia '
             || 'anônima com protocolo, apuração com prazo e sigilo — não tem onde '
             || 'existir. Correção: registro anônimo com protocolo + fluxo de apuração '
             || 'restrito + log de tentativas de acesso + prazo de tratativa vigiado.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_sst_050()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o enquadramento do laudo alimenta o adicional — e o EPI o neutraliza?';
  r.esperado := 'Laudo→função→adicional com fonte rastreável; neutralização viva (CA vencido religa)';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%insalubr%' OR p.prosrc ILIKE '%periculos%' OR p.prosrc ILIKE '%neutraliza%')
    AND (p.prosrc ILIKE '%laudo%' OR p.prosrc ILIKE '%sst_documentos%' OR p.prosrc ILIKE '%cargo%');

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o laudo e o adicional vivem em mundos separados — nenhuma função '
             || 'liga o enquadramento (que deveria sair do laudo importado) à função/'
             || 'colaborador que a Folha usa para calcular os 10/20/40% ou os 30% '
             || '(o motor de cálculo existe no React — adicionais.ts, FOLHA-021 — mas a '
             || 'ORIGEM do enquadramento é digitação). E a via de volta tampouco existe: '
             || 'EPI eficaz pode NEUTRALIZAR a insalubridade e cessar o adicional (CLT '
             || 'art. 191, [VAL]), com o vínculo vivo — CA vencido religa o adicional '
             || '(SST-011). Sem as duas pontes, ou se paga adicional que o EPI eliminou, '
             || 'ou se corta adicional sem laudo que sustente. Correção: enquadramento por '
             || 'função com laudo-fonte (depende do SST-002) + estado de neutralização '
             || 'amarrado à entrega e ao CA do EPI.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Ponte laudo→adicional presente: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_sst_060()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_est text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o PPP tem estrutura para ser gerado?';
  r.esperado := 'PPP montado do histórico de exposição (LTCAT/S-2240), entregue no desligamento e sob demanda';
  v_est := coalesce((SELECT string_agg(table_name, ', ')
                     FROM information_schema.tables
                     WHERE table_schema = 'public' AND table_name ILIKE '%ppp%'),
                    public.qa_fns_com('%ppp%'));

  IF v_est IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o PPP não existe no sistema — nenhuma tabela ou função. O Perfil '
             || 'Profissiográfico é a biografia previdenciária da exposição: obrigatório '
             || 'na rescisão de quem trabalhou exposto e a base da aposentadoria especial '
             || '(Lei 8.213, arts. 57-58), hoje gerado eletronicamente a partir dos '
             || 'S-2240. A cadeia inteira está pendente: sem histórico de exposição '
             || '(SST-031) não há S-2240, e sem S-2240 não há PPP — e esse é o tipo de '
             || 'dívida que não se paga depois: exposição não registrada em 2026 é '
             || 'benefício negado em 2046. Correção: na ordem, SST-002 (extração) → '
             || 'SST-031 (exposição/S-2240) → geração do PPP no desligamento e sob '
             || 'demanda, anexado ao dossiê da rescisão (DESL-082).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Estrutura de PPP presente: %s.', v_est);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_sst_070()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): alguém cruza PGR × PCMSO × LTCAT × S-2240?';
  r.esperado := 'Conferência de coerência apontando risco sem exame, agente sem inventário, exposição sem laudo';
  -- exige cruzamento de RISCOS — "PGR + PCMSO" soltos casam com a função que
  -- cria a árvore de pastas padrão (os nomes das pastas contêm as siglas)
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.proname NOT ILIKE '%pasta%'
    AND (p.prosrc ILIKE '%coerencia%'
         OR (p.prosrc ILIKE '%pgr%' AND p.prosrc ILIKE '%pcmso%' AND p.prosrc ILIKE '%risco%'));

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: os documentos não conversam — nenhuma função cruza o que o PGR '
             || 'inventariou com o que o PCMSO examina, o que o LTCAT mediu e o que o '
             || 'S-2240 declara. A NR-7 exige o PCMSO BASEADO no PGR; divergência entre '
             || 'eles (risco inventariado sem exame previsto, agente medido que o '
             || 'inventário não conhece) é a primeira coisa que a fiscalização procura, '
             || 'porque derruba a credibilidade do conjunto — e hoje cada documento é um '
             || 'PDF isolado em sst_documentos, sem base comum de riscos para comparar. '
             || 'Depende da extração estruturada (SST-002). [BPR] com fundamento nas NRs. '
             || 'Correção: conferência de coerência sobre a base extraída, com relatório '
             || 'de divergências arquivado como evidência.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Coerência conferida por: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_sst_080()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_ev int; v_at int; v_log text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o dado clínico está restrito e o acesso é logado?';
  r.esperado := 'Tabelas clínicas na camada de perfil; aptidão circula sem diagnóstico; log próprio de acesso';
  SELECT count(*) INTO v_ev FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'eventos_saude'
    AND policyname ILIKE 'perfil_restringe%';
  SELECT count(*) INTO v_at FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'atestados'
    AND policyname ILIKE 'perfil_restringe%';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_log
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%eventos_saude%' OR p.prosrc ILIKE '%cid_principal%')
    AND (p.prosrc ILIKE '%log%' OR p.prosrc ILIKE '%acesso%' OR p.prosrc ILIKE '%audit%');

  IF v_ev > 0 AND v_at > 0 AND v_log IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO (mesma tranca sem caderno do AFAST-080, agora no acervo '
             || 'clínico inteiro): eventos_saude (%s política(s)) e atestados (%s) estão '
             || 'na camada de perfil — a restrição de leitura existe e funciona — mas '
             || 'NENHUMA função registra o ACESSO ao dado clínico: quem abriu o exame de '
             || 'quem, quando. O documento pede log específico (seção 22) e o "cofre '
             || 'clínico" (seção 29) é isso: leitura por função que anota o leitor. A '
             || 'separação aptidão × diagnóstico até se sustenta hoje (o apto/inapto vive '
             || 'em campos administrativos da admissão, fora das tabelas clínicas), mas '
             || 'numa investigação de vazamento não há trilha para consultar. Correção: '
             || 'acesso ao clínico via função SECURITY DEFINER com registro append-only '
             || '(leitor, titular, registro, hora) — uma vez, servindo CID (AFAST-080) e '
             || 'exames.',
             v_ev, v_at);
  ELSIF v_ev = 0 OR v_at = 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO GRAVE: tabela clínica fora da camada de perfil '
             || '(eventos_saude: %s; atestados: %s políticas).', v_ev, v_at);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Restrição e log presentes (log: %s).', v_log);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
  ('AFAST-001','qa_caso_afast_001', true),
  ('AFAST-002','qa_caso_afast_002', true),
  ('AFAST-003','qa_caso_afast_003', true),
  ('AFAST-010','qa_caso_afast_010', true),
  ('AFAST-011','qa_caso_afast_011', true),
  ('AFAST-020','qa_caso_afast_020', true),
  ('AFAST-021','qa_caso_afast_021', true),
  ('AFAST-022','qa_caso_afast_022', true),
  ('AFAST-030','qa_caso_afast_030', true),
  ('AFAST-031','qa_caso_afast_031', true),
  ('AFAST-032','qa_caso_afast_032', true),
  ('AFAST-040','qa_caso_afast_040', true),
  ('AFAST-050','qa_caso_afast_050', true),
  ('AFAST-051','qa_caso_afast_051', true),
  ('AFAST-060','qa_caso_afast_060', true),
  ('AFAST-070','qa_caso_afast_070', true),
  ('AFAST-080','qa_caso_afast_080', true),
  ('BEN-001','qa_caso_ben_001', true),
  ('BEN-010','qa_caso_ben_010', true),
  ('BEN-011','qa_caso_ben_011', true),
  ('BEN-012','qa_caso_ben_012', true),
  ('BEN-020','qa_caso_ben_020', true),
  ('BEN-030','qa_caso_ben_030', true),
  ('BEN-040','qa_caso_ben_040', true),
  ('BEN-042','qa_caso_ben_042', true),
  ('BEN-050','qa_caso_ben_050', true),
  ('BEN-051','qa_caso_ben_051', true),
  ('BEN-060','qa_caso_ben_060', true),
  ('BEN-070','qa_caso_ben_070', true),
  ('BEN-071','qa_caso_ben_071', true),
  ('BEN-080','qa_caso_ben_080', true),
  ('COLAB-002','qa_caso_colab_002', true),
  ('COLAB-030','qa_caso_colab_030', true),
  ('COLAB-031','qa_caso_colab_031', true),
  ('COLAB-032','qa_caso_colab_032', true),
  ('DADO-010','qa_caso_dado_010', true),
  ('DESL-013','qa_caso_desl_013', true),
  ('DESL-015','qa_caso_desl_015', true),
  ('DESL-025','qa_caso_desl_025', true),
  ('DESL-057','qa_caso_desl_057', true),
  ('DESL-074','qa_caso_desl_074', true),
  ('DESL-081','qa_caso_desl_081', true),
  ('DESL-083','qa_caso_desl_083', true),
  ('DESL-093','qa_caso_desl_093', true),
  ('DESL-094','qa_caso_desl_094', true),
  ('DESL-105','qa_caso_desl_105', true),
  ('DESL-106','qa_caso_desl_106', true),
  ('DESL-110','qa_caso_desl_110', true),
  ('EMP-051','qa_caso_emp_051', true),
  ('EMP-052','qa_caso_emp_052', true),
  ('EMP-053','qa_caso_emp_053', true),
  ('EMP-054','qa_caso_emp_054', true),
  ('ENQ-001','qa_caso_enq_001', true),
  ('ENQ-010','qa_caso_enq_010', true),
  ('ENQ-011','qa_caso_enq_011', true),
  ('ENQ-012','qa_caso_enq_012', true),
  ('ENQ-013','qa_caso_enq_013', true),
  ('ENQ-014','qa_caso_enq_014', true),
  ('ENQ-050','qa_caso_enq_050', true),
  ('ENQ-051','qa_caso_enq_051', true),
  ('EPI-010','qa_caso_epi_010', true),
  ('EPI-011','qa_caso_epi_011', true),
  ('EPI-020','qa_caso_epi_020', true),
  ('EPI-021','qa_caso_epi_021', true),
  ('EPI-022','qa_caso_epi_022', true),
  ('EPI-030','qa_caso_epi_030', true),
  ('EPI-040','qa_caso_epi_040', true),
  ('EPI-041','qa_caso_epi_041', true),
  ('EPI-042','qa_caso_epi_042', true),
  ('EPI-043','qa_caso_epi_043', true),
  ('EPI-044','qa_caso_epi_044', true),
  ('EPI-050','qa_caso_epi_050', true),
  ('EPI-051','qa_caso_epi_051', true),
  ('EPI-052','qa_caso_epi_052', true),
  ('ESC-001','qa_caso_esc_001', true),
  ('ESC-010','qa_caso_esc_010', true),
  ('ESC-011','qa_caso_esc_011', true),
  ('ESC-012','qa_caso_esc_012', true),
  ('ESC-020','qa_caso_esc_020', true),
  ('ESC-021','qa_caso_esc_021', true),
  ('ESC-031','qa_caso_esc_031', true),
  ('FOLHA-001','qa_caso_folha_001', true),
  ('FOLHA-002','qa_caso_folha_002', true),
  ('FOLHA-030','qa_caso_folha_030', true),
  ('FOLHA-040','qa_caso_folha_040', true),
  ('FOLHA-050','qa_caso_folha_050', true),
  ('FOLHA-051','qa_caso_folha_051', true),
  ('FOLHA-060','qa_caso_folha_060', true),
  ('FOLHA-061','qa_caso_folha_061', true),
  ('FOLHA-070','qa_caso_folha_070', true),
  ('FOLHA-071','qa_caso_folha_071', true),
  ('FOLHA-080','qa_caso_folha_080', true),
  ('FOLHA-081','qa_caso_folha_081', true),
  ('FOLHA-090','qa_caso_folha_090', true),
  ('HCAL-001','qa_caso_hcal_001', true),
  ('HCAL-010','qa_caso_hcal_010', true),
  ('HCAL-011','qa_caso_hcal_011', true),
  ('HCAT-001','qa_caso_hcat_001', true),
  ('HCAT-010','qa_caso_hcat_010', true),
  ('HIER-001','qa_caso_hier_001', true),
  ('HIER-002','qa_caso_hier_002', true),
  ('HTPL-001','qa_caso_htpl_001', true),
  ('HTPL-010','qa_caso_htpl_010', true),
  ('JOR-001','qa_caso_jor_001', true),
  ('JOR-002','qa_caso_jor_002', true),
  ('JOR-010','qa_caso_jor_010', true),
  ('OUV-003','qa_caso_ouv_003', true),
  ('OUV-004','qa_caso_ouv_004', true),
  ('OUV-005','qa_caso_ouv_005', true),
  ('OUV-010','qa_caso_ouv_010', true),
  ('OUV-023','qa_caso_ouv_023', true),
  ('OUV-024','qa_caso_ouv_024', true),
  ('OUV-031','qa_caso_ouv_031', true),
  ('OUV-033','qa_caso_ouv_033', true),
  ('OUV-034','qa_caso_ouv_034', true),
  ('REGRA-001','qa_caso_regra_001', true),
  ('REGRA-002','qa_caso_regra_002', true),
  ('REGRA-003','qa_caso_regra_003', true),
  ('REGRA-004','qa_caso_regra_004', true),
  ('REGRA-005','qa_caso_regra_005', true),
  ('REGRA-006','qa_caso_regra_006', true),
  ('REGRA-010','qa_caso_regra_010', true),
  ('REGRA-011','qa_caso_regra_011', true),
  ('SST-001','qa_caso_sst_001', true),
  ('SST-002','qa_caso_sst_002', true),
  ('SST-003','qa_caso_sst_003', true),
  ('SST-010','qa_caso_sst_010', true),
  ('SST-011','qa_caso_sst_011', true),
  ('SST-020','qa_caso_sst_020', true),
  ('SST-021','qa_caso_sst_021', true),
  ('SST-030','qa_caso_sst_030', true),
  ('SST-031','qa_caso_sst_031', true),
  ('SST-040','qa_caso_sst_040', true),
  ('SST-041','qa_caso_sst_041', true),
  ('SST-050','qa_caso_sst_050', true),
  ('SST-060','qa_caso_sst_060', true),
  ('SST-070','qa_caso_sst_070', true),
  ('SST-080','qa_caso_sst_080', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- Conferencia LEVE (so conta; NAO executa a bateria — evita timeout/rollback) -
SELECT split_part(i.codigo,'-',1) AS familia,
       count(*) AS rotinas_esperadas,
       count(*) FILTER (WHERE p.oid IS NOT NULL) AS funcoes_presentes
FROM public.qa_implementacoes i
LEFT JOIN pg_proc p ON p.proname = i.funcao_sql AND p.pronamespace = 'public'::regnamespace
WHERE i.ativo AND split_part(i.codigo,'-',1) IN
  ('AFAST','BEN','COLAB','DADO','DESL','EMP','ENQ','EPI','ESC','FOLHA','HCAL','HCAT','HIER','HTPL','JOR','OUV','REGRA','SST')
GROUP BY 1 ORDER BY familia;
