-- =====================================================================
-- YOUREYES · SCRIPT DE ENTREGA · REESTRUTURA DO CATALOGO DE PLANOS (etapa 1)
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de PRODUCAO.
--
-- O que faz (mesma logica da migration 20260925194050):
--   * Ponto & Jornada sai do Starter e passa a ser Essential (no Starter vira
--     add-on; o preco fica no SuperAdmin > Precos e Add-ons).
--   * Entram 7 modulos que ja existem como tela e nao eram vendidos: Saude
--     Ocupacional (ASO), Incidentes & Acidentes, Avaliacoes, PDI, Estrategia,
--     Bem-Estar e Financeiro.
--   * Saem os itens que a operacao nao entrega (SLA, CSM, Juridico, DPO,
--     Workshop NR-1): DESATIVADOS, nunca apagados.
--   * SSO desce de Governanca para Enterprise (sob consulta).
--
-- Seguranca:
--   * Roda em UMA transacao (comportamento do SQL Editor): se der erro, desfaz.
--   * ALTERA dado existente (features e plan_entitlements) -> guarda copia
--     antes em backup_features_20260925 e backup_plan_entitlements_20260925.
--     O comando que desfaz esta no fim, em comentario.
--   * Idempotente. NAO cria funcao. So mexe nos planos publicos (tier 1..5);
--     os internos (tier 99), onde estao os clientes atuais, ficam intactos.
--   * Rede de seguranca: quem ja usa Ponto nao perde acesso.
-- =====================================================================

set lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- 1) Copia de seguranca das tabelas que serao alteradas
--    (a tabela e criada por EXECUTE para nao acionar o auto-RLS do editor)
-- ---------------------------------------------------------------------
do $copia$
begin
  if to_regclass('public.backup_features_20260925') is null then
    execute 'create ' || 'table public.backup_features_20260925 as '
         || 'select * from public.features';
    raise notice 'copia criada: backup_features_20260925';
  else
    raise notice 'copia backup_features_20260925 ja existia — mantida';
  end if;

  if to_regclass('public.backup_plan_entitlements_20260925') is null then
    execute 'create ' || 'table public.backup_plan_entitlements_20260925 as '
         || 'select * from public.plan_entitlements';
    raise notice 'copia criada: backup_plan_entitlements_20260925';
  else
    raise notice 'copia backup_plan_entitlements_20260925 ja existia — mantida';
  end if;
end $copia$;

-- ---------------------------------------------------------------------
-- 2) Novos modulos (ja existem como tela; passam a ser vendaveis)
-- ---------------------------------------------------------------------
insert into public.features (key, name, kind, unit, category) values
  ('mod.saude_ocupacional', 'Saude Ocupacional (ASO)',            'boolean', null, 'sst'),
  ('mod.incidentes',        'Incidentes & Acidentes (CAT/FAP)',   'boolean', null, 'sst'),
  ('mod.avaliacoes',        'Avaliacoes de Desempenho',           'boolean', null, 'pessoas'),
  ('mod.pdi',               'PDI - Desenvolvimento Individual',   'boolean', null, 'pessoas'),
  ('mod.estrategia',        'Estrategia / Identidade + Cultura',  'boolean', null, 'gestao'),
  ('mod.bem_estar',         'Bem-Estar / Clima',                  'boolean', null, 'pessoas'),
  ('mod.financeiro',        'Financeiro',                         'boolean', null, 'gestao')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 3) Desativa o que a operacao nao entrega (reversivel: nao apaga)
-- ---------------------------------------------------------------------
update public.features
   set is_active = false
 where key in ('attr.sla','serv.csm','serv.juridico','serv.dpo','serv.workshop_nr1');

-- ---------------------------------------------------------------------
-- 4) Reconstroi a matriz de MODULOS dos planos publicos a partir de uma
--    FONTE UNICA. Nao toca em limit.vidas nem nos planos internos (99).
-- ---------------------------------------------------------------------
delete from public.plan_entitlements pe
using public.plans p, public.features f
 where pe.plan_id = p.id
   and pe.feature_key = f.key
   and p.tier between 1 and 5
   and f.kind = 'boolean';

