-- ============================================================================
-- ENTREGA — Ferias coletivas (RF-007 / arts. 139-141 da CLT)
--
-- Colar INTEIRO no SQL Editor do projeto de PRODUCAO e executar uma vez.
--
-- POR QUE
--   Nao havia fluxo de ferias coletivas. O documento YE-DP-FERIAS-001 (RF-007)
--   pede: programar por setor, ate 2 periodos anuais de no minimo 10 dias
--   corridos, comunicar ao MTE e ao sindicato com 15 dias de antecedencia (e
--   avisar/afixar aos empregados), e tratar quem tem menos de 12 meses de casa
--   com proporcionais e novo aquisitivo (art. 140).
--
-- O QUE MUDA
--   1) ferias_coletivas: programa por setor (ate 2 periodos); trigger valida
--      minimo de 10 dias corridos e maximo de 2 periodos anuais por setor;
--   2) ferias_coletivas_comunicados + ferias_coletiva_abrir_comunicados():
--      abre os 3 comunicados (MTE, sindicato, empregados) com prazo de 15 dias;
--   3) ferias_art140_calc(): a regra do art. 140, PURA (menos de 12 meses ->
--      proporcional); ferias_coletiva_afetados() lista os do setor usando-a;
--   4) rotinas de QA FERIAS-060/061/062.
--
-- SEGURANCA DO DADO
--   So CRIA coisa nova (tabelas, funcoes, trigger). Nao altera nem apaga
--   nenhuma LINHA existente, entao nao ha copia de seguranca a fazer.
--   Idempotente: rodar duas vezes nao quebra nem duplica.
--
-- PROVADO em replica local com schema fiel (admissoes com email/cargo NOT
--   NULL): coletiva de 12 dias aceita com 3 comunicados a 15 dias; periodo de
--   8 dias e 2o programa no ano/setor barrados; novato de 6 meses entra
--   proporcional (~15 dias) e veterano intacto. FERIAS-060/061/062: passou.
--
-- A TELA (aba "Coletivas") so aparece apos Publicar no Lovable.
-- ============================================================================

SET lock_timeout = '10s';

