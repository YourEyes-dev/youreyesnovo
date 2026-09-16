import { createClient } from "https://esm.sh/@supabase/supabase-js@2.90.1";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SITE_URL = Deno.env.get("SITE_URL") || "https://youreyes.com.br";

type Payload = {
  email: string;
  nomeCompleto: string;
  role: "admin" | "manager" | "user";
  method: "invite" | "password";
  password?: string;
};

function buildInviteHtml(nomeCompleto: string, confirmationUrl: string, method: string) {
  return `
    <div style="font-family: 'Inter', Arial, sans-serif; max-width: 480px; margin: 0 auto; padding: 32px 28px; background: #ffffff;">
      <div style="text-align: center; margin-bottom: 8px;">
        <p style="font-size: 24px; font-weight: bold; color: hsl(262, 52%, 50%); margin: 0;">🛡️ YourEyes</p>
      </div>
      <hr style="border-color: #e8e5f0; margin: 16px 0;" />
      <h1 style="font-size: 22px; font-weight: bold; color: hsl(260, 20%, 16%); margin: 0 0 16px;">Olá, ${nomeCompleto}!</h1>
      <p style="font-size: 14px; color: hsl(260, 10%, 46%); line-height: 1.6; margin: 0 0 20px;">
        Você foi convidado(a) para acessar a plataforma <strong>YourEyes</strong>, a solução completa em Saúde e Segurança do Trabalho.
      </p>
      <p style="font-size: 14px; color: hsl(260, 10%, 46%); line-height: 1.6; margin: 0 0 20px;">
        ${method === "invite"
          ? "Clique no botão abaixo para aceitar o convite e configurar sua conta:"
          : "Suas credenciais foram criadas. Acesse a plataforma para começar:"}
      </p>
      <div style="text-align: center; margin: 24px 0;">
        <a href="${confirmationUrl}" style="background-color: hsl(262, 52%, 50%); color: #ffffff; font-size: 14px; font-weight: 600; border-radius: 10px; padding: 14px 28px; text-decoration: none; display: inline-block;">
          ${method === "invite" ? "Aceitar Convite" : "Acessar Plataforma"}
        </a>
      </div>
      <p style="font-size: 12px; color: #999999; margin: 24px 0 0;">
        Se você não esperava este convite, pode ignorar este e-mail com segurança.
      </p>
      <hr style="border-color: #e8e5f0; margin: 16px 0;" />
      <p style="font-size: 11px; color: #b3b3b3; text-align: center; margin: 8px 0 0;">YourEyes — Plataforma de SST</p>
    </div>
  `;
}

async function sendViaResend(email: string, subject: string, html: string): Promise<{ ok: boolean; error?: string }> {
  const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
  if (!RESEND_API_KEY) {
    console.error("RESEND_API_KEY not configured");
    return { ok: false, error: "RESEND_API_KEY not configured" };
  }
  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: "YourEyes <noreply@youreyes.com.br>",
        to: [email],
        subject,
        html,
      }),
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      console.error("Resend error:", err);
      return { ok: false, error: (err as any)?.message ?? `HTTP ${res.status}` };
    }
    console.log("Resend email sent to:", email);
    return { ok: true };
  } catch (e: any) {
    console.error("Email send error:", e?.message ?? e);
    return { ok: false, error: e?.message ?? "Email send error" };
  }
}

