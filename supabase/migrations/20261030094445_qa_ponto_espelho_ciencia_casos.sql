-- ============================================================================
-- QA — ESPELHO DE PONTO, Fatia 0: ciência do colaborador (casos api)
--
--   ESP-CIE-001  ciência em papel exige anexo, grava papel_digitalizado e nunca o id do RH
--   ESP-CIE-002  pela API, ninguém grava ciência direto no espelho (gatilho de guarda)
--   ESP-CIE-003  reabrir arquiva todos no histórico, retira só os sem ciência e
--                preserva os que têm ciência
--
-- Rotinas no cercado (tenant sandbox), desfeitas pelo motor ao fim
-- (qa_executar_descartavel). Atribuição por subconsulta escalar, sem SELECT INTO
-- (padrão do SQL Editor de produção). Idempotente.
-- ============================================================================

SET lock_timeout = '10s';

-- Ajudante: um espelho de teste no cercado (sem claims: o gatilho não vigia).
CREATE OR REPLACE FUNCTION public.qa_esp_espelho(
  p_competencia text, p_semente int, p_status text DEFAULT 'gerado', p_origem text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO public.ponto_espelhos
    (id, tenant_id, colaborador_id, colaborador_nome, colaborador_cpf, competencia,
     status, ciencia_origem, data_confirmacao, confirmado_por)
  VALUES (v_id, public.qa_sandbox_tenant_id(), gen_random_uuid()::text,
          '[QA-ESP] Colaborador ' || p_semente, public.qa_cpf(p_semente), p_competencia,
          p_status, p_origem,
          CASE WHEN p_origem IS NULL THEN NULL ELSE now() END,
          CASE WHEN p_origem IS NULL THEN NULL ELSE 'colaborador' END);
  RETURN v_id;
END $fn$;

-- Ajudante: usuário de RH (papel de gestão) no cercado, com as claims ligadas.
CREATE OR REPLACE FUNCTION public.qa_esp_rh_logado()
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v_uid uuid;
BEGIN
  v_uid := public.qa_mky_usuario_empresa(public.qa_sandbox_tenant_id(), 'esp-rh');
  INSERT INTO public.user_roles (user_id, role) VALUES (v_uid, 'manager') ON CONFLICT DO NOTHING;
  PERFORM public.qa_mky_claims(v_uid);
  RETURN v_uid;
END $fn$;

-- ── ESP-CIE-001 ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_esp_cie_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_claims text := current_setting('request.jwt.claims', true);
  v_esp uuid; v_doc uuid; v_uid uuid;
  v_sem_anexo jsonb; v_ok jsonb; v_row jsonb;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_esp := public.qa_esp_espelho('2099-01', 901);
  v_doc := public.qa_novo_documento('qa-esp-cie-001-papel.pdf');
  UPDATE public.documentos SET colaborador_cpf = public.qa_cpf(901) WHERE id = v_doc;

  r.passo_ordem := 1;
  r.passo_acao := 'RH registra a ciência em papel SEM anexo';
  r.esperado := 'Recusado: anexo_obrigatorio';
  v_uid := public.qa_esp_rh_logado();
  v_sem_anexo := public.ponto_espelho_registrar_ciencia_papel(v_esp, NULL, NULL);

  r.passo_ordem := 2;
  r.passo_acao := 'RH registra a ciência em papel COM o papel digitalizado anexado';
  r.esperado := 'Gravado: status confirmado, ciencia_origem papel_digitalizado, confirmado_por colaborador (não o id do RH)';
  v_ok := public.ponto_espelho_registrar_ciencia_papel(v_esp, v_doc, NULL);
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  v_row := (SELECT to_jsonb(e) FROM public.ponto_espelhos e WHERE e.id = v_esp);

  IF COALESCE(v_sem_anexo->>'erro', '') <> 'anexo_obrigatorio' THEN
    r.situacao := 'falhou'; r.obtido := 'Sem anexo devia ser recusado e veio: ' || COALESCE(v_sem_anexo::text, 'nulo');
  ELSIF NOT COALESCE((v_ok->>'ok')::boolean, false) THEN
    r.situacao := 'falhou'; r.obtido := 'Com anexo devia gravar e veio: ' || COALESCE(v_ok::text, 'nulo');
  ELSIF (v_row->>'status') <> 'confirmado' OR (v_row->>'ciencia_origem') IS DISTINCT FROM 'papel_digitalizado' THEN
    r.situacao := 'falhou'; r.obtido := format('Status %s, origem %s', v_row->>'status', v_row->>'ciencia_origem');
  ELSIF (v_row->>'confirmado_por') = v_uid::text OR (v_row->>'confirmado_por') IS DISTINCT FROM 'colaborador' THEN
    r.situacao := 'falhou'; r.obtido := 'confirmado_por ficou com ' || COALESCE(v_row->>'confirmado_por', 'nulo') || ' (não pode ser o id do RH)';
  ELSIF (v_row->>'arquivo_url') IS NULL THEN
    r.situacao := 'falhou'; r.obtido := 'O caminho do papel anexado não foi gravado no espelho';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Sem anexo recusado; com anexo gravou papel_digitalizado, confirmado_por=colaborador e o caminho do papel.';
  END IF;
  r.detalhe := jsonb_build_object('sem_anexo', v_sem_anexo, 'com_anexo', v_ok);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  BEGIN PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); EXCEPTION WHEN OTHERS THEN NULL; END;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── ESP-CIE-002 ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_esp_cie_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_claims text := current_setting('request.jwt.claims', true);
  v_esp uuid; v_uid uuid;
  v_bloqueou_confirmar boolean := false;
  v_bloqueou_ressalva boolean := false;
  v_enviado_ok boolean := false;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_esp := public.qa_esp_espelho('2099-02', 902);
  v_uid := public.qa_esp_rh_logado();

  r.passo_ordem := 1;
  r.passo_acao := 'Pela API, o RH grava status confirmado e o próprio id em confirmado_por';
  r.esperado := 'Recusado pelo gatilho de guarda';
  BEGIN
    UPDATE public.ponto_espelhos SET status = 'confirmado', confirmado_por = v_uid::text,
           data_confirmacao = now() WHERE id = v_esp;
  EXCEPTION WHEN insufficient_privilege THEN v_bloqueou_confirmar := true;
  END;

  r.passo_ordem := 2;
  r.passo_acao := 'Pela API, o RH grava só uma ressalva (o que liberaria o portão)';
  r.esperado := 'Recusado pelo gatilho de guarda';
  BEGIN
    UPDATE public.ponto_espelhos SET ressalva_texto = 'qa' WHERE id = v_esp;
  EXCEPTION WHEN insufficient_privilege THEN v_bloqueou_ressalva := true;
  END;

  r.passo_ordem := 3;
  r.passo_acao := 'Pela API, mudar de gerado para enviado';
  r.esperado := 'Permitido (não é ciência)';
  BEGIN
    UPDATE public.ponto_espelhos SET status = 'enviado' WHERE id = v_esp;
    v_enviado_ok := true;
  EXCEPTION WHEN OTHERS THEN v_enviado_ok := false;
  END;
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);

  IF NOT v_bloqueou_confirmar THEN
    r.situacao := 'falhou'; r.obtido := 'O RH conseguiu confirmar o espelho direto pela API (ciência forjada).';
  ELSIF NOT v_bloqueou_ressalva THEN
    r.situacao := 'falhou'; r.obtido := 'O RH conseguiu gravar ressalva direto pela API (liberaria o portão do fechamento).';
  ELSIF NOT v_enviado_ok THEN
    r.situacao := 'falhou'; r.obtido := 'A troca gerado -> enviado foi bloqueada, mas não é ciência.';
  ELSE
    r.situacao := 'passou'; r.obtido := 'Ciência direta recusada (confirmar e ressalva); gerado -> enviado segue livre.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  BEGIN PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); EXCEPTION WHEN OTHERS THEN NULL; END;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── ESP-CIE-003 ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_esp_cie_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_sem uuid; v_com uuid; v_res jsonb;
  v_hist int; v_sem_existe boolean; v_com_status text; v_fech_status text;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM set_config('request.jwt.claims', '', true);
  INSERT INTO public.ponto_fechamentos (tenant_id, empresa_id, competencia, status, data_fechamento)
  VALUES (v_t, NULL, '2099-03', 'fechado', now());
  v_sem := public.qa_esp_espelho('2099-03', 903);
  v_com := public.qa_esp_espelho('2099-03', 904, 'confirmado', 'papel_digitalizado');

  r.passo_ordem := 1;
  r.passo_acao := 'Reabrir a competência fechada com motivo';
  r.esperado := 'ok; 2 espelhos no histórico; 1 sem ciência retirado; o com ciência fica; fechamento reaberto';
  v_res := public.ponto_reabrir_competencia(v_t, NULL, '2099-03', '[QA] apuração corrigida', 'qa', 'QA');

  v_hist := (SELECT count(*) FROM public.ponto_espelhos_historico
              WHERE tenant_id = v_t AND competencia = '2099-03');
  v_sem_existe := EXISTS (SELECT 1 FROM public.ponto_espelhos WHERE id = v_sem);
  v_com_status := (SELECT status FROM public.ponto_espelhos WHERE id = v_com);
  v_fech_status := (SELECT status FROM public.ponto_fechamentos
                     WHERE tenant_id = v_t AND competencia = '2099-03' LIMIT 1);

  IF NOT COALESCE((v_res->>'ok')::boolean, false) THEN
    r.situacao := 'falhou'; r.obtido := 'A reabertura foi recusada: ' || COALESCE(v_res::text, 'nulo');
  ELSIF v_hist < 2 THEN
    r.situacao := 'falhou'; r.obtido := format('Só %s espelho(s) no histórico; os 2 deviam ser arquivados', v_hist);
  ELSIF v_sem_existe THEN
    r.situacao := 'falhou'; r.obtido := 'O espelho sem ciência continuou na competência (travaria o refechamento)';
  ELSIF COALESCE(v_com_status, '') <> 'confirmado' THEN
    r.situacao := 'falhou'; r.obtido := 'O espelho COM ciência foi apagado ou perdeu a ciência (status ' || COALESCE(v_com_status, 'apagado') || ')';
  ELSIF COALESCE(v_fech_status, '') <> 'reaberto' THEN
    r.situacao := 'falhou'; r.obtido := 'O fechamento não ficou reaberto (status ' || COALESCE(v_fech_status, 'nulo') || ')';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Histórico com a versão anterior; espelho sem ciência retirado; ciência preservada; competência reaberta.';
  END IF;
  r.detalhe := v_res;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- Documentação dos casos + implementações
