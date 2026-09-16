-- =====================================================================
-- PROGRAMA DE PARCEIROS · ONDA 3 · SCRIPT DE ENTREGA · motor de comissões
-- Cole no SQL Editor de cada ambiente (Teste → Homologação → Produção),
-- avançando só depois que o anterior devolver OK. Requer Ondas 1, 2 e o
-- Contrato de Parceria aplicados.
--
-- O que faz: fechamento mensal (dia 25, pg_cron) com snapshot de MRR,
-- comissão recorrente, evento de setup do implantador (tabela configurável),
-- bônus de renovação e promoção de nível; pagamento/retenção/ajuste pelo
-- SuperAdmin; sugestão de parceiro por localidade para leads da casa;
-- histórico de 12 meses no portal; rotinas QA PGP-010/012/013/014.
-- Só cria; não altera dado existente. Idempotente.
-- Corresponde à migration 20260904150000_parceiros_motor_comissoes.sql.
-- NÃO dispara fechamento sozinho: a primeira competência é fechada pelo
-- SuperAdmin (aba Parceiros › Comissões) ou pelo agendamento do dia 25.
-- =====================================================================

-- =====================================================================
-- PROGRAMA DE PARCEIROS · ONDA 3 · motor de comissões
--
-- Fechamento mensal (dia 25), snapshot de MRR por parceiro/cliente para o
-- gráfico de 12 meses, comissão por evento (setup do implantador, lida da
-- tabela configurável — PGP-005/013), bônus de renovação, promoção de nível,
-- marcação de pagamento pelo SuperAdmin e sugestão de parceiro por
-- localidade para leads da casa (PGP-014). Só cria; o fechamento escreve em
-- tabelas do próprio programa (parceiro_*) e é idempotente por competência
-- (PGP-012): rodar duas vezes não duplica nem altera valores já fechados.
-- =====================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- 1) Snapshots mensais (gráfico "Sua evolução" e histórico auditável)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.parceiro_mrr_snapshots (
  parceiro_id   uuid NOT NULL REFERENCES public.parceiros(id) ON DELETE CASCADE,
  competencia   date NOT NULL,                          -- dia 1 do mês
  tenant_id     uuid REFERENCES public.tenants(id) ON DELETE SET NULL,
  tenant_nome   text,
  estagio       text,
  mrr_cents     bigint NOT NULL DEFAULT 0,
  papel         text,
  criado_em     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (parceiro_id, competencia, tenant_id)
);
ALTER TABLE public.parceiro_mrr_snapshots ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS parceiro_mrr_snapshots_proprio ON public.parceiro_mrr_snapshots;
CREATE POLICY parceiro_mrr_snapshots_proprio ON public.parceiro_mrr_snapshots
  FOR SELECT TO authenticated USING (parceiro_id = public.parceiro_meu_id() OR public.is_superadmin(auth.uid()));
GRANT SELECT ON public.parceiro_mrr_snapshots TO authenticated;
GRANT ALL ON public.parceiro_mrr_snapshots TO service_role;

ALTER TABLE public.leads
  ADD COLUMN IF NOT EXISTS cidade text,
  ADD COLUMN IF NOT EXISTS uf     text;

