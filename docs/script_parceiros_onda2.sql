-- =====================================================================
-- PROGRAMA DE PARCEIROS · ONDA 2 · SCRIPT DE ENTREGA · Área do Parceiro
-- Cole no SQL Editor de cada ambiente (Teste → Homologação → Produção),
-- avançando só depois que o anterior devolver OK. Requer a Onda 1
-- (docs/script_parceiros_onda1.sql) aplicada.
--
-- O que faz: estágio derivado da carteira (regra pura + leitura por
-- tenant), função do portal do parceiro, autocadastro de quem já tem conta,
-- migração (cópia) dos afiliados do Marketplace para o programa, rotina
-- QA PGP-011 e pontes dos testes de tela. Só cria/insere: a migração de
-- afiliados COPIA e não apaga a origem, por isso não gera tabela backup_.
-- Idempotente. Corresponde à migration 20260904130000_parceiros_portal.sql.
-- As telas (site, /parceiro) chegam pelo Publicar no Lovable.
-- =====================================================================

-- =====================================================================
-- PROGRAMA DE PARCEIROS · ONDA 2 · Área do Parceiro (fora do sistema)
--
-- O parceiro entra pelo site (/parceiros/entrar) e cai em /parceiro, sem
-- perfil de tenant. Tudo o que ele vê passa por funções SECURITY DEFINER
-- que devolvem só colunas fechadas (nome fantasia do cliente, plano, MRR,
-- estágio, datas e a própria comissão). Nenhum dado de pessoa física.
--
-- Entra aqui:
--   * estágio derivado (função pura + wrapper por tenant), PGP-011;
--   * parceiro_meu_portal(): tudo que a tela do parceiro mostra;
--   * parceiro_cadastrar(): autocadastro de quem já tem conta;
--   * migração dos afiliados do Marketplace para o programa (decisão 03/09);
--   * pontes qa_cobertura_e2e dos casos de tela do portal.
-- Só cria/insere; a migração de afiliados só copia (não apaga a origem).
-- =====================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- 1) Estágio derivado — regra pura (testável) e leitura por tenant
--    Precedência: Churn > Ativo > Go-live > Implantação > Contrato > Proposta > Lead
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.parceiro_estagio_calc(
  p_tenant_existe boolean, p_tenant_ativo boolean, p_sub_status text,
  p_contrato_assinado boolean, p_onboarding_concluido boolean, p_go_live_em timestamptz,
  p_lead_status text, p_contrato_enviado boolean DEFAULT false)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $parceiro_estagio_calc$
  SELECT CASE
    WHEN p_tenant_existe AND (coalesce(p_sub_status,'') = 'canceled' OR p_tenant_ativo IS FALSE) THEN 'churn'
    WHEN p_tenant_existe AND coalesce(p_sub_status,'') = 'active'
         AND p_onboarding_concluido AND coalesce(p_go_live_em, now() - interval '31 days') <= now() - interval '30 days' THEN 'ativo'
    WHEN p_tenant_existe AND p_onboarding_concluido THEN 'go_live'
    WHEN p_tenant_existe THEN 'implantacao'
    WHEN p_contrato_assinado THEN 'contrato'
    WHEN coalesce(p_lead_status,'') IN ('proposta','negociacao') OR p_contrato_enviado THEN 'proposta'
    ELSE 'lead'
  END
$parceiro_estagio_calc$;
COMMENT ON FUNCTION public.parceiro_estagio_calc IS
  'Regra pura do estágio da carteira do parceiro (PGP-011). O wrapper por tenant só coleta os fatos.';

CREATE OR REPLACE FUNCTION public.parceiro_estagio_tenant(p_tenant_id uuid)
RETURNS text
LANGUAGE sql STABLE
SET search_path = public
AS $parceiro_estagio_tenant$
  SELECT public.parceiro_estagio_calc(
    true,
    t.ativo,
    (SELECT s.status FROM public.subscriptions s WHERE s.tenant_id = t.id),
    EXISTS (SELECT 1 FROM public.programa_validador_clientes c
            JOIN public.programa_validador_contratos k ON k.cliente_id = c.id
            WHERE c.tenant_id = t.id AND k.status = 'assinado'),
    EXISTS (SELECT 1 FROM public.profiles p WHERE p.tenant_id = t.id AND p.onboarding_concluido),
    (SELECT min(p.updated_at) FROM public.profiles p WHERE p.tenant_id = t.id AND p.onboarding_concluido),
    NULL, false)
  FROM public.tenants t WHERE t.id = p_tenant_id
