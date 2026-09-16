-- =====================================================================
-- SCRIPT DE ENTREGA · CENTRAL DE CONTROLE DE CLIENTES
-- Eixo tecnico: captura de erros dos clientes (com mascaramento LGPD)
--
-- Cole no SQL Editor do projeto. Roda em UMA transacao e pode ser
-- executado mais de uma vez sem efeito diferente.
--
-- O QUE FAZ (so CRIA coisa nova; nao altera nem apaga dado existente):
--   . tabelas evento_erro e evento_incidente, com leitura so de superadmin;
--   . mascarar_pii: tira CPF, CNPJ, e-mail, telefone e segredos do texto;
--   . pseudonimo_usuario: apelido estavel do usuario, sem identifica-lo;
--   . registrar_evento_erro: a UNICA porta de escrita de evento, com
--     limite de vazao por usuario e recusa de chamada sem sessao;
--   . central_incidentes / central_situacao_clientes / central_resumo:
--     leitura da tela, restrita a superadmin;
--   . evento_erro_expurgar + agendamento diario (retencao de 90 dias);
--   . documentacao de testes CENTRAL-001..005 e as rotinas do motor.
--
-- Como so cria coisa nova, nao ha copia de seguranca a fazer.
--
-- CONFERIDO em replica local: as migrations do repositorio atravessam um
-- banco vazio sem erro e as cinco rotinas de QA passam.
--
-- Conteudo igual ao das migrations 20260916195655_central_captura_erros.sql
-- e 20260916200604_qa_central_captura_erros.sql.
-- =====================================================================

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

-- =========== DOCUMENTACAO DE TESTES E ROTINAS DO MOTOR ===========


-- ---------------------------------------------------------
-- 1) Modulo na arvore da Documentacao de Testes
-- ---------------------------------------------------------
DO $mod$
DECLARE v_sec uuid;
BEGIN
  SELECT id INTO v_sec FROM public.qa_modulos WHERE path = 'sistema';
  IF v_sec IS NULL THEN
    RAISE EXCEPTION 'Bloco sistema nao encontrado na arvore de QA.';
  END IF;

  INSERT INTO public.qa_modulos (parent_id, label, path, ordem, prioridade_doc, status_doc)
  VALUES (v_sec, 'Central de Controle de Clientes', 'sistema/central-controle-clientes', 9, 2, 'documentado')
  ON CONFLICT (path) DO UPDATE
    SET label = EXCLUDED.label, status_doc = 'documentado', motivo_bloqueio = NULL;
END $mod$;