serve(async (req) => {
  const corsHeaders: Record<string, string> = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };

  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  if (req.method !== "POST") return json({ error: "Method Not Allowed" }, 405);

  const authHeader = req.headers.get("authorization") ?? "";
  const jwt = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : null;
  if (!jwt) return json({ error: "Missing Authorization" }, 401);

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Validate caller
  let callerId: string;
  try {
    const sub = JSON.parse(atob(jwt.split('.')[1])).sub;
    const { data: callerUser, error: callerError } = await admin.auth.admin.getUserById(sub);
    if (callerError || !callerUser?.user) return json({ error: "Invalid token" }, 401);
    callerId = callerUser.user.id;
  } catch {
    return json({ error: "Invalid token" }, 401);
  }

  const { data: userData } = await admin.auth.admin.getUserById(callerId);

  // Get caller's tenant
  const { data: callerProfile } = await admin
    .from("profiles")
    .select("tenant_id")
    .eq("user_id", callerId)
    .single();

  if (!callerProfile?.tenant_id) return json({ error: "Caller has no tenant" }, 403);

  // Check permissions
  const { data: callerRoles } = await admin
    .from("user_roles")
    .select("role")
    .eq("user_id", callerId);

  const roles = callerRoles?.map((r) => r.role) || [];
  const isOwnerOrAdmin = roles.includes("owner") || roles.includes("admin");

  const { data: superCheck } = await admin
    .from("superadmins")
    .select("id")
    .eq("user_id", callerId)
    .eq("ativo", true)
    .maybeSingle();

  if (!isOwnerOrAdmin && !superCheck) {
    return json({ error: "Sem permissão para convidar usuários" }, 403);
  }

  let payload: Payload;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const { email, nomeCompleto, role, method, password } = payload;

  if (!email || !nomeCompleto || !role) {
    return json({ error: "Campos obrigatórios: email, nomeCompleto, role" }, 400);
  }

  if ((role as string) === "owner") {
    return json({ error: "Não é possível criar owners por esta função" }, 400);
  }

  const tenantId = callerProfile.tenant_id;

  // Check if email already exists
  let existingUser: any = null;
  try {
    const { data: allUsers } = await admin.auth.admin.listUsers({ perPage: 1000 });
    existingUser = allUsers?.users?.find(
      (u) => u.email?.toLowerCase() === email.toLowerCase()
    );
  } catch (e) {
    console.error("Error checking existing users:", e);
  }

  if (existingUser) {
    const { data: existingProfile } = await admin
      .from("profiles")
      .select("id, tenant_id")
      .eq("user_id", existingUser.id)
      .maybeSingle();

    if (existingProfile && existingProfile.tenant_id === tenantId) {
      return json({
        ok: true,
        userId: existingUser.id,
        inviteSent: false,
        alreadyExists: true,
      });
    }

    // Conta já existe e pertence a OUTRA organização. Reaproveitar esse
    // auth user vincularia o cadastro a um login de outro tenant — o perfil
    // continuaria no tenant antigo e qualquer operação (definir senha,
    // reenviar convite) falharia com 403. Bloqueia com mensagem clara.
    if (existingProfile && existingProfile.tenant_id !== tenantId) {
      return json(
        {
          error:
            `O e-mail ${email} já possui uma conta vinculada a outra organização no sistema. ` +
            `Utilize um e-mail diferente para este cadastro.`,
        },
        409
      );
    }
  }


  let newUserId: string;

  let emailSent = false;
  let emailError: string | null = null;

  try {
    if (method === "invite") {
      let confirmationUrl: string | null = null;

      if (existingUser) {
        // User already exists in auth — use magiclink/recovery to send a usable link
        newUserId = existingUser.id;
        const { data: linkData, error: linkError } = await admin.auth.admin.generateLink({
          type: existingUser.email_confirmed_at ? "magiclink" : "invite",
          email,
          options: {
            redirectTo: `${SITE_URL}/login`,
          },
        });
        if (linkError) {
          console.error("generateLink (existing) error:", linkError.message);
          // Fallback: recovery link
          const { data: recData, error: recError } = await admin.auth.admin.generateLink({
            type: "recovery",
            email,
            options: { redirectTo: `${SITE_URL}/reset-password` },
          });
          if (recError) {
            console.error("recovery fallback error:", recError.message);
            emailError = recError.message;
          } else {
            confirmationUrl = recData?.properties?.action_link ?? null;
          }
        } else {
          confirmationUrl = linkData?.properties?.action_link ?? null;
        }
      } else {
        // New user — invite link
        const { data: linkData, error: linkError } = await admin.auth.admin.generateLink({
          type: "invite",
          email,
          options: {
            data: { tenant_id: tenantId, nome_completo: nomeCompleto },
            redirectTo: `${SITE_URL}/login`,
          },
        });

        if (linkError || !linkData?.user) {
          console.error("generateLink error:", linkError?.message);
          return json({ error: linkError?.message ?? "Falha ao gerar convite" }, 500);
        }
        newUserId = linkData.user.id;
        confirmationUrl = linkData.properties?.action_link ?? null;
      }

      if (confirmationUrl) {
        const sendResult = await sendViaResend(
          email,
          "Você foi convidado para o YourEyes",
          buildInviteHtml(nomeCompleto, confirmationUrl, "invite")
        );
        if (sendResult?.ok) {
          emailSent = true;
        } else {
          emailError = sendResult?.error ?? "Falha ao enviar email";
        }
      } else if (!emailError) {
        emailError = "Não foi possível gerar o link de convite";
      }
    } else {
      if (!password || password.length < 6) {
        return json({ error: "Senha deve ter no mínimo 6 caracteres" }, 400);
      }
      const { data: newUser, error: createError } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
      });
      if (createError || !newUser?.user) {
        console.error("Create error:", createError?.message);
        if (createError?.message?.includes("already been registered") && existingUser) {
          newUserId = existingUser.id;
        } else {
          return json({ error: createError?.message ?? "Falha ao criar usuário" }, 500);
        }
      } else {
        newUserId = newUser.user.id;
        const sendResult = await sendViaResend(
          email,
          "Bem-vindo ao YourEyes",
          buildInviteHtml(nomeCompleto, `${SITE_URL}/login`, "password")
        );
        if (sendResult?.ok) {
          emailSent = true;
        } else {
          emailError = sendResult?.error ?? "Falha ao enviar email";
        }
      }
    }
  } catch (e: any) {
    console.error("Auth operation error:", e?.message);
    return json({ error: e?.message || "Erro ao criar usuário" }, 500);
  }

  // Check if tenant already has empresa_cadastro — if so, mark onboarding as concluded
  // (new users joining configured tenants should not see the onboarding flow)
  const { count: empresaCount } = await admin
    .from("empresa_cadastro")
    .select("id", { count: "exact", head: true })
    .eq("tenant_id", tenantId);
  const tenantAlreadyConfigured = (empresaCount ?? 0) > 0;

  // Create profile
  const { error: profileError } = await admin.from("profiles").insert({
    user_id: newUserId!,
    tenant_id: tenantId,
    nome_completo: nomeCompleto,
    onboarding_concluido: tenantAlreadyConfigured,
  });

  if (profileError) {
    console.error("Profile error:", profileError.message);
    if (!profileError.message.includes("duplicate")) {
      await admin.auth.admin.deleteUser(newUserId!);
      return json({ error: profileError.message }, 500);
    }
  }

  // Assign role
  const { error: roleError } = await admin.from("user_roles").insert({
    user_id: newUserId!,
    role,
  });

  if (roleError) {
    console.error("Role error:", roleError.message);
    if (!roleError.message.includes("duplicate")) {
      return json({ error: roleError.message }, 500);
    }
  }

  // Audit log
  await admin.from("audit_logs").insert({
    tenant_id: tenantId,
    user_id: callerId,
    user_name: userData?.user?.user_metadata?.nome_completo || userData?.user?.email,
    user_email: userData?.user?.email,
    action: method === "invite" ? "user.invited" : "user.created",
    module: "equipe",
    description: method === "invite"
      ? `Convidou "${nomeCompleto}" (${email}) com perfil "${role}"`
      : `Criou usuário "${nomeCompleto}" (${email}) com perfil "${role}"`,
    target_type: "user",
    target_id: newUserId!,
    target_name: nomeCompleto,
    metadata: { email, role, method },
  });

  return json({
    ok: true,
    userId: newUserId!,
    inviteSent: emailSent,
    emailError,
  });
});