-- ---------------------------------------------------------------------
-- 2) Fechamento de competência (idempotente)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.parceiro_fechar_competencia(p_competencia date DEFAULT NULL, p_fechar boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $parceiro_fechar_competencia$
DECLARE
  v_comp date := date_trunc('month', coalesce(p_competencia, CURRENT_DATE))::date;
  v_p record; v_t record; v_ev record;
  v_pct numeric; v_nivel public.parceiro_niveis%ROWTYPE; v_prox public.parceiro_niveis%ROWTYPE;
  v_mrr_total bigint; v_mrr bigint; v_estagio text; v_atrib text; v_base bigint;
  v_n_rec int := 0; v_n_ev int := 0; v_n_bonus int := 0; v_n_promo int := 0; v_n_parc int := 0;
  v_go_live timestamptz;
BEGIN
  -- Só superadmin ou o robô (pg_cron roda como dono da função, sem auth.uid()).
  IF auth.uid() IS NOT NULL AND NOT public.is_superadmin(auth.uid()) THEN
    RAISE EXCEPTION 'Acesso negado';
  END IF;

  FOR v_p IN SELECT * FROM public.parceiros WHERE status IN ('ativo','suspenso') LOOP
    v_n_parc := v_n_parc + 1;
    SELECT * INTO v_nivel FROM public.parceiro_niveis WHERE id = v_p.nivel_id;
    IF v_nivel.id IS NULL THEN
      SELECT * INTO v_nivel FROM public.parceiro_niveis WHERE trilha = v_p.trilha AND ativo ORDER BY ordem LIMIT 1;
    END IF;
    v_mrr_total := 0;

    FOR v_t IN
      SELECT t.id, t.nome, t.parceiro_id, t.implantador_parceiro_id, t.originado_em,
             public.parceiro_estagio_tenant(t.id) AS estagio,
             public.parceiro_mrr_tenant(t.id) AS mrr_cents,
             (SELECT pl.is_public FROM public.subscriptions s JOIN public.plans pl ON pl.id = s.plan_id WHERE s.tenant_id = t.id) AS plano_publico,
             (SELECT s.status FROM public.subscriptions s WHERE s.tenant_id = t.id) AS sub_status,
             (SELECT s.ciclo_fim FROM public.subscriptions s WHERE s.tenant_id = t.id) AS ciclo_fim,
             (SELECT l.atribuicao FROM public.leads l WHERE l.tenant_convertido_id = t.id AND l.parceiro_id = v_p.id ORDER BY l.created_at LIMIT 1) AS atribuicao,
             (SELECT min(pr.updated_at) FROM public.profiles pr WHERE pr.tenant_id = t.id AND pr.onboarding_concluido) AS go_live_em
      FROM public.tenants t
      WHERE t.parceiro_id = v_p.id OR t.implantador_parceiro_id = v_p.id
    LOOP
      v_mrr := CASE WHEN coalesce(v_t.plano_publico, false) THEN v_t.mrr_cents ELSE 0 END;
      v_atrib := coalesce(v_t.atribuicao, 'link');
      v_pct := coalesce(v_p.percentual_comissao,
                        CASE WHEN v_atrib = 'casa' THEN v_nivel.percentual_casa ELSE v_nivel.percentual_link END, 25);

      -- snapshot (sempre, inclusive plano interno com MRR 0 — fica o rastro)
      INSERT INTO public.parceiro_mrr_snapshots (parceiro_id, competencia, tenant_id, tenant_nome, estagio, mrr_cents, papel)
      VALUES (v_p.id, v_comp, v_t.id, v_t.nome, v_t.estagio, v_mrr,
              CASE WHEN v_t.parceiro_id = v_p.id AND v_t.implantador_parceiro_id = v_p.id THEN 'origem+implantacao'
                   WHEN v_t.parceiro_id = v_p.id THEN 'origem' ELSE 'implantacao' END)
      ON CONFLICT (parceiro_id, competencia, tenant_id) DO UPDATE
        SET estagio = EXCLUDED.estagio, mrr_cents = EXCLUDED.mrr_cents, tenant_nome = EXCLUDED.tenant_nome;

      -- comissão recorrente: só quem ORIGINOU, cliente ativo/go-live em plano público
      IF v_t.parceiro_id = v_p.id AND v_t.estagio IN ('ativo','go_live') AND v_mrr > 0 THEN
        v_mrr_total := v_mrr_total + v_mrr;
        INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, base_cents, percentual, valor_cents, status, observacao)
        VALUES (v_p.id, v_t.id, v_comp, 'recorrente', v_mrr, v_pct, round(v_mrr * v_pct / 100),
                CASE WHEN v_t.sub_status = 'past_due' THEN 'retido' ELSE 'previsto' END,
                CASE WHEN v_t.sub_status = 'past_due' THEN 'Cliente inadimplente na competência — liberado com a regularização' END)
        ON CONFLICT (parceiro_id, tenant_id, competencia, tipo, coalesce(evento,'')) DO UPDATE
          SET base_cents = EXCLUDED.base_cents, percentual = EXCLUDED.percentual, valor_cents = EXCLUDED.valor_cents,
              status = CASE WHEN public.parceiro_comissoes.status IN ('fechado','pago') THEN public.parceiro_comissoes.status ELSE EXCLUDED.status END
          WHERE public.parceiro_comissoes.status NOT IN ('fechado','pago');
        v_n_rec := v_n_rec + 1;
      ELSIF v_t.parceiro_id = v_p.id AND v_t.plano_publico IS FALSE THEN
        -- PGP-010: plano interno/teste rende zero, com rastro
        INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, base_cents, percentual, valor_cents, status, observacao)
        VALUES (v_p.id, v_t.id, v_comp, 'recorrente', 0, v_pct, 0, 'previsto', 'Plano interno ou não público: não gera comissão')
        ON CONFLICT (parceiro_id, tenant_id, competencia, tipo, coalesce(evento,'')) DO NOTHING;
      END IF;

      -- evento: setup concluído pelo IMPLANTADOR (uma vez por cliente; PGP-013)
      IF v_t.implantador_parceiro_id = v_p.id AND v_t.go_live_em IS NOT NULL
         AND NOT EXISTS (SELECT 1 FROM public.parceiro_comissoes c WHERE c.parceiro_id = v_p.id AND c.tenant_id = v_t.id AND c.tipo = 'evento' AND c.evento = 'setup_concluido') THEN
        SELECT * INTO v_ev FROM public.parceiro_eventos_remuneracao
        WHERE trilha = v_p.trilha AND tipo_parceiro = v_p.tipo_parceiro AND evento = 'setup_concluido' AND ativo;
        IF v_ev.id IS NOT NULL THEN
          v_base := v_t.mrr_cents;
          INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, evento, base_cents, percentual, valor_cents, status, observacao)
          VALUES (v_p.id, v_t.id, v_comp, 'evento', 'setup_concluido', v_base, v_ev.percentual_primeira_mensalidade,
                  v_ev.valor_fixo_cents + round(v_base * v_ev.percentual_primeira_mensalidade / 100), 'previsto',
                  'Setup concluído em ' || to_char(v_t.go_live_em, 'DD/MM/YYYY'))
          ON CONFLICT (parceiro_id, tenant_id, competencia, tipo, coalesce(evento,'')) DO NOTHING;
          v_n_ev := v_n_ev + 1;
        END IF;
      END IF;

      -- bônus de renovação: ciclo que termina nesta competência e assinatura segue ativa
      IF v_t.parceiro_id = v_p.id AND v_t.ciclo_fim IS NOT NULL
         AND date_trunc('month', v_t.ciclo_fim)::date = v_comp AND v_t.sub_status = 'active' AND v_mrr > 0 THEN
        INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, evento, base_cents, percentual, valor_cents, status, observacao)
        VALUES (v_p.id, v_t.id, v_comp, 'bonus_renovacao', 'renovacao', v_mrr, v_pct,
                round(v_mrr * v_pct / 100 * coalesce(v_nivel.bonus_renovacao_multiplicador, 2)), 'previsto',
                'Renovação de ciclo em ' || to_char(v_t.ciclo_fim, 'DD/MM/YYYY'))
        ON CONFLICT (parceiro_id, tenant_id, competencia, tipo, coalesce(evento,'')) DO NOTHING;
        v_n_bonus := v_n_bonus + 1;
      END IF;
    END LOOP;

    -- promoção de nível (nunca rebaixa automaticamente — decisão em aberto)
    SELECT * INTO v_prox FROM public.parceiro_niveis
    WHERE trilha = v_p.trilha AND ativo AND ordem > coalesce(v_nivel.ordem, 0) AND mrr_minimo_cents <= v_mrr_total
    ORDER BY ordem DESC LIMIT 1;
    IF v_prox.id IS NOT NULL THEN
      UPDATE public.parceiros SET nivel_id = v_prox.id WHERE id = v_p.id;
      v_n_promo := v_n_promo + 1;
    END IF;
  END LOOP;

  IF p_fechar THEN
    UPDATE public.parceiro_comissoes SET status = 'fechado', fechado_em = now()
    WHERE competencia = v_comp AND status = 'previsto';
  END IF;

  RETURN jsonb_build_object('competencia', to_char(v_comp, 'YYYY-MM'), 'parceiros', v_n_parc,
    'recorrentes', v_n_rec, 'eventos', v_n_ev, 'bonus', v_n_bonus, 'promocoes', v_n_promo, 'fechado', p_fechar);
