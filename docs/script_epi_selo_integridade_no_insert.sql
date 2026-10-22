-- ============================================================================
-- ENTREGA — EPI: selo de integridade (assinatura_hash) também no INSERT assinado
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de TESTE (staging) e, só
-- depois de aprovado, no de PRODUCAO. Espelha a migration deste mesmo acerto.
-- Troca UMA função e UM gatilho de epi_entregas; não altera nem apaga dado, e
-- não preenche fichas antigas (ver o comentário). Roda em UMA transação, é
-- idempotente e não cria tabela. Sem backup_*: nada é alterado nas linhas.
-- ============================================================================

-- =========================================================
-- EPI — o selo de integridade (assinatura_hash) também no INSERT assinado.
--
-- O wizard de entrega grava a ficha JÁ assinada, num único INSERT com signed_at
-- (o motor de estoque trata esse caso: "entrega já assinada no registro"). Mas
-- trg_epi_entrega_sela_integridade era BEFORE UPDATE OF signed_at e só agia
-- quando OLD.signed_at IS NULL: no INSERT nunca disparava, e a ficha mais comum
-- ficava sem hash. O EPI-042 passava porque só conferia que a COLUNA existia.
--
-- Correção: o mesmo selo, com a mesma fórmula, também em BEFORE INSERT. Não
-- altera o hash de quem já tem (só preenche quando está nulo) e NÃO preenche
-- linhas antigas: selar hoje uma ficha assinada no passado atestaria o estado
-- de hoje, não o do ato, e viraria falsa garantia (contagem na conferência).
--
-- Fora de escopo, de propósito (ver EPI-044/EPI-042): o hash cobre a URL da
-- assinatura, não os bytes do arquivo nem os demais campos; e o arquivamento da
-- ficha em Documentos segue pelo wizard, porque o gatilho de arquivamento grava
-- a URL pública do bucket epi-signatures como se fosse caminho do bucket
-- documentos, e ligá-lo no INSERT criaria linhas que não baixam.
--
-- Idempotente. Uma tabela só (epi_entregas) e só trigger de linha: sem risco de
-- deadlock entre tabelas movimentadas.
-- =========================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.epi_entrega_sela_integridade()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $fn$
BEGIN
  IF NEW.signed_at IS NOT NULL AND NEW.assinatura_hash IS NULL THEN
    -- No UPDATE, só sela na passagem de não assinada para assinada.
    IF TG_OP = 'UPDATE' THEN
      IF OLD.signed_at IS NOT NULL THEN
        RETURN NEW;
      END IF;
    END IF;
    NEW.assinatura_hash := encode(
      public.digest(
        COALESCE(NEW.assinatura_url, '') || '|' ||
        COALESCE(NEW.recebido_por_assinatura, '') || '|' ||
        NEW.signed_at::text || '|' || NEW.id::text,
        'sha256'),
      'hex');
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_epi_entrega_sela_integridade ON public.epi_entregas;
CREATE TRIGGER trg_epi_entrega_sela_integridade
  BEFORE INSERT OR UPDATE OF signed_at ON public.epi_entregas
  FOR EACH ROW EXECUTE FUNCTION public.epi_entrega_sela_integridade();

-- Conferência final (o editor mostra só este resultado):
SELECT
  EXISTS (SELECT 1 FROM pg_trigger t
           WHERE t.tgrelid = 'public.epi_entregas'::regclass
             AND t.tgname = 'trg_epi_entrega_sela_integridade'
             AND (t.tgtype & 4) <> 0 AND (t.tgtype & 16) <> 0) AS sela_no_insert_e_no_update,
  (SELECT count(*) FROM public.epi_entregas
     WHERE signed_at IS NOT NULL AND assinatura_hash IS NULL) AS fichas_antigas_sem_hash,
  (SELECT count(*) FROM public.epi_entregas WHERE signed_at IS NOT NULL) AS fichas_assinadas,
  NULL::text AS erro_tecnico;

-- Para desfazer (volta ao gatilho só de UPDATE):
--   DROP TRIGGER IF EXISTS trg_epi_entrega_sela_integridade ON public.epi_entregas;
--   CREATE TRIGGER trg_epi_entrega_sela_integridade BEFORE UPDATE OF signed_at
--     ON public.epi_entregas FOR EACH ROW EXECUTE FUNCTION public.epi_entrega_sela_integridade();
