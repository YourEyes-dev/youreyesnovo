-- =========================================================
-- SCRIPT DE ENTREGA — 13º Salário, Entrega 2
-- Estrutura, integridade, segurança, encargos no banco e lote
--
-- PRÉ-REQUISITO: rodar ANTES o script da Entrega 1
-- (docs/script_13o_apuracao_avos_e_medias.sql). Este depende das
-- funções de apuração criadas lá.
--
-- O QUE ESTE SCRIPT FAZ:
--   * acrescenta em folha_13_calculo as colunas de competência, prazo,
--     pagamento, aprovação, lote e trilha de reabertura;
--   * fecha o vocabulário de situação e impede valor negativo, encargo
--     na 1ª parcela, base de FGTS maior que o 13º e parcela duplicada;
--   * condiciona a LEITURA ao perfil: quem não administra a folha passa
--     a enxergar só o próprio 13º;
--   * traz INSS, IRRF e o prazo legal para dentro do banco;
--   * cria o processamento em lote e o rito de aprovar, pagar e reabrir.
--
-- O QUE ESTE SCRIPT NÃO FAZ: não altera nem apaga nenhum cálculo de 13º
-- já gravado. Só cria objetos novos, acrescenta colunas com valor padrão
-- e adiciona travas NOT VALID — que valem para o que entrar de agora em
-- diante e NÃO varrem o histórico. Por isso não há tabela de backup.
--
-- ATENÇÃO À MUDANÇA DE VISIBILIDADE: depois deste script, um usuário sem
-- perfil de Financeiro/Colaboradores deixa de enxergar o 13º dos outros.
-- É o comportamento pedido (LGPD, dado de remuneração), mas confira os
-- perfis antes de rodar para ninguém perder acesso necessário.
--
-- Idempotente: rodar duas vezes não quebra nem duplica.
-- Rodar no SQL Editor do projeto de PRODUÇÃO, de uma vez só.
-- =========================================================

SET lock_timeout = '10s';

