// =========================================================
// ASS-0001 — FASE 0: arquivo canônico para as edges (sobe o arquivo + chama a RPC).
//
// Hoje cada edge de assinatura por link faz o seu próprio insert em public.documentos,
// com colunas divergentes (nome/categoria/formato que a tabela nem tem) e sem resolver
// pasta nem gravar auditoria. Este módulo dá um caminho ÚNICO: sobe o binário ao
// bucket `documentos` e chama a RPC public.arquivar_documento_servidor, que resolve a
// pasta (colaborador/categoria), insere em documentos e grava documento_audit_logs.
// Espelha src/utils/arquivarDocumento.ts; a RPC é a fonte única da verdade.
//
// NÃO toca módulo nenhum: é a peça reutilizável que a fase 1 ligará nas edges.
// O cliente é tipado de forma frouxa de propósito (supabase-js do edge-runtime).
// =========================================================

// deno-lint-ignore no-explicit-any
type SupabaseLike = any;

export interface ArquivarDocumentoParams {
  tenantId: string;
  empresaId?: string | null;
  userId?: string | null;
  userNome?: string | null;
  /** Conteúdo do arquivo a subir. */
  file: Blob | Uint8Array | ArrayBuffer;
  fileName: string;
  mimeType?: string;
  /** Caminho no bucket `documentos`. Se omitido, é montado por tenant/colaborador/timestamp. */
  storagePath?: string;
  tipo: string;
  observacoes?: string | null;
  dataValidade?: string | null;
  colaboradorId?: string | null;
  colaboradorNome?: string | null;
  colaboradorCpf?: string | null;
  pastaCategoria?:
    | "SST" | "Ergonomia" | "Psicossocial" | "Ponto" | "Financeiro"
    | "Desligamento" | "Admissão" | "Aprendizado" | "Cultura" | null;
  subpastaColaborador?: "Admissão" | "Vida Funcional" | "Saúde Ocupacional" | "Desligamento" | null;
}

export interface ArquivarDocumentoResultado {
  id: string;
  storagePath: string;
  pastaId: string | null;
  status: string;
}

function tamanhoDe(file: Blob | Uint8Array | ArrayBuffer): number {
  if (file instanceof Blob) return file.size;
  if (file instanceof Uint8Array) return file.byteLength;
  return (file as ArrayBuffer).byteLength;
}

/**
 * Sobe o arquivo ao bucket `documentos` e registra o documento pelo servidor.
 * Em falha de upload, devolve null sem registrar; em falha de registro, remove o
 * arquivo recém-subido (limpeza), espelhando o util do app. NÃO lança: devolve null.
 */
export async function arquivarDocumentoServidor(
  supabase: SupabaseLike,
  params: ArquivarDocumentoParams,
): Promise<ArquivarDocumentoResultado | null> {
  const mimeType = params.mimeType ?? "application/pdf";
  const safeName = params.fileName.replace(/[^a-zA-Z0-9._-]/g, "_");
  const timestamp = Date.now();
  const storagePath = params.storagePath ?? (
    params.colaboradorId
      ? `${params.tenantId}/colaboradores/${params.colaboradorId}/${timestamp}_${safeName}`
      : `${params.tenantId}/${timestamp}_${safeName}`
  );

  const { error: uploadError } = await supabase.storage
    .from("documentos")
    .upload(storagePath, params.file, { contentType: mimeType, upsert: false });
  if (uploadError) {
    console.error("[arquivarDocumentoServidor] upload falhou:", uploadError);
    return null;
  }

  const { data, error } = await supabase.rpc("arquivar_documento_servidor", {
    p_doc: {
      tenant_id: params.tenantId,
      empresa_id: params.empresaId ?? null,
      user_id: params.userId ?? null,
      user_nome: params.userNome ?? null,
      colaborador_id: params.colaboradorId ?? null,
      colaborador_nome: params.colaboradorNome ?? null,
      colaborador_cpf: params.colaboradorCpf ?? null,
      pasta_categoria: params.pastaCategoria ?? null,
      subpasta_colaborador: params.subpastaColaborador ?? null,
      storage_path: storagePath,
      file_name: params.fileName,
      mime_type: mimeType,
      tamanho: tamanhoDe(params.file),
      tipo: params.tipo,
      observacoes: params.observacoes ?? null,
      data_validade: params.dataValidade ?? null,
    },
  });

  if (error || !data) {
    console.error("[arquivarDocumentoServidor] registro falhou, removendo arquivo:", error);
    await supabase.storage.from("documentos").remove([storagePath]);
    return null;
  }

  return {
    id: data.id,
    storagePath: data.storage_path ?? storagePath,
    pastaId: data.pasta_id ?? null,
    status: data.status ?? "valido",
  };
}
