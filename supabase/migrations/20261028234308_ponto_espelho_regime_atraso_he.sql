-- ============================================================================
-- Ponto — espelho-resumo respeita o regime de banco de horas
-- [espelho-regime-atraso-he]
-- ----------------------------------------------------------------------------
-- Dois defeitos confirmados com dados (staging, out/2026) e na produção
-- (1 caso em jul/2026):
--
-- D1 — COBRANÇA EM DOBRO com banco vigente: o espelho devolvia
--   atrasos_min = total_debitos_min sem olhar o regime. O mesmo déficit era
--   debitado no banco de horas E exportado para a folha como "atrasos"
--   (fechamento -> ponto_espelhos -> aba Folha / pacote). CLT art. 59 §§2º/5º
--   e art. 462: com banco vigente o déficit compensável vai só para o banco.
--
-- D2 — HORA EXTRA ENGOLIDA sem banco: a HE saía do saldo LÍQUIDO do mês
--   (créditos − débitos), então 60 min extras num dia + 90 de déficit noutro
--   davam HE 0 e ainda 90 de atraso. Sem acordo de compensação a HE é paga
--   integral (CF art. 7º XIII/XVI; CLT art. 59 §1º) e o déficit é descontado
--   à parte, como hora simples.
--
-- O QUE MUDA (só três colunas de saída; assinatura e demais colunas iguais):
--   regime vigente (mesma checagem do banco oficial: ponto_banco_regime_vigente
--   com colaborador_id NULL, no fim da competência — concorda com o tem_regime
--   da aba Folha):
--     he_50 / he_100 : iguais (saldo do ciclo; a aba Folha credita no banco)
--     atrasos_min    : 0   (o déficit já foi debitado no banco)
--   sem regime:
--     he_100 = crédito bruto em domingo/feriado
--     he_50  = créditos brutos do mês − he_100
--     atrasos_min = total de débitos (desconto à parte)
--
-- COMO (CLAUDE.md: funções do Ponto são remendadas por string — nunca
-- CREATE OR REPLACE a partir de base antiga): reinjeção idempotente no corpo
-- VIGENTE. Quatro trechos são trocados; cada um precisa aparecer exatamente
-- uma vez, senão NADA é alterado (só aviso). Preserva os remendos
-- [falta-nao-conta-equalizacao] e o saldo do banco pela fonte única.
-- ponto_espelho_resumo_empresa delega para esta função e herda a correção.
-- Competências já fechadas (ponto_espelhos) não mudam sozinhas.
-- ============================================================================

DO $patch$
DECLARE
  v_src text;
  v_new text;
  v_old_he50 text := 'GREATEST(0, (v_saldo_ant + c.saldo_min) - LEAST(c.credito_100_min, GREATEST(0, v_saldo_ant + c.saldo_min)))::int AS he_50_min';
  v_new_he50 text := 'CASE WHEN rg.tem'
    || ' THEN GREATEST(0, (v_saldo_ant + c.saldo_min) - LEAST(c.credito_100_min, GREATEST(0, v_saldo_ant + c.saldo_min)))'
    || ' ELSE GREATEST(0, c.total_creditos_min - c.credito_100_min) END::int AS he_50_min';
  v_old_he100 text := 'LEAST(c.credito_100_min, GREATEST(0, v_saldo_ant + c.saldo_min))::int AS he_100_min';
  v_new_he100 text := 'CASE WHEN rg.tem'
    || ' THEN LEAST(c.credito_100_min, GREATEST(0, v_saldo_ant + c.saldo_min))'
    || ' ELSE c.credito_100_min END::int AS he_100_min';
  v_old_atr text := 'c.total_debitos_min AS atrasos_min';
  v_new_atr text := 'CASE WHEN rg.tem THEN 0 ELSE c.total_debitos_min END::int AS atrasos_min';
  v_old_from text := 'FROM c;';
  v_new_from text := 'FROM c CROSS JOIN LATERAL ('
    || ' SELECT (rv.id IS NOT NULL) AS tem'
    || ' FROM public.ponto_banco_regime_vigente(p_tenant_id, v_cpf, NULL::text, v_fim) rv'
    || ' ) rg /* [espelho-regime-atraso-he] */;';
  v_ok boolean;
