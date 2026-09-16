// Supabase Edge Function: ai-marketye
// IA do MarketYE (seção 21): gera anúncio a partir de poucos campos, sugere
// faixa de preço por categoria×região, interpreta busca em linguagem natural,
// rascunha resposta a lead e resume conversas/avaliações. Saída estruturada
// via tool-calling (mesmo padrão de ai-plano-acao). Sem dado pessoal de
// cliente no prompt além do que o próprio usuário digitou.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

type Tipo = "gerar_anuncio" | "sugerir_preco" | "interpretar_busca" | "rascunho_resposta" | "resumo_avaliacoes" | "sugerir_parametros" | "gerar_bio";

const SISTEMA = `Você é a IA do MarketYE, marketplace de serviços para empresas da plataforma YourEyes, no Brasil. Cabe qualquer serviço prestado a empresas: SST, saúde ocupacional, RH, jurídico, contábil, treinamentos, palestras, consultoria, tecnologia, manutenção, bem-estar e outros.
Regras invioláveis: escreva em português do Brasil; nunca invente registros profissionais, números de telefone, e-mails ou links; nunca inclua contato direto em textos de anúncio (o contato acontece pela plataforma); não prometa "qualidade garantida" nem fale em nome do YourEyes como prestador; o preço é sempre uma sugestão — quem define é o profissional; use linguagem não disciplinar (nada de punição, sanção, infração, demoção).`;

function ferramenta(tipo: Tipo) {
  switch (tipo) {
    case "gerar_anuncio":
      return {
        name: "registrar_anuncio",
        description: "Devolve o anúncio estruturado",
        parameters: {
          type: "object",
          properties: {
            titulo: { type: "string", description: "Título curto e específico (até 80 caracteres)" },
            descricao: { type: "string", description: "Descrição de 400 a 900 caracteres: o que entrega, para quem, como funciona, o que a empresa recebe (evidências/documentos), sem contato direto" },
            tags: { type: "array", items: { type: "string" }, description: "5 a 8 tags curtas" },
            categoria_slug: { type: "string", description: "slug da categoria mais adequada, escolhido da lista fornecida" },
            base_legal: { type: "string", description: "norma principal atendida (ex.: NR-1), se houver" },
            publico_alvo: { type: "string" },
            tipo_preco: { type: "string", enum: ["hora", "visita", "pacote", "mensal", "sob_orcamento"] },
            preco_sugerido: { type: "number", description: "valor-base sugerido em BRL, coerente com a categoria e a região" },
            preco_minimo: { type: "number" },
            preco_maximo: { type: "number" },
            justificativa_preco: { type: "string", description: "uma frase explicando a faixa; deixe claro que é sugestão" },
          },
          required: ["titulo", "descricao", "tags", "tipo_preco", "justificativa_preco"],
        },
      };
    case "sugerir_preco":
      return { name: "registrar_preco", description: "Faixa de preço sugerida", parameters: { type: "object", properties: { tipo_preco: { type: "string" }, preco_sugerido: { type: "number" }, preco_minimo: { type: "number" }, preco_maximo: { type: "number" }, justificativa_preco: { type: "string" } }, required: ["preco_sugerido", "justificativa_preco"] } };
    case "interpretar_busca":
      return {
        name: "registrar_filtros",
        description: "Filtros extraídos do pedido em linguagem natural",
        parameters: {
          type: "object",
          properties: {
            categoria_slug: { type: "string", description: "slug da categoria da lista, ou vazio" },
            termos: { type: "string", description: "1 a 3 palavras-chave para busca textual" },
            modalidade: { type: "string", enum: ["presencial", "online", "hibrido", ""] },
            uf: { type: "string", description: "sigla da UF se citada" },
            cidade: { type: "string" },
            somente_remoto: { type: "boolean" },
            obrigacoes: { type: "array", items: { type: "string" }, description: "normas citadas ou implícitas, ex.: NR-1, NR-7" },
          },
          required: ["termos"],
        },
      };
    case "rascunho_resposta":
      return { name: "registrar_resposta", description: "Rascunho de resposta do especialista", parameters: { type: "object", properties: { resposta: { type: "string", description: "resposta cordial e objetiva, com perguntas de escopo, prazo típico e próximos passos; sem telefone/e-mail" } }, required: ["resposta"] } };
    case "resumo_avaliacoes":
      return { name: "registrar_resumo", description: "Resumo em prós/contras", parameters: { type: "object", properties: { resumo: { type: "string", description: "texto curto com pontos fortes, ressalvas e o que falta combinar" } }, required: ["resumo"] } };
    case "sugerir_parametros":
      return {
        name: "registrar_pesos",
        description: "Pesos da ordenação da vitrine (somam 100) e explicação simples",
        parameters: {
          type: "object",
          properties: {
            pesos: { type: "object", properties: { fit: { type: "number" }, reputacao: { type: "number" }, saude: { type: "number" }, proximidade: { type: "number" }, exploracao: { type: "number" }, preco: { type: "number" }, destaque: { type: "number" } }, required: ["fit", "reputacao", "saude", "proximidade", "exploracao", "preco", "destaque"] },
            explicacao: { type: "string", description: "2 a 3 frases, em linguagem simples, dizendo o que muda na vitrine com esses pesos" },
          },
          required: ["pesos", "explicacao"],
        },
      };
    case "gerar_bio":
      return {
        name: "registrar_bio",
        description: "Apresentação do especialista e palavras-chave",
        parameters: {
          type: "object",
          properties: {
            bio: { type: "string", description: "apresentação em primeira pessoa, 300 a 600 caracteres, sem contato direto, sem promessas de garantia" },
            especialidades: { type: "array", items: { type: "string" }, description: "3 a 6 especialidades curtas" },
            categoria_slug: { type: "string", description: "slug da área mais próxima na lista, ou vazio" },
          },
          required: ["bio", "especialidades"],
        },
      };
  }
}

