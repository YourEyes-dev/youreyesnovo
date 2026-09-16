// =====================================================================
// qa-disparar-cypress — dispara a corrida de testes de tela (Cypress) na
// esteira do GitHub Actions, sob demanda, a partir do botão "Rodar testes"
// do painel de QA (/admin/qa/runner, aba Cypress).
//
// Por que existe uma função no meio do caminho, em vez de o navegador
// chamar a API do GitHub direto: acionar um workflow exige um token do
// GitHub com permissão de escrita em Actions. Um token desses NÃO pode
// viver no front (site estático, público) — vazaria para qualquer visitante.
// Aqui ele fica só no ambiente da Edge Function (secret GITHUB_DISPATCH_TOKEN)
// e nunca chega ao navegador.
//
// Portões (nesta ordem):
//   1) JWT válido do chamador (Authorization: Bearer ...);
//   2) o chamador é superadmin ativo (tabela `superadmins`);
//   3) o token do GitHub está configurado.
// Só então dispara o workflow certo na branch alvo (default: main) — o da
// homologação (cypress-homologacao.yml) ou o do teste (cypress.yml), escolhido
// pelo ambiente do próprio projeto Supabase (ver WORKFLOW_FILE abaixo).
//
// verify_jwt = false no config.toml: o JWT é validado aqui dentro (para
// devolver 401/403 claros e tratar o preflight OPTIONS), não pelo gateway.
// =====================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.90.1";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
// .trim(): espaço/quebra de linha a mais no copiar-colar do segredo é a causa
// mais comum de "Bad credentials" na API do GitHub.
const GITHUB_TOKEN = (Deno.env.get("GITHUB_DISPATCH_TOKEN") ?? "").trim();
// Configuráveis por ambiente; default aponta para este repositório.
const GITHUB_REPO = (Deno.env.get("GITHUB_REPO") ?? "ustudy123/youreyesnovo").trim();
const WORKFLOW_REF = (Deno.env.get("GITHUB_CYPRESS_REF") ?? "main").trim();

// Ref do projeto de HOMOLOGAÇÃO. O botão de cada ambiente deve disparar a
// esteira DAQUELE ambiente: a homologação tem esteira própria
// (cypress-homologacao.yml, contra o site e o banco da homologação); o teste
// usa a sua (cypress.yml). Antes o botão da homologação disparava a suíte do
// TESTE — resultado no painel errado, confusão sobre qual ambiente foi testado.
const HOMOLOGACAO_REF = "fgsblefvdabgdouipigz";

// Workflow alvo: um override explícito por env vence (escape hatch); senão,
// detecta o ambiente pela URL do próprio projeto. Assim o MESMO deploy serve
// os dois projetos Supabase, e o botão de cada um mira a esteira certa sem
// configuração extra — só o GITHUB_DISPATCH_TOKEN precisa existir em cada um.
const WORKFLOW_FILE = (
  (Deno.env.get("GITHUB_CYPRESS_WORKFLOW") ?? "").trim() ||
  (SUPABASE_URL.includes(HOMOLOGACAO_REF) ? "cypress-homologacao.yml" : "cypress.yml")
);

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  if (req.method !== "POST") return json({ error: "Method Not Allowed" }, 405);

  // ── Portão 1: JWT do chamador ──────────────────────────────────────────
  const authHeader = req.headers.get("authorization") ?? "";
  const jwt = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : null;
  if (!jwt) return json({ error: "Sessão ausente. Faça login novamente." }, 401);

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userError } = await admin.auth.getUser(jwt);
  if (userError || !userData?.user) {
    return json({ error: "Sessão inválida. Faça login novamente." }, 401);
  }
  const userId = userData.user.id;

  // ── Portão 2: superadmin ativo ─────────────────────────────────────────
  const { data: superadmin } = await admin
    .from("superadmins")
    .select("id")
    .eq("user_id", userId)
    .eq("ativo", true)
    .maybeSingle();

  if (!superadmin) {
    return json({ error: "Apenas superadmin pode disparar os testes de tela." }, 403);
  }

  // ── Portão 3: token do GitHub configurado ──────────────────────────────
  if (!GITHUB_TOKEN) {
    return json(
      {
        error:
          "GITHUB_DISPATCH_TOKEN não configurado neste projeto Supabase. " +
          "Crie um token do GitHub com permissão Actions: write e salve como " +
          "secret GITHUB_DISPATCH_TOKEN para habilitar o botão.",
      },
      503,
    );
  }

  // ── Dispara o workflow (workflow_dispatch) ─────────────────────────────
  const url =
    `https://api.github.com/repos/${GITHUB_REPO}/actions/workflows/${WORKFLOW_FILE}/dispatches`;

  let resp: Response;
  try {
    resp = await fetch(url, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${GITHUB_TOKEN}`,
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "youreyes-qa-runner",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ ref: WORKFLOW_REF }),
    });
  } catch (e) {
    return json(
      { error: `Não consegui falar com o GitHub: ${(e as Error).message}` },
      502,
    );
  }

  // Sucesso do dispatch é 204 No Content.
  if (resp.status === 204) {
    return json({
      ok: true,
      mensagem: "Corrida disparada. Ela aparece na esteira em instantes.",
      acompanhar: `https://github.com/${GITHUB_REPO}/actions/workflows/${WORKFLOW_FILE}`,
    });
  }

  // Erros comuns com dica de causa.
  const corpo = await resp.text().catch(() => "");
  let dica = "";
  if (resp.status === 401) dica = " (token inválido ou expirado)";
  else if (resp.status === 403) dica = " (token sem permissão Actions: write neste repositório)";
  else if (resp.status === 404) {
    dica =
      ` (workflow '${WORKFLOW_FILE}' não encontrado na branch '${WORKFLOW_REF}', ` +
      "ou o token não enxerga o repositório)";
  } else if (resp.status === 422) dica = ` (branch '${WORKFLOW_REF}' inválida para dispatch)`;

  return json(
    {
      error: `GitHub recusou o disparo (HTTP ${resp.status})${dica}. ${corpo}`.trim(),
    },
    502,
  );
});
