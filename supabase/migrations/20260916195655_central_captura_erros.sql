-- =========================================================
-- Central de Controle de Clientes — eixo técnico: captura de erros
--
-- Primeira entrega do documento de requisitos v1.0 (seções 3, 8, 19 e 20).
-- O sistema passa a registrar o que quebra na tela do cliente, com contexto
-- suficiente para corrigir, e SEM carregar dado pessoal junto.
--
-- Decisões que governam este arquivo:
--   RN-001 · nenhuma escrita direta: a tabela não tem política de INSERT.
--            Quem grava é a função registrar_evento_erro (SECURITY DEFINER).
--   RN-002 · mascaramento ANTES de gravar (mascarar_pii): CPF, CNPJ, e-mail,
--            telefone, sequência longa de dígitos e valores de campos de
--            segredo (senha, token, chave) nunca chegam ao disco em claro.
--   RN-003 · o usuário entra pseudonimizado: um hash com sal próprio do
--            ambiente, que não volta para o e-mail nem para o nome.
--   RN-005 · erros iguais agrupam por "impressão digital" em um incidente.
--   RN-012 · expurgo automático: evento bruto vive 90 dias.
--   RN-013 · limite de ingestão por usuário (anti-enxurrada).
--   RN-014 · leitura só de superadmin, por RLS.
--
-- Fora do escopo desta entrega (próximas): motor de regras, canais de
-- alerta, "revelar" com auditoria, health score e sinais de uso.
-- =========================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------
-- 1) Mascaramento de dado pessoal (roda na ingestão)
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.mascarar_pii(p_texto text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $mascara$
  SELECT CASE WHEN p_texto IS NULL THEN NULL ELSE
    regexp_replace(
    regexp_replace(
    regexp_replace(
    regexp_replace(
    regexp_replace(
    regexp_replace(
      p_texto,
      -- valor de campo de segredo em JSON ou querystring
      '("?(senha|password|token|authorization|api[_-]?key|secret|chave)"?\s*[:=]\s*"?)([^",&}\s]+)',
      '\1[oculto]', 'gi'),
      -- e-mail
      '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[email]', 'g'),
      -- CNPJ
      '\m\d{2}\.?\d{3}\.?\d{3}/?\d{4}-?\d{2}\M', '[cnpj]', 'g'),
      -- CPF
      '\m\d{3}\.?\d{3}\.?\d{3}-?\d{2}\M', '[cpf]', 'g'),
      -- telefone brasileiro, com ou sem DDI/DDD
      '(\+?55\s?)?\(?\d{2}\)?\s?9?\d{4}[-\s]?\d{4}\M', '[telefone]', 'g'),
      -- qualquer sequência longa de dígitos que tenha escapado
      '\m\d{11,}\M', '[numero]', 'g')
  END
$mascara$;

COMMENT ON FUNCTION public.mascarar_pii(text) IS
  'Mascara dado pessoal em texto livre antes de gravar evento de erro (LGPD, RN-002). Conservadora de propósito: prefere mascarar demais a deixar passar.';

-- ---------------------------------------------------------
-- 2) Sal do pseudônimo (por ambiente, nunca no código)
-- ---------------------------------------------------------
INSERT INTO public.app_config (chave, valor)
VALUES ('pseudonimo_sal', encode(public.gen_random_bytes(32), 'hex'))
ON CONFLICT (chave) DO NOTHING;

CREATE OR REPLACE FUNCTION public.pseudonimo_usuario(p_uid uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $pseudo$
  SELECT CASE WHEN p_uid IS NULL THEN NULL ELSE
    left(encode(public.digest(p_uid::text || COALESCE(
      (SELECT valor FROM public.app_config WHERE chave = 'pseudonimo_sal'), 'sem-sal'
    ), 'sha256'), 'hex'), 16)
  END
$pseudo$;

COMMENT ON FUNCTION public.pseudonimo_usuario(uuid) IS
  'Apelido estável do usuário dentro dos eventos (RN-003): permite dizer "o mesmo usuário de novo" sem guardar quem ele é. O sal vive no app_config de cada ambiente.';

-- ---------------------------------------------------------
-- 3) Incidente (agrupamento) e evento bruto
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.evento_incidente (
  fingerprint       text PRIMARY KEY,
  titulo            text NOT NULL,
  modulo            text,
  tipo              text,
  severidade        text NOT NULL DEFAULT 'media'
                      CHECK (severidade IN ('critica', 'alta', 'media', 'baixa')),
  status            text NOT NULL DEFAULT 'novo'
                      CHECK (status IN ('novo', 'em_analise', 'resolvido', 'fechado')),
  ocorrencias       integer NOT NULL DEFAULT 0,
  primeiro_visto    timestamptz NOT NULL DEFAULT now(),
  ultimo_visto      timestamptz NOT NULL DEFAULT now(),
  resolvido_em      timestamptz,
  observacao        text
);

