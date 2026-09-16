-- =========================================================
-- 13º Salário — Entrega 2, parte 3: aprovar, pagar e reabrir com trilha
--
-- PROBLEMA: um cálculo fechado podia ser sobrescrito por um UPDATE
-- qualquer. Não havia aprovação, não havia registro de quem pagou, e
-- corrigir um valor apagava o anterior — sem motivo, sem dupla
-- aprovação e sem como reconstruir o que foi pago (RF-007, RNF-004).
--
-- ENTREGA:
--   1) decimo_terceiro_aprovar / _pagar — carimbam quem e quando;
--   2) decimo_terceiro_reabrir — NÃO altera o cálculo fechado: cancela
--      o antigo e cria um novo apontando para ele (reaberto_de), com o
--      motivo obrigatório e a diferença apurada. O histórico fica de pé;
--   3) trava de banco: cálculo aprovado ou pago não aceita mais UPDATE
--      de valor — só o caminho da reabertura mexe em dinheiro fechado.
--
-- DUPLA APROVAÇÃO: quem reabre não pode ser quem aprovou. A regra vive
-- no banco, não na tela — quem chamar por fora esbarra nela igual.
--
-- Requisitos YE-DP-13-001: RF-007, RN-009, RNF-004. Caso: DEC13-070.
-- =========================================================

SET lock_timeout = '10s';

