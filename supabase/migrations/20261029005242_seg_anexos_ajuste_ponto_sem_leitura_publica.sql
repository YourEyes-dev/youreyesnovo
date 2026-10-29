-- ============================================================================
-- SEGURANÇA — anexos dos ajustes de ponto enviados pelo app sem leitura pública
-- ----------------------------------------------------------------------------
-- A política "ponto_ajustes_externo_select" (20260523171905) liberava SELECT
-- em storage.objects para anon e authenticated em TODA a pasta externo/ do
-- bucket privado ponto-ajustes-anexos. Com a chave pública do site, qualquer
-- pessoa podia listar e baixar os anexos enviados pelo app de ponto de TODAS
-- as empresas — inclusive atestados e declarações (dado de saúde, LGPD art. 11).
--
-- Correção:
--   * remove a leitura para anon;
--   * cria leitura só para usuário autenticado, e só dos anexos cuja pasta
--     (externo/<token do link>/...) pertence a um link de ponto da PRÓPRIA
--     empresa do usuário;
--   * o envio pelo app (INSERT anon, política ponto_ajustes_externo_insert)
--     continua igual — o app só grava, não lê.
-- Quem lê hoje: só a tela do Ponto do RH (AnexosAjusteModal, signed URL,
-- usuário logado). Idempotente. Caso QA PONTO-SEG-01 (api).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ponto_anexo_externo_do_meu_tenant(p_token text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.ponto_links l
    WHERE l.token = p_token
      AND l.tenant_id = public.current_user_tenant_id()
  );
$function$;

COMMENT ON FUNCTION public.ponto_anexo_externo_do_meu_tenant(text) IS
  'true quando o token de link de ponto pertence à empresa do usuário logado. '
  'Usada pela política de leitura dos anexos externos de ajuste de ponto.';

REVOKE ALL ON FUNCTION public.ponto_anexo_externo_do_meu_tenant(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ponto_anexo_externo_do_meu_tenant(text) TO authenticated;

DROP POLICY IF EXISTS "ponto_ajustes_externo_select" ON storage.objects;
DROP POLICY IF EXISTS "ponto_ajustes_externo_select_tenant" ON storage.objects;
CREATE POLICY "ponto_ajustes_externo_select_tenant"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'ponto-ajustes-anexos'
  AND (storage.foldername(name))[1] = 'externo'
  AND public.ponto_anexo_externo_do_meu_tenant((storage.foldername(name))[2])
);

-- ---------------------------------------------------------------------
-- QA PONTO-SEG-01 — nenhum anon lê anexo de ajuste de ponto
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_seg_01()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_n int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Listar políticas de leitura do bucket ponto-ajustes-anexos que valem para anon';
  r.esperado    := 'Nenhuma: anexo de ajuste (pode ser atestado) só é lido por usuário logado da própria empresa';

  v_n := (SELECT count(*) FROM pg_policies p
           WHERE p.schemaname = 'storage' AND p.tablename = 'objects'
             AND p.cmd IN ('SELECT', 'ALL')
             AND ('anon' = ANY (p.roles) OR 'public' = ANY (p.roles))
             AND COALESCE(p.qual, '') ILIKE '%ponto-ajustes-anexos%');

  IF v_n = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'Nenhuma política deixa anon ler anexos de ajuste de ponto.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: %s política(s) deixam anon ler anexos de ajuste de ponto — '
             || 'exposição de dado de saúde entre empresas (LGPD art. 11).', v_n);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

INSERT INTO public.qa_casos_teste
  (codigo, modulo_id, titulo, objetivo, tipo, nivel, prioridade, status,
   base_legal, passos, disposicao, observacoes)
SELECT
  'PONTO-SEG-01', m.id,
  'Anexos de ajuste de ponto não são legíveis sem login',
  'Os anexos enviados pelo app de ponto (declarações, atestados) ficam no bucket privado '
  || 'ponto-ajustes-anexos. Nenhuma política pode deixar a chave pública (anon) listar ou baixar '
  || 'esses arquivos; o RH lê só os da própria empresa.',
  'negativo', 'api', 'critica', 'aprovado',
  'LGPD art. 11 (dado de saúde) e art. 46 (segurança)',
  jsonb_build_array(jsonb_build_object('ordem', 1,
    'acao', 'Conferir as políticas de leitura do bucket ponto-ajustes-anexos',
    'esperado', 'Nenhuma vale para anon')),
  'em_triagem',
  'Achado na análise da Fase 2 do Ponto (out/2026): política de 20260523171905 liberava externo/ para anon.'
FROM public.qa_modulos m
WHERE m.path = 'jornada-rotina/ponto'
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
VALUES ('PONTO-SEG-01', 'qa_caso_ponto_seg_01', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