BEGIN
  v_src := pg_get_functiondef('public.ponto_espelho_resumo(uuid,text,text)'::regprocedure);

  IF position('[espelho-regime-atraso-he]' IN v_src) > 0 THEN
    RAISE NOTICE 'ponto_espelho_resumo: [espelho-regime-atraso-he] ja aplicado; nada a fazer.';
    RETURN;
  END IF;

  -- Cada âncora precisa aparecer exatamente uma vez no corpo vigente.
  v_ok := (length(v_src) - length(replace(v_src, v_old_he50,  ''))) = length(v_old_he50)
      AND (length(v_src) - length(replace(v_src, v_old_he100, ''))) = length(v_old_he100)
      AND (length(v_src) - length(replace(v_src, v_old_atr,   ''))) = length(v_old_atr)
      AND (length(v_src) - length(replace(v_src, v_old_from,  ''))) = length(v_old_from);

  IF NOT v_ok THEN
    RAISE NOTICE 'ponto_espelho_resumo: ancoras de [espelho-regime-atraso-he] NAO encontradas (ou repetidas); nada alterado — revisar manualmente.';
    RETURN;
  END IF;

  v_new := replace(v_src, v_old_he50, v_new_he50);
  v_new := replace(v_new, v_old_he100, v_new_he100);
  v_new := replace(v_new, v_old_atr, v_new_atr);
  v_new := replace(v_new, v_old_from, v_new_from);
  EXECUTE v_new;
  RAISE NOTICE 'ponto_espelho_resumo: [espelho-regime-atraso-he] aplicado.';
END;
$patch$;

