-- ============================================================================
-- ESPELHO DE PONTO COM ASSINATURA ELETRÔNICA — Fatia 1, PARTE 4 de 4 (testes)
-- Cole INTEIRO no SQL Editor, depois da parte 3.
-- Equivale à migration 20261030100820_qa_assinatura_espelho_casos.sql: casos
-- ESP-ASS-001..016, rotinas qa_caso_esp_ass_* e pontes do Cypress.
-- ============================================================================

SET lock_timeout = '10s';

-- ── Ajudantes ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_esp_como_servico()
RETURNS void LANGUAGE sql AS $fn$
  SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
$fn$;

-- Cenário: colaborador ativo com e-mail, competência fechada, espelho e
-- solicitação enviada com token. Devolve os ids.
CREATE OR REPLACE FUNCTION public.qa_esp_ass_cenario(p_comp text, p_semente int, p_fechar boolean DEFAULT true)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE
  v_t   uuid := public.qa_sandbox_tenant_id();
  v_cpf text;
  v_adm uuid;
  v_esp uuid := gen_random_uuid();
  v_sol uuid := gen_random_uuid();
  v_res jsonb;
  v_tok jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  v_cpf := public.qa_ponto_admissao('[QA-ESP-ASS] Colaborador ' || p_semente, p_semente);
  v_adm := (SELECT a.id FROM public.admissoes a WHERE a.tenant_id = v_t AND a.cpf = v_cpf
             ORDER BY (a.status::text = 'concluido') DESC LIMIT 1);
  IF p_fechar AND NOT EXISTS (SELECT 1 FROM public.ponto_fechamentos f
                               WHERE f.tenant_id = v_t AND f.competencia = p_comp AND f.empresa_id IS NULL) THEN
    INSERT INTO public.ponto_fechamentos (tenant_id, empresa_id, competencia, status, data_fechamento)
    VALUES (v_t, NULL, p_comp, 'fechado', now());
  END IF;
  INSERT INTO public.ponto_espelhos (id, tenant_id, colaborador_id, colaborador_nome, colaborador_cpf, competencia)
  VALUES (v_esp, v_t, v_adm::text, '[QA-ESP-ASS] Colaborador ' || p_semente, v_cpf, p_comp);

  PERFORM public.qa_esp_como_servico();
  v_res := public.assinatura_criar_solicitacao(jsonb_build_object(
    'id', v_sol, 'tenant_id', v_t, 'contexto', 'ponto_espelho', 'documento_ref_id', v_esp,
    'colaborador_id', v_adm, 'colaborador_cpf', v_cpf, 'colaborador_nome', '[QA-ESP-ASS] Colaborador ' || p_semente,
    'email', 'qa-esp-ass-' || p_semente || '@sandbox.invalid',
    'original_path', v_t::text || '/ponto_espelho/' || v_sol::text || '/original.pdf',
    'original_sha256', encode(public.digest('qa-original-' || v_sol::text, 'sha256'), 'hex'),
    'original_bytes', 1000, 'link_base', 'https://youreyes.com.br/'));
  IF COALESCE((v_res->>'ok')::boolean, false) THEN
    PERFORM public.assinatura_registrar_envio(v_sol, 'solicitacao', true);
    v_tok := public.assinatura_emitir_token(v_sol);
  END IF;
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN jsonb_build_object('espelho_id', v_esp, 'solicitacao_id', v_sol, 'cpf', v_cpf,
                            'admissao_id', v_adm, 'criar', v_res, 'token', v_tok->>'token');
END $fn$;

