-- =========================================================
-- 13º Salário — Entrega 2, parte 2: encargos no banco e lote
--
-- PROBLEMA: INSS, IRRF e FGTS do 13º só existiam no NAVEGADOR
-- (src/lib/folha/calculos.ts). Consequências: a folha de dezembro de uma
-- empresa inteira dependia de alguém abrir um modal e repetir o gesto
-- colaborador a colaborador (RNF-008 pede lote sem degradação); e o
-- valor não era reproduzível fora da tela, o que impede auditoria
-- (RNF-001/007).
--
-- ENTREGA:
--   1) decimo_terceiro_inss / _irrf — as tabelas progressivas no banco,
--      lendo folha_tabelas_inss/irrf por vigência, com as faixas de 2025
--      como padrão quando a empresa ainda não cadastrou as suas;
--   2) decimo_terceiro_calcular — uma parcela inteira (bruto, encargos,
--      líquido) com a memória de cada faixa aplicada;
--   3) decimo_terceiro_lote — a empresa inteira de uma vez, idempotente,
--      gravando a competência, o prazo legal e o identificador do lote.
--
-- As contas espelham calcular13/calcularINSS/calcularIRRF do front,
-- inclusive o arredondamento por faixa, para os dois caminhos darem o
-- mesmo número enquanto a tela ainda calcula sozinha.
--
-- Requisitos YE-DP-13-001: RF-003, RF-004, RN-005, RN-006, RN-007,
-- CA-003, CA-004, CA-005, RNF-001/007/008.
-- =========================================================

SET lock_timeout = '10s';

-- ── 1. INSS progressivo ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.decimo_terceiro_inss(
    p_base     NUMERIC,
    p_tenant   UUID DEFAULT NULL,
    p_data_ref DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    v_faixas JSONB;
    v_teto   NUMERIC(12,2);
    v_base   NUMERIC(12,2);
    v_valor  NUMERIC(12,2) := 0;
    v_det    JSONB := '[]'::jsonb;
    v_origem TEXT := 'tabela da empresa';
    r        RECORD;
    v_parc   NUMERIC(12,2);
BEGIN
    IF p_tenant IS NOT NULL THEN
        SELECT t.faixas, t.teto INTO v_faixas, v_teto
          FROM public.folha_tabelas_inss t
         WHERE t.tenant_id = p_tenant
           AND t.vigencia_inicio <= p_data_ref
           AND (t.vigencia_fim IS NULL OR t.vigencia_fim >= p_data_ref)
         ORDER BY t.vigencia_inicio DESC
         LIMIT 1;
    END IF;

    IF v_faixas IS NULL OR jsonb_array_length(v_faixas) = 0 THEN
        -- Padrão de 2025, o mesmo embutido no front. Fica registrado na
        -- memória para ninguém confundir com tabela cadastrada.
        v_faixas := '[{"de":0,"ate":1518.00,"aliquota":7.5},
                      {"de":1518.01,"ate":2793.88,"aliquota":9},
                      {"de":2793.89,"ate":4190.83,"aliquota":12},
                      {"de":4190.84,"ate":8157.41,"aliquota":14}]'::jsonb;
        v_teto   := 8157.41;
        v_origem := 'padrao 2025 (empresa sem tabela vigente cadastrada)';
    END IF;

    v_base := least(COALESCE(p_base, 0), COALESCE(v_teto, 8157.41));
    IF v_base <= 0 THEN
        RETURN jsonb_build_object('valor', 0, 'base_efetiva', 0,
                                  'origem_tabela', v_origem, 'faixas', '[]'::jsonb);
    END IF;

    FOR r IN
        SELECT (f->>'de')::NUMERIC       AS de,
               (f->>'ate')::NUMERIC      AS ate,
               (f->>'aliquota')::NUMERIC AS aliquota
          FROM jsonb_array_elements(v_faixas) f
         ORDER BY (f->>'de')::NUMERIC
    LOOP
        -- Base dentro da faixa: o "de" começa em X,01, então o teto da
        -- faixa anterior é de - 0,01. Arredonda por faixa, como o front.
        v_parc := greatest(0, least(v_base, r.ate) - greatest(0, r.de - 0.01));
        EXIT WHEN v_parc <= 0 AND v_base < r.de;
        CONTINUE WHEN v_parc <= 0;

        v_parc := round(v_parc * r.aliquota / 100, 2);
        v_valor := v_valor + v_parc;
        v_det := v_det || jsonb_build_object(
            'de', r.de, 'ate', r.ate, 'aliquota', r.aliquota, 'valor', v_parc);
    END LOOP;

    RETURN jsonb_build_object(
        'valor', round(v_valor, 2), 'base_efetiva', v_base,
        'origem_tabela', v_origem, 'faixas', v_det);