-- ── 1. O programa de coletivas ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ferias_coletivas (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id    UUID NOT NULL,
    empresa_id   UUID,
    ano          INTEGER NOT NULL,
    departamento TEXT NOT NULL,
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

CREATE OR REPLACE FUNCTION public.ferias_periodo_dias(p_ini DATE, p_fim DATE)
RETURNS INTEGER LANGUAGE sql IMMUTABLE AS $fn$
    SELECT CASE WHEN p_ini IS NULL OR p_fim IS NULL THEN 0 ELSE (p_fim - p_ini + 1) END;
$fn$;

-- ── 2. Validacao (min 10 dias, ate 2 periodos, max 2/ano por setor) ───────
CREATE OR REPLACE FUNCTION public.ferias_coletiva_valida()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE v_qtd_ano INTEGER;
BEGIN
    IF public.ferias_periodo_dias(NEW.p1_inicio, NEW.p1_fim) < 10 THEN
        RAISE EXCEPTION 'Ferias coletivas: cada periodo deve ter no minimo 10 dias corridos (CLT art. 139, §1º). O periodo 1 tem %.',
            public.ferias_periodo_dias(NEW.p1_inicio, NEW.p1_fim) USING ERRCODE = 'check_violation';
    END IF;
    IF (NEW.p2_inicio IS NOT NULL) <> (NEW.p2_fim IS NOT NULL) THEN
        RAISE EXCEPTION 'Ferias coletivas: informe inicio E fim do periodo 2, ou deixe ambos vazios.'
            USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.p2_inicio IS NOT NULL AND public.ferias_periodo_dias(NEW.p2_inicio, NEW.p2_fim) < 10 THEN
        RAISE EXCEPTION 'Ferias coletivas: o periodo 2 deve ter no minimo 10 dias corridos (CLT art. 139, §1º). Tem %.',
            public.ferias_periodo_dias(NEW.p2_inicio, NEW.p2_fim) USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.estado NOT IN ('cancelado') THEN
        SELECT count(*) INTO v_qtd_ano
          FROM public.ferias_coletivas c
         WHERE c.tenant_id = NEW.tenant_id AND c.ano = NEW.ano
           AND c.departamento = NEW.departamento
           AND c.estado NOT IN ('cancelado') AND c.id <> NEW.id;
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

-- ── 3. Comunicados (MTE, sindicato, empregados) ───────────────────────────
CREATE TABLE IF NOT EXISTS public.ferias_coletivas_comunicados (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id    UUID NOT NULL,
    coletiva_id  UUID NOT NULL REFERENCES public.ferias_coletivas(id) ON DELETE CASCADE,
    destino      TEXT NOT NULL,
    prazo_limite DATE NOT NULL,
    status       TEXT NOT NULL DEFAULT 'pendente'
        CHECK (status IN ('pendente', 'gerado', 'protocolado')),
    documento_id UUID,
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

CREATE OR REPLACE FUNCTION public.ferias_coletiva_abrir_comunicados(p_coletiva UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE c RECORD; v_prazo DATE; v_dest TEXT; v_n INTEGER := 0;
BEGIN
    SELECT * INTO c FROM public.ferias_coletivas WHERE id = p_coletiva;
    IF NOT FOUND THEN RETURN 0; END IF;
    v_prazo := c.p1_inicio - 15;
    FOREACH v_dest IN ARRAY ARRAY['mte','sindicato','empregados'] LOOP
        INSERT INTO public.ferias_coletivas_comunicados (tenant_id, coletiva_id, destino, prazo_limite)
        VALUES (c.tenant_id, p_coletiva, v_dest, v_prazo)
        ON CONFLICT (coletiva_id, destino) DO NOTHING;
        IF FOUND THEN v_n := v_n + 1; END IF;
    END LOOP;
    UPDATE public.ferias_coletivas
       SET estado = CASE WHEN estado = 'rascunho' THEN 'programado' ELSE estado END, updated_at = now()
     WHERE id = p_coletiva;
    RETURN v_n;
END $fn$;

-- ── 4. Art. 140 como funcao pura + afetados do setor ──────────────────────
CREATE OR REPLACE FUNCTION public.ferias_art140_calc(p_admissao DATE, p_referencia DATE)
RETURNS TABLE (meses INTEGER, art_140 BOOLEAN, dias_proporcionais INTEGER)
LANGUAGE sql IMMUTABLE AS $fn$
    SELECT m, (m < 12), LEAST(30, floor((m / 12.0) * 30))::int
      FROM (
        SELECT (EXTRACT(YEAR  FROM age(p_referencia, p_admissao)) * 12
              + EXTRACT(MONTH FROM age(p_referencia, p_admissao)))::int AS m
      ) t;
$fn$;

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
        regexp_replace(coalesce(a.cpf,''),'\D','','g'),
        a.nome_completo,
        a.data_admissao,
        calc.meses,
        calc.art_140,
        calc.dias_proporcionais
      FROM public.admissoes a
      CROSS JOIN LATERAL public.ferias_art140_calc(a.data_admissao, c.p1_inicio) AS calc
     WHERE a.tenant_id = c.tenant_id
       AND a.departamento = c.departamento
       AND a.status = 'concluido'
       AND a.data_admissao IS NOT NULL
       AND a.data_admissao <= c.p1_inicio;
END $fn$;

GRANT EXECUTE ON FUNCTION public.ferias_periodo_dias(DATE, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ferias_coletiva_abrir_comunicados(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ferias_art140_calc(DATE, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ferias_coletiva_afetados(UUID) TO authenticated;

-- ── 5. QA — FERIAS-060/061/062 (sondas com rollback) ──────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ferias_060()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_ten uuid; v_id uuid; v_com int; v_prazo date;
BEGIN
    r.passo_ordem := 1;
    r.passo_acao := 'AUDITORIA: existe fluxo de ferias coletivas com comunicados (15 dias)?';
    r.esperado := 'Programa por setor, ate 2 periodos >= 10 dias, comunicados MTE/sindicato/empregados';
    IF to_regclass('public.ferias_coletivas') IS NULL THEN
        r.situacao := 'falhou'; r.obtido := 'ACHADO: sem fluxo de coletivas (arts. 139-141).'; RETURN r;
    END IF;
    SELECT id INTO v_ten FROM public.tenants LIMIT 1;
    IF v_ten IS NULL THEN r.situacao := 'nao_implementado'; r.obtido := 'Sem tenants para a sonda.'; RETURN r; END IF;
    BEGIN
        INSERT INTO public.ferias_coletivas (tenant_id, ano, departamento, p1_inicio, p1_fim)
        VALUES (v_ten, EXTRACT(YEAR FROM CURRENT_DATE)::int, 'QA-Producao', CURRENT_DATE + 40, CURRENT_DATE + 51)
        RETURNING id INTO v_id;
        v_com := public.ferias_coletiva_abrir_comunicados(v_id);
        SELECT count(*), min(prazo_limite) INTO v_com, v_prazo
          FROM public.ferias_coletivas_comunicados WHERE coletiva_id = v_id;
        RAISE EXCEPTION 'qa_rollback';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM <> 'qa_rollback' THEN
            r.situacao := 'erro'; r.obtido := 'A sonda quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
        END IF;
    END;
    IF v_com = 3 AND v_prazo = (CURRENT_DATE + 40 - 15) THEN
        r.situacao := 'passou';
        r.obtido := 'Coletiva de 12 dias aceita; 3 comunicados abertos com prazo 15 dias antes do inicio.';
    ELSE
        r.situacao := 'falhou';
        r.obtido := format('Rito incompleto: comunicados=%s, prazo=%s.', v_com, v_prazo);
    END IF;
    RETURN r;
EXCEPTION WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_061()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_ten uuid; v_ano int := EXTRACT(YEAR FROM CURRENT_DATE)::int;
        v_curto boolean := false; v_terceiro boolean := false;
BEGIN
    r.passo_ordem := 1;
    r.passo_acao := 'AUDITORIA: os limites das coletivas valem (min 10 dias; max 2/ano)?';
    r.esperado := 'Periodo de 8 dias barrado; segundo programa no mesmo ano/setor barrado';
    IF to_regclass('public.ferias_coletivas') IS NULL THEN
        r.situacao := 'falhou'; r.obtido := 'Sem tabela de coletivas.'; RETURN r; END IF;
    SELECT id INTO v_ten FROM public.tenants LIMIT 1;
    IF v_ten IS NULL THEN r.situacao := 'nao_implementado'; r.obtido := 'Sem tenants.'; RETURN r; END IF;
    BEGIN
        BEGIN
            INSERT INTO public.ferias_coletivas (tenant_id, ano, departamento, p1_inicio, p1_fim)
            VALUES (v_ten, v_ano, 'QA-Limites', CURRENT_DATE + 40, CURRENT_DATE + 47);
        EXCEPTION WHEN check_violation THEN v_curto := true; END;
        INSERT INTO public.ferias_coletivas (tenant_id, ano, departamento, p1_inicio, p1_fim)
        VALUES (v_ten, v_ano, 'QA-Limites2', CURRENT_DATE + 40, CURRENT_DATE + 51);
        BEGIN
            INSERT INTO public.ferias_coletivas (tenant_id, ano, departamento, p1_inicio, p1_fim)
            VALUES (v_ten, v_ano, 'QA-Limites2', CURRENT_DATE + 100, CURRENT_DATE + 111);
        EXCEPTION WHEN check_violation THEN v_terceiro := true; END;
        RAISE EXCEPTION 'qa_rollback';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM <> 'qa_rollback' THEN
            r.situacao := 'erro'; r.obtido := 'A sonda quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
        END IF;
    END;
    IF v_curto AND v_terceiro THEN
        r.situacao := 'passou';
        r.obtido := 'Limites valem: periodo de 8 dias barrado (min 10) e segundo programa no mesmo ano/setor barrado.';
    ELSE
        r.situacao := 'falhou';
        r.obtido := format('Limites frouxos: barrou_8dias=%s, barrou_2o=%s.', v_curto, v_terceiro);
    END IF;
    RETURN r;
EXCEPTION WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_062()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_novato RECORD; v_veterano RECORD;
BEGIN
    r.passo_ordem := 1;
    r.passo_acao := 'AUDITORIA: quem tem menos de 12 meses entra proporcional (art. 140)?';
    r.esperado := 'Novato de 6 meses: art_140=true e ~15 dias proporcionais; veterano: art_140=false';
    IF to_regproc('public.ferias_art140_calc') IS NULL THEN
        r.situacao := 'falhou'; r.obtido := 'Sem tratamento do art. 140.'; RETURN r; END IF;
    SELECT * INTO v_novato   FROM public.ferias_art140_calc((DATE '2026-01-01' - INTERVAL '6 months')::date, DATE '2026-01-01');
    SELECT * INTO v_veterano FROM public.ferias_art140_calc((DATE '2026-01-01' - INTERVAL '3 years')::date, DATE '2026-01-01');
    IF v_novato.art_140 AND v_novato.dias_proporcionais BETWEEN 12 AND 18 AND NOT v_veterano.art_140 THEN
        r.situacao := 'passou';
        r.obtido := format('Art. 140 OK: novato de 6 meses entra proporcional (%s dias); veterano nao e afetado.', v_novato.dias_proporcionais);
    ELSE
        r.situacao := 'falhou';
        r.obtido := format('Art. 140 incorreto: novato_140=%s dias=%s veterano_140=%s.',
                           v_novato.art_140, v_novato.dias_proporcionais, v_veterano.art_140);
    END IF;
    RETURN r;
EXCEPTION WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── 6. Conferencia final ──────────────────────────────────────────────────
SELECT
    (SELECT CASE WHEN to_regclass('public.ferias_coletivas') IS NOT NULL THEN 'sim' ELSE 'NAO' END)            AS tabela_coletivas,
    (SELECT CASE WHEN to_regclass('public.ferias_coletivas_comunicados') IS NOT NULL THEN 'sim' ELSE 'NAO' END) AS tabela_comunicados,
    (SELECT CASE WHEN to_regproc('public.ferias_art140_calc') IS NOT NULL THEN 'sim' ELSE 'NAO' END)            AS art_140,
    (SELECT situacao FROM public.qa_caso_ferias_060()) AS qa_060,
    (SELECT situacao FROM public.qa_caso_ferias_061()) AS qa_061,
    (SELECT situacao FROM public.qa_caso_ferias_062()) AS qa_062;