CREATE TABLE IF NOT EXISTS public.evento_erro (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fingerprint       text NOT NULL REFERENCES public.evento_incidente(fingerprint) ON DELETE CASCADE,
  ambiente          text NOT NULL DEFAULT 'desconhecido',
  tenant_id         uuid,
  origem            text NOT NULL DEFAULT 'frontend' CHECK (origem IN ('frontend', 'backend')),
  usuario_pseudo    text,
  modulo            text,
  rota              text,
  acao              text,
  tipo              text,
  mensagem          text,
  stack             text,
  breadcrumbs       jsonb NOT NULL DEFAULT '[]'::jsonb,
  severidade        text NOT NULL DEFAULT 'media'
                      CHECK (severidade IN ('critica', 'alta', 'media', 'baixa')),
  versao_app        text,
  navegador_os      text,
  ocorrido_em       timestamptz NOT NULL DEFAULT now(),
  recebido_em       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_evento_erro_recebido  ON public.evento_erro (recebido_em DESC);
CREATE INDEX IF NOT EXISTS idx_evento_erro_fingerprint ON public.evento_erro (fingerprint, recebido_em DESC);
CREATE INDEX IF NOT EXISTS idx_evento_erro_tenant    ON public.evento_erro (tenant_id, recebido_em DESC);
CREATE INDEX IF NOT EXISTS idx_evento_incidente_vivo ON public.evento_incidente (ultimo_visto DESC)
  WHERE status IN ('novo', 'em_analise');

COMMENT ON TABLE public.evento_erro IS
  'Erro capturado no cliente, já mascarado (LGPD). Gravado somente por registrar_evento_erro; leitura só de superadmin.';
COMMENT ON TABLE public.evento_incidente IS
  'Erros iguais agrupados por impressão digital (RN-005): a fila de trabalho da equipe.';

-- ---------------------------------------------------------
-- 4) RLS: leitura de superadmin; escrita, só pela função
-- ---------------------------------------------------------
ALTER TABLE public.evento_erro      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.evento_incidente ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.evento_erro, public.evento_incidente FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.evento_erro, public.evento_incidente TO authenticated;

DROP POLICY IF EXISTS "Superadmin le evento_erro" ON public.evento_erro;
CREATE POLICY "Superadmin le evento_erro" ON public.evento_erro
  FOR SELECT TO authenticated USING (public.is_superadmin(auth.uid()));

DROP POLICY IF EXISTS "Superadmin le evento_incidente" ON public.evento_incidente;
CREATE POLICY "Superadmin le evento_incidente" ON public.evento_incidente
  FOR SELECT TO authenticated USING (public.is_superadmin(auth.uid()));

DROP POLICY IF EXISTS "Superadmin triagem evento_incidente" ON public.evento_incidente;
CREATE POLICY "Superadmin triagem evento_incidente" ON public.evento_incidente
  FOR UPDATE TO authenticated
  USING (public.is_superadmin(auth.uid()))
  WITH CHECK (public.is_superadmin(auth.uid()));

-- Sem política de INSERT em evento_erro, de propósito (RN-001).

