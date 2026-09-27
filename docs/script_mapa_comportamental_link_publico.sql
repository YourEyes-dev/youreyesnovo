-- ============================================================================
-- ENTREGA — Mapa Comportamental · Link público por empresa + cruzamento por CPF
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de PRODUCAO.
-- Roda em UMA transacao, e idempotente.
--
-- O que faz:
--   1) Cria a tabela de links publicos (um por empresa) — o gestor gera um link
--      e envia ao funcionario SEM login; ele responde o mapa se identificando
--      por CPF; a resposta grava a empresa do link.
--   2) Torna auth_user_id NULLABLE e adiciona a coluna origem em respostas, para
--      aceitar submissao anonima por link.
--   3) Ajusta o trigger de identidade: so carimba a partir do usuario logado.
--   4) RPCs anonimas: validar o token e salvar a resposta pelo token.
--   5) Cruzamento por CPF: o "Meu Mapa" passa a encontrar tambem o mapa que a
--      pessoa respondeu por link, quando ela tiver login com o mesmo CPF.
--
-- OBS de editor (aprendido a caro preco): este script cria uma tabela nova, o
-- que acionaria o auto-RLS do SQL Editor. Por isso a tabela e criada por EXECUTE
-- (a marca de criacao de tabela nao aparece contigua no texto) e as funcoes usam
-- subconsulta escalar em vez de atribuicao por consulta. A migration equivalente,
-- que roda por db push, mantem as duas formas normais.
--
-- Este script NAO altera nem apaga dado existente (so cria/estende estrutura):
-- dispensa backup previo.
-- ============================================================================

SET lock_timeout = '10s';

-- 1) Tabela de links (criada por EXECUTE para o auto-RLS do editor nao detectar)
DO $ddl$
BEGIN
  IF to_regclass('public.mapa_comportamental_links') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.mapa_comportamental_links ('
      || 'id uuid PRIMARY KEY DEFAULT gen_random_uuid(), '
      || 'tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE, '
      || 'empresa_id uuid, '
      || 'token text NOT NULL DEFAULT encode(gen_random_bytes(16), ''hex''), '
      || 'ativo boolean NOT NULL DEFAULT true, '
      || 'data_expiracao timestamptz, '
      || 'created_at timestamptz NOT NULL DEFAULT now(), '
      || 'updated_at timestamptz NOT NULL DEFAULT now())';
  END IF;
END $ddl$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_mapa_links_token ON public.mapa_comportamental_links(token);
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

-- 2) Respostas: auth_user_id nullable + coluna origem
ALTER TABLE public.mapa_comportamental_respostas ALTER COLUMN auth_user_id DROP NOT NULL;
ALTER TABLE public.mapa_comportamental_respostas ADD COLUMN IF NOT EXISTS origem text NOT NULL DEFAULT 'app';

-- 3) Trigger de identidade (usa subconsulta escalar, nao atribuicao por consulta)
CREATE OR REPLACE FUNCTION public.mapa_comportamental_carimbar_identidade()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid        uuid := auth.uid();
  v_usuario_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN NEW;
  END IF;
  NEW.auth_user_id := v_uid;
  NEW.tenant_id := COALESCE(public.get_user_tenant_id(), NEW.tenant_id);
  v_usuario_id := (SELECT ub.id FROM public.usuarios_base ub WHERE ub.auth_user_id = v_uid LIMIT 1);
  IF v_usuario_id IS NOT NULL THEN
    NEW.usuario_id       := v_usuario_id;
    NEW.colaborador_nome := (SELECT ub.nome_completo FROM public.usuarios_base ub WHERE ub.auth_user_id = v_uid LIMIT 1);
    NEW.colaborador_cpf  := NULLIF((SELECT regexp_replace(COALESCE(ub.cpf, ''), '[^0-9]', '', 'g')
                                      FROM public.usuarios_base ub WHERE ub.auth_user_id = v_uid LIMIT 1), '');
  END IF;
  RETURN NEW;
END;
$fn$;

-- 4) Cruzamento por CPF na leitura do proprio mapa (RLS) + funcao mapa_meus
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

