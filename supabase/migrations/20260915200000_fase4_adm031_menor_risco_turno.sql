-- ============================================================================
-- Fase 4 (motores) — ADM-031: idade × risco da função e turno.
--
-- Vedação absoluta (CF art. 7º XXXIII; CLT arts. 404/405): menor de 18 não pode
-- ser admitido/alocado em jornada noturna nem em função insalubre/perigosa —
-- não há adicional que compense. O SST já cadastra os riscos por função; aqui
-- entra o cruzamento na admissão (e na troca de função/escala).
-- ============================================================================

ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS funcao_insalubre boolean NOT NULL DEFAULT false;
ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS funcao_periculosa boolean NOT NULL DEFAULT false;
ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS escala_noturna boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.admissoes.funcao_insalubre IS
  'ADM-031: função com enquadramento de insalubridade (do SST) — vedada a menor de 18.';
COMMENT ON COLUMN public.admissoes.escala_noturna IS
  'ADM-031: escala em jornada noturna — vedada a menor de 18 (CLT art. 404).';

CREATE OR REPLACE FUNCTION public.admissao_valida_menor_risco()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  v_idade integer;
BEGIN
  IF NEW.data_nascimento IS NULL THEN
    RETURN NEW;
  END IF;

  -- Idade na data de admissao (ou hoje, se ainda sem data).
  v_idade := EXTRACT(YEAR FROM age(COALESCE(NEW.data_admissao, CURRENT_DATE), NEW.data_nascimento))::int;

  IF v_idade < 18 THEN
    -- Jornada noturna: vedada ao menor (CLT art. 404).
    IF COALESCE(NEW.escala_noturna, false) THEN
      RAISE EXCEPTION
        'Menor de 18 anos nao pode ser alocado em jornada noturna (CLT art. 404).'
        USING ERRCODE = 'check_violation';
    END IF;
    -- Funcao insalubre ou perigosa (periculosa): vedada ao menor (CLT art. 405).
    IF COALESCE(NEW.funcao_insalubre, false) OR COALESCE(NEW.funcao_periculosa, false) THEN
      RAISE EXCEPTION
        'Menor de 18 anos nao pode ser admitido em funcao insalubre ou perigosa (CLT art. 405, CF art. 7 XXXIII).'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_admissao_valida_menor_risco ON public.admissoes;
CREATE TRIGGER trg_admissao_valida_menor_risco
  BEFORE INSERT OR UPDATE OF data_nascimento, data_admissao,
                            funcao_insalubre, funcao_periculosa, escala_noturna
  ON public.admissoes
  FOR EACH ROW EXECUTE FUNCTION public.admissao_valida_menor_risco();