$parceiro_estagio_tenant$;

-- MRR de tabela do tenant (plano público + add-ons ativos), em centavos.
CREATE OR REPLACE FUNCTION public.parceiro_mrr_tenant(p_tenant_id uuid)
RETURNS bigint
LANGUAGE sql STABLE
SET search_path = public
AS $parceiro_mrr_tenant$
  SELECT coalesce((
      SELECT pp.amount_cents
      FROM public.subscriptions s
      JOIN public.plans pl ON pl.id = s.plan_id AND pl.is_public
      JOIN public.plan_prices pp ON pp.plan_id = pl.id AND pp.period = 'monthly' AND pp.is_active
      WHERE s.tenant_id = p_tenant_id AND s.status IN ('active','trialing','past_due')
      ORDER BY pp.created_at LIMIT 1), 0)
    + coalesce((SELECT sum(a.quantity * a.unit_price_cents) FROM public.subscription_addons a
                WHERE a.tenant_id = p_tenant_id AND a.ativo), 0)
$parceiro_mrr_tenant$;

-- ---------------------------------------------------------------------
-- 2) O portal inteiro numa chamada (só do próprio parceiro)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.parceiro_meu_portal()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $parceiro_meu_portal$
DECLARE
  v_pid uuid := public.parceiro_meu_id();
  v_p public.parceiros%ROWTYPE;
  v_nivel public.parceiro_niveis%ROWTYPE;
  v_prox public.parceiro_niveis%ROWTYPE;
  v_pct numeric;
  v_mrr bigint;
  v_carteira jsonb; v_links jsonb; v_extrato jsonb; v_renov jsonb;
  v_leads90 int; v_prop90 int; v_contr90 int; v_ativos int; v_impl int;
  v_mp uuid;
