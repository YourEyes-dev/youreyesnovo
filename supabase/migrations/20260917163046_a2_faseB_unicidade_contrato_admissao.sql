-- ============================================================================
-- A2 — FASE B: unicidade por CONTRATO em admissoes (nao por CPF).
--
-- A tabela admissoes e um registro historico: a mesma pessoa tem varios
-- vinculos legitimos, inclusive no MESMO CNPJ ao longo do tempo (readmissao,
-- mudanca de cargo) e em CNPJs diferentes (dois empregos). A regra antiga
-- (tenant, CPF) era cedo demais e apagaria historico.
--
-- A duplicata real e a RE-IMPORTACAO do MESMO contrato: mesma
-- (tenant, empresa, CPF, data de admissao, cargo). E essa a chave da unicidade.
--
-- Substitui o indice uq_admissoes_cpf_ativa por uq_admissoes_contrato_ativa.
-- O indice so nasce se NAO houver duplicata exata hoje (a Fase A limpa antes);
-- havendo, avisa e nao cria (nao trava o deploy). A rotina ADM-002 passa a
-- testar a chave de contrato.
-- ============================================================================

-- 1) DIAGNOSTICO — copias exatas do mesmo contrato ainda ativas -----------
CREATE OR REPLACE FUNCTION public.admissoes_contrato_duplicado()
RETURNS TABLE(tenant_id uuid, empresa_id uuid, cpf text, data_admissao date,
              cargo text, quantidade bigint, admissoes uuid[])
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT a.tenant_id,
         a.empresa_id,
         regexp_replace(COALESCE(a.cpf,''),'[^0-9]','','g') AS cpf,
         a.data_admissao,
         a.cargo,
         count(*),
         array_agg(a.id ORDER BY a.created_at)
  FROM public.admissoes a
  WHERE COALESCE(a.cpf,'') <> ''
    AND a.status NOT IN ('desligado','reprovado')
    AND COALESCE(a.inativo,false) = false
  GROUP BY a.tenant_id, a.empresa_id,
           regexp_replace(COALESCE(a.cpf,''),'[^0-9]','','g'),
           a.data_admissao, a.cargo
  HAVING count(*) > 1;
$$;

GRANT EXECUTE ON FUNCTION public.admissoes_contrato_duplicado() TO authenticated;

-- 2) TROCAR O INDICE ------------------------------------------------------
DROP INDEX IF EXISTS public.uq_admissoes_cpf_ativa;

DO $idx$
DECLARE v_dups int;
BEGIN
  SELECT count(*) INTO v_dups FROM public.admissoes_contrato_duplicado();

  IF v_dups > 0 THEN
    RAISE WARNING
      'A2 Fase B: indice de contrato NAO criado — % contrato(s) ainda duplicado(s). '
      'Rode a Fase A (limpeza) e reaplique.', v_dups;
    RETURN;
  END IF;

  CREATE UNIQUE INDEX IF NOT EXISTS uq_admissoes_contrato_ativa
    ON public.admissoes (
      tenant_id,
      COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid),
      regexp_replace(cpf, '[^0-9]', '', 'g'),
      COALESCE(data_admissao, '0001-01-01'::date),
      COALESCE(cargo, '')
    )
    WHERE cpf IS NOT NULL
      AND status NOT IN ('desligado','reprovado')
      AND COALESCE(inativo, false) = false;

  RAISE NOTICE 'A2 Fase B: indice unico de contrato criado.';
END $idx$;

-- 3) ROTINA ADM-002 — testar a chave de contrato --------------------------
CREATE OR REPLACE FUNCTION public.qa_caso_adm_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
  v_emp uuid; v_cpf text := public.qa_cpf(200002);
  v_dup_recusada boolean := false; v_readm_ok boolean := false;
  v_tag text := left(gen_random_uuid()::text, 8);
BEGIN
  PERFORM public.qa_modo_ligar();
  IF v_t IS NULL THEN r.situacao := 'nao_implementado'; r.obtido := 'Cercado de teste ausente.'; RETURN r; END IF;

  INSERT INTO public.empresa_cadastro (tenant_id, razao_social, ativo)
  VALUES (v_t, '[QA-ADM-002] Empresa ' || v_tag, true) RETURNING id INTO v_emp;

  r.passo_ordem := 1;
  r.passo_acao  := 'Criar admissao concluida (empresa, CPF, data, cargo)';
  INSERT INTO public.admissoes (tenant_id, empresa_id, nome_completo, cpf, cargo, status, data_admissao)
  VALUES (v_t, v_emp, '[QA-ADM-002] Primeiro', v_cpf, 'Operador', 'concluido', CURRENT_DATE - 100);

  r.passo_ordem := 2;
  r.passo_acao  := 'Tentar a MESMA admissao de novo (mesmo contrato) — deve recusar';
  r.esperado    := 'Recusada: re-importacao do mesmo contrato e duplicata';
  BEGIN
    INSERT INTO public.admissoes (tenant_id, empresa_id, nome_completo, cpf, cargo, status, data_admissao)
    VALUES (v_t, v_emp, '[QA-ADM-002] Copia', v_cpf, 'Operador', 'concluido', CURRENT_DATE - 100);
  EXCEPTION WHEN unique_violation THEN v_dup_recusada := true;
  END;

  r.passo_ordem := 3;
  r.passo_acao  := 'Readmissao: mesmo CPF/empresa, OUTRA data — deve aceitar';
  r.esperado    := 'Aceita: historico legitimo (readmissao) nao e duplicata';
  BEGIN
    INSERT INTO public.admissoes (tenant_id, empresa_id, nome_completo, cpf, cargo, status, data_admissao)
    VALUES (v_t, v_emp, '[QA-ADM-002] Readmissao', v_cpf, 'Operador', 'concluido', CURRENT_DATE);
    v_readm_ok := true;
  EXCEPTION WHEN OTHERS THEN v_readm_ok := false;
  END;

  IF v_dup_recusada AND v_readm_ok THEN
    r.situacao := 'passou';
    r.obtido   := 'Re-importacao identica recusada; readmissao (outra data) aceita. Chave de contrato correta.';
  ELSIF NOT v_dup_recusada THEN
    r.situacao := 'falhou';
    r.obtido   := 'Copia exata do contrato foi ACEITA — falta o indice unico de contrato.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := 'Readmissao (outra data) foi barrada — a unicidade esta estrita demais (deveria permitir historico).';
  END IF;
  r.detalhe := jsonb_build_object('copia_recusada', v_dup_recusada, 'readmissao_ok', v_readm_ok);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;
