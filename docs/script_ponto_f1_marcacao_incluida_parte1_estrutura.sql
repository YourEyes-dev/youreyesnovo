-- ============================================================================
-- SCRIPT DE ENTREGA (PRODUÇÃO) — F1 PARTE 1 de 2: estrutura
-- Marcação incluída por ajuste nasce identificada (A) e ligada ao ajuste.
-- Cria a coluna ponto_marcacoes.ajuste_id (+ índice) e corrige o gatilho de
-- origem. NÃO altera dados (isso é a parte 2). Idempotente.
-- Rodar a parte 1, conferir, e só então a parte 2.
-- ============================================================================

SET lock_timeout = '10s';

ALTER TABLE public.ponto_marcacoes ADD COLUMN IF NOT EXISTS ajuste_id uuid;
CREATE INDEX IF NOT EXISTS idx_ponto_marcacoes_ajuste_id
  ON public.ponto_marcacoes (ajuste_id) WHERE ajuste_id IS NOT NULL;
COMMENT ON COLUMN public.ponto_marcacoes.ajuste_id IS
  'Ajuste de ponto (ponto_ajustes.id) que originou esta marcação incluída. NULL = batida original.';

CREATE OR REPLACE FUNCTION public.ponto_marcacoes_origem_sync()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF NEW.origem_marcacao IS NULL THEN
    NEW.origem_marcacao := CASE WHEN COALESCE(NEW.marcacao_original, true) THEN 'O' ELSE 'A' END;
  END IF;

  IF TG_OP = 'INSERT' THEN
    -- O DEFAULT 'O' chega antes do gatilho: marcação não original nasce 'A'.
    IF COALESCE(NEW.marcacao_original, true) IS FALSE AND NEW.origem_marcacao = 'O' THEN
      NEW.origem_marcacao := 'A';
    END IF;
    -- Liga ao ajuste antes de trigger_gerar_hash_marcacao sobrescrever o hash.
    IF NEW.ajuste_id IS NULL AND COALESCE(NEW.hash_marcacao, '') ~ '^AJUSTE-[0-9a-fA-F-]{36}' THEN
      NEW.ajuste_id := substring(NEW.hash_marcacao FROM 8 FOR 36)::uuid;
    END IF;
  END IF;

  IF TG_OP = 'UPDATE' AND COALESCE(OLD.marcacao_original, true) IS TRUE
     AND COALESCE(NEW.marcacao_original, true) IS FALSE
     AND NEW.origem_marcacao = 'O' THEN
    NEW.origem_marcacao := 'A';
  END IF;
  RETURN NEW;
END;
$$;

-- Conferência
SELECT json_build_object(
  'coluna_ajuste_id', EXISTS (SELECT 1 FROM information_schema.columns
                              WHERE table_schema='public' AND table_name='ponto_marcacoes' AND column_name='ajuste_id'),
  'gatilho_corrigido', position('ajuste_id' IN pg_get_functiondef('public.ponto_marcacoes_origem_sync()'::regprocedure)) > 0,
  'nao_originais_rotuladas_O_hoje', (SELECT count(*) FROM public.ponto_marcacoes WHERE marcacao_original IS FALSE AND origem_marcacao = 'O')
) AS resultado;
