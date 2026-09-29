-- ============================================================================
-- ENTREGA — DESLIGAMENTO · PARTE 1/2 (tabela admissoes) — PRODUÇÃO
--
-- Divisão em duas partes para isolar a tabela MAIS MOVIMENTADA (admissoes) numa
-- transação só sua — nenhuma outra tabela é travada junto, então não há ciclo de
-- lock cruzado com o tráfego (a causa do deadlock que vimos no FOLHA). Cole a
-- PARTE 1, confira as linhas 'ok', depois a PARTE 2.
--
-- Conteúdo idêntico ao já validado na homologação — só reparticionado por tabela.
-- Cobre desta parte: DESL-065 (colunas de dispensa do exame + CHECK + carimbo)
--        e DESL-025 (colunas da validação jurídica da justa causa).
--
-- SEGURANÇA: só ALTER ADD COLUMN, CHECK (NOT VALID) e TRIGGER em admissoes. Não
-- cria tabela nem altera dado (colunas nascem NULL/false). A CHECK é NOT VALID
-- (as linhas existentes já satisfazem por causa do default false; evita
-- varredura sob ACCESS EXCLUSIVE). Gatilho por último. lock_timeout curto.
-- Idempotente. Se der "deadlock detected", rode de novo.
-- ============================================================================

SET lock_timeout = '10s';

-- ── Colunas em admissoes (DESL-065 + DESL-025) ──────────────────────────────
ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS exame_demissional_dispensado boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS exame_demissional_dispensa_motivo text,
  ADD COLUMN IF NOT EXISTS exame_demissional_dispensa_registrada_em timestamptz,
  ADD COLUMN IF NOT EXISTS exame_demissional_dispensa_registrada_por uuid,
  ADD COLUMN IF NOT EXISTS desligamento_validacao_juridica_por uuid,
  ADD COLUMN IF NOT EXISTS desligamento_validacao_juridica_em timestamptz,
  ADD COLUMN IF NOT EXISTS desligamento_validacao_evidencias text;

COMMENT ON COLUMN public.admissoes.exame_demissional_dispensa_motivo IS
  'DESL-065: justificativa documentada da dispensa do exame demissional (NR-07).';
COMMENT ON COLUMN public.admissoes.desligamento_validacao_juridica_por IS
  'DESL-025: quem (perfil juridico) validou o enquadramento da justa causa (art. 482).';

-- DESL-065: dispensa sem motivo é dispensa sem defesa. CHECK como NOT VALID.
ALTER TABLE public.admissoes
  DROP CONSTRAINT IF EXISTS chk_exame_demissional_dispensa_motivada;
ALTER TABLE public.admissoes
  ADD CONSTRAINT chk_exame_demissional_dispensa_motivada
  CHECK (
    exame_demissional_dispensado = false
    OR COALESCE(btrim(exame_demissional_dispensa_motivo), '') <> ''
  ) NOT VALID;

-- DESL-065: carimba quem/quando registrou a dispensa do exame.
CREATE OR REPLACE FUNCTION public.admissao_carimbar_dispensa_exame()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.exame_demissional_dispensado
     AND (TG_OP = 'INSERT' OR NOT COALESCE(OLD.exame_demissional_dispensado, false)) THEN
    NEW.exame_demissional_dispensa_registrada_em  := now();
    NEW.exame_demissional_dispensa_registrada_por := auth.uid();
  END IF;
  RETURN NEW;
END;
$$;

-- Gatilho por ÚLTIMO (tabela quente).
DROP TRIGGER IF EXISTS trg_admissao_dispensa_exame ON public.admissoes;
CREATE TRIGGER trg_admissao_dispensa_exame
  BEFORE INSERT OR UPDATE OF exame_demissional_dispensado ON public.admissoes
  FOR EACH ROW EXECUTE FUNCTION public.admissao_carimbar_dispensa_exame();


-- ════════════════════ CONFERÊNCIA PARTE 1 (esperado tudo 'ok') ════════════════
WITH alvo(item, presente) AS (
  VALUES
    ('DESL-065 · coluna de dispensa do exame',
       EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='admissoes' AND column_name='exame_demissional_dispensado')),
    ('DESL-065 · CHECK dispensa exige motivo',
       EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_exame_demissional_dispensa_motivada' AND conrelid='public.admissoes'::regclass)),
    ('DESL-065 · carimbo da dispensa (gatilho)',
       EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_admissao_dispensa_exame' AND NOT tgisinternal)),
    ('DESL-025 · validação jurídica da justa causa (colunas)',
       EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='admissoes' AND column_name='desligamento_validacao_juridica_por'))
)
SELECT item, CASE WHEN presente THEN 'ok' ELSE 'FALTOU' END AS situacao FROM alvo ORDER BY item;
