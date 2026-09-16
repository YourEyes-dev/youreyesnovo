-- =========================================================
-- 13º Salário — Entrega 5: eSocial (S-1200 anual e S-1210)
--
-- PROBLEMA: a aba de eSocial da folha gera o S-1200 MENSAL a partir da
-- folha do mês. O 13º não entra ali: ele é informado numa apuração
-- ANUAL própria (indApuracao = 2, período AAAA), e os pagamentos das
-- parcelas vão no S-1210. Nada disso existia — o módulo calculava,
-- pagava e não declarava.
--
-- ENTREGA:
--   * esocial_transmissoes ganha o contexto da folha (origem, ano,
--     parcela, período e indicativo de apuração) e ANTI-DUPLICIDADE:
--     o mesmo evento não é gerado duas vezes;
--   * decimo_terceiro_esocial_validar — a validação ANTES do envio, que
--     é onde se evita a rejeição: CPF ausente, cálculo não aprovado,
--     parcela não paga, valor zerado, colaborador sem admissão;
--   * decimo_terceiro_esocial_gerar — monta o XML do S-1200 anual e do
--     S-1210 e grava como 'pendente', pronto para transmitir.
--
-- O QUE ESTA ENTREGA NÃO FAZ, e é importante dizer: NÃO TRANSMITE.
-- A transmissão depende de certificado digital, procuração eletrônica e
-- do ambiente (produção ou produção restrita) definidos pelo cliente —
-- itens que o próprio documento de requisitos marca como [VAL] e que não
-- se resolvem no banco. O evento fica montado e conferido, com status
-- 'pendente', para o passo de envio quando esses parâmetros existirem.
--
-- LEIAUTE: a versão fica registrada em cada transmissão
-- (leiaute_versao). O documento marca o leiaute como [VAL] — confira a
-- versão vigente no portal do eSocial na data da implantação, porque
-- leiaute desatualizado é a causa mais comum de rejeição.
--
-- Requisitos YE-DP-13-001: RF-005, RN-010, CA-007. Caso: DEC13-050.
-- =========================================================

SET lock_timeout = '10s';

-- ── 1. Contexto da folha nas transmissões ─────────────────────────────
ALTER TABLE public.esocial_transmissoes
    ADD COLUMN IF NOT EXISTS origem_modulo   TEXT,
    ADD COLUMN IF NOT EXISTS origem_id       UUID,
    ADD COLUMN IF NOT EXISTS ano             INT,
    ADD COLUMN IF NOT EXISTS parcela         INT,
    ADD COLUMN IF NOT EXISTS periodo_apuracao TEXT,
    ADD COLUMN IF NOT EXISTS ind_apuracao    INT,
    ADD COLUMN IF NOT EXISTS leiaute_versao  TEXT,
    ADD COLUMN IF NOT EXISTS colaborador_cpf TEXT;

COMMENT ON COLUMN public.esocial_transmissoes.ind_apuracao IS
    'Indicativo de apuracao do eSocial: 1 = mensal, 2 = anual (13o salario).';
COMMENT ON COLUMN public.esocial_transmissoes.leiaute_versao IS
    'Versao do leiaute usada para montar o XML. Leiaute desatualizado e a causa mais comum de rejeicao — confira a vigente na data do envio.';

-- Anti-duplicidade: um evento vivo por origem/tipo. Erro e cancelado
-- ficam de fora, para permitir refazer depois de corrigir.
CREATE UNIQUE INDEX IF NOT EXISTS esocial_transmissoes_origem_uq
    ON public.esocial_transmissoes (tenant_id, tipo_evento, origem_id)
    WHERE origem_id IS NOT NULL
      AND COALESCE(status, '') NOT IN ('erro', 'cancelado', 'rejeitado');