BEGIN
  IF v_pid IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO v_p FROM public.parceiros WHERE id = v_pid;

  -- Uma identidade, dois papéis: se o mesmo usuário já é profissional do
  -- Marketplace, liga os dois cadastros (sem criar nada).
  IF v_p.marketplace_profissional_id IS NULL THEN
    SELECT id INTO v_mp FROM public.marketplace_profissionais WHERE user_id = auth.uid() LIMIT 1;
    IF v_mp IS NOT NULL THEN
      UPDATE public.parceiros SET marketplace_profissional_id = v_mp WHERE id = v_pid;
      v_p.marketplace_profissional_id := v_mp;
    END IF;
  END IF;

  SELECT * INTO v_nivel FROM public.parceiro_niveis WHERE id = v_p.nivel_id;
  IF v_nivel.id IS NULL THEN
    SELECT * INTO v_nivel FROM public.parceiro_niveis WHERE trilha = v_p.trilha AND ativo ORDER BY ordem LIMIT 1;
  END IF;
  SELECT * INTO v_prox FROM public.parceiro_niveis
  WHERE trilha = v_p.trilha AND ativo AND ordem > coalesce(v_nivel.ordem, 0) ORDER BY ordem LIMIT 1;
  v_pct := coalesce(v_p.percentual_comissao, v_nivel.percentual_link, 25);

  -- Carteira: empresas originadas/implantadas + leads ainda sem empresa
  WITH emp AS (
    SELECT t.id, t.nome, t.originado_em, t.parceiro_id, t.implantador_parceiro_id,
           public.parceiro_estagio_tenant(t.id) AS estagio,
           public.parceiro_mrr_tenant(t.id) AS mrr_cents,
           (SELECT pl.name FROM public.subscriptions s JOIN public.plans pl ON pl.id = s.plan_id WHERE s.tenant_id = t.id) AS plano,
           (SELECT pl.is_public FROM public.subscriptions s JOIN public.plans pl ON pl.id = s.plan_id WHERE s.tenant_id = t.id) AS plano_publico,
           (SELECT s.ciclo_fim FROM public.subscriptions s WHERE s.tenant_id = t.id) AS ciclo_fim,
           (SELECT count(*) FROM public.admissoes a WHERE a.tenant_id = t.id AND a.status = 'concluido') AS colaboradores
    FROM public.tenants t
    WHERE t.parceiro_id = v_pid OR t.implantador_parceiro_id = v_pid
  ), leads AS (
    SELECT l.id, coalesce(nullif(l.empresa,''), l.nome) AS nome, l.status::text AS status, l.created_at,
           l.proxima_acao_data, l.proxima_acao_descricao, l.atribuicao
    FROM public.leads l
    WHERE l.parceiro_id = v_pid AND l.deleted_at IS NULL AND l.tenant_convertido_id IS NULL
      AND l.status::text NOT IN ('perdido')
  )
  SELECT jsonb_agg(x ORDER BY x->>'ordem', x->>'nome') INTO v_carteira FROM (
    SELECT jsonb_build_object(
      'tipo', 'empresa', 'id', e.id, 'nome', e.nome, 'plano', e.plano,
      'mrr_cents', CASE WHEN coalesce(e.plano_publico, false) THEN e.mrr_cents ELSE 0 END,
      'estagio', e.estagio,
      'papel', CASE WHEN e.parceiro_id = v_pid AND e.implantador_parceiro_id = v_pid THEN 'origem+implantacao'
                    WHEN e.parceiro_id = v_pid THEN 'origem' ELSE 'implantacao' END,
      'proximo_passo', CASE e.estagio
          WHEN 'ativo' THEN CASE WHEN e.ciclo_fim IS NOT NULL THEN 'Renova ciclo em ' || to_char(e.ciclo_fim, 'DD/MM/YYYY') ELSE 'Ciclo mensal em dia' END
          WHEN 'go_live' THEN 'Onboarding concluído · início do ciclo'
          WHEN 'implantacao' THEN e.colaboradores || ' colaborador(es) cadastrado(s)'
          WHEN 'churn' THEN 'Assinatura encerrada'
          ELSE '' END,
      'comissao_mes_cents', CASE WHEN e.estagio = 'ativo' AND e.parceiro_id = v_pid AND coalesce(e.plano_publico,false)
                                 THEN round(e.mrr_cents * v_pct / 100) ELSE 0 END,
      'aviso', CASE WHEN e.plano IS NOT NULL AND NOT coalesce(e.plano_publico,false) THEN 'Plano interno: não gera comissão' END,
      'ciclo_fim', e.ciclo_fim, 'desde', e.originado_em,
      'ordem', CASE e.estagio WHEN 'ativo' THEN '1' WHEN 'go_live' THEN '2' WHEN 'implantacao' THEN '3' WHEN 'churn' THEN '9' ELSE '5' END
    ) AS x FROM emp e
    UNION ALL
    SELECT jsonb_build_object(
      'tipo', 'lead', 'id', l.id, 'nome', l.nome, 'plano', NULL, 'mrr_cents', 0,
      'estagio', public.parceiro_estagio_calc(false, NULL, NULL, false, false, NULL, l.status, false),
      'papel', 'origem',
      'proximo_passo', CASE WHEN l.proxima_acao_data IS NOT NULL
                            THEN coalesce(l.proxima_acao_descricao, 'Follow-up') || ' em ' || to_char(l.proxima_acao_data, 'DD/MM')
                            ELSE 'Capturado em ' || to_char(l.created_at, 'DD/MM') || CASE WHEN l.atribuicao = 'link' THEN ' via link' ELSE '' END END,
      'comissao_mes_cents', 0, 'aviso', NULL, 'ciclo_fim', NULL, 'desde', l.created_at,
      'ordem', CASE WHEN l.status IN ('proposta','negociacao') THEN '6' ELSE '7' END
    ) FROM leads l
  ) q;

  SELECT coalesce(sum((c->>'mrr_cents')::bigint), 0) INTO v_mrr
  FROM jsonb_array_elements(coalesce(v_carteira,'[]'::jsonb)) c
  WHERE c->>'tipo' = 'empresa' AND c->>'estagio' IN ('ativo','go_live') AND c->>'papel' <> 'implantacao';

  SELECT count(*) FILTER (WHERE c->>'estagio' = 'ativo'), count(*) FILTER (WHERE c->>'estagio' IN ('implantacao','go_live'))
    INTO v_ativos, v_impl
  FROM jsonb_array_elements(coalesce(v_carteira,'[]'::jsonb)) c WHERE c->>'tipo' = 'empresa';

  -- Funil dos últimos 90 dias
  SELECT count(*), count(*) FILTER (WHERE l.status::text IN ('proposta','negociacao','convertido'))
    INTO v_leads90, v_prop90
  FROM public.leads l WHERE l.parceiro_id = v_pid AND l.deleted_at IS NULL AND l.created_at >= now() - interval '90 days';
  SELECT count(*) INTO v_contr90 FROM public.tenants t WHERE t.parceiro_id = v_pid AND t.originado_em >= now() - interval '90 days';

  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', k.id, 'codigo', k.codigo, 'campanha', k.campanha, 'ativo', k.ativo,
      'cliques', (SELECT count(*) FROM public.parceiro_link_cliques c WHERE c.link_id = k.id),
      'leads', (SELECT count(*) FROM public.leads l WHERE l.parceiro_link_id = k.id AND l.deleted_at IS NULL))
    ORDER BY k.campanha = 'principal' DESC, k.created_at), '[]'::jsonb) INTO v_links
  FROM public.parceiro_links k WHERE k.parceiro_id = v_pid AND k.ativo;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'competencia', to_char(c.competencia, 'YYYY-MM'), 'base_cents', c.base_cents, 'percentual', c.percentual,
      'valor_cents', c.valor_cents, 'status', c.status, 'tipo', c.tipo, 'pago_em', c.pago_em)
    ORDER BY c.competencia DESC), '[]'::jsonb) INTO v_extrato
  FROM (SELECT competencia, sum(base_cents) base_cents, max(percentual) percentual, sum(valor_cents) valor_cents,
               min(status) status, string_agg(DISTINCT tipo, ',') tipo, max(pago_em) pago_em
        FROM public.parceiro_comissoes WHERE parceiro_id = v_pid GROUP BY competencia) c;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'nome', t.nome, 'ciclo_fim', s.ciclo_fim,
      'bonus_cents', round(public.parceiro_mrr_tenant(t.id) * v_pct / 100 * coalesce(v_nivel.bonus_renovacao_multiplicador, 2)))
    ORDER BY s.ciclo_fim), '[]'::jsonb) INTO v_renov
  FROM public.tenants t JOIN public.subscriptions s ON s.tenant_id = t.id
  WHERE t.parceiro_id = v_pid AND s.ciclo_fim IS NOT NULL AND s.ciclo_fim >= CURRENT_DATE AND s.status IN ('active','past_due');

  RETURN jsonb_build_object(
    'parceiro', jsonb_build_object(
      'id', v_p.id, 'codigo', v_p.codigo, 'nome', v_p.nome, 'tipo_parceiro', v_p.tipo_parceiro, 'status', v_p.status,
      'cidade', v_p.cidade, 'uf', v_p.uf, 'parceiro_desde', v_p.parceiro_desde, 'trilha', v_p.trilha,
      'email', v_p.email, 'telefone', v_p.telefone, 'pix_chave', v_p.pix_chave,
      'marketplace_profissional_id', v_p.marketplace_profissional_id),
    'nivel', jsonb_build_object('nome', v_nivel.nome, 'percentual', v_pct, 'bonus_renovacao', v_nivel.bonus_renovacao_multiplicador),
    'proximo_nivel', CASE WHEN v_prox.id IS NULL THEN NULL ELSE jsonb_build_object(
      'nome', v_prox.nome, 'mrr_minimo_cents', v_prox.mrr_minimo_cents, 'percentual', v_prox.percentual_link) END,
    'kpis', jsonb_build_object(
      'mrr_cents', v_mrr,
      'comissao_mes_cents', round(v_mrr * v_pct / 100),
      'ganho_acumulado_cents', (SELECT coalesce(sum(valor_cents),0) FROM public.parceiro_comissoes WHERE parceiro_id = v_pid AND status = 'pago'),
      'clientes_ativos', v_ativos, 'em_implantacao', v_impl,
      'leads_90d', v_leads90, 'propostas_90d', v_prop90, 'contratos_90d', v_contr90,
      'fecha_dia', 25, 'paga_dia', 10),
    'links', v_links,
    'carteira', coalesce(v_carteira, '[]'::jsonb),
    'extrato', v_extrato,
    'renovacoes', v_renov
  );
