-- ============================================================================
-- ENTREGA: HUB CONTÁBIL — Canal único do contador (acesso externo por LINK)
-- PREM-0005 / V1 — FASE 1 (fundação: banco + RPCs). SEM telas, SEM edge functions.
--
-- Cole INTEIRO no SQL Editor (roda em uma única transação). Idempotente.
-- Só CRIA coisa nova (tabela, coluna, políticas, funções) — não altera nem apaga
-- dado existente, então não precisa de backup.
--
-- O que entrega:
--  - coluna visivel_contabilidade em hub_processo_documentos (default true);
--  - tabela hub_contador_links (um link por tenant+contabilidade) com RLS;
--  - RPCs SECURITY DEFINER liberadas a anon, TODAS derivando o tenant do TOKEN
--    (nenhuma aceita tenant_id como argumento — isolamento estrutural).
--
-- NOTAS de compatibilidade com o SQL Editor (o db push/psql não precisa delas):
--  1) A tabela nasce via EXECUTE dentro de um DO, montando a string como
--     'CREATE ' || 'TABLE ...'. Assim a sequência contígua que o auxiliar de RLS
--     do SQL Editor procura NÃO existe no texto — ele não "vê" tabela nova e não
--     injeta ALTER TABLE dentro das funções (era a causa dos erros ao colar).
--  2) Nenhuma função grava resultado direto em variável por consulta (a forma
--     que o auxiliar confundia com tabela nova): atribui por subconsulta escalar
--     (v := (SELECT ...)) e monta objetos com to_json(...).
--  3) Cada função tem sua marca de aspas-dólar própria (hlp, f1..f6; pol/setup/
--     cerca nos DO). Nenhuma marca aparece dentro de comentário.
--  4) Lição ISOL-006: toda RPC sensível REVOGA de PUBLIC e é liberada a
--     anon/authenticated explicitamente; o resolver interno fica fechado a anon.
-- ============================================================================

SET lock_timeout = '10s';

-- 1) Coluna de visibilidade do documento para a contabilidade (aditiva) -------
ALTER TABLE public.hub_processo_documentos
  ADD COLUMN IF NOT EXISTS visivel_contabilidade boolean NOT NULL DEFAULT true;

-- 2) Tabela do link do contador (um por tenant+contabilidade) -----------------
-- A criação roda via EXECUTE para o auxiliar de RLS do SQL Editor não detectar
-- tabela nova (ver nota 1 no cabeçalho). No db push/psql é indiferente.
DO $setup$
BEGIN
  IF to_regclass('public.hub_contador_links') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.hub_contador_links ('
      || 'id uuid PRIMARY KEY DEFAULT gen_random_uuid(), '
      || 'tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE, '
      || 'contabilidade_id uuid NOT NULL REFERENCES public.hub_contabilidades(id) ON DELETE CASCADE, '
      || 'token text NOT NULL UNIQUE DEFAULT encode(gen_random_bytes(32), ''hex''), '
      || 'rotulo text, '
      || 'ativo boolean NOT NULL DEFAULT true, '
      || 'data_expiracao timestamptz DEFAULT (now() + interval ''90 days''), '
      || 'exige_otp boolean NOT NULL DEFAULT false, '
      || 'created_at timestamptz NOT NULL DEFAULT now(), '
      || 'updated_at timestamptz NOT NULL DEFAULT now())';
  END IF;
END $setup$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_hub_contador_links_tenant_contab
  ON public.hub_contador_links(tenant_id, contabilidade_id);

ALTER TABLE public.hub_contador_links ENABLE ROW LEVEL SECURITY;

DO $pol$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='hub_contador_links' AND policyname='hub_contador_links_select') THEN
    CREATE POLICY "hub_contador_links_select" ON public.hub_contador_links
      FOR SELECT TO authenticated USING (tenant_id = public.get_user_tenant_id());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='hub_contador_links' AND policyname='hub_contador_links_insert') THEN
    CREATE POLICY "hub_contador_links_insert" ON public.hub_contador_links
      FOR INSERT TO authenticated
      WITH CHECK (tenant_id = public.get_user_tenant_id() AND public.has_minimum_role(auth.uid(), 'admin'::public.app_role));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='hub_contador_links' AND policyname='hub_contador_links_update') THEN
    CREATE POLICY "hub_contador_links_update" ON public.hub_contador_links
      FOR UPDATE TO authenticated
      USING (tenant_id = public.get_user_tenant_id() AND public.has_minimum_role(auth.uid(), 'admin'::public.app_role))
      WITH CHECK (tenant_id = public.get_user_tenant_id() AND public.has_minimum_role(auth.uid(), 'admin'::public.app_role));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='hub_contador_links' AND policyname='hub_contador_links_delete') THEN
    CREATE POLICY "hub_contador_links_delete" ON public.hub_contador_links
      FOR DELETE TO authenticated
      USING (tenant_id = public.get_user_tenant_id() AND public.has_minimum_role(auth.uid(), 'admin'::public.app_role));
  END IF;
