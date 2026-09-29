// Supabase Edge Function: meta-capi — Conversions API da Meta (servidor).
//
// Recebe do navegador o MESMO evento que o Pixel acabou de disparar (mesmo
// event_id) e o repassa à Meta pelo servidor. A Meta deduplica pelo par
// event_name + event_id e conta uma conversão só.
//
// Chamada pública (verify_jwt = false em supabase/config.toml): o front manda
// em text/plain, sem cabeçalho de autenticação, para não haver preflight de
// CORS e o keepalive funcionar. A proteção é a origem (ver _shared/site-lead).
//
// Secrets (Project Settings → Edge Functions → Secrets):
//   META_CAPI_ACCESS_TOKEN  obrigatório — token da Conversions API do pixel
//                           (Events Manager → conjunto de dados → Configurações
//                           → "Gerar token de acesso").
//   META_PIXEL_ID           obrigatório — id do conjunto de dados/pixel.
//   META_TEST_EVENT_CODE    opcional — código TEST... do Events Manager →
//                           Eventos de teste. Com ele, os eventos só aparecem
//                           na aba de teste. Apague depois de validar.
//   SITE_HOSTS_PERMITIDOS   opcional — hosts aceitos (padrão: youreyes.com.br
//                           e www.youreyes.com.br).
//
// Sem token ou sem pixel: não envia nada, registra no log e responde 200
// ({ enviado: false }). Falha aqui nunca chega à tela do visitante.
import {
  corsHeaders, dominioEmail, EMAIL_RE, hostDaChamada, hostPermitido, json,
  lerCorpo, sha256Hex, telefoneE164, texto,
} from "../_shared/site-lead.ts";

const EVENTOS_ACEITOS = new Set(["Lead", "Contact"]);
const GRAPH_VERSAO = (Deno.env.get("META_GRAPH_VERSION") ?? "").trim() || "v21.0";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(req) });
  if (req.method !== "POST") return json(req, { error: "Método não permitido" }, 405);

  const host = hostDaChamada(req);
  if (!hostPermitido(host)) {
    console.log(`[meta-capi] ignorado: host não permitido (${host || "sem origem"})`);
    return json(req, { enviado: false, motivo: "host_nao_permitido" });
  }

  const token = (Deno.env.get("META_CAPI_ACCESS_TOKEN") ?? "").trim();
  const pixelId = (Deno.env.get("META_PIXEL_ID") ?? "").trim();
  if (!token || !pixelId) {
    console.warn(
      "[meta-capi] NÃO ENVIADO: falta secret " +
        [!token && "META_CAPI_ACCESS_TOKEN", !pixelId && "META_PIXEL_ID"].filter(Boolean).join(" e ") +
        " neste projeto (Project Settings → Edge Functions → Secrets).",
    );
    return json(req, { enviado: false, motivo: "sem_configuracao" });
  }

  const corpo = await lerCorpo(req);
  if (!corpo) return json(req, { enviado: false, motivo: "corpo_invalido" }, 400);

  const eventName = texto(corpo.event_name, 40);
  const eventId = texto(corpo.event_id, 100);
  if (!EVENTOS_ACEITOS.has(eventName) || !eventId) {
    return json(req, { enviado: false, motivo: "evento_invalido" }, 400);
  }

  const email = texto(corpo.email, 320).toLowerCase();
  const telefone = telefoneE164(corpo.phone);
  const fbp = texto(corpo.fbp, 500);
  const fbc = texto(corpo.fbc, 500);
  const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim();
  const userAgent = texto(req.headers.get("user-agent"), 1000);

  // Dados de correspondência: e-mail e telefone só vão com hash SHA-256
  // (normalizados antes, como a Meta exige). Nunca em texto aberto.
  const userData: Record<string, unknown> = {};
  if (email && EMAIL_RE.test(email)) userData.em = [await sha256Hex(email)];
  if (telefone) userData.ph = [await sha256Hex(telefone)];
  if (fbp) userData.fbp = fbp;
  if (fbc) userData.fbc = fbc;
  if (userAgent) userData.client_user_agent = userAgent;
  if (ip) userData.client_ip_address = ip;

  let eventSourceUrl = texto(corpo.event_source_url, 2000);
  try {
    if (eventSourceUrl) new URL(eventSourceUrl);
  } catch {
    eventSourceUrl = "";
  }

  const payload: Record<string, unknown> = {
    data: [{
      event_name: eventName,
      event_time: Math.floor(Date.now() / 1000),
      event_id: eventId,
      action_source: "website",
      ...(eventSourceUrl ? { event_source_url: eventSourceUrl } : {}),
      user_data: userData,
    }],
    access_token: token,
  };
  const testCode = (Deno.env.get("META_TEST_EVENT_CODE") ?? "").trim();
  if (testCode) payload.test_event_code = testCode;

  try {
    const r = await fetch(`https://graph.facebook.com/${GRAPH_VERSAO}/${encodeURIComponent(pixelId)}/events`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(8000),
    });
    const resp = await r.json().catch(() => ({}));
    if (!r.ok) {
      console.error(`[meta-capi] Meta recusou ${eventName} (${r.status}):`, JSON.stringify(resp?.error ?? resp).slice(0, 500));
      return json(req, { enviado: false, motivo: "meta_recusou", status: r.status });
    }
    console.log(
      `[meta-capi] ${eventName} enviado event_id=${eventId} recebidos=${resp?.events_received ?? "?"} ` +
        `fbtrace=${resp?.fbtrace_id ?? "-"} teste=${testCode ? "sim" : "nao"} ` +
        `em=${userData.em ? dominioEmail(email) : "-"} ph=${userData.ph ? "sim" : "nao"} fbp=${fbp ? "sim" : "nao"} fbc=${fbc ? "sim" : "nao"}`,
    );
    return json(req, { enviado: true, events_received: resp?.events_received ?? null });
  } catch (e) {
    console.error(`[meta-capi] falha de rede ao enviar ${eventName}:`, (e as Error).message);
    return json(req, { enviado: false, motivo: "falha_rede" });
  }
});
