import { supabase } from "@/integrations/supabase/client";

const BUCKET = "ponto-selfies";

/**
 * Caminho do arquivo no bucket a partir do que está gravado na marcação.
 * Registros antigos guardam a URL pública inteira; os novos guardam só o
 * caminho. Mesma regra da função SQL public.ponto_selfie_caminho.
 */
export function caminhoSelfie(valor: string | null | undefined): string | null {
  if (!valor) return null;
  const marca = `/${BUCKET}/`;
  const i = valor.indexOf(marca);
  const bruto = i >= 0 ? valor.slice(i + marca.length) : valor;
  const semQuery = bruto.split("?")[0];
  try {
    return decodeURIComponent(semQuery);
  } catch {
    return semQuery;
  }
}

/**
 * Link temporário (10 min) para exibir a selfie. O bucket é privado: só quem
 * está logado e é da empresa da marcação consegue gerar (LGPD arts. 11 e 46).
 */
export async function urlTemporariaSelfie(valor: string | null | undefined): Promise<string | null> {
  const caminho = caminhoSelfie(valor);
  if (!caminho) return null;
  const { data, error } = await supabase.storage.from(BUCKET).createSignedUrl(caminho, 600);
  if (error) {
    console.error("Falha ao gerar link da selfie", error);
    return null;
  }
  return data?.signedUrl ?? null;
}
