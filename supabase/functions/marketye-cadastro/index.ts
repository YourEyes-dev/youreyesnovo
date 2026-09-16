// Supabase Edge Function: marketye-cadastro
// Autocadastro de especialista no MarketYE para quem AINDA NÃO tem conta.
// Cria o usuário (e-mail confirmado) e chama a função SQL do sistema
// marketye_cadastrar_especialista_para (service_role), que valida CPF/CNPJ,
// unicidade, registra o consentimento por versão e deixa o cadastro PENDENTE
// para a verificação humana. Quem já tem conta usa marketye_cadastrar_especialista
// (autenticado). Nenhuma regra de negócio decidida aqui: tudo no banco (RN-021).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.90.1";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

type Payload = {
  nome_completo?: string; email?: string; senha?: string; tipo_pessoa?: string; cpf_cnpj?: string; telefone?: string; cidade?: string; estado?: string;
  latitude?: number | null; longitude?: number | null; conselho?: string | null; registro_profissional?: string | null; uf_registro?: string | null; bio?: string | null;
  modalidades?: string[]; especialidades?: string[]; aceite_termos?: boolean; user_agent?: string; origem?: string;
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Método não permitido" }, 405);

  let p: Payload;
  try { p = await req.json(); } catch { return json({ error: "JSON inválido" }, 400); }

  const nome = (p.nome_completo ?? "").trim();
  const email = (p.email ?? "").trim().toLowerCase();
  const senha = p.senha ?? "";
  const documento = (p.cpf_cnpj ?? "").replace(/\D/g, "");
  if (nome.length < 3) return json({ error: "Informe o nome (mínimo 3 letras)" }, 400);
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: "E-mail inválido" }, 400);
  if (senha.length < 6) return json({ error: "A senha precisa ter ao menos 6 caracteres" }, 400);
  if (documento.length !== 11 && documento.length !== 14) return json({ error: "Informe um CPF (11 dígitos) ou CNPJ (14 dígitos)" }, 400);
  if (p.aceite_termos !== true) return json({ error: "É preciso aceitar os Termos do Especialista e a Política de Privacidade" }, 400);

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });

  // Conta já existe? Não criamos nem alteramos senha de ninguém.
  const { data: lista, error: lErr } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
  if (lErr) return json({ error: "Falha ao consultar contas: " + lErr.message }, 500);
  const existente = lista?.users?.find((u) => (u.email ?? "").toLowerCase() === email);
  if (existente) {
    return json({ error: "Já existe uma conta com esse e-mail. Entre com ela em /marketye/entrar e conclua o cadastro de especialista.", ja_existe: true }, 409);
  }

  const { data: novo, error: cErr } = await admin.auth.admin.createUser({
    email, password: senha, email_confirm: true,
    user_metadata: { nome_completo: nome, origem: "marketye" },
  });
  if (cErr || !novo.user) return json({ error: "Não foi possível criar a conta: " + (cErr?.message ?? "") }, 500);
  const userId = novo.user.id;

  const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? null;
  const { data: cad, error: rErr } = await admin.rpc("marketye_cadastrar_especialista_para", {
    p_user_id: userId,
    _dados: {
      nome_completo: nome, email, tipo_pessoa: p.tipo_pessoa === "pj" ? "pj" : "pf", cpf_cnpj: documento, telefone: p.telefone || null,
      cidade: p.cidade || null, estado: p.estado ? String(p.estado).toUpperCase() : null, latitude: p.latitude ?? null, longitude: p.longitude ?? null,
      conselho: p.conselho || null, registro_profissional: p.registro_profissional || null, uf_registro: p.uf_registro || null, bio: p.bio || null,
      modalidades: Array.isArray(p.modalidades) && p.modalidades.length ? p.modalidades : ["presencial"],
      especialidades: Array.isArray(p.especialidades) ? p.especialidades : [],
      aceite_termos: true, user_agent: p.user_agent ?? req.headers.get("user-agent") ?? null, ip, origem: p.origem ?? "site",
    },
  });
  if (rErr || !cad) {
    // Rollback da conta: ninguém fica com conta sem cadastro por erro nosso.
    await admin.auth.admin.deleteUser(userId);
    const msg = (rErr?.message ?? "").replace(/^.*?:\s*/, "");
    return json({ error: msg || "Não foi possível registrar o especialista" }, 400);
  }

  return json({ ok: true, especialista_id: (cad as { id?: string }).id, status: (cad as { status?: string }).status ?? "pendente" });
});
