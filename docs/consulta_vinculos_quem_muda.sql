-- SOMENTE LEITURA — quem passa a NAO conseguir ver ou alterar os VINCULOS de usuario (empresas a que cada um tem acesso)
-- com o script_usuario_vinculos_por_perfil.sql. Mostra, para quem tem perfil ativo e (tem Usuarios/Configuracoes no perfil OU
-- papel de gestao), o alcance por verbo: 'amplo' = faz em qualquer vinculo; 'NAO' = nao faz.
-- criar = incluir vinculo; editar = alterar ou encerrar vinculo; excluir nao se aplica (o app encerra por alteracao).
-- Quem tem papel de gestao mas o perfil nao traz Usuarios/Configuracoes aparece com NAO: perde a tela de gestao de vinculos.
-- Aparecem so os que tem pelo menos um verbo faltando. Dono e Super Admin nao mudam e nao entram. Nao lista CPF.
WITH base AS MATERIALIZED (
  SELECT t.nome AS cliente, ub.id AS usuario_id, ub.nome_completo, ub.tipo_usuario::text AS tipo,
         EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = ub.auth_user_id AND ur.role::text IN ('manager','admin')) AS papel_gestao
  FROM public.usuarios_base ub JOIN public.tenants t ON t.id = ub.tenant_id
  WHERE ub.status::text = 'ativo' AND ub.auth_user_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v JOIN public.perfis_acesso pa ON pa.id = v.perfil_id AND COALESCE(pa.ativo, true)
                 WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true))
    AND NOT EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = ub.auth_user_id AND ur.role::text IN ('owner','superadmin'))
), verbos AS MATERIALIZED (
  SELECT b.usuario_id,
    bool_or(pp.acao::text IN ('criar','administrar') AND COALESCE(pp.escopo::text,'') NOT IN ('proprio_usuario','subordinados_diretos')) AS criar_amplo,
    bool_or(pp.acao::text IN ('criar','administrar') AND COALESCE(pp.escopo::text,'') = 'subordinados_diretos')                           AS criar_equipe,
    bool_or(pp.acao::text IN ('editar','aprovar','administrar') AND COALESCE(pp.escopo::text,'') NOT IN ('proprio_usuario','subordinados_diretos')) AS editar_amplo,
    bool_or(pp.acao::text IN ('editar','aprovar','administrar') AND COALESCE(pp.escopo::text,'') = 'subordinados_diretos')                           AS editar_equipe,
    bool_or(pp.acao::text IN ('excluir','administrar') AND COALESCE(pp.escopo::text,'') NOT IN ('proprio_usuario','subordinados_diretos')) AS excluir_amplo,
    bool_or(pp.acao::text IN ('excluir','administrar') AND COALESCE(pp.escopo::text,'') = 'subordinados_diretos')                           AS excluir_equipe
  FROM base b
  JOIN public.usuario_perfil_vinculos v ON v.usuario_id = b.usuario_id AND COALESCE(v.ativo, true)
  JOIN public.perfis_acesso pa ON pa.id = v.perfil_id AND COALESCE(pa.ativo, true)
  JOIN public.perfil_permissoes pp ON pp.perfil_id = v.perfil_id AND COALESCE(pp.ativo, true)
  WHERE pp.modulo IN ('usuarios','configuracoes')
  GROUP BY b.usuario_id
)
SELECT b.cliente, b.nome_completo, b.tipo,
       CASE WHEN COALESCE(x.criar_amplo,false)   THEN 'amplo' WHEN COALESCE(x.criar_equipe,false)   THEN 'so equipe' ELSE 'NAO' END AS criar,
       CASE WHEN COALESCE(x.editar_amplo,false)  THEN 'amplo' WHEN COALESCE(x.editar_equipe,false)  THEN 'so equipe' ELSE 'NAO' END AS editar,
       'n/a' AS excluir
FROM base b LEFT JOIN verbos x ON x.usuario_id = b.usuario_id
WHERE (x.usuario_id IS NOT NULL OR b.papel_gestao)
  AND NOT (COALESCE(x.criar_amplo, false) AND COALESCE(x.editar_amplo, false))
ORDER BY b.cliente, b.nome_completo;
