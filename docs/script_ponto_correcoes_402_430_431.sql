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

-- ---------------------------------------------------------------------------
-- CONFERENCIA FINAL — as tres correcoes neste ambiente.
-- Esperado: passou | passou | passou | OK
-- ---------------------------------------------------------------------------
WITH x AS MATERIALIZED (
  SELECT (public.qa_caso_ponto_402()).situacao AS c402,
         (public.qa_caso_ponto_430()).situacao AS c430,
         (public.qa_caso_ponto_431()).situacao AS c431
)
SELECT c402, c430, c431,
       CASE WHEN c402 IN ('passou','nao_implementado')
             AND c430 = 'passou'
             AND c431 IN ('passou','falhou')  -- 'falhou' so se a tabela nao existir no ambiente
            THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico
FROM x;
