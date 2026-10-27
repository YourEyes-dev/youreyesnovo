-- ============================================================================
-- ENTREGA — EPI: bucket PRIVADO para a foto do rosto e a assinatura da entrega
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de TESTE (staging) e, só
-- depois de aprovado, no de PRODUCAO. Espelha a migration deste mesmo acerto.
-- Cria o bucket epi-evidencias (privado) e duas políticas de storage (leitura e
-- gravação da própria empresa, com acesso ao módulo EPI). NÃO mexe no bucket
-- epi-signatures (compartilhado com PDI e Experiência) e NÃO move os arquivos
-- antigos. Não cria tabela. UMA transação, idempotente.
-- ORDEM: cole este ANTES de publicar as telas; sem o bucket o upload da
-- entrega falha.
-- ============================================================================

-- =========================================================
-- EPI — bucket PRIVADO para a evidência da entrega (foto do rosto e assinatura).
--
-- PROBLEMA: a foto do colaborador (biometria, dado sensível, LGPD art. 11) e a
-- assinatura iam para epi-signatures, bucket público com leitura aberta
-- (USING bucket_id = ...): qualquer pessoa com o link vê. Esse bucket é dividido
-- com os fluxos de PDI e Experiência (edge functions pdi-assinatura e
-- experiencia-assinatura), que não são de EPI; por isso ele NÃO foi tornado
-- privado aqui.
--
-- CORREÇÃO: bucket novo epi-evidencias, privado.
--   leitura  : usuário autenticado, na pasta da própria empresa (o primeiro
--              nível do caminho é o id da empresa) E com acesso ao módulo EPI;
--   gravação : mesma regra;
--   alterar / apagar: nenhuma política. A evidência é imutável (sem UPDATE o
--              upsert também é recusado: cada arquivo tem caminho próprio).
-- Nada para anônimo.
-- O acesso é por link assinado de curta duração, gerado pela aplicação.
--
-- FORA DE ESCOPO: as fichas antigas continuam em epi-signatures até a migração
-- dos arquivos, que precisa da API de storage (copiar e trocar a referência) e
-- não cabe em SQL.
-- Idempotente. Só bucket e políticas: não cria tabela.
-- =========================================================

SET lock_timeout = '10s';

INSERT INTO storage.buckets (id, name, public)
VALUES ('epi-evidencias', 'epi-evidencias', false)
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS "epi_evidencias_leitura_da_empresa" ON storage.objects;
CREATE POLICY "epi_evidencias_leitura_da_empresa"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'epi-evidencias'
    AND (storage.foldername(name))[1] = public.get_user_tenant_id()::text
    AND public.perfil_permite_modulo(public.get_user_tenant_id(), 'epi')
  );

DROP POLICY IF EXISTS "epi_evidencias_gravacao_da_empresa" ON storage.objects;
CREATE POLICY "epi_evidencias_gravacao_da_empresa"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'epi-evidencias'
    AND (storage.foldername(name))[1] = public.get_user_tenant_id()::text
    AND public.perfil_permite_modulo(public.get_user_tenant_id(), 'epi')
  );

-- Conferência final (o editor mostra só este resultado):
SELECT
  EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'epi-evidencias' AND public = false) AS bucket_privado,
  (SELECT count(*) FROM pg_policy p WHERE p.polrelid = 'storage.objects'::regclass
      AND p.polname IN ('epi_evidencias_leitura_da_empresa', 'epi_evidencias_gravacao_da_empresa')) AS politicas_deve_ser_2,
  (SELECT public FROM storage.buckets WHERE id = 'epi-signatures') AS epi_signatures_segue_como_estava,
  NULL::text AS erro_tecnico;

-- Para desfazer (o upload da entrega volta a depender do bucket antigo só se as telas antigas voltarem):
--   DROP POLICY IF EXISTS "epi_evidencias_leitura_da_empresa" ON storage.objects;
--   DROP POLICY IF EXISTS "epi_evidencias_gravacao_da_empresa" ON storage.objects;
--   (o bucket só pode ser removido pela API de storage se estiver vazio)
