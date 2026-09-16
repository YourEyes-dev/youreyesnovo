-- =====================================================================
-- ADD-ONS · FASE 2 · CONTRATAÇÃO EM AUTOSSERVIÇO + VALOR MENSAL
--
-- O cliente contrata módulos avulsos / vidas extras por conta própria na
-- tela "Meu Plano": o efeito é imediato (via override do motor) e o valor
-- mensal é recalculado (base do plano + add-ons). NÃO cobra automaticamente
-- (o financeiro concilia). Idempotente.
-- =====================================================================

-- Registro dos add-ons contratados (preço congelado no momento da contratação).
create table if not exists public.subscription_addons (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null,
  feature_key      text not null references public.features(key) on delete cascade,
  kind             text not null check (kind in ('module','life')),
  quantity         integer not null default 1,          -- módulo: 1; vidas: nº de vidas extras
  unit_price_cents integer not null default 0,           -- congelado na contratação
  ativo            boolean not null default true,
  contratado_em    timestamptz not null default now(),
  created_by       uuid
);
create index if not exists idx_sub_addons_ativos
  on public.subscription_addons (tenant_id) where ativo;

-- Sem policy permissiva: acesso só pelas funções SECURITY DEFINER abaixo.
alter table public.subscription_addons enable row level security;

-- ---------------------------------------------------------------------
-- Contratar um add-on (módulo avulso ou vidas extras) — pelo próprio cliente.
-- ---------------------------------------------------------------------
create or replace function public.my_contratar_addon(_feature_key text, _quantity integer default 1)
returns void
language plpgsql
security definer
set search_path = public
as $my_contratar_addon$
declare
  v_tenant     uuid := public.current_user_tenant_id();
  v_price      integer;
  v_kind       text;
  v_base_limit bigint;
  v_base_unl   boolean;
begin
  if v_tenant is null then
    raise exception 'Empresa não identificada';
  end if;

  select unit_price_cents into v_price
  from public.addon_prices where feature_key = _feature_key and is_active;
  if v_price is null or v_price <= 0 then
    raise exception 'Item não disponível para contratação';
  end if;

  v_kind := case when _feature_key = 'limit.vidas' then 'life' else 'module' end;

  if v_kind = 'module' then
    if public.tenant_has_feature(v_tenant, _feature_key) then
      raise exception 'Módulo já disponível no seu plano';
    end if;
    -- registra a contratação (substitui um cancelado anterior, se houver)
    update public.subscription_addons set ativo = false
      where tenant_id = v_tenant and feature_key = _feature_key and ativo;
    insert into public.subscription_addons (tenant_id, feature_key, kind, quantity, unit_price_cents, created_by)
    values (v_tenant, _feature_key, 'module', 1, v_price, auth.uid());
    -- libera na hora (override do motor)
    delete from public.subscription_overrides
      where tenant_id = v_tenant and feature_key = _feature_key and reason = 'add-on self-service';
    insert into public.subscription_overrides (tenant_id, feature_key, is_enabled, reason, created_by)
    values (v_tenant, _feature_key, true, 'add-on self-service', auth.uid());

  else  -- vidas extras (semântica: total de vidas extras contratadas)
    if _quantity is null or _quantity < 1 then
      raise exception 'Informe quantas vidas extras deseja';
    end if;
    select pe.limit_value, coalesce(pe.is_unlimited, false) into v_base_limit, v_base_unl
    from public.subscriptions s
    join public.plan_entitlements pe on pe.plan_id = s.plan_id and pe.feature_key = 'limit.vidas'
    where s.tenant_id = v_tenant;
    if coalesce(v_base_unl, false) then
      raise exception 'Seu plano já tem vidas ilimitadas';
    end if;

    update public.subscription_addons set ativo = false
      where tenant_id = v_tenant and feature_key = 'limit.vidas' and ativo;
    insert into public.subscription_addons (tenant_id, feature_key, kind, quantity, unit_price_cents, created_by)
    values (v_tenant, 'limit.vidas', 'life', _quantity, v_price, auth.uid());
    -- eleva o teto para base + extras
    delete from public.subscription_overrides
      where tenant_id = v_tenant and feature_key = 'limit.vidas' and reason = 'add-on self-service';
    insert into public.subscription_overrides (tenant_id, feature_key, limit_value, is_unlimited, reason, created_by)
    values (v_tenant, 'limit.vidas', coalesce(v_base_limit, 0) + _quantity, false, 'add-on self-service', auth.uid());
  end if;
end $my_contratar_addon$;

grant execute on function public.my_contratar_addon(text, integer) to authenticated;

