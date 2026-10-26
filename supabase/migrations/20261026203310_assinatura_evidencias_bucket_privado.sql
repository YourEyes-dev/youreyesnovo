-- =========================================================
-- ASS-0001 — FASE 0: bucket PRIVADO e NEUTRO para a evidência de liveness.
--
-- A foto/quadros do rosto colhidos na verificação de presença são biometria,
-- dado sensível (LGPD art. 11). Precisam de bucket privado, igual ao que o EPI
-- ganhou (epi-evidencias, 20261022215758), mas NEUTRO: serve qualquer módulo que
-- venha a usar a assinatura forte (Advertência etc. na fase 1), sem amarrar a um
-- módulo específico. Por isso a política NÃO exige perfil_permite_modulo de um
-- módulo só: basta ser da própria empresa.
--
--   leitura  : usuário autenticado, na pasta da própria empresa (o primeiro nível
--              do caminho é o tenant_id);
--   gravação : mesma regra;
--   alterar / apagar: nenhuma política. A evidência é imutável (sem UPDATE o
--              upsert também é recusado: cada arquivo tem caminho próprio).
-- Nada para anônimo. Signatários por link gravam pela edge (service_role, que
-- ignora RLS). O acesso de leitura é por link assinado de curta duração, gerado
-- pela aplicação (src/lib/assinaturaEvidencia.ts).
--
-- NÃO toca o bucket epi-evidencias nem nenhum módulo. Idempotente. Só bucket e
-- políticas: não cria tabela.
-- =========================================================

SET lock_timeout = '10s';

INSERT INTO storage.buckets (id, name, public)
VALUES ('assinatura-evidencias', 'assinatura-evidencias', false)
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS "assinatura_evidencias_leitura_da_empresa" ON storage.objects;
CREATE POLICY "assinatura_evidencias_leitura_da_empresa"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'assinatura-evidencias'
    AND (storage.foldername(name))[1] = public.get_user_tenant_id()::text
  );

DROP POLICY IF EXISTS "assinatura_evidencias_gravacao_da_empresa" ON storage.objects;
CREATE POLICY "assinatura_evidencias_gravacao_da_empresa"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'assinatura-evidencias'
    AND (storage.foldername(name))[1] = public.get_user_tenant_id()::text
  );
