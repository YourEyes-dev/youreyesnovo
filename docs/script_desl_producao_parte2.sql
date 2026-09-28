-- ============================================================================
-- ENTREGA — DESLIGAMENTO · PARTE 2/2 (rescisões + eSocial + funções) — PRODUÇÃO
--
-- Rode SÓ DEPOIS da PARTE 1 (conferida, tudo 'ok') — a função de pendências
-- lê as colunas de exame que a PARTE 1 adiciona em admissoes. Esta parte toca
-- folha_rescisoes e esocial_transmissoes (só ADD COLUMN rápido) e cria as
-- funções de prazo/pendência; não põe gatilho em tabela quente.
--
-- Cobre desta parte: DESL-105 (colunas da rescisão complementar), DESL-093
--        (coluna data_limite + função de prazo do S-2299), DESL-015 (dia útil
--        anterior + conferência do art. 477), DESL-065 (função de pendências).
--
-- SEGURANÇA: só ALTER ADD COLUMN e CREATE FUNCTION. Não cria tabela nem altera
-- dado. Idempotente. lock_timeout curto.
-- ============================================================================

SET lock_timeout = '10s';

-- ── DESL-105: rescisão complementar (folha_rescisoes) ───────────────────────
ALTER TABLE public.folha_rescisoes
  ADD COLUMN IF NOT EXISTS rescisao_complementar boolean NOT NULL DEFAULT false;
ALTER TABLE public.folha_rescisoes
  ADD COLUMN IF NOT EXISTS rescisao_origem_id uuid;

COMMENT ON COLUMN public.folha_rescisoes.rescisao_complementar IS
  'DESL-105: true quando a rescisao é complementar (dissidio/reajuste retroativo).';
COMMENT ON COLUMN public.folha_rescisoes.rescisao_origem_id IS
  'DESL-105: referencia a rescisao-mae quando complementar.';

-- ── DESL-093: data-limite do S-2299 (esocial_transmissoes) ──────────────────
-- (Já entregue com o S-2299; ADD IF NOT EXISTS aqui é no-op se já existir.)
ALTER TABLE public.esocial_transmissoes
  ADD COLUMN IF NOT EXISTS data_limite date;

COMMENT ON COLUMN public.esocial_transmissoes.data_limite IS
  'DESL-093: data-limite do evento (S-2299: min(pagamento, termino+10 dias)).';

-- ── DESL-065: pendências de exame demissional (lê as colunas da PARTE 1) ─────
CREATE OR REPLACE FUNCTION public.exame_demissional_pendencias(
  p_tenant_id uuid,
  p_empresa_id uuid DEFAULT NULL
)
RETURNS TABLE(
  admissao_id uuid,
  colaborador_nome text,
  colaborador_cpf text,
  data_desligamento date,
  data_exame_demissional date,
  prazo_final date,
  dias_restantes int,
  situacao text
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT
    a.id,
    a.nome_completo,
    a.cpf,
    a.data_desligamento,
    a.data_exame_demissional,
    (a.data_desligamento + 10)::date AS prazo_final,
    ((a.data_desligamento + 10)::date - CURRENT_DATE)::int AS dias_restantes,
    CASE
      WHEN a.data_exame_demissional IS NOT NULL
           AND a.data_exame_demissional <= a.data_desligamento + 10 THEN 'em_dia'
      WHEN a.data_exame_demissional IS NOT NULL                     THEN 'realizado_fora_do_prazo'
      WHEN CURRENT_DATE > a.data_desligamento + 10                  THEN 'vencido'
      WHEN CURRENT_DATE >= a.data_desligamento + 7                  THEN 'vence_em_breve'
      ELSE 'no_prazo'
    END AS situacao
  FROM public.admissoes a
  WHERE a.tenant_id = p_tenant_id
    AND (p_empresa_id IS NULL OR a.empresa_id = p_empresa_id)
    AND a.status = 'desligado'
    AND a.data_desligamento IS NOT NULL
    AND COALESCE(a.exame_demissional_dispensado, false) = false
  ORDER BY (a.data_desligamento + 10);
$$;

REVOKE EXECUTE ON FUNCTION public.exame_demissional_pendencias(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.exame_demissional_pendencias(uuid, uuid) TO authenticated;

-- ── DESL-015: dia útil anterior (antecipação por fim de semana/feriado) ─────
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

-- ── DESL-015: conferência do prazo do art. 477 + multa do §8º ───────────────
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

  v_limite := public.rescisao_dia_util_anterior(fr.tenant_id, fr.data_desligamento + 10);

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

-- ── DESL-093: prazo do S-2299 = min(pagamento, término + 10 dias) ───────────
CREATE OR REPLACE FUNCTION public.esocial_s2299_prazo(
  p_data_desligamento date,
  p_data_pagamento    date
) RETURNS date
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $$
  SELECT LEAST(
    p_data_desligamento + 10,
    COALESCE(p_data_pagamento, p_data_desligamento + 10)
  );
$$;

COMMENT ON FUNCTION public.esocial_s2299_prazo(date, date) IS
  'DESL-093: prazo do S-2299 = min(pagamento, termino + 10 dias).';


-- ════════════════════ CONFERÊNCIA PARTE 2 (esperado tudo 'ok') ════════════════
WITH alvo(item, presente) AS (
  VALUES
    ('DESL-105 · rescisão complementar (colunas)',
       (EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='folha_rescisoes' AND column_name='rescisao_complementar')
        AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='folha_rescisoes' AND column_name='rescisao_origem_id'))),
    ('DESL-093 · data-limite do S-2299 (coluna)',
       EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='esocial_transmissoes' AND column_name='data_limite')),
    ('DESL-093 · prazo do S-2299 (função)',
       (to_regprocedure('public.esocial_s2299_prazo(date,date)') IS NOT NULL)),
    ('DESL-015 · dia útil anterior (antecipação)',
       (to_regprocedure('public.rescisao_dia_util_anterior(uuid,date)') IS NOT NULL)),
    ('DESL-015 · conferência do prazo do art. 477',
       (to_regprocedure('public.rescisao_confere_prazo_477(uuid)') IS NOT NULL)),
    ('DESL-065 · função de pendências do exame',
       (to_regprocedure('public.exame_demissional_pendencias(uuid,uuid)') IS NOT NULL))
)
SELECT item, CASE WHEN presente THEN 'ok' ELSE 'FALTOU' END AS situacao FROM alvo ORDER BY item;
