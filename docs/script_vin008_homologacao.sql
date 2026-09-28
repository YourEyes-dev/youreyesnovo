-- ============================================================================
-- ENTREGA — VIN-008 (vínculo duplicado na mesma empresa recusado) — HOMOLOGAÇÃO
--
-- Cole no SQL Editor da HOMOLOGAÇÃO; depois de conferido, o MESMO na PRODUÇÃO.
--
-- VIN-008: o mesmo usuário não pode ter dois vínculos ATIVOS na mesma empresa
--   (dois níveis valendo ao mesmo tempo aplicam sempre o mais permissivo —
--   rebaixar alguém deixaria de funcionar). A trava é um índice único PARCIAL
--   (só vínculos ativos; empresa_id com COALESCE porque o perfil padrão nasce
--   sem empresa e dois desses também não podem coexistir).
--
-- IMPORTANTE — este caso pode depender de TRIAGEM humana:
--   Se a base já tiver pares usuário+empresa com mais de um vínculo ativo, criar
--   o índice falharia. O script então NÃO cria o índice e AVISA a contagem —
--   apagar/desativar vínculo é mexer em permissão de gente real, decisão sua,
--   não do script. Nesse caso: resolva os duplicados (decidindo qual perfil
--   vale) e rode de novo. A conferência final mostra quantos pares restam.
--
-- SEGURANÇA: só CREATE UNIQUE INDEX (guardado). Não cria tabela, não apaga dado.
--   Idempotente. usuario_perfil_vinculos é tabela de permissão (baixo volume).
--
-- Origem: migration 20260916210000 (seção VIN-008). Ao fim, conferência.
-- ============================================================================

SET lock_timeout = '10s';

DO $uniq$
DECLARE v_dups int;
BEGIN
  SELECT count(*) INTO v_dups FROM (
    SELECT usuario_id, COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid)
    FROM public.usuario_perfil_vinculos
    WHERE COALESCE(ativo, true)
    GROUP BY 1, 2 HAVING count(*) > 1
  ) d;

  IF v_dups > 0 THEN
    RAISE NOTICE 'VIN-008 NAO CORRIGIDO: existem % par(es) usuario+empresa com mais de um vinculo ativo. O indice de unicidade nao foi criado. Resolva os duplicados (decidindo qual perfil vale) e rode de novo.', v_dups;
  ELSE
    CREATE UNIQUE INDEX IF NOT EXISTS usuario_perfil_vinculos_ativo_uidx
      ON public.usuario_perfil_vinculos
         (usuario_id, COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid))
      WHERE COALESCE(ativo, true);
    RAISE NOTICE 'VIN-008 corrigido: indice de unicidade criado.';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'VIN-008: indice de unicidade nao criado: %', SQLERRM;
END $uniq$;

-- ════════════════════ CONFERÊNCIA (única) ════════════════════════════════════
-- Ideal: duplicados = 0 E índice presente = ok. Se duplicados > 0, o índice
-- fica ausente de propósito — resolva os pares e rode de novo.
WITH conf AS MATERIALIZED (
  SELECT 'VIN-008 · pares usuário+empresa duplicados ativos (ideal 0)'::text AS item,
         (SELECT count(*)::text FROM (
            SELECT usuario_id, COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid)
            FROM public.usuario_perfil_vinculos WHERE COALESCE(ativo, true)
            GROUP BY 1,2 HAVING count(*) > 1) d) AS situacao
  UNION ALL
  SELECT 'VIN-008 · índice de unicidade (ativo)'::text,
         CASE WHEN EXISTS (SELECT 1 FROM pg_class WHERE relname='usuario_perfil_vinculos_ativo_uidx' AND relkind='i')
              THEN 'ok' ELSE 'FALTOU (resolver duplicados primeiro)' END
)
SELECT item, situacao FROM conf ORDER BY item;
