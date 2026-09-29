/**
 * Meta Pixel + Conversions API (deduplicados pelo mesmo event_id).
 *
 * O navegador dispara o evento pelo Pixel e o mesmo evento segue para a
 * Edge Function `meta-capi` (servidor). Como os dois carregam o MESMO
 * `event_id`, a Meta conta uma conversão só.
 *
 * O Pixel só existe nos hosts de produção (ver `index.html` e
 * `HOSTS_PRODUCAO`): fora deles `window.fbq` não existe e a chamada do Pixel
 * vira no-op. A chamada ao servidor sai sempre — é a função quem decide, pela
 * origem, se aquele envio vale (o teste pode ser liberado lá por secret, sem
 * contaminar o dataset de produção).
 *
 * Por que `text/plain` e sem cabeçalhos extras: assim a chamada é uma
 * "requisição simples" — o navegador não faz o preflight de CORS, e o
 * `keepalive` funciona mesmo se o visitante sair da página logo depois.
 * A função tem `verify_jwt = false` (é pública por natureza, como o Pixel).
 */

import { lerOrigemGuardada } from "@/lib/siteOrigem";

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

/**
 * `fbc` = cookie _fbc do Pixel; sem ele (Pixel bloqueado, cookie ainda não
 * gravado), monta pelo fbclid guardado na chegada, no formato da Meta:
 * `fb.1.<timestamp ms>.<fbclid>`.
 */
export function montarFbc(): string | undefined {
  const cookie = lerCookie("_fbc");
  if (cookie) return cookie;
  const origem = lerOrigemGuardada();
  if (origem?.fbclid) return `fb.1.${origem.fbclid_em ?? Date.now()}.${origem.fbclid}`;
  return undefined;
}

export interface TrackConversionData {
  email?: string | null;
  phone?: string | null;
  url?: string | null;
}

/**
 * Dispara um evento de conversão no Pixel e na CAPI, com o mesmo event_id.
 * Nunca lança: falha de rastreamento não pode quebrar a tela do visitante.
 * Devolve o event_id usado.
 */
export function trackConversion(
  eventName: "Lead" | "Contact" | string,
  data: TrackConversionData = {},
): string {
  const eventId = novoEventId();
  let eventSourceUrl = "";
  try {
    eventSourceUrl = data.url ?? (typeof window !== "undefined" ? window.location.href : "");
  } catch {
    /* sem window */
  }

  try {
    window.fbq?.("track", eventName, {}, { eventID: eventId });
  } catch (e) {
    console.warn("[meta] Pixel indisponível:", e);
  }

  try {
    void fetch(CAPI_URL, {
      method: "POST",
      headers: { "Content-Type": "text/plain;charset=UTF-8" },
      keepalive: true,
      body: JSON.stringify({
        event_name: eventName,
        event_id: eventId,
        event_source_url: eventSourceUrl,
        email: data.email?.trim().toLowerCase() || undefined,
        phone: data.phone?.replace(/\D/g, "") || undefined,
        fbp: lerCookie("_fbp") || undefined,
        fbc: montarFbc(),
      }),
    }).catch((e) => console.warn("[meta] CAPI indisponível:", e));
  } catch (e) {
    console.warn("[meta] CAPI indisponível:", e);
  }

  return eventId;
}
