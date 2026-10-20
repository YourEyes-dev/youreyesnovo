-- ============================================================================
-- ENTREGA (QA) — atualiza 5 rotinas de teste da bancada: COLAB-011, 021, 023, 033 e DOC-030
--
-- Cole ESTE arquivo inteiro no SQL Editor (HOMOLOGACAO e, depois, PRODUCAO).
-- A bateria de QA na producao (20/10/2026) mostrou que estas 5 rotinas estao em versao antiga:
-- montam o dado de teste sem CPF valido / sem o desenho atual do versionamento e acusam falha
-- que NAO existe no sistema (gatilhos, restricoes e cpf_valido da producao sao identicos aos da main).
--
-- So troca o corpo de rotinas de TESTE (CREATE OR REPLACE). Nao toca em tabela, dado de cliente,
-- tela ou regra de negocio. Roda em UMA transacao e e idempotente.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.qa_caso_colab_011()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_id uuid;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Tentar cadastrar colaborador SEM CPF (so nome e email)';
  r.esperado := 'Recusado — colaborador sem CPF fica fora da protecao de duplicidade';
  BEGIN
    INSERT INTO public.usuarios_base (tenant_id, nome_completo, email_principal, tipo_usuario, status)
    VALUES (v_t, '[QA-011] Sem CPF', 'qa.011.1@sandbox.invalid', 'colaborador', 'ativo');
    r.situacao := 'falhou';
    r.obtido := 'ACEITOU colaborador sem CPF — a constraint usuarios_base_colaborador_exige_cpf '
             || 'nao esta segurando. Sem CPF, o registro fica fora do indice de unicidade e de '
             || 'qualquer protecao contra duplicidade.';
    RETURN r;
  EXCEPTION WHEN check_violation THEN
    r.obtido := 'Sem CPF, recusado pela constraint.';
  END;

  r.passo_ordem := 2;
  r.passo_acao := 'Cadastrar o mesmo colaborador COM CPF valido';
  r.esperado := 'Aceito — o minimo obrigatorio (nome, email, CPF) basta';
  INSERT INTO public.usuarios_base (tenant_id, nome_completo, email_principal, cpf, tipo_usuario, status)
  VALUES (v_t, '[QA-011] Com CPF', 'qa.011.2@sandbox.invalid', public.qa_cpf(1101),
          'colaborador', 'ativo')
  RETURNING id INTO v_id;

  IF v_id IS NOT NULL THEN
    r.situacao := 'passou';
    r.obtido := 'Colaborador sem CPF barrado; com CPF valido, criado com o minimo. '
             || 'A regra nova (constraint de 30/07, recomendada pelo proprio QA) esta de pe.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'Com CPF valido, nao criou.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

CREATE OR REPLACE FUNCTION public.qa_caso_colab_021()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_id uuid;
  v_estado text;
  v_msg text;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem := 1;
  r.passo_acao  := 'Tentar cadastrar com CPF matematicamente invalido (111.111.111-11)';
  r.esperado    := 'Recusado pelo banco — digito verificador invalido';

  BEGIN
    INSERT INTO public.usuarios_base (tenant_id, nome_completo, email_principal, cpf, tipo_usuario, status)
    VALUES (v_t, '[QA-021] CPF Ruim', 'qa.021.1@sandbox.invalid', '11111111111', 'colaborador', 'ativo')
    RETURNING id INTO v_id;

    r.situacao := 'falhou';
    r.obtido   := 'O BANCO ACEITOU CPF invalido. A validacao existe so no front — '
               || 'a trigger valida_cpf_usuario nao esta instalada nesta base.';
    RETURN r;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_estado = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
  END;

  -- check_violation (23514) e a recusa esperada: e o ERRCODE que a trigger
  -- levanta e o mesmo de um CHECK constraint, caso a defesa mude de forma.
  -- unaccent nao esta garantido em toda base, entao a checagem de texto usa
  -- translate para tirar os acentos que interessam.
  IF v_estado = '23514'
     OR lower(translate(v_msg, 'áàâãéêíóôõúüç', 'aaaaeeiooouuc')) LIKE '%cpf%'
     OR lower(translate(v_msg, 'áàâãéêíóôõúüç', 'aaaaeeiooouuc')) LIKE '%invalid%' THEN
    r.situacao := 'passou';
    r.obtido   := format('Recusado pelo banco, como deveria (SQLSTATE %s): %s', v_estado, v_msg);
  ELSE
    r.situacao := 'falhou';
    r.obtido   := format('A escrita falhou, mas por outro motivo — nao pela validacao de CPF '
                      || '(SQLSTATE %s): %s', v_estado, v_msg);
    r.erro_tecnico := v_msg;
  END IF;

  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

