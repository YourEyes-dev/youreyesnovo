/**
 * Origem da visita no site (tráfego pago) — UTMs da primeira visita, hosts
 * de produção e o "ângulo de dor" que a campanha testou.
 *
 * Por que guardar as UTMs: o anúncio chega em
 * `https://www.youreyes.com.br/?utm_source=...&utm_campaign=...#diagnostico`.
 * A query só existe na primeira tela; qualquer navegação (âncora, login,
 * voltar) pode perdê-la, e o lead é gravado minutos depois. Por isso a
 * PRIMEIRA visita com UTM da sessão fica no sessionStorage e é ela que
 * acompanha o lead.
 *
 * Nada aqui é dado pessoal: só parâmetros de campanha e o endereço de chegada.
 */

/**
 * Hosts de PRODUÇÃO — os únicos onde o Pixel da Meta pode rodar.
 * O mesmo par de hosts está escrito no `index.html` (o Pixel inicializa lá,
 * antes do React). Mudou aqui, mude lá também.
 */
export const HOSTS_PRODUCAO = ["youreyes.com.br", "www.youreyes.com.br"] as const;

export function hostDeProducao(hostname: string | null | undefined): boolean {
  return (HOSTS_PRODUCAO as readonly string[]).includes(String(hostname ?? "").toLowerCase());
}

export interface OrigemVisita {
  utm_source?: string;
  utm_medium?: string;
  utm_campaign?: string;
  utm_content?: string;
  utm_term?: string;
  /** Clique do anúncio da Meta — vira o `fbc` quando o cookie ainda não existe. */
  fbclid?: string;
  /** Momento em que o fbclid foi visto (ms) — compõe o `fbc`. */
  fbclid_em?: number;
  /** Endereço de chegada, sem o hash. */
  landing_url?: string;
  referrer?: string;
  capturado_em?: string;
}

const CHAVE = "ye_origem_primeira_visita";
const PARAMS = ["utm_source", "utm_medium", "utm_campaign", "utm_content", "utm_term", "fbclid"] as const;
const LIMITE = 300;

/**
 * Lê os parâmetros de campanha de uma URL. Aceita também o formato errado
 * `#diagnostico?utm_...` (query depois do hash), que já apareceu em anúncio:
 * a query do hash só é usada se a query normal não trouxer nada.
 */
export function extrairOrigemDaUrl(href: string): OrigemVisita {
  let url: URL;
  try {
    url = new URL(href);
  } catch {
    return {};
  }
  const buscar = (params: URLSearchParams) => {
    const o: OrigemVisita = {};
    for (const p of PARAMS) {
      const v = (params.get(p) ?? "").trim().slice(0, LIMITE);
      if (v) o[p] = v;
    }
    return o;
  };
  let origem = buscar(url.searchParams);
  if (Object.keys(origem).length === 0) {
    const i = url.hash.indexOf("?");
    if (i >= 0) origem = buscar(new URLSearchParams(url.hash.slice(i + 1)));
  }
  return origem;
}

function temCampanha(o: OrigemVisita): boolean {
  return PARAMS.some((p) => Boolean(o[p]));
}

function armazenamento(): Storage | null {
  try {
    return typeof window !== "undefined" ? window.sessionStorage : null;
  } catch {
    return null;
  }
}

/** Origem guardada nesta sessão (ou null). Nunca lança. */
export function lerOrigemGuardada(): OrigemVisita | null {
  try {
    const raw = armazenamento()?.getItem(CHAVE);
    if (!raw) return null;
    const o = JSON.parse(raw) as OrigemVisita;
    return o && typeof o === "object" ? o : null;
  } catch {
    return null;
  }
}

/**
 * Guarda a origem da PRIMEIRA visita com campanha desta sessão. Visitas
 * seguintes não sobrescrevem (first-touch). Devolve a origem vigente.
 * Nunca lança: sem sessionStorage (aba anônima restrita), devolve a da URL.
 */
export function capturarOrigemDaVisita(href?: string): OrigemVisita {
  const atual = typeof window !== "undefined" ? window.location.href : "";
  const endereco = href ?? atual;
  const guardada = lerOrigemGuardada();
  if (guardada && temCampanha(guardada)) return guardada;

  const daUrl = extrairOrigemDaUrl(endereco);
  if (!temCampanha(daUrl)) return guardada ?? {};

  let landing = endereco;
  try {
    const u = new URL(endereco);
    u.hash = "";
    landing = u.toString();
  } catch {
    /* mantém como veio */
  }
  const origem: OrigemVisita = {
    ...daUrl,
    ...(daUrl.fbclid ? { fbclid_em: Date.now() } : {}),
    landing_url: landing.slice(0, 1000),
    referrer: (typeof document !== "undefined" ? document.referrer : "").slice(0, 1000) || undefined,
    capturado_em: new Date().toISOString(),
  };
  try {
    armazenamento()?.setItem(CHAVE, JSON.stringify(origem));
  } catch {
    /* sem armazenamento: segue só com a origem da URL */
  }
  return origem;
}

/** Ângulos de dor aceitos pela propriedade `ye_angulo_dor` do HubSpot. */
export type AnguloDor = "sst" | "jornada" | "documentos" | "pessoas" | "dho" | "estrategia";

/**
 * Deriva o ângulo de dor a partir do nome da campanha. A ordem importa:
 * o primeiro que casar vence (ex.: "nr1_jornada" → sst, porque NR-1 é o
 * tema de SST). Sem correspondência → null (não inventa ângulo).
 */
export function anguloDaCampanha(utmCampaign: string | null | undefined): AnguloDor | null {
  const c = String(utmCampaign ?? "").toLowerCase();
  if (!c) return null;
  const regras: [AnguloDor, RegExp][] = [
    ["sst", /sst|nr-?1|epi/],
    ["jornada", /jornada|ponto/],
    ["documentos", /doc/],
    ["pessoas", /pessoa|cultura/],
    ["dho", /dho/],
    ["estrategia", /estrateg/],
  ];
  for (const [angulo, re] of regras) if (re.test(c)) return angulo;
  return null;
}

/** `utm_source / utm_campaign / utm_content` — texto do `ye_fonte_origem`. */
export function fonteOrigemTexto(o: OrigemVisita | null | undefined): string {
  if (!o) return "";
  const partes = [o.utm_source, o.utm_campaign, o.utm_content].map((p) => (p ?? "").trim());
  if (!partes.some(Boolean)) return "";
  return partes.map((p) => p || "-").join(" / ");
}
