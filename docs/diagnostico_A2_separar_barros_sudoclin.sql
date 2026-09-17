-- ============================================================================
-- DIAGNOSTICO — separar os DOIS grupos na conta "Barros & Nuernberg" (LEITURA).
--
-- Hipotese a confirmar: a conta que aparece com 1112 empresas e nome
-- "BARROS & NUERNBERG" na verdade mistura:
--   (a) os ~1112 clientes SO-PSICOSSOCIAL (responsavel leiri@sudoclin.com); e
--   (b) o grupo PROPRIO da Barros (4 CNPJs, sistema inteiro + ponto,
--       responsavel leirinuernberg@gmail.com).
-- A "promocao" para separar pode nao ter ocorrido de fato no banco.
--
-- Nao altera nada. Nao expoe CPF nem nome de pessoa. Mostra e-mail responsavel
-- (dado que voce mesmo forneceu), nome da conta, CNPJ das empresas-chave e
-- contagens. Predicado de admissao "ativa" identico ao indice A2.
-- ============================================================================

WITH
-- ── Contexto por conta ──────────────────────────────────────────────────────
tstat AS MATERIALIZED (
  SELECT t.id AS tenant_id, t.nome, t.ativo, t.plano,
         (SELECT count(*) FROM public.empresa_cadastro e WHERE e.tenant_id=t.id AND e.ativo IS TRUE) AS empresas_ativas,
         (SELECT count(*) FROM public.admissoes a WHERE a.tenant_id=t.id AND a.cpf IS NOT NULL
             AND a.status <> ALL (ARRAY['desligado','reprovado']::admissao_status[]))              AS adm_ativas,
         EXISTS (SELECT 1 FROM public.ponto_diario pd WHERE pd.tenant_id=t.id)
           OR EXISTS (SELECT 1 FROM public.empresa_cadastro e WHERE e.tenant_id=t.id AND e.usa_controle_ponto IS TRUE) AS usa_ponto
  FROM public.tenants t
),
-- ── E-mails responsaveis -> conta (por usuarios_base e por profiles/auth) ────
emails AS MATERIALIZED (
  SELECT lower(ub.email_principal) AS email, ub.tenant_id, ub.tipo_usuario::text AS papel, 'usuarios_base' AS fonte
  FROM public.usuarios_base ub
  WHERE ub.email_principal ~* '(sudoclin|sudomed|nuernberg|nuberg)'
  UNION
  SELECT lower(au.email), p.tenant_id, COALESCE(p.cargo,'(profile)'), 'profiles/auth' AS fonte
  FROM public.profiles p
  JOIN auth.users au ON au.id = p.user_id
  WHERE au.email ~* '(sudoclin|sudomed|nuernberg|nuberg)'
),
-- ── As 4 empresas-chave do grupo Barros (por CNPJ) ──────────────────────────
alvo(cnpjn) AS (VALUES
  ('26114701000145'),('31219374000126'),('41085456000189'),('41085456000260')
),
empresas_alvo AS MATERIALIZED (
  SELECT a.cnpjn, e.tenant_id, e.id AS empresa_id, e.razao_social, e.ativo, e.usa_controle_ponto,
         (SELECT count(*) FROM public.admissoes ad WHERE ad.empresa_id=e.id AND ad.cpf IS NOT NULL
             AND ad.status <> ALL (ARRAY['desligado','reprovado']::admissao_status[])) AS adm_ativas_empresa
  FROM alvo a
  LEFT JOIN public.empresa_cadastro e
         ON regexp_replace(COALESCE(e.cnpj,''),'[^0-9]','','g') = a.cnpjn
),
-- ── Grupos de duplicata "mesma empresa" e a empresa deles ───────────────────
adm AS MATERIALIZED (
  SELECT tenant_id, empresa_id, regexp_replace(cpf,'[^0-9]','','g') AS cpfn
  FROM public.admissoes
  WHERE cpf IS NOT NULL AND status <> ALL (ARRAY['desligado','reprovado']::admissao_status[])
),
grp AS MATERIALIZED (
  SELECT tenant_id, cpfn,
         count(DISTINCT COALESCE(empresa_id,'00000000-0000-0000-0000-000000000000'::uuid)) AS n_emp,
         min(COALESCE(empresa_id,'00000000-0000-0000-0000-000000000000'::uuid))             AS emp_key
  FROM adm GROUP BY tenant_id, cpfn HAVING count(*) > 1
),
dup_mesma AS MATERIALIZED (
  SELECT g.tenant_id, g.emp_key,
         e.usa_controle_ponto AS emp_ponto,
         (regexp_replace(COALESCE(e.cnpj,''),'[^0-9]','','g') IN (SELECT cnpjn FROM alvo)) AS emp_do_grupo
  FROM grp g
  LEFT JOIN public.empresa_cadastro e ON e.id = g.emp_key
  WHERE g.n_emp = 1
),
dup_por_conta AS MATERIALIZED (
  SELECT tenant_id,
         count(*)                                          AS grupos,
         count(*) FILTER (WHERE emp_ponto IS TRUE)         AS em_empresa_com_ponto,
         count(*) FILTER (WHERE emp_ponto IS NOT TRUE)     AS em_empresa_sem_ponto,
         count(*) FILTER (WHERE emp_do_grupo)              AS em_cnpj_do_grupo_barros
  FROM dup_mesma GROUP BY tenant_id
)
SELECT * FROM (
  -- 1) E-mail responsavel -> qual conta
  SELECT 1 AS ord, '1) E-mail -> conta' AS secao,
         e.email AS chave,
         COALESCE(ts.nome,'(sem tenant)') AS conta,
         left(e.tenant_id::text,8) AS conta_id8,
         ts.ativo AS conta_ativa, ts.usa_ponto,
         ts.empresas_ativas, ts.adm_ativas,
         'papel=' || COALESCE(e.papel,'?') || ' | fonte=' || e.fonte AS detalhe
  FROM (SELECT DISTINCT email, tenant_id, papel, fonte FROM emails) e
  LEFT JOIN tstat ts ON ts.tenant_id = e.tenant_id

  UNION ALL
  -- 2) Cada CNPJ do grupo Barros -> em qual conta esta
  SELECT 2, '2) CNPJ do grupo Barros -> conta',
         ea.cnpjn,
         COALESCE(ts.nome,'(CNPJ NAO ENCONTRADO)'),
         left(ea.tenant_id::text,8),
         ts.ativo, ea.usa_controle_ponto,
         ts.empresas_ativas, ea.adm_ativas_empresa,
         'razao=' || COALESCE(ea.razao_social,'?') || ' | empresa_ativa=' || COALESCE(ea.ativo::text,'?')
  FROM empresas_alvo ea
  LEFT JOIN tstat ts ON ts.tenant_id = ea.tenant_id

  UNION ALL
  -- 3) Onde estao os grupos de duplicata (empresa usa ponto? e do grupo Barros?)
  SELECT 3, '3) Duplicatas (mesma empresa) por tipo',
         'grupos=' || dpc.grupos::text,
         COALESCE(ts.nome,'(' || left(dpc.tenant_id::text,8) || ')'),
         left(dpc.tenant_id::text,8),
         ts.ativo, ts.usa_ponto,
         ts.empresas_ativas, ts.adm_ativas,
         'em empresa COM ponto=' || dpc.em_empresa_com_ponto::text
           || ' | em empresa SEM ponto=' || dpc.em_empresa_sem_ponto::text
           || ' | nos 4 CNPJs do grupo Barros=' || dpc.em_cnpj_do_grupo_barros::text
  FROM dup_por_conta dpc
  LEFT JOIN tstat ts ON ts.tenant_id = dpc.tenant_id
) r
ORDER BY ord, conta, chave;
