-- ============================================================================
-- Identidade Estratégica / Cultura: campos novos para enriquecer o Manual de
-- Cultura gerado por IA (Onda 1).
--
-- Só ADD COLUMN (aditivo, idempotente) em estrategia_cultura — não cria tabela,
-- não altera dado existente. As telas e a edge function ai-cultura-manual passam
-- a usar estes textos.
-- ============================================================================

SET lock_timeout = '10s';

ALTER TABLE public.estrategia_cultura ADD COLUMN IF NOT EXISTS proposito text;
ALTER TABLE public.estrategia_cultura ADD COLUMN IF NOT EXISTS carta_boas_vindas text;
ALTER TABLE public.estrategia_cultura ADD COLUMN IF NOT EXISTS tom_de_voz text;
ALTER TABLE public.estrategia_cultura ADD COLUMN IF NOT EXISTS codigo_conduta text;
ALTER TABLE public.estrategia_cultura ADD COLUMN IF NOT EXISTS dress_code text;
ALTER TABLE public.estrategia_cultura ADD COLUMN IF NOT EXISTS modelo_trabalho text;
