-- MarketYE: anexos do especialista (documentos comprobatórios e foto de perfil)
--
-- Defeito visto no ambiente de teste (12/09/2026): o cadastro pelo formulário
-- de especialista criava o perfil, mas os documentos não subiam. A política de
-- upload do bucket `marketplace-docs` exige que a primeira pasta do caminho
-- seja o id do especialista, e a tela mandava o id do usuário na frente. A tela
-- foi corrigida; aqui entra o que faltava no banco:
--  1. bucket PÚBLICO `marketplace-fotos` para a foto de perfil (a vitrine lê por
--     URL pública; `marketplace-docs` é privado e a URL "pública" dele não abre);
--  2. superadmin lê `marketplace-docs`: é quem aprova os cadastros, e o painel
--     de moderação passa a abrir cada documento por link assinado;
--  3. leitura ampla demais retirada: a política antiga deixava qualquer
--     admin/owner de EMPRESA CLIENTE ler os documentos pessoais de todos os
--     especialistas (no bucket e na tabela). Só o dono e o superadmin leem.
-- Idempotente: rodar de novo não duplica nem quebra.
SET lock_timeout = '10s';

INSERT INTO storage.buckets (id, name, public)
VALUES ('marketplace-fotos', 'marketplace-fotos', true)
ON CONFLICT (id) DO NOTHING;

-- Foto de perfil: qualquer um lê (bucket público); só o especialista dono sobe, troca e apaga a própria.
DROP POLICY IF EXISTS "MarketYE: foto de perfil publica" ON storage.objects;
CREATE POLICY "MarketYE: foto de perfil publica" ON storage.objects FOR SELECT
  USING (bucket_id = 'marketplace-fotos');

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

-- Documentos comprobatórios (bucket privado): o superadmin lê para aprovar o cadastro.
DROP POLICY IF EXISTS "MarketYE: superadmin le os documentos" ON storage.objects;
CREATE POLICY "MarketYE: superadmin le os documentos" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'marketplace-docs' AND public.is_superadmin(auth.uid()));

-- Leitura ampla demais (admin de qualquer empresa cliente) sai do bucket e da tabela.
DROP POLICY IF EXISTS "Admins can view all docs" ON storage.objects;

DROP POLICY IF EXISTS "Users can view own docs" ON public.marketplace_profissional_documentos;
CREATE POLICY "Users can view own docs" ON public.marketplace_profissional_documentos FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM public.marketplace_profissionais p WHERE p.id = profissional_id AND p.user_id = auth.uid())
    OR public.is_superadmin(auth.uid())
  );

COMMENT ON COLUMN public.marketplace_profissional_documentos.arquivo_url IS
  'Caminho do objeto no bucket marketplace-docs. Registros anteriores a 12/09/2026 guardam a URL publica, que nao abre (bucket privado). Quem exibe gera link assinado.';