CREATE OR REPLACE FUNCTION public.qa_caso_colab_023()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem := 1; r.passo_acao := 'Criar pessoa com um email';
  INSERT INTO public.usuarios_base (tenant_id, nome_completo, email_principal, cpf, tipo_usuario, status)
  VALUES (v_t, '[QA-023] A', 'qa.023.dup@sandbox.invalid', public.qa_cpf(2301), 'colaborador', 'ativo');
  r.passo_ordem := 2;
  r.passo_acao := 'Tentar criar OUTRA pessoa (CPF diferente) com o MESMO email no mesmo tenant';
  r.esperado := 'Recusado — email e chave de acesso, nao pode duplicar';
  BEGIN
    INSERT INTO public.usuarios_base (tenant_id, nome_completo, email_principal, cpf, tipo_usuario, status)
    VALUES (v_t, '[QA-023] B', 'qa.023.dup@sandbox.invalid', public.qa_cpf(2302), 'colaborador', 'ativo');
    r.situacao := 'falhou';
    r.obtido := 'O BANCO ACEITOU email duplicado. Nao ha constraint unica em email_principal — dois usuarios podem ter o mesmo login. Falta protecao no banco.';
  EXCEPTION WHEN unique_violation THEN
    r.situacao := 'passou'; r.obtido := 'Recusado, como deveria.';
  END;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

CREATE OR REPLACE FUNCTION public.qa_caso_colab_033()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_cru  text := public.qa_cpf(1033);
  v_fmt  text := public.qa_cpf_formatado(public.qa_cpf(1033));
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM public.qa_fixture_limpar('COLAB-033');

  r.passo_ordem := 1;
  r.passo_acao  := 'Cadastrar pessoa com CPF sem formatacao (' || v_cru || ')';

  INSERT INTO public.usuarios_base
    (tenant_id, nome_completo, email_principal, cpf, tipo_usuario, status)
  VALUES (v_t, '[QA-COLAB-033] Pessoa CPF Cru', public.qa_fixture_email('COLAB-033', 1),
          v_cru, 'colaborador', 'ativo');

  r.passo_ordem := 2;
  r.passo_acao  := 'Cadastrar OUTRA pessoa com o MESMO CPF, agora formatado (' || v_fmt || ')';
  r.esperado    := 'Recusado — mesmos 11 digitos, mesma pessoa';

  BEGIN
    INSERT INTO public.usuarios_base
      (tenant_id, nome_completo, email_principal, cpf, tipo_usuario, status)
    VALUES (v_t, '[QA-COLAB-033] Pessoa CPF Formatado', public.qa_fixture_email('COLAB-033', 2),
            v_fmt, 'colaborador', 'ativo');

    r.situacao := 'falhou';
    r.obtido   := 'ACEITOU. A mesma pessoa existe duas vezes, separada so pela pontuacao do CPF. '
               || 'usuarios_base_cpf_tenant_uidx e sobre a coluna crua e nao enxerga que '
               || regexp_replace(v_fmt,'[^0-9]','','g') || ' = ' || v_cru
               || '. Correcao: normalizar o CPF na escrita (trigger) e reconstruir o indice '
               || 'sobre a forma normalizada.';
    r.detalhe  := jsonb_build_object(
                    'cpf_gravado_1', v_cru,
                    'cpf_gravado_2', v_fmt,
                    'digitos_iguais', regexp_replace(v_fmt,'[^0-9]','','g') = v_cru);
  EXCEPTION
    WHEN unique_violation THEN
      r.situacao := 'passou';
      r.obtido   := 'Recusado com unique_violation. O CPF esta normalizado na escrita.';
    WHEN OTHERS THEN
      r.situacao := 'erro'; r.obtido := 'Erro inesperado'; r.erro_tecnico := SQLERRM;
  END;

  PERFORM public.qa_fixture_limpar('COLAB-033');
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $function$;

