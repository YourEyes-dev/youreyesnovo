-- =========================================================
-- Ferias coletivas (RF-007 / RN-011 / CA-010) — arts. 139 a 141 da CLT
--
-- PROBLEMA: nao havia fluxo de ferias coletivas. O documento YE-DP-FERIAS-001
-- (RF-007) pede: programar por setor, ate 2 periodos anuais de no minimo 10
-- dias corridos, comunicar ao MTE e ao sindicato com 15 dias de antecedencia
-- (e afixar/avisar os empregados), e tratar quem tem menos de 12 meses de
-- casa com proporcionais e novo aquisitivo (art. 140).
--
-- DECISOES DO DONO DO PRODUTO (03/09/2026):
--   • abrangencia por SETOR (admissoes.departamento);
--   • comunicacoes geradas como DOCUMENTOS arquivados, com o prazo de 15 dias
--     controlado (o envio/protocolo e do RH);
--   • novatos: proporcionais ao tempo de casa + novo aquisitivo (art. 140).
--
-- Casos de teste: FERIAS-060, FERIAS-061, FERIAS-062.
-- =========================================================

SET lock_timeout = '10s';

-- ── 1. O programa de coletivas (por setor, ate 2 periodos) ────────────────
CREATE TABLE IF NOT EXISTS public.ferias_coletivas (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id    UUID NOT NULL,
    empresa_id   UUID,
    ano          INTEGER NOT NULL,
    departamento TEXT NOT NULL,        -- setor (admissoes.departamento)

    -- Ate 2 periodos (art. 139, §1º); cada um >= 10 dias corridos.
    p1_inicio DATE NOT NULL, p1_fim DATE NOT NULL,
    p2_inicio DATE, p2_fim DATE,

    estado TEXT NOT NULL DEFAULT 'rascunho'
        CHECK (estado IN ('rascunho', 'programado', 'comunicado', 'concluido', 'cancelado')),

    observacao TEXT,
    criado_por UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ferias_coletivas_tenant
    ON public.ferias_coletivas (tenant_id, ano, departamento);

ALTER TABLE public.ferias_coletivas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "ferias_coletivas por tenant" ON public.ferias_coletivas;
CREATE POLICY "ferias_coletivas por tenant"
ON public.ferias_coletivas FOR ALL TO authenticated
USING (tenant_id = public.get_user_tenant_id())
WITH CHECK (tenant_id = public.get_user_tenant_id());

-- Dias corridos de um periodo (inclusivo).
CREATE OR REPLACE FUNCTION public.ferias_periodo_dias(p_ini DATE, p_fim DATE)
RETURNS INTEGER LANGUAGE sql IMMUTABLE AS $fn$
    SELECT CASE WHEN p_ini IS NULL OR p_fim IS NULL THEN 0 ELSE (p_fim - p_ini + 1) END;
$fn$;

-- ── 2. Validacao: minimo 10 dias, ate 2 periodos, maximo 2/ano por setor ──
CREATE OR REPLACE FUNCTION public.ferias_coletiva_valida()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
    v_qtd_ano INTEGER;
BEGIN
    -- P1 obrigatorio e >= 10 dias corridos
    IF public.ferias_periodo_dias(NEW.p1_inicio, NEW.p1_fim) < 10 THEN
        RAISE EXCEPTION 'Ferias coletivas: cada periodo deve ter no minimo 10 dias corridos (CLT art. 139, §1º). O periodo 1 tem %.',
            public.ferias_periodo_dias(NEW.p1_inicio, NEW.p1_fim) USING ERRCODE = 'check_violation';
    END IF;

    -- P2 opcional; se houver, >= 10 dias e completo
    IF (NEW.p2_inicio IS NOT NULL) <> (NEW.p2_fim IS NOT NULL) THEN
        RAISE EXCEPTION 'Ferias coletivas: informe inicio E fim do periodo 2, ou deixe ambos vazios.'
            USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.p2_inicio IS NOT NULL AND public.ferias_periodo_dias(NEW.p2_inicio, NEW.p2_fim) < 10 THEN
        RAISE EXCEPTION 'Ferias coletivas: o periodo 2 deve ter no minimo 10 dias corridos (CLT art. 139, §1º). Tem %.',
            public.ferias_periodo_dias(NEW.p2_inicio, NEW.p2_fim) USING ERRCODE = 'check_violation';
    END IF;

    -- Maximo 2 periodos anuais POR SETOR: como cada registro ja carrega ate 2
    -- periodos, um segundo registro ativo no mesmo ano/setor estoura o limite.
    IF NEW.estado NOT IN ('cancelado') THEN
        SELECT count(*) INTO v_qtd_ano
          FROM public.ferias_coletivas c
         WHERE c.tenant_id = NEW.tenant_id
           AND c.ano = NEW.ano
           AND c.departamento = NEW.departamento
           AND c.estado NOT IN ('cancelado')
           AND c.id <> NEW.id;
        IF v_qtd_ano >= 1 THEN
            RAISE EXCEPTION 'Ferias coletivas: o setor "%" ja tem um programa em %; sao no maximo 2 periodos anuais e eles cabem em um unico programa (CLT art. 139, §1º).',
                NEW.departamento, NEW.ano USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    NEW.updated_at := now();
    RETURN NEW;
END $fn$;

DROP TRIGGER IF EXISTS trg_ferias_coletiva_valida ON public.ferias_coletivas;
CREATE TRIGGER trg_ferias_coletiva_valida
    BEFORE INSERT OR UPDATE ON public.ferias_coletivas
    FOR EACH ROW EXECUTE FUNCTION public.ferias_coletiva_valida();

-- ── 3. Comunicados obrigatorios (MTE, sindicato, empregados) ──────────────
CREATE TABLE IF NOT EXISTS public.ferias_coletivas_comunicados (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id    UUID NOT NULL,
    coletiva_id  UUID NOT NULL REFERENCES public.ferias_coletivas(id) ON DELETE CASCADE,
    destino      TEXT NOT NULL,   -- 'mte' | 'sindicato' | 'empregados'
    prazo_limite DATE NOT NULL,   -- inicio da coletiva - 15 dias
    status       TEXT NOT NULL DEFAULT 'pendente'
        CHECK (status IN ('pendente', 'gerado', 'protocolado')),
    documento_id UUID,            -- documento arquivado no modulo Documentos
    protocolado_em TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ferias_coletiva_comunicado_unico UNIQUE (coletiva_id, destino)
);

ALTER TABLE public.ferias_coletivas_comunicados ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "ferias_coletivas_comunicados por tenant" ON public.ferias_coletivas_comunicados;
CREATE POLICY "ferias_coletivas_comunicados por tenant"
ON public.ferias_coletivas_comunicados FOR ALL TO authenticated
USING (tenant_id = public.get_user_tenant_id())
WITH CHECK (tenant_id = public.get_user_tenant_id());

-- Abre os 3 comunicados pendentes com o prazo de 15 dias antes do inicio.
CREATE OR REPLACE FUNCTION public.ferias_coletiva_abrir_comunicados(p_coletiva UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
    c       RECORD;
    v_prazo DATE;
    v_dest  TEXT;
    v_n     INTEGER := 0;
BEGIN
    SELECT * INTO c FROM public.ferias_coletivas WHERE id = p_coletiva;
    IF NOT FOUND THEN RETURN 0; END IF;

    v_prazo := c.p1_inicio - 15;   -- art. 139, §2º / art. 141: 15 dias

    FOREACH v_dest IN ARRAY ARRAY['mte','sindicato','empregados'] LOOP
        INSERT INTO public.ferias_coletivas_comunicados (tenant_id, coletiva_id, destino, prazo_limite)
        VALUES (c.tenant_id, p_coletiva, v_dest, v_prazo)
        ON CONFLICT (coletiva_id, destino) DO NOTHING;
        IF FOUND THEN v_n := v_n + 1; END IF;
    END LOOP;

    UPDATE public.ferias_coletivas
       SET estado = CASE WHEN estado = 'rascunho' THEN 'programado' ELSE estado END,
           updated_at = now()
     WHERE id = p_coletiva;

    RETURN v_n;
END $fn$;

-- ── 4. Afetados pelo setor + art. 140 (novatos: proporcionais) ────────────
-- Lista os colaboradores ativos do setor da coletiva; para quem tem menos de
-- 12 meses de casa na virada do periodo, marca art_140=true e os dias
-- proporcionais ((meses de casa / 12) * 30, teto 30). O excedente do periodo
-- coletivo alem dos proporcionais e licenca remunerada (art. 140) — sinalizado.
CREATE OR REPLACE FUNCTION public.ferias_coletiva_afetados(p_coletiva UUID)
RETURNS TABLE (
    colaborador_cpf   TEXT,
    colaborador_nome  TEXT,
    data_admissao     DATE,
    meses_de_casa     INTEGER,
    art_140           BOOLEAN,
    dias_proporcionais INTEGER
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE c RECORD;
BEGIN
    SELECT * INTO c FROM public.ferias_coletivas WHERE id = p_coletiva;
    IF NOT FOUND THEN RETURN; END IF;

    RETURN QUERY
    SELECT
        regexp_replace(coalesce(a.cpf,''),'\D','','g') AS colaborador_cpf,
        a.nome_completo,
        a.data_admissao,
        (EXTRACT(YEAR FROM age(c.p1_inicio, a.data_admissao)) * 12
         + EXTRACT(MONTH FROM age(c.p1_inicio, a.data_admissao)))::int AS meses,
        ((EXTRACT(YEAR FROM age(c.p1_inicio, a.data_admissao)) * 12
         + EXTRACT(MONTH FROM age(c.p1_inicio, a.data_admissao))) < 12) AS art_140,
        LEAST(30, floor(
            ((EXTRACT(YEAR FROM age(c.p1_inicio, a.data_admissao)) * 12
              + EXTRACT(MONTH FROM age(c.p1_inicio, a.data_admissao))) / 12.0) * 30
        ))::int AS dias_prop
      FROM public.admissoes a
     WHERE a.tenant_id = c.tenant_id
       AND a.departamento = c.departamento
       AND a.status = 'concluido'
       AND a.data_admissao IS NOT NULL
       AND a.data_admissao <= c.p1_inicio;
END $fn$;

GRANT EXECUTE ON FUNCTION public.ferias_coletiva_abrir_comunicados(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ferias_coletiva_afetados(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ferias_periodo_dias(DATE, DATE) TO authenticated;
