-- =====================================================================
-- MAPA COMPORTAMENTAL · POSICIONAMENTO NO PLANO + COTA POR CONSUMO
--
-- Decisoes de produto (set/2026):
--   - Modulo incluido a partir do Performance (tier >= 3); Starter/Essential
--     podem contratar como add-on de modulo (mensal).
--   - Cota de "mapas" = numero de pessoas mapeadas, espelhando o teto de vidas
--     do plano (20/80/200/500; Enterprise e internos ilimitado). E CONSUMO
--     acumulado (rotatividade/crescimento consomem), nao contagem instantanea.
--   - Recarga de mapas = compra AVULSA unitaria por pessoa (kind 'quota'),
--     que SOMA ao saldo (balde vitalicio) e NAO entra no valor mensal.
--   - Bloqueio REAL ao iniciar o mapa de uma pessoa nova acima da cota
--     (excecao deliberada ao gating apenas-visual). Nunca bloqueia o que ja
--     existe; re-mapear a mesma pessoa nao consome cota nova.
--
-- Idempotente. Nao cria tabela nova (nao dispara o auto-RLS do SQL Editor).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Features novas: o modulo (boolean) e a cota (metered).
-- ---------------------------------------------------------------------
insert into public.features (key, name, kind, unit, category) values
  ('mod.mapa_comportamental',   'Mapa Comportamental',                    'boolean', null,    'pessoas'),
  ('limit.mapa_comportamental', 'Analises de Mapa Comportamental',        'metered', 'mapas', 'limite')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 2) Matriz de modulo: liga para todo plano com tier >= 3 (Performance
--    para cima; planos internos tier 99 tambem entram por >= 3).
-- ---------------------------------------------------------------------
insert into public.plan_entitlements (plan_id, feature_key, is_enabled)
select p.id, 'mod.mapa_comportamental', true
from public.plans p
where p.tier >= 3
on conflict (plan_id, feature_key) do nothing;

-- ---------------------------------------------------------------------
-- 3) Cota por plano (espelha o teto de vidas). Semeada para TODOS os
--    planos, inclusive Starter/Essential: quando contratam o modulo
--    avulso, a cota ja e a do tamanho do plano deles.
-- ---------------------------------------------------------------------
insert into public.plan_entitlements (plan_id, feature_key, limit_value, is_unlimited)
select p.id, 'limit.mapa_comportamental',
  case p.code
    when 'starter'     then 20
    when 'essential'   then 80
    when 'performance' then 200
    when 'governanca'  then 500
    else null
  end,
  (p.code in ('enterprise', 'early_adopter', 'tester'))
from public.plans p
on conflict (plan_id, feature_key)
do update set limit_value  = excluded.limit_value,
              is_unlimited = excluded.is_unlimited;

-- ---------------------------------------------------------------------
-- 4) Novo kind de add-on: 'quota' (recarga avulsa de analises).
--    Remove qualquer CHECK antigo do kind e recria com os tres valores.
-- ---------------------------------------------------------------------
do $mapa_kind$
declare c text;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'public.subscription_addons'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%kind%'
  loop
    execute format('alter table public.subscription_addons drop constraint %I', c);
  end loop;
  alter table public.subscription_addons
    add constraint subscription_addons_kind_check check (kind in ('module', 'life', 'quota'));
exception when others then
  raise notice 'ajuste do check de kind: %', sqlerrm;
end $mapa_kind$;

-- ---------------------------------------------------------------------
-- 5) Contratacao de add-on: novo ramo 'quota' (limit.mapa_comportamental).
--    Modulo e vida seguem iguais. Quota SOMA (append-only) e recalcula o
--    override do teto para base + total comprado.
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
  v_total      bigint;
