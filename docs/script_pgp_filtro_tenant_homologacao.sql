-- ============================================================================
-- ENTREGA — PGP-010/012/013 · escopo de tenant no motor de comissões — HOMOLOGAÇÃO
--
-- Cole INTEIRO no SQL Editor da HOMOLOGAÇÃO; depois de conferido, o MESMO na
-- PRODUÇÃO. Só CREATE/REPLACE de funções (motor + rotinas de QA) — NÃO cria
-- tabela, NÃO apaga/altera dado de comissão, NÃO mexe em gatilho de tabela.
--
-- Fecha PGP-010/012/013 pelo padrão AFAST-001: o motor parceiro_fechar_competencia
-- ganha p_tenant OPCIONAL (NULL = global; o cron do dia 25 e o superadmin seguem
-- IDÊNTICOS — cada cláusula nova é "p_tenant IS NULL OR ..."). As 3 rotinas de QA
-- passam o cercado, então escrevem só no sandbox e a cerca nunca é cruzada.
--
-- A assinatura muda de 2 → 3 args: DROP da versão antiga primeiro (senão fica uma
-- sobrecarga pendurada), depois CREATE da nova e re-GRANT. O cron chama com 2 args
-- e continua resolvendo para o default.
--
-- Validado em réplica local (motor real + cerca real): motor byte-idêntico ao
-- original fora dos guardas p_tenant (diff conferido); chamada global com a cerca
-- ligada TRAVA no tenant real (bug reproduzido); as 3 rotinas escopadas passam
-- (010 público>0/interno=0, 012 idempotente, 013 parcelas 18000/24000 sem duplicar);
-- zero escrita no tenant real; cenário idempotente; cron 2-arg resolve. Ao fim,
-- conferência única — esperado tudo 'ok'.
-- ============================================================================

SET lock_timeout = '10s';

-- A assinatura muda (2 → 3 args). DROP da versão antiga primeiro para não deixar
-- uma sobrecarga de 2 args pendurada; o cron chama com 2 args e continua
-- resolvendo para o default (p_tenant NULL = global, comportamento intacto).
DROP FUNCTION IF EXISTS public.parceiro_fechar_competencia(date, boolean);