END $parceiro_meu_portal$;
GRANT EXECUTE ON FUNCTION public.parceiro_meu_portal() TO authenticated;

-- Dados do próprio cadastro que o parceiro pode alterar
CREATE OR REPLACE FUNCTION public.parceiro_meu_perfil_salvar(_dados jsonb)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $parceiro_meu_perfil_salvar$
DECLARE v_pid uuid := public.parceiro_meu_id();
BEGIN
  IF v_pid IS NULL THEN RAISE EXCEPTION 'Sem vínculo com parceiro'; END IF;
  UPDATE public.parceiros SET
    telefone = coalesce(nullif(_dados->>'telefone',''), telefone),
    email = coalesce(nullif(_dados->>'email',''), email),
    cidade = coalesce(nullif(_dados->>'cidade',''), cidade),
    uf = coalesce(nullif(upper(_dados->>'uf'),''), uf),
    cep = coalesce(nullif(_dados->>'cep',''), cep),
    raio_atuacao_km = coalesce((_dados->>'raio_atuacao_km')::int, raio_atuacao_km),
    pix_chave = CASE WHEN _dados ? 'pix_chave' THEN nullif(_dados->>'pix_chave','') ELSE pix_chave END
  WHERE id = v_pid;
END $parceiro_meu_perfil_salvar$;
GRANT EXECUTE ON FUNCTION public.parceiro_meu_perfil_salvar(jsonb) TO authenticated;

