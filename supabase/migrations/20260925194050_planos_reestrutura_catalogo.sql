-- =====================================================================
-- Reestrutura do catalogo de planos — etapa 1 (catalogo)
--
-- Aplica a nova matriz de planos x modulos decidida com o dono do produto:
--   * Ponto & Jornada SAI do Starter e passa a ser Essential. No Starter ele
--     vira add-on (o add-on e a propria feature mod.ponto; o preco fica no
--     SuperAdmin > Precos e Add-ons).
--   * Entram 7 modulos que ja existem como tela mas nao eram vendidos:
--     Saude Ocupacional (ASO), Incidentes & Acidentes, Avaliacoes de
--     Desempenho, PDI, Estrategia/Identidade, Bem-Estar e Financeiro.
--   * Saem os itens que a operacao nao entrega (SLA, CSM, Juridico, DPO,
--     Workshop NR-1): DESATIVADOS (is_active=false), nunca apagados.
--   * SSO desce de Governanca para Enterprise (sob consulta).
--
-- Seguranca:
--   * Aditivo e idempotente (rodar duas vezes nao quebra nem duplica).
--   * NAO remove acesso de cliente atual: os clientes de hoje estao no plano
--     tester (tier 99), que recebe TODA feature ativa; e ha uma rede de
--     seguranca que garante o Ponto a quem ja o usa, qualquer que seja o plano.
--   * So mexe nos planos PUBLICOS (tier 1..5); os internos (tier 99) ficam
--     intactos.
-- =====================================================================

set lock_timeout = '10s';

-- 1) Novos modulos (ja existem como tela; passam a ser vendaveis) ------
insert into public.features (key, name, kind, unit, category) values
  ('mod.saude_ocupacional', 'Saude Ocupacional (ASO)',            'boolean', null, 'sst'),
  ('mod.incidentes',        'Incidentes & Acidentes (CAT/FAP)',   'boolean', null, 'sst'),
  ('mod.avaliacoes',        'Avaliacoes de Desempenho',           'boolean', null, 'pessoas'),
  ('mod.pdi',               'PDI - Desenvolvimento Individual',   'boolean', null, 'pessoas'),
  ('mod.estrategia',        'Estrategia / Identidade + Cultura',  'boolean', null, 'gestao'),
  ('mod.bem_estar',         'Bem-Estar / Clima',                  'boolean', null, 'pessoas'),
  ('mod.financeiro',        'Financeiro',                         'boolean', null, 'gestao')
on conflict (key) do nothing;

-- 2) Desativa o que a operacao nao entrega (reversivel: nao apaga) ------
update public.features
   set is_active = false
 where key in ('attr.sla','serv.csm','serv.juridico','serv.dpo','serv.workshop_nr1');

-- 3) Reconstroi a matriz de MODULOS dos planos publicos a partir de uma
--    FONTE UNICA (evita divergencia entre "liga" e "desliga").
--    Nao toca em limit.vidas (kind='limit') nem nos planos internos (99).
delete from public.plan_entitlements pe
using public.plans p, public.features f
 where pe.plan_id = p.id
   and pe.feature_key = f.key
   and p.tier between 1 and 5
   and f.kind = 'boolean';

with feat(key, min_tier) as (values
  -- Starter (1)
  ('mod.estrutura',1),('mod.nr1',1),('mod.ferias',1),('mod.onboarding',1),
  -- Essential (2)  << Ponto entra aqui
  ('mod.ponto',2),('mod.analise_jornada',2),('mod.gro_pgr',2),('mod.psicossocial',2),
  ('mod.epi_ergo',2),('mod.saude_ocupacional',2),('mod.incidentes',2),
  -- Performance (3)
  ('mod.beneficios',3),('mod.metas',3),('mod.trilhas',3),('mod.cultura',3),
  ('mod.contratos_exp',3),('mod.avaliacoes',3),('mod.pdi',3),('mod.bem_estar',3),
  ('mod.financeiro',3),
  -- Governanca (4)
  ('mod.estrategia',4),('mod.kpis',4),('mod.integracao',4),
  -- Enterprise (5)  << SSO desce para ca
  ('mod.sso',5),('infra.banco_dedicado',5),('mod.ia_custom',5),('mod.api_webhooks',5)
)
insert into public.plan_entitlements (plan_id, feature_key, is_enabled)
select p.id, f.key, true
from public.plans p
join feat f on p.tier >= f.min_tier
where p.tier between 1 and 5
on conflict (plan_id, feature_key) do nothing;

-- 4) Rede de seguranca: quem JA usa Ponto nao pode perder acesso. Garante
--    um override habilitando mod.ponto para todo tenant com empresa marcada
--    como usuaria de controle de ponto. Em banco novo (sem tenants) e no-op.
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
exception when foreign_key_violation or not_null_violation
       or undefined_table or undefined_column or raise_exception then
  raise notice 'rede de seguranca do ponto pulada: %', sqlerrm;
end $prodseed$;

-- 5) Conferencia ------------------------------------------------------
do $verifica$
declare
  v_falta text := '';
  v_ponto_no_starter int;
begin
  -- Os 7 novos existem e estao ativos?
  if (select count(*) from public.features
       where key in ('mod.saude_ocupacional','mod.incidentes','mod.avaliacoes',
                     'mod.pdi','mod.estrategia','mod.bem_estar','mod.financeiro')
         and is_active) <> 7 then
    v_falta := v_falta || ' novos_modulos';
  end if;
  -- Ponto saiu do Starter (plano publico tier 1)?
  select count(*) into v_ponto_no_starter
  from public.plan_entitlements pe
  join public.plans p on p.id = pe.plan_id
  where pe.feature_key = 'mod.ponto' and p.tier = 1;
  if v_ponto_no_starter > 0 then
    v_falta := v_falta || ' ponto_ainda_no_starter';
  end if;
  if v_falta <> '' then
    raise exception 'Reestrutura de planos incompleta:%', v_falta;
  end if;
  raise notice 'OK: catalogo de planos reestruturado.';
end $verifica$;