CREATE OR REPLACE FUNCTION public.parceiro_fechar_competencia(p_competencia date DEFAULT NULL, p_fechar boolean DEFAULT true, p_tenant uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $parceiro_fechar_competencia$
DECLARE
  v_comp date := date_trunc('month', coalesce(p_competencia, CURRENT_DATE))::date;
  v_fim  date := (v_comp + interval '1 month' - interval '1 day')::date;
  v_p record; v_t record; v_ev record;
  v_nivel public.parceiro_niveis%ROWTYPE; v_prox public.parceiro_niveis%ROWTYPE;
  v_pct numeric; v_mrr_total bigint; v_base bigint; v_atrib text; v_val bigint; v_setup bigint;
  v_ret_pct numeric := public.parceiro_cfg('retencao_qualidade_pct', 20);
  v_ret_meses int := public.parceiro_cfg('retencao_qualidade_meses', 3)::int;
  v_ciclo int := public.parceiro_cfg('ciclo_meses', 24)::int;
  v_n_rec int := 0; v_n_setup int := 0; v_n_bonus int := 0; v_n_promo int := 0; v_n_parc int := 0; v_n_claw int := 0;
  v_ativacoes_mes int; v_golives_fast int;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;

  FOR v_p IN SELECT * FROM public.parceiros WHERE status IN ('ativo','suspenso')
             AND (p_tenant IS NULL OR EXISTS (SELECT 1 FROM public.tenants tt
                   WHERE tt.id = p_tenant AND (tt.parceiro_id = parceiros.id OR tt.implantador_parceiro_id = parceiros.id))) LOOP
    v_n_parc := v_n_parc + 1;
    SELECT * INTO v_nivel FROM public.parceiro_niveis WHERE id = v_p.nivel_id AND trilha = v_p.trilha;
    IF v_nivel.id IS NULL THEN SELECT * INTO v_nivel FROM public.parceiro_niveis WHERE trilha = v_p.trilha AND ativo ORDER BY ordem LIMIT 1; END IF;
    v_mrr_total := 0; v_ativacoes_mes := 0;

    FOR v_t IN
      SELECT t.id, t.nome, t.parceiro_id, t.implantador_parceiro_id, t.originado_em,
             public.parceiro_estagio_tenant(t.id) AS estagio,
             public.parceiro_mrr_tenant(t.id) AS mrr_cents,
             public.parceiro_base_tenant(t.id) AS base_cents,
             s.status AS sub_status, s.ciclo_inicio, s.ciclo_fim, s.setup_valor_cents, s.go_live_homologado_em,
             s.primeira_mensalidade_compensada_em, s.terceira_mensalidade_compensada_em, s.contrato_assinado_em, s.cancelado_em,
             (SELECT pl.is_public FROM public.plans pl WHERE pl.id = s.plan_id) AS plano_publico,
             (SELECT l.atribuicao FROM public.leads l WHERE l.tenant_convertido_id = t.id AND l.parceiro_id = v_p.id ORDER BY l.created_at LIMIT 1) AS atribuicao
      FROM public.tenants t LEFT JOIN public.subscriptions s ON s.tenant_id = t.id
      WHERE (t.parceiro_id = v_p.id OR t.implantador_parceiro_id = v_p.id) AND (p_tenant IS NULL OR t.id = p_tenant)
    LOOP
      v_base := CASE WHEN coalesce(v_t.plano_publico, false) THEN v_t.base_cents ELSE 0 END;
      v_atrib := coalesce(v_t.atribuicao, 'link');
      v_pct := coalesce(v_p.percentual_comissao, CASE WHEN v_atrib = 'casa' THEN v_nivel.percentual_casa ELSE v_nivel.percentual_link END, 0);

      INSERT INTO public.parceiro_mrr_snapshots (parceiro_id, competencia, tenant_id, tenant_nome, estagio, mrr_cents, papel)
      VALUES (v_p.id, v_comp, v_t.id, v_t.nome, v_t.estagio, v_base,
              CASE WHEN v_t.parceiro_id = v_p.id AND v_t.implantador_parceiro_id = v_p.id THEN 'origem+implantacao'
                   WHEN v_t.parceiro_id = v_p.id THEN 'origem' ELSE 'implantacao' END)
      ON CONFLICT (parceiro_id, competencia, tenant_id) DO UPDATE SET estagio = EXCLUDED.estagio, mrr_cents = EXCLUDED.mrr_cents, tenant_nome = EXCLUDED.tenant_nome;

      -- só o ORIGINADOR recebe; conta só integra depois do go-live homologado
      IF v_t.parceiro_id <> v_p.id THEN CONTINUE; END IF;

      IF v_t.go_live_homologado_em IS NOT NULL AND v_t.go_live_homologado_em <= v_fim
         AND v_t.sub_status IN ('active','past_due') AND v_base > 0 THEN
        v_mrr_total := v_mrr_total + v_base;
        v_val := round(v_base * v_pct / 100);
        -- Operador: retenção de qualidade nos primeiros meses
        IF v_p.trilha = 'operador' AND v_comp < (date_trunc('month', v_t.go_live_homologado_em) + (v_ret_meses || ' months')::interval)::date THEN
          INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, evento, base_cents, percentual, valor_cents, status, observacao)
          VALUES (v_p.id, v_t.id, v_comp, 'retencao', 'retencao_qualidade', v_base, v_ret_pct, round(v_val * v_ret_pct / 100),
                  CASE WHEN v_t.terceira_mensalidade_compensada_em IS NOT NULL THEN 'previsto' ELSE 'retido' END,
                  'Retenção de qualidade do Operador (' || v_ret_pct || '% dos ' || v_ret_meses || ' primeiros meses); liberada após a 3ª mensalidade com a conta ativa')
          ON CONFLICT (parceiro_id, coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), competencia, tipo, coalesce(evento,'')) DO UPDATE
            SET status = CASE WHEN public.parceiro_comissoes.status IN ('fechado','pago') THEN public.parceiro_comissoes.status
                              WHEN v_t.terceira_mensalidade_compensada_em IS NOT NULL THEN 'previsto' ELSE 'retido' END,
                valor_cents = CASE WHEN public.parceiro_comissoes.status IN ('fechado','pago') THEN public.parceiro_comissoes.valor_cents ELSE EXCLUDED.valor_cents END;
          v_val := v_val - round(v_val * v_ret_pct / 100);
        END IF;
        INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, base_cents, percentual, valor_cents, status, observacao)
        VALUES (v_p.id, v_t.id, v_comp, 'recorrente', v_base, v_pct, v_val,
                CASE WHEN v_t.sub_status = 'past_due' THEN 'retido' ELSE 'previsto' END,
                CASE WHEN v_t.sub_status = 'past_due' THEN 'Cliente inadimplente — liberado com a regularização' END)
        ON CONFLICT (parceiro_id, coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), competencia, tipo, coalesce(evento,'')) DO UPDATE
          SET base_cents = EXCLUDED.base_cents, percentual = EXCLUDED.percentual, valor_cents = EXCLUDED.valor_cents, status = EXCLUDED.status, observacao = EXCLUDED.observacao
          WHERE public.parceiro_comissoes.status NOT IN ('fechado','pago');
        v_n_rec := v_n_rec + 1;
      ELSIF v_t.plano_publico IS FALSE AND v_t.sub_status IS NOT NULL THEN
        INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, base_cents, percentual, valor_cents, status, observacao)
        VALUES (v_p.id, v_t.id, v_comp, 'recorrente', 0, v_pct, 0, 'previsto', 'Plano interno ou não público: não gera comissão')
        ON CONFLICT (parceiro_id, coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), competencia, tipo, coalesce(evento,'')) DO NOTHING;
      END IF;

      -- Liberação da retenção de qualidade quando a 3ª mensalidade compensa
      IF v_t.terceira_mensalidade_compensada_em IS NOT NULL THEN
        UPDATE public.parceiro_comissoes SET status = 'previsto', observacao = observacao || ' · liberada em ' || to_char(v_t.terceira_mensalidade_compensada_em,'DD/MM/YYYY')
        WHERE parceiro_id = v_p.id AND tenant_id = v_t.id AND tipo = 'retencao' AND status = 'retido';
      END IF;

      -- SETUP em 3 parcelas (participação da trilha/nível; Operador = fatura direto, não passa pela YE)
      v_setup := coalesce(v_t.setup_valor_cents, 0);
      IF v_setup > 0 AND v_nivel.setup_participacao_pct > 0 AND v_p.trilha <> 'operador' THEN
        IF v_t.primeira_mensalidade_compensada_em IS NOT NULL AND v_t.primeira_mensalidade_compensada_em <= v_fim
           AND NOT EXISTS (SELECT 1 FROM public.parceiro_comissoes c WHERE c.parceiro_id = v_p.id AND c.tenant_id = v_t.id AND c.tipo = 'setup' AND c.evento = 'setup_parcela1') THEN
          INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, evento, base_cents, percentual, valor_cents, status, observacao)
          VALUES (v_p.id, v_t.id, v_comp, 'setup', 'setup_parcela1', v_setup, v_nivel.setup_participacao_pct,
                  round(v_setup * v_nivel.setup_participacao_pct / 100 * public.parceiro_cfg('setup_parcela1_pct',30) / 100), 'previsto',
                  '1ª parcela do setup (' || public.parceiro_cfg('setup_parcela1_pct',30) || '%) — 1ª mensalidade compensada em ' || to_char(v_t.primeira_mensalidade_compensada_em,'DD/MM/YYYY'));
          v_n_setup := v_n_setup + 1;
        END IF;
        IF v_t.go_live_homologado_em IS NOT NULL AND v_t.go_live_homologado_em <= v_fim AND v_t.primeira_mensalidade_compensada_em IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM public.parceiro_comissoes c WHERE c.parceiro_id = v_p.id AND c.tenant_id = v_t.id AND c.tipo = 'setup' AND c.evento = 'setup_parcela2') THEN
          INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, evento, base_cents, percentual, valor_cents, status, observacao)
          VALUES (v_p.id, v_t.id, v_comp, 'setup', 'setup_parcela2', v_setup, v_nivel.setup_participacao_pct,
                  round(v_setup * v_nivel.setup_participacao_pct / 100 * public.parceiro_cfg('setup_parcela2_pct',40) / 100), 'previsto',
                  '2ª parcela do setup (' || public.parceiro_cfg('setup_parcela2_pct',40) || '%) — go-live homologado em ' || to_char(v_t.go_live_homologado_em,'DD/MM/YYYY'));
          v_n_setup := v_n_setup + 1;
          -- Bônus de velocidade: go-live em até N dias da assinatura
          IF v_t.contrato_assinado_em IS NOT NULL AND v_t.go_live_homologado_em - v_t.contrato_assinado_em <= public.parceiro_cfg('bonus_velocidade_dias',15)::int THEN
            SELECT * INTO v_ev FROM public.parceiro_eventos_remuneracao WHERE trilha = v_p.trilha AND evento = 'bonus_velocidade' AND ativo;
            IF v_ev.id IS NOT NULL THEN
              INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, evento, base_cents, percentual, valor_cents, status, observacao)
              VALUES (v_p.id, v_t.id, v_comp, 'evento', 'bonus_velocidade', v_setup, v_ev.percentual_setup,
                      v_ev.valor_fixo_cents + round(v_setup * v_nivel.setup_participacao_pct / 100 * v_ev.percentual_setup / 100), 'previsto',
                      'Bônus de velocidade: go-live em ' || (v_t.go_live_homologado_em - v_t.contrato_assinado_em) || ' dias')
              ON CONFLICT DO NOTHING;
              v_n_bonus := v_n_bonus + 1;
            END IF;
          END IF;
        END IF;
        IF v_t.terceira_mensalidade_compensada_em IS NOT NULL AND v_t.terceira_mensalidade_compensada_em <= v_fim AND v_t.sub_status = 'active'
           AND NOT EXISTS (SELECT 1 FROM public.parceiro_comissoes c WHERE c.parceiro_id = v_p.id AND c.tenant_id = v_t.id AND c.tipo = 'setup' AND c.evento = 'setup_parcela3') THEN
          INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, evento, base_cents, percentual, valor_cents, status, observacao)
          VALUES (v_p.id, v_t.id, v_comp, 'setup', 'setup_parcela3', v_setup, v_nivel.setup_participacao_pct,
                  round(v_setup * v_nivel.setup_participacao_pct / 100 * public.parceiro_cfg('setup_parcela3_pct',30) / 100), 'previsto',
                  '3ª parcela do setup (' || public.parceiro_cfg('setup_parcela3_pct',30) || '%) — 3ª mensalidade compensada com a conta ativa');
          v_n_setup := v_n_setup + 1;
        END IF;
      END IF;

      -- Bônus de retenção 90 dias (todas as trilhas; % do setup total do cliente)
      IF v_setup > 0 AND v_t.go_live_homologado_em IS NOT NULL AND v_t.go_live_homologado_em + 90 <= v_fim AND v_t.sub_status = 'active'
         AND NOT EXISTS (SELECT 1 FROM public.parceiro_comissoes c WHERE c.parceiro_id = v_p.id AND c.tenant_id = v_t.id AND c.evento = 'bonus_retencao_90d') THEN
        SELECT * INTO v_ev FROM public.parceiro_eventos_remuneracao WHERE trilha = v_p.trilha AND evento = 'bonus_retencao_90d' AND ativo;
        IF v_ev.id IS NOT NULL THEN
          INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, evento, base_cents, percentual, valor_cents, status, observacao)
          VALUES (v_p.id, v_t.id, v_comp, 'evento', 'bonus_retencao_90d', v_setup, v_ev.percentual_setup,
                  v_ev.valor_fixo_cents + round(v_setup * v_ev.percentual_setup / 100), 'previsto',
                  'Bônus de retenção: cliente ativo no 90º dia após o go-live (' || to_char(v_t.go_live_homologado_em + 90,'DD/MM/YYYY') || ')');
          v_n_bonus := v_n_bonus + 1;
        END IF;
      END IF;

      -- Ciclo: nasce no go-live; renovação automática com bônus 2×
      IF v_t.go_live_homologado_em IS NOT NULL AND v_t.ciclo_fim IS NULL THEN
        UPDATE public.subscriptions SET ciclo_meses = coalesce(ciclo_meses, v_ciclo), ciclo_inicio = v_t.go_live_homologado_em,
               ciclo_fim = v_t.go_live_homologado_em + (coalesce(ciclo_meses, v_ciclo) || ' months')::interval WHERE tenant_id = v_t.id;
      ELSIF v_t.ciclo_fim IS NOT NULL AND v_t.ciclo_fim BETWEEN v_comp AND v_fim AND v_t.sub_status = 'active' AND v_p.status = 'ativo' AND v_base > 0 THEN
        INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, evento, base_cents, percentual, valor_cents, status, observacao)
        VALUES (v_p.id, v_t.id, v_comp, 'bonus_renovacao', 'renovacao', v_base, v_pct,
                round(v_base * v_pct / 100 * coalesce(v_nivel.bonus_renovacao_multiplicador, public.parceiro_cfg('bonus_renovacao_mult',2))), 'previsto',
                'Renovação de ciclo em ' || to_char(v_t.ciclo_fim,'DD/MM/YYYY') || ' · novo ciclo de ' || v_ciclo || ' meses')
        ON CONFLICT (parceiro_id, coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), competencia, tipo, coalesce(evento,'')) DO NOTHING;
        IF p_fechar THEN
          UPDATE public.subscriptions SET ciclo_inicio = ciclo_fim, ciclo_fim = ciclo_fim + (coalesce(ciclo_meses, v_ciclo) || ' months')::interval WHERE tenant_id = v_t.id;
        END IF;
        v_n_bonus := v_n_bonus + 1;
      END IF;

      -- Clawback: cancelamento entre o 4º e o 12º mês devolve % do setup recebido
      IF v_t.sub_status = 'canceled' AND v_t.go_live_homologado_em IS NOT NULL AND v_setup > 0
         AND (EXTRACT(year FROM age(coalesce(v_t.cancelado_em, v_fim), v_t.go_live_homologado_em)) * 12 + EXTRACT(month FROM age(coalesce(v_t.cancelado_em, v_fim), v_t.go_live_homologado_em)))
             BETWEEN public.parceiro_cfg('clawback_mes_inicio',4) AND public.parceiro_cfg('clawback_mes_fim',12)
         AND NOT EXISTS (SELECT 1 FROM public.parceiro_comissoes c WHERE c.parceiro_id = v_p.id AND c.tenant_id = v_t.id AND c.tipo = 'clawback') THEN
        SELECT coalesce(sum(valor_cents),0) INTO v_val FROM public.parceiro_comissoes WHERE parceiro_id = v_p.id AND tenant_id = v_t.id AND tipo = 'setup' AND status IN ('fechado','pago');
        IF v_val > 0 THEN
          INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, evento, base_cents, percentual, valor_cents, status, observacao)
          VALUES (v_p.id, v_t.id, v_comp, 'clawback', 'clawback_setup', v_val, public.parceiro_cfg('clawback_pct',50),
                  -round(v_val * public.parceiro_cfg('clawback_pct',50) / 100), 'previsto',
                  'Clawback: cancelamento entre o 4º e o 12º mês devolve ' || public.parceiro_cfg('clawback_pct',50) || '% do setup recebido (não se aplica a falha comprovada do produto — ajuste manual)');
          v_n_claw := v_n_claw + 1;
        END IF;
      END IF;

      IF v_t.go_live_homologado_em BETWEEN v_comp AND v_fim THEN v_ativacoes_mes := v_ativacoes_mes + 1; END IF;
    END LOOP;

    -- Bônus de volume: N+ ativações no mês → % sobre os setups do mês (só no fechamento GLOBAL)
    IF p_tenant IS NULL AND v_ativacoes_mes >= public.parceiro_cfg('bonus_volume_ativacoes',3)::int THEN
      SELECT * INTO v_ev FROM public.parceiro_eventos_remuneracao WHERE trilha = v_p.trilha AND evento = 'bonus_volume' AND ativo;
      SELECT coalesce(sum(valor_cents),0) INTO v_val FROM public.parceiro_comissoes WHERE parceiro_id = v_p.id AND competencia = v_comp AND tipo = 'setup';
      IF v_ev.id IS NOT NULL AND v_val > 0 THEN
        INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, evento, base_cents, percentual, valor_cents, status, observacao)
        VALUES (v_p.id, NULL, v_comp, 'evento', 'bonus_volume', v_val, v_ev.percentual_setup, round(v_val * v_ev.percentual_setup / 100), 'previsto',
                'Bônus de volume: ' || v_ativacoes_mes || ' ativações no mês')
        ON CONFLICT DO NOTHING;
        v_n_bonus := v_n_bonus + 1;
      END IF;
    END IF;

    -- Fast Start: N ativações nos primeiros D dias de credenciamento (uma vez; só no fechamento GLOBAL)
    SELECT count(*) INTO v_golives_fast FROM public.tenants t JOIN public.subscriptions s ON s.tenant_id = t.id
    WHERE t.parceiro_id = v_p.id AND s.go_live_homologado_em IS NOT NULL
      AND s.go_live_homologado_em <= v_p.parceiro_desde + public.parceiro_cfg('fast_start_dias',90)::int AND s.go_live_homologado_em <= v_fim;
    IF p_tenant IS NULL AND v_golives_fast >= public.parceiro_cfg('fast_start_ativacoes',3)::int
       AND NOT EXISTS (SELECT 1 FROM public.parceiro_comissoes c WHERE c.parceiro_id = v_p.id AND c.evento = 'fast_start') THEN
      SELECT * INTO v_ev FROM public.parceiro_eventos_remuneracao WHERE trilha = v_p.trilha AND evento = 'fast_start' AND ativo;
      IF v_ev.id IS NOT NULL THEN
        INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, evento, base_cents, percentual, valor_cents, status, observacao)
        VALUES (v_p.id, NULL, v_comp, 'evento', 'fast_start', 0, 0, coalesce(nullif(v_ev.valor_fixo_cents,0), public.parceiro_cfg('fast_start_cents',200000)::bigint), 'previsto',
                'Fast Start: ' || v_golives_fast || ' empresas ativadas nos primeiros ' || public.parceiro_cfg('fast_start_dias',90) || ' dias');
        v_n_bonus := v_n_bonus + 1;
      END IF;
    END IF;

    -- Promoção imediata; nunca rebaixa (proteção de 12 meses / data-base anual)
    SELECT * INTO v_prox FROM public.parceiro_niveis
    WHERE trilha = v_p.trilha AND ativo AND ordem > coalesce(v_nivel.ordem, 0) AND mrr_minimo_cents <= v_mrr_total ORDER BY ordem DESC LIMIT 1;
    IF v_prox.id IS NOT NULL THEN
      UPDATE public.parceiros SET nivel_id = v_prox.id, nivel_conquistado_em = CURRENT_DATE WHERE id = v_p.id;
      v_n_promo := v_n_promo + 1;
    END IF;
  END LOOP;

  -- Override do Master Regional sobre o MRR líquido dos sub-parceiros (só no fechamento GLOBAL)
  IF p_tenant IS NULL THEN
    FOR v_p IN SELECT m.* FROM public.parceiros m WHERE m.master_regional AND m.status = 'ativo' LOOP
      SELECT coalesce(sum(c.base_cents),0) INTO v_base FROM public.parceiro_comissoes c JOIN public.parceiros s ON s.id = c.parceiro_id
      WHERE s.master_parceiro_id = v_p.id AND c.competencia = v_comp AND c.tipo = 'recorrente';
      IF v_base > 0 THEN
        INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, evento, base_cents, percentual, valor_cents, status, observacao)
        VALUES (v_p.id, NULL, v_comp, 'override', 'master_regional', v_base, public.parceiro_cfg('master_override_pct',5), round(v_base * public.parceiro_cfg('master_override_pct',5) / 100), 'previsto', 'Override Master Regional sobre os sub-parceiros')
        ON CONFLICT (parceiro_id, coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), competencia, tipo, coalesce(evento,'')) DO UPDATE SET base_cents = EXCLUDED.base_cents, valor_cents = EXCLUDED.valor_cents
          WHERE public.parceiro_comissoes.status NOT IN ('fechado','pago');
      END IF;
    END LOOP;
  END IF;

  IF p_fechar THEN
    UPDATE public.parceiro_comissoes SET status = 'fechado', fechado_em = now() WHERE competencia = v_comp AND status = 'previsto'
      AND (p_tenant IS NULL OR tenant_id = p_tenant);
  END IF;

  RETURN jsonb_build_object('competencia', to_char(v_comp,'YYYY-MM'), 'parceiros', v_n_parc, 'recorrentes', v_n_rec,
    'setup_parcelas', v_n_setup, 'bonus', v_n_bonus, 'clawbacks', v_n_claw, 'promocoes', v_n_promo, 'fechado', p_fechar,
    'compromisso_ciclo_cents', (SELECT coalesce(sum(c.valor_cents),0) FROM public.parceiro_comissoes c WHERE c.competencia = v_comp AND c.tipo = 'recorrente') * v_ciclo);
