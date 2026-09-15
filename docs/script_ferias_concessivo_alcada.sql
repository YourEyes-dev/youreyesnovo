-- ============================================================================
-- ENTREGA — Ferias: limite concessivo (art. 134) com alcada de diretoria e
-- dobra (art. 137)  [FERIAS-020]
--
-- Colar INTEIRO no SQL Editor (homologacao e, depois de aprovado, producao).
--
-- O QUE MUDA
--   Programar o inicio do gozo ALEM do limite concessivo (aquisitivo_fim + 12
--   meses) passa a ser BLOQUEADO. So a diretoria (admin ou acima) autoriza a
--   excecao, de forma explicita e com trilha (quem/quando). A tela exibe o
--   custo da dobra (art. 137) antes de confirmar.
--     1) colunas autorizado_excecao / autorizado_por / autorizado_em /
--        autorizado_motivo em ferias_programacao;
--     2) CHECK ferias_prog_concessivo (bloqueia sem autorizacao);
--     3) trigger que so deixa admin+ ligar a excecao e carimba autor/data;
--     4) helper ferias_concessivo_avalia() para a tela (vencido/limite/dias).
--
-- SEGURANCA DO DADO
--   So CRIA/ALTERA estrutura (colunas IF NOT EXISTS, constraint, trigger,
--   funcao). Nao altera nem apaga nenhuma LINHA existente -> nao ha copia de
--   seguranca a fazer. Idempotente: rodar duas vezes nao quebra nem duplica.
--   A CHECK entra como NOT VALID: nao rejeita programacoes historicas ja
--   gravadas; passa a valer para o que entrar de agora em diante.
--
-- PROVADO em replica local: perfil comum e nao-admin bloqueados; dentro do
--   concessivo e admin com autorizacao aceitos, com a trilha carimbada.
--
-- Decisoes do dono do produto (14/09/2026): alcada = admin ou acima;
--   comportamento = bloquear + exigir autorizacao explicita.
--
-- A TELA (aviso da dobra + controle de autorizacao) so muda apos Publicar no
-- Lovable.
-- ============================================================================

SET lock_timeout = '10s';

-- ── 1. Colunas de autorizacao e trilha ────────────────────────────────────
ALTER TABLE public.ferias_programacao
    ADD COLUMN IF NOT EXISTS autorizado_excecao BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS autorizado_por     UUID,
    ADD COLUMN IF NOT EXISTS autorizado_em      TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS autorizado_motivo  TEXT;

-- ── 2. Trava do concessivo (art. 134) — NOT VALID (nao mexe no historico) ──
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

-- ── 3. So admin+ liga a excecao; carimba autor/data ───────────────────────
CREATE OR REPLACE FUNCTION public.ferias_prog_autoriza_excecao()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE v_uid UUID := auth.uid();
BEGIN
    IF COALESCE(NEW.autorizado_excecao, false) = false THEN
        NEW.autorizado_por := NULL;
        NEW.autorizado_em  := NULL;
        RETURN NEW;
    END IF;

    IF v_uid IS NOT NULL AND NOT public.has_minimum_role(v_uid, 'admin') THEN
        RAISE EXCEPTION 'Autorizar ferias alem do concessivo exige alcada de diretoria (admin ou acima).'
            USING ERRCODE = 'check_violation';
    END IF;

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
            AND p_inicio_gozo > (p_aquisitivo_fim + INTERVAL '12 months')::date)   AS vencido,
        (p_aquisitivo_fim + INTERVAL '12 months')::date                             AS limite,
        GREATEST(0, (p_inicio_gozo - (p_aquisitivo_fim + INTERVAL '12 months')::date))::int AS dias_alem;
$fn$;

GRANT EXECUTE ON FUNCTION public.ferias_concessivo_avalia(DATE, DATE) TO authenticated;

-- ── 5. Conferencia final ──────────────────────────────────────────────────
SELECT
    (SELECT count(*) FROM information_schema.columns
       WHERE table_name = 'ferias_programacao' AND column_name = 'autorizado_excecao')  AS coluna_autoriza,
    (SELECT count(*) FROM pg_constraint WHERE conname = 'ferias_prog_concessivo')        AS trava_concessivo,
    (to_regproc('public.ferias_concessivo_avalia') IS NOT NULL)                          AS helper_dobra,
    (SELECT situacao FROM public.qa_caso_ferias_020())                                    AS qa_020;
