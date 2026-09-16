-- ============================================================================
-- ENTREGA — Ferias: media das variaveis do art. 142 apurada da folha
--
-- Colar INTEIRO no SQL Editor do projeto de PRODUCAO e executar uma vez.
--
-- POR QUE
--   A media das variaveis das ferias era um campo digitado, que nascia zerado.
--   Quem recebe hora extra habitual, comissao ou adicional leva a MEDIA para as
--   ferias (CLT art. 142); calcular so sobre o fixo paga a menos — em silencio,
--   e sem memoria nada se audita. Primeiro item da revisao do modulo Ferias
--   contra o documento de requisitos YE-DP-FERIAS-001 (RF-004, RN-007, CA-006).
--
-- O QUE MUDA
--   1) ferias_config ganha os parametros da media (media_base, media_divisor,
--      media_vigencia_inicio), por empresa e com vigencia;
--   2) ferias_media_variaveis(...) apura a media a partir dos lancamentos da
--      folha, somando SO as rubricas marcadas com incide_ferias, e devolve a
--      memoria (competencia a competencia, rubrica a rubrica);
--   3) folha_ferias_calculo ganha media_origem (apurada | apurada_ajustada |
--      manual);
--   4) a rotina de QA FERIAS-033 passa a conferir o motor, nao so a existencia.
--
--   Padrao (decisao do dono do produto, 01/09/2026): janela dos 12 meses do
--   proprio periodo aquisitivo, dividida pelos meses do periodo em que houve
--   folha (mes sem variavel entra como zero; quem foi admitido no meio nao e
--   dividido por 12). As duas regras ficam parametrizaveis por empresa.
--
-- SEGURANCA DO DADO
--   So CRIA coisa nova (colunas com IF NOT EXISTS, funcoes com CREATE OR
--   REPLACE, restricoes idempotentes). Nao altera nem apaga nenhuma linha
--   existente, entao nao ha copia de seguranca a fazer. Rodar duas vezes nao
--   quebra nem duplica.
--
-- PROVADO em replica local (massa ficticia: 9 meses de hora extra e 3 de
--   comissao, mais uma rubrica que NAO integra ferias):
--     • janela do aquisitivo, divisor por meses do periodo -> 375,00
--       (soma 4.500 / 12), com a rubrica nao integrante corretamente de fora;
--     • janela parcial de 3 meses -> 300,00;
--     • CPF sem folha e empresa sem rubrica marcada -> media zero COM aviso;
--     • parametro invalido rejeitado pela restricao; reaplicacao sem erro.
--
-- DEPENDE DE CONFIGURACAO: a media so encontra valores se as rubricas
--   variaveis estiverem marcadas como integrantes das ferias no cadastro de
--   rubricas. Quando nao estao, a apuracao devolve zero com aviso explicativo.
--
-- A TELA (aba Ferias no Financeiro) so muda apos Publicar no Lovable.
-- ============================================================================

SET lock_timeout = '10s';

-- ── 1. Parametros da media (por empresa, com vigencia) ────────────────────
ALTER TABLE public.ferias_config
    ADD COLUMN IF NOT EXISTS media_base TEXT NOT NULL DEFAULT 'aquisitivo',
    ADD COLUMN IF NOT EXISTS media_divisor TEXT NOT NULL DEFAULT 'meses_do_periodo',
    ADD COLUMN IF NOT EXISTS media_vigencia_inicio DATE NOT NULL DEFAULT '2026-01-01';