-- Leva a solicitação até "pronta para assinar": CPF, código e (opcional) prova de vida.
CREATE OR REPLACE FUNCTION public.qa_esp_ass_autenticar(p_sol uuid, p_cpf text, p_prova_vida text DEFAULT 'camera')
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE v_hash text := encode(public.digest(p_sol::text || ':123456', 'sha256'), 'hex');
BEGIN
  PERFORM public.qa_esp_como_servico();
  PERFORM public.assinatura_cpf_conferir(p_sol, p_cpf);
  PERFORM public.assinatura_otp_registrar(p_sol, v_hash, 'email', 'q***@sandbox.invalid');
  PERFORM public.assinatura_otp_validar(p_sol, v_hash);
  IF p_prova_vida = 'camera' THEN
    PERFORM public.assinatura_registrar_consentimento(p_sol, jsonb_build_object(
      'finalidade', 'Confirmar a identidade na assinatura', 'versao_texto', 'consentimento-biometrico-v1'));
    PERFORM public.assinatura_registrar_evidencia(p_sol, jsonb_build_object(
      'metodo_liveness', 'face-landmarker', 'versao_detector', 'qa',
      'frames_refs', jsonb_build_array('qa/quadro-1.jpg', 'qa/quadro-2.jpg')));
  ELSIF p_prova_vida = 'recusou' THEN
    PERFORM public.assinatura_registrar_consentimento(p_sol, jsonb_build_object('recusou', true,
      'versao_texto', 'consentimento-biometrico-v1'));
  END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_esp_ass_concluir(p_sol uuid, p_decisao text, p_texto text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE v_t uuid := public.qa_sandbox_tenant_id(); v_res jsonb;
BEGIN
  PERFORM public.qa_esp_como_servico();
  v_res := public.assinatura_concluir(jsonb_build_object(
    'solicitacao_id', p_sol, 'decisao', p_decisao, 'texto', p_texto,
    'assinado_path', v_t::text || '/ponto_espelho/' || p_sol::text || '/assinado.pdf',
    'assinado_sha256', encode(public.digest('qa-assinado-' || p_sol::text, 'sha256'), 'hex'),
    'assinado_bytes', 2000,
    'documento_storage_path', v_t::text || '/colaboradores/qa/' || p_sol::text || '_assinado.pdf',
    'nome_arquivo', 'Espelho de Ponto assinado - QA.pdf',
    'origem', jsonb_build_object('ip', '203.0.113.9', 'user_agent', 'qa-esp-ass', 'assinado_em', now())));
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN v_res;
END $fn$;

-- ── ESP-ASS-001 ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_esp_ass_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_c jsonb;
        v_sem_hash jsonb; v_dupla jsonb; v_aberta jsonb; v_c2 jsonb;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem := 1; r.passo_acao := 'Criar a solicitação de um espelho de competência fechada';
  r.esperado := 'Criada (na_fila) e o espelho passa a enviado';
  v_c := public.qa_esp_ass_cenario('2099-04', 911);

  r.passo_ordem := 2; r.passo_acao := 'Criar sem o hash do PDF congelado; criar uma segunda ativa; criar com competência aberta';
  r.esperado := 'hash_obrigatorio; ja_existe_ativa; competencia_nao_fechada';
  PERFORM public.qa_esp_como_servico();
  v_sem_hash := public.assinatura_criar_solicitacao(jsonb_build_object(
    'tenant_id', v_t, 'documento_ref_id', v_c->>'espelho_id', 'colaborador_cpf', v_c->>'cpf',
    'original_path', 'x/original.pdf', 'original_sha256', 'abc'));
  v_dupla := public.assinatura_criar_solicitacao(jsonb_build_object(
    'tenant_id', v_t, 'documento_ref_id', v_c->>'espelho_id', 'colaborador_cpf', v_c->>'cpf',
    'original_path', 'x/original.pdf', 'original_sha256', repeat('a', 64)));
  PERFORM set_config('request.jwt.claims', '', true);
  v_c2 := public.qa_esp_ass_cenario('2099-05', 912, false);
  v_aberta := v_c2->'criar';

  IF NOT COALESCE((v_c->'criar'->>'ok')::boolean, false) THEN
    r.situacao := 'falhou'; r.obtido := 'A solicitação válida não foi criada: ' || COALESCE((v_c->'criar')::text, 'nulo');
  ELSIF (SELECT status FROM public.ponto_espelhos WHERE id = (v_c->>'espelho_id')::uuid) <> 'enviado' THEN
    r.situacao := 'falhou'; r.obtido := 'O espelho não passou a enviado';
  ELSIF COALESCE(v_sem_hash->>'erro', '') <> 'hash_obrigatorio' THEN
    r.situacao := 'falhou'; r.obtido := 'Sem hash devia recusar e veio ' || v_sem_hash::text;
  ELSIF COALESCE(v_dupla->>'erro', '') <> 'ja_existe_ativa' THEN
    r.situacao := 'falhou'; r.obtido := 'A segunda ativa devia ser recusada e veio ' || v_dupla::text;
  ELSIF COALESCE(v_aberta->>'erro', '') <> 'competencia_nao_fechada' THEN
    r.situacao := 'falhou'; r.obtido := 'Competência aberta devia ser recusada e veio ' || COALESCE(v_aberta::text, 'nulo');
  ELSE
    r.situacao := 'passou'; r.obtido := 'Exige hash, uma ativa por documento e competência fechada.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── ESP-ASS-002 ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_esp_ass_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_c jsonb; v_sol text; v_rh uuid; v_fora uuid;
        v_ve_rh bigint; v_ve_fora bigint; v_ve_anon bigint; v_otp_rh bigint;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_c := public.qa_esp_ass_cenario('2099-06', 913);
  v_sol := v_c->>'solicitacao_id';
  IF to_regprocedure('qa_rls.conta_auth(text)') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Faltam os ajudantes qa_rls para a prova funcional.'; RETURN r;
  END IF;

  r.passo_ordem := 1; r.passo_acao := 'RH da empresa conta a solicitação';
  r.esperado := '1';
  v_rh := public.qa_esp_rh_logado();
  v_ve_rh := qa_rls.conta_auth(format('SELECT count(*) FROM public.assinatura_solicitacoes WHERE id = %L', v_sol));
  v_otp_rh := qa_rls.conta_auth(format('SELECT count(*) FROM public.assinatura_otps WHERE solicitacao_id = %L', v_sol));

  r.passo_ordem := 2; r.passo_acao := 'Usuário de fora da empresa e anônimo contam a solicitação';
  r.esperado := '0 (ou sem permissão)';
  v_fora := gen_random_uuid();
  INSERT INTO auth.users (id, email) VALUES (v_fora, 'qa-esp-fora-' || left(v_fora::text, 8) || '@sandbox.invalid');
  PERFORM public.qa_mky_claims(v_fora);
  v_ve_fora := qa_rls.conta_auth(format('SELECT count(*) FROM public.assinatura_solicitacoes WHERE id = %L', v_sol));
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  v_ve_anon := qa_rls.conta_anon(format('SELECT count(*) FROM public.assinatura_solicitacoes WHERE id = %L', v_sol));
  PERFORM set_config('request.jwt.claims', '', true);

  IF v_ve_rh <> 1 THEN
    r.situacao := 'falhou'; r.obtido := format('O RH da empresa viu %s (devia ver 1)', v_ve_rh);
  ELSIF v_ve_fora > 0 THEN
    r.situacao := 'falhou'; r.obtido := 'FALHA GRAVE: usuário de fora da empresa leu a solicitação';
  ELSIF v_ve_anon > 0 THEN
    r.situacao := 'falhou'; r.obtido := 'FALHA GRAVE: anônimo leu a solicitação';
  ELSIF v_otp_rh > 0 THEN
    r.situacao := 'falhou'; r.obtido := 'O RH conseguiu ler os códigos de uso único';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('RH vê 1; fora da empresa %s; anônimo %s; códigos %s (negativo = sem permissão).', v_ve_fora, v_ve_anon, v_otp_rh);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', '', true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── ESP-ASS-003 ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_esp_ass_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_c jsonb; v_sol uuid; v_cpf text;
        v_sem_otp jsonb; v_sem_cons jsonb; v_sem_pv jsonb; v_hash text;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_c := public.qa_esp_ass_cenario('2099-07', 914);
  v_sol := (v_c->>'solicitacao_id')::uuid; v_cpf := v_c->>'cpf';

  r.passo_ordem := 1; r.passo_acao := 'Concluir só com o CPF conferido (sem código)';
  r.esperado := 'sem_otp';
  PERFORM public.qa_esp_como_servico();
  PERFORM public.assinatura_cpf_conferir(v_sol, v_cpf);
  PERFORM set_config('request.jwt.claims', '', true);
  v_sem_otp := public.qa_esp_ass_concluir(v_sol, 'assinado');

  r.passo_ordem := 2; r.passo_acao := 'Com o código validado, mas sem consentimento';
  r.esperado := 'sem_prova_vida';
  v_hash := encode(public.digest(v_sol::text || ':654321', 'sha256'), 'hex');
  PERFORM public.qa_esp_como_servico();
  PERFORM public.assinatura_otp_registrar(v_sol, v_hash, 'email', 'q***');
  PERFORM public.assinatura_otp_validar(v_sol, v_hash);
  PERFORM set_config('request.jwt.claims', '', true);
  v_sem_cons := public.qa_esp_ass_concluir(v_sol, 'assinado');

  r.passo_ordem := 3; r.passo_acao := 'Com consentimento, mas sem os quadros da prova de vida';
  r.esperado := 'sem_prova_vida';
  PERFORM public.qa_esp_como_servico();
  PERFORM public.assinatura_registrar_consentimento(v_sol, jsonb_build_object(
    'finalidade', 'Confirmar a identidade', 'versao_texto', 'consentimento-biometrico-v1'));
  PERFORM set_config('request.jwt.claims', '', true);
  v_sem_pv := public.qa_esp_ass_concluir(v_sol, 'assinado');

  IF COALESCE(v_sem_otp->>'erro', '') <> 'sem_otp' THEN
    r.situacao := 'falhou'; r.obtido := 'Sem código devia recusar: ' || v_sem_otp::text;
  ELSIF COALESCE(v_sem_cons->>'erro', '') <> 'sem_prova_vida' THEN
    r.situacao := 'falhou'; r.obtido := 'Sem consentimento devia recusar: ' || v_sem_cons::text;
  ELSIF COALESCE(v_sem_pv->>'erro', '') <> 'sem_prova_vida' THEN
    r.situacao := 'falhou'; r.obtido := 'Sem prova de vida devia recusar: ' || v_sem_pv::text;
  ELSIF (SELECT status FROM public.assinatura_solicitacoes WHERE id = v_sol) <> 'visualizado'
    AND (SELECT status FROM public.assinatura_solicitacoes WHERE id = v_sol) <> 'enviado' THEN
    r.situacao := 'falhou'; r.obtido := 'A solicitação mudou de status sem assinatura';
  ELSE
    r.situacao := 'passou'; r.obtido := 'Recusou sem código, sem consentimento e sem os quadros da prova de vida.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', '', true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── ESP-ASS-004 ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_esp_ass_004()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_c jsonb; v_c2 jsonb; v_res jsonb; v_res2 jsonb;
        v_esp jsonb; v_trilha jsonb; v_trilha2 jsonb; v_doc jsonb; v_pasta text; v_mes text;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_c := public.qa_esp_ass_cenario('2099-08', 915);
  v_c2 := public.qa_esp_ass_cenario('2099-08', 916);

  r.passo_ordem := 1; r.passo_acao := 'Assinar com CPF, código, consentimento e prova de vida';
  r.esperado := 'Espelho confirmado; origem colaborador_eletronica; confirmado_por = colaborador; PDF em Jornada/2099/08-Agosto';
  PERFORM public.qa_esp_ass_autenticar((v_c->>'solicitacao_id')::uuid, v_c->>'cpf', 'camera');
  v_res := public.qa_esp_ass_concluir((v_c->>'solicitacao_id')::uuid, 'assinado');
  v_esp := (SELECT to_jsonb(e) FROM public.ponto_espelhos e WHERE e.id = (v_c->>'espelho_id')::uuid);
  v_trilha := (SELECT to_jsonb(t) FROM public.assinaturas_trilha t WHERE t.id = (v_res->>'trilha_id')::uuid);
  v_doc := (SELECT to_jsonb(d) FROM public.documentos d WHERE d.id = (v_res->>'documento_id')::uuid);
  v_mes := (SELECT p.nome FROM public.documento_pastas p WHERE p.id = (v_doc->>'pasta_id')::uuid);

  r.passo_ordem := 2; r.passo_acao := 'Recusar a câmera e assinar com CPF + código';
  r.esperado := 'Assina; trilha marcada sem_prova_vida_recusou_camera';
  PERFORM public.qa_esp_ass_autenticar((v_c2->>'solicitacao_id')::uuid, v_c2->>'cpf', 'recusou');
  v_res2 := public.qa_esp_ass_concluir((v_c2->>'solicitacao_id')::uuid, 'assinado');
  v_trilha2 := (SELECT to_jsonb(t) FROM public.assinaturas_trilha t WHERE t.id = (v_res2->>'trilha_id')::uuid);

  IF NOT COALESCE((v_res->>'ok')::boolean, false) THEN
    r.situacao := 'falhou'; r.obtido := 'A assinatura completa foi recusada: ' || COALESCE(v_res::text, 'nulo');
  ELSIF (v_esp->>'status') <> 'confirmado' OR (v_esp->>'ciencia_origem') IS DISTINCT FROM 'colaborador_eletronica' THEN
    r.situacao := 'falhou'; r.obtido := format('Espelho ficou %s / %s', v_esp->>'status', v_esp->>'ciencia_origem');
  ELSIF (v_esp->>'confirmado_por') IS DISTINCT FROM 'colaborador'
     OR EXISTS (SELECT 1 FROM auth.users u WHERE u.id::text = (v_esp->>'confirmado_por')) THEN
    r.situacao := 'falhou'; r.obtido := 'confirmado_por não é o colaborador: ' || COALESCE(v_esp->>'confirmado_por', 'nulo');
  ELSIF (v_trilha->>'assinatura_hash') IS NULL OR (v_trilha->>'ip_address') IS DISTINCT FROM '203.0.113.9' THEN
    r.situacao := 'falhou'; r.obtido := 'Trilha sem selo ou sem a origem enviada pela borda';
  ELSIF v_mes IS DISTINCT FROM '08-Agosto' THEN
    r.situacao := 'falhou'; r.obtido := 'O PDF assinado não foi para Jornada/2099/08-Agosto (pasta: ' || COALESCE(v_mes, 'nula') || ')';
  ELSIF NOT COALESCE((v_res2->>'ok')::boolean, false)
     OR (v_trilha2->>'metodo_liveness') IS DISTINCT FROM 'sem_prova_vida_recusou_camera' THEN
    r.situacao := 'falhou'; r.obtido := 'A recusa da câmera não ficou marcada na trilha: ' || COALESCE(v_res2::text, 'nulo');
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Ciência do colaborador (eletrônica), sem id do RH; trilha selada com a origem; PDF em Jornada/2099/08-Agosto; recusa da câmera marcada.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', '', true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── ESP-ASS-005 ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_esp_ass_005()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_a jsonb; v_b jsonb; v_ra jsonb; v_rb jsonb; v_pend int; v_st_b text;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_a := public.qa_esp_ass_cenario('2099-09', 917);
  v_b := public.qa_esp_ass_cenario('2099-09', 918);

  r.passo_ordem := 1; r.passo_acao := 'Um assina com ressalva; outro contesta';
  r.esperado := 'Nenhum dos dois aparece como espelho sem ciência no portão';
  PERFORM public.qa_esp_ass_autenticar((v_a->>'solicitacao_id')::uuid, v_a->>'cpf', 'camera');
  v_ra := public.qa_esp_ass_concluir((v_a->>'solicitacao_id')::uuid, 'assinado_com_ressalva', 'Faltou a hora extra do dia 10');
  PERFORM public.qa_esp_ass_autenticar((v_b->>'solicitacao_id')::uuid, v_b->>'cpf', 'nenhuma');
  v_rb := public.qa_esp_ass_concluir((v_b->>'solicitacao_id')::uuid, 'contestado', 'Não trabalhei no dia 12');

  v_pend := (SELECT count(*) FROM public.ponto_fechamento_pendencias_criticas(v_t, NULL, '2099-09') p
              WHERE p.tipo = 'espelho_sem_ciencia'
                AND p.colaborador_cpf IN (v_a->>'cpf', v_b->>'cpf'));
  v_st_b := (SELECT status FROM public.ponto_espelhos WHERE id = (v_b->>'espelho_id')::uuid);

  IF NOT COALESCE((v_ra->>'ok')::boolean, false) OR NOT COALESCE((v_rb->>'ok')::boolean, false) THEN
    r.situacao := 'falhou'; r.obtido := 'Ressalva/contestação recusadas: ' || COALESCE(v_ra::text, '') || ' / ' || COALESCE(v_rb::text, '');
  ELSIF v_pend > 0 THEN
    r.situacao := 'falhou'; r.obtido := format('%s espelho(s) com ressalva/contestação ainda bloqueiam o fechamento', v_pend);
  ELSIF v_st_b <> 'contestado' THEN
    r.situacao := 'falhou'; r.obtido := 'O espelho contestado ficou com status ' || COALESCE(v_st_b, 'nulo');
  ELSE
    r.situacao := 'passou'; r.obtido := 'Ressalva e contestação ficam como recusa formalizada e não bloqueiam o portão.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', '', true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── ESP-ASS-006 ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_esp_ass_006()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_c jsonb; v_res jsonb; v_st text; v_mot text;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_c := public.qa_esp_ass_cenario('2099-10', 919);
  r.passo_ordem := 1; r.passo_acao := 'Reabrir a competência com uma solicitação enviada';
  r.esperado := 'Solicitação cancelada com motivo competencia_reaberta';
  v_res := public.ponto_reabrir_competencia(v_t, NULL, '2099-10', '[QA] correção', 'qa', 'QA');
  v_st := (SELECT status FROM public.assinatura_solicitacoes WHERE id = (v_c->>'solicitacao_id')::uuid);
  v_mot := (SELECT cancelado_motivo FROM public.assinatura_solicitacoes WHERE id = (v_c->>'solicitacao_id')::uuid);
  IF NOT COALESCE((v_res->>'ok')::boolean, false) THEN
    r.situacao := 'falhou'; r.obtido := 'Reabertura recusada: ' || v_res::text;
  ELSIF v_st <> 'cancelado' OR v_mot IS DISTINCT FROM 'competencia_reaberta' THEN
    r.situacao := 'falhou'; r.obtido := format('Solicitação ficou %s (%s)', v_st, COALESCE(v_mot, '-'));
  ELSIF (SELECT token_hash FROM public.assinatura_solicitacoes WHERE id = (v_c->>'solicitacao_id')::uuid) IS NOT NULL THEN
    r.situacao := 'falhou'; r.obtido := 'O link da solicitação cancelada continuou valendo';
  ELSE
    r.situacao := 'passou'; r.obtido := 'Reabrir cancela a solicitação ativa e invalida o link.';
  END IF;
  r.detalhe := v_res;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── ESP-ASS-007 ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_esp_ass_007()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_colab uuid := gen_random_uuid();
        v_d1 jsonb; v_d2 jsonb; v_raiz uuid; v_n_jornada int; v_cam text;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM set_config('request.jwt.claims', '', true);
  r.passo_ordem := 1; r.passo_acao := 'Arquivar dois documentos do mesmo colaborador em Jornada/2099/11-Novembro';
  r.esperado := 'Mesma pasta nas duas vezes; uma única Jornada sob a pasta do colaborador';
  v_d1 := public.arquivar_documento_servidor(jsonb_build_object(
    'tenant_id', v_t, 'colaborador_id', v_colab, 'colaborador_nome', '[QA-ESP-ASS] Pasta 007',
    'colaborador_cpf', public.qa_cpf(920), 'storage_path', v_t::text || '/qa/esp-007-a.pdf',
    'file_name', 'a.pdf', 'subpasta_caminho', public.assinatura_caminho_jornada('2099-11')));
  v_d2 := public.arquivar_documento_servidor(jsonb_build_object(
    'tenant_id', v_t, 'colaborador_id', v_colab, 'colaborador_nome', '[QA-ESP-ASS] Pasta 007',
    'colaborador_cpf', public.qa_cpf(920), 'storage_path', v_t::text || '/qa/esp-007-b.pdf',
    'file_name', 'b.pdf', 'subpasta_caminho', public.assinatura_caminho_jornada('2099-11')));

  -- Sobe da pasta do mês até a pasta do colaborador (é ela que a subárvore do
  -- colaborador em ye_pastas_do_usuario usa como raiz).
  v_raiz := (WITH RECURSIVE sobe AS (
      SELECT p.id, p.pasta_pai_id, p.tipo, p.nome, 0 AS nivel FROM public.documento_pastas p
       WHERE p.id = (v_d1->>'pasta_id')::uuid
      UNION ALL
      SELECT p.id, p.pasta_pai_id, p.tipo, p.nome, s.nivel + 1 FROM public.documento_pastas p
        JOIN sobe s ON p.id = s.pasta_pai_id WHERE s.nivel < 6)
    SELECT id FROM sobe WHERE tipo = 'colaborador' LIMIT 1);
  v_cam := (WITH RECURSIVE sobe AS (
      SELECT p.id, p.pasta_pai_id, p.tipo, p.nome, 0 AS nivel FROM public.documento_pastas p
       WHERE p.id = (v_d1->>'pasta_id')::uuid
      UNION ALL
      SELECT p.id, p.pasta_pai_id, p.tipo, p.nome, s.nivel + 1 FROM public.documento_pastas p
        JOIN sobe s ON p.id = s.pasta_pai_id WHERE s.nivel < 6)
    SELECT string_agg(nome, '/' ORDER BY nivel DESC) FROM sobe WHERE nivel < 3);
  v_n_jornada := (SELECT count(*) FROM public.documento_pastas
                   WHERE pasta_pai_id = v_raiz AND nome = 'Jornada');

  IF (v_d1->>'pasta_id') IS DISTINCT FROM (v_d2->>'pasta_id') THEN
    r.situacao := 'falhou'; r.obtido := 'O segundo arquivamento criou outra pasta (não idempotente)';
  ELSIF v_raiz IS NULL THEN
    r.situacao := 'falhou'; r.obtido := 'A pasta do mês não está dentro da pasta do colaborador';
  ELSIF v_n_jornada <> 1 THEN
    r.situacao := 'falhou'; r.obtido := format('%s pastas Jornada sob o colaborador', v_n_jornada);
  ELSIF v_cam IS DISTINCT FROM 'Jornada/2099/11-Novembro' THEN
    r.situacao := 'falhou'; r.obtido := 'Caminho criado: ' || COALESCE(v_cam, 'nulo');
  ELSE
    r.situacao := 'passou'; r.obtido := 'Jornada/2099/11-Novembro criada uma vez, dentro da pasta do colaborador.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── ESP-ASS-008 ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_esp_ass_008()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_c jsonb; v_ev uuid; v_upd boolean := false; v_del boolean := false;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_c := public.qa_esp_ass_cenario('2099-12', 921);
  v_ev := (SELECT id FROM public.assinatura_eventos WHERE solicitacao_id = (v_c->>'solicitacao_id')::uuid LIMIT 1);
  r.passo_ordem := 1; r.passo_acao := 'Alterar e apagar um evento da trilha (como dono do banco)';
  r.esperado := 'As duas operações recusadas';
  BEGIN
    UPDATE public.assinatura_eventos SET tipo = 'adulterado' WHERE id = v_ev;
  EXCEPTION WHEN OTHERS THEN v_upd := true;
  END;
  BEGIN
    DELETE FROM public.assinatura_eventos WHERE id = v_ev;
  EXCEPTION WHEN OTHERS THEN v_del := true;
  END;
  IF v_ev IS NULL THEN
    r.situacao := 'falhou'; r.obtido := 'O cenário não gerou evento';
  ELSIF NOT v_upd OR NOT v_del THEN
    r.situacao := 'falhou'; r.obtido := format('Alterar recusado: %s; apagar recusado: %s', v_upd, v_del);
  ELSE
    r.situacao := 'passou'; r.obtido := 'A trilha não aceita alteração nem exclusão.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── ESP-ASS-009 ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_esp_ass_009()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_c jsonb; v_uid uuid; v_ve bigint;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_c := public.qa_esp_ass_cenario('2098-01', 922);
  IF to_regprocedure('qa_rls.conta_auth(text)') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Faltam os ajudantes qa_rls.'; RETURN r;
  END IF;
  r.passo_ordem := 1; r.passo_acao := 'Colaborador comum da mesma empresa (sem Ponto/Colaboradores) conta a solicitação de outro';
  r.esperado := '0';
  v_uid := public.qa_mky_usuario_empresa(public.qa_sandbox_tenant_id(), 'esp-comum');
  INSERT INTO public.user_roles (user_id, role) VALUES (v_uid, 'user') ON CONFLICT DO NOTHING;
  PERFORM public.qa_mky_claims(v_uid);
  v_ve := qa_rls.conta_auth(format('SELECT count(*) FROM public.assinatura_solicitacoes WHERE id = %L', v_c->>'solicitacao_id'));
  PERFORM set_config('request.jwt.claims', '', true);
  IF v_ve > 0 THEN
    r.situacao := 'falhou'; r.obtido := 'Usuário sem acesso ao Ponto leu a solicitação de outro colaborador';
  ELSE
    r.situacao := 'passou'; r.obtido := format('Sem acesso ao Ponto não lê (contou %s).', v_ve);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', '', true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── ESP-ASS-010 ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_esp_ass_010()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_ok jsonb; v_ass jsonb; v_can jsonb; v_des jsonb; v_lista uuid[];
BEGIN
  PERFORM public.qa_modo_ligar();
  v_ok  := public.qa_esp_ass_cenario('2098-02', 923);
  v_ass := public.qa_esp_ass_cenario('2098-02', 924);
  v_can := public.qa_esp_ass_cenario('2098-02', 925);
  v_des := public.qa_esp_ass_cenario('2098-02', 926);

  UPDATE public.assinatura_solicitacoes SET proximo_lembrete_em = now() - interval '1 hour'
   WHERE id IN ((v_ok->>'solicitacao_id')::uuid, (v_ass->>'solicitacao_id')::uuid,
                (v_can->>'solicitacao_id')::uuid, (v_des->>'solicitacao_id')::uuid);
  UPDATE public.assinatura_solicitacoes SET status = 'assinado' WHERE id = (v_ass->>'solicitacao_id')::uuid;
  UPDATE public.assinatura_solicitacoes SET status = 'cancelado' WHERE id = (v_can->>'solicitacao_id')::uuid;
  UPDATE public.admissoes SET data_desligamento = CURRENT_DATE - 5 WHERE id = (v_des->>'admissao_id')::uuid;

  r.passo_ordem := 1; r.passo_acao := 'Listar os lembretes devidos';
  r.esperado := 'Só o pendente ativo; fora assinado, cancelado e desligado';
  v_lista := ARRAY(SELECT d.solicitacao_id FROM public.assinatura_lembretes_devidos(1000) d);

  IF NOT ((v_ok->>'solicitacao_id')::uuid = ANY(v_lista)) THEN
    r.situacao := 'falhou'; r.obtido := 'O pendente ativo ficou sem lembrete';
  ELSIF (v_ass->>'solicitacao_id')::uuid = ANY(v_lista) THEN
    r.situacao := 'falhou'; r.obtido := 'Assinado recebeu lembrete';
  ELSIF (v_can->>'solicitacao_id')::uuid = ANY(v_lista) THEN
    r.situacao := 'falhou'; r.obtido := 'Cancelado recebeu lembrete';
  ELSIF (v_des->>'solicitacao_id')::uuid = ANY(v_lista) THEN
    r.situacao := 'falhou'; r.obtido := 'Desligado recebeu lembrete';
  ELSE
    r.situacao := 'passou'; r.obtido := 'Lembrete só para o pendente ativo.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── ESP-ASS-011 ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_esp_ass_011()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_c jsonb; v_sol uuid; v_res jsonb; v_certo jsonb; i int;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_c := public.qa_esp_ass_cenario('2098-03', 927);
  v_sol := (v_c->>'solicitacao_id')::uuid;
  r.passo_ordem := 1; r.passo_acao := 'Digitar 5 CPFs errados e depois o certo';
  r.esperado := '5ª tentativa bloqueia; o certo continua bloqueado';
  PERFORM public.qa_esp_como_servico();
  FOR i IN 1..5 LOOP
    v_res := public.assinatura_cpf_conferir(v_sol, '00000000000');
  END LOOP;
  v_certo := public.assinatura_cpf_conferir(v_sol, v_c->>'cpf');
  PERFORM set_config('request.jwt.claims', '', true);
  IF COALESCE(v_res->>'erro', '') <> 'bloqueado' THEN
    r.situacao := 'falhou'; r.obtido := 'A 5ª tentativa não bloqueou: ' || v_res::text;
  ELSIF COALESCE(v_certo->>'erro', '') <> 'bloqueado' THEN
    r.situacao := 'falhou'; r.obtido := 'Depois do bloqueio o CPF certo passou: ' || v_certo::text;
  ELSE
    r.situacao := 'passou'; r.obtido := '5 CPFs errados bloqueiam por 24 h (o RH destrava gerando novo link).';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', '', true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── Documentação, implementações e pontes ──────────────────────────────────
DO $doc$
DECLARE v_mod uuid;
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL OR to_regclass('public.qa_modulos') IS NULL THEN
    RAISE NOTICE 'Motor de QA ausente; casos ESP-ASS não documentados.';
    RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'jornada-rotina/ponto' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo jornada-rotina/ponto ausente; casos ESP-ASS não documentados.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'ESP-ASS-001', 'Envio do espelho para assinatura exige o PDF congelado com hash e não deixa duas solicitações ativas',
   'negativo', 'alta', 'aprovado', 'api', 'MP 2.200-2/2001, art. 10, §2º (integridade)',
   'Assina-se o PDF congelado no envio: sem o hash dele não há solicitação. Um espelho tem no máximo uma solicitação ativa, e só depois da competência fechada.',
   'Cercado de QA.',
   '[{"ordem":1,"acao":"Criar a solicitação de espelho de competência fechada","resultado_esperado":"Criada (na_fila); espelho enviado"},{"ordem":2,"acao":"Criar sem hash, uma segunda ativa e uma com competência aberta","resultado_esperado":"hash_obrigatorio; ja_existe_ativa; competencia_nao_fechada"}]'::jsonb,
   'Hash obrigatório, uma ativa por espelho, competência fechada.', 'Fatia 1 (30/10/2026).'),
  (v_mod, 'ESP-ASS-002', 'Solicitações de assinatura: outra empresa e anônimo não leem; códigos de uso único não são lidos pela API',
   'negativo', 'critica', 'aprovado', 'api', 'LGPD arts. 6º e 46',
   'As solicitações carregam nome, CPF e e-mail do colaborador. Só a própria empresa (com Ponto/Colaboradores) lê; os códigos ficam fora da API.',
   'Cercado de QA; ajudantes qa_rls.',
   '[{"ordem":1,"acao":"RH da empresa conta a solicitação e os códigos","resultado_esperado":"1 solicitação; 0 códigos"},{"ordem":2,"acao":"Usuário de fora e anônimo contam","resultado_esperado":"0 ou sem permissão"}]'::jsonb,
   'Isolamento por empresa e sem acesso anônimo.', NULL),
  (v_mod, 'ESP-ASS-003', 'Concluir a assinatura recusa sem código, sem consentimento ou sem a prova de vida',
   'negativo', 'critica', 'aprovado', 'api', 'MP 2.200-2/2001, art. 10, §2º; Lei 14.063/2020, art. 4º (régua por analogia)',
   'A assinatura só fecha com CPF conferido, código de uso único validado e prova de vida (ou a recusa registrada da câmera).',
   'Cercado de QA.',
   '[{"ordem":1,"acao":"Concluir só com CPF","resultado_esperado":"sem_otp"},{"ordem":2,"acao":"Com código, sem consentimento","resultado_esperado":"sem_prova_vida"},{"ordem":3,"acao":"Com consentimento, sem os quadros","resultado_esperado":"sem_prova_vida"}]'::jsonb,
   'Nada assina sem as três evidências.', NULL),
  (v_mod, 'ESP-ASS-004', 'Assinar grava a ciência do colaborador (nunca o id do RH), sela a trilha e arquiva em Jornada/AAAA/MM-Mês; recusar a câmera fica marcado',
   'feliz', 'critica', 'aprovado', 'api', 'Súmula 338 do TST; MP 2.200-2/2001, art. 10, §2º; LGPD art. 11, II, g',
   'O espelho passa a confirmado com ciencia_origem colaborador_eletronica e confirmado_por colaborador; a trilha guarda o selo e a origem enviada pela borda; o PDF assinado vai para Jornada/AAAA/MM-Mês. Quem recusa a câmera assina com CPF + código e a trilha registra sem_prova_vida_recusou_camera.',
   'Cercado de QA.',
   '[{"ordem":1,"acao":"Assinar com CPF, código, consentimento e prova de vida","resultado_esperado":"Espelho confirmado/colaborador_eletronica; trilha selada; PDF em Jornada/2099/08-Agosto"},{"ordem":2,"acao":"Recusar a câmera e assinar","resultado_esperado":"Assina; trilha com sem_prova_vida_recusou_camera"}]'::jsonb,
   'Ciência do colaborador com evidências.', NULL),
  (v_mod, 'ESP-ASS-005', 'Assinatura com ressalva e contestação não bloqueiam o fechamento',
   'feliz', 'alta', 'aprovado', 'api', 'Súmula 338 do TST (recusa formalizada)',
   'Decisão da fundadora: contestação não bloqueia o fechamento (vale como recusa formalizada, igual à ressalva). Não existe aceite tácito.',
   'Cercado de QA.',
   '[{"ordem":1,"acao":"Um assina com ressalva, outro contesta","resultado_esperado":"Nenhum aparece como espelho sem ciência; o contestado fica contestado"}]'::jsonb,
   'Ressalva e contestação liberam o portão.', NULL),
  (v_mod, 'ESP-ASS-006', 'Reabrir a competência cancela as solicitações de assinatura ativas e invalida o link',
   'negativo', 'alta', 'aprovado', 'api', 'Súmula 338 do TST',
   'Com a competência reaberta os números vão mudar: o documento enviado deixa de valer (motivo competencia_reaberta).',
   'Cercado de QA.',
   '[{"ordem":1,"acao":"Reabrir com uma solicitação enviada","resultado_esperado":"Solicitação cancelada; token apagado"}]'::jsonb,
   'Reabrir cancela as ativas.', NULL),
  (v_mod, 'ESP-ASS-007', 'Pasta Jornada/AAAA/MM-Mês criada sem duplicar, dentro da pasta do colaborador',
   'feliz', 'media', 'aprovado', 'api', 'LGPD art. 6º, X',
   'O espelho assinado (e o papel digitalizado) vão para Documentos › colaborador › Jornada/AAAA/MM-NomeDoMês. A criação é idempotente e fica na subárvore do colaborador (que ele vê pelo escopo próprio, ye_pastas_do_usuario).',
   'Cercado de QA.',
   '[{"ordem":1,"acao":"Arquivar dois documentos no mesmo caminho","resultado_esperado":"Mesma pasta; uma Jornada; caminho Jornada/2099/11-Novembro sob a pasta do colaborador"}]'::jsonb,
   'Pasta certa, sem duplicar.', NULL),
  (v_mod, 'ESP-ASS-008', 'A trilha da assinatura (eventos) não aceita alteração nem exclusão',
   'negativo', 'alta', 'aprovado', 'api', 'MP 2.200-2/2001, art. 10, §2º; LGPD art. 6º, X',
   'Os eventos (aberto, cpf, código, consentimento, prova de vida, assinado...) são prova: só inserção.',
   'Cercado de QA.',
   '[{"ordem":1,"acao":"UPDATE e DELETE num evento","resultado_esperado":"Os dois recusados"}]'::jsonb,
   'Trilha imutável.', NULL),
  (v_mod, 'ESP-ASS-009', 'Quem não tem acesso ao Ponto não lê a solicitação de assinatura de outro colaborador',
   'negativo', 'alta', 'aprovado', 'api', 'LGPD arts. 6º e 46',
   'Camada de perfil (mesmo portão do Ponto): colaborador comum vê só a própria.',
   'Cercado de QA; ajudantes qa_rls.',
   '[{"ordem":1,"acao":"Colaborador comum conta a solicitação de outro","resultado_esperado":"0"}]'::jsonb,
   'Leitura por perfil.', NULL),
  (v_mod, 'ESP-ASS-010', 'Lembretes de assinatura ignoram assinados, cancelados e desligados',
   'negativo', 'media', 'aprovado', 'api', 'LGPD art. 6º, III (necessidade)',
   'Lembretes em D+2, D+5 e D+8 só para quem ainda deve responder, com o vínculo ativo.',
   'Cercado de QA.',
   '[{"ordem":1,"acao":"Listar lembretes devidos com 4 situações","resultado_esperado":"Só o pendente ativo"}]'::jsonb,
   'Lembrete só para quem deve.', NULL),
  (v_mod, 'ESP-ASS-011', 'Cinco CPFs errados bloqueiam o link de assinatura',
   'negativo', 'alta', 'aprovado', 'api', 'Lei 14.063/2020, art. 4º (controle exclusivo do signatário, por analogia)',
   'O link sozinho não assina: o CPF é conferido no servidor, com no máximo 5 tentativas (bloqueio de 24 h; o RH destrava gerando novo link).',
   'Cercado de QA.',
   '[{"ordem":1,"acao":"5 CPFs errados e depois o certo","resultado_esperado":"bloqueado nas duas"}]'::jsonb,
   'Força bruta barrada.', NULL),
  (v_mod, 'ESP-ASS-012', 'Relatórios › Espelho de Ponto: Visualizar abre a pré-visualização do PDF sem botão de baixar',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'O RH confere o espelho antes de enviar, sem gerar arquivo solto no computador.',
   'Usuário de teste logado.',
   '[{"ordem":1,"acao":"Ponto › Apuração › Relatórios, tipo Espelho de Ponto, clicar Visualizar","resultado_esperado":"Diálogo Pré-visualização do espelho, sem botão de baixar"}]'::jsonb,
   'Pré-visualização sem download.', 'Teste automático cobre a abertura do diálogo; o conteúdo do PDF depende da massa do mês.'),
  (v_mod, 'ESP-ASS-013', 'Relatórios › Espelho de Ponto: Enviar para assinatura gera o link e o status fica Pendente',
   'feliz', 'alta', 'aprovado', 'e2e', 'MP 2.200-2/2001, art. 10, §2º',
   'Com a competência fechada e um colaborador escolhido, o RH envia o espelho: o link aparece uma vez para copiar e o painel mostra Pendente.',
   'Competência fechada com espelho; colaborador com e-mail; função de borda publicada.',
   '[{"ordem":1,"acao":"Escolher um colaborador e clicar Enviar para assinatura","resultado_esperado":"Link exibido para copiar; status Pendente no painel"}]'::jsonb,
   'Envio com link e status.', 'Teste automático cobre a ENTRADA (botão e a regra da competência fechada); o envio real é homologação manual, porque depende de competência fechada e da função de borda com e-mail.'),
  (v_mod, 'ESP-ASS-014', 'Página pública /assinar com token inválido mostra Link inválido',
   'negativo', 'media', 'aprovado', 'e2e', NULL,
   'Token adulterado ou cancelado não revela nada do documento.',
   'Nenhuma.',
   '[{"ordem":1,"acao":"Abrir /assinar/token-invalido","resultado_esperado":"Mensagem Link inválido"}]'::jsonb,
   'Link inválido.', NULL),
  (v_mod, 'ESP-ASS-015', 'Painel de assinaturas do espelho mostra os selos (Assinado ✓, Ressalva, Contestado, Pendente)',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'O RH vê de relance quem assinou, quem fez ressalva, quem contestou e quem está pendente.',
   'Usuário de teste logado.',
   '[{"ordem":1,"acao":"Abrir Relatórios › Espelho de Ponto","resultado_esperado":"Painel Assinaturas do espelho com a legenda dos selos"}]'::jsonb,
   'Selos visíveis.', 'Teste automático confere o painel e a legenda; o selo Assinado numa linha real é conferido na homologação com massa semeada.'),
  (v_mod, 'ESP-ASS-016', 'Colaborador assina o espelho pelo link: CPF, código por e-mail, consentimento, prova de vida e decisão',
   'feliz', 'critica', 'aprovado', 'e2e', 'MP 2.200-2/2001, art. 10, §2º; LGPD art. 11, II, g',
   'Fluxo completo do colaborador, com câmera. Inclui a alternativa de recusar a câmera (assina com CPF + código, marcado como sem prova de vida).',
   'Ambiente com Resend configurado (e-mail real de teste) e câmera.',
   '[{"ordem":1,"acao":"Abrir o link, marcar Li, informar CPF","resultado_esperado":"Pede o código"},{"ordem":2,"acao":"Digitar o código do e-mail","resultado_esperado":"Tela de consentimento"},{"ordem":3,"acao":"Aceitar e fazer a prova de vida","resultado_esperado":"Três decisões disponíveis"},{"ordem":4,"acao":"Concordo e assino","resultado_esperado":"Assinado; via por e-mail; PDF com manifesto em Documentos › Jornada/AAAA/MM-Mês"}]'::jsonb,
   'Assinatura completa com evidências.', 'Homologação manual (câmera e e-mail real); sem teste automático, como o PONTO-499.')
  ON CONFLICT (codigo) DO UPDATE SET
    modulo_id = EXCLUDED.modulo_id, titulo = EXCLUDED.titulo, objetivo = EXCLUDED.objetivo,
    passos = EXCLUDED.passos, resultado_esperado = EXCLUDED.resultado_esperado, nivel = EXCLUDED.nivel,
    base_legal = EXCLUDED.base_legal, observacoes = EXCLUDED.observacoes, status = 'aprovado';

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
      ('ESP-ASS-001', 'qa_caso_esp_ass_001', true),
      ('ESP-ASS-002', 'qa_caso_esp_ass_002', true),
      ('ESP-ASS-003', 'qa_caso_esp_ass_003', true),
      ('ESP-ASS-004', 'qa_caso_esp_ass_004', true),
      ('ESP-ASS-005', 'qa_caso_esp_ass_005', true),
      ('ESP-ASS-006', 'qa_caso_esp_ass_006', true),
      ('ESP-ASS-007', 'qa_caso_esp_ass_007', true),
      ('ESP-ASS-008', 'qa_caso_esp_ass_008', true),
      ('ESP-ASS-009', 'qa_caso_esp_ass_009', true),
      ('ESP-ASS-010', 'qa_caso_esp_ass_010', true),
      ('ESP-ASS-011', 'qa_caso_esp_ass_011', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;

  IF to_regclass('public.qa_cobertura_e2e') IS NOT NULL THEN
    INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste, ativo, criado_em) VALUES
      ('ESP-ASS-012', 'cypress/e2e/ponto.cy.ts', 'abre Relatórios › Espelho de Ponto e a pré-visualização sem botão de baixar', true, now()),
      ('ESP-ASS-013', 'cypress/e2e/ponto.cy.ts', 'mostra Enviar para assinatura no Espelho de Ponto com a regra da competência fechada', true, now()),
      ('ESP-ASS-014', 'cypress/e2e/ponto.cy.ts', 'abre /assinar com token inválido e mostra Link inválido', true, now()),
      ('ESP-ASS-015', 'cypress/e2e/ponto.cy.ts', 'mostra o painel de assinaturas do espelho com a legenda dos selos', true, now())
    ON CONFLICT (codigo) DO UPDATE SET spec = EXCLUDED.spec, teste = EXCLUDED.teste, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentação ESP-ASS não registrada: %', SQLERRM;
