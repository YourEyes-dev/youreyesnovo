-- ============================================================================
-- ACERTO DO BANCO — N&B (CNPJ 41085456000189) · REFECHAR jun/jul (TRAVA-SÓ)
-- Colar no SQL Editor de PRODUÇÃO (projeto diayjpsrcerycycyaxst).
--
-- POR QUE TRAVA-SÓ (e não o botão "Fechar período"):
--   O botão roda a RN29 (ponto_fechar_competencia_banco), que ZERA todo saldo
--   POSITIVO. A N&B 189 é semestral e tem Grupo B (Jaque) que MANTÉM o saldo —
--   o botão zeraria a Jaque (17h13). Aqui só travamos, sem RN29.
--
-- ATENÇÃO AO CNPJ: há DUAS empresas "NUERNBERG & BARROS LTDA" (189 e 260).
--   Este script resolve SÓ a 189 pelo CNPJ — não toca na 260 (já travada).
--
-- ESTADO ESPERADO AO TRAVAR (conferido antes):
--   Jaque (B): jul 17h13 (mantém, migrado +6h26 dentro)
--   Aylyn (A): jul 0h00 (zerada) · Deisi (A): jul 0h00 (zerada)
--   Suzana (demais): jul -10h12 (recalculada pelo fix da escala; mantém)
--
-- SEGURANÇA: só UPDATE de status (ponto_fechamentos). NÃO roda RN29, NÃO altera
--   saldo, NÃO apaga nada. Idempotente. Originais no backup_acerto_fech_20261001.
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
           WHERE regexp_replace(COALESCE(cnpj,''),'[^0-9]','','g') = '41085456000189'
         )
     AND COALESCE(f.status,'') <> 'fechado';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RAISE NOTICE 'N&B 189 — competencias travadas como fechado: %', v_n;
END $reclose$;


-- ---------------------------------------------------------------------
-- CONFERÊNCIA — estado das travas da 189 (jun/jul devem vir 'fechado')
-- ---------------------------------------------------------------------
SELECT
  ec.razao_social,
  ec.cnpj,
  f.competencia,
  f.status,
  f.data_fechamento
FROM public.ponto_fechamentos f
JOIN public.empresa_cadastro ec ON ec.id = f.empresa_id
WHERE regexp_replace(COALESCE(ec.cnpj,''),'[^0-9]','','g') = '41085456000189'
  AND f.competencia IN ('2026-06','2026-07','2026-08','2026-09')
ORDER BY f.competencia;
