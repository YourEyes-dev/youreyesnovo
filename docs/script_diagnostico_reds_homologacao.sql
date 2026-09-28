-- ============================================================================
-- DIAGNÓSTICO (somente leitura) — causa de cada caso vermelho da bateria
--
-- Cole no SQL Editor da HOMOLOGAÇÃO e execute. NÃO altera nada: só lê os
-- resultados JÁ gravados pela última execução de "Todos os módulos".
--
-- Devolve, por caso falhou/erro: código, módulo, situação, o erro técnico e o
-- "obtido" (o ACHADO da rotina) — que é o que o PDF do relatório não mostra
-- para os "falhou". Com isso eu mapeio cada vermelho ao script de entrega que
-- já existe no projeto e monto a fila de portes por módulo.
--
-- Copie o resultado inteiro e me devolva.
--
-- (Se preferir o estado ATUAL em vez do último salvo, rode antes a bateria
--  "Todos os módulos" na tela do SuperAdmin; esta consulta lê a mais recente.)
-- ============================================================================

WITH ult AS (
  SELECT id
  FROM public.qa_execucoes
  WHERE modulo_path = 'todos'
  ORDER BY iniciada_em DESC
  LIMIT 1
)
SELECT ct.codigo,
       m.label                                                              AS modulo,
       r.situacao,
       left(regexp_replace(coalesce(r.erro_tecnico, ''), '\s+', ' ', 'g'), 240) AS erro_tecnico,
       left(regexp_replace(coalesce(r.obtido,      ''), '\s+', ' ', 'g'), 400) AS obtido
FROM public.qa_resultados r
JOIN ult                       ON ult.id = r.execucao_id
JOIN public.qa_casos_teste ct  ON ct.codigo = r.codigo
JOIN public.qa_modulos     m   ON m.id = ct.modulo_id
WHERE r.situacao IN ('falhou', 'erro')
ORDER BY m.label, ct.codigo;
