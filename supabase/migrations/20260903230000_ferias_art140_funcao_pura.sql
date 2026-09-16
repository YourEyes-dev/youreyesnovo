-- =========================================================
-- Ferias coletivas — art. 140 vira funcao PURA + QA robusto
--
-- A rotina qa_caso_ferias_062 inseria uma admissao-sonda, mas admissoes tem
-- colunas NOT NULL sem default (email, cargo) que a sonda nao preenchia — no
-- schema real a sonda quebrava ('erro'). No stub local passava porque a
-- tabela era simplificada.
--
-- Correcao: a regra do art. 140 (menos de 12 meses -> proporcional) vira uma
-- funcao PURA, testavel sem tocar admissoes. A ferias_coletiva_afetados passa
-- a usa-la (uma fonte da regra), e o QA testa a funcao diretamente.
-- =========================================================

SET lock_timeout = '10s';

-- Regra do art. 140, isolada e pura.
CREATE OR REPLACE FUNCTION public.ferias_art140_calc(p_admissao DATE, p_referencia DATE)
RETURNS TABLE (meses INTEGER, art_140 BOOLEAN, dias_proporcionais INTEGER)
LANGUAGE sql
IMMUTABLE
AS $fn$
    SELECT m,
           (m < 12) AS art_140,
           LEAST(30, floor((m / 12.0) * 30))::int AS dias_proporcionais
      FROM (
        SELECT (EXTRACT(YEAR  FROM age(p_referencia, p_admissao)) * 12
              + EXTRACT(MONTH FROM age(p_referencia, p_admissao)))::int AS m
      ) t;
$fn$;

GRANT EXECUTE ON FUNCTION public.ferias_art140_calc(DATE, DATE) TO authenticated;

-- Afetados: mesma saida, agora usando a funcao pura.
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

-- QA-062 testa a funcao pura — nao insere admissao.
CREATE OR REPLACE FUNCTION public.qa_caso_ferias_062()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
    r public.qa_retorno;
    v_novato   RECORD;
    v_veterano RECORD;
BEGIN
    r.passo_ordem := 1;
    r.passo_acao := 'AUDITORIA: quem tem menos de 12 meses entra proporcional (art. 140)?';
    r.esperado := 'Novato de 6 meses: art_140=true e ~15 dias proporcionais; veterano: art_140=false';

    IF to_regproc('public.ferias_art140_calc') IS NULL THEN
        r.situacao := 'falhou';
        r.obtido := 'Sem tratamento do art. 140 (encadeado ao FERIAS-060).';
        RETURN r;
    END IF;

    SELECT * INTO v_novato   FROM public.ferias_art140_calc(
        (DATE '2026-01-01' - INTERVAL '6 months')::date, DATE '2026-01-01');
    SELECT * INTO v_veterano FROM public.ferias_art140_calc(
        (DATE '2026-01-01' - INTERVAL '3 years')::date, DATE '2026-01-01');

    IF v_novato.art_140 AND v_novato.dias_proporcionais BETWEEN 12 AND 18
       AND NOT v_veterano.art_140 THEN
        r.situacao := 'passou';
        r.obtido := format('Art. 140 OK: novato de 6 meses entra proporcional (%s dias); '
                 || 'veterano nao e afetado.', v_novato.dias_proporcionais);
    ELSE
        r.situacao := 'falhou';
        r.obtido := format('Art. 140 incorreto: novato_140=%s dias=%s veterano_140=%s.',
                           v_novato.art_140, v_novato.dias_proporcionais, v_veterano.art_140);
    END IF;
    RETURN r;
EXCEPTION WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;
