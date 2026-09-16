-- ============================================================================
-- Fase 4 — MWKF-011: o BANCO grava a trilha do workflow (decisão do dono do
-- produto, 16/09).
--
-- Um gatilho AFTER UPDATE OF workflow_status em metas registra cada transição
-- em metas_workflow_log — por qualquer caminho (tela, API, integração, SQL), a
-- trilha fica íntegra. A justificativa continua vindo da tela: o gatilho a lê
-- de metas.justificativa_aprovacao (que a aprovação preenche).
--
-- O MWKF-001 é ajustado JUNTO (decisão de produto): a tela deixa de inserir a
-- linha na mão (o banco já grava); o caso passa a preencher a justificativa na
-- própria transição e a conferir a trilha que o gatilho produz.
--
-- Consequência para a tela (Publicar no Lovable): remover o INSERT manual em
-- metas_workflow_log — agora ele é redundante. Até lá, no máximo há linha
-- duplicada (cosmético), nunca ausência de trilha.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.meta_workflow_registra_trilha()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.workflow_status IS DISTINCT FROM OLD.workflow_status THEN
    INSERT INTO public.metas_workflow_log
      (tenant_id, meta_id, status_anterior, status_novo, acao, justificativa)
    VALUES (NEW.tenant_id, NEW.id, OLD.workflow_status, NEW.workflow_status,
            'transicao_' || NEW.workflow_status::text,
            NEW.justificativa_aprovacao);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_meta_workflow_registra_trilha ON public.metas;
CREATE TRIGGER trg_meta_workflow_registra_trilha
  AFTER UPDATE OF workflow_status ON public.metas
  FOR EACH ROW EXECUTE FUNCTION public.meta_workflow_registra_trilha();

-- ── MWKF-001 ajustado ao modelo "banco grava a trilha" ──────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_mwkf_001()
RETURNS public.qa_retorno
LANGUAGE plpgsql
AS $fn$
DECLARE r public.qa_retorno; v_meta uuid; v_n int; v_just text;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_meta := public.qa_nova_meta('[QA-MWKF] Meta em Aprovacao');

  r.passo_ordem := 1;
  r.passo_acao := 'Transicionar rascunho -> em_aprovacao (o banco grava a trilha sozinho)';
  r.esperado := 'workflow_status atualizado e linha no log gravada pelo gatilho';
  UPDATE public.metas SET workflow_status = 'em_aprovacao' WHERE id = v_meta;

  r.passo_ordem := 2;
  r.passo_acao := 'Transicionar em_aprovacao -> ativa com justificativa (da tela)';
  r.esperado := 'Segunda linha no log, com a justificativa preservada';
  UPDATE public.metas
     SET workflow_status = 'ativa', justificativa_aprovacao = 'Meta alinhada ao ciclo 2026'
   WHERE id = v_meta;

  SELECT count(*) INTO v_n FROM public.metas_workflow_log WHERE meta_id = v_meta;
  SELECT justificativa INTO v_just FROM public.metas_workflow_log
  WHERE meta_id = v_meta AND status_novo = 'ativa';

  IF v_n = 2 AND v_just = 'Meta alinhada ao ciclo 2026' THEN
    r.situacao := 'passou'; r.obtido := 'Trilha completa pelo banco: duas transições, justificativa preservada.';
  ELSE
    r.situacao := 'falhou'; r.obtido := format('%s linha(s) no log; justificativa = %s.', v_n, coalesce(v_just, 'nula'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;