END $fn$;

COMMENT ON FUNCTION public.decimo_terceiro_inss(NUMERIC, UUID, DATE) IS
    'INSS progressivo do 13o pela tabela vigente da empresa (folha_tabelas_inss), com a memoria faixa a faixa. Somente leitura.';

-- ── 2. IRRF exclusivo na fonte ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.decimo_terceiro_irrf(
    p_base        NUMERIC,
    p_dependentes INT DEFAULT 0,
    p_tenant      UUID DEFAULT NULL,
    p_data_ref    DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    v_faixas JSONB;
    v_ded_dep NUMERIC(12,2);
    v_base   NUMERIC(12,2);
    v_origem TEXT := 'tabela da empresa';
    r        RECORD;
BEGIN
    IF p_tenant IS NOT NULL THEN
        SELECT t.faixas, t.deducao_por_dependente INTO v_faixas, v_ded_dep
          FROM public.folha_tabelas_irrf t
         WHERE t.tenant_id = p_tenant
           AND t.vigencia_inicio <= p_data_ref
           AND (t.vigencia_fim IS NULL OR t.vigencia_fim >= p_data_ref)
         ORDER BY t.vigencia_inicio DESC
         LIMIT 1;
    END IF;

    IF v_faixas IS NULL OR jsonb_array_length(v_faixas) = 0 THEN
        v_faixas := '[{"de":0,"ate":2259.20,"aliquota":0,"deducao":0},
                      {"de":2259.21,"ate":2826.65,"aliquota":7.5,"deducao":169.44},
                      {"de":2826.66,"ate":3751.05,"aliquota":15,"deducao":381.44},
                      {"de":3751.06,"ate":4664.68,"aliquota":22.5,"deducao":662.77},
                      {"de":4664.69,"ate":999999999,"aliquota":27.5,"deducao":896.00}]'::jsonb;
        v_ded_dep := 189.59;
        v_origem  := 'padrao 2025 (empresa sem tabela vigente cadastrada)';
    END IF;

    v_base := COALESCE(p_base, 0) - (COALESCE(p_dependentes, 0) * COALESCE(v_ded_dep, 0));

    IF v_base <= 0 THEN
        RETURN jsonb_build_object('valor', 0, 'base_efetiva', 0, 'aliquota', 0,
                                  'faixa', 'Isento', 'origem_tabela', v_origem);
    END IF;

    FOR r IN
        SELECT (f->>'de')::NUMERIC       AS de,
               (f->>'ate')::NUMERIC      AS ate,
               (f->>'aliquota')::NUMERIC AS aliquota,
               (f->>'deducao')::NUMERIC  AS deducao
          FROM jsonb_array_elements(v_faixas) f
         ORDER BY (f->>'de')::NUMERIC
    LOOP
        IF v_base >= r.de AND v_base <= r.ate THEN
            RETURN jsonb_build_object(
                'valor', greatest(0, round(v_base * r.aliquota / 100 - r.deducao, 2)),
                'base_efetiva', v_base,
                'aliquota', r.aliquota,
                'deducao_faixa', r.deducao,
                'deducao_dependentes', COALESCE(p_dependentes,0) * COALESCE(v_ded_dep,0),
                'faixa', format('R$ %s a R$ %s', r.de, r.ate),
                'origem_tabela', v_origem);
        END IF;
    END LOOP;

    RETURN jsonb_build_object('valor', 0, 'base_efetiva', v_base, 'aliquota', 0,
                              'faixa', 'Isento', 'origem_tabela', v_origem);
