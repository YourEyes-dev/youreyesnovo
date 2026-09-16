import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
    if (!OPENAI_API_KEY) throw new Error("OPENAI_API_KEY não configurada");

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const authHeader = req.headers.get("Authorization");
    const token = authHeader?.replace("Bearer ", "");
    let tenantId: string | null = null;

    if (token && token !== Deno.env.get("SUPABASE_ANON_KEY")) {
      const { data: { user } } = await supabase.auth.getUser(token);
      if (user) {
        const { data: profile } = await supabase
          .from("profiles")
          .select("tenant_id")
          .eq("user_id", user.id)
          .single();
        tenantId = profile?.tenant_id;
      }
    }

    const { itens_xml, tenant_id: bodyTenantId } = await req.json();
    tenantId = tenantId || bodyTenantId;

    if (!tenantId) {
      return new Response(
        JSON.stringify({ error: "Tenant não identificado" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!itens_xml || !Array.isArray(itens_xml) || itens_xml.length === 0) {
      return new Response(
        JSON.stringify({ error: "Nenhum item enviado para análise" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Fetch existing EPI tipos for this tenant
    const { data: tipos } = await supabase
      .from("epi_tipos")
      .select("id, nome, categoria, ca_numero, marca, fabricante, is_active")
      .eq("tenant_id", tenantId);

    const tiposExistentes = (tipos || []).filter((t: any) => t.is_active !== false);

    const tiposListStr = tiposExistentes.length > 0
      ? tiposExistentes.map((t: any) => `- ID: "${t.id}" | Nome: "${t.nome}" | Categoria: "${t.categoria || 'N/A'}" | CA: "${t.ca_numero || 'N/A'}" | Marca: "${t.marca || 'N/A'}"`).join("\n")
      : "Nenhum tipo de EPI cadastrado.";

    const itensStr = itens_xml.map((item: any, i: number) =>
      `Item ${i + 1}: Descrição="${item.descricao}", Qtd=${item.quantidade}, V.Unit=${item.valor_unitario}, V.Total=${item.valor_total}`
    ).join("\n");

    const systemPrompt = `Você é um especialista em EPIs (Equipamentos de Proteção Individual) no Brasil.
Sua tarefa é analisar itens de uma Nota Fiscal e vinculá-los aos tipos de EPI cadastrados no sistema.

TIPOS DE EPI CADASTRADOS:
${tiposListStr}

REGRAS:
1. Para cada item da NF, tente encontrar o tipo de EPI correspondente baseado na descrição.
2. Se encontrar correspondência, retorne o ID do tipo existente.
3. Se NÃO encontrar correspondência, sugira a criação de um novo tipo com: nome limpo, categoria apropriada.
4. Categorias válidas: "Proteção da Cabeça", "Proteção Auditiva", "Proteção Respiratória", "Proteção Visual", "Proteção Facial", "Proteção das Mãos", "Proteção dos Pés", "Proteção contra Quedas", "Proteção do Tronco", "Sinalização e Visibilidade", "Outros"
5. Limpe o nome do produto: remova códigos, referências de fornecedor, e deixe apenas o nome genérico do EPI.

Responda APENAS com um JSON válido, sem markdown, no formato:
{
  "matches": [
    {
      "index": 0,
      "tipo_id": "uuid-existente ou null se novo",
      "matched": true ou false,
      "nome_limpo": "Nome limpo do EPI",
      "categoria_sugerida": "Categoria",
      "confianca": "alta/media/baixa"
    }
  ]
}`;


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
          { role: "user", content: `Analise estes itens de Nota Fiscal e vincule aos tipos de EPI:\n\n${itensStr}` },
        ],
      }),
    });

    if (!response.ok) {
      if (response.status === 429) {
        return new Response(
          JSON.stringify({ error: "Limite de requisições excedido. Tente novamente em alguns minutos." }),
          { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
      if (response.status === 402) {
        return new Response(
          JSON.stringify({ error: "Créditos insuficientes. Adicione créditos ao workspace." }),
          { status: 402, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
      const errorText = await response.text();
      console.error("AI gateway error:", response.status, errorText);
      return new Response(
        JSON.stringify({ error: "Erro ao consultar IA" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const aiData = await response.json();
    const aiContent = aiData.choices?.[0]?.message?.content || "";
    
    // Parse AI response - clean markdown fences if present
    let cleanedContent = aiContent.trim();
    if (cleanedContent.startsWith("```")) {
      cleanedContent = cleanedContent.replace(/^```(?:json)?\s*/, "").replace(/\s*```$/, "");
    }

    let aiResult: { matches: any[] };
    try {
      aiResult = JSON.parse(cleanedContent);
    } catch (parseErr) {
      console.error("Failed to parse AI response:", cleanedContent);
      return new Response(
        JSON.stringify({ error: "Erro ao interpretar resposta da IA", raw: cleanedContent }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Auto-create new tipos for unmatched items
    const results = [];
    for (const match of aiResult.matches) {
      if (match.matched && match.tipo_id) {
        // Existing tipo - find or note the epi record
        const { data: epiRecord } = await supabase
          .from("epis")
          .select("id")
          .eq("tipo_id", match.tipo_id)
          .eq("tenant_id", tenantId)
          .maybeSingle();

        results.push({
          ...match,
          epi_id: epiRecord?.id || match.tipo_id, // fallback to tipo_id for auto-creation in useImportacaoNF
          created: false,
        });
      } else {
        // Create new tipo
        const { data: novoTipo, error: tipoErr } = await supabase
          .from("epi_tipos")
          .insert({
            tenant_id: tenantId,
            nome: match.nome_limpo || `EPI - Item ${match.index + 1}`,
            categoria: match.categoria_sugerida || "Outros",
            is_active: true,
            validade_meses: 12,
          })
          .select("id, nome, categoria")
          .single();

        if (tipoErr) {
          console.error("Error creating tipo:", tipoErr);
          results.push({ ...match, epi_id: null, created: false, error: tipoErr.message });
          continue;
        }

        results.push({
          ...match,
          tipo_id: novoTipo.id,
          epi_id: novoTipo.id, // will be resolved in useImportacaoNF
          nome_limpo: novoTipo.nome,
          categoria_sugerida: novoTipo.categoria,
          created: true,
        });
      }
    }

    return new Response(
      JSON.stringify({ matches: results }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("ai-nf-match error:", error);
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : "Erro desconhecido" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
