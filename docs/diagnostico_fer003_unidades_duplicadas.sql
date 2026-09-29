-- ============================================================================
-- DIAGNÓSTICO FER-003 — unidades vinculadas a MAIS DE UMA tabela de feriados
--                       (SOMENTE LEITURA)
--
-- NÃO altera nada. Lista as empresas (unidades) que estão em duas ou mais tabelas
-- de feriados ao mesmo tempo — o que hoje o banco permite (o UNIQUE atual é
-- (tabela_id, empresa_id), não impede a mesma empresa em tabelas diferentes) e o
-- que trava a criação do índice único por unidade. A regra do produto é UMA
-- tabela por unidade (a tela faz delete-then-insert), então o vínculo correto é
-- o MAIS RECENTE.
--
-- "manter_sugestao" marca o vínculo mais recente de cada unidade como 'MANTER' e
-- os demais como 'remover'. Se para alguma unidade o certo NÃO for o mais
-- recente, ajuste o vínculo dela na tela antes de rodar o resolvedor.
-- ============================================================================

WITH dup AS MATERIALIZED (
  SELECT tenant_id, empresa_id
  FROM public.feriado_tabela_empresas
  GROUP BY tenant_id, empresa_id
  HAVING count(*) > 1
),
vinc AS MATERIALIZED (
  SELECT fte.id AS vinculo_id, fte.tenant_id, fte.empresa_id,
         COALESCE(e.nome_fantasia, e.razao_social, '(empresa)') AS empresa,
         ft.nome AS tabela_feriados,
         to_char(fte.created_at,'DD/MM/YYYY HH24:MI') AS vinculado_em,
         row_number() OVER (PARTITION BY fte.tenant_id, fte.empresa_id
                            ORDER BY fte.created_at DESC, fte.id) AS rn
  FROM public.feriado_tabela_empresas fte
  JOIN dup ON dup.tenant_id = fte.tenant_id AND dup.empresa_id = fte.empresa_id
  LEFT JOIN public.feriado_tabelas ft ON ft.id = fte.tabela_id
  LEFT JOIN public.empresa_cadastro e ON e.id = fte.empresa_id
)
SELECT empresa, tabela_feriados, vinculado_em,
       CASE WHEN rn = 1 THEN 'MANTER (mais recente)' ELSE 'remover' END AS manter_sugestao,
       empresa_id, vinculo_id
FROM vinc
ORDER BY empresa, rn;
