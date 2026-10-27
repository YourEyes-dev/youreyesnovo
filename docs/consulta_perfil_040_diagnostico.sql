-- SOMENTE LEITURA — diagnostico do PERFIL-040: quantos vinculos/perfis o usuario de teste restrito TEM de verdade.
-- Se vinculos_do_restrito for 2 (um antigo desativado e um ativo), o "le 2 vinculos" do teste antigo era o proprio dado do usuario.
SELECT ub.email_principal,
       count(*)                          AS vinculos_do_restrito,
       count(*) FILTER (WHERE COALESCE(v.ativo, true)) AS vinculos_ativos,
       count(DISTINCT v.perfil_id)       AS perfis_distintos
FROM public.usuarios_base ub
LEFT JOIN public.usuario_perfil_vinculos v ON v.usuario_id = ub.id
WHERE ub.email_principal = 'restrito.e2e@youreyes.local'
GROUP BY ub.email_principal;
