-- =========================================================
-- ASS-0001 — FASE 0: QA da fundação — script de ENTREGA (SQL Editor homolog/prod).
--
-- Documenta e implementa os casos api ASS-001/002/003, roda a bateria do módulo
-- documentos-governanca/assinatura e mostra o resultado. Rode DEPOIS do
-- script_ass0001_fundacao.sql (precisa das funções/tabelas já criadas).
-- NÃO cria tabela (logo, sem a pegadinha do auto-RLS); idempotente.
-- =========================================================

SET lock_timeout = '10s';

-- ── Módulo + casos ──
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
   'Lei 14.063/2020, art. 4º; MP 2.200-2/2001, art. 10, §2º; LGPD art. 6º, X',
   'selar_assinatura gera hash determinístico e sensível; selar_assinatura_origem prefere cf-connecting-ip, cai para o primeiro x-forwarded-for, e sem cabeçalhos devolve IP/UA nulos — hora sempre do servidor.',
   'Nenhuma: funções puras/do servidor.',
   '[{"ordem":1,"acao":"Selar 2x igual e 1x diferente","resultado_esperado":"64 hex; iguais p/ igual; diferente p/ conteúdo diferente"},
     {"ordem":2,"acao":"Origem com cf-connecting-ip + x-forwarded-for","resultado_esperado":"IP = cf-connecting-ip"},
     {"ordem":3,"acao":"Origem só com x-forwarded-for","resultado_esperado":"IP = primeiro da lista"},
     {"ordem":4,"acao":"Origem sem cabeçalhos","resultado_esperado":"IP/UA nulos; hora presente"}]'::jsonb,
   'Hash e origem são do servidor; o navegador não prevalece.',
   'Coração do avançada forte. Espelha os gatilhos do EPI (20261022203847 e 20261022213306).'),
  (v_mod, 'ASS-002',
   'O consentimento biométrico (LGPD art. 11) é registrado na trilha com origem do servidor e exige aceite',
   'positivo', 'alta', 'aprovado', 'api',
   'LGPD art. 11, I e art. 9º; Lei 14.063/2020, art. 4º',
   'O aceite é gravado com quem/quando/qual versão; IP do servidor; sem aceite, recusa.',
   'Cercado de teste (sandbox).',
   '[{"ordem":1,"acao":"Registrar aceito com IP no cabeçalho e IP falso no corpo","resultado_esperado":"linha gravada; ip do cabeçalho; versão preservada"},
     {"ordem":2,"acao":"Tentar sem aceite","resultado_esperado":"recusado"}]'::jsonb,
   'Consentimento na trilha com versão e origem do servidor; sem aceite não grava.',
   'Tela: src/components/assinatura/ConsentimentoBiometrico.tsx; versão em src/lib/assinaturaConsentimento.ts.'),
  (v_mod, 'ASS-003',
   'O arquivo canônico no servidor resolve a pasta do colaborador, grava em documentos e registra a auditoria',
   'positivo', 'alta', 'aprovado', 'api',
   'LGPD art. 6º, X; boa governança documental',
   'Um só caminho de arquivamento no servidor em vez de inserts divergentes por edge.',
   'Cercado de teste (sandbox).',
   '[{"ordem":1,"acao":"Arquivar documento de colaborador pelo servidor","resultado_esperado":"id e pasta_id; nome_arquivo = storage_path; pasta resolvida"},
     {"ordem":2,"acao":"Conferir auditoria","resultado_esperado":"documento_audit_logs tem a linha de upload"}]'::jsonb,
   'Documento na pasta certa, colunas canônicas, com auditoria.',
   'Espelha src/utils/arquivarDocumento.ts; o upload do binário fica na camada Deno/cliente.')
  ON CONFLICT (codigo) DO UPDATE SET
    modulo_id = EXCLUDED.modulo_id, titulo = EXCLUDED.titulo, objetivo = EXCLUDED.objetivo,
    passos = EXCLUDED.passos, resultado_esperado = EXCLUDED.resultado_esperado,
    base_legal = EXCLUDED.base_legal, observacoes = EXCLUDED.observacoes, status = 'aprovado';
END $doc$;

