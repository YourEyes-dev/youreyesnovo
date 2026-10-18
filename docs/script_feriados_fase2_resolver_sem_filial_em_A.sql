-- =====================================================================
-- ENTREGA — Unificacao de feriados, FASE 2
-- Resolver public.feriados_da_empresa deixa de ler a abrangencia 'filial' de
-- public.feriados. "Feriado so desta unidade" passa a morar UNICAMENTE no
-- calendario por unidade (modelo B), ja povoado pela Fase 1.
--
-- PRE-REQUISITO OBRIGATORIO: rodar ANTES, no MESMO ambiente, o portao
-- docs/script_feriados_fase2_golden_resolver.sql e obter
--   vencedores_filial = 0  E  faltando = 0.
-- So aplique este script com esse veredito OK. Caso contrario, a Fase 1 ainda
-- nao cobriu tudo e aplicar aqui removeria feriados de unidade do calculo.
--
-- So-cria-funcao (nao cria tabela): nao aciona o auto-RLS do editor e nao
-- precisa de backup. Idempotente (CREATE OR REPLACE). Comportamento identico
-- quando o portao esta OK (a unica saida removida — vencedor origem='filial' —
-- ja nao ocorre apos a Fase 1). Rode o arquivo inteiro de uma vez.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.feriados_da_empresa(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_ini date,
  p_fim date
)
RETURNS TABLE(data date, nome text, origem text)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  WITH loc AS (
    SELECT
      (SELECT ec.estado FROM public.empresa_cadastro ec WHERE ec.id = p_empresa_id) AS uf,
      (SELECT ec.cidade FROM public.empresa_cadastro ec WHERE ec.id = p_empresa_id) AS cidade
  ),
  dias AS (
    SELECT g::date AS d FROM generate_series(p_ini, p_fim, interval '1 day') g
  ),
  candidatos AS (
    -- P0: calendario por unidade (modelo B)
    SELECT d.d AS data, i.nome, 'tabela'::text AS origem, 0 AS prio
    FROM dias d
    JOIN public.feriado_tabela_empresas v ON v.empresa_id = p_empresa_id
    JOIN public.feriado_tabelas t
      ON t.id = v.tabela_id AND t.ativo = true AND t.tenant_id = p_tenant_id
     AND (t.ano IS NULL OR t.ano = EXTRACT(YEAR FROM d.d)::int)
    JOIN public.feriado_tabela_itens i
      ON i.tabela_id = t.id AND i.ativo = true AND i.tipo = 'feriado'
     AND (
       (i.recorrente = true
         AND i.dia = EXTRACT(DAY FROM d.d)::smallint
         AND i.mes = EXTRACT(MONTH FROM d.d)::smallint)
       OR (i.recorrente = false AND i.data = d.d)
     )
    WHERE p_empresa_id IS NOT NULL

    UNION ALL

    -- P2..P4: base public.feriados — so por localizacao (municipal/estadual/
    -- nacional). A abrangencia filial foi unificada no calendario (B).
    SELECT d.d, f.nome, f.abrangencia,
           CASE f.abrangencia
             WHEN 'municipal' THEN 2 WHEN 'estadual' THEN 3 ELSE 4 END
    FROM dias d
    CROSS JOIN loc
    JOIN public.feriados f
      ON COALESCE(f.ativo, true) = true AND f.tipo = 'feriado'
     AND (f.tenant_id IS NULL OR f.tenant_id = p_tenant_id)
     AND (
       (COALESCE(f.recorrente, false) = true
         AND f.dia = EXTRACT(DAY FROM d.d)::smallint
         AND f.mes = EXTRACT(MONTH FROM d.d)::smallint)
       OR (COALESCE(f.recorrente, false) = false AND f.data = d.d)
     )
     AND (
       f.abrangencia = 'nacional'
       OR (f.abrangencia = 'estadual'
           AND loc.uf IS NOT NULL AND btrim(loc.uf) <> ''
           AND upper(btrim(f.uf)) = upper(btrim(loc.uf)))
       OR (f.abrangencia = 'municipal'
           AND loc.uf IS NOT NULL AND btrim(loc.uf) <> ''
           AND loc.cidade IS NOT NULL AND btrim(loc.cidade) <> ''
           AND upper(btrim(f.uf)) = upper(btrim(loc.uf))
           AND upper(btrim(f.municipio)) = upper(btrim(loc.cidade)))
     )
  )
  SELECT DISTINCT ON (c.data) c.data, c.nome, c.origem
  FROM candidatos c
  ORDER BY c.data, c.prio, c.nome;
$fn$;

GRANT EXECUTE ON FUNCTION public.feriados_da_empresa(uuid, uuid, date, date)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.feriados_da_empresa(uuid, uuid, date, date) IS
  'Resolucao unica de feriados por empresa/unidade e periodo. Prioridade: calendario da unidade (B) > municipal > estadual > nacional. A abrangencia filial foi unificada no calendario por unidade (unificacao de feriados, Fase 2). Consumida por feriado_do_dia (espelho) e por ponto_equalizacao_competencia (RN02).';

-- ---------------------------------------------------------------------
-- CONFERENCIA: o ramo 'filial' de A saiu do resolver? (esperado: t)
-- ---------------------------------------------------------------------
SELECT position('abrangencia = ''filial''' IN
                pg_get_functiondef('public.feriados_da_empresa(uuid,uuid,date,date)'::regprocedure)) = 0
       AS sem_ramo_filial;
