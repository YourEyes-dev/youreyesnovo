-- ============================================================================
-- LISTA dos grupos AMBIGUOS: mesma empresa, mesmo CPF, MESMA data de admissao,
-- mas CARGO diferente. SOMENTE LEITURA.
--
-- Sao os que NAO entram na limpeza automatica (a chave de contrato inclui o
-- cargo, entao cargos diferentes = contratos distintos aos olhos da regra).
-- Mas cheiram a RECLASSIFICACAO de cargo numa re-importacao (um e o certo, o
-- outro ficou velho). Quem decide qual fica e o RH.
--
-- Nao expoe CPF nem nome. CPF mascarado; empresa por ID + ultimos do documento.
-- Predicado de "ativa" identico ao A2.
-- ============================================================================

WITH
adm AS MATERIALIZED (
  SELECT a.id, a.tenant_id, a.empresa_id,
         regexp_replace(a.cpf,'[^0-9]','','g')        AS cpfn,
         COALESCE(a.data_admissao,'0001-01-01'::date) AS dta,
         a.data_admissao, a.cargo, a.status::text AS status, a.created_at
  FROM public.admissoes a
  WHERE a.cpf IS NOT NULL
    AND a.status <> ALL (ARRAY['desligado','reprovado']::admissao_status[])
),
ambig AS MATERIALIZED (
  SELECT tenant_id, empresa_id, cpfn, dta
  FROM adm
  GROUP BY tenant_id, empresa_id, cpfn, dta
  HAVING count(DISTINCT COALESCE(cargo,'')) > 1
)
SELECT
  COALESCE(t.nome,'(' || left(a.tenant_id::text,8) || ')')          AS conta,
  dense_rank() OVER (ORDER BY a.tenant_id, a.empresa_id, a.cpfn, a.dta) AS grupo,
  '****' || right(a.cpfn,3)                                         AS cpf_mascarado,
  a.empresa_id,
  CASE WHEN e.cnpj IS NOT NULL
       THEN 'CNPJ ****' || right(regexp_replace(e.cnpj,'[^0-9]','','g'),4)
       WHEN e.cpf IS NOT NULL THEN 'PF ****' || right(regexp_replace(e.cpf,'[^0-9]','','g'),3)
       ELSE '(sem doc)' END                                        AS empresa_doc,
  a.id                                                             AS admissao_id,
  a.data_admissao,
  a.cargo,
  a.status,
  a.created_at
FROM adm a
JOIN ambig g ON g.tenant_id=a.tenant_id AND g.empresa_id IS NOT DISTINCT FROM a.empresa_id
             AND g.cpfn=a.cpfn AND g.dta=a.dta
LEFT JOIN public.tenants t          ON t.id = a.tenant_id
LEFT JOIN public.empresa_cadastro e ON e.id = a.empresa_id
ORDER BY conta, grupo, a.cargo;
