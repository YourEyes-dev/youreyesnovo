-- ============================================================================
-- ESPELHO DE PONTO — Fatia 0 (parte 1): de onde veio a ciência do espelho
--
-- Até aqui o botão "Confirmar" da aba Fechamento gravava status 'confirmado' e
-- confirmado_por = id do usuário do RH. A "ciência" ficava sendo do RH, não do
-- trabalhador — não prova nada (Súmula 338 do TST) e ainda liberava o portão do
-- fechamento.
--
-- O QUE FAZ
--   (1) ponto_espelhos.ciencia_origem: colaborador_eletronica | papel_digitalizado
--       | rh_legado. Nula = sem ciência.
--   (2) Backfill: os espelhos que JÁ têm ciência registrada pelo caminho antigo
--       (status confirmado/ressalva ou data_confirmacao preenchida) recebem
--       'rh_legado' — não apaga nem altera a ciência, só diz de onde ela veio.
--       Antes, as linhas tocadas são copiadas para o schema privado backup.
--       O gatilho do adicional noturno fica desligado só durante o backfill,
--       para que a marcação de origem não recalcule número de espelho fechado.
--
-- Desfazer o backfill (se preciso):
--   UPDATE public.ponto_espelhos e SET ciencia_origem = b.ciencia_origem
--     FROM backup.ponto_espelhos_ciencia_20261030 b WHERE b.id = e.id;
--
-- Idempotente. Não altera o motor de saldo nem a apuração.
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
END $chk$;

COMMENT ON COLUMN public.ponto_espelhos.ciencia_origem IS
  'De onde veio a ciencia do espelho: colaborador_eletronica (assinatura eletronica pelo proprio colaborador), papel_digitalizado (papel assinado anexado pelo RH) ou rh_legado (registrada pelo botao antigo do RH, antes de 30/10/2026). Nula = sem ciencia.';

CREATE SCHEMA IF NOT EXISTS backup;

CREATE TABLE IF NOT EXISTS backup.ponto_espelhos_ciencia_20261030 (
  id uuid PRIMARY KEY, tenant_id uuid, competencia text, status text,
  ciencia_origem text, data_confirmacao timestamptz, confirmado_por text,
  copiado_em timestamptz DEFAULT now()
);

INSERT INTO backup.ponto_espelhos_ciencia_20261030
  (id, tenant_id, competencia, status, ciencia_origem, data_confirmacao, confirmado_por)
SELECT e.id, e.tenant_id, e.competencia, e.status, e.ciencia_origem, e.data_confirmacao, e.confirmado_por
  FROM public.ponto_espelhos e
 WHERE e.ciencia_origem IS NULL
   AND (COALESCE(e.status, '') IN ('confirmado', 'ressalva', 'assinado')
        OR e.data_confirmacao IS NOT NULL)
ON CONFLICT (id) DO NOTHING;

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