begin
  if v_tenant is null then
    raise exception 'Empresa não identificada';
  end if;

  select unit_price_cents into v_price
  from public.addon_prices where feature_key = _feature_key and is_active;
  if v_price is null or v_price <= 0 then
    raise exception 'Item não disponível para contratação';
  end if;

  v_kind := case
              when _feature_key = 'limit.vidas' then 'life'
              when _feature_key = 'limit.mapa_comportamental' then 'quota'
              else 'module'
            end;

  if v_kind = 'module' then
    if public.tenant_has_feature(v_tenant, _feature_key) then
      raise exception 'Módulo já disponível no seu plano';
    end if;
    update public.subscription_addons set ativo = false
      where tenant_id = v_tenant and feature_key = _feature_key and ativo;
    insert into public.subscription_addons (tenant_id, feature_key, kind, quantity, unit_price_cents, created_by)
    values (v_tenant, _feature_key, 'module', 1, v_price, auth.uid());
    delete from public.subscription_overrides
      where tenant_id = v_tenant and feature_key = _feature_key and reason = 'add-on self-service';
    insert into public.subscription_overrides (tenant_id, feature_key, is_enabled, reason, created_by)
    values (v_tenant, _feature_key, true, 'add-on self-service', auth.uid());

  elsif v_kind = 'life' then
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
    delete from public.subscription_overrides
      where tenant_id = v_tenant and feature_key = 'limit.vidas' and reason = 'add-on self-service';
    insert into public.subscription_overrides (tenant_id, feature_key, limit_value, is_unlimited, reason, created_by)
    values (v_tenant, 'limit.vidas', coalesce(v_base_limit, 0) + _quantity, false, 'add-on self-service', auth.uid());

  else  -- 'quota': recarga avulsa de analises de mapa (SOMA ao saldo)
    if _quantity is null or _quantity < 1 then
      raise exception 'Informe quantas análises deseja adicionar';
    end if;
    select pe.limit_value, coalesce(pe.is_unlimited, false) into v_base_limit, v_base_unl
    from public.subscriptions s
    join public.plan_entitlements pe on pe.plan_id = s.plan_id and pe.feature_key = 'limit.mapa_comportamental'
    where s.tenant_id = v_tenant;
    if coalesce(v_base_unl, false) then
      raise exception 'Seu plano já tem análises ilimitadas';
    end if;

    -- Append-only: cada compra fica registrada; o saldo e a soma de todas.
    insert into public.subscription_addons (tenant_id, feature_key, kind, quantity, unit_price_cents, created_by)
    values (v_tenant, 'limit.mapa_comportamental', 'quota', _quantity, v_price, auth.uid());

    v_total := coalesce((
      select sum(sa.quantity) from public.subscription_addons sa
      where sa.tenant_id = v_tenant and sa.feature_key = 'limit.mapa_comportamental'
        and sa.kind = 'quota' and sa.ativo
    ), 0);

    delete from public.subscription_overrides
      where tenant_id = v_tenant and feature_key = 'limit.mapa_comportamental' and reason = 'add-on self-service';
    insert into public.subscription_overrides (tenant_id, feature_key, limit_value, is_unlimited, reason, created_by)
    values (v_tenant, 'limit.mapa_comportamental', coalesce(v_base_limit, 0) + v_total, false, 'add-on self-service', auth.uid());
  end if;
end $my_contratar_addon$;

grant execute on function public.my_contratar_addon(text, integer) to authenticated;

-- ---------------------------------------------------------------------
-- 6) Cancelamento: recarga de analises e compra avulsa, nao cancelavel.
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
  if _feature_key = 'limit.mapa_comportamental' then
    raise exception 'Recargas de análises são compras avulsas e não podem ser canceladas';
  end if;
  update public.subscription_addons set ativo = false
    where tenant_id = v_tenant and feature_key = _feature_key and ativo;
  delete from public.subscription_overrides
    where tenant_id = v_tenant and feature_key = _feature_key and reason = 'add-on self-service';
end $my_cancelar_addon$;

