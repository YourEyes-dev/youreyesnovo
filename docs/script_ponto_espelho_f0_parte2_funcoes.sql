-- ============================================================================
-- ESPELHO DE PONTO — Fatia 0, PARTE 2 de 2 (funções + gatilho + QA)
-- Cole INTEIRO no SQL Editor, DEPOIS da parte 1.
-- Equivale às migrations 20261030094241_ponto_espelho_ciencia_papel_reabertura.sql
-- e 20261030094445_qa_ponto_espelho_ciencia_casos.sql (mesmo texto).
--
-- Não cria tabela (sem o auxiliar de RLS do editor). Funções sem SELECT INTO.
-- Um único gatilho novo, numa única tabela (ponto_espelhos). Idempotente.
-- ============================================================================

SET lock_timeout = '10s';

-- (1) Guarda da ciência --------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_espelho_ciencia_guarda()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $fn$
DECLARE
  v_claims text := NULLIF(current_setting('request.jwt.claims', true), '');
  v_role   text;
BEGIN
  v_role := CASE WHEN v_claims IS NULL THEN '' ELSE COALESCE(v_claims::jsonb->>'role', '') END;

  -- Só a chamada pela API com usuário (ou anônimo) é vigiada.
  IF v_role NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;
  -- Função do servidor que registra ciência acende esta marca (vale só na transação).
  IF COALESCE(current_setting('ye.espelho_ciencia', true), '') = 'on' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF COALESCE(NEW.status, 'gerado') NOT IN ('gerado', 'enviado')
       OR NEW.ciencia_origem IS NOT NULL
       OR NEW.data_confirmacao IS NOT NULL
       OR NEW.confirmado_por IS NOT NULL
       OR COALESCE(NEW.assinatura_hash, '') <> ''
       OR NULLIF(btrim(COALESCE(NEW.ressalva_texto, '')), '') IS NOT NULL THEN
      RAISE EXCEPTION 'A ciência do espelho de ponto não pode ser gravada direto: ela vem da assinatura do colaborador ou do registro do papel assinado.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.ciencia_origem IS DISTINCT FROM OLD.ciencia_origem
     OR NEW.data_confirmacao IS DISTINCT FROM OLD.data_confirmacao
     OR NEW.confirmado_por IS DISTINCT FROM OLD.confirmado_por
     OR NEW.assinatura_hash IS DISTINCT FROM OLD.assinatura_hash
     OR NEW.ressalva_texto IS DISTINCT FROM OLD.ressalva_texto
     OR (NEW.status IS DISTINCT FROM OLD.status
         AND NOT (COALESCE(OLD.status, 'gerado') IN ('gerado', 'enviado')
                  AND COALESCE(NEW.status, 'gerado') IN ('gerado', 'enviado'))) THEN
    RAISE EXCEPTION 'A ciência do espelho de ponto não pode ser alterada direto: ela vem da assinatura do colaborador ou do registro do papel assinado.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_ponto_espelho_ciencia_guarda ON public.ponto_espelhos;
CREATE TRIGGER trg_ponto_espelho_ciencia_guarda
  BEFORE INSERT OR UPDATE ON public.ponto_espelhos
  FOR EACH ROW EXECUTE FUNCTION public.ponto_espelho_ciencia_guarda();

COMMENT ON FUNCTION public.ponto_espelho_ciencia_guarda() IS
  'Gatilho: pela API (authenticated/anon) a ciencia do espelho (status confirmado/ressalva, data_confirmacao, confirmado_por, assinatura_hash, ressalva_texto, ciencia_origem) so muda por funcao do servidor que acende ye.espelho_ciencia. Status gerado/enviado segue livre.';

