// Webhook do Mercado Pago — recebe notificações de pagamento, atualiza assinaturas
// e, quando aprovado, provisiona tenant + cliente e envia e-mail de ativação.
// Público (verify_jwt=false). MP não envia JWT; validação por consulta autenticada à API do MP.
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-runtime, x-supabase-client-runtime-version",
};
import { createClient } from "npm:@supabase/supabase-js@2";

const STATUS_MAP: Record<string, string> = {
  approved: "approved",
  authorized: "approved",
  pending: "pending",
  in_process: "pending",
  in_mediation: "pending",
  rejected: "rejected",
  cancelled: "cancelled",
  refunded: "refunded",
  charged_back: "charged_back",
};

const APP_URL = Deno.env.get("APP_URL") || "https://youreyes.com.br";
const FROM_EMAIL = Deno.env.get("EMAIL_FROM") || "YourEyes <no-reply@youreyes.com.br>";

function slugify(input: string) {
  return (input || "cliente")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "")
    .slice(0, 40) || "cliente";
}

async function sendActivationEmail(opts: {
  to: string;
  nomeEmpresa: string;
  planoNome: string;
  ciclo: string;
  activationUrl: string;
}) {
  const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
  if (!RESEND_API_KEY) {
    console.warn("[mp-webhook] RESEND_API_KEY não configurada — pulando envio de e-mail");
    return { skipped: true };
  }
  const html = `
<!doctype html>
<html><body style="font-family:Arial,Helvetica,sans-serif;background:#f5f6f8;padding:32px;color:#0B1D34;">
  <div style="max-width:560px;margin:auto;background:#fff;border-radius:12px;padding:32px;box-shadow:0 6px 24px rgba(0,0,0,0.06);">
    <h1 style="margin:0 0 8px;color:#0B1D34;font-size:22px;">Pagamento aprovado 🎉</h1>
    <p style="margin:0 0 16px;font-size:15px;line-height:1.55;">
      Olá! Recebemos a confirmação do seu pagamento do plano
      <strong>${opts.planoNome}</strong> (${opts.ciclo}). Falta apenas um passo para ativar o seu acesso ao <strong>YourEyes</strong>.
    </p>
    <p style="margin:0 0 24px;font-size:15px;line-height:1.55;">
      Clique no botão abaixo para <strong>criar sua senha</strong> e concluir a ativação da conta da sua empresa.
    </p>
    <p style="text-align:center;margin:28px 0;">
      <a href="${opts.activationUrl}"
         style="background:#0B1D34;color:#fff;text-decoration:none;padding:14px 28px;border-radius:8px;font-weight:bold;display:inline-block;">
        Ativar minha conta
      </a>
    </p>
    <p style="margin:0 0 8px;font-size:13px;color:#5a6474;">
      Se o botão não funcionar, copie e cole este link no navegador:
    </p>
    <p style="word-break:break-all;font-size:12px;color:#0B1D34;">${opts.activationUrl}</p>
    <hr style="border:none;border-top:1px solid #e5e7eb;margin:24px 0;">
    <p style="font-size:12px;color:#8a94a6;margin:0;">
      Este link é válido por 30 dias. Se você não reconhece esta compra, ignore este e-mail.
    </p>
  </div>
</body></html>`;

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: FROM_EMAIL,
      to: [opts.to],
      subject: `Ative sua conta YourEyes — ${opts.planoNome}`,
      html,
    }),
  });
  const body = await res.text();
  if (!res.ok) {
    console.error("[mp-webhook] resend erro:", res.status, body);
    return { ok: false, status: res.status, body };
  }
  return { ok: true };
}

