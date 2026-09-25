/**
 * Utility to auto-archive generated documents to the Documentos module.
 * Resolves collaborator folders under "Gestão de Pessoas" and SST/company folders.
 * Creates audit log entries for traceability.
 */
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { criarPastaColaborador } from "./criarPastaColaborador";

interface ArquivarDocumentoParams {
  tenantId: string;
  empresaId?: string | null;
  userId: string;
  userNome: string;
  // File
  file: Blob;
  fileName: string;
  mimeType?: string;
  // Metadata
  tipo: string;
  observacoes?: string;
  dataValidade?: string | null;
  // Collaborator (optional — if provided, archives in collaborator folder)
  colaboradorId?: string | null;
  colaboradorNome?: string | null;
  colaboradorCpf?: string | null;
  // Target folder category (used when no collaborator)
  pastaCategoria?: "SST" | "Ergonomia" | "Psicossocial" | "Ponto" | "Financeiro" | "Desligamento" | "Admissão" | "Aprendizado" | "Cultura" | null;
  // Subfolder inside collaborator folder
  subpastaColaborador?: "Admissão" | "Vida Funcional" | "Saúde Ocupacional" | "Desligamento" | null;
  // Subfolder inside the "Cultura Organizacional" folder (used with pastaCategoria "Cultura")
  subpastaCultura?: "Manual de Cultura" | "Documentos da Cultura" | null;
}

/**
 * Finds or creates the appropriate folder for a collaborator under "Gestão de Pessoas".
 * Delegates to the shared criarPastaColaborador utility.
 * Returns the pasta_id (or subfolder id if subpasta is specified).
 */
async function findOrCreateColaboradorPasta(
  tenantId: string,
  colaboradorId: string,
  colaboradorNome: string,
  colaboradorCpf?: string | null,
  subpasta?: string | null,
  empresaId?: string | null
): Promise<string | null> {
  const colabPastaId = await criarPastaColaborador({
    tenantId,
    colaboradorId,
    colaboradorNome,
    colaboradorCpf,
    empresaId,
  });

  // If subpasta requested, find it inside the collaborator folder
  if (colabPastaId && subpasta) {
    const { data: sub } = await supabase
      .from("documento_pastas")
      .select("id")
      .eq("tenant_id", tenantId)
      .eq("pasta_pai_id", colabPastaId)
      .eq("nome", subpasta)
      .maybeSingle();

    if (sub?.id) return sub.id;
  }

  return colabPastaId;
}

/**
 * Finds the appropriate company-level folder for non-collaborator documents.
 */
async function findCategoriaPasta(
  tenantId: string,
  categoria: string
): Promise<string | null> {
  // Map categories to expected folder names
  const FOLDER_MAP: Record<string, string[]> = {
    SST: ["SST e Segurança do Trabalho", "SST da Empresa"],
    Ergonomia: ["Ergonomia", "AEP — Avaliação Ergonômica Preliminar"],
    Psicossocial: ["Riscos Psicossociais (NR-01)", "Diagnóstico Psicossocial"],
    Ponto: ["Gestão de Pessoas", "Processos Organizacionais"],
    Financeiro: ["Processos Organizacionais", "Gestão de Pessoas"],
    Desligamento: ["Gestão de Pessoas"],
    "Admissão": ["Gestão de Pessoas"],
    Aprendizado: ["Processos Organizacionais", "Gestão de Pessoas"],
    // "Cultura" é resolvida por findOrCreateCulturaPasta (pasta dedicada, criada
    // sob demanda), não por este mapa.
  };

  const candidates = FOLDER_MAP[categoria] || [categoria];

  for (const nome of candidates) {
    const { data } = await supabase
      .from("documento_pastas")
      .select("id")
      .eq("tenant_id", tenantId)
      .eq("nome", nome)
      .limit(1)
      .maybeSingle();

    if (data?.id) return data.id;
  }

  return null;
}

/**
 * Finds or creates a folder by name at a given level (root or under a parent),
 * scoped by tenant + empresa so it matches how the Documentos module lists folders.
 */
async function findOrCreatePastaPorNome(
  tenantId: string,
  empresaId: string | null | undefined,
  nome: string,
  parentId: string | null,
  tipo: string,
  ordem: number,
  icone: string | null,
  userId: string,
  userNome: string | null
): Promise<string | null> {
  let query = supabase
    .from("documento_pastas")
    .select("id")
    .eq("tenant_id", tenantId)
    .eq("nome", nome);

  query = parentId ? query.eq("pasta_pai_id", parentId) : query.is("pasta_pai_id", null);
  query = empresaId ? query.eq("empresa_id", empresaId) : query.is("empresa_id", null);

  const { data: existente } = await query.limit(1).maybeSingle();
  if (existente?.id) return existente.id;

  const { data: nova, error } = await supabase
    .from("documento_pastas")
    .insert({
      tenant_id: tenantId,
      empresa_id: empresaId || null,
      nome,
      tipo,
      pasta_pai_id: parentId,
      ordem,
      icone,
      criado_por: userId,
      criado_por_nome: userNome,
    } as any)
    .select("id")
    .single();

  if (error || !nova) {
    console.warn("[arquivarDocumento] Não foi possível criar a pasta:", nome, error);
    return null;
  }
  return (nova as any).id;
}

