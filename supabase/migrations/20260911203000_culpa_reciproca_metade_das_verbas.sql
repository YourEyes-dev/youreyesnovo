-- =========================================================
-- Culpa recíproca: o motivo que faltava, e a metade que a lei manda
--
-- ACHADO (caso DEC13-061): "culpa reciproca nao existe como motivo de
-- rescisao". Sem ele, quem opera o desligamento tem duas saídas erradas:
-- lançar como justa causa (paga ZERO — a empresa fica devedora) ou como
-- dispensa comum (paga INTEIRO — a empresa perde dinheiro).
--
-- O que a lei diz: reconhecida a culpa recíproca, as verbas devidas na
-- dispensa sem justa causa são pagas pela METADE (CLT, art. 484; Súmula
-- 14 do TST). Alcança aviso prévio, 13º proporcional, férias
-- proporcionais e a multa do FGTS (40% viram 20%). Saldo de salário e
-- férias VENCIDAS não entram na metade: são direito já adquirido.
--
-- ESTA MIGRATION:
--   1. acrescenta CULPA_RECIPROCA ao vocabulário de motivos;
--   2. aplica a metade no 13º da rescisão, com o fundamento na memória;
--   3. ensina a trava da justa causa a reconhecer o motivo novo — ela
--      passa a recusar também o 13º INTEIRO na culpa recíproca, que é o
--      outro jeito de errar.
--
-- As comparações são feitas por TEXTO de propósito: valor novo de
-- vocabulário não pode ser usado como literal na mesma transação em que
-- é criado, e o script de entrega roda tudo de uma vez só.
--
-- Requisitos YE-DP-13-001: RN-009. Casos: DEC13-061 (13º) e DESL-035
-- (aviso prévio, já documentado na família de Desligamento).
-- =========================================================

SET lock_timeout = '10s';

ALTER TYPE public.rescisao_tipo ADD VALUE IF NOT EXISTS 'CULPA_RECIPROCA';