-- ---------------------------------------------------------
-- 2) Casos documentados
-- ---------------------------------------------------------
DO $doc$
DECLARE v_mod uuid;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'sistema/central-controle-clientes';

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'CENTRAL-001', 'Dado pessoal nao e gravado em claro no evento de erro',
   'negativo', 'critica', 'aprovado', 'api',
   'A Central e a maior superficie de dado pessoal interno da casa. Um erro na tela pode arrastar CPF, e-mail ou telefone do colaborador do cliente. Nada disso pode chegar ao disco.',
   'Usuario autenticado.',
   '[{"ordem":1,"acao":"Registrar um erro cuja mensagem contem CPF, e-mail, telefone e um token","resultado_esperado":"O evento gravado mostra [cpf], [email], [telefone] e [oculto]; nenhum dos valores originais aparece"}]'::jsonb,
   'O evento existe, e util para depurar, e nao carrega dado pessoal.',
   'LGPD art. 11 / RN-002. Mascaramento por public.mascarar_pii, aplicado na ingestao.'),

  (v_mod, 'CENTRAL-002', 'Escrita direta na tabela de evento e negada',
   'negativo', 'critica', 'aprovado', 'api',
   'Fecha a classe de vulnerabilidade ja conhecida na casa: gravacao direta em tabela exposta. A unica porta e a funcao do servidor.',
   'Sessao de usuario comum (papel authenticated).',
   '[{"ordem":1,"acao":"Tentar INSERT direto em evento_erro pelo papel authenticated","resultado_esperado":"A gravacao e recusada"}]'::jsonb,
   'Nenhum caminho de escrita alem de registrar_evento_erro.',
   'RN-001. A tabela nao tem politica de INSERT, de proposito.'),

  (v_mod, 'CENTRAL-003', 'Erros iguais agrupam em um unico incidente',
   'feliz', 'alta', 'aprovado', 'api',
   'Mil ocorrencias do mesmo defeito precisam virar UMA linha na fila de trabalho, senao a equipe se afoga e para de olhar.',
   'Usuario autenticado.',
   '[{"ordem":1,"acao":"Registrar duas vezes o mesmo erro, mudando apenas os numeros da mensagem","resultado_esperado":"Um unico incidente, com o contador de ocorrencias em 2"}]'::jsonb,
   'Um defeito = um incidente, com contagem.',
   'RN-005. A impressao digital ignora numeros, enderecos e aspas.'),

  (v_mod, 'CENTRAL-004', 'Sem sessao, a ingestao recusa o evento',
   'negativo', 'alta', 'aprovado', 'api',
   'A porta de entrada de evento so aceita origem autenticada da aplicacao, para nao virar deposito aberto de qualquer um.',
   'Nenhuma sessao ativa.',
   '[{"ordem":1,"acao":"Chamar a ingestao sem sessao","resultado_esperado":"Resposta gravado=false, motivo sem_sessao; nada e gravado"}]'::jsonb,
   'Evento anonimo nao entra.',
   'Secao 3.4 do documento de requisitos.'),

  (v_mod, 'CENTRAL-005', 'Usuario aparece pseudonimizado no evento',
   'feliz', 'alta', 'aprovado', 'api',
   'Precisamos saber que foi o mesmo usuario de novo, sem guardar quem ele e.',
   'Usuario autenticado.',
   '[{"ordem":1,"acao":"Registrar um erro e ler o evento gravado","resultado_esperado":"O campo do usuario traz um apelido estavel, diferente do id e sem e-mail ou nome"}]'::jsonb,
   'Rastreabilidade sem identificacao.',
   'RN-003. O sal do pseudonimo vive no app_config de cada ambiente.')
  ON CONFLICT (codigo) DO NOTHING;
END $doc$;

