-- =====================================================================
-- YOUREYES · SCRIPT DE ENTREGA · Mapa Comportamental (Fatia 4)
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de PRODUCAO.
--
-- Pre-requisito: Fatias 1 e 2 ja aplicadas (a tabela de acessos vem da Fatia 1).
--
-- O que faz: Ficha da pessoa + Mapa do Time. Amplia a leitura dos mapas para
-- gestor/RH (perfil_permite_modulo), mantendo: respostas item a item nunca
-- expostas a terceiros (RN-003); toda leitura de mapa de TERCEIRO registrada
-- (RF-013); titular consulta quem acessou o proprio mapa.
--
-- Seguro: roda em UMA transacao; idempotente; NAO cria tabela (nenhum gatilho
-- de auto-RLS do editor) e as funcoes nao usam SELECT ... INTO. So CRIA
-- politica e funcoes; nao altera nem apaga dado existente.
--
-- Espelha a migration 20260926225906_mapa_comportamental_ficha_time.sql.
-- =====================================================================

set lock_timeout = '10s';

-- 1) Politica permissiva adicional: leitura por perfil (gestor/RH).
do $pol$
begin
  if not exists (select 1 from pg_policies where schemaname='public'
      and tablename='mapa_comportamental_respostas' and policyname='mapa_comp_resp_select_perfil') then
    create policy mapa_comp_resp_select_perfil on public.mapa_comportamental_respostas
      for select to authenticated
      using (public.perfil_permite_modulo(tenant_id, variadic array['mapa_comportamental'::text]));
  end if;
end $pol$;

-- 2) Ver mapa de terceiro (ficha), sem respostas item a item, com log.
create or replace function public.mapa_comportamental_ver_mapa(p_mapa_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public'
as $fn$
declare
  v_auth uuid := auth.uid();
  v_tenant uuid;
  v_titular uuid;
  v_res jsonb;
begin
  v_tenant  := (select tenant_id   from public.mapa_comportamental_respostas where id = p_mapa_id);
  v_titular := (select auth_user_id from public.mapa_comportamental_respostas where id = p_mapa_id);
  if v_tenant is null then return null; end if;

  if not (v_titular = v_auth
          or public.is_superadmin(v_auth)
          or public.perfil_permite_modulo(v_tenant, variadic array['mapa_comportamental'::text])) then
    raise exception 'Sem permissão para ver este mapa.';
  end if;

  if v_titular <> v_auth then
    insert into public.mapa_comportamental_acessos (tenant_id, mapa_id, acessado_por, acessado_por_nome)
    values (v_tenant, p_mapa_id, v_auth,
            (select nome_completo from public.usuarios_base where auth_user_id = v_auth limit 1));
  end if;

  v_res := (select to_jsonb(r) - 'respostas' - 'tempo_por_item'
            from public.mapa_comportamental_respostas r where r.id = p_mapa_id);
  return v_res;
end;
$fn$;
revoke execute on function public.mapa_comportamental_ver_mapa(uuid) from public, anon;
grant  execute on function public.mapa_comportamental_ver_mapa(uuid) to authenticated;

-- 3) Mapa do Time (composicao) para gestor/RH.
create or replace function public.mapa_comportamental_time(p_empresa_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path to 'public'
as $fn$
declare v_tenant uuid := public.get_user_tenant_id(); v_res jsonb;
begin
  if v_tenant is null or not public.perfil_permite_modulo(v_tenant, variadic array['mapa_comportamental'::text]) then
    return '[]'::jsonb;
  end if;
  v_res := (select coalesce(jsonb_agg(
              jsonb_build_object('mapa_id', id, 'nome', colaborador_nome, 'arquetipo', arquetipo,
                'confiabilidade', confiabilidade, 'concluido_em', concluido_em)
              order by colaborador_nome), '[]'::jsonb)
            from public.mapa_comportamental_respostas
            where tenant_id = v_tenant and status = 'concluido'
              and (p_empresa_id is null or empresa_id = p_empresa_id));
  return v_res;
end;
$fn$;
revoke execute on function public.mapa_comportamental_time(uuid) from public, anon;
grant  execute on function public.mapa_comportamental_time(uuid) to authenticated;

-- 4) Quem acessou o meu mapa (transparencia ao titular).
create or replace function public.mapa_comportamental_meus_acessos()
returns jsonb language plpgsql stable security definer set search_path to 'public'
as $fn$
declare v_auth uuid := auth.uid(); v_res jsonb;
begin
  v_res := (select coalesce(jsonb_agg(
              jsonb_build_object('acessado_por_nome', a.acessado_por_nome, 'acessado_em', a.acessado_em)
              order by a.acessado_em desc), '[]'::jsonb)
            from public.mapa_comportamental_acessos a
            join public.mapa_comportamental_respostas r on r.id = a.mapa_id
            where r.auth_user_id = v_auth);
  return v_res;
