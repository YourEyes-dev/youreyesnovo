/**
 * Meta Pixel + Conversions API (deduplicados pelo mesmo event_id).
 *
 * O navegador dispara o evento pelo Pixel e o mesmo evento segue para a
 * Edge Function `meta-capi` (servidor). Como os dois carregam o MESMO
 * `event_id`, a Meta conta uma conversão só.
 */

type Fbq = (...args: unknown[]) => void;

declare global {
  interface Window {
    fbq?: Fbq;
  }
}

const CAPI_URL = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/meta-capi`;

/** Lê um cookie do navegador (usado para _fbp e _fbc). */
function lerCookie(nome: string): string | null {
  if (typeof document === "undefined") return null;
  const achado = document.cookie
    .split("; ")
    .find((c) => c.startsWith(`${nome}=`));
  return achado ? decodeURIComponent(achado.slice(nome.length + 1)) : null;
}

function novoEventId(): string {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  return `ev-${Date.now()}-${Math.random().toString(36).slice(2, 12)}`;
}

export interface TrackConversionData {
  email?: string | null;
  phone?: string | null;
  url?: string | null;
}

/**
 * Dispara um evento de conversão no Pixel e na CAPI.
 * Nunca lança: falha de rastreamento não pode quebrar a tela do visitante.
 */
export function trackConversion(
  eventName: "Lead" | "Contact" | string,
  data: TrackConversionData = {},
): string {
  const eventId = novoEventId();
  const eventSourceUrl =
    data.url ?? (typeof window !== "undefined" ? window.location.href : "");

  try {
    window.fbq?.("track", eventName, {}, { eventID: eventId });
  } catch (e) {
    console.warn("[meta] Pixel indisponível:", e);
  }

  try {
    void fetch(CAPI_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      keepalive: true,
      body: JSON.stringify({
        event_name: eventName,
        event_id: eventId,
        event_source_url: eventSourceUrl,
        email: data.email?.trim().toLowerCase() || undefined,
        phone: data.phone?.replace(/\D/g, "") || undefined,
        fbp: lerCookie("_fbp") || undefined,
        fbc: lerCookie("_fbc") || undefined,
      }),
    }).catch((e) => console.warn("[meta] CAPI indisponível:", e));
  } catch (e) {
    console.warn("[meta] CAPI indisponível:", e);
  }

  return eventId;
}
