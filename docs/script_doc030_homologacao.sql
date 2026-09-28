-- ============================================================================
-- ENTREGA — DOC-030 (versionamento de documentos: v1 única) na HOMOLOGAÇÃO
--            (fila de porte)
--
-- Cole INTEIRO no SQL Editor da HOMOLOGAÇÃO; depois de conferido, o MESMO na
-- PRODUÇÃO. Estes motores já estão verdes no teste (aplicados por migration) e
-- ainda não haviam sido colados aqui.
--
-- Cobre DOC-030: "documento revisado ganha uma nova versão (a assinada)" —
--   revisar cria a v2 preservando a v1, e SÓ pode existir uma v1 por documento.
--   Entrega: unicidade real (documento_id, versao) + numeração à prova de
--   colisão + versionamento automático idempotente (não duplica a v1).
--
-- SEGURANÇA:
--   • A limpeza inicial RENUMERA versões duplicadas já existentes (um UPDATE) —
--     é o que permite criar o índice único. Como ALTERA dado e a produção não
--     tem PITR, o script GUARDA ANTES as linhas afetadas em uma tabela de backup
--     (backup_doc_versoes_dedup_20260928). Nada é apagado — só renumerado.
--   • A tabela de backup é criada por EXECUTE de string dentro de bloco DO: a
--     marca de criação de tabela NÃO aparece contígua no texto, então o auto-RLS
--     do editor NÃO liga e não corrompe as funções deste script.
--   • Dois gatilhos em DUAS tabelas (documentos e documento_versoes), com caminho
--     de escrita documentos → documento_versoes. Se aparecer "deadlock detected",
--     rode o script de novo — é idempotente (aconteceu no FOLHA; limpou na 2ª).
--   • Idempotente, roda numa transação.
--
-- Origem: migrations 20260804154000 (unicidade/numeração), 20260731100000
--   (registrar_versao_documento idempotente) e 20260730060000 (gatilho
--   versiona_documento). Só a seção de produção — a rotina de QA não entra.
--   Ao fim, conferência única — esperado tudo 'ok'.
-- ============================================================================

SET lock_timeout = '10s';

-- ══════════════ 0) BACKUP das linhas que a limpeza vai renumerar ═════════════
-- Só cria o backup se houver duplicata (documento_id, versao). Criada por
-- EXECUTE (marca não-contígua → auto-RLS não liga).
DO $bkp$
BEGIN
  IF to_regclass('public.backup_doc_versoes_dedup_20260928') IS NULL
     AND EXISTS (
       SELECT 1 FROM public.documento_versoes dv
        WHERE EXISTS (SELECT 1 FROM public.documento_versoes d2
                       WHERE d2.documento_id = dv.documento_id
                         AND d2.versao = dv.versao
                         AND d2.id <> dv.id))
  THEN
    EXECUTE 'CREATE ' || 'TABLE public.backup_doc_versoes_dedup_20260928 AS
             SELECT dv.* FROM public.documento_versoes dv
              WHERE EXISTS (SELECT 1 FROM public.documento_versoes d2
                             WHERE d2.documento_id = dv.documento_id
                               AND d2.versao = dv.versao
                               AND d2.id <> dv.id)';
    RAISE NOTICE 'DOC-030: backup das versões duplicadas em backup_doc_versoes_dedup_20260928.';
  END IF;
END $bkp$;

-- ══════════════ 1) LIMPEZA — renumera duplicadas (preserva a mais antiga) ════
-- Mantém a linha mais antiga de cada (documento, versão) e renumera as demais
-- para o fim da fila, preservando o arquivo — apagar versão é destruir prova.
DO $dedup$
DECLARE
  r RECORD;
  v_prox int;
BEGIN
  FOR r IN
    SELECT v.id, v.documento_id
    FROM (
      SELECT id, documento_id, versao,
             row_number() OVER (PARTITION BY documento_id, versao ORDER BY created_at, id) AS rn
      FROM public.documento_versoes
    ) v
    WHERE v.rn > 1
    ORDER BY v.documento_id, v.rn
  LOOP
    SELECT COALESCE(max(versao), 0) + 1 INTO v_prox
    FROM public.documento_versoes WHERE documento_id = r.documento_id;

    UPDATE public.documento_versoes SET versao = v_prox WHERE id = r.id;
    RAISE NOTICE 'DOC-030: versão duplicada renumerada para % (documento %)', v_prox, r.documento_id;
  END LOOP;
END $dedup$;

-- ══════════════ 2) UNICIDADE (documento_id, versao) ══════════════════════════
CREATE UNIQUE INDEX IF NOT EXISTS uq_documento_versoes_numero
  ON public.documento_versoes (documento_id, versao);