-- ── 1. Colunas que faltavam ───────────────────────────────────────────
ALTER TABLE public.folha_13_calculo
    ADD COLUMN IF NOT EXISTS admissao_id       UUID REFERENCES public.admissoes(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS empresa_id        UUID,
    ADD COLUMN IF NOT EXISTS competencia       TEXT,
    ADD COLUMN IF NOT EXISTS data_prevista     DATE,
    ADD COLUMN IF NOT EXISTS data_pagamento    DATE,
    ADD COLUMN IF NOT EXISTS aprovado_por      UUID,
    ADD COLUMN IF NOT EXISTS aprovado_por_nome TEXT,
    ADD COLUMN IF NOT EXISTS aprovado_em       TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS pago_por          UUID,
    ADD COLUMN IF NOT EXISTS pago_em           TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS reaberto_de       UUID REFERENCES public.folha_13_calculo(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS reabertura_motivo TEXT,
    ADD COLUMN IF NOT EXISTS lote_id           UUID,
    ADD COLUMN IF NOT EXISTS observacao        TEXT;

COMMENT ON COLUMN public.folha_13_calculo.admissao_id IS
    'Vinculo real com a admissao que originou o calculo (o colaborador_id e TEXT solto, herdado).';
COMMENT ON COLUMN public.folha_13_calculo.data_prevista IS
    'Prazo legal da parcela (Lei 4.749/1965): 30/11 para a 1a, 20/12 para a 2a, antecipado por fim de semana ou feriado.';
COMMENT ON COLUMN public.folha_13_calculo.reaberto_de IS
    'Quando o calculo nasce da reabertura de um fechado, aponta para o anterior — a trilha nao se perde.';
COMMENT ON COLUMN public.folha_13_calculo.lote_id IS
    'Identifica a rodada de processamento em lote que gerou a linha.';

-- ── 2. Vocabulário de situação ────────────────────────────────────────
-- O default herdado é 'calculado'; o vocabulário passa a ser fechado.
-- NOT VALID de proposito: barra o que entra de agora em diante sem
-- varrer o historico de producao, que pode ter valor fora da lista.
DO $ck$
BEGIN
    ALTER TABLE public.folha_13_calculo
        ADD CONSTRAINT folha_13_calculo_status_ck
        CHECK (status IN ('rascunho', 'calculado', 'aprovado', 'pago', 'cancelado')) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

-- Valores não podem ser negativos.
DO $ck$
BEGIN
    ALTER TABLE public.folha_13_calculo
        ADD CONSTRAINT folha_13_calculo_valores_ck
        CHECK (valor_bruto >= 0 AND valor_inss >= 0 AND valor_irrf >= 0
               AND valor_fgts >= 0 AND total_descontos >= 0) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

-- Aprovado e pago exigem carimbo de quem e quando.
DO $ck$
BEGIN
    ALTER TABLE public.folha_13_calculo
        ADD CONSTRAINT folha_13_calculo_aprovacao_ck
        CHECK (status <> 'aprovado' OR aprovado_em IS NOT NULL) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

DO $ck$
BEGIN
    ALTER TABLE public.folha_13_calculo
        ADD CONSTRAINT folha_13_calculo_pagamento_ck
        CHECK (status <> 'pago' OR data_pagamento IS NOT NULL) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

-- ── Uma parcela viva por colaborador/ano ──────────────────────────────
-- Cancelado fica de fora: é o que permite reabrir sem apagar o
-- histórico. Linha sem CPF também, porque não identifica ninguém.
--
-- TOLERANTE DE PROPÓSITO: se a base já tiver duas parcelas vivas da
-- mesma pessoa (dado antigo), a criação do índice falharia e, num
-- script de uma transação só, derrubaria a entrega inteira. Aqui ela
-- avisa e segue; a conferência final aponta o que precisa ser
-- resolvido antes de tentar de novo.
DO $ix$
BEGIN
    CREATE UNIQUE INDEX IF NOT EXISTS folha_13_calculo_parcela_viva_uq
        ON public.folha_13_calculo (
            tenant_id, ano, parcela,
            regexp_replace(colaborador_cpf, '[^0-9]', '', 'g'),
            COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid))
        WHERE status <> 'cancelado'
          AND colaborador_cpf IS NOT NULL
          AND regexp_replace(colaborador_cpf, '[^0-9]', '', 'g') <> '';

    COMMENT ON INDEX public.folha_13_calculo_parcela_viva_uq IS
        'Uma parcela viva por colaborador/ano/empresa. Cancelado e linha sem CPF ficam de fora.';
EXCEPTION WHEN unique_violation OR others THEN
    RAISE NOTICE 'Unicidade da parcela viva NAO criada: %. Ha calculo duplicado na base — a conferencia final lista.', SQLERRM;
END $ix$;

-- ── 4. Camada de perfil: remuneração não é de todo mundo ──────────────
DO $rls$
DECLARE
    c_admin CONSTANT TEXT :=
        $a$public.perfil_permite_modulo(tenant_id, 'financeiro', 'colaboradores')$a$;
    c_proprio CONSTANT TEXT :=
        $p$regexp_replace(COALESCE(colaborador_cpf, ''), '[^0-9]', '', 'g')
             = public.cpf_do_usuario_logado()$p$;
BEGIN
    IF to_regclass('public.folha_13_calculo') IS NULL THEN
        RAISE NOTICE 'folha_13_calculo não existe nesta base; camada de perfil pulada.';
        RETURN;
    END IF;

    EXECUTE 'DROP POLICY IF EXISTS perfil_restringe_leitura_folha_13_calculo ON public.folha_13_calculo';
    EXECUTE format(
        'CREATE POLICY perfil_restringe_leitura_folha_13_calculo ON public.folha_13_calculo
           AS RESTRICTIVE FOR SELECT TO authenticated USING (%s OR %s)',
        c_admin, c_proprio);
    RAISE NOTICE 'Camada de perfil aplicada em folha_13_calculo: quem não administra a folha só vê o próprio 13º.';
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'folha_13_calculo ficou SEM a camada de perfil: %', SQLERRM;
END $rls$;

-- ── 5. Prazo legal da parcela (Lei 4.749/1965) ────────────────────────
-- 1ª até 30/11, 2ª até 20/12; se a data cair em fim de semana ou
-- feriado, ANTECIPA para o último dia útil anterior.
CREATE OR REPLACE FUNCTION public.decimo_terceiro_prazo_legal(
    p_ano     INT,
    p_parcela INT,
    p_uf      TEXT DEFAULT NULL,
    p_municipio TEXT DEFAULT NULL
)
RETURNS DATE
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    v_data DATE;
    v_i    INT := 0;
BEGIN
    IF p_ano IS NULL OR p_parcela NOT IN (1, 2) THEN
        RETURN NULL;
    END IF;

    v_data := CASE WHEN p_parcela = 1
                   THEN make_date(p_ano, 11, 30)
                   ELSE make_date(p_ano, 12, 20) END;

    -- Anda para trás até cair em dia útil. O limite de 15 tentativas é
    -- folga de sobra para qualquer emenda de feriados.
    WHILE v_i < 15 LOOP
        EXIT WHEN extract(isodow FROM v_data) < 6
              AND NOT EXISTS (
                  SELECT 1 FROM public.feriados f
                   WHERE COALESCE(f.ativo, true)
                     -- Só feriado de fato: facultativo não obriga a antecipar.
                     AND COALESCE(f.tipo, '') <> 'facultativo'
                     -- A tabela guarda data fixa OU recorrente por dia/mês.
                     AND (f.data = v_data
                          OR (COALESCE(f.recorrente, false)
                              AND f.dia = extract(day   FROM v_data)::int
                              AND f.mes = extract(month FROM v_data)::int))
                     AND (COALESCE(f.abrangencia, 'nacional') = 'nacional'
                          OR (p_uf IS NOT NULL AND f.uf = p_uf)
                          OR (p_municipio IS NOT NULL AND f.municipio = p_municipio)));
        v_data := v_data - 1;
        v_i := v_i + 1;
    END LOOP;

    RETURN v_data;
END $fn$;

COMMENT ON FUNCTION public.decimo_terceiro_prazo_legal(INT, INT, TEXT, TEXT) IS
    'Prazo legal da parcela do 13o (Lei 4.749/1965): 30/11 e 20/12, antecipando para o ultimo dia util anterior quando cai em fim de semana ou feriado.';

GRANT EXECUTE ON FUNCTION public.decimo_terceiro_prazo_legal(INT, INT, TEXT, TEXT) TO authenticated;


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

-- ── 2. DEC13-070: a sonda informa a data de pagamento ─────────────────

-- ── 3. As regras dos encargos passam a viver no banco ─────────────────
-- Até aqui elas existiam só no cálculo da tela: quem gravasse por fora
-- (importação, script, integração) furava a regra sem resistência.
-- Casos DEC13-040, DEC13-041 e DEC13-042.

-- INSS e IRRF só na 2ª parcela (Lei 4.749/1965; RIR/2018 art. 700: a
-- tributação é exclusiva na fonte, apurada na 2ª sobre o valor integral).
DO $ck$
BEGIN
    ALTER TABLE public.folha_13_calculo
        ADD CONSTRAINT folha_13_calculo_encargos_2a_ck
        CHECK (parcela <> 1
               OR (COALESCE(valor_inss, 0) = 0 AND COALESCE(valor_irrf, 0) = 0
                   AND COALESCE(base_inss, 0) = 0 AND COALESCE(base_irrf, 0) = 0)) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

-- FGTS incide sobre a parcela paga, nunca sobre mais que o 13º cheio
-- (Lei 8.036 art. 15): a soma das duas bases fecha exatamente o bruto.
DO $ck$
BEGIN
    ALTER TABLE public.folha_13_calculo
        ADD CONSTRAINT folha_13_calculo_base_fgts_ck
        CHECK (COALESCE(base_fgts, 0) <= COALESCE(valor_bruto, 0)) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

-- O adiantamento deduzido não pode superar o próprio 13º.
DO $ck$
BEGIN
    ALTER TABLE public.folha_13_calculo
        ADD CONSTRAINT folha_13_calculo_primeira_ck
        CHECK (COALESCE(valor_primeira_parcela, 0) <= COALESCE(valor_bruto, 0)) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

-- ── Sonda de QA DEC13-070 acompanha a trava nova ──────────────────────
-- O CHECK de pagamento (acima) recusa status 'pago' sem data. A sonda de
-- QA foi escrita para o banco antigo, frouxo: ela gravava 'pago' sem
-- data e, com a trava, passaria a devolver 'erro' em vez de julgar o
-- sistema. A sonda se ajusta a regra nova; a regra fica.
-- ── 2. DEC13-070: a sonda informa a data de pagamento ─────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_070()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_id uuid; v_alterou boolean := false; v_trg text;
BEGIN
  -- A sonda grava e NÃO desfaz (padrão desta família). Com a unicidade
  -- da Entrega 2, rodar duas vezes colidiria com a própria linha da
  -- rodada anterior — então ela limpa o próprio rastro antes.
  DELETE FROM public.folha_13_calculo
   WHERE tenant_id = public.qa_sandbox_tenant_id()
     AND colaborador_id = 'qa-dec13-070';

  -- Pago exige data de pagamento desde a Entrega 2 (CHECK
  -- folha_13_calculo_pagamento_ck) — a sonda informa, como a tela faz.
  INSERT INTO public.folha_13_calculo
    (tenant_id, ano, colaborador_id, colaborador_nome, colaborador_cpf, parcela,
     valor_bruto, total_liquido, status, data_pagamento)
  VALUES (public.qa_sandbox_tenant_id(), extract(year from CURRENT_DATE)::int,
          'qa-dec13-070', 'QA Pago Editado', '00000000070', 2, 3000, 2500,
          'pago', CURRENT_DATE)
  RETURNING id INTO v_id;

  r.passo_ordem := 1;
  r.passo_acao := 'Editar diretamente o valor bruto de um cálculo com status PAGO';
  r.esperado := 'Bloqueado — valor pago só muda por reabertura com motivo, dupla aprovação e diferença';
  BEGIN
    UPDATE public.folha_13_calculo SET valor_bruto = 9999 WHERE id = v_id;
    SELECT (valor_bruto = 9999) INTO v_alterou FROM public.folha_13_calculo WHERE id = v_id;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_alterou := false; END;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: existe trilha de alteração na tabela do 13º?';
  r.esperado := 'Gatilho de auditoria registrando antes/depois (RNF-004: log imutável)';
  SELECT string_agg(DISTINCT t.tgname, ', ') INTO v_trg
  FROM pg_trigger t
  WHERE t.tgrelid = 'public.folha_13_calculo'::regclass AND NOT t.tgisinternal
    AND t.tgname NOT ILIKE '%updated_at%' AND t.tgname NOT ILIKE 'qa\_%';

  IF v_alterou AND v_trg IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: um cálculo PAGO foi editado em silêncio — o valor bruto mudou de 3.000 '
             || 'para 9.999 sem bloqueio, sem justificativa, sem aprovação e sem trilha. '
             || 'Correção: trava de UPDATE para status pago/fechado + fluxo de reabertura '
             || '(RF-007 do documento).';
  ELSIF NOT v_alterou THEN
    r.situacao := 'passou';
    r.obtido := format('A edição direta do cálculo pago foi recusada pela trava do banco%s.',
                       CASE WHEN v_trg IS NULL THEN '' ELSE ' (gatilhos: ' || v_trg || ')' END);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Alteração registrada em trilha (%s) — conferir se guarda antes/depois.', v_trg);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── 2. As regras dos encargos passam a viver no banco ─────────────────
-- Até aqui elas existiam só no cálculo da tela: quem gravasse por fora
-- (importação, script, integração) furava a regra sem resistência.
-- Casos DEC13-040, DEC13-041 e DEC13-042.

-- INSS e IRRF só na 2ª parcela (Lei 4.749/1965; RIR/2018 art. 700: a
-- tributação é exclusiva na fonte, apurada na 2ª sobre o valor integral).
DO $ck$
BEGIN
    ALTER TABLE public.folha_13_calculo
        ADD CONSTRAINT folha_13_calculo_encargos_2a_ck
        CHECK (parcela <> 1
               OR (COALESCE(valor_inss, 0) = 0 AND COALESCE(valor_irrf, 0) = 0
                   AND COALESCE(base_inss, 0) = 0 AND COALESCE(base_irrf, 0) = 0)) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

-- FGTS incide sobre a parcela paga, nunca sobre mais que o 13º cheio
-- (Lei 8.036 art. 15): a soma das duas bases fecha exatamente o bruto.
DO $ck$
BEGIN
    ALTER TABLE public.folha_13_calculo
        ADD CONSTRAINT folha_13_calculo_base_fgts_ck
        CHECK (COALESCE(base_fgts, 0) <= COALESCE(valor_bruto, 0)) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

-- O adiantamento deduzido não pode superar o próprio 13º.
DO $ck$
BEGIN
    ALTER TABLE public.folha_13_calculo
        ADD CONSTRAINT folha_13_calculo_primeira_ck
        CHECK (COALESCE(valor_primeira_parcela, 0) <= COALESCE(valor_bruto, 0)) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

-- ── Conferência final (o editor só mostra o último resultado) ─────────
WITH esperado AS MATERIALIZED (
    SELECT * FROM (VALUES
        ('coluna competencia',        'coluna', 'competencia'),
        ('coluna data_prevista',      'coluna', 'data_prevista'),
        ('coluna data_pagamento',     'coluna', 'data_pagamento'),
        ('coluna aprovado_em',        'coluna', 'aprovado_em'),
        ('coluna reaberto_de',        'coluna', 'reaberto_de'),
        ('coluna lote_id',            'coluna', 'lote_id'),
        ('trava de situacao',         'check',  'folha_13_calculo_status_ck'),
        ('trava de encargo na 1a parcela', 'check', 'folha_13_calculo_encargos_2a_ck'),
        ('trava de base de FGTS',     'check',  'folha_13_calculo_base_fgts_ck'),
        ('unicidade da parcela viva', 'indice', 'folha_13_calculo_parcela_viva_uq'),
        ('camada de perfil',          'politica','perfil_restringe_leitura_folha_13_calculo'),
        ('trava de calculo fechado',  'gatilho','trg_decimo_terceiro_trava_fechado'),
        ('funcao prazo legal',        'funcao', 'decimo_terceiro_prazo_legal'),
        ('funcao INSS',               'funcao', 'decimo_terceiro_inss'),
        ('funcao IRRF',               'funcao', 'decimo_terceiro_irrf'),
        ('funcao calcular parcela',   'funcao', 'decimo_terceiro_calcular'),
        ('funcao lote',               'funcao', 'decimo_terceiro_lote'),
        ('funcao aprovar',            'funcao', 'decimo_terceiro_aprovar'),
        ('funcao pagar',              'funcao', 'decimo_terceiro_pagar'),
        ('funcao reabrir',            'funcao', 'decimo_terceiro_reabrir')
    ) AS t(item, especie, nome)
)
SELECT e.item,
       CASE WHEN
         CASE e.especie
           WHEN 'coluna'   THEN EXISTS (SELECT 1 FROM information_schema.columns
                                         WHERE table_schema='public' AND table_name='folha_13_calculo'
                                           AND column_name=e.nome)
           WHEN 'check'    THEN EXISTS (SELECT 1 FROM pg_constraint WHERE conname=e.nome)
           WHEN 'indice'   THEN EXISTS (SELECT 1 FROM pg_class WHERE relname=e.nome AND relkind='i')
           WHEN 'politica' THEN EXISTS (SELECT 1 FROM pg_policies WHERE policyname=e.nome)
           WHEN 'gatilho'  THEN EXISTS (SELECT 1 FROM pg_trigger WHERE tgname=e.nome AND NOT tgisinternal)
           WHEN 'funcao'   THEN EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                                         WHERE n.nspname='public' AND p.proname=e.nome)
         END
       THEN 'OK' ELSE 'FALTOU' END AS situacao,
       CASE WHEN
         CASE e.especie
           WHEN 'coluna'   THEN EXISTS (SELECT 1 FROM information_schema.columns
                                         WHERE table_schema='public' AND table_name='folha_13_calculo'
                                           AND column_name=e.nome)
           WHEN 'check'    THEN EXISTS (SELECT 1 FROM pg_constraint WHERE conname=e.nome)
           WHEN 'indice'   THEN EXISTS (SELECT 1 FROM pg_class WHERE relname=e.nome AND relkind='i')
           WHEN 'politica' THEN EXISTS (SELECT 1 FROM pg_policies WHERE policyname=e.nome)
           WHEN 'gatilho'  THEN EXISTS (SELECT 1 FROM pg_trigger WHERE tgname=e.nome AND NOT tgisinternal)
           WHEN 'funcao'   THEN EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                                         WHERE n.nspname='public' AND p.proname=e.nome)
         END
       THEN NULL ELSE 'Objeto nao encontrado apos a execucao' END AS erro_tecnico
  FROM esperado e
 UNION ALL
