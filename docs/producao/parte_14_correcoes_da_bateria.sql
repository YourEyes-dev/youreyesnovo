-- ============================================================================
-- PRODUCAO — PONTO, PARTE 14 de 16
--
-- ANTES DE COLAR ESTA PARTE
--   * o RETRATO (passo_00_retrato_antes.sql) ja tem de ter sido tirado;
--   * as partes anteriores ja tem de ter sido aplicadas, nesta ordem, cada uma
--     com a conferencia terminando em OK.
--
-- ONDE COLAR
-- No SQL Editor do projeto de PRODUCAO. Execute o arquivo INTEIRO, uma vez.
-- Pode rodar de novo sem risco: e idempotente.
--
-- CONTEUDO
-- Identico ao que foi aplicado e conferido na homologacao, onde a bateria do
-- Ponto fechou em 133 passou / 1 falhou / 0 erro.
--
-- AO FINAL
-- Sai UMA conferencia com duas partes: as pecas que chegaram e o VOLUME —
-- quantas linhas das tabelas vivas do Ponto mudaram de quantidade. Nesta parte o esperado e ZERO.
-- ============================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- MEDICAO DE VOLUME (inicio) — a contagem de agora fica guardada para a
-- conferencia do fim comparar. Tabela propria, que nenhum sistema le.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ponto_entrega_volume (
  parte          integer NOT NULL,
  tabela         text    NOT NULL,
  linhas_antes   bigint  NOT NULL,
  linhas_depois  bigint,
  marca_antes    text,
  marca_depois   text,
  medido_em      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (parte, tabela)
);

-- Para a tabela criada por uma versao anterior desta fila continuar servindo.
ALTER TABLE public.ponto_entrega_volume ADD COLUMN IF NOT EXISTS marca_antes  text;
ALTER TABLE public.ponto_entrega_volume ADD COLUMN IF NOT EXISTS marca_depois text;

-- Tabela nova em public fica exposta pela API do Supabase. Esta nao tem dado
-- pessoal, mas tambem nao e da conta de ninguem: RLS ligada e sem politica.
ALTER TABLE public.ponto_entrega_volume ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ponto_entrega_volume FROM PUBLIC;

DO $fechadura$
BEGIN
  EXECUTE 'REVOKE ALL ON public.ponto_entrega_volume FROM anon, authenticated';
EXCEPTION WHEN undefined_object THEN
  RAISE NOTICE 'Papeis anon/authenticated nao existem nesta base.';
END $fechadura$;

DO $volume$
DECLARE
  t text;
  n bigint;
  m text;
BEGIN
  DELETE FROM public.ponto_entrega_volume WHERE parte = 14;
  FOREACH t IN ARRAY ARRAY['ponto_diario', 'ponto_marcacoes', 'ponto_espelhos', 'ponto_banco_horas', 'ponto_alertas', 'ponto_links', 'ponto_fechamentos', 'atestados']
  LOOP
    CONTINUE WHEN to_regclass('public.' || t) IS NULL;
    EXECUTE format('SELECT count(*) FROM public.%I', t) INTO n;
    m := NULL;
    -- A marca e a data da ultima alteracao registrada na tabela. Contagem
    -- pega linha criada ou apagada; a marca pega linha ALTERADA.
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name=t AND column_name='updated_at') THEN
      EXECUTE format('SELECT max(updated_at)::text FROM public.%I', t) INTO m;
    END IF;
    INSERT INTO public.ponto_entrega_volume (parte, tabela, linhas_antes, marca_antes)
    VALUES (14, t, n, m);
  END LOOP;
END $volume$;