-- ── 1. Aprovar ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.decimo_terceiro_aprovar(
    p_calculo UUID,
    p_nome    TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE r public.folha_13_calculo;
BEGIN
    SELECT * INTO r FROM public.folha_13_calculo WHERE id = p_calculo;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('erro', 'Cálculo não encontrado.');
    END IF;
    IF r.status = 'cancelado' THEN
        RETURN jsonb_build_object('erro', 'Cálculo cancelado não pode ser aprovado.');
    END IF;
    IF r.status IN ('aprovado', 'pago') THEN
        RETURN jsonb_build_object('ok', true, 'ja_estava', r.status, 'id', r.id);
    END IF;

    UPDATE public.folha_13_calculo
       SET status = 'aprovado',
           aprovado_por = auth.uid(),
           aprovado_por_nome = p_nome,
           aprovado_em = now(),
           updated_at = now()
     WHERE id = p_calculo;

    RETURN jsonb_build_object('ok', true, 'id', p_calculo, 'status', 'aprovado');
END $fn$;

-- ── 2. Pagar ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.decimo_terceiro_pagar(
    p_calculo UUID,
    p_data    DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    r public.folha_13_calculo;
    v_atraso INT;
BEGIN
    SELECT * INTO r FROM public.folha_13_calculo WHERE id = p_calculo;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('erro', 'Cálculo não encontrado.');
    END IF;
    IF r.status = 'cancelado' THEN
        RETURN jsonb_build_object('erro', 'Cálculo cancelado não pode ser pago.');
    END IF;
    IF r.status <> 'aprovado' AND r.status <> 'pago' THEN
        RETURN jsonb_build_object('erro',
            'Só se paga o que foi aprovado. Situação atual: ' || r.status);
    END IF;

    UPDATE public.folha_13_calculo
       SET status = 'pago', data_pagamento = p_data,
           pago_por = auth.uid(), pago_em = now(), updated_at = now()
     WHERE id = p_calculo;

    -- O prazo é legal (Lei 4.749): pagar depois vira multa. O sistema
    -- não impede, mas devolve o atraso para quem paga ver.
    v_atraso := CASE WHEN r.data_prevista IS NOT NULL AND p_data > r.data_prevista
                     THEN p_data - r.data_prevista ELSE 0 END;

    RETURN jsonb_build_object(
        'ok', true, 'id', p_calculo, 'status', 'pago',
        'data_pagamento', p_data, 'prazo_legal', r.data_prevista,
        'dias_de_atraso', v_atraso,
        'aviso', CASE WHEN v_atraso > 0
                      THEN format('Pagamento %s dia(s) após o prazo legal (%s) — Lei 4.749/1965.',
                                  v_atraso, r.data_prevista)
                      ELSE NULL END);
END $fn$;

-- ── 3. Reabrir: cancela e recria, nunca sobrescreve ───────────────────
CREATE OR REPLACE FUNCTION public.decimo_terceiro_reabrir(
    p_calculo UUID,
    p_motivo  TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    r      public.folha_13_calculo;
    v_c    JSONB;
    v_novo UUID;
    v_dif  NUMERIC(12,2);
BEGIN
    IF p_motivo IS NULL OR length(btrim(p_motivo)) < 10 THEN
        RETURN jsonb_build_object('erro',
            'Reabertura exige motivo escrito (ao menos 10 caracteres) — é o que fica na trilha.');
    END IF;

    SELECT * INTO r FROM public.folha_13_calculo WHERE id = p_calculo;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('erro', 'Cálculo não encontrado.');
    END IF;
    IF r.status = 'cancelado' THEN
        RETURN jsonb_build_object('erro', 'Este cálculo já foi cancelado por uma reabertura anterior.');
    END IF;

    -- Dupla aprovação: quem aprovou não reabre o próprio ato.
    IF r.aprovado_por IS NOT NULL AND auth.uid() IS NOT NULL
       AND r.aprovado_por = auth.uid() THEN
        RETURN jsonb_build_object('erro',
            'Quem aprovou este cálculo não pode reabri-lo: a reabertura exige uma segunda pessoa.');
    END IF;

    v_c := public.decimo_terceiro_calcular(
               r.tenant_id, r.colaborador_cpf, r.ano, r.parcela,
               r.empresa_id, 0, r.valor_primeira_parcela, r.tipo_vinculo);

    -- Cancela primeiro: a unicidade só admite uma parcela viva.
    UPDATE public.folha_13_calculo
       SET status = 'cancelado', observacao = COALESCE(observacao || ' | ', '') ||
           format('Cancelado por reabertura em %s: %s', now()::date, p_motivo),
           updated_at = now()
     WHERE id = p_calculo;

    INSERT INTO public.folha_13_calculo (
        tenant_id, empresa_id, admissao_id, ano, parcela,
        colaborador_id, colaborador_nome, colaborador_cpf, tipo_vinculo,
        meses_trabalhados, remuneracao_base, media_variaveis,
        valor_bruto, valor_primeira_parcela,
        base_inss, valor_inss, base_irrf, valor_irrf,
        base_fgts, valor_fgts, total_descontos, total_liquido,
        status, competencia, data_prevista,
        reaberto_de, reabertura_motivo,
        avos_origem, media_origem, memoria_calculo)
    VALUES (
        r.tenant_id, r.empresa_id, r.admissao_id, r.ano, r.parcela,
        r.colaborador_id, r.colaborador_nome, r.colaborador_cpf, r.tipo_vinculo,
        (v_c->>'avos')::INT,
        (v_c->>'remuneracao_base')::NUMERIC, (v_c->>'media_variaveis')::NUMERIC,
        (v_c->>'valor_bruto')::NUMERIC, (v_c->>'valor_primeira_parcela')::NUMERIC,
        (v_c->>'base_inss')::NUMERIC, (v_c->>'valor_inss')::NUMERIC,
        (v_c->>'base_irrf')::NUMERIC, (v_c->>'valor_irrf')::NUMERIC,
        (v_c->>'base_fgts')::NUMERIC, (v_c->>'valor_fgts')::NUMERIC,
        (v_c->>'total_descontos')::NUMERIC, (v_c->>'total_liquido')::NUMERIC,
        'calculado', v_c->>'competencia', (v_c->>'data_prevista')::DATE,
        r.id, p_motivo,
        'apurado', 'apurado', v_c->'memoria')
    RETURNING id INTO v_novo;

    v_dif := round(COALESCE((v_c->>'total_liquido')::NUMERIC, 0) - COALESCE(r.total_liquido, 0), 2);

    RETURN jsonb_build_object(
        'ok', true,
        'cancelado', r.id, 'novo', v_novo,
        'liquido_anterior', r.total_liquido,
        'liquido_novo', (v_c->>'total_liquido')::NUMERIC,
        'diferenca', v_dif,
        'sentido', CASE WHEN v_dif > 0 THEN 'complemento a pagar'
                        WHEN v_dif < 0 THEN 'estorno a apurar'
                        ELSE 'sem diferença' END,
        'motivo', p_motivo);
END $fn$;

-- ── 4. Trava: dinheiro fechado não se sobrescreve ─────────────────────
CREATE OR REPLACE FUNCTION public.decimo_terceiro_trava_fechado()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $tg$
BEGIN
    -- Só protege os valores. Mudar situação, datas e carimbos é o
    -- caminho normal de aprovar, pagar e cancelar por reabertura.
    IF OLD.status IN ('aprovado', 'pago')
       AND (NEW.valor_bruto      IS DISTINCT FROM OLD.valor_bruto
         OR NEW.valor_inss       IS DISTINCT FROM OLD.valor_inss
         OR NEW.valor_irrf       IS DISTINCT FROM OLD.valor_irrf
         OR NEW.valor_fgts       IS DISTINCT FROM OLD.valor_fgts
         OR NEW.total_liquido    IS DISTINCT FROM OLD.total_liquido
         OR NEW.meses_trabalhados IS DISTINCT FROM OLD.meses_trabalhados)
    THEN
        RAISE EXCEPTION 'Cálculo de 13º já % não pode ter valores alterados. Use a reabertura, que preserva o histórico e registra o motivo.', OLD.status
            USING ERRCODE = 'raise_exception';
    END IF;
    RETURN NEW;
END $tg$;

DROP TRIGGER IF EXISTS trg_decimo_terceiro_trava_fechado ON public.folha_13_calculo;
CREATE TRIGGER trg_decimo_terceiro_trava_fechado
BEFORE UPDATE ON public.folha_13_calculo
FOR EACH ROW EXECUTE FUNCTION public.decimo_terceiro_trava_fechado();

COMMENT ON FUNCTION public.decimo_terceiro_reabrir(UUID, TEXT) IS
    'Reabre uma parcela fechada: cancela a linha antiga e cria a nova apontando para ela (reaberto_de), com motivo obrigatorio e a diferenca apurada. Exige segunda pessoa: quem aprovou nao reabre.';

GRANT EXECUTE ON FUNCTION public.decimo_terceiro_aprovar(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decimo_terceiro_pagar(UUID, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decimo_terceiro_reabrir(UUID, TEXT) TO authenticated;
