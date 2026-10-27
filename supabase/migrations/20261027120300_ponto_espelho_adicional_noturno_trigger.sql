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

