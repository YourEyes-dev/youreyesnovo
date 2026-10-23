-- ============================================================================
-- ENTREGA — Arquivos (storage) LOTE 0: regras com a EMPRESA e o PERFIL
--
-- Cole no SQL Editor do projeto de PRODUCAO (antes, em HOMOLOGACAO e TESTE, o mesmo arquivo).
-- UMA transacao, idempotente. So politicas de storage e uma funcao de apoio: nenhum dado e alterado,
-- sem criar tabela (o auxiliar de RLS automatico do editor nao entra). Termina com UMA conferencia SELECT.
--
-- Efeito esperado: nada muda para quem ja trabalha na propria empresa com o perfil certo. Deixam de
-- funcionar: gestor de uma empresa lendo/enviando/apagando arquivo de OUTRA, e gestor com perfil sem o
-- modulo (atestados/sst, trilhas/aprendizado, epi, ergonomia, hub_contabil) mexendo nos arquivos dele.
-- Para DESFAZER (so se necessario), recriar as regras antigas (so papel) — ver o fim deste arquivo.
-- ============================================================================

SET lock_timeout = '10s';

-- Apoio: a evidencia pertence a um registro de trilha da empresa do usuario?
CREATE OR REPLACE FUNCTION public.ye_trilha_evidencia_da_empresa(p_name text)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  IF p_name IS NULL OR public.get_user_tenant_id() IS NULL THEN
    RETURN false;
  END IF;
  RETURN EXISTS (
    SELECT 1 FROM public.trilha_progresso tp
     WHERE tp.tenant_id = public.get_user_tenant_id()
       AND tp.evidencia_url = p_name
  );
END;
$fn$;

DO $g$
BEGIN
  EXECUTE 'REVOKE EXECUTE ON FUNCTION public.ye_trilha_evidencia_da_empresa(text) FROM PUBLIC, anon';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.ye_trilha_evidencia_da_empresa(text) TO authenticated, service_role';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Ajuste de grants pulado: %', SQLERRM;
END $g$;

-- 1) ATESTADOS ---------------------------------------------------------------
DO $atest$
BEGIN
  DROP POLICY IF EXISTS "Managers podem ver atestados" ON storage.objects;
  DROP POLICY IF EXISTS "Managers podem fazer upload de atestados" ON storage.objects;
  DROP POLICY IF EXISTS "Managers podem deletar atestados" ON storage.objects;
  DROP POLICY IF EXISTS "Atestados: leitura pela empresa e pelo perfil" ON storage.objects;
  DROP POLICY IF EXISTS "Atestados: envio pela empresa e pelo perfil" ON storage.objects;
  DROP POLICY IF EXISTS "Atestados: exclusao pela empresa e pelo perfil" ON storage.objects;

  CREATE POLICY "Atestados: leitura pela empresa e pelo perfil"
    ON storage.objects FOR SELECT TO authenticated
    USING (
      bucket_id = 'atestados'
      AND split_part(name, '/', 1) = public.get_user_tenant_id()::text
      AND public.perfil_permite_modulo(public.get_user_tenant_id(), 'atestados', 'sst')
    );
  CREATE POLICY "Atestados: envio pela empresa e pelo perfil"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (
      bucket_id = 'atestados'
      AND split_part(name, '/', 1) = public.get_user_tenant_id()::text
      AND public.perfil_permite_modulo(public.get_user_tenant_id(), 'atestados', 'sst')
    );
  CREATE POLICY "Atestados: exclusao pela empresa e pelo perfil"
    ON storage.objects FOR DELETE TO authenticated
    USING (
      bucket_id = 'atestados'
      AND split_part(name, '/', 1) = public.get_user_tenant_id()::text
      AND public.perfil_permite_modulo(public.get_user_tenant_id(), 'atestados', 'sst')
    );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENCAO: regras do bucket atestados nao aplicadas: %', SQLERRM;
END $atest$;

-- 2) TRILHA-EVIDENCIAS (a evidencia propria continua pelas regras de "dono do arquivo") -----
DO $trilha$
BEGIN
  DROP POLICY IF EXISTS "Managers can view all trilha evidence" ON storage.objects;
  DROP POLICY IF EXISTS "Trilha: evidencias da empresa lidas pelo perfil" ON storage.objects;
  CREATE POLICY "Trilha: evidencias da empresa lidas pelo perfil"
    ON storage.objects FOR SELECT TO authenticated
    USING (
      bucket_id = 'trilha-evidencias'
      AND public.ye_trilha_evidencia_da_empresa(name)
      AND public.perfil_permite_modulo(public.get_user_tenant_id(), 'trilhas', 'aprendizado')
    );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENCAO: regra do bucket trilha-evidencias nao aplicada: %', SQLERRM;
