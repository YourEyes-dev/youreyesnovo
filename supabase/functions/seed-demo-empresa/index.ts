// =====================================================================
// seed-demo-empresa — EMPRESA DE DEMONSTRAÇÃO (só no ambiente de TESTE)
//
// Cria a "Metalúrgica Exemplo Ltda" com setores, cargos, GHE, ~80
// colaboradores fictícios, duas campanhas psicossociais concluídas (com
// respostas fictícias calculadas pelo mesmo código da tela) e a usuária
// "Ana Demonstração" (gestora, sem Super Admin), para prints de marketing e
// demos de venda sem expor dado de cliente.
//
// Portões (mesmo padrão da seed-e2e-user):
//   1) TOKEN — x-qa-token == QA_E2E_TOKEN;
//   2) TRAVA DE AMBIENTE — só o projeto de TESTE (staging). Nem homologação
//      (que tem cópia de dado real de cliente), nem produção (recusada
//      explicitamente, além de fora da lista).
//
// Isolamento: tudo vive num TENANT PRÓPRIO (DEMO_TENANT_ID). A conta-robô do
// Cypress é owner do tenant da Empresa Staging e não enxerga este — nenhuma
// rotina de teste muda de resultado por causa da demo.
//
// Idempotente: IDs fixos e "confere antes de inserir". Rodar de novo não
// duplica nada; as campanhas são recriadas só se ainda não existirem.
// =====================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.90.1";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import {
  DEMO_CNPJ, DEMO_CPF_ANA, DEMO_EMAIL, DEMO_EMPRESA_ID, DEMO_NOME, DEMO_SENHA_PADRAO, DEMO_TENANT_ID,
  gerarColaboradores, SETORES,
} from "./base.ts";
import { semearPsicossocial } from "./psicossocial.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const QA_E2E_TOKEN = (Deno.env.get("QA_E2E_TOKEN") ?? "").trim();

// ALLOWLIST: só o TESTE. A homologação ficou de fora de propósito (tem dado
// copiado de cliente real); a produção é barrada duas vezes.
const REFS_PERMITIDOS = ["bmehdgthciuvdbvutsdv"];
const REF_PRODUCAO = "diayjpsrcerycycyaxst";

// deno-lint-ignore no-explicit-any
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Admin = ReturnType<typeof createClient<any, "public", any>>;

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-qa-token",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

async function garantirTenantEmpresa(admin: Admin) {
  const { data: t } = await admin.from("tenants").select("id").eq("id", DEMO_TENANT_ID).maybeSingle();
  if (!t) {
    const { error } = await admin.from("tenants").insert({
      id: DEMO_TENANT_ID,
      nome: "Metalúrgica Exemplo Ltda",
      slug: "metalurgica-exemplo-demo",
      plano: "enterprise",
      ativo: true,
      configuracoes: { demo: true, ambiente: "staging", finalidade: "demonstracao_comercial" },
    });
    if (error) throw new Error("tenants: " + error.message);
  }
  const { data: e } = await admin.from("empresa_cadastro").select("id").eq("id", DEMO_EMPRESA_ID).maybeSingle();
  if (!e) {
    const { error } = await admin.from("empresa_cadastro").insert({
      id: DEMO_EMPRESA_ID,
      tenant_id: DEMO_TENANT_ID,
      razao_social: "Metalúrgica Exemplo Ltda",
      nome_fantasia: "Metalúrgica Exemplo",
      cnpj: DEMO_CNPJ,
      cidade: "Joinville",
      estado: "SC",
      cep: "89200-000",
      endereco: "Rua das Indústrias",
      numero: "1000",
      bairro: "Distrito Industrial",
      telefone: "(47) 3000-0000",
      email: "contato@metalurgica-exemplo.demo",
      cnae_principal: "2512800",
      cnae_descricao: "Fabricação de esquadrias de metal",
      grau_risco: 3,
      tipo_pessoa: "pj",
      tipo_unidade: "matriz",
      total_colaboradores: 77,
      ativo: true,
      ai_context:
        "Metalúrgica de médio porte (fictícia, demonstração). Usinagem CNC, solda e montagem de " +
        "estruturas metálicas em dois turnos; manutenção com sobreaviso; logística com empilhadeiras.",
    });
    if (error) throw new Error("empresa_cadastro: " + error.message);
  }
}

