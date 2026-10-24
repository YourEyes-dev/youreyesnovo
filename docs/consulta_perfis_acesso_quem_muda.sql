-- SOMENTE LEITURA — quem passa a ler/gravar MENOS nas tabelas de perfis de acesso (perfis_acesso, perfil_permissoes,
-- perfil_excecoes, usuario_perfil_vinculos) com o script_perfis_acesso_leitura_escrita.sql.
-- Lista quem tem papel de gestao (manager/admin), nao e dono nem Super Admin, TEM perfil ativo e cujo perfil NAO libera algum dos itens abaixo.
--   ve_gestao_de_acessos     = enxerga os perfis/permissoes/liberacoes/vinculos de TODOS (modulos Usuarios, Configuracoes ou Perfis & Acessos, escopo alem do proprio)
--   edita_perfis             = cria/edita perfis e permissoes (modulos Perfis & Acessos ou Configuracoes, com criar/editar/excluir/administrar)
--   concede_acessos          = cria/edita vinculos de perfil e liberacoes (modulos Usuarios, Configuracoes ou Perfis & Acessos, idem)
-- Quem perde continua vendo o PROPRIO perfil e o menu normalmente. Sem perfil vinculado nao muda. Colaborador comum (papel user) passa a ver
-- so o proprio perfil: efeito pretendido, nao listado. Nao lista CPF nem dado da ficha.
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
    COALESCE(bool_or(pp.modulo IN ('usuarios','configuracoes','perfis_acesso')
                     AND COALESCE(pp.escopo::text,'') <> 'proprio_usuario'), false) AS ve_gestao_de_acessos,
    COALESCE(bool_or(pp.modulo IN ('perfis_acesso','configuracoes')
                     AND pp.acao::text IN ('criar','editar','excluir','administrar')
                     AND COALESCE(pp.escopo::text,'') NOT IN ('proprio_usuario','subordinados_diretos')), false) AS edita_perfis,
    COALESCE(bool_or(pp.modulo IN ('usuarios','configuracoes','perfis_acesso')
                     AND pp.acao::text IN ('criar','editar','aprovar','excluir','administrar')
                     AND COALESCE(pp.escopo::text,'') NOT IN ('proprio_usuario','subordinados_diretos')), false) AS concede_acessos
  FROM base b
  LEFT JOIN public.usuario_perfil_vinculos v ON v.usuario_id = b.usuario_id AND COALESCE(v.ativo, true)
  LEFT JOIN public.perfis_acesso pa ON pa.id = v.perfil_id AND COALESCE(pa.ativo, true)
  LEFT JOIN public.perfil_permissoes pp ON pp.perfil_id = pa.id AND COALESCE(pp.ativo, true)
  GROUP BY b.cliente, b.usuario_id, b.nome_completo, b.tipo
)
SELECT cliente, nome_completo, tipo,
       CASE WHEN ve_gestao_de_acessos THEN 'continua' ELSE 'PERDE' END AS ve_gestao_de_acessos,
       CASE WHEN edita_perfis         THEN 'continua' ELSE 'PERDE' END AS edita_perfis,
       CASE WHEN concede_acessos      THEN 'continua' ELSE 'PERDE' END AS concede_acessos
FROM calc
WHERE NOT (ve_gestao_de_acessos AND edita_perfis AND concede_acessos)
ORDER BY cliente, nome_completo;
