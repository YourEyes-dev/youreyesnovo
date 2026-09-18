-- =========================================================
-- QA 13º — as sondas apertadas vêm por último
--
-- A documentação de testes tem duas levas. A 1ª traz as sondas DEC13-050
-- e DEC13-070 nas versões antigas: a de 050 aceitava qualquer função com
-- "anual" no texto (passava de graça) e a de 070 gravava status 'pago'
-- sem data de pagamento (que a trava da Entrega 2 recusa, com razão).
--
-- Nas migrations isso já estava certo pela ordem dos carimbos. No script
-- de entrega único, porém, a 1ª leva é aplicada depois — e sobrescrevia
-- as versões apertadas. Esta migration existe para que as duas pontas
-- fiquem iguais: o ambiente de teste (migrations) e os demais (script).
--
-- Somente rotinas de teste: não altera cálculo, regra nem dado.
-- =========================================================

SET lock_timeout = '10s';


-- ── DEC13-050: cobra as funções do eSocial pelo nome ──────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_050()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_unq       text;
  v_validar   boolean;
  v_gerar     boolean;
  v_anual     boolean;
  v_faltando  text[] := ARRAY[]::text[];
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a folha anual do 13º tem eventos, validação prévia e anti-duplicidade?';
  r.esperado := 'S-1200 (apuração anual, indApuracao=2) e S-1210 (pagamentos), validação antes do envio e unicidade por origem';

  IF to_regclass('public.esocial_transmissoes') IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A tabela de transmissões do eSocial não existe nesta base.';
    RETURN r;
  END IF;

  -- unicidade: vale constraint OU índice único (o índice parcial é o que
  -- permite refazer o evento depois de um erro ou cancelamento)
  SELECT string_agg(nome, ', ') INTO v_unq FROM (
    SELECT conname AS nome FROM pg_constraint
     WHERE conrelid = 'public.esocial_transmissoes'::regclass AND contype = 'u'
    UNION
    SELECT c.relname FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
     WHERE i.indrelid = 'public.esocial_transmissoes'::regclass
       AND i.indisunique AND NOT i.indisprimary
  ) u;

  SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'decimo_terceiro_esocial_validar')
    INTO v_validar;
  SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'decimo_terceiro_esocial_gerar')
    INTO v_gerar;
  SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'decimo_terceiro_esocial_gerar'
                    AND p.prosrc LIKE '%indApuracao>2<%')
    INTO v_anual;

  IF NOT v_validar THEN v_faltando := array_append(v_faltando, 'validação prévia do 13º (decimo_terceiro_esocial_validar)'); END IF;
  IF NOT v_gerar   THEN v_faltando := array_append(v_faltando, 'montagem dos eventos (decimo_terceiro_esocial_gerar)'); END IF;
  IF v_gerar AND NOT v_anual THEN v_faltando := array_append(v_faltando, 'apuração ANUAL no S-1200 (indApuracao = 2)'); END IF;
  IF v_unq IS NULL THEN v_faltando := array_append(v_faltando, 'anti-duplicidade em esocial_transmissoes'); END IF;

  IF array_length(v_faltando, 1) IS NOT NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO (terceiro da série ADM-093/FERIAS-081, agora pela folha ANUAL): falta '
             || array_to_string(v_faltando, '; ') || '. A competência anual tem regra própria de '
             || 'retificação e prazo; sem os eventos, o 13º pago não existe para o governo — e a '
             || 'DCTFWeb de dezembro não fecha com a folha. Correção: geração dos dois eventos no '
             || 'fechamento (apuração e pagamento), chave natural (vínculo + tipo + competência '
             || 'anual) e tradução de rejeição em instrução, nunca reenvio às cegas.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Proteções presentes: validação prévia e montagem do S-1200 anual e do S-1210, com unicidade (%s).', v_unq);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-070: informa a data de pagamento ────────────────────────────
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
