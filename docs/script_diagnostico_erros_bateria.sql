-- ============================================================================
-- DIAGNOSTICO — o detalhe tecnico dos casos que deram ERRO na ultima bateria
--
-- POR QUE EXISTE
-- No relatorio (tela e PDF), um caso com situacao ERRO aparece apenas como
-- "A rotina quebrou". A causa fica na coluna erro_tecnico do resultado, que
-- o relatorio nao imprime. Sem ela nao da para separar o que e defeito do
-- sistema do que e falta de massa de teste no ambiente.
--
-- ERRO nao e o mesmo que FALHOU:
--   FALHOU = a rotina rodou e o sistema nao atende a regra (achado legitimo);
--   ERRO   = a rotina nao conseguiu chegar ao fim (faltou dado, permissao ou
--            estrutura no ambiente).
--
-- COMO USAR
-- Cole no SQL Editor do MESMO ambiente onde a bateria rodou, logo depois
-- dela. Traz a ultima execucao do modulo do Ponto; para outro modulo, troque
-- o caminho no filtro.
--
-- Somente leitura: nao cria, nao altera e nao apaga nada.
-- ============================================================================

WITH ultima AS MATERIALIZED (
  SELECT e.id
  FROM public.qa_execucoes e
  ORDER BY e.iniciada_em DESC
  LIMIT 1
)
SELECT c.codigo,
       left(c.titulo, 60) AS caso,
       r.passo_ordem      AS parou_no_passo,
       left(coalesce(r.passo_acao, ''), 70) AS passo,
       coalesce(r.erro_tecnico, '(sem detalhe)') AS erro_tecnico
FROM public.qa_resultados r
JOIN public.qa_casos_teste c ON c.id = r.caso_id
JOIN public.qa_modulos    m ON m.id = c.modulo_id
CROSS JOIN ultima u
WHERE r.execucao_id = u.id
  AND r.situacao = 'erro'
  AND m.path = 'jornada-rotina/ponto'
ORDER BY c.codigo;
