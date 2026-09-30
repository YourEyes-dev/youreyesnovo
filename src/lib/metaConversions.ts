/**
 * Meta Pixel + Conversions API (deduplicados pelo mesmo event_id).
 *
 * O navegador dispara o evento pelo Pixel e o mesmo evento segue para a
 * Edge Function `meta-capi` (servidor). Como os dois carregam o MESMO
 * `event_id`, a Meta conta uma conversão só.
 *
 * O Pixel NÃO carrega mais no index.html. O app logado e o site institucional
 * dividem o domínio (a raiz "/" é o site para visitante e o painel para quem
 * tem sessão), e o Pixel global mandava para a Meta cliques de telas internas
 * de clientes (ex.: SubscribedButtonClick "Apuração" no Ponto) — problema de
 * LGPD e de dataset. Agora:
 *  - só o site público chama `iniciarMetaPixel()` (Site.tsx e /lp), e só em
 *    host de produção (`HOSTS_PRODUCAO`);
 *  - `autoConfig` desligado: nada de clique/formulário automático, só os
 *    eventos explícitos (PageView, Lead, Contact);
 *  - `disablePushState`: a troca de rota do SPA não vira PageView;
 *  - ao sair do site público (desmontagem — ex.: login na mesma aba),
 *    `pausarMetaPixel()` revoga o consentimento no Pixel: a biblioteca fica
 *    carregada, mas não envia mais nada até o site público voltar a montar.
 *
 * A chamada ao servidor (CAPI) sai sempre que há conversão explícita — é a
 * função quem decide, pela origem, se aquele envio vale.
 *
 * Por que `text/plain` e sem cabeçalhos extras: assim a chamada é uma
 * "requisição simples" — o navegador não faz o preflight de CORS, e o
 * `keepalive` funciona mesmo se o visitante sair da página logo depois.
 * A função tem `verify_jwt = false` (é pública por natureza, como o Pixel).
 */

import { hostDeProducao, lerOrigemGuardada } from "@/lib/siteOrigem";

type Fbq = ((...args: unknown[]) => void) & {
  callMethod?: (...args: unknown[]) => void;
  queue?: unknown[];
  push?: unknown;
  loaded?: boolean;
  version?: string;
  disablePushState?: boolean;
  allowDuplicatePageViews?: boolean;
};

declare global {
  interface Window {
    fbq?: Fbq;
    _fbq?: Fbq;
  }
}

export const META_PIXEL_ID = "1366578955244006";
const FBEVENTS_URL = "https://connect.facebook.net/en_US/fbevents.js";

/** Pixel ligado agora (site público montado, em produção). */
let pixelAtivo = false;
let pixelIniciado = false;

/**
 * Liga o Pixel para o site público. Só em host de produção; fora dele não
 * carrega nada e devolve false. Idempotente: a biblioteca é carregada uma vez;
 * chamadas seguintes só reativam o envio e registram o PageView da tela.
 */
export function iniciarMetaPixel(hostname?: string): boolean {
  try {
    if (typeof window === "undefined") return false;
    if (!hostDeProducao(hostname ?? window.location.hostname)) return false;

    if (!pixelIniciado || !window.fbq) {
      if (!window.fbq) {
        // Base code oficial da Meta, sem a chamada automática de init/PageView.
        const n = function (...args: unknown[]) {
          if (n.callMethod) n.callMethod(...args);
          else n.queue!.push(args);
        } as Fbq;
        n.push = n;
        n.loaded = true;
        n.version = "2.0";
        n.queue = [];
        window.fbq = n;
        if (!window._fbq) window._fbq = n;
        // Sem PageView automático em troca de rota do SPA (history.pushState).
        n.disablePushState = true;
        n.allowDuplicatePageViews = false;
        const t = document.createElement("script");
        t.async = true;
        t.src = FBEVENTS_URL;
        const s = document.getElementsByTagName("script")[0];
        if (s?.parentNode) s.parentNode.insertBefore(t, s);
        else document.head.appendChild(t);
      }
      window.fbq.disablePushState = true;
      // Sem eventos automáticos (cliques em botão, dados de formulário).
      window.fbq("set", "autoConfig", false, META_PIXEL_ID);
      window.fbq("init", META_PIXEL_ID);
      pixelIniciado = true;
    } else {
      window.fbq("consent", "grant");
    }
    pixelAtivo = true;
    window.fbq("track", "PageView");
    return true;
  } catch (e) {
    console.warn("[meta] Pixel indisponível:", e);
    return false;
  }
}

/**
 * Chamado quando o site público sai de cena (desmontagem). A partir daqui o
 * Pixel não envia mais nada — nem evento explícito, nem automático.
 */
export function pausarMetaPixel(): void {
  if (!pixelAtivo) return;
  pixelAtivo = false;
  try {
    window.fbq?.("consent", "revoke");
  } catch {
    /* nada a fazer */
  }
}

/** Só para teste: volta o módulo ao estado inicial. */
export function __reiniciarPixelParaTeste(): void {
  pixelAtivo = false;
  pixelIniciado = false;
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
    // Só com o site público ativo: nunca do app logado.
    if (pixelAtivo) window.fbq?.("track", eventName, {}, { eventID: eventId });
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
