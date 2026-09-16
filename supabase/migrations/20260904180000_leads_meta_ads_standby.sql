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
