// ─────────────────────────────────────────────────────────────────────────────
// Mapa Comportamental — arquivar o PDF do relatório no prontuário (RF-028).
//
// O titular exporta o PDF e uma cópia é arquivada no módulo Documentos, na
// pasta funcional do colaborador. O upload do arquivo vai direto para o bucket
// "documentos" (permitido a qualquer membro do tenant, desde que a chave comece
// pelo tenant_id); o REGISTRO em public.documentos — cuja escrita normalmente
// exige manager+ — é gravado por uma RPC SECURITY DEFINER que autoriza o
// próprio titular. Caminho determinístico por mapa: a reexportação sobrescreve
// o mesmo objeto (idempotente, um único documento por mapa).
// ─────────────────────────────────────────────────────────────────────────────

import { supabase } from "@/integrations/supabase/client";
import { rpcUntyped } from "@/integrations/supabase/untypedClient";
import { useAuth } from "./useAuth";

export type ResultadoArquivo =
  | { arquivado: true; jaExistia: boolean }
  | { arquivado: false; motivo: string };

export function useMapaComportamentalArquivo() {
  const { tenantId } = useAuth();

  // Best-effort: nunca lança. O download do PDF é o que importa; o
  // arquivamento é um efeito colateral e não deve travar a experiência.
  const arquivar = async (blob: Blob, mapaId: string): Promise<ResultadoArquivo> => {
    if (!tenantId || !mapaId) return { arquivado: false, motivo: "sem contexto" };
    // Chave começando pelo tenant (exigência da política do bucket) e estável
    // por mapa (a nova exportação substitui a anterior).
    const path = `${tenantId}/mapa-comportamental/${mapaId}.pdf`;
    try {
      const { error: upErr } = await supabase.storage
        .from("documentos")
        .upload(path, blob, { contentType: "application/pdf", upsert: true });
      if (upErr) return { arquivado: false, motivo: upErr.message };

      const { data, error } = await rpcUntyped("mapa_comportamental_arquivar_no_prontuario", {
        p_mapa_id: mapaId,
        p_storage_path: path,
        p_tamanho: blob.size,
      });
      if (error) return { arquivado: false, motivo: error.message };
      if (data && data.ok) return { arquivado: true, jaExistia: !!data.ja_existia };
      return { arquivado: false, motivo: (data && data.erro) || "recusado" };
    } catch (e) {
      return { arquivado: false, motivo: e instanceof Error ? e.message : "erro" };
    }
  };

  return { arquivar };
}
