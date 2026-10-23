-- SOMENTE LEITURA — usuarios SEM perfil de acesso vinculado, por cliente, papel e tipo.
-- Sem perfil, a escrita na jornada segue o legado: papel de gestao (manager/admin) ou tipo administrador/gestor grava;
-- papel comum (user) deixa de gravar (antes gravava, por so o tenant decidir). Nao lista nomes nem CPF.
WITH sem AS MATERIALIZED (
  SELECT t.nome AS cliente, ub.tipo_usuario::text AS tipo,
         COALESCE((SELECT string_agg(DISTINCT ur.role::text, '+' ORDER BY ur.role::text) FROM public.user_roles ur WHERE ur.user_id = ub.auth_user_id), 'sem papel') AS papel,
         (EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = ub.auth_user_id AND ur.role::text IN ('manager','admin','owner','superadmin'))
          OR ub.tipo_usuario::text IN ('administrador','gestor')) AS legado_grava
  FROM public.usuarios_base ub JOIN public.tenants t ON t.id = ub.tenant_id
  WHERE ub.status::text = 'ativo' AND ub.auth_user_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v JOIN public.perfis_acesso pa ON pa.id = v.perfil_id AND COALESCE(pa.ativo, true)
                     WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true))
)
SELECT cliente, papel, tipo, count(*) AS usuarios,
       CASE WHEN legado_grava THEN 'continua gravando (legado)' ELSE 'deixa de gravar' END AS efeito
FROM sem
GROUP BY cliente, papel, tipo, legado_grava
ORDER BY legado_grava, cliente, papel;
