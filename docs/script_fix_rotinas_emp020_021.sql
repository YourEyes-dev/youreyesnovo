-- ============================================================================
-- Correcao das rotinas de QA EMP-020/EMP-021 — ENTREGA producao.
--
-- Diagnostico: o gatilho de duplicidade JA barra o CNPJ duplicado na
-- homologacao (teste direto: row2_blocked=t). Quem reportava 'ACEITOU' era a
-- ROTINA de QA emp_020/021, uma versao ANTIGA (stale) que media errado — o
-- controle funciona, a medicao e que estava desatualizada.
--
-- Aqui as rotinas voltam a versao de referencia (a do desenvolvimento). So
-- CREATE OR REPLACE de funcoes de QA (somente leitura, rollback) — nao ha DDL
-- em empresa_cadastro, entao nao ha lock pesado nem risco de deadlock. Remove
-- tambem a funcao de diagnostico qa_caso_diag_emp, se tiver sido criada.
--
-- A CONFERENCIA das rotinas continua em docs/conferencia_emp_unicidade.sql,
-- para rodar DEPOIS em transacao propria.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.qa_caso_emp_020()
RETURNS qa_retorno LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem := 1; r.passo_acao := 'Criar empresa ativa com um CNPJ';
  r.esperado := 'Segunda empresa ativa com o mesmo CNPJ e recusada';
  INSERT INTO public.empresa_cadastro (tenant_id, razao_social, nome_fantasia, cnpj, ativo)
  VALUES (v_t, '[QA-EMP] Ativa 1', '[QA-EMP] Ativa 1', '11222333000848', true);
  r.passo_ordem := 2; r.passo_acao := 'Tentar segunda empresa ATIVA com o mesmo CNPJ';
  BEGIN
    INSERT INTO public.empresa_cadastro (tenant_id, razao_social, nome_fantasia, cnpj, ativo)
    VALUES (v_t, '[QA-EMP] Ativa 2', '[QA-EMP] Ativa 2', '11222333000848', true);
    r.situacao := 'falhou'; r.obtido := 'ACEITOU duas empresas ativas com o mesmo CNPJ.';
  EXCEPTION WHEN unique_violation THEN
    r.situacao := 'passou'; r.obtido := 'Recusado: a trava impede CNPJ ativo duplicado.';
  END;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

CREATE OR REPLACE FUNCTION public.qa_caso_emp_021()
RETURNS qa_retorno LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_inativa uuid;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem := 1; r.passo_acao := 'Criar uma empresa ATIVA e outra INATIVA com o mesmo CNPJ';
  r.esperado := 'Ativar a inativa (UPDATE ativo=true) e recusado';
  INSERT INTO public.empresa_cadastro (tenant_id, razao_social, nome_fantasia, cnpj, ativo)
  VALUES (v_t, '[QA-EMP] Ja Ativa', '[QA-EMP] Ja Ativa', '11222333000929', true);
  INSERT INTO public.empresa_cadastro (tenant_id, razao_social, nome_fantasia, cnpj, ativo)
  VALUES (v_t, '[QA-EMP] Inativa', '[QA-EMP] Inativa', '11222333000929', false)
  RETURNING id INTO v_inativa;
  r.passo_ordem := 2; r.passo_acao := 'Tentar ativar a segunda (mesmo CNPJ ja ativo na primeira)';
  BEGIN
    UPDATE public.empresa_cadastro SET ativo = true WHERE id = v_inativa;
    r.situacao := 'falhou'; r.obtido := 'ATIVOU a duplicata — a trava nao pega o UPDATE.';
  EXCEPTION WHEN unique_violation THEN
    r.situacao := 'passou'; r.obtido := 'Recusado: nao da pra ativar duplicata de CNPJ.';
  END;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

DROP FUNCTION IF EXISTS public.qa_caso_diag_emp();

-- Confirmacao leve (so catalogo) ---------------------------------------------
SELECT 'qa_caso_emp_020' AS rotina,
       CASE WHEN prosrc ILIKE '%impede CNPJ ativo duplicado%' THEN 'atualizada' ELSE 'ANTIGA' END AS estado
FROM pg_proc WHERE proname='qa_caso_emp_020' AND pronamespace='public'::regnamespace
UNION ALL
SELECT 'qa_caso_emp_021',
       CASE WHEN prosrc ILIKE '%nao da pra ativar duplicata de CNPJ%' THEN 'atualizada' ELSE 'ANTIGA' END
FROM pg_proc WHERE proname='qa_caso_emp_021' AND pronamespace='public'::regnamespace
ORDER BY rotina;
