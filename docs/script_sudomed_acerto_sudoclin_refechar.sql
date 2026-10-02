-- ============================================================================
-- ACERTO DO BANCO — SUDOCLIN · REFECHAR junho/julho (TRAVA-SÓ, sem RN29)
-- Colar no SQL Editor de PRODUÇÃO (projeto diayjpsrcerycycyaxst).
--
-- POR QUE NÃO USAR O BOTÃO "Fechar período":
--   O fechamento normal da tela roda, no fim, a regra RN29
--   (ponto_fechar_competencia_banco), que ZERA todo saldo POSITIVO
--   ("positivo já foi pago como hora extra, não transita"). Isso é a lógica
--   MENSAL. A Sudomed é SEMESTRAL e o Grupo B MANTÉM o saldo — então o botão
--   zeraria a Vera (11h32) e qualquer outro positivo. Por isso refechamos
--   SÓ A TRAVA aqui, sem tocar em nenhum saldo.
--
-- O QUE ESTE SCRIPT FAZ:
--   Marca o fechamento de 2026-06 e 2026-07 da SUDOCLIN como status='fechado'.
--   Isso faz a fonte única (ponto_banco_horas_oficial) passar a devolver a
--   FOTOGRAFIA já gravada (Súmula 338 — mês fechado não recalcula):
--     Carol = julho 0h00 · Vera = julho 11h32 (exatamente como está hoje).
--   NÃO roda RN29. NÃO altera ponto_banco_horas. NÃO apaga nada.
--
-- SEGURANÇA: só UPDATE de status na tabela de travas (ponto_fechamentos).
--   Idempotente (rodar de novo não muda nada). As linhas originais já estão
--   no backup_acerto_fech_20261001 (Passo 0).
-- ============================================================================

DO $reclose$
DECLARE
  v_n int := 0;
BEGIN
  UPDATE public.ponto_fechamentos f
     SET status           = 'fechado',
         data_fechamento  = COALESCE(f.data_fechamento, now()),
         reaberto_em      = NULL,
         reaberto_por     = NULL,
         reaberto_por_nome= NULL,
         motivo_reabertura= NULL,
         updated_at       = now()
   WHERE f.competencia IN ('2026-06','2026-07')
     AND f.empresa_id IN (
           SELECT id FROM public.empresa_cadastro
           WHERE razao_social ILIKE '%SUDOCLIN%'
         )
     AND COALESCE(f.status,'') <> 'fechado';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RAISE NOTICE 'SUDOCLIN — competencias travadas como fechado: %', v_n;
END $reclose$;


-- ---------------------------------------------------------------------
-- CONFERÊNCIA 1 — estado das travas da SUDOCLIN (devem vir 'fechado' em jun/jul)
-- ---------------------------------------------------------------------
SELECT
  ec.razao_social,
  f.competencia,
  f.status,
  f.data_fechamento
FROM public.ponto_fechamentos f
JOIN public.empresa_cadastro ec ON ec.id = f.empresa_id
WHERE ec.razao_social ILIKE '%SUDOCLIN%'
  AND f.competencia IN ('2026-06','2026-07','2026-08','2026-09')
ORDER BY f.competencia;

-- Depois desta conferência, rode a conferência oficial de sempre
-- (script_sudomed_banco_conferencia_oficial.sql) e confirme que a SUDOCLIN
-- segue com: Carol julho 0h00 (fonte=fechada) e Vera julho 11h32 (fonte=fechada),
-- sem nenhuma divergência.