END $parceiro_fechar_competencia$;
GRANT EXECUTE ON FUNCTION public.parceiro_fechar_competencia(date, boolean) TO authenticated;

-- Agendamento: dia 25, 06:30 — fecha a competência corrente. Sob demanda continua possível.
DO $cron$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('parceiros-fechamento-mensal')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'parceiros-fechamento-mensal');
    PERFORM cron.schedule('parceiros-fechamento-mensal', '30 6 25 * *',
      $job$ SELECT public.parceiro_fechar_competencia(CURRENT_DATE, true); $job$);
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron indisponível; o fechamento segue chamável pelo SuperAdmin: %', SQLERRM;
END $cron$;

-- ---------------------------------------------------------------------
-- 3) SuperAdmin: ver e pagar
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.superadmin_parceiro_comissoes_list(_competencia date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $superadmin_parceiro_comissoes_list$
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  RETURN coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id', c.id, 'parceiro_id', c.parceiro_id, 'parceiro_nome', p.nome, 'pix_chave', p.pix_chave,
      'tenant_nome', t.nome, 'competencia', to_char(c.competencia, 'YYYY-MM'), 'tipo', c.tipo, 'evento', c.evento,
      'base_cents', c.base_cents, 'percentual', c.percentual, 'valor_cents', c.valor_cents, 'status', c.status,
      'fechado_em', c.fechado_em, 'pago_em', c.pago_em, 'observacao', c.observacao)
    ORDER BY c.competencia DESC, p.nome, t.nome)
    FROM public.parceiro_comissoes c
    JOIN public.parceiros p ON p.id = c.parceiro_id
    LEFT JOIN public.tenants t ON t.id = c.tenant_id
    WHERE _competencia IS NULL OR c.competencia = date_trunc('month', _competencia)::date), '[]'::jsonb);