END $trilha$;

-- 3) EPI-SIGNATURES (envio so na pasta da empresa; exclusao pela empresa e pelo perfil) --------
DO $epi$
BEGIN
  DROP POLICY IF EXISTS "Managers podem deletar assinaturas" ON storage.objects;
  DROP POLICY IF EXISTS "Usuários podem fazer upload de assinaturas" ON storage.objects;
  DROP POLICY IF EXISTS "EPI assinaturas: exclusao pela empresa e pelo perfil" ON storage.objects;
  DROP POLICY IF EXISTS "EPI assinaturas: envio so na pasta da empresa" ON storage.objects;

  CREATE POLICY "EPI assinaturas: exclusao pela empresa e pelo perfil"
    ON storage.objects FOR DELETE TO authenticated
    USING (
      bucket_id = 'epi-signatures'
      AND split_part(name, '/', 1) = public.get_user_tenant_id()::text
      AND public.perfil_permite_modulo(public.get_user_tenant_id(), 'epi')
    );
  CREATE POLICY "EPI assinaturas: envio so na pasta da empresa"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (
      bucket_id = 'epi-signatures'
      AND split_part(name, '/', 1) = public.get_user_tenant_id()::text
    );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENCAO: regras do bucket epi-signatures nao aplicadas: %', SQLERRM;
END $epi$;

-- 4) ERGONOMIA-EVIDENCIAS e HUB-CONTABIL (ja limitavam a pasta da empresa; faltava o perfil) ----
DO $outros$
BEGIN
  DROP POLICY IF EXISTS "Tenant users can delete ergonomia evidencias" ON storage.objects;
  DROP POLICY IF EXISTS "Ergonomia: exclusao pela empresa e pelo perfil" ON storage.objects;
  CREATE POLICY "Ergonomia: exclusao pela empresa e pelo perfil"
    ON storage.objects FOR DELETE TO authenticated
    USING (
      bucket_id = 'ergonomia-evidencias'
      AND (storage.foldername(name))[1] = public.get_user_tenant_id()::text
      AND public.perfil_permite_modulo(public.get_user_tenant_id(), 'ergonomia')
    );

  DROP POLICY IF EXISTS "Tenant users can delete hub-contabil files" ON storage.objects;
  DROP POLICY IF EXISTS "Hub contabil: exclusao pela empresa e pelo perfil" ON storage.objects;
  CREATE POLICY "Hub contabil: exclusao pela empresa e pelo perfil"
    ON storage.objects FOR DELETE TO authenticated
    USING (
      bucket_id = 'hub-contabil'
      AND (storage.foldername(name))[1] = public.get_user_tenant_id()::text
      AND public.perfil_permite_modulo(public.get_user_tenant_id(), 'hub_contabil')
    );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENCAO: regras de ergonomia/hub-contabil nao aplicadas: %', SQLERRM;
END $outros$;

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT
  (SELECT count(*) FROM pg_policies WHERE schemaname='storage' AND tablename='objects'
     AND policyname IN ('Atestados: leitura pela empresa e pelo perfil','Atestados: envio pela empresa e pelo perfil',
                        'Atestados: exclusao pela empresa e pelo perfil','Trilha: evidencias da empresa lidas pelo perfil',
                        'EPI assinaturas: exclusao pela empresa e pelo perfil','EPI assinaturas: envio so na pasta da empresa',
                        'Ergonomia: exclusao pela empresa e pelo perfil','Hub contabil: exclusao pela empresa e pelo perfil')) AS regras_novas_esperado_8,
  (SELECT count(*) FROM pg_policies WHERE schemaname='storage' AND tablename='objects'
     AND policyname IN ('Managers podem ver atestados','Managers podem fazer upload de atestados','Managers podem deletar atestados',
                        'Managers can view all trilha evidence','Managers podem deletar assinaturas'))                    AS regras_antigas_esperado_0,
  (SELECT count(*) FROM pg_proc WHERE proname='ye_trilha_evidencia_da_empresa')                                        AS funcao_de_apoio_esperado_1;

-- PARA DESFAZER (recria o comportamento antigo — so papel, sem empresa; NAO recomendado):
--   DROP POLICY "Atestados: leitura pela empresa e pelo perfil" ON storage.objects;  (e as demais novas)
--   CREATE POLICY "Managers podem ver atestados" ON storage.objects FOR SELECT TO authenticated
--     USING (bucket_id = 'atestados' AND has_minimum_role(auth.uid(), 'manager'::app_role));
