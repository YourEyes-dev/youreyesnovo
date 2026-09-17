-- ============================================================================
-- DIAGNOSTICO A2 — "de quem sao as duplicatas?" (SOMENTE LEITURA)
--
-- Nao altera NADA. Apenas descreve os grupos duplicados que o A2 adiou, para
-- decidir com seguranca o que e lixo de teste, o que e multi-CNPJ legitimo e o
-- que e duplicata real a limpar.
--
-- Seguro para compartilhar: o resultado NAO expoe CPF nem nome de pessoa.
-- Mostra apenas o nome da CONTA (tenant), contagens e sinais. CPF entra so como
-- contagem de "faixa de teste" (900.000.0XX), nunca o numero.
--
-- Contexto de negocio que este diagnostico separa:
--  - Cenario 1 (auto-gestao multi-CNPJ): a MESMA pessoa admitida em DUAS
--    empresas do mesmo grupo e LEGITIMA. O indice A2 e por (tenant, cpf) e nao
--    olha empresa_id, entao marcaria isso como "duplicata" sem ser. Aqui isso
--    aparece como "possivel_multi_cnpj" e NAO deve ser limpo.
--  - Duplicata REAL: mesmo CPF na MESMA empresa, ativo mais de uma vez.
--  - Lixo de teste: conta inativa, nome com teste/demo/staging, ou CPF na faixa
--    ficticia da casa (900.000.0XX) que vazou do banco unico antigo.
--
-- Predicados IDENTICOS aos indices do A2, para os numeros baterem com a
-- conferencia que voce ja rodou (557 / 11 / 2).
-- ============================================================================

WITH
-- ── Admissoes "ativas" pela MESMA regra do indice A2 (ADM-002) ──────────────
adm AS MATERIALIZED (
  SELECT a.tenant_id,
         a.empresa_id,
         regexp_replace(a.cpf, '[^0-9]', '', 'g') AS cpfn
  FROM public.admissoes a
  WHERE a.cpf IS NOT NULL
    AND a.status <> ALL (ARRAY['desligado','reprovado']::admissao_status[])
),
adm_grp AS MATERIALIZED (
  SELECT tenant_id,
         cpfn,
         count(*)                    AS n_adm,
         -- COALESCE p/ o sentinel: assim empresa NULL conta como "uma empresa"
         -- e dup_mesma_empresa + possivel_multi_cnpj sempre soma = grupos.
         count(DISTINCT COALESCE(empresa_id,'00000000-0000-0000-0000-000000000000'::uuid)) AS n_emp,
         bool_or(empresa_id IS NULL) AS tem_sem_empresa,
         (cpfn LIKE '9000000%')      AS faixa_teste
  FROM adm
  GROUP BY tenant_id, cpfn
  HAVING count(*) > 1
),
adm_por_conta AS MATERIALIZED (
  SELECT tenant_id,
         count(*)                                   AS grupos,
         count(*) FILTER (WHERE n_emp = 1)          AS dup_mesma_empresa,
         count(*) FILTER (WHERE n_emp > 1)          AS possivel_multi_cnpj,
         count(*) FILTER (WHERE tem_sem_empresa)    AS grupos_sem_empresa,
         count(*) FILTER (WHERE faixa_teste)        AS grupos_cpf_faixa_teste
  FROM adm_grp
  GROUP BY tenant_id
),
-- ── Empresas ativas com CPF duplicado (EMP-070/071), mesma regra do indice ──
emp_grp AS MATERIALIZED (
  SELECT tenant_id,
         regexp_replace(cpf, '[^0-9]', '', 'g')  AS cpfn,
         count(*)                                AS n,
         bool_or(regexp_replace(cpf,'[^0-9]','','g') LIKE '9000000%') AS faixa_teste
  FROM public.empresa_cadastro
  WHERE ativo IS TRUE AND cpf IS NOT NULL
  GROUP BY tenant_id, regexp_replace(cpf, '[^0-9]', '', 'g')
  HAVING count(*) > 1
),
emp_por_conta AS MATERIALIZED (
  SELECT tenant_id,
         count(*)                            AS grupos,
         count(*) FILTER (WHERE faixa_teste) AS grupos_cpf_faixa_teste
  FROM emp_grp
  GROUP BY tenant_id
),
-- ── Vinculos de perfil ativos duplicados (VIN-008), mesma regra do indice ───
vin_grp AS MATERIALIZED (
  SELECT tenant_id,
         usuario_id,
         COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid) AS emp,
         count(*) AS n
  FROM public.usuario_perfil_vinculos
  WHERE COALESCE(ativo, true) IS TRUE
  GROUP BY tenant_id, usuario_id, COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid)
  HAVING count(*) > 1
),
vin_por_conta AS MATERIALIZED (
  SELECT tenant_id, count(*) AS grupos
  FROM vin_grp
  GROUP BY tenant_id
),
-- ── Contexto por conta: usa ponto? tem admissao? conta ativa? ───────────────
contas AS MATERIALIZED (
  SELECT DISTINCT tenant_id FROM (
    SELECT tenant_id FROM adm_por_conta
    UNION SELECT tenant_id FROM emp_por_conta
    UNION SELECT tenant_id FROM vin_por_conta
  ) x
),
ctx AS MATERIALIZED (
  SELECT c.tenant_id,
         t.nome                                                     AS conta,
         COALESCE(t.ativo, false)                                   AS conta_ativa,
         t.plano                                                    AS plano,
         EXISTS (SELECT 1 FROM public.ponto_diario pd WHERE pd.tenant_id = c.tenant_id)
           OR EXISTS (SELECT 1 FROM public.empresa_cadastro e
                       WHERE e.tenant_id = c.tenant_id AND e.usa_controle_ponto IS TRUE) AS usa_ponto,
         (SELECT count(*) FROM public.admissoes a
           WHERE a.tenant_id = c.tenant_id
             AND a.cpf IS NOT NULL
             AND a.status <> ALL (ARRAY['desligado','reprovado']::admissao_status[]))    AS adm_ativas_total,
         (SELECT count(*) FROM public.empresa_cadastro e
           WHERE e.tenant_id = c.tenant_id AND e.ativo IS TRUE)                          AS empresas_ativas
  FROM contas c
  LEFT JOIN public.tenants t ON t.id = c.tenant_id
)
-- ── Resultado unico ─────────────────────────────────────────────────────────
SELECT
  ord, secao, conta, conta_ativa, usa_ponto,
  grupos, dup_mesma_empresa, possivel_multi_cnpj, com_cpf_faixa_teste, sinais
