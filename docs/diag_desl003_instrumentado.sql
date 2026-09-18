-- ============================================================================
-- DIAGNOSTICO INSTRUMENTADO do DESL-003 (rollback automatico) — HOMOLOGACAO.
-- Insere o afastamento indeterminado com data_fim FUTURA (para nao disparar o
-- RAISE de afastamento_valida_e_encerra) e LE de volta o que os gatilhos BEFORE
-- gravaram: prazo_indeterminado ainda e true? status_geral_new foi derivado?
-- Isso revela qual peca da cadeia de afastamentos zera/ignora o prazo.
-- Depois de usar: DROP FUNCTION public.qa_caso_diag_desl003();
-- ============================================================================
CREATE OR REPLACE FUNCTION public.qa_caso_diag_desl003() RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
  v_cpf text := public.qa_cpf(100003); v_id uuid;
  v_prazo boolean; v_sgn text; v_status text; v_helper boolean;
BEGIN
  PERFORM public.qa_modo_ligar();
  -- data_fim futura evita o RAISE do valida_e_encerra; queremos so ver os campos.
  INSERT INTO public.afastamentos
    (tenant_id, colaborador_nome, colaborador_cpf, data_inicio, data_fim, status, prazo_indeterminado)
  VALUES (v_t, '[DIAG-DESL003]', v_cpf, CURRENT_DATE - 60, CURRENT_DATE + 3650, 'ativo', true)
  RETURNING id INTO v_id;
  SELECT prazo_indeterminado, status_geral_new::text, status::text
    INTO v_prazo, v_sgn, v_status
  FROM public.afastamentos WHERE id = v_id;
  v_helper := public.afastamento_sem_prazo_e_legitimo(v_prazo, v_status, v_sgn, NULL);
  r.situacao := 'passou';
  r.obtido := format(
    'apos BEFORE triggers -> prazo_indeterminado=%s | status_geral_new=%s | status=%s | helper_diz_legitimo=%s',
    v_prazo, COALESCE(v_sgn,'(null)'), v_status, v_helper);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'quebrou ao inserir'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

SELECT (public.qa_executar_descartavel('qa_caso_diag_desl003')).obtido AS diagnostico_desl003;
