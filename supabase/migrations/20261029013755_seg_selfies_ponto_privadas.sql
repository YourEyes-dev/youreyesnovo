-- ============================================================================
-- SEGURANÇA — selfies das batidas de ponto deixam de ser públicas (LGPD)
-- ----------------------------------------------------------------------------
-- O bucket ponto-selfies foi criado PÚBLICO (20260311193831) e as telas
-- gravavam o link público de cada foto em ponto_marcacoes.selfie_url. Quem
-- tivesse o link abria a foto do rosto do colaborador sem login, para sempre
-- (no quiosque interno o caminho ainda levava o CPF). Além disso a política
-- "Anyone can view ponto selfies" deixava qualquer usuário logado, de QUALQUER
-- empresa, ler o bucket inteiro.
--
-- Correção:
--   * bucket privado;
--   * leitura só para usuário logado e só da selfie que pertence a uma batida
--     da PRÓPRIA empresa — vale para qualquer formato de caminho, antigo ou
--     novo, via ponto_selfie_caminho(selfie_url) com índice;
--   * as telas passam a gravar o caminho e exibir por link temporário (o front
--     desta entrega publica ANTES do script de produção).
-- O envio (INSERT) não muda. LGPD art. 11, II, g e art. 46. QA PONTO-SEG-02.
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

-- ---------------------------------------------------------------------
-- QA PONTO-SEG-02
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_seg_02()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_publico boolean;
  v_amplas int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir o bucket ponto-selfies e suas políticas de leitura';
  r.esperado    := 'Bucket privado; nenhuma política de leitura sem a checagem de empresa';

  v_publico := (SELECT b.public FROM storage.buckets b WHERE b.id = 'ponto-selfies');
  v_amplas := (SELECT count(*) FROM pg_policies p
                WHERE p.schemaname = 'storage' AND p.tablename = 'objects'
                  AND p.cmd IN ('SELECT', 'ALL')
                  AND COALESCE(p.qual, '') ILIKE '%ponto-selfies%'
                  AND COALESCE(p.qual, '') NOT ILIKE '%ponto_selfie_do_meu_tenant%');

  IF COALESCE(v_publico, false) = false AND v_amplas = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'Selfies em bucket privado; leitura só da própria empresa.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: bucket público=%s; políticas de leitura sem checagem de empresa=%s. '
             || 'A foto do rosto do colaborador fica acessível fora da empresa (LGPD arts. 11 e 46).',
             coalesce(v_publico::text, 'bucket ausente'), v_amplas);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

INSERT INTO public.qa_casos_teste
  (codigo, modulo_id, titulo, objetivo, tipo, nivel, prioridade, status,
   base_legal, passos, disposicao, observacoes)
SELECT
  'PONTO-SEG-02', m.id,
  'Selfies das batidas ficam em bucket privado, legíveis só pela própria empresa',
  'A selfie da batida é a foto do rosto do colaborador. Não pode abrir por link público nem ser '
  || 'lida por usuário de outra empresa.',
  'negativo', 'api', 'critica', 'aprovado',
  'LGPD art. 11, II, g (prevenção à fraude na autenticação) e art. 46 (segurança)',
  jsonb_build_array(jsonb_build_object('ordem', 1,
    'acao', 'Conferir o bucket ponto-selfies e as políticas de leitura',
    'esperado', 'Privado; leitura só com checagem de empresa')),
  'em_triagem',
  'Achado em 29/10/2026 ao analisar selfie no pedido de ajuste: bucket criado público em 20260311193831.'
FROM public.qa_modulos m
WHERE m.path = 'jornada-rotina/ponto'
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
VALUES ('PONTO-SEG-02', 'qa_caso_ponto_seg_02', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
