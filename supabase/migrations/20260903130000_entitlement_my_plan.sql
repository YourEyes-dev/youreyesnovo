-- =====================================================================
-- P5 · PAINEL DE CONSUMO · leitura do plano da própria empresa
--
-- Função só-leitura para a tela "Meu Plano" (do cliente): devolve, de uma vez,
-- o plano atual, o uso × limite de vidas (colaboradores ativos) e a lista de
-- módulos disponíveis × bloqueados. Usa current_user_tenant_id() — o cliente
-- não passa tenant por fora.
--
-- Vidas = colaboradores ativos = admissoes com status 'concluido' (regra da
-- casa). O teto vem do motor (entitlement_resolve de 'limit.vidas').
--
-- NÃO bloqueia nada; é só leitura. Idempotente.
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
    return null;  -- sem tenant: o frontend trata como "sem plano"
  end if;

  -- plano atual (via motor)
  select p.code, p.name, p.is_public into v_plan
  from subscriptions s
  join plans p on p.id = s.plan_id
  where s.tenant_id = v_tenant;

  -- uso de vidas = colaboradores ativos
  v_used := (select count(*) from admissoes
             where tenant_id = v_tenant and status = 'concluido');

  -- teto de vidas (respeita plano + override)
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
