-- =====================================================================
-- YOUREYES · SCRIPT DE ENTREGA · Mapa Comportamental (Fatia 2)
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de PRODUCAO.
--
-- Pre-requisito: a Fatia 1 (script_mapa_comportamental_fundacao.sql) ja aplicada.
--
-- O que faz: Governanca (politica/aviso publicaveis, com a trava RF-001),
-- Campanhas, Convites (participacoes) e vinculo da resposta a campanha.
--
-- Seguro:
--   * Roda em UMA transacao; se der erro, desfaz sozinho.
--   * Idempotente. So CRIA coisa nova (tabelas, funcoes, politicas, triggers).
--     Nao altera nem apaga dado existente -> nao precisa de backup previo.
--   * Tabelas criadas por EXECUTE (evita o auto-RLS do editor) e funcoes sem
--     SELECT ... INTO (evita a corrupcao de corpo de funcao no editor).
--
-- Espelha a migration 20260926192209_mapa_comportamental_campanhas.sql.
-- =====================================================================

set lock_timeout = '10s';

-- 1) Tabelas (criadas por EXECUTE).
do $tab$
begin
  if to_regclass('public.mapa_comportamental_politicas') is null then
    execute 'create ' || 'table public.mapa_comportamental_politicas ('
      || 'id uuid primary key default gen_random_uuid(), '
      || 'tenant_id uuid not null references public.tenants(id) on delete cascade, '
      || 'versao int not null, '
      || 'titulo text not null default ''Política de Uso — Mapa Comportamental'', '
      || 'texto_politica text not null, '
      || 'texto_aviso text not null, '
      || 'publicada boolean not null default false, '
      || 'publicada_em timestamptz, '
      || 'publicada_por uuid, '
      || 'publicada_por_nome text, '
      || 'created_at timestamptz not null default now(), '
      || 'updated_at timestamptz not null default now(), '
      || 'constraint uq_mapa_comp_politica_versao unique (tenant_id, versao))';
  end if;

  if to_regclass('public.mapa_comportamental_campanhas') is null then
    execute 'create ' || 'table public.mapa_comportamental_campanhas ('
      || 'id uuid primary key default gen_random_uuid(), '
      || 'tenant_id uuid not null references public.tenants(id) on delete cascade, '
      || 'empresa_id uuid, '
      || 'nome text not null, '
      || 'descricao text, '
      || 'publico jsonb not null default ''{"tipo":"empresa_inteira"}''::jsonb, '
      || 'status text not null default ''rascunho'', '
      || 'data_inicio date, '
      || 'data_fim date, '
      || 'instrumento_versao int not null default 1, '
      || 'politica_id uuid references public.mapa_comportamental_politicas(id), '
      || 'criado_por uuid, '
      || 'criado_por_nome text, '
      || 'created_at timestamptz not null default now(), '
      || 'updated_at timestamptz not null default now(), '
      || 'constraint mapa_comp_camp_status_chk check (status in (''rascunho'',''ativa'',''encerrada'')))';
  end if;

  if to_regclass('public.mapa_comportamental_participacoes') is null then
    execute 'create ' || 'table public.mapa_comportamental_participacoes ('
      || 'id uuid primary key default gen_random_uuid(), '
      || 'tenant_id uuid not null references public.tenants(id) on delete cascade, '
      || 'campanha_id uuid not null references public.mapa_comportamental_campanhas(id) on delete cascade, '
      || 'usuario_id uuid not null, '
      || 'colaborador_nome text, '
      || 'colaborador_cpf text, '
      || 'token text not null default encode(gen_random_bytes(16), ''hex''), '
      || 'status text not null default ''pendente'', '
      || 'respondido_em timestamptz, '
      || 'created_at timestamptz not null default now(), '
      || 'constraint uq_mapa_comp_participacao unique (campanha_id, usuario_id), '
      || 'constraint uq_mapa_comp_participacao_token unique (token), '
      || 'constraint mapa_comp_part_status_chk check (status in (''pendente'',''respondido'')))';
  end if;
end $tab$;

create index if not exists idx_mapa_comp_politicas_tenant on public.mapa_comportamental_politicas(tenant_id, publicada);
create index if not exists idx_mapa_comp_campanhas_tenant_status on public.mapa_comportamental_campanhas(tenant_id, status);
create index if not exists idx_mapa_comp_part_campanha on public.mapa_comportamental_participacoes(campanha_id);
create index if not exists idx_mapa_comp_part_usuario on public.mapa_comportamental_participacoes(tenant_id, usuario_id, status);

