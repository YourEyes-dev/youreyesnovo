import { supabase } from "@/integrations/supabase/client";

// Captura do link de indicação (?ref=CODIGO): guarda por 90 dias (janela de
// atribuição do programa) e registra o clique sem dado de pessoa.
const CHAVE = "ye_parceiro_ref";
const DIAS = 90;

export function capturarRefDaUrl(): string | null {
  try {
    const url = new URL(window.location.href);
    const ref = (url.searchParams.get("ref") || "").replace(/[^A-Za-z0-9-]/g, "").toUpperCase();
    if (!ref) return lerRef();
    const atual = lerRef();
    localStorage.setItem(CHAVE, JSON.stringify({ ref, expira: Date.now() + DIAS * 86400000 }));
    if (atual !== ref) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      void (supabase as any).rpc("parceiro_registrar_clique", { p_codigo: ref, p_ua_hash: hashCurto(navigator.userAgent) });
    }
    return ref;
  } catch { return null; }
}

export function lerRef(): string | null {
  try {
    const raw = localStorage.getItem(CHAVE);
    if (!raw) return null;
    const { ref, expira } = JSON.parse(raw) as { ref: string; expira: number };
    if (!ref || Date.now() > expira) { localStorage.removeItem(CHAVE); return null; }
    return ref;
  } catch { return null; }
}

function hashCurto(s: string): string {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
  return Math.abs(h).toString(36);
}
