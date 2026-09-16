-- ============================================================================
-- MarketYE — anexos do especialista (documentos e foto de perfil)
-- Script de entrega para o SQL Editor. Mesmo conteúdo da migration
-- 20260912013000_marketye_anexos_fotos.sql. Idempotente: pode rodar duas vezes.
-- Só CRIA/AJUSTA política e bucket — não altera nem apaga dado de tabela, por
-- isso não há tabela de backup.
--
-- O que faz:
--  1. bucket PÚBLICO marketplace-fotos para a foto de perfil do especialista
--     (a vitrine lê por URL pública; o bucket de documentos é privado);
--  2. superadmin passa a ler o bucket marketplace-docs (aprovação de cadastro;
--     o painel de moderação abre cada documento por link assinado);
--  3. retira a leitura ampla demais: admin/owner de qualquer empresa cliente
--     podia ler os documentos pessoais de todos os especialistas. Só o dono e
--     o superadmin leem.
-- Cada item em bloco próprio: erro em um vira aviso e não derruba os demais.
-- ============================================================================
SET lock_timeout = '10s';

DO $anexos1$
BEGIN
  INSERT INTO storage.buckets (id, name, public)
  VALUES ('marketplace-fotos', 'marketplace-fotos', true)
  ON CONFLICT (id) DO NOTHING;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'bucket marketplace-fotos: %', SQLERRM;
END $anexos1$;

DO $anexos2$
BEGIN
  DROP POLICY IF EXISTS "MarketYE: foto de perfil publica" ON storage.objects;
  CREATE POLICY "MarketYE: foto de perfil publica" ON storage.objects FOR SELECT
    USING (bucket_id = 'marketplace-fotos');
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'politica foto publica: %', SQLERRM;
END $anexos2$;

DO $anexos3$
BEGIN
  DROP POLICY IF EXISTS "MarketYE: especialista sobe a propria foto" ON storage.objects;
  CREATE POLICY "MarketYE: especialista sobe a propria foto" ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'marketplace-fotos'
      AND split_part(name, '/', 1) IN (SELECT id::text FROM public.marketplace_profissionais WHERE user_id = auth.uid()));
  DROP POLICY IF EXISTS "MarketYE: especialista troca a propria foto" ON storage.objects;
  CREATE POLICY "MarketYE: especialista troca a propria foto" ON storage.objects FOR UPDATE TO authenticated
    USING (bucket_id = 'marketplace-fotos'
      AND split_part(name, '/', 1) IN (SELECT id::text FROM public.marketplace_profissionais WHERE user_id = auth.uid()));
  DROP POLICY IF EXISTS "MarketYE: especialista apaga a propria foto" ON storage.objects;
  CREATE POLICY "MarketYE: especialista apaga a propria foto" ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'marketplace-fotos'
      AND split_part(name, '/', 1) IN (SELECT id::text FROM public.marketplace_profissionais WHERE user_id = auth.uid()));
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'politicas foto do especialista: %', SQLERRM;
END $anexos3$;

DO $anexos4$
BEGIN
  DROP POLICY IF EXISTS "MarketYE: superadmin le os documentos" ON storage.objects;
  CREATE POLICY "MarketYE: superadmin le os documentos" ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'marketplace-docs' AND public.is_superadmin(auth.uid()));
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'politica superadmin le documentos: %', SQLERRM;
END $anexos4$;

DO $anexos5$
BEGIN
  DROP POLICY IF EXISTS "Admins can view all docs" ON storage.objects;
  DROP POLICY IF EXISTS "Users can view own docs" ON public.marketplace_profissional_documentos;
  CREATE POLICY "Users can view own docs" ON public.marketplace_profissional_documentos FOR SELECT
    USING (
      EXISTS (SELECT 1 FROM public.marketplace_profissionais p WHERE p.id = profissional_id AND p.user_id = auth.uid())
      OR public.is_superadmin(auth.uid())
    );
  COMMENT ON COLUMN public.marketplace_profissional_documentos.arquivo_url IS
    'Caminho do objeto no bucket marketplace-docs. Registros anteriores a 12/09/2026 guardam a URL publica, que nao abre (bucket privado). Quem exibe gera link assinado.';
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'leitura dos documentos (tabela e bucket): %', SQLERRM;
END $anexos5$;

-- Conferência (única saída que o SQL Editor mostra): tudo deve vir "ok".
WITH esperadas(item) AS (
  VALUES ('MarketYE: foto de perfil publica'),
         ('MarketYE: especialista sobe a propria foto'),
         ('MarketYE: especialista troca a propria foto'),
         ('MarketYE: especialista apaga a propria foto'),
         ('MarketYE: superadmin le os documentos')
)
SELECT 'politica storage: ' || e.item AS item,
       CASE WHEN EXISTS (SELECT 1 FROM pg_policies pp WHERE pp.schemaname = 'storage' AND pp.tablename = 'objects' AND pp.policyname = e.item)
            THEN 'ok' ELSE 'FALTA' END AS situacao
FROM esperadas e
UNION ALL
SELECT 'bucket marketplace-fotos (publico)',
       CASE WHEN EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'marketplace-fotos' AND public) THEN 'ok' ELSE 'FALTA' END
UNION ALL
SELECT 'politica antiga "Admins can view all docs" removida',
       CASE WHEN EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'Admins can view all docs')
            THEN 'AINDA EXISTE' ELSE 'ok' END
UNION ALL
SELECT 'tabela de documentos: leitura so do dono e do superadmin',
       CASE WHEN EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'marketplace_profissional_documentos'
                           AND policyname = 'Users can view own docs' AND qual LIKE '%is_superadmin%' AND qual NOT LIKE '%has_minimum_role%')
            THEN 'ok' ELSE 'FALTA' END
ORDER BY 1;