-- 2) Trigger RF-001 + updated_at + marcar participacao.
create or replace function public.mapa_comportamental_exige_politica()
returns trigger language plpgsql security definer set search_path to 'public'
as $fn$
begin
  if new.status = 'ativa' then
    if not exists (select 1 from public.mapa_comportamental_politicas p
                   where p.tenant_id = new.tenant_id and p.publicada = true) then
      raise exception 'Publique a política de uso antes de ativar uma campanha do Mapa Comportamental (RF-001).';
    end if;
  end if;
  return new;
end;
$fn$;

drop trigger if exists trg_mapa_comp_exige_politica on public.mapa_comportamental_campanhas;
create trigger trg_mapa_comp_exige_politica
  before insert or update on public.mapa_comportamental_campanhas
  for each row execute function public.mapa_comportamental_exige_politica();

drop trigger if exists trg_mapa_comp_camp_updated_at on public.mapa_comportamental_campanhas;
create trigger trg_mapa_comp_camp_updated_at
  before update on public.mapa_comportamental_campanhas
  for each row execute function public.update_updated_at_column();

drop trigger if exists trg_mapa_comp_pol_updated_at on public.mapa_comportamental_politicas;
create trigger trg_mapa_comp_pol_updated_at
  before update on public.mapa_comportamental_politicas
  for each row execute function public.update_updated_at_column();

create or replace function public.mapa_comportamental_marcar_participacao()
returns trigger language plpgsql security definer set search_path to 'public'
as $fn$
begin
  if new.status = 'concluido' and new.campanha_id is not null and new.usuario_id is not null then
    update public.mapa_comportamental_participacoes
       set status = 'respondido', respondido_em = coalesce(new.concluido_em, now())
     where campanha_id = new.campanha_id and usuario_id = new.usuario_id and status <> 'respondido';
  end if;
  return new;
end;
$fn$;

drop trigger if exists trg_mapa_comp_marcar_participacao on public.mapa_comportamental_respostas;
create trigger trg_mapa_comp_marcar_participacao
  after insert or update on public.mapa_comportamental_respostas
  for each row execute function public.mapa_comportamental_marcar_participacao();

-- 3) RLS
alter table public.mapa_comportamental_politicas     enable row level security;
alter table public.mapa_comportamental_campanhas     enable row level security;
alter table public.mapa_comportamental_participacoes enable row level security;

do $pol$
begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='mapa_comportamental_politicas' and policyname='mapa_comp_pol_select') then
    create policy mapa_comp_pol_select on public.mapa_comportamental_politicas
      for select to authenticated using (tenant_id = public.get_user_tenant_id());
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='mapa_comportamental_politicas' and policyname='mapa_comp_pol_manage') then
    create policy mapa_comp_pol_manage on public.mapa_comportamental_politicas
      for all to authenticated
      using (tenant_id = public.get_user_tenant_id() and public.has_minimum_role(auth.uid(),'manager'::public.app_role))
      with check (tenant_id = public.get_user_tenant_id() and public.has_minimum_role(auth.uid(),'manager'::public.app_role));
  end if;

  if not exists (select 1 from pg_policies where schemaname='public' and tablename='mapa_comportamental_campanhas' and policyname='mapa_comp_camp_select') then
    create policy mapa_comp_camp_select on public.mapa_comportamental_campanhas
      for select to authenticated using (tenant_id = public.get_user_tenant_id());
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='mapa_comportamental_campanhas' and policyname='mapa_comp_camp_manage') then
    create policy mapa_comp_camp_manage on public.mapa_comportamental_campanhas
      for all to authenticated
      using (tenant_id = public.get_user_tenant_id() and public.has_minimum_role(auth.uid(),'manager'::public.app_role))
      with check (tenant_id = public.get_user_tenant_id() and public.has_minimum_role(auth.uid(),'manager'::public.app_role));
  end if;

  if not exists (select 1 from pg_policies where schemaname='public' and tablename='mapa_comportamental_participacoes' and policyname='mapa_comp_part_select') then
    create policy mapa_comp_part_select on public.mapa_comportamental_participacoes
      for select to authenticated
      using (
        public.is_superadmin(auth.uid())
        or public.perfil_permite_modulo(tenant_id, variadic array['mapa_comportamental'::text])
        or exists (select 1 from public.usuarios_base ub where ub.auth_user_id = auth.uid() and ub.id = usuario_id));
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='mapa_comportamental_participacoes' and policyname='mapa_comp_part_manage') then
    create policy mapa_comp_part_manage on public.mapa_comportamental_participacoes
      for all to authenticated
      using (tenant_id = public.get_user_tenant_id() and public.has_minimum_role(auth.uid(),'manager'::public.app_role))
      with check (tenant_id = public.get_user_tenant_id() and public.has_minimum_role(auth.uid(),'manager'::public.app_role));
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='mapa_comportamental_participacoes' and policyname='perfil_restringe_leitura_mapa_comportamental_participacoes') then
    create policy perfil_restringe_leitura_mapa_comportamental_participacoes
      on public.mapa_comportamental_participacoes as restrictive for select to authenticated
      using (
        public.is_superadmin(auth.uid())
        or public.perfil_permite_modulo(tenant_id, variadic array['mapa_comportamental'::text])
        or exists (select 1 from public.usuarios_base ub where ub.auth_user_id = auth.uid() and ub.id = usuario_id));
  end if;
