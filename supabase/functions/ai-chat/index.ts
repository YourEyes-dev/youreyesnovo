import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { exigirUsuario, respostaDeErro } from "../_shared/auth.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
};

interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

interface ChatRequest {
  messages: ChatMessage[];
  contexto?: string;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    // Sem login a IA não responde: antes qualquer pessoa com a URL gastava a
    // chave da OpenAI da casa.
    await exigirUsuario(req);

    const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
    if (!OPENAI_API_KEY) {
      throw new Error("OPENAI_API_KEY não configurada");
    }

    const { messages, contexto }: ChatRequest = await req.json();

    const systemPrompt = `Você é um assistente virtual especializado em segurança do trabalho, ergonomia e saúde ocupacional no Brasil.

Suas áreas de conhecimento incluem:
- NR-17 (Ergonomia) e todas as outras Normas Regulamentadoras
- Análise Ergonômica do Trabalho (AET) e Análise Ergonômica Preliminar (AEP)
- Gestão de EPIs
- Planos de ação e metodologia 5W2H
- Matriz GUT para priorização
- PCMSO, PGR, LTCAT
- Segurança do trabalho em geral

Diretrizes:
- Responda sempre em português brasileiro
- Seja objetivo e prático
- Cite normas e referências quando aplicável
- Forneça exemplos práticos quando possível
- Se não souber algo, admita e sugira onde buscar a informação
- Mantenha respostas concisas, mas completas

${contexto ? `Contexto adicional do usuário: ${contexto}` : ""}`;

    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4o",
        messages: [
          { role: "system", content: systemPrompt },
          ...messages
        ],
        max_tokens: 2000,
        stream: true,
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error("OpenAI API error:", response.status, errorText);
      
      if (response.status === 429) {
        return new Response(
          JSON.stringify({ error: "Limite de requisições excedido. Tente novamente em alguns minutos." }),
          { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
      
      throw new Error(`Erro na API OpenAI: ${response.status}`);
    }

    // Stream the response
    return new Response(response.body, {
      headers: { 
        ...corsHeaders, 
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        "Connection": "keep-alive"
      },
    });

  } catch (error) {
    return respostaDeErro(error, corsHeaders);
  }
});
