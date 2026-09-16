-- ============================================================================
-- ENTREGA — Ferias: eventos do eSocial S-2230/S-1200/S-1210 (RF-008)
--
-- Colar INTEIRO no SQL Editor do projeto de PRODUCAO e executar uma vez.
--
-- ESCOPO (decisao do dono do produto, 11/09/2026): GERAR, VALIDAR e
-- REGISTRAR os eventos, sob demanda. O ENVIO real (assinatura ICP-Brasil +
-- SOAP ao governo) e passo seguinte, quando certificado/ambiente existirem.
--
-- O QUE MUDA
--   1) esocial_transmissoes ganha ferias_calculo_id, competencia e
--      motivo_afastamento, com UNIQUE (tenant, ferias_calculo_id, tipo_evento)
--      para anti-duplicidade;
--   2) ferias_esocial_validar(): confere datas do gozo, CPF, valores e a data
--      de pagamento (art. 145) ANTES de gerar;
--   3) ferias_esocial_gerar(): monta S-2230 (motivo 15, datas exatas), S-1200
--      (ferias + terco) e S-1210 (detPgtoFer com a data real), em JSON;
--      idempotente e retificavel — nunca duplica o evento do mesmo gozo, e
--      nao reabre evento ja aceito;
--   4) ferias_esocial_interpretar_retorno(): traduz o codigo de rejeicao.
--   (As rotinas de QA FERIAS-080/081/082 rodam na homologacao, via a bancada
--    de QA; nao entram neste script de producao.)
--
-- SEGURANCA DO DADO
--   So CRIA/ALTERA estrutura (colunas com IF NOT EXISTS, indice, funcoes).
--   Nao altera nem apaga nenhuma LINHA existente, entao nao ha copia de
--   seguranca a fazer. Idempotente: rodar duas vezes nao quebra nem duplica.
--
-- PROVADO em replica local com schema fiel (folha_ferias_calculo com
--   colaborador_id NOT NULL): S-2230 com motivo 15 e datas exatas; rejeicao
--   traduzida e reenvio sem duplicar; S-1200/S-1210 com rubricas e data real;
--   gozo sem pagamento -> S-1210 'invalido'. FERIAS-080/081/082: passou.
--
-- A TELA (secao eSocial no detalhe do calculo) so muda apos Publicar no Lovable.
-- ============================================================================

SET lock_timeout = '10s';

-- ── 1. Vinculo do evento com a ferias que o originou ──────────────────────
ALTER TABLE public.esocial_transmissoes
    ADD COLUMN IF NOT EXISTS ferias_calculo_id UUID,
    ADD COLUMN IF NOT EXISTS competencia       TEXT,
    ADD COLUMN IF NOT EXISTS motivo_afastamento TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS uq_esocial_ferias_evento
    ON public.esocial_transmissoes (tenant_id, ferias_calculo_id, tipo_evento)
    WHERE ferias_calculo_id IS NOT NULL;

-- ── 2. Validacao previa ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ferias_esocial_validar(p_calculo UUID)
RETURNS TABLE (ok BOOLEAN, problemas TEXT[])
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
    c RECORD;
    v_prob TEXT[] := ARRAY[]::TEXT[];
BEGIN
    SELECT * INTO c FROM public.folha_ferias_calculo WHERE id = p_calculo;
    IF NOT FOUND THEN
        RETURN QUERY SELECT false, ARRAY['Calculo de ferias nao encontrado.']; RETURN;
    END IF;

    IF c.data_inicio_gozo IS NULL OR c.data_fim_gozo IS NULL THEN
        v_prob := array_append(v_prob, 'Datas de gozo incompletas (S-2230 exige inicio e fim).');
    ELSIF c.data_fim_gozo < c.data_inicio_gozo THEN
        v_prob := array_append(v_prob, 'Data de fim do gozo anterior ao inicio.');
    END IF;

    IF regexp_replace(coalesce(c.colaborador_cpf,''),'\D','','g') = '' THEN
        v_prob := array_append(v_prob, 'CPF do colaborador ausente.');
    END IF;

    IF coalesce(c.valor_ferias,0) <= 0 THEN
        v_prob := array_append(v_prob, 'Valor de ferias zerado (S-1200 exige a rubrica de ferias).');
    END IF;
    IF coalesce(c.valor_terco,0) <= 0 THEN
        v_prob := array_append(v_prob, 'Terco constitucional zerado (S-1200 exige a rubrica do 1/3).');
    END IF;

    IF c.data_pagamento IS NULL THEN
        v_prob := array_append(v_prob, 'Data de pagamento ausente (S-1210 detPgtoFer exige a data real).');
    ELSIF c.data_inicio_gozo IS NOT NULL AND c.data_pagamento > (c.data_inicio_gozo - 2) THEN
        v_prob := array_append(v_prob, 'Pagamento apos o prazo do art. 145 (ate 2 dias antes do inicio) — o eSocial registra a data real.');
    END IF;

    RETURN QUERY SELECT (array_length(v_prob,1) IS NULL), v_prob;
END $fn$;