/**
 * Resolves (creating on demand) the "Cultura Organizacional" folder and its
 * subfolder. Mirrors the STANDARD_STRUCTURE node, so tenants that never rodaram
 * o assistente de estrutura também ganham a pasta ao salvar o primeiro documento.
 */
async function findOrCreateCulturaPasta(
  tenantId: string,
  empresaId: string | null | undefined,
  subpasta: string | null | undefined,
  userId: string,
  userNome: string | null
): Promise<string | null> {
  const rootId = await findOrCreatePastaPorNome(
    tenantId, empresaId, "Cultura Organizacional", null, "root", 4, "Heart", userId, userNome
  );
  if (!rootId) return null;
  if (!subpasta) return rootId;

  const ordem = subpasta === "Manual de Cultura" ? 0 : 1;
  const icone = subpasta === "Manual de Cultura" ? "FileText" : "FileCheck";
  const subId = await findOrCreatePastaPorNome(
    tenantId, empresaId, subpasta, rootId, "categoria", ordem, icone, userId, userNome
  );
  return subId || rootId;
}

/**
 * Archives a generated document to Supabase Storage + creates a record in the `documentos` table.
 * Automatically resolves the correct folder and creates audit trail.
 */
export async function arquivarDocumento(params: ArquivarDocumentoParams): Promise<{ id: string; storagePath: string } | null> {
  const {
    tenantId,
    empresaId,
    userId,
    userNome,
    file,
    fileName,
    mimeType = "application/pdf",
    tipo,
    observacoes,
    dataValidade,
    colaboradorId,
    colaboradorNome,
    colaboradorCpf,
    pastaCategoria,
    subpastaColaborador,
    subpastaCultura,
  } = params;

  try {
    // 1. Build storage path
    const timestamp = Date.now();
    const safeName = fileName.replace(/[^a-zA-Z0-9._-]/g, "_");
    const storagePath = colaboradorId
      ? `${tenantId}/colaboradores/${colaboradorId}/${timestamp}_${safeName}`
      : `${tenantId}/${timestamp}_${safeName}`;

    // 2. Upload to storage
    const { error: uploadError } = await supabase.storage
      .from("documentos")
      .upload(storagePath, file, { contentType: mimeType, upsert: false });

    if (uploadError) throw uploadError;

    // 3. Resolve target folder
    let pastaId: string | null = null;

    if (colaboradorId && colaboradorNome) {
      pastaId = await findOrCreateColaboradorPasta(
        tenantId,
        colaboradorId,
        colaboradorNome,
        colaboradorCpf,
        subpastaColaborador,
        empresaId
      );
    } else if (pastaCategoria === "Cultura") {
      pastaId = await findOrCreateCulturaPasta(tenantId, empresaId, subpastaCultura, userId, userNome);
    } else if (pastaCategoria) {
      pastaId = await findCategoriaPasta(tenantId, pastaCategoria);
    }

    // 4. Calculate status based on expiry date
    let status: "valido" | "vencendo" | "vencido" = "valido";
    if (dataValidade) {
      const validade = new Date(dataValidade);
      const hoje = new Date();
      const trintaDiasAntes = new Date(validade);
      trintaDiasAntes.setDate(trintaDiasAntes.getDate() - 30);

      if (validade < hoje) status = "vencido";
      else if (hoje > trintaDiasAntes) status = "vencendo";
    }

    // 5. Insert document record
    const { data: docData, error: docError } = await fromTable("documentos")
      .insert({
        tenant_id: tenantId,
        empresa_id: empresaId || null,
        colaborador_id: colaboradorId || null,
        colaborador_nome: colaboradorNome || "",
        colaborador_cpf: colaboradorCpf || null,
        nome_arquivo: storagePath,
        nome_original: fileName,
        tipo,
        tamanho: file.size,
        mime_type: mimeType,
        storage_path: storagePath,
        data_validade: dataValidade || null,
        status,
        observacoes: observacoes || null,
        criado_por: userId,
        criado_por_nome: userNome,
        pasta_id: pastaId,
        versao_atual: 1,
        total_versoes: 1,
      } as any)
      .select("id")
      .single();

    if (docError) {
      // Cleanup storage on failure
      await supabase.storage.from("documentos").remove([storagePath]);
      throw docError;
    }

    // 6. Create audit log
    try {
      await fromTable("documento_audit_logs").insert({
        tenant_id: tenantId,
        documento_id: (docData as any).id,
        documento_nome: fileName,
        acao: "upload",
        pasta_destino_id: pastaId,
        pasta_destino_nome: tipo,
        usuario_id: userId,
        usuario_nome: userNome,
      } as any);
    } catch { /* non-blocking */ }

    return { id: (docData as any).id, storagePath };
  } catch (error) {
    console.error("[arquivarDocumento] Erro:", error);
    return null;
  }
}
