-- ============================================================================
-- DIAGNÓSTICO (SOMENTE LEITURA) — Banco de horas de uma empresa
-- Empresa CNPJ 26114701000145. Seguro rodar em PRODUÇÃO: não altera nada.
--
-- Mostra, por colaborador e competência (a partir de 2026-07):
--   · o saldo da FOTOGRAFIA (ponto_banco_horas) e seus componentes;
--   · o saldo OFICIAL ao vivo (ponto_banco_horas_oficial), que é o número que
--     o documento imprime e que o carry-over agora usa;
--   · a diferença entre os dois (se ≠ 0, a fotografia foi escrita "na mão" sem
--     um movimento que a explique — é o caso do zero fantasma);
--   · quantos movimentos MANUAIS existem (zeragem de verdade seria um movimento).
--
-- Como ler: uma linha com snap_saldo = 0, oficial_saldo <> 0 e movs_manuais = 0
-- é exatamente um saldo "zerado por escrita direta" — que não gruda, porque não
-- há movimento. A correção é registrar a liquidação como MOVIMENTO (ver plano).
-- ============================================================================

WITH emp AS (
  SELECT id AS empresa_id, tenant_id, cnpj
  FROM public.empresa_cadastro
  WHERE regexp_replace(COALESCE(cnpj, ''), '[^0-9]', '', 'g') IN (
    '26114701000145',  -- Itapejara
    '41085456000189',  -- Realeza
    '31219374000126'   -- Dois Vizinhos
  )
)
SELECT
  emp.cnpj AS empresa_cnpj,
  b.competencia,
  b.colaborador_nome,
  b.colaborador_cpf,
  b.saldo_anterior_minutos AS snap_anterior,
  b.creditos_minutos       AS snap_cred,
  b.debitos_minutos        AS snap_deb,
  b.compensados_minutos    AS snap_comp,
  b.saldo_atual_minutos    AS snap_saldo,
  o.saldo_atual_min        AS oficial_saldo,
  o.fonte,
  (b.saldo_atual_minutos - o.saldo_atual_min) AS diverg_snap_vs_oficial,
  (SELECT count(*) FROM public.ponto_banco_horas_movimentacoes m
     WHERE m.banco_horas_id = b.id
       AND COALESCE(m.origem, '') NOT IN ('apuracao', 'apuracao_auto')) AS movs_manuais
FROM public.ponto_banco_horas b
JOIN emp ON emp.empresa_id = b.empresa_id
LEFT JOIN LATERAL public.ponto_banco_horas_oficial(
  b.tenant_id, b.competencia, b.empresa_id, b.colaborador_cpf) o ON true
WHERE b.competencia >= '2026-07'
ORDER BY b.colaborador_nome, b.competencia;
