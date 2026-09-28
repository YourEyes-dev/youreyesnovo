-- ============================================================================
-- ENTREGA — Mapa Comportamental: arquivar o PDF "Meu Mapa" no prontuário (RF-028)
--
-- Cole este arquivo inteiro no SQL Editor do projeto (roda em UMA transação).
-- Idempotente: pode rodar mais de uma vez sem quebrar nem duplicar.
--
-- O que faz: cria a RPC que grava o registro do PDF do relatório em
-- public.documentos (o upload do arquivo em si é feito pelo app, no bucket
-- "documentos", com a chave começando pelo tenant). A RPC roda como
-- SECURITY DEFINER para permitir que o PRÓPRIO titular arquive o seu mapa —
-- a escrita normal em documentos exige manager+. Autoriza o titular do mapa
-- ou um gestor/RH do mesmo tenant.
--
-- RN-009: o arquivo é filiado à subpasta "Vida Funcional" do colaborador,
-- NUNCA a "Saúde Ocupacional"; a classificação é 'pessoal', não de saúde.
--
-- Este script NÃO cria tabela e NÃO altera nem apaga dado existente — apenas
-- cria função e documenta o caso de QA. Não requer backup prévio.
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
  v_tenant   uuid;
  v_empresa  uuid;
  v_auth     uuid;
  v_cpf      text;
  v_nome     text;
  v_colab_id uuid;
  v_pasta    uuid;
  v_doc_id   uuid;
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

  IF NOT (
        auth.uid() = v_auth
     OR (public.has_minimum_role(auth.uid(), 'manager'::app_role) AND v_tenant = public.get_user_tenant_id())
  ) THEN
    RETURN json_build_object('ok', false, 'erro', 'sem permissao');
  END IF;

  IF p_storage_path IS NULL OR left(p_storage_path, length(v_tenant::text) + 1) <> v_tenant::text || '/' THEN
    RETURN json_build_object('ok', false, 'erro', 'caminho invalido');
  END IF;

  IF v_cpf IS NOT NULL THEN
    v_colab_id := (SELECT ub.id FROM public.usuarios_base ub
                   WHERE ub.tenant_id = v_tenant
                     AND regexp_replace(COALESCE(ub.cpf, ''), '[^0-9]', '', 'g') = v_cpf
                     AND COALESCE(ub.status, 'ativo') <> 'excluido'
                   ORDER BY (ub.tipo_usuario = 'colaborador') DESC, ub.created_at
                   LIMIT 1);
  END IF;

  IF v_colab_id IS NOT NULL THEN
    v_pasta := public.documento_pasta_do_colaborador(
      v_tenant, v_colab_id, v_nome, v_cpf, v_empresa, 'Vida Funcional'
    );
  END IF;

  v_doc_id := (SELECT id FROM public.documentos
               WHERE tenant_id = v_tenant AND storage_path = p_storage_path LIMIT 1);
  IF v_doc_id IS NOT NULL THEN
    UPDATE public.documentos
       SET tamanho = COALESCE(p_tamanho, 0), updated_at = now()
     WHERE id = v_doc_id;
    RETURN json_build_object('ok', true, 'documento_id', v_doc_id, 'ja_existia', true);
  END IF;

  INSERT INTO public.documentos (
    tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
    nome_arquivo, nome_original, tipo, tamanho, mime_type, storage_path,
    status, observacoes, criado_por, criado_por_nome, pasta_id,
    versao_atual, total_versoes, classificacao
  ) VALUES (
    v_tenant, v_empresa, v_colab_id, v_nome, v_cpf,
    p_storage_path, 'Meu Mapa (Mapa Comportamental).pdf', 'Mapa Comportamental',
    COALESCE(p_tamanho, 0), 'application/pdf', p_storage_path,
    'valido', 'Relatório do Mapa Comportamental arquivado pelo próprio módulo (RF-028).',
    auth.uid(), v_nome, v_pasta, 1, 1, 'pessoal'
  )
  RETURNING id INTO v_doc_id;

  RETURN json_build_object('ok', true, 'documento_id', v_doc_id, 'ja_existia', false);
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('ok', false, 'erro', 'falha ao arquivar', 'detalhe', SQLERRM);
END;
$fn$;

REVOKE ALL ON FUNCTION public.mapa_comportamental_arquivar_no_prontuario(uuid, text, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mapa_comportamental_arquivar_no_prontuario(uuid, text, int) TO authenticated;

-- ── QA — MAPA-011 ────────────────────────────────────────────────────────────
DO $doc$
DECLARE v_mod uuid;
BEGIN
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'desenvolvimento-performance/mapa-comportamental');
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo QA ausente — pulei o caso do arquivamento.';
    RETURN;
  END IF;
  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
    (v_mod, 'MAPA-011', 'Arquivar o PDF do relatório no prontuário', 'feliz', 'alta', 'aprovado', 'api',
     'A RPC de arquivamento existe e é executável pelo titular/gestor.',
     'Migration do arquivamento aplicada.',
     '[{"ordem":1,"acao":"Verificar a RPC de arquivamento e o grant a authenticated","resultado_esperado":"função presente e com EXECUTE para authenticated"}]'::jsonb,
     'RPC presente e concedida.', 'RF-028; RN-009 (vai para Vida Funcional, nunca Saúde).')
  ON CONFLICT (codigo) DO NOTHING;
  RAISE NOTICE 'OK: caso MAPA-011 documentado.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'MAPA-011 doc: %', SQLERRM;
END $doc$;

CREATE OR REPLACE FUNCTION public.qa_caso_mapa_011()
RETURNS public.qa_retorno
LANGUAGE plpgsql
AS $fn$
DECLARE r public.qa_retorno; v_ok boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Verificar a RPC de arquivamento e o grant a authenticated';
  r.esperado    := 'mapa_comportamental_arquivar_no_prontuario presente e com EXECUTE para authenticated';
  v_ok := EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.proname = 'mapa_comportamental_arquivar_no_prontuario'
          )
      AND COALESCE(
            has_function_privilege('authenticated',
              'public.mapa_comportamental_arquivar_no_prontuario(uuid, text, int)', 'EXECUTE'),
            false);
  IF v_ok THEN r.situacao := 'passou'; r.obtido := 'RPC presente e concedida';
  ELSE r.situacao := 'falhou'; r.obtido := 'RPC ausente ou sem grant'; END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END;
$fn$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES ('MAPA-011', 'qa_caso_mapa_011')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- ── Conferência final (o editor mostra só o último resultado) ────────────────
SELECT
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'mapa_comportamental_arquivar_no_prontuario') AS rpc_presente,
  has_function_privilege('authenticated',
    'public.mapa_comportamental_arquivar_no_prontuario(uuid, text, int)', 'EXECUTE') AS grant_authenticated,
  (SELECT funcao_sql FROM public.qa_implementacoes WHERE codigo = 'MAPA-011') AS qa_rotina,
  (SELECT nivel FROM public.qa_casos_teste WHERE codigo = 'MAPA-011') AS qa_nivel;