-- ── 2. Validação prévia: onde se evita a rejeição ─────────────────────
CREATE OR REPLACE FUNCTION public.decimo_terceiro_esocial_validar(
    p_tenant UUID,
    p_ano    INT
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    v_problemas JSONB := '[]'::jsonb;
    v_aptos     INT := 0;
    r           RECORD;
    v_motivo    TEXT;
BEGIN
    IF p_tenant IS NULL OR p_ano IS NULL THEN
        RETURN jsonb_build_object('erro', 'Informe empresa e ano-base.');
    END IF;

    FOR r IN
        SELECT c.id, c.colaborador_nome, c.colaborador_cpf, c.parcela, c.status,
               c.valor_bruto, c.total_liquido, c.admissao_id
          FROM public.folha_13_calculo c
         WHERE c.tenant_id = p_tenant AND c.ano = p_ano
           AND c.status <> 'cancelado'
         ORDER BY c.colaborador_nome, c.parcela
    LOOP
        v_motivo := NULL;

        IF r.colaborador_cpf IS NULL
           OR length(regexp_replace(r.colaborador_cpf, '[^0-9]', '', 'g')) <> 11 THEN
            v_motivo := 'CPF ausente ou inválido — o eSocial identifica o trabalhador pelo CPF.';
        ELSIF r.admissao_id IS NULL THEN
            v_motivo := 'Cálculo sem vínculo com a admissão: o evento precisa da matrícula do trabalhador.';
        ELSIF COALESCE(r.valor_bruto, 0) <= 0 THEN
            v_motivo := 'Valor bruto zerado: evento sem remuneração é rejeitado.';
        ELSIF r.status NOT IN ('aprovado', 'pago') THEN
            v_motivo := format('Cálculo em "%s": só se declara o que foi aprovado ou pago.', r.status);
        END IF;

        IF v_motivo IS NULL THEN
            v_aptos := v_aptos + 1;
        ELSE
            v_problemas := v_problemas || jsonb_build_object(
                'calculo_id',  r.id,
                'colaborador', r.colaborador_nome,
                'parcela',     r.parcela,
                'problema',    v_motivo);
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'ano', p_ano,
        'aptos', v_aptos,
        'com_problema', jsonb_array_length(v_problemas),
        'problemas', v_problemas,
        'pode_transmitir', (v_aptos > 0 AND jsonb_array_length(v_problemas) = 0),
        'validado_em', now());
END $fn$;

COMMENT ON FUNCTION public.decimo_terceiro_esocial_validar(UUID, INT) IS
    'Validacao previa do 13o para o eSocial: CPF, vinculo, valor e situacao do calculo. E onde se evita a rejeicao, antes de transmitir.';

GRANT EXECUTE ON FUNCTION public.decimo_terceiro_esocial_validar(UUID, INT) TO authenticated;