grant execute on function public.my_cancelar_addon(text) to authenticated;

-- ---------------------------------------------------------------------
-- 7) entitlement_my_plan(): + bloco 'mapas' (uso x cota). Quota fica FORA
--    do valor mensal e da lista de add-ons recorrentes (e compra avulsa).
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
  v_mapas  record;
  v_used   bigint;
  v_limit  bigint;
  v_unl    boolean;
  v_mapas_used  bigint;
  v_mapas_limit bigint;
  v_mapas_unl   boolean;
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

  -- mapas usados = pessoas distintas com mapa CONCLUIDO (por CPF; na
  -- autoaplicacao sem CPF, cai no auth_user_id).
  v_mapas_used := (
    select count(distinct coalesce(
             nullif(regexp_replace(coalesce(r.colaborador_cpf, ''), '[^0-9]', '', 'g'), ''),
             r.auth_user_id::text))
    from mapa_comportamental_respostas r
    where r.tenant_id = v_tenant and r.status = 'concluido'
  );
  select limit_value, is_unlimited into v_mapas
  from entitlement_resolve(v_tenant, 'limit.mapa_comportamental');
  v_mapas_limit := v_mapas.limit_value;
  v_mapas_unl   := coalesce(v_mapas.is_unlimited, false);

  v_base_cents := (select pp.amount_cents from plan_prices pp
                   where pp.plan_id = v_plan.plan_id and pp.period = 'monthly' and pp.is_active
                   limit 1);
  -- Valor mensal soma so o que e recorrente (vida e modulo). Quota nao entra.
  v_addons_cents := coalesce((
    select sum(case when sa.kind = 'life' then sa.quantity * sa.unit_price_cents
                    when sa.kind = 'module' then sa.unit_price_cents
                    else 0 end)
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
    'mapas', jsonb_build_object(
      'used', v_mapas_used,
      'limit', v_mapas_limit,
      'is_unlimited', v_mapas_unl,
      'remaining', case when v_mapas_unl or v_mapas_limit is null then null else greatest(v_mapas_limit - v_mapas_used, 0) end,
      'percent',   case when v_mapas_unl or v_mapas_limit is null or v_mapas_limit = 0 then null
                        else least(round(v_mapas_used::numeric * 100 / v_mapas_limit)::int, 100) end
    ),
    'modulos', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'key', f.key, 'name', f.name, 'category', f.category,
               'disponivel', public.tenant_has_feature(v_tenant, f.key)
             ) order by f.category nulls last, f.name), '[]'::jsonb)
      from features f where f.is_active and f.kind = 'boolean'
    ),
    'precos', coalesce((
      select jsonb_object_agg(ap.feature_key, ap.unit_price_cents)
      from addon_prices ap where ap.is_active and ap.unit_price_cents > 0
    ), '{}'::jsonb),
    -- add-ons recorrentes ativos (modulo e vida); quota (avulso) fica fora.
    'addons', coalesce((
      select jsonb_agg(jsonb_build_object(
               'feature_key', sa.feature_key, 'name', f.name, 'kind', sa.kind,
               'quantity', sa.quantity, 'unit_price_cents', sa.unit_price_cents
             ) order by sa.kind, f.name)
      from subscription_addons sa join features f on f.key = sa.feature_key
      where sa.tenant_id = v_tenant and sa.ativo and sa.kind in ('module', 'life')
    ), '[]'::jsonb),
    'valores', jsonb_build_object(
      'base_cents', v_base_cents,
      'addons_cents', v_addons_cents,
      'total_cents', case when v_base_cents is null then null else v_base_cents + v_addons_cents end
    )
  );
end $entitlement_my_plan$;

grant execute on function public.entitlement_my_plan() to authenticated;

