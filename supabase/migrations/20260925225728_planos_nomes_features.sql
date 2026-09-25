-- =====================================================================
-- Nomes do catálogo de planos — acentos + tags de status
--
-- As telas "Meu Plano" e "SuperAdmin > Preços e Add-ons" mostram o NOME de
-- cada feature (features.name) direto do catálogo. Os nomes foram semeados
-- sem acento (o SQL Editor de produção não aceita bem acentos em alguns
-- fluxos), e alguns módulos precisam sinalizar status.
--
-- Este arquivo só corrige TEXTO (features.name):
--   * acentos nos nomes antigos e nos 7 módulos novos;
--   * "(em breve)" em KPIs e Integrações ERP (sem tela ainda);
--   * "(sob consulta)" em SSO, IA customizada e API/webhooks (Enterprise,
--     sem tela / sob medida).
--
-- Aditivo, idempotente e reversível (só muda name). NÃO mexe em plano,
-- entitlement, preço ou is_active.
-- =====================================================================

update public.features f
   set name = v.nome
  from (values
    -- acentos (nomes antigos)
    ('mod.nr1',            'NR-1 & visão psicossocial'),
    ('mod.ferias',         'Férias + Atestados'),
    ('mod.gro_pgr',        'GRO + Inventário PGR'),
    ('mod.analise_jornada','Análise de Jornada'),
    ('mod.beneficios',     'Benefícios + Documentos + Hub Contábil'),
    ('mod.metas',          'Metas + Plano de Ação (5W2H)'),
    ('mod.trilhas',        'Trilhas + Aprendizado & Competências'),
    ('mod.contratos_exp',  'Contratos de Experiência'),
    -- acentos (módulos novos)
    ('mod.saude_ocupacional','Saúde Ocupacional (ASO)'),
    ('mod.avaliacoes',     'Avaliações de Desempenho'),
    ('mod.pdi',            'PDI — Desenvolvimento Individual'),
    ('mod.estrategia',     'Estratégia / Identidade + Cultura'),
    -- tags de status
    ('mod.kpis',           'KPIs operacionais avançados (em breve)'),
    ('mod.integracao',     'Integração ERP (TOTVS/SAP/Sênior/Gupy) — em breve'),
    ('mod.sso',            'SSO + auditoria de acessos (sob consulta)'),
    ('mod.ia_custom',      'IA customizada por setor (sob consulta)'),
    ('mod.api_webhooks',   'API dedicada + webhooks (sob consulta)')
  ) as v(key, nome)
 where f.key = v.key
   and f.name is distinct from v.nome;
