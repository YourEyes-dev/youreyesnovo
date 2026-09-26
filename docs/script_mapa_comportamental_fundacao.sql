-- =====================================================================
-- YOUREYES · SCRIPT DE ENTREGA · Mapa Comportamental (Fatia 1 do MVP)
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de PRODUCAO.
--
-- O que faz: cria a fundacao do modulo Mapa Comportamental (bloco
-- Desenvolvimento & Performance): instrumento versionado, tabela de respostas
-- com resultado apurado, log de acesso, RLS (leitura restrita ao titular +
-- trava RESTRICTIVE de perfil), painel agregado com supressao por baixo N, e a
-- documentacao de QA (modulo + casos MAPA-001/002).
--
-- Seguro:
--   * Roda em UMA transacao; se der erro, desfaz sozinho.
--   * Idempotente: rodar duas vezes nao quebra nem duplica.
--   * So CRIA coisa nova (tabelas, funcoes, politicas, seed). Nao altera nem
--     apaga dado existente, entao nao precisa de backup previo.
--   * As tabelas sao criadas por EXECUTE (string quebrada) para NAO acionar o
--     auxiliar "auto-RLS" do editor, e as funcoes nao usam SELECT ... INTO —
--     as duas pegadinhas conhecidas do SQL Editor.
--
-- Espelha as migrations 20260926011539 e 20260926011805.
-- =====================================================================

set lock_timeout = '10s';

-- 1) Tabelas (criadas por EXECUTE; a sequencia contigua do comando de criacao
--    de tabela nao existe no texto, entao o auto-RLS do editor nao dispara).
do $tab$
begin
  if to_regclass('public.mapa_comportamental_instrumentos') is null then
    execute 'create ' || 'table public.mapa_comportamental_instrumentos ('
      || 'id uuid primary key default gen_random_uuid(), '
      || 'versao int not null unique, '
      || 'algoritmo_versao text not null, '
      || 'titulo text not null default ''Mapa Comportamental'', '
      || 'total_itens int not null default 28, '
      || 'definicao jsonb not null default ''{}''::jsonb, '
      || 'vigente boolean not null default true, '
      || 'created_at timestamptz not null default now())';
  end if;

  if to_regclass('public.mapa_comportamental_respostas') is null then
    execute 'create ' || 'table public.mapa_comportamental_respostas ('
      || 'id uuid primary key default gen_random_uuid(), '
      || 'tenant_id uuid not null references public.tenants(id) on delete cascade, '
      || 'empresa_id uuid, '
      || 'auth_user_id uuid not null, '
      || 'usuario_id uuid, '
      || 'colaborador_nome text, '
      || 'colaborador_cpf text, '
      || 'campanha_id uuid, '
      || 'instrumento_versao int not null default 1, '
      || 'algoritmo_versao text not null default ''v1'', '
      || 'status text not null default ''rascunho'', '
      || 'respostas jsonb not null default ''{}''::jsonb, '
      || 'resultado jsonb, '
      || 'arquetipo text, '
      || 'indice_consistencia int, '
      || 'confiabilidade text, '
      || 'aviso_versao text, '
      || 'aviso_aceite_em timestamptz, '
      || 'tempo_total_segundos int, '
      || 'tempo_por_item jsonb, '
      || 'concluido_em timestamptz, '
      || 'vence_em date, '
      || 'created_at timestamptz not null default now(), '
      || 'updated_at timestamptz not null default now(), '
      || 'constraint mapa_comp_status_chk check (status in (''rascunho'',''concluido'')), '
      || 'constraint mapa_comp_confiab_chk check (confiabilidade is null or confiabilidade in (''alta'',''baixa'')))';
  end if;

  if to_regclass('public.mapa_comportamental_acessos') is null then
    execute 'create ' || 'table public.mapa_comportamental_acessos ('
      || 'id uuid primary key default gen_random_uuid(), '
      || 'tenant_id uuid not null references public.tenants(id) on delete cascade, '
      || 'mapa_id uuid not null references public.mapa_comportamental_respostas(id) on delete cascade, '
      || 'acessado_por uuid not null, '
      || 'acessado_por_nome text, '
      || 'acessado_em timestamptz not null default now())';
  end if;
end $tab$;

-- Indices (nao acionam o auto-RLS).
create index if not exists idx_mapa_comp_resp_tenant_user
  on public.mapa_comportamental_respostas(tenant_id, auth_user_id);
create index if not exists idx_mapa_comp_resp_tenant_status
  on public.mapa_comportamental_respostas(tenant_id, status);