END $parceiro_fechar_competencia$;

-- Re-concede o EXECUTE (o grant antigo era na assinatura de 2 args, agora removida).
GRANT EXECUTE ON FUNCTION public.parceiro_fechar_competencia(date, boolean, uuid) TO authenticated;

-- ── qa_pgp_cenario idempotente (select-then-insert/update dos parceiros QA) ──
CREATE OR REPLACE FUNCTION public.qa_pgp_cenario(OUT o_parceiro uuid, OUT o_impl uuid, OUT o_tenant_pub uuid)
RETURNS record LANGUAGE plpgsql AS $$
DECLARE v_plano uuid; v_uid uuid := gen_random_uuid();
BEGIN
  PERFORM public.qa_modo_ligar();
  o_tenant_pub := public.qa_sandbox_tenant_id();
  IF o_tenant_pub IS NULL THEN RAISE EXCEPTION 'Cercado qa-sandbox não existe neste ambiente'; END IF;

  SELECT id INTO o_parceiro FROM public.parceiros WHERE codigo = 'QA-PGP-ORIG';
  IF o_parceiro IS NULL THEN
    INSERT INTO public.parceiros (codigo, nome, tipo_parceiro, trilha, status) VALUES ('QA-PGP-ORIG', 'QA Origem', 'representante', 'representante', 'ativo') RETURNING id INTO o_parceiro;
  ELSE
    UPDATE public.parceiros SET nome='QA Origem', tipo_parceiro='representante', trilha='representante', status='ativo' WHERE id = o_parceiro;
  END IF;

  SELECT id INTO o_impl FROM public.parceiros WHERE codigo = 'QA-PGP-IMPL';
  IF o_impl IS NULL THEN
    INSERT INTO public.parceiros (codigo, nome, tipo_parceiro, trilha, status) VALUES ('QA-PGP-IMPL', 'QA Operador', 'implantador', 'operador', 'ativo') RETURNING id INTO o_impl;
  ELSE
    UPDATE public.parceiros SET nome='QA Operador', tipo_parceiro='implantador', trilha='operador', status='ativo' WHERE id = o_impl;
  END IF;

  SELECT id INTO v_plano FROM public.plans WHERE code = 'performance';
  UPDATE public.tenants SET parceiro_id = o_parceiro, implantador_parceiro_id = o_impl, originado_em = now() - interval '90 days', ativo = true WHERE id = o_tenant_pub;
  INSERT INTO public.subscriptions (tenant_id, plan_id, status) VALUES (o_tenant_pub, v_plano, 'active')
  ON CONFLICT (tenant_id) DO UPDATE SET plan_id = EXCLUDED.plan_id, status = 'active';
  UPDATE public.subscriptions SET setup_valor_cents = 120000, contrato_assinado_em = CURRENT_DATE - 60,
    primeira_mensalidade_compensada_em = CURRENT_DATE - 50, go_live_homologado_em = CURRENT_DATE - 45,
    terceira_mensalidade_compensada_em = NULL, cancelado_em = NULL, ciclo_inicio = NULL, ciclo_fim = NULL, desconto_pct = 0
  WHERE tenant_id = o_tenant_pub;
  INSERT INTO auth.users (id, email) VALUES (v_uid, 'qa-pgp-' || left(v_uid::text,8) || '@exemplo.test');
  INSERT INTO public.profiles (user_id, tenant_id, nome_completo, onboarding_concluido) VALUES (v_uid, o_tenant_pub, 'QA Owner', true);
  DELETE FROM public.parceiro_comissoes WHERE tenant_id = o_tenant_pub;
  DELETE FROM public.parceiro_mrr_snapshots WHERE tenant_id = o_tenant_pub;
