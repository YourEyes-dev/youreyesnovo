-- ============================================================================
-- ENTREGA — Central de Controle: captura de erros (eixo tecnico)
--
-- Espelha a migration 20260916195655_central_captura_erros.sql (fonte da
-- verdade, ja no teste), que existe no desenvolvimento/teste mas nunca desceu
-- para homologacao e producao (passivo medido em 09/2026 pelo inventario).
--
-- O QUE ENTREGA:
--   * 2 tabelas: evento_incidente (agrupamento) e evento_erro (bruto);
--   * 4 indices; 3 politicas (leitura/triagem so superadmin, RLS);
--   * 7 funcoes: mascarar_pii, pseudonimo_usuario, registrar_evento_erro
--     (unica porta de escrita, SECURITY DEFINER), central_incidentes,
--     central_situacao_clientes, central_resumo, evento_erro_expurgar;
--   * seed do sal do pseudonimo no app_config (ON CONFLICT DO NOTHING);
--   * agendamento do expurgo de 90 dias no pg_cron (guardado).
--
-- DEPENDENCIA QUE FALTAVA EMBAIXO (conferido no inventario): homologacao e
-- producao NAO tinham os atalhos public.gen_random_bytes / public.digest que a
-- migration extensoes_base cria (o teste tem). Como as funcoes chamam
-- public.digest / public.gen_random_bytes com prefixo e SET search_path=public,
-- este script cria esses atalhos PRIMEIRO, guardados e idempotentes, iguais aos
-- do extensoes_base. Uso COM prefixo (extensions.digest) segue funcionando.
--
-- SEGURANCA: entrega ADITIVA. So cria estrutura/funcoes novas (CREATE ... IF NOT
-- EXISTS, CREATE OR REPLACE de funcoes que estao AUSENTES embaixo — conferido:
-- nenhuma delas existe hoje em homolog/prod, entao nao ha corpo a sobrescrever)
-- e semeia UMA linha de config nova (ON CONFLICT DO NOTHING). NAO altera nem
-- apaga dado existente, entao nao ha backup a fazer. Idempotente: rodar duas
-- vezes nao quebra nem duplica. Roda inteiro em UMA transacao.
--
-- CONFERENCIA: rode a query do fim como uma query SEPARADA depois — o editor do
-- Supabase costuma anexar comandos ao final do arquivo e esconder o ultimo
-- resultado. Esperada: 3 | 2 | 7 | 4 | 3 | OK.
-- ============================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------
-- 0) Atalhos public do pgcrypto (dependencia; guardados)
--    Parametros NOMEADOS de proposito (p_n / p_data / p_type), nunca posicionais:
--    o editor do Supabase conta os cifroes no texto cru para achar as aspas-dolar,
--    e um numero IMPAR deles desalinha a contagem e faz o editor inserir ; no meio
--    de um comando. Sem parametro posicional, a contagem fica PAR. Equivalem aos
--    atalhos do extensoes_base.
-- ---------------------------------------------------------
DO $ext$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE p.proname = 'gen_random_bytes' AND n.nspname = 'extensions')
     AND NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE p.proname = 'gen_random_bytes' AND n.nspname = 'public') THEN
    CREATE FUNCTION public.gen_random_bytes(p_n integer)
    RETURNS bytea LANGUAGE sql
    AS 'SELECT extensions.gen_random_bytes(p_n)';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE p.proname = 'digest' AND n.nspname = 'extensions')
     AND NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE p.proname = 'digest' AND n.nspname = 'public') THEN
    CREATE FUNCTION public.digest(p_data text, p_type text)
    RETURNS bytea LANGUAGE sql IMMUTABLE
    AS 'SELECT extensions.digest(p_data, p_type)';
    CREATE FUNCTION public.digest(p_data bytea, p_type text)
    RETURNS bytea LANGUAGE sql IMMUTABLE
    AS 'SELECT extensions.digest(p_data, p_type)';
  END IF;
END $ext$;

-- ---------------------------------------------------------
-- 1) Mascaramento de dado pessoal (roda na ingestao)
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
      '("?(senha|password|token|authorization|api[_-]?key|secret|chave)"?\s*[:=]\s*"?)([^",&}\s]+)',
      '\1[oculto]', 'gi'),
      '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[email]', 'g'),
      '\m\d{2}\.?\d{3}\.?\d{3}/?\d{4}-?\d{2}\M', '[cnpj]', 'g'),
      '\m\d{3}\.?\d{3}\.?\d{3}-?\d{2}\M', '[cpf]', 'g'),
      '(\+?55\s?)?\(?\d{2}\)?\s?9?\d{4}[-\s]?\d{4}\M', '[telefone]', 'g'),
      '\m\d{11,}\M', '[numero]', 'g')
  END
$mascara$;

COMMENT ON FUNCTION public.mascarar_pii(text) IS
  'Mascara dado pessoal em texto livre antes de gravar evento de erro (LGPD, RN-002). Conservadora de proposito: prefere mascarar demais a deixar passar.';

-- ---------------------------------------------------------
-- 2) Sal do pseudonimo (por ambiente, nunca no codigo)
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
  'Apelido estavel do usuario dentro dos eventos (RN-003): permite dizer "o mesmo usuario de novo" sem guardar quem ele e. O sal vive no app_config de cada ambiente.';

