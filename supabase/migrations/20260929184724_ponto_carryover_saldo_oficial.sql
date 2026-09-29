-- ============================================================================
-- Banco de horas — carry-over pelo FECHAMENTO OFICIAL do mês anterior
-- Itens 1/3/5 do pacote de correções do Ponto
--
-- PROBLEMA
--   apurar_banco_horas_colaborador abria a competência com
--   "saldo_anterior = ponto_banco_horas.saldo_atual_minutos do mês anterior" —
--   a FOTOGRAFIA crua. Essa fotografia só é reescrita quando se roda "Apurar";
--   ela NÃO acompanha edições posteriores (zeragem de saldo, ajuste aprovado,
--   atestado que chegou depois). O documento, porém, imprime o número OFICIAL
--   ao vivo (ponto_banco_horas_oficial). Quando os dois divergiam, o mês
--   seguinte abria com um saldo que nunca bateu com o que foi impresso — e,
--   ao zerar um saldo sem reapurar os meses à frente, o saldo antigo continuava
--   sendo puxado para frente. (Relato: "até agosto batia; depois de zerar,
--   parou"; "um mês não fecha com o outro".)
--
-- O QUE FAZ (aditivo, cirúrgico)
--   Troca a FONTE do saldo anterior: passa a ler o fechamento OFICIAL do mês
--   anterior (ponto_banco_horas_oficial), que devolve, para mês fechado, os
--   valores congelados (Súmula 338) e, para mês aberto, o cálculo ao vivo — nos
--   dois casos, exatamente o número que o documento imprimiu. Assim o começo de
--   um mês sempre bate com o fim do anterior.
--
-- GARANTIAS
--   · Muda SÓ a origem do saldo anterior. Crédito/débito, regime, prazo de
--     vencimento, movimentações e recomputo do saldo atual seguem idênticos aos
--     de 20260819270000 (parte que este arquivo reescreve por completo).
--   · ponto_banco_horas_oficial filtra por CPF (4º parâmetro), então o LIMIT 1
--     devolve o saldo do próprio colaborador.
--   · Não há recursão: a fonte oficial lê a fotografia + os saldos diários; não
--     chama a apuração de volta.
--   · Corrigir a MECÂNICA não reescreve o passado: os meses já apurados com o
--     número torto continuam como estão até serem reapurados em ordem
--     cronológica (feito pelo script de entrega docs/script_carryover_banco_horas.sql).
--   · Idempotente (CREATE OR REPLACE).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.apurar_banco_horas_colaborador(p_tenant_id uuid, p_colaborador_cpf text, p_competencia text, p_empresa_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ini date := to_date(p_competencia || '-01', 'YYYY-MM-DD');
  v_fim date := (to_date(p_competencia || '-01', 'YYYY-MM-DD') + INTERVAL '1 month - 1 day')::date;
  v_colaborador_id text;
  v_colaborador_nome text;
  v_empresa_id uuid := p_empresa_id;
  v_banco_id uuid;
  v_creditos int := 0;
  v_debitos int := 0;
  v_saldo_anterior int := 0;
  v_tem_anterior boolean := false;
  v_comp_anterior text;
  v_tot_cred int := 0;
  v_tot_deb int := 0;
  v_tot_comp int := 0;
  v_regime public.ponto_banco_horas_config;
  v_prazo date;
  -- Só para LOCALIZAR os dias no ponto_diario. Ao gravar seguimos usando
  -- p_colaborador_cpf, para não alterar o formato já existente na tabela.
  v_cpf text := regexp_replace(COALESCE(p_colaborador_cpf, ''), '[^0-9]', '', 'g');
BEGIN
  SELECT colaborador_id, colaborador_nome, empresa_id
    INTO v_colaborador_id, v_colaborador_nome, v_empresa_id
  FROM public.ponto_diario
  WHERE tenant_id = p_tenant_id
    AND regexp_replace(colaborador_cpf, '[^0-9]', '', 'g') = v_cpf
    AND data BETWEEN v_ini AND v_fim
  ORDER BY data DESC
  LIMIT 1;

  IF v_colaborador_id IS NULL THEN
    RETURN;
  END IF;
  IF v_empresa_id IS NULL THEN
    v_empresa_id := COALESCE(public.ponto_empresa_do_cpf(p_tenant_id, p_colaborador_cpf), p_empresa_id);
  END IF;

  -- FONTE ÚNICA: soma os saldos diários calculados pela função acima.
  SELECT
    COALESCE(SUM(CASE WHEN s.saldo_min > 0 THEN s.saldo_min ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN s.saldo_min < 0 THEN -s.saldo_min ELSE 0 END), 0)
  INTO v_creditos, v_debitos
  FROM public.ponto_saldo_dias_competencia(p_tenant_id, p_colaborador_cpf, p_competencia) s;

  -- (170) Banco só com instrumento vigente + (171/354) prazo de vencimento.
  -- Sem regime de compensação vigente: nada vai para o banco (devido em dinheiro
  -- na folha). Com regime: credita/debita e grava o prazo de compensação
  -- derivado (fim da competência + prazo_compensacao_dias do regime — 6 meses no
  -- acordo individual, até 12 no coletivo). CLT art. 59, §§2º/5º/6º.
  v_regime := public.ponto_banco_regime_vigente(p_tenant_id, p_colaborador_cpf, v_colaborador_id, v_fim);
  IF v_regime.id IS NULL THEN
    v_creditos := 0;
    v_debitos  := 0;
    v_prazo    := NULL;
  ELSE
    v_prazo := v_fim + COALESCE(v_regime.prazo_compensacao_dias, 180);
  END IF;

  -- Saldo anterior = FECHAMENTO OFICIAL do mês anterior (o mesmo número que o
  -- documento imprime), não a fotografia crua saldo_atual_minutos. A fotografia
  -- do mês anterior pode estar defasada (ex.: saldo zerado ou ajustado sem
  -- reapurar os meses seguintes); copiar o número cru quebrava a continuidade
  -- entre meses. A fonte oficial devolve, para mês fechado, os valores
  -- congelados (Súmula 338) e, para mês aberto, o cálculo ao vivo — nos dois
  -- casos, o número que foi impresso.
  v_comp_anterior := to_char(v_ini - INTERVAL '1 month', 'YYYY-MM');
  SELECT o.saldo_atual_min INTO v_saldo_anterior
  FROM public.ponto_banco_horas_oficial(p_tenant_id, v_comp_anterior, NULL, p_colaborador_cpf) o
  LIMIT 1;
  v_tem_anterior := FOUND;
  IF NOT v_tem_anterior THEN
    -- Sem movimento nem fotografia no mês anterior: preserva o saldo anterior
    -- lançado manualmente nesta competência (comportamento anterior).
    SELECT saldo_anterior_minutos INTO v_saldo_anterior
    FROM public.ponto_banco_horas
    WHERE tenant_id = p_tenant_id
      AND colaborador_cpf = p_colaborador_cpf
      AND competencia = p_competencia;
  END IF;
  v_saldo_anterior := COALESCE(v_saldo_anterior, 0);

  INSERT INTO public.ponto_banco_horas (
    tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
    tipo, competencia, saldo_anterior_minutos
  ) VALUES (
    p_tenant_id, v_empresa_id, v_colaborador_id, v_colaborador_nome, p_colaborador_cpf,
    'mensal', p_competencia, v_saldo_anterior
  )
  ON CONFLICT (tenant_id, colaborador_cpf, competencia)
  DO UPDATE SET
    saldo_anterior_minutos = EXCLUDED.saldo_anterior_minutos,
    empresa_id = COALESCE(public.ponto_banco_horas.empresa_id, EXCLUDED.empresa_id),
    colaborador_nome = EXCLUDED.colaborador_nome,
    colaborador_id = EXCLUDED.colaborador_id,
    updated_at = now()
  RETURNING id INTO v_banco_id;

  IF v_banco_id IS NULL THEN
    SELECT id INTO v_banco_id
    FROM public.ponto_banco_horas
    WHERE tenant_id = p_tenant_id
      AND colaborador_cpf = p_colaborador_cpf
      AND competencia = p_competencia;
  END IF;

  -- Remove as movimentações automáticas anteriores (as duas origens
  -- históricas). Lançamentos manuais são preservados.
  DELETE FROM public.ponto_banco_horas_movimentacoes
  WHERE banco_horas_id = v_banco_id
    AND origem IN ('apuracao', 'apuracao_auto');

  IF v_creditos > 0 THEN
    INSERT INTO public.ponto_banco_horas_movimentacoes (
      tenant_id, banco_horas_id, colaborador_cpf, data_referencia, tipo, minutos, descricao, origem
    ) VALUES (
      p_tenant_id, v_banco_id, p_colaborador_cpf, v_fim, 'credito', v_creditos,
      'Apuração automática — horas trabalhadas além da jornada', 'apuracao'
    );
  END IF;

  IF v_debitos > 0 THEN
    INSERT INTO public.ponto_banco_horas_movimentacoes (
      tenant_id, banco_horas_id, colaborador_cpf, data_referencia, tipo, minutos, descricao, origem
    ) VALUES (
      p_tenant_id, v_banco_id, p_colaborador_cpf, v_fim, 'debito', v_debitos,
      'Apuração automática — atrasos, faltas e saídas antecipadas', 'apuracao'
    );
  END IF;

  SELECT
    COALESCE(SUM(minutos) FILTER (WHERE tipo = 'credito'), 0),
    COALESCE(SUM(minutos) FILTER (WHERE tipo = 'debito'), 0),
    COALESCE(SUM(minutos) FILTER (WHERE tipo = 'compensacao'), 0)
  INTO v_tot_cred, v_tot_deb, v_tot_comp
  FROM public.ponto_banco_horas_movimentacoes
  WHERE banco_horas_id = v_banco_id;

  UPDATE public.ponto_banco_horas
  SET creditos_minutos = v_tot_cred,
      debitos_minutos = v_tot_deb,
      compensados_minutos = v_tot_comp,
      saldo_atual_minutos = saldo_anterior_minutos + v_tot_cred - v_tot_deb - v_tot_comp,
      prazo_compensacao = COALESCE(v_prazo, prazo_compensacao),
      updated_at = now()
  WHERE id = v_banco_id;
END;
$function$;

COMMENT ON FUNCTION public.apurar_banco_horas_colaborador(uuid, text, text, uuid) IS
  'Apura o banco de horas do colaborador. Saldo anterior = fechamento OFICIAL do mes anterior (ponto_banco_horas_oficial), para o comeco de um mes bater com o fim do anterior. So credita/debita com regime vigente e grava prazo_compensacao. CLT art. 59 §§2/5/6.';