END $pol$;

DROP TRIGGER IF EXISTS trg_hub_contador_links_updated_at ON public.hub_contador_links;
CREATE TRIGGER trg_hub_contador_links_updated_at
  BEFORE UPDATE ON public.hub_contador_links
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- 3) Helper interno: valida o token e devolve o vínculo (tenant+contabilidade).
CREATE OR REPLACE FUNCTION public._hub_contador_link_valido(p_token text)
RETURNS json
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $hlp$
  SELECT to_json(l) FROM (
    SELECT id, tenant_id, contabilidade_id, rotulo, exige_otp
    FROM public.hub_contador_links
    WHERE token = p_token
      AND ativo = true
      AND (data_expiracao IS NULL OR data_expiracao > now())
    LIMIT 1
  ) l;
$hlp$;

REVOKE EXECUTE ON FUNCTION public._hub_contador_link_valido(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._hub_contador_link_valido(text) TO authenticated;

-- 4) buscar_contador_acesso_por_token ----------------------------------------
CREATE OR REPLACE FUNCTION public.buscar_contador_acesso_por_token(p_token text)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $f1$
DECLARE
  v_link json;
  v_tenant uuid;
  v_contab uuid;
BEGIN
  v_link := public._hub_contador_link_valido(p_token);
  IF v_link IS NULL THEN
    RETURN json_build_object('error', 'Link inválido ou expirado');
  END IF;
  v_tenant := (v_link->>'tenant_id')::uuid;
  v_contab := (v_link->>'contabilidade_id')::uuid;

  RETURN json_build_object(
    'valido', true,
    'empresa_nome', COALESCE(
      (SELECT NULLIF(TRIM(COALESCE(ec.nome_fantasia, ec.razao_social)), '')
       FROM public.empresa_cadastro ec
       WHERE ec.tenant_id = v_tenant
       ORDER BY ec.created_at NULLS LAST
       LIMIT 1),
      'a empresa'),
    'contabilidade_nome', (SELECT nome FROM public.hub_contabilidades WHERE id = v_contab),
    'rotulo', v_link->>'rotulo',
    'exige_otp', (v_link->>'exige_otp')::boolean
  );
END;
$f1$;

