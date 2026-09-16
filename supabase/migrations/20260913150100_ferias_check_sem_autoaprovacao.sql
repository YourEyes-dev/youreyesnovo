-- ============================================================================
-- Fase 0 do plano de correção do Motor — FERIAS-056
-- Segregação de funções: ninguém aprova as próprias férias.
--
-- Espelha a trava que o ajuste de ponto já tem (chk_ajuste_sem_autoaprovacao,
-- PONTO-252). O CHECK pega a igualdade literal aprovado_por = colaborador_id.
--
-- Antes de criar a constraint, neutraliza auto-aprovações preexistentes
-- (inclusive resíduo de execuções anteriores da bateria), guardando as linhas
-- afetadas num backup — regra da casa para scripts que ALTERAM dado. Reverter a
-- aprovação inválida = devolver a solicitação a 'pendente' e limpar o aprovador.
-- ============================================================================

-- Backup das linhas que serão tocadas (idempotente).
DO $$
BEGIN
  CREATE TABLE IF NOT EXISTS public.backup_ferias_autoaprovacao_20260913 AS
    SELECT * FROM public.ferias_solicitacoes
     WHERE aprovado_por IS NOT NULL
       AND aprovado_por::text = colaborador_id::text;
EXCEPTION WHEN duplicate_table THEN
  NULL;
END $$;

-- Neutraliza a auto-aprovação: sem aprovador e de volta a pendente.
UPDATE public.ferias_solicitacoes
   SET aprovado_por      = NULL,
       aprovado_por_nome = NULL,
       data_aprovacao    = NULL,
       status            = CASE WHEN status = 'aprovado' THEN 'pendente' ELSE status END
 WHERE aprovado_por IS NOT NULL
   AND aprovado_por::text = colaborador_id::text;

-- Trava definitiva.
ALTER TABLE public.ferias_solicitacoes
  DROP CONSTRAINT IF EXISTS chk_ferias_sem_autoaprovacao;
ALTER TABLE public.ferias_solicitacoes
  ADD CONSTRAINT chk_ferias_sem_autoaprovacao
  CHECK (aprovado_por IS NULL OR aprovado_por::text <> colaborador_id::text);

-- Desfazer (comentado): restaurar as aprovações do backup, se algum dia preciso.
--   UPDATE public.ferias_solicitacoes f
--      SET aprovado_por = b.aprovado_por, aprovado_por_nome = b.aprovado_por_nome,
--          data_aprovacao = b.data_aprovacao, status = b.status
--     FROM public.backup_ferias_autoaprovacao_20260913 b
--    WHERE f.id = b.id;
