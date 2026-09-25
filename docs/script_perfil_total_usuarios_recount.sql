-- ============================================================================
-- ENTREGA: conserta o contador perfis_acesso.total_usuarios (Perfis & Acessos)
-- Equivalente a migration 20260925004115_perfil_total_usuarios_recount_dedup.sql
-- Cole INTEIRO no SQL Editor (roda em uma unica transacao).
--
-- O QUE FAZ
--   1) Guarda um backup das colunas que serao alteradas (id, total_usuarios).
--   2) Volta a funcao do gatilho para RECONTAGEM completa e idempotente,
--      contando usuarios DISTINTOS com vinculo ativo.
--   3) Deixa EXATAMENTE UM gatilho (apaga os dois nomes historicos e recria um).
--   4) Recalcula todos os perfis uma vez (backfill).
--   5) Conferencia final: lista perfis que ainda divergem -- deve vir VAZIO.
--
-- POR QUE ESTAVA ERRADO
--   Em 20260307012815 a funcao virou incremental (+1/-1) e um gatilho novo foi
--   criado sem apagar o antigo. Dois gatilhos disparavam a mesma funcao: contava
--   em dobro e derivava sem se autocorrigir. Voltar a recontagem por COUNT e ter
--   um unico gatilho resolve de forma idempotente.
--
--   Idempotente: rodar duas vezes nao quebra nem duplica.
-- ============================================================================

SET lock_timeout = '10s';

-- 1) BACKUP do que sera alterado (mesmas linhas do UPDATE, so as colunas tocadas).
--    Producao nao tem PITR; este backup permite desfazer so o que foi mexido.
--    Desfazer, se necessario:
--    UPDATE public.perfis_acesso p SET total_usuarios = b.total_usuarios
--    FROM public.backup_perfis_total_usuarios_20260925 b WHERE b.id = p.id;
CREATE TABLE IF NOT EXISTS public.backup_perfis_total_usuarios_20260925 AS
SELECT id, total_usuarios FROM public.perfis_acesso;

-- 2) Funcao de recontagem completa e idempotente (usuarios distintos, ativos).
CREATE OR REPLACE FUNCTION public.atualizar_total_usuarios_perfil()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
  UPDATE public.perfis_acesso
  SET total_usuarios = (
    SELECT COUNT(DISTINCT upv.usuario_id)
    FROM public.usuario_perfil_vinculos upv
    WHERE upv.perfil_id = COALESCE(NEW.perfil_id, OLD.perfil_id)
      AND upv.ativo = true
  )
  WHERE id = COALESCE(NEW.perfil_id, OLD.perfil_id);
  RETURN COALESCE(NEW, OLD);
END;
$fn$;

-- 3) Exatamente um gatilho.
DROP TRIGGER IF EXISTS trigger_atualizar_total_usuarios_perfil ON public.usuario_perfil_vinculos;
DROP TRIGGER IF EXISTS trg_atualizar_total_usuarios_perfil ON public.usuario_perfil_vinculos;
CREATE TRIGGER trg_atualizar_total_usuarios_perfil
  AFTER INSERT OR UPDATE OR DELETE ON public.usuario_perfil_vinculos
  FOR EACH ROW EXECUTE FUNCTION public.atualizar_total_usuarios_perfil();

-- 4) Backfill de TODOS os perfis (inclusive os que ficam em zero).
UPDATE public.perfis_acesso p
SET total_usuarios = COALESCE((
  SELECT COUNT(DISTINCT upv.usuario_id)
  FROM public.usuario_perfil_vinculos upv
  WHERE upv.perfil_id = p.id AND upv.ativo = true
), 0);

-- 5) CONFERENCIA (unico resultado exibido): perfis cujo contador ainda difira do
--    real apos o backfill. O esperado e NENHUMA linha.
SELECT p.id,
       p.nome,
       p.tenant_id,
       p.total_usuarios              AS contador,
       COALESCE(r.qtd, 0)            AS usuarios_reais,
       (p.total_usuarios - COALESCE(r.qtd, 0)) AS diferenca
FROM public.perfis_acesso p
LEFT JOIN (
  SELECT perfil_id, COUNT(DISTINCT usuario_id) AS qtd
  FROM public.usuario_perfil_vinculos
  WHERE ativo = true
  GROUP BY perfil_id
) r ON r.perfil_id = p.id
WHERE p.total_usuarios IS DISTINCT FROM COALESCE(r.qtd, 0)
ORDER BY diferenca DESC;
