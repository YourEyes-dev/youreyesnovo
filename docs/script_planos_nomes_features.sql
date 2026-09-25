-- =====================================================================
-- YOUREYES · SCRIPT DE ENTREGA · NOMES DO CATALOGO (acentos + tags)
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de PRODUCAO.
--
-- O que faz: corrige o TEXTO dos nomes de features (features.name) que
-- aparecem em "Meu Plano" e em "SuperAdmin > Precos e Add-ons":
--   * acentos nos nomes antigos e nos 7 modulos novos;
--   * "(em breve)" em KPIs e Integracoes ERP;
--   * "(sob consulta)" em SSO, IA customizada e API/webhooks.
--
-- Seguro:
--   * Roda em UMA transacao; se der erro, desfaz sozinho.
--   * ALTERA dado existente (features.name) -> guarda copia antes em
--     backup_features_nomes_20260925 (criada por EXECUTE para nao acionar
--     o auto-RLS do editor). Comando de desfazer no rodape.
--   * Idempotente. NAO cria funcao. NAO mexe em plano/entitlement/preco/
--     is_active.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Copia de seguranca (so os nomes atuais)
-- ---------------------------------------------------------------------
do $copia$
begin
  if to_regclass('public.backup_features_nomes_20260925') is null then
    execute 'create ' || 'table public.backup_features_nomes_20260925 as '
         || 'select key, name from public.features';
    raise notice 'copia criada: backup_features_nomes_20260925';
  else
    raise notice 'copia backup_features_nomes_20260925 ja existia — mantida';
  end if;
end $copia$;

-- ---------------------------------------------------------------------
-- 2) Ajuste dos nomes
-- ---------------------------------------------------------------------
update public.features f
   set name = v.nome
  from (values
    ('mod.nr1',            'NR-1 & visão psicossocial'),
    ('mod.ferias',         'Férias + Atestados'),
    ('mod.gro_pgr',        'GRO + Inventário PGR'),
    ('mod.analise_jornada','Análise de Jornada'),
    ('mod.beneficios',     'Benefícios + Documentos + Hub Contábil'),
    ('mod.metas',          'Metas + Plano de Ação (5W2H)'),
    ('mod.trilhas',        'Trilhas + Aprendizado & Competências'),
    ('mod.contratos_exp',  'Contratos de Experiência'),
    ('mod.saude_ocupacional','Saúde Ocupacional (ASO)'),
    ('mod.avaliacoes',     'Avaliações de Desempenho'),
    ('mod.pdi',            'PDI — Desenvolvimento Individual'),
    ('mod.estrategia',     'Estratégia / Identidade + Cultura'),
    ('mod.kpis',           'KPIs operacionais avançados (em breve)'),
    ('mod.integracao',     'Integração ERP (TOTVS/SAP/Sênior/Gupy) — em breve'),
    ('mod.sso',            'SSO + auditoria de acessos (sob consulta)'),
    ('mod.ia_custom',      'IA customizada por setor (sob consulta)'),
    ('mod.api_webhooks',   'API dedicada + webhooks (sob consulta)')
  ) as v(key, nome)
 where f.key = v.key
   and f.name is distinct from v.nome;

-- ---------------------------------------------------------------------
-- CONFERENCIA (o editor mostra so este ultimo resultado)
--   Esperado: os 17 nomes abaixo com acento/tag; 'ok' em todos.
-- ---------------------------------------------------------------------
with alvo(key, nome) as (values
  ('mod.nr1','NR-1 & visão psicossocial'),
  ('mod.ferias','Férias + Atestados'),
  ('mod.gro_pgr','GRO + Inventário PGR'),
  ('mod.analise_jornada','Análise de Jornada'),
  ('mod.beneficios','Benefícios + Documentos + Hub Contábil'),
  ('mod.metas','Metas + Plano de Ação (5W2H)'),
  ('mod.trilhas','Trilhas + Aprendizado & Competências'),
  ('mod.contratos_exp','Contratos de Experiência'),
  ('mod.saude_ocupacional','Saúde Ocupacional (ASO)'),
  ('mod.avaliacoes','Avaliações de Desempenho'),
  ('mod.pdi','PDI — Desenvolvimento Individual'),
  ('mod.estrategia','Estratégia / Identidade + Cultura'),
  ('mod.kpis','KPIs operacionais avançados (em breve)'),
  ('mod.integracao','Integração ERP (TOTVS/SAP/Sênior/Gupy) — em breve'),
  ('mod.sso','SSO + auditoria de acessos (sob consulta)'),
  ('mod.ia_custom','IA customizada por setor (sob consulta)'),
  ('mod.api_webhooks','API dedicada + webhooks (sob consulta)')
)
select a.key,
       f.name as nome_atual,
       case when f.name = a.nome then 'ok' else 'CONFERIR' end as status
from alvo a
left join public.features f on f.key = a.key
order by a.key;

-- ---------------------------------------------------------------------
-- PARA DESFAZER:
--   update public.features f set name = b.name
--     from public.backup_features_nomes_20260925 b where b.key = f.key;
-- ---------------------------------------------------------------------