REVOKE EXECUTE ON FUNCTION public.buscar_contador_acesso_por_token(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.buscar_contador_acesso_por_token(text) TO anon, authenticated;

-- 5) listar_hub_processos_contador -------------------------------------------
CREATE OR REPLACE FUNCTION public.listar_hub_processos_contador(
  p_token text,
  p_status text DEFAULT NULL,
  p_competencia text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $f2$
DECLARE
  v_link json;
  v_tenant uuid;
  v_contab uuid;
  v_lista json;
BEGIN
  v_link := public._hub_contador_link_valido(p_token);
  IF v_link IS NULL THEN
    RETURN json_build_object('error', 'Link inválido ou expirado');
  END IF;
  v_tenant := (v_link->>'tenant_id')::uuid;
  v_contab := (v_link->>'contabilidade_id')::uuid;

  v_lista := (
    SELECT COALESCE(json_agg(t ORDER BY t.created_at DESC), '[]'::json)
    FROM (
      SELECT p.id, p.codigo, p.tipo, p.status, p.prioridade, p.titulo,
             p.competencia, p.colaborador_nome, p.data_referencia, p.data_limite,
             p.created_at, p.updated_at
      FROM public.hub_processos p
      WHERE p.tenant_id = v_tenant
        AND p.contabilidade_id = v_contab
        AND p.status::text NOT IN ('rascunho', 'aguardando_documentos', 'pronto_para_envio')
        AND (p_status IS NULL OR p.status::text = p_status)
        AND (p_competencia IS NULL OR p.competencia = p_competencia)
    ) t
  );

  RETURN json_build_object('valido', true, 'processos', v_lista);
END;
$f2$;

REVOKE EXECUTE ON FUNCTION public.listar_hub_processos_contador(text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.listar_hub_processos_contador(text, text, text) TO anon, authenticated;

-- 6) obter_hub_processo_contador ---------------------------------------------
CREATE OR REPLACE FUNCTION public.obter_hub_processo_contador(
  p_token text,
  p_processo_id uuid
)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $f3$
DECLARE
  v_link json;
  v_tenant uuid;
  v_contab uuid;
  v_proc json;
  v_docs json;
  v_coments json;
BEGIN
  v_link := public._hub_contador_link_valido(p_token);
  IF v_link IS NULL THEN
    RETURN json_build_object('error', 'Link inválido ou expirado');
  END IF;
  v_tenant := (v_link->>'tenant_id')::uuid;
  v_contab := (v_link->>'contabilidade_id')::uuid;

  v_proc := (
    SELECT to_json(p2) FROM (
      SELECT p.id, p.codigo, p.tipo, p.status, p.prioridade, p.titulo, p.descricao,
             p.competencia, p.colaborador_nome, p.colaborador_cpf, p.colaborador_matricula,
             p.data_referencia, p.data_limite, p.created_at, p.updated_at
      FROM public.hub_processos p
      WHERE p.id = p_processo_id
        AND p.tenant_id = v_tenant
        AND p.contabilidade_id = v_contab
        AND p.status::text NOT IN ('rascunho', 'aguardando_documentos', 'pronto_para_envio')
      LIMIT 1
    ) p2
  );
  IF v_proc IS NULL THEN
    RETURN json_build_object('error', 'Processo não encontrado');
  END IF;

  v_docs := (
    SELECT COALESCE(json_agg(d ORDER BY d.created_at), '[]'::json)
    FROM (
      SELECT id, tipo, nome, descricao, origem, arquivo_url, arquivo_nome,
             arquivo_tamanho, arquivo_mime, status, created_at
      FROM public.hub_processo_documentos
      WHERE processo_id = p_processo_id
        AND tenant_id = v_tenant
        AND visivel_contabilidade = true
    ) d
  );

  v_coments := (
    SELECT COALESCE(json_agg(c ORDER BY c.created_at), '[]'::json)
    FROM (
      SELECT id, autor_nome, autor_perfil, conteudo, arquivo_url, arquivo_nome, created_at
      FROM public.hub_processo_comentarios
      WHERE processo_id = p_processo_id
        AND tenant_id = v_tenant
        AND eh_interno = false
    ) c
  );

  RETURN json_build_object(
    'valido', true,
    'processo', v_proc,
    'documentos', v_docs,
    'comentarios', v_coments
  );
END;
$f3$;

REVOKE EXECUTE ON FUNCTION public.obter_hub_processo_contador(text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.obter_hub_processo_contador(text, uuid) TO anon, authenticated;

-- 7) comentar_hub_processo_contador ------------------------------------------
CREATE OR REPLACE FUNCTION public.comentar_hub_processo_contador(
  p_token text,
  p_processo_id uuid,
  p_conteudo text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $f4$
DECLARE
  v_link json;
  v_tenant uuid;
  v_contab uuid;
  v_autor text;
  v_ip text;
  v_conteudo text := NULLIF(TRIM(COALESCE(p_conteudo, '')), '');
BEGIN
  v_link := public._hub_contador_link_valido(p_token);
  IF v_link IS NULL THEN
    RETURN json_build_object('error', 'Link inválido ou expirado');
  END IF;
  v_tenant := (v_link->>'tenant_id')::uuid;
  v_contab := (v_link->>'contabilidade_id')::uuid;

  IF v_conteudo IS NULL THEN
    RETURN json_build_object('error', 'Escreva o comentário');
  END IF;
  v_conteudo := left(v_conteudo, 5000);

  IF NOT (SELECT EXISTS (
    SELECT 1 FROM public.hub_processos p
    WHERE p.id = p_processo_id
      AND p.tenant_id = v_tenant
      AND p.contabilidade_id = v_contab
      AND p.status::text NOT IN ('rascunho', 'aguardando_documentos', 'pronto_para_envio')
  )) THEN
    RETURN json_build_object('error', 'Processo não encontrado');
  END IF;

  v_autor := COALESCE(NULLIF(v_link->>'rotulo', ''),
                      (SELECT nome FROM public.hub_contabilidades WHERE id = v_contab),
                      'Contabilidade');

  BEGIN
    v_ip := coalesce(
      split_part(current_setting('request.headers', true)::json->>'x-forwarded-for', ',', 1),
      current_setting('request.headers', true)::json->>'cf-connecting-ip');
  EXCEPTION WHEN OTHERS THEN v_ip := NULL; END;

  INSERT INTO public.hub_processo_comentarios
    (tenant_id, processo_id, autor_nome, autor_perfil, conteudo, eh_interno)
  VALUES
    (v_tenant, p_processo_id, v_autor, 'contador', v_conteudo, false);

  INSERT INTO public.hub_processo_historico
    (tenant_id, processo_id, acao, usuario_nome, perfil, descricao, ip)
  VALUES
    (v_tenant, p_processo_id, 'comentario_contador', v_autor, 'contador',
     'Comentário da contabilidade pelo canal externo', v_ip);

  RETURN json_build_object('success', true);
END;
$f4$;

REVOKE EXECUTE ON FUNCTION public.comentar_hub_processo_contador(text, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.comentar_hub_processo_contador(text, uuid, text) TO anon, authenticated;

-- 8) mudar_status_hub_processo_contador (só o conjunto permitido ao contador) --
CREATE OR REPLACE FUNCTION public.mudar_status_hub_processo_contador(
  p_token text,
  p_processo_id uuid,
  p_novo_status text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $f5$
DECLARE
  v_link json;
  v_tenant uuid;
  v_contab uuid;
  v_autor text;
  v_ip text;
  v_atual text;
BEGIN
  v_link := public._hub_contador_link_valido(p_token);
  IF v_link IS NULL THEN
    RETURN json_build_object('error', 'Link inválido ou expirado');
  END IF;
  v_tenant := (v_link->>'tenant_id')::uuid;
  v_contab := (v_link->>'contabilidade_id')::uuid;

  IF p_novo_status NOT IN (
    'recebido_contabilidade', 'em_analise', 'pendente_complementacao',
    'processado', 'documentos_devolvidos'
  ) THEN
    RETURN json_build_object('error', 'Transição de status não permitida para a contabilidade');
  END IF;

  v_atual := (
    SELECT p.status::text FROM public.hub_processos p
    WHERE p.id = p_processo_id
      AND p.tenant_id = v_tenant
      AND p.contabilidade_id = v_contab
      AND p.status::text NOT IN ('rascunho', 'aguardando_documentos', 'pronto_para_envio')
    LIMIT 1
  );
  IF v_atual IS NULL THEN
    RETURN json_build_object('error', 'Processo não encontrado');
  END IF;

  v_autor := COALESCE(NULLIF(v_link->>'rotulo', ''),
                      (SELECT nome FROM public.hub_contabilidades WHERE id = v_contab),
                      'Contabilidade');

  BEGIN
    v_ip := coalesce(
      split_part(current_setting('request.headers', true)::json->>'x-forwarded-for', ',', 1),
      current_setting('request.headers', true)::json->>'cf-connecting-ip');
  EXCEPTION WHEN OTHERS THEN v_ip := NULL; END;

  UPDATE public.hub_processos
  SET status = p_novo_status::public.hub_processo_status, updated_at = now()
  WHERE id = p_processo_id
    AND tenant_id = v_tenant
    AND contabilidade_id = v_contab;

  INSERT INTO public.hub_processo_historico
    (tenant_id, processo_id, acao, usuario_nome, perfil, status_anterior, status_novo, descricao, ip)
  VALUES
    (v_tenant, p_processo_id, 'status_alterado_contador', v_autor, 'contador',
     v_atual::public.hub_processo_status, p_novo_status::public.hub_processo_status,
     'Status alterado pela contabilidade pelo canal externo', v_ip);

  RETURN json_build_object('success', true, 'status', p_novo_status);
END;
$f5$;

REVOKE EXECUTE ON FUNCTION public.mudar_status_hub_processo_contador(text, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mudar_status_hub_processo_contador(text, uuid, text) TO anon, authenticated;

-- 9) registrar_documento_contador (devolutiva da contabilidade) --------------
CREATE OR REPLACE FUNCTION public.registrar_documento_contador(
  p_token text,
  p_processo_id uuid,
  p_nome text,
  p_arquivo_url text,
  p_arquivo_nome text DEFAULT NULL,
  p_tipo text DEFAULT 'outros',
  p_arquivo_tamanho integer DEFAULT NULL,
  p_arquivo_mime text DEFAULT NULL,
  p_descricao text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $f6$
DECLARE
  v_link json;
  v_tenant uuid;
  v_contab uuid;
  v_autor text;
  v_ip text;
  v_nome text := NULLIF(TRIM(COALESCE(p_nome, '')), '');
  v_tipo text := 'outros';
BEGIN
  v_link := public._hub_contador_link_valido(p_token);
  IF v_link IS NULL THEN
    RETURN json_build_object('error', 'Link inválido ou expirado');
  END IF;
  v_tenant := (v_link->>'tenant_id')::uuid;
  v_contab := (v_link->>'contabilidade_id')::uuid;

  IF v_nome IS NULL THEN
    RETURN json_build_object('error', 'Informe o nome do documento');
  END IF;
  IF p_arquivo_url IS NULL OR TRIM(p_arquivo_url) = '' THEN
    RETURN json_build_object('error', 'Arquivo ausente');
  END IF;

  IF NOT (SELECT EXISTS (
    SELECT 1 FROM public.hub_processos p
    WHERE p.id = p_processo_id
      AND p.tenant_id = v_tenant
      AND p.contabilidade_id = v_contab
      AND p.status::text NOT IN ('rascunho', 'aguardando_documentos', 'pronto_para_envio')
  )) THEN
    RETURN json_build_object('error', 'Processo não encontrado');
  END IF;

  IF p_tipo IS NOT NULL AND EXISTS (
    SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname = 'hub_doc_tipo' AND e.enumlabel = p_tipo
  ) THEN
    v_tipo := p_tipo;
  END IF;

  v_autor := COALESCE(NULLIF(v_link->>'rotulo', ''),
                      (SELECT nome FROM public.hub_contabilidades WHERE id = v_contab),
                      'Contabilidade');

  BEGIN
    v_ip := coalesce(
      split_part(current_setting('request.headers', true)::json->>'x-forwarded-for', ',', 1),
      current_setting('request.headers', true)::json->>'cf-connecting-ip');
  EXCEPTION WHEN OTHERS THEN v_ip := NULL; END;

  INSERT INTO public.hub_processo_documentos
    (tenant_id, processo_id, tipo, nome, descricao, origem,
     arquivo_url, arquivo_nome, arquivo_tamanho, arquivo_mime,
     visivel_contabilidade, status, enviado_por)
  VALUES
    (v_tenant, p_processo_id, v_tipo::public.hub_doc_tipo, left(v_nome, 200),
     NULLIF(TRIM(COALESCE(p_descricao, '')), ''), 'devolutiva_contabilidade',
     p_arquivo_url, COALESCE(NULLIF(TRIM(COALESCE(p_arquivo_nome, '')), ''), v_nome),
     p_arquivo_tamanho, p_arquivo_mime,
     true, 'recebido', v_autor);

  INSERT INTO public.hub_processo_historico
    (tenant_id, processo_id, acao, usuario_nome, perfil, descricao, ip)
  VALUES
    (v_tenant, p_processo_id, 'documento_devolvido_contador', v_autor, 'contador',
     'Documento enviado pela contabilidade: ' || left(v_nome, 200), v_ip);

  RETURN json_build_object('success', true);
END;
$f6$;

REVOKE EXECUTE ON FUNCTION public.registrar_documento_contador(text, uuid, text, text, text, text, integer, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.registrar_documento_contador(text, uuid, text, text, text, text, integer, text, text) TO anon, authenticated;

-- 10) Cerca do QA: protege a tabela nova nos ambientes que têm o cercado
-- (staging/homologação). Em produção, onde o cercado não existe, não faz nada.
DO $cerca$
BEGIN
  IF to_regprocedure('public.qa_instalar_cercas()') IS NOT NULL THEN
    PERFORM public.qa_instalar_cercas();
  END IF;
END $cerca$;

-- 11) CONFERÊNCIA (único resultado exibido): estrutura e RPCs criadas ---------
SELECT
  to_regclass('public.hub_contador_links') IS NOT NULL AS tabela_links_ok,
  EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='uq_hub_contador_links_tenant_contab') AS indice_unico_ok,
  EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='hub_processo_documentos' AND column_name='visivel_contabilidade') AS coluna_visivel_ok,
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname IN (
      'buscar_contador_acesso_por_token',
      'listar_hub_processos_contador',
      'obter_hub_processo_contador',
      'comentar_hub_processo_contador',
      'mudar_status_hub_processo_contador',
      'registrar_documento_contador')) AS rpcs_ok,
  has_function_privilege('anon', 'public.buscar_contador_acesso_por_token(text)', 'EXECUTE') AS anon_executa_rpc,
  has_function_privilege('anon', 'public._hub_contador_link_valido(text)', 'EXECUTE') AS anon_executa_resolver_DEVE_SER_FALSE;
