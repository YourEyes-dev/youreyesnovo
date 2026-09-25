-- ============================================================================
-- ENTREGA: Ouvidoria — link público (sem login) + acompanhamento por protocolo
-- Cole INTEIRO no SQL Editor (roda em uma única transação). Idempotente.
--
-- Cria: colunas novas em public.ouvidoria (origem, empresa_id, autor_cpf,
-- protocolo), a tabela public.ouvidoria_links (um link por tenant) com RLS, e as
-- RPCs SECURITY DEFINER liberadas para anon. Só CRIA coisa nova (não altera nem
-- apaga dado existente), então não precisa de backup.
--
-- NOTAS de compatibilidade com o SQL Editor (o db push/psql não precisa delas):
--  1) Cada função usa marca de aspas-dólar PRÓPRIA (f1..f7; pol no DO).
--  2) Nenhuma função grava resultado direto em variável por consulta (a forma que
--     o auxiliar de RLS do SQL Editor confundia com "tabela nova", injetando
--     ALTER TABLE dentro da função e quebrando o corpo). Aqui as funções atribuem
--     por subconsulta escalar (v := (SELECT ...)) e por to_json(...).
-- ============================================================================

SET lock_timeout = '10s';

-- 1) Colunas novas em public.ouvidoria (aditivas) ----------------------------
ALTER TABLE public.ouvidoria ADD COLUMN IF NOT EXISTS origem text NOT NULL DEFAULT 'app';
ALTER TABLE public.ouvidoria ADD COLUMN IF NOT EXISTS empresa_id uuid;
ALTER TABLE public.ouvidoria ADD COLUMN IF NOT EXISTS autor_cpf text;
ALTER TABLE public.ouvidoria ADD COLUMN IF NOT EXISTS protocolo text;

CREATE UNIQUE INDEX IF NOT EXISTS uq_ouvidoria_protocolo_por_tenant
  ON public.ouvidoria(tenant_id, protocolo)
  WHERE protocolo IS NOT NULL;

-- 2) Tabela do link público (um por tenant) ----------------------------------
-- A criação da tabela roda via EXECUTE dentro de um DO. Assim o auxiliar de RLS
-- do SQL Editor não "vê" uma tabela nova no texto e não injeta ALTER TABLE dentro
-- das funções deste script (era a causa dos erros ao colar). No db push/psql é
-- indiferente.
DO $setup$
BEGIN
  IF to_regclass('public.ouvidoria_links') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.ouvidoria_links (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE, token text NOT NULL UNIQUE, ativo boolean NOT NULL DEFAULT true, data_expiracao timestamptz, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now())';
  END IF;
END $setup$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_ouvidoria_links_por_tenant
  ON public.ouvidoria_links(tenant_id);

ALTER TABLE public.ouvidoria_links ENABLE ROW LEVEL SECURITY;

DO $pol$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='ouvidoria_links' AND policyname='ouvidoria_links_select') THEN
    CREATE POLICY "ouvidoria_links_select" ON public.ouvidoria_links
      FOR SELECT TO authenticated USING (tenant_id = public.get_user_tenant_id());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='ouvidoria_links' AND policyname='ouvidoria_links_insert') THEN
    CREATE POLICY "ouvidoria_links_insert" ON public.ouvidoria_links
      FOR INSERT TO authenticated
      WITH CHECK (tenant_id = public.get_user_tenant_id() AND public.has_minimum_role(auth.uid(), 'admin'::public.app_role));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='ouvidoria_links' AND policyname='ouvidoria_links_update') THEN
    CREATE POLICY "ouvidoria_links_update" ON public.ouvidoria_links
      FOR UPDATE TO authenticated
      USING (tenant_id = public.get_user_tenant_id() AND public.has_minimum_role(auth.uid(), 'admin'::public.app_role))
      WITH CHECK (tenant_id = public.get_user_tenant_id() AND public.has_minimum_role(auth.uid(), 'admin'::public.app_role));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='ouvidoria_links' AND policyname='ouvidoria_links_delete') THEN
    CREATE POLICY "ouvidoria_links_delete" ON public.ouvidoria_links
      FOR DELETE TO authenticated
      USING (tenant_id = public.get_user_tenant_id() AND public.has_minimum_role(auth.uid(), 'admin'::public.app_role));
  END IF;
