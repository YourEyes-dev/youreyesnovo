-- ============================================================================
-- CRITICO #1 Parte B: o adicional noturno aparece no ESPELHO (e assim na folha
-- e no AEJ) por um TRIGGER BEFORE em ponto_espelhos que seta
-- total_adicional_noturno_minutos = SUM(ponto_diario.adicional_noturno) do
-- colaborador na competencia. NAO toca ponto_espelho_resumo (patch-eada por
-- varias migrations) nem o frontend. A coluna ja existe na tabela.
-- Diff zero hoje (adicional=0 em todas as fixtures). Idempotente.
-- ============================================================================
SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.ponto_espelho_adicional_noturno()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
BEGIN
  NEW.total_adicional_noturno_minutos := (
    SELECT COALESCE(SUM(COALESCE(pd.adicional_noturno_minutos, 0)), 0)::int
    FROM public.ponto_diario pd
    WHERE pd.tenant_id = NEW.tenant_id
      AND regexp_replace(COALESCE(pd.colaborador_cpf, ''), '[^0-9]', '', 'g')
          = regexp_replace(COALESCE(NEW.colaborador_cpf, ''), '[^0-9]', '', 'g')
      AND to_char(pd.data, 'YYYY-MM') = NEW.competencia
  );
  RETURN NEW;
END; $fn$;

DROP TRIGGER IF EXISTS trg_ponto_espelho_adicional_noturno ON public.ponto_espelhos;
CREATE TRIGGER trg_ponto_espelho_adicional_noturno
  BEFORE INSERT OR UPDATE ON public.ponto_espelhos
  FOR EACH ROW EXECUTE FUNCTION public.ponto_espelho_adicional_noturno();

-- VALIDACAO (rollback): noturno no ponto_diario -> trigger seta no espelho (mesmo upsert mandando 0)
DO $val$
DECLARE
  v_t uuid := public.qa_sandbox_tenant_id(); v_cpf text := public.qa_cpf(7806);
  v_d date := DATE '2026-09-15'; v_pd int; v_esp int;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM public.qa_ponto_admissao('QA B trig', 7806);
  PERFORM public.qa_ponto_marca(v_cpf,'QA B trig', v_d, TIME '22:00','entrada');
  PERFORM public.qa_ponto_marca(v_cpf,'QA B trig', v_d, TIME '23:30','saida');
  PERFORM public.consolidar_ponto_diario_manual(v_t, v_cpf, v_d);
  SELECT adicional_noturno_minutos INTO v_pd FROM public.ponto_diario
    WHERE tenant_id=v_t AND colaborador_cpf=v_cpf AND data=v_d LIMIT 1;
  -- simula o upsert do fechamento mandando 0 no adicional
  INSERT INTO public.ponto_espelhos (tenant_id, colaborador_cpf, colaborador_nome, competencia, total_adicional_noturno_minutos, status)
  VALUES (v_t, v_cpf, 'QA B trig', '2026-09', 0, 'gerado');
  SELECT total_adicional_noturno_minutos INTO v_esp FROM public.ponto_espelhos
    WHERE tenant_id=v_t AND regexp_replace(colaborador_cpf,'[^0-9]','','g')=v_cpf AND competencia='2026-09' LIMIT 1;
  RAISE NOTICE 'B-TRIG: ponto_diario.adicional=% | espelho.total_adicional_noturno=% (trigger deve ter posto o valor real, mesmo com upsert=0)', COALESCE(v_pd::text,'NULL'), COALESCE(v_esp::text,'NULL');
  RAISE EXCEPTION 'ROLLBACK_ME';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM <> 'ROLLBACK_ME' THEN RAISE NOTICE 'B-TRIG ERRO: %', SQLERRM; END IF;
END $val$;