-- ---------------------------------------------------------
-- 5) Ingestão: a ÚNICA porta de escrita
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.registrar_evento_erro(p_evento jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $ingest$
DECLARE
  v_uid         uuid := auth.uid();
  v_tenant      uuid;
  v_recentes    int;
  v_mensagem    text;
  v_stack       text;
  v_modulo      text;
  v_rota        text;
  v_acao        text;
  v_tipo        text;
  v_sev         text;
  v_fingerprint text;
  v_titulo      text;
  v_assinatura  text;
BEGIN
  -- Só origem autenticada da aplicação (seção 3.4 do documento).
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('gravado', false, 'motivo', 'sem_sessao');
  END IF;

  -- Anti-enxurrada (RN-013): 60 eventos por usuário por minuto.
  SELECT count(*) INTO v_recentes
  FROM public.evento_erro
  WHERE usuario_pseudo = public.pseudonimo_usuario(v_uid)
    AND recebido_em > now() - interval '1 minute';
  IF v_recentes >= 60 THEN
    RETURN jsonb_build_object('gravado', false, 'motivo', 'limite_por_minuto');
  END IF;

  v_tenant := public.current_user_tenant_id();

  -- Mascaramento ANTES de qualquer gravação (RN-002).
  v_mensagem := left(public.mascarar_pii(NULLIF(p_evento->>'mensagem', '')), 2000);
  v_stack    := left(public.mascarar_pii(NULLIF(p_evento->>'stack', '')), 8000);
  v_modulo   := left(COALESCE(NULLIF(p_evento->>'modulo', ''), 'desconhecido'), 120);
  v_rota     := left(public.mascarar_pii(NULLIF(p_evento->>'rota', '')), 300);
  v_acao     := left(public.mascarar_pii(NULLIF(p_evento->>'acao', '')), 300);
  v_tipo     := left(COALESCE(NULLIF(p_evento->>'tipo', ''), 'erro'), 120);
  v_sev      := COALESCE(NULLIF(p_evento->>'severidade', ''), 'media');
  IF v_sev NOT IN ('critica', 'alta', 'media', 'baixa') THEN v_sev := 'media'; END IF;

  IF v_mensagem IS NULL THEN
    RETURN jsonb_build_object('gravado', false, 'motivo', 'evento_sem_mensagem');
  END IF;

  -- Impressão digital: o mesmo defeito, visto muitas vezes, é UM incidente.
  -- Números, endereços e aspas saem da conta para a variação não separar iguais.
  v_assinatura := lower(regexp_replace(
                    COALESCE(split_part(v_stack, E'\n', 1), v_mensagem),
                    '[0-9]+|https?://[^\s)]+|["'']', '', 'g'));
  v_fingerprint := left(encode(public.digest(
                     v_modulo || '|' || v_tipo || '|' ||
                     lower(regexp_replace(v_mensagem, '[0-9]+', '', 'g')) || '|' || v_assinatura,
                   'sha256'), 'hex'), 32);
  v_titulo := left(v_mensagem, 200);

  INSERT INTO public.evento_incidente (fingerprint, titulo, modulo, tipo, severidade, ocorrencias)
  VALUES (v_fingerprint, v_titulo, v_modulo, v_tipo, v_sev, 1)
  ON CONFLICT (fingerprint) DO UPDATE
    SET ocorrencias  = public.evento_incidente.ocorrencias + 1,
        ultimo_visto = now(),
        -- incidente já resolvido que volta a acontecer reabre (RN-005)
        status       = CASE WHEN public.evento_incidente.status IN ('resolvido', 'fechado')
                            THEN 'novo' ELSE public.evento_incidente.status END,
        resolvido_em = CASE WHEN public.evento_incidente.status IN ('resolvido', 'fechado')
                            THEN NULL ELSE public.evento_incidente.resolvido_em END;

  INSERT INTO public.evento_erro (
    fingerprint, ambiente, tenant_id, origem, usuario_pseudo, modulo, rota, acao,
    tipo, mensagem, stack, breadcrumbs, severidade, versao_app, navegador_os, ocorrido_em
  ) VALUES (
    v_fingerprint,
    left(COALESCE(NULLIF(p_evento->>'ambiente', ''), 'desconhecido'), 40),
    v_tenant,
    CASE WHEN COALESCE(p_evento->>'origem', 'frontend') = 'backend' THEN 'backend' ELSE 'frontend' END,
    public.pseudonimo_usuario(v_uid),
    v_modulo, v_rota, v_acao, v_tipo, v_mensagem, v_stack,
    COALESCE((SELECT jsonb_agg(to_jsonb(public.mascarar_pii(x)))
              FROM jsonb_array_elements_text(
                CASE WHEN jsonb_typeof(p_evento->'breadcrumbs') = 'array'
                     THEN p_evento->'breadcrumbs' ELSE '[]'::jsonb END) AS t(x)),
             '[]'::jsonb),
    v_sev,
    left(NULLIF(p_evento->>'versao_app', ''), 60),
    left(NULLIF(p_evento->>'navegador_os', ''), 200),
    COALESCE((p_evento->>'ocorrido_em')::timestamptz, now())
  );

  RETURN jsonb_build_object('gravado', true, 'fingerprint', v_fingerprint);
EXCEPTION WHEN OTHERS THEN
  -- Telemetria nunca derruba a tela de quem está trabalhando.
  RETURN jsonb_build_object('gravado', false, 'motivo', 'erro_na_ingestao');
END
$ingest$;

REVOKE ALL ON FUNCTION public.registrar_evento_erro(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.registrar_evento_erro(jsonb) TO authenticated;

COMMENT ON FUNCTION public.registrar_evento_erro(jsonb) IS
  'Única porta de escrita de evento de erro (RN-001). Mascara dado pessoal, pseudonimiza o usuário, agrupa por impressão digital e limita a vazão por usuário.';

-- ---------------------------------------------------------
-- 6) Leitura para a tela (cross-tenant, só superadmin)
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.central_incidentes(p_limite int DEFAULT 50)
RETURNS TABLE (
  fingerprint text, titulo text, modulo text, severidade text, status text,
  ocorrencias int, clientes_afetados int, primeiro_visto timestamptz, ultimo_visto timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $inc$
  SELECT i.fingerprint, i.titulo, i.modulo, i.severidade, i.status, i.ocorrencias,
         (SELECT count(DISTINCT e.tenant_id)::int FROM public.evento_erro e
           WHERE e.fingerprint = i.fingerprint),
         i.primeiro_visto, i.ultimo_visto
  FROM public.evento_incidente i
  WHERE public.is_superadmin(auth.uid())
    AND i.status IN ('novo', 'em_analise')
  ORDER BY CASE i.severidade WHEN 'critica' THEN 0 WHEN 'alta' THEN 1
                             WHEN 'media' THEN 2 ELSE 3 END,
           i.ultimo_visto DESC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limite, 50), 200))
