-- ============================================================================
-- DIAGNÓSTICO — valores de empresa_cadastro.tipo_pessoa fora de {pj, pf, NULL}
--               (SOMENTE LEITURA)
--
-- NÃO altera nada. A CHECK chk_empresa_tipo_pessoa só aceita 'pj'/'pf'/NULL, e o
-- script de normalização converteu só as variantes de 'juridica'/'fisica'.
-- Sobraram valores inválidos com OUTRA grafia/conteúdo — este diagnóstico mostra
-- exatamente quais são e quantas linhas cada um tem, para decidir o mapeamento
-- (ex.: 'mei' → 'pj'? 'PJ' maiúsculo → 'pj'? lixo → NULL?).
--
-- Enquanto houver qualquer valor fora de {pj,pf,NULL}:
--   • a constraint NÃO pode ser validada (VALIDATE CONSTRAINT falha);
--   • QUALQUER update dessas linhas falha com 23514 — inclusive telas reais
--     (ex.: o recount de cotas do gatilho de admissão ao cadastrar colaborador).
-- ============================================================================

SELECT
  tipo_pessoa AS valor_invalido,
  count(*)     AS linhas,
  -- amostra de como normalizar: o que 'parece' (só sugestão, não aplica nada)
  CASE
    WHEN lower(btrim(tipo_pessoa)) LIKE 'p%j%' OR lower(btrim(tipo_pessoa)) LIKE '%jur%' THEN 'sugere pj'
    WHEN lower(btrim(tipo_pessoa)) LIKE 'p%f%' OR lower(btrim(tipo_pessoa)) LIKE '%fis%' OR lower(btrim(tipo_pessoa)) LIKE '%fís%' THEN 'sugere pf'
    WHEN lower(btrim(tipo_pessoa)) IN ('mei','micro','microempreendedor') THEN 'sugere pj (MEI é PJ)'
    ELSE 'indefinido — revisar'
  END AS sugestao
FROM public.empresa_cadastro
WHERE tipo_pessoa IS NOT NULL
  AND tipo_pessoa NOT IN ('pj','pf')
GROUP BY tipo_pessoa
ORDER BY count(*) DESC;
