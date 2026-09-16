-- =====================================================================
-- P1 · PLANO DA EMPRESA VIA MOTOR DE ENTITLEMENTS
--
-- Objetivo: o painel Super Admin passa a definir o plano de uma empresa
-- gravando no MOTOR (public.subscriptions), em vez de so escrever o rotulo
-- legado em tenants.plano. A verdade do plano passa a morar em subscriptions.
--
-- NAO mexe no enum public.tenant_plan nem em tenants.plano (que continua
-- existindo como rotulo legado). NAO liga nenhum bloqueio (enforcement
-- segue desligado) - mudar o plano so registra a escolha.
--
-- Duas pequenas mudancas, ambas idempotentes:
--   1) superadmin_set_tenant_plan(tenant, plan_code): grava/atualiza a
--      assinatura da empresa (server-side, restrito a superadmin).
--   2) superadmin_tenants_list(): passa a devolver tambem 'plano_atual'
--      (o code do plano vigente no motor), para o painel exibir o plano real.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Escrita segura do plano (restrita a superadmin)
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- 2) Listagem de empresas passa a expor o plano vigente no motor.
--    (Redefinicao fiel da funcao existente + o campo plano_atual.)
-- ---------------------------------------------------------------------
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