create unique index if not exists uq_mapa_comp_rascunho_autoaplicacao
  on public.mapa_comportamental_respostas(tenant_id, auth_user_id)
  where status = 'rascunho' and campanha_id is null;
create index if not exists idx_mapa_comp_acessos_mapa
  on public.mapa_comportamental_acessos(mapa_id);

-- 2) Seed do instrumento v1 (metainformacao; itens e algoritmo vivem no codigo).
insert into public.mapa_comportamental_instrumentos (versao, algoritmo_versao, total_itens, vigente, definicao)
values (
  1, 'v1', 28, true,
  jsonb_build_object(
    'versao', 1, 'algoritmo_versao', 'v1', 'total_itens', 28,
    'limiar_perfil_misto', 2, 'tempo_minimo_segundos', 60,
    'eixos', jsonb_build_object(
      'foco','A=Pessoas / B=Tarefas', 'ritmo','A=Acelerado / B=Ponderado',
      'modo','A=Constante / B=Cadenciado', 'motor','1=Racional / 2=Relacional / 3=Pragmatico'),
    'pares_controle', jsonb_build_array(
      jsonb_build_array(1,25), jsonb_build_array(7,26),
      jsonb_build_array(13,27), jsonb_build_array(19,28)),
    'fonte','src/data/instrumentos/mapaComportamental.ts'))
on conflict (versao) do nothing;

-- 3) Trigger de identidade (carimba tenant/usuario/nome/cpf; sem SELECT ... INTO).
create or replace function public.mapa_comportamental_carimbar_identidade()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_uid uuid := auth.uid();
  v_usuario_id uuid;
begin
  new.auth_user_id := v_uid;
  new.tenant_id := coalesce(public.get_user_tenant_id(), new.tenant_id);
  v_usuario_id := (select ub.id from public.usuarios_base ub where ub.auth_user_id = v_uid limit 1);
  if v_usuario_id is not null then
    new.usuario_id := v_usuario_id;
    new.colaborador_nome := (select ub.nome_completo from public.usuarios_base ub where ub.id = v_usuario_id);
    new.colaborador_cpf := nullif((select regexp_replace(coalesce(ub.cpf,''),'[^0-9]','','g')
                                     from public.usuarios_base ub where ub.id = v_usuario_id), '');
  end if;
  return new;
end;
$fn$;

drop trigger if exists trg_mapa_comp_carimbar_identidade on public.mapa_comportamental_respostas;
create trigger trg_mapa_comp_carimbar_identidade
  before insert on public.mapa_comportamental_respostas
  for each row execute function public.mapa_comportamental_carimbar_identidade();

drop trigger if exists trg_mapa_comp_updated_at on public.mapa_comportamental_respostas;
create trigger trg_mapa_comp_updated_at
  before update on public.mapa_comportamental_respostas
  for each row execute function public.update_updated_at_column();

-- 4) RLS
alter table public.mapa_comportamental_instrumentos enable row level security;
alter table public.mapa_comportamental_respostas    enable row level security;
alter table public.mapa_comportamental_acessos      enable row level security;

do $pol$
begin
  if not exists (select 1 from pg_policies where schemaname='public'
      and tablename='mapa_comportamental_instrumentos' and policyname='mapa_comp_instr_select') then
    create policy mapa_comp_instr_select on public.mapa_comportamental_instrumentos
      for select to authenticated using (true);
  end if;

  if not exists (select 1 from pg_policies where schemaname='public'
      and tablename='mapa_comportamental_respostas' and policyname='mapa_comp_resp_select_titular') then
    create policy mapa_comp_resp_select_titular on public.mapa_comportamental_respostas
      for select to authenticated
      using (auth_user_id = auth.uid() or public.is_superadmin(auth.uid()));
  end if;

  if not exists (select 1 from pg_policies where schemaname='public'
      and tablename='mapa_comportamental_respostas' and policyname='mapa_comp_resp_insert_titular') then
    create policy mapa_comp_resp_insert_titular on public.mapa_comportamental_respostas
      for insert to authenticated
      with check (auth_user_id = auth.uid() and tenant_id = public.get_user_tenant_id());
  end if;

  if not exists (select 1 from pg_policies where schemaname='public'
      and tablename='mapa_comportamental_respostas' and policyname='mapa_comp_resp_update_titular') then
    create policy mapa_comp_resp_update_titular on public.mapa_comportamental_respostas
      for update to authenticated
      using (auth_user_id = auth.uid())
      with check (auth_user_id = auth.uid());
  end if;

  if not exists (select 1 from pg_policies where schemaname='public'
      and tablename='mapa_comportamental_respostas' and policyname='perfil_restringe_leitura_mapa_comportamental_respostas') then
    create policy perfil_restringe_leitura_mapa_comportamental_respostas
      on public.mapa_comportamental_respostas
      as restrictive for select to authenticated
      using (
        auth_user_id = auth.uid()
        or public.is_superadmin(auth.uid())
        or public.perfil_permite_modulo(tenant_id, variadic array['mapa_comportamental'::text]));
  end if;

  if not exists (select 1 from pg_policies where schemaname='public'
      and tablename='mapa_comportamental_acessos' and policyname='mapa_comp_acessos_select') then
    create policy mapa_comp_acessos_select on public.mapa_comportamental_acessos
      for select to authenticated
      using (
        public.is_superadmin(auth.uid())
        or public.perfil_permite_modulo(tenant_id, variadic array['mapa_comportamental'::text])
        or exists (select 1 from public.mapa_comportamental_respostas r
                   where r.id = mapa_id and r.auth_user_id = auth.uid()));
  end if;

  if not exists (select 1 from pg_policies where schemaname='public'
      and tablename='mapa_comportamental_acessos' and policyname='mapa_comp_acessos_insert') then
    create policy mapa_comp_acessos_insert on public.mapa_comportamental_acessos
      for insert to authenticated
      with check (acessado_por = auth.uid() and tenant_id = public.get_user_tenant_id());
  end if;
