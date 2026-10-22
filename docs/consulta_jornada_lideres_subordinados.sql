-- SOMENTE LEITURA — os lideres com Ponto em escopo "subordinados diretos" enxergam a equipe?
-- Para cada lider (papel de gestao, perfil com Ponto/Colaboradores so em subordinados diretos), conta quantas
-- pessoas o sistema reconhece como subordinadas: (1) admissao com o CPF do lider em gestor_cpf; (2) pessoas de
-- departamentos que a ficha do lider chefia (departamentos.gestor_admissao_id). Zero nas duas = o lider so ve a si mesmo.
-- Nao mostra CPF nem dado de jornada: so o nome do lider e as contagens.
WITH lideres AS MATERIALIZED (
  SELECT t.nome AS cliente, ub.tenant_id, ub.nome_completo,
         regexp_replace(COALESCE(ub.cpf, ''), '[^0-9]', '', 'g') AS cpf
  FROM public.usuarios_base ub
  JOIN public.tenants t ON t.id = ub.tenant_id
  WHERE ub.status::text = 'ativo' AND ub.auth_user_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = ub.auth_user_id AND ur.role::text IN ('manager','admin'))
    AND EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v
                  JOIN public.perfil_permissoes pp ON pp.perfil_id = v.perfil_id AND COALESCE(pp.ativo, true)
                 WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true)
                   AND pp.modulo IN ('ponto','colaboradores') AND COALESCE(pp.escopo::text, '') = 'subordinados_diretos')
    AND NOT EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v
                  JOIN public.perfil_permissoes pp ON pp.perfil_id = v.perfil_id AND COALESCE(pp.ativo, true)
                 WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true)
                   AND pp.modulo IN ('ponto','colaboradores')
                   AND COALESCE(pp.escopo::text, '') NOT IN ('proprio_usuario','subordinados_diretos'))
)
SELECT l.cliente, l.nome_completo,
  (l.cpf <> '') AS lider_tem_cpf_cadastrado,
  (SELECT count(DISTINCT regexp_replace(COALESCE(s.cpf, ''), '[^0-9]', '', 'g'))
     FROM public.admissoes s
    WHERE s.tenant_id = l.tenant_id AND l.cpf <> ''
      AND regexp_replace(COALESCE(s.gestor_cpf, ''), '[^0-9]', '', 'g') = l.cpf)            AS equipe_pelo_cpf_do_gestor,
  (SELECT count(DISTINCT regexp_replace(COALESCE(s.cpf, ''), '[^0-9]', '', 'g'))
     FROM public.admissoes s
     JOIN public.departamentos d ON lower(trim(d.nome)) = lower(trim(s.departamento)) AND d.tenant_id = l.tenant_id
     JOIN public.admissoes g ON g.id = d.gestor_admissao_id AND g.tenant_id = l.tenant_id
      AND regexp_replace(COALESCE(g.cpf, ''), '[^0-9]', '', 'g') = l.cpf
    WHERE s.tenant_id = l.tenant_id AND l.cpf <> '')                                        AS equipe_pelo_departamento
FROM lideres l
ORDER BY l.cliente, l.nome_completo;