end $pol$;

-- 4) RPCs (sem SELECT ... INTO).
create or replace function public.mapa_comportamental_gerar_convites(p_campanha_id uuid)
returns integer language plpgsql security definer set search_path to 'public'
as $fn$
declare
  v_tenant uuid;
  v_publico jsonb;
  v_tipo text;
  v_total int;
begin
  v_tenant  := (select tenant_id from public.mapa_comportamental_campanhas where id = p_campanha_id);
  v_publico := (select publico   from public.mapa_comportamental_campanhas where id = p_campanha_id);
  if v_tenant is null then raise exception 'Campanha não encontrada.'; end if;
  if not public.perfil_permite_modulo(v_tenant, variadic array['mapa_comportamental'::text]) then
    raise exception 'Sem permissão para gerar convites.';
  end if;

  v_tipo := coalesce(v_publico->>'tipo', 'empresa_inteira');

  if v_tipo = 'lista' then
    insert into public.mapa_comportamental_participacoes (tenant_id, campanha_id, usuario_id, colaborador_nome, colaborador_cpf)
    select v_tenant, p_campanha_id, ub.id, ub.nome_completo, nullif(regexp_replace(coalesce(ub.cpf,''),'[^0-9]','','g'),'')
    from public.usuarios_base ub
    where ub.tenant_id = v_tenant
      and ub.id::text in (select jsonb_array_elements_text(coalesce(v_publico->'usuario_ids','[]'::jsonb)))
    on conflict (campanha_id, usuario_id) do nothing;
  else
    insert into public.mapa_comportamental_participacoes (tenant_id, campanha_id, usuario_id, colaborador_nome, colaborador_cpf)
    select v_tenant, p_campanha_id, ub.id, ub.nome_completo, nullif(regexp_replace(coalesce(ub.cpf,''),'[^0-9]','','g'),'')
    from public.usuarios_base ub
    where ub.tenant_id = v_tenant and ub.status::text = 'ativo'
    on conflict (campanha_id, usuario_id) do nothing;
  end if;

  v_total := (select count(*) from public.mapa_comportamental_participacoes where campanha_id = p_campanha_id);
  return v_total;
end;
$fn$;
revoke execute on function public.mapa_comportamental_gerar_convites(uuid) from public, anon;
grant  execute on function public.mapa_comportamental_gerar_convites(uuid) to authenticated;