-- (2) Ciência em papel digitalizado --------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_espelho_registrar_ciencia_papel(
  p_espelho_id   uuid,
  p_documento_id uuid,
  p_ressalva     text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid       uuid := auth.uid();
  v_tenant    uuid;
  v_cpf       text;
  v_status    text;
  v_origem    text;
  v_doc_path  text;
  v_doc_cpf   text;
  v_ressalva  text := NULLIF(btrim(COALESCE(p_ressalva, '')), '');
  v_novo      text;
  v_nome_rh   text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'nao_autenticado');
  END IF;

  v_tenant := (SELECT e.tenant_id FROM public.ponto_espelhos e WHERE e.id = p_espelho_id);
  IF v_tenant IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'espelho_nao_encontrado');
  END IF;
  v_cpf    := (SELECT regexp_replace(COALESCE(e.colaborador_cpf, ''), '[^0-9]', '', 'g') FROM public.ponto_espelhos e WHERE e.id = p_espelho_id);
  v_status := (SELECT COALESCE(e.status, 'gerado') FROM public.ponto_espelhos e WHERE e.id = p_espelho_id);
  v_origem := (SELECT e.ciencia_origem FROM public.ponto_espelhos e WHERE e.id = p_espelho_id);

  IF v_tenant IS DISTINCT FROM public.get_user_tenant_id() THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'espelho_de_outra_empresa');
  END IF;
  IF NOT public.perfil_permite_modulo(v_tenant, VARIADIC ARRAY['ponto', 'colaboradores'])
     OR NOT public.perfil_escreve(v_tenant, ARRAY['ponto', 'colaboradores'], ARRAY['editar', 'aprovar'], v_cpf) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_permissao');
  END IF;
  IF v_origem IS NOT NULL OR v_status NOT IN ('gerado', 'enviado') THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'espelho_ja_tem_ciencia');
  END IF;

  -- O anexo é obrigatório: documento da mesma empresa, do mesmo colaborador.
  v_doc_path := (SELECT d.storage_path FROM public.documentos d
                  WHERE d.id = p_documento_id AND d.tenant_id = v_tenant);
  v_doc_cpf  := (SELECT regexp_replace(COALESCE(d.colaborador_cpf, ''), '[^0-9]', '', 'g')
                   FROM public.documentos d WHERE d.id = p_documento_id AND d.tenant_id = v_tenant);
  IF p_documento_id IS NULL OR v_doc_path IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'anexo_obrigatorio');
  END IF;
  IF COALESCE(v_doc_cpf, '') <> '' AND v_doc_cpf <> v_cpf THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'anexo_de_outro_colaborador');
  END IF;

  v_novo := CASE WHEN v_ressalva IS NULL THEN 'confirmado' ELSE 'ressalva' END;
  v_nome_rh := (SELECT p.nome_completo FROM public.profiles p WHERE p.user_id = v_uid LIMIT 1);

  PERFORM set_config('ye.espelho_ciencia', 'on', true);
  UPDATE public.ponto_espelhos
     SET status           = v_novo,
         ressalva_texto   = v_ressalva,
         data_confirmacao = now(),
         confirmado_por   = 'colaborador',
         ciencia_origem   = 'papel_digitalizado',
         arquivo_url      = v_doc_path
   WHERE id = p_espelho_id;
  PERFORM set_config('ye.espelho_ciencia', 'off', true);

  BEGIN
    INSERT INTO public.ponto_audit_log
      (tenant_id, tabela_origem, registro_id, acao, dados_anteriores, dados_novos, usuario_id)
    VALUES (v_tenant, 'ponto_espelhos', p_espelho_id, 'UPDATE',
            jsonb_build_object('status', v_status),
            jsonb_build_object('evento', 'ciencia_papel_digitalizado', 'status', v_novo,
                               'documento_id', p_documento_id, 'com_ressalva', v_ressalva IS NOT NULL,
                               'registrado_por_nome', v_nome_rh),
            v_uid);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'ponto_espelho_registrar_ciencia_papel: trilha nao gravada (%)', SQLERRM;
  END;

  RETURN jsonb_build_object('ok', true, 'status', v_novo, 'ciencia_origem', 'papel_digitalizado');
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.ponto_espelho_registrar_ciencia_papel(uuid, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ponto_espelho_registrar_ciencia_papel(uuid, uuid, text) TO authenticated, service_role;

COMMENT ON FUNCTION public.ponto_espelho_registrar_ciencia_papel(uuid, uuid, text) IS
  'Registra a ciencia do espelho a partir do PAPEL assinado pelo colaborador e digitalizado (anexo obrigatorio, ja arquivado em documentos). Grava ciencia_origem=papel_digitalizado e confirmado_por=colaborador; quem registrou vai para ponto_audit_log. Ressalva escrita no papel vira status ressalva.';

-- (3) Reabertura formal: arquiva tudo, retira só o que não tem ciência ---------
CREATE OR REPLACE FUNCTION public.ponto_reabrir_competencia(
  p_tenant_id   uuid,
  p_empresa_id  uuid,
  p_competencia text,
  p_motivo      text,
  p_por         text DEFAULT NULL,
  p_por_nome    text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid       uuid := auth.uid();
  v_alcada    boolean := false;
  v_fech_id   uuid;
  v_fech_st   text;
  v_versao    int;
  v_qtd       int := 0;
  v_retirados int := 0;
BEGIN
  -- Motivo é obrigatório (reabertura é ato formal).
  IF p_motivo IS NULL OR btrim(p_motivo) = '' THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'motivo_obrigatorio');
  END IF;

  -- Pela API, só a própria empresa.
  IF v_uid IS NOT NULL AND p_tenant_id IS DISTINCT FROM public.get_user_tenant_id()
     AND NOT COALESCE(public.is_superadmin(v_uid), false) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_alcada_para_reabrir');
  END IF;

  -- A competência precisa existir e estar FECHADA.
  v_fech_id := (
    SELECT f.id FROM public.ponto_fechamentos f
     WHERE f.tenant_id = p_tenant_id
       AND f.competencia = p_competencia
       AND (p_empresa_id IS NULL OR f.empresa_id IS NOT DISTINCT FROM p_empresa_id)
     ORDER BY f.data_fechamento DESC NULLS LAST
     LIMIT 1);
  IF v_fech_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'competencia_sem_fechamento');
  END IF;
  v_fech_st := (SELECT COALESCE(f.status, '') FROM public.ponto_fechamentos f WHERE f.id = v_fech_id);
  IF v_fech_st <> 'fechado' THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'competencia_nao_esta_fechada', 'status_atual', v_fech_st);
  END IF;

  -- Alçada: só papéis de gestão reabrem. No SQL Editor (auth.uid() nulo), o
  -- administrador executa direto e o responsável fica registrado por p_por.
  IF v_uid IS NULL THEN
    v_alcada := true;
  ELSE
    v_alcada := public.has_role(v_uid, 'manager'::public.app_role)
             OR public.has_role(v_uid, 'admin'::public.app_role)
             OR public.has_role(v_uid, 'owner'::public.app_role)
             OR public.has_role(v_uid, 'superadmin'::public.app_role)
             OR COALESCE(public.is_superadmin(v_uid), false);
  END IF;
  IF NOT COALESCE(v_alcada, false) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_alcada_para_reabrir');
  END IF;

  -- Arquiva a versão corrente dos espelhos (a que o colaborador recebeu).
  v_versao := (
    SELECT COALESCE(max(h.versao), 0) + 1 FROM public.ponto_espelhos_historico h
     WHERE h.tenant_id = p_tenant_id AND h.competencia = p_competencia
       AND h.empresa_id IS NOT DISTINCT FROM p_empresa_id);

  INSERT INTO public.ponto_espelhos_historico
    (tenant_id, empresa_id, competencia, colaborador_cpf, colaborador_nome,
     versao, espelho_snapshot, motivo_reabertura, reaberto_por, reaberto_por_nome)
  SELECT e.tenant_id, e.empresa_id, e.competencia, e.colaborador_cpf, e.colaborador_nome,
         v_versao, to_jsonb(e.*), p_motivo, p_por, p_por_nome
  FROM public.ponto_espelhos e
  WHERE e.tenant_id = p_tenant_id AND e.competencia = p_competencia
    AND (p_empresa_id IS NULL OR e.empresa_id IS NOT DISTINCT FROM p_empresa_id);
  GET DIAGNOSTICS v_qtd = ROW_COUNT;

  -- Retira os espelhos ainda SEM ciência (já guardados no histórico acima): serão
  -- gerados de novo, com os números corrigidos, no próximo fechamento. Mesma
  -- definição de "sem ciência" do portão do fechamento (PONTO-387).
  DELETE FROM public.ponto_espelhos e
   WHERE e.tenant_id = p_tenant_id AND e.competencia = p_competencia
     AND (p_empresa_id IS NULL OR e.empresa_id IS NOT DISTINCT FROM p_empresa_id)
     AND e.ciencia_origem IS NULL
     AND COALESCE(e.status, '') NOT IN ('confirmado', 'assinado', 'ressalva')
     AND e.data_confirmacao IS NULL
     AND COALESCE(e.assinatura_hash, '') = ''
     AND NULLIF(btrim(COALESCE(e.ressalva_texto, '')), '') IS NULL;
  GET DIAGNOSTICS v_retirados = ROW_COUNT;

  -- Marca o fechamento como reaberto (libera novas marcações/edição no período).
  UPDATE public.ponto_fechamentos
     SET status = 'reaberto',
         reaberto_em = now(),
         reaberto_por = p_por,
         reaberto_por_nome = p_por_nome,
         motivo_reabertura = p_motivo,
         updated_at = now()
   WHERE id = v_fech_id;

  -- Trilha (acessória; nunca derruba a reabertura).
  BEGIN
    INSERT INTO public.ponto_audit_log
      (tenant_id, tabela_origem, registro_id, acao, dados_anteriores, dados_novos, usuario_id)
    VALUES (p_tenant_id, 'ponto_fechamentos', v_fech_id, 'UPDATE',
            jsonb_build_object('status', 'fechado', 'competencia', p_competencia),
            jsonb_build_object('evento', 'REABERTURA', 'status', 'reaberto', 'competencia', p_competencia,
                               'motivo', p_motivo, 'por', p_por, 'por_nome', p_por_nome,
                               'espelhos_arquivados', v_qtd, 'espelhos_sem_ciencia_retirados', v_retirados,
                               'versao_arquivada', v_versao),
            v_uid);
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN jsonb_build_object(
    'ok', true,
    'competencia', p_competencia,
    'espelhos_arquivados', v_qtd,
    'espelhos_sem_ciencia_retirados', v_retirados,
    'versao_arquivada', v_versao,
    'status', 'reaberto'
  );
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.ponto_reabrir_competencia(uuid, uuid, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ponto_reabrir_competencia(uuid, uuid, text, text, text, text) TO authenticated, service_role;

COMMENT ON FUNCTION public.ponto_reabrir_competencia(uuid, uuid, text, text, text, text) IS
  'Reabertura formal de competencia fechada: exige motivo, confere alcada (papeis de gestao) e empresa, arquiva TODOS os espelhos no historico (versao N), retira os espelhos ainda sem ciencia (gerados de novo no proximo fechamento), marca o fechamento como reaberto e registra a trilha. Espelho com ciencia permanece. PONTO-358.';

-- ---------------------------------------------------------------- QA

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

-- CONFERÊNCIA: peças no lugar e os 3 casos ESP-CIE rodados no cercado de QA
-- (esperado: tudo true e os 3 casos "passou"; sem o motor de QA, "sem_motor").
SELECT
  to_regprocedure('public.ponto_espelho_registrar_ciencia_papel(uuid,uuid,text)') IS NOT NULL AS rpc_papel_ok,
  EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_ponto_espelho_ciencia_guarda' AND NOT tgisinternal) AS guarda_ok,
  position('espelhos_sem_ciencia_retirados' IN pg_get_functiondef('public.ponto_reabrir_competencia(uuid,uuid,text,text,text,text)'::regprocedure)) > 0 AS reabertura_nova_ok,
  CASE WHEN to_regprocedure('public.qa_executar_descartavel(text)') IS NULL THEN 'sem_motor'
       ELSE (public.qa_executar_descartavel('qa_caso_esp_cie_001')).situacao::text END AS esp_cie_001,
  CASE WHEN to_regprocedure('public.qa_executar_descartavel(text)') IS NULL THEN 'sem_motor'
       ELSE (public.qa_executar_descartavel('qa_caso_esp_cie_002')).situacao::text END AS esp_cie_002,
  CASE WHEN to_regprocedure('public.qa_executar_descartavel(text)') IS NULL THEN 'sem_motor'
       ELSE (public.qa_executar_descartavel('qa_caso_esp_cie_003')).situacao::text END AS esp_cie_003;