end $pol$;

-- 5) Painel agregado (RH/gestor) com supressao por baixo N; sem SELECT ... INTO.
create or replace function public.mapa_comportamental_painel(p_empresa_id uuid default null)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $fn$
declare
  v_tenant uuid := public.get_user_tenant_id();
  v_min int := 5;
  v_total int;
  v_validos int;
  v_baixa int;
  v_cons numeric;
  v_dist jsonb;
begin
  if v_tenant is null
     or not public.perfil_permite_modulo(v_tenant, variadic array['mapa_comportamental'::text]) then
    return jsonb_build_object('suprimido', true, 'total_concluidos', 0, 'minimo_respondentes', v_min);
  end if;

  v_total := (select count(*) from public.mapa_comportamental_respostas
              where tenant_id = v_tenant and status = 'concluido'
                and (p_empresa_id is null or empresa_id = p_empresa_id));
  v_validos := (select count(*) from public.mapa_comportamental_respostas
                where tenant_id = v_tenant and status = 'concluido' and confiabilidade = 'alta'
                  and (p_empresa_id is null or empresa_id = p_empresa_id));
  v_baixa := (select count(*) from public.mapa_comportamental_respostas
              where tenant_id = v_tenant and status = 'concluido' and confiabilidade = 'baixa'
                and (p_empresa_id is null or empresa_id = p_empresa_id));

  if v_validos < v_min then
    return jsonb_build_object('suprimido', true, 'total_concluidos', v_total,
                              'minimo_respondentes', v_min, 'confiabilidade_baixa', v_baixa);
  end if;

  v_cons := (select round(avg(indice_consistencia)::numeric, 2)
             from public.mapa_comportamental_respostas
             where tenant_id = v_tenant and status = 'concluido' and confiabilidade = 'alta'
               and (p_empresa_id is null or empresa_id = p_empresa_id));

  v_dist := (select coalesce(jsonb_object_agg(arq, qt), '{}'::jsonb) from (
               select coalesce(arquetipo, 'indefinido') as arq, count(*) as qt
               from public.mapa_comportamental_respostas
               where tenant_id = v_tenant and status = 'concluido' and confiabilidade = 'alta'
                 and (p_empresa_id is null or empresa_id = p_empresa_id)
               group by 1) d);

  return jsonb_build_object('suprimido', false, 'total_concluidos', v_total,
                            'minimo_respondentes', v_min, 'distribuicao_arquetipos', v_dist,
                            'consistencia_media', v_cons, 'confiabilidade_baixa', v_baixa);
end;
$fn$;

revoke execute on function public.mapa_comportamental_painel(uuid) from public, anon;
grant  execute on function public.mapa_comportamental_painel(uuid) to authenticated;

-- 6) QA — modulo + casos MAPA-001/002 (documentacao) e rotinas (sem SELECT ... INTO).
do $doc$
declare
  v_parent uuid;
  v_mod uuid;
