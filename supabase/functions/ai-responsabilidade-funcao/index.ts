import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { getCompanyContext } from '../_shared/ai-helper.ts'

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { cargoNome, descricao, textoAtual, acao, competenciaNome, competenciaTipo, tenantId,
            objetivoFuncao, atividades, competencias } = await req.json();

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    const companyContext = await getCompanyContext(supabase, tenantId);

    const apiKey = Deno.env.get("OPENAI_API_KEY");
    if (!apiKey) throw new Error("OPENAI_API_KEY not configured");

    let systemPrompt = "";
    let userPrompt = "";

    if (acao === "sugerir_perfil_ideal") {
      const atividadesTxt = Array.isArray(atividades) ? atividades.filter(Boolean).join("; ") : (atividades || "");
      const competenciasTxt = Array.isArray(competencias) ? competencias.filter(Boolean).join("; ") : (competencias || "");
      systemPrompt = `Você é especialista em RH e no instrumento "Mapa Comportamental" da casa. A partir do objetivo, atividades e competências comportamentais de uma FUNÇÃO (cargo), sugira o ESTILO comportamental que TENDE a fluir nela — em linguagem de tendência, nunca de capacidade ou aptidão. Não existe perfil melhor nem pior; é referência de desenvolvimento, não critério de seleção/promoção/desligamento.

Responda SOMENTE em JSON válido, com exatamente estas chaves e valores em minúsculas:
- "arquetipo_ideal": um de "pioneiro" | "conector" | "guardiao" | "estrategista"
- "motor_ideal": array com 1 ou 2 de "racional" | "relacional" | "pragmatico"
- "modo_ideal": um de "constante" | "cadenciado" | "misto"
- "justificativa": 1 a 2 frases curtas explicando a tendência (sem julgamento de valor)

Referência dos arquétipos (Foco × Ritmo): pioneiro = tarefas + acelerado; conector = pessoas + acelerado; guardiao = pessoas + ponderado; estrategista = tarefas + ponderado.

${companyContext}`;
      userPrompt = `Função: ${cargoNome || ""}
Objetivo: ${objetivoFuncao || "(não informado)"}
Atividades: ${atividadesTxt || "(não informadas)"}
Competências comportamentais: ${competenciasTxt || "(não informadas)"}

Sugira o estilo comportamental que tende a fluir nesta função, no formato JSON pedido.`;
    } else if (acao === "sugerir_descricao_competencia") {
      systemPrompt = `Você é um especialista em gestão de competências e RH. Gere descrições curtas e objetivas para competências profissionais. Retorne apenas o texto da descrição (1-2 frases), sem explicações adicionais.
      
${companyContext}`;
      userPrompt = `Gere uma descrição curta e objetiva para a seguinte competência:

Competência: ${competenciaNome}
Tipo: ${competenciaTipo || "técnica"}
${cargoNome ? `Função: ${cargoNome}` : ""}

A descrição deve explicar o que essa competência significa no contexto da função e como ela se aplica no dia a dia. Seja conciso (1-2 frases).`;
    } else if (acao === "melhorar") {
      systemPrompt = `Você é um especialista em descrição de cargos e gestão de pessoas. Melhore textos de responsabilidade de função tornando-os mais profissionais, claros e completos. Retorne apenas o texto melhorado, sem explicações ou formatação adicional.
      
${companyContext}`;
      userPrompt = `Cargo: ${cargoNome}${descricao ? `\nDescrição: ${descricao}` : ""}

Texto atual de responsabilidade:
${textoAtual}

Melhore este texto tornando-o mais profissional, claro e completo. Mantenha o mesmo tom e escopo, mas melhore a clareza, objetividade e completude. Retorne apenas o texto melhorado.`;
    } else {
      // acao === "gerar"
      systemPrompt = `Você é um especialista em descrição de cargos, RH e gestão de pessoas. Gere textos profissionais de responsabilidade de função que descrevam objetivos, impacto no negócio e área de atuação. Retorne apenas o texto gerado, sem explicações ou formatação adicional.
      
${companyContext}`;
      userPrompt = `Cargo: ${cargoNome}${descricao ? `\nDescrição: ${descricao}` : ""}${textoAtual ? `\nContexto adicional: ${textoAtual}` : ""}

Gere um texto profissional de responsabilidade para este cargo. O texto deve descrever:
- Objetivo principal da função
- Impacto no negócio
- Área de atuação e escopo de responsabilidade
- Principais entregas esperadas

Seja objetivo, profissional e direto. Use linguagem corporativa adequada. Retorne apenas o texto (2 a 4 parágrafos), sem títulos nem formatação.`;
    }

    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userPrompt },
        ],
        ...(acao === "sugerir_perfil_ideal" ? { response_format: { type: "json_object" } } : {}),
      }),
    });

    if (!response.ok) {
      if (response.status === 429) {
        return new Response(JSON.stringify({ error: "Limite de requisições excedido. Tente novamente em breve." }), {
          status: 429,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      if (response.status === 402) {
        return new Response(JSON.stringify({ error: "Limite da API OpenAI atingido. Verifique o saldo/limites da chave." }), {
          status: 402,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      const errorText = await response.text();
      throw new Error(`AI API error: ${response.status} - ${errorText}`);
    }

    const data = await response.json();
    const conteudo = data.choices?.[0]?.message?.content?.trim() || "";

    if (acao === "sugerir_perfil_ideal") {
      // Valida contra os enums do instrumento; descarta o que vier fora.
      const ARQ = ["pioneiro", "conector", "guardiao", "estrategista"];
      const MOT = ["racional", "relacional", "pragmatico"];
      const MOD = ["constante", "cadenciado", "misto"];
      let parsed: Record<string, unknown> = {};
      try { parsed = JSON.parse(conteudo); } catch { parsed = {}; }
      const arq = String(parsed.arquetipo_ideal ?? "").toLowerCase();
      const modo = String(parsed.modo_ideal ?? "").toLowerCase();
      const motoresRaw = Array.isArray(parsed.motor_ideal) ? parsed.motor_ideal : [];
      const perfil = {
        arquetipo_ideal: ARQ.includes(arq) ? arq : null,
        motor_ideal: motoresRaw.map((m) => String(m).toLowerCase()).filter((m) => MOT.includes(m)).slice(0, 2),
        modo_ideal: MOD.includes(modo) ? modo : null,
        justificativa: typeof parsed.justificativa === "string" ? parsed.justificativa : null,
      };
      return new Response(JSON.stringify({ perfil }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ texto: conteudo }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Error:", error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
