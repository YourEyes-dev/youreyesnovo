-- ============================================================================
-- Mapa Comportamental — Link público por empresa (colaborador sem acesso ao
-- sistema) + cruzamento por CPF no "Meu Mapa".
--
-- Necessidade: há funcionários que não têm login. O gestor gera um link por
-- empresa, envia ao funcionário, e ele responde o mapa se identificando por
-- CPF. A resposta grava a empresa do link. Mesmo padrão dos links públicos de
-- Ponto e Ouvidoria (token por tenant/empresa + RPCs SECURITY DEFINER anon que
-- rederivam tenant/empresa do token — o cliente nunca envia tenant/empresa).
--
-- E: quando o funcionário passar a ter login com o MESMO CPF, o "Meu Mapa" tem
-- de encontrar o mapa que ele respondeu por link (cruzamento por CPF), além do
-- vínculo por auth_user_id.
-- ============================================================================

SET lock_timeout = '10s';

-- ────────────────────────────────────────────────────────────────────────────
-- 1) Tabela de links públicos (um por empresa dentro do tenant)
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.mapa_comportamental_links (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  empresa_id     uuid,
  token          text NOT NULL DEFAULT encode(gen_random_bytes(16), 'hex'),
  ativo          boolean NOT NULL DEFAULT true,
  data_expiracao timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_mapa_links_token ON public.mapa_comportamental_links(token);
-- Um link por (tenant, empresa). COALESCE para tratar "sem empresa" como chave estável.
CREATE UNIQUE INDEX IF NOT EXISTS uq_mapa_links_por_empresa
  ON public.mapa_comportamental_links(tenant_id, COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid));

ALTER TABLE public.mapa_comportamental_links ENABLE ROW LEVEL SECURITY;

DO $pol$
BEGIN
  DROP POLICY IF EXISTS mapa_links_select ON public.mapa_comportamental_links;
  CREATE POLICY mapa_links_select ON public.mapa_comportamental_links
    FOR SELECT TO authenticated
    USING (tenant_id = public.get_user_tenant_id() OR public.is_superadmin(auth.uid()));

  DROP POLICY IF EXISTS mapa_links_manage ON public.mapa_comportamental_links;
  CREATE POLICY mapa_links_manage ON public.mapa_comportamental_links
    FOR ALL TO authenticated
    USING (tenant_id = public.get_user_tenant_id() AND public.has_minimum_role(auth.uid(), 'manager'::public.app_role))
    WITH CHECK (tenant_id = public.get_user_tenant_id() AND public.has_minimum_role(auth.uid(), 'manager'::public.app_role));
END $pol$;

-- ────────────────────────────────────────────────────────────────────────────
-- 2) Ajustes na tabela de respostas para aceitar submissão anônima por link
--    - auth_user_id passa a ser NULLABLE (resposta por link não tem login)
--    - coluna origem marca a procedência ('app' | 'link_publico')
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.mapa_comportamental_respostas ALTER COLUMN auth_user_id DROP NOT NULL;
ALTER TABLE public.mapa_comportamental_respostas ADD COLUMN IF NOT EXISTS origem text NOT NULL DEFAULT 'app';

-- Trigger de identidade: só carimba a partir do usuário logado. Em submissão
-- anônima (auth.uid() IS NULL), respeita o que a RPC SECURITY DEFINER preencheu.
CREATE OR REPLACE FUNCTION public.mapa_comportamental_carimbar_identidade()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_ub record;
BEGIN
  IF v_uid IS NULL THEN
    -- Submissão por link público: a identidade já vem da RPC (tenant/empresa/
    -- cpf/nome), não sobrescreve nada.
    RETURN NEW;
  END IF;
  NEW.auth_user_id := v_uid;
  NEW.tenant_id := COALESCE(public.get_user_tenant_id(), NEW.tenant_id);
  SELECT ub.id, ub.nome_completo,
         regexp_replace(COALESCE(ub.cpf, ''), '[^0-9]', '', 'g') AS cpf_num
    INTO v_ub
    FROM public.usuarios_base ub
   WHERE ub.auth_user_id = v_uid
   LIMIT 1;
  IF FOUND THEN
    NEW.usuario_id       := v_ub.id;
    NEW.colaborador_nome := v_ub.nome_completo;
    NEW.colaborador_cpf  := NULLIF(v_ub.cpf_num, '');
  END IF;
  RETURN NEW;
END;
$fn$;

