-- =====================================================================
-- QA — MAPA COMPORTAMENTAL · PLANO / COTA / ADD-ON (nivel api, read-only)
--
-- Cobre a Etapa 2: documenta e implementa no motor de QA os casos da
-- familia planos/cota/add-on do Mapa Comportamental (antes sem cobertura).
--
-- Tambem faz um refino: extrai a "chave da pessoa" (CPF normalizado ou, na
-- autoaplicacao sem CPF, o usuario) para uma funcao unica, usada TANTO pelo
-- trigger de bloqueio quanto pela contagem do Meu Plano. Assim "refazer o
-- mapa da mesma pessoa nao consome nova analise" (contestacao/RF-014) fica com
-- fonte unica e testavel.
--
-- Idempotente. Nao cria tabela (nao aciona auto-RLS do editor).
-- =====================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- 1) Chave da pessoa (fonte unica): CPF so-digitos; se vazio, o usuario.
--    Duas linhas da mesma pessoa (mesmo CPF, com ou sem pontuacao) caem na
--    mesma chave -> contam como UMA vida.
-- ---------------------------------------------------------------------
create or replace function public.mapa_comportamental_chave_pessoa(p_cpf text, p_user uuid)
returns text
language sql
immutable
as $chave$
  select coalesce(nullif(regexp_replace(coalesce(p_cpf, ''), '[^0-9]', '', 'g'), ''), p_user::text)
$chave$;

-- ---------------------------------------------------------------------
-- 2) Trigger de bloqueio: passa a usar a chave unica (mesma semantica,
--    agora centralizada). Bloqueia iniciar mapa de pessoa nova acima da
--    cota; isenta quem ja foi mapeado (re-mapa/contestacao); nunca mexe
--    no que ja existe.
-- ---------------------------------------------------------------------
create or replace function public.mapa_comportamental_checar_cota()
returns trigger
language plpgsql
security definer
set search_path = public
as $mapa_cota$
declare
  v_tenant uuid := NEW.tenant_id;
  v_key    text := public.mapa_comportamental_chave_pessoa(NEW.colaborador_cpf, NEW.auth_user_id);
  v_res    record;
  v_used   bigint;
begin
  if v_tenant is null then
    return NEW;
  end if;

  select limit_value, is_unlimited into v_res
  from public.entitlement_resolve(v_tenant, 'limit.mapa_comportamental');
  if v_res.is_unlimited or v_res.limit_value is null then
    return NEW;
  end if;

  -- Pessoa ja mapeada (mesma chave) nao consome cota nova: re-mapa passa.
  if v_key is not null and exists (
    select 1 from public.mapa_comportamental_respostas r
    where r.tenant_id = v_tenant and r.status = 'concluido'
      and public.mapa_comportamental_chave_pessoa(r.colaborador_cpf, r.auth_user_id) = v_key
  ) then
    return NEW;
  end if;

  v_used := (
    select count(distinct public.mapa_comportamental_chave_pessoa(r.colaborador_cpf, r.auth_user_id))
    from public.mapa_comportamental_respostas r
    where r.tenant_id = v_tenant and r.status = 'concluido'
  );

  if v_used >= v_res.limit_value then
    raise exception 'Cota de mapas comportamentais atingida (% de %). Contrate mais análises em Meu Plano.',
      v_used, v_res.limit_value using errcode = 'check_violation';
  end if;

  return NEW;
end $mapa_cota$;

-- ---------------------------------------------------------------------
-- 3) entitlement_my_plan(): a contagem de mapas usa a MESMA chave unica.
-- ---------------------------------------------------------------------
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
  v_mapas  record;
  v_used   bigint;
  v_limit  bigint;
  v_unl    boolean;
  v_mapas_used  bigint;
  v_mapas_limit bigint;
  v_mapas_unl   boolean;
  v_base_cents   integer;
  v_addons_cents integer;
