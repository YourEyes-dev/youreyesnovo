-- SOMENTE LEITURA — quem hoje ve TODAS as manifestacoes da Ouvidoria e deixa de ver
-- depois do script_ouvidoria_escopo_pelo_perfil.sql (perfil vinculado sem Ouvidoria em
-- escopo amplo). Dono (owner) e Super Admin nao mudam. Quem NAO tem perfil vinculado nao muda.
WITH base AS MATERIALIZED (
  SELECT t.nome AS cliente, ub.id AS usuario_id, ub.nome_completo, ub.tipo_usuario::text AS tipo,
         ub.auth_user_id, ub.tenant_id
  FROM public.usuarios_base ub
  JOIN public.tenants t ON t.id = ub.tenant_id
  WHERE ub.status::text = 'ativo' AND ub.auth_user_id IS NOT NULL
)
SELECT b.cliente, b.nome_completo, b.tipo,
       (SELECT string_agg(ur.role::text, ', ' ORDER BY ur.role::text) FROM public.user_roles ur WHERE ur.user_id = b.auth_user_id) AS papeis,
       (SELECT string_agg(DISTINCT pa.nome, ', ')
          FROM public.usuario_perfil_vinculos v JOIN public.perfis_acesso pa ON pa.id = v.perfil_id
         WHERE v.usuario_id = b.usuario_id AND COALESCE(v.ativo, true)) AS perfis,
       COALESCE((SELECT string_agg(DISTINCT pp.acao::text || ':' || pp.escopo::text, ', ')
          FROM public.usuario_perfil_vinculos v JOIN public.perfil_permissoes pp ON pp.perfil_id = v.perfil_id
         WHERE v.usuario_id = b.usuario_id AND COALESCE(v.ativo, true) AND COALESCE(pp.ativo, true)
           AND pp.modulo = 'ouvidoria'), '(nenhuma)') AS ouvidoria_no_perfil
FROM base b
WHERE EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = b.auth_user_id AND ur.role::text IN ('manager','admin'))
  AND NOT EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = b.auth_user_id AND ur.role::text IN ('owner','superadmin'))
  AND EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v
               JOIN public.perfis_acesso pa ON pa.id = v.perfil_id AND COALESCE(pa.ativo, true)
              WHERE v.usuario_id = b.usuario_id AND COALESCE(v.ativo, true))
  AND NOT EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v
               JOIN public.perfil_permissoes pp ON pp.perfil_id = v.perfil_id AND COALESCE(pp.ativo, true)
              WHERE v.usuario_id = b.usuario_id AND COALESCE(v.ativo, true)
                AND pp.modulo = 'ouvidoria' AND COALESCE(pp.escopo::text, '') <> 'proprio_usuario')
ORDER BY b.cliente, b.nome_completo;
