-- ============================================================================
-- Mapa Comportamental — correção do arquivamento no prontuário (RF-028).
--
-- A primeira versão resolvia o dono do prontuário por public.usuarios_base, mas
-- as PASTAS de colaborador do módulo Documentos são chaveadas por admissoes.id
-- (o app monta a árvore a partir de public.admissoes — ver useColaboradores /
-- syncColaboradores). Com o id errado, documento_pasta_do_colaborador criava
-- uma pasta PARALELA e o PDF não aparecia na pasta que o usuário vê.
--
-- Correção: resolver o colaborador por public.admissoes (CPF, status
-- 'concluido') e usar o empresa_id da própria admissão para casar com a pasta
-- existente. Continua indo para "Vida Funcional" (RN-009 — nunca Saúde) e com
-- classificação 'pessoal'. Idempotente por caminho de storage.
-- ============================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.mapa_comportamental_arquivar_no_prontuario(
  p_mapa_id      uuid,
  p_storage_path text,
  p_tamanho      int DEFAULT 0
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_tenant    uuid;
  v_empresa   uuid;
  v_auth      uuid;
  v_cpf       text;
  v_nome      text;
  v_colab_id  uuid;
  v_colab_emp uuid;
  v_pasta     uuid;
  v_doc_id    uuid;
BEGIN
  v_tenant := (SELECT tenant_id FROM public.mapa_comportamental_respostas
               WHERE id = p_mapa_id AND status = 'concluido' LIMIT 1);
  IF v_tenant IS NULL THEN
    RETURN json_build_object('ok', false, 'erro', 'mapa nao encontrado ou nao concluido');
  END IF;

  v_empresa := (SELECT empresa_id FROM public.mapa_comportamental_respostas WHERE id = p_mapa_id LIMIT 1);
  v_auth    := (SELECT auth_user_id FROM public.mapa_comportamental_respostas WHERE id = p_mapa_id LIMIT 1);
  v_cpf     := NULLIF(regexp_replace(COALESCE(
                 (SELECT colaborador_cpf FROM public.mapa_comportamental_respostas WHERE id = p_mapa_id LIMIT 1), ''),
                 '[^0-9]', '', 'g'), '');
  v_nome    := COALESCE(
                 (SELECT colaborador_nome FROM public.mapa_comportamental_respostas WHERE id = p_mapa_id LIMIT 1),
                 'Colaborador(a)');

  -- Autorização: titular do mapa OU gestor/RH do mesmo tenant.
  IF NOT (
        auth.uid() = v_auth
     OR (public.has_minimum_role(auth.uid(), 'manager'::app_role) AND v_tenant = public.get_user_tenant_id())
  ) THEN
    RETURN json_build_object('ok', false, 'erro', 'sem permissao');
  END IF;

  -- Defesa em profundidade: a chave do objeto tem de começar pelo tenant.
  IF p_storage_path IS NULL OR left(p_storage_path, length(v_tenant::text) + 1) <> v_tenant::text || '/' THEN
    RETURN json_build_object('ok', false, 'erro', 'caminho invalido');
  END IF;

  -- Dono do prontuário: a ADMISSÃO (mesma chave das pastas do módulo Documentos).
  IF v_cpf IS NOT NULL THEN
    v_colab_id := (SELECT a.id FROM public.admissoes a
                   WHERE a.tenant_id = v_tenant
                     AND regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g') = v_cpf
                     AND a.status = 'concluido'
                   ORDER BY (a.empresa_id IS NOT DISTINCT FROM v_empresa) DESC, a.created_at DESC
                   LIMIT 1);
    v_colab_emp := (SELECT a.empresa_id FROM public.admissoes a WHERE a.id = v_colab_id LIMIT 1);
    v_nome := COALESCE((SELECT a.nome_completo FROM public.admissoes a WHERE a.id = v_colab_id LIMIT 1), v_nome);
  END IF;

  -- Pasta "Vida Funcional" do colaborador (RN-009 — nunca Saúde), casando o
  -- empresa_id com o da admissão (é como a pasta foi criada pelo app).
  IF v_colab_id IS NOT NULL THEN
    v_pasta := public.documento_pasta_do_colaborador(
      v_tenant, v_colab_id, v_nome, v_cpf, COALESCE(v_colab_emp, v_empresa), 'Vida Funcional'
    );
  END IF;

  -- Idempotente por caminho de storage (a reexportação sobrescreve o objeto).
  v_doc_id := (SELECT id FROM public.documentos
               WHERE tenant_id = v_tenant AND storage_path = p_storage_path LIMIT 1);
  IF v_doc_id IS NOT NULL THEN
    UPDATE public.documentos
       SET tamanho = COALESCE(p_tamanho, 0),
           colaborador_id = COALESCE(v_colab_id, colaborador_id),
           pasta_id = COALESCE(v_pasta, pasta_id),
           updated_at = now()
     WHERE id = v_doc_id;
    RETURN json_build_object('ok', true, 'documento_id', v_doc_id, 'ja_existia', true, 'em_pasta', v_pasta IS NOT NULL);
  END IF;

  INSERT INTO public.documentos (
    tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
    nome_arquivo, nome_original, tipo, tamanho, mime_type, storage_path,
    status, observacoes, criado_por, criado_por_nome, pasta_id,
    versao_atual, total_versoes, classificacao
  ) VALUES (
    v_tenant, COALESCE(v_colab_emp, v_empresa), v_colab_id, v_nome, v_cpf,
    p_storage_path, 'Meu Mapa (Mapa Comportamental).pdf', 'Mapa Comportamental',
    COALESCE(p_tamanho, 0), 'application/pdf', p_storage_path,
    'valido', 'Relatório do Mapa Comportamental arquivado pelo próprio módulo (RF-028).',
    auth.uid(), v_nome, v_pasta, 1, 1, 'pessoal'
  )
  RETURNING id INTO v_doc_id;

  RETURN json_build_object('ok', true, 'documento_id', v_doc_id, 'ja_existia', false, 'em_pasta', v_pasta IS NOT NULL);
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('ok', false, 'erro', 'falha ao arquivar', 'detalhe', SQLERRM);
END;
$fn$;

REVOKE ALL ON FUNCTION public.mapa_comportamental_arquivar_no_prontuario(uuid, text, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mapa_comportamental_arquivar_no_prontuario(uuid, text, int) TO authenticated;