DO $doc$
DECLARE v_mod uuid;
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL OR to_regclass('public.qa_modulos') IS NULL THEN
    RAISE NOTICE 'Motor de QA ausente; casos ESP-CIE não documentados.';
    RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'jornada-rotina/ponto' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo jornada-rotina/ponto ausente; casos ESP-CIE não documentados.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'ESP-CIE-001',
   'Ciência do espelho em papel: exige o papel assinado anexado e nunca grava o RH como quem deu ciência',
   'negativo', 'critica', 'aprovado', 'api',
   'Súmula 338 do TST (o controle é prova do empregador; a ciência tem de ser do trabalhador); CLT art. 74, §2º',
   'O antigo botão Confirmar gravava o id do usuário do RH em confirmado_por: a ciência era do RH, não do colaborador. Agora o RH só registra a ciência que o colaborador deu no PAPEL, anexando a digitalização.',
   'Cercado de QA; usuário de RH com papel de gestão.',
   '[{"ordem":1,"acao":"Registrar ciência em papel sem anexo","resultado_esperado":"Recusado (anexo_obrigatorio)"},
     {"ordem":2,"acao":"Registrar com o papel digitalizado arquivado em Documentos","resultado_esperado":"status confirmado; ciencia_origem papel_digitalizado; confirmado_por = colaborador; arquivo_url = caminho do papel"}]'::jsonb,
   'Só papel anexado vira ciência; o id do RH nunca ocupa o lugar da assinatura.',
   'Fatia 0 do espelho com assinatura (30/10/2026). Quem registrou fica em ponto_audit_log.'),
  (v_mod, 'ESP-CIE-002',
   'Pela API, ninguém grava ciência direto no espelho de ponto',
   'negativo', 'critica', 'aprovado', 'api',
   'Súmula 338 do TST; LGPD art. 6º, X (prestação de contas)',
   'A política de escrita do espelho deixava qualquer gestor mudar status, ressalva e confirmado_por pela API, liberando o portão do fechamento sem ciência real. O gatilho de guarda só aceita essas mudanças vindas das funções do servidor.',
   'Cercado de QA; usuário de RH com papel de gestão.',
   '[{"ordem":1,"acao":"UPDATE status=confirmado + confirmado_por=id do RH, como authenticated","resultado_esperado":"Recusado"},
     {"ordem":2,"acao":"UPDATE só da ressalva_texto, como authenticated","resultado_esperado":"Recusado"},
     {"ordem":3,"acao":"UPDATE de gerado para enviado","resultado_esperado":"Permitido"}]'::jsonb,
   'Ciência só pelo servidor; gerado/enviado livre.',
   'Gatilho trg_ponto_espelho_ciencia_guarda (ponto_espelho_ciencia_guarda).'),
  (v_mod, 'ESP-CIE-003',
   'Reabrir a competência arquiva os espelhos no histórico, retira só os sem ciência e preserva a ciência dada',
   'feliz', 'alta', 'aprovado', 'api',
   'Súmula 338 do TST (o documento cientificado não pode ser regravado por cima)',
   'A tela apagava pelo navegador os espelhos gerado/enviado, sem histórico. A reabertura passa a ser a função do servidor (PONTO-358): versão N no histórico, retirada só do que ainda não tem ciência (senão o refechamento travaria no portão) e a ciência dada permanece.',
   'Cercado de QA; competência fechada com um espelho sem ciência e um com ciência.',
   '[{"ordem":1,"acao":"ponto_reabrir_competencia com motivo","resultado_esperado":"ok; 2 linhas no histórico; o sem ciência sai; o com ciência fica confirmado; fechamento reaberto"}]'::jsonb,
   'Reabertura com histórico e ciência preservada.',
   'O refechamento pela tela não manda mais status no upsert do espelho (não sobrescreve a ciência).')
  ON CONFLICT (codigo) DO UPDATE SET
    modulo_id = EXCLUDED.modulo_id, titulo = EXCLUDED.titulo, objetivo = EXCLUDED.objetivo,
    passos = EXCLUDED.passos, resultado_esperado = EXCLUDED.resultado_esperado,
    base_legal = EXCLUDED.base_legal, observacoes = EXCLUDED.observacoes, status = 'aprovado';

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
      ('ESP-CIE-001', 'qa_caso_esp_cie_001', true),
      ('ESP-CIE-002', 'qa_caso_esp_cie_002', true),
      ('ESP-CIE-003', 'qa_caso_esp_cie_003', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentação ESP-CIE não registrada: %', SQLERRM;
END $doc$;