-- ── Rotinas ──
CREATE OR REPLACE FUNCTION public.qa_caso_ass_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_h1 text; v_h2 text; v_h3 text; v_o1 jsonb; v_o2 jsonb; v_o3 jsonb;
BEGIN
  r.passo_ordem := 1; r.passo_acao := 'Selar a mesma assinatura 2x e uma 3ª diferente';
  r.esperado := 'hash de 64 hex; determinístico; sensível ao conteúdo';
  v_h1 := public.selar_assinatura('doc-abc', 'colab assinou', '2026-01-02T03:04:05.678Z'::timestamptz, 'id-1');
  v_h2 := public.selar_assinatura('doc-abc', 'colab assinou', '2026-01-02T03:04:05.678Z'::timestamptz, 'id-1');
  v_h3 := public.selar_assinatura('doc-XYZ', 'colab assinou', '2026-01-02T03:04:05.678Z'::timestamptz, 'id-1');
  PERFORM set_config('request.headers', '{"cf-connecting-ip":"203.0.113.7","x-forwarded-for":"198.51.100.9, 10.0.0.1","user-agent":"qa-agente"}', true);
  v_o1 := public.selar_assinatura_origem();
  PERFORM set_config('request.headers', '{"x-forwarded-for":"198.51.100.9, 10.0.0.1"}', true);
  v_o2 := public.selar_assinatura_origem();
  PERFORM set_config('request.headers', '', true);
  v_o3 := public.selar_assinatura_origem();
  IF v_h1 !~ '^[0-9a-f]{64}$' THEN r.situacao := 'falhou'; r.obtido := format('hash fora do formato: %s', v_h1);
  ELSIF v_h1 IS DISTINCT FROM v_h2 THEN r.situacao := 'falhou'; r.obtido := 'não determinístico';
  ELSIF v_h1 = v_h3 THEN r.situacao := 'falhou'; r.obtido := 'conteúdo diferente, mesmo hash';
  ELSIF (v_o1->>'ip_address') IS DISTINCT FROM '203.0.113.7' THEN r.situacao := 'falhou'; r.obtido := 'cf-connecting-ip não prevaleceu';
  ELSIF (v_o1->>'user_agent') IS DISTINCT FROM 'qa-agente' THEN r.situacao := 'falhou'; r.obtido := 'user-agent não registrado';
  ELSIF (v_o2->>'ip_address') IS DISTINCT FROM '198.51.100.9' THEN r.situacao := 'falhou'; r.obtido := 'x-forwarded-for não deu o primeiro endereço';
  ELSIF (v_o3->>'ip_address') IS NOT NULL OR (v_o3->>'user_agent') IS NOT NULL THEN r.situacao := 'falhou'; r.obtido := 'sem cabeçalhos devia dar nulo';
  ELSIF (v_o3->>'assinado_em') IS NULL THEN r.situacao := 'falhou'; r.obtido := 'hora do servidor ausente';
  ELSE r.situacao := 'passou'; r.obtido := 'hash e origem do servidor; corpo não prevalece';
  END IF;
  r.detalhe := jsonb_build_object('h1', v_h1, 'h3', v_h3, 'o1', v_o1, 'o2', v_o2, 'o3', v_o3);
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_ass_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_res jsonb; v_id uuid; v_row jsonb; v_recusou boolean := false;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem := 1; r.passo_acao := 'Registrar consentimento aceito, IP no cabeçalho e falso no corpo';
  r.esperado := 'linha gravada; ip do cabeçalho; versão preservada';
  PERFORM set_config('request.headers', '{"cf-connecting-ip":"203.0.113.50","user-agent":"qa-consent"}', true);
  v_res := public.registrar_consentimento_biometrico(jsonb_build_object(
    'tenant_id', v_t, 'contexto', 'advertencia', 'documento_ref', 'qa-doc-002',
    'signatario_nome', 'QA Signatário 002', 'signatario_cpf', public.qa_cpf(2),
    'finalidade', 'Confirmar a identidade na assinatura deste documento',
    'versao_texto', 'consentimento-biometrico-v1', 'aceito', true, 'ip_address', '1.1.1.1'));
  v_id := (v_res->>'id')::uuid;
  v_row := (SELECT to_jsonb(c) FROM public.consentimentos_assinatura c WHERE c.id = v_id);
  r.passo_ordem := 2; r.passo_acao := 'Tentar sem aceite (aceito=false)';
  BEGIN
    PERFORM public.registrar_consentimento_biometrico(jsonb_build_object('tenant_id', v_t, 'finalidade', 'x', 'versao_texto', 'v1', 'aceito', false));
  EXCEPTION WHEN OTHERS THEN v_recusou := true; END;
  IF v_row IS NULL THEN r.situacao := 'falhou'; r.obtido := 'consentimento aceito não gravado';
  ELSIF (v_row->>'ip_address') IS DISTINCT FROM '203.0.113.50' THEN r.situacao := 'falhou'; r.obtido := 'ip do corpo prevaleceu sobre o do cabeçalho';
  ELSIF (v_row->>'versao_texto') IS DISTINCT FROM 'consentimento-biometrico-v1' THEN r.situacao := 'falhou'; r.obtido := 'versão não preservada';
  ELSIF NOT v_recusou THEN r.situacao := 'falhou'; r.obtido := 'registro sem aceite não foi recusado';
  ELSE r.situacao := 'passou'; r.obtido := 'gravado com versão e IP do servidor; sem aceite recusado';
  END IF;
  r.detalhe := jsonb_build_object('registro', v_row, 'recusou_sem_aceite', v_recusou);
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_ass_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_colab uuid := gen_random_uuid();
        v_res jsonb; v_doc_id uuid; v_pasta uuid; v_doc jsonb; v_tem_audit boolean;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM set_config('request.headers', '', true);
  r.passo_ordem := 1; r.passo_acao := 'Arquivar documento de colaborador pelo servidor';
  r.esperado := 'id e pasta_id; nome_arquivo = storage; pasta resolvida';
  v_res := public.arquivar_documento_servidor(jsonb_build_object(
    'tenant_id', v_t, 'user_nome', 'QA Sistema', 'colaborador_id', v_colab::text,
    'colaborador_nome', 'QA Colaborador 003', 'colaborador_cpf', public.qa_cpf(3),
    'storage_path', v_t::text || '/colaboradores/' || v_colab::text || '/qa-advertencia-003.pdf',
    'file_name', 'advertencia-003.pdf', 'tipo', 'advertencia', 'mime_type', 'application/pdf', 'tamanho', 2048));
  v_doc_id := (v_res->>'id')::uuid; v_pasta := (v_res->>'pasta_id')::uuid;
  v_doc := (SELECT to_jsonb(d) FROM public.documentos d WHERE d.id = v_doc_id);
  r.passo_ordem := 2; r.passo_acao := 'Conferir auditoria';
  v_tem_audit := EXISTS (SELECT 1 FROM public.documento_audit_logs WHERE documento_id = v_doc_id AND acao = 'upload');
  IF v_doc IS NULL THEN r.situacao := 'falhou'; r.obtido := 'documento não gravado';
  ELSIF v_pasta IS NULL OR (v_doc->>'pasta_id') IS NULL THEN r.situacao := 'falhou'; r.obtido := 'pasta do colaborador não resolvida';
  ELSIF (v_doc->>'nome_arquivo') IS DISTINCT FROM (v_doc->>'storage_path') THEN r.situacao := 'falhou'; r.obtido := 'colunas divergentes (nome_arquivo <> storage_path)';
  ELSIF NOT v_tem_audit THEN r.situacao := 'falhou'; r.obtido := 'auditoria não gravada';
  ELSE r.situacao := 'passou'; r.obtido := format('documento %s na pasta %s com auditoria', v_doc_id, v_pasta);
  END IF;
  r.detalhe := jsonb_build_object('retorno', v_res, 'tem_audit', v_tem_audit, 'pasta_id', v_pasta);
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES
  ('ASS-001', 'qa_caso_ass_001'), ('ASS-002', 'qa_caso_ass_002'), ('ASS-003', 'qa_caso_ass_003')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- ── Rodar a bateria do módulo ──
DO $roda$ BEGIN PERFORM public.qa_rodar_bateria('manual', 'documentos-governanca/assinatura'); END $roda$;

-- ── CONFERÊNCIA (o editor mostra só o último resultado) ──
SELECT codigo, situacao::text AS situacao, left(obtido, 80) AS resultado, erro_tecnico
FROM public.qa_resultados
WHERE execucao_id = (SELECT id FROM public.qa_execucoes ORDER BY iniciada_em DESC LIMIT 1)
ORDER BY codigo;