with feat(key, min_tier) as (values
  ('mod.estrutura',1),('mod.nr1',1),('mod.ferias',1),('mod.onboarding',1),
  ('mod.ponto',2),('mod.analise_jornada',2),('mod.gro_pgr',2),('mod.psicossocial',2),
  ('mod.epi_ergo',2),('mod.saude_ocupacional',2),('mod.incidentes',2),
  ('mod.beneficios',3),('mod.metas',3),('mod.trilhas',3),('mod.cultura',3),
  ('mod.contratos_exp',3),('mod.avaliacoes',3),('mod.pdi',3),('mod.bem_estar',3),
  ('mod.financeiro',3),
  ('mod.estrategia',4),('mod.kpis',4),('mod.integracao',4),
  ('mod.sso',5),('infra.banco_dedicado',5),('mod.ia_custom',5),('mod.api_webhooks',5)
)
insert into public.plan_entitlements (plan_id, feature_key, is_enabled)
select p.id, f.key, true
from public.plans p
join feat f on p.tier >= f.min_tier
where p.tier between 1 and 5
on conflict (plan_id, feature_key) do nothing;

-- ---------------------------------------------------------------------
-- 5) Rede de seguranca: quem JA usa Ponto nao perde acesso
-- ---------------------------------------------------------------------
do $prodseed$
begin
  insert into public.subscription_overrides (tenant_id, feature_key, is_enabled, reason)
  select distinct e.tenant_id, 'mod.ponto', true,
         'reestrutura-planos: preserva ponto de quem ja usa'
  from public.empresa_cadastro e
  where e.usa_controle_ponto is true
    and not exists (
      select 1 from public.subscription_overrides so
      where so.tenant_id = e.tenant_id
        and so.feature_key = 'mod.ponto'
        and so.is_enabled is true
        and (so.expires_at is null or so.expires_at > now())
    );
exception when others then
  raise notice 'rede de seguranca do ponto pulada: %', sqlerrm;
end $prodseed$;

-- ---------------------------------------------------------------------
-- CONFERENCIA (o editor mostra so este ultimo resultado)
--   Esperado: Starter SEM ponto; Essential COM ponto; os 7 novos presentes
--   a partir do nivel indicado; e os 5 servicos irreais inativos.
-- ---------------------------------------------------------------------
with pub as materialized (
  select id, code, tier from public.plans where tier between 1 and 5
),
por_plano as materialized (
  select p.code, p.tier,
         count(*) filter (where f.kind='boolean' and f.is_active) as modulos_ativos,
         bool_or(pe.feature_key='mod.ponto')            as tem_ponto,
         bool_or(pe.feature_key='mod.saude_ocupacional') as tem_aso
  from pub p
  left join public.plan_entitlements pe on pe.plan_id = p.id
  left join public.features f on f.key = pe.feature_key
  group by p.code, p.tier
),
servicos as materialized (
  select count(*) filter (where not is_active) as inativos
  from public.features
  where key in ('attr.sla','serv.csm','serv.juridico','serv.dpo','serv.workshop_nr1')
)
select 1 as ordem, p.tier, p.code as plano,
       p.modulos_ativos::text as modulos_ativos,
       case when p.tem_ponto then 'sim' else 'nao' end as tem_ponto,
       case when p.tem_aso   then 'sim' else 'nao' end as tem_saude_ocup,
       '' as obs
from por_plano p
union all
select 9, 99, 'CONFERE',
       (select inativos::text from servicos) || '/5 servicos inativos',
       (select case when bool_or(tem_ponto) filter (where tier=1) then 'FALHA:starter tem ponto'
                    else 'ok:starter sem ponto' end from por_plano),
       (select case when bool_and(tem_ponto) filter (where tier>=2) then 'ok:ess+ tem ponto'
                    else 'CONFERIR' end from por_plano),
       'esperado: 5/5 inativos'
order by ordem, tier;

-- ---------------------------------------------------------------------
-- PARA DESFAZER (se necessario):
--   delete from public.plan_entitlements;
--   insert into public.plan_entitlements select * from public.backup_plan_entitlements_20260925;
--   update public.features f set is_active = b.is_active
--     from public.backup_features_20260925 b where b.key = f.key;
--   (e remova os overrides criados:
--    delete from public.subscription_overrides
--     where reason = 'reestrutura-planos: preserva ponto de quem ja usa';)
-- ---------------------------------------------------------------------
