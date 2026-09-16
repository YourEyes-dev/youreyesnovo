-- ============================================================================
-- PRODUCAO — PONTO, PARTE 08 de 16
--
-- ANTES DE COLAR ESTA PARTE
--   * o RETRATO (passo_00_retrato_antes.sql) ja tem de ter sido tirado;
--   * as partes anteriores ja tem de ter sido aplicadas, nesta ordem, cada uma
--     com a conferencia terminando em OK.
--
-- ONDE COLAR
-- No SQL Editor do projeto de PRODUCAO. Execute o arquivo INTEIRO, uma vez.
-- Pode rodar de novo sem risco: e idempotente.
--
-- CONTEUDO
-- Identico ao que foi aplicado e conferido na homologacao, onde a bateria do
-- Ponto fechou em 133 passou / 1 falhou / 0 erro.
--
-- AO FINAL
-- Sai UMA conferencia com duas partes: as pecas que chegaram e o VOLUME —
-- quantas linhas das tabelas vivas do Ponto mudaram de quantidade. Nesta parte o esperado e ZERO.
-- ============================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- MEDICAO DE VOLUME (inicio) — a contagem de agora fica guardada para a
-- conferencia do fim comparar. Tabela propria, que nenhum sistema le.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ponto_entrega_volume (
  parte          integer NOT NULL,
  tabela         text    NOT NULL,
  linhas_antes   bigint  NOT NULL,
  linhas_depois  bigint,
  marca_antes    text,
  marca_depois   text,
  medido_em      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (parte, tabela)
);

-- Para a tabela criada por uma versao anterior desta fila continuar servindo.
ALTER TABLE public.ponto_entrega_volume ADD COLUMN IF NOT EXISTS marca_antes  text;
ALTER TABLE public.ponto_entrega_volume ADD COLUMN IF NOT EXISTS marca_depois text;

-- Tabela nova em public fica exposta pela API do Supabase. Esta nao tem dado
-- pessoal, mas tambem nao e da conta de ninguem: RLS ligada e sem politica.
ALTER TABLE public.ponto_entrega_volume ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ponto_entrega_volume FROM PUBLIC;

DO $fechadura$
BEGIN
  EXECUTE 'REVOKE ALL ON public.ponto_entrega_volume FROM anon, authenticated';
EXCEPTION WHEN undefined_object THEN
  RAISE NOTICE 'Papeis anon/authenticated nao existem nesta base.';
END $fechadura$;

DO $volume$
DECLARE
  t text;
  n bigint;
  m text;
BEGIN
  DELETE FROM public.ponto_entrega_volume WHERE parte = 8;
  FOREACH t IN ARRAY ARRAY['ponto_diario', 'ponto_marcacoes', 'ponto_espelhos', 'ponto_banco_horas', 'ponto_alertas', 'ponto_links', 'ponto_fechamentos', 'atestados']
  LOOP
    CONTINUE WHEN to_regclass('public.' || t) IS NULL;
    EXECUTE format('SELECT count(*) FROM public.%I', t) INTO n;
    m := NULL;
    -- A marca e a data da ultima alteracao registrada na tabela. Contagem
    -- pega linha criada ou apagada; a marca pega linha ALTERADA.
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name=t AND column_name='updated_at') THEN
      EXECUTE format('SELECT max(updated_at)::text FROM public.%I', t) INTO m;
    END IF;
    INSERT INTO public.ponto_entrega_volume (parte, tabela, linhas_antes, marca_antes)
    VALUES (8, t, n, m);
  END LOOP;
END $volume$;

-- ############################################################
-- BLOCO: script_ponto_onda5_banco_instrumento_vigente.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 5 (parte 1): banco de horas só com instrumento vigente
-- Alvos: ponto_banco_regime_vigente (nova); apurar_banco_horas_colaborador
-- PONTO-170
--
-- O banco de horas creditava para todo mundo, sem regime nem acordo. Sem
-- instrumento valido e vigente (CLT art. 59, §§2º e 5º), a hora extra e devida
-- em DINHEIRO na competencia — manda-la para o banco e postergar pagamento
-- devido. Passa a so creditar/debitar o banco quando ha regime de compensacao
-- vigente para o vinculo; sem regime, o excedente segue apurado no dia e vai
-- para a folha (nao some).
--
-- GARANTIAS
--   · So muda quem NAO tem regime: vinculo com regime vigente segue identico.
--   · Nao apaga nada — a hora extra continua apurada no dia; apenas nao vira
--     saldo de banco sem lastro. A batch apurar_banco_horas so repassa para esta
--     funcao, entao o comportamento propaga sozinho.
-- Aditivo e idempotente (CREATE OR REPLACE). Sem backfill.
-- ============================================================================

-- (1) Resolução do regime de banco vigente do vínculo ------------------------
CREATE OR REPLACE FUNCTION public.ponto_banco_regime_vigente(
  p_tenant_id      uuid,
  p_colaborador_cpf text,
  p_colaborador_id text,
  p_ref_data       date
)
RETURNS public.ponto_banco_horas_config
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_cpf       text := regexp_replace(COALESCE(p_colaborador_cpf, ''), '[^0-9]', '', 'g');
  v_escala_id uuid;
  v_empresa   uuid;
  v_cfg       public.ponto_banco_horas_config;
