-- =====================================================================
-- PROGRAMA DE PARCEIROS · ONDA 4 · SCRIPT DE ENTREGA · captura do ?ref= e
-- porta em standby para leads de Meta Ads
-- Cole no SQL Editor de cada ambiente (Teste → Homologação → Produção),
-- avançando só depois que o anterior devolver OK. Requer a Política v2.
--
-- O que faz: resolve o código do link, conta cliques (sem pessoa), cria o
-- lead do CRM já atribuído quando a landing recebe ?ref=, grava a origem
-- no tenant provisionado (webhook/onboarding), acrescenta a origem
-- 'meta_ads' e deixa a integração Meta pronta porém DESLIGADA (chaves
-- vazias em app_config). Só cria. Idempotente.
-- Corresponde às migrations 20260904170000 e 20260904180000.
-- ATENÇÃO: a origem 'meta_ads' é um valor novo de enum — o SQL Editor roda
-- tudo numa transação; por isso este script NÃO usa o valor no mesmo bloco
-- em que o cria (a função que o usa é criada, não executada).
-- =====================================================================

-- =====================================================================
-- PROGRAMA DE PARCEIROS · ONDA 4 · captura automática da origem (?ref=)
--
-- O código do link viaja da landing (landing_leads.ref_codigo) ao checkout
-- (assinaturas.ref_codigo) e ao provisionamento do tenant, que grava
-- parceiro_id/parceiro_link_id/originado_em. Cliques ficam em
-- parceiro_link_cliques sem dado de pessoa. Só cria; idempotente.
-- =====================================================================
SET lock_timeout = '10s';

