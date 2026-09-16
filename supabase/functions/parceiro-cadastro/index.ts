// Supabase Edge Function: parceiro-cadastro
// Autocadastro no Programa de Parceiros para quem AINDA NÃO tem conta.
// Cria o usuário (e-mail confirmado, sem depender de e-mail de confirmação),
// o parceiro e o vínculo. A regra de status por tipo (indicador ativo,
// demais pendentes) é do trigger no banco — aqui não se decide nada disso.
// Quem já tem conta usa a função SQL parceiro_cadastrar (autenticado).
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

const TIPOS = ["indicador", "representante", "implantador", "clinica", "contabilidade"];
const TRILHAS = ["indicador", "representante", "operador"];

type Payload = {
  nome?: string; email?: string; senha?: string; tipo_parceiro?: string; trilha?: string; tipo_pessoa?: string;
  documento?: string; telefone?: string; endereco?: string; cidade?: string; uf?: string; cep?: string;
  raio_atuacao_km?: number; aceite_termos?: boolean; user_agent?: string;
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Método não permitido" }, 405);

  let p: Payload;
  try { p = await req.json(); } catch { return json({ error: "JSON inválido" }, 400); }

  const nome = (p.nome ?? "").trim();
  const email = (p.email ?? "").trim().toLowerCase();
  const senha = p.senha ?? "";
  const tipo = (p.tipo_parceiro ?? "indicador").trim();
  if (nome.length < 3) return json({ error: "Informe o nome (mínimo 3 letras)" }, 400);
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: "E-mail inválido" }, 400);
  if (senha.length < 6) return json({ error: "A senha precisa ter ao menos 6 caracteres" }, 400);
  if (!TIPOS.includes(tipo)) return json({ error: "Tipo de parceiro inválido" }, 400);
  const trilha = p.trilha && TRILHAS.includes(p.trilha) ? p.trilha : null; // null = o banco deriva do perfil
  if (p.aceite_termos !== true) return json({ error: "É preciso aceitar os termos do programa" }, 400);

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Conta já existe? Não criamos nem alteramos senha de ninguém: a pessoa
  // entra com a conta que tem e conclui o cadastro autenticada.
  const { data: lista, error: lErr } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
  if (lErr) return json({ error: "Falha ao consultar contas: " + lErr.message }, 500);
  const existente = lista?.users?.find((u) => (u.email ?? "").toLowerCase() === email);
  if (existente) {
    return json({ error: "Já existe uma conta com esse e-mail. Entre com ela em /parceiros/entrar e conclua o cadastro de parceiro.", ja_existe: true }, 409);
  }

  const { data: novo, error: cErr } = await admin.auth.admin.createUser({
    email, password: senha, email_confirm: true,
    user_metadata: { nome_completo: nome, origem: "programa_parceiros" },
  });
  if (cErr || !novo.user) return json({ error: "Não foi possível criar a conta: " + (cErr?.message ?? "") }, 500);
  const userId = novo.user.id;

  const { data: parceiro, error: pErr } = await admin
    .from("parceiros")
    .insert({
      nome, tipo_pessoa: p.tipo_pessoa === "pf" ? "pf" : "pj", documento: p.documento || null,
      tipo_parceiro: tipo, trilha, email, telefone: p.telefone || null, cidade: p.cidade || null,
      uf: p.uf ? String(p.uf).toUpperCase() : null, cep: p.cep || null, endereco: p.endereco?.trim() || null,
      raio_atuacao_km: Number.isFinite(p.raio_atuacao_km) ? p.raio_atuacao_km : 50,
      aceite_termos_em: new Date().toISOString(), created_by: userId,
    })
    .select("id, codigo, status")
    .single();
  if (pErr || !parceiro) {
    await admin.auth.admin.deleteUser(userId);
    return json({ error: "Não foi possível registrar o parceiro: " + (pErr?.message ?? "") }, 500);
  }

  const { error: vErr } = await admin.from("parceiro_usuarios").insert({ parceiro_id: parceiro.id, user_id: userId, papel: "dono" });
  if (vErr) return json({ error: "Conta criada, mas o vínculo falhou: " + vErr.message }, 500);

  // O aceite marcado no formulário só manifesta a intenção (aceite_termos_em).
  // O contrato de verdade é gerado com os dados das duas partes e fica PENDENTE
  // até a assinatura eletrônica (assinatura, selfie, IP, dispositivo, localização,
  // hash) em /assinar-contrato/:token — o mesmo fluxo dos contratos do SuperAdmin.
  let contratoToken: string | null = null;
  try {
    const { data: ini, error: iniErr } = await admin.rpc("parceiro_contrato_iniciar_assinatura_para", { p_parceiro_id: parceiro.id });
    if (iniErr) console.error("contrato pendente (nao-fatal):", iniErr.message);
    contratoToken = (ini as { token?: string } | null)?.token ?? null;
  } catch (e) {
    console.error("contrato pendente (nao-fatal):", (e as Error).message);
  }

  return json({ ok: true, parceiro_id: parceiro.id, codigo: parceiro.codigo, status: parceiro.status, contrato_token: contratoToken });
});
