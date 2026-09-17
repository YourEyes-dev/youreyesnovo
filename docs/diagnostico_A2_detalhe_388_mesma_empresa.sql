-- ============================================================================
-- DETALHE dos grupos "MESMA EMPRESA" (duplicata real) — SOMENTE LEITURA.
--
-- Nao altera nada. Caracteriza os grupos onde o MESMO CPF aparece ativo mais de
-- uma vez na MESMA empresa (os "dup_mesma_empresa" do diagnostico anterior),
-- para entender se sao:
--   (a) ARTEFATO de fluxo — mesma contratacao virou 2 linhas (mesma data de
--       admissao, mesmo cargo, status adjacentes tipo aprovado+concluido);
--   (b) RE-ENTRADA REAL — datas/cargos diferentes (decisao de RH de verdade).
--
-- Nao expoe CPF nem nome de pessoa: agrupa por conta + padrao de status e
-- conta quantos grupos tem data/cargo iguais vs diferentes.
-- Predicado de "ativa" identico ao indice A2.
-- ============================================================================

WITH
adm AS MATERIALIZED (
  SELECT a.tenant_id,
         a.empresa_id,
         regexp_replace(a.cpf, '[^0-9]', '', 'g') AS cpfn,
         a.status::text                            AS st,
         a.data_admissao,
         a.cargo
  FROM public.admissoes a
  WHERE a.cpf IS NOT NULL
    AND a.status <> ALL (ARRAY['desligado','reprovado']::admissao_status[])
),
grp AS MATERIALIZED (
  SELECT tenant_id,
         cpfn,
         count(*)                                                                  AS n_rows,
         count(DISTINCT COALESCE(empresa_id,'00000000-0000-0000-0000-000000000000'::uuid)) AS n_emp,
         bool_or(empresa_id IS NULL)                                               AS tem_sem_empresa,
         array_to_string(array_agg(DISTINCT st ORDER BY st), '+')                  AS padrao_status,
         count(DISTINCT data_admissao)                                             AS datas_distintas,
         count(DISTINCT cargo)                                                     AS cargos_distintos
  FROM adm
  GROUP BY tenant_id, cpfn
  HAVING count(*) > 1
),
mesma AS MATERIALIZED (            -- so os "dup_mesma_empresa" (n_emp = 1)
  SELECT * FROM grp WHERE n_emp = 1
)
SELECT
  COALESCE(t.nome, '(' || left(m.tenant_id::text,8) || ')')      AS conta,
  m.padrao_status,
  count(*)                                                       AS grupos,
  sum(m.n_rows)                                                  AS admissoes_no_grupo,
  count(*) FILTER (WHERE m.datas_distintas <= 1)                 AS grupos_mesma_data_adm,
  count(*) FILTER (WHERE m.datas_distintas > 1)                  AS grupos_datas_diferentes,
  count(*) FILTER (WHERE m.cargos_distintos <= 1)                AS grupos_mesmo_cargo,
  count(*) FILTER (WHERE m.tem_sem_empresa)                      AS grupos_com_admissao_sem_empresa
FROM mesma m
LEFT JOIN public.tenants t ON t.id = m.tenant_id
GROUP BY COALESCE(t.nome, '(' || left(m.tenant_id::text,8) || ')'), m.padrao_status
ORDER BY grupos DESC, conta, m.padrao_status;