function prompt(tipo: Tipo, d: Record<string, unknown>): string {
  const cats = Array.isArray(d.categorias) ? (d.categorias as { slug: string; nome: string; obrigacao_legal?: string[] }[]).map((c) => `${c.slug} = ${c.nome}${c.obrigacao_legal?.length ? ` (${c.obrigacao_legal.join(", ")})` : ""}`).join("\n") : "";
  switch (tipo) {
    case "gerar_anuncio":
      return `Crie um anúncio de serviço a partir destes dados do profissional:
O QUE FAZ: ${d.o_que_faz ?? ""}
CATEGORIA ESCOLHIDA: ${d.categoria ?? "não informada"}
CONSELHO/REGISTRO: ${d.conselho ?? "não informado"}
REGIÃO: ${[d.cidade, d.uf].filter(Boolean).join("/") || "não informada"}
MODALIDADE: ${d.modalidade ?? "presencial"}
CATEGORIAS DISPONÍVEIS (slug = nome):
${cats}
Sugira também uma faixa de preço realista para o mercado brasileiro dessa categoria e região (valores de referência de 2026), deixando claro que é sugestão.`;
    case "sugerir_preco":
      return `Sugira faixa de preço (BRL, 2026) para: ${d.servico ?? ""}; categoria ${d.categoria ?? ""}; região ${[d.cidade, d.uf].filter(Boolean).join("/")}; modalidade ${d.modalidade ?? ""}.`;
    case "interpretar_busca":
      return `Uma empresa cliente digitou este pedido na vitrine: "${d.texto ?? ""}".
Traduza em filtros. CATEGORIAS DISPONÍVEIS (slug = nome (normas)):
${cats}`;
    case "rascunho_resposta":
      return `Você escreve EM NOME DO ESPECIALISTA. Serviço: ${d.servico ?? "não informado"}. Obrigação legal citada: ${d.obrigacao ?? "nenhuma"}.
CONVERSA ATÉ AQUI (autor: texto):
${d.conversa ?? ""}
Escreva a próxima mensagem do especialista.`;
    case "resumo_avaliacoes":
      return `${d.contexto ?? "Resuma em prós e contras."}
CONTEÚDO:
${d.conversa ?? d.avaliacoes ?? ""}`;
    case "sugerir_parametros":
      return `A equipe do YourEyes quer ajustar como a vitrine ordena os especialistas. Objetivo dito por ela: "${d.objetivo ?? ""}".
Os sete pesos são: fit (encaixe com a obrigação legal que a empresa precisa cumprir), reputacao (avaliações e nível), saude (atendimento recente: responde rápido, não cancela), proximidade (perto da empresa ou atende remoto), exploracao (chance para quem é novo), preco (preço e promoções), destaque (destaque pago, sempre rotulado, no máximo 10).
Pesos atuais: ${JSON.stringify(d.pesos_atuais ?? {})}. Devolva pesos inteiros que somem 100, mantendo destaque <= 10 e exploracao >= 5, e explique em linguagem simples.`;
    case "gerar_bio":
      return `Escreva a apresentação pública de um prestador de serviços para empresas, a partir do que ele contou:
O QUE FAZ: ${d.o_que_faz ?? ""}
ÁREA (se escolhida): ${d.area ?? "não informada"}
REGISTRO PROFISSIONAL: ${d.registro ?? "não informado"}
REGIÃO: ${[d.cidade, d.uf].filter(Boolean).join("/") || "não informada"}
ÁREAS DISPONÍVEIS (slug = nome):
${cats}
Tom: direto, confiável, sem jargão. Sem telefone, e-mail ou link.`;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  try {
    const apiKey = Deno.env.get("OPENAI_API_KEY");
    if (!apiKey) {
      // Segredo do projeto (Project Settings > Edge Functions > Secrets), não
      // copiado entre ambientes. Sem ele a IA não roda, mas a tela segue útil:
      // a mensagem diz o que falta e que dá para preencher à mão.
      return json({ error: "A IA não está configurada neste ambiente (falta o segredo OPENAI_API_KEY nas Edge Functions do projeto). Dá para preencher o anúncio à mão no passo 2." }, 503);
    }
    const body = await req.json();
    const tipo = body?.tipo as Tipo;
    const dados = (body?.dados ?? {}) as Record<string, unknown>;
    const tool = ferramenta(tipo);
    if (!tool) return json({ error: "Tipo inválido" }, 400);

    const resp = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        temperature: tipo === "interpretar_busca" ? 0.1 : 0.6,
        messages: [{ role: "system", content: SISTEMA }, { role: "user", content: prompt(tipo, dados) }],
        tools: [{ type: "function", function: tool }],
        tool_choice: { type: "function", function: { name: tool.name } },
      }),
    });
    if (resp.status === 429) return json({ error: "A IA está ocupada agora. Tente de novo em instantes." }, 429);
    if (!resp.ok) throw new Error(`OpenAI ${resp.status}: ${await resp.text()}`);
    const data = await resp.json();
    const args = data?.choices?.[0]?.message?.tool_calls?.[0]?.function?.arguments;
    if (!args) throw new Error("A IA não devolveu resultado estruturado");
    const resultado = JSON.parse(args);
    // Cinto de segurança: nada de contato direto em texto gerado.
    for (const k of ["descricao", "resposta", "titulo", "bio"]) {
      if (typeof resultado[k] === "string") {
        resultado[k] = resultado[k]
          .replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, "[contato pela plataforma]")
          .replace(/(https?:\/\/|www\.)[^\s]+/g, "[link removido]")
          .replace(/(\(?\d{2}\)?[\s.-]?)?\d{4,5}[\s.-]?\d{4}/g, "[contato pela plataforma]");
      }
    }
    return json(resultado);
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Erro desconhecido" }, 500);
  }
});
