-- =========================================================
-- Correcao pontual — sonda de QA DEC13-070
--
-- O caso DEC13-070 acusa erro tecnico:
--   new row for relation "folha_13_calculo" violates check constraint
--   "folha_13_calculo_pagamento_ck"
--
-- Nao e defeito do sistema, e o contrario: a sonda foi escrita para o
-- banco ANTIGO, frouxo, e gravava status 'pago' sem data de pagamento.
-- A trava criada na Entrega 2 recusa isso — com razao, porque data de
-- pagamento e o que prova o cumprimento do prazo legal. A sonda se
-- ajusta a regra nova; a regra fica.
--
-- Este script substitui APENAS a rotina de teste. Nao toca em dado,
-- nem em regra, nem em calculo. Idempotente.
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

-- ── Conferencia ───────────────────────────────────────────────────────
SELECT 'sonda de QA DEC13-070 informa a data de pagamento' AS item,
       CASE WHEN position('data_pagamento' in p.prosrc) > 0 THEN 'OK' ELSE 'FALTOU' END AS situacao,
       CASE WHEN position('data_pagamento' in p.prosrc) > 0
            THEN 'rode a bateria do modulo de novo: o DEC13-070 deve passar'
            ELSE 'a rotina nao foi substituida' END AS erro_tecnico
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'qa_caso_dec13_070';