END $fn$;

COMMENT ON FUNCTION public.decimo_terceiro_irrf(NUMERIC, INT, UUID, DATE) IS
    'IRRF exclusivo na fonte do 13o pela tabela vigente da empresa (folha_tabelas_irrf), com deducao por dependente. Somente leitura.';

GRANT EXECUTE ON FUNCTION public.decimo_terceiro_inss(NUMERIC, UUID, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decimo_terceiro_irrf(NUMERIC, INT, UUID, DATE) TO authenticated;

-- ── 3. Uma parcela inteira ────────────────────────────────────────────
-- Espelha calcular13 do front: 1ª parcela é 50% sem INSS/IRRF (o FGTS
-- incide na competência do pagamento); 2ª aplica INSS e IRRF sobre o
-- 13º cheio, calculado em separado da folha do mês (RN-005/007), deduz
-- o adiantamento e recolhe FGTS sobre a diferença.
CREATE OR REPLACE FUNCTION public.decimo_terceiro_calcular(
    p_tenant       UUID,
    p_cpf          TEXT,
    p_ano          INT,
    p_parcela      INT,
    p_empresa      UUID    DEFAULT NULL,
    p_dependentes  INT     DEFAULT 0,
    p_primeira     NUMERIC DEFAULT NULL,
    p_tipo_vinculo TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    v_ap        JSONB;
    v_avos      INT;
    v_bruto     NUMERIC(12,2);
    v_primeira  NUMERIC(12,2);
    v_inss_j    JSONB := NULL;
    v_irrf_j    JSONB := NULL;
    v_inss      NUMERIC(12,2) := 0;
    v_irrf      NUMERIC(12,2) := 0;
    v_base_fgts NUMERIC(12,2) := 0;
    v_fgts      NUMERIC(12,2) := 0;
    v_desc      NUMERIC(12,2) := 0;
    v_liq       NUMERIC(12,2) := 0;
    v_aliq_fgts NUMERIC(5,2)  := 8.00;
    v_tem_fgts  BOOLEAN := true;
    v_tem_inss  BOOLEAN := true;
    v_data_ref  DATE;
BEGIN
    IF p_parcela NOT IN (1, 2) THEN
        RETURN jsonb_build_object('erro', 'Parcela deve ser 1 ou 2.');
    END IF;

    v_ap    := public.decimo_terceiro_apurar(p_tenant, p_cpf, p_ano, NULL, p_empresa);
    v_avos  := COALESCE((v_ap->>'avos')::INT, 0);
    v_bruto := round(COALESCE((v_ap->>'base_integral')::NUMERIC, 0) * v_avos / 12.0, 2);

    -- Regras do vínculo (avulso, estagiário e afins podem não ter FGTS).
    IF p_tipo_vinculo IS NOT NULL THEN
        SELECT c.fgts, c.aliquota_fgts, c.inss_empregado
          INTO v_tem_fgts, v_aliq_fgts, v_tem_inss
          FROM public.folha_vinculos_config c
         WHERE c.tenant_id = p_tenant AND c.tipo_vinculo = p_tipo_vinculo
         LIMIT 1;
        v_tem_fgts  := COALESCE(v_tem_fgts, true);
        v_aliq_fgts := COALESCE(v_aliq_fgts, 8.00);
        v_tem_inss  := COALESCE(v_tem_inss, true);
    END IF;

    v_data_ref := public.decimo_terceiro_prazo_legal(p_ano, p_parcela);

    IF p_parcela = 1 THEN
        v_primeira  := round(v_bruto / 2, 2);
        v_base_fgts := v_primeira;
        v_fgts      := CASE WHEN v_tem_fgts THEN round(v_base_fgts * v_aliq_fgts / 100, 2) ELSE 0 END;
        v_liq       := v_primeira;
    ELSE
        v_primeira := COALESCE(p_primeira, round(v_bruto / 2, 2));

        IF v_tem_inss THEN
            v_inss_j := public.decimo_terceiro_inss(v_bruto, p_tenant, v_data_ref);
            v_inss   := COALESCE((v_inss_j->>'valor')::NUMERIC, 0);
        END IF;

        v_irrf_j := public.decimo_terceiro_irrf(v_bruto - v_inss, p_dependentes, p_tenant, v_data_ref);
        v_irrf   := COALESCE((v_irrf_j->>'valor')::NUMERIC, 0);

        v_base_fgts := v_bruto - v_primeira;
        v_fgts      := CASE WHEN v_tem_fgts THEN round(v_base_fgts * v_aliq_fgts / 100, 2) ELSE 0 END;

        v_desc := round(v_inss + v_irrf + v_primeira, 2);
        v_liq  := round(v_bruto - v_desc, 2);
    END IF;

    RETURN jsonb_build_object(
        'ano', p_ano, 'parcela', p_parcela, 'avos', v_avos,
        'remuneracao_base',      (v_ap->>'remuneracao_base')::NUMERIC,
        'media_variaveis',       (v_ap->>'media_variaveis')::NUMERIC,
        'valor_bruto',           v_bruto,
        'valor_primeira_parcela', v_primeira,
        'base_inss',   CASE WHEN p_parcela = 2 THEN v_bruto ELSE 0 END,
        'valor_inss',  v_inss,
        'base_irrf',   CASE WHEN p_parcela = 2 THEN v_bruto - v_inss ELSE 0 END,
        'valor_irrf',  v_irrf,
        'base_fgts',   v_base_fgts,
        'valor_fgts',  v_fgts,
        'total_descontos', v_desc,
        'total_liquido',   v_liq,
        'data_prevista',   v_data_ref,
        'competencia',     to_char(v_data_ref, 'YYYY-MM'),
        'memoria', jsonb_build_object(
            'apuracao', v_ap, 'inss', v_inss_j, 'irrf', v_irrf_j,
            'aliquota_fgts', v_aliq_fgts, 'dependentes_irrf', COALESCE(p_dependentes, 0),
            'fundamento', 'Lei 4.749/1965 (parcelas); INSS e IRRF so na 2a; FGTS nas duas'));
END $fn$;

COMMENT ON FUNCTION public.decimo_terceiro_calcular(UUID, TEXT, INT, INT, UUID, INT, NUMERIC, TEXT) IS
    'Calcula uma parcela do 13o de um vinculo (bruto, INSS, IRRF, FGTS, liquido) com a memoria completa. Somente leitura: nada e gravado.';

GRANT EXECUTE ON FUNCTION public.decimo_terceiro_calcular(UUID, TEXT, INT, INT, UUID, INT, NUMERIC, TEXT) TO authenticated;


-- ── 4. A empresa inteira de uma vez ───────────────────────────────────
-- Idempotente: quem já tem cálculo vivo daquela parcela é pulado, não
-- duplicado (a unicidade do índice também barraria). Grava competência,
-- prazo legal e o identificador do lote.
CREATE OR REPLACE FUNCTION public.decimo_terceiro_lote(
    p_tenant  UUID,
    p_ano     INT,
    p_parcela INT,
    p_empresa UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    v_lote     UUID := gen_random_uuid();
    v_prazo    DATE;
    a          RECORD;
    v_c        JSONB;
    v_criados  INT := 0;
    v_pulados  INT := 0;
    v_semavo   INT := 0;
    v_erros    JSONB := '[]'::jsonb;
    v_total    NUMERIC(14,2) := 0;
BEGIN
    IF p_tenant IS NULL OR p_ano IS NULL OR p_parcela NOT IN (1, 2) THEN
        RETURN jsonb_build_object('erro', 'Informe empresa, ano-base e parcela (1 ou 2).');
    END IF;

    v_prazo := public.decimo_terceiro_prazo_legal(p_ano, p_parcela);

    FOR a IN
        SELECT ad.id, ad.nome_completo, ad.cpf, ad.tipo_contrato, ad.empresa_id
          FROM public.admissoes ad
         WHERE ad.tenant_id = p_tenant
           AND ad.status = 'concluido'
           AND ad.data_admissao IS NOT NULL
           AND (p_empresa IS NULL OR ad.empresa_id = p_empresa)
         ORDER BY ad.nome_completo
    LOOP
        BEGIN
            -- Já existe cálculo vivo desta parcela? Então não se mexe.
            IF EXISTS (
                SELECT 1 FROM public.folha_13_calculo c
                 WHERE c.tenant_id = p_tenant AND c.ano = p_ano AND c.parcela = p_parcela
                   AND regexp_replace(COALESCE(c.colaborador_cpf,''), '[^0-9]', '', 'g')
                       = regexp_replace(COALESCE(a.cpf,''), '[^0-9]', '', 'g')
                   AND c.status <> 'cancelado')
            THEN
                v_pulados := v_pulados + 1;
                CONTINUE;
            END IF;

            v_c := public.decimo_terceiro_calcular(
                       p_tenant, a.cpf, p_ano, p_parcela, p_empresa, 0, NULL, a.tipo_contrato);

            -- Sem avo não há 13º a pagar: não se grava linha zerada.
            IF COALESCE((v_c->>'avos')::INT, 0) = 0 THEN
                v_semavo := v_semavo + 1;
                CONTINUE;
            END IF;

            INSERT INTO public.folha_13_calculo (
                tenant_id, empresa_id, admissao_id, ano, parcela,
                colaborador_id, colaborador_nome, colaborador_cpf, tipo_vinculo,
                meses_trabalhados, remuneracao_base, media_variaveis,
                valor_bruto, valor_primeira_parcela,
                base_inss, valor_inss, base_irrf, valor_irrf,
                base_fgts, valor_fgts, total_descontos, total_liquido,
                status, competencia, data_prevista, lote_id,
                avos_origem, media_origem, memoria_calculo)
            VALUES (
                p_tenant, a.empresa_id, a.id, p_ano, p_parcela,
                a.id::text, a.nome_completo, a.cpf, a.tipo_contrato,
                (v_c->>'avos')::INT,
                (v_c->>'remuneracao_base')::NUMERIC, (v_c->>'media_variaveis')::NUMERIC,
                (v_c->>'valor_bruto')::NUMERIC, (v_c->>'valor_primeira_parcela')::NUMERIC,
                (v_c->>'base_inss')::NUMERIC, (v_c->>'valor_inss')::NUMERIC,
                (v_c->>'base_irrf')::NUMERIC, (v_c->>'valor_irrf')::NUMERIC,
                (v_c->>'base_fgts')::NUMERIC, (v_c->>'valor_fgts')::NUMERIC,
                (v_c->>'total_descontos')::NUMERIC, (v_c->>'total_liquido')::NUMERIC,
                'calculado', v_c->>'competencia', v_prazo, v_lote,
                'apurado', 'apurado', v_c->'memoria');

            v_criados := v_criados + 1;
            v_total   := v_total + COALESCE((v_c->>'total_liquido')::NUMERIC, 0);

        EXCEPTION WHEN OTHERS THEN
            -- Um colaborador problemático não derruba a folha inteira,
            -- mas volta nomeado no resultado.
            v_erros := v_erros || jsonb_build_object(
                'colaborador', a.nome_completo, 'erro', SQLERRM);
        END;
    END LOOP;

    RETURN jsonb_build_object(
        'lote_id', v_lote, 'ano', p_ano, 'parcela', p_parcela,
        'prazo_legal', v_prazo,
        'criados', v_criados, 'ja_existiam', v_pulados, 'sem_avo', v_semavo,
        'total_liquido', round(v_total, 2),
        'erros', v_erros, 'processado_em', now());
END $fn$;

COMMENT ON FUNCTION public.decimo_terceiro_lote(UUID, INT, INT, UUID) IS
    'Calcula e grava a parcela do 13o de todos os vinculos da empresa de uma vez. Idempotente: quem ja tem calculo vivo e pulado. Devolve o resumo do lote.';

GRANT EXECUTE ON FUNCTION public.decimo_terceiro_lote(UUID, INT, INT, UUID) TO authenticated;
