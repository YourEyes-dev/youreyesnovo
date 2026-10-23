-- SOMENTE LEITURA — quem passa a NAO ver (nem gravar) as trilhas de auditoria de usuarios e perfis
-- (aba de historico do usuario e auditoria de perfis) com o script_logs_de_acesso_por_perfil.sql.
-- Lista quem tem papel de gestao (manager/admin), nao e dono nem Super Admin, e: (a) tem perfil ativo que NAO traz
-- Usuarios, Perfis & Acessos ou Configuracoes em escopo amplo; ou (b) nao tem perfil e portanto segue o legado (nao muda).
-- Colaborador comum nao e listado: nunca deveria ler as trilhas. Nao lista CPF nem conteudo das trilhas.
WITH base AS MATERIALIZED (
  SELECT t.nome AS cliente, ub.id AS usuario_id, ub.nome_completo, ub.tipo_usuario::text AS tipo
  FROM public.usuarios_base ub JOIN public.tenants t ON t.id = ub.tenant_id
  WHERE ub.status::text = 'ativo' AND ub.auth_user_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = ub.auth_user_id AND ur.role::text IN ('manager','admin'))
    AND NOT EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = ub.auth_user_id AND ur.role::text IN ('owner','superadmin'))
    AND EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v JOIN public.perfis_acesso pa ON pa.id = v.perfil_id AND COALESCE(pa.ativo, true)
                 WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true))
), mod AS MATERIALIZED (
  SELECT b.usuario_id,
    bool_or(pp.modulo IN ('usuarios','perfis_acesso','configuracoes') AND COALESCE(pp.escopo::text,'') <> 'proprio_usuario') AS le_trilhas,
    bool_or(pp.modulo IN ('usuarios','perfis_acesso','configuracoes') AND COALESCE(pp.escopo::text,'') <> 'proprio_usuario'
            AND pp.acao::text IN ('criar','editar','aprovar','excluir','administrar')) AS grava_trilhas
  FROM base b
  JOIN public.usuario_perfil_vinculos v ON v.usuario_id = b.usuario_id AND COALESCE(v.ativo, true)
  JOIN public.perfil_permissoes pp ON pp.perfil_id = v.perfil_id AND COALESCE(pp.ativo, true)
  GROUP BY b.usuario_id
)
SELECT b.cliente, b.nome_completo, b.tipo,
       CASE WHEN COALESCE(m.le_trilhas, false)    THEN 'le' ELSE 'NAO le' END     AS trilhas_de_usuarios_e_perfis,
       CASE WHEN COALESCE(m.grava_trilhas, false) THEN 'grava' ELSE 'NAO grava' END AS registro_das_acoes
FROM base b LEFT JOIN mod m ON m.usuario_id = b.usuario_id
WHERE NOT COALESCE(m.le_trilhas, false) OR NOT COALESCE(m.grava_trilhas, false)
ORDER BY b.cliente, b.nome_completo;