-- ---------------------------------------------------------
-- 3) Incidente (agrupamento) e evento bruto + RLS literal
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
ALTER TABLE public.evento_incidente ENABLE ROW LEVEL SECURITY;

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
ALTER TABLE public.evento_erro ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_evento_erro_recebido  ON public.evento_erro (recebido_em DESC);
CREATE INDEX IF NOT EXISTS idx_evento_erro_fingerprint ON public.evento_erro (fingerprint, recebido_em DESC);
CREATE INDEX IF NOT EXISTS idx_evento_erro_tenant    ON public.evento_erro (tenant_id, recebido_em DESC);
CREATE INDEX IF NOT EXISTS idx_evento_incidente_vivo ON public.evento_incidente (ultimo_visto DESC)
  WHERE status IN ('novo', 'em_analise');

COMMENT ON TABLE public.evento_erro IS
  'Erro capturado no cliente, ja mascarado (LGPD). Gravado somente por registrar_evento_erro; leitura so de superadmin.';
COMMENT ON TABLE public.evento_incidente IS
  'Erros iguais agrupados por impressao digital (RN-005): a fila de trabalho da equipe.';

-- ---------------------------------------------------------
-- 4) RLS: leitura de superadmin; escrita so pela funcao
-- ---------------------------------------------------------
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

-- Sem politica de INSERT em evento_erro, de proposito (RN-001).

-- ---------------------------------------------------------
-- 5) Ingestao: a UNICA porta de escrita
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
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('gravado', false, 'motivo', 'sem_sessao');
  END IF;

  SELECT count(*) INTO v_recentes
  FROM public.evento_erro
  WHERE usuario_pseudo = public.pseudonimo_usuario(v_uid)
    AND recebido_em > now() - interval '1 minute';
  IF v_recentes >= 60 THEN
    RETURN jsonb_build_object('gravado', false, 'motivo', 'limite_por_minuto');
  END IF;

  v_tenant := public.current_user_tenant_id();

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
  RETURN jsonb_build_object('gravado', false, 'motivo', 'erro_na_ingestao');
END
$ingest$;

REVOKE ALL ON FUNCTION public.registrar_evento_erro(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.registrar_evento_erro(jsonb) TO authenticated;

COMMENT ON FUNCTION public.registrar_evento_erro(jsonb) IS
  'Unica porta de escrita de evento de erro (RN-001). Mascara dado pessoal, pseudonimiza o usuario, agrupa por impressao digital e limita a vazao por usuario.';

-- ---------------------------------------------------------
-- 6) Leitura para a tela (cross-tenant, so superadmin)
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
-- 7) Expurgo automatico (RN-012) + agendamento (guardado)
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
  DELETE FROM public.evento_incidente i
   WHERE i.status IN ('resolvido', 'fechado')
     AND NOT EXISTS (SELECT 1 FROM public.evento_erro e WHERE e.fingerprint = i.fingerprint);
  RETURN v_apagados;
END
$expurgo$;

COMMENT ON FUNCTION public.evento_erro_expurgar() IS
  'Retencao de 90 dias do evento bruto (RN-012). Prazo a confirmar com o DPO.';

DO $agenda$
BEGIN
  PERFORM cron.unschedule('central-expurgo-eventos');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'central-expurgo-eventos ainda nao existia (%).', SQLERRM;
END
$agenda$;

DO $agenda2$
BEGIN
  PERFORM cron.schedule('central-expurgo-eventos', '20 4 * * *',
                        'SELECT public.evento_erro_expurgar()');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Nao foi possivel agendar o expurgo (%).', SQLERRM;
END
$agenda2$;

-- ---------------------------------------------------------
-- CONFERENCIA — rode SEPARADA (query propria) apos aplicar.
-- Esperado: 3 | 2 | 7 | 4 | 3 | OK
-- ---------------------------------------------------------
WITH atalhos AS MATERIALIZED (
  SELECT count(*) AS n FROM (VALUES
    ('public.gen_random_bytes(integer)'),
    ('public.digest(text, text)'),
    ('public.digest(bytea, text)')
  ) v(sig) WHERE to_regprocedure(v.sig) IS NOT NULL
),
tabs AS MATERIALIZED (
  SELECT count(*) AS n FROM (VALUES
    ('public.evento_incidente'), ('public.evento_erro')
  ) v(rel) WHERE to_regclass(v.rel) IS NOT NULL
),
fns AS MATERIALIZED (
  SELECT count(*) AS n FROM (VALUES
    ('public.mascarar_pii(text)'),
    ('public.pseudonimo_usuario(uuid)'),
    ('public.registrar_evento_erro(jsonb)'),
    ('public.central_incidentes(integer)'),
    ('public.central_situacao_clientes()'),
    ('public.central_resumo()'),
    ('public.evento_erro_expurgar()')
  ) v(sig) WHERE to_regprocedure(v.sig) IS NOT NULL
),
idxs AS MATERIALIZED (
  SELECT count(*) AS n FROM pg_indexes
  WHERE schemaname='public' AND indexname IN (
    'idx_evento_erro_recebido','idx_evento_erro_fingerprint',
    'idx_evento_erro_tenant','idx_evento_incidente_vivo')
),
pols AS MATERIALIZED (
  SELECT count(*) AS n FROM pg_policies
  WHERE schemaname='public' AND policyname IN (
    'Superadmin le evento_erro','Superadmin le evento_incidente',
    'Superadmin triagem evento_incidente')
)
SELECT
  (SELECT n FROM atalhos) AS atalhos_pgcrypto_de_3,
  (SELECT n FROM tabs)    AS tabelas_de_2,
  (SELECT n FROM fns)     AS funcoes_de_7,
  (SELECT n FROM idxs)    AS indices_de_4,
  (SELECT n FROM pols)    AS policies_de_3,
  CASE WHEN (SELECT n FROM atalhos)=3 AND (SELECT n FROM tabs)=2
        AND (SELECT n FROM fns)=7 AND (SELECT n FROM idxs)=4
        AND (SELECT n FROM pols)=3
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;