BEGIN
  -- Escala vigente do colaborador na data (para casar a config por escala).
  SELECT a.escala_id INTO v_escala_id
  FROM public.ponto_escala_atribuicoes a
  WHERE a.tenant_id = p_tenant_id
    AND (regexp_replace(COALESCE(a.colaborador_cpf, ''), '[^0-9]', '', 'g') = v_cpf
         OR a.colaborador_id::text = p_colaborador_id)
    AND COALESCE(a.ativa, true) = true
    AND (a.data_inicio IS NULL OR a.data_inicio <= p_ref_data)
    AND (a.data_fim IS NULL OR a.data_fim >= p_ref_data)
  ORDER BY a.data_inicio DESC NULLS LAST
  LIMIT 1;

  v_empresa := public.ponto_empresa_do_cpf(p_tenant_id, p_colaborador_cpf);

  -- Regime vigente que cobre o vínculo: específico da escala > da empresa >
  -- do tenant. Se o regime exige acordo individual ou CCT/ACT, precisa do
  -- instrumento anexado (acordo_id) para valer.
  SELECT c.* INTO v_cfg
  FROM public.ponto_banco_horas_config c
  WHERE c.tenant_id = p_tenant_id
    AND COALESCE(c.ativo, false) = true
    AND (c.data_inicio IS NULL OR c.data_inicio <= p_ref_data)
    AND (c.escala_id IS NULL OR c.escala_id = v_escala_id)
    AND (c.empresa_id IS NULL OR c.empresa_id = v_empresa)
    AND (
      (COALESCE(c.exige_acordo_individual, false) = false
       AND COALESCE(c.exige_cct_act, false) = false)
      OR c.acordo_id IS NOT NULL
    )
  ORDER BY (c.escala_id IS NOT NULL) DESC,
           (c.empresa_id IS NOT NULL) DESC,
           c.data_inicio DESC NULLS LAST
  LIMIT 1;

  RETURN v_cfg;  -- linha com todos os campos NULL quando não há regime vigente
END;
$$;

COMMENT ON FUNCTION public.ponto_banco_regime_vigente(uuid, text, text, date) IS
  'Resolve o regime de banco de horas vigente do vinculo na data (config especifica da escala prevalece sobre a da empresa e a do tenant; exige acordo/CCT anexado quando o regime marca que o exige). Retorna a linha de ponto_banco_horas_config, ou linha nula quando nao ha regime. CLT art. 59 §§2/5.';

-- (2) Apuração credita/debita o banco só com regime vigente ------------------
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

  -- (170) Banco só com instrumento vigente (CLT art. 59, §§2º/5º): sem regime
  -- de compensação vigente para o vínculo, nada vai para o banco — o excedente
  -- continua apurado no dia e é devido em dinheiro (folha). Com regime, credita
  -- e debita como sempre.
  v_regime := public.ponto_banco_regime_vigente(p_tenant_id, p_colaborador_cpf, v_colaborador_id, v_fim);
  IF v_regime.id IS NULL THEN
    v_creditos := 0;
    v_debitos  := 0;
  END IF;

  -- Saldo anterior = saldo atual da competência anterior; se não houver,
  -- preserva o saldo anterior lançado manualmente nesta competência.
  v_comp_anterior := to_char(v_ini - INTERVAL '1 month', 'YYYY-MM');
  SELECT saldo_atual_minutos INTO v_saldo_anterior
  FROM public.ponto_banco_horas
  WHERE tenant_id = p_tenant_id
    AND colaborador_cpf = p_colaborador_cpf
    AND competencia = v_comp_anterior;
  v_tem_anterior := FOUND;
  IF NOT v_tem_anterior THEN
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
      updated_at = now()
  WHERE id = v_banco_id;
END;
$function$;

COMMENT ON FUNCTION public.apurar_banco_horas_colaborador(uuid, text, text, uuid) IS
  'Apura o banco de horas do colaborador na competencia. So credita/debita o banco quando ha regime de compensacao vigente (ponto_banco_regime_vigente); sem regime, o excedente nao vira saldo de banco (devido em dinheiro na folha). CLT art. 59 §§2/5.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | OK