-- ── 13º da rescisão: metade na culpa recíproca ────────────────────────
CREATE OR REPLACE FUNCTION public.decimo_terceiro_da_rescisao(
    p_rescisao UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    r         public.folha_rescisoes;
    v_ano     INT;
    v_ap      JSONB;
    v_avos    INT;
    v_base    NUMERIC(12,2);
    v_devido  NUMERIC(12,2);
    v_integral NUMERIC(12,2);
    v_pago    NUMERIC(12,2) := 0;
    v_perde   BOOLEAN := false;
    v_metade  BOOLEAN := false;
BEGIN
    SELECT * INTO r FROM public.folha_rescisoes WHERE id = p_rescisao;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('erro', 'Rescisão não encontrada.');
    END IF;

    v_ano    := extract(year FROM r.data_desligamento)::INT;
    v_perde  := (r.tipo_rescisao::text = 'DISPENSA_COM_JUSTA_CAUSA');
    v_metade := (r.tipo_rescisao::text = 'CULPA_RECIPROCA');

    v_ap   := public.decimo_terceiro_apurar(r.tenant_id, r.colaborador_cpf, v_ano, NULL, NULL);
    v_avos := COALESCE((v_ap->>'avos')::INT, 0);
    v_base := COALESCE((v_ap->>'base_integral')::NUMERIC, 0);

    v_integral := round(v_base * v_avos / 12.0, 2);
    v_devido := CASE WHEN v_perde  THEN 0
                     WHEN v_metade THEN round(v_integral / 2, 2)
                     ELSE v_integral END;

    -- Adiantamento já pago no ano (inclusive o das férias): abate.
    SELECT COALESCE(sum(c.total_liquido), 0) INTO v_pago
      FROM public.folha_13_calculo c
     WHERE c.tenant_id = r.tenant_id
       AND c.ano = v_ano
       AND c.status = 'pago'
       AND regexp_replace(COALESCE(c.colaborador_cpf,''), '[^0-9]', '', 'g')
           = regexp_replace(COALESCE(r.colaborador_cpf,''), '[^0-9]', '', 'g');

    RETURN jsonb_build_object(
        'rescisao_id',   r.id,
        'ano',           v_ano,
        'tipo_rescisao', r.tipo_rescisao,
        'perde_por_justa_causa', v_perde,
        'metade_por_culpa_reciproca', v_metade,
        'avos',          v_avos,
        'base',          v_base,
        'devido_integral', v_integral,
        'devido',        v_devido,
        'ja_pago_no_ano', v_pago,
        'a_pagar_na_rescisao', greatest(round(v_devido - v_pago, 2), 0),
        'a_descontar',   CASE WHEN v_pago > v_devido
                              THEN round(v_pago - v_devido, 2) ELSE 0 END,
        'fundamento', CASE
            WHEN v_perde
              THEN 'Justa causa: perde o 13o proporcional (Lei 4.090/1962).'
            WHEN v_metade
              THEN 'Culpa reciproca: metade do 13o proporcional (CLT, art. 484; Sumula 14 do TST). Integral seria R$ '
                   || to_char(v_integral, 'FM999999990.00') || '.'
            ELSE 'Rescisao no ano-base: 13o proporcional aos avos, deduzido o adiantamento ja pago.' END,
        'memoria', v_ap,
        'apurado_em', now());
END $fn$;

COMMENT ON FUNCTION public.decimo_terceiro_da_rescisao(UUID) IS
    'Apura o 13o proporcional que cabe numa rescisao pelo motivo (justa causa perde; culpa reciproca paga metade, CLT art. 484 e Sumula 14 do TST), deduz o adiantamento ja pago no ano e devolve a memoria.';

GRANT EXECUTE ON FUNCTION public.decimo_terceiro_da_rescisao(UUID) TO authenticated;

-- ── A trava passa a cobrir os dois jeitos de errar ────────────────────
CREATE OR REPLACE FUNCTION public.decimo_terceiro_rescisao_valida()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $tg$
DECLARE
    v_ap       JSONB;
    v_integral NUMERIC(12,2);
BEGIN
    -- Justa causa nao gera 13o proporcional (Lei 4.090/1962).
    IF NEW.tipo_rescisao::text = 'DISPENSA_COM_JUSTA_CAUSA'
       AND COALESCE(NEW.decimo_terceiro_proporcional, 0) > 0 THEN
        RAISE EXCEPTION 'Dispensa por justa causa não gera 13º proporcional (Lei 4.090/1962). Valor informado: R$ %. Se o caso for culpa recíproca, use o motivo "Culpa Recíproca", que paga metade (CLT, art. 484; Súmula 14 do TST).',
            to_char(NEW.decimo_terceiro_proporcional, 'FM999999990.00');
    END IF;

    -- Culpa reciproca paga METADE: o valor inteiro tambem e recusado,
    -- porque pagar a mais aqui e dinheiro que nao volta.
    IF NEW.tipo_rescisao::text = 'CULPA_RECIPROCA'
       AND COALESCE(NEW.decimo_terceiro_proporcional, 0) > 0
       AND NEW.colaborador_cpf IS NOT NULL THEN
        v_ap := public.decimo_terceiro_apurar(NEW.tenant_id, NEW.colaborador_cpf,
                    extract(year FROM NEW.data_desligamento)::INT, NULL, NULL);
        v_integral := round(COALESCE((v_ap->>'base_integral')::NUMERIC, 0)
                          * COALESCE((v_ap->>'avos')::INT, 0) / 12.0, 2);
        IF v_integral > 0
           AND NEW.decimo_terceiro_proporcional > round(v_integral / 2, 2) + 0.02 THEN
            RAISE EXCEPTION 'Culpa recíproca paga METADE do 13º proporcional (CLT, art. 484; Súmula 14 do TST): o devido é R$ % e foi informado R$ %.',
                to_char(round(v_integral / 2, 2), 'FM999999990.00'),
                to_char(NEW.decimo_terceiro_proporcional, 'FM999999990.00');
        END IF;
    END IF;

    RETURN NEW;
END $tg$;

COMMENT ON FUNCTION public.decimo_terceiro_rescisao_valida() IS
    'Recusa 13o proporcional na justa causa (Lei 4.090/1962) e valor acima da metade na culpa reciproca (CLT art. 484; Sumula 14 do TST).';