async function provisionAccount(supabase: any, params: {
  assinaturaId: string;
  payerEmail: string;
  planoId: string;
  planoNome: string;
  ciclo: string;
}) {
  const { assinaturaId, payerEmail, planoId, planoNome, ciclo } = params;

  // Verifica se já foi provisionado
  const { data: assinatura } = await supabase
    .from("assinaturas")
    .select("cliente_id, tenant_id, activation_email_sent_at")
    .eq("id", assinaturaId)
    .maybeSingle();

  if (assinatura?.cliente_id && assinatura?.activation_email_sent_at) {
    console.log("[mp-webhook] já provisionado — ignorando");
    return { ok: true, alreadyProvisioned: true };
  }

  let clienteId = assinatura?.cliente_id as string | null;
  let tenantId = assinatura?.tenant_id as string | null;
  let activationToken: string | null = null;

  // Reuso ou criação de cliente/tenant
  if (!clienteId) {
    // 1. cria tenant
    const baseSlug = slugify(payerEmail.split("@")[0] || "cliente");
    const slug = `${baseSlug}-${Math.random().toString(36).slice(2, 6)}`;
    const nomeEmpresa = `Empresa ${payerEmail.split("@")[0]}`;

    const { data: tenant, error: tenantErr } = await supabase
      .from("tenants")
      .insert({
        nome: nomeEmpresa,
        slug,
        plano: (planoId || "starter") as any,
        ativo: true,
      })
      .select("id")
      .single();

    if (tenantErr) {
      console.error("[mp-webhook] erro criar tenant:", tenantErr);
      return { ok: false, error: tenantErr.message }

    // Programa de Parceiros: o ?ref= que veio da landing/checkout grava a origem no tenant
    try {
      const { data: assRef } = await supabase.from("assinaturas").select("ref_codigo, raw_payload").eq("id", assinaturaId).maybeSingle();
      const refCodigo = (assRef?.ref_codigo as string | null) || ((assRef?.raw_payload as { metadata?: { ref_codigo?: string } } | null)?.metadata?.ref_codigo ?? null);
      if (refCodigo) await supabase.rpc("parceiro_atribuir_tenant_por_ref", { p_tenant_id: tenant.id, p_codigo: refCodigo });
    } catch (e) { console.error("[mp-webhook] origem do parceiro (nao-fatal):", (e as Error).message); }
;
    }
    tenantId = tenant.id;

    // 2. cria cliente com activation_token
    activationToken = crypto.randomUUID();
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();

    const { data: cliente, error: clienteErr } = await supabase
      .from("programa_validador_clientes")
      .insert({
        nome_empresa: nomeEmpresa,
        poc_email: payerEmail,
        poc_nome: payerEmail.split("@")[0],
        tenant_id: tenantId,
        fase: "ativo",
        tipo_cliente: "pago",
        plano: planoId,
        activation_token: activationToken,
        activation_token_expires_at: expiresAt,
        conta_ativada: false,
      } as any)
      .select("id")
      .single();

    if (clienteErr) {
      console.error("[mp-webhook] erro criar cliente:", clienteErr);
      return { ok: false, error: clienteErr.message };
    }
    clienteId = cliente.id;
  } else {
    // Recupera token existente
    const { data: cli } = await supabase
      .from("programa_validador_clientes")
      .select("activation_token, activation_token_expires_at, conta_ativada")
      .eq("id", clienteId)
      .maybeSingle();
    if (cli?.conta_ativada) {
      console.log("[mp-webhook] conta já ativada");
      await supabase
        .from("assinaturas")
        .update({ activation_email_sent_at: new Date().toISOString() })
        .eq("id", assinaturaId);
      return { ok: true, alreadyActivated: true };
    }
    activationToken = cli?.activation_token || null;
    // Se não tem token válido, gera novo
    if (!activationToken || (cli?.activation_token_expires_at && new Date(cli.activation_token_expires_at) < new Date())) {
      activationToken = crypto.randomUUID();
      await supabase
        .from("programa_validador_clientes")
        .update({
          activation_token: activationToken,
          activation_token_expires_at: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
        } as any)
        .eq("id", clienteId);
    }
  }

  // 3. atualiza assinatura com vínculos
  await supabase
    .from("assinaturas")
    .update({ cliente_id: clienteId, tenant_id: tenantId })
    .eq("id", assinaturaId);

  // 4. envia e-mail
  const activationUrl = `${APP_URL}/ativar-conta?token=${activationToken}`;
  const emailRes = await sendActivationEmail({
    to: payerEmail,
    nomeEmpresa: `Empresa ${payerEmail.split("@")[0]}`,
    planoNome,
    ciclo,
    activationUrl,
  });

  if ((emailRes as any).ok || (emailRes as any).skipped) {
    await supabase
      .from("assinaturas")
      .update({ activation_email_sent_at: new Date().toISOString() })
      .eq("id", assinaturaId);
  }

  return { ok: true, clienteId, tenantId, activationUrl, emailRes };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const accessToken = Deno.env.get("MERCADOPAGO_ACCESS_TOKEN");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!accessToken || !supabaseUrl || !serviceRole) {
      return new Response(JSON.stringify({ error: "missing_env" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const url = new URL(req.url);
    const qType = url.searchParams.get("type") || url.searchParams.get("topic");
    const qId = url.searchParams.get("data.id") || url.searchParams.get("id");

    let body: any = {};
    try {
      body = await req.json();
    } catch (_) {}

    const type = body?.type || body?.topic || qType;
    const paymentId =
      body?.data?.id ||
      body?.resource?.toString().split("/").pop() ||
      qId;

    console.log("[mp-webhook] evento:", { type, paymentId });

    if (!paymentId || (type && type !== "payment" && type !== "payment.updated")) {
      return new Response(JSON.stringify({ ok: true, ignored: true }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const mpRes = await fetch(`https://api.mercadopago.com/v1/payments/${paymentId}`, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    const payment = await mpRes.json();
    if (!mpRes.ok) {
      console.error("[mp-webhook] erro buscar pagamento:", payment);
      return new Response(JSON.stringify({ ok: true, error: "fetch_failed" }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(supabaseUrl, serviceRole, {
      auth: { persistSession: false },
    });

    const status = STATUS_MAP[payment.status] || payment.status || "pending";
    const externalReference = payment.external_reference as string | null;
    const preferenceId = (payment.additional_info?.preference_id ||
      payment.order?.id ||
      null) as string | null;
    const meta = payment.metadata || {};

    const patch: Record<string, unknown> = {
      status,
      payment_id: String(payment.id),
      payer_email: payment.payer?.email ?? null,
      payment_method: payment.payment_method_id ?? payment.payment_type_id ?? null,
      raw_payload: payment,
      approved_at: status === "approved" ? new Date().toISOString() : null,
      external_reference: externalReference,
    };

    // Localiza assinatura existente
    let existingId: string | null = null;
    if (externalReference) {
      const { data } = await supabase
        .from("assinaturas")
        .select("id")
        .eq("external_reference", externalReference)
        .maybeSingle();
      existingId = data?.id ?? null;
    }
    if (!existingId && preferenceId) {
      const { data } = await supabase
        .from("assinaturas")
        .select("id")
        .eq("preference_id", preferenceId)
        .maybeSingle();
      existingId = data?.id ?? null;
    }

    let assinaturaId: string | null = existingId;
    let planoId = meta.plano_id ?? "desconhecido";
    let planoNome = meta.plano_nome ?? payment.description ?? "Assinatura";
    let ciclo = meta.ciclo ?? "mensal";

    if (existingId) {
      await supabase.from("assinaturas").update(patch).eq("id", existingId);
      // Recupera plano_nome/ciclo caso metadata esteja vazia
      const { data: a } = await supabase
        .from("assinaturas")
        .select("plano_id, plano_nome, ciclo")
        .eq("id", existingId)
        .maybeSingle();
      if (a) {
        planoId = a.plano_id;
        planoNome = a.plano_nome;
        ciclo = a.ciclo;
      }
    } else {
      const preco_mensal = Number(meta.preco_mensal ?? payment.transaction_amount ?? 0);
      const meses = Number(meta.meses ?? 1);
      const { data: inserted, error } = await supabase
        .from("assinaturas")
        .insert({
          plano_id: planoId,
          plano_nome: planoNome,
          ciclo,
          preco_mensal,
          valor_total: Number(payment.transaction_amount ?? preco_mensal * meses),
          meses,
          preference_id: preferenceId,
          ...patch,
        })
        .select("id")
        .single();
      if (error) console.error("[mp-webhook] insert erro:", error);
      assinaturaId = inserted?.id ?? null;
    }

    // Provisiona conta quando pagamento aprovado
    let provision: any = null;
    const payerEmail = payment.payer?.email ?? null;
    if (status === "approved" && assinaturaId && payerEmail) {
      provision = await provisionAccount(supabase, {
        assinaturaId,
        payerEmail,
        planoId,
        planoNome,
        ciclo,
      });
      console.log("[mp-webhook] provision:", provision);
    }

    return new Response(JSON.stringify({ ok: true, status, provision }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("[mp-webhook] erro:", err);
    return new Response(JSON.stringify({ ok: false, error: String(err) }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