-- ---------------------------------------------------------------------
-- 3) Autocadastro (quem já tem conta: cliente, profissional do Marketplace)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.parceiro_cadastrar(_dados jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $parceiro_cadastrar$
DECLARE v_id uuid; v_uid uuid := auth.uid(); v_mp uuid; v_email text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'É preciso estar autenticado'; END IF;
  IF public.parceiro_meu_id() IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'ja_existia', true, 'parceiro_id', public.parceiro_meu_id());
  END IF;
  IF coalesce(btrim(_dados->>'nome'),'') = '' THEN RAISE EXCEPTION 'Informe o nome'; END IF;
  IF coalesce((_dados->>'aceite_termos')::boolean, false) IS NOT TRUE THEN RAISE EXCEPTION 'É preciso aceitar os termos do programa'; END IF;
  SELECT email INTO v_email FROM auth.users WHERE id = v_uid;
  SELECT id INTO v_mp FROM public.marketplace_profissionais WHERE user_id = v_uid LIMIT 1;

  INSERT INTO public.parceiros
    (nome, tipo_pessoa, documento, tipo_parceiro, email, telefone, cidade, uf, cep,
     raio_atuacao_km, aceite_termos_em, marketplace_profissional_id, created_by)
  VALUES
    (_dados->>'nome', coalesce(_dados->>'tipo_pessoa','pj'), nullif(_dados->>'documento',''),
     coalesce(_dados->>'tipo_parceiro','indicador'), coalesce(nullif(_dados->>'email',''), v_email),
     nullif(_dados->>'telefone',''), nullif(_dados->>'cidade',''), nullif(upper(_dados->>'uf'),''),
     nullif(_dados->>'cep',''), coalesce((_dados->>'raio_atuacao_km')::int, 50), now(), v_mp, v_uid)
  RETURNING id INTO v_id;

  INSERT INTO public.parceiro_usuarios (parceiro_id, user_id, papel) VALUES (v_id, v_uid, 'dono');
  RETURN jsonb_build_object('ok', true, 'parceiro_id', v_id,
    'status', (SELECT status FROM public.parceiros WHERE id = v_id),
    'codigo', (SELECT codigo FROM public.parceiros WHERE id = v_id));
END $parceiro_cadastrar$;
GRANT EXECUTE ON FUNCTION public.parceiro_cadastrar(jsonb) TO authenticated;