END $superadmin_parceiro_comissoes_list$;
GRANT EXECUTE ON FUNCTION public.superadmin_parceiro_comissoes_list(date) TO authenticated;

CREATE OR REPLACE FUNCTION public.superadmin_parceiro_comissao_status(_ids uuid[], _status text, _observacao text DEFAULT NULL)
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $superadmin_parceiro_comissao_status$
DECLARE v_n int;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  IF _status NOT IN ('previsto','fechado','pago','retido') THEN RAISE EXCEPTION 'Status inválido'; END IF;
  UPDATE public.parceiro_comissoes SET
    status = _status,
    pago_em = CASE WHEN _status = 'pago' THEN now() ELSE NULL END,
    fechado_em = CASE WHEN _status IN ('fechado','pago') THEN coalesce(fechado_em, now()) ELSE fechado_em END,
    observacao = coalesce(_observacao, observacao)
  WHERE id = ANY(_ids);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $superadmin_parceiro_comissao_status$;
GRANT EXECUTE ON FUNCTION public.superadmin_parceiro_comissao_status(uuid[], text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.superadmin_parceiro_comissao_ajuste(_parceiro_id uuid, _competencia date, _valor_cents bigint, _observacao text)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $superadmin_parceiro_comissao_ajuste$
DECLARE v_id uuid;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, evento, base_cents, valor_cents, status, observacao)
  VALUES (_parceiro_id, NULL, date_trunc('month', _competencia)::date, 'ajuste', 'ajuste-' || gen_random_uuid()::text, 0, _valor_cents, 'fechado', _observacao)
  RETURNING id INTO v_id;
  RETURN v_id;
END $superadmin_parceiro_comissao_ajuste$;
GRANT EXECUTE ON FUNCTION public.superadmin_parceiro_comissao_ajuste(uuid, date, bigint, text) TO authenticated;