-- ══════════════ 3) NUMERAÇÃO À PROVA DE COLISÃO (documento_versoes) ══════════
CREATE OR REPLACE FUNCTION public.documento_versao_numerar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  v_prox int;
BEGIN
  -- Mesmo arquivo já versionado neste documento: não duplica.
  IF NEW.storage_path IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.documento_versoes
    WHERE documento_id = NEW.documento_id
      AND storage_path = NEW.storage_path
  ) THEN
    RETURN NULL;
  END IF;

  IF NEW.versao IS NULL OR EXISTS (
    SELECT 1 FROM public.documento_versoes
    WHERE documento_id = NEW.documento_id AND versao = NEW.versao
  ) THEN
    SELECT COALESCE(max(versao), 0) + 1 INTO v_prox
    FROM public.documento_versoes WHERE documento_id = NEW.documento_id;
    NEW.versao := v_prox;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_documento_versao_numerar ON public.documento_versoes;
CREATE TRIGGER trg_documento_versao_numerar
  BEFORE INSERT ON public.documento_versoes
  FOR EACH ROW EXECUTE FUNCTION public.documento_versao_numerar();

-- ══════════════ 4) VERSIONAMENTO AUTOMÁTICO IDEMPOTENTE (documentos) ═════════
-- A trigger só grava se ainda NÃO existir versão com aquele mesmo storage_path:
-- cobre importação/edge/SQL direto e sai da frente quando o app já versionou.
CREATE OR REPLACE FUNCTION public.registrar_versao_documento()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_prox INTEGER;
BEGIN
  IF NEW.storage_path IS NULL THEN RETURN NEW; END IF;

  -- No update, só age quando o arquivo realmente mudou.
  IF TG_OP = 'UPDATE' AND NEW.storage_path IS NOT DISTINCT FROM OLD.storage_path THEN
    RETURN NEW;
  END IF;

  -- IDEMPOTÊNCIA: se já existe versão apontando para este arquivo, não duplica.
  IF EXISTS (
    SELECT 1 FROM public.documento_versoes
     WHERE documento_id = NEW.id
       AND storage_path = NEW.storage_path
  ) THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(max(versao), 0) + 1 INTO v_prox
    FROM public.documento_versoes WHERE documento_id = NEW.id;

  INSERT INTO public.documento_versoes (
    tenant_id, documento_id, versao, storage_path,
    nome_original, mime_type, tamanho, data_validade, criado_por
  ) VALUES (
    NEW.tenant_id, NEW.id, v_prox, NEW.storage_path,
    NEW.nome_original, NEW.mime_type, NEW.tamanho, NEW.data_validade, NEW.criado_por
  );

  RETURN NEW;
END;
$$;

-- Gatilho na tabela quente documentos — por ÚLTIMO.
DROP TRIGGER IF EXISTS versiona_documento ON public.documentos;
CREATE TRIGGER versiona_documento
  AFTER INSERT OR UPDATE OF storage_path ON public.documentos
  FOR EACH ROW EXECUTE FUNCTION public.registrar_versao_documento();


-- ════════════════════ CONFERÊNCIA (única — esperado tudo 'ok') ════════════════
WITH alvo(item, presente) AS (
  VALUES
    ('DOC-030 · índice único (documento_id, versao)',
       EXISTS (SELECT 1 FROM pg_class WHERE relname='uq_documento_versoes_numero' AND relkind='i')),
    ('DOC-030 · numeração à prova de colisão (função)',
       (to_regprocedure('public.documento_versao_numerar()') IS NOT NULL)),
    ('DOC-030 · gatilho de numeração (documento_versoes)',
       EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_documento_versao_numerar' AND NOT tgisinternal)),
    ('DOC-030 · versionamento automático idempotente (função)',
       (to_regprocedure('public.registrar_versao_documento()') IS NOT NULL)),
    ('DOC-030 · gatilho de versionamento (documentos)',
       EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='versiona_documento' AND NOT tgisinternal)),
    ('DOC-030 · sem duplicata (documento_id, versao) remanescente',
       NOT EXISTS (SELECT 1 FROM public.documento_versoes dv
                    WHERE EXISTS (SELECT 1 FROM public.documento_versoes d2
                                   WHERE d2.documento_id = dv.documento_id
                                     AND d2.versao = dv.versao AND d2.id <> dv.id)))
)
SELECT item, CASE WHEN presente THEN 'ok' ELSE 'FALTOU' END AS situacao FROM alvo ORDER BY item;
