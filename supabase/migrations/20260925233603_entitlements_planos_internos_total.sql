-- =====================================================================
-- Entitlements — planos internos (tier 99) voltam a ter acesso TOTAL
--
-- Sintoma: no plano Early Adopter (interno, para clientes de teste) alguns
-- modulos apareciam com cadeado.
--
-- Causa: o seed original do motor ligava cada feature para todo plano com
-- tier >= min_tier SEM restricao, entao os planos internos (early_adopter e
-- tester, tier 99) recebiam TUDO. A reestrutura do catalogo
-- (20260925194050) reconstruiu a matriz so para os planos publicos
-- (tier 1..5). Os 7 modulos NOVOS criados ali (saude_ocupacional,
-- incidentes, avaliacoes, pdi, estrategia, bem_estar, financeiro) nunca
-- ganharam linha em plan_entitlements para os planos internos -> resolvem
-- como false -> cadeado.
--
-- Correcao em duas camadas:
--   (1) DURAVEL — entitlement_resolve passa a tratar plano interno (tier
--       >= 99) como acesso total por design: base habilitada e ilimitada,
--       ainda respeitando override explicito do tenant. Assim, qualquer
--       feature FUTURA ja nasce liberada nesses planos, sem depender de
--       alguem lembrar de inserir a linha.
--   (2) COERENCIA — repoe as linhas de plan_entitlements dos planos internos
--       para toda feature boolean ATIVA, para o registro/matriz continuar
--       fiel ao que o resolvedor entrega.
--
-- Aditivo, idempotente. NAO mexe nos planos publicos (tier 1..5) nem em
-- preco/assinatura. So leitura de plano no resolvedor + linhas de matriz
-- dos internos.
-- =====================================================================

set lock_timeout = '10s';

-- (1) Resolvedor: plano interno = acesso total por design ---------------
create or replace function public.entitlement_resolve(p_tenant uuid, p_feature text)
returns table(available boolean, limit_value bigint, is_unlimited boolean, source text)
language plpgsql stable security definer set search_path = public as $entitlement_resolve$
declare
  v_plan   uuid;
  v_status text;
  v_tier   int;
  v_base   record;
  v_ov     record;
  v_avail  boolean := false;
  v_limit  bigint  := null;
  v_unl    boolean := false;
  v_src    text    := 'no_subscription';
begin
  select s.plan_id, s.status, p.tier
    into v_plan, v_status, v_tier
  from subscriptions s
  join plans p on p.id = s.plan_id
  where s.tenant_id = p_tenant;

  if v_plan is null then
    return query select false, null::bigint, false, 'no_subscription';
    return;
  end if;

  -- Plano interno (tier >= 99): acesso total por design (clientes de teste).
  -- Vira a BASE; um plan_entitlement ou override explicito ainda refina.
  if coalesce(v_tier, 0) >= 99 then
    v_avail := true;
    v_unl   := true;
    v_src   := 'plan_internal';
  end if;

  -- base do plano (colunas qualificadas por alias para evitar ambiguidade)
  select pe.is_enabled, pe.limit_value, pe.is_unlimited into v_base
  from plan_entitlements pe
  where pe.plan_id = v_plan and pe.feature_key = p_feature;

  if found then
    v_avail := coalesce(v_base.is_enabled, v_avail);
    v_limit := v_base.limit_value;
    v_unl   := coalesce(v_base.is_unlimited, v_unl);
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

-- (2) Coerencia da matriz: internos recebem toda feature boolean ativa ---
insert into public.plan_entitlements (plan_id, feature_key, is_enabled)
select p.id, f.key, true
from public.plans p
join public.features f on f.kind = 'boolean' and f.is_active
where p.tier >= 99
on conflict (plan_id, feature_key) do nothing;

-- (3) Conferencia -------------------------------------------------------
do $verifica$
declare
  v_faltantes int;
begin
  -- Nenhuma feature boolean ativa pode faltar num plano interno.
  select count(*) into v_faltantes
  from public.plans p
  cross join public.features f
  where p.tier >= 99
    and f.kind = 'boolean' and f.is_active
    and not exists (
      select 1 from public.plan_entitlements pe
      where pe.plan_id = p.id and pe.feature_key = f.key and pe.is_enabled
    );
  if v_faltantes > 0 then
    raise exception 'Planos internos ainda com % feature(s) sem entitlement.', v_faltantes;
  end if;
  raise notice 'OK: planos internos com acesso total (resolvedor + matriz).';
end $verifica$;