FROM (
  -- 0) RESUMO GERAL (deve bater com 557 / 11 / 2)
  SELECT 0 AS ord,
         'RESUMO GERAL' AS secao,
         NULL::text AS conta, NULL::boolean AS conta_ativa, NULL::boolean AS usa_ponto,
         (SELECT COALESCE(sum(grupos),0) FROM adm_por_conta) AS grupos,
         (SELECT COALESCE(sum(dup_mesma_empresa),0) FROM adm_por_conta) AS dup_mesma_empresa,
         (SELECT COALESCE(sum(possivel_multi_cnpj),0) FROM adm_por_conta) AS possivel_multi_cnpj,
         (SELECT COALESCE(sum(grupos_cpf_faixa_teste),0) FROM adm_por_conta) AS com_cpf_faixa_teste,
         'ADMISSOES: grupos totais | mesma empresa=dup real | multi=possivel multi-CNPJ | faixa_teste=CPF 900.000.0XX'
           AS sinais

  UNION ALL
  SELECT 1, 'ADMISSAO por conta',
         COALESCE(ctx.conta, '(conta sem cadastro em tenants: ' || left(ap.tenant_id::text,8) || ')'),
         ctx.conta_ativa, ctx.usa_ponto,
         ap.grupos, ap.dup_mesma_empresa, ap.possivel_multi_cnpj, ap.grupos_cpf_faixa_teste,
         concat_ws(' | ',
           CASE WHEN ctx.conta_ativa IS NOT TRUE THEN 'CONTA INATIVA (provavel teste)' END,
           CASE WHEN ctx.conta IS NOT NULL AND ctx.conta ~* '(teste|test|demo|staging|homolog|sandbox|exemplo|qa\M)' THEN 'NOME parece teste' END,
           CASE WHEN ap.grupos_cpf_faixa_teste > 0 THEN 'tem CPF de faixa ficticia' END,
           CASE WHEN ap.grupos_sem_empresa > 0 THEN ap.grupos_sem_empresa::text || ' grupo(s) com admissao SEM empresa vinculada' END,
           CASE WHEN ctx.usa_ponto IS NOT TRUE THEN 'NAO usa ponto (so-psicossocial? nao deveria ter admissao)' END,
           'admissoes ativas na conta=' || COALESCE(ctx.adm_ativas_total,0)::text,
           'empresas ativas=' || COALESCE(ctx.empresas_ativas,0)::text)
  FROM adm_por_conta ap
  LEFT JOIN ctx ON ctx.tenant_id = ap.tenant_id

  UNION ALL
  SELECT 2, 'EMPRESA (CPF) por conta',
         COALESCE(ctx.conta, '(' || left(ep.tenant_id::text,8) || ')'),
         ctx.conta_ativa, ctx.usa_ponto,
         ep.grupos, NULL, NULL, ep.grupos_cpf_faixa_teste,
         concat_ws(' | ',
           CASE WHEN ctx.conta_ativa IS NOT TRUE THEN 'CONTA INATIVA' END,
           CASE WHEN ep.grupos_cpf_faixa_teste > 0 THEN 'tem CPF de faixa ficticia' END,
           'empresas ativas na conta=' || COALESCE(ctx.empresas_ativas,0)::text)
  FROM emp_por_conta ep
  LEFT JOIN ctx ON ctx.tenant_id = ep.tenant_id

  UNION ALL
  SELECT 3, 'VINCULO por conta',
         COALESCE(ctx.conta, '(' || left(vp.tenant_id::text,8) || ')'),
         ctx.conta_ativa, ctx.usa_ponto,
         vp.grupos, NULL, NULL, NULL,
         'vinculos de perfil ativos duplicados (usuario/empresa)'
  FROM vin_por_conta vp
  LEFT JOIN ctx ON ctx.tenant_id = vp.tenant_id
) r
ORDER BY ord, grupos DESC NULLS LAST, conta;
