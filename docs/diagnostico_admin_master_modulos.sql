-- ============================================================================
-- DIAGNOSTICO (somente leitura) — Administrador Master x modulos do plano
-- Cole no SQL Editor de PRODUCAO. Nao altera nada.
-- Mostra, por cliente, o plano, a situacao da assinatura e QUAIS modulos liberados
-- pelo plano o perfil Administrador Master nao tem (nenhuma permissao ativa).
-- ============================================================================
WITH mapa AS MATERIALIZED (
  SELECT * FROM (VALUES
    ('empresa', NULL), ('filiais', NULL), ('departamentos', NULL), ('cargos', NULL),
    ('colaboradores', NULL), ('terceiros', NULL), ('organograma', NULL),
    ('identidade_estrategica', 'mod.estrategia'), ('planejamento_estrategico', 'mod.estrategia'),
    ('metas', 'mod.metas'), ('plano_acao', 'mod.metas'),
    ('onboarding', 'mod.onboarding'), ('contratos_experiencia', 'mod.contratos_exp'),
    ('cultura_celebracoes', 'mod.cultura'), ('feed', 'mod.cultura'),
    ('feedback', 'mod.cultura'), ('ouvidoria', 'mod.cultura'),
    ('bem_estar', 'mod.bem_estar'),
    ('aprendizado', 'mod.trilhas'), ('trilhas', 'mod.trilhas'),
    ('avaliacoes', 'mod.avaliacoes'), ('pdi', 'mod.pdi'),
    ('mapa_comportamental', 'mod.mapa_comportamental'),
    ('ponto', 'mod.ponto'), ('analise_jornada', 'mod.analise_jornada'),
    ('ferias', 'mod.ferias'), ('atestados', 'mod.ferias'),
    ('beneficios', 'mod.beneficios'), ('documentos', 'mod.beneficios'),
    ('hub_contabil', 'mod.beneficios'),
    ('sst', 'mod.nr1'), ('psicossocial', 'mod.psicossocial'),
    ('ergonomia', 'mod.epi_ergo'), ('epi', 'mod.epi_ergo'),
    ('incidentes', 'mod.incidentes'), ('financeiro', 'mod.financeiro'),
    ('marketplace', NULL), ('academia', NULL),
    ('usuarios', NULL), ('perfis_acesso', NULL), ('configuracoes', NULL),
    ('suporte', NULL), ('auditoria', NULL)
     ) AS m(modulo, feature)
), masters AS MATERIALIZED (
  SELECT pa.id AS perfil_id, pa.tenant_id, t.nome AS cliente
    FROM public.perfis_acesso pa
    JOIN public.tenants t ON t.id = pa.tenant_id
   WHERE pa.nome = 'Administrador Master'
     AND COALESCE(pa.tipo::text, '') <> 'padrao_sistema'
     AND COALESCE(pa.ativo, true) = true
), falta AS MATERIALIZED (
  SELECT ms.perfil_id, ms.tenant_id, ms.cliente, m.modulo
    FROM masters ms
    JOIN public.subscriptions s ON s.tenant_id = ms.tenant_id AND s.status NOT IN ('paused', 'canceled')
   CROSS JOIN mapa m
   WHERE (m.feature IS NULL OR public.tenant_has_feature(ms.tenant_id, m.feature))
     AND NOT EXISTS (SELECT 1 FROM public.perfil_permissoes x
                      WHERE x.perfil_id = ms.perfil_id AND x.modulo = m.modulo
                        AND COALESCE(x.ativo, true) = true)
)
SELECT ms.cliente,
       COALESCE(pl.name, '(sem assinatura)')                       AS plano,
       COALESCE(s.status, '-')                                     AS assinatura,
       (SELECT count(*) FROM falta f WHERE f.perfil_id = ms.perfil_id) AS modulos_faltando,
       (SELECT string_agg(f.modulo, ', ' ORDER BY f.modulo) FROM falta f WHERE f.perfil_id = ms.perfil_id) AS quais
  FROM masters ms
  LEFT JOIN public.subscriptions s ON s.tenant_id = ms.tenant_id
  LEFT JOIN public.plans pl ON pl.id = s.plan_id
 ORDER BY modulos_faltando DESC, ms.cliente;
