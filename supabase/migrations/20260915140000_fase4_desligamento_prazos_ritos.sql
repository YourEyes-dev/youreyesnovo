-- ============================================================================
-- Fase 4 (motores) — Desligamento: prazos e ritos.
--
-- DESL-015: conferência do pagamento da rescisão contra o art. 477 (10 dias,
--           antecipação por dia não útil, multa do §8º projetada).
-- DESL-025: registro da validação jurídica do enquadramento da justa causa.
-- DESL-093: prazo projetado e vigiado do S-2299 (mín(pagamento, término+10)).
-- DESL-105: rescisão complementar como registro próprio (tipo + rescisão-mãe).
-- DESL-106: reversão de desligamento exige rito (justificativa/aprovação);
--           UPDATE cru que apaga o desligamento é bloqueado.
-- ============================================================================

-- ── DESL-025: validação jurídica da justa causa ─────────────────────────────
ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS desligamento_validacao_juridica_por uuid;
ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS desligamento_validacao_juridica_em timestamptz;
ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS desligamento_validacao_evidencias text;

COMMENT ON COLUMN public.admissoes.desligamento_validacao_juridica_por IS
  'DESL-025: quem (perfil juridico) validou o enquadramento da justa causa (art. 482).';

-- ── DESL-106: reversão de desligamento só por rito ──────────────────────────
ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS reversao_desligamento_justificativa text;
ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS reversao_desligamento_aprovada_por uuid;

COMMENT ON COLUMN public.admissoes.reversao_desligamento_justificativa IS
  'DESL-106: motivo da reversao do desligamento (rito com dupla aprovacao, estorno e tratamento do eSocial).';

CREATE OR REPLACE FUNCTION public.admissao_bloqueia_reversao_desligamento()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  -- Sair de 'desligado' de volta para ativo/concluído é reversão: exige rito.
  -- Sem justificativa registrada, o UPDATE cru que apaga o desligamento é barrado.
  IF OLD.status::text = 'desligado'
     AND NEW.status::text <> 'desligado'
     AND COALESCE(NEW.reversao_desligamento_justificativa, '') = '' THEN
    RAISE EXCEPTION
      'Reversao de desligamento exige rito (motivo, aprovacao, estorno e tratamento do S-2299). Registre a justificativa da reversao.'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_admissao_bloqueia_reversao_desligamento ON public.admissoes;
CREATE TRIGGER trg_admissao_bloqueia_reversao_desligamento
  BEFORE UPDATE OF status ON public.admissoes
  FOR EACH ROW EXECUTE FUNCTION public.admissao_bloqueia_reversao_desligamento();

-- ── DESL-105: rescisão complementar ─────────────────────────────────────────
-- (tipo_rescisao já existe como enum do MOTIVO da rescisão — não é aqui. Aqui
-- marcamos a NATUREZA original × complementar e o vínculo à rescisão-mãe.)
ALTER TABLE public.folha_rescisoes
  ADD COLUMN IF NOT EXISTS rescisao_complementar boolean NOT NULL DEFAULT false;
ALTER TABLE public.folha_rescisoes
  ADD COLUMN IF NOT EXISTS rescisao_origem_id uuid;

COMMENT ON COLUMN public.folha_rescisoes.rescisao_complementar IS
  'DESL-105: true quando a rescisao é complementar (dissidio/reajuste retroativo).';
COMMENT ON COLUMN public.folha_rescisoes.rescisao_origem_id IS
  'DESL-105: referencia a rescisao-mae quando complementar.';

-- ── DESL-015: conferência do prazo do art. 477 e da multa do §8º ────────────
-- Antecipação: se o 10º dia cair em fim de semana/feriado, a data-limite é o
-- dia útil ANTERIOR (o pagamento não pode atrasar por conta do calendário).
CREATE OR REPLACE FUNCTION public.rescisao_dia_util_anterior(
  p_tenant uuid,
  p_data   date
) RETURNS date
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
DECLARE v_dia date := p_data; v_i int := 0;
BEGIN
  WHILE v_i < 15 LOOP
    IF EXTRACT(DOW FROM v_dia) NOT IN (0, 6)
       AND NOT EXISTS (SELECT 1 FROM public.feriados f
                        WHERE f.ativo AND (f.tenant_id = p_tenant OR f.tenant_id IS NULL)
                          AND f.data = v_dia) THEN
      RETURN v_dia;
    END IF;
    v_dia := v_dia - 1; v_i := v_i + 1;
  END LOOP;
  RETURN v_dia;
END;
$$;

CREATE OR REPLACE FUNCTION public.rescisao_confere_prazo_477(p_rescisao_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  fr        public.folha_rescisoes%ROWTYPE;
  v_limite  date;
  v_salario numeric;
  v_atraso  boolean;
BEGIN
  SELECT * INTO fr FROM public.folha_rescisoes WHERE id = p_rescisao_id;
  IF NOT FOUND THEN RETURN NULL; END IF;

  -- Art. 477, §6º: pagamento das verbas rescisórias em até 10 dias do término.
  v_limite := public.rescisao_dia_util_anterior(fr.tenant_id, fr.data_desligamento + 10);

  -- Salário base para a multa do §8º (um salário ao empregado, em atraso).
  SELECT a.salario INTO v_salario
    FROM public.admissoes a WHERE a.id = fr.admissao_id;

  v_atraso := fr.data_pagamento IS NOT NULL AND fr.data_pagamento > v_limite;

  RETURN jsonb_build_object(
    'data_limite', v_limite,
    'data_pagamento', fr.data_pagamento,
    'em_atraso', COALESCE(v_atraso, false),
    'multa_477_paragrafo_8', CASE WHEN COALESCE(v_atraso, false)
                                  THEN COALESCE(v_salario, 0) ELSE 0 END
  );
END;
$$;

COMMENT ON FUNCTION public.rescisao_confere_prazo_477(uuid) IS
  'DESL-015: confere o pagamento da rescisao contra o prazo do art. 477 e projeta a multa do §8º.';

-- ── DESL-093: prazo projetado do S-2299 (desligamento) ──────────────────────
ALTER TABLE public.esocial_transmissoes
  ADD COLUMN IF NOT EXISTS data_limite date;

COMMENT ON COLUMN public.esocial_transmissoes.data_limite IS
  'DESL-093: data-limite do evento (S-2299: min(pagamento, termino+10 dias)).';

CREATE OR REPLACE FUNCTION public.esocial_s2299_prazo(
  p_data_desligamento date,
  p_data_pagamento    date
) RETURNS date
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $$
  -- S-2299 (desligamento): ate 10 dias do desligamento, ANTECIPADO se o
  -- pagamento das verbas vier antes — vence o primeiro dos dois relogios.
  SELECT LEAST(
    p_data_desligamento + 10,
    COALESCE(p_data_pagamento, p_data_desligamento + 10)
  );
$$;

COMMENT ON FUNCTION public.esocial_s2299_prazo(date, date) IS
  'DESL-093: prazo do S-2299 = min(pagamento, termino + 10 dias).';