-- ---------------------------------------------------------------------
-- 4) Migração dos afiliados do Marketplace (decisão 03/09/2026)
--    Copia; não apaga a origem. Só age onde há dado.
-- ---------------------------------------------------------------------
DO $mig$
DECLARE r record; v_pid uuid; v_n int := 0;
BEGIN
  FOR r IN
    SELECT DISTINCT mp.id AS mp_id, mp.user_id, mp.nome_completo, mp.email, mp.telefone, mp.cidade, mp.estado, mp.codigo_afiliado
    FROM public.marketplace_profissionais mp
    WHERE mp.codigo_afiliado IS NOT NULL
       OR EXISTS (SELECT 1 FROM public.marketplace_afiliados_comissoes c WHERE c.profissional_id = mp.id)
  LOOP
    SELECT id INTO v_pid FROM public.parceiros WHERE marketplace_profissional_id = r.mp_id;
    IF v_pid IS NULL THEN
      INSERT INTO public.parceiros (codigo, nome, tipo_pessoa, tipo_parceiro, email, telefone, cidade, uf, marketplace_profissional_id, observacoes)
      VALUES (nullif(upper(regexp_replace(coalesce(r.codigo_afiliado,''), '[^A-Za-z0-9-]', '', 'g')),''),
              r.nome_completo, 'pf', 'indicador', r.email, r.telefone, r.cidade, r.estado, r.mp_id,
              'Migrado do programa de afiliados do Marketplace')
      RETURNING id INTO v_pid;
      IF r.user_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.parceiro_usuarios WHERE user_id = r.user_id) THEN
        INSERT INTO public.parceiro_usuarios (parceiro_id, user_id) VALUES (v_pid, r.user_id);
      END IF;
    END IF;
    INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, base_cents, valor_cents, status, observacao)
    SELECT v_pid, c.tenant_indicado_id, date_trunc('month', c.created_at)::date, 'ajuste',
           0, round(coalesce(c.valor,0) * 100)::bigint,
           CASE WHEN c.status = 'pago' THEN 'pago' ELSE 'previsto' END,
           'Migrado de marketplace_afiliados_comissoes ' || c.id
    FROM public.marketplace_afiliados_comissoes c
    WHERE c.profissional_id = r.mp_id
      AND NOT EXISTS (SELECT 1 FROM public.parceiro_comissoes x WHERE x.observacao = 'Migrado de marketplace_afiliados_comissoes ' || c.id);
    UPDATE public.tenants t SET parceiro_id = v_pid, originado_em = coalesce(t.originado_em, now())
    WHERE t.parceiro_id IS NULL AND t.id IN (SELECT tenant_indicado_id FROM public.marketplace_afiliados_comissoes WHERE profissional_id = r.mp_id);
    v_n := v_n + 1;
  END LOOP;
  RAISE NOTICE 'Afiliados do Marketplace migrados para o Programa de Parceiros: %', v_n;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Migração dos afiliados não aplicada (%). Nada foi perdido: a origem permanece.', SQLERRM;
END $mig$;

