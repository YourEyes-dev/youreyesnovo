-- ============================================================================
-- DIAGNÓSTICO VIN-008 — "quais são os vínculos duplicados?" (SOMENTE LEITURA)
--
-- NÃO altera nada. Lista, para cada par usuário+empresa com mais de um vínculo
-- ATIVO, os vínculos concorrentes — para você decidir qual perfil vale e
-- desativar o(s) outro(s). Depois disso, o índice de unicidade do VIN-008 cria
-- sozinho (rode o script_vin008_homologacao de novo).
--
-- Não expõe CPF nem nome de pessoa (segue a convenção do diagnóstico A2): mostra
-- o id do vínculo, a conta, a empresa, o perfil, quem atribuiu e quando. O
-- usuario_id aparece como identificador técnico (UUID) para você casar as linhas.
--
-- "manter_sugestao" é só uma DICA: marca como 'MANTER (mais recente)' o vínculo
-- mais novo de cada par e 'revisar' os demais. A decisão é sua — o mais recente
-- nem sempre é o certo (pode ser o mais permissivo que você quer remover).
-- ============================================================================

WITH grupos AS MATERIALIZED (
  -- Pares (usuario, empresa) com mais de um vínculo ATIVO — a mesma regra do
  -- índice parcial do VIN-008.
  SELECT usuario_id,
         COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid) AS emp_key
  FROM public.usuario_perfil_vinculos
  WHERE COALESCE(ativo, true)
  GROUP BY 1, 2
  HAVING count(*) > 1
),
vinc AS MATERIALIZED (
  SELECT v.id                              AS vinculo_id,
         t.nome                            AS conta,
         v.usuario_id,
         COALESCE(e.nome_fantasia, e.razao_social, '(perfil padrão — sem empresa)') AS empresa,
         p.nome                            AS perfil,
         p.tipo                            AS perfil_tipo,
         v.ativo,
         v.atribuido_por_nome,
         v.observacao,
         v.created_at,
         row_number() OVER (
           PARTITION BY v.usuario_id,
                        COALESCE(v.empresa_id,'00000000-0000-0000-0000-000000000000'::uuid)
           ORDER BY v.created_at DESC, v.id
         ) AS rn
  FROM public.usuario_perfil_vinculos v
  JOIN grupos g
    ON g.usuario_id = v.usuario_id
   AND g.emp_key = COALESCE(v.empresa_id,'00000000-0000-0000-0000-000000000000'::uuid)
  LEFT JOIN public.perfis_acesso  p ON p.id = v.perfil_id
  LEFT JOIN public.empresa_cadastro e ON e.id = v.empresa_id
  LEFT JOIN public.tenants         t ON t.id = v.tenant_id
  WHERE COALESCE(v.ativo, true)
)
SELECT
  conta,
  usuario_id,
  empresa,
  perfil,
  perfil_tipo,
  atribuido_por_nome,
  observacao,
  to_char(created_at, 'DD/MM/YYYY HH24:MI') AS criado_em,
  CASE WHEN rn = 1 THEN 'MANTER (mais recente)?' ELSE 'revisar' END AS manter_sugestao,
  vinculo_id
FROM vinc
ORDER BY conta, usuario_id, empresa, created_at;

-- ============================================================================
-- COMO RESOLVER (depois de decidir, e SÓ na homologação primeiro):
--
-- Desvincular no sistema é marcar ativo = false (o histórico fica; o índice
-- parcial só conta os ativos). NÃO apague a linha — desative a que sobra.
--
-- 1) Guarde antes as linhas dos grupos (produção não tem PITR). Rode:
--      -- (via EXECUTE para não acionar o auto-RLS do editor)
--      DO $bkp$
--      BEGIN
--        IF to_regclass('public.backup_vin008_dupes_20260928') IS NULL THEN
--          EXECUTE 'CREATE ' || 'TABLE public.backup_vin008_dupes_20260928 AS
--            SELECT v.* FROM public.usuario_perfil_vinculos v
--             WHERE (v.usuario_id, COALESCE(v.empresa_id,''00000000-0000-0000-0000-000000000000''::uuid))
--                   IN (SELECT usuario_id, COALESCE(empresa_id,''00000000-0000-0000-0000-000000000000''::uuid)
--                         FROM public.usuario_perfil_vinculos WHERE COALESCE(ativo,true)
--                        GROUP BY 1,2 HAVING count(*) > 1)';
--        END IF;
--      END $bkp$;
--
-- 2) Para cada vínculo que você decidiu REMOVER, use o vinculo_id da lista:
--      UPDATE public.usuario_perfil_vinculos
--         SET ativo = false, updated_at = now()
--       WHERE id = '<cole_o_vinculo_id_aqui>';
--
-- 3) Rode o script_vin008_homologacao de novo — a conferência deve fechar
--    (0 duplicados, índice ok).
-- ============================================================================
