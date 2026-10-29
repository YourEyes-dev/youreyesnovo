-- ============================================================================
-- SCRIPT DE ENTREGA (PRODUÇÃO) — SEGURANÇA: selfies das batidas privadas
-- ATENÇÃO À ORDEM: publique ANTES as telas desta entrega (Vercel, PR main →
-- producao). A tela nova exibe a selfie por link temporário e funciona com o
-- bucket ainda público; depois deste script, a tela antiga deixaria de mostrar.
-- Torna o bucket ponto-selfies privado e deixa a leitura só para usuário logado
-- da empresa da batida. Não altera dados. Idempotente.
-- O índice novo trava gravações em ponto_marcacoes por alguns segundos enquanto
-- é criado: rodar fora do horário de pico de batidas.
-- ============================================================================

SET lock_timeout = '10s';

-- Caminho do arquivo a partir do valor gravado (URL pública antiga ou caminho)
CREATE OR REPLACE FUNCTION public.ponto_selfie_caminho(p_valor text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT CASE
    WHEN p_valor IS NULL OR p_valor = '' THEN NULL
    WHEN position('/ponto-selfies/' IN p_valor) > 0
      THEN split_part(substring(p_valor FROM position('/ponto-selfies/' IN p_valor) + 15), '?', 1)
    ELSE split_part(p_valor, '?', 1)
  END;
$function$;

CREATE INDEX IF NOT EXISTS idx_ponto_marcacoes_selfie_caminho
  ON public.ponto_marcacoes (public.ponto_selfie_caminho(selfie_url))
  WHERE selfie_url IS NOT NULL;

-- A selfie pertence a uma batida da empresa do usuário logado?
CREATE OR REPLACE FUNCTION public.ponto_selfie_do_meu_tenant(p_caminho text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.ponto_marcacoes m
    WHERE m.selfie_url IS NOT NULL
      AND public.ponto_selfie_caminho(m.selfie_url) = p_caminho
      AND m.tenant_id = public.current_user_tenant_id()
  );
$function$;

REVOKE ALL ON FUNCTION public.ponto_selfie_do_meu_tenant(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ponto_selfie_do_meu_tenant(text) TO authenticated;

DROP POLICY IF EXISTS "Anyone can view ponto selfies" ON storage.objects;
DROP POLICY IF EXISTS "Tenant users can view ponto selfies" ON storage.objects;
DROP POLICY IF EXISTS "ponto_selfies_select_tenant" ON storage.objects;
-- exclusão ampla antiga (qualquer usuário logado, bucket inteiro); fica só a do superadmin
DROP POLICY IF EXISTS "Users can delete own ponto selfies" ON storage.objects;
CREATE POLICY "ponto_selfies_select_tenant"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'ponto-selfies'
  AND public.ponto_selfie_do_meu_tenant(name)
);

UPDATE storage.buckets SET public = false WHERE id = 'ponto-selfies';

-- Conferência (o editor mostra só este resultado)
SELECT json_build_object(
  'bucket_privado', (SELECT NOT b.public FROM storage.buckets b WHERE b.id = 'ponto-selfies'),
  'politica_leitura_por_empresa', EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='ponto_selfies_select_tenant'),
  'politicas_leitura_sem_checagem', (SELECT count(*) FROM pg_policies p WHERE p.schemaname='storage' AND p.tablename='objects'
       AND p.cmd IN ('SELECT','ALL') AND COALESCE(p.qual,'') ILIKE '%ponto-selfies%'
       AND COALESCE(p.qual,'') NOT ILIKE '%ponto_selfie_do_meu_tenant%'),
  'indice_criado', to_regclass('public.idx_ponto_marcacoes_selfie_caminho') IS NOT NULL,
  'batidas_com_selfie', (SELECT count(*) FROM public.ponto_marcacoes WHERE selfie_url IS NOT NULL)
) AS resultado;
