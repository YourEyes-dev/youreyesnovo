-- ============================================================================
-- ACERTO DO BANCO — N&B (CNPJ 41085456000260) · REFECHAR jun/jul (TRAVA-SÓ)
-- Colar no SQL Editor de PRODUÇÃO (projeto diayjpsrcerycycyaxst).
--
-- POR QUE TRAVA-SÓ (e não o botão "Fechar período"):
--   O botão roda a RN29 (ponto_fechar_competencia_banco), que ZERA todo saldo
--   POSITIVO. A N&B 260 é semestral e o Grupo B MANTÉM o saldo — então o botão
--   zeraria a Luiza (12h45) e a Juleide (5h13). Aqui só travamos, sem RN29.
--
-- ATENÇÃO AO CNPJ: há DUAS empresas com razão social "NUERNBERG & BARROS LTDA"
--   (189 e 260). Este script resolve SÓ a 260 pelo CNPJ — não toca na 189.
--
-- O QUE FAZ: marca o fechamento de 2026-06 e 2026-07 da empresa 260 como
--   status='fechado'. A fonte única passa a devolver a fotografia gravada
--   (Súmula 338): Luiza/Juleide/Pamela congeladas como estão hoje. NÃO roda
--   RN29, NÃO altera saldo, NÃO apaga nada. Idempotente.
--   (As linhas originais já estão no backup_acerto_fech_20261001 — Passo 0.)
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
           WHERE regexp_replace(COALESCE(cnpj,''),'[^0-9]','','g') = '41085456000260'
         )
     AND COALESCE(f.status,'') <> 'fechado';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RAISE NOTICE 'N&B 260 — competencias travadas como fechado: %', v_n;
END $reclose$;


-- ---------------------------------------------------------------------
-- CONFERÊNCIA — estado das travas da 260 (jun/jul devem vir 'fechado')
-- ---------------------------------------------------------------------
SELECT
  ec.razao_social,
  ec.cnpj,
  f.competencia,
  f.status,
  f.data_fechamento
FROM public.ponto_fechamentos f
JOIN public.empresa_cadastro ec ON ec.id = f.empresa_id
WHERE regexp_replace(COALESCE(ec.cnpj,''),'[^0-9]','','g') = '41085456000260'
  AND f.competencia IN ('2026-06','2026-07','2026-08','2026-09')
ORDER BY f.competencia;
