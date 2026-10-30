-- ============================================================================
-- ASSINATURA FORTE — FUNDAÇÃO ASS-0001 (Fase 0), PARTE 2 de 2 (funções + QA)
-- Cole INTEIRO no SQL Editor, DEPOIS da parte 1 (precisa das tabelas dela).
--
-- Equivale às FUNÇÕES das migrations (mesmo texto):
--   20261026203238_assinatura_selar_servidor.sql        (selar_assinatura, selar_assinatura_origem)
--   20261026203342_assinatura_consentimento_biometrico.sql (registrar_consentimento_biometrico)
--   20261026203414_assinaturas_trilha.sql               (registrar_assinatura_trilha)
--   20261026203446_arquivar_documento_servidor.sql      (arquivar_documento_servidor)
--   20261026203518_qa_assinatura_fundacao_casos.sql     (casos ASS-001..003 + rotinas)
--
-- ATENÇÃO À ORDEM: três destas funções foram REDEFINIDAS em 30/10 pela migration
-- 20261030100106_assinatura_fundacao_origem_e_subpastas.sql (origem pela borda,
-- empresa do usuário, subpastas em vários níveis): registrar_consentimento_biometrico,
-- registrar_assinatura_trilha e arquivar_documento_servidor. Aqui vai a versão de
-- 26/10 (a da fundação); a versão FINAL (a do staging) está em
-- docs/script_assinatura_espelho_parte2_funcoes.sql. Por isso, a ordem é:
--   1) docs/script_assinatura_fundacao_parte1_estrutura.sql
--   2) docs/script_assinatura_fundacao_parte2_funcoes.sql      <- ESTE
--   3) docs/script_assinatura_espelho_parte2_funcoes.sql       (REAPLICAR se o banco
--      já tinha o espelho: devolve a versão final de 30/10 das três funções)
--   4) docs/script_assinatura_espelho_parte4_testes.sql        (reaplicar: casos ESP-ASS)
-- Banco que ainda NÃO tem o espelho (produção): fundação 1 e 2, depois
-- ponto_espelho_f0 parte 1 e 2, depois assinatura_espelho parte 1, 2, 3 e 4.
-- NUNCA rode esta parte 2 sozinha depois do espelho sem reaplicar a parte 2 do
-- espelho em seguida (voltaria as três funções para a versão de 26/10).
-- A coluna proximo_passo da conferência diz o que fazer em seguida.
--
-- Não cria tabela. Nenhuma atribuição por consulta com destino em variável
-- (só subconsulta escalar). Nenhuma função com bloco injetado em runtime.
-- Marcas de aspas-dólar só em código, em número par. Só cria/redefine função e
-- documenta casos de QA (sem UPDATE/DELETE de dado de cliente). Idempotente.
-- ============================================================================

SET lock_timeout = '10s';

-- 1) O SELO DE INTEGRIDADE (hash) ------------------------------------------------
CREATE OR REPLACE FUNCTION public.selar_assinatura(
  p_conteudo   text,
  p_assinatura text,
  p_quando     timestamptz,
  p_id         text
) RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $fn$
  SELECT encode(
    public.digest(
      COALESCE(p_conteudo, '') || '|' ||
      COALESCE(p_assinatura, '') || '|' ||
      to_char(p_quando AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') || '|' ||
      COALESCE(p_id, ''),
      'sha256'),
    'hex');
$fn$;

COMMENT ON FUNCTION public.selar_assinatura(text, text, timestamptz, text) IS
  'ASS-0001: selo de integridade (sha256 hex) de uma assinatura, calculado no servidor sobre conteudo|assinatura|hora-ISO-UTC|id. Hora canonizada para bater com o modulo Deno selar-assinatura.ts. Reutilizavel por qualquer modulo.';

-- 2) A ORIGEM PELO SERVIDOR (IP, dispositivo, hora) ------------------------------
CREATE OR REPLACE FUNCTION public.selar_assinatura_origem()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $fn$
DECLARE
  v_h  jsonb;
  v_ip text;
  v_ua text;