CREATE OR REPLACE FUNCTION public.qa_caso_doc_030()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_doc uuid; v_qtd int; v_v1 int; v_v2 int; v_path_v1 text;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao  := 'Guardar um documento — a v1 nasce com ele';
  r.esperado    := 'Revisar cria a versao 2 preservando a versao 1 (a premissa da assinatura)';
  v_doc := public.qa_novo_documento('[QA] termo.pdf');

  SELECT storage_path INTO v_path_v1
  FROM public.documento_versoes WHERE documento_id = v_doc AND versao = 1;

  r.passo_ordem := 2;
  r.passo_acao  := 'Documento assinado chega: gravar o novo arquivo (revisao)';
  INSERT INTO public.documento_versoes
    (tenant_id, documento_id, versao, nome_original, storage_path, tamanho, mime_type, motivo_revisao)
  VALUES (v_t, v_doc, 2, '[QA] termo_assinado.pdf', 'qa/termo_v2_assinado.pdf', 2048,
          'application/pdf', 'Versao assinada');

  r.passo_ordem := 3;
  r.passo_acao  := 'Tentar forcar uma SEGUNDA versao 1 (o defeito do DOC-030)';
  INSERT INTO public.documento_versoes
    (tenant_id, documento_id, versao, nome_original, storage_path, tamanho, mime_type)
  VALUES (v_t, v_doc, 1, '[QA] termo_falso.pdf', 'qa/termo_v1_falso.pdf', 512, 'application/pdf');

  r.passo_ordem := 4;
  r.passo_acao  := 'Conferir: v1 unica e preservada, v2 assinada';
  SELECT count(*) INTO v_qtd FROM public.documento_versoes WHERE documento_id = v_doc;
  SELECT count(*) INTO v_v1  FROM public.documento_versoes WHERE documento_id = v_doc AND versao = 1;
  SELECT count(*) INTO v_v2  FROM public.documento_versoes WHERE documento_id = v_doc AND versao = 2;

  IF v_v1 = 1 AND v_v2 = 1
     AND (SELECT storage_path FROM public.documento_versoes
           WHERE documento_id = v_doc AND versao = 1) IS NOT DISTINCT FROM v_path_v1 THEN
    r.situacao := 'passou';
    r.obtido   := format('v1 unica e intacta, v2 assinada. A tentativa de sobrescrever a v1 virou '
                      || 'versao %s em vez de duplicar. Total de versoes: %s.', v_qtd, v_qtd);
  ELSE
    r.situacao := 'falhou';
    r.obtido   := format('Esperava v1 unica e preservada. Total=%s, v1=%s, v2=%s.', v_qtd, v_v1, v_v2);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

-- ── Conferencia (o editor mostra so o ultimo resultado) ─────────────────────
-- Esperado: as 5 linhas com igual_a_main = true.
SELECT nome, hash_producao, hash_main, (hash_producao = hash_main) AS igual_a_main
FROM (
  SELECT v.nome, v.hash_main,
         coalesce((SELECT left(md5(regexp_replace(regexp_replace(p.prosrc, '--[^\n]*', '', 'g'), '\s+', '', 'g')), 8)
                     FROM pg_proc p JOIN pg_namespace s ON s.oid = p.pronamespace
                    WHERE s.nspname = 'public' AND p.proname = v.nome LIMIT 1), 'NAO EXISTE') AS hash_producao
  FROM (VALUES ('qa_caso_colab_011','2ae0e5b2'), ('qa_caso_colab_021','ec994b20'), ('qa_caso_colab_023','f36cd0b8'), ('qa_caso_colab_033','8e42d474'), ('qa_caso_doc_030','f4bc2512')) v(nome, hash_main)
) x ORDER BY nome;

-- Depois, para ver as rotinas passando (leitura; cada caso roda numa subtransacao desfeita):
--   SELECT public.qa_rodar_bateria('manual', 'estrutura-organizacional/colaboradores');
--   SELECT public.qa_rodar_bateria('manual', 'documentos-governanca/documentos');