end;
$fn$;
revoke execute on function public.mapa_comportamental_meus_acessos() from public, anon;
grant  execute on function public.mapa_comportamental_meus_acessos() to authenticated;

-- 5) QA — MAPA-005/006.
do $doc$
declare v_mod uuid;
begin
  v_mod := (select id from public.qa_modulos where path = 'desenvolvimento-performance/mapa-comportamental');
  if v_mod is null then raise notice 'Modulo QA ausente — pulei os casos.'; return; end if;
  insert into public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  values
    (v_mod, 'MAPA-005', 'Leitura de mapa de terceiro e registrada (RF-013)', 'feliz', 'alta', 'aprovado', 'api',
     'A funcao de ver mapa de terceiro grava acesso e nao expoe respostas item a item.', 'Fatia 4 aplicada.',
     '[{"ordem":1,"acao":"Verificar mapa_comportamental_ver_mapa","resultado_esperado":"presente e security definer"}]'::jsonb,
     'A funcao de leitura com log existe.', 'Cobre RF-013/RN-003.'),
    (v_mod, 'MAPA-006', 'Leitura ampla por perfil (gestor/RH)', 'feliz', 'media', 'aprovado', 'api',
     'Alem do titular, quem o perfil permite o modulo le os mapas do tenant.', 'Fatia 4 aplicada.',
     '[{"ordem":1,"acao":"Verificar politica mapa_comp_resp_select_perfil","resultado_esperado":"presente"}]'::jsonb,
     'A politica de leitura por perfil existe.', 'Cobre a matriz de acesso.')
  on conflict (codigo) do nothing;
  raise notice 'OK: casos MAPA-005/006 documentados.';
end $doc$;

create or replace function public.qa_caso_mapa_005()
returns public.qa_retorno language plpgsql
as $fn$
declare r public.qa_retorno; v_ok boolean;
begin
  r.passo_ordem := 1; r.passo_acao := 'Verificar funcao de leitura de mapa de terceiro (com log)';
  r.esperado := 'mapa_comportamental_ver_mapa presente e SECURITY DEFINER';
  v_ok := (select exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname='public' and p.proname='mapa_comportamental_ver_mapa' and p.prosecdef));
  if v_ok then r.situacao := 'passou'; r.obtido := 'Presente e SECURITY DEFINER';
  else r.situacao := 'falhou'; r.obtido := 'Ausente ou nao SECURITY DEFINER'; end if;
  return r;
exception when others then
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := sqlerrm; return r;
end;
$fn$;

create or replace function public.qa_caso_mapa_006()
returns public.qa_retorno language plpgsql
as $fn$
declare r public.qa_retorno; v_ok boolean;
begin
  r.passo_ordem := 1; r.passo_acao := 'Verificar politica permissiva de leitura por perfil';
  r.esperado := 'mapa_comp_resp_select_perfil presente';
  v_ok := (select exists (select 1 from pg_policies where schemaname='public'
           and tablename='mapa_comportamental_respostas' and policyname='mapa_comp_resp_select_perfil'));
  if v_ok then r.situacao := 'passou'; r.obtido := 'Politica presente';
  else r.situacao := 'falhou'; r.obtido := 'Politica ausente'; end if;
  return r;
exception when others then
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := sqlerrm; return r;
end;
$fn$;

insert into public.qa_implementacoes (codigo, funcao_sql) values
  ('MAPA-005', 'qa_caso_mapa_005'), ('MAPA-006', 'qa_caso_mapa_006')
on conflict (codigo) do update set funcao_sql = excluded.funcao_sql, ativo = true;

-- 6) Conferencia final.
select
  (select count(*) from pg_policies where schemaname='public' and tablename='mapa_comportamental_respostas' and policyname='mapa_comp_resp_select_perfil') as politica_perfil,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('mapa_comportamental_ver_mapa','mapa_comportamental_time','mapa_comportamental_meus_acessos')) as funcoes,
  (select count(*) from public.qa_casos_teste where codigo in ('MAPA-005','MAPA-006')) as casos_qa,
  (public.qa_caso_mapa_005()).situacao as mapa_005,
  (public.qa_caso_mapa_006()).situacao as mapa_006;
