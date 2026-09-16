-- =========================================================
-- QA eSocial de ferias — a sonda preenche colaborador_id (NOT NULL)
--
-- qa_ferias_sonda_calculo inseria em folha_ferias_calculo sem colaborador_id,
-- que e TEXT NOT NULL no schema real -> a sonda quebrava e FERIAS-080/081/082
-- davam 'erro'. No stub local a coluna era nullable, por isso passava.
--
-- Correcao: a sonda passa a preencher colaborador_id. As rotinas 080/081/082
-- nao mudam (usam a sonda).
-- =========================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.qa_ferias_sonda_calculo(p_tenant UUID)
RETURNS UUID
LANGUAGE plpgsql AS $fn$
DECLARE v_id UUID;
BEGIN
    INSERT INTO public.folha_ferias_calculo
        (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
         periodo_aquisitivo_inicio, periodo_aquisitivo_fim,
         data_inicio_gozo, data_fim_gozo, dias_gozo,
         valor_ferias, valor_terco, total_liquido, data_pagamento, status)
    VALUES
        (p_tenant, 'QA-ESOCIAL', 'QA eSocial', '90000000191',
         CURRENT_DATE - 400, CURRENT_DATE - 35,
         CURRENT_DATE + 40, CURRENT_DATE + 69, 30,
         3000, 1000, 3600, CURRENT_DATE + 37, 'calculado')
    RETURNING id INTO v_id;
    RETURN v_id;
END $fn$;
