-- ============================================================================
-- DIAGNOSTICO 3 (rollback automatico) — estado real ao inserir 2 empresas com
-- o mesmo CNPJ na HOMOLOGACAO. Cria uma rotina de QA e roda pelo executor
-- descartavel (desfaz tudo). Revela onde o CNPJ deixa de ser barrado.
-- Depois de usar, pode remover: DROP FUNCTION public.qa_caso_diag_emp();
-- ============================================================================
CREATE OR REPLACE FUNCTION public.qa_caso_diag_emp() RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
  v_cnpj text := '11222333000848';
  v_id1 uuid; v_ativo1 boolean; v_tenant1 uuid; v_cnpj1 text;
  v_cnt_before int; v_blocked boolean := false; v_err text := ''; v_cnt_after int;
BEGIN
  PERFORM public.qa_modo_ligar();
  INSERT INTO public.empresa_cadastro (tenant_id, razao_social, nome_fantasia, cnpj, ativo)
    VALUES (v_t,'DIAG1','DIAG1',v_cnpj,true) RETURNING id, ativo, tenant_id, cnpj INTO v_id1, v_ativo1, v_tenant1, v_cnpj1;
  SELECT count(*) INTO v_cnt_before FROM public.empresa_cadastro
    WHERE tenant_id=v_t AND ativo=true AND regexp_replace(coalesce(cnpj,''),'[^0-9]','','g')=v_cnpj;
  BEGIN
    INSERT INTO public.empresa_cadastro (tenant_id, razao_social, nome_fantasia, cnpj, ativo)
      VALUES (v_t,'DIAG2','DIAG2',v_cnpj,true);
  EXCEPTION
    WHEN unique_violation THEN v_blocked := true;
    WHEN OTHERS THEN v_err := SQLERRM;
  END;
  SELECT count(*) INTO v_cnt_after FROM public.empresa_cadastro
    WHERE tenant_id=v_t AND ativo=true AND regexp_replace(coalesce(cnpj,''),'[^0-9]','','g')=v_cnpj;
  r.situacao := 'passou';
  r.obtido := format('row1_ativo=%s | row1_tenant=%s | row1_cnpjnorm=%s | v_t=%s | ativos_com_cnpj_apos_row1=%s | row2_blocked=%s | row2_erro=%s | ativos_apos_row2=%s',
     v_ativo1, v_tenant1, regexp_replace(coalesce(v_cnpj1,''),'[^0-9]','','g'), v_t, v_cnt_before, v_blocked, NULLIF(v_err,''), v_cnt_after);
  RETURN r;
END $fn$;

SELECT (public.qa_executar_descartavel('qa_caso_diag_emp')).obtido AS diagnostico;
