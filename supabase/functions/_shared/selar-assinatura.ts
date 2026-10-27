// =========================================================
// ASS-0001 — FASE 0: o selo de assinatura no SERVIDOR, para as edges por link.
//
// As edges de assinatura por link (advertencia-link, experiencia-assinatura, ...)
// recebem a requisição do navegador do signatário DIRETO. Por isso é AQUI, na edge,
// que a origem confiável pode ser lida: os cabeçalhos cf-connecting-ip /
// x-forwarded-for chegam à edge com o IP do signatário. Se a edge insere com
// service_role e deixa o banco derivar `request.headers`, ele veria os cabeçalhos
// da chamada edge->PostgREST, não os do signatário. Então a edge deriva a origem e
// SELA o hash, e grava valores já prontos (ou chama as RPCs que fazem isso).
//
// Espelha, em Deno, as funções SQL public.selar_assinatura e
// public.selar_assinatura_origem (migration 20261026203238). A fórmula do hash e a
// canonização da hora (ISO-8601 UTC com milissegundos) são idênticas, de modo que
// o mesmo ato produz o MESMO selo nos dois lados.
//
// NÃO importa nada externo e NÃO toca módulo nenhum: é só a peça reutilizável.
// =========================================================

export interface OrigemDaAssinatura {
  /** IP do signatário, do cf-connecting-ip (preferido) ou do 1º x-forwarded-for; null se ausente. */
  ip: string | null;
  /** Dispositivo (user-agent) do cabeçalho; null se ausente. */
  userAgent: string | null;
  /** Hora do servidor (relógio da edge), em ISO-8601 UTC com milissegundos. */
  assinadoEm: string;
}

/**
 * Deriva a origem (IP, dispositivo, hora) dos cabeçalhos da requisição que chegou
 * à edge — nunca do corpo. Prefere cf-connecting-ip (o Cloudflare o define e o
 * cliente não forja) e cai para o primeiro endereço de x-forwarded-for.
 */
export function origemDaRequisicao(req: Request): OrigemDaAssinatura {
  const cf = req.headers.get("cf-connecting-ip")?.trim();
  const xff = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  const ua = req.headers.get("user-agent")?.trim();
  return {
    ip: cf || xff || null,
    userAgent: ua || null,
    assinadoEm: new Date().toISOString(),
  };
}

export interface EntradaDoSelo {
  /** Conteúdo ou referência do documento assinado (ex.: URL da assinatura, id do doc). */
  conteudo?: string | null;
  /** Quem/como assinou (ex.: nome do recebedor, papel). */
  assinatura?: string | null;
  /** Hora da assinatura; aceita ISO string ou Date (canonizada para ISO UTC ms). */
  quando: string | Date;
  /** Identificador do registro/documento. */
  id: string;
}

/**
 * Calcula o selo de integridade (sha256 hex) sobre
 *   conteudo | assinatura | hora-ISO-UTC-ms | id
 * exatamente como public.selar_assinatura no banco. A hora é canonizada por
 * toISOString() (ex.: 2026-10-26T20:32:38.123Z), que casa com o to_char do SQL.
 */
export async function selarAssinatura(entrada: EntradaDoSelo): Promise<string> {
  const quandoIso = typeof entrada.quando === "string"
    ? new Date(entrada.quando).toISOString()
    : entrada.quando.toISOString();
  const base = [
    entrada.conteudo ?? "",
    entrada.assinatura ?? "",
    quandoIso,
    entrada.id ?? "",
  ].join("|");
  const bytes = new TextEncoder().encode(base);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
