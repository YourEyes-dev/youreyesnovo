-- ============================================================================
-- ENTREGA — DESLIGAMENTO (prazos, exame demissional e ritos) na HOMOLOGAÇÃO
--            (fila de porte)
--
-- Cole INTEIRO no SQL Editor da HOMOLOGAÇÃO; depois de conferido, o MESMO na
-- PRODUÇÃO. Estes motores já estão verdes no teste (aplicados por migration) e
-- ainda não haviam sido colados aqui.
--
-- Cobre (só o que ainda faltava portar):
--   DESL-065 · exame demissional (NR-07 7.5.11): registro da dispensa com motivo,
--             carimbo de quem/quando dispensou, e a função de pendências que
--             classifica cada desligamento (em_dia / vencido / fora do prazo).
--   DESL-025 · validação jurídica do enquadramento da justa causa (art. 482).
--   DESL-105 · rescisão complementar como registro próprio (natureza + mãe).
--   DESL-015 · conferência do pagamento contra o art. 477 (10 dias, antecipação
--             por dia não útil, multa do §8º projetada).
--   DESL-093 · prazo projetado do S-2299 = mín(pagamento, término+10).
--
-- JÁ PORTADOS antes (NÃO repetidos aqui): DESL-003 (dispensa × afastamento),
--   DESL-106 (reversão com rito), DESL-035/042 (culpa recíproca), DESL-090/091/093
--   (fila do S-2299 e coluna data_limite). Este script só adiciona o que faltava.
--
-- SEGURANÇA:
--   • NÃO cria tabela nova (auto-RLS do editor não liga); NÃO apaga dado. As
--     colunas novas nascem NULL ou com default (a de exame nasce false → a CHECK
--     é satisfeita por todas as linhas existentes).
--   • admissoes é a tabela mais movimentada. A CHECK entra como NOT VALID (valida
--     linhas novas/alteradas daqui em diante; as existentes já satisfazem por
--     causa do default), evitando varredura sob ACCESS EXCLUSIVE. lock_timeout
--     curto. O gatilho em admissoes é criado por ÚLTIMO.
--   • Se aparecer "deadlock detected" (disputa de lock com o tráfego), basta
--     rodar o script de novo — ele é idempotente. (Aconteceu com o FOLHA;
--     limpou na segunda passada.)
--   • Idempotente, roda numa transação.
--
-- Origem: migrations 20260804153000 (DESL-065) e 20260915140000 (prazos/ritos,
--   sem o bloco de reversão/DESL-106, já entregue). Ao fim, conferência única —
--   esperado tudo 'ok'.
-- ============================================================================

SET lock_timeout = '10s';

-- ══════════════ Colunas em admissoes (DESL-065 + DESL-025) ═══════════════════
-- Agrupadas para tomar o lock de admissoes uma vez só. Todos os ADD COLUMN são
-- metadata-only (o default constante não reescreve a tabela no PG11+).
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

-- DESL-065: dispensa sem motivo é dispensa sem defesa. CHECK como NOT VALID —
-- as linhas existentes já satisfazem (dispensado=false por default); só as
-- novas/alteradas são conferidas daqui em diante, sem varredura pesada.
ALTER TABLE public.admissoes
  DROP CONSTRAINT IF EXISTS chk_exame_demissional_dispensa_motivada;
ALTER TABLE public.admissoes
  ADD CONSTRAINT chk_exame_demissional_dispensa_motivada
  CHECK (
    exame_demissional_dispensado = false
    OR COALESCE(btrim(exame_demissional_dispensa_motivo), '') <> ''
  ) NOT VALID;

-- ══════════════ Colunas em folha_rescisoes (DESL-105) ════════════════════════
ALTER TABLE public.folha_rescisoes
  ADD COLUMN IF NOT EXISTS rescisao_complementar boolean NOT NULL DEFAULT false;
