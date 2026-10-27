-- SOMENTE LEITURA — quem passa a ter MENOS acesso a arquivos com o script_arquivos_lote0_empresa_e_perfil.sql.
-- Lista usuarios com papel de gestao (manager/admin), SEM papel de dono, que TEM perfil de acesso ativo
-- mas cujo perfil nao traz o modulo em escopo amplo. Quem nao tem perfil vinculado nao muda (legado).
-- Colunas "perde_*": true = deixa de ler/enviar/apagar arquivos daquele tipo.
WITH base AS MATERIALIZED (
  SELECT t.nome AS cliente, ub.id AS usuario_id, ub.nome_completo, ub.tipo_usuario::text AS tipo, ub.auth_user_id
  FROM public.usuarios_base ub JOIN public.tenants t ON t.id = ub.tenant_id
  WHERE ub.status::text = 'ativo' AND ub.auth_user_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = ub.auth_user_id AND ur.role::text IN ('manager','admin'))
    AND NOT EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = ub.auth_user_id AND ur.role::text IN ('owner','superadmin'))
    AND EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v JOIN public.perfis_acesso pa ON pa.id = v.perfil_id AND COALESCE(pa.ativo, true)
                 WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true))
), tem AS MATERIALIZED (
  SELECT b.usuario_id,
    bool_or(pp.modulo IN ('atestados','sst'))        AS atestados,
    bool_or(pp.modulo IN ('trilhas','aprendizado'))  AS trilhas,
    bool_or(pp.modulo = 'epi')                       AS epi,
    bool_or(pp.modulo = 'ergonomia')                 AS ergonomia,
    bool_or(pp.modulo = 'hub_contabil')              AS hub_contabil
  FROM base b
  JOIN public.usuario_perfil_vinculos v ON v.usuario_id = b.usuario_id AND COALESCE(v.ativo, true)
  JOIN public.perfil_permissoes pp ON pp.perfil_id = v.perfil_id AND COALESCE(pp.ativo, true)
       AND COALESCE(pp.escopo::text, '') <> 'proprio_usuario'
  GROUP BY b.usuario_id
)
SELECT b.cliente, b.nome_completo, b.tipo,
       NOT COALESCE(t.atestados, false)    AS perde_atestados,
       NOT COALESCE(t.trilhas, false)      AS perde_trilha,
       NOT COALESCE(t.epi, false)          AS perde_epi_exclusao,
       NOT COALESCE(t.ergonomia, false)    AS perde_ergonomia_exclusao,
       NOT COALESCE(t.hub_contabil, false) AS perde_hub_exclusao
FROM base b LEFT JOIN tem t ON t.usuario_id = b.usuario_id
WHERE NOT (COALESCE(t.atestados, false) AND COALESCE(t.trilhas, false) AND COALESCE(t.epi, false)
           AND COALESCE(t.ergonomia, false) AND COALESCE(t.hub_contabil, false))
ORDER BY b.cliente, b.nome_completo;
