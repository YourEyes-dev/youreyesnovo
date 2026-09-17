-- ============================================================================
-- RE-CONTAGEM sob a chave CORRETA de contrato — SOMENTE LEITURA.
--
-- A tabela de admissoes e usada como registro historico (todo contrato que a
-- pessoa ja teve). Entao "mesmo CPF na mesma empresa" NAO e duplicata — o
-- historico legitimo tem varias linhas. A duplicata real e a RE-IMPORTACAO do
-- MESMO contrato: mesma (empresa, CPF, data de admissao, cargo).
--
-- Este script mede, por conta:
--   - admissoes ativas totais;
--   - contratos DISTINTOS (empresa, CPF, data, cargo) = o historico legitimo;
--   - grupos com copia EXATA (mesma empresa/CPF/data/cargo repetida) e quantas
--     LINHAS sobrariam para inativar (n-1 por grupo) = a limpeza segura;
--   - grupos "mesma data, cargo diferente" = ambiguos, para o RH olhar (podem
--     ser reclassificacao de cargo numa re-importacao); NAO entram no automatico.
--
-- Nao altera nada. Nao expoe CPF nem nome. Predicado de "ativa" identico ao A2.
-- ============================================================================

WITH
adm AS MATERIALIZED (
  SELECT a.tenant_id,
         a.empresa_id,
         regexp_replace(a.cpf,'[^0-9]','','g')          AS cpfn,
         COALESCE(a.data_admissao,'0001-01-01'::date)   AS dta,
         COALESCE(a.cargo,'')                            AS crg
  FROM public.admissoes a
  WHERE a.cpf IS NOT NULL
    AND a.status <> ALL (ARRAY['desligado','reprovado']::admissao_status[])
),
-- copia EXATA do mesmo contrato
exato AS MATERIALIZED (
  SELECT tenant_id, empresa_id, cpfn, dta, crg, count(*) AS n
  FROM adm
  GROUP BY tenant_id, empresa_id, cpfn, dta, crg
  HAVING count(*) > 1
),
exato_conta AS MATERIALIZED (
  SELECT tenant_id,
         count(*)            AS grupos_copia_exata,
         sum(n - 1)          AS linhas_a_inativar
  FROM exato GROUP BY tenant_id
),
-- mesma (empresa, CPF, data) com cargos diferentes = ambiguo p/ conferencia
ambiguo AS MATERIALIZED (
  SELECT tenant_id, empresa_id, cpfn, dta
  FROM adm
  GROUP BY tenant_id, empresa_id, cpfn, dta
  HAVING count(DISTINCT crg) > 1
),
ambiguo_conta AS MATERIALIZED (
  SELECT tenant_id, count(*) AS grupos_data_cargo_ambiguo
  FROM ambiguo GROUP BY tenant_id
),
-- historico legitimo = contratos distintos
distintos AS MATERIALIZED (
  SELECT tenant_id, count(*) AS contratos_distintos
  FROM (SELECT DISTINCT tenant_id, empresa_id, cpfn, dta, crg FROM adm) d
  GROUP BY tenant_id
),
contas AS MATERIALIZED (
  SELECT DISTINCT tenant_id FROM (
    SELECT tenant_id FROM exato_conta
    UNION SELECT tenant_id FROM ambiguo_conta
  ) x
)
SELECT
  COALESCE(t.nome,'(' || left(c.tenant_id::text,8) || ')')                       AS conta,
  (SELECT count(*) FROM adm a WHERE a.tenant_id=c.tenant_id)                     AS adm_ativas,
  COALESCE(d.contratos_distintos,0)                                             AS contratos_distintos_legitimos,
  COALESCE(ec.grupos_copia_exata,0)                                            AS grupos_copia_exata,
  COALESCE(ec.linhas_a_inativar,0)                                             AS linhas_a_inativar,
  COALESCE(ac.grupos_data_cargo_ambiguo,0)                                     AS grupos_ambiguos_p_rh
FROM contas c
LEFT JOIN public.tenants t   ON t.id = c.tenant_id
LEFT JOIN exato_conta ec     ON ec.tenant_id = c.tenant_id
LEFT JOIN ambiguo_conta ac   ON ac.tenant_id = c.tenant_id
LEFT JOIN distintos d        ON d.tenant_id = c.tenant_id
ORDER BY linhas_a_inativar DESC NULLS LAST, conta;