-- ---------------------------------------------------------------------
-- Cancelar um add-on contratado (remove o efeito e desativa o registro).
-- ---------------------------------------------------------------------
create or replace function public.my_cancelar_addon(_feature_key text)
returns void
language plpgsql
security definer
set search_path = public
as $my_cancelar_addon$
declare v_tenant uuid := public.current_user_tenant_id();
begin
  if v_tenant is null then
    raise exception 'Empresa não identificada';
  end if;
  update public.subscription_addons set ativo = false
    where tenant_id = v_tenant and feature_key = _feature_key and ativo;
  -- desfaz só o override criado pela contratação em autosserviço
  delete from public.subscription_overrides
    where tenant_id = v_tenant and feature_key = _feature_key and reason = 'add-on self-service';
end $my_cancelar_addon$;

grant execute on function public.my_cancelar_addon(text) to authenticated;

-- ---------------------------------------------------------------------
-- entitlement_my_plan() ESTENDIDA: + preços de add-on, + valor mensal,
-- + lista de add-ons contratados (para a tela fazer tudo numa chamada).
-- ---------------------------------------------------------------------
create or replace function public.entitlement_my_plan()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $entitlement_my_plan$
declare
  v_tenant uuid := public.current_user_tenant_id();
  v_plan   record;
  v_vidas  record;
  v_used   bigint;
  v_limit  bigint;
  v_unl    boolean;
  v_base_cents   integer;
  v_addons_cents integer;
begin
  if v_tenant is null then
    return null;
  end if;

  select p.id as plan_id, p.code, p.name, p.is_public into v_plan
  from subscriptions s join plans p on p.id = s.plan_id
  where s.tenant_id = v_tenant;

  v_used := (select count(*) from admissoes where tenant_id = v_tenant and status = 'concluido');

  select limit_value, is_unlimited into v_vidas
  from entitlement_resolve(v_tenant, 'limit.vidas');
  v_limit := v_vidas.limit_value;
  v_unl   := coalesce(v_vidas.is_unlimited, false);

  -- preço-base do plano (mensal) e soma dos add-ons ativos
  v_base_cents := (select pp.amount_cents from plan_prices pp
                   where pp.plan_id = v_plan.plan_id and pp.period = 'monthly' and pp.is_active
                   limit 1);
  v_addons_cents := coalesce((
    select sum(case when sa.kind = 'life' then sa.quantity * sa.unit_price_cents
                    else sa.unit_price_cents end)
    from subscription_addons sa
    where sa.tenant_id = v_tenant and sa.ativo
  ), 0);

  return jsonb_build_object(
    'plano',
      case when v_plan.code is null then null
      else jsonb_build_object('code', v_plan.code, 'name', v_plan.name, 'is_public', v_plan.is_public)
      end,
    'vidas', jsonb_build_object(
      'used', v_used,
      'limit', v_limit,
      'is_unlimited', v_unl,
      'remaining', case when v_unl or v_limit is null then null else greatest(v_limit - v_used, 0) end,
      'percent',   case when v_unl or v_limit is null or v_limit = 0 then null
                        else least(round(v_used::numeric * 100 / v_limit)::int, 100) end
    ),
    'modulos', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'key', f.key, 'name', f.name, 'category', f.category,
               'disponivel', public.tenant_has_feature(v_tenant, f.key)
             ) order by f.category nulls last, f.name), '[]'::jsonb)
      from features f where f.is_active and f.kind = 'boolean'
    ),
    -- preços disponíveis para contratação (feature_key -> centavos), > 0
    'precos', coalesce((
      select jsonb_object_agg(ap.feature_key, ap.unit_price_cents)
      from addon_prices ap where ap.is_active and ap.unit_price_cents > 0
    ), '{}'::jsonb),
    -- add-ons já contratados (ativos)
    'addons', coalesce((
      select jsonb_agg(jsonb_build_object(
               'feature_key', sa.feature_key, 'name', f.name, 'kind', sa.kind,
               'quantity', sa.quantity, 'unit_price_cents', sa.unit_price_cents
             ) order by sa.kind, f.name)
      from subscription_addons sa join features f on f.key = sa.feature_key
      where sa.tenant_id = v_tenant and sa.ativo
    ), '[]'::jsonb),
    'valores', jsonb_build_object(
      'base_cents', v_base_cents,
      'addons_cents', v_addons_cents,
      'total_cents', case when v_base_cents is null then null else v_base_cents + v_addons_cents end
    )
  );
end $entitlement_my_plan$;

grant execute on function public.entitlement_my_plan() to authenticated;
