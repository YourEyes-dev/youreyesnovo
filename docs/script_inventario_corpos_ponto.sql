-- ============================================================================
-- INVENTARIO DE CORPOS — modulo PONTO (triagem de drift). SOMENTE LEITURA.
--
-- Nao cria, nao altera, nao apaga nada. So um SELECT que devolve, para cada
-- funcao de produto do modulo ponto (exclui as rotinas de QA qa_caso_ponto_*):
--   * objeto           — identidade (nome + argumentos);
--   * md5_bruto         — hash do corpo cru (pg_get_functiondef);
--   * md5_normalizado   — hash do corpo com todo espaco em branco colapsado;
--   * linhas            — tamanho aproximado (numero de linhas do corpo);
--   * corpo             — a definicao completa da funcao.
--
-- COMO USAR (a triagem do drift):
--   1) rode ESTE script no SQL Editor do TESTE (bmehdgthciuvdbvutsdv) e exporte
--      o resultado como CSV;
--   2) rode o MESMO script no SQL Editor da PRODUCAO (diayjpsrcerycycyaxst) e
--      exporte como CSV;
--   3) me mande os dois CSVs.
--
-- Com os dois em maos eu comparo por objeto:
--   * md5_normalizado igual nos dois  -> drift COSMETICO (so formatacao/espaco);
--   * md5_normalizado diferente        -> diferenca REAL de logica — ai eu leio
--                                         os dois corpos e digo o que mudou.
-- Assim separamos o que e so estetica do que muda comportamento, sem
-- sobrescrever nada no escuro.
-- ============================================================================

SELECT
  p.proname || '(' || pg_get_function_arguments(p.oid) || ')'        AS objeto,
  md5(pg_get_functiondef(p.oid))                                     AS md5_bruto,
  md5(regexp_replace(pg_get_functiondef(p.oid), '\s+', ' ', 'g'))    AS md5_normalizado,
  (length(pg_get_functiondef(p.oid))
     - length(replace(pg_get_functiondef(p.oid), E'\n', '')) + 1)    AS linhas,
  pg_get_functiondef(p.oid)                                          AS corpo
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prokind = 'f'
  AND p.proname LIKE '%ponto%'
  AND p.proname NOT LIKE 'qa\_%'
ORDER BY objeto;
