-- =====================================================================
-- YOUREYES · CONFERENCIA (SOMENTE LEITURA) · MOTOR DE ENTITLEMENTS
-- Cole no SQL Editor do projeto de TESTE (o "DEV" onde o motor foi
-- aplicado a mao). NAO altera nada - so le e reporta.
--
-- Serve para reconciliar o que ja esta no banco com a migration/versao
-- do repositorio ANTES de promover. Confira: (1) o resultado final da
-- tabela abaixo (todas as linhas OK) e (2) a aba "Messages"/NOTICE do
-- editor, onde sai o smoke test das funcoes.
-- =====================================================================

-- ---------------------------------------------------------------------
-- SMOKE TEST das funcoes de resolucao.
--   Se a funcao entitlement_resolve ainda for a versao ORIGINAL (com o
--   bug de ambiguidade em limit_value), a chamada abaixo dispara erro e
--   o NOTICE avisa. A migration/script de entrega ja corrige isso.
-- ---------------------------------------------------------------------
do $conf$
declare v boolean; v_tenant uuid;
begin
  select tenant_id into v_tenant from public.subscriptions limit 1;
  if v_tenant is null then
    raise notice 'SMOKE: nao ha assinaturas ainda (bloco 09 nao rodou?).';
    return;
  end if;
  begin
    select public.tenant_has_feature(v_tenant, 'mod.ponto') into v;
    raise notice 'SMOKE OK: tenant_has_feature respondeu = % (funcoes saudaveis).', v;
  exception when others then
    raise notice 'SMOKE FALHOU: %  -> o DEV ainda tem a versao com bug; aplicar a versao corrigida.', sqlerrm;
  end;
end $conf$;

-- ---------------------------------------------------------------------
-- CHECKLIST (resultado unico exibido pelo editor)
-- ---------------------------------------------------------------------
with existentes as (
  select count(*) as n from information_schema.tables
  where table_schema='public' and table_name in
    ('plans','plan_prices','features','plan_entitlements','subscriptions',
     'subscription_overrides','usage_counters','entitlement_audit_log',
     'entitlement_denials_log','entitlement_gated_tables')
),
chk(ordem, item, esperado, obtido) as (
  select 1, 'tabelas do motor presentes', '10', (select n::text from existentes)
  union all
  select 2, 'planos', '7', (select count(*)::text from public.plans)
  union all
  select 3, 'features', '26', (select count(*)::text from public.features)
  union all
  select 4, 'precos_monthly', '5',
         (select count(*)::text from public.plan_prices where period='monthly')
  union all
  select 5, 'matriz starter/essential/performance/governanca/enterprise',
         '6/10/15/20/26',
         (select string_agg(fl::text, '/' order by tier)
          from (
            select min(p.tier) tier, count(*) filter (where pe.is_enabled) fl
            from public.plans p left join public.plan_entitlements pe on pe.plan_id=p.id
            where p.code in ('starter','essential','performance','governanca','enterprise')
            group by p.code
          ) z)
  union all
  select 6, 'internos tester/early_adopter (26 cada)', '26/26',
         (select string_agg(fl::text,'/' order by code)
          from (
            select p.code, count(*) filter (where pe.is_enabled) fl
            from public.plans p left join public.plan_entitlements pe on pe.plan_id=p.id
            where p.code in ('early_adopter','tester')
            group by p.code
          ) z)
  union all
  select 7, 'tenants x assinaturas (devem casar)',
         (select count(*)::text from public.tenants),
         (select count(*)::text from public.subscriptions)
  union all
  select 8, 'tenants sem assinatura (deve ser 0)', '0',
         (select count(*)::text from public.tenants t
          where not exists (select 1 from public.subscriptions s where s.tenant_id=t.id))
  union all
  select 9, 'policies de enforcement ligadas (0 = fail-open, nada bloqueado)', '0',
         (select count(*)::text from public.entitlement_gated_tables)
)
select item, esperado, obtido,
       case when esperado = obtido then 'OK' else 'CONFERIR' end as status
from chk order by ordem;
