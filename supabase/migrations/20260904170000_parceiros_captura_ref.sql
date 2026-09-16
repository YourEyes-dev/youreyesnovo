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