/** Departamentos, cargos e GHE (com vínculo GHE↔cargo). Devolve mapas por nome. */
async function garantirEstrutura(admin: Admin) {
  const deptos: Record<string, string> = {};
  const cargos: Record<string, string> = {};
  const ghes: Record<string, string> = {};

  for (const s of SETORES) {
    let { data: d } = await admin.from("departamentos").select("id")
      .eq("tenant_id", DEMO_TENANT_ID).eq("empresa_id", DEMO_EMPRESA_ID).eq("nome", s.nome).maybeSingle();
    if (!d) {
      const r = await admin.from("departamentos").insert({
        tenant_id: DEMO_TENANT_ID, empresa_id: DEMO_EMPRESA_ID, nome: s.nome, descricao: s.descricao, ativo: true,
      }).select("id").single();
      if (r.error) throw new Error("departamentos: " + r.error.message);
      d = r.data;
    }
    deptos[s.nome] = d!.id;

    for (const c of s.cargos) {
      let { data: cg } = await admin.from("cargos").select("id")
        .eq("tenant_id", DEMO_TENANT_ID).eq("empresa_id", DEMO_EMPRESA_ID).eq("nome", c.nome).maybeSingle();
      if (!cg) {
        const r = await admin.from("cargos").insert({
          tenant_id: DEMO_TENANT_ID, empresa_id: DEMO_EMPRESA_ID, nome: c.nome,
          descricao: `${c.nome} — ${s.nome} (empresa de demonstração)`,
          departamento_id: d!.id, ativo: true, nivel: c.nivel,
          objetivo_funcao: `Executar as atividades de ${c.nome.toLowerCase()} com segurança e qualidade.`,
          escopo_geral: `Atividades do setor de ${s.nome}.`,
          responsabilidade: "Cumprir procedimentos, normas de SST e metas do setor.",
        }).select("id").single();
        if (r.error) throw new Error("cargos: " + r.error.message);
        cg = r.data;
      }
      cargos[c.nome] = cg!.id;
    }

    let { data: g } = await admin.from("psicossocial_ghe").select("id")
      .eq("tenant_id", DEMO_TENANT_ID).eq("codigo", s.ghe.codigo).maybeSingle();
    if (!g) {
      const r = await admin.from("psicossocial_ghe").insert({
        tenant_id: DEMO_TENANT_ID, empresa_id: DEMO_EMPRESA_ID,
        codigo: s.ghe.codigo, nome: s.ghe.nome, descricao: s.ghe.descricao, ativo: true,
      }).select("id").single();
      if (r.error) throw new Error("psicossocial_ghe: " + r.error.message);
      g = r.data;
    }
    ghes[s.ghe.codigo] = g!.id;

    for (const c of s.cargos) {
      const { error } = await admin.from("psicossocial_ghe_cargos").upsert({
        tenant_id: DEMO_TENANT_ID, ghe_id: g!.id, cargo_id: cargos[c.nome], departamento_id: d!.id,
      }, { onConflict: "ghe_id,cargo_id", ignoreDuplicates: true });
      if (error) console.error("psicossocial_ghe_cargos:", error.message);
    }
  }
  return { deptos, cargos, ghes };
}

async function garantirColaboradores(admin: Admin, criadoPor: string, cargos: Record<string, string>) {
  const { count } = await admin.from("admissoes").select("id", { count: "exact", head: true })
    .eq("tenant_id", DEMO_TENANT_ID);
  if ((count ?? 0) > 0) return; // já semeados
  const linhas = gerarColaboradores().map((c, i) => ({
    tenant_id: DEMO_TENANT_ID, empresa_id: DEMO_EMPRESA_ID,
    status: "concluido",
    nome_completo: c.nome, cpf: c.cpf,
    data_nascimento: c.dataNascimento,
    estado_civil: i % 3 === 0 ? "solteiro" : "casado",
    genero: c.genero,
    email: c.email,
    telefone: "(47) 99000-" + String(i + 1).padStart(4, "0"),
    cidade: "Joinville", estado: "SC",
    cargo: c.cargo, cargo_id: cargos[c.cargo] ?? null, departamento: c.setor,
    data_admissao: c.dataAdmissao,
    tipo_contrato: "CLT", jornada_trabalho: "44h semanais",
    salario: c.setor === "Administrativo" ? 4200 : 3600,
    gestor_imediato: c.setor === "Administrativo" ? "Gerente Administrativo" : `Liderança de ${c.setor}`,
    criado_por: criadoPor,
  }));
  const { error } = await admin.from("admissoes").insert(linhas);
  if (error) throw new Error("admissoes: " + error.message);
}