-- ────────────────────────────────────────────────────────────────────────────
-- 3) Cruzamento por CPF na LEITURA do próprio mapa (RLS)
--    O titular sempre lê os mapas do próprio auth_user_id E os que tenham o
--    CPF dele (ex.: respondidos por link antes de ele ter login).
-- ────────────────────────────────────────────────────────────────────────────
DO $pol$
BEGIN
  DROP POLICY IF EXISTS mapa_comp_resp_select_titular ON public.mapa_comportamental_respostas;
  CREATE POLICY mapa_comp_resp_select_titular ON public.mapa_comportamental_respostas
    FOR SELECT TO authenticated
    USING (
      auth_user_id = auth.uid()
      OR public.is_superadmin(auth.uid())
      OR (public.cpf_do_usuario_logado() <> '' AND colaborador_cpf = public.cpf_do_usuario_logado())
    );

  DROP POLICY IF EXISTS perfil_restringe_leitura_mapa_comportamental_respostas ON public.mapa_comportamental_respostas;
  CREATE POLICY perfil_restringe_leitura_mapa_comportamental_respostas ON public.mapa_comportamental_respostas
    AS RESTRICTIVE FOR SELECT TO authenticated
    USING (
      auth_user_id = auth.uid()
      OR public.is_superadmin(auth.uid())
      OR (public.cpf_do_usuario_logado() <> '' AND colaborador_cpf = public.cpf_do_usuario_logado())
      OR public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['mapa_comportamental'::text])
    );
END $pol$;

-- Leitura dos MEUS mapas (auth_user_id OU cpf) — usada pela tela "Meu Mapa".
-- SECURITY DEFINER e restrita ao próprio chamador (nunca devolve mapa alheio).
CREATE OR REPLACE FUNCTION public.mapa_comportamental_meus()
RETURNS SETOF public.mapa_comportamental_respostas
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT r.*
  FROM public.mapa_comportamental_respostas r
  WHERE r.tenant_id = public.get_user_tenant_id()
    AND (
      r.auth_user_id = auth.uid()
      OR (public.cpf_do_usuario_logado() <> '' AND r.colaborador_cpf = public.cpf_do_usuario_logado())
    )
  ORDER BY r.created_at DESC;
$fn$;

