import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const { colaboradorNome, notas, evidencias, dimensoes } = await req.json();
    const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
    if (!OPENAI_API_KEY) throw new Error("OPENAI_API_KEY não configurada");

    // Montar resumo de evidências
    const feedbacksTexto = (evidencias?.feedbacks || []).slice(0, 5)
      .map((f: any) => `- [${f.categoria}] ${f.descricao}`).join("\n") || "Nenhum feedback registrado";

    const ocorrenciasTexto = (evidencias?.ocorrencias || []).slice(0, 5)
      .map((o: any) => `- [${o.tipo}] ${o.descricao}`).join("\n") || "Nenhuma ocorrência registrada";

    const metasTexto = (evidencias?.metas || []).slice(0, 5)
      .map((m: any) => `- ${m.titulo}: ${m.progresso}% (${m.status})`).join("\n") || "Nenhuma meta cadastrada";

    const trilhasTexto = (evidencias?.trilhas || []).slice(0, 5)
      .map((t: any) => `- ${t.nome}: ${t.percentual}% (${t.status})`).join("\n") || "Nenhuma trilha registrada";

    // Montar resumo de notas por dimensão
    const notasPorDimensao = (dimensoes || []).map((d: any) => {
      const notasDim = d.criterios.map((c: any) => notas[c.id]).filter((n: number) => n > 0);
      const media = notasDim.length > 0 ? (notasDim.reduce((a: number, b: number) => a + b, 0) / notasDim.length).toFixed(1) : "N/A";
      return `${d.nome}: média ${media}/5`;
    }).join(", ");

    const riscoTexto = evidencias?.risco?.burnout
      ? `Burnout: ${evidencias.risco.burnout} | Boreout: ${evidencias.risco.boreout} | IRP: ${evidencias.risco.irp}`
      : "Sem dados de risco disponíveis";

    const systemPrompt = `Você é um assistente de RH especializado em avaliações de desempenho. 
Sua função é gerar rascunhos técnicos, objetivos e baseados em evidências para gestores revisarem.
Seja específico, use os dados fornecidos, evite generalidades.
NUNCA invente informações além das evidências fornecidas.
Responda sempre em português brasileiro.`;

    const userPrompt = `Gere um rascunho de avaliação de desempenho para ${colaboradorNome}.

NOTAS POR DIMENSÃO: ${notasPorDimensao}

FEEDBACKS DO PERÍODO:
${feedbacksTexto}

OCORRÊNCIAS DO PERÍODO:
${ocorrenciasTexto}

METAS:
${metasTexto}

TRILHAS DE APRENDIZADO:
${trilhasTexto}

INDICADORES DE RISCO HUMANO (apenas contexto, não diagnóstico):
${riscoTexto}

Retorne um JSON com:
{
  "pontos_fortes": "2-3 parágrafos sobre pontos fortes baseados nas evidências",
  "areas_desenvolvimento": "2-3 parágrafos sobre áreas de desenvolvimento",
  "resumo": "1 parágrafo resumindo o desempenho geral e recomendando próximos passos"
}`;

    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userPrompt },
        ],
        response_format: { type: "json_object" },
        temperature: 0.4,
      }),
    });

    if (!response.ok) {
      const err = await response.text();
      throw new Error(`OpenAI error: ${response.status} - ${err}`);
    }

    const result = await response.json();
    const content = JSON.parse(result.choices[0].message.content);

    return new Response(JSON.stringify(content), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("avaliacao-ia-rascunho error:", error);
    return new Response(JSON.stringify({ error: (error as Error).message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