-- ---------------------------------------------------------------------
-- 4) Sugestão de parceiro por localidade (leads da casa) — PGP-014
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.parceiros_sugerir_para_lead(_lead_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $parceiros_sugerir_para_lead$
DECLARE v_l record;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  SELECT cidade, uf INTO v_l FROM public.leads WHERE id = _lead_id;
  RETURN coalesce((SELECT jsonb_agg(x ORDER BY x->>'prioridade', x->>'nome') FROM (
    SELECT jsonb_build_object(
      'id', p.id, 'nome', p.nome, 'tipo_parceiro', p.tipo_parceiro, 'cidade', p.cidade, 'uf', p.uf,
      'nivel', n.nome, 'clientes', (SELECT count(*) FROM public.tenants t WHERE t.parceiro_id = p.id),
      'motivo', CASE
        WHEN v_l.cidade IS NOT NULL AND lower(unaccent_safe(p.cidade)) = lower(unaccent_safe(v_l.cidade)) AND upper(p.uf) = upper(v_l.uf) THEN 'Mesma cidade'
        WHEN v_l.uf IS NOT NULL AND upper(p.uf) = upper(v_l.uf) THEN 'Mesmo estado'
        ELSE 'Atende à distância' END,
      'prioridade', CASE
        WHEN v_l.cidade IS NOT NULL AND lower(unaccent_safe(p.cidade)) = lower(unaccent_safe(v_l.cidade)) AND upper(p.uf) = upper(v_l.uf) THEN '1'
        WHEN v_l.uf IS NOT NULL AND upper(p.uf) = upper(v_l.uf) THEN '2' ELSE '3' END
        || lpad((9 - coalesce(n.ordem, 0))::text, 2, '0')
    ) AS x
    FROM public.parceiros p LEFT JOIN public.parceiro_niveis n ON n.id = p.nivel_id
    WHERE p.status = 'ativo' AND p.tipo_parceiro IN ('representante','implantador','clinica','contabilidade','indicador')
    LIMIT 5) q), '[]'::jsonb);
END $parceiros_sugerir_para_lead$;
GRANT EXECUTE ON FUNCTION public.parceiros_sugerir_para_lead(uuid) TO authenticated;

-- Remove acentos sem depender da extensão unaccent
CREATE OR REPLACE FUNCTION public.unaccent_safe(p text)
RETURNS text LANGUAGE sql IMMUTABLE
AS $unaccent_safe$
  SELECT translate(coalesce(p,''),
    'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
    'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC')
$unaccent_safe$;

CREATE OR REPLACE FUNCTION public.superadmin_lead_encaminhar(_lead_id uuid, _parceiro_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $superadmin_lead_encaminhar$
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  UPDATE public.leads SET parceiro_id = _parceiro_id,
    atribuicao = CASE WHEN _parceiro_id IS NULL THEN NULL ELSE 'casa' END,
    origem = CASE WHEN _parceiro_id IS NOT NULL AND origem = 'prospect_manual' THEN 'indicacao'::lead_origem ELSE origem END
  WHERE id = _lead_id;
END $superadmin_lead_encaminhar$;
GRANT EXECUTE ON FUNCTION public.superadmin_lead_encaminhar(uuid, uuid) TO authenticated;

-- ---------------------------------------------------------------------
-- 5) Portal: histórico de 12 meses
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.parceiro_meu_portal_com_contrato()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $parceiro_meu_portal_com_contrato$
  SELECT CASE WHEN public.parceiro_meu_id() IS NULL THEN NULL
         ELSE public.parceiro_meu_portal()
              || jsonb_build_object('contrato', public.parceiro_contrato_situacao(public.parceiro_meu_id()))
              || jsonb_build_object('historico', coalesce((
                   SELECT jsonb_agg(jsonb_build_object('competencia', to_char(m.competencia,'YYYY-MM'), 'mrr_cents', m.mrr) ORDER BY m.competencia)
                   FROM (SELECT competencia, sum(mrr_cents) FILTER (WHERE papel <> 'implantacao' AND estagio IN ('ativo','go_live')) AS mrr
                         FROM public.parceiro_mrr_snapshots WHERE parceiro_id = public.parceiro_meu_id()
                         GROUP BY competencia ORDER BY competencia DESC LIMIT 12) m), '[]'::jsonb))
         END
$parceiro_meu_portal_com_contrato$;

-- ---------------------------------------------------------------------
-- 6) QA — PGP-010, 012, 013, 014 (sondas com linhas sintéticas, descartadas)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.qa_pgp_cenario(OUT o_parceiro uuid, OUT o_impl uuid, OUT o_tenant_pub uuid)
RETURNS record LANGUAGE plpgsql AS $$
DECLARE v_plano uuid; v_uid uuid := gen_random_uuid();
BEGIN
  -- Escreve só no cercado de QA (as cercas bloqueiam qualquer outro tenant).
  PERFORM public.qa_modo_ligar();
  o_tenant_pub := public.qa_sandbox_tenant_id();
  IF o_tenant_pub IS NULL THEN RAISE EXCEPTION 'Cercado qa-sandbox não existe neste ambiente'; END IF;
  INSERT INTO public.parceiros (codigo, nome, tipo_parceiro, status) VALUES ('QA-PGP-ORIG', 'QA Origem', 'indicador', 'ativo') RETURNING id INTO o_parceiro;
  INSERT INTO public.parceiros (codigo, nome, tipo_parceiro, status) VALUES ('QA-PGP-IMPL', 'QA Implantador', 'implantador', 'ativo') RETURNING id INTO o_impl;
  SELECT id INTO v_plano FROM public.plans WHERE code = 'performance';
  UPDATE public.tenants SET parceiro_id = o_parceiro, implantador_parceiro_id = o_impl, originado_em = now() - interval '90 days', ativo = true
  WHERE id = o_tenant_pub;
  INSERT INTO public.subscriptions (tenant_id, plan_id, status) VALUES (o_tenant_pub, v_plano, 'active')
  ON CONFLICT (tenant_id) DO UPDATE SET plan_id = EXCLUDED.plan_id, status = 'active';
  INSERT INTO auth.users (id, email) VALUES (v_uid, 'qa-pgp-' || left(v_uid::text,8) || '@exemplo.test');
  INSERT INTO public.profiles (user_id, tenant_id, nome_completo, onboarding_concluido) VALUES (v_uid, o_tenant_pub, 'QA Owner', true);
  UPDATE public.profiles SET updated_at = now() - interval '45 days' WHERE tenant_id = o_tenant_pub;
  DELETE FROM public.parceiro_comissoes WHERE tenant_id = o_tenant_pub;
  DELETE FROM public.parceiro_mrr_snapshots WHERE tenant_id = o_tenant_pub;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_pgp_010()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; c record; v_int bigint; v_pub bigint; v_tester uuid;
