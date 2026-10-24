-- SOMENTE LEITURA — quem passa a ler/gravar MENOS no cadastro de usuarios (usuarios_base) com o script_usuarios_base_trava.sql (PARTE 2).
-- Lista quem tem papel de gestao (manager/admin), nao e dono nem Super Admin, TEM perfil ativo e cujo perfil NAO libera algum item:
--   le_lista_de_usuarios = ve a ficha de TODOS os usuarios (modulos Usuarios, Configuracoes ou Perfis & Acessos, escopo alem do proprio)
--   cria_usuarios        = cadastra usuario (modulos Usuarios ou Configuracoes, com criar/administrar)
--   edita_usuarios       = altera o cadastro de outros usuarios (modulos Usuarios ou Configuracoes, com editar/aprovar/administrar)
-- Quem perde a lista continua usando todos os seletores de pessoas (nome, foto, cargo, so ativos) e o proprio cadastro.
-- Sem perfil vinculado nao muda. Colaborador comum (papel user) passa a ler so a propria linha: efeito pretendido, nao listado.
-- Nao lista CPF, e-mail nem dado da ficha.
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
                     AND COALESCE(pp.escopo::text,'') <> 'proprio_usuario'), false) AS le_lista,
    COALESCE(bool_or(pp.modulo IN ('usuarios','configuracoes')
                     AND pp.acao::text IN ('criar','administrar')
                     AND COALESCE(pp.escopo::text,'') NOT IN ('proprio_usuario','subordinados_diretos')), false) AS cria,
    COALESCE(bool_or(pp.modulo IN ('usuarios','configuracoes')
                     AND pp.acao::text IN ('editar','aprovar','administrar')
                     AND COALESCE(pp.escopo::text,'') NOT IN ('proprio_usuario','subordinados_diretos')), false) AS edita
  FROM base b
  LEFT JOIN public.usuario_perfil_vinculos v ON v.usuario_id = b.usuario_id AND COALESCE(v.ativo, true)
  LEFT JOIN public.perfis_acesso pa ON pa.id = v.perfil_id AND COALESCE(pa.ativo, true)
  LEFT JOIN public.perfil_permissoes pp ON pp.perfil_id = pa.id AND COALESCE(pp.ativo, true)
  GROUP BY b.cliente, b.usuario_id, b.nome_completo, b.tipo
)
SELECT cliente, nome_completo, tipo,
       CASE WHEN le_lista THEN 'continua' ELSE 'PERDE' END AS le_lista_de_usuarios,
       CASE WHEN cria     THEN 'continua' ELSE 'PERDE' END AS cria_usuarios,
       CASE WHEN edita    THEN 'continua' ELSE 'PERDE' END AS edita_usuarios
FROM calc
WHERE NOT (le_lista AND cria AND edita)
ORDER BY cliente, nome_completo;
