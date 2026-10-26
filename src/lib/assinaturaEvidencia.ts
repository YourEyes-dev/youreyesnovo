import { supabase } from "@/integrations/supabase/client";

/**
 * ASS-0001 — FASE 0: evidência de liveness da assinatura forte, em bucket PRIVADO
 * e NEUTRO (serve qualquer módulo). Generaliza src/lib/epiEvidencia.ts sem tocá-lo.
 *
 * Os frames do rosto (biometria, LGPD art. 11) nunca viram URL pública: ficam no
 * bucket privado `assinatura-evidencias` (migration 20261026203310), sob a pasta
 * da empresa, e são lidos por link assinado de curta duração.
 */
export const BUCKET_EVIDENCIA_ASSINATURA = "assinatura-evidencias";

/** Tipo do arquivo de uma imagem em data URL (padrão png). */
export function tipoDaImagem(dataUrl: string): string {
  return /^data:([^;,]+)[;,]/.exec(dataUrl)?.[1] ?? "image/png";
}

/** Converte um data URL (ex.: canvas.toDataURL) em Blob para upload. */
export function dataUrlParaBlob(dataUrl: string): Blob {
  const [cabecalho, corpo] = dataUrl.split(",");
  const tipo = tipoDaImagem(dataUrl);
  const ehBase64 = /;base64/i.test(cabecalho);
  const binario = ehBase64 ? atob(corpo) : decodeURIComponent(corpo);
  const bytes = new Uint8Array(binario.length);
  for (let i = 0; i < binario.length; i++) bytes[i] = binario.charCodeAt(i);
  return new Blob([bytes], { type: tipo });
}

/**
 * Link de leitura de uma evidência, de curta duração.
 *
 * Caminhos no bucket privado viram link assinado; uma URL completa (fichas antigas,
 * migração à parte) é devolvida como está.
 */
export async function urlDaEvidencia(
  referencia: string | null | undefined,
  segundos = 300,
): Promise<string | null> {
  if (!referencia) return null;
  if (/^https?:\/\//i.test(referencia)) return referencia;
  const { data, error } = await supabase.storage
    .from(BUCKET_EVIDENCIA_ASSINATURA)
    .createSignedUrl(referencia, segundos);
  if (error || !data) return null;
  return data.signedUrl;
}

export interface PersistirFramesParams {
  /** Empresa dona da evidência; é o PRIMEIRO nível do caminho (a política RLS confere). */
  tenantId: string;
  /** Módulo/fluxo que colheu a evidência (ex.: 'advertencia', 'epi'). */
  contexto: string;
  /** Id/token do documento ou ato ao qual a evidência pertence. */
  referenciaId: string;
  /** Frames capturados (data URLs do canvas). */
  frames: string[];
}

/**
 * Persiste os frames da verificação de presença no bucket privado e devolve os
 * CAMINHOS gravados (não data URLs). Grava em
 *   {tenantId}/{contexto}/{referenciaId}/{timestamp}-{i}.{ext}
 * Frames que falharem são pulados; devolve só os que subiram.
 */
export async function persistirFramesDaEvidencia(
  params: PersistirFramesParams,
): Promise<string[]> {
  const { tenantId, contexto, referenciaId, frames } = params;
  const base = `${tenantId}/${contexto}/${referenciaId}`;
  const timestamp = Date.now();
  const caminhos: string[] = [];

  for (let i = 0; i < frames.length; i++) {
    const frame = frames[i];
    if (!frame) continue;
    const blob = dataUrlParaBlob(frame);
    const ext = (blob.type.split("/")[1] || "jpg").replace("jpeg", "jpg");
    const caminho = `${base}/${timestamp}-${i}.${ext}`;
    const { error } = await supabase.storage
      .from(BUCKET_EVIDENCIA_ASSINATURA)
      .upload(caminho, blob, { contentType: blob.type, upsert: false });
    if (!error) caminhos.push(caminho);
    else console.warn("[assinaturaEvidencia] frame não subiu:", caminho, error);
  }

  return caminhos;
}
