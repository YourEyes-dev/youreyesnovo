-- ============================================================================
-- LEVANTAMENTO (SOMENTE LEITURA) — quais tabelas decidem o acesso pelo PAPEL (manager/admin)
-- e NAO pelo perfil de acesso. Nao altera nada e nao devolve dado de ninguem: so nomes de
-- tabelas, de colunas e de politicas.
--
-- Rode a CONSULTA A (detalhe) e depois a B (resumo), uma por vez no SQL Editor, e cole o
-- resultado. Nivel: 1-CRITICO > 2-ALTO > 3-MEDIO > 4-BAIXO.
--   CRITICO : tabela sem RLS, ou com politica aberta (USING true) para quem nao e service_role.
--   ALTO    : leitura liberada por papel, SEM camada de perfil, e com coluna de dado pessoal/sensivel.
--   MEDIO   : leitura por papel sem camada de perfil (sem coluna sensivel), ou escrita por papel
--             sem camada de perfil.
--   BAIXO   : so politicas de tenant, sem papel nem perfil (ex.: tabela de apoio).
-- "camada de perfil" = politica que consulta perfil_permite_modulo / perfil_permite_acao /
-- perfil_escreve / perfil_amplo_sem_subordinados / ye_eh_dono / pode_gerir_acesso.
-- ============================================================================

-- ── CONSULTA A: detalhe por tabela (so as que NAO estao estruturadas) ────────
WITH tabelas AS MATERIALIZED (
  SELECT c.relname AS tabela, c.relrowsecurity AS rls, GREATEST(c.reltuples, 0)::bigint AS linhas_aprox
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind = 'r'
    AND c.relname NOT LIKE 'qa\_%' AND c.relname NOT LIKE 'backup\_%'
    AND EXISTS (SELECT 1 FROM information_schema.columns k
                 WHERE k.table_schema = 'public' AND k.table_name = c.relname AND k.column_name = 'tenant_id')
),
pol AS MATERIALIZED (
  SELECT p.tablename AS tabela, p.permissive, p.cmd, p.roles,
         lower(COALESCE(p.qual, '') || ' ' || COALESCE(p.with_check, '')) AS txt,
         COALESCE(p.qual, '') AS qual, COALESCE(p.with_check, '') AS wc
  FROM pg_policies p WHERE p.schemaname = 'public'
),
sens AS MATERIALIZED (
  SELECT k.table_name AS tabela, string_agg(k.column_name, ', ' ORDER BY k.column_name) AS colunas
  FROM information_schema.columns k
  WHERE k.table_schema = 'public'
    AND k.column_name ~* '(^cpf|_cpf|^rg$|cid|salario|remunera|atestado|diagnost|saude|nascimento|telefone|celular|e_?mail|endereco|^cep$|^pis$|ctps|biometr|selfie|denuncia|assedio|resposta|laudo|exame)'
  GROUP BY 1
),
agg AS MATERIALIZED (
  SELECT t.tabela, t.rls, t.linhas_aprox, COALESCE(s.colunas, '') AS colunas_sensiveis,
    COALESCE(bool_or(p.permissive = 'PERMISSIVE' AND p.cmd IN ('SELECT', 'ALL')
                     AND p.txt ~ 'has_(minimum_)?role'), false)                      AS le_por_papel,
    COALESCE(bool_or(p.permissive = 'PERMISSIVE' AND p.cmd IN ('INSERT', 'UPDATE', 'DELETE', 'ALL')
                     AND p.txt ~ 'has_(minimum_)?role'), false)                      AS escreve_por_papel,
    COALESCE(bool_or(p.txt ~ 'perfil_permite|perfil_escreve|perfil_amplo|ye_eh_dono|pode_gerir_acesso'), false) AS camada_perfil,
    COALESCE(bool_or(p.txt ~ 'tipo_usuario'), false)                                  AS usa_tipo_usuario,
    COALESCE(bool_or(p.permissive = 'PERMISSIVE' AND (btrim(p.qual) = 'true' OR btrim(p.wc) = 'true')
                     AND NOT (p.roles = ARRAY['service_role']::name[])), false)       AS politica_aberta,
    count(p.tabela) AS n_politicas
  FROM tabelas t
  LEFT JOIN sens s ON s.tabela = t.tabela
  LEFT JOIN pol p ON p.tabela = t.tabela
  GROUP BY t.tabela, t.rls, t.linhas_aprox, s.colunas
)
SELECT
  CASE WHEN NOT rls OR politica_aberta                           THEN '1-CRITICO'
       WHEN le_por_papel AND NOT camada_perfil AND colunas_sensiveis <> '' THEN '2-ALTO'
       WHEN (le_por_papel OR escreve_por_papel) AND NOT camada_perfil      THEN '3-MEDIO'
       WHEN usa_tipo_usuario AND NOT camada_perfil                         THEN '3-MEDIO'
       ELSE '4-BAIXO' END                                          AS nivel,
  tabela,
  CASE WHEN NOT rls THEN 'SEM RLS' WHEN politica_aberta THEN 'POLITICA ABERTA'
       ELSE concat_ws(' + ', CASE WHEN le_por_papel THEN 'le por papel' END,
                              CASE WHEN escreve_por_papel THEN 'escreve por papel' END,
                              CASE WHEN usa_tipo_usuario THEN 'usa tipo_usuario' END) END AS motivo,
  linhas_aprox, left(colunas_sensiveis, 110) AS colunas_sensiveis, camada_perfil, n_politicas
FROM agg
WHERE NOT camada_perfil
  AND (NOT rls OR politica_aberta OR le_por_papel OR escreve_por_papel OR usa_tipo_usuario)
ORDER BY 1, linhas_aprox DESC, tabela;

-- ── CONSULTA B: arquivos (storage) liberados por papel (rode separado) ───────
-- Mostra as politicas de leitura/escrita de arquivos que decidem por papel, sem consultar o perfil.
SELECT p.policyname, p.cmd, left(regexp_replace(COALESCE(p.qual, p.with_check, ''), '\s+', ' ', 'g'), 220) AS regra
FROM pg_policies p
WHERE p.schemaname = 'storage' AND p.tablename = 'objects'
  AND lower(COALESCE(p.qual, '') || ' ' || COALESCE(p.with_check, '')) ~ 'has_(minimum_)?role'
  AND lower(COALESCE(p.qual, '') || ' ' || COALESCE(p.with_check, '')) !~ 'perfil_permite|perfil_escreve|ye_eh_dono'
ORDER BY p.policyname;
