// Supabase Edge Function: meta-leads-webhook — STANDBY
// Recebe leads de formulários da Meta (Facebook/Instagram Lead Ads) via
// webhook "leadgen". Fica desligada até app_config ter as chaves:
//   meta_leads_ativo = 'true', meta_verify_token, meta_app_secret,
//   meta_page_access_token (para buscar os campos do lead na Graph API).
// GET  → verificação do webhook (hub.challenge)
// POST → valida X-Hub-Signature-256 e grava via public.leads_receber_meta
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.90.1";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

async function cfg(chave: string): Promise<string> {
  const { data } = await admin.from("app_config").select("valor").eq("chave", chave).maybeSingle();
  return (data?.valor ?? "").trim();
}
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } });

async function hmacHex(secret: string, body: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

serve(async (req) => {
  const ativo = (await cfg("meta_leads_ativo")) === "true";
  const verifyToken = await cfg("meta_verify_token");
  const appSecret = await cfg("meta_app_secret");
  const pageToken = await cfg("meta_page_access_token");

  if (req.method === "GET") {
    // Verificação do webhook na Meta: precisa do verify token mesmo em standby.
    const url = new URL(req.url);
    if (!verifyToken) return json({ error: "standby: meta_verify_token não configurado" }, 503);
    if (url.searchParams.get("hub.mode") === "subscribe" && url.searchParams.get("hub.verify_token") === verifyToken) {
      return new Response(url.searchParams.get("hub.challenge") ?? "", { status: 200 });
    }
    return json({ error: "verify token inválido" }, 403);
  }
  if (req.method !== "POST") return json({ error: "Método não permitido" }, 405);
  if (!ativo || !appSecret) return json({ error: "standby: integração Meta Ads desligada (meta_leads_ativo/meta_app_secret)" }, 503);

  const raw = await req.text();
  const assinatura = req.headers.get("x-hub-signature-256") ?? "";
  const esperado = "sha256=" + (await hmacHex(appSecret, raw));
  if (assinatura !== esperado) return json({ error: "assinatura inválida" }, 401);

  let body: { entry?: Array<{ changes?: Array<{ field?: string; value?: Record<string, unknown> }> }> };
  try { body = JSON.parse(raw); } catch { return json({ error: "JSON inválido" }, 400); }

  const resultados: unknown[] = [];
  for (const entry of body.entry ?? []) {
    for (const change of entry.changes ?? []) {
      if (change.field !== "leadgen") continue;
      const v = change.value ?? {};
      const leadgenId = String(v.leadgen_id ?? "");
      if (!leadgenId) continue;
      // Busca os campos do formulário na Graph API (quando há token de página)
      let campos: Record<string, string> = {};
      if (pageToken) {
        try {
          const r = await fetch(`https://graph.facebook.com/v20.0/${leadgenId}?access_token=${encodeURIComponent(pageToken)}`);
          const j = await r.json();
          for (const f of j.field_data ?? []) campos[String(f.name)] = Array.isArray(f.values) ? String(f.values[0] ?? "") : "";
          campos.ad_id = String(j.ad_id ?? v.ad_id ?? ""); campos.form_id = String(j.form_id ?? v.form_id ?? "");
        } catch (e) { campos = { erro_graph: (e as Error).message }; }
      }
      const { data, error } = await admin.rpc("leads_receber_meta", {
        _external_id: leadgenId, _form_id: String(v.form_id ?? campos.form_id ?? ""),
        _campanha: String(v.adgroup_id ?? v.ad_id ?? campos.ad_id ?? ""), _payload: { ...v, ...campos },
      });
      resultados.push(error ? { leadgenId, erro: error.message } : data);
    }
  }
  return json({ ok: true, processados: resultados });
});