-- ---------------------------------------------------------------------
-- QA PONTO-487 — com banco vigente, o atraso NÃO vai para a folha
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_487()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid;
  v_cpf text := public.qa_cpf(4871);
  v_d1 date;
  v_comp text;
  v_e RECORD;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Colaborador COM banco de horas vigente trabalha 6h30 de uma jornada de 8h';
  r.esperado    := 'Espelho: debitos 90, atrasos para a folha 0 (o deficit fica so no banco)';

  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();
  -- Datas fixas, passadas e sem feriado nacional (terça e quarta): data móvel
  -- cairia num feriado em alguns meses (ex.: 02/11) e o dia viria protegido.
  v_d1   := DATE '2026-08-11';
  v_comp := to_char(v_d1, 'YYYY-MM');

  -- Regime vigente garantido (sem exigência de acordo); a bateria desfaz ao fim.
  INSERT INTO public.ponto_banco_horas_config
    (tenant_id, tipo, prazo_compensacao_dias, permite_saldo_negativo,
     exige_acordo_individual, exige_cct_act, data_inicio, ativo)
  VALUES (v_t, 'individual', 180, true, false, false, DATE '2025-01-01', true);

  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Espelho Banco', 480, 10, v_d1, v_d1);
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Espelho Banco', v_d1, 390);   -- -90

  SELECT * INTO v_e FROM public.ponto_espelho_resumo(v_t, v_cpf, v_comp) LIMIT 1;

  IF v_e IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'O espelho nao devolveu linha para o colaborador da massa de teste.';
  ELSIF COALESCE(v_e.total_debitos_min, 0) = 90 AND COALESCE(v_e.atrasos_min, -1) = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'Com banco vigente o deficit de 90 min fica so no banco: debitos 90, atrasos para a folha 0.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: com banco vigente o espelho manda %s min de atraso para a folha '
             || '(debitos %s). O mesmo deficit seria debitado no banco E descontado na folha '
             || '(cobranca em dobro, CLT art. 462).',
             coalesce(v_e.atrasos_min::text, 'nulo'), coalesce(v_e.total_debitos_min::text, 'nulo'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

-- ---------------------------------------------------------------------
-- QA PONTO-488 — sem banco, HE é paga integral e o atraso sai à parte
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_488()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid;
  v_cpf text := public.qa_cpf(4881);
  v_d1 date;
  v_comp text;
  v_e RECORD;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Colaborador SEM banco de horas: +60 min num dia e -90 min no outro';
  r.esperado    := 'Espelho: HE 60 (integral) e atrasos 90 (separados), sem abater um do outro';

  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();
  -- Datas fixas, passadas e sem feriado nacional (terça e quarta): data móvel
  -- cairia num feriado em alguns meses (ex.: 02/11) e o dia viria protegido.
  v_d1   := DATE '2026-08-11';
  v_comp := to_char(v_d1, 'YYYY-MM');

  -- Sem instrumento de compensação: desliga os regimes do cercado (a bateria
  -- desfaz tudo ao fim do caso — qa_executar_descartavel).
  UPDATE public.ponto_banco_horas_config SET ativo = false WHERE tenant_id = v_t;

  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Espelho Sem Banco', 480, 10, v_d1, v_d1 + 1);
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Espelho Sem Banco', v_d1, 540);       -- +60
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Espelho Sem Banco', v_d1 + 1, 390);   -- -90

  SELECT * INTO v_e FROM public.ponto_espelho_resumo(v_t, v_cpf, v_comp) LIMIT 1;

  IF v_e IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'O espelho nao devolveu linha para o colaborador da massa de teste.';
  ELSIF COALESCE(v_e.he_50_min, 0) + COALESCE(v_e.he_100_min, 0) = 60
        AND COALESCE(v_e.atrasos_min, -1) = 90 THEN
    r.situacao := 'passou';
    r.obtido := 'Sem banco a HE de 60 min e paga integral e os 90 min de atraso saem a parte.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: sem banco o espelho paga HE %s (esperado 60) e atrasos %s (esperado 90). '
             || 'Abater a HE de um dia com a ausencia de outro, sem acordo de compensacao, '
             || 'deixa de pagar hora extra devida (CF art. 7 XIII/XVI; CLT art. 59 par. 1).',
             COALESCE(v_e.he_50_min, 0) + COALESCE(v_e.he_100_min, 0),
             coalesce(v_e.atrasos_min::text, 'nulo'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

-- ---------------------------------------------------------------------
-- QA PONTO-489 — guarda: os remendos do espelho continuam no corpo vigente
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_489()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_src text;
  v_faltam text[] := ARRAY[]::text[];
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Ler o corpo vigente de ponto_espelho_resumo';
  r.esperado    := 'Os tres remendos presentes: regime x atraso/HE, equalizacao nao e falta, saldo pela fonte unica';

  v_src := pg_get_functiondef('public.ponto_espelho_resumo(uuid,text,text)'::regprocedure);
  IF position('[espelho-regime-atraso-he]' IN v_src) = 0 THEN
    v_faltam := v_faltam || '[espelho-regime-atraso-he]'::text; END IF;
  IF position('[falta-nao-conta-equalizacao]' IN v_src) = 0 THEN
    v_faltam := v_faltam || '[falta-nao-conta-equalizacao]'::text; END IF;
  IF position('ponto_banco_horas_oficial' IN v_src) = 0 THEN
    v_faltam := v_faltam || 'saldo pela fonte unica (ponto_banco_horas_oficial)'::text; END IF;

  IF cardinality(v_faltam) = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'Os tres remendos do espelho estao no corpo vigente.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o espelho perdeu remendo(s): ' || array_to_string(v_faltam, ', ')
             || '. Provavel CREATE OR REPLACE a partir de base antiga — reinjetar (ver CLAUDE.md).';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

-- ---------------------------------------------------------------------
-- Documentação dos casos + ligação com as rotinas
-- ---------------------------------------------------------------------
INSERT INTO public.qa_casos_teste
  (codigo, modulo_id, titulo, objetivo, tipo, nivel, prioridade, status,
   base_legal, passos, disposicao, observacoes)
SELECT v.codigo, m.id, v.titulo, v.objetivo, v.tipo::public.qa_caso_tipo, 'api', 'critica', 'aprovado',
       v.base_legal, v.passos, 'em_triagem', v.observacoes
FROM public.qa_modulos m
CROSS JOIN (VALUES
  ('PONTO-487',
   'Com banco de horas vigente, o atraso não vai para a folha',
   'O déficit parcial de quem tem regime de banco vigente é debitado no banco de horas. '
   || 'O espelho-resumo (que alimenta fechamento, aba Folha e pacote) não pode mandá-lo também '
   || 'como atraso: seria cobrança em dobro.',
   'negativo',
   'CLT art. 59, §§2º e 5º; art. 462',
   jsonb_build_array(
     jsonb_build_object('ordem', 1, 'acao', 'Colaborador com banco vigente trabalha 6h30 de 8h',
                        'esperado', 'Espelho: débitos 90, atrasos 0')),
   'Nasceu da validação da Fase 1 do plano do Ponto (out/2026); 1 caso real em jul/2026.'),
  ('PONTO-488',
   'Sem banco de horas, a hora extra é paga integral e o atraso sai à parte',
   'Sem acordo de compensação não se abate a hora extra de um dia com a ausência de outro: '
   || 'a HE vem do crédito bruto do mês e o déficit é descontado separado.',
   'negativo',
   'CF art. 7º, XIII e XVI; CLT art. 59, §1º; Súmula 85 TST',
   jsonb_build_array(
     jsonb_build_object('ordem', 1, 'acao', 'Sem banco: +60 num dia, -90 no outro',
                        'esperado', 'Espelho: HE 60, atrasos 90')),
   'Fase 1 do plano do Ponto (out/2026).'),
  ('PONTO-489',
   'Guarda: os remendos do espelho-resumo continuam aplicados',
   'ponto_espelho_resumo é remendado por string em runtime; um CREATE OR REPLACE a partir de '
   || 'base antiga apagaria as correções em silêncio. A guarda confere as três marcas no corpo vigente.',
   'excecao',
   'Integridade do cálculo (CLT art. 59; Portaria MTP 671/2021, art. 74)',
   jsonb_build_array(
     jsonb_build_object('ordem', 1, 'acao', 'Ler o corpo vigente da função',
                        'esperado', 'Marcas [espelho-regime-atraso-he], [falta-nao-conta-equalizacao] e fonte única presentes')),
   'Fase 1 do plano do Ponto (out/2026).')
) AS v(codigo, titulo, objetivo, tipo, base_legal, passos, observacoes)
WHERE m.path = 'jornada-rotina/ponto'
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
  ('PONTO-487', 'qa_caso_ponto_487', true),
  ('PONTO-488', 'qa_caso_ponto_488', true),
  ('PONTO-489', 'qa_caso_ponto_489', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

DO $fim$
BEGIN
  RAISE NOTICE 'Espelho-resumo respeita o regime de banco: sem cobranca em dobro, sem HE engolida.';
END $fim$;