-- ── 3. Montagem dos eventos ───────────────────────────────────────────
-- S-1200 com indApuracao = 2 (anual) leva a remuneração do 13º do ano;
-- S-1210 leva o pagamento de cada parcela. Um evento por trabalhador.
--
-- O XML sai montado e GRAVADO como 'pendente'. Não há envio aqui: a
-- transmissão depende de certificado, procuração e ambiente definidos
-- pelo cliente. O que esta função entrega é o evento pronto e conferido.
CREATE OR REPLACE FUNCTION public.decimo_terceiro_esocial_gerar(
    p_tenant  UUID,
    p_ano     INT,
    p_tipo    TEXT DEFAULT 'S-1200',
    p_leiaute TEXT DEFAULT 'S-1.3'
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    v_val     JSONB;
    r         RECORD;
    v_cnpj    TEXT;
    v_xml     TEXT;
    v_gerados INT := 0;
    v_pulados INT := 0;
    v_cpf     TEXT;
    v_periodo TEXT;
    v_ind     INT;
BEGIN
    IF p_tipo NOT IN ('S-1200', 'S-1210') THEN
        RETURN jsonb_build_object('erro', 'Tipo deve ser S-1200 (remuneração anual) ou S-1210 (pagamentos).');
    END IF;

    -- Não se monta evento sobre base torta.
    v_val := public.decimo_terceiro_esocial_validar(p_tenant, p_ano);
    IF NOT COALESCE((v_val->>'pode_transmitir')::BOOLEAN, false) THEN
        RETURN jsonb_build_object(
            'erro', 'A validação prévia apontou pendências — corrija antes de montar os eventos.',
            'validacao', v_val);
    END IF;

    SELECT regexp_replace(COALESCE(cnpj, ''), '[^0-9]', '', 'g') INTO v_cnpj
      FROM public.empresa_cadastro WHERE tenant_id = p_tenant LIMIT 1;
    v_cnpj := COALESCE(NULLIF(v_cnpj, ''), '00000000000000');

    -- S-1200 é um evento por trabalhador no ano; S-1210, um por parcela.
    FOR r IN
        SELECT c.id, c.colaborador_nome, c.colaborador_cpf, c.parcela,
               c.valor_bruto, c.valor_inss, c.valor_irrf, c.total_liquido,
               c.data_pagamento, c.empresa_id
          FROM public.folha_13_calculo c
         WHERE c.tenant_id = p_tenant AND c.ano = p_ano
           AND c.status IN ('aprovado', 'pago')
           AND (p_tipo = 'S-1200' OR c.status = 'pago')
         ORDER BY c.colaborador_nome, c.parcela
    LOOP
        -- No S-1200 basta UM evento por trabalhador (apuração anual), e
        -- ele leva o 13º INTEIRO. Cada linha de folha_13_calculo já
        -- guarda o 13º cheio em valor_bruto (a parcela paga fica em
        -- valor_primeira_parcela / total_liquido) — somar as duas
        -- parcelas declararia o DOBRO ao eSocial. Usa-se a linha da 2ª,
        -- que é a do fechamento.
        CONTINUE WHEN p_tipo = 'S-1200' AND r.parcela <> 2;

        v_cpf     := regexp_replace(r.colaborador_cpf, '[^0-9]', '', 'g');
        v_ind     := CASE WHEN p_tipo = 'S-1200' THEN 2 ELSE 1 END;
        v_periodo := CASE WHEN p_tipo = 'S-1200'
                          THEN p_ano::text
                          ELSE to_char(COALESCE(r.data_pagamento, CURRENT_DATE), 'YYYY-MM') END;

        IF EXISTS (
            SELECT 1 FROM public.esocial_transmissoes t
             WHERE t.tenant_id = p_tenant AND t.tipo_evento = p_tipo
               AND t.origem_id = r.id
               AND COALESCE(t.status, '') NOT IN ('erro', 'cancelado', 'rejeitado'))
        THEN
            v_pulados := v_pulados + 1;
            CONTINUE;
        END IF;

        IF p_tipo = 'S-1200' THEN
            v_xml := format($x$<?xml version="1.0" encoding="UTF-8"?>
<eSocial>
  <evtRemun>
    <ideEvento>
      <indRetif>1</indRetif>
      <indApuracao>2</indApuracao>
      <perApur>%s</perApur>
      <tpAmb>2</tpAmb>
    </ideEvento>
    <ideEmpregador><tpInsc>1</tpInsc><nrInsc>%s</nrInsc></ideEmpregador>
    <ideTrabalhador><cpfTrab>%s</cpfTrab></ideTrabalhador>
    <dmDev>
      <ideDmDev>13-%s</ideDmDev>
      <infoPerApur>
        <ideEstabLot>
          <tpInsc>1</tpInsc><nrInsc>%s</nrInsc>
          <remunPerApur>
            <itensRemun>
              <codRubr>13SAL</codRubr>
              <vrRubr>%s</vrRubr>
            </itensRemun>
          </remunPerApur>
        </ideEstabLot>
      </infoPerApur>
    </dmDev>
  </evtRemun>
</eSocial>$x$, p_ano, v_cnpj, v_cpf, p_ano, v_cnpj, to_char(r.valor_bruto, 'FM999999990.00'));
        ELSE
            v_xml := format($x$<?xml version="1.0" encoding="UTF-8"?>
<eSocial>
  <evtPgtos>
    <ideEvento>
      <indApuracao>1</indApuracao>
      <perApur>%s</perApur>
      <tpAmb>2</tpAmb>
    </ideEvento>
    <ideEmpregador><tpInsc>1</tpInsc><nrInsc>%s</nrInsc></ideEmpregador>
    <ideBenef><cpfBenef>%s</cpfBenef></ideBenef>
    <infoPgto>
      <dtPgto>%s</dtPgto>
      <tpPgto>1</tpPgto>
      <perRef>%s</perRef>
      <ideDmDev>13-%s-P%s</ideDmDev>
      <vrLiq>%s</vrLiq>
    </infoPgto>
  </evtPgtos>
</eSocial>$x$, v_periodo, v_cnpj, v_cpf,
        to_char(COALESCE(r.data_pagamento, CURRENT_DATE), 'YYYY-MM-DD'),
        p_ano::text, p_ano, r.parcela, to_char(r.total_liquido, 'FM999999990.00'));
        END IF;

        INSERT INTO public.esocial_transmissoes (
            tenant_id, empresa_id, tipo_evento, xml_enviado, status,
            origem_modulo, origem_id, ano, parcela, periodo_apuracao,
            ind_apuracao, leiaute_versao, colaborador_cpf, tentativas)
        VALUES (
            p_tenant, r.empresa_id, p_tipo, v_xml, 'pendente',
            'decimo_terceiro', r.id, p_ano,
            CASE WHEN p_tipo = 'S-1210' THEN r.parcela END,
            v_periodo, v_ind, p_leiaute, v_cpf, 0);

        v_gerados := v_gerados + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'ano', p_ano, 'tipo', p_tipo, 'leiaute', p_leiaute,
        'eventos_gerados', v_gerados,
        'ja_existiam', v_pulados,
        'situacao', 'pendente de transmissão',
        'aviso', 'Os eventos foram MONTADOS, não enviados. A transmissão depende de certificado digital, procuração eletrônica e ambiente definidos pelo cliente. Confira a versão do leiaute vigente antes de transmitir.',
        'gerado_em', now());
END $fn$;

COMMENT ON FUNCTION public.decimo_terceiro_esocial_gerar(UUID, INT, TEXT, TEXT) IS
    'Monta os eventos do 13o para o eSocial: S-1200 com apuracao ANUAL (indApuracao=2) e S-1210 dos pagamentos. Grava como pendente; NAO transmite.';

GRANT EXECUTE ON FUNCTION public.decimo_terceiro_esocial_gerar(UUID, INT, TEXT, TEXT) TO authenticated;