-- ---------------------------------------------------------------------
-- 8) Catalogo do SuperAdmin: inclui a recarga de mapas (kind 'quota').
-- ---------------------------------------------------------------------
create or replace function public.superadmin_addon_prices_list()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $superadmin_addon_prices_list$
declare result jsonb;
begin
  if not public.is_superadmin(auth.uid()) then
    raise exception 'Acesso negado';
  end if;

  select coalesce(jsonb_agg(
           jsonb_build_object(
             'key', f.key,
             'name', f.name,
             'category', f.category,
             'kind', case
                       when f.key = 'limit.vidas' then 'life'
                       when f.key = 'limit.mapa_comportamental' then 'quota'
                       else 'module'
                     end,
             'unit_price_cents', coalesce(ap.unit_price_cents, 0)
           )
           order by (f.key in ('limit.vidas', 'limit.mapa_comportamental')) desc,
                    f.category nulls last, f.name
         ), '[]'::jsonb)
  into result
  from public.features f
  left join public.addon_prices ap on ap.feature_key = f.key
  where f.is_active and (f.kind = 'boolean' or f.key in ('limit.vidas', 'limit.mapa_comportamental'));

  return result;
end $superadmin_addon_prices_list$;

grant execute on function public.superadmin_addon_prices_list() to authenticated;

-- ---------------------------------------------------------------------
-- 9) Bloqueio real da cota: trigger BEFORE INSERT em respostas. Roda
--    depois do carimbo de identidade (nome 'cota' > 'carimbar'), entao
--    NEW.tenant_id / colaborador_cpf ja estao preenchidos. Cobre os tres
--    caminhos (autoaplicacao, campanha, link publico). Nunca bloqueia
--    quem ja existe; re-mapear a mesma pessoa nao consome cota.
-- ---------------------------------------------------------------------
create or replace function public.mapa_comportamental_checar_cota()
returns trigger
language plpgsql
security definer
set search_path = public
as $mapa_cota$
declare
  v_tenant uuid := NEW.tenant_id;
  v_cpf    text := nullif(regexp_replace(coalesce(NEW.colaborador_cpf, ''), '[^0-9]', '', 'g'), '');
  v_res    record;
  v_used   bigint;
begin
  if v_tenant is null then
    return NEW;  -- sem tenant, deixa RLS/identidade tratarem
  end if;

  select limit_value, is_unlimited into v_res
  from public.entitlement_resolve(v_tenant, 'limit.mapa_comportamental');
  if v_res.is_unlimited or v_res.limit_value is null then
    return NEW;  -- ilimitado (Enterprise/internos) ou sem cota definida
  end if;

  -- Re-mapear alguem ja concluido (por CPF ou pelo proprio usuario) nao consome.
  if exists (
    select 1 from public.mapa_comportamental_respostas r
    where r.tenant_id = v_tenant and r.status = 'concluido'
      and ( (v_cpf is not null
             and nullif(regexp_replace(coalesce(r.colaborador_cpf, ''), '[^0-9]', '', 'g'), '') = v_cpf)
         or (NEW.auth_user_id is not null and r.auth_user_id = NEW.auth_user_id) )
  ) then
    return NEW;
  end if;

  v_used := (
    select count(distinct coalesce(
             nullif(regexp_replace(coalesce(r.colaborador_cpf, ''), '[^0-9]', '', 'g'), ''),
             r.auth_user_id::text))
    from public.mapa_comportamental_respostas r
    where r.tenant_id = v_tenant and r.status = 'concluido'
  );

  if v_used >= v_res.limit_value then
    raise exception 'Cota de mapas comportamentais atingida (% de %). Contrate mais análises em Meu Plano.',
      v_used, v_res.limit_value using errcode = 'check_violation';
  end if;

  return NEW;
end $mapa_cota$;

drop trigger if exists trg_mapa_comp_cota on public.mapa_comportamental_respostas;
create trigger trg_mapa_comp_cota
  before insert on public.mapa_comportamental_respostas
  for each row execute function public.mapa_comportamental_checar_cota();
