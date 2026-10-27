-- ============================================================================
-- CONSULTA (somente leitura) — a camada de leitura por perfil ja esta nas 8
-- tabelas CRITICAS da auditoria (PERFIL-AUD-007/005/002)? SEGURO rodar em
-- PRODUCAO: nao altera nada, so consulta o catalogo de politicas. Serve para a
-- fundadora conferir se o furo ainda existe ANTES de aplicar os scripts de entrega.
--
-- Como ler o resultado:
--   camada_perfil = 'OK (RESTRICTIVE/SELECT)'  -> protegida.
--   camada_perfil = 'FALTA'                     -> qualquer membro da empresa le
--                                                  essa tabela pela API (furo aberto).
-- Enquanto qualquer uma aparecer 'FALTA' em PRODUCAO, o vazamento existe la tambem.
-- ============================================================================
SELECT t.tabela,
       CASE WHEN to_regclass('public.' || t.tabela) IS NULL THEN 'tabela ausente nesta base'
            WHEN p.policyname IS NULL THEN 'FALTA'
            ELSE 'OK (' || p.permissive || '/' || p.cmd || ')' END AS camada_perfil
FROM (VALUES ('restricoes_laborais'), ('condicoes_especiais_historico'),
             ('humor_diario'), ('humor_historico'), ('onboarding_percepcao_cultural'),
             ('onboarding_respostas'), ('avaliacao_feedbacks'), ('feedbacks')) AS t(tabela)
LEFT JOIN pg_policies p
  ON p.schemaname = 'public'
 AND p.tablename = t.tabela
 AND p.policyname = 'perfil_restringe_leitura_' || t.tabela
ORDER BY t.tabela;
