-- SOMENTE LEITURA — quem passa a ver MENOS dados de jornada com o script_jornada_lote1a_leitura_por_perfil.sql.
-- Colaborador comum (papel user) tambem passa a ver so a propria linha: isso e o efeito pretendido e NAO e listado.
-- Aqui entram so quem tem papel de gestao (manager/admin), nao e dono, TEM perfil ativo e cujo perfil nao libera
-- Ponto/Colaboradores em escopo amplo. Quem nao tem perfil vinculado nao muda (legado).
WITH base AS MATERIALIZED (
  SELECT t.nome AS cliente, ub.id AS usuario_id, ub.nome_completo, ub.tipo_usuario::text AS tipo, ub.auth_user_id
  FROM public.usuarios_base ub JOIN public.tenants t ON t.id = ub.tenant_id
  WHERE ub.status::text = 'ativo' AND ub.auth_user_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = ub.auth_user_id AND ur.role::text IN ('manager','admin'))
    AND NOT EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = ub.auth_user_id AND ur.role::text IN ('owner','superadmin'))
    AND EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v JOIN public.perfis_acesso pa ON pa.id = v.perfil_id AND COALESCE(pa.ativo, true)
                 WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true))
), mod AS MATERIALIZED (
  SELECT b.usuario_id,
    bool_or(pp.modulo IN ('ponto','colaboradores') AND COALESCE(pp.escopo::text,'') NOT IN ('proprio_usuario','subordinados_diretos'))  AS amplo_ponto,
    bool_or(pp.modulo IN ('ponto','colaboradores') AND COALESCE(pp.escopo::text,'') = 'subordinados_diretos')                           AS sub_ponto,
    bool_or(pp.modulo IN ('analise_jornada','ponto','colaboradores') AND COALESCE(pp.escopo::text,'') NOT IN ('proprio_usuario','subordinados_diretos')) AS amplo_jornada
  FROM base b
  JOIN public.usuario_perfil_vinculos v ON v.usuario_id = b.usuario_id AND COALESCE(v.ativo, true)
  JOIN public.perfil_permissoes pp ON pp.perfil_id = v.perfil_id AND COALESCE(pp.ativo, true)
  GROUP BY b.usuario_id
)
SELECT b.cliente, b.nome_completo, b.tipo,
       CASE WHEN COALESCE(m.amplo_ponto, false)  THEN 'todas'
            WHEN COALESCE(m.sub_ponto, false)    THEN 'propria + subordinados'
            ELSE 'so a propria' END                                   AS ponto_banco_horas_ajustes_etc,
       CASE WHEN COALESCE(m.amplo_jornada, false) THEN 'todas'
            WHEN COALESCE(m.sub_ponto, false)     THEN 'propria + subordinados'
            ELSE 'so a propria' END                                   AS analise_de_jornada
FROM base b LEFT JOIN mod m ON m.usuario_id = b.usuario_id
WHERE NOT COALESCE(m.amplo_ponto, false) OR NOT COALESCE(m.amplo_jornada, false)
ORDER BY b.cliente, b.nome_completo;
