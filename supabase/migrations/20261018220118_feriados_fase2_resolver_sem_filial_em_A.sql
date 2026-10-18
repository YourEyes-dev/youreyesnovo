-- =====================================================================
-- Unificacao de feriados — FASE 2: resolver deixa de ler 'filial' em A
--
-- Depois da FASE 1 (backfill), todo feriado de abrangencia 'filial' ativo de
-- public.feriados tem item identico no calendario por unidade (modelo B), que
-- ja tem prioridade P0 na fonte unica public.feriados_da_empresa. Esta fase
-- remove o ramo 'filial' do lado A do resolver — a partir daqui, "feriado so
-- desta unidade" mora UNICAMENTE no calendario (B). Nacional/estadual/
-- municipal continuam em A.
--
-- Por que e um no-op (quando a FASE 1 esta completa no ambiente): a UNICA
-- saida que esta funcao deixa de produzir e a de vencedor com origem='filial'.
-- Com o backfill aplicado, B (P0) vence em toda data que antes resolvia por
-- 'filial', entao o resolver nunca mais devolve origem='filial' — e remover o
-- ramo nao muda nenhuma linha. O portao desta fase (docs/script_feriados_
-- fase2_golden_resolver.sql) prova isso: exige vencedores_filial = 0 ANTES de
-- aplicar. NAO aplicar esta fase num ambiente onde a FASE 1 ainda nao rodou.
--
-- Muda SO o corpo de feriados_da_empresa. feriado_do_dia,
-- ponto_feriados_colaborador, ponto_feriados_trabalhados e
-- ponto_equalizacao_competencia delegam a esta funcao e seguem intactos.
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
AS $$
  WITH loc AS (
    SELECT
      (SELECT ec.estado FROM public.empresa_cadastro ec WHERE ec.id = p_empresa_id) AS uf,
      (SELECT ec.cidade FROM public.empresa_cadastro ec WHERE ec.id = p_empresa_id) AS cidade
  ),
  dias AS (
    SELECT g::date AS d FROM generate_series(p_ini, p_fim, interval '1 day') g
  ),
  candidatos AS (
    -- P0: tabela nomeada vinculada a filial (calendario por unidade)
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

    -- P2..P4: base public.feriados — SO por localizacao (municipal/estadual/
    -- nacional). A abrangencia 'filial' foi unificada no calendario (B) na
    -- FASE 1 e NAO e mais lida aqui.
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
$$;

GRANT EXECUTE ON FUNCTION public.feriados_da_empresa(uuid, uuid, date, date)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.feriados_da_empresa(uuid, uuid, date, date) IS
  'Resolucao unica de feriados por empresa/unidade e periodo. Prioridade: calendario da unidade (B) > municipal > estadual > nacional. A abrangencia filial foi unificada no calendario por unidade (unificacao de feriados, Fase 2). Consumida por feriado_do_dia (espelho) e por ponto_equalizacao_competencia (RN02).';