-- ---------------------------------------------------------------------
-- 5) QA — PGP-011 (estágio derivado) e pontes de tela
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.qa_caso_pgp_011()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; e1 text; e2 text; e3 text; e4 text; e5 text; e6 text; e7 text; erros text := '';
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Aplicar a regra pura a 7 cenários, um por estágio, com fatos concorrentes';
  r.esperado := 'churn, ativo, go_live, implantacao, contrato, proposta, lead';
  e1 := public.parceiro_estagio_calc(true, true, 'canceled', true, true, now() - interval '400 days', NULL);
  e2 := public.parceiro_estagio_calc(true, true, 'active', true, true, now() - interval '60 days', NULL);
  e3 := public.parceiro_estagio_calc(true, true, 'active', true, true, now() - interval '5 days', NULL);
  e4 := public.parceiro_estagio_calc(true, true, 'trialing', true, false, NULL, NULL);
  e5 := public.parceiro_estagio_calc(false, NULL, NULL, true, false, NULL, 'negociacao');
  e6 := public.parceiro_estagio_calc(false, NULL, NULL, false, false, NULL, 'negociacao');
  e7 := public.parceiro_estagio_calc(false, NULL, NULL, false, false, NULL, 'novo');
  IF e1 <> 'churn' THEN erros := erros || format(' cenário churn -> %s;', e1); END IF;
  IF e2 <> 'ativo' THEN erros := erros || format(' cenário ativo -> %s;', e2); END IF;
  IF e3 <> 'go_live' THEN erros := erros || format(' cenário go_live -> %s;', e3); END IF;
  IF e4 <> 'implantacao' THEN erros := erros || format(' cenário implantacao -> %s;', e4); END IF;
  IF e5 <> 'contrato' THEN erros := erros || format(' cenário contrato -> %s;', e5); END IF;
  IF e6 <> 'proposta' THEN erros := erros || format(' cenário proposta -> %s;', e6); END IF;
  IF e7 <> 'lead' THEN erros := erros || format(' cenário lead -> %s;', e7); END IF;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: o wrapper por tenant usa a regra pura (uma fonte da precedência)';
  r.esperado := 'parceiro_estagio_tenant chama parceiro_estagio_calc';
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                 WHERE n.nspname = 'public' AND p.proname = 'parceiro_estagio_tenant' AND p.prosrc ILIKE '%parceiro_estagio_calc%') THEN
    erros := erros || ' wrapper não usa a regra pura;';
  END IF;

  IF erros = '' THEN
    r.situacao := 'passou'; r.obtido := 'Sete cenários no estágio esperado; wrapper delega à regra pura.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'ACHADO: precedência do estágio divergente:' || erros;
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES ('PGP-011', 'qa_caso_pgp_011')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- Pontes caso ↔ it() (título EXATO do it() no spec)
INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste) VALUES
  ('PGP-030', 'cypress/e2e/portal-parceiro.cy.ts', 'PGP-030: Parceiro sem empresa loga pelo site e cai na Área do Parceiro'),
  ('PGP-031', 'cypress/e2e/portal-parceiro.cy.ts', 'PGP-031: Portal: copiar o link de indicação'),
  ('PGP-032', 'cypress/e2e/portal-parceiro.cy.ts', 'PGP-032: Portal: carteira lista as empresas originadas com estágio e exporta CSV')
ON CONFLICT (codigo) DO UPDATE SET spec = EXCLUDED.spec, teste = EXCLUDED.teste, ativo = true;

-- =====================================================================
-- CONFERÊNCIA FINAL (o editor mostra só este resultado)
-- =====================================================================
WITH funcoes AS MATERIALIZED (
  SELECT count(*) AS n FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
  WHERE ns.nspname = 'public' AND p.proname IN (
    'parceiro_estagio_calc','parceiro_estagio_tenant','parceiro_mrr_tenant','parceiro_meu_portal',
    'parceiro_meu_perfil_salvar','parceiro_cadastrar','qa_caso_pgp_011')
), regra AS MATERIALIZED (
  SELECT public.parceiro_estagio_calc(true, true, 'canceled', true, true, now(), NULL) AS churn,
         public.parceiro_estagio_calc(false, NULL, NULL, false, false, NULL, 'negociacao') AS proposta
), qa AS MATERIALIZED (
  SELECT (public.qa_caso_pgp_011()).situacao::text AS pgp_011,
         (SELECT count(*) FROM public.qa_cobertura_e2e WHERE codigo IN ('PGP-030','PGP-031','PGP-032') AND ativo) AS pontes
), migrados AS MATERIALIZED (
  SELECT count(*) AS n FROM public.parceiros WHERE observacoes = 'Migrado do programa de afiliados do Marketplace'
)
SELECT
  CASE WHEN f.n = 7 AND r.churn = 'churn' AND r.proposta = 'proposta' AND q.pgp_011 = 'passou' AND q.pontes = 3
       THEN 'OK — Programa de Parceiros (Onda 2) aplicado'
       ELSE 'ATENÇÃO — confira as colunas ao lado' END AS resultado,
  f.n || '/7' AS funcoes,
  r.churn || ' / ' || r.proposta AS regra_estagio,
  q.pgp_011 AS qa_pgp_011,
  q.pontes || '/3' AS pontes_e2e,
  m.n AS afiliados_migrados,
  NULL::text AS erro_tecnico
FROM funcoes f, regra r, qa q, migrados m;