-- ############################################################
-- BLOCO: script_ponto_correcoes_402_430_431.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — PONTO 402/430/431: as tres primeiras lacunas reais da bateria
--
-- ONDE COLAR: SQL Editor da HOMOLOGACAO (e da PRODUCAO, quando aprovado).
--
-- POR QUE ESTAS TRES
-- Cruzando a bateria da homologacao com a do projeto, 84 das 91 falhas ja
-- tem correcao pronta (sao distancia de entrega). Sobraram 7 lacunas de
-- verdade, que falham nos DOIS ambientes. Estas sao as tres primeiras:
-- baratas de corrigir e de risco alto.
--
--   402  Feriado nao trabalhado virava FALTA — descontava salario e
--        derrubava o DSR de quem nao devia nada (Lei 605/1949, art. 1).
--   430  Ajuste de ponto aceitava motivo VAZIO — marcacao alterada sem
--        justificativa e indicio de manipulacao na fiscalizacao.
--   431  Dossie de fiscalizacao DUPLICAVA por competencia — a empresa
--        apresenta um e o auditor encontra o outro.
--
-- O QUE MUDA DE COMPORTAMENTO (leia antes de aplicar)
--   - Dias de FERIADO sem marcacao passam a ser gravados como dia neutro
--     na proxima consolidacao/reapuracao. Dias ja fechados nao sao
--     reescritos por este arquivo: a correcao vale daqui em diante.
--   - Ajustes novos exigem motivo com ao menos 3 caracteres. Historico
--     antigo e preservado (a regra entra como NOT VALID).
--   - Dossies duplicados da mesma competencia sao consolidados no mais
--     recente. O que sair e copiado antes para backup_dossies_duplicados_
--     <aaaammdd>, e a producao nao tem PITR — por isso a copia.
--
-- GARANTIAS
--   - Idempotente: rodar duas vezes nao duplica nem quebra.
--   - Guarda o que remove antes de remover.
--   - Nenhuma escrita nova depende do formato do indice da apuracao
--     diaria (chave com ou sem empresa) — funciona em ambiente antigo.
--   - As sondas 402 e 431 acompanham a correcao e passam a medir
--     comportamento, nao detalhe de implementacao.
-- Roda inteiro em UMA transacao.
-- ============================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- (402) Feriado sem marcação é dia neutro
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_grava_feriado_neutro(
  p_tenant_id uuid, p_empresa_id uuid, p_colaborador_id uuid,
  p_colaborador_nome text, p_colaborador_cpf text, p_data date, p_nome_feriado text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_id uuid;
BEGIN
  -- Atualiza-ou-insere sem ON CONFLICT: funciona com a chave do dia nova
  -- (com empresa) e com a antiga (sem), sem depender da forma do indice.
  SELECT d.id INTO v_id
  FROM public.ponto_diario d
  WHERE d.tenant_id = p_tenant_id
    AND d.colaborador_cpf = p_colaborador_cpf
    AND d.data = p_data
    AND (d.empresa_id IS NOT DISTINCT FROM p_empresa_id OR d.empresa_id IS NULL)
  ORDER BY d.empresa_id NULLS LAST
  LIMIT 1;

  IF v_id IS NOT NULL THEN
    UPDATE public.ponto_diario
       SET empresa_id        = COALESCE(empresa_id, p_empresa_id),
           tipo_dia          = 'feriado',
           feriado_nome      = p_nome_feriado,
           status            = 'justificado',
           horas_trabalhadas = make_interval(mins => 0),
           horas_faltantes   = make_interval(mins => 0),
           atraso_minutos    = 0,
           observacao        = 'Feriado: ' || p_nome_feriado,
           updated_at        = now()
     WHERE id = v_id;
  ELSE
    INSERT INTO public.ponto_diario
      (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, data,
       entrada, saida_almoco, retorno_almoco, saida,
       horas_trabalhadas, horas_faltantes, status, tipo_dia, feriado_nome, observacao)
    VALUES
      (p_tenant_id, p_empresa_id, p_colaborador_id, p_colaborador_nome, p_colaborador_cpf, p_data,
       NULL, NULL, NULL, NULL,
       make_interval(mins => 0), make_interval(mins => 0), 'justificado',
       'feriado', p_nome_feriado, 'Feriado: ' || p_nome_feriado);
  END IF;
END $function$;

COMMENT ON FUNCTION public.ponto_grava_feriado_neutro(uuid, uuid, uuid, text, text, date, text) IS
  'Grava o dia de feriado NAO TRABALHADO como dia neutro: sem falta, sem debito de jornada, com o nome do feriado. Lei 605/1949, art. 1. PONTO-402.';

-- A consolidação passa a consultar o feriado antes de calcular o dia.
DO $consolida$
DECLARE v_src text; v_novo text; v_marca text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'consolidar_ponto_diario_manual';

  IF v_src IS NULL THEN
    RAISE NOTICE 'consolidar_ponto_diario_manual nao existe nesta base — (402) pulado.';
    RETURN;
  END IF;

  IF v_src ILIKE '%ponto_grava_feriado_neutro%' THEN
    RAISE NOTICE '(402) ja aplicado — nada a fazer.';
    RETURN;
  END IF;

  -- Ponto de insercao: logo depois de resolver a empresa do colaborador e
  -- antes de calcular o dia. A ancora existe em todas as versoes.
  v_marca := 'c := public._ponto_calc_dia(';
  IF position(v_marca IN v_src) = 0 THEN
    RAISE NOTICE '(402) NAO aplicado: a ancora do calculo do dia mudou nesta base. Revisar a mao.';
    RETURN;
  END IF;

  v_novo := replace(v_src, v_marca,
    '-- Feriado sem marcacao e dia neutro, nunca falta (Lei 605/1949, art. 1).'
 || '  -- Feriado TRABALHADO segue pelo calculo: e la que a dobra e a folga'  || chr(10)
 || '  -- compensatoria sao decididas (PONTO-320/321).'                       || chr(10)
 || '  IF NOT EXISTS (SELECT 1 FROM public.ponto_marcacoes m'                 || chr(10)
 || '                  WHERE m.tenant_id = p_tenant_id'                       || chr(10)
 || '                    AND m.colaborador_cpf = p_colaborador_cpf'           || chr(10)
 || '                    AND m.data_marcacao = p_data) THEN'                  || chr(10)
 || '    DECLARE v_feriado text;'                                             || chr(10)
 || '    BEGIN'                                                               || chr(10)
 || '      v_feriado := public.feriado_do_dia(p_tenant_id, v_cid, p_data);'   || chr(10)
 || '      IF v_feriado IS NOT NULL THEN'                                     || chr(10)
 || '        PERFORM public.ponto_grava_feriado_neutro(p_tenant_id, v_eid, v_cid,' || chr(10)
 || '                  v_cnome, p_colaborador_cpf, p_data, v_feriado);'       || chr(10)
 || '        RETURN;'                                                         || chr(10)
 || '      END IF;'                                                           || chr(10)
 || '    EXCEPTION WHEN OTHERS THEN'                                          || chr(10)
 || '      NULL;  -- cadastro de feriados indisponivel nao pode travar o dia' || chr(10)
 || '    END;'                                                                || chr(10)
 || '  END IF;'                                                               || chr(10) || chr(10)
 || '  ' || v_marca);

  EXECUTE v_novo;
  RAISE NOTICE '(402) consolidacao passa a tratar feriado sem marcacao como dia neutro.';
END $consolida$;

-- ---------------------------------------------------------------------
-- (430) Ajuste exige motivo com conteúdo
-- ---------------------------------------------------------------------
DO $motivo$
DECLARE v_legado int;
BEGIN
  IF to_regclass('public.ponto_ajustes') IS NULL THEN
    RAISE NOTICE '(430) pulado: ponto_ajustes nao existe nesta base.';
    RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_constraint
              WHERE conrelid = 'public.ponto_ajustes'::regclass
                AND conname = 'ponto_ajustes_motivo_com_conteudo') THEN
    RAISE NOTICE '(430) ja aplicado — nada a fazer.';
    RETURN;
  END IF;

  SELECT count(*) INTO v_legado FROM public.ponto_ajustes
  WHERE length(btrim(coalesce(motivo, ''))) < 3;

  -- NOT VALID de proposito: vale para tudo que entrar daqui em diante e
  -- nao reprova historico antigo, que ninguem pode mais corrigir.
  ALTER TABLE public.ponto_ajustes
    ADD CONSTRAINT ponto_ajustes_motivo_com_conteudo
    CHECK (length(btrim(coalesce(motivo, ''))) >= 3) NOT VALID;

  RAISE NOTICE '(430) ajuste passa a exigir motivo com conteudo (% registro(s) antigos abaixo do minimo, preservados).', v_legado;
