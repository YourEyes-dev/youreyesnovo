-- =====================================================================
-- P1 · SCRIPT DE ENTREGA · PLANO DA EMPRESA VIA MOTOR
-- Cole no SQL Editor de cada ambiente (Desenvolvimento -> Homologacao ->
-- Producao), nesta ordem, so avancando apos o anterior dar tudo OK.
--
-- O que faz: painel Super Admin passa a gravar o plano da empresa no motor
-- (public.subscriptions) e a listagem passa a mostrar o plano vigente.
-- NAO mexe no enum tenant_plan; NAO liga bloqueio nenhum. Idempotente.
-- =====================================================================

create or replace function public.superadmin_set_tenant_plan(
  _tenant_id uuid, _plan_code text)
returns text
language plpgsql
security definer
set search_path to 'public'
as $superadmin_set_tenant_plan$
declare v_plan_id uuid;
begin
  if not public.is_superadmin(auth.uid()) then
    raise exception 'Acesso negado';
  end if;

  select id into v_plan_id from public.plans where code = _plan_code;
  if v_plan_id is null then
    raise exception 'Plano inexistente: %', _plan_code;
  end if;

  insert into public.subscriptions (tenant_id, plan_id)
  values (_tenant_id, v_plan_id)
  on conflict (tenant_id) do update set plan_id = excluded.plan_id;

  return _plan_code;
end $superadmin_set_tenant_plan$;

grant execute on function public.superadmin_set_tenant_plan(uuid, text) to authenticated;

create or replace function public.superadmin_tenants_list()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $superadmin_tenants_list$
declare result jsonb;
begin
  if not public.is_superadmin(auth.uid()) then
    raise exception 'Acesso negado';
  end if;

  select jsonb_agg(row_to_json(x) order by x.created_at desc) into result
  from (
    select
      t.*,
      ec.email,
      ec.telefone,
      ec.cnpj,
      (select p.code
         from subscriptions s
         join plans p on p.id = s.plan_id
        where s.tenant_id = t.id) as plano_atual,
      (select count(*) from profiles where tenant_id = t.id) as total_usuarios,
      (select count(*) from admissoes where tenant_id = t.id and status = 'concluido') as total_colaboradores
    from tenants t
    left join lateral (
      select email, telefone, cnpj
      from empresa_cadastro
      where tenant_id = t.id and tipo_unidade = 'matriz'
      order by created_at desc
      limit 1
    ) ec on true
  ) x;

  return coalesce(result, '[]'::jsonb);
end $superadmin_tenants_list$;

-- =====================================================================
-- CONFERENCIA FINAL (o editor mostra so este ultimo resultado)
-- =====================================================================
with chk(ordem, item, esperado, obtido) as (
  select 1, 'funcao superadmin_set_tenant_plan existe', '1',
         (select count(*)::text from pg_proc where proname='superadmin_set_tenant_plan')
  union all
  select 2, 'funcao superadmin_tenants_list existe', '1',
         (select count(*)::text from pg_proc where proname='superadmin_tenants_list')
  union all
  select 3, 'superadmin_tenants_list expoe plano_atual', 'sim',
         (select case when exists (
            select 1 from pg_proc
            where proname='superadmin_tenants_list'
              and pg_get_functiondef(oid) like '%plano_atual%'
          ) then 'sim' else 'nao' end)
)
select item, esperado, obtido,
       case when esperado = obtido then 'OK' else 'CONFERIR' end as status
from chk order by ordem;
