-- ============================================================================
-- DIAGNOSTICO — o ACHADO de cada caso que reprovou na ultima bateria
--
-- POR QUE EXISTE
-- O relatorio (tela e PDF) mostra, para cada caso reprovado, o objetivo do
-- teste e o campo tecnico do erro. O que ele NAO mostra e o campo "obtido" —
-- justamente onde a rotina escreve O QUE ENCONTROU no ambiente. Sem ele, dois
-- casos reprovados por motivos completamente diferentes (uma peca que falta
-- no ambiente x uma regra que o sistema nao cumpre) ficam identicos na leitura.
--
-- Lembrete da diferenca:
--   FALHOU = a rotina rodou e o ambiente nao atende a regra (achado legitimo);
--   ERRO   = a rotina nao conseguiu chegar ao fim.
--
-- COMO USAR
-- Cole no SQL Editor do MESMO ambiente onde a bateria rodou, logo depois dela.
-- Traz a ultima execucao do modulo do Ponto; para outro modulo, troque o
-- caminho no filtro.
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
       left(c.titulo, 55)                        AS caso,
       r.situacao,
       left(coalesce(r.obtido, '(sem achado registrado)'), 400) AS achado,
       left(coalesce(r.erro_tecnico, ''), 120)   AS detalhe_tecnico
FROM public.qa_resultados r
JOIN public.qa_casos_teste c ON c.id = r.caso_id
JOIN public.qa_modulos    m ON m.id = c.modulo_id
CROSS JOIN ultima u
WHERE r.execucao_id = u.id
  AND r.situacao IN ('falhou', 'erro')
  AND m.path = 'jornada-rotina/ponto'
ORDER BY r.situacao DESC, c.codigo;
