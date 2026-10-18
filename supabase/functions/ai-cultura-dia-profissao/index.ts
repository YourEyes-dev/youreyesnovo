import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { autenticar, respostaDeErro } from "../_shared/auth.ts";
import {
  MAX_CARGOS_POR_CHAMADA, SISTEMA, montarPrompt, prepararCargos, sanitizarResultados,
} from "../_shared/dias-profissao.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
};

const json = (corpo: unknown, status = 200) =>
  new Response(JSON.stringify(corpo), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

// Sugere o dia comemorativo da profissão de cada cargo. SÓ SUGERE: quem aprova é
// uma pessoa na tela de Cultura. Recebe apenas NOMES DE CARGO (nenhum dado de
// colaborador) e exige login; a empresa vem do cadastro do usuário, nunca do corpo.
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    await autenticar(req);
    const corpo = await req.json();
    const cargos = prepararCargos(corpo?.cargos);
    if (cargos.length === 0) return json({ error: `Envie de 1 a ${MAX_CARGOS_POR_CHAMADA} cargos` }, 400);

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

    return json({ sugestoes: sanitizarResultados(cargos, bruto) });
  } catch (e) {
    return respostaDeErro(e, corsHeaders);
  }
});