BEGIN
  BEGIN
    v_h := NULLIF(current_setting('request.headers', true), '')::jsonb;
  EXCEPTION WHEN OTHERS THEN
    v_h := NULL;
  END;

  IF v_h IS NOT NULL THEN
    -- cf-connecting-ip o Cloudflare define e o cliente nao forja; cai para o
    -- PRIMEIRO endereco de x-forwarded-for. Nunca o que o corpo mandou.
    v_ip := COALESCE(
      NULLIF(btrim(v_h->>'cf-connecting-ip'), ''),
      NULLIF(btrim(split_part(COALESCE(v_h->>'x-forwarded-for', ''), ',', 1)), ''));
    v_ua := NULLIF(btrim(v_h->>'user-agent'), '');
  END IF;

  RETURN jsonb_build_object(
    'ip_address', v_ip,
    'user_agent', v_ua,
    'assinado_em', to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
END;
$fn$;

COMMENT ON FUNCTION public.selar_assinatura_origem() IS
  'ASS-0001: IP/dispositivo/hora da assinatura derivados do servidor (request.headers + now()); sem cabecalhos devolve ip/ua nulos. Um gatilho BEFORE INSERT de assinatura chama isto em vez de confiar no corpo.';

REVOKE EXECUTE ON FUNCTION public.selar_assinatura(text, text, timestamptz, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.selar_assinatura_origem() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.selar_assinatura(text, text, timestamptz, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.selar_assinatura_origem() TO authenticated, service_role;

-- 3) CONSENTIMENTO BIOMÉTRICO (LGPD art. 11) -------------------------------------
CREATE OR REPLACE FUNCTION public.registrar_consentimento_biometrico(p_dados jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_id       uuid := gen_random_uuid();
  v_tenant   uuid := NULLIF(p_dados->>'tenant_id', '')::uuid;
  v_origem   jsonb := public.selar_assinatura_origem();
  v_ip       text := v_origem->>'ip_address';
  v_ua       text := v_origem->>'user_agent';
  v_quando   timestamptz := (v_origem->>'assinado_em')::timestamptz;
BEGIN
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'Consentimento inválido: informe o tenant.'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF COALESCE(p_dados->>'finalidade', '') = '' OR COALESCE(p_dados->>'versao_texto', '') = '' THEN
    RAISE EXCEPTION 'Consentimento inválido: finalidade e versão do texto são obrigatórias.'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF COALESCE((p_dados->>'aceito')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'Consentimento não pode ser registrado sem o aceite do titular.'
      USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.consentimentos_assinatura
    (id, tenant_id, contexto, documento_ref, signatario_nome, signatario_cpf,
     finalidade, versao_texto, aceito, ip_address, user_agent, aceito_em)
  VALUES
    (v_id, v_tenant, COALESCE(NULLIF(p_dados->>'contexto', ''), 'assinatura'),
     NULLIF(p_dados->>'documento_ref', ''), NULLIF(p_dados->>'signatario_nome', ''),
     NULLIF(p_dados->>'signatario_cpf', ''), p_dados->>'finalidade', p_dados->>'versao_texto',
     true, v_ip, v_ua, v_quando);

  RETURN jsonb_build_object(
    'id', v_id,
    'versao_texto', p_dados->>'versao_texto',
    'aceito_em', v_quando,
    'ip_address', v_ip);
END;
$fn$;

COMMENT ON FUNCTION public.registrar_consentimento_biometrico(jsonb) IS
  'ASS-0001: registra o consentimento biometrico (LGPD art. 11) na trilha, com origem (IP/UA/hora) derivada do servidor. Chamada pelo app autenticado e pelas edges de link (service_role). Devolve id e versao.';

REVOKE EXECUTE ON FUNCTION public.registrar_consentimento_biometrico(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.registrar_consentimento_biometrico(jsonb) TO authenticated, service_role;

-- 4) TRILHA PADRONIZADA DA ASSINATURA --------------------------------------------
CREATE OR REPLACE FUNCTION public.registrar_assinatura_trilha(p_dados jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_id       uuid := gen_random_uuid();
  v_tenant   uuid := NULLIF(p_dados->>'tenant_id', '')::uuid;
  v_origem   jsonb := public.selar_assinatura_origem();
  v_ip       text := v_origem->>'ip_address';
  v_ua       text := v_origem->>'user_agent';
  v_quando   timestamptz := (v_origem->>'assinado_em')::timestamptz;
  v_ref      text := NULLIF(p_dados->>'documento_ref', '');
  v_hash     text;
BEGIN
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'Trilha inválida: informe o tenant.'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Sela o hash no servidor sobre a hora do servidor, quando houver conteúdo e
  -- assinatura; senão, aceita um hash já selado por outra camada do servidor.
  IF COALESCE(p_dados->>'conteudo', '') <> '' OR COALESCE(p_dados->>'assinatura', '') <> '' THEN
    v_hash := public.selar_assinatura(
      p_dados->>'conteudo', p_dados->>'assinatura', v_quando, COALESCE(v_ref, v_id::text));
  ELSE
    v_hash := NULLIF(p_dados->>'assinatura_hash', '');
  END IF;

  INSERT INTO public.assinaturas_trilha
    (id, tenant_id, contexto, documento_ref, signatario_nome, signatario_papel,
     signatario_cpf, cpf_validado, metodo_liveness, versao_detector, assinatura_hash,
     ip_address, user_agent, assinado_em, versao_consentimento, consentimento_id,
     frames_refs, liveness_data)
  VALUES
    (v_id, v_tenant, COALESCE(NULLIF(p_dados->>'contexto', ''), 'assinatura'), v_ref,
     NULLIF(p_dados->>'signatario_nome', ''), NULLIF(p_dados->>'signatario_papel', ''),
     NULLIF(p_dados->>'signatario_cpf', ''), COALESCE((p_dados->>'cpf_validado')::boolean, false),
     NULLIF(p_dados->>'metodo_liveness', ''), NULLIF(p_dados->>'versao_detector', ''), v_hash,
     v_ip, v_ua, v_quando, NULLIF(p_dados->>'versao_consentimento', ''),
     NULLIF(p_dados->>'consentimento_id', '')::uuid,
     COALESCE(p_dados->'frames_refs', '[]'::jsonb), p_dados->'liveness_data');

  RETURN jsonb_build_object(
    'id', v_id,
    'assinatura_hash', v_hash,
    'assinado_em', v_quando,
    'ip_address', v_ip);
END;
$fn$;

COMMENT ON FUNCTION public.registrar_assinatura_trilha(jsonb) IS
  'ASS-0001: grava a trilha padronizada da assinatura, selando hash e origem pelo servidor. App autenticado e edges de link (service_role). Devolve id e hash.';

REVOKE EXECUTE ON FUNCTION public.registrar_assinatura_trilha(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.registrar_assinatura_trilha(jsonb) TO authenticated, service_role;

-- 5) ARQUIVO CANÔNICO NO SERVIDOR (documentos + auditoria) -----------------------
CREATE OR REPLACE FUNCTION public.arquivar_documento_servidor(p_doc jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_tenant    uuid := NULLIF(p_doc->>'tenant_id', '')::uuid;
  v_empresa   uuid := NULLIF(p_doc->>'empresa_id', '')::uuid;
  v_user      uuid := NULLIF(p_doc->>'user_id', '')::uuid;
  v_user_nome text := NULLIF(p_doc->>'user_nome', '');
  v_colab_id  uuid := NULLIF(p_doc->>'colaborador_id', '')::uuid;
  v_colab_nome text := NULLIF(p_doc->>'colaborador_nome', '');
  v_colab_cpf text := NULLIF(p_doc->>'colaborador_cpf', '');
  v_categoria text := NULLIF(p_doc->>'pasta_categoria', '');
  v_subpasta  text := NULLIF(p_doc->>'subpasta_colaborador', '');
  v_storage   text := NULLIF(p_doc->>'storage_path', '');
  v_nome_orig text := NULLIF(p_doc->>'file_name', '');
  v_tipo      text := COALESCE(NULLIF(p_doc->>'tipo', ''), 'documento');
  v_mime      text := COALESCE(NULLIF(p_doc->>'mime_type', ''), 'application/pdf');
  v_tamanho   integer := COALESCE((p_doc->>'tamanho')::integer, 0);
  v_validade  date := NULLIF(p_doc->>'data_validade', '')::date;
  v_gp        uuid;
  v_colab_pasta uuid;
  v_pasta_id  uuid;
  v_doc_id    uuid := gen_random_uuid();
  v_status    text := 'valido';
  v_sub       text;
  v_i         int := 0;
  v_cand      text;
  v_cultura_root uuid;
BEGIN
  IF v_tenant IS NULL OR v_storage IS NULL OR v_nome_orig IS NULL THEN
    RAISE EXCEPTION 'Arquivamento inválido: informe tenant, storage_path e file_name.'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- 1) Resolver a pasta de destino -------------------------------------------
  IF v_colab_id IS NOT NULL AND v_colab_nome IS NOT NULL THEN
    -- Pasta do colaborador, sob "Gestão de Pessoas" (espelha criarPastaColaborador).
    v_colab_pasta := (
      SELECT id FROM public.documento_pastas
       WHERE tenant_id = v_tenant AND colaborador_id = v_colab_id AND tipo = 'colaborador'
         AND COALESCE(empresa_id::text, '') = COALESCE(v_empresa::text, '')
       LIMIT 1);

    IF v_colab_pasta IS NULL THEN
      v_gp := (
        SELECT id FROM public.documento_pastas
         WHERE tenant_id = v_tenant AND nome = 'Gestão de Pessoas'
           AND COALESCE(empresa_id::text, '') = COALESCE(v_empresa::text, '')
         LIMIT 1);
      IF v_gp IS NULL THEN
        v_gp := gen_random_uuid();
        INSERT INTO public.documento_pastas
          (id, tenant_id, empresa_id, nome, tipo, ordem, icone, criado_por, criado_por_nome)
        VALUES (v_gp, v_tenant, v_empresa, 'Gestão de Pessoas', 'root', 5, 'Users', v_user, v_user_nome);
      END IF;

      v_colab_pasta := gen_random_uuid();
      INSERT INTO public.documento_pastas
        (id, tenant_id, empresa_id, nome, tipo, pasta_pai_id, colaborador_id, colaborador_cpf,
         colaborador_nome, ordem, icone, criado_por, criado_por_nome)
      VALUES (v_colab_pasta, v_tenant, v_empresa, v_colab_nome, 'colaborador', v_gp, v_colab_id,
              v_colab_cpf, v_colab_nome, 0, 'User', v_user, v_user_nome);
    END IF;

    -- Garante as subpastas padrão (idempotente).
    v_i := 0;
    FOREACH v_sub IN ARRAY ARRAY['Admissão', 'Vida Funcional', 'Saúde Ocupacional', 'Desligamento'] LOOP
      IF NOT EXISTS (
        SELECT 1 FROM public.documento_pastas
         WHERE tenant_id = v_tenant AND pasta_pai_id = v_colab_pasta AND nome = v_sub) THEN
        INSERT INTO public.documento_pastas
          (id, tenant_id, empresa_id, nome, tipo, pasta_pai_id, ordem, criado_por, criado_por_nome)
        VALUES (gen_random_uuid(), v_tenant, v_empresa, v_sub, 'categoria', v_colab_pasta, v_i, v_user, v_user_nome);
      END IF;
      v_i := v_i + 1;
    END LOOP;

    IF v_subpasta IS NOT NULL THEN
      v_pasta_id := (
        SELECT id FROM public.documento_pastas
         WHERE tenant_id = v_tenant AND pasta_pai_id = v_colab_pasta AND nome = v_subpasta LIMIT 1);
    END IF;
    v_pasta_id := COALESCE(v_pasta_id, v_colab_pasta);

  ELSIF v_categoria = 'Cultura' THEN
    v_cultura_root := (
      SELECT id FROM public.documento_pastas
       WHERE tenant_id = v_tenant AND nome = 'Cultura Organizacional'
         AND COALESCE(empresa_id::text, '') = COALESCE(v_empresa::text, '') AND pasta_pai_id IS NULL
       LIMIT 1);
    IF v_cultura_root IS NULL THEN
      v_cultura_root := gen_random_uuid();
      INSERT INTO public.documento_pastas
        (id, tenant_id, empresa_id, nome, tipo, ordem, icone, criado_por, criado_por_nome)
      VALUES (v_cultura_root, v_tenant, v_empresa, 'Cultura Organizacional', 'root', 4, 'Heart', v_user, v_user_nome);
    END IF;
    v_pasta_id := v_cultura_root;

  ELSIF v_categoria IS NOT NULL THEN
    -- Primeira pasta existente entre os nomes candidatos da categoria.
    FOREACH v_cand IN ARRAY (CASE v_categoria
        WHEN 'SST' THEN ARRAY['SST e Segurança do Trabalho', 'SST da Empresa']
        WHEN 'Ergonomia' THEN ARRAY['Ergonomia', 'AEP — Avaliação Ergonômica Preliminar']
        WHEN 'Psicossocial' THEN ARRAY['Riscos Psicossociais (NR-01)', 'Diagnóstico Psicossocial']
        WHEN 'Ponto' THEN ARRAY['Gestão de Pessoas', 'Processos Organizacionais']
        WHEN 'Financeiro' THEN ARRAY['Processos Organizacionais', 'Gestão de Pessoas']
        WHEN 'Desligamento' THEN ARRAY['Gestão de Pessoas']
        WHEN 'Admissão' THEN ARRAY['Gestão de Pessoas']
        WHEN 'Aprendizado' THEN ARRAY['Processos Organizacionais', 'Gestão de Pessoas']
        ELSE ARRAY[v_categoria] END) LOOP
      v_pasta_id := (
        SELECT id FROM public.documento_pastas
         WHERE tenant_id = v_tenant AND nome = v_cand LIMIT 1);
      EXIT WHEN v_pasta_id IS NOT NULL;
    END LOOP;
  END IF;

  -- 2) Status pela validade ---------------------------------------------------
  IF v_validade IS NOT NULL THEN
    IF v_validade < CURRENT_DATE THEN v_status := 'vencido';
    ELSIF v_validade <= CURRENT_DATE + 30 THEN v_status := 'vencendo';
    END IF;
  END IF;

  -- 3) Registro do documento (colunas canônicas) ------------------------------
  INSERT INTO public.documentos
    (id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
     nome_arquivo, nome_original, tipo, tamanho, mime_type, storage_path, data_validade,
     status, observacoes, criado_por, criado_por_nome, pasta_id, versao_atual, total_versoes)
  VALUES
    (v_doc_id, v_tenant, v_empresa, v_colab_id, COALESCE(v_colab_nome, ''), v_colab_cpf,
     v_storage, v_nome_orig, v_tipo, v_tamanho, v_mime, v_storage, v_validade,
     v_status, NULLIF(p_doc->>'observacoes', ''), v_user, v_user_nome, v_pasta_id, 1, 1);

  -- 4) Auditoria (não bloqueante) ---------------------------------------------
  BEGIN
    INSERT INTO public.documento_audit_logs
      (tenant_id, documento_id, documento_nome, acao, pasta_destino_id, pasta_destino_nome,
       usuario_id, usuario_nome)
    VALUES
      (v_tenant, v_doc_id, v_nome_orig, 'upload', v_pasta_id, v_tipo, v_user, v_user_nome);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'arquivar_documento_servidor: auditoria falhou (seguindo): %', SQLERRM;
  END;

  RETURN jsonb_build_object('id', v_doc_id, 'storage_path', v_storage, 'pasta_id', v_pasta_id, 'status', v_status);
END;
$fn$;

COMMENT ON FUNCTION public.arquivar_documento_servidor(jsonb) IS
  'ASS-0001: arquivo canonico no servidor (espelha src/utils/arquivarDocumento.ts): resolve pasta (colaborador/categoria), insere em documentos e grava documento_audit_logs. Edges chamam isto em vez de insert proprio. Upload ao storage fica na camada Deno/cliente.';

REVOKE EXECUTE ON FUNCTION public.arquivar_documento_servidor(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.arquivar_documento_servidor(jsonb) TO authenticated, service_role;

-- 6) QA DA FUNDAÇÃO: casos ASS-001..003 (nível api) -----------------------------
DO $doc$
DECLARE v_sec uuid; v_mod uuid;
BEGIN
  v_sec := (SELECT id FROM public.qa_modulos WHERE path = 'documentos-governanca' LIMIT 1);
  IF v_sec IS NULL THEN
    RAISE NOTICE 'Seção documentos-governanca não encontrada: casos ASS não documentados.';
    RETURN;
  END IF;

  INSERT INTO public.qa_modulos (parent_id, label, path, ordem)
  VALUES (v_sec, 'Assinatura forte (fundação)', 'documentos-governanca/assinatura', 3)
  ON CONFLICT (path) DO NOTHING;

  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'documentos-governanca/assinatura' LIMIT 1);

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'ASS-001',
   'O selo da assinatura (hash e origem IP/hora) é feito pelo servidor e não pode ser forjado pelo navegador',
   'negativo', 'alta', 'aprovado', 'api',
   'Lei 14.063/2020, art. 4º (assinatura avançada: identificar o signatário e detectar alteração); MP 2.200-2/2001, art. 10, §2º; LGPD art. 6º, X (prestação de contas)',
   'A fundação precisa provar quem/quando/de onde. selar_assinatura gera o mesmo hash para a mesma entrada (determinístico) e muda quando a entrada muda; selar_assinatura_origem prefere cf-connecting-ip, cai para o primeiro x-forwarded-for, e sem cabeçalhos devolve IP/UA nulos — a hora é sempre do servidor.',
   'Nenhuma: funções puras/do servidor, sem dados de fixture.',
   '[{"ordem":1,"acao":"Selar a mesma assinatura duas vezes e uma terceira com conteúdo diferente","resultado_esperado":"hash de 64 hex; iguais para entrada igual; diferente para conteúdo diferente"},
     {"ordem":2,"acao":"Derivar a origem com cf-connecting-ip e x-forwarded-for presentes","resultado_esperado":"IP = cf-connecting-ip; UA do cabeçalho"},
     {"ordem":3,"acao":"Derivar a origem só com x-forwarded-for (lista)","resultado_esperado":"IP = primeiro endereço da lista"},
     {"ordem":4,"acao":"Derivar a origem sem cabeçalhos","resultado_esperado":"IP e UA nulos; hora do servidor presente"}]'::jsonb,
   'O hash e a origem (IP/hora) são do servidor; o que o navegador mandar não prevalece.',
   'Coração do avançada forte. Espelha os gatilhos do EPI (20261022203847 e 20261022213306), agora reutilizáveis por qualquer módulo. Fase 1 aplica à Advertência.'),
  (v_mod, 'ASS-002',
   'O consentimento biométrico (LGPD art. 11) é registrado na trilha com origem do servidor e exige aceite',
   'feliz', 'alta', 'aprovado', 'api',
   'LGPD art. 11, I (consentimento específico e destacado para dado sensível) e art. 9º (finalidade); Lei 14.063/2020, art. 4º',
   'Antes de ligar a câmera, o aceite do consentimento é gravado com quem/quando/qual versão do texto; o IP vem do servidor, não do corpo; sem aceite, o registro é recusado.',
   'Cercado de teste (sandbox).',
   '[{"ordem":1,"acao":"Registrar o consentimento aceito com cabeçalho de IP e um IP falso no corpo","resultado_esperado":"linha gravada; ip_address do cabeçalho; versão do texto preservada"},
     {"ordem":2,"acao":"Tentar registrar sem aceite (aceito=false)","resultado_esperado":"recusado com erro claro"}]'::jsonb,
   'Consentimento fica na trilha com a versão aceita e a origem do servidor; sem aceite, não grava.',
   'Lacuna LGPD que não existia. A tela é src/components/assinatura/ConsentimentoBiometrico.tsx; a versão do texto é VERSAO_CONSENTIMENTO_BIOMETRICO (src/lib/assinaturaConsentimento.ts).'),
  (v_mod, 'ASS-003',
   'O arquivo canônico no servidor resolve a pasta do colaborador, grava em documentos e registra a auditoria',
   'feliz', 'alta', 'aprovado', 'api',
   'LGPD art. 6º, X (prestação de contas); boa governança documental',
   'Um só caminho de arquivamento no servidor para todas as assinaturas por link, em vez de cada edge inserir à mão com colunas divergentes. Resolve/cria a pasta do colaborador sob "Gestão de Pessoas", insere em documentos com as colunas certas e grava documento_audit_logs.',
   'Cercado de teste (sandbox).',
   '[{"ordem":1,"acao":"Arquivar um documento de um colaborador pelo servidor","resultado_esperado":"devolve id e pasta_id; documento gravado em documentos com nome_arquivo = storage_path e pasta_id resolvida"},
     {"ordem":2,"acao":"Conferir a auditoria","resultado_esperado":"documento_audit_logs tem a linha de upload do documento"}]'::jsonb,
   'Documento arquivado na pasta certa, com as colunas canônicas e com trilha de auditoria.',
   'Espelha src/utils/arquivarDocumento.ts. O upload do binário continua na camada Deno/cliente; a RPC cuida dos registros. Fase 1: as edges (advertencia-link etc.) passam a chamar _shared/arquivar-documento.ts.')
  ON CONFLICT (codigo) DO UPDATE SET
    modulo_id = EXCLUDED.modulo_id, titulo = EXCLUDED.titulo, objetivo = EXCLUDED.objetivo,
    passos = EXCLUDED.passos, resultado_esperado = EXCLUDED.resultado_esperado,
    base_legal = EXCLUDED.base_legal, observacoes = EXCLUDED.observacoes, status = 'aprovado';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentação ASS-001..003 não registrada: %', SQLERRM;
