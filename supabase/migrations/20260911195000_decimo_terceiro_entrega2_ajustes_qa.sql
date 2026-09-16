-- =========================================================
-- 13º Salário — Entrega 2, parte 4: um defeito meu e duas sondas de QA
--
-- 1) DUAS SONDAS DE QA ESCRITAS PARA O BANCO FROUXO
--    As travas da Entrega 2 quebraram duas rotinas que dependiam da
--    folga antiga — elas passaram a devolver 'erro' em vez de julgar o
--    sistema. As sondas se ajustam à regra nova; a regra fica.
--      · DEC13-041 gravava a sonda sem CPF — a unicidade da Entrega 2
--        só vale onde há CPF, então esse caso se resolveu sozinho;
--      · DEC13-070 gravava status 'pago' sem data de pagamento, que o
--        CHECK novo recusa. A sonda passa a informar a data — e o caso,
--        que existia para acusar a falta da trava, agora a encontra.
--
-- Requisitos YE-DP-13-001: RF-007, RNF-004.
-- =========================================================

SET lock_timeout = '10s';

-- ── 2. DEC13-070: a sonda informa a data de pagamento ─────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_070()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_id uuid; v_alterou boolean := false; v_trg text;
BEGIN
  -- A sonda grava e NÃO desfaz (padrão desta família). Com a unicidade
  -- da Entrega 2, rodar duas vezes colidiria com a própria linha da
  -- rodada anterior — então ela limpa o próprio rastro antes.
  DELETE FROM public.folha_13_calculo
   WHERE tenant_id = public.qa_sandbox_tenant_id()
     AND colaborador_id = 'qa-dec13-070';

  -- Pago exige data de pagamento desde a Entrega 2 (CHECK
  -- folha_13_calculo_pagamento_ck) — a sonda informa, como a tela faz.
  INSERT INTO public.folha_13_calculo
    (tenant_id, ano, colaborador_id, colaborador_nome, colaborador_cpf, parcela,
     valor_bruto, total_liquido, status, data_pagamento)
  VALUES (public.qa_sandbox_tenant_id(), extract(year from CURRENT_DATE)::int,
          'qa-dec13-070', 'QA Pago Editado', '00000000070', 2, 3000, 2500,
          'pago', CURRENT_DATE)
  RETURNING id INTO v_id;

  r.passo_ordem := 1;
  r.passo_acao := 'Editar diretamente o valor bruto de um cálculo com status PAGO';
  r.esperado := 'Bloqueado — valor pago só muda por reabertura com motivo, dupla aprovação e diferença';
  BEGIN
    UPDATE public.folha_13_calculo SET valor_bruto = 9999 WHERE id = v_id;
    SELECT (valor_bruto = 9999) INTO v_alterou FROM public.folha_13_calculo WHERE id = v_id;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_alterou := false; END;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: existe trilha de alteração na tabela do 13º?';
  r.esperado := 'Gatilho de auditoria registrando antes/depois (RNF-004: log imutável)';
  SELECT string_agg(DISTINCT t.tgname, ', ') INTO v_trg
  FROM pg_trigger t
  WHERE t.tgrelid = 'public.folha_13_calculo'::regclass AND NOT t.tgisinternal
    AND t.tgname NOT ILIKE '%updated_at%' AND t.tgname NOT ILIKE 'qa\_%';

  IF v_alterou AND v_trg IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: um cálculo PAGO foi editado em silêncio — o valor bruto mudou de 3.000 '
             || 'para 9.999 sem bloqueio, sem justificativa, sem aprovação e sem trilha. '
             || 'Correção: trava de UPDATE para status pago/fechado + fluxo de reabertura '
             || '(RF-007 do documento).';
  ELSIF NOT v_alterou THEN
    r.situacao := 'passou';
    r.obtido := format('A edição direta do cálculo pago foi recusada pela trava do banco%s.',
                       CASE WHEN v_trg IS NULL THEN '' ELSE ' (gatilhos: ' || v_trg || ')' END);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Alteração registrada em trilha (%s) — conferir se guarda antes/depois.', v_trg);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── 2. As regras dos encargos passam a viver no banco ─────────────────
-- Até aqui elas existiam só no cálculo da tela: quem gravasse por fora
-- (importação, script, integração) furava a regra sem resistência.
-- Casos DEC13-040, DEC13-041 e DEC13-042.

-- INSS e IRRF só na 2ª parcela (Lei 4.749/1965; RIR/2018 art. 700: a
-- tributação é exclusiva na fonte, apurada na 2ª sobre o valor integral).
DO $ck$
BEGIN
    ALTER TABLE public.folha_13_calculo
        ADD CONSTRAINT folha_13_calculo_encargos_2a_ck
        CHECK (parcela <> 1
               OR (COALESCE(valor_inss, 0) = 0 AND COALESCE(valor_irrf, 0) = 0
                   AND COALESCE(base_inss, 0) = 0 AND COALESCE(base_irrf, 0) = 0)) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

-- FGTS incide sobre a parcela paga, nunca sobre mais que o 13º cheio
-- (Lei 8.036 art. 15): a soma das duas bases fecha exatamente o bruto.
DO $ck$
BEGIN
    ALTER TABLE public.folha_13_calculo
        ADD CONSTRAINT folha_13_calculo_base_fgts_ck
        CHECK (COALESCE(base_fgts, 0) <= COALESCE(valor_bruto, 0)) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;

-- O adiantamento deduzido não pode superar o próprio 13º.
DO $ck$
BEGIN
    ALTER TABLE public.folha_13_calculo
        ADD CONSTRAINT folha_13_calculo_primeira_ck
        CHECK (COALESCE(valor_primeira_parcela, 0) <= COALESCE(valor_bruto, 0)) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL;
END $ck$;
