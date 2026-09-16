-- =====================================================================
-- P3 (camada visual) · SCRIPT DE ENTREGA · entitlement_my_features()
-- Cole no SQL Editor de cada ambiente (Desenvolvimento -> Homologação ->
-- Produção), avançando só após o anterior dar OK.
--
-- Cria a função somente-leitura que o menu usa para saber quais módulos o
-- plano da empresa logada libera. NÃO liga bloqueio no banco. Idempotente.
-- =====================================================================

create or replace function public.entitlement_my_features()
returns setof text
language sql
stable
security definer
set search_path = public
as $entitlement_my_features$
  select f.key
  from public.features f
  where f.is_active
    and f.kind = 'boolean'
    and public.tenant_has_feature(public.current_user_tenant_id(), f.key);
$entitlement_my_features$;

grant execute on function public.entitlement_my_features() to authenticated;

-- =====================================================================
-- CONFERÊNCIA (o editor mostra só o último resultado)
-- =====================================================================
with chk(ordem, item, esperado, obtido) as (
  select 1, 'função entitlement_my_features existe', '1',
         (select count(*)::text from pg_proc where proname='entitlement_my_features')
  union all
  select 2, 'authenticated pode executar', 'sim',
         (select case when has_function_privilege('authenticated',
                   'public.entitlement_my_features()', 'execute')
                 then 'sim' else 'nao' end)
)
select item, esperado, obtido,
       case when esperado = obtido then 'OK' else 'CONFERIR' end as status
from chk order by ordem;