-- Resolve um código de link (principal ou campanha) para parceiro ativo
CREATE OR REPLACE FUNCTION public.parceiro_resolver_ref(p_codigo text)
RETURNS TABLE (parceiro_id uuid, link_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $parceiro_resolver_ref$
  SELECT k.parceiro_id, k.id
  FROM public.parceiro_links k JOIN public.parceiros p ON p.id = k.parceiro_id
  WHERE k.ativo AND p.status = 'ativo' AND upper(k.codigo) = upper(regexp_replace(coalesce(p_codigo,''), '[^A-Za-z0-9-]', '', 'g'))
  LIMIT 1
$parceiro_resolver_ref$;
GRANT EXECUTE ON FUNCTION public.parceiro_resolver_ref(text) TO anon, authenticated, service_role;

-- Clique no link (chamado pela landing; sem IP, sem pessoa; limite por link/minuto)
CREATE OR REPLACE FUNCTION public.parceiro_registrar_clique(p_codigo text, p_ua_hash text DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $parceiro_registrar_clique$
DECLARE v record; v_recentes int;
BEGIN
  SELECT * INTO v FROM public.parceiro_resolver_ref(p_codigo);
  IF v.link_id IS NULL THEN RETURN false; END IF;
  SELECT count(*) INTO v_recentes FROM public.parceiro_link_cliques WHERE link_id = v.link_id AND clicado_em > now() - interval '1 minute';
  IF v_recentes >= 60 THEN RETURN false; END IF;   -- freio contra robô
  INSERT INTO public.parceiro_link_cliques (link_id, ua_hash) VALUES (v.link_id, left(p_ua_hash, 64));
  RETURN true;
END $parceiro_registrar_clique$;
GRANT EXECUTE ON FUNCTION public.parceiro_registrar_clique(text, text) TO anon, authenticated;

-- Landing: lead com ref vira lead do CRM já atribuído ao parceiro (atribuição link)
CREATE OR REPLACE FUNCTION public.landing_leads_atribuir_parceiro()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $landing_leads_atribuir_parceiro$
DECLARE v record;
BEGIN
  IF NEW.ref_codigo IS NULL OR btrim(NEW.ref_codigo) = '' THEN RETURN NEW; END IF;
  SELECT * INTO v FROM public.parceiro_resolver_ref(NEW.ref_codigo);
  IF v.parceiro_id IS NULL THEN RETURN NEW; END IF;
  INSERT INTO public.leads (nome, email, telefone, empresa, origem, status, landing_lead_id, parceiro_id, parceiro_link_id, atribuicao, notas)
  VALUES (NEW.nome, NEW.email, NEW.telefone, NEW.empresa, 'landing_page', 'novo', NEW.id, v.parceiro_id, v.link_id, 'link',
          'Chegou pelo link de indicação ' || upper(NEW.ref_codigo));
  RETURN NEW;
END $landing_leads_atribuir_parceiro$;
DROP TRIGGER IF EXISTS trg_landing_leads_atribuir_parceiro ON public.landing_leads;
CREATE TRIGGER trg_landing_leads_atribuir_parceiro AFTER INSERT ON public.landing_leads
  FOR EACH ROW EXECUTE FUNCTION public.landing_leads_atribuir_parceiro();

-- Provisionamento (webhook / onboarding): grava a origem no tenant a partir do ref
CREATE OR REPLACE FUNCTION public.parceiro_atribuir_tenant_por_ref(p_tenant_id uuid, p_codigo text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $parceiro_atribuir_tenant_por_ref$
DECLARE v record;
BEGIN
  SELECT * INTO v FROM public.parceiro_resolver_ref(p_codigo);
  IF v.parceiro_id IS NULL THEN RETURN false; END IF;
  UPDATE public.tenants SET parceiro_id = v.parceiro_id, parceiro_link_id = v.link_id, originado_em = coalesce(originado_em, now())
  WHERE id = p_tenant_id AND parceiro_id IS NULL;
  -- lead do CRM com o mesmo e-mail? marca convertido
  RETURN FOUND;
END $parceiro_atribuir_tenant_por_ref$;
GRANT EXECUTE ON FUNCTION public.parceiro_atribuir_tenant_por_ref(uuid, text) TO service_role, authenticated;

-- Origem de tráfego pago (Meta Ads) entra no enum; a integração fica em standby
ALTER TYPE public.lead_origem ADD VALUE IF NOT EXISTS 'meta_ads';

-- QA PGP-015 — ref grava a origem no lead
CREATE OR REPLACE FUNCTION public.qa_caso_pgp_015()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_p uuid; v_l uuid; v_lead record; v_ok boolean; v_t uuid;
BEGIN
  DELETE FROM public.parceiros WHERE codigo = 'QA-PGP-REF';   -- sobra de execução avulsa fora do descarte
  INSERT INTO public.parceiros (codigo, nome, tipo_parceiro, trilha, status) VALUES ('QA-PGP-REF', 'QA Ref', 'indicador', 'indicador', 'ativo') RETURNING id INTO v_p;
  r.passo_ordem := 1; r.passo_acao := 'Clique + landing_lead com ref_codigo do parceiro';
  r.esperado := 'Clique contado; lead do CRM criado com parceiro_id, link e atribuição link';
  v_ok := public.parceiro_registrar_clique('qa-pgp-ref', 'ua');
  INSERT INTO public.landing_leads (nome, email, telefone, empresa, ref_codigo) VALUES ('QA Lead Ref', 'qa-ref@exemplo.test', '46999999999', 'QA Empresa Ref', 'QA-PGP-REF') RETURNING id INTO v_l;
  SELECT parceiro_id, atribuicao, parceiro_link_id INTO v_lead FROM public.leads WHERE landing_lead_id = v_l;
  r.passo_ordem := 2; r.passo_acao := 'Provisionar tenant com o mesmo ref';
  r.esperado := 'tenants.parceiro_id preenchido';
  v_t := public.qa_sandbox_tenant_id();
  PERFORM public.qa_modo_ligar();
  UPDATE public.tenants SET parceiro_id = NULL, parceiro_link_id = NULL WHERE id = v_t;
  PERFORM public.parceiro_atribuir_tenant_por_ref(v_t, 'QA-PGP-REF');
  IF v_ok AND v_lead.parceiro_id = v_p AND v_lead.atribuicao = 'link' AND v_lead.parceiro_link_id IS NOT NULL
     AND (SELECT parceiro_id FROM public.tenants WHERE id = v_t) = v_p THEN
    r.situacao := 'passou'; r.obtido := 'Clique registrado; lead atribuído por link; tenant originado pelo ref.';
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: clique=%s, lead.parceiro=%s, atribuicao=%s, tenant.parceiro=%s', v_ok, v_lead.parceiro_id = v_p, v_lead.atribuicao, (SELECT parceiro_id FROM public.tenants WHERE id = v_t) = v_p);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;
INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES ('PGP-015', 'qa_caso_pgp_015')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- =====================================================================
-- LEADS · integração Meta Ads (formulários de lead de tráfego pago) — STANDBY
--
-- Deixa a porta pronta sem ligar nada: tabela de eventos recebidos, chaves de
-- configuração vazias em app_config (a Edge Function meta-leads-webhook
-- responde 503 "standby" enquanto não houver token) e a origem 'meta_ads' no
-- Kanban. Quando a campanha for criada, basta preencher as chaves.
-- =====================================================================
SET lock_timeout = '10s';

CREATE TABLE IF NOT EXISTS public.leads_integracoes_eventos (
  id            bigserial PRIMARY KEY,
  origem        text NOT NULL DEFAULT 'meta_ads',
  external_id   text NOT NULL,
  form_id       text,
  campanha      text,
  payload       jsonb NOT NULL DEFAULT '{}'::jsonb,
  lead_id       uuid REFERENCES public.leads(id) ON DELETE SET NULL,
  status        text NOT NULL DEFAULT 'recebido' CHECK (status IN ('recebido','processado','ignorado','erro')),
  erro          text,
  recebido_em   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (origem, external_id)
);
ALTER TABLE public.leads_integracoes_eventos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS leads_integracoes_superadmin ON public.leads_integracoes_eventos;
CREATE POLICY leads_integracoes_superadmin ON public.leads_integracoes_eventos FOR ALL TO authenticated
  USING (public.is_superadmin(auth.uid())) WITH CHECK (public.is_superadmin(auth.uid()));
GRANT ALL ON public.leads_integracoes_eventos TO service_role;
GRANT SELECT ON public.leads_integracoes_eventos TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.leads_integracoes_eventos_id_seq TO service_role;

-- Chaves vazias = integração desligada (a função recusa). Preencher no SQL Editor quando houver campanha.
INSERT INTO public.app_config (chave, valor) VALUES
  ('meta_verify_token', ''), ('meta_app_secret', ''), ('meta_page_access_token', ''), ('meta_leads_ativo', 'false')
ON CONFLICT (chave) DO NOTHING;

-- Função chamada pela Edge Function (service_role): cria/atualiza o lead a partir do formulário
CREATE OR REPLACE FUNCTION public.leads_receber_meta(_external_id text, _form_id text, _campanha text, _payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $leads_receber_meta$
DECLARE v_ev bigint; v_lead uuid; v_nome text; v_email text; v_tel text; v_emp text; v_cidade text; v_uf text; v_ref record;
BEGIN
  INSERT INTO public.leads_integracoes_eventos (origem, external_id, form_id, campanha, payload)
  VALUES ('meta_ads', _external_id, _form_id, _campanha, coalesce(_payload,'{}'::jsonb))
  ON CONFLICT (origem, external_id) DO NOTHING RETURNING id INTO v_ev;
  IF v_ev IS NULL THEN RETURN jsonb_build_object('ok', true, 'duplicado', true); END IF;

  -- Campos usuais do formulário de lead da Meta (field_data → name/values)
  v_nome  := coalesce(_payload->>'full_name', _payload->>'nome', _payload->>'name', 'Lead Meta Ads');
  v_email := coalesce(_payload->>'email', _payload->>'e-mail');
  v_tel   := coalesce(_payload->>'phone_number', _payload->>'telefone', _payload->>'whatsapp');
  v_emp   := coalesce(_payload->>'company_name', _payload->>'empresa');
  v_cidade := coalesce(_payload->>'city', _payload->>'cidade');
  v_uf    := coalesce(_payload->>'state', _payload->>'uf');
  SELECT * INTO v_ref FROM public.parceiro_resolver_ref(_payload->>'ref');

  INSERT INTO public.leads (nome, email, telefone, empresa, cidade, uf, origem, status, notas, tags, parceiro_id, parceiro_link_id, atribuicao)
  VALUES (left(v_nome,100), v_email, v_tel, v_emp, v_cidade, v_uf, 'meta_ads', 'novo',
          'Meta Ads · formulário ' || coalesce(_form_id,'?') || coalesce(' · campanha ' || _campanha, ''),
          ARRAY['meta_ads', coalesce(_campanha,'sem-campanha')], v_ref.parceiro_id, v_ref.link_id, CASE WHEN v_ref.parceiro_id IS NULL THEN NULL ELSE 'link' END)
  RETURNING id INTO v_lead;
  UPDATE public.leads_integracoes_eventos SET lead_id = v_lead, status = 'processado' WHERE id = v_ev;
  RETURN jsonb_build_object('ok', true, 'lead_id', v_lead);
EXCEPTION WHEN OTHERS THEN
  UPDATE public.leads_integracoes_eventos SET status = 'erro', erro = SQLERRM WHERE id = v_ev;
  RETURN jsonb_build_object('ok', false, 'erro', SQLERRM);
END $leads_receber_meta$;
GRANT EXECUTE ON FUNCTION public.leads_receber_meta(text, text, text, jsonb) TO service_role;

-- =====================================================================
-- CONFERÊNCIA FINAL
-- =====================================================================
WITH f AS MATERIALIZED (SELECT count(*) AS n FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace WHERE ns.nspname='public' AND p.proname IN
       ('parceiro_resolver_ref','parceiro_registrar_clique','landing_leads_atribuir_parceiro','parceiro_atribuir_tenant_por_ref','leads_receber_meta','qa_caso_pgp_015')),
     t AS MATERIALIZED (SELECT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_landing_leads_atribuir_parceiro') AS trigger_landing,
                              EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='leads_integracoes_eventos') AS tabela_meta),
     e AS MATERIALIZED (SELECT EXISTS (SELECT 1 FROM pg_enum en JOIN pg_type ty ON ty.oid = en.enumtypid WHERE ty.typname='lead_origem' AND en.enumlabel='meta_ads') AS origem_meta),
     k AS MATERIALIZED (SELECT count(*) AS n FROM public.app_config WHERE chave LIKE 'meta_%')
SELECT CASE WHEN f.n = 6 AND t.trigger_landing AND t.tabela_meta AND e.origem_meta AND k.n = 4 THEN 'OK — Onda 4 aplicada (Meta Ads em standby)' ELSE 'ATENÇÃO — confira as colunas ao lado' END AS resultado,
       f.n || '/6' AS funcoes, t.trigger_landing, t.tabela_meta, e.origem_meta, k.n || '/4' AS chaves_meta_vazias, NULL::text AS erro_tecnico
FROM f, t, e, k;
