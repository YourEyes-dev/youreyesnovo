-- =====================================================================
-- P5 · SCRIPT DE ENTREGA · entitlement_my_plan()
-- Cole no SQL Editor de cada ambiente (Desenvolvimento -> Homologação ->
-- Produção), avançando só após o anterior dar OK.
--
-- Cria a função só-leitura que alimenta a tela "Meu Plano" (plano atual,
-- uso × limite de vidas, módulos disponíveis × bloqueados). NÃO bloqueia
-- nada. Idempotente.
-- =====================================================================

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
begin
  if v_tenant is null then
    return null;
  end if;

  select p.code, p.name, p.is_public into v_plan
  from subscriptions s
  join plans p on p.id = s.plan_id
  where s.tenant_id = v_tenant;

  v_used := (select count(*) from admissoes
             where tenant_id = v_tenant and status = 'concluido');

  select limit_value, is_unlimited into v_vidas
  from entitlement_resolve(v_tenant, 'limit.vidas');
  v_limit := v_vidas.limit_value;
  v_unl   := coalesce(v_vidas.is_unlimited, false);

  return jsonb_build_object(
    'plano',
      case when v_plan.code is null then null
      else jsonb_build_object('code', v_plan.code, 'name', v_plan.name, 'is_public', v_plan.is_public)
      end,
    'vidas', jsonb_build_object(
      'used', v_used,
      'limit', v_limit,
      'is_unlimited', v_unl,
      'remaining',
        case when v_unl or v_limit is null then null
        else greatest(v_limit - v_used, 0) end,
      'percent',
        case when v_unl or v_limit is null or v_limit = 0 then null
        else least(round(v_used::numeric * 100 / v_limit)::int, 100) end
    ),
    'modulos', (
      select coalesce(jsonb_agg(
               jsonb_build_object(
                 'key', f.key,
                 'name', f.name,
                 'category', f.category,
                 'disponivel', public.tenant_has_feature(v_tenant, f.key)
               ) order by f.category nulls last, f.name
             ), '[]'::jsonb)
      from features f
      where f.is_active and f.kind = 'boolean'
    )
  );
end $entitlement_my_plan$;

grant execute on function public.entitlement_my_plan() to authenticated;

-- =====================================================================
-- CONFERÊNCIA (o editor mostra só o último resultado)
-- =====================================================================
with chk(ordem, item, esperado, obtido) as (
  select 1, 'função entitlement_my_plan existe', '1',
         (select count(*)::text from pg_proc where proname='entitlement_my_plan')
  union all
  select 2, 'authenticated pode executar', 'sim',
         (select case when has_function_privilege('authenticated',
                   'public.entitlement_my_plan()', 'execute')
                 then 'sim' else 'nao' end)
)
select item, esperado, obtido,
       case when esperado = obtido then 'OK' else 'CONFERIR' end as status
from chk order by ordem;
