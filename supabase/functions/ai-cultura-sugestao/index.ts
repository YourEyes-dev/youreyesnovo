import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3'
import { getCompanyContext } from '../_shared/ai-helper.ts'
import { autenticar, respostaDeErro } from '../_shared/auth.ts'

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    // A empresa vem do cadastro do usuário logado, nunca do corpo da requisição.
    const { tenantId } = await autenticar(req);
    const { campo, contexto } = await req.json();

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    const companyContext = await getCompanyContext(supabase, tenantId);

    if (!campo) {
      return new Response(JSON.stringify({ error: "Campo é obrigatório" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const prompts: Record<string, string> = {
      missao: `Crie uma declaração de missão corporativa profissional e inspiradora para uma empresa. ${contexto?.visao ? `A visão da empresa é: "${contexto.visao}".` : ""} ${contexto?.valores?.length ? `Os valores são: ${contexto.valores.join(", ")}.` : ""} A missão deve ter 2-3 frases, ser clara, objetiva e comunicar o propósito fundamental da organização. Retorne APENAS o texto da missão, sem aspas, títulos ou explicações.`,

      visao: `Crie uma declaração de visão corporativa profissional e aspiracional para uma empresa. ${contexto?.missao ? `A missão da empresa é: "${contexto.missao}".` : ""} ${contexto?.valores?.length ? `Os valores são: ${contexto.valores.join(", ")}.` : ""} A visão deve ter 1-2 frases, ser ambiciosa, inspiradora e descrever onde a empresa quer chegar no futuro. Retorne APENAS o texto da visão, sem aspas, títulos ou explicações.`,

      valores: `Sugira 5 a 7 valores corporativos relevantes e profissionais para uma empresa. ${contexto?.missao ? `Missão: "${contexto.missao}".` : ""} ${contexto?.visao ? `Visão: "${contexto.visao}".` : ""} ${contexto?.valores_existentes?.length ? `Valores já cadastrados (NÃO repita): ${contexto.valores_existentes.join(", ")}.` : ""} Cada valor deve ser uma palavra ou expressão curta (máximo 3 palavras). Retorne APENAS uma lista JSON de strings, exemplo: ["Integridade", "Inovação"]. Sem explicações.`,

      principios: `Sugira 4 a 6 princípios culturais profissionais para uma empresa. ${contexto?.missao ? `Missão: "${contexto.missao}".` : ""} ${contexto?.valores?.length ? `Valores: ${contexto.valores.join(", ")}.` : ""} ${contexto?.principios_existentes?.length ? `Princípios já cadastrados (NÃO repita): ${contexto.principios_existentes.join(", ")}.` : ""} Cada princípio deve ser uma frase curta e impactante (máximo 8 palavras). Retorne APENAS uma lista JSON de strings. Sem explicações.`,

      comportamentos_esperados: `Sugira 5 a 7 comportamentos esperados dos colaboradores em uma empresa. ${contexto?.valores?.length ? `Valores da empresa: ${contexto.valores.join(", ")}.` : ""} ${contexto?.principios?.length ? `Princípios: ${contexto.principios.join(", ")}.` : ""} ${contexto?.existentes?.length ? `Comportamentos já cadastrados (NÃO repita): ${contexto.existentes.join(", ")}.` : ""} Cada comportamento deve ser uma frase curta e prática (máximo 10 palavras), começando com verbo no infinitivo. Retorne APENAS uma lista JSON de strings. Sem explicações.`,

      comportamentos_nao_tolerados: `Sugira 4 a 6 comportamentos não tolerados em uma empresa. ${contexto?.valores?.length ? `Valores da empresa: ${contexto.valores.join(", ")}.` : ""} ${contexto?.principios?.length ? `Princípios: ${contexto.principios.join(", ")}.` : ""} ${contexto?.existentes?.length ? `Comportamentos já cadastrados (NÃO repita): ${contexto.existentes.join(", ")}.` : ""} Cada comportamento deve ser uma frase curta e clara (máximo 10 palavras). Retorne APENAS uma lista JSON de strings. Sem explicações.`,
    };

    const prompt = prompts[campo];
    if (!prompt) {
      return new Response(JSON.stringify({ error: "Campo inválido" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const apiKey = Deno.env.get("OPENAI_API_KEY");
    if (!apiKey) throw new Error("OPENAI_API_KEY not configured");

    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        response_format: { type: "json_object" },
        max_tokens: 8000,
        messages: [
          { role: "system", content: `Você é um consultor de cultura organizacional. Responda apenas com o conteúdo solicitado, sem explicações adicionais. 
          
${companyContext}` },
          { role: "user", content: prompt }
        ],
      }),
    });

    if (!response.ok) {
      if (response.status === 429) {
        return new Response(JSON.stringify({ error: "Limite de requisições excedido. Tente novamente em alguns minutos." }), {
          status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      if (response.status === 402) {
        return new Response(JSON.stringify({ error: "Créditos insuficientes." }), {
          status: 402, headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      const errorText = await response.text();
      throw new Error(`AI API error: ${response.status} - ${errorText}`);
    }

    const data = await response.json();
    let content = data.choices?.[0]?.message?.content?.trim() || "";

    // For text fields (missao, visao) return as texto
    if (campo === "missao" || campo === "visao") {
      return new Response(JSON.stringify({ texto: content }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // For list fields, parse JSON array
    // Clean markdown code blocks if present
    if (content.startsWith("```")) {
      content = content.replace(/^```json?\n?/, "").replace(/\n?```$/, "");
    }
    
    let items: string[] = [];
    try {
      items = JSON.parse(content);
      if (!Array.isArray(items)) items = [content];
    } catch {
      // Try to extract items line by line
      items = content.split("\n").map((l: string) => l.replace(/^[-•*\d.)\s]+/, "").trim()).filter(Boolean);
    }

    return new Response(JSON.stringify({ items }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return respostaDeErro(error, corsHeaders);
  }
});