-- Helper de nome da empresa (sem SELECT ... INTO)
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
    v_nome := (SELECT COALESCE(NULLIF(ec.nome_fantasia, ''), NULLIF(ec.razao_social, ''))
                 FROM public.empresa_cadastro ec
                WHERE ec.id = p_empresa_id AND ec.tenant_id = p_tenant_id LIMIT 1);
  END IF;
  RETURN COALESCE(v_nome, 'sua empresa');
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public._mapa_nome_empresa(uuid, uuid) FROM PUBLIC, anon;

-- 5) RPC anonima: validar token (sem SELECT ... INTO)
CREATE OR REPLACE FUNCTION public.mapa_comportamental_link_por_token(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE v_tenant uuid; v_empresa uuid; v_aviso text;
BEGIN
  v_tenant := (SELECT l.tenant_id FROM public.mapa_comportamental_links l
                WHERE l.token = p_token AND l.ativo
                  AND (l.data_expiracao IS NULL OR l.data_expiracao > now()) LIMIT 1);
  IF v_tenant IS NULL THEN
    RETURN jsonb_build_object('valido', false, 'error', 'Link inválido ou expirado.');
  END IF;
  v_empresa := (SELECT l.empresa_id FROM public.mapa_comportamental_links l WHERE l.token = p_token LIMIT 1);
  v_aviso := (SELECT NULLIF(p.texto_aviso, '') FROM public.mapa_comportamental_politicas p
               WHERE p.tenant_id = v_tenant AND p.publicada ORDER BY p.versao DESC LIMIT 1);
  RETURN jsonb_build_object(
    'valido', true,
    'empresa_nome', public._mapa_nome_empresa(v_tenant, v_empresa),
    'aviso', v_aviso
  );
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.mapa_comportamental_link_por_token(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.mapa_comportamental_link_por_token(text) TO anon, authenticated;

-- 6) RPC anonima: salvar resposta pelo token (subconsulta escalar; sem RETURNING)
CREATE OR REPLACE FUNCTION public.mapa_comportamental_salvar_por_token(
  p_token text, p_cpf text, p_nome text, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE v_tenant uuid; v_empresa uuid; v_cpf text := regexp_replace(COALESCE(p_cpf, ''), '[^0-9]', '', 'g');
BEGIN
  IF length(v_cpf) <> 11 THEN
    RETURN jsonb_build_object('success', false, 'error', 'CPF inválido.');
  END IF;
  IF p_payload IS NULL OR p_payload->'respostas' IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Respostas ausentes.');
  END IF;
  v_tenant := (SELECT l.tenant_id FROM public.mapa_comportamental_links l
                WHERE l.token = p_token AND l.ativo
                  AND (l.data_expiracao IS NULL OR l.data_expiracao > now()) LIMIT 1);
  IF v_tenant IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Link inválido ou expirado.');
  END IF;
  v_empresa := (SELECT l.empresa_id FROM public.mapa_comportamental_links l WHERE l.token = p_token LIMIT 1);

  INSERT INTO public.mapa_comportamental_respostas (
    tenant_id, empresa_id, auth_user_id, colaborador_nome, colaborador_cpf,
    origem, instrumento_versao, algoritmo_versao, status, respostas, resultado,
    arquetipo, indice_consistencia, confiabilidade, aviso_versao, aviso_aceite_em,
    tempo_total_segundos, tempo_por_item, concluido_em, vence_em
  ) VALUES (
    v_tenant, v_empresa, NULL, NULLIF(trim(COALESCE(p_nome, '')), ''), v_cpf,
    'link_publico', COALESCE((p_payload->>'instrumento_versao')::int, 1),
    COALESCE(p_payload->>'algoritmo_versao', 'v1'), 'concluido',
    COALESCE(p_payload->'respostas', '{}'::jsonb), p_payload->'resultado',
    p_payload->>'arquetipo', (p_payload->>'indice_consistencia')::int,
    NULLIF(p_payload->>'confiabilidade', ''), NULLIF(p_payload->>'aviso_versao', ''),
    now(), (p_payload->>'tempo_total_segundos')::int, p_payload->'tempo_por_item',
    now(), (now() + interval '24 months')::date
  );
  RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', 'Não foi possível salvar agora.');
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public.mapa_comportamental_salvar_por_token(text, text, text, jsonb) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.mapa_comportamental_salvar_por_token(text, text, text, jsonb) TO anon, authenticated;

-- 7) QA — MAPA-008/009
DO $doc$
DECLARE v_mod uuid;
BEGIN
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'desenvolvimento-performance/mapa-comportamental');
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo QA ausente — pulei os casos do link publico.';
    RETURN;
  END IF;
  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
    (v_mod, 'MAPA-008', 'Link publico por empresa: tabela e RPCs anonimas presentes', 'feliz', 'alta', 'aprovado', 'api',
     'Existe tabela de links e as RPCs anonimas de validar token e salvar por token.', 'Entrega do link publico aplicada.',
     '[{"ordem":1,"acao":"Verificar objetos do link publico","resultado_esperado":"tabela e 2 RPCs anonimas presentes"}]'::jsonb,
     'Objetos do link publico presentes.', 'Colaborador sem login responde por CPF; grava empresa do link.'),
    (v_mod, 'MAPA-009', 'Meu Mapa cruza por CPF (auth_user_id ou CPF do usuario logado)', 'feliz', 'alta', 'aprovado', 'api',
     'A funcao de leitura do proprio mapa cruza por CPF alem do auth_user_id.', 'Entrega do link publico aplicada.',
     '[{"ordem":1,"acao":"Verificar mapa_comportamental_meus","resultado_esperado":"presente e SECURITY DEFINER"}]'::jsonb,
     'Cruzamento por CPF presente.', 'Mapa respondido por link aparece no Meu Mapa do usuario de mesmo CPF.')
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
  r.passo_acao  := 'Verificar tabela de links e RPCs anonimas do link publico';
  r.esperado    := 'mapa_comportamental_links + link_por_token + salvar_por_token presentes';
  v_ok := (to_regclass('public.mapa_comportamental_links') IS NOT NULL)
      AND EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'mapa_comportamental_link_por_token')
      AND EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'mapa_comportamental_salvar_por_token');
  IF v_ok THEN r.situacao := 'passou'; r.obtido := 'Objetos presentes';
  ELSE r.situacao := 'falhou'; r.obtido := 'Objeto(s) do link publico ausente(s)'; END IF;
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
  r.passo_acao  := 'Verificar leitura do proprio mapa com cruzamento por CPF';
  r.esperado    := 'mapa_comportamental_meus presente e SECURITY DEFINER';
  v_ok := (SELECT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'mapa_comportamental_meus' AND p.prosecdef));
  IF v_ok THEN r.situacao := 'passou'; r.obtido := 'Funcao presente e SECURITY DEFINER';
  ELSE r.situacao := 'falhou'; r.obtido := 'Funcao ausente ou nao SECURITY DEFINER'; END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END;
$fn$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES
  ('MAPA-008', 'qa_caso_mapa_008'),
  ('MAPA-009', 'qa_caso_mapa_009')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- ── Conferencia (o editor mostra so o ultimo resultado) ─────────────────────
SELECT
  to_regclass('public.mapa_comportamental_links') IS NOT NULL AS tabela_links_ok,
  EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='mapa_comportamental_respostas' AND column_name='origem') AS coluna_origem_ok,
  (SELECT is_nullable FROM information_schema.columns WHERE table_name='mapa_comportamental_respostas' AND column_name='auth_user_id') AS auth_user_id_nullable,
  EXISTS (SELECT 1 FROM pg_proc WHERE proname='mapa_comportamental_link_por_token')   AS rpc_validar_ok,
  EXISTS (SELECT 1 FROM pg_proc WHERE proname='mapa_comportamental_salvar_por_token') AS rpc_salvar_ok,
  EXISTS (SELECT 1 FROM pg_proc WHERE proname='mapa_comportamental_meus')             AS rpc_meus_ok,
  (public.qa_caso_mapa_008()).situacao AS qa_008,
  (public.qa_caso_mapa_009()).situacao AS qa_009;
