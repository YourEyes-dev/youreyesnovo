-- ============================================================================
-- CAT / S-2210 — preencher o PRAZO da pendencia de CAT (AFAST-030).
--
-- Achado: o acidente dispara a pendencia de CAT (a inteligencia funciona), mas
-- a coluna afastamentos_pendencias.prazo fica vazia — o "1o dia util seguinte"
-- (art. 22 da Lei 8.213) vira prioridade textual sem relogio. Correcao: um
-- gatilho preenche o prazo = proximo dia util (reusa afastamento_proximo_dia_util,
-- que ja conhece o calendario de feriados). Em obito o prazo e imediato (a
-- pendencia especifica cuida). Read-only por natureza (so completa o prazo).
--
-- DRIFT: afastamento_proximo_dia_util existe no desenvolvimento, mas nao na
-- homologacao/producao. A migration cria/atualiza a funcao antes de usa-la
-- (CREATE OR REPLACE = no-op onde ja existe igual) para atravessar banco novo.
-- ============================================================================

-- Calendario: proximo dia util (pula fim de semana e feriados cadastrados).
CREATE OR REPLACE FUNCTION public.afastamento_proximo_dia_util(p_tenant uuid, p_data date)
RETURNS date LANGUAGE plpgsql STABLE SET search_path TO 'public'
AS $fn$
DECLARE
  v_dia date := p_data + 1;
  v_i   int := 0;
BEGIN
  WHILE v_i < 30 LOOP
    IF EXTRACT(DOW FROM v_dia) NOT IN (0, 6)
       AND NOT EXISTS (
         SELECT 1 FROM public.feriados f
          WHERE f.ativo
            AND (f.tenant_id = p_tenant OR f.tenant_id IS NULL)
            AND f.data = v_dia
       ) THEN
      RETURN v_dia;
    END IF;
    v_dia := v_dia + 1;
    v_i := v_i + 1;
  END LOOP;
  RETURN v_dia;
END $fn$;

CREATE OR REPLACE FUNCTION public.trg_cat_pendencia_prazo()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE v_inicio date;
BEGIN
  IF lower(COALESCE(NEW.tipo_pendencia,'')) = 'cat' AND NEW.prazo IS NULL THEN
    SELECT data_inicio INTO v_inicio FROM public.afastamentos WHERE id = NEW.afastamento_id;
    IF v_inicio IS NOT NULL THEN
      NEW.prazo := public.afastamento_proximo_dia_util(NEW.tenant_id, v_inicio);
    END IF;
  END IF;
  RETURN NEW;
END $fn$;

DROP TRIGGER IF EXISTS cat_pendencia_prazo ON public.afastamentos_pendencias;
CREATE TRIGGER cat_pendencia_prazo
  BEFORE INSERT OR UPDATE OF tipo_pendencia, prazo, afastamento_id
  ON public.afastamentos_pendencias
  FOR EACH ROW EXECUTE FUNCTION public.trg_cat_pendencia_prazo();

-- Backfill: pendencias de CAT existentes sem prazo
UPDATE public.afastamentos_pendencias p
   SET prazo = public.afastamento_proximo_dia_util(p.tenant_id, a.data_inicio),
       updated_at = now()
  FROM public.afastamentos a
 WHERE p.afastamento_id = a.id
   AND lower(COALESCE(p.tipo_pendencia,'')) = 'cat'
   AND p.prazo IS NULL
   AND a.data_inicio IS NOT NULL;