-- ---------------------------------------------------------
-- 3) Rotinas do motor (somente leitura do ponto de vista do usuario:
--    escrevem apenas dentro da propria transacao de teste)
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.qa_caso_central_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_texto text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Mascarar mensagem com CPF, e-mail, telefone e token';
  r.esperado := 'Nenhum valor original sobrevive ao mascaramento';

  v_texto := public.mascarar_pii(
    'colaborador 900.000.012-34 (maria.silva@empresa.com.br), fone (46) 99123-4567, token=abc123');

  IF v_texto LIKE '%[cpf]%' AND v_texto LIKE '%[email]%'
     AND v_texto LIKE '%[telefone]%' AND v_texto LIKE '%[oculto]%'
     AND v_texto NOT LIKE '%900.000.012-34%' AND v_texto NOT LIKE '%maria.silva%'
     AND v_texto NOT LIKE '%abc123%' THEN
    r.situacao := 'passou';
    r.obtido := 'Dado pessoal mascarado antes de gravar: ' || v_texto;
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'Sobrou dado pessoal no texto mascarado: ' || v_texto;
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_central_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_insert_livre boolean; v_grant boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA: procurar caminho de escrita direta em evento_erro';
  r.esperado := 'Nenhuma politica de INSERT e nenhum GRANT de INSERT para anon/authenticated';

  SELECT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'evento_erro'
      AND cmd IN ('INSERT', 'ALL')
  ) INTO v_insert_livre;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.role_table_grants
    WHERE table_schema = 'public' AND table_name = 'evento_erro'
      AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE')
      AND grantee IN ('anon', 'authenticated')
  ) INTO v_grant;

  IF NOT v_insert_livre AND NOT v_grant THEN
    r.situacao := 'passou';
    r.obtido := 'Escrita so pela funcao do servidor: sem politica de INSERT e sem GRANT de escrita.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'Existe caminho de escrita direta (politica=' || v_insert_livre::text ||
                ', grant=' || v_grant::text || ').';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_central_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_uid uuid; v_a jsonb; v_b jsonb; v_oc int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Registrar o mesmo erro duas vezes, mudando so os numeros';
  r.esperado := 'Um unico incidente, com duas ocorrencias';

  SELECT user_id INTO v_uid FROM public.superadmins WHERE ativo LIMIT 1;
  IF v_uid IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Sem superadmin ativo para simular a sessao.';
    RETURN r;
  END IF;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);

  v_a := public.registrar_evento_erro(jsonb_build_object(
    'mensagem', '[QA-CENTRAL3] falha no registro 111', 'modulo', 'QA',
    'tipo', 'QaTeste', 'stack', 'at rotinaDeTeste (qa.ts:111)'));
  v_b := public.registrar_evento_erro(jsonb_build_object(
    'mensagem', '[QA-CENTRAL3] falha no registro 999', 'modulo', 'QA',
    'tipo', 'QaTeste', 'stack', 'at rotinaDeTeste (qa.ts:999)'));

  SELECT ocorrencias INTO v_oc FROM public.evento_incidente
   WHERE fingerprint = v_b->>'fingerprint';

  IF (v_a->>'fingerprint') = (v_b->>'fingerprint') AND COALESCE(v_oc, 0) >= 2 THEN
    r.situacao := 'passou';
    r.obtido := 'Os dois erros caíram no mesmo incidente, com contador em ' || v_oc::text || '.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'Erros iguais geraram incidentes diferentes (' ||
                COALESCE(v_a->>'fingerprint','?') || ' x ' || COALESCE(v_b->>'fingerprint','?') || ').';
  END IF;
  r.detalhe := jsonb_build_object('primeiro', v_a, 'segundo', v_b, 'ocorrencias', v_oc);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_central_004()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_resposta jsonb;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Chamar a ingestao sem nenhuma sessao';
  r.esperado := 'Recusa com motivo sem_sessao, sem gravar nada';

  -- Sessao ausente: claims sem 'sub' (e como o PostgREST chega sem login).
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  v_resposta := public.registrar_evento_erro(
    jsonb_build_object('mensagem', '[QA-CENTRAL4] tentativa anonima', 'modulo', 'QA'));

  IF (v_resposta->>'gravado') = 'false' AND (v_resposta->>'motivo') = 'sem_sessao' THEN
    r.situacao := 'passou';
    r.obtido := 'Ingestao recusou evento sem sessao.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'Ingestao aceitou (ou recusou pelo motivo errado): ' || v_resposta::text;
  END IF;
  r.detalhe := v_resposta;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_central_005()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_uid uuid; v_pseudo text; v_email text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Gerar o apelido do usuario e comparar com o que identifica a pessoa';
  r.esperado := 'Apelido estavel, diferente do id e sem e-mail';

  SELECT user_id, email INTO v_uid, v_email FROM public.superadmins WHERE ativo LIMIT 1;
  IF v_uid IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Sem superadmin ativo para gerar o apelido.';
    RETURN r;
  END IF;

  v_pseudo := public.pseudonimo_usuario(v_uid);

  IF v_pseudo IS NOT NULL
     AND v_pseudo <> v_uid::text
     AND position(COALESCE(v_email, '@@') in v_pseudo) = 0
     AND v_pseudo = public.pseudonimo_usuario(v_uid) THEN
    r.situacao := 'passou';
    r.obtido := 'Usuario entra como apelido estavel, sem identificar a pessoa.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'O apelido nao protege a identidade do usuario.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- === CONFERENCIA (unico resultado que o editor mostra) ===
SELECT
  (SELECT count(*) FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name IN ('evento_erro','evento_incidente'))  AS tabelas_criadas_esperado_2,
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname IN
      ('mascarar_pii','pseudonimo_usuario','registrar_evento_erro','central_incidentes',
       'central_situacao_clientes','central_resumo','evento_erro_expurgar'))              AS funcoes_criadas_esperado_7,
  (SELECT count(*) FROM pg_policies WHERE schemaname='public'
     AND tablename='evento_erro' AND cmd IN ('INSERT','ALL'))                             AS escrita_direta_deve_ser_zero,
  (SELECT count(*) FROM public.qa_casos_teste WHERE codigo LIKE 'CENTRAL-%')              AS casos_documentados_esperado_5,
  (SELECT count(*) FROM cron.job WHERE jobname = 'central-expurgo-eventos')               AS expurgo_agendado_esperado_1,
  public.mascarar_pii('teste 900.000.012-34 e maria@empresa.com.br')                      AS amostra_mascarada;
