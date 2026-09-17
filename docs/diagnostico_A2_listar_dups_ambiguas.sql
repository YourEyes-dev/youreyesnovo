-- ============================================================================
-- LISTA das duplicatas AMBIGUAS (mesma empresa, mas data OU cargo diferentes).
-- SOMENTE LEITURA. Nao altera nada.
--
-- Sao os grupos que NAO entram na limpeza automatica: como diferem em data de
-- admissao ou cargo, podem ser re-entrada/2o contrato legitimo, nao copia. Aqui
-- vao um a um, com o ID da admissao e da empresa, para o RH abrir no sistema e
-- decidir. Nao expoe CPF nem nome de pessoa (CPF mascarado, sem nome; a empresa
-- vai pelo ID e ultimos 4 do CNPJ).
--
-- Predicado de "ativa" identico ao indice A2.
-- ============================================================================

WITH
adm AS MATERIALIZED (
  SELECT a.id, a.tenant_id, a.empresa_id,
         regexp_replace(a.cpf,'[^0-9]','','g') AS cpfn,
         a.data_admissao, a.cargo, a.status::text AS status, a.created_at
  FROM public.admissoes a
  WHERE a.cpf IS NOT NULL
    AND a.status <> ALL (ARRAY['desligado','reprovado']::admissao_status[])
),
grp AS MATERIALIZED (
  SELECT tenant_id, cpfn,
         count(*) AS n_rows,
         count(DISTINCT COALESCE(empresa_id,'00000000-0000-0000-0000-000000000000'::uuid)) AS n_emp,
         count(DISTINCT data_admissao) AS datas_distintas,
         count(DISTINCT cargo)         AS cargos_distintos
  FROM adm
  GROUP BY tenant_id, cpfn
  HAVING count(*) > 1
),
ambig AS MATERIALIZED (   -- mesma empresa, mas data OU cargo diferente
  SELECT tenant_id, cpfn
  FROM grp
  WHERE n_emp = 1 AND (datas_distintas > 1 OR cargos_distintos > 1)
)
SELECT
  COALESCE(t.nome,'(' || left(a.tenant_id::text,8) || ')')          AS conta,
  dense_rank() OVER (ORDER BY a.tenant_id, a.cpfn)                  AS grupo,
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
JOIN ambig g   ON g.tenant_id = a.tenant_id AND g.cpfn = a.cpfn
LEFT JOIN public.tenants t          ON t.id = a.tenant_id
LEFT JOIN public.empresa_cadastro e ON e.id = a.empresa_id
ORDER BY conta, grupo, a.data_admissao, a.created_at;