$inc$;

CREATE OR REPLACE FUNCTION public.central_situacao_clientes()
RETURNS TABLE (
  tenant_id uuid, nome text, colaboradores int, situacao text, erros_24h int
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $sit$
  SELECT t.id,
         t.nome,
         (SELECT count(*)::int FROM public.admissoes a
           WHERE a.tenant_id = t.id AND a.status::text = 'concluido'),
         CASE WHEN COALESCE(x.erros, 0) > 0 THEN 'erro' ELSE 'ok' END,
         COALESCE(x.erros, 0)::int
  FROM public.tenants t
  LEFT JOIN LATERAL (
    SELECT count(*) AS erros
    FROM public.evento_erro e
    WHERE e.tenant_id = t.id
      AND e.recebido_em > now() - interval '24 hours'
  ) x ON true
  WHERE public.is_superadmin(auth.uid())
    AND t.ativo IS NOT FALSE
  ORDER BY t.nome
$sit$;

CREATE OR REPLACE FUNCTION public.central_resumo()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $res$
  SELECT CASE WHEN NOT public.is_superadmin(auth.uid()) THEN '{}'::jsonb ELSE
    jsonb_build_object(
      'erros_24h', (SELECT count(*) FROM public.evento_erro
                     WHERE recebido_em > now() - interval '24 hours'),
      'incidentes_abertos', (SELECT count(*) FROM public.evento_incidente
                              WHERE status IN ('novo', 'em_analise')),
      'incidentes_criticos', (SELECT count(*) FROM public.evento_incidente
                               WHERE status IN ('novo', 'em_analise') AND severidade = 'critica'),
      'clientes_com_erro', (SELECT count(DISTINCT tenant_id) FROM public.evento_erro
                             WHERE recebido_em > now() - interval '24 hours'
                               AND tenant_id IS NOT NULL)
    )
  END
$res$;

REVOKE ALL ON FUNCTION public.central_incidentes(int)     FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.central_situacao_clientes() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.central_resumo()            FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.central_incidentes(int)     TO authenticated;
GRANT EXECUTE ON FUNCTION public.central_situacao_clientes() TO authenticated;
GRANT EXECUTE ON FUNCTION public.central_resumo()            TO authenticated;

-- ---------------------------------------------------------
-- 7) Expurgo automático (RN-012)
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.evento_erro_expurgar()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $expurgo$
DECLARE v_apagados int;
BEGIN
  DELETE FROM public.evento_erro WHERE recebido_em < now() - interval '90 days';
  GET DIAGNOSTICS v_apagados = ROW_COUNT;
  -- Incidente sem nenhum evento vivo e já resolvido também sai.
  DELETE FROM public.evento_incidente i
   WHERE i.status IN ('resolvido', 'fechado')
     AND NOT EXISTS (SELECT 1 FROM public.evento_erro e WHERE e.fingerprint = i.fingerprint);
  RETURN v_apagados;
END
$expurgo$;

COMMENT ON FUNCTION public.evento_erro_expurgar() IS
  'Retenção de 90 dias do evento bruto (RN-012). Prazo a confirmar com o DPO.';

DO $agenda$
BEGIN
  PERFORM cron.unschedule('central-expurgo-eventos');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'central-expurgo-eventos ainda não existia (%).', SQLERRM;
END
$agenda$;

DO $agenda2$
BEGIN
  PERFORM cron.schedule('central-expurgo-eventos', '20 4 * * *',
                        'SELECT public.evento_erro_expurgar()');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Não foi possível agendar o expurgo (%).', SQLERRM;
END
$agenda2$;
