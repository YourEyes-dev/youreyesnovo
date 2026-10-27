-- =========================================================
-- ASS-0001 — FASE 0: arquivo canônico no SERVIDOR (documentos + auditoria).
--
-- Hoje cada edge de assinatura por link arquiva o documento assinado fazendo o
-- SEU próprio insert em public.documentos, com colunas divergentes do util canônico
-- do app (src/utils/arquivarDocumento.ts). Ex.: experiencia-assinatura insere
-- `nome/categoria/subcategoria/formato` — colunas que a tabela NÃO tem — e sem
-- resolver a pasta do colaborador nem gravar auditoria. Resultado: documento
-- arquivado torto (ou nem arquivado) e sem trilha.
--
-- CORREÇÃO (fundação): uma RPC única que espelha o arquivarDocumento.ts: resolve a
-- pasta do colaborador (sob "Gestão de Pessoas", criando a pasta e as subpastas
-- padrão sob demanda) OU a pasta da categoria; insere em public.documentos com as
-- colunas certas; e grava public.documento_audit_logs. As edges passam a chamar
-- esta RPC (via _shared/arquivar-documento.ts) em vez de inserir à mão.
--
-- O UPLOAD do arquivo ao storage continua na camada Deno/cliente (SQL não sobe
-- binário): esta RPC recebe o storage_path já gravado e cuida só dos REGISTROS.
--
-- documento_audit_logs é criada aqui com IF NOT EXISTS porque nasceu fora das
-- migrations em produção (padrão da casa p/ objetos de produção, ver CLAUDE.md).
-- Não se mexe na RLS dela: fica como já está em produção (o app autenticado grava).
--
-- SECURITY DEFINER: as edges chamam com service_role e o arquivamento é ato do
-- servidor. NÃO toca módulo nenhum. Idempotente.
-- =========================================================

SET lock_timeout = '10s';

CREATE TABLE IF NOT EXISTS public.documento_audit_logs (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL,
  documento_id        uuid,
  documento_nome      text,
  acao                text NOT NULL,
  pasta_destino_id    uuid,
  pasta_destino_nome  text,
  usuario_id          uuid,
  usuario_nome        text,
  created_at          timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.documento_audit_logs IS
  'Trilha de auditoria do modulo Documentos (upload/mover/excluir). Trazida para as migrations por IF NOT EXISTS (nasceu fora delas em producao).';

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
