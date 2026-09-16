-- =====================================================================
-- YOUREYES · MOTOR DE ENTITLEMENTS (planos -> entitlements -> modulos ->
--            limites -> permissoes) · versionamento do motor "como esta"
--
-- Origem: instalado a mao no banco de DEV (3 SQLs do handoff). Aqui ele
-- vira migration IDEMPOTENTE, para:
--   (a) atravessar um banco vazio sem erro (garantia da casa);
--   (b) reconciliar com o DEV/STAGING onde ja foi aplicado a mao
--       (create ... if not exists / on conflict / drop policy if exists),
--       sem duplicar seed nem quebrar o que existe.
--
-- Contem: catalogo (plans/features/precos/matriz) + contrato por tenant
-- (subscriptions/overrides) + consumo/auditoria + funcoes de resolucao +
-- RLS do catalogo + seed dos 7 planos e 26 features + FK e atribuicao de
-- assinatura 'tester' a todos os tenants + infraestrutura do gerador de
-- enforcement (SEM aplicar nenhuma policy de bloqueio ainda: P3 e fail-open).
--
-- NAO mexe no enum public.tenant_plan nem em tenants.plano (decisao de
-- produto - P1 - fica para depois).
--
-- Dependencias ja existentes no repo (conferidas):
--   public.tenants(id uuid pk) · public.profiles.tenant_id ·
--   public.current_user_tenant_id() (le profiles.tenant_id) ·
--   gen_random_uuid() nativo (extensoes base ja garantidas em migration propria)
-- =====================================================================


-- =====================================================================
-- 02 · CATALOGO (global - definido pela plataforma)
-- =====================================================================

create table if not exists public.plans (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique,          -- 'starter','essential',...
  name        text not null,
  description text,
  tier        int  not null default 0,       -- ordenacao: 1..5 ; internos = 99
  is_public   boolean not null default true, -- aparece na pagina de planos
  status      text not null default 'active' check (status in ('active','inactive')),
  created_at  timestamptz not null default now()
);
comment on table public.plans is 'Catalogo de planos. code e a chave estavel usada em todo o sistema.';