END $pol$;

DROP TRIGGER IF EXISTS trg_ouvidoria_links_updated_at ON public.ouvidoria_links;
CREATE TRIGGER trg_ouvidoria_links_updated_at
  BEFORE UPDATE ON public.ouvidoria_links
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- 3) Nome de exibição da empresa a partir do tenant --------------------------
CREATE OR REPLACE FUNCTION public._ouvidoria_nome_empresa(p_tenant_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $f1$
  SELECT COALESCE(
    (SELECT NULLIF(TRIM(COALESCE(ec.nome_fantasia, ec.razao_social)), '')
     FROM public.empresa_cadastro ec
     WHERE ec.tenant_id = p_tenant_id
     ORDER BY ec.created_at NULLS LAST
     LIMIT 1),
    'sua empresa'
  );
$f1$;

-- 4) Resolve colaborador por CPF (declaratório) ------------------------------
CREATE OR REPLACE FUNCTION public._ouvidoria_resolver_colaborador_cpf(p_tenant_id uuid, p_cpf text)
RETURNS TABLE (nome text, empresa_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $f2$
  SELECT a.nome_completo, a.empresa_id
  FROM public.admissoes a
  WHERE a.tenant_id = p_tenant_id
    AND regexp_replace(COALESCE(a.cpf,''), '\D', '', 'g') = regexp_replace(COALESCE(p_cpf,''), '\D', '', 'g')
    AND length(regexp_replace(COALESCE(p_cpf,''), '\D', '', 'g')) = 11
    AND a.status = 'concluido'
    AND COALESCE(a.inativo, false) = false
  ORDER BY a.data_admissao DESC NULLS LAST
  LIMIT 1;
$f2$;

REVOKE EXECUTE ON FUNCTION public._ouvidoria_nome_empresa(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public._ouvidoria_resolver_colaborador_cpf(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._ouvidoria_nome_empresa(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public._ouvidoria_resolver_colaborador_cpf(uuid, text) TO authenticated;

-- 5) buscar_ouvidoria_link_por_token -----------------------------------------
CREATE OR REPLACE FUNCTION public.buscar_ouvidoria_link_por_token(p_token text)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $f3$
DECLARE
  v_tenant uuid;
BEGIN
  v_tenant := (
    SELECT tenant_id FROM public.ouvidoria_links
    WHERE token = p_token AND ativo = true
      AND (data_expiracao IS NULL OR data_expiracao > now())
    LIMIT 1
  );
  IF v_tenant IS NULL THEN
    RETURN json_build_object('error', 'Link inválido ou expirado');
  END IF;
  RETURN json_build_object('valido', true, 'empresa_nome', public._ouvidoria_nome_empresa(v_tenant));
END;
$f3$;

REVOKE EXECUTE ON FUNCTION public.buscar_ouvidoria_link_por_token(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.buscar_ouvidoria_link_por_token(text) TO anon, authenticated;

-- 6) buscar_colaborador_ouvidoria_por_cpf ------------------------------------
CREATE OR REPLACE FUNCTION public.buscar_colaborador_ouvidoria_por_cpf(p_token text, p_cpf text)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $f4$
DECLARE
  v_tenant uuid;
  v_colab json;
BEGIN
  v_tenant := (
    SELECT tenant_id FROM public.ouvidoria_links
    WHERE token = p_token AND ativo = true
      AND (data_expiracao IS NULL OR data_expiracao > now())
    LIMIT 1
  );
  IF v_tenant IS NULL THEN
    RETURN json_build_object('error', 'Link inválido ou expirado');
  END IF;

  v_colab := (
    SELECT json_build_object('nome', nome, 'empresa_id', empresa_id)
    FROM public._ouvidoria_resolver_colaborador_cpf(v_tenant, p_cpf)
  );
  IF v_colab IS NULL THEN
    RETURN json_build_object('encontrado', false);
  END IF;

  RETURN json_build_object(
    'encontrado', true,
    'nome', v_colab->>'nome',
    'empresa_id', v_colab->>'empresa_id',
    'empresa_nome', public._ouvidoria_nome_empresa(v_tenant)
  );
END;
$f4$;

REVOKE EXECUTE ON FUNCTION public.buscar_colaborador_ouvidoria_por_cpf(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.buscar_colaborador_ouvidoria_por_cpf(text, text) TO anon, authenticated;

-- 7) registrar_manifestacao_externa ------------------------------------------
CREATE OR REPLACE FUNCTION public.registrar_manifestacao_externa(
  p_token text,
  p_tipo text,
  p_assunto text,
  p_mensagem text,
  p_anonimo boolean,
  p_cpf text DEFAULT NULL,
  p_nome text DEFAULT NULL,
  p_email text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $f5$
DECLARE
  v_tenant uuid;
  v_rot json;
  v_colab json;
  v_assunto text := NULLIF(TRIM(COALESCE(p_assunto,'')), '');
  v_mensagem text := NULLIF(TRIM(COALESCE(p_mensagem,'')), '');
  v_cpf_digits text := regexp_replace(COALESCE(p_cpf,''), '\D', '', 'g');
  v_nome text := NULLIF(TRIM(COALESCE(p_nome,'')), '');
  v_email text := NULLIF(TRIM(COALESCE(p_email,'')), '');
  v_empresa_id uuid;
  v_protocolo text;
  v_tentativa int := 0;
BEGIN
  v_tenant := (
    SELECT tenant_id FROM public.ouvidoria_links
    WHERE token = p_token AND ativo = true
      AND (data_expiracao IS NULL OR data_expiracao > now())
    LIMIT 1
  );
  IF v_tenant IS NULL THEN
    RETURN json_build_object('error', 'Link inválido ou expirado');
  END IF;

  IF p_tipo NOT IN ('sugestao','reclamacao','denuncia','elogio','duvida') THEN
    RETURN json_build_object('error', 'Tipo de manifestação inválido');
  END IF;
  IF v_assunto IS NULL OR v_mensagem IS NULL THEN
    RETURN json_build_object('error', 'Preencha o assunto e a mensagem');
  END IF;
  v_assunto := left(v_assunto, 200);
  v_mensagem := left(v_mensagem, 5000);

  IF COALESCE(p_anonimo, false) = false THEN
    IF length(v_cpf_digits) = 11 THEN
      v_colab := (
        SELECT json_build_object('nome', nome, 'empresa_id', empresa_id)
        FROM public._ouvidoria_resolver_colaborador_cpf(v_tenant, v_cpf_digits)
      );
      IF v_colab IS NOT NULL THEN
        v_empresa_id := (v_colab->>'empresa_id')::uuid;
        IF v_nome IS NULL THEN v_nome := v_colab->>'nome'; END IF;
      END IF;
    END IF;
  ELSE
    v_cpf_digits := NULL;
    v_nome := NULL;
    v_email := NULL;
    v_empresa_id := NULL;
  END IF;

  v_rot := (
    SELECT to_json(t) FROM (
      SELECT responsavel_id, responsavel_nome, departamento_responsavel
      FROM public.ouvidoria_roteamento
      WHERE tenant_id = v_tenant AND tipo_manifestacao = p_tipo AND ativo = true
      LIMIT 1
    ) t
  );

  LOOP
    v_tentativa := v_tentativa + 1;
    v_protocolo := 'OUV-' || to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'YYYYMMDD') || '-' ||
                   upper(substring(encode(gen_random_bytes(4), 'hex') from 1 for 6));
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.ouvidoria WHERE tenant_id = v_tenant AND protocolo = v_protocolo
    );
    IF v_tentativa >= 8 THEN
      v_protocolo := 'OUV-' || upper(substring(encode(gen_random_bytes(8), 'hex') from 1 for 12));
      EXIT;
    END IF;
  END LOOP;

  INSERT INTO public.ouvidoria (
    tenant_id, tipo, assunto, mensagem, anonimo,
    autor_id, autor_nome, autor_email, autor_cpf, empresa_id,
    status, prioridade, anexos, origem, protocolo,
    responsavel_id, responsavel_nome, departamento_destino
  ) VALUES (
    v_tenant, p_tipo, v_assunto, v_mensagem, COALESCE(p_anonimo, false),
    NULL, v_nome, v_email, v_cpf_digits, v_empresa_id,
    'pendente', 'normal', '[]'::jsonb, 'link_publico', v_protocolo,
    (v_rot->>'responsavel_id')::uuid, v_rot->>'responsavel_nome', v_rot->>'departamento_responsavel'
  );

  RETURN json_build_object('success', true, 'protocolo', v_protocolo);
END;
$f5$;

REVOKE EXECUTE ON FUNCTION public.registrar_manifestacao_externa(text, text, text, text, boolean, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.registrar_manifestacao_externa(text, text, text, text, boolean, text, text, text) TO anon, authenticated;

-- 8) buscar_ouvidoria_link_por_ponto_token -----------------------------------
CREATE OR REPLACE FUNCTION public.buscar_ouvidoria_link_por_ponto_token(p_ponto_token text)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $f6$
DECLARE
  v_tenant uuid;
  v_token text;
BEGIN
  v_tenant := (
    SELECT tenant_id FROM public.ponto_links
    WHERE token = p_ponto_token AND ativo = true
      AND (data_expiracao IS NULL OR data_expiracao > now())
    LIMIT 1
  );
  IF v_tenant IS NULL THEN
    RETURN json_build_object('encontrado', false);
  END IF;

  v_token := (
    SELECT token FROM public.ouvidoria_links
    WHERE tenant_id = v_tenant AND ativo = true
      AND (data_expiracao IS NULL OR data_expiracao > now())
    LIMIT 1
  );
  IF v_token IS NULL THEN
    RETURN json_build_object('encontrado', false);
  END IF;

  RETURN json_build_object('encontrado', true, 'token', v_token);
END;
$f6$;

REVOKE EXECUTE ON FUNCTION public.buscar_ouvidoria_link_por_ponto_token(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.buscar_ouvidoria_link_por_ponto_token(text) TO anon, authenticated;

-- 9) consultar_manifestacao_ouvidoria: acompanhamento por protocolo -----------
CREATE OR REPLACE FUNCTION public.consultar_manifestacao_ouvidoria(p_token text, p_protocolo text)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $f7$
DECLARE
  v_tenant uuid;
  v_m json;
BEGIN
  v_tenant := (
    SELECT tenant_id FROM public.ouvidoria_links
    WHERE token = p_token AND ativo = true
      AND (data_expiracao IS NULL OR data_expiracao > now())
    LIMIT 1
  );
  IF v_tenant IS NULL THEN
    RETURN json_build_object('error', 'Link inválido ou expirado');
  END IF;

  v_m := (
    SELECT to_json(t) FROM (
      SELECT tipo, assunto, status, resposta, respondido_em, created_at
      FROM public.ouvidoria
      WHERE tenant_id = v_tenant AND protocolo = upper(TRIM(COALESCE(p_protocolo, '')))
      LIMIT 1
    ) t
  );
  IF v_m IS NULL THEN
    RETURN json_build_object('encontrado', false);
  END IF;

  RETURN json_build_object(
    'encontrado', true,
    'tipo', v_m->>'tipo',
    'assunto', v_m->>'assunto',
    'status', v_m->>'status',
    'resposta', v_m->>'resposta',
    'respondido_em', v_m->>'respondido_em',
    'created_at', v_m->>'created_at'
  );
END;
$f7$;

REVOKE EXECUTE ON FUNCTION public.consultar_manifestacao_ouvidoria(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.consultar_manifestacao_ouvidoria(text, text) TO anon, authenticated;

-- 10) CONFERÊNCIA (único resultado exibido): confirma estrutura e RPCs criadas.
SELECT
  to_regclass('public.ouvidoria_links') IS NOT NULL AS tabela_links_ok,
  (SELECT count(*) FROM information_schema.columns
    WHERE table_schema='public' AND table_name='ouvidoria'
      AND column_name IN ('origem','empresa_id','autor_cpf','protocolo')) AS colunas_ouvidoria_ok,
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname IN (
      'buscar_ouvidoria_link_por_token',
      'buscar_colaborador_ouvidoria_por_cpf',
      'registrar_manifestacao_externa',
      'buscar_ouvidoria_link_por_ponto_token',
      'consultar_manifestacao_ouvidoria')) AS rpcs_ok;