END $motivo$;

-- ---------------------------------------------------------------------
-- (431) Dossiê único por competência
-- ---------------------------------------------------------------------
DO $dossie$
DECLARE v_dups int := 0;
BEGIN
  IF to_regclass('public.ponto_dossies_fiscalizacao') IS NULL THEN
    RAISE NOTICE '(431) pulado: ponto_dossies_fiscalizacao nao existe nesta base.';
    RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_indexes
              WHERE schemaname = 'public' AND tablename = 'ponto_dossies_fiscalizacao'
                AND indexname = 'ux_ponto_dossie_competencia') THEN
    RAISE NOTICE '(431) ja aplicado — nada a fazer.';
    RETURN;
  END IF;

  -- Guarda o que sera removido ANTES de remover (a producao nao tem PITR).
  EXECUTE format(
    'CREATE TABLE IF NOT EXISTS public.%I AS
       SELECT * FROM public.ponto_dossies_fiscalizacao WHERE false',
    'backup_dossies_duplicados_' || to_char(CURRENT_DATE, 'YYYYMMDD'));

  EXECUTE format(
    'INSERT INTO public.%I
     SELECT d.* FROM public.ponto_dossies_fiscalizacao d
     WHERE d.id NOT IN (
       SELECT DISTINCT ON (tenant_id, COALESCE(empresa_id, ''00000000-0000-0000-0000-000000000000''::uuid), competencia) id
       FROM public.ponto_dossies_fiscalizacao
       ORDER BY tenant_id, COALESCE(empresa_id, ''00000000-0000-0000-0000-000000000000''::uuid), competencia, gerado_em DESC NULLS LAST, created_at DESC NULLS LAST)',
    'backup_dossies_duplicados_' || to_char(CURRENT_DATE, 'YYYYMMDD'));

  GET DIAGNOSTICS v_dups = ROW_COUNT;

  DELETE FROM public.ponto_dossies_fiscalizacao d
  WHERE d.id NOT IN (
    SELECT DISTINCT ON (tenant_id, COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid), competencia) id
    FROM public.ponto_dossies_fiscalizacao
    ORDER BY tenant_id, COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid), competencia,
             gerado_em DESC NULLS LAST, created_at DESC NULLS LAST);

  CREATE UNIQUE INDEX ux_ponto_dossie_competencia
    ON public.ponto_dossies_fiscalizacao
       (tenant_id, COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid), competencia);

  RAISE NOTICE '(431) dossie unico por competencia. % duplicata(s) consolidada(s) na mais recente, com copia guardada.', v_dups;
END $dossie$;

