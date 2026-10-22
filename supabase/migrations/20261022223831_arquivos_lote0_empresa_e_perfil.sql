-- ============================================================================
-- ARQUIVOS (storage) — LOTE 0: regras que valiam para QUALQUER gestor de QUALQUER empresa
--
-- Levantamento de 10/2026 (consulta B): regras de arquivos decidiam so pelo PAPEL (manager),
-- sem olhar a empresa nem o perfil. Pela regra, quem tinha papel de gestao em uma empresa podia
-- listar/baixar/apagar os arquivos de OUTRAS empresas nestes buckets:
--   atestados          leitura, envio e exclusao (atestados medicos — LGPD art. 11)
--   trilha-evidencias  leitura (evidencias de treinamento de colaboradores)
--   epi-signatures     exclusao e envio (fotos e assinaturas de entrega de EPI)
--   ergonomia-evidencias, hub-contabil  exclusao (ja limitava a pasta da empresa; faltava o perfil)
--
-- O que muda: cada regra passa a exigir A EMPRESA (pasta ou registro da empresa) e o PERFIL
-- (perfil_permite_modulo: dono e Super Admin passam; sem perfil vinculado vale o papel de gestao,
-- como sempre; com perfil exige o modulo em escopo amplo).
--
-- NAO muda (anotado para a proxima etapa): o bucket epi-signatures e PUBLICO — a leitura por
-- endereco continua aberta; fecha-lo exige trocar as telas para endereco assinado e migrar os
-- enderecos ja gravados. Super Admin continua apagando ponto-selfies.
--
-- Caminhos conferidos no front: atestados e epi-signatures comecam pela empresa; trilha-evidencias
-- comeca pelo colaborador (por isso a leitura confere o registro em trilha_progresso).
-- Funcoes de borda (assinaturas) usam a chave de servico e nao sao afetadas.
-- So politicas e uma funcao de apoio; nenhum dado e alterado.
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
