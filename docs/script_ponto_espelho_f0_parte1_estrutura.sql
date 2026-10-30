-- ============================================================================
-- ESPELHO DE PONTO — Fatia 0, PARTE 1 de 2 (estrutura + backfill)
-- Cole INTEIRO no SQL Editor. Rode ANTES da parte 2.
-- Equivale à migration 20261030094216_ponto_espelho_ciencia_origem.sql.
--
-- (1) ponto_espelhos.ciencia_origem: colaborador_eletronica | papel_digitalizado
--     | rh_legado (nula = sem ciência).
-- (2) Backfill: espelhos que JÁ têm ciência pelo caminho antigo (status
--     confirmado/ressalva ou data_confirmacao) recebem 'rh_legado'. Só diz de
--     onde veio a ciência; não muda status, números nem datas. As linhas tocadas
--     são copiadas antes para backup.ponto_espelhos_ciencia_20261030 (schema
--     privado). O gatilho do adicional noturno fica desligado só durante o
--     backfill, para não recalcular espelho fechado.
--
-- Desfazer o backfill:
--   UPDATE public.ponto_espelhos e SET ciencia_origem = b.ciencia_origem
--     FROM backup.ponto_espelhos_ciencia_20261030 b WHERE b.id = e.id;
--
-- Não cria função. Tabela de backup criada por EXECUTE. Idempotente.
-- ============================================================================

SET lock_timeout = '10s';

ALTER TABLE public.ponto_espelhos
  ADD COLUMN IF NOT EXISTS ciencia_origem text;

DO $chk$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'ponto_espelhos_ciencia_origem_chk'
                    AND conrelid = 'public.ponto_espelhos'::regclass) THEN
    ALTER TABLE public.ponto_espelhos
      ADD CONSTRAINT ponto_espelhos_ciencia_origem_chk
      CHECK (ciencia_origem IS NULL
             OR ciencia_origem IN ('colaborador_eletronica', 'papel_digitalizado', 'rh_legado'));
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Restricao ciencia_origem nao criada: %', SQLERRM;
END $chk$;

COMMENT ON COLUMN public.ponto_espelhos.ciencia_origem IS
  'De onde veio a ciencia do espelho: colaborador_eletronica (assinatura eletronica pelo proprio colaborador), papel_digitalizado (papel assinado anexado pelo RH) ou rh_legado (registrada pelo botao antigo do RH, antes de 30/10/2026). Nula = sem ciencia.';

DO $bk$
BEGIN
  IF to_regnamespace('backup') IS NULL THEN
    EXECUTE 'CREATE SCHEMA backup';
  END IF;
  IF to_regclass('backup.ponto_espelhos_ciencia_20261030') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE backup.ponto_espelhos_ciencia_20261030 ('
         || 'id uuid PRIMARY KEY, tenant_id uuid, competencia text, status text, '
         || 'ciencia_origem text, data_confirmacao timestamptz, confirmado_por text, '
         || 'copiado_em timestamptz DEFAULT now())';
  END IF;
  INSERT INTO backup.ponto_espelhos_ciencia_20261030
    (id, tenant_id, competencia, status, ciencia_origem, data_confirmacao, confirmado_por)
  SELECT e.id, e.tenant_id, e.competencia, e.status, e.ciencia_origem, e.data_confirmacao, e.confirmado_por
    FROM public.ponto_espelhos e
   WHERE e.ciencia_origem IS NULL
     AND (COALESCE(e.status, '') IN ('confirmado', 'ressalva', 'assinado')
          OR e.data_confirmacao IS NOT NULL)
  ON CONFLICT (id) DO NOTHING;
END $bk$;

DO $bf$
DECLARE
  v_tem_gatilho boolean := EXISTS (
    SELECT 1 FROM pg_trigger
     WHERE tgname = 'trg_ponto_espelho_adicional_noturno'
       AND tgrelid = 'public.ponto_espelhos'::regclass AND NOT tgisinternal);
  v_n int;
BEGIN
  IF v_tem_gatilho THEN
    ALTER TABLE public.ponto_espelhos DISABLE TRIGGER trg_ponto_espelho_adicional_noturno;
  END IF;

  UPDATE public.ponto_espelhos
     SET ciencia_origem = 'rh_legado'
   WHERE ciencia_origem IS NULL
     AND (COALESCE(status, '') IN ('confirmado', 'ressalva', 'assinado')
          OR data_confirmacao IS NOT NULL);
  GET DIAGNOSTICS v_n = ROW_COUNT;

  IF v_tem_gatilho THEN
    ALTER TABLE public.ponto_espelhos ENABLE TRIGGER trg_ponto_espelho_adicional_noturno;
  END IF;
  RAISE NOTICE 'ciencia_origem: % espelho(s) marcados como rh_legado.', v_n;
END $bf$;

-- CONFERÊNCIA: coluna criada, quantos ficaram como rh_legado, backup guardado
-- e nenhum espelho com ciência sem origem (esperado 0 na última coluna).
SELECT
  EXISTS (SELECT 1 FROM information_schema.columns
           WHERE table_schema = 'public' AND table_name = 'ponto_espelhos'
             AND column_name = 'ciencia_origem')                          AS coluna_ok,
  (SELECT count(*) FROM public.ponto_espelhos WHERE ciencia_origem = 'rh_legado') AS espelhos_rh_legado,
  (SELECT count(*) FROM backup.ponto_espelhos_ciencia_20261030)          AS linhas_no_backup,
  (SELECT count(*) FROM public.ponto_espelhos
    WHERE ciencia_origem IS NULL
      AND (COALESCE(status, '') IN ('confirmado', 'ressalva', 'assinado')
           OR data_confirmacao IS NOT NULL))                             AS com_ciencia_sem_origem,
  EXISTS (SELECT 1 FROM pg_trigger
           WHERE tgname = 'trg_ponto_espelho_adicional_noturno'
             AND tgenabled <> 'D')                                       AS gatilho_noturno_religado;