DO $ck$
BEGIN
    ALTER TABLE public.ferias_config
        ADD CONSTRAINT ferias_config_media_base_ck
        CHECK (media_base IN ('aquisitivo', 'anteriores_ao_gozo'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

DO $ck$
BEGIN
    ALTER TABLE public.ferias_config
        ADD CONSTRAINT ferias_config_media_divisor_ck
        CHECK (media_divisor IN ('meses_do_periodo', 'meses_com_valor'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

-- ── 2. Apuracao da media (somente leitura) ────────────────────────────────
CREATE OR REPLACE FUNCTION public.ferias_media_variaveis(
    p_tenant            UUID,
    p_cpf               TEXT,
    p_aquisitivo_inicio DATE,
    p_aquisitivo_fim    DATE,
    p_inicio_gozo       DATE DEFAULT NULL,
    p_empresa           UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    v_base          TEXT := 'aquisitivo';
    v_divisor_regra TEXT := 'meses_do_periodo';
    v_vigencia      DATE := '2026-01-01';
    v_cpf           TEXT := regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
    v_ini           TEXT;
    v_fim           TEXT;
    v_total         NUMERIC(14,2) := 0;
    v_meses_folha   INTEGER := 0;
    v_meses_valor   INTEGER := 0;
    v_divisor       INTEGER := 0;
    v_media         NUMERIC(14,2) := 0;
    v_rubricas_mkd  INTEGER := 0;
    v_competencias  JSONB := '[]'::jsonb;
    v_rubricas      JSONB := '[]'::jsonb;
    v_avisos        TEXT[] := ARRAY[]::TEXT[];
BEGIN
    IF p_tenant IS NULL OR v_cpf = '' OR p_aquisitivo_inicio IS NULL OR p_aquisitivo_fim IS NULL THEN
        RETURN jsonb_build_object(
            'media', 0, 'total', 0, 'meses_divisor', 0,
            'avisos', to_jsonb(ARRAY['Informe colaborador e periodo aquisitivo para apurar a media.'])
        );
    END IF;

    SELECT c.media_base, c.media_divisor, c.media_vigencia_inicio
      INTO v_base, v_divisor_regra, v_vigencia
      FROM public.ferias_config c
     WHERE c.tenant_id = p_tenant
       AND (c.empresa_id = p_empresa OR (p_empresa IS NULL AND c.empresa_id IS NULL))
     LIMIT 1;

    IF NOT FOUND THEN
        SELECT c.media_base, c.media_divisor, c.media_vigencia_inicio
          INTO v_base, v_divisor_regra, v_vigencia
          FROM public.ferias_config c
         WHERE c.tenant_id = p_tenant AND c.empresa_id IS NULL
         LIMIT 1;
    END IF;

    v_base          := coalesce(v_base, 'aquisitivo');
    v_divisor_regra := coalesce(v_divisor_regra, 'meses_do_periodo');
    v_vigencia      := coalesce(v_vigencia, DATE '2026-01-01');

    IF v_base = 'anteriores_ao_gozo' AND p_inicio_gozo IS NOT NULL THEN
        v_fim := to_char((date_trunc('month', p_inicio_gozo) - INTERVAL '1 month'), 'YYYY-MM');
        v_ini := to_char((date_trunc('month', p_inicio_gozo) - INTERVAL '12 months'), 'YYYY-MM');
    ELSE
        IF v_base = 'anteriores_ao_gozo' THEN
            v_avisos := array_append(v_avisos, 'Sem data de inicio do gozo: a media foi apurada pelo periodo aquisitivo.');
            v_base := 'aquisitivo';
        END IF;
        v_ini := to_char(p_aquisitivo_inicio, 'YYYY-MM');
        v_fim := to_char(p_aquisitivo_fim,    'YYYY-MM');
    END IF;

    SELECT count(*) INTO v_rubricas_mkd
      FROM public.folha_rubricas r
     WHERE r.tenant_id = p_tenant AND r.incide_ferias AND r.ativa;

    IF v_rubricas_mkd = 0 THEN
        v_avisos := array_append(v_avisos, 'Nenhuma rubrica esta marcada como integrante das ferias no cadastro de rubricas — a media sai zero ate alguem marcar (hora extra, comissao, adicionais).');
    END IF;

    WITH janela AS MATERIALIZED (
        SELECT l.valor, pe.competencia,
               coalesce(l.rubrica_codigo, r.codigo_interno) AS codigo,
               coalesce(r.descricao, l.rubrica_descricao)   AS descricao
          FROM public.folha_lancamentos l
          JOIN public.folha_periodos pe ON pe.id = l.periodo_id
          JOIN public.folha_rubricas  r ON r.id = l.rubrica_id
         WHERE l.tenant_id = p_tenant
           AND regexp_replace(coalesce(l.colaborador_cpf, ''), '\D', '', 'g') = v_cpf
           AND pe.competencia BETWEEN v_ini AND v_fim
           AND r.incide_ferias
           AND r.ativa
           AND r.tipo = 'PROVENTO'
    ),
    por_competencia AS MATERIALIZED (
        SELECT competencia, sum(valor)::NUMERIC(14,2) AS valor
          FROM janela GROUP BY competencia
    ),
    por_rubrica AS MATERIALIZED (
        SELECT codigo, descricao, sum(valor)::NUMERIC(14,2) AS valor
          FROM janela GROUP BY codigo, descricao
    )
    SELECT
        coalesce((SELECT sum(valor) FROM por_competencia), 0),
        coalesce((SELECT count(*) FROM por_competencia WHERE valor > 0), 0),
        coalesce((SELECT jsonb_agg(jsonb_build_object('competencia', competencia, 'valor', valor)
                                   ORDER BY competencia) FROM por_competencia), '[]'::jsonb),
        coalesce((SELECT jsonb_agg(jsonb_build_object('codigo', codigo, 'descricao', descricao, 'valor', valor)
                                   ORDER BY valor DESC) FROM por_rubrica), '[]'::jsonb)
      INTO v_total, v_meses_valor, v_competencias, v_rubricas;

    SELECT count(DISTINCT pe.competencia) INTO v_meses_folha
      FROM public.folha_itens i
      JOIN public.folha_periodos pe ON pe.id = i.periodo_id
     WHERE i.tenant_id = p_tenant
       AND regexp_replace(coalesce(i.colaborador_cpf, ''), '\D', '', 'g') = v_cpf
       AND pe.competencia BETWEEN v_ini AND v_fim;

    IF v_divisor_regra = 'meses_com_valor' THEN
        v_divisor := v_meses_valor;
    ELSE
        v_divisor := CASE WHEN v_meses_folha > 0 THEN v_meses_folha ELSE v_meses_valor END;
        IF v_meses_folha = 0 AND v_meses_valor > 0 THEN
            v_avisos := array_append(v_avisos, 'Nao ha folha fechada do colaborador nesta janela; a media foi dividida pelos meses com valor.');
        END IF;
    END IF;

    IF v_divisor > 0 THEN
        v_media := round(v_total / v_divisor, 2);
    END IF;

    IF v_total = 0 AND v_rubricas_mkd > 0 THEN
        v_avisos := array_append(v_avisos, 'Nenhum lancamento de rubrica variavel encontrado na janela — confira se a folha do periodo foi importada.');
    END IF;

    RETURN jsonb_build_object(
        'media',              v_media,
        'total',              v_total,
        'meses_divisor',      v_divisor,
        'meses_com_folha',    v_meses_folha,
        'meses_com_valor',    v_meses_valor,
        'base',               v_base,
        'divisor_regra',      v_divisor_regra,
        'janela_inicio',      v_ini,
        'janela_fim',         v_fim,
        'parametros_vigencia', v_vigencia,
        'fundamento',         'CLT art. 142',
        'apurado_em',         now(),
        'competencias',       v_competencias,
        'rubricas',           v_rubricas,
        'avisos',             to_jsonb(v_avisos)
    );
END $fn$;

GRANT EXECUTE ON FUNCTION public.ferias_media_variaveis(UUID, TEXT, DATE, DATE, DATE, UUID) TO authenticated;

-- ── 3. Origem da media no calculo gravado ─────────────────────────────────
ALTER TABLE public.folha_ferias_calculo
    ADD COLUMN IF NOT EXISTS media_origem TEXT NOT NULL DEFAULT 'manual';

DO $ck$
BEGIN
    ALTER TABLE public.folha_ferias_calculo
        ADD CONSTRAINT folha_ferias_calculo_media_origem_ck
        CHECK (media_origem IN ('apurada', 'manual', 'apurada_ajustada'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

-- ── 4. QA — FERIAS-033 confere o motor, nao so a existencia ───────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ferias_033()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
    r          public.qa_retorno;
    v_existe   BOOLEAN;
    v_sonda    JSONB;
    v_faltando TEXT[];
    v_param    BOOLEAN;
BEGIN
    r.passo_ordem := 1;
    r.passo_acao  := 'AUDITORIA (somente leitura): a media das variaveis do art. 142 e apurada da folha, com memoria?';
    r.esperado    := 'Funcao que soma as rubricas marcadas como integrantes das ferias na janela do periodo e devolve media + memoria competencia a competencia';

    SELECT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'ferias_media_variaveis'
    ) INTO v_existe;

    IF NOT v_existe THEN
        r.situacao := 'falhou';
        r.obtido := 'ACHADO CENTRAL do documento de requisitos: a media das variaveis nao e '
                 || 'apurada — o campo e digitado e nasce zerado. Correcao: apuracao '
                 || 'deterministica a partir das rubricas marcadas com incide_ferias, com '
                 || 'memoria exportavel (RF-004 e RNF-001 do documento).';
        RETURN r;
    END IF;

    v_sonda := public.ferias_media_variaveis(
        '00000000-0000-0000-0000-000000000000'::uuid,
        '00000000000', DATE '2025-01-01', DATE '2025-12-31'
    );

    SELECT array_agg(chave) INTO v_faltando
      FROM unnest(ARRAY['media','total','meses_divisor','base','divisor_regra',
                        'janela_inicio','janela_fim','competencias','rubricas',
                        'parametros_vigencia','fundamento']) AS chave
     WHERE NOT (v_sonda ? chave);

    SELECT public.qa_col_existe('ferias_config', 'media_base') IS NOT NULL
       AND public.qa_col_existe('ferias_config', 'media_divisor') IS NOT NULL
      INTO v_param;

    IF v_faltando IS NOT NULL THEN
        r.situacao := 'falhou';
        r.obtido := format('A apuracao existe, mas a memoria esta incompleta: faltam %s no '
                 || 'retorno. Sem esses campos o valor nao se reproduz depois (RNF-008).',
                 array_to_string(v_faltando, ', '));
    ELSIF NOT coalesce(v_param, false) THEN
        r.situacao := 'falhou';
        r.obtido := 'A apuracao existe e devolve memoria, mas a base e o divisor nao sao '
                 || 'parametrizaveis por empresa (ferias_config.media_base / media_divisor).';
    ELSE
        r.situacao := 'passou';
        r.obtido := format('Media apurada da folha por ferias_media_variaveis, com memoria '
                 || 'completa (janela %s a %s, base "%s", divisor "%s") e parametros por '
                 || 'empresa com vigencia.',
                 v_sonda->>'janela_inicio', v_sonda->>'janela_fim',
                 v_sonda->>'base', v_sonda->>'divisor_regra');
    END IF;

    RETURN r;
EXCEPTION WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── 5. Conferencia final (o editor mostra so o ultimo resultado) ──────────
SELECT
    (SELECT CASE WHEN to_regprocedure(
        'public.ferias_media_variaveis(uuid,text,date,date,date,uuid)') IS NOT NULL
        THEN 'sim' ELSE 'NAO — verificar' END)                          AS funcao_instalada,
    (SELECT CASE WHEN public.qa_col_existe('ferias_config','media_base') IS NOT NULL
                  AND public.qa_col_existe('ferias_config','media_divisor') IS NOT NULL
        THEN 'sim' ELSE 'NAO — verificar' END)                          AS parametros_por_empresa,
    (SELECT CASE WHEN public.qa_col_existe('folha_ferias_calculo','media_origem') IS NOT NULL
        THEN 'sim' ELSE 'NAO — verificar' END)                          AS media_origem_no_calculo,
    (SELECT situacao FROM public.qa_caso_ferias_033())                  AS qa_ferias_033,
    (SELECT obtido   FROM public.qa_caso_ferias_033())                  AS qa_ferias_033_detalhe;
