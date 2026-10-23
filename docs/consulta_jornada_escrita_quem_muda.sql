-- SOMENTE LEITURA — quem passa a NAO conseguir gravar na jornada com o script_jornada_escrita_por_perfil.sql.
-- Lista quem tem perfil ativo e (tem Ponto/Colaboradores/Analise de Jornada no perfil OU tem papel de gestao) e mostra, por verbo, o alcance da escrita:
--   'amplo'    = grava em qualquer linha da empresa;   'so equipe' = so na linha de subordinado direto;   'NAO' = nao grava.
-- Quem tem papel de gestao mas o perfil nao traz Ponto aparece com NAO nos tres (e o caso do gestor que gravava sem o perfil permitir).
-- Aparecem so os que tem pelo menos um verbo faltando. Dono e Super Admin nunca mudam e nao entram.
-- criar = incluir registro (escala, banco de horas, acordo, link...); editar = alterar ou resolver alerta (vale tambem aprovar);
-- excluir = apagar. Quem tem 'administrar' no modulo vale por todos os verbos.
-- Nao lista CPF nem dado de jornada: so nome do usuario e alcance.
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
  WHERE pp.modulo IN ('ponto','colaboradores','analise_jornada')
  GROUP BY b.usuario_id
)
SELECT b.cliente, b.nome_completo, b.tipo,
       CASE WHEN COALESCE(x.criar_amplo,false)   THEN 'amplo' WHEN COALESCE(x.criar_equipe,false)   THEN 'so equipe' ELSE 'NAO' END AS criar,
       CASE WHEN COALESCE(x.editar_amplo,false)  THEN 'amplo' WHEN COALESCE(x.editar_equipe,false)  THEN 'so equipe' ELSE 'NAO' END AS editar,
       CASE WHEN COALESCE(x.excluir_amplo,false) THEN 'amplo' WHEN COALESCE(x.excluir_equipe,false) THEN 'so equipe' ELSE 'NAO' END AS excluir
FROM base b LEFT JOIN verbos x ON x.usuario_id = b.usuario_id
WHERE (x.usuario_id IS NOT NULL OR b.papel_gestao)
  AND NOT (COALESCE(x.criar_amplo, false) AND COALESCE(x.editar_amplo, false) AND COALESCE(x.excluir_amplo, false))
ORDER BY b.cliente, b.nome_completo;
