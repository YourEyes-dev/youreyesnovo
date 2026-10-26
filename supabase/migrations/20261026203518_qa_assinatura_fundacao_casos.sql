-- =========================================================
-- ASS-0001 — FASE 0: QA da fundação (casos api ASS-001/002/003).
--
-- Documenta e implementa os três casos que guardam a fundação reutilizável:
--   ASS-001  selar_assinatura: hash e origem (IP/hora) vêm do servidor;
--   ASS-002  consentimento biométrico registrado na trilha, origem pelo servidor;
--   ASS-003  arquivo canônico no servidor (pasta + documentos + auditoria).
-- Nível 'api' (motor SQL). Só documenta/implementa — a bateria roda no staging/
-- homologação (script de entrega), como no EPI-047. NÃO toca módulo nenhum.
-- Idempotente.
-- =========================================================

SET lock_timeout = '10s';

-- ── Módulo (submódulo de Documentos & Governança) ──
DO $doc$
DECLARE v_sec uuid; v_mod uuid;
BEGIN
  SELECT id INTO v_sec FROM public.qa_modulos WHERE path = 'documentos-governanca';
  IF v_sec IS NULL THEN RAISE EXCEPTION 'Seção documentos-governanca não encontrada.'; END IF;

  INSERT INTO public.qa_modulos (parent_id, label, path, ordem)
  VALUES (v_sec, 'Assinatura forte (fundação)', 'documentos-governanca/assinatura', 3)
  ON CONFLICT (path) DO NOTHING;

  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'documentos-governanca/assinatura';

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
   'positivo', 'alta', 'aprovado', 'api',
   'LGPD art. 11, I (consentimento específico e destacado para dado sensível) e art. 9º (finalidade); Lei 14.063/2020, art. 4º',
   'Antes de ligar a câmera, o aceite do consentimento é gravado com quem/quando/qual versão do texto; o IP vem do servidor, não do corpo; sem aceite, o registro é recusado.',
   'Cercado de teste (sandbox).',
   '[{"ordem":1,"acao":"Registrar o consentimento aceito com cabeçalho de IP e um IP falso no corpo","resultado_esperado":"linha gravada; ip_address do cabeçalho; versão do texto preservada"},
     {"ordem":2,"acao":"Tentar registrar sem aceite (aceito=false)","resultado_esperado":"recusado com erro claro"}]'::jsonb,
   'Consentimento fica na trilha com a versão aceita e a origem do servidor; sem aceite, não grava.',
   'Lacuna LGPD que não existia. A tela é src/components/assinatura/ConsentimentoBiometrico.tsx; a versão do texto é VERSAO_CONSENTIMENTO_BIOMETRICO (src/lib/assinaturaConsentimento.ts).'),
  (v_mod, 'ASS-003',
   'O arquivo canônico no servidor resolve a pasta do colaborador, grava em documentos e registra a auditoria',
   'positivo', 'alta', 'aprovado', 'api',
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
