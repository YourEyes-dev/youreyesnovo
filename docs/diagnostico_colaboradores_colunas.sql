-- ============================================================================
-- DIAGNÓSTICO 3 (DECISIVO) — "Selecionar Colaborador" vazio no Novo Atestado
--                            (SOMENTE LEITURA — não altera nada)
--
-- Causa provável: a tela lê os colaboradores da tabela `admissoes` pedindo uma
-- lista FIXA de colunas. Se UMA dessas colunas não existir no banco, o servidor
-- (PostgREST) recusa a consulta INTEIRA (erro 400) e a tela recebe lista vazia —
-- exatamente o sintoma. A consulta de atestados NÃO pede a coluna nova, por isso
-- os atestados continuam aparecendo enquanto os colaboradores somem.
--
-- A coluna `cargo_id` foi adicionada em 28/09 (Onda 2). Ela entra sozinha no
-- ambiente de teste (esteira), mas na homologação e na produção só existe depois
-- de colar o script `docs/script_admissoes_cargo_id.sql` à mão. Se ela faltar
-- aqui, este diagnóstico aponta.
--
-- Rode no SQL Editor do MESMO ambiente onde a tela está vazia.
-- Qualquer linha "FALTA" é a causa; o alvo mais provável é `cargo_id`.
-- ============================================================================

WITH esperadas(ord, col) AS (
  VALUES
    (1,'id'),(2,'nome_completo'),(3,'cpf'),(4,'cargo'),(5,'cargo_id'),
    (6,'departamento'),(7,'email'),(8,'celular'),(9,'filial'),
    (10,'data_admissao'),(11,'empresa_id'),(12,'gestor_imediato'),
    (13,'foto_url'),(14,'tipo_contrato'),(15,'bate_ponto'),(16,'inativo')
)
SELECT
  e.col AS coluna_que_a_tela_pede,
  CASE WHEN c.column_name IS NULL
       THEN 'FALTA — quebra o SELECT inteiro (lista vem vazia)'
       ELSE 'ok' END AS situacao
FROM esperadas e
LEFT JOIN information_schema.columns c
  ON c.table_schema = 'public'
 AND c.table_name  = 'admissoes'
 AND c.column_name = e.col
ORDER BY (c.column_name IS NOT NULL), e.ord;