create or replace function public.mapa_comportamental_cobertura(p_campanha_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public'
as $fn$
declare v_tenant uuid; v_conv int; v_resp int;
begin
  v_tenant := (select tenant_id from public.mapa_comportamental_campanhas where id = p_campanha_id);
  if v_tenant is null or not public.perfil_permite_modulo(v_tenant, variadic array['mapa_comportamental'::text]) then
    return jsonb_build_object('convidados', 0, 'respondidos', 0, 'pct', 0);
  end if;
  v_conv := (select count(*) from public.mapa_comportamental_participacoes where campanha_id = p_campanha_id);
  v_resp := (select count(*) from public.mapa_comportamental_participacoes where campanha_id = p_campanha_id and status = 'respondido');
  return jsonb_build_object('convidados', v_conv, 'respondidos', v_resp,
    'pct', case when v_conv > 0 then round((v_resp::numeric / v_conv) * 100, 1) else 0 end);
end;
$fn$;
revoke execute on function public.mapa_comportamental_cobertura(uuid) from public, anon;
grant  execute on function public.mapa_comportamental_cobertura(uuid) to authenticated;

create or replace function public.mapa_comportamental_minha_campanha_pendente()
returns jsonb language plpgsql stable security definer set search_path to 'public'
as $fn$
declare v_uid uuid := auth.uid(); v_res jsonb;
begin
  v_res := (
    select jsonb_build_object('campanha_id', c.id, 'nome', c.nome, 'data_fim', c.data_fim, 'participacao_id', pa.id)
    from public.mapa_comportamental_participacoes pa
    join public.mapa_comportamental_campanhas c on c.id = pa.campanha_id
    join public.usuarios_base ub on ub.id = pa.usuario_id
    where ub.auth_user_id = v_uid and pa.status = 'pendente' and c.status = 'ativa'
    order by c.data_fim nulls last, c.created_at limit 1);
  return v_res;
end;
$fn$;
revoke execute on function public.mapa_comportamental_minha_campanha_pendente() from public, anon;
grant  execute on function public.mapa_comportamental_minha_campanha_pendente() to authenticated;

-- 5) QA — casos MAPA-003/004.
do $doc$
declare v_mod uuid;
begin
  v_mod := (select id from public.qa_modulos where path = 'desenvolvimento-performance/mapa-comportamental');
  if v_mod is null then raise notice 'Modulo QA ausente — pulei os casos.'; return; end if;
  insert into public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  values
    (v_mod, 'MAPA-003', 'Trava RF-001: ativar campanha exige politica publicada', 'negativo', 'alta', 'aprovado', 'api',
     'Sem politica publicada, a campanha nao pode ser ativada.', 'Fatia 2 aplicada.',
     '[{"ordem":1,"acao":"Verificar trigger trg_mapa_comp_exige_politica","resultado_esperado":"presente"}]'::jsonb,
     'A trava RF-001 existe.', 'Cobre RF-001.'),
    (v_mod, 'MAPA-004', 'Participacoes protegidas por politica RESTRICTIVE de perfil', 'feliz', 'critica', 'aprovado', 'api',
     'PERFIL-003: participacoes carregam nome/cpf.', 'Fatia 2 aplicada.',
     '[{"ordem":1,"acao":"Verificar pg_policies em participacoes","resultado_esperado":"RESTRICTIVE presente"}]'::jsonb,
     'A politica RESTRICTIVE existe.', 'Cobre RN-002/RN-003.')
  on conflict (codigo) do nothing;
  raise notice 'OK: casos MAPA-003/004 documentados.';
end $doc$;

create or replace function public.qa_caso_mapa_003()
returns public.qa_retorno language plpgsql
as $fn$
declare r public.qa_retorno; v_ok boolean;
begin
  r.passo_ordem := 1; r.passo_acao := 'Verificar trigger RF-001'; r.esperado := 'trg_mapa_comp_exige_politica presente';
  v_ok := (select exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
           where c.relname = 'mapa_comportamental_campanhas' and t.tgname = 'trg_mapa_comp_exige_politica' and not t.tgisinternal));
  if v_ok then r.situacao := 'passou'; r.obtido := 'Trigger RF-001 presente';
  else r.situacao := 'falhou'; r.obtido := 'Trigger RF-001 ausente'; end if;
  return r;
exception when others then
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := sqlerrm; return r;
end;
$fn$;

create or replace function public.qa_caso_mapa_004()
returns public.qa_retorno language plpgsql
as $fn$
declare r public.qa_retorno; v_ok boolean;
begin
  r.passo_ordem := 1; r.passo_acao := 'Verificar politica RESTRICTIVE nas participacoes';
  r.esperado := 'perfil_restringe_leitura_mapa_comportamental_participacoes RESTRICTIVE';
  v_ok := (select exists (select 1 from pg_policies where schemaname='public'
           and tablename='mapa_comportamental_participacoes'
           and policyname='perfil_restringe_leitura_mapa_comportamental_participacoes' and permissive='RESTRICTIVE'));
  if v_ok then r.situacao := 'passou'; r.obtido := 'RESTRICTIVE presente';
  else r.situacao := 'falhou'; r.obtido := 'RESTRICTIVE ausente'; end if;
  return r;
exception when others then
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := sqlerrm; return r;
end;
$fn$;

insert into public.qa_implementacoes (codigo, funcao_sql) values
  ('MAPA-003', 'qa_caso_mapa_003'), ('MAPA-004', 'qa_caso_mapa_004')
on conflict (codigo) do update set funcao_sql = excluded.funcao_sql, ativo = true;

-- 6) Conferencia final.
select
  (select count(*) from pg_policies where schemaname='public' and tablename='mapa_comportamental_campanhas') as pol_campanhas,
  (select count(*) from pg_policies where schemaname='public' and tablename='mapa_comportamental_participacoes' and permissive='RESTRICTIVE') as restritiva_participacoes,
  (select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relname='mapa_comportamental_campanhas' and t.tgname='trg_mapa_comp_exige_politica') as trava_rf001,
  (select count(*) from public.qa_casos_teste where codigo in ('MAPA-003','MAPA-004')) as casos_qa,
  (public.qa_caso_mapa_003()).situacao as mapa_003,
  (public.qa_caso_mapa_004()).situacao as mapa_004;