BEGIN
  SELECT * INTO c FROM public.qa_pgp_cenario();
  r.passo_ordem := 1; r.passo_acao := 'Fechar competência com o cliente em plano público';
  r.esperado := 'Comissão recorrente > 0';
  PERFORM public.parceiro_fechar_competencia(CURRENT_DATE, false);
  SELECT valor_cents INTO v_pub FROM public.parceiro_comissoes WHERE parceiro_id = c.o_parceiro AND tenant_id = c.o_tenant_pub AND tipo = 'recorrente';

  r.passo_ordem := 2; r.passo_acao := 'Trocar o mesmo cliente para plano interno (não público) e fechar de novo';
  r.esperado := 'Comissão recorrente = 0 com observação';
  SELECT id INTO v_tester FROM public.plans WHERE is_public = false ORDER BY tier DESC LIMIT 1;
  IF v_tester IS NULL THEN r.situacao := 'nao_implementado'; r.obtido := 'Não há plano interno (is_public = false) neste ambiente para testar.'; RETURN r; END IF;
  DELETE FROM public.parceiro_comissoes WHERE tenant_id = c.o_tenant_pub;
  UPDATE public.subscriptions SET plan_id = v_tester WHERE tenant_id = c.o_tenant_pub;
  PERFORM public.parceiro_fechar_competencia(CURRENT_DATE, false);
  SELECT valor_cents INTO v_int FROM public.parceiro_comissoes WHERE parceiro_id = c.o_parceiro AND tenant_id = c.o_tenant_pub AND tipo = 'recorrente';

  IF coalesce(v_pub,0) > 0 AND v_int = 0 THEN
    r.situacao := 'passou'; r.obtido := format('público = %s centavos; interno = %s', v_pub, v_int);
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: público = %s (esperado > 0), interno = %s (esperado 0).', v_pub, v_int);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_pgp_012()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; c record; n1 int; n2 int; s1 bigint; s2 bigint; st text;
BEGIN
  SELECT * INTO c FROM public.qa_pgp_cenario();
  r.passo_ordem := 1; r.passo_acao := 'Fechar a mesma competência duas vezes';
  r.esperado := 'Mesmo número de linhas e mesma soma; status fechado preservado';
  PERFORM public.parceiro_fechar_competencia(CURRENT_DATE, true);
  SELECT count(*), sum(valor_cents) INTO n1, s1 FROM public.parceiro_comissoes WHERE parceiro_id IN (c.o_parceiro, c.o_impl);
  PERFORM public.parceiro_fechar_competencia(CURRENT_DATE, true);
  SELECT count(*), sum(valor_cents) INTO n2, s2 FROM public.parceiro_comissoes WHERE parceiro_id IN (c.o_parceiro, c.o_impl);
  SELECT string_agg(DISTINCT status, ',') INTO st FROM public.parceiro_comissoes WHERE parceiro_id IN (c.o_parceiro, c.o_impl);
  IF n1 = n2 AND s1 = s2 AND st = 'fechado' THEN
    r.situacao := 'passou'; r.obtido := format('%s linhas, %s centavos nas duas rodadas; status %s', n1, s1, st);
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: 1ª rodada %s linhas/%s; 2ª %s linhas/%s; status %s.', n1, s1, n2, s2, st);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_pgp_013()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; c record; v_val bigint; v_n int; v_ev record; v_esp bigint;
BEGIN
  SELECT * INTO c FROM public.qa_pgp_cenario();
  UPDATE public.parceiro_eventos_remuneracao SET valor_fixo_cents = 30000, percentual_primeira_mensalidade = 50, ativo = true
  WHERE trilha = 'operador' AND tipo_parceiro = 'implantador' AND evento = 'setup_concluido';
  r.passo_ordem := 1; r.passo_acao := 'Fechar competência: implantador de cliente com onboarding concluído';
  r.esperado := 'Uma comissão tipo evento/setup_concluido com valor fixo + % da 1ª mensalidade (tabela), e não duplica';
  PERFORM public.parceiro_fechar_competencia(CURRENT_DATE, false);
  PERFORM public.parceiro_fechar_competencia(CURRENT_DATE, false);
  SELECT count(*), max(valor_cents) INTO v_n, v_val FROM public.parceiro_comissoes
  WHERE parceiro_id = c.o_impl AND tenant_id = c.o_tenant_pub AND tipo = 'evento' AND evento = 'setup_concluido';
  v_esp := 30000 + round(public.parceiro_mrr_tenant(c.o_tenant_pub) * 50 / 100);
  IF v_n = 1 AND v_val = v_esp THEN
    r.situacao := 'passou'; r.obtido := format('1 evento de setup, %s centavos (tabela: fixo 30000 + 50%%).', v_val);
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: %s evento(s), valor %s (esperado 1 evento de %s).', v_n, v_val, v_esp);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_pgp_014()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_lead uuid; v_perto uuid; v_longe uuid; v_sug jsonb; v_atrib text; v_sa uuid;
BEGIN
  INSERT INTO public.parceiros (codigo, nome, tipo_parceiro, status, cidade, uf) VALUES ('QA-PGP-PERTO', 'QA Perto', 'representante', 'ativo', 'Pato Branco', 'PR') RETURNING id INTO v_perto;
  INSERT INTO public.parceiros (codigo, nome, tipo_parceiro, status, cidade, uf) VALUES ('QA-PGP-LONGE', 'QA Longe', 'representante', 'ativo', 'Manaus', 'AM') RETURNING id INTO v_longe;
  INSERT INTO public.leads (nome, empresa, cidade, uf) VALUES ('QA Lead', 'QA Empresa Local', 'pato branco', 'pr') RETURNING id INTO v_lead;
  -- simula superadmin para as funções que exigem
  SELECT user_id INTO v_sa FROM public.superadmins WHERE ativo LIMIT 1;
  IF v_sa IS NULL THEN
    v_sa := gen_random_uuid();
    INSERT INTO auth.users (id, email) VALUES (v_sa, 'qa-sa-' || left(v_sa::text,8) || '@exemplo.test');
    INSERT INTO public.superadmins (user_id, email) VALUES (v_sa, 'qa-sa@exemplo.test');
  END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);

  r.passo_ordem := 1; r.passo_acao := 'Sugerir parceiros para lead de Pato Branco/PR';
  r.esperado := 'Parceiro da mesma cidade em primeiro';
  v_sug := public.parceiros_sugerir_para_lead(v_lead);
  r.passo_ordem := 2; r.passo_acao := 'Encaminhar o lead ao parceiro sugerido';
  r.esperado := 'leads.atribuicao = casa';
  PERFORM public.superadmin_lead_encaminhar(v_lead, v_perto);
  SELECT atribuicao INTO v_atrib FROM public.leads WHERE id = v_lead;

  IF (v_sug->0->>'id')::uuid = v_perto AND v_atrib = 'casa' THEN
    r.situacao := 'passou'; r.obtido := format('1º sugerido: %s (%s); atribuição %s', v_sug->0->>'nome', v_sug->0->>'motivo', v_atrib);
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: 1º sugerido = %s (esperado QA Perto); atribuição = %s (esperado casa).', v_sug->0->>'nome', v_atrib);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES
  ('PGP-010', 'qa_caso_pgp_010'), ('PGP-012', 'qa_caso_pgp_012'),
  ('PGP-013', 'qa_caso_pgp_013'), ('PGP-014', 'qa_caso_pgp_014')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- =====================================================================
