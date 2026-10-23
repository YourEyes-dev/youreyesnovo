import { supabase } from "@/integrations/supabase/client";

/** Bucket PRIVADO da evidência de entrega de EPI (foto do rosto e assinatura). */
export const BUCKET_EVIDENCIA_EPI = "epi-evidencias";

/**
 * Link de leitura da evidência de uma entrega, de curta duração.
 *
 * As entregas novas guardam o CAMINHO do arquivo no bucket privado; as antigas
 * guardam a URL pública do bucket epi-signatures (até a migração dos arquivos).
 * URL completa é devolvida como está; caminho vira link assinado.
 */
export async function urlDaEvidenciaEpi(
  referencia: string | null | undefined,
  segundos = 300
): Promise<string | null> {
  if (!referencia) return null;
  if (/^https?:\/\//i.test(referencia)) return referencia;
  const { data, error } = await supabase.storage
    .from(BUCKET_EVIDENCIA_EPI)
    .createSignedUrl(referencia, segundos);
  if (error || !data) return null;
  return data.signedUrl;
}

/**
 * A entrega só pode ser gravada como ASSINADA com a foto e a imagem da
 * assinatura em mãos. Devolve a mensagem do que falta, ou null se está tudo certo.
 * (A recusa de assinatura não leva foto nem assinatura.)
 */
export function evidenciaFaltandoNaEntrega(
  status: "entregue" | "recusado",
  foto: string | null | undefined,
  assinatura: string | null | undefined
): string | null {
  if (status !== "entregue") return null;
  if (!assinatura) return "a assinatura do colaborador não foi capturada";
  if (!foto) return "a foto do colaborador não foi capturada";
  return null;
}

/** Tipo do arquivo de uma imagem em data URL (padrão png). */
export function tipoDaImagem(dataUrl: string): string {
  return /^data:([^;,]+)[;,]/.exec(dataUrl)?.[1] ?? "image/png";
}
