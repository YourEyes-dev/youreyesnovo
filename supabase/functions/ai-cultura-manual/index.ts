import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3'
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
    const {
      missao, visao, valores, principios, comportamentos_esperados, comportamentos_nao_tolerados,
      empresa_nome, organograma, tenantId,
      proposito, carta_boas_vindas, tom_de_voz, codigo_conduta, dress_code, modelo_trabalho,
      documentos_cultura,
    } = await req.json();

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    const companyContext = await getCompanyContext(supabase, tenantId);

    // Build organogram HTML section from tree data
    function buildOrgHtml(nodes: any[], level = 0): string {
      if (!nodes || nodes.length === 0) return "";
      const indent = level * 32;
      return nodes.map((node: any) => {
        const children = (node.children || []);
        const bg = level === 0 ? "#1e3a5f" : level === 1 ? "#2d8a6e" : level === 2 ? "#f4a261" : "#6c757d";
        const textColor = "#ffffff";
        const childrenHtml = buildOrgHtml(children, level + 1);
        return `
          <div style="margin-left:${indent}px; margin-bottom:8px;">
            <div style="display:inline-block; background:${bg}; color:${textColor}; border-radius:8px; padding:10px 18px; font-size:14px; font-weight:600; box-shadow:0 2px 8px rgba(0,0,0,0.12);">
              <span>📌 ${node.titulo}</span>${node.nome_ocupante ? `<span style="font-weight:400; font-size:12px; margin-left:8px; opacity:0.85;">— ${node.nome_ocupante}</span>` : ""}
            </div>
            ${childrenHtml ? `<div style="border-left:3px solid ${bg}; margin-left:16px; padding-left:16px; margin-top:8px;">${childrenHtml}</div>` : ""}
          </div>`;
      }).join("");
    }

    // Build flat-to-tree structure
    function buildTree(flat: any[]): any[] {
      if (!flat || flat.length === 0) return [];
      const map = new Map<string, any>();
      const roots: any[] = [];
      flat.forEach((n: any) => map.set(n.id, { ...n, children: [] }));
      flat.forEach((n: any) => {
        const node = map.get(n.id)!;
        if (n.parent_id && map.has(n.parent_id)) {
          map.get(n.parent_id).children.push(node);
        } else {
          roots.push(node);
        }
      });
      return roots;
    }

    const orgTree = buildTree(organograma || []);
    const orgHtml = orgTree.length > 0 ? buildOrgHtml(orgTree) : "";
    const orgSection = orgHtml ? `
      <div style="margin: 40px 0; padding: 40px; background: #f8f9fa; border-radius: 16px;">
        <div style="background: linear-gradient(135deg, #1e3a5f, #2d8a6e); color: #fff; padding: 24px 32px; border-radius: 12px; margin-bottom: 32px;">
          <h2 style="margin:0; font-size:28px; font-weight:700;">🏢 Estrutura Organizacional</h2>
          <p style="margin:8px 0 0; font-size:15px; opacity:0.85;">Hierarquia e responsabilidades da equipe</p>
        </div>
        <div style="padding: 8px 0;">
          ${orgHtml}
        </div>
      </div>` : "";

    if (!missao && !visao && valores?.length === 0 && principios?.length === 0) {
      return new Response(JSON.stringify({ error: "Preencha ao menos Missão, Visão ou Valores antes de gerar o manual." }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const prompt = `Você é um consultor sênior de cultura organizacional e employer branding. Com base nos dados culturais abaixo, gere um MANUAL DE CULTURA ORGANIZACIONAL completo, profissional e visualmente rico em HTML.

${companyContext}

DADOS DA ESTRATÉGIA:
- Nome da empresa: ${empresa_nome || "Nossa Empresa"}
- Missão: ${missao || "(não informada)"}
- Visão: ${visao || "(não informada)"}
- Valores: ${valores?.length > 0 ? valores.join(", ") : "(nenhum)"}
- Princípios Culturais: ${principios?.length > 0 ? principios.join(", ") : "(nenhum)"}
- Comportamentos Esperados: ${comportamentos_esperados?.length > 0 ? comportamentos_esperados.join(", ") : "(nenhum)"}
- Comportamentos Não Tolerados: ${comportamentos_nao_tolerados?.length > 0 ? comportamentos_nao_tolerados.join(", ") : "(nenhum)"}
- Propósito: ${proposito || "(não informado)"}
- Carta / Manifesto de boas-vindas (voz da liderança): ${carta_boas_vindas || "(não informada)"}
- Tom de voz e comunicação: ${tom_de_voz || "(não informado)"}
- Conduta e diversidade: ${codigo_conduta || "(não informado)"}
- Dress code: ${dress_code || "(não informado)"}
- Modelo de trabalho (presencial/híbrido/remoto, horários): ${modelo_trabalho || "(não informado)"}
- Documentos que compõem a cultura (anexados pela empresa): ${documentos_cultura?.length > 0 ? documentos_cultura.join(", ") : "(nenhum)"}

INSTRUÇÕES OBRIGATÓRIAS PARA O MANUAL:

1. O manual DEVE ter no mínimo 8 seções completas e detalhadas:
   - Capa com nome da empresa e título "Manual de Cultura Organizacional"
   - Mensagem de Boas-Vindas (2-3 parágrafos inspiradores). Se houver "Carta / Manifesto de boas-vindas", use-a como base desta seção, preservando o tom da liderança
   - Nosso Propósito (quando informado, seção própria explicando por que a empresa existe além do lucro e o impacto que quer gerar; integre com a Missão)
   - Nossa Missão (explicação expandida com contexto e significado prático)
   - Nossa Visão de Futuro (detalhamento da visão com metas aspiracionais)
   - Nossos Valores (cada valor com título, descrição detalhada de 3-4 linhas e um exemplo prático de como vivenciá-lo no dia a dia)
   - Princípios Culturais (cada princípio com explicação aprofundada e diretrizes de aplicação)
   - Comportamentos Esperados (cada comportamento detalhado com cenários práticos e exemplos do que FAZER)
   - Comportamentos Não Tolerados (cada comportamento com explicação do impacto negativo e exemplos do que NÃO fazer)
   - Conduta e Diversidade (quando informado, seção sobre respeito, inclusão e como as pessoas devem se tratar)
   - Como Nos Comunicamos (quando houver "Tom de voz e comunicação", seção descrevendo o jeito da empresa de se comunicar)
   - Como Trabalhamos (quando houver "Dress code" e/ou "Modelo de trabalho", seção prática sobre vestimenta, presencial/híbrido/remoto, horários e flexibilidade)
   - Como Vivemos Nossa Cultura (seção integradora com dicas práticas para o dia a dia)
   - Documentos Complementares (quando houver documentos anexados, cite-os como leitura de referência que faz parte da cultura — ex.: Código de Ética e Conduta, Regulamento Interno)
   - Compromisso Coletivo (encerramento motivacional)

   IMPORTANTE: só inclua as seções acima cujos dados foram informados. Nunca invente conteúdo para um campo marcado como "(não informado)" — simplesmente omita a seção correspondente.

2. FORMATAÇÃO HTML OBRIGATÓRIA:
   - Use CSS inline em cada elemento
   - Use a paleta de cores: primário #1e3a5f (azul escuro), secundário #2d8a6e (verde), accent #f4a261 (laranja), fundo #f8f9fa, texto #1a1a2e
   - Fonte: font-family: 'Segoe UI', 'Inter', system-ui, sans-serif
   - Cada seção deve ter um cabeçalho com fundo colorido, ícone emoji e título grande
   - Use cards com border-radius: 12px, box-shadow e padding generoso (24px+)
   - Use ícones emoji relevantes para cada seção (🎯 🚀 💎 🌟 ✅ 🚫 🤝 📌)
   - Use listas estilizadas com marcadores coloridos customizados
   - Use divisores visuais entre seções
   - A capa deve ser full-width com gradient de fundo
   - Cada valor/princípio deve estar em um card individual com borda lateral colorida
   - Use alternância de cores de fundo nas seções (branco e cinza claro)
   - Tamanho mínimo de fonte: 15px para corpo, 28px para títulos de seção, 42px para capa
   - Espaçamento generoso: margin entre seções de 40px+, padding interno de 32px+

3. O HTML deve ser SELF-CONTAINED (sem referências externas) e pronto para impressão com @media print
4. O documento deve ter aspecto de um manual corporativo premium, não um documento simples
5. Cada seção deve ter conteúdo SUBSTANCIAL — nunca menos de 3 parágrafos ou 5 itens detalhados
6. Para valores e princípios, EXPANDA cada item com contexto real e exemplos práticos mesmo que o usuário tenha dado apenas o título
7. Adicione uma barra lateral colorida (4px) à esquerda de cada card de valor/princípio
8. Use gradients sutis nos headers de seção
9. Adicione números de página no rodapé e data de geração

Retorne APENAS o HTML completo sem explicações, markdown ou code blocks. O HTML deve começar com <!DOCTYPE html>.`;

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
        messages: [
          { role: "system", content: "Você é um designer e consultor de cultura organizacional. Gere apenas HTML completo e profissional. Nunca inclua markdown, code blocks ou explicações — apenas o HTML puro." },
          { role: "user", content: prompt }
        ],
      }),
    });

    if (!response.ok) {
      if (response.status === 429) {
        return new Response(JSON.stringify({ error: "Limite de requisições excedido. Tente novamente em alguns minutos." }), {
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
    let html = data.choices?.[0]?.message?.content?.trim() || "";

    // Clean up markdown code blocks if present
    if (html.startsWith("```")) {
      html = html.replace(/^```html?\n?/, "").replace(/\n?```$/, "");
    }

    // Inject the org chart section before </body> if it exists, otherwise append
    if (orgSection) {
      if (html.includes("</body>")) {
        html = html.replace("</body>", `${orgSection}</body>`);
      } else {
        html = html + orgSection;
      }
    }

    return new Response(JSON.stringify({ html }), {
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
