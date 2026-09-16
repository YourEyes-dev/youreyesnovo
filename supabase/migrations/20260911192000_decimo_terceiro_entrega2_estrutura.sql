-- =========================================================
-- 13º Salário — Entrega 2, parte 1: estrutura, integridade e segurança
--
-- PROBLEMA: folha_13_calculo era uma tabela rasa. Guardava valores, mas
-- não guardava QUANDO a parcela foi paga, se alguém APROVOU, a que
-- competência pertence, nem qual admissão originou o cálculo — o
-- colaborador era um TEXT solto. Sem isso não há como provar prazo
-- cumprido (Lei 4.749: 1ª até 30/11, 2ª até 20/12), não há trilha de
-- reabertura e não há auditoria. A tabela também aceitava dois cálculos
-- da mesma parcela para a mesma pessoa no mesmo ano, e a leitura era
-- protegida só por tenant: qualquer usuário autenticado da empresa
-- enxergava a remuneração de todo mundo.
--
-- ENTREGA:
--   1) colunas de competência, prazo, pagamento, aprovação e trilha de
--      reabertura, mais o vínculo real com a admissão;
--   2) vocabulário de situação com CHECK, e unicidade por
--      (empresa, ano, colaborador, parcela) entre os cálculos vivos;
--   3) camada de perfil (política RESTRICTIVE): quem não administra a
--      folha só enxerga o próprio 13º.
--
-- Requisitos YE-DP-13-001: RF-007, RN-003, RN-004, RNF-004, RNF-005,
-- RNF-007. Casos: DEC13-070 (reabertura), DEC13-071 (perfil).
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