--   regime_helper : t  (funcao ponto_banco_regime_vigente existe)
--   apuracao_gate : t  (a apuracao consulta o regime vigente)
-- ---------------------------------------------------------------------------
SELECT
  (to_regprocedure('public.ponto_banco_regime_vigente(uuid,text,text,date)') IS NOT NULL) AS regime_helper,
  EXISTS (SELECT 1 FROM pg_proc WHERE proname='apurar_banco_horas_colaborador'
            AND prosrc ILIKE '%ponto_banco_regime_vigente%')                              AS apuracao_gate,
  CASE WHEN to_regprocedure('public.ponto_banco_regime_vigente(uuid,text,text,date)') IS NOT NULL
        AND EXISTS (SELECT 1 FROM pg_proc WHERE proname='apurar_banco_horas_colaborador'
              AND prosrc ILIKE '%ponto_banco_regime_vigente%')
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda5_prazo_vencimento_saldo.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 5 (parte 2): prazo de vencimento em cada crédito do banco
-- Alvo: apurar_banco_horas_colaborador (substituição completa da função)
-- PONTO-171 / PONTO-354  ·  DEPENDE DA PARTE 1 (#21: ponto_banco_regime_vigente)
--
-- A conversão de saldo vencido em hora extra já existe e funciona, mas nunca
-- dispara porque a apuração jamais grava prazo_compensacao. Passa a gravar
-- prazo_compensacao = fim da competência + prazo_compensacao_dias do regime
-- vigente (6 meses no acordo individual, até 12 no coletivo). Com o prazo na
-- linha, a conversão automática que já existe encontra o que converter no
-- vencimento. CLT art. 59, §§2º/5º/6º.
--
-- GARANTIAS
--   · Depende da parte 1 (#21): usa ponto_banco_regime_vigente. Sem regime, não
--     há crédito nem prazo. Só ACRESCENTA o prazo; sem regime preserva o prazo
--     já existente (não apaga vencimento de saldo acumulado sob regime anterior).
--   · Não altera a conversão nem o motor de saldo. Aditivo e idempotente.
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

  -- Saldo anterior = saldo atual da competência anterior; se não houver,
  -- preserva o saldo anterior lançado manualmente nesta competência.
  v_comp_anterior := to_char(v_ini - INTERVAL '1 month', 'YYYY-MM');
  SELECT saldo_atual_minutos INTO v_saldo_anterior
  FROM public.ponto_banco_horas
  WHERE tenant_id = p_tenant_id
    AND colaborador_cpf = p_colaborador_cpf
    AND competencia = v_comp_anterior;
  v_tem_anterior := FOUND;
  IF NOT v_tem_anterior THEN
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
  'Apura o banco de horas do colaborador. So credita/debita com regime vigente (parte 1) e grava prazo_compensacao = fim da competencia + prazo_compensacao_dias do regime (parte 2), para a conversao automatica de saldo vencido disparar. CLT art. 59 §§2/5/6.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | OK
--   apuracao_prazo : t  (a apuracao grava prazo_compensacao)
--   usa_regime     : t  (deriva do regime vigente — parte 1)
-- ---------------------------------------------------------------------------
WITH src AS (
  SELECT prosrc FROM pg_proc WHERE proname='apurar_banco_horas_colaborador' LIMIT 1
)
SELECT
  (prosrc ILIKE '%prazo_compensacao%')        AS apuracao_prazo,
  (prosrc ILIKE '%ponto_banco_regime_vigente%') AS usa_regime,
  CASE WHEN prosrc ILIKE '%prazo_compensacao%' AND prosrc ILIKE '%ponto_banco_regime_vigente%'
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico
FROM src;



-- ############################################################
-- BLOCO: script_ponto_onda5_alertas_banco.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 5 (parte 3): alertas de vencimento e de teto de acumulo
-- Alvo: ponto_banco_alertas_monitorar (nova)
-- PONTO-355 / PONTO-356  ·  DEPENDE DA PARTE 1 (#21: ponto_banco_regime_vigente)
--
-- Dois avisos que faltavam no banco de horas:
--   (355) VENCIMENTO PROXIMO: X dias antes do prazo_compensacao (parte 2),
--         alerta com a acao sugerida (programar compensacao ou pagar). Sem isso
--         o RH so descobre o saldo vencido quando ja virou passivo (art. 59 §5º).
--   (356) TETO DE ACUMULO: o limite_acumulo_horas da configuracao era
--         decorativo; passa a ser comparado com o saldo e a gerar alerta do
--         excedente.
--
-- Um monitor que so insere alertas (idempotente), no padrao dos monitores das
-- ondas 2 e 4. Nao roda sozinho, sem gatilho em tabela quente, sem tocar no
-- motor de saldo. Aditivo e idempotente (CREATE OR REPLACE). Sem backfill.
-- Sugestao: agendar (pg_cron) a chamada diaria, ex.: SELECT ponto_banco_alertas_monitorar(15);
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ponto_banco_alertas_monitorar(p_dias_aviso integer DEFAULT 15)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_n         int := 0;
  v_ins       int;
  b           RECORD;
  v_regime    public.ponto_banco_horas_config;
  v_limite_min int;
  v_dias_ate  int;
  v_comp_fim  date;
BEGIN
  FOR b IN
    SELECT * FROM public.ponto_banco_horas
    WHERE COALESCE(convertido_extras, false) = false
      AND COALESCE(saldo_atual_minutos, 0) > 0
      AND tenant_id IS NOT NULL
  LOOP
    -- (355) Vencimento próximo: até p_dias_aviso dias antes do prazo, ainda não
    -- vencido. Idempotente por colaborador/prazo.
    IF b.prazo_compensacao IS NOT NULL
       AND b.prazo_compensacao >= CURRENT_DATE
       AND b.prazo_compensacao <= CURRENT_DATE + COALESCE(p_dias_aviso, 15) THEN
      v_dias_ate := b.prazo_compensacao - CURRENT_DATE;
      INSERT INTO public.ponto_alertas
        (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
         tipo, severidade, titulo, descricao, data_referencia)
      SELECT b.tenant_id, b.empresa_id, b.colaborador_id::text, b.colaborador_nome, b.colaborador_cpf,
             'banco_vencimento_proximo', 'media',
             'Saldo de banco de horas perto de vencer',
             format('Saldo de %s min (competencia %s) vence em %s — faltam %s dia(s). Antes do prazo, '
                 || 'programar a compensacao ou pagar como hora extra; vencido, o saldo vira hora '
                 || 'extra devida (CLT art. 59, §5º).',
                 b.saldo_atual_minutos, b.competencia, b.prazo_compensacao, v_dias_ate),
             b.prazo_compensacao
      WHERE NOT EXISTS (
        SELECT 1 FROM public.ponto_alertas a
        WHERE a.tenant_id = b.tenant_id
          AND a.colaborador_cpf = b.colaborador_cpf
          AND a.tipo = 'banco_vencimento_proximo'
          AND a.data_referencia = b.prazo_compensacao
      );
      GET DIAGNOSTICS v_ins = ROW_COUNT;
      v_n := v_n + v_ins;
    END IF;

    -- (356) Teto de acúmulo: compara o saldo com limite_acumulo_horas do regime
    -- vigente. Idempotente por colaborador/competência.
    v_regime := public.ponto_banco_regime_vigente(
                  b.tenant_id, b.colaborador_cpf, b.colaborador_id::text,
                  COALESCE(b.prazo_compensacao, CURRENT_DATE));
    IF v_regime.limite_acumulo_horas IS NOT NULL AND v_regime.limite_acumulo_horas > 0 THEN
      v_limite_min := round(v_regime.limite_acumulo_horas * 60)::int;
      IF b.saldo_atual_minutos > v_limite_min THEN
        BEGIN
          v_comp_fim := (to_date(b.competencia || '-01', 'YYYY-MM-DD') + INTERVAL '1 month - 1 day')::date;
        EXCEPTION WHEN OTHERS THEN
          v_comp_fim := CURRENT_DATE;
        END;
        INSERT INTO public.ponto_alertas
          (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
           tipo, severidade, titulo, descricao, data_referencia)
        SELECT b.tenant_id, b.empresa_id, b.colaborador_id::text, b.colaborador_nome, b.colaborador_cpf,
               'banco_teto_acumulo', 'alta',
               'Saldo de banco acima do teto de acumulo',
               format('Saldo de %s min ultrapassa o teto de acumulo do regime (%s h = %s min). '
                   || 'Excedente de %s min — regularizar (compensar ou pagar) o que passa do teto.',
                   b.saldo_atual_minutos, v_regime.limite_acumulo_horas, v_limite_min,
                   b.saldo_atual_minutos - v_limite_min),
               v_comp_fim
        WHERE NOT EXISTS (
          SELECT 1 FROM public.ponto_alertas a
          WHERE a.tenant_id = b.tenant_id
            AND a.colaborador_cpf = b.colaborador_cpf
            AND a.tipo = 'banco_teto_acumulo'
            AND a.data_referencia = v_comp_fim
        );
        GET DIAGNOSTICS v_ins = ROW_COUNT;
        v_n := v_n + v_ins;
      END IF;
    END IF;
  END LOOP;

  RETURN v_n;
END;
$$;

COMMENT ON FUNCTION public.ponto_banco_alertas_monitorar(integer) IS
  'Monitor do banco de horas: alerta o RH sobre saldo perto de vencer (X dias antes do prazo_compensacao) e sobre saldo acima do limite_acumulo_horas do regime. So insere em ponto_alertas, idempotente. CLT art. 59.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | t | OK
--   monitor_existe  : t  (funcao ponto_banco_alertas_monitorar)
--   alerta_vencto   : t  (gera alerta de vencimento — ponto_alertas + prazo)
--   usa_teto        : t  (consulta limite_acumulo)
-- ---------------------------------------------------------------------------
WITH src AS (SELECT prosrc FROM pg_proc WHERE proname='ponto_banco_alertas_monitorar' LIMIT 1)
SELECT
  (to_regprocedure('public.ponto_banco_alertas_monitorar(integer)') IS NOT NULL) AS monitor_existe,
  ((SELECT prosrc FROM src) ILIKE '%ponto_alertas%' AND (SELECT prosrc FROM src) ILIKE '%prazo%') AS alerta_vencto,
  ((SELECT prosrc FROM src) ILIKE '%limite_acumulo%') AS usa_teto,
  CASE WHEN to_regprocedure('public.ponto_banco_alertas_monitorar(integer)') IS NOT NULL
        AND (SELECT prosrc FROM src) ILIKE '%ponto_alertas%'
        AND (SELECT prosrc FROM src) ILIKE '%prazo%'
        AND (SELECT prosrc FROM src) ILIKE '%limite_acumulo%'
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda5_limite_diario_compensacao.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 5 (parte 4): limite de 10h diárias no regime de compensacao
-- Alvo: ponto_banco_limite_diario_monitorar (nova)
-- PONTO-172  ·  DEPENDE DA PARTE 1 (#21: ponto_banco_regime_vigente)
--
-- Em regime de compensacao (banco de horas), a jornada do dia nao pode passar
-- de 10 horas (CLT art. 59, §2º). O limite e DO REGIME e independe do teto de 2h
-- extras: um dia de 11h com banco e irregular mesmo que o saldo compense depois.
-- Passa a existir um monitor que sinaliza os dias acima de 600 minutos para quem
-- esta em regime de compensacao vigente.
--
-- Baixo risco: so insere alertas, idempotente por colaborador/dia. Nao roda
-- sozinho, sem gatilho em tabela quente, sem tocar no motor de saldo. Depende do
-- ponto_banco_regime_vigente (parte 1). Aditivo e idempotente. Sem backfill.
-- Sugestao: agendar (pg_cron) junto do monitor de alertas do banco (parte 3).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ponto_banco_limite_diario_monitorar(p_competencia text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ini date := to_date(p_competencia || '-01', 'YYYY-MM-DD');
  v_fim date := (to_date(p_competencia || '-01', 'YYYY-MM-DD') + INTERVAL '1 month - 1 day')::date;
  v_n   int := 0;
  v_ins int;
  b     RECORD;
  v_regime public.ponto_banco_horas_config;
BEGIN
  FOR b IN
    SELECT d.tenant_id, d.empresa_id, d.colaborador_id, d.colaborador_nome,
           d.colaborador_cpf, d.data,
           floor(EXTRACT(EPOCH FROM d.horas_trabalhadas)/60)::int AS min_trab
    FROM public.ponto_diario d
    WHERE d.data BETWEEN v_ini AND v_fim
      AND d.tenant_id IS NOT NULL
      -- Limite de 10 horas (600 minutos) da jornada em regime de compensacao
      -- (CLT art. 59, §2º): so passa adiante o dia que excede.
      AND floor(EXTRACT(EPOCH FROM d.horas_trabalhadas)/60)::int > 600
  LOOP
    -- O limite de 10 horas vale para quem esta em regime de compensacao.
    v_regime := public.ponto_banco_regime_vigente(
                  b.tenant_id, b.colaborador_cpf, b.colaborador_id::text, b.data);
    IF v_regime.id IS NOT NULL THEN
      INSERT INTO public.ponto_alertas
        (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
         tipo, severidade, titulo, descricao, data_referencia)
      SELECT b.tenant_id, b.empresa_id, b.colaborador_id::text, b.colaborador_nome, b.colaborador_cpf,
             'banco_limite_10h', 'alta',
             'Jornada acima de 10h em regime de compensacao (CLT art. 59, §2º)',
             format('Jornada de %s min neste dia em regime de compensacao ultrapassa o limite de '
                 || '10 horas (600 minutos) do art. 59, §2º. O limite e do regime e independe do '
                 || 'teto de 2h extras — dia de mais de 10 horas e irregular ainda que o saldo '
                 || 'compense depois. Excedente de %s min.',
                 b.min_trab, b.min_trab - 600),
             b.data
      WHERE NOT EXISTS (
        SELECT 1 FROM public.ponto_alertas a
        WHERE a.tenant_id = b.tenant_id
          AND a.colaborador_cpf = b.colaborador_cpf
          AND a.tipo = 'banco_limite_10h'
          AND a.data_referencia = b.data
      );
      GET DIAGNOSTICS v_ins = ROW_COUNT;
      v_n := v_n + v_ins;
    END IF;
  END LOOP;

  RETURN v_n;
END;
$$;

COMMENT ON FUNCTION public.ponto_banco_limite_diario_monitorar(text) IS
  'Monitor: sinaliza dias com jornada acima de 10 horas (600 min) para colaborador em regime de compensacao (CLT art. 59, §2º). So insere em ponto_alertas, idempotente por colaborador/dia.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | OK
--   monitor_existe : t  (funcao ponto_banco_limite_diario_monitorar)
--   limite_10h     : t  (verifica 600 min em regime de compensacao)
-- ---------------------------------------------------------------------------
WITH src AS (SELECT prosrc FROM pg_proc WHERE proname='ponto_banco_limite_diario_monitorar' LIMIT 1)
SELECT
  (to_regprocedure('public.ponto_banco_limite_diario_monitorar(text)') IS NOT NULL) AS monitor_existe,
  ((SELECT prosrc FROM src) ILIKE '%600%compensa%')                                  AS limite_10h,
  CASE WHEN to_regprocedure('public.ponto_banco_limite_diario_monitorar(text)') IS NOT NULL
        AND (SELECT prosrc FROM src) ILIKE '%600%compensa%'
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda5_escala_12x36.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 5 (parte 6): escala 12x36 por ciclo
-- Alvos: ponto_apurar_ciclo_plantao_do_dia (nova); injecoes guardadas em
--        ponto_jornada_do_dia, ponto_saldo_dias_competencia (monolito) e
--        ponto_feriados_trabalhados.
--
-- ALVO DO MOTOR DE SALDO (drift do ensaio): no repositorio a apuracao foi
--   refatorada em casca + ponto_saldo_dias_competencia_bruto, mas ESSA
--   REFATORACAO NUNCA CHEGOU A PRODUCAO — la (e na homologacao, copia fiel) a
--   apuracao segue num unico corpo monolitico ponto_saldo_dias_competencia.
--   A ancora da injecao e identica nos dois; muda so o nome. Aqui o alvo e o
--   monolito. Verificado contra o corpo real de producao: a ancora casa e e unica.
-- PONTO-150 / PONTO-151
--
-- Os campos de ciclo existem na escala (tipo '12x36', ciclo_horas_trabalho/
-- descanso, ciclo_inicio_data) e nenhuma apuracao os lia: o plantonista 12x36
-- teria 4h de "extra" em todo plantao e "falta" em toda folga, e o feriado
-- trabalhado geraria dobra indevida (a 12x36 ja compensa por lei — art. 59-A e
-- §2º). Passa a: ler o ciclo (plantao/folga), nao gerar HE no plantao nem falta
-- na folga, e pular a dobra de feriado de quem e 12x36.
--
-- SEGURANCA (mesmo padrao da onda 3): as injecoes sao IDEMPOTENTES (so entram se
-- ainda nao estao) e GUARDADAS por ancora. Se o corpo em producao divergir da
-- ancora (remendo proprio), a injecao NAO altera nada e emite um aviso — a
-- conferencia abaixo acusa o que faltou. So muda quem e 12x36; para o resto, a
-- helper devolve eh_ciclo=false e nada muda. Aditivo. Sem backfill.
-- ============================================================================

-- (1) Helper do ciclo ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_apurar_ciclo_plantao_do_dia(
  p_tenant_id      uuid,
  p_cpf            text,
  p_colaborador_id text,
  p_data           date
)
RETURNS TABLE(eh_ciclo boolean, eh_plantao boolean, jornada_min integer)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_cpf   text := regexp_replace(COALESCE(p_cpf, ''), '[^0-9]', '', 'g');
  v_esc   public.ponto_escalas;
  v_trab  int;
  v_desc  int;
  v_cycle_days int;
  v_dias_trab  int;
  v_off   int;
BEGIN
  eh_ciclo := false; eh_plantao := NULL; jornada_min := NULL;

  SELECT e.* INTO v_esc
  FROM public.ponto_escala_atribuicoes a
  JOIN public.ponto_escalas e ON e.id = a.escala_id
  WHERE a.tenant_id = p_tenant_id
    AND (regexp_replace(COALESCE(a.colaborador_cpf, ''), '[^0-9]', '', 'g') = v_cpf
         OR a.colaborador_id::text = p_colaborador_id)
    AND COALESCE(a.ativa, true) = true
    AND a.data_inicio <= p_data
    AND (a.data_fim IS NULL OR a.data_fim >= p_data)
  ORDER BY a.data_inicio DESC
  LIMIT 1;

  IF v_esc.id IS NULL THEN
    RETURN NEXT; RETURN;
  END IF;

  v_esc := public.ponto_escala_com_versao(v_esc, p_data);
  v_trab := COALESCE(v_esc.ciclo_horas_trabalho, 0);
  v_desc := COALESCE(v_esc.ciclo_horas_descanso, 0);

  -- Escala de plantao por ciclo: tipo 12x36 (ou campos de ciclo preenchidos).
  IF COALESCE(v_esc.tipo, '') = '12x36' OR (v_trab > 0 AND v_desc > 0) THEN
    IF v_trab = 0 THEN v_trab := 12; END IF;   -- defaults do 12x36
    IF v_desc = 0 THEN v_desc := 36; END IF;
    eh_ciclo := true;

    -- Sem ancora nao da para localizar a posicao no ciclo.
    IF v_esc.ciclo_inicio_data IS NULL THEN
      RETURN NEXT; RETURN;
    END IF;

    v_cycle_days := GREATEST(1, ceil((v_trab + v_desc)::numeric / 24)::int);  -- 12x36 -> 2
    v_dias_trab  := GREATEST(1, ceil(v_trab::numeric / 24)::int);             -- 12x36 -> 1
    v_off := ((p_data - v_esc.ciclo_inicio_data) % v_cycle_days + v_cycle_days) % v_cycle_days;
    eh_plantao := (v_off < v_dias_trab);
    jornada_min := CASE WHEN eh_plantao THEN LEAST(v_trab, 24) * 60 ELSE 0 END;
  END IF;

  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION public.ponto_apurar_ciclo_plantao_do_dia(uuid, text, text, date) IS
  'Diz se o dia e plantao ou folga na escala de ciclo 12x36 (le ciclo_horas_trabalho/descanso a partir de ciclo_inicio_data) e a jornada do plantao. Base da apuracao por ciclo (CLT art. 59-A). eh_ciclo=false quando o vinculo nao e de plantao.';

-- (2) ponto_jornada_do_dia: jornada do ciclo no plantao, 0 na folga -----------
DO $inj$
DECLARE
  v_def text;
  v_anchor text := 'v_escala := public.ponto_escala_com_versao(v_escala, p_data);';
  v_add text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc
   WHERE proname = 'ponto_jornada_do_dia' AND pronamespace = 'public'::regnamespace LIMIT 1;
  IF v_def IS NULL THEN RETURN; END IF;

  IF position('ponto_apurar_ciclo_plantao_do_dia' IN v_def) > 0 THEN
    RETURN;  -- ja injetado
  ELSIF position(v_anchor IN v_def) = 0 THEN
    RAISE NOTICE 'ponto_jornada_do_dia: ancora do ciclo nao encontrada — NADA alterado (corpo divergente).';
    RETURN;
  END IF;

  v_add := v_anchor || E'\n\n  -- (150) 12x36 por ciclo (art. 59-A): plantao usa a jornada do ciclo; folga = 0.\n'
    || E'  DECLARE v_ciclo record;\n'
    || E'  BEGIN\n'
    || E'    SELECT * INTO v_ciclo FROM public.ponto_apurar_ciclo_plantao_do_dia(p_tenant_id, p_cpf, p_colaborador_id, p_data);\n'
    || E'    IF v_ciclo.eh_ciclo AND v_ciclo.eh_plantao IS NOT NULL THEN\n'
    || E'      jornada_min := v_ciclo.jornada_min;\n'
    || E'      tol_min := COALESCE(v_escala.tolerancia_diaria_minutos, 0);\n'
    || E'      RETURN NEXT; RETURN;\n'
    || E'    END IF;\n'
    || E'  END;';

  v_def := replace(v_def, v_anchor, v_add);
  EXECUTE v_def;
END $inj$;

-- (3) ponto_saldo_dias_competencia (monolito): folga do ciclo nao gera falta --
DO $inj$
DECLARE
  v_def text;
  v_anchor text := E'IF v_jornada IS NULL OR v_jornada = 0 THEN\n      IF EXTRACT(DOW FROM r.data)::int IN (0, 6) THEN\n        v_esperado := 0;\n      ELSE\n        v_esperado := COALESCE(v_fb_jornada, 0);\n      END IF;\n    ELSE\n      v_esperado := v_jornada;\n    END IF;';
  v_add text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc
   WHERE proname = 'ponto_saldo_dias_competencia' AND pronamespace = 'public'::regnamespace LIMIT 1;
  IF v_def IS NULL THEN RETURN; END IF;

  IF position('ponto_apurar_ciclo_plantao_do_dia' IN v_def) > 0 THEN
    RETURN;
  ELSIF position(v_anchor IN v_def) = 0 THEN
    RAISE NOTICE 'ponto_saldo_dias_competencia: ancora do ciclo nao encontrada — NADA alterado (corpo divergente; envie o pg_get_functiondef para reconciliar).';
    RETURN;
  END IF;

  v_add := v_anchor || E'\n\n    -- (150) 12x36 por ciclo (art. 59-A): plantao usa a jornada do ciclo; a FOLGA\n'
    || E'    -- do ciclo NAO gera falta (sobrepoe o fallback de 8h dos dias uteis).\n'
    || E'    DECLARE v_ciclo record;\n'
    || E'    BEGIN\n'
    || E'      SELECT * INTO v_ciclo FROM public.ponto_apurar_ciclo_plantao_do_dia(p_tenant_id, v_cpf, r.colaborador_id::text, r.data);\n'
    || E'      IF v_ciclo.eh_ciclo AND v_ciclo.eh_plantao IS NOT NULL THEN\n'
    || E'        IF v_ciclo.eh_plantao THEN v_esperado := COALESCE(v_ciclo.jornada_min, v_esperado);\n'
    || E'        ELSE v_esperado := 0; END IF;\n'
    || E'      END IF;\n'
    || E'    END;';

  v_def := replace(v_def, v_anchor, v_add);
  EXECUTE v_def;
END $inj$;

-- (4) ponto_feriados_trabalhados: pula a dobra de feriado na 12x36 ------------
DO $inj$
DECLARE
  v_def text;
  v_anchor text := 'CASE WHEN fc.data_folga IS NULL THEN t.trab_min ELSE 0 END';
  v_add text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc
   WHERE proname = 'ponto_feriados_trabalhados' AND pronamespace = 'public'::regnamespace LIMIT 1;
  IF v_def IS NULL THEN RETURN; END IF;

  IF position('ponto_apurar_ciclo_plantao_do_dia' IN v_def) > 0 THEN
    RETURN;
  ELSIF position(v_anchor IN v_def) = 0 THEN
    RAISE NOTICE 'ponto_feriados_trabalhados: ancora nao encontrada — NADA alterado (corpo divergente).';
    RETURN;
  END IF;

  -- (151) Na 12x36 (art. 59-A, §2º) o feriado ja e compensado pela escala de
  -- plantao — sem dobra. Zera o adicional quando o vinculo e de ciclo.
  v_add := 'CASE WHEN fc.data_folga IS NULL AND NOT COALESCE((SELECT c.eh_ciclo FROM public.ponto_apurar_ciclo_plantao_do_dia(p_tenant_id, p_colaborador_cpf, v_cid::text, h.data) c LIMIT 1), false) THEN t.trab_min ELSE 0 END';

  v_def := replace(v_def, v_anchor, v_add);
  EXECUTE v_def;
END $inj$;

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | t | t | OK
--   helper_existe : t  (ponto_apurar_ciclo_plantao_do_dia)
--   jornada_ciclo : t  (ponto_jornada_do_dia le o ciclo)
--   saldo_ciclo   : t  (o motor de saldo le o ciclo — se f, o corpo de producao
--                       divergiu: me envie pg_get_functiondef(ponto_saldo_dias_
--                       competencia) para reconciliar)
--   feriado_ciclo : t  (a apuracao de feriado distingue a 12x36)
-- ---------------------------------------------------------------------------
SELECT
  (to_regprocedure('public.ponto_apurar_ciclo_plantao_do_dia(uuid,text,text,date)') IS NOT NULL) AS helper_existe,
  (EXISTS (SELECT 1 FROM pg_proc WHERE proname='ponto_jornada_do_dia'
     AND prosrc ILIKE '%ponto_apurar_ciclo_plantao_do_dia%'))                                    AS jornada_ciclo,
  (EXISTS (SELECT 1 FROM pg_proc WHERE proname='ponto_saldo_dias_competencia'
     AND prosrc ILIKE '%ponto_apurar_ciclo_plantao_do_dia%'))                                    AS saldo_ciclo,
  (EXISTS (SELECT 1 FROM pg_proc WHERE proname='ponto_feriados_trabalhados'
     AND prosrc ILIKE '%ponto_apurar_ciclo_plantao_do_dia%'))                                    AS feriado_ciclo,
  CASE WHEN to_regprocedure('public.ponto_apurar_ciclo_plantao_do_dia(uuid,text,text,date)') IS NOT NULL
        AND EXISTS (SELECT 1 FROM pg_proc WHERE proname='ponto_jornada_do_dia' AND prosrc ILIKE '%ponto_apurar_ciclo_plantao_do_dia%')
        AND EXISTS (SELECT 1 FROM pg_proc WHERE proname='ponto_saldo_dias_competencia' AND prosrc ILIKE '%ponto_apurar_ciclo_plantao_do_dia%')
        AND EXISTS (SELECT 1 FROM pg_proc WHERE proname='ponto_feriados_trabalhados' AND prosrc ILIKE '%ponto_apurar_ciclo_plantao_do_dia%')
       THEN 'OK' ELSE 'CONFERIR (corpo divergente — ver aviso)' END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda5_liquidar_banco_rescisao.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 5 (parte 5): liquidacao do saldo de banco na rescisao
-- Alvos: ponto_banco_liquidar_rescisao (nova); gatilho no desligamento (admissoes)
-- PONTO-173
--
-- O desligamento nao conversava com o banco de horas: o colaborador desligado
-- com saldo positivo perdia o registro. A CLT art. 59, §3º manda pagar as horas
-- nao compensadas na rescisao, sobre a REMUNERACAO DA DATA DA RESCISAO. Passa a
-- existir a funcao de liquidacao e um gatilho no desligamento que a dispara —
-- blindado: falha na liquidacao NAO quebra o desligamento.
--
-- GARANTIAS
--   · Nao altera o motor de saldo nem a apuracao; so le o banco e registra a
--     liquidacao (movimentacao liquidacao_rescisao). Idempotente; saldo
--     zero/negativo nao gera credito. Nada e apagado.
--   · Um unico gatilho, na tabela admissoes (que ja tem varios gatilhos de
--     desligamento). lock_timeout curto para a criacao do gatilho.
-- Aditivo e idempotente (CREATE OR REPLACE; DROP TRIGGER IF EXISTS + CREATE).
-- ============================================================================
SET lock_timeout = '10s';

-- (1) Liquidação do saldo -----------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_banco_liquidar_rescisao(
  p_tenant_id       uuid,
  p_colaborador_cpf text,
  p_data_rescisao   date DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_cpf   text := regexp_replace(COALESCE(p_colaborador_cpf, ''), '[^0-9]', '', 'g');
  v_data  date := COALESCE(p_data_rescisao, CURRENT_DATE);
  v_banco RECORD;
  v_min   int;
BEGIN
  -- Saldo final = saldo da ULTIMA competência (o saldo do banco carrega adiante
  -- via saldo_anterior).
  SELECT * INTO v_banco
  FROM public.ponto_banco_horas
  WHERE tenant_id = p_tenant_id
    AND regexp_replace(colaborador_cpf, '[^0-9]', '', 'g') = v_cpf
  ORDER BY competencia DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN 0;  -- sem banco (sem regime): nada a liquidar
  END IF;

  v_min := COALESCE(v_banco.saldo_atual_minutos, 0);
  IF v_min <= 0 THEN
    RETURN 0;  -- saldo zero/negativo não gera crédito rescisório
  END IF;

  -- Idempotente: não liquida o mesmo banco duas vezes.
  IF EXISTS (
    SELECT 1 FROM public.ponto_banco_horas_movimentacoes m
    WHERE m.banco_horas_id = v_banco.id AND m.tipo = 'liquidacao_rescisao'
  ) THEN
    RETURN 0;
  END IF;

  INSERT INTO public.ponto_banco_horas_movimentacoes
    (tenant_id, banco_horas_id, colaborador_cpf, data_referencia, tipo, minutos, descricao, origem)
  VALUES (
    p_tenant_id, v_banco.id, v_banco.colaborador_cpf, v_data, 'liquidacao_rescisao', v_min,
    format('Liquidacao do saldo de banco de horas na rescisao (%s min): pagar como horas nao '
        || 'compensadas sobre a REMUNERACAO DA DATA DA RESCISAO (CLT art. 59, §3º).', v_min),
    'rescisao'
  );

  -- Marca o saldo como liquidado (preserva o registro; documenta a quitacao).
  UPDATE public.ponto_banco_horas
  SET observacoes = COALESCE(observacoes, '')
        || format(' [Liquidado na rescisao em %s: %s min a pagar na folha]', v_data, v_min),
      updated_at = now()
  WHERE id = v_banco.id;

  RETURN v_min;
END;
$$;

COMMENT ON FUNCTION public.ponto_banco_liquidar_rescisao(uuid, text, date) IS
  'Liquida o saldo positivo do banco de horas na rescisao: registra a movimentacao liquidacao_rescisao com os minutos a pagar sobre a remuneracao da data da rescisao (CLT art. 59, §3º). Idempotente; saldo zero/negativo nao gera credito.';

-- (2) Gatilho no desligamento (blindado) -------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_banco_liquidar_rescisao_trg()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_desligou boolean;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_desligou := (NEW.status::text = 'desligado' OR NEW.data_desligamento IS NOT NULL);
  ELSE
    v_desligou := (NEW.status::text = 'desligado' AND COALESCE(OLD.status::text, '') <> 'desligado')
               OR (NEW.data_desligamento IS NOT NULL AND OLD.data_desligamento IS NULL);
  END IF;

  IF v_desligou AND NEW.tenant_id IS NOT NULL AND NEW.cpf IS NOT NULL THEN
    BEGIN
      PERFORM public.ponto_banco_liquidar_rescisao(NEW.tenant_id, NEW.cpf, NEW.data_desligamento);
    EXCEPTION WHEN OTHERS THEN
      -- Nunca quebra o desligamento por causa da liquidacao do banco.
      RAISE NOTICE 'Liquidacao de banco na rescisao falhou para % (%): %', NEW.cpf, NEW.tenant_id, SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ponto_banco_liquidar_rescisao ON public.admissoes;
CREATE TRIGGER trg_ponto_banco_liquidar_rescisao
  AFTER INSERT OR UPDATE ON public.admissoes
  FOR EACH ROW EXECUTE FUNCTION public.ponto_banco_liquidar_rescisao_trg();

COMMENT ON FUNCTION public.ponto_banco_liquidar_rescisao_trg() IS
  'No desligamento (admissoes -> status desligado / data_desligamento): liquida o saldo do banco de horas para a rescisao. Blindado — falha aqui nao quebra o desligamento. CLT art. 59, §3º.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | OK
--   funcao_existe  : t  (ponto_banco_liquidar_rescisao)
--   gatilho_existe : t  (trg_ponto_banco_liquidar_rescisao em admissoes)
-- ---------------------------------------------------------------------------
SELECT
  (to_regprocedure('public.ponto_banco_liquidar_rescisao(uuid,text,date)') IS NOT NULL) AS funcao_existe,
  (EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_ponto_banco_liquidar_rescisao'
     AND tgrelid='public.admissoes'::regclass AND NOT tgisinternal))                     AS gatilho_existe,
  CASE WHEN to_regprocedure('public.ponto_banco_liquidar_rescisao(uuid,text,date)') IS NOT NULL
        AND EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_ponto_banco_liquidar_rescisao'
              AND tgrelid='public.admissoes'::regclass AND NOT tgisinternal)
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;


-- ============================================================================

-- ---------------------------------------------------------------------
-- MEDICAO DE VOLUME (fim) — a mesma contagem, agora depois da parte.
-- ---------------------------------------------------------------------
DO $volume2$
DECLARE
  v record;
  n bigint;
  m text;
BEGIN
  FOR v IN SELECT tabela FROM public.ponto_entrega_volume
            WHERE parte = 8 AND tabela NOT LIKE '(copia)%'
  LOOP
    EXECUTE format('SELECT count(*) FROM public.%I', v.tabela) INTO n;
    m := NULL;
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name=v.tabela AND column_name='updated_at') THEN
      EXECUTE format('SELECT max(updated_at)::text FROM public.%I', v.tabela) INTO m;
    END IF;
    UPDATE public.ponto_entrega_volume
       SET linhas_depois = n, marca_depois = m
     WHERE parte = 8 AND tabela = v.tabela;
  END LOOP;
END $volume2$;

-- ============================================================================
-- CONFERENCIA DESTA PARTE — pecas e volume
-- ============================================================================
WITH esperado (tipo, nome, marcador) AS MATERIALIZED (
  VALUES
    ('funcao', 'ponto_banco_regime_vigente', NULL),
    ('funcao', 'apurar_banco_horas_colaborador', NULL),
    ('funcao', 'ponto_banco_alertas_monitorar', 'Saldo de banco de horas perto de vencer'),
    ('funcao', 'ponto_banco_limite_diario_monitorar', 'Jornada acima de 10h em regime de compensacao (CLT art. 59, §2º)'),
    ('funcao', 'ponto_apurar_ciclo_plantao_do_dia', NULL),
    ('funcao', 'ponto_banco_liquidar_rescisao', NULL),
    ('funcao', 'ponto_banco_liquidar_rescisao_trg', ' AND COALESCE(OLD.status::text, '),
    ('gatilho', 'trg_ponto_banco_liquidar_rescisao', NULL)
), estado AS MATERIALIZED (
  SELECT e.tipo, e.nome, e.marcador,
         CASE e.tipo
           WHEN 'funcao'  THEN EXISTS (SELECT 1 FROM pg_proc p
                                        JOIN pg_namespace n ON n.oid = p.pronamespace
                                       WHERE n.nspname = 'public' AND p.proname = e.nome
                                         AND (e.marcador IS NULL
                                              OR p.prosrc LIKE '%' || e.marcador || '%'))
           WHEN 'tabela'  THEN to_regclass('public.' || e.nome) IS NOT NULL
           WHEN 'indice'  THEN EXISTS (SELECT 1 FROM pg_indexes
                                       WHERE schemaname = 'public' AND indexname = e.nome)
           WHEN 'gatilho' THEN EXISTS (SELECT 1 FROM pg_trigger
                                       WHERE NOT tgisinternal AND tgname = e.nome)
           WHEN 'coluna'  THEN EXISTS (SELECT 1 FROM information_schema.columns
                                       WHERE table_schema = 'public'
                                         AND table_name  = split_part(e.nome, '.', 1)
                                         AND column_name = split_part(e.nome, '.', 2))
         END AS presente
  FROM esperado e
), volume AS MATERIALIZED (
  SELECT v.tabela, v.linhas_antes AS antes, COALESCE(v.linhas_depois, v.linhas_antes) AS agora,
         v.marca_antes, v.marca_depois
  FROM public.ponto_entrega_volume v
  WHERE v.parte = 8
)
SELECT 'peca faltando'::text AS o_que, tipo || ' ' || nome AS detalhe, 'FALTOU'::text AS situacao
FROM estado WHERE NOT presente
UNION ALL
SELECT 'volume', tabela || ': ' || antes || ' para ' || agora || ' linha(s)',
       CASE WHEN agora = antes THEN 'sem alteracao' ELSE 'MUDOU ' || (agora - antes) || ' linha(s)' END
FROM volume WHERE agora <> antes
UNION ALL
SELECT 'volume', tabela || ': conteudo alterado (ultima alteracao passou de '
       || COALESCE(marca_antes, '-') || ' para ' || COALESCE(marca_depois, '-') || ')',
       'CONFERIR — ou e movimento normal de cliente durante a execucao'
FROM volume WHERE marca_antes IS DISTINCT FROM marca_depois
  AND tabela <> ''
UNION ALL
SELECT 'RESUMO',
       (SELECT count(*) FROM estado WHERE presente)::text || ' de '
         || (SELECT count(*) FROM estado)::text || ' pecas no lugar; '
         || COALESCE((SELECT sum(abs(agora - antes)) FROM volume), 0)::text
         || ' linha(s) de dado vivo alteradas',
       CASE
         WHEN (SELECT count(*) FROM estado WHERE NOT presente) > 0 THEN 'CONFERIR — falta peca'
         WHEN false THEN 'OK'
         WHEN COALESCE((SELECT sum(abs(agora - antes)) FROM volume), 0) > 0
           THEN 'CONFERIR — esta parte nao deveria alterar dado vivo'
         ELSE 'OK'
       END
ORDER BY 1 DESC, 2;