begin
  v_parent := (select id from public.qa_modulos where path = 'desenvolvimento-performance');
  insert into public.qa_modulos (parent_id, label, path, ordem)
  values (v_parent, 'Mapa Comportamental', 'desenvolvimento-performance/mapa-comportamental', 50)
  on conflict (path) do nothing;

  v_mod := (select id from public.qa_modulos where path = 'desenvolvimento-performance/mapa-comportamental');

  insert into public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  values
    (v_mod, 'MAPA-001', 'Instrumento vigente v1 com 28 itens', 'feliz', 'alta', 'aprovado', 'api',
     'Garante que o instrumento de referencia foi semeado e esta vigente.',
     'Script de fundacao aplicado.',
     '[{"ordem":1,"acao":"Consultar instrumento vigente","resultado_esperado":"versao=1, total_itens=28, vigente=true"}]'::jsonb,
     'Existe exatamente um instrumento vigente v1 com 28 itens.', 'Cobre RF-016.'),
    (v_mod, 'MAPA-002', 'Respostas protegidas por politica RESTRICTIVE de perfil', 'feliz', 'critica', 'aprovado', 'api',
     'PERFIL-003: tabela com dado pessoal precisa da politica RESTRICTIVE de perfil.',
     'Script de fundacao aplicado.',
     '[{"ordem":1,"acao":"Verificar pg_policies","resultado_esperado":"existe perfil_restringe_leitura_mapa_comportamental_respostas RESTRICTIVE"}]'::jsonb,
     'A politica RESTRICTIVE de perfil existe na tabela de respostas.', 'Cobre RN-002/RN-003.')
  on conflict (codigo) do nothing;

  raise notice 'OK: modulo QA + casos MAPA-001/002 documentados.';
end $doc$;

create or replace function public.qa_caso_mapa_001()
returns public.qa_retorno
language plpgsql
as $fn$
declare
  r public.qa_retorno;
  v_qt int;
begin
  r.passo_ordem := 1;
  r.passo_acao  := 'Consultar instrumento vigente v1 (somente leitura)';
  r.esperado    := 'Um instrumento vigente com versao=1 e total_itens=28';
  v_qt := (select count(*) from public.mapa_comportamental_instrumentos
           where versao = 1 and vigente = true and total_itens = 28);
  if v_qt = 1 then
    r.situacao := 'passou';
    r.obtido := 'Instrumento v1 vigente com 28 itens encontrado';
  else
    r.situacao := 'falhou';
    r.obtido := format('Encontrados %s instrumentos v1 vigentes com 28 itens (esperado 1)', v_qt);
  end if;
  return r;
exception when others then
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := sqlerrm; return r;
end;
$fn$;

create or replace function public.qa_caso_mapa_002()
returns public.qa_retorno
language plpgsql
as $fn$
declare
  r public.qa_retorno;
  v_ok boolean;
begin
  r.passo_ordem := 1;
  r.passo_acao  := 'Verificar politica RESTRICTIVE de perfil na tabela de respostas';
  r.esperado    := 'perfil_restringe_leitura_mapa_comportamental_respostas existe como RESTRICTIVE';
  v_ok := (select exists (select 1 from pg_policies
             where schemaname='public' and tablename='mapa_comportamental_respostas'
               and policyname='perfil_restringe_leitura_mapa_comportamental_respostas'
               and permissive='RESTRICTIVE'));
  if v_ok then
    r.situacao := 'passou'; r.obtido := 'Politica RESTRICTIVE de perfil presente';
  else
    r.situacao := 'falhou'; r.obtido := 'Politica RESTRICTIVE de perfil ausente';
  end if;
  return r;
exception when others then
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := sqlerrm; return r;
end;
$fn$;

insert into public.qa_implementacoes (codigo, funcao_sql) values
  ('MAPA-001', 'qa_caso_mapa_001'),
  ('MAPA-002', 'qa_caso_mapa_002')
on conflict (codigo) do update set funcao_sql = excluded.funcao_sql, ativo = true;

-- 7) Conferencia final (o editor mostra so o ultimo resultado).
select
  (select count(*) from public.mapa_comportamental_instrumentos where vigente and versao=1 and total_itens=28) as instrumentos_v1,
  (select count(*) from pg_policies where schemaname='public' and tablename='mapa_comportamental_respostas') as politicas_respostas,
  (select count(*) from pg_policies where schemaname='public' and tablename='mapa_comportamental_respostas' and permissive='RESTRICTIVE') as politicas_restritivas,
  (select count(*) from public.qa_casos_teste where codigo in ('MAPA-001','MAPA-002')) as casos_qa,
  (public.qa_caso_mapa_001()).situacao as mapa_001,
  (public.qa_caso_mapa_002()).situacao as mapa_002;