END $doc$;

-- CONFERÊNCIA: os 11 casos api rodados no cercado de QA (esperado "passou").
SELECT
  CASE WHEN to_regprocedure('public.qa_executar_descartavel(text)') IS NULL THEN 'sem_motor' ELSE (public.qa_executar_descartavel('qa_caso_esp_ass_001')).situacao::text END AS esp_ass_001,
  CASE WHEN to_regprocedure('public.qa_executar_descartavel(text)') IS NULL THEN 'sem_motor' ELSE (public.qa_executar_descartavel('qa_caso_esp_ass_002')).situacao::text END AS esp_ass_002,
  CASE WHEN to_regprocedure('public.qa_executar_descartavel(text)') IS NULL THEN 'sem_motor' ELSE (public.qa_executar_descartavel('qa_caso_esp_ass_003')).situacao::text END AS esp_ass_003,
  CASE WHEN to_regprocedure('public.qa_executar_descartavel(text)') IS NULL THEN 'sem_motor' ELSE (public.qa_executar_descartavel('qa_caso_esp_ass_004')).situacao::text END AS esp_ass_004,
  CASE WHEN to_regprocedure('public.qa_executar_descartavel(text)') IS NULL THEN 'sem_motor' ELSE (public.qa_executar_descartavel('qa_caso_esp_ass_005')).situacao::text END AS esp_ass_005,
  CASE WHEN to_regprocedure('public.qa_executar_descartavel(text)') IS NULL THEN 'sem_motor' ELSE (public.qa_executar_descartavel('qa_caso_esp_ass_006')).situacao::text END AS esp_ass_006,
  CASE WHEN to_regprocedure('public.qa_executar_descartavel(text)') IS NULL THEN 'sem_motor' ELSE (public.qa_executar_descartavel('qa_caso_esp_ass_007')).situacao::text END AS esp_ass_007,
  CASE WHEN to_regprocedure('public.qa_executar_descartavel(text)') IS NULL THEN 'sem_motor' ELSE (public.qa_executar_descartavel('qa_caso_esp_ass_008')).situacao::text END AS esp_ass_008,
  CASE WHEN to_regprocedure('public.qa_executar_descartavel(text)') IS NULL THEN 'sem_motor' ELSE (public.qa_executar_descartavel('qa_caso_esp_ass_009')).situacao::text END AS esp_ass_009,
  CASE WHEN to_regprocedure('public.qa_executar_descartavel(text)') IS NULL THEN 'sem_motor' ELSE (public.qa_executar_descartavel('qa_caso_esp_ass_010')).situacao::text END AS esp_ass_010,
  CASE WHEN to_regprocedure('public.qa_executar_descartavel(text)') IS NULL THEN 'sem_motor' ELSE (public.qa_executar_descartavel('qa_caso_esp_ass_011')).situacao::text END AS esp_ass_011;