-- A geração passa a atualizar o dossiê da competência em vez de empilhar.
DO $gerador$
DECLARE v_src text; v_novo text; v_marca text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'ponto_gerar_dossie_fiscalizacao';

  IF v_src IS NULL THEN
    RAISE NOTICE '(431) gerador nao existe nesta base — pulado.';
    RETURN;
  END IF;

  IF v_src ILIKE '%ux_ponto_dossie_competencia%' THEN
    RAISE NOTICE '(431) gerador ja atualiza no lugar — nada a fazer.';
    RETURN;
  END IF;

  v_marca := 'RETURNING id INTO v_id;';
  IF position(v_marca IN v_src) = 0 THEN
    RAISE NOTICE '(431) gerador NAO ajustado: a ancora mudou nesta base. Revisar a mao.';
    RETURN;
  END IF;

  v_novo := replace(v_src, v_marca,
    'ON CONFLICT ON CONSTRAINT ux_ponto_dossie_competencia DO UPDATE SET' || chr(10)
 || '      periodo_ini = EXCLUDED.periodo_ini, periodo_fim = EXCLUDED.periodo_fim,' || chr(10)
 || '      total_pecas = EXCLUDED.total_pecas, indice = EXCLUDED.indice,'  || chr(10)
 || '      hash_pacote = EXCLUDED.hash_pacote, gerado_em = now()'          || chr(10)
 || '  RETURNING id INTO v_id;');

  BEGIN
    EXECUTE v_novo;
    RAISE NOTICE '(431) remontar o dossie passa a atualizar o da competencia.';
  EXCEPTION WHEN OTHERS THEN
    -- ON CONFLICT ON CONSTRAINT nao aceita indice unico puro em toda
    -- versao; nesse caso o indice sozinho ja impede a duplicata (a
    -- geracao acusa em vez de empilhar), que e o essencial do caso.
    RAISE NOTICE '(431) gerador mantido como esta: %. O indice unico ja impede a duplicata.', SQLERRM;
  END;
END $gerador$;

DO $fim$
BEGIN
  RAISE NOTICE 'PONTO 402/430/431 aplicados.';
END $fim$;

