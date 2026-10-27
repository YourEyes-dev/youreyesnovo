-- SOMENTE LEITURA — quem passa a ler MENOS do cadastro de colaboradores (admissoes) com o script_admissoes_trava_leitura.sql.
-- Rode DEPOIS da PARTE 1 (usa a lista de modulos ye_modulos_dados_pessoas()).
-- Lista quem tem papel de gestao (manager/admin), nao e dono nem Super Admin, TEM perfil ativo e cujo perfil NAO libera a ficha
-- completa de todos: "so equipe" = le a ficha dos subordinados diretos; "so a propria" = le so a propria ficha.
-- Quem perde fica com o diretorio de pessoas (nome, cargo, departamento, foto) em todas as telas. Sem perfil vinculado nao muda.
-- Colaborador comum (papel user) passa a ler so a propria ficha: efeito pretendido, nao listado. Nao lista CPF nem dado da ficha.
WITH base AS MATERIALIZED (
  SELECT t.nome AS cliente, ub.id AS usuario_id, ub.nome_completo, ub.tipo_usuario::text AS tipo
  FROM public.usuarios_base ub JOIN public.tenants t ON t.id = ub.tenant_id
  WHERE ub.status::text = 'ativo' AND ub.auth_user_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = ub.auth_user_id AND ur.role::text IN ('manager','admin'))
    AND NOT EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = ub.auth_user_id AND ur.role::text IN ('owner','superadmin'))
    AND EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v JOIN public.perfis_acesso pa ON pa.id = v.perfil_id AND COALESCE(pa.ativo, true)
                 WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true))
), calc AS MATERIALIZED (
  SELECT b.*,
    bool_or(pp.modulo = ANY (public.ye_modulos_dados_pessoas()) AND COALESCE(pp.escopo::text,'') NOT IN ('proprio_usuario','subordinados_diretos')) AS todos,
    bool_or(pp.modulo = ANY (public.ye_modulos_dados_pessoas()) AND COALESCE(pp.escopo::text,'') = 'subordinados_diretos')                           AS equipe
  FROM base b
  LEFT JOIN public.usuario_perfil_vinculos v ON v.usuario_id = b.usuario_id AND COALESCE(v.ativo, true)
  LEFT JOIN public.perfis_acesso pa ON pa.id = v.perfil_id AND COALESCE(pa.ativo, true)
  LEFT JOIN public.perfil_permissoes pp ON pp.perfil_id = pa.id AND COALESCE(pp.ativo, true)
  GROUP BY b.cliente, b.usuario_id, b.nome_completo, b.tipo
)
SELECT cliente, nome_completo, tipo,
       CASE WHEN COALESCE(equipe, false) THEN 'so equipe' ELSE 'so a propria' END AS passa_a_ler_a_ficha_de
FROM calc
WHERE NOT COALESCE(todos, false)
ORDER BY cliente, nome_completo;