END $doc$;

-- ── ASS-001 ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ass_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno;
        v_h1 text; v_h2 text; v_h3 text;
        v_o1 jsonb; v_o2 jsonb; v_o3 jsonb;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Selar a mesma assinatura 2x e uma 3ª com conteúdo diferente';
  r.esperado := 'hash de 64 hex; determinístico; sensível ao conteúdo';
  v_h1 := public.selar_assinatura('doc-abc', 'colab assinou', '2026-01-02T03:04:05.678Z'::timestamptz, 'id-1');
  v_h2 := public.selar_assinatura('doc-abc', 'colab assinou', '2026-01-02T03:04:05.678Z'::timestamptz, 'id-1');
  v_h3 := public.selar_assinatura('doc-XYZ', 'colab assinou', '2026-01-02T03:04:05.678Z'::timestamptz, 'id-1');

  r.passo_ordem := 2;
  r.passo_acao := 'Origem com cf-connecting-ip e x-forwarded-for';
  PERFORM set_config('request.headers',
    '{"cf-connecting-ip":"203.0.113.7","x-forwarded-for":"198.51.100.9, 10.0.0.1","user-agent":"qa-agente"}', true);
  v_o1 := public.selar_assinatura_origem();

  r.passo_ordem := 3;
  r.passo_acao := 'Origem só com x-forwarded-for (lista)';
  PERFORM set_config('request.headers', '{"x-forwarded-for":"198.51.100.9, 10.0.0.1"}', true);
  v_o2 := public.selar_assinatura_origem();

  r.passo_ordem := 4;
  r.passo_acao := 'Origem sem cabeçalhos';
  PERFORM set_config('request.headers', '', true);
  v_o3 := public.selar_assinatura_origem();

  IF v_h1 !~ '^[0-9a-f]{64}$' THEN
    r.situacao := 'falhou'; r.obtido := format('hash fora do formato sha256 hex: %s', v_h1);
  ELSIF v_h1 IS DISTINCT FROM v_h2 THEN
    r.situacao := 'falhou'; r.obtido := 'o mesmo conteúdo gerou hashes diferentes (não determinístico)';
  ELSIF v_h1 = v_h3 THEN
    r.situacao := 'falhou'; r.obtido := 'conteúdo diferente gerou o mesmo hash (não detecta alteração)';
  ELSIF (v_o1->>'ip_address') IS DISTINCT FROM '203.0.113.7' THEN
    r.situacao := 'falhou'; r.obtido := format('com cf-connecting-ip o IP devia ser 203.0.113.7 e foi %s', COALESCE(v_o1->>'ip_address','vazio'));
  ELSIF (v_o1->>'user_agent') IS DISTINCT FROM 'qa-agente' THEN
    r.situacao := 'falhou'; r.obtido := 'user-agent do cabeçalho não foi registrado';
  ELSIF (v_o2->>'ip_address') IS DISTINCT FROM '198.51.100.9' THEN
    r.situacao := 'falhou'; r.obtido := format('x-forwarded-for devia dar o primeiro endereço (198.51.100.9) e deu %s', COALESCE(v_o2->>'ip_address','vazio'));
  ELSIF (v_o3->>'ip_address') IS NOT NULL OR (v_o3->>'user_agent') IS NOT NULL THEN
    r.situacao := 'falhou'; r.obtido := 'sem cabeçalhos o IP/UA deviam ser nulos (não inventar)';
  ELSIF (v_o3->>'assinado_em') IS NULL THEN
    r.situacao := 'falhou'; r.obtido := 'a hora do servidor não foi registrada';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'hash determinístico e sensível; IP/UA/hora vêm do servidor; corpo não prevalece';
  END IF;
  r.detalhe := jsonb_build_object('h1', v_h1, 'h3', v_h3, 'o1', v_o1, 'o2', v_o2, 'o3', v_o3);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── ASS-002 ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ass_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_res jsonb; v_id uuid; v_row jsonb; v_recusou boolean := false;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Registrar o consentimento aceito, com IP no cabeçalho e IP falso no corpo';
  r.esperado := 'linha gravada; ip do cabeçalho; versão do texto preservada';
  PERFORM set_config('request.headers', '{"cf-connecting-ip":"203.0.113.50","user-agent":"qa-consent"}', true);
  v_res := public.registrar_consentimento_biometrico(jsonb_build_object(
    'tenant_id', v_t, 'contexto', 'advertencia', 'documento_ref', 'qa-doc-002',
    'signatario_nome', 'QA Signatário 002', 'signatario_cpf', public.qa_cpf(2),
    'finalidade', 'Confirmar a identidade na assinatura deste documento',
    'versao_texto', 'consentimento-biometrico-v1', 'aceito', true, 'ip_address', '1.1.1.1'));
  v_id := (v_res->>'id')::uuid;
  v_row := (SELECT to_jsonb(c) FROM public.consentimentos_assinatura c WHERE c.id = v_id);

  r.passo_ordem := 2;
  r.passo_acao := 'Tentar registrar sem aceite (aceito=false)';
  BEGIN
    PERFORM public.registrar_consentimento_biometrico(jsonb_build_object(
      'tenant_id', v_t, 'finalidade', 'x', 'versao_texto', 'v1', 'aceito', false));
  EXCEPTION WHEN OTHERS THEN
    v_recusou := true;
  END;

  IF v_row IS NULL THEN
    r.situacao := 'falhou'; r.obtido := 'o consentimento aceito não foi gravado na trilha';
  ELSIF (v_row->>'ip_address') IS DISTINCT FROM '203.0.113.50' THEN
    r.situacao := 'falhou'; r.obtido := format('ip gravado foi %s; devia ser o do cabeçalho (203.0.113.50), não o do corpo (1.1.1.1)', COALESCE(v_row->>'ip_address','vazio'));
  ELSIF (v_row->>'versao_texto') IS DISTINCT FROM 'consentimento-biometrico-v1' THEN
    r.situacao := 'falhou'; r.obtido := 'a versão do texto aceita não foi preservada';
  ELSIF NOT v_recusou THEN
    r.situacao := 'falhou'; r.obtido := 'o registro sem aceite deveria ter sido recusado';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'consentimento gravado com versão e IP do servidor; registro sem aceite recusado';
  END IF;
  r.detalhe := jsonb_build_object('registro', v_row, 'recusou_sem_aceite', v_recusou);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── ASS-003 ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ass_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_colab uuid := gen_random_uuid(); v_res jsonb; v_doc_id uuid; v_pasta uuid;
        v_doc jsonb; v_tem_audit boolean;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM set_config('request.headers', '', true);

  r.passo_ordem := 1;
  r.passo_acao := 'Arquivar um documento de colaborador pelo servidor';
  r.esperado := 'devolve id e pasta_id; documento com nome_arquivo = storage e pasta resolvida';
  v_res := public.arquivar_documento_servidor(jsonb_build_object(
    'tenant_id', v_t, 'user_nome', 'QA Sistema',
    'colaborador_id', v_colab::text, 'colaborador_nome', 'QA Colaborador 003',
    'colaborador_cpf', public.qa_cpf(3),
    'storage_path', v_t::text || '/colaboradores/' || v_colab::text || '/qa-advertencia-003.pdf',
    'file_name', 'advertencia-003.pdf', 'tipo', 'advertencia',
    'mime_type', 'application/pdf', 'tamanho', 2048));
  v_doc_id := (v_res->>'id')::uuid;
  v_pasta := (v_res->>'pasta_id')::uuid;
  v_doc := (SELECT to_jsonb(d) FROM public.documentos d WHERE d.id = v_doc_id);

  r.passo_ordem := 2;
  r.passo_acao := 'Conferir a auditoria';
  v_tem_audit := EXISTS (
    SELECT 1 FROM public.documento_audit_logs
     WHERE documento_id = v_doc_id AND acao = 'upload');

  IF v_doc IS NULL THEN
    r.situacao := 'falhou'; r.obtido := 'o documento não foi gravado em documentos';
  ELSIF v_pasta IS NULL OR (v_doc->>'pasta_id') IS NULL THEN
    r.situacao := 'falhou'; r.obtido := 'a pasta do colaborador não foi resolvida (pasta_id nulo)';
  ELSIF (v_doc->>'nome_arquivo') IS DISTINCT FROM (v_doc->>'storage_path') THEN
    r.situacao := 'falhou'; r.obtido := 'nome_arquivo não ficou igual ao storage_path (colunas divergentes)';
  ELSIF NOT v_tem_audit THEN
    r.situacao := 'falhou'; r.obtido := 'não gravou a linha de auditoria (documento_audit_logs)';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('documento %s arquivado na pasta %s com auditoria', v_doc_id, v_pasta);
  END IF;
  r.detalhe := jsonb_build_object('retorno', v_res, 'tem_audit', v_tem_audit,
                                  'pasta_id', v_pasta, 'nome_arquivo', v_doc->>'nome_arquivo');
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES
  ('ASS-001', 'qa_caso_ass_001'),
  ('ASS-002', 'qa_caso_ass_002'),
  ('ASS-003', 'qa_caso_ass_003')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- ── CONFERÊNCIA (esperado: funcoes_ok true, casos 3, ASS-001..003 "passou") ──
