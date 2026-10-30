-- ============================================================================
-- ESPELHO DE PONTO — Fatia 0 (parte 2): ciência só do colaborador, papel com
-- anexo, reabertura pelo servidor
--
-- (1) GUARDA DA CIÊNCIA (gatilho em ponto_espelhos). Pela API, ninguém grava
--     ciência à mão: status confirmado/ressalva, data_confirmacao, confirmado_por,
--     assinatura_hash, ressalva_texto e ciencia_origem só mudam por função do
--     servidor (que acende a marca de transação ye.espelho_ciencia). Status
--     gerado <-> enviado continua livre. O SQL Editor, as migrations e as funções
--     de borda com a chave de serviço não são afetados (não chegam como
--     'authenticated'/'anon').
--
-- (2) ponto_espelho_registrar_ciencia_papel: o antigo botão "Confirmar" do RH vira
--     "Registrar ciência em papel". Exige o documento anexado (papel assinado e
--     digitalizado, já arquivado em Documentos), grava ciencia_origem =
--     'papel_digitalizado' e confirmado_por = 'colaborador' (quem assinou o papel
--     foi ele). Quem REGISTROU fica na trilha (ponto_audit_log), nunca no lugar
--     da assinatura.
--
-- (3) ponto_reabrir_competencia (mesma assinatura da onda 2, PONTO-358): continua
--     arquivando TODOS os espelhos da competência no histórico (versão N) e agora
--     também retira os espelhos ainda SEM ciência (mesma definição do portão do
--     fechamento, PONTO-387), que serão gerados de novo no próximo fechamento.
--     Os espelhos com ciência permanecem. A tela deixa de apagar espelho pelo
--     navegador. Função sem bloco injetado em runtime (conferido: nenhuma
--     migration faz replace no corpo dela).
--
-- Idempotente. Não toca consolidar_ponto_diario_manual nem a apuração.
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