begin
  if v_tenant is null then
    return null;
  end if;

  select p.id as plan_id, p.code, p.name, p.is_public into v_plan
  from subscriptions s join plans p on p.id = s.plan_id
  where s.tenant_id = v_tenant;

  v_used := (select count(*) from admissoes where tenant_id = v_tenant and status = 'concluido');

  select limit_value, is_unlimited into v_vidas
  from entitlement_resolve(v_tenant, 'limit.vidas');
  v_limit := v_vidas.limit_value;
  v_unl   := coalesce(v_vidas.is_unlimited, false);

  v_mapas_used := (
    select count(distinct public.mapa_comportamental_chave_pessoa(r.colaborador_cpf, r.auth_user_id))
    from mapa_comportamental_respostas r
    where r.tenant_id = v_tenant and r.status = 'concluido'
  );
  select limit_value, is_unlimited into v_mapas
  from entitlement_resolve(v_tenant, 'limit.mapa_comportamental');
  v_mapas_limit := v_mapas.limit_value;
  v_mapas_unl   := coalesce(v_mapas.is_unlimited, false);

  v_base_cents := (select pp.amount_cents from plan_prices pp
                   where pp.plan_id = v_plan.plan_id and pp.period = 'monthly' and pp.is_active
                   limit 1);
  v_addons_cents := coalesce((
    select sum(case when sa.kind = 'life' then sa.quantity * sa.unit_price_cents
                    when sa.kind = 'module' then sa.unit_price_cents
                    else 0 end)
    from subscription_addons sa
    where sa.tenant_id = v_tenant and sa.ativo
  ), 0);

  return jsonb_build_object(
    'plano',
      case when v_plan.code is null then null
      else jsonb_build_object('code', v_plan.code, 'name', v_plan.name, 'is_public', v_plan.is_public)
      end,
    'vidas', jsonb_build_object(
      'used', v_used,
      'limit', v_limit,
      'is_unlimited', v_unl,
      'remaining', case when v_unl or v_limit is null then null else greatest(v_limit - v_used, 0) end,
      'percent',   case when v_unl or v_limit is null or v_limit = 0 then null
                        else least(round(v_used::numeric * 100 / v_limit)::int, 100) end
    ),
    'mapas', jsonb_build_object(
      'used', v_mapas_used,
      'limit', v_mapas_limit,
      'is_unlimited', v_mapas_unl,
      'remaining', case when v_mapas_unl or v_mapas_limit is null then null else greatest(v_mapas_limit - v_mapas_used, 0) end,
      'percent',   case when v_mapas_unl or v_mapas_limit is null or v_mapas_limit = 0 then null
                        else least(round(v_mapas_used::numeric * 100 / v_mapas_limit)::int, 100) end
    ),
    'modulos', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'key', f.key, 'name', f.name, 'category', f.category,
               'disponivel', public.tenant_has_feature(v_tenant, f.key)
             ) order by f.category nulls last, f.name), '[]'::jsonb)
      from features f where f.is_active and f.kind = 'boolean'
    ),
    'precos', coalesce((
      select jsonb_object_agg(ap.feature_key, ap.unit_price_cents)
      from addon_prices ap where ap.is_active and ap.unit_price_cents > 0
    ), '{}'::jsonb),
    'addons', coalesce((
      select jsonb_agg(jsonb_build_object(
               'feature_key', sa.feature_key, 'name', f.name, 'kind', sa.kind,
               'quantity', sa.quantity, 'unit_price_cents', sa.unit_price_cents
             ) order by sa.kind, f.name)
      from subscription_addons sa join features f on f.key = sa.feature_key
      where sa.tenant_id = v_tenant and sa.ativo and sa.kind in ('module', 'life')
    ), '[]'::jsonb),
    'valores', jsonb_build_object(
      'base_cents', v_base_cents,
      'addons_cents', v_addons_cents,
      'total_cents', case when v_base_cents is null then null else v_base_cents + v_addons_cents end
    )
  );
end $entitlement_my_plan$;

grant execute on function public.entitlement_my_plan() to authenticated;

