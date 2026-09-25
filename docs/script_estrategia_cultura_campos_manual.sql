-- ============================================================================
-- ENTREGA: Identidade Estratégica / Cultura — campos novos do Manual de Cultura
-- Equivalente à migration 20260925174520_estrategia_cultura_campos_manual.sql
-- Cole INTEIRO no SQL Editor. Idempotente.
--
-- Só ADD COLUMN em estrategia_cultura (não cria tabela, não altera dado existente
-- — sem necessidade de backup e sem o auxiliar de RLS do editor, que só liga em
-- CREATE TABLE / SELECT INTO).
-- ============================================================================

SET lock_timeout = '10s';

ALTER TABLE public.estrategia_cultura ADD COLUMN IF NOT EXISTS proposito text;
ALTER TABLE public.estrategia_cultura ADD COLUMN IF NOT EXISTS carta_boas_vindas text;
ALTER TABLE public.estrategia_cultura ADD COLUMN IF NOT EXISTS tom_de_voz text;
ALTER TABLE public.estrategia_cultura ADD COLUMN IF NOT EXISTS codigo_conduta text;
ALTER TABLE public.estrategia_cultura ADD COLUMN IF NOT EXISTS dress_code text;
ALTER TABLE public.estrategia_cultura ADD COLUMN IF NOT EXISTS modelo_trabalho text;

-- Conferência (único resultado): deve retornar 6.
SELECT count(*) AS colunas_novas_ok
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'estrategia_cultura'
  AND column_name IN ('proposito','carta_boas_vindas','tom_de_voz','codigo_conduta','dress_code','modelo_trabalho');