ALTER TABLE public.folha_rescisoes
  ADD COLUMN IF NOT EXISTS rescisao_origem_id uuid;

COMMENT ON COLUMN public.folha_rescisoes.rescisao_complementar IS
  'DESL-105: true quando a rescisao é complementar (dissidio/reajuste retroativo).';
COMMENT ON COLUMN public.folha_rescisoes.rescisao_origem_id IS
  'DESL-105: referencia a rescisao-mae quando complementar.';

-- ══════════════ Coluna em esocial_transmissoes (DESL-093) ════════════════════
-- (Já entregue com o S-2299; ADD IF NOT EXISTS aqui é no-op se já existir.)
ALTER TABLE public.esocial_transmissoes
  ADD COLUMN IF NOT EXISTS data_limite date;

COMMENT ON COLUMN public.esocial_transmissoes.data_limite IS
  'DESL-093: data-limite do evento (S-2299: min(pagamento, termino+10 dias)).';

-- ══════════════ Funções ══════════════════════════════════════════════════════

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

-- DESL-065: pendências de exame demissional (uma linha por desligamento que
-- ainda deve exame, já classificada) — alimenta painel, alerta e conferência.
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

-- DESL-015: se o 10º dia cair em fim de semana/feriado, a data-limite é o dia
-- útil ANTERIOR (o pagamento não pode atrasar por conta do calendário).
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

-- DESL-015: confere o pagamento da rescisão contra o art. 477 e projeta a
-- multa do §8º.
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

-- DESL-093: prazo do S-2299 = min(pagamento, término + 10 dias).
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

-- ══════════════ Gatilho em admissoes (por ÚLTIMO, tabela quente) ═════════════
DROP TRIGGER IF EXISTS trg_admissao_dispensa_exame ON public.admissoes;
CREATE TRIGGER trg_admissao_dispensa_exame
  BEFORE INSERT OR UPDATE OF exame_demissional_dispensado ON public.admissoes
  FOR EACH ROW EXECUTE FUNCTION public.admissao_carimbar_dispensa_exame();


-- ════════════════════ CONFERÊNCIA (única — esperado tudo 'ok') ════════════════
WITH alvo(item, presente) AS (
  VALUES
    ('DESL-065 · coluna de dispensa do exame',
       EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='admissoes' AND column_name='exame_demissional_dispensado')),
    ('DESL-065 · CHECK dispensa exige motivo',
       EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_exame_demissional_dispensa_motivada' AND conrelid='public.admissoes'::regclass)),
    ('DESL-065 · carimbo da dispensa (gatilho)',
       EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_admissao_dispensa_exame' AND NOT tgisinternal)),
    ('DESL-065 · função de pendências do exame',
       (to_regprocedure('public.exame_demissional_pendencias(uuid,uuid)') IS NOT NULL)),
    ('DESL-025 · validação jurídica da justa causa (colunas)',
       EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='admissoes' AND column_name='desligamento_validacao_juridica_por')),
    ('DESL-105 · rescisão complementar (colunas)',
       (EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='folha_rescisoes' AND column_name='rescisao_complementar')
        AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='folha_rescisoes' AND column_name='rescisao_origem_id'))),
    ('DESL-015 · dia útil anterior (antecipação)',
       (to_regprocedure('public.rescisao_dia_util_anterior(uuid,date)') IS NOT NULL)),
    ('DESL-015 · conferência do prazo do art. 477',
       (to_regprocedure('public.rescisao_confere_prazo_477(uuid)') IS NOT NULL)),
    ('DESL-093 · data-limite do S-2299 (coluna)',
       EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='esocial_transmissoes' AND column_name='data_limite')),
    ('DESL-093 · prazo do S-2299 (função)',
       (to_regprocedure('public.esocial_s2299_prazo(date,date)') IS NOT NULL))
)
SELECT item, CASE WHEN presente THEN 'ok' ELSE 'FALTOU' END AS situacao FROM alvo ORDER BY item;