-- ---------------------------------------------------------------------
-- 4) Documentacao dos casos (nivel api) sob o modulo ja existente.
-- ---------------------------------------------------------------------
DO $doc$
DECLARE v_mod uuid;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos
   WHERE path = 'desenvolvimento-performance/mapa-comportamental';
  IF v_mod IS NULL THEN
    RAISE NOTICE 'modulo QA mapa-comportamental ausente; casos de plano nao documentados';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
    (v_mod, 'MAPA-PLANO-001', 'Modulo incluido a partir do Performance (tier>=3)', 'feliz', 'alta', 'aprovado', 'api',
     'O modulo mod.mapa_comportamental esta na matriz dos planos tier>=3 e ausente em Starter/Essential.',
     'Migration de plano/cota aplicada.',
     '[{"ordem":1,"acao":"Consultar plan_entitlements de mod.mapa_comportamental por plano","resultado_esperado":"presente em performance/governanca/enterprise e internos; ausente em starter/essential"}]'::jsonb,
     'Performance para cima tem o modulo; Starter e Essential nao.',
     'Posicionamento comercial (add-on nos planos baixos).'),
    (v_mod, 'MAPA-PLANO-002', 'Cota de analises espelha o teto de vidas', 'feliz', 'alta', 'aprovado', 'api',
     'limit.mapa_comportamental semeado 20/80/200/500 e ilimitado no Enterprise/internos.',
     'Migration de plano/cota aplicada.',
     '[{"ordem":1,"acao":"Consultar limit_value/is_unlimited de limit.mapa_comportamental por plano","resultado_esperado":"starter=20, essential=80, performance=200, governanca=500, enterprise/internos ilimitado"}]'::jsonb,
     'Os limites por plano batem com o teto de vidas.',
     'Cota = pessoas mapeadas.'),
    (v_mod, 'MAPA-PLANO-003', 'Add-on aceita o tipo quota (recarga avulsa)', 'feliz', 'media', 'aprovado', 'api',
     'subscription_addons.kind aceita quota (alem de module e life).',
     'Migration de plano/cota aplicada.',
     '[{"ordem":1,"acao":"Inspecionar o CHECK de kind em subscription_addons","resultado_esperado":"o check inclui quota"}]'::jsonb,
     'O CHECK de kind inclui quota.',
     'Recarga avulsa unitaria por pessoa.'),
    (v_mod, 'MAPA-PLANO-004', 'Bloqueio de cota instalado (trigger + funcao)', 'feliz', 'critica', 'aprovado', 'api',
     'O trigger BEFORE INSERT trg_mapa_comp_cota e a funcao mapa_comportamental_checar_cota existem.',
     'Migration de plano/cota aplicada.',
     '[{"ordem":1,"acao":"Verificar pg_trigger e pg_proc","resultado_esperado":"trigger e funcao presentes"}]'::jsonb,
     'O bloqueio real da cota esta instalado na tabela de respostas.',
     'Enforcement deliberado (excecao ao gating apenas-visual).'),
    (v_mod, 'MAPA-PLANO-005', 'Contagem por pessoa: refazer o mapa nao consome nova analise', 'feliz', 'critica', 'aprovado', 'api',
     'A chave da pessoa colapsa o mesmo CPF (com/sem pontuacao) numa unica vida: contestar e refazer usa a contagem do mesmo funcionario.',
     'Funcao mapa_comportamental_chave_pessoa aplicada.',
     '[{"ordem":1,"acao":"Contar distintas chaves de {CPF pontuado, mesmo CPF sem pontuacao, outro CPF}","resultado_esperado":"2 pessoas distintas"}]'::jsonb,
     'O mesmo CPF conta uma vez; refazer nao vira nova vida.',
     'Cobre RF-014 (contestacao/reaplicacao) no lado da cota.'),
    (v_mod, 'MAPA-PLANO-006', 'Recarga de analises nao e cancelavel (compra avulsa)', 'feliz', 'media', 'aprovado', 'api',
     'my_cancelar_addon recusa cancelar limit.mapa_comportamental (balde vitalicio).',
     'Migration de plano/cota aplicada.',
     '[{"ordem":1,"acao":"Inspecionar o corpo de my_cancelar_addon","resultado_esperado":"ha guarda recusando limit.mapa_comportamental"}]'::jsonb,
     'Cancelar recarga de analises e recusado.',
     'Compra avulsa nao volta.')
  ON CONFLICT (codigo) DO NOTHING;

  RAISE NOTICE 'OK: casos MAPA-PLANO-001..006 documentados.';
END $doc$;

