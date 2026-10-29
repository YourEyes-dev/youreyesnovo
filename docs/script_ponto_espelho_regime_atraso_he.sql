-- ============================================================================
-- SCRIPT DE ENTREGA (PRODUÇÃO) — espelho-resumo respeita o regime de banco
-- [espelho-regime-atraso-he]  ·  Plano do Ponto, Fase 1
--
-- Corrige: (D1) cobrança em dobro — com banco vigente o déficit ia para o
-- banco E para a folha como atraso; (D2) hora extra engolida — sem banco a HE
-- saía do saldo líquido do mês. Só muda he_50/he_100/atrasos do espelho.
--
-- Reinjeção idempotente no corpo VIGENTE (não reescreve a função; preserva os
-- remendos de equalização e do saldo pela fonte única). Se alguma âncora não
-- for encontrada, NADA é alterado e a conferência mostra marca_aplicada=false.
-- Só altera FUNÇÃO (não toca dado): não precisa de backup de linhas.
-- Competências já fechadas não mudam sozinhas.
--
-- COMO DESFAZER (se precisar): reinjetar o inverso — trocar, no corpo vigente,
-- cada trecho novo (CASE WHEN rg.tem ...) pelo original e
-- "FROM c CROSS JOIN LATERAL (...) rg /* [espelho-regime-atraso-he] */;" por "FROM c;".
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

-- Conferência (o editor mostra só este resultado)
SELECT json_build_object(
  'marca_aplicada', position('[espelho-regime-atraso-he]' IN pg_get_functiondef('public.ponto_espelho_resumo(uuid,text,text)'::regprocedure)) > 0,
  'remendo_equalizacao_preservado', position('[falta-nao-conta-equalizacao]' IN pg_get_functiondef('public.ponto_espelho_resumo(uuid,text,text)'::regprocedure)) > 0,
  'saldo_fonte_unica_preservado', position('ponto_banco_horas_oficial' IN pg_get_functiondef('public.ponto_espelho_resumo(uuid,text,text)'::regprocedure)) > 0
) AS resultado;