/** Conta "Ana Demonstração": owner do TENANT DEMO (não superadmin). */
async function garantirUsuaria(admin: Admin, senha: string): Promise<string> {
  let uid: string | null = null;
  for (let page = 1; page <= 10 && !uid; page++) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 200 });
    if (error) throw new Error("listUsers: " + error.message);
    const achado = data?.users?.find((u) => (u.email ?? "").toLowerCase() === DEMO_EMAIL);
    if (achado) uid = achado.id;
    if (!data?.users?.length || data.users.length < 200) break;
  }
  if (uid) {
    const { error } = await admin.auth.admin.updateUserById(uid, { password: senha, email_confirm: true });
    if (error) throw new Error("updateUserById: " + error.message);
  } else {
    const { data, error } = await admin.auth.admin.createUser({
      email: DEMO_EMAIL, password: senha, email_confirm: true,
      user_metadata: { nome_completo: DEMO_NOME },
    });
    if (error) throw new Error("createUser: " + error.message);
    uid = data.user!.id;
  }

  const { error: pErr } = await admin.from("profiles").upsert({
    user_id: uid, tenant_id: DEMO_TENANT_ID, nome_completo: DEMO_NOME,
    cargo: "Gestora de RH", onboarding_concluido: true,
  }, { onConflict: "user_id" });
  if (pErr) throw new Error("profiles: " + pErr.message);

  // Papel do TENANT (owner = gestão completa do próprio cliente). NÃO é
  // superadmin: superadmin vive na tabela superadmins, que não é tocada.
  const { error: rErr } = await admin.from("user_roles")
    .upsert({ user_id: uid, role: "owner" }, { onConflict: "user_id,role" });
  if (rErr) throw new Error("user_roles: " + rErr.message);
  // Garantia explícita: se alguém tiver marcado esta conta como superadmin, desfaz.
  await admin.from("superadmins").delete().eq("user_id", uid);

  const { data: ub } = await admin.from("usuarios_base").select("id")
    .eq("auth_user_id", uid).maybeSingle();
  const dadosUb = {
    tenant_id: DEMO_TENANT_ID, nome_completo: DEMO_NOME, email_principal: DEMO_EMAIL,
    tipo_usuario: "administrador", status: "ativo", cargo_funcao: "Gestora de RH",
  };
  if (ub) {
    const { error } = await admin.from("usuarios_base").update(dadosUb).eq("auth_user_id", uid);
    if (error) throw new Error("usuarios_base(update): " + error.message);
  } else {
    const { error } = await admin.from("usuarios_base").insert({ ...dadosUb, auth_user_id: uid, cpf: DEMO_CPF_ANA });
    if (error) throw new Error("usuarios_base(insert): " + error.message);
  }

  // Sem o popup diário de humor cobrindo a tela na hora do print.
  const hoje = new Date().toISOString().split("T")[0];
  const { data: humor } = await admin.from("humor_diario").select("id").eq("user_id", uid).eq("data", hoje).limit(1);
  if (!humor?.length) {
    await admin.from("humor_diario").insert({
      tenant_id: DEMO_TENANT_ID, user_id: uid, user_nome: DEMO_NOME, data: hoje, humor: "Bem", emoji: "😊",
    });
  }
  return uid;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  if (req.method !== "POST") return json({ error: "Method Not Allowed" }, 405);

  // ── Portão 1: token ──
  if (!QA_E2E_TOKEN) return json({ error: "QA_E2E_TOKEN nao configurado neste projeto. Seed recusado." }, 503);
  if ((req.headers.get("x-qa-token") ?? "").trim() !== QA_E2E_TOKEN) return json({ error: "Token invalido." }, 401);

  // ── Portão 2: só o ambiente de TESTE ──
  if (SUPABASE_URL.includes(REF_PRODUCAO)) {
    return json({ error: "Recusado: a empresa de demonstracao NUNCA e criada na PRODUCAO." }, 403);
  }
  if (!REFS_PERMITIDOS.some((ref) => SUPABASE_URL.includes(ref))) {
    return json({ error: "Recusado: a empresa de demonstracao so existe no ambiente de TESTE." }, 403);
  }

  let senha = DEMO_SENHA_PADRAO;
  try {
    const bruto = (await req.text()).trim();
    if (bruto) {
      const b = JSON.parse(bruto) as { senha?: string };
      if (b.senha && b.senha.length >= 8) senha = b.senha;
    }
  } catch { /* corpo opcional */ }

  // deno-lint-ignore no-explicit-any
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const admin = createClient<any, "public", any>(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    await garantirTenantEmpresa(admin);
    const uid = await garantirUsuaria(admin, senha);
    const estrutura = await garantirEstrutura(admin);
    await garantirColaboradores(admin, uid, estrutura.cargos);
    const psicossocial = await semearPsicossocial(admin, uid, estrutura.ghes);
    return json({
      ok: true,
      tenant_id: DEMO_TENANT_ID,
      empresa_id: DEMO_EMPRESA_ID,
      login: DEMO_EMAIL,
      psicossocial,
      mensagem: "Empresa de demonstração pronta (Metalúrgica Exemplo Ltda).",
    });
  } catch (e) {
    console.error("seed-demo-empresa:", e);
    return json({ error: (e as Error).message }, 500);
  }
});
