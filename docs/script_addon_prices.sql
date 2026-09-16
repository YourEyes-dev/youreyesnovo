-- =====================================================================
-- ADD-ONS · FASE 1 · SCRIPT DE ENTREGA · catálogo de preços
-- Cole no SQL Editor de cada ambiente (Desenvolvimento -> Homologação ->
-- Produção), avançando só após o anterior dar OK.
--
-- Cria a tabela addon_prices + funções de superadmin para configurar o
-- preço de cada módulo avulso e da vida extra. NÃO cobra nem bloqueia.
-- Idempotente.
-- =====================================================================

create table if not exists public.addon_prices (
  feature_key      text primary key references public.features(key) on delete cascade,
  unit_price_cents integer not null default 0,
  is_active        boolean not null default true,
  updated_at       timestamptz not null default now()
);

alter table public.addon_prices enable row level security;
drop policy if exists p_addon_prices_read on public.addon_prices;
create policy p_addon_prices_read on public.addon_prices
  for select to anon, authenticated using (true);

create or replace function public.superadmin_set_addon_price(_feature_key text, _cents integer)
returns void
language plpgsql
security definer
set search_path = public
as $superadmin_set_addon_price$
begin
  if not public.is_superadmin(auth.uid()) then
    raise exception 'Acesso negado';
  end if;
  if not exists (select 1 from public.features where key = _feature_key) then
    raise exception 'Feature inexistente: %', _feature_key;
  end if;

  insert into public.addon_prices (feature_key, unit_price_cents, updated_at)
  values (_feature_key, greatest(coalesce(_cents, 0), 0), now())
  on conflict (feature_key)
  do update set unit_price_cents = greatest(coalesce(excluded.unit_price_cents, 0), 0),
                updated_at = now();
end $superadmin_set_addon_price$;

grant execute on function public.superadmin_set_addon_price(text, integer) to authenticated;

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
             'kind', case when f.key = 'limit.vidas' then 'life' else 'module' end,
             'unit_price_cents', coalesce(ap.unit_price_cents, 0)
           )
           order by (f.key = 'limit.vidas') desc, f.category nulls last, f.name
         ), '[]'::jsonb)
  into result
  from public.features f
  left join public.addon_prices ap on ap.feature_key = f.key
  where f.is_active and (f.kind = 'boolean' or f.key = 'limit.vidas');

  return result;
end $superadmin_addon_prices_list$;

grant execute on function public.superadmin_addon_prices_list() to authenticated;

-- =====================================================================
-- CONFERÊNCIA (o editor mostra só o último resultado)
-- =====================================================================
with chk(ordem, item, esperado, obtido) as (
  select 1, 'tabela addon_prices existe', '1',
         (select count(*)::text from information_schema.tables
          where table_schema='public' and table_name='addon_prices')
  union all
  select 2, 'função superadmin_set_addon_price existe', '1',
         (select count(*)::text from pg_proc where proname='superadmin_set_addon_price')
  union all
  select 3, 'função superadmin_addon_prices_list existe', '1',
         (select count(*)::text from pg_proc where proname='superadmin_addon_prices_list')
)
select item, esperado, obtido,
       case when esperado = obtido then 'OK' else 'CONFERIR' end as status
from chk order by ordem;