-- CONFERÊNCIA FINAL (o editor mostra só este resultado)
-- =====================================================================
WITH f AS MATERIALIZED (
  SELECT count(*) AS n FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
  WHERE ns.nspname = 'public' AND p.proname IN ('parceiro_fechar_competencia','superadmin_parceiro_comissoes_list',
    'superadmin_parceiro_comissao_status','superadmin_parceiro_comissao_ajuste','parceiros_sugerir_para_lead',
    'superadmin_lead_encaminhar','unaccent_safe','qa_pgp_cenario','qa_caso_pgp_010','qa_caso_pgp_012','qa_caso_pgp_013','qa_caso_pgp_014')
), t AS MATERIALIZED (
  SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='parceiro_mrr_snapshots') AS snapshots,
         EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='leads' AND column_name='cidade') AS leads_cidade
), c AS MATERIALIZED (
  SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_cron') AS tem_cron
), q AS MATERIALIZED (
  SELECT count(*) AS n FROM public.qa_implementacoes WHERE codigo IN ('PGP-010','PGP-012','PGP-013','PGP-014') AND ativo
), lido AS MATERIALIZED (
  SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
                 WHERE ns.nspname='public' AND p.proname='parceiro_fechar_competencia' AND p.prosrc ILIKE '%parceiro_eventos_remuneracao%') AS motor_le_tabela
)
SELECT CASE WHEN f.n = 12 AND t.snapshots AND t.leads_cidade AND q.n = 4 AND lido.motor_le_tabela
            THEN 'OK — Programa de Parceiros (Onda 3) aplicado' ELSE 'ATENÇÃO — confira as colunas ao lado' END AS resultado,
       f.n || '/12' AS funcoes, t.snapshots, t.leads_cidade, c.tem_cron AS agendamento_dia_25_disponivel,
       q.n || '/4' AS rotinas_qa, lido.motor_le_tabela, NULL::text AS erro_tecnico
FROM f, t, c, q, lido;
