-- SOMENTE LEITURA — quem passa a ver MENOS dados de saude e RH com o script_saude_rh_leitura_por_perfil.sql.
-- Considera quem tem papel de gestao (manager/admin), nao e dono nem Super Admin, TEM perfil ativo e cujo perfil nao libera
-- tudo. Quem nao tem perfil vinculado nao muda (legado). Colaborador comum passa a ver so a propria linha: efeito pretendido.
-- Colunas: afastamentos = todos / so equipe / so os proprios; motivo_no_selo = o selo "Afastado" mostra o motivo clinico?;
-- esocial = ve os eventos eSocial?; contratos = ve os contratos de experiencia (todos/equipe/proprios)?;
-- certificado = pode gravar o certificado digital da empresa? Nao lista CPF nem conteudo.
WITH base AS MATERIALIZED (
  SELECT t.nome AS cliente, ub.id AS usuario_id, ub.nome_completo, ub.tipo_usuario::text AS tipo
  FROM public.usuarios_base ub JOIN public.tenants t ON t.id = ub.tenant_id
  WHERE ub.status::text = 'ativo' AND ub.auth_user_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = ub.auth_user_id AND ur.role::text IN ('manager','admin'))
    AND NOT EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = ub.auth_user_id AND ur.role::text IN ('owner','superadmin'))
    AND EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v JOIN public.perfis_acesso pa ON pa.id = v.perfil_id AND COALESCE(pa.ativo, true)
                 WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true))
), perm AS MATERIALIZED (
  SELECT b.usuario_id, pp.modulo, pp.acao::text AS acao, COALESCE(pp.escopo::text, '') AS escopo
  FROM base b
  JOIN public.usuario_perfil_vinculos v ON v.usuario_id = b.usuario_id AND COALESCE(v.ativo, true)
  JOIN public.perfis_acesso pa ON pa.id = v.perfil_id AND COALESCE(pa.ativo, true)
  JOIN public.perfil_permissoes pp ON pp.perfil_id = v.perfil_id AND COALESCE(pp.ativo, true)
), calc AS MATERIALIZED (
  SELECT b.*,
    bool_or(p.modulo IN ('atestados','sst','colaboradores','ferias','financeiro','psicossocial','ponto') AND p.escopo NOT IN ('proprio_usuario','subordinados_diretos')) AS afast_todos,
    bool_or(p.modulo IN ('atestados','sst','colaboradores','ferias','financeiro','psicossocial','ponto') AND p.escopo = 'subordinados_diretos')                      AS afast_equipe,
    bool_or(p.modulo IN ('atestados','sst') AND p.escopo NOT IN ('proprio_usuario','subordinados_diretos'))                                                                AS motivo,
    bool_or(p.modulo IN ('financeiro','incidentes','sst','configuracoes') AND p.escopo <> 'proprio_usuario')                                                                AS esocial,
    bool_or(p.modulo IN ('contratos_experiencia','admissoes','onboarding','colaboradores') AND p.escopo NOT IN ('proprio_usuario','subordinados_diretos'))                  AS contr_todos,
    bool_or(p.modulo IN ('contratos_experiencia','admissoes','onboarding','colaboradores') AND p.escopo = 'subordinados_diretos')                                           AS contr_equipe,
    bool_or(p.modulo = 'configuracoes' AND p.escopo <> 'proprio_usuario' AND p.acao IN ('criar','editar','aprovar','excluir','administrar'))                                AS cert_grava
  FROM base b LEFT JOIN perm p ON p.usuario_id = b.usuario_id
  GROUP BY b.cliente, b.usuario_id, b.nome_completo, b.tipo
)
SELECT cliente, nome_completo, tipo,
       CASE WHEN COALESCE(afast_todos, false) THEN 'todos' WHEN COALESCE(afast_equipe, false) THEN 'so equipe' ELSE 'so os proprios' END AS afastamentos,
       CASE WHEN COALESCE(motivo, false) THEN 'sim' ELSE 'nao' END        AS motivo_no_selo,
       CASE WHEN COALESCE(esocial, false) THEN 'sim' ELSE 'nao' END       AS esocial,
       CASE WHEN COALESCE(contr_todos, false) THEN 'todos' WHEN COALESCE(contr_equipe, false) THEN 'so equipe' ELSE 'so os proprios' END AS contratos_experiencia,
       CASE WHEN COALESCE(cert_grava, false) THEN 'sim' ELSE 'nao' END    AS certificado_digital_grava
FROM calc
WHERE NOT (COALESCE(afast_todos, false) AND COALESCE(motivo, false) AND COALESCE(esocial, false) AND COALESCE(contr_todos, false) AND COALESCE(cert_grava, false))
ORDER BY cliente, nome_completo;
