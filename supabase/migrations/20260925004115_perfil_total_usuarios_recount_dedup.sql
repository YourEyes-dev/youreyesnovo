-- ============================================================================
-- Perfis & Acessos: conserta o contador perfis_acesso.total_usuarios
--
-- Sintoma (visto em cliente): o "N usuarios" do card de cada perfil nao fechava
-- com o numero real de usuarios vinculados.
--
-- Causa: em 20260307012815 a funcao atualizar_total_usuarios_perfil() foi trocada
-- de uma RECONTAGEM completa (COUNT, idempotente) por uma versao INCREMENTAL
-- (+1/-1), e um gatilho novo (trg_atualizar_total_usuarios_perfil) foi criado SEM
-- apagar o antigo (trigger_atualizar_total_usuarios_perfil, de 20260307012016).
-- Os dois gatilhos sobreviveram e passaram a disparar a MESMA funcao incremental
-- a cada mudanca: cada inclusao contava em dobro, e, por ser incremental, qualquer
-- evento perdido/edicao direta fazia o valor derivar de vez, sem se autocorrigir.
--
-- Correcao (estrutural, roda em qualquer banco):
--   1) Volta a funcao para recontagem completa e idempotente, contando USUARIOS
--      DISTINTOS com vinculo ativo (mesma semantica que a tela passou a mostrar).
--   2) Deixa EXATAMENTE UM gatilho na tabela (apaga os dois nomes conhecidos e
--      recria um so) -- some o disparo em dobro.
--   3) Recalcula todos os perfis uma vez (backfill) para corrigir o que ja drifou.
-- ============================================================================

SET lock_timeout = '10s';

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

-- Exatamente um gatilho: apaga os dois nomes ja usados historicamente e recria
-- apenas um. Idempotente (DROP IF EXISTS + CREATE).
DROP TRIGGER IF EXISTS trigger_atualizar_total_usuarios_perfil ON public.usuario_perfil_vinculos;
DROP TRIGGER IF EXISTS trg_atualizar_total_usuarios_perfil ON public.usuario_perfil_vinculos;
CREATE TRIGGER trg_atualizar_total_usuarios_perfil
  AFTER INSERT OR UPDATE OR DELETE ON public.usuario_perfil_vinculos
  FOR EACH ROW EXECUTE FUNCTION public.atualizar_total_usuarios_perfil();

-- Backfill: recalcula TODOS os perfis (inclusive os que ficam em zero). Subconsulta
-- correlacionada por perfil -- perfis_acesso e uma tabela pequena; nao ha operacao
-- linha a linha com funcao por registro.
UPDATE public.perfis_acesso p
SET total_usuarios = COALESCE((
  SELECT COUNT(DISTINCT upv.usuario_id)
  FROM public.usuario_perfil_vinculos upv
  WHERE upv.perfil_id = p.id AND upv.ativo = true
), 0);

COMMENT ON FUNCTION public.atualizar_total_usuarios_perfil() IS
  'Mantem perfis_acesso.total_usuarios por RECONTAGEM completa e idempotente (usuarios distintos com vinculo ativo) a cada mudanca em usuario_perfil_vinculos. Substitui a versao incremental de 20260307012815, que, somada ao gatilho duplicado, contava em dobro e derivava.';
