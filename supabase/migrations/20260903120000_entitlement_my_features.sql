-- =====================================================================
-- P3 (camada visual) · LEITURA DAS FUNCIONALIDADES DO PRÓPRIO TENANT
--
-- Função somente-leitura para o frontend (menu) descobrir, de uma vez, quais
-- módulos o plano da empresa logada libera. Usa current_user_tenant_id(),
-- então o cliente não passa tenant por fora (sem risco de espiar outro).
--
-- Respeita plano + override + status da assinatura (via tenant_has_feature).
-- Se a empresa não tiver assinatura, devolve VAZIO — e o frontend, por
-- segurança, trata vazio como "mostrar tudo" (à prova de falha).
--
-- NÃO liga bloqueio nenhum no banco: é só leitura para a UX do menu.
-- Idempotente.
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
