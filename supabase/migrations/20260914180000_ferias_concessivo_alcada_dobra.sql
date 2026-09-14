-- =========================================================
-- FERIAS-020 — Limite concessivo (art. 134) com alçada de diretoria e dobra (art. 137)
--
-- Regra: as férias devem ser concedidas nos 12 meses seguintes ao fim do
-- período aquisitivo (concessivo). Programar o INÍCIO do gozo além desse limite
-- é o gatilho da dobra (art. 137). Perfil comum fica BLOQUEADO; só admin ou
-- acima autoriza a exceção, de forma explícita e com trilha (quem/quando).
--
-- Decisões do dono do produto (14/09/2026):
--   • alçada = admin ou acima (has_minimum_role >= 'admin');
--   • comportamento = bloquear + exigir autorização explícita (não só alertar).
--
-- Implementação (padrão da casa — CHECK de linha, como ferias_prog_abono_teto):
--   1) colunas de autorização + trilha;
--   2) CHECK ferias_prog_concessivo (bloqueia sem autorização) — NOT VALID para
--      não rejeitar linhas históricas já gravadas; enforçado nas novas;
--   3) trigger que só deixa admin+ ligar a exceção e carimba autor/data;
--   4) helper ferias_concessivo_avalia() para a tela mostrar o custo da dobra.
-- =========================================================

SET lock_timeout = '10s';

-- ── 1. Colunas de autorização e trilha ────────────────────────────────────
ALTER TABLE public.ferias_programacao
    ADD COLUMN IF NOT EXISTS autorizado_excecao BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS autorizado_por     UUID,
    ADD COLUMN IF NOT EXISTS autorizado_em      TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS autorizado_motivo  TEXT;

-- ── 2. Trava do concessivo (art. 134) ─────────────────────────────────────
-- Bloqueia programar o início do gozo (p1_inicio) além de aquisitivo_fim + 12
-- meses, a menos que a exceção esteja autorizada. NOT VALID: vale para o que
-- entrar de agora em diante, sem rejeitar retroativamente o histórico.
DO $concessivo$
BEGIN
    ALTER TABLE public.ferias_programacao
        DROP CONSTRAINT IF EXISTS ferias_prog_concessivo;
    ALTER TABLE public.ferias_programacao
        ADD CONSTRAINT ferias_prog_concessivo CHECK (
            p1_inicio IS NULL
            OR p1_inicio <= (aquisitivo_fim + INTERVAL '12 months')
            OR autorizado_excecao = true
        ) NOT VALID;
    RAISE NOTICE 'Trava do concessivo (art. 134/137) aplicada.';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'ATENCAO: trava do concessivo NAO aplicada: %.', SQLERRM;
END $concessivo$;

-- ── 3. Só admin+ liga a exceção; carimba autor/data ───────────────────────
CREATE OR REPLACE FUNCTION public.ferias_prog_autoriza_excecao()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE v_uid UUID := auth.uid();
BEGIN
    -- Só interessa quando a exceção está (ou passa a estar) ligada.
    IF COALESCE(NEW.autorizado_excecao, false) = false THEN
        NEW.autorizado_por := NULL;
        NEW.autorizado_em  := NULL;
        RETURN NEW;
    END IF;

    -- Em contexto autenticado, exige alçada de diretoria (admin ou acima).
    -- Perfil comum não pode se auto-autorizar para escapar da trava.
    IF v_uid IS NOT NULL AND NOT public.has_minimum_role(v_uid, 'admin') THEN
        RAISE EXCEPTION 'Autorizar férias além do concessivo exige alçada de diretoria (admin ou acima).'
            USING ERRCODE = 'check_violation';
    END IF;

    -- Carimbo da trilha (mantém quem já veio preenchido, senão usa o usuário atual).
    NEW.autorizado_por := COALESCE(NEW.autorizado_por, v_uid);
    NEW.autorizado_em  := COALESCE(NEW.autorizado_em, now());
    RETURN NEW;
END $fn$;

DROP TRIGGER IF EXISTS trg_ferias_prog_autoriza_excecao ON public.ferias_programacao;
CREATE TRIGGER trg_ferias_prog_autoriza_excecao
BEFORE INSERT OR UPDATE ON public.ferias_programacao
FOR EACH ROW EXECUTE FUNCTION public.ferias_prog_autoriza_excecao();

-- ── 4. Helper para a tela: avalia o concessivo e o custo da dobra ─────────
CREATE OR REPLACE FUNCTION public.ferias_concessivo_avalia(
    p_aquisitivo_fim DATE, p_inicio_gozo DATE
)
RETURNS TABLE (vencido BOOLEAN, limite DATE, dias_alem INTEGER)
LANGUAGE sql
IMMUTABLE
AS $fn$
    SELECT
        (p_inicio_gozo IS NOT NULL
            AND p_inicio_gozo > (p_aquisitivo_fim + INTERVAL '12 months')::date)  AS vencido,
        (p_aquisitivo_fim + INTERVAL '12 months')::date                            AS limite,
        GREATEST(0, (p_inicio_gozo - (p_aquisitivo_fim + INTERVAL '12 months')::date))::int AS dias_alem;
$fn$;

GRANT EXECUTE ON FUNCTION public.ferias_concessivo_avalia(DATE, DATE) TO authenticated;

-- Nota: a rotina de QA FERIAS-020 (qa_caso_ferias_020) já existe e cobre o
-- bloqueio: com o concessivo vencido, o INSERT sem autorização passa a levantar
-- check_violation e o caso deixa de acusar o achado.
