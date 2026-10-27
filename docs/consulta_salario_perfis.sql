-- SOMENTE LEITURA — quais perfis de acesso ainda veem SALARIO (pode_ver_salario ligado) e quantas pessoas usam cada um.
-- Serve para decidir, junto com cada cliente, quais perfis devem ter o salario desligado. Os perfis "Colaborador (padrao)" ja
-- sao desligados pelo script_salario_padrao_fechado.sql; aqui aparecem os criados pelos clientes (e os demais modelos).
-- Coluna "so_autosservico": o perfil so da acesso aos PROPRIOS dados (nenhuma permissao em escopo amplo ou de subordinados)
-- — nesse caso ver salario nao faz sentido e o perfil e candidato a desligar. Nao lista nome de pessoa nem CPF.
SELECT t.nome AS cliente, pa.nome AS perfil, pa.tipo::text AS tipo_do_perfil,
       (SELECT count(*) FROM public.usuario_perfil_vinculos v
          WHERE v.perfil_id = pa.id AND COALESCE(v.ativo, true)) AS pessoas_vinculadas,
       NOT EXISTS (SELECT 1 FROM public.perfil_permissoes pp
                    WHERE pp.perfil_id = pa.id AND COALESCE(pp.ativo, true)
                      AND COALESCE(pp.escopo::text, '') NOT IN ('proprio_usuario')) AS so_autosservico
FROM public.perfis_acesso pa JOIN public.tenants t ON t.id = pa.tenant_id
WHERE COALESCE(pa.ativo, true) AND pa.pode_ver_salario
ORDER BY so_autosservico DESC, t.nome, pa.nome;
