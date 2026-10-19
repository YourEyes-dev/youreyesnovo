import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { autenticar, respostaDeErro } from "../_shared/auth.ts";
import {
  MAX_CARGOS_POR_CHAMADA, SISTEMA, UUID_RE, filtrarCargosDaEmpresa, montarPrompt, prepararCargos, sanitizarResultados,
} from "../_shared/dias-profissao.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
};

const json = (corpo: unknown, status = 200) =>
  new Response(JSON.stringify(corpo), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

// Sugere o dia comemorativo da profissão de cada cargo. SÓ SUGERE: quem aprova é
// uma pessoa na tela de Cultura. Recebe apenas NOMES DE CARGO (nenhum dado de
// colaborador) e exige login. A empresa-mãe (tenant) vem do cadastro do usuário, nunca
// do corpo; a EMPRESA ativa vem do corpo, mas só vale se pertencer a esse tenant, e só
// são analisados os cargos que existem nela (cadastro de cargos e colaboradores).
const POR_PAGINA = 1000;
const MAX_PAGINAS = 50;

// deno-lint-ignore no-explicit-any
async function lerTodos(montar: (de: number, ate: number) => PromiseLike<{ data: any[] | null; error: unknown }>) {
  // deno-lint-ignore no-explicit-any
  const linhas: any[] = [];
  for (let p = 0; p < MAX_PAGINAS; p++) {
    const { data, error } = await montar(p * POR_PAGINA, p * POR_PAGINA + POR_PAGINA - 1);
    if (error) throw error;
    linhas.push(...(data ?? []));
    if (!data || data.length < POR_PAGINA) break;
  }
  return linhas;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const { tenantId, admin } = await autenticar(req);
    const corpo = await req.json();
    const solicitados = prepararCargos(corpo?.cargos);
    if (solicitados.length === 0) return json({ error: `Envie de 1 a ${MAX_CARGOS_POR_CHAMADA} cargos` }, 400);

    // A empresa precisa ser do tenant de quem está logado (nunca confiar no corpo).
    const empresaId = corpo?.empresaId;
    if (typeof empresaId !== "string" || !UUID_RE.test(empresaId)) {
      return json({ error: "Selecione a empresa antes de analisar os cargos." }, 400);
    }
    const { data: empresa } = await admin
      .from("empresa_cadastro")
      .select("id")
      .eq("id", empresaId)
      .eq("tenant_id", tenantId)
      .maybeSingle();
    if (!empresa) return json({ error: "Esta empresa não pertence ao seu cadastro." }, 403);

    // Cargos que existem NESTA empresa: cadastro de cargos e cargo dos colaboradores ativos.
    const [doCadastro, dosColaboradores] = await Promise.all([
      lerTodos((de, ate) =>
        admin.from("cargos").select("nome").eq("tenant_id", tenantId).eq("empresa_id", empresaId).range(de, ate)
      ),
      lerTodos((de, ate) =>
        admin.from("admissoes").select("cargo").eq("tenant_id", tenantId).eq("empresa_id", empresaId).eq("status", "concluido").range(de, ate)
      ),
    ]);
    const { aceitos: cargos, ignorados } = filtrarCargosDaEmpresa(solicitados, [
      ...doCadastro.map((c) => c.nome as string),
      ...dosColaboradores.map((a) => a.cargo as string),
    ]);
    if (cargos.length === 0) {
      return json({ error: "Nenhum dos cargos informados existe na empresa selecionada." }, 400);
    }

    const apiKey = Deno.env.get("OPENAI_API_KEY");
    if (!apiKey) throw new Error("OPENAI_API_KEY não configurada");

    const resposta = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        temperature: 0,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: SISTEMA },
          { role: "user", content: montarPrompt(cargos) },
        ],
      }),
    });

    if (!resposta.ok) {
      console.error("OpenAI API error:", resposta.status, await resposta.text());
      return json({ error: "O serviço de IA não respondeu. Tente de novo em instantes." }, 502);
    }

    const dados = await resposta.json();
    let bruto: unknown = null;
    try {
      bruto = JSON.parse(dados.choices?.[0]?.message?.content ?? "{}");
    } catch {
      return json({ error: "A IA devolveu uma resposta ilegível. Tente de novo." }, 502);
    }

    return json({ sugestoes: sanitizarResultados(cargos, bruto), ignorados });
  } catch (e) {
    return respostaDeErro(e, corsHeaders);
  }
});