-- Este script recria decimo_terceiro_calcular na versao SEM a politica do
-- adiantamento (que vem no script seguinte). Reaplicar este script
-- sozinho, depois da entrega completa, faria a politica escolhida pela
-- empresa deixar de valer em silencio. A linha abaixo avisa quando isso
-- acontecer: a correcao e reaplicar o script do adiantamento na sequencia.
SELECT 'a politica do adiantamento continua valendo',
       CASE WHEN NOT EXISTS (SELECT 1 FROM information_schema.columns
                              WHERE table_schema='public' AND table_name='decimo_terceiro_config'
                                AND column_name='adiantamento_base') THEN 'OK'
            WHEN position('adiantamento_base' in p.prosrc) > 0 THEN 'OK'
            ELSE 'RESOLVER' END,
       CASE WHEN NOT EXISTS (SELECT 1 FROM information_schema.columns
                              WHERE table_schema='public' AND table_name='decimo_terceiro_config'
                                AND column_name='adiantamento_base') THEN NULL
            WHEN position('adiantamento_base' in p.prosrc) > 0 THEN NULL
            ELSE 'este script devolveu o calculo a versao anterior a politica do adiantamento — '
                 || 'rode em seguida o script_13o_adiantamento_e_media_sumula347.sql' END
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='decimo_terceiro_calcular'
 UNION ALL