SELECT
  (to_regprocedure('public.selar_assinatura(text,text,timestamptz,text)') IS NOT NULL
   AND to_regprocedure('public.selar_assinatura_origem()') IS NOT NULL
   AND to_regprocedure('public.registrar_consentimento_biometrico(jsonb)') IS NOT NULL
   AND to_regprocedure('public.registrar_assinatura_trilha(jsonb)') IS NOT NULL
   AND to_regprocedure('public.arquivar_documento_servidor(jsonb)') IS NOT NULL) AS funcoes_ok,
  (SELECT count(*) FROM public.qa_casos_teste WHERE codigo IN ('ASS-001', 'ASS-002', 'ASS-003')) AS casos_documentados,
  CASE WHEN to_regprocedure('public.qa_executar_descartavel(text)') IS NULL THEN 'sem_motor'
       ELSE (public.qa_executar_descartavel('qa_caso_ass_001')).situacao::text END AS ass_001,
  CASE WHEN to_regprocedure('public.qa_executar_descartavel(text)') IS NULL THEN 'sem_motor'
       ELSE (public.qa_executar_descartavel('qa_caso_ass_002')).situacao::text END AS ass_002,
  CASE WHEN to_regprocedure('public.qa_executar_descartavel(text)') IS NULL THEN 'sem_motor'
       ELSE (public.qa_executar_descartavel('qa_caso_ass_003')).situacao::text END AS ass_003,
  public.selar_assinatura('a', 'b', '2026-01-01T00:00:00.000Z'::timestamptz, 'id') AS exemplo_hash,
  CASE WHEN to_regclass('public.assinatura_solicitacoes') IS NOT NULL
       THEN 'REAPLICAR docs/script_assinatura_espelho_parte2_funcoes.sql e depois a parte4'
       ELSE 'seguir: ponto_espelho_f0 parte1/parte2, depois assinatura_espelho parte1..4'
  END AS proximo_passo;