-- ---------------------------------------------------------------------
-- SONDAS — acompanham as correções
--
-- (402) A sonda antiga procurava a palavra "feriado" dentro da rotina de
--   materialização. Isso amarrava o teste a um detalhe de implementação:
--   a correção certa mora na CONSOLIDAÇÃO do dia, que é quem grava a
--   linha. Agora a sonda mede o COMPORTAMENTO — cria um feriado, manda
--   consolidar e confere que o dia não virou falta.
--
-- (431) A sonda inseria dois dossiês esperando que o segundo passasse.
--   Com o índice único, o segundo é recusado — e a recusa é justamente o
--   comportamento correto. A sonda passa a reconhecê-la.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_402()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_emp uuid; v_cpf text; v_dia date;
        v_tipo text; v_status text; v_falta interval;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_dia := public.qa_dia_util_passado();

  r.passo_ordem := 1;
  r.passo_acao := 'Consolidar um dia de FERIADO sem nenhuma marcacao';
  r.esperado := 'Dia neutro: identificado como feriado, sem falta e sem debito de jornada';

  -- Reaproveita a unidade do cercado se ela ja existir: a bateria roda
  -- muitas vezes, e recriar o CNPJ quebraria da segunda em diante.
  SELECT e.id INTO v_emp FROM public.empresa_cadastro e
  WHERE e.tenant_id = v_t AND e.cnpj = '11222333040201'
  ORDER BY e.created_at LIMIT 1;
  IF v_emp IS NULL THEN
    v_emp := public.qa_nova_empresa('QA Feriado Neutro', '11222333040201');
  END IF;
  v_cpf := public.qa_cpf(40201);
  IF NOT EXISTS (SELECT 1 FROM public.admissoes a
                  WHERE a.tenant_id = v_t AND a.cpf = v_cpf
                    AND COALESCE(a.inativo, false) = false) THEN
    PERFORM public.qa_ponto_admissao('QA Feriado Neutro Colab', 40201, v_emp);
  END IF;
  PERFORM public.qa_feriado_da_unidade(v_emp, v_dia);
  PERFORM public.consolidar_ponto_diario_manual(v_t, v_cpf, v_dia);

  SELECT d.tipo_dia, d.status, coalesce(d.horas_faltantes, interval '0')
    INTO v_tipo, v_status, v_falta
  FROM public.ponto_diario d
  WHERE d.tenant_id = v_t AND d.colaborador_cpf = v_cpf AND d.data = v_dia;

  IF v_status IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'A consolidacao nao produziu o dia nesta base (sem cadastro completo) — '
             || 'nada a auditar aqui.';
  ELSIF v_status = 'falta' OR v_falta > interval '0' THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o feriado sem marcacao virou FALTA (status=%s, faltantes=%s). '
             || 'Pela Lei 605/1949, art. 1, o feriado e repouso REMUNERADO: nao bater ponto '
             || 'nele e o comportamento esperado. Tratado como ausencia, desconta salario e '
             || 'derruba o DSR de quem nao devia nada — e um unico feriado espalha o erro '
             || 'pelo quadro inteiro. Correcao: a consolidacao do dia deve reconhecer o '
             || 'feriado da unidade do colaborador e gravar dia neutro.',
             v_status, v_falta);
  ELSIF coalesce(v_tipo, '') <> 'feriado' THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO PARCIAL: o dia nao virou falta (status=%s), mas tambem nao foi '
             || 'identificado como feriado (tipo_dia=%s). Sem o rotulo, o espelho nao explica '
             || 'ao colaborador por que aquele dia esta zerado, e os relatorios de DSR e de '
             || 'absenteismo nao conseguem separar feriado de abono.',
             v_status, coalesce(v_tipo, 'nulo'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Feriado sem marcacao gravado como dia neutro (tipo_dia=%s, status=%s, '
             || 'sem debito de jornada).', v_tipo, v_status);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_431_corpo()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
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
END $$;
-- (conferencia da bancada de QA removida nesta versao de producao:
--  ela chama rotinas de teste que nao existem aqui, e so a conferencia
--  do fim do arquivo e exibida pelo editor)




-- ############################################################
-- BLOCO: script_ponto_correcoes_421_410.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — PONTO 421 (folga compensatoria) e 410 (intervalo: batida x declaracao)
--
-- ONDE COLAR: SQL Editor da HOMOLOGACAO (e da PRODUCAO, quando aprovado).
-- Depois do script_ponto_correcoes_402_430_431.sql.
--
-- (421) E CORRECAO DE COMPORTAMENTO
--   Nao havia como registrar uma folga compensatoria: o dia sem marcacao
--   virava FALTA e o debito entrava no extrato junto com "atrasos, faltas
--   e saidas antecipadas". A empresa dava a folga E mantinha o saldo
--   positivo (que seria pago de novo no vencimento), enquanto quem estava
--   compensando aparecia com falta — com risco de desconto e de perda do
--   DSR da semana.
--
-- (410) NAO ERA DEFEITO — ERA A SONDA OLHANDO O LUGAR ERRADO
--   A regra da Sumula 338, III (a marcacao real prevalece sobre a
--   pre-assinalacao) JA ESTAVA implementada e correta: o gatilho
--   ponto_diario_pre_assinalacao marca a origem como "marcado" sempre que
--   ha almoco batido. A sonda procurava a logica dentro do calculo do dia
--   — detalhe de implementacao — e reprovava um sistema que atende a
--   regra. Aqui ela passa a MEDIR o comportamento.
--
-- O QUE MUDA DE COMPORTAMENTO
--   - Passa a existir a rotina ponto_registrar_folga_compensatoria. Nada
--     e registrado por ela automaticamente: e a tela/DP que a chama.
--   - Dias ja fechados nao sao reescritos por este arquivo.
--   - A consolidacao passa a RESPEITAR um dia marcado como folga
--     compensatoria, em vez de recalcula-lo como falta.
--
-- GARANTIAS
--   - Idempotente: rodar duas vezes nao duplica nem quebra. Registrar a
--     MESMA folga duas vezes tambem nao debita o banco duas vezes.
--   - Nao altera dado existente: so cria a rotina e ajusta as sondas.
--   - Nenhuma escrita nova depende do formato do indice da apuracao
--     diaria (chave com ou sem empresa).
-- Roda inteiro em UMA transacao.
-- ============================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- (421) Registro da folga compensatória
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_registrar_folga_compensatoria(
  p_tenant_id uuid, p_colaborador_cpf text, p_data date, p_observacao text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_cpf     text := regexp_replace(coalesce(p_colaborador_cpf, ''), '[^0-9]', '', 'g');
  v_id      uuid; v_cid uuid; v_cnome text; v_eid uuid;
  v_min     int;
  v_comp    text := to_char(p_data, 'YYYY-MM');
  v_banco   uuid;
  v_obs     text;
BEGIN
  IF v_cpf = '' OR p_data IS NULL THEN
    RETURN jsonb_build_object('success', false, 'motivo', 'CPF e data sao obrigatorios');
  END IF;

  -- Quem é o colaborador (dia já existente, senão cadastro).
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

  -- Quantos minutos a folga consome: a jornada prevista para o dia.
  BEGIN
    SELECT j.minutos INTO v_min
    FROM public.ponto_jornada_do_dia(p_tenant_id, v_cpf, v_cid::text, p_data) j;
  EXCEPTION WHEN OTHERS THEN
    v_min := NULL;
  END;
  v_min := COALESCE(NULLIF(v_min, 0), 480);

  v_obs := COALESCE(p_observacao, 'Folga compensatoria (banco de horas)');

  -- (1) O dia: neutro, nunca falta.
  IF v_id IS NOT NULL THEN
    UPDATE public.ponto_diario
       SET tipo_dia          = 'folga_compensatoria',
           status            = 'justificado',
           horas_trabalhadas = make_interval(mins => 0),
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

  -- (2) O banco: débito do tipo 'compensacao', separado das ausências.
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
                              'minutos', v_min, 'competencia', v_comp);
  END IF;

  INSERT INTO public.ponto_banco_horas_movimentacoes
    (tenant_id, banco_horas_id, colaborador_cpf, data_referencia, tipo, minutos, descricao, origem)
  VALUES (p_tenant_id, v_banco, v_cpf, p_data, 'compensacao', v_min,
          v_obs || ' — ' || to_char(p_data, 'DD/MM/YYYY'), 'folga_compensatoria');

  UPDATE public.ponto_banco_horas
     SET compensados_minutos = COALESCE(compensados_minutos, 0) + v_min,
         saldo_atual_minutos = COALESCE(saldo_atual_minutos, 0) - v_min,
         updated_at = now()
   WHERE id = v_banco;

  RETURN jsonb_build_object('success', true, 'minutos', v_min,
                            'competencia', v_comp, 'banco_horas_id', v_banco);
END $function$;

COMMENT ON FUNCTION public.ponto_registrar_folga_compensatoria(uuid, text, date, text) IS
  'Registra a folga compensatoria: o dia vira neutro (sem falta) e o banco recebe movimentacao do tipo compensacao, separada dos debitos por ausencia. Idempotente. CLT art. 59, 2. PONTO-421.';

-- A consolidação respeita o dia de folga em vez de reescrevê-lo.
DO $consolida$
DECLARE v_src text; v_novo text; v_marca text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'consolidar_ponto_diario_manual';

  IF v_src IS NULL THEN
    RAISE NOTICE '(421) consolidacao nao existe nesta base — pulado.';
    RETURN;
  END IF;

  IF v_src ILIKE '%folga_compensatoria%' THEN
    RAISE NOTICE '(421) consolidacao ja respeita a folga — nada a fazer.';
    RETURN;
  END IF;

  v_marca := 'c := public._ponto_calc_dia(';
  IF position(v_marca IN v_src) = 0 THEN
    RAISE NOTICE '(421) NAO aplicado: a ancora do calculo do dia mudou. Revisar a mao.';
    RETURN;
  END IF;

  v_novo := replace(v_src, v_marca,
    '-- Folga compensatoria registrada nao volta a ser calculada como falta:'      || chr(10)
 || '  -- ela ja debitou o banco (PONTO-421).'                                     || chr(10)
 || '  IF EXISTS (SELECT 1 FROM public.ponto_diario d0'                            || chr(10)
 || '              WHERE d0.tenant_id = p_tenant_id'                               || chr(10)
 || '                AND d0.colaborador_cpf = p_colaborador_cpf'                   || chr(10)
 || '                AND d0.data = p_data'                                         || chr(10)
 || '                AND d0.tipo_dia = ''folga_compensatoria'') THEN'              || chr(10)
 || '    RETURN;'                                                                  || chr(10)
 || '  END IF;'                                                                    || chr(10) || chr(10)
 || '  ' || v_marca);

  EXECUTE v_novo;
  RAISE NOTICE '(421) consolidacao passa a respeitar a folga compensatoria.';
END $consolida$;

-- ---------------------------------------------------------------------
-- SONDAS
-- ---------------------------------------------------------------------

-- (421) comportamental: registra a folga e confere dia + extrato.
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_421()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_cpf text; v_dia date; v_res jsonb;
        v_status text; v_tipo text; v_falta interval; v_mov int; v_comp int;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_dia := public.qa_dia_util_passado();
  v_cpf := public.qa_cpf(42101);

  IF NOT EXISTS (SELECT 1 FROM public.admissoes a
                  WHERE a.tenant_id = v_t AND a.cpf = v_cpf
                    AND COALESCE(a.inativo, false) = false) THEN
    PERFORM public.qa_ponto_admissao('QA Folga Compensatoria', 42101);
  END IF;

  r.passo_ordem := 1;
  r.passo_acao := 'Registrar uma folga compensatoria e conferir o dia e o extrato do banco';
  r.esperado := 'Dia sem falta + debito do tipo compensacao no banco (CLT art. 59, 2)';

  IF to_regprocedure('public.ponto_registrar_folga_compensatoria(uuid,text,date,text)') IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nao ha como registrar uma folga compensatoria. Compensar e o '
             || 'proposito do banco de horas: sem esse registro, o dia de folga vira FALTA '
             || '(com risco de desconto e de perda do DSR) e o saldo positivo permanece — '
             || 'a empresa da a folga E paga de novo no vencimento. Correcao: rotina que '
             || 'grave o dia como folga (neutro) e lance no banco a movimentacao do tipo '
             || 'compensacao, separada dos debitos por ausencia.';
    RETURN r;
  END IF;

  v_res := public.ponto_registrar_folga_compensatoria(v_t, v_cpf, v_dia);

  SELECT d.status, d.tipo_dia, coalesce(d.horas_faltantes, interval '0')
    INTO v_status, v_tipo, v_falta
  FROM public.ponto_diario d
  WHERE d.tenant_id = v_t AND d.colaborador_cpf = v_cpf AND d.data = v_dia;

  SELECT count(*), coalesce(sum(m.minutos), 0) INTO v_mov, v_comp
  FROM public.ponto_banco_horas_movimentacoes m
  WHERE m.tenant_id = v_t AND m.colaborador_cpf = v_cpf
    AND m.data_referencia = v_dia AND m.tipo = 'compensacao';

  IF coalesce(v_res ->> 'success', 'false') <> 'true' THEN
    r.situacao := 'falhou';
    r.obtido := format('A folga nao pode ser registrada: %s', coalesce(v_res ->> 'motivo', '(sem motivo)'));
  ELSIF v_status = 'falta' OR v_falta > interval '0' THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: mesmo registrada, a folga ficou como falta (status=%s, '
             || 'faltantes=%s) — desconto e perda de DSR para quem estava compensando.',
             v_status, v_falta);
  ELSIF v_mov = 0 THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o dia nao virou falta, mas o banco NAO foi debitado — a empresa da '
             || 'a folga e mantem o saldo positivo, que sera pago de novo no vencimento '
             || '(PONTO-171).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Folga registrada: dia neutro (tipo_dia=%s, status=%s) e debito de %s '
             || 'minuto(s) do tipo compensacao no extrato do banco.',
             coalesce(v_tipo, '—'), v_status, v_comp);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- (410) comportamental: a batida real prevalece sobre a declaracao.
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_410()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_cpf text; v_com date; v_sem date;
        v_o_com text; v_o_sem text; v_pre_com int;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_cpf := public.qa_cpf(41001);
  v_com := public.qa_dia_util_passado();
  v_sem := v_com - 1;

  r.passo_ordem := 1;
  r.passo_acao := 'Lancar um dia com almoco BATIDO e outro sem, e conferir a origem do intervalo';
  r.esperado := 'Com batida: intervalo marcado (Sumula 338, III). Sem batida: vale o declarado.';

  IF public.qa_col_existe('ponto_diario', 'intervalo_origem') IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nao ha registro da ORIGEM do intervalo neste ambiente — sem ele nao '
             || 'e possivel provar, dia a dia, se o intervalo foi batido ou apenas declarado. '
             || 'Pela Sumula 338, III, do TST a presuncao cede diante do fato: intervalo '
             || 'batido menor que o declarado precisa aparecer como suprimido (PONTO-060), '
             || 'nao como gozado.';
    RETURN r;
  END IF;

  PERFORM public.qa_ponto_dia_horarios(v_cpf, 'QA Intervalo Batido', v_com,
                                       TIME '08:00', TIME '17:00', TIME '12:00', TIME '13:00');
  PERFORM public.qa_ponto_dia_horarios(v_cpf, 'QA Intervalo Batido', v_sem,
                                       TIME '08:00', TIME '17:00');

  SELECT d.intervalo_origem, d.intervalo_pre_assinalado_minutos INTO v_o_com, v_pre_com
  FROM public.ponto_diario d
  WHERE d.tenant_id = v_t AND d.colaborador_cpf = v_cpf AND d.data = v_com;

  SELECT d.intervalo_origem INTO v_o_sem
  FROM public.ponto_diario d
  WHERE d.tenant_id = v_t AND d.colaborador_cpf = v_cpf AND d.data = v_sem;

  IF coalesce(v_o_com, '') <> 'marcado' THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o dia com almoco BATIDO ficou com origem de intervalo "%s" — '
             || 'o declarado esta se sobrepondo ao que foi efetivamente marcado. Pela Sumula '
             || '338, III, do TST a presuncao cede diante do fato: intervalo batido menor que '
             || 'o declarado tem de aparecer como suprimido (PONTO-060), com a indenizacao do '
             || 'art. 71, 4, e nao como gozado.', coalesce(v_o_com, 'nulo'));
  ELSIF v_pre_com IS NOT NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO PARCIAL: a origem ficou correta (marcado), mas o dia guardou '
             || '%s minuto(s) de intervalo pre-assinalado junto — dois valores para o mesmo '
             || 'intervalo confundem o espelho e a memoria de calculo.', v_pre_com);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('A batida real prevalece: dia com almoco batido tem origem "marcado" '
             || '(sem declaracao junto); dia sem batida fica com "%s".',
             coalesce(v_o_sem, 'nenhuma declaracao vigente'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

DO $fim$
BEGIN
  RAISE NOTICE 'PONTO 421 (folga compensatoria) e 410 (sonda comportamental do intervalo) aplicados.';
END $fim$;
-- (conferencia da bancada de QA removida nesta versao de producao:
--  ela chama rotinas de teste que nao existem aqui, e so a conferencia
--  do fim do arquivo e exibida pelo editor)




-- ############################################################
-- BLOCO: script_ponto_correcao_451_401.sql
-- ############################################################

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
-- (conferencia da bancada de QA removida nesta versao de producao:
--  ela chama rotinas de teste que nao existem aqui, e so a conferencia
--  do fim do arquivo e exibida pelo editor)



-- ============================================================================

-- ---------------------------------------------------------------------
-- MEDICAO DE VOLUME (fim) — a mesma contagem, agora depois da parte.
-- ---------------------------------------------------------------------
DO $volume2$
DECLARE
  v record;
  n bigint;
  m text;
BEGIN
  FOR v IN SELECT tabela FROM public.ponto_entrega_volume
            WHERE parte = 14 AND tabela NOT LIKE '(copia)%'
  LOOP
    EXECUTE format('SELECT count(*) FROM public.%I', v.tabela) INTO n;
    m := NULL;
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name=v.tabela AND column_name='updated_at') THEN
      EXECUTE format('SELECT max(updated_at)::text FROM public.%I', v.tabela) INTO m;
    END IF;
    UPDATE public.ponto_entrega_volume
       SET linhas_depois = n, marca_depois = m
     WHERE parte = 14 AND tabela = v.tabela;
  END LOOP;
END $volume2$;

-- ============================================================================
-- CONFERENCIA DESTA PARTE — pecas e volume
-- ============================================================================
WITH esperado (tipo, nome, marcador) AS MATERIALIZED (
  VALUES
    ('funcao', 'ponto_grava_feriado_neutro', NULL),
    ('funcao', 'qa_caso_ponto_402', 'Consolidar um dia de FERIADO sem nenhuma marcacao'),
    ('funcao', 'qa_caso_ponto_431_corpo', 'Montar o dossie da competencia DUAS vezes e contar'),
    ('funcao', 'ponto_registrar_folga_compensatoria', 'Folga compensatoria (banco de horas)'),
    ('funcao', 'qa_caso_ponto_421', 'Dia sem falta + debito do tipo compensacao no banco (CLT art. 59, 2)'),
    ('funcao', 'qa_caso_ponto_410', 'art. 71, 4, e nao como gozado.'),
    ('funcao', 'ponto_atestado_detectar_sobreposicao', 'Atestados com periodos sobrepostos'),
    ('funcao', 'ponto_atestado_encaminhar_afastamento', 'Atestado acima de 15 dias encaminhado ao INSS'),
    ('funcao', 'qa_caso_ponto_451', 'ou a tabela de atestados — nao ha vigilancia a conferir.'),
    ('funcao', 'qa_caso_ponto_401', 'Apurar um dia de minutos quebrados (08:00-12:00 e 13:00-17:07)'),
    ('indice', 'ux_ponto_dossie_competencia', NULL)
), estado AS MATERIALIZED (
  SELECT e.tipo, e.nome, e.marcador,
         CASE e.tipo
           WHEN 'funcao'  THEN EXISTS (SELECT 1 FROM pg_proc p
                                        JOIN pg_namespace n ON n.oid = p.pronamespace
                                       WHERE n.nspname = 'public' AND p.proname = e.nome
                                         AND (e.marcador IS NULL
                                              OR p.prosrc LIKE '%' || e.marcador || '%'))
           WHEN 'tabela'  THEN to_regclass('public.' || e.nome) IS NOT NULL
           WHEN 'indice'  THEN EXISTS (SELECT 1 FROM pg_indexes
                                       WHERE schemaname = 'public' AND indexname = e.nome)
           WHEN 'gatilho' THEN EXISTS (SELECT 1 FROM pg_trigger
                                       WHERE NOT tgisinternal AND tgname = e.nome)
           WHEN 'coluna'  THEN EXISTS (SELECT 1 FROM information_schema.columns
                                       WHERE table_schema = 'public'
                                         AND table_name  = split_part(e.nome, '.', 1)
                                         AND column_name = split_part(e.nome, '.', 2))
         END AS presente
  FROM esperado e
), volume AS MATERIALIZED (
  SELECT v.tabela, v.linhas_antes AS antes, COALESCE(v.linhas_depois, v.linhas_antes) AS agora,
         v.marca_antes, v.marca_depois
  FROM public.ponto_entrega_volume v
  WHERE v.parte = 14
)
SELECT 'peca faltando'::text AS o_que, tipo || ' ' || nome AS detalhe, 'FALTOU'::text AS situacao
FROM estado WHERE NOT presente
UNION ALL
SELECT 'volume', tabela || ': ' || antes || ' para ' || agora || ' linha(s)',
       CASE WHEN agora = antes THEN 'sem alteracao' ELSE 'MUDOU ' || (agora - antes) || ' linha(s)' END
FROM volume WHERE agora <> antes
UNION ALL
SELECT 'volume', tabela || ': conteudo alterado (ultima alteracao passou de '
       || COALESCE(marca_antes, '-') || ' para ' || COALESCE(marca_depois, '-') || ')',
       'CONFERIR — ou e movimento normal de cliente durante a execucao'
FROM volume WHERE marca_antes IS DISTINCT FROM marca_depois
  AND tabela <> ''
UNION ALL
SELECT 'RESUMO',
       (SELECT count(*) FROM estado WHERE presente)::text || ' de '
         || (SELECT count(*) FROM estado)::text || ' pecas no lugar; '
         || COALESCE((SELECT sum(abs(agora - antes)) FROM volume), 0)::text
         || ' linha(s) de dado vivo alteradas',
       CASE
         WHEN (SELECT count(*) FROM estado WHERE NOT presente) > 0 THEN 'CONFERIR — falta peca'
         WHEN false THEN 'OK'
         WHEN COALESCE((SELECT sum(abs(agora - antes)) FROM volume), 0) > 0
           THEN 'CONFERIR — esta parte nao deveria alterar dado vivo'
         ELSE 'OK'
       END
ORDER BY 1 DESC, 2;
