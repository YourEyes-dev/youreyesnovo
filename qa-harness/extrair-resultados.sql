-- Extrai UM veredito por caso, ordenado por código (saída determinística).
-- Formato: <codigo>\t<situacao>  (passou | falhou | nao_implementado | erro)
SELECT DISTINCT ON (codigo) codigo, situacao::text
FROM public.qa_resultados
ORDER BY codigo, id DESC;