REVOKE EXECUTE ON FUNCTION public.mapa_comportamental_meus() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.mapa_comportamental_meus() TO authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- 4) Helper: nome de exibição da empresa (não exposto a anon diretamente)
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._mapa_nome_empresa(p_tenant_id uuid, p_empresa_id uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE v_nome text;
BEGIN
  IF p_empresa_id IS NOT NULL THEN
    SELECT COALESCE(NULLIF(ec.nome_fantasia, ''), NULLIF(ec.razao_social, ''))
      INTO v_nome
      FROM public.empresa_cadastro ec
     WHERE ec.id = p_empresa_id AND ec.tenant_id = p_tenant_id
     LIMIT 1;
  END IF;
  RETURN COALESCE(v_nome, 'sua empresa');
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public._mapa_nome_empresa(uuid, uuid) FROM PUBLIC, anon;

-- ────────────────────────────────────────────────────────────────────────────
-- 5) RPC anônima: validar o token do link e devolver o contexto para a tela
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.mapa_comportamental_link_por_token(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE v_link record; v_aviso text;
BEGIN
  SELECT l.tenant_id, l.empresa_id
    INTO v_link
    FROM public.mapa_comportamental_links l
   WHERE l.token = p_token
     AND l.ativo
     AND (l.data_expiracao IS NULL OR l.data_expiracao > now())
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('valido', false, 'error', 'Link inválido ou expirado.');
  END IF;

  SELECT COALESCE(NULLIF(p.texto_aviso, ''), NULL)
    INTO v_aviso
    FROM public.mapa_comportamental_politicas p
   WHERE p.tenant_id = v_link.tenant_id AND p.publicada
   ORDER BY p.versao DESC
   LIMIT 1;

  RETURN jsonb_build_object(
    'valido', true,
    'empresa_nome', public._mapa_nome_empresa(v_link.tenant_id, v_link.empresa_id),
    'aviso', v_aviso
  );
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.mapa_comportamental_link_por_token(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.mapa_comportamental_link_por_token(text) TO anon, authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- 6) RPC anônima: salvar a resposta do mapa pelo link (identifica por CPF)
--    Rederiva tenant/empresa do token. O cálculo determinístico é feito no
--    cliente (mesmo padrão do fluxo logado; respostas ficam guardadas para
--    auditar/recalcular). Grava origem='link_publico'.
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.mapa_comportamental_salvar_por_token(
  p_token   text,
  p_cpf     text,
  p_nome    text,
  p_payload jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_link record;
  v_cpf  text := regexp_replace(COALESCE(p_cpf, ''), '[^0-9]', '', 'g');
  v_id   uuid;
BEGIN
  IF length(v_cpf) <> 11 THEN
    RETURN jsonb_build_object('success', false, 'error', 'CPF inválido.');
  END IF;
  IF p_payload IS NULL OR p_payload->'respostas' IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Respostas ausentes.');
  END IF;

  SELECT l.tenant_id, l.empresa_id
    INTO v_link
    FROM public.mapa_comportamental_links l
   WHERE l.token = p_token
     AND l.ativo
     AND (l.data_expiracao IS NULL OR l.data_expiracao > now())
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Link inválido ou expirado.');
  END IF;

  INSERT INTO public.mapa_comportamental_respostas (
    tenant_id, empresa_id, auth_user_id, colaborador_nome, colaborador_cpf,
    origem, instrumento_versao, algoritmo_versao, status, respostas, resultado,
    arquetipo, indice_consistencia, confiabilidade, aviso_versao, aviso_aceite_em,
    tempo_total_segundos, tempo_por_item, concluido_em, vence_em
  )
  VALUES (
    v_link.tenant_id,
    v_link.empresa_id,
    NULL,
    NULLIF(trim(COALESCE(p_nome, '')), ''),
    v_cpf,
    'link_publico',
    COALESCE((p_payload->>'instrumento_versao')::int, 1),
    COALESCE(p_payload->>'algoritmo_versao', 'v1'),
    'concluido',
    COALESCE(p_payload->'respostas', '{}'::jsonb),
    p_payload->'resultado',
    p_payload->>'arquetipo',
    (p_payload->>'indice_consistencia')::int,
    NULLIF(p_payload->>'confiabilidade', ''),
    NULLIF(p_payload->>'aviso_versao', ''),
    now(),
    (p_payload->>'tempo_total_segundos')::int,
    p_payload->'tempo_por_item',
    now(),
    (now() + interval '24 months')::date
  )
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('success', true, 'id', v_id);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', 'Não foi possível salvar agora.');
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.mapa_comportamental_salvar_por_token(text, text, text, jsonb) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.mapa_comportamental_salvar_por_token(text, text, text, jsonb) TO anon, authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- 7) QA — MAPA-008 (link público) e MAPA-009 (cruzamento por CPF)
-- ────────────────────────────────────────────────────────────────────────────
DO $doc$
DECLARE v_mod uuid;
BEGIN
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'desenvolvimento-performance/mapa-comportamental');
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo QA ausente — pulei os casos do link público.';
    RETURN;
  END IF;
  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
    (v_mod, 'MAPA-008', 'Link público por empresa: tabela e RPCs anônimas presentes', 'feliz', 'alta', 'aprovado', 'api',
     'Existe tabela de links e as RPCs anônimas de validar token e salvar por token.',
     'Migration do link público aplicada.',
     '[{"ordem":1,"acao":"Verificar objetos do link público","resultado_esperado":"tabela e 2 RPCs anônimas presentes"}]'::jsonb,
     'Objetos do link público presentes.', 'Colaborador sem login responde por CPF; grava empresa do link.'),
    (v_mod, 'MAPA-009', 'Meu Mapa cruza por CPF (auth_user_id ou CPF do usuário logado)', 'feliz', 'alta', 'aprovado', 'api',
     'A função de leitura do próprio mapa cruza por CPF além do auth_user_id.',
     'Migration do link público aplicada.',
     '[{"ordem":1,"acao":"Verificar mapa_comportamental_meus","resultado_esperado":"presente e SECURITY DEFINER"}]'::jsonb,
     'Cruzamento por CPF presente.', 'Mapa respondido por link aparece no Meu Mapa do usuário de mesmo CPF.')
  ON CONFLICT (codigo) DO NOTHING;
  RAISE NOTICE 'OK: casos MAPA-008/009 documentados.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'MAPA-008/009 doc: %', SQLERRM;
END $doc$;

CREATE OR REPLACE FUNCTION public.qa_caso_mapa_008()
RETURNS public.qa_retorno
LANGUAGE plpgsql
AS $fn$
DECLARE r public.qa_retorno; v_ok boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Verificar tabela de links e RPCs anônimas do link público';
  r.esperado    := 'mapa_comportamental_links + link_por_token + salvar_por_token presentes';
  v_ok := (to_regclass('public.mapa_comportamental_links') IS NOT NULL)
      AND EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'mapa_comportamental_link_por_token')
      AND EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'mapa_comportamental_salvar_por_token');
  IF v_ok THEN r.situacao := 'passou'; r.obtido := 'Objetos presentes';
  ELSE r.situacao := 'falhou'; r.obtido := 'Objeto(s) do link público ausente(s)'; END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_mapa_009()
RETURNS public.qa_retorno
LANGUAGE plpgsql
AS $fn$
DECLARE r public.qa_retorno; v_ok boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Verificar leitura do próprio mapa com cruzamento por CPF';
  r.esperado    := 'mapa_comportamental_meus presente e SECURITY DEFINER';
  v_ok := (SELECT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'mapa_comportamental_meus' AND p.prosecdef));
  IF v_ok THEN r.situacao := 'passou'; r.obtido := 'Função presente e SECURITY DEFINER';
  ELSE r.situacao := 'falhou'; r.obtido := 'Função ausente ou não SECURITY DEFINER'; END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END;
$fn$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES
  ('MAPA-008', 'qa_caso_mapa_008'),
  ('MAPA-009', 'qa_caso_mapa_009')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