create table if not exists public.plan_prices (
  id          uuid primary key default gen_random_uuid(),
  plan_id     uuid not null references public.plans(id) on delete cascade,
  currency    text not null default 'BRL',
  amount_cents integer,                       -- null = "sob consulta"
  period      text not null default 'monthly'
              check (period in ('monthly','semiannual','yearly','custom')),
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

create table if not exists public.features (
  id          uuid primary key default gen_random_uuid(),
  key         text not null unique,           -- 'mod.ponto','limit.vidas',...
  name        text not null,
  description text,
  kind        text not null
              check (kind in ('boolean','limit','metered')),
  unit        text,                           -- 'vidas','consultas','gb'...
  category    text,                           -- agrupamento p/ UX
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

create table if not exists public.plan_entitlements (
  id           uuid primary key default gen_random_uuid(),
  plan_id      uuid not null references public.plans(id) on delete cascade,
  feature_key  text not null references public.features(key) on delete cascade,
  is_enabled   boolean not null default true, -- p/ features boolean
  limit_value  bigint,                        -- p/ limit/metered (null = sem valor)
  is_unlimited boolean not null default false,
  unique (plan_id, feature_key)
);


-- =====================================================================
-- 03 · CONTRATO (por tenant)
-- =====================================================================

create table if not exists public.subscriptions (
  id                   uuid primary key default gen_random_uuid(),
  tenant_id            uuid not null unique,
  plan_id              uuid not null references public.plans(id),
  status               text not null default 'trialing'
                       check (status in ('trialing','active','past_due','paused','canceled')),
  trial_ends_at        timestamptz,
  current_period_start timestamptz not null default date_trunc('month', now()),
  current_period_end   timestamptz not null default (date_trunc('month', now()) + interval '1 month'),
  payment_confirmed    boolean not null default false, -- toggle manual (sem gateway ainda)
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);
comment on column public.subscriptions.status is
  'trialing/active/past_due = com direito; paused/canceled = sem direito.';

create table if not exists public.subscription_overrides (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null,
  feature_key  text not null references public.features(key) on delete cascade,
  is_enabled   boolean,        -- null = nao mexe nesta dimensao
  limit_value  bigint,         -- null = nao mexe
  is_unlimited boolean,        -- null = nao mexe
  reason       text,
  expires_at   timestamptz,    -- null = permanente
  created_by   uuid,
  created_at   timestamptz not null default now()
);
create index if not exists idx_overrides_lookup
  on public.subscription_overrides (tenant_id, feature_key);


-- =====================================================================
-- 04 · CONSUMO / AUDITORIA
-- =====================================================================

create table if not exists public.usage_counters (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null,
  feature_key  text not null references public.features(key) on delete cascade,
  period_start date not null default date_trunc('month', now())::date,
  used_value   bigint not null default 0,
  updated_at   timestamptz not null default now(),
  unique (tenant_id, feature_key, period_start)
);

create table if not exists public.entitlement_audit_log (
  id          uuid primary key default gen_random_uuid(),
  actor       uuid,
  action      text not null,          -- 'plan.update','override.create',...
  entity      text,                   -- 'plan_entitlements','subscription',...
  entity_id   uuid,
  tenant_id   uuid,
  before      jsonb,
  after       jsonb,
  created_at  timestamptz not null default now()
);

create table if not exists public.entitlement_denials_log (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null,
  feature_key text not null,
  reason      text,
  context     text,                   -- rota/acao onde ocorreria o bloqueio
  created_at  timestamptz not null default now()
);


-- =====================================================================
-- 05 · INDICES + updated_at
-- =====================================================================
create index if not exists idx_plan_ent_plan   on public.plan_entitlements (plan_id);
create index if not exists idx_plan_ent_feature on public.plan_entitlements (feature_key);
create index if not exists idx_usage_lookup     on public.usage_counters (tenant_id, feature_key, period_start);
create index if not exists idx_denials_tenant   on public.entitlement_denials_log (tenant_id, feature_key);

-- Funcao de updated_at propria do motor (o repo usa handle_updated_at() em
-- outras tabelas; mantemos set_updated_at() para bater com o DEV do motor).
create or replace function public.set_updated_at()
returns trigger language plpgsql as $set_updated_at$
begin new.updated_at = now(); return new; end $set_updated_at$;

drop trigger if exists trg_subscriptions_updated on public.subscriptions;
create trigger trg_subscriptions_updated
  before update on public.subscriptions
  for each row execute function public.set_updated_at();


-- =====================================================================
-- 06 · FUNCOES DE RESOLUCAO (fonte unica da verdade)
-- =====================================================================

create or replace function public.entitlement_resolve(p_tenant uuid, p_feature text)
returns table(available boolean, limit_value bigint, is_unlimited boolean, source text)
language plpgsql stable security definer set search_path = public as $entitlement_resolve$
declare
  v_plan   uuid;
  v_status text;
  v_base   record;
  v_ov     record;
  v_avail  boolean := false;
  v_limit  bigint  := null;
  v_unl    boolean := false;
  v_src    text    := 'no_subscription';
begin
  select plan_id, status into v_plan, v_status
  from subscriptions where tenant_id = p_tenant;

  if v_plan is null then
    return query select false, null::bigint, false, 'no_subscription';
    return;
  end if;

  -- base do plano
  -- (colunas qualificadas por alias: os nomes limit_value/is_unlimited tambem
  --  sao colunas de saida da funcao - sem o alias, o Postgres acusa ambiguidade
  --  e a funcao quebra em EXECUCAO. Corrigido aqui em relacao ao SQL original.)
  select pe.is_enabled, pe.limit_value, pe.is_unlimited into v_base
  from plan_entitlements pe
  where pe.plan_id = v_plan and pe.feature_key = p_feature;

  if found then
    v_avail := coalesce(v_base.is_enabled, false);
    v_limit := v_base.limit_value;
    v_unl   := coalesce(v_base.is_unlimited, false);
    v_src   := 'plan';
  end if;

  -- override do tenant (vence o plano), respeitando expiracao
  select so.is_enabled, so.limit_value, so.is_unlimited into v_ov
  from subscription_overrides so
  where so.tenant_id = p_tenant and so.feature_key = p_feature
    and (so.expires_at is null or so.expires_at > now())
  order by so.created_at desc
  limit 1;

  if found then
    if v_ov.is_enabled   is not null then v_avail := v_ov.is_enabled;   end if;
    if v_ov.limit_value  is not null then v_limit := v_ov.limit_value;  end if;
    if v_ov.is_unlimited is not null then v_unl   := v_ov.is_unlimited; end if;
    v_src := 'override';
  end if;

  -- status da assinatura remove o direito quando pausada/cancelada
  if v_status in ('paused','canceled') then
    v_avail := false;
    v_src   := 'subscription_' || v_status;
  end if;

  return query select v_avail, v_limit, v_unl, v_src;
end $entitlement_resolve$;

create or replace function public.tenant_has_feature(p_tenant uuid, p_feature text)
returns boolean language sql stable security definer set search_path = public as $tenant_has_feature$
  select coalesce((select available from entitlement_resolve(p_tenant, p_feature)), false);
$tenant_has_feature$;

create or replace function public.entitlement_can_use(
  p_tenant uuid, p_feature text, p_current_usage bigint default null)
returns table(allowed boolean, reason text, limit_value bigint, used bigint, remaining bigint)
language plpgsql stable security definer set search_path = public as $entitlement_can_use$
declare r record; v_used bigint;
begin
  select * into r from entitlement_resolve(p_tenant, p_feature);

  if not r.available then
    return query select false, r.source, r.limit_value, null::bigint, null::bigint;
    return;
  end if;

  v_used := coalesce(
    p_current_usage,
    (select used_value from usage_counters
      where tenant_id = p_tenant and feature_key = p_feature
        and period_start = date_trunc('month', now())::date),
    0);

  if r.is_unlimited or r.limit_value is null then
    return query select true, 'allowed', r.limit_value, v_used, null::bigint;
    return;
  end if;

  if v_used >= r.limit_value then
    return query select false, 'limit_reached', r.limit_value, v_used, 0::bigint;
    return;
  end if;

  return query select true, 'allowed', r.limit_value, v_used, (r.limit_value - v_used);
end $entitlement_can_use$;

create or replace function public.log_entitlement_denial(
  p_tenant uuid, p_feature text, p_context text default null)
returns void language plpgsql security definer set search_path = public as $log_entitlement_denial$
declare r record;
begin
  select * into r from entitlement_can_use(p_tenant, p_feature);
  if not r.allowed then
    insert into entitlement_denials_log(tenant_id, feature_key, reason, context)
    values (p_tenant, p_feature, r.reason, p_context);
  end if;
end $log_entitlement_denial$;


-- =====================================================================
-- 07 · RLS (seguranca - a verdade mora no banco)
-- =====================================================================
alter table public.plans                   enable row level security;
alter table public.plan_prices             enable row level security;
alter table public.features                enable row level security;
alter table public.plan_entitlements       enable row level security;
alter table public.subscriptions           enable row level security;
alter table public.subscription_overrides  enable row level security;
alter table public.usage_counters          enable row level security;
alter table public.entitlement_audit_log   enable row level security;
alter table public.entitlement_denials_log enable row level security;

-- Catalogo e publico (a pagina de planos precisa ler). So leitura.
drop policy if exists p_plans_read on public.plans;
create policy p_plans_read on public.plans for select to anon, authenticated using (true);

drop policy if exists p_prices_read on public.plan_prices;
create policy p_prices_read on public.plan_prices for select to anon, authenticated using (true);

drop policy if exists p_features_read on public.features;
create policy p_features_read on public.features for select to anon, authenticated using (true);

drop policy if exists p_plan_ent_read on public.plan_entitlements;
create policy p_plan_ent_read on public.plan_entitlements for select to anon, authenticated using (true);

-- Tabelas de contrato/consumo: SEM policy permissiva = ninguem acessa direto.
-- O acesso do cliente acontece pelas funcoes SECURITY DEFINER (RPC) acima, e a
-- escrita acontece pelo backend (service_role, que ignora RLS).
-- (Leitura da propria assinatura pela API fica para o dashboard de consumo - P5.)

-- Permite chamar as funcoes via RPC.
grant execute on function public.entitlement_resolve(uuid,text)        to anon, authenticated;
grant execute on function public.tenant_has_feature(uuid,text)         to anon, authenticated;
grant execute on function public.entitlement_can_use(uuid,text,bigint) to anon, authenticated;
grant execute on function public.log_entitlement_denial(uuid,text,text) to authenticated;


-- =====================================================================
-- 08 · SEED - os 7 planos + a matriz (idempotente)
-- =====================================================================

-- 8.1 Planos (5 comerciais + 2 internos)
insert into public.plans (code, name, description, tier, is_public) values
  ('starter',      'Starter',      'Para quem esta comecando a organizar a operacao.',        1, true),
  ('essential',    'Essential',    'Para quem ja tem processo e precisa colocar no ar.',       2, true),
  ('performance',  'Performance',  'Para quem ja tem processo e precisa medir.',               3, true),
  ('governanca',   'Governanca',   'Para quem opera em multiplas unidades e precisa integrar.',4, true),
  ('enterprise',   'Enterprise',   'Para grandes operacoes com exigencia maxima de seguranca.',5, true),
  ('early_adopter','Early Adopter','Plano interno gratuito (acesso total).',                  99, false),
  ('tester',       'Tester',       'Plano interno de teste (acesso total).',                  99, false)
on conflict (code) do nothing;

-- 8.2 Precos (mensal; enterprise = sob consulta)
insert into public.plan_prices (plan_id, amount_cents, period)
select p.id, v.cents, 'monthly'
from (values
  ('starter',      19700),
  ('essential',    39700),
  ('performance',  79700),
  ('governanca',  179700),
  ('enterprise',    null::int)
) as v(code, cents)
join public.plans p on p.code = v.code
where not exists (
  select 1 from public.plan_prices pp
  where pp.plan_id = p.id and pp.period = 'monthly'
);

-- 8.3 Features (modulos, servicos, limite)
insert into public.features (key, name, kind, unit, category) values
  ('mod.estrutura',        'Estrutura organizacional',                 'boolean', null, 'base'),
  ('mod.nr1',              'NR-1 & visao psicossocial',                'boolean', null, 'sst'),
  ('mod.ponto',            'Ponto & Jornada',                          'boolean', null, 'jornada'),
  ('mod.ferias',           'Ferias + Atestados',                       'boolean', null, 'jornada'),
  ('mod.onboarding',       'Onboarding',                               'boolean', null, 'pessoas'),
  ('mod.gro_pgr',          'GRO + Inventario PGR',                     'boolean', null, 'sst'),
  ('mod.psicossocial',     'Campanhas psicossociais + resultados',     'boolean', null, 'sst'),
  ('mod.epi_ergo',         'EPIs + Ergonomia',                         'boolean', null, 'sst'),
  ('mod.analise_jornada',  'Analise de Jornada',                       'boolean', null, 'jornada'),
  ('mod.beneficios',       'Beneficios + Documentos + Hub Contabil',   'boolean', null, 'gestao'),
  ('mod.metas',            'Metas + Plano de Acao (5W2H)',             'boolean', null, 'gestao'),
  ('mod.trilhas',          'Trilhas + Aprendizado & Competencias',     'boolean', null, 'pessoas'),
  ('mod.cultura',          'Feedback, Ouvidoria & Cultura',            'boolean', null, 'pessoas'),
  ('mod.contratos_exp',    'Contratos de Experiencia',                 'boolean', null, 'pessoas'),
  ('mod.sso',              'SSO + auditoria de acessos',               'boolean', null, 'integracao'),
  ('mod.kpis',             'KPIs operacionais avancados',              'boolean', null, 'gestao'),
  ('mod.integracao',       'Integracao ERP (TOTVS/SAP/Senior/Gupy)',   'boolean', null, 'integracao'),
  ('attr.sla',             'SLA 99,5% garantido',                      'boolean', null, 'servico'),
  ('serv.csm',             'CSM dedicado',                             'boolean', null, 'servico'),
  ('infra.banco_dedicado', 'Banco de dados dedicado',                  'boolean', null, 'infra'),
  ('mod.ia_custom',        'IA customizada por setor',                 'boolean', null, 'ia'),
  ('mod.api_webhooks',     'API dedicada + webhooks',                  'boolean', null, 'integracao'),
  ('serv.juridico',        'Assessoria juridico-trabalhista',          'boolean', null, 'servico'),
  ('serv.dpo',             'DPO + LGPD avancado',                      'boolean', null, 'servico'),
  ('serv.workshop_nr1',    'Workshop mensal NR-1',                     'boolean', null, 'servico'),
  ('limit.vidas',          'Colaboradores / vidas ativas',            'limit',   'vidas', 'limite')
on conflict (key) do nothing;

-- 8.4 Matriz: liga cada feature boolean para todo plano com tier >= min_tier.
--     Planos internos (tier 99) recebem TUDO automaticamente.
with feat(key, min_tier) as (values
  ('mod.estrutura',1),('mod.nr1',1),('mod.ponto',1),('mod.ferias',1),('mod.onboarding',1),
  ('mod.gro_pgr',2),('mod.psicossocial',2),('mod.epi_ergo',2),('mod.analise_jornada',2),
  ('mod.beneficios',3),('mod.metas',3),('mod.trilhas',3),('mod.cultura',3),('mod.contratos_exp',3),
  ('mod.sso',4),('mod.kpis',4),('mod.integracao',4),('attr.sla',4),('serv.csm',4),
  ('infra.banco_dedicado',5),('mod.ia_custom',5),('mod.api_webhooks',5),
  ('serv.juridico',5),('serv.dpo',5),('serv.workshop_nr1',5)
)
insert into public.plan_entitlements (plan_id, feature_key, is_enabled)
select p.id, f.key, true
from public.plans p
join feat f on p.tier >= f.min_tier
on conflict (plan_id, feature_key) do nothing;

-- 8.5 Limite de vidas por plano
insert into public.plan_entitlements (plan_id, feature_key, limit_value, is_unlimited)
select p.id, 'limit.vidas',
  case p.code
    when 'starter'     then 20
    when 'essential'   then 80
    when 'performance' then 200
    when 'governanca'  then 500
    else null
  end,
  (p.code in ('enterprise','early_adopter','tester'))   -- ilimitado
from public.plans p
on conflict (plan_id, feature_key)
do update set limit_value = excluded.limit_value,
              is_unlimited = excluded.is_unlimited;


-- =====================================================================
-- 09 · INTEGRIDADE + ATRIBUICAO DE ASSINATURA (bloco09)
-- =====================================================================

-- 09.1 FK subscriptions -> tenants (PK confirmado: public.tenants.id)
alter table public.subscriptions
  drop constraint if exists fk_subscriptions_tenant;
alter table public.subscriptions
  add constraint fk_subscriptions_tenant
  foreign key (tenant_id) references public.tenants(id) on delete cascade;

-- 09.2 Sem clientes pagantes: todos os tenants recebem o plano 'tester'
--      (acesso total), entao nada quebra. Idempotente (where not exists).
insert into public.subscriptions
  (tenant_id, plan_id, status, trial_ends_at, current_period_start, current_period_end)
select t.id,
       (select id from public.plans where code = 'tester'),
       'trialing',
       now() + interval '30 days',
       date_trunc('month', now()),
       date_trunc('month', now()) + interval '1 month'
from public.tenants t
where not exists (
  select 1 from public.subscriptions s where s.tenant_id = t.id
);


-- =====================================================================
-- 10 · INFRAESTRUTURA DO GERADOR DE ENFORCEMENT (Bloco A do gerador)
--   Cria a config feature->tabela e as funcoes que geram/aplicam as
--   policies RESTRICTIVE. NAO aplica NENHUMA policy de bloqueio aqui:
--   o mapa (entitlement_gated_tables) nasce vazio e o enforcement so e
--   ligado depois, modulo a modulo, em modo fail-open (P3).
-- =====================================================================

create table if not exists public.entitlement_gated_tables (
  feature_key text not null references public.features(key) on delete cascade,
  table_name  text not null,
  mode        text not null default 'full'
              check (mode in ('full','write_only')),
  -- full       = sem a feature, o tenant nao faz NADA na tabela (nem le)
  -- write_only = sem a feature, ainda LE (historico), mas nao cria/edita/apaga
  primary key (feature_key, table_name)
);

create or replace function public.entitlement_build_statements()
returns table(table_name text, stmt text)
language plpgsql stable as $entitlement_build_statements$
declare
  r record; v_pol text; v_rls boolean; v_perm int;
begin
  for r in
    select g.feature_key, g.table_name, g.mode
    from public.entitlement_gated_tables g
    order by g.table_name, g.feature_key
  loop
    -- tabela existe?
    if not exists (select 1 from information_schema.tables
                   where table_schema='public' and table_name = r.table_name) then
      table_name := r.table_name;
      stmt := format('-- IGNORADO (%s): tabela public.%s nao existe', r.feature_key, r.table_name);
      return next; continue;
    end if;

    -- RLS ligada + tem policy permissiva (isolamento)?
    select c.relrowsecurity into v_rls
    from pg_class c where c.oid = ('public.'||r.table_name)::regclass;

    select count(*) into v_perm
    from pg_policies
    where schemaname='public' and tablename=r.table_name and permissive='PERMISSIVE';

    if not coalesce(v_rls,false) or v_perm = 0 then
      table_name := r.table_name;
      stmt := format('-- ATENCAO (%s): public.%s esta com RLS desligada ou SEM policy permissiva de isolamento por tenant. NAO gerei restrictive (bloquearia tudo). Garanta o isolamento por tenant primeiro.', r.feature_key, r.table_name);
      return next; continue;
    end if;

    if r.mode = 'full' then
      v_pol := 'ent_' || r.table_name;
      table_name := r.table_name;
      stmt := format('drop policy if exists %I on public.%I;', v_pol, r.table_name);
      return next;
      table_name := r.table_name;
      stmt := format(
        'create policy %I on public.%I as restrictive for all to authenticated '
        || 'using (public.tenant_has_feature(public.current_user_tenant_id(), %L)) '
        || 'with check (public.tenant_has_feature(public.current_user_tenant_id(), %L));',
        v_pol, r.table_name, r.feature_key, r.feature_key);
      return next;
    else  -- write_only: leitura livre (isolamento que ja existe), escrita gateada
      v_pol := 'ent_ins_' || r.table_name;
      table_name := r.table_name;
      stmt := format('drop policy if exists %I on public.%I;', v_pol, r.table_name); return next;
      table_name := r.table_name;
      stmt := format('create policy %I on public.%I as restrictive for insert to authenticated with check (public.tenant_has_feature(public.current_user_tenant_id(), %L));', v_pol, r.table_name, r.feature_key); return next;
      v_pol := 'ent_upd_' || r.table_name;
      table_name := r.table_name;
      stmt := format('drop policy if exists %I on public.%I;', v_pol, r.table_name); return next;
      table_name := r.table_name;
      stmt := format('create policy %I on public.%I as restrictive for update to authenticated using (public.tenant_has_feature(public.current_user_tenant_id(), %L)) with check (public.tenant_has_feature(public.current_user_tenant_id(), %L));', v_pol, r.table_name, r.feature_key, r.feature_key); return next;
      v_pol := 'ent_del_' || r.table_name;
      table_name := r.table_name;
      stmt := format('drop policy if exists %I on public.%I;', v_pol, r.table_name); return next;
      table_name := r.table_name;
      stmt := format('create policy %I on public.%I as restrictive for delete to authenticated using (public.tenant_has_feature(public.current_user_tenant_id(), %L));', v_pol, r.table_name, r.feature_key); return next;
    end if;
  end loop;
end $entitlement_build_statements$;

create or replace function public.entitlement_apply_policies()
returns table(table_name text, stmt text, status text)
language plpgsql as $entitlement_apply_policies$
declare r record;
begin
  for r in select * from public.entitlement_build_statements() loop
    if left(r.stmt,2) = '--' then
      table_name := r.table_name; stmt := r.stmt; status := 'pulado'; return next; continue;
    end if;
    begin
      execute r.stmt;
      table_name := r.table_name; stmt := r.stmt; status := 'ok'; return next;
    exception when others then
      table_name := r.table_name; stmt := r.stmt; status := 'ERRO: '||sqlerrm; return next;
    end;
  end loop;
end $entitlement_apply_policies$;

-- =====================================================================
-- FIM. Idempotente. Enforcement (policies restrictive) NAO e ligado aqui:
-- e feito depois, modulo a modulo, via entitlement_gated_tables + o gerador,
-- em fail-open primeiro (log_entitlement_denial) -> so entao aplicar.
-- =====================================================================