-- ── 3. Gerar os tres eventos (idempotente, anti-duplicidade) ──────────────
CREATE OR REPLACE FUNCTION public.ferias_esocial_gerar(p_calculo UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
    c        RECORD;
    v_val    RECORD;
    v_comp   TEXT;
    v_status TEXT;
    v_msg    TEXT;
    v_cpf    TEXT;
    v_n      INTEGER := 0;
    ev       RECORD;
BEGIN
    SELECT * INTO c FROM public.folha_ferias_calculo WHERE id = p_calculo;
    IF NOT FOUND THEN RETURN 0; END IF;

    SELECT * INTO v_val FROM public.ferias_esocial_validar(p_calculo);
    v_comp := to_char(c.data_inicio_gozo, 'YYYY-MM');
    v_cpf  := regexp_replace(coalesce(c.colaborador_cpf,''),'\D','','g');

    IF NOT v_val.ok THEN
        v_status := 'invalido';
        v_msg := 'Validacao pre-envio: ' || array_to_string(v_val.problemas, ' ');
    ELSE
        v_status := 'pendente';
        v_msg := NULL;
    END IF;

    FOR ev IN
        SELECT * FROM (VALUES
            ('S-2230', '15'::text, jsonb_build_object(
                'evento','S-2230','cpfTrab',v_cpf,'nmTrab',c.colaborador_nome,
                'codMotAfast','15','dtIniAfast',c.data_inicio_gozo,'dtTermAfast',c.data_fim_gozo,
                'diasGozo',c.dias_gozo)),
            ('S-1200', NULL::text, jsonb_build_object(
                'evento','S-1200','cpfTrab',v_cpf,'perApur',v_comp,
                'itensRemun', jsonb_build_array(
                    jsonb_build_object('rubrica','FERIAS_GOZO','valor',c.valor_ferias),
                    jsonb_build_object('rubrica','TERCO_FERIAS','valor',c.valor_terco)))),
            ('S-1210', NULL::text, jsonb_build_object(
                'evento','S-1210','cpfTrab',v_cpf,'perApur',v_comp,
                'detPgtoFer', jsonb_build_object(
                    'dtPgto',c.data_pagamento,'vrLiq',c.total_liquido,
                    'vrFerias',c.valor_ferias,'vrTerco',c.valor_terco)))
        ) AS t(tipo, motivo, payload)
    LOOP
        INSERT INTO public.esocial_transmissoes
            (tenant_id, empresa_id, tipo_evento, ferias_calculo_id, competencia,
             motivo_afastamento, xml_enviado, status, mensagem_retorno, updated_at)
        VALUES
            (c.tenant_id, NULL, ev.tipo, c.id, v_comp, ev.motivo,
             ev.payload::text, v_status, v_msg, now())
        ON CONFLICT (tenant_id, ferias_calculo_id, tipo_evento)
          WHERE ferias_calculo_id IS NOT NULL
        DO UPDATE SET
            xml_enviado = EXCLUDED.xml_enviado,
            competencia = EXCLUDED.competencia,
            motivo_afastamento = EXCLUDED.motivo_afastamento,
            status = CASE WHEN public.esocial_transmissoes.status IN ('processado','enviado')
                          THEN public.esocial_transmissoes.status ELSE EXCLUDED.status END,
            mensagem_retorno = EXCLUDED.mensagem_retorno,
            updated_at = now();
        v_n := v_n + 1;
    END LOOP;

    RETURN v_n;
END $fn$;

-- ── 4. Interpretar o retorno (traduzir rejeicao) ──────────────────────────
CREATE OR REPLACE FUNCTION public.ferias_esocial_interpretar_retorno(
    p_transmissao UUID, p_codigo TEXT, p_mensagem TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
    v_status TEXT;
    v_traducao TEXT;
BEGIN
    v_traducao := CASE p_codigo
        WHEN '201' THEN 'Aceito com advertencias — confira as inconsistencias.'
        WHEN '202' THEN 'Aceito.'
        WHEN '301' THEN 'Erro de schema/leiaute — verifique campos obrigatorios e formato das datas.'
        WHEN '302' THEN 'Erro de regra — dado inconsistente (ex.: data fora do periodo, valor divergente).'
        ELSE coalesce(p_mensagem, 'Retorno nao reconhecido; conferir no ambiente do eSocial.')
    END;
    v_status := CASE WHEN p_codigo IN ('201','202') THEN 'processado' ELSE 'rejeitado' END;

    UPDATE public.esocial_transmissoes
       SET status = v_status, codigo_retorno = p_codigo, mensagem_retorno = v_traducao,
           xml_retorno = coalesce(p_mensagem, xml_retorno),
           ultima_tentativa = now(), updated_at = now()
     WHERE id = p_transmissao;

    RETURN v_status || ': ' || v_traducao;
END $fn$;

GRANT EXECUTE ON FUNCTION public.ferias_esocial_validar(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ferias_esocial_gerar(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ferias_esocial_interpretar_retorno(UUID, TEXT, TEXT) TO authenticated;

-- ── 6. Conferencia final (so catalogo do banco — nao depende de rotinas QA) ─
SELECT
    (SELECT count(*) FROM information_schema.columns
       WHERE table_name = 'esocial_transmissoes' AND column_name = 'ferias_calculo_id') AS vinculo_ferias,
    (to_regproc('public.ferias_esocial_validar') IS NOT NULL)                            AS valida,
    (to_regproc('public.ferias_esocial_gerar') IS NOT NULL)                              AS gera_eventos,
    (to_regproc('public.ferias_esocial_interpretar_retorno') IS NOT NULL)                AS interpreta_retorno,
    (SELECT count(*) FROM pg_indexes WHERE indexname = 'uq_esocial_ferias_evento')       AS anti_duplicidade;
