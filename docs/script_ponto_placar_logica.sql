-- ============================================================================
-- PLACAR DO PONTO — classificador de drift (COSMETICO x LOGICA). SO LEITURA.
--
-- Por que este script existe:
--   O inventario de corpos (script_inventario_corpos_ponto.sql) traz o md5
--   NORMALIZADO, que colapsa espacos em branco mas NAO remove comentarios. Um
--   comentario reescrito muda esse md5 sem mudar UMA LINHA de comportamento —
--   entao "md5_normalizado diferente" ainda pode ser drift cosmetico. Alem
--   disso o corpo completo e enorme e nao cabe colado no chat sem cortar.
--
--   Este script resolve os dois problemas de uma vez: para cada funcao do
--   modulo ponto devolve DOIS hashes pequenos (sem o corpo):
--     * md5_logica       — corpo com COMENTARIOS E espacos removidos. Se este
--                          for igual nos dois ambientes, o comportamento e o
--                          mesmo (a diferenca, se houver, e so comentario).
--     * md5_normalizado   — so espacos colapsados (o mesmo do inventario), para
--                          separar "identico" de "so muda comentario".
--
-- COMO USAR:
--   1) rode ESTE script no SQL Editor do TESTE (bmehdgthciuvdbvutsdv);
--   2) rode o MESMO no SQL Editor da PRODUCAO (diayjpsrcerycycyaxst);
--   3) me mande os dois resultados INTEIROS (sao so 3 colunas curtas por linha —
--      cabem no chat sem cortar). Eu cruzo por objeto:
--        * md5_logica igual nos dois            -> SEM drift de logica (fim);
--        * md5_logica igual mas normalizado dif -> drift so de comentario/espaco;
--        * md5_logica diferente                 -> drift REAL de logica: eu leio
--                                                  as duas e digo o que mudou.
--
-- Observacao tecnica: a remocao de comentario e por texto (tira /* ... */ e
--   tudo apos --). Se algum comentario falso aparecer dentro de uma string, ele
--   e removido IGUAL nos dois ambientes, entao a comparacao continua valida.
--   Nao cria, nao altera, nao apaga nada.
-- ============================================================================

WITH fn AS MATERIALIZED (
  SELECT
    p.proname || '(' || pg_get_function_arguments(p.oid) || ')' AS objeto,
    pg_get_functiondef(p.oid)                                   AS def
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prokind = 'f'
    AND p.proname LIKE '%ponto%'
    AND p.proname NOT LIKE 'qa\_%'
)
SELECT
  objeto,
  md5(
    regexp_replace(                                   -- 3) colapsa espacos
      regexp_replace(                                 -- 2) tira comentario de linha (--...)
        regexp_replace(fn.def, '/\*.*?\*/', '', 'g'), -- 1) tira comentario de bloco
        '--[^' || chr(10) || ']*', '', 'g'),
      '\s+', ' ', 'g')
  )                                                            AS md5_logica,
  md5(regexp_replace(fn.def, '\s+', ' ', 'g'))                 AS md5_normalizado
FROM fn
ORDER BY objeto;
