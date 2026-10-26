-- ============================================================================
-- CONSULTA (somente leitura) — a camada de leitura por perfil esta nas tabelas
-- que o dashboard expoe? SEGURO rodar em PRODUCAO: nao altera nada, so consulta
-- o catalogo de politicas. Serve para a fundadora conferir se o furo do
-- DASH-PERFIL-01 ainda existe em producao ANTES de aplicar os scripts de entrega.
--
-- Como ler o resultado:
--   camada_perfil = 'OK (RESTRICTIVE/SELECT)'  -> protegida.
--   camada_perfil = 'FALTA'                     -> qualquer membro da empresa le
--                                                  essa tabela pela API (furo aberto).
-- Enquanto avaliacao_respostas / avaliacao_9box / metas aparecerem como 'FALTA'
-- em PRODUCAO, o vazamento existe la tambem (afastamentos/afastamentos_pendencias
-- ja foram fechados na entrega de 23/10).
-- ============================================================================
SELECT t.tabela,
       CASE WHEN to_regclass('public.' || t.tabela) IS NULL THEN 'tabela ausente nesta base'
            WHEN p.policyname IS NULL THEN 'FALTA'
            ELSE 'OK (' || p.permissive || '/' || p.cmd || ')' END AS camada_perfil
FROM (VALUES ('avaliacao_respostas'), ('avaliacao_9box'), ('metas'),
             ('afastamentos'), ('afastamentos_pendencias')) AS t(tabela)
LEFT JOIN pg_policies p
  ON p.schemaname = 'public'
 AND p.tablename = t.tabela
 AND p.policyname = 'perfil_restringe_leitura_' || t.tabela
ORDER BY t.tabela;