-- ---------------------------------------------------------------------
-- 5) Rotinas de motor (read-only).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.qa_caso_mapa_plano_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_incl int; v_baixos int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir matriz de mod.mapa_comportamental por tier';
  r.esperado    := 'Incluido em tier>=3; ausente em Starter/Essential';
  SELECT count(*) INTO v_incl
    FROM public.plan_entitlements e JOIN public.plans p ON p.id = e.plan_id
   WHERE e.feature_key = 'mod.mapa_comportamental' AND e.is_enabled AND p.tier >= 3;
  SELECT count(*) INTO v_baixos
    FROM public.plan_entitlements e JOIN public.plans p ON p.id = e.plan_id
   WHERE e.feature_key = 'mod.mapa_comportamental' AND e.is_enabled AND p.tier IN (1, 2);
  IF v_incl >= 1 AND v_baixos = 0 THEN
    r.situacao := 'passou';
    r.obtido := format('%s planos tier>=3 com o modulo; %s em Starter/Essential', v_incl, v_baixos);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('tier>=3=%s (esperado>=1); Starter/Essential=%s (esperado 0)', v_incl, v_baixos);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_mapa_plano_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_ok boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir cota de limit.mapa_comportamental por plano';
  r.esperado    := 'starter=20, essential=80, performance=200, governanca=500, enterprise/internos ilimitado';
  SELECT
    bool_and(CASE p.code
      WHEN 'starter'     THEN e.limit_value = 20 AND NOT e.is_unlimited
      WHEN 'essential'   THEN e.limit_value = 80 AND NOT e.is_unlimited
      WHEN 'performance' THEN e.limit_value = 200 AND NOT e.is_unlimited
      WHEN 'governanca'  THEN e.limit_value = 500 AND NOT e.is_unlimited
      WHEN 'enterprise'  THEN e.is_unlimited
      ELSE true END)
  INTO v_ok
  FROM public.plan_entitlements e JOIN public.plans p ON p.id = e.plan_id
  WHERE e.feature_key = 'limit.mapa_comportamental';
  IF coalesce(v_ok, false) THEN
    r.situacao := 'passou'; r.obtido := 'Limites por plano conferem com o teto de vidas';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'Algum limite por plano nao bate com o esperado';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_mapa_plano_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_ok boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Inspecionar CHECK de kind em subscription_addons';
  r.esperado    := 'O check inclui quota';
  SELECT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.subscription_addons'::regclass AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%quota%'
  ) INTO v_ok;
  IF v_ok THEN r.situacao := 'passou'; r.obtido := 'kind aceita quota';
  ELSE r.situacao := 'falhou'; r.obtido := 'kind nao aceita quota'; END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_mapa_plano_004()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_trg boolean; v_fn boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Verificar trigger e funcao de bloqueio de cota';
  r.esperado    := 'trg_mapa_comp_cota e mapa_comportamental_checar_cota presentes';
  SELECT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_mapa_comp_cota') INTO v_trg;
  SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'mapa_comportamental_checar_cota') INTO v_fn;
  IF v_trg AND v_fn THEN r.situacao := 'passou'; r.obtido := 'Trigger e funcao presentes';
  ELSE r.situacao := 'falhou'; r.obtido := format('trigger=%s funcao=%s', v_trg, v_fn); END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_mapa_plano_005()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_distintos int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Contar pessoas distintas por chave (mesmo CPF com/sem pontuacao + outro)';
  r.esperado    := '2 pessoas distintas (o mesmo CPF colapsa numa vida)';
  SELECT count(DISTINCT public.mapa_comportamental_chave_pessoa(cpf, u)) INTO v_distintos
  FROM (VALUES
    ('900.000.001-91'::text, NULL::uuid),
    ('90000000191'::text,    NULL::uuid),
    ('900.000.002-00'::text, NULL::uuid)
  ) AS amostra(cpf, u);
  IF v_distintos = 2 THEN
    r.situacao := 'passou'; r.obtido := 'Mesmo CPF conta 1 vez; refazer nao vira nova vida';
  ELSE
    r.situacao := 'falhou'; r.obtido := format('Chaves distintas=%s (esperado 2)', v_distintos);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_mapa_plano_006()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_ok boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Inspecionar my_cancelar_addon';
  r.esperado    := 'Ha guarda recusando cancelar limit.mapa_comportamental';
  SELECT pg_get_functiondef(p.oid) ILIKE '%limit.mapa_comportamental%'
    INTO v_ok
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'my_cancelar_addon'
  LIMIT 1;
  IF coalesce(v_ok, false) THEN
    r.situacao := 'passou'; r.obtido := 'Recarga de analises nao e cancelavel';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'Guarda de recarga ausente em my_cancelar_addon';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ---------------------------------------------------------------------
-- 6) Wiring caso -> rotina.
-- ---------------------------------------------------------------------
INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES
  ('MAPA-PLANO-001', 'qa_caso_mapa_plano_001'),
  ('MAPA-PLANO-002', 'qa_caso_mapa_plano_002'),
  ('MAPA-PLANO-003', 'qa_caso_mapa_plano_003'),
  ('MAPA-PLANO-004', 'qa_caso_mapa_plano_004'),
  ('MAPA-PLANO-005', 'qa_caso_mapa_plano_005'),
  ('MAPA-PLANO-006', 'qa_caso_mapa_plano_006')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