SELECT 'sonda de QA DEC13-070 ajustada a trava de pagamento',
       CASE WHEN position('data_pagamento' in p.prosrc) > 0 THEN 'OK' ELSE 'FALTOU' END,
       CASE WHEN position('data_pagamento' in p.prosrc) > 0 THEN NULL
            ELSE 'qa_caso_dec13_070 ainda grava pago sem data e vai acusar erro na bateria' END
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='qa_caso_dec13_070'
 UNION ALL
-- Se a unicidade nao pode ser criada, aqui esta o motivo, nomeado.
SELECT format('DUPLICADO: %s, ano %s, parcela %s', d.colaborador_nome, d.ano, d.parcela),
       'RESOLVER',
       format('%s calculos vivos da mesma parcela — cancele os que sobram e rode o script de novo', d.qtd)
  FROM (
        SELECT colaborador_nome, ano, parcela, count(*) AS qtd
          FROM public.folha_13_calculo
         WHERE status <> 'cancelado'
           AND colaborador_cpf IS NOT NULL
           AND regexp_replace(colaborador_cpf, '[^0-9]', '', 'g') <> ''
         GROUP BY tenant_id, ano, parcela,
                  regexp_replace(colaborador_cpf, '[^0-9]', '', 'g'),
                  COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid),
                  colaborador_nome
        HAVING count(*) > 1
       ) d
 ORDER BY 2 DESC, 1;
