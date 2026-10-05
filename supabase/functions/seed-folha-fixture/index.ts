// =====================================================================
// seed-folha-fixture — semeia um 13º JÁ CALCULADO na Empresa Staging
//
// Por que existe: vários casos e2e do financeiro só aparecem na tela quando
// há DADO calculado (o detalhe do holerite/13º). Sem isso, o teste de tela
// não tem o que asseverar e o caso fica descoberto. Esta função gera, de
// forma idempotente, as 1ª e 2ª parcelas do 13º do ano corrente para os
// colaboradores que a seed-e2e-user já plantou (20 colaboradores, salário
// R$ 5.000), via a RPC decimo_terceiro_lote. Com isso, a aba 13º passa a ter
// linhas e o DETALHE mostra INSS/IRRF/FGTS — destravando o caso DEC13-042.
//
// Fatia 1 da "fixture de folha". A folha MENSAL (para FOLHA-021/022/041) virá
// numa fatia seguinte, com a mesma mecânica.
//
// Dois portões, iguais aos de seed-e2e-user:
//   1) TOKEN combinado — x-qa-token == QA_E2E_TOKEN (segredo por projeto).
//   2) TRAVA DE AMBIENTE — só TESTE/HOMOLOGAÇÃO; produção barrada duas vezes.
// Idempotente: decimo_terceiro_lote pula quem já tem cálculo no ano/parcela.
// =====================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.90.1";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const QA_E2E_TOKEN = (Deno.env.get("QA_E2E_TOKEN") ?? "").trim();

// Mesma allowlist de seed-e2e-user: TESTE (staging) e HOMOLOGAÇÃO. Produção
// nunca entra aqui, e ainda é barrada explicitamente por REF_PRODUCAO.
const REFS_PERMITIDOS = [
  "bmehdgthciuvdbvutsdv", // teste (staging)
  "fgsblefvdabgdouipigz", // homologação
];
const REF_PRODUCAO = "diayjpsrcerycycyaxst";

// Tenant fixo da Empresa Staging (o mesmo de seed-e2e-user).
const TENANT_ID = "11111111-1111-1111-1111-111111111111";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-qa-token",
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

  // ── Portão 1: token combinado ──
  if (!QA_E2E_TOKEN) {
    return json({ error: "QA_E2E_TOKEN nao configurado neste projeto. Seed recusado." }, 503);
  }
  if ((req.headers.get("x-qa-token") ?? "").trim() !== QA_E2E_TOKEN) {
    return json(
      { error: "Token invalido: QA_E2E_TOKEN do GitHub difere do valor no Supabase." },
      401,
    );
  }

  // ── Portão 2: trava de ambiente (nunca semear produção) ──
  if (SUPABASE_URL.includes(REF_PRODUCAO)) {
    return json({ error: "Recusado: esta funcao NUNCA semeia na PRODUCAO." }, 403);
  }
  if (!REFS_PERMITIDOS.some((ref) => SUPABASE_URL.includes(ref))) {
    return json(
      { error: "Recusado: esta funcao so semeia no TESTE ou na HOMOLOGACAO." },
      403,
    );
  }

  const admin = createClient<any, "public", any>(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const ano = new Date().getFullYear();
  const resultado: Record<string, unknown> = { tenant: TENANT_ID, ano, parcelas: {} };

  try {
    // 1ª e 2ª parcela — a 2ª deduz a 1ª, então a ordem importa.
    for (const parcela of [1, 2]) {
      const { data, error } = await admin.rpc("decimo_terceiro_lote", {
        p_tenant: TENANT_ID,
        p_ano: ano,
        p_parcela: parcela,
      });
      if (error) {
        (resultado.parcelas as Record<string, unknown>)[parcela] = { erro: error.message };
      } else {
        // Guarda só o essencial do retorno (criados / ja_existiam).
        const d = (data ?? {}) as Record<string, unknown>;
        (resultado.parcelas as Record<string, unknown>)[parcela] = {
          criados: d.criados ?? 0,
          ja_existiam: d.ja_existiam ?? 0,
          sem_avo: d.sem_avo ?? 0,
        };
      }
    }

    // Conferência: quantos cálculos de 13º existem agora no ano, no tenant.
    const { count } = await admin
      .from("folha_13_calculo")
      .select("id", { count: "exact", head: true })
      .eq("tenant_id", TENANT_ID)
      .eq("ano", ano);
    resultado.total_calculos_no_ano = count ?? null;

    return json({ ok: true, ...resultado });
  } catch (e) {
    return json({ ok: false, erro: (e as Error).message, ...resultado }, 500);
  }
});