END $$;

-- ── As 3 rotinas passam o cercado ao motor (escopo) ─────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_pgp_010()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; c record; v_int bigint; v_pub bigint; v_tester uuid;
BEGIN
  SELECT * INTO c FROM public.qa_pgp_cenario();
  r.passo_ordem := 1; r.passo_acao := 'Fechar competência com o cliente em plano público';
  r.esperado := 'Comissão recorrente > 0';
  PERFORM public.parceiro_fechar_competencia(CURRENT_DATE, false, c.o_tenant_pub);
  SELECT valor_cents INTO v_pub FROM public.parceiro_comissoes WHERE parceiro_id = c.o_parceiro AND tenant_id = c.o_tenant_pub AND tipo = 'recorrente';

  r.passo_ordem := 2; r.passo_acao := 'Trocar o mesmo cliente para plano interno (não público) e fechar de novo';
  r.esperado := 'Comissão recorrente = 0 com observação';
  SELECT id INTO v_tester FROM public.plans WHERE is_public = false ORDER BY tier DESC LIMIT 1;
  IF v_tester IS NULL THEN r.situacao := 'nao_implementado'; r.obtido := 'Não há plano interno (is_public = false) neste ambiente para testar.'; RETURN r; END IF;
  DELETE FROM public.parceiro_comissoes WHERE tenant_id = c.o_tenant_pub;
  UPDATE public.subscriptions SET plan_id = v_tester WHERE tenant_id = c.o_tenant_pub;
  PERFORM public.parceiro_fechar_competencia(CURRENT_DATE, false, c.o_tenant_pub);
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
  PERFORM public.parceiro_fechar_competencia(CURRENT_DATE, true, c.o_tenant_pub);
  SELECT count(*), sum(valor_cents) INTO n1, s1 FROM public.parceiro_comissoes WHERE parceiro_id IN (c.o_parceiro, c.o_impl);
  PERFORM public.parceiro_fechar_competencia(CURRENT_DATE, true, c.o_tenant_pub);
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
DECLARE r public.qa_retorno; c record; v_n int; v_p1 bigint; v_p2 bigint; v_esp1 bigint; v_esp2 bigint; v_part numeric; v_p3 int;
BEGIN
  SELECT * INTO c FROM public.qa_pgp_cenario();
  SELECT n.setup_participacao_pct INTO v_part FROM public.parceiros p JOIN public.parceiro_niveis n ON n.id = p.nivel_id WHERE p.id = c.o_parceiro;
  r.passo_ordem := 1; r.passo_acao := 'Fechar duas vezes: Representante nível Foco, setup R$ 1.200, 1ª mensalidade compensada e go-live homologado, 3ª ainda não';
  r.esperado := format('Parcela 1 = 1200 × %s%% × %s%%; parcela 2 = 1200 × %s%% × %s%%; sem parcela 3; sem duplicar', v_part, public.parceiro_cfg('setup_parcela1_pct',30), v_part, public.parceiro_cfg('setup_parcela2_pct',40));
  PERFORM public.parceiro_fechar_competencia(CURRENT_DATE, false, c.o_tenant_pub);
  PERFORM public.parceiro_fechar_competencia(CURRENT_DATE, false, c.o_tenant_pub);
  SELECT count(*) INTO v_n FROM public.parceiro_comissoes WHERE parceiro_id = c.o_parceiro AND tenant_id = c.o_tenant_pub AND tipo = 'setup';
  SELECT valor_cents INTO v_p1 FROM public.parceiro_comissoes WHERE parceiro_id = c.o_parceiro AND tenant_id = c.o_tenant_pub AND evento = 'setup_parcela1';
  SELECT valor_cents INTO v_p2 FROM public.parceiro_comissoes WHERE parceiro_id = c.o_parceiro AND tenant_id = c.o_tenant_pub AND evento = 'setup_parcela2';
  SELECT count(*) INTO v_p3 FROM public.parceiro_comissoes WHERE parceiro_id = c.o_parceiro AND tenant_id = c.o_tenant_pub AND evento = 'setup_parcela3';
  v_esp1 := round(120000 * v_part / 100 * public.parceiro_cfg('setup_parcela1_pct',30) / 100);
  v_esp2 := round(120000 * v_part / 100 * public.parceiro_cfg('setup_parcela2_pct',40) / 100);
  IF v_n = 2 AND v_p1 = v_esp1 AND v_p2 = v_esp2 AND v_p3 = 0 THEN
    r.situacao := 'passou'; r.obtido := format('parcela 1 = %s, parcela 2 = %s centavos; parcela 3 aguardando a 3ª mensalidade; sem duplicidade.', v_p1, v_p2);
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: %s linha(s) de setup; p1 = %s (esp. %s); p2 = %s (esp. %s); p3 = %s (esp. 0).', v_n, v_p1, v_esp1, v_p2, v_esp2, v_p3);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ════════════════════ CONFERÊNCIA (única — esperado tudo 'ok') ════════════════
WITH alvo(item, presente) AS (
  VALUES
    ('PGP · motor com filtro de tenant (3 args) e sem a sobrecarga de 2 args',
       (to_regprocedure('public.parceiro_fechar_competencia(date,boolean,uuid)') IS NOT NULL
        AND to_regprocedure('public.parceiro_fechar_competencia(date,boolean)') IS NULL)),
    ('PGP-010 · rotina escopada ao cercado',
       (pg_get_functiondef('public.qa_caso_pgp_010()'::regprocedure) ~* 'c\.o_tenant_pub')),
    ('PGP-012 · rotina escopada ao cercado',
       (pg_get_functiondef('public.qa_caso_pgp_012()'::regprocedure) ~* 'c\.o_tenant_pub')),
    ('PGP-013 · rotina escopada ao cercado',
       (pg_get_functiondef('public.qa_caso_pgp_013()'::regprocedure) ~* 'c\.o_tenant_pub')),
    ('PGP · cenário idempotente (não duplica QA-PGP)',
       (pg_get_functiondef('public.qa_pgp_cenario()'::regprocedure) ~* 'WHERE codigo = ''QA-PGP-ORIG'''))
)
SELECT item, CASE WHEN presente THEN 'ok' ELSE 'FALTOU' END AS situacao FROM alvo ORDER BY item;
