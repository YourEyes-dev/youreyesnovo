-- =====================================================================
-- Chave primária de cada tabela — insumo da sincronia de UM cliente.
--
-- A cópia completa não precisa disto: ela trunca e recarrega, sem casar
-- linha com linha. A sincronia cirúrgica precisa, porque ela ATUALIZA a
-- linha que já existe na homologação — e o que liga as duas pontas é a
-- chave, que nunca é embaralhada (são uuid e inteiro; a máscara só toca
-- texto, json e listas).
--
-- Só chave de UMA coluna. Medido no schema: 353 das 354 tabelas do public
-- são assim; a única exceção (ponto_entrega_conferencia) não tem chave
-- primária nenhuma e por isso fica de fora da sincronia — sem chave não há
-- como dizer qual linha daqui é qual linha de lá. Tabela nova que nasça
-- sem chave também ficará de fora, e o passo avisa quantas foram.
--
-- Saída: schema.tabela|coluna_da_chave
-- Somente leitura.
-- =====================================================================
SELECT quote_ident(n.nspname) || '.' || quote_ident(t.relname)
       || '|' || quote_ident(a.attname)
  FROM pg_constraint c
  JOIN pg_class t       ON t.oid = c.conrelid
  JOIN pg_namespace n   ON n.oid = t.relnamespace
  JOIN pg_attribute a   ON a.attrelid = t.oid AND a.attnum = c.conkey[1]
 WHERE c.contype = 'p'
   AND array_length(c.conkey, 1) = 1
   AND t.relkind = 'r'
   AND (n.nspname = 'public' OR (n.nspname = 'auth' AND t.relname = 'users'))
 ORDER BY 1;
