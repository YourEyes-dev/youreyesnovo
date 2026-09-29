// Auxiliares das funções públicas do site (meta-capi, hubspot-lead).
//
// As duas são chamadas pelo navegador do visitante, sem login
// (verify_jwt = false). A proteção de ambiente é a ORIGEM da chamada: por
// padrão só o site de produção é aceito. Assim, o site de teste, os domínios
// do Lovable, o localhost e as pré-visualizações — que usam o mesmo código e,
// às vezes, a mesma base — não mandam evento para a Meta nem contato para o
// HubSpot. Para validar no ambiente de teste, libere o host de teste pelo
// secret SITE_HOSTS_PERMITIDOS daquele projeto (lista separada por vírgula).
//
// Nenhuma URL ou chave de projeto aqui: só os hosts públicos do site.

const HOSTS_PADRAO = ["youreyes.com.br", "www.youreyes.com.br"];

export function hostsPermitidos(): string[] {
  const env = (Deno.env.get("SITE_HOSTS_PERMITIDOS") ?? "").trim();
  if (!env) return HOSTS_PADRAO;
  return env.split(",").map((h) => h.trim().toLowerCase()).filter(Boolean);
}

/** Host de quem chamou: cabeçalho Origin (o navegador sempre manda em POST
 *  entre domínios) e, na falta dele, o Referer. */
export function hostDaChamada(req: Request): string {
  for (const cab of ["origin", "referer"]) {
    const v = req.headers.get(cab);
    if (!v) continue;
    try {
      return new URL(v).hostname.toLowerCase();
    } catch {
      /* tenta o próximo */
    }
  }
  return "";
}

export function hostPermitido(host: string): boolean {
  return Boolean(host) && hostsPermitidos().includes(host);
}

export function corsHeaders(req: Request): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": req.headers.get("origin") || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "content-type, authorization, apikey, x-client-info",
    "Vary": "Origin",
  };
}

export function json(req: Request, corpo: unknown, status = 200): Response {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { ...corsHeaders(req), "Content-Type": "application/json" },
  });
}

/** Lê o corpo como JSON. O front manda em text/plain (sem preflight), por
 *  isso não dá para confiar no Content-Type. Corpo acima de 16 KB é recusado. */
export async function lerCorpo(req: Request): Promise<Record<string, unknown> | null> {
  try {
    const texto = await req.text();
    if (!texto || texto.length > 16_384) return null;
    const obj = JSON.parse(texto);
    return obj && typeof obj === "object" && !Array.isArray(obj) ? obj as Record<string, unknown> : null;
  } catch {
    return null;
  }
}

export function texto(v: unknown, max: number): string {
  return typeof v === "string" ? v.trim().slice(0, max) : "";
}

export const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

/** Telefone só com dígitos e com o código do país. Número brasileiro
 *  digitado sem o 55 (10 ou 11 dígitos: DDD + número) ganha o 55. */
export function telefoneE164(v: unknown): string {
  const d = String(v ?? "").replace(/\D/g, "");
  if (!d) return "";
  if ((d.length === 10 || d.length === 11) && !d.startsWith("55")) return `55${d}`;
  return d;
}

export async function sha256Hex(valor: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(valor));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Domínio do e-mail — o máximo de identificação que vai para o log. */
export function dominioEmail(email: string): string {
  const i = email.lastIndexOf("@");
  return i >= 0 ? email.slice(i + 1) : "";
}
