-- ============================================================================
-- ENTREGA (HOMOLOGAÇÃO) — cofre da selfie do ponto: bucket + políticas
--
-- POR QUE ESTE SCRIPT EXISTE:
--   O bucket de armazenamento 'ponto-selfies' e suas políticas são criados por
--   migrations (20260311193831 e 20260610010000), então o TESTE e a PRODUÇÃO já
--   têm — a selfie do link funciona lá. A HOMOLOGAÇÃO é um projeto separado,
--   forward-only, que não recebeu essa parte de storage. Sem o bucket + a
--   política de upload anônimo, a página pública tira a selfie mas o ENVIO da
--   foto falha; o app segue sem foto e o banco devolve "É obrigatório tirar a
--   selfie". Este script traz o storage da homologação ao mesmo estado do
--   teste/produção.
--
--   Aplique no SQL Editor da HOMOLOGAÇÃO (fgsblefvdabgdouipigz). É idempotente:
--   em um projeto que já tenha o bucket/políticas, ele é inócuo.
--
-- SEGURANCA: só cria bucket e políticas de storage; não altera nem apaga dado.
-- ============================================================================

-- 1) Bucket público 'ponto-selfies' (a foto é servida por URL pública).
INSERT INTO storage.buckets (id, name, public)
VALUES ('ponto-selfies', 'ponto-selfies', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- 2) Upload ANÔNIMO da página pública, restrito ao prefixo externo/
--    (mesma política da migration 20260610010000).
DROP POLICY IF EXISTS "Anon can upload external ponto selfies" ON storage.objects;
CREATE POLICY "Anon can upload external ponto selfies"
ON storage.objects FOR INSERT TO anon
WITH CHECK (bucket_id = 'ponto-selfies' AND name LIKE 'externo/%');

-- 3) Políticas para usuários autenticados (kiosk interno), como na migration
--    20260311193831 — para o registro interno também gravar selfie.
DROP POLICY IF EXISTS "Authenticated users can upload ponto selfies" ON storage.objects;
CREATE POLICY "Authenticated users can upload ponto selfies"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'ponto-selfies');

DROP POLICY IF EXISTS "Anyone can view ponto selfies" ON storage.objects;
CREATE POLICY "Anyone can view ponto selfies"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'ponto-selfies');

DROP POLICY IF EXISTS "Users can delete own ponto selfies" ON storage.objects;
CREATE POLICY "Users can delete own ponto selfies"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'ponto-selfies');

-- ── Conferência — esperado: bucket_publico = true e as duas colunas de política true
SELECT
  (SELECT public FROM storage.buckets WHERE id = 'ponto-selfies')                    AS bucket_publico,
  EXISTS (SELECT 1 FROM pg_policies
           WHERE schemaname = 'storage' AND tablename = 'objects'
             AND policyname = 'Anon can upload external ponto selfies')               AS policy_anon_upload,
  EXISTS (SELECT 1 FROM pg_policies
           WHERE schemaname = 'storage' AND tablename = 'objects'
             AND policyname = 'Authenticated users can upload ponto selfies')         AS policy_auth_upload;
